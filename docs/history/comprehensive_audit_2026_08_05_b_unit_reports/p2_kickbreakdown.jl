# U10 probe 2: decompose the CPU<->CUDA kick difference by component, and run
# the SAME comparison for the plain PICPoissonSolver twin as a control. If plain
# PIC shows the same magnitude, the divergence is inherited from the PIC twin
# seam; if only GaussianPIC shows it, it lives in this region.
using Octopus
using Octopus: CUDA
using Printf

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

function report(tag, e0, p0, mksolver)
    solver = mksolver()
    ecpu = deepcopy(e0); pcpu = deepcopy(p0)
    base = Dict{Symbol,Any}()
    for (bn, b) in ((:e, ecpu), (:p, pcpu))
        base[bn] = (px=copy(b.rep.px), py=copy(b.rep.py), pz=copy(b.rep.pz))
    end
    egpu = to_gpu(ecpu); pgpu = to_gpu(pcpu)
    collide!(solver, ecpu, pcpu, CPU)
    collide!(solver, egpu, pgpu, GPU)
    CUDA.synchronize()
    for (bn, cb, gb) in ((:e, ecpu, egpu), (:p, pcpu, pgpu))
        for comp in (:px, :py, :pz)
            b0 = base[bn][comp]
            dc = getproperty(cb.rep, comp) .- b0
            dg = Array(getproperty(gb.rep, comp)) .- b0
            adiff = maximum(abs.(dc .- dg))
            skick = maximum(abs, dc)
            scoord = maximum(abs, b0)
            @printf("%-40s %s.%-3s |dkick|max=%.3e  relkick=%.3e  rel_to_p_rms=%.3e\n",
                    tag, bn, comp, adiff, skick == 0 ? 0.0 : adiff / skick,
                    scoord == 0 ? 0.0 : adiff / scoord)
        end
    end
end

sl5 = LongitudinalSlicing(nslices=5, method=:normal_quantile, center_position=:centroid)
ef = mkbeam(6000, 106.0e-6, 9.5e-6, 0.7e-2, 19, 1, -1.0, EMASS_EV, 10.0e9, 1.7e11)
pf = mkbeam(6000, 95.0e-6, 8.5e-6, 6.0e-2, 23, 2, 1.0, PMASS_EV, 275.0e9, 0.7e11)

println("### GaussianPIC, longitudinal_kick=true, TSC, grid 64")
report("gpic", ef, pf, () -> GaussianPICPoissonSolver(slicing=sl5, grid=(64, 64),
    green_cache=:none, deposit_method=:TSC, longitudinal_kick=true))

println()
println("### plain PIC control, longitudinal_kick=true, TSC, grid 64")
report("pic ", ef, pf, () -> PICPoissonSolver(slicing=sl5, grid=(64, 64),
    green_cache=:none, deposit_method=:TSC, longitudinal_kick=true))

println()
println("### GaussianPIC, longitudinal_kick=false")
report("gpic-nolk", ef, pf, () -> GaussianPICPoissonSolver(slicing=sl5, grid=(64, 64),
    green_cache=:none, deposit_method=:TSC, longitudinal_kick=false))

println()
println("### plain PIC control, longitudinal_kick=false")
report("pic -nolk", ef, pf, () -> PICPoissonSolver(slicing=sl5, grid=(64, 64),
    green_cache=:none, deposit_method=:TSC, longitudinal_kick=false))

println()
println("### GaussianPIC, ns=0 equivalent (margin 0, neutralize off) lk=true")
report("gpic-m0", ef, pf, () -> GaussianPICPoissonSolver(slicing=sl5, grid=(64, 64),
    green_cache=:none, deposit_method=:TSC, longitudinal_kick=true,
    margin_sigma=0.0, neutralize=false))

println()
println("### soft-Gaussian solver control (no grid at all), lk=true")
report("gauss", ef, pf, () -> GaussianPoissonSolver(slicing=sl5, longitudinal_kick=true))
