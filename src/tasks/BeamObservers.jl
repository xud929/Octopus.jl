import Base: read

export AbstractSchedule, AbstractBeamObserver, AbstractBeamAction,
       AlwaysSchedule, EveryNSteps, AtTurns, PredicateSchedule,
       should_run, ScheduledObserver, ScheduledAction,
       schedule_option_schema, observer_option_schema,
       Moment, name, symbol, column_names,
       BeamMomentObserver, JLD2BeamMomentObserver, MomentObserver,
       CoordinateSnapshotObserver, LuminosityObserver, BeamSwapAction,
       observe!, apply_action!, run_observers!, run_actions!,
       prepare_observers!, prepare_line_observers!,
       finalize_observers!, requires_elementwise_tracking,
       MomentOutputFile, OutputFile, MomentFile, read_moment

"""
Turn gate for a scheduled observer or action. A subtype implements
`should_run(schedule, ctx::TrackingContext) -> Bool`; one with configurable
fields also provides `schedule_option_schema`.
"""
abstract type AbstractSchedule end

"""
Read-only tracking hook. A subtype must implement
`observe!(observer, ctx::TrackingContext, rep)`; it may also extend the no-op
lifecycle fallbacks `prepare_observer!`, `prepare_line_observer!`,
`finalize_observer!`, and `requires_elementwise_tracking`, and provide
`observer_option_schema` / `configuration_report` for the configuration
metadata checks.
"""
abstract type AbstractBeamObserver end

"""
State-mutating tracking hook. A subtype must implement
`apply_action!(action, ctx::TrackingContext, rep)`.
"""
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

"""
    should_run(schedule, ctx::TrackingContext) -> Bool

Whether a scheduled hook is active on the absolute turn in `ctx`. Implemented
by every `AbstractSchedule` subtype; `run_observers!` and `run_actions!`
consult it before running each hook.
"""
function should_run end

should_run(::AlwaysSchedule, ctx::TrackingContext) = true
should_run(schedule::EveryNSteps, ctx::TrackingContext) =
    ctx.turn >= schedule.start &&
    ctx.turn < schedule.stop &&
    (ctx.turn - schedule.start) % schedule.step == 0
should_run(schedule::AtTurns, ctx::TrackingContext) = ctx.turn in schedule.turns
should_run(schedule::PredicateSchedule, ctx::TrackingContext) = Bool(schedule.predicate(ctx))

"""
    schedule_option_schema(schedule_or_type)

The schedule type's configurable fields as a `NamedTuple` of
`ConfigurationOptionMeta`. Consumed by `configuration_report` and checked by
`validate_configuration_metadata()`.
"""
function schedule_option_schema end

schedule_option_schema(::Type{AlwaysSchedule}) = NamedTuple()
schedule_option_schema(::AlwaysSchedule) = NamedTuple()
const _EVERY_N_STEPS_OPTION_SCHEMA = (
    start=ConfigurationOptionMeta(Int, 0, "First eligible turn.";
        category=:diagnostic, consumer=:hook_schedule),
    stop=ConfigurationOptionMeta(Int, typemax(Int), "Exclusive final eligible turn.";
        category=:diagnostic, consumer=:hook_schedule),
    step=ConfigurationOptionMeta(Int, 1, "Turn interval between observations/actions.";
        category=:diagnostic, consumer=:hook_schedule),
)
schedule_option_schema(::Type{EveryNSteps}) = _EVERY_N_STEPS_OPTION_SCHEMA
schedule_option_schema(::EveryNSteps) = _EVERY_N_STEPS_OPTION_SCHEMA
schedule_option_schema(::Type{AtTurns}) = (
    turns=ConfigurationOptionMeta(Set{Int}, Set{Int}(), "Explicit observed/action turns.";
        category=:diagnostic, consumer=:hook_schedule),)
schedule_option_schema(::AtTurns) = schedule_option_schema(AtTurns)
schedule_option_schema(::Type{<:PredicateSchedule}) = (
    predicate=ConfigurationOptionMeta(Function, nothing, "User predicate evaluated for each turn.";
        category=:diagnostic, consumer=:hook_schedule),)
schedule_option_schema(::PredicateSchedule) = schedule_option_schema(typeof(PredicateSchedule(identity)))

function configuration_report(schedule::AbstractSchedule)
    return Tuple(ConfigurationEntry(name, getproperty(schedule, name), getproperty(schedule, name),
        :resolved, "validated schedule configuration", meta.consumer)
        for (name, meta) in pairs(schedule_option_schema(schedule)))
end

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

"""
    observe!(observer, ctx::TrackingContext, rep)

Record one measurement of the particle representation `rep`. The one method
every `AbstractBeamObserver` subtype must implement. Called through
`run_observers!` when the observer's schedule is active: after the turn for
task-level observers, at the observer's line position for in-line placements.
"""
function observe! end

"""
    apply_action!(action, ctx::TrackingContext, rep)

Mutate the particle representation `rep`. The one method every
`AbstractBeamAction` subtype must implement. Called through `run_actions!`
when the action's schedule is active.
"""
function apply_action! end

"""
    run_observers!(observers, ctx::TrackingContext, rep)

Call `observe!` for every observer whose schedule is active on `ctx.turn`.
`execute!` runs this after each tracked turn; each hook's active/inactive
decision is logged as a `:hook_schedule` execution record.
"""
function run_observers!(observers, ctx::TrackingContext, rep)
    for raw in _hook_tuple(observers)
        item = _as_scheduled_observer(raw)
        active = should_run(item.schedule, ctx)
        policy = _ACTIVE_RESOLVED_POLICY[]
        backend = policy isa AbstractResolvedExecutionPolicy ? backend_type(policy) : :unknown
        _record_execution!(:hook_schedule, backend,
            (kind=:observer, observer=Symbol(nameof(typeof(item.observer))),
             schedule=Symbol(nameof(typeof(item.schedule))), turn=ctx.turn, active=active))
        if active
            observe!(item.observer, ctx, rep)
        end
    end
    return nothing
end

"""
    prepare_observers!(observers, runtime_elems; turns=nothing, first_turn=0)

Call `prepare_observer!` for every task-level observer. `execute!` runs this
before the turn loop; `first_turn` is the absolute turn the coming window
starts at, which lets an observer discard readings from a replayed window.
"""
function prepare_observers!(observers, runtime_elems; turns=nothing, first_turn=0)
    for raw in _hook_tuple(observers)
        item = _as_scheduled_observer(raw)
        prepare_observer!(item.observer, runtime_elems, item.schedule, turns, first_turn)
    end
    return nothing
end

prepare_observer!(observer::AbstractBeamObserver, runtime_elems) = nothing
prepare_observer!(observer::AbstractBeamObserver, runtime_elems, schedule, turns) =
    prepare_observer!(observer, runtime_elems)
prepare_observer!(observer::AbstractBeamObserver, runtime_elems, schedule, turns,
                  first_turn) = prepare_observer!(observer, runtime_elems, schedule, turns)

"""
    prepare_line_observers!(entries::Tuple; turns=nothing, first_turn=0)

Call `prepare_line_observer!` for every in-line observer entry. `execute!`
runs this next to `prepare_observers!`, before the turn loop.
"""
function prepare_line_observers!(entries::Tuple; turns=nothing, first_turn=0)
    for entry in entries
        if entry isa LineObserverEntry
            prepare_line_observer!(entry.observer, turns, first_turn)
        end
    end
    return nothing
end

prepare_line_observer!(observer::ScheduledObserver, turns) =
    prepare_line_observer!(observer.observer, observer.schedule, turns)
prepare_line_observer!(observer::ScheduledObserver, turns, first_turn) =
    prepare_line_observer!(observer.observer, observer.schedule, turns, first_turn)
# NOTE: do not add a `(::AbstractBeamObserver, turns, first_turn)` method here.
# It has the same signature as the `(observer, schedule, turns)` one above --
# both lower to `(::AbstractBeamObserver, ::Any, ::Any)` -- so it silently
# OVERWRITES it and makes the module fail to precompile. The three-argument call
# from `prepare_line_observers!` lands on this method for any non-scheduled
# observer and correctly returns nothing.
prepare_line_observer!(observer::AbstractBeamObserver, schedule, turns) = nothing
prepare_line_observer!(observer::AbstractBeamObserver, schedule, turns, first_turn) =
    prepare_line_observer!(observer, schedule, turns)

# Every observer gets its finalize even when an earlier one throws: a
# finalizer is where buffered measurements reach disk, and one broken observer
# must not silently discard every later observer's output (audit part 7, T7).
# The first error is rethrown once the rest have run.
"""
    finalize_observers!(observers)

Call `finalize_observer!` on every task-level observer. `execute!` runs this
once the turn loop ends, including when it throws. Every observer is
finalized even when an earlier finalizer fails; the first error is rethrown
once the rest have run.
"""
function finalize_observers!(observers)
    first_error = nothing
    for raw in _hook_tuple(observers)
        item = _as_scheduled_observer(raw)
        try
            finalize_observer!(item.observer)
        catch e
            first_error === nothing && (first_error = e)
        end
    end
    first_error === nothing || throw(first_error)
    return nothing
end

finalize_observer!(observer::AbstractBeamObserver) = nothing

"""
    requires_elementwise_tracking(observer_or_observers[, ctx])

Whether tracking must keep per-element boundaries instead of fusing the line.
The single-observer fallback is `false`; an observer that needs per-element
diagnostics (e.g. `LuminosityObserver`) returns `true`. The `ctx` form only
counts observers whose schedule is active on `ctx.turn`, and `execute!` uses
it to pick each turn's tracking plan.
"""
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

"""
    run_actions!(actions, ctx::TrackingContext, rep)

Call `apply_action!` for every action whose schedule is active on `ctx.turn`.
`execute!` runs this before each tracked turn, so an action sees the beam as
the turn starts; each hook's active/inactive decision is logged as a
`:hook_schedule` execution record.
"""
function run_actions!(actions, ctx::TrackingContext, rep)
    for raw in _hook_tuple(actions)
        item = _as_scheduled_action(raw)
        active = should_run(item.schedule, ctx)
        policy = _ACTIVE_RESOLVED_POLICY[]
        backend = policy isa AbstractResolvedExecutionPolicy ? backend_type(policy) : :unknown
        _record_execution!(:hook_schedule, backend,
            (kind=:action, action=Symbol(nameof(typeof(item.action))),
             schedule=Symbol(nameof(typeof(item.schedule))), turn=ctx.turn, active=active))
        if active
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
    append::Bool
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
    MomentObserver(path; orders=1:2, extra=(), exclude=(), capacity=1024, append=false)

Write selected beam moments to an HDF5 table.

With the default `append=false`, re-executing a task prepares a **fresh**
table at `path`: output from the previous execution is replaced. With
`append=true` the table is created chunked/extendible and every execution
**continues** it — a run split across `execute!` calls on one task object,
or an injection swap-out passing a new beam to that same task, produces one
file with continuous absolute turns automatically; a second task sharing the
path or a fresh process restarting a chunked run continues it **when
`execute!` is given the matching absolute `start_turn`** (the file keeps the
rows, but the resume point is the caller's — a fresh task with no
`start_turn` executes from absolute turn 0 and therefore replaces the
recorded timeline, with one warning naming the `start_turn` remedy).
Replayed turn windows (a failed `execute!`'s retry, an explicit `start_turn`
rewind) drop their stale rows first, so the table never carries two rows for
one turn. The two modes' files differ in HDF5 layout (contiguous vs
chunked); an `append=true` observer refuses to continue a replace-mode file
rather than corrupt it, and replaces a zero-byte leftover (a crash at create
time) fresh. `/elapsed_time` always reports the current execution's wall
time.

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
With `append=false` (the default), re-executing a task prepares a fresh table
at `path`: output from the previous execution is replaced. With `append=true`
the table is continued instead; see the paragraph above for exactly which
continuation cases need an explicit `start_turn`.
"""
function MomentObserver(path::AbstractString; orders=1:2, extra=(), exclude=(),
                        capacity::Integer=1024, append::Bool=false)
    capacity >= 0 || throw(ArgumentError("capacity must be nonnegative"))
    moments = _selected_moments(orders=orders, extra=extra, exclude=exclude)
    names = ["turn"; collect(name.(moments))]
    buffer = Matrix{Float64}(undef, max(Int(capacity), 1), length(names))
    return MomentObserver(String(path), moments, names, Int(capacity), buffer, 0, 0, 0,
                          UInt64(0), false, Bool(append), nothing)
end

mutable struct CoordinateSnapshotObserver <: AbstractBeamObserver
    path::String
    npart::Union{Nothing,Int}
    append::Bool
    # (turn, byte offset before that record) for every record THIS object
    # wrote — the compact record format carries no turn label, so this map is
    # what lets a replayed window truncate its stale records (U6-2).
    written::Vector{Tuple{Int64,Int64}}
end

"""
    CoordinateSnapshotObserver(path; npart=nothing, append=true)

Write coordinate snapshots in the Octopus compact coordinate record format.
"""
function CoordinateSnapshotObserver(path::AbstractString; npart=nothing, append::Bool=true)
    count = npart === nothing ? nothing : Int(npart)
    count === nothing || count >= 0 || throw(ArgumentError("npart must be nonnegative or nothing"))
    return CoordinateSnapshotObserver(String(path), count, append, Tuple{Int64,Int64}[])
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

const _BUFFERED_OBSERVER_OPTION_SCHEMA = (
    path=ConfigurationOptionMeta(String, nothing, "Required output path.";
        category=:output, consumer=:observer_output),
    capacity=ConfigurationOptionMeta(Int, 1, "Number of observed rows buffered before a flush.";
        category=:output, consumer=:observer_output),
)
"""
    observer_option_schema(observer_or_type)

The observer type's configurable fields as a `NamedTuple` of
`ConfigurationOptionMeta`. Consumed by `configuration_report` and checked per
concrete observer by `validate_configuration_metadata()`.
"""
function observer_option_schema end

observer_option_schema(::Type{BeamMomentObserver}) = _BUFFERED_OBSERVER_OPTION_SCHEMA
observer_option_schema(::BeamMomentObserver) = _BUFFERED_OBSERVER_OPTION_SCHEMA
observer_option_schema(::Type{JLD2BeamMomentObserver}) = _BUFFERED_OBSERVER_OPTION_SCHEMA
observer_option_schema(::JLD2BeamMomentObserver) = _BUFFERED_OBSERVER_OPTION_SCHEMA
observer_option_schema(::Type{MomentObserver}) = (
    path=ConfigurationOptionMeta(String, nothing, "Required HDF5 output path.";
        category=:output, consumer=:observer_output),
    moments=ConfigurationOptionMeta(Tuple, nothing, "Resolved canonical moment selection.";
        category=:diagnostic, consumer=:moment_reduction),
    capacity=ConfigurationOptionMeta(Int, 1024, "Observed rows buffered before an HDF5 flush.";
        category=:output, consumer=:observer_output),
    append=ConfigurationOptionMeta(Bool, false, "Continue an existing appendable moment file across executions, tasks, and process restarts instead of preparing a fresh table; replayed turn windows drop their stale rows first.";
        category=:output, consumer=:observer_output),
)
observer_option_schema(::MomentObserver) = observer_option_schema(MomentObserver)
observer_option_schema(::Type{CoordinateSnapshotObserver}) = (
    path=ConfigurationOptionMeta(String, nothing, "Required coordinate output path.";
        category=:output, consumer=:observer_output),
    npart=ConfigurationOptionMeta(Union{Nothing,Int}, nothing,
        "Number of particles written; nothing writes all particles.";
        category=:output, consumer=:observer_output),
    append=ConfigurationOptionMeta(Bool, true, "Append after the first snapshot.";
        category=:output, consumer=:observer_output),
)
observer_option_schema(::CoordinateSnapshotObserver) = observer_option_schema(CoordinateSnapshotObserver)
observer_option_schema(::Type{LuminosityObserver}) = (
    path=ConfigurationOptionMeta(String, nothing, "Required weak-strong luminosity output path.";
        category=:output, consumer=:observer_output),)
observer_option_schema(::LuminosityObserver) = observer_option_schema(LuminosityObserver)

function configuration_report(observer::Union{BeamMomentObserver,JLD2BeamMomentObserver})
    return (
        ConfigurationEntry(:path, observer.path, observer.path, :resolved,
            "required output path", :observer_output),
        ConfigurationEntry(:capacity, observer.buffer_capacity, observer.buffer_capacity,
            observer.buffer_capacity == 0 ? :inactive_dependency : :resolved,
            observer.buffer_capacity == 0 ? "zero capacity disables output" :
                                            "active output buffer capacity",
            :observer_output),
    )
end

function configuration_report(observer::MomentObserver)
    return (
        ConfigurationEntry(:path, observer.path, observer.path, :resolved,
            "required HDF5 output path", :observer_output),
        ConfigurationEntry(:moments, observer.moments, observer.moments, :resolved,
            "canonical selection resolved from orders/extra/exclude", :moment_reduction),
        ConfigurationEntry(:capacity, observer.buffer_capacity, observer.buffer_capacity,
            observer.buffer_capacity == 0 ? :inactive_dependency : :resolved,
            observer.buffer_capacity == 0 ? "zero capacity disables output" :
                                            "active HDF5 buffer capacity",
            :observer_output),
        ConfigurationEntry(:append, observer.append, observer.append, :resolved,
            observer.append ?
                "continues one extendible table across executions and restarts" :
                "each execution prepares a fresh table (replace mode)",
            :observer_output),
    )
end

function configuration_report(observer::CoordinateSnapshotObserver)
    return (
        ConfigurationEntry(:path, observer.path, observer.path, :resolved,
            "required coordinate output path", :observer_output),
        ConfigurationEntry(:npart, observer.npart, observer.npart, :resolved,
            observer.npart === nothing ? "all particles" : "explicit particle count",
            :observer_output),
        ConfigurationEntry(:append, observer.append, observer.append, :resolved,
            "snapshot append mode", :observer_output),
    )
end
configuration_report(observer::LuminosityObserver) = (
    ConfigurationEntry(:path, observer.path, observer.path, :resolved,
        "required luminosity output path", :observer_output),)

function _observer_backend()
    policy = _ACTIVE_RESOLVED_POLICY[]
    return policy isa AbstractResolvedExecutionPolicy ? backend_type(policy) : :unknown
end

"""
    BeamSwapAction(provider)

Replace the current representation with the `Phase6DRep` or `Beam` returned by
`provider(ctx)`. If `provider` accepts no arguments, it is called as
`provider()`.
"""
struct BeamSwapAction{F} <: AbstractBeamAction
    provider::F
end

function observe!(observer::BeamMomentObserver, ctx::TrackingContext, rep)
    observer.buffer_capacity == 0 && return nothing
    _record_execution!(:observer_output, _observer_backend(),
        (observer=:BeamMomentObserver, turn=ctx.turn, capacity=observer.buffer_capacity))
    observer.initialized || _initialize_moment_file!(observer)
    push!(observer.buffer_turns, Float64(ctx.turn))
    push!(observer.buffer, _moment_output_row(beam_statistics(rep; diagonal_fourth=true)))
    length(observer.buffer) >= observer.buffer_capacity && _flush_moment_buffer!(observer)
    return nothing
end

function observe!(observer::JLD2BeamMomentObserver, ctx::TrackingContext, rep)
    observer.buffer_capacity == 0 && return nothing
    _record_execution!(:observer_output, _observer_backend(),
        (observer=:JLD2BeamMomentObserver, turn=ctx.turn, capacity=observer.buffer_capacity))
    observer.initialized || _initialize_jld2_moment_file!(observer)
    push!(observer.buffer_turns, Float64(ctx.turn))
    push!(observer.buffer, beam_statistics(rep; diagonal_fourth=true))
    length(observer.buffer) >= observer.buffer_capacity && _flush_jld2_moment_buffer!(observer)
    return nothing
end

function observe!(observer::MomentObserver, ctx::TrackingContext, rep)
    observer.buffer_capacity == 0 && return nothing
    _record_execution!(:observer_output, _observer_backend(),
        (observer=:MomentObserver, turn=ctx.turn, capacity=observer.buffer_capacity,
         moments=length(observer.moments)))
    observer.initialized || throw(ArgumentError("MomentObserver must be prepared by a predictable schedule before tracking"))
    observer.buffer_length += 1
    observer.buffer[observer.buffer_length, :] .= _moment_observer_row(ctx, rep, observer.moments, observer)
    observer.buffer_length >= observer.buffer_capacity && _flush_moment_observer!(observer)
    return nothing
end

function observe!(observer::CoordinateSnapshotObserver, ctx::TrackingContext, rep)
    npart = observer.npart === nothing ? length(rep) : observer.npart
    npart <= length(rep) || throw(ArgumentError(
        "CoordinateSnapshotObserver npart $(npart) exceeds particle count $(length(rep))"))
    _record_execution!(:observer_output, _observer_backend(),
        (observer=:CoordinateSnapshotObserver, turn=ctx.turn, npart=npart,
         append=observer.append))
    offset = observer.append && isfile(observer.path) ? Int64(filesize(observer.path)) :
             Int64(0)
    write_beam_coordinates(observer.path, rep; npart=npart, append=observer.append)
    push!(observer.written, (Int64(ctx.turn), offset))
    observer.append = true
    return nothing
end

function observe!(observer::LuminosityObserver, ctx::TrackingContext, rep)
    _record_execution!(:observer_output, _observer_backend(),
        (observer=:LuminosityObserver, turn=ctx.turn, elements=length(observer.elements)))
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

# ---------------------------------------------------------------------------
# Replayed-window discard for the continuing observers (2026-08-05 audit
# open-queue U6-2). A failed `execute!`'s retry — or an explicit `start_turn`
# rewind — replays absolute turns these observers may already have written,
# and until this block only `MomentObserver` and the task-level .lum file
# followed the idempotence rule (drop rows at or beyond the incoming window's
# `first_turn`); the others duplicated turn labels. Each discard acts only on
# a CONTINUING observer object (`initialized`/`append` already set): a fresh
# object rewrites its file anyway, which is the documented replace semantics.
# ---------------------------------------------------------------------------

function prepare_observer!(observer::LuminosityObserver, runtime_elems, schedule,
                           turns, first_turn)
    prepare_observer!(observer, runtime_elems)
    _discard_replayed_luminosity_rows!(observer, Int(first_turn))
    return nothing
end
prepare_line_observer!(observer::LuminosityObserver, schedule, turns, first_turn=0) =
    _discard_replayed_luminosity_rows!(observer, Int(first_turn))

function _discard_replayed_luminosity_rows!(observer::LuminosityObserver, first_turn::Int)
    (observer.initialized && isfile(observer.path)) || return nothing
    rows = readlines(observer.path)
    turn_of(line) = tryparse(Int, first(split(line, '\t')))
    kept = [line for line in rows
            if !isempty(strip(line)) && turn_of(line) !== nothing &&
               turn_of(line) < first_turn]
    tmp = observer.path * ".prepare.tmp"
    open(tmp, "w") do io
        for line in kept
            println(io, line)
        end
    end
    mv(tmp, observer.path; force=true)
    return nothing
end

function prepare_observer!(observer::JLD2BeamMomentObserver, runtime_elems, schedule,
                           turns, first_turn)
    _discard_replayed_jld2_rows!(observer, Int(first_turn))
    return nothing
end
prepare_line_observer!(observer::JLD2BeamMomentObserver, schedule, turns, first_turn=0) =
    _discard_replayed_jld2_rows!(observer, Int(first_turn))

function _discard_replayed_jld2_rows!(observer::JLD2BeamMomentObserver, first_turn::Int)
    # Unflushed rows from a crashed window would be re-observed by the retry.
    empty!(observer.buffer_turns)
    empty!(observer.buffer)
    (observer.initialized && isfile(observer.path)) || return nothing
    # Atomic: this rewrites `data`, and a kill mid-rewrite must not leave the
    # file without it (U7-2).
    _jld2_atomic_update!(observer.path) do pending
        haskey(pending, "data") || return nothing
        data = pending["data"]
        keep = findall(<(Float64(first_turn)), view(data, :, 1))
        length(keep) == size(data, 1) && return nothing
        kept = data[keep, :]
        pending["data"] = kept
        pending["record_count"] = Int64(size(kept, 1))
        observer.record_count = size(kept, 1)
        return nothing
    end
    return nothing
end

function prepare_observer!(observer::BeamMomentObserver, runtime_elems, schedule,
                           turns, first_turn)
    _discard_replayed_binary_rows!(observer, Int(first_turn))
    return nothing
end
prepare_line_observer!(observer::BeamMomentObserver, schedule, turns, first_turn=0) =
    _discard_replayed_binary_rows!(observer, Int(first_turn))

function _discard_replayed_binary_rows!(observer::BeamMomentObserver, first_turn::Int)
    empty!(observer.buffer_turns)
    empty!(observer.buffer)
    (observer.initialized && isfile(observer.path)) || return nothing
    # The `filesize > 0` guard the F7 fix gave both twins and this one lacked
    # (2026-08-05_b audit, U7-7). Without it the two `read(io, Int32)` below hit
    # a zero-length file and threw a bare `EOFError` naming neither the path nor
    # the observer. F7's own disposition for the HDF5 twin was that "a zero-byte
    # leftover from a crash at create time is not a table; it is replaced
    # fresh"; the binary twin neither replaced nor explained. Reachability is
    # low -- `initialized` is monotone within an object, so something outside
    # the observer must have truncated the file -- but the asymmetry is what
    # makes the class regenerate.
    if filesize(observer.path) == 0
        @warn "moment observer: the recorded file is zero bytes (a crash at " *
              "create time leaves this), so there are no rows to discard; it " *
              "will be written fresh" path = observer.path
        observer.initialized = false
        return nothing
    end
    open(observer.path, "r+") do io
        nrows = Int(read(io, Int32))
        fmtlen = Int(read(io, Int32))
        fmt = String(read(io, fmtlen))
        ncols = count(==(','), fmt) + 1
        rowbytes = ncols * sizeof(Float64)
        base = 8 + fmtlen
        turn_at(i) = (seek(io, base + (i - 1) * rowbytes); read(io, Float64))
        # Rows are in ascending turn order (schedules plan forward and rewinds
        # drop), so the cutoff is a binary search on the leading turn column.
        lo, hi = 1, nrows
        kept = nrows
        while lo <= hi
            mid = (lo + hi) >> 1
            if turn_at(mid) < Float64(first_turn)
                lo = mid + 1
            else
                kept = mid - 1
                hi = mid - 1
            end
        end
        kept = min(kept, nrows)
        if kept < nrows
            seekstart(io)
            write(io, Int32(kept))
            truncate(io, base + kept * rowbytes)
        end
        observer.record_count = kept
        return nothing
    end
    return nothing
end

function prepare_observer!(observer::CoordinateSnapshotObserver, runtime_elems, schedule,
                           turns, first_turn)
    _discard_replayed_snapshots!(observer, Int(first_turn))
    return nothing
end
prepare_line_observer!(observer::CoordinateSnapshotObserver, schedule, turns, first_turn=0) =
    _discard_replayed_snapshots!(observer, Int(first_turn))

function _discard_replayed_snapshots!(observer::CoordinateSnapshotObserver, first_turn::Int)
    # Snapshot records carry no turn label in the file, so the discard uses
    # the (turn → byte offset) map this observer keeps for the records IT
    # wrote: same-object retries truncate cleanly; records in a pre-existing
    # file the object never wrote cannot be attributed and are left alone.
    isempty(observer.written) && return nothing
    isfile(observer.path) || return (empty!(observer.written); nothing)
    idx = findfirst(entry -> entry[1] >= first_turn, observer.written)
    idx === nothing && return nothing
    offset = observer.written[idx][2]
    open(observer.path, "r+") do io
        truncate(io, offset)
    end
    resize!(observer.written, idx - 1)
    # `append = false` is only correct when NOTHING precedes this object's
    # records. `offset` is the byte position before the first record being
    # dropped, so a non-zero offset with an empty `written` list means the file
    # still holds data this observer never wrote -- the very data the
    # `truncate` above just took care to preserve, per this function's own
    # docstring ("records in a pre-existing file the object never wrote cannot
    # be attributed and are left alone").
    #
    # Resetting unconditionally made the next `observe!` compute offset = 0 and
    # reopen with "w", destroying that prefix. Measured: a 19-byte foreign
    # prefix survived the discard (file truncated 215 -> 19) and was gone after
    # the retry (2026-08-05_b audit, U7-1).
    isempty(observer.written) && offset == 0 && (observer.append = false)
    return nothing
end

function prepare_observer!(observer::MomentObserver, runtime_elems, schedule, turns,
                          first_turn=0)
    _prepare_moment_observer!(observer, schedule, turns, first_turn)
    return nothing
end

function prepare_line_observer!(observer::MomentObserver, schedule, turns, first_turn=0)
    _prepare_moment_observer!(observer, schedule, turns, first_turn)
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
        # Rows land at the offset the on-disk count implies, and the count is
        # updated only after they are written — in that order, so a crash
        # between the two leaves orphan bytes past the counted region that
        # the next flush overwrites, never a count exceeding the rows on
        # disk (the HDF5 observer makes the same ordering promise;
        # 2026-08-05 audit, U6-6).
        seek(io, 4)
        fmtlen = Int(read(io, Int32))
        rowbytes = (1 + length(first(observer.buffer))) * sizeof(Float64)
        seek(io, 8 + fmtlen + observer.record_count * rowbytes)
        for (turn, row) in zip(observer.buffer_turns, observer.buffer)
            write(io, Float64(turn))
            write(io, Float64.(row))
        end
        observer.record_count += length(observer.buffer)
        seekstart(io)
        write(io, Int32(observer.record_count))
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
    # Atomic: `_append_jld2_moment_columns!` rewrites the WHOLE `data` matrix on
    # every flush, so the delete-then-write window it used to run in was open
    # once per observed turn (U7-2).
    _jld2_atomic_update!(observer.path) do pending
        _append_jld2_moment_columns!(pending, observer)
    end
    empty!(observer.buffer_turns)
    empty!(observer.buffer)
    return nothing
end

finalize_observer!(observer::JLD2BeamMomentObserver) =
    _flush_jld2_moment_buffer!(observer)

function finalize_observer!(observer::MomentObserver)
    try
        _flush_moment_observer!(observer)
    finally
        # A MomentObserver owns one output table per task execution. Mark it
        # unprepared after every run so the same task can be executed again.
        observer.initialized = false
    end
    return nothing
end

function _prepare_moment_observer!(observer::MomentObserver, schedule, turns,
                                  first_turn::Integer=0)
    if observer.buffer_capacity == 0
        # `capacity = 0` disables output, which is documented and deliberate --
        # but "disables output" and "leaves the last run's file untouched" are
        # different promises, and only the first was made (2026-08-05_b audit,
        # U7-9). A stale table from a previous run sits at `path` looking
        # exactly like current output, with nothing said. The file is NOT
        # removed here, because deleting a user's data on a disabled observer
        # would be a worse surprise than leaving it; the point is that the
        # ambiguity stops being silent.
        isfile(observer.path) && filesize(observer.path) > 0 &&
            @warn "MomentObserver(capacity=0) writes nothing, and a file already " *
                  "exists at this path: it is from an EARLIER run and will not be " *
                  "updated. Delete it, or use a different path, if you are about " *
                  "to read it as this run's output." path = observer.path maxlog = 1
        return nothing
    end
    planned_turns = _scheduled_turns(schedule, turns, first_turn)
    planned_turns === nothing && throw(ArgumentError(
        "MomentObserver requires a predictable schedule: use AlwaysSchedule, EveryNSteps, or AtTurns with known task turns."
    ))
    observer.buffer_length = 0
    observer.start_time_ns = time_ns()
    if observer.append && isfile(observer.path) && filesize(observer.path) > 0
        # Continue the existing table (a zero-byte leftover from a crash at
        # create time is not a table; it is replaced fresh, matching the
        # .lum twin). The kept rows live in the FILE, but the resume POINT is
        # the caller's: a fresh task or process continues the table only when
        # execute! is given the matching absolute start_turn — without it,
        # execution starts at turn 0 and replaces the recorded timeline
        # (loudly; see _moment_append_continue!).
        kept = _moment_append_continue!(observer, Int(first_turn), length(planned_turns))
        observer.record_count = kept
        observer.planned_records = kept + length(planned_turns)
    else
        observer.planned_records = length(planned_turns)
        observer.record_count = 0
        _initialize_hdf5_moment_file!(observer)
    end
    observer.initialized = true
    return nothing
end

"""
Open an existing appendable moment file, drop any rows at or beyond
`first_turn`, and grow the table's extent for the upcoming window.

Dropping the replayed window is the same idempotence rule the BPM observer
follows: rows there can only exist from a failed `execute!` whose retry
replays the same absolute turns, or from an explicit `start_turn` rewind —
either way the timeline from `first_turn` on is being rewritten, and a table
with two rows for one turn is corrupt for every reader. Rows are in ascending
turn order (schedules plan forward and rewinds drop), so the cutoff is a
binary search on the turn column.
"""
function _moment_append_continue!(observer::MomentObserver, first_turn::Int, nplanned::Int)
    return HDF5.h5open(observer.path, "r+") do file
        (haskey(file, "data") && haskey(file, "record_count") &&
         haskey(file, "column_names")) || throw(ArgumentError(
            "MomentObserver(append=true): $(observer.path) exists but is not a moment file. Use a new path."))
        dset = file["data"]
        haskey(HDF5.attributes(dset), "appendable") || throw(ArgumentError(
            "MomentObserver(append=true): $(observer.path) was created without append=true, " *
            "so its HDF5 table is fixed-size and cannot grow. Use a new path or delete it."))
        read(file["column_names"]) == observer.column_names || throw(ArgumentError(
            "MomentObserver(append=true): the moment selection differs from the existing " *
            "file at $(observer.path); matching columns are required to continue it."))
        written = Int(read(file["record_count"])[1])
        kept = written
        if written > 0
            turn_col = dset[1:written, 1]
            kept = searchsortedfirst(turn_col, Float64(first_turn)) - 1
        end
        if written > 0 && kept == 0
            @warn "MomentObserver(append=true) is replacing the entire existing " *
                  "moment table at $(observer.path): execution starts at turn " *
                  "$(first_turn), at or before every recorded row. Pass the " *
                  "matching absolute start_turn to execute! to continue the " *
                  "file instead." dropped_rows = written
        end
        HDF5.set_extent_dims(dset, (kept + nplanned, length(observer.column_names)))
        file["record_count"][1] = Int64(kept)
        HDF5.flush(file)
        return kept
    end
end

# The planner must filter against the ABSOLUTE turn window `execute!` will run,
# `first_turn : first_turn + turns - 1`, because `should_run` is handed
# `ctx.turn = first_turn + offset` (Tasks.jl). Filtering against `0:turns-1`
# instead -- which is what these did -- makes the plan disagree with the
# predicate whenever `first_turn != 0`:
#
#   _scheduled_turns(AtTurns([100,101]), 3)  ->  Int64[]
#   while execute!(turns=3, start_turn=100) fires the observer twice
#     -> MomentObserver over-runs its preallocated table and throws
#
#   _scheduled_turns(EveryNSteps(start=0,stop=6,step=2), 3)  ->  [0,2]
#   on a SECOND execute!(turns=3), which runs turns 3,4,5 and fires once at 4
#     -> plan says 2 records, one is written, no error, silently wrong header
#
# `first_turn != 0` is not exotic: it is every second `execute!` on the same
# task, which Tasks.jl documents as a supported way to split a run.
function _scheduled_turns(::AlwaysSchedule, turns, first_turn::Integer=0)
    turns === nothing && return nothing
    return collect(Int(first_turn):(Int(first_turn) + Int(turns) - 1))
end

function _scheduled_turns(schedule::EveryNSteps, turns, first_turn::Integer=0)
    turns === nothing && return nothing
    lo = Int(first_turn)
    hi = lo + Int(turns)                      # exclusive
    stop = min(schedule.stop, hi)
    schedule.start >= stop && return Int[]
    # Enumerate from the first schedule point at or after `lo` rather than
    # from `schedule.start`: enumerating from the start makes planning cost
    # proportional to the ABSOLUTE turn -- measured 0.009 ms at first_turn=0
    # vs 29.5 ms at 1e8 -- penalising exactly the chunked long run
    # `first_turn` exists to serve (audit part 7, T10). Everything in
    # `from:step:stop-1` already lies inside `[lo, hi)`, so no filter remains.
    from = schedule.start >= lo ? schedule.start :
           schedule.start + cld(lo - schedule.start, schedule.step) * schedule.step
    return collect(from:schedule.step:(stop - 1))
end

function _scheduled_turns(schedule::AtTurns, turns, first_turn::Integer=0)
    turns === nothing && return nothing
    lo = Int(first_turn)
    hi = lo + Int(turns)
    return sort!([turn for turn in schedule.turns if lo <= turn < hi])
end

_scheduled_turns(schedule::PredicateSchedule, turns, first_turn::Integer=0) = nothing

function _initialize_hdf5_moment_file!(observer::MomentObserver)
    HDF5.h5open(observer.path, "w") do file
        ncols = length(observer.column_names)
        if observer.append
            # Chunked with an unlimited row dimension: a contiguous HDF5
            # dataset (the replace-mode layout below) can never grow, which
            # is the structural reason append needed more than a mode flag.
            # Chunked datasets read back identically; unwritten rows are the
            # 0.0 fill value, matching the replace-mode zeros.
            chunk_rows = clamp(observer.planned_records, 1, 1024)
            dset = HDF5.create_dataset(file, "data", HDF5.datatype(Float64),
                HDF5.dataspace((observer.planned_records, ncols); max_dims=(-1, ncols));
                chunk=(chunk_rows, ncols))
            HDF5.attributes(dset)["appendable"] = Int8(1)
        else
            file["data"] = zeros(Float64, observer.planned_records, ncols)
        end
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
    row2 <= observer.planned_records || error(
        "MomentObserver received more records ($(row2)) than planned ($(observer.planned_records))")
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

"""
    _moment_live_flags(arrays)

Per-particle liveness for a moment reduction, or `nothing` when the mask is off.

One `NaN` in any coordinate makes its mean `NaN`, and every central moment is
built from all six means -- so a single dead particle takes out the entire
moment row, not just the coordinate it died in. That coupling is why the mask
has to be computed once from all six arrays and then shared by the mean pass and
every moment pass, rather than applied per coordinate.
"""
function _moment_live_flags(arrays)
    allow_lost_particles() || return nothing
    x, px, y, py, z, pz = arrays
    flags = Vector{Bool}(undef, length(x))
    @inbounds for i in eachindex(x)
        flags[i] = is_live(x[i], px[i], y[i], py[i], z[i], pz[i])
    end
    return flags
end

@inline _moment_live(::Nothing, i) = true
@inline _moment_live(flags::Vector{Bool}, i) = @inbounds flags[i]

_moment_denominator(::Nothing, n::Integer) = Int(n)
_moment_denominator(flags::Vector{Bool}, n::Integer) = count(flags)

function _moment_observer_row(ctx::TrackingContext, rep, moments::Tuple, observer=nothing)
    row = Vector{Float64}(undef, length(moments) + 1)
    row[1] = Float64(ctx.turn)
    isempty(moments) && return row
    arrays = map(collect, coordinate_arrays(rep))
    flags = _moment_live_flags(arrays)
    nlive = _moment_denominator(flags, length(arrays[1]))
    # An all-dead beam has no moments to report. `NaN` is the honest value, and
    # the turn column stays intact so the record still says *when* that happened.
    if nlive == 0
        fill!(view(row, 2:length(row)), NaN)
        return row
    end
    means = ntuple(6) do i
        a = arrays[i]
        s = 0.0
        @inbounds for k in eachindex(a)
            _moment_live(flags, k) && (s += a[k])
        end
        Float64(s / nlive)
    end
    for (j, moment) in enumerate(moments)
        row[j + 1] = _compute_moment(arrays, means, moment, flags, nlive)
    end
    return row
end

if _HAS_CUDA
    @eval begin
        function _moment_observer_row(ctx::TrackingContext,
                                      rep::Phase6DRep{<:CUDA.CuArray}, moments::Tuple,
                                      observer::MomentObserver)
            row = Vector{Float64}(undef, length(moments) + 1)
            row[1] = Float64(ctx.turn)
            isempty(moments) && return row
            arrays = coordinate_arrays(rep)
            n = length(arrays[1])
            # `nothing` when the mask is off, so the reductions below stay the
            # plain device reductions they were.
            flags = allow_lost_particles() ?
                is_live.(arrays[1], arrays[2], arrays[3], arrays[4], arrays[5], arrays[6]) :
                nothing
            nlive = flags === nothing ? n : Int(sum(flags))
            if nlive == 0
                fill!(view(row, 2:length(row)), NaN)
                return row
            end
            means = ntuple(6) do i
                a = flags === nothing ? arrays[i] :
                    ifelse.(flags, arrays[i], zero(eltype(arrays[i])))
                Float64(sum(a) / nlive)
            end
            scratch = observer.reduction_scratch
            if !(scratch isa CUDA.CuArray) || length(scratch) != n || eltype(scratch) != eltype(arrays[1])
                scratch = similar(arrays[1])
                observer.reduction_scratch = scratch
            end
            for (j, moment) in enumerate(moments)
                row[j + 1] = _cuda_compute_moment!(scratch, arrays, means, moment, flags, nlive)
            end
            return row
        end

        function _cuda_compute_moment!(scratch, arrays, means, moment::Moment,
                                       flags=nothing, nlive=length(scratch))
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
            # Zero the dead *after* the product: their coordinates are non-finite,
            # so masking each factor would still leave NaN in the accumulator.
            flags === nothing || (scratch .= ifelse.(flags, scratch, zero(eltype(scratch))))
            return Float64(sum(scratch) / nlive)
        end
    end
end

function _compute_moment(arrays, means, moment::Moment, flags=nothing, nlive=length(arrays[1]))
    powers = moment.powers
    order = sum(powers)
    order == 1 && return means[findfirst(!=(0), powers)]
    n = length(arrays[1])
    acc = 0.0
    @inbounds for i in 1:n
        _moment_live(flags, i) || continue
        term = 1.0
        for d in 1:6
            p = powers[d]
            p == 0 && continue
            term *= (arrays[d][i] - means[d]) ^ p
        end
        acc += term
    end
    return acc / nlive
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

"""
Apply `mutate!(pending)` to a JLD2 file's contents and swap it in atomically.

`pending` is a `Dict` of every key the file currently holds; whatever it holds
afterwards is what the file will hold. The new contents go to a sibling
temporary and are `mv`-ed over the original, so a process death leaves either
the old file or the new one and never a partial.

This exists because `_jld2_replace!` is `delete!` then write, in place: between
those two calls the file has no `data` key at all, and
`_append_jld2_moment_columns!` runs that on EVERY flush (default capacity 1, so
once per observed turn). A kill in that window loses the entire history rather
than the in-flight row. That is the F4 defect, fixed for the `.lum` path with
tmp + `mv` and left unfixed in this twin; `_discard_replayed_jld2_rows!` then
added a second instance of it. The binary and HDF5 twins both make the opposite
promise -- rows first, count second (F9) -- and JLD2 made none
(2026-08-05_b audit, U7-2).
"""
function _jld2_atomic_update!(mutate!, path::AbstractString)
    pending = Dict{String,Any}()
    if isfile(path)
        JLD2.jldopen(path, "r") do file
            for k in _jld2_all_keys(file)
                pending[k] = file[k]
            end
        end
    end
    mutate!(pending)
    tmp = path * ".tmp"
    try
        JLD2.jldopen(tmp, "w") do file
            for (k, v) in pending
                file[k] = v
            end
        end
        mv(tmp, path; force=true)
    catch
        rm(tmp; force=true)
        rethrow()
    end
    return nothing
end

"""Every leaf key in a JLD2 file, including nested `metadata/...` paths."""
function _jld2_all_keys(file, prefix::String="")
    node = isempty(prefix) ? file : file[prefix]
    out = String[]
    for k in keys(node)
        full = isempty(prefix) ? String(k) : prefix * "/" * String(k)
        child = file[full]
        if child isa JLD2.Group
            append!(out, _jld2_all_keys(file, full))
        else
            push!(out, full)
        end
    end
    return out
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

"""
Width in columns of each block of the JLD2 moment table, in order.

The ONE place the layout is stated (2026-08-05_b audit, U7-8). It used to live
in three independent hand copies -- the column names, a table of hardcoded
`turn=1:1, mean=2:7, covariance=8:43, ...` offsets, and a third set of
`col += 6 / += 36 / += 3` steps inside the matrix builder -- with no tripwire.
Adding or reordering a column in one silently mislabels `read_moment(:emittance)`
from the others. The three did agree (1+6+36+6+3+1+1+6 = 60); Measured Lesson 4
is that hand-copied knowledge drifts, so derive and add a tripwire.
"""
const _JLD2_MOMENT_BLOCK_WIDTHS = (
    turn = 1,
    mean = 6,
    covariance = 36,
    rms = 6,
    emittance = 3,
    xz_covariance = 1,
    yz_covariance = 1,
    diagonal_fourth_central = 6,
)

"""Column ranges of the JLD2 moment table, derived from the block widths."""
function _jld2_moment_ranges()
    offset = 0
    pairs = map(keys(_JLD2_MOMENT_BLOCK_WIDTHS)) do name
        width = getproperty(_JLD2_MOMENT_BLOCK_WIDTHS, name)
        range = (offset + 1):(offset + width)
        offset += width
        name => range
    end
    return NamedTuple(pairs)
end

function _jld2_moment_data_matrix(turn, mean, covariance, rms, emittance, xz, yz, fourth)
    n = length(turn)
    data = Matrix{Float64}(undef, n, length(_jld2_moment_column_names()))
    # The SAME ranges the readers use, not a third copy of the arithmetic (U7-8).
    r = _jld2_moment_ranges()
    data[:, r.turn] .= turn
    data[:, r.mean] .= mean
    data[:, r.covariance] .= reshape(covariance, n, length(r.covariance))
    data[:, r.rms] .= rms
    data[:, r.emittance] .= emittance
    data[:, r.xz_covariance] .= xz
    data[:, r.yz_covariance] .= yz
    data[:, r.diagonal_fourth_central] .= fourth
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

"""
Whether a moment file is HDF5, decided by its CONTENT rather than its name.

`MomentObserver` calls `HDF5.h5open(path, "w")` unconditionally, so it writes
HDF5 to whatever path it is given -- while this predicate used to test only
`splitext(path)[2] in (".h5", ".hdf5")`. On any other extension the read fell
through to the JLD2 branch, which returns `file["data"]` whole and never applies
the `/data[1:record_count, :]` slice its own docstring promises. JLD2 reads an
HDF5 file successfully (with a "File likely not written by JLD2" warning), so
the result was silent wrong data, not an error: measured on a run that
preallocated 10 records and wrote 4, a `.h5` path read back 4 correct rows and a
`.dat` path read back 10 -- the last six fabricated, all-zero, and carrying turn
label 0.0 (2026-08-05_b audit, U7-4).

The HDF5 signature is the fixed 8-byte magic at the start of the file, so this
is exact rather than heuristic. A missing or unreadable file falls back to the
extension, which keeps the error message about the path rather than the format.
"""
function _is_hdf5_output(path::AbstractString)
    p = String(path)
    magic = UInt8[0x89, 0x48, 0x44, 0x46, 0x0d, 0x0a, 0x1a, 0x0a]
    try
        isfile(p) || return lowercase(splitext(p)[2]) in (".h5", ".hdf5")
        open(p, "r") do io
            head = read(io, length(magic))
            return length(head) == length(magic) && head == magic
        end
    catch
        return lowercase(splitext(p)[2]) in (".h5", ".hdf5")
    end
end

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
