# U21 — `test/examples/` harnesses + `test/nightly_suite.sh`

Reading unit of the comprehensive audit protocol (`docs/comprehensive_audit.md`),
closing the coverage gap declared in
`docs/history/comprehensive_audit_2026_08_05_b.md` (row U21: "DID NOT RETURN
before the halt — region unreported").

Repo: `/cfs/ad/dxu/Library/Julia/Octopus`.
HEAD at unit start: `b986c73`. **HEAD moved twice during this unit** — see
"Provenance and tree drift" below. Julia 1.12.4, CUDA RTX 4500 Ada.

## Region and coverage

| File | Lines | Depth |
|---|---|---|
| `test/nightly_suite.sh` | 71 | every line, read + executed (13 controlled runs) |
| `test/examples/strong_strong_tracking.jl` | 696 | every line, read + executed (76 + 39 + 9 configurations) |
| `test/examples/weak_strong_tracking.jl` | 318 | every line, read + executed (14 configurations) |

Cross-read for verification only (not audited, seams noted and stopped at):
`examples/weak_strong_tracking.jl` (290), `examples/strong_strong_tracking.jl`
(1-200 for the config/solver blocks), `.github/workflows/ci.yml`,
`AGENTS.md` (Hard-Won Rules, Source Ownership, Updating Examples),
`docs/comprehensive_audit.md` (Measured Lessons 1-9),
`docs/current_runtime.md` §"Nightly Full-Suite Gate", `docs/todo.md` row,
`docs/history/comprehensive_audit_2026_08_05_unit_reports/U18_report.md`,
`test/runtests.jl` (testset structure and CUDA gating only: lines 36-62, 7130-7136,
`grep` of all `@testset`), `.gitignore`,
`src/policies/Policies.jl` 146-275, `src/beam/Beam.jl` 325-400 and 445-495,
`src/tasks/Tasks.jl` 77-150, `src/tasks/strongstrong/interface.jl` 105-200,
1200-1310, 1470-1530, 1820-1830, 1880-1900, 1983-2015, 2217-2231.

No repository file was modified. All probe scripts and outputs are in
`<session scratch>/audit/`. `~/.octopus_nightly/` was never touched and the
real nightly suite was never run.

## Provenance and tree drift (read this before quoting any number below)

Another agent was committing to `main` throughout this unit:

| time (EDT) | event |
|---|---|
| 19:56 | unit start, `git status` clean, HEAD `b986c73` |
| 19:58:33 | commit `7503de4` (`src/track/phase6d_track.jl`, CUDA-only method) |
| 19:59-20:03 | pair bit-identity runs (CPU only) |
| 20:01:25 | commit `3057d21` (`src/tasks/strongstrong/spectral_cuda.jl`, CUDA-only) |
| 20:06-20:35 | CPU matrix, GPU matrix, final probe, policy probe (all after `3057d21`) |
| 20:33 | HEAD `a94afbc`; five commits landed during this unit (`7503de4`, `3057d21`, `7516c3b`, `91f6cad`, `a94afbc`) |

Repository integrity at unit end: `git status --short` clean; the only new path is
an empty, gitignored `test/result/` created at 20:27 by another agent's suite run,
not by this unit (every probe here ran from byte-identical script copies in scratch
with `src/` symlinked, so their `joinpath(@__DIR__, "..", "result")` resolved inside
scratch). `~/.octopus_nightly/status.tsv` still has its original mtime 18:09:51 and
its single pre-existing row.

Both drifting files are CUDA-only, so the CPU pair comparison straddling them is
sound (and the straddled runs came out bit-identical, which is itself the check).
Every matrix ran inside ONE Julia session, so all cases within a matrix share one
tree state. Timings below were taken with 2-3 Julia processes on the box; they are
labelled and are not benchmark-grade.

---

# LEADS

## Nightly gate

### LEAD U21-1 [MAJOR, confidence high] test/nightly_suite.sh:49-57
Claim: the suite's exit code is recovered by **scraping the log file**, a channel
the tested program also writes to, so a FAILING suite can be recorded `PASS`/`exit 0`
and the script itself can exit 0.
Mechanism: `{ echo hdr; "$JULIA" …; echo "exit=$?"; } > "$LOG" 2>&1` writes the
status into the log as text; line 56 reads it back with
`CODE="$(sed -n 's/^exit=//p' "$LOG" | tail -1)"`. The code never lives in a shell
variable, so two things the tested program controls can defeat it: (a) if julia's
final stdout line has no trailing newline, the script's own `exit=N` marker is
concatenated onto that line and `^exit=` no longer matches — the code is lost;
(b) once (a) has happened, `tail -1` selects whatever earlier line in the suite's
own output begins with `exit=`. The header at lines 20-22 asserts the opposite
("the code is captured before any postprocessing").
Repro: with a julia stub that prints `exit=0` on its own line, ends its output
without a newline, and exits 1:
```
printf '#!/bin/bash\nprintf "Test Summary: | Pass Total\\nexit=0\\nERROR: SOME TESTS FAILED"\nexit 1\n' > /tmp/js; chmod +x /tmp/js
HOME=/tmp/h OCTOPUS_NIGHTLY_JULIA=/tmp/js test/nightly_suite.sh; echo "script exit=$?"
cat /tmp/h/.octopus_nightly/status.tsv
```
Measured row: `20260805_195736  v0.1.9-239-gb986c73-dirty  1  PASS  0`, script exit 0.
Fix shape: `"$JULIA" … > "$LOG" 2>&1; CODE=$?` — a shell variable, not a log scrape.

### LEAD U21-2 [MEDIUM, confidence high] test/nightly_suite.sh:56-57
Claim: the same scrape turns a **PASSING** suite into `FAIL` with a synthetic
`exit 125` whenever the suite's last stdout line lacks a trailing newline.
Mechanism: `^exit=` fails to match (see U21-1(a)), `CODE` is empty, line 57
substitutes the sentinel 125. 125 is undocumented and indistinguishable in
`status.tsv` from a genuine exit 125.
Repro: julia stub that prints without a trailing newline and exits 0:
```
printf '#!/bin/bash\nprintf "Test Summary: | Pass Total\\nOctopus | 5 5 1.0s"\nexit 0\n' > /tmp/js2; chmod +x /tmp/js2
HOME=/tmp/h2 OCTOPUS_NIGHTLY_JULIA=/tmp/js2 test/nightly_suite.sh; echo "script exit=$?"
```
Measured row: `20260805_195652  v0.1.9-239-gb986c73  1  FAIL  125`, script exit 125.

### LEAD U21-3 [MEDIUM, confidence high] test/nightly_suite.sh:36-43
Claim: lock contention writes **no row at all** and exits 0, so a wedged or
killed run silences the nightly record for up to 24 h while every cron
invocation reports success.
Mechanism: if `mkdir "$LOCK"` fails and the lock is younger than 1440 min, line 41
`exit 0` returns before any row is appended and before `latest.log` is updated.
The header's "one appended row per run" is false on this path, and `exit 0` is
indistinguishable from a passing run to anything watching cron's exit status.
The only surviving signal is a stale date, which nothing checks automatically.
Repro:
```
mkdir -p /tmp/h3/.octopus_nightly/lock
HOME=/tmp/h3 OCTOPUS_NIGHTLY_JULIA=/bin/false test/nightly_suite.sh; echo "exit=$?"
ls /tmp/h3/.octopus_nightly/     # -> only `lock`; no status.tsv, no log
```
Measured: script exit 0, `status.tsv` never created.

### LEAD U21-4 [MEDIUM, confidence high] test/nightly_suite.sh:33,46
Claim: two further row-less exits. `mkdir -p "$OUTDIR"` (line 33) is unchecked, so
on a machine where `$HOME/.octopus_nightly` cannot be created the gate exits 0
forever with no row and no log; `cd "$REPO" || exit 1` (line 46) exits without a
row too.
Repro (first case):
```
mkdir -p /tmp/ro; chmod 500 /tmp/ro
HOME=/tmp/ro OCTOPUS_NIGHTLY_JULIA=/bin/false test/nightly_suite.sh; echo "exit=$?"
```
Measured: two `mkdir`/`find` errors on stderr (which cron mails, but only if
`MAILTO` is set), script **exit 0**, no row.

### LEAD U21-5 [LOW, confidence high] test/nightly_suite.sh:58
Claim: the `testsets` column is a real, uncalibrated coverage tripwire: it is not
scraped from anything truncated, but nothing compares it to an expected value, so
the one failure it can detect — a GPU machine that silently stops running the CUDA
half — is recorded as `PASS` with a smaller number.
Mechanism: `grep -c '^Test Summary'` counts **top-level** testsets only (Julia
prints one `Test Summary:` header per top-level `@testset`; nested ones do not add
a line). For this suite that is 135 (`grep -c '^@testset' test/runtests.jl`) plus
the 16 indented testsets inside the top-level `if Octopus._HAS_CUDA &&
Octopus.CUDA.functional()` block at `test/runtests.jl:7133` = **151 with a GPU, 135
without**. The only real nightly row on this machine (read, not written:
`~/.octopus_nightly/status.tsv`, mtime 18:09, before this unit began) is
`20260805_175308  v0.1.9-224-gb6957df  151  PASS  0`, which confirms the 151
derivation from a live run. `docs/current_runtime.md` records "first row PASS at
151 testsets" in prose; that and this one row are the only places the expected
value exists — nothing compares a future row against them.
Repro (counting semantics):
```
julia -e 'using Test; @testset "a" begin @test 1==1 end; @testset "b" begin @test 2==2; @testset "n" begin @test 3==3 end end' 2>&1 | grep -c '^Test Summary'
```
Measured: 2 (not 3) — nested testsets are not counted.

### LEAD U21-6 [LOW, confidence med] test/nightly_suite.sh:36-43
Claim: stale-lock reclamation is racy — two runs that both observe `-mmin +1440`
both `rmdir` and both `mkdir`, and the second `rmdir` removes the first run's
*fresh* lock, so both proceed concurrently and both append rows.
Mechanism: test-and-set is three separate non-atomic syscalls
(`find` → `rmdir` → `mkdir`). Argued from the code; NOT measured (needs a
contrived simultaneous launch with a >24 h-old lock).
Repro: create a lock dir with `touch -d '3 days ago'`, launch two copies of the
script within the same second, and count rows in `status.tsv` (expect 2).

### LEAD U21-7 [LOW, confidence high] test/nightly_suite.sh:15,17,29
Claim: header/output mismatch. It documents `$HOME/.octopus_nightly/<date>.log`
and a `date` column; `STAMP="$(date +%Y%m%d_%H%M%S)"` makes both a *datetime*
stamp.
Repro: any run — the measured filename is `20260805_195639.log` and the first
column is `20260805_195639` under the header `date`.

### LEAD U21-8 [LOW, confidence high] test/nightly_suite.sh:20-22
Claim: the header's own justification is factually wrong — "the trailing-pipe trap
… is why the code is captured before any postprocessing". The code is not captured;
it is written into `$LOG` and re-parsed out of it with `sed … | tail -1`. This is
the documentation face of U21-1 and is the reason the defect reads as intentional.

### LEAD U21-9 [LOW, confidence low] test/nightly_suite.sh:69
Claim: `ls -1t "$OUTDIR"/*.log | grep -v latest | …` filters on the whole path, so a
`$HOME` whose path contains the substring `latest` disables log rotation entirely.

## Harnesses

### LEAD U21-10 [MEDIUM, confidence high] test/examples/strong_strong_tracking.jl:29-39
Claim: the U18-2 documentation fix landed by `b986c73` was inserted **into the
middle of a sentence**, so the header now reads as garbage at its most-read point.
Mechanism: line 29 ends "…Select the Poisson solver with"; lines 30-37 are eight
lines of unrelated new text; the sentence's object ("`OCTOPUS_SOLVER` (pic |
spectral | gaussian | gaussian_pic)…") resumes at line 39.
Repro: `sed -n '29,40p' test/examples/strong_strong_tracking.jl` — the first two
lines do not form a sentence.

### LEAD U21-11 [MEDIUM, confidence high] test/examples/strong_strong_tracking.jl:35-36 vs 642-650
Claim: the same commit's documentation and code contradict each other about
`OCTOPUS_TURN_TIMING_PATH`. The new header text (line 36) annotates it
"(cwd-relative)"; the new code (649-650) made it **not** cwd-relative.
Repro: `grep -n 'cwd-relative' test/examples/strong_strong_tracking.jl` and
`sed -n '642,652p'` — one says cwd, the other `joinpath(@__DIR__, "..", …)`.

### LEAD U21-12 [MEDIUM, confidence high] test/examples/strong_strong_tracking.jl:644-650
Claim: the U18-5 fix's own comment misdescribes its own code, and the fix
**relocates** the stray repository write rather than removing it — into a
directory that is *not* gitignored.
Mechanism: the comment claims "A relative path resolves against this harness's own
result directory"; `timing_path = joinpath(@__DIR__, "..", timing_path)` resolves
against `test/`, not `test/result/`. The documented example
(`OCTOPUS_TURN_TIMING_PATH=result/pic_turn_times.tsv`, header line 120) lands in
`test/result/` only because the *string* happens to start with `result/`. Any other
relative path lands directly in `<repo>/test/`, and `.gitignore` covers `result/`
but not `*.tsv`, so it appears as an untracked repository file.
Repro:
```
OCTOPUS_RECORD_TURN_TIMES=1 OCTOPUS_TURN_TIMING_PATH=stray.tsv julia --project=. test/examples/strong_strong_tracking.jl
git status --short          # -> ?? test/stray.tsv
git check-ignore -v test/stray.tsv   # -> no match
```
Measured in the CPU matrix (case `TURN_TIMING_PATH=stray.tsv`): `strays: stray.tsv`
appeared in the harness's `test/` directory; the `result/t.tsv` case instead
produced `files=…,t.tsv` inside `test/result/`.

### LEAD U21-13 [MEDIUM, confidence high] test/examples/strong_strong_tracking.jl:45-46
Claim: U18-1 was only half-fixed. The code comment at 365-369 now correctly warns
that the commented solver block is dead code, but the header still says "The
soft-Gaussian solver is also available as a commented alternative **below the
solver construction**" — the sentence U18-1 flagged (the block is *above* the
construction) and which the new note contradicts.
Repro: `sed -n '45,46p'` vs `sed -n '365,369p'` vs the block's position at 373-381
relative to the `solver = if …` at 424.

### LEAD U21-14 [LOW, confidence high] test/examples/strong_strong_tracking.jl:365-381 vs 434-441
Claim: the new note claims the commented block "stays as the reference for what
that switch builds", but `OCTOPUS_SOLVER=gaussian` does not pass two of the
keywords the block sets.
Mechanism: the commented `GaussianPoissonSolver(...)` at 373-381 sets
`virtual_drift = :hirata` and `include_sigma_xy = false`; the switch at 434-441
passes only `slicing, min_sigma, luminosity_scale, longitudinal_kick, batch_mode`.
Repro: `diff <(sed -n '373,381p') <(sed -n '435,441p')` — the reference over-states
the switch by two keywords.

### LEAD U21-15 [MEDIUM, confidence high] test/examples/strong_strong_tracking.jl:252-351 (all boolean toggles)
Claim: every boolean `OCTOPUS_*` toggle silently treats an unrecognised value as
`false`, so a mistyped value silently *disables* the five flags whose default is on.
Mechanism: the idiom is `get(ENV, K, default) in ("1","true","TRUE","yes","YES")`.
`True`, `on`, `False`, `Yes`, `1 ` are all "not in the list". For default-off flags
a typo silently fails to enable; for `OCTOPUS_PIC_LONGITUDINAL_KICK`,
`OCTOPUS_CUDA_PIC_ASYNC`, `_BATCH_FFT`, `_WAVEFRONT_FFT`, `_INDEXED_WAVEFRONT`
(default `"1"`) a typo silently turns the feature **off**.
Repro:
```
OCTOPUS_DISABLE_COLLISION=True julia --project=. test/examples/strong_strong_tracking.jl | grep beam_beam
# -> beam_beam_collision = enabled     (identical rms to the no-env baseline)
OCTOPUS_CUDA_PIC_ASYNC=False julia --project=. test/examples/strong_strong_tracking.jl | grep cuda_pic_async
# -> cuda_pic_async = false            (the word "False" turned it OFF)
```
Measured: `DISABLE_COLLISION=True` and `=on` produced byte-identical stdout and
`.lum` to baseline; `CUDA_PIC_ASYNC=False` set the flag to `false` (and on CPU
tripped the library's own `non-default CUDA-only solver options are inactive on
CPU storage` warning, `interface.jl:2091` — that tripwire works).

### LEAD U21-16 [MEDIUM, confidence high] test/examples/strong_strong_tracking.jl:230 and test/examples/weak_strong_tracking.jl:141
Claim: `OCTOPUS_USE_GPU` is the one boolean with a stricter, different grammar
(`== "1"`), so `OCTOPUS_USE_GPU=true` and `=yes` silently run on **CPU** while the
same two words enable every other flag in the same file.
Mechanism: `use_gpu = get(ENV, "OCTOPUS_USE_GPU", "0") == "1"`. This is the worst
instance of U21-15 because a "GPU" benchmark that silently ran on CPU is a wrong
measurement rather than a missing one, and the harness prints nothing about which
backend it used.
Repro:
```
OCTOPUS_USE_GPU=true julia --project=. test/examples/strong_strong_tracking.jl
```
Measured: byte-identical stdout and `.lum` to the CPU baseline for both `true` and
`yes`, in both harnesses.

### LEAD U21-17 [MAJOR, confidence high] test/examples/strong_strong_tracking.jl:235-247, 633-636
Claim: `OCTOPUS_CUDA_THREADS`, `OCTOPUS_CUDA_BLOCKS` and `OCTOPUS_CPU_THREADS`
configure **only beam construction and are then discarded**; tracking always runs
at the library defaults — while header lines 122-126 advertise exactly these
variables as the way to "Benchmark fused CUDA launch geometry through the public
policy interface. PIC family overrides … otherwise inherit `CUDA_THREADS`". Any
A/B benchmark taken with these knobs measured nothing.
Mechanism: the harness builds `policy` with the requested launch geometry and
passes it to `Beam(...)` (line 265/278), but constructs
`StrongStrongTask(line_ele, line_pro; luminosity_path=…, diagnostics)` (633-636)
with **no `policy=` kwarg**. At execute time `_resolve_strong_strong_policy` calls
`_resolve_execution_policy(task.policy, rep)` with `task.policy === nothing`
(`src/tasks/strongstrong/interface.jl:2222`; `src/beam/Beam.jl:333-337`), which
builds a **fresh default** `CUDAExecutionPolicy()` / `CPUThreadsExecutionPolicy()`.
The PIC per-kernel "inherit" path then inherits that default's 256, not
`CUDA_THREADS` (`interface.jl:177`, `_resolve_cuda_pic_configuration`).
`src/tasks/Tasks.jl:83-85` documents this behaviour; the harness header
contradicts it.
Repro (decisive — prints the requested policy beside the one `execute!` uses):
```julia
# julia --project=. --threads=4
ENV["OCTOPUS_CPU_THREADS"] = "1"          # or USE_GPU=1 + CUDA_THREADS=64
include("test/examples/strong_strong_tracking.jl")
@show policy, task.policy,
      Octopus._resolve_execution_policy(task.policy, beam_ele.rep)
```
Measured (`julia --threads=4`, one session, five configurations):

| harness env | policy the harness built | `task.policy` | policy `execute!` uses |
|---|---|---|---|
| (none) | `CPUThreadsExecutionPolicy(:auto)` | `nothing` | `ResolvedCPUExecutionPolicy(4)` |
| `CPU_THREADS=1` | `CPUThreadsExecutionPolicy(1)` | `nothing` | **`ResolvedCPUExecutionPolicy(4)`** |
| `USE_GPU=1` | `CUDALaunchConfig(256, :auto)` | `nothing` | `ResolvedCUDAExecutionPolicy(0, 256, :auto)` |
| `USE_GPU=1 CUDA_THREADS=64` | `CUDALaunchConfig(64, :auto)` | `nothing` | **`ResolvedCUDAExecutionPolicy(0, 256, :auto)`** |
| `USE_GPU=1 CUDA_THREADS=2048 CUDA_BLOCKS=7` | `CUDALaunchConfig(2048, 7)` | `nothing` | **`ResolvedCUDAExecutionPolicy(0, 256, :auto)`** |

Corroborating: `OCTOPUS_USE_GPU=1 OCTOPUS_CUDA_THREADS=2048` — an impossible block
size on every NVIDIA GPU (max 1024) — ran to completion with stdout and `.lum`
byte-identical to the 256 default, and never reached the device-limit guard at
`src/beam/Beam.jl:355-356`, because that guard is only reached through the policy
path the task discards.
Seam note: both clean `examples/` scripts omit `policy=` the same way
(`examples/strong_strong_tracking.jl:253`), so this is a workflow-wide seam and the
auditor's call, not the harness's alone. The harness-side fact is that three
documented benchmarking knobs are inert for the thing they are documented to tune.

### LEAD U21-18 [MEDIUM, confidence high] test/examples/strong_strong_tracking.jl:352-364, 424-441
Claim: all seven `OCTOPUS_CUDA_PIC_*_THREADS` overrides are validated and then
**discarded** for two of the four solvers `OCTOPUS_SOLVER` selects.
Mechanism: `cuda_pic_backend_configurations` is passed only to
`GaussianPICPoissonSolver` (line 457) and `PICPoissonSolver` (line 478).
`SpectralPoissonSolver` (425-433) and `GaussianPoissonSolver` (435-441) receive no
`backend_configurations`, and those two solver types have no such field
(`backend_configurations` is a `PICPoissonSolver` field,
`src/tasks/strongstrong/interface.jl:1211`). The name makes it worse:
`OCTOPUS_CUDA_PIC_SPECTRAL_THREADS` is exactly what a user tuning
`OCTOPUS_SOLVER=spectral` would set, and it is read, range-checked, and dropped.
Repro:
```
OCTOPUS_USE_GPU=1 OCTOPUS_SOLVER=spectral OCTOPUS_CUDA_PIC_SPECTRAL_THREADS=2048 julia --project=. test/examples/strong_strong_tracking.jl
```
Measured: throws `ArgumentError: CUDA PIC thread counts must be nothing or
integers in 1:1024` from the `CUDAPICLaunchConfig` constructor at line 355 — i.e.
the value is validated even though no spectral code will ever see it.

### LEAD U21-19 [MEDIUM, confidence high] test/examples/strong_strong_tracking.jl:352-353, 589-600
Claim: `OCTOPUS_MOMENT_CAPACITY=0` is silently accepted, writes **no moment files
at all**, and the harness still prints the two moment paths as if it had.
Mechanism: `moment_capacity = parse(Int, get(ENV, "OCTOPUS_MOMENT_CAPACITY", …))`
has no lower bound; `MomentObserver(path; capacity=0)` is accepted; the summary
lines at 693-694 print the paths unconditionally because they are gated on
`disable_moments`, not on whether anything was written.
Repro:
```
OCTOPUS_MOMENT_CAPACITY=0 julia --project=. test/examples/strong_strong_tracking.jl
ls test/result/           # -> pic_hcc.lum only; no .ele.h5, no .pro.h5
```
Measured: `snap: lum=aabbf57092cd0ba6 ele=MISSING pro=MISSING files=pic_hcc.lum`
with `stdout_changed: false` — the run's own report is byte-identical to a run that
did write them. This is "loud beats silent" (Measured Lesson 8) inverted: data
vanished and the summary claimed otherwise.

### LEAD U21-20 [LOW, confidence high] test/examples/strong_strong_tracking.jl:677-684
Claim: the summary block prints PIC-family settings unconditionally, so a
non-PIC-solver run reports configuration it did not apply.
Mechanism: with `OCTOPUS_SOLVER=gaussian`, the lines `pic_green_cache`,
`pic_slice_pair_green_min_ratio`, `pic_slice_pair_green_growth`, `cuda_pic_async`,
`cuda_pic_batch_fft`, `cuda_pic_wavefront_fft`, `cuda_pic_indexed_wavefront`,
`pic_luminosity_every`, `pic_luminosity_grid`, `pic_luminosity_deposit_method` are
all printed with their env values, and none of them is passed to
`GaussianPoissonSolver` (435-441). With `OCTOPUS_SOLVER=gaussian_pic` line 682
prints `pic_luminosity_grid = (128, 128)` (`input.solver.pic_grid`) while the
solver actually uses `gpic_grid` (default `(64, 64)`).
Repro: `OCTOPUS_SOLVER=gaussian julia --project=. test/examples/strong_strong_tracking.jl`
— measured stdout differs from the PIC baseline in exactly 3 lines
(`poisson_solver`, the two `rms` lines) plus the removal of
`pic_luminosity_deposit_method_resolved`; all ten PIC-knob lines print unchanged.

### LEAD U21-21 [LOW, confidence high] test/examples/strong_strong_tracking.jl:415-422
Claim: inconsistent grid-value validation. `OCTOPUS_PIC_LUMINOSITY_GRID` checks
`length(values) == 2` and raises a named error (line 316); `OCTOPUS_SPECTRAL_GRID`
and `OCTOPUS_GPIC_GRID` do not, so a one-element value dies with a raw
`BoundsError: attempt to access 1-element Vector{Int64} at index [2]`.
Repro: `OCTOPUS_SOLVER=spectral OCTOPUS_SPECTRAL_GRID=64 julia --project=. test/examples/strong_strong_tracking.jl`
(measured: BoundsError, vs `OCTOPUS_PIC_LUMINOSITY_GRID=64` → `OCTOPUS_PIC_LUMINOSITY_GRID must be nx,ny`).

### LEAD U21-22 [LOW, confidence high] test/examples/strong_strong_tracking.jl:254-263
Claim: `OCTOPUS_ELECTRON_ENERGY_GEV=-5` (a negative beam energy) is accepted and
tracked to completion, printing `electron_energy_GeV = -5.0` and plausible rms.
Mechanism: `parse(Float64, …) * 1.0e9` with no sign or magnitude check; the same
holds for `OCTOPUS_PROTON_ENERGY_GEV`.
Repro: `OCTOPUS_ELECTRON_ENERGY_GEV=-5 julia --project=. test/examples/strong_strong_tracking.jl; echo $?`
Measured: exit 0, `electron rms = [2.3595e-4, …]`.

### LEAD U21-23 [LOW, confidence high] test/examples/strong_strong_tracking.jl:1-139
Claim: eight `OCTOPUS_*` variables are still absent from the header after the
U18-2 fix, because the fix used globs instead of names — `OCTOPUS_CUDA_PIC_*_THREADS`
and "the CUDA_PIC_SLICE_PAIR green-cache aliases" are not greppable or
copy-pasteable, and they also drop the `OCTOPUS_` prefix.
Repro:
```
comm -13 <(sed -n '1,139p' test/examples/strong_strong_tracking.jl | grep -o 'OCTOPUS_[A-Z_]*' | sort -u) \
         <(awk 'NR>140' test/examples/strong_strong_tracking.jl | grep -o 'OCTOPUS_[A-Z_]*' | sort -u)
```
Measured: `OCTOPUS_CUDA_PIC_{FIELD,GATHER_SCATTER,GREEN,KICK,LUMINOSITY,SPECTRAL}_THREADS`,
`OCTOPUS_CUDA_PIC_SLICE_PAIR_GREEN_{GROWTH,MIN_RATIO}` — 8 names.

### LEAD U21-24 [LOW, confidence high] test/examples/strong_strong_tracking.jl:159,179 and test/examples/weak_strong_tracking.jl:63,70
Claim: dead configuration fields that read as authoritative defaults.
`input.electron.n_macro = 2560000` and `input.proton.n_macro = 1024000` are read
nowhere (the actual default is `default_demo_macroparticles = 200`, line 151); the
clean counterpart deliberately keeps these in its `config` block instead and has no
such fields in `input`. In the weak-strong harness `input.total_turns = 1_000_000`
(:63) and `input.weak_beam.n_macro = 1_024_000` (:70) are likewise read nowhere
(here the clean example carries the same two dead fields — region-adjacent).
Repro: `grep -n 'n_macro' test/examples/strong_strong_tracking.jl` — the only
consumers are `n_macro_ele`/`n_macro_pro` from `ENV`.

### LEAD U21-25 [LOW, confidence high] test/examples/strong_strong_tracking.jl:291-292
Claim (out of hypothesis): the harness asserts element types through the runtime
representation, `eltype(beam_ele.rep.x)`, which AGENTS.md classes as an
implementation detail that "may change" (Architectural Rules; Two-Layer Element
Design). A public accessor would survive a representation change; this line would
not.

### LEAD U21-26 [LOW, confidence high] test/examples/weak_strong_tracking.jl:33
Claim (cosmetic): the U18-6 fix produced a 138-character line whose parenthetical
interrupts the sentence, in a header that otherwise wraps at ~79 columns.
Repro: `awk 'length>100 {print FILENAME":"FNR": "length}' test/examples/*.jl`.

### LEAD U21-27 [LOW, confidence high] both harnesses (write paths)
Claim: confirms and refines the prior unit's finding. Both harnesses write into
the repository working tree at fixed, non-configurable paths, and **no `OCTOPUS_*`
override exists**:
* `test/examples/weak_strong_tracking.jl:61` → `<repo>/test/result/weak_strong.lum`,
  `<repo>/test/result/weak_strong_moments.h5`
* `test/examples/strong_strong_tracking.jl:148` → `<repo>/test/result/pic_hcc.lum`,
  `pic_hcc.ele.h5`, `pic_hcc.pro.h5`
* plus `OCTOPUS_TURN_TIMING_PATH` (see U21-12), which can land outside `result/`.
`result_dir` is a literal `joinpath(@__DIR__, "..", "result")`; `grep -n result_dir`
shows no `ENV` read anywhere in either file. `test/result/` **is** gitignored
(`git check-ignore -v test/result/pic_hcc.lum` → `.gitignore:16:result/`).
**REFUTES** the prior unit's failure-mode claim: two concurrent runs do NOT fail
with "an opaque HDF5 error at finalize". Measured twice — at the 2-turn default and
with a deliberately widened write window (`OCTOPUS_TURNS=40
OCTOPUS_MOMENT_CAPACITY=2`, 20 flushes each) — both processes exited 0, printed no
error, and left one set of files. The real behaviour is **silent last-writer-wins
clobbering**, which is worse than an error by the repository's own "loud beats
silent" rule.
Repro:
```
julia --project=. test/examples/strong_strong_tracking.jl & \
julia --project=. test/examples/strong_strong_tracking.jl & wait
```
Measured: both exit 0.

### LEAD U21-28 [LOW, confidence high] seam — moment `.h5` outputs are not reproducible
Claim (out of hypothesis, seam — stopping here): `pic_hcc.{ele,pro}.h5` and
`weak_strong_moments.h5` are not byte-reproducible across two identical runs, so no
byte-level regression check can be built on them.
Mechanism: two independent sources — HDF5 object-header birth timestamps in the
file format, and an `elapsed_time` **dataset** written by `MomentObserver`
(`src/analysis/BeamObservers.jl`, not audited here).
Repro: run `test/examples/weak_strong_tracking.jl` twice with identical inputs and
`cmp` the two `weak_strong_moments.h5`.
Measured: 48 differing bytes, all in 4-byte object-header timestamps and their
checksums; the four `HDF5` datasets are `column_names`, `data`, `elapsed_time`,
`record_count`, and `elapsed_time` differs by construction.

---

# Hypothesis (a) — the nightly gate, answered point by point

**(i) Does it run the exact documented gate?  YES.**
`test/nightly_suite.sh:51-52` is
`"$JULIA" --project=. --threads=4 -e 'using Pkg; Pkg.test(julia_args=["--threads=4"])'`,
character-for-character the `.github/workflows/ci.yml` "Run fast package tests"
step and Measured Lesson 9's calibrated invocation. Two immaterial differences:
CI runs `Pkg.instantiate()` first (the nightly relies on `Pkg.test` resolving), and
neither passes `--startup-file=no`, so a machine with a
`~/.julia/config/startup.jl` runs a slightly different environment than CI.

**(ii) Does it commit Measured Lesson 9's exact error (a trailing pipe eating the
failing exit code)?  NO — but it commits a sibling that is worse.**
The literal trap is absent: line 69's pipeline is followed by an explicit
`exit "$CODE"` at line 71, measured to propagate 1, 127 and 137 correctly. The
sibling defect is U21-1: the exit code is round-tripped through the log text
instead of a shell variable.

**(iii) Does a FAILING suite produce a FAIL row?  USUALLY, BUT NOT RELIABLY.**
Demonstrations, all against a scratch `$HOME` with the real script unmodified via
its own `OCTOPUS_NIGHTLY_JULIA` hook (`~/.octopus_nightly` untouched):

| # | julia stub | script exit | row written to `status.tsv` |
|---|---|---|---|
| A | `/bin/false` (exit 1) | 1 | `20260805_195639  v0.1.9-239-gb986c73  0  FAIL  1` |
| B | `/bin/true` (exit 0) | 0 | `20260805_195652  v0.1.9-239-gb986c73  0  PASS  0` |
| C | exit 0, last line lacks `\n` | **125** | `20260805_195652  v0.1.9-239-gb986c73  1  FAIL  125` |
| D | `/nonexistent/julia` | 127 | `20260805_195652  v0.1.9-239-gb986c73  0  FAIL  127` |
| E | **exit 1**, prints `exit=0`, last line lacks `\n` | **0** | `20260805_195736  v0.1.9-239-gb986c73-dirty  1  **PASS  0**` |
| I | exit 1, prints `exit=lol` (with `\n`) | 1 | `20260805_200945  v0.1.9-241-g3057d21  0  FAIL  1` |
| J | killed by SIGKILL | 137 | `20260805_200945  v0.1.9-241-g3057d21  1  FAIL  137` |
| F | lock held, <24 h old | **0** | **no row at all; `status.tsv` never created** |
| K | lock held, 3 days old | 1 | `20260805_201202  v0.1.9-241-g3057d21  0  FAIL  1` (lock reclaimed) |
| G | `$HOME` unwritable | **0** | **no row at all** |

Rows A, B, D, I, J, K are correct. Row C is a false FAIL (U21-2). **Row E is a
failing suite recorded as PASS with the script exiting 0** (U21-1). Rows F and G
are silent no-ops (U21-3, U21-4).
Baseline check for the happy path: an uncaught Julia error — which is how a failing
`Pkg.test` terminates — exits 1 (`julia -e 'error("boom")'; echo $?` → 1), so the
common case does produce a FAIL row.

**(iv) Is the testset count real or scraped from something truncable?  REAL, but
uncalibrated.** See U21-5. The log is never truncated by this script; the count is
of top-level `Test Summary:` headers, which is 151 with a GPU and 135 without.

**(v) Can a concurrent or interrupted run clobber or corrupt `status.tsv`?  NO
CORRUPTION MEASURED.** Within the lock, the row is one `printf … >>` — a single
small `O_APPEND` write, atomic on Linux. The failure mode is a **missing** row
(U21-3, U21-4), not a corrupted one. The lock itself has a reclamation race
(U21-6, argued not measured). An interrupted run leaves the lock behind; the
`-mmin +1440` reclamation was measured to work (row K).

**(vi) Does the shebang match the syntax used?  YES.** `#!/bin/bash`, and the body
uses only POSIX-compatible constructs plus GNU `find -mmin`, `xargs -r`, `ln -sfn`
— all available on the Linux hosts this targets. The file is `100755` in git.
`shellcheck` is not installed on this box, so no linter was run (see Unchecked).

---

# Hypothesis (b) — pair bit-identity: **PASS, both pairs**

Method: byte-identical copies of all four scripts placed in a scratch tree at the
same relative depth (`clone/{examples,test/examples}` with `clone/src` symlinked to
the repository `src/`), so each script's `joinpath(@__DIR__, "..", "result")`
resolves inside scratch and **nothing was patched**. `cmp` confirmed all four
copies byte-identical to the repository originals before running. Every
`OCTOPUS_*` variable unset (`env | grep -c '^OCTOPUS_'` → 0).

| pair | observable | example | harness | verdict |
|---|---|---|---|---|
| weak-strong | `rms` (6 doubles) | `[9.570787996269571e-5, 1.1797688746010158e-4, 8.642069261157512e-6, 1.1634985550187557e-4, 6.013617230833779e-2, 6.584986899628289e-4]` | identical | **bit-identical** |
| weak-strong | `weak_strong.lum` | 50 bytes | 50 bytes | **`cmp` clean** |
| strong-strong | electron `rms` | `[8.224897020012971e-5, 2.849005945081036e-4, 1.036419700534238e-5, 1.650738634926186e-4, 7.021209648524774e-3, 5.481470809149434e-4]` | identical | **bit-identical** |
| strong-strong | proton `rms` | `[9.422779492815086e-5, 1.1989278847823692e-4, 8.148281847685992e-6, 1.2382658083667767e-4, 5.987801202592774e-2, 6.613387923224379e-4]` | identical | **bit-identical** |
| strong-strong | `pic_hcc.lum` | 56 bytes | 56 bytes | **`cmp` clean** |

The remaining stdout differences are only the output paths (different `result_dir`
by design, documented in both headers) and, for strong-strong, the harness's extra
`n_macro_*` and configuration echo lines. The moment `.h5` files differ in 46-48
bytes, but so do two runs of the *same* script (U21-28) — the difference is
timestamps, not drift.

This is the strongest available form of the check: it means every default of the
23 solver/diagnostic keywords the harness passes explicitly (and the clean example
does not) equals the constructor default it stands in for.

---

# Hypothesis (c) — `OCTOPUS_*` effectiveness table

49 variables are read by `test/examples/strong_strong_tracking.jl`, 4 by
`test/examples/weak_strong_tracking.jl` (`OCTOPUS_TURNS`, `OCTOPUS_N_MACRO`,
`OCTOPUS_USE_GPU`, `OCTOPUS_CUDA_DEVICE`; the first three are shared).

Method: three driver scripts, each running the byte-identical harness clone
repeatedly inside one Julia session (so all cases share one tree state and one
compiled `Octopus`), clearing every `OCTOPUS_*` between cases. Observables per
case: full stdout, `sha256` of `pic_hcc.lum`, per-dataset content hashes of the two
`.h5` files, the file list, and any file created in `test/` outside `result/`.
"Effect" below means **an output bit changed**, not merely that the harness
echoed the value.

Legend: **bits** = output bytes changed; **diag** = stdout diagnostics only, `.lum`
unchanged; **none** = nothing observable changed; **throw** = rejected loudly.

| Variable | Default | Non-default tested | CPU effect | CUDA effect |
|---|---|---|---|---|
| `OCTOPUS_TURNS` | `2` | `3` / `abc` | **bits** / throw | — |
| `OCTOPUS_N_MACRO` | unset→200 | `300` / `0` | **bits** / throw | — |
| `OCTOPUS_N_MACRO_ELE` | 200 | `300` | **bits** | — |
| `OCTOPUS_N_MACRO_PRO` | 200 | `300` | **bits** | — |
| `OCTOPUS_USE_GPU` | `0` | `1` | **bits** | — |
| `OCTOPUS_USE_GPU` (mistyped) | `0` | `true`, `yes` | **none (silent CPU)** | — |
| `OCTOPUS_CPU_THREADS` | `auto` | `1`,`2`,`4` / `0`,`-4`,`8`(>nthreads) | **none — discarded before tracking (U21-17)** / throw (`CPU threads must be in 1:4`) | n/a |
| `OCTOPUS_CUDA_DEVICE` | unset | `0` / `99` | none (branch not taken) | selects storage device / throw (`CUDA error: invalid device ordinal (code 101)`) |
| `OCTOPUS_CUDA_THREADS` | `256` | `64` / `2048` | n/a | **none — discarded before tracking (U21-17); 2048 silently accepted, no range check** |
| `OCTOPUS_CUDA_BLOCKS` | `auto` | `32`,`7` / `nope` | n/a | **none — discarded before tracking (U21-17)** / throw |
| `OCTOPUS_WEAK_STRONG_LIMIT` | `0` | `1` | **bits** | — |
| `OCTOPUS_ELECTRON_ENERGY_GEV` | 10 | `20` / `-5` | **bits** / **bits, accepted (U21-22)** | — |
| `OCTOPUS_PROTON_ENERGY_GEV` | 275 | `100` | **bits** | — |
| `OCTOPUS_SOLVER` | `pic` | `gaussian`,`spectral`,`gaussian_pic` / `bogus` | **bits** / throw (named) | **bits** |
| `OCTOPUS_SPECTRAL_GRID` | `127,383` | `63,63` / `64` | **bits** / throw (`BoundsError`) | **bits** |
| `OCTOPUS_SPECTRAL_DOMAIN_FACTOR` | `8.0` | `4.0` | **bits** | — |
| `OCTOPUS_SPECTRAL_FIELD_PRECISION` | `double` | `single` / `bogus` | **bits** / throw (named) | — |
| `OCTOPUS_GPIC_GRID` | `64,64` | `32,32` / `32` | **bits** / throw (`BoundsError`) | — |
| `OCTOPUS_PIC_GREEN_CACHE` | `slice_pair` | `none` / `bogus` | **bits** / throw (named) | **bits** |
| `OCTOPUS_PIC_SLICE_PAIR_GREEN_MIN_RATIO` | `0.50` | `0.95` | **bits** | — |
| `OCTOPUS_PIC_SLICE_PAIR_GREEN_GROWTH` | `0.25` | `1.5` | **bits** | — |
| `OCTOPUS_CUDA_PIC_SLICE_PAIR_GREEN_MIN_RATIO` (alias) | — | `0.95` | **bits** | — |
| `OCTOPUS_CUDA_PIC_SLICE_PAIR_GREEN_GROWTH` (alias) | — | `1.5` | **bits** | — |
| `OCTOPUS_PIC_LONGITUDINAL_KICK` | `1` | `0` | **bits** | — |
| `OCTOPUS_PIC_BATCH_MODE` | `wavefront` | `sequential` / `bogus` | **bits** / throw (named) | **bits** |
| `OCTOPUS_CUDA_PIC_ASYNC` | `1` | `0` | diag + warn (CPU-inactive) | **bits** |
| `OCTOPUS_CUDA_PIC_BATCH_FFT` | `1` | `0` | diag + warn | **bits** |
| `OCTOPUS_CUDA_PIC_WAVEFRONT_FFT` | `1` | `0` | diag + warn | **bits** |
| `OCTOPUS_CUDA_PIC_INDEXED_WAVEFRONT` | `1` | `0` | diag + warn | **diag only — `.lum` identical (paths agree bitwise)** |
| `OCTOPUS_PIC_LUMINOSITY_EVERY` | `1` | `2`, `0` / `-1` | **bits** / throw (named) | — |
| `OCTOPUS_PIC_LUMINOSITY_GRID` | inherit | `64,64` / `64` | **bits** / throw (named) | — |
| `OCTOPUS_PIC_LUMINOSITY_DEPOSIT_METHOD` | inherit | `TSC` / `BOGUS` | **bits** / throw (named) | — |
| `OCTOPUS_RECORD_TURN_TIMES` | `0` | `1` | diag | diag |
| `OCTOPUS_TURN_TIMING_PATH` | `""` | `result/t.tsv`, `stray.tsv` | **new file** (locations per U21-12) | — |
| `OCTOPUS_CUDA_MEMORY_LOG_EVERY` | `0` | `1` | diag (inactive-on-CPU warn) | diag |
| `OCTOPUS_CUDA_PIC_TIMING` | `0` | `1` | diag | diag |
| `OCTOPUS_CUDA_PIC_TIMING_DETAIL` | `0` | `1` | diag | **bits** (documented: disables async) |
| `OCTOPUS_PIC_CACHE_STATS` | `0` | `1` | diag | diag |
| `OCTOPUS_CUDA_NVTX` | `0` | `1` | diag | **none** (NVTX ranges need a profiler) |
| `OCTOPUS_DISABLE_MOMENTS` | `0` | `1` | **files removed** | — |
| `OCTOPUS_DISABLE_LUMINOSITY_OUTPUT` | `0` | `1` | **file removed** | — |
| `OCTOPUS_DISABLE_COLLISION` | `0` | `1` / `True`, `on` | **bits** / **none (silent, U21-15)** | — |
| `OCTOPUS_MOMENT_CAPACITY` | `100` | `1` / `0` | none / **files silently absent (U21-19)** | — |
| `OCTOPUS_CUDA_PIC_GATHER_SCATTER_THREADS` | inherit | `64` / `2048` | none / throw | **none** / throw (1:1024) |
| `OCTOPUS_CUDA_PIC_DEPOSITION_THREADS` | inherit | `64` / `2048` | none / throw | **none** / throw |
| `OCTOPUS_CUDA_PIC_KICK_THREADS` | inherit | `64` / `2048` | none / throw | **none** / throw |
| `OCTOPUS_CUDA_PIC_FIELD_THREADS` | inherit | `64` / `2048` | none / throw | **none** / throw |
| `OCTOPUS_CUDA_PIC_SPECTRAL_THREADS` | inherit | `64` / `2048` | none / throw | **none** / throw (also with `SOLVER=spectral`, where it is discarded — U21-18) |
| `OCTOPUS_CUDA_PIC_GREEN_THREADS` | inherit | `64` / `2048` | none / throw | **none** / throw |
| `OCTOPUS_CUDA_PIC_LUMINOSITY_THREADS` | inherit | `64` / `2048` | none / throw | **none** / throw |

The weak-strong harness's own four variables, measured separately
(`probe_final.txt`, `julia --threads=4`):

| Variable | Default | Non-default tested | Effect |
|---|---|---|---|
| `OCTOPUS_TURNS` | `2` | `3` / `abc` | **bits** / throw |
| `OCTOPUS_N_MACRO` | `10000` | `5000` / `0`, `-5` | **bits** / throw (named) |
| `OCTOPUS_USE_GPU` | `0` | `1` | **bits** (CPU↔CUDA agree to 1-2 ulp) |
| `OCTOPUS_USE_GPU` | `0` | `true`, `yes` | **none — silent CPU (U21-16)** |
| `OCTOPUS_CUDA_DEVICE` | unset | `0` (with `USE_GPU=1`) / `99` | selects device / throw |
| `OCTOPUS_CUDA_DEVICE` | unset | `0` **without** `USE_GPU` | none (branch not taken — correct) |

Reading of the "none" rows: the seven per-kernel `*_THREADS` overrides are
*launch-geometry* knobs and are not expected to move output bits; their
reachability is proved instead by the fact that an out-of-range value is rejected
by `CUDAPICLaunchConfig` (1:1024), and they do reach the solver through
`backend_configurations` — except for the two solvers of U21-18. The three
*policy-level* knobs (`OCTOPUS_CPU_THREADS`, `OCTOPUS_CUDA_THREADS`,
`OCTOPUS_CUDA_BLOCKS`) are a different case: U21-17 shows by direct inspection of
the resolved policy that they never reach tracking at all. `OCTOPUS_CUDA_NVTX`
legitimately changes nothing observable without a profiler attached.

Reverse direction (invalid values rejected vs silently accepted):
* **Rejected with a named error:** `OCTOPUS_SOLVER`, `OCTOPUS_PIC_GREEN_CACHE`,
  `OCTOPUS_PIC_BATCH_MODE`, `OCTOPUS_SPECTRAL_FIELD_PRECISION`,
  `OCTOPUS_PIC_LUMINOSITY_DEPOSIT_METHOD`, `OCTOPUS_PIC_LUMINOSITY_GRID`,
  `OCTOPUS_PIC_LUMINOSITY_EVERY`, `OCTOPUS_CPU_THREADS`, `OCTOPUS_N_MACRO`,
  the seven `OCTOPUS_CUDA_PIC_*_THREADS`. Non-numeric values die with Julia's
  `ArgumentError: invalid base 10 digit`.
* **Rejected with an unhelpful error:** `OCTOPUS_SPECTRAL_GRID=64`,
  `OCTOPUS_GPIC_GRID=32` (`BoundsError: attempt to access 1-element
  Vector{Int64} at index [2]`, U21-21). `OCTOPUS_CUDA_DEVICE=99` gives
  `CUDA error: invalid device ordinal (code 101, ERROR_INVALID_DEVICE)` — clear
  enough, though it does not name the variable.
* **Silently accepted:** every mistyped boolean (U21-15, U21-16),
  `OCTOPUS_CUDA_THREADS=2048` and `OCTOPUS_CUDA_BLOCKS=7` (U21-17),
  `OCTOPUS_MOMENT_CAPACITY=0` (U21-19), negative beam energies (U21-22).

---

# Hypothesis (d) — repository writes

Answered in LEAD U21-27. Summary: `<repo>/test/result/{weak_strong.lum,
weak_strong_moments.h5, pic_hcc.lum, pic_hcc.ele.h5, pic_hcc.pro.h5}` plus an
optional `OCTOPUS_TURN_TIMING_PATH` file; fixed names, no `OCTOPUS_*` override;
`test/result/` is gitignored but a relative timing path outside `result/` is not.
Concurrent runs silently clobber rather than erroring — the prior unit's HDF5
failure mode was **not** reproduced.

---

# Clean list (verified, with the evidence)

1. **The gate invocation is exact** (hypothesis a.i). `diff` of
   `test/nightly_suite.sh:51-52` against `.github/workflows/ci.yml`'s test step:
   identical modulo the julia binary path.
2. **Measured Lesson 9's literal trap is absent.** `exit "$CODE"` at line 71
   propagates the code past the `ls | grep | tail | xargs` pipeline; measured to
   return 1, 127 and 137 from the corresponding stubs.
3. **The happy paths of the nightly gate work**: FAIL row on exit 1, PASS row on
   exit 0, header row created on first run, `latest.log` symlink correct, 14-log
   rotation arithmetic correct (`tail -n +15` keeps 14), stale lock reclaimed after
   24 h, `git describe --always --dirty` correctly marked the tree `-dirty` while
   another agent had uncommitted changes and dropped the marker when it did not.
4. **`status.tsv` is not corrupted** by concurrency or interruption; the row is one
   atomic small append inside the lock.
5. **Shebang/mode**: `#!/bin/bash`, POSIX-compatible body, `100755` in git.
6. **Both harness↔example pairs are bit-identical at defaults** — see hypothesis
   (b) table. Byte-identical script copies, `OCTOPUS_*` fully cleared, identical
   `rms` vectors to the last digit and `cmp`-clean `.lum` files for both pairs.
7. **Cross-citations are present and correct in both directions** for both pairs:
   `test/examples/weak_strong_tracking.jl:6-9` ↔ `examples/weak_strong_tracking.jl:12-14`;
   `test/examples/strong_strong_tracking.jl:4-9` ↔ `examples/strong_strong_tracking.jl:11-14`.
8. **The documented output locations are true**: the harness headers claim
   `test/result/` and the clean examples claim repo-root `result/`; both verified by
   running byte-identical copies and listing what appeared.
9. **45 of the 49 strong-strong variables and all 4 weak-strong variables are
   effective**, in the sense of changing output bits, output files, or diagnostic
   output on the backend they apply to. The exceptions are the three policy-level
   knobs of U21-17 (`OCTOPUS_CPU_THREADS`, `OCTOPUS_CUDA_THREADS`,
   `OCTOPUS_CUDA_BLOCKS`) and `OCTOPUS_CUDA_NVTX`, which by its nature produces
   nothing observable without a profiler attached.
10. **Solver selection is the one variable with a whitelist and it works**
    (`OCTOPUS_SOLVER=bogus` → `OCTOPUS_SOLVER must be one of pic, spectral,
    gaussian, gaussian_pic; got "bogus"`), and the three alternative solvers all run
    to completion and change results on both CPU and CUDA.
11. **The `.lum` files agree bitwise between the compacted and indexed CUDA
    wavefront paths** (`OCTOPUS_CUDA_PIC_INDEXED_WAVEFRONT=0` vs `1`:
    `lum=d6a591dbfcb16e2a` both) — a positive parity result the harness's A/B
    toggle exists to produce.
12. **The library's own inactive-option tripwire fires from these harnesses**:
    setting a CUDA-only solver option on CPU storage produced
    `Warning: non-default CUDA-only solver options are inactive on CPU storage;
    options = [:cuda_async]` (`interface.jl:2091`).
13. **`OCTOPUS_CUDA_PIC_TIMING_DETAIL=1` really does disable async field solves**,
    exactly as header lines 128-129 claim: its CUDA `.lum` equals the
    `CUDA_PIC_ASYNC=0` `.lum` (`3c3d0fa188872570`) and differs from the baseline.
14. **CPU and CUDA agree to 1-2 ulp in the weak-strong harness.** With every other
    variable unset, `OCTOPUS_USE_GPU=1` gives
    `rms = [9.570787996269571e-5, 1.1797688746010156e-4, 8.64206926115751e-6,
    1.1634985550187559e-4, 6.013617230833779e-2, 6.584986899628289e-4]` against the
    CPU `[…010158, …157512e-6, …187557, …]` — differences in the last one or two
    digits only.
15. **`OCTOPUS_MOMENT_CAPACITY` is a pure buffering parameter for every value ≥ 1.**
    Capacity 1 and capacity 100 produced identical moment-dataset hashes
    (`pic_hcc.ele.h5=6041e7c878225d37`, `pic_hcc.pro.h5=09b94891698b56ea`); only 0
    is broken (U21-19).
16. **The moment `.h5` *data* is deterministic** once the wall-clock `elapsed_time`
    dataset is excluded: across nine strong-strong runs in one session
    (`probe_final.txt`), the dataset signature is stable at
    `6041e7c878225d37`/`09b94891698b56ea` for every configuration expected to be a
    no-op. It is only the file bytes that are irreproducible (U21-28).
17. **`OCTOPUS_DISABLE_MOMENTS=1` reports honestly** — the summary prints
    `electron moments = disabled` / `proton moments = disabled`, which is exactly
    the behaviour `OCTOPUS_MOMENT_CAPACITY=0` fails to provide (U21-19); the two
    cases side by side are what makes U21-19 checkable.

---

# Unchecked, and why

* **The real nightly suite was never run** (`Pkg.test`), and
  `~/.octopus_nightly/status.tsv` was never touched — both forbidden by the brief.
  So the 151/135 testset numbers are derived from `runtests.jl`'s structure plus a
  measured demonstration of `grep -c '^Test Summary'` semantics, not from a live
  nightly row.
* **`shellcheck` is not installed** on this box, so no shell linter was run against
  `nightly_suite.sh`; all shell findings come from reading plus the 13 executed
  scenarios.
* **U21-6 (stale-lock race) is argued, not measured** — it needs two launches inside
  the same second against a >24 h-old lock.
* **No timing benchmarks were taken.** U21-17 is established by inspecting the
  resolved policy object rather than by wall-clock A/B, because the box was running
  2-3 concurrent Julia processes throughout and 200-macroparticle runs are
  dominated by fixed costs. The two timings quoted anywhere in this report (per-case
  seconds in the matrices) are for shape only, not for comparison.
* **Seams noted and stopped at, per protocol**: `MomentObserver`'s `elapsed_time`
  dataset and capacity-0 behaviour (`src/analysis/BeamObservers.jl`);
  `CUDALaunchConfig`'s missing upper bound (`src/policies/Policies.jl:146-163`)
  against `CUDAPICLaunchConfig`'s 1:1024 check; whether `StrongStrongTask`/
  `TrackingTask` *should* receive the caller's policy
  (`src/tasks/strongstrong/interface.jl:2222`, `src/tasks/Tasks.jl:83-85`); and the
  bitwise difference between cached and uncached slice-pair Green functions
  (`OCTOPUS_PIC_GREEN_CACHE=none` changes the CUDA `.lum`), which was observed but
  not quantified.
* **`examples/` files were read only for comparison**, not audited — they are U18's
  region.

# Probe artifacts (session scratch, `<scratch>/audit/`)

`effectiveness_cpu.jl` + `.txt` (76 cases), `effectiveness_gpu.jl` + `.txt` (39
cases), `probe_final.jl` + `.txt` (23 cases), `policy_probe.jl` (the U21-17
measurement), `h5probe.jl`,
`fakehome_*/` (10 nightly scenarios, each with its own `status.tsv` and log),
`clone/`, `clone_gpu/`, `clone2/`, `clone_conc/` (byte-identical script copies,
`cmp`-verified), `ws_example.out`, `ws_harness.out`, `ss_example.out`,
`ss_harness.out`, `conc_{A,B}.out`, `conc2_{A,B}.out`.
