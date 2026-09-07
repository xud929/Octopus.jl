#=
Weak-strong tracking example: a live weak proton beam colliding with a fixed
soft-Gaussian strong beam, through a crab crossing.

This is the clean, production-shaped example. Edit the small `config` block
below, then run from the project root:

    julia --project=. examples/weak_strong_tracking.jl

For a configurable development/testing harness of the same case with
environment-variable toggles (run size, CUDA device selection), see
test/examples/weak_strong_tracking.jl.

The pattern this example follows:

1. Define one `input` named tuple: weak beam, optics, crab cavity, strong beam,
   radiation, output.
2. Build the weak `Beam` directly from the input (including any initial offset).
3. Build element specs in tracking order and place observers where they matter.
4. Build `TrackingTask(line)` and `execute!` it.

Output is ONE run artifact under `result/<seed>/`
(docs/design/run_artifact.md):

- `<case_name>.h5` : `/luminosity/strong_beam_1` (turn and luminosity),
  `/moments/weak_beam`, and the `/execution` ledger; a line with apertures
  would add `/losses`. Read with one handle: `out = TaskOutput(path)`,
  then `read(out, :luminosity; name = "strong_beam_1")`, `read(out,
  :moments; name = "weak_beam")`, `read(out, :execution)`

so seed scans and multi-case studies (different chromaticities, crab
schemes) never collide on output paths — change `case_name` or `seed` and
everything downstream follows.
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus

# Physics input for this weak-proton crab-crossing case.
input = (
    # `case_name` and `seed` name the output directory and files below; every
    # field in this block is consumed — a field nothing reads is the
    # config-that-was-never-read defect class (AGENTS.md Invariants).
    case_name = "weak_strong",
    result_dir = joinpath(@__DIR__, "..", "result"),
    seed = 123456789,

    weak_beam = (
        charge = 1.0,
        mass = PMASS_EV,
        energy = 275.0e9,
        n_particle = 0.6881e11,
        cutoff = 5.0,
        sigx = 95.0e-6,
        sigy = 8.5e-6,
        sigz = 6.0e-2,
        sigd = 6.6e-4,
        beta_x = 0.8,
        beta_y = 0.072,
        alpha = (0.0, 0.0, 0.0),
        zeta = (0.0, 0.0, 0.0, 0.0),
        eta = (0.0, 0.0, 0.0, 0.0),
        coupling = (0.0, 0.0, 0.0, 0.0),
        initial_offset = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0),
    ),

    optics = (
        crab_beta_x = 1300.0,
        crab_beta_y = 100.0,
        # HALF the full crossing angle, which is what LorentzBoostSpec takes and
        # what the crab strength tan(theta)/sqrt(beta_cc*beta*) below assumes.
        # Named `half_crossing_angle` in knob_control.jl, Knobs.jl and
        # validation/crossing_luminosity_anchor.jl -- same quantity, and the
        # factor of two is the classic beam-beam error (2026-08-05_b audit,
        # U16-10).
        crossing_angle = 12.5e-3,
        tune = (0.228, 0.210, -0.01),
        chromaticity = (2.0, 2.0),
    ),

    crab_cavity = (
        frequency = 197.0e6,
        # Relative harmonic weights of the horizontal crab kick; the absolute
        # scale tan(crossing_angle)/sqrt(beta_cc * beta*) is derived below.
        # (4/3, -1/3) is the two-harmonic scheme that cancels the leading
        # nonlinearity of a single 197 MHz cavity; (1.0, 0.0, 0.0) is a
        # single-harmonic crab.
        harmonic_weights = (4.0 / 3.0, -1.0 / 3.0, 0.0),
        strength_y = (0.0, 0.0, 0.0),
        phase = (0.0, 0.0, 0.0),
    ),

    strong_beam = (
        charge = -1.0,
        n_particle = 1.7203e11,
        sigma = (95.0e-6, 8.5e-6, 0.7e-2),
        beta = (0.55, 0.056),
        alpha = (0.0, 0.0),
        z_slices = 7,
        slice_method = :equal_area,
        center = (0.0, 0.0, 0.0),
        angle = (0.0, 0.0, 0.0),
        curvature = (0.0, 0.0, 0.0),
        virtual_drift = :hirata,
        hvoffset = nothing,
    ),

    radiation = (
        damping_turns = (1.0e100, 1.0e100, 1.0e100),
        is_damping = false,
        is_excitation = true,
        alpha = (0.0, 0.0, 0.0),
        zeta = (0.0, 0.0, 0.0, 0.0),
        eta = (0.0, 0.0, 0.0, 0.0),
        coupling = (0.0, 0.0, 0.0, 0.0),
    ),

    output = (
        # The filename derives from `case_name` above — one authority, no
        # copies. `capacity` is the ARTIFACT'S: the one knob for how many
        # rows every producer batches between appends (the per-observer
        # capacities retired 2026-08-18). On a networked filesystem the
        # per-turn write is the dominant observer cost (measured 2.3 ms/turn
        # on a cluster filesystem vs 0.02 local; docs/history/
        # weak_strong_cuda_luminosity_2026_08_11.md), and amortized cost
        # falls monotonically with capacity; do not lower it on shared
        # storage.
        capacity = 1024,
        moment_start = 0,
        moment_step = 1,
    ),
)

# Run configuration. Edit these; the physics `input` above is separate.
config = (
    # WHICH DEVICE THIS RUN USES -- the one line to edit.
    #
    #   :auto          CUDA when a device is functional, CPU threads otherwise.
    #                  The default, so this file runs unmodified on a GPU box
    #                  and on one without (CI has no GPU).
    #   :cuda          one CUDA device, and an ERROR if none is functional.
    #   :threads       CPU logical workers, one process.
    #   :multiprocess  MPI ranks x CPU threads. Read the note in the execution
    #                  policy block below first: this file must then be run in
    #                  PACKAGE mode under a launcher.
    execution = :auto,
    gpu_device = nothing,  # CUDA device index, or nothing for the current one
    threads = :auto,       # CPU logical workers per process
    ranks = :auto,         # :multiprocess only; an integer asserts the count
    turns = 2,           # raise for a real run (production: 1_000_000)
    n_macro = 10_000,    # ~1_024_000 for a production weak beam
)
turns = config.turns
n_macro = config.n_macro
# ---------------------------------------------------------------------------
# Execution policy.
#
# `:auto` prefers CUDA and falls back to CPU threads, and the run PRINTS which
# it chose: a measurement whose device you have to guess at is one you cannot
# report. `:cuda` is the same choice made strict -- it errors rather than
# quietly running on the CPU, which is what you want when the device is the
# point of the run.
# ---------------------------------------------------------------------------
cuda_ok = false
if config.execution === :auto || config.execution === :cuda
    import CUDA
    cuda_ok = CUDA.functional(false)
    config.execution === :cuda && !cuda_ok && error(
        "config.execution = :cuda, but CUDA.functional(false) is false: no " *
        "usable device. Use :auto to fall back to CPU threads, or :threads.")
end

policy = if config.execution === :multiprocess
    # One Octopus process per MPI rank, each with its own CPU logical workers.
    #
    # This choice needs the file run in PACKAGE MODE under a launcher:
    #
    #   mpiexec -n 4 julia --project=. -e 'using Octopus, MPI; include("examples/weak_strong_tracking.jl")'
    #
    # because `MultiProcessExecutionPolicy` reaches a real communicator only
    # through the `OctopusMPIExt` package extension, and a package extension
    # attaches only to a PACKAGE -- which the `include` of src/Octopus.jl at the
    # top of this file is not. Without the extension every rank would be its own
    # communicator of one, `ranks = :auto` would accept that, and `mpiexec -n 4`
    # would run FOUR whole simulations racing on one artifact path: exit 0,
    # plausible timings, wrong answer. So it is refused instead.
    Base.get_extension(Main.Octopus, :OctopusMPIExt) === nothing && error(
        "config.execution = :multiprocess needs the OctopusMPIExt extension, " *
        "which attaches only when Octopus is loaded as a PACKAGE with MPI also " *
        "loaded. Run: mpiexec -n <P> julia --project=. -e 'using Octopus, MPI; " *
        "include(\"examples/weak_strong_tracking.jl\")'")
    MultiProcessExecutionPolicy(threads = config.threads, ranks = config.ranks)
elseif cuda_ok
    CUDAExecutionPolicy(device = config.gpu_device)
else
    CPUThreadsExecutionPolicy(threads = config.threads)
end
println("execution policy = ", nameof(typeof(policy)),
        config.execution === :auto ?
            (cuda_ok ? "  (auto: a CUDA device is available)" :
                       "  (auto: no CUDA device, running on CPU threads)") : "")
set_global_rng!(seed = input.seed, method = :philox)

wb = input.weak_beam
beta_z = wb.sigz / wb.sigd
emit = (wb.sigx^2 / wb.beta_x, wb.sigy^2 / wb.beta_y, wb.sigz * wb.sigd)
weak_r0 = RE * ME0 / wb.mass

beam = Beam(n_macro, policy, Float64;
    beta = (wb.beta_x, wb.beta_y, beta_z),
    alpha = wb.alpha,
    emit = emit,
    cutoff = wb.cutoff,
    rng_id = 1,
    charge = wb.charge,
    mc2 = wb.mass,
    E0 = wb.energy,
    r0 = weak_r0,
    npart = wb.n_particle,
    zeta = wb.zeta,
    eta = wb.eta,
    R = wb.coupling,
    initial_offset = wb.initial_offset,
)

opt = input.optics
cckick = tan(opt.crossing_angle) / sqrt(wb.beta_x * opt.crab_beta_x)
cc_strength_x = cckick .* input.crab_cavity.harmonic_weights

tccb2ip = Linear6DSpec{Float64}(;
    beta1 = (opt.crab_beta_x, opt.crab_beta_y, beta_z),
    beta2 = (wb.beta_x, wb.beta_y, beta_z),
    alpha1 = (0.0, 0.0, 0.0),
    alpha2 = (0.0, 0.0, 0.0),
    dmu = (pi / 2.0, 0.0, 0.0),
    zeta1 = (0.0, 0.0, 0.0, 0.0),
    eta1 = (0.0, 0.0, 0.0, 0.0),
    R1 = (0.0, 0.0, 0.0, 0.0),
    zeta2 = (0.0, 0.0, 0.0, 0.0),
    eta2 = (0.0, 0.0, 0.0, 0.0),
    R2 = (0.0, 0.0, 0.0, 0.0),
)
tccb2ip_inv = Linear6DSpec{Float64}(matrix = inv(Matrix(Linear6D(tccb2ip))))

ip2tcca = Linear6DSpec{Float64}(;
    beta1 = (wb.beta_x, wb.beta_y, beta_z),
    beta2 = (opt.crab_beta_x, opt.crab_beta_y, beta_z),
    alpha1 = (0.0, 0.0, 0.0),
    alpha2 = (0.0, 0.0, 0.0),
    dmu = (pi / 2.0, 0.0, 0.0),
    zeta1 = (0.0, 0.0, 0.0, 0.0),
    eta1 = (0.0, 0.0, 0.0, 0.0),
    R1 = (0.0, 0.0, 0.0, 0.0),
    zeta2 = (0.0, 0.0, 0.0, 0.0),
    eta2 = (0.0, 0.0, 0.0, 0.0),
    R2 = (0.0, 0.0, 0.0, 0.0),
)
ip2tcca_inv = Linear6DSpec{Float64}(matrix = inv(Matrix(Linear6D(ip2tcca))))

tccb = ThinCrabCavitySpec{3}(input.crab_cavity.frequency;
    strengthX = cc_strength_x,
    strengthY = input.crab_cavity.strength_y,
    phase = input.crab_cavity.phase,
)
tcca = ThinCrabCavitySpec{3}(input.crab_cavity.frequency;
    strengthX = cc_strength_x,
    strengthY = input.crab_cavity.strength_y,
    phase = input.crab_cavity.phase,
)

one_turn = Linear6DSpec{Float64}(;
    beta1 = (wb.beta_x, wb.beta_y, beta_z),
    beta2 = (wb.beta_x, wb.beta_y, beta_z),
    alpha1 = (0.0, 0.0, 0.0),
    alpha2 = (0.0, 0.0, 0.0),
    dmu = (2pi * opt.tune[1], 2pi * opt.tune[2], 2pi * opt.tune[3]),
    zeta1 = (0.0, 0.0, 0.0, 0.0),
    eta1 = (0.0, 0.0, 0.0, 0.0),
    R1 = (0.0, 0.0, 0.0, 0.0),
    zeta2 = (0.0, 0.0, 0.0, 0.0),
    eta2 = (0.0, 0.0, 0.0, 0.0),
    R2 = (0.0, 0.0, 0.0, 0.0),
)

chrom = ChromaticityKickSpec{Float64}(;
    xi = opt.chromaticity,
    beta = (wb.beta_x, wb.beta_y, beta_z),
    alpha = wb.alpha,
    zeta = (0.0, 0.0, 0.0, 0.0),
    eta = (0.0, 0.0, 0.0, 0.0),
    R = (0.0, 0.0, 0.0, 0.0),
)

strong = input.strong_beam
kbb = wb.charge * strong.charge * strong.n_particle * weak_r0 * wb.mass / wb.energy
klum = strong.n_particle * wb.n_particle / n_macro
thin_strong = ThinStrongBeamSpec{Float64}(;
    kbb = kbb,
    klum = klum,
    beta = strong.beta,
    alpha = strong.alpha,
    sigma = (strong.sigma[1], strong.sigma[2]),
    center = strong.center,
    angle = strong.angle,
    curvature = strong.curvature,
    virtual_drift = strong.virtual_drift,
)
gsb = GaussianStrongBeamSpec{Float64}(;
    thin = thin_strong,
    ns = strong.z_slices,
    sigz = strong.sigma[3],
    slice_method = strong.slice_method,
    hvoffset = strong.hvoffset,
)

rad = input.radiation
radiation = LumpedRadSpec{Float64}(;
    damping_turns = rad.damping_turns,
    beta = (wb.beta_x, wb.beta_y, beta_z),
    alpha = rad.alpha,
    sigma = (wb.sigx, wb.sigy, wb.sigz),
    zeta = rad.zeta,
    eta = rad.eta,
    R = rad.coupling,
    is_damping = rad.is_damping,
    is_excitation = rad.is_excitation,
    rng_id = 2,
)

# Output lands under result/<seed>/, named by the case, so seed scans and
# multi-case studies never collide.
outdir = joinpath(input.result_dir, string(input.seed))
mkpath(outdir)
artifact_path = joinpath(outdir, input.case_name * ".h5")
# The run artifact attaches at the TASK: the strong beam's luminosity channel
# lands in it per turn, alongside the execution ledger. The moment observer
# stays a line entry -- its position is physical -- but is a named VIEW into
# the same file.
moment_observer = ScheduledObserver(
    MomentObserver(; name = "weak_beam"),
    EveryNSteps(
        start = input.output.moment_start,
        step = input.output.moment_step,
    ),
)

line_specs = (
    tccb2ip_inv,
    tccb,
    tccb2ip,
    LorentzBoostSpec(opt.crossing_angle),
    gsb,
    RevLorentzBoostSpec(opt.crossing_angle),
    ip2tcca,
    tcca,
    ip2tcca_inv,
    one_turn,
    chrom,
    radiation,
    moment_observer,
)
# `policy = policy` is load-bearing, not tidiness. Without it
# `task.policy === nothing` and `execute!` resolves a FRESH default, so the
# policy built above would reach only `Beam(...)` and be discarded -- the
# strong-strong example beside this one already passes it (2026-08-05_b audit,
# U21-17, and its harness twin got the same fix on 2026-09-06).
#
# It is fatal rather than cosmetic for `:multiprocess`: an inferred default is a
# single-process policy, so every rank would track the WHOLE beam and write the
# same paths. Caught by the library's launcher tripwire, which warned
# "PMI_SIZE=2 ... the execution policy in force is a single-process one" on the
# first divided run of this file.
task = TrackingTask(line_specs;
    policy = policy,
    artifact = RunArtifact(artifact_path; capacity = input.output.capacity))
execute!(task, beam; turns = turns)

stats = beam_statistics(beam)
println("turns = ", turns)
println("n_macro = ", n_macro)
println("artifact = ", artifact_path)
println("  /luminosity/strong_beam_1, /moments/weak_beam, /execution")
# `beam_statistics` is a purely local reduction -- no collective, no shard
# argument -- so under `:multiprocess` it describes THIS RANK'S SHARD, not the
# beam. Labelled accordingly, because a reader comparing a divided run's rms
# against a single-process one would otherwise be comparing a shard with a beam
# and calling the difference physics.
_rms_label(name) = policy isa MultiProcessExecutionPolicy ?
    "$(name) (this rank's shard, not the whole beam)" : name
println(_rms_label("rms"), " = ", stats.rms)
