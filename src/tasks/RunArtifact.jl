export RunArtifact, TaskOutput

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
`first_turn` are dropped), append this execution's ledger row, register the
path by artifact identity, and hold the file open.
"""
function prepare_run_artifact!(art::RunArtifact, labels::Vector{String},
                               first_turn::Int, planned_turns::Int)
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
                           shard_offset::Integer=0)
    # Every rank builds and gathers its rows -- the gather is a collective, so
    # a rank that returned early would hang the rest -- and only rank 0, which
    # holds the file, writes them.
    gathered = _ra_gathered_loss_rows(record, shard_offset)
    art.file === nothing && return nothing
    record === nothing && return nothing
    haskey(art.file, "losses") && HDF5.delete_object(art.file, "losses")
    g = HDF5.create_group(art.file, "losses")
    g["aperture_names"] = aperture_names(record)
    g["aperture_counts"] = loss_counts(record)
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
const _RA_KINDS = (:luminosity, :moments, :snapshot, :bpm, :losses, :execution)

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

function _ra_losses(f)
    g = f["losses"]
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
         unattributed=Int(read(a["summary_unattributed"]))) : nothing
    merge(rows,
          (aperture_names=String.(read(g["aperture_names"])),
           aperture_counts=Int.(read(g["aperture_counts"])),
           aperture_s=haskey(g, "aperture_s") ? read(g["aperture_s"]) : nothing,
           summary=summary))
end

_ra_execution(f) = begin
    ex = f["execution"]
    (start_turn=read(ex["start_turn"]), turns=read(ex["turns"]),
     current_turn=read(ex["current_turn"]), elapsed=read(ex["elapsed"]))
end

"""
    read(out::TaskOutput, kind::Symbol; name=nothing, column=nothing, turn=nothing,
         orders=nothing, extra=(), exclude=())

One product of the artifact. `kind` is one of `:luminosity`, `:moments`,
`:snapshot`, `:bpm`, `:losses`, `:execution` -- or `:all` for every product
present, nested by kind (named kinds as `Dict{String,NamedTuple}`; reads the
WHOLE file, snapshots included).

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
flush.
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
    if kind in (:all, :losses, :execution)
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
        kind === :losses && return _ra_losses(f)
        kind === :execution && return _ra_execution(f)
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
and the single products carry their own `(columns, rows, ...)`. One call
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
