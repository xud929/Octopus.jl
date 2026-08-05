using Octopus
const O = Octopus
println("threads(:default) = ", Threads.nthreads(:default))

mkb(rng_id, charge, mc2, E0, n) = begin
    set_global_rng!(seed=5, method=:philox)
    Beam(n, CPUThreadsExecutionPolicy(), Float64;
        beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
        sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0, rng_id=rng_id,
        charge=charge, mc2=mc2, E0=E0, r0=RE * ME0 / mc2, npart=1.0e10)
end
beams(n) = (mkb(1, -1.0, EMASS_EV, 10.0e9, n), mkb(2, 1.0, PMASS_EV, 275.0e9, n))
L6s(b, t) = Linear6DSpec{Float64}(; beta1=b, beta2=b, alpha1=(0.0, 0.0, 0.0),
                                  alpha2=(0.0, 0.0, 0.0), dmu=2pi .* t)
A = L6s((0.55, 0.056, 12.7), (0.08, 0.14, -0.069))
B = L6s((0.8, 0.072, 90.9), (0.228, 0.210, -0.01))

# Above the parallel thresholds: _STRONG_STRONG_PARALLEL_MOMENT_MIN =
# _STRONG_STRONG_PARALLEL_KICK_MIN = _PIC_PARALLEL_DEPOSIT_MIN = 4096 per slice.
const NPART = 20_000

function run_at(workers, solver)
    ip = StrongStrongCollision(:ip; poisson_solver=solver)
    p = tempname() * ".lum"
    t = StrongStrongTask((ip, A), (ip, B); luminosity_path=p,
                         policy=CPUThreadsExecutionPolicy(threads=workers))
    b1, b2 = beams(NPART)
    execute!(t, b1, b2; turns=2)
    coords = vcat((Array(a) for a in coordinate_arrays(b1.rep))...,
                  (Array(a) for a in coordinate_arrays(b2.rep))...)
    lum = readlines(p)[2:end]
    rm(p; force=true)
    return coords, lum
end

println("=== P10: does the fixed-chunk claim hold? bitwise invariance across worker counts ===")
for (nm, solver) in (("PIC", PICPoissonSolver(grid=(32, 32),
                          slicing=LongitudinalSlicing(nslices=3, method=:normal_quantile))),
                     ("Gaussian", GaussianPoissonSolver(
                          slicing=LongitudinalSlicing(nslices=3, method=:normal_quantile))))
    ws = unique((1, 2, Threads.nthreads(:default)))
    ref = run_at(first(ws), solver)
    ok = true
    for w in ws[2:end]
        r = run_at(w, solver)
        same = r[1] == ref[1] && r[2] == ref[2]
        ok &= same
        println("  ", nm, ": workers ", first(ws), " vs ", w, " -> bit-identical: ", same)
    end
    println("  ", nm, ": ", NPART, " particles/beam, 3 slices, 2 turns -> invariant: ", ok)
end

println()
println("=== P11: fixed 16 deposit buffers regardless of worker count ===")
for (nx, ny) in ((32, 32), (128, 128), (256, 256))
    w = O._pic_cpu_workspace(Float64, nx, ny)
    bytes = sum(sizeof, w.local_charge)
    println("  grid=(", nx, ",", ny, "): local_charge = ", length(w.local_charge),
            " buffers, ", round(bytes / 2^20; digits=2), " MiB",
            " (1 buffer would be ", round(bytes / length(w.local_charge) / 2^20; digits=2), " MiB)")
end
