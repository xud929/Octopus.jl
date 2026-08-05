# Reading unit U7 — `src/tasks/BeamObservers.jl` + `src/tasks/BPMObserver.jl`

**Commit audited:** `7de4d81` (63 commits past the previous audit's `6a3f39ab`).
**Region:** `src/tasks/BeamObservers.jl` (1,861 lines) and
`src/tasks/BPMObserver.jl` (324 lines) — **every line of both read**.
**Briefed hypothesis:** the producer↔consumer protocol seam; whether the F1/F3–F9
append/restart fixes (+331 lines in `BeamObservers.jl` since `6a3f39ab`) close
what they claim; torn writes and atomicity; silent row loss; ordering; and the
BPM measurement model against `docs/theory/bpm_measurement_model.md`.

Probe scripts and outputs live in this directory; nothing in the repository was
modified. Every number below was produced on this machine with
`julia --startup-file=no --project=/cfs/ad/dxu/Library/Julia/Octopus`,
Julia 1.12.4, CUDA functional.

---

## 1. Provenance

| what | how |
|---|---|
| `git diff 6a3f39ab HEAD` over both files | read in full |
| `BeamObservers.jl` 1–1861, `BPMObserver.jl` 1–324 | read line by line |
| `AGENTS.md` "Hard-Won Rules"; `docs/comprehensive_audit.md` "Measured Lessons" | read |
| `docs/theory/bpm_measurement_model.md` (233 lines) | read in full |
| `src/tasks/Tasks.jl` (906 lines) — `execute!`, prepare/flush context | read in full (reference, not region) |
| `src/tasks/strongstrong/interface.jl` `_prepare_strong_strong_luminosity_file!` | read (reference — the `.lum` twin) |
| F1, F3–F9 in `docs/history/comprehensive_audit_2026_08_05.md` §4 | read (only those entries) |
| `test/runtests.jl` "Every continuing observer drops its replayed window", "BPM reads a device number, not the truth", "Observer finalizers, BPM noise keys…" | read |
| `_misalign_matrix`, `_mean`, `_live_stat_flags`, `_host_coordinate_arrays`, `write_beam_coordinates`, `validate_configuration_metadata` | read (callees) |
| probes `p1`–`p14` | **executed** |

Probes executed (all in this directory):

- `p1_four_format_retry.jl` — the four-format crash/retry matrix.
- `p2_negctl_and_snapshot.jl` — negative control + snapshot on a non-empty file.
- `p5_bpm.jl`, `p6_bpm_cost.jl`, `p12_bpm_gpu.jl` — BPM model & cost.
- `p4_kill_and_cost.jl`, `p9_jld2_growth.jl` — format cost and growth law.
- `p10_child_fault.jl` + `p11_fault_driver.jl` — deterministic mid-flush death.
- `p7_misc.jl` — schedules, ordering, capacity=0, extension dispatch.
- `p13b_bpm_occurrence.jl`, `p14_snapshot_crash.jl` — targeted confirmations.

---

## 2. Hypothesis (a) — do the four-format fixes close what they claim? **YES**, measured, with a negative control.

Observers built at their **default** constructor settings (`capacity=1` for the
two moment observers, `append=true` for `CoordinateSnapshotObserver` — the
repo's own testset uses `append=false`, which is the weaker configuration).

Three scenarios per format, `p1_four_format_retry.jl`:

- **A** clean split: `execute!(turns=3)` twice.
- **B** real crash: an action throws at turn 4 of an 8-turn run; the retry
  replays turns 0–7 because `execute!` did not advance the stored turn.
- **C** explicit rewind: `execute!(turns=6)` then `execute!(turns=6, start_turn=3)`.

| format | A (want 0:5) | B after crash | B after retry (want 0:7) | C before (0:5) | C after (want 0:8) |
|---|---|---|---|---|---|
| Luminosity | `[0,1,2,3,4,5]` | `[0,1,2,3]` | `[0,1,2,3,4,5,6,7]` | `[0..5]` | `[0,1,2,3,4,5,6,7,8]` |
| JLD2 | `[0,1,2,3,4,5]` | `[0,1,2,3]` | `[0,1,2,3,4,5,6,7]` | `[0..5]` | `[0,1,2,3,4,5,6,7,8]` |
| binary | `[0,1,2,3,4,5]` | `[0,1,2,3]` | `[0,1,2,3,4,5,6,7]` | `[0..5]` | `[0,1,2,3,4,5,6,7,8]` |
| snapshot | `[0,1,2,3,4,5]` | `[0,1,2,3]` | `[0,1,2,3,4,5,6,7]` | `[0..5]` | `[0,1,2,3,4,5,6,7,8]` |

No duplicated turn label, no gap, in any cell. (Snapshot records carry no turn
label on disk, so the probe stamps the absolute turn into `x[1]` with an action
and reads it back per record — that is what makes the snapshot column
comparable to the other three.)

**Negative control** (`p2_negctl_and_snapshot.jl`): the four five-argument
`prepare_observer!` methods were overwritten with pre-fix no-ops and scenario C
re-run. All four then produce

```
[0, 1, 2, 3, 4, 5, 3, 4, 5, 6, 7, 8]
```

— turns 3, 4, 5 duplicated, matching the `[0,1,2,0,1,2,3,4,5]` the audit record
quotes. **The discard code is load-bearing and the closure claim is honest.**

Also checked by reading and confirmed by `p7_misc.jl` (F): the `AtTurns` planner
and `should_run` agree across a rewind — `AtTurns([7,2,9,4])`, `turns=6` gives
`[2,4]`; then `start_turn=3, turns=6` gives `[2,4,7]` (4 re-recorded, 7 added, 9
still outside the window).

**But the snapshot fix has a hole its own docstring names** — see LEAD U7-1.

---

## 3. LEADS

### LEAD U7-1 [Moderate, confidence high] src/tasks/BeamObservers.jl:1094
Claim: `_discard_replayed_snapshots!` truncates the file to preserve
coordinate records it cannot attribute, then sets `append = false`, so the very
next `observe!` reopens the file with `"w"` and destroys exactly the records it
just preserved.

Mechanism: the function's own docstring says "records in a pre-existing file the
object never wrote cannot be attributed and are **left alone**", and the
`truncate(io, offset)` at line 1091 honours that — `offset` is the byte position
*before* this object's first record, i.e. the end of the foreign data. But when
every one of the object's own records is dropped, line 1093–1094 does
`resize!(observer.written, 0)` and then `isempty(observer.written) &&
(observer.append = false)`. `observe!` (line 934–936) therefore computes
`offset = 0` and calls `write_beam_coordinates(path, rep; append=false)`, which
is `open(path, "w")` (`src/beam/Beam.jl:726`). The foreign prefix is gone. The
`append=false` reset is only correct when the object's base offset was 0; it is
applied unconditionally. This fires on the headline case — a crashed `execute!`
retried from turn 0 — because that always drops all of the object's records.

Repro: `julia --startup-file=no --project=<repo> p14_snapshot_crash.jl`.
Two foreign records are written to a path, a `CoordinateSnapshotObserver(path)`
(default `append=true`) crashes at turn 3 of a 6-turn run, then retries.
Observed:

```
pre-existing records            : [-1, -2]  bytes=104
after the crashed execute!      : [-1, -2, 0, 1, 2]  bytes=260
after the retry                 : [0, 1, 2, 3, 4, 5]  bytes=312
REQUIRED (function's own docstring): [-1, -2, 0, 1, 2, 3, 4, 5]
```

The rewind variant (`p2_negctl_and_snapshot.jl` part b) gives the same wipe:
`[-1,-2,0,1,2]` → `[0,1,2]`, 104 bytes destroyed silently.
Not covered by the repo's testset, which builds the observer with `append=false`
and asserts only a record *count*.

---

### LEAD U7-2 [Moderate, confidence high] src/tasks/BeamObservers.jl:1557 (`_jld2_replace!`), reached from 1549, 1550, 1019, 1020
Claim: a process death anywhere inside a `JLD2BeamMomentObserver` flush loses
the **entire** history, not the in-flight row — the F4 defect ("a kill in the
window lost the whole history", fixed for the `.lum` path with tmp+`mv`) is
unfixed in this twin, and the U6-2 discard added a second instance of it.

Mechanism: `_jld2_replace!` is `haskey && delete!(file, key); file[key] = value`
inside a `jldopen(path, "r+")`. `_append_jld2_moment_columns!` rebuilds the whole
`data` matrix (`vcat`) and pushes it through `_jld2_replace!` on **every** flush
— default `capacity = 1`, so once per observed turn. Between the `delete!` and
the re-write the file has no `data` key at all. The binary and HDF5 twins both
make the opposite promise (rows first, count second, F9); JLD2 makes none, and
`_discard_replayed_jld2_rows!` (new code) uses the same primitive.

Repro: `julia --startup-file=no --project=<repo> p11_fault_driver.jl`.
It monkeypatches each observer's write path to hard-`_exit` inside the window
(after `delete!`; after the rows but before the count; after the `/data`
hyperslab but before `/record_count`) and then inspects the file:

```
bin    after mid-flush death : count=10  rows_on_disk=11  count<=rows OK
h5     after mid-flush death : record_count=10  extent=40  size=18184
jld2   after mid-flush death : readable but NO /data key  (size=37097)
```

Ten flushed rows survive in the binary and HDF5 files; **zero** survive in the
JLD2 file, which opens cleanly and reports nothing.

---

### LEAD U7-3 [Moderate, confidence high] src/tasks/BeamObservers.jl:1531–1561
Claim: `JLD2BeamMomentObserver` file size is **quadratic** in the number of
flushes — a 2,000-turn default run writes 961 MB for 960 KB of data (1,001×) —
because JLD2 never reclaims the space of the dataset `_jld2_replace!` deletes.

Mechanism: every flush appends a complete copy of the growing `data` matrix, so
the file accumulates `Σ_{k=1..n} 8·ncol·k = 4·ncol·n·(n+1)` bytes. `ncol = 60`.
`_discard_replayed_jld2_rows!` adds one more full copy per prepare.

Repro: `julia --startup-file=no --project=<repo> p9_jld2_growth.jl`.

| rows | file bytes | quadratic model `4·60·n·(n+1)` | useful `8·60·n` | blowup |
|---|---|---|---|---|
| 100 | 2,458,457 | 2,424,000 | 48,000 | 51× |
| 200 | 9,708,857 | 9,648,000 | 96,000 | 101× |
| 400 | 38,609,657 | 38,496,000 | 192,000 | 201× |
| 800 | 154,011,257 | 153,792,000 | 384,000 | 401× |

Model agrees to 1.4%, 0.6%, 0.3%, 0.1% — mechanism confirmed, not inferred.
`capacity` divides it only linearly (800 turns: cap 1 → 154 MB/5.9 s,
cap 10 → 15.6 MB/0.53 s, cap 100 → 1.74 MB/0.065 s). Cross-format at 2,000
turns (`p4_kill_and_cost.jl`): binary 0.043 s / 544 KB, HDF5 0.601 s / 455 KB,
**JLD2 19.47 s / 961 MB**. Extrapolated to a 100,000-turn run the JLD2 file is
~2.4 TB. Nothing in the docstring or the option schema warns.

---

### LEAD U7-4 [Moderate, confidence high] src/tasks/BeamObservers.jl:1745 (`_is_hdf5_output`), consumed at 1669–1678 and 1704–1709
Claim: `MomentObserver` writes HDF5 to whatever path it is given, but
`read(MomentOutputFile(path))` picks its reader from the **filename extension**;
on a non-`.h5`/`.hdf5` path the read goes down the JLD2 branch, which ignores
`/record_count` and returns fabricated all-zero rows carrying duplicate turn
labels.

Mechanism: `_initialize_hdf5_moment_file!` calls `HDF5.h5open(path, "w")`
unconditionally, and preallocates `planned_records` rows. `_is_hdf5_output` tests
only `splitext(path)[2] ∈ (".h5",".hdf5")`. For any other extension `read` falls
to `read_moment(path, :data)`, which returns `file["data"]` whole — the
`/data[1:record_count, :]` slice its own docstring promises is never applied.
JLD2 reads the HDF5 file successfully (with a "File likely not written by JLD2"
warning), so the failure is silent-wrong-data, not an error.

Repro: `julia --startup-file=no --project=<repo> p9_jld2_growth.jl` (section D).
A `MomentObserver("m.dat"; orders=1, capacity=1)` run crashes at turn 3 of an
8-turn window:

```
/data rows=8  /record_count=3
Octopus._is_hdf5_output("m.dat") = false
read(MomentOutputFile) returned rows=8   turn column=[0, 1, 2, 0, 0, 0, 0, 0]
(an .h5 path would have returned 3 rows)
```

Five fabricated rows, four extra rows labelled turn 0 — the exact "two rows for
one turn is corrupt for every reader" failure the whole idempotence campaign was
about, arriving through the reader instead of the writer.

---

### LEAD U7-5 [Moderate, confidence high] src/tasks/BPMObserver.jl:200–205 (`_bpm_centroid`)
Claim: on a CUDA beam a BPM reading copies **all six** coordinate arrays to the
host every time, so one reading costs 77 ms at the production benchmark size —
168× the `MomentObserver` device path for the same two numbers — while the
function's own docstring justifies its existence with "a lattice can hold
hundreds of BPMs read every turn".

Mechanism: `_bpm_centroid` calls `_host_coordinate_arrays(rep)`, which is
`map(_host_array, coordinate_arrays(rep))` and therefore `Array(v)` for each of
x, px, y, py, z, pz (`src/beam/Beam.jl:587`). Four of the six are used only when
`allow_lost_particles()` is on (off by default), and even then the mask is
computable on device — the CUDA `_moment_observer_row`
(`BeamObservers.jl:1440–1472`) does exactly that with `sum` and broadcast
`ifelse`. At 2.56M particles the copy is 6 × 2.56e6 × 8 B = 123 MB per reading.

Repro: `julia --startup-file=no --project=<repo> p12_bpm_gpu.jl` (each timer
individually warmed, 10 reps):

```
N=250000    observe!=   4.82 ms   host copy(6 arrays)=  37.86 ms   device sum(x)+sum(y)=0.075 ms   MomentObserver 2 means=0.173 ms   BPM/Moment=  28x
N=1000000   observe!=  18.01 ms   host copy(6 arrays)=  41.96 ms   device sum(x)+sum(y)=0.060 ms   MomentObserver 2 means=0.189 ms   BPM/Moment=  95x
N=2560000   observe!=  76.84 ms   host copy(6 arrays)=  58.45 ms   device sum(x)+sum(y)=0.074 ms   MomentObserver 2 means=0.456 ms   BPM/Moment= 168x
```

For scale: the recorded production point is 2.56M/1.024M at ~0.3 s per turn.
A *single* BPM adds ~26% to a turn; the "hundreds of BPMs" the docstring
contemplates would add tens of seconds per turn. The measurement is allocation-
noisy (six fresh host arrays per call), which is why the two component timers do
not add exactly — the conclusion does not depend on that.

---

### LEAD U7-6 [Low, confidence high] src/tasks/BeamObservers.jl:1280–1286
Claim: F3's "loud replacement" mitigation only fires when the whole table is
dropped (`kept == 0`); a fresh task given a wrong-but-nonzero `start_turn`
destroys the tail of an appendable table silently.

Mechanism: `_moment_append_continue!` computes `kept` by binary search, then
warns only under `written > 0 && kept == 0`. Any `first_turn` strictly inside the
recorded range leaves `kept > 0` and drops `written - kept` rows with no signal.
That is the intended idempotence rule for a deliberate rewind, but it is
indistinguishable from the F3 scenario (a fresh task whose caller does not know
the resume point).

Repro: `julia --startup-file=no --project=<repo> p7_misc.jl` (section B).
A 10-row appendable table, then a **fresh** task with `start_turn=1, turns=2`:

```
rows after first run                        10
rows after fresh task, start_turn=1         3
turn column                                 [0, 1, 2]
```

Nine rows destroyed, no warning, exit status clean.

---

### LEAD U7-7 [Low, confidence high] src/tasks/BeamObservers.jl:1038–1042
Claim: `_discard_replayed_binary_rows!` has no `filesize > 0` guard — the F7 fix
that `_prepare_moment_observer!` (line 1230) and the `.lum` twin both carry — so
a zero-byte file makes the prepare die with a bare `EOFError`.

Mechanism: after `(observer.initialized && isfile(observer.path)) || return`, the
function immediately does `read(io, Int32)` twice. On a zero-length file that is
`EOFError`, with no message naming the path or the observer. F7's disposition
for the HDF5 twin was "a zero-byte leftover from a crash at create time is not a
table; it is replaced fresh"; the binary twin neither replaces nor explains.

Repro: `julia --startup-file=no --project=<repo> p7_misc.jl` (section G) —
observe 2 turns, truncate the file to 0 bytes externally, rewind:

```
zero-byte file, same object rewind          THROWS EOFError : EOFError: read end of file
```

Reachability is genuinely low (`initialized` is monotone within an object, so the
file must be truncated by something outside the observer). Reported because the
asymmetry with F7 is what makes the class regenerate, not because the case is
common.

---

### LEAD U7-8 [Low, confidence med] src/tasks/BeamObservers.jl:1518–1605
Claim: the JLD2 column layout is hand-copied into **three** independent places
with no tripwire — Measured Lesson 4 ("hand-copied knowledge always drifts;
derive, plus a tripwire") in a region that has no coverage of the invariant.

Mechanism: `_jld2_moment_column_names()` (line 1518) builds the 60 names;
`_jld2_moment_ranges()` (line 1579) hardcodes the offsets `turn=1:1, mean=2:7,
covariance=8:43, rms=44:49, emittance=50:52, xz=53:53, yz=54:54,
diagonal_fourth_central=55:60`; `_jld2_moment_data_matrix` (line 1592) hardcodes
the same offsets a third time as `col += 6 / += 36 / += 3 / …`. Adding or
reordering a column in one place silently mislabels `read_moment(:emittance)`
from the others. The three currently agree (I checked the arithmetic:
1+6+36+6+3+1+1+6 = 60).

Repro: `grep -rn "_jld2_moment_ranges\|_jld2_moment_column_names\|_jld2_moment_data_matrix" --include='*.jl' .`
returns hits only inside `src/tasks/BeamObservers.jl` — no test, no contract, no
consistency check anywhere in the repository.

---

### LEAD U7-9 [Low, confidence high] src/tasks/BeamObservers.jl:1223
Claim: `MomentObserver(capacity=0)` silently skips the predictable-schedule
validation *and* leaves any previous file at `path` in place, so a stale table
looks like current output.

Mechanism: `_prepare_moment_observer!` returns at line 1223 before
`_scheduled_turns` is consulted and before `_initialize_hdf5_moment_file!` runs.
The documented meaning of `capacity = 0` is "disables output", but "disables
output" and "leaves last run's file untouched" are different promises.

Repro: `julia --startup-file=no --project=<repo> p7_misc.jl` (sections C, D):

```
rows written with capacity=1                4
rows after a capacity=0 re-run              4
PredicateSchedule capacity=1                throws ArgumentError
PredicateSchedule capacity=0                NO ERROR; file exists=false
```

---

### LEAD U7-10 [Low, confidence high — out of contract] src/tasks/BeamObservers.jl:1152–1176
Claim: two `BeamMomentObserver`s writing one path silently interleave and lose
rows; the file ends up self-consistent and wrong.

Mechanism: `_initialize_moment_file!` opens `"w"` unconditionally on a fresh
object, truncating whatever another observer wrote. `_discard_replayed_binary_rows!`
then re-reads the count from disk at the next prepare, so the surviving observer
resyncs onto the *other* writer's rows and appends after them. No warning
anywhere. (I originally suspected a seek-past-EOF hole; the discard's re-read of
the on-disk count prevents that — a genuine incidental benefit of the new code,
recorded here so the next reader does not re-derive the wrong mechanism.)

Repro: `julia --startup-file=no --project=<repo> p9_jld2_growth.jl` (section C):

```
after 4 turns: size=1334  observer.record_count=4
after a second observer wrote 2 turns: size=790  reported_count=2
after the FIRST observer flushed again: size=1334
turn column read back = [0.0, 1.0, 4.0, 5.0]
```

Turns 2 and 3 are gone; the file reports 4 valid rows. Marked out of contract
because nothing documents path sharing for the binary observer — but the
`MomentObserver` docstring *does* document "a second task sharing the path",
so a user may reasonably expect the same of its siblings.

---

### LEAD U7-11 [Low, confidence high] src/tasks/BPMObserver.jl:170–171, 179–187
Claim: `bpm_reading` mutates the observer. The exported convenience form
`bpm_reading(bpm, xbar, ybar, turn)` consumes an occurrence index, so a
read-only-looking call changes the noise of every later reading of that BPM in
the same turn.

Mechanism: `_bpm_noise_occurrence!` increments `bpm.noise_uses` on every call
with a nonzero-noise BPM. Neither the `bpm_reading` docstring ("Apply the device
model to a centroid and return `(x_read, y_read)`") nor the type's docstring says
the call is mutating, and the function has no `!`. The effect is masked in the
common case because `_bpm_discard_window!` resets the counter at every
`prepare_observer!`, i.e. once per `execute!`; it survives inside one `execute!`.

Repro: `julia --startup-file=no --project=<repo> p13b_bpm_occurrence.jl` — one
`execute!(turns=4)` with an action that peeks via `bpm_reading(b,0,0,ctx.turn)`:

```
recorded readings, no peek : [2.0933e-5, 6.7091e-6, 8.0939e-6, -6.9285e-6]
recorded readings, w/ peek : [1.3633e-6, -8.9485e-7, 4.8809e-6, -1.2806e-5]
identical = false
```

---

### LEAD U7-12 [Low, confidence high] src/tasks/BPMObserver.jl:200–205
Claim: a BPM reading of a fully-lost beam is `NaN` by an undocumented `0/0`,
where the moment observer's identical situation is an explicit, commented branch.

Mechanism: `_bpm_centroid` computes `nlive = flags === nothing ? length(rep) :
count(flags)` and passes it to `_mean(v, flags, nlive)`, which returns `s/nlive`.
With `nlive == 0` that is `0.0/0` = `NaN`. `_moment_observer_row`
(`BeamObservers.jl:1420–1423`) handles the same case deliberately —
"An all-dead beam has no moments to report. `NaN` is the honest value, and the
turn column stays intact" — and says so. The BPM arrives at the same answer by
accident and documents nothing.

Repro: `julia --startup-file=no --project=<repo> p5_bpm.jl` (section 9), under
`allow_lost_particles(; enabled=true)` with a single NaN particle:
`all-dead beam reading = (NaN, NaN)`.
The behaviour is right; only its provenance and documentation are not.

---

### LEAD U7-13 [Low, confidence med — structural] src/tasks/BeamObservers.jl:934–937
Claim: the compact coordinate record format has no framing or length check, so a
torn record makes every later record unreadable, and the `(turn → byte offset)`
map cannot repair it.

Mechanism: each record is `UInt32(n)` then `6n` `Float64`s back to back. A
partial write leaves a record whose declared `n` does not match the bytes
present; a sequential reader then mis-frames everything after it.
`observe!` computes the next offset from `filesize`, so the map faithfully
records offsets into an already-corrupt file, and `_discard_replayed_snapshots!`
truncating to one of them cannot recover the framing. The `.lum` twin got
explicit torn-last-line handling in F1; this format has no equivalent and no
way to add one without a format change.

Repro: none run — this is an argument from the format definition
(`src/beam/Beam.jl:716–724`) plus `observe!`'s use of `filesize`. Recorded as a
structural lead, not a measurement.

---

## 4. Clean list — what was checked and found sound, with the evidence

**Hypothesis (a) — the four-format discard.** Sound. Section 2's matrix plus the
negative control: with the four `prepare_observer!` methods stubbed out, all
four formats duplicate turns 3–5; with them in place, all four give exactly
`0:8`. Additionally, the discards resync `record_count` from the file
(binary) and from the dataset (JLD2), so an out-of-date in-memory count cannot
desync the write offset.

**Hypothesis (b) — atomicity, partial credit.**
- `_discard_replayed_luminosity_rows!` (line 990–996) writes
  `path * ".prepare.tmp"` and `mv`s over — atomic, matching F4's fix in the
  `.lum` twin. Read and confirmed.
- `_flush_moment_buffer!` (binary, F9's rewrite) — measured crash-safe:
  deterministic death after the rows and before the count leaves
  `count=10, rows_on_disk=11`, i.e. count ≤ rows, file readable. F9's promise
  holds under a real interruption.
- `_flush_moment_observer!` (HDF5) — measured crash-safe the same way:
  `record_count=10, extent=40`, file readable, reader returns 10 rows.
- `_discard_replayed_binary_rows!` — writes the *smaller* count before
  `truncate`, so the on-disk count is ≤ the rows on disk at every instant.
  Read; the ordering is correct by inspection and consistent with F9.
- `_discard_replayed_snapshots!` — a single `truncate` syscall.
- JLD2 is the exception: LEAD U7-2.

**Hypothesis (c) — silent row loss.** No unbounded or unchecked buffer write
found.
- `BeamMomentObserver` / `JLD2BeamMomentObserver` buffer into `Vector`s and
  flush at `length >= capacity`; no fixed bound to overrun.
- `MomentObserver` buffers into `Matrix(undef, max(capacity,1), ncols)` and
  flushes at `buffer_length >= capacity`, so the index cannot exceed the
  allocation; over-planning is a directed `error(...)` (F6's fix, line 1370)
  rather than the old `BoundsError("<message>")`.
- Schedule/plan agreement checked for all three predictable schedules by reading
  `_scheduled_turns` against `should_run`, and measured for `AtTurns` across a
  rewind (`p7_misc.jl` F: `[2,4] → [2,4,7]`).
- `PredicateSchedule` + `MomentObserver` throws a directed `ArgumentError`
  (measured) — except at `capacity=0` (LEAD U7-9).
- `capacity == 0` is reported as `:inactive_dependency` with "zero capacity
  disables output" in `configuration_report`, so it is not silently ignored
  configuration.
- `observe!(CoordinateSnapshotObserver)` throws on `npart > length(rep)` before
  reaching `write_beam_coordinates`'s silent `min` clamp.
- `finalize_observers!` / `_finalize_line_observers!` run every finalizer even
  when one throws (T7), so a broken observer cannot discard a later one's buffer.
  Read; the nesting in `Tasks.jl:519–528` matches.

**Hypothesis (d) — ordering.** Clean. There is no `Dict` or `Set` iteration on
any output path.
- `_hook_tuple` preserves order for `Tuple` and `AbstractVector` and throws a
  `MethodError` for anything else; `classify_task_hooks`/`_push_task_hook!`
  preserve declaration order and throw a directed `ArgumentError` on an
  unsupported hook type.
- `AtTurns` holds a `Set` but `_scheduled_turns` `sort!`s it and `should_run`
  only tests membership.
- `_selected_moments` ends in `sort!` over a total order (`Base.isless(::Moment,
  ::Moment)` keys on `(sum(powers), -powers...)`), so column order does not
  depend on user input order — as the docstring claims.
- `_read_hdf5_selection`'s `Dict` is a lookup table; iteration is over the
  sorted `requested` tuple.
- `run_observers!`/`run_actions!` are serial loops on the calling thread, invoked
  after `track!` returns; no thread can interleave an observer with tracking.
- Measured (`p7_misc.jl` E): three hooks, one on `EveryNSteps(step=2)`, give
  `a@0 b@0 c@0  a@1 c@1  a@2 b@2 c@2` — declaration order, inactive hooks
  skipped in place.

**Hypothesis (e) — the BPM measurement model.** Sound, and all five of the
theory note's §7 checkable claims verified independently
(`p5_bpm.jl`, `p6_bpm_cost.jl`):

| note §7 claim | measured |
|---|---|
| 1. zero-error BPM reproduces the moment centroid | **bitwise identical** through the real observer path: BPM `(0.003, 1.0842021724855044e-19)` vs `beam_statistics.mean` `(0.003, 1.0842021724855044e-19)` |
| 2. every error term reaches the reading | all nine move it; inert set empty |
| 3. MAD-X limit `(1+MSCALX)x + MREX` | `0.00457` exactly, `g=0.5, b=7e-5, x=3e-3` |
| 4. a BPM does not perturb tracking | bit-identical x, px, y, py over 5 turns through a drift+quadrupole line |
| 5. noise reproducible across chunks and matching σ | `(10,)` vs `(3,3,4)` chunking gives identical turn/x/y vectors; 20,000 draws give σ = 9.9636e-6 for a requested 1.0e-5, mean −3.6e-8 |

Plus the note's §2 architecture argument, re-measured: `MarkerSpec()` and
`MarkerSpec(x_offset=1e-3, y_offset=-8e-4)` produce **bit-identical** maps
(max difference exactly `0.0`) — the misaligned zero-length element really does
return its input, so the offset genuinely cannot live in the map. The offset
lives in `bpm_reading` (`BPMObserver.jl:149–150`) and subtracts, Bmad's sign,
verified: a BPM at `+1 mm` reads a design-axis beam at `−1 mm`.

The rotation convention was traced through `_misalign_matrix(T,0,0,tilt,false)`
= `R_z(ψ)` row-major; `c, s = W[1], W[4]` picks `(cos ψ, sin ψ)` and the code
applies `[c s; −s c]`, which is AT's `rel` and Bmad's `M_m` at zero crunch —
measured to agree with `(cos θ·x̄ + sin θ·ȳ, cos θ·ȳ − sin θ·x̄)` at θ = 0.37.
The claim "`tilt = psi` means one thing everywhere in Octopus" holds: this is the
same `Q'a` contraction `_frame_change` uses.

The note's §6 deferred list was checked against the code — **crunch**, the
**error/calibration pairing**, `n_sample`/dispersion/phase, single-plane
monitors, and charge/intensity dependence are all genuinely absent, none
half-implemented. §6's "naming and discovery" item is the one place the note has
drifted: it says observers have no naming scheme, while `BPMObserver` does carry
a `name::String` that reaches the execution record and the configuration report.
That is the note being conservative, not the code being wrong.

**BPM test coverage is real and I was wrong to suspect otherwise.** `test/runtests.jl`
has a dedicated testset ("BPM reads a device number, not the truth", line 4051)
that covers §2's marker identity, §7.1–§7.5, both sign conventions, the tilt at
π/2, all nine effectiveness cases, and the negative-σ rejections; plus the T8/T9/
T11 noise-key tests at line 2817 and the chunk-invariance/idempotence tests at
2898–2930. `validate_configuration_metadata()`
(`src/tasks/strongstrong/interface.jl:1758–1790`) includes `BPMObserver()` and
carries a `subtypes(AbstractBeamObserver)` tree guard so the next observer cannot
repeat U3-4. The one committed gap: the BPM's optional TSV `path` output and
`_bpm_discard_window!`'s TSV rewrite are never exercised — I verified them by
probe (`p5_bpm.jl` item 10: memory `[0..8]` and TSV `[0..8]` after a rewind).

**Other things read and found sound:** the `Moment` name grammar and its
round-trip (compact vs `_`-separated, multi-digit); `_moments_for_order`'s
recursive enumeration; the CPU/CUDA `_compute_moment` pair including the
"zero the dead *after* the product" argument (masking each factor would leave
NaN — correct, and the CUDA path uses `ifelse` for exactly that reason);
`_moment_live_flags`'s single shared mask and its docstring's coupling argument;
the `(turn → byte offset)` map's construction in `observe!`; the method-overwrite
NOTE at line 230–235 (`prepare_line_observer!(::AbstractBeamObserver, ::Any,
::Any)` really would be shadowed by a 3-arg `(observer, turns, first_turn)`
method, and every new discard method correctly supplies both arities);
`BPMObserver`'s two prepare methods typed on the concrete type for the same
reason; the F8 docstring relocation onto `BeamSwapAction`; `_jld2_moment_ranges`
arithmetic (60 columns, ranges consistent); and the covariance
`(n,6,6) → (n,36) → (n,6,6)` reshape round trip.

---

## 5. Not checked, and why

- **A true SIGKILL race.** `p8_kill2.jl` sent `SIGKILL` to child writers at
  1.2–3.2 s into 400,000/30,000/3,000-turn runs; every child nevertheless
  completed (`reported_rows` equal to the full run), so the kill never landed
  inside the write loop and the probe measured nothing. I substituted
  deterministic in-process fault injection (`p11_fault_driver.jl`), which
  reproduces the *code* window exactly but not OS page-cache reordering or a
  power loss. **What the filesystem leaves after an un-clean shutdown is
  unverified** for all four formats.
- **`LuminosityObserver` luminosity values.** The probes used a drift line, so
  every `luminosity(elem, ctx, rep)` returned 0.0 and the rows are `turn\t`.
  The turn-label protocol is what I was briefed to test; the value path and the
  `requires_elementwise_tracking` isolation it depends on were read, not run.
- **CPU/CUDA numerical parity of `_moment_observer_row`.** Both paths were read
  and the masking argument checked; no cross-backend numbers were measured.
  That is a backend-parity question other units own.
- **`src/tasks/strongstrong/interface.jl`'s `.lum` prepare.** Read as the
  reference twin; the asymmetries I found (torn-line handling, header
  validation, malformed-row refusal — all present there, all absent from
  `_discard_replayed_luminosity_rows!`) are **not** reported as leads because I
  established by reading that `LuminosityObserver` has no cross-process
  continuation at all: `_discard_replayed_luminosity_rows!` is gated on
  `observer.initialized`, which only a same-process write sets, and a fresh
  object's first `observe!` opens with `"w"`. A torn line therefore cannot
  survive into a discard. **This is a cross-file seam and it is the auditor's
  call, not mine** — flagging it here rather than as a lead.
- **`docs/todo.md` and the open-queue rows.** Outside my region.
