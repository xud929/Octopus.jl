using Octopus
const O = Octopus

println("=== A. solver option consumers, by solver; which are :cuda_pic_launch ===")
for T in O._solver_contract_types()
    kind = nameof(T)
    for (name, meta) in pairs(O.solver_option_schema(T))
        if meta.consumer === :cuda_pic_launch
            println("  ", rpad(string(kind), 26), ".", rpad(string(name), 26),
                    " category=", meta.category,
                    " cpu_supported=", O.CPUThreadsBackend in meta.supported_backends)
        end
    end
end

println()
println("=== B. every (solver, option) consumer/category/backends, and its route in the contract ===")
contract = SolverOptionEffectivenessContract()
for T in O._solver_contract_types()
    kind = nameof(T)
    alts = get(contract.alternatives, kind, Dict{Symbol,Any}())
    for (name, meta) in pairs(O.solver_option_schema(T))
        route = if haskey(contract.inactive, (kind, name)); "INACTIVE(excused)"
        elseif !haskey(alts, name); "NO-ALTERNATIVE(fails)"
        elseif !(O.CPUThreadsBackend in meta.supported_backends); "CUDA-ONLY"
        else "CPU" end
        exec = meta.category in (:execution, :performance)
        println("  ", rpad(string(kind), 26), ".", rpad(string(name), 28),
                " cat=", rpad(string(meta.category), 22),
                " consumer=", rpad(string(meta.consumer), 24),
                " ", rpad(route, 20), exec ? " [execution-half]" : "")
    end
end

println()
println("=== C. _solver_contract_receipt_carries: does the :cuda_pic_launch branch ever compare? ===")
# Synthesise a receipt exactly as cuda_pic_launch publishes and ask the helper
# about an option name that is neither :threads nor :blocks.
struct FakeReceipt; consumer::Symbol; values; end
recs = [FakeReceipt(:cuda_pic_launch, (family=:kick, threads=999))]
for nm in (:backend_configurations, :threads, :blocks, :total_nonsense)
    got = O._solver_contract_receipt_carries(recs, :cuda_pic_launch, nm, :a_value_never_published)
    println("  name=", rpad(string(nm), 26), " requested=:a_value_never_published -> ", got)
end

println()
println("=== D. validate(contract; kwargs...) silently ignores unknown keywords ===")
r1 = validate(SymplecticityContract())
r2 = validate(SymplecticityContract(); tolerance=1.0e-30, this_kwarg_does_not_exist=42)
println("  same result with a nonsense kwarg? ", r1.passed == r2.passed && r1.message == r2.message)
println("  -> ", r2.status, " ", r2.message[1:min(60,end)])
println("  ctor rejects unknown kw? ",
        try SymplecticityContract(nonsense=1); "NO (accepted)" catch e; "yes ($(nameof(typeof(e))))" end)

println()
println("=== E. PublicConfiguration worker sweep degeneracy ===")
nt = Threads.nthreads(:default)
sweep = unique((1, min(2, nt), nt))
println("  nthreads(:default)=", nt, "  worker_sweep=", sweep,
        "  -> worker-invariance comparisons executed = ", max(length(sweep) - 1, 0))
println("  (with -t1 the sweep is (1,) and the invariance comparison never runs,")
println("   yet metrics[:cpu_worker_coordinate_max_abs_error]=0.0 and [:cpu_worker_effective]=true)")
