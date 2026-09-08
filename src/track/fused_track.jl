export fusedTrack, fusedTrackLuminous

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

"""
    fusedTrackLuminous(mask, ctx, elems, particle_id, coord...)
        -> ((x, px, y, py, z, pz), (lums...))

The luminosity-carrying twin of [`fusedTrack`](@ref). Threads the coordinate
tuple exactly as `fusedTrack` does, and alongside it a tuple of per-particle
luminosity contributions -- one entry per luminosity-producing element, in line
order, so the artifact's per-element channels keep their attribution.

`fusedTrack` ITSELF IS NOT TOUCHED, deliberately: its six-value return is the
element-callable contract, implemented by `CompositeLine` among others, so
changing its arity would break composition at every nesting site. A line that
asks for no luminosity keeps the identical specialization and pays nothing.

Elements that produce no luminosity contribute an EMPTY tuple, which splices
away at compile time, so the accumulator tuple is exactly as long as the number
of strong beams -- zero for most lines.

Masking happens inside `track_luminous`, at each element's own position; see
that function for why the caller must not do it.
"""
@inline @generated function fusedTrackLuminous(mask, ctx::TrackingContext, elems::Elems,
                                               particle_id,
                                               coord::Vararg{Any,N}) where {Elems<:Tuple,N}
    syms = Expr(:tuple, [gensym() for _ in 1:N]...)
    stmts = Expr[]
    lums = Symbol[]
    push!(stmts, :($syms = coord))

    function emit_calls(elems_symbol, elems_type)
        for k in 1:length(elems_type.parameters)
            T = elems_type.parameters[k]
            if T <: Tuple
                nested = gensym(:nested_)
                push!(stmts, :($nested = getfield($elems_symbol, $k)))
                emit_calls(nested, T)
            else
                res = gensym(:res_)
                push!(stmts, Expr(:(=), res,
                    Expr(:call, :track_luminous, :(getfield($elems_symbol, $k)),
                         :mask, :ctx, :particle_id, syms.args...)))
                push!(stmts, :($syms = getfield($res, 1)))
                l = gensym(:lum_)
                push!(stmts, :($l = getfield($res, 2)))
                push!(lums, l)
            end
        end
        return nothing
    end

    emit_calls(:elems, Elems)
    lum_tuple = Expr(:tuple, [Expr(:..., l) for l in lums]...)
    push!(stmts, Expr(:tuple, syms, lum_tuple))
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
