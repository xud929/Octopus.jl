# U14: BeamObservers.jl + BPMObserver.jl

Reading unit of the comprehensive audit 2026-10-18 (protocol `docs/comprehensive_audit.md`).
Tree under audit: `/cfs/ad/dxu/Library/Julia/Octopus` at commit 24e8683, read only.
Every claim below is a LEAD, not a finding. Numbers were produced on this machine
(Julia 1.12.4, `--threads=4`, one RTX 4500 Ada, CUDA functional) by the probe scripts under
`result/comprehensive_audit_2026_10_18/probes/U14/`; each probe's log sits beside it.

## Region

- `src/tasks/BeamObservers.jl` lines 1-1605 (schedules, hook plumbing, `Moment`, `MomentObserver`,
  `CoordinateSnapshotObserver`, `BeamSwapAction`, the CPU and CUDA moment rows, `MomentOutput` and
  its HDF5/legacy-JLD2 readers).
- `src/tasks/BPMObserver.jl` lines 1-447 (the BPM device model, centroid, occurrence counter,
  artifact mode, prepare/discard, option schema and configuration report).
- Total 2052 lines, all read line by line.

## Provenance

READ line by line (the region): `src/tasks/BeamObservers.jl` 1-1605; `src/tasks/BPMObserver.jl` 1-447.

READ as references and seams (not region; read only where a lead or a hypothesis needed them):
`docs/theory/bpm_measurement_model.md` 1-233 (whole);
`docs/history/comprehensive_audit_2026_08_05_b_unit_reports/U7_report.md` (whole);
`docs/todo.md` the row "The every-turn `MomentObserver` and artifact row dominate the CPU per-turn
cost" (the brief's "row 34"; it is the 33rd table line of the file);
`src/tasks/RunArtifact.jl` 60-215 (the `RunArtifact` docstring: append, capacity, crash recovery),
640-720 (`prepare_run_artifact!` open/continue), 1285-1460 (`_ra_truncate_probe!`, `_active_probe_s`,
`_ra_bind_probe!`, `_ra_push_probe_rows!`, `_ra_open`), 1529-1562 (`_ra_probe_columns`),
1900-2070 (`read(::TaskOutput, kind)`, the table of contents);
`src/tasks/Tasks.jl` 1290-1320, 1355-1420, 1440-1530, 1536-1565 (the `execute!` prepare/turn/finalize
call sites and `_warn_unfireable_schedules`), 1630-1660, 2140-2235, 2345-2365, 2440-2462 (line entries,
plan building, `ObserverSegment`, in-line finalize), 773-835 (`_collect_spec_s!` walker methods);
`src/policies/Policies.jl` 90-200 (`ExecutionAudit`, `_record_execution!`), 798-860 and 940-990 and
1038-1062 (`_masked_global_sum/count`, `_mp_current_shard`, `_mp_gather_rows`);
`src/beam/Beam.jl` 300-320, 745-800, 860-885 (`allow_lost_particles`, `_mean`, masked statistics,
`_live_stat_flags`); `src/elements/misalignment.jl` 40-80 (`_misalign_matrix`, `_frame_change`);
`src/math/counter_rng.jl` 430-470 (`octopus_normal`, `octopus_normal_pair`);
`src/elements/turn_modulated.jl` 1590-1615 (`_foreach_unrolled`);
`src/contracts/Contracts.jl` 405-430 (`_output_receipt_gaps` and the `:bpm_reading` exemption);
`test/runtests.jl` 16416-16470, 16534-16582, 16616-16655, 20655-20700, 25379-25396 (the testsets that
probe this region: finalizers/noise keys/planner, crashed `execute!`, BPM artifact buffering, the
output receipts and path registry, MomentObserver task reuse).

Repository-wide greps (read only): `_register_observer_path!`/`_OBSERVER_PATH_REGISTRY` callers;
`planned_records` and `.record_count` readers; JLD2 writer remnants; `bpm_reading` receipt sites;
`_collect_spec_s!` methods.

One slip to disclose: a single read-only `git rev-parse --short HEAD` was run inside the checkout
(it printed 24e8683). The brief says never to run git there; the command modified nothing.

EXECUTED (probe scripts in `probes/U14/`, logs beside them):

| probe | what it measures | headline numbers |
|---|---|---|
| `p1_protocol.jl` | append/restart protocol for `/moments`, `/snapshot`, `/bpm`: clean split (A), crash at turn 4 of 8 then retry (B), rewind to 3 (C), continuation by NEW objects at 9 (E), `append=false` across two `execute!` (D), receipts of a refused `observe!` (R) | A/B/C/E: every kind's turn column exactly `0:5`, `0:3` then `0:7`, `0:8`, `0:11`, cursors 5/3/7/8/11; D: artifact `[3,4,5]` vs BPM memory `0:5`; R: one `:observer_output` receipt from the refused MomentObserver, none from the refused snapshot; a path-registry warning fired on E |
| `p2_garbage_row.jl` | an exception injected inside `_moment_observer_row` (by redefining `_moment_live_flags` in the probe process) during an artifact run, capacity 3 | S1 fresh run, crash at turn 4: file holds `[0,1,2,3,1.0]`, cursor 1; retry from 0 repairs to `0:7`. S2/S3 chunked (chunk 1 = turns 0-3 clean, chunk 2 crashes at turn 6): file holds `[0,1,2,3,4,5,6.94e-310]`, cursor 0; the retry of chunk 2 yields `[0,4,5,6,7]` -- turns 1,2,3 destroyed, run finishes clean |
| `p3_cost.jl` | CPU per-turn cost at N = 1e5, 4 threads, drift + thin strong beam | tracking only 5.73 ms/turn; general loop with a no-op observer 7.85; + artifact 9.07; MomentObserver orders=1:2 (27 moments) + artifact 33.05; orders=1 10.80; BPM 8.77; MomentObserver + BPM 45.96. `_moment_observer_row` alone: 38.2 ms and 4.80 MB per call (27 moments), 2.45 ms (6 moments); the six `collect` copies alone 5.59 ms, 4.81 MB; BPM `observe!` 0.054 ms |
| `p4_reader_cursor.jl` | a simulated torn tail (dataset extent +2 rows, cursor untouched) read through both readers, then a continuing `execute!`; a zero-row group through both readers | both readers return 8 rows with turn column `[0,1,2,3,4,5,0,0]`, `record_count` 8, TOC rows 8, cursor 5; after the writer's reopen and 2 more turns: `[0,1,2,3,4,5,0,0,6,7]`, cursor 7 -- the torn rows survive. Zero-row group: every reader returns an empty result, none throws |
| `p5_bpm.jl` | the BPM model against the theory note; Float64 and Float32 centroids vs the moment observer; the noise pair; one BPM placed twice; the group's attributes; all-dead; Float32 reading | tilt and the full composed model agree with the note to the bit (diff 0.0); Float64 centroid differs from `m100000` by 17 ulp (pairwise vs serial sum); Float32 beam: BPM centroid is a `Float32`, 2.64e-11 m from the Float64-accumulated moment; `octopus_normal(.,1),(.,2)` equal `octopus_normal_pair(.,1)`; twice-placed BPM: memory mode two readings per turn with distinct noise, artifact mode refused as "duplicate probe name"; `/bpm/ipbpm` attributes `name, rows_valid_through_turn, s` only; all-dead `(NaN, NaN)`; Float32 beam reading stored as Float64 |
| `p6_snapshot_cost.jl` (CPU half; its CUDA half failed on a scoping slip in the script and was rerun as `p6b`) | snapshot with `npart=16` every turn at N = 1e6 | 30.70 -> 80.68 ms/turn: 49.98 ms per 16-particle fire; six `Array(col)[1:16]` allocate 48.0 MB per fire, `Array(view(col,1:16))` 0.33 MB |
| `p6b_snapshot_cuda.jl` | the same on CUDA at N = 2.56e6; the BPM masked-path host copy; the CUDA moment row | 8.35 -> 38.05 ms/turn: 29.70 ms per 16-particle fire (122.9 MB device-to-host); six `Array(col)[1:16]` 10.79 ms vs `Array(view(col,1:16))` 0.046 ms; BPM `observe!` mask off 0.106 ms, mask on 57.4 ms; CUDA `_moment_observer_row` 27 moments 0.937 ms |
| `p7_parse_and_search.jl` | how the `@warn` in `_warn_unfireable_schedules` parses; `searchsortedlast` on the turn columns p2/p4 produced | the `schedule =` keyword's value is the expression `schedule \ turns = turns` (a local function definition), only 3 keyword arguments reach `@warn`; `searchsortedlast([0,1,2,3,4,5,0,0], 5.0) = 8`, `searchsortedlast([0..5, 6.9e-310], 0.0) = 1`, `searchsortedlast([0,1,2,3,1.0], 1.0) = 2` with 3 rows really <= 1 |

## Leads

### LEAD U14-1 [Major, confidence high] src/tasks/BeamObservers.jl:851
Claim: `observe!(::MomentObserver)` increments `buffer_length` before the row exists, so any exception inside `_moment_observer_row` leaves an undefined or stale row in the buffer that the best-effort finalize pushes into the artifact, and the artifact then stamps its cursor from that row's garbage turn and destroys valid rows at the next bind.
Mechanism: lines 851-852 are `observer.buffer_length += 1` and then `observer.buffer[observer.buffer_length, :] .= _moment_observer_row(...)`. If the right-hand side throws (an interrupt landing in the reduction -- which p3 shows is 73% of a CPU turn -- a CUDA launch failure, a failed MPI collective), the slot is counted but never written: it holds `undef` memory on a fresh buffer or the previous batch's row on a reused one. `execute!` fails, `finalize_observers!` runs best-effort (Tasks.jl 1513-1519), `_flush_moment_observer!` pushes `buffer[1:buffer_length, :]` including that slot, and `_ra_push_probe_rows!` (RunArtifact.jl:1386, seam) sets `rows_valid_through_turn = round(Int64, rows[end, 1])` from the garbage. On the retry or resume, `_ra_bind_probe!` truncates to `min(cursor, first_turn - 1)` through `searchsortedlast` over a turn column that is no longer sorted (RunArtifact.jl:1293, seam). Measured, p2: a fresh run crashing at turn 4 leaves `[0,1,2,3,1.0]` with cursor 1 (the stale slot is turn 1's row, physically plausible and duplicated); a chunked run whose second chunk crashes leaves `[0,1,2,3,4,5,6.94e-310]` with cursor 0, and the retry of chunk 2 truncates chunk 1 to one row and finishes clean with `[0,4,5,6,7]`. The BPM (BPMObserver.jl 314-318) and the snapshot (903-911) compute first and append after; this observer is the odd one. Shape of a fix inside the region: compute the row into a local, then store and increment; the seam side (a monotone-turn check at push, a row-count cursor) is the auditor's call.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 result/comprehensive_audit_2026_10_18/probes/U14/p2_garbage_row.jl` -- the line "S2 after retry of chunk 2 (want 0:7)" prints `[0.0, 4.0, 5.0, 6.0, 7.0]`; after a fix it prints `0.0:7.0` and the "after chunk-2 crash" line shows no row beyond turn 5.

### LEAD U14-2 [Major, confidence high] src/tasks/RunArtifact.jl:1293
Claim: SEAM, out of region (noted and stopped): the artifact's crash recovery "any rows beyond the cursor are a torn tail ... and are truncated" cannot remove a torn tail whose rows read as the HDF5 fill value, because `_ra_truncate_probe!` keys the rule on the turn VALUE via `searchsortedlast`, and zero-filled rows satisfy `turn <= cursor`; the continuation then appends after them.
Mechanism: `_ra_push_probe_rows!` extends the dataset, writes the rows, then stamps the cursor and flushes. A kill between the extent change reaching disk and the row data reaching disk leaves rows that read as 0.0 (HDF5 fill value); a partial chunk write leaves arbitrary values. `_ra_truncate_probe!` reads the turn column and keeps `searchsortedlast(turns, keep_through)` rows, which (a) assumes a sorted column -- a torn or garbage tail breaks the assumption (p7: `searchsortedlast([0,1,2,3,1.0], 1.0)` = 2 with 3 rows really <= 1) -- and (b) even sorted, treats a 0.0 tail as valid rows of turn 0. In-region anchor: `_read_hdf5_record_count` (BeamObservers.jl:1485-1486) asserts "every row is cursor-valid on disk, so the row count IS the record count", which is exactly the property this seam fails to enforce. Measured, p4: six valid rows, cursor 5, extent grown by 2; a continuing `execute!(turns=2, start_turn=6)` leaves `[0,1,2,3,4,5,0,0,6,7]` with cursor 7 -- two fabricated turn-0 rows in the middle of the table, the U7-4 "fabricated all-zero rows carrying turn label 0.0" class arriving through the writer this time.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 result/comprehensive_audit_2026_10_18/probes/U14/p4_reader_cursor.jl` -- the line "after a continuing execute! (writer reopen)" prints a turn column of length 10 containing `0.0, 0.0` at positions 7-8; a correct truncation prints `[0,1,2,3,4,5,6,7]`.

### LEAD U14-3 [Moderate, confidence high] src/tasks/BeamObservers.jl:1487
Claim: no reader applies `rows_valid_through_turn` -- `_read_hdf5_record_count` returns `size(data, 1)` and `_ra_probe_columns` (RunArtifact.jl:1543, seam) reads every row -- so a live or crashed artifact's torn tail is served as data, `read(out, :record_count)` counts it, and the `_ra_open` notice telling a reader that "rows are valid through each group's rows_valid_through_turn cursor" names a rule nothing in the reading surface implements.
Mechanism: the retired standalone HDF5 writer kept `/record_count` and the reader sliced `data[1:record_count, :]`; the artifact replaced the count with a per-group cursor but the reader replaced the slice with the row count, on the comment's assumption that rows and cursor cannot disagree. They disagree during a live write (between the row write and the cursor stamp) and after an interrupted one (until a WRITER reopens the file; and per U14-2 not even then). `_ra_open` explicitly supports reading while a writer holds the lock and points the reader at the cursor; `MomentOutput` and `TaskOutput` both ignore it. Measured, p4: 6 valid rows, cursor 5 -> `read(MomentOutput)` 8 rows, `read(MomentOutput, :record_count)` 8, `read(TaskOutput, :moments)` 8 rows, TOC rows 8, the last two rows turn 0.0.
Repro: same command as U14-2; the lines "read(MomentOutput, :record_count) = 8" and "read(TaskOutput) toc rows = 8" against "cursor=5". A cursor-honouring reader reports 6.

### LEAD U14-4 [Moderate, confidence high] src/tasks/BeamObservers.jl:1066
Claim: the CPU `_moment_observer_row` costs 38 ms per call at N = 1e5 for the default 27-moment selection -- 73% of a harness-like turn at four threads, 6.7x the tracking itself -- through 34 single-threaded passes over the beam plus six full `collect` copies (4.8 MB per observed turn), which is the open todo row measured, with the copies as the one contributor the row does not list.
Mechanism: line 1066 `arrays = map(collect, coordinate_arrays(rep))` copies all six coordinate vectors (5.6 ms and 4.81 MB of the 38 ms, p3); lines 1079 and 1303 then run `_masked_global_sum`, a serial `for k in 1:n` fold on the calling thread, once for each of the six means and once per order >= 2 moment -- 27 passes for `orders=1:2` -- while the worker threads idle; the CUDA twin (1133-1284) is one fused two-pass kernel (0.94 ms at N = 2.56e6, p6b). Measured, p3 (N = 1e5, 4 threads, drift + thin strong beam): tracking only 5.73 ms/turn; general loop + no-op observer 7.85; + artifact 9.07; + MomentObserver(orders=1:2) 33.05; MomentObserver + BPM 45.96; `orders=1` 10.80 (the 6-moment row is 2.45 ms, so the cost is the per-moment passes, not the setup). The mask (`allow_lost_particles`) adds one pass: 39.1 ms. Severity is performance (class 15), not correctness; it is the open row's number on this machine.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 result/comprehensive_audit_2026_10_18/probes/U14/p3_cost.jl` -- "MomentObserver(orders=1:2, 27 moments) + artifact(64)" at about 33 ms/turn against "tracking only" at about 6; "_moment_observer_row CPU 27 moments" about 38 ms and 4.80 MB per call.

### LEAD U14-5 [Moderate, confidence high] src/tasks/BeamObservers.jl:907
Claim: `observe!(::CoordinateSnapshotObserver)` copies ALL SIX whole coordinate arrays to the host on every fire and then keeps the leading `nlocal` rows, so the `npart` knob the docstring offers for "controlling snapshot volume" does not control the cost: a 16-particle snapshot costs 50 ms per fire at N = 1e6 on the CPU and 30 ms (123 MB device-to-host) at N = 2.56e6 on CUDA.
Mechanism: line 907 is `rows[:, 2 + j] = Float64.(Array(col)[1:nlocal])`: `Array(col)` materialises the whole vector (a full copy for a CPU `Vector`, a full D2H transfer for a `CuArray`) before `[1:nlocal]` slices it. `Array(view(col, 1:nlocal))` transfers `nlocal` elements. This is the U7-5 class (the BPM's six-array host copy, fixed on the BPM's default path in that batch) living on in the snapshot twin, and the docstring's own volume control (`npart`) is what makes a user expect the small snapshot to be cheap. Measured: CPU N = 1e6, 30.70 -> 80.68 ms/turn with the snapshot (p6); six `Array(col)[1:16]` allocate 48.0 MB against 0.33 MB for the view form. CUDA N = 2.56e6, 8.35 -> 38.05 ms/turn (p6b); six `Array(col)[1:16]` 10.79 ms against 0.046 ms for `Array(view(col, 1:16))`. The per-fire cost dwarfs the row push it was meant to avoid buffering.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 result/comprehensive_audit_2026_10_18/probes/U14/p6b_snapshot_cuda.jl` -- "snapshot(npart=16) costs ~30 ms/fire on CUDA at N=2.56e6" and the two D2H timings (about 11 ms vs about 0.05 ms); after a fix the per-fire cost is below 1 ms.

### LEAD U14-6 [Minor, confidence high] src/tasks/Tasks.jl:1557
Claim: OUT OF REGION and out of hypothesis: the "a scheduled hook cannot fire in this run" warning prints a closure in place of the schedule and omits `turns`, because the `\` after `schedule = schedule` sits outside the string literal and Julia parses `schedule \ turns = turns` as a one-line definition of a local operator `\`.
Mechanism: in `_warn_unfireable_schedules`, three backslashes continue the message string (legal); the fourth, after `schedule = schedule`, is the left-division operator, so the keyword becomes `schedule = (schedule \ turns = turns)` -- a function-definition expression whose value is the function object -- and `turns = turns` is consumed by it. p7 parses the exact text: three keyword arguments reach `@warn` (schedule, first_turn, maxlog) where four were intended. Observed in p4's log: `schedule = (::Octopus.var"#\\#_warn_unfireable_schedules##0") (generic function with 1 method)`, `first_turn = 0`, no `turns`. The warning was the fix for 2026-08-05_b U13-6 ("said nothing"); it now fires but cannot tell the user WHICH hook or window it is about, and no test pins its payload.
Repro: `julia --startup-file=no result/comprehensive_audit_2026_10_18/probes/U14/p7_parse_and_search.jl` -- "number of keyword args handed to @warn: 3"; or run p4 and read the warning's `schedule =` line. Correct output names the schedule object and carries `turns`.

### LEAD U14-7 [Minor, confidence high] src/tasks/BeamObservers.jl:847
Claim: `observe!(::MomentObserver)` records its `:observer_output` receipt BEFORE the `initialized` refusal, so an audited run that refuses the fire still carries a receipt claiming the observer produced output; the snapshot twin (893-901) refuses first and records nothing.
Mechanism: lines 847-849 call `_record_execution!(:observer_output, ...)`, line 850 throws `ArgumentError("MomentObserver must be prepared ...")`. A receipt is the proof "the consumer boundary was reached and applied the value"; here it is emitted for a call that applied nothing (class 6: a refusal firing after the record was appended; class 11: the receipt is what a contract asserts). Measured, p1 (R): after one refused MomentObserver fire and one refused snapshot fire, `execution_receipts` holds exactly `[(:observer_output, :MomentObserver)]`.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 result/comprehensive_audit_2026_10_18/probes/U14/p1_protocol.jl` -- the line "receipts after the two refusals:" prints one `:MomentObserver` receipt; consistent ordering prints an empty vector.

### LEAD U14-8 [Minor, confidence high] src/tasks/BeamObservers.jl:215
Claim: the process-wide path registry warns on a legitimate sequential continuation -- a NEW `RunArtifact(path; append=true)` continuing a file whose previous writer has finished and closed -- with wording ("a second live observer ... that another live observer is writing ... later flushes from both will interleave") and a comment block (190-204) that describe the retired standalone writers, not the artifact that now registers.
Mechanism: `_register_observer_path!` is called from `prepare_run_artifact!` (RunArtifact.jl:778) with the artifact object; a task object that outlives its `execute!` keeps its artifact alive, so the `WeakRef` never goes stale and any new artifact on the path warns, although the first file handle is closed and the cross-process lock -- the real exclusion since 2026-10-16 -- admits exactly this writer. The warning names "observers" that are `RunArtifact`s and promises an interleave the per-group cursor and the lock no longer allow; the design text ("the same task continuing is silent while a second writer on the path draws the collision warning") is honest about the trigger but the message is not about what happens. Measured, p1 (E): the warning fired with `first_observer = RunArtifact, second_observer = RunArtifact` while the file ended correct (`0:11` in every group).
Repro: run p1 as above; the warning appears once, before the "E:" block, and that block's turn columns are exactly `0:11`.

### LEAD U14-9 [Minor, confidence high] src/tasks/BPMObserver.jl:76
Claim: the BPM docstring's "the memory arrays and the artifact cannot disagree" (also 357-359) is false under the artifact's default `append=false`, which recreates the file per `execute!`: after two `execute!(turns=3)` on one task the artifact's `/bpm/<name>` holds turns `[3,4,5]` while `readings(bpm)` holds `0:5`.
Mechanism: `_bpm_prepare!` keeps the memory prefix with `turn < first_turn` and sets `artifact_flushed = length(bpm.turns)`, which is right when the group was continued; with `append=false` the group is created empty at the second prepare, so the prefix exists in memory and nowhere in the file. The artifact documents the recreation (RunArtifact.jl:134); the BPM text makes an unconditional claim about a condition the artifact owns (class 14). Measured, p1 (D).
Repro: run p1; the "D:" block prints `bpm turn col = [3, 4, 5]` and `bpm memory turns = [0, 1, 2, 3, 4, 5]`.

### LEAD U14-10 [Minor, confidence high] src/tasks/BeamObservers.jl:971
Claim: `planned_records` is written at prepare and read nowhere, so the planner requirement that refuses `PredicateSchedule` for `MomentObserver` (953-956) and the comment block explaining `_scheduled_turns` by over-run and header failures (977-992) justify themselves by the preallocated HDF5 table retired on 2026-08-18.
Mechanism: `grep -rn "planned_records" src test` finds only the field, its constructor zero and the assignment at 971 (the suite reads `record_count`, not `planned_records`). The artifact dataset is extensible (`max_dims=(-1, ncols)`), so nothing is sized from the plan; the refusal's message ("requires a predictable schedule") names a requirement with no remaining consumer, and the comment describes behaviour the code no longer has (class 14). `_scheduled_turns` itself is still live through `_warn_unfireable_schedules`, which is why this is a documentation-and-dead-field lead rather than a removal.
Repro: `grep -rn "planned_records" /cfs/ad/dxu/Library/Julia/Octopus/src /cfs/ad/dxu/Library/Julia/Octopus/test` -- three hits, all in `src/tasks/BeamObservers.jl`, none a read.

### LEAD U14-11 [Minor, confidence high] src/tasks/BPMObserver.jl:273
Claim: for a `Float32` beam the BPM centroid is accumulated in `Float32` (`_mean(rep.x)` is `sum(v)/length(v)` in the array's element type, on CPU and on CUDA) while the moment observer promotes every term to `Float64` (1079 on the CPU, 1144 in the kernel), so "the centroid" has two accumulation precisions across the two diagnostics.
Mechanism: `Octopus._bpm_centroid` returns `(Float32, Float32)` on a `Float32` rep; `bpm_reading` then widens the already-rounded value. Measured, p5, N = 1e5, mean 1e-3, spread 1e-3: `Float64` beam -> BPM and `m100000` differ by 17 ulp (pairwise vs serial sum, "to round-off" as the theory note's check 1 says); `Float32` beam -> `eltype` of the centroid is `Float32` and the difference is 2.64e-11 m. Physically negligible against any BPM resolution, reported because it is class 9 (one quantity, two conventions) and because the note's check 1 is stated without a precision caveat.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 result/comprehensive_audit_2026_10_18/probes/U14/p5_bpm.jl` -- the "Float32:" line prints `eltype(bpm centroid)=Float32` and a diff of order 1e-11.

### LEAD U14-12 [Minor, confidence high] src/tasks/BPMObserver.jl:387
Claim: one BPM object placed twice in a line -- the "read twice in one turn" pattern the occurrence counter exists for (comment 115-119; suite T9) and which works in memory mode -- is refused in artifact mode as `duplicate probe name`, a message that misattributes the cause, and `_line_probe_s_map` (BeamObservers.jl:256) would in any case keep only the last placement's `s`.
Mechanism: `prepare_line_observers!` calls `_bpm_prepare!` once per `LineObserverEntry`; the second call reaches `_ra_bind_probe!` with the same `kind/name`, which is in `art.probe_names` from the first call and throws (RunArtifact.jl:1332). The refusal is loud, so nothing is silently wrong; but the user is told they reused a NAME when they placed one object twice, and a single `s` attribute per group could not represent two positions. Measured, p5: memory mode gives turns `[0,0,1,1]` with distinct noise per reading; artifact mode throws `ArgumentError: duplicate probe name "twice" under /bpm`.
Repro: run p5; the two "one BPM placed twice" lines.

### LEAD U14-13 [Minor, confidence med] src/tasks/BPMObserver.jl:403
Claim: the nine device-model options declare consumer `:bpm_reading`, under which no receipt is ever recorded, and `/bpm/<name>` carries only the attributes `name`, `s` and `rows_valid_through_turn`, so neither the run's receipts nor its file can say which offset, gain, tilt or noise produced the recorded readings.
Mechanism: `grep -rn bpm_reading src` outside `BPMObserver.jl` finds only the Contracts.jl sentence exempting it from the output-receipt check (418-419, "belong to the schema-driven sweep of docs/todo.md row 28"); `observe!` records `name, turn, artifact, capacity` only (311-313); `_ra_bind_probe!` stamps `name` and `s`. The invariant "assert what the run recorded" has nothing to assert for the error model: a `/bpm` group from a run with `x_offset=1e-4` and one with `x_offset=0` are indistinguishable without the script. Measured, p5 (6): attributes `["name", "rows_valid_through_turn", "s"]`, datasets `["column_names", "data"]`. Confidence med because the exemption is deliberate and ledgered; the lead is that the ledgered gap is also a provenance gap in the file.
Repro: run p5; the "attributes on /bpm/ipbpm:" line; `grep -rn "bpm_reading" /cfs/ad/dxu/Library/Julia/Octopus/src | grep -v BPMObserver.jl` returns only the Contracts.jl docstring line.

## Clean

Hypothesis 1 (append/restart protocol across every output format). The three remaining formats are
the artifact groups `/moments`, `/snapshot`, `/bpm`; the standalone HDF5, binary, JLD2 and TSV writers
of the previous audit are gone (the only `jldopen` left is the legacy READER `_read_moment`, 1582-1597,
and the retired constructors throw migration pointers at 658-665, 741-747, 139-147). Measured in p1
with `capacity=3` and `capacity=4` so that both the capacity-boundary flush and the finalize flush were
exercised: clean split `0:5`, crash at turn 4 of 8 then retry `0:3 -> 0:7`, rewind to 3 `0:8`,
continuation by new task and observer objects at 9 `0:11`, each turn exactly once in all three groups,
the BPM memory arrays equal to the `/bpm` turn column in every `append=true` case, cursors equal to
the last turn. The snapshot block is written per fire (two particles, two rows per turn), the BPM
`artifact_flushed` cursor starts past the retained prefix (394) so continuation does not re-push.
The failing-`execute!` path flushes the buffered tail (B: turn 3 was buffered and reached the file).
The "JLD2 delete-then-write" class (U7-2) is closed by removal of the writer. The protocol is sound
for well-formed rows; U14-1 and U14-2 are the two ways a row becomes ill-formed.

Hypothesis 2 (silent row drops). Checked by reading: non-root MPI ranks drop their pushes by design
(`_ra_push_probe_rows!` returns on `!_mp_is_root()`, the bind returns the key without a file); a zero-row
push returns early and leaves the cursor alone, consistent with the bind's truncation rule; the buffer
cannot overrun its allocation on the normal path (flush at `buffer_length >= buffer_capacity`, both
sized from `art.capacity`); `_read_hdf5_selection` skips requested-but-absent moments as its docstring
says and `TaskOutput` returns a labelled `NamedTuple` for the same selection, while `_read_hdf5_column`
throws `KeyError` for an absent single column (a documented asymmetry, not a drop). Zero-row groups read
as empty through all five reading forms without throwing (p4). The per-turn `:hook_schedule` and
`:observer_output` receipts allocate only under `with_execution_audit` (opt-in; `_record_execution!`
returns on `audit === nothing` and the named tuples are isbits). The every-turn cost is U14-4.

Hypothesis 3 (BPM device-number semantics vs the note). `bpm_reading` implements the note's section 4
model exactly: `W = _misalign_matrix(Float64, 0, 0, tilt, false)` is `R_z(psi)` row-major, `c, s =
W[1], W[4]` = `(cos, sin)`, and `[c s; -s c]` is applied to the centroid minus the offset, gain outside
the rotation, readout outside the gain. Measured, p5: tilt 0.1 on (1e-3, 0) gives `(cos*1e-3, -sin*1e-3)`
to the bit; the full composed model with all seven deterministic terms nonzero matches the formula with
difference `(0.0, 0.0)`. The noise draw goes through `octopus_normal(seed, method, turn, rng_id,
occurrence, component)` as the note's section 5 says, with the occurrence in the particle slot and the
first reading of a turn at occurrence 0; components 1 and 2 equal the two halves of
`octopus_normal_pair(..., 1)` (p5), so the two calls recompute one pair (a style point, not a defect).
The occurrence counter is reset by `_bpm_discard_window!` at every prepare (364-365), so a replayed
window redraws the same noise. The all-dead centroid is `NaN` on both the BPM and the moment paths and
both now say so (U7-12 closed). `rng_id` is `UInt64` end to end (S1-7 closed) and `0` auto-assigns
(S1-1 closed). `configuration_report(::BPMObserver)` always lists `name` and `rng_id` as active and
compares the rest against the schema defaults. The note's section 6 deferrals (crunch, calibration
pairing, single-plane monitors, intensity dependence) are absent from the code, none half-implemented.

Schedules and planner. `should_run` for the three predictable schedules and `_scheduled_turns` agree on
the absolute window: checked by hand on `EveryNSteps(start=0, stop=6, step=2)` at `first_turn=3,
turns=3` (`[4]`), `start=10` outside the window (`[]`), `start=5` (`[5]`), `stop<=lo` (`[]`); the suite's
T10 oracle (runtests.jl 16463-16470) sweeps 2000 combinations. `AtTurns` holds a `Set` but the plan
sorts it and `should_run` only tests membership.

Hook plumbing. `_hook_tuple`, `classify_task_hooks`, `_push_task_hook!` preserve declaration order and
throw a directed `ArgumentError` on an unsupported hook type; `finalize_observers!` runs every finalizer
and rethrows the first error; the method-overwrite NOTE at 305-310 is correct (the 3-argument
`prepare_line_observer!(::AbstractBeamObserver, ::Any, ::Any)` would be shadowed) and both
`MomentObserver` and `BPMObserver` supply the typed methods; `_collect_spec_s!`'s probe arm pushes
`(s, 0.0, hook)` for observers and in-line actions fall to the walker's generic method (Tasks.jl:835),
so `_line_probe_s_map` cannot `MethodError` on a line with actions; the arc position reaches the file
(`s = 0.5` for a BPM between two half-metre drifts, p5).

Moment machinery. The `Moment` name grammar round-trips (compact for single digits, `_`-separated
otherwise; negative or malformed powers throw); `_moments_for_order` enumerates in the canonical order
`isless` sorts by; the CPU row builds one shared live mask from all six coordinates (the docstring's
coupling argument holds), returns `NaN` moments with an intact turn on an all-dead beam, and accumulates
`Float32` terms in `Float64`; the CUDA row is one kernel in two passes with the power rows as a `Val`
type parameter, a power-of-two block (256) tree reduction in fixed order, the host finish in block order,
chunking at 32 accumulators with `nm` bounding the valid partial columns, and `use_mask` as a runtime
`Bool` so both branches share one kernel; its early returns (`isempty(moments)`, `nlive == 0`) are
decided from rank-global quantities, so the MPI path cannot strand a rank (read; the divided path was not
executed, see Unchecked). The CUDA row measured 0.94 ms for 27 moments at N = 2.56e6 (p6b).

Readers. `_is_hdf5_output` decides by the 8-byte HDF5 signature (U7-4 closed, and the suite pins it);
`read(::MomentOutput, :elapsed_time)` on an artifact group throws a directed message pointing at the
execution ledger; `column_names` reads the group's `column_names`; `MomentOutput(path; name)` and
`read(TaskOutput(path), :moments; name)` return the same rows (p4, same 8 rows in the torn case, same
6 otherwise). The `MomentOutput` docstring (1306-1331) still describes `/record_count` and
`elapsed_time` as if every file had them; the behaviour behind each is correct or loud, so style only.

BPM cost. The BPM's default path is two device-side reductions (0.106 ms at N = 2.56e6 on CUDA, 0.054 ms
at N = 1e5 on the CPU, no allocation), the U7-5 fix holding; the masked path's six-array host copy is
documented in place (282-285) and measured at 57.4 ms at N = 2.56e6 on CUDA -- the documented remaining
half, not reported as a lead.

## Unchecked

- The divided (MPI) paths of this region -- `_mp_current_shard`/`_mp_gather_rows` in the snapshot,
  the serial `_masked_global_sum` form of `_bpm_centroid`, the non-root bind and push -- were read but
  not executed under `MPI.mpiexec()`; the one-rank identities hold by the passthrough methods read in
  Policies.jl 1045 and 807/850.
- CPU/CUDA parity of `_moment_observer_row` was not re-measured here; the suite's "Fused CUDA moment
  row matches the CPU fold on every liveness path" (runtests.jl 26296) owns it and was not run.
- `_copy_rep!`/`BeamSwapAction` across backends (a CPU destination with a CUDA source) was read only.
- The legacy JLD2 reader `_read_moment` (1582-1597) was not executed: no legacy columnar file is
  available on this tree to read.
- The real torn-tail geometry on this NFS mount (which of the extent, the rows and the attribute reach
  disk first at a hard kill) was not measured; p4 simulates the extent-without-rows state, and the
  rows-without-cursor state is the one the current rule handles. The previous audit's SIGKILL probes
  (U7, section 5) never landed inside a write either.
- `src/tasks/Tasks.jl` and `src/tasks/RunArtifact.jl` are outside this region; U14-2 and U14-6 are
  reported as seams/out-of-region and stopped, per the brief.
- The `WeakRef` staleness of `_OBSERVER_PATH_REGISTRY` entries after an artifact is collected was not
  exercised (it would need a GC-timed probe); U14-8 concerns the live case.
