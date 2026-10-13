export RunArtifact, TaskOutput, turn_modulation_provenance

# ---------------------------------------------------------------------------
# The run artifact: one HDF5 output file per task, one group per producer.
# Design: docs/design/run_artifact.md (decided and implemented 2026-08-18).
# This file carries the container, the per-group crash-recovery cursor, the
# execution ledger, the luminosity channels (strong-strong per collision,
# weak-strong per strong beam, INDEPENDENT turn axes), the /losses writer,
# the probe row-matrix machinery the named observer views bind through
# (/moments|snapshot|bpm/<name>), and the TaskOutput reader. The standalone
# per-observer writers retired behind it (step 4).
# ---------------------------------------------------------------------------

"""
    RunArtifact(path; append=false, capacity=64)

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
- `/losses`: the loss accounting, rewritten whole per `execute!` from the
  cumulative record.
- `/execution`: one row per `execute!` — `start_turn`, planned `turns`,
  `current_turn` and wall-clock `elapsed`, the last two updated at every
  flush — appended and never overwritten, so every execution of a swap-out
  or chunked run keeps its record. `current_turn` is the turn the execution
  had reached at its most recent flush: live progress and rate from one
  `h5ls` while running, and the run-level how-far-did-it-get answer after a
  crash (the per-group cursors answer the same question per dataset).
- `/turn_modulation/<slot>`: the turn-by-turn modulation provenance of the
  `execute!` whose `/execution` ledger row is `<slot>`, written only when
  its line had a modulated element (docs/design/turn_modulation.md, D7):
  `element_count` on the slot group; one subgroup per modulated element in
  line order with `element`, `beam` (1 for a `TrackingTask` line, 1 or 2 for
  the strong-strong task's two lines) and `slot_count`; one subgroup per
  ACTIVE slot below it, named by the slot label, with `index`, `kind`
  (`white`, `pink` or `table`), `rng_id`, `digest`, `name`, `length`.
  Attributes only; nothing here is ever rewritten or deleted, so a
  continued file keeps every generation of rules it ran. Read it with
  [`turn_modulation_provenance`](@ref) or `read(out, :turn_modulation)`: an
  empty vector means no `execute!` recorded in the file had a modulated
  element.

Read it back through one handle: [`TaskOutput`](@ref).

`append=false` (default) recreates the file per `execute!`; `append=true`
continues it across `execute!` calls and process restarts under the replay
idempotence rule: rows at or beyond the incoming window's first turn are
dropped per group first. A file whose luminosity groups do not match the
task's collision labels is refused rather than silently mixed.

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

Pass it to the task (`StrongStrongTask(...; artifact=RunArtifact(path))`, or
a bare path as sugar). The artifact path is registered by artifact identity,
so the same task continuing is silent while a second writer on the path
draws the collision warning.
"""
mutable struct RunArtifact
    path::String
    append::Bool
    capacity::Int
    # execute!-scoped state
    file::Union{Nothing,HDF5.File}
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
end

function RunArtifact(path::AbstractString; append::Bool=false, capacity::Integer=64)
    cap = Int(capacity)
    cap >= 1 || throw(ArgumentError("RunArtifact capacity must be at least 1; got $(cap)."))
    return RunArtifact(String(path), Bool(append), cap, nothing,
                       Dict{String,Vector{Int64}}(), Dict{String,Vector{Float64}}(),
                       0, UInt64(0), false, Int64(0), Set{String}())
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

"""
Open (or create) the artifact for one `execute!`: validate or build the
luminosity groups for `labels`, apply crash-truncation (rows beyond each
group's cursor are a torn tail) and the replay rule (rows at or beyond
`first_turn` are dropped), append this execution's ledger row, record the
line's turn-modulation provenance `turn_modulation` (the receipt entries of
`_turn_modulation_entries`) under `/turn_modulation/<slot>` for that row --
nothing when empty -- register the path by artifact identity, and hold the
file open.
"""
function prepare_run_artifact!(art::RunArtifact, labels::Vector{String},
                               first_turn::Int, planned_turns::Int;
                               turn_modulation::AbstractVector=Any[])
    art.file === nothing || error("RunArtifact at $(art.path) is already open; " *
                                  "one artifact serves one execute! at a time")
    # One run, one output file, written by rank 0. Every rank still runs the
    # observers -- their reductions are collectives and a rank that skipped
    # them would hang its peers -- but only rank 0 opens the file, so the
    # others leave `file === nothing` and every write below no-ops.
    _mp_is_root() || return nothing
    if !art.registered
        _register_observer_path!(art, art.path)
        art.registered = true
    end
    fresh = !art.append || !isfile(art.path) || filesize(art.path) == 0
    file = HDF5.h5open(art.path, fresh ? "w" : "r+")
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
            _ra_extendable!(ex, "start_turn", Int64)
            _ra_extendable!(ex, "turns", Int64)
            _ra_extendable!(ex, "current_turn", Int64)
            _ra_extendable!(ex, "elapsed", Float64)
        else
            haskey(file, "luminosity") || throw(ArgumentError(
                "RunArtifact(append=true): $(art.path) is not a run artifact " *
                "(no /luminosity group). Use a new path."))
        existing = sort(collect(keys(file["luminosity"])))
            sort(labels) == existing || throw(ArgumentError(
                "RunArtifact(append=true): the luminosity groups at $(art.path) " *
                "($(existing)) do not match this task's collision labels " *
                "($(sort(labels))). Use a new path."))
            for label in labels
                g = file["luminosity"][label]
                cursor = Int64(_ra_get_attr(g, "rows_valid_through_turn",
                                            Int64(typemin(Int32))))
                # Torn tail first (rows the cursor never blessed), then the
                # replay rule: both reduce to one keep-through bound.
                _ra_truncate_group!(g, min(cursor, Int64(first_turn) - 1))
            end
        end
        ex = file["execution"]
        if !haskey(ex, "current_turn")
            # A step-1 file from before the column existed: add it, padding
            # the earlier rows with the nothing-known sentinel.
            d = _ra_extendable!(ex, "current_turn", Int64)
            nprev = length(ex["start_turn"])
            if nprev > 0
                HDF5.set_extent_dims(d, (nprev,))
                d[1:nprev] = fill(Int64(typemin(Int32)), nprev)
            end
        end
        n = length(ex["start_turn"])
        # The provenance slot of the row about to be appended must be free:
        # checked BEFORE the four ledger datasets are extended, so a refusal
        # leaves the ledger as it found it. Checked inside the writer after
        # the append, the refusal left a phantom row (`start_turn`, `turns`,
        # `current_turn = first_turn - 1`, `elapsed = 0.0`) that the reader
        # paired with the stranger group (2026-10-13 neighbour audit, U5-3).
        _ra_check_turn_modulation_slot(file, art.path, n + 1, turn_modulation)
        for (name, val) in (("start_turn", Int64(first_turn)),
                            ("turns", Int64(planned_turns)),
                            ("current_turn", Int64(first_turn) - 1),
                            ("elapsed", 0.0))
            d = ex[name]
            HDF5.set_extent_dims(d, (n + 1,))
            d[n + 1] = val
        end
        art.execution_slot = n + 1
        # Keyed by the ledger row just appended, so written after it.
        _ra_write_turn_modulation!(file, art.path, art.execution_slot, turn_modulation)
        art.start_time_ns = time_ns()
        art.current_turn = Int64(first_turn) - 1
        empty!(art.probe_names)
        HDF5.flush(file)
    catch
        close(file)
        rethrow()
    end
    art.file = file
    empty!(art.pending_turns)
    empty!(art.pending_values)
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
# `digest`, `name`, `length`; HDF5 link names admit the brackets). Written at
# prepare from the receipt the task records (`_turn_modulation_entries`), so
# the artifact and the `:turn_modulation` receipt derive from the one walk;
# never rewritten or deleted, so a continued file keeps every generation.
# ---------------------------------------------------------------------------

"""
Write `/turn_modulation/<slot>` for the ledger row `slot` just appended:
nothing when `entries` is empty (an unmodulated `execute!` leaves no group for
its slot), otherwise the element groups and their slot groups. Nothing here is
ever rewritten or deleted -- every execution that had a modulated element
keeps its own record, so a continued file holds every generation of rules it
ran; a slot group that already exists can only mean the ledger and the
provenance disagree, and is refused by `_ra_check_turn_modulation_slot`, which
`prepare_run_artifact!` runs BEFORE appending the row (U5-3) and this writer
runs again.
"""
function _ra_write_turn_modulation!(file, path::String, slot::Int, entries)
    isempty(entries) && return nothing
    _ra_check_turn_modulation_slot(file, path, slot, entries)
    root = haskey(file, "turn_modulation") ? file["turn_modulation"] :
           HDF5.create_group(file, "turn_modulation")
    g = HDF5.create_group(root, string(slot))
    _ra_set_attr!(g, "element_count", Int64(length(entries)))
    for (k, entry) in enumerate(entries)
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
        end
    end
    return nothing
end

"""
Record one collision's luminosity for one turn. Rows land on THIS label's own
turn axis; nothing about other collisions' schedules is consulted, which is
the design's point.
"""
function push_luminosity!(art::RunArtifact, label::String, turn::Integer, value::Float64)
    _mp_is_root() || return nothing
    t = get!(() -> Int64[], art.pending_turns, label)
    v = get!(() -> Float64[], art.pending_values, label)
    push!(t, Int64(turn))
    push!(v, value)
    length(t) >= art.capacity && _ra_flush_luminosity!(art, label)
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
    ex = art.file["execution"]
    ex["current_turn"][art.execution_slot] = art.current_turn
    ex["elapsed"][art.execution_slot] = (time_ns() - art.start_time_ns) / 1.0e9
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
"""
function _ra_gathered_loss_rows(record, shard_offset::Integer)
    record === nothing && return nothing
    record.slots === nothing && return nothing
    r = loss_records(record; offset=shard_offset)
    n = length(r.particle_id)
    rows = Matrix{Float64}(undef, n, length(LOSS_RECORD_COLUMNS))
    for (j, col) in enumerate(LOSS_RECORD_COLUMNS)
        rows[:, j] = Float64.(getproperty(r, Symbol(col)))
    end
    return _mp_gather_rows(rows)
end

"""
Rewrite the artifact's `/losses` group from the task's cumulative loss
record, mirroring `write_loss_record`'s layout (per-loss rows, aperture
names/counts/arc positions, and the reconciliation summary as attributes
when the caller has one). Rewritten WHOLE per execute! -- the record is
cumulative and a particle is lost at most once, so the rewrite is
idempotent, exactly the loss-log rule. A task with no loss record (no
aperture in the line) writes nothing; a counters-only record (no log
slots requested) writes the per-aperture accounting without rows.
"""
function _ra_write_losses!(art::RunArtifact, record, s_positions, summary,
                           shard_offset::Integer=0; folded::Bool=false)
    # Every rank builds and gathers its rows -- the gather is a collective, so
    # a rank that returned early would hang the rest -- and only rank 0, which
    # holds the file, writes them.
    gathered = _ra_gathered_loss_rows(record, shard_offset)
    art.file === nothing && return nothing
    record === nothing && return nothing
    haskey(art.file, "losses") && HDF5.delete_object(art.file, "losses")
    g = HDF5.create_group(art.file, "losses")
    g["aperture_names"] = aperture_names(record)
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
    g["aperture_counts"] = summary === nothing ? loss_counts(record) :
                           collect(Int, summary.by_aperture)
    s_positions === nothing || (g["aperture_s"] = collect(Float64, s_positions))
    if gathered !== nothing
        g["data"] = gathered
        g["column_names"] = collect(String, LOSS_RECORD_COLUMNS)
        _ra_set_attr!(g, "record_count", Int64(size(gathered, 1)))
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

"""Flush every pending group, stamp this execution's elapsed time, close."""
function finalize_run_artifact!(art::RunArtifact)
    art.file === nothing && return nothing
    try
        for label in collect(keys(art.pending_turns))
            _ra_flush_luminosity!(art, label)
        end
        ex = art.file["execution"]
        ex["current_turn"][art.execution_slot] = art.current_turn
        ex["elapsed"][art.execution_slot] = (time_ns() - art.start_time_ns) / 1.0e9
        HDF5.flush(art.file)
    finally
        close(art.file)
        art.file = nothing
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
Bind one probe to the open artifact: create its group (or continue it,
refusing a column-layout mismatch), apply the crash-truncation and replay
rules, and enforce name uniqueness within this execute!. Returns the group
key the probe pushes rows through.
"""
function _ra_bind_probe!(art::RunArtifact, kind::String, name::String,
                         colnames::Vector{String}, first_turn::Int;
                         s::Union{Nothing,Real}=nothing)
    isempty(name) && throw(ArgumentError("a probe bound to the artifact needs a name"))
    key = kind * "/" * name
    # Non-root ranks hold no file, so a probe binds to a name and writes
    # nothing; its observer still computes, because the computation is a
    # collective.
    _mp_is_root() || return key
    art.file === nothing && throw(ArgumentError(
        "a named probe needs an open run artifact; give the task artifact=..."))
    key in art.probe_names && throw(ArgumentError(
        "duplicate probe name $(repr(name)) under /$(kind): names are the " *
        "artifact's group identities and must be unique within a task"))
    push!(art.probe_names, key)
    f = art.file
    parent = haskey(f, kind) ? f[kind] : HDF5.create_group(f, kind)
    if haskey(parent, name)
        g = parent[name]
        stored = read(g["column_names"])
        stored == colnames || throw(ArgumentError(
            "the probe group /$(key) at $(art.path) carries columns $(stored), " *
            "not $(colnames); use a different name or path"))
        cursor = Int64(_ra_get_attr(g, "rows_valid_through_turn",
                                    Int64(typemin(Int32))))
        _ra_truncate_probe!(g, min(cursor, Int64(first_turn) - 1))
    else
        g = HDF5.create_group(parent, name)
        ncols = length(colnames)
        HDF5.create_dataset(g, "data", HDF5.datatype(Float64),
            HDF5.dataspace((0, ncols); max_dims=(-1, ncols)); chunk=(256, ncols))
        g["column_names"] = colnames
        _ra_set_attr!(g, "name", name)
        _ra_set_attr!(g, "rows_valid_through_turn", Int64(typemin(Int32)))
    end
    # The design's `attrs: name, s`: a line-placed probe records WHERE in the
    # line it sat (arc length at its placement), so the file answers it
    # without the script that made it. Stamped on continue too -- idempotent
    # for the same lattice, corrective if the probe moved.
    s === nothing || _ra_set_attr!(g, "s", Float64(s))
    HDF5.flush(f)
    return key
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
    g = art.file[key]
    d = g["data"]
    n = size(d, 1)
    HDF5.set_extent_dims(d, (n + size(rows, 1), size(d, 2)))
    d[(n + 1):(n + size(rows, 1)), :] = Float64.(rows)
    _ra_set_attr!(g, "rows_valid_through_turn", Int64(round(Int64, rows[end, 1])))
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

_ra_open(path) = HDF5.h5open(String(path), "r")
_ra_open(f::Function, path) = HDF5.h5open(f, String(path), "r")

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

const _RA_NAMED_KINDS = (:luminosity, :moments, :snapshot, :bpm)
const _RA_KINDS = (:luminosity, :moments, :snapshot, :bpm, :losses, :execution,
                   :turn_modulation)

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

# `g` is the /losses group, handed over by `_ra_require_group` (U5-7).
function _ra_losses(g)
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

# `ex` is the /execution group, handed over by `_ra_require_group` (U5-7).
_ra_execution(ex) =
    (start_turn=read(ex["start_turn"]), turns=read(ex["turns"]),
     current_turn=read(ex["current_turn"]), elapsed=read(ex["elapsed"]))

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
`_ra_tm_count` and the eight others (`index`, `kind`, `rng_id`, `digest`,
`name`, `length` on a slot group; `element`, `beam` on an element group) --
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
Read a present `/turn_modulation` group: one entry per execution slot that
recorded modulation, in ledger order. Every count is checked against the
subgroups present and every attribute is read without a default; a mismatch,
a missing count or a missing attribute is a TORN group, refused by an
`ArgumentError` naming the group (and the attribute) rather than read short.
"""
function _ra_turn_modulation(f)
    root = f["turn_modulation"]
    slots = sort!([parse(Int, String(k)) for k in keys(root) if root[k] isa HDF5.Group])
    out = NamedTuple[]
    for slot in slots
        where = "/turn_modulation/$(slot)"
        g = root[string(slot)]
        present = count(k -> g[k] isa HDF5.Group, keys(g))
        n = _ra_tm_count(g, "element_count", where)
        present == n || throw(ArgumentError(
            "$(where) is torn: element_count = $(n) but $(present) element group(s) present"))
        elements = NamedTuple[]
        for k in 1:n
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
                push!(entries, (Int(_ra_tm_attr(sg, "index", where_s)),
                                (slot=label, kind=Symbol(_ra_tm_attr(sg, "kind", where_s)),
                                 rng_id=UInt64(_ra_tm_attr(sg, "rng_id", where_s)),
                                 digest=UInt64(_ra_tm_attr(sg, "digest", where_s)),
                                 name=String(_ra_tm_attr(sg, "name", where_s)),
                                 length=Int(_ra_tm_attr(sg, "length", where_s)))))
            end
            sort!(entries; by=first)
            push!(elements, (element=String(_ra_tm_attr(eg, "element", where_e)),
                             beam=Int(_ra_tm_attr(eg, "beam", where_e)),
                             slots=NamedTuple[s for (_, s) in entries]))
        end
        push!(out, (execution=slot, elements=elements))
    end
    return out
end

_ra_turn_modulation_or_empty(f) =
    haskey(f, "turn_modulation") ? _ra_turn_modulation(f) : NamedTuple[]

"""
    turn_modulation_provenance(path::AbstractString) -> Vector{NamedTuple}

The turn-by-turn modulation provenance a run artifact recorded -- its
`/turn_modulation/<slot>` groups (docs/design/turn_modulation.md, D7: the
table rule owns its provenance in the run artifact): one entry per `execute!`
whose line had a modulated element, in `/execution` ledger order,

    (execution = 1,                             # the /execution ledger row
     elements  = [(element = "ThinCrabCavity",  # one per modulated element, line order
                   beam    = 1,                 # 1; a strong-strong task records 1 then 2
                   slots   = [(slot = "phase_noise[1]", kind = :white,
                               rng_id = 0x0000000000000007, digest = 0x0000000000000000,
                               name = "", length = 0),
                              (slot = "strength_noise[1]", kind = :table,
                               rng_id = 0x0000000000000000, digest = <FNV-1a 64 of the
                               table's bytes>, name = "amp", length = 10)])])

so a table's identity (`digest`, `name`, `length`) and a stream rule's
`rng_id` travel with the file (`kind` is `:white`, `:pink` or `:table`; the
fields a kind does not use hold zeros and `""`). Nothing in the group is ever
rewritten or deleted: a continued (`append=true`) file keeps one entry per
modulated execution, so every generation of rules it ran is on record. An
empty vector means no `execute!` recorded in this file had a modulated
element -- an unmodulated run, or a file from before the group existed;
neither is an error (the `/losses` reader's posture for its later-added
attributes). A group whose counts disagree with the subgroups present is
torn and refused with a message saying so. `read(out, :turn_modulation)` on a
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
when the run recorded one (`nothing` otherwise). `:execution` returns the
ledger -- one entry per `execute!`, `current_turn`/`elapsed` updated at every
flush. `:turn_modulation` returns the turn-by-turn modulation provenance, one
entry per `execute!` that had a modulated element, the vector
[`turn_modulation_provenance`](@ref) documents (empty when no recorded
`execute!` had one or the file predates the group).
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
`turn_modulation`, attributes only, is its provenance vector whole. One call
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
                toc[k] = (columns=haskey(obj, "column_names") ?
                              String.(read(obj["column_names"])) : String[],
                          rows=haskey(obj, "data") ? size(obj["data"], 1) : 0,
                          apertures=String.(read(obj["aperture_names"])))
            elseif k == "turn_modulation"
                # Attributes only, so the provenance IS the metadata.
                toc[k] = _ra_turn_modulation(f)
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
