"""
    track!(rep, elems, turns; policy=nothing, context=TrackingContext())

Track all particles in `rep` through callable runtime `elems` for `turns`
turns. With `policy=nothing`, the execution policy is inferred from particle
storage. A supplied policy selects execution for existing storage and never
migrates it. `context` supplies turn and counter-RNG state independently of the
execution policy.
"""
function track!(rep, elems, turns; policy::Union{Nothing,AbstractExecutionPolicy}=nothing,
                context::TrackingContext=TrackingContext())
	resolved = _resolve_execution_policy(policy, rep)
	_with_execution_policy(resolved) do
		track!(rep, elems, turns, resolved, context)
	end
	return nothing
end

function track!(rep, elems, turns, policy::AbstractExecutionPolicy;
                context::TrackingContext=TrackingContext())
	Base.depwarn("pass execution policy with policy= instead of as a positional argument", :track!)
	return track!(rep, elems, turns; policy=policy, context=context)
end

function track!(rep, elems, turns, policy::ResolvedCPUExecutionPolicy,
				ctx::TrackingContext)
	for turn in 1:turns
		turn_ctx = with_turn(ctx, ctx.turn + Int64(turn - 1))
		_run_logical_workers(policy.threads) do worker, nworkers
			for index in worker:nworkers:length(rep)
				@inbounds rep[index] = fusedTrack(turn_ctx, elems, index, rep[index]...)
			end
		end
	end
	return nothing
end

function track!(rep, elems, turns, policy::ResolvedCPUExecutionPolicy)
	for turn in 1:turns
		_run_logical_workers(policy.threads) do worker, nworkers
			for index in worker:nworkers:length(rep)
				@inbounds rep[index] = fusedTrack(elems, rep[index]...)
			end
		end
	end
	return nothing
end

function track!(rep, elems, turns, ::Type{CPUThreadsBackend})
	Base.depwarn("backend-tag track! is deprecated; pass policy=CPUThreadsExecutionPolicy()", :track!)
	policy = ResolvedCPUExecutionPolicy(Threads.nthreads(:default))
	return _with_execution_policy(policy) do
		track!(rep, elems, turns, policy)
	end
end

function track!(rep, elems, turns, ::Type{CPUThreadsBackend}, ctx::TrackingContext)
	Base.depwarn("backend-tag track! is deprecated; pass policy= and context=", :track!)
	policy = ResolvedCPUExecutionPolicy(Threads.nthreads(:default))
	return _with_execution_policy(policy) do
		track!(rep, elems, turns, policy, ctx)
	end
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
		const _CUDA_FUSED_OCCUPANCY_CACHE = Dict{Any,Int}()
		const _CUDA_FUSED_OCCUPANCY_LOCK = ReentrantLock()

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
		    _cuda_launch_track_kernel!(rep, elems, turns; threads, blocks, stream=nothing)

		Private CUDA fused-kernel launcher. Public callers select geometry with a
		`CUDAExecutionPolicy`.
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

		function _cuda_fused_occupancy_blocks(rep, elems, turns, ctx, threads::Int)
			length(rep) == 0 && return 0
			kernel = ctx === nothing ?
				CUDA.@cuda(launch=false, cuda_track_kernel!(rep, elems, turns)) :
				CUDA.@cuda(launch=false, cuda_track_kernel!(rep, elems, turns, ctx))
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

		function _cuda_resolve_fused_blocks(policy::ResolvedCUDAExecutionPolicy,
										 rep, elems, turns, ctx)
			policy.blocks isa Int && return policy.blocks
			return _cuda_fused_occupancy_blocks(rep, elems, turns, ctx, policy.threads)
		end

		function _cuda_launch_track_policy!(rep, elems, turns,
									 policy::ResolvedCUDAExecutionPolicy,
									 ctx; stream=nothing)
			length(rep) == 0 && return nothing
			blocks = _cuda_resolve_fused_blocks(policy, rep, elems, turns, ctx)
			_record_execution!(:cuda_fused_launch, CUDABackend,
				(threads=policy.threads, blocks=blocks, requested_blocks=policy.blocks,
				 particles=length(rep), stream=stream === nothing ? :default : :explicit))
			if ctx === nothing
				_cuda_launch_track_kernel!(rep, elems, turns;
					threads=policy.threads, blocks=blocks, stream=stream)
			else
				_cuda_launch_track_kernel!(rep, elems, turns, ctx;
					threads=policy.threads, blocks=blocks, stream=stream)
			end
			return nothing
		end

		function _flush_cuda_policy_segment!(rep, fused, policy, ctx, stream)
			isempty(fused) && return nothing
			track!(rep, Tuple(fused), 1, policy, ctx; stream=stream)
			empty!(fused)
			return nothing
		end

		function _track_cuda_policy_elementwise!(rep, elems::Tuple, policy, ctx, stream)
			fused = Any[]
			for elem in elems
				if elem isa Tuple
					_flush_cuda_policy_segment!(rep, fused, policy, ctx, stream)
					_track_cuda_policy_elementwise!(rep, elem, policy, ctx, stream)
				elseif _requires_cuda_elementwise(elem, ctx)
					_flush_cuda_policy_segment!(rep, fused, policy, ctx, stream)
					track!(rep, elem, 1, policy; stream=stream)
				else
					push!(fused, elem)
				end
			end
			_flush_cuda_policy_segment!(rep, fused, policy, ctx, stream)
			return nothing
		end

		function track!(rep, elems, turns, policy::ResolvedCUDAExecutionPolicy;
						stream=nothing)
			if _requires_cuda_elementwise(elems)
				for _ in 1:turns
					_track_cuda_policy_elementwise!(rep, elems, policy, TrackingContext(), stream)
				end
			else
				_cuda_launch_track_policy!(rep, elems, turns, policy, nothing; stream=stream)
			end
			return nothing
		end

		function track!(rep, elems, turns, policy::ResolvedCUDAExecutionPolicy,
						ctx::TrackingContext; stream=nothing)
			if _requires_cuda_elementwise(elems, ctx)
				for turn in 1:turns
					turn_ctx = with_turn(ctx, ctx.turn + Int64(turn - 1))
					_track_cuda_policy_elementwise!(rep, elems, policy, turn_ctx, stream)
				end
			else
				_cuda_launch_track_policy!(rep, elems, turns, policy, ctx; stream=stream)
			end
			return nothing
		end

		function track!(rep, elems, turns, ::Type{CUDABackend}; threads=256, blocks=256, stream=nothing)
			Base.depwarn("backend-tag/CUDA-keyword track! is deprecated; pass policy=CUDAExecutionPolicy(...) instead", :track!)
			policy = ResolvedCUDAExecutionPolicy(
				CUDA.deviceid(CUDA.device(rep.x)), Int(threads), Int(blocks))
			return _with_execution_policy(policy) do
				track!(rep, elems, turns, policy; stream=stream)
			end
		end

		function track!(rep, elems, turns, ::Type{CUDABackend}, ctx::TrackingContext; threads=256, blocks=256, stream=nothing)
			Base.depwarn("backend-tag/CUDA-keyword track! is deprecated; pass policy= and context=", :track!)
			policy = ResolvedCUDAExecutionPolicy(
				CUDA.deviceid(CUDA.device(rep.x)), Int(threads), Int(blocks))
			return _with_execution_policy(policy) do
				track!(rep, elems, turns, policy, ctx; stream=stream)
			end
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
