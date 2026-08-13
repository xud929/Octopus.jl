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
# Run from the project root:
#
#     julia --startup-file=no --project=. validation/crossing_luminosity_anchor.jl
#
# Outputs, under result/lum_anchor/: lum_headon.lum, lum_crossing.lum,
# lum_crab.lum (undocumented until the 2026-08-05_b audit, U25-12).
# Guarded like every other script in `validation/`: without it this file
# cannot be `include`d after any sibling in one process, which is how the
# audit harnesses drive them (2026-08-05_b audit, U25-14).
if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus
using Statistics
import SpecialFunctions: erfinv

const OUTDIR = joinpath(@__DIR__, "..", "result", "lum_anchor")
mkpath(OUTDIR)

theta = 12.5e-3                       # half crossing angle
sig   = (100.0e-6, 100.0e-6, 0.02)
beta  = (0.5, 0.5, 0.02 / 5.0e-4)
crab_beta = (150.0, 30.0, beta[3])
crab_freq = 100.0e6
tunes = (0.31, 0.32, -0.005)
nmacro = 200_000
# Parameterized for the paper's robustness statements (five paired seeds;
# the 1/7/15/31-slice x 128^2/256^2 grid scan); defaults reproduce the
# archived single-seed anchor.
nslices = parse(Int, get(ENV, "OCTOPUS_ANCHOR_NSLICES", "15"))
anchor_seed = parse(Int, get(ENV, "OCTOPUS_ANCHOR_SEED", "20260728"))
anchor_grid = parse(Int, get(ENV, "OCTOPUS_ANCHOR_GRID", "128"))
energy = 10.0e9
npart_small = 1.0e8                   # xi ~ 1e-5: geometry test, not dynamics

function run_config(tag; angle, crab)
    set_global_rng!(seed = anchor_seed, method = :philox)
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
    solver = PICPoissonSolver(; slicing = sl, grid = (anchor_grid, anchor_grid),
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

    lum_path = joinpath(OUTDIR, "lum_$(tag).lum")
    task = StrongStrongTask(elems, elems; luminosity_path = lum_path)
    execute!(task, b1, b2; turns = 3)
    vals = Float64[]
    for l in eachline(lum_path)
        v = tryparse(Float64, last(split(l)))
        v === nothing || push!(vals, v)
    end
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

println("phi (Piwinski) = ", round(phi; digits = 3))
println("R continuous   = ", round(Rcont; digits = 5))
println("R discrete-15  = ", round(Rdisc; digits = 5))
println("R code no-crab = ", round(Lx / L0; digits = 5))
println("R code crab    = ", round(Lc / L0; digits = 5))
println("code/discrete (no-crab) = ", round(Lx / L0 / Rdisc; digits = 4))
