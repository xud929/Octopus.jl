#=
Validate the spectral sine-series 2D Poisson field solver (see
docs/spectral_sine_poisson_solver.md) against the exact Bassetti-Erskine
Gaussian kick, and characterize how accuracy scales with the number of modes /
grid resolution and the rectangular domain size.

Reference model: `gaussian_beambeam_kick` (exact 2D Gaussian field). Source is a
deterministic equal-probability Gaussian quantile grid. Error metric per case is
the field-shape residual after least-squares calibration of the overall
constant, normalized by the maximum exact kick norm on the field grid:

    c        = argmin_c || c*E_spectral - K_exact ||^2
    rel(x,y) = |c*E_spectral - K_exact| / max_grid |K_exact|

The same least-squares calibration is applied to the PIC solver so the two are
compared purely on field shape (the physical coupling constant kbb is applied
separately in production and is not part of this shape test).

Run from the project root:

    julia --project=. validation/spectral_poisson_field_validation.jl

Two solver variants are implemented:

- grid-free: mode coefficients formed directly from particle positions
  (`rho_lm = (4/ab) sum_p sin(alpha_l x_p) sin(beta_m y_p)`); cost O(Np*L*M) for
  deposition and O(Nf*L*M) for evaluation. Uses the exact analytic derivative.
- grid (DST): particles deposited by CIC onto an Nx x Ny mesh, solved by a 2D
  type-I discrete sine transform, differentiated by finite differences; cost
  O(Np) + O(Nx*Ny*log) + O(Nf). This is the practical variant.

Outputs `result/spectral_poisson_field_validation.tsv`.
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus
using SpecialFunctions, Statistics, FFTW, Printf
const O = Octopus

# ---------------------------------------------------------------- source
function gaussian_quantile_grid(sigx, sigy, n)
    u = ((1:n) .- 0.5) ./ n
    q = sqrt(2.0) .* erfinv.(2.0 .* u .- 1.0)
    x = Float64[]; y = Float64[]
    for yy in q, xx in q
        push!(x, sigx * xx); push!(y, sigy * yy)
    end
    return x, y
end

# ---------------------------------------------------------------- grid-free spectral
# Domain is [-Lx,Lx] x [-Ly,Ly] centered on the beam; the sine basis lives on
# [0,2Lx] x [0,2Ly] after shifting. Uses the exact analytic field derivative.
function spectral_free_field(xp, yp, Lx, Ly, L, M, xf, yf)
    a = 2Lx; b = 2Ly; np = length(xp)
    al = [l * pi / a for l in 1:L]; bm = [m * pi / b for m in 1:M]
    sX = Matrix{Float64}(undef, L, np); sY = Matrix{Float64}(undef, M, np)
    @inbounds for p in 1:np
        xs = xp[p] + Lx; ys = yp[p] + Ly
        for l in 1:L; sX[l, p] = sin(al[l] * xs); end
        for m in 1:M; sY[m, p] = sin(bm[m] * ys); end
    end
    phi = Matrix{Float64}(undef, L, M)
    @inbounds for l in 1:L, m in 1:M
        s = 0.0
        for p in 1:np; s += sX[l, p] * sY[m, p]; end
        phi[l, m] = -(4 / (a * b)) * s / (al[l]^2 + bm[m]^2)   # kbb = 1
    end
    nf = length(xf); Ex = Vector{Float64}(undef, nf); Ey = Vector{Float64}(undef, nf)
    @inbounds for k in 1:nf
        X = xf[k] + Lx; Y = yf[k] + Ly; ex = 0.0; ey = 0.0
        for l in 1:L
            cX = cos(al[l] * X); sXk = sin(al[l] * X)
            for m in 1:M
                ex += phi[l, m] * al[l] * cX * sin(bm[m] * Y)
                ey += phi[l, m] * bm[m] * sXk * cos(bm[m] * Y)
            end
        end
        Ex[k] = -ex; Ey[k] = -ey
    end
    return Ex, Ey
end

# ---------------------------------------------------------------- grid (DST) spectral
# Anisotropic mesh Nx x Ny lets flat beams resolve the thin direction.
function spectral_grid_field(xp, yp, Lx, Ly, Nx, Ny, xf, yf)
    a = 2Lx; b = 2Ly; np = length(xp); hx = a / (Nx + 1); hy = b / (Ny + 1)
    rho = zeros(Nx, Ny)
    @inbounds for p in 1:np
        X = (xp[p] + Lx) / hx; Y = (yp[p] + Ly) / hy
        i = floor(Int, X); j = floor(Int, Y); fx = X - i; fy = Y - j
        for (ii, wx) in ((i, 1 - fx), (i + 1, fx)), (jj, wy) in ((j, 1 - fy), (j + 1, fy))
            (1 <= ii <= Nx && 1 <= jj <= Ny) && (rho[ii, jj] += wx * wy)
        end
    end
    al = [l * pi / a for l in 1:Nx]; bm = [m * pi / b for m in 1:Ny]
    rhat = FFTW.r2r(rho, FFTW.RODFT00)
    phat = [-rhat[l, m] / (al[l]^2 + bm[m]^2) for l in 1:Nx, m in 1:Ny]
    phi = FFTW.r2r(phat, FFTW.RODFT00) ./ (2 * (Nx + 1) * 2 * (Ny + 1))
    Exg = zeros(Nx, Ny); Eyg = zeros(Nx, Ny)
    @inbounds for i in 1:Nx, j in 1:Ny
        xm = i > 1 ? phi[i - 1, j] : 0.0; xpp = i < Nx ? phi[i + 1, j] : 0.0
        ym = j > 1 ? phi[i, j - 1] : 0.0; ypp = j < Ny ? phi[i, j + 1] : 0.0
        Exg[i, j] = -(xpp - xm) / (2hx); Eyg[i, j] = -(ypp - ym) / (2hy)
    end
    interp(F, X, Y) = begin
        xi = (X + Lx) / hx; yj = (Y + Ly) / hy; i = floor(Int, xi); j = floor(Int, yj)
        fx = xi - i; fy = yj - j; v = 0.0
        for (ii, wx) in ((i, 1 - fx), (i + 1, fx)), (jj, wy) in ((j, 1 - fy), (j + 1, fy))
            (1 <= ii <= Nx && 1 <= jj <= Ny) && (v += wx * wy * F[ii, jj])
        end
        v
    end
    Ex = [interp(Exg, xf[k], yf[k]) for k in eachindex(xf)]
    Ey = [interp(Eyg, xf[k], yf[k]) for k in eachindex(yf)]
    return Ex, Ey
end

# ---------------------------------------------------------------- hybrid: DST deposit + exact spectral derivative
# Fast DST deposition for the mode coefficients, then the exact analytic field
# derivative (cosine in the differentiated axis) evaluated at the field points.
# This removes both the O(Np L M) direct deposition and the finite-difference
# field error, and is the accuracy-competitive variant.
function spectral_specderiv_field(xp, yp, Lx, Ly, Nx, Ny, xf, yf)
    a = 2Lx; b = 2Ly; hx = a / (Nx + 1); hy = b / (Ny + 1)
    rho = zeros(Nx, Ny)
    @inbounds for p in eachindex(xp)
        X = (xp[p] + Lx) / hx; Y = (yp[p] + Ly) / hy
        i = floor(Int, X); j = floor(Int, Y); fx = X - i; fy = Y - j
        for (ii, wx) in ((i, 1 - fx), (i + 1, fx)), (jj, wy) in ((j, 1 - fy), (j + 1, fy))
            (1 <= ii <= Nx && 1 <= jj <= Ny) && (rho[ii, jj] += wx * wy)
        end
    end
    al = [l * pi / a for l in 1:Nx]; bm = [m * pi / b for m in 1:Ny]
    rhat = FFTW.r2r(rho, FFTW.RODFT00)
    phat = [-rhat[l, m] / (al[l]^2 + bm[m]^2) for l in 1:Nx, m in 1:Ny]
    nrm = (Nx + 1) * (Ny + 1)                              # phi_lm = phat / nrm
    nf = length(xf); Ex = zeros(nf); Ey = zeros(nf)
    @inbounds for k in 1:nf
        X = xf[k] + Lx; Y = yf[k] + Ly; ex = 0.0; ey = 0.0
        for l in 1:Nx
            cX = cos(al[l] * X); sX = sin(al[l] * X)
            for m in 1:Ny
                pc = phat[l, m] / nrm
                ex += pc * al[l] * cX * sin(bm[m] * Y)
                ey += pc * bm[m] * sX * cos(bm[m] * Y)
            end
        end
        Ex[k] = -ex; Ey[k] = -ey
    end
    return Ex, Ey
end

# ---------------------------------------------------------------- PIC reference
function pic_field(sxv, syv, xf, yf, pg)
    solver = PICPoissonSolver(grid=(pg, pg), deposit_method=:TSC, green_type=:integrated)
    sgrid, fgrid = O._pic_interaction_grids(solver,
        minimum(sxv), maximum(sxv), minimum(syv), maximum(syv),
        minimum(xf), maximum(xf), minimum(yf), maximum(yf))
    phi, Ex, Ey = O._pic_solve_field(solver, sxv, syv, sgrid, fgrid)
    pex = Float64[]; pey = Float64[]
    for k in eachindex(xf)
        ex, ey, _ = O._pic_interpolate_kick(solver, fgrid, xf[k], yf[k], phi, Ex, Ey, phi, Ex, Ey, 1.0, 0.0)
        push!(pex, ex); push!(pey, ey)
    end
    return pex, pey
end

# ---------------------------------------------------------------- metric
function shape_relerr(Ex, Ey, Kx, Ky)
    c = (sum(Ex .* Kx) + sum(Ey .* Ky)) / (sum(Ex .^ 2) + sum(Ey .^ 2))
    resid = [hypot(c * Ex[k] - Kx[k], c * Ey[k] - Ky[k]) for k in eachindex(Ex)]
    Kn = [hypot(Kx[k], Ky[k]) for k in eachindex(Kx)]
    m = maximum(Kn)
    return (median(resid) / m, quantile(resid, 0.95) / m, maximum(resid) / m)
end

bench(f) = (f(); t = Inf; for _ in 1:3; t = min(t, @elapsed f()); end; t)

# ---------------------------------------------------------------- run
const NSRC = parse(Int, get(ENV, "OCTOPUS_SPECTRAL_NSRC", "100"))
const FA = parse(Int, get(ENV, "OCTOPUS_SPECTRAL_FIELD_AXIS", "41"))
result_dir = normpath(joinpath(@__DIR__, "..", "result"))
mkpath(result_dir)

cases = [(1.0, "round", 256), (5.0, "flat5", 256), (25.0, "flat25", 512)]
rows = String[]
push!(rows, "case\tratio\tmethod\tparams\tmedian_rel\tp95_rel\tmax_rel\tseconds")
println("case      ratio  method   params                 median      p95        max        seconds")
for (ratio, name, pg) in cases
    sx = 2.0e-3; sy = sx / ratio
    sxv, syv = gaussian_quantile_grid(sx, sy, NSRC)
    xg = collect(range(-4sx, 4sx, length=FA)); yg = collect(range(-4sy, 4sy, length=FA))
    xf = Float64[]; yf = Float64[]
    for Y in yg, X in xg; push!(xf, X); push!(yf, Y); end
    Kx = [first(gaussian_beambeam_kick(sx, sy, xf[k], yf[k])) for k in eachindex(xf)]
    Ky = [last(gaussian_beambeam_kick(sx, sy, xf[k], yf[k])) for k in eachindex(xf)]

    # Recommended settings: square domain sized to max(sx,sy); anisotropic grid
    # resolving the thin direction with Ny ~ 2*domsig*(sx/sy).
    smax = max(sx, sy); domsig = 16.0
    Lx = domsig * smax; Ly = domsig * smax
    Nx = 128; Ny = max(128, ceil(Int, 6 * domsig * (smax / min(sx, sy))))
    Ny = min(Ny, 1200)
    for (label, f) in (
            ("spectral-specderiv", () -> spectral_specderiv_field(sxv, syv, Lx, Ly, Nx, Ny, xf, yf)),
            ("spectral-grid-fd", () -> spectral_grid_field(sxv, syv, Lx, Ly, Nx, Ny, xf, yf)),
            ("spectral-free", () -> spectral_free_field(sxv, syv, Lx, Ly, 96, 96, xf, yf)),
            ("pic", () -> pic_field(sxv, syv, xf, yf, pg)))
        Ex, Ey = f()
        md, p95, mx = shape_relerr(Ex, Ey, Kx, Ky)
        t = bench(f)
        params = startswith(label, "spectral") ?
                 (label == "spectral-free" ? "d=16 L=M=96" : "d=16 Nx=$Nx Ny=$Ny") : "grid=$pg TSC"
        @printf("%-9s %5.0f  %-18s %-16s %.3e  %.3e  %.3e  %.4f\n", name, ratio, label, params, md, p95, mx, t)
        push!(rows, @sprintf("%s\t%.0f\t%s\t%s\t%.6e\t%.6e\t%.6e\t%.6f", name, ratio, label, params, md, p95, mx, t))
    end
end

# ---- scaling regression: domain size (round) and thin-grid (flat25) ----
println("\n# domain-size scaling (round, grid-free L=M=96), median rel error:")
let sx = 2.0e-3, sy = 2.0e-3
    sxv, syv = gaussian_quantile_grid(sx, sy, NSRC)
    xg = collect(range(-4sx, 4sx, length=FA)); yg = collect(range(-4sy, 4sy, length=FA))
    xf = Float64[]; yf = Float64[]; for Y in yg, X in xg; push!(xf, X); push!(yf, Y); end
    Kx = [first(gaussian_beambeam_kick(sx, sy, xf[k], yf[k])) for k in eachindex(xf)]
    Ky = [last(gaussian_beambeam_kick(sx, sy, xf[k], yf[k])) for k in eachindex(xf)]
    for domsig in (4.0, 6.0, 10.0, 16.0, 24.0)
        Ex, Ey = spectral_free_field(sxv, syv, domsig * sx, domsig * sy, 96, 96, xf, yf)
        md, p95, mx = shape_relerr(Ex, Ey, Kx, Ky)
        @printf("  domsig=%2.0f  median=%.3e  p95=%.3e  max=%.3e\n", domsig, md, p95, mx)
        push!(rows, @sprintf("round-domain\t1\tspectral-free\tdomsig=%.0f L=M=96\t%.6e\t%.6e\t%.6e\t-", domsig, md, p95, mx))
    end
end
println("\n# thin-direction grid scaling (flat25, domsig=8), median rel error:")
let sx = 2.0e-3, sy = 2.0e-3 / 25
    sxv, syv = gaussian_quantile_grid(sx, sy, NSRC)
    xg = collect(range(-4sx, 4sx, length=FA)); yg = collect(range(-4sy, 4sy, length=FA))
    xf = Float64[]; yf = Float64[]; for Y in yg, X in xg; push!(xf, X); push!(yf, Y); end
    Kx = [first(gaussian_beambeam_kick(sx, sy, xf[k], yf[k])) for k in eachindex(xf)]
    Ky = [last(gaussian_beambeam_kick(sx, sy, xf[k], yf[k])) for k in eachindex(xf)]
    for Ny in (128, 256, 512, 1024)
        Ex, Ey = spectral_grid_field(sxv, syv, 8sx, 8sx, 64, Ny, xf, yf)
        md, p95, mx = shape_relerr(Ex, Ey, Kx, Ky)
        @printf("  Ny=%4d (Ny/(2*domsig*ratio)=%.2f)  median=%.3e  p95=%.3e  max=%.3e\n",
                Ny, Ny / (2 * 8 * 25), md, p95, mx)
        push!(rows, @sprintf("flat25-thingrid\t25\tspectral-grid\tdomsig=8 Nx=64 Ny=%d\t%.6e\t%.6e\t%.6e\t-", Ny, md, p95, mx))
    end
end

summary_path = joinpath(result_dir, "spectral_poisson_field_validation.tsv")
open(summary_path, "w") do io
    for r in rows; println(io, r); end
end
println("\nsummary = ", summary_path)
