using Octopus
const O = Octopus

println("=== G. :solver_runtime receipt is a dump of the object under test ===")
# Reproduce exactly what the contract does for an execution-category option
# whose declared consumer is :solver_runtime. The only such option today is
# GaussianPoissonSolver.batch_mode (category :performance, CUDA-only).
meta = O.solver_option_schema(O.GaussianPoissonSolver).batch_mode
println("  GaussianPoissonSolver.batch_mode  category=", meta.category,
        " consumer=", meta.consumer,
        " supported_backends=", meta.supported_backends)

base1, base2 = O._strong_strong_contract_base_beams(
    StrongStrongPICBackendConsistencyContract(n_particles=64))
solver = O.GaussianPoissonSolver(
    slicing=O.LongitudinalSlicing(nslices=3, method=:normal_quantile),
    batch_mode=:sequential)
# Run on the CPU backend, where the option is BY ITS OWN DECLARATION inactive
# (CPUThreadsBackend is not in supported_backends).
_, _, receipts_cpu = O._solver_contract_observable(solver, base1, base2, O.CPUThreadsBackend)
println("  CPU half: :solver_runtime receipts = ",
        count(r -> r.consumer === :solver_runtime, receipts_cpu),
        "  (the CPU observable calls collide! directly, bypassing _strong_strong_collide!,")
println("   so NO CPU option ever exercises _solver_contract_receipt_carries)")
_, _, receipts = O._solver_contract_cuda_observable(solver, base1, base2)
sr = [r for r in receipts if r.consumer === :solver_runtime]
println("  CUDA half: :solver_runtime receipts = ", length(sr))
println("  receipt.configuration.batch_mode = ", sr[1].values.configuration.batch_mode)
println("  _solver_contract_receipt_carries(..., :solver_runtime, :batch_mode, :sequential) = ",
        O._solver_contract_receipt_carries(receipts, :solver_runtime, :batch_mode, :sequential))
println("  the receipt is emitted by _strong_strong_collide! (interface.jl) from")
println("  solver_configuration(solver) BEFORE any backend code runs, so it reports")
println("  the value we set, not a value any consumer read.")

println()
println("=== H. HighEnergyWeakStrongLimit 'reference' shares the production kernel ===")
for f in (:_slice_slice_gaussian_kick!, :_slice_transverse_moments, :_slice_collision_order)
    ms = methods(getfield(O, f))
    println("  ", rpad(string(f), 30), " methods=", length(ms),
            " defined at ", [string(m.file, ":", m.line) for m in ms][1:min(3,end)])
end

println()
println("=== I. StrongStrongPIC contract: vacuous halves reachable from public options ===")
c1 = StrongStrongPICBackendConsistencyContract(green_cache=:none, turns=2, batch_mode=:sequential)
println("  green_cache=:none  -> cache_reuse_ok is forced true by `green_cache != :slice_pair`")
println("  batch_mode=:sequential -> pair_trace_expected=false -> pair check vacuous, rel error recorded as 0.0")
println("  unknown batch_mode accepted by the CONTRACT struct? ",
        try (StrongStrongPICBackendConsistencyContract(batch_mode=:typo); "YES") catch e; "no" end)
println("  ... and by the solver it builds? ",
        try (O.PICPoissonSolver(grid=(16,16), batch_mode=:typo); "YES (silent)") catch e;
            "no ($(nameof(typeof(e))))" end)
println("  unknown green_cache accepted by the CONTRACT struct? ",
        try (StrongStrongPICBackendConsistencyContract(green_cache=:typo); "YES") catch e; "no" end)
println("  ... and by the solver? ",
        try (O.PICPoissonSolver(grid=(16,16), green_cache=:typo); "YES (silent)") catch e;
            "no ($(nameof(typeof(e))))" end)

println()
println("=== J. StrongStrongTask defaults: schema vs a SECOND hand copy ===")
println("  validate_configuration_metadata compares strong_strong_task_option_schema()")
println("  against the literal (luminosity_path=nothing, luminosity_append=false),")
println("  not against the StrongStrongTask constructor. Real constructor defaults:")
t = O.StrongStrongTask((O.StrongStrongCollision(:ip),), (O.StrongStrongCollision(:ip),))
for f in (:luminosity_path, :luminosity_append)
    println("    StrongStrongTask.", rpad(string(f), 20), " = ", getproperty(t, f),
            "   schema.default = ", getproperty(O.strong_strong_task_option_schema(), f).default)
end

println()
println("=== K. BPMObserver schema<->report check is guaranteed by construction ===")
b = O.BPMObserver()
schema_names = Set(keys(O.observer_option_schema(b)))
report_names = Set(e.name for e in O.configuration_report(b))
println("  equal? ", schema_names == report_names,
        "  (configuration_report(::BPMObserver) iterates the same schema it is compared to)")
