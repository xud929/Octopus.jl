export RunArtifact, TaskOutput, turn_modulation_provenance, run_artifact_option_schema

# ---------------------------------------------------------------------------
# The run artifact: one HDF5 output file per task, one group per producer.
# Design: docs/design/run_artifact.md (decided and implemented 2026-08-18).
# This file carries the container, the per-group crash-recovery cursor, the
# execution ledger, the luminosity channels (strong-strong per collision,
# weak-strong per strong beam, INDEPENDENT turn axes), the /losses writer,
# the probe row-matrix machinery the named observer views bind through
# (/moments|snapshot|bpm/<name>), and the TaskOutput reader. The standalone
# per-observer writers retired behind it (step 4). Since 2026-10-15 it also
# carries the turn-modulation series recorder (`TurnModulationRecorder`, the
# `record_turn_modulation` option; docs/design/turn_modulation_record.md).
# ---------------------------------------------------------------------------

# The recorder needs its artifact for the ledger stamp at every series flush
# (2026-10-16 neighbour audit, U5-1), and the artifact holds its recorders:
# the abstract root breaks the definition cycle.
abstract type AbstractRunArtifact end

"""
    TurnModulationRecorder

The run artifact's sink for ONE beam's turn-modulation series during one
`execute!` (docs/design/turn_modulation_record.md, D5-D8). Built by
`prepare_run_artifact!` on rank 0 when `record_turn_modulation` is on and the
beam's line has a modulated element; handed to the turn loop by
`_turn_modulation_sink(art, beam)`; filled by the recording hook
(`update(elem, ctx, sink)`, `src/elements/turn_modulated.jl`) through
`_record_turn_draws!`, once per modulated element per turn IN LINE ORDER, with
the draws of the very evaluation that built the realised element; flushed by
`_ra_flush_turn_modulation!` every `capacity` turns and at finalize, the
batching the luminosity rows take. The loop's per-turn protocol:
`_tm_begin_turn!` before the segments run, `_tm_end_turn!` after them, which
checks that every element the provenance lists was met exactly once -- a
miscount drops the turn's partial values and raises, naming the beam and the
turn; it never writes a misaligned column -- and counts the row.

`keys[k]` is element `k`'s group path under `/turn_modulation/<slot>`,
`active[k]` the indices of its ACTIVE slots into the draws tuple, `buffers[k]`
its pending values turn-major; `cursor` counts the elements met this turn,
`rows` the pending turns. `file` and `capacity` are the artifact's, fixed for
the `execute!`.
"""
mutable struct TurnModulationRecorder
    const file::HDF5.File
    const capacity::Int
    const beam::Int
    const keys::Vector{String}
    const active::Vector{Vector{Int}}
    const buffers::Vector{Vector{Float64}}
    cursor::Int
    rows::Int
    # The artifact this recorder writes for, or `nothing` for a recorder built
    # by hand (the suite's direct-API tests); the series flush stamps the
    # ledger through it.
    const owner::Union{Nothing,AbstractRunArtifact}
end
TurnModulationRecorder(file, capacity, beam, keys, active, buffers, cursor, rows) =
    TurnModulationRecorder(file, capacity, beam, keys, active, buffers, cursor, rows, nothing)

"""
A probe bound to the artifact this `execute!` and not yet committed: what
`_ra_bind_probe!` validated and `commit_run_artifact!` creates or continues
(`_ra_commit_probe!`) -- the group key, its kind and name, the column layout,
the window's first turn the replay rule truncates against, and the probe's arc
position `s` (`nothing` for a task-hook probe). 2026-10-19 fix batch, F-58.
"""
struct PendingProbeBind
    key::String
    kind::String
    name::String
    colnames::Vector{String}
    first_turn::Int64
    s::Union{Nothing,Float64}
end

"""
    RunArtifact(path; append=false, capacity=64, record_turn_modulation=false)

The one-output-file-per-task sink (docs/design/run_artifact.md): an HDF5 file
with one group per producer, owned by the task that carries it.

The artifact carries every product of the run:

- `/luminosity/<label>`: per-producer `turns`/`values` datasets with
  INDEPENDENT turn axes — a collision (strong-strong labels) or strong beam
  (weak-strong `strong_beam_<i>`) writes a row exactly when its own
  luminosity schedule evaluated, so per-IP schedules may disagree freely.
  `NaN` keeps its meaning: evaluated and failed.
- `/moments/<name>`, `/snapshot/<name>`, `/bpm/<name>`: the named probe
  views (`MomentObserver(; name=...)`, `CoordinateSnapshotObserver(;
  name=...)`, `BPMObserver(...; artifact=true)`) — row-matrix groups whose
  column 1 is the absolute turn, names unique within a task; a line-placed
  probe additionally carries its arc position as the `s` attribute (the
  design's `attrs: name, s`; task-hook probes have no line position and
  carry none).
- `/losses`: the loss accounting in the `write_loss_record` layout, written
  per `execute!` under the replay rule like every other group (2026-10-19 fix
  batch, F-57): a continued file keeps the earlier windows' loss rows below the
  incoming window's first turn and drops the rows at or beyond it, this
  window's record is appended, and `aperture_counts` follows the rows; the
  `summary_*` attributes are the writing `execute!`'s beam (`_ra_write_losses!`).
- `/execution`: one row per `execute!` — `start_turn`, planned `turns`,
  `current_turn` and wall-clock `elapsed`, the last two updated at every
  flush, and since 2026-10-16 `rng_seed` and `rng_method`, the global
  stochastic seed and the counter-RNG method's name (`"philox"`,
  `"splitmix"`) in force when that `execute!` began, so a `set_global_rng!`
  between two windows is on record row by row — appended and never
  overwritten, so every execution of a swap-out or chunked run keeps its
  record. `current_turn` is the turn the execution had reached at its most
  recent flush: live progress and rate from one `h5ls` while running, and
  the run-level how-far-did-it-get answer after a crash (the per-group
  cursors answer the same question per dataset). A continued
  (`append=true`) file whose ledger lacks any of these columns predates them
  and is refused by name rather than padded; reading such a file stays
  possible, its missing columns read as `nothing`.
- `/turn_modulation/<slot>`: the turn-by-turn modulation provenance of the
  `execute!` whose `/execution` ledger row is `<slot>`, written only when
  its line had a modulated element (docs/design/turn_modulation.md, D7):
  `element_count` and the cursor `elements_valid_through` on the slot group
  (0 when the group is created, advanced after each element group is
  complete, series dataset included; a slot whose cursor is behind its
  count is PARTIAL, the artefact of a writer that stopped mid-prepare, read
  as far as the cursor with a warning naming the slot, never rolled back,
  and refused by name under `append=true`; 2026-10-16 owner decision); one
  subgroup per modulated element in
  line order with `element`, `beam` (1 for a `TrackingTask` line, 1 or 2 for
  the strong-strong task's two lines) and `slot_count`; one subgroup per
  ACTIVE slot below it, named by the slot label, with `index`, `kind` (a
  rule's `_rule_kind` label, one of `_turn_rule_kinds()`: `white`, `pink`,
  `table`; `spectral` labels the spec-level `SpectralNoise`, which resolves
  to a table at compile and so never reaches a file), `rng_id`, `digest`,
  `name`, `length` and the
  slot's nominal parameters as `nominal_<name>` attributes (`nominal_phase`,
  `nominal_strengthX`, `nominal_strengthY` on a crab cavity slot, the
  harmonic's three; `nominal_phase`, `nominal_strength` on an RF cavity
  slot; docs/design/turn_modulation_record.md, D3). With
  `record_turn_modulation=true` each element subgroup also holds the
  dataset `series`: `turns` rows by one `Float64` column per active slot in
  provenance order, the OFFSETS the rules produced -- radians on a phase
  slot, the dimensionless relative factor `d` on a strength slot, row `i`
  being absolute turn `first_turn + i - 1` -- with the attributes `columns`,
  `first_turn` and `turns` (D7). The subgroup name `state` under a slot
  group is RESERVED for a future stateful rule's checkpoint (D10); nothing
  writes it. Nothing here is ever rewritten or deleted, so a continued file
  keeps every generation of rules it ran. Read it with
  [`turn_modulation_provenance`](@ref) or `read(out, :turn_modulation)`: an
  empty vector means no `execute!` recorded in the file had a modulated
  element.

Read it back through one handle: [`TaskOutput`](@ref).

`append=false` (default) recreates the file per `execute!`; `append=true`
continues it across `execute!` calls and process restarts under the replay
idempotence rule: rows at or beyond the incoming window's first turn are
dropped per group first. A file whose luminosity groups do not match the
task's collision labels is refused rather than silently mixed, as is one
whose `/losses` group names other apertures than the task's line. The window
protocol is validation before mutation (2026-10-19 fix batch, F-56/F-58):
`prepare_run_artifact!` runs every by-name refusal of a continuation before
it writes anything, each probe bind validates its group without touching it,
and `commit_run_artifact!` -- called by the task after the last refusal that
can stop a run before its first turn -- applies the replay rule to every
channel and probe at once; a refused continuation leaves the file as found
(byte-identical when the prepare refuses).

**Cross-process exclusion** (2026-10-16): while an `execute!` holds the
file, rank 0 also holds the sidecar lock `<path>.lock`, created exclusively
(`O_CREAT | O_EXCL`) with one line, `host=<hostname> pid=<pid>
since=<ISO 8601 time> task=<task kind>`, taken before the file opens, fresh
or appending, and removed after it closes, at finalize and on every crash
path. A second Octopus writer on the path — any process, any host, either
`append` — is refused by name with the lock's line and the remedy: if that
process is gone, remove the lock. Nothing takes a lock over automatically,
because its holder may be alive on another host (the mount is NFS, where
HDF5's own file lock is not effective); a lock left by a killed run is
removed by hand, and the refusal says which file. The lock is ADVISORY and
for Octopus writers: HDF5 itself does not honour it, and readers never take
it — [`TaskOutput`](@ref), [`turn_modulation_provenance`](@ref) and
`MomentOutput` read while a writer holds the file, see its last flushed
state, and say so once per writer with an `@info` naming the lock's line.
The in-process registry of live writers (the "second live observer"
warning) stays beside it.

**Crash recovery** is the per-group cursor attribute
`rows_valid_through_turn`, written AFTER its batch of rows and flushed with
it: on open, any rows beyond the cursor are a torn tail from an interrupted
write and are truncated. `capacity` is the rows-per-group buffered between
flushes — the ONE batching knob for the row-shaped producers (luminosity,
moments, BPM readings; the per-observer capacities retired 2026-08-18).
Snapshots are the deliberate exception: a phase-space block is already
large (N particles x 8 columns), so each fire writes its block immediately
— the per-write cost the capacity exists to amortize is negligible against
the block itself, and buffering blocks would multiply host memory for
nothing. A snapshot's volume knobs are its SCHEDULE and `npart`. The file
handle is held open for the whole `execute!`, so flushing costs no
open/close.

`record_turn_modulation=false` (default) leaves the per-turn offsets of the
turn-modulation rules unrecorded; `true` records them, on every turn of every
`execute!` the artifact serves, as the `series` dataset beside each modulated
element's provenance (docs/design/turn_modulation_record.md): one row per
turn, one column per active slot, fed by the SAME evaluation that builds the
realised element -- the hook hands the recorder its draws; nothing is read
back from the element and no rule is evaluated twice -- buffered `capacity`
rows at a time and flushed through the same single-threaded writer as the
luminosity rows, written by rank 0 under MPI (every rank realises the same
values) and host-side on CUDA (the rules never reach the device). Off,
nothing in the tracking changes and no `series` is written; on, nothing in
the tracking changes either -- the coordinates, the luminosity, the moments
and the `:turn_modulation` receipt are bitwise what they are with it off --
and the file grows by 8 bytes per active slot per turn, which is why the
default is off. A value that is not `true` or `false` is refused by name.
Inactive on a line with no modulated element: there is nothing to record and
nothing is written, as the provenance writes nothing for such an `execute!`.
Structured metadata: [`run_artifact_option_schema`](@ref).

**What the prepare resolved** is on record once per `execute!` as the
`:run_artifact_output` receipt (`with_execution_audit`; 2026-10-16 fix batch,
S4-1/S4-2), recorded by `prepare_run_artifact!` itself -- the one consumer
boundary of these three options, reached from both task kinds -- after its
last refusal: `task` (the carrying task's kind), `artifact` (the path),
`append` (the request) beside `continued` (what happened: an existing file
was continued, or the file was created fresh), `capacity` (the batching every
row producer and recorder uses), `record_turn_modulation` (the request)
beside `recording` (recorders built: the switch on AND the line has a
modulated element) and `execution` (the ledger row appended). Each task kind
records its own output receipt beside it (`:tracking_output`,
`:strong_strong_output`) with the artifact path and the luminosity channels
it opened.

Pass it to the task (`StrongStrongTask(...; artifact=RunArtifact(path))`, or
a bare path as sugar). The artifact path is registered by artifact identity,
so the same task continuing is silent while a second writer on the path
draws the collision warning.
"""
mutable struct RunArtifact <: AbstractRunArtifact
    path::String
    append::Bool
    capacity::Int
    record_turn_modulation::Bool
    # execute!-scoped state
    file::Union{Nothing,HDF5.File}
    # The series recorders of the current execute!, one per beam whose line
    # has a modulated element; empty unless `record_turn_modulation` is on,
    # and on rank 0 only (the other ranks hold no file). Built at prepare,
    # flushed and emptied at finalize.
    turn_modulation_recorders::Vector{TurnModulationRecorder}
    pending_turns::Dict{String,Vector{Int64}}
    pending_values::Dict{String,Vector{Float64}}
    execution_slot::Int
    start_time_ns::UInt64
    registered::Bool
    # The turn the current execution has reached (execute!-scoped, set by
    # the task's turn loop); persisted into /execution/current_turn at every
    # flush, so the ledger row tracks live progress.
    current_turn::Int64
    # Probe identities bound THIS execute! (kind/name keys): the uniqueness
    # domain of the design's name-as-identity rule. Cleared at prepare.
    probe_names::Set{String}
    # The line this writer wrote into the sidecar lock `<path>.lock` while it
    # holds the file (`_ra_take_lock!`), `nothing` when it holds no lock: the
    # cross-process exclusion of 2026-10-16 (neighbour audit, S5-2).
    lock_line::Union{Nothing,String}
    # What the prepare RESOLVED for the current execute! (execute!-scoped, rank
    # 0): whether an existing file was continued (`append` is the request; a
    # path that does not exist yet is created fresh under `append=true`). The
    # `:run_artifact_output` receipt carries it (2026-10-16 fix batch, S4-2).
    continued::Bool
    # The window protocol (2026-10-19 fix batch, F-56/F-58), execute!-scoped on
    # rank 0: the window's first turn the replay rule truncates against, the
    # probes bound and not yet committed, and whether `commit_run_artifact!`
    # has applied the rule -- before it no row may arrive and `/losses` is not
    # written; set at prepare, cleared at finalize.
    first_turn::Int64
    committed::Bool
    pending_probes::Vector{PendingProbeBind}
end

function RunArtifact(path::AbstractString; append=false, capacity=64,
                     record_turn_modulation=false)
    # Refused BY NAME (2026-10-16 neighbour audit, S4-6): `append=1` used to
    # die in a TypeError that named no keyword, and `capacity=true` was
    # accepted as 1 because `Integer` admits `Bool`.
    append isa Bool || throw(ArgumentError(
        "RunArtifact append must be true or false; got $(repr(append))."))
    (capacity isa Integer && !(capacity isa Bool)) || throw(ArgumentError(
        "RunArtifact capacity must be an integer number of turns; got $(repr(capacity))."))
    cap = Int(capacity)
    cap >= 1 || throw(ArgumentError("RunArtifact capacity must be at least 1; got $(cap)."))
    # Refused BY NAME, not coerced: `record_turn_modulation=1` is not a request
    # this option understands, and a truthy non-Bool read as `true` would be
    # a configuration the caller never wrote.
    record_turn_modulation isa Bool || throw(ArgumentError(
        "RunArtifact record_turn_modulation must be true or false; got " *
        "$(repr(record_turn_modulation))."))
    return RunArtifact(String(path), Bool(append), cap, record_turn_modulation, nothing,
                       TurnModulationRecorder[],
                       Dict{String,Vector{Int64}}(), Dict{String,Vector{Float64}}(),
                       0, UInt64(0), false, Int64(0), Set{String}(), nothing, false,
                       Int64(0), false, PendingProbeBind[])
end

"""
    run_artifact_option_schema() -> NamedTuple

Public configuration options of [`RunArtifact`](@ref) -- `append`, `capacity`
and `record_turn_modulation` -- as `ConfigurationOptionMeta`, the twin of
`tracking_task_option_schema()`. Checked by `validate_configuration_metadata()`:
every key is a field of the type, every declared default equals what the
constructor builds, and every option names the runtime boundary that applies
it. All three name the `:run_artifact_output` receipt, which
`prepare_run_artifact!` -- the one boundary that applies them, reached from
both task kinds -- records once per `execute!` after its last refusal, with
what it RESOLVED beside each request: `append` beside `continued` (an
existing file continued, or created fresh), `capacity` as every row-shaped
producer and recorder batches by it, `record_turn_modulation` beside
`recording` (recorders built: the switch on AND the line has a modulated
element), and the ledger row `execution`. Before the 2026-10-16 fix batch
(neighbour audit S4-1, S4-2) `append` and `record_turn_modulation` named the
`:strong_strong_output` receipt, unreachable from a `TrackingTask` and
carrying the REQUEST, and `capacity` the `:observer_output` receipts, recorded
only with a `MomentObserver` present. The effect of `record_turn_modulation`
is the `series` dataset itself, read back through
`turn_modulation_provenance`; the `:turn_modulation` receipt is unchanged by
the switch (D9 of docs/design/turn_modulation_record.md). The suite derives
the option-to-receipt pairs from this schema and checks them under both task
kinds ("Run artifact receipts and slots: ...").
"""
run_artifact_option_schema() = (
    append=ConfigurationOptionMeta(Bool, false,
        "`false` recreates the file per `execute!`; `true` continues it across " *
        "`execute!` calls and process restarts under the replay idempotence rule " *
        "(rows at or beyond the incoming window's first turn are dropped per group " *
        "first, /losses included, by commit_run_artifact! after every refusal). A " *
        "file whose luminosity groups do not match the task's collision labels is " *
        "refused rather than silently mixed, as is an existing file that is not " *
        "HDF5, one without the ledger, one holding a partial /turn_modulation slot " *
        "and one whose /losses names other apertures; a refused continuation " *
        "leaves the file as found. Resolved at prepare: the :run_artifact_output " *
        "receipt's `continued` says whether an existing file was continued or " *
        "the path was created fresh.";
        category=:output, consumer=:run_artifact_output),
    capacity=ConfigurationOptionMeta(Int, 64,
        "Rows per group buffered between flushes, the ONE batching knob for every " *
        "row-shaped producer (luminosity, moments, BPM readings, the turn-modulation " *
        "series); snapshots write their block per fire. At least 1, refused by name " *
        "otherwise. Carried as applied by the :run_artifact_output receipt and by " *
        "the :observer_output receipts of the probes that batch by it.";
        category=:output, consumer=:run_artifact_output),
    record_turn_modulation=ConfigurationOptionMeta(Bool, false,
        "Record the turn-modulation rules' per-turn offsets as the `series` dataset " *
        "beside each modulated element's `/turn_modulation` provenance: one row per " *
        "turn, one Float64 column per active slot (radians on a phase slot, the " *
        "relative factor d on a strength slot), from the same evaluation that builds " *
        "the realised element, batched with `capacity`, written by rank 0, host-side " *
        "on CUDA. OFF by default because it costs 8 bytes per active slot per turn " *
        "without bound; the tracking, the luminosity, the moments and the " *
        ":turn_modulation receipt are bitwise identical with it on and off. Inactive " *
        "on a line with no modulated element (nothing to record, nothing written); a " *
        "value other than true or false is refused by name. Read back with " *
        "turn_modulation_provenance(path) or read(TaskOutput(path), :turn_modulation): " *
        "each slot entry's `series` (nothing when the run did not record) and `nominal`, " *
        "each element entry's `first_turn` and `turns` (the window the series covers). " *
        "Resolved at prepare: the :run_artifact_output receipt's `recording` says " *
        "whether recorders were built (the switch on AND a modulated element).";
        category=:output, consumer=:run_artifact_output),
)

# ---------------------------------------------------------------------------
# The output receipts (2026-10-16 fix batch; neighbour audit S4-1, S4-2, S4-10).
# A receipt names ONE consumer and an option's metadata names ONE consumer, and
# the artifact is one object two task kinds carry: the only receipt that is
# true under both is the one the artifact records at its own boundary,
# `prepare_run_artifact!`, after its last refusal -- the request under each
# option's own name, what was applied beside it (Measured Lesson 11: a receipt
# that echoes the request passes while the run does something else). Each
# task kind records its own output receipt beside it with the task's output
# options (`_ra_task_output_receipt`). Both shapes are built here, once.
# ---------------------------------------------------------------------------

"""
    _ra_output_receipt(art, task_kind, turn_modulation) -> NamedTuple

The values of the `:run_artifact_output` receipt for `art` after this rank's
prepare: `task`, `artifact`, `append` and `continued`, `capacity`,
`record_turn_modulation` and `recording`, `execution`. On rank 0 `continued`
and `execution` are what the prepare decided; a non-root rank opens no file
and decides neither, so it carries `nothing` for both (said, not guessed),
while `recording` -- the switch on AND a modulated element in the line -- is
the same truth on every rank.
"""
function _ra_output_receipt(art::RunArtifact, task_kind::AbstractString, turn_modulation)
    root = _mp_is_root()
    recording = root ? !isempty(art.turn_modulation_recorders) :
                       (art.record_turn_modulation && !isempty(turn_modulation))
    return (task=Symbol(task_kind), artifact=art.path,
            append=art.append, continued=root ? art.continued : nothing,
            capacity=art.capacity,
            record_turn_modulation=art.record_turn_modulation, recording=recording,
            execution=root ? art.execution_slot : nothing)
end

"""
    _ra_task_output_receipt(art, channels; extra...) -> NamedTuple

The values of a task kind's output receipt (`:tracking_output`,
`:strong_strong_output`): `artifact` (the path, `nothing` without one),
`channels` (the luminosity channel labels the artifact opened with, `nothing`
without one) and the task's own output options in `extra` (`loss_report` on
the `TrackingTask`). Recorded by each task once per `execute!` AFTER its
artifact is prepared -- or in its place when there is none -- so a prepare
refusal leaves no output receipt claiming a run.
"""
_ra_task_output_receipt(::Nothing, channels; extra...) =
    (; artifact=nothing, channels=nothing, extra...)
_ra_task_output_receipt(art::RunArtifact, channels; extra...) =
    (; artifact=art.path, channels=collect(String, channels), extra...)

"""
    _ra_artifact_entry(art, consumer) -> ConfigurationEntry

The `:artifact` output entry of a task's `configuration_report`, shared by both
task kinds. A report runs BEFORE the `execute!`, so it can state the request
and what is already decided, not the resolution: `append=false` and
`record_turn_modulation=false` leave nothing to decide (`:resolved`,
"rewriting"); `append=true` and `record_turn_modulation=true` are decided at
prepare (whether the file exists; whether the line has a modulated element)
and reported by the `:run_artifact_output` receipt, so the entry is
`:unresolved` and says where the answer lands (before the 2026-10-16 fix
batch the strong-strong report called the request `:resolved`, S4-2). No
artifact: `:inactive_dependency`.
"""
function _ra_artifact_entry(art::Union{Nothing,RunArtifact}, consumer::Symbol)
    art === nothing && return ConfigurationEntry(:artifact, nothing, nothing, :inactive_dependency,
                                                 "run-artifact output disabled", consumer)
    pending = art.append || art.record_turn_modulation
    reason = (art.append ? "continuing" : "rewriting") * " the run artifact at " * art.path *
             (art.append ? " (whether an existing file is continued is decided at prepare: " *
                           "the :run_artifact_output receipt's `continued`)" : "") *
             (art.record_turn_modulation ?
              ", recording the turn-modulation series (whether the line has a modulated " *
              "element is decided at prepare: the receipt's `recording`)" : "")
    return ConfigurationEntry(:artifact, art, art.path, pending ? :unresolved : :resolved,
                              reason, consumer)
end

# HDF5 attribute write-or-overwrite (plain assignment refuses an existing
# attribute in HDF5.jl, and the cursor is rewritten at every flush).
function _ra_set_attr!(obj, name::String, value)
    a = HDF5.attributes(obj)
    haskey(a, name) && HDF5.delete_attribute(obj, name)
    a[name] = value
    return nothing
end

_ra_get_attr(obj, name::String, default) = begin
    a = HDF5.attributes(obj)
    haskey(a, name) ? read(a[name]) : default
end

function _ra_extendable!(parent, name::String, ::Type{T}) where {T}
    return HDF5.create_dataset(parent, name, HDF5.datatype(T),
                               HDF5.dataspace((0,); max_dims=(-1,)); chunk=(256,))
end

function _ra_append_rows!(dset, vals)
    n = length(dset)
    HDF5.set_extent_dims(dset, (n + length(vals),))
    dset[(n + 1):(n + length(vals))] = vals
    return nothing
end

# Truncate one luminosity group to rows with turn <= keep_through. Rows are in
# ascending turn order (schedules plan forward; rewinds drop), so the cutoff
# is a scan for the boundary.
function _ra_truncate_group!(g, keep_through::Int64)
    dt, dv = g["turns"], g["values"]
    turns = length(dt) == 0 ? Int64[] : read(dt)
    keep = searchsortedlast(turns, keep_through)
    if keep < length(turns)
        HDF5.set_extent_dims(dt, (keep,))
        HDF5.set_extent_dims(dv, (keep,))
    end
    _ra_set_attr!(g, "rows_valid_through_turn",
                  Int64(keep == 0 ? typemin(Int32) : turns[keep]))
    return nothing
end

# ---------------------------------------------------------------------------
# The /execution ledger's columns, ONE table for the writer that creates them,
# the writer that appends a row, the continue-check and the reader (2026-10-16
# neighbour audit, S5-4). The row's values at prepare are, in this order: the
# window's first turn, its planned length, `first_turn - 1` (nothing reached
# yet), `0.0` elapsed, and the global stochastic seed and counter-RNG method in
# force when the `execute!` began -- `rng_method` as the method's name
# (`string(global_rng_method())`, derived from `rng_method_symbol`, so a new
# method names itself here). Before these two columns a file recorded the
# global seed nowhere: after a `set_global_rng!` between two windows its only
# mention of a seed was a spectral table's canonical name.
# ---------------------------------------------------------------------------
const _RA_LEDGER_COLUMNS = (("start_turn", Int64), ("turns", Int64), ("current_turn", Int64),
                            ("elapsed", Float64), ("rng_seed", UInt64), ("rng_method", String))

# ---------------------------------------------------------------------------
# Cross-process exclusion: the sidecar lock (2026-10-16 neighbour audit, S5-2).
# HDF5's own file lock is not effective on this NFSv3 mount, and nothing else
# stopped a second PROCESS from opening a path another process held: measured
# with `append=false` the second writer truncated the first's open file (which
# then read back torn: "len not positive after adjustment for EOA"), with
# `append=true` both appended into one ledger, and two concurrent writers of
# one path both finished with one run's 400 rows silently gone. The in-process
# registry (`_register_observer_path!`, U7-10) sees only this process. The lock
# is ADVISORY and for Octopus writers: HDF5 itself does not honour it, and a
# reader never takes it (a second process may read while the first writes and
# sees the last flushed state; the readers announce the writer instead,
# `_ra_open`). There is NO automatic stale-lock takeover: the lock may belong
# to a process on another host, and a decision to remove it is the user's --
# the refusal says what it found and how to remove it.
# ---------------------------------------------------------------------------

"""The sidecar lock file of the artifact at `path`: `<path>.lock`."""
_ra_lock_path(path::AbstractString) = String(path) * ".lock"

"""
    _ra_lock_info(path) -> Union{Nothing,String}

The line a live Octopus writer wrote into the sidecar lock of the artifact at
`path` (`host=<hostname> pid=<pid> since=<ISO 8601 local time> task=<task
kind>`), or `nothing` when no lock file exists (the lock removed between the
existence check and the read counts as none). A lock file that exists but holds
no line -- its writer was interrupted between creating and writing it -- reads
as a string saying so, so a refusal can still name the lock.
"""
function _ra_lock_info(path::AbstractString)
    lock = _ra_lock_path(path)
    isfile(lock) || return nothing
    line = try
        strip(read(lock, String))
    catch err
        err isa Union{SystemError,Base.IOError} || rethrow()
        return nothing
    end
    return isempty(line) ? "its line is empty: the writer was interrupted before it wrote it" :
           String(line)
end

"""
    _ra_take_lock!(art, task_kind)

Create the sidecar lock of `art.path` EXCLUSIVELY (`O_CREAT | O_EXCL`, so two
processes racing for one path cannot both succeed) and write its one line --
this host, this process id, the time and `task_kind` -- remembering the line
in `art.lock_line` for the release. An existing lock refuses the open with an
`ArgumentError` naming the lock path, the line it holds (who, where, since
when) and the remedy: if that process is gone, remove the lock. Nothing is
taken over automatically. A lock created whose line could not be written is
removed again before the error propagates, so a failed take leaves no lock.
"""
function _ra_take_lock!(art::RunArtifact, task_kind::AbstractString)
    lock = _ra_lock_path(art.path)
    line = "host=$(gethostname()) pid=$(getpid()) since=" *
           Libc.strftime("%Y-%m-%dT%H:%M:%S%z", time()) * " task=$(task_kind)"
    flags = Base.Filesystem.JL_O_WRONLY | Base.Filesystem.JL_O_CREAT | Base.Filesystem.JL_O_EXCL
    fd = try
        Base.Filesystem.open(lock, flags, 0o644)
    catch err
        if err isa Base.IOError && err.code == Base.UV_EEXIST
            held = _ra_lock_info(art.path)
            throw(ArgumentError(
                "RunArtifact at $(art.path): another Octopus writer holds its lock $(lock) " *
                "($(held === nothing ? "its line could not be read: the lock was removed or " *
                "emptied in the meantime" : held)); a second writer on one path would silently " *
                "lose one run's output, so this execute! is refused. If that process is gone, " *
                "remove $(lock)."))
        end
        rethrow()
    end
    written = false
    try
        write(fd, line * "\n")
        written = true
    finally
        close(fd)
        written || rm(lock; force=true)
    end
    art.lock_line = line
    return nothing
end

"""
    _ra_release_lock!(art)

Remove the sidecar lock `art` holds (nothing when it holds none), AFTER its
file is closed, so a writer that takes the lock next finds the file released.
Only this writer's own lock is removed: a lock file that vanished while held,
or that now carries another writer's line, means someone removed this one
while the run was live and perhaps wrote the path -- said out loud with a
warning naming the path and the lock, and a stranger's lock is left in place.
"""
function _ra_release_lock!(art::RunArtifact)
    line = art.lock_line
    line === nothing && return nothing
    art.lock_line = nothing
    lock = _ra_lock_path(art.path)
    held = _ra_lock_info(art.path)
    if held === nothing
        @warn "the run artifact's lock file was removed while this writer held it; another " *
              "writer may have written the path in the meantime, and the two runs' rows " *
              "may interleave" path = art.path lock = lock
    elseif held != line
        @warn "the run artifact's lock file no longer carries this writer's line: it was " *
              "removed and retaken by another writer while this run was live; that " *
              "writer's lock is left in place" path = art.path lock = lock held = held
    else
        rm(lock; force=true)
    end
    return nothing
end

"""
Open (or create) the artifact for one `execute!`: validate the file against
this window -- every by-name refusal of the table `_RA_PREPARE_CHECKS`, run in
the table's order after the open and BEFORE anything is written to a continued
file -- then append this execution's ledger row, record the line's
turn-modulation provenance `turn_modulation` (the receipt entries of
`_turn_modulation_entries`) under `/turn_modulation/<slot>` for that row --
nothing when empty -- with each active slot's nominal parameters from
`turn_modulation_columns` (the aligned entries of `_turn_modulation_columns!`,
required whenever `turn_modulation` is non-empty), create the `series`
datasets and this execution's recorders when `record_turn_modulation` is on,
register the path by artifact identity, hold the file open, and record the
`:run_artifact_output` receipt with what was resolved
(`_ra_output_receipt`).

The replay rule is NOT applied here (2026-10-19 fix batch, F-56/F-58): the
luminosity channels and the probe groups keep every row until
[`commit_run_artifact!`](@ref), which the task calls after its observers have
bound -- each bind validating its group without touching it -- and after its
last refusal that can stop the run before the first turn. A continuation this
function refuses therefore leaves the file BYTE-IDENTICAL, measured by the
suite for every entry of the table; before the fix four of the refusals fired
after the truncation had dropped every luminosity row at or beyond
`first_turn` (100 rows and cursor 99 became 50 and 49).

Before the file opens, fresh or continued, rank 0 takes the sidecar lock
`<path>.lock` (`_ra_take_lock!`; `task_kind` is the task's type name, written
into the lock line so a refused second writer learns who holds the path);
a path another Octopus process holds is refused by name, and the lock is
released with the file at finalize and on every path that closes it, this
function's own refusals included. A continued path that exists and is not
an HDF5 file is refused by name BEFORE the open (`HDF5.ishdf5`; before the
2026-10-16 fix batch HDF5's own "unable to determine if ... is accessible"
message surfaced first, S5-7). The table's checks, in order: the file is a
run artifact (`/luminosity`); its luminosity groups are exactly `labels`; it
carries the `/execution` ledger with every column of `_RA_LEDGER_COLUMNS`
(a continued file lacking any predates the seed columns and is refused by
name rather than padded); no `/turn_modulation` slot is PARTIAL (a cursor
behind its element count, the artefact of a writer that stopped mid-prepare;
never rolled back); its `/losses` group, when present and `aperture_names`
is given, names exactly this task's apertures (`aperture_names` is the
task's loss record's names; `nothing`, the default, is a writer that records
no losses and leaves the group unchecked); and the provenance slot the
ledger row would take is free, with the recorder's column walk agreeing with
the provenance. The in-process path registry is written AFTER the last of
these refusals, so a refused writer is never registered as a live one (unit
A's open point, 2026-10-16); the lock keeps its place before the registry.
"""
function prepare_run_artifact!(art::RunArtifact, labels::Vector{String},
                               first_turn::Int, planned_turns::Int;
                               turn_modulation::AbstractVector=Any[],
                               turn_modulation_columns::AbstractVector=Any[],
                               aperture_names::Union{Nothing,AbstractVector{<:AbstractString},NamedTuple}=nothing,
                               task_kind::AbstractString="prepare_run_artifact!")
    art.file === nothing || error("RunArtifact at $(art.path) is already open; " *
                                  "one artifact serves one execute! at a time")
    # A recorder outlives nothing: whatever the previous execute! left is gone
    # before this one decides whether it records (on every rank, so a
    # non-root rank never holds one either).
    empty!(art.turn_modulation_recorders)
    # One run, one output file, written by rank 0. Every rank still runs the
    # observers -- their reductions are collectives and a rank that skipped
    # them would hang its peers -- but only rank 0 opens the file, so the
    # others leave `file === nothing` and every write below no-ops. A
    # non-root rank still records the output receipt, with the decisions it
    # did not make (`continued`, `execution`) as `nothing`.
    if !_mp_is_root()
        _record_execution!(:run_artifact_output, _observer_backend(),
                           _ra_output_receipt(art, task_kind, turn_modulation))
        return nothing
    end
    # The lock first, for a fresh open as for a continued one: whether the
    # file is to be truncated or appended is decided under exclusion, and a
    # path another process holds is refused before anything touches it --
    # before the in-process registry too (written after the last refusal
    # below), so a refused writer is not registered as a live one.
    _ra_take_lock!(art, task_kind)
    fresh = !art.append || !isfile(art.path) || filesize(art.path) == 0
    # An existing file that is not HDF5 cannot be a run artifact: refused by
    # name BEFORE the open, which would otherwise fail first with HDF5's own
    # "unable to determine if ... is accessible in the HDF5 format" and make
    # the by-name refusal below unreachable (2026-10-16 neighbour audit, S5-7).
    if !fresh && !HDF5.ishdf5(art.path)
        _ra_release_lock!(art)
        throw(ArgumentError(
            "RunArtifact(append=true): $(art.path) exists ($(filesize(art.path)) bytes) and is " *
            "not an HDF5 file, so it is not a run artifact this writer can continue; use a " *
            "new path or append=false"))
    end
    file = try
        HDF5.h5open(art.path, fresh ? "w" : "r+")
    catch
        # The open itself failed (a handle this process holds, an unwritable
        # path): the lock goes with it, or the path would stay refused.
        _ra_release_lock!(art)
        rethrow()
    end
    try
        if fresh
            _ra_set_attr!(file, "octopus_run_artifact", Int64(1))
            lum = HDF5.create_group(file, "luminosity")
            for label in labels
                g = HDF5.create_group(lum, label)
                _ra_extendable!(g, "turns", Int64)
                _ra_extendable!(g, "values", Float64)
                _ra_set_attr!(g, "label", label)
                _ra_set_attr!(g, "rows_valid_through_turn", Int64(typemin(Int32)))
            end
            ex = HDF5.create_group(file, "execution")
            for (name, T) in _RA_LEDGER_COLUMNS
                _ra_extendable!(ex, name, T)
            end
        end
        # VALIDATION BEFORE MUTATION (2026-10-19 fix batch, F-56): every
        # by-name refusal of this window, in the table's order, before a
        # continued file is written to. The table `_RA_PREPARE_CHECKS` is the
        # one source -- the suite derives a byte-identity fixture per entry
        # from it -- and nothing below truncates: the replay rule waits for
        # `commit_run_artifact!`, after every probe has bound. A fresh file
        # passes the continuation checks by construction (its skeleton was
        # just created) and still meets the provenance check, which concerns
        # both. Checked BEFORE the ledger datasets are extended, so a refusal
        # leaves the ledger as it found it (U5-3: a refusal after the append
        # left a phantom row the reader paired with a stranger group).
        ctx = (path=art.path, labels=labels, first_turn=Int64(first_turn),
               entries=turn_modulation, columns=turn_modulation_columns,
               aperture_names=aperture_names)
        for check in _RA_PREPARE_CHECKS
            check(file, ctx)
        end
        ex = file["execution"]
        n = length(ex["start_turn"])
        # The row's values in the table's column order (`_RA_LEDGER_COLUMNS`):
        # the seed and the method are those in force NOW, as this execute!
        # begins, which is what every stochastic consumer of the window keys
        # its draws on.
        row = (Int64(first_turn), Int64(planned_turns), Int64(first_turn) - 1, 0.0,
               UInt64(global_rng_seed()), string(global_rng_method()))
        length(row) == length(_RA_LEDGER_COLUMNS) || error(
            "the /execution ledger row has $(length(row)) values for " *
            "$(length(_RA_LEDGER_COLUMNS)) columns")
        for ((name, T), val) in zip(_RA_LEDGER_COLUMNS, row)
            d = ex[name]
            HDF5.set_extent_dims(d, (n + 1,))
            d[n + 1] = convert(T, val)
        end
        art.execution_slot = n + 1
        # Keyed by the ledger row just appended, so written after it: the
        # provenance groups and, with the switch on, each element's `series`
        # dataset inside the same per-element loop, so the slot group's cursor
        # blesses an element only once its dataset exists too.
        _ra_write_turn_modulation!(file, art.path, art.execution_slot, turn_modulation,
                                   turn_modulation_columns;
                                   series=art.record_turn_modulation ?
                                          (Int(first_turn), Int(planned_turns)) : nothing)
        # The recorders over those datasets; the ONE branch the switch takes at
        # prepare (the turn loops read them back through `_turn_modulation_sink`).
        art.record_turn_modulation &&
            _ra_build_turn_modulation_recorders!(art, file, art.execution_slot, turn_modulation,
                                                 turn_modulation_columns)
        art.start_time_ns = time_ns()
        art.current_turn = Int64(first_turn) - 1
        # The window protocol's state (F-56/F-58): uncommitted until the task
        # calls `commit_run_artifact!`, no probe bound yet.
        art.first_turn = Int64(first_turn)
        art.committed = false
        empty!(art.pending_probes)
        empty!(art.probe_names)
        HDF5.flush(file)
    catch
        # A refusal leaves the path as it found it: file closed, lock gone,
        # and -- the registry being written only below -- not registered.
        close(file)
        _ra_release_lock!(art)
        rethrow()
    end
    # The in-process registry AFTER the last refusal (unit A's open point,
    # 2026-10-16): a writer refused inside the body above stayed registered as
    # a live one until the process ended when this sat before the open.
    if !art.registered
        _register_observer_path!(art, art.path)
        art.registered = true
    end
    art.file = file
    art.continued = !fresh
    empty!(art.pending_turns)
    empty!(art.pending_values)
    # The resolution, on record (S4-1, S4-2): recorded last, so a refused
    # prepare leaves no receipt claiming a prepared artifact.
    _record_execution!(:run_artifact_output, _observer_backend(),
                       _ra_output_receipt(art, task_kind, turn_modulation))
    return nothing
end

"""
    commit_run_artifact!(art)

Commit this `execute!`'s window: apply the replay idempotence rule to EVERY
group the window writes, at once, after the last refusal that can stop the run
before its first turn (2026-10-19 fix batch, F-56/F-58). Each luminosity
channel of a continued file is truncated to `min(cursor, first_turn - 1)` --
the torn tail beyond its `rows_valid_through_turn` cursor and the rows at or
beyond this window's first turn, one bound -- and each probe bound this
`execute!` (`_ra_bind_probe!`, which validated without touching the file) is
created, or truncated the same way, and stamped with its `s`
(`_ra_commit_probe!`). Then rows may arrive: `push_luminosity!` and
`_ra_push_probe_rows!` refuse by name before the commit (a row appended beyond
stale rows would be the silent form of the defect), a probe cannot bind after
it, and `_ra_write_losses!` writes `/losses` only for a committed window -- a
window refused before its commit leaves the file as the prepare found it, its
ledger row aside. Called once per `execute!` by both task kinds, right after
their observers have prepared (every bind done) and after their last pre-turn
refusal; a second call is an error. Nothing on a non-root rank, which holds no
file. Before the fix the prepare truncated the channels and each bind its own
group, so a later refusal left the earlier groups cut back.
"""
function commit_run_artifact!(art::RunArtifact)
    _mp_is_root() || return nothing
    f = art.file
    f === nothing && error(
        "RunArtifact at $(art.path) is not open: prepare_run_artifact! comes before " *
        "commit_run_artifact!")
    art.committed && error(
        "RunArtifact at $(art.path): the window starting at turn $(art.first_turn) is already " *
        "committed; commit_run_artifact! runs once per execute!")
    keep_through = art.first_turn - 1
    if art.continued
        # A fresh file's channels are new and empty: nothing to replay.
        lum = f["luminosity"]
        for label in keys(lum)
            g = lum[label]
            g isa HDF5.Group || continue
            cursor = Int64(_ra_get_attr(g, "rows_valid_through_turn",
                                        Int64(typemin(Int32))))
            # Torn tail first (rows the cursor never blessed), then the
            # replay rule: both reduce to one keep-through bound.
            _ra_truncate_group!(g, min(cursor, keep_through))
        end
    end
    for pending in art.pending_probes
        _ra_commit_probe!(f, pending)
    end
    empty!(art.pending_probes)
    art.committed = true
    HDF5.flush(f)
    return nothing
end

"""
Refuse to continue a file holding a PARTIAL `/turn_modulation` slot: a slot
group whose cursor `elements_valid_through` is behind its `element_count`, the
artefact of a writer that stopped between creating the group and completing
its last element (owner decision 2026-10-16: the reader reports it, nothing
rolls it back, and a new execution does not stack on top of it). A slot
group without the count (torn) or without the cursor (written before the
cursor existed) is not this check's concern; the readers judge those.
"""
function _ra_check_partial_slots(file, path::String)
    haskey(file, "turn_modulation") || return nothing
    root = file["turn_modulation"]
    for k in keys(root)
        g = root[k]
        g isa HDF5.Group || continue
        n = _ra_get_attr(g, "element_count", nothing)
        valid = _ra_get_attr(g, _RA_TM_CURSOR, nothing)
        (n === nothing || valid === nothing) && continue
        Int(valid) < Int(n) && throw(ArgumentError(
            "RunArtifact(append=true): /turn_modulation/$(String(k)) at $(path) is partial " *
            "($(Int(valid)) of $(Int(n)) modulated element group(s) written before the writer " *
            "stopped): a crash artefact this writer neither continues past nor rolls back; " *
            "use a new path, or remove the partial slot and its ledger row by hand"))
    end
    return nothing
end

# ---------------------------------------------------------------------------
# /turn_modulation/<slot>: the turn-by-turn modulation provenance of ONE
# execute!, keyed by its /execution ledger row (docs/design/turn_modulation.md,
# D7: the table rule owns its provenance in the run artifact). Attributes
# only, no turn axis: `element_count` on the slot group; one subgroup per
# modulated element in line order (`/turn_modulation/<slot>/<k>`, attrs
# `element`, `beam`, `slot_count`); one subgroup per ACTIVE slot below it named
# by the slot label (`.../<k>/phase_noise[1]`, attrs `index`, `kind`, `rng_id`,
# `digest`, `name`, `length`, and the slot's nominal parameters as
# `nominal_<name>`; HDF5 link names admit the brackets). Written at
# prepare from the provenance entries the task computes (`_turn_modulation_entries`;
# it records them as its `:turn_modulation` receipt after this prepare), so
# the artifact and the `:turn_modulation` receipt derive from the one walk;
# never rewritten or deleted, so a continued file keeps every generation.
#
# The SERIES (docs/design/turn_modulation_record.md, D3-D8; 2026-10-15): with
# `record_turn_modulation` on, each element group `<k>` also holds the dataset
# `series`, `turns` rows by one Float64 column per active slot in provenance
# order -- the OFFSETS the rules produced, row i being absolute turn
# `first_turn + i - 1` -- with the attributes `columns`, `first_turn`, `turns`,
# created at prepare (zero rows) and appended by the recorder every `capacity`
# turns and at finalize. The nominals a reader forms the realised values from
# are the slot groups' `nominal_*` attributes, written with the provenance
# whether or not the run records. The group name `state` directly under a slot
# group is RESERVED for the checkpoint of a future stateful rule (D10: one
# dataset per stateful slot, written once after the window's last turn); no
# shipped rule is stateful, nothing writes it today, and the readers return
# `nothing` for it.
# ---------------------------------------------------------------------------

"""
Every refusal of the provenance writer, run BEFORE anything is written: the
slot group must not exist, and the recorder's column walk must agree with
the provenance element for element and slot for slot. `prepare_run_artifact!`
runs it before it appends the ledger row and the writer runs it again before
it creates the first group, so a refusal leaves neither a ledger row without
its provenance (the phantom row, 2026-10-16 neighbour audit U5-6) nor a slot
group every reader rejects as torn (U5-3). The message names both counts of
the column walk (U5-4: it used to print the active count for either).
"""
function _ra_validate_turn_modulation!(file, path::String, slot::Int, entries, columns)
    isempty(entries) && return nothing
    _ra_check_turn_modulation_slot(file, path, slot, entries)
    length(columns) == length(entries) || throw(ArgumentError(
        "RunArtifact at $(path): the turn-modulation provenance lists $(length(entries)) " *
        "modulated element(s) but the recorder's column walk lists $(length(columns)); " *
        "the two walks over the line disagree"))
    for (k, entry) in enumerate(entries)
        col = columns[k]
        (length(col.active) == length(entry.slots) && length(col.nominal) == length(entry.slots)) ||
            throw(ArgumentError(
                "RunArtifact at $(path): modulated element $(k) ($(entry.element)) has " *
                "$(length(entry.slots)) active slot(s) in its provenance but " *
                "$(length(col.active)) active and $(length(col.nominal)) nominal " *
                "entries in the recorder's column walk"))
    end
    return nothing
end

# ---------------------------------------------------------------------------
# The prepare's refusals, ONE table (2026-10-19 fix batch, F-56).
# `prepare_run_artifact!` runs every entry, in order, after the open and before
# its first write, so a refused continuation leaves the file byte-identical.
# Each check takes the open file and the window's context
# `(path, labels, first_turn, entries, columns, aperture_names)` and returns
# `nothing` or throws the `ArgumentError` that names the cause. The order
# matters where a later check reads what an earlier one established (the
# ledger before its columns and the provenance slot). The suite derives one
# byte-identity fixture per entry from `_RA_PREPARE_CHECKS` and reads the
# prepare's body for the loop ("Run artifact replay: ..."), so an entry cannot
# join without its measurement and a refusal cannot leave the table. Before
# the table the ledger, column, partial-slot and provenance refusals sat
# after the luminosity truncation (100 rows and cursor 99 became 50 and 49).
# ---------------------------------------------------------------------------

"""The file is a run artifact: it carries a `/luminosity` group."""
function _ra_check_is_artifact(file, ctx)
    haskey(file, "luminosity") || throw(ArgumentError(
        "RunArtifact(append=true): $(ctx.path) is not a run artifact " *
        "(no /luminosity group). Use a new path."))
    return nothing
end

"""The luminosity groups are exactly this task's collision labels."""
function _ra_check_labels(file, ctx)
    existing = sort(collect(keys(file["luminosity"])))
    sort(ctx.labels) == existing || throw(ArgumentError(
        "RunArtifact(append=true): the luminosity groups at $(ctx.path) " *
        "($(existing)) do not match this task's collision labels " *
        "($(sort(ctx.labels))). Use a new path."))
    return nothing
end

"""
The `/execution` ledger is present: a file without it is not one this writer
made (2026-10-16 neighbour audit, U5-9: it used to surface as a raw KeyError).
"""
function _ra_check_ledger(file, ctx)
    haskey(file, "execution") || throw(ArgumentError(
        "RunArtifact(append=true): $(ctx.path) carries no /execution ledger, so it " *
        "is not a run artifact this writer can continue; use a new path or append=false"))
    return nothing
end

"""
Every column this writer appends is in the ledger. A file lacking any of them
predates the `rng_seed` and `rng_method` columns (2026-10-16, S5-4) and is
refused BY NAME, as found and unchanged, rather than padded: a padded seed
column would claim a provenance the earlier rows never recorded. (This
supersedes the step-1 `current_turn` padding, whose files lack these too.)
"""
function _ra_check_ledger_columns(file, ctx)
    ex = file["execution"]
    absent = String[]
    for (name, _) in _RA_LEDGER_COLUMNS
        haskey(ex, name) || push!(absent, name)
    end
    isempty(absent) || throw(ArgumentError(
        "RunArtifact(append=true): the /execution ledger at $(ctx.path) has no " *
        "$(join(absent, ", ")) column(s): the file predates the ledger's rng_seed and " *
        "rng_method columns (2026-10-16) and this writer does not continue it; use a " *
        "new path or append=false"))
    return nothing
end

"""The table's method of `_ra_check_partial_slots`: no provenance slot is partial."""
_ra_check_partial_slots(file, ctx::NamedTuple) = _ra_check_partial_slots(file, ctx.path)

"""
The `/losses` group, when the file has one and the task records losses
(`aperture_names !== nothing`), names exactly this task's apertures: a
continued file keeps the earlier windows' loss rows under the file's aperture
ids (`_ra_write_losses!`, F-57), so a line with other apertures -- or none --
is refused rather than silently mixed, the luminosity labels' rule. A group
without the names dataset is not one this writer wrote and is refused as torn.
`aperture_names` is a vector for a one-beam writer (a `TrackingTask`, whose
group is `/losses` itself) and a NamedTuple `(beam_1 = ..., beam_2 = ...)` for
a `StrongStrongTask` (one entry per beam, that beam's record names or none;
its groups are `/losses/beam_<i>`, unit R of the same fix batch): each beam
group the file holds must name that beam's apertures, and the other task
kind's layout is refused by name rather than nested into or replaced silently.
"""
function _ra_check_loss_apertures(file, ctx)
    ctx.aperture_names === nothing && return nothing
    haskey(file, "losses") || return nothing
    g = file["losses"]
    if ctx.aperture_names isa NamedTuple
        haskey(g, "aperture_names") && throw(ArgumentError(
            "RunArtifact(append=true): the /losses group at $(ctx.path) is a one-beam " *
            "(TrackingTask) group, which a StrongStrongTask, writing /losses/beam_<i>, does " *
            "not continue; use a new path or append=false"))
        for (key, names) in pairs(ctx.aperture_names)
            haskey(g, String(key)) || continue
            _ra_check_loss_group_apertures(g[String(key)], "/losses/$(key)",
                                           collect(String, names), ctx.path)
        end
        return nothing
    end
    _ra_check_loss_group_apertures(g, "/losses", collect(String, ctx.aperture_names), ctx.path)
    return nothing
end

# One loss group (`where`: `/losses` or `/losses/beam_<i>`) against the
# apertures `names` the task's line carries for it.
function _ra_check_loss_group_apertures(g, where::String, names::Vector{String}, path::String)
    haskey(g, "aperture_names") || throw(ArgumentError(
        "RunArtifact(append=true): the $(where) group at $(path) has no aperture_names " *
        "dataset, so it is not a group this writer can continue; use a new path or append=false"))
    stored = String.(read(g["aperture_names"]))
    stored == names || throw(ArgumentError(
        "RunArtifact(append=true): the $(where) group at $(path) names the apertures " *
        "$(stored) but this task's line has " *
        (isempty(names) ? "no aperture" : "the apertures $(names)") * "; a continued file " *
        "keeps the losses of its earlier windows under the file's aperture ids, so a " *
        "different aperture set is refused rather than silently mixed. Use a new path or " *
        "append=false"))
    return nothing
end

"""
The provenance slot the ledger row would take is free and the recorder's
column walk agrees with the provenance (`_ra_validate_turn_modulation!`; the
writer runs it again before it creates the first group). Reads the ledger, so
it follows `_ra_check_ledger` in the table.
"""
_ra_check_turn_modulation(file, ctx) =
    _ra_validate_turn_modulation!(file, ctx.path, length(file["execution"]["start_turn"]) + 1,
                                  ctx.entries, ctx.columns)

const _RA_PREPARE_CHECKS = (_ra_check_is_artifact, _ra_check_labels, _ra_check_ledger,
                            _ra_check_ledger_columns, _ra_check_partial_slots,
                            _ra_check_loss_apertures, _ra_check_turn_modulation)

"""
Write `/turn_modulation/<slot>` for the ledger row `slot` just appended:
nothing when `entries` is empty (an unmodulated `execute!` leaves no group for
its slot), otherwise the element groups and their slot groups, each slot group
carrying its nominal parameters from `columns` (the entries of
`_turn_modulation_columns!`, aligned with `entries`; a misaligned pair is
refused by name), and, with `series = (first_turn, planned_turns)`, each
element's `series` dataset (zero rows, one `Float64` column per active slot,
extendable, chunked `(256, ncols)`; attributes `columns`, `first_turn`,
`turns`) created right after its slot groups. Nothing here is
ever rewritten or deleted -- every execution that had a modulated element
keeps its own record, so a continued file holds every generation of rules it
ran; a slot group that already exists can only mean the ledger and the
provenance disagree, and is refused by `_ra_check_turn_modulation_slot`, which
`prepare_run_artifact!` runs BEFORE appending the row (U5-3) and this writer
runs again.

The slot group's CURSOR (owner decision 2026-10-16, the stage 3-4 audit's
U5-2: no rollback, the reader reports): `elements_valid_through` is created
at 0 BEFORE the first element group and advanced to `k` only after element
`k` is complete -- its attributes, its slot groups with their nominals, and
its `series` dataset when recording. A writer stopped by an HDF5 error
mid-way leaves the cursor behind `element_count`: a PARTIAL slot, which the
readers read as far as the cursor with a warning naming the slot, and which
`append=true` refuses by name. The row groups' `rows_valid_through_turn` is
the same protocol one level down.
"""
function _ra_write_turn_modulation!(file, path::String, slot::Int, entries, columns;
                                    series::Union{Nothing,Tuple{Int,Int}}=nothing)
    isempty(entries) && return nothing
    _ra_validate_turn_modulation!(file, path, slot, entries, columns)
    root = haskey(file, "turn_modulation") ? file["turn_modulation"] :
           HDF5.create_group(file, "turn_modulation")
    g = HDF5.create_group(root, string(slot))
    _ra_set_attr!(g, "element_count", Int64(length(entries)))
    # The cursor before any element group: nothing valid yet.
    _ra_set_attr!(g, _RA_TM_CURSOR, Int64(0))
    for (k, entry) in enumerate(entries)
        col = columns[k]
        eg = HDF5.create_group(g, string(k))
        _ra_set_attr!(eg, "element", String(entry.element))
        _ra_set_attr!(eg, "beam", Int64(entry.beam))
        _ra_set_attr!(eg, "slot_count", Int64(length(entry.slots)))
        for (i, s) in enumerate(entry.slots)
            sg = HDF5.create_group(eg, String(s.slot))
            _ra_set_attr!(sg, "index", Int64(i))
            _ra_set_attr!(sg, "kind", String(s.kind))
            _ra_set_attr!(sg, "rng_id", UInt64(s.rng_id))
            _ra_set_attr!(sg, "digest", UInt64(s.digest))
            _ra_set_attr!(sg, "name", String(s.name))
            _ra_set_attr!(sg, "length", Int64(s.length))
            for (name, value) in pairs(col.nominal[i])
                _ra_set_attr!(sg, _RA_TM_NOMINAL_PREFIX * String(name), Float64(value))
            end
        end
        if series !== nothing
            labels = String[String(s.slot) for s in entry.slots]
            ncols = length(labels)
            d = HDF5.create_dataset(eg, "series", HDF5.datatype(Float64),
                                    HDF5.dataspace((0, ncols); max_dims=(-1, ncols));
                                    chunk=(256, ncols))
            _ra_set_attr!(d, "columns", labels)
            _ra_set_attr!(d, "first_turn", Int64(series[1]))
            _ra_set_attr!(d, "turns", Int64(series[2]))
        end
        # Element k complete: the cursor blesses it.
        _ra_set_attr!(g, _RA_TM_CURSOR, Int64(k))
    end
    return nothing
end

# The attribute prefix of a slot group's nominal parameters, the reserved
# subgroup name of an execution slot (D10) and the slot group's cursor, the
# three names the writer and the readers share.
const _RA_TM_NOMINAL_PREFIX = "nominal_"
const _RA_TM_STATE = "state"
const _RA_TM_CURSOR = "elements_valid_through"

"""
Build this execution's recorders over the `series` datasets the provenance
writer created for the ledger row `slot`: one `TurnModulationRecorder` per
beam that has a modulated element, in `art.turn_modulation_recorders`, each
element's buffer sized for `capacity` turns of its active columns up front
(`sizehint!`; before the 2026-10-16 fix batch the buffers grew by doubling,
about 580 bytes per turn averaged on the suite's fixture, U9-5 -- the
recording hook is allocation-free below the flush now). Called by
`prepare_run_artifact!` on rank 0 after `_ra_write_turn_modulation!` and
only when `record_turn_modulation` is on; nothing when `entries` is empty
(the option is inactive on a line with no modulated element). A dataset the
writer did not create is an error naming it: the two run in one prepare.
"""
function _ra_build_turn_modulation_recorders!(art::RunArtifact, file, slot::Int, entries, columns)
    empty!(art.turn_modulation_recorders)
    isempty(entries) && return nothing
    beams = Int[]
    for entry in entries
        Int(entry.beam) in beams || push!(beams, Int(entry.beam))
    end
    for beam in beams
        keys_b = String[]
        active_b = Vector{Int}[]
        buffers_b = Vector{Float64}[]
        for (k, entry) in enumerate(entries)
            Int(entry.beam) == beam || continue
            key = "turn_modulation/$(slot)/$(k)"
            haskey(file[key], "series") || error(
                "RunArtifact at $(art.path): $(key) has no series dataset although " *
                "record_turn_modulation is on; the provenance writer and the recorder " *
                "builder disagree")
            active = collect(Int, columns[k].active)
            push!(keys_b, key)
            push!(active_b, active)
            push!(buffers_b, sizehint!(Float64[], art.capacity * length(active)))
        end
        push!(art.turn_modulation_recorders,
              TurnModulationRecorder(file, art.capacity, beam, keys_b, active_b, buffers_b, 0, 0, art))
    end
    return nothing
end

"""
    _turn_modulation_sink(art, beam) -> Union{Nothing,TurnModulationRecorder}

The recorder the turn loop hands the recording hook for `beam`'s line, or
`nothing`: no artifact, the switch off, a non-root rank, or a line with no
modulated element. Resolved once per `execute!`, before the first turn.
"""
_turn_modulation_sink(::Nothing, beam::Integer) = nothing
function _turn_modulation_sink(art::RunArtifact, beam::Integer)
    for rec in art.turn_modulation_recorders
        rec.beam == beam && return rec
    end
    return nothing
end

"""
    _record_turn_draws!(rec::TurnModulationRecorder, draws::Tuple)

The recording hook's hand-over of one modulated element's draws (see
`src/elements/turn_modulated.jl`): the next element of this beam's provenance
in line order; its ACTIVE slots' values are appended to the element's buffer.
A modulated element the provenance did not list is an error naming the beam,
never an extra column.
"""
function _record_turn_draws!(rec::TurnModulationRecorder, draws::Tuple)
    k = rec.cursor + 1
    k <= length(rec.keys) || error(
        "the turn-modulation recorder of beam $(rec.beam) met modulated element $(k) " *
        "this turn but the provenance lists $(length(rec.keys)); the line and its " *
        "provenance disagree")
    rec.cursor = k
    buf = rec.buffers[k]
    for s in rec.active[k]
        push!(buf, Float64(draws[s]))
    end
    return nothing
end

"""The turn loop's per-turn protocol: nothing on `nothing`, the recorder's otherwise."""
_tm_begin_turn!(::Nothing) = nothing
_tm_begin_turn!(rec::TurnModulationRecorder) = (rec.cursor = 0; nothing)
_tm_end_turn!(::Nothing, turn::Integer) = nothing
function _tm_end_turn!(rec::TurnModulationRecorder, turn::Integer)
    if rec.cursor != length(rec.keys)
        # Drop this turn's partial values first, so what the crash path flushes
        # stays rectangular, then say what happened.
        for k in eachindex(rec.keys)
            resize!(rec.buffers[k], rec.rows * length(rec.active[k]))
        end
        met = rec.cursor
        rec.cursor = 0
        error("turn $(turn): the turn-modulation recorder of beam $(rec.beam) met $(met) " *
              "modulated element(s) but the provenance lists $(length(rec.keys)); the " *
              "turn's offsets are dropped, not written misaligned")
    end
    rec.rows += 1
    rec.rows >= rec.capacity && _ra_flush_turn_modulation!(rec)
    return nothing
end

"""
Append the pending COMPLETE turns of every element of `rec` to its `series`
dataset and flush the file: `rows` new rows per dataset, each buffer
turn-major, the batching the luminosity rows take (`capacity` turns per flush,
and the tail at finalize). Values beyond the complete rows belong to a turn
that did not finish -- the crash path's finalize, a run stopped between
`_tm_begin_turn!` and `_tm_end_turn!` -- and are dropped, never written as a
misaligned row; the dataset's row count after a crash is the number of turns
completed through the last flush, and the ledger's `current_turn` carries the
progress, as for every producer.
"""
function _ra_flush_turn_modulation!(rec::TurnModulationRecorder)
    for k in eachindex(rec.keys)
        ncols = length(rec.active[k])
        buf = rec.buffers[k]
        nvals = rec.rows * ncols
        length(buf) >= nvals || error(
            "the turn-modulation recorder of beam $(rec.beam) holds $(length(buf)) value(s) " *
            "for element $(k) where $(rec.rows) complete turn(s) of $(ncols) column(s) need " *
            "$(nvals)")
        if rec.rows > 0
            d = rec.file[rec.keys[k]]["series"]
            n = size(d, 1)
            HDF5.set_extent_dims(d, (n + rec.rows, ncols))
            d[(n + 1):(n + rec.rows), :] = permutedims(reshape(view(buf, 1:nvals), ncols, rec.rows))
        end
        empty!(buf)
    end
    if rec.rows > 0
        # Rows first, the ledger after, flushed together (the luminosity
        # channel's ordering): a crash in between leaves rows the ledger does
        # not yet claim, which is the conservative side.
        rec.owner === nothing || _ra_stamp_ledger!(rec.owner)
        HDF5.flush(rec.file)
    end
    rec.rows = 0
    return nothing
end

"""
Record one collision's luminosity for one turn. Rows land on THIS label's own
turn axis; nothing about other collisions' schedules is consulted, which is
the design's point.
"""
function push_luminosity!(art::RunArtifact, label::String, turn::Integer, value::Float64)
    _mp_is_root() || return nothing
    # Before the commit the channel may still hold rows at or beyond this
    # window's first turn: a row buffered now would land beyond stale rows,
    # the silent form of F-56. Refused by name (2026-10-19 fix batch).
    art.committed || error(
        "RunArtifact at $(art.path): a luminosity row for $(label) (turn $(turn)) arrived " *
        "before the window committed; commit_run_artifact! applies the replay rule after " *
        "the last refusal and before the first turn")
    t = get!(() -> Int64[], art.pending_turns, label)
    v = get!(() -> Float64[], art.pending_values, label)
    push!(t, Int64(turn))
    push!(v, value)
    length(t) >= art.capacity && _ra_flush_luminosity!(art, label)
    return nothing
end

"""
    _ra_stamp_ledger!(art)

Persist the `/execution` ledger's live-progress columns, `current_turn` and
`elapsed`, for this `execute!`'s row. Called by EVERY flush -- the luminosity
channel, the probe rows (moments, BPM), the turn-modulation series -- and by
finalize, so a reader of a running or killed file learns how far the run got
whatever channels it carries. Before the 2026-10-16 neighbour audit (leads
U5-1 and U4-1) only the luminosity flush and finalize stamped it, so a
weak-strong task without a strong beam, the crab-noise example's own shape,
showed the nothing-known sentinel after a kill with tens of thousands of rows
on file. `current_turn` is the turn being processed when the flush ran (both
loops assign it at the top of the turn, before any channel push); each
channel's own cursor (`rows_valid_through_turn`, a series' row count) says
where that channel stands, so within one turn the ledger may lead a channel
by one.
"""
function _ra_stamp_ledger!(art::RunArtifact)
    ex = art.file["execution"]
    ex["current_turn"][art.execution_slot] = art.current_turn
    ex["elapsed"][art.execution_slot] = (time_ns() - art.start_time_ns) / 1.0e9
    return nothing
end

function _ra_flush_luminosity!(art::RunArtifact, label::String)
    t = get(art.pending_turns, label, nothing)
    (t === nothing || isempty(t)) && return nothing
    v = art.pending_values[label]
    g = art.file["luminosity"][label]
    _ra_append_rows!(g["turns"], t)
    _ra_append_rows!(g["values"], v)
    # Rows first, cursor after, flushed together: a crash in between leaves
    # rows beyond the cursor, which the next open truncates -- conservative.
    _ra_set_attr!(g, "rows_valid_through_turn", t[end])
    _ra_stamp_ledger!(art)
    HDF5.flush(art.file)
    empty!(t)
    empty!(v)
    return nothing
end

"""
This rank's loss rows, in global particle order, gathered onto rank 0.

Returns `nothing` when the record keeps counters only, so the caller writes no
`/data`. The rows carry the GLOBAL particle id: the slot they came from is
this rank's, and the offset turns it back into the particle it names.
`gather=false` skips the gather (a collective) and returns this rank's own
rows: the strong-strong crash path, which runs INSIDE the execution scope
while an exception is in flight and the ranks may not agree on having thrown.
"""
function _ra_gathered_loss_rows(record, shard_offset::Integer; gather::Bool=true)
    record === nothing && return nothing
    record.slots === nothing && return nothing
    r = loss_records(record; offset=shard_offset)
    n = length(r.particle_id)
    rows = Matrix{Float64}(undef, n, length(LOSS_RECORD_COLUMNS))
    for (j, col) in enumerate(LOSS_RECORD_COLUMNS)
        rows[:, j] = Float64.(getproperty(r, Symbol(col)))
    end
    return gather ? _mp_gather_rows(rows) : rows
end

# The group a loss record is written into. A `TrackingTask` (one beam) owns
# `/losses` itself, as it always has; a `StrongStrongTask` (2026-10-19, unit R)
# writes one subgroup per beam whose line carries an aperture,
# `/losses/beam_<i>`, each in the one-beam layout, so a beam's group is
# field-for-field what the TrackingTask writes for the same beam. Either way
# the group written is REPLACED whole (the idempotent rewrite rule below); a
# one-beam `/losses` met by a per-beam write -- a file another task kind wrote
# before -- is replaced too rather than nested into.
function _ra_losses_group!(file, ::Nothing)
    haskey(file, "losses") && HDF5.delete_object(file, "losses")
    return HDF5.create_group(file, "losses")
end
function _ra_losses_group!(file, beam::Integer)
    haskey(file, "losses") && haskey(file["losses"], "aperture_names") &&
        HDF5.delete_object(file, "losses")
    parent = haskey(file, "losses") ? file["losses"] : HDF5.create_group(file, "losses")
    name = "beam_$(beam)"
    haskey(parent, name) && HDF5.delete_object(parent, name)
    return HDF5.create_group(parent, name)
end

# The group of a continued file whose earlier rows this window's write merges
# under the replay rule (F-57; `_ra_write_losses!`): `/losses` itself for a
# one-beam writer when it is the one-beam layout, `/losses/beam_<i>` for beam
# `i` of a `StrongStrongTask` when the file holds it; `nothing` when there is
# nothing to merge (a fresh file, a first window for this beam, or the other
# task kind's layout, which the prepare refused to continue --
# `_ra_check_loss_apertures` -- and which the writer replaces whole).
function _ra_existing_losses_group(file, ::Nothing)
    haskey(file, "losses") || return nothing
    g = file["losses"]
    return haskey(g, "aperture_names") ? g : nothing
end
function _ra_existing_losses_group(file, beam::Integer)
    haskey(file, "losses") || return nothing
    parent = file["losses"]
    haskey(parent, "aperture_names") && return nothing
    name = "beam_$(beam)"
    return haskey(parent, name) ? parent[name] : nothing
end

"""
The rows of a continued `/losses` group that survive this window: `turn`
below `first_turn` (the replay rule) and `(particle_id, turn)` not among this
record's rows `gathered` -- the same beam continuing in one process already
carries its earlier rows in its cumulative record, so they are kept once.
Both matrices are in the `LOSS_RECORD_COLUMNS` layout; `gathered` is `nothing`
for a counters-only record, which keeps every row below `first_turn`.
"""
function _ra_retained_loss_rows(data0::AbstractMatrix, gathered, first_turn::Int64)
    jid = findfirst(==("particle_id"), LOSS_RECORD_COLUMNS)
    jturn = findfirst(==("turn"), LOSS_RECORD_COLUMNS)
    own = Set{Tuple{Int64,Int64}}()
    if gathered !== nothing
        for i in 1:size(gathered, 1)
            push!(own, (Int64(gathered[i, jid]), Int64(gathered[i, jturn])))
        end
    end
    keep = Int[]
    for i in 1:size(data0, 1)
        t = data0[i, jturn]
        t < first_turn || continue
        (Int64(data0[i, jid]), Int64(t)) in own && continue
        push!(keep, i)
    end
    return data0[keep, :]
end

"""
Write the artifact's `/losses` group for this `execute!` -- the
`write_loss_record` layout (per-loss rows, aperture names/counts/arc
positions, and the reconciliation summary as attributes when the caller has
one) -- under the replay idempotence rule every other group follows
(2026-10-19 fix batch, F-57; before it the group was rewritten whole from the
current record, so a new task continuing a file, a process restart, emptied
it). On a continued file the group's earlier rows are kept where their `turn`
is below this window's first turn and not already in this record
(`_ra_retained_loss_rows`: the same beam continuing in one process carries
its earlier rows in its cumulative record, so they are kept once), rows at or
beyond it are dropped as replayed, and this record's rows -- every one of
them; the record is the beam's and cumulative -- are appended, in that order;
`aperture_counts` is this record's attribution plus that of the kept rows,
so `sum(aperture_counts) == record_count` whenever rows are logged. The
`summary_*` attributes are the writing `execute!`'s beam (`loss_summary`: its
particles, live, dead, logged, unattributed), not a sum over windows: on a
fresh file `sum(aperture_counts) == summary_logged` as before, on a continued
file the counts exceed the beam's `logged` by the earlier windows' retained
losses. A continued group that logged no rows (a counters-only record)
carries its counts whole -- there is no turn to replay by -- and says so with
a warning. The group is still written whole, deleted and recreated from the
merged rows. A window that never committed (`commit_run_artifact!`: refused
before its first turn) writes nothing and leaves the group as found; one that
ran turns without committing is an error. A task with no loss record (no
aperture in the line) writes nothing; the aperture names of a continued group
were matched against this task's at prepare (`_ra_check_loss_apertures`), so
a mismatch here is an internal error, not a refusal.
`beam = i` writes beam `i` of a `StrongStrongTask` into `/losses/beam_i`
(`_ra_losses_group!`) and merges that beam's earlier rows from the same
subgroup (`_ra_existing_losses_group`); `gather = false` writes this rank's
rows without the gather collective (the strong-strong crash path, see
`_ra_gathered_loss_rows`).
"""
function _ra_write_losses!(art::RunArtifact, record, s_positions, summary,
                           shard_offset::Integer=0; folded::Bool=false,
                           beam::Union{Nothing,Integer}=nothing, gather::Bool=true)
    # Every rank builds and gathers its rows -- the gather is a collective, so
    # a rank that returned early would hang the rest -- and only rank 0, which
    # holds the file, writes them.
    gathered = _ra_gathered_loss_rows(record, shard_offset; gather=gather)
    art.file === nothing && return nothing
    record === nothing && return nothing
    if !art.committed
        # Refused before its first turn: nothing ran, the group stays as found.
        # Turns tracked without the commit are an ordering bug, said by name.
        art.current_turn >= art.first_turn && error(
            "RunArtifact at $(art.path): the window starting at turn $(art.first_turn) reached " *
            "turn $(art.current_turn) without commit_run_artifact!, so /losses cannot be " *
            "written under the replay rule")
        return nothing
    end
    names = aperture_names(record)
    # The GLOBAL attribution, not this rank's. `loss_counts(record)` is the
    # rank-local `LossRecord.counts`, bumped only by this rank's own kills, and
    # every other value in this group is the whole beam's: `data` is
    # `_mp_gather_rows`ed over all ranks and the `summary_*` attributes come from
    # the all-summed counts. Writing the local array here made a reader
    # reconciling `sum(aperture_counts)` against `summary_dead` -- which is
    # precisely what `loss_summary`'s docstring tells them to do -- see a
    # phantom unattributed gap that grew with the rank count, silently
    # (2026-09-06 neighbour audit). `summary.by_aperture` is the same array
    # all-summed by `_global_loss_summary`, index-aligned with `aperture_names`
    # because both derive from the same record, and identical to the local one
    # at a single rank.
    counts = summary === nothing ? Int.(loss_counts(record)) : collect(Int, summary.by_aperture)
    # The replay rule for the single group (F-57): the earlier windows' rows of
    # a continued file below this window's first turn, less those this
    # cumulative record carries itself, keep their place ahead of this record's.
    kept = zeros(Float64, 0, length(LOSS_RECORD_COLUMNS))
    g0 = _ra_existing_losses_group(art.file, beam)
    if art.continued && g0 !== nothing
        stored = String.(read(g0["aperture_names"]))
        stored == names || error(
            "RunArtifact at $(art.path): the /losses group names the apertures $(stored) but " *
            "this record's are $(names); prepare_run_artifact! validates this for every task " *
            "that records losses (aperture_names)")
        if haskey(g0, "data")
            cols0 = String.(read(g0["column_names"]))
            cols0 == LOSS_RECORD_COLUMNS || error(
                "RunArtifact at $(art.path): the /losses group carries columns $(cols0), not " *
                "$(LOSS_RECORD_COLUMNS); not a group this writer can continue")
            kept = _ra_retained_loss_rows(read(g0["data"]), gathered, art.first_turn)
        else
            stored_counts = Int.(read(g0["aperture_counts"]))
            length(stored_counts) == length(counts) && (counts .+= stored_counts)
            @warn "the continued run artifact's /losses group logged no per-loss rows, so the " *
                  "replay rule cannot apply to its earlier windows: their per-aperture counts " *
                  "are carried whole and added to this window's, and a replayed window counts " *
                  "twice" path = art.path
        end
    end
    jelem = findfirst(==("element_id"), LOSS_RECORD_COLUMNS)
    for i in 1:size(kept, 1)
        e = Int(kept[i, jelem])
        1 <= e <= length(counts) && (counts[e] += 1)
    end
    merged = gathered === nothing ? kept : vcat(kept, gathered)
    g = _ra_losses_group!(art.file, beam)
    g["aperture_names"] = names
    g["aperture_counts"] = counts
    s_positions === nothing || (g["aperture_s"] = collect(Float64, s_positions))
    if gathered !== nothing || size(merged, 1) > 0
        g["data"] = merged
        g["column_names"] = collect(String, LOSS_RECORD_COLUMNS)
        _ra_set_attr!(g, "record_count", Int64(size(merged, 1)))
    end
    if summary !== nothing
        _ra_set_attr!(g, "summary_particles", Int64(summary.particles))
        _ra_set_attr!(g, "summary_live", Int64(summary.live))
        _ra_set_attr!(g, "summary_dead", Int64(summary.dead))
        _ra_set_attr!(g, "summary_unattributed", Int64(summary.unattributed))
        # `logged` is what makes the group SELF-CHECKING: `sum(aperture_counts)
        # == summary_logged` is the reconciliation `loss_summary`'s docstring
        # tells a reader to make, and until 2026-09-07 the file carried one side
        # of it and not the other. `write_loss_record` has always written it
        # (src/elements/aperture.jl); this group had not.
        _ra_set_attr!(g, "summary_logged", Int64(summary.logged))
        # WHOSE numbers these are, said in the file (2026-09-07). The success
        # path folds this group across the ranks; the CRASH path deliberately
        # does not -- it runs outside the execution-policy scope, where every
        # collective is its passthrough, precisely so a rank-local failure
        # flushes what this rank saw instead of deadlocking against peers that
        # may not have thrown (see the catch block in `_execute!`). Both are
        # right, and they are different numbers: a crashed four-rank run wrote
        # `dead=1` where a successful one writes `dead=4`, with nothing in the
        # file to tell them apart. The 2026-09-06 neighbour audit priced that
        # as "write this rank's rows, LABELLED AS SUCH"; this is the label.
        # `Int64`, like every other attribute here: HDF5 has no native bool and
        # a round-tripped `Bool` would depend on HDF5.jl's mapping.
        _ra_set_attr!(g, "summary_folded", Int64(folded))
    end
    HDF5.flush(art.file)
    return nothing
end

"""
Flush every pending group (the luminosity channels, the turn-modulation
series), stamp this execution's elapsed time, close, and release the sidecar
lock -- after the close, so the next writer to take the lock finds the file
released. Every path that closes the artifact runs through here: the success
paths of both tasks, their crash paths, and the strong-strong task's
observer-prepare refusal (U5-2); the one close that does not, the prepare's
own refusal, releases the lock itself.
"""
function finalize_run_artifact!(art::RunArtifact)
    art.file === nothing && return nothing
    try
        # A window that tracked turns without `commit_run_artifact!` wrote no
        # row (the pushes refuse) and never applied the replay rule: the error
        # of a success path, a warning beside the error that stopped a crashed
        # run. A window refused before its first turn is not this (nothing ran).
        (!art.committed && art.current_turn >= art.first_turn) && error(
            "RunArtifact at $(art.path): the window starting at turn $(art.first_turn) reached " *
            "turn $(art.current_turn) without commit_run_artifact!; its groups were never replayed")
        for label in collect(keys(art.pending_turns))
            _ra_flush_luminosity!(art, label)
        end
        for rec in art.turn_modulation_recorders
            _ra_flush_turn_modulation!(rec)
        end
        _ra_stamp_ledger!(art)
        HDF5.flush(art.file)
    finally
        close(art.file)
        art.file = nothing
        empty!(art.turn_modulation_recorders)
        art.committed = false
        empty!(art.pending_probes)
        _ra_release_lock!(art)
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Probes as views (migration step 2): moments, snapshots and BPM readings are
# ROW-MATRIX groups -- 2-D extendable `data` whose column 1 is the absolute
# turn, plus `column_names` -- under /moments, /snapshot and /bpm, keyed by
# the probe's NAME (the design's identity rule; unique within one execute!).
# One machinery serves all three: the products differ only in their columns
# and their rows-per-fire.
# ---------------------------------------------------------------------------

"""
The artifact the CURRENT task execution carries, or `nothing`. Bound around
observer preparation by the task (`Base.ScopedValues`, the diagnostics-sink
precedent), so line-placed probes -- which have no task handle -- can join
the artifact at prepare time.
"""
const _ACTIVE_RUN_ARTIFACT = Base.ScopedValues.ScopedValue{Any}(nothing)
active_run_artifact() = _ACTIVE_RUN_ARTIFACT[]

function _ra_truncate_probe!(g, keep_through::Int64)
    d = g["data"]
    nrows = size(d, 1)
    turns = nrows == 0 ? Float64[] : d[1:nrows, 1]
    keep = searchsortedlast(turns, Float64(keep_through))
    keep < nrows && HDF5.set_extent_dims(d, (keep, size(d, 2)))
    _ra_set_attr!(g, "rows_valid_through_turn",
                  Int64(keep == 0 ? typemin(Int32) : round(Int64, turns[keep])))
    return nothing
end

# The prepare walk's observer -> arc-position map (one spec traversal, the
# U11-1 walker; built in BeamObservers.jl where ScheduledObserver exists).
# nothing outside a prepare, or for a task-hook probe with no line position.
const _ACTIVE_PROBE_S_MAP = Base.ScopedValues.ScopedValue{Any}(nothing)
function _active_probe_s(observer)
    m = _ACTIVE_PROBE_S_MAP[]
    m === nothing && return nothing
    return get(m, observer, nothing)
end

"""
Bind one probe to the open artifact: validate it -- a name, one of the table's
named kinds, unique within this `execute!`, and, when its group exists, a
stored column layout equal to `colnames` -- and register it for the commit,
which creates or continues the group and applies the crash-truncation and
replay rules (`commit_run_artifact!`, `_ra_commit_probe!`). Nothing is written
here (2026-10-19 fix batch, F-58: binding truncated one group at a time, so a
later probe's refusal left the earlier probes cut back to `first_turn - 1`). A
bind after the commit is refused by name. Returns the group key the probe
pushes rows through.
"""
function _ra_bind_probe!(art::RunArtifact, kind::String, name::String,
                         colnames::Vector{String}, first_turn::Int;
                         s::Union{Nothing,Real}=nothing)
    isempty(name) && throw(ArgumentError("a probe bound to the artifact needs a name"))
    # A probe binds under one of the table's named kinds and nothing else, so
    # the groups a run writes are the groups the readers know (S4-8).
    Symbol(kind) in _RA_NAMED_KINDS || throw(ArgumentError(
        "a probe cannot bind under /$(kind): the run artifact's named product groups are " *
        join(string.(_RA_NAMED_KINDS), ", ") * " (_RA_GROUPS)"))
    key = kind * "/" * name
    # Non-root ranks hold no file, so a probe binds to a name and writes
    # nothing; its observer still computes, because the computation is a
    # collective.
    _mp_is_root() || return key
    art.file === nothing && throw(ArgumentError(
        "a named probe needs an open run artifact; give the task artifact=..."))
    art.committed && throw(ArgumentError(
        "the probe /$(key) binds after the window committed: every probe binds before " *
        "commit_run_artifact!, which applies the replay rule to all of them at once"))
    key in art.probe_names && throw(ArgumentError(
        "duplicate probe name $(repr(name)) under /$(kind): names are the " *
        "artifact's group identities and must be unique within a task"))
    f = art.file
    if haskey(f, kind) && haskey(f[kind], name)
        stored = read(f[kind][name]["column_names"])
        stored == colnames || throw(ArgumentError(
            "the probe group /$(key) at $(art.path) carries columns $(stored), " *
            "not $(colnames); use a different name or path"))
    end
    push!(art.probe_names, key)
    push!(art.pending_probes,
          PendingProbeBind(key, kind, name, copy(colnames), Int64(first_turn),
                           s === nothing ? nothing : Float64(s)))
    return key
end

"""
Create or continue one probe group at the commit (the body `_ra_bind_probe!`
ran at bind time before the 2026-10-19 fix batch): an existing group is
truncated to `min(cursor, first_turn - 1)` by `_ra_truncate_probe!` -- the
torn tail beyond its cursor and the replayed rows, one bound -- and a new one
is created with its `data` matrix, `column_names`, `name` and the
nothing-known cursor. The design's `attrs: name, s` either way: a line-placed
probe records WHERE in the line it sat (arc length at its placement), so the
file answers it without the script that made it; stamped on continue too --
idempotent for the same lattice, corrective if the probe moved.
"""
function _ra_commit_probe!(f, pending::PendingProbeBind)
    parent = haskey(f, pending.kind) ? f[pending.kind] : HDF5.create_group(f, pending.kind)
    if haskey(parent, pending.name)
        g = parent[pending.name]
        cursor = Int64(_ra_get_attr(g, "rows_valid_through_turn",
                                    Int64(typemin(Int32))))
        _ra_truncate_probe!(g, min(cursor, pending.first_turn - 1))
    else
        g = HDF5.create_group(parent, pending.name)
        ncols = length(pending.colnames)
        HDF5.create_dataset(g, "data", HDF5.datatype(Float64),
            HDF5.dataspace((0, ncols); max_dims=(-1, ncols)); chunk=(256, ncols))
        g["column_names"] = pending.colnames
        _ra_set_attr!(g, "name", pending.name)
        _ra_set_attr!(g, "rows_valid_through_turn", Int64(typemin(Int32)))
    end
    pending.s === nothing || _ra_set_attr!(g, "s", pending.s)
    return nothing
end

"""
Append a block of probe rows (column 1 is the absolute turn) and advance the
group's cursor to the block's last turn, flushed together -- the same
rows-then-cursor ordering the luminosity channel uses, so a crash between
them truncates conservatively on the next open.
"""
function _ra_push_probe_rows!(art::RunArtifact, key::String, rows::AbstractMatrix)
    _mp_is_root() || return nothing
    size(rows, 1) == 0 && return nothing
    # Loud, named failure instead of getindex(::Nothing): rows arriving after
    # finalize mean a flush-ordering bug (observers must flush BEFORE the
    # artifact closes -- the 2026-08-18 strong-strong finalize-order lesson).
    art.file === nothing && error(
        "RunArtifact at $(art.path) is closed but probe rows for $(key) " *
        "are still arriving: observer flushes must run before " *
        "finalize_run_artifact!")
    # The group exists and is replayed only from the commit on (F-58).
    art.committed || error(
        "RunArtifact at $(art.path): probe rows for $(key) arrived before the window " *
        "committed; commit_run_artifact! applies the replay rule after the last refusal " *
        "and before the first turn")
    g = art.file[key]
    d = g["data"]
    n = size(d, 1)
    HDF5.set_extent_dims(d, (n + size(rows, 1), size(d, 2)))
    d[(n + 1):(n + size(rows, 1)), :] = Float64.(rows)
    _ra_set_attr!(g, "rows_valid_through_turn", Int64(round(Int64, rows[end, 1])))
    # The ledger after the rows and the cursor, flushed together (U5-1).
    _ra_stamp_ledger!(art)
    HDF5.flush(art.file)
    return nothing
end


# ---------------------------------------------------------------------------
# Readers (step 4): the convenience surface for the one-file-per-task
# artifact, matching the ergonomics the standalone files had. Moment groups
# additionally read through the full MomentOutput machinery
# (`MomentOutput(path; name="IP6")` -- read()/read(out, item)/
# column_names work as they always did).
# ---------------------------------------------------------------------------

"""
    _ra_open(path) -> HDF5.File
    _ra_open(f, path)

Open an artifact for READING, lock-aware (2026-10-16, S5-2). A reader never
takes the sidecar lock: a second process may read while a writer holds the
file and sees the last flushed state. When a live lock exists for `path`, the
reader says so once per writer and process -- an `@info` naming the writer's
line (host, pid, since when, task) and that the rows are valid through each
group's `rows_valid_through_turn` cursor and the ledger's `current_turn` -- and
an open that fails under the lock (a flush landing) is retried once before the
failure propagates with the lock information in it. Only the open is retried
and rewrapped, never `f`: a torn group `f` refuses keeps its own error. Every
public reader goes through here -- `TaskOutput`, `turn_modulation_provenance`
and the `MomentOutput` HDF5 reads -- so a standalone (pre-artifact) moment
file, which never has a lock, reads as before.
"""
function _ra_open(path)
    p = String(path)
    held = _ra_lock_info(p)
    if held !== nothing
        @info "a live Octopus writer holds the run artifact's lock, so the file is being " *
              "written: its rows are valid through each group's rows_valid_through_turn " *
              "cursor and the ledger's current_turn, and a read may fail while a flush " *
              "lands" path = p writer = held maxlog = 1 _id = Symbol("run_artifact_lock_", hash((p, held)))
    end
    try
        return HDF5.h5open(p, "r")
    catch
        held === nothing && rethrow()
        try
            return HDF5.h5open(p, "r")
        catch
            error("reading the run artifact at $(p) failed twice while a live Octopus writer " *
                  "holds its lock ($(held)): the file is being written and the open landed " *
                  "on a flush both times; read it again, or wait for the writer to finish")
        end
    end
end
function _ra_open(f::Function, path)
    h = _ra_open(path)
    try
        return f(h)
    finally
        close(h)
    end
end

"""
    TaskOutput(path)

Lightweight handle for reading a task's run artifact -- the one-HDF5-per-task
output (`docs/design/run_artifact.md`). One `read` serves everything, from
discovery to data, the `MomentOutput` ergonomics generalized:

```julia
out = TaskOutput("run.h5")
read(out)                                    # recursive contents: kind => name =>
                                             #   (columns, rows[, s]) -- metadata only
read(out, :luminosity)                       # Dict name => (turn=..., value=...)
read(out, :luminosity; name="ip")            # one collision's series
read(out, :moments; name="IP6")              # columns as a NamedTuple
read(out, :moments; name="IP6", column=Moment(; x=1))   # one column
read(out, :moments; name="IP6", orders=1:2)  # a moment selection
read(out, :bpm; name="BPM_07", column=:x)
read(out, :snapshot; name="inj", turn=2)     # one fired block
read(out, :losses)                           # rows + apertures + summary
read(out, :execution)                        # one ledger row per execute!
read(out, :turn_modulation)                  # modulation provenance per execute!
read(out, :all)                              # every product, nested by kind
```

Moment groups additionally read through the full `MomentOutput` machinery
(`MomentOutput(path; name="IP6")` -- `read(out)`/`read(out, item)`/
`column_names` work as they always did).

Reading never takes the artifact's sidecar lock (`<path>.lock`, held by a
live writer; see [`RunArtifact`](@ref)): a file another process is writing
reads as of its last flush, with its rows valid through each group's
`rows_valid_through_turn` cursor and the ledger's `current_turn`. When such a
lock exists, every reader here says so once per writer and process -- an
`@info` naming the lock's line (host, pid, since when, task) -- and an open
that fails while a flush lands is retried once before the failure propagates
with the lock information in it (2026-10-16).
"""
struct TaskOutput
    path::String
end
TaskOutput(path::AbstractString) = TaskOutput(String(path))

"""The table of contents: each product kind present, with its group names."""
function _ra_contents(path::AbstractString)
    _ra_open(path) do f
        out = Dict{String,Vector{String}}()
        for kind in keys(f)
            obj = f[kind]
            # Named-group kinds list their probe/channel names; single
            # products (losses, execution) are present with no names.
            subs = obj isa HDF5.Group ?
                [String(k) for k in keys(obj) if obj[k] isa HDF5.Group] : String[]
            out[String(kind)] = sort(subs)
        end
        out
    end
end

# The artifact's product groups, ONE table: every top-level group a producer
# writes, with its shape -- `:named` (a group of named groups: the luminosity
# channels and the three probe kinds, which `_ra_bind_probe!` refuses to bind
# under any other name), `:single` (one group: the losses, the ledger; a
# strong-strong artifact nests one `beam_<i>` subgroup per beam inside the
# single losses group, `_ra_losses_group!`, which its readers return keyed by
# beam) and
# `:slotted` (one group per execution slot: the provenance). `_RA_KINDS` and
# `_RA_NAMED_KINDS` derive from it, and the suite pins the table against a run
# of every producer (2026-10-16 neighbour audit, S4-8: the hand list was
# correct and had no tripwire).
const _RA_GROUPS = (luminosity=:named, moments=:named, snapshot=:named, bpm=:named,
                    losses=:single, execution=:single, turn_modulation=:slotted)
const _RA_NAMED_KINDS = Tuple(k for (k, shape) in pairs(_RA_GROUPS) if shape === :named)
const _RA_KINDS = keys(_RA_GROUPS)

function _ra_require_group(f, out::TaskOutput, kind::Symbol)
    haskey(f, String(kind)) || throw(ArgumentError(
        "$(out.path) carries no $(kind); present: " *
        join(sort(collect(keys(_ra_contents(out.path)))), ", ")))
    return f[String(kind)]
end

function _ra_named_group(g, out::TaskOutput, kind::Symbol, name)
    haskey(g, String(name)) || throw(ArgumentError(
        "$(out.path) has no $(kind) group named $(repr(String(name))); " *
        "present: " * join(_ra_contents(out.path)[String(kind)], ", ")))
    return g[String(name)]
end

# Reader fields are the per-row convention (turn, value) -- the quantity is
# named by the KIND, matching the probes' singular column names; the FILE
# datasets keep their layout names (turns/values), so existing artifacts
# continue and append untouched (owner direction, 2026-08-19).
_ra_lum_series(g) = (turn=read(g["turns"]), value=read(g["values"]))

function _ra_probe_columns(g)
    names = String.(read(g["column_names"]))
    data = read(g["data"])
    # `s` is the probe's arc position (the design's attrs: name, s), nothing
    # for task-hook probes and files from before the attribute existed --
    # the read_losses mixed scalars-and-columns precedent.
    (; :s => _ra_get_attr(g, "s", nothing),
       (Symbol(n) => vec(data[:, i]) for (i, n) in pairs(names))...)
end

_ra_column_key(column::Symbol) = column
_ra_column_key(column::AbstractString) = Symbol(column)
# The Moment method lives in BeamObservers.jl, where Moment is defined
# (that file loads after this one).

function _ra_select_column(rows::NamedTuple, column, what)
    key = _ra_column_key(column)
    haskey(rows, key) || throw(ArgumentError(
        "$(what) has no column $(repr(key)); present: " *
        join(string.(keys(rows)), ", ")))
    return rows[key]
end

# `g` is the /losses group, handed over by `_ra_require_group` (U5-7). A
# `TrackingTask` wrote the one-beam layout into the group itself; a
# `StrongStrongTask` wrote one subgroup per beam whose line carries an
# aperture (`_ra_losses_group!`), returned here keyed by beam (`beam_1`,
# `beam_2`), each entry the one-beam shape.
function _ra_losses(g)
    if !haskey(g, "aperture_names")
        beams = sort([String(k) for k in keys(g) if g[k] isa HDF5.Group])
        return (; (Symbol(b) => _ra_losses(g[b]) for b in beams)...)
    end
    a = HDF5.attributes(g)
    rows = if haskey(g, "data")
        names = String.(read(g["column_names"]))
        data = read(g["data"])
        (; (Symbol(n) => vec(data[:, i]) for (i, n) in pairs(names))...)
    else
        (; (Symbol(n) => Float64[] for n in LOSS_RECORD_COLUMNS)...)
    end
    summary = haskey(a, "summary_dead") ?
        (particles=Int(read(a["summary_particles"])),
         live=Int(read(a["summary_live"])),
         dead=Int(read(a["summary_dead"])),
         # `nothing` for a file written before 2026-09-07, the same shape this
         # reader already uses for an absent `aperture_s`.
         logged=haskey(a, "summary_logged") ? Int(read(a["summary_logged"])) : nothing,
         # `true` when this group was folded across the ranks, `false` when it
         # is one rank's (a crashed divided run). `nothing` for a file written
         # before 2026-09-07, which cannot say.
         folded=haskey(a, "summary_folded") ? read(a["summary_folded"]) != 0 : nothing,
         unattributed=Int(read(a["summary_unattributed"]))) : nothing
    merge(rows,
          (aperture_names=String.(read(g["aperture_names"])),
           aperture_counts=Int.(read(g["aperture_counts"])),
           aperture_s=haskey(g, "aperture_s") ? read(g["aperture_s"]) : nothing,
           summary=summary))
end

# The table-of-contents entry of a /losses group (`read(::TaskOutput)`): the
# one-beam layout's columns, row count and aperture names, or, for a
# strong-strong artifact, that entry per beam subgroup keyed by beam.
function _ra_losses_toc(obj)
    haskey(obj, "aperture_names") ||
        return (; (Symbol(String(k)) => _ra_losses_toc(obj[k])
                   for k in keys(obj) if obj[k] isa HDF5.Group)...)
    return (columns=haskey(obj, "column_names") ?
                String.(read(obj["column_names"])) : String[],
            rows=haskey(obj, "data") ? size(obj["data"], 1) : 0,
            apertures=String.(read(obj["aperture_names"])))
end

# `ex` is the /execution group, handed over by `_ra_require_group` (U5-7). One
# field per column of `_RA_LEDGER_COLUMNS`, in the table's order; a column the
# file lacks -- `rng_seed` and `rng_method` on a file written before 2026-10-16
# -- reads as `nothing`, the `/losses` reader's posture for its later-added
# attributes (reading an old file stays possible; only continuing one refuses).
_ra_execution(ex) =
    (; (Symbol(name) => (haskey(ex, name) ? read(ex[name]) : nothing)
        for (name, _) in _RA_LEDGER_COLUMNS)...)

"""
Refuse a `/turn_modulation/<slot>` group that already exists when `entries`
is non-empty: `slot` is the ledger row `prepare_run_artifact!` is about to
append, so an existing group means the file's ledger and its provenance
disagree. An unmodulated execute! (`entries` empty) writes no group and
claims none, so a stranger group does not refuse it. The one source of the
refusal: `prepare_run_artifact!` runs it BEFORE the ledger append (so a
refused call leaves the ledger unchanged, U5-3) and the writer runs it again.
"""
function _ra_check_turn_modulation_slot(file, path::String, slot::Int, entries)
    isempty(entries) && return nothing
    haskey(file, "turn_modulation") || return nothing
    haskey(file["turn_modulation"], string(slot)) && throw(ArgumentError(
        "RunArtifact at $(path): /turn_modulation/$(slot) already exists although " *
        "no execute! has recorded execution ledger row $(slot) yet; the file's " *
        "ledger and provenance disagree. Use a new path."))
    return nothing
end

"""
An attribute of a provenance group read WITHOUT a default: a group lacking it
is TORN, refused by an `ArgumentError` naming the group and the attribute. One
message shape for every attribute the reader needs -- the counts through
`_ra_tm_count`, the eight others (`index`, `kind`, `rng_id`, `digest`,
`name`, `length` on a slot group; `element`, `beam` on an element group) and
the series dataset's three (`columns`, `first_turn`, `turns`) --
where a bare `attributes(g)[name]` surfaced `KeyError: key "index" not found`,
naming the attribute but not the group (2026-10-13 neighbour audit, U5-1).
"""
function _ra_tm_attr(g, name::String, where::String)
    a = HDF5.attributes(g)
    haskey(a, name) || throw(ArgumentError(
        "$(where) is torn: the $(name) attribute is missing"))
    return read(a[name])
end

"""A count attribute read WITHOUT a default: a group lacking it is torn."""
_ra_tm_count(g, name::String, where::String) = Int(_ra_tm_attr(g, name, where))

"""
The nominal parameters of a slot group as a NamedTuple, from its `nominal_*`
attributes in name order (`(phase, strengthX, strengthY)` on a crab cavity
slot, `(phase, strength)` on an RF cavity slot), or `nothing` when the group
carries none -- a file written before the nominals existed (2026-10-15), the
posture of the `/losses` reader for its later-added attributes. A group whose
element recorded a `series` must carry them: `_ra_turn_modulation` refuses that
combination as torn.
"""
function _ra_tm_nominal(sg)
    a = HDF5.attributes(sg)
    names = sort!([String(n) for n in keys(a) if startswith(String(n), _RA_TM_NOMINAL_PREFIX)])
    isempty(names) && return nothing
    offset = length(_RA_TM_NOMINAL_PREFIX)
    return (; (Symbol(n[(offset + 1):end]) => Float64(read(a[n])) for n in names)...)
end

"""
The recorded `series` of an element group as `(columns, first_turn, turns)`:
one `Vector{Float64}` per column in the order of `labels` (the element's slot
labels by `index`) and the window the dataset's two attributes declare; or
`nothing` when the element recorded none (the run had `record_turn_modulation`
off, or predates it). With `data=false` (the table of contents) the dataset is
not read: the recorded row count stands in for each column. Torn by name: a
missing `columns`, `first_turn` or `turns` attribute, a `columns` attribute
that does not name the slot groups in index order, or a data width other than
the column count. The ROW COUNT is authoritative for how many turns were
recorded: a dataset with fewer rows than its `turns` attribute is a run
stopped before its window completed (killed, or interrupted between two
flushes), read as it stands -- never padded, never refused -- with one
warning naming the dataset (review F2, 2026-10-15; before, it read back
silently).
"""
function _ra_tm_series(eg, where_e::String, labels::Vector{String}, data::Bool)
    haskey(eg, "series") || return nothing
    d = eg["series"]
    where_d = where_e * "/series"
    columns = String.(_ra_tm_attr(d, "columns", where_d))
    first_turn = Int(_ra_tm_attr(d, "first_turn", where_d))
    turns = Int(_ra_tm_attr(d, "turns", where_d))
    columns == labels || throw(ArgumentError(
        "$(where_d) is torn: its columns $(columns) do not name the slot groups " *
        "$(labels) in index order"))
    nrows, ncols = size(d)
    ncols == length(columns) || throw(ArgumentError(
        "$(where_d) is torn: $(ncols) data column(s) for $(length(columns)) labelled column(s)"))
    nrows < turns && @warn(
        "$(where_d) holds $(nrows) recorded turn(s) of the $(turns) its turns attribute " *
        "declares (first_turn $(first_turn)): the run was stopped before its window " *
        "completed; the rows are read as they stand and the row count is authoritative")
    # The other side (2026-10-16 neighbour audit, U5-10): more rows than the
    # window declares is not a run this writer produced; read as they stand,
    # said out loud.
    nrows > turns && @warn(
        "$(where_d) holds $(nrows) recorded turn(s) but its turns attribute declares " *
        "$(turns) (first_turn $(first_turn)): more rows than the window planned, which " *
        "no run of this writer produces; the rows are read as they stand")
    data || return (columns=fill(nrows, ncols), first_turn=first_turn, turns=turns)
    block = nrows == 0 ? zeros(Float64, 0, ncols) : read(d)
    return (columns=[Vector{Float64}(block[:, j]) for j in 1:ncols],
            first_turn=first_turn, turns=turns)
end

"""
Read a present `/turn_modulation` group: one entry per execution slot that
recorded modulation, in ledger order, in the shape `turn_modulation_provenance`
documents -- each slot entry carrying its `nominal` and its `series`, the
latter the recorded column (or the row count with `data=false`, the table of
contents' metadata-only read) or `nothing` when the run did not record; each
execution entry carrying `state = nothing`, the reserved checkpoint group of
docs/design/turn_modulation_record.md D10, which nothing writes today and
which the element count skips. Every count is checked against the
subgroups present and every attribute is read without a default; a mismatch,
a missing count or a missing attribute is a TORN group, refused by an
`ArgumentError` naming the group (and the attribute) rather than read short.

A PARTIAL slot is not torn (owner decision 2026-10-16, the stage 3-4 audit's
U5-2): its cursor `elements_valid_through` is behind its `element_count`,
the artefact of a writer stopped by an HDF5 error between creating the group
and completing its last element. It is read as far as the cursor -- the
complete element groups, in order -- with one warning naming the slot and
the counts; the half-written group beyond the cursor (at most one) is
skipped, never read as torn, and nothing rolls it back (`append=true`
refuses such a file by name instead). A slot written before the cursor
existed (2026-10-16) carries none and is complete by construction: its
writer validated before writing, and its count must match the groups.

A slot's `kind` is a rule's `_rule_kind` label; one outside the catalogue's
vocabulary (`_turn_rule_kinds()`, derived from the `AbstractTurnRule` tree)
is a file from a newer writer or a corrupted attribute, read as it stands
with a warning naming the slot group and the known kinds (S4-5: it used to
round-trip in silence).
"""
function _ra_turn_modulation(f; data::Bool=true)
    root = f["turn_modulation"]
    slots = sort!([parse(Int, String(k)) for k in keys(root) if root[k] isa HDF5.Group])
    kinds = _turn_rule_kinds()
    out = NamedTuple[]
    for slot in slots
        where = "/turn_modulation/$(slot)"
        g = root[string(slot)]
        present = count(k -> String(k) != _RA_TM_STATE && g[k] isa HDF5.Group, keys(g))
        n = _ra_tm_count(g, "element_count", where)
        cursor = _ra_get_attr(g, _RA_TM_CURSOR, nothing)
        valid = cursor === nothing ? n : Int(cursor)
        valid <= n || throw(ArgumentError(
            "$(where) is torn: $(_RA_TM_CURSOR) = $(valid) exceeds element_count = $(n)"))
        if valid < n
            # The partial slot: the complete prefix 1:valid, perhaps one
            # half-written group beyond it, nothing else.
            (valid <= present <= valid + 1) || throw(ArgumentError(
                "$(where) is torn: $(_RA_TM_CURSOR) = $(valid) of element_count = $(n) but " *
                "$(present) element group(s) present"))
            @warn "$(where) is partial: $(valid) of $(n) modulated element group(s) were " *
                  "written before the writer stopped (an error during prepare_run_artifact!); " *
                  "the slot is read as far as its cursor and is never rolled back, and " *
                  "append=true refuses the file by name" path = HDF5.filename(f)
        else
            present == n || throw(ArgumentError(
                "$(where) is torn: element_count = $(n) but $(present) element group(s) present"))
        end
        elements = NamedTuple[]
        for k in 1:valid
            haskey(g, string(k)) || throw(ArgumentError(
                "$(where) is torn: element group $(k) of $(n) is missing"))
            eg = g[string(k)]
            where_e = "$(where)/$(k)"
            labels = [String(l) for l in keys(eg) if eg[l] isa HDF5.Group]
            nslots = _ra_tm_count(eg, "slot_count", where_e)
            length(labels) == nslots || throw(ArgumentError(
                "$(where_e) is torn: slot_count = $(nslots) but $(length(labels)) " *
                "slot group(s) present"))
            entries = Tuple{Int,NamedTuple}[]
            for label in labels
                sg = eg[label]
                where_s = "$(where_e)/$(label)"
                kind_label = String(_ra_tm_attr(sg, "kind", where_s))
                Symbol(kind_label) in kinds || @warn(
                    "$(where_s) carries the kind $(repr(kind_label)), which is not a rule kind " *
                    "this reader knows ($(join(string.(kinds), ", "))): a file from a newer " *
                    "writer, or a corrupted attribute; read as it stands")
                push!(entries, (Int(_ra_tm_attr(sg, "index", where_s)),
                                (slot=label, kind=Symbol(kind_label),
                                 rng_id=UInt64(_ra_tm_attr(sg, "rng_id", where_s)),
                                 digest=UInt64(_ra_tm_attr(sg, "digest", where_s)),
                                 name=String(_ra_tm_attr(sg, "name", where_s)),
                                 length=Int(_ra_tm_attr(sg, "length", where_s)),
                                 nominal=_ra_tm_nominal(sg))))
            end
            sort!(entries; by=first)
            ordered = NamedTuple[s for (_, s) in entries]
            series = _ra_tm_series(eg, where_e, String[s.slot for s in ordered], data)
            if series !== nothing
                # A recorded element whose slot group lost its nominals is torn
                # like any other missing attribute: the series cannot be formed
                # into realised values without them.
                for s in ordered
                    s.nominal === nothing && throw(ArgumentError(
                        "$(where_e)/$(s.slot) is torn: the $(_RA_TM_NOMINAL_PREFIX)* " *
                        "attributes are missing although the element recorded a series"))
                end
            end
            slots_out = NamedTuple[merge(s, (series = series === nothing ? nothing : series.columns[j],))
                                   for (j, s) in enumerate(ordered)]
            # The window the series covers, from the dataset's attributes
            # (`nothing`, like `series`, when the run did not record): a reader
            # compares it with the row count, which is authoritative (F2).
            push!(elements, (element=String(_ra_tm_attr(eg, "element", where_e)),
                             beam=Int(_ra_tm_attr(eg, "beam", where_e)),
                             first_turn=series === nothing ? nothing : series.first_turn,
                             turns=series === nothing ? nothing : series.turns,
                             slots=slots_out))
        end
        push!(out, (execution=slot, elements=elements, state=nothing))
    end
    return out
end

_ra_turn_modulation_or_empty(f; data::Bool=true) =
    haskey(f, "turn_modulation") ? _ra_turn_modulation(f; data=data) : NamedTuple[]

"""
    turn_modulation_provenance(path::AbstractString) -> Vector{NamedTuple}

The turn-by-turn modulation provenance a run artifact recorded -- its
`/turn_modulation/<slot>` groups (docs/design/turn_modulation.md, D7: the
table rule owns its provenance in the run artifact): one entry per `execute!`
whose line had a modulated element, in `/execution` ledger order,

    (execution = 1,                             # the /execution ledger row
     elements  = [(element = "ThinCrabCavity",  # one per modulated element, line order
                   beam    = 1,                 # 1; a strong-strong task records 1 then 2
                   first_turn = 0, turns = 5,   # the window the series covers (its
                                                # dataset's attributes); nothing when
                                                # the run did not record
                   slots   = [(slot = "phase_noise[1]", kind = :white,
                               rng_id = 0x0000000000000007, digest = 0x0000000000000000,
                               name = "", length = 0,
                               nominal = (phase = 0.0, strengthX = 0.002, strengthY = 0.0),
                               series = [dphi_1, dphi_2, ...]),   # or nothing
                              (slot = "strength_noise[1]", kind = :table,
                               rng_id = 0x0000000000000000, digest = <FNV-1a 64 of the
                               table's bytes>, name = "amp", length = 10,
                               nominal = (phase = 0.0, strengthX = 0.002, strengthY = 0.0),
                               series = [d_1, d_2, ...])])],      # or nothing
     state     = nothing)                       # reserved (D10), written by nothing

so a table's identity (`digest`, `name`, `length`) and a stream rule's
`rng_id` travel with the file (`kind` is the rule's `_rule_kind` label, one
of `_turn_rule_kinds()`, derived from the rule catalogue: `:white`, `:pink`,
`:table`, and `:spectral` for the spec-level `SpectralNoise`, which resolves
to a table at compile and so never reaches a file; a kind outside that
vocabulary is read as it stands with a warning naming the slot group; the
fields a kind does not use hold zeros and `""`). `nominal` is the slot's
nominal parameters, read from its `nominal_*` attributes (the harmonic's
`phase`, `strengthX`, `strengthY` on a crab cavity slot; `phase`, `strength`
on an RF cavity slot; `nothing` for a file written before they existed).
`series` is the slot's recorded column when the run had
`RunArtifact(...; record_turn_modulation=true)` and `nothing` otherwise
(docs/design/turn_modulation_record.md): one `Float64` per turn of that
`execute!` window, entry `i` the OFFSET the rule produced for absolute turn
`first_turn + i - 1` (the ledger row's `start_turn`; the dataset's `first_turn`
and `turns` attributes repeat the window), radians on a phase slot and the
dimensionless relative factor `d` on a strength slot, so the realised values
are `nominal.phase + series[i]` and `nominal.strengthX * (1 + series[i])`,
`nominal.strengthY * (1 + series[i])` (`nominal.strength * (1 + series[i])` on
the RF cavity), exactly as the element formed them. The series and the
nominals are stored as `Float64` whatever the element's numeric type `T`, so
"exactly as the element formed them" holds bit for bit for `T = Float64` and
to `Float64` rounding for any other `T`. The element entry's `first_turn` and
`turns` are the window the series covers, read from the dataset's attributes
(`nothing` when the run did not record); the ROW COUNT of a series is
authoritative: a run stopped before its window completed (killed, or
interrupted between two flushes) leaves fewer rows than `turns`, and such a
series is read as it stands with a warning naming the dataset, never padded
or refused. The `/execution` ledger's `current_turn` is a separate progress
mark: both loops assign it at the top of each turn and every flush persists
it (luminosity, probe rows, series; since the 2026-10-16 neighbour audit,
before which a `TrackingTask` without strong beams wrote it only at
finalize), so on a killed run the ledger may lead a channel by the one turn
in flight and the rows decide. `state` is `nothing`: the
group reserved for a future stateful rule's checkpoint (D10) is written by
nothing today. Nothing in the group is ever
rewritten or deleted: a continued (`append=true`) file keeps one entry per
modulated execution, so every generation of rules it ran is on record. An
empty vector means no `execute!` recorded in this file had a modulated
element -- an unmodulated run, or a file from before the group existed;
neither is an error (the `/losses` reader's posture for its later-added
attributes). A group whose counts disagree with the subgroups present, or a
series whose columns do not name the slot groups, is
torn and refused with a message saying so. A PARTIAL slot is different
(owner decision 2026-10-16): a writer stopped by an HDF5 error mid-prepare
leaves the slot group's cursor `elements_valid_through` behind its
`element_count`, and such a slot is read as far as the cursor -- the
complete element groups only -- with one warning naming the slot; nothing
rolls it back, and `RunArtifact(...; append=true)` refuses the file by
name. `read(out, :turn_modulation)` on a
[`TaskOutput`](@ref) returns the same vector.
"""
turn_modulation_provenance(path::AbstractString) =
    _ra_open(_ra_turn_modulation_or_empty, path)

"""
    read(out::TaskOutput, kind::Symbol; name=nothing, column=nothing, turn=nothing,
         orders=nothing, extra=(), exclude=())

One product of the artifact. `kind` is one of `:luminosity`, `:moments`,
`:snapshot`, `:bpm`, `:losses`, `:execution`, `:turn_modulation` -- or `:all`
for every product present, nested by kind (named kinds as
`Dict{String,NamedTuple}`; reads the WHOLE file, snapshots included).

For the named kinds, no `name` returns every group as a
`Dict{String,NamedTuple}`; `name` selects one group, returned as a
`NamedTuple` of column vectors (luminosity: `(turn, value)`, each series on
its OWN turn axis -- a collision has a row exactly where its schedule
evaluated; the execution ledger's `turns` is a different thing, the planned
window length per `execute!`). `column` narrows a probe group to one column vector and accepts a
`Symbol`, a column-name string, or a `Moment` (moment groups). `turn` narrows
a snapshot group to one fired block.

`orders`/`extra`/`exclude` narrow a MOMENT group to a selection, by the
`MomentObserver` rules (expand `orders`, add `extra`, remove `exclude`;
requested moments not recorded in the group are skipped): the columns come
back as the usual `NamedTuple`, `turn` first. `read(out, :moments;
name="IP6", orders=1)` is the keyword twin of
`read(MomentOutput(path; name="IP6"); orders=1)`, which returns the same
selection as a matrix.

Probe groups carry the scalar `s` — the probe's arc position in its line —
beside the columns (`nothing` for task-hook probes and pre-attribute files).

`:losses` returns the per-loss rows as column vectors (pre-kill coordinates),
the per-aperture names/counts/arc positions, and the reconciliation summary
when the run recorded one (`nothing` otherwise); for a `StrongStrongTask`
artifact, that shape per beam whose line carries an aperture, keyed `beam_1`,
`beam_2` (the artifact's `/losses/beam_<i>` subgroups). On a continued
(`append=true`) file the rows and `aperture_counts` of each group span every
window the file holds under the replay rule (the earlier windows' rows below
each later window's first turn, then that window's own; 2026-10-19), while
`summary` is the LAST `execute!`'s beam, so `sum(aperture_counts) ==
summary.logged` holds on a fresh file and the counts exceed `summary.logged`
by the earlier windows' retained losses on a continued one. `:execution` returns the
ledger -- one entry per `execute!`: `start_turn`, `turns`,
`current_turn`/`elapsed` updated at every flush of every channel (luminosity,
probe rows, turn-modulation series) and at finalize, and `rng_seed`/
`rng_method`, the global stochastic seed and the counter-RNG method's name in
force when that `execute!` began (`nothing` for a file written before
2026-10-16). `:turn_modulation` returns the turn-by-turn modulation provenance, one
entry per `execute!` that had a modulated element, the vector
[`turn_modulation_provenance`](@ref) documents (empty when no recorded
`execute!` had one or the file predates the group), each slot entry with its
`nominal` and, when the run recorded (`record_turn_modulation=true`), its
`series`, each element entry with the window the series covers (`first_turn`,
`turns`; the row count is authoritative, a shorter series warns by name).
"""
function Base.read(out::TaskOutput, kind::Symbol;
                   name::Union{Nothing,AbstractString}=nothing,
                   column=nothing, turn::Union{Nothing,Integer}=nothing,
                   orders=nothing, extra=(), exclude=())
    kind === :all || kind in _RA_KINDS || throw(ArgumentError(
        "unknown artifact product $(repr(kind)); one of " *
        join(string.(_RA_KINDS), ", ") * ", all"))
    selection = orders !== nothing || !isempty(extra) || !isempty(exclude)
    if selection
        kind === :moments || throw(ArgumentError(
            "orders/extra/exclude select moment columns; they do not apply to $(kind)"))
        name === nothing && throw(ArgumentError(
            "orders/extra/exclude selection needs a name= to pick the moment group"))
        column === nothing || throw(ArgumentError(
            "pass either column or an orders/extra/exclude selection, not both"))
    end
    if kind in (:all, :losses, :execution, :turn_modulation)
        (name === nothing && column === nothing && turn === nothing) ||
            throw(ArgumentError("$(kind) is not a named group: name/column/turn do not apply"))
    end
    if kind === :all
        present = _ra_contents(out.path)
        items = [Symbol(k) => read(out, Symbol(k)) for k in sort(collect(keys(present)))]
        return (; items...)
    end
    turn === nothing || kind === :snapshot || throw(ArgumentError(
        "turn selects a snapshot block; it does not apply to $(kind)"))
    column === nothing || kind in (:moments, :snapshot, :bpm) || throw(ArgumentError(
        "column selects from a probe group; it does not apply to $(kind)"))
    _ra_open(out.path) do f
        # The single-product kinds take their group through `_ra_require_group`
        # like the named kinds, so a file lacking the group answers "carries no
        # <kind>; present: ..." rather than a raw HDF5 KeyError (pre-existing;
        # 2026-10-13 neighbour audit, U5-7). An absent /turn_modulation is the
        # documented empty answer instead: no execute! recorded modulation.
        kind === :losses && return _ra_losses(_ra_require_group(f, out, kind))
        kind === :execution && return _ra_execution(_ra_require_group(f, out, kind))
        kind === :turn_modulation && return _ra_turn_modulation_or_empty(f)
        g = _ra_require_group(f, out, kind)
        one_group = kind === :luminosity ? _ra_lum_series : _ra_probe_columns
        if name === nothing
            column === nothing && turn === nothing || throw(ArgumentError(
                "column/turn selection needs a name= to pick the group"))
            return Dict(String(k) => one_group(g[k])
                        for k in keys(g) if g[k] isa HDF5.Group)
        end
        rows = one_group(_ra_named_group(g, out, kind, name))
        if turn !== nothing
            keep = rows.turn .== Float64(turn)
            # Scalars (the s attribute) carry through; only columns filter.
            rows = (; (k => (v isa AbstractVector ? v[keep] : v)
                       for (k, v) in pairs(rows))...)
        end
        if selection
            # The MomentObserver selection rules; requested-but-unrecorded
            # moments are skipped, matching MomentOutput.
            wanted = Symbol[:turn]
            for m in _selected_moments(orders=orders === nothing ? () : orders,
                                       extra=extra, exclude=exclude)
                push!(wanted, symbol(m))
            end
            rows = (; (k => rows[k] for k in wanted if haskey(rows, k))...)
        end
        column === nothing && return rows
        return _ra_select_column(rows, column, "$(kind)/$(name)")
    end
end

"""
    read(out::TaskOutput) -> Dict{String,Any}

The artifact's table of contents, RECURSIVE and metadata-only (shape and
attribute reads; no data): each named kind maps to `Dict(name =>
(columns, rows[, s]))` -- `s` is the probe's arc position where stamped --
and the single products carry their own `(columns, rows, ...)`;
`turn_modulation` is its provenance vector whole (attributes, the nominals
included), with each slot's `series` standing as the recorded ROW COUNT in
place of the column that `read(out, :turn_modulation)` returns (`nothing`
when the run did not record). One call
tells you how to write every subsequent `read(out, kind; ...)`;
`read(out, :all)` returns the same nesting with the data in it.
"""
function Base.read(out::TaskOutput)
    _ra_open(out.path) do f
        toc = Dict{String,Any}()
        for kind in keys(f)
            obj = f[kind]
            k = String(kind)
            if k == "execution"
                cols = sort(collect(String.(keys(obj))))
                toc[k] = (columns=cols,
                          rows=isempty(cols) ? 0 : length(obj[first(cols)]))
            elseif k == "losses"
                toc[k] = _ra_losses_toc(obj)
            elseif k == "turn_modulation"
                # The provenance IS the metadata; a recorded series is read as
                # its row count here, not as data.
                toc[k] = _ra_turn_modulation(f; data=false)
            elseif obj isa HDF5.Group
                groups = Dict{String,NamedTuple}()
                for name in keys(obj)
                    g = obj[name]
                    g isa HDF5.Group || continue
                    if k == "luminosity"
                        groups[String(name)] = (columns=["turn", "value"],
                                                rows=length(g["turns"]))
                    else
                        s = _ra_get_attr(g, "s", nothing)
                        base = (columns=String.(read(g["column_names"])),
                                rows=size(g["data"], 1))
                        groups[String(name)] = s === nothing ? base :
                                               merge(base, (s=Float64(s),))
                    end
                end
                toc[k] = groups
            end
        end
        toc
    end
end
