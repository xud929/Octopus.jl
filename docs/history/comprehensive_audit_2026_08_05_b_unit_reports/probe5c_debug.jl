using Octopus
using Printf
const O = Octopus
const DBG = Ref(0)

# Replica of Octopus._pic_collide! (:node branch) with the ONLY change being an
# added tally of particles that fall outside the mesh their charge is deposited
# on / their kick is read from, at the moment the pair is processed.  Nothing in
# the shipped code counts these: `workspace.dropped` is written only inside
# `_pic_interaction!`, and only under `grid_extent !== :extrema`, which
# `_validate_pic_solver` forbids for :node and :source_slice.

mutable struct Tally
    src_out::Int
    fld_out::Int
    charge_lost::Float64
    charge_total::Float64
end

function interaction_node_counted!(solver, source, param_source, field, param_field, kbb,
                                   workspace, gL, gR, tally)
    nsource = length(source.x); nfield = length(field.x)
    T = promote_type(eltype(source.x), eltype(field.x), typeof(kbb))
    sL = T(0.5) * (T(param_source.center) - T(param_field.lb))
    sR = T(0.5) * (T(param_source.center) - T(param_field.rb))
    for i in 1:nfield
        @inbounds begin
            s = T(0.5) * (field.z[i] - T(param_source.center))
            field.x[i] += s * field.px[i]; field.y[i] += s * field.py[i]
            if solver.longitudinal_kick
                field.pz[i] -= T(0.25) * (field.px[i]^2 + field.py[i]^2)
            end
        end
    end
    # --- instrumentation ---
    DBG[] += 1
    for (g, s) in ((gL, sL), (gR, sR))
        if DBG[] <= 4
            gg0 = g.source_grid
            n_out = O._pic_count_outside_box_drifted(source.x, source.px, source.y, source.py, s, s, gg0.x0, gg0.x0+gg0.width, gg0.y0, gg0.y0+gg0.height)
            @printf("   DBG call=%d drift=% .5g box_x=[% .5g,% .5g] src_x=[% .5g,% .5g] box_y=[% .5g,% .5g] src_y=[% .5g,% .5g] out=%d/%d\n", DBG[], s, gg0.x0, gg0.x0+gg0.width, minimum(source.x .+ source.px .* s), maximum(source.x .+ source.px .* s), gg0.y0, gg0.y0+gg0.height, minimum(source.y .+ source.py .* s), maximum(source.y .+ source.py .* s), n_out, length(source.x))
        end
        gg = g.source_grid
        tally.src_out += O._pic_count_outside_box_drifted(
            source.x, source.px, source.y, source.py, s, s,
            gg.x0, gg.x0 + gg.width, gg.y0, gg.y0 + gg.height)
        tally.charge_total += nsource
    end
    for g in (gL, gR)
        gg = g.field_grid
        tally.fld_out += O._pic_count_outside_box(
            field.x, field.y, gg.x0, gg.x0 + gg.width, gg.y0, gg.y0 + gg.height)
    end
    # --- end instrumentation; remainder is the shipped code verbatim ---
    phiL, ExL, EyL = O._pic_solve_drifted_field_with_green_fft!(
        workspace.left, solver, source, sL, gL.source_grid, gL.green_fft, workspace)
    tally.charge_lost += nsource - sum(workspace.charge)
    phiR, ExR, EyR = O._pic_solve_drifted_field_with_green_fft!(
        workspace.right, solver, source, sR, gR.source_grid, gR.green_fft, workspace)
    tally.charge_lost += nsource - sum(workspace.charge)
    phiZ = nothing
    if solver.longitudinal_kick
        nx, ny = solver.grid
        phiZ, _, _ = O._pic_solve_drifted_field_with_green_fft!(
            O._pic_mid_field!(workspace, nx, ny), solver, source, sR,
            gL.source_grid, gL.green_fft, workspace)
    end
    kick_scale = T(2) * T(kbb)
    hzi, zbias = O._slice_interpolation_parameters(T(param_field.lb), T(param_field.rb))
    for i in 1:nfield
        @inbounds begin
            zL = clamp(-T(field.z[i]) * hzi + zbias, zero(T), one(T)); zR = one(T) - zL
            x = field.x[i]; y = field.y[i]
            KxL, KyL, _ = O._pic_interpolate_kick(solver, gL.field_grid, x, y,
                                                  phiL, ExL, EyL, phiL, ExL, EyL, one(T), zero(T))
            KxR, KyR, _ = O._pic_interpolate_kick(solver, gR.field_grid, x, y,
                                                  phiR, ExR, EyR, phiR, ExR, EyR, one(T), zero(T))
            field.px[i] += kick_scale * (zL * KxL + zR * KxR)
            field.py[i] += kick_scale * (zL * KyL + zR * KyR)
            if solver.longitudinal_kick
                _, _, Kz = O._pic_interpolate_kick(solver, gL.field_grid, x, y,
                                                   phiL, ExL, EyL, phiZ, ExL, EyL, one(T), zero(T))
                field.pz[i] += kick_scale * Kz * hzi
            end
            s = T(0.5) * (T(param_source.center) - field.z[i])
            field.x[i] += s * field.px[i]; field.y[i] += s * field.py[i]
            if solver.longitudinal_kick
                field.pz[i] += T(0.25) * (field.px[i]^2 + field.py[i]^2)
            end
        end
    end
    sM = T(0.5) * (T(param_source.center) - T(param_field.center))
    vx = Vector{T}(undef, nsource); vy = Vector{T}(undef, nsource)
    for i in 1:nsource
        @inbounds vx[i] = source.x[i] + source.px[i] * sM
        @inbounds vy[i] = source.y[i] + source.py[i] * sM
    end
    return vx, vy
end

function collide_node_counted!(solver, beam1, beam2)
    O._validate_pic_solver(solver)
    T = O._pic_cpu_scalar_type(solver, beam1, beam2)
    nx, ny = solver.grid
    workspace = O._pic_cpu_workspace(T, nx, ny)
    slices1 = O.longitudinal_slices(beam1.rep, solver.slicing1)
    slices2 = O.longitudinal_slices(beam2.rep, solver.slicing2)
    kbb1 = O._pic_kbb1(solver, beam1, beam2); kbb2 = O._pic_kbb2(solver, beam1, beam2)
    tally = Tally(0, 0, 0.0, 0.0)
    node_cache = Dict{Tuple{Int,Int},Dict{Int,Any}}()
    O._pic_prebuild_node_caches!(node_cache, solver, T, beam1.rep, slices1, beam2.rep, slices2, 1)
    O._pic_prebuild_node_caches!(node_cache, solver, T, beam2.rep, slices2, beam1.rep, slices1, 2)
    for (_, i, j) in O._slice_collision_order(slices1, slices2)
        idx1 = slices1.indices[i]; idx2 = slices2.indices[j]
        (isempty(idx1) || isempty(idx2)) && continue
        param1 = (weight=slices1.weight[i], lb=slices1.boundary[i],
                  center=slices1.center[i], rb=slices1.boundary[i + 1])
        param2 = (weight=slices2.weight[j], lb=slices2.boundary[j],
                  center=slices2.center[j], rb=slices2.boundary[j + 1])
        coord1 = O._pic_extract_slice(beam1.rep, idx1); coord2 = O._pic_extract_slice(beam2.rep, idx2)
        field1 = O._pic_copy_coords(coord1); field2 = O._pic_copy_coords(coord2)
        nc1 = get!(() -> Dict{Int,Any}(), node_cache, (i, 1))
        nc2 = get!(() -> Dict{Int,Any}(), node_cache, (j, 2))
        gL1 = O._pic_node_grid!(nc1, solver, T, coord1, param1.center, beam2.rep,
                                slices2.indices, slices2.boundary, j)
        gR1 = O._pic_node_grid!(nc1, solver, T, coord1, param1.center, beam2.rep,
                                slices2.indices, slices2.boundary, j + 1)
        gL2 = O._pic_node_grid!(nc2, solver, T, coord2, param2.center, beam1.rep,
                                slices1.indices, slices1.boundary, i)
        gR2 = O._pic_node_grid!(nc2, solver, T, coord2, param2.center, beam1.rep,
                                slices1.indices, slices1.boundary, i + 1)
        (gL1 === nothing || gR1 === nothing || gL2 === nothing || gR2 === nothing) && continue
        interaction_node_counted!(solver, coord1, param1, field2, param2, kbb2, workspace, gL1, gR1, tally)
        interaction_node_counted!(solver, coord2, param2, field1, param1, kbb1, workspace, gL2, gR2, tally)
        O._pic_store_slice!(beam1.rep, idx1, field1)
        O._pic_store_slice!(beam2.rep, idx2, field2)
    end
    return tally, workspace
end

# Realistic-ish flat-beam-ish setup, 15 slices; kbb is swept.
function mkbeam(n; seed=1, sx=1.0e-4, sy=1.0e-5, sz=2.0e-2, spx=1.0e-5, spy=1.0e-6)
    s(scale, phase, k) = [scale * sin(k * i + phase) for i in 1:n]
    rep = O.Phase6DRep(s(sx, 0.0, 0.7), s(spx, 0.3, 1.1), s(sy, 0.9, 0.53),
                       s(spy, 1.2, 1.7), s(sz, 2.0, 0.31), s(1.0e-4, 2.5, 2.3))
    params = O.BeamParams{Float64}(charge=1.0, mc2=1.0, E0=1.0, r0=1.0e-9, npart=n)
    return O.Beam{O.CPUThreadsBackend,typeof(params),typeof(rep)}(params, rep)
end

println("interaction_grid = :node — mesh built at TURN START, deposits happen after intra-turn kicks")
println("kbb        src_particles_outside  field_particles_outside  charge_lost  workspace.dropped(real collide)")
for kbb in (1.0e-6,)
    solver = O.PICPoissonSolver(kbb1=kbb, kbb2=kbb, luminosity_scale=1.0, grid=(32, 32),
                                green_cache=:none, interaction_grid=:node,
                                slicing=O.LongitudinalSlicing(nslices=15, method=:equal_count))
    b1 = mkbeam(3000); b2 = mkbeam(3000; seed=2)
    tally, _ = collide_node_counted!(solver, b1, b2)
    # what the shipped code reports for the same run
    c1 = mkbeam(3000); c2 = mkbeam(3000; seed=2)
    T = O._pic_cpu_scalar_type(solver, c1, c2)
    ws = O._pic_cpu_workspace(T, solver.grid...)
    O._pic_collide!(solver, c1, c2, nothing, ws, O._pic_green_cache(solver, T))
    @printf("%-9.3g  %-21d  %-23d  %-11.6g  %d\n",
            kbb, tally.src_out, tally.fld_out, tally.charge_lost, ws.dropped[])
end
