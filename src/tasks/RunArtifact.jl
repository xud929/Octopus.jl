export RunArtifact

# ---------------------------------------------------------------------------
# The run artifact: one HDF5 output file per task, one group per producer.
# Design: docs/design/run_artifact.md (decided 2026-08-18). This file is
# migration step 1: the container, the crash-recovery cursor, the execution
# channel, and the strong-strong luminosity channel with INDEPENDENT
# per-collision turn axes. The text `.lum` path is untouched and may run
# alongside (it is the design's live mirror); probes and losses join in later
# steps.
# ---------------------------------------------------------------------------

"""
    RunArtifact(path; append=false, capacity=64)

The one-output-file-per-task sink (docs/design/run_artifact.md): an HDF5 file
with one group per producer, owned by the task that carries it.

This first migration step records the strong-strong luminosity channel and
the execution ledger:

- `/luminosity/<label>`: per-collision `turns`/`values` datasets with
  INDEPENDENT turn axes — a collision writes a row exactly when its own
  luminosity schedule evaluated, so per-IP schedules may disagree freely
  (the fixed-width text row's whole-row drop rule does not apply here).
  `NaN` keeps its meaning: evaluated and failed.
- `/execution`: one row per `execute!` — `start_turn`, planned `turns`,
  `current_turn` and wall-clock `elapsed`, the last two updated at every
  flush — appended and never overwritten, so every execution of a swap-out
  or chunked run keeps its record. `current_turn` is the turn the execution
  had reached at its most recent flush: live progress and rate from one
  `h5ls` while running, and the run-level how-far-did-it-get answer after a
  crash (the per-group cursors answer the same question per dataset).

`append=false` (default) recreates the file per `execute!`; `append=true`
continues it across `execute!` calls and process restarts under the replay
idempotence rule: rows at or beyond the incoming window's first turn are
dropped per group first. A file whose luminosity groups do not match the
task's collision labels is refused rather than silently mixed.

**Crash recovery** is the per-group cursor attribute
`rows_valid_through_turn`, written AFTER its batch of rows and flushed with
it: on open, any rows beyond the cursor are a torn tail from an interrupted
write and are truncated. `capacity` is the rows-per-group buffered between
flushes; the file handle is held open for the whole `execute!`, so flushing
costs no open/close.

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
`first_turn` are dropped), append this execution's ledger row, register the
path by artifact identity, and hold the file open.
"""
function prepare_run_artifact!(art::RunArtifact, labels::Vector{String},
                               first_turn::Int, planned_turns::Int)
    art.file === nothing || error("RunArtifact at $(art.path) is already open; " *
                                  "one artifact serves one execute! at a time")
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
        for (name, val) in (("start_turn", Int64(first_turn)),
                            ("turns", Int64(planned_turns)),
                            ("current_turn", Int64(first_turn) - 1),
                            ("elapsed", 0.0))
            d = ex[name]
            HDF5.set_extent_dims(d, (n + 1,))
            d[n + 1] = val
        end
        art.execution_slot = n + 1
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

"""
Record one collision's luminosity for one turn. Rows land on THIS label's own
turn axis; nothing about other collisions' schedules is consulted, which is
the design's point.
"""
function push_luminosity!(art::RunArtifact, label::String, turn::Integer, value::Float64)
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
Rewrite the artifact's `/losses` group from the task's cumulative loss
record, mirroring `write_loss_record`'s layout (per-loss rows, aperture
names/counts/arc positions, and the reconciliation summary as attributes
when the caller has one). Rewritten WHOLE per execute! -- the record is
cumulative and a particle is lost at most once, so the rewrite is
idempotent, exactly the loss-log rule. A task with no loss record (no
aperture in the line) writes nothing; a counters-only record (no log
slots requested) writes the per-aperture accounting without rows.
"""
function _ra_write_losses!(art::RunArtifact, record, s_positions, summary)
    art.file === nothing && return nothing
    record === nothing && return nothing
    haskey(art.file, "losses") && HDF5.delete_object(art.file, "losses")
    g = HDF5.create_group(art.file, "losses")
    g["aperture_names"] = aperture_names(record)
    g["aperture_counts"] = loss_counts(record)
    s_positions === nothing || (g["aperture_s"] = collect(Float64, s_positions))
    if record.slots !== nothing
        r = loss_records(record)
        n = length(r.particle_id)
        data = Matrix{Float64}(undef, n, length(LOSS_RECORD_COLUMNS))
        for (j, col) in enumerate(LOSS_RECORD_COLUMNS)
            data[:, j] = Float64.(getproperty(r, Symbol(col)))
        end
        g["data"] = data
        g["column_names"] = collect(String, LOSS_RECORD_COLUMNS)
        _ra_set_attr!(g, "record_count", Int64(n))
    end
    if summary !== nothing
        _ra_set_attr!(g, "summary_particles", Int64(summary.particles))
        _ra_set_attr!(g, "summary_live", Int64(summary.live))
        _ra_set_attr!(g, "summary_dead", Int64(summary.dead))
        _ra_set_attr!(g, "summary_unattributed", Int64(summary.unattributed))
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

"""
Bind one probe to the open artifact: create its group (or continue it,
refusing a column-layout mismatch), apply the crash-truncation and replay
rules, and enforce name uniqueness within this execute!. Returns the group
key the probe pushes rows through.
"""
function _ra_bind_probe!(art::RunArtifact, kind::String, name::String,
                         colnames::Vector{String}, first_turn::Int)
    art.file === nothing && throw(ArgumentError(
        "a named probe needs an open run artifact; give the task artifact=..."))
    isempty(name) && throw(ArgumentError("a probe bound to the artifact needs a name"))
    key = kind * "/" * name
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
    size(rows, 1) == 0 && return nothing
    g = art.file[key]
    d = g["data"]
    n = size(d, 1)
    HDF5.set_extent_dims(d, (n + size(rows, 1), size(d, 2)))
    d[(n + 1):(n + size(rows, 1)), :] = Float64.(rows)
    _ra_set_attr!(g, "rows_valid_through_turn", Int64(round(Int64, rows[end, 1])))
    HDF5.flush(art.file)
    return nothing
end
