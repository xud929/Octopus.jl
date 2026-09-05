# The slice-aligned collide (multi-process step 4d). Design and the review
# it went through: docs/design/multi_process_policy.md, "Step 4d".
#
# For one collide the live particles of each beam are laid out by slice,
# slice-aligned, so a slice lives on a contiguous GROUP of ranks and no rank
# holds parts of two slices (below `P <= nslices` a rank holds whole slices).
# Every pair of slices is then a conversation between two small groups and a
# few owners, point-to-point, and nothing a pair does waits on a rank outside
# it. The particles migrate in at the entry and back at the exit; outside the
# collide the chunk-aligned home layout is untouched.
#
# At one rank every message is to oneself (the seam's self-delivery), one
# group holds every slice with its members in home order, and the deposit,
# the solve and the luminosity are the undivided collide's operations on the
# same numbers in the same order: that run is the CPU collide bit for bit,
# which is the pin that touches this code.

"""
    _PICSlicedLayout

Where every slice of one beam lives for this collide: `counts[s]` the global
live members of slice `s`, `groups[s]` the 0-based ranks holding it (a
contiguous range, empty for an empty slice), `parts[s][k]` the positions
within the slice -- in the beam's global member order -- that the `k`-th
rank of the group holds. Derived on every rank from the counts alone.
"""
struct _PICSlicedLayout
    counts::Vector{Int}
    groups::Vector{UnitRange{Int}}
    parts::Vector{Vector{UnitRange{Int}}}
end

"""
The slice-aligned cut. With `P <= nslices` whole slices go to ranks by their
midpoint in the cumulative count; with `P > nslices` each non-empty slice
gets a share of ranks proportional to its count (largest remainder, never
more ranks than members), and its members are split evenly among them.
"""
function _pic_sliced_layout(counts::Vector{Int}, P::Int)
    ns = length(counts)
    N = sum(counts)
    groups = [1:0 for _ in 1:ns]
    parts = [UnitRange{Int}[] for _ in 1:ns]
    N == 0 && return _PICSlicedLayout(counts, groups, parts)
    if P <= ns
        C = 0
        for s in 1:ns
            n = counts[s]
            if n > 0
                r = min(P - 1, floor(Int, (C + n / 2) / (N / P)))
                groups[s] = r:r
                parts[s] = [1:n]
            end
            C += n
        end
        return _PICSlicedLayout(counts, groups, parts)
    end
    g = zeros(Int, ns)
    frac = fill(-1.0, ns)
    for s in 1:ns
        counts[s] == 0 && continue
        q = P * counts[s] / N
        g[s] = min(counts[s], max(1, floor(Int, q)))
        frac[s] = q - floor(q)
    end
    total = sum(g)
    while total < P
        s = 0
        for t in 1:ns
            counts[t] == 0 && continue
            g[t] < counts[t] || continue
            (s == 0 || frac[t] > frac[s]) && (s = t)
        end
        s == 0 && break            # every slice already has as many ranks as members
        g[s] += 1
        frac[s] = -1.0
        total += 1
    end
    while total > P
        s = 0
        for t in 1:ns
            g[t] > 1 || continue
            (s == 0 || g[t] > g[s]) && (s = t)
        end
        s == 0 && break
        g[s] -= 1
        total -= 1
    end
    r0 = 0
    for s in 1:ns
        g[s] == 0 && continue
        groups[s] = r0:(r0 + g[s] - 1)
        parts[s] = [let (lo, hi) = _chunk_bounds(counts[s], g[s], k); lo:hi; end for k in 1:g[s]]
        r0 += g[s]
    end
    return _PICSlicedLayout(counts, groups, parts)
end

"""The rank holding position `pos` of slice `s`."""
function _pic_sliced_rank(layout::_PICSlicedLayout, s::Int, pos::Int)
    group = layout.groups[s]
    for (k, part) in enumerate(layout.parts[s])
        pos in part && return group[k]
    end
    error("position $(pos) of slice $(s) is outside every part of its group")
end

"""The slices this rank holds, with the part index of each."""
function _pic_sliced_mine(layout::_PICSlicedLayout, rank::Int)
    mine = Tuple{Int,Int}[]
    for s in eachindex(layout.groups)
        group = layout.groups[s]
        rank in group && push!(mine, (s, rank - first(group) + 1))
    end
    return mine
end

"""
    _PICSlicedBeam{T}

One beam on this rank for the collide: the slices it holds (`slices`, in
slice order, each `(s, part)`), their coordinates (`states[s]`, six vectors
in the beam's global member order), and what the return migration needs --
the received columns' order by slice (`bucket`), where each slice's bucket
starts (`starts`), the columns' senders (`senders`), and, for the home side,
the home index of every column it sent in the order it sent them (`home`).
"""
struct _PICSlicedBeam{T}
    layout::_PICSlicedLayout
    slices::Vector{Tuple{Int,Int}}
    states::Dict{Int,NamedTuple{(:x, :px, :y, :py, :z, :pz),NTuple{6,Vector{T}}}}
    bucket::Vector{Int}
    starts::Dict{Int,Int}
    senders::Vector{Int}
    home::Vector{Int}
    migrated_out::Int
    migrated_in::Int
end

"""
Migrate one beam in: pack the live members slice by slice with their slice
index, send each to the rank the layout gives its position, and bucket what
arrives by slice. The position of a member within its slice is this rank's
prefix of the slice's members over the ranks before it plus its local order
-- the prefix from one all-sum of the per-rank slice counts.
"""
function _pic_sliced_migrate_in(rep::Phase6DRep, slices, layout::_PICSlicedLayout,
                                ::Type{T}) where {T}
    ns = length(layout.counts)
    P = _mp_nranks()
    rank = _mp_rank()
    local_counts = zeros(Float64, ns, P)
    for s in 1:ns
        local_counts[s, rank + 1] = length(slices.indices[s])
    end
    _mp_allsum!(local_counts)
    prefix = zeros(Int, ns)
    for s in 1:ns, q in 1:rank
        prefix[s] += Int(local_counts[s, q])
    end
    ncols = sum(length, slices.indices; init=0)
    cols = Matrix{T}(undef, 7, ncols)
    dest = Vector{Int}(undef, ncols)
    home = Vector{Int}(undef, ncols)
    c = 0
    for s in 1:ns
        for (o, i) in enumerate(slices.indices[s])
            c += 1
            @inbounds begin
                cols[1, c] = rep.x[i]; cols[2, c] = rep.px[i]
                cols[3, c] = rep.y[i]; cols[4, c] = rep.py[i]
                cols[5, c] = rep.z[i]; cols[6, c] = rep.pz[i]
                cols[7, c] = T(s)
            end
            dest[c] = _pic_sliced_rank(layout, s, prefix[s] + o)
            home[c] = i
        end
    end
    order = sortperm(dest; alg=MergeSort)          # the stable order the exchange applies
    received, from_counts = _mp_exchange_columns(cols, dest)
    m = size(received, 2)
    slice_of = [Int(received[7, j]) for j in 1:m]
    bucket = sortperm(slice_of; alg=MergeSort)
    senders = Vector{Int}(undef, m)
    j = 0
    for (q, n) in enumerate(from_counts), _ in 1:n
        j += 1
        senders[j] = q - 1
    end
    states = Dict{Int,NamedTuple{(:x, :px, :y, :py, :z, :pz),NTuple{6,Vector{T}}}}()
    starts = Dict{Int,Int}()
    mine = _pic_sliced_mine(layout, rank)
    b = 1
    for (s, _) in mine
        n = 0
        while b + n <= m && slice_of[bucket[b + n]] == s
            n += 1
        end
        x = Vector{T}(undef, n); px = similar(x); y = similar(x)
        py = similar(x); z = similar(x); pz = similar(x)
        for o in 1:n
            col = bucket[b + o - 1]
            @inbounds begin
                x[o] = received[1, col]; px[o] = received[2, col]
                y[o] = received[3, col]; py[o] = received[4, col]
                z[o] = received[5, col]; pz[o] = received[6, col]
            end
        end
        states[s] = (x=x, px=px, y=y, py=py, z=z, pz=pz)
        starts[s] = b
        b += n
    end
    b - 1 == m || error("received $(m) columns but bucketed $(b - 1): a column of a slice this rank does not hold")
    return _PICSlicedBeam{T}(layout, mine, states, bucket, starts, senders, home[order],
                            ncols, m)
end

"""
Migrate one beam back: every column returns to its sender in the order it
arrived, so the home rank's columns come back in the order it sent them and
land in their home slots through the order it remembered.
"""
function _pic_sliced_migrate_out!(rep::Phase6DRep, beam::_PICSlicedBeam{T}) where {T}
    m = length(beam.bucket)
    cols = Matrix{T}(undef, 6, m)
    for (s, _) in beam.slices
        st = beam.states[s]
        b0 = beam.starts[s]
        for o in eachindex(st.x)
            col = beam.bucket[b0 + o - 1]
            @inbounds begin
                cols[1, col] = st.x[o]; cols[2, col] = st.px[o]
                cols[3, col] = st.y[o]; cols[4, col] = st.py[o]
                cols[5, col] = st.z[o]; cols[6, col] = st.pz[o]
            end
        end
    end
    back, _ = _mp_exchange_columns(cols, beam.senders)
    size(back, 2) == length(beam.home) || error(
        "$(size(back, 2)) columns came home, $(length(beam.home)) were sent")
    for k in eachindex(beam.home)
        i = beam.home[k]
        @inbounds begin
            rep.x[i] = back[1, k]; rep.px[i] = back[2, k]
            rep.y[i] = back[3, k]; rep.py[i] = back[4, k]
            rep.z[i] = back[5, k]; rep.pz[i] = back[6, k]
        end
    end
    return nothing
end

# --- scratch ------------------------------------------------------------------

"""Buffers the sliced collide reuses across batches: pools of planes,
potentials, luminosity deposits and records, each taken in order and reset
per batch (every message of a batch is waited before the next)."""
mutable struct _PICSlicedScratch{T}
    planes::Vector{Matrix{T}}
    plane_cursor::Int
    lum::Vector{Matrix{T}}
    lum_cursor::Int
    records::Vector{Vector{T}}
    record_cursor::Int
    fields::Vector{_PICFieldWorkspace{T}}   # Ex, Ey per plane on the field side
    field_cursor::Int
end
_PICSlicedScratch{T}() where {T} =
    _PICSlicedScratch{T}(Matrix{T}[], 0, Matrix{T}[], 0, Vector{T}[], 0, _PICFieldWorkspace{T}[], 0)

function _pic_sliced_plane!(sc::_PICSlicedScratch{T}, nx::Int, ny::Int) where {T}
    sc.plane_cursor += 1
    if sc.plane_cursor > length(sc.planes)
        push!(sc.planes, zeros(T, nx, ny))
    end
    A = sc.planes[sc.plane_cursor]
    size(A) == (nx, ny) || (A = zeros(T, nx, ny); sc.planes[sc.plane_cursor] = A)
    return A
end
function _pic_sliced_lum!(sc::_PICSlicedScratch{T}, nx::Int, ny::Int) where {T}
    sc.lum_cursor += 1
    if sc.lum_cursor > length(sc.lum)
        push!(sc.lum, zeros(T, nx, ny))
    end
    A = sc.lum[sc.lum_cursor]
    size(A) == (nx, ny) || (A = zeros(T, nx, ny); sc.lum[sc.lum_cursor] = A)
    return A
end
function _pic_sliced_record!(sc::_PICSlicedScratch{T}, n::Int) where {T}
    sc.record_cursor += 1
    if sc.record_cursor > length(sc.records)
        push!(sc.records, zeros(T, n))
    end
    v = sc.records[sc.record_cursor]
    length(v) == n || (v = zeros(T, n); sc.records[sc.record_cursor] = v)
    fill!(v, zero(T))
    return v
end
function _pic_sliced_field!(sc::_PICSlicedScratch{T}, nx::Int, ny::Int) where {T}
    sc.field_cursor += 1
    if sc.field_cursor > length(sc.fields)
        push!(sc.fields, _PICFieldWorkspace(zeros(T, 0, 0), zeros(T, nx, ny), zeros(T, nx, ny)))
    end
    f = sc.fields[sc.field_cursor]
    size(f.Ex) == (nx, ny) || (f = _PICFieldWorkspace(zeros(T, 0, 0), zeros(T, nx, ny), zeros(T, nx, ny));
                               sc.fields[sc.field_cursor] = f)
    return f
end
function _pic_sliced_reset!(sc::_PICSlicedScratch)
    sc.plane_cursor = 0; sc.lum_cursor = 0; sc.record_cursor = 0; sc.field_cursor = 0
    return nothing
end

# --- the records ---------------------------------------------------------------
#
# A member's record for a pair, 32 numbers: as SOURCE of its direction
# (bounds negated-min/max x 4, sums x 4, count, flag) and as FIELD of the
# other (the same ten), then its slice's first member (x, px, y, py, z),
# which the coordinator takes from the group's first rank; the last slot is
# unused. The coordinator's reduced record, 64 numbers: for each direction
# the source's ten, the field's ten, the source's first member (five), the
# field's first member (five), and a verdict slot.
const _PIC_SLICED_RECORD = 32
const _PIC_SLICED_REDUCED = 64

@inline _pic_sliced_role_offset(as_source::Bool) = as_source ? 0 : 10

"""
This rank's record for pair `(i, j)` from its part of one slice: the extents
and sums of the part as the source of one direction (drifted to the field
slice's edges) and as the field of the other (drifted to the source's
centre), the `_pic_batch_local_extents!` loops on one part.
"""
function _pic_sliced_record(rec::Vector{T}, solver::PICPoissonSolver, part,
                            param_own, param_other, origin) where {T}
    fill!(rec, zero(T))
    ge = Symbol(solver.grid_extent)
    n = length(part.x)
    # as source: drifts to the other slice's edges
    sL = T(0.5) * (T(param_own.center) - T(param_other.lb))
    sR = T(0.5) * (T(param_own.center) - T(param_other.rb))
    if origin !== nothing
        x0 = T(origin[1]) + T(origin[2]) * sL
        y0 = T(origin[3]) + T(origin[4]) * sL
    elseif n > 0
        x0 = part.x[1] + part.px[1] * sL
        y0 = part.y[1] + part.py[1] * sL
    else
        x0 = zero(T); y0 = zero(T)
    end
    xmin = T(Inf); xmax = T(-Inf); ymin = T(Inf); ymax = T(-Inf)
    sxs = zero(T); sxs2 = zero(T); sys = zero(T); sys2 = zero(T)
    for k in 1:n
        @inbounds begin
            xl = part.x[k] + part.px[k] * sL
            yl = part.y[k] + part.py[k] * sL
            xr = part.x[k] + part.px[k] * sR
            yr = part.y[k] + part.py[k] * sR
            xmin = min(xmin, xl, xr); xmax = max(xmax, xl, xr)
            ymin = min(ymin, yl, yr); ymax = max(ymax, yl, yr)
            if ge !== :extrema
                dxl = xl - x0; dxr = xr - x0
                dyl = yl - y0; dyr = yr - y0
                sxs += dxl + dxr; sxs2 += dxl * dxl + dxr * dxr
                sys += dyl + dyr; sys2 += dyl * dyl + dyr * dyr
            end
        end
    end
    bad = n > 0 && !all(isfinite, (xmin, xmax, ymin, ymax))
    @inbounds begin
        rec[1] = -xmin; rec[2] = xmax; rec[3] = -ymin; rec[4] = ymax
        rec[5] = sxs; rec[6] = sxs2; rec[7] = sys; rec[8] = sys2
        rec[9] = T(2 * n); rec[10] = bad ? one(T) : zero(T)
    end
    # as field: drifted to the other slice's centre, without writing the drift
    center = T(param_other.center)
    if origin !== nothing
        s0 = T(0.5) * (T(origin[5]) - center)
        fx0 = T(origin[1]) + s0 * T(origin[2])
        fy0 = T(origin[3]) + s0 * T(origin[4])
    elseif n > 0
        fx0 = part.x[1] + T(0.5) * (part.z[1] - center) * part.px[1]
        fy0 = part.y[1] + T(0.5) * (part.z[1] - center) * part.py[1]
    else
        fx0 = zero(T); fy0 = zero(T)
    end
    fxmin = T(Inf); fxmax = T(-Inf); fymin = T(Inf); fymax = T(-Inf)
    fxs = zero(T); fxs2 = zero(T); fys = zero(T); fys2 = zero(T)
    for k in 1:n
        @inbounds begin
            s = T(0.5) * (part.z[k] - center)
            xd = part.x[k] + s * part.px[k]
            yd = part.y[k] + s * part.py[k]
            fxmin = min(fxmin, xd); fxmax = max(fxmax, xd)
            fymin = min(fymin, yd); fymax = max(fymax, yd)
            if ge !== :extrema
                dx = xd - fx0; dy = yd - fy0
                fxs += dx; fxs2 += dx * dx
                fys += dy; fys2 += dy * dy
            end
        end
    end
    fbad = n > 0 && !all(isfinite, (fxmin, fxmax, fymin, fymax))
    @inbounds begin
        rec[11] = -fxmin; rec[12] = fxmax; rec[13] = -fymin; rec[14] = fymax
        rec[15] = fxs; rec[16] = fxs2; rec[17] = fys; rec[18] = fys2
        rec[19] = T(n); rec[20] = fbad ? one(T) : zero(T)
        if n > 0
            rec[21] = part.x[1]; rec[22] = part.px[1]; rec[23] = part.y[1]
            rec[24] = part.py[1]; rec[25] = part.z[1]
        end
    end
    return rec
end

"""
The coordinator's fold of the members' records into the reduced record:
extents by max (negated minima), sums, counts and flags in group rank order
-- the same additions the all-summed 4c stacks made -- the first member from
each group's first rank. `recs1` are `G1_i`'s records in rank order (source
of direction 1, field of direction 2), `recs2` are `G2_j`'s.
"""
function _pic_sliced_reduce(red::Vector{T}, recs1, recs2) where {T}
    fill!(red, zero(T))
    fill!(view(red, 1:4), T(-Inf)); fill!(view(red, 11:14), T(-Inf))
    fill!(view(red, 31:34), T(-Inf)); fill!(view(red, 41:44), T(-Inf))
    # direction 1: source = group 1 (its role-0 block), field = group 2 (its role-10 block)
    # direction 2: source = group 2 (role 0), field = group 1 (role 10)
    fold!(dst, off_dst, recs, off_src) = begin
        for r in recs
            @inbounds for k in 1:4
                dst[off_dst + k] = max(dst[off_dst + k], r[off_src + k])
            end
            @inbounds for k in 5:10
                dst[off_dst + k] += r[off_src + k]
            end
        end
        nothing
    end
    fold!(red, 0, recs1, 0)        # d1 source bounds/sums (from G1 as source)
    fold!(red, 10, recs2, 10)      # d1 field (from G2 as field)
    fold!(red, 30, recs2, 0)       # d2 source (from G2 as source)
    fold!(red, 40, recs1, 10)      # d2 field (from G1 as field)
    isempty(recs1) || copyto!(red, 21, recs1[1], 21, 5)   # d1 source origin: G1's first rank
    isempty(recs2) || copyto!(red, 26, recs2[1], 21, 5)   # d1 field origin: G2's first rank
    isempty(recs2) || copyto!(red, 51, recs2[1], 21, 5)   # d2 source origin
    isempty(recs1) || copyto!(red, 56, recs1[1], 21, 5)   # d2 field origin
    bad = red[10] > 0 || red[20] > 0 || red[40] > 0 || red[50] > 0
    red[61] = bad ? one(T) : zero(T)
    return red
end

"""
The grids of one direction from the reduced record (`d = 1`: offsets 0 and
10; `d = 2`: 30 and 40), the `_pic_batch_prepare!` arithmetic. Returns
`(source_grid0, field_grid0, source_bounds, field_bounds)`.
"""
function _pic_sliced_grids(solver::PICPoissonSolver, ::Type{T}, red, d::Int,
                           param_source, param_field) where {T}
    o = d == 1 ? 0 : 30
    ge = Symbol(solver.grid_extent)
    kext = T(solver.grid_extent_sigma)
    sL = T(0.5) * (T(param_source.center) - T(param_field.lb))
    @inbounds begin
        sxmin = -red[o + 1]; sxmax = red[o + 2]; symin = -red[o + 3]; symax = red[o + 4]
        sxs = red[o + 5]; sxs2 = red[o + 6]; sys = red[o + 7]; sys2 = red[o + 8]
        ns = Int(red[o + 9])
        fxmin = -red[o + 11]; fxmax = red[o + 12]; fymin = -red[o + 13]; fymax = red[o + 14]
        fxs = red[o + 15]; fxs2 = red[o + 16]; fys = red[o + 17]; fys2 = red[o + 18]
        nf = Int(red[o + 19])
        sx0 = T(red[o + 21]) + T(red[o + 22]) * sL
        sy0 = T(red[o + 23]) + T(red[o + 24]) * sL
        s0 = T(0.5) * (T(red[o + 30]) - T(param_source.center))
        fx0 = T(red[o + 26]) + s0 * T(red[o + 27])
        fy0 = T(red[o + 28]) + s0 * T(red[o + 29])
    end
    sxmin, sxmax = _pic_axis_extent(ge, sxmin, sxmax, sx0, sxs, sxs2, ns, kext)
    symin, symax = _pic_axis_extent(ge, symin, symax, sy0, sys, sys2, ns, kext)
    fxmin, fxmax = _pic_axis_extent(ge, fxmin, fxmax, fx0, fxs, fxs2, nf, kext)
    fymin, fymax = _pic_axis_extent(ge, fymin, fymax, fy0, fys, fys2, nf, kext)
    all(isfinite, (sxmin, sxmax, symin, symax, fxmin, fxmax, fymin, fymax)) ||
        return nothing
    source_grid0, field_grid0 = _pic_interaction_grids(
        solver, sxmin, sxmax, symin, symax, fxmin, fxmax, fymin, fymax)
    return (source_grid0, field_grid0,
            (xmin=sxmin, xmax=sxmax, ymin=symin, ymax=symax),
            (xmin=fxmin, xmax=fxmax, ymin=fymin, ymax=fymax))
end

# The final grids of a direction, nine numbers: bad flag, source x0 y0 width
# height, field x0 y0 width height.
const _PIC_SLICED_GRIDS = 9
_pic_sliced_grid_from(v, o) = (x0=v[o + 1], y0=v[o + 2], width=v[o + 3], height=v[o + 4])

# --- tags ------------------------------------------------------------------------
@inline _pic_sliced_tag(pair::Int, code::Int) = (pair - 1) * 32 + code
const _PIC_TAG_RECORD1 = 1      # G1 member's record to the coordinator
const _PIC_TAG_RECORD2 = 2      # G2 member's record
const _PIC_TAG_REDUCED = 3      # coordinator to owner(d): 3 + d - 1
const _PIC_TAG_GRIDS = 5        # owner(d) to members: 5 + d - 1
const _PIC_TAG_PARTIAL = 7      # member to owner(d), plane m: 7 + 3(d-1) + (m-1)
const _PIC_TAG_POTENTIAL = 13   # owner(d) to field members: 13 + 3(d-1) + (m-1)
const _PIC_TAG_LUMEXT1 = 19     # G1 member's luminosity extrema
const _PIC_TAG_LUMEXT2 = 20
const _PIC_TAG_LUMMESH = 21
const _PIC_TAG_LUMDEP1 = 22
const _PIC_TAG_LUMDEP2 = 23
# The :sigma origin messages take two codes INSIDE the pair's tag space
# (`_PIC_TAG_ORIGIN1`/`2`, below). A band of their own above the pairs'
# collided with the pair band from a few hundred pairs on, and a slice-keyed
# tag also leaned on MPI's non-overtaking rule to keep consecutive origins of
# one slice in order; per-pair codes need neither argument (the 4e review).
# A batch holds at most one pair per slice, so the batched loop's per-slice
# exchange is per-pair too and takes the same tags.

# --- one pair's bookkeeping on this rank -----------------------------------------------

"""
What this rank is to pair `(i, j)` of the batch: member of the source group
of direction 1 (`in1`), of direction 2 (`in2`), the coordinator, the owner
of either direction; and the buffers its roles fill.
"""
mutable struct _PICSlicedPair{T}
    p::Int                       # position in the collision order
    i::Int
    j::Int
    pair::Int                    # tag base
    in1::Bool
    in2::Bool
    coord::Int
    owner::NTuple{2,Int}
    param1::NamedTuple{(:weight, :lb, :center, :rb),NTuple{4,T}}
    param2::NamedTuple{(:weight, :lb, :center, :rb),NTuple{4,T}}
    rec1::Union{Nothing,Vector{T}}
    rec2::Union{Nothing,Vector{T}}
    recs_in::Vector{Vector{T}}   # coordinator: G1's then G2's records
    reduced::Union{Nothing,Vector{T}}
    grids_out::NTuple{2,Union{Nothing,Vector{T}}}   # owner(d)'s grids message
    grids_in::NTuple{2,Union{Nothing,Vector{T}}}    # a member's received grids per direction
    owned::NTuple{2,Any}         # owner(d): (source_grid, field_grid, green_fft) or nothing
    partials_in::NTuple{2,Vector{Vector{Matrix{T}}}}  # owner(d): per plane, the group's partials
    potentials_in::NTuple{2,Vector{Matrix{T}}}        # field member: per plane
    potentials_out::NTuple{2,Vector{Matrix{T}}}       # owner(d): per plane
    vx1::Vector{T}; vy1::Vector{T}                    # virtual positions of my part of slice i
    vx2::Vector{T}; vy2::Vector{T}                    # of my part of slice j
    lumext::Union{Nothing,Vector{T}}
    lumexts_in::Vector{Vector{T}}
    lummesh::Union{Nothing,Vector{T}}
    lumdep1::Union{Nothing,Matrix{T}}
    lumdep2::Union{Nothing,Matrix{T}}
    lumdeps_in::NTuple{2,Vector{Matrix{T}}}
    bad::Bool
end

function _pic_sliced_pair(::Type{T}, p, i, j, ns2, in1, in2, coord, owner, param1, param2) where {T}
    none = Union{Nothing,Vector{T}}
    return _PICSlicedPair{T}(p, i, j, (i - 1) * ns2 + j, in1, in2, coord, owner,
        param1, param2, nothing, nothing, Vector{T}[], nothing,
        (nothing, nothing), (nothing, nothing), (nothing, nothing),
        (Vector{Matrix{T}}[], Vector{Matrix{T}}[]), (Matrix{T}[], Matrix{T}[]),
        (Matrix{T}[], Matrix{T}[]), T[], T[], T[], T[], nothing, Vector{T}[], nothing,
        nothing, nothing, (Matrix{T}[], Matrix{T}[]), false)
end

# --- the leaves: the arithmetic BOTH loops run ---------------------------------
#
# The batched loop (`:sequential`) and the dataflow loop (`:wavefront`) differ
# only in WHEN a pair's stages run, never in what they compute -- so every
# number either produces comes from the functions below, and the launcher's
# `:sequential == :default` arm pins the two loops to the same bits on every
# gate. Nothing here communicates.

"""
One direction's deposits on a source part: the dropped count against the
source mesh, then each plane's interior at the drift its node sits at.
"""
function _pic_sliced_deposit!(planes, solver::PICPoissonSolver, part, param_source,
                              param_field, source_grid, workspace::_PICCPUWorkspace,
                              ::Type{T}) where {T}
    nx, ny = solver.grid
    sL = T(0.5) * (T(param_source.center) - T(param_field.lb))
    sR = T(0.5) * (T(param_source.center) - T(param_field.rb))
    hx = T(source_grid.width) / T(nx - 1)
    hy = T(source_grid.height) / T(ny - 1)
    x0 = T(source_grid.x0); y0 = T(source_grid.y0)
    if Symbol(solver.grid_extent) !== :extrema
        workspace.dropped[] += _pic_count_outside_box_drifted(
            part.x, part.px, part.y, part.py, sL, sR,
            source_grid.x0, source_grid.x0 + source_grid.width,
            source_grid.y0, source_grid.y0 + source_grid.height)
    end
    for m in eachindex(planes)
        s = m == 1 ? sL : m == 2 ? sR : T(0.5) * (sL + sR)
        plane = planes[m]
        fill!(plane, zero(T))
        _pic_deposit_drifted!(plane, solver.deposit_method, part.x, part.px, part.y, part.py,
                              T(s), x0, y0, hx, hy, nx, ny, workspace)
    end
    return planes
end

"""The source part's virtual positions at the luminosity plane, read BEFORE
any kick of that part."""
function _pic_sliced_virtual!(vx, vy, part, param_source, param_field, ::Type{T}) where {T}
    sM = T(0.5) * (T(param_source.center) - T(param_field.center))
    n = length(part.x)
    resize!(vx, n); resize!(vy, n)
    _pic_map_particles(n) do first_i, last_i
        _pic_virtual_positions_range!(vx, vy, part, sM, first_i, last_i)
    end
    return nothing
end

"""
One plane on its owner: the group's partials summed IN GROUP RANK ORDER --
never on arrival, which is what keeps the sum the serial one -- into the
padded plane's interior, the FFT convolution with the pair's Green table,
and the potential's interior out.
"""
function _pic_sliced_solve_plane!(phi, partials, green_fft, workspace::_PICCPUWorkspace,
                                  nx::Int, ny::Int, ::Type{T}) where {T}
    charge = workspace.charge
    fill!(charge, zero(T))
    interior = view(charge, 1:nx, 1:ny)
    for partial in partials
        interior .+= partial
    end
    spectral = workspace.spectral
    spectral .= charge
    workspace.fft_plan * spectral
    spectral .*= green_fft
    workspace.ifft_plan * spectral
    for jj in 1:ny, ii in 1:nx
        @inbounds phi[ii, jj] = real(spectral[ii, jj])
    end
    return phi
end

"""
One direction's field work on a field part: the gradients of the gathered
potentials, the drift, the dropped count against the mesh the kick reads,
and the kick.
"""
function _pic_sliced_kick!(fields, solver::PICPoissonSolver, field, potentials,
                           source_grid, field_grid, param_source, param_field, kbb,
                           workspace::_PICCPUWorkspace, ::Type{T}) where {T}
    nx, ny = solver.grid
    hx = T(source_grid.width) / T(nx - 1)
    hy = T(source_grid.height) / T(ny - 1)
    fourth = _pic_fourth_order(solver)
    for m in eachindex(fields)
        fw = fields[m]
        _pic_field!(fw.Ex, fw.Ey, potentials[m], hx, hy, fourth)
    end
    nfield = length(field.x)
    center = T(param_source.center)
    for k in 1:nfield
        @inbounds begin
            s = T(0.5) * (field.z[k] - center)
            field.x[k] += s * field.px[k]
            field.y[k] += s * field.py[k]
            if solver.longitudinal_kick
                field.pz[k] -= T(0.25) * (field.px[k] * field.px[k] + field.py[k] * field.py[k])
            end
        end
    end
    if Symbol(solver.grid_extent) !== :extrema
        workspace.dropped[] += _pic_count_outside_box(
            field.x, field.y,
            field_grid.x0, field_grid.x0 + field_grid.width,
            field_grid.y0, field_grid.y0 + field_grid.height)
    end
    kick_scale = T(2) * T(kbb)
    hzi, zbias = _slice_interpolation_parameters(T(param_field.lb), T(param_field.rb))
    phiL = potentials[1]; phiR = potentials[2]
    L = fields[1]; R = fields[2]
    if length(potentials) == 3
        phiM = potentials[3]; M = fields[3]
        _pic_map_particles(nfield) do first_i, last_i
            _pic_apply_kick_quadratic_range!(
                solver, field, field_grid, phiL, L.Ex, L.Ey, phiM, M.Ex, M.Ey,
                phiR, R.Ex, R.Ey, kick_scale, hzi, zbias, center, T, first_i, last_i)
        end
    else
        _pic_map_particles(nfield) do first_i, last_i
            _pic_apply_kick_range!(
                solver, field, field_grid, phiL, L.Ex, L.Ey, phiR, R.Ex, R.Ey,
                kick_scale, hzi, zbias, center, T, first_i, last_i)
        end
    end
    return nothing
end

"""
The pair's luminosity on its coordinator: each beam's deposits folded in
group rank order, then the overlap sum over the full deposit extent.
"""
function _pic_sliced_overlap(q1, q2, q1s, q2s, mesh, klum, lnx::Int, lny::Int,
                             ::Type{T}) where {T}
    fill!(q1, zero(T)); fill!(q2, zero(T))
    for q in q1s
        q1 .+= q
    end
    for q in q2s
        q2 .+= q
    end
    lum = zero(T)
    for jj in 1:(lny + 1), ii in 1:(lnx + 1)
        @inbounds lum += q1[ii, jj] * q2[ii, jj]
    end
    return lum * T(klum) * mesh[5] * mesh[6]
end

"""The distinct ranks of both groups, ascending."""
function _pic_sliced_members(g1::UnitRange{Int}, g2::UnitRange{Int})
    ranks = Int[]
    for r in g1; push!(ranks, r); end
    for r in g2; r in g1 || push!(ranks, r); end
    return sort!(ranks)
end

# --- the collide ---------------------------------------------------------------------

"""
The slice-aligned collide of one batch list. Fills `ran` and `lum_parts`
(this rank's coordinated pairs; the caller all-sums the vector) and leaves
the kicked coordinates in the sliced beams.
"""
function _pic_collide_sliced!(sb1::_PICSlicedBeam{T}, sb2::_PICSlicedBeam{T}, batches, order,
                              pair_pos, lum_parts, ran, solver::PICPoissonSolver,
                              slices1, slices2, workspace::_PICCPUWorkspace, green_cache,
                              sc::_PICSlicedScratch{T}, kbb1, kbb2, klum,
                              compute_luminosity::Bool) where {T}
    P = _mp_nranks()
    rank = _mp_rank()
    ns1 = length(sb1.layout.counts)
    ns2 = length(sb2.layout.counts)
    nx, ny = solver.grid
    lnx, lny = _pic_luminosity_grid(solver)
    nplanes = _pic_quadratic_slice(solver) ? 3 : 2
    ge = Symbol(solver.grid_extent)
    sigma = ge === :sigma
    reqs = _mp_requests()
    nbad = 0
    _mp_check_tag_bound(_pic_sliced_tag(ns1 * ns2, _PIC_TAG_CODES))
    # The :sigma origins: each slice's estimator is shifted about the slice's
    # first member AS IT IS AT THAT PAIR -- kicked by the pairs before it --
    # so each group's first rank tells the other members its current first
    # member before every batch the slice takes part in (stage 0, under
    # :sigma only; one small hop). Held outside the per-batch pool.
    origins1 = Dict{Int,Vector{T}}()
    origins2 = Dict{Int,Vector{T}}()
    if sigma
        for (sb, origins) in ((sb1, origins1), (sb2, origins2)), (s, _) in sb.slices
            origins[s] = zeros(T, 5)
        end
    end
    partials_sent = 0; partials_received = 0; potentials_sent = 0; potentials_received = 0
    lum_sent = 0; lum_received = 0; messages = 0; pairs_coordinated = 0; planes_solved = 0
    for batch in batches
        _pic_sliced_reset!(sc)
        # the pairs of this batch, in (i, j) order, with this rank's roles
        pairs = _PICSlicedPair{T}[]
        canon = sort([(pr.i, pr.j) for pr in batch])
        for (q, (i, j)) in enumerate(canon)
            n1 = sb1.layout.counts[i]
            n2 = sb2.layout.counts[j]
            p = pair_pos[(i, j)]
            if n1 == 0 || n2 == 0
                ran[p] = false
                continue
            end
            ran[p] = true
            g1 = sb1.layout.groups[i]
            g2 = sb2.layout.groups[j]
            in1 = rank in g1
            in2 = rank in g2
            coord = first(g1)
            owner = ((2 * (q - 1)) % P, (2 * (q - 1) + 1) % P)
            involved = in1 || in2 || rank == coord || rank == owner[1] || rank == owner[2]
            involved || continue
            param1 = (weight=T(slices1.weight[i]), lb=T(slices1.boundary[i]),
                      center=T(slices1.center[i]), rb=T(slices1.boundary[i + 1]))
            param2 = (weight=T(slices2.weight[j]), lb=T(slices2.boundary[j]),
                      center=T(slices2.center[j]), rb=T(slices2.boundary[j + 1]))
            push!(pairs, _pic_sliced_pair(T, p, i, j, ns2, in1, in2, coord, owner, param1, param2))
        end
        # --- stage 0 (:sigma): the current first member of each slice in play
        if sigma
            for pr in pairs, (sb, origins, code, s, in_group) in
                    ((sb1, origins1, _PIC_TAG_ORIGIN1, pr.i, pr.in1),
                     (sb2, origins2, _PIC_TAG_ORIGIN2, pr.j, pr.in2))
                in_group || continue
                group = sb.layout.groups[s]
                v = origins[s]
                st = sb.states[s]
                if rank == first(group)
                    fill!(v, zero(T))
                    if !isempty(st.x)
                        v[1] = st.x[1]; v[2] = st.px[1]; v[3] = st.y[1]; v[4] = st.py[1]; v[5] = st.z[1]
                    end
                    for r in group
                        r == rank && continue
                        push!(reqs, _mp_isend(v, r, _pic_sliced_tag(pr.pair, code)))
                        messages += 1
                    end
                else
                    push!(reqs, _mp_irecv!(v, first(group), _pic_sliced_tag(pr.pair, code)))
                end
            end
            _mp_wait_all(reqs, :wait_origins)
        end
        # --- stage 1: records to the coordinator ----------------------------------
        for pr in pairs
            g1 = sb1.layout.groups[pr.i]; g2 = sb2.layout.groups[pr.j]
            if pr.in1
                pr.rec1 = _pic_sliced_record(_pic_sliced_record!(sc, _PIC_SLICED_RECORD),
                                             solver, sb1.states[pr.i], pr.param1, pr.param2,
                                             sigma ? origins1[pr.i] : nothing)
                push!(reqs, _mp_isend(pr.rec1, pr.coord, _pic_sliced_tag(pr.pair, _PIC_TAG_RECORD1)))
                messages += 1
            end
            if pr.in2
                pr.rec2 = _pic_sliced_record(_pic_sliced_record!(sc, _PIC_SLICED_RECORD),
                                             solver, sb2.states[pr.j], pr.param2, pr.param1,
                                             sigma ? origins2[pr.j] : nothing)
                push!(reqs, _mp_isend(pr.rec2, pr.coord, _pic_sliced_tag(pr.pair, _PIC_TAG_RECORD2)))
                messages += 1
            end
            if rank == pr.coord
                pairs_coordinated += 1
                for r in g1
                    v = _pic_sliced_record!(sc, _PIC_SLICED_RECORD)
                    push!(pr.recs_in, v)
                    push!(reqs, _mp_irecv!(v, r, _pic_sliced_tag(pr.pair, _PIC_TAG_RECORD1)))
                end
                for r in g2
                    v = _pic_sliced_record!(sc, _PIC_SLICED_RECORD)
                    push!(pr.recs_in, v)
                    push!(reqs, _mp_irecv!(v, r, _pic_sliced_tag(pr.pair, _PIC_TAG_RECORD2)))
                end
            end
        end
        _mp_wait_all(reqs, :wait_records)
        # --- the coordinator reduces and tells the owners --------------------------
        for pr in pairs
            if rank == pr.coord
                n1 = length(sb1.layout.groups[pr.i])
                pr.reduced = _pic_sliced_reduce(_pic_sliced_record!(sc, _PIC_SLICED_REDUCED),
                                                view(pr.recs_in, 1:n1),
                                                view(pr.recs_in, (n1 + 1):length(pr.recs_in)))
                for d in 1:2
                    push!(reqs, _mp_isend(pr.reduced, pr.owner[d], _pic_sliced_tag(pr.pair, _PIC_TAG_REDUCED + d - 1)))
                    messages += 1
                end
            end
            for d in 1:2
                rank == pr.owner[d] || continue
                v = _pic_sliced_record!(sc, _PIC_SLICED_REDUCED)
                pr.grids_out = Base.setindex(pr.grids_out, v, d)   # reuse the slot to hold the received reduced record for now
                push!(reqs, _mp_irecv!(v, pr.coord, _pic_sliced_tag(pr.pair, _PIC_TAG_REDUCED + d - 1)))
            end
        end
        _mp_wait_all(reqs, :wait_reduced)
        # --- the owners form the grids and tell the members ---------------------------
        for pr in pairs
            members = _pic_sliced_members(sb1.layout.groups[pr.i], sb2.layout.groups[pr.j])
            for d in 1:2
                if rank == pr.owner[d]
                    red = pr.grids_out[d]
                    param_source = d == 1 ? pr.param1 : pr.param2
                    param_field = d == 1 ? pr.param2 : pr.param1
                    g = _pic_sliced_record!(sc, _PIC_SLICED_GRIDS)
                    bad = red[61] > 0
                    grids = bad ? nothing : _pic_sliced_grids(solver, T, red, d, param_source, param_field)
                    if grids === nothing
                        g[1] = one(T)
                        pr.owned = Base.setindex(pr.owned, nothing, d)
                    else
                        source_grid0, field_grid0, sb, fb = grids
                        source_grid, field_grid, green_fft = _pic_slice_pair_green!(
                            workspace, solver, T, green_cache, (pr.i, pr.j, d),
                            source_grid0, field_grid0, sb, fb)
                        # the no-cache path returns the workspace's own table; keep a copy
                        green_fft === workspace.green_fft && (green_fft = copy(green_fft))
                        pr.owned = Base.setindex(pr.owned, (source_grid, field_grid, green_fft), d)
                        g[2] = T(source_grid.x0); g[3] = T(source_grid.y0)
                        g[4] = T(source_grid.width); g[5] = T(source_grid.height)
                        g[6] = T(field_grid.x0); g[7] = T(field_grid.y0)
                        g[8] = T(field_grid.width); g[9] = T(field_grid.height)
                    end
                    pr.grids_out = Base.setindex(pr.grids_out, g, d)
                    for r in members
                        push!(reqs, _mp_isend(g, r, _pic_sliced_tag(pr.pair, _PIC_TAG_GRIDS + d - 1)))
                        messages += 1
                    end
                end
                if pr.in1 || pr.in2
                    v = _pic_sliced_record!(sc, _PIC_SLICED_GRIDS)
                    pr.grids_in = Base.setindex(pr.grids_in, v, d)
                    push!(reqs, _mp_irecv!(v, pr.owner[d], _pic_sliced_tag(pr.pair, _PIC_TAG_GRIDS + d - 1)))
                end
            end
        end
        _mp_wait_all(reqs, :wait_grids)
        # --- stage 2: deposits to the owners, virtual positions -------------------------
        for pr in pairs
            if pr.in1 || pr.in2
                pr.bad = pr.grids_in[1][1] > 0 || pr.grids_in[2][1] > 0
            elseif pr.owned[1] === nothing && pr.owned[2] === nothing &&
                   (rank == pr.owner[1] || rank == pr.owner[2])
                pr.bad = true
            end
            pr.bad && (nbad += 1)
            pr.bad && continue
            for d in 1:2
                as_source = d == 1 ? pr.in1 : pr.in2
                as_source || continue
                part = d == 1 ? sb1.states[pr.i] : sb2.states[pr.j]
                param_source = d == 1 ? pr.param1 : pr.param2
                param_field = d == 1 ? pr.param2 : pr.param1
                source_grid = _pic_sliced_grid_from(pr.grids_in[d], 1)
                planes = [_pic_sliced_plane!(sc, nx, ny) for _ in 1:nplanes]
                _pic_sliced_deposit!(planes, solver, part, param_source, param_field,
                                     source_grid, workspace, T)
                for m in 1:nplanes
                    push!(reqs, _mp_isend(planes[m], pr.owner[d],
                                          _pic_sliced_tag(pr.pair, _PIC_TAG_PARTIAL + 3 * (d - 1) + m - 1)))
                    partials_sent += 1
                end
                # the source's virtual positions, before anything kicks this part
                _pic_sliced_virtual!(d == 1 ? pr.vx1 : pr.vx2, d == 1 ? pr.vy1 : pr.vy2,
                                     part, param_source, param_field, T)
            end
            for d in 1:2
                rank == pr.owner[d] || continue
                pr.owned[d] === nothing && continue
                src_group = d == 1 ? sb1.layout.groups[pr.i] : sb2.layout.groups[pr.j]
                perplane = pr.partials_in[d]
                for m in 1:nplanes
                    got = Matrix{T}[]
                    for r in src_group
                        plane = _pic_sliced_plane!(sc, nx, ny)
                        push!(got, plane)
                        push!(reqs, _mp_irecv!(plane, r, _pic_sliced_tag(pr.pair, _PIC_TAG_PARTIAL + 3 * (d - 1) + m - 1)))
                        partials_received += 1
                    end
                    push!(perplane, got)
                end
            end
        end
        _mp_wait_all(reqs, :wait_deposits)
        # --- the owners fold, solve and send the potentials -------------------------------
        for pr in pairs
            pr.bad && continue
            for d in 1:2
                rank == pr.owner[d] || continue
                owned = pr.owned[d]
                owned === nothing && continue
                _, _, green_fft = owned
                field_group = d == 1 ? sb2.layout.groups[pr.j] : sb1.layout.groups[pr.i]
                for m in 1:nplanes
                    phi = _pic_sliced_solve_plane!(_pic_sliced_plane!(sc, nx, ny),
                                                   pr.partials_in[d][m], green_fft,
                                                   workspace, nx, ny, T)
                    planes_solved += 1
                    push!(pr.potentials_out[d], phi)
                    for r in field_group
                        push!(reqs, _mp_isend(phi, r, _pic_sliced_tag(pr.pair, _PIC_TAG_POTENTIAL + 3 * (d - 1) + m - 1)))
                        potentials_sent += 1
                    end
                end
            end
            for d in 1:2
                as_field = d == 1 ? pr.in2 : pr.in1
                as_field || continue
                for m in 1:nplanes
                    phi = _pic_sliced_plane!(sc, nx, ny)
                    push!(pr.potentials_in[d], phi)
                    push!(reqs, _mp_irecv!(phi, pr.owner[d], _pic_sliced_tag(pr.pair, _PIC_TAG_POTENTIAL + 3 * (d - 1) + m - 1)))
                    potentials_received += 1
                end
            end
        end
        _mp_wait_all(reqs, :wait_potentials)
        # --- the field members take the gradient and kick ---------------------------------
        for pr in pairs
            pr.bad && continue
            for d in 1:2
                as_field = d == 1 ? pr.in2 : pr.in1
                as_field || continue
                field = d == 1 ? sb2.states[pr.j] : sb1.states[pr.i]
                param_source = d == 1 ? pr.param1 : pr.param2
                param_field = d == 1 ? pr.param2 : pr.param1
                kbb = d == 1 ? kbb2 : kbb1
                source_grid = _pic_sliced_grid_from(pr.grids_in[d], 1)
                field_grid = _pic_sliced_grid_from(pr.grids_in[d], 5)
                fields = [_pic_sliced_field!(sc, nx, ny) for _ in 1:nplanes]
                _pic_sliced_kick!(fields, solver, field, pr.potentials_in[d],
                                  source_grid, field_grid, param_source, param_field,
                                  kbb, workspace, T)
            end
        end
        # --- stage 3: the luminosity ------------------------------------------------------
        compute_luminosity || continue
        for pr in pairs
            pr.bad && continue
            g1 = sb1.layout.groups[pr.i]; g2 = sb2.layout.groups[pr.j]
            for (as, vx, vy, code) in ((pr.in1, pr.vx1, pr.vy1, _PIC_TAG_LUMEXT1),
                                       (pr.in2, pr.vx2, pr.vy2, _PIC_TAG_LUMEXT2))
                as || continue
                v = _pic_sliced_record!(sc, 4)
                v[1] = -_pic_extremum(minimum, vx, T(Inf)); v[2] = _pic_extremum(maximum, vx, T(-Inf))
                v[3] = -_pic_extremum(minimum, vy, T(Inf)); v[4] = _pic_extremum(maximum, vy, T(-Inf))
                code == _PIC_TAG_LUMEXT1 ? (pr.lumext = v) : nothing
                push!(reqs, _mp_isend(v, pr.coord, _pic_sliced_tag(pr.pair, code)))
                messages += 1
            end
            if rank == pr.coord
                for (g, code) in ((g1, _PIC_TAG_LUMEXT1), (g2, _PIC_TAG_LUMEXT2)), r in g
                    v = _pic_sliced_record!(sc, 4)
                    push!(pr.lumexts_in, v)
                    push!(reqs, _mp_irecv!(v, r, _pic_sliced_tag(pr.pair, code)))
                end
            end
        end
        _mp_wait_all(reqs, :wait_lum_extents)
        for pr in pairs
            pr.bad && continue
            members = _pic_sliced_members(sb1.layout.groups[pr.i], sb2.layout.groups[pr.j])
            if rank == pr.coord
                xmin = T(Inf); xmax = T(-Inf); ymin = T(Inf); ymax = T(-Inf)
                for v in pr.lumexts_in
                    xmin = min(xmin, -v[1]); xmax = max(xmax, v[2])
                    ymin = min(ymin, -v[3]); ymax = max(ymax, v[4])
                end
                mesh = _pic_luminosity_mesh(solver, T, xmin, xmax, ymin, ymax)
                mv = _pic_sliced_record!(sc, 6)
                mv[1] = mesh.xmin; mv[2] = mesh.ymin; mv[3] = mesh.hx; mv[4] = mesh.hy
                mv[5] = mesh.hxi; mv[6] = mesh.hyi
                pr.lummesh = mv
                for r in members
                    push!(reqs, _mp_isend(mv, r, _pic_sliced_tag(pr.pair, _PIC_TAG_LUMMESH)))
                    messages += 1
                end
            end
            if pr.in1 || pr.in2
                mv = _pic_sliced_record!(sc, 6)
                pr.lummesh = mv
                push!(reqs, _mp_irecv!(mv, pr.coord, _pic_sliced_tag(pr.pair, _PIC_TAG_LUMMESH)))
            end
        end
        _mp_wait_all(reqs, :wait_lum_mesh)
        method = _pic_luminosity_deposit_method(solver)
        for pr in pairs
            pr.bad && continue
            g1 = sb1.layout.groups[pr.i]; g2 = sb2.layout.groups[pr.j]
            mv = pr.lummesh
            for (as, vx, vy, code) in ((pr.in1, pr.vx1, pr.vy1, _PIC_TAG_LUMDEP1),
                                       (pr.in2, pr.vx2, pr.vy2, _PIC_TAG_LUMDEP2))
                as || continue
                q = _pic_sliced_lum!(sc, lnx + 1, lny + 1)
                fill!(q, zero(T))
                _pic_deposit!(q, method, vx, vy, mv[1], mv[2], mv[3], mv[4], lnx + 1, lny + 1)
                push!(reqs, _mp_isend(q, pr.coord, _pic_sliced_tag(pr.pair, code)))
                lum_sent += 1
            end
            if rank == pr.coord
                for (g, code, slot) in ((g1, _PIC_TAG_LUMDEP1, 1), (g2, _PIC_TAG_LUMDEP2, 2)), r in g
                    q = _pic_sliced_lum!(sc, lnx + 1, lny + 1)
                    push!(pr.lumdeps_in[slot], q)
                    push!(reqs, _mp_irecv!(q, r, _pic_sliced_tag(pr.pair, code)))
                    lum_received += 1
                end
            end
        end
        _mp_wait_all(reqs, :wait_lum_deposits)
        for pr in pairs
            pr.bad && continue
            rank == pr.coord || continue
            @inbounds lum_parts[pr.p] = _pic_sliced_overlap(
                _pic_sliced_lum!(sc, lnx + 1, lny + 1), _pic_sliced_lum!(sc, lnx + 1, lny + 1),
                pr.lumdeps_in[1], pr.lumdeps_in[2], pr.lummesh, klum, lnx, lny, T)
        end
    end
    _record_execution!(:pic_slice_exchange, CPUThreadsBackend,
                       (partials_sent=partials_sent, partials_received=partials_received,
                        potentials_sent=potentials_sent, potentials_received=potentials_received,
                        lum_sent=lum_sent, lum_received=lum_received, messages=messages,
                        pairs_coordinated=pairs_coordinated, planes_solved=planes_solved,
                        # A batch is a barrier here: nothing of the next batch
                        # starts before this one is through.
                        cross_batch_starts=0, batches_in_flight_max=1,
                        max_in_flight=maximum(length, batches; init=0),
                        wait_calls=0, wait_ns=0, scans=0, high_planes=0,
                        schedule=:batched, ranks=P))
    return nbad
end

# --- the dataflow loop (multi-process step 4e) ---------------------------------
#
# The batched loop above walks every pair of a wavefront batch through the
# same stage at the same time, so a rank waits at each stage for the slowest
# member of the batch and idles whenever its own pairs are done. Nothing in
# the physics asks for that: a pair depends only on its two slices' PREVIOUS
# pairs, so each rank can instead run an event loop -- scan its pairs in the
# collision order, run every stage whose receives have arrived, and block on
# the union of what is outstanding only when a whole scan ran nothing.
#
# The stages, their messages, their tags and every number they compute are the
# batched loop's (the leaves above are shared), so the two loops are
# bit-identical; `batch_mode = :sequential` keeps the batched loop and the
# launcher child pins the two against each other at every rank count.
#
# Three rules make it safe:
#
#  * **The gate** is the collision order, not index arithmetic. A pair may
#    start once the pair BEFORE it on each of its slices (among the non-empty
#    pairs, in `order`) has kicked. For ascending slice centres the collision
#    time `-(c1+c2)/2` puts the largest `j` first, so slice `i`'s predecessor
#    of `(i, j)` is `(i, j+1)`, not `(i, j-1)` -- the 4e review's finding, and
#    the reason this is derived from `order` and never computed from indices.
#  * **A send buffer belongs to its send** until MPI says the send completed:
#    a pair returns its buffers to the free lists only after `_mp_test_all` on
#    its send list is true. Under the batched loop the per-stage `_mp_wait_all`
#    covered that; here nothing else does, and a plane reused early would
#    corrupt a peer's charge silently.
#  * **A pair that meets a non-finite extent releases its slices anyway** --
#    it marks itself done without kicking, exactly as the batched loop skips
#    it, so its successors run and the collide reaches the count that makes
#    every rank throw. Under dataflow a bad pair that simply stopped would
#    hang its slices instead.

"""
Which loop the slice-aligned collide runs, for measurement and for the pin
that holds the two to the same bits: `:auto` (the schedule decides --
`:wavefront` runs the dataflow loop, `:sequential` the batched one),
`:dataflow`, or `:batched`. NOT a solver keyword: one keyword means one thing
everywhere, and this selects an implementation of the same physics, not a
configuration of it.
"""
const _PIC_SLICED_LOOP = Base.ScopedValues.ScopedValue{Symbol}(:auto)

const _PIC_DF_ORIGINS = 1
const _PIC_DF_RECORDS = 2
const _PIC_DF_REDUCE = 3
const _PIC_DF_GRIDS = 4
const _PIC_DF_DEPOSIT = 5
const _PIC_DF_SOLVE = 6
const _PIC_DF_KICK = 7
const _PIC_DF_LUMEXT = 8
const _PIC_DF_LUMMESH = 9
const _PIC_DF_LUMDEP = 10
const _PIC_DF_LUMFOLD = 11
const _PIC_DF_DONE = 12
const _PIC_DF_STAGE_NAMES = (:wait_origins, :wait_records, :wait_reduced, :wait_grids,
                             :wait_deposits, :wait_solve, :wait_potentials, :wait_lum_extents,
                             :wait_lum_mesh, :wait_lum_deposits, :wait_lum_fold, :wait_done)
# The relay stages: a rank serves these before its own deposits and kicks, so
# the pairs waiting on it are not held behind a long stage of its own.
const _PIC_DF_RELAY = (_PIC_DF_REDUCE, _PIC_DF_GRIDS, _PIC_DF_SOLVE, _PIC_DF_LUMMESH,
                       _PIC_DF_LUMFOLD)
# The origin's codes live INSIDE the pair's tag space (the 4e review: a
# separate band collided with the pair band from a few hundred pairs on).
const _PIC_TAG_ORIGIN1 = 24
const _PIC_TAG_ORIGIN2 = 25
const _PIC_TAG_CODES = 32

"""Free lists for the dataflow loop, by shape: a pair takes what it needs and
gives it all back when its receives are consumed and its sends complete."""
mutable struct _PICDataflowPool{T}
    planes::Vector{Matrix{T}}
    lums::Vector{Matrix{T}}
    fields::Vector{_PICFieldWorkspace{T}}
    recs::Dict{Int,Vector{Vector{T}}}
    nx::Int
    ny::Int
    lnx::Int
    lny::Int
    live_planes::Int
    high_planes::Int
end
_PICDataflowPool{T}(nx, ny, lnx, lny) where {T} =
    _PICDataflowPool{T}(Matrix{T}[], Matrix{T}[], _PICFieldWorkspace{T}[],
                        Dict{Int,Vector{Vector{T}}}(), nx, ny, lnx, lny, 0, 0)

function _pic_df_pool(::Type{T}, holder::Base.RefValue{Any}, nx, ny, lnx, lny) where {T}
    pool = holder[]
    if pool isa _PICDataflowPool{T} && pool.nx == nx && pool.ny == ny &&
       pool.lnx == lnx && pool.lny == lny
        return pool
    end
    fresh = _PICDataflowPool{T}(nx, ny, lnx, lny)
    holder[] = fresh
    return fresh
end

function _pic_df_plane!(pool::_PICDataflowPool{T}) where {T}
    pool.live_planes += 1
    pool.high_planes = max(pool.high_planes, pool.live_planes)
    isempty(pool.planes) && return zeros(T, pool.nx, pool.ny)
    return pop!(pool.planes)
end
_pic_df_give_plane!(pool::_PICDataflowPool{T}, A::Matrix{T}) where {T} =
    (pool.live_planes -= 1; push!(pool.planes, A); nothing)
_pic_df_lum!(pool::_PICDataflowPool{T}) where {T} =
    isempty(pool.lums) ? zeros(T, pool.lnx + 1, pool.lny + 1) : pop!(pool.lums)
_pic_df_field!(pool::_PICDataflowPool{T}) where {T} =
    isempty(pool.fields) ?
        _PICFieldWorkspace(zeros(T, 0, 0), zeros(T, pool.nx, pool.ny), zeros(T, pool.nx, pool.ny)) :
        pop!(pool.fields)
function _pic_df_rec!(pool::_PICDataflowPool{T}, n::Int) where {T}
    free = get!(() -> Vector{T}[], pool.recs, n)
    v = isempty(free) ? zeros(T, n) : pop!(free)
    fill!(v, zero(T))
    return v
end

"""What the dataflow loop counted, in a struct because its event loop reads
these outside the closure that writes them."""
mutable struct _PICDataflowCounters
    nbad::Int
    partials_sent::Int
    partials_received::Int
    potentials_sent::Int
    potentials_received::Int
    lum_sent::Int
    lum_received::Int
    messages::Int
    pairs_coordinated::Int
    planes_solved::Int
    cross_batch_starts::Int
    batches_in_flight_max::Int
    max_in_flight::Int
    inflight::Int
end
_PICDataflowCounters() = _PICDataflowCounters(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

"""One pair on this rank under the dataflow loop: its roles, its gate, the
stage it will run next, its per-stage receives, its outstanding sends, and
every buffer it holds."""
mutable struct _PICDataflowPair{T,R}
    p::Int
    i::Int
    j::Int
    pair::Int
    batch::Int
    in1::Bool
    in2::Bool
    coord::Int
    owner::NTuple{2,Int}
    param1::NamedTuple{(:weight, :lb, :center, :rb),NTuple{4,T}}
    param2::NamedTuple{(:weight, :lb, :center, :rb),NTuple{4,T}}
    gate1::Int
    gate2::Int
    stage::Int
    bad::Bool
    retired::Bool
    recv::Vector{Vector{R}}
    sends::Vector{R}
    origin1::Union{Nothing,Vector{T}}
    origin2::Union{Nothing,Vector{T}}
    rec1::Union{Nothing,Vector{T}}
    rec2::Union{Nothing,Vector{T}}
    recs_in::Vector{Vector{T}}
    reduced::Union{Nothing,Vector{T}}
    reduced_in::Vector{Union{Nothing,Vector{T}}}
    grids_out::Vector{Union{Nothing,Vector{T}}}
    grids_in::Vector{Union{Nothing,Vector{T}}}
    owned::Vector{Any}
    partials_in::NTuple{2,Vector{Vector{Matrix{T}}}}
    potentials_in::NTuple{2,Vector{Matrix{T}}}
    vx1::Vector{T}
    vy1::Vector{T}
    vx2::Vector{T}
    vy2::Vector{T}
    lumexts_in::Vector{Vector{T}}
    lummesh::Union{Nothing,Vector{T}}
    lumdeps_in::NTuple{2,Vector{Matrix{T}}}
    took_planes::Vector{Matrix{T}}
    took_lums::Vector{Matrix{T}}
    took_fields::Vector{_PICFieldWorkspace{T}}
    took_recs::Vector{Vector{T}}
end

function _pic_df_pair(::Type{T}, ::Type{R}, p, i, j, ns2, batch, in1, in2, coord, owner,
                      param1, param2) where {T,R}
    return _PICDataflowPair{T,R}(
        p, i, j, (i - 1) * ns2 + j, batch, in1, in2, coord, owner, param1, param2,
        0, 0, _PIC_DF_ORIGINS, false, false,
        [R[] for _ in 1:_PIC_DF_DONE], R[],
        nothing, nothing, nothing, nothing, Vector{T}[], nothing,
        Union{Nothing,Vector{T}}[nothing, nothing],
        Union{Nothing,Vector{T}}[nothing, nothing],
        Union{Nothing,Vector{T}}[nothing, nothing],
        Any[nothing, nothing],
        (Vector{Matrix{T}}[], Vector{Matrix{T}}[]), (Matrix{T}[], Matrix{T}[]),
        T[], T[], T[], T[], Vector{T}[], nothing, (Matrix{T}[], Matrix{T}[]),
        Matrix{T}[], Matrix{T}[], _PICFieldWorkspace{T}[], Vector{T}[])
end

_pic_df_take_rec!(pr::_PICDataflowPair{T}, pool, n::Int) where {T} =
    (v = _pic_df_rec!(pool, n); push!(pr.took_recs, v); v)
_pic_df_take_plane!(pr::_PICDataflowPair{T}, pool) where {T} =
    (A = _pic_df_plane!(pool); push!(pr.took_planes, A); A)
_pic_df_take_lum!(pr::_PICDataflowPair{T}, pool) where {T} =
    (A = _pic_df_lum!(pool); push!(pr.took_lums, A); A)
_pic_df_take_field!(pr::_PICDataflowPair{T}, pool) where {T} =
    (f = _pic_df_field!(pool); push!(pr.took_fields, f); f)

"""Give a finished pair's buffers back. Called only once its sends have
completed, so no buffer is handed out while MPI may still be reading it."""
function _pic_df_retire!(pr::_PICDataflowPair{T}, pool::_PICDataflowPool{T}) where {T}
    for A in pr.took_planes
        _pic_df_give_plane!(pool, A)
    end
    append!(pool.lums, pr.took_lums)
    append!(pool.fields, pr.took_fields)
    for v in pr.took_recs
        push!(get!(() -> Vector{T}[], pool.recs, length(v)), v)
    end
    empty!(pr.took_planes); empty!(pr.took_lums); empty!(pr.took_fields); empty!(pr.took_recs)
    pr.retired = true
    return nothing
end

"""
For each slice of each beam, the previous non-empty pair in the collision
order -- the pair whose kick must land before the next one reads the slice.
Returned as two maps from pair position to pair position (0 = none).
"""
function _pic_df_predecessors(order, pair_pos, counts1::Vector{Int}, counts2::Vector{Int})
    prev1 = Dict{Int,Int}()
    prev2 = Dict{Int,Int}()
    last1 = zeros(Int, length(counts1))
    last2 = zeros(Int, length(counts2))
    for entry in order
        i = Int(entry[2]); j = Int(entry[3])
        (counts1[i] == 0 || counts2[j] == 0) && continue
        p = pair_pos[(i, j)]
        prev1[p] = last1[i]
        prev2[p] = last2[j]
        last1[i] = p
        last2[j] = p
    end
    return prev1, prev2
end

"""
The slice-aligned collide under the dataflow loop. Same stages, same
arithmetic and same messages as `_pic_collide_sliced!`; only when a rank runs
them differs.
"""
function _pic_collide_dataflow!(sb1::_PICSlicedBeam{T}, sb2::_PICSlicedBeam{T}, order,
                                pair_pos, batch_of, lum_parts, ran, solver::PICPoissonSolver,
                                slices1, slices2, workspace::_PICCPUWorkspace, green_cache,
                                pool::_PICDataflowPool{T}, kbb1, kbb2, klum,
                                compute_luminosity::Bool) where {T}
    P = _mp_nranks()
    rank = _mp_rank()
    ns1 = length(sb1.layout.counts)
    ns2 = length(sb2.layout.counts)
    nx, ny = solver.grid
    lnx, lny = _pic_luminosity_grid(solver)
    nplanes = _pic_quadratic_slice(solver) ? 3 : 2
    sigma = Symbol(solver.grid_extent) === :sigma
    R = eltype(_mp_requests())
    prev1, prev2 = _pic_df_predecessors(order, pair_pos, sb1.layout.counts, sb2.layout.counts)
    # This rank's pairs, in the collision order, with the position of each in
    # this list so a gate is a local index.
    pairs = _PICDataflowPair{T,R}[]
    index_of = Dict{Int,Int}()
    for entry in order
        i = Int(entry[2]); j = Int(entry[3])
        p = pair_pos[(i, j)]
        if sb1.layout.counts[i] == 0 || sb2.layout.counts[j] == 0
            ran[p] = false
            continue
        end
        ran[p] = true
        g1 = sb1.layout.groups[i]; g2 = sb2.layout.groups[j]
        in1 = rank in g1; in2 = rank in g2
        coord = first(g1)
        b, q = batch_of[p]      # the wavefront batch, and the position that deals its owners
        owner = ((2 * (q - 1)) % P, (2 * (q - 1) + 1) % P)
        (in1 || in2 || rank == coord || rank == owner[1] || rank == owner[2]) || continue
        param1 = (weight=T(slices1.weight[i]), lb=T(slices1.boundary[i]),
                  center=T(slices1.center[i]), rb=T(slices1.boundary[i + 1]))
        param2 = (weight=T(slices2.weight[j]), lb=T(slices2.boundary[j]),
                  center=T(slices2.center[j]), rb=T(slices2.boundary[j + 1]))
        push!(pairs, _pic_df_pair(T, R, p, i, j, ns2, b, in1, in2, coord, owner, param1, param2))
        index_of[p] = length(pairs)
    end
    for pr in pairs
        pr.in1 && (pr.gate1 = get(index_of, get(prev1, pr.p, 0), 0))
        pr.in2 && (pr.gate2 = get(index_of, get(prev2, pr.p, 0), 0))
    end
    npairs_all = ns1 * ns2
    _mp_check_tag_bound(_pic_sliced_tag(npairs_all, _PIC_TAG_CODES))
    # In a struct, not as locals: `run_stage!` below is a closure and every
    # one of these is assigned inside it and read outside, which makes each a
    # `Core.Box` (the permanent lowered-code sweep names them).
    c = _PICDataflowCounters()
    wait_calls = 0; wait_ns = 0; scans = 0
    live = Set{Int}()          # batch indices of pairs in flight on this rank

    ready(pr) = _mp_test_all(pr.recv[pr.stage])
    gated(pr) = (pr.gate1 != 0 && pairs[pr.gate1].stage <= _PIC_DF_KICK) ||
                (pr.gate2 != 0 && pairs[pr.gate2].stage <= _PIC_DF_KICK)

    function run_stage!(pr)
        s = pr.stage
        g1 = sb1.layout.groups[pr.i]; g2 = sb2.layout.groups[pr.j]
        if s == _PIC_DF_ORIGINS
            # A pair enters flight here: the counters read the frontier.
            if !isempty(live) && !(pr.batch in live)
                c.cross_batch_starts += 1
            end
            push!(live, pr.batch)
            c.inflight += 1
            c.max_in_flight = max(c.max_in_flight, c.inflight)
            c.batches_in_flight_max = max(c.batches_in_flight_max, length(live))
            if sigma
                for (sb, code, s_idx, in_group) in ((sb1, _PIC_TAG_ORIGIN1, pr.i, pr.in1),
                                                    (sb2, _PIC_TAG_ORIGIN2, pr.j, pr.in2))
                    in_group || continue
                    group = sb.layout.groups[s_idx]
                    v = _pic_df_take_rec!(pr, pool, 5)
                    code == _PIC_TAG_ORIGIN1 ? (pr.origin1 = v) : (pr.origin2 = v)
                    st = sb.states[s_idx]
                    if rank == first(group)
                        if !isempty(st.x)
                            v[1] = st.x[1]; v[2] = st.px[1]; v[3] = st.y[1]
                            v[4] = st.py[1]; v[5] = st.z[1]
                        end
                        for r in group
                            r == rank && continue
                            push!(pr.sends, _mp_isend(v, r, _pic_sliced_tag(pr.pair, code)))
                            c.messages += 1
                        end
                    else
                        push!(pr.recv[_PIC_DF_RECORDS],
                              _mp_irecv!(v, first(group), _pic_sliced_tag(pr.pair, code)))
                    end
                end
            end
            pr.stage = _PIC_DF_RECORDS
        elseif s == _PIC_DF_RECORDS
            if pr.in1
                pr.rec1 = _pic_sliced_record(_pic_df_take_rec!(pr, pool, _PIC_SLICED_RECORD),
                                             solver, sb1.states[pr.i], pr.param1, pr.param2,
                                             sigma ? pr.origin1 : nothing)
                push!(pr.sends, _mp_isend(pr.rec1, pr.coord,
                                          _pic_sliced_tag(pr.pair, _PIC_TAG_RECORD1)))
                c.messages += 1
            end
            if pr.in2
                pr.rec2 = _pic_sliced_record(_pic_df_take_rec!(pr, pool, _PIC_SLICED_RECORD),
                                             solver, sb2.states[pr.j], pr.param2, pr.param1,
                                             sigma ? pr.origin2 : nothing)
                push!(pr.sends, _mp_isend(pr.rec2, pr.coord,
                                          _pic_sliced_tag(pr.pair, _PIC_TAG_RECORD2)))
                c.messages += 1
            end
            if rank == pr.coord
                c.pairs_coordinated += 1
                for r in g1
                    v = _pic_df_take_rec!(pr, pool, _PIC_SLICED_RECORD)
                    push!(pr.recs_in, v)
                    push!(pr.recv[_PIC_DF_REDUCE],
                          _mp_irecv!(v, r, _pic_sliced_tag(pr.pair, _PIC_TAG_RECORD1)))
                end
                for r in g2
                    v = _pic_df_take_rec!(pr, pool, _PIC_SLICED_RECORD)
                    push!(pr.recs_in, v)
                    push!(pr.recv[_PIC_DF_REDUCE],
                          _mp_irecv!(v, r, _pic_sliced_tag(pr.pair, _PIC_TAG_RECORD2)))
                end
            end
            for d in 1:2
                if rank == pr.owner[d]
                    v = _pic_df_take_rec!(pr, pool, _PIC_SLICED_REDUCED)
                    pr.reduced_in[d] = v
                    push!(pr.recv[_PIC_DF_GRIDS],
                          _mp_irecv!(v, pr.coord, _pic_sliced_tag(pr.pair, _PIC_TAG_REDUCED + d - 1)))
                end
                if pr.in1 || pr.in2
                    v = _pic_df_take_rec!(pr, pool, _PIC_SLICED_GRIDS)
                    pr.grids_in[d] = v
                    push!(pr.recv[_PIC_DF_DEPOSIT],
                          _mp_irecv!(v, pr.owner[d], _pic_sliced_tag(pr.pair, _PIC_TAG_GRIDS + d - 1)))
                end
            end
            pr.stage = _PIC_DF_REDUCE
        elseif s == _PIC_DF_REDUCE
            if rank == pr.coord
                n1 = length(g1)
                pr.reduced = _pic_sliced_reduce(
                    _pic_df_take_rec!(pr, pool, _PIC_SLICED_REDUCED), view(pr.recs_in, 1:n1),
                    view(pr.recs_in, (n1 + 1):length(pr.recs_in)))
                for d in 1:2
                    push!(pr.sends, _mp_isend(pr.reduced, pr.owner[d],
                                              _pic_sliced_tag(pr.pair, _PIC_TAG_REDUCED + d - 1)))
                    c.messages += 1
                end
            end
            pr.stage = _PIC_DF_GRIDS
        elseif s == _PIC_DF_GRIDS
            members = _pic_sliced_members(g1, g2)
            for d in 1:2
                rank == pr.owner[d] || continue
                red = pr.reduced_in[d]
                param_source = d == 1 ? pr.param1 : pr.param2
                param_field = d == 1 ? pr.param2 : pr.param1
                g = _pic_df_take_rec!(pr, pool, _PIC_SLICED_GRIDS)
                grids = red[61] > 0 ? nothing :
                        _pic_sliced_grids(solver, T, red, d, param_source, param_field)
                if grids === nothing
                    g[1] = one(T)
                    pr.owned[d] = nothing
                else
                    source_grid0, field_grid0, sbnd, fbnd = grids
                    source_grid, field_grid, green_fft = _pic_slice_pair_green!(
                        workspace, solver, T, green_cache, (pr.i, pr.j, d),
                        source_grid0, field_grid0, sbnd, fbnd)
                    green_fft === workspace.green_fft && (green_fft = copy(green_fft))
                    pr.owned[d] = (source_grid, field_grid, green_fft)
                    g[2] = T(source_grid.x0); g[3] = T(source_grid.y0)
                    g[4] = T(source_grid.width); g[5] = T(source_grid.height)
                    g[6] = T(field_grid.x0); g[7] = T(field_grid.y0)
                    g[8] = T(field_grid.width); g[9] = T(field_grid.height)
                end
                pr.grids_out[d] = g
                for r in members
                    push!(pr.sends, _mp_isend(g, r, _pic_sliced_tag(pr.pair, _PIC_TAG_GRIDS + d - 1)))
                    c.messages += 1
                end
                # The source group's partials, posted with the grids that ask
                # for them: a stage early, so the charge has somewhere to land
                # the moment it is deposited.
                if pr.owned[d] !== nothing
                    src_group = d == 1 ? g1 : g2
                    for m in 1:nplanes
                        got = Matrix{T}[]
                        for r in src_group
                            plane = _pic_df_take_plane!(pr, pool)
                            push!(got, plane)
                            push!(pr.recv[_PIC_DF_SOLVE],
                                  _mp_irecv!(plane, r, _pic_sliced_tag(
                                      pr.pair, _PIC_TAG_PARTIAL + 3 * (d - 1) + m - 1)))
                            c.partials_received += 1
                        end
                        push!(pr.partials_in[d], got)
                    end
                end
            end
            pr.stage = _PIC_DF_DEPOSIT
        elseif s == _PIC_DF_DEPOSIT
            if pr.in1 || pr.in2
                pr.bad = pr.grids_in[1][1] > 0 || pr.grids_in[2][1] > 0
            elseif pr.owned[1] === nothing && pr.owned[2] === nothing
                pr.bad = true
            end
            if pr.bad
                # Release the slices without kicking (the batched loop's skip),
                # so the successors run and the collide reaches its count.
                c.nbad += 1
                pr.stage = _PIC_DF_DONE
                c.inflight -= 1
                return true
            end
            for d in 1:2
                as_source = d == 1 ? pr.in1 : pr.in2
                as_source || continue
                part = d == 1 ? sb1.states[pr.i] : sb2.states[pr.j]
                param_source = d == 1 ? pr.param1 : pr.param2
                param_field = d == 1 ? pr.param2 : pr.param1
                source_grid = _pic_sliced_grid_from(pr.grids_in[d], 1)
                planes = [_pic_df_take_plane!(pr, pool) for _ in 1:nplanes]
                _pic_sliced_deposit!(planes, solver, part, param_source, param_field,
                                     source_grid, workspace, T)
                for m in 1:nplanes
                    push!(pr.sends, _mp_isend(planes[m], pr.owner[d], _pic_sliced_tag(
                        pr.pair, _PIC_TAG_PARTIAL + 3 * (d - 1) + m - 1)))
                    c.partials_sent += 1
                end
                _pic_sliced_virtual!(d == 1 ? pr.vx1 : pr.vx2, d == 1 ? pr.vy1 : pr.vy2,
                                     part, param_source, param_field, T)
            end
            for d in 1:2
                as_field = d == 1 ? pr.in2 : pr.in1
                as_field || continue
                for m in 1:nplanes
                    phi = _pic_df_take_plane!(pr, pool)
                    push!(pr.potentials_in[d], phi)
                    push!(pr.recv[_PIC_DF_KICK], _mp_irecv!(phi, pr.owner[d], _pic_sliced_tag(
                        pr.pair, _PIC_TAG_POTENTIAL + 3 * (d - 1) + m - 1)))
                    c.potentials_received += 1
                end
            end
            pr.stage = _PIC_DF_SOLVE
        elseif s == _PIC_DF_SOLVE
            for d in 1:2
                rank == pr.owner[d] || continue
                owned = pr.owned[d]
                owned === nothing && continue
                _, _, green_fft = owned
                field_group = d == 1 ? g2 : g1
                for m in 1:nplanes
                    phi = _pic_sliced_solve_plane!(_pic_df_take_plane!(pr, pool),
                                                   pr.partials_in[d][m], green_fft,
                                                   workspace, nx, ny, T)
                    c.planes_solved += 1
                    for r in field_group
                        push!(pr.sends, _mp_isend(phi, r, _pic_sliced_tag(
                            pr.pair, _PIC_TAG_POTENTIAL + 3 * (d - 1) + m - 1)))
                        c.potentials_sent += 1
                    end
                end
            end
            pr.stage = _PIC_DF_KICK
        elseif s == _PIC_DF_KICK
            for d in 1:2
                as_field = d == 1 ? pr.in2 : pr.in1
                as_field || continue
                field = d == 1 ? sb2.states[pr.j] : sb1.states[pr.i]
                param_source = d == 1 ? pr.param1 : pr.param2
                param_field = d == 1 ? pr.param2 : pr.param1
                kbb = d == 1 ? kbb2 : kbb1
                source_grid = _pic_sliced_grid_from(pr.grids_in[d], 1)
                field_grid = _pic_sliced_grid_from(pr.grids_in[d], 5)
                fields = [_pic_df_take_field!(pr, pool) for _ in 1:nplanes]
                _pic_sliced_kick!(fields, solver, field, pr.potentials_in[d],
                                  source_grid, field_grid, param_source, param_field,
                                  kbb, workspace, T)
            end
            pr.stage = compute_luminosity ? _PIC_DF_LUMEXT : _PIC_DF_DONE
            pr.stage == _PIC_DF_DONE && (c.inflight -= 1)
        elseif s == _PIC_DF_LUMEXT
            for (as, vx, vy, code) in ((pr.in1, pr.vx1, pr.vy1, _PIC_TAG_LUMEXT1),
                                       (pr.in2, pr.vx2, pr.vy2, _PIC_TAG_LUMEXT2))
                as || continue
                v = _pic_df_take_rec!(pr, pool, 4)
                v[1] = -_pic_extremum(minimum, vx, T(Inf)); v[2] = _pic_extremum(maximum, vx, T(-Inf))
                v[3] = -_pic_extremum(minimum, vy, T(Inf)); v[4] = _pic_extremum(maximum, vy, T(-Inf))
                push!(pr.sends, _mp_isend(v, pr.coord, _pic_sliced_tag(pr.pair, code)))
                c.messages += 1
            end
            if rank == pr.coord
                for (g, code) in ((g1, _PIC_TAG_LUMEXT1), (g2, _PIC_TAG_LUMEXT2)), r in g
                    v = _pic_df_take_rec!(pr, pool, 4)
                    push!(pr.lumexts_in, v)
                    push!(pr.recv[_PIC_DF_LUMMESH],
                          _mp_irecv!(v, r, _pic_sliced_tag(pr.pair, code)))
                end
            end
            if pr.in1 || pr.in2
                mv = _pic_df_take_rec!(pr, pool, 6)
                pr.lummesh = mv
                push!(pr.recv[_PIC_DF_LUMDEP],
                      _mp_irecv!(mv, pr.coord, _pic_sliced_tag(pr.pair, _PIC_TAG_LUMMESH)))
            end
            pr.stage = _PIC_DF_LUMMESH
        elseif s == _PIC_DF_LUMMESH
            if rank == pr.coord
                xmin = T(Inf); xmax = T(-Inf); ymin = T(Inf); ymax = T(-Inf)
                for v in pr.lumexts_in
                    xmin = min(xmin, -v[1]); xmax = max(xmax, v[2])
                    ymin = min(ymin, -v[3]); ymax = max(ymax, v[4])
                end
                mesh = _pic_luminosity_mesh(solver, T, xmin, xmax, ymin, ymax)
                mv = _pic_df_take_rec!(pr, pool, 6)
                mv[1] = mesh.xmin; mv[2] = mesh.ymin; mv[3] = mesh.hx; mv[4] = mesh.hy
                mv[5] = mesh.hxi; mv[6] = mesh.hyi
                rank in g1 || rank in g2 || (pr.lummesh = mv)
                for r in _pic_sliced_members(g1, g2)
                    push!(pr.sends, _mp_isend(mv, r, _pic_sliced_tag(pr.pair, _PIC_TAG_LUMMESH)))
                    c.messages += 1
                end
                for (g, code, slot) in ((g1, _PIC_TAG_LUMDEP1, 1), (g2, _PIC_TAG_LUMDEP2, 2)), r in g
                    q = _pic_df_take_lum!(pr, pool)
                    push!(pr.lumdeps_in[slot], q)
                    push!(pr.recv[_PIC_DF_LUMFOLD],
                          _mp_irecv!(q, r, _pic_sliced_tag(pr.pair, code)))
                    c.lum_received += 1
                end
            end
            pr.stage = _PIC_DF_LUMDEP
        elseif s == _PIC_DF_LUMDEP
            method = _pic_luminosity_deposit_method(solver)
            mv = pr.lummesh
            for (as, vx, vy, code) in ((pr.in1, pr.vx1, pr.vy1, _PIC_TAG_LUMDEP1),
                                       (pr.in2, pr.vx2, pr.vy2, _PIC_TAG_LUMDEP2))
                as || continue
                q = _pic_df_take_lum!(pr, pool)
                fill!(q, zero(T))
                _pic_deposit!(q, method, vx, vy, mv[1], mv[2], mv[3], mv[4], lnx + 1, lny + 1)
                push!(pr.sends, _mp_isend(q, pr.coord, _pic_sliced_tag(pr.pair, code)))
                c.lum_sent += 1
            end
            pr.stage = _PIC_DF_LUMFOLD
        elseif s == _PIC_DF_LUMFOLD
            if rank == pr.coord
                @inbounds lum_parts[pr.p] = _pic_sliced_overlap(
                    _pic_df_take_lum!(pr, pool), _pic_df_take_lum!(pr, pool),
                    pr.lumdeps_in[1], pr.lumdeps_in[2], pr.lummesh, klum, lnx, lny, T)
            end
            pr.stage = _PIC_DF_DONE
            c.inflight -= 1
        end
        return true
    end

    remaining = length(pairs)
    while remaining > 0
        scans += 1
        ran_any = false
        # Relay duties first (a coordinator's fold, an owner's grids and
        # solves, the luminosity folds), then this rank's own particle work:
        # a pair waiting on this rank is not held behind a long deposit.
        for relay in (true, false)
            for pr in pairs
                pr.stage == _PIC_DF_DONE && continue
                (pr.stage in _PIC_DF_RELAY) == relay || continue
                pr.stage == _PIC_DF_ORIGINS && gated(pr) && continue
                ready(pr) || continue
                run_stage!(pr)
                ran_any = true
                pr.stage == _PIC_DF_DONE && (remaining -= 1)
            end
        end
        # Buffers go back only once the sends that read them have completed.
        for pr in pairs
            (pr.stage == _PIC_DF_DONE && !pr.retired && _mp_test_all(pr.sends)) &&
                _pic_df_retire!(pr, pool)
        end
        ran_any && continue
        remaining == 0 && break
        # Nothing ran: block on everything outstanding, whichever arrives.
        union = _mp_requests()
        stage = _PIC_DF_DONE
        for pr in pairs
            pr.stage == _PIC_DF_DONE && continue
            isempty(pr.recv[pr.stage]) && continue   # gated, not waiting on a message
            append!(union, pr.recv[pr.stage])
            stage = min(stage, pr.stage)
        end
        isempty(union) && error(
            "the PIC dataflow loop has $(remaining) pair(s) to run and nothing outstanding: " *
            "the first is pair $(first(pr.p for pr in pairs if pr.stage != _PIC_DF_DONE)) " *
            "at stage $(_PIC_DF_STAGE_NAMES[first(pr.stage for pr in pairs if pr.stage != _PIC_DF_DONE)])")
        t0 = time_ns()
        _mp_wait_any(union, _PIC_DF_STAGE_NAMES[stage])
        wait_ns += Int(time_ns() - t0)
        wait_calls += 1
    end
    # Every send drained before the buffers are handed back to the next collide.
    for pr in pairs
        pr.retired || (_mp_wait_all(pr.sends, :wait_sends); _pic_df_retire!(pr, pool))
    end
    _record_execution!(:pic_slice_exchange, CPUThreadsBackend,
                       (partials_sent=c.partials_sent, partials_received=c.partials_received,
                        potentials_sent=c.potentials_sent, potentials_received=c.potentials_received,
                        lum_sent=c.lum_sent, lum_received=c.lum_received, messages=c.messages,
                        pairs_coordinated=c.pairs_coordinated, planes_solved=c.planes_solved,
                        cross_batch_starts=c.cross_batch_starts,
                        batches_in_flight_max=c.batches_in_flight_max,
                        max_in_flight=c.max_in_flight, wait_calls=wait_calls,
                        wait_ns=wait_ns, scans=scans, high_planes=pool.high_planes,
                        schedule=:dataflow, ranks=P))
    return c.nbad
end
