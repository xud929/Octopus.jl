#=
Strong-strong tracking example with two live beams.

This is the CONFIGURABLE development/testing harness: it exposes the solver
A/B selection, CUDA launch tuning, per-phase timing, and diagnostic/output
toggles through OCTOPUS_* environment variables, for use while developing the
solvers. For the clean, production-shaped example meant as a user guideline
(a small edit-these config block, no environment variables), see
examples/strong_strong_tracking.jl.

Run from the Octopus project root:

    julia --project=. test/examples/strong_strong_tracking.jl

This script is direct Julia construction of a realistic crab-crossing
electron-proton strong-strong case. The default run is intentionally small for
interactive testing. Use environment variables for larger runs:

    OCTOPUS_TURNS=100 OCTOPUS_N_MACRO_ELE=2560000 OCTOPUS_N_MACRO_PRO=1024000 julia --project=. test/examples/strong_strong_tracking.jl

Use CUDA for beam construction and tracking:

    OCTOPUS_USE_GPU=1 julia --project=. test/examples/strong_strong_tracking.jl

Select a CUDA device explicitly:

    OCTOPUS_USE_GPU=1 OCTOPUS_CUDA_DEVICE=1 julia --project=. test/examples/strong_strong_tracking.jl

Run divided across MPI ranks -- one Octopus process per rank, each with its own
CPU logical workers. OCTOPUS_CPU_THREADS sets the per-rank thread count (the
same keyword the threads-only arm reads), and OCTOPUS_RANKS optionally states
the process count the run must match:

    OCTOPUS_USE_MPI=1 OCTOPUS_CPU_THREADS=8 OCTOPUS_RANKS=16 mpiexec -n 16 julia --project=. test/examples/strong_strong_tracking.jl

OCTOPUS_RANKS defaults to `auto`, which accepts whatever the launcher started;
naming the count makes the policy reject a communicator of another size, which
is the cheap way to catch a launcher that started a different number of
processes than the command line says.

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

What the P ranks each write, and what only rank 0 writes: every rank prints its
own configuration dump behind an `mpi_rank = r of P` line (each rank asserting
the configuration it actually read), and `turn_timings_seconds` is that rank's
own wall clock. Only rank 0 writes the OCTOPUS_TURN_TIMING_PATH TSV, and only
rank 0 writes the run artifact (the library gates that itself). The
`electron rms`/`proton rms` lines are that RANK'S SHARD and are labelled so:
`beam_statistics` is a local reduction with no collective in it, so under MPI it
describes a shard, never the beam.

This example uses the PIC solver by default. Select the Poisson solver with
OCTOPUS_SOLVER (pic | spectral | gaussian | gaussian_pic); an unrecognized name
is an error. The spectral grid/box can be overridden with
OCTOPUS_SPECTRAL_GRID="nx,ny" and OCTOPUS_SPECTRAL_DOMAIN_FACTOR for A/B timing:

    OCTOPUS_USE_GPU=1 OCTOPUS_SOLVER=spectral OCTOPUS_N_MACRO_ELE=2560000 OCTOPUS_N_MACRO_PRO=1024000 OCTOPUS_RECORD_TURN_TIMES=1 julia --project=. test/examples/strong_strong_tracking.jl

Further switches this header once omitted (2026-08-05 audit, U18-2), all read
below with the defaults shown at their read sites: OCTOPUS_CPU_THREADS,
OCTOPUS_N_MACRO, OCTOPUS_PROTON_ENERGY_GEV, OCTOPUS_CUDA_NVTX,
OCTOPUS_DISABLE_MOMENTS, OCTOPUS_DISABLE_LUMINOSITY_OUTPUT,
OCTOPUS_MOMENT_CAPACITY, OCTOPUS_SPECTRAL_FIELD_PRECISION, OCTOPUS_GPIC_GRID,
OCTOPUS_TURN_TIMING_PATH (a relative value resolves against `test/result/`,
beside this harness -- NOT against the caller's cwd),
OCTOPUS_CUDA_PIC_SLICE_PAIR_GREEN_MIN_RATIO,
OCTOPUS_CUDA_PIC_SLICE_PAIR_GREEN_GROWTH,
OCTOPUS_CUDA_PIC_GATHER_SCATTER_THREADS, OCTOPUS_CUDA_PIC_DEPOSITION_THREADS,
OCTOPUS_CUDA_PIC_KICK_THREADS, OCTOPUS_CUDA_PIC_FIELD_THREADS,
OCTOPUS_CUDA_PIC_SPECTRAL_THREADS, OCTOPUS_CUDA_PIC_GREEN_THREADS and
OCTOPUS_CUDA_PIC_LUMINOSITY_THREADS.

(Written out by name rather than as globs: the U18-2 fix wrote "the
CUDA_PIC_SLICE_PAIR green-cache aliases" and "the per-kernel CUDA_PIC_*_THREADS
overrides", which are neither greppable nor copy-pasteable and also dropped the
OCTOPUS_ prefix, so eight variables stayed effectively undocumented --
2026-08-05_b audit, U21-23.)

The `.h5` run artifact is NOT byte-reproducible across two identical runs, so
no byte-level regression check can be built on it (2026-08-05_b audit, U21-28).
Two independent sources: HDF5 writes object-header birth timestamps into the file
format itself, and the artifact's `/execution` ledger records wall time. Measured
on the weak-strong harness, 48 differing bytes between two identical runs, all in
4-byte timestamps and their checksums. Compare the DATASETS, not the files.

The soft-Gaussian solver is also available as a commented alternative ABOVE the
solver construction.

Run the high-energy weak-strong limiting case by making the electron beam
effectively rigid. Energies are supplied in GeV for these convenience knobs:

    OCTOPUS_WEAK_STRONG_LIMIT=1 julia --project=. test/examples/strong_strong_tracking.jl
    OCTOPUS_ELECTRON_ENERGY_GEV=1e100 julia --project=. test/examples/strong_strong_tracking.jl

Disable the beam-beam collision while retaining both complete ring lines:

    OCTOPUS_DISABLE_COLLISION=1 julia --project=. test/examples/strong_strong_tracking.jl

Control the PIC longitudinal potential-difference kick. It is enabled by default:

    OCTOPUS_PIC_LONGITUDINAL_KICK=1 julia --project=. test/examples/strong_strong_tracking.jl
    OCTOPUS_PIC_LONGITUDINAL_KICK=0 julia --project=. test/examples/strong_strong_tracking.jl

Select the slice-pair schedule -- every solver's `batch_mode`, read on CPU and CUDA
(the spectral 6D loop reads it on CPU; its CUDA route has one schedule and says so):

    OCTOPUS_PIC_BATCH_MODE=sequential julia --project=. test/examples/strong_strong_tracking.jl
    OCTOPUS_PIC_BATCH_MODE=wavefront julia --project=. test/examples/strong_strong_tracking.jl

Compute PIC luminosity every N turns. Use 0 to disable luminosity computation:

    OCTOPUS_PIC_LUMINOSITY_EVERY=10 julia --project=. test/examples/strong_strong_tracking.jl

Select an independent luminosity grid or deposition method. `INHERIT` (the
default) follows the force `deposit_method`; `CIC` and `TSC` override it:

    OCTOPUS_PIC_LUMINOSITY_GRID=128,128 OCTOPUS_PIC_LUMINOSITY_DEPOSIT_METHOD=TSC julia --project=. test/examples/strong_strong_tracking.jl

The persistent slice-pair Green cache is the default for CPU and CUDA task
execution. Disable it to run an uncached reference comparison:

    OCTOPUS_PIC_GREEN_CACHE=slice_pair julia --project=. test/examples/strong_strong_tracking.jl
    OCTOPUS_PIC_GREEN_CACHE=none julia --project=. test/examples/strong_strong_tracking.jl

Tune the slice-pair Green cache. `GROWTH=0.20` builds cached
grids 1.20 times larger than the current request:

    OCTOPUS_PIC_GREEN_CACHE=slice_pair OCTOPUS_PIC_SLICE_PAIR_GREEN_MIN_RATIO=0.50 OCTOPUS_PIC_SLICE_PAIR_GREEN_GROWTH=0.20 julia --project=. test/examples/strong_strong_tracking.jl

Disable CUDA PIC asynchronous field solves for comparison:

    OCTOPUS_USE_GPU=1 OCTOPUS_CUDA_PIC_ASYNC=0 julia --project=. test/examples/strong_strong_tracking.jl

Disable CUDA PIC batched FFT field solves for comparison:

    OCTOPUS_USE_GPU=1 OCTOPUS_CUDA_PIC_BATCH_FFT=0 julia --project=. test/examples/strong_strong_tracking.jl

Disable CUDA PIC wavefront-level batched FFTs for comparison:

    OCTOPUS_USE_GPU=1 OCTOPUS_PIC_BATCH_MODE=wavefront OCTOPUS_CUDA_PIC_WAVEFRONT_FFT=0 julia --project=. test/examples/strong_strong_tracking.jl

Print statistics for the default slice-pair Green cache:

    OCTOPUS_USE_GPU=1 OCTOPUS_PIC_BATCH_MODE=wavefront OCTOPUS_PIC_GREEN_CACHE=slice_pair OCTOPUS_PIC_CACHE_STATS=1 julia --project=. test/examples/strong_strong_tracking.jl

Test the indexed CUDA wavefront path. It skips compact gather/scatter and
deposits/kicks through slice index vectors while leaving canonical particle
order unchanged:

    OCTOPUS_USE_GPU=1 OCTOPUS_PIC_BATCH_MODE=wavefront OCTOPUS_CUDA_PIC_INDEXED_WAVEFRONT=1 julia --project=. test/examples/strong_strong_tracking.jl

Log CUDA memory every N turns:

    OCTOPUS_USE_GPU=1 OCTOPUS_CUDA_MEMORY_LOG_EVERY=10 julia --project=. test/examples/strong_strong_tracking.jl

Print CUDA PIC phase timings:

    OCTOPUS_USE_GPU=1 OCTOPUS_CUDA_PIC_TIMING=1 julia --project=. test/examples/strong_strong_tracking.jl

Record synchronized complete-turn timings and optionally write them as TSV:

    OCTOPUS_USE_GPU=1 OCTOPUS_RECORD_TURN_TIMES=1 OCTOPUS_TURN_TIMING_PATH=result/pic_turn_times.tsv julia --project=. test/examples/strong_strong_tracking.jl

Benchmark fused CUDA launch geometry through the public policy interface. PIC
family overrides are optional and otherwise inherit `CUDA_THREADS`:

    OCTOPUS_USE_GPU=1 OCTOPUS_CUDA_THREADS=256 OCTOPUS_CUDA_BLOCKS=auto julia --project=. test/examples/strong_strong_tracking.jl
    OCTOPUS_USE_GPU=1 OCTOPUS_CUDA_PIC_DEPOSITION_THREADS=128 julia --project=. test/examples/strong_strong_tracking.jl

Print additive field subphase timings. This disables async PIC field solves for
diagnosis:

    OCTOPUS_USE_GPU=1 OCTOPUS_CUDA_PIC_TIMING=1 OCTOPUS_CUDA_PIC_TIMING_DETAIL=1 julia --project=. test/examples/strong_strong_tracking.jl

Output is ONE run artifact under `test/result/` (this harness keeps its
outputs beside the tests; the clean `examples/` counterpart writes the same
layout under the repo-root `result/`):

- `test/result/<seed>/pic_hcc.h5` : `/luminosity/ip`, `/moments/electron`
  and `/moments/proton`, and the `/execution` ledger; read through one
  handle, `read(TaskOutput(path), kind; name = ...)`.
=#

"""
Parse a boolean `OCTOPUS_*` switch, rejecting anything it does not recognise.

Two defects this replaces (2026-08-05_b audit, U21-15/U21-16). Every toggle used
`get(ENV, K, default) in ("1", "true", "TRUE", "yes", "YES")`, so an
unrecognised value fell through to `false` -- a typo did not fail, it silently
DISABLED the five switches whose default is on, and the run looked healthy.
And `OCTOPUS_USE_GPU` alone used `== "1"`, a stricter and different grammar, so
`OCTOPUS_USE_GPU=true` and `=yes` silently ran on CPU while those same two words
enabled every other flag in this file -- the worst version of the defect,
because the whole point of the switch is which hardware the timing came from.

One grammar now, and a value outside it is an error naming the variable.

Defined HERE, above the Octopus load, because `OCTOPUS_USE_MPI` decides HOW
Octopus is loaded and so must be read before it. Every other switch in this
file is read further down, at the point it is used.
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
# It is read BEFORE Octopus is loaded because it decides HOW Octopus is loaded,
# and that is a correctness requirement rather than a preference:
#
# `MultiProcessExecutionPolicy` reaches a real communicator only through the
# `OctopusMPIExt` package extension, and a package extension loads only for a
# PACKAGE. This harness's default load is `include`ing src/Octopus.jl into
# `Main`, which is not one. Measured on this tree 2026-09-06:
# `Base.PkgId(Main.Octopus)` is `Base.PkgId(nothing, "Main")` and
# `Base.get_extension(Main.Octopus, :OctopusMPIExt)` is `nothing` under the
# include, against `OctopusMPIExt` under `using Octopus`. Without the extension
# every process is its own communicator of one, `ranks = :auto` accepts that as
# legitimate, and `mpiexec -n 8` runs EIGHT identical whole simulations racing
# on one artifact path: exit 0, plausible timings, wrong answer. The one failure
# mode this switch has is silent, so the assertion below makes it loud.
#
# The default path is untouched: with the switch off this is the same `include`
# the suite's example-runner testset has always executed.
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
    # `MPI.Init` is idempotent through `Initialized()` and the extension's own
    # activation makes exactly this call, so nothing downstream can tell the
    # difference (test/mpi_seam_check.jl inits early for the same reason). Doing
    # it here makes this process's rank available to this file before `execute!`
    # rather than only after it.
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

input = (
    case_name = "pic_hcc",
    # OCTOPUS_RESULT_DIR lets concurrent or comparative runs write somewhere of
    # their own (2026-08-05_b audit, U21-27). The path was fixed and had no
    # override, and two simultaneous runs did NOT fail -- measured twice,
    # including with a deliberately widened write window, both exited 0 and left
    # one set of files. Silent last-writer-wins is worse than an error by this
    # repository's own "loud beats silent" rule, and there was no way to avoid
    # it short of editing the harness.
    result_dir = get(ENV, "OCTOPUS_RESULT_DIR", joinpath(@__DIR__, "..", "result")),
    seed = 123456789,
    default_demo_macroparticles = 200,
    crossing_angle = 12.5e-3,

    electron = (
        charge = -1.0,
        mass = EMASS_EV,
        energy = 10.0e9,
        n_particle = 1.7203e11,
        # NOTE: no `n_macro` here. The production macroparticle counts are
        # 2_560_000 electrons and 1_024_000 protons, but this harness takes its
        # count from OCTOPUS_N_MACRO / _ELE / _PRO and defaults to
        # `default_demo_macroparticles` (200). Fields named `n_macro` sat in
        # this block reading as authoritative defaults while nothing read them
        # (2026-08-05_b audit, U21-24); the clean `examples/` counterpart keeps
        # the production numbers in its `config` block, where they ARE read.
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

    slicing = (
        zslice = 15,
        center = :centroid,
    ),

    solver = (
        pic_grid = (128, 128),
        pic_deposit_method = :CIC,
        pic_luminosity_deposit_method = nothing,
        pic_green_type = :integrated,
        pic_slice_pair_green_min_ratio = 0.50,
        pic_slice_pair_green_growth = 0.25,
        min_sigma = 1.0e-12,
        luminosity_scale = nothing,
    ),

    output = (
        # Filenames derive from `case_name` — one authority, no copies (the
        # weak-strong pair's 2026-08-11 fix, same class); `total_turns` went
        # with them, a hand copy that only bounded the moment schedule.
        # `capacity` is the ARTIFACT'S: the one knob for how many rows every
        # producer batches between appends (the per-observer capacities
        # retired 2026-08-18); networked filesystems punish smaller flushes
        # (docs/history/weak_strong_cuda_luminosity_2026_08_11.md).
        moment_start = 0,
        moment_step = 1,
        capacity = 1024,
    ),
)

turns = parse(Int, get(ENV, "OCTOPUS_TURNS", "2"))
common_n_macro = get(ENV, "OCTOPUS_N_MACRO", "")
n_macro_ele = parse(Int, get(ENV, "OCTOPUS_N_MACRO_ELE",
                             isempty(common_n_macro) ? string(input.default_demo_macroparticles) : common_n_macro))
n_macro_pro = parse(Int, get(ENV, "OCTOPUS_N_MACRO_PRO",
                             isempty(common_n_macro) ? string(input.default_demo_macroparticles) : common_n_macro))

use_gpu = env_bool("OCTOPUS_USE_GPU", false)
# The multi-process policy composes the CPU policy and is CPU storage only, so
# there is no CUDA arm to divide. Asking for both is a request one of the two
# switches would have to be silently dropped from, which this repository counts
# as a defect rather than a convenience.
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
    cuda_threads = parse(Int, get(ENV, "OCTOPUS_CUDA_THREADS", "256"))
    cuda_blocks_text = lowercase(get(ENV, "OCTOPUS_CUDA_BLOCKS", "auto"))
    cuda_blocks = cuda_blocks_text == "auto" ? :auto : parse(Int, cuda_blocks_text)
    CUDAExecutionPolicy(device = cuda_device,
        launch = CUDALaunchConfig(threads = cuda_threads, blocks = cuda_blocks))
else
    cpu_threads_text = lowercase(get(ENV, "OCTOPUS_CPU_THREADS", "auto"))
    cpu_threads = cpu_threads_text == "auto" ? :auto : parse(Int, cpu_threads_text)
    if use_mpi
        # OCTOPUS_RANKS goes straight through as the policy's `ranks`, and this
        # harness adds no logic of its own: the policy already rejects a
        # communicator whose size differs from an explicit request, so naming the
        # count here is the free way to assert that the launcher started the
        # process count you meant. Left `auto` it accepts whatever `mpiexec -n`
        # started -- which is the same accept-anything that makes an unloaded
        # extension look legitimate, so prefer an explicit value when the
        # timing matters.
        ranks_text = lowercase(strip(get(ENV, "OCTOPUS_RANKS", "auto")))
        ranks = ranks_text == "auto" ? :auto : parse(Int, ranks_text)
        # Per-rank threads are the SAME OCTOPUS_CPU_THREADS the threads-only arm
        # reads: one keyword, one meaning. `MultiProcessExecutionPolicy` composes
        # `CPUThreadsExecutionPolicy(threads)` unchanged, so at one rank this is
        # that policy, bit for bit.
        MultiProcessExecutionPolicy(threads = cpu_threads, ranks = ranks)
    else
        CPUThreadsExecutionPolicy(threads = cpu_threads)
    end
end
set_global_rng!(seed = input.seed, method = :philox)

ele = input.electron
pro = input.proton
weak_strong_limit = env_bool("OCTOPUS_WEAK_STRONG_LIMIT", false)
# A beam energy must be positive (2026-08-05_b audit, U21-22).
# `OCTOPUS_ELECTRON_ENERGY_GEV=-5` used to be accepted and tracked to
# completion, printing `electron_energy_GeV = -5.0` and plausible-looking rms,
# exit 0 -- a nonsense configuration producing numbers a reader would trust.
function _energy_env(name, default_eV)
    haskey(ENV, name) || return default_eV
    gev = parse(Float64, ENV[name])
    (isfinite(gev) || gev > 0) || error("$(name) must be a positive number of GeV; got $(gev)")
    gev > 0 || error("$(name) must be positive; got $(gev) GeV")
    return gev * 1.0e9
end

electron_energy = if haskey(ENV, "OCTOPUS_ELECTRON_ENERGY_GEV")
    _energy_env("OCTOPUS_ELECTRON_ENERGY_GEV", ele.energy)
elseif weak_strong_limit
    1.0e100 * 1.0e9
else
    ele.energy
end
proton_energy = _energy_env("OCTOPUS_PROTON_ENERGY_GEV", pro.energy)

beam_ele = Beam(n_macro_ele, policy, Float64;
    beta = ele.beta,
    alpha = ele.alpha,
    sigma = ele.sigma,
    cutoff = ele.cutoff,
    rng_id = 1,
    charge = ele.charge,
    mc2 = ele.mass,
    E0 = electron_energy,
    r0 = RE * ME0 / ele.mass,
    npart = ele.n_particle,
)

beam_pro = Beam(n_macro_pro, policy, Float64;
    beta = pro.beta,
    alpha = pro.alpha,
    sigma = pro.sigma,
    cutoff = pro.cutoff,
    rng_id = 2,
    charge = pro.charge,
    mc2 = pro.mass,
    E0 = proton_energy,
    r0 = RE * ME0 / pro.mass,
    npart = pro.n_particle,
)

# Through `coordinate_arrays`, the public accessor, rather than `beam.rep.x`
# (2026-08-05_b audit, U21-25). AGENTS.md classes the representation as an
# implementation detail that "may change"; reaching into `.rep.x` is exactly
# what a representation change breaks, and a harness is the worst place to
# discover that.
eltype(first(coordinate_arrays(beam_ele))) === Float64 ||
    error("electron beam tracking arrays must be Float64")
eltype(first(coordinate_arrays(beam_pro))) === Float64 ||
    error("proton beam tracking arrays must be Float64")

slicing = LongitudinalSlicing(;
    method = :normal_quantile,
    nslices = input.slicing.zslice,
    center_position = input.slicing.center,
)

pic_green_cache = Symbol(lowercase(get(ENV, "OCTOPUS_PIC_GREEN_CACHE", "slice_pair")))
pic_slice_pair_green_min_ratio = parse(Float64, get(ENV, "OCTOPUS_PIC_SLICE_PAIR_GREEN_MIN_RATIO",
                                                    get(ENV, "OCTOPUS_CUDA_PIC_SLICE_PAIR_GREEN_MIN_RATIO",
                                                        string(input.solver.pic_slice_pair_green_min_ratio))))
pic_slice_pair_green_growth = parse(Float64, get(ENV, "OCTOPUS_PIC_SLICE_PAIR_GREEN_GROWTH",
                                                 get(ENV, "OCTOPUS_CUDA_PIC_SLICE_PAIR_GREEN_GROWTH",
                                                     string(input.solver.pic_slice_pair_green_growth))))
pic_longitudinal_kick = env_bool("OCTOPUS_PIC_LONGITUDINAL_KICK", true)
pic_batch_mode = Symbol(lowercase(get(ENV, "OCTOPUS_PIC_BATCH_MODE", "wavefront")))
cuda_pic_async = env_bool("OCTOPUS_CUDA_PIC_ASYNC", true)
cuda_pic_batch_fft = env_bool("OCTOPUS_CUDA_PIC_BATCH_FFT", true)
cuda_pic_wavefront_fft = env_bool("OCTOPUS_CUDA_PIC_WAVEFRONT_FFT", true)
cuda_pic_indexed_wavefront = env_bool("OCTOPUS_CUDA_PIC_INDEXED_WAVEFRONT", true)
pic_luminosity_every = parse(Int, get(ENV, "OCTOPUS_PIC_LUMINOSITY_EVERY", "1"))
pic_luminosity_grid = if haskey(ENV, "OCTOPUS_PIC_LUMINOSITY_GRID")
    values = parse.(Int, split(ENV["OCTOPUS_PIC_LUMINOSITY_GRID"], ','))
    length(values) == 2 || error("OCTOPUS_PIC_LUMINOSITY_GRID must be nx,ny")
    (values[1], values[2])
else
    nothing
end
pic_luminosity_deposit_method = if haskey(ENV, "OCTOPUS_PIC_LUMINOSITY_DEPOSIT_METHOD")
    value = uppercase(ENV["OCTOPUS_PIC_LUMINOSITY_DEPOSIT_METHOD"])
    value == "INHERIT" ? nothing : Symbol(value)
else
    input.solver.pic_luminosity_deposit_method
end
pic_luminosity_schedule =
    pic_luminosity_every < 0 ? error("OCTOPUS_PIC_LUMINOSITY_EVERY must be >= 0") :
    pic_luminosity_every == 0 ? AtTurns(Int[]) :
    pic_luminosity_every == 1 ? nothing :
    EveryNSteps(step = pic_luminosity_every)
record_turn_times = env_bool("OCTOPUS_RECORD_TURN_TIMES", false)
diagnostics = StrongStrongDiagnostics(;
    record_turn_times,
    memory_log_every = parse(Int, get(ENV, "OCTOPUS_CUDA_MEMORY_LOG_EVERY", "0")),
    pic_timing = env_bool("OCTOPUS_CUDA_PIC_TIMING", false),
    pic_timing_detail = env_bool("OCTOPUS_CUDA_PIC_TIMING_DETAIL", false),
    cache_stats = env_bool("OCTOPUS_PIC_CACHE_STATS", false),
    nvtx = env_bool("OCTOPUS_CUDA_NVTX", false),
)
disable_moments = env_bool("OCTOPUS_DISABLE_MOMENTS", false)
disable_luminosity_output = env_bool("OCTOPUS_DISABLE_LUMINOSITY_OUTPUT", false)
disable_collision = env_bool("OCTOPUS_DISABLE_COLLISION", false)
# OCTOPUS_MOMENT_CAPACITY now sets the ARTIFACT capacity (the one knob for
# every producer's batching); 0 keeps its documented harness meaning of
# "disable moment output", folded into disable_moments below since the
# library-level capacity=0 spelling retired with the per-observer capacity.
moment_capacity = parse(Int, get(ENV, "OCTOPUS_MOMENT_CAPACITY",
                                 string(input.output.capacity)))
disable_moments = disable_moments || moment_capacity == 0
artifact_capacity = moment_capacity > 0 ? moment_capacity : input.output.capacity
optional_cuda_pic_threads(key) = haskey(ENV, key) ? parse(Int, ENV[key]) : nothing
cuda_pic_launch = CUDAPICLaunchConfig(
    gather_scatter_threads = optional_cuda_pic_threads("OCTOPUS_CUDA_PIC_GATHER_SCATTER_THREADS"),
    deposition_threads = optional_cuda_pic_threads("OCTOPUS_CUDA_PIC_DEPOSITION_THREADS"),
    kick_threads = optional_cuda_pic_threads("OCTOPUS_CUDA_PIC_KICK_THREADS"),
    field_threads = optional_cuda_pic_threads("OCTOPUS_CUDA_PIC_FIELD_THREADS"),
    spectral_threads = optional_cuda_pic_threads("OCTOPUS_CUDA_PIC_SPECTRAL_THREADS"),
    green_threads = optional_cuda_pic_threads("OCTOPUS_CUDA_PIC_GREEN_THREADS"),
    luminosity_threads = optional_cuda_pic_threads("OCTOPUS_CUDA_PIC_LUMINOSITY_THREADS"),
)
cuda_pic_backend_configurations = use_gpu ? (cuda_pic_launch,) : ()
# NOTE (2026-08-05 audit, U18-1): solver selection moved to the
# OCTOPUS_SOLVER environment switch further down, which OVERRIDES anything
# assembled here — uncommenting this block alone is dead code. Use
# OCTOPUS_SOLVER=gaussian instead.
#
# This block is the reference for the solver's KEYWORD SET, not for what the
# switch passes (2026-08-05_b audit, U21-14): the switch sets slicing,
# min_sigma, luminosity_scale, longitudinal_kick and batch_mode, and leaves
# `virtual_drift` and `include_sigma_xy` at their constructor defaults. The
# earlier wording said the block "stays as the reference for what that switch
# builds", which over-stated it by exactly those two keywords — edit the switch
# if you need them.
#
# The soft-Gaussian solver replaces the grid PIC field solve with sliced
# Gaussian moments and a closed-form Bassetti-Erskine kick; see
# docs/theory/beam_beam_longitudinal_kick.md.
#
# solver = GaussianPoissonSolver(;
#     slicing = slicing,
#     min_sigma = input.solver.min_sigma,
#     luminosity_scale = input.solver.luminosity_scale,
#     longitudinal_kick = true,
#     virtual_drift = :hirata,      # :hirata, :chromatic, or :exact
#     include_sigma_xy = false,     # true for the full coupled transverse covariance
#     batch_mode = :wavefront,      # :wavefront or :sequential
# )
#
# Or the spectral sine-series solver (Dirichlet box + DST/DCT field solve). The
# grid follows N_thin ~ 5*domain_factor*sigma_x/sigma_y for flat beams (see
# docs/theory/spectral_sine_poisson_solver.md). With `longitudinal_kick=true` it applies
# the same synchro-beam drift and potential-difference pz structure as the PIC
# path. CUDA supports method=:grid only; method=:grid_free is CPU-only.
#
# Recommended CUDA production setting for the ~11:1 flat beams: grid=(127, 383),
# domain_factor=8. This matches the analytic/PIC kick to ~1% (both beams, all of
# x/y/z) and is ~6x faster than grid=(128,1024)/16 on GPU. Through the full example
# beamline at the production case it is ~1.5x the PIC solver (0.46 vs 0.31 s/turn on
# an RTX 4500 Ada), comparable but not at parity. The odd sizes are deliberate: a grid dimension
# N gives a DST/DCT extension of length 2(N+1), so N = 2^k-1 (127, 383, 511, ...)
# makes that a power of two and the CUDA real-FFT optimal. See the optimization
# history for the CPU/CUDA performance campaign.
#
# solver = SpectralPoissonSolver(;
#     slicing = slicing,
#     luminosity_scale = input.solver.luminosity_scale,
#     grid = (127, 383),            # ~11:1 flat production beams; (127,127) for round
#     domain_factor = 8.0,
#     method = :grid,               # :grid (fast, CUDA) or :grid_free (CPU only)
#     longitudinal_kick = true,
# )

# Solver selection via OCTOPUS_SOLVER (pic | spectral | gaussian | gaussian_pic);
# defaults to pic. An unrecognized name is an error rather than a silent fallback.
# The spectral grid/domain_factor can be overridden with OCTOPUS_SPECTRAL_GRID
# ("nx,ny") and OCTOPUS_SPECTRAL_DOMAIN_FACTOR for A/B benchmarking; the
# Gaussian-subtracted PIC grid with OCTOPUS_GPIC_GRID ("nx,ny").
solver_name = lowercase(get(ENV, "OCTOPUS_SOLVER", "pic"))
solver_name in ("pic", "spectral", "gaussian", "gaussian_pic") || error(
    "OCTOPUS_SOLVER must be one of pic, spectral, gaussian, gaussian_pic; got $(repr(solver_name))")
# Same named error its sibling OCTOPUS_PIC_LUMINOSITY_GRID raises (2026-08-05_b
# audit, U21-21). Without the arity check a one-element value died with a raw
# `BoundsError: attempt to access 1-element Vector{Int64} at index [2]`, which
# tells the user nothing about which variable was wrong or what it wanted.
_grid_env(name, default) = let v = get(ENV, name, default)
    parts = parse.(Int, split(v, ','))
    length(parts) == 2 || error("$(name) must be nx,ny; got $(repr(v))")
    all(>(0), parts) || error("$(name) entries must be positive; got $(repr(v))")
    (parts[1], parts[2])
end

spectral_grid = _grid_env("OCTOPUS_SPECTRAL_GRID", "127,383")
spectral_domain_factor = parse(Float64, get(ENV, "OCTOPUS_SPECTRAL_DOMAIN_FACTOR", "8.0"))
spectral_field_precision = Symbol(lowercase(get(ENV, "OCTOPUS_SPECTRAL_FIELD_PRECISION", "double")))
gpic_grid = _grid_env("OCTOPUS_GPIC_GRID", "64,64")

solver = if solver_name == "spectral"
    SpectralPoissonSolver(;
        slicing = slicing,
        luminosity_scale = input.solver.luminosity_scale,
        grid = spectral_grid,
        domain_factor = spectral_domain_factor,
        method = :grid,
        field_precision = spectral_field_precision,
        longitudinal_kick = pic_longitudinal_kick,
        # The solvers' one schedule keyword (2026-09-04); the spectral 6D loop
        # reads it on CPU, the CUDA route records that it has one schedule.
        batch_mode = pic_batch_mode,
    )
elseif solver_name == "gaussian"
    GaussianPoissonSolver(;
        slicing = slicing,
        min_sigma = input.solver.min_sigma,
        luminosity_scale = input.solver.luminosity_scale,
        longitudinal_kick = pic_longitudinal_kick,
        batch_mode = pic_batch_mode,
    )
elseif solver_name == "gaussian_pic"
    GaussianPICPoissonSolver(;
        slicing = slicing,
        luminosity_scale = input.solver.luminosity_scale,
        grid = gpic_grid,
        deposit_method = input.solver.pic_deposit_method,
        green_type = input.solver.pic_green_type,
        green_cache = pic_green_cache,
        longitudinal_kick = pic_longitudinal_kick,
        batch_mode = pic_batch_mode,
        cuda_async = cuda_pic_async,
        cuda_batch_fft = cuda_pic_batch_fft,
        cuda_wavefront_fft = cuda_pic_wavefront_fft,
        cuda_indexed_wavefront = cuda_pic_indexed_wavefront,
        luminosity_schedule = pic_luminosity_schedule,
        backend_configurations = cuda_pic_backend_configurations,
    )
else
    PICPoissonSolver(;
        slicing = slicing,
        luminosity_scale = input.solver.luminosity_scale,
        grid = input.solver.pic_grid,
        deposit_method = input.solver.pic_deposit_method,
        green_type = input.solver.pic_green_type,
        green_cache = pic_green_cache,
        slice_pair_green_min_ratio = pic_slice_pair_green_min_ratio,
        slice_pair_green_growth = pic_slice_pair_green_growth,
        longitudinal_kick = pic_longitudinal_kick,
        batch_mode = pic_batch_mode,
        cuda_async = cuda_pic_async,
        cuda_batch_fft = cuda_pic_batch_fft,
        cuda_wavefront_fft = cuda_pic_wavefront_fft,
        cuda_indexed_wavefront = cuda_pic_indexed_wavefront,
        luminosity_schedule = pic_luminosity_schedule,
        luminosity_grid = pic_luminosity_grid,
        luminosity_deposit_method = pic_luminosity_deposit_method,
        backend_configurations = cuda_pic_backend_configurations,
    )
end

# A launch override the chosen solver cannot consume is REFUSED, not dropped.
#
# `backend_configurations` is a `PICPoissonSolver` field, so it reaches only the
# `pic` and `gaussian_pic` solvers. For `spectral` and `gaussian` all seven
# OCTOPUS_CUDA_PIC_*_THREADS values were parsed, range-checked and then
# discarded. The name makes it worse than a no-op:
# OCTOPUS_CUDA_PIC_SPECTRAL_THREADS is exactly what someone tuning
# OCTOPUS_SOLVER=spectral would reach for, and the run reported a timing that
# had nothing to do with the value they set (2026-08-05_b audit, U21-18).
#
# AGENTS.md: a non-default request must be honoured or rejected, never silently
# ignored.
let launch_keys = ("OCTOPUS_CUDA_PIC_GATHER_SCATTER_THREADS",
                   "OCTOPUS_CUDA_PIC_DEPOSITION_THREADS",
                   "OCTOPUS_CUDA_PIC_KICK_THREADS",
                   "OCTOPUS_CUDA_PIC_FIELD_THREADS",
                   "OCTOPUS_CUDA_PIC_SPECTRAL_THREADS",
                   "OCTOPUS_CUDA_PIC_GREEN_THREADS",
                   "OCTOPUS_CUDA_PIC_LUMINOSITY_THREADS")
    requested = filter(k -> haskey(ENV, k), launch_keys)
    if !isempty(requested) && !(solver_name in ("pic", "gaussian_pic"))
        error("$(join(requested, ", ")) set with OCTOPUS_SOLVER=$(solver_name), " *
              "which has no backend_configurations field: these per-kernel launch " *
              "overrides reach only the pic and gaussian_pic solvers, so the value " *
              "would be parsed and discarded. Drop them, or select a PIC solver.")
    end
end

electron_tccb2ip = Linear6DSpec{Float64}(;
    beta1 = ele.crab_beta,
    beta2 = ele.beta,
    alpha1 = ele.alpha,
    alpha2 = ele.alpha,
    dmu = (pi / 2.0, 0.0, 0.0),
)
electron_tccb2ip_inv = Linear6DSpec{Float64}(matrix = inv(Matrix(Linear6D(electron_tccb2ip))))

electron_ip2tcca = Linear6DSpec{Float64}(;
    beta1 = ele.beta,
    beta2 = ele.crab_beta,
    alpha1 = ele.alpha,
    alpha2 = ele.alpha,
    dmu = (pi / 2.0, 0.0, 0.0),
)
electron_ip2tcca_inv = Linear6DSpec{Float64}(matrix = inv(Matrix(Linear6D(electron_ip2tcca))))

electron_tccb = ThinCrabCavitySpec{3}(ele.crab_frequency;
    strengthX = ele.crab_strength_x,
    strengthY = ele.crab_strength_y,
    phase = ele.crab_phase,
)
electron_tcca = ThinCrabCavitySpec{3}(ele.crab_frequency;
    strengthX = ele.crab_strength_x,
    strengthY = ele.crab_strength_y,
    phase = ele.crab_phase,
)

electron_one_turn = Linear6DSpec{Float64}(;
    beta1 = ele.beta,
    beta2 = ele.beta,
    alpha1 = ele.alpha,
    alpha2 = ele.alpha,
    dmu = 2pi .* ele.tune,
)
electron_chrom = ChromaticityKickSpec{Float64}(;
    xi = ele.chromaticity,
    beta = ele.beta,
    alpha = ele.alpha,
)
electron_rad = LumpedRadSpec{Float64}(;
    damping_turns = ele.radiation_damping_turns,
    beta = ele.beta,
    alpha = ele.alpha,
    sigma = ele.sigma,
    is_damping = true,
    is_excitation = true,
    rng_id = 3,
)

proton_tccb2ip = Linear6DSpec{Float64}(;
    beta1 = pro.crab_beta,
    beta2 = pro.beta,
    alpha1 = pro.alpha,
    alpha2 = pro.alpha,
    dmu = (pi / 2.0, 0.0, 0.0),
)
proton_tccb2ip_inv = Linear6DSpec{Float64}(matrix = inv(Matrix(Linear6D(proton_tccb2ip))))

proton_ip2tcca = Linear6DSpec{Float64}(;
    beta1 = pro.beta,
    beta2 = pro.crab_beta,
    alpha1 = pro.alpha,
    alpha2 = pro.alpha,
    dmu = (pi / 2.0, 0.0, 0.0),
)
proton_ip2tcca_inv = Linear6DSpec{Float64}(matrix = inv(Matrix(Linear6D(proton_ip2tcca))))

proton_tccb = ThinCrabCavitySpec{3}(pro.crab_frequency;
    strengthX = pro.crab_strength_x,
    strengthY = pro.crab_strength_y,
    phase = pro.crab_phase,
)
proton_tcca = ThinCrabCavitySpec{3}(pro.crab_frequency;
    strengthX = pro.crab_strength_x,
    strengthY = pro.crab_strength_y,
    phase = pro.crab_phase,
)

proton_one_turn = Linear6DSpec{Float64}(;
    beta1 = pro.beta,
    beta2 = pro.beta,
    alpha1 = pro.alpha,
    alpha2 = pro.alpha,
    dmu = 2pi .* pro.tune,
)
proton_chrom = ChromaticityKickSpec{Float64}(;
    xi = pro.chromaticity,
    beta = pro.beta,
    alpha = pro.alpha,
)

lb = LorentzBoostSpec(input.crossing_angle)
rlb = RevLorentzBoostSpec(input.crossing_angle)
ip = StrongStrongCollision(:ip; poisson_solver = solver)
collision_elements = disable_collision ? () : (ip,)

# Outputs land under result_dir/<seed>/, named by the case, matching the
# clean example's layout.
outdir = joinpath(input.result_dir, string(input.seed))
mkpath(outdir)
artifact_path = joinpath(outdir, input.case_name * ".h5")
moment_schedule = EveryNSteps(;
    start = input.output.moment_start,
    step = input.output.moment_step,
)
electron_observers = disable_moments ? () : (
    ScheduledObserver(
        MomentObserver(; name = "electron"),
        moment_schedule,
    ),
)
proton_observers = disable_moments ? () : (
    ScheduledObserver(
        MomentObserver(; name = "proton"),
        moment_schedule,
    ),
)
# Post-unification, OCTOPUS_DISABLE_LUMINOSITY_OUTPUT means "no luminosity
# rows on disk". With moments also disabled nothing needs the artifact and it
# is dropped whole; with moments enabled their named views need the artifact,
# and the luminosity channel writes whenever the collision evaluates -- so
# that combination is only honest when luminosity evaluation itself is off
# (OCTOPUS_PIC_LUMINOSITY_EVERY=0, the diagnostics benchmark's :moments
# mode). Anything else would silently write the rows the caller asked to
# suppress, so it errors instead.
disable_artifact = disable_luminosity_output && disable_moments
if disable_luminosity_output && !disable_moments && pic_luminosity_every != 0
    error("OCTOPUS_DISABLE_LUMINOSITY_OUTPUT=1 cannot suppress the " *
          "luminosity channel while the artifact exists for the moment " *
          "views and the collision still evaluates luminosity: also set " *
          "OCTOPUS_PIC_LUMINOSITY_EVERY=0, or OCTOPUS_DISABLE_MOMENTS=1 " *
          "to drop the artifact whole.")
end

line_ele = (
    electron_tccb2ip_inv,
    electron_tccb,
    electron_tccb2ip,
    lb,
    collision_elements...,
    rlb,
    electron_ip2tcca,
    electron_tcca,
    electron_ip2tcca_inv,
    electron_one_turn,
    electron_chrom,
    electron_rad,
    electron_observers...,
)

line_pro = (
    proton_tccb2ip_inv,
    proton_tccb,
    proton_tccb2ip,
    lb,
    collision_elements...,
    rlb,
    proton_ip2tcca,
    proton_tcca,
    proton_ip2tcca_inv,
    proton_one_turn,
    proton_chrom,
    proton_observers...,
)

task = StrongStrongTask(line_ele, line_pro;
    # Without this the launch geometry built above reaches only `Beam(...)` and
    # is then discarded: `task.policy === nothing` makes `execute!` resolve a
    # FRESH default policy, and the PIC per-kernel "inherit" path inherits that
    # default's 256 threads rather than OCTOPUS_CUDA_THREADS. Measured: a
    # harness policy of CPUThreadsExecutionPolicy(1) executed at
    # ResolvedCPUExecutionPolicy(4), and OCTOPUS_CUDA_THREADS=2048 -- an
    # impossible block size on every NVIDIA GPU -- ran to completion with
    # byte-identical output to the default, never reaching the device-limit
    # guard, because that guard sits on the policy path the task discarded. All
    # three documented launch knobs were inert for the thing they tune
    # (2026-08-05_b audit, U21-17).
    policy = policy,
    artifact = disable_artifact ? nothing :
               RunArtifact(artifact_path; capacity = artifact_capacity),
    diagnostics,
)
execute!(task, beam_ele, beam_pro; turns = turns)

# Under MPI every rank runs this whole file, so everything below happens P
# times. Which of those repetitions is correct differs line by line, and the
# distinction is made here once.
#
# The rank comes from `MPI.Comm_rank(MPI.COMM_WORLD)`, NOT from Octopus's
# `_mp_is_root()`. Octopus's collectives read a serial passthrough outside an
# active policy scope and `execute!` has already closed its scope by this line,
# so `_mp_is_root()` would return `true` on EVERY rank -- silently
# (docs/experiences.md, "A collective outside its scope is a silent no-op").
mpi_nranks = use_mpi ? MPI.Comm_size(MPI.COMM_WORLD) : 1
mpi_rank = use_mpi ? MPI.Comm_rank(MPI.COMM_WORLD) : 0
writes_files = mpi_rank == 0
if use_mpi
    # The configuration dump below is deliberately NOT root-gated: each rank
    # reporting the configuration it actually read is this repository's "assert
    # what the run recorded" rule, and a rank that resolved something different
    # should say so. This line tells the reader the repetition is expected.
    println("mpi_rank = ", mpi_rank, " of ", mpi_nranks)
end

if record_turn_times
    timings = turn_timings(task)
    println("turn_timings_seconds = ", join(timings, ','))
    timing_path = get(ENV, "OCTOPUS_TURN_TIMING_PATH", "")
    # One path, P ranks: without this gate every rank opens the same TSV for
    # writing and the file is whichever rank finished last, interleaved with
    # whichever had not. The stdout line above is per-rank on purpose (each
    # rank's own wall clock is real data); the FILE has one owner.
    if !isempty(timing_path) && writes_files
        # A relative path resolves against this harness's own result
        # directory, not the caller's cwd: the header's documented example
        # (result/pic_turn_times.tsv) used to land in repo-root result/,
        # contradicting the same header's claim that this harness keeps its
        # outputs beside the tests (2026-08-05 audit, U18-5).
        isabspath(timing_path) ||
            (timing_path = joinpath(@__DIR__, "..", timing_path))
        mkpath(dirname(timing_path))
        open(timing_path, "w") do io
            println(io, "turn\tseconds")
            for (turn, seconds) in enumerate(timings)
                println(io, turn - 1, '\t', seconds)
            end
        end
    end
end

# `beam_statistics` is a purely local reduction -- it issues no collective and
# takes no shard argument (src/beam/Beam.jl) -- and under MPI `beam_ele` holds
# this rank's SHARD. So these are the shard's moments, not the beam's, and the
# two are labelled apart below rather than printed under one name.
stats_ele = beam_statistics(beam_ele)
stats_pro = beam_statistics(beam_pro)
println("turns = ", turns)
println("n_macro_ele = ", n_macro_ele)
println("n_macro_pro = ", n_macro_pro)
println("poisson_solver = ", nameof(typeof(solver)))
println("beam_beam_collision = ", disable_collision ? "disabled" : "enabled")
println("weak_strong_limit = ", weak_strong_limit)
println("electron_energy_GeV = ", electron_energy / 1.0e9)
println("proton_energy_GeV = ", proton_energy / 1.0e9)
println("pic_longitudinal_kick = ", pic_longitudinal_kick)
println("pic_batch_mode = ", pic_batch_mode)
# The PIC-family lines print only when a PIC-family solver is actually in use
# (2026-08-05_b audit, U21-20). They used to print unconditionally, so a
# `OCTOPUS_SOLVER=gaussian` or `=spectral` run reported ten settings it never
# applied -- green_cache, the two slice-pair ratios, the four cuda_pic flags and
# the three luminosity ones -- none of which reaches a GaussianPoissonSolver or
# a SpectralPoissonSolver. A configuration dump that lists what was NOT applied
# is worse than one that stays quiet, because it is what a reader trusts when
# reconciling two runs.
if solver isa Union{PICPoissonSolver,GaussianPICPoissonSolver}
    println("cuda_pic_async = ", cuda_pic_async)
    println("cuda_pic_batch_fft = ", cuda_pic_batch_fft)
    println("cuda_pic_wavefront_fft = ", cuda_pic_wavefront_fft)
    println("cuda_pic_indexed_wavefront = ", cuda_pic_indexed_wavefront)
    println("pic_green_cache = ", pic_green_cache)
    println("pic_slice_pair_green_min_ratio = ", pic_slice_pair_green_min_ratio)
    println("pic_slice_pair_green_growth = ", pic_slice_pair_green_growth)
    println("pic_luminosity_every = ", pic_luminosity_every)
    # The grid the solver ACTUALLY uses. With OCTOPUS_SOLVER=gaussian_pic this
    # printed `input.solver.pic_grid` while the hybrid ran on `gpic_grid`
    # (default (64, 64) against a reported (128, 128)) -- U21-20.
    println("pic_luminosity_grid = ",
            pic_luminosity_grid !== nothing ? pic_luminosity_grid :
            solver isa GaussianPICPoissonSolver ? gpic_grid : input.solver.pic_grid)
    println("pic_luminosity_deposit_method = ",
            pic_luminosity_deposit_method === nothing ? "inherit" : pic_luminosity_deposit_method)
else
    println("pic_family_settings = not applied (solver is ", nameof(typeof(solver)), ")")
end
# Only the PIC-family solvers expose a resolved luminosity deposit method; the
# spectral and soft-Gaussian configurations have no such field.
let resolved = solver_configuration(solver)
    hasproperty(resolved, :resolved_luminosity_deposit_method) &&
        println("pic_luminosity_deposit_method_resolved = ",
                resolved.resolved_luminosity_deposit_method)
end
println("artifact = ", disable_artifact ? "disabled" : artifact_path)
# Report what was WRITTEN, not what was configured. These were gated on
# `disable_moments` alone, so `OCTOPUS_MOMENT_CAPACITY=0` -- the harness's
# documented way to disable moment output, folded into disable_moments above
# since the library-level capacity=0 spelling retired -- printed both groups
# as though they existed. Nothing wrote them (2026-08-05_b audit, U21-19;
# its claim that capacity=0 is silently ACCEPTED describes intended
# behaviour, but the reporting was wrong). The capacity=0 branch first, or
# the fold above would mask its more specific message.
_moment_status(group) = moment_capacity == 0 ? "disabled (OCTOPUS_MOMENT_CAPACITY=0)" :
                        disable_moments ? "disabled" :
                        "$(artifact_path):/moments/$(group)"
println("electron moments = ", _moment_status("electron"))
println("proton moments = ", _moment_status("proton"))
# Named for what they are. Under MPI this is one shard of `mpi_nranks`, and a
# reader comparing an MPI run's "electron rms" against a threads-only run's
# would otherwise be comparing a shard with a beam and calling the difference
# physics.
# At one rank the shard IS the beam, so the qualifier only appears when it is
# true. Keyed on the communicator's size, not on `use_mpi`.
_rms_label(beam) = mpi_nranks > 1 ?
    "$(beam) rms (rank $(mpi_rank) shard of $(mpi_nranks), not the whole beam)" :
    "$(beam) rms"
println(_rms_label("electron"), " = ", stats_ele.rms)
println(_rms_label("proton"), " = ", stats_pro.rms)

# ---------------------------------------------------------------------------
# PUBLISHED NAMES: what an including script may rely on.
#
# `validation/strong_strong_diagnostics_benchmark.jl` and
# `validation/strong_strong_pic_extreme_benchmark.jl` include this file and then
# read a dozen of its globals. None of that was a declared interface, so a
# rename here broke both with an `UndefVarError` at the END of a
# production-size GPU run -- after the measurement, not before it
# (2026-08-05_b audit, U25-15). This list IS the interface; `HARNESS_EXPORTS`
# lets an including script assert it before spending an hour.
#
# Adding a name here is free. Removing or renaming one is a breaking change to
# both benchmark scripts, and the assertion at the top of each will say so
# immediately rather than at the end.
# ---------------------------------------------------------------------------
const HARNESS_EXPORTS = (
    :input,                 # the resolved configuration NamedTuple
    :task,                  # the StrongStrongTask that was executed
    :solver,                # the Poisson solver it was built with
    :policy,                # the execution policy
    :artifact_path,         # the run artifact's path, whether or not anything wrote it
    :stats_ele,             # beam_statistics of each beam after the run
    :stats_pro,
)

"""
Assert that this harness still publishes everything `names` asks for.

Call it immediately after `include`ing the harness, so a rename fails in the
first second rather than after the measured run.
"""
function assert_harness_exports(names)
    missing_names = [n for n in names if !isdefined(@__MODULE__, n)]
    isempty(missing_names) || error(
        "the strong-strong harness no longer publishes " *
        join(missing_names, ", ") * ". Its published interface is " *
        "HARNESS_EXPORTS in test/examples/strong_strong_tracking.jl; update " *
        "this script and that list together.")
    return nothing
end
