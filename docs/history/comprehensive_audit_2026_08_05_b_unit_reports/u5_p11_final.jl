using Octopus
const O = Octopus
println("=== F1: declared dependencies vs the _pic_option_active gate ===")
sch = O.solver_option_schema(PICPoissonSolver)
for (n, m) in pairs(sch)
    isempty(m.dependencies) && continue
    # does _pic_option_active ever return false for this name?
    gated = n in (:slice_pair_green_min_ratio, :slice_pair_green_growth, :cuda_batch_fft,
                  :cuda_wavefront_fft, :cuda_indexed_wavefront)
    println("  ", rpad(n, 28), " dependencies=", m.dependencies,
            "  gated by _pic_option_active: ", gated)
end
println()
println("=== F2: any option restricted to CPU only (would be inert on CUDA, unwarned)? ===")
for T in (PICPoissonSolver, GaussianPoissonSolver, O.SpectralPoissonSolver,
          O.GaussianPICPoissonSolver)
    for (n, m) in pairs(O.solver_option_schema(T))
        (CUDABackend in m.supported_backends) ||
            println("  CPU-ONLY: ", nameof(T), ".", n, " backends=", m.supported_backends)
    end
end
for (n, m) in pairs(O.diagnostics_option_schema())
    (CUDABackend in m.supported_backends) ||
        println("  CPU-ONLY diagnostic: ", n, " backends=", m.supported_backends)
end
println("  (nothing above => the CPU-side preflight warning has no CUDA-side mirror to need)")
println()
println("=== F3: LongitudinalSlicing methods accepted vs documented ===")
accepted = Symbol[]
for m in (:equal_area, :equal_count, :equal_width, :equal_spaced, :normal_quantile,
          :gaussian, :Gaussian, :specified)
    try
        LongitudinalSlicing(nslices=1, method=m); push!(accepted, m)
    catch; end
end
doc = string(@doc LongitudinalSlicing)
println("  accepted by constructor: ", accepted)
println("  NOT named in the docstring: ", [m for m in accepted if !occursin(string(m), doc)])
println()
println("=== F4: is strong_strong_task_option_schema part of the public surface? ===")
println("  exported by Octopus: ", :strong_strong_task_option_schema in names(Octopus))
for f in (:slicing_option_schema, :cuda_pic_launch_option_schema, :diagnostics_option_schema,
          :solver_option_schema, :solver_configuration, :observer_option_schema,
          :policy_option_schema, :schedule_option_schema)
    println("  ", rpad(f, 30), " exported: ", f in names(Octopus))
end
