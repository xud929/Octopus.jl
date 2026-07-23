export AbstractTrackOp, TrackingContext, with_turn, track_particle

"""
    TrackingContext(; turn=0, seed=global_rng_seed(),
                    rng_method=global_rng_method_code())

Immutable execution context passed through tracking workflows and optionally
into per-particle fused tracking. The context is intentionally small and
`isbits` so it can be passed to CUDA kernels. `turn` identifies the current
turn, while `seed` and `rng_method` snapshot the current Octopus global RNG
state for stochastic tracking.
"""
struct TrackingContext
	turn::Int64
	seed::UInt64
	rng_method::UInt8
end

TrackingContext(; turn::Integer=0,
	            seed::Integer=global_rng_seed(),
	            rng_method=global_rng_method_code()) =
	TrackingContext(Int64(turn), UInt64(seed), rng_method_code(rng_method))

"""
    with_turn(ctx, turn)

Return a copy of `ctx` with a new turn value. Use this helper instead of
manually reconstructing `TrackingContext` so future scalar context fields only
need to be handled in one place.
"""
@inline with_turn(ctx::TrackingContext, turn::Integer) =
	TrackingContext(Int64(turn), ctx.seed, ctx.rng_method)

"""
    AbstractTrackOp

Runtime tracking object interface. These objects contain only the data needed by
tracking kernels and are produced from structured element specs by
`compile_runtime`.
"""
abstract type AbstractTrackOp end

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

include("fused_track.jl")
