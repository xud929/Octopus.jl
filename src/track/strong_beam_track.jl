function track!(rep, elem::ThinStrongBeam, turns, ::Type{CPUThreadsBackend})
	for turn in 1:turns
		local_lum = zeros(eltype(rep.x), Threads.maxthreadid())
		Threads.@threads for index in keys(rep)
			@inbounds begin
				x, px, y, py, z, pz, lum =
					_thin_strong_beam_track(elem, rep[index]...)
				rep[index] = (x, px, y, py, z, pz)
				local_lum[Threads.threadid()] += lum
			end
		end
		elem.last_luminosity = sum(local_lum)
	end
	return nothing
end

function track!(rep, elem::GaussianStrongBeam, turns, ::Type{CPUThreadsBackend})
	for turn in 1:turns
		local_lum = zeros(eltype(rep.x), Threads.maxthreadid())
		Threads.@threads for index in keys(rep)
			@inbounds begin
				x, px, y, py, z, pz, lum =
					_track_gaussian_strong_beam_with_luminosity(elem, rep[index]...)
				rep[index] = (x, px, y, py, z, pz)
				local_lum[Threads.threadid()] += lum
			end
		end
		elem.last_luminosity = sum(local_lum)
	end
	return nothing
end

function _track_gaussian_strong_beam_with_luminosity(elem::GaussianStrongBeam,
                                                     x, px, y, py, z, pz)
	lum = zero(x + px + y + py + z + pz)
	kbb0 = elem.thin.kbb
	x0, y0, z0 = elem.thin.xo, elem.thin.yo, elem.thin.zo
	for i in elem.ns:-1:1
		thin = _slice_thin_strong_beam(
			elem.thin,
			kbb0 * elem.slice_weight[i],
			x0 + elem.slice_hoffset[i],
			y0 + elem.slice_voffset[i],
			elem.slice_center[i],
		)
		x, px, y, py, z, pz, l = _thin_strong_beam_track(thin, x, px, y, py, z, pz)
		lum += l * elem.slice_weight[i]
	end
	return x, px, y, py, z, pz, lum
end

if _HAS_CUDA
	@eval begin
		_requires_cuda_elementwise(elem::ThinStrongBeam) = true
		_requires_cuda_elementwise(elem::GaussianStrongBeam) = true

		function cuda_track_thin_strong_beam_kernel!(
			rep, lum, turns,
			sigx0, sigy0, betx0, bety0, alfx0, alfy0, gamx0, gamy0,
			emitx, emity, kbb, klum, xo, yo, zo, pxo, pyo, pzo,
			ppxo, ppyo, ppzo, dynamic_drift_flag,
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
							sigx0, sigy0, betx0, bety0, alfx0, alfy0, gamx0, gamy0,
							emitx, emity, kbb, klum, xo, yo, zo, pxo, pyo, pzo,
							ppxo, ppyo, ppzo, dynamic_drift_flag,
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
			sigx0, sigy0, betx0, bety0, alfx0, alfy0, gamx0, gamy0,
			emitx, emity, kbb, klum, xo, yo, zo, pxo, pyo, pzo,
			ppxo, ppyo, ppzo, dynamic_drift_flag,
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
							x, px, y, py, z, pz, l = _cuda_thin_strong_beam_track(
								x, px, y, py, z, pz,
								sigx0, sigy0, betx0, bety0, alfx0, alfy0, gamx0, gamy0,
								emitx, emity,
								kbb * slice_weight[i], klum,
								xo + slice_hoffset[i], yo + slice_voffset[i], slice_center[i],
								pxo, pyo, pzo, ppxo, ppyo, ppzo, dynamic_drift_flag,
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
	end
end

function track!(rep, elem::ThinStrongBeam, turns, ::Type{CUDABackend}; threads=256, blocks=256, stream=nothing)
	_HAS_CUDA || error("CUDABackend requires CUDA.jl to be available.")
	elem.size_signal === nothing || error("CUDA ThinStrongBeam tracking requires pre-updated numeric fields; size_signal is not supported inside the kernel.")
	elem.centroid_signal === nothing || error("CUDA ThinStrongBeam tracking requires pre-updated numeric fields; centroid_signal is not supported inside the kernel.")
	elem.angle_signal === nothing || error("CUDA ThinStrongBeam tracking requires pre-updated numeric fields; angle_signal is not supported inside the kernel.")
	N = length(rep)
	T = eltype(rep.x)
	lum = CUDA.zeros(T, N)
	if stream === nothing
		CUDA.@cuda threads=threads blocks=blocks cuda_track_thin_strong_beam_kernel!(
			rep, lum, Int(turns),
			elem.sigx0, elem.sigy0, elem.betx0, elem.bety0, elem.alfx0, elem.alfy0,
			elem.gamx0, elem.gamy0, elem.emitx, elem.emity, elem.kbb, elem.klum,
			elem.xo, elem.yo, elem.zo, elem.pxo, elem.pyo, elem.pzo,
			elem.ppxo, elem.ppyo, elem.ppzo, elem.dynamic_drift_flag,
		)
	else
		CUDA.@cuda threads=threads blocks=blocks stream=stream cuda_track_thin_strong_beam_kernel!(
			rep, lum, Int(turns),
			elem.sigx0, elem.sigy0, elem.betx0, elem.bety0, elem.alfx0, elem.alfy0,
			elem.gamx0, elem.gamy0, elem.emitx, elem.emity, elem.kbb, elem.klum,
			elem.xo, elem.yo, elem.zo, elem.pxo, elem.pyo, elem.pzo,
			elem.ppxo, elem.ppyo, elem.ppzo, elem.dynamic_drift_flag,
		)
		CUDA.synchronize(stream)
	end
	elem.last_luminosity = sum(Array(lum))
	return nothing
end

function track!(rep, elem::GaussianStrongBeam, turns, ::Type{CUDABackend}; threads=256, blocks=256, stream=nothing)
	_HAS_CUDA || error("CUDABackend requires CUDA.jl to be available.")
	elem.thin.size_signal === nothing || error("CUDA GaussianStrongBeam tracking requires pre-updated numeric fields; size_signal is not supported inside the kernel.")
	elem.thin.centroid_signal === nothing || error("CUDA GaussianStrongBeam tracking requires pre-updated numeric fields; centroid_signal is not supported inside the kernel.")
	elem.thin.angle_signal === nothing || error("CUDA GaussianStrongBeam tracking requires pre-updated numeric fields; angle_signal is not supported inside the kernel.")
	N = length(rep)
	T = eltype(rep.x)
	lum = CUDA.zeros(T, N)
	slice_center = CUDA.CuArray(T.(elem.slice_center))
	slice_weight = CUDA.CuArray(T.(elem.slice_weight))
	slice_hoffset = CUDA.CuArray(T.(elem.slice_hoffset))
	slice_voffset = CUDA.CuArray(T.(elem.slice_voffset))
	t = elem.thin
	if stream === nothing
		CUDA.@cuda threads=threads blocks=blocks cuda_track_gaussian_strong_beam_kernel!(
			rep, lum, Int(turns), elem.ns, slice_center, slice_weight, slice_hoffset, slice_voffset,
			t.sigx0, t.sigy0, t.betx0, t.bety0, t.alfx0, t.alfy0,
			t.gamx0, t.gamy0, t.emitx, t.emity, t.kbb, t.klum,
			t.xo, t.yo, t.zo, t.pxo, t.pyo, t.pzo,
			t.ppxo, t.ppyo, t.ppzo, t.dynamic_drift_flag,
		)
	else
		CUDA.@cuda threads=threads blocks=blocks stream=stream cuda_track_gaussian_strong_beam_kernel!(
			rep, lum, Int(turns), elem.ns, slice_center, slice_weight, slice_hoffset, slice_voffset,
			t.sigx0, t.sigy0, t.betx0, t.bety0, t.alfx0, t.alfy0,
			t.gamx0, t.gamy0, t.emitx, t.emity, t.kbb, t.klum,
			t.xo, t.yo, t.zo, t.pxo, t.pyo, t.pzo,
			t.ppxo, t.ppyo, t.ppzo, t.dynamic_drift_flag,
		)
		CUDA.synchronize(stream)
	end
	elem.last_luminosity = sum(Array(lum))
	return nothing
end

@inline function _cuda_thin_strong_beam_track(
	x, px, y, py, z, pz,
	sigx0, sigy0, betx0, bety0, alfx0, alfy0, gamx0, gamy0,
	emitx, emity, kbb, klum, xo, yo, zo, pxo, pyo, pzo,
	ppxo, ppyo, ppzo, dynamic_drift_flag,
)
	(sigx0 == 0 || sigy0 == 0) && return x, px, y, py, z, pz, zero(x)
	x, px, y, py, z, pz, S = _cuda_dynamic_drift(x, px, y, py, z, pz, zo, dynamic_drift_flag)
	x, px, y, py, z, pz, lum = _cuda_cp_kick(
		x, px, y, py, z, pz, S,
		betx0, bety0, alfx0, alfy0, gamx0, gamy0, emitx, emity,
		kbb, xo, yo, pxo, pyo, ppxo, ppyo,
	)
	x, px, y, py, z, pz = _cuda_reverse_dynamic_drift(x, px, y, py, z, pz, zo, dynamic_drift_flag)
	return x, px, y, py, z, pz, lum * klum
end

@inline function _cuda_dynamic_drift(x, px, y, py, z, pz, zo, flag)
	S = 0.5 * (z - zo)
	if flag == -2
		PHI = sqrt(1 - 0.5 * (px * px + py * py) / ((1 + pz) * (1 + pz))) - 1
		x += S * px / (1 + pz)
		y += S * py / (1 + pz)
		z += 2 * S * PHI
	elseif flag == -1
		x += S * px
		y += S * py
	elseif flag == 0
		x += S * px
		y += S * py
		pz -= 0.25 * (px * px + py * py)
	elseif flag == 1
		PHI = sqrt(1 - 0.5 * (px * px + py * py) / ((1 + pz) * (1 + pz))) - 1
		x += S * px / (1 + pz)
		y += S * py / (1 + pz)
		z += 2 * S * PHI
		pz += (1 + pz) * PHI
	else
		ps = sqrt((1 + pz) * (1 + pz) - px * px - py * py)
		H = 1 + pz - ps
		rr = 0.5 * H / ps
		z2 = (z + rr * zo) / (1 + rr)
		S = 0.5 * (z2 - zo)
		z -= H / ps * S
		pz -= 0.5 * H
		x += px / ps * S
		y += py / ps * S
	end
	return x, px, y, py, z, pz, S
end

@inline function _cuda_reverse_dynamic_drift(x, px, y, py, z, pz, zo, flag)
	S = 0.5 * (z - zo)
	if flag == -2
		PSI = sqrt(1 + 0.5 * (px * px + py * py) / ((1 + pz) * (1 + pz))) - 1
		x -= S * px / (1 + pz)
		y -= S * py / (1 + pz)
		z += 2 * S * PSI
	elseif flag == -1
		x -= S * px
		y -= S * py
	elseif flag == 0
		x -= S * px
		y -= S * py
		pz += 0.25 * (px * px + py * py)
	elseif flag == 1
		PSI = sqrt(1 + 0.5 * (px * px + py * py) / ((1 + pz) * (1 + pz))) - 1
		x -= S * px / (1 + pz)
		y -= S * py / (1 + pz)
		z += 2 * S * PSI
		pz += (1 + pz) * PSI
	else
		H0 = 0.5 * (px * px + py * py) / (1 + pz)
		ps0 = 1 + pz - 0.5 * H0
		pz += 0.5 * H0
		x -= px / ps0 * S
		y -= py / ps0 * S
		z += H0 / ps0 * S
	end
	return x, px, y, py, z, pz
end

@inline function _cuda_cp_kick(
	x, px, y, py, z, pz, S,
	betx0, bety0, alfx0, alfy0, gamx0, gamy0, emitx, emity,
	kbb, xo, yo, pxo, pyo, ppxo, ppyo,
)
	betx = betx0 + 2 * S * alfx0 + S * S * gamx0
	bety = bety0 + 2 * S * alfy0 + S * S * gamy0
	sigx = sqrt(emitx * betx)
	sigy = sqrt(emity * bety)
	xx = x - xo + pxo * S - 0.5 * ppxo * S * S
	yy = y - yo + pyo * S - 0.5 * ppyo * S * S
	Kx, Ky = _cuda_gaussian_beambeam_kick(sigx, sigy, xx, yy)
	expterm = exp(-0.5 * (xx * xx / (sigx * sigx) + yy * yy / (sigy * sigy)))
	px += Kx * kbb
	py += Ky * kbb
	dsize = abs((sigx - sigy) / 2)
	msize = sigx - (sigx - sigy) / 2
	if dsize / msize < ROUND_BEAM_THRESHOLD
		Uxx = -kbb * expterm / msize / sigx
		Uyy = -kbb * expterm / msize / sigy
	else
		temp1 = kbb * (xx * Kx + yy * Ky)
		temp2 = sigx * sigx - sigy * sigy
		temp3 = sigy / sigx
		Uxx = (temp1 - 2 * kbb * (1 - expterm * temp3)) / temp2
		Uyy = (-temp1 + 2 * kbb * (1 - expterm / temp3)) / temp2
	end
	dsigx2 = 0.5 * emitx * (alfx0 + S * gamx0)
	dsigy2 = 0.5 * emity * (alfy0 + S * gamy0)
	pz -= Uxx * dsigx2 + Uyy * dsigy2
	return x, px, y, py, z, pz, expterm / TWOPI / sigx / sigy
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
