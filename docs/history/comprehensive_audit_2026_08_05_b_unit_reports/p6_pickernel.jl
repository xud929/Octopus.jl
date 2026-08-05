using Octopus, CUDA, Printf
const CUDABackend = Octopus.CUDABackend
const O = Octopus
function pair(backend, n=20_000)
    set_global_rng!(seed=7, method=:philox)
    e = Beam(n, backend, Float64; beta=(1.0,1.0,10.0), alpha=(0.0,0.0,0.0),
        sigma=(1.0e-4,1.0e-4,1.0e-2), cutoff=5.0, rng_id=1, charge=-1.0,
        mc2=EMASS_EV, E0=10.0e9, r0=RE*ME0/EMASS_EV, npart=1.7e11)
    p = Beam(n, backend, Float64; beta=(1.0,1.0,10.0), alpha=(0.0,0.0,0.0),
        sigma=(1.0e-4,1.0e-4,1.0e-2), cutoff=5.0, rng_id=2, charge=1.0,
        mc2=PMASS_EV, E0=275.0e9, r0=RE*ME0/PMASS_EV, npart=1.7e11)
    return e, p
end
sl = LongitudinalSlicing(nslices=5, method=:normal_quantile, center_position=:centroid)
e, p = pair(CUDABackend)
before = Array(e.rep.px)
picsolver = PICPoissonSolver(grid=(32,32), green_cache=:none, slicing=sl)
ip = StrongStrongCollision(:ip; poisson_solver=picsolver)
task = StrongStrongTask((ip,), (ip,);
    policy=Octopus.CUDAExecutionPolicy(launch=Octopus.CUDALaunchConfig(threads=512, blocks=:auto)))
try
    execute!(task, e, p; turns=1); CUDA.synchronize()
catch err
    bt = catch_backtrace()
    s = sprint(showerror, err, bt)
    for line in split(s, '\n')
        occursin("kernel", line) || occursin("pic_cuda.jl", line) || occursin("Octopus", line) || continue
        println(first(line, 220))
    end
end
println("beam mutated before the throw? ", Array(e.rep.px) != before)
