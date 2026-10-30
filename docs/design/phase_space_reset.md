# Phase-space reset for repeated noise trials

Design reviewed 2026-10-29 for the owner's requested noise-response experiment,
by separate architecture and validation reviewers. The implementation and
measured validation are recorded in the
[campaign record](../history/audit_phase_space_reset_2026_10_29.md). This note
records the reviewed decisions; the record distinguishes executed checks
from unverified boundaries.

## Experiment and decision

Given a saved particle coordinate vector $X_0$ and the noise realization
$\eta_i$ on absolute turn $i$, measure

$$
X_i = F(X_0;\eta_i), \qquad
\Delta X_i = F(X_0;\eta_i)-F(X_0;0).
$$

Each particle retains its own $X_0$. A uniform grid therefore measures the
response at many specified phase-space points simultaneously. The noiseless
reference is $F(X_0;0)$, which equals $X_0$ only at a fixed point. These are
one-turn response samples; a long-term growth or resonance study still needs
the evolving trajectory. Correlated noise remains correlated between trials.
The cavity's phase and strength meanings stay those of
[the crab-cavity response derivation](../theory/crab_cavity_noise_response.md)
and [turn modulation](turn_modulation.md).

Add `PhaseSpaceResetSpec`, registered as `:phase_space_reset`, as a built-in
line operation. On first passage it captures an independent copy of all six
coordinate arrays. On every later passage it restores those arrays. It changes
neither the absolute turn nor the noise streams. The task owns the mutable
capture state; the element spec carries only meaning, precision, placement
metadata and the selected method.

```text
capture/restore X0 -> noisy physical lattice -> observe Xi and finalize losses
       ^                                                   |
       +---------------------- next turn ------------------+
```

For the first implementation a `TrackingTask` may contain exactly one reset,
at its first tracking position. Read-only observers may precede it. Rotate the
line to choose another reference location. An interior reset, multiple resets,
or a reset in a `StrongStrongTask` is rejected before tracking. The strong-strong
case needs a separate decision about restoring both live beams and solver
state, so it cannot acquire support merely because its line walker finds the
new kind.

## Public surface and classification

The constructor follows the existing element convention:

```julia
PhaseSpaceResetSpec(; name="", tracking_method=NonSymplectic6DMap(), kwargs...)
PhaseSpaceResetSpec{Float32}(; name="")
```

The standard `numeric_type` keyword and typed constructor obey the common
precision rule. There is no `backend`, `n_macro`, RNG, snapshot source, or
capture-cadence keyword: storage comes from the beam and execution policy,
and capture occurs on first passage. Nonzero geometric placement parameters
are refused, including when inherited through a kept-whole or transformed
line. Flattened, untransformed line structure may contain the reset if it is
still the first tracking element. The first version refuses arbitrary action
hooks on a reset task: a callback could reorder, replace or mutate the input
ensemble without updating the saved reference.

Only `NonSymplectic6DMap` is declared. For a fixed reference the restore is
$R(X)=X_0$, whose coordinate Jacobian is zero, so it is non-invertible and
non-symplectic. The kind declares no `TwissDispersionAnalysis` or symplecticity
contract. Scalar runtime calls, bare low-level tracking, and ordinary optics
analysis through a reset must fail by name; they lack the task lifecycle that
makes capture meaningful. A no-op fallback would conceal an unsupported run.

An explicit `clear_phase_space_reset!(task)` discards the saved reference and
arms capture on the next passage. It does not rewind the turn or reseed noise,
and is refused while the task is executing. It clears that reference's
in-memory trial aggregates, last-trial summary and scratch; clear itself never
changes existing artifact files. Pre-admission refusal preserves prior reset
product rows, although artifact preparation may write execution/provenance
metadata. The next capture advances a `reference_epoch` counter
that is not itself cleared. When continuing an artifact, a fresh capture uses
an epoch greater than every stored epoch for that reset name, including when
a new task continues an old file. Rank 0 reads the stored maximum during
admission and broadcasts the decision; it is committed only with the admitted
capture. A task-local counter alone could label two different references as
epoch 1 after a process restart. `phase_space_reset_summary(task)` returns
the most recent admitted execution's bounded totals: `completed_trials`,
`attempted_particle_trials`, `survivor_particle_trials`, `aperture_loss_events`,
`unattributed_loss_events`, aperture attribution, and `last_trial` with its
reference epoch, capture turn, completion/fold status and counts. Only completed
trials enter the aggregate; a partial trial remains visible as `last_trial`.
The accessor returns `nothing` before the first admitted execution and after
an explicit clear. An admitted zero-turn window reports zero totals.
Full per-trial history is read from the artifact. An unnamed reset resolves to
the artifact identity `"reset"`; the constructor's empty-name default remains the canonical placement
metadata default shared by every element kind.

## Capture ownership and lifecycle

The runtime state is private to one task and beam, outside both compiled
element tuples and cached tracking plans. Compiling a spec is pure: it must
not allocate a beam snapshot or inspect an unrelated beam. Reusing the same
spec in another task creates an independent capture.

Calls sharing a task must be serialized, as for other mutable tracking
workflows. Reentrant execution from an observer is refused before the inner
call can modify the outer call's pending trial or output lifecycle.

The saved state binds the six coordinate-array identities, all six lengths and axes, element
type, storage backend (including CUDA device identity) and global
particle-index interval. Changing the beam,
replacing an array, changing its size or changing MPI partitioning while a
reference is armed is rejected before coordinates or artifacts change. An
explicit clear allows the caller to capture a new beam. A task must not guess
that another beam of the same shape is the same ensemble. Particle order is
part of the binding; externally reordering coordinate contents is outside the
continuation contract.

The first captured state must be finite in all six coordinates. This makes
the set of attempted particles explicit and prevents a pre-existing NaN from
being attributed to every later trial. Under MPI the finite-state verdict is
agreed across all ranks before any rank throws. The snapshot is a deep copy:
neither later kicks nor a user write to the current beam may alter it.
CUDA finite-state checks and per-trial reconciliation reuse a device-resident
Boolean mask and reduce only its count to the host. In particular, CUDA's
artifact-free reset loop must not copy all six coordinate arrays to the host
just to count losses. The mask adds one Boolean per local particle to storage.

Capture survives successful continuation calls and tracking-plan cache
changes. A zero-turn call does not capture or restore. Repositioning the
absolute turn does not itself rearm capture: replay uses the same saved
reference and the requested absolute noise turns. Per-window in-memory trial
summaries are cleared only after the new execution has passed admission; a
refused run leaves the previous summary available. With `RunArtifact(path; append=true)`, artifact rows obey the
existing replay rule: preserve rows below the new first turn, replace rows at
or beyond it. The default `append=false` replaces earlier execution windows. A replay after explicit recapture uses the newly captured
reference and labels its rows with its new generation; replay does not infer
or restore an earlier generation's coordinates.

At a failed run, completed trials retain their diagnostics. A trial is
complete only after its physical turn and all turn observations return
successfully. A later finalizer failure does not undo those completed rows.
For a pending trial, best-effort failure finalization runs outside the policy
scope with no MPI collective: it records root-local information with
`completed=false` and `folded=false`, and preserves the original exception if
the diagnostic write also fails. A partial trial is never included in a
completed-trial aggregate. Failure must not silently make the next call
capture partially advanced coordinates as a new reference. The saved reference
remains armed, so retry restores it; artifact replay replaces the failed
window's rows. Retry, explicit turn repositioning and clear behavior are
checked together, because the existing `TrackingTask` advances its stored
turn only after the whole execution succeeds.

## CPU, CUDA and MPI execution

Capture and restore use storage on the same backend as the beam: host arrays
for CPU, CUDA arrays for CUDA, and rank-local arrays for MPI. The snapshot is
six arrays of the coordinate type, costing $6N_{local}\,\mathrm{sizeof}(T)$
bytes, allocated once per capture. Restore performs copies, not conversions,
and preserves the bits of the saved coordinates, including signed zero.
There is no per-turn snapshot allocation, coordinate transfer to the host,
or MPI gather for restoration.

A dedicated tracking segment separates reset from the physical map. CUDA
copies and subsequent tracking respect stream order; a host observer cannot
read before pending device work completes. The reset segment forces the task
through the lifecycle-aware turn loop even when there are no observers or
artifact. It is not implemented as a generic `BeamSwapAction`, whose callback
semantics are deliberately refused in multi-rank tracking today.

The existing `MultiProcessExecutionPolicy` determines the supported local
backend. This feature does not add a new CUDA/MPI policy combination. Global
particle IDs and the absolute-turn counter remain the keys for stochastic
elements. All ranks enter diagnostic collectives in the same order, including
ranks whose local trial had no loss. No condition based on local loss counts
may gate a collective.

## Losses are outcomes of trials

A particle stopped by an aperture remains dead through the rest of that
trial. Restoring its finite reference at the next trial revives it. Its loss
must be recorded before the buffers are cleared; permanently removing it
would change the intended sampling ensemble.

The existing `LossRecord` is a suitable bounded scratch representation: one
slot per local particle and one counter per aperture on the active backend.
Its old lifetime assumption, "each particle is lost at most once", becomes
"at most once within this trial". The aperture transition predicate and
pre-kill coordinates keep their current meaning. Do not change the ordinary
tracking path's cumulative loss behavior.

For a reset task, the order is:

1. Capture or restore before the physical map and start clean trial counters.
2. Track the physical line; collect only the first aperture death per particle.
3. Let line and end-of-turn observers record the response before restoration.
4. Reconcile the final live/dead state against this trial's aperture counts,
   retain the trial summary and requested event rows, then mark the trial
   complete. Clear scratch only when the next trial begins.

Step 4 runs on the last turn as well. Splitting `execute!` calls cannot lose
the last trial or append it twice. Unexpected non-finite coordinates are
counted separately as unattributed failures before any restoration can erase
them. They retain the normal loss-reporting warning semantics. The initial
implementation requires `loss_report=true`; accepting `false` and still
performing reconciliation would violate that option's meaning, while skipping
the check would allow reset to hide failed particles.

Keep current-trial state and aggregate trial outcomes separate. In
particular, `current_dead - cumulative_logged` is invalid after restoration.
The last-trial `loss_summary(rep, task)` has the existing meanings of
`particles`, `live`, `dead`, `logged`, `unattributed`, and aperture attribution.
The latest execution's `phase_space_reset_summary(task)` reports completed
trials, attempted particle-trials, survivor particle-trials and total
aperture/unattributed loss events. Ratios use
attempted trials; coordinate moments from surviving particles are conditional
on survival. This feature does not silently reinterpret an ordinary
beam-moment observer as a per-particle noise-response analysis.

With an artifact, retain per-trial summaries and every aperture event
with absolute turn, global particle ID, aperture ID and pre-kill coordinates.
The same particle may appear in several turns. In memory retain aggregate
counts and the last trial only, costing $O(n_{apertures})$ independent of the
turn count, beside the bounded particle scratch. The review rejected an early
per-window vector of summary rows: a million-turn study would make diagnostic
memory grow even without an artifact. Do not accumulate coordinate or event
histories across turns in memory. Artifact presence enables detailed event rows using
the existing output convention, avoiding a redundant new public logging switch.

Use named probe groups `/reset_trials/<name>` and `/reset_losses/<name>`, read
through `read(TaskOutput(path), :reset_trials; name="reset")` and the analogous
`:reset_losses` query. Trial columns identify absolute turn, reference
epoch and capture turn, attempted particles, live, dead, logged,
unattributed, completion/fold status and per-aperture counts. Event columns
start with turn for the existing replay machinery, then reference epoch,
capture turn, completion/fold status, global particle ID, aperture ID and the
six pre-kill coordinates.
Aperture names accompany their indexed columns. Keeping reference identity in
every row makes an explicit recapture visible in a continued file rather than
silently changing the meaning of its earlier samples. The group-level metadata
does not replace these row identities.

This layout distinguishes reset trials from permanent beam loss and leaves
the existing `/losses` reader unchanged on ordinary tasks. A reset task bypasses
the permanent-loss tail writer. The new groups use the shared named-probe
bind/commit/push machinery and the [run-artifact protocol](run_artifact.md):
validate before mutation, root-only writing, row-indexed cursors, and the
existing replay rule. Calling the current whole-record writer once after the
run would retain only the last trial and is not an implementation of this
design. Empty event groups are valid: a completed trial with zero losses still
has its summary row, and the last completed trial is represented even if the
run ends without another reset.

The two optional reset products flush each trial before its particle scratch
can be reused, like coordinate snapshots. `RunArtifact.capacity` does not
batch these products; its existing producers retain their own behavior.
The trial consumer records `flush_mode=:per_trial` with an artifact and
`:none` without one, and `capacity_applies=false`. This deliberately makes
diagnostic durability visible and makes no throughput claim for optional
per-trial I/O.

## Metadata, receipts and integration

The element registers its actual method, precision, backends and runtime type,
and only contracts with implemented validators. Regenerate the registry
snapshot, add the API route and current-runtime description, and index this
note. The suite must derive coverage of the new kind rather than adding
unexplained exceptions to registry walks.

Metadata probes that currently invoke every runtime as a scalar map need a
task-only capability and a real task-level capture/restore probe for this
kind. Low-level refusal is a positive test; it is not a reason to silently
skip the new kind's precision, metadata or backend-consistency checks.

Consumer receipts identify actual capture versus restore, absolute turn,
captured turn/reference generation, local and global particle counts, backend
and shard interval. Trial receipts identify completed outcomes. Receipts are
emitted after the corresponding operation succeeds, never from a requested
configuration alone. The snapshot state remains execution data, not an
`ElementSpec` parameter or artifact copy of all coordinates by default.

## Validation and completion

The primary oracle is repeated explicit one-turn tracking without a reset:
for each absolute turn $i$, independently copy the original $X_0$, track the
original physical lattice, and read the result. Compare that with turn $i$ of
one run containing the reset. The reference does not call any reset helper.
Assert equal noise values and RNG identities before judging response equality,
so agreement cannot come from repeating turn zero or disabling modulation.

The matrix covers:

- no noise; an asymmetric prescribed `TurnTable`; white noise; correlated
  noise; and a per-particle stochastic element to exercise MPI index offsets;
- every particle and all six output coordinates per trial, exact restoration,
  exact alive/dead decisions away from aperture boundaries, event identity and
  pre-kill coordinates, and correctly conditioned statistics;
- `Float32` and `Float64`, CPU worker counts, CUDA storage and launches, and
  real MPI launches with one, two and four ranks and an uneven partition;
- one run versus continuation calls, nonzero starting turn, zero turns,
  snapshot independence, separate tasks sharing a spec, explicit recapture,
  changed beam/storage/partition refusals, invalid placement and method,
  low-level and optics refusals, and the final-trial flush;
- repeated loss of one particle, loss then survival of one particle,
  simultaneous aperture and unattributed losses, all-lost and no-loss trials,
  and an empty-loss rank participating in global accounting;
- artifact readback, no duplicate rows across chunks, recorded noise and reset
  receipts, and safe rejection/replay behavior for continued output.

Copies are bitwise checks. Deterministic same-backend reference paths use
exact comparison where their arithmetic is unchanged; otherwise bounds are
stated in coordinate scales and justified by the physical kernels' established
backend tolerances. Cross-backend physics agreement never borrows a tolerance
from the reset copy, which has no arithmetic. Negative controls omit reset,
alias the reference, or repeat turn zero and must fail the corresponding
oracle before the check counts as effective.

Run focused probes before the full four-thread gate with CUDA active,
including metadata/help, configuration effectiveness where touched, source
closure/docstring tripwires, backend consistency and actual MPI launches.
End with a targeted neighbour audit of loss accounting, the normal no-reset
path, nested/wrapped line discovery, observer ordering, artifact continuation,
and the unsupported strong-strong path. Commit the measured counts, tolerances,
skips and provenance with the code; a green claim names what actually ran.
