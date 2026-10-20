#=
Benchmark strong-strong PIC scheduling options on CPU and CUDA.

The benchmark uses identical initial host coordinates for every run, warms each
configuration before timing, and reports the median steady-state time. Physics
work is held constant: luminosity and the longitudinal kick remain enabled.

Every configuration is a NamedTuple whose fields other than `name` are passed
straight through as `PICPoissonSolver` keywords (`batch_mode`, `green_cache`
and, on CUDA, `cuda_async`, `cuda_batch_fft`, `cuda_wavefront_fft`,
`cuda_indexed_wavefront`), so a configuration field the solver does not read
cannot exist here: it is an unknown-keyword error, never a silently identical
run. `solver_default` is derived from `PICPoissonSolver()` itself.

Fixed point and provenance. The physics case (the 20k-per-beam EIC-shaped e-p
pair below, 15 slices, grid 128, seed 123456789) is unchanged since the first
version (2026-07-17). On 2026-10-19 (fix batch unit X, comprehensive audit
2026-10-18 F-200) the driver was ported to the run artifact: the task carries
`artifact = RunArtifact(path)` and the physics check reads the last luminosity
row back with `read(TaskOutput(path), :luminosity; name = "ip")` -- the
`luminosity_path` keyword and the `.lum` text file were retired 2026-08-17/18
and the driver had been dead since. Its eleven CUDA "configurations" differed
only through `OCTOPUS_CUDA_PIC_*` environment switches that no runtime code
reads, so only four were distinct; they now set the solver's own keywords, the
two rows whose switches have no runtime counterpart at all
(`wavefront_batched_luminosity`, `wavefront_async_luminosity`) are gone, and
the roster is nine named rows plus `solver_default`. The phase profile of the
fastest validated configuration runs under
`StrongStrongDiagnostics(pic_timing = true)` instead of an environment switch.
Rows recorded before 2026-10-19 came from a driver that compared four
configurations under eleven names: do not compare rows by name across that
date.

Run from the Octopus project root, preferably with one CPU thread per physical
core on a single socket:

    julia --threads=32 --project=. profiling/benchmark_strong_strong_pic.jl

Size and selection controls, defaults shown -- every OCTOPUS_BENCH_* name this
script reads (the list is checked against the read sites at load; the
`let` block after the `const`s):

    OCTOPUS_BENCH_N_MACRO=20000
    OCTOPUS_BENCH_TURNS=2
    OCTOPUS_BENCH_REPEATS=3
    OCTOPUS_BENCH_WARMUP_TURNS=1
    OCTOPUS_BENCH_SLICES=15
    OCTOPUS_BENCH_GRID=128
    OCTOPUS_BENCH_CACHE_MIN_RATIO=0.50
    OCTOPUS_BENCH_CACHE_GROWTH=0.25
    OCTOPUS_BENCH_PHYSICS_RTOL=1e-10
    OCTOPUS_BENCH_CACHE_STATS=0
    OCTOPUS_BENCH_PROFILE_FASTEST=1
    OCTOPUS_BENCH_CUDA_CONFIGS=wavefront_indexed,wavefront_batched   (default: every row)
    OCTOPUS_BENCH_CPU_CONFIGS=cpu_sequential,cpu_wavefront           (default: every row)
    OCTOPUS_BENCH_RESULT_PATH=result/strong_strong_pic_benchmark.tsv

The tab-separated summary is written to
`result/strong_strong_pic_benchmark.tsv`. Set
`OCTOPUS_BENCH_PROFILE_FASTEST=0` to skip the final CUDA phase profile.

Physics verdict, like with like (2026-10-20, fix batch 2 of the 2026-10-18
comprehensive audit). Every row -- CPU and CUDA -- is judged against the FIRST
CPU row with the SAME `green_cache` at `OCTOPUS_BENCH_PHYSICS_RTOL` (coordinate
relative L2 and luminosity), and the summary's `reference` column names it. The
slice-pair cache is a discretisation choice (cached Green grids expanded by the
growth factor and reused across pairs), so judged against the `:none` CPU row
the `solver_default` row read 1.76e-4 "inconsistent" on both backends
identically (unit X, fix batch 2026-10-19) -- the cache's discretisation, not a
kernel. That difference is now printed as INFO (CPU slice-pair against CPU
`:none`) and not gated; a row inconsistent with its own-cache reference fails
the run with exit 1 after the summary is written (`BENCH-PHYSICS ...
verdict=FAIL`), where the column used to be written and read by nothing. The
CPU rows run first (they are the references); a `OCTOPUS_BENCH_CPU_CONFIGS`
selection that leaves a cache without its CPU reference is refused by name.

The gate's CUDA arm runs this benchmark at a reduced size (the testset
"CUDA-requiring validation scripts run in the gate's CUDA arm" in
test/runtests.jl reads the line below; validation/README.md); its timings at
that size are a run receipt, not a performance record:

GATE-CUDA-ARM: env OCTOPUS_BENCH_N_MACRO=2000 OCTOPUS_BENCH_GRID=32 OCTOPUS_BENCH_SLICES=5 OCTOPUS_BENCH_TURNS=1 OCTOPUS_BENCH_REPEATS=1 OCTOPUS_BENCH_WARMUP_TURNS=1 OCTOPUS_BENCH_PROFILE_FASTEST=0 OCTOPUS_BENCH_RESULT_PATH=@TMP@/strong_strong_pic_benchmark.tsv ; verdict "BENCH-PHYSICS rows=14 consistent=14"
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus
import CUDA

CUDA.functional(false) || error("CUDA is not functional in this Julia session")

const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))
const RESULT_PATH = normpath(joinpath(PROJECT_ROOT,
    get(ENV, "OCTOPUS_BENCH_RESULT_PATH", "result/strong_strong_pic_benchmark.tsv")))
const BOOL_TRUE = ("1", "true", "TRUE", "yes", "YES")

env_int(name, default) = parse(Int, get(ENV, name, string(default)))
env_bool(name, default) = get(ENV, name, default ? "1" : "0") in BOOL_TRUE

const N_MACRO = env_int("OCTOPUS_BENCH_N_MACRO", 20_000)
const TURNS = env_int("OCTOPUS_BENCH_TURNS", 2)
const REPEATS = env_int("OCTOPUS_BENCH_REPEATS", 3)
const WARMUP_TURNS = env_int("OCTOPUS_BENCH_WARMUP_TURNS", 1)
const NSLICES = env_int("OCTOPUS_BENCH_SLICES", 15)
const GRID_SIZE = env_int("OCTOPUS_BENCH_GRID", 128)
const CACHE_MIN_RATIO = parse(Float64, get(ENV, "OCTOPUS_BENCH_CACHE_MIN_RATIO", "0.50"))
const CACHE_GROWTH = parse(Float64, get(ENV, "OCTOPUS_BENCH_CACHE_GROWTH", "0.25"))
const PROFILE_FASTEST = env_bool("OCTOPUS_BENCH_PROFILE_FASTEST", true)
const CACHE_STATS = env_bool("OCTOPUS_BENCH_CACHE_STATS", false)
const PHYSICS_RTOL = parse(Float64, get(ENV, "OCTOPUS_BENCH_PHYSICS_RTOL", "1e-10"))

# The header's OCTOPUS_BENCH_* list against what this file reads, so the two
# cannot drift (five names were missing from it before 2026-10-19,
# comprehensive audit F-202): the header is the text above the first `=#`.
let text = read(@__FILE__, String)
    header, body = split(text, "=#"; limit=2)
    named = Set(m.match for m in eachmatch(r"OCTOPUS_BENCH_[A-Z_]+", header))
    read_names = Set(m.match for m in eachmatch(r"OCTOPUS_BENCH_[A-Z_]+", body))
    named == read_names || error("benchmark header drift: named but never read " *
        string(sort!(collect(setdiff(named, read_names)))) * "; read but not named " *
        string(sort!(collect(setdiff(read_names, named)))))
end

N_MACRO > 0 || error("OCTOPUS_BENCH_N_MACRO must be positive")
TURNS > 0 || error("OCTOPUS_BENCH_TURNS must be positive")
REPEATS > 0 || error("OCTOPUS_BENCH_REPEATS must be positive")
WARMUP_TURNS >= 0 || error("OCTOPUS_BENCH_WARMUP_TURNS must be non-negative")
NSLICES > 0 || error("OCTOPUS_BENCH_SLICES must be positive")
GRID_SIZE > 2 || error("OCTOPUS_BENCH_GRID must be greater than 2")

# One NamedTuple per configuration: `name`, then PICPoissonSolver keywords
# verbatim (header). The CUDA rows are the first version's roster minus the
# two whose switches had no runtime counterpart; the explicit
# `cuda_indexed_wavefront=false` on every row but `wavefront_indexed` is that
# roster's baseline, not the solver's default (`true`), which is why
# `solver_default` -- the constructor's own values, read off an instance --
# closes the list.
const CUDA_CONFIGS = [
    (name="sequential_batched", batch_mode=:sequential, green_cache=:none,
     cuda_async=true, cuda_batch_fft=true, cuda_wavefront_fft=true, cuda_indexed_wavefront=false),
    (name="sequential_four_stream", batch_mode=:sequential, green_cache=:none,
     cuda_async=true, cuda_batch_fft=false, cuda_wavefront_fft=true, cuda_indexed_wavefront=false),
    (name="sequential_synchronous", batch_mode=:sequential, green_cache=:none,
     cuda_async=false, cuda_batch_fft=true, cuda_wavefront_fft=true, cuda_indexed_wavefront=false),
    (name="wavefront_batched", batch_mode=:wavefront, green_cache=:none,
     cuda_async=true, cuda_batch_fft=true, cuda_wavefront_fft=true, cuda_indexed_wavefront=false),
    (name="wavefront_pair_batched", batch_mode=:wavefront, green_cache=:none,
     cuda_async=true, cuda_batch_fft=true, cuda_wavefront_fft=false, cuda_indexed_wavefront=false),
    (name="wavefront_four_stream", batch_mode=:wavefront, green_cache=:none,
     cuda_async=true, cuda_batch_fft=false, cuda_wavefront_fft=true, cuda_indexed_wavefront=false),
    (name="wavefront_indexed", batch_mode=:wavefront, green_cache=:none,
     cuda_async=true, cuda_batch_fft=true, cuda_wavefront_fft=true, cuda_indexed_wavefront=true),
    (name="sequential_slice_pair_cache", batch_mode=:sequential, green_cache=:slice_pair,
     cuda_async=true, cuda_batch_fft=true, cuda_wavefront_fft=true, cuda_indexed_wavefront=false),
    (name="wavefront_slice_pair_cache", batch_mode=:wavefront, green_cache=:slice_pair,
     cuda_async=true, cuda_batch_fft=true, cuda_wavefront_fft=true, cuda_indexed_wavefront=false),
    let d = PICPoissonSolver()
        (name="solver_default", batch_mode=d.batch_mode, green_cache=d.green_cache,
         cuda_async=d.cuda_async, cuda_batch_fft=d.cuda_batch_fft,
         cuda_wavefront_fft=d.cuda_wavefront_fft,
         cuda_indexed_wavefront=d.cuda_indexed_wavefront)
    end,
]

const CPU_CONFIGS = [
    (name="cpu_sequential", batch_mode=:sequential, green_cache=:none),
    (name="cpu_wavefront", batch_mode=:wavefront, green_cache=:none),
    (name="cpu_sequential_slice_pair_cache", batch_mode=:sequential, green_cache=:slice_pair),
    (name="cpu_wavefront_slice_pair_cache", batch_mode=:wavefront, green_cache=:slice_pair),
]

function selected_configs(configs, env_name)
    selection = strip(get(ENV, env_name, ""))
    isempty(selection) && return configs
    requested = Set(strip.(split(selection, ',')))
    available = Set(cfg.name for cfg in configs)
    missing = setdiff(requested, available)
    isempty(missing) || error("unknown configurations in $(env_name): $(join(sort!(collect(missing)), ", "))")
    return filter(cfg -> cfg.name in requested, configs)
end

# Everything but `name` is a solver keyword (header): a field the solver does
# not read is an unknown-keyword error, never a silently identical run.
solver_options(cfg) = NamedTuple{filter(!=(:name), keys(cfg))}(cfg)

function make_base_beams()
    set_global_rng!(seed=123456789, method=:philox)
    electron = Beam(N_MACRO, CPUThreadsBackend, Float64;
        beta=(0.55, 0.056, 0.7e-2 / 5.5e-4), alpha=(0.0, 0.0, 0.0),
        sigma=(106.0e-6, 9.5e-6, 0.7e-2), cutoff=5.0, rng_id=1,
        charge=-1.0, mc2=EMASS_EV, E0=10.0e9,
        r0=RE * ME0 / EMASS_EV, npart=1.7203e11)
    proton = Beam(N_MACRO, CPUThreadsBackend, Float64;
        beta=(0.8, 0.072, 6.0e-2 / 6.6e-4), alpha=(0.0, 0.0, 0.0),
        sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0, rng_id=2,
        charge=1.0, mc2=PMASS_EV, E0=275.0e9,
        r0=RE * ME0 / PMASS_EV, npart=0.6881e11)
    return electron, proton
end

function clone_cpu(beam)
    arrays = map(x -> copy(Array(x)), coordinate_arrays(beam.rep))
    rep = Phase6DRep(arrays...)
    return Beam{CPUThreadsBackend,typeof(beam.params),typeof(rep)}(beam.params, rep)
end

function clone_cuda(beam)
    arrays = map(x -> CUDA.CuArray(Array(x)), coordinate_arrays(beam.rep))
    rep = Phase6DRep(arrays...)
    return Beam{CUDABackend,typeof(beam.params),typeof(rep)}(beam.params, rep)
end

clone_for_backend(beam, ::Type{CPUThreadsBackend}) = clone_cpu(beam)
clone_for_backend(beam, ::Type{CUDABackend}) = clone_cuda(beam)

function make_task(cfg, artifact_path; profile=false)
    slicing = LongitudinalSlicing(method=:normal_quantile, nslices=NSLICES,
                                  center_position=:centroid)
    solver = PICPoissonSolver(; slicing=slicing, grid=(GRID_SIZE, GRID_SIZE),
        deposit_method=:CIC, green_type=:integrated,
        slice_pair_green_min_ratio=CACHE_MIN_RATIO,
        slice_pair_green_growth=CACHE_GROWTH,
        longitudinal_kick=true, luminosity_schedule=nothing,
        solver_options(cfg)...)
    ip = StrongStrongCollision(:ip; poisson_solver=solver)
    # The artifact is the task's one output; `/luminosity/ip` is what the
    # physics check reads back. `append=false`: every execute! of the task
    # rewrites the file, so the last repeat's rows are what remain.
    return StrongStrongTask((ip,), (ip,); artifact=RunArtifact(artifact_path),
        diagnostics=StrongStrongDiagnostics(pic_timing=profile, cache_stats=CACHE_STATS))
end

sync_backend(::Type{CPUThreadsBackend}) = nothing
sync_backend(::Type{CUDABackend}) = CUDA.synchronize()

function median_value(values)
    ordered = sort(values)
    n = length(ordered)
    isodd(n) && return ordered[(n + 1) ÷ 2]
    return (ordered[n ÷ 2] + ordered[n ÷ 2 + 1]) / 2
end

function read_last_luminosity(path)
    series = read(TaskOutput(path), :luminosity; name="ip")
    isempty(series.value) && return NaN
    return Float64(last(series.value))
end

host_coordinates(beam) = map(x -> Array(x), coordinate_arrays(beam.rep))

function coordinate_error(a, b)
    sum_diff2 = 0.0
    sum_ref2 = 0.0
    max_abs = 0.0
    for (xa, xb) in zip(a, b)
        for i in eachindex(xa, xb)
            d = Float64(xa[i] - xb[i])
            max_abs = max(max_abs, abs(d))
            sum_diff2 += d * d
            sum_ref2 += Float64(xb[i])^2
        end
    end
    return max_abs, sqrt(sum_diff2 / max(sum_ref2, eps(Float64)))
end

function run_configuration(cfg, backend, base1, base2, tempdir)
    artifact_path = joinpath(tempdir, cfg.name * ".h5")
    task = make_task(cfg, artifact_path)

    if WARMUP_TURNS > 0
        warm1 = clone_for_backend(base1, backend)
        warm2 = clone_for_backend(base2, backend)
        execute!(task, warm1, warm2; turns=WARMUP_TURNS)
        sync_backend(backend)
    end

    times = Float64[]
    final1 = nothing
    final2 = nothing
    luminosity = NaN
    for repeat in 1:REPEATS
        beam1 = clone_for_backend(base1, backend)
        beam2 = clone_for_backend(base2, backend)
        sync_backend(backend)
        t0 = time_ns()
        execute!(task, beam1, beam2; turns=TURNS)
        sync_backend(backend)
        push!(times, (time_ns() - t0) * 1.0e-9)
        if repeat == REPEATS
            final1 = host_coordinates(beam1)
            final2 = host_coordinates(beam2)
            luminosity = read_last_luminosity(artifact_path)
        end
    end
    med = median_value(times)
    return (name=cfg.name, backend=backend === CUDABackend ? "cuda" : "cpu",
            green_cache=cfg.green_cache,
            seconds=med, seconds_per_turn=med / TURNS, samples=times,
            luminosity=luminosity, beam1=final1, beam2=final2)
end

function errors_against(result, reference)
    max1, rel1 = coordinate_error(result.beam1, reference.beam1)
    max2, rel2 = coordinate_error(result.beam2, reference.beam2)
    lum_rel = abs(result.luminosity - reference.luminosity) /
              max(abs(reference.luminosity), eps(Float64))
    return max(max1, max2), max(rel1, rel2), lum_rel
end

# LIKE WITH LIKE (fix batch 2 of the 2026-10-18 comprehensive audit,
# 2026-10-20): a row's physics reference is the FIRST CPU row with the same
# `green_cache`. The slice-pair cache is a discretisation choice -- its cached
# Green grids are expanded by `slice_pair_green_growth` and reused across pairs,
# so they are not the `:none` route's per-pair grids -- and the verdict here is
# about backend and schedule agreement at `PHYSICS_RTOL`, not about the cache's
# own discretisation. Judged against the `:none` CPU row, `solver_default`
# (`:slice_pair`) read 1.76e-4 "inconsistent" on BOTH backends identically
# (unit X's observation, fix batch 2026-10-19): a verdict that cannot
# distinguish a wrong kernel from a different discretisation. The cache's
# discretisation difference is printed as INFO below, not gated. A selection
# (OCTOPUS_BENCH_CPU_CONFIGS) that leaves a cache value without its CPU
# reference is refused by name rather than judged against the wrong one.
function reference_for(result, cpu_results)
    index = findfirst(r -> r.green_cache === result.green_cache, cpu_results)
    index === nothing && error(
        "no CPU reference row with green_cache = $(repr(result.green_cache)) for " *
        "$(result.name): include a CPU configuration with that cache in " *
        "OCTOPUS_BENCH_CPU_CONFIGS (every row is judged against the CPU row of its own cache)")
    return cpu_results[index]
end

function print_result(result, reference)
    max_abs, rel, lum_rel = errors_against(result, reference)
    println(rpad(result.name, 38),
            " median=", round(result.seconds_per_turn; digits=6), " s/turn",
            " samples=", join(round.(result.samples; digits=4), ","),
            " max_abs=", max_abs, " coord_rel=", rel, " lum_rel=", lum_rel,
            " vs ", reference.name)
    return max_abs, rel, lum_rel
end

consistent_with(result, reference) = begin
    _, rel, lum_rel = errors_against(result, reference)
    rel <= PHYSICS_RTOL && lum_rel <= PHYSICS_RTOL
end

function write_summary(path, results, cpu_results)
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, "backend\tconfiguration\tgreen_cache\treference\tseconds_per_turn\tmedian_seconds\tsamples_seconds\tmax_coordinate_abs_vs_reference\tcoordinate_rel_vs_reference\tluminosity_rel_vs_reference\tphysics_consistent\tluminosity")
        for result in results
            reference = reference_for(result, cpu_results)
            max_abs, rel, lum_rel = errors_against(result, reference)
            consistent = rel <= PHYSICS_RTOL && lum_rel <= PHYSICS_RTOL
            println(io, join((result.backend, result.name, result.green_cache, reference.name,
                result.seconds_per_turn, result.seconds, join(result.samples, ","),
                max_abs, rel, lum_rel, consistent, result.luminosity), '\t'))
        end
    end
end

function profile_configuration(cfg, base1, base2, tempdir)
    # One task with `pic_timing=true` from construction: a diagnostic is a
    # task field, not an environment switch flipped between two execute!s,
    # so the warm-up turns print a profile as well -- the labelled
    # steady-state block is the one to read.
    task = make_task(cfg, joinpath(tempdir, "profile_" * cfg.name * ".h5"); profile=true)
    if WARMUP_TURNS > 0
        println("  [warm-up: JIT and cache build, not steady state]")
        warm1 = clone_cuda(base1)
        warm2 = clone_cuda(base2)
        execute!(task, warm1, warm2; turns=WARMUP_TURNS)
        CUDA.synchronize()
    end
    println("  [steady-state turn]")
    beam1 = clone_cuda(base1)
    beam2 = clone_cuda(base2)
    execute!(task, beam1, beam2; turns=1)
    CUDA.synchronize()
    return nothing
end

println("Strong-strong PIC configuration benchmark")
println("  particles per beam = ", N_MACRO)
println("  slices             = ", NSLICES)
println("  grid               = ", GRID_SIZE, " x ", GRID_SIZE)
println("  cache min ratio    = ", CACHE_MIN_RATIO)
println("  cache growth       = ", CACHE_GROWTH)
println("  timed turns        = ", TURNS)
println("  repeats            = ", REPEATS)
println("  warmup turns       = ", WARMUP_TURNS)
println("  physics tolerance  = ", PHYSICS_RTOL)
println("  Julia threads      = ", Threads.nthreads())
println("  CUDA device        = ", CUDA.device())

base1, base2 = make_base_beams()
all_results = Any[]
cuda_configs = selected_configs(CUDA_CONFIGS, "OCTOPUS_BENCH_CUDA_CONFIGS")
cpu_configs = selected_configs(CPU_CONFIGS, "OCTOPUS_BENCH_CPU_CONFIGS")

mktempdir() do tempdir
    # CPU first: its rows are the references every row is judged against.
    println("\nCPU configurations (each row against the first CPU row of its own green_cache)")
    cpu_results = Any[]
    for cfg in cpu_configs
        GC.gc(true)
        result = run_configuration(cfg, CPUThreadsBackend, base1, base2, tempdir)
        push!(cpu_results, result)
        push!(all_results, result)
        print_result(result, reference_for(result, cpu_results))
    end
    isempty(cpu_results) && error("OCTOPUS_BENCH_CPU_CONFIGS selected no CPU configuration; the CPU rows are the references")

    println("\nCUDA configurations (each row against the CPU row of its own green_cache)")
    cuda_results = Any[]
    for cfg in cuda_configs
        GC.gc(true)
        CUDA.reclaim()
        result = run_configuration(cfg, CUDABackend, base1, base2, tempdir)
        push!(cuda_results, result)
        push!(all_results, result)
        print_result(result, reference_for(result, cpu_results))
    end

    # The cache's own discretisation, reported and not gated: the slice-pair
    # CPU reference against the :none CPU reference, when both exist.
    let none = findfirst(r -> r.green_cache === :none, cpu_results),
        pair = findfirst(r -> r.green_cache === :slice_pair, cpu_results)
        if none !== nothing && pair !== nothing
            _, rel, lum_rel = errors_against(cpu_results[pair], cpu_results[none])
            println("\nINFO slice-pair cache discretisation (CPU ", cpu_results[pair].name,
                    " vs CPU ", cpu_results[none].name, ", not gated): coord_rel=", rel,
                    " lum_rel=", lum_rel)
        end
    end

    raw_fastest_cuda = cuda_results[argmin(getproperty.(cuda_results, :seconds_per_turn))]
    raw_fastest_cpu = cpu_results[argmin(getproperty.(cpu_results, :seconds_per_turn))]
    consistent_cpu = filter(r -> consistent_with(r, reference_for(r, cpu_results)), cpu_results)
    fastest_cpu = consistent_cpu[argmin(getproperty.(consistent_cpu, :seconds_per_turn))]
    consistent_cuda = filter(r -> consistent_with(r, reference_for(r, cpu_results)), cuda_results)
    fastest_cuda = isempty(consistent_cuda) ? nothing :
        consistent_cuda[argmin(getproperty.(consistent_cuda, :seconds_per_turn))]
    comparison_cuda = fastest_cuda === nothing ? raw_fastest_cuda : fastest_cuda
    speedup = fastest_cpu.seconds_per_turn / comparison_cuda.seconds_per_turn
    comparison_reference = reference_for(comparison_cuda, cpu_results)
    max_abs, coord_rel, lum_rel = errors_against(comparison_cuda, comparison_reference)

    println("\nFastest configurations")
    println("  raw CUDA = ", raw_fastest_cuda.name, " at ", raw_fastest_cuda.seconds_per_turn, " s/turn")
    if fastest_cuda === nothing
        println("  validated CUDA = none met physics tolerance ", PHYSICS_RTOL)
    else
        println("  validated CUDA = ", fastest_cuda.name, " at ", fastest_cuda.seconds_per_turn, " s/turn")
    end
    println("  raw CPU = ", raw_fastest_cpu.name, " at ", raw_fastest_cpu.seconds_per_turn, " s/turn")
    println("  validated CPU = ", fastest_cpu.name, " at ", fastest_cpu.seconds_per_turn, " s/turn")
    println("  compared CUDA speedup over CPU = ", speedup, "x")
    println("  CPU/GPU max coordinate abs error = ", max_abs, " (", comparison_cuda.name, " vs ", comparison_reference.name, ")")
    println("  CPU/GPU coordinate relative L2 error = ", coord_rel)
    println("  CPU/GPU luminosity relative error = ", lum_rel)

    write_summary(RESULT_PATH, all_results, cpu_results)
    println("  summary = ", RESULT_PATH)
    # The physics verdict is a VERDICT: a row inconsistent with the CPU row of
    # its own cache is a backend or schedule disagreement, and the run says so
    # with exit 1 after the summary is written. Before 2026-10-20 the column
    # was written and nothing read it.
    inconsistent = [r.backend * "/" * r.name for r in all_results
                    if !consistent_with(r, reference_for(r, cpu_results))]
    println("BENCH-PHYSICS rows=", length(all_results), " consistent=",
            length(all_results) - length(inconsistent), " tolerance=", PHYSICS_RTOL,
            " verdict=", isempty(inconsistent) ? "PASS" : "FAIL")
    isempty(inconsistent) || error("physics_consistent is false for " * join(inconsistent, ", ") *
                                   " against the CPU row of the same green_cache (tolerance $(PHYSICS_RTOL))")

    if PROFILE_FASTEST && fastest_cuda !== nothing
        println("\nCUDA phase profile for validated fastest configuration (one steady-state turn):")
        cfg = CUDA_CONFIGS[findfirst(c -> c.name == fastest_cuda.name, CUDA_CONFIGS)]
        profile_configuration(cfg, base1, base2, tempdir)
    elseif PROFILE_FASTEST
        println("\nSkipping CUDA phase profile because no configuration met the physics tolerance.")
    end
end
