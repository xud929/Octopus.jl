#=
Benchmark ONE CPU strong-strong `collide!` in isolation, with a bitwise digest.

Purpose. The end-to-end harnesses (`test/examples/strong_strong_tracking.jl`)
time a whole turn -- ring lines, observers, moment output and the collision
together -- which is the right number to report but the wrong instrument for
optimizing the solver: a 5% change inside `collide!` disappears into it, and one
run costs minutes. This script builds the same EIC crab-crossing production pair
and times `collide!` alone, repeatably, on the CPU.

It also prints a DIGEST: a rotate-then-xor fold over the raw Float64 bit pattern
of every coordinate of both beams after the collide. Two runs agree there only
if every particle is bitwise equal. That is the gate the CPU-threading campaign
runs against, because a threading change is allowed to be faster and is not
allowed to move a bit -- see `docs/history/cpu_threading_2026_08_09.md`. Compare
digests across thread counts, and across a change, rather than eyeballing the
luminosity.

Unlike `benchmark_strong_strong_pic.jl`, this script does NOT require CUDA.

It collides through the TASK path with one persistent task, so the Green cache
and workspace pool live across repeats exactly as they do under `execute!`.
Timing a public `collide!` instead measures a COLD cache on every call, which
is a property of the harness rather than of the solver -- see the comment at
`bench_task` for the measurement.

Structure. Build both beams once, snapshot their coordinates, then for each
repeat restore the snapshot and time one `collide!`. Restoring matters:
`collide!` mutates both beams, so without it repeat k solves a different problem
from repeat k-1 and the times are not comparable.

Run from the Octopus project root:

    julia --startup-file=no --project=. --threads=16 profiling/benchmark_collide_cpu.jl

On this 2-socket box also set `JULIA_THREAD_SLEEP_THRESHOLD=0` for any run above
~32 threads; idle Julia threads spin in `poptask` and compete for memory
bandwidth with the working ones (measured 11.0 -> 8.4 s at 128 threads). It
changes no results.

Environment switches, with the defaults shown at their read sites below:
OCTOPUS_BENCH_SOLVER (pic | gaussian_pic | spectral | gaussian),
OCTOPUS_BENCH_N_ELE, OCTOPUS_BENCH_N_PRO, OCTOPUS_BENCH_SLICES,
OCTOPUS_BENCH_GRID, OCTOPUS_BENCH_REPEATS, OCTOPUS_BENCH_PROFILE,
OCTOPUS_BENCH_PROFILE_PATH, OCTOPUS_BENCH_TAG, OCTOPUS_BENCH_TSV,
OCTOPUS_BENCH_BATCH_MODE (wavefront | sequential; the solvers' own keyword).

The production point is `OCTOPUS_BENCH_N_ELE=2560000 OCTOPUS_BENCH_N_PRO=1024000`
with the default 15 slices and grid 128; the defaults here are a quarter of that,
which is the iteration point -- it weights per-particle work against grid work
differently from production, so report both when they disagree.

Outputs: a summary to stdout, one appended row per run to OCTOPUS_BENCH_TSV when
set, and a sampling profile to OCTOPUS_BENCH_PROFILE_PATH when
OCTOPUS_BENCH_PROFILE=1.
=#

# OCTOPUS_BENCH_MPI=1 runs the same fixed point divided across MPI ranks. It
# requires PACKAGE mode -- `using Octopus`, not `include("src/Octopus.jl")` --
# because a package extension activates in no other, and without OctopusMPIExt
# a process under a launcher has no communicator and the policy refuses. The
# two modes are exclusive: including the source defines `Main.Octopus`, which
# a later `using Octopus` cannot then bind.
const BENCH_MPI = get(ENV, "OCTOPUS_BENCH_MPI", "0") == "1"
if BENCH_MPI
    @eval using Octopus
    @eval using MPI
else
    if !isdefined(Main, :Octopus)
        include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
    end
    @eval using .Octopus
end
using Printf
using Profile
using Dates

# Only the soft-Gaussian solver divides today (campaign step 4a); the others
# refuse, loudly, when asked to.
#
#     OCTOPUS_BENCH_MPI=1 OCTOPUS_BENCH_SOLVER=gaussian mpiexec -bind-to core \
#         -n 16 julia --startup-file=no --threads=4 profiling/benchmark_collide_cpu.jl
#
env_int(name, default) = parse(Int, get(ENV, name, string(default)))
env_bool(name, default) = get(ENV, name, default ? "1" : "0") in ("1", "true", "yes")

const SOLVER  = lowercase(get(ENV, "OCTOPUS_BENCH_SOLVER", "pic"))
const N_ELE   = env_int("OCTOPUS_BENCH_N_ELE", 640_000)
const N_PRO   = env_int("OCTOPUS_BENCH_N_PRO", 256_000)
const NSLICES = env_int("OCTOPUS_BENCH_SLICES", 15)
const GRID    = env_int("OCTOPUS_BENCH_GRID", 128)
const REPEATS = env_int("OCTOPUS_BENCH_REPEATS", 3)
const DOPROF  = env_bool("OCTOPUS_BENCH_PROFILE", false)
const TAG     = get(ENV, "OCTOPUS_BENCH_TAG", "")
const TSV     = get(ENV, "OCTOPUS_BENCH_TSV", "")
# The solvers' own keyword, exposed so the two schedules can be timed against
# each other; `:wavefront` is the solver default and stays the default here.
const BATCH_MODE = Symbol(lowercase(get(ENV, "OCTOPUS_BENCH_BATCH_MODE", "wavefront")))
# Which loop the slice-aligned PIC collide runs (step 4e): `auto` lets the
# schedule decide, `dataflow` and `batched` force one, so both can be timed
# back to back on the same box -- the only fair A/B on a shared machine.
const PIC_LOOP = Symbol(lowercase(get(ENV, "OCTOPUS_BENCH_PIC_LOOP", "auto")))

REPEATS > 0 || error("OCTOPUS_BENCH_REPEATS must be positive")
N_ELE > 0 && N_PRO > 0 || error("OCTOPUS_BENCH_N_ELE and _N_PRO must be positive")

set_global_rng!(seed = 123456789, method = :philox)

policy = BENCH_MPI ? MultiProcessExecutionPolicy(threads = :auto) :
                     CPUThreadsExecutionPolicy(threads = :auto)
if BENCH_MPI && !(SOLVER in ("gaussian", "pic"))
    error("OCTOPUS_BENCH_MPI=1 supports OCTOPUS_BENCH_SOLVER=gaussian (step 4a) " *
          "and pic (step 4c) only: gaussian_pic and spectral still refuse to " *
          "run divided.")
end

# The production case of test/examples/strong_strong_tracking.jl. Kept here as
# literals rather than included from that harness: this script must stay a
# fixed measurement point even when the harness's demo defaults change.
const ELE = (charge = -1.0, mass = EMASS_EV, energy = 10.0e9, n_particle = 1.7203e11,
             cutoff = 5.0, sigma = (106.0e-6, 9.5e-6, 0.7e-2),
             beta = (0.55, 0.056, 0.7e-2 / 5.5e-4), alpha = (0.0, 0.0, 0.0))
const PRO = (charge = 1.0, mass = PMASS_EV, energy = 275.0e9, n_particle = 0.6881e11,
             cutoff = 5.0, sigma = (95.0e-6, 8.5e-6, 6.0e-2),
             beta = (0.8, 0.072, 6.0e-2 / 6.6e-4), alpha = (0.0, 0.0, 0.0))

beam_ele = Beam(N_ELE, policy, Float64; beta = ELE.beta, alpha = ELE.alpha,
                sigma = ELE.sigma, cutoff = ELE.cutoff, rng_id = 1,
                charge = ELE.charge, mc2 = ELE.mass, E0 = ELE.energy,
                r0 = RE * ME0 / ELE.mass, npart = ELE.n_particle)
beam_pro = Beam(N_PRO, policy, Float64; beta = PRO.beta, alpha = PRO.alpha,
                sigma = PRO.sigma, cutoff = PRO.cutoff, rng_id = 2,
                charge = PRO.charge, mc2 = PRO.mass, E0 = PRO.energy,
                r0 = RE * ME0 / PRO.mass, npart = PRO.n_particle)

slicing = LongitudinalSlicing(; method = :normal_quantile, nslices = NSLICES,
                              center_position = :centroid)

solver = if SOLVER == "spectral"
    # The documented production recommendation for these ~11:1 flat beams.
    SpectralPoissonSolver(; slicing = slicing, grid = (127, 383),
                          domain_factor = 8.0, method = :grid,
                          longitudinal_kick = true, batch_mode = BATCH_MODE)
elseif SOLVER == "gaussian"
    GaussianPoissonSolver(; slicing = slicing, min_sigma = 1.0e-12,
                          longitudinal_kick = true, batch_mode = BATCH_MODE)
elseif SOLVER == "gaussian_pic"
    GaussianPICPoissonSolver(; slicing = slicing, grid = (GRID, GRID),
                             deposit_method = :CIC, green_type = :integrated,
                             green_cache = :slice_pair, longitudinal_kick = true,
                             batch_mode = BATCH_MODE)
elseif SOLVER == "pic"
    PICPoissonSolver(; slicing = slicing, grid = (GRID, GRID),
                     deposit_method = :CIC, green_type = :integrated,
                     green_cache = :slice_pair,
                     slice_pair_green_min_ratio = 0.50,
                     slice_pair_green_growth = 0.25,
                     longitudinal_kick = true, batch_mode = BATCH_MODE)
else
    error("OCTOPUS_BENCH_SOLVER must be pic | gaussian_pic | spectral | gaussian; " *
          "got $(repr(SOLVER))")
end

# Through `coordinate_arrays`, the public accessor, rather than `beam.rep.x`:
# AGENTS.md classes the representation as an implementation detail that may
# change, and a benchmark is a bad place to discover that it did.
snapshot(beam) = map(copy, coordinate_arrays(beam))
restore!(beam, snap) = foreach((a, b) -> copyto!(a, b), coordinate_arrays(beam), snap)

snap_ele = snapshot(beam_ele)
snap_pro = snapshot(beam_pro)

# Collide through the TASK path, not the public `collide!`, and hold one task
# across every repeat.
#
# `collide!(solver, b1, b2, backend)` builds a fresh Green cache AND a fresh
# workspace pool on every call, so it measures a COLD cache every time.
# Production does not: `execute!` keeps both in `task.runtime_cache` across
# turns. Measured at the production point, PIC's Green cache takes 450 misses on
# turn 1 and then 450 hits on turn 2, settling at ~60-90 rebuilds per turn -- so
# the direct path was charging 450 x 1.05 MB of Green-FFT copies to every
# collide, 0.68 GiB of the 1.02 GiB this script used to report. That is a
# property of the harness, not of the solver, and a benchmark that measures it
# is measuring the wrong thing (found by allocation-profiling gpic in the
# 2026-08-10 session).
#
# `Octopus._strong_strong_collide_backend!` is the same entry `execute!` uses
# per collision, and it is generic over all four solvers. Reaching for an
# internal here is what AGENTS.md permits a profiling script to do when the goal
# is to measure an implementation detail -- and the detail IS the caching. The task carries empty
# lines: nothing here tracks, so no element is needed -- only the runtime_cache.
# OCTOPUS_BENCH_CACHE_STATS=1 prints the slice-pair Green cache's hits, misses
# and rebuilds after every collide (every rank prints its own), the counters
# that say what a first-collide-after-warm-up slowdown is made of.
bench_task = StrongStrongTask((), (); poisson_solver = solver,
                              diagnostics = StrongStrongDiagnostics(
                                  cache_stats = env_bool("OCTOPUS_BENCH_CACHE_STATS", false)))
const BENCH_LABEL = :bench
bench_ctx(turn) = TrackingContext(turn = Int64(turn))

"""
Process CPU seconds (user+sys), read from `/proc/self/stat`.

Utilisation is `cpu / (wall * nthreads)`: 100% means every thread did useful
work for the whole collide. It is ONLY meaningful with
`JULIA_THREAD_SLEEP_THRESHOLD=0` -- otherwise idle Julia threads spin in
`poptask` and this counts that spinning as work.

Read the number as a diagnostic, not a target. Raising occupancy can make the
wall time WORSE when the added work is overhead: the per-batch worker
allocation measured 37.7% -> 42.1% utilisation and 3.20 -> 3.94 s at 16
threads. Compare CPU seconds against the 1-thread run -- the gap is what
parallelism costs.
"""
function cpu_seconds()
    stat = read("/proc/self/stat", String)
    fields = split(stat[findlast(==(')'), stat) + 1:end])
    return (parse(Int, fields[12]) + parse(Int, fields[13])) / 100
end

"""
Order-sensitive bitwise digest of every coordinate of every beam.

Rotate-then-xor over the raw bit patterns, so two digests agree only if every
coordinate is bitwise equal -- `==` on the whole state in one number. A
tolerance comparison would hide exactly the roundoff-scale movement a fold-order
or codegen change produces, which is what this campaign has to detect.
"""
function coordinate_digest(beams...)
    h = UInt64(0)
    for beam in beams, a in coordinate_arrays(beam), v in a
        h = (h << 1) | (h >> 63)
        h ⊻= reinterpret(UInt64, Float64(v))
    end
    return h
end

# Read from the communicator, not the policy field, and read once.
const BENCH_RANK, BENCH_RANKS = let
    resolved = Octopus._resolve_execution_policy(policy, beam_ele.rep)
    Octopus._with_execution_policy(resolved) do
        (Octopus._mp_rank(), Octopus._mp_nranks())
    end
end

# One scope for the whole measurement: every reduction the collide issues sees
# the communicator, and BOTH beams' shards are derived once instead of per
# collide. Both, keyed by beam (multi-process step 4b): this scoped one shard
# -- the electron beam's -- and the single-slot scope of the time handed it to
# the proton beam as well, so every divided measurement before 4b ran the
# proton beam's lane folds and shift origins at the electron beam's offset.
const BENCH_RESOLVED = Octopus._resolve_execution_policy(policy, beam_ele.rep)
# Inside the task's diagnostics scope too: `execute!` enters it and the
# collide's cache-statistics print reads it, so calling the collide directly
# without it silently prints nothing (the 3c lesson, met by this instrument
# a second time, 2026-09-05).
bench_scoped(f) = Base.ScopedValues.with(Octopus._ACTIVE_STRONG_STRONG_DIAGNOSTICS => bench_task.diagnostics,
                                         Octopus._PIC_SLICED_LOOP => PIC_LOOP) do
    Octopus._with_execution_policy(BENCH_RESOLVED) do
        Octopus._with_beam_shards(f, beam_ele.rep, beam_pro.rep)
    end
end

@printf("solver=%s rank=%d ranks=%d n_ele=%d n_pro=%d local_ele=%d slices=%d grid=%d julia_threads=%d\n",
        SOLVER, BENCH_RANK, BENCH_RANKS, N_ELE, N_PRO, length(beam_ele.rep),
        NSLICES, GRID, Threads.nthreads(:default))

# Two warm collides, not one: the first compiles and fills the Green cache
# cold, the second is the first to run against a warm cache. Timing from a
# single warm-up would still carry 450 cache misses.
for w in 1:2
    restore!(beam_ele, snap_ele)
    restore!(beam_pro, snap_pro)
    bench_scoped() do
        Octopus._strong_strong_collide_backend!(bench_task, BENCH_LABEL, solver, beam_ele, beam_pro,
                                        CPUThreadsBackend, bench_ctx(w))
    end
end

times = Float64[]
lums = Float64[]
digests = UInt64[]
gcs = Float64[]
cpus = Float64[]
allocs = Float64[]
# What the collectives cost, from the extension's clocks (rank 0 reports,
# after the timed collides). Reset here so the warm collides do not count.
BENCH_MPI && Octopus._mp_reset_collective_times!()
for _ in 1:REPEATS
    restore!(beam_ele, snap_ele)
    restore!(beam_pro, snap_pro)
    gc0 = Base.gc_num()
    cpu0 = cpu_seconds()
    t0 = time_ns()
    lum = bench_scoped() do
        Octopus._strong_strong_collide_backend!(bench_task, BENCH_LABEL, solver,
                                          beam_ele, beam_pro, CPUThreadsBackend,
                                          bench_ctx(10 + length(times)))
    end
    dt = (time_ns() - t0) / 1e9
    cpu = cpu_seconds() - cpu0
    gc1 = Base.gc_num()
    gc_s = (gc1.total_time - gc0.total_time) / 1e9
    nthreads = Threads.nthreads(:default)
    alloc_gib = (gc1.allocd - gc0.allocd + gc1.total_allocd - gc0.total_allocd) / 2^30
    @printf("  rank %d collide %.4f s   gc %.4f s (%.1f%%)   cpu %.1f s   util %.1f%%   alloc %.3f GiB%s\n",
            BENCH_RANK, dt, gc_s, 100 * gc_s / dt, cpu, 100 * cpu / (dt * nthreads), alloc_gib,
            get(ENV, "JULIA_THREAD_SLEEP_THRESHOLD", "") == "0" ? "" :
                "   (idle threads spinning: util inflated)")
    if env_bool("OCTOPUS_BENCH_CACHE_STATS", false) && BENCH_RANK == 0
        # The task's own cache objects, read after the collide: what THIS
        # process's cache holds and how it was used, cumulative.
        for (k, v) in bench_task.runtime_cache
            v isa Octopus._PICSlicePairGreenCache || continue
            @printf("  rank 0 green cache %s: entries %d hits %d misses %d rebuilds %d\n",
                    repr(objectid(v)), length(v.entries), v.hits, v.misses, v.rebuilds)
        end
    end
    push!(times, dt)
    push!(lums, lum)
    push!(digests, coordinate_digest(beam_ele, beam_pro))
    push!(gcs, gc_s)
    push!(cpus, cpu)
    push!(allocs, (gc1.allocd - gc0.allocd + gc1.total_allocd - gc0.total_allocd) / 2^30)
end

if BENCH_MPI && BENCH_RANK == 0
    ct = Octopus._mp_collective_times()
    if ct !== nothing
        total_ns = sum(last, values(ct); init=0)
        @printf("COLLECTIVES rank 0 over %d collides: %.4f s in MPI calls (%.1f%% of %.4f s wall)\n",
                REPEATS, total_ns / 1e9, 100 * total_ns / 1e9 / sum(times), sum(times))
        for kind in sort(collect(keys(ct)); by=string)
            calls, ns = ct[kind]
            @printf("  %-12s calls %7d   %.4f s   %.1f us/call\n", kind, calls, ns / 1e9, ns / 1e3 / calls)
        end
    end
end
sorted = sort(times)
median = sorted[cld(length(sorted), 2)]
# The row reports the MEDIAN run's own gc/cpu/allocation, not an average across
# repeats: mixing the median of one quantity with the mean of another describes
# no run that happened.
med_i = findfirst(==(median), times)
@printf("MEDIAN %.4f s   min %.4f   max %.4f\n", median, first(sorted), last(sorted))
@printf("luminosity = %.17g\n", first(lums))
@printf("DIGEST 0x%016x   (repeats agree: %s)\n",
        first(digests), all(==(first(digests)), digests))
# Repeats that disagree mean the solver is not deterministic on identical input,
# which invalidates every timing comparison made with this script.
all(==(first(digests)), digests) ||
    @warn "repeats produced different coordinates; timings below are not comparable"

if !isempty(TSV)
    dir = dirname(TSV)
    isempty(dir) || isdir(dir) || mkpath(dir)
    fresh = !isfile(TSV)
    # `datetime` and `commit` come from the caller when there is one, so a
    # nightly row identifies the tree it measured rather than the moment the
    # file was written. Falling back to `now()` and "unknown" keeps a hand run
    # from writing an empty column.
    stamp = get(ENV, "OCTOPUS_BENCH_STAMP", "")
    isempty(stamp) && (stamp = Dates.format(Dates.now(), "yyyymmdd_HHMMSS"))
    commit = get(ENV, "OCTOPUS_BENCH_COMMIT", "unknown")
    open(TSV, "a") do io
        fresh && println(io,
            "datetime\tcommit\thost\ttag\tsolver\tn_ele\tn_pro\tslices\tgrid\t" *
            "julia_threads\tmedian_s\tmin_s\tmax_s\tgc_s\tcpu_s\tutil_pct\t" *
            "alloc_gib\tluminosity\tdigest")
        # Field by field rather than one long `@printf` format: `@printf`
        # requires a LITERAL format string, so a concatenated one is a load-time
        # error -- which is how the first run of `nightly_benchmark.sh` failed,
        # after every solver had finished its timings. Per-field formatting also
        # keeps each column next to the header entry it belongs to.
        nthreads = Threads.nthreads(:default)
        row = (stamp, commit, gethostname(), TAG, SOLVER,
               string(N_ELE), string(N_PRO), string(NSLICES), string(GRID),
               string(nthreads),
               @sprintf("%.6f", median),
               @sprintf("%.6f", first(sorted)),
               @sprintf("%.6f", last(sorted)),
               @sprintf("%.4f", gcs[med_i]),
               @sprintf("%.2f", cpus[med_i]),
               @sprintf("%.1f", 100 * cpus[med_i] / (median * nthreads)),
               @sprintf("%.4f", allocs[med_i]),
               @sprintf("%.17g", first(lums)),
               @sprintf("0x%016x", first(digests)))
        println(io, join(row, '\t'))
    end
    println("appended to $TSV")
end

if DOPROF
    path = get(ENV, "OCTOPUS_BENCH_PROFILE_PATH", "profiling/log/collide_cpu_profile.txt")
    dir = dirname(path)
    isempty(dir) || isdir(dir) || mkpath(dir)
    Profile.init(n = 20_000_000, delay = 0.001)
    restore!(beam_ele, snap_ele)
    restore!(beam_pro, snap_pro)
    Profile.clear()
    # INSIDE the scope: outside it a divided run profiles an undivided collide
    # of this rank's shard (the 3c lesson -- a collective outside its scope is
    # a no-op -- met by the instrument itself, 2026-09-05).
    @profile bench_scoped() do
        Octopus._strong_strong_collide_backend!(bench_task, BENCH_LABEL, solver,
                                                beam_ele, beam_pro, CPUThreadsBackend,
                                                bench_ctx(99))
    end
    open(path, "w") do io
        println(io, "======== FLAT (self time) ========")
        Profile.print(io, format = :flat, sortedby = :count, mincount = 10, maxdepth = 200)
        println(io, "\n\n======== TREE ========")
        Profile.print(io, format = :tree, maxdepth = 40, mincount = 20)
    end
    println("profile written to $path")
end
