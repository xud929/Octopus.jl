# U1 targeted particle-tune neighbour-audit reproducer, 2026-10-30.
# See U1.md for the measured red/green result and scope.
function _prepare_particle_tunes!(task, rep, entries)
    present = _has_particle_tunes(entries)
    state = task.particle_tunes[]
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
