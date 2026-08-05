using Octopus
using Printf
const O = Octopus

println("=== (A) luminosity deposit allocates per call above _PIC_PARALLEL_DEPOSIT_MIN ===")
println("_PIC_PARALLEL_DEPOSIT_MIN = ", O._PIC_PARALLEL_DEPOSIT_MIN,
        "   _PIC_DEPOSIT_CHUNKS = ", O._PIC_DEPOSIT_CHUNKS)
for (npair, grid) in ((4095, 128), (4096, 128), (68000, 128), (68000, 64))
    solver = O.PICPoissonSolver(kbb1=1.0, kbb2=1.0, luminosity_scale=1.0, grid=(grid, grid))
    x1 = [1.0e-4 * sin(0.7i) for i in 1:npair]; y1 = [1.0e-5 * sin(0.3i) for i in 1:npair]
    x2 = copy(x1); y2 = copy(y1)
    ws = O._pic_cpu_workspace(Float64, grid, grid)
    O._pic_luminosity(solver, x1, y1, x2, y2, 1.0, ws)   # warm up
    a = @allocated O._pic_luminosity(solver, x1, y1, x2, y2, 1.0, ws)
    t = @elapsed for _ in 1:5
        O._pic_luminosity(solver, x1, y1, x2, y2, 1.0, ws)
    end
    @printf("  n/slice=%-7d grid=%-4d  allocated per luminosity call = %.3f MB   %.3f ms/call\n",
            npair, grid, a / 2^20, 1000 * t / 5)
end

println("\n=== (B) :node staleness control — same tally against a FRESH mesh ===")
ele = (charge=-1.0, mass=EMASS_EV, energy=10.0e9, n_particle=1.7203e11, cutoff=5.0,
       sigma=(106.0e-6, 9.5e-6, 0.7e-2), beta=(0.55, 0.056, 0.7e-2 / 5.5e-4),
       alpha=(0.0, 0.0, 0.0))
pro = (charge=1.0, mass=PMASS_EV, energy=275.0e9, n_particle=0.6881e11, cutoff=5.0,
       sigma=(95.0e-6, 8.5e-6, 6.0e-2), beta=(0.8, 0.072, 6.0e-2 / 6.6e-4),
       alpha=(0.0, 0.0, 0.0))
NPART = parse(Int, get(ENV, "NP", "30000")); NSLICES = 15; GRID = 64
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
solver = O.PICPoissonSolver(; slicing=slicing, grid=(GRID, GRID), deposit_method=:CIC,
                            green_type=:integrated, green_cache=:none,
                            longitudinal_kick=true, interaction_grid=:node)
function runB()
    b1, b2 = mk()
    T = Float64
    ws = O._pic_cpu_workspace(T, GRID, GRID)
    s1 = O.longitudinal_slices(b1.rep, solver.slicing1)
    s2 = O.longitudinal_slices(b2.rep, solver.slicing2)
    kbb1 = O._pic_kbb1(solver, b1, b2); kbb2 = O._pic_kbb2(solver, b1, b2)
    nc_all = Dict{Tuple{Int,Int},Dict{Int,Any}}()
    O._pic_prebuild_node_caches!(nc_all, solver, T, b1.rep, s1, b2.rep, s2, 1)
    O._pic_prebuild_node_caches!(nc_all, solver, T, b2.rep, s2, b1.rep, s1, 2)
    stale_out = 0; fresh_out = 0; total = 0
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
        for (src, ps, fld, pf, kbb, gL, gR, rep_f, ind_f, bnd_f, node) in
            ((c1, p1, f2, p2, kbb2, gL1, gR1, b2.rep, s2.indices, s2.boundary, j),
             (c2, p2, f1, p1, kbb1, gL2, gR2, b1.rep, s1.indices, s1.boundary, i))
            sL = 0.5 * (ps.center - pf.lb); sR = 0.5 * (ps.center - pf.rb)
            # stale mesh (the shipped one, built at turn start)
            for (g, s) in ((gL, sL), (gR, sR))
                gg = g.source_grid
                stale_out += O._pic_count_outside_box_drifted(
                    src.x, src.px, src.y, src.py, s, s,
                    gg.x0, gg.x0 + gg.width, gg.y0, gg.y0 + gg.height)
                total += length(src.x)
            end
            # control: the same node meshes rebuilt from the CURRENT beam state
            fresh = Dict{Int,Any}()
            O._pic_build_node_grids!(fresh, solver, T, src, ps.center, rep_f, ind_f, bnd_f)
            for (b, s) in ((node, sL), (node + 1, sR))
                g = get(fresh, b, nothing); g === nothing && continue
                gg = g.source_grid
                fresh_out += O._pic_count_outside_box_drifted(
                    src.x, src.px, src.y, src.py, s, s,
                    gg.x0, gg.x0 + gg.width, gg.y0, gg.y0 + gg.height)
            end
            O._pic_interaction_node!(solver, src, ps, fld, pf, kbb, ws, gL, gR)
        end
        O._pic_store_slice!(b1.rep, idx1, f1); O._pic_store_slice!(b2.rep, idx2, f2)
    end
    @printf("  source deposits outside the TURN-START mesh: %d of %d\n", stale_out, total)
    @printf("  source deposits outside a mesh REBUILT at collision time: %d of %d\n", fresh_out, total)
    
end
runB()
