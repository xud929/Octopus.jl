using Octopus, CUDA, Printf
const CUDABackend = Octopus.CUDABackend
const O = Octopus

function pair(backend, n=20_000)
    set_global_rng!(seed=7, method=:philox)
    e = Beam(n, backend, Float64;
        beta=(1.0, 1.0, 10.0), alpha=(0.0, 0.0, 0.0), sigma=(1.0e-4, 1.0e-4, 1.0e-2),
        cutoff=5.0, rng_id=1, charge=-1.0, mc2=EMASS_EV, E0=10.0e9,
        r0=RE * ME0 / EMASS_EV, npart=1.7e11)
    p = Beam(n, backend, Float64;
        beta=(1.0, 1.0, 10.0), alpha=(0.0, 0.0, 0.0), sigma=(1.0e-4, 1.0e-4, 1.0e-2),
        cutoff=5.0, rng_id=2, charge=1.0, mc2=PMASS_EV, E0=275.0e9,
        r0=RE * ME0 / PMASS_EV, npart=1.7e11)
    return e, p
end
sl = LongitudinalSlicing(nslices=5, method=:normal_quantile, center_position=:centroid)

println("### direct collide! under a scoped resolved policy")
for bm in (:sequential, :wavefront), threads in (256, 384, 512, 1024)
    e, p = pair(CUDABackend)
    solver = GaussianPoissonSolver(slicing=sl, longitudinal_kick=true, batch_mode=bm)
    pol = O.ResolvedCUDAExecutionPolicy(0, threads, :auto)
    ok = try
        O._with_resolved_policy(pol) do
            collide!(solver, e, p, CUDABackend); CUDA.synchronize()
        end
        "OK"
    catch err
        "FAIL: " * first(split(sprint(showerror, err), '\n'))
    end
    @printf("  batch_mode=%-11s threads=%-5d %s\n", bm, threads, ok)
end

println()
println("### public StrongStrongTask API with CUDAExecutionPolicy(threads=512)")
for bm in (:sequential, :wavefront)
    e, p = pair(CUDABackend)
    solver = GaussianPoissonSolver(slicing=sl, longitudinal_kick=true, batch_mode=bm)
    ip = StrongStrongCollision(:ip; poisson_solver=solver)
    task = StrongStrongTask((ip,), (ip,);
        policy=Octopus.CUDAExecutionPolicy(
            launch=Octopus.CUDALaunchConfig(threads=512, blocks=:auto)))
    ok = try
        execute!(task, e, p; turns=1); CUDA.synchronize(); "OK"
    catch err
        "FAIL: " * first(split(sprint(showerror, err), '\n'))
    end
    @printf("  batch_mode=%-11s %s\n", bm, ok)
end

println()
println("### PIC solver, same policy (control)")
e, p = pair(CUDABackend)
picsolver = PICPoissonSolver(grid=(32,32), green_cache=:none, slicing=sl)
ip = StrongStrongCollision(:ip; poisson_solver=picsolver)
task = StrongStrongTask((ip,), (ip,);
    policy=Octopus.CUDAExecutionPolicy(
        launch=Octopus.CUDALaunchConfig(threads=512, blocks=:auto)))
try
    execute!(task, e, p; turns=1); CUDA.synchronize(); println("  PIC threads=512 OK")
catch err
    println("  PIC threads=512 FAIL: ", first(split(sprint(showerror, err), '\n')))
end
