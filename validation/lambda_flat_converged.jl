#=
Converged flat-beam Yokoya point.

The manuscript's aspect-ratio scan (Fig. 6a) is measured at REDUCED settings
-- 2048 turns, 2e4 macroparticles/beam, one seed -- and carries an adopted
+-0.005 scan uncertainty plus a possible common reduced-settings offset of up
to ~0.008.  The flat-limit statement ("neither plane reaches 1.33") therefore
rests on the weakest data in the section.

This driver measures the single most load-bearing point, r = sigma_y/sigma_x =
0.09, at the CONVERGED settings used for the round-beam benchmark of Table 2:
8192 turns, 1e5 macroparticles/beam, three seeds -- and reports BOTH planes.

Lambda_x is in units of the wide plane's own xi_x; Lambda_y in units of the
narrow plane's own xi_y = xi_x / r, matching the manuscript's convention.

Characterisation, no verdict: the script prints and records (`OCTOPUS_LFC_OUT`)
the measured Lambda of both planes; the archived converged values are in the
header of `lambda_round_converged.jl` and in the paper repository, and a run
at reduced settings (fewer turns, fewer macroparticles) is not converged and
is not compared with them.

Run from the project root (the defaults are the converged settings; the
environment variables below reduce them):
  OCTOPUS_LFC_TURNS=8192 OCTOPUS_LFC_NMACRO=100000 \
  julia --threads=8 --project=. validation/lambda_flat_converged.jl

Environment: OCTOPUS_LFC_TURNS, OCTOPUS_LFC_NMACRO, OCTOPUS_LFC_ASPECT,
OCTOPUS_LFC_SEEDS (comma-separated), OCTOPUS_LFC_OUT.
=#

# Guarded like every other script in `validation/` (2026-08-05_b audit,
# U25-14): until 2026-10-22 this file and emit_xcode.jl re-evaluated the
# package when included after a sibling in one process, and this one
# redefined its top-level `const`s (2026-10-18 comprehensive audit,
# F-243/U54-6).
if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
mkpath(joinpath(@__DIR__, "..", "result"))
using .Octopus
using Statistics
import FFTW

const TURNS = parse(Int, get(ENV, "OCTOPUS_LFC_TURNS", "8192"))
const NMACRO = parse(Int, get(ENV, "OCTOPUS_LFC_NMACRO", "100000"))
const ASPECT = parse(Float64, get(ENV, "OCTOPUS_LFC_ASPECT", "0.09"))
const SEEDS = [parse(Int, s) for s in split(get(ENV, "OCTOPUS_LFC_SEEDS",
                                               "20260727,20260728,20260729"), ',')]
const OUT = get(ENV, "OCTOPUS_LFC_OUT",
                joinpath(@__DIR__, "..", "result", "lambda_flat_converged.tsv"))

# One source: the package's estimator (the one `CoherentModePhysicsContract`
# judges with). Until 2026-10-22 this was one of six hand copies of the
# Hann-window plus parabolic-interpolation estimator across `validation/`,
# bound to nothing (2026-10-18 comprehensive audit, F-243/U54-7).
fractional_tune(signal) = Octopus._coherent_fractional_tune(signal)

"""Symmetric coherent-mode run; returns Lambda in BOTH planes."""
function measure_both(; aspect, xi_x = 0.005, turns = TURNS, n_macro = NMACRO,
                        seed = 20260727)
    set_global_rng!(seed = seed, method = :philox)
    policy = CPUThreadsExecutionPolicy()
    energy = 10.0e9
    gamma_rel = energy / EMASS_EV
    r0 = RE * ME0 / EMASS_EV
    sigx = 106.0e-6
    sigy = aspect * sigx
    beta = (0.55, 0.55, 0.7e-2 / 5.5e-4)
    sigma = (sigx, sigy, 0.7e-2)
    npart = xi_x * 2pi * gamma_rel * sigx * (sigx + sigy) / (r0 * beta[1])
    # narrow-plane beam-beam parameter of the same configuration
    xi_y = npart * r0 * beta[2] / (2pi * gamma_rel * sigy * (sigx + sigy))

    offset1 = (0.1 * sigx, 0.0, 0.1 * sigy, 0.0, 0.0, 0.0)
    beam1 = Beam(n_macro, policy, Float64;
        beta = beta, alpha = (0.0, 0.0, 0.0), sigma = sigma, cutoff = 5.0,
        rng_id = 1, charge = -1.0, mc2 = EMASS_EV, E0 = energy, r0 = r0,
        npart = npart, initial_offset = offset1)
    beam2 = Beam(n_macro, policy, Float64;
        beta = beta, alpha = (0.0, 0.0, 0.0), sigma = sigma, cutoff = 5.0,
        rng_id = 2, charge = +1.0, mc2 = EMASS_EV, E0 = energy, r0 = r0,
        npart = npart)

    slicing = LongitudinalSlicing(; method = :normal_quantile, nslices = 1,
                                  center_position = :centroid)
    solver = PICPoissonSolver(; slicing = slicing, grid = (128, 128),
        deposit_method = :CIC, green_type = :integrated, green_cache = :slice_pair,
        longitudinal_kick = false)
    ip = StrongStrongCollision(:ip; poisson_solver = solver)
    one_turn = Linear6DSpec{Float64}(;
        beta1 = beta, beta2 = beta, alpha1 = (0.0, 0.0, 0.0),
        alpha2 = (0.0, 0.0, 0.0), dmu = 2pi .* (0.31, 0.32, -0.01))
    task = StrongStrongTask((ip, one_turn), (ip, one_turn); policy = policy)

    # Deterministic line (collision + linear map, no stochastic element), so
    # the per-turn execute! loop is safe here; see
    # data/multiturn_deferred/README.md in the paper repository
    # (https://github.com/xud929/2026_octopus_cpc).
    x1 = Vector{Float64}(undef, turns); x2 = similar(x1)
    y1 = similar(x1); y2 = similar(x1)
    for t in 1:turns
        execute!(task, beam1, beam2; turns = 1)
        x1[t] = mean(beam1.rep.x); x2[t] = mean(beam2.rep.x)
        y1[t] = mean(beam1.rep.y); y2[t] = mean(beam2.rep.y)
    end
    qsx = fractional_tune(x1 .+ x2); qpx = fractional_tune(x1 .- x2)
    qsy = fractional_tune(y1 .+ y2); qpy = fractional_tune(y1 .- y2)
    return (Lx = (qpx - qsx) / xi_x, Ly = (qpy - qsy) / xi_y,
            qsx = qsx, qsy = qsy, xi_y = xi_y)
end

println("Converged flat-beam Yokoya point")
println("  aspect r = ", ASPECT, "   turns = ", TURNS,
        "   n_macro = ", NMACRO, "/beam   seeds = ", SEEDS)
println()

Lx = Float64[]; Ly = Float64[]
open(OUT, "w") do io
    println(io, "seed\taspect\tturns\tn_macro\tLambda_x\tLambda_y\tq_sigma_x\tq_sigma_y\txi_y")
    for s in SEEDS
        t = @elapsed r = measure_both(; aspect = ASPECT, seed = s)
        push!(Lx, r.Lx); push!(Ly, r.Ly)
        println(io, s, '\t', ASPECT, '\t', TURNS, '\t', NMACRO, '\t',
                r.Lx, '\t', r.Ly, '\t', r.qsx, '\t', r.qsy, '\t', r.xi_y)
        flush(io)
        println("  seed ", s, ":  Lambda_x = ", round(r.Lx; digits = 4),
                "   Lambda_y = ", round(r.Ly; digits = 4),
                "   (xi_y = ", round(r.xi_y; digits = 4), ", ",
                round(t; digits = 0), " s)")
    end
end

println()
println("Lambda_x = ", round(mean(Lx); digits = 4), " +- ",
        round(length(Lx) > 1 ? std(Lx) : 0.0; digits = 4))
println("Lambda_y = ", round(mean(Ly); digits = 4), " +- ",
        round(length(Ly) > 1 ? std(Ly) : 0.0; digits = 4))
println("written to ", OUT)
