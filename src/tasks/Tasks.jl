export TrackingContext, TrackingTask, execute!, update!, luminosity

"""
    update!(elem, ctx)

Per-turn runtime-element update hook. Elements that need turn-dependent
ramping, modulation, or cached state should extend this method.
"""
update!(elem, ctx::TrackingContext) = nothing
update!(elem::ThinStrongBeam, ctx::TrackingContext) =
    update_strong_beam!(elem, ctx.turn)
update!(elem::GaussianStrongBeam, ctx::TrackingContext) =
    update_strong_beam!(elem, ctx.turn)

"""
    luminosity(elem, ctx, rep)

Per-element luminosity hook. Non-beam-beam elements return `0.0`; beam-beam
elements report the luminosity stored during diagnostic tracking.
"""
luminosity(elem, ctx::TrackingContext, rep) = 0.0
luminosity(elem::Union{ThinStrongBeam,GaussianStrongBeam}, ctx::TrackingContext, rep) =
    elem.last_luminosity

"""
    TrackingTask

Workflow for tracking one or more element specs through a phase-space
representation. Each element spec owns its selected tracking method. The
execution policy is inferred from particle storage by default or supplied
explicitly to select CPU concurrency or CUDA launch configuration.

Typical use:

```julia
line = (
    CrabDispersionSpec{Float64}(zeta1 = 0.1),
    MomentumDispersionSpec{Float64}(eta1 = 0.2),
)

rep = Phase6DRep([1.0], [2.0], [3.0], [4.0], [5.0], [6.0])
task = TrackingTask(line)
execute!(task, rep; turns = 1)
```

Put scheduled observers/actions directly in the line when location matters.
Task-level hooks run at turn boundaries.
"""
struct TrackingTask <: AbstractTask
    elements::Tuple
    policy::Union{Nothing,AbstractExecutionPolicy}
    actions::Tuple
    observers::Tuple
    contracts::Vector{DataType}
    analyses::Vector{DataType}
    runtime_entries_cache::Base.RefValue{Any}
    plan_cache::Dict{Any,Any}
end

function configuration_report(task::TrackingTask, rep::Phase6DRep)
    policy = task.policy === nothing ?
        (_infer_backend(rep) === CPUThreadsBackend ? CPUThreadsExecutionPolicy() : CUDAExecutionPolicy()) :
        task.policy
    action_reports = Tuple((
        action=Symbol(nameof(typeof(item.action))),
        schedule=configuration_report(item.schedule),
    ) for item in task.actions)
    observer_reports = Tuple((
        observer=configuration_report(item.observer),
        schedule=configuration_report(item.schedule),
    ) for item in task.observers)
    return (policy=configuration_report(policy, rep),
            actions=action_reports, observers=observer_reports)
end

"""
    TrackingTask(elements; policy=nothing,
                 hooks=(),
                 contracts=..., analyses=...)

Construct a tracking workflow from one element spec or a sequence of element
specs. The sequence is stored as a tuple so it can later compile to the
tuple-based runtime line used by `fusedTrack`. If `policy=nothing`, a default
policy is inferred from the representation passed to `execute!`. An explicit
policy must match storage and its resolved worker count or CUDA launch geometry
is applied to both fused and isolated tracking segments. The immutable
`TrackingContext` used by context-aware stochastic
tracking snapshots the Octopus global RNG state at execution time. `hooks` may
contain scheduled or unscheduled observers and actions.
Actions run before each turn and may mutate the representation; observers run
after each turn and should be read-only.

Line-level hooks can also appear inside `elements`:

```julia
line = (
    crab_cavity,
    beam_beam,
    ScheduledObserver(LuminosityObserver("luminosity.dat")),
    radiation,
)
```

Inactive scheduled line hooks do not break fusion. `TrackingTask` caches plans
by active hook pattern and keeps runtime element objects by reference, so
turn-dependent updates mutate the cached runtime objects in place.

The older `actions` and `observers` keywords remain accepted as compatibility
aliases and are merged into `hooks`.
"""
function TrackingTask(elements;
                      policy::Union{Nothing,AbstractExecutionPolicy}=nothing,
                      seed=nothing,
                      hooks=(),
                      actions=(),
                      observers=(),
                      contracts::Vector{DataType}=_collect_contracts(elements),
                      analyses::Vector{DataType}=_collect_analyses(elements))
    element_tuple = _element_tuple(elements)
    seed !== nothing && @warn "TrackingTask seed keyword is deprecated; use set_global_rng!(seed=...) instead." seed
    action_tuple, observer_tuple = classify_task_hooks(hooks, actions, observers)
    return TrackingTask(element_tuple, policy, action_tuple, observer_tuple, contracts, analyses,
                        Ref{Any}(nothing), Dict{Any,Any}())
end

_element_tuple(element::AbstractElementSpec) = (element,)
_element_tuple(elements::Tuple) = elements
_element_tuple(elements::AbstractVector) = Tuple(elements)

_first_element(element::AbstractElementSpec) = element
_first_element(elements) = first(_element_tuple(elements))

function _collect_contracts(elements)
    contracts = DataType[]
    for element in _element_tuple(elements)
        element isa AbstractElementSpec && append!(contracts, required_contracts(element))
    end
    return unique(contracts)
end

function _collect_analyses(elements)
    analyses = DataType[]
    for element in _element_tuple(elements)
        element isa AbstractElementSpec && append!(analyses, supported_analyses(element))
    end
    return unique(analyses)
end

"""
    execute!(task::TrackingTask, rep; turns=1)
    execute!(task::TrackingTask, beam::Beam; turns=1)

Execute a tracking task on an existing phase-space representation. Each element
spec in `task.elements` is compiled with `compile_runtime`, one execution
policy is resolved and checked against representation storage, and particles
are tracked through the resulting runtime element sequence in place.

Returns `rep`.
"""
execute!(task::TrackingTask, beam::Beam; turns::Integer=1) =
    (execute!(task, beam.rep; turns=turns); beam)

function execute!(task::TrackingTask, rep; turns::Integer=1)
    runtime_entries = _runtime_entries(task)
    runtime_elems = _physics_line(runtime_entries)
    policy = _resolve_execution_policy(task.policy, rep)
    return _with_execution_policy(policy) do
        _execute_tracking_task!(task, rep, runtime_entries, runtime_elems, Int(turns), policy)
    end
end

function _execute_tracking_task!(task, rep, runtime_entries, runtime_elems,
                                 turns::Int, policy)
    if isempty(task.actions) && isempty(task.observers) && !_has_line_hooks(runtime_entries)
        _execute_fast_tracking_turns!(rep, runtime_elems, turns, policy, TrackingContext())
        return rep
    end
    prepare_observers!(task.observers, runtime_elems; turns=turns)
    prepare_line_observers!(runtime_entries; turns=turns)
    try
        base_ctx = TrackingContext()
        for turn in 0:(turns - 1)
            ctx = with_turn(base_ctx, turn)
            run_actions!(task.actions, ctx, rep)
            task_diagnostics = requires_elementwise_tracking(task.observers, ctx)
            plan_key = _active_plan_key(runtime_entries, ctx, task_diagnostics)
            plan = get!(task.plan_cache, plan_key) do
                _build_tracking_plan(runtime_entries, plan_key)
            end
            _execute_tracking_plan_turn!(rep, plan, policy, ctx)
            run_observers!(task.observers, ctx, rep)
        end
    finally
        finalize_observers!(task.observers)
        _finalize_line_observers!(runtime_entries)
    end
    return rep
end

function _execute_fast_tracking_turns!(rep, runtime_elems, turns::Int, policy,
                                       base_ctx::TrackingContext)
    for turn in 0:(turns - 1)
        ctx = with_turn(base_ctx, turn)
        _update_runtime_line!(runtime_elems, ctx)
        track!(rep, runtime_elems, 1, policy, ctx)
    end
    return nothing
end

_runtime_or_existing(element::AbstractElementSpec) = compile_runtime(element)
_runtime_or_existing(element) = element

struct PhysicsEntry{E}
    element::E
end

struct LineObserverEntry{O}
    observer::O
    hook_index::Int
end

struct LineActionEntry{A}
    action::A
    hook_index::Int
end

function _runtime_entries(task::TrackingTask)
    cached = task.runtime_entries_cache[]
    cached === nothing || return cached
    entries = _runtime_line_entries(task.elements)
    task.runtime_entries_cache[] = entries
    empty!(task.plan_cache)
    return entries
end

function _runtime_line_entries(elements)
    out = Any[]
    hook_counter = Ref(0)
    _append_runtime_line!(out, elements, hook_counter)
    return Tuple(out)
end

function _append_runtime_line!(out, elements::Tuple, hook_counter)
    for element in elements
        _append_runtime_line!(out, element, hook_counter)
    end
    return out
end

function _append_runtime_line!(out, element::AbstractVector, hook_counter)
    for item in element
        _append_runtime_line!(out, item, hook_counter)
    end
    return out
end

function _append_runtime_line!(out, element, hook_counter)
    line_entry = _line_entry_or_nothing(element, hook_counter)
    if line_entry !== nothing
        push!(out, line_entry)
        return out
    end
    runtime = _runtime_or_existing(element)
    if runtime isa Tuple
        _append_runtime_line!(out, runtime, hook_counter)
    else
        push!(out, PhysicsEntry(runtime))
    end
    return out
end

_line_entry_or_nothing(element, hook_counter) = nothing
_line_entry_active(entry, ctx) = false
_line_entry_requires_diagnostics(entry) = false

function _physics_line(entries::Tuple)
    return Tuple(entry.element for entry in entries if entry isa PhysicsEntry)
end

_has_line_hooks(entries::Tuple) = any(entry -> entry isa Union{LineObserverEntry,LineActionEntry}, entries)

struct FusedSegment{Elems}
    elements::Elems
end

struct IsolatedSegment{Elem}
    element::Elem
end

struct ObserverSegment{O}
    observer::O
end

struct ActionSegment{A}
    action::A
end

function _active_plan_key(entries::Tuple, ctx, task_diagnostics::Bool)
    active_hooks = Int[]
    for entry in entries
        if entry isa Union{LineObserverEntry,LineActionEntry} && _line_entry_active(entry, ctx)
            push!(active_hooks, entry.hook_index)
        end
    end
    return (Tuple(active_hooks), task_diagnostics)
end

function _build_tracking_plan(entries::Tuple, plan_key)
    active_hooks, task_diagnostics = plan_key
    active_set = Set(active_hooks)
    segments = Any[]
    fused = Any[]
    tracked = Any[]
    pending_line_diagnostics = Ref(_count_active_line_diagnostics(entries, active_set))
    _append_tracking_segments!(segments, fused, tracked, entries, active_set,
                               task_diagnostics, pending_line_diagnostics)
    _flush_fused_segment!(segments, fused)
    return Tuple(segments)
end

function _count_active_line_diagnostics(entries::Tuple, active_hooks::Set)
    count = 0
    for entry in entries
        if entry isa LineObserverEntry &&
           entry.hook_index in active_hooks &&
           _line_entry_requires_diagnostics(entry)
            count += 1
        end
    end
    return count
end

function _append_tracking_segments!(segments, fused, tracked, entries::Tuple,
                                    active_hooks::Set, task_diagnostics::Bool,
                                    pending_line_diagnostics::Base.RefValue)
    for entry in entries
        if entry isa PhysicsEntry
            elem = entry.element
            push!(tracked, elem)
            diagnostics_required = task_diagnostics || pending_line_diagnostics[] > 0
            if diagnostics_required && requires_isolated_tracking(elem)
                _flush_fused_segment!(segments, fused)
                push!(segments, IsolatedSegment(elem))
            else
                push!(fused, elem)
            end
        elseif entry isa LineObserverEntry
            entry.hook_index in active_hooks || continue
            _flush_fused_segment!(segments, fused)
            prepare_observer!(entry.observer.observer, Tuple(tracked))
            push!(segments, ObserverSegment(entry.observer))
            if _line_entry_requires_diagnostics(entry)
                pending_line_diagnostics[] -= 1
            end
        elseif entry isa LineActionEntry
            entry.hook_index in active_hooks || continue
            _flush_fused_segment!(segments, fused)
            push!(segments, ActionSegment(entry.action))
        end
    end
    return nothing
end

function _flush_fused_segment!(segments, fused)
    isempty(fused) && return nothing
    push!(segments, FusedSegment(Tuple(fused)))
    empty!(fused)
    return nothing
end

requires_isolated_tracking(elem) = false
requires_isolated_tracking(elem::Union{ThinStrongBeam,GaussianStrongBeam}) = true

function _execute_tracking_plan_turn!(rep, plan::Tuple, policy, ctx; stream=nothing)
    for segment in plan
        _execute_tracking_segment_turn!(rep, segment, policy, ctx; stream=stream)
    end
    return nothing
end

function _execute_tracking_segment_turn!(rep, segment::FusedSegment, policy, ctx; stream=nothing)
    _update_runtime_line!(segment.elements, ctx)
    _track_fused_runtime!(rep, segment.elements, policy, ctx, stream)
    return nothing
end

function _execute_tracking_segment_turn!(rep, segment::IsolatedSegment, policy, ctx; stream=nothing)
    update!(segment.element, ctx)
    _track_isolated_runtime!(rep, segment.element, policy, ctx, stream)
    return nothing
end

function _execute_tracking_segment_turn!(rep, segment::ObserverSegment, policy, ctx; stream=nothing)
    _synchronize_segment_stream(stream)
    run_observers!((segment.observer,), ctx, rep)
    return nothing
end

function _execute_tracking_segment_turn!(rep, segment::ActionSegment, policy, ctx; stream=nothing)
    _synchronize_segment_stream(stream)
    run_actions!((segment.action,), ctx, rep)
    return nothing
end

function _track_fused_runtime!(rep, elems, policy, ctx, stream)
    if policy isa ResolvedCUDAExecutionPolicy && stream !== nothing
        track!(rep, elems, 1, policy, ctx; stream=stream)
    else
        track!(rep, elems, 1, policy, ctx)
    end
    return nothing
end

function _track_isolated_runtime!(rep, elem, policy, ctx, stream)
    _record_execution!(:isolated_tracking, backend_type(policy),
                       (element=Symbol(nameof(typeof(elem))), turn=ctx.turn,
                        stream=stream === nothing ? :default : :explicit))
    if policy isa ResolvedCUDAExecutionPolicy && stream !== nothing
        track!(rep, elem, 1, policy; stream=stream)
    else
        track!(rep, elem, 1, policy)
    end
    return nothing
end

function _synchronize_segment_stream(stream)
    if stream !== nothing && _HAS_CUDA
        CUDA.synchronize(stream)
    end
    return nothing
end

function _finalize_line_observers!(entries::Tuple)
    for entry in entries
        entry isa LineObserverEntry && finalize_observer!(entry.observer.observer)
    end
    return nothing
end

function _update_runtime_line!(runtime_elems::Tuple, ctx)
    for elem in runtime_elems
        if elem isa Tuple
            _update_runtime_line!(elem, ctx)
        else
            update!(elem, ctx)
        end
    end
    return nothing
end

_hook_tuple_or_empty(hooks::Tuple) = hooks
_hook_tuple_or_empty(hooks::AbstractVector) = Tuple(hooks)
_hook_tuple_or_empty(::Nothing) = ()
_hook_tuple_or_empty(hook) = (hook,)
