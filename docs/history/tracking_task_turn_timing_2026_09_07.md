# `TrackingTask` gains per-turn timing, and the instrument it mirrors had a bug — 2026-09-07

`StrongStrongTask` has recorded per-turn wall-clock seconds on request since
early in the campaign. `TrackingTask` recorded none, so every weak-strong timing
claim in this repository rested on differencing whole-process wall clocks while
every strong-strong one rested on an instrument.

That asymmetry is not cosmetic. It produced the 2026-09-06 finding that the
64-thread weak-strong arm "degrades as the run proceeds", which was retracted on
2026-09-07 ([`weak_strong_64thread_lead_2026_09_07.md`](weak_strong_64thread_lead_2026_09_07.md))
after replication gave one series that falls and one that climbs, and returned
the record's unphysical -0.5 s intercept as +46.0 and +44.9 s. The instrument's
absence caused a wrong conclusion and cost a full investigation to undo.

## The alternative was checked and rejected on the record

The design note pointed at the run artifact's per-execution ledger: "Richer
per-turn timing joins the same group behind the existing diagnostics precedent."
It cannot serve, for two independent reasons.

**It overwrites.** `ex["current_turn"][art.execution_slot] = art.current_turn` is
one slot per `execute!`. A reader gets one `(turn, elapsed)` pair per execution,
not a series — live progress for `h5ls` during a run, not history.

**It cannot instrument its own motivating case.** `task.artifact === nothing` is
a term of the fast-path gate in `_execute_tracking_task!`. Attaching an artifact
to obtain timings moves the run OFF the loop a benchmark measures. The route is
self-defeating for exactly the workload that needed it.

`docs/design/run_artifact.md` now carries that correction.

## The trap: two turn loops whose witnesses disagree

`TrackingTask` has **two** turn loops. `_execute_fast_tracking_turns!` runs when
the task has no actions, no observers, no line hooks and no artifact; the general
loop in `_execute_tracking_task!` runs otherwise.

The two available witnesses take different ones:

| witness | takes |
|---|---|
| `test/examples/weak_strong_tracking.jl` (always attaches an artifact) | the GENERAL loop |
| `profiling/benchmark_track_cpu.jl` (builds a bare `TrackingTask(line_specs)`) | the FAST loop |

An implementer who instruments the general loop and validates against the
harness gets a green harness, a green MPI arm, a plausible per-turn series — and
a permanently empty vector for the benchmark, which is the case the work was
undertaken for. The failure is silent because the witness that would catch it is
not the witness anyone reaches for.

Two defences, because a comment is not one:

- `_execute_fast_tracking_turns!` takes `record`, `times` and `backend` as
  **required positional parameters**. It has one call site, so a half-finished
  job is a compile error rather than an empty vector.
- The `:tracking_turn_timing` receipt carries a **`fast_path`** field, so the
  suite asserts *which loop ran* rather than merely that some loop produced
  numbers. Both loops are pinned by name.

## The bug in the instrument being mirrored

`StrongStrongDiagnostics.record_turn_times` declares: "**Synchronize at
complete-turn boundaries** and record wall-clock seconds."

It took `turn_t0` at the top of the turn body and called `CUDA.synchronize()`
only at the tail. For N turns there are N+1 complete-turn boundaries, and the
**opening one was missing**: nothing synchronized between `execute!` entry and
the loop, so whatever was still queued on the device when the loop began — the
beam upload, warm-up launches, anything the caller left in flight — was pending
at `turn_t0`, and the tail `synchronize()` waited for all of it.

**Turn 1, and only turn 1, absorbed the entry backlog.** Turns 2..N were always
correct, because the previous iteration's sync had drained the queue.

Two reasons it survived: the 2026-09-06 production benchmark reads a "straight
mean over turns 100-200", which skips turn 1; and the facility has **never been
tested** — `record_turn_times`, `turn_timings` and `diagnostic_summary` appear
zero times in `test/runtests.jl`, and
`validation/strong_strong_diagnostics_consistency.jl` is not included by the
suite. Fixed in the same commit, because shipping the new instrument with a
deliberate index-1 asymmetry to the one it mirrors just creates the next wrong
comparison.

## What landed

One keyword, one meaning, two tasks: `record_turn_times` on `TrackingTask`,
read back by the same exported `turn_timings` accessor that serves
`StrongStrongTask`. Not a second spelling for one idea.

**Not** a `StrongStrongDiagnostics` field, and the reason is a defect class this
repository names first: five of that struct's six options have no consumer on
this path, and `_warn_inactive_diagnostics` filters on backend rather than on
task, so a `TrackingTask` handed `pic_timing=true` would have accepted it in
silence.

- Metadata in a new exported `tracking_task_option_schema()`, checked by
  `validate_configuration_metadata` against a CONSTRUCTED `TrackingTask(())` —
  the U5-4 rule — for key-is-a-field, default-matches-constructor, and
  names-a-consumer.
- **The fifth tree walk.** The policy, solver, schedule and observer walks were
  totalized; tasks were the family whose completeness rested on a reviewer
  noticing, and the record says that fails (U3-5 added a task option with no
  schema; U5-11 shipped a schema unexported). Added with the second task schema
  rather than after it. `StrongStrongTask` is parametric, so the walk sees a
  `UnionAll` — which is why `_concrete_octopus_subtypes` gates on abstractness
  rather than `isconcretetype`; verified in process that the walk returns both
  tasks.
- CUDA: synchronize at every complete-turn boundary **including the opening
  one**, on both tasks.
- MPI: rank-local `time_ns()`, no collective inside the loop and none in the
  accessor — `execute!` has closed its policy scope by then, where a collective
  is a silent no-op. Per-rank semantics stated in the option's own docstring: the
  turn's wall time is the MAX across ranks.
- Cleared per `execute!`, never appended: `execute!` accepts `start_turn=`, and
  under a reposition an appended index maps to no turn at all.
- Opt-in, for storage rather than CPU: 8 bytes per turn without bound, against
  workloads that run 1e7 turns.

## The payoff, measured

`OCTOPUS_BENCH_TURN_SERIES=1 profiling/benchmark_track_cpu.jl` now answers inside
one run the question that needed four runs and a subtraction:

```
WS-TURN-SERIES rank=0 turns=16 first_quarter_mean=0.0222 last_quarter_mean=0.0145 drift=0.652x
```

Falling, not climbing — the same direction the within-process windows showed on
2026-09-07, and the opposite of what differencing whole-process wall times
reported. `OCTOPUS_RECORD_TURN_TIMES=1` gives the same series from the
weak-strong harness, per rank.

This is also the first in-suite pin of complete-turn timing on **either** task.
