using Octopus
const O = Octopus
show_r(label, r) = println(rpad(label, 50), " ", rpad(string(r.status), 9), " | ",
                           first(split(r.message, '\n'))[1:min(120,end)])

println("threads=", Threads.nthreads(), "  CUDA functional=", O.CUDA.functional())
println("global RNG before: seed=", repr(O.global_rng_seed()), " method=", O.global_rng_method())
O.set_global_rng!(seed=0xDEADBEEF, method=:philox)
sentinel = O.global_rng_seed()

for (label, c) in (
        ("SymplecticityContract",                         SymplecticityContract()),
        ("ElementParameterEffectivenessContract",         ElementParameterEffectivenessContract()),
        ("PTCConsistencyContract",                        PTCConsistencyContract()),
        ("KnobEffectivenessContract",                     KnobEffectivenessContract()),
        ("PublicConfigurationEffectivenessContract",      PublicConfigurationEffectivenessContract()),
        ("SolverOptionEffectivenessContract",             SolverOptionEffectivenessContract()),
        ("StrongStrongGaussianBackendConsistency",        StrongStrongGaussianBackendConsistencyContract()),
        ("StrongStrongPICBackendConsistency",             StrongStrongPICBackendConsistencyContract()),
        ("StrongStrongPIC(green_cache=:none,seq)",        StrongStrongPICBackendConsistencyContract(green_cache=:none, batch_mode=:sequential)),
        ("HighEnergyWeakStrongLimitContract",             HighEnergyWeakStrongLimitContract()),
        ("CoherentModePhysicsContract(:pic)",             CoherentModePhysicsContract()),
        ("CoherentModePhysicsContract(:gaussian_pic)",    CoherentModePhysicsContract(solver=:gaussian_pic)),
    )
    r = try validate(c) catch e; (status=:THREW, message=sprint(showerror, e), metrics=Dict()) end
    show_r(label, r)
    leaked = O.global_rng_seed() != sentinel
    leaked && println("      !! RNG LEAK: seed now ", repr(O.global_rng_seed()))
    O.set_global_rng!(seed=sentinel, method=:philox)
    if label == "StrongStrongPIC(green_cache=:none,seq)"
        for k in (:cache_histories_match, :cache_reuse_observed, :cpu_cache_history,
                  :gpu_cache_history, :slice_pair_luminosity_records_compared,
                  :slice_pair_luminosity_rel_error, :slice_pair_luminosity_passed_tolerance)
            haskey(r.metrics, k) && println("      ", rpad(string(k), 42), " = ", r.metrics[k])
        end
    end
    if startswith(label, "SolverOption") || startswith(label, "PublicConfiguration")
        for (k, v) in sort(collect(r.metrics); by=x->string(x[1]))
            k in (:cpu_options_checked, :cuda_only_options, :cuda_options_checked,
                  :cuda_launch_solvers_checked, :cuda_status, :cpu_workers_tested,
                  :cpu_worker_coordinate_max_abs_error, :cuda_pic_families_observed) &&
                println("      ", rpad(string(k), 42), " = ", v)
        end
    end
end
