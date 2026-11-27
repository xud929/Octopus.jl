# Test Lanes: the Fast Checkpoint and the Full Gate

> **Status: implemented (2026-08-13); the suite split into files with
> `only=<file>` selection on 2026-11-27.** Mechanism in `test/runtests.jl`
> (the driver: the lane preamble, `only=`, the layout tripwire, the
> accounting banners) and the `_lane_gate` guards inside the files of
> `test/suite/`. This note records the measurements that shaped the lanes,
> the decision matrix for when the full gate is mandatory, the rules that
> keep a partial run honest, and (section 5) the split's state.

## 1. What exists

- **`lane=full`** (the default — plain `Pkg.test`, CI, the nightly script):
  every testset, unchanged. This is the finish line for every commit outside
  the derived markdown-only class of section 3, per the gate rule in
  `AGENTS.md` (Verification Matrix).
- **`lane=fast`** (`Pkg.test(test_args=["lane=fast"])`, with
  `julia_args=["--threads=4"]` as always): a development checkpoint that
  skips the sections registered with `_lane_gate` — the measured heavyweight
  tail — and keeps everything else, including the structural tripwires
  (architecture integrity, method-overwrite guard, metadata validators, the
  `Core.Box` sweep, knob round-trips) and the whole population of cheap pins
  where the audit history says regressions actually hide.

- **`only=<file>[,<file>]`** (`Pkg.test(test_args=["only=artifact_observers"])`,
  since 2026-11-27): `core.jl` -- the structural sweeps every run executes --
  plus the named files of `test/suite/`, in the driver's include order, the
  files not run named in a banner at the end; a checkpoint exactly as the
  fast lane is, and the two combine (`lane=fast` inside the selected files).
  `only=core` is the smoke run. What makes a selection trustworthy is the
  layout the driver's first testset enforces on every run: the directory is
  the include list, block titles and column-0 helper names are unique across
  the files, and no file reaches for a helper another file defines,
  `common.jl` excepted -- so a file runs under `only=` in the state the full
  lane gives it, but for what earlier files leave behind in the process (a
  registry claim, a result file), which only the full lane sees. The files,
  the parser they are read through (`test/suite_structure.jl`), the mover
  (`test/move_testsets.jl`) and the measurements are in
  [`../history/suite_split_2026_11_27.md`](../history/suite_split_2026_11_27.md).

An unknown lane name, an unknown file name or any other argument is an
**error**, never a silent fall-through to full: a typo must not produce a
vacuous verdict. A fast run prints one loud
`LANE SKIP` line per skipped section as it skips it, and ends with a banner
naming everything skipped and stating that the full gate is still owed. A
skipped check that vanishes silently is the F2 failure mode; the banner is
the countermeasure.

## 2. The measurements that shaped the split (2026-08-13)

Full-suite time distribution, GPU-active gate (184 testsets, testset time
summed 36.6 min) and CPU-only 4-thread run (170 testsets, 24.4 min): the top
13 sections consume ~26 min (GPU) / ~17 min (CPU) — dominated by "Every
example script runs against the current interface" (~6.5 min), "Solver option
effectiveness" (4.5 min GPU / 1.2 CPU), "script mode picks up the ForwardDiff
rules" (~4.5 min, a fresh-process compile), "Physics contracts" (~1.9 min) —
while the remaining ~170 testsets sum to ~11 min (GPU) / ~7 min (CPU). Fixed
`Pkg.test` overhead (spawn, precompile check, load) is ~4–5 min on top of
either. So:

- full gate: ~22–30 min wall depending on machine and CUDA;
- fast lane: **measured 9.5 min wall** on the GPU node at first landing
  (2026-08-13, 171 of 184 testsets) — roughly a third of the gate, while
  keeping >90% of the *testset population*.

The registered sections were the 13 measured heavyweights at first landing
(2026-08-13); the list lives in the `_lane_gate` call sites and nowhere else
(no second hand-copy; `grep -oh '_lane_gate("[^"]*"' test/suite/*.jl | sort -u`
lists them, 17 titles at 2026-10-22, the same 17 after the 2026-11-27 split).
Membership is a judgment renewed by measurement, not a property a tripwire
can check: when a new testset lands, the question "does it belong behind a
gate?" is part of its review, and this note's numbers are the precedent.

Added 2026-10-20 (fix batch 2 of the 2026-10-18 comprehensive audit), the
last section of the file: "CUDA-requiring validation scripts run in the gate's
CUDA arm". It runs every CUDA-capable script of `validation/` and `profiling/`
in a subprocess at the reduced size its own `GATE-CUDA-ARM:` header line
declares, asserting exit 0 and the script's verdict token, when the test
process has a device; on a CPU-only process (CI) it prints the scripts it did
not run and records a `@test_skip`. The list is derived from the scripts'
CUDA refusals and `OCTOPUS_REQUIRE_GPU_CONTRACT` reads, both directions
tripwired (`validation/README.md`, "The gate's CUDA arm"). It is full-lane
because it is the only place these scripts execute at all: CI has no GPU,
and three of them had been dead for two months (A-4, F-200, F-236). Its
measured cost on the GPU node is in the README's table (the owner's budget
rule: the gate may not grow by more than ten minutes); on CI it costs one
directory scan.

## 3. When the full gate is mandatory

The fast lane is a checkpoint **during** development. The full gate is the
bar **before any push** (owner decision 2026-09-04; it was before any commit
until then, and the change is priced in `../experiences.md`), and for the
following change classes no amount of fast-lane green substitutes — each row is paid for by a recorded incident:

| change class | minimum bar | the receipt |
|---|---|---|
| anything reachable from CUDA kernels (`*_cuda.jl`, fused device paths, throws in device code) | full gate **with CUDA active** | the dominant recorded failure class; CI has no GPU, so a local GPU run is the *only* CUDA gate |
| a CUDA-requiring script under `validation/` or `profiling/`, or a retirement whose blast radius reaches one | full gate **with CUDA active** | the CUDA arm section runs them; three scripts were dead for two months with every CPU gate green (2026-10-18 audit, A-4, F-200, F-236) |
| concurrency surfaces (worker closures, reductions, chunk grids, counter RNG) | full gate | the `Core.Box` class; thread-count invariance history (U5-1/2, U16-3) |
| acceptance/rejection semantics, contracts, tolerances, aperture/loss | full gate | blast-radius rule; F2 aborted ~4,660 test lines silently |
| symbol removal/rename or arity change | full gate, after a repo-wide grep | U3-2 capped 4 of 12 launches; U1-6 left 4 stale call sites in the sibling file |
| public config fields, solver/task options, observers, schedules | full gate | the "passes alone, fails in the suite" class (U3-2, U5-1); config-effectiveness contracts live in the heavy sections the fast lane skips |
| element tracking kernels, `compile_runtime`, coordinate conversions | full gate | physics contracts and backend-consistency checks are skipped by the fast lane |
| test infrastructure itself (gates, lanes, the driver, the layout of `test/suite/`) | full gate | F2 again: a broken gate is the worst defect, because it silences every other one |
| markdown-only, DERIVED: `git diff --name-only` lists only `.md` files and none of them is `docs/registry_snapshot.md` | fast lane on the final tree (owner decision 2026-09-03) | the classification is read from the diff, not claimed; the only docs checks the suite has -- the snapshot compare and the `AGENTS.md` source-map tripwire, both in "Architecture integrity" -- run in the fast lane, so the full gate added nothing but insurance against misclassification, and the derivation removes the misclassification |
| docs plus anything else (a `.jl` comment, `ci.yml`, the snapshot) | full gate (before the push, the bar stated above) | "it's only docs" is a claim; the derived row above is the check, and a diff outside it is not docs-only (the 2026-09-03 AGENTS.md restructure itself touched four `.jl` files and `ci.yml`) |

During the inner development loop, the probe workflow recorded in
`../guides/development_workflow.md` (script-mode `include("src/Octopus.jl")`
probes, targeted testset extraction run in package mode) remains the fastest
iteration path; the fast lane sits between probes and the gate.

## 4. Rules that keep a partial run honest

1. **A skip is loud, always** — per-section `LANE SKIP` lines plus the final
   banner. If the banner ever fails to appear on a fast run, that is a bug in
   the lane mechanism and outranks whatever the run was checking.
2. **The verdict is labeled.** "Tests passed" from a fast run means *the fast
   lane* passed. The banner says so; any human or agent report of a fast run
   must carry the lane name (the "the suite is green" claim is about which
   testsets actually ran — AGENTS.md Invariants).
3. **No lane accumulates authority.** Green fast runs during development do
   not reduce the finish-line requirement; the full gate runs on the final
   tree before every push (owner decision 2026-09-04) outside the derived
   markdown-only class of section 3, and that class still runs the fast lane
   on the final tree.
4. **Unknown lanes error.** `lane=fats` must die, not silently run full; so
   must an unknown `only=` name and any other argument.
5. **A selection names what it left out.** An `only=` run ends with the
   suite files it did not run, in the lane banner's form; a selection whose
   banner is missing is the same bug as a missing lane banner, and a report
   of such a run carries the file names it ran.

## 5. Built on 2026-11-27, and what remains

The three items this section listed as "deliberately not built (yet)" since
2026-08-13 -- `only=<section>` selection, a smoke lane, and splitting
`runtests.jl` into files -- landed together on 2026-11-27, in the order the
last of them predicted: the split made lane membership file membership and
`only=` fell out of it. The record is
[`../history/suite_split_2026_11_27.md`](../history/suite_split_2026_11_27.md),
with the measurements that priced the decision: the gate at 100 minutes
(2026-11-27, CUDA active, 519 rows) against the 24.5 the per-push rule was
set on (2026-09-04), the fast lane at 41, the testset times summing to 98 of
the 100, and three subprocess-bound sections (the MPI seam, every example
script, the CUDA validation arm) holding 44 of them.

- **`only=<file>`** selects suite files; `core.jl` always runs, so `only=core`
  IS the smoke lane: the layout tripwire and the twelve structural sweeps,
  3 min 29 s wall on the GPU node at first landing, 2 min 09 s of it
  "Architecture integrity".
- **The split is staged.** `core.jl` and the first area file
  (`artifact_observers.jl`, 23 testsets with their 12 fixtures) are peeled;
  `legacy.jl` holds the other 451 testsets and 17 lane-gated blocks in the
  single file's order. Each further peel moves one area by title through
  `test/move_testsets.jl`, with its helpers, under the layout tripwire, as
  its own gated push; the open row of `../todo.md` lists the areas with the
  weights a keyword pass over the gate log gave them. Hidden order
  dependence between regrouped testsets is what each peel's full gate
  measures; the split's own reordering found one (the U12-8 control's
  class-form leak, section 2 of the record), the first peel none.
- **Not built, still:** running the three subprocess-bound sections beside
  the in-process suite, the one lever left on the gate's own length. The
  split shortens every checkpoint before the gate and nothing after it.
