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
writers. Deferred niceties (s-position attributes,
weak-strong label names, a first-class live text mirror) are an open ledger
row. Prerequisites had landed before implementation: the luminosity-sink
unification (2026-08-17), the keyword retirement, and the weak-strong
fresh-observer append fix (2026-08-18).

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
                             aperture_s, per-loss rows, summary)

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

### Execution diagnostics

The moment files' `turn` + `elapsed_time` per fire is a style worth keeping
and generalising (owner direction, 2026-08-18): execution numbers are a
product of the run like any other, so the artifact gives them their own
channel — an `/execution/` group with ONE ROW PER `execute!` (execution
index, start turn, window length, CURRENT TURN and elapsed updated at every
flush -- live progress and rate from one `h5ls`, and the run-level
how-far-did-it-get answer after a crash -- plus backend),
appended and never overwritten, so a swap-out run's every execution keeps
its record; rows from a replayed window are RETAINED too, distinguishable by
execution index, because both attempts' timings are exactly what a retry
diagnosis wants. Richer per-turn timing joins the same group behind the
existing diagnostics precedent (`StrongStrongDiagnostics.record_turn_times`),
and the opt-in/out keyword for execution logging harmonises with that
diagnostics object on both tasks rather than inventing a second switch. The
interim fix already landed on the moment files: a per-execution ledger
(`/execution_elapsed`, `/execution_start_turn`, appended at prepare, updated
per flush, created on demand for older files) with the scalar
`/elapsed_time` keeping its documented current-execution semantics for
existing readers — its overhead is one tiny dataset write per flush, so it
needs no switch.

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
