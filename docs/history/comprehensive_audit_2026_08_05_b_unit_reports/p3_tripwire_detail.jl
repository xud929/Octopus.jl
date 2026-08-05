# U11 probe 3: exact tripwire arithmetic equivalence CPU vs CUDA, and the two
# corner inputs the CUDA accumulator handles differently from the CPU deficit.
using Octopus, Printf, Test, Logging
const O = Octopus
const CU = Octopus.CUDA

function cuda_dropped(sxh, syh, L, Nx, Ny)
    lease = O._acquire_spectral_cuda_ws(Float64, Nx, Ny)
    ws = lease.workspace
    try
        CU.fill!(ws.dropped, 0.0)
        O._cuda_spectral_field!(ws, CU.CuArray(sxh), CU.CuArray(syh), L, L)
        CU.synchronize()
        return Array(ws.dropped)[1]
    finally
        O._release_spectral_cuda_ws!(lease)
    end
end
function cpu_deficit(sxh, syh, L, Nx, Ny)
    ws = O._spectral_grid_ws(Nx, Ny)
    O._spectral_field_grid_solve!(ws, sxh, syh, L, L)
    return length(sxh) - sum(ws.rho)
end

println("=== (1) same physical quantity? CPU grid deficit vs CUDA in-kernel sum ===")
for (label, sxh, syh, L, Nx, Ny) in (
        ("all inside",            [1.0e-4 * sin(i) for i in 1:64], zeros(64), 1.0e-3, 16, 16),
        ("one fully outside",     [fill(1.0e-4, 63); 5.0e-3],      zeros(64), 1.0e-3, 16, 16),
        ("several straddling",    vcat([1.0e-4 * sin(i) for i in 1:60],
                                       [0.999e-3, -0.999e-3, 1.05e-3, -1.05e-3]), zeros(64), 1.0e-3, 16, 16),
        ("straddle, fine grid",   vcat([1.0e-4 * sin(i) for i in 1:60],
                                       [0.999e-3, -0.999e-3, 1.05e-3, -1.05e-3]), zeros(64), 1.0e-3, 128, 128))
    c = cpu_deficit(sxh, syh, L, Nx, Ny); g = cuda_dropped(sxh, syh, L, Nx, Ny)
    @printf("  %-22s CPU deficit %.17g   CUDA dropped %.17g   |diff| %.3e\n",
            label, c, g, abs(c - g))
end

println("=== (2) corner: a NaN coordinate ===")
let sxh = [fill(1.0e-4, 63); NaN], syh = zeros(64), L = 1.0e-3
    @printf("  CPU deficit %.17g   CUDA dropped %.17g\n",
            cpu_deficit(sxh, syh, L, 16, 16), cuda_dropped(sxh, syh, L, 16, 16))
end

println("=== (3) corner: a finite coordinate past the _GRID_REJECT cut ===")
for xbad in (1.0e10, 1.0e13, 1.0e20)
    sxh = [fill(1.0e-4, 63); xbad]; syh = zeros(64); L = 1.0e-3
    @printf("  x=%.0e  CPU deficit %.17g   CUDA dropped %.17g\n",
            xbad, cpu_deficit(sxh, syh, L, 16, 16), cuda_dropped(sxh, syh, L, 16, 16))
end

println("=== (4) full CPU warning ledger vs the one CUDA aggregate ===")
strong_h(n) = begin
    s(scale, phase) = [scale * sin(0.7 * i + phase) for i in 1:n]
    x = s(1.0e-4, 0.0); x[1] = 8.0e-4
    (x, s(1.0e-5, 0.3), s(1.0e-4, 0.9), s(1.0e-5, 1.2), s(1.0e-2, 2.0), s(1.0e-4, 2.5))
end
mkcpu(n) = (rep = Phase6DRep(strong_h(n)...);
            p = BeamParams{Float64}(charge=1.0, mc2=1.0, E0=1.0, r0=1.0, npart=n);
            Beam{CPUThreadsBackend,typeof(p),typeof(rep)}(p, rep))
mkgpu(n) = (rep = Phase6DRep((CU.CuArray(a) for a in strong_h(n))...);
            p = BeamParams{Float64}(charge=1.0, mc2=1.0, E0=1.0, r0=1.0, npart=n);
            Beam{O.CUDABackend,typeof(p),typeof(rep)}(p, rep))
capture(f) = (lg = Test.TestLogger(min_level=Logging.Debug);
              r = with_logger(lg) do; f() end; (r, lg.logs))

sp = SpectralPoissonSolver(kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0,
    grid=(64, 64), slicing=LongitudinalSlicing(nslices=2, method=:equal_count))
_, lc = capture(() -> collide!(sp, mkcpu(256), mkcpu(256), CPUThreadsBackend))
_, lg = capture(() -> (r = collide!(sp, mkgpu(256), mkgpu(256), O.CUDABackend); CU.synchronize(); r))
wc = [l for l in lc if occursin("clipped charge", string(l.message))]
wg = [l for l in lg if occursin("clipped charge", string(l.message))]
tot_c = sum(l.kwargs[:dropped_fraction] * l.kwargs[:nsource] for l in wc; init=0.0)
tot_g = isempty(wg) ? 0.0 : wg[1].kwargs[:dropped_fraction] * wg[1].kwargs[:ndeposits]
println("  CPU warnings (per solve):")
for l in wc
    @printf("    dropped_fraction=%.6e  nsource=%d  -> dropped=%.6f\n",
            l.kwargs[:dropped_fraction], l.kwargs[:nsource],
            l.kwargs[:dropped_fraction] * l.kwargs[:nsource])
end
@printf("  CPU total dropped charge (over warned solves) : %.6f\n", tot_c)
@printf("  CUDA total dropped charge (whole collision)   : %.6f\n", tot_g)
@printf("  CPU worst-solve fraction %.4e vs CUDA reported %.4e  (quieter by %.1fx)\n",
        maximum(l.kwargs[:dropped_fraction] for l in wc; init=0.0),
        isempty(wg) ? 0.0 : wg[1].kwargs[:dropped_fraction],
        maximum(l.kwargs[:dropped_fraction] for l in wc; init=0.0) /
            (isempty(wg) ? NaN : wg[1].kwargs[:dropped_fraction]))
@printf("  CPU kwarg keys %s ; CUDA kwarg keys %s\n",
        sort(string.(collect(keys(wc[1].kwargs)))), sort(string.(collect(keys(wg[1].kwargs)))))

println("=== (5) is the small-grid corner reachable at a plausible domain_factor? ===")
for (df, g) in ((4.0, 16), (4.0, 32), (5.0, 32), (8.0, 32), (2.0, 64), (16.0, 8))
    s = SpectralPoissonSolver(kbb1=1.0e-12, kbb2=1.0e-12, luminosity_scale=1.0,
        grid=(g, g), domain_factor=df, longitudinal_kick=false,
        slicing=LongitudinalSlicing(nslices=2, method=:equal_count))
    _, l1 = capture(() -> collide!(s, mkcpu(256), mkcpu(256), CPUThreadsBackend))
    _, l2 = capture(() -> (r = collide!(s, mkgpu(256), mkgpu(256), O.CUDABackend); CU.synchronize(); r))
    n1 = count(l -> occursin("clipped charge", string(l.message)), l1)
    n2 = count(l -> occursin("clipped charge", string(l.message)), l2)
    @printf("  domain_factor=%.1f grid=%d : CPU warns %d, CUDA warns %d\n", df, g, n1, n2)
end
