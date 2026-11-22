# Included after `using .Octopus` with `MAXREGS::Int` defined in Main: caps the fused tracking
# kernel's registers (ptxas --maxrregcount) on both launch forms and in the occupancy query,
# so that `blocks=:auto` sees the capped kernel. A/B probe only; never part of Octopus.
Octopus.eval(quote
    function _cuda_launch_track_kernel!(rep, elems, turns; threads=256, blocks=256, stream=nothing)
        if stream === nothing
            CUDA.@cuda threads=threads blocks=blocks maxregs=$(Main.MAXREGS) cuda_track_kernel!(rep, elems, turns)
        else
            CUDA.@cuda threads=threads blocks=blocks stream=stream maxregs=$(Main.MAXREGS) cuda_track_kernel!(rep, elems, turns)
        end
        return nothing
    end
    function _cuda_launch_track_kernel!(rep, elems, turns, ctx::TrackingContext; threads=256, blocks=256, stream=nothing)
        if stream === nothing
            CUDA.@cuda threads=threads blocks=blocks maxregs=$(Main.MAXREGS) cuda_track_kernel!(rep, elems, turns, ctx)
        else
            CUDA.@cuda threads=threads blocks=blocks stream=stream maxregs=$(Main.MAXREGS) cuda_track_kernel!(rep, elems, turns, ctx)
        end
        return nothing
    end
    function _cuda_fused_occupancy_blocks(rep, elems, turns, ctx, threads::Int)
        length(rep) == 0 && return 0
        kernel = ctx === nothing ?
            CUDA.@cuda(launch=false, maxregs=$(Main.MAXREGS), cuda_track_kernel!(rep, elems, turns)) :
            CUDA.@cuda(launch=false, maxregs=$(Main.MAXREGS), cuda_track_kernel!(rep, elems, turns, ctx))
        device = CUDA.deviceid(CUDA.device(rep.x))
        key = (device, typeof(rep), typeof(elems), ctx === nothing, threads)
        active_per_sm = lock(_CUDA_FUSED_OCCUPANCY_LOCK) do
            get!(_CUDA_FUSED_OCCUPANCY_CACHE, key) do
                CUDA.active_blocks(kernel.fun, threads)
            end
        end
        sm_count = CUDA.attribute(CUDA.device(rep.x), CUDA.DEVICE_ATTRIBUTE_MULTIPROCESSOR_COUNT)
        return min(cld(length(rep), threads), active_per_sm * sm_count)
    end
end)
println("maxregs override active: ", Main.MAXREGS)
