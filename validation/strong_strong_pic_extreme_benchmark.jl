#=
Benchmark the fastest accepted CUDA strong-strong 2D PIC path at production
macroparticle count. The reference uses 2.56M electrons, 1M protons, a 128×128
grid, 15 slices per beam, wavefront batching, asynchronous field solves, and
the persistent slice-pair Green cache. Complete-turn timings include one CUDA
synchronization at each boundary. The first 20 of 30 turns are warm-up; the
last 10 are the primary steady-state sample.

Inputs are the fixed defaults below and may be overridden with the same
environment variables accepted by `test/examples/strong_strong_tracking.jl`
(the clean `examples/` counterpart reads no environment variables), EXCEPT
the two that would make this something other than the CUDA PIC benchmark:
`OCTOPUS_USE_GPU=0` and an `OCTOPUS_SOLVER` other than `pic` are refused by
name before the harness is included. Until 2026-10-22 a CPU override ran the
whole production-size workload on CPU threads and then died at the summary's
`CUDA.name(CUDA.device())` -- the harness binds `CUDA` only under `use_gpu` --
a failure at the end of a long run (2026-10-18 comprehensive audit,
F-243/U54-3). The summary's `precision`, `grid` and `slices_per_beam` rows are
read off the solver the run used (its element type, `grid` and per-beam
slicing), not typed here (U54-5), and `git_commit` is this script's tree
whatever the working directory.
Outputs (2026-08-05_b audit, U25-8 -- the second file was undocumented, and it
is the one that carries the provenance):

    result/pic_extreme_turn_times.tsv  per-turn wall times
    result/pic_extreme_summary.tsv     git commit, GPU and driver, resolved
                                       CUDA launch configuration, timings

plus the printed physics summary.

Run from the project root:

    julia --project=. validation/strong_strong_pic_extreme_benchmark.jl

The gate's CUDA arm runs this benchmark at a reduced size, 20 turns (the
minimum its steady-state window needs) of 4000 macroparticles per beam, so the
driver, the harness's CUDA path and the summary's launch-family provenance are
executed by the gate rather than by nobody (the testset "CUDA-requiring
validation scripts run in the gate's CUDA arm" in test/runtests.jl reads the
line below; validation/README.md). Its timings at that size are not a
performance record.

GATE-CUDA-ARM: env OCTOPUS_N_MACRO_ELE=4000 OCTOPUS_N_MACRO_PRO=4000 OCTOPUS_TURNS=20 OCTOPUS_RESULT_DIR=@TMP@ OCTOPUS_TURN_TIMING_PATH=@TMP@/pic_extreme_turn_times.tsv OCTOPUS_BENCHMARK_SUMMARY_PATH=@TMP@/pic_extreme_summary.tsv ; verdict "benchmark_summary = "
=#

defaults = Dict(
    "OCTOPUS_USE_GPU" => "1",
    "OCTOPUS_SOLVER" => "PIC",
    "OCTOPUS_TURNS" => "30",
    "OCTOPUS_N_MACRO_ELE" => "2560000",
    "OCTOPUS_N_MACRO_PRO" => "1000000",
    "OCTOPUS_PIC_BATCH_MODE" => "wavefront",
    "OCTOPUS_PIC_GREEN_CACHE" => "slice_pair",
    "OCTOPUS_CUDA_PIC_ASYNC" => "1",
    "OCTOPUS_CUDA_PIC_BATCH_FFT" => "1",
    "OCTOPUS_CUDA_PIC_WAVEFRONT_FFT" => "1",
    "OCTOPUS_CUDA_PIC_INDEXED_WAVEFRONT" => "1",
    "OCTOPUS_PIC_SLICE_PAIR_GREEN_MIN_RATIO" => "0.50",
    "OCTOPUS_PIC_SLICE_PAIR_GREEN_GROWTH" => "0.25",
    "OCTOPUS_PIC_LUMINOSITY_EVERY" => "0",
    "OCTOPUS_DISABLE_LUMINOSITY_OUTPUT" => "1",
    "OCTOPUS_DISABLE_MOMENTS" => "1",
    "OCTOPUS_RECORD_TURN_TIMES" => "1",
    "OCTOPUS_TURN_TIMING_PATH" => joinpath(@__DIR__, "..", "result", "pic_extreme_turn_times.tsv"),
)
for (key, value) in defaults
    haskey(ENV, key) || (ENV[key] = value)
end
# Refused BEFORE the include, by name (F-243/U54-3): the benchmark measures the
# CUDA PIC path, and the summary's GPU, driver and launch-family rows exist
# only there. The harness's own boolean spellings (its `env_bool`).
let gpu = lowercase(strip(ENV["OCTOPUS_USE_GPU"])), solver_name = lowercase(strip(ENV["OCTOPUS_SOLVER"]))
    gpu in ("1", "true", "yes", "on") || error(
        "OCTOPUS_USE_GPU=$(repr(ENV["OCTOPUS_USE_GPU"])): this script is the CUDA PIC reference benchmark and " *
        "records the device, driver and launch families in its summary; for a CPU run use " *
        "test/examples/strong_strong_tracking.jl directly.")
    solver_name == "pic" || error(
        "OCTOPUS_SOLVER=$(repr(ENV["OCTOPUS_SOLVER"])): this script benchmarks the CUDA PIC path and reads " *
        "PICPoissonSolver's grid, slicing and launch families; the diagnostics benchmark " *
        "(validation/strong_strong_diagnostics_benchmark.jl) is the one with a solver switch.")
end

include(joinpath(@__DIR__, "..", "test", "examples", "strong_strong_tracking.jl"))
# Assert the harness's published interface BEFORE anything else reads it:
# these names were an undeclared dependency, and a rename in the harness
# surfaced as an UndefVarError at the end of a production-size GPU run
# (2026-08-05_b audit, U25-15).
assert_harness_exports((:input, :task, :solver, :policy))

solver isa PICPoissonSolver || error("the harness built a $(nameof(typeof(solver))); this benchmark reads PICPoissonSolver's fields")
_solver_eltype(::PICPoissonSolver{T}) where {T} = T
timings = turn_timings(task)
length(timings) >= 20 || error("benchmark requires at least 20 turns so the final 10 exclude warm-up")
steady = timings[(end - 9):end]
steady_mean = sum(steady) / length(steady)
sorted = sort(steady)
steady_median = (sorted[5] + sorted[6]) / 2
steady_min = minimum(steady)
steady_std = sqrt(sum((x - steady_mean)^2 for x in steady) / (length(steady) - 1))
println("steady_last_ten_mean_seconds = ", steady_mean)
println("steady_last_ten_median_seconds = ", steady_median)
println("steady_last_ten_min_seconds = ", steady_min)
println("steady_last_ten_std_seconds = ", steady_std)

summary_path = get(ENV, "OCTOPUS_BENCHMARK_SUMMARY_PATH",
                   joinpath(@__DIR__, "..", "result", "pic_extreme_summary.tsv"))
mkpath(dirname(summary_path))
summary = [
    # This script's tree, not the caller's cwd (U54-3; the diagnostics benchmark
    # made the same change on 2026-10-20).
    "git_commit" => readchomp(`git -C $(dirname(@__DIR__)) rev-parse HEAD`),
    "julia_version" => string(VERSION),
    "gpu" => string(CUDA.name(CUDA.device())),
    "cuda_driver" => string(CUDA.driver_version()),
    "cuda_runtime" => string(CUDA.runtime_version()),
    # Read off the solver the run used, not typed (F-243/U54-5: three string
    # literals shadowed the harness's values with nothing to notice a change).
    "precision" => string(_solver_eltype(solver)),
    "turns" => string(length(timings)),
    "n_macro_ele" => ENV["OCTOPUS_N_MACRO_ELE"],
    "n_macro_pro" => ENV["OCTOPUS_N_MACRO_PRO"],
    "grid" => join(string.(solver.grid), "x"),
    "deposit_method" => string(input.solver.pic_deposit_method),
    "luminosity_deposit_method" => string(solver.luminosity_deposit_method),
    "resolved_luminosity_deposit_method" => string(
        solver_configuration(solver).resolved_luminosity_deposit_method),
    "slices_per_beam" => (solver.slicing1.nslices == solver.slicing2.nslices ? string(solver.slicing1.nslices) :
                          "$(solver.slicing1.nslices)/$(solver.slicing2.nslices)"),
    "batch_mode" => ENV["OCTOPUS_PIC_BATCH_MODE"],
    "green_cache" => ENV["OCTOPUS_PIC_GREEN_CACHE"],
    "slice_pair_green_min_ratio" => ENV["OCTOPUS_PIC_SLICE_PAIR_GREEN_MIN_RATIO"],
    "slice_pair_green_growth" => ENV["OCTOPUS_PIC_SLICE_PAIR_GREEN_GROWTH"],
    "indexed_wavefront" => ENV["OCTOPUS_CUDA_PIC_INDEXED_WAVEFRONT"],
    "steady_last_ten_mean_seconds" => string(steady_mean),
    "steady_last_ten_median_seconds" => string(steady_median),
    "steady_last_ten_min_seconds" => string(steady_min),
    "steady_last_ten_std_seconds" => string(steady_std),
]
if policy isa CUDAExecutionPolicy
    push!(summary, "cuda_fused_threads_requested" => string(policy.launch.threads))
    push!(summary, "cuda_fused_blocks_requested" => string(policy.launch.blocks))
    push!(summary, "cuda_fused_blocks_resolution" =>
        (policy.launch.blocks === :auto ? "per_compiled_kernel_occupancy_and_particle_coverage" :
                                          "explicit"))
    config_entries = configuration_report(solver; policy=policy, backend=CUDABackend)
    # Derive the family list, do not re-type it (2026-08-05_b audit, U25-6).
    # This tuple used to be hand-copied here. `only(filter(...))` throws if a
    # LISTED family disappears, but an eighth family added to the solver would
    # simply never appear in the provenance summary -- a run recorded as fully
    # provenanced while silently omitting a launch parameter that shaped it.
    # That is Measured Lesson 4: a hand-maintained copy of a set that grows has
    # nothing to keep it honest.
    for family in Octopus._CUDA_PIC_LAUNCH_FAMILIES
        option = Symbol(:cuda_pic_, family, :_threads)
        entry = only(filter(item -> item.name === option, config_entries))
        push!(summary, string(option, "_requested") => string(entry.requested))
        push!(summary, string(option, "_resolved") => string(entry.resolved))
    end
end
open(summary_path, "w") do io
    println(io, "key\tvalue")
    for (key, value) in summary
        println(io, key, '\t', value)
    end
end
println("benchmark_summary = ", summary_path)
