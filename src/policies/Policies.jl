export PlaceholderPolicy, CPUThreadsExecutionPolicy, GPUExecutionPolicy,
       backend_type, activate_policy!

"""
    PlaceholderPolicy()

Placeholder execution policy used for examples and metadata until a real
execution choice is required. It intentionally does not imply slicing,
accuracy, MPI, or backend behavior.
"""
struct PlaceholderPolicy <: AbstractExecutionPolicy end

"""
    CPUThreadsExecutionPolicy(; threads=Threads.nthreads())

Policy for the currently implemented CPU threaded execution backend.
"""
struct CPUThreadsExecutionPolicy <: AbstractExecutionPolicy
    threads::Int
end
CPUThreadsExecutionPolicy(; threads::Integer=Threads.nthreads()) =
    CPUThreadsExecutionPolicy(Int(threads))

"""
    GPUExecutionPolicy(; threads=256, blocks=256, device=nothing)

Policy for the currently implemented CUDA GPU execution backend.

`device` selects the CUDA device by index, matching CUDA.jl's `CUDA.device!`
convention. Use `GPUExecutionPolicy()` to keep the current CUDA device, or
`GPUExecutionPolicy(device=1)` to select GPU 1 before Octopus allocates or
tracks GPU arrays.
"""
struct GPUExecutionPolicy <: AbstractExecutionPolicy
    threads::Int
    blocks::Int
    device::Union{Nothing,Int}
end
GPUExecutionPolicy(threads::Integer, blocks::Integer) =
    GPUExecutionPolicy(Int(threads), Int(blocks), nothing)
GPUExecutionPolicy(; threads::Integer=256, blocks::Integer=256, device=nothing) =
    GPUExecutionPolicy(Int(threads), Int(blocks), device === nothing ? nothing : Int(device))

"""
    backend_type(policy)

Return the runtime backend tag associated with an executable policy.
"""
backend_type(::CPUThreadsExecutionPolicy) = CPUThreadsBackend
backend_type(::GPUExecutionPolicy) = CUDABackend
backend_type(::PlaceholderPolicy) =
    error("PlaceholderPolicy has no execution backend. Use CPUThreadsExecutionPolicy or GPUExecutionPolicy to execute a task.")

"""Activate side effects associated with an execution policy."""
activate_policy!(policy::AbstractExecutionPolicy) = policy
function activate_policy!(policy::GPUExecutionPolicy)
    policy.device === nothing && return policy
    _HAS_CUDA || error("GPUExecutionPolicy(device=...) requires CUDA.jl to be available.")
    CUDA.device!(policy.device)
    return policy
end

description(::Type{PlaceholderPolicy}) = "Placeholder policy with no executable backend."
description(::Type{CPUThreadsExecutionPolicy}) = "Runs on CPU threads."
description(::Type{GPUExecutionPolicy}) = "Runs on a CUDA-capable GPU."
