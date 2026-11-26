#=
Octopus side of the BBSCL comparison, case L (element-by-element lattice): a 64-cell
FODO ring of thick drifts, quadrupoles, sector bends and sextupoles with one thin RF
cavity, tracked turn by turn. The BBSCL twin is written by gen_bbscl_L.py from the
optics this script prints in OCT_MODE=optics.

Cell (15 m): QF(0.5) SF(0.2) D(1.8) B(3.0) D(2.0) QD(0.5) SD(0.2) D(1.8) B(3.0) D(2.0);
64 cells = 960 m, 128 bends of 2 pi/128; RF h = 320, 2 MV, phase 0 at the start of the ring.
Proton beam at 275 GeV, geometric emittances 1e-8 m (x, y), sigma_delta 1e-7 (so that
dispersion, which neither initial distribution carries, is irrelevant), centroid offsets
(1e-4, 0, 1e-4, 0, 1e-3, 0) so that the tunes can be read off the centroid motion.

Environment (defaults in parentheses):
  OCT_MODE (track)     optics = Twiss analysis only (prints and writes lattice_optics.txt); track = run
  OCT_GPU (1)          1 = CUDA, 0 = CPU threads
  OCT_N (1048576)      macroparticles (BBSCL needs a multiple of 256)
  OCT_TURNS (200), OCT_WARMUP (20)
  OCT_NST (1), OCT_ORDER (2)   integrator slices and order of every thick magnet
  OCT_NCELL (64)       FODO cells (64 = 960 m; the BBSCL twin must be generated with the same --ncell)
  OCT_MOMENTS_EVERY (0)  k = MomentObserver every k turns (1 for the tune measurement)
  OCT_OPTICS (result/bbscl_comparison_2026_11_22/lattice_optics.txt)  the file optics mode writes / track mode reads
  OCT_SEED (123456789), OCT_OUT
=#
if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "..", "src", "Octopus.jl"))
end
using .Octopus
using Statistics
using Printf
using DelimitedFiles

envi(n, d) = parse(Int, get(ENV, n, string(d)))
const MODE   = lowercase(get(ENV, "OCT_MODE", "track"))
const GPU    = envi("OCT_GPU", 1) == 1
const N      = envi("OCT_N", 1_048_576)
const TURNS  = envi("OCT_TURNS", 200)
const WARMUP = envi("OCT_WARMUP", 20)
const NST    = envi("OCT_NST", 1)
const ORDER  = envi("OCT_ORDER", 2)
const MOM    = envi("OCT_MOMENTS_EVERY", 0)
const SEED   = envi("OCT_SEED", 123456789)
const OPTICS = get(ENV, "OCT_OPTICS", joinpath(@__DIR__, "lattice_optics.txt"))
const NCELL  = envi("OCT_NCELL", 64)
tag = "N$(N)_c$(NCELL)_nst$(NST)_o$(ORDER)_" * (GPU ? "cuda" : "cpu")
const OUT = get(ENV, "OCT_OUT", joinpath(@__DIR__, "octopus_L_" * tag * ".tsv"))

const E0 = 275.0e9
const KQ = 0.36          # quadrupole gradient k1 [m^-2]  (BBSCL K1 = k1 L = 0.18)
const K2F, K2D = 1.0, -2.0   # sextupole k2 [m^-3]      (BBSCL K2 = k2 L)
const LQ, LS, LB = 0.5, 0.2, 3.0
const ANGLE = 2pi / (2 * NCELL)
const RF_V, RF_H = 2.0e6, 320
const EMIT = (1.0e-8, 1.0e-8)
const SIGD = 1.0e-7
const OFFSET = (1.0e-4, 0.0, 1.0e-4, 0.0, 1.0e-3, 0.0)

mag(spec) = spec
qf = QuadrupoleSpec(; L = LQ, k1 = KQ, nst = NST, integrator_order = ORDER, fringe = :none)
qd = QuadrupoleSpec(; L = LQ, k1 = -KQ, nst = NST, integrator_order = ORDER, fringe = :none)
sf = SextupoleSpec(; L = LS, k2 = K2F, nst = NST, integrator_order = ORDER, fringe = :none)
sd = SextupoleSpec(; L = LS, k2 = K2D, nst = NST, integrator_order = ORDER, fringe = :none)
d18 = DriftSpec(; L = 1.8)
d20 = DriftSpec(; L = 2.0)
bend = SBendSpec(; L = LB, angle = ANGLE, nst = NST, integrator_order = ORDER, bend_fringe = true, fringe = :none)
beta0, gamma0 = reference_beta_gamma(E0, PMASS_EV)
const RF_F = RF_H * beta0 * 299792458.0 / (NCELL * 15.0)   # f = h beta c / C, given explicitly so the bare analysis can run
rf = ThinRFCavitySpec(RF_F; voltage = RF_V, e0 = E0, mc2 = PMASS_EV, charge = 1, phase = 0.0)
cell = Any[qf, sf, d18, bend, d20, qd, sd, d18, bend, d20]
elements = Any[rf]
for _ in 1:NCELL
    append!(elements, cell)
end
println("elements per turn = ", length(elements), "  circumference = ", NCELL * 15.0, " m")

if MODE == "optics"
    ring = BeamLine("FODO_RING", elements...)
    r1 = analyze(TwissDispersionAnalysis(strict = false, emittances = (EMIT[1], EMIT[2], 1.0e-9)), ring)
    println("run 1 status = ", r1.status, "  longitudinal selection = ", r1.dispersion.longitudinal)
    r = analyze(TwissDispersionAnalysis(strict = false, emittances = (EMIT[1], EMIT[2], 1.0e-9),
                                        longitudinal_mode = r1.dispersion.longitudinal), ring)
    println("run 2 status = ", r.status)
    for s in r.degradations; println("  degradation: ", s); end
    for s in r.failures; println("  failure: ", s); end
    point = linear_optics(r)
    println("beta = ", point.twiss.beta, "  alpha = ", point.twiss.alpha)
    tunes = Float64[]
    for (j, mu) in enumerate(r.physical.tunes)
        q = mu / (2pi)
        println("mode ", j, ": mu = ", mu, "  Q = ", q, mu > pi ? "  (1 - Q = $(1 - q))" : "")
        push!(tunes, q)
    end
    open(OPTICS, "w") do io
        println(io, "# beta_x alpha_x beta_y alpha_y beta_z Q1 Q2 Q3 ncell (Q = mu/2pi as the analysis orients it)")
        println(io, join(string.((point.twiss.beta[1], point.twiss.alpha[1], point.twiss.beta[2],
                                  point.twiss.alpha[2], point.twiss.beta[3], tunes..., NCELL)), " "))
    end
    println("wrote ", OPTICS)
    exit(0)
end

isfile(OPTICS) || error("run OCT_MODE=optics first: $OPTICS not found")
opt = vec(readdlm(OPTICS, comments = true, comment_char = '#'))
bx, ax, by, ay, bz = opt[1:5]
# The optics file comes from the ONE-cell analysis (OCT_MODE=optics OCT_NCELL=1): the periodic
# transverse Twiss of the cell is the ring's, and with h and V fixed the synchrotron tune is
# independent of the circumference, so beta_z = C eta/(2 pi Q_s) scales with the cell count.
opt_ncell = length(opt) >= 9 ? Int(opt[9]) : 1
if opt_ncell != NCELL
    opt_ncell == 1 || error("optics file is for ncell=$(opt_ncell), not 1 or $(NCELL)")
    bz *= NCELL
end
println("optics from file: beta = ", (bx, by, bz), "  alpha = ", (ax, ay))

if GPU
    import CUDA
    CUDA.functional(false) || error("OCT_GPU=1 but CUDA is not functional")
    policy = CUDAExecutionPolicy()
else
    policy = CPUThreadsExecutionPolicy()
end
println("policy = ", nameof(typeof(policy)), "  threads = ", Threads.nthreads())
set_global_rng!(seed = SEED, method = :philox)

point = LinearOptics(; beta = (bx, by, bz), alpha = (ax, ay, 0.0))
emit_z = (bz * SIGD) * SIGD
beam = Beam(N, policy, Float64; optics = point, emit = (EMIT[1], EMIT[2], emit_z), cutoff = 5.0, rng_id = 1,
            charge = 1.0, mc2 = PMASS_EV, E0 = E0, npart = 1.0e11,
            initial_offset = OFFSET)
line_elems = copy(elements)
if MOM > 0
    push!(line_elems, ScheduledObserver(MomentObserver(; name = "beam"), EveryNSteps(start = 0, step = MOM)))
end
line = Tuple(line_elems)
artifact = RunArtifact(; storage = :memory, capacity = 1024)
task = TrackingTask(line; policy = policy, artifact = artifact, record_turn_times = true)
s0 = beam_statistics(beam)
t0 = time()
execute!(task, beam; turns = TURNS)
GPU && CUDA.synchronize()
wall = time() - t0
times = turn_timings(task)
s1 = beam_statistics(beam)
sel = (WARMUP + 1):TURNS
tt = times[sel]
@printf("turns=%d N=%d ncell=%d nst=%d order=%d backend=%s elements=%d\n", TURNS, N, NCELL, NST, ORDER, GPU ? "cuda" : "cpu", length(elements))
@printf("wall(execute!)=%.3f s  mean/turn (turns %d-%d) = %.5f s  median = %.5f s  sd = %.5f s  min = %.5f max = %.5f\n",
        wall, first(sel), last(sel), mean(tt), median(tt), std(tt), minimum(tt), maximum(tt))
println("rms initial = ", s0.rms)
println("rms final   = ", s1.rms)
println("mean final  = ", s1.mean)
open(OUT, "w") do io
    println(io, "# octopus case L  N=$N turns=$TURNS ncell=$NCELL nst=$NST order=$ORDER backend=$(GPU ? "cuda" : "cpu") seed=$SEED elements=$(length(elements))")
    println(io, "# rms_initial\t", join(s0.rms, "\t")); println(io, "# rms_final\t", join(s1.rms, "\t"))
    println(io, "turn\tseconds")
    for (k, t) in enumerate(times); println(io, k, "\t", t); end
end
if MOM > 0
    mo = read(TaskOutput(artifact), :moments; name = "beam", orders = 1:2)
    open(replace(OUT, ".tsv" => "_moments.tsv"), "w") do io
        cols = collect(keys(mo))
        println(io, "# columns: ", join(string.(cols), "\t"))
        for r in 1:length(mo[1]); println(io, join((mo[c][r] for c in cols), "\t")); end
    end
end
println("BBSCL-COMPARISON-OCTOPUS-L done -> ", OUT)
