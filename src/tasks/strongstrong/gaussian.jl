"""
    collide!(solver, beam1, beam2, backend)

Advance two beams through one strong-strong collision and return the luminosity
estimate for that collision.
"""
function collide!(solver::GaussianPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend})
    slices1 = longitudinal_slices(beam1.rep, solver.slicing)
    slices2 = longitudinal_slices(beam2.rep, solver.slicing)
    kbb1 = _strong_strong_kbb1(solver, beam1, beam2)
    kbb2 = _strong_strong_kbb2(solver, beam1, beam2)
    klum1, klum2 = _strong_strong_luminosity_scales(solver, beam1, beam2)
    luminosity = zero(eltype(beam1.rep.x))
    for (_, i, j) in _slice_collision_order(slices1, slices2)
        moments1 = _slice_transverse_moments(beam1.rep, slices1.indices[i], solver.ignore_centroid1, solver.min_sigma)
        moments2 = _slice_transverse_moments(beam2.rep, slices2.indices[j], solver.ignore_centroid2, solver.min_sigma)
        lum2 = _slice_slice_gaussian_kick!(
            beam1.rep, slices1.indices[i], moments2, slices2.center[j],
            slices2.weight[j] * kbb1, slices2.weight[j] * klum1,
            solver.min_sigma,
        )
        lum1 = _slice_slice_gaussian_kick!(
            beam2.rep, slices2.indices[j], moments1, slices1.center[i],
            slices1.weight[i] * kbb2, slices1.weight[i] * klum2,
            solver.min_sigma,
        )
        luminosity += solver.gaussian_when_luminosity == 1 ? lum1 : lum2
    end
    return luminosity
end

function _slice_slice_gaussian_kick!(rep::Phase6DRep, idx::Vector{Int}, moments2,
                                     center2, kbb_slice, klum_slice, min_sigma)
    isempty(idx) && return zero(eltype(rep.x))
    T = eltype(rep.x)
    n = length(idx)
    nchunks = Threads.nthreads()
    if nchunks == 1 || n < _STRONG_STRONG_PARALLEL_KICK_MIN
        lum = zero(T)
        for i in idx
            @inbounds lum += _apply_slice_kick_one!(rep, i, moments2, center2, kbb_slice, min_sigma)
        end
        return lum / TWOPI * klum_slice
    end
    local_lum = zeros(T, nchunks)
    Threads.@threads :static for chunk in 1:nchunks
        first_i, last_i = _chunk_bounds(n, nchunks, chunk)
        lum = zero(T)
        for pos in first_i:last_i
            @inbounds lum += _apply_slice_kick_one!(rep, idx[pos], moments2, center2, kbb_slice, min_sigma)
        end
        local_lum[chunk] = lum
    end
    return sum(local_lum) / TWOPI * klum_slice
end

@inline function _drifted_gaussian_moments(moments, S, min_sigma)
    mx = moments.mx + moments.mpx * S
    my = moments.my + moments.mpy * S
    sx2 = moments.sx^2 + (2 * moments.covxpx + moments.spx^2 * S) * S
    sy2 = moments.sy^2 + (2 * moments.covypy + moments.spy^2 * S) * S
    sigx = max(sqrt(max(sx2, zero(sx2))), min_sigma)
    sigy = max(sqrt(max(sy2, zero(sy2))), min_sigma)
    return (mx=mx, my=my, sigx=sigx, sigy=sigy)
end

@inline function _apply_slice_kick_one!(rep::Phase6DRep, i, moments2, center2, kbb_slice, min_sigma)
    S1 = (rep.z[i] - center2) / 2
    S2 = -S1
    drifted = _drifted_gaussian_moments(moments2, S2, min_sigma)
    rep.x[i] += rep.px[i] * S1
    rep.y[i] += rep.py[i] * S1
    xx = rep.x[i] - drifted.mx
    yy = rep.y[i] - drifted.my
    Kx, Ky = gaussian_beambeam_kick(drifted.sigx, drifted.sigy, xx, yy)
    rep.px[i] += kbb_slice * Kx
    rep.py[i] += kbb_slice * Ky
    expterm = exp(-0.5 * (xx^2 / drifted.sigx^2 + yy^2 / drifted.sigy^2))
    rep.x[i] -= rep.px[i] * S1
    rep.y[i] -= rep.py[i] * S1
    return expterm / drifted.sigx / drifted.sigy
end
