export TrackingContext, TrackingTask, execute!, update!, luminosity, loss_record

"""
    update!(elem, ctx)

Per-turn runtime-element update hook. Elements that need turn-dependent
ramping, modulation, or cached state should extend this method.
"""
update!(elem, ctx::TrackingContext) = nothing

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
    next_turn::Base.RefValue{Int64}
    runtime_entries_cache::Base.RefValue{Any}
    plan_cache::Dict{Any,Any}
    loss_log::Union{Nothing,String}
    loss_report::Bool
    loss_record::Base.RefValue{Any}
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

# Loss accounting

Every `execute!` reconciles two independent counts of how many particles are
gone (see [`loss_summary`](@ref)) and reports the result, because a diagnostic
nobody fires is not a diagnostic — and the number that matters,
`unattributed`, is one no user thinks to ask for.

- **Nothing lost**: silent. A clean run prints nothing.
- **`loss_log` given**: the accounting goes into that HDF5, next to the
  per-aperture names, counts and arc positions, and the console stays quiet —
  a run that asked for an artifact should not also chatter.
- **Otherwise**: a short summary on `stdout`, broken down per collimator.
- **`unattributed != 0`**: warns either way. It means a coordinate went
  non-finite where nothing was collimating, and that should not be reachable
  only by opening a file afterwards.

The reconciliation costs one `O(N)` non-finite reduction per `execute!` call,
not per turn. `loss_report = false` skips that reduction rather than merely
silencing it, so a caller stepping one turn at a time pays nothing — but it
switches off the **detection** along with the printing: no `unattributed`
warning, and no summary written into `loss_log`. The per-particle loss records
are unaffected.
"""
function TrackingTask(elements;
                      policy::Union{Nothing,AbstractExecutionPolicy}=nothing,
                      seed=nothing,
                      hooks=(),
                      actions=(),
                      observers=(),
                      contracts::Vector{DataType}=_collect_contracts(elements),
                      analyses::Vector{DataType}=_collect_analyses(elements),
                      loss_log::Union{Nothing,AbstractString}=nothing,
                      loss_report::Bool=true)
    element_tuple = _element_tuple(elements)
    seed !== nothing && @warn "TrackingTask seed keyword is deprecated; use set_global_rng!(seed=...) instead." seed
    _warn_duplicate_radiation_streams(element_tuple)
    _warn_hidden_apertures(element_tuple)
    action_tuple, observer_tuple = classify_task_hooks(hooks, actions, observers)
    return TrackingTask(element_tuple, policy, action_tuple, observer_tuple, contracts, analyses,
                        Ref{Int64}(0), Ref{Any}(nothing), Dict{Any,Any}(),
                        loss_log === nothing ? nothing : String(loss_log),
                        loss_report, Ref{Any}(nothing))
end

"""
    loss_record(task) -> LossRecord or nothing

The task's loss record, or `nothing` if the line has no aperture or the task has
not run yet. Allocated on the first `execute!`, sized and placed to match the
representation it is given.
"""
loss_record(task::TrackingTask) = task.loss_record[]

loss_summary(rep_or_beam, task::TrackingTask) = loss_summary(rep_or_beam, task.loss_record[])
# Disambiguation, not convenience. `loss_summary(::Phase6DRep, record)` is more
# specific in the first argument and the method above is more specific in the
# second, so neither dominates and the call was a MethodError -- for exactly the
# argument `execute!(task, rep; turns=...)` hands the caller. Passing a `Beam`
# happened to work, because its method is untyped in both positions.
loss_summary(rep::Phase6DRep, task::TrackingTask) = loss_summary(rep, task.loss_record[])

"""
Warn when an aperture sits inside an own-state (kept-whole) sub-line.

A kept-whole line compiles to ONE runtime op, so the aperture binder cannot
reach an aperture inside it: the kill still happens, but with no element id,
no counts row, and no name — the loss surfaces only as the unattributed
warning (2026-08-05 audit, U11-8). Until the binder learns to thread ids
through composite lines, the honest behavior is to say so at construction.
"""
function _warn_hidden_apertures(elements::Tuple)
    hidden = Symbol[]
    _collect_hidden_apertures!(hidden, elements, false)
    isempty(hidden) || @warn "aperture(s) inside a kept-whole (own-state) line are " *
        "outside loss accounting: they still kill particles, but the losses " *
        "surface only as unattributed. Dissolve the line or place the " *
        "aperture at task level for per-aperture attribution." apertures = hidden
    return nothing
end
_collect_hidden_apertures!(out, elements::Tuple, inside) =
    (foreach(e -> _collect_hidden_apertures!(out, e, inside), elements); out)
_collect_hidden_apertures!(out, elements::AbstractVector, inside) =
    (foreach(e -> _collect_hidden_apertures!(out, e, inside), elements); out)
_collect_hidden_apertures!(out, entry::LineEntry, inside) =
    _collect_hidden_apertures!(out, getfield(entry, :spec), inside)
function _collect_hidden_apertures!(out, element::ElementSpec{:line}, inside)
    # Entering an own-state line: everything below compiles to one op.
    own = _line_has_own_state(element)
    foreach(e -> _collect_hidden_apertures!(out, e, inside || own),
            line_entries(element))
    return out
end
_collect_hidden_apertures!(out, element::ElementSpec{:aperture}, inside) =
    (inside && push!(out, Symbol(getparam(element, :name, :unnamed))); out)
_collect_hidden_apertures!(out, element, inside) = out

"""
Warn when two radiation placements in a line share an RNG stream.

`LumpedRadSpec` auto-assigns a fresh `rng_id` per spec OBJECT, so placing one
spec object twice — repeating a `BeamLine` cell is the natural way — makes
every placement draw the SAME noise for a given (turn, particle):
perfectly correlated kicks, and excitation variance scaling with the square
of the placement count instead of linearly (2026-08-05 audit, F14; measured
two kicks = exactly 2× one). Until line placements carry an identity of
their own (the deferred observer-identity scheme in `docs/todo.md`),
distinct specs — or explicit distinct `rng_id`s — are the remedy, and this
warning is what keeps the trap from being silent.
"""
function _warn_duplicate_radiation_streams(elements::Tuple)
    ids = UInt64[]
    _collect_radiation_ids!(ids, elements)
    length(ids) == length(unique(ids)) && return nothing
    dup = [id for id in unique(ids) if count(==(id), ids) > 1]
    @warn "multiple stochastic radiation placements share an rng_id: their " *
          "excitation draws are identical (correlated kicks; variance grows " *
          "with the square of the placement count, not linearly). Give each " *
          "placement its own LumpedRadSpec or an explicit distinct rng_id." rng_ids = dup
    return nothing
end
_collect_radiation_ids!(ids, elements::Tuple) =
    (foreach(e -> _collect_radiation_ids!(ids, e), elements); ids)
_collect_radiation_ids!(ids, elements::AbstractVector) =
    (foreach(e -> _collect_radiation_ids!(ids, e), elements); ids)
_collect_radiation_ids!(ids, entry::LineEntry) =
    _collect_radiation_ids!(ids, getfield(entry, :spec))
function _collect_radiation_ids!(ids, element::ElementSpec{:line})
    foreach(e -> _collect_radiation_ids!(ids, e), line_entries(element))
    return ids
end
_collect_radiation_ids!(ids, element::ElementSpec{:lumped_radiation}) =
    (push!(ids, UInt64(getparam(element, :rng_id, 0))); ids)
_collect_radiation_ids!(ids, element) = ids

"""
Aperture specs in the line, in lattice order. Their position **is** their
identity: Octopus element specs carry no id of their own, so `element_id` is the
index of the aperture in the compiled line, assigned here.
"""
function _aperture_specs(elements::Tuple)
    out = ElementSpec{:aperture}[]
    _collect_aperture_specs!(out, elements)
    return out
end

_collect_aperture_specs!(out, elements::Tuple) =
    (foreach(e -> _collect_aperture_specs!(out, e), elements); out)
# Every container `_append_runtime_line!` walks must be walked here identically:
# this collector sizes the loss record's `counts` while `_bind_apertures`
# assigns an id to every runtime aperture, and a container seen by one walker
# and not the other leaves `counts` undersized under an unchecked
# `counts[id] += 1` (audit part 7, T3).
_collect_aperture_specs!(out, elements::AbstractVector) =
    (foreach(e -> _collect_aperture_specs!(out, e), elements); out)
_collect_aperture_specs!(out, element::ElementSpec{:aperture}) = (push!(out, element); out)
_collect_aperture_specs!(out, entry::LineEntry) =
    _collect_aperture_specs!(out, getfield(entry, :spec))
_collect_aperture_specs!(out, element) = out

"""
Arc position of each aperture, in the order `_aperture_specs` returns them, so
the two line up entry for entry with `aperture_names` and `aperture_counts`.

`s` is the summed `L` of everything ahead of the aperture: the design arc length
a collimator sits at, which is how MAD-X and elegant report one and what makes a
loss file readable without the script that produced it. Zero-length entries --
markers, thin multipoles, in-line observers, the apertures themselves -- advance
nothing.

Two honest limits. A `PatchSpec` carries its path length in `dz` rather than
`L`, so a line containing one reports arc length that omits it; folding `dz` in
would be wrong as often as right, because a patch displaces a frame in a
direction that need not lie along the design orbit. And this is arc length only
-- where a magnet sits in *space* still needs the geometry layer that
`docs/theory/misalignment_and_patch_maps.md` Section 8 asks for.
"""
function _aperture_s_positions(elements)
    out = Float64[]
    _collect_aperture_s!(out, elements, Ref(0.0))
    return out
end

_collect_aperture_s!(out, elements::Tuple, s) =
    (foreach(e -> _collect_aperture_s!(out, e, s), elements); out)
_collect_aperture_s!(out, elements::AbstractVector, s) =
    (foreach(e -> _collect_aperture_s!(out, e, s), elements); out)
_collect_aperture_s!(out, element::ElementSpec{:aperture}, s) = (push!(out, s[]); out)
function _collect_aperture_s!(out, entry::LineEntry, s)
    spec = getfield(entry, :spec)
    spec isa ElementSpec{:aperture} && return (push!(out, s[]); out)
    # `_placement_length`, not a raw `:L` read: a nested own-state line
    # counted as zero length here, shifting every later aperture_s (U11-1).
    s[] += _placement_length(entry)
    return out
end
function _collect_aperture_s!(out, element, s)
    # `_placement_length` so a bare own-state line spec in a task tuple
    # contributes its contents' length, not zero (U11-1).
    element isa AbstractElementSpec && (s[] += _placement_length(element))
    return out
end

"""
Attach the shared record and the lattice-order id to every aperture in the line.

The record depends on the representation -- its size and its backend -- while the
compiled line does not, so this runs at `execute!` rather than at compile time.
Rebuilding the runtime rather than mutating the spec keeps the user's specs
reusable across beams: two tasks over two beams get two records from one spec.
"""
function _attach_loss_record(elem::Aperture{F,M,R,T}, record, id) where {F,M,R,T}
    return Aperture{F,M,typeof(record),T}(
        elem.method, elem.shape, elem.x_limit, elem.y_limit, elem.dx, elem.dy,
        elem.alive, record, Int32(id))
end

_element_tuple(element::AbstractElementSpec) = (element,)
# A line hands the task its placements. One carrying state of its own -- a
# misaligned cryostat -- stays whole, because the wrap has to enclose it.
_element_tuple(line::ElementSpec{:line}) =
    _line_has_own_state(line) ? (line,) : Tuple(line_entries(line))
_element_tuple(elements::Tuple) = elements
_element_tuple(elements::AbstractVector) = Tuple(elements)


# Contracts and analyses walk the same containers the runtime line walk does:
# a placement contributes its spec's declarations, and a nested vector or line
# is seen through rather than skipped. Before part 7's T5 fix, a task built
# from a `BeamLine` declared no contracts and no analyses, because a
# `LineEntry` is not an `AbstractElementSpec` and the walk tested only that.
function _collect_contracts(elements)
    contracts = DataType[]
    _collect_declared!(contracts, _element_tuple(elements), required_contracts)
    return unique(contracts)
end

function _collect_analyses(elements)
    analyses = DataType[]
    _collect_declared!(analyses, _element_tuple(elements), supported_analyses)
    return unique(analyses)
end

_collect_declared!(out, elements::Union{Tuple,AbstractVector}, getter) =
    (foreach(e -> _collect_declared!(out, e, getter), elements); out)
_collect_declared!(out, entry::LineEntry, getter) =
    _collect_declared!(out, getfield(entry, :spec), getter)
# A line kept whole (one carrying state of its own) still tracks through its
# placements, so their declarations apply to the task.
_collect_declared!(out, line::ElementSpec{:line}, getter) =
    (append!(out, getter(line)); _collect_declared!(out, line_entries(line), getter))
_collect_declared!(out, element::AbstractElementSpec, getter) =
    (append!(out, getter(element)); out)
_collect_declared!(out, element, getter) = out

"""
    execute!(task::TrackingTask, rep; turns=1, start_turn=nothing)
    execute!(task::TrackingTask, beam::Beam; turns=1, start_turn=nothing)

Execute a tracking task on an existing phase-space representation. Each element
spec in `task.elements` is compiled with `compile_runtime`, one execution
policy is resolved and checked against representation storage, and particles
are tracked through the resulting runtime element sequence in place.

Successful calls continue from the task's next absolute turn, so splitting a
run across multiple `execute!` calls preserves schedules, turn-dependent
updates, and counter-based random streams. Set `start_turn` to a non-negative
integer to explicitly reposition the task before that call, for example when
restoring a checkpoint. A failed call does not advance the stored turn.

Returns `rep`.
"""
execute!(task::TrackingTask, beam::Beam; turns::Integer=1, start_turn=nothing) =
    (execute!(task, beam.rep; turns=turns, start_turn=start_turn); beam)

function execute!(task::TrackingTask, rep; turns::Integer=1, start_turn=nothing)
    nturns, first_turn, next_turn =
        _task_execution_window(task.next_turn[], turns, start_turn)
    runtime_entries = _runtime_entries(task, rep)
    runtime_elems = _physics_line(runtime_entries)
    policy = _resolve_execution_policy(task.policy, rep)
    result = try
        _with_execution_policy(policy) do
            _execute_tracking_task!(
                task, rep, runtime_entries, runtime_elems, nturns, first_turn, policy)
        end
    catch
        # A crashed run still flushes the loss accounting recorded so far: the
        # per-particle slots were written during tracking, and the file is the
        # artifact wanted most after a crash -- before this ran only on
        # success, so a blown-up run left no loss file at all (audit part 7,
        # T6). The stored turn is deliberately NOT advanced, matching the
        # docstring above.
        summary = _task_loss_summary(task, rep)
        wrote_file = _write_task_loss_log(task, summary)
        _report_losses(task, rep, summary, wrote_file)
        rethrow()
    end
    task.next_turn[] = next_turn
    summary = _task_loss_summary(task, rep)
    wrote_file = _write_task_loss_log(task, summary)
    _report_losses(task, rep, summary, wrote_file)
    return result
end

"""
Rewrite the loss file after a run, when a path was given.

Rewritten whole rather than appended: the record is cumulative and a particle is
lost at most once, so the file after `n` turns is a superset of the file after
`n-1`. That makes the write idempotent and makes a run split across several
`execute!` calls produce the same file as one long call.
"""
function _write_task_loss_log(task::TrackingTask, summary)
    task.loss_log === nothing && return false
    record = task.loss_record[]
    record === nothing && return false
    record.slots === nothing && return false
    write_loss_record(task.loss_log, record;
                      s=_aperture_s_positions(task.elements), summary=summary)
    return true
end

"""
Report the loss accounting at the end of a run.

A diagnostic nobody fires is not a diagnostic. `loss_summary` reconciles two
independent counts of how many particles are gone, and its whole point is
`unattributed` -- particles that went non-finite with no aperture responsible --
which is a signal the user did not ask for and therefore will not think to
query. So it is emitted automatically.

**Silent when nothing was lost.** A clean run prints nothing, which is what
keeps this usable in a test suite and a validation sweep. When a file was
requested the numbers go there instead, because a run that asked for an artifact
should not also chatter at the console.

`unattributed != 0` warns in either case. It means a particle died somewhere
there is no collimator -- a numerical blowup, an imaginary square root -- and
that should not be reachable only by opening an HDF5 file afterwards.
"""
function _report_losses(task::TrackingTask, rep, summary, wrote_file::Bool)
    summary === nothing && return nothing
    if summary.unattributed != 0
        @warn "particles were lost with no aperture responsible; a coordinate went \
               non-finite where nothing was collimating" unattributed = summary.unattributed dead = summary.dead logged = summary.logged
    end
    # `loss_report` was already honoured upstream, by not computing `summary` at
    # all; reaching here with one means reporting was asked for.
    (wrote_file || summary.dead == 0) && return nothing
    io = stdout
    println(io, "loss summary: ", summary.dead, " of ", summary.particles,
            " particles lost (", summary.live, " live)")
    if !isempty(summary.names)
        for (name, count) in zip(summary.names, summary.by_aperture)
            count == 0 && continue
            println(io, "  ", rpad(name, 24), count)
        end
    end
    summary.unattributed == 0 ||
        println(io, "  ", rpad("(unattributed)", 24), summary.unattributed)
    return nothing
end

"""
The task's loss accounting, or `nothing` when it was switched off.

Costs one `O(N)` non-finite reduction per `execute!` call -- not per turn -- and
runs even with no aperture in the line, because that is exactly the case where a
particle can go non-finite with nothing to blame.

`loss_report = false` skips the reduction itself rather than merely silencing
its output, which is the point of the switch: a caller stepping one turn at a
time pays the `O(N)` per call otherwise. **It therefore switches off the
detection, not just the printing** -- no `unattributed` warning, and no summary
in the loss file. That is a real trade and is why the default is on.
"""
function _task_loss_summary(task::TrackingTask, rep)
    task.loss_report || return nothing
    rep === nothing && return nothing
    return loss_summary(rep, task.loss_record[])
end

function _execute_tracking_task!(task, rep, runtime_entries, runtime_elems,
                                 turns::Int, first_turn::Int64, policy)
    if isempty(task.actions) && isempty(task.observers) && !_has_line_hooks(runtime_entries)
        _execute_fast_tracking_turns!(
            rep, runtime_elems, turns, first_turn, policy, TrackingContext())
        return rep
    end
    # `first_turn`, not just the count: `should_run` is handed the ABSOLUTE turn
    # (`first_turn + offset` below), so a planner filtering against `0:turns-1`
    # disagrees with it on every execute! after the first.
    prepare_observers!(task.observers, runtime_elems; turns=turns, first_turn=first_turn)
    prepare_line_observers!(runtime_entries; turns=turns, first_turn=first_turn)
    try
        base_ctx = TrackingContext()
        for offset in 0:(turns - 1)
            turn = first_turn + offset
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
        # Nested so the line observers are finalized even when a task-level
        # finalizer throws; each helper already finishes its own list before
        # rethrowing its first error (audit part 7, T7).
        try
            finalize_observers!(task.observers)
        finally
            _finalize_line_observers!(runtime_entries)
        end
    end
    return rep
end

function _execute_fast_tracking_turns!(rep, runtime_elems, turns::Int,
                                       first_turn::Int64, policy,
                                       base_ctx::TrackingContext)
    for offset in 0:(turns - 1)
        turn = first_turn + offset
        ctx = with_turn(base_ctx, turn)
        _update_runtime_line!(runtime_elems, ctx)
        track!(rep, runtime_elems, 1, policy, ctx)
    end
    return nothing
end

function _task_execution_window(stored_turn::Int64, turns::Integer, start_turn)
    turns >= 0 || throw(ArgumentError("turns must be non-negative; got $(turns)"))
    nturns = try
        Int(turns)
    catch error
        error isa InexactError || rethrow()
        throw(ArgumentError("turns must fit in Int; got $(turns)"))
    end
    first_turn = if start_turn === nothing
        stored_turn
    elseif start_turn isa Integer
        start_turn >= 0 || throw(ArgumentError(
            "start_turn must be non-negative; got $(start_turn)"))
        try
            Int64(start_turn)
        catch error
            error isa InexactError || rethrow()
            throw(ArgumentError("start_turn must fit in Int64; got $(start_turn)"))
        end
    else
        throw(ArgumentError(
            "start_turn must be nothing or an integer; got $(repr(start_turn))"))
    end
    next_turn = try
        Base.Checked.checked_add(first_turn, Int64(nturns))
    catch error
        error isa OverflowError || rethrow()
        throw(ArgumentError(
            "turn window overflows Int64: start_turn=$(first_turn), turns=$(nturns)"))
    end
    return nturns, first_turn, next_turn
end

_runtime_or_existing(element::AbstractElementSpec) = compile_runtime(element)
_runtime_or_existing(entry::LineEntry) = compile_runtime(entry)
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

function _runtime_entries(task::TrackingTask, rep=nothing)
    # The loss record is sized and placed by the representation, so a task
    # re-run on a different beam needs a different record and therefore a
    # recompiled line. Keying the cache on the record identity is what makes
    # that automatic rather than a footgun.
    record = _ensure_loss_record!(task, rep)
    cached = task.runtime_entries_cache[]
    if cached !== nothing
        entries, knob_dependent, kepoch, sepoch, crecord = cached
        # Knob-dependent lines recompile when the knob epoch has moved, and any
        # line recompiles when a spec parameter was mutated in place
        # (post-construction knob binding), so both kinds of change reach this
        # task at its next execute!.
        ((!knob_dependent || kepoch == knob_epoch()) && sepoch == _spec_epoch() &&
         crecord === record) && return entries
    end
    kepoch = knob_epoch()
    sepoch = _spec_epoch()
    entries = _runtime_line_entries(task.elements)
    entries = _bind_apertures(entries, record)
    task.runtime_entries_cache[] =
        (entries, _has_knob_parameters(task.elements), kepoch, sepoch, record)
    empty!(task.plan_cache)
    return entries
end

"""
Allocate the task's loss record on first use, or return the existing one.

Reallocated when the representation changes shape or backend, because the
per-particle slots are indexed by particle and live on the beam's device.
"""
function _ensure_loss_record!(task::TrackingTask, rep)
    rep === nothing && return task.loss_record[]
    specs = _aperture_specs(task.elements)
    isempty(specs) && return nothing
    existing = task.loss_record[]
    want_slots = task.loss_log !== nothing
    if existing !== nothing
        fits = length(loss_counts(existing)) == length(specs) &&
               _loss_record_matches_rep(existing, rep) &&
               (existing.slots === nothing) == !want_slots &&
               (existing.slots === nothing || size(existing.slots, 2) == length(rep))
        fits && return existing
    end
    names = [String(getparam(spec, :name, "")) for spec in specs]
    for (i, name) in enumerate(names)
        isempty(name) && (names[i] = "aperture_$(i)")
    end
    record = LossRecord(names, length(rep), rep; log=want_slots)
    task.loss_record[] = record
    return record
end

_bind_apertures(entries::Tuple, ::Nothing) = entries

function _bind_apertures(entries::Tuple, record)
    id = Ref(0)
    bound = map(entry -> _bind_aperture_entry(entry, record, id), entries)
    # `counts` was sized by `_aperture_specs` over the user's element structure;
    # the ids were just assigned over the compiled runtime line. If the two
    # walkers ever disagree again on what a container is, fail here on the
    # host, loudly -- the alternative is an unchecked `counts[id]` write past
    # the end of the vector inside the tracking kernel (audit part 7, T3).
    id[] == length(record.counts) || error(
        "loss record sized for $(length(record.counts)) apertures but the " *
        "compiled line contains $(id[]); an element container is being walked " *
        "by _append_runtime_line! but not by _aperture_specs")
    return bound
end

_bind_aperture_entry(entry::PhysicsEntry{<:Aperture}, record, id) =
    PhysicsEntry(_attach_loss_record(entry.element, record, id[] += 1))
_bind_aperture_entry(entry, record, id) = entry

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

function _append_runtime_line!(out, entry::LineEntry, hook_counter)
    spec = getfield(entry, :spec)
    # An in-line observer placed in a line is still an in-line observer; only a
    # physical element goes through the placement's parameter merge.
    spec isa AbstractElementSpec ||
        return _append_runtime_line!(out, spec, hook_counter)
    push!(out, PhysicsEntry(compile_runtime(entry)))
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

# Same contract as finalize_observers!: every in-line observer is finalized
# even when an earlier one throws, and the first error surfaces afterwards
# (audit part 7, T7).
function _finalize_line_observers!(entries::Tuple)
    first_error = nothing
    for entry in entries
        entry isa LineObserverEntry || continue
        try
            finalize_observer!(entry.observer.observer)
        catch e
            first_error === nothing && (first_error = e)
        end
    end
    first_error === nothing || throw(first_error)
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



