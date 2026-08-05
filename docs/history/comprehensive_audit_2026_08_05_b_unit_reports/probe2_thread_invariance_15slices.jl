using Octopus
using Printf
const O = Octopus

mkr(n) = begin
    s(scale, phase) = [scale * sin(0.7 * i + phase) for i in 1:n]
    z = [2.0e-2 * sin(0.7 * i + 2.0) + 1.0e-3 * sin(3.1 * i) for i in 1:n]
    O.Phase6DRep(s(1.0e-4, 0.0), s(1.0e-5, 0.3), s(1.0e-4, 0.9),
                 s(1.0e-5, 1.2), z, s(1.0e-4, 2.5))
end
mkb(n) = begin
    rep = mkr(n)
    params = O.BeamParams{Float64}(charge=1.0, mc2=1.0, E0=1.0, r0=1.0e-9, npart=n)
    O.Beam{O.CPUThreadsBackend,typeof(params),typeof(rep)}(params, rep)
end
workers(f, k, rep) = O._with_execution_policy(f,
    O._resolve_execution_policy(O.CPUThreadsExecutionPolicy(threads=k), rep))
ulps(a, b) = (a == b) ? 0 : abs(reinterpret(Int64, a) - reinterpret(Int64, b))
function diffstats(A, B)
    nd = 0; maxabs = 0.0; maxulp = 0
    for (a, b) in zip(A, B), (x, y) in zip(a, b)
        if x != y
            nd += 1; maxabs = max(maxabs, abs(x - y)); maxulp = max(maxulp, ulps(x, y))
        end
    end
    return (nd, sum(length, A), maxabs, maxulp)
end

const NPART = 90000        # 15 slices -> 6000/slice, above every 4096 threshold
const COUNTS = (1, 4, 8)
slc = O.LongitudinalSlicing(nslices=15, method=:equal_count)
slca = O.LongitudinalSlicing(nslices=15, method=:equal_area)

solvers = (
    ("pic/equal_count", O.PICPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0,
        grid=(32, 32), green_cache=:none, slicing=slc)),
    ("pic/equal_area", O.PICPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0,
        grid=(32, 32), green_cache=:none, slicing=slca)),
    ("pic/lumTSC", O.PICPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0,
        grid=(32, 32), green_cache=:none, slicing=slc, deposit_method=:TSC)),
    ("gauss", O.GaussianPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6,
        luminosity_scale=1.0, slicing=slc)),
    ("spectral_l", O.SpectralPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6,
        luminosity_scale=1.0, grid=(32, 32), slicing=slc)),
    ("spectral_t", O.SpectralPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, longitudinal_kick=false,
        luminosity_scale=1.0, grid=(32, 32), slicing=slc)),
)
println("n = $NPART, 15 slices -> $(NPART ÷ 15)/slice; pool = ", Threads.nthreads(:default))
for (label, solver) in solvers
    outs = map(COUNTS) do k
        b1, b2 = mkb(NPART), mkb(NPART)
        lum = workers(k, b1.rep) do
            O.collide!(solver, b1, b2, O.CPUThreadsBackend)
        end
        (lum, map(copy, O.coordinate_arrays(b1.rep)), map(copy, O.coordinate_arrays(b2.rep)))
    end
    for t in 2:length(COUNTS)
        d1 = diffstats(outs[1][2], outs[t][2]); d2 = diffstats(outs[1][3], outs[t][3])
        @printf("%-18s %d-vs-%d  b1 %d/%d (max|d|=%.3g,%d ulp)  b2 %d/%d (max|d|=%.3g,%d ulp)  lum %d ulp (%.17g vs %.17g)\n",
                label, COUNTS[1], COUNTS[t], d1[1], d1[2], d1[3], d1[4], d2[1], d2[2], d2[3], d2[4],
                ulps(outs[1][1], outs[t][1]), outs[1][1], outs[t][1])
    end
end
