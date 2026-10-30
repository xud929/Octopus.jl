# Phase-space reset neighbour review — unit U1

> Parent closure: the final CUDA-active gate passed on 2026-10-29; see the
> [campaign receipt](../audit_phase_space_reset_2026_10_29.md#final-gate-receipt-and-closure).
> Pending-gate statements below describe this unit's earlier handoff.

Status: U1 targeted work complete; parent campaign gate and report date pending.
Reviewer: `/root/reset_architecture`.

## Scope and provenance

The parent assigned the reset element, metadata and parameter-effectiveness
adaptations, low-level CPU/CUDA refusal paths, the existing backend validation
script, and a targeted read of the task/runtime/loss seams. This is a scoped
feature review, not a new repository-wide audit. The parent owns task-state
implementation, the aggregate audit decision, negative-control reruns and the
final gate. Another agent owns the new independent oracle, MPI tests and
artifact implementation; their reported passes are not counted as executions
by U1.

Directly inspected, line by line: `src/elements/phase_space_reset.jl`,
`src/tasks/PhaseSpaceReset.jl`, `src/tasks/PhaseSpaceResetTrials.jl`.
Directly inspected at changed functions and immediate callers:
`src/knowledge/Knowledge.jl` default-map probing and metadata checks;
`src/contracts/Contracts.jl` parameter-effectiveness and tracking-backend
contracts; `src/track/Track.jl` runtime traits;
`src/track/phase6d_track.jl` public/resolved/deprecated CPU/CUDA entries and
wrapper traversal; `src/tasks/Tasks.jl` compile/prepare/plan/execute integration;
`src/tasks/strongstrong/interface.jl` shared compile/binding refusal;
`src/beam/Beam.jl` live/dead counting; `src/elements/aperture.jl` loss scratch
access; `src/tasks/RunArtifact.jl` reset event binding/writing;
`validation/tracking_backend_consistency.jl` complete coverage composition
and per-kind execution; relevant existing registry and new reset testsets in
`test/runtests.jl`; `test/phase_space_reset_probe.jl` independent-oracle setup.
`src/elements/Elements.jl` and `src/Octopus.jl` were inspected for include
ordering. No claim is made to have reviewed unrelated sections of those large
files. All task-only trait/probe/reset references were enumerated with a
source-wide `rg` call after edits.

The design note, element guide, contracts/analysis guide, configuration guide,
testing-lane backend requirements and runtime backend notes were consulted.
`docs/experiences.md` and `docs/comprehensive_audit.md` were read in full;
truncated middle output from the audit protocol was re-read in smaller chunks.
The latest full audit's summary and open-queue framing were consulted as
historical context, not current evidence.

## Implementation and clean checks

Traceability anchors on the reviewed tree:

| Requirement or seam | Implementation | Executable evidence |
|---|---|---|
| Task-owned reset and storage binding | `src/elements/phase_space_reset.jl:49`; `src/tasks/PhaseSpaceReset.jl:42`, `:52`, `:102` | independent oracle and lifecycle testsets; backend reset reference |
| Positive metadata probe | `src/knowledge/Knowledge.jl:1206`; `src/elements/phase_space_reset.jl:84`; `src/contracts/Contracts.jl:4091` | 610 declared defaults; 549 decided parameter-effectiveness pairs |
| Bare tracking refusal | `src/track/Track.jl:64`; `src/track/phase6d_track.jl:20`, `:81` | CPU/CUDA direct and buried marker no-mutation checks |
| Strong-strong refusal | `src/tasks/strongstrong/interface.jl:3781` | direct/buried marker in each beam, unchanged coordinates and turn |
| Reentrant/admission rollback | `src/tasks/Tasks.jl:1032`, `:1057`, `:2061` | parent-provided red/green probes executed by U1 |
| Device-local per-trial liveness | `src/tasks/PhaseSpaceResetTrials.jl:45` | source call chain; device-copy negative control assigned to parent |
| Bounded trial summary and event gathering | `src/tasks/PhaseSpaceResetTrials.jl:186`, `:225` | source complexity review; independent artifact/loss tests |
| Declared backend class and actual restore | `validation/tracking_backend_consistency.jl:262`, `:373`, `:475` | GPU-required backend validation, N=2000, two turns |

- The spec declares only `NonSymplectic6DMap`. Its runtime is a typed marker;
  snapshot ownership stays with `TrackingTask`, outside CUDA arguments and
  compiled-plan caches. The scalar map throws a static message, so the
  refusal branch introduces no interpolated string into device code.
- Public and resolved CPU/CUDA `track!` entries reject the task-only marker
  before any particle loop or launch. Deprecated backend routes delegate to
  those entries. `MisalignedElement`, `RefTilted`, `TurnModulated` and
  `CompositeLine` recurse through the same task-only trait.
- Placement requests are declared in the common schema and rejected at
  compile time when nonzero or nondefault. The effectiveness contract still
  exercises every declared parameter; only its physically invalid baseline
  placement enrichment is suppressed for this kind. It reports rejections,
  not silent exemptions.
- The default and effectiveness metadata probes use a real
  capture/mutate/restore task witness. The mutation changes all six arrays
  independently. A no-op reset, snapshot alias or recapture cannot satisfy
  the restoration check.
- Backend validation derives the task-managed kind set and requires a
  matching executable witness. The reset leads its own reset-plus-kick line;
  its final result is compared with an independent ordinary one-turn run.
  The per-kind arm additionally mutates every coordinate between task calls
  and demands exact recovery on CPU and CUDA. Existing composed and aperture
  lines retain their checks.
- All six storage identities, lengths and axes, backend/device and MPI shard
  identity are bound to the reference. The snapshot remains rank local;
  normal completion folds small trial counters, while partial failure avoids
  MPI collectives.

## Leads delivered to the parent

### LEAD U1-1 [Moderate, confidence high] unbounded window accounting

Claim: the first implementation's `window_rows::Vector{NamedTuple}` grew with
every turn even without output, contradicting bounded default state.
Mechanism: a completed trial pushed another row for the full execution window.
Repro: inspect `ResetTrialLedger` fields and increase trial count; retained row
count grows linearly. Parent replaced it with aggregate counters plus the last
trial; full history now requires artifact output. Final source was re-read.
This is a source-confirmed complexity correction, not a measured speed claim.

### LEAD U1-2 [Moderate, confidence high] hidden CUDA coordinate transfers

Claim: using ordinary `loss_summary -> count_dead -> count_live` at every reset
trial transferred all six coordinate arrays to host each turn.
Mechanism: `count_live` reaches `_host_coordinate_arrays`; the reset snapshot
being a CuArray alone did not satisfy the device-residency requirement.
Repro: trace that call chain or replace `_host_coordinate_arrays` with a
throwing sentinel during a reset-only GPU trial. The implementation now uses a
reusable device liveness mask and scalar device reduction. The new source was
re-read; independent negative-control execution belongs to the parent.

### LEAD U1-3 [Moderate, confidence high] non-x resize admission gap

Claim: the original storage signature bound `length(rep)` (x length) and six
object identities, but missed in-place resizing of another coordinate vector.
Mechanism: `resize!(rep.y, ...)` preserves its object identity and x length,
allowing admission before mismatched copy or count operations.
Repro: capture, resize y in place, then execute; refusal must precede restore
and preserve the old reference/turn. Parent added six lengths/axes and an
initial equal-length check, with MPI agreement. Source re-read confirmed the
checks; the parent owns the old-helper negative control.

### LEAD U1-4 [Minor, confidence high] zero-loss event-transfer overhead

Claim: artifact reconciliation called `loss_records` and transferred an 8N
slot array even when local recorded losses were zero.
Mechanism: a per-trial diagnostic reused the generic slot reader to discover
an empty local event list. The new path uses the already measured local loss
count to construct zero rows, then still enters the unconditional gather.
No performance ratio is claimed; the avoided transfer follows from the call
path. Source re-read confirmed rank participation is preserved.

### LEAD U1-5 [Minor, confidence high] unattributed warning overclaims coordinates

Claim: the initial unattributed-loss warning said non-finite coordinates were
recorded, but the trial product records counts and the event product contains
aperture-attributed events only.
Mechanism: without a separate coordinate observer, an unattributed failure's
coordinates are absent from both products. Requested correction: say its loss
count is recorded before restoration. Parent changed the warning accordingly;
U1 re-read the final warning string.

### LEAD U1-6 [Minor, confidence high] incomplete new metadata declaration

Claim: the first new element declaration used four unapproved vocabulary
keywords and omitted seven placement key spellings from construction help.
Repro: `validate_element_metadata()` reported 11 named errors while checking
all 610/610 defaults. Corrected the declaration to two deliberate controlled
keywords, `:phase_space_reset` and `:noise_response`, and derive the help's
placement-key list from `_PLACEMENT_PARAM_KEYS`. The negative result is
recorded in `/tmp/phase_space_reset_architecture_probe.log`; the corrected
validator subsequently passed with 610/610 defaults checked.

### LEAD U1-7 [Moderate, confidence high] stale full-suite refusal-stage assertion

Claim: after the effectiveness census was updated, a later assertion in the
same testset still required every rejected candidate to fail at construction.
Mechanism: `test/runtests.jl` near line 16472 asserted
`all(startswith("constructor:"), values(r0.metrics[:rejected_reasons]))`,
whereas the measured reset result has exactly eight placement rejections
prefixed `compile_or_map:`. This was found in the final read-only tripwire
sweep, before the full gate. The existing measured result is its negative
evidence; no extra Julia process was launched. Requested the test owner retain
the constructor-only assertion for existing kinds and explicitly derive the
task-managed placement set whose refusal occurs at compile/map time.

### LEAD U1-8 [Minor, confidence high] artifact history wording needs append scope

Claim: public API/current-runtime text says an artifact retains every trial or
full history without stating the across-execution append requirement.
Mechanism: the earlier rename reproduction demonstrated that `artifact=path`
uses append=false and replaces the prior window; append=true retains and
replays previous windows. Requested the document owner qualify full-history
claims with `RunArtifact(path; append=true)` and retain the documented
replacement rule for rows at or after the replay turn. No runtime defect is
claimed by this wording lead.

## Corrections to the review's own assumptions

- The initial proposed default name `"reset"` conflicts with the canonical
  element metadata name default `""`. The implementation keeps the canonical
  default and resolves the empty diagnostic name to `"reset"` at the task
  boundary; schema consistency is retained.
- An unsupported `Symplectic6DMap` request follows the existing generic
  `compile_runtime` protocol and raises `MethodError`, not `ArgumentError`.
  The test expectation was corrected; no global rejection semantics changed.
- The first anticipated parameter-effectiveness census was an estimate from
  schema structure. Actual counts below supersede it.
- U2 raised a possible cross-stream restore race. Source-wide caller census
  found that TrackingTask calls `_execute_tracking_plan_turn!` without an
  explicit stream; explicit streams enter only from StrongStrongTask, which
  refuses reset. Restore, scratch clearing and subsequent kernels therefore
  use the same CUDA task's current stream on the supported public path. No
  defect was established and no change was made for this hypothesis.
- The scratch architecture harness initially treated
  `validate_configuration_metadata()`'s Boolean result as a `.passed` record.
  That harness assertion errored although the validator returned `true`.
  The follow-up asserts the actual Boolean API.
- A first aperture-rename reproduction used the default artifact append=false
  mode. It proved stale aperture labels, but could not justify a retained-file
  continuation refusal. The corrected reproduction explicitly requests
  `RunArtifact(path; append=true)`; its distinct red receipt is recorded below.

## Execution record

Environment observed directly: Julia 1.12.4, four threads, CUDA functional,
NVIDIA RTX 4500 Ada Generation.

- `julia --project=. --threads=4 /tmp/phase_space_reset_architecture_probe.jl`:
  first contract block took 220.3 s. Element parameter effectiveness passed:
  549 checked, 0 ignored, 0 skipped kinds, 0 broken kinds, 35 unperturbable,
  31 rejected, 32 carried, 66 undecided, 10 weak-evidence cases. Reset's eight
  placement keys are explicitly refused; tracking_method is unperturbable.
  The metadata validator checked 610/610 defaults but failed the 11 vocabulary
  and help errors above; the harness also had one Boolean API error. The
  overall process therefore exited 1, with 9 passed, 1 failed and 1 errored
  assertion; the following refusal testset did not run.
- The same process ran `validate(PublicConfigurationEffectivenessContract())`:
  passed with CPU workers [1,2,4], worker-coordinate max absolute error 0;
  serial MPI passthrough 1 rank (not a launcher test); CUDA launch threads
  64/128/256/512; all seven PIC launch families at requested 64 and fallback
  128; CPU/CUDA coordinate max absolute error 1.0842021724855044e-19;
  24 output receipt pairs checked; seven Beam initialization cases and seven
  receipts on each backend. Configuration metadata returned `true`.
- Parent's reentrant reproduction `/tmp/octopus_reset_reentrant_repro.jl`:
  before its fix, 13 passed/8 failed in 19.4 s. Both outer executions returned
  normally but retained completed_trials=0 and last_trial completed=false,
  folded=false; the artifact row also had completed=0, folded=0. After the
  parent moved refusal outside failure cleanup, 21/21 passed in 18.0 s;
  both summaries and the artifact row report completed=true/folded=true.
  Logs: `/tmp/octopus_reset_reentrant_red.log` and `_green.log`.
- Parent's foreign-storage reproduction `/tmp/octopus_reset_wrong_beam_repro.jl`:
  before its fix, 6 passed/4 failed in 17.1 s. A refused second beam replaced
  the prior loss record in both artifact modes: logged 1→0 and unattributed
  0→1. Log: `/tmp/octopus_reset_wrong_beam_red.log`. After the parent's
  pre-admission rollback fix, 10/10 passed in 15.6 s: identical record and
  summary retained in both modes.
- Parent-requested aperture-rename reproduction
  `/tmp/octopus_reset_rename_repro.jl`, with append=true: 1 passed/4 failed in
  19.4 s. After changing the spec name OLD→NEW, the continuation was accepted,
  the scratch record retained OLD, file turns became [0,1] and next_turn=2.
  Log: `/tmp/octopus_reset_rename_append_red.log`. After reset-only name
  matching and admission rollback, 5/5 passed in 3.2 s: ArgumentError,
  identical old record, file turns [0], next_turn=1.
- Corrected metadata/help/configuration checks: 9/9 passed in 83.0 s;
  validate_element_metadata returned passed=true with errors=[] and 610/610
  defaults checked. Both element_help query forms executed.
- StrongStrongTask and low-level wrapper refusal checks: 24/24 passed in
  11.9 s. Four strong-strong cases cover direct and buried reset in either
  beam; four bare-track cases cover direct and buried reset on CPU and CUDA.
  Each refusal precedes coordinate or stored-turn mutation. Combined green
  log `/tmp/phase_space_reset_architecture_green.log`, exit 0, contains these
  four corrected testsets (48 assertions total).
- `OCTOPUS_REQUIRE_GPU_CONTRACT=1 OCTOPUS_CONTRACT_N=2000 julia --project=.
  --threads=4 validation/tracking_backend_consistency.jl`: exit 0;
  all 35 instances meet their declared classes on CPU/CPU and CPU/CUDA.
  Reset contract: two turns, 12000 coordinate slots, max absolute error 0,
  bitwise=true on both comparisons. The independently copied one-turn kick
  reference passes; the per-kind capture/mutate/restore witness is bitwise
  in all six coordinates with bound 0. The ordinary composed line remains
  CPU/CPU bitwise and CPU/CUDA max absolute error
  8.196568423990414e-17, global relative error 3.794018931393513e-15,
  at atol=rtol=1e-10. The aperture arm still kills 1370 of 2000 particles
  and retains 630, avoiding an identity-only or all-lost comparison.
  No GPU leg skipped. Log: `/tmp/phase_space_reset_backend.log`.
  After this proof the element declares
  `ElementTrackingBackendConsistencyContract`; the parent final metadata
  check/snapshot/gate cover that declaration on the final tree.

The initial sandbox attempt could not open Julia's compiled-cache pidfile and
ran no feature check; the actual probes ran with authorized cache/GPU access.
Warnings from the parameter sweep's deliberately invalid radiation/curvature
fixtures and the scratch process's cross-consumer RNG fixture ordering were
visible. No warning was suppressed.

The full gate and MPI launcher are assigned to the parent/other agents and
are deliberately not represented as U1 executions. U1 released the Julia slot
after the successful backend script; `git diff --check` was clean.

## Final read-only tripwire sweep

After the parent requested another pass before the gate, U1 re-read the reset
element and low-level guards, the complete current design note, public API and
runtime additions, and registry-derived sweeps for precision, rounding,
analysis declarations, complex-step parameters, friendly-type lookup,
metadata placement schemas, public task keywords, detached docstrings and
CUDA-script discovery. No Julia ran while the design agent owned the slot.
The stale refusal-stage assertion above was the one definite remaining gate
failure found. The precision test's CPU-only skip text also still said 31
kinds; the test owner was asked to derive that message from `length(kinds)`.
The new standalone validation declares its CUDA marker and required-GPU gate
header, and is indexed in `validation/README.md`; no extra skip was introduced.
The registry snapshot is deliberately assigned to the parent for regeneration.

Other inspected sweeps remain applicable without a reset exception: analysis
selection compares exact method types, the complex-step sweep considers only
nonzero scalar parameters actually stored in each example (the reset example
stores none), friendly-type selection is structural and does not track its
all-kind line, and schema/API keyword checks do not treat private task state
as a new public option. New exports have immediately attached docstrings;
their typed constructor does not attach documentation to a foreign binding.
The search found no stale `phase_space_reset_trials`, `window_rows` or old
reference-generation accessor in current source or the scoped public docs.

## Full-gate allocation regression and measured correction

The first full CUDA-active gate stopped after about 41 minutes at the existing
`(e) once-per-execute! walks` assertions in `test/runtests.jl`: fast execution
allocated 867120 bytes and general execution 689744 bytes, both above the
unchanged 400000-byte ceilings. This was a real no-reset-path regression
introduced by the campaign, missed by the initial targeted functional checks.
The parent assigned U1 its diagnosis and minimal correction, giving U1 the
exclusive Julia slot. The failed gate is
`result/phase_space_reset_full_gate_20261029.log`, exit 1; its 107/109 passing
assertions in that enclosing testset do not make the full gate green.

### LEAD U1-9 [Moderate, confidence high] new entry predicate boxes heterogeneous tuples

Claim: `_has_phase_space_reset(entries)` used an ordinary `any` over a large
heterogeneous tuple, repeating the exact boxing defect the old allocation
fixture already guarded.
Mechanism: runtime-index iteration boxes the 40-entry tuple once per visited
position; the new predicate is called several times per ordinary execution.
Repro: `julia --project=. --threads=4 --check-bounds=yes
/tmp/octopus_reset_alloc_probe.jl`, before correction, exited 1 with 1 passed
and 3 failed checks. Warm measurements were fast=867120 B, general=689616 B,
and the predicate alone=189824 B. Calling public `execute!` and internal
`_execute_tracking_window!` gave identical allocations, excluding the new
rollback wrapper as the cause. `Profile.Allocs` attributed 725088 B across
156 tuple allocations in one fast execution directly to the predicate.

The correction is confined to `src/tasks/PhaseSpaceReset.jl`:
`_has_phase_space_reset` now uses the existing `_foreach_unrolled` traversal
with a scalar `Ref(false)`. It preserves short circuit semantics and all
positive/negative refusal behavior. No tracking kernel or tolerance changed.
The initially suspected `_requires_tracking_task(elems)` sibling measured
0 B on this fixture, so it was left unchanged. This is a correction to the
initial hypothesis, not a claim that both predicates were defective.

| Warm allocation measurement | Before | After |
|---|---:|---:|
| Ordinary fast `execute!(turns=1)` | 867120 B | 107824 B |
| Ordinary general `execute!(turns=1)` | 689616 B | 119936 B |
| `_has_phase_space_reset(entries)` | 189824 B | 0 B |
| `_requires_tracking_task(elems)` | 0 B | 0 B |

The complete six-coordinate fingerprints printed before/after were textually
identical, verified from the two logs. Both representations had four
particles; final px was -0.025870961893281568 for each, final py was
-0.006467740473320392 for each, and the complete stored fingerprint also
compares x/y/z/pz, not only these illustrative values. Profiled allocations
fell from 849616 B/568 allocations to 105920 B/254 allocations on the fast
path; the unprofiled figures above are the acceptance measurement. These are
allocation measurements, not a claim about steady-state tracking speed.

Permanent coverage extends the existing per-walk list with both new
predicates at its unchanged <=256-byte limit. Empty and no-reset tuples,
direct and frame-wrapped resets in the last slot of the heterogeneous tuple,
and bare-track refusal before coordinate mutation are asserted explicitly.
The whole-execution ceilings remain <400000 B. This fixture's previous red
measurement is the regression test's negative control.

Checks after the correction, all with four threads and --check-bounds=yes:

- Scratch allocation/profile reproduction: 4/4 passed; log
  `/tmp/octopus_reset_alloc_green.log`; before log
  `/tmp/octopus_reset_alloc_red.log`.
- Exact expanded suite allocation block: 29/29 passed, 23.7 s.
- Exact CPU/CUDA reset lifecycle, ownership, restoration and refusal testset:
  255/255 passed, 34.4 s.
- Exact source `Core.Box` sweep: 5/5 passed, 1.6 s.
- Combined checks log `/tmp/octopus_reset_alloc_checks.log`, exit 0;
  `git diff --check` clean. No bound was relaxed and no check was skipped.

U1 released the Julia slot to the parent for a fresh full gate on this tree.
No new full-gate pass is claimed by this unit report.

## Limits

This operation is an explicit nonphysical reset, so no symplecticity claim is
made for it. No accelerator field equation changed or was re-derived here.
No new steady-state performance benchmark or multi-GPU run was performed.
Generic asymmetric MPI inputs of different coordinate precision were not
tested: `_runtime_entries` checks precision before collective reset admission.
The new coordinated checks target same-precision storage ownership, partition,
shape and finite-reference inputs; this review makes no broader claim that
all malformed distributed calls fail collectively.
CPU/CUDA numerical comparisons use each existing element's rounding class;
reset storage copies themselves require bitwise equality. The campaign's
final tree, complete test counts, negative controls and push authorization
belong to the parent report.
