# Neighbour audit — the retirement sweep, reader, and capacity unification (2026-08-18, second audit of the day)

Owner-requested neighbour audit of the step-4 campaign: the standalone-writer
retirement, the `TaskOutput` reader (`read(out)` contents / `read(out, kind;
name/column/turn)` / `read(out, :all)`), the artifact-capacity unification,
and the strong-strong finalize-order fix. Method: the changed surface's
NEIGHBOURS — the sibling code paths, the prose that describes the retired
machinery, the helper functions the deletions orphaned, and the documents
that must stay findable — swept by targeted grep and read, fixes applied
beside the findings.

## The bug the campaign's own gate caught (context, verified fixed)

The strong-strong `execute!` closed the artifact BEFORE
`_finalize_strong_strong_line_observers!` flushed line-placed probe tails,
so a moment view's buffered rows arrived at a closed file
(`getindex(::Nothing, ::String)`). The suite's strong-strong artifact cases
all used bare lines; the EXAMPLE-runner testset caught it — the argument for
keeping the examples in the gate. Fixed with observers-flush-first on both
success and crash paths, pinned with exactly the failing shape (run-artifact
testset case 4d: SS task, line-placed `MomentObserver(; name=...)`, tail
flushed only at finalize), and `_ra_push_probe_rows!` now raises a NAMED
ordering-violation error instead of the cryptic `getindex`.

## F1 — the weak-strong twin: verified clean

The same-shaped risk on the other task: `_execute_tracking_task!` finalizes
task-level and line observers INSIDE itself, on both the success path
(finalizer failure raises) and the failure path (best-effort, warn, never
mask) — and both run before the outer `execute!`'s artifact close on either
path. Correct order; no change.

## F2 — stale prose describing the retired machinery: eight sites fixed

Living docstrings and comments still narrating the text-file world, updated
in place (historical narration in `docs/history/` untouched, as ever):

- `interface.jl` module docstring, `luminosity_schedule` bullet: skipped
  turns are "omitted from the task luminosity file" → leave no row in the
  artifact's luminosity channel.
- `spectral.jl`, the same phrase in three places (solver docstring, the
  `luminosity_schedule` schema description, the compute-gate comment).
- `StrongStrongTask` struct, artifact-field comment: still called the field
  "migration step 1" with "the text observer above may run alongside as the
  live mirror" — the mirror is retired; the artifact is the one output.
- The U4-4/F2 validate-before-commit comment in `execute!`: its "So:"
  paragraph described the retired text planner in the present tense; now
  past tense, closing with what the artifact keeps of that shape (prepare
  validates — label match, torn-tail truncation — before any probe binds).
- `Tasks.jl` weak-strong turn loop: "the text observer's positive filter"
  → the positive filter carried over FROM the retired text observer.
- `pic_cpu.jl` N7 comment: Float64 "is what the task layer already writes
  to .lum files" → writes into the artifact's luminosity channel.
- `validation/tracking_context_policy_consistency.jl` header: "luminosity
  observers explicitly isolate weak-strong elements" → the artifact's
  luminosity channel requests the same isolation.

## F3 — retired-symbol sweep: only intentional remnants

`LuminosityObserver`, the `read_*` family, `artifact_contents`,
`TaskOutputFile`, `loss_log`, `luminosity_path/append`, the per-observer
capacities: every hit in the living tree is a retirement stub (kwargs kept
to throw the migration pointer), a suite pin of those errors, or historical
narration attached to a still-live check (the U3-5/U5-4 metadata-validator
comments). `:LuminosityObserver` is pinned absent from `names(Octopus)`.

## F4 — orphan sweep: clean

Every deleted helper is gone without survivors (`_flush_bpm_rows!`,
`_write_task_loss_log`, `_moment_append_continue!`,
`_initialize_hdf5_moment_file!`, `_moment_execution_slot!`,
`_discard_replayed_snapshots!`, the text planners);
`_SNAPSHOT_ARTIFACT_COLUMNS` lives with its one binder; the path registry
(`_register_observer_path!`) has exactly one live writer left — the
artifact, by artifact identity — which is what closed the writer-registry
ledger row. The `:strong_strong_output` execution receipt carries
`(artifact, append)`.

## F5 — findability: verified

`docs/design/run_artifact.md` indexed in `docs/README.md`, its status
header carrying the implemented-beyond-the-wording correction;
`docs/public_api.md` rewritten to the `TaskOutput` surface; the validation
README entries updated where behaviour changed (schedule-output,
pic-option, crossing anchor, diagnostics benchmark) and confirmed still
true where generic (plan-consistency, tracking-context). The
`.ipynb_checkpoints` copies under `docs/design/` are untracked and
gitignored — local Jupyter artifacts, not repo content.

## F6 — process lesson, the gate-verdict class again

The first full-gate run of this campaign REPORTED success (background
wrapper exit 0) while its log recorded two example-script failures — the
wrapper's trailing `tail` masked `Pkg.test`'s exit code, the same
read-the-log-not-the-banner lesson the 2026-08-11 audit recorded for gate
verdicts. The relaunched gate wrapper prints `GATE_EXIT=$?` explicitly. The
verdict habit (grep the log for the failure signature before believing any
green) is what caught both this and the finalize-order bug behind it.

## Verdict

One real ordering bug (caught by the gate's example testset, fixed, pinned),
eight stale-prose sites fixed, one script-header correction, no orphaned
machinery, no unintentional survivors of the retired surface. The
full-suite gate rerun and the strong-strong timing-noise confirmation run
serialize behind this audit; the campaign commit carries both.
