#=
Measure strong-strong moment and luminosity diagnostics without changing the
validated PIC solver configuration. The default target is 200 turns; turns
100-199 form the measured window so a moment capacity of 100 includes one
representative HDF5 flush.

Modes:
  baseline       no moments, no luminosity calculation, no artifact
  luminosity     luminosity calculation, no artifact
  luminosity_io  luminosity calculation and its artifact channel
  moments        two moment views in the artifact, no luminosity calculation
  both           moments plus luminosity calculation and channel

Run from the project root, for example:

  OCTOPUS_DIAGNOSTIC_BENCHMARK_MODE=baseline \
    julia --project=. validation/strong_strong_diagnostics_benchmark.jl

Set OCTOPUS_SOLVER=gaussian to exercise the soft-Gaussian source-moment path.
The per-kernel CUDA PIC launch families are a PIC-family property: the PIC and
Gaussian-PIC solvers report one `cuda_pic_<family>_threads` entry per family
and the summary records each; the soft-Gaussian solver has no
`backend_configurations` and its summary row says `not applicable` instead.
(Until 2026-10-20 the family loop ran for every CUDA policy and the Gaussian
mode errored at it AFTER the measured run; comprehensive audit 2026-10-18,
F-207.) The `turns` row and the printed sample window are the EFFECTIVE run
length, `OCTOPUS_TURNS` as the harness read it (a pre-set `OCTOPUS_TURNS`
wins over OCTOPUS_DIAGNOSTIC_BENCHMARK_TURNS), and `git_commit` is read from
this script's own tree, so the summary is provenance of the run that
happened wherever it was launched from.

The gate's CUDA arm runs this benchmark at a reduced size (the testset
"CUDA-requiring validation scripts run in the gate's CUDA arm" in
test/runtests.jl reads the line below; see validation/README.md):

GATE-CUDA-ARM: env OCTOPUS_N_MACRO_ELE=4000 OCTOPUS_N_MACRO_PRO=4000 OCTOPUS_DIAGNOSTIC_BENCHMARK_TURNS=12 OCTOPUS_DIAGNOSTIC_BENCHMARK_SAMPLE_TURNS=4 OCTOPUS_DIAGNOSTIC_BENCHMARK_MODE=both OCTOPUS_RESULT_DIR=@TMP@ ; verdict "diagnostic_summary = " ; outputs result/pic_diagnostics_both_turn_times.tsv result/pic_diagnostics_both_summary.tsv

Outputs (2026-08-05_b audit, U25-8 -- this header named none of them):

    result/pic_diagnostics_<mode>_turn_times.tsv   per-turn wall times
    result/pic_diagnostics_<mode>_summary.tsv      provenance and the sampled
                                                   mean/median/min/std

and, written by the tracking harness this script includes, in the modes that
enable it:

    test/result/<seed>/pic_hcc.h5        the run artifact (all modes except
                                         baseline and luminosity):
                                         /luminosity/ip in luminosity_io/both,
                                         /moments/{electron,proton} in
                                         moments/both
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
    "OCTOPUS_SOLVER" => "PIC",
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

# Guard the EFFECTIVE turn count, not this script's own variable.
#
# The check above compares `sample_turns` against `turns`, which comes from
# OCTOPUS_DIAGNOSTIC_BENCHMARK_TURNS -- but the loop just above only sets
# OCTOPUS_TURNS when it is not already present, so a pre-set OCTOPUS_TURNS wins
# and the two numbers are unrelated. With a smaller pre-set value the sample
# slice below runs off the end and the script dies with a BoundsError AFTER the
# entire measured workload has been paid for (2026-08-05_b audit, U25-5).
let effective = parse(Int, ENV["OCTOPUS_TURNS"])
    effective >= sample_turns || error(
        "OCTOPUS_TURNS=$(effective) is smaller than sample_turns=$(sample_turns): " *
        "the benchmark would track $(effective) turns and then fail sampling the " *
        "last $(sample_turns). Raise OCTOPUS_TURNS, lower " *
        "OCTOPUS_DIAGNOSTIC_BENCHMARK_SAMPLE_TURNS, or unset OCTOPUS_TURNS to use " *
        "OCTOPUS_DIAGNOSTIC_BENCHMARK_TURNS=$(turns).")
end

include(joinpath(@__DIR__, "..", "test", "examples", "strong_strong_tracking.jl"))
# Assert the harness's published interface BEFORE anything else reads it:
# these names were an undeclared dependency, and a rename in the harness
# surfaced as an UndefVarError at the end of a production-size GPU run
# (2026-08-05_b audit, U25-15).
assert_harness_exports((:input, :task, :artifact_path,
         :stats_ele, :stats_pro, :solver, :policy))

timings = turn_timings(task)
sample = timings[(end - sample_turns + 1):end]
sample_mean = sum(sample) / length(sample)
sorted = sort(sample)
mid = length(sorted) ÷ 2
sample_median = isodd(length(sorted)) ? sorted[mid + 1] : (sorted[mid] + sorted[mid + 1]) / 2
sample_std = sqrt(sum((x - sample_mean)^2 for x in sample) / (length(sample) - 1))

file_size(path) = isfile(path) ? filesize(path) : 0
artifact_bytes = (luminosity_file_enabled || moments_enabled) ?
                 file_size(artifact_path) : 0

# The EFFECTIVE run length: `turns` above is this script's own variable, and a
# pre-set OCTOPUS_TURNS wins over it (the guard above only prevents the
# BoundsError), so the summary used to name a configuration the run did not
# use (comprehensive audit 2026-10-18, F-207 / U40-5).
effective_turns = parse(Int, ENV["OCTOPUS_TURNS"])
length(timings) == effective_turns || error(
    "the harness recorded $(length(timings)) turn timings against OCTOPUS_TURNS=$(effective_turns)")
println("diagnostic_mode = ", mode)
println("sample_turns = ", effective_turns - sample_turns, ":", effective_turns - 1)
println("sample_mean_seconds = ", sample_mean)
println("sample_median_seconds = ", sample_median)
println("sample_min_seconds = ", minimum(sample))
println("sample_std_seconds = ", sample_std)
println("artifact_bytes = ", artifact_bytes)

summary_path = joinpath(result_dir, "pic_diagnostics_$(mode)_summary.tsv")
configuration_rows = Pair{String,Any}[
    # This script's tree, not the caller's cwd: launched from elsewhere the
    # bare `git rev-parse` either died after the measured run or recorded
    # another repository's commit (comprehensive audit 2026-10-18, U40-15).
    "git_commit" => readchomp(`git -C $(dirname(@__DIR__)) rev-parse HEAD`),
    "mode" => mode,
    "solver" => nameof(typeof(solver)),
    "turns" => effective_turns,
    "sample_turns" => sample_turns,
    "sample_mean_seconds" => sample_mean,
    "sample_median_seconds" => sample_median,
    "sample_min_seconds" => minimum(sample),
    "sample_std_seconds" => sample_std,
    "moment_capacity" => ENV["OCTOPUS_MOMENT_CAPACITY"],
    "artifact_bytes" => artifact_bytes,
    "electron_rms" => join(stats_ele.rms, ','),
    "proton_rms" => join(stats_pro.rms, ','),
]
if policy isa CUDAExecutionPolicy
    push!(configuration_rows, "cuda_fused_threads_requested" => policy.launch.threads)
    push!(configuration_rows, "cuda_fused_blocks_requested" => policy.launch.blocks)
    config_entries = configuration_report(solver; policy=policy, backend=CUDABackend)
    # Derive the family list and refuse to skip one (2026-08-05_b audit, U25-6).
    # This was a hand-copied tuple whose loop body did `isempty(matches) &&
    # continue`, which swallowed BOTH directions: a family added to the solver
    # never appeared, and a family that stopped being reported vanished without
    # a word. Either way the summary claimed complete provenance while missing a
    # launch parameter that shaped the timings it records.
    #
    # For the PIC-family solvers only: the launch families are fields of
    # `PICPoissonSolver` (reached by `pic` and `gaussian_pic`), and the
    # soft-Gaussian solver's `configuration_report` carries none of the seven
    # `cuda_pic_*` entries by design. The U25-6 derivation assumed a PIC solver
    # and so made the documented OCTOPUS_SOLVER=gaussian mode error HERE, after
    # the whole measured run (comprehensive audit 2026-10-18, F-207). The
    # summary now says so instead of claiming or crashing.
    if solver isa Union{PICPoissonSolver,GaussianPICPoissonSolver}
        for family in Octopus._CUDA_PIC_LAUNCH_FAMILIES
            option = Symbol(:cuda_pic_, family, :_threads)
            matches = filter(item -> item.name === option, config_entries)
            isempty(matches) && error(
                "CUDA PIC launch family $(family) is in Octopus._CUDA_PIC_LAUNCH_FAMILIES " *
                "but configuration_report did not report $(option): the benchmark " *
                "summary would silently omit it.")
            entry = only(matches)
            push!(configuration_rows, string(option, "_requested") => entry.requested)
            push!(configuration_rows, string(option, "_resolved") => entry.resolved)
        end
    else
        # Loud, not silent: a reader of the summary must see that the launch
        # families were not applicable rather than wonder why they are missing.
        any(item -> startswith(string(item.name), "cuda_pic_"), config_entries) && error(
            "$(nameof(typeof(solver))) reported cuda_pic_* launch entries: the family " *
            "loop above assumed it has none; teach this script the solver's launch surface.")
        push!(configuration_rows, "cuda_pic_launch_families" =>
            "not applicable ($(nameof(typeof(solver))) has no backend_configurations)")
        println("cuda_pic_launch_families = not applicable (", nameof(typeof(solver)),
                " has no backend_configurations)")
    end
end
open(summary_path, "w") do io
    println(io, "key\tvalue")
    for (key, value) in configuration_rows
        println(io, key, '\t', value)
    end
end
println("diagnostic_summary = ", summary_path)
