if _HAS_CUDA
	@eval begin
		_requires_cuda_elementwise(elem::LumpedRad) =
			elem.method isa Radiation6DMap || elem.method isa Diffusion6DMap
		_requires_cuda_elementwise(elem::LumpedRad, ctx::TrackingContext) = false

		# A thin wrapper over the SAME `_track_lumped_rad_context` functions
		# the fused kernel uses: `elem.method` is a static type parameter, so
		# the dispatch compiles away, and the counter draws are keyed by
		# (seed, method, turn, elem.rng_id, particle index, component) exactly
		# as everywhere else (2026-08-05_b audit, U14-7).
		function cuda_track_lumped_rad_kernel!(rep, elem, ctx)
			start_index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
			stride = CUDA.gridDim().x * CUDA.blockDim().x
			index = start_index
			while index<=length(rep)
				@inbounds rep[index] = _track_lumped_rad_context(
					elem.method, elem, ctx, index, rep[index]...)
				index += stride
			end
			return nothing
		end

		function track!(rep, elem::LumpedRad, turns, ::Type{CUDABackend}; threads=256, blocks=256, stream=nothing)
			# Counter-RNG route (2026-08-05_b audit, U14-7): this deprecated
			# single-element entry point was the only GPU radiation path
			# outside the counter-RNG guarantee — it drew with
			# `CUDA.default_rng()`, so its results depended on CUDA's global
			# RNG state, could not match the CPU, and were not thread- or
			# layout-invariant. It now draws through the global counter RNG
			# with 0-based turns (the fused route's convention), and the six
			# N-length device allocations per turn are gone with the
			# pre-drawn normal arrays they carried.
			base = TrackingContext()
			for turn in 1:turns
				ctx = with_turn(base, Int64(turn - 1))
				if stream === nothing
					CUDA.@cuda threads=threads blocks=blocks cuda_track_lumped_rad_kernel!(
						rep, elem, ctx,
					)
				else
					CUDA.@cuda threads=threads blocks=blocks stream=stream cuda_track_lumped_rad_kernel!(
						rep, elem, ctx,
					)
				end
			end
			return nothing
		end

		function track!(rep, elem::LumpedRad, turns, policy::ResolvedCUDAExecutionPolicy;
						stream=nothing)
			blocks = policy.blocks isa Int ? policy.blocks : min(cld(length(rep), policy.threads), 256)
			blocks == 0 && return nothing
			_record_execution!(:cuda_radiation_compatibility_launch, CUDABackend,
				(threads=policy.threads, blocks=blocks, requested_blocks=policy.blocks,
				 stream=stream === nothing ? :default : :explicit))
			return track!(rep, elem, turns, CUDABackend;
				threads=policy.threads, blocks=blocks, stream=stream)
		end
	end
end
