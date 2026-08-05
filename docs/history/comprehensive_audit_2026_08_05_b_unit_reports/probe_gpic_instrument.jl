#=
Instrument validation (audit protocol Phase 12) for
validation/gaussian_pic_field_validation.jl.

Replicates the script's `run_case` verbatim, then feeds the metric two known
defects:

  mode=:be   -- the Bassetti-Erskine evaluator itself is wrong by a factor
                (1+d). In the script the SAME call supplies both the reference
                `ekx` and the hybrid's analytic add-back, so this asks whether
                the hybrid column can see an error in its own reference.
  mode=:ref  -- only the comparison reference is wrong by (1+d) (the add-back
                keeps the true value). Both columns should move.

Run: julia --project=. probe_gpic_instrument.jl
=#
include(joinpath(@__DIR__, "repo", "src", "Octopus.jl"))
using .Octopus
const O = Octopus
using SpecialFunctions: erf, erfinv
using FFTW, Statistics, Printf

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
function quantile_grid(sigx, sigy, n)
    u = ((1:n) .- 0.5) ./ n
    q = sqrt(2.0) .* erfinv.(2.0 .* u .- 1.0)
    x = Float64[]; y = Float64[]
    for yy in q, xx in q
        push!(x, sigx * xx); push!(y, sigy * yy)
    end
    return x, y
end
function solve_from_charge(solver, charge, source_grid, field_grid, nx, ny)
    green_fft = O._pic_green_fft(solver, Float64, source_grid, field_grid)
    sp = Complex{Float64}.(charge)
    fft!(sp); sp .*= green_fft; ifft!(sp)
    phi = real.(sp[1:nx, 1:ny])
    hx = source_grid.width / (nx - 1); hy = source_grid.height / (ny - 1)
    Ex, Ey = O._pic_field(phi, hx, hy)
    return phi, Ex, Ey
end

function run_case(sigx, sigy; grid, method=:CIC, nsrc_axis=400, field_axis=81,
                  extent=4.0, margin_sigma=5.0, delta=0.0, mode=:none)
    solver = PICPoissonSolver(; grid=(grid, grid), deposit_method=method, green_type=:integrated)
    nx = ny = grid
    sx, sy = quantile_grid(sigx, sigy, nsrc_axis)
    ns = length(sx)
    xg = collect(range(-extent * sigx, extent * sigx; length=field_axis))
    yg = collect(range(-extent * sigy, extent * sigy; length=field_axis))
    sxmin = min(minimum(sx), -margin_sigma * sigx); sxmax = max(maximum(sx), margin_sigma * sigx)
    symin = min(minimum(sy), -margin_sigma * sigy); symax = max(maximum(sy), margin_sigma * sigy)
    source_grid, field_grid = O._pic_interaction_grids(solver, sxmin, sxmax, symin, symax,
        min(minimum(xg), sxmin), max(maximum(xg), sxmax),
        min(minimum(yg), symin), max(maximum(yg), symax))
    hx = source_grid.width / (nx - 1); hy = source_grid.height / (ny - 1)
    Qpart = zeros(2nx, 2ny)
    O._pic_deposit!(Qpart, method, sx, sy, source_grid.x0, source_grid.y0, hx, hy, nx, ny)
    phiP, ExP, EyP = solve_from_charge(solver, Qpart, source_grid, field_grid, nx, ny)
    xn = [source_grid.x0 + (i - 1) * hx for i in 1:nx]
    yn = [source_grid.y0 + (j - 1) * hy for j in 1:ny]
    gx = gauss_profile(xn, hx, 0.0, sigx, method); gy = gauss_profile(yn, hy, 0.0, sigy, method)
    dQ = copy(Qpart)
    for j in 1:ny, i in 1:nx
        dQ[i, j] -= ns * gx[i] * gy[j]
    end
    phiD, ExD, EyD = solve_from_charge(solver, dQ, source_grid, field_grid, nx, ny)
    pic = Float64[]; hyb = Float64[]; en = Float64[]
    for y in yg, x in xg
        bx, by = gaussian_beambeam_kick(sigx, sigy, x, y)   # true BE
        # injected defect
        if mode === :be          # the evaluator itself is wrong -> both uses wrong
            ekx = (1 + delta) * bx; eky = (1 + delta) * by
            abx = ekx; aby = eky                              # add-back uses same call
        elseif mode === :ref     # only the comparison reference is wrong
            ekx = (1 + delta) * bx; eky = (1 + delta) * by
            abx = bx; aby = by
        else
            ekx = bx; eky = by; abx = bx; aby = by
        end
        peX, peY, _ = O._pic_interpolate_kick(solver, field_grid, x, y, phiP, ExP, EyP, phiP, ExP, EyP, 1.0, 0.0)
        deX, deY, _ = O._pic_interpolate_kick(solver, field_grid, x, y, phiD, ExD, EyD, phiD, ExD, EyD, 1.0, 0.0)
        pkx = 2peX / ns; pky = 2peY / ns
        hkx = 2 * (deX + (ns / 2) * abx) / ns; hky = 2 * (deY + (ns / 2) * aby) / ns
        push!(pic, hypot(pkx - ekx, pky - eky))
        push!(hyb, hypot(hkx - ekx, hky - eky))
        push!(en, hypot(ekx, eky))
    end
    gn = maximum(en)
    return (pic_med=median(pic) / gn, pic_max=maximum(pic) / gn,
            hyb_med=median(hyb) / gn, hyb_max=maximum(hyb) / gn)
end

println("gaussian_pic_field_validation.jl instrument validation (round case, grid 128, CIC)")
println("baseline and injected-defect response of the two reported columns\n")
@printf("%-28s %12s %12s %12s %12s\n", "injection", "PIC med", "PIC max", "HYB med", "HYB max")
base = run_case(2.0e-3, 2.0e-3; grid=128, method=:CIC)
@printf("%-28s %12.4e %12.4e %12.4e %12.4e\n", "none (baseline)", base.pic_med, base.pic_max, base.hyb_med, base.hyb_max)
for d in (1e-6, 1e-4, 1e-2, 1.0)
    r = run_case(2.0e-3, 2.0e-3; grid=128, method=:CIC, delta=d, mode=:be)
    @printf("%-28s %12.4e %12.4e %12.4e %12.4e\n", "BE evaluator x(1+$d)", r.pic_med, r.pic_max, r.hyb_med, r.hyb_max)
end
for d in (1e-6, 1e-4, 1e-2)
    r = run_case(2.0e-3, 2.0e-3; grid=128, method=:CIC, delta=d, mode=:ref)
    @printf("%-28s %12.4e %12.4e %12.4e %12.4e\n", "reference only x(1+$d)", r.pic_med, r.pic_max, r.hyb_med, r.hyb_max)
end
