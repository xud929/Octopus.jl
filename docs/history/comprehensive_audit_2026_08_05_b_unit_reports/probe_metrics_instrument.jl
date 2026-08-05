#=
Instrument validation (audit protocol Phase 12) for the field-error metrics of

  validation/spectral_poisson_field_validation.jl   (shape_relerr, LSQ-calibrated)
  validation/pic_gaussian_field_validation.jl       (|K_pic - K_exact| / max|K_exact|)

Injections:
  (S1) feed shape_relerr a "solver output" that is the EXACT reference scaled by
       a constant -- i.e. perfect shape, wrong normalization by 2x / 1e-6.
  (S2) scale the reference by (1+d) and see whether shape_relerr moves.
  (P1) scale the reference by (1+d) in the pic_gaussian_field_validation metric.
  (P2) shift the evaluation mesh by one PIC cell (grid displacement defect).
=#
include(joinpath(@__DIR__, "repo", "src", "Octopus.jl"))
using .Octopus
using SpecialFunctions, Statistics, Printf
const O = Octopus

# ------------------------------------------------------- spectral metric (verbatim)
function shape_relerr(Ex, Ey, Kx, Ky)
    c = (sum(Ex .* Kx) + sum(Ey .* Ky)) / (sum(Ex .^ 2) + sum(Ey .^ 2))
    resid = [hypot(c * Ex[k] - Kx[k], c * Ey[k] - Ky[k]) for k in eachindex(Ex)]
    Kn = [hypot(Kx[k], Ky[k]) for k in eachindex(Kx)]
    m = maximum(Kn)
    return (median(resid) / m, quantile(resid, 0.95) / m, maximum(resid) / m)
end

sx = 2.0e-3; sy = 2.0e-3 / 5
FA = 41
xg = collect(range(-4sx, 4sx, length=FA)); yg = collect(range(-4sy, 4sy, length=FA))
xf = Float64[]; yf = Float64[]
for Y in yg, X in xg; push!(xf, X); push!(yf, Y); end
Kx = [first(gaussian_beambeam_kick(sx, sy, xf[k], yf[k])) for k in eachindex(xf)]
Ky = [last(gaussian_beambeam_kick(sx, sy, xf[k], yf[k])) for k in eachindex(xf)]

println("== S1: shape_relerr fed a solver output that is the reference times a constant ==")
for s in (1.0, 1.0 + 1e-6, 2.0, 0.5, -1.0)
    md, p95, mx = shape_relerr(s .* Kx, s .* Ky, Kx, Ky)
    @printf("  solver = %6.6g x exact:  median=%.3e  p95=%.3e  max=%.3e\n", s, md, p95, mx)
end

println("\n== S2: reference scaled by (1+d); solver = a genuinely approximate field ==")
# a crude but shape-wrong solver: BE of a slightly wrong sigma
Ax = [first(gaussian_beambeam_kick(sx * 1.02, sy, xf[k], yf[k])) for k in eachindex(xf)]
Ay = [last(gaussian_beambeam_kick(sx * 1.02, sy, xf[k], yf[k])) for k in eachindex(xf)]
for d in (0.0, 1e-6, 1e-2, 1.0)
    md, p95, mx = shape_relerr(Ax, Ay, (1 + d) .* Kx, (1 + d) .* Ky)
    @printf("  d = %-8g median=%.6e  p95=%.6e  max=%.6e\n", d, md, p95, mx)
end

# ------------------------------------------------------- pic_gaussian_field_validation metric
function gaussian_quantile_grid(sigx, sigy, n)
    u = ((1:n) .- 0.5) ./ n
    q = sqrt(2.0) .* erfinv.(2.0 .* u .- 1.0)
    x = Vector{Float64}(undef, n * n); y = similar(x); k = 1
    for yy in q, xx in q
        x[k] = sigx * xx; y[k] = sigy * yy; k += 1
    end
    return x, y
end

function pic_case(sigx, sigy; nsource_axis, field_axis, extent_sigma, pic_grid,
                  refscale=1.0, cellshift=0.0)
    solver = PICPoissonSolver(; grid=(pic_grid, pic_grid), deposit_method=:TSC, green_type=:integrated)
    source_x, source_y = gaussian_quantile_grid(sigx, sigy, nsource_axis)
    nsource = length(source_x)
    xgrid = collect(range(-extent_sigma * sigx, extent_sigma * sigx; length=field_axis))
    ygrid = collect(range(-extent_sigma * sigy, extent_sigma * sigy; length=field_axis))
    source_grid, field_grid = O._pic_interaction_grids(solver,
        minimum(source_x), maximum(source_x), minimum(source_y), maximum(source_y),
        minimum(xgrid), maximum(xgrid), minimum(ygrid), maximum(ygrid))
    phi, Ex, Ey = O._pic_solve_field(solver, source_x, source_y, source_grid, field_grid)
    hx = field_grid.width / (pic_grid - 1)
    rel = Float64[]; exact_norm = Float64[]
    for y in ygrid, x in xgrid
        pic_ex, pic_ey, _ = O._pic_interpolate_kick(solver, field_grid,
            x + cellshift * hx, y, phi, Ex, Ey, phi, Ex, Ey, 1.0, 0.0)
        pic_kx = 2.0 * pic_ex / nsource; pic_ky = 2.0 * pic_ey / nsource
        ekx0, eky0 = gaussian_beambeam_kick(sigx, sigy, x, y)
        exact_kx = refscale * ekx0; exact_ky = refscale * eky0
        push!(rel, hypot(pic_kx - exact_kx, pic_ky - exact_ky))
        push!(exact_norm, hypot(exact_kx, exact_ky))
    end
    gn = maximum(exact_norm)
    r = rel ./ gn
    return (median=median(r), p95=quantile(r, 0.95), max=maximum(r))
end

println("\n== P1/P2: pic_gaussian_field_validation metric, round case (reduced: 160x160 source, 61 field axis, grid 128) ==")
kw = (nsource_axis=160, field_axis=61, extent_sigma=4.0, pic_grid=128)
b = pic_case(2.0e-3, 2.0e-3; kw...)
@printf("  baseline                       median=%.4e p95=%.4e max=%.4e\n", b.median, b.p95, b.max)
for d in (1e-6, 1e-4, 1e-3, 1e-2)
    r = pic_case(2.0e-3, 2.0e-3; kw..., refscale=1 + d)
    @printf("  reference x(1+%-8g)         median=%.4e p95=%.4e max=%.4e   (median delta = %+.2e)\n",
            d, r.median, r.p95, r.max, r.median - b.median)
end
for s in (0.01, 0.1, 1.0)
    r = pic_case(2.0e-3, 2.0e-3; kw..., cellshift=s)
    @printf("  evaluation mesh shift %-6g cell median=%.4e p95=%.4e max=%.4e   (median x%.1f)\n",
            s, r.median, r.p95, r.max, r.median / b.median)
end
