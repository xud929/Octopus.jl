# U6 Audit Report — BeamObservers.jl, BPMObserver.jl, Tasks.jl

Repository: /cfs/ad/dxu/Library/Julia/Octopus @ 6a3f39a
Probes: /tmp/claude-320114/-cfs-ad-dxu-Library-Julia-Octopus/94771dda-fd24-4438-922e-a4bd8afa2361/scratchpad/U6/
(p1_append.jl, p2_retry_dup.jl, p3_bpm.jl, p4_docs.jl, p5_docs2.jl, p6_docs3.jl, p7_docattach.jl)
All probes CPU-only, run as `julia --startup-file=no --project=. <script>`; every output
file written under the scratch directory. Julia 1.12.4.

## Coverage

- src/tasks/BeamObservers.jl — lines 1–1582, every line read.
- src/tasks/BPMObserver.jl — lines 1–324, every line read.
- src/tasks/Tasks.jl — lines 1–827, every line read.
- Cross-referenced (targeted reads, not full audits): src/tasks/strongstrong/interface.jl
  1680–2330 (luminosity_append protocol, StrongStrongTask cache gating, observer prep),
  src/math/counter_rng.jl 20–150 (octopus_normal chain), src/elements/misalignment.jl 40–80
  (_misalign_matrix layout), src/elements/aperture.jl 105–125 (_loss_record_matches_rep),
  src/elements/beam_line.jl 138–160 (_has_knob_parameters for LineEntry/line),
  src/track/Track.jl 13–32 (TrackingContext/with_turn), src/beam/Beam.jl helper existence,
  docs/theory/bpm_measurement_model.md sections 4–7.

## Leads

### U6-1 (medium) — BeamObservers.jl:962-976 with 524-535: MomentObserver(append=true)
silently destroys the entire table on any turn-0 window, including the docstring's own
advertised continuation cases.

`_prepare_moment_observer!` computes `kept = rows with turn < first_turn` and truncates.
A fresh task (or a fresh process) has `next_turn = 0`, so executing WITHOUT `start_turn`
gives `first_turn = 0` and `kept = 0`: every prior row is dropped, no warning, no error.
The docstring (lines 528–531) lists "a second task sharing the path, or a fresh process
restarting a chunked run" as cases that "produce one file with continuous absolute turns";
neither continues unless the user separately knows to pass `start_turn`, which the
docstring never states. Even `execute!(task; turns=0)` on a fresh task wipes the file.

Numbers (probe p1_append.jl):
- case 4: file with 10 rows (turns 0–9) -> fresh task, `turns=3`, no start_turn ->
  file holds 3 rows `[0,1,2]`; 10 rows destroyed silently.
- case 5b: file with 7 rows (turns 0–6) -> fresh task, `turns=0` -> file holds 0 rows.
- case 8 (control): explicit `start_turn=2` continues correctly -> `[0,1,2,3,4]`.

Same semantics in the sibling `_prepare_strong_strong_luminosity_file!`
(strongstrong/interface.jl:1976-2000, `parse < first_turn` filter): the two protocols
agree with each other, and both agree on this hazard. The invariant violated is the
append docstring's own promise of continuation across tasks and restarts; the minimal
fix space (warn, or require start_turn when the file is nonempty and first_turn==0) is
the auditor's call.
Repro: scratchpad/U6/p1_append.jl (cases 4, 5b).

### U6-2 (medium) — BeamObservers.jl:818-832, 913-940, 893-908, 806-816: the four
non-appending observers duplicate turn labels on a failed execute!'s retry, violating
the T6 idempotence rule the same file states as its own invariant.

`_moment_append_continue!`'s docstring (BeamObservers.jl:983-989) says "a table with two
rows for one turn is corrupt for every reader", and BPMObserver/MomentObserver both drop
replayed windows. LuminosityObserver, JLD2BeamMomentObserver, BeamMomentObserver, and
CoordinateSnapshotObserver have no discard path: their `initialized`/`append` flags stay
set after the crash (finalize does not reset them), so the retry appends the replayed
turns again.

Numbers (probe p2_retry_dup.jl; crash at absolute turn 3 of a 6-turn window, then retry):
- LuminosityObserver .dat turn column: `[0,1,2,0,1,2,3,4,5]` — 3 duplicate labels.
- JLD2BeamMomentObserver turn column:  `[0,1,2,0,1,2,3,4,5]` — 3 duplicate labels.
- BPMObserver control (same crash protocol): `[0,1,2,3,4,5]` — 0 duplicates.
BeamMomentObserver and CoordinateSnapshotObserver share the structure by code identity
(no prepare_observer! discard method; flags never reset) — not separately probed.
Secondary effect, same mechanism: in a fresh process `initialized=false` again, so the
first observation truncates ("w") a luminosity/TSV file from the previous process —
chunked-run continuation across processes is impossible for these observers.
Repro: scratchpad/U6/p2_retry_dup.jl.

### U6-3 (low) — BeamObservers.jl:764-770: the BeamSwapAction docstring is attached to
nothing; the exported type has no documentation.

The docstring sits AFTER `struct BeamSwapAction` (760-762) and is separated from the next
expression (`function observe!(::BeamMomentObserver, ...)`, line 772) by a blank line at
771. On Julia 1.12.4 a blank line between the closing `\"\"\"` and the following
expression prevents attachment entirely: the string is evaluated as a no-op literal.
Numbers: probe p6_docs3.jl scans `Docs.meta(Octopus)` — controls (Moment, BPMObserver
docstrings) found; "BeamSwapAction(provider)" and "Replace the current representation"
found on ZERO bindings. Probe p7_docattach.jl minimal repro: blank-gap variant attaches
to NOTHING, tight variant attaches normally. Consequence: `?BeamSwapAction` returns the
"No documentation found" stub and the provider(ctx)-vs-provider() calling contract
(implemented at _call_provider, line 859-861) is invisible to users.
Repro: scratchpad/U6/p6_docs3.jl, scratchpad/U6/p7_docattach.jl.

### U6-4 (low) — BeamObservers.jl:623-626: MomentObserver docstring's closing paragraph
contradicts the append contract stated 100 lines above in the same docstring.

"Re-executing a task prepares a fresh table at `path`; output from the previous execution
is replaced." is stated unconditionally, but with `append=true` (lines 524-535 of the
same docstring) re-execution continues the table — verified by probe p1 case 2-3.
Stale pre-append text; qualifies as docstring<->code drift on the new option.
Repro: read the two paragraphs; behavior demonstrated by p1_append.jl.

### U6-5 (info) — BeamObservers.jl:1092: `throw(BoundsError("MomentObserver received
more records than planned"))` misuses the BoundsError constructor: the string becomes the
"array" field, so the user sees "BoundsError: attempt to access String". The guard
itself is correct and loud (fires when observations exceed the planned schedule, e.g. one
observer placed twice in a line); only the message is garbled. Reading-level; the
identical misuse pattern was demonstrated incidentally by an early probe-runner error.

### U6-6 (low) — BeamObservers.jl:893-908: BeamMomentObserver flush writes the
incremented record count into the header (lines 896-898) BEFORE writing the buffered
rows (899-903). A crash or I/O failure between the two writes leaves a compact binary
file whose header count exceeds the rows actually present — the reverse of the
record-count-gates-data discipline the HDF5 path follows (rows first, count last,
BeamObservers.jl:1094-1095). Reading-level; no probe (requires injected I/O failure).

## Sound (invariant verified, and how)

1. Append crash/retry idempotence (defect class 1c): crash at absolute turn 7 leaves
   record_count=7, turns 0-6, next_turn unadvanced (5); retry yields exactly turns 0-9,
   record_count=10, all unique — no duplicate, no hole (p1 cases 2-3). Extent regrown/
   reshrunk via set_extent_dims; stale rows beyond record_count are unreachable to the
   readers, which all slice `1:record_count`.
2. append=true with no existing file (class 1b): creates the chunked table, extent (5,7),
   `appendable` attribute present (p1 case 1).
3. Mode/schema refusals (class 1a): append onto a replace-mode file -> ArgumentError via
   the `appendable` attribute check (997-999); different moment selection -> ArgumentError
   via the column_names comparison (1000-1002). Both probed (p1 cases 6-7). The writer
   checks the marker; readers don't need to (record_count gating).
4. The two append protocols agree (class 1e): `_moment_append_continue!` and
   `_prepare_strong_strong_luminosity_file!` both drop rows >= first_turn, both continue
   absolute turns, both carry a writer-checked schema marker (HDF5 attribute vs header
   line). U6-1's hazard is shared, consistently.
5. `append` effectiveness (class 2): consumed on both file-creating paths
   (_prepare_moment_observer! 962, _initialize_hdf5_moment_file! 1066); flush/readers are
   mode-agnostic by design; declared in observer_option_schema (690) and
   configuration_report (732-737) with consumer :observer_output, which fires in observe!.
6. T6 loss artifacts (class 3): execute!'s catch block (Tasks.jl:317-328) runs
   _task_loss_summary/_write_task_loss_log/_report_losses before rethrow; stored turn not
   advanced (probe p1 case 2: next_turn=5 after the crash). Loss file rewritten whole,
   idempotent by construction (Tasks.jl:336-352).
7. T2 loss-record reallocation (class 3): _ensure_loss_record! (Tasks.jl:548-568) checks
   aperture count, _loss_record_matches_rep (aperture.jl:112-117: CUDA-vs-host storage and
   slots eltype), slots wanted/shape; runtime cache keyed on record identity
   (Tasks.jl:529) so a new record forces recompile; _bind_apertures' id==length(counts)
   host-side check (Tasks.jl:580-584) executes on every compiled line.
8. BPM error model vs docs/theory/bpm_measurement_model.md (class 4): zero-error reading
   equals centroid exactly; full model residual 0.0 in x and y against
   G·R(tilt)·(centroid-offset)+readout computed by hand with R=[c s; -s c]; MAD-X limit
   residual 0.0 against (1+MSCALX)x+MREX (p3 cases 1-2). W row-major from
   _misalign_matrix, W[1]/W[4] = cos/sin — consistent with _frame_change's Q'a use.
9. BPM noise key purity (class 4): reading identical after Random.seed!/rand churn (pure
   counter chain, counter_rng.jl 89-134, no global state); ctx snapshot immune to mid-run
   set_global_rng!; two auto-id BPMs at one turn decorrelated (ids 4,5, distinct
   readings); second reading of a turn draws occurrence 1 (differs); replay after
   _bpm_discard_window! reproduces both draws exactly (p3 cases 3-6). BPM retry control:
   0 duplicate labels (p2).
10. Knob-epoch gating (class 5): both AbstractTask subtypes (only two exist) gate their
    runtime caches on knob_epoch()+_spec_epoch() with plan caches emptied on recompile —
    TrackingTask Tasks.jl:522-539, StrongStrongTask interface.jl:2208-2226; the part-9
    BeamLine methods (_has_knob_parameters for LineEntry and ElementSpec{:line}) are
    present at beam_line.jl:152-157 and reachable from both.
11. Scheduling edges (class 6): planner filters against the absolute window in all three
    predictable schedules (1032-1061; EveryNSteps first-point arithmetic checked:
    start=0,step=3,lo=7 -> from=9, correct); empty AtTurns yields a 0-row table without
    error; PredicateSchedule is refused loudly at prepare (957-959); over-firing is
    caught by the planned-records guard (1090-1092, message quality aside — U6-5);
    turns=0 execute handled (window math Tasks.jl:465-496 checked, incl. overflow).
12. HDF5 lifecycle (class 7): every h5open/jldopen in these files is inside a do-block
    (closed on error); the flush BoundsError is thrown before opening; chunk rows
    clamp(planned,1,1024) with unlimited max_dims — no unbounded chunk growth; writer and
    readers share /column_names as plain strings, read back with String.() (no encoding
    drift found).
13. No spawned blocks in any of the three files (grep for @spawn/@async/@threads: none),
    so class 8's closure-capture check is vacuous here. The overwrite-trap NOTE at
    154-159 was checked against the actual method table: BPMObserver's typed methods
    (BPMObserver.jl:274-277) cannot collide with the AbstractBeamObserver fallbacks.
