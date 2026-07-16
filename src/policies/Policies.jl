export PlaceholderPolicy, CPUThreadsExecutionPolicy, GPUExecutionPolicy,
       backend_type

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
    GPUExecutionPolicy(; threads=256, blocks=256)

Policy for the currently implemented CUDA GPU execution backend. The CUDA
dependency is required only when GPU runtime tracking is invoked.
"""
struct GPUExecutionPolicy <: AbstractExecutionPolicy
    threads::Int
    blocks::Int
end
GPUExecutionPolicy(; threads::Integer=256, blocks::Integer=256) =
    GPUExecutionPolicy(Int(threads), Int(blocks))

"""
    backend_type(policy)

Return the runtime backend tag associated with an executable policy.
"""
backend_type(::CPUThreadsExecutionPolicy) = CPUThreadsBackend
backend_type(::GPUExecutionPolicy) = CUDABackend
backend_type(::PlaceholderPolicy) =
    error("PlaceholderPolicy has no execution backend. Use CPUThreadsExecutionPolicy or GPUExecutionPolicy to execute a task.")

description(::Type{PlaceholderPolicy}) = "Placeholder policy with no executable backend."
description(::Type{CPUThreadsExecutionPolicy}) = "Runs on CPU threads."
description(::Type{GPUExecutionPolicy}) = "Runs on CUDA-capable GPUs."
