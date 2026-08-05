using Octopus, CUDA
const CUDABackend = Octopus.CUDABackend
using Octopus: Phase6DRep, coordinate_arrays

const N = 200_000
const NS = 9

function beams()
    b1 = Beam(N, CPUThreadsBackend, Float64;
        beta=(0.55, 0.056, 0.7e-2 / 5.5e-4), alpha=(0.0, 0.0, 0.0),
        sigma=(106e-6, 9.5e-6, 0.7e-2), cutoff=5.0, rng_id=1,
        charge=-1.0, mc2=Octopus.EMASS_EV, E0=10e9, r0=Octopus.RE, npart=1.7203e11)
    b2 = Beam(N, CPUThreadsBackend, Float64;
        beta=(0.8, 0.072, 6e-2 / 6.6e-4), alpha=(0.0, 0.0, 0.0),
        sigma=(95e-6, 8.5e-6, 6e-2), cutoff=5.0, rng_id=2,
        charge=1.0, mc2=Octopus.PMASS_EV, E0=275e9,
        r0=Octopus.RE * Octopus.ME0 / Octopus.PMASS_EV, npart=0.6881e11)
    return b1, b2
end
host(a) = copy(Array(a))
gpu(b) = (rep = Phase6DRep((CUDA.CuArray(host(a)) for a in coordinate_arrays(b.rep))...);
          Beam{CUDABackend,typeof(b.params),typeof(rep)}(b.params, rep))

function timeit(; longitudinal_kick, interaction_grid, batch_mode=:wavefront,
                cuda_async=true, turns=6)
    b1o, b2o = beams()
    slicing = LongitudinalSlicing(method=:normal_quantile, nslices=NS, center_position=:centroid)
    solver = PICPoissonSolver(slicing=slicing, grid=(64, 64), deposit_method=:CIC,
        interaction_grid=interaction_grid, batch_mode=batch_mode,
        cuda_async=cuda_async, longitudinal_kick=longitudinal_kick,
        luminosity_schedule=nothing)
    ip = StrongStrongCollision(:ip; poisson_solver=solver)
    mktempdir() do dir
        task = StrongStrongTask((ip,), (ip,); luminosity_path=joinpath(dir, "lum"))
        b1 = gpu(b1o); b2 = gpu(b2o)
        execute!(task, b1, b2; turns=1)          # warm up
        CUDA.synchronize()
        b1 = gpu(b1o); b2 = gpu(b2o)
        t = @elapsed begin
            execute!(task, b1, b2; turns=turns); CUDA.synchronize()
        end
        return t / turns
    end
end

println("seconds/turn, N=$N, nslices=$NS, grid=64x64, CUDA")
for ig in (:node, :slice_pair)
    for bm in ((:wavefront, true), (:sequential, false))
        a = timeit(longitudinal_kick=true,  interaction_grid=ig, batch_mode=bm[1], cuda_async=bm[2])
        b = timeit(longitudinal_kick=false, interaction_grid=ig, batch_mode=bm[1], cuda_async=bm[2])
        println("  interaction_grid=", rpad(ig, 12), " batch_mode=", rpad(bm[1], 11),
                " longkick=true: ", round(a, digits=5), " s   longkick=false: ", round(b, digits=5),
                " s   saving=", round(100 * (a - b) / a, digits=1), "%")
    end
end
