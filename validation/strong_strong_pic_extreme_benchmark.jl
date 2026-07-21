#=
Benchmark the fastest accepted CUDA strong-strong 2D PIC path at production
macroparticle count. The reference uses 2.56M electrons, 1M protons, a 128×128
grid, 15 slices per beam, wavefront batching, asynchronous field solves, and
the persistent slice-pair Green cache. Complete-turn timings include one CUDA
synchronization at each boundary. The first 20 of 30 turns are warm-up; the
last 10 are the primary steady-state sample.

Inputs are the fixed defaults below and may be overridden with the same
environment variables accepted by `examples/strong_strong_tracking.jl`.
Outputs are the printed physics summary and `result/pic_extreme_turn_times.tsv`.

Run from the project root:

    julia --project=. validation/strong_strong_pic_extreme_benchmark.jl
=#

defaults = Dict(
    "OCTOPUS_USE_GPU" => "1",
    "OCTOPUS_POISSON_SOLVER" => "PIC",
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

include(joinpath(@__DIR__, "..", "examples", "strong_strong_tracking.jl"))

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
    "git_commit" => readchomp(`git rev-parse HEAD`),
    "julia_version" => string(VERSION),
    "gpu" => string(CUDA.name(CUDA.device())),
    "cuda_driver" => string(CUDA.driver_version()),
    "cuda_runtime" => string(CUDA.runtime_version()),
    "precision" => "Float64",
    "turns" => string(length(timings)),
    "n_macro_ele" => ENV["OCTOPUS_N_MACRO_ELE"],
    "n_macro_pro" => ENV["OCTOPUS_N_MACRO_PRO"],
    "grid" => "128x128",
    "deposit_method" => string(input.solver.pic_deposit_method),
    "luminosity_deposit_method" => string(solver.luminosity_deposit_method),
    "resolved_luminosity_deposit_method" => string(
        solver_configuration(solver).resolved_luminosity_deposit_method),
    "slices_per_beam" => "15",
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
open(summary_path, "w") do io
    println(io, "key\tvalue")
    for (key, value) in summary
        println(io, key, '\t', value)
    end
end
println("benchmark_summary = ", summary_path)
