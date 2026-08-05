using Octopus
const O = Octopus
println("nthreads(:default) = ", Threads.nthreads(:default))
println("worker_sweep = ", unique((1, min(2, Threads.nthreads(:default)), Threads.nthreads(:default))))
r = validate(PublicConfigurationEffectivenessContract())
println("status = ", r.status)
for k in (:cpu_workers_tested, :cpu_worker_receipts, :cpu_worker_coordinate_max_abs_error,
          :cpu_worker_effective, :cuda_status)
    println("  ", rpad(string(k), 40), " = ", get(r.metrics, k, "<absent>"))
end
println("-> at one thread the invariance comparison at Contracts.jl:344-348 executes ZERO times,")
println("   yet :cpu_worker_coordinate_max_abs_error and :cpu_worker_effective are reported as measured.")
