import Base: read

export AbstractSchedule, AbstractBeamObserver, AbstractBeamAction,
       AlwaysSchedule, EveryNSteps, AtTurns, PredicateSchedule,
       should_run, ScheduledObserver, ScheduledAction,
       Moment, name, symbol, column_names,
       BeamMomentObserver, JLD2BeamMomentObserver, MomentObserver,
       CoordinateSnapshotObserver, LuminosityObserver, BeamSwapAction,
       observe!, apply_action!, run_observers!, run_actions!,
       prepare_observers!, prepare_line_observers!,
       finalize_observers!, requires_elementwise_tracking,
       MomentOutputFile, OutputFile, MomentFile, read_moment

abstract type AbstractSchedule end
abstract type AbstractBeamObserver end
abstract type AbstractBeamAction end

"""Run on every turn."""
struct AlwaysSchedule <: AbstractSchedule end

"""
    EveryNSteps(; start=0, stop=typemax(Int), step=1)

Run on turns `start, start + step, ...` while `turn < stop`.
"""
struct EveryNSteps <: AbstractSchedule
    start::Int
    stop::Int
    step::Int
end
function EveryNSteps(; start::Integer=0, stop::Integer=typemax(Int), step::Integer=1)
    step > 0 || throw(ArgumentError("step must be positive"))
    return EveryNSteps(Int(start), Int(stop), Int(step))
end

"""Run on an explicit set of turns."""
struct AtTurns <: AbstractSchedule
    turns::Set{Int}
end
AtTurns(turns::Union{AbstractVector,AbstractRange,Tuple}) = AtTurns(Set(Int.(turns)))

"""Run when `predicate(ctx)` returns true."""
struct PredicateSchedule{F} <: AbstractSchedule
    predicate::F
end

should_run(::AlwaysSchedule, ctx::TrackingContext) = true
should_run(schedule::EveryNSteps, ctx::TrackingContext) =
    ctx.turn >= schedule.start &&
    ctx.turn < schedule.stop &&
    (ctx.turn - schedule.start) % schedule.step == 0
should_run(schedule::AtTurns, ctx::TrackingContext) = ctx.turn in schedule.turns
should_run(schedule::PredicateSchedule, ctx::TrackingContext) = Bool(schedule.predicate(ctx))

"""
    ScheduledObserver(observer, schedule=AlwaysSchedule())

Read-only tracking hook. When passed through `TrackingTask(...; hooks=...)`,
observers run after a turn finishes. When placed inside the element line,
observers run at that location in the line.
"""
struct ScheduledObserver{O<:AbstractBeamObserver,S<:AbstractSchedule}
    observer::O
    schedule::S
end
ScheduledObserver(observer::AbstractBeamObserver) =
    ScheduledObserver(observer, AlwaysSchedule())

"""
    ScheduledAction(action, schedule=AlwaysSchedule())

State-mutating tracking hook. When passed through `TrackingTask(...; hooks=...)`,
actions run before a turn starts. When placed inside the element line, actions
run at that location in the line.
"""
struct ScheduledAction{A<:AbstractBeamAction,S<:AbstractSchedule}
    action::A
    schedule::S
end
ScheduledAction(action::AbstractBeamAction) =
    ScheduledAction(action, AlwaysSchedule())

function run_observers!(observers, ctx::TrackingContext, rep)
    for raw in _hook_tuple(observers)
        item = _as_scheduled_observer(raw)
        if should_run(item.schedule, ctx)
            observe!(item.observer, ctx, rep)
        end
    end
    return nothing
end

function prepare_observers!(observers, runtime_elems; turns=nothing)
    for raw in _hook_tuple(observers)
        item = _as_scheduled_observer(raw)
        prepare_observer!(item.observer, runtime_elems, item.schedule, turns)
    end
    return nothing
end

prepare_observer!(observer::AbstractBeamObserver, runtime_elems) = nothing
prepare_observer!(observer::AbstractBeamObserver, runtime_elems, schedule, turns) =
    prepare_observer!(observer, runtime_elems)

function prepare_line_observers!(entries::Tuple; turns=nothing)
    for entry in entries
        if entry isa LineObserverEntry
            prepare_line_observer!(entry.observer, turns)
        end
    end
    return nothing
end

prepare_line_observer!(observer::ScheduledObserver, turns) =
    prepare_line_observer!(observer.observer, observer.schedule, turns)
prepare_line_observer!(observer::AbstractBeamObserver, schedule, turns) = nothing

function finalize_observers!(observers)
    for raw in _hook_tuple(observers)
        item = _as_scheduled_observer(raw)
        finalize_observer!(item.observer)
    end
    return nothing
end

finalize_observer!(observer::AbstractBeamObserver) = nothing

function requires_elementwise_tracking(observers)
    for raw in _hook_tuple(observers)
        item = _as_scheduled_observer(raw)
        requires_elementwise_tracking(item.observer) && return true
    end
    return false
end

function requires_elementwise_tracking(observers, ctx::TrackingContext)
    for raw in _hook_tuple(observers)
        item = _as_scheduled_observer(raw)
        should_run(item.schedule, ctx) || continue
        requires_elementwise_tracking(item.observer) && return true
    end
    return false
end

requires_elementwise_tracking(observer::AbstractBeamObserver) = false

function run_actions!(actions, ctx::TrackingContext, rep)
    for raw in _hook_tuple(actions)
        item = _as_scheduled_action(raw)
        if should_run(item.schedule, ctx)
            apply_action!(item.action, ctx, rep)
        end
    end
    return nothing
end

_hook_tuple(hooks::Tuple) = hooks
_hook_tuple(hooks::AbstractVector) = Tuple(hooks)
_hook_tuple(::Nothing) = ()
_hook_tuple(hook::ScheduledObserver) = (hook,)
_hook_tuple(hook::ScheduledAction) = (hook,)
_hook_tuple(hook::AbstractBeamObserver) = (hook,)
_hook_tuple(hook::AbstractBeamAction) = (hook,)

_as_scheduled_observer(item::ScheduledObserver) = item
_as_scheduled_observer(item::AbstractBeamObserver) = ScheduledObserver(item)
_as_scheduled_action(item::ScheduledAction) = item
_as_scheduled_action(item::AbstractBeamAction) = ScheduledAction(item)

function _next_line_hook_index!(hook_counter)
    hook_counter[] += 1
    return hook_counter[]
end

function _line_entry_or_nothing(observer::ScheduledObserver, hook_counter)
    return LineObserverEntry(observer, _next_line_hook_index!(hook_counter))
end
function _line_entry_or_nothing(observer::AbstractBeamObserver, hook_counter)
    return _line_entry_or_nothing(ScheduledObserver(observer), hook_counter)
end
function _line_entry_or_nothing(action::ScheduledAction, hook_counter)
    return LineActionEntry(action, _next_line_hook_index!(hook_counter))
end
function _line_entry_or_nothing(action::AbstractBeamAction, hook_counter)
    return _line_entry_or_nothing(ScheduledAction(action), hook_counter)
end

_line_entry_active(entry::LineObserverEntry, ctx) =
    should_run(entry.observer.schedule, ctx)
_line_entry_active(entry::LineActionEntry, ctx) =
    should_run(entry.action.schedule, ctx)
_line_entry_requires_diagnostics(entry::LineObserverEntry) =
    requires_elementwise_tracking(entry.observer.observer)
_line_entry_requires_diagnostics(entry::LineActionEntry) = false

function classify_task_hooks(hooks=(), actions=(), observers=())
    action_items = Any[]
    observer_items = Any[]
    for hook in _hook_tuple(hooks)
        _push_task_hook!(action_items, observer_items, hook)
    end
    for action in _hook_tuple(actions)
        _push_task_hook!(action_items, observer_items, action)
    end
    for observer in _hook_tuple(observers)
        _push_task_hook!(action_items, observer_items, observer)
    end
    return Tuple(action_items), Tuple(observer_items)
end

_push_task_hook!(actions, observers, hook::ScheduledAction) =
    push!(actions, hook)
_push_task_hook!(actions, observers, hook::AbstractBeamAction) =
    push!(actions, ScheduledAction(hook))
_push_task_hook!(actions, observers, hook::ScheduledObserver) =
    push!(observers, hook)
_push_task_hook!(actions, observers, hook::AbstractBeamObserver) =
    push!(observers, ScheduledObserver(hook))
function _push_task_hook!(actions, observers, hook)
    throw(ArgumentError("unsupported task hook type $(typeof(hook)); use ScheduledAction, ScheduledObserver, AbstractBeamAction, or AbstractBeamObserver"))
end

mutable struct BeamMomentObserver <: AbstractBeamObserver
    path::String
    buffer_capacity::Int
    buffer_turns::Vector{Float64}
    buffer::Vector{Vector{Float64}}
    record_count::Int
    initialized::Bool
end

"""
    BeamMomentObserver(path; capacity=1)

Write turn, means, upper-triangular covariance, and diagonal fourth central
moments to an Octopus compact binary moment-output file.
"""
function BeamMomentObserver(path::AbstractString; capacity::Integer=1)
    capacity >= 0 || throw(ArgumentError("capacity must be nonnegative"))
    return BeamMomentObserver(String(path), Int(capacity), Float64[], Vector{Float64}[], 0, false)
end

mutable struct JLD2BeamMomentObserver <: AbstractBeamObserver
    path::String
    buffer_capacity::Int
    buffer_turns::Vector{Float64}
    buffer::Vector{Any}
    record_count::Int
    initialized::Bool
end

"""
    Moment(p1, p2, p3, p4, p5, p6)
    Moment(; x=0, px=0, y=0, py=0, z=0, pz=0)
    Moment(name::Union{Symbol,AbstractString})

Multi-index identifier for a beam moment in six-dimensional phase space.
Coordinates are ordered as `(x, px, y, py, z, pz)`, and all powers must be
nonnegative integers.

Examples:

```julia
Moment(; x = 1)          # mean x
Moment(; px = 1)         # mean px
Moment(; x = 1, px = 1)  # central <(x-<x>)(px-<px>)>
Moment(; z = 2)          # central <(z-<z>)^2>
Moment(; pz = 4)         # central <(pz-<pz>)^4>
Moment(1, 0, 0, 0, 0, 0)
Moment(:m100000)
Moment("m1_0_0_0_0_0")
```

Moment convention:

- Order 1 moments are raw means.
- Order 2 and higher moments are central moments.
- `Moment(0, 0, 0, 0, 0, 0)` is ignored by `MomentObserver` selection.

The canonical column name is available with `name(moment)`, and the canonical
symbol with `symbol(moment)`.
"""
struct Moment
    powers::NTuple{6,Int}
    function Moment(powers::NTuple{6,Int})
        all(p -> p >= 0, powers) || throw(ArgumentError("moment powers must be nonnegative integers"))
        return new(powers)
    end
end

Moment(moment::Moment) = moment
Moment(powers::Vararg{Integer,6}) = Moment(ntuple(i -> Int(powers[i]), 6))
Moment(; x::Integer=0, px::Integer=0, y::Integer=0, py::Integer=0,
       z::Integer=0, pz::Integer=0) =
    Moment(Int(x), Int(px), Int(y), Int(py), Int(z), Int(pz))
Moment(name::Symbol) = Moment(String(name))
function Moment(raw::AbstractString)
    text = String(raw)
    startswith(text, "m") || throw(ArgumentError("moment name must start with `m`: $text"))
    body = text[2:end]
    isempty(body) && throw(ArgumentError("moment name has no powers: $text"))
    powers = if occursin('_', body)
        parts = split(body, '_')
        length(parts) == 6 || throw(ArgumentError("separated moment name must contain six powers: $text"))
        ntuple(i -> parse(Int, parts[i]), 6)
    else
        length(body) == 6 || throw(ArgumentError("compact moment name must contain six powers: $text"))
        ntuple(i -> parse(Int, body[i]), 6)
    end
    return Moment(powers)
end

Base.:(==)(a::Moment, b::Moment) = a.powers == b.powers
Base.hash(moment::Moment, h::UInt) = hash(moment.powers, h)
Base.isless(a::Moment, b::Moment) =
    (sum(a.powers), _moment_order_key(a.powers)) < (sum(b.powers), _moment_order_key(b.powers))
Base.show(io::IO, moment::Moment) = print(io, "Moment(", join(moment.powers, ", "), ")")

"""
    name(moment::Moment)

Return the canonical HDF5 column name for a moment.

Compact form is used when all powers are single digits:

```julia
name(Moment(; x = 1))       == "m100000"
name(Moment(; x = 1, px=1)) == "m110000"
name(Moment(; pz = 4))      == "m000004"
```

If any power is multi-digit, underscore-separated form is used without an
underscore after `m`:

```julia
name(Moment(; x = 10))       == "m10_0_0_0_0_0"
name(Moment(; x = 1, px=10)) == "m1_10_0_0_0_0"
```
"""
function name(moment::Moment)
    powers = moment.powers
    if all(p -> 0 <= p <= 9, powers)
        return "m" * join(string.(powers), "")
    end
    return "m" * join(string.(powers), "_")
end

"""
    symbol(moment::Moment)

Return `Symbol(name(moment))`.

```julia
symbol(Moment(; x = 1)) == :m100000
```
"""
symbol(moment::Moment) = Symbol(name(moment))

_moment_order_key(powers::NTuple{6,Int}) = ntuple(i -> -powers[i], 6)
_moment_order(moment::Moment) = sum(moment.powers)

function _normalize_orders(orders)
    out = Int[]
    _flatten_orders!(out, orders)
    filter!(>(0), out)
    return Tuple(sort!(unique!(out)))
end

function _flatten_orders!(out, order::Integer)
    push!(out, Int(order))
    return out
end

function _flatten_orders!(out, orders)
    for order in orders
        _flatten_orders!(out, order)
    end
    return out
end

function _moment_tuple(items)
    items === nothing && return ()
    items isa Moment && return (items,)
    items isa Union{AbstractString,Symbol} && return (Moment(items),)
    return Tuple(Moment(item) for item in items)
end

function _moments_for_order(order::Integer)
    order <= 0 && return Moment[]
    out = Moment[]
    powers = zeros(Int, 6)
    _append_moments_for_order!(out, powers, Int(order), 1)
    return out
end

function _append_moments_for_order!(out, powers, remaining::Int, dim::Int)
    if dim == 6
        powers[dim] = remaining
        push!(out, Moment(ntuple(i -> powers[i], 6)))
        return out
    end
    for p in remaining:-1:0
        powers[dim] = p
        _append_moments_for_order!(out, powers, remaining - p, dim + 1)
    end
    powers[dim] = 0
    return out
end

function _selected_moments(; orders=1:2, extra=(), exclude=())
    moments = Moment[]
    for order in _normalize_orders(orders)
        append!(moments, _moments_for_order(order))
    end
    append!(moments, _moment_tuple(extra))
    excluded = Set(_moment_tuple(exclude))
    moments = [moment for moment in unique(moments) if _moment_order(moment) > 0 && !(moment in excluded)]
    return Tuple(sort!(moments))
end

mutable struct MomentObserver <: AbstractBeamObserver
    path::String
    moments::Tuple
    column_names::Vector{String}
    buffer_capacity::Int
    buffer::Matrix{Float64}
    buffer_length::Int
    record_count::Int
    planned_records::Int
    start_time_ns::UInt64
    initialized::Bool
    reduction_scratch::Any
end

"""
    JLD2BeamMomentObserver(path; capacity=1)

Write beam statistics to a Julia-native JLD2 file.

The file uses a columnar layout:

- `data`: dense matrix with one row per observed turn. Column 1 is `turn`;
  the remaining columns are flattened beam statistics.

Column metadata is stored under `metadata/column_names` and
`metadata/ranges/<name>`. Turn is column 1 of `data`; no duplicate `turn`
dataset is stored. Use `read(MomentOutputFile(path), :emittance)` or
`read_moment(path, :emittance)` to extract named blocks without duplicating
datasets in the file.
"""
function JLD2BeamMomentObserver(path::AbstractString; capacity::Integer=1)
    capacity >= 0 || throw(ArgumentError("capacity must be nonnegative"))
    return JLD2BeamMomentObserver(String(path), Int(capacity), Float64[], Any[], 0, false)
end

"""
    MomentObserver(path; orders=1:2, extra=(), exclude=(), capacity=1024)

Write selected beam moments to an HDF5 table.

`MomentObserver` is a scheduled observer. Put it in a task line or task hooks
through `ScheduledObserver`. The observer writes one row per scheduled
observation. Column 1 is always `turn`; the remaining columns are selected
moments.

The HDF5 file contains:

- `/data`: dense numeric matrix. Column 1 is `turn`.
- `/column_names`: string names aligned with `/data` columns.
- `/record_count`: number of rows already flushed to disk.
- `/elapsed_time`: elapsed wall time in seconds, updated whenever the buffer is
  flushed.

`capacity` is the number of observed rows buffered in memory before a block is
written to HDF5. Larger values reduce I/O overhead. Smaller values update
`/record_count` and `/elapsed_time` more frequently for progress monitoring.
`capacity = 0` disables output.

Moment selection is:

```julia
selected = expand_orders(orders)
selected = union(selected, extra)
selected = setdiff(selected, exclude)
```

`exclude` wins. `turn` is always present and is not part of moment selection.
Column order is canonical and does not depend on user input order.
`orders` accepts integers, ranges, vectors, tuples, and nested combinations
such as `1:2`, `(1, 2)`, `(1:2, 3)`, or `()`.

Default output:

```julia
MomentObserver("moments.h5")
```

writes all first-order moments and all unique second-order central moments.
First-order moments are means. Moments of order 2 or higher are central moments.

Common examples:

```julia
obs = MomentObserver("moments.h5")
hook = ScheduledObserver(obs, EveryNSteps(start = 0, stop = 1000, step = 10))
task = TrackingTask((line..., hook))
execute!(task, beam; turns = 1000)
```

Select only first-order moments:

```julia
MomentObserver("mean_only.h5"; orders = 1)
```

Add a fourth-order longitudinal momentum moment:

```julia
MomentObserver("moments.h5";
    orders = 1:2,
    extra = (Moment(; pz = 4),),
)
```

Remove one default moment, for example the `z` variance:

```julia
MomentObserver("moments.h5";
    orders = 1:2,
    exclude = (Moment(; z = 2),),
)
```

Read output:

```julia
out = MomentOutputFile("moments.h5")
data = read(out)
turns = read(out, :turn)
mx = read(out, Moment(; x = 1))
sxpx = read(out, :m110000)
names = column_names(out)
records = read(out, :record_count)
seconds = read(out, :elapsed_time)
```

The observer requires a predictable schedule (`AlwaysSchedule`,
`EveryNSteps`, or `AtTurns`) so the HDF5 data matrix can be preallocated.
"""
function MomentObserver(path::AbstractString; orders=1:2, extra=(), exclude=(), capacity::Integer=1024)
    capacity >= 0 || throw(ArgumentError("capacity must be nonnegative"))
    moments = _selected_moments(orders=orders, extra=extra, exclude=exclude)
    names = ["turn"; collect(name.(moments))]
    buffer = Matrix{Float64}(undef, max(Int(capacity), 1), length(names))
    return MomentObserver(String(path), moments, names, Int(capacity), buffer, 0, 0, 0, UInt64(0), false, nothing)
end

mutable struct CoordinateSnapshotObserver <: AbstractBeamObserver
    path::String
    npart::Union{Nothing,Int}
    append::Bool
end

"""
    CoordinateSnapshotObserver(path; npart=nothing, append=true)

Write coordinate snapshots in the Octopus compact coordinate record format.
"""
function CoordinateSnapshotObserver(path::AbstractString; npart=nothing, append::Bool=true)
    return CoordinateSnapshotObserver(String(path), npart === nothing ? nothing : Int(npart), append)
end

mutable struct LuminosityObserver <: AbstractBeamObserver
    path::String
    elements::Tuple
    initialized::Bool
end

"""
    LuminosityObserver(path)

Write one row per observed turn: turn number followed by positive luminosity
values reported by runtime beam-beam elements in the task line.

This observer requests diagnostic tracking. `TrackingTask` then keeps ordinary
line segments fused while isolating beam-beam runtime elements so they can
update their `last_luminosity` field.
"""
LuminosityObserver(path::AbstractString) = LuminosityObserver(String(path), (), false)

struct BeamSwapAction{F} <: AbstractBeamAction
    provider::F
end

"""
    BeamSwapAction(provider)

Replace the current representation with the `Phase6DRep` or `Beam` returned by
`provider(ctx)`. If `provider` accepts no arguments, it is called as
`provider()`.
"""

function observe!(observer::BeamMomentObserver, ctx::TrackingContext, rep)
    observer.buffer_capacity == 0 && return nothing
    observer.initialized || _initialize_moment_file!(observer)
    push!(observer.buffer_turns, Float64(ctx.turn))
    push!(observer.buffer, _moment_output_row(beam_statistics(rep; diagonal_fourth=true)))
    length(observer.buffer) >= observer.buffer_capacity && _flush_moment_buffer!(observer)
    return nothing
end

function observe!(observer::JLD2BeamMomentObserver, ctx::TrackingContext, rep)
    observer.buffer_capacity == 0 && return nothing
    observer.initialized || _initialize_jld2_moment_file!(observer)
    push!(observer.buffer_turns, Float64(ctx.turn))
    push!(observer.buffer, beam_statistics(rep; diagonal_fourth=true))
    length(observer.buffer) >= observer.buffer_capacity && _flush_jld2_moment_buffer!(observer)
    return nothing
end

function observe!(observer::MomentObserver, ctx::TrackingContext, rep)
    observer.buffer_capacity == 0 && return nothing
    observer.initialized || throw(ArgumentError("MomentObserver must be prepared by a predictable schedule before tracking"))
    observer.buffer_length += 1
    observer.buffer[observer.buffer_length, :] .= _moment_observer_row(ctx, rep, observer.moments, observer)
    observer.buffer_length >= observer.buffer_capacity && _flush_moment_observer!(observer)
    return nothing
end

function observe!(observer::CoordinateSnapshotObserver, ctx::TrackingContext, rep)
    npart = observer.npart === nothing ? length(rep) : observer.npart
    write_beam_coordinates(observer.path, rep; npart=npart, append=observer.append)
    observer.append = true
    return nothing
end

function observe!(observer::LuminosityObserver, ctx::TrackingContext, rep)
    mode = observer.initialized ? "a" : "w"
    open(observer.path, mode) do io
        print(io, ctx.turn, '\t')
        for elem in observer.elements
            lum = luminosity(elem, ctx, rep)
            lum > 0.0 && print(io, lum, '\t')
        end
        print(io, '\n')
    end
    observer.initialized = true
    return nothing
end

function prepare_observer!(observer::LuminosityObserver, runtime_elems)
    observer.elements = runtime_elems
    return nothing
end

function prepare_observer!(observer::MomentObserver, runtime_elems, schedule, turns)
    _prepare_moment_observer!(observer, schedule, turns)
    return nothing
end

function prepare_line_observer!(observer::MomentObserver, schedule, turns)
    _prepare_moment_observer!(observer, schedule, turns)
    return nothing
end

requires_elementwise_tracking(::LuminosityObserver) = true

function apply_action!(action::BeamSwapAction, ctx::TrackingContext, rep)
    replacement = _call_provider(action.provider, ctx)
    replacement_rep = replacement isa Beam ? replacement.rep : replacement
    _copy_rep!(rep, replacement_rep)
    return nothing
end

function _call_provider(provider, ctx)
    return applicable(provider, ctx) ? provider(ctx) : provider()
end

function _moment_output_row(stats)
    row = Float64[]
    append!(row, Float64.(stats.mean))
    for i in 1:6, j in i:6
        push!(row, Float64(stats.covariance[i, j]))
    end
    append!(row, Float64.(stats.diagonal_fourth_central))
    return row
end

function _initialize_moment_file!(observer::BeamMomentObserver)
    fmt = "turn"
    for i in 1:6
        fmt *= ",mu$i"
    end
    for i in 1:6, j in i:6
        fmt *= ",sigma$i$j"
    end
    for i in 1:6
        fmt *= ",kappa$i"
    end
    open(observer.path, "w") do io
        write(io, Int32(0))
        write(io, Int32(sizeof(fmt)))
        write(io, codeunits(fmt))
    end
    observer.initialized = true
    return nothing
end

function _flush_moment_buffer!(observer::BeamMomentObserver)
    isempty(observer.buffer) && return nothing
    open(observer.path, "r+") do io
        observer.record_count += length(observer.buffer)
        seekstart(io)
        write(io, Int32(observer.record_count))
        seekend(io)
        for (turn, row) in zip(observer.buffer_turns, observer.buffer)
            write(io, Float64(turn))
            write(io, Float64.(row))
        end
    end
    empty!(observer.buffer_turns)
    empty!(observer.buffer)
    return nothing
end

finalize_observer!(observer::BeamMomentObserver) =
    _flush_moment_buffer!(observer)

function _initialize_jld2_moment_file!(observer::JLD2BeamMomentObserver)
    JLD2.jldopen(observer.path, "w") do file
        file["metadata/format"] = "Octopus.JLD2BeamMomentObserver"
        file["metadata/layout"] = "columnar_v2"
        file["metadata/labels"] = ["x", "px", "y", "py", "z", "pz"]
        file["metadata/covariance_layout"] = "full_6x6"
        file["metadata/column_names"] = _jld2_moment_column_names()
        for (name, range) in pairs(_jld2_moment_ranges())
            file["metadata/ranges/$(name)"] = collect(range)
        end
        file["record_count"] = Int64(0)
    end
    observer.initialized = true
    return nothing
end

function _flush_jld2_moment_buffer!(observer::JLD2BeamMomentObserver)
    isempty(observer.buffer) && return nothing
    JLD2.jldopen(observer.path, "r+") do file
        _append_jld2_moment_columns!(file, observer)
    end
    empty!(observer.buffer_turns)
    empty!(observer.buffer)
    return nothing
end

finalize_observer!(observer::JLD2BeamMomentObserver) =
    _flush_jld2_moment_buffer!(observer)

finalize_observer!(observer::MomentObserver) =
    _flush_moment_observer!(observer)

function _prepare_moment_observer!(observer::MomentObserver, schedule, turns)
    observer.buffer_capacity == 0 && return nothing
    observer.initialized && return nothing
    planned_turns = _scheduled_turns(schedule, turns)
    planned_turns === nothing && throw(ArgumentError(
        "MomentObserver requires a predictable schedule: use AlwaysSchedule, EveryNSteps, or AtTurns with known task turns."
    ))
    observer.planned_records = length(planned_turns)
    observer.record_count = 0
    observer.buffer_length = 0
    observer.start_time_ns = time_ns()
    _initialize_hdf5_moment_file!(observer)
    observer.initialized = true
    return nothing
end

function _scheduled_turns(::AlwaysSchedule, turns)
    turns === nothing && return nothing
    return collect(0:(Int(turns) - 1))
end

function _scheduled_turns(schedule::EveryNSteps, turns)
    turns === nothing && return nothing
    stop = min(schedule.stop, Int(turns))
    schedule.start >= stop && return Int[]
    return [turn for turn in schedule.start:schedule.step:(stop - 1) if 0 <= turn < Int(turns)]
end

function _scheduled_turns(schedule::AtTurns, turns)
    turns === nothing && return nothing
    return sort!([turn for turn in schedule.turns if 0 <= turn < Int(turns)])
end

_scheduled_turns(schedule::PredicateSchedule, turns) = nothing

function _initialize_hdf5_moment_file!(observer::MomentObserver)
    HDF5.h5open(observer.path, "w") do file
        file["data"] = zeros(Float64, observer.planned_records, length(observer.column_names))
        file["column_names"] = observer.column_names
        file["record_count"] = Int64[0]
        file["elapsed_time"] = Float64[0.0]
        HDF5.flush(file)
    end
    return nothing
end

function _flush_moment_observer!(observer::MomentObserver)
    observer.buffer_length == 0 && return nothing
    row1 = observer.record_count + 1
    row2 = observer.record_count + observer.buffer_length
    row2 <= observer.planned_records || throw(BoundsError("MomentObserver received more records than planned"))
    HDF5.h5open(observer.path, "r+") do file
        file["data"][row1:row2, :] = observer.buffer[1:observer.buffer_length, :]
        file["record_count"][1] = Int64(row2)
        elapsed = (time_ns() - observer.start_time_ns) / 1.0e9
        file["elapsed_time"][1] = Float64(elapsed)
        HDF5.flush(file)
    end
    observer.record_count = row2
    observer.buffer_length = 0
    return nothing
end

function _moment_observer_row(ctx::TrackingContext, rep, moments::Tuple, observer=nothing)
    row = Vector{Float64}(undef, length(moments) + 1)
    row[1] = Float64(ctx.turn)
    isempty(moments) && return row
    arrays = map(collect, coordinate_arrays(rep))
    means = ntuple(i -> Float64(sum(arrays[i]) / length(arrays[i])), 6)
    for (j, moment) in enumerate(moments)
        row[j + 1] = _compute_moment(arrays, means, moment)
    end
    return row
end

if _HAS_CUDA
    @eval begin
        function _moment_observer_row(ctx::TrackingContext,
                                      rep::Phase6DRep{<:CUDA.CuArray}, moments::Tuple,
                                      observer::MomentObserver)
            get(ENV, "OCTOPUS_CUDA_MOMENT_REDUCTION", "1") in
                ("1", "true", "TRUE", "yes", "YES") ||
                return _moment_observer_row(ctx, Phase6DRep(map(Array, coordinate_arrays(rep))...), moments)
            row = Vector{Float64}(undef, length(moments) + 1)
            row[1] = Float64(ctx.turn)
            isempty(moments) && return row
            arrays = coordinate_arrays(rep)
            n = length(arrays[1])
            means = ntuple(i -> Float64(sum(arrays[i]) / n), 6)
            scratch = observer.reduction_scratch
            if !(scratch isa CUDA.CuArray) || length(scratch) != n || eltype(scratch) != eltype(arrays[1])
                scratch = similar(arrays[1])
                observer.reduction_scratch = scratch
            end
            for (j, moment) in enumerate(moments)
                row[j + 1] = _cuda_compute_moment!(scratch, arrays, means, moment)
            end
            return row
        end

        function _cuda_compute_moment!(scratch, arrays, means, moment::Moment)
            powers = moment.powers
            order = sum(powers)
            order == 1 && return means[findfirst(!=(0), powers)]
            fill!(scratch, one(eltype(scratch)))
            for d in 1:6
                p = powers[d]
                p == 0 && continue
                if p == 1
                    scratch .= scratch .* (arrays[d] .- means[d])
                elseif p == 2
                    scratch .= scratch .* (arrays[d] .- means[d]) .^ 2
                else
                    scratch .= scratch .* (arrays[d] .- means[d]) .^ p
                end
            end
            return Float64(sum(scratch) / length(scratch))
        end
    end
end

function _compute_moment(arrays, means, moment::Moment)
    powers = moment.powers
    order = sum(powers)
    order == 1 && return means[findfirst(!=(0), powers)]
    n = length(arrays[1])
    acc = 0.0
    @inbounds for i in 1:n
        term = 1.0
        for d in 1:6
            p = powers[d]
            p == 0 && continue
            term *= (arrays[d][i] - means[d]) ^ p
        end
        acc += term
    end
    return acc / n
end

function _jld2_moment_column_names()
    labels = ["x", "px", "y", "py", "z", "pz"]
    names = String["turn"]
    append!(names, ["mean_$label" for label in labels])
    append!(names, ["cov_$(labels[i])_$(labels[j])" for i in 1:6 for j in 1:6])
    append!(names, ["rms_$label" for label in labels])
    append!(names, ["emit_x", "emit_y", "emit_z"])
    push!(names, "xz_covariance")
    push!(names, "yz_covariance")
    append!(names, ["diagonal_fourth_$label" for label in labels])
    return names
end

function _append_jld2_moment_columns!(file, observer::JLD2BeamMomentObserver)
    new_turn = Float64.(observer.buffer_turns)
    new_mean = _rows_matrix(stats -> stats.mean, observer.buffer, 6)
    new_covariance = _rows_covariance(observer.buffer)
    new_rms = _rows_matrix(stats -> stats.rms, observer.buffer, 6)
    new_emittance = _rows_matrix(stats -> stats.emittance, observer.buffer, 3)
    new_xz = Float64[stats.xz_covariance for stats in observer.buffer]
    new_yz = Float64[stats.yz_covariance for stats in observer.buffer]
    new_fourth = _rows_matrix(stats -> stats.diagonal_fourth_central, observer.buffer, 6)
    new_data = _jld2_moment_data_matrix(
        new_turn, new_mean, new_covariance, new_rms, new_emittance, new_xz, new_yz, new_fourth,
    )

    data = _jld2_read_or_empty(file, "data", zeros(Float64, 0, length(_jld2_moment_column_names())))

    data = vcat(data, new_data)

    observer.record_count = size(data, 1)
    _jld2_replace!(file, "data", data)
    _jld2_replace!(file, "record_count", Int64(observer.record_count))
    return nothing
end

_jld2_read_or_empty(file, key::AbstractString, default) =
    haskey(file, key) ? file[key] : default

function _jld2_replace!(file, key::AbstractString, value)
    haskey(file, key) && delete!(file, key)
    file[key] = value
    return nothing
end

function _rows_matrix(getter, stats_buffer, width::Integer)
    out = Matrix{Float64}(undef, length(stats_buffer), width)
    for (i, stats) in pairs(stats_buffer)
        out[i, :] .= Float64.(getter(stats))
    end
    return out
end

function _rows_covariance(stats_buffer)
    out = Array{Float64}(undef, length(stats_buffer), 6, 6)
    for (i, stats) in pairs(stats_buffer)
        out[i, :, :] .= Float64.(stats.covariance)
    end
    return out
end

function _jld2_moment_ranges()
    return (
        turn = 1:1,
        mean = 2:7,
        covariance = 8:43,
        rms = 44:49,
        emittance = 50:52,
        xz_covariance = 53:53,
        yz_covariance = 54:54,
        diagonal_fourth_central = 55:60,
    )
end

function _jld2_moment_data_matrix(turn, mean, covariance, rms, emittance, xz, yz, fourth)
    n = length(turn)
    data = Matrix{Float64}(undef, n, length(_jld2_moment_column_names()))
    col = 1
    data[:, col] .= turn; col += 1
    data[:, col:(col + 5)] .= mean; col += 6
    data[:, col:(col + 35)] .= reshape(covariance, n, 36); col += 36
    data[:, col:(col + 5)] .= rms; col += 6
    data[:, col:(col + 2)] .= emittance; col += 3
    data[:, col] .= xz; col += 1
    data[:, col] .= yz; col += 1
    data[:, col:(col + 5)] .= fourth
    return data
end

"""
    MomentOutputFile(path)

Lightweight handle for reading a `MomentObserver` output file.

For HDF5 files written by `MomentObserver`, `read(file)` returns the full
written `/data` matrix up to `/record_count`. Use `read(file, item)` for one
column and keyword moment selection for a smaller matrix.

```julia
out = MomentOutputFile("result/pic_hcc.h5")

data = read(out)
turn = read(out, :turn)
mx = read(out, Moment(; x = 1))
sxpx = read(out, :m110000)
first_second = read(out; orders = 1:2)
names = column_names(out)
records = read(out, :record_count)
seconds = read(out, :elapsed_time)
```

`MomentOutputFile` is the preferred reader for `MomentObserver` HDF5 files.
`OutputFile` and `MomentFile` remain compatibility aliases.
"""
struct MomentOutputFile
    path::String
end

MomentOutputFile(path::AbstractString) = MomentOutputFile(String(path))

const OutputFile = MomentOutputFile
const MomentFile = MomentOutputFile

const _READ_ALL_MOMENT_COLUMNS = :__octopus_read_all_moment_columns__

"""
    read(file::MomentOutputFile)
    read(file::MomentOutputFile; orders=..., extra=(), exclude=())

Read an output data matrix.

With no keyword selection, this returns the full written data matrix
`/data[1:record_count, :]`. Column 1 is `turn`, and the remaining columns match
`column_names(file)`.

With `orders`, `extra`, or `exclude`, this returns a selected HDF5 moment table.
The returned matrix still includes `turn` as column 1. Selection uses the same
rules as `MomentObserver`: expand `orders`, add `extra`, then remove `exclude`.
Unavailable requested moments are skipped.

```julia
out = MomentOutputFile("moments.h5")
data = read(out)
names = column_names(out)

first_order = read(out; orders = 1)
first_second = read(out; orders = 1:2)
selected = read(out; orders = (), extra = (Moment(; pz = 4),))
without_z2 = read(out; orders = 1:2, exclude = (Moment(; z = 2),))
```
"""
function read(file::MomentOutputFile; orders=_READ_ALL_MOMENT_COLUMNS, extra=(), exclude=())
    if !_is_hdf5_output(file.path)
        orders === _READ_ALL_MOMENT_COLUMNS && isempty(extra) && isempty(exclude) && return read_moment(file.path, :data)
        throw(ArgumentError("keyword moment selection is only supported for HDF5 output files"))
    end
    if orders === _READ_ALL_MOMENT_COLUMNS && isempty(extra) && isempty(exclude)
        return _read_hdf5_data(file.path)
    end
    return _read_hdf5_selection(file.path; orders=orders, extra=extra, exclude=exclude)
end

"""
    read(file::MomentOutputFile, item)

Read one named output column or progress field.

For HDF5 moment output, `item` may be:

- `:turn` or `"turn"`
- a `Moment`, such as `Moment(; x=1)`
- a compact or separated moment name, such as `:m100000` or `:m1_0_0_0_0_0`
- `:record_count`
- `:elapsed_time`

Examples:

```julia
out = MomentOutputFile("moments.h5")
turns = read(out, :turn)
mx = read(out, Moment(; x = 1))
sxpx = read(out, :m110000)
records = read(out, :record_count)
seconds = read(out, :elapsed_time)
```
"""
function read(file::MomentOutputFile, item::Union{Moment,Symbol,AbstractString})
    _is_hdf5_output(file.path) && return _read_hdf5_column(file.path, item)
    item isa Symbol && return read_moment(file.path, item)
    item isa AbstractString && return read_moment(file.path, Symbol(item))
    return read_moment(file.path, Symbol(name(item)))
end

"""
    column_names(file::MomentOutputFile)

Return output column names as strings.

For `MomentObserver` HDF5 files, this reads `/column_names`. The returned names
align with columns of `read(file)`.

```julia
out = MomentOutputFile("moments.h5")
data = read(out)
names = column_names(out)

names[1] == "turn"
```

This is useful for table conversion:

```julia
using DataFrames
df = DataFrame(data, Symbol.(names))
```
"""
function column_names(file::MomentOutputFile)
    if _is_hdf5_output(file.path)
        return HDF5.h5open(file.path, "r") do h5
            String.(read(h5["column_names"]))
        end
    end
    return JLD2.jldopen(file.path, "r") do jld
        String.(jld["metadata/column_names"])
    end
end

_is_hdf5_output(path::AbstractString) =
    lowercase(splitext(String(path))[2]) in (".h5", ".hdf5")

function _read_hdf5_record_count(h5)
    count = read(h5["record_count"])
    return count isa AbstractArray ? Int(first(count)) : Int(count)
end

function _read_hdf5_data(path::AbstractString)
    return HDF5.h5open(path, "r") do h5
        n = _read_hdf5_record_count(h5)
        data = read(h5["data"])
        data[1:n, :]
    end
end

function _read_hdf5_column(path::AbstractString, item)
    return HDF5.h5open(path, "r") do h5
        special = _read_hdf5_special(h5, item)
        special === _NOT_HDF5_SPECIAL || return special
        names = String.(read(h5["column_names"]))
        index = _hdf5_column_index(names, item)
        n = _read_hdf5_record_count(h5)
        vec(h5["data"][1:n, index])
    end
end

const _NOT_HDF5_SPECIAL = :__octopus_not_hdf5_special__

function _read_hdf5_special(h5, item)
    item isa Union{Symbol,AbstractString} || return _NOT_HDF5_SPECIAL
    key = String(item)
    if key == "record_count"
        return _read_hdf5_record_count(h5)
    elseif key == "elapsed_time"
        haskey(h5, "elapsed_time") || throw(ArgumentError(
            "`elapsed_time` is not present in this output file. " *
            "Recreate the file with the current MomentObserver to monitor elapsed wall time."
        ))
        return Float64(first(read(h5["elapsed_time"])))
    end
    return _NOT_HDF5_SPECIAL
end

function _read_hdf5_selection(path::AbstractString; orders=(), extra=(), exclude=())
    requested = _selected_moments(orders=orders, extra=extra, exclude=exclude)
    return HDF5.h5open(path, "r") do h5
        names = String.(read(h5["column_names"]))
        name_to_index = Dict(name => i for (i, name) in pairs(names))
        cols = Int[1]
        for moment in requested
            idx = get(name_to_index, name(moment), nothing)
            idx === nothing && continue
            push!(cols, idx)
        end
        n = _read_hdf5_record_count(h5)
        data = h5["data"][1:n, :]
        data[:, cols]
    end
end

function _hdf5_column_index(names::Vector{String}, item::Moment)
    idx = findfirst(==(name(item)), names)
    idx === nothing && throw(KeyError(name(item)))
    return idx
end

function _hdf5_column_index(names::Vector{String}, item::Symbol)
    item === :turn && return _hdf5_column_index(names, "turn")
    return _hdf5_column_index(names, String(item))
end

function _hdf5_column_index(names::Vector{String}, item::AbstractString)
    key = String(item)
    normalized = key == "turn" ? key : name(Moment(key))
    idx = findfirst(==(normalized), names)
    idx === nothing && throw(KeyError(key))
    return idx
end

"""
    read_moment(file_or_path, name)

Read a named moment block from a columnar `JLD2BeamMomentObserver` file without
duplicating datasets on disk.

Prefer `read(MomentOutputFile(path))` for new code. `read_moment` is kept as a
compatibility alias and for callers that already have an open JLD2 file handle.

Supported names are `:turn`, `:data`, `:mean`, `:covariance`, `:rms`,
`:emittance`, `:xz_covariance`, `:yz_covariance`, and
`:diagonal_fourth_central`.
"""
function read_moment(path::AbstractString, name::Symbol)
    return JLD2.jldopen(path, "r") do file
        read_moment(file, name)
    end
end

function read_moment(file, name::Symbol)
    name === :data && return file["data"]
    range_key = "metadata/ranges/$(name)"
    haskey(file, range_key) || throw(KeyError(name))
    data = file["data"]
    cols = file[range_key]
    block = data[:, cols]
    name === :covariance && return reshape(block, size(block, 1), 6, 6)
    return size(block, 2) == 1 ? vec(block) : block
end

function _copy_rep!(dest, src)
    length(dest) == length(src) || throw(DimensionMismatch("replacement beam length does not match destination"))
    for (d, s) in zip(coordinate_arrays(dest), coordinate_arrays(src))
        d .= s
    end
    return dest
end
