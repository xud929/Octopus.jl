export AbstractTrackOp, TrackingContext, with_turn, with_index_offset, track_particle

"""
    TrackingContext(; turn=0, seed=global_rng_seed(),
                    rng_method=global_rng_method_code(), index_offset=0)

Immutable execution context passed through tracking workflows and optionally
into per-particle fused tracking. The context is intentionally small and
`isbits` so it can be passed to CUDA kernels. `turn` identifies the current
turn, while `seed` and `rng_method` snapshot the current Octopus global RNG
state for stochastic tracking.

`index_offset` is what makes a run divided across MPI ranks draw the same
random numbers as an undivided one. The Octopus counter RNG keys each particle's
stream on its index, so a rank holding global particles `k+1 … k+m` must key
them on `k+i`, not on its own `1 … m`; the offset is that `k`. It is `0` in
every single-process run, which is every run that does not go through a
`MultiProcessExecutionPolicy`.
"""
struct TrackingContext
	turn::Int64
	seed::UInt64
	rng_method::UInt8
	index_offset::Int64
end

TrackingContext(; turn::Integer=0,
	            seed::Integer=global_rng_seed(),
	            rng_method=global_rng_method_code(),
	            index_offset::Integer=0) =
	TrackingContext(Int64(turn), UInt64(seed), rng_method_code(rng_method),
	                Int64(index_offset))

"""
    with_turn(ctx, turn)

Return a copy of `ctx` with a new turn value. Use this helper instead of
manually reconstructing `TrackingContext` so future scalar context fields only
need to be handled in one place.
"""
@inline with_turn(ctx::TrackingContext, turn::Integer) =
	TrackingContext(Int64(turn), ctx.seed, ctx.rng_method, ctx.index_offset)

"""
    with_index_offset(ctx, offset)

Return a copy of `ctx` whose per-particle RNG streams are keyed from `offset`.
Set once per run from the multi-process shard; see `TrackingContext`.
"""
@inline with_index_offset(ctx::TrackingContext, offset::Integer) =
	TrackingContext(ctx.turn, ctx.seed, ctx.rng_method, Int64(offset))

"""
    AbstractTrackOp

Runtime tracking object interface. These objects contain only the data needed by
tracking kernels and are produced from structured element specs by
`compile_runtime`.
"""
abstract type AbstractTrackOp end

"""
    _required_beam_eltype(op) -> Union{Nothing,Type}

The coordinate element type a runtime element requires of the beam it tracks:
its numeric type parameter, the `T<:Number` every runtime struct with numeric
parameters carries (`LatticeMagnet{M,T,...}`, `ThinMultipole{M,T,N}`,
`Aperture{F,M,R,T}`, ...), derived from `typeof(op)` by
`_numeric_type_parameter`; `nothing` for an element with no numeric parameter
(`Marker`). The wrappers and `CompositeLine` answer with the type of what they
hold (their methods sit beside their structs), which is also the type the
placement wraps are built in.

ONE precision rule for every kind (owner decision 2026-10-16, fix H of the
crab-cavity noise neighbour audit): a beam whose element type differs from an
element's is refused BY NAME when a task compiles its line (`_check_beam_eltype`,
`src/tasks/Tasks.jl`, and the strong-strong twin), in either direction, on both
backends, with the remedy from `_beam_eltype_remedy`; a `Float32` beam needs
`Float32` elements everywhere, built with each kind's `Spec{Float32}` form.
Before it (measured 2026-10-16 over all 31 kinds, fix D) a `Float64` element on
a `Float32` beam promoted and narrowed every coordinate on store on the CPU,
and on CUDA 12 kinds failed at device compile with an `InvalidIRError` (a
kernel branch on a runtime flag -- `_has_survey`, `iszero(strength)`,
`is_excitation` -- returning the beam's tuple type on one side and the
element's on the other) while 19 narrowed silently; the by-name refusal
covered the two modulated cavities and the radiation element only.

The suite derives the set of kinds answering a type from the registry (every
kind but `:marker` and `:line`) and pins it both ways; a runtime struct with two
distinct numeric type parameters is refused here so the derivation never
guesses.
"""
_required_beam_eltype(op::AbstractTrackOp) = _numeric_type_parameter(typeof(op))
_required_beam_eltype(op) = nothing

"""
    _numeric_type_parameter(T::Type) -> Union{Nothing,Type}

The one type parameter of the concrete type `T` that is a `Number` type, or
`nothing`; two distinct ones are refused rather than guessed between.
"""
function _numeric_type_parameter(::Type{T}) where {T}
    found = nothing
    for p in T.parameters
        (p isa Type && p <: Number) || continue
        (found === nothing || p === found) || throw(ArgumentError(
            "$(nameof(T)) carries two numeric type parameters, $(found) and $(p), so " *
            "the beam element type it requires cannot be derived; the kind must " *
            "declare _required_beam_eltype itself"))
        found = p
    end
    return found
end

"""
    _beam_eltype_remedy(op, B) -> String

The remedy `_check_beam_eltype` names for a beam of element type `B` refused by
`op`: the typed forms of the kinds the registry maps to `op`'s runtime type,
DERIVED from `ELEMENT_META_BY_KIND` (`_typed_form_names`) and spelled in the
keyword form every kind has (`QuadrupoleSpec{Float32}(; ...)`), or the beam in
the element's type. A kind whose typed form takes a positional argument the
keyword spelling would hide owns its own method (the crab cavity's `{N,T}`).
"""
function _beam_eltype_remedy(op, ::Type{B}) where {B}
    T = _required_beam_eltype(op)
    forms = _typed_form_names(op)
    element = isempty(forms) ? "the kind's Spec{$(B)}(; ...) form" :
                               join(("$(f){$(B)}(; ...)" for f in forms), " or ")
    return "build the element in the beam's type, $(element), or the beam in $(T) " *
           "(Beam(n, policy, $(T)))"
end

"""
    _typed_form_names(op) -> Vector{String}

The friendly constructor names of every registered kind whose runtime type is
`op`'s (the type's wrapper, `_compiled_matches_runtime`'s rule), sorted: a
`LatticeMagnet` is six kinds' runtime, a `ThinMultipole` seven's.
"""
function _typed_form_names(op)
    W = typeof(op).name.wrapper
    names = String[]
    for meta in values(ELEMENT_META_BY_KIND)
        meta.friendly_constructor === nothing && continue
        any(rt -> rt isa Type && Base.unwrap_unionall(rt).name.wrapper === W,
            values(meta.runtime_types)) || continue
        push!(names, string(nameof(meta.friendly_constructor)))
    end
    return sort!(unique!(names))
end

"""
    track_particle(tracking_method, op, x, px, y, py, z, pz)

Per-particle tracking primitive. Implementations dispatch on the tracking
method type, such as `Symplectic6DMap` or `NonSymplectic6DMap`, and a runtime element object. The
method receives one particle as `(x, px, y, py, z, pz)` and returns the updated
six-tuple.
"""
@inline function track_particle(::Type{M}, op::AbstractTrackOp, x0, px0, y0, py0, z0, pz0) where {M<:AbstractTrackingMethod}
	return track_particle(M(), op, x0, px0, y0, py0, z0, pz0)
end

@inline function track_particle(method::M, op::AbstractTrackOp, x0, px0, y0, py0, z0, pz0) where {M<:AbstractTrackingMethod}
	throw(MethodError(track_particle, (method, op, x0, px0, y0, py0, z0, pz0)))
end

@inline function (op::AbstractTrackOp)(ctx::TrackingContext, particle_id,
	                                   x0, px0, y0, py0, z0, pz0)
	return op(x0, px0, y0, py0, z0, pz0)
end

"""
    track_luminous(op, mask, ctx, particle_id, x, px, y, py, z, pz)
        -> ((x, px, y, py, z, pz), (lums...))

Track one particle through `op` AND hand back whatever luminosity it produced,
as a tuple with one entry per luminosity-producing element inside `op` -- empty
for the overwhelming majority of elements, which produce none.

This exists because the fused kernel throws luminosity away. The strong-beam
kernels already compute it (`_thin_strong_beam_track` returns seven values; the
`GaussianStrongBeam` form accumulates over every slice) and then drop it on the
floor, which is why a strong beam has to be pulled OUT of the fused traversal
into its own segment before its luminosity can be recorded at all. The wrappers
drop it for the same reason: each forwards to a six-value `track_particle`.

MASKING HAPPENS HERE, not in the caller, and that is the whole point of the
shape. `_add_luminosity` judges liveness from the coordinates it is handed, and
the rule (`src/track/strong_beam_track.jl`) is to judge the OUTPUT of the kick.
In a fused pass the caller only ever sees end-of-line coordinates, so a caller
that applied the mask would exclude a particle that was alive at the strong beam
and lost at a downstream aperture -- a plausible, slightly wrong luminosity, with
every coordinate digest still bit-identical. Judged here, at the element's own
position, the semantics are exactly the isolated path's.

The default produces nothing and costs nothing: an empty tuple splices away at
compile time.
"""
@inline track_luminous(op, mask, ctx::TrackingContext, particle_id,
                       x, px, y, py, z, pz) =
	(op(ctx, particle_id, x, px, y, py, z, pz), ())

include("fused_track.jl")
