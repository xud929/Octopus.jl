#=
Validate context-aware policy execution for radiation and weak-strong tracking.
The fast and planned paths must preserve counter-RNG samples and turn signals;
CUDA launch geometry must not change stochastic results. Radiation must remain
in fused tracking, while luminosity observers explicitly isolate weak-strong
elements and preserve CPU/CUDA coordinates and output.

Run from the project root:

    julia --threads=4 --project=. validation/tracking_context_policy_consistency.jl
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus

struct ContextPolicyNoopObserver <: AbstractBeamObserver end
Octopus.observe!(::ContextPolicyNoopObserver, ctx::TrackingContext, rep) = nothing

function base_rep(n=2048)
    return Octopus._contract_default_initial_rep(n, Float64)
end

radiation = LumpedRadSpec{Float64}(
    damping_turns=(4000.0, 5000.0, 3000.0),
    beta=(0.8, 0.072, 90.0), alpha=(0.0, 0.0, 0.0),
    sigma=(95e-6, 8.5e-6, 6e-2), rng_id=901,
)

function run_radiation(policy, backend; planned=false)
    rep = Octopus._contract_rep_for_backend(base_rep(), backend)
    hooks = planned ? (ContextPolicyNoopObserver(),) : ()
    audit = ExecutionAudit()
    set_global_rng!(seed=0x12345678, method=:philox)
    with_execution_audit(audit) do
        execute!(TrackingTask((radiation,); policy=policy, hooks=hooks), rep; turns=3)
        backend === CUDABackend && Octopus.CUDA.synchronize()
    end
    return rep, audit
end

cpu_policy = CPUThreadsExecutionPolicy(threads=min(2, Threads.nthreads(:default)))
cpu_fast, _ = run_radiation(cpu_policy, CPUThreadsBackend)
cpu_planned, _ = run_radiation(cpu_policy, CPUThreadsBackend; planned=true)
cpu_metrics = Octopus._contract_coordinate_metrics(cpu_fast, cpu_planned, 0.0, 0.0)
cpu_metrics[:max_abs_error] == 0.0 || error("CPU fast/planned radiation mismatch")

available, reason = Octopus._contract_backends_available(CUDABackend)
if available
    explicit = CUDAExecutionPolicy(launch=CUDALaunchConfig(threads=128, blocks=3))
    automatic = CUDAExecutionPolicy(launch=CUDALaunchConfig(threads=256, blocks=:auto))
    gpu_explicit, explicit_audit = run_radiation(explicit, CUDABackend)
    gpu_auto, auto_audit = run_radiation(automatic, CUDABackend)
    gpu_metrics = Octopus._contract_coordinate_metrics(gpu_explicit, gpu_auto, 0.0, 0.0)
    gpu_metrics[:max_abs_error] == 0.0 || error("CUDA launch geometry changed radiation RNG")
    for audit in (explicit_audit, auto_audit)
        any(r -> r.consumer === :cuda_fused_launch, execution_receipts(audit)) ||
            error("radiation did not reach fused CUDA tracking")
        any(r -> r.consumer === :cuda_radiation_compatibility_launch,
            execution_receipts(audit)) &&
            error("TrackingTask incorrectly used legacy CUDA radiation tracking")
    end
    cross_metrics = Octopus._contract_coordinate_metrics(cpu_fast, gpu_auto, 1e-10, 1e-10)
    cross_metrics[:passed_tolerance] || error("CPU/CUDA radiation mismatch")
else
    println("CUDA radiation checks skipped: ", reason)
end

weak = ThinStrongBeamSpec{Float64}(
    kbb=1e-8, klum=1.0, beta=(0.82, 0.075), alpha=(0.01, -0.02),
    sigma=(110e-6, 12e-6),
    centroid_signal=LinearTurnSignal((0.0, 0.0), (1e-7, -2e-7)),
)

function run_weak(policy, backend, path)
    rep = Octopus._contract_rep_for_backend(base_rep(), backend)
    observer = ScheduledObserver(LuminosityObserver(path))
    audit = ExecutionAudit()
    with_execution_audit(audit) do
        execute!(TrackingTask((weak, observer); policy=policy), rep; turns=2)
        backend === CUDABackend && Octopus.CUDA.synchronize()
    end
    return rep, audit
end

mktempdir() do dir
    cpu_weak, cpu_audit = run_weak(cpu_policy, CPUThreadsBackend, joinpath(dir, "cpu.tsv"))
    count(r -> r.consumer === :isolated_tracking, execution_receipts(cpu_audit)) == 2 ||
        error("CPU weak-strong diagnostic isolation/update count mismatch")
    if available
        gpu_weak, gpu_audit = run_weak(
            CUDAExecutionPolicy(launch=CUDALaunchConfig(threads=128, blocks=3)),
            CUDABackend, joinpath(dir, "gpu.tsv"),
        )
        count(r -> r.consumer === :isolated_tracking, execution_receipts(gpu_audit)) == 2 ||
            error("CUDA weak-strong diagnostic isolation/update count mismatch")
        metrics = Octopus._contract_coordinate_metrics(cpu_weak, gpu_weak, 1e-10, 1e-10)
        metrics[:passed_tolerance] || error("CPU/CUDA isolated weak-strong mismatch")
        cpu_lum = readlines(joinpath(dir, "cpu.tsv"))
        gpu_lum = readlines(joinpath(dir, "gpu.tsv"))
        length(cpu_lum) == length(gpu_lum) == 2 || error("weak-strong luminosity row mismatch")
    end
end

println("tracking context/policy consistency validation passed")
