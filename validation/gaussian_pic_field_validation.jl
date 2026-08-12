#=
Validate the Gaussian-subtracted PIC field (GaussianPICPoissonSolver) against the
analytic Bassetti-Erskine kick, and quantify its accuracy gain over the plain
PIC solver at a fixed grid.

Reference model: `gaussian_beambeam_kick` (exact 2D Gaussian / Bassetti-Erskine).
Error metric: per-point transverse kick error, normalized by the maximum exact
kick norm on the evaluation grid; medians and maxima reported over the grid.

The source slice is a deterministic Gaussian quantile lattice (no macroparticle
shot noise), so this isolates the *systematic* grid-discretization error -- the
coherent part of the field that drives tune shift, luminosity, and multi-turn
dynamics, and exactly the part the Gaussian subtraction removes. (In a live
simulation the per-particle single-turn kick is additionally shot-noise limited;
that floor is identical for PIC and the hybrid and is not what this checks.)

Both solvers are exercised through their real internals: PIC via
a local `solve_from_charge` wrapper around the production `_pic_green_fft`/
`_pic_field` kernels, and the hybrid via the same integrated-log Green convolution
with the erf-integrated Gaussian subtracted on the grid and the exact
Bassetti-Erskine field added back.

Outputs (under result/):
- gaussian_pic_field_validation_summary.tsv

Run from the project root:

    julia --project=. validation/gaussian_pic_field_validation.jl
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus
const O = Octopus
using SpecialFunctions: erf, erfinv
using FFTW
using Statistics
using Printf
using DelimitedFiles

result_dir = normpath(joinpath(@__DIR__, "..", "result"))
mkpath(result_dir)

# --- node-centered erf Gaussian deposition profile (docs Section 5) ---
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
"""
Equality tripwire against the shipped `_gpic_gaussian_profile!`.

The profile above is deliberately an INDEPENDENT re-derivation -- that
independence is what makes this a validation of the shipped code rather than a
tautology. But the script's header claims both solvers are "exercised through
their real internals", and with a hand copy in the subtraction path a regression
in `_gpic_gaussian_profile!` (its CIC/TSC branch, the half/3half cell edges, the
1.125/1.5/0.5 weights) would leave this study green (2026-08-05_b audit, U10-5).

So the copy stays and the drift becomes loud. Measured agreement when this was
added: 2.36e-16 (CIC), 4.27e-15 (TSC).
"""
function check_profile_against_shipped(; atol=1.0e-12)
    worst = 0.0
    for method in (:CIC, :TSC), (nnode, h, mu, s) in (
            (33, 0.25, 0.3, 1.1), (64, 0.1, -0.7, 0.45), (17, 0.5, 0.0, 2.0))
        x0 = -h * (nnode ÷ 2)
        nodes = [x0 + h * (k - 1) for k in 1:nnode]
        mine = gauss_profile(nodes, h, mu, s, method)
        theirs = Vector{Float64}(undef, nnode)
        Main.Octopus._gpic_gaussian_profile!(theirs, x0, h, mu, s, method)
        worst = max(worst, maximum(abs, mine .- theirs))
    end
    worst <= atol || error(
        "validation's own erf node profile has drifted from the shipped " *
        "_gpic_gaussian_profile!: max |difference| = $(worst) > $(atol). " *
        "One of the two is wrong; this script's accuracy table certifies the " *
        "SHIPPED one, so they must agree.")
    return worst
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
    # `_pic_fourth_order(solver)`, not the `fourth=false` default. This local
    # reimplementation hardcoded second order, so the public solver option
    # `field_derivative = :fourth` was silently ignored by the study that
    # carries the hybrid's documented accuracy table -- a copy fallen behind
    # the original, which is what production does at
    # `_pic_field!(..., _pic_fourth_order(solver))` (2026-08-05_b audit,
    # U23-10). The committed defaults give the same value either way; the
    # point is that the option is now reachable from this harness.
    Ex, Ey = O._pic_field(phi, hx, hy, O._pic_fourth_order(solver))
    return phi, Ex, Ey
end

function run_case(sigx, sigy; grid, method=:CIC, nsrc_axis=400, field_axis=81,
                  extent=4.0, margin_sigma=5.0)
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

    # Subtraction profile and add-back are both built from the SOURCE SAMPLE's
    # moments, as production does (`_gpic_source_moments` -> the profile it
    # subtracts and the Gaussian it adds back), not from the nominal (0, sigma).
    #
    # Forcing both to nominal made the HYB column circular: the add-back was the
    # identical `gaussian_beambeam_kick(sigx, sigy, ...)` call that supplies the
    # reference, so `hkx - ekx = 2*deX/ns + ekx - ekx = 2*deX/ns` identically --
    # the reported hybrid error was the magnitude of the residual grid field
    # measured against zero, carrying no information about the Bassetti-Erskine
    # evaluator, the moment estimate, or the consistency between the subtracted
    # profile and the added-back field, which is exactly where a production bug
    # lives. Docs section 9 and the manuscript's Figure 2 rest on this column
    # (2026-08-05_b audit, U23-2).
    mx = sum(sx) / ns
    my = sum(sy) / ns
    sxs = sqrt(max(sum(abs2, sx .- mx) / ns, 0.0))
    sys = sqrt(max(sum(abs2, sy .- my) / ns, 0.0))
    xn = [source_grid.x0 + (i - 1) * hx for i in 1:nx]
    yn = [source_grid.y0 + (j - 1) * hy for j in 1:ny]
    gx = gauss_profile(xn, hx, mx, sxs, method); gy = gauss_profile(yn, hy, my, sys, method)
    dQ = copy(Qpart)
    for j in 1:ny, i in 1:nx
        dQ[i, j] -= ns * gx[i] * gy[j]
    end
    phiD, ExD, EyD = solve_from_charge(solver, dQ, source_grid, field_grid, nx, ny)

    pic = Float64[]; hyb = Float64[]; en = Float64[]
    for y in yg, x in xg
        # Reference: the analytic field of the NOMINAL Gaussian.
        ekx, eky = gaussian_beambeam_kick(sigx, sigy, x, y)
        # Add-back: the analytic field of the SAMPLE's Gaussian, at the sample's
        # centroid -- the quantity production actually adds. It no longer
        # cancels against the reference, so the HYB column measures the
        # subtract/add-back consistency instead of `2*deX/ns` (U23-2).
        akx, aky = gaussian_beambeam_kick(sxs, sys, x - mx, y - my)
        peX, peY, _ = O._pic_interpolate_kick(solver, field_grid, x, y, phiP, ExP, EyP, phiP, ExP, EyP, 1.0, 0.0)
        deX, deY, _ = O._pic_interpolate_kick(solver, field_grid, x, y, phiD, ExD, EyD, phiD, ExD, EyD, 1.0, 0.0)
        pkx = 2peX / ns; pky = 2peY / ns
        hkx = 2 * (deX + (ns / 2) * akx) / ns; hky = 2 * (deY + (ns / 2) * aky) / ns
        push!(pic, hypot(pkx - ekx, pky - eky))
        push!(hyb, hypot(hkx - ekx, hky - eky))
        push!(en, hypot(ekx, eky))
    end
    gn = maximum(en)
    return (pic_med=median(pic) / gn, pic_max=maximum(pic) / gn,
            hyb_med=median(hyb) / gn, hyb_max=maximum(hyb) / gn)
end

# Aspect ratios from round to the ~11:1 production flat beams.
cases = [
    ("round", 2.0e-3, 2.0e-3),
    ("5:1", 2.0e-3, 0.4e-3),
    ("production_e ~11:1", 106.0e-6, 9.5e-6),
    ("25:1", 2.0e-3, 0.08e-3),
]
# Default 48,64,128 (12 rows). The archived paper table
# `data/gaussian_pic_field_validation_summary.tsv` in the paper repository
# (https://github.com/xud929/2026_octopus_cpc) carries 24 rows at
# 48,64,96,128,192,256, so REGENERATING IT NEEDS THE OVERRIDE:
#
#   OCTOPUS_GPIC_GRIDS=48,64,96,128,192,256 julia --project=. --threads=4 \
#       validation/gaussian_pic_field_validation.jl
#
# That override was recorded in neither this header, validation/README.md
# nor the package README (now the paper repository's), so the frozen figure
# could not be reproduced from
# the committed defaults (2026-08-05_b audit, U23-10).
grids = Tuple(parse.(Int, split(get(ENV, "OCTOPUS_GPIC_GRIDS", "48,64,128"), ',')))

# Run the tripwire BEFORE any accuracy number is produced: a table certifying
# the shipped profile, computed with a copy that has silently drifted from it,
# is worse than no table (U10-5).
let drift = check_profile_against_shipped()
    println("erf node profile vs shipped _gpic_gaussian_profile!: max |diff| = ", drift)
end

rows = Any[]
println("Gaussian-subtracted PIC field accuracy vs Bassetti-Erskine (deterministic source)")
@printf("%-20s %5s %6s | %10s %10s | %10s %10s | %6s %6s\n",
        "case", "grid", "meth", "PIC med", "PIC max", "HYB med", "HYB max", "x med", "x max")
for (name, sigx, sigy) in cases, g in grids
    r = run_case(sigx, sigy; grid=g, method=:CIC)
    @printf("%-20s %5d %6s | %10.2e %10.2e | %10.2e %10.2e | %6.1f %6.1f\n",
            name, g, "CIC", r.pic_med, r.pic_max, r.hyb_med, r.hyb_max,
            r.pic_med / r.hyb_med, r.pic_max / r.hyb_max)
    push!(rows, (name, g, "CIC", sigx, sigy, r.pic_med, r.pic_max, r.hyb_med, r.hyb_max,
                 r.pic_med / r.hyb_med, r.pic_max / r.hyb_max))
end

summary_path = joinpath(result_dir, "gaussian_pic_field_validation_summary.tsv")
open(summary_path, "w") do io
    println(io, "# columns\tcase\tgrid\tmethod\tsigx\tsigy\tpic_median\tpic_max\thybrid_median\thybrid_max\tmedian_gain\tmax_gain")
    for r in rows
        println(io, join(r, '\t'))
    end
end
println("\nsummary = ", summary_path)
