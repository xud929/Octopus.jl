# U10 probe 8: route coverage and guard reachability.
#  a. confirm the "empty slice" configuration really produces empty slices
#  b. batch_mode = :sequential CPU<->CUDA parity (the third CUDA route)
#  c. the two CUDA reference routes must REJECT a finite coupling_tol
#  d. the six options the hybrid rejects must throw on BOTH backends
#  e. workspace.dropped[] after a GaussianPIC collide (the inert-counter claim)
using Octopus
using Octopus: CUDA
const O = Octopus
using Printf

const CPU = CPUThreadsBackend
const GPU = Octopus.CUDABackend
to_gpu(b) = begin
    rep = Phase6DRep((CUDA.CuArray(copy(a)) for a in coordinate_arrays(b.rep))...)
    Beam{GPU,typeof(b.params),typeof(rep)}(b.params, rep)
end
function mkbeam(n, sigx, sigy, sigz, seed, rngid, q, mc2, E0, npart)
    set_global_rng!(seed=seed, method=:philox)
    return Beam(n, CPU, Float64; beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
        sigma=(sigx, sigy, sigz), cutoff=5.0, rng_id=rngid,
        charge=q, mc2=mc2, E0=E0, r0=RE * ME0 / mc2, npart=npart)
end
mkflat() = (mkbeam(6000, 106.0e-6, 9.5e-6, 0.7e-2, 19, 1, -1.0, EMASS_EV, 10.0e9, 1.7e11),
            mkbeam(6000, 95.0e-6, 8.5e-6, 6.0e-2, 23, 2, 1.0, PMASS_EV, 275.0e9, 0.7e11))

println("###### a. empty-slice configuration ######")
sl_empty = LongitudinalSlicing(nslices=9, method=:equal_width, center_position=:centroid)
e, p = mkflat()
for b in (e, p)
    b.rep.z .*= 0.05; b.rep.z[1] *= 400.0; b.rep.z[2] *= -400.0
end
for (nm, b) in ((:e, e), (:p, p))
    s = O.longitudinal_slices(b.rep, sl_empty)
    counts = [length(s.indices[i]) for i in 1:9]
    @printf("  %s slice populations: %s   (empty slices: %d)\n",
            nm, string(counts), count(==(0), counts))
end

println()
println("###### b. batch_mode = :sequential parity ######")
sl5 = LongitudinalSlicing(nslices=5, method=:normal_quantile, center_position=:centroid)
for lk in (false, true), dm in (:CIC, :TSC)
    ec, pc = mkflat()
    base = (copy(ec.rep.px), copy(ec.rep.py), copy(ec.rep.pz))
    eg, pg = to_gpu(ec), to_gpu(pc)
    s = GaussianPICPoissonSolver(slicing=sl5, grid=(64, 64), green_cache=:none,
        deposit_method=dm, longitudinal_kick=lk, batch_mode=:sequential)
    lc = collide!(s, ec, pc, CPU)
    lg = collide!(s, eg, pg, GPU); CUDA.synchronize()
    cmax = 0.0
    for (a, b) in zip(coordinate_arrays(ec.rep), coordinate_arrays(eg.rep))
        A = Array(a); B = Array(b); sc = maximum(abs, A); sc == 0 && continue
        cmax = max(cmax, maximum(abs.(A .- B)) / sc)
    end
    kmax = 0.0
    for (comp, b0) in zip((:px, :py, :pz), base)
        dc = getproperty(ec.rep, comp) .- b0
        dg = Array(getproperty(eg.rep, comp)) .- b0
        sc = maximum(abs, b0)
        kmax = max(kmax, maximum(abs.(dc .- dg)) / sc)
    end
    @printf("  sequential lk=%-5s dm=%-4s  coord=%.3e  kick/p_rms=%.3e  lum rel=%.3e\n",
            lk, dm, cmax, kmax, abs(lg - lc) / abs(lc))
end

println()
println("###### c. CUDA reference routes must reject a finite coupling_tol ######")
for (tag, kw) in (("wavefront non-indexed", (batch_mode=:wavefront, cuda_indexed_wavefront=false)),
                  ("sequential", (batch_mode=:sequential,)),
                  ("wavefront indexed (must NOT throw)", (batch_mode=:wavefront, cuda_indexed_wavefront=true)))
    ec, pc = mkflat(); eg, pg = to_gpu(ec), to_gpu(pc)
    s = GaussianPICPoissonSolver(; slicing=sl5, grid=(64, 64), green_cache=:none,
        coupling_tol=0.05, kw...)
    r = try; collide!(s, eg, pg, GPU); CUDA.synchronize(); "no throw"
        catch err; "THROW $(typeof(err))"; end
    @printf("  %-38s %s\n", tag, r)
end

println()
println("###### d. rejected options throw on both backends ######")
for (opt, val) in ((:slice_interpolation, :quadratic), (:interaction_grid, :source_slice),
                   (:grid_extent, :sigma), (:cuda_async, false),
                   (:cuda_batch_fft, false), (:cuda_wavefront_fft, false))
    kw = Dict{Symbol,Any}(:slicing => sl5, :grid => (64, 64), :green_cache => :none, opt => val)
    s = try; GaussianPICPoissonSolver(; kw...); catch err; nothing; end
    if s === nothing
        @printf("  %-24s = %-12s  rejected at CONSTRUCTION\n", opt, val); continue
    end
    ec, pc = mkflat(); eg, pg = to_gpu(ec), to_gpu(pc)
    rc = try; collide!(s, ec, pc, CPU); "no throw"; catch err; "THROW"; end
    rg = try; collide!(s, eg, pg, GPU); CUDA.synchronize(); "no throw"; catch err; "THROW"; end
    @printf("  %-24s = %-12s  CPU: %-9s CUDA: %s\n", opt, val, rc, rg)
end

println()
println("###### e. dropped-particle counter after a GaussianPIC collide ######")
ec, pc = mkflat()
T = O._pic_cpu_scalar_type(GaussianPICPoissonSolver(slicing=sl5, grid=(64, 64)).pic, ec, pc)
ws = O._pic_cpu_workspace(T, 64, 64)
ws.dropped[] = 7   # poison it, to see whether _gpic_collide! resets or reports
gc_cache = O._pic_green_cache(GaussianPICPoissonSolver(slicing=sl5, grid=(64, 64)).pic, T)
O._gpic_collide!(GaussianPICPoissonSolver(slicing=sl5, grid=(64, 64), green_cache=:none),
                 ec, pc, nothing, ws, gc_cache)
@printf("  workspace.dropped[] before=7 after _gpic_collide! = %d  (PIC's _pic_collide! resets to 0 and warns)\n",
        ws.dropped[])
