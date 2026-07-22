"""
    collide!(solver, beam1, beam2, backend)

Advance two beams through one strong-strong collision and return the luminosity
estimate for that collision.
"""
function collide!(solver::GaussianPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend})
    slices1 = longitudinal_slices(beam1.rep, solver.slicing1)
    slices2 = longitudinal_slices(beam2.rep, solver.slicing2)
    kbb1 = _strong_strong_kbb1(solver, beam1, beam2)
    kbb2 = _strong_strong_kbb2(solver, beam1, beam2)
    klum1, klum2 = _strong_strong_luminosity_scales(solver, beam1, beam2)
    T = eltype(beam1.rep.x)
    luminosity = zero(T)
    for (_, i, j) in _slice_collision_order(slices1, slices2)
        luminosity += _cpu_gaussian_slice_pair!(
            solver, beam1.rep, beam2.rep, slices1, slices2, i, j,
            kbb1, kbb2, klum1, klum2,
        )
    end
    return luminosity
end

function _cpu_gaussian_slice_pair!(solver::GaussianPoissonSolver{T,D,COUPLED,LONGITUDINAL},
                                   rep1, rep2, slices1, slices2, i, j,
                                   kbb1, kbb2, klum1, klum2) where {T,D,COUPLED,LONGITUDINAL}
    moments1 = _slice_transverse_moments(
        rep1, slices1.indices[i], solver.ignore_centroid1, solver.min_sigma,
        Val(COUPLED))
    moments2 = _slice_transverse_moments(
        rep2, slices2.indices[j], solver.ignore_centroid2, solver.min_sigma,
        Val(COUPLED))
    sample_beam1 = solver.gaussian_when_luminosity == 1
    lum2 = _slice_slice_gaussian_kick!(
        rep1, slices1.indices[i], moments2, slices2.center[j],
        slices2.weight[j] * kbb1, slices2.weight[j] * klum1,
        solver.min_sigma, solver.virtual_drift, Val(LONGITUDINAL),
        Val(!sample_beam1),
    )
    lum1 = _slice_slice_gaussian_kick!(
        rep2, slices2.indices[j], moments1, slices1.center[i],
        slices1.weight[i] * kbb2, slices1.weight[i] * klum2,
        solver.min_sigma, solver.virtual_drift, Val(LONGITUDINAL),
        Val(sample_beam1),
    )
    return sample_beam1 ? lum1 : lum2
end

function _slice_slice_gaussian_kick!(rep::Phase6DRep, idx::Vector{Int}, moments2,
                                     center2, kbb_slice, klum_slice, min_sigma,
                                     virtual_drift::AbstractVirtualDrift,
                                     longitudinal_kick::Val,
                                     compute_luminosity::Val{COMPUTE_LUMINOSITY}) where {COMPUTE_LUMINOSITY}
    isempty(idx) && return zero(eltype(rep.x))
    T = eltype(rep.x)
    n = length(idx)
    nchunks = _cpu_worker_count()
    if nchunks == 1 || n < _STRONG_STRONG_PARALLEL_KICK_MIN
        lum = zero(T)
        for i in idx
            @inbounds lum += _apply_slice_kick_one!(
                rep, i, moments2, center2, kbb_slice, min_sigma,
                virtual_drift, longitudinal_kick, compute_luminosity)
        end
        return lum / TWOPI * klum_slice
    end
    local_lum = zeros(T, nchunks)
    _run_logical_workers(nchunks) do chunk, _
        first_i, last_i = _chunk_bounds(n, nchunks, chunk)
        lum = zero(T)
        for pos in first_i:last_i
            @inbounds lum += _apply_slice_kick_one!(
                rep, idx[pos], moments2, center2, kbb_slice, min_sigma,
                virtual_drift, longitudinal_kick, compute_luminosity)
        end
        local_lum[chunk] = lum
    end
    return sum(local_lum) / TWOPI * klum_slice
end

@inline _soft_gaussian_covariance(moments) = moments.moments

@inline _soft_gaussian_covariance(moments::NamedTuple{N}) where {N} =
    _soft_gaussian_covariance(moments, Val(:moments in N))

@inline _soft_gaussian_covariance(moments::NamedTuple, ::Val{true}) = moments.moments

@inline function _soft_gaussian_covariance(moments::NamedTuple, ::Val{false})
    T = typeof(moments.sx)
    return StrongTransverseMoments{T,false}(
        moments.sx * moments.sx, zero(T), moments.sy * moments.sy,
        moments.covxpx, zero(T), zero(T), moments.covypy,
        moments.spx * moments.spx, zero(T), moments.spy * moments.spy,
    )
end

@inline _soft_gaussian_drift(drift, ::Val{true}) = drift
@inline _soft_gaussian_drift(::AbstractVirtualDrift, ::Val{false}) =
    UnsafeVirtualDrift(_ParaxialFrozenLongitudinalDrift())

@inline function _apply_slice_kick_one!(rep::Phase6DRep, i, moments2, center2,
                                        kbb_slice, min_sigma,
                                        virtual_drift::AbstractVirtualDrift,
                                        longitudinal_kick::Val{LONGITUDINAL},
                                        ::Val{COMPUTE_LUMINOSITY}) where {LONGITUDINAL,COMPUTE_LUMINOSITY}
    @inbounds begin
        x = rep.x[i]; px = rep.px[i]
        y = rep.y[i]; py = rep.py[i]
        z = rep.z[i]; pz = rep.pz[i]
    end
    drift = _soft_gaussian_drift(virtual_drift, longitudinal_kick)
    x, px, y, py, z, pz, S = _forward_virtual_drift(
        drift, x, px, y, py, z, pz, center2)
    xx = x - moments2.mx + moments2.mpx * S
    yy = y - moments2.my + moments2.mpy * S
    px0, py0, pz0 = px, py, pz
    x, px, y, py, z, pz, density = _cp_covariance_kick(
        _soft_gaussian_covariance(moments2), kbb_slice, S, xx, yy,
        x, px, y, py, z, pz)
    if LONGITUDINAL
        pz += 0.5 * ((px - px0) * moments2.mpx +
                    (py - py0) * moments2.mpy)
    else
        pz = pz0
    end
    x, px, y, py, z, pz = _reverse_virtual_drift(
        drift, x, px, y, py, z, pz, center2)
    @inbounds begin
        rep.x[i] = x; rep.px[i] = px
        rep.y[i] = y; rep.py[i] = py
        rep.z[i] = z; rep.pz[i] = pz
    end
    return COMPUTE_LUMINOSITY ? density * TWOPI : zero(density)
end

@inline _apply_slice_kick_one!(rep::Phase6DRep, i, moments2, center2,
                               kbb_slice, min_sigma,
                               virtual_drift::AbstractVirtualDrift,
                               longitudinal_kick::Val,
                               compute_luminosity::Bool) =
    _apply_slice_kick_one!(rep, i, moments2, center2, kbb_slice, min_sigma,
                           virtual_drift, longitudinal_kick,
                           Val(compute_luminosity))

# Compatibility entry point for code that exercised the former internal helper.
@inline _apply_slice_kick_one!(rep::Phase6DRep, i, moments2, center2,
                               kbb_slice, min_sigma,
                               longitudinal_kick::Bool=true,
                               compute_luminosity::Bool=true) =
    _apply_slice_kick_one!(rep, i, moments2, center2, kbb_slice, min_sigma,
                           HirataParaxialDrift(), Val(longitudinal_kick),
                           Val(compute_luminosity))
