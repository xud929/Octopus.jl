#=
Benchmark the crab cavity noise example across the three execution policies --
CPU threads, MultiProcessExecutionPolicy (MPI ranks x threads) and CUDA -- with
a per-turn instrument and a digest of the output.

Purpose. The crab cavity noise example (test/examples/crab_cavity_noise.jl)
is a weak-strong TrackingTask with two TurnModulated crab cavities; its rules
are realised on the host once per turn and the counter RNG keys on particle
slot and turn, so the SAME run divided across MPI ranks must reproduce the
threads-only run bit for bit, and the CUDA run must agree to rounding. This
driver runs the harness once per arm as a SUBPROCESS, times every turn with
the harness's own instrument, and compares the outputs, so "how fast is each
backend" and "do the backends agree" are answered by one table.

Fixed case (the production point; the harness owns the physics literals and
this driver passes only switches, so it tracks the harness rather than
copying it): rule white at scale 1 (phase rms 10 urad, relative strength rms
1e-4 per active harmonic), OCTOPUS_RADIATION=0 so the crab noise is the only
stochastic drive (a formality: the example's radiation element ships with
`damping_turns = 1e100`, an excitation scale of 1.4e-50 that leaves every
moment bitwise unchanged, so the toggle removes an inert element unless the
damping turns are set; 2026-10-16 neighbour audit), seed 123456789, the
example's beams and optics, moments
every turn; sizes N in {1e5, 1e6} macroparticles and 2000 turns by default.
Since 2026-10-15 every arm also records the realised turn-modulation
series by the harness default (OCTOPUS_RECORD_TURN_MODULATION, which this
driver's environment stripping leaves at its default of on): 8 B per
active slot per turn, measured at +11 us/turn for eight slots at the
artifact's default capacity (docs/history/turn_modulation_record_2026_10_15.md),
below this driver's resolution; the digests are of the moments and the
luminosity, which recording leaves bitwise unchanged.
`harness=weak_strong` runs test/examples/weak_strong_tracking.jl instead: the
same case WITHOUT the noise and with radiation excitation on, which carried
the MPI and timing toggles first and is the driver's dry-run target.

What is measured, per arm:
  * steady ms/turn: median, 10th and 90th percentile of the per-turn wall
    time over turns skip+1..T (skip = 20 by default) read from the timing
    file OCTOPUS_RECORD_TURN_TIMES=1 / OCTOPUS_TURN_TIMING_PATH makes the
    harness write (`turn\tseconds`, one row per turn; the crab harness adds
    a `max_over_ranks_seconds` column). Per-turn numbers come from the
    per-turn instrument and NEVER from differenced wall times: the
    2026-09-06 production benchmark differenced whole runs and was retracted
    (docs/history/weak_strong_rerun_instrumented_2026_09_07.md). Under MPI
    the `seconds` column is rank 0's own clock; the turn's wall time is the
    slowest rank's, which the driver reports beside it ("max-rank") from the
    file's column when there is one, else by folding the per-rank
    `turn_timings_seconds` lines the ranks print (best effort: those lines
    tear under a launcher). For the crab harness the driver checks its
    max-rank median against the harness's own `steady_ms_per_turn` (the same
    statistic) and rejects the arm if the two instruments disagree.
  * the whole-process wall time (load, JIT, the run, the artifact flush),
    the 1-minute load average at launch and at exit (a shared node), and for
    the CUDA arm `nvidia-smi` GPU utilisation before and after (a shared GPU).
  * the OUTPUT, read back from the run artifact with HDF5.jl, not from the
    harness's printout: the rms emittances at the last recorded moment row
    (eps = sqrt(<x^2><px^2> - <x px>^2) from the central second moments, the
    harness's own estimator; for the crab harness the driver checks its
    reading against the CRAB-NOISE line bit for bit), the luminosity mean,
    and a digest: SHA-256 over the raw Float64 bytes of
    /moments/<name>/data, /luminosity/strong_beam_1/turns and
    /luminosity/strong_beam_1/values, in that order, so output identity is
    one string comparison, plus the same digest for each block alone
    (`digest_lum`, `digest_moments`).
Then a comparison table per (N, turns): ms/turn, speed-up against the
threads baseline (`baseline=`, default threads:16), wall, digests, and the
identity verdict against the baseline: "bitwise identical" when the whole
digests match; otherwise the maximum relative difference of eps_x_last,
eps_y_last and lumi_mean, whether the luminosity series and the moments
block are each bitwise, and, when both artifacts are still readable, the
difference over the whole moments matrix (per column, scaled to the
column's largest magnitude, the worst column named) and over the
luminosity series. What to expect, from docs/design/multi_process_policy.md
("Three execution modes"): threads vs MPI TRACKING is bitwise, which the
luminosity series (a per-turn sum the collide folds in a fixed order)
shows; the MOMENTS under MPI are P partial sums folded in rank order and
carry the accumulation difference between one serial sum and P of them
(1.7e-14 at two ranks, 8.7e-14 at four, measured there), so their digest
moves while the luminosity digest holds -- folding them on the fixed chunk
grid instead was implemented and refused (docs/experiences.md, "The
attractive uniformity is sometimes the wrong one"); CUDA vs CPU agrees to
rounding, ~1e-15 relative on the emittances and the luminosity.

Load mode. `load=package` (the default) starts every child as
`julia -e 'using Octopus; include(<harness>)'`, so all three arms load the
precompiled package: the harness's own default is an `include` of
src/Octopus.jl, which compiles Octopus from source in every non-MPI run
(~170 s on the 128-core node) while its MPI branch must load the package,
and that made the threads and CUDA arms' whole-process wall incomparable
with the MPI arms' (176 s against 27 s around a 2 s run, 2026-10-14).
`load=include` runs `julia <harness>` as the harness documents. The
per-turn numbers do not depend on the choice, the wall does, and the TSV
records it (`load_mode`).

Outputs, under `out=` (default <root>/result/crab_noise/MPI_B, git-ignored):
  benchmark_<tag>.tsv   one row per arm, appended as arms finish; the
                        driver is RESUMABLE and skips an arm whose row
                        (harness, arm, n_macro, turns) is already there
  benchmark_<tag>.log   this driver's printout, appended
  <tag>/<arm>_N<N>_T<T>.log         the child's stdout+stderr
  <tag>/<arm>_N<N>_T<T>_turn_times.tsv   the per-turn timing file
  <tag>/<arm>_N<N>_T<T>/<seed>/<case>.h5 the child's artifact (its
                        OCTOPUS_RESULT_DIR; one directory per arm so arms
                        never share a path)

Run from the Octopus project root (script mode; arguments are key=value):

    julia --startup-file=no --project=. profiling/crab_cavity_noise_backends.jl \
        n_macro=100000,1000000 turns=2000 \
        arms=threads:16,threads:32,mpi:4x8,mpi:8x8,mpi:16x8,cuda tag=prod

    harness=crab|weak_strong  (crab)      n_macro=<list>  (100000,1000000)
    turns=<T>                 (2000)      skip=<n>        (20)
    arms=<list>  threads:<T> | mpi:<R>x<T> | cuda
                 (threads:16,threads:32,mpi:4x8,mpi:8x8,mpi:16x8,cuda)
    baseline=<arm>            (threads:16) tag=<name>     (<harness>_<date>)
    out=<dir>                 (<root>/result/crab_noise/MPI_B)
    seed=<int>                (123456789; the crab harness reads it, the
                               weak-strong harness has it fixed)
    timeout=<s>               (7200 per arm; the child is killed past it)
    cuda_threads=<n>          (1; julia --threads of the CUDA arm)
    load=package|include      (package; how the child loads Octopus, below)
    moment_step=<n>           (1; crab only: OCTOPUS_MOMENT_STEP, turns between
                               moment rows -- a large step takes the every-turn
                               observer and artifact row out of the per-turn
                               cost and so separates it from the tracking cost;
                               recorded per row, part of the resume key, and
                               asserted through the artifact's moment row count)

Arms run ONE AT A TIME in the order given, sizes ascending; on a shared
128-core node never run two drivers at once. The child inherits this
process's environment with every OCTOPUS_* variable REMOVED first, so a
child reads exactly the switches this driver sets and nothing from the
shell. The MPI launcher is `MPI.mpiexec()` of the MPI.jl that resolves in
this project's load path (the MPICH_jll artifact binary, with that Cmd's
PATH/LD_LIBRARY_PATH), never a system `mpiexec` from PATH: the children
load the same libmpi. The MPI arms need Octopus and MPI to resolve as
PACKAGES in the child (`using Octopus`): --project=<root> plus MPI in the
stacked default environment is the configuration this was developed on.
JULIA_THREAD_SLEEP_THRESHOLD is left as inherited (the sibling benchmark
sets it to 0 above ~32 threads; no arm here exceeds 32 threads per process).
A failed arm (non-zero exit, timeout, missing artifact or timing file) is
reported with the tail of its log and writes NO row, so a resumed run
retries it.
=#
using Printf
using Statistics
using SHA
using HDF5
using Dates

const ROOT = normpath(joinpath(@__DIR__, ".."))
const JULIA = joinpath(Sys.BINDIR, Base.julia_exename())

# ---------------------------------------------------------------- arguments
const KNOWN_KEYS = ("harness", "n_macro", "turns", "skip", "arms", "baseline",
                    "tag", "out", "seed", "timeout", "cuda_threads", "load", "moment_step")
function parse_args(args)
    kv = Dict{String,String}()
    for a in args
        m = match(r"^([a-z_]+)=(.*)$", a)
        m === nothing && error("argument $(repr(a)) is not key=value; keys: $(join(KNOWN_KEYS, ", "))")
        k, v = m.captures
        k in KNOWN_KEYS || error("unknown key $(repr(k)); keys: $(join(KNOWN_KEYS, ", "))")
        haskey(kv, k) && error("key $(repr(k)) given twice")
        kv[k] = v
    end
    kv
end
const ARGMAP = parse_args(ARGS)
argstr(k, d) = get(ARGMAP, k, d)
argint(k, d) = parse(Int, argstr(k, string(d)))

const HARNESS = let h = argstr("harness", "crab")
    h in ("crab", "weak_strong") || error("harness=$(h) must be crab or weak_strong")
    h
end
const HARNESS_PATH = joinpath(ROOT, "test", "examples",
    HARNESS == "crab" ? "crab_cavity_noise.jl" : "weak_strong_tracking.jl")
isfile(HARNESS_PATH) || error("harness not found: $(HARNESS_PATH)")
const N_LIST = [parse(Int, strip(s)) for s in split(argstr("n_macro", "100000,1000000"), ",")]
const TURNS = argint("turns", 2000)
const SKIP = argint("skip", 20)
TURNS > SKIP || error("turns=$(TURNS) must exceed skip=$(SKIP) for a steady window")
const SEED = argint("seed", 123456789)
const TIMEOUT_S = argint("timeout", 7200)
const CUDA_THREADS = argint("cuda_threads", 1)
const LOAD = let l = argstr("load", "package")
    l in ("package", "include") || error("load=$(l) must be package or include")
    l
end
# Turns between moment rows (the crab harness's OCTOPUS_MOMENT_STEP; row 1 is
# turn 0). 1 records every turn; a larger step takes the every-turn observer
# and artifact row out of the per-turn cost, which separates it from the
# tracking cost. The weak-strong harness has no such switch and records
# every turn, so a non-default value is refused there rather than dropped.
const MOMENT_STEP = argint("moment_step", 1)
MOMENT_STEP >= 1 || error("moment_step=$(MOMENT_STEP) must be at least 1")
HARNESS == "weak_strong" && MOMENT_STEP != 1 && error(
    "moment_step=$(MOMENT_STEP): only the crab harness reads OCTOPUS_MOMENT_STEP; " *
    "the weak-strong harness records every turn")
const EXPECTED_MOMENT_ROWS = length(0:MOMENT_STEP:TURNS-1)
const TAG = argstr("tag", HARNESS * "_" * Dates.format(now(), "yyyymmdd"))
occursin(r"^[A-Za-z0-9_.-]+$", TAG) || error("tag=$(repr(TAG)) must be [A-Za-z0-9_.-]+")
const OUT = abspath(argstr("out", joinpath(ROOT, "result", "crab_noise", "MPI_B")))
const BASELINE = argstr("baseline", "threads:16")

struct Arm
    label::String      # as given: threads:16, mpi:4x8, cuda
    kind::Symbol       # :threads, :mpi, :cuda
    ranks::Int
    threads::Int
end
function parse_arm(s::AbstractString)
    s = strip(s)
    if (m = match(r"^threads:(\d+)$", s)) !== nothing
        t = parse(Int, m.captures[1]); t >= 1 || error("arm $(s): threads must be >= 1")
        return Arm(s, :threads, 1, t)
    elseif (m = match(r"^mpi:(\d+)x(\d+)$", s)) !== nothing
        r, t = parse.(Int, m.captures)
        (r >= 1 && t >= 1) || error("arm $(s): ranks and threads must be >= 1")
        return Arm(s, :mpi, r, t)
    elseif s == "cuda"
        return Arm(s, :cuda, 1, CUDA_THREADS)
    end
    error("arm $(repr(s)) is not threads:<T>, mpi:<R>x<T> or cuda")
end
const ARMS = [parse_arm(s) for s in split(argstr("arms", "threads:16,threads:32,mpi:4x8,mpi:8x8,mpi:16x8,cuda"), ",")]
length(unique(a.label for a in ARMS)) == length(ARMS) || error("arms list repeats an arm")
armkey(a::Arm) = replace(a.label, ":" => "")          # threads16, mpi4x8, cuda
runkey(a::Arm, n) = "$(armkey(a))_N$(n)_T$(TURNS)"

# ------------------------------------------------------------------- output
mkpath(OUT)
const TSV_PATH = joinpath(OUT, "benchmark_$(TAG).tsv")
const LOG_PATH = joinpath(OUT, "benchmark_$(TAG).log")
const LOGIO = open(LOG_PATH, "a")
function say(args...)
    s = string(args...)
    println(stdout, s); flush(stdout)
    println(LOGIO, s); flush(LOGIO)
end

const COLUMNS = ["tag", "harness", "arm", "n_macro", "turns", "started_at", "wall_s",
    "loadavg_launch", "loadavg_end", "gpu_util_before", "gpu_util_after",
    "steady_ms_median", "steady_ms_p10", "steady_ms_p90", "steady_ms_median_maxrank",
    "turn1_s", "sum_turns_s", "harness_steady_ms_per_turn",
    "moments_rows", "lum_rows", "eps_x_last", "eps_y_last", "lumi_mean", "digest",
    "artifact", "timing_path", "log", "julia_threads", "ranks", "commit", "load_mode",
    "digest_lum", "digest_moments", "moment_step"]

function read_rows(path)
    rows = Dict{String,String}[]
    isfile(path) || return rows
    lines = readlines(path)
    isempty(lines) && return rows
    header = split(lines[1], '\t')
    header == COLUMNS || error("$(path) has a header this driver does not write; move it aside or use another tag")
    for l in lines[2:end]
        isempty(strip(l)) && continue
        f = split(l, '\t')
        length(f) == length(COLUMNS) || error("$(path): a row has $(length(f)) fields, expected $(length(COLUMNS))")
        push!(rows, Dict(zip(COLUMNS, String.(f))))
    end
    rows
end
function append_row!(path, row::Dict{String,String})
    fresh = !isfile(path) || filesize(path) == 0
    open(path, "a") do io
        fresh && println(io, join(COLUMNS, '\t'))
        vals = [get(row, c, "n/a") for c in COLUMNS]
        any(v -> occursin('\t', v) || occursin('\n', v), vals) && error("a TSV field contains a tab or newline")
        println(io, join(vals, '\t'))
    end
end
rowkey(r) = (r["harness"], r["arm"], r["n_macro"], r["turns"], r["moment_step"])

# -------------------------------------------------------------- host probes
loadavg1() = try; split(read("/proc/loadavg", String))[1]; catch; "n/a"; end
function gpu_util()
    try
        strip(read(`nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader`, String))
    catch
        "n/a"
    end
end
const COMMIT = try
    strip(read(`git -C $(ROOT) rev-parse --short HEAD`, String))
catch
    "unknown"
end

# ---------------------------------------------------------------- launcher
# Loaded at TOP LEVEL, and only when an MPI arm is requested: a `using`
# issued from inside a function leaves the new binding in a world age the
# calling function cannot see (Julia 1.12), so the launcher is resolved here.
const NEED_MPI = any(a -> a.kind === :mpi, ARMS)
if NEED_MPI
    using MPI
end
const LAUNCHER = NEED_MPI ? MPI.mpiexec() : nothing
const MPI_IMPL = NEED_MPI ? join(string.(MPI.identify_implementation()), " ") : "n/a"
function launcher()
    LAUNCHER === nothing && error("an MPI arm needs the launcher, but no MPI arm was requested at load")
    LAUNCHER
end

# The child's environment: this process's, with every OCTOPUS_* removed, the
# launcher Cmd's own settings (artifact PATH/LD_LIBRARY_PATH) layered over it,
# then this arm's switches.
function child_env(extra::Vector{Pair{String,String}}, base_cmd::Union{Nothing,Cmd})
    env = Dict{String,String}(k => v for (k, v) in ENV if !startswith(k, "OCTOPUS_"))
    if base_cmd !== nothing && base_cmd.env !== nothing
        for kv in base_cmd.env
            i = findfirst('=', kv)
            i === nothing && continue
            env[kv[1:i-1]] = kv[i+1:end]
        end
    end
    for (k, v) in extra
        env[k] = v
    end
    [k * "=" * v for (k, v) in env]
end

# --------------------------------------------------------------- the child
function arm_switches(arm::Arm, n::Int, result_dir::String, timing_path::String, case::String)
    sw = Pair{String,String}[
        "OCTOPUS_TURNS" => string(TURNS),
        "OCTOPUS_N_MACRO" => string(n),
        "OCTOPUS_RESULT_DIR" => result_dir,
        "OCTOPUS_RECORD_TURN_TIMES" => "1",
        "OCTOPUS_TURN_TIMING_PATH" => timing_path,
    ]
    if HARNESS == "crab"
        append!(sw, ["OCTOPUS_NOISE_RULE" => "white", "OCTOPUS_NOISE_SCALE" => "1",
                     "OCTOPUS_RADIATION" => "0", "OCTOPUS_SEED" => string(SEED),
                     "OCTOPUS_CASE_NAME" => case, "OCTOPUS_MOMENT_STEP" => string(MOMENT_STEP)])
    end
    if arm.kind === :threads
        push!(sw, "OCTOPUS_CPU_THREADS" => string(arm.threads))
    elseif arm.kind === :mpi
        append!(sw, ["OCTOPUS_USE_MPI" => "1", "OCTOPUS_RANKS" => string(arm.ranks),
                     "OCTOPUS_CPU_THREADS" => string(arm.threads)])
    else
        push!(sw, "OCTOPUS_USE_GPU" => "1")
    end
    sw
end

function child_command(arm::Arm, switches)
    jl = if LOAD == "package"
        # `using Octopus` first: the harness then skips its `include` of
        # src/Octopus.jl (its header sanctions exactly this) and every arm
        # loads the precompiled package the MPI branch needs anyway.
        code = "using Octopus; include($(repr(HARNESS_PATH)))"
        `$(JULIA) --startup-file=no --project=$(ROOT) --threads=$(arm.threads) -e $(code)`
    else
        `$(JULIA) --startup-file=no --project=$(ROOT) --threads=$(arm.threads) $(HARNESS_PATH)`
    end
    if arm.kind === :mpi
        l = launcher()
        cmd = `$(l) -n $(arm.ranks) $(jl)`
        return setenv(cmd, child_env(switches, l))
    end
    setenv(jl, child_env(switches, nothing))
end

# Run the child with its output in a log file; returns (ok, wall_s, timed_out).
function run_child(cmd::Cmd, logpath::String)
    t0 = time()
    proc = open(logpath, "w") do io
        p = run(pipeline(cmd; stdout = io, stderr = io); wait = false)
        timed_out = Ref(false)
        watchdog = Timer(TIMEOUT_S) do _
            if process_running(p)
                timed_out[] = true
                kill(p)
            end
        end
        wait(p)
        close(watchdog)
        (p, timed_out[])
    end
    p, timed_out = proc
    (success(p), time() - t0, timed_out)
end

# ----------------------------------------------------------------- parsing
# The timing file is `turn\tseconds` (the weak-strong harness) or
# `turn\tseconds\tmax_over_ranks_seconds` (the crab harness; the third column
# is the slowest rank's clock, the turn's wall time, equal to `seconds` at one
# rank). Columns are read by header name. Returns (seconds, max_over_ranks or
# nothing).
function parse_timing_file(path)
    lines = readlines(path)
    isempty(lines) && error("$(path): empty")
    header = String.(split(strip(lines[1]), '\t'))
    ("turn" in header && "seconds" in header) || error("$(path): header $(repr(lines[1])) lacks turn/seconds")
    cols = Dict(h => Float64[] for h in header)
    for l in lines[2:end]
        isempty(strip(l)) && continue
        f = split(l, '\t')
        length(f) == length(header) || error("$(path): a row has $(length(f)) fields, the header $(length(header))")
        for (h, v) in zip(header, f)
            push!(cols[h], parse(Float64, v))
        end
    end
    cols["turn"] == 1:length(cols["turn"]) || error("$(path): turn index is not 1..T")
    (cols["seconds"], get(cols, "max_over_ranks_seconds", nothing))
end
function steady_stats(secs::Vector{Float64})
    length(secs) > SKIP || error("timing series has $(length(secs)) turns, skip=$(SKIP) leaves nothing")
    w = secs[SKIP+1:end]
    # The median in seconds, then x1000: the crab harness's own arithmetic for
    # its steady_ms_per_turn, so the two agree bit for bit at skip = 20.
    (median = 1000 * median(w), p10 = 1000 * quantile(w, 0.10), p90 = 1000 * quantile(w, 0.90))
end

# Every rank prints `turn_timings_seconds[ (rank r shard of P; ...)] = [..]`;
# the per-turn maximum over ranks is the turn's wall time. Returns nothing
# when the log has fewer than two such lines.
function maxrank_series(text::String)
    series = Vector{Float64}[]
    for m in eachmatch(r"turn_timings_seconds[^=\n]* = \[([^\]]*)\]", text)
        vals = Float64[]
        for s in split(m.captures[1], ",")
            v = tryparse(Float64, strip(s))
            # The ranks' stdout lines interleave under the launcher (one
            # rank's series torn by another's at 4 ranks, 2026-10-14), so
            # this series is best effort: a torn log yields "n/a", never a
            # number, and never an abort -- the rank-0 timing FILE is the
            # measurement.
            v === nothing && return nothing
            push!(vals, v)
        end
        push!(series, vals)
    end
    (length(series) >= 2 && all(length(s) == TURNS for s in series)) || return nothing
    [maximum(s[i] for s in series) for i in 1:TURNS]
end

grab(text, re) = (m = match(re, text); m === nothing ? nothing : String(m.captures[1]))
function crab_line(text)
    m = match(r"^CRAB-NOISE (.*)$"m, text)
    m === nothing && return nothing
    Dict{String,String}(String(x.captures[1]) => String(x.captures[2])
                        for x in eachmatch(r"(\S+?)=(\S+)", m.captures[1]))
end

# ---------------------------------------------------------- the artifact
struct Output
    moments::Matrix{Float64}
    names::Vector{String}
    lum_turns::Vector{Float64}
    lum_values::Vector{Float64}
end
function read_output(path)
    h5open(path, "r") do f
        mg = f["moments"]
        names = keys(mg)
        length(names) == 1 || error("$(path): expected one /moments group, found $(names)")
        g = mg[names[1]]
        Output(read(g["data"]), read(g["column_names"]),
               Float64.(read(f["luminosity/strong_beam_1/turns"])),
               Float64.(read(f["luminosity/strong_beam_1/values"])))
    end
end
rawbytes(a) = collect(reinterpret(UInt8, vec(a)))
function sha_of(arrays...)
    ctx = SHA256_CTX()
    for a in arrays
        SHA.update!(ctx, rawbytes(a))
    end
    bytes2hex(SHA.digest!(ctx))
end
# Three digests: the whole output, and its two blocks apart, because they
# answer different questions. The luminosity series is a per-turn sum the
# collide folds in a fixed order, so it is the proxy for TRACKING identity;
# the moments are P partial sums folded in rank order under MPI and so carry
# the documented accumulation difference between one serial sum and P of
# them (docs/design/multi_process_policy.md, "Three execution modes":
# tracking bitwise, scalar diagnostics 1.7e-14 at two ranks, 8.7e-14 at
# four) -- a moments digest that moves while the luminosity digest holds is
# that property, not a tracking difference.
digest(o::Output) = sha_of(o.moments, o.lum_turns, o.lum_values)
digest_lum(o::Output) = sha_of(o.lum_turns, o.lum_values)
digest_moments(o::Output) = sha_of(o.moments)
col(o::Output, name) = (i = findfirst(==(name), o.names); i === nothing && error("moments lack column $(name)"); view(o.moments, :, i))
eps_series(o::Output) = (sqrt.(col(o, "m200000") .* col(o, "m020000") .- col(o, "m110000") .^ 2),
                         sqrt.(col(o, "m002000") .* col(o, "m000200") .- col(o, "m001100") .^ 2))
lumi_mean(o::Output) = sum(o.lum_values) / length(o.lum_values)

reldiff(a, b) = a == b ? 0.0 : abs(a - b) / max(abs(a), abs(b))
function max_reldiff(a::AbstractArray, b::AbstractArray)
    size(a) == size(b) || return NaN
    m = 0.0
    for (x, y) in zip(a, b)
        m = max(m, reldiff(x, y))
    end
    m
end
# Per column, the largest |a - b| over the rows divided by the column's
# largest magnitude in either run: a difference relative to the COLUMN'S
# scale, because a first moment that sits near zero (a centroid of 1e-13 on
# a beam of 1e-4) makes an element-wise relative difference meaningless.
# Returns the worst column's value and name.
function moments_diff(a::Output, b::Output)
    size(a.moments) == size(b.moments) || return (NaN, "shape $(size(a.moments)) vs $(size(b.moments))")
    worst, name = 0.0, "none"
    for j in axes(a.moments, 2)
        ca = view(a.moments, :, j); cb = view(b.moments, :, j)
        scale = max(maximum(abs, ca), maximum(abs, cb))
        scale == 0 && continue
        d = maximum(abs(x - y) for (x, y) in zip(ca, cb)) / scale
        d > worst && ((worst, name) = (d, a.names[j]))
    end
    (worst, name)
end

# ------------------------------------------------------------------ one arm
function run_arm!(rows, arm::Arm, n::Int)
    key = runkey(arm, n)
    armdir = joinpath(OUT, TAG)
    mkpath(armdir)
    result_dir = joinpath(armdir, key)
    timing_path = joinpath(armdir, key * "_turn_times.tsv")
    logpath = joinpath(armdir, key * ".log")
    case = HARNESS == "crab" ? key : "weak_strong"
    expected_artifact = joinpath(result_dir, string(SEED), case * ".h5")
    for p in (timing_path, expected_artifact)
        isfile(p) && rm(p)      # a stale file must not pass for this run's
    end
    switches = arm_switches(arm, n, result_dir, timing_path, case)
    cmd = child_command(arm, switches)

    say("")
    say("=== arm ", arm.label, "  N = ", n, "  turns = ", TURNS, "  harness = ", HARNESS)
    say("  switches: ", join(["$(k)=$(v)" for (k, v) in switches], " "))
    say("  command : ", join(cmd.exec, " "))
    started = Dates.format(now(), "yyyy-mm-ddTHH:MM:SS")
    la0 = loadavg1()
    gpu0 = arm.kind === :cuda ? gpu_util() : "n/a"
    say("  launch  : ", started, "  loadavg1 = ", la0, arm.kind === :cuda ? "  gpu(util,mem) before = $(gpu0)" : "")
    ok, wall, timed_out = run_child(cmd, logpath)
    la1 = loadavg1()
    gpu1 = arm.kind === :cuda ? gpu_util() : "n/a"
    text = read(logpath, String)
    say(@sprintf("  exit    : %s  wall = %.1f s  loadavg1 = %s%s", ok ? "ok" : (timed_out ? "TIMEOUT (killed)" : "FAILED"),
                 wall, la1, arm.kind === :cuda ? "  gpu(util,mem) after = $(gpu1)" : ""))
    if !ok
        say("  --- tail of ", logpath)
        for l in last(split(text, '\n'), 25); say("  | ", l); end
        say("  no row written for ", arm.label, " at N = ", n, " (rerun resumes it)")
        return false
    end

    # Assert what the run recorded, not what was passed.
    problems = String[]
    artifact = something(grab(text, r"^artifact = (\S+)$"m), "")
    isempty(artifact) && push!(problems, "no `artifact = ` line in the child's output")
    !isempty(artifact) && artifact != expected_artifact &&
        push!(problems, "artifact path $(artifact) differs from the expected $(expected_artifact)")
    t_rec = grab(text, r"^turns = (\d+)$"m); n_rec = grab(text, r"^n_macro = (\d+)$"m)
    t_rec == string(TURNS) || push!(problems, "child recorded turns = $(t_rec), asked $(TURNS)")
    n_rec == string(n) || push!(problems, "child recorded n_macro = $(n_rec), asked $(n)")
    if arm.kind === :mpi
        # The ranks' lines tear under the launcher ("mpi_rank = mpi_rank = 1
        # of 4" at 4 ranks, 2026-10-14), so they are evidence of the SIZE the
        # ranks saw, not a census of the ranks; the census is the exit status,
        # since the policy refuses a communicator whose size differs from
        # OCTOPUS_RANKS and the harness passes OCTOPUS_RANKS straight through.
        sizes_seen = Set(String(m.captures[2]) for m in eachmatch(r"mpi_rank = (\d+) of (\d+)", text))
        (!isempty(sizes_seen) && sizes_seen == Set([string(arm.ranks)])) ||
            push!(problems, "mpi_rank lines report communicator sizes $(collect(sizes_seen)); asked $(arm.ranks)")
    end
    # Not end-anchored: the crab harness follows the path with a parenthesised
    # description of the columns.
    tp_rec = grab(text, r"^turn_timing_path = (\S+)"m)
    tp_rec == timing_path || push!(problems, "turn_timing_path = $(tp_rec), asked $(timing_path)")
    isfile(timing_path) || push!(problems, "timing file missing: $(timing_path)")
    isfile(artifact) || push!(problems, "artifact missing: $(artifact)")
    cn = HARNESS == "crab" ? crab_line(text) : nothing
    if HARNESS == "crab"
        cn === nothing && push!(problems, "no CRAB-NOISE line")
        if cn !== nothing
            # `ranks` and `threads` are what the POLICY resolved (the
            # communicator receipt and the logical-worker count), not an
            # echo of the switches; `threads` is NA on CUDA.
            for (k, v) in ("rule" => "white", "scale" => "1.0", "radiation" => "0",
                           "turns" => string(TURNS), "n_macro" => string(n), "seed" => string(SEED),
                           "ranks" => string(arm.ranks),
                           "threads" => (arm.kind === :cuda ? "NA" : string(arm.threads)))
                get(cn, k, "") == v || push!(problems, "CRAB-NOISE $(k)=$(get(cn, k, "<absent>")), asked $(v)")
            end
        end
    end
    if !isempty(problems)
        say("  REJECTED: the run did not record the configuration this arm asked for:")
        for p in problems; say("    - ", p); end
        say("  no row written for ", arm.label, " at N = ", n)
        return false
    end

    secs, maxsecs = parse_timing_file(timing_path)
    length(secs) == TURNS || (say("  REJECTED: timing file has $(length(secs)) turns, expected $(TURNS)"); return false)
    st = steady_stats(secs)
    # The turn's wall time under MPI: the file's own column when the harness
    # writes one, else the best-effort fold of the ranks' printed series.
    mr = maxsecs !== nothing ? maxsecs : (arm.kind === :mpi ? maxrank_series(text) : nothing)
    mr_median = mr === nothing ? "n/a" : (length(mr) == TURNS ? @sprintf("%.4f", steady_stats(mr).median) : "n/a")
    if cn !== nothing && SKIP == 20 && mr !== nothing && get(cn, "steady_ms_per_turn", "NA") != "NA"
        # The harness's steady_ms_per_turn is the same statistic over the same
        # column; the two instruments must agree, or one of them misread.
        hs = parse(Float64, cn["steady_ms_per_turn"]); ds = steady_stats(mr).median
        reldiff(hs, ds) <= 1e-9 ||
            (say("  REJECTED: CRAB-NOISE steady_ms_per_turn = $(hs) but the driver's median over the same column = $(ds)"); return false)
    end
    out = read_output(artifact)
    # The moment row count is the one trace OCTOPUS_MOMENT_STEP leaves in the
    # output (the summary line does not echo it): rows at turns 0, step, ...
    size(out.moments, 1) == EXPECTED_MOMENT_ROWS ||
        (say("  REJECTED: artifact has $(size(out.moments, 1)) moment rows, moment_step=$(MOMENT_STEP) over $(TURNS) turns gives $(EXPECTED_MOMENT_ROWS)"); return false)
    ex, ey = eps_series(out)
    lm = lumi_mean(out)
    dg = digest(out)
    if cn !== nothing
        # The harness computed the same estimator from the same file; a
        # mismatch means the driver read a different artifact or column.
        for (k, v) in ("eps_x_last" => ex[end], "eps_y_last" => ey[end], "lumi_mean" => lm)
            parse(Float64, cn[k]) == v || (say("  REJECTED: driver's $(k) = $(repr(v)) but CRAB-NOISE says $(cn[k])"); return false)
        end
    end
    say(@sprintf("  steady  : median %.4f ms/turn  p10 %.4f  p90 %.4f  (turns %d..%d; rank-0 clock%s)",
                 st.median, st.p10, st.p90, SKIP + 1, TURNS,
                 mr_median == "n/a" ? "" : "; max over ranks median $(mr_median) ms"))
    say(@sprintf("  turn 1  : %.3f s (JIT)   sum of turns %.2f s of %.1f s wall", secs[1], sum(secs), wall))
    say("  output  : eps_x_last = ", ex[end], "  eps_y_last = ", ey[end], "  lumi_mean = ", lm)
    say("  digest  : ", dg, "  (moments ", size(out.moments, 1), " rows x ", size(out.moments, 2),
        " cols; luminosity ", length(out.lum_values), " rows)")
    row = Dict{String,String}(
        "tag" => TAG, "harness" => HARNESS, "arm" => arm.label, "n_macro" => string(n), "turns" => string(TURNS),
        "started_at" => started, "wall_s" => @sprintf("%.2f", wall),
        "loadavg_launch" => la0, "loadavg_end" => la1, "gpu_util_before" => gpu0, "gpu_util_after" => gpu1,
        "steady_ms_median" => @sprintf("%.4f", st.median), "steady_ms_p10" => @sprintf("%.4f", st.p10),
        "steady_ms_p90" => @sprintf("%.4f", st.p90), "steady_ms_median_maxrank" => mr_median,
        "turn1_s" => @sprintf("%.3f", secs[1]), "sum_turns_s" => @sprintf("%.3f", sum(secs)),
        "harness_steady_ms_per_turn" => cn === nothing ? "n/a" : get(cn, "steady_ms_per_turn", "n/a"),
        "moments_rows" => string(size(out.moments, 1)), "lum_rows" => string(length(out.lum_values)),
        "eps_x_last" => repr(ex[end]), "eps_y_last" => repr(ey[end]), "lumi_mean" => repr(lm), "digest" => dg,
        "artifact" => artifact, "timing_path" => timing_path, "log" => logpath,
        "julia_threads" => string(arm.threads), "ranks" => string(arm.ranks), "commit" => COMMIT,
        "load_mode" => LOAD, "digest_lum" => digest_lum(out), "digest_moments" => digest_moments(out),
        "moment_step" => string(MOMENT_STEP))
    append_row!(TSV_PATH, row)
    push!(rows, row)
    true
end

# ------------------------------------------------------------- comparison
function compare(rows)
    for n in N_LIST
        sel = [r for r in rows if r["harness"] == HARNESS && r["n_macro"] == string(n) &&
                                  r["turns"] == string(TURNS) && r["moment_step"] == string(MOMENT_STEP)]
        isempty(sel) && continue
        order = Dict(a.label => i for (i, a) in enumerate(ARMS))
        sort!(sel; by = r -> get(order, r["arm"], 1000))
        base = findfirst(r -> r["arm"] == BASELINE, sel)
        base === nothing && (base = findfirst(r -> startswith(r["arm"], "threads:"), sel))
        b = base === nothing ? nothing : sel[base]
        bout = (b !== nothing && isfile(b["artifact"])) ? read_output(b["artifact"]) : nothing
        say("")
        say("### ", HARNESS, "  N = ", n, "  turns = ", TURNS, "  moment_step = ", MOMENT_STEP,
            "  steady window turns ", SKIP + 1, "..", TURNS,
            b === nothing ? "  (no threads baseline)" : "  baseline " * b["arm"])
        say(rpad("arm", 12), rpad("ms/turn med", 12), rpad("[p10, p90]", 20), rpad("max-rank", 9), rpad("speed-up", 9),
            rpad("wall s", 9), rpad("load", 11), rpad("digest", 14), "identity vs baseline")
        for r in sel
            med = parse(Float64, r["steady_ms_median"])
            sp = b === nothing ? "n/a" : @sprintf("%.2fx", parse(Float64, b["steady_ms_median"]) / med)
            # The verdict's form follows the expectation: a CPU arm (threads
            # or MPI) MUST reproduce the baseline's luminosity series bit for
            # bit (tracking identity) and its moments to the documented fold
            # bound, the worst scaled column quoted; a CUDA arm is reported
            # as relative differences against the threads baseline.
            ident = if b === nothing
                "n/a"
            elseif r["digest"] == b["digest"]
                "bitwise identical"
            else
                d = maximum(reldiff(parse(Float64, r[k]), parse(Float64, b[k])) for k in ("eps_x_last", "eps_y_last", "lumi_mean"))
                lum_same = r["digest_lum"] == b["digest_lum"]
                mom_same = r["digest_moments"] == b["digest_moments"]
                detail = ""
                if bout !== nothing && isfile(r["artifact"])
                    o = read_output(r["artifact"])
                    md, mc = moments_diff(o, bout)
                    detail = @sprintf("worst column %s at %.2e scaled to its max; luminosity series max rel %.2e",
                                      mc, md, max_reldiff(o.lum_values, bout.lum_values))
                end
                if r["arm"] == "cuda"
                    @sprintf("CUDA vs %s: eps_x/eps_y/lumi max rel %.2e; luminosity %s; moments %s%s", b["arm"], d,
                             lum_same ? "BITWISE" : "differ", mom_same ? "BITWISE" : "differ",
                             isempty(detail) ? "" : " (" * detail * ")")
                else
                    @sprintf("luminosity series %s; moments %s%s; eps_x/eps_y/lumi max rel %.2e",
                             lum_same ? "BITWISE (required: ok)" : "DIFFERS (REQUIRED BITWISE: VIOLATED)",
                             mom_same ? "BITWISE" : "within fold bound?",
                             isempty(detail) ? "" : " (" * detail * ")", d)
                end
            end
            say(rpad(r["arm"], 12), rpad(r["steady_ms_median"], 12),
                rpad("[" * r["steady_ms_p10"] * ", " * r["steady_ms_p90"] * "]", 20),
                rpad(r["steady_ms_median_maxrank"], 9), rpad(sp, 9), rpad(r["wall_s"], 9),
                rpad(r["loadavg_launch"] * "/" * r["loadavg_end"], 11), rpad(r["digest"][1:12], 14), ident)
        end
        for r in sel
            r["gpu_util_before"] == "n/a" || say("  ", r["arm"], " GPU (util, memory) before: ", r["gpu_util_before"],
                                                 "; after: ", r["gpu_util_after"])
        end
        say("  output: ", join(["$(r["arm"]) eps_x_last=$(r["eps_x_last"]) eps_y_last=$(r["eps_y_last"]) lumi_mean=$(r["lumi_mean"])" for r in sel], "\n          "))
    end
end

# -------------------------------------------------------------------- main
say("")
say("crab_cavity_noise_backends ", Dates.format(now(), "yyyy-mm-dd HH:MM:SS"), "  tag = ", TAG, "  commit = ", COMMIT)
say("  harness = ", HARNESS_PATH)
say("  n_macro = ", N_LIST, "  turns = ", TURNS, "  skip = ", SKIP, "  seed = ", SEED,
    "  arms = ", join((a.label for a in ARMS), ","), "  baseline = ", BASELINE, "  load = ", LOAD)
say("  julia = ", JULIA, "  host = ", gethostname(), "  cpus = ", Sys.CPU_THREADS, "  loadavg1 = ", loadavg1())
say("  tsv = ", TSV_PATH)
rows = read_rows(TSV_PATH)
isempty(rows) || say("  resuming: ", length(rows), " row(s) already in the TSV")
if NEED_MPI
    say("  MPI launcher = ", LAUNCHER.exec[1], " (", MPI_IMPL, ")")
    # One process warms the package-mode compile cache so R ranks do not
    # race to precompile; it also fails loudly here if the extension is absent.
    say("  warming the package-mode compile cache (using Octopus, MPI) ...")
    warm = setenv(`$(JULIA) --startup-file=no --project=$(ROOT) -e 'using Octopus, MPI; Base.get_extension(Octopus, :OctopusMPIExt) === nothing && error("OctopusMPIExt did not load")'`,
                  child_env(Pair{String,String}[], nothing))
    success(warm) || error("package-mode load of Octopus+MPI failed; the MPI arms cannot run")
end
failed = String[]
for n in sort(N_LIST), arm in ARMS
    if any(r -> rowkey(r) == (HARNESS, arm.label, string(n), string(TURNS), string(MOMENT_STEP)), rows)
        say("skip ", arm.label, " at N = ", n, ": row exists")
        continue
    end
    run_arm!(rows, arm, n) || push!(failed, "$(arm.label) at N = $(n)")
end
compare(rows)
say("")
isempty(failed) || say("ARMS WITHOUT A ROW: ", join(failed, "; "))
say("rows: ", TSV_PATH)
say("log : ", LOG_PATH)
close(LOGIO)
