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

# Process-wide registry of output paths with a live WRITER (2026-08-05_b
# audit, U7-10; re-homed on the run artifact 2026-08-18; narrowed 2026-10-21,
# comprehensive audit F-85). Two live standalone observers writing one path
# ended self-consistent and WRONG: the second's initializer truncated the
# first's rows and the survivor resynced onto the OTHER writer's rows --
# measured turn column [0, 1, 4, 5] from an interleaved 4-turn and 2-turn
# pair, with the file reporting 4 valid rows and no warning anywhere. Today
# the artifact's sidecar lock (`_ra_take_lock!`, taken BEFORE this registry
# is written) refuses a second writer on an open path by name, so the only
# collision this registry can still see is a path whose earlier artifact
# holds its file OPEN while a new one initializes -- the lock removed by hand
# -- and that is the one case it warns about. A second artifact OBJECT
# continuing or rewriting a path whose writer has finished and closed is the
# documented sequential case (a new task continuing a file, a refused task's
# path reused) and is silent: the registry asks the earlier object whether it
# is still writing (`_path_writer_is_live`), not merely whether it is still
# alive, which is what it asked until F-85 ("a second live observer ..." on
# every legitimate continuation, p1 block E). A warning rather than an error
# and per-process rather than per-task, as before: the registry keys on weak
# object identity, which can flag the collision but cannot prove intent, and
# a collected artifact's entry goes stale with it.
const _OBSERVER_PATH_REGISTRY = Dict{String,WeakRef}()
const _OBSERVER_PATH_REGISTRY_LOCK = ReentrantLock()

# Whether a registered writer still holds its output open. A run artifact
# writes between `prepare_run_artifact!` and `finalize_run_artifact!`, while
# its file handle is set; an object the registry cannot ask counts as live.
_path_writer_is_live(art::RunArtifact) = art.file !== nothing
_path_writer_is_live(::Any) = true

function _register_observer_path!(observer, path::AbstractString)
    key = abspath(String(path))
    lock(_OBSERVER_PATH_REGISTRY_LOCK) do
        prior = get(_OBSERVER_PATH_REGISTRY, key, nothing)
        if prior !== nothing
            live = prior.value
            if live !== nothing && live !== observer && _path_writer_is_live(live)
                @warn "a run artifact is initializing an output path that another run " *
                      "artifact in this process still holds open: the sidecar lock that " *
                      "refuses a second writer must have been removed by hand, and two " *
                      "open writers on one path interleave their rows into a " *
                      "self-consistent but wrong file. Finalize the first writer, or " *
                      "give each run its own path (U7-10; F-85, 2026-10-21)." path = key first_writer =
                      typeof(live) second_writer = typeof(observer)
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
    _refuse_repeated_observers(Any[_as_scheduled_observer(raw).observer for raw in _hook_tuple(observers)])
    for raw in _hook_tuple(observers)
        item = _as_scheduled_observer(raw)
        prepare_observer!(item.observer, runtime_elems, item.schedule, turns, first_turn)
    end
    return nothing
end

"""
    _observer_binds_one_group(observer) -> Bool

Whether the observer records into ONE artifact group (`/kind/<name>`, one arc
position), so that placing the same object twice in a line or listing it
twice among a task's hooks would send two readings per turn into one group
under one `s`: true for `MomentObserver` and `CoordinateSnapshotObserver`
(artifact views by construction) and for a `BPMObserver` with
`artifact=true` (its method is in BPMObserver.jl); false by default -- a
memory-mode BPM reads as often as it is placed, the "read twice in one turn"
pattern its occurrence counter exists for. Consulted by the task-level prepare walk
(`prepare_observers!`) and, for a line's placements, by the line compile
(`_refuse_repeated_line_observers` from `_runtime_entries`, once per
compilation; the per-execute! walk `prepare_line_observers!` stays
allocation-free under the 2026-10-16 cost pin) through
`_refuse_repeated_observers`, which refuses such an observer placed more than
once BY ITS CAUSE, before any bind: until 2026-10-21 the second placement
reached the artifact bind and was refused as a "duplicate probe name", a
message about a NAME two objects share when one object had been placed twice
(comprehensive audit 2026-10-18, F-89). Two DISTINCT objects sharing a name
are still the artifact's refusal.
"""
_observer_binds_one_group(::AbstractBeamObserver) = false
# (the MomentObserver and CoordinateSnapshotObserver methods follow their types below)

_observer_display_name(obs) =
    hasfield(typeof(obs), :name) ? String(getfield(obs, :name)) : string(nameof(typeof(obs)))

# `observers` are the RAW observer objects of one prepare walk (task hooks, or
# one line's placements), counted by object identity.
function _refuse_repeated_observers(observers)
    counts = IdDict{Any,Int}()
    order = Any[]
    for obs in observers
        haskey(counts, obs) || push!(order, obs)
        counts[obs] = get(counts, obs, 0) + 1
    end
    for obs in order
        counts[obs] > 1 && _observer_binds_one_group(obs) && throw(ArgumentError(
            "$(nameof(typeof(obs)))(name=$(repr(_observer_display_name(obs)))) is placed " *
            "$(counts[obs]) times in this task (in the line or among its hooks) and records " *
            "one artifact group with one arc position, so two readings per turn would land in " *
            "one group under one `s`: give each placement its own observer object (a distinct " *
            "name), or, for a BPM, read in memory mode (artifact=false), which may be placed as " *
            "often as the lattice has pickups"))
    end
    return nothing
end

"""
    _refuse_repeated_line_observers(entries::Tuple) -> nothing

The line placements' half of the repeated-observer refusal (F-89), run ONCE
per compilation by `_runtime_entries` over the compiled line's resolved hook
entries (`_line_hook_entries`), before any artifact bind and before the
per-execute! walks, which stay allocation-free (the 2026-10-16 cost pin on
the once-per-execute! walks: fix batch 3's first gate attempt measured 352
bytes against 256 with this count inside `prepare_line_observers!`,
2026-10-22). The task-level hooks are counted by `prepare_observers!`.
"""
function _refuse_repeated_line_observers(entries::Tuple)
    placed = Any[]
    for entry in _line_hook_entries(entries)
        entry isa LineObserverEntry && push!(placed, entry.observer.observer)
    end
    _refuse_repeated_observers(placed)
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
runs this next to `prepare_observers!`, before the turn loop. The walk over
the heterogeneous entries tuple is unrolled (`_foreach_unrolled`,
src/elements/turn_modulated.jl): a `for` over it boxed the whole tuple per
element, about 190 kB per call on a 40-element line of eight types
(2026-10-16 neighbour audit, U9-4).
"""
function prepare_line_observers!(entries::Tuple; turns=nothing, first_turn=0)
    # No allocation here: this is a once-per-execute! walk under the
    # 2026-10-16 cost pin (<= 256 bytes); the repeated-placement count over the
    # line runs once per compilation in `_runtime_entries`
    # (`_refuse_repeated_line_observers`), where the hook entries are resolved
    # anyway. Fix batch 3's first gate attempt measured 352 bytes with the
    # count inside this walk (2026-10-22).
    _foreach_unrolled(entries) do entry
        entry isa LineObserverEntry && prepare_line_observer!(entry.observer, turns, first_turn)
        nothing
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
through `ScheduledObserver`, on any schedule -- `AlwaysSchedule`,
`EveryNSteps`, `AtTurns`, or a `PredicateSchedule` (accepted at one rank
since 2026-10-21; a run divided across ranks refuses every
predicate-scheduled observer, Tasks.jl). It writes one row per observation;
the artifact dataset is extensible, so nothing is sized from the schedule.

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
                          0, 0, false, nothing, String(name), nothing, nothing)
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

# Both artifact views record one group each (`_observer_binds_one_group`,
# documented with its fallback above, F-89).
_observer_binds_one_group(::MomentObserver) = true
_observer_binds_one_group(::CoordinateSnapshotObserver) = true

"""
    observer_option_schema(observer_or_type)

The observer type's configurable fields as a `NamedTuple` of
`ConfigurationOptionMeta`. Consumed by `configuration_report` and checked per
concrete observer by `validate_configuration_metadata()`.
"""
function observer_option_schema end

#
# Every option below names the `:observer_output` receipt its observer records
# at each fire, and that receipt carries a field named after each option
# (`name`, `moments` as the selection's length, `npart` beside the count
# captured): the pairing the suite derives from these schemas and checks
# (2026-10-16 fix batch, S4-3). `moments` had named `:moment_reduction`, a
# consumer no receipt ever recorded, while its value rode in this receipt all
# along; the snapshot observer recorded no receipt at all.
observer_option_schema(::Type{MomentObserver}) = (
    name=ConfigurationOptionMeta(String, nothing,
        "Group identity inside the task's run artifact (/moments/<name>); required, unique within a task.";
        category=:output, consumer=:observer_output),
    moments=ConfigurationOptionMeta(Tuple, nothing,
        "Canonical moment selection resolved from orders/extra/exclude; exclude wins. " *
        "The :observer_output receipt carries the selection's length per fire.";
        category=:output, consumer=:observer_output),)
observer_option_schema(::MomentObserver) = observer_option_schema(MomentObserver)
observer_option_schema(::Type{CoordinateSnapshotObserver}) = (
    name=ConfigurationOptionMeta(String, nothing,
        "Group identity inside the task's run artifact (/snapshot/<name>); required, unique within a task.";
        category=:output, consumer=:observer_output),
    npart=ConfigurationOptionMeta(Union{Nothing,Int}, nothing,
        "Leading particle count captured per fire; nothing captures every particle. " *
        "The :observer_output receipt carries the request beside the count captured.";
        category=:output, consumer=:observer_output),)
observer_option_schema(::CoordinateSnapshotObserver) =
    observer_option_schema(CoordinateSnapshotObserver)

function configuration_report(observer::MomentObserver)
    return (
        ConfigurationEntry(:name, observer.name, observer.name, :resolved,
            "artifact group identity (/moments/<name>)", :observer_output),
        ConfigurationEntry(:moments, observer.moments, observer.moments, :resolved,
            "canonical selection resolved from orders/extra/exclude", :observer_output),
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
    # The refusal FIRST and the receipt after it, as the snapshot twin orders
    # them: recorded before the refusal, a refused fire left a receipt
    # claiming an observation (comprehensive audit 2026-10-18, F-84). `name`
    # joined the receipt in the 2026-10-16 fix batch (S4-3): the option names
    # this receipt as its consumer, and it carried no field for it.
    observer.initialized || throw(ArgumentError(
        "MomentObserver(name=$(repr(observer.name))) must be prepared (artifact-bound) before tracking"))
    _record_execution!(:observer_output, _observer_backend(),
        (observer=:MomentObserver, name=Symbol(observer.name), turn=ctx.turn,
         capacity=observer.buffer_capacity, moments=length(observer.moments)))
    # Compute the row, THEN commit it: the count advances only once the row
    # is in the buffer. Incremented first (until 2026-10-19), an exception
    # inside `_moment_observer_row` left a stale or undefined row under the
    # count, which the best-effort finalize of the failed run pushed into the
    # artifact; the group's cursor was stamped from that row's turn column,
    # and the retry of a chunked run truncated chunk 1 away (F-73: after the
    # crash `[0,1,2,3,4,5,<garbage>]`, after the retry `[0,4,5,6,7]`).
    row = _moment_observer_row(ctx, rep, observer.moments, observer)
    observer.buffer[observer.buffer_length + 1, :] .= row
    observer.buffer_length += 1
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
    # The receipt the schema declares for `name` and `npart` (2026-10-16 fix
    # batch, S4-3; none was recorded before): the request under the option's
    # name, the count captured beside it (`nothing` requests every particle).
    # No `capacity`: a snapshot writes its block per fire and batches nothing.
    _record_execution!(:observer_output, _observer_backend(),
        (observer=:CoordinateSnapshotObserver, name=Symbol(observer.name), turn=ctx.turn,
         npart=observer.npart, captured=npart))
    nlocal = clamp(npart - offset, 0, length(rep))
    rows = _snapshot_block(rep, offset, nlocal, ctx.turn)
    # Every rank gathers -- it is a collective -- and rank 0, which holds the
    # file, is the one whose push writes anything.
    _ra_push_probe_rows!(observer.artifact_ref, observer.artifact_key,
                         _mp_gather_rows(rows))
    return nothing
end

"""
    _snapshot_block(rep, offset, nlocal, turn) -> Matrix{Float64}

The `[turn, particle_id, x, px, y, py, z, pz]` rows of this rank's part of a
snapshot: the leading `nlocal` local particles, ids `offset + 1 : offset +
nlocal` (global under a divided run), each coordinate moved through
`view(col, 1:nlocal)` -- `nlocal` elements copied, on the host or device to
host. Until 2026-10-21 each column was `Array(col)[1:nlocal]`: the WHOLE array
materialised (a full device-to-host transfer on CUDA) and then sliced, so a
16-particle snapshot cost 29.4 ms and 122.9 MB per fire at N = 2.56e6 on CUDA
and 50 ms and 48 MB at N = 1e6 on the CPU, against 0.05 ms for six 16-element
views -- the `npart` knob the docstring offers for controlling snapshot volume
controlled the rows written and nothing of the cost (comprehensive audit
2026-10-18, F-79; the BPM's six-array host copy of U7-5 living on here).
"""
function _snapshot_block(rep, offset::Int, nlocal::Int, turn)
    rows = Matrix{Float64}(undef, nlocal, 8)
    rows[:, 1] .= Float64(turn)
    rows[:, 2] .= Float64.(offset .+ (1:nlocal))
    for (j, col) in enumerate(coordinate_arrays(rep))
        rows[:, 2 + j] .= Float64.(Array(view(col, 1:nlocal)))
    end
    return rows
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

# `schedule` and `turns` are the prepare chain's arguments and decide nothing
# here since 2026-10-21 (F-87): the row buffer is sized from the artifact's
# capacity and the dataset is extensible, so no plan of the schedule's turns
# is needed -- see the note above `_scheduled_turns`.
function _prepare_moment_observer!(observer::MomentObserver, schedule, turns,
                                  first_turn::Integer=0)
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
    observer.record_count = 0
    observer.initialized = true
    return nothing
end

# `_scheduled_turns` enumerates the turns a predictable schedule fires on
# inside the ABSOLUTE window `execute!` will run, `first_turn : first_turn +
# turns - 1`, because `should_run` is handed `ctx.turn = first_turn + offset`
# (Tasks.jl); its consumer is `_warn_unfireable_schedules` (Tasks.jl), which
# warns when a hook's schedule selects no turn of the window, and `nothing`
# means "not enumerable" (a predicate), about which that warning says nothing.
# Filtering against `0:turns-1` instead -- which is what these did -- made the
# plan disagree with the predicate whenever `first_turn != 0`:
#
#   _scheduled_turns(AtTurns([100,101]), 3)  ->  Int64[]
#   while execute!(turns=3, start_turn=100) fires the observer twice
#
#   _scheduled_turns(EveryNSteps(start=0,stop=6,step=2), 3)  ->  [0,2]
#   on a SECOND execute!(turns=3), which runs turns 3,4,5 and fires once at 4
#
# `first_turn != 0` is not exotic: it is every second `execute!` on the same
# task, which Tasks.jl documents as a supported way to split a run. The
# MomentObserver's own consumer of the plan -- the preallocated HDF5 table it
# sized from `planned_records` -- retired on 2026-08-18 with the standalone
# writer (the artifact dataset is extensible), and until 2026-10-21 the
# observer still refused a PredicateSchedule as "requires a predictable
# schedule" on that table's behalf and wrote a `planned_records` that nothing
# read (comprehensive audit 2026-10-18, F-87). A predicate schedule is
# accepted now at one rank, as for every other probe; a divided run refuses
# every predicate-scheduled observer in `_reject_unsharded_tracking_features`
# (Tasks.jl), where that rule lives.
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

# Elementwise tuple add as a separate function, shared by the CPU sweep and
# the CUDA kernel: `map` on tuples of 32+ elements takes Base's generic
# `Any32` path, which allocates and is invalid GPU IR -- exactly at the chunk
# width. A closure over function ARGUMENTS is box-free (they are never
# reassigned), unlike one over a reassigned accumulator local.
@inline _moment_tuple_add(a::NTuple{N,Float64}, b::NTuple{N,Float64}) where {N} =
    ntuple(i -> @inbounds(a[i] + b[i]), Val(N))

"""
    _moment_pow(x::Float64, p::Int) -> Float64

`x^p` for a moment's power, bit for bit, without the generic `^` on every
factor of every particle: `x`, `x*x` and `x*x*x` for p = 1, 2, 3 -- exactly
what Julia 1.12's `^(::Float64, ::Integer)` returns for those powers
(`pow_body` returns `x*x*x` for 3 by name; its square-and-multiply loop for 2
reduces to `x*x` with a zero compensation term; p = 1 is `x` through its
`muladd(x, 1.0, 0.0)` finish, the signed zero included -- measured identical
on 68,009 samples across 17 decades, unit G probe `pow_identity.jl`,
2026-10-21) -- and `^` itself from p = 4 on, where `pow_body` is a
compensated product that neither `(x*x)*(x*x)` nor repeated multiplication
reproduces (34,071 and 23,639 of the 68,009 samples differ). The suite pins
the three identities against `^` on every run, so a Julia release that
changes `pow_body` fails by name rather than moving a recorded moment.
"""
@inline function _moment_pow(x::Float64, p::Int)
    p == 1 && return x
    p == 2 && return x * x
    p == 3 && return x * x * x
    return x^p
end

# Accumulators bound one fused CPU sweep as registers bound one fused CUDA
# pass (`_CUDA_FUSED_MOMENT_CHUNK`): a selection with more order >= 2 rows runs
# the same sweep in chunks of this width -- ceil(nm/32) sweeps instead of one
# serial pass per moment. The default orders=1:2 set has 21 rows (one sweep);
# orders=1:3 has 77 (three).
const _CPU_FUSED_MOMENT_CHUNK = 32

# Pass 1's power rows: the six identity rows, whose terms are the coordinates
# themselves (`1.0 * (x - 0.0) === x`, signed zero included), so the sweep's
# accumulators are the six coordinate sums.
const _CPU_MOMENT_PASS1_VAL = Val(((1, 0, 0, 0, 0, 0), (0, 1, 0, 0, 0, 0), (0, 0, 1, 0, 0, 0),
                                   (0, 0, 0, 1, 0, 0), (0, 0, 0, 0, 1, 0), (0, 0, 0, 0, 0, 1)))

"""
The CPU moment row's plan for one selection: the indices of its order >= 2
rows into `moments` and those rows' powers as `Val` type parameters, in chunks
of `_CPU_FUSED_MOMENT_CHUNK` (the CUDA workspace's shape; cached on the
observer's `reduction_scratch` when the row has an observer, built per call
otherwise). Its own type, so a CPU plan and a CUDA workspace left in that
field by the other backend never mistake each other.
"""
struct _CPUMomentPlan
    moments::Tuple
    reduce_idx::Vector{Int}
    chunks::Vector{Tuple{Int,Int,Any}}     # (offset into reduce_idx, count, Val(powers))
end

function _cpu_moment_plan(moments::Tuple, observer)
    cached = observer === nothing ? nothing : observer.reduction_scratch
    cached isa _CPUMomentPlan && cached.moments === moments && return cached
    reduce_idx = [j for (j, m) in enumerate(moments) if sum(m.powers) >= 2]
    chunks = Tuple{Int,Int,Any}[]
    off = 0
    while off < length(reduce_idx)
        c = min(_CPU_FUSED_MOMENT_CHUNK, length(reduce_idx) - off)
        # `let`-bound copy: capturing the reassigned loop variable would box
        # it (the suite's Core.Box tripwire; the CUDA workspace's precedent).
        val = let base = off
            Val(ntuple(m -> moments[reduce_idx[base + m]].powers, c))
        end
        push!(chunks, (off, c, val))
        off += c
    end
    plan = _CPUMomentPlan(moments, reduce_idx, chunks)
    observer === nothing || (observer.reduction_scratch = plan)
    return plan
end

"""
    _cpu_fused_moment_sweep(arrays, flags, n, Val(POWERS), means) -> NTuple{NM,Float64}

One serial sweep over the local particles accumulating, for every power row
of `POWERS` (a compile-time tuple of six-tuples, the CUDA kernel's
convention), the sum over the live particles of the product over the
coordinates of `(coordinate - mean)^power`: each coordinate read ONCE per
particle, the six differences formed once and shared by every row. Every
accumulator sees the same terms in the same left-to-right particle order as
the serial `_masked_global_sum` fold this replaces, each term formed as that
fold formed it (`1.0 * factor_1 * factor_2 ...` over the coordinates with a
nonzero power, in coordinate order, `_moment_pow` for the factor), so the
result is bitwise the per-moment fold's. Pass 1 of the row calls it with the
six identity rows and `means = 0` (a term is then the coordinate itself);
pass 2 with the order >= 2 rows and the means. Dead particles are skipped
through `flags` -- `nothing` when the mask is off, when a non-finite
coordinate stays LOUD and poisons the row, as before.
"""
function _cpu_fused_moment_sweep(arrays, flags, n::Int, powers::Val{POWERS},
                                 means::NTuple{6,Float64}) where {POWERS}
    x, px, y, py, z, pz = arrays
    accs = ntuple(_ -> 0.0, Val(length(POWERS)))
    @inbounds for i in 1:n
        _moment_live(flags, i) || continue
        diffs = (Float64(x[i]) - means[1], Float64(px[i]) - means[2], Float64(y[i]) - means[3],
                 Float64(py[i]) - means[4], Float64(z[i]) - means[5], Float64(pz[i]) - means[6])
        accs = _moment_tuple_add(accs, _fused_moment_terms(diffs, powers))
    end
    return accs
end

"""
    _fused_moment_terms(diffs::NTuple{6,Float64}, Val(POWERS)) -> NTuple{NM,Float64}

One particle's term for every power row of `POWERS`, as STRAIGHT-LINE code
generated from the rows: row `(2, 0, 0, 0, 0, 0)` becomes
`1.0 * _moment_pow(diffs[1], 2)`, row `(1, 1, 0, 0, 0, 0)` becomes
`(1.0 * _moment_pow(diffs[1], 1)) * _moment_pow(diffs[2], 1)` -- the factors
of the nonzero powers in coordinate order, left-associated from `1.0`,
exactly the `t = 1.0; t *= (a[i] - mean)^p` fold of the row this replaces,
with every index and power a literal so `_moment_pow` folds to its multiply.
A `@generated` function rather than an `ntuple` closure over the type
parameter: measured on the fused row's first cut (unit G, 2026-10-21), the
closure's inner loops over the six coordinates ran at RUNTIME on the host --
250 ns per particle for 27 moments, 25.0 ms per row at N = 1e5 against 40.6
before -- where the CUDA kernel's identical source unrolls on the device.
"""
@generated function _fused_moment_terms(diffs::NTuple{6,Float64}, ::Val{POWERS}) where {POWERS}
    terms = Expr[]
    for row in POWERS
        ex = :(1.0)
        for d in 1:6
            p = row[d]
            p == 0 && continue
            ex = :($ex * _moment_pow(diffs[$d], $p))
        end
        push!(terms, ex)
    end
    return Expr(:tuple, terms...)
end

# The sweep's partials summed across the ranks in rank order, elementwise
# (`_mp_allsum!`), as the tuple; at one rank the partials ARE the totals and
# no arithmetic happens that the undivided run did not do. Under a divided run
# one all-sum per sweep replaces one per quantity: elementwise, so each
# quantity's total is the bits the per-quantity all-sum produced.
function _cpu_moment_global_sums(arrays, flags, n::Int, val, means::NTuple{6,Float64})
    accs = _cpu_fused_moment_sweep(arrays, flags, n, val, means)
    _mp_nranks() == 1 && return accs
    partial = collect(accs)
    _mp_allsum!(partial)
    return ntuple(i -> partial[i], length(accs))
end

"""
    _moment_observer_row(ctx, rep, moments, observer=nothing) -> Vector{Float64}

One row of a `MomentObserver`: the absolute turn, then every selected moment
over the live particles -- the CPU method (the CUDA twin below dispatches on a
device representation). Two fused serial sweeps over the beam, as the CUDA
twin makes two fused passes: pass 1 the six coordinate sums (the live count
comes from the mask), pass 2 every order >= 2 row in chunks of
`_CPU_FUSED_MOMENT_CHUNK` (`_cpu_fused_moment_sweep`); first-order moments are
the means. The arrays are read in place -- a `Vector`, a view, any
`AbstractVector` -- so the row allocates nothing proportional to the beam.
Until 2026-10-21 the row copied all six arrays (`map(collect, ...)`, 4.80 MB
per row at N = 1e5) and made one serial `_masked_global_sum` pass per moment
with the generic `^` on every factor: 27.6 to 40 ms per row for the default
27 moments, 69 to 75 % of a harness-like CPU turn at four threads
(comprehensive audit 2026-10-18, F-78; todo row 14). The fused row keeps "a
lost particle is excluded from every reduction, exactly" (one live mask from
all six coordinates, shared by both passes) and is BITWISE the fold it
replaces -- the same accumulation order per quantity, the same term
arithmetic (`_moment_pow`); the suite's oracle testset pins that on both
element types, masked and unmasked, and the `/moments` fixtures written
before and after were byte-identical (unit G's report).
"""
function _moment_observer_row(ctx::TrackingContext, rep, moments::Tuple, observer=nothing)
    row = Vector{Float64}(undef, length(moments) + 1)
    row[1] = Float64(ctx.turn)
    isempty(moments) && return row
    arrays = coordinate_arrays(rep)
    flags = _moment_live_flags(arrays)
    local_n = length(arrays[1])
    nlive = flags === nothing ? _mp_global_count(local_n) :
                                _masked_global_count(k -> @inbounds(flags[k]), local_n)
    # An all-dead beam has no moments to report. `NaN` is the honest value, and
    # the turn column stays intact so the record still says *when* that happened.
    if nlive == 0
        fill!(view(row, 2:length(row)), NaN)
        return row
    end
    sums = _cpu_moment_global_sums(arrays, flags, local_n, _CPU_MOMENT_PASS1_VAL, ntuple(_ -> 0.0, 6))
    means = ntuple(d -> sums[d] / nlive, 6)
    plan = _cpu_moment_plan(moments, observer)
    for (off, c, val) in plan.chunks
        accs = _cpu_moment_global_sums(arrays, flags, local_n, val, means)
        for slot in 1:c
            row[plan.reduce_idx[off + slot] + 1] = accs[slot] / nlive
        end
    end
    for (j, moment) in enumerate(moments)
        order = sum(moment.powers)
        order >= 2 && continue
        row[j + 1] = order == 1 ? means[findfirst(!=(0), moment.powers)] : 1.0
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
        # `_moment_tuple_add` (the shared section above) is the elementwise
        # tuple add both the kernel and the CPU sweep use.
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

"""
    MomentOutput(path)

Lightweight handle for reading a `MomentObserver` output file.

For HDF5 files written by `MomentObserver`, `read(file)` returns the full
written `/data` matrix up to the record count -- the `record_count` dataset
of a standalone (pre-artifact) file, or the rows the group's `rows_valid`
cursor blesses inside a run artifact, so a torn tail beyond the cursor is
never returned (2026-10-19). Use `read(file, item)` for one column and
keyword moment selection for a smaller matrix.

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
`/data[1:record_count, :]` (an artifact group's record count is its cursor's
`rows_valid`, the rows `read(file, :record_count)` reports). Column 1 is
`turn`, and the remaining columns match `column_names(file)`.

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
- `:record_count` -- the rows a read returns: an artifact group's cursor-blessed
  rows (`rows_valid`), a standalone file's `record_count`
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
        return _ra_open(file.path) do h5
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
    # A standalone (pre-artifact) moment file counts its records in the
    # `record_count` dataset. An artifact probe group has none: its records
    # are the rows its cursor blesses (`_ra_rows_valid`, RunArtifact.jl) --
    # until 2026-10-19 this took every row on disk, so a torn tail of fill
    # rows read back as data and `:record_count` counted it (F-59).
    haskey(h5, "record_count") ||
        return _ra_rows_valid(h5, size(h5["data"], 1), String(HDF5.name(h5)))
    count = read(h5["record_count"])
    return count isa AbstractArray ? Int(first(count)) : Int(count)
end

_moment_h5_root(h5, group::String) = isempty(group) ? h5 : h5[group]

function _read_hdf5_data(path::AbstractString, group::String="")
    return _ra_open(path) do h5
        root = _moment_h5_root(h5, group)
        n = _read_hdf5_record_count(root)
        data = read(root["data"])
        data[1:n, :]
    end
end

function _read_hdf5_column(path::AbstractString, group::String, item)
    return _ra_open(path) do h5
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
    return _ra_open(path) do h5
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
