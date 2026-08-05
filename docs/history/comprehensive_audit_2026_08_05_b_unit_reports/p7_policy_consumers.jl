## Executed policy-field -> runtime-consumer table. Each public policy field is
## set to a NON-default value and the execution audit is asked whether that
## value reached a consumer boundary. Also probes the receipt `backend` field.

using Octopus

const ELEMS = (DriftSpec(L=0.5), QuadrupoleSpec(L=0.3, k1=1.2))

function run(policy, backend)
    rep = Octopus._contract_rep_for_backend(
        Octopus._contract_default_initial_rep(4096, Float64), backend)
    audit = ExecutionAudit()
    with_execution_audit(audit) do
        execute!(TrackingTask(ELEMS; policy=policy), rep; turns=2)
        backend === CUDABackend && Octopus.CUDA.synchronize()
    end
    return execution_receipts(audit)
end

show_sel(rs, c) = begin
    sel = filter(r -> r.consumer === c, rs)
    println("    ", rpad(string(c), 22), "n=", length(sel),
            "  values=", isempty(sel) ? "-" : string(unique(r.values for r in sel)),
            "  backend=", isempty(sel) ? "-" : string(unique(r.backend for r in sel)))
    return sel
end

println("== CPUThreadsExecutionPolicy(threads=3) ==")
rs_cpu = run(CPUThreadsExecutionPolicy(threads=min(3, Threads.nthreads(:default))),
             CPUThreadsBackend)
show_sel(rs_cpu, :cpu_logical_workers)

avail, reason = Octopus._contract_backends_available(CUDABackend)
if avail
    println("== CUDAExecutionPolicy(device=0, launch=(threads=128, blocks=7)) ==")
    rs = run(CUDAExecutionPolicy(device=0, launch=CUDALaunchConfig(threads=128, blocks=7)),
             CUDABackend)
    show_sel(rs, :cuda_device)
    show_sel(rs, :cuda_fused_launch)

    println("== CUDAExecutionPolicy(launch=(threads=64, blocks=:auto)) ==")
    rs = run(CUDAExecutionPolicy(launch=CUDALaunchConfig(threads=64, blocks=:auto)),
             CUDABackend)
    show_sel(rs, :cuda_device)
    show_sel(rs, :cuda_fused_launch)

    println("== GPUExecutionPolicy(threads=32, blocks=5, device=0) [deprecated] ==")
    rs = run(GPUExecutionPolicy(threads=32, blocks=5, device=0), CUDABackend)
    show_sel(rs, :cuda_device)
    show_sel(rs, :cuda_fused_launch)
else
    println("CUDA legs skipped: ", reason)
end

println("== PlaceholderPolicy ==")
try
    backend_type(PlaceholderPolicy())
    println("  backend_type returned WITHOUT error -- unexpected")
catch err
    println("  backend_type errors as documented: ", first(split(sprint(showerror, err), '\n')))
end
try
    run(PlaceholderPolicy(), CPUThreadsBackend)
    println("  execute! with PlaceholderPolicy SUCCEEDED -- unexpected")
catch err
    println("  execute! errors: ", first(split(sprint(showerror, err), '\n')))
end
println("  configuration_report = ", configuration_report(PlaceholderPolicy()))
println("  policy_option_schema = ", policy_option_schema(PlaceholderPolicy()))
println("  description          = ", description(PlaceholderPolicy))

println()
println("== configuration_report field content (is `reason` ever consumed?) ==")
for e in configuration_report(CPUThreadsExecutionPolicy(threads=1))
    println("  ", e)
end
