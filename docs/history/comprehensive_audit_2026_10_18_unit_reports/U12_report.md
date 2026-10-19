# U12: Tasks.jl

Comprehensive audit 2026-10-18, reading unit U12. Tree under audit: the main
checkout `/cfs/ad/dxu/Library/Julia/Octopus` at commit 24e8683, read-only. Every
claim below is a LEAD, not a finding. Line numbers are pointers into that
commit; each lead's Repro line is its durable identity.

## Region

- `src/tasks/Tasks.jl`, lines 1-2465 (whole file; 2465 lines). Depth: line by line.

Reference material consulted only where a lead or a check touched it (not part
of the region; read in the ranges named under Provenance):
`src/elements/beam_line.jl`, `src/tasks/RunArtifact.jl`,
`src/tasks/BeamObservers.jl`, `src/elements/turn_modulated.jl`,
`src/elements/aperture.jl`, `src/policies/Policies.jl`,
`src/track/strong_beam_track.jl`, `src/track/phase6d_track.jl`,
`src/knobs/Knobs.jl`, `src/knowledge/Knowledge.jl`, `test/runtests.jl` (grep
only), `docs/design/run_artifact.md`, `docs/theory/aperture_and_particle_loss.md`,
`docs/design/survey_and_reference_channel.md`, and the previous audit's
`LEAD_INDEX.md` (its U13 rows on Tasks.jl).

## Provenance

READ line by line (the region): `src/tasks/Tasks.jl` 1-200, 200-480, 480-760,
760-1040, 1040-1320, 1320-1600, 1600-1880, 1880-2160, 2160-2465 (every line of
the file, in nine consecutive passes).

READ in part (references, by range): `beam_line.jl` 100-200, 200-330, 330-470,
640-930; `RunArtifact.jl` 360-420, 600-700, 1160-1300, 1300-1385 (partial),
1948-1966; `BeamObservers.jl` 222-440, 905-1000; `turn_modulated.jl` 1590-1760;
`aperture.jl` 55-150, 655-700; `Policies.jl` 100-187, 185-260, 1225-1275;
`strong_beam_track.jl` 1-30 and the `_run_logical_workers` call sites;
`phase6d_track.jl` grep for the particle-id convention; `Knobs.jl` 1038-1041;
`Knowledge.jl` 149, 184, 200 (grep); `run_artifact.md` 290-315, 425-460;
`aperture_and_particle_loss.md` 160-260; `survey_and_reference_channel.md` grep;
`test/runtests.jl` grep only (tripwire list 10751-10767, lines 23735-23775,
24522-24533).

EXECUTED (probe scripts and logs, all under
`/cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U12/`):

- `probe_u12.jl` -> `probe_u12.log` (exit 0). Seven sections, numbers below:
  - P1: a `ScheduledObserver(MomentObserver(name="m"))` inside an own-state line
    (`x_offset=1e-4`) placed bare, and inside a structural line placed as the
    one member of a tuple: both `execute!` with `MethodError: no method matching
    compile_runtime(::ScheduledObserver{MomentObserver, AlwaysSchedule})`. The
    same structural line placed bare (flattened) runs and its `/moments/m` reads
    back.
  - P2: two line-placed `MomentObserver(name="dup")` with an artifact:
    `ArgumentError: duplicate probe name "dup"`; receipts recorded in the
    `ExecutionAudit`: `[:run_artifact_output, :tracking_output]`;
    `:tracking_turn_timing` absent; the `:tracking_output` receipt carries
    `artifact=<path>, channels=String[], loss_report=true`; the file exists after
    the refusal, the lock is released, and its ledger reads
    `(start_turn=[0], turns=[3], current_turn=[-1], elapsed=[0.2756], ...)`.
  - P3: `AtTurns([500])` on a 10-turn run: LINE-placed observer -> no warning
    (zero log records); TASK-hook observer -> the "cannot fire" warning;
    TASK-hook action -> no warning; LINE-placed action -> no warning.
  - P4: `MomentObserver(name="m")` between `DriftSpec(L=1.0)` and `DriftSpec(L=2.0)`:
    flat tuple -> `/moments/m` attribute `s = 1.0`, probe map size 1;
    `BeamLine("RING", ...)` (flattened to `LineEntry` placements) -> attribute
    `s` MISSING, probe map size 0.
  - P5: observer whose `finalize_observer!` throws after 3 tracked turns ->
    `next_turn = 0`. Success-path `/losses` write forced to throw (method piracy
    in the probe process, `record::Nothing`) after 3 tracked turns ->
    `next_turn = 3`, artifact handle open, lock file present; the retry is
    refused `RunArtifact at ... is already open; one artifact serves one execute!`.
  - P6 (clean check): aperture line with an action that throws at turn 2 of 5:
    `next_turn = 0`, file closed, lock gone, `loss_summary = (particles=8, live=0,
    dead=8, logged=8, unattributed=0)`, `/losses` carries 8 rows, `aperture_s=[1.0]`,
    attributes `summary_dead=8, summary_logged=8, summary_unattributed=0,
    summary_folded=0`; no warning emitted.
  - P7: `loss_summary(::Phase6DRep, record)` is called 2 times on the crash
    path of one `execute!` and 1 time on the success path.
- `probe_u12_p5b.jl` -> `probe_u12_p5b.log` (exit 0). The P5 sequence with the
  retry in separate top-level statements: 1st `execute!` (3 turns, write fails)
  -> `next_turn=3 open=true lock=true`; 2nd `execute!` -> refused "already open",
  after which `open=false lock=false` and `next_turn=3`; the reader opening the
  file while the handle was open logged `a live Octopus writer holds the run
  artifact's lock ... pid=827152` for a writer that was wedged, not writing.
  (The 3rd run in that log failing again is a probe artefact: deleting the
  positional pirated method leaves its keyword-sorter method in place.)

## Leads

### LEAD U12-1 [Moderate, confidence high] src/tasks/Tasks.jl:818
Claim: An in-line observer placed through `BeamLine` (the flattened `LineEntry` form) is invisible to the probe arc-position walk, so every probe view bound from a `BeamLine`-built lattice is written without its `s` attribute while the same observer in a flat tuple gets `s = 1.0` (hypothesis 1).
Mechanism: `_collect_spec_s!(out, entry::LineEntry, s, Kv)` handles a `LineEntry` whose spec is an `ElementSpec{:line}` (descend) or an `ElementSpec` (push when the kind matches) and otherwise only advances the arc by `_placement_length(entry)`; a `LineEntry` whose spec is a `ScheduledObserver`/`AbstractBeamObserver` is never forwarded to the probe arm `_collect_spec_s!(out, hook::Union{ScheduledObserver,AbstractBeamObserver}, s, ::Val{K})` (BeamObservers.jl:236), which matches a BARE hook only. `_append_runtime_line!(out, entry::LineEntry, ...)` (Tasks.jl:2048) DOES forward a non-spec entry to the hook path, so the compile walker and the arc walker disagree on what a placed hook is. `_line_probe_s_map(task.elements)` (BeamObservers.jl:249, bound at Tasks.jl:1379) therefore returns an empty map for any lattice built with `BeamLine(...)`, `_active_probe_s(observer)` is `nothing`, and `_ra_bind_probe!` skips the `s` attribute (RunArtifact.jl:1360). Silent: no number is wrong, a number is absent. Blast radius: `MomentObserver`, `CoordinateSnapshotObserver`, `BPMObserver(artifact=true)` placed in a `BeamLine`, in both task kinds (`interface.jl:2722` binds the same map). No suite tripwire covers the spec-side walkers' container set (a grep of `test/runtests.jl` for `_collect_spec_s!`/`_effective_spec` finds only the U1-2 radiation pin at 24533 and a cavity test at 14961).
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U12/probe_u12.jl`, section P4: the flat tuple prints `s = 1.0`, the `BeamLine` form prints `s = missing` and `probe map size = 0`. Equivalent one-liner: `length(Octopus._line_probe_s_map(Octopus._element_tuple(BeamLine("R", DriftSpec(L=1.0), ScheduledObserver(MomentObserver(name="m")), DriftSpec(L=2.0)))))` should be 1 and is 0.

### LEAD U12-2 [Moderate, confidence high] src/tasks/Tasks.jl:1385
Claim: The unfireable-schedule warning (the U13-6 fix) covers task-level OBSERVERS only; a line-placed scheduled observer, a task-level scheduled action and a line-placed scheduled action whose schedule selects no turn of the window run silently, and the warning has no test in the suite (out of hypothesis; defect classes 6 and 13).
Mechanism: `_warn_unfireable_schedules(task.observers, turns, first_turn)` is the only call and is handed `task.observers`; `task.actions` and the `LineObserverEntry`/`LineActionEntry` hooks of `runtime_entries` are never checked, while the docstring (Tasks.jl:1530-1543) says "a scheduled hook". The line observers' prepare (`_prepare_moment_observer!`, BeamObservers.jl:955) computes the same `_scheduled_turns` and stores `planned_records = 0` without a word. `grep -nE '_warn_unfireable_schedules|cannot fire in this run|selects no turn|observe nothing' test/` matches nothing, so the fix landed with no regression test and its coverage gap was never visible.
Repro: `probe_u12.jl` section P3: with `AtTurns([500])` on `execute!(...; turns=10)` the log-record counts are 0 (line observer), 1 (task observer), 0 (task action), 0 (line action); expected 1 in all four.

### LEAD U12-3 [Moderate, confidence med] src/tasks/Tasks.jl:1051
Claim: A failure in the success path's output step (`_ra_write_losses!` or `finalize_run_artifact!` after `task.next_turn[] = next_turn`) advances the stored turn, contradicting the `execute!` contract "A failed call does not advance the stored turn", and leaves the run artifact open with its sidecar lock held, so the task's next `execute!` is refused with "already open" and a reader meanwhile sees a "live writer" that is wedged (hypothesis 2).
Mechanism: Lines 1051-1077 run after the `try`/`catch` (1000-1050) returns: the stored turn is assigned first, then `_with_resolved_policy(active) do ... _ra_write_losses!(...; folded=true); finalize_run_artifact!(task.artifact) end`. An exception there propagates out of `execute!` with nothing closing `art.file` or releasing `<path>.lock` (`finalize_run_artifact!` is the only closer and is what threw or was skipped). The comment at 1067-1070 says "A failure HERE is the failure" -- correct -- but neither the documented turn rule nor the artifact's close-on-every-path rule (`run_artifact.md` 425-435: the lock is removed "on every path that closes the artifact") holds on this path. The observer-finalizer failure after completed tracking takes the other branch (`finally` -> `catch` at 1000) and does NOT advance the turn (P5), so the two output-failure cases disagree. The next `execute!` on the task is refused by `prepare_run_artifact!`'s "already open" check (RunArtifact.jl:621) and only then does the catch path close the file, so the task self-heals after one spurious refusal.
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U12/probe_u12_p5b.jl`: prints `after 1st: next_turn=3 open=true lock=true`, then `2nd execute! (retry): RunArtifact at ... is already open`, then `after 2nd: next_turn=3 open=false lock=false`. Expected: either `next_turn=0` (the documented rule) or, if advancing is the intended semantics, the docstring corrected and the artifact closed with its lock released before the error propagates.

### LEAD U12-4 [Minor, confidence high] src/tasks/Tasks.jl:1376
Claim: The `:tracking_output` receipt is recorded ahead of two refusals that can still stop the run with no turn tracked -- the observers' prepare (a duplicate probe name) and the `:fused`-on-CUDA refusal -- so a refused run leaves a receipt claiming its artifact opened with channels, against the rule the same function states for the other two per-run receipts (hypothesis 2, receipts before validation).
Mechanism: Order in `_execute_tracking_task!`: hidden-beam refusal (1341) -> `prepare_run_artifact!` (1365) -> `_record_execution!(:tracking_output, ...)` (1376) -> `prepare_observers!`/`prepare_line_observers!` (1382-1383, which throw on a duplicate name through `_ra_bind_probe!`) -> fused-on-CUDA `throw` (1406) -> `_record_tracking_receipts!` (1415). The docstring of `_record_tracking_receipts!` (1262-1283) lists exactly those refusals as the ones the receipts must follow "so a refused run leaves no receipt claiming it ran" (U3-6), and the S4-10 comment at 1370-1375 claims "A prepare refusal leaves no output receipt claiming a run", which is true of the ARTIFACT's prepare only. The artifact itself is finalized by the catch path with a ledger row for a run that never tracked; that row is self-labelled (`current_turn = -1`) and matches the U1-3 rule for crashes, so the receipt, not the row, is the inconsistency.
Repro: `probe_u12.jl` section P2: `receipts recorded: [:run_artifact_output, :tracking_output]` with `has :tracking_turn_timing receipt: false` after `ArgumentError: duplicate probe name "dup"`. Expected under the stated rule: no `:tracking_output` receipt.

### LEAD U12-5 [Minor, confidence high] src/tasks/Tasks.jl:859
Claim: An in-line hook inside a line that compiles WHOLE -- an own-state line placed bare, or any `BeamLine` placed inside a tuple or vector -- is refused at the first `execute!` with a raw `MethodError` from `compile_runtime(::ScheduledObserver)` rather than by name, because the task's container rules and the line compiler disagree on whether a hook is a line member (hypothesis 1; cross-file seam with `beam_line.jl:728`).
Mechanism: `_element_tuple(line::ElementSpec{:line})` flattens a bare structural line (so its hook entries reach `_append_runtime_line!(out, entry::LineEntry, ...)`, which routes a non-spec entry to the hook path) but keeps an own-state line whole, and `_element_tuple(elements::Tuple)`/`(::AbstractVector)` never flattens a line nested inside; such a line falls to `_append_runtime_line!(out, element, hook_counter)` (2058) -> `_runtime_or_existing` -> `compile_runtime(::ElementSpec{:line})` (beam_line.jl:728), whose `Tuple(compile_runtime(e) for e in line_entries(resolved))` has no method for a hook entry. `BeamLine`'s docstring admits hooks as children, and `TrackingTask`'s says line-level hooks can appear inside `elements`, so the shape is a documented one; the refusal is loud but names nothing (not the limitation, not the remedy). The probe arm of `_collect_spec_s!` (BeamObservers.jl:236) would also mis-position such a hook if it ever compiled, and a hook inside a `CompositeLine` has no segment to run in (`_append_tracking_segments!` sees `PhysicsEntry`s only), so the honest outcome is a by-name refusal at construction.
Repro: `probe_u12.jl` section P1: both "own-state line placed bare" and "structural line placed inside a tuple" print `MethodError: no method matching compile_runtime(::ScheduledObserver{MomentObserver, AlwaysSchedule})`; the flattened control prints OK. Expected: an `ArgumentError` naming the hook, the line and the remedy, ideally from `TrackingTask(...)` rather than `execute!`.

### LEAD U12-6 [Minor, confidence high] src/tasks/Tasks.jl:1036
Claim: The crash path computes the task's loss summary twice -- once for `_report_losses` (1023) and again as `crash_summary` for the artifact write (1036-1040) -- so a crashed run pays two O(N) non-finite reductions (two device reductions on CUDA) where the success path pays one (hypothesis 3; cost only, no wrong number).
Mechanism: `summary` from the first `try` is scoped to that block and not reused; the second `try` recomputes `_task_loss_summary(task, rep)` to tolerate the first having thrown, although a `summary` that was computed can simply be carried (`nothing` when it was not).
Repro: `probe_u12.jl` section P7: `loss_summary calls on the crash path (one execute!): 2`, `... success path ...: 1`. Expected 1 on both.

## Clean

What was checked and found sound, with the evidence.

- Spec-side walkers' container set (hypothesis 1), compared by reading, one row
  per walker over the four spec containers `Tuple`, `AbstractVector`,
  `LineEntry`, `ElementSpec{:line}`: `_collect_radiation_ids!` (Tasks.jl
  428-440), `_collect_aperture_specs!` (728-741), `_collect_spec_s!` (786-842),
  `_collect_declared!` (880-891), `_each_turn_rule_spec` (turn_modulated.jl,
  behind `_collect_turn_modulation_streams!`/`_collect_turn_tables!`/
  `_modulated_spec_owners`), `_has_knob_parameters` (Knobs.jl 1038-1041 plus
  beam_line.jl 160-165) and the compile walk `_append_runtime_line!`
  (2030-2071) all descend every one of the four; every `LineEntry` read goes
  through `_effective_spec`/`_merged_params` (overrides honoured), and the
  compile walk's merge is the same `_merged_params` (beam_line.jl 138-146,
  188-194). The one divergence found is the hook-bearing `LineEntry` (U12-1,
  U12-5). The `:line` placement with an `L` override is refused by
  `_placement_length(entry)` (beam_line.jl 439-460) on the arc walk before any
  other walker could disagree.
- Runtime-side walkers over the compiled line, compared by reading against the
  wrapper inventory (`grep -rnE '^\s+(inner|ops|base)::' src` finds exactly
  `CompositeLine.ops`, `MisalignedElement.inner`, `RefTilted.inner`,
  `TurnModulated.base/inner`): `_aperture_rebind` (1811-1822), `_survey_rebind`
  (1906-1945), `_check_beam_eltype` (1696-1707), `_hidden_strong_beam_count`
  (2290-2298) each own a method for all four; the two rebinders rebuild
  `TurnModulated(base, base, rule)` from the nominal element (the U2-1 rule).
  The suite's wrapper-walk tripwire list (test/runtests.jl 10751-10767) names
  all four of these walks.
- Aperture id order against the record's `counts`: `_aperture_specs` and
  `_aperture_rebind` both walk in placement/op order through nested lines and
  wrappers, and `_bind_apertures` refuses a count mismatch on the host (1795).
  Measured (P6): one aperture after a 1 m drift reports `aperture_s = [1.0]`,
  `element_id = 1`, `aperture_names = ["A"]`, counts `[8]` aligned.
- The crash path (hypothesis 3): the accounting is flushed best-effort
  OUTSIDE the policy scope, each flush failure is a `@warn` and never replaces
  the primary error, `rethrow()` is last, and the stored turn stays (P6:
  `next_turn = 0`, file closed, lock released, `/losses` written with
  `summary_folded = 0`, no exception replacement; P5b's second run shows the
  "could not be finalized" warning beside the propagating primary error).
  `_report_losses` warns on `unattributed != 0` BEFORE its `wrote_file` early
  return, so detection survives the quiet-console rule.
- The finalizer two-path rule (`tracking_completed`, 1497-1527): a finalizer
  failure after completed tracking propagates (P5: "finalizer boom" surfaced);
  after a tracking failure both finalizer lists run best-effort with a `@warn`.
- Receipt ordering for `:tracking_turn_timing` and `:turn_modulation`: recorded
  after every refusal on both loops (P2: absent on the duplicate-name refusal).
- Particle-id convention: `_track_fused_luminous!` hands `fusedTrackLuminous`
  the GLOBAL id `ctx.index_offset + index` (2401), the same as
  `phase6d_track.jl:53,300`, and the aperture's slot write subtracts
  `ctx.index_offset` (aperture.jl:328), so a shard's per-particle slots stay
  local on this path too.
- Worker count on the luminous fused path: `_run_logical_workers(local_chunks)`
  (2395) is the isolated strong-beam path's exact recipe
  (strong_beam_track.jl:111,163: fixed `_REDUCTION_CHUNKS` grid, chunk-ordered
  `_mp_chunk_fold`), the basis of the bit-identity claim; the
  `:cpu_logical_workers` receipt records `workers = local_chunks`. Note, not a
  lead: `policy.threads` is the spawn count on the plain fused path
  (phase6d_track.jl:50,64) but not here -- inherited from the U5-2 recipe and
  visible in the receipt.
- `_task_execution_window` (1595-1626): `Int(turns)`, `Int64(start_turn)` and
  the `checked_add` are each guarded, converting `InexactError`/`OverflowError`
  into named `ArgumentError`s; `turns = 0` is accepted by design. A `Bool`
  `start_turn` passes the `isa Integer` test (edge, harmless).
- `_bind_survey` arithmetic: `ds[1] = total - kicks[n] + kicks[1]` differences
  O(C) numbers to an O(ds) result with no O(1) intermediates (class 12 does not
  apply); `n == 0` deliberately does not return early (1868-1872) so a runtime
  cavity handed directly is still counted by the check at 1885.
- `_validate_reference_chain` reads `gamma0`, `strength`, `phase`, `beta0`
  through the matched entry, and `getparam(::LineEntry, ...)` merges overrides
  (beam_line.jl:146), so a placement override is honoured by the chain check as
  by the compile.
- Compile-cache invalidation (1649-1680): knob epoch (knob-dependent lines),
  spec epoch (bumped by `setproperty!` on an `ElementSpec`, Knowledge.jl
  184/200, and on a `LineEntry`, beam_line.jl 82), and record identity; the
  plan cache is emptied on every recompile. `_ensure_loss_record!` keys the
  record on the beam's storage array through a `WeakRef` (S5-1) and on slot
  presence/width/backend.
- `_global_loss_summary` sums integer counts across ranks (exact); only the
  success path globalizes, by design.
- `_partition_shared`, `_placement_phrase`, `_site_sharing_reported` and
  `_warn_resolved_duplicate_tables`'s `placed`/`aligned`/`note` logic read
  consistent with the `ReportedSharing` contract (one cause, one warning); a
  group with any site the constructor did not cover still warns.
- `_physics_line` is `@generated` over the entries' types; `_line_hook_entries`,
  `prepare_line_observers!` and `_finalize_line_observers!` use
  `_foreach_unrolled` with a `Ref` instead of a rebound capture (the `Core.Box`
  rule).
- Style only, not a lead: `_ensure_loss_record!` compares
  `length(loss_counts(existing))` (1770), which is `Array(record.counts)` -- a
  device-to-host copy per `execute!` on CUDA to compare a length
  (`length(existing.counts)` suffices); once per call, O(apertures).

## Unchecked

- Multi-rank behaviour (the crash path's rank-local flush, `_mp_is_root`
  outside the scope, `_global_loss_summary`): reasoned from the code and the
  policy helpers, not executed under `mpiexec`.
- CUDA-specific branches in the region (`_stamp_turn!`/`_open_turn_boundary`
  synchronization, the `:fused`-on-CUDA refusal, the CUDA loss record path):
  read only; no GPU probe was run.
- The bit-identity claim of `_track_fused_luminous!` against the isolated
  route and the 1.13x/1.08x timing claims in the schema docstring: not
  re-measured here (the file says the suite pins the former).
- `_warn_resolved_duplicate_tables`/`_site_sharing_reported` were checked by
  reading only; no spectral-table fixture was executed.
- Reference files were read only in the ranges listed under Provenance; the
  bodies of `_ra_stamp_ledger!`, `_ra_take_lock!`, `resolve_knobs(::ElementSpec)`,
  `fusedTrackLuminous`, and the suite's wrapper-walk tripwire logic (beyond its
  list) were not read.
- The previous audit's U13 report was consulted through `LEAD_INDEX.md` rows
  only (U13-2, U13-3, U13-5, U13-6 all recorded fixed); its body was not re-read.
