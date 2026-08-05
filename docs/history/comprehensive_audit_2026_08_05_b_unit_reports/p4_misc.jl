using Octopus
using InteractiveUtils: subtypes
const O = Octopus

println("=== C2. :cuda_pic_launch receipt branch, with a receipt that HAS blocks ===")
struct FakeReceipt; consumer::Symbol; values; end
recs = [FakeReceipt(:cuda_pic_launch, (family=:kick, threads=999, blocks=7))]
for nm in (:backend_configurations, :threads, :blocks)
    println("  name=", rpad(string(nm), 24), " -> ",
            O._solver_contract_receipt_carries(recs, :cuda_pic_launch, nm, :never_published))
end
println("  (the ONLY options declaring consumer :cuda_pic_launch are")
println("   PICPoissonSolver.backend_configurations and GaussianPICPoissonSolver.backend_configurations,")
println("   both of which take the `|| return true` short-circuit)")
println()
println("  latent crash: a receipt with :threads but no :blocks + name===:blocks ->")
recs2 = [FakeReceipt(:cuda_pic_launch, (family=:kick, threads=999))]
try
    O._solver_contract_receipt_carries(recs2, :cuda_pic_launch, :blocks, 7)
    println("    no throw")
catch e
    println("    THROWS ", nameof(typeof(e)), ": ", sprint(showerror, e))
end

println()
println("=== D. validate(contract; kwargs...) silently ignores unknown keywords ===")
r1 = validate(SymplecticityContract())
r2 = validate(SymplecticityContract(); tolerance=1.0e-30, this_kwarg_does_not_exist=42)
println("  identical result with nonsense kwargs? ", r1.passed == r2.passed && r1.message == r2.message)
println("  status=", r2.status)
println("  every validate method signature accepts kwargs...; none read them:")
println("  ctor rejects unknown kw? ",
        try (SymplecticityContract(nonsense=1); "NO (accepted)") catch e; "yes ($(nameof(typeof(e))))" end)

println()
println("=== E. PublicConfiguration worker sweep degeneracy ===")
nt = Threads.nthreads(:default)
sweep = unique((1, min(2, nt), nt))
println("  nthreads(:default)=", nt, "  worker_sweep=", sweep,
        "  -> worker-invariance comparisons executed = ", max(length(sweep) - 1, 0))

println()
println("=== F. SolverOptionEffectiveness tripwire vs swept set ===")
# The guard checks contract.probes; the sweep iterates the hardcoded
# _solver_contract_types(). Add an Octopus-defined solver WITH a probe entry
# but absent from the hardcoded tuple: the guard passes, the sweep skips it.
@eval O struct AuditGhostSolver <: AbstractPoissonSolver end
println("  concrete Octopus AbstractPoissonSolver subtypes now: ",
        [T for T in subtypes(O.AbstractPoissonSolver) if !isabstracttype(T)])
println("  _solver_contract_types() (the SWEPT set) is unchanged: ", O._solver_contract_types())
probes = copy(O._default_solver_option_probes())
probes[:AuditGhostSolver] = NamedTuple()          # the natural response to the guard
r = validate(SolverOptionEffectivenessContract(probes=probes))
println("  contract status with a ghost solver that has a probe but is never swept: ", r.status)
println("  message: ", r.message)
# and the control: without a probe entry the guard does fire
r2 = validate(SolverOptionEffectivenessContract())
println("  control (no probe entry for the ghost): ", r2.status, " | ", r2.message[1:min(90,end)])
