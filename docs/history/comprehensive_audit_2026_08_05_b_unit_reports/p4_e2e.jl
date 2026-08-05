using Octopus, CUDA, Printf
const CUDABackend = Octopus.CUDABackend
const O = Octopus

function pair(backend)
    set_global_rng!(seed=7, method=:philox)
    e = Beam(200_003, backend, Float64;
        beta=(1.0, 1.0, 10.0), alpha=(0.0, 0.0, 0.0), sigma=(1.0e-4, 1.0e-4, 1.0e-2),
        cutoff=5.0, rng_id=1, charge=-1.0, mc2=EMASS_EV, E0=10.0e9,
        r0=RE * ME0 / EMASS_EV, npart=1.7e11)
    p = Beam(200_003, backend, Float64;
        beta=(1.0, 1.0, 10.0), alpha=(0.0, 0.0, 0.0), sigma=(1.0e-4, 1.0e-4, 1.0e-2),
        cutoff=5.0, rng_id=2, charge=1.0, mc2=PMASS_EV, E0=275.0e9,
        r0=RE * ME0 / PMASS_EV, npart=1.7e11)
    return e, p
end

sl = LongitudinalSlicing(nslices=5, method=:normal_quantile, center_position=:centroid)

function run(threads, blocks, batch_mode)
    e, p = pair(CUDABackend)
    solver = GaussianPoissonSolver(slicing=sl, longitudinal_kick=true,
                                   batch_mode=batch_mode)
    pol = O.ResolvedCUDAExecutionPolicy(0, threads, blocks)
    lum = O._with_resolved_policy(pol) do
        l = collide!(solver, e, p, CUDABackend)
        CUDA.synchronize()
        l
    end
    return (px=Array(e.rep.px), py=Array(e.rep.py), x=Array(e.rep.x),
            pz=Array(e.rep.pz), lum=lum)
end

ref = run(256, :auto, :sequential)
println("reference: threads=256 blocks=:auto batch_mode=:sequential  lum=$(ref.lum)")
println()
@printf("%-38s %14s %14s %14s %12s\n", "config", "max|dpx|", "relmax dpx", "max|dpz|", "dlum/lum")
for (threads, blocks, bm) in ((256, :auto, :sequential), (64, :auto, :sequential),
                              (128, :auto, :sequential), (384, :auto, :sequential),
                              (256, 1024, :sequential), (256, 512, :sequential),
                              (256, :auto, :wavefront), (64, :auto, :wavefront))
    r = run(threads, blocks, bm)
    dpx = maximum(abs, r.px .- ref.px)
    scale = maximum(abs, ref.px)
    dpz = maximum(abs, r.pz .- ref.pz)
    @printf("threads=%-4d blocks=%-6s %-11s %14.6e %14.6e %14.6e %12.4e\n",
        threads, string(blocks), string(bm), dpx, dpx/scale, dpz,
        (r.lum - ref.lum)/ref.lum)
end
