if _HAS_CUDA
	@eval begin
		_requires_cuda_elementwise(elem::LumpedRad) =
			elem.method isa Radiation6DMap || elem.method isa Diffusion6DMap
		_requires_cuda_elementwise(elem::LumpedRad, ctx::TrackingContext) = false

		function cuda_track_lumped_rad_kernel!(rep, elem, nx, npx, ny, npy, nz, npz)
			start_index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
			stride = CUDA.gridDim().x * CUDA.blockDim().x
			index = start_index
			while index<=length(rep)
				@inbounds begin
					if elem.method isa Diffusion6DMap
						rep[index] = _track_lumped_rad_particle(
							elem,
							rep[index]...,
							nx[index], npx[index], ny[index], npy[index], nz[index], npz[index],
							false, elem.is_excitation,
						)
					else
						rep[index] = _track_lumped_rad_particle(
							elem,
							rep[index]...,
							nx[index], npx[index], ny[index], npy[index], nz[index], npz[index],
						)
					end
				end
				index += stride
			end
			return nothing
		end

		function track!(rep, elem::LumpedRad, turns, ::Type{CUDABackend}; threads=256, blocks=256, stream=nothing)
			N = length(rep)
			T = eltype(rep.x)
			for turn in 1:turns
				nx = elem.is_excitation ? Random.randn(CUDA.default_rng(), T, N) : rep.x
				npx = elem.is_excitation ? Random.randn(CUDA.default_rng(), T, N) : rep.px
				ny = elem.is_excitation ? Random.randn(CUDA.default_rng(), T, N) : rep.y
				npy = elem.is_excitation ? Random.randn(CUDA.default_rng(), T, N) : rep.py
				nz = elem.is_excitation ? Random.randn(CUDA.default_rng(), T, N) : rep.z
				npz = elem.is_excitation ? Random.randn(CUDA.default_rng(), T, N) : rep.pz
				if stream === nothing
					CUDA.@cuda threads=threads blocks=blocks cuda_track_lumped_rad_kernel!(
						rep, elem, nx, npx, ny, npy, nz, npz,
					)
				else
					CUDA.@cuda threads=threads blocks=blocks stream=stream cuda_track_lumped_rad_kernel!(
						rep, elem, nx, npx, ny, npy, nz, npz,
					)
				end
			end
			return nothing
		end
	end
end
