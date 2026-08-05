# U10 probe 3:
#  (1) a genuinely DEAD particle (all six coordinates NaN, the aperture
#      convention of src/elements/aperture.jl) inside a colliding slice:
#      does the CPU twin and the CUDA twin behave the same way?
#  (2) coupled (rotated) subtraction parity, CPU vs CUDA indexed wavefront.
#  (3) parity normalized by the momentum scale (the meaningful metric).
using Octopus
using Octopus: CUDA
using Printf
using Statistics: std

const CPU = CPUThreadsBackend
const GPU = Octopus.CUDABackend

to_gpu(b) = begin
    rep = Phase6DRep((CUDA.CuArray(copy(a)) for a in coordinate_arrays(b.rep))...)
    Beam{GPU,typeof(b.params),typeof(rep)}(b.params, rep)
end

function mkbeam(n, sigx, sigy, sigz, seed, rngid, q, mc2, E0, npart; cutoff=5.0)
    set_global_rng!(seed=seed, method=:philox)
    return Beam(n, CPU, Float64;
        beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
        sigma=(sigx, sigy, sigz), cutoff=cutoff, rng_id=rngid,
        charge=q, mc2=mc2, E0=E0, r0=RE * ME0 / mc2, npart=npart)
end

sl5 = LongitudinalSlicing(nslices=5, method=:normal_quantile, center_position=:centroid)
mkflat() = (mkbeam(6000, 106.0e-6, 9.5e-6, 0.7e-2, 19, 1, -1.0, EMASS_EV, 10.0e9, 1.7e11),
            mkbeam(6000, 95.0e-6, 8.5e-6, 6.0e-2, 23, 2, 1.0, PMASS_EV, 275.0e9, 0.7e11))

println("############ (1) DEAD PARTICLE (all-NaN, aperture convention) ############")
for solvername in (:gpic, :pic)
    for indexed in (true, false)
        solvername === :pic && indexed === false && continue
        e, p = mkflat()
        # kill particle 100 of the electron beam exactly as ApertureSpec does
        for a in coordinate_arrays(e.rep); a[100] = NaN; end
        eg, pg = to_gpu(e), to_gpu(p)
        solver = solvername === :gpic ?
            GaussianPICPoissonSolver(slicing=sl5, grid=(64, 64), green_cache=:none,
                deposit_method=:TSC, longitudinal_kick=true, cuda_indexed_wavefront=indexed) :
            PICPoissonSolver(slicing=sl5, grid=(64, 64), green_cache=:none,
                deposit_method=:TSC, longitudinal_kick=true, cuda_indexed_wavefront=indexed)
        cpures = try
            collide!(solver, e, p, CPU); "no throw"
        catch err
            "THROW " * string(typeof(err))
        end
        gpures = try
            collide!(solver, eg, pg, GPU); CUDA.synchronize(); "no throw"
        catch err
            "THROW " * string(typeof(err))
        end
        @printf("%-6s indexed=%-5s  CPU: %-28s  CUDA: %s\n",
                solvername, indexed, cpures, gpures)
        if cpures == "no throw" && gpures == "no throw"
            nnan_cpu = count(isnan, e.rep.px)
            nnan_gpu = count(isnan, Array(eg.rep.px))
            finite_ok = true
            m = 0.0
            for (a, b) in zip(coordinate_arrays(e.rep), coordinate_arrays(eg.rep))
                A = Array(a); B = Array(b)
                msk = isfinite.(A) .& isfinite.(B)
                sc = maximum(abs, A[msk])
                m = max(m, maximum(abs.(A[msk] .- B[msk])) / sc)
                finite_ok &= (isfinite.(A) == isfinite.(B))
            end
            @printf("        NaN count CPU=%d CUDA=%d  same-NaN-mask=%s  survivor reldiff=%.3e\n",
                    nnan_cpu, nnan_gpu, finite_ok, m)
        end
    end
end

println()
println("############ (2) COUPLED subtraction parity (CPU vs CUDA indexed) ############")
function tilt!(b, r)
    sx = std(b.rep.x); sy = std(b.rep.y)
    b.rep.y .= b.rep.y .+ r * (sy / sx) * b.rep.x
    return b
end
for r in (0.1, 0.3, 0.6), dm in (:CIC, :TSC), lk in (false, true)
    e, p = mkflat(); tilt!(e, r); tilt!(p, r)
    base = (copy(e.rep.px), copy(e.rep.py), copy(e.rep.pz))
    eg, pg = to_gpu(e), to_gpu(p)
    solver = GaussianPICPoissonSolver(slicing=sl5, grid=(64, 64), green_cache=:none,
        deposit_method=dm, longitudinal_kick=lk, coupling_tol=0.05)
    collide!(solver, e, p, CPU)
    collide!(solver, eg, pg, GPU); CUDA.synchronize()
    cmax = 0.0
    for (a, b) in zip(coordinate_arrays(e.rep), coordinate_arrays(eg.rep))
        A = Array(a); B = Array(b); sc = maximum(abs, A)
        sc == 0 && continue
        cmax = max(cmax, maximum(abs.(A .- B)) / sc)
    end
    kmax = 0.0
    for (comp, b0) in zip((:px, :py, :pz), base)
        dc = getproperty(e.rep, comp) .- b0
        dg = Array(getproperty(eg.rep, comp)) .- b0
        sc = maximum(abs, b0)
        kmax = max(kmax, maximum(abs.(dc .- dg)) / sc)
    end
    @printf("r=%.2f dm=%-4s lk=%-5s  coord=%.3e  kick/p_rms=%.3e\n", r, dm, lk, cmax, kmax)
end

println()
println("############ (3) mode census: which branch actually ran? ############")
# Instrument by calling the decision helper directly on real slice moments.
e, p = mkflat(); tilt!(e, 0.3); tilt!(p, 0.3)
sl = Octopus.longitudinal_slices(e.rep, sl5)
for i in 1:5
    idx = sl.indices[i]
    coord = Octopus._pic_extract_slice(e.rep, idx)
    mom = Octopus._gpic_source_moments(coord)
    bL = Octopus._gpic_boundary(mom, 1.0e-3)
    bR = Octopus._gpic_boundary(mom, -1.0e-3)
    for tol in (Inf, 0.05, 0.5)
        md = Octopus._gpic_control_variate_mode(mom.n, tol, bL, bR)
        @printf("slice %d n=%5d rxyL=%+.4f tol=%-5s -> %s\n", i, mom.n, bL.rxy, tol, md)
    end
end
