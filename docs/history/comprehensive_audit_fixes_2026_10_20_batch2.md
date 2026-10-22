# Comprehensive-audit fix batch 2 (2026-10-20): the instrument rows

**Status:** complete 2026-10-21: four units merged, the two-arm full gate green
with CUDA active on the integrated tree 8763e8b (section 4, the second attempt; the
first was red at the batch's own new testset and is recorded there); the push was
authorized by the owner in advance (2026-10-20, "Push after gate green then move on
next step"); the push and its CI run are recorded by an addendum in the next
batch's commit, together with batch 1's.

Batch 2 of the 2026-10-18 comprehensive audit's fix campaign
([`comprehensive_audit_2026_10_18.md`](comprehensive_audit_2026_10_18.md); batch 1
is [`comprehensive_audit_fixes_2026_10_19.md`](comprehensive_audit_fixes_2026_10_19.md)),
on the owner's word of 2026-10-20 ("Go ahead Batch 2, 3, 4 one by one"). The rows
whose subject is the instruments -- contracts, suite checks, validators, validation
scripts and harnesses that could not fail, skipped silently or asserted what nobody
measured -- taken before the runtime rows because every later fix is verified by
them. Four units A to D, each a sub-agent proposing one commit on its own branch
from `main` at b9c1253 under a common brief whose first rule was that the proof of
an instrument is that it can fail: every repaired check shown RED under an injected
regression and GREEN on the real tree. The integrator read every diff, re-ran every
unit's regression testsets RED on the integration tree before the merge and GREEN
after it with the unit's neighbours, resolved the merges, and ran the pre-gate
checks and the gate. Unit reports, probes and the integrator's logs:
`result/fix_batch2_2026_10_20/{plan,units,probes,verify}/` (git-ignored scratch; the
numbers are quoted here; `verify/INTEGRATION.md` is the red/green table).

## 1 Owner decisions (2026-10-20)

1. **Order.** Batches 2 (instruments), 3 (runtime rows) and 4 (documentation and
   the Minor pointer) one by one; this record is batch 2.
2. **Method.** Sub-agents propose, the integrator verifies, as in batch 1; push only
   on the owner's word after the gate.

## 2 Units and what landed

### Unit A: contracts that cannot fail or skip where CI runs (F-10, F-107, F-108, F-139, F-140, F-46 to F-55)

`fix2-contracts`, 4b7ce42, 8 files (+754/-168). Every contract of the row was shown
passing under an injected regression on the unfixed tree and failing by name on the
fixed one (`probes/A/baseline_*.log`, `fixed_*.log`), green on the real tree. Landed:
the effectiveness contracts use override and fallback values that DIFFER
(`PublicConfigurationEffectivenessContract` gains `cuda_pic_threads = 64` against
`cuda_threads = 128`, refuses equal values, and observes the fallback run;
`_ANALYSIS_CONTRACT_LONGITUDINAL_INDEX` is 1, a betatron pair, against the heuristic's
2, and the observable reads the selected mode and the moved `eta` off the result,
failing when the alternative is the heuristic's own choice; F-10, F-140); the twelve
false exemptions of the element-parameter effectiveness contract retired (checked 530
to 542 alone, 549 with unit C's seven conventions; F-107); the stale-exemption
tripwire runs before the CUDA early return (`:failed` under
`CUDA_VISIBLE_DEVICES=""`; F-108); the identity contract's F6a diversion is a named
failure (20 findings where the metric alone counted; F-139); the PIC backend
contract derives its pair expectation `nslices^2 * turns` from its configuration
instead of reading it off the CPU output (F-46); a one-thread run is `:skipped`
(F-47); backend fields take `Type{<:AbstractExecutionBackend}` (F-48); the contract's
base beams are built before anything auto-assigns a stream (zero registry warnings
in a fresh process; F-49); the symplecticity tolerances re-frozen at about 100x the
residuals measured in both CPU arms, so the 1e-9 kernel defect of the audit fails
(F-51); the output-boundary check counts the pairs it judged and fails on zero
(F-52); the MPI contract's forwarded fields derive from `fieldnames` (F-53); two
cross-file seams closed, `_preflight_solver_kbb` refusing a derived-strength beam
BEFORE any line mutates it and `_float_params` refusing a missing parameter by name
(F-54, F-55). The `green_type` gap batch 1 left open is closed: both PIC contracts
gained the field, and the `:standard` route under the default cache is contracted
at the controls' class (measured `global_rel_error` 7.0e-16, per-pair luminosity
1.1e-14, identical cache histories). The allowances `1e-10` are derived in the
docstrings from the measured floors (6.5e-16 Gaussian, 2.3e-15 PIC; the PIC
deposit's run-to-run spread 1.7e-11 is the class they stay above; F-50). Red on the
integration tree before the merge (A_red.log, with unit C in): "Contract coverage
guards ..." errored on the missing derived-field API, "Stage 6: the identity contract
passes ..." 169/3, "4b-B contract plumbing ..." 21/1, "Element parameter
effectiveness" 36/13 (537 against 542); green after it (A_green.log: those four plus
"Solver option effectiveness" with CUDA, "4b-B registry ...", "Run artifact receipts
and slots ...", "Physics contracts", unit C's three, "Architecture integrity";
A_green_ext.log: "Knob control" and the unconverged-iterate route). The one merge
conflict, the effectiveness ratchet (C's 537 against A's 542), was resolved at the
value measured on the merged tree, 549 (unperturbable 34, rejected 23). Not verified
by the unit: the MPI launcher legs (the forwarding is proven by the in-process
round trip; the gate's seam testset runs them), the `-C haswell` arm beyond the
symplecticity residuals.

### Unit B: suite checks that cannot fail or skip silently (F-156, F-210 to F-221)

`fix2-test-suite`, dca1330, `test/runtests.jl` +884/-289 and eight lines of
`docs/theory/bpm_measurement_model.md`; no `src/` change. Thirteen findings addressed
in 37 testsets, each repaired check shown RED under an injected regression and GREEN
on the real tree (112 runner invocations, 40 green and 71 red; `probes/B/digest.txt`
and `logs/`): tautologies replaced by assertions on the measured quantity (the
explicit-partition frame availability, the spectral solve/eval split against an
independent reference, the bend's cancellation-free map against the audit's moved
crossover, the `_cross_backend_violations` checker control), circular pins re-derived
from independent references with stated tolerances, `if` gates given visible skips
(`@test_skip` naming the unrun half: the CPU-only path of the cross-backend classes,
the one-precision rule, the solver-option and public-configuration contracts, the
script-mode ForwardDiff check that used to record `@test true`), hand lists derived
with tripwires (the Core.Box allowlist's stale entry and blinded detector, the
configuration-status vocabulary against its producers, the octupole class pin
against the registry), F-220's harness tolerances re-derived from the measurement
(PIC luminosity 0.12, PIC size 0.01, spectral 0.05 and 0.05, where 0.60 and 0.80
had stood and a PIC luminosity wrong by 1.5x passed; the 1.5x control is asserted),
and F-215: `spectral_cuda.jl`'s eleven kernel rows joined the launch-site tripwire
with the fixed-count token rule (green under `--check-bounds=yes` with CUDA; the two
interp-scatter kick kernels' ceilings 1024 and 896 against their fixed 256). Two
`@test_broken` markers hold the expectation that the inactive `misalign_convention`
values are refused (U31-6: a source change, priced), and flip to "Unexpected Pass"
the day the source refuses them. Four defects in the unit's own first drafts were
caught by the red/green discipline before the commit (its report, section 5). The
integrator's re-run of the unit's green batches and five of its red injections on
the merged tree: `verify/B_digest.txt` (section 3). Priced, not fixed: the
8192/16384 cancellation-class bounds (U32-3), the kernel-side explicit `fma` for two
contraction-dependent pins (U37-7), the six CUDA route hand lists (U37-10), the
walk-set derivation (U31-4, F-69), the RNG save/restore (U33-5). Not verified by the
unit: the lane's order couplings across the 37 changed testsets (the RNG-registry
warnings), which the gate sees; the MPI launcher testset (the `armloop` change
verified by a fixture probe, 0 mismatches).

### Unit C: validators that skip (F-168 to F-175)

`fix2-validators`, 754becb, 11 files. Reproduced on b9c1253 by injection, each
MISSED there and CAUGHT on the fix (`probes/C/unfixed_validators.log`,
`fixed_validators.log`): `validate_element_metadata` compared only the defaults the
example happened to set, 77 of 608 (a `drift.h` redeclared from 0 to 6 validated
clean while the compiled map moved); it held no runtime map to its method list, no
Symbol default to its alternatives, no free text to non-empty, no kind's placement
entries to the one table (13 kinds had hand-copied the entries and 79 copies had
drifted: every unit lost, seven kinds' `misalign_convention` without the
alternatives that make it perturbable); the `:line` answered `Symplectic6DMap()` to
`default_method` while its compile refused that request; `validate_configuration_metadata`
compared the CPU and legacy GPU defaults with literals; `_mp_resolve_shard` took
its verdict on this rank's count alone, so four ranks holding (256, 256, 255, 257)
split -- ranks 0 and 1 proceeded into the next collective while 2 and 3 threw, the
deadlock shape, measured under `mpiexec`; `_launcher_rank_count` read the per-node
`MPI_LOCALNRANKS` ahead of three global counts. Landed: every declared default is
compared on two bases (the example, or the example's required parameters alone
where the constructor refuses the default beside a folded twin; 607 of 607 checked,
11 on the required base, returned as counts so a skip is visible), runtime maps
against method lists, discrete defaults within their alternatives, free text
non-empty, every kind's placement entries held to `_PLACEMENT_PARAMS` through the
new `_placement_param(key; meaning)` (the seven conventions became perturbable:
effectiveness 537 checked, 34 unperturbable), a method-less kind refused by name;
the policy validator compares the CPU, CUDA and legacy GPU defaults with constructed
policies; `_mp_shard_verdict` on the all-summed counts gives every rank the same
verdict (the integrator's four-rank run on the merged tree: every rank throws naming
ranks 2 and 3, launcher exit 0; `verify/C_shard_fixint.log`); the global launcher
counts come first; the `_mp_chunk_fold` docstring names its real arity. The
snapshot is byte-identical; `element_help` renders for all 31 kinds. Red on the
integration tree before the merge (C_red.log: the new testset 1 pass / 4 errors,
"The rank shard is a whole number of reduction chunks" 220/2/4, "The multi-process
policy rejects what it cannot honour" 14/4, "Element parameter effectiveness" 35/2),
green after it with nine neighbours (C_green.log). Cost: the first
`validate_element_metadata()` call in a process now takes about 72 s of JIT, once.
Not verified by the unit: two pre-existing child-process validator controls fail only
under the stage runner (suite-helper and `@__DIR__` reasons, diagnosed, unchanged).

### Unit D: validation scripts, harnesses and examples; the CUDA class fix (F-203 to F-207, F-224 to F-229, F-237 to F-239)

`fix2-scripts-harnesses`, 21d2cc2, 39 files (+1927/-600; scripts, tests and docs
only, no `src/` change). Landed on the fourteen findings: every script and harness
of the row asserts what the run recorded -- header lists held to the body at load
(the batch-1 pattern of `benchmark_strong_strong_pic.jl`), unread variables and keys
refused by name (`config.execution`, the switch-gated variables; the crab harness
the template), distinct output tags per arm, dropped-particle counts, gated metrics
where a verdict was print-only, the PIC benchmark's verdict compared like with like
(each row against the CPU row of the same `green_cache`, exit 1 on inconsistency;
batch 1's `solver_default` 1.76e-4 against the `:none` reference was the cache's
discretisation, as flagged); three more found and fixed in the unit's own neighbour
audit (`profiling/crab_cavity_noise_backends.jl` exited 0 on a failed arm, the
PIC-cache contract refuses one turn, two floor rules re-derived from measured
values). The class fix batch 1 left open: the full lane's last testset,
"CUDA-requiring validation scripts run in the gate's CUDA arm", DERIVES every
CUDA-capable script of `validation/` and `profiling/` from four code markers, requires
each to carry one machine-readable `GATE-CUDA-ARM:` header line (the reduced size
as environment or arguments, the verdict token, the outputs; or a named exclusion,
today the two CUPTI profiler wrappers), runs each in its own process with the
gate's own flags and thread count when the process has a device, four at a time
with a 900 s watchdog, asserting exit 0, the token and the outputs, and records a
visible skip naming the unrun scripts on a CPU-only process; both directions and
the README section's coverage are tripwires, each shown red by name on scratch
scripts. On the integration tree the arm ran 18 scripts in 370 s (their own times
sum to 1322 s), every exit 0 (D_green.log), inside the ten-minute budget.
`validation/README.md` carries the arm's section and table, `docs/design/testing_lanes.md`
and the examples guide the rule. Red before the merge (D_red.log: 121 pass / 21
fail / 1 error, the CUDA-capable scripts carrying no header line), green after it
with the retired-spelling tripwire, "Architecture integrity" and the high-energy
limit testset. Not verified by the unit: the MPI harness arms; anything at
production size; the budget on another host.

## 3 Integration

Merge order into `fix2-batch-int` (from b9c1253): C (f02a5cd), A (c6606c0, the
ratchet conflict), D (94b7792, clean), B (9e1dbed, one conflict at the public-configuration contract's verdict: B's CUDA/no-CUDA status split kept first, A's new metrics after it). Every unit's
regression testsets ran RED on the integration tree before its merge and GREEN after
it with its neighbours; the table with every count is
`result/fix_batch2_2026_10_20/verify/INTEGRATION.md`. Runner artefacts (suite-level
helpers, `ForwardDiff` and `Symbolics` in the test environment) were supplied by the
units' preambles; the gate runs the suite as one process.

Conflicts and what the integration found:

- **A on C** (`test/runtests.jl`, the effectiveness ratchet): C had raised the
  floor to 537 (the seven conventions made perturbable), A to 542 (the twelve
  exemptions retired). Neither side was the right value: the merged tree measures
  549 (unperturbable 34, rejected 23), because the two sets of newly checked
  parameters are disjoint; the ratchet was set to the measured sum
  (`verify/A_effectiveness_merged.log`).
- **B on A** (the public-configuration contract's verdict): A asserted the new
  metrics, B the CUDA/no-CUDA status split with a visible skip; both kept, B's
  split first.
- **D** merged clean (its testset is the file's last block by design).
- **An order coupling the integration exposed** (c81ff32): "Dropped PIC charge
  reaches a reader" asserts silence while its two beams claimed `rng_id = 1` and
  `2` explicitly, so its verdict depended on whether an earlier block in the same
  process had auto-assigned those ids to an observer; after "BPM reads a device
  number, not the truth" it went red (the registry's held-id warning), alone it
  was green, and in the full suite the earlier explicit claims hid it. The fixture
  now takes `_unheld_rng_id` ids, the suite's convention, and the coupled order is
  green. No `src/` change.
- **Runner artefacts, not defects:** "The harnesses refuse the retired OCTOPUS_MP
  spelling" reads `@__DIR__`, which is not `test/` for a cut block (green with the
  unit's root substitution and in the suite); the suite-level helpers and the
  `ForwardDiff`/`Symbolics` test dependencies were supplied by the units'
  preambles and scratch environments.

The batch's neighbour audit: each unit's own (section 5 of its report), the
integrator's green runs of every unit's testsets with its neighbours after each
merge (`verify/*_green.log`, `verify/B_logs/`), the repeated unit-B batches on the
merged tree, and the pre-gate checks of section 4.

## 4 Pre-gate checks and the gate

On c81ff32, before the gate: the extracted source sweeps green
(`sweeps_wt_fixbatch2_int.log`, on 9e1dbed; the one commit after it changes a test
fixture), `validate_element_metadata()` passed with 607 of 607 defaults checked,
`validate_configuration_metadata()` true, the registry snapshot byte-identical
(`verify/final_checks_9e1dbed.log`).

**The first two-arm gate (c81ff32, 2026-10-20 11:55 to 14:12) was RED in both
arms, at one testset: the batch's own CUDA arm.** Every other testset passed (364
summaries per arm, no skip, no signal). Four of the eighteen scripts failed in their
subprocess with `Package Statistics not found in current path`
(`profiling/crab_cavity_noise_backends.jl`, `validation/soft_gaussian_pic_comparison.jl`,
`validation/strong_strong_spectral_comparison.jl`) or `Package DelimitedFiles not
found` (`validation/pic_option_consistency.jl`): `Pkg.test` runs the test process
with `JULIA_LOAD_PATH = @:<test environment>` and no `@stdlib`, the subprocess
inherited that path with `--project=<root>`, and a standard library the project
does not depend on cannot be loaded there, where a plain shell's default path has
it -- which is why the unit's and the integrator's stage-runner runs (18 of 18,
exit 0) could not see it. The testset did what it was built for on its first gate.
Fix (integrator commit 8763e8b): the subprocess load path gets `@stdlib`
appended when absent, the project and the test environment staying first, and the
script runs from the repository root. Reproduced through the testset itself under an
emulated test load path (`@:<scratch env holding Test>`, `--check-bounds=yes`):
with the gate's testset text, RED (191 pass / 14 fail: five scripts, the four above plus `validation/lattice_cells.jl`, failing on `Printf`, `DelimitedFiles` or `Statistics`, the scratch environment being stricter than the test target's; `verify/cudaarm_emulated_red.log`); with the fix, GREEN (18 scripts exit 0, four at a time, the testset's verdict after 1251.8 s; `verify/cudaarm_emulated_green.log`). The gate's log tag `fixbatch2` had been used by batch 1's
second attempt and was overwritten (the logs are git-ignored scratch; batch 1's
numbers are in its record; `result/gates/turnmod/LOG_TAGS.md`); the second attempt
is tagged `b2a2`.

**The second two-arm gate (8763e8b, tag `b2a2`) ran on 2026-10-21 under an NFS
client saturated by another user's jobs (section 6, last lesson), which stretched
it without touching a verdict.** Native arm (CUDA active) 09:55 to 14:01, 4 h 05 min,
exit 0: 364 testsets, every one green, Broken 2 (unit B's two `@test_broken` markers
in "Misalignment maps", the expectation that the inactive `misalign_convention`
values are refused), no skip, no signal, no core. The CUDA-arm testset: 205 of 205,
all 18 scripts exit 0 (1271.5 s of wall for the scripts, four at a time, their own
times summing to 4727.0 s; the first attempt had 194 of 205 with 11 failures). The
per-testset time column summed to 13,206 s against the first attempt's 4,005 s on
the same 364 names (3.3x), the subprocess-heavy testsets hit hardest (the examples
2651 s against 674 s, the MPI seam 1669 s against 577 s, the CUDA arm 1274 s
against 342 s). AVX2 arm
(`OPENBLAS_CORETYPE=Haswell`, `julia -C haswell`, CUDA active) 14:01 to 17:56, 3 h 55 min,
exit 0: 364 testsets, every one green, the same two Broken, no skip, no signal, no
core; the CUDA-arm testset 205 of 205 (18 scripts exit 0, 1243.2 s of wall for the
scripts, their own times summing to 4621.3 s); the time column 12,709 s, 3.2x the
first attempt's native arm. The F-244 segfault did not occur in either arm of either
attempt. Logs: `result/gates/turnmod/full_gate_{native,avx2}_pty_b2a2.log`
(git-ignored scratch; the numbers are here).

This record and the ledger changes of section 5 are a markdown-only commit on
top of the gated tree; the fast lane on the final tree is their gate:
GREEN (`result/gates/turnmod/fast_lane_wt_b2a2_final.log`, 2026-10-21 17:59:34 to
19:16:58, exit 0, 348 testset summaries, 17 `LANE SKIP` lines, no unindexed
document), run on this commit's tree before this sentence was
filled in.

## 5 Ledger

Five rows retired to `todo_ledger_archive.md` ("Rows retired by the
comprehensive-audit fix batch 2, closed 2026-10-21") with their closing
measurements: the contracts, the suite checks, the validators, the validation
scripts, the harnesses and examples. The pointer row carries what the batch left
for the owner. Six lessons in `experiences.md` (section 6). This record is indexed in `docs/README.md`.

## 6 Lessons recorded

- An instrument is finished when it has been shown failing: inject the regression
  the check exists to catch, quote the red run and the green one (the batch's
  organizing rule; 112 runner invocations for the suite alone, four of the units'
  own first drafts caught by it).
- A verdict taken on one rank's data is a deadlock in waiting: a collective
  decision is taken on the all-summed data every rank holds, so every rank throws
  or none does (unit C's shard verdict).
- A script that only a GPU can run is run by nobody until the gate runs it: derive
  the list from the scripts' own refusals, declare the reduced size in the script,
  run them in the gate's CUDA arm, skip visibly elsewhere (unit D).
- Two units that raise one ratchet add; resolve a numeric merge conflict by
  measuring on the merged tree, never by choosing a side (A and C: 549).
- A subprocess under `Pkg.test` does not have the shell's load path: a script
  that runs in a terminal can fail in the gate on a standard library the project
  does not depend on; give the subprocess its path explicitly (the CUDA arm's
  first gate).
- A gate's wall time is not the suite's time: under a shared NFS client saturated
  by another user's writes the same tree ran 3.3x slower with every testset green;
  a slow gate is diagnosed from the mount statistics (`/proc/self/mountstats`), not
  relaunched, and nothing else is launched on the mount meanwhile (the second gate).

## 7 Not verified

Collected from the units (their sections 7) and the integrator: the MPI launcher
legs of the forwarded contract fields and the `armloop` change (proven by in-process
round trips and a fixture probe; the gate's seam testset ran them at 1, 2 and 4
ranks), the production sizes of every validation script (the arm runs the reduced
sizes), the CUDA arm's budget on another host, the lane's order couplings beyond
the one the integration found (the gate as one process is the check), the
`-C haswell` arm beyond what the AVX2 gate arm itself measures, and the items the
units priced rather than fixed (the pointer row names them).

## Addendum 2026-10-22 (push and CI)

The batch was pushed as da40d39 on 2026-10-21 (eleven commits over b9c1253); CI run 467 completed green. Recorded by the fix batch 3 commit, as the status line above said.
