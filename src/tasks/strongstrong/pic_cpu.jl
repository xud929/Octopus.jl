function collide!(solver::PICPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend})
    return collide!(solver, beam1, beam2, CPUThreadsBackend, nothing)
end

function collide!(solver::PICPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend},
                  ctx::Nothing)
    return _pic_collide!(solver, beam1, beam2, ctx)
end

function collide!(solver::PICPoissonSolver, beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend},
                  ctx::TrackingContext)
    return _pic_collide!(solver, beam1, beam2, ctx)
end

function _pic_collide!(solver::PICPoissonSolver, beam1::Beam, beam2::Beam, ctx)
    T = _pic_cpu_scalar_type(solver, beam1, beam2)
    nx, ny = solver.grid
    workspace = _pic_cpu_workspace(T, nx, ny)
    green_cache = _pic_green_cache(solver, T)
    return _pic_collide!(solver, beam1, beam2, ctx, workspace, green_cache)
end

function _strong_strong_collide!(task::StrongStrongTask, label::Symbol,
                                 solver::PICPoissonSolver,
                                 beam1::Beam, beam2::Beam, ::Type{CPUThreadsBackend},
                                 ctx::TrackingContext)
    T = _pic_cpu_scalar_type(solver, beam1, beam2)
    workspace = _pic_cpu_workspace!(task.runtime_cache, label, solver, T)
    green_cache = _pic_green_cache!(task.runtime_cache, label, solver, T)
    return _pic_collide!(solver, beam1, beam2, ctx, workspace, green_cache)
end

function _pic_collide!(solver::PICPoissonSolver, beam1::Beam, beam2::Beam, ctx,
                       workspace::_PICCPUWorkspace, green_cache)
    _validate_pic_solver(solver)
    slices1 = longitudinal_slices(beam1.rep, solver.slicing1)
    slices2 = longitudinal_slices(beam2.rep, solver.slicing2)
    kbb1 = _pic_kbb1(solver, beam1, beam2)
    kbb2 = _pic_kbb2(solver, beam1, beam2)
    klum = _pic_luminosity_scale(solver, beam1, beam2)
    compute_luminosity = _pic_compute_luminosity(solver, ctx)
    T = promote_type(eltype(beam1.rep.x), eltype(beam2.rep.x), typeof(kbb1), typeof(kbb2))
    luminosity = compute_luminosity ? zero(eltype(beam1.rep.x)) : T(NaN)
    for (_, i, j) in _slice_collision_order(slices1, slices2)
        idx1 = slices1.indices[i]
        idx2 = slices2.indices[j]
        (isempty(idx1) || isempty(idx2)) && continue
        param1 = (weight=slices1.weight[i], lb=slices1.boundary[i],
                  center=slices1.center[i], rb=slices1.boundary[i + 1])
        param2 = (weight=slices2.weight[j], lb=slices2.boundary[j],
                  center=slices2.center[j], rb=slices2.boundary[j + 1])
        coord1 = _pic_extract_slice(beam1.rep, idx1)
        coord2 = _pic_extract_slice(beam2.rep, idx2)
        field1 = _pic_copy_coords(coord1)
        field2 = _pic_copy_coords(coord2)
        vx1, vy1 = _pic_interaction!(
            solver, coord1, param1, field2, param2, kbb2, workspace, green_cache, (i, j, 1),
        )
        vx2, vy2 = _pic_interaction!(
            solver, coord2, param2, field1, param1, kbb1, workspace, green_cache, (i, j, 2),
        )
        _pic_store_slice!(beam1.rep, idx1, field1)
        _pic_store_slice!(beam2.rep, idx2, field2)
        if compute_luminosity
            pair_luminosity = _pic_luminosity(solver, vx1, vy1, vx2, vy2, klum, workspace)
            luminosity += pair_luminosity
            sink = _ACTIVE_PIC_LUMINOSITY_PAIR_SINK[]
            sink === nothing || push!(sink, (
                turn=ctx === nothing ? -1 : ctx.turn, i=Int(i), j=Int(j),
                luminosity=Float64(pair_luminosity),
            ))
        end
    end
    _pic_report_green_cache(green_cache)
    return luminosity
end

function _pic_cpu_scalar_type(solver::PICPoissonSolver, beam1::Beam, beam2::Beam)
    return promote_type(
        eltype(beam1.rep.x), eltype(beam2.rep.x),
        typeof(_pic_kbb1(solver, beam1, beam2)),
        typeof(_pic_kbb2(solver, beam1, beam2)),
    )
end

function _pic_cpu_workspace!(runtime_cache::Dict, label::Symbol,
                             solver::PICPoissonSolver, ::Type{T}) where {T}
    key = (:cpu_pic_workspace, label, T, solver.grid, Threads.nthreads())
    return get!(runtime_cache, key) do
        _pic_cpu_workspace(T, solver.grid...)
    end
end

function _pic_green_cache!(runtime_cache::Dict, label::Symbol,
                           solver::PICPoissonSolver, ::Type{T}) where {T}
    key = (
        :cpu_pic_green_cache,
        label,
        T,
        solver.grid,
        Symbol(solver.green_type),
        Symbol(solver.green_cache),
        solver.slice_pair_green_min_ratio,
        solver.slice_pair_green_growth,
    )
    return get!(runtime_cache, key) do
        _pic_green_cache(solver, T)
    end
end

function _validate_pic_solver(solver::PICPoissonSolver)
    nx, ny = solver.grid
    _validate_pic_grid(nx, ny)
    method = Symbol(solver.deposit_method)
    (method == :CIC || method == :TSC) ||
        throw(ArgumentError("PICPoissonSolver deposit_method must be :CIC or :TSC"))
    luminosity_method = _pic_luminosity_deposit_method(solver)
    (luminosity_method == :CIC || luminosity_method == :TSC) ||
        throw(ArgumentError("PICPoissonSolver luminosity_deposit_method must resolve to :CIC or :TSC"))
    green = Symbol(solver.green_type)
    (green == :integrated || green == :standard) ||
        throw(ArgumentError("PICPoissonSolver green_type must be :integrated or :standard"))
    cache = Symbol(solver.green_cache)
    (cache == :none || cache == :slice_pair) ||
        throw(ArgumentError("PICPoissonSolver green_cache must be :none or :slice_pair"))
    batch_mode = Symbol(solver.batch_mode)
    (batch_mode == :sequential || batch_mode == :wavefront) ||
        throw(ArgumentError("PICPoissonSolver batch_mode must be :sequential or :wavefront"))
    return nothing
end

function _validate_pic_grid(nx::Integer, ny::Integer)
    nx >= 5 && ny >= 5 || throw(ArgumentError("PICPoissonSolver grid must be at least (5, 5)"))
    return nothing
end

_pic_kbb1(solver::PICPoissonSolver, beam1, beam2) =
    solver.kbb1 !== nothing ? solver.kbb1 : _strong_strong_kbb1(solver, beam1, beam2) / length(beam2.rep)
_pic_kbb2(solver::PICPoissonSolver, beam1, beam2) =
    solver.kbb2 !== nothing ? solver.kbb2 : _strong_strong_kbb2(solver, beam1, beam2) / length(beam1.rep)

function _pic_luminosity_scale(solver::PICPoissonSolver, beam1, beam2)
    solver.luminosity_scale !== nothing && return solver.luminosity_scale
    return beam1.params.npart * beam2.params.npart / (length(beam1.rep) * length(beam2.rep))
end

function _pic_extract_slice(rep::Phase6DRep, idx)
    T = eltype(rep.x)
    n = length(idx)
    x = Vector{T}(undef, n); px = similar(x); y = similar(x)
    py = similar(x); z = similar(x); pz = similar(x)
    for (j, i) in pairs(idx)
        @inbounds begin
            x[j] = rep.x[i]; px[j] = rep.px[i]
            y[j] = rep.y[i]; py[j] = rep.py[i]
            z[j] = rep.z[i]; pz[j] = rep.pz[i]
        end
    end
    return (x=x, px=px, y=y, py=py, z=z, pz=pz)
end

_pic_copy_coords(c) = (x=copy(c.x), px=copy(c.px), y=copy(c.y),
                       py=copy(c.py), z=copy(c.z), pz=copy(c.pz))

function _pic_store_slice!(rep::Phase6DRep, idx, c)
    for (j, i) in pairs(idx)
        @inbounds begin
            rep.x[i] = c.x[j]; rep.px[i] = c.px[j]
            rep.y[i] = c.y[j]; rep.py[i] = c.py[j]
            rep.z[i] = c.z[j]; rep.pz[i] = c.pz[j]
        end
    end
    return nothing
end

function _pic_interaction!(solver::PICPoissonSolver, source, param_source, field, param_field, kbb)
    nx, ny = solver.grid
    T = promote_type(eltype(source.x), eltype(field.x), typeof(kbb))
    workspace = _pic_cpu_workspace(T, nx, ny)
    green_cache = _pic_green_cache(solver, T)
    return _pic_interaction!(solver, source, param_source, field, param_field, kbb, workspace, green_cache)
end

function _pic_interaction!(solver::PICPoissonSolver, source, param_source, field, param_field, kbb,
                           workspace::_PICCPUWorkspace)
    green_cache = _pic_green_cache(solver, promote_type(eltype(source.x), eltype(field.x), typeof(kbb)))
    return _pic_interaction!(solver, source, param_source, field, param_field, kbb, workspace, green_cache)
end

function _pic_interaction!(solver::PICPoissonSolver, source, param_source, field, param_field, kbb,
                           workspace::_PICCPUWorkspace, green_cache)
    return _pic_interaction!(solver, source, param_source, field, param_field, kbb, workspace, green_cache, nothing)
end

function _pic_interaction!(solver::PICPoissonSolver, source, param_source, field, param_field, kbb,
                           workspace::_PICCPUWorkspace, green_cache, cache_key)
    nsource = length(source.x)
    nfield = length(field.x)
    T = promote_type(eltype(source.x), eltype(field.x), typeof(kbb))

    sL = T(0.5) * (T(param_source.center) - T(param_field.lb))
    sR = T(0.5) * (T(param_source.center) - T(param_field.rb))
    source_xl = source.x[1] + source.px[1] * sL
    source_yl = source.y[1] + source.py[1] * sL
    source_xr = source.x[1] + source.px[1] * sR
    source_yr = source.y[1] + source.py[1] * sR
    source_xmin = min(source_xl, source_xr)
    source_xmax = max(source_xl, source_xr)
    source_ymin = min(source_yl, source_yr)
    source_ymax = max(source_yl, source_yr)
    for i in 2:nsource
        @inbounds begin
            xl = source.x[i] + source.px[i] * sL
            yl = source.y[i] + source.py[i] * sL
            xr = source.x[i] + source.px[i] * sR
            yr = source.y[i] + source.py[i] * sR
            source_xmin = min(source_xmin, xl, xr)
            source_xmax = max(source_xmax, xl, xr)
            source_ymin = min(source_ymin, yl, yr)
            source_ymax = max(source_ymax, yl, yr)
        end
    end

    field_xmin = field_xmax = field.x[1] + T(0.5) * (field.z[1] - T(param_source.center)) * field.px[1]
    field_ymin = field_ymax = field.y[1] + T(0.5) * (field.z[1] - T(param_source.center)) * field.py[1]
    for i in 1:nfield
        @inbounds begin
            s = T(0.5) * (field.z[i] - T(param_source.center))
            field.x[i] += s * field.px[i]
            field.y[i] += s * field.py[i]
            if solver.longitudinal_kick
                field.pz[i] -= T(0.25) * (field.px[i] * field.px[i] + field.py[i] * field.py[i])
            end
            field_xmin = min(field_xmin, field.x[i]); field_xmax = max(field_xmax, field.x[i])
            field_ymin = min(field_ymin, field.y[i]); field_ymax = max(field_ymax, field.y[i])
        end
    end

    source_grid0, field_grid0 = _pic_interaction_grids(
        solver, source_xmin, source_xmax, source_ymin, source_ymax,
        field_xmin, field_xmax, field_ymin, field_ymax,
    )
    source_bounds = (xmin=source_xmin, xmax=source_xmax, ymin=source_ymin, ymax=source_ymax)
    field_bounds = (xmin=field_xmin, xmax=field_xmax, ymin=field_ymin, ymax=field_ymax)
    source_grid, field_grid, green_fft = _pic_slice_pair_green!(
        workspace, solver, T, green_cache, cache_key, source_grid0, field_grid0, source_bounds, field_bounds,
    )
    phiL, ExL, EyL = _pic_solve_drifted_field_with_green_fft!(
        workspace.left, solver, source, sL, source_grid, green_fft, workspace,
    )
    phiR, ExR, EyR = _pic_solve_drifted_field_with_green_fft!(
        workspace.right, solver, source, sR, source_grid, green_fft, workspace,
    )

    kick_scale = T(2) * T(kbb)
    hzi = inv(T(param_field.rb) - T(param_field.lb))
    for i in 1:nfield
        @inbounds begin
            zL, zR = _slice_interpolation_weights(field.z[i], T(param_field.lb), T(param_field.rb))
            Kx, Ky, Kz = _pic_interpolate_kick(
                solver, field_grid, field.x[i], field.y[i],
                phiL, ExL, EyL, phiR, ExR, EyR, zL, zR,
            )
            field.px[i] += kick_scale * Kx
            field.py[i] += kick_scale * Ky
            if solver.longitudinal_kick
                field.pz[i] += kick_scale * Kz * hzi
            end
            s = T(0.5) * (T(param_source.center) - field.z[i])
            field.x[i] += s * field.px[i]
            field.y[i] += s * field.py[i]
            if solver.longitudinal_kick
                field.pz[i] += T(0.25) * (field.px[i] * field.px[i] + field.py[i] * field.py[i])
            end
        end
    end

    sM = T(0.5) * (T(param_source.center) - T(param_field.center))
    vx = Vector{T}(undef, nsource)
    vy = Vector{T}(undef, nsource)
    for i in 1:nsource
        @inbounds begin
            vx[i] = source.x[i] + source.px[i] * sM
            vy[i] = source.y[i] + source.py[i] * sM
        end
    end
    return vx, vy
end

@inline function _slice_interpolation_weights(z, lb, rb)
    T = typeof(z + lb + rb)
    denom = T(rb - lb)
    if !isfinite(denom) || denom == zero(T)
        half = T(0.5)
        return half, half
    end
    zL = clamp(T(rb - z) / denom, zero(T), one(T))
    return zL, one(T) - zL
end

function _pic_interaction_grids(solver::PICPoissonSolver, sxmin, sxmax, symin, symax,
                                fxmin, fxmax, fymin, fymax)
    nx, ny = solver.grid
    T = promote_type(typeof(sxmin), typeof(fxmin))
    width = max(T(sxmax - sxmin), T(fxmax - fxmin), eps(T))
    height = max(T(symax - symin), T(fymax - fymin), eps(T))
    tx = width / (nx - 4)
    ty = height / (ny - 4)
    width += 3 * tx
    height += 3 * ty
    sx0 = T(sxmin) - T(1.5) * tx
    sy0 = T(symin) - T(1.5) * ty
    fx0 = T(fxmin) - T(1.5) * tx
    fy0 = T(fymin) - T(1.5) * ty
    sx0, fx0 = _pic_align_grid_origins(solver.green_type, sx0, fx0, tx)
    sy0, fy0 = _pic_align_grid_origins(solver.green_type, sy0, fy0, ty)
    return (x0=sx0, y0=sy0, width=width, height=height),
           (x0=fx0, y0=fy0, width=width, height=height)
end

function _pic_green_cache(solver::PICPoissonSolver, ::Type{T}) where {T}
    cache = Symbol(solver.green_cache)
    cache == :slice_pair && return _PICSlicePairGreenCache{T}(
        Dict{Tuple{Int,Int,Int},_PICSlicePairGreenEntry{T}}(), 0, 0, 0,
    )
    return nothing
end

function _pic_slice_pair_green!(workspace::_PICCPUWorkspace, solver::PICPoissonSolver, ::Type{T},
                                cache, cache_key, source_grid, field_grid,
                                source_bounds, field_bounds) where {T}
    if cache isa _PICSlicePairGreenCache{T} && cache_key !== nothing
        entry = get(cache.entries, cache_key, nothing)
        if entry !== nothing && _pic_slice_pair_entry_usable(solver, entry, source_grid, field_grid, source_bounds, field_bounds)
            cache.hits += 1
            entry.uses += 1
            return entry.source_grid, entry.field_grid, entry.green_fft
        end
        expanded_source = _pic_expand_grid_by(source_grid, T(1) + T(solver.slice_pair_green_growth))
        expanded_field = _pic_expand_grid_by(field_grid, T(1) + T(solver.slice_pair_green_growth))
        green_fft = copy(_pic_green_fft!(workspace, solver, T, expanded_source, expanded_field))
        if entry === nothing
            cache.misses += 1
            cache.entries[cache_key] = _PICSlicePairGreenEntry{T}(expanded_source, expanded_field, green_fft, 1, 0)
        else
            cache.rebuilds += 1
            entry.rebuilds += 1
            cache.entries[cache_key] = _PICSlicePairGreenEntry{T}(expanded_source, expanded_field, green_fft, 1, entry.rebuilds)
        end
        return expanded_source, expanded_field, green_fft
    end
    return source_grid, field_grid, _pic_green_fft!(workspace, solver, T, source_grid, field_grid)
end

function _pic_slice_pair_entry_usable(solver::PICPoissonSolver, entry, source_grid, field_grid, source_bounds, field_bounds)
    min_ratio = solver.slice_pair_green_min_ratio
    _pic_grid_size_usable(entry.source_grid, source_grid, min_ratio) || return false
    _pic_grid_size_usable(entry.field_grid, field_grid, min_ratio) || return false
    _pic_grid_covers_bounds(solver, entry.source_grid, source_bounds) || return false
    _pic_grid_covers_bounds(solver, entry.field_grid, field_bounds) || return false
    return true
end

function _pic_grid_size_usable(cached_grid, requested_grid, min_ratio)
    cached_grid.width >= requested_grid.width || return false
    cached_grid.height >= requested_grid.height || return false
    requested_grid.width >= min_ratio * cached_grid.width || return false
    requested_grid.height >= min_ratio * cached_grid.height || return false
    return true
end

function _pic_grid_covers_bounds(solver::PICPoissonSolver, grid, bounds)
    nx, ny = solver.grid
    T = promote_type(typeof(grid.x0), typeof(bounds.xmin))
    hx = T(grid.width) / T(nx - 1)
    hy = T(grid.height) / T(ny - 1)
    margin = T(_PIC_TEMPLATE_MARGIN_CELLS)
    grid.x0 + margin * hx <= bounds.xmin || return false
    grid.x0 + grid.width - margin * hx >= bounds.xmax || return false
    grid.y0 + margin * hy <= bounds.ymin || return false
    grid.y0 + grid.height - margin * hy >= bounds.ymax || return false
    return true
end

function _pic_expand_grid_by(grid, factor)
    factor <= one(factor) && return grid
    T = promote_type(typeof(grid.x0), typeof(grid.width), typeof(factor))
    new_width = T(grid.width) * T(factor)
    new_height = T(grid.height) * T(factor)
    return (
        x0=T(grid.x0) - (new_width - T(grid.width)) / T(2),
        y0=T(grid.y0) - (new_height - T(grid.height)) / T(2),
        width=new_width,
        height=new_height,
    )
end

function _pic_report_green_cache(cache)
    cache === nothing && return nothing
    _strong_strong_diagnostics().cache_stats || return nothing
    if cache isa _PICSlicePairGreenCache
        total = cache.hits + cache.misses + cache.rebuilds
        reuse_rate = total == 0 ? 0.0 : cache.hits / total
        initial_fill_rate = total == 0 ? 0.0 : cache.misses / total
        rebuild_rate = total == 0 ? 0.0 : cache.rebuilds / total
        println(
            "PIC slice-pair Green cache: entries=$(length(cache.entries)), " *
            "hits=$(cache.hits), misses=$(cache.misses), rebuilds=$(cache.rebuilds), " *
            "reuse_rate=$(reuse_rate), initial_fill_rate=$(initial_fill_rate), rebuild_rate=$(rebuild_rate)"
        )
    end
    return nothing
end

function _pic_align_grid_origins(green_type, source0, field0, h)
    f1 = source0 / h - floor(source0 / h)
    f2 = field0 / h - floor(field0 / h)
    t = (f2 - f1) / 2
    if Symbol(green_type) == :standard
        t += t > 0 ? -0.25 : 0.25
    else
        if t > 0.5
            t -= 0.5
        elseif t < -0.5
            t += 0.5
        end
    end
    shift = t * h
    return source0 + shift, field0 - shift
end

function _pic_solve_field(solver::PICPoissonSolver, x, y, source_grid, field_grid)
    nx, ny = solver.grid
    T = eltype(x)
    workspace = _pic_cpu_workspace(T, nx, ny)
    green_fft = _pic_green_fft(solver, T, source_grid, field_grid)
    return _pic_solve_field_with_green_fft!(
        workspace.left, solver, x, y, source_grid, green_fft, workspace,
    )
end

function _pic_green_fft(solver::PICPoissonSolver, ::Type{T}, source_grid, field_grid) where {T}
    nx, ny = solver.grid
    _validate_pic_grid(nx, ny)
    green = Matrix{T}(undef, 2nx, 2ny)
    _pic_green!(green, solver.green_type, T(field_grid.x0), T(field_grid.y0),
                T(source_grid.x0), T(source_grid.y0),
                T(source_grid.width) / (nx - 1), T(source_grid.height) / (ny - 1),
                nx, ny)
    return fft(green)
end

function _pic_green_fft!(workspace::_PICCPUWorkspace, solver::PICPoissonSolver,
                         ::Type{T}, source_grid, field_grid) where {T}
    nx, ny = solver.grid
    _validate_pic_grid(nx, ny)
    hx = T(source_grid.width) / (nx - 1)
    hy = T(source_grid.height) / (ny - 1)
    _pic_green!(workspace.green, solver.green_type, T(field_grid.x0), T(field_grid.y0),
                T(source_grid.x0), T(source_grid.y0), hx, hy, nx, ny)
    workspace.green_fft .= workspace.green
    workspace.fft_plan * workspace.green_fft
    return workspace.green_fft
end

function _pic_solve_field_with_green_fft!(field::_PICFieldWorkspace,
                                          solver::PICPoissonSolver, x, y,
                                          source_grid, green_fft,
                                          workspace::_PICCPUWorkspace)
    nx, ny = solver.grid
    T = eltype(x)
    hx = T(source_grid.width) / (nx - 1)
    hy = T(source_grid.height) / (ny - 1)
    charge = workspace.charge
    fill!(charge, zero(T))
    _pic_deposit!(charge, solver.deposit_method, x, y, T(source_grid.x0), T(source_grid.y0), hx, hy, nx, ny, workspace)
    spectral = workspace.spectral
    spectral .= charge
    workspace.fft_plan * spectral
    spectral .*= green_fft
    workspace.ifft_plan * spectral
    phi = field.phi
    for j in 1:ny, i in 1:nx
        @inbounds phi[i, j] = real(spectral[i, j])
    end
    _pic_field!(field.Ex, field.Ey, phi, hx, hy)
    return phi, field.Ex, field.Ey
end

function _pic_solve_drifted_field_with_green_fft!(field::_PICFieldWorkspace,
                                                  solver::PICPoissonSolver, source, drift_s,
                                                  source_grid, green_fft,
                                                  workspace::_PICCPUWorkspace)
    nx, ny = solver.grid
    T = eltype(source.x)
    hx = T(source_grid.width) / T(nx - 1)
    hy = T(source_grid.height) / T(ny - 1)
    charge = workspace.charge
    fill!(charge, zero(T))
    _pic_deposit_drifted!(
        charge, solver.deposit_method, source.x, source.px, source.y, source.py, T(drift_s),
        T(source_grid.x0), T(source_grid.y0), hx, hy, nx, ny, workspace,
    )
    spectral = workspace.spectral
    spectral .= charge
    workspace.fft_plan * spectral
    spectral .*= green_fft
    workspace.ifft_plan * spectral
    phi = field.phi
    for j in 1:ny, i in 1:nx
        @inbounds phi[i, j] = real(spectral[i, j])
    end
    _pic_field!(field.Ex, field.Ey, phi, hx, hy)
    return phi, field.Ex, field.Ey
end

function _pic_deposit!(charge, method, x, y, x0, y0, hx, hy, nx, ny)
    if Threads.nthreads() > 1 && length(x) >= _PIC_PARALLEL_DEPOSIT_MIN
        return _pic_deposit_threaded!(charge, method, x, y, x0, y0, hx, hy, nx, ny)
    end
    return _pic_deposit_serial!(charge, method, x, y, x0, y0, hx, hy, nx, ny)
end

function _pic_deposit!(charge, method, x, y, x0, y0, hx, hy, nx, ny,
                       workspace::_PICCPUWorkspace)
    if Threads.nthreads() > 1 && length(x) >= _PIC_PARALLEL_DEPOSIT_MIN
        return _pic_deposit_threaded!(charge, method, x, y, x0, y0, hx, hy, nx, ny, workspace)
    end
    return _pic_deposit_serial!(charge, method, x, y, x0, y0, hx, hy, nx, ny)
end

function _pic_deposit_drifted!(charge, method, x, px, y, py, drift_s, x0, y0, hx, hy, nx, ny,
                               workspace::_PICCPUWorkspace)
    if Threads.nthreads() > 1 && length(x) >= _PIC_PARALLEL_DEPOSIT_MIN
        return _pic_deposit_drifted_threaded!(charge, method, x, px, y, py, drift_s, x0, y0, hx, hy, nx, ny, workspace)
    end
    return _pic_deposit_drifted_serial!(charge, method, x, px, y, py, drift_s, x0, y0, hx, hy, nx, ny)
end

function _pic_deposit_serial!(charge, method, x, y, x0, y0, hx, hy, nx, ny)
    hxi = inv(hx); hyi = inv(hy)
    for i in eachindex(x)
        if Symbol(method) == :CIC
            ix, wx = _pic_cic_weights((x[i] - x0) * hxi, nx)
            iy, wy = _pic_cic_weights((y[i] - y0) * hyi, ny)
        else
            ix, wx = _pic_tsc_weights((x[i] - x0) * hxi, nx)
            iy, wy = _pic_tsc_weights((y[i] - y0) * hyi, ny)
        end
        for m in eachindex(wx), n in eachindex(wy)
            @inbounds charge[ix + m - 1, iy + n - 1] += wx[m] * wy[n]
        end
    end
    return charge
end

function _pic_deposit_drifted_serial!(charge, method, x, px, y, py, drift_s, x0, y0, hx, hy, nx, ny)
    hxi = inv(hx); hyi = inv(hy)
    for i in eachindex(x)
        xd = x[i] + px[i] * drift_s
        yd = y[i] + py[i] * drift_s
        if Symbol(method) == :CIC
            ix, wx = _pic_cic_weights((xd - x0) * hxi, nx)
            iy, wy = _pic_cic_weights((yd - y0) * hyi, ny)
        else
            ix, wx = _pic_tsc_weights((xd - x0) * hxi, nx)
            iy, wy = _pic_tsc_weights((yd - y0) * hyi, ny)
        end
        for m in eachindex(wx), n in eachindex(wy)
            @inbounds charge[ix + m - 1, iy + n - 1] += wx[m] * wy[n]
        end
    end
    return charge
end

function _pic_deposit_threaded!(charge, method, x, y, x0, y0, hx, hy, nx, ny)
    nchunks = Threads.nthreads()
    local_charge = [zero(charge) for _ in 1:nchunks]
    Threads.@threads :static for chunk in 1:nchunks
        first_i, last_i = _chunk_bounds(length(x), nchunks, chunk)
        local_grid = local_charge[chunk]
        _pic_deposit_range!(local_grid, method, x, y, x0, y0, hx, hy, nx, ny, first_i, last_i)
    end
    for local_grid in local_charge
        charge .+= local_grid
    end
    return charge
end

function _pic_deposit_threaded!(charge, method, x, y, x0, y0, hx, hy, nx, ny,
                                workspace::_PICCPUWorkspace)
    nchunks = Threads.nthreads()
    local_charge = workspace.local_charge
    length(local_charge) == nchunks || return _pic_deposit_threaded!(charge, method, x, y, x0, y0, hx, hy, nx, ny)
    Threads.@threads :static for chunk in 1:nchunks
        local_grid = local_charge[chunk]
        fill!(local_grid, zero(eltype(local_grid)))
        first_i, last_i = _chunk_bounds(length(x), nchunks, chunk)
        _pic_deposit_range!(local_grid, method, x, y, x0, y0, hx, hy, nx, ny, first_i, last_i)
    end
    for local_grid in local_charge
        charge .+= local_grid
    end
    return charge
end

function _pic_deposit_drifted_threaded!(charge, method, x, px, y, py, drift_s, x0, y0, hx, hy, nx, ny,
                                        workspace::_PICCPUWorkspace)
    nchunks = Threads.nthreads()
    local_charge = workspace.local_charge
    length(local_charge) == nchunks ||
        return _pic_deposit_drifted_serial!(charge, method, x, px, y, py, drift_s, x0, y0, hx, hy, nx, ny)
    Threads.@threads :static for chunk in 1:nchunks
        local_grid = local_charge[chunk]
        fill!(local_grid, zero(eltype(local_grid)))
        first_i, last_i = _chunk_bounds(length(x), nchunks, chunk)
        _pic_deposit_drifted_range!(
            local_grid, method, x, px, y, py, drift_s, x0, y0, hx, hy, nx, ny, first_i, last_i,
        )
    end
    for local_grid in local_charge
        charge .+= local_grid
    end
    return charge
end

function _pic_deposit_drifted_range!(charge, method, x, px, y, py, drift_s, x0, y0, hx, hy, nx, ny, first_i, last_i)
    hxi = inv(hx); hyi = inv(hy)
    for i in first_i:last_i
        xd = x[i] + px[i] * drift_s
        yd = y[i] + py[i] * drift_s
        if Symbol(method) == :CIC
            ix, wx = _pic_cic_weights((xd - x0) * hxi, nx)
            iy, wy = _pic_cic_weights((yd - y0) * hyi, ny)
        else
            ix, wx = _pic_tsc_weights((xd - x0) * hxi, nx)
            iy, wy = _pic_tsc_weights((yd - y0) * hyi, ny)
        end
        for m in eachindex(wx), n in eachindex(wy)
            @inbounds charge[ix + m - 1, iy + n - 1] += wx[m] * wy[n]
        end
    end
    return charge
end

function _pic_deposit_range!(charge, method, x, y, x0, y0, hx, hy, nx, ny, first_i, last_i)
    hxi = inv(hx); hyi = inv(hy)
    for i in first_i:last_i
        if Symbol(method) == :CIC
            ix, wx = _pic_cic_weights((x[i] - x0) * hxi, nx)
            iy, wy = _pic_cic_weights((y[i] - y0) * hyi, ny)
        else
            ix, wx = _pic_tsc_weights((x[i] - x0) * hxi, nx)
            iy, wy = _pic_tsc_weights((y[i] - y0) * hyi, ny)
        end
        for m in eachindex(wx), n in eachindex(wy)
            @inbounds charge[ix + m - 1, iy + n - 1] += wx[m] * wy[n]
        end
    end
    return charge
end

function _pic_cic_weights(u, n)
    base = clamp(floor(Int, u) + 1, 1, n - 1)
    f = clamp(u - floor(u), zero(u), one(u))
    return base, (one(f) - f, f)
end

function _pic_tsc_weights(u, n)
    ix = floor(Int, u)
    f = u - floor(u)
    if f < 0.5
        t = f * f
        w = (0.125 + 0.5 * (t - f), 0.75 - t, 0.125 + 0.5 * (t + f))
        base = ix
    else
        fr = one(f) - f
        t = fr * fr
        w = (0.125 + 0.5 * (t + fr), 0.75 - t, 0.125 + 0.5 * (t - fr))
        base = ix + 1
    end
    return clamp(base, 1, n - 2), w
end

@inline function _pic_atan_ratio(num, den)
    if den == 0
        num == 0 && return zero(promote_type(typeof(num), typeof(den)))
        return copysign(oftype(num / one(den), PI / 2), num)
    end
    return atan(num / den)
end

@inline function _pic_kernel_integral(x, y)
    r2 = x * x + y * y
    r2 = max(r2, eps(typeof(r2)))
    return (log(r2) - 3) * x * y + _pic_atan_ratio(y, x) * x * x + _pic_atan_ratio(x, y) * y * y
end

function _pic_green(green_type, field_x0, field_y0, source_x0, source_y0, hx, hy, nx, ny)
    T = promote_type(typeof(field_x0), typeof(hx))
    green = Matrix{T}(undef, 2nx, 2ny)
    _pic_green!(green, green_type, field_x0, field_y0, source_x0, source_y0, hx, hy, nx, ny)
    return green
end

function _pic_green!(green, green_type, field_x0, field_y0, source_x0, source_y0, hx, hy, nx, ny)
    T = eltype(green)
    half_hx = hx / 2
    half_hy = hy / 2
    hxihyi = T(-0.5) / (hx * hy)
    for i in 0:(2nx - 1), j in 0:(2ny - 1)
        ii = i < nx ? i : i - 2nx
        jj = j < ny ? j : j - 2ny
        x = field_x0 - source_x0 + ii * hx
        y = field_y0 - source_y0 + jj * hy
        if Symbol(green_type) == :integrated
            val = _pic_kernel_integral(x + half_hx, y + half_hy)
            val += _pic_kernel_integral(x - half_hx, y - half_hy)
            val -= _pic_kernel_integral(x + half_hx, y - half_hy)
            val -= _pic_kernel_integral(x - half_hx, y + half_hy)
            green[i + 1, j + 1] = hxihyi * val
        else
            r2 = max(x * x + y * y, eps(T))
            green[i + 1, j + 1] = T(-0.5) * log(r2)
        end
    end
    return green
end

function _pic_field(phi, hx, hy)
    nx, ny = size(phi)
    T = eltype(phi)
    Ex = Matrix{T}(undef, nx, ny)
    Ey = Matrix{T}(undef, nx, ny)
    _pic_field!(Ex, Ey, phi, hx, hy)
    return Ex, Ey
end

function _pic_field!(Ex, Ey, phi, hx, hy)
    nx, ny = size(phi)
    T = eltype(phi)
    hxi = inv(hx); hyi = inv(hy)
    for i in 1:nx
        Ey[i, 1] = hyi * (T(1.5) * phi[i, 1] - 2 * phi[i, 2] + T(0.5) * phi[i, 3])
        Ey[i, ny] = hyi * (-T(1.5) * phi[i, ny] + 2 * phi[i, ny - 1] - T(0.5) * phi[i, ny - 2])
        for j in 2:(ny - 1)
            Ey[i, j] = T(0.5) * hyi * (phi[i, j - 1] - phi[i, j + 1])
        end
    end
    for j in 1:ny
        Ex[1, j] = hxi * (T(1.5) * phi[1, j] - 2 * phi[2, j] + T(0.5) * phi[3, j])
        Ex[nx, j] = hxi * (-T(1.5) * phi[nx, j] + 2 * phi[nx - 1, j] - T(0.5) * phi[nx - 2, j])
        for i in 2:(nx - 1)
            Ex[i, j] = T(0.5) * hxi * (phi[i - 1, j] - phi[i + 1, j])
        end
    end
    return nothing
end

function _pic_interpolate_kick(solver, grid, x, y, phiL, ExL, EyL, phiR, ExR, EyR, zL, zR)
    nx, ny = solver.grid
    hx = grid.width / (nx - 1)
    hy = grid.height / (ny - 1)
    if Symbol(solver.deposit_method) == :CIC
        ix, wx = _pic_cic_weights((x - grid.x0) / hx, nx)
        iy, wy = _pic_cic_weights((y - grid.y0) / hy, ny)
    else
        ix, wx = _pic_tsc_weights((x - grid.x0) / hx, nx)
        iy, wy = _pic_tsc_weights((y - grid.y0) / hy, ny)
    end
    Kx = zero(x); Ky = zero(x); Kz = zero(x)
    for m in eachindex(wx), n in eachindex(wy)
        ii = ix + m - 1
        jj = iy + n - 1
        @inbounds begin
            w = wx[m] * wy[n]
            Kx += w * (zL * ExL[ii, jj] + zR * ExR[ii, jj])
            Ky += w * (zL * EyL[ii, jj] + zR * EyR[ii, jj])
            Kz += w * (phiL[ii, jj] - phiR[ii, jj])
        end
    end
    return Kx, Ky, Kz
end

function _pic_luminosity(solver::PICPoissonSolver, x1, y1, x2, y2, klum)
    nx, ny = _pic_luminosity_grid(solver)
    T = promote_type(eltype(x1), eltype(x2), typeof(klum))
    q1 = zeros(T, nx + 1, ny + 1)
    q2 = zeros(T, nx + 1, ny + 1)
    return _pic_luminosity!(solver, x1, y1, x2, y2, klum, q1, q2)
end

function _pic_luminosity(solver::PICPoissonSolver, x1, y1, x2, y2, klum,
                         workspace::_PICCPUWorkspace)
    nx, ny = _pic_luminosity_grid(solver)
    if size(workspace.luminosity_q1) != (nx + 1, ny + 1)
        return _pic_luminosity(solver, x1, y1, x2, y2, klum)
    end
    return _pic_luminosity!(solver, x1, y1, x2, y2, klum,
                            workspace.luminosity_q1, workspace.luminosity_q2)
end

function _pic_luminosity!(solver::PICPoissonSolver, x1, y1, x2, y2, klum, q1, q2)
    nx, ny = _pic_luminosity_grid(solver)
    T = promote_type(eltype(x1), eltype(x2), typeof(klum))
    xmin = min(minimum(x1), minimum(x2))
    xmax = max(maximum(x1), maximum(x2))
    ymin = min(minimum(y1), minimum(y2))
    ymax = max(maximum(y1), maximum(y2))
    width = max(T(xmax - xmin), eps(T))
    height = max(T(ymax - ymin), eps(T))
    tx = width / T(nx - 1.1)
    ty = height / T(ny - 1.1)
    width += T(0.1) * tx
    height += T(0.1) * ty
    xmin -= T(0.05) * tx
    ymin -= T(0.05) * ty
    hx = width / (nx - 1)
    hy = height / (ny - 1)
    hxi = inv(hx); hyi = inv(hy)
    fill!(q1, zero(T))
    fill!(q2, zero(T))
    method = _pic_luminosity_deposit_method(solver)
    _pic_deposit!(q1, method, x1, y1, xmin, ymin, hx, hy, nx + 1, ny + 1)
    _pic_deposit!(q2, method, x2, y2, xmin, ymin, hx, hy, nx + 1, ny + 1)
    lum = zero(T)
    for j in 1:ny, i in 1:nx
        @inbounds lum += q1[i, j] * q2[i, j]
    end
    return lum * T(klum) * hxi * hyi
end
