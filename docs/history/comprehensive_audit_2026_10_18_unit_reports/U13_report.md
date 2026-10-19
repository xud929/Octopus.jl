# U13: RunArtifact.jl (new since the last audit)

Tree under audit: `/cfs/ad/dxu/Library/Julia/Octopus` at commit 24e8683, read-only. Unit brief:
`result/comprehensive_audit_2026_10_18/plan/U13.md`; standing rules: `plan/BRIEF_COMMON.md`.
Every claim below is a LEAD, not a finding.

## Region

- `src/tasks/RunArtifact.jl`, lines 1-2070 (the whole file; 2070 lines): the `RunArtifact` sink,
  its option schema and receipts, the sidecar lock, `prepare_run_artifact!` /
  `finalize_run_artifact!`, the `/execution` ledger, the luminosity channel, the `/losses` writer,
  the probe row-matrix machinery, the turn-modulation provenance writer and series recorder, and
  the `TaskOutput` / `turn_modulation_provenance` readers.

Seams read for context only (not audited line by line; leads that touch them are marked as seams):
`src/tasks/Tasks.jl` 893-1000, 1025-1085, 1355-1500, 1760-1795; `src/tasks/strongstrong/interface.jl`
2665-2790, 2885-2950; `src/elements/turn_modulated.jl` 1840-1980 and the two wrap sites;
`src/tasks/BeamObservers.jl` 860-915, 955-1035; `src/tasks/BPMObserver.jl` 300-340;
`src/math/counter_rng.jl` 20-50; `src/contracts/Contracts.jl` 560-680.

References compared against: `docs/design/run_artifact.md` (all 543 lines),
`docs/design/turn_modulation_record.md` (all 440 lines), `docs/public_api.md` 116-215,
`docs/todo.md` line 28 (the row the brief calls "todo row 29": "The effectiveness contract pins
`RunArtifact` options only through receipts").

## Provenance

READ line by line: `src/tasks/RunArtifact.jl` 1-2070 in six passes (1-340, 340-680, 680-1019,
1019-1358, 1358-1697, 1697-2070); the two design notes and the public_api section whole.

EXECUTED (scripts and logs under `result/comprehensive_audit_2026_10_18/probes/U13/`; each
`julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 <script>` unless stated):

| probe | script / log | what it measured | numbers |
|---|---|---|---|
| A1 | `probe_A_artifact.jl` / `probe_A.log` | a continued file whose ledger lacks `rng_seed`, prepared with `append=true` at `first_turn=50` | refused by name; luminosity rows 100 -> 50, cursor 99 -> 49, ledger rows 1 -> 1, lock released |
| A1b | same | a continued file holding a partial `/turn_modulation/1`, prepared at `first_turn=50` | refused by name; rows 100 -> 50, cursor 99 -> 49 |
| A2 | same | a group with 10 rows beyond its cursor (cursor 9, 20 rows on disk) read through `TaskOutput`, then continued by a writer at `first_turn=1000` | reader: 20 rows, keys `(:turn, :value)`, toc rows 20, no warning; writer after open: 10 rows |
| A3 | same | `read(TaskOutput(p))` with `p.lock` present and (i) no file, (ii) a text file | both: "failed twice while a live Octopus writer holds its lock ... landed on a flush both times"; without the lock the text file gives HDF5's "unable to determine if ..." |
| A4 | same | `append=true` onto a `chmod 000` artifact | `ArgumentError` (not-HDF5 refusal), lock NOT leaked, a second writer accepted -- clean |
| A5 | same | a stray group `/turn_modulation/foo` and a foreign top-level group `/foreign` | `turn_modulation_provenance` and `read(out)` (the table of contents) both die with `ArgumentError: invalid base 10 digit 'f' in "foo"`; `read(out, :all)` dies with "unknown artifact product :foreign" |
| A6 | `probe_E_bind_and_attrs.jl` / `probe_E.log` | attributes of `/luminosity/ip` | `["label", "rows_valid_through_turn"]` (the design table says `attrs: label, s`) |
| A7 | same | a luminosity group whose cursor attribute is absent, continued at `first_turn=1000` | rows 10 -> 0 (all ten were below `first_turn`) |
| E1 | same | window 1 with probes m1, m2 (10 rows each); window 2 `append=true, start_turn=5` with m2's columns changed | m2's bind refused by name; m1 rows 10 -> 5, m2 rows 10 |
| B | `probe_B_losses_restart.jl` / `probe_B.log` | `/losses` across windows: same task, then a NEW task object continuing the file with `append=true` (a process restart) | window 1: 1 loss row, counts [1], dead 1; window 3 by the new task: 0 rows, counts [0], dead 0, ledger start_turns [0, 3, 6] |
| C | `probe_C_kill.sh` + `probe_C_child.jl` + `probe_C_reader.jl` / `probe_C.log` | a writer flushing one luminosity row and one probe row per turn (`capacity=1`) killed with SIGKILL after 2, 4 and 7 s, then read | all three rounds readable: luminosity rows 1438 / 2106 / 2656 = cursor+1, rows beyond cursor 0; probe rows likewise; ledger `current_turn` 1438 / 2105 / 2655 (leads the channel by at most one turn); lock left in place |
| D1 | `probe_D_recording.jl` / `probe_D.log` | two `ThinCrabCavity` with noise in one line, `record_turn_modulation=true` | both element entries `element = "ThinCrabCavity"`, group attrs `["beam", "element", "slot_count"]`; distinguishable only by order and by nominal phase |
| D2 | same | crash at turn 7 of 10, recording on, `capacity=4` | series rows 7 of `turns=10`, one warning naming the dataset, ledger `current_turn` 6, lock released |
| D3 | same | crash at turn 5 of 10, `capacity=100` (no intermediate flush) | series rows 5 (the crash finalize flushed the tail), ledger `current_turn` 4 |

## Leads

### LEAD U13-1 [Major, confidence high] src/tasks/RunArtifact.jl:688
Claim: Under `append=true`, four by-name refusals of `prepare_run_artifact!` fire AFTER the replay truncation has already dropped every luminosity row at or beyond `first_turn`, so a refused continuation damages the file it claims to leave as found.
Mechanism: The continued-file branch truncates each luminosity group to `min(cursor, first_turn - 1)` (lines 688-695, `_ra_truncate_group!` shrinks both datasets and rewrites the cursor) before the ledger checks at 699 (no `/execution`), 715 (missing `rng_seed`/`rng_method` columns -- whose message and the design, `run_artifact.md` 507-511, promise the file is "left as found, never padded"), 723 (partial slot) and 734 (slot collision / column-walk mismatch); the `catch` at 767-773 closes and releases but cannot undo `set_extent_dims`, and its comment "A refusal leaves the path as it found it" is false for these rows. The exposure is exactly the retry case `append=true` exists for (a replayed window after a crash), on any pre-2026-10-16 file or any file with a partial slot: the retry is refused and the replayed window's rows are gone with no warning. The fix is ordering: run every refusal before the truncation loop (the label check at 684 already is). Hypothesis 2, the phantom-row class mirrored: a refusal after rows were dropped instead of after a row was appended.
Repro: `cd result/comprehensive_audit_2026_10_18/probes/U13 && julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 probe_A_artifact.jl` -- section A1: build 100 rows through prepare/push/finalize, delete `/execution/rng_seed`, prepare `RunArtifact(p; append=true)` at `first_turn=50`: an `ArgumentError` naming the missing column AND "after: lum rows = 50, cursor = 49" (expected 100 / 99). Section A1b repeats it for the partial-slot refusal (100 -> 50).

### LEAD U13-2 [Major, confidence high] src/tasks/RunArtifact.jl:1190
Claim: `/losses` does not follow the replay rule the design promises for `append=true` across process restarts: a continued window written by a fresh task object deletes the group and rewrites it from an empty record, so every loss of the earlier windows disappears from the file silently.
Mechanism: `_ra_write_losses!` runs `HDF5.delete_object(art.file, "losses")` and rewrites the group from `task.loss_record[]` (lines 1190-1237), which is cumulative only within one task object and one beam storage (Tasks.jl 1769-1783 reallocates it when the rep's arrays change). On a restart -- the design's stated use, `run_artifact.md` 233-237 "continues it across `execute!` calls and process restarts under the replay idempotence rule (rows at or beyond the incoming window's first turn are dropped per group first)" -- the record is empty, so rows BEFORE `first_turn` are dropped too, together with `aperture_counts` and the `summary_*` attributes, and nothing in the file or on the console says so (the `/execution` ledger still lists all three windows). Violates "Loud beats silent"; hypothesis 1 (append/restart protocol). The remedy is a design decision: merge the file's existing rows below `first_turn` into the rewrite, or warn by name that `/losses` restarts with the process.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 result/comprehensive_audit_2026_10_18/probes/U13/probe_B_losses_restart.jl` -- "window 1: loss rows = 1 ... dead = 1" then, after a NEW `TrackingTask` continues the same path with `append=true, start_turn=6` and a beam that loses nothing, "window 3 (new task B): loss rows = 0, aperture_counts = [0], summary.dead = 0; ledger start_turns = [0, 3, 6]".

### LEAD U13-3 [Moderate, confidence high] src/tasks/RunArtifact.jl:1346
Claim: Probe groups are truncated one bind at a time, so a later probe's bind refusal (duplicate name, changed columns) leaves every earlier probe already cut back to `first_turn - 1` -- the same ordering defect as U13-1 one level down, and the opposite of what the strong-strong prepare comment claims ("Validate every output preparer BEFORE any of them commits").
Mechanism: `_ra_bind_probe!` validates and commits per probe: it truncates the continued group at line 1346 (`_ra_truncate_probe!`, a `set_extent_dims` on `data`) and returns; the next probe's bind may then refuse at 1332 (duplicate) or 1341 (column mismatch). The refusal closes the artifact through the task's catch (TrackingTask) or the observer-prepare catch (strong-strong, interface.jl 2724-2733), neither of which can restore the rows. Cross-file seam: the per-probe validate-and-commit sits in `BeamObservers.jl`/`BPMObserver.jl` bind calls; the destructive step is in this region.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 result/comprehensive_audit_2026_10_18/probes/U13/probe_E_bind_and_attrs.jl` -- section E1: two `MomentObserver`s m1, m2 write 10 rows each; the continuation at `start_turn=5` with m2 at `orders=1:2` is refused ("the probe group /moments/m2 ... carries columns ...") and prints "m1 rows = 5, m2 rows = 10" (expected 10 / 10).

### LEAD U13-4 [Moderate, confidence med] src/tasks/RunArtifact.jl:1539
Claim: The public readers neither apply nor expose the per-group cursor `rows_valid_through_turn`, so a reader of a live or killed file receives the torn tail the design declares invalid, with no field to apply the rule the lock-aware `@info` tells them to apply.
Mechanism: `_ra_lum_series` (1539) and `_ra_probe_columns` (1541-1549) return the raw datasets; the table of contents (2055-2062) reports `rows = length(turns)` / `size(data, 1)`; none reads the cursor attribute. The writer's open is the only consumer of the cursor (690-694, 1344-1346), so the writer and the readers disagree on what a group holds (defect class 3). The `_ra_open` message (1423-1426) says "its rows are valid through each group's rows_valid_through_turn cursor", but no `read` surface carries that number. Mitigating measurement: three SIGKILLs with a flush per row (probe C) never produced rows beyond a cursor, so the practical exposure needs a kill inside the flush itself; the disagreement is nonetheless in the code and the toc could carry the cursor at no cost.
Repro: probe A section A2: build 10 rows (cursor 9), append rows 10..19 through raw HDF5 without touching the cursor; `read(TaskOutput(p), :luminosity; name="ip")` returns 20 rows with keys `(:turn, :value)` and `read(out)["luminosity"]["ip"].rows == 20`, while a writer opened with `append=true` at `first_turn=1000` leaves 10.

### LEAD U13-5 [Minor, confidence high] src/tasks/RunArtifact.jl:1434
Claim: Under a lock, `_ra_open` replaces the open's own error with a fixed "landed on a flush both times" diagnosis, so a stale lock beside a missing or non-HDF5 file is misreported as a flush race.
Mechanism: The inner `catch` at 1434-1437 discards the exception (ENOENT, HDF5's "unable to determine if ... is accessible", a permission error) and raises a generic `error(...)` whose text asserts a cause it did not observe; the design (`run_artifact.md` 450) says the failure propagates "with the lock information in it", which would mean wrapping, not replacing. Defect class 6 (an exception from a failure path replacing the original error).
Repro: probe A section A3: `write(p * ".lock", "host=elsewhere pid=1 ...")` with no `p` -> `read(TaskOutput(p))` raises "reading the run artifact at ... failed twice while a live Octopus writer holds its lock (...): the file is being written and the open landed on a flush both times"; the same text for a text file at `p`; without the lock the real HDF5 message surfaces.

### LEAD U13-6 [Minor, confidence high] src/tasks/RunArtifact.jl:1736
Claim: One stray non-numeric group under `/turn_modulation`, or one foreign top-level group, makes the whole table of contents (`read(out)`), `turn_modulation_provenance` and `read(out, :all)` unreadable with an error that does not name the group.
Mechanism: `_ra_turn_modulation` parses every subgroup name with `parse(Int, ...)` (1736), so `foo` raises `ArgumentError: invalid base 10 digit 'f'` from Base, and `read(out)` calls it for the toc (2048), taking every other product down with it; `read(out, :all)` (1970) maps every top-level key of `_ra_contents` through `read(out, Symbol(k))`, which refuses a key outside `_RA_KINDS` (1952). A reader of a file touched by another tool loses the parts that are intact. Out of hypothesis (robustness of the reader).
Repro: probe A section A5: create `/turn_modulation/foo` and `/foreign` in a valid artifact; `turn_modulation_provenance(p)` and `read(TaskOutput(p))` raise "invalid base 10 digit 'f' in \"foo\""; `read(TaskOutput(p), :all)` raises "unknown artifact product :foreign".

### LEAD U13-7 [Minor, confidence high] src/tasks/RunArtifact.jl:918
Claim: The `/turn_modulation/<slot>/<k>` element group identifies a modulated element by its type name and line order only -- no spec label, no `s` -- so two cavities of one type in one line are told apart only by the order `k` (and, by luck, by differing nominals), against the design's own "Names are identities" and the probes' `attrs: name, s`.
Mechanism: The writer stamps `element = String(entry.element)` (918), where the seam `_turn_modulation_provenance!` (turn_modulated.jl 1883-1885) supplies `string(nameof(typeof(w.inner)))`; the arc-position map the probes use (`_ACTIVE_PROBE_S_MAP`, 1303) is not consulted for modulated elements, and neither the spec's `name` parameter nor its provenance path is written. Hypothesis 3 (provenance completeness: element labels); seed and `rng_id` are complete (see Clean). A design gap rather than a coding slip, reported because the brief names it.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 result/comprehensive_audit_2026_10_18/probes/U13/probe_D_recording.jl` -- section D1: a line of two `ThinCrabCavitySpec{1}` with `phase_noise` prints `element 1: element = "ThinCrabCavity"`, `element 2: element = "ThinCrabCavity"`, element group attrs `["beam", "element", "slot_count"]`.

### LEAD U13-8 [Minor, confidence low] src/tasks/RunArtifact.jl:412
Claim: The cursor is advanced by delete-then-create (`_ra_set_attr!`), so the rows-then-cursor protocol has an instant with no cursor at all; a writer that reopens a group in that state truncates every row, the ones below `first_turn` included.
Mechanism: `_ra_set_attr!` calls `delete_attribute` then creates the attribute anew (412-417) at every flush (1145, 1386, 1296, 1448); if HDF5's metadata cache persists the deletion and not the re-creation (an eviction under cache pressure, or a kill inside the flush), the next open reads the default `typemin(Int32)` (690-691, 1344-1345) and keeps zero rows -- not the conservative prefix the design promises but the whole group. Unmeasured as a kill (probe C's three rounds never produced the state); measured as the writer's response to the state. An in-place attribute write (HDF5.jl's `attrs(obj)[name] = v`, which overwrites a same-typed attribute) keeps a cursor present at every instant.
Repro: probe E section A7: delete `rows_valid_through_turn` from a 10-row luminosity group, continue with `append=true` at `first_turn=1000`: "rows after append-open ... = 0 (were 10, all below first_turn)".

### LEAD U13-9 [Minor, confidence high] docs/design/run_artifact.md:90
Claim: The design's schema table declares attributes the writer never stamps: `s` on `/luminosity/<label>` and a `provenance path` attribute on `/moments/<name>`.
Mechanism: The fresh-file branch writes `label` and `rows_valid_through_turn` only (670-673); `_ra_bind_probe!` writes `name`, `rows_valid_through_turn` and, for a line-placed probe, `s` (1353-1360). The readers follow the code (no `s` on a luminosity series, 1539). Defect class 14 (documentation as claims); `docs/design/run_artifact.md` lines 90 and 92.
Repro: probe E section A6 prints `/luminosity/ip attrs = ["label", "rows_valid_through_turn"]`.

### LEAD U13-10 [Minor, confidence high] docs/design/run_artifact.md:444
Claim: The design's concurrent-reader claim ("eight readers during a 3000-turn write, each a consistent prefix") cites its evidence in the git-ignored `result/` tree, which AGENTS.md declares "never evidence", and no committed harness reproduces it.
Mechanism: Line 444 names `result/.../auditor/probe_rw_reader2.log`; `docs/history/crab_cavity_noise_audit_fixes_2026_10_16.md` line 30 repeats the reference without the numbers or a script; `grep -rn probe_rw_reader2 docs/` finds only these two mentions. Defect class 14. (The kill measurement of this unit, probe C, is a different claim -- a killed writer, not concurrent readers -- and is itself committed only under `result/` by the audit protocol's own rule, so it is reported here as a measurement, not as evidence for the design note.)
Repro: `grep -rn "probe_rw_reader2" /cfs/ad/dxu/Library/Julia/Octopus/docs /cfs/ad/dxu/Library/Julia/Octopus/test /cfs/ad/dxu/Library/Julia/Octopus/validation` lists two prose mentions and no script.

## Clean

- **Hypothesis 1, a death mid-flush (probe C).** Three SIGKILLs of a writer flushing one luminosity row and one probe row per turn, at 2, 4 and 7 s: every file opened and read through `TaskOutput`; `turns` and `values` lengths equal; reader rows = cursor + 1 (1438, 2106, 2656 luminosity; 1438, 2105, 2655 probe); zero rows beyond either cursor; the ledger's `current_turn` leads the channel cursor by at most one turn, as the docstring at 1123-1127 states; the lock stays, as documented (147-150). Caveat: three rounds, kills between flushes rather than demonstrably inside one.
- **Hypothesis 1, the crash path with recording on (probe D2, D3).** An action raising at turn 7 of 10 (`capacity=4`) leaves 7 series rows, the reader's one warning naming the dataset, ledger `current_turn=6`, lock released; at `capacity=100` with a crash at turn 5 the finalize flushes the tail (5 rows, ledger 4). Matches `run_artifact.md` 188-199 and the `_tm_end_turn!` / `_ra_flush_turn_modulation!` code (1040-1095: partial-turn values dropped by `resize!`/`view(buf, 1:nvals)`, rows then ledger then flush).
- **The sidecar lock.** Taken before `isfile`/`ishdf5`/`h5open` (643-644), released on the not-HDF5 refusal (650), a failed open (661), every refusal inside the body (771), and at finalize after the close (1263-1266); the strong-strong observer-prepare refusal and both crash paths run through `finalize_run_artifact!` (interface.jl 2731, 2760, 2777; Tasks.jl 1043, 1074). Probe A4: an unreadable file (`chmod 000`) is refused by name with the lock released and a second writer accepted. Release compares the line it wrote (`_ra_release_lock!`, 563-581) and leaves a stranger's lock in place. Not measured: two processes racing for one `O_EXCL` create on this NFS mount (see Unchecked).
- **Hypothesis 2, writers vs schema.** Every dataset the design table (90-110) declares is written and read back by the code paths named: luminosity (667-674 / 1539), the three probe kinds (1316-1363 / 1541), `/losses` (1182-1240 / 1565-1591, every attribute read with a default where it was added later), `/execution` from the one column table `_RA_LEDGER_COLUMNS` (464-465; create 676-678, append 744-748, continue-check 711-719, reader 1598-1600), `/turn_modulation` attributes (905-947 / 1734-1817) and `series` (933-942 / 1674-1702), `state` reserved and read as `nothing` (1742, 1814). Exceptions are U13-9 (two declared attributes never written).
- **Hypothesis 2, the phantom row.** The ledger row is appended (744-748) only after `_ra_validate_turn_modulation!` (734) has run the slot-collision and column-walk refusals; a slot group is created only after the writer re-runs them (908). A failure between the row and the provenance leaves the documented partial slot, refused on append by `_ra_check_partial_slots` (801-817; probe A1b measured the refusal, with the U13-1 caveat).
- **The partial-slot reader.** `_ra_turn_modulation` 1734-1817: cursor beyond count torn (1746); partial slot admits `valid <= present <= valid + 1` groups, reads `1:valid`, warns once with the path (1748-1757); complete slot requires `present == n`; every attribute read without a default through `_ra_tm_attr`; a recorded element without nominals refused (1797-1801); series `columns` checked against the slot labels in index order and the data width against the column count (1681-1686); row count authoritative with warnings both ways (1687-1697).
- **Zero-column series unreachable.** `_turn_modulation_columns!` would emit an element with `active = []`, but both wrap sites return the bare element when every rule is `nothing` (crab_cavity.jl 441-447, rf_cavity.jl 571-577), so an `HDF5.dataspace((0, 0))` with `chunk=(256, 0)` is never requested.
- **Options reach their consumers (class 11).** `append` at 644; `capacity` at 1108 (luminosity), 1054 (series), BeamObservers.jl 968-969 (moments), BPMObserver.jl 320 (BPM), snapshots per fire by design; `record_turn_modulation` at 756 and 760, and the receipt's `recording` is derived from the recorders actually built (357), not from the request. The constructor refuses `append`, `capacity` and `record_turn_modulation` by name and type (250-261), `Bool` excluded from `capacity`.
- **Seed and stream provenance (hypothesis 3).** `rng_seed` is `UInt64` by construction (`_GLOBAL_RNG_SEED::Ref{UInt64}`, counter_rng.jl 23; `set_global_rng!` converts at the boundary), `rng_method` is the method's name; each slot group carries `rng_id`, `digest`, `name`, `length`, `kind` and the nominals. The gap is the element identity, U13-7.
- **The effectiveness contract and todo row 28 ("row 29" in the brief).** `Contracts.jl` 598-665 now reads the `:run_artifact_output` receipt under both task kinds and checks `append -> continued` (false then true), `record_turn_modulation -> recording` (true with a modulated element, false without), `capacity`, `execution` rows and task kinds; the receipt's `continued` is `!fresh` (782), the very value that chose the `h5open` mode (657), so it is a resolution, not an echo. What the contract still does not do is open the file (no check that the `series` dataset exists or that the continued file gained rows); that is exactly what the open row says, and the row's text predates the 2026-10-16 move of the pins from `:strong_strong_output` to `:run_artifact_output` (stale wording, not a defect).
- **Receipt ordering.** `:run_artifact_output` is recorded last on rank 0 (787) and at the early return on a non-root rank with `continued`/`execution` as `nothing` (633-637, 355-364); the task receipts follow the prepare (Tasks.jl 1376, interface.jl 2719).
- **Readers do not take the lock; one retry only on the open.** 1428-1439, with the `@info` keyed per path and lock line (1426). Caveat U13-5 on the message.

## Unchecked

- Cross-host atomicity of the `O_EXCL` lock create on the NFSv3 mount: not measured (one host available to this unit); the Linux client implements NFSv3 exclusive create with a verifier, but the design's own claim rests on it unmeasured.
- MPI non-root paths (`_mp_is_root() == false` branches at 633, 1103, 1329, 1372, 1184-1188): read, not executed under `mpiexec`.
- The CUDA arm: nothing in this file is device-reachable; not executed.
- A kill landing inside an `HDF5.flush` (the state U13-4 and U13-8 presuppose): three SIGKILL rounds did not produce it; whether it can arise with HDF5 1.14's metadata cache was not established either way.
- The `MomentOutput` HDF5 read path and `_selected_moments` (BeamObservers.jl), which `read(out, :moments; orders=...)` delegates to (2005-2009): outside the region, not read.
- The suite testsets covering this region (titles at runtests.jl 18094, 18432, 18644, 19695, 20271, 20504) were not re-run by this unit; the probes above reproduce the behaviours directly.
