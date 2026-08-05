## `_active_cuda_launch` is a SECOND consumer of CUDAExecutionPolicy's
## threads/blocks. Measure: (a) it returns the policy's values, (b) it emits no
## execution receipt, (c) its `:auto` rule differs from the fused path's.

using Octopus
using Octopus: _active_cuda_launch, _with_resolved_policy, ResolvedCUDAExecutionPolicy

pol = ResolvedCUDAExecutionPolicy(0, 64, 3)     # device, threads, blocks
audit = ExecutionAudit()
with_execution_audit(audit) do
    _with_resolved_policy(pol) do
        for n in (100, 100_000, 10_000_000)
            println("  explicit blocks=3, n=", n, " -> ", _active_cuda_launch(n))
        end
    end
end
println("  receipts emitted by these calls: ", length(execution_receipts(audit)))

pol_auto = ResolvedCUDAExecutionPolicy(0, 64, :auto)
with_execution_audit(ExecutionAudit()) do
    _with_resolved_policy(pol_auto) do
        for n in (100, 100_000, 10_000_000)
            println("  blocks=:auto,     n=", n, " -> ", _active_cuda_launch(n),
                    "   (coverage cld(n,64)=", cld(n, 64), ", capped at 256)")
        end
    end
end

println("  outside any resolved-policy scope: ", _active_cuda_launch(1_000_000),
        "  <- silently ignores the user's launch request")

println()
println("  declared consumers for CUDAExecutionPolicy options:")
for (name, meta) in pairs(policy_option_schema(CUDAExecutionPolicy))
    println("    ", rpad(string(name), 9), "consumer=", meta.consumer)
end
