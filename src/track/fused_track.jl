export fusedTrack

"""
    fusedTrack(elems, coord...)
    fusedTrack(ctx, elems, particle_id, coord...)

Track one phase-space coordinate through a callable runtime element or a nested
tuple of callable runtime elements.

For tuple input, `fusedTrack` recursively expands the tuple at compile time into
a straight-line sequence of calls:

```julia
coord = elem1(coord...)
coord = elem2(coord...)
...
```

This keeps the hot tracking path independent of element specs, tracking-method
metadata, and method-selection logic. Runtime elements are expected to be
compact callable objects produced by `compile_runtime`.
"""
@inline fusedTrack(elem, coord::Vararg{Any,N}) where {N} = elem(coord...)

@inline fusedTrack(ctx::TrackingContext, elem, particle_id, coord::Vararg{Any,N}) where {N} =
    elem(ctx, particle_id, coord...)

@inline @generated function fusedTrack(elems::Elems, coord::Vararg{Any,N}) where {Elems<:Tuple,N}
    syms = Expr(:tuple, [gensym() for _ in 1:N]...)
    stmts = Expr[]
    push!(stmts, :($syms = coord))

    function emit_calls(elems_symbol, elems_type)
        for k in 1:length(elems_type.parameters)
            T = elems_type.parameters[k]
            if T <: Tuple
                nested = gensym(:nested_)
                push!(stmts, :($nested = getfield($elems_symbol, $k)))
                emit_calls(nested, T)
            else
                call = Expr(:call, :(getfield($elems_symbol, $k)), syms.args...)
                push!(stmts, Expr(:(=), syms, call))
            end
        end
        return nothing
    end

    emit_calls(:elems, Elems)
    push!(stmts, syms)
    return Expr(:block, stmts...)
end

@inline @generated function fusedTrack(ctx::TrackingContext, elems::Elems, particle_id,
                                       coord::Vararg{Any,N}) where {Elems<:Tuple,N}
    syms = Expr(:tuple, [gensym() for _ in 1:N]...)
    stmts = Expr[]
    push!(stmts, :($syms = coord))

    function emit_calls(elems_symbol, elems_type)
        for k in 1:length(elems_type.parameters)
            T = elems_type.parameters[k]
            if T <: Tuple
                nested = gensym(:nested_)
                push!(stmts, :($nested = getfield($elems_symbol, $k)))
                emit_calls(nested, T)
            else
                call = Expr(:call, :(getfield($elems_symbol, $k)), :ctx, :particle_id, syms.args...)
                push!(stmts, Expr(:(=), syms, call))
            end
        end
        return nothing
    end

    emit_calls(:elems, Elems)
    push!(stmts, syms)
    return Expr(:block, stmts...)
end
