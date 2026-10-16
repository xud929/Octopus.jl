# U3 reading-unit report: `src/tasks/Tasks.jl` (comprehensive audit, crab-cavity noise campaign, 2026-10-16)

Repository: Octopus, main checkout `/cfs/ad/dxu/Library/Julia/Octopus` at `3126908`.
Unit: U3. Written for a reader who was not in the session. Every claim below is a
LEAD, not a finding; the auditor owns the judgement and the cross-file seams.

## 1. Region and provenance

Region: `src/tasks/Tasks.jl` in full, 1978 lines, read line by line (five
`sed`/`awk` chunks, no skipping), with emphasis on the campaign diff
`git diff 6995151 3126908 -- src/tasks/Tasks.jl` (+78/-16: the
`_warn_duplicate_turn_tables` warning and its call from
`_warn_duplicate_turn_modulation_streams`; `turn_modulation_columns` handed to
`prepare_run_artifact!`; the `_tm_sink` resolution and the
`_tm_begin_turn!`/`_tm_end_turn!` bracket in the general loop; the `sink`
keyword threaded through `_execute_tracking_plan_turn!` and the five
`_execute_tracking_segment_turn!` methods; comments on the fast loop).

Seams READ (to understand what the region calls; not audited as regions):
`src/tasks/RunArtifact.jl` (`prepare_run_artifact!`, `TurnModulationRecorder`,
`_turn_modulation_sink`, `_record_turn_draws!`, `_tm_begin_turn!`,
`_tm_end_turn!`, `_ra_flush_turn_modulation!`, `_ra_create_turn_modulation_series!`,
`finalize_run_artifact!`, the `:turn_modulation` readers);
`src/elements/turn_modulated.jl` (`update`/`update_line` with sink,
`_check_turn_window`/`_check_rule_window`, `_each_turn_rule_spec`,
`_collect_turn_modulation_ids!`, `_collect_turn_tables!`,
`_turn_modulation_provenance!`, `_turn_modulation_columns!`, `_push_rule_slot!`,
`TurnTable`, `SpectralNoise`, `_resolve_turn_rule`, `_spectral_table`,
`_spectral_synthesis`, `_rule_stream_id`); `src/elements/crab_cavity.jl`
(`_turn_modulation_wrap`, `_turn_rule_values`); `src/tasks/strongstrong/interface.jl`
(constructor line 2400, window check 2584-2592, receipt 2639-2644, columns
2669-2672, loop sinks 2832-2882, `_execute_strong_strong_segment!` 3109-3122,
`_execute_strong_strong_segment_pair!` sink forwarding); `src/knobs/Knobs.jl`
and `src/knowledge/Knowledge.jl` (`knob_epoch`, `_spec_epoch` and their bump
sites); `src/elements/beam_line.jl` (`_has_knob_parameters` on placements);
`src/math/counter_rng.jl` (`claim_rng_id!`); `src/track/Track.jl`
(`TrackingContext`). Reference documents read: `docs/design/turn_modulation.md`
4.4-4.5, `docs/design/turn_modulation_record.md` D1-D10 and section 9,
`docs/design/spectral_turn_table.md` section 3 (D1-D11),
`docs/history/turn_modulation_record_2026_10_15.md` section 4.

EXECUTED (read-only probes; scripts and logs under
`result/audit_crab_noise_2026_10_16/U3/`, `u3_common.jl` the shared prelude;
`julia --project=. --threads=4 <script>`; CPU threads, plus one CUDA arm):

| script | hypothesis | log |
|---|---|---|
| `p1_alignment.jl` | H1 turn alignment, sink plumbing, every loop/segment kind, CUDA arm | `p1_alignment.log` |
| `p2_warnings.jl` | H2 the two constructor warnings, 12 cases | `p2_warnings.log` |
| `p3_recompile.jl` | H3 recompile triggers vs spectral re-synthesis and seed | `p3_recompile.log` |
| `p4_crash.jl` | H4 crash path (in-line action, task observer, task action, short table, no recorder) | `p4_crash.log` |
| `p5_seed.jl` | H5 the deprecated `seed` keyword | `p5_seed.log` |
| `p6_receipt_before_refusal.jl` | out-of-hypothesis: receipt recorded before refusals | `p6_receipt_before_refusal.log` |

The suite was not run by this unit (the auditor's gate, not a reading unit's).

## 2. Leads

### LEAD U3-1 [low, confidence high] src/tasks/Tasks.jl:207
Claim: `TrackingTask(...; seed=...)` warns "deprecated" and then IGNORES the value, and neither the warning text nor any test says so.
Mechanism: the keyword (line 180) is consumed only by `seed !== nothing && @warn "... deprecated; use set_global_rng!(seed=...) instead." seed` (line 207); nothing reads it afterwards, the task's draws come from the global seed in force, and `global_rng_seed()` is unchanged. The repository's own precedent for keywords that no longer act is to RETIRE them with an `ArgumentError` naming the replacement (`loss_log`, `luminosity`, lines 192-202; `luminosity_path`/`luminosity_append` in the strong-strong constructor); this one has been "deprecated" since the initial commit (60da747, 2026-07-15) and `grep -n "seed keyword is deprecated" test/runtests.jl` finds no pin. The twin at `src/tasks/strongstrong/interface.jl:2401` behaves identically (seam). Under the Invariants this is a non-default request that is honoured nowhere; the warning makes it non-silent but does not say the value is unused.
Repro: `julia --project=. --threads=4 result/audit_crab_noise_2026_10_16/U3/p5_seed.jl` prints `coordinates seed=123 == seed=456: true; == no keyword: true` and `global_rng_seed() ... unchanged by the keyword: true` (a 1-harmonic crab cavity with `WhiteNoise(rng_id=7)`, 3 turns, one particle; three tasks built with `seed=nothing/123/456` under `set_global_rng!(seed=0x5eed)` give bitwise-equal coordinates). Inline: build the three tasks, `execute!` 3 turns each on fresh identical reps, compare `coordinate_arrays`.

### LEAD U3-2 [low-medium, confidence high; design-accepted, flagged for the owner] src/tasks/Tasks.jl:1310
Claim: `set_global_rng!(seed=...)` between two `execute!` calls is honoured by the live rules from the next turn but NOT by a `SpectralNoise` table in the same line, with no warning at `execute!`; the receipt's canonical name is the only evidence.
Mechanism: `_runtime_entries` (1297-1323) returns the cached compiled line unless the knob epoch moved on a knob-dependent line, the spec epoch moved, or the loss record's identity changed (1310-1311); a seed change bumps none of these, so `_resolve_turn_rule` (turn_modulated.jl:833, `seed = global_rng_seed()` at compile) is not re-run and the compiled `TurnTable` keeps the bytes synthesised under the old seed, while `WhiteNoise`/`PinkNoise` read `ctx.seed` from the new global every turn. The SpectralNoise docstring and `spectral_turn_table.md` D11 state exactly this ("the one stated difference"), so it is a design decision; the lead is that nothing at the consumer boundary warns when `global_rng_seed() != the seed in the compiled table's name`, and a user has no public way to force the re-synthesis short of a spec mutation, a knob step or a new task. Measured: the white slot's recorded series equals its replay under the NEW seed in the same `execute!` whose table name still says `seed=1001`.
Repro: `julia --project=. --threads=4 result/audit_crab_noise_2026_10_16/U3/p3_recompile.jl`, step "(c) set_global_rng!(2002) with NO recompile trigger": `recompiled=false`, `digest == (a): true`, `table name=spectral(flat; ... seed=1001, rng_id=11, slot=1, ...)` while `global seed now 2002`, and `white slot series == replay under the CURRENT global seed: true`. Inline: a crab cavity with `phase_noise=(SpectralNoise(1e-4,(1/64,1/4),:flat; rng_id=11, turns=256),)` and `strength_noise=(WhiteNoise(1e-4; rng_id=12),)`, `execute!` 4 turns, `set_global_rng!(seed=2002)`, `execute!` 4 turns under `with_execution_audit`; compare the `:turn_modulation` receipt's table `name` and digest across the two calls.

### LEAD U3-3 [low, confidence high] src/tasks/Tasks.jl:453
Claim: a `SpectralNoise(rng_id=k)` on one element and the OFFLINE `spectral_turn_table(...; seed=global_rng_seed(), rng_id=k, slot=s)` on another, where `s` is the slot the rule will resolve into, compile to identical tables and neither constructor warning fires.
Mechanism: both warnings run on SPEC-level rules at construction (`_warn_duplicate_turn_tables` collects `rule.digest`, which a `SpectralNoise` does not have yet; `_warn_duplicate_turn_modulation_streams` collects `rule.rng_id`, which a `TurnTable` does not have), so the pair contributes one digest entry and one id entry and `length(ids) == length(unique(ids))` holds in both collectors; the equality only exists after `_resolve_turn_rule` synthesises the rule's table under the same `(seed, rng_id, slot)`. `claim_rng_id!` cannot help: it only raises the counter (`atomic_max!`), a second explicit claim of an id is never refused (measured, p2 case (l)). The brief's question "where is that case caught?" for a SpectralNoise PAIR with one explicit id is answered positively (p2 case (d): the stream warning fires on the spec-level `rng_id`); this mixed spectral-plus-offline shape is the one that is not caught. Edge case: the author must copy the global seed into the offline call by hand.
Repro: `julia --project=. --threads=4 result/audit_crab_noise_2026_10_16/U3/p2_warnings.jl`, case "(f)": `digest-warnings=0 ... stream-warnings=0` at construction, then `compiled digests: A=0x1c0f3c1489874a56 B=0x1c0f3c1489874a56; equal=true` with identical canonical names (`seed=24301, rng_id=7, slot=1`). Inline: `offline = spectral_turn_table(:flat, 1e-4, (1/64,1/4); turns=256, seed=global_rng_seed(), rng_id=7, slot=1)`; build `TrackingTask((crab(SpectralNoise(1e-4,(1/64,1/4),:flat; rng_id=7, turns=256)), disp, crab(offline)))` under a `TestLogger`; compare `Octopus._slot_rules(compile_runtime(spec).rule)[1][2].digest` for both specs.

### LEAD U3-4 [low, confidence high; informational, documented as "the rows decide"] src/tasks/Tasks.jl:1123
Claim: a task-level observer that throws at turn `t` leaves the `series` with rows through `t` while the ledger's `current_turn` is `t - 1`; the two progress marks disagree by one row in the direction opposite to the strong-strong loop's.
Mechanism: in the general loop `_tm_end_turn!(_tm_sink, turn)` (1123) closes the row before `run_observers!(task.observers, ctx, rep)` (1124) and before `art.current_turn = Int64(turn)` (1126); the crash path then finalizes with `rec.rows` complete rows and `art.current_turn` as last stamped. The row for turn `t` is physically right (the kick ran), and `RunArtifact.jl`'s reader docstring says the row count is authoritative, but that docstring describes the strong-strong loop's stamp-before-the-turn order (ledger ahead of rows); here the rows run ahead of the ledger. An in-line action throwing mid-turn and a task-level action throwing before the turn both leave rows = `current_turn + 1` consistently (measured 3 and 2).
Repro: `julia --project=. --threads=4 result/audit_crab_noise_2026_10_16/U3/p4_crash.jl`, variant "(3) TASK-LEVEL observer throws at turn 3": `ledger: ... current_turn=[2]` and `series ... rows=4 values=[0.001, 0.002, 0.003, 0.004]`; variants (1), (2), (4) print `rows=3`, `current_turn=[2]`. Inline: `struct O <: AbstractBeamObserver end; Octopus.observe!(::O, ctx, rep) = ctx.turn == 3 && error("x")`; `TrackingTask((coll, crab(table), disp); hooks=(ScheduledObserver(O(), AlwaysSchedule()),), artifact=RunArtifact(p; record_turn_modulation=true))`, `execute!(turns=8)`, then `read(TaskOutput(p), :execution).current_turn` against the series length.

### LEAD U3-5 [low, confidence high] src/tasks/Tasks.jl:708
Claim: the fast-loop predicate is hand-copied twice -- in the `:tracking_turn_timing` receipt (`fast_path=`, 708-709) and in the branch that actually selects the loop (975-976) -- so a change to one copy would make the receipt lie silently about which loop ran.
Mechanism: both read `isempty(task.actions) && isempty(task.observers) && !_has_line_hooks(runtime_entries) && task.artifact === nothing`, with no shared helper and no tripwire that the two agree; the Invariants' "do not hand-copy knowledge ... derive it from one source" names this shape, and the receipt's documented purpose (701-704: "the only way a test can assert the instrument ran on the loop the benchmark takes") makes its agreement with the branch load-bearing. Today the copies agree (measured).
Repro: `julia --project=. --threads=4 result/audit_crab_noise_2026_10_16/U3/p1_alignment.jl`, section "(g)": `fast task: timing receipt fast_path=true`, `artifact task: fast_path=false`, `coordinates after 5 turns bitwise equal (fast vs general): true`. Inline: `grep -n "task.artifact === nothing" src/tasks/Tasks.jl` shows the two sites; edit one and the receipt no longer names the loop taken.

### LEAD U3-6 [low, confidence high] src/tasks/Tasks.jl:720
Claim: the `:turn_modulation` receipt (and the `:tracking_turn_timing` receipt) is recorded before three refusals that can still stop the run with no turn tracked: the hidden-strong-beam refusal (1016-1029), the `:fused`-on-CUDA refusal (1073-1080) inside `_execute_tracking_task!`, and `prepare_run_artifact!`'s own refusals (label mismatch, provenance-slot collision).
Mechanism: U1-5 (2026-10-13) moved `_reject_unsharded_tracking_features` ahead of both receipts for exactly this reason ("a run refused here leaves no receipt claiming it ran"); the other refusals remained below them. The design accepts a receipt that names the resolved window for a run that CRASHED mid-way (711-719), which is a different case from a run refused before its first turn. Not in the campaign diff (pre-existing shape); the campaign's `turn_modulation_columns` argument did not add a new refusal ahead of the receipt on the `execute!` path (the columns/entries length check inside `_ra_write_turn_modulation!` cannot fire there, both walks run over the same `runtime_elems`).
Repro: `julia --project=. --threads=4 result/audit_crab_noise_2026_10_16/U3/p6_receipt_before_refusal.jl`: case (1), a `ThinStrongBeamSpec(...; x_offset=1e-4)` beside a modulated crab cavity with an artifact, prints `:turn_modulation receipts recorded: 1 (window 3 turns); file created: false; next_turn=0`; case (2), `append=true` onto a file whose luminosity labels differ, prints `receipts recorded: 1; ledger rows after: [0]`; case (3), the window refusal (which sits before the receipts), prints `0`.

Observations that are style, documented behaviour or cost only (not leads):
- The stream warning's text "their per-turn draws are identical" is over-strong when the shared id sits on different slot numbers of the two elements, or on a `SpectralNoise` and a `WhiteNoise` (p2 case (j): the warning fires, the two never share a counter-RNG cell). Conservative in the right direction; pre-existing wording.
- `RunArtifact(path)` with the default `append=false` recreates the file on the second `execute!` of the same task: the first window's series is gone (p1 (j): ledger `[5]`, one provenance entry). Documented in the `RunArtifact` docstring ("recreates the file per execute!").
- Every new `rep` OBJECT recompiles a line that has an aperture (loss-record identity, 1310-1311 with `_ensure_loss_record!` 1348), and each recompile re-synthesises every `SpectralNoise` table: 0.045 s at 2^20 turns on this box (p3 (g), (h)). Documented in the SpectralNoise docstring (review F5). Without an aperture a new rep does not recompile.
- `turns = 0` with `start_turn > length(table)` is refused by the window check though no turn would run (`first_turn + 0 <= length` at turn_modulated.jl:1073); a `turns=0` reposition is otherwise a no-op. Nit, not probed.
- The crash path computes `_task_loss_summary(task, rep)` twice (753 and 767), one `O(N)` reduction each; cosmetic.
- In the crash path `_report_losses(..., wrote_file = task.artifact !== nothing)` suppresses the console summary even when the crash came before `prepare_run_artifact!` opened the file (so nothing was written); only the per-collimator console lines are lost, the `unattributed` warning still fires. Pre-existing; nit.

## 3. Clean list (what was compared or measured)

H1, turn alignment and sink plumbing (p1, all `RESULT` lines `true`):
- Exactly four call sites of the pure hook exist in `src/` (`grep -rn "update_line(\|[^_]update(" src/` outside its definition file): the three element-carrying segments (1849, 1857, 1865) pass `sink`; the fourth is the fast loop (1239), taken only when `task.artifact === nothing` (975-976), and `artifact` is a field of the immutable `TrackingTask` struct, so no task can acquire an artifact after construction. A task with an artifact therefore cannot reach the fast loop; an artifact-less modulated task takes it and realises without a recorder, which is correct (p1 (g): `fast_path=true`, no plan built, coordinates bitwise equal to the general loop's).
- General loop, `FusedSegment` only: rows `== table[first+1 : first+rows]` and receipt `first_turn ==` artifact `first_turn` for the first call (0, 5 turns), the second call on the same task (5, 3 turns) and a `start_turn=10` reposition (10, 4 turns); `task.next_turn == 14` after (p1 (a)-(c)).
- Plan split by an in-line `ObserverSegment` (two modulated cavities, `start_turn=3`): both recorded in line order (p1 (d)); `IsolatedSegment` present (strong beam + artifact): both cavities recorded (p1 (e)); `LuminousFusedSegment` (`luminosity_tracking=:fused`, CPU) carrying the cavities: recorded (p1 (f)).
- The kick used the recorded row: for `k in (0, 7, 13)`, `execute!(turns=1, start_turn=k)` with the table records `[table[k+1]]` and gives coordinates bitwise equal to a static cavity at `phase = table[k+1]` (p1 (h)).
- CUDA arm (`CUDAExecutionPolicy`, device rep, `start_turn=2`, 5 turns): series `== table[3:7]`, coordinates equal to the CPU run (max |diff| 0.0 on all six) (p1 (i)).
- Window check before any turn and before the receipts: `_check_turn_window` at 674 runs before `_activate_resolved_policy!`, the receipts and `prepare_run_artifact!`; a short table at the second `execute!` throws with the table, slot and absolute window named, leaves `next_turn` unadvanced, appends no ledger row, and the next valid call records `first_turn=5` with rows `table[6:8]` (p4 (5)).
- `_survey_rebind(::TurnModulated)` (1494-1497) rebuilds from `base` with the already-resolved rule: no second synthesis at survey, and the U2-1 double-count fix holds by construction.

H2, the warnings (p2, every case `as expected`):
- One table on two slots of one cavity, phase+strength included: silent (a, a2). Same table object on two cavities, and two table objects of equal bytes: one digest warning naming both sites and the digest (b, b2). Distinct tables: silent (c). One spec object placed twice in a `BeamLine`: two elements, warns (g). `StrongStrongTask` with equal digests across its two lines warns through the one call; distinct digests silent (h, h2).
- Two `SpectralNoise` with one explicit id on two cavities: the stream warning (d); explicit + auto: silent (e); one explicit id on both slots of ONE cavity: silent and the compiled digests differ, the slot is in the key (k, F1 holds).
- Both warnings fire at construction only: 0 on the first `execute!`, 0 on an `execute!` after a knob step that recompiled (i).
- `_collect_turn_tables!` and `_collect_turn_modulation_ids!` share `_each_turn_rule_spec`, which reads `_effective_spec(entry)` (override-merged, U1-2) and descends `ElementSpec{:line}`; hooks and non-spec entries fall to the no-op (by reading).

H3, recompile identity vs re-synthesis (p3):
- Triggers enumerated from 1310-1311: knob epoch (knob-dependent lines only; `_has_knob_parameters` covers placement overrides and nested lines, beam_line.jl:160-165), spec epoch (any in-place `ElementSpec` or `LineEntry` mutation anywhere), loss-record identity (lines with apertures: a new rep object, a shape/backend change, a change of `want_slots`). Each recompile empties `plan_cache` (1321).
- Knob step under one seed: recompiled, digest unchanged (deterministic re-synthesis) (a, b). Knob step after a seed change: recompiled, new digest, name carries `seed=2002` (d). Unrelated spec mutation: recompiled, digest unchanged under the same seed (e). Knob step on a knob-free line: no recompile (f). New rep: recompile with an aperture, none without (g).
- The receipt's provenance digest and name are those of the compiled table in force (read from `runtime_elems`), so the receipt is honest about the seed used (c, d).

H4, the crash path (p4):
- In-line action throwing between two cavities at turn 3 (partial row: element 1 recorded, element 2 not): the injected error propagates unchanged, `next_turn` stays 0, the artifact is closed and the recorders emptied, both series hold exactly 3 complete rows (turns 0-2), the partial values are dropped, the reader warns once per short series, `/losses` carries both loss rows and the reconciliation summary (1); identical with `capacity=2`, where a flush had fired mid-window (2). Task-level action at turn 3: rows 3, `current_turn` 2 (4). Without the recorder the crash still delivers `/losses` (6).
- `_tm_end_turn!`'s miscount branch truncates each buffer to `rows * ncols` before raising, so the finalize flush stays rectangular (by reading; the suite's recorder testset pins "a turn closed with an element missing is refused with its partial values dropped").
- No shipped rule can throw per turn (a `SpectralNoise` is evaluated at compile only; a `TurnTable` out of range is refused before the window), so the mid-turn injection used hooks.

H5, the `seed` keyword: see LEAD U3-1 (measured ignored; the StrongStrongTask twin warns identically).

Other reading checks that came out sound: `_task_execution_window` (turns >= 0, Int/Int64 overflow refusals, `start_turn` type refusal); the segment methods are the only consumers of the `sink` keyword and `ObserverSegment`/`ActionSegment` accept and ignore it; `_turn_modulation_sink(art, 1)` is resolved once per `execute!` after `prepare_run_artifact!` emptied and rebuilt the recorders, and resolves to `nothing` on non-root ranks (no file, no recorders) so they realise without recording; the `turn_modulation_columns` and the receipt entries come from one `runtime_elems` walk each, aligned by `_ra_write_turn_modulation!`'s length checks.

## 4. Unchecked, and why

- Multi-rank execution (non-root sink `nothing`, root-only file, the crash path's per-rank loss flush): read only; no `mpiexec` was launched by this unit (the suite's two-rank arm of the one-particle probe covers the recorder under MPI).
- The strong-strong loop body in `src/tasks/strongstrong/interface.jl` beyond the call signatures and sink forwarding: another unit's region; the seam is that `_execute_tracking_plan_turn!` (3120) and `_execute_strong_strong_segment_pair!` forward `sink1`/`sink2` per beam.
- Stateful rules (successor persistence across plans and calls): none shipped; the docstring at 637-650 states the limitation.
- `Float32` lines, `GaussianStrongBeam` in the isolated/luminous paths, the `:fused`-on-CUDA refusal (read only; it sits after the receipts, LEAD U3-6).
- The HDF5 extent arithmetic of `_ra_flush_turn_modulation!` beyond its measured behaviour at `capacity` 2 and 64.
- The suite's gate: not run by this unit.

## 5. Files

Report: `result/audit_crab_noise_2026_10_16/U3_report.md`. Scratch:
`result/audit_crab_noise_2026_10_16/U3/{u3_common,p1_alignment,p2_warnings,p3_recompile,p4_crash,p5_seed,p6_receipt_before_refusal}.jl`
with matching `.log` files and the probe artifacts `*_<pid>.h5`. No repository
file was modified.
