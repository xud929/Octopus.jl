using Octopus
using Printf
const O = Octopus

function mkbeam(n; sx=1.0e-4, sy=1.0e-5, sz=2.0e-2, spx=1.0e-5, spy=1.0e-6)
    s(scale, phase, k) = [scale * sin(k * i + phase) for i in 1:n]
    rep = O.Phase6DRep(s(sx, 0.0, 0.7), s(spx, 0.3, 1.1), s(sy, 0.9, 0.53),
                       s(spy, 1.2, 1.7), s(sz, 2.0, 0.31), s(1.0e-4, 2.5, 2.3))
    params = O.BeamParams{Float64}(charge=1.0, mc2=1.0, E0=1.0, r0=1.0e-9, npart=n)
    return O.Beam{O.CPUThreadsBackend,typeof(params),typeof(rep)}(params, rep)
end

solver = O.PICPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0, grid=(32, 32),
                            green_cache=:none, interaction_grid=:node,
                            slicing=O.LongitudinalSlicing(nslices=15, method=:equal_count))
b1 = mkbeam(3000); b2 = mkbeam(3000)
T = Float64
s1 = O.longitudinal_slices(b1.rep, solver.slicing1)
s2 = O.longitudinal_slices(b2.rep, solver.slicing2)
println("min_transverse_extent = ", solver.min_transverse_extent)
nc = Dict{Int,Any}()
src = O._pic_extract_slice(b1.rep, s1.indices[1])
O._pic_build_node_grids!(nc, solver, T, src, s1.center[1], b2.rep, s2.indices, s2.boundary)
println("nodes built: ", sort(collect(keys(nc))))
for b in (1, 8, 16)
    g = nc[b]
    d = 0.5 * (s1.center[1] - s2.boundary[b])
    xs = src.x .+ src.px .* d
    ys = src.y .+ src.py .* d
    @printf("node %2d drift=% .4g\n", b, d)
    @printf("   source_grid x0=% .6g w=% .6g  -> [% .6g, % .6g]   src x in [% .6g, % .6g]\n",
            g.source_grid.x0, g.source_grid.width,
            g.source_grid.x0, g.source_grid.x0 + g.source_grid.width,
            minimum(xs), maximum(xs))
    @printf("   source_grid y0=% .6g h=% .6g  -> [% .6g, % .6g]   src y in [% .6g, % .6g]\n",
            g.source_grid.y0, g.source_grid.height,
            g.source_grid.y0, g.source_grid.y0 + g.source_grid.height,
            minimum(ys), maximum(ys))
    nx, ny = solver.grid
    hx = g.source_grid.width / (nx - 1); hy = g.source_grid.height / (ny - 1)
    u = (xs .- g.source_grid.x0) ./ hx
    v = (ys .- g.source_grid.y0) ./ hy
    @printf("   u in [%.3f, %.3f] (valid [0,%d])   v in [%.3f, %.3f] (valid [0,%d])\n",
            minimum(u), maximum(u), nx - 1, minimum(v), maximum(v), ny - 1)
    println("   outside count = ", O._pic_count_outside_box_drifted(
        src.x, src.px, src.y, src.py, d, d,
        g.source_grid.x0, g.source_grid.x0 + g.source_grid.width,
        g.source_grid.y0, g.source_grid.y0 + g.source_grid.height), " of ", length(src.x))
end
