# U18 probe 8: how wide is the thread-invariance pin's envelope for the
# SPECTRAL solver?  The pin (test/runtests.jl "CPU solver stack is thread-count
# invariant", second block) runs nslices=3.  The spectral luminosity reduction
# partitions with `_cpu_worker_count()` (src/tasks/strongstrong/spectral.jl
# ~1103: max_workers = clamp(_cpu_worker_count(), ...); nworkers = clamp(...);
# _chunk_bounds(length(batch), nworkers, chunk)), unlike the PIC/moment
# reductions which use the fixed _REDUCTION_CHUNKS / _PIC_DEPOSIT_CHUNKS grids.
# So: does bit-equality survive a larger slice count?
using Octopus

mkr(n) = begin
    s(scale, phase) = [scale * sin(0.7 * i + phase) for i in 1:n]
    z = [2.0e-2 * sin(0.7 * i + 2.0) + 1.0e-3 * sin(3.1 * i) for i in 1:n]
    Phase6DRep(s(1.0e-4, 0.0), s(1.0e-5, 0.3), s(1.0e-4, 0.9),
               s(1.0e-5, 1.2), z, s(1.0e-4, 2.5))
end
mkb(n) = begin
    rep = mkr(n)
    params = BeamParams{Float64}(charge=1.0, mc2=1.0, E0=1.0, r0=1.0e-9, npart=n)
    Beam{CPUThreadsBackend,typeof(params),typeof(rep)}(params, rep)
end
workers(f, k, rep) = Octopus._with_execution_policy(f,
    Octopus._resolve_execution_policy(CPUThreadsExecutionPolicy(threads=k), rep))

function compare(label, solver, n, counts)
    outs = map(counts) do k
        b1, b2 = mkb(n), mkb(n)
        lum = workers(k, b1.rep) do
            collide!(solver, b1, b2, CPUThreadsBackend)
        end
        (lum, map(copy, coordinate_arrays(b1.rep)), map(copy, coordinate_arrays(b2.rep)))
    end
    for o in 2:length(outs)
        ce = all(a == b for (a, b) in zip(outs[1][2], outs[o][2])) &&
             all(a == b for (a, b) in zip(outs[1][3], outs[o][3]))
        dmax = maximum(maximum(abs, a .- b) for (a, b) in zip(outs[1][2], outs[o][2]))
        ld = outs[1][1] - outs[o][1]
        rel = outs[1][1] == 0 ? 0.0 : abs(ld) / abs(outs[1][1])
        println("  ", rpad(label, 34), "workers $(counts[1]) vs $(counts[o]): ",
                "lum_eq=", outs[1][1] == outs[o][1], " coords_eq=", ce,
                "  coord_maxdiff=", dmax, "  lum_absdiff=", ld, " (rel ", rel, ")")
    end
end

counts = unique((1, 2, Threads.nthreads(:default)))
println("counts = ", counts, "   n = 15000")
for ns in (3, 5, 9, 15)
    slc = LongitudinalSlicing(nslices=ns, method=:equal_count)
    sp = SpectralPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0,
        grid=(32, 32), slicing=slc)
    compare("spectral_l nslices=$ns", sp, 15000, counts)
end
for ns in (3, 15)
    slc = LongitudinalSlicing(nslices=ns, method=:equal_count)
    spt = SpectralPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0,
        grid=(32, 32), longitudinal_kick=false, slicing=slc)
    compare("spectral_t nslices=$ns", spt, 15000, counts)
    pic = PICPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0,
        grid=(16, 16), green_cache=:none, slicing=slc)
    compare("pic nslices=$ns", pic, 15000, counts)
end
