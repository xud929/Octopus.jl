using Octopus
using Printf
const O = Octopus

# EIC-like flat pair, copied from validation/slice_interpolation_emittance_growth.jl
ele = (charge=-1.0, mass=EMASS_EV, energy=10.0e9, n_particle=1.7203e11, cutoff=5.0,
       sigma=(106.0e-6, 9.5e-6, 0.7e-2), beta=(0.55, 0.056, 0.7e-2 / 5.5e-4),
       alpha=(0.0, 0.0, 0.0), tune=(0.08, 0.14, -0.069))
pro = (charge=1.0, mass=PMASS_EV, energy=275.0e9, n_particle=0.6881e11, cutoff=5.0,
       sigma=(95.0e-6, 8.5e-6, 6.0e-2), beta=(0.8, 0.072, 6.0e-2 / 6.6e-4),
       alpha=(0.0, 0.0, 0.0), tune=(0.228, 0.210, -0.01))

NPART = parse(Int, get(ENV, "NP", "30000"))
NSLICES = 15
GRID = 64

set_global_rng!(seed=17, method=:philox)
policy = CPUThreadsExecutionPolicy()
mk() = (Beam(NPART, policy, Float64; beta=ele.beta, alpha=ele.alpha, sigma=ele.sigma,
             cutoff=ele.cutoff, rng_id=1, charge=ele.charge, mc2=ele.mass, E0=ele.energy,
             r0=RE * ME0 / ele.mass, npart=ele.n_particle),
        Beam(NPART, policy, Float64; beta=pro.beta, alpha=pro.alpha, sigma=pro.sigma,
             cutoff=pro.cutoff, rng_id=2, charge=pro.charge, mc2=pro.mass, E0=pro.energy,
             r0=RE * ME0 / pro.mass, npart=pro.n_particle))

slicing = O.LongitudinalSlicing(; method=:normal_quantile, nslices=NSLICES,
                                center_position=:centroid)

mutable struct Tally
    src_out::Int
    fld_out::Int
    src_total::Int
    charge_lost::Float64
    charge_total::Float64
end

# ---- :node replica of _pic_collide! with an added out-of-mesh tally ----------
function node_tally(solver, b1, b2)
    O._validate_pic_solver(solver)
    T = O._pic_cpu_scalar_type(solver, b1, b2)
    workspace = O._pic_cpu_workspace(T, solver.grid...)
    s1 = O.longitudinal_slices(b1.rep, solver.slicing1)
    s2 = O.longitudinal_slices(b2.rep, solver.slicing2)
    kbb1 = O._pic_kbb1(solver, b1, b2); kbb2 = O._pic_kbb2(solver, b1, b2)
    t = Tally(0, 0, 0, 0.0, 0.0)
    nc_all = Dict{Tuple{Int,Int},Dict{Int,Any}}()
    O._pic_prebuild_node_caches!(nc_all, solver, T, b1.rep, s1, b2.rep, s2, 1)
    O._pic_prebuild_node_caches!(nc_all, solver, T, b2.rep, s2, b1.rep, s1, 2)
    for (_, i, j) in O._slice_collision_order(s1, s2)
        idx1 = s1.indices[i]; idx2 = s2.indices[j]
        (isempty(idx1) || isempty(idx2)) && continue
        p1 = (weight=s1.weight[i], lb=s1.boundary[i], center=s1.center[i], rb=s1.boundary[i+1])
        p2 = (weight=s2.weight[j], lb=s2.boundary[j], center=s2.center[j], rb=s2.boundary[j+1])
        c1 = O._pic_extract_slice(b1.rep, idx1); c2 = O._pic_extract_slice(b2.rep, idx2)
        f1 = O._pic_copy_coords(c1); f2 = O._pic_copy_coords(c2)
        nc1 = nc_all[(i, 1)]; nc2 = nc_all[(j, 2)]
        gL1 = get(nc1, j, nothing); gR1 = get(nc1, j + 1, nothing)
        gL2 = get(nc2, i, nothing); gR2 = get(nc2, i + 1, nothing)
        (gL1 === nothing || gR1 === nothing || gL2 === nothing || gR2 === nothing) && continue
        for (src, ps, fld, pf, kbb, gL, gR) in ((c1, p1, f2, p2, kbb2, gL1, gR1),
                                                (c2, p2, f1, p1, kbb1, gL2, gR2))
            sL = 0.5 * (ps.center - pf.lb); sR = 0.5 * (ps.center - pf.rb)
            for (g, s) in ((gL, sL), (gR, sR))
                gg = g.source_grid
                t.src_out += O._pic_count_outside_box_drifted(
                    src.x, src.px, src.y, src.py, s, s,
                    gg.x0, gg.x0 + gg.width, gg.y0, gg.y0 + gg.height)
                t.src_total += length(src.x)
                O._pic_solve_drifted_field_with_green_fft!(
                    workspace.left, solver, src, s, gg, g.green_fft, workspace)
                t.charge_lost += length(src.x) - sum(workspace.charge)
                t.charge_total += length(src.x)
            end
            for g in (gL, gR)
                gg = g.field_grid
                xd = [fld.x[k] + 0.5 * (fld.z[k] - ps.center) * fld.px[k] for k in eachindex(fld.x)]
                yd = [fld.y[k] + 0.5 * (fld.z[k] - ps.center) * fld.py[k] for k in eachindex(fld.y)]
                t.fld_out += O._pic_count_outside_box(xd, yd, gg.x0, gg.x0 + gg.width,
                                                      gg.y0, gg.y0 + gg.height)
            end
            O._pic_interaction_node!(solver, src, ps, fld, pf, kbb, workspace, gL, gR)
        end
        O._pic_store_slice!(b1.rep, idx1, f1); O._pic_store_slice!(b2.rep, idx2, f2)
    end
    return t
end

# ---- :source_slice replica -------------------------------------------------
function source_slice_tally(solver, b1, b2)
    O._validate_pic_solver(solver)
    T = O._pic_cpu_scalar_type(solver, b1, b2)
    workspace = O._pic_cpu_workspace(T, solver.grid...)
    green_cache = O._pic_green_cache(solver, T)
    s1 = O.longitudinal_slices(b1.rep, solver.slicing1)
    s2 = O.longitudinal_slices(b2.rep, solver.slicing2)
    kbb1 = O._pic_kbb1(solver, b1, b2); kbb2 = O._pic_kbb2(solver, b1, b2)
    t = Tally(0, 0, 0, 0.0, 0.0)
    ub = Dict{Tuple{Int,Int},Any}()
    for (_, i, j) in O._slice_collision_order(s1, s2)
        idx1 = s1.indices[i]; idx2 = s2.indices[j]
        (isempty(idx1) || isempty(idx2)) && continue
        p1 = (weight=s1.weight[i], lb=s1.boundary[i], center=s1.center[i], rb=s1.boundary[i+1])
        p2 = (weight=s2.weight[j], lb=s2.boundary[j], center=s2.center[j], rb=s2.boundary[j+1])
        c1 = O._pic_extract_slice(b1.rep, idx1); c2 = O._pic_extract_slice(b2.rep, idx2)
        f1 = O._pic_copy_coords(c1); f2 = O._pic_copy_coords(c2)
        ov1 = get!(() -> O._pic_union_bounds(c1, p1.center, b2.rep, s2.indices), ub, (i, 1))
        ov2 = get!(() -> O._pic_union_bounds(c2, p2.center, b1.rep, s1.indices), ub, (j, 2))
        for (src, ps, fld, pf, kbb, ov, key) in ((c1, p1, f2, p2, kbb2, ov1, (i, 0, 1)),
                                                 (c2, p2, f1, p1, kbb1, ov2, (j, 0, 2)))
            sb, fb = ov
            sg, fg = O._pic_interaction_grids(solver, sb.xmin, sb.xmax, sb.ymin, sb.ymax,
                                              fb.xmin, fb.xmax, fb.ymin, fb.ymax)
            sL = 0.5 * (ps.center - pf.lb); sR = 0.5 * (ps.center - pf.rb)
            t.src_out += O._pic_count_outside_box_drifted(
                src.x, src.px, src.y, src.py, sL, sR,
                sg.x0, sg.x0 + sg.width, sg.y0, sg.y0 + sg.height)
            t.src_total += length(src.x)
            xd = [fld.x[k] + 0.5 * (fld.z[k] - ps.center) * fld.px[k] for k in eachindex(fld.x)]
            yd = [fld.y[k] + 0.5 * (fld.z[k] - ps.center) * fld.py[k] for k in eachindex(fld.y)]
            t.fld_out += O._pic_count_outside_box(xd, yd, fg.x0, fg.x0 + fg.width,
                                                  fg.y0, fg.y0 + fg.height)
            O._pic_interaction!(solver, src, ps, fld, pf, kbb, workspace, green_cache, key, ov)
        end
        O._pic_store_slice!(b1.rep, idx1, f1); O._pic_store_slice!(b2.rep, idx2, f2)
    end
    return t
end

for mode in (:node, :source_slice)
    solver = O.PICPoissonSolver(; slicing=slicing, grid=(GRID, GRID), deposit_method=:CIC,
                                green_type=:integrated, green_cache=:none,
                                longitudinal_kick=true, interaction_grid=mode)
    be, bp = mk()
    t = mode === :node ? node_tally(solver, be, bp) : source_slice_tally(solver, be, bp)
    ws = O._pic_cpu_workspace(Float64, GRID, GRID)
    be2, bp2 = mk()
    O._pic_collide!(solver, be2, bp2, nothing, ws, O._pic_green_cache(solver, Float64))
    @printf("%-14s src outside mesh %d/%d (%.4g%%)  field outside %d  charge lost %.6g of %.6g (%.4g%%)  shipped workspace.dropped = %d\n",
            mode, t.src_out, t.src_total, 100 * t.src_out / max(t.src_total, 1),
            t.fld_out, t.charge_lost, t.charge_total,
            100 * t.charge_lost / max(t.charge_total, 1), ws.dropped[])
end
