import Base: read

export AbstractSchedule, AbstractBeamObserver, AbstractBeamAction,
       AlwaysSchedule, EveryNSteps, AtTurns, PredicateSchedule,
       should_run, ScheduledObserver, ScheduledAction,
       schedule_option_schema, observer_option_schema,
       Moment, name, symbol, column_names,
       MomentObserver,
       CoordinateSnapshotObserver, BeamSwapAction,
       observe!, apply_action!, run_observers!, run_actions!,
       prepare_observers!, prepare_line_observers!,
       finalize_observers!, requires_elementwise_tracking,
       MomentOutput, MomentOutputFile, OutputFile, MomentFile

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

# Process-wide registry of output paths with a live writing observer
# (2026-08-05_b audit, U7-10). Two live observers writing one path end
# self-consistent and WRONG: the second's initializer truncates the first's
# rows, and the surviving writer then resyncs onto the OTHER observer's rows
# and appends after them — measured turn column [0, 1, 4, 5] from an
# interleaved 4-turn and 2-turn pair, with the file reporting 4 valid rows
# and no warning anywhere. Path sharing by a SINGLE observer continued
# across tasks is documented and handled; a SECOND live observer on the same
# path is almost certainly a mistake, so its initialization warns. A warning
# rather than an error, and per-process rather than per-task, deliberately:
# the interleave crosses task boundaries (each execute! prepares and
# finalizes cleanly, so no task-scoped check can see it), and the registry
# keys on weak object identity, which can flag the collision but cannot
# prove intent. A collected observer's entry goes stale with it, so an
# abandoned path can be reused without noise.
const _OBSERVER_PATH_REGISTRY = Dict{String,WeakRef}()
const _OBSERVER_PATH_REGISTRY_LOCK = ReentrantLock()

function _register_observer_path!(observer, path::AbstractString)
    key = abspath(String(path))
    lock(_OBSERVER_PATH_REGISTRY_LOCK) do
        prior = get(_OBSERVER_PATH_REGISTRY, key, nothing)
        if prior !== nothing
            live = prior.value
            if live !== nothing && live !== observer
                @warn "a second live observer is initializing an output path " *
                      "that another live observer is writing: this " *
                      "initialization truncates the first observer's rows, " *
                      "and later flushes from both will interleave into a " *
                      "self-consistent but wrong file. Give each observer " *
                      "its own path (U7-10)." path = key first_observer =
                      typeof(live) second_observer = typeof(observer)
            end
        end
        _OBSERVER_PATH_REGISTRY[key] = WeakRef(observer)
    end
    return nothing
end

# The probe arm of the ONE arc traversal (`_collect_spec_s!`, Tasks.jl --
# the U11-1/T3 single-walker rule): in-line observers are zero-length and
# advance nothing (the aperture walker's pinned contract), and under the
# `:__probe__` kind they are COLLECTED with their arc position. Lives here
# rather than beside the walker because ScheduledObserver loads after
# Tasks.jl.
function _collect_spec_s!(out, hook::Union{ScheduledObserver,AbstractBeamObserver},
                          s, ::Val{K}) where {K}
    _kind_matches(:__probe__, K) && push!(out, (s[], 0.0, hook))
    return out
end

"""
Arc position of every in-line observer, keyed by the OBSERVER OBJECT
(unwrapped from its ScheduledObserver), from one spec-line walk. Consumed
through the `_ACTIVE_PROBE_S_MAP` scope during prepare, so the artifact bind
can stamp the design's `s` attribute; task-hook observers are absent from
the map and stamp nothing.
"""
function _line_probe_s_map(elements, more...)
    d = IdDict{Any,Float64}()
    for line in (elements, more...)
        out = Tuple{Float64,Float64,Any}[]
        _collect_spec_s!(out, line, Ref(0.0), Val(:__probe__))
        for (pos, _, hook) in out
            obs = hook isa ScheduledObserver ? hook.observer : hook
            d[obs] = pos
        end
    end
    return d
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
diagnostics returns `true`. The `ctx` form only
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

# TaskOutput's column selector accepts a Moment; the method lives here
# because RunArtifact.jl loads before Moment exists.
_ra_column_key(column::Moment) = symbol(column)

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
    moments::Tuple
    column_names::Vector{String}
    buffer_capacity::Int
    buffer::Matrix{Float64}
    buffer_length::Int
    record_count::Int
    planned_records::Int
    initialized::Bool
    reduction_scratch::Any
    # The probe is a named VIEW into the owning task's RunArtifact --
    # /moments/<name>, bound at prepare through the active-artifact scope.
    name::String
    artifact_ref::Any
    artifact_key::Union{Nothing,String}
end

_moment_column_names(moments) = ["turn"; collect(name.(moments))]

"""
    MomentObserver(path::AbstractString; ...)

Retired. See the `MomentObserver(; name, ...)` artifact-view constructor.
"""
function MomentObserver(path::AbstractString; orders=1:2, extra=(), exclude=(),
                        capacity::Integer=1024, append::Bool=false)
    throw(ArgumentError(
        "the standalone moment file writer was retired (2026-08-18): construct " *
        "MomentObserver(; name=..., orders=..., capacity=...) as a view into the " *
        "task's artifact=RunArtifact(path; append=..., capacity=...), and read it " *
        "back with MomentOutput(path; name=...)"))
end

"""
    MomentObserver(; name, orders=1:2, extra=(), exclude=())

Record selected beam moments into the owning task's [`RunArtifact`](@ref) as
the group `/moments/<name>` -- column 1 the absolute turn, then the selected
moments. `name` is the group identity, unique within a task;
append/replay/crash semantics come from the artifact's per-group cursor.
Requires the task to carry `artifact=...`; refused loudly at prepare
otherwise.

`MomentObserver` is a scheduled observer: put it in a task line or task hooks
through `ScheduledObserver`, with a predictable schedule (`AlwaysSchedule`,
`EveryNSteps`, or `AtTurns`). It writes one row per scheduled observation.

Moment selection is:

```julia
selected = expand_orders(orders)
selected = union(selected, extra)
selected = setdiff(selected, exclude)
```

`exclude` wins. `turn` is always present and is not part of moment selection.
Column order is canonical and does not depend on user input order. `orders`
accepts integers, ranges, vectors, tuples, and nested combinations such as
`1:2`, `(1, 2)`, `(1:2, 3)`, or `()`. First-order moments are means; moments
of order 2 or higher are central moments.

Buffering is the ARTIFACT'S: `RunArtifact(path; capacity=...)` is the one
knob deciding how many rows the row-shaped producers batch per append (the
per-observer `capacity` retired 2026-08-18; snapshots write a block per fire
instead). The row buffer is sized from it at prepare.

Read back through the same handle as before:

```julia
out = MomentOutput("run.h5"; name = "IP6")
data = read(out)
turns = read(out, :turn)
mx = read(out, Moment(; x = 1))
```

with per-execution timing in `read(TaskOutput("run.h5"), :execution)`.
"""
function MomentObserver(; name::AbstractString, orders=1:2, extra=(), exclude=(),
                        capacity=nothing)
    capacity === nothing || throw(ArgumentError(
        "the per-observer capacity was retired (2026-08-18): buffering " *
        "belongs to the sink, so pass artifact=RunArtifact(path; " *
        "capacity=...) on the task instead"))
    isempty(String(name)) && throw(ArgumentError("the artifact-view MomentObserver needs a nonempty name"))
    moments = _selected_moments(orders=orders, extra=extra, exclude=exclude)
    cols = _moment_column_names(moments)
    # The row buffer is sized from the artifact's capacity at prepare.
    return MomentObserver(moments, cols, 0, Matrix{Float64}(undef, 0, length(cols)),
                          0, 0, 0, false, nothing, String(name), nothing, nothing)
end

mutable struct CoordinateSnapshotObserver <: AbstractBeamObserver
    npart::Union{Nothing,Int}
    # The probe is a named VIEW into the owning task's RunArtifact --
    # /snapshot/<name>, rows [turn, particle_id, x, px, y, py, z, pz],
    # one block per fire.
    name::String
    artifact_ref::Any
    artifact_key::Union{Nothing,String}
end

"""
    CoordinateSnapshotObserver(path; ...)

Retired. See the `CoordinateSnapshotObserver(; name, ...)` artifact-view
constructor.
"""
function CoordinateSnapshotObserver(path::AbstractString; npart=nothing, append::Bool=true)
    throw(ArgumentError(
        "the standalone coordinate snapshot file was retired (2026-08-18): " *
        "construct CoordinateSnapshotObserver(; name=..., npart=...) as a view " *
        "into the task's artifact=RunArtifact(path), and read it back with " *
        "read(TaskOutput(path), :snapshot; name=name)"))
end

"""
    CoordinateSnapshotObserver(; name, npart=nothing)

Record full phase-space snapshots into the owning task's
[`RunArtifact`](@ref) as `/snapshot/<name>` -- rows
`[turn, particle_id, x, px, y, py, z, pz]`, one block per fire, replayed
windows dropped by the artifact's per-group cursor. `npart` captures only
the leading particles; `nothing` captures every particle. Requires the task
to carry `artifact=...`; read back with
`read(TaskOutput(path), :snapshot; name=name)`.

Each fire writes its block IMMEDIATELY: the artifact's `capacity` batching
deliberately does not apply here, because a snapshot block is already large
and buffering blocks would multiply host memory for no amortization gain.
Control snapshot volume with the observer's schedule and `npart`.
"""
function CoordinateSnapshotObserver(; name::AbstractString, npart=nothing)
    isempty(String(name)) && throw(ArgumentError("the artifact-view CoordinateSnapshotObserver needs a nonempty name"))
    count = npart === nothing ? nothing : Int(npart)
    count === nothing || count >= 0 || throw(ArgumentError("npart must be nonnegative or nothing"))
    return CoordinateSnapshotObserver(count, String(name), nothing, nothing)
end

"""
    observer_option_schema(observer_or_type)

The observer type's configurable fields as a `NamedTuple` of
`ConfigurationOptionMeta`. Consumed by `configuration_report` and checked per
concrete observer by `validate_configuration_metadata()`.
"""
function observer_option_schema end

observer_option_schema(::Type{MomentObserver}) = (
    name=ConfigurationOptionMeta(String, nothing,
        "Group identity inside the task's run artifact (/moments/<name>); required, unique within a task.";
        category=:output, consumer=:observer_output),
    moments=ConfigurationOptionMeta(Tuple, nothing,
        "Canonical moment selection resolved from orders/extra/exclude; exclude wins.";
        category=:output, consumer=:moment_reduction),)
observer_option_schema(::MomentObserver) = observer_option_schema(MomentObserver)
observer_option_schema(::Type{CoordinateSnapshotObserver}) = (
    name=ConfigurationOptionMeta(String, nothing,
        "Group identity inside the task's run artifact (/snapshot/<name>); required, unique within a task.";
        category=:output, consumer=:observer_output),
    npart=ConfigurationOptionMeta(Union{Nothing,Int}, nothing,
        "Leading particle count captured per fire; nothing captures every particle.";
        category=:output, consumer=:observer_output),)
observer_option_schema(::CoordinateSnapshotObserver) =
    observer_option_schema(CoordinateSnapshotObserver)

function configuration_report(observer::MomentObserver)
    return (
        ConfigurationEntry(:name, observer.name, observer.name, :resolved,
            "artifact group identity (/moments/<name>)", :observer_output),
        ConfigurationEntry(:moments, observer.moments, observer.moments, :resolved,
            "canonical selection resolved from orders/extra/exclude", :moment_reduction),
    )
end

function configuration_report(observer::CoordinateSnapshotObserver)
    return (
        ConfigurationEntry(:name, observer.name, observer.name, :resolved,
            "artifact group identity (/snapshot/<name>)", :observer_output),
        ConfigurationEntry(:npart, observer.npart, observer.npart, :resolved,
            observer.npart === nothing ? "all particles" : "explicit particle count",
            :observer_output),
    )
end

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

function observe!(observer::MomentObserver, ctx::TrackingContext, rep)
    _record_execution!(:observer_output, _observer_backend(),
        (observer=:MomentObserver, turn=ctx.turn, capacity=observer.buffer_capacity,
         moments=length(observer.moments)))
    observer.initialized || throw(ArgumentError("MomentObserver must be prepared by a predictable schedule before tracking"))
    observer.buffer_length += 1
    observer.buffer[observer.buffer_length, :] .= _moment_observer_row(ctx, rep, observer.moments, observer)
    observer.buffer_length >= observer.buffer_capacity && _flush_moment_observer!(observer)
    return nothing
end

const _SNAPSHOT_ARTIFACT_COLUMNS =
    ["turn", "particle_id", "x", "px", "y", "py", "z", "pz"]

function _bind_snapshot_probe!(observer::CoordinateSnapshotObserver, first_turn::Int)
    art = active_run_artifact()
    art === nothing && throw(ArgumentError(
        "CoordinateSnapshotObserver(name=$(repr(observer.name))) is an " *
        "artifact view: the task must carry artifact=RunArtifact(...)"))
    observer.artifact_ref = art
    observer.artifact_key = _ra_bind_probe!(art, "snapshot", observer.name,
                                            _SNAPSHOT_ARTIFACT_COLUMNS, first_turn;
                                            s=_active_probe_s(observer))
    return nothing
end

function prepare_observer!(observer::CoordinateSnapshotObserver, runtime_elems,
                           schedule, turns, first_turn)
    _bind_snapshot_probe!(observer, Int(first_turn))
    return nothing
end
prepare_line_observer!(observer::CoordinateSnapshotObserver, schedule, turns, first_turn=0) =
    _bind_snapshot_probe!(observer, Int(first_turn))

# One row per particle, so a divided run would have to gather the beam onto
# rank 0 before writing (see `_observer_is_per_particle`).
_observer_is_per_particle(::CoordinateSnapshotObserver) = true

function observe!(observer::CoordinateSnapshotObserver, ctx::TrackingContext, rep)
    # `npart` counts the WHOLE beam, as it always has: under a divided run
    # each rank contributes the part of `1:npart` its shard covers, and the
    # rows carry the global particle id. At one rank the offset is zero, the
    # shard is the beam, and this is what it was.
    offset, global_n = _mp_current_shard(rep)
    npart = observer.npart === nothing ? global_n : observer.npart
    npart <= global_n || throw(ArgumentError(
        "CoordinateSnapshotObserver npart $(npart) exceeds particle count $(global_n)"))
    observer.artifact_key === nothing && throw(ArgumentError(
        "CoordinateSnapshotObserver must be prepared (artifact-bound) before tracking"))
    nlocal = clamp(npart - offset, 0, length(rep))
    rows = Matrix{Float64}(undef, nlocal, 8)
    rows[:, 1] .= Float64(ctx.turn)
    rows[:, 2] .= Float64.(offset .+ (1:nlocal))
    for (j, col) in enumerate((rep.x, rep.px, rep.y, rep.py, rep.z, rep.pz))
        rows[:, 2 + j] = Float64.(Array(col)[1:nlocal])
    end
    # Every rank gathers -- it is a collective -- and rank 0, which holds the
    # file, is the one whose push writes anything.
    _ra_push_probe_rows!(observer.artifact_ref, observer.artifact_key,
                         _mp_gather_rows(rows))
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



function apply_action!(action::BeamSwapAction, ctx::TrackingContext, rep)
    replacement = _call_provider(action.provider, ctx)
    replacement_rep = replacement isa Beam ? replacement.rep : replacement
    _copy_rep!(rep, replacement_rep)
    return nothing
end

function _call_provider(provider, ctx)
    return applicable(provider, ctx) ? provider(ctx) : provider()
end

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
    planned_turns = _scheduled_turns(schedule, turns, first_turn)
    planned_turns === nothing && throw(ArgumentError(
        "MomentObserver requires a predictable schedule: use AlwaysSchedule, EveryNSteps, or AtTurns with known task turns."
    ))
    observer.buffer_length = 0
    art = active_run_artifact()
    art === nothing && throw(ArgumentError(
        "MomentObserver(name=$(repr(observer.name))) is an artifact view: " *
        "the task must carry artifact=RunArtifact(...)"))
    observer.artifact_ref = art
    observer.artifact_key = _ra_bind_probe!(art, "moments", observer.name,
                                            observer.column_names,
                                            Int(first_turn);
                                            s=_active_probe_s(observer))
    # Buffering is the artifact's: one capacity for every producer.
    observer.buffer_capacity = art.capacity
    observer.buffer = Matrix{Float64}(undef, art.capacity,
                                      length(observer.column_names))
    observer.planned_records = length(planned_turns)
    observer.record_count = 0
    observer.initialized = true
    return nothing
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

function _flush_moment_observer!(observer::MomentObserver)
    observer.buffer_length == 0 && return nothing
    observer.artifact_key === nothing && throw(ArgumentError(
        "MomentObserver must be prepared (artifact-bound) before flushing"))
    _ra_push_probe_rows!(observer.artifact_ref, observer.artifact_key,
                         observer.buffer[1:observer.buffer_length, :])
    observer.record_count += observer.buffer_length
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
    local_n = length(arrays[1])
    islive = k -> _moment_live(flags, k)
    nlive = _masked_global_count(islive, local_n)
    # An all-dead beam has no moments to report. `NaN` is the honest value, and
    # the turn column stays intact so the record still says *when* that happened.
    if nlive == 0
        fill!(view(row, 2:length(row)), NaN)
        return row
    end
    means = ntuple(6) do i
        a = arrays[i]
        Float64(_masked_global_sum(k -> @inbounds(a[k]), islive, local_n) / nlive)
    end
    for (j, moment) in enumerate(moments)
        row[j + 1] = _compute_moment(arrays, means, moment, flags, nlive)
    end
    return row
end

if _HAS_CUDA
    @eval begin
        # One fused kernel serves both passes of the moment row. Each thread
        # reads its particle's six coordinates ONCE and accumulates a term for
        # all NM requested power rows in registers; blocks tree-reduce each
        # accumulator in shared memory in a fixed order and the host finishes
        # over the block partials in block order — deterministic for a fixed
        # (n, threads, blocks), with no floating-point atomics anywhere.
        #
        # Pass 1 uses `means = 0` with the six identity power rows plus one
        # all-zero row: a zero-power row's term is exactly 1.0, so its
        # accumulator counts the particles the mask admitted. Pass 2 gets the
        # real means and the order >= 2 rows, in chunks of
        # `_CUDA_FUSED_MOMENT_CHUNK` power rows. The per-moment
        # fill/broadcast/sum loop this replaces made ~33 host sync round-trips
        # and ~80 full-array passes per observed turn — 1.53 ms at 1M
        # particles against 0.63 ms for a single reduction (2026-08-11
        # record); the fused path makes 1 + ceil(nm/32) round-trips and as
        # many passes — 2 for the default 27-moment set.
        #
        # The power rows arrive as a Val TYPE PARAMETER, not data: with
        # runtime powers the inner loops were branchy shared-memory walks and
        # the kernel ran latency-bound at the same ~0.9 ms/turn on the RTX
        # 4500 Ada and the A100 — the fingerprint of dependent-chain latency,
        # which neither FP64 rate nor bandwidth buys back. As compile-time
        # constants the loops unroll to bare multiplies (the default
        # second-order set becomes 21 pair products), measured 0.90 -> 0.52
        # ms/turn on the Ada and 3.84 -> 1.50 for orders=1:3. Each distinct
        # moment selection JIT-compiles its own kernel once per session,
        # cached by CUDA.jl on the Val type.
        #
        # `use_mask` is a runtime Bool, not a Val: both branches share one
        # compiled kernel, so the unmasked path cannot drift a ulp from the
        # masked path over identical live data. Dead particles are skipped by
        # re-testing `is_live` on the coordinates rather than through a
        # precomputed flags array; with the mask off every particle
        # contributes and a non-finite coordinate stays LOUD (NaN row), as on
        # the CPU path.
        # Elementwise tuple add as a separate function: `map` on tuples of 32+
        # elements takes Base's generic `Any32` path, which allocates and is
        # invalid GPU IR — exactly at the chunk width. A closure over function
        # ARGUMENTS is box-free (they are never reassigned), unlike one over
        # the kernel's reassigned accumulator local.
        @inline _moment_tuple_add(a::NTuple{N,Float64}, b::NTuple{N,Float64}) where {N} =
            ntuple(i -> @inbounds(a[i] + b[i]), Val(N))

        function _cuda_fused_moment_kernel!(partials, x, px, y, py, z, pz,
                                            ::Val{POWERS}, means, use_mask::Bool,
                                            n::Int) where {POWERS}
            NM = length(POWERS)
            tid = CUDA.threadIdx().x
            nthreads = CUDA.blockDim().x
            bid = CUDA.blockIdx().x
            stride = CUDA.gridDim().x * nthreads
            accs = ntuple(_ -> 0.0, Val(length(POWERS)))
            i = (bid - 1) * nthreads + tid
            @inbounds while i <= n
                xi = Float64(x[i]); pxi = Float64(px[i]); yi = Float64(y[i])
                pyi = Float64(py[i]); zi = Float64(z[i]); pzi = Float64(pz[i])
                if !use_mask || is_live(xi, pxi, yi, pyi, zi, pzi)
                    diffs = (xi - means[1], pxi - means[2], yi - means[3],
                             pyi - means[4], zi - means[5], pzi - means[6])
                    # `terms` then `map`, not an accumulating closure: a
                    # closure that captured the reassigned `accs` would box it
                    # and fail GPU compilation. POWERS[m][d] is a compile-time
                    # constant, so both inner loops unroll away.
                    terms = ntuple(Val(length(POWERS))) do m
                        term = 1.0
                        for d in 1:6
                            p = POWERS[m][d]
                            for _ in 1:p
                                term *= diffs[d]
                            end
                        end
                        term
                    end
                    accs = _moment_tuple_add(accs, terms)
                end
                i += stride
            end
            shared = CUDA.CuDynamicSharedArray(Float64, nthreads)
            for m in 1:NM
                @inbounds shared[tid] = accs[m]
                CUDA.sync_threads()
                s = nthreads >> 1
                while s > 0
                    if tid <= s
                        @inbounds shared[tid] += shared[tid + s]
                    end
                    CUDA.sync_threads()
                    s >>= 1
                end
                if tid == 1
                    @inbounds partials[bid, m] = shared[1]
                end
                CUDA.sync_threads()
            end
            return nothing
        end

        # Register accumulators bound one fused pass: past this many order >= 2
        # rows the kernel's ntuple would spill to local memory and invert the
        # win, so larger selections run the SAME kernel in chunks of this
        # width — ceil(nm/32) passes and syncs instead of one per moment. The
        # default orders=1:2 set has 21 rows (one chunk); orders=1:3 has 77
        # (three chunks, for the planned tail studies).
        const _CUDA_FUSED_MOMENT_CHUNK = 32
        const _CUDA_MOMENT_THREADS = 256
        const _CUDA_MOMENT_PASS1_VAL = Val((
            (1, 0, 0, 0, 0, 0), (0, 1, 0, 0, 0, 0), (0, 0, 1, 0, 0, 0),
            (0, 0, 0, 1, 0, 0), (0, 0, 0, 0, 1, 0), (0, 0, 0, 0, 0, 1),
            (0, 0, 0, 0, 0, 0)))

        function _cuda_moment_workspace!(observer::MomentObserver, moments::Tuple, n::Int)
            reduce_idx = [j for (j, m) in enumerate(moments) if sum(m.powers) >= 2]
            nm2 = length(reduce_idx)
            width = min(nm2, _CUDA_FUSED_MOMENT_CHUNK)
            blocks = max(min(cld(n, _CUDA_MOMENT_THREADS), 256), 1)
            ws = observer.reduction_scratch
            valid = ws isa NamedTuple && ws.n == n && ws.reduce_idx == reduce_idx
            valid && return ws
            # One (offset, count, Val-of-powers) entry per chunk; the Val's
            # type identity is what keys the JIT cache to this selection.
            chunks = Tuple{Int,Int,Any}[]
            off = 0
            while off < nm2
                c = min(_CUDA_FUSED_MOMENT_CHUNK, nm2 - off)
                # `let`-bound copy: capturing the reassigned loop variable
                # would box it (the suite's Core.Box tripwire caught exactly
                # that here on the first version).
                val = let base = off
                    Val(ntuple(m -> moments[reduce_idx[base + m]].powers, c))
                end
                push!(chunks, (off, c, val))
                off += c
            end
            ws = (n=n, reduce_idx=reduce_idx, blocks=blocks, chunks=chunks,
                  partials1=CUDA.CuArray{Float64}(undef, blocks, 7),
                  partials2=nm2 == 0 ? nothing : CUDA.CuArray{Float64}(undef, blocks, width),
                  host1=Matrix{Float64}(undef, blocks, 7),
                  host2=nm2 == 0 ? nothing : Matrix{Float64}(undef, blocks, width))
            observer.reduction_scratch = ws
            return ws
        end

        # Host-side fixed-order finish of the block partials: column sums in
        # block order, deterministic like the kernel's tree. `nm` bounds the
        # valid columns — a partial chunk leaves stale data in the rest of the
        # reused buffer.
        function _cuda_moment_block_sums!(host, partials, nm::Int)
            copyto!(host, partials)
            nb = size(host, 1)
            return ntuple(nm) do m
                s = 0.0
                @inbounds for b in 1:nb
                    s += host[b, m]
                end
                s
            end
        end

        function _moment_observer_row(ctx::TrackingContext,
                                      rep::Phase6DRep{<:CUDA.CuArray}, moments::Tuple,
                                      observer::MomentObserver)
            row = Vector{Float64}(undef, length(moments) + 1)
            row[1] = Float64(ctx.turn)
            isempty(moments) && return row
            arrays = coordinate_arrays(rep)
            n = length(arrays[1])
            use_mask = allow_lost_particles()
            ws = _cuda_moment_workspace!(observer, moments, n)
            threads = _CUDA_MOMENT_THREADS
            shmem = threads * sizeof(Float64)
            zero6 = ntuple(_ -> 0.0, 6)
            CUDA.@cuda threads=threads blocks=ws.blocks shmem=shmem _cuda_fused_moment_kernel!(
                ws.partials1, arrays..., _CUDA_MOMENT_PASS1_VAL, zero6, use_mask, n)
            sums = _cuda_moment_block_sums!(ws.host1, ws.partials1, 7)
            nlive = use_mask ? Int(sums[7]) : n
            if nlive == 0
                fill!(view(row, 2:length(row)), NaN)
                return row
            end
            means = ntuple(d -> sums[d] / nlive, 6)
            for (off, c, val) in ws.chunks
                CUDA.@cuda threads=threads blocks=ws.blocks shmem=shmem _cuda_fused_moment_kernel!(
                    ws.partials2, arrays..., val, means, use_mask, n)
                sums2 = _cuda_moment_block_sums!(ws.host2, ws.partials2, c)
                for slot in 1:c
                    row[ws.reduce_idx[off + slot] + 1] = sums2[slot] / nlive
                end
            end
            for (j, moment) in enumerate(moments)
                order = sum(moment.powers)
                order >= 2 && continue
                row[j + 1] = order == 1 ? means[findfirst(!=(0), moment.powers)] : 1.0
            end
            return row
        end
    end
end

function _compute_moment(arrays, means, moment::Moment, flags=nothing, nlive=length(arrays[1]))
    powers = moment.powers
    order = sum(powers)
    order == 1 && return means[findfirst(!=(0), powers)]
    n = length(arrays[1])
    islive = i -> _moment_live(flags, i)
    term = i -> begin
        t = 1.0
        @inbounds for d in 1:6
            p = powers[d]
            p == 0 && continue
            t *= (arrays[d][i] - means[d]) ^ p
        end
        t
    end
    return _masked_global_sum(term, islive, n) / nlive
end

"""
    MomentOutput(path)

Lightweight handle for reading a `MomentObserver` output file.

For HDF5 files written by `MomentObserver`, `read(file)` returns the full
written `/data` matrix up to `/record_count`. Use `read(file, item)` for one
column and keyword moment selection for a smaller matrix.

```julia
out = MomentOutput("result/pic_hcc.h5")

data = read(out)
turn = read(out, :turn)
mx = read(out, Moment(; x = 1))
sxpx = read(out, :m110000)
first_second = read(out; orders = 1:2)
names = column_names(out)
records = read(out, :record_count)
seconds = read(out, :elapsed_time)
```

`MomentOutput` is the preferred reader for moment output (renamed from
`MomentOutputFile` 2026-08-18, matching `TaskOutput`). `MomentOutputFile`,
`OutputFile` and `MomentFile` remain compatibility aliases.
"""
struct MomentOutput
    path::String
    # "" reads a standalone moment file at the HDF5 root (the pre-artifact
    # layout, still readable); "moments/<name>" reads that probe's group
    # inside a run artifact (docs/design/run_artifact.md).
    group::String
end

MomentOutput(path::AbstractString; name::Union{Nothing,AbstractString}=nothing) =
    MomentOutput(String(path), name === nothing ? "" : "moments/" * String(name))

const MomentOutputFile = MomentOutput
const OutputFile = MomentOutput
const MomentFile = MomentOutput

const _READ_ALL_MOMENT_COLUMNS = :__octopus_read_all_moment_columns__

"""
    read(file::MomentOutput)
    read(file::MomentOutput; orders=..., extra=(), exclude=())

Read an output data matrix.

With no keyword selection, this returns the full written data matrix
`/data[1:record_count, :]`. Column 1 is `turn`, and the remaining columns match
`column_names(file)`.

With `orders`, `extra`, or `exclude`, this returns a selected HDF5 moment table.
The returned matrix still includes `turn` as column 1. Selection uses the same
rules as `MomentObserver`: expand `orders`, add `extra`, then remove `exclude`.
Unavailable requested moments are skipped.

```julia
out = MomentOutput("moments.h5")
data = read(out)
names = column_names(out)

first_order = read(out; orders = 1)
first_second = read(out; orders = 1:2)
selected = read(out; orders = (), extra = (Moment(; pz = 4),))
without_z2 = read(out; orders = 1:2, exclude = (Moment(; z = 2),))
```
"""
function read(file::MomentOutput; orders=_READ_ALL_MOMENT_COLUMNS, extra=(), exclude=())
    if !_is_hdf5_output(file.path)
        orders === _READ_ALL_MOMENT_COLUMNS && isempty(extra) && isempty(exclude) && return _read_moment(file.path, :data)
        throw(ArgumentError("keyword moment selection is only supported for HDF5 output files"))
    end
    if orders === _READ_ALL_MOMENT_COLUMNS && isempty(extra) && isempty(exclude)
        return _read_hdf5_data(file.path, file.group)
    end
    return _read_hdf5_selection(file.path, file.group;
                                orders=orders, extra=extra, exclude=exclude)
end

"""
    read(file::MomentOutput, item)

Read one named output column or progress field.

For HDF5 moment output, `item` may be:

- `:turn` or `"turn"`
- a `Moment`, such as `Moment(; x=1)`
- a compact or separated moment name, such as `:m100000` or `:m1_0_0_0_0_0`
- `:record_count`
- `:elapsed_time`

Examples:

```julia
out = MomentOutput("moments.h5")
turns = read(out, :turn)
mx = read(out, Moment(; x = 1))
sxpx = read(out, :m110000)
records = read(out, :record_count)
seconds = read(out, :elapsed_time)
```
"""
function read(file::MomentOutput, item::Union{Moment,Symbol,AbstractString})
    _is_hdf5_output(file.path) && return _read_hdf5_column(file.path, file.group, item)
    item isa Symbol && return _read_moment(file.path, item)
    item isa AbstractString && return _read_moment(file.path, Symbol(item))
    return _read_moment(file.path, Symbol(name(item)))
end

"""
    column_names(file::MomentOutput)

Return output column names as strings.

For `MomentObserver` HDF5 files, this reads `/column_names`. The returned names
align with columns of `read(file)`.

```julia
out = MomentOutput("moments.h5")
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
function column_names(file::MomentOutput)
    if _is_hdf5_output(file.path)
        return HDF5.h5open(file.path, "r") do h5
            String.(read(_moment_h5_root(h5, file.group)["column_names"]))
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
    # An artifact probe group has no record_count dataset: every row is
    # cursor-valid on disk, so the row count IS the record count.
    haskey(h5, "record_count") || return size(h5["data"], 1)
    count = read(h5["record_count"])
    return count isa AbstractArray ? Int(first(count)) : Int(count)
end

_moment_h5_root(h5, group::String) = isempty(group) ? h5 : h5[group]

function _read_hdf5_data(path::AbstractString, group::String="")
    return HDF5.h5open(path, "r") do h5
        root = _moment_h5_root(h5, group)
        n = _read_hdf5_record_count(root)
        data = read(root["data"])
        data[1:n, :]
    end
end

function _read_hdf5_column(path::AbstractString, group::String, item)
    return HDF5.h5open(path, "r") do h5
        root = _moment_h5_root(h5, group)
        special = _read_hdf5_special(root, item)
        special === _NOT_HDF5_SPECIAL || return special
        names = String.(read(root["column_names"]))
        index = _hdf5_column_index(names, item)
        n = _read_hdf5_record_count(root)
        vec(root["data"][1:n, index])
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
            "`elapsed_time` is not present here. A run artifact's timing lives " *
            "in its execution ledger: use read(TaskOutput(path), :execution). " *
            "A standalone " *
            "moment file needs recreating with the current MomentObserver."
        ))
        return Float64(first(read(h5["elapsed_time"])))
    end
    return _NOT_HDF5_SPECIAL
end

function _read_hdf5_selection(path::AbstractString, group::String="";
                              orders=(), extra=(), exclude=())
    requested = _selected_moments(orders=orders, extra=extra, exclude=exclude)
    return HDF5.h5open(path, "r") do h5
        h5 = _moment_h5_root(h5, group)
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
Read a named moment block from a legacy columnar JLD2 moment file (format
`"Octopus.JLD2BeamMomentObserver"`). The writer was removed 2026-08-11 and
the public `read_moment` name retired 2026-08-18 (owner direction) --
`read(MomentOutput(path))` and `read(MomentOutput(path), item)` are the one
reading surface, and they route through this internally so archived files
remain readable. Supported names: `:turn`, `:data`, `:mean`, `:covariance`,
`:rms`, `:emittance`, `:xz_covariance`, `:yz_covariance`,
`:diagonal_fourth_central`.
"""
function _read_moment(path::AbstractString, name::Symbol)
    return JLD2.jldopen(path, "r") do file
        _read_moment(file, name)
    end
end

function _read_moment(file, name::Symbol)
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
