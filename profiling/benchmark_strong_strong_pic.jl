#=
Benchmark strong-strong PIC scheduling options on CPU and CUDA.

The benchmark uses identical initial host coordinates for every run, warms each
configuration before timing, and reports the median steady-state time. Physics
work is held constant: luminosity and the longitudinal kick remain enabled.

Run from the Octopus project root, preferably with one CPU thread per physical
core on a single socket:

    julia --threads=32 --project=. profiling/benchmark_strong_strong_pic.jl

Useful size controls:

    OCTOPUS_BENCH_N_MACRO=20000
    OCTOPUS_BENCH_TURNS=2
    OCTOPUS_BENCH_REPEATS=3
    OCTOPUS_BENCH_WARMUP_TURNS=1
    OCTOPUS_BENCH_SLICES=15
    OCTOPUS_BENCH_GRID=128
    OCTOPUS_BENCH_CACHE_MIN_RATIO=0.50
    OCTOPUS_BENCH_CACHE_GROWTH=0.25
    OCTOPUS_BENCH_CUDA_CONFIGS=wavefront_indexed,wavefront_batched
    OCTOPUS_BENCH_CPU_CONFIGS=cpu_sequential,cpu_wavefront
    OCTOPUS_BENCH_RESULT_PATH=result/strong_strong_pic_benchmark.tsv

The tab-separated summary is written to
`result/strong_strong_pic_benchmark.tsv`. Set
`OCTOPUS_BENCH_PROFILE_FASTEST=0` to skip the final CUDA phase profile.
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

N_MACRO > 0 || error("OCTOPUS_BENCH_N_MACRO must be positive")
TURNS > 0 || error("OCTOPUS_BENCH_TURNS must be positive")
REPEATS > 0 || error("OCTOPUS_BENCH_REPEATS must be positive")
WARMUP_TURNS >= 0 || error("OCTOPUS_BENCH_WARMUP_TURNS must be non-negative")
NSLICES > 0 || error("OCTOPUS_BENCH_SLICES must be positive")
GRID_SIZE > 2 || error("OCTOPUS_BENCH_GRID must be greater than 2")

const CUDA_CONFIGS = [
    (name="sequential_batched", batch_mode=:sequential, green_cache=:none,
     async=true, batch_fft=true, wavefront_fft=true, wavefront_green_fft=true,
     indexed=false, batch_luminosity=false, async_luminosity=false),
    (name="sequential_four_stream", batch_mode=:sequential, green_cache=:none,
     async=true, batch_fft=false, wavefront_fft=true, wavefront_green_fft=true,
     indexed=false, batch_luminosity=false, async_luminosity=false),
    (name="sequential_synchronous", batch_mode=:sequential, green_cache=:none,
     async=false, batch_fft=true, wavefront_fft=true, wavefront_green_fft=true,
     indexed=false, batch_luminosity=false, async_luminosity=false),
    (name="wavefront_batched", batch_mode=:wavefront, green_cache=:none,
     async=true, batch_fft=true, wavefront_fft=true, wavefront_green_fft=true,
     indexed=false, batch_luminosity=false, async_luminosity=false),
    (name="wavefront_pair_batched", batch_mode=:wavefront, green_cache=:none,
     async=true, batch_fft=true, wavefront_fft=false, wavefront_green_fft=true,
     indexed=false, batch_luminosity=false, async_luminosity=false),
    (name="wavefront_four_stream", batch_mode=:wavefront, green_cache=:none,
     async=true, batch_fft=false, wavefront_fft=true, wavefront_green_fft=true,
     indexed=false, batch_luminosity=false, async_luminosity=false),
    (name="wavefront_indexed", batch_mode=:wavefront, green_cache=:none,
     async=true, batch_fft=true, wavefront_fft=true, wavefront_green_fft=true,
     indexed=true, batch_luminosity=false, async_luminosity=false),
    (name="wavefront_batched_luminosity", batch_mode=:wavefront, green_cache=:none,
     async=true, batch_fft=true, wavefront_fft=true, wavefront_green_fft=true,
     indexed=false, batch_luminosity=true, async_luminosity=false),
    (name="wavefront_async_luminosity", batch_mode=:wavefront, green_cache=:none,
     async=true, batch_fft=true, wavefront_fft=true, wavefront_green_fft=true,
     indexed=false, batch_luminosity=false, async_luminosity=true),
    (name="sequential_slice_pair_cache", batch_mode=:sequential, green_cache=:slice_pair,
     async=true, batch_fft=true, wavefront_fft=true, wavefront_green_fft=true,
     indexed=false, batch_luminosity=false, async_luminosity=false),
    (name="wavefront_slice_pair_cache", batch_mode=:wavefront, green_cache=:slice_pair,
     async=true, batch_fft=true, wavefront_fft=true, wavefront_green_fft=true,
     indexed=false, batch_luminosity=false, async_luminosity=false),
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

function set_cuda_options!(cfg; timing=false)
    ENV["OCTOPUS_CUDA_PIC_ASYNC"] = cfg.async ? "1" : "0"
    ENV["OCTOPUS_CUDA_PIC_BATCH_FFT"] = cfg.batch_fft ? "1" : "0"
    ENV["OCTOPUS_CUDA_PIC_WAVEFRONT_FFT"] = cfg.wavefront_fft ? "1" : "0"
    ENV["OCTOPUS_CUDA_PIC_WAVEFRONT_GREEN_FFT"] = cfg.wavefront_green_fft ? "1" : "0"
    ENV["OCTOPUS_CUDA_PIC_INDEXED_WAVEFRONT"] = cfg.indexed ? "1" : "0"
    ENV["OCTOPUS_CUDA_PIC_BATCH_LUMINOSITY"] = cfg.batch_luminosity ? "1" : "0"
    ENV["OCTOPUS_CUDA_PIC_ASYNC_LUMINOSITY"] = cfg.async_luminosity ? "1" : "0"
    ENV["OCTOPUS_CUDA_PIC_TIMING"] = timing ? "1" : "0"
    ENV["OCTOPUS_CUDA_PIC_TIMING_DETAIL"] = "0"
    ENV["OCTOPUS_CUDA_NVTX"] = "0"
    ENV["OCTOPUS_PIC_CACHE_STATS"] = CACHE_STATS ? "1" : "0"
    return nothing
end

function make_base_beams()
    set_global_rng!(seed=123456789, method=:philox)
    electron = Beam(N_MACRO, CPUThreadsBackend, Float64;
        beta=(0.55, 0.056, 0.7e-2 / 5.5e-4), alpha=(0.0, 0.0),
        sigma=(106.0e-6, 9.5e-6, 0.7e-2), cutoff=5.0, rng_id=1,
        charge=-1.0, mc2=EMASS_EV, E0=10.0e9,
        r0=RE * ME0 / EMASS_EV, npart=1.7203e11)
    proton = Beam(N_MACRO, CPUThreadsBackend, Float64;
        beta=(0.8, 0.072, 6.0e-2 / 6.6e-4), alpha=(0.0, 0.0),
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

function make_task(cfg, luminosity_path)
    slicing = LongitudinalSlicing(method=:normal_quantile, nslices=NSLICES,
                                  center_position=:centroid)
    solver = PICPoissonSolver(slicing=slicing, grid=(GRID_SIZE, GRID_SIZE),
        deposit_method=:CIC, green_type=:integrated, green_cache=cfg.green_cache,
        slice_pair_green_min_ratio=CACHE_MIN_RATIO,
        slice_pair_green_growth=CACHE_GROWTH,
        longitudinal_kick=true, batch_mode=cfg.batch_mode, luminosity_schedule=nothing)
    ip = StrongStrongCollision(:ip; poisson_solver=solver)
    return StrongStrongTask((ip,), (ip,); luminosity_path=luminosity_path)
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
    lines = readlines(path)
    isempty(lines) && return NaN
    fields = split(lines[end], '\t')
    return parse(Float64, fields[end])
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

function run_configuration(cfg, backend, base1, base2, tempdir; profile=false)
    backend === CUDABackend && set_cuda_options!(cfg; timing=profile)
    lum_path = joinpath(tempdir, cfg.name * ".lum")
    task = make_task(cfg, lum_path)

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
            luminosity = read_last_luminosity(lum_path)
        end
    end
    med = median_value(times)
    return (name=cfg.name, backend=backend === CUDABackend ? "cuda" : "cpu",
            seconds=med, seconds_per_turn=med / TURNS, samples=times,
            luminosity=luminosity, beam1=final1, beam2=final2)
end

function print_result(result, reference=nothing)
    if reference === nothing
        max_abs = 0.0
        rel = 0.0
        lum_rel = 0.0
    else
        max1, rel1 = coordinate_error(result.beam1, reference.beam1)
        max2, rel2 = coordinate_error(result.beam2, reference.beam2)
        max_abs = max(max1, max2)
        rel = max(rel1, rel2)
        lum_rel = abs(result.luminosity - reference.luminosity) /
                  max(abs(reference.luminosity), eps(Float64))
    end
    println(rpad(result.name, 38),
            " median=", round(result.seconds_per_turn; digits=6), " s/turn",
            " samples=", join(round.(result.samples; digits=4), ","),
            " max_abs=", max_abs, " coord_rel=", rel, " lum_rel=", lum_rel)
    return max_abs, rel, lum_rel
end

function errors_against(result, reference)
    max1, rel1 = coordinate_error(result.beam1, reference.beam1)
    max2, rel2 = coordinate_error(result.beam2, reference.beam2)
    lum_rel = abs(result.luminosity - reference.luminosity) /
              max(abs(reference.luminosity), eps(Float64))
    return max(max1, max2), max(rel1, rel2), lum_rel
end

function write_summary(path, results, cpu_reference)
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, "backend\tconfiguration\tseconds_per_turn\tmedian_seconds\tsamples_seconds\tmax_coordinate_abs_vs_cpu_reference\tcoordinate_rel_vs_cpu_reference\tluminosity_rel_vs_cpu_reference\tphysics_consistent\tluminosity")
        for result in results
            max_abs, rel, lum_rel = errors_against(result, cpu_reference)
            consistent = rel <= PHYSICS_RTOL && lum_rel <= PHYSICS_RTOL
            println(io, join((result.backend, result.name, result.seconds_per_turn,
                result.seconds, join(result.samples, ","), max_abs, rel, lum_rel,
                consistent, result.luminosity), '\t'))
        end
    end
end

function profile_configuration(cfg, base1, base2, tempdir)
    lum_path = joinpath(tempdir, "profile_" * cfg.name * ".lum")
    set_cuda_options!(cfg; timing=false)
    task = make_task(cfg, lum_path)
    if WARMUP_TURNS > 0
        warm1 = clone_cuda(base1)
        warm2 = clone_cuda(base2)
        execute!(task, warm1, warm2; turns=WARMUP_TURNS)
        CUDA.synchronize()
    end
    set_cuda_options!(cfg; timing=true)
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
    println("\nCUDA configurations")
    cuda_results = Any[]
    for cfg in cuda_configs
        GC.gc(true)
        CUDA.reclaim()
        result = run_configuration(cfg, CUDABackend, base1, base2, tempdir)
        push!(cuda_results, result)
        push!(all_results, result)
        print_result(result, isempty(cuda_results) ? nothing : cuda_results[1])
    end

    println("\nCPU configurations")
    cpu_results = Any[]
    for cfg in cpu_configs
        GC.gc(true)
        result = run_configuration(cfg, CPUThreadsBackend, base1, base2, tempdir)
        push!(cpu_results, result)
        push!(all_results, result)
        print_result(result, isempty(cpu_results) ? nothing : cpu_results[1])
    end

    raw_fastest_cuda = cuda_results[argmin(getproperty.(cuda_results, :seconds_per_turn))]
    cpu_reference = cpu_results[1]
    raw_fastest_cpu = cpu_results[argmin(getproperty.(cpu_results, :seconds_per_turn))]
    consistent_cpu = filter(cpu_results) do result
        _, rel, lum_rel = errors_against(result, cpu_reference)
        rel <= PHYSICS_RTOL && lum_rel <= PHYSICS_RTOL
    end
    fastest_cpu = consistent_cpu[argmin(getproperty.(consistent_cpu, :seconds_per_turn))]
    consistent_cuda = filter(cuda_results) do result
        _, rel, lum_rel = errors_against(result, cpu_reference)
        rel <= PHYSICS_RTOL && lum_rel <= PHYSICS_RTOL
    end
    fastest_cuda = isempty(consistent_cuda) ? nothing :
        consistent_cuda[argmin(getproperty.(consistent_cuda, :seconds_per_turn))]
    comparison_cuda = fastest_cuda === nothing ? raw_fastest_cuda : fastest_cuda
    speedup = fastest_cpu.seconds_per_turn / comparison_cuda.seconds_per_turn
    max_abs, coord_rel, lum_rel = errors_against(comparison_cuda, cpu_reference)

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
    println("  CPU/GPU max coordinate abs error = ", max_abs)
    println("  CPU/GPU coordinate relative L2 error = ", coord_rel)
    println("  CPU/GPU luminosity relative error = ", lum_rel)

    write_summary(RESULT_PATH, all_results, cpu_reference)
    println("  summary = ", RESULT_PATH)

    if PROFILE_FASTEST && fastest_cuda !== nothing
        println("\nCUDA phase profile for validated fastest configuration (one steady-state turn):")
        cfg = CUDA_CONFIGS[findfirst(c -> c.name == fastest_cuda.name, CUDA_CONFIGS)]
        profile_configuration(cfg, base1, base2, tempdir)
    elseif PROFILE_FASTEST
        println("\nSkipping CUDA phase profile because no configuration met the physics tolerance.")
    end
end
