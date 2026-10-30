export PhaseSpaceResetSpec, PhaseSpaceReset

"""
    PhaseSpaceResetSpec(; name="", tracking_method=NonSymplectic6DMap(), kwargs...)
    PhaseSpaceResetSpec{T}(; kwargs...)

Capture every particle's six coordinates on first passage through a
[`TrackingTask`](@ref), and restore that reference on subsequent passages.
The snapshot stays on the beam's backend: host memory for CPU tracking,
device memory for CUDA, and the local shard for MPI. The absolute turn,
particle IDs and noise streams continue normally. Observe the response after
the physical lattice and before the next reset.

One reset is supported, at the task's first tracking position; preceding
read-only observers are allowed. Nonzero placement transforms, action hooks,
interior/multiple resets and `StrongStrongTask` are refused. Reset tasks
require `loss_report=true`: losses are recorded once per trial before a
restoration revives the original finite ensemble. The initial reference must
be finite. Its storage identity and partition must remain unchanged until
`clear_phase_space_reset!(task)` explicitly arms a new capture.

This is a non-invertible experimental operation, classified only as
[`NonSymplectic6DMap`](@ref). Scalar calls, bare `track!` and optics analysis
through it are refused; the task supplies the capture and loss lifecycle.
The typed form and `numeric_type=T` use the common element precision rule.
An empty `name` resolves to `"reset"` for diagnostic group naming.
"""
abstract type PhaseSpaceResetSpec{T} end

function PhaseSpaceResetSpec(; numeric_type=nothing, kwargs...)
    numeric_type === nothing || return PhaseSpaceResetSpec{numeric_type}(; kwargs...)
    return ElementSpec{:phase_space_reset}(_spec_params(; kwargs...))
end
(::Type{PhaseSpaceResetSpec{T}})(; kwargs...) where {T} =
    ElementSpec{:phase_space_reset}(_typed_spec_params(T; kwargs...))

default_method(::Type{ElementSpec{:phase_space_reset}}) = NonSymplectic6DMap()
_requires_tracking_task(::Type{ElementSpec{:phase_space_reset}}) = true
_element_probe_placement_supported(::Type{ElementSpec{:phase_space_reset}}) = false

"""
    PhaseSpaceReset{M,T}

Compiled marker for a task-managed phase-space capture/restore operation.
It carries the selected method and numeric type only. The owning task keeps
the snapshot and trial accounting, independently of compiled-line and plan
caches; no reference coordinates are stored in an element specification.
"""
struct PhaseSpaceReset{M<:AbstractTrackingMethod,T<:Number} <: AbstractTrackOp
    method::M
end

function PhaseSpaceReset(spec::ElementSpec{:phase_space_reset}, method::NonSymplectic6DMap)
    # Keep the canonical placement schema, while refusing every unsupported
    # request before the generic wraps could reinterpret a capture's frame.
    for key in _PLACEMENT_PARAM_KEYS
        value = _declared_param(spec, key)
        allowed = key === :misalign_convention ? value === :bmad :
                  value isa Number && iszero(value)
        allowed || throw(ArgumentError(
            "PhaseSpaceResetSpec does not support placement parameter $(key)=$(repr(value)); " *
            "use the default placement and rotate the line to choose the reference point"))
    end
    return PhaseSpaceReset{typeof(method),numeric_type(spec)}(method)
end

const _PHASE_SPACE_RESET_TASK_REQUIRED =
    "PhaseSpaceReset requires TrackingTask capture/restore and trial-loss lifecycle; scalar maps, bare track! and optics analysis through a reset are unsupported"

_requires_tracking_task(::PhaseSpaceReset) = true
@inline track_particle(::NonSymplectic6DMap, ::PhaseSpaceReset, x, px, y, py, z, pz) =
    throw(ArgumentError(_PHASE_SPACE_RESET_TASK_REQUIRED))
@inline (::PhaseSpaceReset)(x, px, y, py, z, pz) =
    throw(ArgumentError(_PHASE_SPACE_RESET_TASK_REQUIRED))
@inline (::PhaseSpaceReset)(::TrackingContext, particle_id, x, px, y, py, z, pz) =
    throw(ArgumentError(_PHASE_SPACE_RESET_TASK_REQUIRED))

_cross_backend_rounding(::PhaseSpaceReset) = _rounding_class(bitwise=_COORDINATE_NAMES,
    why="capture and restoration copy all six coordinates without arithmetic on either backend; bitwise for every restore, at any turn count with a fixed reference and storage")

# Called by metadata and effectiveness validators only after the module has
# loaded Tasks.jl. A no-op reset, a recaptured reference or an aliased snapshot
# fails this witness, so task-only metadata receives executable coverage.
function _element_metadata_probe(spec::ElementSpec{:phase_space_reset}, coordinates)
    T = numeric_type(spec)
    original = ntuple(i -> T(coordinates[i]), 6)
    rep = Phase6DRep(ntuple(i -> [original[i]], 6)...)
    task = TrackingTask((spec,); policy=CPUThreadsExecutionPolicy(threads=1))
    execute!(task, rep; turns=1)
    isequal(Tuple(rep[1]), original) || throw(ErrorException(
        "PhaseSpaceReset metadata probe: first capture changed the coordinates"))
    for (i, array) in enumerate(coordinate_arrays(rep))
        array[1] = original[i] + T(i + 1)
    end
    execute!(task, rep; turns=1)
    restored = Tuple(rep[1])
    isequal(restored, original) || throw(ErrorException(
        "PhaseSpaceReset metadata probe: restoration did not recover the independent reference"))
    return collect(restored)
end

const _PHASE_SPACE_RESET_PLACEMENT_PARAMS = merge(_PLACEMENT_PARAMS,
    NamedTuple{_PLACEMENT_PARAM_KEYS}(map(_PLACEMENT_PARAM_KEYS) do key
        _placement_param(key; meaning=key === :misalign_convention ?
            "only the default :bmad is accepted because reset has no geometric placement; other requests are refused" :
            "reset has no geometric placement; this parameter must be zero and a nonzero request is refused")
    end))

@element_spec begin
    kind = :phase_space_reset
    spec_type = ElementSpec{:phase_space_reset}
    friendly_constructor = PhaseSpaceResetSpec
    runtime_type = PhaseSpaceReset
    description = "Task-managed capture and restoration of six-dimensional coordinates for repeated noise trials from a fixed initial ensemble."
    keywords = [:phase_space_reset, :noise_response]
    tracking_methods = [NonSymplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        tracking_method=ParamMeta(default=NonSymplectic6DMap(),
            meaning="non-symplectic experimental reset; only NonSymplectic6DMap is supported"),
        _PHASE_SPACE_RESET_PLACEMENT_PARAMS...,
    )
    example = PhaseSpaceResetSpec()
    construction_help = "PhaseSpaceResetSpec(; name=\"\", tracking_method=NonSymplectic6DMap(), numeric_type=nothing), or PhaseSpaceResetSpec{T}(). Captures once, then restores all six coordinates on their existing CPU/CUDA backend while noise advances by absolute turn. Place exactly one at the first tracking position of a TrackingTask, with loss_report=true; read-only entry observers are allowed. Placement inputs (" * join(string.(_PLACEMENT_PARAM_KEYS), ", ") * ") must stay at their defaults: nonzero transforms and non-default misalign_convention are refused, as are action hooks, interior/multiple resets, bare track!, scalar maps, optics analysis and StrongStrongTask. Snapshot ownership and trial losses belong to the task. clear_phase_space_reset!(task) explicitly rearms capture without rewinding noise; an empty name resolves to the diagnostic name reset. The typed constructor and numeric_type obey the common precision rule."
end
