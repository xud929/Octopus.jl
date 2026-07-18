#=
Profile CUDA strong-strong tracking with CUDA.jl/CUPTI.

Run from the Octopus project root:

    julia --project=. profiling/profile_strong_strong_cuda.jl

The script enables CUDA execution, PIC by default, and NVTX ranges around
strong-strong task phases and CUDA PIC sub-phases. It intentionally defaults to
a short run; override the usual example environment variables for larger cases.

Useful options:

    OCTOPUS_TURNS=3
    OCTOPUS_N_MACRO_ELE=2560000
    OCTOPUS_N_MACRO_PRO=1024000
    OCTOPUS_POISSON_SOLVER=PIC
    OCTOPUS_PIC_GREEN_CACHE=slice_pair
    OCTOPUS_CUDA_MEMORY_LOG_EVERY=1
    OCTOPUS_CUDA_PIC_TIMING=1
    OCTOPUS_CUDA_PIC_TIMING_DETAIL=0
    OCTOPUS_PROFILE_TRACE=0

For an Nsight Systems timeline, use for example:

    OCTOPUS_PROFILE_MODE=none nsys profile --trace=cuda,nvtx --stats=true julia --project=. profiling/profile_strong_strong_cuda.jl

`OCTOPUS_PROFILE_MODE` controls the profiler wrapper:

- `cuda`: use CUDA.jl's internal `CUDA.@profile` summary.
- `none`: run normally with NVTX ranges; use this under Nsight Systems.
=#

profile_mode = lowercase(get(ENV, "OCTOPUS_PROFILE_MODE", "cuda"))

ENV["OCTOPUS_USE_GPU"] = get(ENV, "OCTOPUS_USE_GPU", "1")
ENV["OCTOPUS_POISSON_SOLVER"] = get(ENV, "OCTOPUS_POISSON_SOLVER", "PIC")
ENV["OCTOPUS_PIC_GREEN_CACHE"] = get(ENV, "OCTOPUS_PIC_GREEN_CACHE", "slice_pair")
ENV["OCTOPUS_TURNS"] = get(ENV, "OCTOPUS_TURNS", "3")
ENV["OCTOPUS_N_MACRO"] = get(ENV, "OCTOPUS_N_MACRO", "20000")
ENV["OCTOPUS_CUDA_MEMORY_LOG_EVERY"] = get(ENV, "OCTOPUS_CUDA_MEMORY_LOG_EVERY", "1")
ENV["OCTOPUS_CUDA_PIC_TIMING"] = get(ENV, "OCTOPUS_CUDA_PIC_TIMING", "1")

# CUDA.jl's internal CUPTI profiler can fail while decoding NVTX marker color
# metadata on some CUPTI/NVTX combinations. Keep NVTX ranges for Nsight mode,
# but disable them by default for CUDA.@profile summaries.
default_nvtx = profile_mode == "none" ? "1" : "0"
ENV["OCTOPUS_CUDA_NVTX"] = get(ENV, "OCTOPUS_CUDA_NVTX", default_nvtx)

import CUDA

CUDA.functional(false) || error("CUDA is not functional in this Julia session.")

if profile_mode == "cuda"
    profile_trace = get(ENV, "OCTOPUS_PROFILE_TRACE", "0") in ("1", "true", "TRUE", "yes", "YES")
    if profile_trace
        CUDA.@profile trace=true begin
            include(joinpath(@__DIR__, "..", "examples", "strong_strong_tracking.jl"))
        end
    else
        CUDA.@profile begin
            include(joinpath(@__DIR__, "..", "examples", "strong_strong_tracking.jl"))
        end
    end
elseif profile_mode == "none"
    include(joinpath(@__DIR__, "..", "examples", "strong_strong_tracking.jl"))
else
    error("unknown OCTOPUS_PROFILE_MODE=$(profile_mode); use cuda or none")
end
