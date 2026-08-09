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
OCTOPUS_BENCH_PROFILE_PATH, OCTOPUS_BENCH_TAG, OCTOPUS_BENCH_TSV.

The production point is `OCTOPUS_BENCH_N_ELE=2560000 OCTOPUS_BENCH_N_PRO=1024000`
with the default 15 slices and grid 128; the defaults here are a quarter of that,
which is the iteration point -- it weights per-particle work against grid work
differently from production, so report both when they disagree.

Outputs: a summary to stdout, one appended row per run to OCTOPUS_BENCH_TSV when
set, and a sampling profile to OCTOPUS_BENCH_PROFILE_PATH when
OCTOPUS_BENCH_PROFILE=1.
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus
using Printf
using Profile

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

REPEATS > 0 || error("OCTOPUS_BENCH_REPEATS must be positive")
N_ELE > 0 && N_PRO > 0 || error("OCTOPUS_BENCH_N_ELE and _N_PRO must be positive")

set_global_rng!(seed = 123456789, method = :philox)

policy = CPUThreadsExecutionPolicy(threads = :auto)

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
                          longitudinal_kick = true)
elseif SOLVER == "gaussian"
    GaussianPoissonSolver(; slicing = slicing, min_sigma = 1.0e-12,
                          longitudinal_kick = true, batch_mode = :wavefront)
elseif SOLVER == "gaussian_pic"
    GaussianPICPoissonSolver(; slicing = slicing, grid = (GRID, GRID),
                             deposit_method = :CIC, green_type = :integrated,
                             green_cache = :slice_pair, longitudinal_kick = true,
                             batch_mode = :wavefront)
elseif SOLVER == "pic"
    PICPoissonSolver(; slicing = slicing, grid = (GRID, GRID),
                     deposit_method = :CIC, green_type = :integrated,
                     green_cache = :slice_pair,
                     slice_pair_green_min_ratio = 0.50,
                     slice_pair_green_growth = 0.25,
                     longitudinal_kick = true, batch_mode = :wavefront)
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

@printf("solver=%s n_ele=%d n_pro=%d slices=%d grid=%d julia_threads=%d\n",
        SOLVER, N_ELE, N_PRO, NSLICES, GRID, Threads.nthreads(:default))

collide!(solver, beam_ele, beam_pro, CPUThreadsBackend)     # compile + warm caches

times = Float64[]
lums = Float64[]
digests = UInt64[]
for _ in 1:REPEATS
    restore!(beam_ele, snap_ele)
    restore!(beam_pro, snap_pro)
    gc0 = Base.gc_num()
    cpu0 = cpu_seconds()
    t0 = time_ns()
    lum = collide!(solver, beam_ele, beam_pro, CPUThreadsBackend)
    dt = (time_ns() - t0) / 1e9
    cpu = cpu_seconds() - cpu0
    gc1 = Base.gc_num()
    gc_s = (gc1.total_time - gc0.total_time) / 1e9
    nthreads = Threads.nthreads(:default)
    @printf("  collide %.4f s   gc %.4f s (%.1f%%)   cpu %.1f s   util %.1f%%%s\n",
            dt, gc_s, 100 * gc_s / dt, cpu, 100 * cpu / (dt * nthreads),
            get(ENV, "JULIA_THREAD_SLEEP_THRESHOLD", "") == "0" ? "" :
                "   (idle threads spinning: util inflated)")
    push!(times, dt)
    push!(lums, lum)
    push!(digests, coordinate_digest(beam_ele, beam_pro))
end

sorted = sort(times)
median = sorted[cld(length(sorted), 2)]
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
    open(TSV, "a") do io
        fresh && println(io, "tag\tsolver\tn_ele\tn_pro\tslices\tgrid\tjulia_threads\t" *
                             "median_s\tmin_s\tmax_s\tluminosity\tdigest")
        @printf(io, "%s\t%s\t%d\t%d\t%d\t%d\t%d\t%.6f\t%.6f\t%.6f\t%.17g\t0x%016x\n",
                TAG, SOLVER, N_ELE, N_PRO, NSLICES, GRID, Threads.nthreads(:default),
                median, first(sorted), last(sorted), first(lums), first(digests))
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
    @profile collide!(solver, beam_ele, beam_pro, CPUThreadsBackend)
    open(path, "w") do io
        println(io, "======== FLAT (self time) ========")
        Profile.print(io, format = :flat, sortedby = :count, mincount = 10, maxdepth = 200)
        println(io, "\n\n======== TREE ========")
        Profile.print(io, format = :tree, maxdepth = 40, mincount = 20)
    end
    println("profile written to $path")
end
