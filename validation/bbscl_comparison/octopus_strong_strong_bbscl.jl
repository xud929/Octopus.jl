#=
Octopus side of the BBSCL comparison, case S (strong-strong): the EIC-like
electron-proton collision of examples/strong_strong_tracking.jl with the crab
cavities and chromaticity kicks removed (BBSCL has neither), Hirata Lorentz
boosts for the crossing angle, linear one-turn maps, lumped radiation damping
and excitation on the electron ring, PIC or soft-Gaussian solver. The BBSCL
twin is bbscl_S_{e,p}.in in the same directory.

Environment (defaults in parentheses):
  OCT_GPU (1)             1 = CUDA (error if no device), 0 = CPU threads
  OCT_NE (2560000)        electron macroparticles   (BBSCL: multiples of 256)
  OCT_NP (1024000)        proton macroparticles
  OCT_TURNS (200)         turns
  OCT_WARMUP (20)         turns excluded from the timing statistics
  OCT_NS (15)             slices per beam (normal-quantile boundaries, centroid)
  OCT_GRID (128)          PIC grid per side
  OCT_SOLVER (pic)        pic | gaussian
  OCT_ANGLE (12.5e-3)     HALF crossing angle in rad; 0 = head-on (no boosts)
  OCT_RAD (1)             1 = electron radiation damping + excitation, 0 = off
  OCT_MOMENTS_EVERY (0)   0 = no moment observers; k = both beams every k turns
  OCT_SEED (123456789)
  OCT_OUT (result/bbscl_comparison_2026_11_22/octopus_S_<tag>.tsv)
=#
if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "..", "src", "Octopus.jl"))
end
using .Octopus
using Statistics
using Printf

envi(n, d) = parse(Int, get(ENV, n, string(d)))
envf(n, d) = parse(Float64, get(ENV, n, string(d)))
const GPU    = envi("OCT_GPU", 1) == 1
const NE     = envi("OCT_NE", 2_560_000)
const NP     = envi("OCT_NP", 1_024_000)
const TURNS  = envi("OCT_TURNS", 200)
const WARMUP = envi("OCT_WARMUP", 20)
const NS     = envi("OCT_NS", 15)
const GRID   = envi("OCT_GRID", 128)
const SOLVER = lowercase(get(ENV, "OCT_SOLVER", "pic"))
const ANGLE  = envf("OCT_ANGLE", 12.5e-3)
const RAD    = envi("OCT_RAD", 1) == 1
const MOM    = envi("OCT_MOMENTS_EVERY", 0)
const SEED   = envi("OCT_SEED", 123456789)
tag = "$(SOLVER)_Ne$(NE)_Np$(NP)_ns$(NS)_g$(GRID)_ang$(ANGLE)_rad$(RAD ? 1 : 0)_" * (GPU ? "cuda" : "cpu")
const OUT = get(ENV, "OCT_OUT", joinpath(@__DIR__, "octopus_S_" * tag * ".tsv"))

if GPU
    import CUDA
    CUDA.functional(false) || error("OCT_GPU=1 but CUDA is not functional")
    policy = CUDAExecutionPolicy()
else
    policy = CPUThreadsExecutionPolicy()
end
println("policy = ", nameof(typeof(policy)), "  threads = ", Threads.nthreads())
set_global_rng!(seed = SEED, method = :philox)

# Physics literals of examples/strong_strong_tracking.jl (crabs and chromaticity dropped).
ele = (charge = -1.0, mass = EMASS_EV, energy = 10.0e9, n_particle = 1.7203e11, cutoff = 5.0,
       sigma = (106.0e-6, 9.5e-6, 0.7e-2), sigd = 5.5e-4, beta_star = (0.55, 0.056),
       tune = (0.08, 0.14, -0.069), damping_turns = (4000.0, 4000.0, 2000.0))
pro = (charge = 1.0, mass = PMASS_EV, energy = 275.0e9, n_particle = 0.6881e11, cutoff = 5.0,
       sigma = (95.0e-6, 8.5e-6, 6.0e-2), sigd = 6.6e-4, beta_star = (0.8, 0.072),
       tune = (0.228, 0.210, -0.01))
ele_ip = LinearOptics(; beta = (ele.beta_star..., ele.sigma[3] / ele.sigd))
pro_ip = LinearOptics(; beta = (pro.beta_star..., pro.sigma[3] / pro.sigd))

beam_ele = Beam(NE, policy, Float64; optics = ele_ip, sigma = ele.sigma, cutoff = ele.cutoff,
    rng_id = 1, charge = ele.charge, mc2 = ele.mass, E0 = ele.energy, r0 = RE * ME0 / ele.mass,
    npart = ele.n_particle)
beam_pro = Beam(NP, policy, Float64; optics = pro_ip, sigma = pro.sigma, cutoff = pro.cutoff,
    rng_id = 2, charge = pro.charge, mc2 = pro.mass, E0 = pro.energy, r0 = RE * ME0 / pro.mass,
    npart = pro.n_particle)

slicing = LongitudinalSlicing(; method = :normal_quantile, nslices = NS, center_position = :centroid)
solver = if SOLVER == "pic"
    PICPoissonSolver(; slicing = slicing, grid = (GRID, GRID), deposit_method = :CIC,
        green_type = :integrated, green_cache = :slice_pair, slice_pair_green_min_ratio = 0.50,
        slice_pair_green_growth = 0.25, longitudinal_kick = true)
elseif SOLVER == "gaussian"
    GaussianPoissonSolver(; slicing = slicing, longitudinal_kick = true)
else
    error("OCT_SOLVER=$(SOLVER) is not pic or gaussian")
end

ele_one_turn = Linear6DSpec{Float64}(ele_ip, ele_ip; dmu = 2pi .* ele.tune)
pro_one_turn = Linear6DSpec{Float64}(pro_ip, pro_ip; dmu = 2pi .* pro.tune)
ele_rad = LumpedRadSpec{Float64}(; damping_turns = ele.damping_turns, optics = ele_ip,
    sigma = ele.sigma, is_damping = true, is_excitation = true, rng_id = 3)
ip = StrongStrongCollision(:ip; poisson_solver = solver)

le = Any[]; lp = Any[]
if ANGLE > 0
    lb = LorentzBoostSpec(ANGLE); rlb = RevLorentzBoostSpec(ANGLE)
    push!(le, lb); push!(lp, lb)
end
push!(le, ip); push!(lp, ip)
if ANGLE > 0
    push!(le, rlb); push!(lp, rlb)
end
push!(le, ele_one_turn); push!(lp, pro_one_turn)
RAD && push!(le, ele_rad)
if MOM > 0
    sched = EveryNSteps(; start = 0, step = MOM)
    push!(le, ScheduledObserver(MomentObserver(; name = "electron"), sched))
    push!(lp, ScheduledObserver(MomentObserver(; name = "proton"), sched))
end
line_ele = Tuple(le); line_pro = Tuple(lp)

artifact = RunArtifact(; storage = :memory, capacity = 1024)
task = StrongStrongTask(line_ele, line_pro; policy = policy, artifact = artifact,
                        diagnostics = StrongStrongDiagnostics(record_turn_times = true))
se0 = beam_statistics(beam_ele); sp0 = beam_statistics(beam_pro)
t0 = time()
execute!(task, beam_ele, beam_pro; turns = TURNS)
GPU && CUDA.synchronize()
wall = time() - t0
times = turn_timings(task)
lum = read(TaskOutput(artifact), :luminosity; name = "ip")
se1 = beam_statistics(beam_ele); sp1 = beam_statistics(beam_pro)

sel = (WARMUP + 1):TURNS
tt = times[sel]
@printf("solver=%s turns=%d Ne=%d Np=%d ns=%d grid=%d angle=%g rad=%d backend=%s\n", SOLVER, TURNS, NE, NP,
        NS, GRID, ANGLE, RAD ? 1 : 0, GPU ? "cuda" : "cpu")
@printf("wall(execute!)=%.3f s  mean/turn (turns %d-%d) = %.5f s  median = %.5f s  sd = %.5f s  min = %.5f max = %.5f\n",
        wall, first(sel), last(sel), mean(tt), median(tt), std(tt), minimum(tt), maximum(tt))
@printf("luminosity per crossing [m^-2]: turn 1 = %.6e  mean(sel) = %.6e  last = %.6e\n",
        lum.value[1], mean(lum.value[sel]), lum.value[end])
println("electron rms initial = ", se0.rms); println("electron rms final   = ", se1.rms)
println("proton rms initial   = ", sp0.rms); println("proton rms final     = ", sp1.rms)
open(OUT, "w") do io
    println(io, "# octopus case S  solver=$SOLVER Ne=$NE Np=$NP turns=$TURNS ns=$NS grid=$GRID angle=$ANGLE rad=$(RAD ? 1 : 0) backend=$(GPU ? "cuda" : "cpu") seed=$SEED")
    println(io, "# e_rms_initial\t", join(se0.rms, "\t")); println(io, "# e_rms_final\t", join(se1.rms, "\t"))
    println(io, "# p_rms_initial\t", join(sp0.rms, "\t")); println(io, "# p_rms_final\t", join(sp1.rms, "\t"))
    println(io, "turn\tseconds\tluminosity_m2")
    for (k, t) in enumerate(times)
        println(io, k, "\t", t, "\t", lum.value[k])
    end
end
if MOM > 0
    for nm in ("electron", "proton")
        mo = read(TaskOutput(artifact), :moments; name = nm, orders = 1:2)
        open(replace(OUT, ".tsv" => "_moments_$(nm).tsv"), "w") do io
            cols = collect(keys(mo))
            println(io, "# columns: ", join(string.(cols), "\t"))
            for r in 1:length(mo[1])
                println(io, join((mo[c][r] for c in cols), "\t"))
            end
        end
    end
end
println("BBSCL-COMPARISON-OCTOPUS-S done -> ", OUT)
