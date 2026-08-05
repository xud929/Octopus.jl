using Octopus
using Printf
const O = Octopus

println("=== U5-7: _pic_cic_weights at the exact top edge u = n-1 ===")
for (u, n) in ((4.0, 5), (0.0, 5), (2.0, 5), (3.5, 5), (31.0, 32))
    b, w = O._pic_cic_weights(u, n)
    @printf("  u=%-5g n=%-3d -> base=%d weights=(%g, %g)   charge nodes %d,%d\n", u, n, b, w[1], w[2], b, b + 1)
end
# centre of mass of a single-particle deposit
for u in (2.0, 4.0)
    c = zeros(10, 10)
    O._pic_deposit_serial!(c, :CIC, [u], [u], 0.0, 0.0, 1.0, 1.0, 5, 5)
    com = sum((i - 1) * c[i, j] for i in 1:10, j in 1:10) / sum(c)
    @printf("  particle at u=%g (n=5): charge centre of mass = %g (should equal u)\n", u, com)
end

println("\n=== U5-6/U5-5: dropped counter is per PARTICLE and covers the SOURCE side ===")
# corner escapee: one field particle outside in BOTH x and y
solver = O.PICPoissonSolver(kbb1=1.0, kbb2=1.0, luminosity_scale=1.0, grid=(16, 16),
                            grid_extent=:sigma, grid_extent_sigma=2.0, green_cache=:none)
n = 4001
src = (x=[1.0e-4 * sin(0.7i) for i in 1:n], px=zeros(n),
       y=[1.0e-4 * sin(0.31i) for i in 1:n], py=zeros(n),
       z=zeros(n), pz=zeros(n))
fld = (x=copy(src.x), px=zeros(n), y=copy(src.y), py=zeros(n), z=zeros(n), pz=zeros(n))
# push one particle far out in both axes
src2 = (x=copy(src.x), px=copy(src.px), y=copy(src.y), py=copy(src.py), z=copy(src.z), pz=copy(src.pz))
src2.x[1] = 3.0e-3; src2.y[1] = 3.0e-3
fld2 = (x=copy(fld.x), px=copy(fld.px), y=copy(fld.y), py=copy(fld.py), z=copy(fld.z), pz=copy(fld.pz))
fld2.x[1] = 3.0e-3; fld2.y[1] = 3.0e-3
p = (weight=1.0, lb=-1.0e-3, center=0.0, rb=1.0e-3)
ws = O._pic_cpu_workspace(Float64, 16, 16)
ws.dropped[] = 0
O._pic_interaction!(solver, src2, p, fld2, p, 1.0, ws, nothing, (1, 1, 1))
@printf("  one source AND one field particle outside in BOTH axes -> dropped = %d (per-particle count would be 2)\n",
        ws.dropped[])

# source-only escapee: charge conservation vs the counter
ws.dropped[] = 0
src3 = (x=copy(src.x), px=copy(src.px), y=copy(src.y), py=copy(src.py), z=copy(src.z), pz=copy(src.pz))
src3.x[1] = 3.0e-3
fld3 = (x=copy(fld.x), px=copy(fld.px), y=copy(fld.y), py=copy(fld.py), z=copy(fld.z), pz=copy(fld.pz))
O._pic_interaction!(solver, src3, p, fld3, p, 1.0, ws, nothing, (1, 1, 1))
@printf("  one SOURCE-only escapee (field fully inside) -> dropped = %d, deposited charge = %.12g of %d\n",
        ws.dropped[], sum(ws.charge), n)

println("\n=== U5-8: luminosity overlap sum covers the full deposit extent ===")
for meth in (:CIC, :TSC)
    s = O.PICPoissonSolver(kbb1=1.0, kbb2=1.0, luminosity_scale=1.0, grid=(16, 16),
                           deposit_method=meth)
    np = 200
    x = [1.0e-4 * (2 * (i - 1) / (np - 1) - 1) for i in 1:np]
    y = [1.0e-5 * (2 * (i - 1) / (np - 1) - 1) for i in 1:np]
    nx, ny = O._pic_luminosity_grid(s)
    q1 = zeros(nx + 1, ny + 1); q2 = zeros(nx + 1, ny + 1)
    lum_full = O._pic_luminosity!(s, x, y, x, y, 1.0, q1, q2)
    # excluded row/col charge under the OLD 1:nx,1:ny sum
    excl = sum(q1) - sum(q1[i, j] for i in 1:nx, j in 1:ny)
    old = 0.0
    for j in 1:ny, i in 1:nx
        old += q1[i, j] * q2[i, j]
    end
    scale = lum_full == 0 ? 1.0 : lum_full
    @printf("  %s: charge in the previously-excluded row/col = %.6g of %d;  relative luminosity change = %.3g\n",
            meth, excl, np, (lum_full - old * (lum_full / (lum_full))) / scale * 0 +
            (lum_full - old * (lum_full / lum_full)) / scale)
    @printf("      full-extent lum = %.12g   old-extent lum (same q) = %.12g   deficit = %.3g\n",
            lum_full, old * lum_full / lum_full, (lum_full - old * lum_full / lum_full) / scale)
end

println("\n=== U5-3 / F11: configuration combinations that must now throw ===")
function try_ctor(f, tag)
    try
        f(); @printf("  %-58s NO THROW\n", tag)
    catch e
        @printf("  %-58s throws %s\n", tag, typeof(e))
    end
end
try_ctor("node + quadratic (validate)") do
    O._validate_pic_solver(O.PICPoissonSolver(grid=(16, 16), interaction_grid=:node,
                                              slice_interpolation=:quadratic))
end
try_ctor("node + linear (validate)") do
    O._validate_pic_solver(O.PICPoissonSolver(grid=(16, 16), interaction_grid=:node))
end
try_ctor("node + grid_extent=:sigma (validate)") do
    O._validate_pic_solver(O.PICPoissonSolver(grid=(16, 16), interaction_grid=:node,
                                              grid_extent=:sigma))
end
for (bm, ia, bf, wf, iw) in ((:wavefront, true, true, true, true),
                             (:wavefront, true, true, true, false),
                             (:wavefront, true, false, true, true),
                             (:wavefront, true, true, false, true),
                             (:wavefront, false, true, true, true),
                             (:sequential, false, false, false, false),
                             (:sequential, true, false, false, false))
    try_ctor("CUDA :node batch=$bm async=$ia batch_fft=$bf wf_fft=$wf idx=$iw") do
        O._require_cuda_pic_options(O.PICPoissonSolver(grid=(16, 16), interaction_grid=:node,
            batch_mode=bm, cuda_async=ia, cuda_batch_fft=bf,
            cuda_wavefront_fft=wf, cuda_indexed_wavefront=iw))
    end
end
