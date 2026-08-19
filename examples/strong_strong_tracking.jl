#=
Strong-strong tracking example: a crab-crossing electron-proton collision with
two live beams colliding through a Poisson solver.

This is the clean, production-shaped example meant as a precedent for writing
your own strong-strong simulations. Edit the small `config` block below, then run
from the project root:

    julia --project=. examples/strong_strong_tracking.jl

For a configurable development/testing harness of the *same* case with
environment-variable toggles (solver A/B selection, CUDA launch tuning,
per-phase timing, and diagnostic/output switches used while developing the
solvers), see test/examples/strong_strong_tracking.jl.

The pattern this example follows:

1. Define one `input` named tuple: beams, optics, crab cavities, slicing, solver.
2. Build an execution policy (CPU threads or CUDA) from `config`.
3. Build both live `Beam`s from the input.
4. Build a Poisson solver. PIC is used here; the soft-Gaussian, spectral, and
   Gaussian-subtracted-PIC alternatives are shown commented below and share the
   same interface (see `?AbstractPoissonSolver`).
5. Build both ring lines with matching `StrongStrongCollision` markers.
6. Build a `StrongStrongTask` and `execute!` it.

Output is ONE run artifact under `result/<seed>/` (docs/design/run_artifact.md):

- `<case_name>.h5` : `/luminosity/ip` (turn and per-collision luminosity),
  `/moments/electron` and `/moments/proton`, and the `/execution` ledger.
  Read with one handle: `out = TaskOutput(path)`, then
  `read(out, :luminosity; name = "ip")`, `read(out, :moments;
  name = "electron")` (or `MomentOutput(path; name = "electron")` for
  Moment-aware selection), `read(out, :execution)`.
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus

# ---------------------------------------------------------------------------
# Run configuration. Edit these; the physics `input` below is separate.
# ---------------------------------------------------------------------------
config = (
    use_gpu = false,       # true routes beam storage and tracking to CUDA
    turns = 2,             # small for an interactive check; raise for a real run
    n_macro_ele = 200,     # ~2_560_000 for a production electron beam
    n_macro_pro = 200,     # ~1_024_000 for a production proton beam
)

# ---------------------------------------------------------------------------
# Physics input (the collision case). Independent of the run configuration.
# ---------------------------------------------------------------------------
input = (
    # `case_name` and `seed` name the output directory and files below.
    case_name = "pic_hcc",
    result_dir = joinpath(@__DIR__, "..", "result"),
    seed = 123456789,
    # HALF the full crossing angle, which is what LorentzBoostSpec takes and
    # what the crab strength tan(theta)/sqrt(beta_cc*beta*) below assumes.
    # Named `half_crossing_angle` in knob_control.jl, Knobs.jl and
    # validation/crossing_luminosity_anchor.jl -- same quantity, and the
    # factor of two is the classic beam-beam error (2026-08-05_b audit,
    # U16-10).
    crossing_angle = 12.5e-3,

    electron = (
        charge = -1.0,
        mass = EMASS_EV,
        energy = 10.0e9,
        n_particle = 1.7203e11,
        cutoff = 5.0,
        sigma = (106.0e-6, 9.5e-6, 0.7e-2),
        beta = (0.55, 0.056, 0.7e-2 / 5.5e-4),
        alpha = (0.0, 0.0, 0.0),
        crab_beta = (150.0, 30.0, 0.7e-2 / 5.5e-4),
        tune = (0.08, 0.14, -0.069),
        chromaticity = (1.0, 1.0),
        crab_frequency = 394.0e6,
        crab_strength_x = (tan(12.5e-3) / sqrt(150.0 * 0.55), 0.0, 0.0),
        crab_strength_y = (0.0, 0.0, 0.0),
        crab_phase = (0.0, 0.0, 0.0),
        radiation_damping_turns = (4000.0, 4000.0, 2000.0),
    ),

    proton = (
        charge = 1.0,
        mass = PMASS_EV,
        energy = 275.0e9,
        n_particle = 0.6881e11,
        cutoff = 5.0,
        sigma = (95.0e-6, 8.5e-6, 6.0e-2),
        beta = (0.8, 0.072, 6.0e-2 / 6.6e-4),
        alpha = (0.0, 0.0, 0.0),
        crab_beta = (1300.0, 30.0, 6.0e-2 / 6.6e-4),
        tune = (0.228, 0.210, -0.01),
        chromaticity = (2.0, 2.0),
        crab_frequency = 197.0e6,
        crab_strength_x = (
            tan(12.5e-3) / sqrt(1300.0 * 0.8) * 4.0 / 3.0,
            -tan(12.5e-3) / sqrt(1300.0 * 0.8) / 3.0,
            0.0,
        ),
        crab_strength_y = (0.0, 0.0, 0.0),
        crab_phase = (0.0, 0.0, 0.0),
    ),

    slicing = (zslice = 15, center = :centroid),

    solver = (
        pic_grid = (128, 128),
        pic_deposit_method = :CIC,
        pic_green_type = :integrated,
        pic_slice_pair_green_min_ratio = 0.50,
        pic_slice_pair_green_growth = 0.25,
    ),

    output = (
        # The filename derives from `case_name` above — one authority, no
        # copies (the weak-strong pair's 2026-08-11 fix, same class).
        # `capacity` is the ARTIFACT'S: the one knob for how many rows every
        # producer batches between appends (the per-observer capacities
        # retired 2026-08-18); networked filesystems punish less
        # (docs/history/weak_strong_cuda_luminosity_2026_08_11.md). The
        # artifact holds one file handle open across execute!.
        moment_start = 0,
        moment_step = 1,
        capacity = 1024,
    ),
)

# ---------------------------------------------------------------------------
# Execution policy and live beams.
# ---------------------------------------------------------------------------
if config.use_gpu
    import CUDA
    CUDA.functional(false) || error("config.use_gpu is true, but CUDA is not functional")
end
policy = config.use_gpu ? CUDAExecutionPolicy() : CPUThreadsExecutionPolicy()

set_global_rng!(seed = input.seed, method = :philox)

ele = input.electron
pro = input.proton

beam_ele = Beam(config.n_macro_ele, policy, Float64;
    beta = ele.beta, alpha = ele.alpha, sigma = ele.sigma, cutoff = ele.cutoff,
    rng_id = 1, charge = ele.charge, mc2 = ele.mass, E0 = ele.energy,
    r0 = RE * ME0 / ele.mass, npart = ele.n_particle,
)
beam_pro = Beam(config.n_macro_pro, policy, Float64;
    beta = pro.beta, alpha = pro.alpha, sigma = pro.sigma, cutoff = pro.cutoff,
    rng_id = 2, charge = pro.charge, mc2 = pro.mass, E0 = pro.energy,
    r0 = RE * ME0 / pro.mass, npart = pro.n_particle,
)

slicing = LongitudinalSlicing(;
    method = :normal_quantile,
    nslices = input.slicing.zslice,
    center_position = input.slicing.center,
)

# ---------------------------------------------------------------------------
# Poisson solver. All strong-strong solvers share the common keywords where the
# role applies (`slicing`, `longitudinal_kick`, `kbb1`/`kbb2`, and `grid` for
# the mesh-based solvers; the soft-Gaussian solver is grid-free); see
# `?AbstractPoissonSolver`. PIC is used here; alternatives are commented below.
# ---------------------------------------------------------------------------
solver = PICPoissonSolver(;
    slicing = slicing,
    grid = input.solver.pic_grid,
    deposit_method = input.solver.pic_deposit_method,
    green_type = input.solver.pic_green_type,
    green_cache = :slice_pair,
    slice_pair_green_min_ratio = input.solver.pic_slice_pair_green_min_ratio,
    slice_pair_green_growth = input.solver.pic_slice_pair_green_growth,
    longitudinal_kick = true,
    # The luminosity schedule lives HERE, on the solver: e.g.
    # `luminosity_schedule = EveryNSteps(step = 10)` puts a luminosity row in
    # the artifact every 10th turn -- skipped turns still get their beam-beam
    # kicks and simply have no row in /luminosity/ip (each collision keeps
    # its own turn axis). Default: every turn. Every solver takes it; for
    # the grid solvers it also skips the evaluation cost, while for
    # GaussianPoissonSolver (whose luminosity is a free byproduct of the
    # kick) it gates reporting only.
)

# Sliced soft-Gaussian (Bassetti-Erskine) solver:
# solver = GaussianPoissonSolver(; slicing = slicing, longitudinal_kick = true)
#
# Spectral sine-series solver (recommended flat-beam setting shown):
# solver = SpectralPoissonSolver(; slicing = slicing, grid = (127, 383),
#                                domain_factor = 8.0, method = :grid,
#                                longitudinal_kick = true)
#
# Gaussian-subtracted PIC hybrid (grid=(64,64) matches PIC@128 systematic
# accuracy at lower cost; see docs/theory/gaussian_subtracted_pic_solver.md):
# solver = GaussianPICPoissonSolver(; slicing = slicing, grid = (64, 64),
#                                   longitudinal_kick = true)

# ---------------------------------------------------------------------------
# Beam lines. Each ring carries the same collision marker at the IP, framed by
# crab-cavity transport, the Lorentz boost pair, and one-turn optics.
# ---------------------------------------------------------------------------
electron_tccb2ip = Linear6DSpec{Float64}(;
    beta1 = ele.crab_beta, beta2 = ele.beta, alpha1 = ele.alpha, alpha2 = ele.alpha,
    dmu = (pi / 2.0, 0.0, 0.0),
)
electron_tccb2ip_inv = Linear6DSpec{Float64}(matrix = inv(Matrix(Linear6D(electron_tccb2ip))))
electron_ip2tcca = Linear6DSpec{Float64}(;
    beta1 = ele.beta, beta2 = ele.crab_beta, alpha1 = ele.alpha, alpha2 = ele.alpha,
    dmu = (pi / 2.0, 0.0, 0.0),
)
electron_ip2tcca_inv = Linear6DSpec{Float64}(matrix = inv(Matrix(Linear6D(electron_ip2tcca))))
electron_tccb = ThinCrabCavitySpec{3}(ele.crab_frequency;
    strengthX = ele.crab_strength_x, strengthY = ele.crab_strength_y, phase = ele.crab_phase)
electron_tcca = ThinCrabCavitySpec{3}(ele.crab_frequency;
    strengthX = ele.crab_strength_x, strengthY = ele.crab_strength_y, phase = ele.crab_phase)
electron_one_turn = Linear6DSpec{Float64}(;
    beta1 = ele.beta, beta2 = ele.beta, alpha1 = ele.alpha, alpha2 = ele.alpha,
    dmu = 2pi .* ele.tune)
electron_chrom = ChromaticityKickSpec{Float64}(; xi = ele.chromaticity, beta = ele.beta, alpha = ele.alpha)
electron_rad = LumpedRadSpec{Float64}(;
    damping_turns = ele.radiation_damping_turns, beta = ele.beta, alpha = ele.alpha,
    sigma = ele.sigma, is_damping = true, is_excitation = true, rng_id = 3)

proton_tccb2ip = Linear6DSpec{Float64}(;
    beta1 = pro.crab_beta, beta2 = pro.beta, alpha1 = pro.alpha, alpha2 = pro.alpha,
    dmu = (pi / 2.0, 0.0, 0.0))
proton_tccb2ip_inv = Linear6DSpec{Float64}(matrix = inv(Matrix(Linear6D(proton_tccb2ip))))
proton_ip2tcca = Linear6DSpec{Float64}(;
    beta1 = pro.beta, beta2 = pro.crab_beta, alpha1 = pro.alpha, alpha2 = pro.alpha,
    dmu = (pi / 2.0, 0.0, 0.0))
proton_ip2tcca_inv = Linear6DSpec{Float64}(matrix = inv(Matrix(Linear6D(proton_ip2tcca))))
proton_tccb = ThinCrabCavitySpec{3}(pro.crab_frequency;
    strengthX = pro.crab_strength_x, strengthY = pro.crab_strength_y, phase = pro.crab_phase)
proton_tcca = ThinCrabCavitySpec{3}(pro.crab_frequency;
    strengthX = pro.crab_strength_x, strengthY = pro.crab_strength_y, phase = pro.crab_phase)
proton_one_turn = Linear6DSpec{Float64}(;
    beta1 = pro.beta, beta2 = pro.beta, alpha1 = pro.alpha, alpha2 = pro.alpha,
    dmu = 2pi .* pro.tune)
proton_chrom = ChromaticityKickSpec{Float64}(; xi = pro.chromaticity, beta = pro.beta, alpha = pro.alpha)

lb = LorentzBoostSpec(input.crossing_angle)
rlb = RevLorentzBoostSpec(input.crossing_angle)
ip = StrongStrongCollision(:ip; poisson_solver = solver)

# Output lands under result/<seed>/, named by the case — the same layout as
# the weak-strong example, so seed scans and multi-case studies never collide.
# One artifact per task: the moment probes are named VIEWS into it, placed in
# their lines; the luminosity channel comes from the collision itself.
outdir = joinpath(input.result_dir, string(input.seed))
mkpath(outdir)
artifact_path = joinpath(outdir, input.case_name * ".h5")
moment_schedule = EveryNSteps(;
    start = input.output.moment_start, step = input.output.moment_step)
electron_observer = ScheduledObserver(
    MomentObserver(; name = "electron"), moment_schedule)
proton_observer = ScheduledObserver(
    MomentObserver(; name = "proton"), moment_schedule)

line_ele = (
    electron_tccb2ip_inv, electron_tccb, electron_tccb2ip, lb, ip, rlb,
    electron_ip2tcca, electron_tcca, electron_ip2tcca_inv,
    electron_one_turn, electron_chrom, electron_rad, electron_observer,
)
line_pro = (
    proton_tccb2ip_inv, proton_tccb, proton_tccb2ip, lb, ip, rlb,
    proton_ip2tcca, proton_tcca, proton_ip2tcca_inv,
    proton_one_turn, proton_chrom, proton_observer,
)

# ---------------------------------------------------------------------------
# Build and run.
# ---------------------------------------------------------------------------
# `policy` is passed here as well as to `Beam(...)`: a task built without it
# resolves a fresh default at execute time, so any non-default execution choice
# would reach beam construction and be silently dropped for the tracking itself
# (2026-08-05_b audit, U21-17).
# The run artifact attaches at the TASK -- pair-level luminosity belongs to
# neither line -- and every product lands in the one file: the collision's
# luminosity channel, both moment views, the execution ledger.
# `RunArtifact(path; append = true)` would continue one file across
# executions and restarts instead of rewriting it per run; `capacity` is the
# one buffering knob for every producer (worthwhile on networked
# filesystems).
task = StrongStrongTask(line_ele, line_pro; policy = policy,
                        artifact = RunArtifact(artifact_path;
                                               capacity = input.output.capacity))
execute!(task, beam_ele, beam_pro; turns = config.turns)

stats_ele = beam_statistics(beam_ele)
stats_pro = beam_statistics(beam_pro)
println("turns = ", config.turns)
println("poisson_solver = ", nameof(typeof(solver)))
println("artifact = ", artifact_path)
println("  /luminosity/ip, /moments/electron, /moments/proton, /execution")
println("electron rms = ", stats_ele.rms)
println("proton rms = ", stats_pro.rms)
