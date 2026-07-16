"""
    track!(rep, elems, turns, CPUThreadsBackend)

Track all particles in `rep` through `elems` for `turns` turns using CPU
threads. `elems` must be callable runtime elements or a nested tuple of
callable runtime elements.
"""
function track!(rep, elems, turns, ::Type{CPUThreadsBackend})
	for turn in 1:turns
		Threads.@threads for index in keys(rep)
			@inbounds rep[index] = fusedTrack(elems, rep[index]...)
		end
	end
	return nothing
end

function track!(rep, elems, turns, ::Type{CPUThreadsBackend}, ctx::TrackingContext)
	for turn in 1:turns
		turn_ctx = with_turn(ctx, ctx.turn + Int64(turn - 1))
		Threads.@threads for index in keys(rep)
			@inbounds rep[index] = fusedTrack(turn_ctx, elems, index, rep[index]...)
		end
	end
	return nothing
end

_requires_cuda_elementwise(elem) = false
_requires_cuda_elementwise(elems::Tuple) = any(_requires_cuda_elementwise, elems)
_requires_cuda_elementwise(elem, ctx::TrackingContext) = _requires_cuda_elementwise(elem)
_requires_cuda_elementwise(elems::Tuple, ctx::TrackingContext) =
	any(elem -> _requires_cuda_elementwise(elem, ctx), elems)

function _track_line_elementwise!(rep, elems::Tuple, backend)
	fused = Any[]
	_track_line_elementwise!(rep, elems, backend, fused)
	_flush_cuda_fused_segment!(rep, fused, backend)
	return nothing
end

function _track_line_elementwise!(rep, elems::Tuple, backend, ctx::TrackingContext)
	fused = Any[]
	_track_line_elementwise!(rep, elems, backend, fused, ctx)
	_flush_cuda_fused_segment!(rep, fused, backend, ctx)
	return nothing
end

function _track_line_elementwise!(rep, elems::Tuple, backend, fused)
	for elem in elems
		_track_line_elementwise!(rep, elem, backend, fused)
	end
	return nothing
end

function _track_line_elementwise!(rep, elem, backend, fused)
	if _requires_cuda_elementwise(elem)
		_flush_cuda_fused_segment!(rep, fused, backend)
		track!(rep, elem, 1, backend)
	else
		push!(fused, elem)
	end
	return nothing
end

function _track_line_elementwise!(rep, elems::Tuple, backend, fused, ctx::TrackingContext)
	for elem in elems
		_track_line_elementwise!(rep, elem, backend, fused, ctx)
	end
	return nothing
end

function _track_line_elementwise!(rep, elem, backend, fused, ctx::TrackingContext)
	if _requires_cuda_elementwise(elem, ctx)
		_flush_cuda_fused_segment!(rep, fused, backend, ctx)
		track!(rep, elem, 1, backend)
	else
		push!(fused, elem)
	end
	return nothing
end

function _flush_cuda_fused_segment!(rep, fused, backend)
	isempty(fused) && return nothing
	track!(rep, Tuple(fused), 1, backend)
	empty!(fused)
	return nothing
end

function _flush_cuda_fused_segment!(rep, fused, backend, ctx::TrackingContext)
	isempty(fused) && return nothing
	track!(rep, Tuple(fused), 1, backend, ctx)
	empty!(fused)
	return nothing
end

function _track_line_elementwise!(rep, elem, backend)
	track!(rep, elem, 1, backend)
	return nothing
end

function _track_line_elementwise!(rep, elem, backend, ctx::TrackingContext)
	if _requires_cuda_elementwise(elem, ctx)
		track!(rep, elem, 1, backend)
	else
		track!(rep, elem, 1, backend, ctx)
	end
	return nothing
end

if _HAS_CUDA
	@eval begin
		function CUDA.cudaconvert(rep::Phase6DRep)
			return Phase6DRep(
				CUDA.cudaconvert(rep.x),
				CUDA.cudaconvert(rep.px),
				CUDA.cudaconvert(rep.y),
				CUDA.cudaconvert(rep.py),
				CUDA.cudaconvert(rep.z),
				CUDA.cudaconvert(rep.pz),
			)
		end

		"""
		    cuda_track_kernel!(rep, elems, turns)

		CUDA kernel for particle tracking. This method is defined only when
		`CUDA.jl` is available.
		"""
		function cuda_track_kernel!(rep, elems, turns)
			start_index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
			stride = CUDA.gridDim().x * CUDA.blockDim().x
			for turn in 1:turns
				index = start_index
				while index<=length(rep)
					@inbounds rep[index] = fusedTrack(elems, rep[index]...)
					index += stride
				end
			end
			return nothing
		end

		function cuda_track_kernel!(rep, elems, turns, ctx::TrackingContext)
			start_index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
			stride = CUDA.gridDim().x * CUDA.blockDim().x
			for turn in 1:turns
				turn_ctx = with_turn(ctx, ctx.turn + Int64(turn - 1))
				index = start_index
				while index<=length(rep)
					@inbounds rep[index] = fusedTrack(turn_ctx, elems, index, rep[index]...)
					index += stride
				end
			end
			return nothing
		end

		"""
		    track!(rep, elems, turns, CUDABackend; threads=256, blocks=256)

		Track all particles with a CUDA kernel. Requires `CUDA.jl`.
		"""
		function _cuda_launch_track_kernel!(rep, elems, turns; threads=256, blocks=256, stream=nothing)
			if stream === nothing
				CUDA.@cuda threads=threads blocks=blocks cuda_track_kernel!(rep, elems, turns)
			else
				CUDA.@cuda threads=threads blocks=blocks stream=stream cuda_track_kernel!(rep, elems, turns)
			end
			return nothing
		end

		function _cuda_launch_track_kernel!(rep, elems, turns, ctx::TrackingContext; threads=256, blocks=256, stream=nothing)
			if stream === nothing
				CUDA.@cuda threads=threads blocks=blocks cuda_track_kernel!(rep, elems, turns, ctx)
			else
				CUDA.@cuda threads=threads blocks=blocks stream=stream cuda_track_kernel!(rep, elems, turns, ctx)
			end
			return nothing
		end

		function track!(rep, elems, turns, ::Type{CUDABackend}; threads=256, blocks=256, stream=nothing)
			if _requires_cuda_elementwise(elems)
				for turn in 1:turns
					_track_line_elementwise!(rep, elems, CUDABackend)
				end
			else
				_cuda_launch_track_kernel!(rep, elems, turns; threads=threads, blocks=blocks, stream=stream)
			end
			return nothing
		end

		function track!(rep, elems, turns, ::Type{CUDABackend}, ctx::TrackingContext; threads=256, blocks=256, stream=nothing)
			if _requires_cuda_elementwise(elems, ctx)
				for turn in 1:turns
					turn_ctx = with_turn(ctx, ctx.turn + Int64(turn - 1))
					_track_line_elementwise!(rep, elems, CUDABackend, turn_ctx)
				end
			else
				_cuda_launch_track_kernel!(rep, elems, turns, ctx; threads=threads, blocks=blocks, stream=stream)
			end
			return nothing
		end
	end
else
	function cuda_track_kernel!(args...)
		error("CUDA tracking requires CUDA.jl to be available.")
	end

	function track!(rep, elems, turns, ::Type{CUDABackend}; threads=256, blocks=256, stream=nothing)
		error("CUDABackend requires CUDA.jl to be available.")
	end

	function track!(rep, elems, turns, ::Type{CUDABackend}, ctx::TrackingContext; threads=256, blocks=256, stream=nothing)
		error("CUDABackend requires CUDA.jl to be available.")
	end
end
