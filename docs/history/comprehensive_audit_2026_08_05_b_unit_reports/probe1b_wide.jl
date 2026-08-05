using Octopus
using Printf

const O = Octopus

# Same beam generator as the permanent pin (test/runtests.jl), but n is a knob.
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
    for (a, b) in zip(A, B)
        for (x, y) in zip(a, b)
            if x != y
                nd += 1
                maxabs = max(maxabs, abs(x - y))
                maxulp = max(maxulp, ulps(x, y))
            end
        end
    end
    total = sum(length, A)
    return (nd, total, maxabs, maxulp)
end

const NPART = 15000            # 3 slices -> 5000/slice, above _PIC_PARALLEL_DEPOSIT_MIN = 4096
const COUNTS = (1, 2, 3, 5, 7, 16, 64)
slc = O.LongitudinalSlicing(nslices=3, method=:equal_count)

solvers = (
    ("pic", O.PICPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0,
        grid=(16, 16), green_cache=:none, slicing=slc)),
    ("pic_tsc_g64", O.PICPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0,
        grid=(64, 64), green_cache=:none, slicing=slc, deposit_method=:TSC)),
    ("pic_slicepair_cache", O.PICPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0,
        grid=(16, 16), green_cache=:slice_pair, slicing=slc)),
    ("pic_source_slice", O.PICPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0,
        grid=(16, 16), green_cache=:none, slicing=slc, interaction_grid=:source_slice)),
    ("pic_node", O.PICPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0,
        grid=(16, 16), green_cache=:none, slicing=slc, interaction_grid=:node)),
    ("pic_quadratic", O.PICPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0,
        grid=(16, 16), green_cache=:none, slicing=slc, slice_interpolation=:quadratic)),
    ("gpic", O.GaussianPICPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6,
        luminosity_scale=1.0, grid=(16, 16), green_cache=:none, slicing=slc)),
    ("gauss", O.GaussianPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6,
        luminosity_scale=1.0, slicing=slc)),
    ("spectral_l", O.SpectralPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6,
        luminosity_scale=1.0, grid=(32, 32), slicing=slc)),
    ("spectral_t", O.SpectralPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, longitudinal_kick=false,
        luminosity_scale=1.0, grid=(32, 32), slicing=slc)),
)

println("n = $NPART particles/beam, 3 equal_count slices -> $(NPART ÷ 3) per slice")
println("threads pool = ", Threads.nthreads(:default))
println()

for (label, solver) in solvers
    outs = map(COUNTS) do k
        b1, b2 = mkb(NPART), mkb(NPART)
        lum = workers(k, b1.rep) do
            O.collide!(solver, b1, b2, O.CPUThreadsBackend)
        end
        (lum, map(copy, O.coordinate_arrays(b1.rep)), map(copy, O.coordinate_arrays(b2.rep)))
    end
    for t in 2:length(COUNTS)
        d1 = diffstats(outs[1][2], outs[t][2])
        d2 = diffstats(outs[1][3], outs[t][3])
        lu = ulps(outs[1][1], outs[t][1])
        @printf("%-20s %d-vs-%d  beam1 %d/%d differ (max|d|=%.3g, %d ulp)  beam2 %d/%d (max|d|=%.3g, %d ulp)  lum %d ulp\n",
                label, COUNTS[1], COUNTS[t], d1[1], d1[2], d1[3], d1[4],
                d2[1], d2[2], d2[3], d2[4], lu)
    end
end

println()
println("== _slice_transverse_moments directly, n above _STRONG_STRONG_PARALLEL_MOMENT_MIN ==")
for n in (4095, 4096, 8192, 200000)
    rep = mkr(n)
    idx = collect(1:n)
    res = map(COUNTS) do k
        O._with_execution_policy(
            O._resolve_execution_policy(O.CPUThreadsExecutionPolicy(threads=k), rep)) do
            O._slice_transverse_moments(rep, idx, false, 0.0, Val(true))
        end
    end
    worst = 0; worstfield = :none
    for t in 2:length(COUNTS)
        for f in (:mx, :sx, :mpx, :spx, :covxpx, :my, :sy, :mpy, :spy, :covypy)
            u = ulps(getfield(res[1], f), getfield(res[t], f))
            if u > worst
                worst = u; worstfield = f
            end
        end
    end
    @printf("n=%-8d  max moment disagreement over 1/4/8 workers: %d ulp (%s)\n", n, worst, worstfield)
end
