export clear_particle_tunes!, particle_tune_tables

# Preparation belongs to the task. A compiled runtime only supplies the
# transforms/source description, or device-compatible references to labels.
mutable struct _ParticleTuneBinding
    placement::Int
    template::Any
    key::Any
    op::Any
    tunes::Any
    rotations::Any
    owners::NTuple{6,Any}
    signature::Any
    epoch::Int64
    initialization_turn::Int64
    seed::UInt64
    rng_method::Any
end

function _ParticleTuneBinding(placement, template, epoch)
    _ParticleTuneBinding(placement, template, _particle_tune_binding_key(template),
        nothing, nothing, nothing, _empty_reset_owners(), nothing,
        epoch, -1, UInt64(0), nothing)
end

mutable struct _ParticleTuneState
    bindings::Dict{Int,_ParticleTuneBinding}
    epoch::Int64
    running::Bool
    admission::Int
end
_ParticleTuneState() = _ParticleTuneState(Dict{Int,_ParticleTuneBinding}(), 0, false, 0)

struct ParticleTuneSegment
    binding::_ParticleTuneBinding
end

_contains_particle_tunes(::Any) = false
_contains_particle_tunes(::ParticleLinear6D) = true
_contains_particle_tunes(w::Union{MisalignedElement,RefTilted,TurnModulated}) =
    _contains_particle_tunes(w.inner)
_contains_particle_tunes(c::CompositeLine) = any(_contains_particle_tunes, c.ops)

function _has_particle_tunes(entries::Tuple)
    found = Ref(false)
    _foreach_unrolled(entries) do entry
        found[] || (found[] = entry isa PhysicsEntry &&
                              _contains_particle_tunes(entry.element))
        nothing
    end
    return found[]
end

function _particle_tune_collective_error(err, message)
    verdict = Int[err !== nothing]
    _mp_allsum!(verdict)
    verdict[1] == 0 && return nothing
    detail = err === nothing ? "another MPI rank refused preparation" : sprint(showerror, err)
    throw(ArgumentError(message * ": " * detail))
end

function _prepare_particle_tunes!(task, rep, entries)
    present = _has_particle_tunes(entries)
    state = task.particle_tunes[]
    if _mp_nranks() > 1
        # All ranks must decide together whether to enter preparation. A local
        # fast return here otherwise strands a rank with an active source in
        # its first collective when a peer's line has ordinary Linear6D.
        for active in (present, state !== nothing)
            lo, hi = _mp_allminmax(Int(active), Int(active))
            lo == hi || throw(ArgumentError(
                "particle-tune presence or task state differs across MPI ranks"))
        end
    end
    !present && state === nothing && return nothing
    if state === nothing
        state = _ParticleTuneState()
        task.particle_tunes[] = state
    end
    candidates = Dict{Int,Any}()
    signature = nothing
    err = try
        state.running && throw(ArgumentError("particle-tune task is already executing"))
        !present || (isempty(task.actions) && !_has_line_actions(entries)) || throw(ArgumentError(
            "particle tunes require stable particle identities and do not support action hooks"))
        signature = _reset_storage_signature(rep)
        all(==(signature.n), signature.lengths) || throw(ArgumentError(
            "particle tunes require all six coordinate arrays to have the same length"))
        all(==((Base.OneTo(signature.n),)), signature.axes) || throw(ArgumentError(
            "particle tunes require one-based contiguous particle slot indices"))
        for (i, entry) in enumerate(entries)
            entry isa PhysicsEntry || continue
            elem = entry.element
            _contains_particle_tunes(elem) || continue
            elem isa ParticleLinear6D || throw(ArgumentError(
                "particle tunes inside a composite or placement wrapper require an unsupported body-entrance initialization boundary; use a flat untransformed placement"))
            elem.source === nothing && throw(ArgumentError(
                "a bound ParticleLinear6D cannot be moved to another task; pass its Linear6DSpec or copied tune arrays"))
            binding = get(state.bindings, i, nothing)
            if binding !== nothing && binding.op !== nothing
                binding.signature == signature &&
                    all(p -> p[1].value === p[2], zip(binding.owners, coordinate_arrays(rep))) ||
                    throw(ArgumentError("particle-tune binding belongs to different coordinate storage, device or MPI partition; call clear_particle_tunes!(task) first"))
                isequal(binding.key, _particle_tune_binding_key(elem)) || throw(ArgumentError(
                    "particle-tune source, omitted-plane nominal tune or rng_id changed; call clear_particle_tunes!(task) first"))
            else
                _validate_particle_tune_shape(elem; global_n=signature.global_n,
                    index_offset=signature.offset, local_n=signature.n)
            end
            candidates[i] = elem
        end
        for (i, binding) in state.bindings
            binding.op === nothing || haskey(candidates, i) || throw(ArgumentError(
                "a bound particle-tune placement was removed or moved; call clear_particle_tunes!(task) first"))
        end
        nothing
    catch failure
        failure
    end
    _particle_tune_collective_error(err, "particle-tune admission failed before tracking")
    # A different bound/unbound placement set would make ranks enter different
    # first-passage collectives. Check it before any turn or user callback.
    layout = sort!(collect(keys(candidates)))
    if _mp_nranks() > 1
        lo, hi = _mp_allminmax(length(layout), length(layout))
        lo == hi || throw(ArgumentError("particle-tune placement counts differ across MPI ranks"))
        for i in layout
            lo, hi = _mp_allminmax(i, i)
            lo == hi || throw(ArgumentError("particle-tune placement positions differ across MPI ranks"))
            bound = haskey(state.bindings, i) && state.bindings[i].op !== nothing
            lo, hi = _mp_allminmax(Int(bound), Int(bound))
            lo == hi || throw(ArgumentError("particle-tune binding states differ across MPI ranks"))
            schema = _particle_tune_collective_schema(candidates[i], state.epoch)
            lo, hi = _mp_allminmax(length(schema), length(schema))
            lo == hi || throw(ArgumentError("particle-tune source schemas differ across MPI ranks"))
            lows, highs = copy(schema), copy(schema)
            _mp_allmin!(lows)
            _mp_allmax!(highs)
            lows == highs || throw(ArgumentError(
                "particle-tune precision, optics, planes, source kinds, nominal tunes, rng_id or epoch differ across MPI ranks"))
        end
    end
    for i in layout
        elem = candidates[i]
        binding = get(state.bindings, i, nothing)
        if binding === nothing
            binding = _ParticleTuneBinding(i, elem, state.epoch)
            state.bindings[i] = binding
        end
        binding.template = elem
        binding.key = _particle_tune_binding_key(elem)
        if binding.op === nothing
            binding.signature = signature
        else
            # Only the shared optics change. Labels and cached rotations are
            # precisely the arrays installed at the first successful passage.
            binding.op = _bind_particle_tunes(elem, binding.tunes, binding.rotations,
                                               signature.offset)
        end
    end
    for i in setdiff(collect(keys(state.bindings)), layout)
        delete!(state.bindings, i)
    end
    return state
end

# Portable, injective encoding of the declared preparation metadata. Julia
# object identity is process-local and cannot be an MPI configuration key.
# Callback captures and arbitrary distribution internals remain user code;
# callers must supply equivalent sources on every rank.
function _particle_tune_collective_schema(op, epoch)
    schema = UInt64[op.rng_id, epoch, length(op.source.groups), sizeof(eltype(op.nominal_tunes))]
    for value in (op.A..., op.inv_A...)
        push!(schema, reinterpret(UInt64, Float64(value)))
    end
    active = _particle_tune_planes(op)
    for (k, plane) in enumerate(_PARTICLE_TUNE_PLANES)
        push!(schema, plane in active ? UInt64(0) : reinterpret(UInt64, Float64(op.nominal_tunes[k])))
    end
    for group in op.source.groups
        push!(schema, length(group.planes))
        append!(schema, map(_tune_plane_index, group.planes))
        name = codeunits(string(group.mode))
        push!(schema, length(name))
        append!(schema, name)
        group.mode === :constant && push!(schema, reinterpret(UInt64, Float64(group.source)))
        group.mode === :array && push!(schema, length(group.source))
    end
    return schema
end

function _initialize_particle_tune_binding!(binding, rep, policy, ctx, stream)
    _synchronize_segment_stream(stream)
    elem = binding.template
    signature = _reset_storage_signature(rep)
    if _mp_nranks() > 1 && _particle_tunes_stochastic(elem.source)
        for key in (ctx.seed, UInt64(ctx.rng_method))
            lo, hi = _mp_allminmax(key, key)
            lo == hi || throw(ArgumentError(
                "particle-tune initialization seed or RNG method differ across MPI ranks; no map applied at this placement"))
        end
    end
    need_coordinates = _particle_tunes_need_coordinates(elem)
    hostcoords = nothing
    local_error = try
        if need_coordinates
            hostcoords = map(Array, coordinate_arrays(rep))
            all(a -> all(isfinite, a), hostcoords) || throw(ArgumentError(
                "coordinate tune functions require finite entrance coordinates in all six dimensions"))
        end
        nothing
    catch err
        err
    end
    _particle_tune_collective_error(local_error,
        "particle-tune entrance validation failed; no map applied at placement $(binding.placement)")
    staged_tunes = nothing
    staged_rotations = nothing
    staged_op = nothing
    local_error = try
        host_tunes, host_rotations = _initialize_particle_tunes(elem, hostcoords, ctx;
            index_offset=signature.offset, global_n=signature.global_n,
            local_n=signature.n, epoch=binding.epoch)
        staged_tunes = map(a -> _on_backend(backend_type(policy), a), host_tunes)
        staged_rotations = map(a -> _on_backend(backend_type(policy), a), host_rotations)
        staged_op = _bind_particle_tunes(elem, staged_tunes, staged_rotations, signature.offset)
        nothing
    catch err
        err
    end
    _particle_tune_collective_error(local_error,
        "particle-tune initialization failed; no map applied at placement $(binding.placement)")
    binding.tunes = staged_tunes
    binding.rotations = staged_rotations
    binding.op = staged_op
    binding.owners = map(_coordinate_storage_owner, coordinate_arrays(rep))
    binding.signature = signature
    binding.initialization_turn = ctx.turn
    binding.seed = ctx.seed
    binding.rng_method = rng_method_symbol(ctx.rng_method)
    _record_execution!(:particle_tune_initialization, backend_type(policy), (
        entry_index=binding.placement,
        planes=_particle_tune_planes(elem),
        source_kinds=map(d -> d.kind, _particle_tune_descriptors(elem)),
        n_local=signature.n, global_n=signature.global_n,
        index_offset=signature.offset, epoch=binding.epoch,
        initialization_turn=ctx.turn, seed=ctx.seed, rng_method=binding.rng_method,
        rng_id=elem.rng_id, device=signature.device,
    ))
    return nothing
end

function _execute_tracking_segment_turn!(rep, segment::ParticleTuneSegment, policy, ctx;
                                        stream=nothing, sink=nothing)
    binding = segment.binding
    binding.op === nothing && _initialize_particle_tune_binding!(binding, rep, policy, ctx, stream)
    _track_admitted!(rep, (binding.op,), 1, policy, ctx; stream=stream)
    return nothing
end

"""
    clear_particle_tunes!(task::TrackingTask)

Discard this task's frozen particle tunes. The next passage through each active
`Linear6DSpec` initializes from its then-current entrance coordinates/sources.
Clearing initialized bindings increments a preparation epoch, so distributions
draw fresh labels without changing the global seed or other noise streams.
The turn, coordinates, and phase-space reset reference are unchanged. Refused
while the task executes. Input arrays remain global arrays on MPI.
"""
function clear_particle_tunes!(task::TrackingTask)
    _begin_tracking_task_mutation!(task,
        "cannot clear particle tunes while their task is executing or changing state")
    try
        return _clear_particle_tunes!(task)
    finally
        _end_tracking_task_mutation!(task)
    end
end

function _clear_particle_tunes!(task::TrackingTask)
    state = task.particle_tunes[]
    state === nothing && return task
    state.running && throw(ArgumentError("cannot clear particle tunes while their task is executing"))
    if any(b -> b.op !== nothing, values(state.bindings))
        state.epoch = Base.checked_add(state.epoch, Int64(1))
    end
    for (i, binding) in state.bindings
        state.bindings[i] = _ParticleTuneBinding(i, binding.template, state.epoch)
    end
    empty!(task.plan_cache)
    return task
end

"""
    particle_tune_tables(task::TrackingTask)

Return placement-ordered records of this task's local particle-tune bindings.
Each record has `bound`, `placement` (compiled line-entry index), independent
host copies `tunes=(nux=..., nuy=..., nuz=...)`, `planes`, `sources`,
`global_range`, `global_particles`, `local_particles`, `index_offset`, and
initialization provenance (`epoch`, `initialization_turn`, `seed`,
`rng_method`, `rng_id`). Unbound entries have `tunes=nothing`; before the
first admission the result is empty. This explicit accessor copies CUDA data
to the host. It never exposes the arrays used by tracking.
"""
function particle_tune_tables(task::TrackingTask)
    state = task.particle_tunes[]
    state === nothing && return ()
    return Tuple(map(sort!(collect(keys(state.bindings)))) do i
        b = state.bindings[i]
        s = b.signature
        bound = b.op !== nothing
        (placement=i, bound=bound,
         tunes=bound ? NamedTuple{(:nux,:nuy,:nuz)}(map(a -> copy(Array(a)), b.tunes)) : nothing,
         planes=_particle_tune_planes(b.template), sources=_particle_tune_descriptors(b.template),
         global_range=s === nothing ? nothing : ((s.offset+1):(s.offset+s.n)),
         global_particles=s === nothing ? nothing : s.global_n,
         local_particles=s === nothing ? nothing : s.n,
         index_offset=s === nothing ? nothing : s.offset,
         epoch=b.epoch, initialization_turn=bound ? b.initialization_turn : nothing,
         seed=bound ? b.seed : nothing, rng_method=bound ? b.rng_method : nothing,
         rng_id=b.template.rng_id)
    end)
end
