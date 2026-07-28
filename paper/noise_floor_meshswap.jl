#=
Shot-noise floor versus systematic floor at flat (production 11:1) aspect
ratio -- the flat-beam counterpart of Section 6.4 C of
docs/history/poisson_solver_review_2026_07_24.md (which is round-beam only).

Method (identical to the review, Section 6.1): per-point transverse-kick
error |K_num - K_exact| normalized by max|K_exact| over an 81x81 field grid
spanning +-4 sigma; median reported. Reference is the exact Bassetti-Erskine
kick (gaussian_beambeam_kick). Sources: deterministic 400x400 Gaussian
quantile lattice (systematic floor, no shot noise) and randomly sampled
Gaussians at 1e4 / 1e5 / 1e6 macroparticles.

Solvers, "as used" (no fitted constants), production-faithful moment usage
(sampled moments feed the soft-Gaussian solver and the hybrid's subtraction):
  - soft-Gaussian     : Bassetti-Erskine of the measured sample moments
  - PIC CIC 128^2     : integrated-log Green FFT (production config)
  - hybrid CIC 64^2   : erf-integrated Gaussian subtraction + BE add-back
  - spectral :grid    : round (127,127)/d16, flat (127,383)/d8 (recommended)

The round-beam case is run first as a correctness gate against the review's
recorded numbers; the flat case (sig_x/sig_y = 11) is the new result.

Run from this folder (CPU, ~2-4 min after compilation):

    julia --startup-file=no --project=/cfs/ad/dxu/Library/Julia/Octopus flat_beam_noise_floor.jl

Output: data/flat_beam_noise_floor.tsv plus a printed table.
=#

const OCTOPUS_ROOT = "/cfs/ad/dxu/Library/Julia/Octopus"

if !isdefined(Main, :Octopus)
    include(joinpath(OCTOPUS_ROOT, "src", "Octopus.jl"))
end
using .Octopus
const O = Octopus
using SpecialFunctions: erf, erfinv
using FFTW
using Random
using Statistics
using Printf

# --- node-centered erf Gaussian deposition profile ---------------------------
# (as in validation/gaussian_pic_field_validation.jl, docs Section 5)
gval(x, mu, s) = exp(-(x - mu)^2 / (2s^2)) / (s * sqrt(2pi))
m0(A, B, mu, s) = 0.5 * (erf((B - mu) / (s * sqrt(2))) - erf((A - mu) / (s * sqrt(2))))
function m1(A, B, mu, s, xi)
    d = mu - xi
    return d * m0(A, B, mu, s) - s^2 * (gval(B, mu, s) - gval(A, mu, s))
end
function m2(A, B, mu, s, xi)
    d = mu - xi
    return (s^2 + d^2) * m0(A, B, mu, s) -
           s^2 * ((B - mu) * gval(B, mu, s) - (A - mu) * gval(A, mu, s)) -
           2 * d * s^2 * (gval(B, mu, s) - gval(A, mu, s))
end
function gauss_profile(nodes, h, mu, s, method::Symbol)
    g = similar(nodes)
    for (k, xi) in pairs(nodes)
        if method === :CIC
            g[k] = m0(xi - h, xi + h, mu, s) +
                   (m1(xi - h, xi, mu, s, xi) - m1(xi, xi + h, mu, s, xi)) / h
        else
            Lw = (xi - 1.5h, xi - 0.5h); C = (xi - 0.5h, xi + 0.5h); Rw = (xi + 0.5h, xi + 1.5h)
            g[k] = 0.75 * m0(C..., mu, s) - m2(C..., mu, s, xi) / h^2 +
                   1.125 * (m0(Lw..., mu, s) + m0(Rw..., mu, s)) +
                   1.5 * (m1(Lw..., mu, s, xi) - m1(Rw..., mu, s, xi)) / h +
                   0.5 * (m2(Lw..., mu, s, xi) + m2(Rw..., mu, s, xi)) / h^2
        end
    end
    return g
end

# --- sources ------------------------------------------------------------------
function quantile_grid(sigx, sigy, n)
    u = ((1:n) .- 0.5) ./ n
    q = sqrt(2.0) .* erfinv.(2.0 .* u .- 1.0)
    x = Vector{Float64}(undef, n * n); y = similar(x)
    k = 1
    for yy in q, xx in q
        x[k] = sigx * xx; y[k] = sigy * yy; k += 1
    end
    return x, y
end

sample_moments(v) = (m = mean(v); (m, sqrt(mean(abs2, v .- m))))

# --- solver field evaluations ---------------------------------------------------
function solve_from_charge(solver, charge, source_grid, field_grid, nx, ny)
    green_fft = O._pic_green_fft(solver, Float64, source_grid, field_grid)
    sp = Complex{Float64}.(charge)
    fft!(sp); sp .*= green_fft; ifft!(sp)
    phi = real.(sp[1:nx, 1:ny])
    hx = source_grid.width / (nx - 1); hy = source_grid.height / (ny - 1)
    Ex, Ey = O._pic_field(phi, hx, hy)
    return phi, Ex, Ey
end

# PIC on its production path (grids, deposit, Green FFT, interpolation).
function pic_kicks(sx, sy, xf, yf; grid, method)
    solver = PICPoissonSolver(; grid = (grid, grid), deposit_method = method,
                              green_type = :integrated)
    sgrid, fgrid = O._pic_interaction_grids(solver,
        minimum(sx), maximum(sx), minimum(sy), maximum(sy),
        min(minimum(xf), minimum(sx)), max(maximum(xf), maximum(sx)),
        min(minimum(yf), minimum(sy)), max(maximum(yf), maximum(sy)))
    phi, Ex, Ey = O._pic_solve_field(solver, sx, sy, sgrid, fgrid)
    ns = length(sx)
    kx = Vector{Float64}(undef, length(xf)); ky = similar(kx)
    for k in eachindex(xf)
        ex, ey, _ = O._pic_interpolate_kick(solver, fgrid, xf[k], yf[k],
                                            phi, Ex, Ey, phi, Ex, Ey, 1.0, 0.0)
        kx[k] = 2ex / ns; ky[k] = 2ey / ns
    end
    return kx, ky
end

# Gaussian-subtracted hybrid: deposit, subtract the erf-integrated reference
# Gaussian of the MEASURED moments, residual Green-FFT solve, add back the
# exact BE kick of those measured moments (production-faithful control variate).
function hybrid_kicks(sx, sy, xf, yf, mux, sigxm, muy, sigym; grid, method,
                      margin_sigma = 5.0)
    solver = PICPoissonSolver(; grid = (grid, grid), deposit_method = method,
                              green_type = :integrated)
    nx = ny = grid
    ns = length(sx)
    # Pad the source grid to +-margin_sigma so the erf-integrated reference
    # Gaussian is not truncated (as in validation/gaussian_pic_field_validation.jl).
    sxmin = min(minimum(sx), mux - margin_sigma * sigxm)
    sxmax = max(maximum(sx), mux + margin_sigma * sigxm)
    symin = min(minimum(sy), muy - margin_sigma * sigym)
    symax = max(maximum(sy), muy + margin_sigma * sigym)
    sgrid, fgrid = O._pic_interaction_grids(solver,
        sxmin, sxmax, symin, symax,
        min(minimum(xf), sxmin), max(maximum(xf), sxmax),
        min(minimum(yf), symin), max(maximum(yf), symax))
    hx = sgrid.width / (nx - 1); hy = sgrid.height / (ny - 1)
    Q = zeros(2nx, 2ny)
    O._pic_deposit!(Q, method, sx, sy, sgrid.x0, sgrid.y0, hx, hy, nx, ny)
    xn = [sgrid.x0 + (i - 1) * hx for i in 1:nx]
    yn = [sgrid.y0 + (j - 1) * hy for j in 1:ny]
    gx = gauss_profile(xn, hx, mux, sigxm, method)
    gy = gauss_profile(yn, hy, muy, sigym, method)
    for j in 1:ny, i in 1:nx
        Q[i, j] -= ns * gx[i] * gy[j]
    end
    phi, Ex, Ey = solve_from_charge(solver, Q, sgrid, fgrid, nx, ny)
    kx = Vector{Float64}(undef, length(xf)); ky = similar(kx)
    for k in eachindex(xf)
        ex, ey, _ = O._pic_interpolate_kick(solver, fgrid, xf[k], yf[k],
                                            phi, Ex, Ey, phi, Ex, Ey, 1.0, 0.0)
        bkx, bky = gaussian_beambeam_kick(sigxm, sigym, xf[k] - mux, yf[k] - muy)
        kx[k] = 2ex / ns + bkx; ky[k] = 2ey / ns + bky
    end
    return kx, ky
end

# Spectral sine-series :grid path, production box rule (square, sized to the
# larger rms; _spectral_field_grid output is already in the BE convention).
function spectral_kicks(sx, sy, xf, yf; N, dfac)
    smax = max(sqrt(mean(abs2, sx .- mean(sx))), sqrt(mean(abs2, sy .- mean(sy))))
    emax = max(maximum(abs, sx), maximum(abs, sy),
               maximum(abs, xf), maximum(abs, yf))
    L = max(dfac * smax, 1.05 * emax)
    Ex, Ey = O._spectral_field_grid(sx, sy, xf, yf, L, L, N[1], N[2])
    return Ex, Ey
end

# --- one case: medians of the four solvers -------------------------------------
function case_medians(sx, sy, xf, yf, kex, key, gnorm;
                      picgrid, hybgrid, spN, spdfac)
    mux, sigxm = sample_moments(sx)
    muy, sigym = sample_moments(sy)
    med(kx, ky) = median([hypot(kx[k] - kex[k], ky[k] - key[k])
                          for k in eachindex(kx)]) / gnorm
    # soft-Gaussian: BE of the measured moments
    gkx = similar(kex); gky = similar(key)
    for k in eachindex(xf)
        gkx[k], gky[k] = gaussian_beambeam_kick(sigxm, sigym,
                                                xf[k] - mux, yf[k] - muy)
    end
    m_gauss = med(gkx, gky)
    m_pic = med(pic_kicks(sx, sy, xf, yf; grid = picgrid, method = :CIC)...)
    m_hyb = med(hybrid_kicks(sx, sy, xf, yf, mux, sigxm, muy, sigym;
                             grid = hybgrid, method = :CIC)...)
    m_spec = med(spectral_kicks(sx, sy, xf, yf; N = spN, dfac = spdfac)...)
    return (m_gauss, m_pic, m_hyb, m_spec)
end

function run_family(name, sigx, sigy; picgrid, hybgrid, spN, spdfac, seed, io)
    println("\n== $(name):  sigx/sigy = $(round(sigx / sigy; sigdigits=4)), ",
            "PIC $(picgrid)^2, hybrid $(hybgrid)^2, spectral $(spN)/d$(Int(spdfac)) ==")
    println(io, "# family=$(name) sigx=$(sigx) sigy=$(sigy) picgrid=$(picgrid) ",
                "hybgrid=$(hybgrid) spectral=$(spN) domain_factor=$(spdfac) seed=$(seed)")
    @printf("%-14s  %10s  %10s  %10s  %10s\n",
            "n_macro", "soft-G", "PIC", "hybrid", "spectral")
    xg = collect(range(-4sigx, 4sigx; length = 81))
    yg = collect(range(-4sigy, 4sigy; length = 81))
    xf = Float64[]; yf = Float64[]
    for Y in yg, X in xg
        push!(xf, X); push!(yf, Y)
    end
    kex = similar(xf); key = similar(yf)
    for k in eachindex(xf)
        kex[k], key[k] = gaussian_beambeam_kick(sigx, sigy, xf[k], yf[k])
    end
    gnorm = maximum(hypot.(kex, key))
    # The random-source error is dominated by a few low-order moment
    # fluctuations of the draw, so a single draw scatters strongly; report the
    # median over independent draws of the per-draw median.
    rng = MersenneTwister(seed)
    for (n, ndraws) in ((10_000, 5), (100_000, 5), (1_000_000, 3))
        meds = [Float64[], Float64[], Float64[], Float64[]]
        for _ in 1:ndraws
            sx = sigx .* randn(rng, n); sy = sigy .* randn(rng, n)
            m = case_medians(sx, sy, xf, yf, kex, key, gnorm;
                             picgrid, hybgrid, spN, spdfac)
            push!.(meds, m)
        end
        m = median.(meds)
        line = @sprintf("%-14s  %10.2e  %10.2e  %10.2e  %10.2e",
                        @sprintf("%.0e x%d", n, ndraws), m...)
        println(line)
        println(io, @sprintf("%.0e", n), "\t", join(m, '\t'))
    end
    sx, sy = quantile_grid(sigx, sigy, 400)
    m = case_medians(sx, sy, xf, yf, kex, key, gnorm;
                     picgrid, hybgrid, spN, spdfac)
    println(@sprintf("%-14s  %10.2e  %10.2e  %10.2e  %10.2e",
                     "deterministic", m...))
    println(io, "deterministic\t", join(m, '\t'))
    return nothing
end


out = "/home/cfsd/dxu/.claude/jobs/a218e0b7/tmp/noise_floor_meshswap.tsv"
open(out, "w") do io
    println(io, "# Median |K_num - K_exact| / max|K_exact|, 81x81 field grid +-4 sigma")
    println(io, "family_case\tsoft_gaussian\tpic\thybrid\tspectral")
    # correctness gate: reproduce the review's round-beam Section 6.4 C
    run_family("round (gate)", 2.0e-3, 2.0e-3;
               picgrid = 64, hybgrid = 128, spN = (127, 127), spdfac = 16.0,
               seed = 20260727, io)
    # the new result: flat 11:1 (production electron aspect ratio)
    run_family("flat 11:1", 2.0e-3, 2.0e-3 / 11;
               picgrid = 64, hybgrid = 128, spN = (127, 383), spdfac = 8.0,
               seed = 20260727, io)
end
println("\nwrote $(out)")
println("review round-beam reference (6.4 C): soft-G 2.2e-3/9.3e-4/3.5e-4/6.3e-5,")
println("PIC128 3.8e-3/1.2e-3/4.8e-4/4.1e-4, hyb64 3.6e-3/1.1e-3/4.5e-4/1.6e-4,")
println("spectral 3.7e-3/1.6e-3/1.2e-3/1.2e-3 (rows 1e4/1e5/1e6/deterministic)")
