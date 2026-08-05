# U11 probe 7: pin the mechanism of the silent CUDA tripwire in the blow-up
# regime, and locate the transition.
using Octopus, Printf, Test, Logging
const O = Octopus
const CU = Octopus.CUDA

strong_h(n) = begin
    s(scale, phase) = [scale * sin(0.7 * i + phase) for i in 1:n]
    x = s(1.0e-4, 0.0); x[1] = 8.0e-4
    (x, s(1.0e-5, 0.3), s(1.0e-4, 0.9), s(1.0e-5, 1.2), s(1.0e-2, 2.0), s(1.0e-4, 2.5))
end
mkcpu(n) = (rep = Phase6DRep((copy(a) for a in strong_h(n))...);
            p = BeamParams{Float64}(charge=1.0, mc2=1.0, E0=1.0, r0=1.0, npart=n);
            Beam{CPUThreadsBackend,typeof(p),typeof(rep)}(p, rep))
mkgpu(n) = (rep = Phase6DRep((CU.CuArray(copy(a)) for a in strong_h(n))...);
            p = BeamParams{Float64}(charge=1.0, mc2=1.0, E0=1.0, r0=1.0, npart=n);
            Beam{O.CUDABackend,typeof(p),typeof(rep)}(p, rep))
capture(f) = (lg = Test.TestLogger(min_level=Logging.Debug);
              r = with_logger(lg) do; f() end; (r, lg.logs))

println("kbb        max|x| CPU   max|x| CUDA   X=|x|/hx      CPU warns/dropped   CUDA warns/dropped")
for kbb in (1.0e8, 1.0e9, 1.0e10, 1.0e10 * 3, 1.0e11, 1.0e12)
    sv = SpectralPoissonSolver(kbb1=kbb, kbb2=kbb, luminosity_scale=1.0,
        grid=(64, 64), slicing=LongitudinalSlicing(nslices=2, method=:equal_count))
    bc1 = mkcpu(256); bc2 = mkcpu(256); bg1 = mkgpu(256); bg2 = mkgpu(256)
    _, lc = capture(() -> collide!(sv, bc1, bc2, CPUThreadsBackend))
    _, lg = capture(() -> (v = collide!(sv, bg1, bg2, O.CUDABackend); CU.synchronize(); v))
    wc = [l for l in lc if occursin("clipped charge", string(l.message))]
    wg = [l for l in lg if occursin("clipped charge", string(l.message))]
    tc = sum(l.kwargs[:dropped_fraction] * l.kwargs[:nsource] for l in wc; init=0.0)
    tg = sum(l.kwargs[:dropped_fraction] * l.kwargs[:ndeposits] for l in wg; init=0.0)
    Lx = isempty(wc) ? NaN : wc[1].kwargs[:box][1]
    hx = 2Lx / 65
    mx = maximum(abs, bc1.rep.x)
    @printf("%.0e   %10.3e   %10.3e   %10.3e    %d / %-8.4g   %d / %-8.4g\n",
            kbb, mx, maximum(abs, Array(bg1.rep.x)), mx / hx,
            length(wc), tc, length(wg), tg)
end

println()
println("_GRID_REJECT cut = 1e15 ; typemin(Int)>>2 = ", typemin(Int) >> 2)
println("A deposit coordinate with |(x+Lx)/hx| > 1e15 takes the reject branch, and")
println("the four CIC weights then cancel to EXACTLY 0 in the `clipped` sum.")

# Direct kernel-level demonstration of the cancellation.
let Nx = 16, Ny = 16, L = 1.0e-3
    hx = 2L / (Nx + 1)
    lease = O._acquire_spectral_cuda_ws(Float64, Nx, Ny); ws = lease.workspace
    try
        println()
        @printf("%-14s %-12s %-14s %-14s\n", "x", "X=(x+L)/hx", "CPU deficit", "CUDA dropped")
        for x in (2.0e-3, 1.0e0, 1.0e6, 1.0e10, 1.0e11, 1.0e12, 1.0e13)
            xs = [fill(1.0e-4, 63); x]
            CU.fill!(ws.dropped, 0.0)
            O._cuda_spectral_field!(ws, CU.CuArray(xs), CU.zeros(Float64, 64), L, L)
            CU.synchronize()
            wsc = O._spectral_grid_ws(Nx, Ny)
            O._spectral_field_grid_solve!(wsc, xs, zeros(64), L, L)
            @printf("%-14.0e %-12.3e %-14.4f %-14.4f\n",
                    x, (x + L) / hx, 64 - sum(wsc.rho), Array(ws.dropped)[1])
        end
    finally
        O._release_spectral_cuda_ws!(lease)
    end
end
