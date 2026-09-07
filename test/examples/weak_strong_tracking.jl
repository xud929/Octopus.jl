using LinearAlgebra

#=
Weak-strong tracking example with crab crossing.

This is the CONFIGURABLE development/testing harness (run size and CUDA device
via OCTOPUS_* environment variables). For the clean, production-shaped example
meant as a user guideline (no environment variables), see
examples/weak_strong_tracking.jl.

Run from the Octopus project root:

    julia --project=. test/examples/weak_strong_tracking.jl

The default run is intentionally small: 2 turns and 10000 macroparticles. Use
environment variables for larger runs without editing the physics input:

    OCTOPUS_TURNS=1000 OCTOPUS_N_MACRO=1024000 julia --project=. test/examples/weak_strong_tracking.jl

Run the same example with CUDA storage and CUDA tracking kernels:

    OCTOPUS_USE_GPU=1 julia --project=. test/examples/weak_strong_tracking.jl

Select a CUDA device explicitly:

    OCTOPUS_USE_GPU=1 OCTOPUS_CUDA_DEVICE=1 julia --project=. test/examples/weak_strong_tracking.jl

Choose the CPU logical-worker count (default `auto`, meaning the process's
default thread count):

    OCTOPUS_CPU_THREADS=8 julia --project=. --threads=8 test/examples/weak_strong_tracking.jl

Run divided across MPI ranks -- one Octopus process per rank, each with its own
CPU logical workers. OCTOPUS_CPU_THREADS sets the per-rank thread count (the
same keyword as above), and OCTOPUS_RANKS optionally states the process count
the run must match; left `auto` it accepts whatever the launcher started:

    OCTOPUS_USE_MPI=1 OCTOPUS_CPU_THREADS=8 OCTOPUS_RANKS=16 mpiexec -n 16 julia --project=. test/examples/weak_strong_tracking.jl

Setting OCTOPUS_MP is an error, not a no-op.
docs/history/production_benchmark_2026_09_06.md names that spelling -- it is
what the scratch copies behind that measurement used -- and history is frozen,
so the record still says it. An unread variable would have made a threads-only
run look like an MPI one, so the dead spelling is refused by name.

This arm needs an environment where BOTH Octopus and MPI resolve as PACKAGES.
The multi-process policy reaches a communicator only through the OctopusMPIExt
package extension, and that extension does not load for the `include` of
src/Octopus.jl this harness uses by default -- so OCTOPUS_USE_MPI=1 loads
Octopus as a package instead, and refuses to run if the extension is still
absent. Without it every rank would be its own communicator of one -- which
OCTOPUS_RANKS=auto accepts -- and every process would track the whole beam.
Octopus's own launcher tripwire catches that under the six launcher variables
it knows (PMI_SIZE and its siblings); this refusal fires earlier, at load,
names the cause rather than a size disagreement, and covers the launchers that
tripwire does not know. OCTOPUS_USE_GPU=1 together with
OCTOPUS_USE_MPI=1 is an error: the multi-process policy composes the CPU policy
and is CPU storage only.

Under MPI every rank prints these lines behind its own `mpi_rank = r of P`
line, each rank asserting the configuration it actually read. Only rank 0
writes the run artifact (the library gates that itself). The `rms` line is that
RANK'S SHARD and is labelled so: `beam_statistics` is a local reduction with no
collective in it, so under MPI it describes a shard, never the beam.

CUDA checks:

    julia --project=. -e 'using CUDA; println(CUDA.functional()); println(CUDA.has_cuda_gpu())'
    julia --project=. -e 'using CUDA; CUDA.versioninfo()'

This file is the developer harness for realistic weak-strong tracking; the
concise precedent is examples/weak_strong_tracking.jl. It covers:

1. Define one `input` named tuple with beam, optics, element, and output
   settings.
2. Construct the weak beam directly from the input, including the initial
   offset.
3. Construct element specs in tracking order.
4. Place observers/actions in the line when their location matters.
5. Build `TrackingTask(line)` and execute it with `execute!`.

Outputs are written to `test/result/<seed>/`, named by the case (this harness
keeps its outputs beside the tests; the clean `examples/` counterpart writes
the same layout under the repo-root `result/`):

- `<case_name>.h5`: the run artifact -- `/luminosity/strong_beam_1` (turn and
  luminosity), `/moments/weak_beam` (scheduled first- and second-order
  moments), and the `/execution` ledger; read through one handle,
  `read(TaskOutput(path), kind; name = ...)`.
=#

"""
Parse a boolean `OCTOPUS_*` switch, rejecting anything it does not recognise.

The same one grammar the strong-strong harness uses
(test/examples/strong_strong_tracking.jl, 2026-08-05_b audit U21-15/U21-16),
brought here 2026-09-06 because this file still carried the defect that fix was
about: `OCTOPUS_USE_GPU` was read as `== "1"`, so `OCTOPUS_USE_GPU=true` and
`=yes` -- the words that enable every other flag in these harnesses -- silently
ran on CPU, and the whole point of the switch is which hardware the timing came
from. One grammar, and a value outside it is an error naming the variable.

Defined above the Octopus load because `OCTOPUS_USE_MPI` decides HOW Octopus is
loaded and so must be read before it.
"""
function env_bool(key::AbstractString, default::Bool)
    raw = get(ENV, key, default ? "1" : "0")
    lowered = lowercase(strip(raw))
    lowered in ("1", "true", "yes", "on") && return true
    lowered in ("0", "false", "no", "off") && return false
    error("$(key)=$(repr(raw)) is not a boolean; use 1/0, true/false, yes/no or on/off")
end

# OCTOPUS_USE_MPI=1 runs this harness divided across MPI ranks -- one Octopus
# process per rank, each with its own CPU logical workers (OCTOPUS_CPU_THREADS).
# Read BEFORE Octopus is loaded because it decides HOW Octopus is loaded:
# `MultiProcessExecutionPolicy` reaches a communicator only through the
# `OctopusMPIExt` package extension, and a package extension loads only for a
# PACKAGE, which the default `include` of src/Octopus.jl into `Main` is not.
# Measured on this tree 2026-09-06: `Base.get_extension(Main.Octopus,
# :OctopusMPIExt)` is `nothing` under the include and `OctopusMPIExt` under
# `using Octopus`. Without the extension every process is its own communicator
# of one, which `ranks = :auto` accepts. The library's `_launcher_rank_count`
# tripwire already throws under the six launcher variables it knows; the
# assertion below fires earlier (at load, not after the run), names the cause
# rather than a size disagreement, and covers a launcher outside that list --
# which is where a silent P-whole-simulations run would otherwise come from.
# With the switch off this is the same `include` the suite has always run.
# `OCTOPUS_MP` is NOT this switch, and setting it must not look like it worked.
# `docs/history/production_benchmark_2026_09_06.md` -- frozen, as history is --
# names an `OCTOPUS_MP`/`OCTOPUS_RANKS` branch as the thing to add, because that
# is the spelling the throwaway scratch copies behind that measurement used. An
# operator following that record would set `OCTOPUS_MP=1`, get a threads-only
# run, and report it as MPI: a non-default request silently ignored, which this
# repository counts as a defect rather than a typo. The dead spelling is
# therefore refused BY NAME, the way `TrackingTask` refuses `loss_log` and
# `luminosity` (src/tasks/Tasks.jl, retired 2026-08-18). Refused on presence,
# not on value: `OCTOPUS_MP=0` also means the reader believes this switch
# exists.
haskey(ENV, "OCTOPUS_MP") && error(
    "OCTOPUS_MP is not a switch this harness reads. The multi-process switch is " *
    "OCTOPUS_USE_MPI=1, matching OCTOPUS_USE_GPU; OCTOPUS_RANKS and " *
    "OCTOPUS_CPU_THREADS are spelled as you have them. OCTOPUS_MP is what the " *
    "scratch copies behind docs/history/production_benchmark_2026_09_06.md used, " *
    "and that record is frozen, so it still names the old spelling.")

use_mpi = env_bool("OCTOPUS_USE_MPI", false)
if use_mpi
    # A Main.Octopus that came from an `include` cannot be turned into the
    # package: Julia 1.12 makes `using Octopus` a hard error here ("importing
    # Octopus into Main conflicts with an existing global"), which is loud but
    # says nothing about the cause. Say it here instead.
    if isdefined(Main, :Octopus) && Base.PkgId(Main.Octopus).uuid === nothing
        error("OCTOPUS_USE_MPI=1 needs Octopus loaded as a PACKAGE, because the " *
              "OctopusMPIExt extension attaches only to a package -- but " *
              "Main.Octopus is already an `include`d module (its PkgId carries no " *
              "UUID). Either drop the earlier `include` of src/Octopus.jl and let " *
              "this harness load the package, or `using Octopus` before including " *
              "this file.")
    end
    using Octopus
    using MPI
    # Idempotent through `Initialized()`, and the extension's own activation
    # makes exactly this call (test/mpi_seam_check.jl inits early for the same
    # reason); doing it here makes this process's rank available to this file
    # before `execute!` rather than only after it.
    MPI.Initialized() || MPI.Init(threadlevel = :funneled)
elseif !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "..", "src", "Octopus.jl"))
end
using .Octopus
if use_mpi && Base.get_extension(Main.Octopus, :OctopusMPIExt) === nothing
    error("OCTOPUS_USE_MPI=1, but OctopusMPIExt did not load. Every rank would " *
          "then be its own communicator of one and each would run the WHOLE " *
          "simulation, racing on one artifact path and reporting plausible " *
          "timings. Run this harness against an environment where Octopus and " *
          "MPI both resolve as packages, and do not pre-`include` src/Octopus.jl " *
          "into Main before it.")
end

# Input for this weak-proton crab-crossing case.
# Set OCTOPUS_TURNS and OCTOPUS_N_MACRO in the shell to run a smaller or larger
# job without editing the physics input below.
input = (
    case_name = "weak_strong",
    # OCTOPUS_RESULT_DIR: see the strong-strong harness (2026-08-05_b audit,
    # U21-27). Two concurrent runs used to clobber one another silently.
    result_dir = get(ENV, "OCTOPUS_RESULT_DIR", joinpath(@__DIR__, "..", "result")),
    seed = 123456789,
    # NOTE: no `total_turns` or `weak_beam.n_macro` here. Both sat in this
    # block reading as authoritative defaults while nothing read them
    # (2026-08-05_b audit, U21-24): the turn count comes from OCTOPUS_TURNS and
    # the macroparticle count from OCTOPUS_N_MACRO (default 10000).

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
        crossing_angle = 12.5e-3,
        tune = (0.228, 0.210, -0.01),
        chromaticity = (2.0, 2.0),
    ),

    crab_cavity = (
        frequency = 197.0e6,
        # Relative harmonic weights of the horizontal crab kick; (4/3, -1/3)
        # is the two-harmonic compensation scheme, (1.0, 0.0, 0.0) a single
        # cavity. The absolute scale is derived below.
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
        # Filenames derive from `case_name` — one authority, no copies (its
        # previous life as a defined-but-unread field was the U21-24 class the
        # NOTE above records for total_turns/n_macro). `capacity` is the
        # ARTIFACT'S: the one knob for how many rows every producer batches
        # between appends (the per-observer capacities retired 2026-08-18);
        # on networked filesystems the per-turn write dominates observer
        # cost (2.3 ms/turn measured;
        # docs/history/weak_strong_cuda_luminosity_2026_08_11.md).
        capacity = 1024,
        moment_start = 0,
        moment_step = 1,
    ),
)

turns = parse(Int, get(ENV, "OCTOPUS_TURNS", "2"))
n_macro = parse(Int, get(ENV, "OCTOPUS_N_MACRO", "10000"))

# Execution policy used for beam construction. Tasks infer the backend from the
# beam storage at execution time.
# CPU threads are the portable default. Set OCTOPUS_USE_GPU=1 to use CUDA.
# Observers still write on the host and may synchronize GPU data when scheduled.
use_gpu = env_bool("OCTOPUS_USE_GPU", false)
# The multi-process policy composes the CPU policy and is CPU storage only, so
# there is no CUDA arm to divide; asking for both is a request one of the two
# switches would have to be silently dropped from.
use_gpu && use_mpi && error(
    "OCTOPUS_USE_GPU=1 and OCTOPUS_USE_MPI=1 together: MultiProcessExecutionPolicy " *
    "composes CPUThreadsExecutionPolicy and runs on CPU storage, so there is no " *
    "CUDA-plus-MPI mode to select. Choose one.")
if use_gpu
    import CUDA
    CUDA.functional(false) || error("OCTOPUS_USE_GPU=1 requested, but CUDA.functional(false) is false.")
end
policy = if use_gpu
    cuda_device_env = get(ENV, "OCTOPUS_CUDA_DEVICE", "")
    cuda_device = isempty(cuda_device_env) ? nothing : parse(Int, cuda_device_env)
    CUDAExecutionPolicy(device = cuda_device)
else
    # OCTOPUS_CPU_THREADS, the same keyword and the same `auto` default the
    # strong-strong harness reads. This file did not read it at all before
    # 2026-09-06, so the only thread count it could run at was the process
    # default -- and the MPI arm needs a per-rank count, which is exactly this.
    cpu_threads_text = lowercase(strip(get(ENV, "OCTOPUS_CPU_THREADS", "auto")))
    cpu_threads = cpu_threads_text == "auto" ? :auto : parse(Int, cpu_threads_text)
    if use_mpi
        # OCTOPUS_RANKS passes straight through as the policy's `ranks` with no
        # harness logic: the policy already rejects a communicator whose size
        # differs from an explicit request. `auto` accepts whatever `mpiexec -n`
        # started.
        ranks_text = lowercase(strip(get(ENV, "OCTOPUS_RANKS", "auto")))
        ranks = ranks_text == "auto" ? :auto : parse(Int, ranks_text)
        MultiProcessExecutionPolicy(threads = cpu_threads, ranks = ranks)
    else
        CPUThreadsExecutionPolicy(threads = cpu_threads)
    end
end
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

# Outputs land under result_dir/<seed>/, named by the case, matching the
# clean example's layout so seed scans and multi-case runs never collide.
outdir = joinpath(input.result_dir, string(input.seed))
mkpath(outdir)
artifact_path = joinpath(outdir, input.case_name * ".h5")
# One run artifact per task; the moment observer is a named view into it.
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
# `policy = policy` is load-bearing, not tidiness. With `task.policy === nothing`
# `execute!` resolves a FRESH default policy, so the one built above reached only
# `Beam(...)` and was discarded -- the strong-strong harness carries the same
# note (2026-08-05_b audit, U21-17) and this twin never got the fix. At the
# defaults nothing changes (`CPUThreadsExecutionPolicy(threads = :auto)` is what
# the fresh default resolved to anyway), but OCTOPUS_CPU_THREADS now reaches
# execution, OCTOPUS_CUDA_DEVICE now reaches execution, and OCTOPUS_USE_MPI
# works at all: an inferred default is a `CPUThreadsExecutionPolicy`, so without
# this every rank would have tracked the whole beam, silently.
# OCTOPUS_RECORD_TURN_TIMES=1 gives a per-turn wall-clock series from ONE run.
# Off by default: on CUDA it synchronizes at every complete-turn boundary and so
# perturbs the throughput it measures, and it stores 8 bytes per turn without
# bound. It exists because the alternative -- differencing whole-process wall
# times across separate runs -- produced a wrong answer on 2026-09-06 and cost a
# retraction (docs/history/weak_strong_64thread_lead_2026_09_07.md).
record_turn_times = env_bool("OCTOPUS_RECORD_TURN_TIMES", false)
task = TrackingTask(line_specs;
    policy = policy,
    record_turn_times = record_turn_times,
    artifact = RunArtifact(artifact_path; capacity = input.output.capacity))
execute!(task, beam; turns = turns)

# Under MPI every rank runs this whole file. The rank comes from
# `MPI.Comm_rank(MPI.COMM_WORLD)`, NOT from Octopus's `_mp_is_root()`: the
# Octopus collectives read a serial passthrough outside an active policy scope
# and `execute!` has closed its scope by this line, so `_mp_is_root()` would
# return `true` on every rank -- silently (docs/experiences.md, "A collective
# outside its scope is a silent no-op").
mpi_nranks = use_mpi ? MPI.Comm_size(MPI.COMM_WORLD) : 1
mpi_rank = use_mpi ? MPI.Comm_rank(MPI.COMM_WORLD) : 0
use_mpi && println("mpi_rank = ", mpi_rank, " of ", mpi_nranks)
# Rank 0 alone writes files; every rank prints. One path and P writers is a
# race, and this harness had no such flag before (the strong-strong one does).
writes_files = mpi_rank == 0
if record_turn_times
    series = turn_timings(task)
    # PER RANK, and said so: each rank clocked its own shard's turn and no
    # collective was issued, so the turn's true wall time is the MAX across
    # ranks, not this line. Printed by every rank for the same reason the
    # configuration dump is -- each rank asserting what it actually measured.
    println("turn_timings_seconds", mpi_nranks > 1 ? " (rank $(mpi_rank) shard of $(mpi_nranks); the turn's wall time is the max over ranks)" : "",
            " = ", series)
    if writes_files
        path = get(ENV, "OCTOPUS_TURN_TIMING_PATH", "")
        if !isempty(path)
            # Relative paths resolve against the repository, never into
            # OCTOPUS_RESULT_DIR: the suite asserts rank 0's result directory
            # holds exactly one file.
            full = isabspath(path) ? path : joinpath(@__DIR__, "..", "..", path)
            mkpath(dirname(full))
            open(full, "w") do io
                println(io, "turn\tseconds")
                for (i, dt) in enumerate(series)
                    println(io, i, "\t", dt)
                end
            end
            println("turn_timing_path = ", full)
        end
    end
end
# `beam_statistics` is a purely local reduction -- no collective, no shard
# argument (src/beam/Beam.jl) -- and under MPI `beam` holds this rank's SHARD.
# Named for what it is, so a reader comparing an MPI run's rms against a
# threads-only run's is not comparing a shard with a beam. At one rank the shard
# IS the beam, so the qualifier appears only when it is true.
stats = beam_statistics(beam)
println("turns = ", turns)
println("n_macro = ", n_macro)
println("artifact = ", artifact_path)
println("  /luminosity/strong_beam_1, /moments/weak_beam, /execution")
println(mpi_nranks > 1 ?
        "rms (rank $(mpi_rank) shard of $(mpi_nranks), not the whole beam) = " :
        "rms = ", stats.rms)
