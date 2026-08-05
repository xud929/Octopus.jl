using Octopus, CUDA, Printf
const CUDABackend = Octopus.CUDABackend
const O = Octopus
function pair(backend, ET)
    set_global_rng!(seed=11, method=:philox)
    e = Beam(4000, backend, ET; beta=(1.0,1.0,10.0), alpha=(0.0,0.0,0.0),
        sigma=(1.0e-4,1.0e-4,1.0e-2), cutoff=5.0, rng_id=1, charge=-1.0,
        mc2=EMASS_EV, E0=10.0e9, r0=RE*ME0/EMASS_EV, npart=1.7e11)
    p = Beam(4000, backend, ET; beta=(1.0,1.0,10.0), alpha=(0.0,0.0,0.0),
        sigma=(1.0e-4,1.0e-4,1.0e-2), cutoff=5.0, rng_id=2, charge=1.0,
        mc2=PMASS_EV, E0=275.0e9, r0=RE*ME0/PMASS_EV, npart=1.7e11)
    return e, p
end
sl = LongitudinalSlicing(nslices=4, method=:normal_quantile, center_position=:centroid)
slea = LongitudinalSlicing(nslices=4, method=:equal_area, center_position=:centroid)
slec = LongitudinalSlicing(nslices=4, method=:equal_count, center_position=:centroid)

println("### Float32 device compilation of every reachable CUDA route")
for ET in (Float32,)
  for (tag, kw) in (
      ("PIC slice_pair CIC lin  lk=1 iw=1 wf", (interaction_grid=:slice_pair, deposit_method=:CIC, slice_interpolation=:linear, longitudinal_kick=true, cuda_indexed_wavefront=true, batch_mode=:wavefront)),
      ("PIC slice_pair TSC quad lk=0 iw=0 wf", (interaction_grid=:slice_pair, deposit_method=:TSC, slice_interpolation=:quadratic, longitudinal_kick=false, cuda_indexed_wavefront=false, batch_mode=:wavefront)),
      ("PIC slice_pair CIC lin  lk=1 iw=0 sq", (interaction_grid=:slice_pair, deposit_method=:CIC, slice_interpolation=:linear, longitudinal_kick=true, cuda_indexed_wavefront=false, batch_mode=:sequential)),
      ("PIC node       TSC lin  lk=1 iw=1 wf", (interaction_grid=:node, deposit_method=:TSC, slice_interpolation=:linear, longitudinal_kick=true, cuda_indexed_wavefront=true, batch_mode=:wavefront)),
      ("PIC field_derivative=:fourth        ", (field_derivative=:fourth,)),
  )
    e, p = pair(CUDABackend, ET)
    s = PICPoissonSolver(; grid=(32,32), green_cache=:none, slicing=sl, kw...)
    st = try
        O._with_resolved_policy(O.ResolvedCUDAExecutionPolicy(0, 256, :auto)) do
            l = collide!(s, e, p, CUDABackend); CUDA.synchronize()
            isfinite(l) ? "ok  lum=$(l)" : "NONFINITE lum"
        end
    catch err
        "FAIL: " * first(first(split(sprint(showerror, err), '\n')), 100)
    end
    @printf("  %-38s %s\n", tag, st)
  end
  for (tag, slc) in (("slicing=:equal_area", slea), ("slicing=:equal_count", slec))
    e, p = pair(CUDABackend, ET)
    s = PICPoissonSolver(; grid=(32,32), green_cache=:none, slicing=slc)
    st = try
        O._with_resolved_policy(O.ResolvedCUDAExecutionPolicy(0, 256, :auto)) do
            l = collide!(s, e, p, CUDABackend); CUDA.synchronize(); "ok  lum=$(l)"
        end
    catch err
        "FAIL: " * first(first(split(sprint(showerror, err), '\n')), 100)
    end
    @printf("  %-38s %s\n", tag, st)
  end
  for (tag, kw) in (("Gaussian seq coupled lk=1", (batch_mode=:sequential, include_sigma_xy=true, longitudinal_kick=true)),
                    ("Gaussian wf  coupled lk=0", (batch_mode=:wavefront, include_sigma_xy=true, longitudinal_kick=false)),
                    ("Gaussian wf  uncoup  lk=1", (batch_mode=:wavefront, include_sigma_xy=false, longitudinal_kick=true)))
    e, p = pair(CUDABackend, ET)
    s = GaussianPoissonSolver(; slicing=sl, kw...)
    st = try
        O._with_resolved_policy(O.ResolvedCUDAExecutionPolicy(0, 256, :auto)) do
            l = collide!(s, e, p, CUDABackend); CUDA.synchronize(); "ok  lum=$(l)"
        end
    catch err
        "FAIL: " * first(first(split(sprint(showerror, err), '\n')), 100)
    end
    @printf("  %-38s %s\n", tag, st)
  end
end
