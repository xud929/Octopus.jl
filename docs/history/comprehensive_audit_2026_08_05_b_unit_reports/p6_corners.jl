# U11 probe 6: remaining corners.
using Octopus, Printf, Test, Logging
const O = Octopus
const CU = Octopus.CUDA

println("=== (1) CPU transverse hoist: x/y really are never mutated ===")
let n = 800
    s(scale, phase) = [scale * sin(0.7 * i + phase) for i in 1:n]
    arrs = (s(1.0e-4, 0.0), s(1.0e-5, 0.3), s(1.0e-4, 0.9), s(1.0e-5, 1.2),
            [2.0e-2 * sin(0.7 * i + 2.0) for i in 1:n], s(1.0e-4, 2.5))
    mk() = (rep = Phase6DRep((copy(a) for a in arrs)...);
            p = BeamParams{Float64}(charge=1.0, mc2=1.0, E0=1.0, r0=1.0e-9, npart=n);
            Beam{CPUThreadsBackend,typeof(p),typeof(rep)}(p, rep))
    sv = SpectralPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0,
        grid=(32, 32), longitudinal_kick=false,
        slicing=LongitudinalSlicing(nslices=5, method=:equal_count))
    b1 = mk(); b2 = mk()
    x0 = copy(b1.rep.x); y0 = copy(b1.rep.y); z0 = copy(b1.rep.z); pz0 = copy(b1.rep.pz)
    collide!(sv, b1, b2, CPUThreadsBackend)
    @printf("  x %s  y %s  z %s  pz %s (all must be true)\n",
            b1.rep.x == x0, b1.rep.y == y0, b1.rep.z == z0, b1.rep.pz == pz0)
end

println("=== (2) empty source slice: does a zero-length CUDA deposit launch? ===")
let Nx = 16, Ny = 16
    lease = O._acquire_spectral_cuda_ws(Float64, Nx, Ny); ws = lease.workspace
    try
        empt = CU.zeros(Float64, 0)
        try
            O._cuda_spectral_field!(ws, empt, empt, 1.0e-3, 1.0e-3); CU.synchronize()
            println("  ns=0 _cuda_spectral_field! : OK (no error)")
        catch e
            println("  ns=0 _cuda_spectral_field! : THROWS ", sprint(showerror, e)[1:min(end, 140)])
        end
    finally
        O._release_spectral_cuda_ws!(lease)
    end
end

println("=== (3) is the silent (NaN / _GRID_REJECT) tripwire hole reachable through collide!? ===")
# 6D blow-up: crank kbb until the collision itself produces non-finite coordinates.
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

for kbb in (1.0e-4, 1.0e0, 1.0e4, 1.0e8, 1.0e12)
    sv = SpectralPoissonSolver(kbb1=kbb, kbb2=kbb, luminosity_scale=1.0,
        grid=(64, 64), slicing=LongitudinalSlicing(nslices=2, method=:equal_count))
    bc1 = mkcpu(256); bc2 = mkcpu(256)
    bg1 = mkgpu(256); bg2 = mkgpu(256)
    rc, lc = capture(() -> collide!(sv, bc1, bc2, CPUThreadsBackend))
    ok = true
    rg, lg = try
        capture(() -> (v = collide!(sv, bg1, bg2, O.CUDABackend); CU.synchronize(); v))
    catch e; ok = false; (NaN, []) end
    wc = [l for l in lc if occursin("clipped charge", string(l.message))]
    wg = [l for l in lg if occursin("clipped charge", string(l.message))]
    tc = sum(l.kwargs[:dropped_fraction] * l.kwargs[:nsource] for l in wc; init=0.0)
    tg = sum(l.kwargs[:dropped_fraction] * l.kwargs[:ndeposits] for l in wg; init=0.0)
    nf_c = count(!isfinite, bc1.rep.x)
    nf_g = ok ? count(!isfinite, Array(bg1.rep.x)) : -1
    @printf("  kbb=%.0e  nonfinite x after: CPU %d / CUDA %d ; warns CPU %d CUDA %d ; total dropped CPU %.4g CUDA %.4g\n",
            kbb, nf_c, nf_g, length(wc), length(wg), tc, tg)
end

println("=== (4) direct kernel: dropped charge for a slice with NaN / huge coordinates ===")
let Nx = 16, Ny = 16, L = 1.0e-3
    lease = O._acquire_spectral_cuda_ws(Float64, Nx, Ny); ws = lease.workspace
    try
        for (label, xs) in (("64 in-box", fill(1.0e-4, 64)),
                            ("1 NaN", [fill(1.0e-4, 63); NaN]),
                            ("1 Inf", [fill(1.0e-4, 63); Inf]),
                            ("8 NaN", [fill(1.0e-4, 56); fill(NaN, 8)]),
                            ("1 at 1e13", [fill(1.0e-4, 63); 1.0e13]))
            CU.fill!(ws.dropped, 0.0)
            O._cuda_spectral_field!(ws, CU.CuArray(xs), CU.zeros(Float64, 64), L, L)
            CU.synchronize()
            wsc = O._spectral_grid_ws(Nx, Ny)
            O._spectral_field_grid_solve!(wsc, xs, zeros(64), L, L)
            @printf("  %-12s CPU deficit %8.4f   CUDA dropped %8.4f\n",
                    label, 64 - sum(wsc.rho), Array(ws.dropped)[1])
        end
    finally
        O._release_spectral_cuda_ws!(lease)
    end
end
