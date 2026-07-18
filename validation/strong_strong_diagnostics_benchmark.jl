#=
Measure strong-strong moment and luminosity diagnostics without changing the
validated PIC solver configuration. The default target is 200 turns; turns
100-199 form the measured window so a moment capacity of 100 includes one
representative HDF5 flush.

Modes:
  baseline       no moments, no luminosity calculation or file
  luminosity     luminosity calculation, no luminosity file
  luminosity_io  luminosity calculation and text file
  moments        two moment files, no luminosity calculation or file
  both           moments plus luminosity calculation and text file

Run from the project root, for example:

  OCTOPUS_DIAGNOSTIC_BENCHMARK_MODE=baseline \
    julia --project=. validation/strong_strong_diagnostics_benchmark.jl
=#

mode = Symbol(lowercase(get(ENV, "OCTOPUS_DIAGNOSTIC_BENCHMARK_MODE", "baseline")))
mode in (:baseline, :luminosity, :luminosity_io, :moments, :both) ||
    error("unknown diagnostic benchmark mode: $(mode)")

turns = parse(Int, get(ENV, "OCTOPUS_DIAGNOSTIC_BENCHMARK_TURNS", "200"))
sample_turns = parse(Int, get(ENV, "OCTOPUS_DIAGNOSTIC_BENCHMARK_SAMPLE_TURNS", "100"))
turns >= sample_turns || error("turns must be at least sample_turns")

moments_enabled = mode in (:moments, :both)
luminosity_enabled = mode in (:luminosity, :luminosity_io, :both)
luminosity_file_enabled = mode in (:luminosity_io, :both)
result_dir = joinpath(@__DIR__, "..", "result")
timing_path = joinpath(result_dir, "pic_diagnostics_$(mode)_turn_times.tsv")

defaults = Dict(
    "OCTOPUS_USE_GPU" => "1",
    "OCTOPUS_POISSON_SOLVER" => "PIC",
    "OCTOPUS_TURNS" => string(turns),
    "OCTOPUS_N_MACRO_ELE" => "2560000",
    "OCTOPUS_N_MACRO_PRO" => "1000000",
    "OCTOPUS_PIC_BATCH_MODE" => "wavefront",
    "OCTOPUS_PIC_GREEN_CACHE" => "slice_pair",
    "OCTOPUS_PIC_SLICE_PAIR_GREEN_MIN_RATIO" => "0.50",
    "OCTOPUS_PIC_SLICE_PAIR_GREEN_GROWTH" => "0.25",
    "OCTOPUS_CUDA_PIC_ASYNC" => "1",
    "OCTOPUS_CUDA_PIC_BATCH_FFT" => "1",
    "OCTOPUS_CUDA_PIC_WAVEFRONT_FFT" => "1",
    "OCTOPUS_CUDA_PIC_INDEXED_WAVEFRONT" => "1",
    "OCTOPUS_PIC_LUMINOSITY_EVERY" => luminosity_enabled ? "1" : "0",
    "OCTOPUS_DISABLE_LUMINOSITY_OUTPUT" => luminosity_file_enabled ? "0" : "1",
    "OCTOPUS_DISABLE_MOMENTS" => moments_enabled ? "0" : "1",
    "OCTOPUS_MOMENT_CAPACITY" => "100",
    "OCTOPUS_RECORD_TURN_TIMES" => "1",
    "OCTOPUS_TURN_TIMING_PATH" => timing_path,
)
for (key, value) in defaults
    haskey(ENV, key) || (ENV[key] = value)
end

include(joinpath(@__DIR__, "..", "examples", "strong_strong_tracking.jl"))

timings = turn_timings(task)
sample = timings[(end - sample_turns + 1):end]
sample_mean = sum(sample) / length(sample)
sorted = sort(sample)
mid = length(sorted) ÷ 2
sample_median = isodd(length(sorted)) ? sorted[mid + 1] : (sorted[mid] + sorted[mid + 1]) / 2
sample_std = sqrt(sum((x - sample_mean)^2 for x in sample) / (length(sample) - 1))

file_size(path) = isfile(path) ? filesize(path) : 0
luminosity_bytes = luminosity_file_enabled ? file_size(luminosity_path) : 0
electron_moment_bytes = moments_enabled ? file_size(electron_moment_path) : 0
proton_moment_bytes = moments_enabled ? file_size(proton_moment_path) : 0

println("diagnostic_mode = ", mode)
println("sample_turns = ", turns - sample_turns, ":", turns - 1)
println("sample_mean_seconds = ", sample_mean)
println("sample_median_seconds = ", sample_median)
println("sample_min_seconds = ", minimum(sample))
println("sample_std_seconds = ", sample_std)
println("luminosity_bytes = ", luminosity_bytes)
println("electron_moment_bytes = ", electron_moment_bytes)
println("proton_moment_bytes = ", proton_moment_bytes)

summary_path = joinpath(result_dir, "pic_diagnostics_$(mode)_summary.tsv")
open(summary_path, "w") do io
    println(io, "key\tvalue")
    for (key, value) in (
        "git_commit" => readchomp(`git rev-parse HEAD`),
        "mode" => mode,
        "turns" => turns,
        "sample_turns" => sample_turns,
        "sample_mean_seconds" => sample_mean,
        "sample_median_seconds" => sample_median,
        "sample_min_seconds" => minimum(sample),
        "sample_std_seconds" => sample_std,
        "moment_capacity" => ENV["OCTOPUS_MOMENT_CAPACITY"],
        "luminosity_bytes" => luminosity_bytes,
        "electron_moment_bytes" => electron_moment_bytes,
        "proton_moment_bytes" => proton_moment_bytes,
        "electron_rms" => join(stats_ele.rms, ','),
        "proton_rms" => join(stats_pro.rms, ','),
    )
        println(io, key, '\t', value)
    end
end
println("diagnostic_summary = ", summary_path)
