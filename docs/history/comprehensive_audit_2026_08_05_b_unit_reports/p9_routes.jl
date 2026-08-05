using Octopus, CUDA, Printf
const CUDABackend = Octopus.CUDABackend
const CPUThreadsBackend = Octopus.CPUThreadsBackend
const O = Octopus

function pair(backend)
    set_global_rng!(seed=11, method=:philox)
    e = Beam(6000, backend, Float64; beta=(1.0,1.0,10.0), alpha=(0.0,0.0,0.0),
        sigma=(1.0e-4,1.0e-4,1.0e-2), cutoff=5.0, rng_id=1, charge=-1.0,
        mc2=EMASS_EV, E0=10.0e9, r0=RE*ME0/EMASS_EV, npart=1.7e11)
    p = Beam(6000, backend, Float64; beta=(1.0,1.0,10.0), alpha=(0.0,0.0,0.0),
        sigma=(1.0e-4,1.0e-4,1.0e-2), cutoff=5.0, rng_id=2, charge=1.0,
        mc2=PMASS_EV, E0=275.0e9, r0=RE*ME0/PMASS_EV, npart=1.7e11)
    return e, p
end
sl = LongitudinalSlicing(nslices=4, method=:normal_quantile, center_position=:centroid)

function compare(; kw...)
    ec, pc = pair(CPUThreadsBackend)
    eg, pg = pair(CUDABackend)
    s = PICPoissonSolver(; grid=(32,32), green_cache=:none, slicing=sl, kw...)
    lc = collide!(s, ec, pc, CPUThreadsBackend)
    lg = O._with_resolved_policy(O.ResolvedCUDAExecutionPolicy(0, 256, :auto)) do
        l = collide!(s, eg, pg, CUDABackend); CUDA.synchronize(); l
    end
    md = 0.0; scale = 0.0
    for f in (:x,:px,:y,:py,:z,:pz)
        for (a,b) in ((getfield(ec.rep,f), Array(getfield(eg.rep,f))),
                      (getfield(pc.rep,f), Array(getfield(pg.rep,f))))
            md = max(md, maximum(abs, a .- b)); scale = max(scale, maximum(abs, a))
        end
    end
    return md, md/scale, abs(lg-lc)/abs(lc)
end

@printf("%-58s %10s %12s %12s\n", "route", "status", "relmax", "rel dlum")
for bm in (:wavefront, :sequential), iw in (true, false), async in (true, false),
    bfft in (true, false), wfft in (true, false), lk in (true, false)
    tag = "bm=$bm iw=$iw async=$async bfft=$bfft wfft=$wfft lk=$lk"
    try
        md, rel, dl = compare(batch_mode=bm, cuda_indexed_wavefront=iw,
            cuda_async=async, cuda_batch_fft=bfft, cuda_wavefront_fft=wfft,
            longitudinal_kick=lk)
        @printf("%-58s %10s %12.3e %12.3e\n", tag, "ok", rel, dl)
    catch err
        @printf("%-58s %10s %s\n", tag, "ERR",
                first(first(split(sprint(showerror, err), '\n')), 90))
    end
end
