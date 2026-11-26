#=
Octopus side of the BBSCL comparison, case W (weak-strong): a live proton beam
against a rigid sliced Gaussian electron beam, Hirata Lorentz boosts for the
crossing angle, a linear one-turn map, no crab cavities, no chromaticity, no
radiation (the weak beam is a proton beam). The BBSCL twin is
bbscl_W_{e,p}.in in the same directory.

Environment (defaults in parentheses):
  OCT_GPU (1)         1 = CUDA (error if no device), 0 = CPU threads
  OCT_N (1024000)     weak-beam macroparticles (BBSCL needs a multiple of 256)
  OCT_TURNS (200)     turns
  OCT_WARMUP (20)     turns excluded from the timing statistics
  OCT_NS (7)          strong-beam slices
  OCT_ANGLE (12.5e-3) HALF crossing angle in rad; 0 = head-on (no boosts in the line)
  OCT_MOMENTS_EVERY (0) 0 = no moment observer; k = MomentObserver every k turns
  OCT_SEED (123456789)
  OCT_OUT (result/bbscl_comparison_2026_11_22/octopus_W_<tag>.tsv)
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
const N      = envi("OCT_N", 1_024_000)
const TURNS  = envi("OCT_TURNS", 200)
const WARMUP = envi("OCT_WARMUP", 20)
const NS     = envi("OCT_NS", 7)
const ANGLE  = envf("OCT_ANGLE", 12.5e-3)
const MOM    = envi("OCT_MOMENTS_EVERY", 0)
const SEED   = envi("OCT_SEED", 123456789)
tag = "N$(N)_ns$(NS)_ang$(ANGLE)_" * (GPU ? "cuda" : "cpu")
const OUT = get(ENV, "OCT_OUT", joinpath(@__DIR__, "octopus_W_" * tag * ".tsv"))

if GPU
    import CUDA
    CUDA.functional(false) || error("OCT_GPU=1 but CUDA is not functional")
    policy = CUDAExecutionPolicy()
else
    policy = CPUThreadsExecutionPolicy()
end
println("policy = ", nameof(typeof(policy)), "  threads = ", Threads.nthreads())
set_global_rng!(seed = SEED, method = :philox)

# Physics: the EIC-like weak-strong case of examples/weak_strong_tracking.jl
# without crab cavities, chromaticity and radiation.
wb = (charge = 1.0, mass = PMASS_EV, energy = 275.0e9, n_particle = 0.6881e11, cutoff = 5.0,
      sigx = 95.0e-6, sigy = 8.5e-6, sigz = 6.0e-2, sigd = 6.6e-4, beta_x = 0.8, beta_y = 0.072)
strong = (charge = -1.0, n_particle = 1.7203e11, sigma = (95.0e-6, 8.5e-6, 0.7e-2),
          beta = (0.55, 0.056), alpha = (0.0, 0.0))
tune = (0.228, 0.210, -0.01)

beta_z = wb.sigz / wb.sigd
emit = (wb.sigx^2 / wb.beta_x, wb.sigy^2 / wb.beta_y, wb.sigz * wb.sigd)
weak_r0 = RE * ME0 / wb.mass
ip_point = LinearOptics(; beta = (wb.beta_x, wb.beta_y, beta_z))

beam = Beam(N, policy, Float64; optics = ip_point, emit = emit, cutoff = wb.cutoff, rng_id = 1,
            charge = wb.charge, mc2 = wb.mass, E0 = wb.energy, npart = wb.n_particle)

kbb = wb.charge * strong.charge * strong.n_particle * weak_r0 * wb.mass / wb.energy
klum = strong.n_particle * wb.n_particle / N
gsb = GaussianStrongBeamSpec{Float64}(; kbb = kbb, klum = klum, beta = strong.beta,
        alpha = strong.alpha, sigma = (strong.sigma[1], strong.sigma[2]),
        virtual_drift = :hirata, ns = NS, sigz = strong.sigma[3], slice_method = :equal_area)
one_turn = Linear6DSpec{Float64}(ip_point, ip_point; dmu = (2pi * tune[1], 2pi * tune[2], 2pi * tune[3]))

elems = Any[]
ANGLE > 0 && push!(elems, LorentzBoostSpec(ANGLE))
push!(elems, gsb)
ANGLE > 0 && push!(elems, RevLorentzBoostSpec(ANGLE))
push!(elems, one_turn)
if MOM > 0
    push!(elems, ScheduledObserver(MomentObserver(; name = "weak_beam"), EveryNSteps(start = 0, step = MOM)))
end
line = Tuple(elems)

artifact = RunArtifact(; storage = :memory, capacity = 1024)
task = TrackingTask(line; policy = policy, artifact = artifact, record_turn_times = true)
s0 = beam_statistics(beam)
t0 = time()
execute!(task, beam; turns = TURNS)
GPU && CUDA.synchronize()
wall = time() - t0
times = turn_timings(task)
lum = read(TaskOutput(artifact), :luminosity; name = "strong_beam_1")
s1 = beam_statistics(beam)

sel = (WARMUP + 1):TURNS
tt = times[sel]
@printf("turns=%d N=%d ns=%d angle=%g backend=%s\n", TURNS, N, NS, ANGLE, GPU ? "cuda" : "cpu")
@printf("wall(execute!)=%.3f s  mean/turn (turns %d-%d) = %.5f s  median = %.5f s  sd = %.5f s  min = %.5f max = %.5f\n",
        wall, first(sel), last(sel), mean(tt), median(tt), std(tt), minimum(tt), maximum(tt))
@printf("luminosity per crossing [m^-2]: turn 1 = %.6e  mean(sel) = %.6e  last = %.6e\n",
        lum.value[1], mean(lum.value[sel]), lum.value[end])
println("rms initial = ", s0.rms)
println("rms final   = ", s1.rms)
open(OUT, "w") do io
    println(io, "# octopus case W  N=$N turns=$TURNS ns=$NS angle=$ANGLE backend=$(GPU ? "cuda" : "cpu") seed=$SEED")
    println(io, "# rms_initial\t", join(s0.rms, "\t"))
    println(io, "# rms_final\t", join(s1.rms, "\t"))
    println(io, "turn\tseconds\tluminosity_m2")
    for (k, t) in enumerate(times)
        println(io, k, "\t", t, "\t", lum.value[k])
    end
end
if MOM > 0
    mo = read(TaskOutput(artifact), :moments; name = "weak_beam", orders = 1:2)
    open(replace(OUT, ".tsv" => "_moments.tsv"), "w") do io
        cols = collect(keys(mo))
        println(io, "# columns: ", join(string.(cols), "\t"))
        for r in 1:length(mo[1])
            println(io, join((mo[c][r] for c in cols), "\t"))
        end
    end
end
println("BBSCL-COMPARISON-OCTOPUS-W done -> ", OUT)
