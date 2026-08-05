using Octopus, CUDA, Random
const O = Octopus
const CUDABackend = Octopus.CUDABackend

println("="^78); println("T1: grid-cache host twins  CUDA vs CPU (exact agreement expected)"); println("="^78)
for T in (Float64, Float32)
    rng = MersenneTwister(7)
    solver = PICPoissonSolver(grid=(32, 32))
    mismatch_size = 0; mismatch_cover = 0; mismatch_expand = 0; n = 0
    for _ in 1:200_000
        w = T(exp(4 * randn(rng))); h = T(exp(4 * randn(rng)))
        x0 = T(randn(rng)); y0 = T(randn(rng))
        cached = (x0=x0, y0=y0, width=w, height=h)
        req = (x0=T(x0 + 0.1 * randn(rng)), y0=T(y0 + 0.1 * randn(rng)),
               width=T(w * (0.2 + 1.2 * rand(rng))), height=T(h * (0.2 + 1.2 * rand(rng))))
        mr = T(0.5)
        a = O._cuda_pic_grid_size_usable(cached, req, mr)
        b = O._pic_grid_size_usable(cached, req, mr)
        a == b || (mismatch_size += 1)
        bx = T(x0 + w * rand(rng)); bX = T(bx + w * 0.3 * rand(rng))
        by = T(y0 + h * rand(rng)); bY = T(by + h * 0.3 * rand(rng))
        bnds = (xmin=bx, xmax=bX, ymin=by, ymax=bY)
        c = O._cuda_pic_grid_covers_bounds(solver, cached, bnds)
        d = O._pic_grid_covers_bounds(solver, cached, bnds)
        c == d || (mismatch_cover += 1)
        for g in (T(0), T(0.25), T(1.0))
            e1 = O._cuda_pic_expand_grid_by(cached, T(1) + g)
            e2 = O._pic_expand_grid_by(cached, T(1) + g)
            (e1.x0 === e2.x0 && e1.y0 === e2.y0 && e1.width === e2.width && e1.height === e2.height) ||
                (mismatch_expand += 1)
        end
        n += 1
    end
    println("  $T  n=$n  size_usable_mismatch=$mismatch_size  covers_bounds_mismatch=$mismatch_cover  expand_mismatch=$mismatch_expand")
end

println()
println("="^78); println("T2: CUDA interaction deposit conserves charge on the meshes the code builds"); println("="^78)
# Reproduce _cuda_pic_prepare_interaction's grid sizing, then deposit and sum.
for T in (Float64, Float32)
  for method in (:CIC, :TSC)
    for growth in (T(0.0), T(0.25))
        solver = PICPoissonSolver(grid=(32, 32), deposit_method=method,
                                  slice_pair_green_growth=growth)
        rng = MersenneTwister(11)
        n = 20_000
        x = T.(1e-4 .* randn(rng, n)); px = T.(1e-5 .* randn(rng, n))
        y = T.(1e-5 .* randn(rng, n)); py = T.(1e-6 .* randn(rng, n))
        sL = T(1e-3); sR = T(-2e-3)
        xl = x .+ px .* sL; xr = x .+ px .* sR
        yl = y .+ py .* sL; yr = y .+ py .* sR
        sxmin = min(minimum(xl), minimum(xr)); sxmax = max(maximum(xl), maximum(xr))
        symin = min(minimum(yl), minimum(yr)); symax = max(maximum(yl), maximum(yr))
        sg, fg = O._pic_interaction_grids(solver, sxmin, sxmax, symin, symax,
                                          sxmin, sxmax, symin, symax)
        if growth > 0
            sg = O._cuda_pic_expand_grid_by(sg, T(1) + growth)
            fg2 = O._cuda_pic_expand_grid_by(fg, T(1) + growth)
            sg, _ = O._pic_realign_expanded_grids(solver.green_type, sg, fg2, solver.grid...)
        end
        nx, ny = solver.grid
        hx = T(sg.width) / T(nx - 1); hy = T(sg.height) / T(ny - 1)
        charge = CUDA.zeros(T, 2nx, 2ny)
        code = method === :CIC ? Int32(1) : Int32(2)
        dx = CUDA.CuArray(x); dpx = CUDA.CuArray(px)
        dy = CUDA.CuArray(y); dpy = CUDA.CuArray(py)
        CUDA.@cuda threads=256 blocks=cld(n, 256) O._cuda_pic_deposit_drifted_nomask_kernel!(
            charge, dx, dpx, dy, dpy, sL, T(sg.x0), T(sg.y0), hx, hy,
            Int32(nx), Int32(ny), code)
        CUDA.synchronize()
        tot = sum(Array(charge))
        println("  $T $method growth=$growth   deposited=", tot, "  expected=", n,
                "  rel_deficit=", (n - Float64(tot)) / n)
    end
  end
end

println()
println("="^78); println("T3: CUDA luminosity deposit conserves charge on the (n+1)x(n+1) plane"); println("="^78)
for T in (Float64, Float32), method in (:CIC, :TSC)
    solver = PICPoissonSolver(grid=(32, 32), luminosity_deposit_method=method)
    nx, ny = O._pic_luminosity_grid(solver)
    rng = MersenneTwister(3); n = 20_000
    x = T.(1e-4 .* randn(rng, n)); y = T.(1e-5 .* randn(rng, n))
    xmin = minimum(x); xmax = maximum(x); ymin = minimum(y); ymax = maximum(y)
    width, height = O._pic_resolve_transverse_extent(solver, T(xmax - xmin), T(ymax - ymin), "probe")
    tx = width / T(nx - 1.1); ty = height / T(ny - 1.1)
    width += T(0.1) * tx; height += T(0.1) * ty
    xmin -= T(0.05) * tx; ymin -= T(0.05) * ty
    hx = width / T(nx - 1); hy = height / T(ny - 1)
    q = CUDA.zeros(T, nx + 1, ny + 1)
    code = method === :CIC ? Int32(1) : Int32(2)
    CUDA.@cuda threads=256 blocks=cld(n, 256) O._cuda_pic_deposit_nomask_kernel!(
        q, CUDA.CuArray(x), CUDA.CuArray(y), xmin, ymin, hx, hy,
        Int32(nx + 1), Int32(ny + 1), code)
    CUDA.synchronize()
    qh = Array(q)
    println("  $T $method  full_sum=", sum(qh), "  old_1:nx,1:ny_sum=", sum(qh[1:nx, 1:ny]),
            "  charge outside old window=", sum(qh) - sum(qh[1:nx, 1:ny]),
            "  rel_deficit_full=", (n - Float64(sum(qh))) / n)
end
