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
    method = slicing.method
    if method == :equal_area
        return _longitudinal_slices_equal_area(rep, slicing)
    elseif method == :equal_count
        return _longitudinal_slices_equal_count(rep, slicing)
    elseif method == :equal_width || method == :equal_spaced
        return _longitudinal_slices_equal_width(rep, slicing)
    elseif method == :specified
        return _longitudinal_slices_specified(rep, slicing)
    else
        throw(ArgumentError("unknown longitudinal slicing method $method"))
    end
end

function _strong_strong_kbb1(solver, beam1, beam2)
    solver.kbb1 !== nothing && return solver.kbb1
    p1, p2 = beam1.params, beam2.params
    return p1.charge * p2.charge * p1.r0 * p2.npart * p1.mc2 / p1.E0
end

function _strong_strong_kbb2(solver, beam1, beam2)
    solver.kbb2 !== nothing && return solver.kbb2
    p1, p2 = beam1.params, beam2.params
    return p1.charge * p2.charge * p2.r0 * p1.npart * p2.mc2 / p2.E0
end

function _strong_strong_luminosity_scales(solver, beam1, beam2)
    if solver.luminosity_scale !== nothing
        return solver.luminosity_scale, solver.luminosity_scale
    end
    p1, p2 = beam1.params, beam2.params
    return p1.npart * p2.npart / length(beam1.rep),
           p1.npart * p2.npart / length(beam2.rep)
end

function _longitudinal_slices_equal_area(rep::Phase6DRep, slicing::LongitudinalSlicing)
    slicing.resolution > 0 || throw(ArgumentError("resolution must be positive"))
    z = _host_array(rep.z)
    T = eltype(z)
    ns = slicing.nslices
    bins = ns * slicing.resolution
    zmin = minimum(z)
    zmax = maximum(z)
    if zmin == zmax
        boundaries = fill(T(zmin), ns + 1)
        indices = [Int[] for _ in 1:ns]
        append!(indices[1], eachindex(z))
        return _finish_longitudinal_slices(rep, slicing, indices, boundaries)
    end
    width = (zmax - zmin) / bins
    counts = _threaded_histogram(z, zmin, width, bins)
    cumulative = cumsum(counts) ./ length(z)
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
    return _slices_from_boundaries(rep, slicing, boundaries)
end

function _threaded_histogram(z, zmin, width, bins::Int)
    nchunks = Threads.nthreads()
    if nchunks == 1
        counts = zeros(Int, bins)
        for zi in z
            bin = floor(Int, (zi - zmin) / width) + 1
            counts[clamp(bin, 1, bins)] += 1
        end
        return counts
    end
    local_counts = [zeros(Int, bins) for _ in 1:nchunks]
    Threads.@threads :static for chunk in 1:nchunks
        first_i, last_i = _chunk_bounds(length(z), nchunks, chunk)
        counts = local_counts[chunk]
        for i in first_i:last_i
            zi = z[i]
            bin = floor(Int, (zi - zmin) / width) + 1
            counts[clamp(bin, 1, bins)] += 1
        end
    end
    counts = local_counts[1]
    for chunk in 2:nchunks
        counts .+= local_counts[chunk]
    end
    return counts
end

function _longitudinal_slices_equal_count(rep::Phase6DRep, slicing::LongitudinalSlicing)
    z = _host_array(rep.z)
    T = eltype(z)
    n = length(z)
    ns = slicing.nslices
    order = sortperm(z)
    indices = [Int[] for _ in 1:ns]
    for s in 1:ns
        first_pos = floor(Int, (s - 1) * n / ns) + 1
        last_pos = floor(Int, s * n / ns)
        if first_pos <= last_pos
            append!(indices[s], @view order[first_pos:last_pos])
        end
    end
    sorted_z = z[order]
    boundaries = Vector{T}(undef, ns + 1)
    boundaries[1] = minimum(z)
    boundaries[end] = maximum(z)
    for s in 1:(ns - 1)
        pos = floor(Int, s * n / ns)
        boundaries[s + 1] = (sorted_z[pos] + sorted_z[pos + 1]) / 2
    end
    return _finish_longitudinal_slices(rep, slicing, indices, boundaries)
end

function _longitudinal_slices_equal_width(rep::Phase6DRep, slicing::LongitudinalSlicing)
    z = _host_array(rep.z)
    T = eltype(z)
    ns = slicing.nslices
    zmin = minimum(z)
    zmax = maximum(z)
    boundaries = collect(range(zmin, zmax; length=ns + 1))
    if zmin == zmax
        indices = [Int[] for _ in 1:ns]
        append!(indices[1], eachindex(z))
        return _finish_longitudinal_slices(rep, slicing, indices, boundaries)
    end
    width = (zmax - zmin) / ns
    indices = _threaded_indices_by_function(z, ns) do zi
        return clamp(floor(Int, (zi - zmin) / width) + 1, 1, ns)
    end
    return _finish_longitudinal_slices(rep, slicing, indices, boundaries)
end

function _longitudinal_slices_specified(rep::Phase6DRep, slicing::LongitudinalSlicing)
    z = _host_array(rep.z)
    T = eltype(z)
    n = length(z)
    μ = sum(z) / n
    σ = sqrt(max(sum(zi -> (zi - μ)^2, z) / n, zero(T)))
    internal = sort([T(μ + p * σ) for p in slicing.positions])
    boundaries = Vector{T}(undef, length(internal) + 2)
    boundaries[1] = minimum(z)
    boundaries[end] = maximum(z)
    for (i, b) in enumerate(internal)
        boundaries[i + 1] = clamp(b, boundaries[1], boundaries[end])
    end
    return _slices_from_boundaries(rep, slicing, boundaries)
end

function _slices_from_boundaries(rep::Phase6DRep, slicing, boundaries)
    z = _host_array(rep.z)
    ns = length(boundaries) - 1
    indices = _threaded_indices_by_function(z, ns) do zi
        s = searchsortedlast(boundaries, zi)
        return clamp(s, 1, ns)
    end
    return _finish_longitudinal_slices(rep, slicing, indices, boundaries)
end

function _threaded_indices_by_function(slice_index, z, ns::Int)
    nchunks = Threads.nthreads()
    if nchunks == 1
        indices = [Int[] for _ in 1:ns]
        for i in eachindex(z)
            push!(indices[slice_index(z[i])], i)
        end
        return indices
    end
    local_counts = [zeros(Int, ns) for _ in 1:nchunks]
    Threads.@threads :static for chunk in 1:nchunks
        first_i, last_i = _chunk_bounds(length(z), nchunks, chunk)
        counts = local_counts[chunk]
        for i in first_i:last_i
            s = slice_index(z[i])
            counts[s] += 1
        end
    end
    local_indices = [[Vector{Int}(undef, local_counts[chunk][s]) for s in 1:ns] for chunk in 1:nchunks]
    local_offsets = [zeros(Int, ns) for _ in 1:nchunks]
    Threads.@threads :static for chunk in 1:nchunks
        first_i, last_i = _chunk_bounds(length(z), nchunks, chunk)
        offsets = local_offsets[chunk]
        chunk_indices = local_indices[chunk]
        for i in first_i:last_i
            s = slice_index(z[i])
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

function _finish_longitudinal_slices(rep::Phase6DRep, slicing, indices, boundaries)
    z = _host_array(rep.z)
    T = eltype(z)
    total = length(z)
    ns = length(indices)
    centers = Vector{T}(undef, ns)
    weights = Vector{T}(undef, ns)
    for s in 1:ns
        idx = indices[s]
        weights[s] = length(idx) / total
        if slicing.center_position == :centroid
            centers[s] = isempty(idx) ? (boundaries[s] + boundaries[s + 1]) / 2 :
                         sum(i -> z[i], idx) / length(idx)
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

function _slice_transverse_moments(rep::Phase6DRep, idx::Vector{Int}, ignore_centroid::Bool, min_sigma)
    x, px, y, py = rep.x, rep.px, rep.y, rep.py
    T = promote_type(eltype(x), typeof(min_sigma))
    n = length(idx)
    if n == 0
        z = zero(T)
        return (mx=z, sx=T(min_sigma), mpx=z, spx=z, covxpx=z,
                my=z, sy=T(min_sigma), mpy=z, spy=z, covypy=z)
    end
    sx = zero(T); spx = zero(T); sy = zero(T); spy = zero(T)
    sx2sum = zero(T); spx2sum = zero(T); sy2sum = zero(T); spy2sum = zero(T)
    sxpxsum = zero(T); sypysum = zero(T)
    nchunks = Threads.nthreads()
    if nchunks == 1 || n < _STRONG_STRONG_PARALLEL_MOMENT_MIN
        for i in idx
            @inbounds begin
                xi = x[i]; pxi = px[i]; yi = y[i]; pyi = py[i]
                sx += xi; spx += pxi; sy += yi; spy += pyi
                sx2sum += xi * xi; spx2sum += pxi * pxi
                sy2sum += yi * yi; spy2sum += pyi * pyi
                sxpxsum += xi * pxi; sypysum += yi * pyi
            end
        end
    else
        local_sums = [zeros(T, 10) for _ in 1:nchunks]
        Threads.@threads :static for chunk in 1:nchunks
            first_i, last_i = _chunk_bounds(n, nchunks, chunk)
            sums = local_sums[chunk]
            for pos in first_i:last_i
                @inbounds begin
                    i = idx[pos]
                    xi = x[i]; pxi = px[i]; yi = y[i]; pyi = py[i]
                    sums[1] += xi; sums[2] += pxi; sums[3] += yi; sums[4] += pyi
                    sums[5] += xi * xi; sums[6] += pxi * pxi
                    sums[7] += yi * yi; sums[8] += pyi * pyi
                    sums[9] += xi * pxi; sums[10] += yi * pyi
                end
            end
        end
        for sums in local_sums
            sx += sums[1]; spx += sums[2]; sy += sums[3]; spy += sums[4]
            sx2sum += sums[5]; spx2sum += sums[6]
            sy2sum += sums[7]; spy2sum += sums[8]
            sxpxsum += sums[9]; sypysum += sums[10]
        end
    end
    invn = inv(T(n))
    mx = sx * invn
    mpx = spx * invn
    my = sy * invn
    mpy = spy * invn
    sx2 = sx2sum * invn - mx * mx
    spx2 = spx2sum * invn - mpx * mpx
    sy2 = sy2sum * invn - my * my
    spy2 = spy2sum * invn - mpy * mpy
    covxpx = sxpxsum * invn - mx * mpx
    covypy = sypysum * invn - my * mpy
    if ignore_centroid
        mx = zero(T); mpx = zero(T); my = zero(T); mpy = zero(T)
    end
    return (
        mx=T(mx), sx=max(sqrt(max(T(sx2), zero(T))), T(min_sigma)),
        mpx=T(mpx), spx=sqrt(max(T(spx2), zero(T))), covxpx=T(covxpx),
        my=T(my), sy=max(sqrt(max(T(sy2), zero(T))), T(min_sigma)),
        mpy=T(mpy), spy=sqrt(max(T(spy2), zero(T))), covypy=T(covypy),
    )
end
