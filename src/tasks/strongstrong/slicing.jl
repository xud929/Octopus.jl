struct LongitudinalSlices{T,I}
    center::Vector{T}
    weight::Vector{T}
    boundary::Vector{T}
    indices::I
end

"""
    gaussian_slice_centers(nslices; sigma=1, mean=0)

Return equal-population longitudinal slice centroids for a Gaussian bunch.

The internal slice boundaries are Gaussian quantiles,
`sqrt(2) * inverse_erf(2p - 1)`. The returned center for each slice is the
conditional mean of the Gaussian between adjacent boundaries, so the two
outermost slices are finite even though their ideal boundaries are infinite.

```julia
centers = gaussian_slice_centers(15; sigma = 0.007)
```
"""
function gaussian_slice_centers(nslices::Integer; sigma::Real=1.0, mean::Real=0.0)
    ns = Int(nslices)
    ns > 0 || throw(ArgumentError("nslices must be positive"))
    T = promote_type(typeof(float(sigma)), typeof(float(mean)), Float64)
    σ = T(sigma)
    μ = T(mean)
    σ > zero(T) || throw(ArgumentError("sigma must be positive"))
    invsqrt2pi = inv(sqrt(TWOPI))
    centers = Vector{T}(undef, ns)
    for s in 1:ns
        a = s == 1 ? T(-Inf) : sqrt(T(2)) * inverse_erf(T(2 * (s - 1) / ns - 1))
        b = s == ns ? T(Inf) : sqrt(T(2)) * inverse_erf(T(2 * s / ns - 1))
        pdfa = isinf(a) ? zero(T) : invsqrt2pi * exp(-a * a / 2)
        pdfb = isinf(b) ? zero(T) : invsqrt2pi * exp(-b * b / 2)
        centers[s] = μ + σ * T(ns) * (pdfa - pdfb)
    end
    return centers
end

"""
    longitudinal_slices(rep_or_beam, slicing)

Return longitudinal slice centers, weights, boundaries, and particle indices for
the current CPU representation. This is intended for solver internals and
diagnostics.
"""
longitudinal_slices(beam::Beam, slicing::LongitudinalSlicing) =
    longitudinal_slices(beam.rep, slicing)

function longitudinal_slices(rep::Phase6DRep, slicing::LongitudinalSlicing)
    slicing.nslices > 0 || throw(ArgumentError("nslices must be positive"))
    isempty(rep.z) && throw(ArgumentError("longitudinal slicing requires at least one particle"))
    method = slicing.method
    flags = _live_flags(rep, active_live_mask())
    # Every method below divides by the live count and sizes boundaries from
    # live extrema, so an all-dead beam has to be rejected here rather than
    # surfacing downstream as a non-finite boundary.
    flags === nothing || count(flags) > 0 || throw(ArgumentError(
        "longitudinal slicing requires at least one live particle; " *
        "all $(length(rep.z)) are non-finite"))
    # `:equal_count` orders the whole beam and cuts it into equal parts, which
    # is a global sort rather than a fold: a rank can sort its own shard but
    # not learn where its particles sit in the beam's order without moving
    # them. Every other method sizes its boundaries from the longitudinal
    # statistics, which ARE folds and are already global.
    if method == :equal_count && _mp_nranks() > 1
        throw(ArgumentError(
            "longitudinal slicing method :equal_count needs a global ordering " *
            "of the beam, which the collective seam does not provide, so it " *
            "cannot run on the $(_mp_nranks()) ranks in force. Every other " *
            "method sizes its boundaries from the longitudinal statistics, " *
            "which are summed across the ranks: :equal_area, :equal_width, " *
            ":normal_quantile and :specified all run divided."))
    end
    if method == :equal_area
        return _longitudinal_slices_equal_area(rep, slicing, flags)
    elseif method == :equal_count
        return _longitudinal_slices_equal_count(rep, slicing, flags)
    elseif method == :equal_width || method == :equal_spaced
        return _longitudinal_slices_equal_width(rep, slicing, flags)
    elseif method == :normal_quantile || method == :gaussian || method == :Gaussian
        return _longitudinal_slices_gaussian(rep, slicing, flags)
    elseif method == :specified
        return _longitudinal_slices_specified(rep, slicing, flags)
    else
        throw(ArgumentError("unknown longitudinal slicing method $method"))
    end
end

function _strong_strong_kbb1(solver, beam1, beam2)
    solver.kbb1 !== nothing && return solver.kbb1
    p1, p2 = beam1.params, beam2.params
    isfinite(p1.E0) && !iszero(p1.E0) || throw(ArgumentError(
        "beam1 E0 must be finite and nonzero when kbb1 is not specified; got $(p1.E0)"))
    return p1.charge * p2.charge * p1.r0 * p2.npart * p1.mc2 / p1.E0
end

function _strong_strong_kbb2(solver, beam1, beam2)
    solver.kbb2 !== nothing && return solver.kbb2
    p1, p2 = beam1.params, beam2.params
    isfinite(p2.E0) && !iszero(p2.E0) || throw(ArgumentError(
        "beam2 E0 must be finite and nonzero when kbb2 is not specified; got $(p2.E0)"))
    return p1.charge * p2.charge * p2.r0 * p1.npart * p2.mc2 / p2.E0
end

function _strong_strong_luminosity_scales(solver, beam1, beam2)
    if solver.luminosity_scale !== nothing
        return solver.luminosity_scale, solver.luminosity_scale
    end
    p1, p2 = beam1.params, beam2.params
    # The macroparticle counts here are the BEAMS', not the shards': the scale
    # turns a per-macroparticle overlap into a physical luminosity, and a rank
    # dividing by its own count would scale its contribution by the rank count.
    n1 = _mp_global_count(length(beam1.rep))
    n2 = _mp_global_count(length(beam2.rep))
    n1 == 0 && throw(ArgumentError("strong-strong luminosity requires a nonempty beam1"))
    n2 == 0 && throw(ArgumentError("strong-strong luminosity requires a nonempty beam2"))
    return p1.npart * p2.npart / n1,
           p1.npart * p2.npart / n2
end

function _longitudinal_slices_equal_area(rep::Phase6DRep, slicing::LongitudinalSlicing, flags)
    slicing.resolution > 0 || throw(ArgumentError("resolution must be positive"))
    z = _host_array(rep.z)
    T = eltype(z)
    ns = slicing.nslices
    bins = ns * slicing.resolution
    stats = _live_z_stats(z, flags)
    zmin = stats.zmin
    zmax = stats.zmax
    if zmin == zmax
        boundaries = fill(T(zmin), ns + 1)
        indices = [Int[] for _ in 1:ns]
        for i in eachindex(z)
            _flag_live(flags, i) && push!(indices[1], i)
        end
        return _finish_longitudinal_slices(rep, slicing, indices, boundaries, flags)
    end
    width = (zmax - zmin) / bins
    counts = _threaded_histogram(z, zmin, width, bins, flags)
    _mp_nranks() == 1 || _mp_allsum!(counts)
    cumulative = cumsum(counts) ./ max(stats.n_live, 1)
    cumulative[end] = one(T)
    centers = [T(zmin + (i - 0.5) * width) for i in 1:bins]
    boundaries = Vector{T}(undef, ns + 1)
    boundaries[1] = T(zmin)
    boundaries[end] = T(zmax)
    current = 1
    for s in 1:(ns - 1)
        target = s / ns
        while current <= bins && cumulative[current] <= target
            current += 1
        end
        if current <= 1
            x1 = boundaries[1]
            x2 = centers[1]
            y1 = zero(T)
            y2 = cumulative[1]
        elseif current > bins
            x1 = centers[end]
            x2 = boundaries[end]
            y1 = cumulative[end - 1]
            y2 = one(T)
        else
            x1 = centers[current - 1]
            x2 = centers[current]
            y1 = cumulative[current - 1]
            y2 = cumulative[current]
        end
        boundaries[s + 1] = y2 == y1 ? (x1 + x2) / 2 :
                            x2 * (target - y1) / (y2 - y1) +
                            x1 * (target - y2) / (y1 - y2)
    end
    return _slices_from_boundaries(rep, slicing, boundaries, flags)
end

"""
    _slice_bin(zi, zmin, width, bins)

Longitudinal bin index for `zi`, or `0` for a coordinate that has none.

`floor(Int, NaN)` throws an `InexactError` from inside the kernel, so a
non-finite coordinate cannot be converted and must be rejected before the
conversion. The `!(...)` form is deliberate and matches `_pic_cic_weights`:
every comparison against `NaN` is false, so non-finite input takes the reject
branch without a separate `isfinite` call.

A particle killed by an aperture is NaN by construction, so this is the point
where a dead particle stops contributing to slicing rather than crashing it.
"""
@inline function _slice_bin(zi, zmin, width, bins::Int)
    d = (zi - zmin) / width
    !(d > -Inf && d < Inf) && return 0
    return clamp(floor(Int, d) + 1, 1, bins)
end

"""
    _live_flags(rep, mask)

Per-particle liveness for one slicing call, or `nothing` when the mask is off.

Slicing walks the representation several times -- extrema, then a histogram or
sort, then the index assignment -- so liveness is derived once here rather than
recomputed per pass. On CUDA storage that also collapses what would otherwise be
several device-to-host copies of all six coordinates into one.

`nothing` is the off state rather than a vector of `true`, so `_flag_live`
constant-folds to `true` and the unmasked passes keep their original cost.
"""
_live_flags(rep::Phase6DRep, ::LiveMask{false}) = nothing

function _live_flags(rep::Phase6DRep, ::LiveMask{true})
    x, px, y, py, z, pz = _host_coordinate_arrays(rep)
    flags = Vector{Bool}(undef, length(z))
    @inbounds for i in eachindex(z)
        flags[i] = is_live(x[i], px[i], y[i], py[i], z[i], pz[i])
    end
    return flags
end

@inline _flag_live(::Nothing, i) = true
@inline _flag_live(flags::Vector{Bool}, i) = @inbounds flags[i]

_live_count(::Nothing, n::Integer) = Int(n)
_live_count(flags::Vector{Bool}, n::Integer) = count(flags)

# One canonical reduction shape for every ORDER-DEPENDENT slicing statistic —
# the z mean, the z standard deviation, and the slice centroids (U6-7). Fixed
# 4096 lanes: lane t folds elements t, t + 4096, t + 2·4096, … in order, and
# the lane sums are then folded serially 1..4096. The same shape runs on both
# backends — strided lanes are coalesced for the CUDA kernels and one
# cache-resident accumulator pass for the CPU — so boundaries and centers are
# bit-identical across backends by construction rather than "close": before
# this, `:normal_quantile` boundaries differed by up to 1363 ulps and
# `:equal_count` centroids by up to 48,247 ulps between the CPU's serial or
# pairwise folds and the CUDA broadcast reductions, which at Float32 is a
# ~1e-7 relative divergence upstream of every kick. min/max/count are
# order-independent and exact under any shape, so they keep their native
# reductions on each backend. The lane count is a fixed constant for the same
# reason `_cuda_gaussian_moment_launch` fixes its geometry: the partition IS
# the summation order, so nothing runtime-dependent may choose it.
const _SLICE_FOLD_LANES = 4096

"""Lane-shaped Σ f(z_i) over live particles; the CUDA z-stats kernels
implement exactly this fold (see `_cuda_lane_z_moment_kernel!`)."""
function _lane_z_moment(z::AbstractVector, flags, μ, ::Val{POW};
                        offset::Integer=0) where {POW}
    T = eltype(z)
    L = _SLICE_FOLD_LANES
    acc = zeros(T, L)
    # Lanes are keyed by the GLOBAL particle index, so a divided beam puts each
    # particle in the lane it would have occupied undivided. The ranks then
    # exchange lane partials rather than scalars, which keeps the fold's shape
    # across processes even though the accumulation within a lane is split.
    @inbounds for i in eachindex(z)
        _flag_live(flags, i) || continue
        v = POW == 2 ? (z[i] - μ) * (z[i] - μ) : z[i]
        acc[((i + Int(offset) - 1) % L) + 1] += v
    end
    s = zero(T)
    @inbounds for t in 1:L
        s += acc[t]
    end
    # The ranks exchange the FOLDED scalar, not the 4096 lanes. Exchanging
    # lanes would keep the fold's shape across processes, but the shape is
    # already broken by the split within a lane -- a rank's partial starts
    # from zero where the undivided accumulation would have carried in
    # everything before it -- so it buys precision that is not there while
    # costing 4096x the bytes, which is 32 KB per call per rank against 8.
    return _mp_global_sum(s)
end

"""Lane-shaped Σ z[idx[k]] over a slice's member list, in list order; the
CUDA centroid kernel implements exactly this fold."""
function _lane_indexed_sum(z::AbstractVector, idx)
    T = eltype(z)
    L = _SLICE_FOLD_LANES
    acc = zeros(T, L)
    @inbounds for k in eachindex(idx)
        acc[((k - 1) % L) + 1] += z[idx[k]]
    end
    s = zero(T)
    @inbounds for t in 1:L
        s += acc[t]
    end
    # Keyed by the member's POSITION in the list, which is per-slice data no
    # fixed particle distribution aligns with, so a divided run groups these
    # differently from an undivided one however the exchange is shaped. Every
    # member is still counted exactly once; the difference is the
    # accumulation, and it is the parity tolerance class the campaign prices
    # (docs/design/multi_process_policy.md). So the ranks exchange the folded
    # scalar rather than the lanes.
    return _mp_global_sum(s)
end

"""
    _live_z_stats(z, flags)

Longitudinal extrema, mean, standard deviation and live count in one pass.

Every slicing method sizes its boundaries from some subset of these five
numbers, so masking them here is what stops a dead particle from moving a
boundary. With `flags === nothing` the loop is the unmasked reduction and keeps
the old NaN-propagating behaviour on purpose: `min`/`max` propagate `NaN` in
Julia, so a non-finite `z` still reaches `_finish_longitudinal_slices` as a
non-finite boundary and trips the chokepoint there, exactly as before.
"""
function _live_z_stats(z::AbstractVector, flags)
    T = eltype(z)
    zmin = T(Inf); zmax = T(-Inf)
    n_live = 0
    @inbounds for i in eachindex(z)
        _flag_live(flags, i) || continue
        zi = z[i]
        zmin = min(zmin, zi); zmax = max(zmax, zi)
        n_live += 1
    end
    # These five numbers set the slice boundaries, and every rank must get the
    # SAME ones or the ranks disagree about which particle is in which slice --
    # which is not a small difference but a different collision. Count and
    # extrema are order-independent and therefore exact at any rank count; the
    # mean and sigma go through the lane fold below, which carries the shard
    # offset so lanes match.
    offset = 0
    if _mp_nranks() > 1
        offset, _ = _mp_current_shard(length(z))
        counts = [n_live]
        _mp_allsum!(counts)
        n_live = counts[1]
        zmin, zmax = _mp_allminmax(zmin, zmax)
    end
    n_live == 0 && return (n_live=0, zmin=T(NaN), zmax=T(NaN), mean=T(NaN), sigma=T(NaN))
    # Mean and sigma through the canonical lane fold (U6-7), so the CUDA
    # twin's kernels produce bit-identical values; NaN from live input still
    # propagates through the lane sums exactly as it did serially.
    μ = _lane_z_moment(z, flags, zero(T), Val(1); offset=offset) / n_live
    s2 = _lane_z_moment(z, flags, μ, Val(2); offset=offset)
    return (n_live=n_live, zmin=zmin, zmax=zmax, mean=μ,
            sigma=sqrt(max(s2 / n_live, zero(T))))
end

"""
Bin the live particles by `z`, over the WHOLE beam.

The counts are integers, so the cross-rank sum is exact whatever order it
takes -- and it has to happen, because these counts are the empirical
distribution the equal-area boundaries are cut from. A rank binning only its
own shard cuts the boundaries of a beam it cannot see: measured, at two and
four ranks the boundaries bunched into the top of the distribution and left
whole slices empty, while the longitudinal statistics beside them were already
exact and agreed.
"""
function _threaded_histogram(z, zmin, width, bins::Int, flags=nothing)
    nchunks = _cpu_worker_count()
    if nchunks == 1
        counts = zeros(Int, bins)
        for i in eachindex(z)
            _flag_live(flags, i) || continue
            bin = _slice_bin(z[i], zmin, width, bins)
            bin == 0 || (counts[bin] += 1)
        end
        return counts
    end
    local_counts = [zeros(Int, bins) for _ in 1:nchunks]
    # `chunk_counts`, NOT `counts`. The do-block is a CLOSURE, and `counts` is
    # also assigned at function scope -- in the `nchunks == 1` branch above and
    # in the reduction below. Assigning it inside the closure therefore does not
    # create a per-worker local: it writes the one shared captured box, so all
    # workers end up incrementing whichever array was stored there last. The
    # result was a histogram that was silently wrong and different on every run
    # (totals of 392-399 where the answer is 397, bins both gaining and losing
    # counts), which propagated into the slice boundaries of the DEFAULT
    # `:equal_area` method for any run on more than one thread. A distinct name
    # is the whole fix; the name collision was the entire bug.
    _run_logical_workers(nchunks) do chunk, _
        first_i, last_i = _chunk_bounds(length(z), nchunks, chunk)
        chunk_counts = local_counts[chunk]
        for i in first_i:last_i
            _flag_live(flags, i) || continue
            zi = z[i]
            bin = _slice_bin(zi, zmin, width, bins)
            bin == 0 || (chunk_counts[bin] += 1)
        end
    end
    counts = local_counts[1]
    for chunk in 2:nchunks
        counts .+= local_counts[chunk]
    end
    return counts
end

function _longitudinal_slices_equal_count(rep::Phase6DRep, slicing::LongitudinalSlicing, flags)
    z = _host_array(rep.z)
    T = eltype(z)
    ns = slicing.nslices
    # Rank the live particles only. `sortperm` orders `NaN` above every finite
    # value, so sorting the whole array would pack the dead into the last
    # slices rather than dropping them -- equal-count is the one method where a
    # dead particle displaces a live one instead of merely shifting a boundary.
    order = flags === nothing ? sortperm(z) :
            sort!(findall(flags); by = i -> z[i])
    n = length(order)
    indices = [Int[] for _ in 1:ns]
    for s in 1:ns
        first_pos = floor(Int, (s - 1) * n / ns) + 1
        last_pos = floor(Int, s * n / ns)
        if first_pos <= last_pos
            append!(indices[s], @view order[first_pos:last_pos])
        end
    end
    sorted_z = z[order]
    stats = _live_z_stats(z, flags)
    boundaries = Vector{T}(undef, ns + 1)
    boundaries[1] = stats.zmin
    boundaries[end] = stats.zmax
    for s in 1:(ns - 1)
        pos = floor(Int, s * n / ns)
        boundaries[s + 1] = if pos == 0
            sorted_z[1]
        elseif pos == n
            sorted_z[end]
        else
            (sorted_z[pos] + sorted_z[pos + 1]) / 2
        end
    end
    return _finish_longitudinal_slices(rep, slicing, indices, boundaries, flags)
end

function _longitudinal_slices_equal_width(rep::Phase6DRep, slicing::LongitudinalSlicing, flags)
    z = _host_array(rep.z)
    T = eltype(z)
    ns = slicing.nslices
    stats = _live_z_stats(z, flags)
    zmin = stats.zmin
    zmax = stats.zmax
    boundaries = collect(range(zmin, zmax; length=ns + 1))
    if zmin == zmax
        indices = [Int[] for _ in 1:ns]
        for i in eachindex(z)
            _flag_live(flags, i) && push!(indices[1], i)
        end
        return _finish_longitudinal_slices(rep, slicing, indices, boundaries, flags)
    end
    width = (zmax - zmin) / ns
    indices = _threaded_indices_by_function(z, ns, flags) do zi
        return _slice_bin(zi, zmin, width, ns)
    end
    return _finish_longitudinal_slices(rep, slicing, indices, boundaries, flags)
end

function _longitudinal_slices_specified(rep::Phase6DRep, slicing::LongitudinalSlicing, flags)
    z = _host_array(rep.z)
    T = eltype(z)
    stats = _live_z_stats(z, flags)
    μ = stats.mean
    σ = stats.sigma
    internal = sort([T(μ + p * σ) for p in slicing.positions])
    boundaries = Vector{T}(undef, length(internal) + 2)
    boundaries[1] = stats.zmin
    boundaries[end] = stats.zmax
    for (i, b) in enumerate(internal)
        boundaries[i + 1] = clamp(b, boundaries[1], boundaries[end])
    end
    return _slices_from_boundaries(rep, slicing, boundaries, flags)
end

function _longitudinal_slices_gaussian(rep::Phase6DRep, slicing::LongitudinalSlicing, flags)
    z = _host_array(rep.z)
    T = eltype(z)
    ns = slicing.nslices
    stats = _live_z_stats(z, flags)
    μ = stats.mean
    σ = stats.sigma
    if σ == zero(T)
        boundaries = fill(T(μ), ns + 1)
        return _slices_from_boundaries(rep, slicing, boundaries, flags)
    end
    boundaries = _gaussian_slice_boundaries(T, ns, μ, σ, stats.zmin, stats.zmax)
    return _slices_from_boundaries(rep, slicing, boundaries, flags)
end

function _gaussian_slice_boundaries(::Type{T}, ns::Integer, μ, σ, zmin, zmax) where {T}
    boundaries = Vector{T}(undef, Int(ns) + 1)
    boundaries[1] = T(zmin)
    boundaries[end] = T(zmax)
    for s in 1:(Int(ns) - 1)
        q = sqrt(T(2)) * inverse_erf(T(2 * s / ns - 1))
        boundaries[s + 1] = clamp(T(μ + σ * q), boundaries[1], boundaries[end])
    end
    return boundaries
end

function _slices_from_boundaries(rep::Phase6DRep, slicing, boundaries, flags=nothing)
    z = _host_array(rep.z)
    ns = length(boundaries) - 1
    # A zero-width distribution collapses every boundary to one value, and
    # `searchsortedlast` + clamp then filed everything into slice `ns` -- while
    # the equal-width and equal-area paths deliberately use slice 1 for the
    # same beam. One convention, slice 1, for every method that reaches this
    # function (audit part 6, R7).
    #
    # NOT `:equal_count`, which never gets here: it builds membership from the
    # rank permutation and calls `_finish_longitudinal_slices` directly, so a
    # zero-width beam lands in the LAST slices by rank -- measured [2,2,3] for
    # seven co-located particles at ns=3, where every other method gives
    # [7,0,0], and [0,0,1] for a single particle where the others give [1,0,0].
    # That is deliberate and documented as the R2 rank contract in
    # `LongitudinalSlicing`'s docstring, and both backends agree on it; the word
    # "everywhere" was the only thing wrong here (2026-08-05_b audit, U6-8).
    if ns > 0 && boundaries[1] == boundaries[end]
        indices = [Int[] for _ in 1:ns]
        for i in eachindex(z)
            _flag_live(flags, i) && push!(indices[1], i)
        end
        return _finish_longitudinal_slices(rep, slicing, indices, boundaries, flags)
    end
    indices = _threaded_indices_by_function(z, ns, flags) do zi
        s = searchsortedlast(boundaries, zi)
        return clamp(s, 1, ns)
    end
    return _finish_longitudinal_slices(rep, slicing, indices, boundaries, flags)
end

function _threaded_indices_by_function(slice_index, z, ns::Int, flags=nothing)
    # A dead particle joins no slice. `_slice_bin` already returns `0` for a
    # non-finite coordinate, but the boundary-search callers do not:
    # `searchsortedlast` orders `NaN` above every boundary and would file it
    # into the last slice. Consulting `flags` first makes the drop uniform
    # across every slicing method rather than a property of one index function.
    @inline live_index(i) = _flag_live(flags, i) ? slice_index(z[i]) : 0
    nchunks = _cpu_worker_count()
    if nchunks == 1
        indices = [Int[] for _ in 1:ns]
        for i in eachindex(z)
            # `0` means the coordinate has no bin -- non-finite, e.g. a particle
            # an aperture killed. It joins no slice and so contributes to no
            # interaction, which is what a dead particle should do.
            si = live_index(i)
            si == 0 || push!(indices[si], i)
        end
        return indices
    end
    local_counts = [zeros(Int, ns) for _ in 1:nchunks]
    _run_logical_workers(nchunks) do chunk, _
        first_i, last_i = _chunk_bounds(length(z), nchunks, chunk)
        counts = local_counts[chunk]
        for i in first_i:last_i
            s = live_index(i)
            s == 0 || (counts[s] += 1)
        end
    end
    local_indices = [[Vector{Int}(undef, local_counts[chunk][s]) for s in 1:ns] for chunk in 1:nchunks]
    local_offsets = [zeros(Int, ns) for _ in 1:nchunks]
    _run_logical_workers(nchunks) do chunk, _
        first_i, last_i = _chunk_bounds(length(z), nchunks, chunk)
        offsets = local_offsets[chunk]
        chunk_indices = local_indices[chunk]
        for i in first_i:last_i
            s = live_index(i)
            s == 0 && continue
            offsets[s] += 1
            chunk_indices[s][offsets[s]] = i
        end
    end
    indices = [Int[] for _ in 1:ns]
    for s in 1:ns
        total = 0
        for chunk in 1:nchunks
            total += length(local_indices[chunk][s])
        end
        sizehint!(indices[s], total)
        for chunk in 1:nchunks
            append!(indices[s], local_indices[chunk][s])
        end
    end
    return indices
end

function _chunk_bounds(n::Int, nchunks::Int, chunk::Int)
    first_i = fld((chunk - 1) * n, nchunks) + 1
    last_i = fld(chunk * n, nchunks)
    return first_i, last_i
end

function _finish_longitudinal_slices(rep::Phase6DRep, slicing, indices, boundaries, flags=nothing)
    # Earliest non-finite chokepoint: a NaN/Inf z propagates into the boundary
    # extrema/quantiles of every slicing method, so one O(nslices) check here
    # covers them all (N1, docs/history/todo_ledger_archive.md).
    #
    # Under `allow_lost_particles` the boundaries were built from live particles
    # only, so a dead one can no longer reach them and this no longer fires for
    # a killed particle. What it still catches is the case it was written for: a
    # boundary that came out non-finite from *live* input, which is a solver bug
    # either way. That is the "no unexpected NaN" restatement, not a weakening.
    all(isfinite, boundaries) ||
        _nonfinite_coordinate_error(:beam, (z=rep.z,); context="longitudinal slicing")
    z = _host_array(rep.z)
    T = eltype(z)
    # Weights are a fraction of the *live* beam, so they still sum to one when
    # part of the beam is dead. Dividing by the full length would silently scale
    # every slice weight -- and therefore every kick -- by the survival ratio.
    # The whole beam's live count, so a slice's weight is its share of the
    # BEAM and not of the shard -- every kick scales with it.
    total = _mp_nranks() == 1 ? _live_count(flags, length(z)) :
            _masked_global_count(k -> _flag_live(flags, k), length(z))
    ns = length(indices)
    centers = Vector{T}(undef, ns)
    weights = Vector{T}(undef, ns)
    for s in 1:ns
        idx = indices[s]
        members = _mp_nranks() == 1 ? length(idx) : _mp_global_count(length(idx))
        weights[s] = members / total
        if slicing.center_position == :centroid
            # Canonical lane fold (U6-7): the CUDA centroid kernel and the
            # equal-count host path fold the same member list the same way.
            centers[s] = if _mp_nranks() == 1
                isempty(idx) ? (boundaries[s] + boundaries[s + 1]) / 2 :
                _lane_indexed_sum(z, idx) / length(idx)
            else
                # `_lane_indexed_sum` is itself a collective, so every rank
                # calls it whether or not it holds members of this slice.
                total_z = _lane_indexed_sum(z, idx)
                members == 0 ? (boundaries[s] + boundaries[s + 1]) / 2 :
                               total_z / members
            end
        elseif slicing.center_position == :midpoint
            centers[s] = (boundaries[s] + boundaries[s + 1]) / 2
        else
            throw(ArgumentError("unknown slice center_position $(slicing.center_position)"))
        end
    end
    return LongitudinalSlices(centers, weights, collect(boundaries), indices)
end

function _slice_collision_order(slices1, slices2)
    order = Tuple{promote_type(eltype(slices1.center),eltype(slices2.center)),Int,Int}[]
    for i in eachindex(slices1.center), j in eachindex(slices2.center)
        push!(order, (-(slices1.center[i] + slices2.center[j]) / 2, i, j))
    end
    sort!(order, by=first)
    return order
end

function _slice_collision_order_from_centers(centers1::AbstractVector, centers2::AbstractVector)
    T = promote_type(eltype(centers1), eltype(centers2))
    order = Tuple{T,Int,Int}[]
    for i in eachindex(centers1), j in eachindex(centers2)
        push!(order, (-(T(centers1[i]) + T(centers2[j])) / 2, i, j))
    end
    sort!(order, by=first)
    return order
end

"""
    collision_pair_batches(centers1, centers2)
    collision_pair_batches(nslices1, nslices2; sigma1=1, sigma2=1, mean1=0, mean2=0)

Group slice-pair collisions into ready conflict-free batches.

Pairs are sorted by computed collision time,
`-(center1[i] + center2[j]) / 2`. A pair is ready when every earlier
collision involving its beam-1 slice and every earlier collision involving its
beam-2 slice has already been completed. Each batch contains ready pairs with
no repeated beam-1 or beam-2 slice, so the pairs in that batch can be processed
simultaneously without changing the per-slice collision order.

Each returned pair is a named tuple `(time, i, j)`.

```julia
batches = collision_pair_batches(15, 15; sigma1 = 0.007, sigma2 = 0.060)
length(batches)
maximum(length, batches)
```
"""
function collision_pair_batches(centers1::AbstractVector, centers2::AbstractVector)
    order = _slice_collision_order_from_centers(centers1, centers2)
    T = promote_type(eltype(centers1), eltype(centers2))
    pairtype = NamedTuple{(:time,:i,:j),Tuple{T,Int,Int}}
    pairs = [(time=T(time), i=i, j=j) for (time, i, j) in order]
    batches = Vector{Vector{pairtype}}()
    isempty(pairs) && return batches

    ns1 = length(centers1)
    ns2 = length(centers2)
    by_i = [Int[] for _ in 1:ns1]
    by_j = [Int[] for _ in 1:ns2]
    for k in eachindex(pairs)
        p = pairs[k]
        push!(by_i[p.i], k)
        push!(by_j[p.j], k)
    end

    next_i = ones(Int, ns1)
    next_j = ones(Int, ns2)
    done = falses(length(pairs))
    remaining = length(pairs)
    while remaining > 0
        current = pairtype[]
        used_i = Set{Int}()
        used_j = Set{Int}()
        for k in eachindex(pairs)
            done[k] && continue
            p = pairs[k]
            (p.i in used_i || p.j in used_j) && continue
            ready_i = next_i[p.i] <= length(by_i[p.i]) && by_i[p.i][next_i[p.i]] == k
            ready_j = next_j[p.j] <= length(by_j[p.j]) && by_j[p.j][next_j[p.j]] == k
            if ready_i && ready_j
                push!(current, p)
                push!(used_i, p.i)
                push!(used_j, p.j)
                done[k] = true
                next_i[p.i] += 1
                next_j[p.j] += 1
                remaining -= 1
            end
        end
        isempty(current) && error("internal collision scheduler error: no ready slice-pair found")
        push!(batches, current)
    end
    return batches
end

collision_pair_batches(slices1::LongitudinalSlices, slices2::LongitudinalSlices) =
    collision_pair_batches(slices1.center, slices2.center)

function collision_pair_batches(nslices1::Integer, nslices2::Integer;
                                sigma1::Real=1.0, sigma2::Real=1.0,
                                mean1::Real=0.0, mean2::Real=0.0)
    centers1 = gaussian_slice_centers(nslices1; sigma=sigma1, mean=mean1)
    centers2 = gaussian_slice_centers(nslices2; sigma=sigma2, mean=mean2)
    return collision_pair_batches(centers1, centers2)
end

_slice_transverse_moments(rep::Phase6DRep, idx::Vector{Int},
                          ignore_centroid::Bool, min_sigma) =
    _slice_transverse_moments(rep, idx, ignore_centroid, min_sigma, Val(false))

@inline _shifted_second_moment(sum2, mean_offset, invn) =
    muladd(-mean_offset, mean_offset, sum2 * invn)

@inline _shifted_cross_moment(sum12, mean_offset1, mean_offset2, invn) =
    muladd(-mean_offset1, mean_offset2, sum12 * invn)

"""
The transverse coordinates of a slice's globally-first member, on every rank.

Two collectives and no gather: the ranks agree on WHICH particle it is with a
minimum over the global index each holds, and then the one rank that owns it
contributes its coordinates while the others contribute zeros, so the sum is
that rank's values exactly.
"""
function _mp_slice_reference(rep::Phase6DRep, idx::Vector{Int}, ::Type{T}) where {T}
    offset, _ = _mp_current_shard(length(rep.z))
    mine = isempty(idx) ? typemax(Int) : offset + idx[1]
    first_global, _ = _mp_allminmax(mine, mine)
    values = zeros(T, 4)
    if !isempty(idx) && offset + idx[1] == first_global
        i = idx[1]
        @inbounds values .= (T(rep.x[i]), T(rep.px[i]), T(rep.y[i]), T(rep.py[i]))
    end
    _mp_allsum!(values)
    return (values[1], values[2], values[3], values[4])
end

function _slice_transverse_moments(rep::Phase6DRep, idx::Vector{Int},
                                   ignore_centroid::Bool, min_sigma,
                                   ::Val{COUPLED}) where {COUPLED}
    x, px, y, py = rep.x, rep.px, rep.y, rep.py
    T = promote_type(eltype(x), typeof(min_sigma))
    # The count is the WHOLE slice's, so every rank agrees on whether the slice
    # is empty and therefore on whether the collectives below happen at all --
    # a rank that returned early because its own shard held no member of this
    # slice would leave its peers waiting at the next one.
    divided = _mp_nranks() > 1
    # TWO counts, and confusing them is a segfault: `n_local` is how many
    # members THIS rank holds and bounds every loop and chunk grid below,
    # while `n` is how many the slice has and is the denominator the moments
    # divide by. They are the same number in a single-process run, which is
    # why a first cut used one for both and crashed only when a shard's slice
    # crossed the chunking threshold.
    n_local = length(idx)
    n = divided ? _mp_global_count(n_local) : n_local
    if n == 0
        z = zero(T)
        floor2 = T(min_sigma) * T(min_sigma)
        moments = StrongTransverseMoments{T,COUPLED}(
            floor2, z, floor2, z, z, z, z, z, z, z)
        return (mx=z, sx=T(min_sigma), mpx=z, spx=z, covxpx=z,
                my=z, sy=T(min_sigma), mpy=z, spy=z, covypy=z,
                moments=moments)
    end
    # The shift reference. Every rank must use the SAME one: these are shifted
    # moments, and two ranks shifting by different origins produce sums that
    # cannot be added. Undivided it is the slice's first member, as it has
    # always been; divided it is the first member GLOBALLY, which is that same
    # particle.
    x0, px0, y0, py0 = if divided
        _mp_slice_reference(rep, idx, T)
    else
        first_particle = idx[1]
        @inbounds (T(x[first_particle]), T(px[first_particle]),
                   T(y[first_particle]), T(py[first_particle]))
    end
    sdx = zero(T); sdpx = zero(T); sdy = zero(T); sdpy = zero(T)
    sdx2 = zero(T); sdpx2 = zero(T); sdy2 = zero(T); sdpy2 = zero(T)
    sdxpx = zero(T); sdypy = zero(T)
    sdxy = zero(T); sdxpy = zero(T); sdpxy = zero(T); sdpxpy = zero(T)
    # Fixed chunk grid above the threshold, and path choice by data size
    # ONLY: the chunk-ordered fold must not depend on the worker count, and
    # neither may the serial/chunked decision (U5-2; moments moved by up to
    # 131,072 ulps between 1/4/8 workers pre-fix).
    nchunks = _REDUCTION_CHUNKS
    # Path choice and chunk grid on the LOCAL count: they are about the work
    # this rank does. The fold's shape therefore depends on the shard size,
    # which is a property of the rank count and not of the worker count -- the
    # count-invariance U5-2 pinned is within a process and is untouched.
    if n_local < _STRONG_STRONG_PARALLEL_MOMENT_MIN
        for i in idx
            @inbounds begin
                dx = T(x[i]) - x0; dpx = T(px[i]) - px0
                dy = T(y[i]) - y0; dpy = T(py[i]) - py0
                sdx += dx; sdpx += dpx; sdy += dy; sdpy += dpy
                sdx2 += dx * dx; sdpx2 += dpx * dpx
                sdy2 += dy * dy; sdpy2 += dpy * dpy
                sdxpx += dx * dpx; sdypy += dy * dpy
                if COUPLED
                    sdxy += dx * dy; sdxpy += dx * dpy
                    sdpxy += dpx * dy; sdpxpy += dpx * dpy
                end
            end
        end
    else
        local_sums = [zeros(T, COUPLED ? 14 : 10) for _ in 1:nchunks]
        _run_logical_workers(nchunks) do chunk, _
            first_i, last_i = _chunk_bounds(n_local, nchunks, chunk)
            sums = local_sums[chunk]
            for pos in first_i:last_i
                @inbounds begin
                    i = idx[pos]
                    dx = T(x[i]) - x0; dpx = T(px[i]) - px0
                    dy = T(y[i]) - y0; dpy = T(py[i]) - py0
                    sums[1] += dx; sums[2] += dpx
                    sums[3] += dy; sums[4] += dpy
                    sums[5] += dx * dx; sums[6] += dpx * dpx
                    sums[7] += dy * dy; sums[8] += dpy * dpy
                    sums[9] += dx * dpx; sums[10] += dy * dpy
                    if COUPLED
                        sums[11] += dx * dy; sums[12] += dx * dpy
                        sums[13] += dpx * dy; sums[14] += dpx * dpy
                    end
                end
            end
        end
        for sums in local_sums
            sdx += sums[1]; sdpx += sums[2]; sdy += sums[3]; sdpy += sums[4]
            sdx2 += sums[5]; sdpx2 += sums[6]
            sdy2 += sums[7]; sdpy2 += sums[8]
            sdxpx += sums[9]; sdypy += sums[10]
            if COUPLED
                sdxy += sums[11]; sdxpy += sums[12]
                sdpxy += sums[13]; sdpxpy += sums[14]
            end
        end
    end
    if divided
        # One message per slice, carrying the ten or fourteen shifted sums.
        # The kick that follows is local, so this is the only exchange the
        # soft-Gaussian path needs per slice.
        packed = COUPLED ?
            T[sdx, sdpx, sdy, sdpy, sdx2, sdpx2, sdy2, sdpy2, sdxpx, sdypy,
              sdxy, sdxpy, sdpxy, sdpxpy] :
            T[sdx, sdpx, sdy, sdpy, sdx2, sdpx2, sdy2, sdpy2, sdxpx, sdypy]
        _mp_allsum!(packed)
        sdx, sdpx, sdy, sdpy = packed[1], packed[2], packed[3], packed[4]
        sdx2, sdpx2, sdy2, sdpy2 = packed[5], packed[6], packed[7], packed[8]
        sdxpx, sdypy = packed[9], packed[10]
        if COUPLED
            sdxy, sdxpy = packed[11], packed[12]
            sdpxy, sdpxpy = packed[13], packed[14]
        end
    end
    invn = inv(T(n))
    dmx = sdx * invn; dmpx = sdpx * invn
    dmy = sdy * invn; dmpy = sdpy * invn
    mx = x0 + dmx; mpx = px0 + dmpx
    my = y0 + dmy; mpy = py0 + dmpy
    sx2 = _shifted_second_moment(sdx2, dmx, invn)
    spx2 = _shifted_second_moment(sdpx2, dmpx, invn)
    sy2 = _shifted_second_moment(sdy2, dmy, invn)
    spy2 = _shifted_second_moment(sdpy2, dmpy, invn)
    covxpx = _shifted_cross_moment(sdxpx, dmx, dmpx, invn)
    covypy = _shifted_cross_moment(sdypy, dmy, dmpy, invn)
    covxy = COUPLED ? _shifted_cross_moment(sdxy, dmx, dmy, invn) : zero(T)
    covxpy = COUPLED ? _shifted_cross_moment(sdxpy, dmx, dmpy, invn) : zero(T)
    covpxy = COUPLED ? _shifted_cross_moment(sdpxy, dmpx, dmy, invn) : zero(T)
    covpxpy = COUPLED ? _shifted_cross_moment(sdpxpy, dmpx, dmpy, invn) : zero(T)
    floor2 = T(min_sigma) * T(min_sigma)
    varx = max(T(sx2), floor2)
    vary = max(T(sy2), floor2)
    moments = StrongTransverseMoments{T,COUPLED}(
        varx, T(covxy), vary,
        T(covxpx), T(covxpy), T(covpxy), T(covypy),
        max(T(spx2), zero(T)), T(covpxpy), max(T(spy2), zero(T)),
    )
    if ignore_centroid
        mx = zero(T); mpx = zero(T); my = zero(T); mpy = zero(T)
    end
    return (
        mx=T(mx), sx=sqrt(varx),
        mpx=T(mpx), spx=sqrt(max(T(spx2), zero(T))), covxpx=T(covxpx),
        my=T(my), sy=sqrt(vary),
        mpy=T(mpy), spy=sqrt(max(T(spy2), zero(T))), covypy=T(covypy),
        moments=moments,
    )
end
