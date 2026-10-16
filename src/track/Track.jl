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

The coordinate element type a runtime element requires of the beam it tracks,
or `nothing` (the generic answer) for an element that promotes with the beam.

The standing behaviour of a plain element is promotion: a `Float64` element
tracking a `Float32` beam computes in `Float64` and the store narrows the
result, on the CPU for every registered kind and on CUDA for the kinds whose
kernels return one tuple type (measured over all 31 kinds on 2026-10-16, fix D
of the crab-cavity noise neighbour audit: 31 of 31 run on the CPU, 19 on
CUDA; the thick-magnet family, both strong beams, the accelerating cavity,
the RF cavity and the radiation element fail at device compile with an
`InvalidIRError`, because a kernel branch on a runtime flag -- `_has_survey`,
`iszero(strength)`, `is_excitation` -- returns a tuple of the beam's type on
one side and of the element's on the other).

A kind that declares its own `T` here is refused a mismatched beam BY NAME
when a task compiles its line (`_check_beam_eltype`, `src/tasks/Tasks.jl`,
and the strong-strong twin), in either direction, on both backends, with the
remedy from `_beam_eltype_remedy`. The owner's policy (2026-10-16, fix D) puts
the two modulated cavities and the radiation element behind it: `ThinRFCavity`
and `LumpedRad` because their device kernels do not compile and their CPU
kernels narrow silently, `ThinCrabCavity` so that the two modulated kinds
agree on what a `Float32` line is (its own kernel promotes on both backends).
Every other kind keeps the promoting behaviour; the suite derives the
declaring set from this function's method table and pins the CPU behaviour of
the rest.
"""
_required_beam_eltype(op) = nothing

"""
    _beam_eltype_remedy(op, B) -> String

The remedy `_check_beam_eltype` names for a beam of element type `B` refused
by `op`; a declaring kind owns a method naming its typed constructor where
it has one. The generic text names the two moves every mismatch has.
"""
_beam_eltype_remedy(op, ::Type{B}) where {B} =
    "build the element in the beam's type, $(B), or the beam in the element's " *
    "($(_required_beam_eltype(op))), Beam(n, policy, $(_required_beam_eltype(op)))"

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
