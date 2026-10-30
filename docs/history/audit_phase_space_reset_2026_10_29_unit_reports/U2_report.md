# Phase-space reset neighbour audit, reading unit U2

> Parent closure: the final CUDA-active gate passed on 2026-10-29; see the
> [campaign receipt](../audit_phase_space_reset_2026_10_29.md#final-gate-receipt-and-closure).
> Pending-gate statements below describe this unit's earlier handoff.

Date: 2026-10-29. Auditor: delegated agent `/root/reset_validation`.
Status: second source-review pass complete; no Julia reproduction or validation command was run by this reading unit. Parent-owned red/green evidence is recorded below with that provenance. The driving agent owns reproduction, adjudication, fixes, and final-tree gates. Source line references describe the working tree as read and may move with those fixes.

## Scope and provenance

The assignment was the new task-owned reset state and its integration with the trial-loss/artifact lifecycle: pre-admission refusal, reentrant refusal, capture ownership, clearing, plan reuse, continuation/replay, reference epochs, partial failures under MPI, and preserving ordinary permanent-loss behavior. The protocol was `docs/comprehensive_audit.md`, read in full before this campaign; its reading-unit rules govern this report. `docs/experiences.md` was also read in full before the earlier implementation phase.

This agent implemented `PhaseSpaceResetTrials.jl` and the reset-specific additions to `RunArtifact.jl` in the preceding authorized implementation phase. This neighbour pass therefore is independent of the root's task integration but is a self-review of those two helper regions. It made no repository edits. Scratch reproduction files and this report are its only audit writes.

### Direct reading coverage

| Region | Depth and comparison |
| --- | --- |
| `src/tasks/PhaseSpaceReset.jl` | Every line of the then-current 196-line file, including capture signatures, collective preflight, state/cached-plan ownership, clear, and copied public summary. |
| `src/tasks/Tasks.jl` | Every changed hunk, plus surrounding `execute!` admission/catch/output tail, `_execute_tracking_task!` admission/commit/turn/finalizer flow, `_runtime_entries`, `_ensure_loss_record!`, plan construction, `_global_loss_summary`, and artifact failure close. Ordinary success/failure loss branches and ordinary record allocation were compared to their reset branches. |
| `src/tasks/PhaseSpaceResetTrials.jl` | Every line of the then-current 277-line file. Compared CUDA scalar liveness reduction against ordinary loss summary, per-trial scratch clearing against cumulative ordinary losses, success collective folding against failure local output, and replacement writes against ordinary probe append semantics. |
| `src/tasks/RunArtifact.jl` | Every changed hunk. Read `_next_reset_reference_epoch`, `_ra_write_reset_trial!`, named group/read routing, and surrounding unchanged `_ra_bind_probe!`, `_ra_commit_probe!`, `_ra_truncate_probe!`, `_ra_push_probe_rows!`, `commit_run_artifact!`, and reader protocol. Earlier implementation review included artifact prepare and ordinary loss writer. No claim to a full-file audit. |
| `src/policies/Policies.jl` | Relevant serial collective seam, policy scopes, and shard association. This pass directly checked `_mp_allsum!`; prior implementation review covered gather/broadcast paths used by the helpers. No full policy audit. |
| `src/beam/Beam.jl` | `Phase6DRep` storage/shape constructor, compared with armed-reference resize/identity checks. |
| `test/runtests.jl` | Targeted reset tests and existing aperture/loss contracts inventoried; no full-suite source audit. |
| `docs/design/phase_space_reset.md` | Draft reviewed during design phase and current lifecycle/output sections checked against implementation. |

No accelerator equation was changed or independently rederived in this unit: the reset is a nonphysical storage operation, and this unit assessed ownership and diagnostic semantics. No Julia test, CUDA run, MPI run, performance measurement, or full gate counts as executed by this unit. The implementation agent's reports must supply those results separately.

## Leads

### LEAD U2-1 [moderate, confidence high] src/tasks/Tasks.jl:1097

Claim: The original recursive-execution refusal entered generic failure cleanup and consumed the outer execution's pending trial, even when the observer caught the intended refusal.

Mechanism: An observer called `execute!` on its already-running reset task. `_prepare_phase_space_reset!` threw on `state.running` inside the nested call's generic catch region. That catch called `_finish_failed_reset_trial!` on the shared state, recording the outer pending trial as partial; with an artifact it also closed the outer file. The outer observer could catch the `ArgumentError`, but its completed trial had already been finalized incorrectly. Source at discovery: `PhaseSpaceReset.jl:69`, `Tasks.jl:1092/1133` before the five-line entry guard was added.

Repro: `julia --project=. --threads=4 /tmp/octopus_reset_reentrant_repro.jl`. Both `artifact=false` and `artifact=true` variants must report exactly one nested `ArgumentError`, a successful outer execution, `task.next_turn[] == 1`, `completed_trials == 1`, and one last trial with `completed=true, folded=true`. The artifact variant must contain turn `[0]` with both flags `[1]` and no retained lock. Before the guard, the no-artifact variant is expected to have zero completed trials and a false-completion last trial; the artifact variant may additionally fail the outer write or have partial output.

Disposition: Fixed by the root with an early entry refusal before `_runtime_entries` and outside the failure catch. The new guard at `Tasks.jl:1033–1037` was read. Parent-owned reproduction: unfixed **13 passed / 8 failed**, fixed **21 / 21 passed**. This unit read `/tmp/octopus_reset_reentrant_red.log` and `/tmp/octopus_reset_reentrant_green.log`; it did not execute either run.

### LEAD U2-2 [moderate, confidence high] src/tasks/Tasks.jl:1928

Claim: Refusing an armed reset task's reuse with another beam can replace its last-trial public loss record before the ownership check throws.

Mechanism: `execute!` calls `_runtime_entries` before reset ownership preflight. `_runtime_entries` first calls `_ensure_loss_record!`, whose foreign-storage case allocates and installs a fresh record/owner. Only afterward does `_prepare_phase_space_reset!` reject the foreign beam against the saved six-array ownership. The bounded reset-window summary and saved reference survive, but `loss_record(task)` has changed and `loss_summary(original_rep, task)` no longer describes that original beam's last trial. With one aperture loss it changes from `logged=1, unattributed=0` to `logged=0, unattributed=1`. Relevant call chain at read time: `Tasks.jl:1050 -> 1928 -> 2076–2078`, then `PhaseSpaceReset.jl:80`.

Repro: `julia --project=. --threads=4 /tmp/octopus_reset_wrong_beam_repro.jl`. Both artifact variants execute a two-particle reset/aperture trial with one loss, save the record and summary, attempt a same-shaped foreign beam (expect `ArgumentError`), then assert the record identity and original-beam loss summary are unchanged. The bounded reset summary and `next_turn == 1` should also remain unchanged.

Disposition: Fixed by the root with a wrapper that saves the prior loss record/owner, records the admission counter, and restores prior diagnostic ownership on failure before admission. Parent-owned reproduction: unfixed **6 passed / 4 failed**, fixed **10 / 10 passed**. This unit read `/tmp/octopus_reset_wrong_beam_red.log`; the green count was supplied by the parent. The initial rollback cleared the compiled-line cache; the second neighbour pass found U2-3 below at that new boundary.

### LEAD U2-3 [moderate, confidence high] src/tasks/Tasks.jl:1050

Claim: The first failed-admission rollback implementation discards a resolved spectral-noise table, so a later valid run can silently use a different noise table after the global seed changes.

Mechanism: The U2-2 fix restores the old loss record and owner but unconditionally assigns `runtime_entries_cache[] = nothing` before rethrowing. Even a refusal caused solely by an out-of-range `start_turn` clears a previously valid cache. The next execution recompiles `SpectralNoise` under the new global seed. This contradicts the existing resolved-table behavior: without a spec/knob/accepted-storage change, changing the global seed warns while the existing table stays as synthesized (`turn_modulated.jl:820–835`, suite testset “Turn modulation at execute!: the global-seed drift warning for resolved spectral tables and the equal-digest check over the resolved line”). The reset reference remains armed, so the accepted experiment resumes with altered noise despite only a refused window request intervening.

Repro: `julia --project=. --threads=4 /tmp/octopus_reset_refusal_spectral_repro.jl`. For both artifact variants, compile reset plus spectral crab at seed 1001, change the global seed to 2002, refuse `start_turn=256` for a 256-turn table, and resume at turn 1. Expected: old table identity/digest, `resolved_seed == 1001`, and the `:turn_modulation` consumer receipt keeps the original digest. The initial rollback is expected to produce seed 2002 and a different digest. No parameter, beam shape, or ownership change is needed.

Disposition: Fixed by the parent after reproducing **8 passed / 8 failed** in 19.1 s across artifact-free and artifact variants. Both unfixed variants changed `resolved_seed` from 1001 to 2002 and digest `0x9bfa3854007880a2` to `0x6ec260c55254f052`. The fixed harness reports **16 / 16 passed** in 18.6 s; both variants retain seed 1001, identical table identity/digest, and the original consumer receipt digest. This unit read `/tmp/octopus_reset_refusal_spectral_red.log` and `/tmp/octopus_reset_refusal_spectral_green.log` and the fixed wrapper. The fix saves the previous runtime cache and restores it on pre-admission refusal, while clearing plans so a candidate-record plan cannot survive; the old runtime-cache key continues to force legitimate spec/knob recompilation. This unit prepared the harness and did not run Julia.

### Parent-owned aperture-catalogue regression

The parent also reproduced a related same-count aperture rename: cached loss-record names could hide the changed spec name from output binding, so continuation silently retained the old attribution labels. The accepted fix compares resolved aperture names when reset state exists, causing rebinding to expose the mismatch to precommit validation; rejected admission restores the prior record. Parent-owned reproduction `/tmp/octopus_reset_rename_repro.jl`: unfixed **1 passed / 4 failed**, fixed **5 / 5 passed**. This unit read the red log and harness and inspected `_ensure_loss_record!` with `match_names`, `_loss_record_aperture_names`, and reset-specific caller selection. The green count was supplied by the parent. Ordinary tasks retain the default `match_names=false` behavior.

## Clean observations from source, not runtime passes

- The snapshot lives in task state, outside the compiled runtime tuple and cached plan. Cached reset segments hold that same state object, so recompilation does not rearm capture. Clear replaces the state object's ledger and removes its reference; a no-aperture cached segment still sees the replacement through the same state object. With apertures, dropping the record invalidates the runtime cache through record identity.
- Armed capture checks all six array identities, lengths and axes, backend/device, local length and global MPI interval/rank count. Shape and ownership verdicts are collectively agreed before normal preflight refusal. The first capture validates finite coordinates before copying; zero-turn admission does not capture or restore.
- Window aggregates reset after artifact commit, not during product binding. A refusal after product binding but before commit leaves the previous bounded summary available. The accessor copies mutable aperture totals/names and deep-copies the last trial. The record-rebinding exception was fixed as U2-2 above; cache preservation is the additional U2-3 boundary.
- Absolute turn/context advances independently from restoration. Snapshot, capture turn, and reference epoch persist across continuation and explicit replay. Clear preserves the epoch counter and task turn, while the next capture obtains a new epoch.
- `_next_reset_reference_epoch` reads valid rows from both reset product groups before replay truncation. A fresh task continuing an artifact therefore chooses an epoch above stored references rather than restarting at 1. Root read failures are broadcast as refusals, preventing other ranks from proceeding into later collectives after only root failed. Malformed or inexactly representable output epochs are refused.
- Trial columns and event columns both carry their reference epoch and capture turn. Continued aperture catalogue/name validation runs before generic bind/commit, preventing rewritten group attributes from relabeling earlier aperture rows.
- Loss scratch is cleared only at each reset-trial beginning. Each successful trial is reconciled after tracking, turn observers, and luminosity output. Finalizer failures occur after completed trials have `pending=false`, so they do not append a second partial trial.
- Successful trial summaries fold small counts and gather optional event rows. Zero-event ranks contribute empty rows to the same unconditional gather; their CUDA slot matrix is not copied merely to discover zero events. Artifact-free CUDA liveness uses a reusable device mask and scalar reduction, avoiding generic six-coordinate host copies.
- The partial-failure path explicitly passes `completed=false, folded=false`, performs no loss-summary reduction, no event gather, and no broadcast. Only the rank owning the artifact file writes it. The stored shard offset preserves global particle IDs in its root-local event rows. Completed-window aggregate counters exclude this partial row while the latest trial remains visible.
- The reset writer uses the shared valid-row cursor protocol and replaces any current-turn rows before retrying a failed write. Events precede the completed summary; normal monotone appends do not reread all history. Per-trial flushes are explicit documented exceptions to the artifact capacity knob, with a receipt stating that capacity is inactive for these products.
- Ordinary loss-summary, dead-count, and permanent `/losses` writer bodies were not changed. Reset execution bypasses ordinary end-of-run permanent-loss output; ordinary execution retains its cumulative record behavior. This source comparison is not a substitute for the parent's ordinary-loss regression tests.
- A warning originally promised persistence of unattributed failing coordinates even though reset products store only the unattributed count. The architecture reviewer flagged this, the root corrected it, and this unit read the corrected count-only warning at `PhaseSpaceResetTrials.jl:269`.

## Deliberately unchecked and boundaries

- True simultaneous calls from multiple threads to the same task are unsupported. The root explicitly chose to document serialized task calls rather than introduce task-wide thread safety in this feature. The ordinary `running` flag is a lifecycle/reentrant guard, not an atomic lock. No artificial barrier test or claim of thread-safe concurrent admission is made.
- The root's early recursive guard and failed-admission rollback were read but not executed here. Parent-owned focused regression results are recorded above; they do not stand for the final full gate or every callback phase.
- CUDA kernel/device compilation, allocation residency, stream ordering, and no-host-copy spy tests belong to the coordinated validation runs. An explicit-stream question was checked with `/root/reset_architecture`: its source-wide caller census found that ordinary `TrackingTask` calls the plan with `stream=nothing`, while the only explicit-stream caller is StrongStrongTask, which rejects reset. This is another agent's source evidence, not this unit's runtime measurement.
- MPI behavior was reasoned from scopes/collective seams, not executed by this unit. Rank-asymmetric arbitrary observer/kernel failures can still inherit the framework's general failure limitations; this unit claims only that the reset failure finalizer itself adds no collective.
- Real disk-full/process-kill/HDF5 failure injection was not executed here. The same-turn retry and valid-cursor behavior were inspected against the existing probe protocol, not experimentally fault-injected by this unit.
- Reference-epoch extreme-range cases, malformed external artifacts, every public reader selector combination, and external in-place particle reordering were not executed. Reordering coordinate contents externally remains outside the armed-reference continuation contract.
- No broad performance claim is made. In-memory counters are bounded by aperture count; artifact history and its explicit per-trial flush cost are proportional to requested diagnostics. Snapshot memory itself is six coordinate arrays plus one Boolean mask per local particle.

## Scratch artifacts

- `/tmp/octopus_reset_reentrant_repro.jl`: U2-1 no-artifact and artifact variants, prepared but not run by this unit.
- `/tmp/octopus_reset_wrong_beam_repro.jl`: U2-2 no-artifact and artifact variants, prepared but not run by this unit.
- `/tmp/octopus_reset_refusal_spectral_repro.jl`: U2-3 artifact-free and artifact variants, prepared but not run by this unit.
- `/tmp/octopus_reset_rename_repro.jl`: parent-owned aperture-name continuation harness, read by this unit.
- `/tmp/octopus_reset_U2_report.md`: this report. The root must copy the durable report and any retained reproduction/measurements into the campaign's committed evidence before claiming them in the final history.


## Second-pass persistence and documentation review

The follow-up pass directly re-read the current wrapper/admission rollback, reset state, trial-loss helper, reset writer and epoch helper, named product readers, and the surrounding shared bind/commit/append protocol. It also read the complete current reset lifecycle/output test blocks and public/current-runtime documentation additions. No repository files changed and no Julia process ran under this unit.

The unchanged persistence conclusions remain source-supported: binding validates before shared product commit; accepted replay replaces rows from the requested first turn; each trial writes events before its summary and marks the ledger complete only after successful output; a pending failed turn is best-effort local output with both flags false; finalizer failure does not relabel already completed trials; fresh captures allocate epochs above valid retained output; zero-event trials still have summary rows; and ordinary permanent-loss output is bypassed only for reset tasks. No new runtime defect was found in these artifact/final-trial paths during this pass.

The root corrected the wording qualification found in this pass: `clear_phase_space_reset!` itself does not change the file, and precommit refusal preserves prior reset product rows, but the shared artifact prepare protocol can legitimately record an attempted execution/provenance ledger entry before product commit. Whole-file byte identity is not promised. The design and public API also now state that retaining prior execution windows requires `RunArtifact(path; append=true)`; the default `append=false` replaces them. This unit read both corrections.

No concrete source lead remains open in this assigned unit after the parent-owned U2-1/U2-2/U2-3 fixes and aperture-catalogue regression. The final-tree full gate is still the parent's separate obligation; these focused results do not claim that gate. True concurrent task execution, real process-kill/disk-full fault injection, and all broader runtime boundaries remain as listed above. A final read-only `git diff --check` returned success during this pass.

## Third pass: reset-detection allocation boundary

The parent reported that the first full gate stopped at the existing ordinary-tracking allocation pins: fast execution allocated **867,120 B**, general execution **689,744 B**, against the unchanged **<400,000 B** bounds (`test/runtests.jl`, once-per-execute walks). The gate had executed **121,080 passing assertions, 2 failing assertions, 2 broken checks, 251 testsets**, over approximately **41 minutes**, before stopping. These are parent-provided results, not a run by this unit. They are a failed gate, not final validation. `/root/reset_architecture` owns Julia, measurements, and the implementation repair.

This unit performed a read-only source-wide census of `_has_phase_space_reset`, `_requires_tracking_task`, `_reject_task_only_tracking`, and their task/low-level call sites. It directly read the existing allocation pin and its per-walk companions, the fast turn loop, general segment forwarding, both CPU low-level overloads, CUDA guard additions, and strong-strong compilation refusal.

The census establishes two distinct repeated surfaces:

- `_has_phase_space_reset(entries)` was an `any` walk over the heterogeneous runtime-entry tuple. Normal task admission calls it through reset preflight; the fast-loop branch and its receipt also call it; general execution uses it to select reset state; normal output and failure cleanup use it to select loss semantics.
- `_requires_tracking_task(elems::Tuple)` was a separate `any` walk. `_reject_task_only_tracking` calls it before resolved CPU/CUDA tracking. The task's fast loop calls `track!(..., 1, ...)` every turn, and general fused segments do so every turn/segment. This identifies a separate per-turn guard that needed measurement; it does not prove that guard allocates. The architecture probe subsequently measured the generic predicate at **0 B**, so it stays unchanged.

The actual measured fix is deliberately narrower than the preliminary one-trait proposal: only `_has_phase_space_reset` changes. It now uses the existing `_foreach_unrolled` walker and a typed `Ref(false)` accumulator. Each literal-index visit checks `found[]` first, then applies the unchanged `PhysicsEntry && _requires_tracking_task(entry.element)` predicate, and the closure returns `nothing`. The generic `_requires_tracking_task(::Tuple)` and all wrapper/CompositeLine methods remain unchanged because that predicate measured **0 B** before the fix. No PhysicsEntry trait-forwarding refactor was made. This unit read the actual edited helper and the unchanged generic trait. Empty tuples still return false; nonphysics entries never access `.element`; once a reset is found no further capability call runs; wrapper recursion and placement/cardinality checks are unchanged. The source change is approved within this reading unit's scope.

Coverage reviewed in the actual test changes:

1. Keep the existing **<400,000 B** ordinary fast/general execution bounds unchanged.
2. Both `_has_phase_space_reset` and the unchanged `_requires_tracking_task` are added to the existing **<=256 B** warmed walk pins over the 40-element/eight-type ordinary lattice. The zero-cost generic predicate is pinned, not modified.
3. Check false results for empty and ordinary tuples and true results with reset in the final slot of a long heterogeneous tuple. The late positive prevents accidental early truncation or incomplete generated coverage.
4. Bare and kept-whole transformed reset runtime objects are tested at the final position of the long tuple through both predicates. Public `track!` must refuse them before any of the six coordinate arrays changes. Existing direct/resolved refusal tests retain their prior scope.
5. Retain the task's duplicate-reset, interior-reset, transformed/kept-whole placement, readonly-entry-observer, and strong-strong refusal tests. The optimized trait answers presence; task admission still owns placement and cardinality checks.

Architecture-owned measurements were read from `/tmp/octopus_reset_alloc_red.log` and `/tmp/octopus_reset_alloc_green.log`:

| Measurement | Before | After |
| --- | ---: | ---: |
| `_has_phase_space_reset` | 189,824 B | 0 B |
| Generic `_requires_tracking_task` | 0 B | 0 B, unchanged |
| Ordinary fast `execute!` | 867,120 B | 107,824 B |
| Ordinary general `execute!` | 689,616 B | 119,936 B |
| Focused allocation assertions | 1 pass, 3 fail | 4/4 pass |

The isolated general-run baseline differs by 128 B from the earlier full-gate measurement (689,744 B); both exceed the same unchanged bound before the fix. Internal-window and public-wrapper measurements were identical, excluding the new wrapper as the cause. The logged six-coordinate fingerprints match before/after for both paths. This unit read the probe and result lines; it did not execute the measurements. The actual permanent tests add both allocation pins and positive/negative capability/no-coordinate-mutation checks.

No Julia execution or repository edit was made by this unit in this pass. A read-only `git diff --check` passed. The replacement full gate remains the root's obligation; these focused numbers do not claim that gate.
