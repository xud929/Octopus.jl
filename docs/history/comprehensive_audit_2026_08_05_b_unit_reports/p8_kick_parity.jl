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
    for f in (:x, :px, :y, :py, :z, :pz)
        a = getfield(ec.rep, f); b = Array(getfield(eg.rep, f))
        md = max(md, maximum(abs, a .- b)); scale = max(scale, maximum(abs, a))
        a2 = getfield(pc.rep, f); b2 = Array(getfield(pg.rep, f))
        md = max(md, maximum(abs, a2 .- b2)); scale = max(scale, maximum(abs, a2))
    end
    return md, md/scale, abs(lg - lc)/abs(lc)
end

cases = Any[]
for ig in (:slice_pair, :node, :source_slice), dm in (:CIC, :TSC),
    si in (:linear, :quadratic), lk in (true, false)
    push!(cases, (ig=ig, dm=dm, si=si, lk=lk))
end
@printf("%-14s %-5s %-10s %-6s %-8s %12s %12s %12s\n",
        "interaction", "dep", "slice_int", "lkick", "status", "maxabs", "relmax", "rel dlum")
for c in cases
  for bm in (:wavefront, :sequential)
    try
        md, rel, dl = compare(interaction_grid=c.ig, deposit_method=c.dm,
                              slice_interpolation=c.si, longitudinal_kick=c.lk,
                              batch_mode=bm)
        @printf("%-14s %-5s %-10s %-6s %-8s %12.3e %12.3e %12.3e\n",
                string(c.ig)*"/"*string(bm)[1:4], c.dm, c.si, c.lk, "ok", md, rel, dl)
    catch err
        msg = first(split(sprint(showerror, err), '\n'))
        @printf("%-14s %-5s %-10s %-6s %-8s %s\n",
                string(c.ig)*"/"*string(bm)[1:4], c.dm, c.si, c.lk, "ERR", first(msg, 110))
    end
  end
end
