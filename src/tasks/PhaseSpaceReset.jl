export clear_phase_space_reset!, phase_space_reset_summary

# The spec and runtime sentinel live in elements/phase_space_reset.jl. This
# state belongs to a task, never to a spec, a CUDA argument or a cached plan.
mutable struct _PhaseSpaceResetState
    name::String
    snapshot::Any
    owners::NTuple{6,WeakRef}
    signature::Any
    reference_epoch::Int64
    pending_epoch::Int64
    capture_turn::Int64
    ledger::ResetTrialLedger
    record::Base.RefValue{Any}
    artifact::Union{Nothing,RunArtifact}
    running::Bool
    admission::Int
end

_empty_reset_owners() = ntuple(_ -> WeakRef(nothing), 6)

function _PhaseSpaceResetState(name, task)
    return _PhaseSpaceResetState(name, nothing, _empty_reset_owners(), nothing,
        0, 0, -1, ResetTrialLedger(), task.loss_record, task.artifact, false, 0)
end

struct PhaseSpaceResetSegment
    state::_PhaseSpaceResetState
end

function _has_phase_space_reset(entries::Tuple)
    # Unroll the heterogeneous entry tuple, as the other task-level walkers
    # do. Iterating it through `any` boxed the whole 40-cavity tuple at each
    # step (189824 bytes per check), even for a line with no reset.
    found = Ref(false)
    _foreach_unrolled(entries) do entry
        found[] || (found[] = entry isa PhysicsEntry &&
                              _requires_tracking_task(entry.element))
        nothing
    end
    return found[]
end

function _reset_name(task)
    events = Tuple{Float64,Float64,Any}[]
    _collect_spec_s!(events, task.elements, Ref(0.0), Val(:phase_space_reset))
    isempty(events) && return "reset"
    name = String(getparam(last(first(events)), :name, ""))
    return isempty(name) ? "reset" : name
end

function _reset_storage_signature(rep)
    backend = _infer_backend(rep)
    device = backend === CUDABackend ? CUDA.deviceid(CUDA.device(rep.x)) : -1
    offset, global_n = _mp_current_shard(rep)
    return (n=length(rep), coordinate_type=eltype(rep.x), backend=backend,
            device=device, offset=offset, global_n=global_n, ranks=_mp_nranks(),
            lengths=map(length, coordinate_arrays(rep)),
            axes=map(axes, coordinate_arrays(rep)))
end

function _prepare_phase_space_reset!(task, rep, entries; turns=1)
    _has_phase_space_reset(entries) || return nothing
    physics = _physics_line(entries)
    length(physics) > 0 && first(physics) isa PhaseSpaceReset || throw(ArgumentError(
        "PhaseSpaceReset must be the first tracking element; rotate the line to choose its reference point"))
    count(_requires_tracking_task, physics) == 1 || throw(ArgumentError(
        "a TrackingTask supports exactly one PhaseSpaceReset, with no reset hidden in a composite or wrapper"))
    isempty(task.actions) && !_has_line_actions(entries) || throw(ArgumentError(
        "PhaseSpaceReset does not support action hooks that can replace or reorder the saved ensemble"))
    task.loss_report || throw(ArgumentError(
        "PhaseSpaceReset requires loss_report=true so restoration cannot erase unreported particle failures"))
    name = _reset_name(task)
    signature = _reset_storage_signature(rep)
    state = task.phase_space_reset[]
    if state === nothing
        state = _PhaseSpaceResetState(name, task)
        task.phase_space_reset[] = state
    end
    state.running && throw(ArgumentError("a PhaseSpaceReset task cannot execute concurrently or recursively"))
    mismatch = state.snapshot !== nothing &&
        (state.name != name || state.signature != signature ||
         !all(pair -> pair[1].value === pair[2], zip(state.owners, coordinate_arrays(rep))))
    # A local shape or ownership refusal must be agreed before any other rank
    # can enter the turn loop's collectives. The same rule applies to X0.
    shape_valid = all(==(signature.n), signature.lengths)
    bad = Int[mismatch, !shape_valid,
              state.snapshot === nothing && turns > 0 && shape_valid ?
                  _reset_count_dead!(state.ledger, rep) : 0]
    _mp_allsum!(bad)
    bad[1] == 0 || throw(ArgumentError(
        "PhaseSpaceReset reference belongs to different coordinate storage, device, name or MPI partition; call clear_phase_space_reset!(task) before capturing another ensemble"))
    bad[2] == 0 || throw(ArgumentError(
        "PhaseSpaceReset requires all six coordinate arrays to have the same length"))
    bad[3] == 0 || throw(ArgumentError(
        "PhaseSpaceReset requires finite initial coordinates in all six dimensions"))
    state.name = name
    state.artifact = task.artifact
    return state
end

_bind_phase_space_reset_window!(::Nothing, task, first_turn, turns) = nothing
function _bind_phase_space_reset_window!(state::_PhaseSpaceResetState, task, first_turn, turns)
    state.pending_epoch = state.snapshot === nothing && turns > 0 ?
        _next_reset_reference_epoch(task.artifact, state.name, state.reference_epoch) :
        state.reference_epoch
    _bind_reset_trials!(state.ledger, task.artifact, state.name, Int(first_turn),
                        aperture_names(task.loss_record[]))
    return nothing
end

function _execute_tracking_segment_turn!(rep, segment::PhaseSpaceResetSegment, policy, ctx;
                                        stream=nothing, sink=nothing)
    _synchronize_segment_stream(stream)
    state = segment.state
    operation = if state.snapshot === nothing
        # copy(CuArray) allocates on the device; no host staging or RNG is used.
        state.snapshot = Phase6DRep(map(copy, coordinate_arrays(rep))...)
        state.owners = map(WeakRef, coordinate_arrays(rep))
        state.signature = _reset_storage_signature(rep)
        state.reference_epoch = state.pending_epoch
        state.capture_turn = ctx.turn
        :capture
    else
        for (dest, saved) in zip(coordinate_arrays(rep), coordinate_arrays(state.snapshot))
            copyto!(dest, saved)
        end
        :restore
    end
    _begin_reset_trial!(state.ledger, state.record[], ctx,
                       state.reference_epoch, state.capture_turn)
    _record_execution!(:phase_space_reset, backend_type(policy), (
        name=state.name, operation=operation, turn=ctx.turn,
        reference_epoch=state.reference_epoch, capture_turn=state.capture_turn,
        local_particles=length(rep), global_particles=state.signature.global_n,
        index_offset=state.signature.offset, device=state.signature.device,
    ))
    return nothing
end

function _finish_failed_reset_trial!(task, rep)
    state = task.phase_space_reset[]
    state === nothing && return nothing
    # Outside the policy scope: no rank may enter a collective on an exception
    # path. The stored signature retains the original global particle offset.
    offset = state.signature === nothing ? 0 : state.signature.offset
    _finish_reset_trial!(state.ledger, rep, task.loss_record[], task.artifact;
                         completed=false, folded=false, shard_offset=offset)
    return nothing
end

"""
    clear_phase_space_reset!(task::TrackingTask)

Discard this task's saved phase-space reference and the most recent window's
trial summary. The next passage through [`PhaseSpaceResetSpec`](@ref) captures
the then-current finite beam. The absolute turn and RNG configuration are
unchanged; existing artifact rows are retained under their reference epochs.
A later capture receives a new epoch. Refused while this task is executing.
"""
function clear_phase_space_reset!(task::TrackingTask)
    state = task.phase_space_reset[]
    state === nothing && return task
    state.running && throw(ArgumentError(
        "cannot clear the PhaseSpaceReset reference while its task is executing"))
    state.snapshot = nothing
    state.owners = _empty_reset_owners()
    state.signature = nothing
    state.capture_turn = -1
    state.ledger = ResetTrialLedger()
    # The next trial starts clean. Dropping the record also invalidates the
    # runtime cache, so every aperture is rebound to the new scratch record.
    task.loss_record[] = nothing
    task.loss_owner[] = WeakRef(nothing)
    return task
end

"""
    phase_space_reset_summary(task::TrackingTask)

Return a copy of the bounded accounting for the most recent admitted execution
window of a task containing [`PhaseSpaceResetSpec`](@ref), or `nothing` before
its first admission. Totals count completed trials only: `completed_trials`,
`attempted_particle_trials`, `survivor_particle_trials`, `aperture_loss_events`
and `unattributed_loss_events`, with `by_aperture` and `aperture_names`.
`last_trial` identifies its absolute turn, reference epoch, capture turn and
counts; `completed=false` labels a partial trial and `folded=false` labels a
local failure flush, without MPI reduction. Earlier completed trials remain
in the totals. A new admitted window clears these totals; it preserves X0.
Per-trial history is available in an attached artifact as
`read(TaskOutput(path), :reset_trials; name="reset")`; detailed aperture events
are under `:reset_losses`. Use `RunArtifact(path; append=true)` to retain prior
execution windows; replay replaces rows from its starting turn onward.
Coordinate moments describe surviving particles.
"""
function phase_space_reset_summary(task::TrackingTask)
    state = task.phase_space_reset[]
    state === nothing && return nothing
    ledger = state.ledger
    ledger.admitted || return nothing
    return (completed_trials=ledger.completed_trials,
            attempted_particle_trials=ledger.attempted_particle_trials,
            survivor_particle_trials=ledger.survivor_particle_trials,
            aperture_loss_events=ledger.aperture_loss_events,
            unattributed_loss_events=ledger.unattributed_loss_events,
            by_aperture=copy(ledger.by_aperture),
            aperture_names=copy(ledger.aperture_names),
            last_trial=deepcopy(ledger.last_trial))
end
