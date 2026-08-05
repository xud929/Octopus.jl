# U11 probe 2: CUDA/CPU twin comparison for the spectral solver.
using Octopus, Printf, Test, Logging
const O = Octopus
const CU = Octopus.CUDA

relerr(a, b) = maximum(abs.(vec(a) .- vec(b))) / max(maximum(abs, vec(b)), eps())
maxulp(a, b) = maximum(abs.(vec(a) .- vec(b)) ./ max.(eps.(abs.(vec(b))), floatmin()))

println("=== (a) deposit-atomic nondeterminism baseline ===")
let Nx = 32, Ny = 32, L = 3.0e-3, ns = 4000
    lease = O._acquire_spectral_cuda_ws(Float64, Nx, Ny)
    ws = lease.workspace
    sx = CU.CuArray([1.0e-3 * sin(0.7 * i) for i in 1:ns])
    sy = CU.CuArray([0.8e-3 * cos(0.31 * i + 0.4) for i in 1:ns])
    Ex1, Ey1, _, _ = O._cuda_spectral_field!(ws, sx, sy, L, L)
    A1 = Array(Ex1); B1 = Array(Ey1)
    same = true; worst = 0.0
    for _ in 1:6
        Ex2, Ey2, _, _ = O._cuda_spectral_field!(ws, sx, sy, L, L)
        A2 = Array(Ex2)
        A1 == A2 || (same = false)
        worst = max(worst, relerr(A2, A1))
    end
    @printf("  repeated _cuda_spectral_field! bit-identical: %s (max rel dev %.3e)\n", same, worst)
    O._release_spectral_cuda_ws!(lease)
end

println("=== (b) CUDA vs CPU mesh field solve (same source) ===")
let Nx = 32, Ny = 48, L = 3.0e-3, ns = 4000
    sxh = [1.0e-3 * sin(0.7 * i) for i in 1:ns]
    syh = [0.8e-3 * cos(0.31 * i + 0.4) for i in 1:ns]
    wsc = O._spectral_grid_ws(Nx, Ny)
    O._spectral_field_grid_potential!(wsc, sxh, syh, Float64[], Float64[], L, L)
    lease = O._acquire_spectral_cuda_ws(Float64, Nx, Ny)
    ws = lease.workspace
    sx = CU.CuArray(sxh); sy = CU.CuArray(syh)
    spx = CU.zeros(Float64, ns); spy = CU.zeros(Float64, ns)
    O._cuda_spectral_potential_solve!(ws, ws.PhigL, ws.ExgL, ws.EygL, sx, spx, sy, spy, 0.0, L, L)
    CU.synchronize()
    rho_g = Array(ws.rho)
    @printf("  rho   CPU vs CUDA : rel %.3e  bitwise %s\n", relerr(rho_g, wsc.rho), rho_g == wsc.rho)
    @printf("  Exg   CPU vs CUDA : rel %.3e  max ulp %.1f\n", relerr(Array(ws.ExgL), wsc.Exg), maxulp(Array(ws.ExgL), wsc.Exg))
    @printf("  Eyg   CPU vs CUDA : rel %.3e  max ulp %.1f\n", relerr(Array(ws.EygL), wsc.Eyg), maxulp(Array(ws.EygL), wsc.Eyg))
    @printf("  Phig  CPU vs CUDA : rel %.3e  max ulp %.1f\n", relerr(Array(ws.PhigL), wsc.Phig), maxulp(Array(ws.PhigL), wsc.Phig))
    # the transverse-only route (_cuda_spectral_field!) against the same CPU mesh
    Ex, Ey, _, _ = O._cuda_spectral_field!(ws, sx, sy, L, L)
    @printf("  Exg (field! route) CPU vs CUDA : rel %.3e\n", relerr(Array(Ex), wsc.Exg))
    @printf("  Eyg (field! route) CPU vs CUDA : rel %.3e\n", relerr(Array(Ey), wsc.Eyg))
    O._release_spectral_cuda_ws!(lease)
end

println("=== (c) tripwire: does the CUDA one FIRE, with what number ===")
# The documented reachable corner: the box is L = max(d*sigma, 1.05*emax); with a
# tiny domain_factor the 1.05*emax term wins, and on a small grid one CIC cell is
# wider than the 5% headroom, so the extreme particle's stencil straddles the wall.
strong_h(n) = begin
    s(scale, phase) = [scale * sin(0.7 * i + phase) for i in 1:n]
    x = s(1.0e-4, 0.0); x[1] = 8.0e-4
    (x, s(1.0e-5, 0.3), s(1.0e-4, 0.9), s(1.0e-5, 1.2), s(1.0e-2, 2.0), s(1.0e-4, 2.5))
end
mkcpu(n) = begin
    rep = Phase6DRep(strong_h(n)...)
    params = BeamParams{Float64}(charge=1.0, mc2=1.0, E0=1.0, r0=1.0, npart=n)
    Beam{CPUThreadsBackend,typeof(params),typeof(rep)}(params, rep)
end
mkgpu(n) = begin
    rep = Phase6DRep((CU.CuArray(a) for a in strong_h(n))...)
    params = BeamParams{Float64}(charge=1.0, mc2=1.0, E0=1.0, r0=1.0, npart=n)
    Beam{O.CUDABackend,typeof(params),typeof(rep)}(params, rep)
end

function capture(f)
    logger = Test.TestLogger(min_level=Logging.Debug)
    r = with_logger(logger) do; f() end
    return r, logger.logs
end

for (label, solver) in (
        ("6D  grid=64 nsl=2 (recorded R9 case)",
         SpectralPoissonSolver(kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0,
             grid=(64, 64), slicing=LongitudinalSlicing(nslices=2, method=:equal_count))),
        ("transverse grid=8 df=1e-6 (small-grid corner)",
         SpectralPoissonSolver(kbb1=1.0e-9, kbb2=1.0e-9, luminosity_scale=1.0,
             grid=(8, 8), domain_factor=1.0e-6, longitudinal_kick=false,
             slicing=LongitudinalSlicing(nslices=2, method=:equal_count))))
    _, lc = capture(() -> collide!(solver, mkcpu(256), mkcpu(256), CPUThreadsBackend))
    _, lg = capture(() -> (r = collide!(solver, mkgpu(256), mkgpu(256), O.CUDABackend); CU.synchronize(); r))
    wc = [l for l in lc if occursin("clipped charge at the Dirichlet wall", string(l.message))]
    wg = [l for l in lg if occursin("clipped charge at the Dirichlet wall", string(l.message))]
    @printf("  %s\n", label)
    @printf("    CPU  warnings: %d", length(wc))
    isempty(wc) || @printf("  first dropped_fraction=%.4e  nsource=%d",
                           wc[1].kwargs[:dropped_fraction], wc[1].kwargs[:nsource])
    println()
    @printf("    CUDA warnings: %d", length(wg))
    isempty(wg) || @printf("  dropped_fraction=%.4e  ndeposits=%d",
                           wg[1].kwargs[:dropped_fraction], wg[1].kwargs[:ndeposits])
    println()
    isempty(wc) || isempty(wg) ||
        @printf("    same message text: %s ; same keys: %s\n",
                string(wc[1].message) == string(wg[1].message),
                sort(collect(keys(wc[1].kwargs))) == sort(collect(keys(wg[1].kwargs))))
end
