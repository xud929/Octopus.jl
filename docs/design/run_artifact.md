# The run artifact: one output file per task

**Status: decided 2026-08-18 (owner discussion); implemented 2026-08-18, all
four migration steps.** The archive's "The run artifact: one output file per
task" row is the full implementation record. Step 4 went further than the
"adapters, deprecated on the owner's schedule" wording below: the owner
retired the standalone writers outright (the text luminosity observer
deleted; the per-observer file paths and `loss_log=` throw precise migration
errors), with the reader surface landed first: ONE handle,
`read(TaskOutput(path), kind; name=..., column=..., turn=...)`, the bare
`read` returning the table of contents and `:all` the whole file, with
`MomentOutput(path; name=...)` for Moment-aware selection (owner
direction, 2026-08-18 — one `read` from discovery to data, not one function
per product). Buffering unified the same day (owner direction): the
"per-product buffer" ownership in the table below moved to the SINK —
`RunArtifact(path; capacity=...)` is the one batching knob for every
producer, and the per-observer `capacity` keywords retired with the
writers. Of the deferred niceties, the s-position
attributes LANDED 2026-08-19 (probes stamp `attrs: name, s` at bind, from
the one U11-1 arc walker; the reader surfaces `s` beside the columns);
weak-strong label names and a first-class live text mirror remain an open
ledger row. Prerequisites had landed before implementation: the luminosity-sink
unification (2026-08-17), the keyword retirement, and the weak-strong
fresh-observer append fix (2026-08-18). The artifact's third option,
`record_turn_modulation` (stage 1 of `turn_modulation_record.md`, landed
2026-10-15, record `../history/turn_modulation_record_2026_10_15.md`),
records the turn-modulation rules' offsets turn by turn, and the artifact's
options gained their structured metadata the same day, the exported
`run_artifact_option_schema()`; see "Artifact options" and the
turn-modulation series paragraph of the schema below.

## The problem

A task's run currently scatters its story across three to five files with
three independent file-handling stacks: the `.lum` text file (append,
replay-drop, torn-line detection, header contract), per-observer HDF5 moment
files (their own append and capacity), coordinate snapshots (byte-offset
replay maps), BPM output (capacity, flushed cursor), and the loss log
(`write_loss_record`). The append/replay/capacity/registry logic exists in
several implementations that converged in capability while staying separate
in code — the same maintained-twice shape the luminosity unification closed
one level down. And the products the task generates each turn keep growing:
losses, luminosity, moments, snapshots, BPM readings, with more to come.

## The decision

**One HDF5 artifact per task**, owned by the task, with one group per
producer. Everything below follows from a two-axis split the discussion
sharpened:

### Probes versus channels

- **Probes** are observation points the USER PLACES: moment observers,
  coordinate snapshots, BPMs. Observation is a choice; position is part of
  the probe's identity; multiple instances per line are legal and
  meaningful. Probes stay line-placed (their `s` is physical) and their
  constructors keep choosing WHAT to record (which moments, which
  coordinates).
- **Channels** are products INTRINSIC to physics elements: luminosity from
  collisions and strong beams, losses from apertures. The element exists for
  physics reasons; the user either collects its product or does not.
  Channels are declared on the PRODUCER:
  - `StrongStrongCollision` declares its luminosity channel — it already
    owns the compute schedule (`luminosity_schedule`, since evaluation
    costs real solver work), and the declaration belongs beside it;
  - `ThinStrongBeamSpec`/`GaussianStrongBeamSpec` declare the weak-strong
    luminosity channel — they already carry `last_luminosity` and `klum`,
    i.e. they were the producers all along;
  - apertures declare the loss channel (they already do, through
    `LossRecord`).

  The name "LuminosityObserver" conflates the two ideas; it remains the
  working API through the migration, and the end state spells the channel
  as a declaration on the producer.

### What each party owns

| concern | owner |
|---|---|
| which quantities | the probe/channel constructor |
| where produced | line placement (probes) / the producing element (channels) |
| which turns | the per-product schedule (compute schedule for costly channels; observation schedule for probes) |
| buffering | the per-product buffer (capacity posture below) |
| the sink | the TASK: one artifact, open/append/replay/finalize, exactly once |

### Artifact schema

One group per producer, position and provenance as attributes:

    /luminosity/ip6          (turns, values)   attrs: label, s
    /luminosity/ip8          (turns, values)
    /moments/IP6             scheduled blocks  attrs: name, s, provenance path
    /moments/ARC1_QF3
    /snapshot/injection      coordinate blocks attrs: name, s
    /bpm/BPM_07              readings          attrs: name, s
    /losses                  the write_loss_record layout (names, counts,
                             aperture_s, per-loss rows, summary); a
                             TrackingTask's one beam; rows and counts span
                             every window of a continued file under the
                             replay rule, the summary is the last execute!'s
                             beam (the /losses paragraph under Crash recovery)
    /losses/beam_1           a StrongStrongTask's: one subgroup per beam
    /losses/beam_2           whose line carries an aperture, each in the
                             layout above and under the same replay rule
                             (2026-10-19; the reader returns them keyed by beam)
    /turn_modulation/3/1/phase_noise[1]   attrs only: element_count on the
                             execution slot (/3 = ledger row 3); element, beam,
                             slot_count per element; index, kind, rng_id,
                             digest, name, length per slot, and the slot's
                             nominals (nominal_phase, nominal_strengthX,
                             nominal_strengthY; RF: nominal_phase,
                             nominal_strength)
    /turn_modulation/3/1/series           (turns x active slots) Float64, the
                             recorded offsets, with record_turn_modulation
                             = true only; attrs: columns, first_turn, turns
    /turn_modulation/3/state              RESERVED for a stateful rule's
                             checkpoint (turn_modulation_record.md, D10);
                             written by nothing today

**Independent turn axes per dataset.** This is the payoff of declaring
channels on producers: each collision writes its own `(turns, values)` pair,
so per-IP luminosity schedules may disagree freely — and the mixed-IP
row-drop machinery (drop the row WHOLE, warn, count) becomes unnecessary
rather than ported. A workaround evaporating is the sign the decomposition
is right. The weak-strong per-element luminosity columns split the same way.

**Names are identities.** Every probe takes a `name`, defaulting to its
beam-line provenance path (`ARC1/CQS[3]` — machinery that exists), unique
within a task, enforced loudly. This finally supplies the "observer identity
scheme" the original BPM design note deferred (archived ledger, BPM row).

**Turn-modulation provenance.** `/turn_modulation/<slot>` records what the
line's turn-by-turn modulation rules were for the `execute!` whose
`/execution` ledger row is `<slot>` (`docs/design/turn_modulation.md`, D7:
the table rule is a pure consumer and owns its provenance in the run
artifact). One subgroup per `execute!` that had a modulated element, with
`element_count` and the cursor `elements_valid_through` (the partial-slot
paragraph under Crash recovery); below it one subgroup per modulated element
in line order
with `element`, `beam` (1 for a `TrackingTask` line; a strong-strong
artifact records both lines, beam 1's elements then beam 2's) and
`slot_count`; below that one subgroup per ACTIVE slot named by the slot
label with `index`, `kind` (the rule's `_rule_kind` label, one of the
vocabulary `_turn_rule_kinds()` derives from the rule catalogue: `white`,
`pink`, `table`, and `spectral` for the spec-level `SpectralNoise`, which
resolves to a table at compile and so never reaches a file; the readers
warn by name on a kind outside the vocabulary and the suite pins every text
naming it to the derived set -- 2026-10-16, S4-5), the stream rule's
`rng_id`, the table's `digest` (FNV-1a 64 over its bytes), `name` and
`length`, zeros and `""` where a field does not apply. Attributes only, no
turn axis; written at prepare from the receipt the task records; nothing is
ever deleted or rewritten, so a continued `append=true` file keeps every
generation of rules it ran. An unmodulated `execute!` writes nothing for its
slot: an empty `turn_modulation_provenance(path)` (or `read(out,
:turn_modulation)`) means no `execute!` recorded in this file had a
modulated element -- a file from before the group existed reads the same,
and neither is an error. Counts that disagree with the subgroups present
mark a torn group, refused by name.

**Turn-modulation series.** With `record_turn_modulation = true` on the
`RunArtifact` (`turn_modulation_record.md`, D3-D8; stage 1 landed
2026-10-15, record `../history/turn_modulation_record_2026_10_15.md`), the
same execution-slot group gains, under each modulated element `<k>`, one
two-dimensional `Float64` dataset `/turn_modulation/<slot>/<k>/series` of
`turns` rows by one column per ACTIVE slot in provenance order (extendable,
chunked `(256, ncols)`, created with zero rows at prepare), with the
attributes `columns` (the slot labels in column order), `first_turn` and
`turns` (the window, as the receipt records it). Row `i` holds the offsets
the rules produced for absolute turn `first_turn + i - 1`: radians on a
phase slot; on a strength slot the dimensionless relative factor `d` that
scales both planes' strengths of the harmonic, `S_X (1 + d)` and
`S_Y (1 + d)` (the RF cavity's compiled `strength`, `qV/(P0 c)`, likewise).
The offsets are recorded, not the realised values, which are the thing
under test; the nominals a reader needs to form them are attributes of each
active slot's group beside `index` and `kind` (`nominal_phase`,
`nominal_strengthX`, `nominal_strengthY` on a crab cavity slot, the
harmonic's three parameters on both of its slots; `nominal_phase`,
`nominal_strength` on an RF cavity slot), written by the provenance writer
at prepare WHETHER OR NOT the run records, so the realised phase is
`nominal_phase + d` and the realised strength `nominal_strengthX * (1 + d)`
exactly as the element forms them, while an offset recovered from element
fields, `(S + d) - S`, would miss a replay by a relative 1e-12. The rows are
the draws of the very evaluation that built the realised element
(`_realize_draws`, whose two-element projection is `realize`; the recording
form of the hook, `update(elem, ctx, sink)`, hands them to the sink in line
order) -- the recorder never reads the compiled element and never
re-evaluates a rule. The sink is a `TurnModulationRecorder`, one per beam
that has a modulated element, built by `prepare_run_artifact!` on rank 0
only and resolved once per `execute!` by `_turn_modulation_sink(art, beam)`
(`nothing` with no artifact, the switch off, a non-root rank or no modulated
element, and `nothing` IS the plain hook: one dispatch, zero allocation);
`_tm_begin_turn!` opens each turn's row and `_tm_end_turn!` closes it,
checking that every element the provenance lists was met exactly once -- a
miscount drops the turn's partial values and raises, naming the beam and
the turn, never writing a misaligned column -- and the complete rows are
appended every `capacity` turns and at finalize, the batching the
luminosity rows take, so after a crash the dataset holds the turns
completed through the last flush. The row count is authoritative: a dataset
shorter than its `turns` attribute is such a stopped run, read as it stands
with one warning naming the dataset (the readers' element entry carries
`first_turn` and `turns` from the attributes beside `element` and `beam`,
`nothing` when the run did not record; review F2, 2026-10-15), and the
`/execution` ledger's `current_turn` is a separate progress mark that a
`TrackingTask` without strong beams writes to the file only at finalize,
while the strong-strong loop stamps it before each turn (persisted at the
luminosity flushes) and closes the turn's series row after it, so on a
killed run the two can disagree and the rows decide. The series and the
nominals are stored as `Float64` whatever the element's numeric type `T`, so
"exactly as the element forms them" holds bit for bit for `T = Float64` and
to `Float64` rounding otherwise. On CUDA the values are host-side already
(the rebuild runs before any device conversion); under MPI every rank
realises the same draws and rank 0 writes. Like the provenance, a `series`
is never rewritten or deleted, so chunked and repositioned runs stack one
dataset per execution slot, and a knob change between windows shows as a
different nominal in the next slot. The group `/turn_modulation/<slot>/state`
is RESERVED for the checkpoint of a future stateful rule (D10): one group
per execution slot, written once after the window's last turn by stateful
rules only, holding one dataset per stateful slot; no shipped rule is
stateful (a tripwire pins it), nothing writes the group today, the readers'
element count skips it, and they return `nothing` for it. The readers keep
their shape: `turn_modulation_provenance(path)` and `read(out,
:turn_modulation)` return the same vector as before; each slot entry gains
`nominal` (a NamedTuple of the slot's nominal attributes, `(phase,
strengthX, strengthY)` or `(phase, strength)`; `nothing` only for a file
written before they existed) and `series` (the slot's column as a
`Vector{Float64}`, or `nothing` when the run did not record), and each
execution entry gains `state = nothing`. The table of contents (`read(out)`)
stays metadata-only: its `series` field is the recorded ROW COUNT, not the
column. Torn, refused by name: a `series` missing `columns`, `first_turn` or
`turns`; `columns` not naming the slot groups in index order; a data width
other than the column count; a recorded element whose slot groups carry no
nominals.

### Artifact options

`RunArtifact(path; append=false, capacity=64, record_turn_modulation=false)`
-- the sink's options, each documented in full in `?RunArtifact`; everything
else about a run's output is decided on the producers ("What each party
owns" above).

- `append`: `false` recreates the file per `execute!`; `true` continues it
  across `execute!` calls and process restarts under the replay idempotence
  rule (rows at or beyond the incoming window's first turn are dropped per
  group first, `/losses` included); a file whose luminosity groups do not
  match the task's collision labels is refused rather than silently mixed,
  as is one whose `/losses` names other apertures than the task's line. The
  rule is applied by `commit_run_artifact!` after every refusal of the
  window, so a refused continuation leaves the file as found (the window
  protocol under Crash recovery, 2026-10-19).
- `capacity`: the rows per group buffered between flushes, the ONE batching
  knob for every row-shaped producer (luminosity, moments, BPM readings and
  the turn-modulation series; snapshots write their block per fire); at
  least 1, refused by name otherwise.
- `record_turn_modulation` (stage 1 of `turn_modulation_record.md`, landed
  2026-10-15): `true` records the turn-modulation rules' offsets turn by
  turn as the `series` dataset above, for every active slot of every
  modulated element, over every `execute!` window the artifact is attached
  to. Default `false`: no `series` dataset and no recorder; the slot groups
  still carry their nominal attributes (the provenance writer writes them
  regardless), everything else is identical to a run that never had the
  option, and the readers' `series` field is `nothing`. Inactive: `true` on
  a line with no modulated element has nothing to record and writes nothing,
  as the provenance writes nothing for such an `execute!`; the readers'
  empty vector says so, and it is not an error. Invalid: a value that is not
  a `Bool` is refused by name, an `ArgumentError` naming the keyword and the
  value (`record_turn_modulation = 1` is not coerced), as a `capacity` below
  1 is. The strong-strong `configuration_report` prints it in the `:artifact`
  output entry (", recording the turn-modulation series"). The switch
  changes nothing in the tracking: the tracked coordinates, the luminosity,
  the moments and the `:turn_modulation` receipt are bitwise identical with
  it on and off (pinned by the suite's "The run artifact records the
  realised turn modulation", CPU and CUDA arms; by decision D2 the switch is
  not a keyword of `with_execution_audit`, so a run's output never depends
  on whether a contract wrapped it). Cost: 8 bytes per active slot per turn,
  one `Float64`, batched with `capacity`: 8 MB per million turns per slot,
  64 MB per million turns for the crab-noise example's eight active slots,
  which is why the default is off. Measured at landing (CPU, 4 threads, 1024
  particles, two crab cavities with 8 active slots, a dispersion element and
  an every-turn `MomentObserver`, 2000 turns, best of 2): at `capacity = 64`
  off 0.276 s, on 0.298 s, +11.2 us per turn, the HDF5 extend and flush
  every 64 turns amortised; at `capacity = 1024` off 0.161 s, on 0.159 s,
  within noise; the file grew from 158607 to 295778 bytes, 68.6 bytes per
  turn for 8 columns (64 of data). Structured metadata:
  `run_artifact_option_schema()` (exported; `append`, `capacity` and
  `record_turn_modulation` as `ConfigurationOptionMeta`, category `:output`,
  all three naming the `:run_artifact_output` receipt, below), checked by a
  `RunArtifact` block of `validate_configuration_metadata()` (every key a
  field of the type, every declared default equal to a constructed
  artifact's, every option naming its consumer). As every public option
  (AGENTS.md Invariants), it lands with its runtime consumer, its structured
  metadata, its inactive and invalid behaviour and its effectiveness test at
  the consumer boundary.

**The output receipts (decided 2026-10-16, fix batch of the crab-noise
neighbour audit; leads S4-1, S4-2, S4-3, S4-10).** Measured on ac3fbb2:
under a `TrackingTask` not one receipt carried `append`,
`record_turn_modulation` or (without a `MomentObserver`) `capacity`; the
`:strong_strong_output` receipt, the declared consumer of the first two,
carried the REQUEST -- `append = true` on a path that did not exist while
the file was created fresh, `record_turn_modulation = true` on a line with
no modulated element while nothing was recorded -- and the strong-strong
`configuration_report` called it `:resolved`; `CoordinateSnapshotObserver`
declared `:observer_output` as the consumer of `name` and `npart` and never
recorded one; `BPMObserver`'s receipt carried neither its `artifact` switch
nor the capacity it batches by; `TrackingTask` accepted `artifact` and
`loss_report` with no schema entry and no report entry. A receipt names ONE
consumer and an option's metadata names ONE consumer, and the artifact is one
object two task kinds carry, so the only receipt that is true under both is
the one the artifact records at its own boundary: `prepare_run_artifact!`
records `:run_artifact_output` once per `execute!` AFTER its last refusal
(and, on a non-root MPI rank, at its early return), with `task` (the
carrying task's kind), `artifact` (the path), the request under each
option's own name and what was applied beside it -- `append` beside
`continued` (an existing file continued, or the path created fresh),
`capacity` (the batching every row producer and recorder uses),
`record_turn_modulation` beside `recording` (recorders built: the switch on
AND the line has a modulated element) -- and `execution`, the ledger row
appended; a non-root rank, which opens no file, carries `nothing` for
`continued` and `execution`. Each task kind records its own output receipt
beside it, also after the prepare, so a prepare refusal leaves neither:
`:tracking_output` (new; `artifact`, `channels` -- the luminosity channel
labels the artifact opened with -- and `loss_report`) and
`:strong_strong_output` (moved after the prepare; `artifact`, `channels`).
`tracking_task_option_schema()` gained `artifact` and `loss_report`, both
naming `:tracking_output`, and `configuration_report(::TrackingTask)` an
`output` entry pair; the `:artifact` entry of BOTH task reports is built by
one helper and is `:unresolved` while `append` or `record_turn_modulation`
is requested, since a report runs before the `execute!` and both are decided
at prepare (the reason names the receipt field that carries the answer);
`:resolved` ("rewriting ...") when neither is. The three probes' receipts
carry the fields their metadata names: the moment probe's `name` (new),
`moments` and the artifact's `capacity` (`moments` had named
`:moment_reduction`, a consumer no receipt ever recorded); the snapshot's
`name` and `npart` beside `captured` (new receipt); the BPM's `artifact`
and `capacity` (new fields; `nothing` in memory-only mode). The pairing is
DERIVED, never a hand list: `_output_receipt_gaps(receipts, schemas)`
(src/contracts/Contracts.jl) takes the consumers every `:output` option
names across the schemas and requires, for every option naming one of them,
a receipt of that consumer belonging to the option's owner that carries a
field named after the option; `validate(PublicConfigurationEffectivenessContract())`
runs it over a `TrackingTask` fixture (every artifact option away from its
default, `loss_report=false`, a modulated element, all three probes, a
fresh then a continued window) and a `StrongStrongTask` fixture (the two
requests resolved inactive), and the suite's "Run artifact receipts and
slots: ..." testset adds the negative controls, the static tripwire that
every `:output` consumer has a `_record_execution!` site, and the pins above.
Rejected: naming one task's receipt for a shared option (the `blocks`
precedent is one object with two consumers of its own, not two owners) and
renaming `:strong_strong_output` to a shared symbol (a rename across files
other units of the batch were editing). Record:
`../history/audit_crab_cavity_noise_neighbours_2026_10_16.md`.

### Buffer protocol — three shapes, one protocol, not one buffer type

The pattern (allocate at task construction → elements write during tracking
→ task reduces at turn end and decides whether to fire) already exists three
times; the artifact codifies the PROTOCOL and deliberately keeps the three
buffer shapes, because the products genuinely differ:

1. **per-turn rows** (luminosity): fixed width, one row per evaluated turn;
2. **event records** (losses): a particle is lost at most once, so the
   device buffer is O(N) slots (`LossRecord`), not rows — contention-free,
   written from kernels, reduced by the task;
3. **scheduled blocks** (moments, snapshots, BPM): matrices at scheduled
   turns.

**Device constraint, stated plainly:** anything written from inside a kernel
must be preallocated, fixed-layout, contention-free. Per-particle slots and
post-kernel reductions are the two workable patterns; a generic
"send to buffer" callable from device code is not on offer.

### Performance posture

The redesign redirects SINKS, not producers: kernels, moment reductions,
luminosity folds and loss slots are untouched, so the hot paths do not move.
On the host side:

- one file handle replaces three to five (the measured NFS cost — 2.3
  ms/turn — was per open/close, not per byte);
- HDF5 per-call overhead exceeds a text append, so the artifact's default
  posture is CAPACITY BATCHING (buffer rows, one dataset write per flush) —
  a per-turn unbuffered h5 write of a tiny luminosity row would be a
  regression, and the strong-strong held-open-stream shape maps onto a
  held-open file handle with batched dataset appends;
- all sink writes happen sequentially at turn boundaries; one artifact per
  task; tasks never share one (registry identity, as today);
- an optional LIVE TEXT MIRROR for luminosity keeps `tail -f` on long runs.

### Crash recovery — the one place the design must work to match today

The text `.lum` has measured torn-line semantics; a hard-killed HDF5 file is
a nastier object. The mitigation generalizes the snapshot's replay map: each
group carries a **rows-valid-through-turn cursor attribute**, flushed with
its batch, so a retry trusts exactly the cursored prefix and the replay
discard truncates datasets against absolute turns, as the text path does
today. This must be designed in from the first dataset, not retrofitted.

**The window protocol: validation before mutation (2026-10-19 fix batch,
the comprehensive audit's F-56, F-58).** Measured on cb3c344: under
`append=true` four by-name refusals of `prepare_run_artifact!` -- the
missing ledger, a ledger lacking the seed columns, a partial provenance slot,
an occupied provenance slot -- fired AFTER the replay truncation had dropped
every luminosity row at or beyond `first_turn` (100 rows and cursor 99 became
50 and 49, the file closed and unlocked, the refusal claiming to leave it as
found); and probe groups were truncated one bind at a time, so a later
probe's refused bind (a duplicate name, a changed column layout) left every
earlier probe cut back to `first_turn - 1`. The decision is one protocol in
three steps, each the task's to call once per `execute!`:

1. `prepare_run_artifact!` validates and writes nothing to a continued file
   before it has: every by-name refusal is an entry of one table,
   `_RA_PREPARE_CHECKS` (the file is an artifact; its luminosity groups are
   the task's labels; the ledger is present with every column; no provenance
   slot is partial; its `/losses` names exactly the task's apertures when the
   task records losses, the `aperture_names` keyword; the provenance slot is
   free and the two walks agree), run in order after the open and before the
   ledger row is appended. A continuation the prepare refuses leaves the
   file BYTE-IDENTICAL: an HDF5 `r+` open and close without a write changes
   no byte (measured), and the suite derives one fixture per table entry and
   pins the bytes, so a refusal cannot join the table without its
   measurement and the loop's place before the first write is read from the
   source.
2. Every probe bind (`_ra_bind_probe!`) validates -- a name, a known kind,
   unique within the `execute!`, the stored column layout -- and registers
   the probe; it creates and truncates nothing.
3. `commit_run_artifact!`, called by both task kinds after their observers
   have prepared and after their last refusal that can stop a run before its
   first turn, applies the replay rule to every group at once: each
   luminosity channel of a continued file is truncated to `min(cursor,
   first_turn - 1)` (the torn tail and the replayed rows, one bound), each
   bound probe is created or truncated the same way and stamped with its
   `s`. Only then may rows arrive: `push_luminosity!` and the probe push
   refuse by name before the commit (a row appended beyond stale rows would
   be the silent form of the defect), a probe cannot bind after it, a second
   commit is an error, and a window that tracked turns without committing is
   refused at finalize. A window refused between its prepare and its commit
   -- an observer's refusal, the fused-route refusal -- leaves every row and
   cursor as the prepare found them; it keeps its ledger row, whose
   `current_turn = start_turn - 1` says nothing ran, and writes no `/losses`.

Rejected: truncating lazily at the first write (a window whose probes never
fire would leave its replayed rows in place, and the crash path's `/losses`
write could not tell a refused window from a run), and moving the ledger row
into the commit as well (it would move the provenance groups and the series
recorders with it; the retained row is the ledger's documented posture for a
replayed window, and it says it reached nothing). Record: the 2026-10-19 fix
batch's history record, the comprehensive audit's section 4 for the findings.

**`/losses` under the replay rule (2026-10-19 fix batch, F-57).** Measured
on cb3c344: the group was deleted and rewritten whole from the task's
in-memory record at every `execute!`, and the record is the BEAM's (it is
reallocated when a different beam object arrives, `_ensure_loss_record!`), so
a new task continuing a file -- the process restart `append=true` promises --
rewrote it from an empty record: three windows in the ledger, zero loss
rows, `aperture_counts = [0]`, `summary_dead = 0`; and within one task a
fresh beam per window lost the earlier window's rows the same way. The
decision: `/losses` follows the rule every other group follows, by the
`turn` column of its rows. `_ra_write_losses!`, on a continued file, keeps
the group's rows whose `turn` is below this window's first turn and that this
record does not itself carry (the same beam continuing in one process holds
its earlier rows in its cumulative record, so they are kept once, keyed on
`(particle_id, turn)`), drops the rows at or beyond it as replayed, and
appends every row of this record; `aperture_counts` is this record's
attribution plus that of the kept rows, so `sum(aperture_counts) ==
record_count` whenever rows are logged. The `summary_*` attributes stay the
writing `execute!`'s beam -- `particles`, `live`, `dead`, `logged`,
`unattributed` as `loss_summary` defines them, the beam's state at the end of
that window, not a sum over windows: a restart from a checkpoint carries a
different beam, and the reconciliation `unattributed = dead - logged` is only
meaningful within one beam. So on a fresh file `sum(aperture_counts) ==
summary_logged` as before, and on a continued file the counts exceed
`summary_logged` by the earlier windows' retained losses; a reader of a
continued file reads the rows and counts as the file's history and the
summary as its last window's beam. A continued file's `/losses` must name
exactly the task's apertures -- the rows' `element_id` is interpreted under
the file's names -- so a line with other apertures, or none, is refused at
prepare (the labels' rule). A continued group that logged no rows (a
counters-only record, unreachable from a task with an artifact, which always
allocates slots) carries its counts whole, there being no turn to replay by,
and the writer warns that a replayed window counts twice. A window that
never committed writes nothing and leaves the group as found. Rejected:
reading the earlier rows back into the new task's record (the record is a
per-particle device buffer keyed by slot; a restart's beam need not have the
same particles), and a per-execution slotted `/losses` (a schema change for
every reader where the existing columns already carry the turn).

**The row-indexed cursor (decided 2026-10-19, the comprehensive audit's fix
batch; F-73, F-74, F-59, F-63, F-84).** Measured on cb3c344: the cursor was
the turn attribute `rows_valid_through_turn` alone and the truncation
searched the turn column for it (`searchsortedlast`), so a torn tail of HDF5
fill rows -- the extent advanced by a kill between the data write and the
cursor flush, every unwritten row reading as turn 0 -- passed through
untouched and a continuation appended after it (`[0,1,2,3,4,5,0,0,6,7]`,
F-74); no reader applied the cursor at all (20 rows on disk at cursor 9 read
as 20, and `MomentOutput`'s `:record_count` counted the tail, F-59); a group
whose cursor attribute was absent took the no-rows default and was truncated
to zero rows on the next append-open, rows below `first_turn` included
(F-63), the cursor's rewrite being a delete-then-create with exactly that
window; and `observe!(::MomentObserver)` advanced its row count before the
row existed, so an exception inside the row computation left a garbage row
that the failed run's best-effort finalize pushed, the cursor was stamped
from that row's turn, and the retry of a chunked run cut chunk 1 away
(`[0,4,5,6,7]` for a run owed `0:7`, F-73). Decided: the cursor KEYS ON THE
ROW INDEX the writer owns. Every row group (`/luminosity/<label>`,
`/moments|snapshot|bpm/<name>`) carries the pair `rows_valid` -- the number
of leading rows the writer has blessed; the rows beyond it are a torn tail
whatever their values -- and `rows_valid_through_turn`, the turn of that
row, the public meaning (the no-rows sentinel `typemin(Int32)` when none),
stamped together after each batch of rows (`_ra_stamp_cursor!`) and
re-stamped by the truncation of an append-open; a group created and not yet
flushed carries the turn sentinel alone and reads as zero rows blessed. The
append-open truncates to `rows_valid` first, then applies the replay rule to
the blessed prefix, whose turns are non-decreasing by construction (a prefix
out of turn order is refused by name). Every reader -- `read(TaskOutput(p),
kind; ...)` for every named kind and `:all`, the table of contents,
`MomentOutput` and its `:record_count` -- returns the blessed rows only, and
the table of contents reports `rows` (what a read returns) beside
`rows_on_disk` (the extent), the one surface for the raw count. A same-type
scalar attribute is rewritten in place, so a cursor never passes through an
absent state. Compatibility rule: a group whose cursor is absent, and a
group holding rows under the turn cursor of a file written before
2026-10-19, are REFUSED by name under `append=true`, as found and never
truncated, with the remedy (a new path, or `append=false`) -- the
ledger-column precedent of 2026-10-16, chosen over deriving `rows_valid`
from the turn cursor because that derivation is the by-value guess F-74 is
about and is ambiguous on a snapshot whose fill value equals a recorded
turn; reading such a file stays possible, every row on disk with a warning
naming the group. `observe!` computes the row, then commits it, and records
its `:observer_output` receipt after its `initialized` refusal, as the
snapshot twin does (F-84). The suite's "The run artifact's row cursor: ..."
testset pins each shape against the measured values; the probes are under
`result/fix_batch_2026_10_19/probes/T/`.

**The partial provenance slot (decided 2026-10-16, owner; the stage 3-4
audit's U5-2, restored by the crab-noise neighbour audit).** Since the
2026-10-16 neighbour audit the provenance writer runs every refusal before
it creates the first group, so only an HDF5 error mid-write can leave a
`/turn_modulation/<slot>` group half-created. Decided: the reader reports,
nothing rolls back. The slot group carries the cursor
`elements_valid_through`, the row groups' protocol one level up: created at
0 BEFORE the first element group and advanced to `k` only after element `k`
is complete -- its attributes, its slot groups with their nominals and, with
`record_turn_modulation` on, its `series` dataset, which the writer now
creates inside the same per-element loop (`_ra_write_turn_modulation!`,
`series = (first_turn, planned_turns)`; `_ra_build_turn_modulation_recorders!`
builds the recorders over the datasets afterwards). A writer stopped mid-way
leaves the cursor behind `element_count`: a PARTIAL slot, the crash artefact
it is. The readers (`turn_modulation_provenance`, `read(out,
:turn_modulation)`, the table of contents, `read(out, :all)`) read such a
slot as far as the cursor -- the complete element groups, in order -- with
one warning naming the slot and the counts, skip the at most one half-written
group beyond it, and never error on it (a cursor beyond the count, a complete
slot missing a group, or a count disagreeing with the groups present stay
TORN and refused by name as before); `RunArtifact(...; append=true)` onto a
file holding a partial slot in any execution is refused by name, as found,
with the remedy (a new path, or removing the slot and its ledger row by
hand). A slot written before the cursor existed carries none and reads as
complete by construction (its writer validated before writing; its count
must match the groups), and the append check leaves it to the readers. The
suite builds both shapes a stopped writer leaves through HDF5 directly
(element 2 half-written; element 2 never created). The series' own
"cursor" is its row count, compared with its `turns` attribute (review F2).
Record: `../history/audit_crab_cavity_noise_neighbours_2026_10_16.md`.

**Cross-process exclusion (decided 2026-10-16, owner; neighbour audit
S5-2).** The artifact had none: the in-process registry (`U7-10`, the
"second live observer" warning) sees one process, and HDF5's own file lock
is not effective on the NFSv3 mount the runs use. Measured on 8ace18b: a
second process opening a path another process held SUCCEEDED with either
`append` -- `append=false` truncated the holder's open file, which then read
back torn ("len not positive after adjustment for EOA"); `append=true`
appended into the holder's ledger -- and two concurrent writers of one path
both finished, one run's 400 rows silently gone. The decision is a SIDECAR
LOCK FILE `<path>.lock`, created exclusively (`O_CREAT | O_EXCL`, so two
processes racing for one path cannot both succeed), holding one line
`host=<hostname> pid=<pid> since=<ISO 8601 local time> task=<task kind>`,
taken by rank 0 in `prepare_run_artifact!` BEFORE the file opens, for a
fresh open as for an appending one (whether to truncate or continue is
decided under exclusion), and removed AFTER the file closes, in
`finalize_run_artifact!` and so on every path that closes the artifact (the
success and crash paths of both tasks, the strong-strong observer-prepare
refusal); the prepare's own refusals, the one close that does not run
through finalize, release it themselves, as does an open that fails. A
second writer finding the lock is refused with an `ArgumentError` naming the
lock path, the line it holds (who, where, since when) and the remedy: if
that process is gone, remove the lock. There is NO automatic stale-lock
takeover -- the holder may be alive on another host, and a pid test or an
age test would be a guess -- so a lock left by a killed run is removed by
hand, and the refusal says which file. READERS do not take the lock: a
second process may read while the first writes and sees the last flushed
state (measured: eight readers during a 3000-turn write, each a consistent
prefix; `result/.../auditor/probe_rw_reader2.log`). The public readers are
lock-aware instead: `TaskOutput`, `turn_modulation_provenance` and the
`MomentOutput` HDF5 reads open through one `_ra_open`, which, when a live
lock exists for the path, emits one `@info` per writer and process naming
the lock's line and that the rows are valid through each group's
`rows_valid_through_turn` cursor and the ledger's `current_turn`, and
retries a failed open once (a flush landing) before the failure propagates
with the lock information in it; only the open is retried, never the read
body, so a torn group keeps its own refusal. The lock is ADVISORY and for
Octopus writers: HDF5 itself does not honour it, a foreign `h5open` is not
stopped by it. The in-process registry stays beside it, now reporting only
the sequential sharing it was built for (a refused writer is not registered
as live). Record: `../history/audit_crab_cavity_noise_neighbours_2026_10_16.md`.

### Execution diagnostics

The moment files' `turn` + `elapsed_time` per fire is a style worth keeping
and generalising (owner direction, 2026-08-18): execution numbers are a
product of the run like any other, so the artifact gives them their own
channel — an `/execution/` group with ONE ROW PER `execute!` (execution
index, start turn, window length, CURRENT TURN and elapsed updated at every
flush -- live progress and rate from one `h5ls`, and the run-level
how-far-did-it-get answer after a crash; as landed the row holds
`start_turn`, `turns`, `current_turn` and `elapsed`, no backend column --
2026-10-16 neighbour audit -- and, since the same day's fix batch, `rng_seed`
and `rng_method`, the paragraph below),
appended and never overwritten, so a swap-out run's every execution keeps
its record; rows from a replayed window are RETAINED too, distinguishable by
execution index, because both attempts' timings are exactly what a retry
diagnosis wants. Richer per-turn timing joins the same group behind the
existing diagnostics precedent (`StrongStrongDiagnostics.record_turn_times`),
**(Corrected 2026-09-07: the ledger route cannot serve this.** The per-execution
ledger OVERWRITES -- `current_turn` and `elapsed` are one slot per `execute!` --
so a reader gets one (turn, elapsed) pair per execution, not a series; it is
live progress for `h5ls` during a run, not history. And decisively,
`task.artifact === nothing` is a term of the fast-path gate in
`_execute_tracking_task!`, so attaching an artifact to obtain timings moves the
run OFF the loop a benchmark measures -- the route cannot instrument its own
motivating case. Per-turn timing landed instead as `record_turn_times` on the
task itself, in memory, read back with `turn_timings`. Record:
[`../history/tracking_task_turn_timing_2026_09_07.md`](../history/tracking_task_turn_timing_2026_09_07.md).)
and the opt-in/out keyword for execution logging harmonises with that
diagnostics object on both tasks rather than inventing a second switch. The
interim fix already landed on the moment files: a per-execution ledger
(`/execution_elapsed`, `/execution_start_turn`, appended at prepare, updated
per flush, created on demand for older files) with the scalar
`/elapsed_time` keeping its documented current-execution semantics for
existing readers — its overhead is one tiny dataset write per flush, so it
needs no switch.

**Seed provenance (decided 2026-10-16, owner; neighbour audit S5-4).** The
ledger row carries two more columns, appended with the row at prepare:
`rng_seed` (`UInt64`) and `rng_method` (a string, the counter-RNG method's
name as `rng_method_symbol` spells it -- `"philox"`, `"splitmix"` -- so a
new method names itself here), the global stochastic seed and method in
force when that `execute!` began, which is what every stochastic consumer
of the window keys its draws on. Measured before: after a
`set_global_rng!` between two windows the file's only mention of a seed was
a spectral table's canonical name; a white or pink stream, a beam
initialization, a radiation element left no trace of theirs. The six
columns are ONE table in the writer (`_RA_LEDGER_COLUMNS`: creation, the
appended row, the continue-check and the reader derive from it; the suite
derives its column pins from it and checks that this note names each). A
continued (`append=true`) file whose ledger lacks any column of the table
predates the two and is refused by name -- the message says the file
predates the columns, 2026-10-16, and offers a new path or `append=false`
-- and left as found, never padded: a padded seed column would claim a
provenance the earlier rows never recorded. (This supersedes the step-1
padding of `current_turn`, whose files lack these columns too.) Reading an
old file stays possible: `read(out, :execution)` returns `nothing` for a
column the file lacks, the `/losses` reader's posture for its later-added
attributes. Record: `../history/audit_crab_cavity_noise_neighbours_2026_10_16.md`.

## Migration

Behind the current APIs, in order; each step gated and byte/dataset-compared
against the outputs it replaces where determinism permits:

1. the artifact container + cursor + the luminosity channel (strong-strong
   first: its planner logic transfers, its row-drop logic retires);
2. moments and snapshots as views (constructors gain `name`); BPM joins;
3. losses (already h5-shaped; `write_loss_record`'s layout becomes the
   `/losses` group);
4. compatibility surface: `luminosity=`/`LuminosityObserver` and the
   per-observer file paths remain as adapters writing through the artifact,
   deprecated on the owner's schedule, not before.

## Rejected alternatives

- **Status quo** (per-product files): N file stacks converging in capability
  while diverging in code; the run's story scattered.
- **One flat table**: forces shared turn axes and fixed rows — the mixed-IP
  drop hack generalized to every product pair.
- **Task-level channel attachment** (the interim state): superseded by
  producer declaration, which dissolves the row assembly the task never
  physically owned.
- **Text for the unified file**: no groups, no matrices, no per-dataset
  axes; text's virtues (tail -f) survive as the live mirror instead.
- **One buffer type for everything**: the three shapes are physically
  different; flattening them buys uniformity of words, not of code.
