# The batched exchange of the divided PIC collide (multi-process step 4c,
# performance phase).
#
# Divided, under the wavefront schedule on the `:slice_pair` mesh, a batch's
# pairs are conflict-free, so every pair of a batch can reach each collective
# TOGETHER, and the planes can be solved ONCE rather than on every rank. Per
# batch: one exchange of every pair's mesh extents; every pair deposits the
# nx x ny interior of its planes (the padding of the FFT plane is zero on
# every rank, so it is not sent); a reduce-scatter hands each plane's partial
# deposits to ONE rank, its owner, which solves it; an all-gather of the
# potentials -- nx x ny, a quarter of the padded plane -- gives every rank
# every plane, and each rank takes the field gradient itself; then one
# exchange of the luminosity meshes' extents, a reduce-scatter of the
# luminosity deposits to owners who form the overlap sums, and an all-gather
# of those scalars. Seven collectives per batch (eight under
# `grid_extent = :sigma`) where the per-pair exchange issued about
# twenty-four per pair, the FFT work divided by the rank count, and the
# traffic per rank a third of the all-summed padded planes'. With no
# collective inside a pair, the pairs of a batch run on the worker pool again
# (the per-pair exchange had to run them one at a time on the main thread,
# MPI being `:funneled`).
#
# The arithmetic is the per-pair path's, stage by stage, in the same order per
# particle and per grid element: the same loops compute the extents (the
# field's from `x + s*px` without writing it, the in-place drift moving to the
# stage that kicks -- the same two operations on the same two numbers), the
# same deposits write the planes, the owner's fold of the partials is the
# all-sum's sum per element in rank order (the padding sums zeros to zero),
# the owner's solve is the solve any rank made, every rank's gradient of the
# same potential is the same field, and the kicks read what they always
# read. The launcher child pins the two divided schedules to the same bits at
# every rank count it runs.
#
# What stays on the per-pair exchange: `interaction_grid = :node` (its planes
# come from prebuilt node meshes and it interpolates a third, longitudinal
# plane -- a different staging, not yet written), `:source_slice` (never
# batches), and `batch_mode = :sequential`, which is the batched exchange's
# bitwise reference.

"""
    _PICBatchExchange{T}

One batch's staging for the batched exchange: every pair of the batch writes
its local extents, the interiors of its deposited planes and its luminosity
deposits into slots of these arrays, each collective then carries the whole
batch, and the pairs read their slots back. Sized for the widest batch of a
collide; kept across collides through `_pic_batch_exchange!`, since the
staging is tens of MB at the production point and allocating it per turn is
exactly what the workspace pool exists to avoid. A slot is `(pair position
k, direction d)`, numbered `pd = 2(k - 1) + d`; a plane slot is
`(pd - 1) * nplanes + m`.
"""
struct _PICBatchExchange{T}
    width::Int
    nplanes::Int                       # per direction: 2, or 3 under :quadratic
    minmax::Vector{T}                  # 8 per slot: -min and max of source x, y and field x, y
    sums::Vector{T}                    # 12 per slot: the :sigma sums, both counts, both flags
    origins::Vector{T}                 # 10 per slot: the :sigma origins, source then field
    charge::Array{T,3}                 # (nx, ny, plane slots): the deposits' interiors
    phis::Array{T,3}                   # (nx, ny, plane slots): the owners' solved potentials
    fields::Vector{_PICFieldWorkspace{T}}   # per plane slot: Ex, Ey (phi lives in `phis`)
    greens::Vector{Matrix{Complex{T}}} # per slot: the no-cache path's own Green table
    vx::Vector{Vector{T}}              # per slot: the source's virtual positions
    vy::Vector{Vector{T}}
    lum_minmax::Vector{T}              # 4 per pair
    lum_q::Array{T,3}                  # (lnx + 1, lny + 1, 2 per pair)
    lum_values::Vector{T}              # per pair: the owner's overlap sum
    lum_h::Matrix{T}                   # (2, width): the overlap mesh's inverse spacings
    sL::Matrix{T}                      # (2, width)
    sR::Matrix{T}
    grids::Matrix{Any}                 # (2, width): (source_grid, field_grid, green_fft)
    active::Vector{Bool}
end

function _pic_batch_exchange(solver::PICPoissonSolver, ::Type{T}, width::Int) where {T}
    nx, ny = solver.grid
    lnx, lny = _pic_luminosity_grid(solver)
    nplanes = _pic_quadratic_slice(solver) ? 3 : 2
    nslots = 2 * width
    return _PICBatchExchange{T}(
        width, nplanes,
        fill(T(-Inf), 8 * nslots), zeros(T, 12 * nslots), zeros(T, 10 * nslots),
        zeros(T, nx, ny, nplanes * nslots), zeros(T, nx, ny, nplanes * nslots),
        [_PICFieldWorkspace(zeros(T, 0, 0), zeros(T, nx, ny), zeros(T, nx, ny))
         for _ in 1:(nplanes * nslots)],
        [Matrix{Complex{T}}(undef, 0, 0) for _ in 1:nslots],
        [T[] for _ in 1:nslots], [T[] for _ in 1:nslots],
        fill(T(-Inf), 4 * width), zeros(T, lnx + 1, lny + 1, 2 * width), zeros(T, width),
        zeros(T, 2, width), zeros(T, 2, width), zeros(T, 2, width),
        Matrix{Any}(nothing, 2, width), fill(false, width))
end

"""
The batch exchange for this collide, reused from `holder` when the one it
holds is wide enough for `width` and shaped for this solver and type.
"""
function _pic_batch_exchange!(holder::Base.RefValue{Any}, solver::PICPoissonSolver,
                              ::Type{T}, width::Int) where {T}
    nx, ny = solver.grid
    lnx, lny = _pic_luminosity_grid(solver)
    nplanes = _pic_quadratic_slice(solver) ? 3 : 2
    ex = holder[]
    if ex isa _PICBatchExchange{T} && ex.width >= width && ex.nplanes == nplanes &&
       size(ex.charge, 1) == nx && size(ex.charge, 2) == ny &&
       size(ex.lum_q, 1) == lnx + 1 && size(ex.lum_q, 2) == lny + 1
        return ex
    end
    fresh = _pic_batch_exchange(solver, T, width)
    holder[] = fresh
    return fresh
end

@inline _pic_batch_slot(k::Int, d::Int) = 2 * (k - 1) + d
@inline _pic_batch_plane(ex::_PICBatchExchange, pd::Int, m::Int) = (pd - 1) * ex.nplanes + m
"""The `(k, d)` a plane slot belongs to."""
@inline function _pic_batch_slot_pair(ex::_PICBatchExchange, slot::Int)
    pd = (slot - 1) ÷ ex.nplanes + 1
    return (pd - 1) ÷ 2 + 1, (pd - 1) % 2 + 1
end

_pic_batch_param(slices, i::Int) = (weight=slices.weight[i], lb=slices.boundary[i],
                                    center=slices.center[i], rb=slices.boundary[i + 1])

"""
The owner's first member of slice `c` into `origins[at:at+4]` as `(x, px, y,
py, z)`, zeros elsewhere; after the batch's one all-sum every rank holds the
owner's values exactly (zero plus a number is that number).
"""
function _pic_batch_origin!(origins, at::Int, c, owns::Bool)
    if owns && !isempty(c.x)
        origins[at] = c.x[1]; origins[at + 1] = c.px[1]
        origins[at + 2] = c.y[1]; origins[at + 3] = c.py[1]
        origins[at + 4] = c.z[1]
    end
    return nothing
end

"""
The `:sigma` estimator's shift origins for one direction, from the exchanged
first member (`origins`, offsets `so` for the source and `fo` for the field)
-- the same expressions `_pic_interaction!` forms from `source_ref` and
`field_ref`, so the extents agree to the bit.
"""
function _pic_batch_origins(::Type{T}, source, param_source, field, sL, origins,
                            so::Int, fo::Int) where {T}
    if origins !== nothing
        source_x0 = T(origins[so]) + T(origins[so + 1]) * sL
        source_y0 = T(origins[so + 2]) + T(origins[so + 3]) * sL
        s = T(0.5) * (T(origins[fo + 4]) - T(param_source.center))
        field_x0 = T(origins[fo]) + s * T(origins[fo + 1])
        field_y0 = T(origins[fo + 2]) + s * T(origins[fo + 3])
    else
        if !isempty(source.x)
            source_x0 = source.x[1] + source.px[1] * sL
            source_y0 = source.y[1] + source.py[1] * sL
        else
            source_x0 = zero(T); source_y0 = zero(T)
        end
        if !isempty(field.x)
            field_x0 = field.x[1] + T(0.5) * (field.z[1] - T(param_source.center)) * field.px[1]
            field_y0 = field.y[1] + T(0.5) * (field.z[1] - T(param_source.center)) * field.py[1]
        else
            field_x0 = zero(T); field_y0 = zero(T)
        end
    end
    return source_x0, source_y0, field_x0, field_y0
end

"""
Stage A of one direction: the local extents and `:sigma` sums of the source
(drifted to the field slice's two edges) and of the field (drifted to the
source's centre, computed without writing the drift), into the slot's entries
of `ex.minmax` (negated minima, so one all-max serves) and `ex.sums`.
"""
function _pic_batch_local_extents!(ex::_PICBatchExchange{T}, k::Int, d::Int,
                                   solver::PICPoissonSolver, source, param_source,
                                   field, param_field, origins, so::Int, fo::Int) where {T}
    pd = _pic_batch_slot(k, d)
    nsource = length(source.x)
    nfield = length(field.x)
    sL = T(0.5) * (T(param_source.center) - T(param_field.lb))
    sR = T(0.5) * (T(param_source.center) - T(param_field.rb))
    ex.sL[d, k] = sL
    ex.sR[d, k] = sR
    ge = Symbol(solver.grid_extent)
    source_x0, source_y0, field_x0, field_y0 =
        _pic_batch_origins(T, source, param_source, field, sL, origins, so, fo)
    source_xmin = T(Inf); source_xmax = T(-Inf)
    source_ymin = T(Inf); source_ymax = T(-Inf)
    sxs = zero(T); sxs2 = zero(T); sys = zero(T); sys2 = zero(T)
    for i in 1:nsource
        @inbounds begin
            xl = source.x[i] + source.px[i] * sL
            yl = source.y[i] + source.py[i] * sL
            xr = source.x[i] + source.px[i] * sR
            yr = source.y[i] + source.py[i] * sR
            source_xmin = min(source_xmin, xl, xr)
            source_xmax = max(source_xmax, xl, xr)
            source_ymin = min(source_ymin, yl, yr)
            source_ymax = max(source_ymax, yl, yr)
            if ge !== :extrema
                dxl = xl - source_x0; dxr = xr - source_x0
                dyl = yl - source_y0; dyr = yr - source_y0
                sxs += dxl + dxr; sxs2 += dxl * dxl + dxr * dxr
                sys += dyl + dyr; sys2 += dyl * dyl + dyr * dyr
            end
        end
    end
    source_bad = nsource > 0 &&
        !all(isfinite, (source_xmin, source_xmax, source_ymin, source_ymax))
    field_xmin = T(Inf); field_xmax = T(-Inf)
    field_ymin = T(Inf); field_ymax = T(-Inf)
    fxs = zero(T); fxs2 = zero(T); fys = zero(T); fys2 = zero(T)
    for i in 1:nfield
        @inbounds begin
            s = T(0.5) * (field.z[i] - T(param_source.center))
            xd = field.x[i] + s * field.px[i]
            yd = field.y[i] + s * field.py[i]
            field_xmin = min(field_xmin, xd); field_xmax = max(field_xmax, xd)
            field_ymin = min(field_ymin, yd); field_ymax = max(field_ymax, yd)
            if ge !== :extrema
                dx = xd - field_x0
                dy = yd - field_y0
                fxs += dx; fxs2 += dx * dx
                fys += dy; fys2 += dy * dy
            end
        end
    end
    field_bad = nfield > 0 &&
        !all(isfinite, (field_xmin, field_xmax, field_ymin, field_ymax))
    base = 8 * (pd - 1)
    @inbounds begin
        ex.minmax[base + 1] = -source_xmin; ex.minmax[base + 2] = source_xmax
        ex.minmax[base + 3] = -source_ymin; ex.minmax[base + 4] = source_ymax
        ex.minmax[base + 5] = -field_xmin;  ex.minmax[base + 6] = field_xmax
        ex.minmax[base + 7] = -field_ymin;  ex.minmax[base + 8] = field_ymax
    end
    sbase = 12 * (pd - 1)
    @inbounds begin
        ex.sums[sbase + 1] = sxs; ex.sums[sbase + 2] = sxs2
        ex.sums[sbase + 3] = sys; ex.sums[sbase + 4] = sys2
        ex.sums[sbase + 5] = fxs; ex.sums[sbase + 6] = fxs2
        ex.sums[sbase + 7] = fys; ex.sums[sbase + 8] = fys2
        ex.sums[sbase + 9] = T(2 * nsource)
        ex.sums[sbase + 10] = T(nfield)
        ex.sums[sbase + 11] = source_bad ? one(T) : zero(T)
        ex.sums[sbase + 12] = field_bad ? one(T) : zero(T)
    end
    return nothing
end

"""An inactive slot: extrema no rank's maximum can see, sums of nothing."""
function _pic_batch_clear_slot!(ex::_PICBatchExchange{T}, k::Int) where {T}
    for d in 1:2
        pd = _pic_batch_slot(k, d)
        fill!(view(ex.minmax, (8 * (pd - 1) + 1):(8 * pd)), T(-Inf))
        fill!(view(ex.sums, (12 * (pd - 1) + 1):(12 * pd)), zero(T))
    end
    return nothing
end

"""
Stage B of one direction, after the extents exchange: the mesh extents from
the exchanged values (the non-finite verdict first, agreed as a count, so
every rank throws or none), the grids, the Green table, the dropped-source
count, and the deposits of every plane into the slot's planes.
"""
function _pic_batch_prepare!(ex::_PICBatchExchange{T}, k::Int, d::Int,
                             solver::PICPoissonSolver, source, param_source,
                             field, param_field, workspace::_PICCPUWorkspace,
                             green_cache, cache_key, origins, so::Int, fo::Int) where {T}
    pd = _pic_batch_slot(k, d)
    sL = ex.sL[d, k]
    sR = ex.sR[d, k]
    ge = Symbol(solver.grid_extent)
    kext = T(solver.grid_extent_sigma)
    base = 8 * (pd - 1)
    sbase = 12 * (pd - 1)
    @inbounds begin
        source_xmin = -ex.minmax[base + 1]; source_xmax = ex.minmax[base + 2]
        source_ymin = -ex.minmax[base + 3]; source_ymax = ex.minmax[base + 4]
        field_xmin = -ex.minmax[base + 5];  field_xmax = ex.minmax[base + 6]
        field_ymin = -ex.minmax[base + 7];  field_ymax = ex.minmax[base + 8]
        sxs = ex.sums[sbase + 1]; sxs2 = ex.sums[sbase + 2]
        sys = ex.sums[sbase + 3]; sys2 = ex.sums[sbase + 4]
        fxs = ex.sums[sbase + 5]; fxs2 = ex.sums[sbase + 6]
        fys = ex.sums[sbase + 7]; fys2 = ex.sums[sbase + 8]
        nsource_count = Int(ex.sums[sbase + 9])
        nfield_count = Int(ex.sums[sbase + 10])
        source_bad = ex.sums[sbase + 11] > zero(T)
        field_bad = ex.sums[sbase + 12] > zero(T)
    end
    source_x0, source_y0, field_x0, field_y0 =
        _pic_batch_origins(T, source, param_source, field, sL, origins, so, fo)
    source_xmin, source_xmax = _pic_axis_extent(ge, source_xmin, source_xmax,
                                                source_x0, sxs, sxs2, nsource_count, kext)
    source_ymin, source_ymax = _pic_axis_extent(ge, source_ymin, source_ymax,
                                                source_y0, sys, sys2, nsource_count, kext)
    (source_bad || !all(isfinite, (source_xmin, source_xmax, source_ymin, source_ymax))) &&
        _nonfinite_coordinate_error(:source,
            (x=source.x, px=source.px, y=source.y, py=source.py);
            context=_pic_slice_context(cache_key))
    field_xmin, field_xmax = _pic_axis_extent(ge, field_xmin, field_xmax,
                                              field_x0, fxs, fxs2, nfield_count, kext)
    field_ymin, field_ymax = _pic_axis_extent(ge, field_ymin, field_ymax,
                                              field_y0, fys, fys2, nfield_count, kext)
    (field_bad || !all(isfinite, (field_xmin, field_xmax, field_ymin, field_ymax))) &&
        _nonfinite_coordinate_error(:field,
            (x=field.x, px=field.px, y=field.y, py=field.py, z=field.z);
            context=_pic_slice_context(cache_key))
    source_grid0, field_grid0 = _pic_interaction_grids(
        solver, source_xmin, source_xmax, source_ymin, source_ymax,
        field_xmin, field_xmax, field_ymin, field_ymax,
    )
    source_bounds = (xmin=source_xmin, xmax=source_xmax, ymin=source_ymin, ymax=source_ymax)
    field_bounds = (xmin=field_xmin, xmax=field_xmax, ymin=field_ymin, ymax=field_ymax)
    source_grid, field_grid, green_fft = _pic_slice_pair_green!(
        workspace, solver, T, green_cache, cache_key, source_grid0, field_grid0,
        source_bounds, field_bounds,
    )
    if green_fft === workspace.green_fft
        # The no-cache path returns the worker's own table, which the next
        # pair on this worker overwrites before the solve stage reads it.
        own = ex.greens[pd]
        if size(own) != size(green_fft)
            own = similar(green_fft)
            ex.greens[pd] = own
        end
        copyto!(own, green_fft)
        green_fft = own
    end
    ex.grids[d, k] = (source_grid, field_grid, green_fft)
    if ge !== :extrema
        # The source half of the dropped count, at the drifted positions the
        # deposits use; the field half is counted after the drift, in stage C.
        workspace.dropped[] += _pic_count_outside_box_drifted(
            source.x, source.px, source.y, source.py, sL, sR,
            source_grid.x0, source_grid.x0 + source_grid.width,
            source_grid.y0, source_grid.y0 + source_grid.height)
    end
    nx, ny = solver.grid
    hx = T(source_grid.width) / T(nx - 1)
    hy = T(source_grid.height) / T(ny - 1)
    method = solver.deposit_method
    x0 = T(source_grid.x0)
    y0 = T(source_grid.y0)
    for m in 1:ex.nplanes
        s = m == 1 ? sL : m == 2 ? sR : T(0.5) * (sL + sR)
        # The nx x ny interior only: the deposit never writes the padding
        # (CIC's base is clamped to n - 1, TSC's to n - 2), and zeros summed
        # across ranks are zeros, so only the interior travels.
        charge = view(ex.charge, :, :, _pic_batch_plane(ex, pd, m))
        fill!(charge, zero(T))
        _pic_deposit_drifted!(charge, method, source.x, source.px, source.y, source.py,
                              T(s), x0, y0, hx, hy, nx, ny, workspace)
    end
    return nothing
end

"""
The owner's solve of one plane slot, after the reduce-scatter: the summed
interior into the worker's zero-padded plane, the FFT convolution with the
pair's Green table, the potential's interior into `ex.phis` -- what
`_pic_solve_drifted_field_with_green_fft!` does after its all-sum.
"""
function _pic_batch_solve!(ex::_PICBatchExchange{T}, slot::Int, workspace::_PICCPUWorkspace,
                           green_fft, nx::Int, ny::Int) where {T}
    charge = workspace.charge
    fill!(charge, zero(T))
    copyto!(view(charge, 1:nx, 1:ny), view(ex.charge, :, :, slot))
    spectral = workspace.spectral
    spectral .= charge
    workspace.fft_plan * spectral
    spectral .*= green_fft
    workspace.ifft_plan * spectral
    phi = view(ex.phis, :, :, slot)
    for j in 1:ny, i in 1:nx
        @inbounds phi[i, j] = real(spectral[i, j])
    end
    return nothing
end

"""
Stage C of one direction, after the potentials' all-gather: the field
gradients from the gathered potentials (every rank from the same numbers, so
every rank the same field), the field slice's drift (in place, as
`_pic_interaction!` does at its start -- here after the deposits that read
the source, which for direction 2 is the slice direction 1 kicks), its
dropped count against the mesh the kick reads, the kicks, and the source's
virtual positions into the slot's buffers for the luminosity stage.
"""
function _pic_batch_finish!(ex::_PICBatchExchange{T}, k::Int, d::Int,
                            solver::PICPoissonSolver, source, param_source,
                            field, param_field, kbb, workspace::_PICCPUWorkspace) where {T}
    pd = _pic_batch_slot(k, d)
    source_grid, field_grid, _ = ex.grids[d, k]
    nx, ny = solver.grid
    hx = T(source_grid.width) / T(nx - 1)
    hy = T(source_grid.height) / T(ny - 1)
    fourth = _pic_fourth_order(solver)
    for m in 1:ex.nplanes
        slot = _pic_batch_plane(ex, pd, m)
        fw = ex.fields[slot]
        _pic_field!(fw.Ex, fw.Ey, view(ex.phis, :, :, slot), hx, hy, fourth)
    end
    nfield = length(field.x)
    for i in 1:nfield
        @inbounds begin
            s = T(0.5) * (field.z[i] - T(param_source.center))
            field.x[i] += s * field.px[i]
            field.y[i] += s * field.py[i]
            if solver.longitudinal_kick
                field.pz[i] -= T(0.25) * (field.px[i] * field.px[i] + field.py[i] * field.py[i])
            end
        end
    end
    if Symbol(solver.grid_extent) !== :extrema
        workspace.dropped[] += _pic_count_outside_box(
            field.x, field.y,
            field_grid.x0, field_grid.x0 + field_grid.width,
            field_grid.y0, field_grid.y0 + field_grid.height)
    end
    slotL = _pic_batch_plane(ex, pd, 1)
    slotR = _pic_batch_plane(ex, pd, 2)
    L = ex.fields[slotL]
    R = ex.fields[slotR]
    phiL = view(ex.phis, :, :, slotL)
    phiR = view(ex.phis, :, :, slotR)
    kick_scale = T(2) * T(kbb)
    hzi, zbias = _slice_interpolation_parameters(T(param_field.lb), T(param_field.rb))
    if _pic_quadratic_slice(solver)
        slotM = _pic_batch_plane(ex, pd, 3)
        M = ex.fields[slotM]
        phiM = view(ex.phis, :, :, slotM)
        _pic_map_particles(nfield) do first_i, last_i
            _pic_apply_kick_quadratic_range!(
                solver, field, field_grid, phiL, L.Ex, L.Ey, phiM, M.Ex, M.Ey,
                phiR, R.Ex, R.Ey, kick_scale, hzi, zbias,
                T(param_source.center), T, first_i, last_i,
            )
        end
    else
        _pic_map_particles(nfield) do first_i, last_i
            _pic_apply_kick_range!(
                solver, field, field_grid, phiL, L.Ex, L.Ey, phiR, R.Ex, R.Ey,
                kick_scale, hzi, zbias, T(param_source.center), T, first_i, last_i,
            )
        end
    end
    sM = T(0.5) * (T(param_source.center) - T(param_field.center))
    nsource = length(source.x)
    vx = ex.vx[pd]
    vy = ex.vy[pd]
    if length(vx) != nsource
        resize!(vx, nsource)
        resize!(vy, nsource)
    end
    _pic_map_particles(nsource) do first_i, last_i
        _pic_virtual_positions_range!(vx, vy, source, sM, first_i, last_i)
    end
    return nothing
end

"""
One wavefront batch of the divided collide through the batched exchange. Runs
the stages above over every pair of `batch`, the pairs of a stage on
`nworkers` workers with their own workspaces, the collectives between the
stages on the main thread. Writes `ran[p]` and, when asked, `lum_parts[p]`
for every pair, exactly as `_pic_collide_pair!` would have.
"""
function _pic_collide_batch_divided!(ex::_PICBatchExchange{T}, batch, lum_parts, ran, pair_pos,
                                     solver::PICPoissonSolver, slices1, slices2,
                                     state1, state2, scratch2, workspaces, green_cache,
                                     kbb1, kbb2, klum, compute_luminosity::Bool,
                                     plan1, plan2, nworkers::Int) where {T}
    nk = length(batch)
    nk <= ex.width || error("PIC batch exchange sized for $(ex.width) pairs met a batch of $(nk)")
    sigma = Symbol(solver.grid_extent) === :sigma
    for k in 1:nk
        pr = batch[k]
        ex.active[k] = plan1.counts[pr.i] > 0 && plan2.counts[pr.j] > 0
        ran[pair_pos[(pr.i, pr.j)]] = ex.active[k]
    end
    # --- the :sigma origins: owners contribute, one all-sum ---------------
    if sigma
        fill!(view(ex.origins, 1:(20 * nk)), zero(T))
        for k in 1:nk
            ex.active[k] || continue
            pr = batch[k]
            coord1 = state1[pr.i]
            coord2 = state2[pr.j]
            at = 20 * (k - 1)
            # Direction 1: source slice i, field slice j (a copy of it, so the
            # same first member); direction 2: source slice j, field slice i.
            # All four are pre-kick, as in the per-pair path: neither
            # interaction writes its source, and direction 2's field is read
            # before it is kicked.
            _pic_batch_origin!(ex.origins, at + 1, coord1, plan1.owns_reference[pr.i])
            _pic_batch_origin!(ex.origins, at + 6, coord2, plan2.owns_reference[pr.j])
            _pic_batch_origin!(ex.origins, at + 11, coord2, plan2.owns_reference[pr.j])
            _pic_batch_origin!(ex.origins, at + 16, coord1, plan1.owns_reference[pr.i])
        end
        _mp_allsum!(view(ex.origins, 1:(20 * nk)))
    end
    origins_of(k) = sigma ? view(ex.origins, (20 * (k - 1) + 1):(20 * k)) : nothing
    # --- stage A: local extents ---------------------------------------------
    _run_logical_workers(nworkers) do chunk, _
        lo, hi = _chunk_bounds(nk, nworkers, chunk)
        for k in lo:hi
            if !ex.active[k]
                _pic_batch_clear_slot!(ex, k)
                continue
            end
            pr = batch[k]
            coord1 = state1[pr.i]
            coord2 = state2[pr.j]
            field2 = _pic_copy_slice!(scratch2[pr.j], coord2)
            param1 = _pic_batch_param(slices1, pr.i)
            param2 = _pic_batch_param(slices2, pr.j)
            orig = origins_of(k)
            _pic_batch_local_extents!(ex, k, 1, solver, coord1, param1, field2, param2, orig, 1, 6)
            _pic_batch_local_extents!(ex, k, 2, solver, coord2, param2, coord1, param1, orig, 11, 16)
        end
    end
    _mp_allmax!(view(ex.minmax, 1:(16 * nk)))
    _mp_allsum!(view(ex.sums, 1:(24 * nk)))
    # --- stage B: extents -> grids -> Green -> deposits ----------------------
    _run_logical_workers(nworkers) do chunk, _
        ws = workspaces[chunk]
        lo, hi = _chunk_bounds(nk, nworkers, chunk)
        for k in lo:hi
            ex.active[k] || continue
            pr = batch[k]
            coord1 = state1[pr.i]
            coord2 = state2[pr.j]
            field2 = scratch2[pr.j]
            param1 = _pic_batch_param(slices1, pr.i)
            param2 = _pic_batch_param(slices2, pr.j)
            orig = origins_of(k)
            _pic_batch_prepare!(ex, k, 1, solver, coord1, param1, field2, param2, ws,
                                green_cache, (pr.i, pr.j, 1), orig, 1, 6)
            _pic_batch_prepare!(ex, k, 2, solver, coord2, param2, coord1, param1, ws,
                                green_cache, (pr.i, pr.j, 2), orig, 11, 16)
        end
    end
    nplanes = ex.nplanes * 2 * nk
    # --- the planes to their owners, the owners' solves, the potentials to all
    owned = _mp_reduce_scatter_blocks!(view(ex.charge, :, :, 1:nplanes), nplanes)
    _record_execution!(:pic_grid_exchange, CPUThreadsBackend,
                       (planes=nplanes, batched=true, ranks=_mp_nranks()))
    nx, ny = solver.grid
    if !isempty(owned)
        nsolve = clamp(nworkers, 1, length(owned))
        _run_logical_workers(nsolve) do chunk, _
            ws = workspaces[chunk]
            lo, hi = _chunk_bounds(length(owned), nsolve, chunk)
            for idx in lo:hi
                slot = owned[idx]
                k, d = _pic_batch_slot_pair(ex, slot)
                ex.active[k] || continue
                _, _, green_fft = ex.grids[d, k]
                _pic_batch_solve!(ex, slot, ws, green_fft, nx, ny)
            end
        end
    end
    _mp_allgather_blocks!(view(ex.phis, :, :, 1:nplanes), nplanes)
    # --- stage C: gradients, drifts, kicks, virtual positions ---------------
    _run_logical_workers(nworkers) do chunk, _
        ws = workspaces[chunk]
        lo, hi = _chunk_bounds(nk, nworkers, chunk)
        for k in lo:hi
            ex.active[k] || continue
            pr = batch[k]
            coord1 = state1[pr.i]
            coord2 = state2[pr.j]
            field2 = scratch2[pr.j]
            param1 = _pic_batch_param(slices1, pr.i)
            param2 = _pic_batch_param(slices2, pr.j)
            # Direction 1 first: its virtual positions read slice i before
            # direction 2 drifts and kicks it, as the per-pair order does.
            _pic_batch_finish!(ex, k, 1, solver, coord1, param1, field2, param2, kbb2, ws)
            _pic_batch_finish!(ex, k, 2, solver, coord2, param2, coord1, param1, kbb1, ws)
            # The kicked scratch becomes the resident slice j; no two pairs of
            # a batch share a slice index, so this write never races.
            @inbounds state2[pr.j], scratch2[pr.j] = scratch2[pr.j], state2[pr.j]
        end
    end
    compute_luminosity || return nothing
    # --- the luminosity: extents, deposits, overlap --------------------------
    lnx, lny = _pic_luminosity_grid(solver)
    for k in 1:nk
        base = 4 * (k - 1)
        if !ex.active[k]
            fill!(view(ex.lum_minmax, (base + 1):(base + 4)), T(-Inf))
            continue
        end
        x1 = ex.vx[_pic_batch_slot(k, 1)]; y1 = ex.vy[_pic_batch_slot(k, 1)]
        x2 = ex.vx[_pic_batch_slot(k, 2)]; y2 = ex.vy[_pic_batch_slot(k, 2)]
        xmin = min(_pic_extremum(minimum, x1, T(Inf)), _pic_extremum(minimum, x2, T(Inf)))
        xmax = max(_pic_extremum(maximum, x1, T(-Inf)), _pic_extremum(maximum, x2, T(-Inf)))
        ymin = min(_pic_extremum(minimum, y1, T(Inf)), _pic_extremum(minimum, y2, T(Inf)))
        ymax = max(_pic_extremum(maximum, y1, T(-Inf)), _pic_extremum(maximum, y2, T(-Inf)))
        @inbounds begin
            ex.lum_minmax[base + 1] = -xmin; ex.lum_minmax[base + 2] = xmax
            ex.lum_minmax[base + 3] = -ymin; ex.lum_minmax[base + 4] = ymax
        end
    end
    _mp_allmax!(view(ex.lum_minmax, 1:(4 * nk)))
    fill!(view(ex.lum_q, :, :, 1:(2 * nk)), zero(T))
    method = _pic_luminosity_deposit_method(solver)
    _run_logical_workers(nworkers) do chunk, _
        lo, hi = _chunk_bounds(nk, nworkers, chunk)
        for k in lo:hi
            ex.active[k] || continue
            base = 4 * (k - 1)
            @inbounds begin
                xmin = -ex.lum_minmax[base + 1]; xmax = ex.lum_minmax[base + 2]
                ymin = -ex.lum_minmax[base + 3]; ymax = ex.lum_minmax[base + 4]
            end
            mesh = _pic_luminosity_mesh(solver, T, xmin, xmax, ymin, ymax)
            ex.lum_h[1, k] = mesh.hxi
            ex.lum_h[2, k] = mesh.hyi
            x1 = ex.vx[_pic_batch_slot(k, 1)]; y1 = ex.vy[_pic_batch_slot(k, 1)]
            x2 = ex.vx[_pic_batch_slot(k, 2)]; y2 = ex.vy[_pic_batch_slot(k, 2)]
            q1 = view(ex.lum_q, :, :, 2 * k - 1)
            q2 = view(ex.lum_q, :, :, 2 * k)
            _pic_deposit!(q1, method, x1, y1, mesh.xmin, mesh.ymin, mesh.hx, mesh.hy, lnx + 1, lny + 1)
            _pic_deposit!(q2, method, x2, y2, mesh.xmin, mesh.ymin, mesh.hx, mesh.hy, lnx + 1, lny + 1)
        end
    end
    # Each pair's two deposits to one owner, which forms the overlap sum --
    # the per-pair path's sum over the all-summed grids, in its order -- and
    # the scalars to all.
    owned_pairs = _mp_reduce_scatter_blocks!(view(ex.lum_q, :, :, 1:(2 * nk)), nk)
    fill!(view(ex.lum_values, 1:nk), zero(T))
    for k in owned_pairs
        ex.active[k] || continue
        q1 = view(ex.lum_q, :, :, 2 * k - 1)
        q2 = view(ex.lum_q, :, :, 2 * k)
        lum = zero(T)
        for j in 1:(lny + 1), i in 1:(lnx + 1)
            @inbounds lum += q1[i, j] * q2[i, j]
        end
        @inbounds ex.lum_values[k] = lum
    end
    _mp_allgather_blocks!(view(ex.lum_values, 1:nk), nk)
    for k in 1:nk
        ex.active[k] || continue
        pr = batch[k]
        @inbounds lum_parts[pair_pos[(pr.i, pr.j)]] =
            ex.lum_values[k] * T(klum) * ex.lum_h[1, k] * ex.lum_h[2, k]
    end
    return nothing
end
