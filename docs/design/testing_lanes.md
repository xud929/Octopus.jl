# Test Lanes: the Fast Checkpoint and the Full Gate

> **Status: implemented (2026-08-13).** Mechanism in `test/runtests.jl` (the
> lane preamble, the `_lane_gate` guards, the accounting banner). This note
> records the measurements that shaped it, the decision matrix for when the
> full gate is mandatory, and the rules that keep a partial run honest.

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

An unknown lane name is an **error**, never a silent fall-through to full: a
typo must not produce a vacuous verdict. A fast run prints one loud
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

The registered sections are exactly the 13 measured heavyweights; the list
lives in the `_lane_gate` call sites and nowhere else (no second hand-copy).
Membership is a judgment renewed by measurement, not a property a tripwire
can check: when a new testset lands, the question "does it belong behind a
gate?" is part of its review, and this note's numbers are the precedent.

## 3. When the full gate is mandatory

The fast lane is a checkpoint **during** development. The full gate is the
bar **before any commit**, and for the following change classes no amount of
fast-lane green substitutes — each row is paid for by a recorded incident:

| change class | minimum bar | the receipt |
|---|---|---|
| anything reachable from CUDA kernels (`*_cuda.jl`, fused device paths, throws in device code) | full gate **with CUDA active** | the dominant recorded failure class; CI has no GPU, so a local GPU run is the *only* CUDA gate |
| concurrency surfaces (worker closures, reductions, chunk grids, counter RNG) | full gate | the `Core.Box` class; thread-count invariance history (U5-1/2, U16-3) |
| acceptance/rejection semantics, contracts, tolerances, aperture/loss | full gate | blast-radius rule; F2 aborted ~4,660 test lines silently |
| symbol removal/rename or arity change | full gate, after a repo-wide grep | U3-2 capped 4 of 12 launches; U1-6 left 4 stale call sites in the sibling file |
| public config fields, solver/task options, observers, schedules | full gate | the "passes alone, fails in the suite" class (U3-2, U5-1); config-effectiveness contracts live in the heavy sections the fast lane skips |
| element tracking kernels, `compile_runtime`, coordinate conversions | full gate | physics contracts and backend-consistency checks are skipped by the fast lane |
| test infrastructure itself (gates, lanes, `runtests.jl` structure) | full gate | F2 again: a broken gate is the worst defect, because it silences every other one |
| markdown-only, DERIVED: `git diff --name-only` lists only `.md` files and none of them is `docs/registry_snapshot.md` | fast lane on the final tree (owner decision 2026-09-03) | the classification is read from the diff, not claimed; the only docs checks the suite has -- the snapshot compare and the `AGENTS.md` source-map tripwire, both in "Architecture integrity" -- run in the fast lane, so the full gate added nothing but insurance against misclassification, and the derivation removes the misclassification |
| docs plus anything else (a `.jl` comment, `ci.yml`, the snapshot) | full gate before commit | "it's only docs" is a claim; the derived row above is the check, and a diff outside it is not docs-only (the 2026-09-03 AGENTS.md restructure itself touched four `.jl` files and `ci.yml`) |

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
   tree before every commit outside the derived markdown-only class of
   section 3, and that class still runs the fast lane on the final tree.
4. **Unknown lanes error.** `lane=fats` must die, not silently run full.

## 5. Deliberately not built (yet)

- **`only=<section>` positive selection** — running one named section plus
  the structural tripwires. Worth building when `runtests.jl` is next
  reorganized; today the script-mode probe workflow covers targeted
  iteration, and wrapping all 184 testsets in named sections is a larger
  restructuring than the 13-guard mechanism justified.
- **A `smoke` lane** (validators + docs checks only, ~5 min) — blocked on the
  same reorganization: the structural checks are scattered through the file,
  so positive selection needs section membership everywhere.
- **Splitting `runtests.jl` into files** — the natural v2, at which point
  lane membership becomes file membership and the `only=` lane falls out.
