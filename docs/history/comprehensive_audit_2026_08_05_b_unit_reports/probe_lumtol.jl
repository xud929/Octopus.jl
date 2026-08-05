using Octopus, Printf
mk(seed, ns, meth) = begin
    pair() = begin
        set_global_rng!(seed=seed, method=:philox)
        e = Beam(6000, CPUThreadsBackend, Float64; beta=(0.55,0.056,12.0), alpha=(0.0,0.0,0.0),
            sigma=(106.0e-6,9.5e-6,7.0e-3), cutoff=5.0, rng_id=1, charge=-1.0,
            mc2=EMASS_EV, E0=10.0e9, r0=RE*ME0/EMASS_EV, npart=1.7e11)
        p = Beam(6000, CPUThreadsBackend, Float64; beta=(0.8,0.072,90.0), alpha=(0.0,0.0,0.0),
            sigma=(95.0e-6,8.5e-6,6.0e-2), cutoff=5.0, rng_id=2, charge=1.0,
            mc2=PMASS_EV, E0=275.0e9, r0=RE*ME0/PMASS_EV, npart=0.7e11)
        (e,p)
    end
    sl = LongitudinalSlicing(nslices=ns, method=meth, center_position=:centroid)
    (pair, sl)
end
function lums(seed, ns, meth, kwlist)
    pair, sl = mk(seed, ns, meth)
    out = Float64[]
    for kw in kwlist
        e,p = pair()
        push!(out, collide!(PICPoissonSolver(; slicing=sl, grid=(64,64), kw...), e, p, CPUThreadsBackend))
    end
    out
end
l = lums(77, 3, :normal_quantile, ((;), (; field_derivative=:fourth)))
@printf("6131 field_derivative :fourth vs default  reldiff=%.3g (rtol 1e-3, headroom %.0fx)\n",
        abs(l[2]-l[1])/abs(l[1]), 1e-3/(abs(l[2]-l[1])/abs(l[1])))
l = lums(91, 3, :normal_quantile, ((;), (; slice_interpolation=:quadratic)))
@printf("6201 slice_interpolation :quadratic       reldiff=%.3g (rtol 1e-3, headroom %.0fx)\n",
        abs(l[2]-l[1])/abs(l[1]), 1e-3/(abs(l[2]-l[1])/abs(l[1])))
l = lums(53, 4, :normal_quantile, ((;), (; interaction_grid=:source_slice), (; interaction_grid=:node)))
@printf("6301 interaction_grid :source_slice       reldiff=%.3g (rtol 1e-3)\n", abs(l[2]-l[1])/abs(l[1]))
@printf("6335 interaction_grid :node              reldiff=%.3g (rtol 1e-3)\n", abs(l[3]-l[1])/abs(l[1]))
pair, sl5 = mk(64, 5, :normal_quantile)
sl5 = LongitudinalSlicing(nslices=5, method=:normal_quantile)
base = nothing; res = Float64[]
for kw in ((;), (; grid_extent=:sigma), (; grid_quantize=0.125), (; grid_extent=:sigma, grid_quantize=0.125))
    e,p = pair()
    push!(res, collide!(PICPoissonSolver(; slicing=sl5, grid=(64,64), kw...), e, p, CPUThreadsBackend))
end
for (i,nm) in enumerate((":sigma", "quantize", "both"))
    @printf("6436 grid_extent %-9s               reldiff=%.3g (rtol 5e-3, headroom %.0fx)\n",
            nm, abs(res[i+1]-res[1])/abs(res[1]), 5e-3/(abs(res[i+1]-res[1])/abs(res[1])))
end
