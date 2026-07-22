function track!(rep, elem::ThinStrongBeam, turns, ::Type{CPUThreadsBackend})
	Base.depwarn("backend-tag track! is deprecated; pass policy=CPUThreadsExecutionPolicy()", :track!)
	policy = ResolvedCPUExecutionPolicy(Threads.nthreads(:default))
	return _with_execution_policy(policy) do
		track!(rep, elem, turns, policy)
	end
end

function track!(rep, elem::ThinStrongBeam, turns, policy::ResolvedCPUExecutionPolicy)
	for _ in 1:turns
		local_lum = zeros(eltype(rep.x), policy.threads)
		_run_logical_workers(policy.threads) do worker, nworkers
			value = zero(eltype(rep.x))
			for index in worker:nworkers:length(rep)
				@inbounds begin
					x, px, y, py, z, pz, lum = _thin_strong_beam_track(elem, rep[index]...)
					rep[index] = (x, px, y, py, z, pz)
					value += lum
				end
			end
			local_lum[worker] = value
		end
		elem.last_luminosity = sum(local_lum)
	end
	return nothing
end

function track!(rep, elem::GaussianStrongBeam, turns, ::Type{CPUThreadsBackend})
	Base.depwarn("backend-tag track! is deprecated; pass policy=CPUThreadsExecutionPolicy()", :track!)
	policy = ResolvedCPUExecutionPolicy(Threads.nthreads(:default))
	return _with_execution_policy(policy) do
		track!(rep, elem, turns, policy)
	end
end

function track!(rep, elem::GaussianStrongBeam, turns, policy::ResolvedCPUExecutionPolicy)
	for _ in 1:turns
		local_lum = zeros(eltype(rep.x), policy.threads)
		_run_logical_workers(policy.threads) do worker, nworkers
			value = zero(eltype(rep.x))
			for index in worker:nworkers:length(rep)
				@inbounds begin
					x, px, y, py, z, pz, lum =
						_track_gaussian_strong_beam_with_luminosity(elem, rep[index]...)
					rep[index] = (x, px, y, py, z, pz)
					value += lum
				end
			end
			local_lum[worker] = value
		end
		elem.last_luminosity = sum(local_lum)
	end
	return nothing
end

@inline function _track_gaussian_strong_beam_with_luminosity(
		elem::GaussianStrongBeam, x, px, y, py, z, pz)
	lum = zero(x + px + y + py + z + pz)
	kbb0 = elem.thin.kbb
	x0, y0, z0 = elem.thin.xo, elem.thin.yo, elem.thin.zo
	for i in elem.ns:-1:1
		slice_pxo, slice_pyo = _slice_transverse_angles(elem, i)
		thin = _slice_thin_strong_beam(
			elem.thin,
			kbb0 * elem.slice_weight[i],
			x0 + elem.slice_hoffset[i],
			y0 + elem.slice_voffset[i],
			z0 + elem.slice_center[i],
			slice_pxo,
			slice_pyo,
		)
		x, px, y, py, z, pz, l = _thin_strong_beam_track(thin, x, px, y, py, z, pz)
		lum += l * elem.slice_weight[i]
	end
	return x, px, y, py, z, pz, lum
end

@inline _slice_transverse_angles(
		elem::GaussianStrongBeam{M,T,P,D,false}, i) where {M,T,P,D} =
	(elem.thin.pxo, elem.thin.pyo)

@inline _slice_transverse_angles(
		elem::GaussianStrongBeam{M,T,P,D,true}, i) where {M,T,P,D} =
	(elem.thin.pxo + elem.slice_pxoffset[i],
	 elem.thin.pyo + elem.slice_pyoffset[i])

@inline _has_slice_angles(::GaussianStrongBeam{M,T,P,D,A}) where {M,T,P,D,A} = A

if _HAS_CUDA
	@eval begin
		_requires_cuda_elementwise(elem::ThinStrongBeam) = true
		_requires_cuda_elementwise(elem::GaussianStrongBeam) = true

		function cuda_track_thin_strong_beam_kernel!(
			rep, lum, turns,
			moments, kbb, klum, xo, yo, zo, pxo, pyo, pzo,
			ppxo, ppyo, ppzo, virtual_drift,
		)
			start_index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
			stride = CUDA.gridDim().x * CUDA.blockDim().x
			index = start_index
			while index <= length(rep)
				@inbounds begin
					x, px, y, py, z, pz = rep[index]
					total_lum = zero(x)
					for turn in 1:turns
						x, px, y, py, z, pz, l = _cuda_thin_strong_beam_track(
							x, px, y, py, z, pz,
							moments, kbb, klum, xo, yo, zo, pxo, pyo, pzo,
							ppxo, ppyo, ppzo, virtual_drift,
						)
						total_lum += l
					end
					rep[index] = (x, px, y, py, z, pz)
					lum[index] = total_lum
				end
				index += stride
			end
			return nothing
		end

		function cuda_track_gaussian_strong_beam_kernel!(
			rep, lum, turns, ns, slice_center, slice_weight, slice_hoffset, slice_voffset,
			slice_pxoffset, slice_pyoffset, has_slice_angles,
			moments, kbb, klum, xo, yo, zo, pxo, pyo, pzo,
			ppxo, ppyo, ppzo, virtual_drift,
		)
			start_index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
			stride = CUDA.gridDim().x * CUDA.blockDim().x
			index = start_index
			while index <= length(rep)
				@inbounds begin
					x, px, y, py, z, pz = rep[index]
					total_lum = zero(x)
					for turn in 1:turns
						for i in ns:-1:1
							slice_pxo, slice_pyo = _cuda_slice_transverse_angles(
								has_slice_angles, pxo, pyo,
								slice_pxoffset, slice_pyoffset, i)
							x, px, y, py, z, pz, l = _cuda_thin_strong_beam_track(
								x, px, y, py, z, pz,
								moments,
								kbb * slice_weight[i], klum,
								xo + slice_hoffset[i], yo + slice_voffset[i], zo + slice_center[i],
								slice_pxo, slice_pyo, pzo,
								ppxo, ppyo, ppzo, virtual_drift,
							)
							total_lum += l * slice_weight[i]
						end
					end
					rep[index] = (x, px, y, py, z, pz)
					lum[index] = total_lum
				end
				index += stride
			end
			return nothing
		end

		@inline _cuda_slice_transverse_angles(
			::Val{false}, pxo, pyo, slice_pxoffset, slice_pyoffset, i) = (pxo, pyo)

		@inline _cuda_slice_transverse_angles(
			::Val{true}, pxo, pyo, slice_pxoffset, slice_pyoffset, i) =
			(pxo + slice_pxoffset[i], pyo + slice_pyoffset[i])
	end
end

function track!(rep, elem::ThinStrongBeam, turns, ::Type{CUDABackend}; threads=256, blocks=256, stream=nothing)
	_HAS_CUDA || error("CUDABackend requires CUDA.jl to be available.")
	N = length(rep)
	T = eltype(rep.x)
	lum = CUDA.zeros(T, N)
	if stream === nothing
		CUDA.@cuda threads=threads blocks=blocks cuda_track_thin_strong_beam_kernel!(
			rep, lum, Int(turns),
			elem.moments, elem.kbb, elem.klum,
			elem.xo, elem.yo, elem.zo, elem.pxo, elem.pyo, elem.pzo,
			elem.ppxo, elem.ppyo, elem.ppzo, elem.virtual_drift,
		)
	else
		CUDA.@cuda threads=threads blocks=blocks stream=stream cuda_track_thin_strong_beam_kernel!(
			rep, lum, Int(turns),
			elem.moments, elem.kbb, elem.klum,
			elem.xo, elem.yo, elem.zo, elem.pxo, elem.pyo, elem.pzo,
			elem.ppxo, elem.ppyo, elem.ppzo, elem.virtual_drift,
		)
		CUDA.synchronize(stream)
	end
	elem.last_luminosity = sum(Array(lum))
	return nothing
end

function track!(rep, elem::ThinStrongBeam, turns, policy::ResolvedCUDAExecutionPolicy;
				stream=nothing)
	blocks = policy.blocks isa Int ? policy.blocks : min(cld(length(rep), policy.threads), 256)
	blocks == 0 && return nothing
	_record_execution!(:cuda_weak_strong_launch, CUDABackend,
		(threads=policy.threads, blocks=blocks, requested_blocks=policy.blocks,
		 element=:thin, stream=stream === nothing ? :default : :explicit))
	return track!(rep, elem, turns, CUDABackend;
		threads=policy.threads, blocks=blocks, stream=stream)
end

function track!(rep, elem::GaussianStrongBeam, turns, ::Type{CUDABackend}; threads=256, blocks=256, stream=nothing)
	_HAS_CUDA || error("CUDABackend requires CUDA.jl to be available.")
	N = length(rep)
	T = eltype(rep.x)
	lum = CUDA.zeros(T, N)
	slice_center = CUDA.CuArray(T.(elem.slice_center))
	slice_weight = CUDA.CuArray(T.(elem.slice_weight))
	slice_hoffset = CUDA.CuArray(T.(elem.slice_hoffset))
	slice_voffset = CUDA.CuArray(T.(elem.slice_voffset))
	has_slice_angles = Val(_has_slice_angles(elem))
	slice_pxoffset = _has_slice_angles(elem) ? CUDA.CuArray(T.(elem.slice_pxoffset)) : nothing
	slice_pyoffset = _has_slice_angles(elem) ? CUDA.CuArray(T.(elem.slice_pyoffset)) : nothing
	t = elem.thin
	if stream === nothing
		CUDA.@cuda threads=threads blocks=blocks cuda_track_gaussian_strong_beam_kernel!(
			rep, lum, Int(turns), elem.ns, slice_center, slice_weight, slice_hoffset, slice_voffset,
			slice_pxoffset, slice_pyoffset, has_slice_angles,
			t.moments, t.kbb, t.klum,
			t.xo, t.yo, t.zo, t.pxo, t.pyo, t.pzo,
			t.ppxo, t.ppyo, t.ppzo, t.virtual_drift,
		)
	else
		CUDA.@cuda threads=threads blocks=blocks stream=stream cuda_track_gaussian_strong_beam_kernel!(
			rep, lum, Int(turns), elem.ns, slice_center, slice_weight, slice_hoffset, slice_voffset,
			slice_pxoffset, slice_pyoffset, has_slice_angles,
			t.moments, t.kbb, t.klum,
			t.xo, t.yo, t.zo, t.pxo, t.pyo, t.pzo,
			t.ppxo, t.ppyo, t.ppzo, t.virtual_drift,
		)
		CUDA.synchronize(stream)
	end
	elem.last_luminosity = sum(Array(lum))
	return nothing
end

function track!(rep, elem::GaussianStrongBeam, turns, policy::ResolvedCUDAExecutionPolicy;
				stream=nothing)
	blocks = policy.blocks isa Int ? policy.blocks : min(cld(length(rep), policy.threads), 256)
	blocks == 0 && return nothing
	_record_execution!(:cuda_weak_strong_launch, CUDABackend,
		(threads=policy.threads, blocks=blocks, requested_blocks=policy.blocks,
		 element=:gaussian, stream=stream === nothing ? :default : :explicit))
	return track!(rep, elem, turns, CUDABackend;
		threads=policy.threads, blocks=blocks, stream=stream)
end

@inline function _cuda_thin_strong_beam_track(
	x, px, y, py, z, pz,
	moments, kbb, klum, xo, yo, zo, pxo, pyo, pzo,
	ppxo, ppyo, ppzo, virtual_drift,
)
	(moments.a0 == 0 || moments.d0 == 0) && return x, px, y, py, z, pz, zero(x)
	x, px, y, py, z, pz, S = _forward_virtual_drift(
		virtual_drift, x, px, y, py, z, pz, zo)
	x, px, y, py, z, pz, lum = _cuda_cp_kick(
		x, px, y, py, z, pz, S,
		moments, kbb, xo, yo, pxo, pyo, ppxo, ppyo,
	)
	x, px, y, py, z, pz = _reverse_virtual_drift(
		virtual_drift, x, px, y, py, z, pz, zo)
	return x, px, y, py, z, pz, lum * klum
end

@inline function _cuda_cp_kick(
	x, px, y, py, z, pz, S,
	moments, kbb, xo, yo, pxo, pyo, ppxo, ppyo,
)
	xx = x - xo + pxo * S - 0.5 * ppxo * S * S
	yy = y - yo + pyo * S - 0.5 * ppyo * S * S
	px0, py0 = px, py
	x, px, y, py, z, pz, density = _cuda_cp_covariance_kick(
		moments, kbb, S, xx, yy, x, px, y, py, z, pz)
	pz += 0.5 * ((px - px0) * (pxo - ppxo * S) +
	             (py - py0) * (pyo - ppyo * S))
	return x, px, y, py, z, pz, density
end

@inline function _cuda_cp_covariance_kick(m::StrongTransverseMoments{T,false}, kbb,
	S, xx, yy, x, px, y, py, z, pz) where {T}
	a, _, d, au, _, du = _transport_transverse_moments(m, S)
	(a <= 0 || d <= 0) && return x, px, y, py, z, pz, zero(x)
	sigx, sigy = sqrt(a), sqrt(d)
	Kx, Ky = _cuda_gaussian_beambeam_kick(sigx, sigy, xx, yy)
	expterm = exp(-0.5 * (xx * xx / a + yy * yy / d))
	px += kbb * Kx
	py += kbb * Ky
	dsize = abs(sigx - sigy) / 2
	msize = (sigx + sigy) / 2
	if dsize / msize < ROUND_BEAM_THRESHOLD
		Hxx, _, Hyy = _round_gaussian_hessian(kbb, msize, xx, yy, expterm)
	else
		Hxx, Hyy = _elliptic_gaussian_hessian_diagonal(
			kbb, sigx, sigy, xx, yy, Kx, Ky, expterm)
	end
	pz += 0.25 * (Hxx * au + Hyy * du)
	return x, px, y, py, z, pz, expterm / (TWOPI * sigx * sigy)
end

@inline function _cuda_cp_covariance_kick(m::StrongTransverseMoments{T,true}, kbb,
	S, xx, yy, x, px, y, py, z, pz) where {T}
	a, b, d, au, bu, du = _transport_transverse_moments(m, S)
	detA = a * d - b * b
	(a <= 0 || d <= 0 || detA <= 0) && return x, px, y, py, z, pz, zero(x)
	D = sqrt((a - d) * (a - d) + 4 * b * b)
	if D <= ROUND_BEAM_THRESHOLD * (a + d)
		sigma = sqrt((a + d) / 2)
		Kx, Ky = _cuda_gaussian_beambeam_kick(sigma, sigma, xx, yy)
		expterm = exp(-0.5 * (xx * xx + yy * yy) / (sigma * sigma))
		Fx, Fy = kbb * Kx, kbb * Ky
		Hxx, Hxy, Hyy = _round_gaussian_hessian(kbb, sigma, xx, yy, expterm)
		px += Fx
		py += Fy
		pz += 0.25 * (Hxx * au + 2 * Hxy * bu + Hyy * du)
		return x, px, y, py, z, pz, expterm / (TWOPI * sigma * sigma)
	end
	theta = 0.5 * atan(2 * b, a - d)
	c, s = cos(theta), sin(theta)
	lambda1 = (a + d + D) / 2
	lambda2 = (a + d - D) / 2
	sig1, sig2 = sqrt(lambda1), sqrt(lambda2)
	xh = c * xx + s * yy
	yh = -s * xx + c * yy
	Kxh, Kyh = _cuda_gaussian_beambeam_kick(sig1, sig2, xh, yh)
	expterm = exp(-0.5 * (xh * xh / lambda1 + yh * yh / lambda2))
	Fxh, Fyh = kbb * Kxh, kbb * Kyh
	px += c * Fxh - s * Fyh
	py += s * Fxh + c * Fyh
	H11, H22 = _elliptic_gaussian_hessian_diagonal(
		kbb, sig1, sig2, xh, yh, Kxh, Kyh, expterm)
	Du = ((a - d) * (au - du) + 4 * b * bu) / D
	lambda1u = (au + du + Du) / 2
	lambda2u = (au + du - Du) / 2
	thetau = ((a - d) * bu - b * (au - du)) / (D * D)
	pz += 0.25 * (H11 * lambda1u + H22 * lambda2u)
	pz -= 0.5 * thetau * (Fxh * yh - Fyh * xh)
	return x, px, y, py, z, pz, expterm / (TWOPI * sig1 * sig2)
end

@inline function _cuda_gaussian_beambeam_kick(sigx, sigy, x, y)
	(sigx == 0 || sigy == 0) && return zero(x), zero(y)
	dsize = abs((sigx - sigy) / 2)
	msize = sigx - (sigx - sigy) / 2
	negx = x < 0
	negy = y < 0
	x = abs(x)
	y = abs(y)
	if dsize / msize < ROUND_BEAM_THRESHOLD
		rr = x * x + y * y
		if rr == 0
			return zero(x), zero(y)
		end
		temp = 2 * (1 - exp(-rr / (2 * msize * msize))) / rr
		Kx = temp * x
		Ky = temp * y
	else
		if sigx > sigy
			sig1, sig2, x1, x2 = sigx, sigy, x, y
		else
			sig1, sig2, x1, x2 = sigy, sigx, y, x
		end
		denominator = SQRT2 * sqrt(sig1 * sig1 - sig2 * sig2)
		z1r = x1 / denominator
		z1i = x2 / denominator
		z2r = sig2 / sig1 * x1 / denominator
		z2i = sig1 / sig2 * x2 / denominator
		w1r, w1i = faddeeva_w_upper_reim(z1r, z1i)
		w2r, w2i = faddeeva_w_upper_reim(z2r, z2i)
		A = 2 * SQRTPI / denominator
		B = exp(-x1 * x1 / (2 * sig1 * sig1) - x2 * x2 / (2 * sig2 * sig2))
		retr = A * (w1r - B * w2r)
		reti = A * (w1i - B * w2i)
		if sigx > sigy
			Ky = retr
			Kx = reti
		else
			Ky = reti
			Kx = retr
		end
	end
	return negx ? -Kx : Kx, negy ? -Ky : Ky
end
