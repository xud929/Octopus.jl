export PlaceholderPolicy, CPUThreadsExecutionPolicy,
       AbstractGPUExecutionPolicy, CUDALaunchConfig, CUDAExecutionPolicy,
       GPUExecutionPolicy, backend_type, activate_policy!,
       ConfigurationOptionMeta, ConfigurationEntry, policy_option_schema,
       configuration_report, validate_configuration_metadata,
       ExecutionAudit, ExecutionAuditReceipt,
       with_execution_audit, execution_receipts

"""
    ConfigurationOptionMeta(option_type, default, meaning; ...)

Structured metadata for a public configuration option. `consumer` names the
runtime boundary that must apply the resolved value; `supported_backends` and
`dependencies` explain when the option can be active.
"""
struct ConfigurationOptionMeta
    option_type::Any
    default::Any
    meaning::String
    category::Symbol
    supported_backends::Tuple
    dependencies::Tuple{Vararg{Symbol}}
    consumer::Symbol
end

ConfigurationOptionMeta(option_type, default, meaning;
                        category=:execution,
                        supported_backends=(),
                        dependencies=(),
                        consumer=:unspecified) =
    ConfigurationOptionMeta(option_type, default, String(meaning), Symbol(category),
                            Tuple(supported_backends), Tuple(Symbol.(dependencies)),
                            Symbol(consumer))

"""One requested/resolved configuration value and its effectiveness status."""
struct ConfigurationEntry
    name::Symbol
    requested::Any
    resolved::Any
    status::Symbol
    reason::String
    consumer::Symbol
end

"""A receipt emitted at an actual execution consumer boundary."""
struct ExecutionAuditReceipt
    consumer::Symbol
    backend::Any
    values::NamedTuple
end

"""
    ExecutionAudit()

Opt-in collection of configuration-effectiveness receipts. Normal execution
does not allocate receipts and does not synchronize merely for auditing.
"""
mutable struct ExecutionAudit
    receipts::Vector{ExecutionAuditReceipt}
end
ExecutionAudit() = ExecutionAudit(ExecutionAuditReceipt[])

const _ACTIVE_EXECUTION_AUDIT = Base.ScopedValues.ScopedValue{Any}(nothing)
const _ACTIVE_RESOLVED_POLICY = Base.ScopedValues.ScopedValue{Any}(nothing)

execution_receipts(audit::ExecutionAudit) = copy(audit.receipts)

"""Run `f()` while recording actual configuration consumers into `audit`."""
function with_execution_audit(f::F, audit::ExecutionAudit=ExecutionAudit()) where {F}
    Base.ScopedValues.with(_ACTIVE_EXECUTION_AUDIT => audit) do
        f()
    end
    return audit
end

function _record_execution!(consumer::Symbol, backend, values::NamedTuple)
    audit = _ACTIVE_EXECUTION_AUDIT[]
    audit === nothing || push!(audit.receipts, ExecutionAuditReceipt(consumer, backend, values))
    return nothing
end

function _with_resolved_policy(f::F, policy) where {F}
    return Base.ScopedValues.with(_ACTIVE_RESOLVED_POLICY => policy) do
        f()
    end
end

"""
    PlaceholderPolicy()

Placeholder execution policy used for examples and metadata until a real
execution choice is required. It intentionally does not imply slicing,
accuracy, MPI, or backend behavior.
"""
struct PlaceholderPolicy <: AbstractExecutionPolicy end

"""
    CPUThreadsExecutionPolicy(; threads=:auto)

Run with a fixed number of Octopus logical workers in Julia's default thread
pool. `:auto` resolves to `Threads.nthreads(:default)`. An integer must be in
`1:Threads.nthreads(:default)`; values are rejected rather than clamped.

Logical workers are work partitions/tasks. Julia's scheduler decides which OS
threads execute them, so this policy does not promise thread pinning.
"""
struct CPUThreadsExecutionPolicy <: AbstractExecutionPolicy
    threads::Union{Int,Symbol}
    function CPUThreadsExecutionPolicy(threads::Union{Integer,Symbol})
        if threads isa Symbol
            threads === :auto || throw(ArgumentError(
                "CPU threads must be :auto or an integer; got $(repr(threads))."))
            return new(:auto)
        end
        n = Int(threads)
        max_threads = Threads.nthreads(:default)
        1 <= n <= max_threads || throw(ArgumentError(
            "CPU threads must be in 1:$(max_threads); got $(n)."))
        return new(n)
    end
end
CPUThreadsExecutionPolicy(; threads=:auto) = CPUThreadsExecutionPolicy(threads)

abstract type AbstractGPUExecutionPolicy <: AbstractExecutionPolicy end

"""
    CUDALaunchConfig(; threads=256, blocks=:auto)

Launch geometry for fused CUDA tracking. `blocks=:auto` uses occupancy and
particle coverage; a positive integer preserves an explicit tuning choice.
"""
struct CUDALaunchConfig
    threads::Int
    blocks::Union{Int,Symbol}
    function CUDALaunchConfig(threads::Integer, blocks::Union{Integer,Symbol})
        nt = Int(threads)
        nt > 0 || throw(ArgumentError("CUDA threads must be positive; got $(nt)."))
        if blocks isa Symbol
            blocks === :auto || throw(ArgumentError(
                "CUDA blocks must be :auto or a positive integer; got $(repr(blocks))."))
            return new(nt, :auto)
        end
        nb = Int(blocks)
        nb > 0 || throw(ArgumentError("CUDA blocks must be positive; got $(nb)."))
        return new(nt, nb)
    end
end
CUDALaunchConfig(; threads::Integer=256, blocks=:auto) =
    CUDALaunchConfig(threads, blocks)

"""
    CUDAExecutionPolicy(; device=nothing, launch=CUDALaunchConfig())

Execution policy for CUDA storage. `device=nothing` resolves from particle
storage when tracking and keeps the current CUDA device only while allocating a
new `Beam`. CUDA-specific launch choices live in `CUDALaunchConfig`.
"""
struct CUDAExecutionPolicy <: AbstractGPUExecutionPolicy
    device::Union{Nothing,Int}
    launch::CUDALaunchConfig
    function CUDAExecutionPolicy(device, launch::CUDALaunchConfig)
        dev = device === nothing ? nothing : Int(device)
        dev === nothing || dev >= 0 || throw(ArgumentError(
            "CUDA device must be a nonnegative index or nothing; got $(repr(device))."))
        return new(dev, launch)
    end
end
CUDAExecutionPolicy(; device=nothing, launch::CUDALaunchConfig=CUDALaunchConfig()) =
    CUDAExecutionPolicy(device, launch)

"""
    GPUExecutionPolicy(; threads=256, blocks=256, device=nothing)

Deprecated compatibility policy for the historical CUDA-only `GPU` name. New
code should use `CUDAExecutionPolicy(launch=CUDALaunchConfig(...))`.
"""
struct GPUExecutionPolicy <: AbstractGPUExecutionPolicy
    threads::Int
    blocks::Int
    device::Union{Nothing,Int}
    function GPUExecutionPolicy(threads::Integer, blocks::Integer, device)
        Base.depwarn(
            "GPUExecutionPolicy is deprecated; use CUDAExecutionPolicy with CUDALaunchConfig.",
            :GPUExecutionPolicy,
        )
        launch = CUDALaunchConfig(threads, blocks)
        dev = device === nothing ? nothing : Int(device)
        dev === nothing || dev >= 0 || throw(ArgumentError(
            "CUDA device must be a nonnegative index or nothing; got $(repr(device))."))
        return new(launch.threads, launch.blocks, dev)
    end
end
GPUExecutionPolicy(threads::Integer, blocks::Integer) =
    GPUExecutionPolicy(threads, blocks, nothing)
GPUExecutionPolicy(; threads::Integer=256, blocks::Integer=256, device=nothing) =
    GPUExecutionPolicy(threads, blocks, device)

abstract type AbstractResolvedExecutionPolicy end
struct ResolvedCPUExecutionPolicy <: AbstractResolvedExecutionPolicy
    threads::Int
end
struct ResolvedCUDAExecutionPolicy <: AbstractResolvedExecutionPolicy
    device::Int
    threads::Int
    blocks::Union{Int,Symbol}
end

backend_type(::CPUThreadsExecutionPolicy) = CPUThreadsBackend
backend_type(::CUDAExecutionPolicy) = CUDABackend
backend_type(::GPUExecutionPolicy) = CUDABackend
backend_type(::ResolvedCPUExecutionPolicy) = CPUThreadsBackend
backend_type(::ResolvedCUDAExecutionPolicy) = CUDABackend
backend_type(::PlaceholderPolicy) = error(
    "PlaceholderPolicy has no execution backend. Use CPUThreadsExecutionPolicy or CUDAExecutionPolicy to execute a task.")

_resolved_cpu_threads(policy::CPUThreadsExecutionPolicy) =
    policy.threads === :auto ? Threads.nthreads(:default) : policy.threads

function _cpu_worker_count()
    policy = _ACTIVE_RESOLVED_POLICY[]
    return policy isa ResolvedCPUExecutionPolicy ? policy.threads : Threads.nthreads(:default)
end

function _run_logical_workers(f::F, workers::Integer=_cpu_worker_count()) where {F}
    nworkers = Int(workers)
    nworkers > 0 || throw(ArgumentError("logical worker count must be positive"))
    _record_execution!(:cpu_logical_workers, CPUThreadsBackend,
                       (workers=nworkers, pool_threads=Threads.nthreads(:default)))
    if nworkers == 1
        f(1, 1)
        return nothing
    end
    @sync for worker in 1:nworkers
        Threads.@spawn f(worker, nworkers)
    end
    return nothing
end

function _active_cuda_launch(nitems::Integer)
    policy = _ACTIVE_RESOLVED_POLICY[]
    policy isa ResolvedCUDAExecutionPolicy || return (threads=256, blocks=256)
    blocks = policy.blocks isa Int ? policy.blocks : min(cld(Int(nitems), policy.threads), 256)
    return (threads=policy.threads, blocks=max(blocks, 1))
end

_legacy_cuda_policy(policy::GPUExecutionPolicy) = CUDAExecutionPolicy(
    device=policy.device,
    launch=CUDALaunchConfig(threads=policy.threads, blocks=policy.blocks),
)

"""Activate allocation-time side effects associated with an execution policy."""
activate_policy!(policy::AbstractExecutionPolicy) = policy
function activate_policy!(policy::Union{CUDAExecutionPolicy,GPUExecutionPolicy})
    device = policy.device
    device === nothing && return policy
    @isdefined(_HAS_CUDA) && _HAS_CUDA || error("CUDA policy requires CUDA.jl to be available.")
    CUDA.device!(device)
    return policy
end

const _CPU_POLICY_OPTION_SCHEMA = (
    threads=ConfigurationOptionMeta(Union{Int,Symbol}, :auto,
        "Number of Octopus logical workers in Julia's default thread pool.";
        supported_backends=(CPUThreadsBackend,), consumer=:cpu_logical_workers),
)

const _CUDA_POLICY_OPTION_SCHEMA = (
    device=ConfigurationOptionMeta(Union{Nothing,Int}, nothing,
        "CUDA device index; nothing resolves from particle storage.";
        supported_backends=(CUDABackend,), consumer=:cuda_device),
    threads=ConfigurationOptionMeta(Int, 256,
        "Threads per block for fused CUDA tracking.";
        supported_backends=(CUDABackend,), consumer=:cuda_fused_launch),
    blocks=ConfigurationOptionMeta(Union{Int,Symbol}, :auto,
        "Blocks for fused CUDA tracking; :auto uses occupancy and particle coverage.";
        supported_backends=(CUDABackend,), dependencies=(:threads,),
        consumer=:cuda_fused_launch),
)

const _LEGACY_GPU_POLICY_OPTION_SCHEMA = (
    device=ConfigurationOptionMeta(Union{Nothing,Int}, nothing,
        "Deprecated CUDA device selector.";
        supported_backends=(CUDABackend,), consumer=:cuda_device),
    threads=ConfigurationOptionMeta(Int, 256,
        "Deprecated fused CUDA thread-count compatibility option.";
        supported_backends=(CUDABackend,), consumer=:cuda_fused_launch),
    blocks=ConfigurationOptionMeta(Int, 256,
        "Deprecated fused CUDA block-count compatibility option.";
        supported_backends=(CUDABackend,), dependencies=(:threads,),
        consumer=:cuda_fused_launch),
)

policy_option_schema(::Type{CPUThreadsExecutionPolicy}) = _CPU_POLICY_OPTION_SCHEMA
policy_option_schema(::CPUThreadsExecutionPolicy) = _CPU_POLICY_OPTION_SCHEMA
policy_option_schema(::Type{CUDAExecutionPolicy}) = _CUDA_POLICY_OPTION_SCHEMA
policy_option_schema(::CUDAExecutionPolicy) = _CUDA_POLICY_OPTION_SCHEMA
policy_option_schema(::Type{GPUExecutionPolicy}) = _LEGACY_GPU_POLICY_OPTION_SCHEMA
policy_option_schema(::GPUExecutionPolicy) = _LEGACY_GPU_POLICY_OPTION_SCHEMA
policy_option_schema(::Type{PlaceholderPolicy}) = NamedTuple()
policy_option_schema(::PlaceholderPolicy) = NamedTuple()

"""
    configuration_report(object[, storage...])

Return structured `ConfigurationEntry` values for a policy, solver, slicing
configuration, task, schedule, observer, or diagnostics object. Each entry
separates the requested value from its resolved value and reports whether it is
resolved, inherited, inactive, library-managed, deprecated, or still awaiting
runtime information. Execution audits provide the separate evidence that a
resolved value reached its concrete consumer.
"""
function configuration_report(policy::CPUThreadsExecutionPolicy)
    resolved = _resolved_cpu_threads(policy)
    return (
        ConfigurationEntry(:threads, policy.threads, resolved, :resolved,
            policy.threads === :auto ? "inherited from Julia's default thread pool" :
                                       "explicit logical-worker count",
            :cpu_logical_workers),
    )
end

function configuration_report(policy::CUDAExecutionPolicy)
    return (
        ConfigurationEntry(:device, policy.device, policy.device, :unresolved,
            policy.device === nothing ? "resolved from CUDA particle storage at execution" :
                                        "validated against CUDA particle storage at execution",
            :cuda_device),
        ConfigurationEntry(:threads, policy.launch.threads, policy.launch.threads, :resolved,
            "explicit fused CUDA thread count", :cuda_fused_launch),
        ConfigurationEntry(:blocks, policy.launch.blocks, policy.launch.blocks,
            policy.launch.blocks === :auto ? :unresolved : :resolved,
            policy.launch.blocks === :auto ? "resolved from kernel occupancy and particle coverage" :
                                             "explicit fused CUDA block count",
            :cuda_fused_launch),
    )
end
function configuration_report(policy::GPUExecutionPolicy)
    return (
        ConfigurationEntry(:device, policy.device, policy.device, :deprecated,
            "applied through the CUDAExecutionPolicy compatibility adapter", :cuda_device),
        ConfigurationEntry(:threads, policy.threads, policy.threads, :deprecated,
            "applied through the CUDAExecutionPolicy compatibility adapter", :cuda_fused_launch),
        ConfigurationEntry(:blocks, policy.blocks, policy.blocks, :deprecated,
            "applied through the CUDAExecutionPolicy compatibility adapter", :cuda_fused_launch),
    )
end
configuration_report(::PlaceholderPolicy) = ()

description(::Type{PlaceholderPolicy}) = "Placeholder policy with no executable backend."
description(::Type{CPUThreadsExecutionPolicy}) = "Runs with a bounded number of CPU logical workers."
description(::Type{CUDAExecutionPolicy}) = "Runs CUDA kernels with backend-specific launch configuration."
description(::Type{GPUExecutionPolicy}) = "Deprecated CUDA execution-policy compatibility type."
