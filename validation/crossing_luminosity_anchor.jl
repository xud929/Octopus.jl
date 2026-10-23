# Crossing-angle luminosity anchor: PIC luminosity vs analytic Piwinski factor.
# Symmetric Gaussian beams, hourglass suppressed (beta* >> sigma_z), tiny bunch
# charge (beam-beam negligible). Three configs: head-on, half-crossing 12.5 mrad
# without crabs, same with ideal crabs. Reference: continuous R = 1/sqrt(1+phi^2)
# and the 15-quantile-slice discrete sum (isolates slicing error).
#
# Error metric: relative difference of the measured luminosity ratio against
# each reference. Paper-cited; data/crossing_lum_anchor.tsv in the paper
# repository (https://github.com/xud929/2026_octopus_cpc) is the
# hand-transcribed copy.
#
# Verdicts (since 2026-10-22; until then every number was print-only and
# nothing in the repository would have noticed a refactor moving them --
# comprehensive audit 2026-10-18, F-243/U54-9), each printed with its number:
#   crab      ideal crabs restore the head-on luminosity: |L_crab/L_headon - 1|
#             <= TOL_CRAB. The boost-plus-crab geometry differs from head-on at
#             O(theta^2) = 1.6e-4 and the three runs share their macroparticles
#             (one seed), so the ratio is 1 to a few 1e-4 at every size.
#   discrete  the code's crossing reduction against the 15-slice discrete
#             reference: |(L_crossing/L_headon)/R_discrete - 1| <= TOL_DISCRETE.
#             Measured 1.0073 at the paper's size (2026-10-18 audit U54), 1.0069
#             and 1.0086 at 20000 and 50000 macroparticles (fix batch 4); the
#             bound is a regression guard at two to three times that residual,
#             not a derived error bar.
# Prints `LUM-ANCHOR phi=.. R_cont=.. R_disc=.. R_code=.. R_crab=.. code_over_disc=.. verdict=PASS|FAIL`
# and exits 1 on FAIL.
#
# Run from the project root:
#
#     julia --startup-file=no --project=. validation/crossing_luminosity_anchor.jl
#
# Environment (the defaults are the paper's):
#     OCTOPUS_LUM_ANCHOR_NMACRO=200000       macroparticles per beam
#     OCTOPUS_LUM_ANCHOR_OUT=result/lum_anchor  the artifacts' directory
#
# Outputs, under OCTOPUS_LUM_ANCHOR_OUT: lum_headon.h5, lum_crossing.h5,
# lum_crab.h5 -- run artifacts whose /luminosity/ip channel this script reads
# back (outputs undocumented until the 2026-08-05_b audit, U25-12).
# Guarded like every other script in `validation/`: without it this file
# cannot be `include`d after any sibling in one process, which is how the
# audit harnesses drive them (2026-08-05_b audit, U25-14).
if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus
using Statistics
import SpecialFunctions: erfinv

const OUTDIR = get(ENV, "OCTOPUS_LUM_ANCHOR_OUT", joinpath(@__DIR__, "..", "result", "lum_anchor"))
mkpath(OUTDIR)
const TOL_CRAB = 2.0e-3
const TOL_DISCRETE = 2.0e-2

theta = 12.5e-3                       # half crossing angle
sig   = (100.0e-6, 100.0e-6, 0.02)
beta  = (0.5, 0.5, 0.02 / 5.0e-4)
crab_beta = (150.0, 30.0, beta[3])
crab_freq = 100.0e6
tunes = (0.31, 0.32, -0.005)
nmacro = parse(Int, get(ENV, "OCTOPUS_LUM_ANCHOR_NMACRO", "200000"))
nslices = 15
energy = 10.0e9
npart_small = 1.0e8                   # xi ~ 1e-5: geometry test, not dynamics

function run_config(tag; angle, crab)
    set_global_rng!(seed = 20260728, method = :philox)
    policy = CPUThreadsExecutionPolicy()
    gr = energy / EMASS_EV
    r0 = RE * ME0 / EMASS_EV
    b1 = Beam(nmacro, policy, Float64; beta = beta, alpha = (0.0, 0.0, 0.0),
        sigma = sig, cutoff = 5.0, rng_id = 1, charge = -1.0, mc2 = EMASS_EV,
        E0 = energy, r0 = r0, npart = npart_small)
    b2 = Beam(nmacro, policy, Float64; beta = beta, alpha = (0.0, 0.0, 0.0),
        sigma = sig, cutoff = 5.0, rng_id = 2, charge = +1.0, mc2 = EMASS_EV,
        E0 = energy, r0 = r0, npart = npart_small)

    sl = LongitudinalSlicing(; method = :normal_quantile, nslices = nslices,
        center_position = :centroid)
    solver = PICPoissonSolver(; slicing = sl, grid = (128, 128),
        deposit_method = :CIC, green_type = :integrated,
        longitudinal_kick = true)
    ip = StrongStrongCollision(:ip; poisson_solver = solver)

    ot = Linear6DSpec{Float64}(; beta1 = beta, beta2 = beta,
        alpha1 = (0.0, 0.0, 0.0), alpha2 = (0.0, 0.0, 0.0),
        dmu = 2pi .* tunes)

    lb = LorentzBoostSpec(angle)
    rlb = RevLorentzBoostSpec(angle)

    elems = if crab
        strength = (tan(angle) / sqrt(crab_beta[1] * beta[1]), 0.0, 0.0)
        tccb2ip = Linear6DSpec{Float64}(; beta1 = crab_beta, beta2 = beta,
            alpha1 = (0.0, 0.0, 0.0), alpha2 = (0.0, 0.0, 0.0),
            dmu = (pi / 2.0, 0.0, 0.0))
        tccb2ip_inv = Linear6DSpec{Float64}(matrix = inv(Matrix(Linear6D(tccb2ip))))
        ip2tcca = Linear6DSpec{Float64}(; beta1 = beta, beta2 = crab_beta,
            alpha1 = (0.0, 0.0, 0.0), alpha2 = (0.0, 0.0, 0.0),
            dmu = (pi / 2.0, 0.0, 0.0))
        ip2tcca_inv = Linear6DSpec{Float64}(matrix = inv(Matrix(Linear6D(ip2tcca))))
        tcc = ThinCrabCavitySpec{3}(crab_freq; strengthX = strength,
            strengthY = (0.0, 0.0, 0.0), phase = (0.0, 0.0, 0.0))
        (tccb2ip_inv, tcc, tccb2ip, lb, ip, rlb, ip2tcca, tcc, ip2tcca_inv, ot)
    else
        (lb, ip, rlb, ot)
    end

    lum_path = joinpath(OUTDIR, "lum_$(tag).h5")
    task = StrongStrongTask(elems, elems; artifact = lum_path)
    execute!(task, b1, b2; turns = 3)
    vals = collect(Float64, read(TaskOutput(lum_path), :luminosity; name = "ip").value)
    println(tag, " luminosity per turn: ", vals)
    mean(vals)
end

L0 = run_config("headon"; angle = 0.0, crab = false)
Lx = run_config("crossing"; angle = theta, crab = false)
Lc = run_config("crab"; angle = theta, crab = true)

phi = tan(theta) * sig[3] / sig[1]
Rcont = 1 / sqrt(1 + phi^2)

# discrete reference on the same 15 equal-charge quantile slices
edges = [sqrt(2.0) * erfinv(2 * (i / nslices) - 1) for i in 0:nslices]
centers = [nslices * (exp(-edges[i]^2 / 2) - exp(-edges[i+1]^2 / 2)) / sqrt(2pi)
           for i in 1:nslices] .* sig[3]
Rdisc = sum(exp(-(tan(theta) * (z1 - z2))^2 / (4 * sig[1]^2))
            for z1 in centers, z2 in centers) / nslices^2

println("nmacro per beam = ", nmacro, "   (artifacts under ", OUTDIR, ")")
println("phi (Piwinski) = ", round(phi; digits = 3))
println("R continuous   = ", round(Rcont; digits = 5))
println("R discrete-15  = ", round(Rdisc; digits = 5))
println("R code no-crab = ", round(Lx / L0; digits = 5))
println("R code crab    = ", round(Lc / L0; digits = 5), "   (|. - 1| = ", round(abs(Lc / L0 - 1); sigdigits = 3), ")")
println("code/discrete (no-crab) = ", round(Lx / L0 / Rdisc; digits = 4), "   (|. - 1| = ", round(abs(Lx / L0 / Rdisc - 1); sigdigits = 3), ")")
crab_ok = abs(Lc / L0 - 1) <= TOL_CRAB
disc_ok = abs(Lx / L0 / Rdisc - 1) <= TOL_DISCRETE
println("verdicts: crab restores head-on within ", TOL_CRAB, ": ", crab_ok ? "PASS" : "FAIL",
        "; code/discrete within ", TOL_DISCRETE, " of 1: ", disc_ok ? "PASS" : "FAIL")
println("LUM-ANCHOR phi=", phi, " R_cont=", Rcont, " R_disc=", Rdisc, " R_code=", Lx / L0, " R_crab=", Lc / L0,
        " code_over_disc=", Lx / L0 / Rdisc, " nmacro=", nmacro, " verdict=", (crab_ok && disc_ok) ? "PASS" : "FAIL")
(crab_ok && disc_ok) || exit(1)
