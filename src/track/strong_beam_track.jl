function track!(rep, elem::ThinStrongBeam, turns, ::Type{CPUThreadsBackend})
	Base.depwarn("backend-tag track! is deprecated; pass policy=CPUThreadsExecutionPolicy()", :track!)
	policy = ResolvedCPUExecutionPolicy(Threads.nthreads(:default))
	return _with_execution_policy(policy) do
		track!(rep, elem, turns, policy)
	end
end

"""
Accumulate a per-particle luminosity contribution unless the particle is dead.

Liveness is judged on the coordinates the map *returned*, not the ones it
consumed. A particle that goes non-finite partway through the turn produces a
`NaN` contribution, and testing the input would let that `NaN` into the sum and
take the whole beam's luminosity with it. The output test drops exactly the
contributions that carry no information.

Under `LiveMask{false}` this is `value + lum` with no test, so the default path
is the sum it was before -- including staying `NaN` when a coordinate is
non-finite, which is what makes the failure visible when losses are not expected.
"""
@inline _add_luminosity(::LiveMask{false}, value, lum, x, px, y, py, z, pz) = value + lum

@inline _add_luminosity(mask::LiveMask{true}, value, lum, x, px, y, py, z, pz) =
	live(mask, x, px, y, py, z, pz) ? value + lum : value

"""
Total the CUDA per-particle luminosity array, dropping dead particles.

The kernel has already run, so liveness is read from the post-kernel
representation -- the same "judge the output" rule as the CPU accumulator, and
for the same reason.

The reduction runs on the device and only the scalar crosses PCIe. The
previous host-side `sum(Array(lum))` copied the full buffer every observed
turn -- 8 MB and 6.3 ms at 1M particles, the single largest host-side gap in
the weak-strong turn cycle (2026-08-11 record in `docs/history/`). The device
tree reduction associates the sum differently from the old host pairwise sum,
so `last_luminosity` may move in its last ulp relative to pre-change results;
it is deterministic for a fixed device, length, and launch. CPU and CUDA
backends already used different fold orders (fixed-chunk fold vs host pairwise
sum), so cross-backend luminosity agreement stays physics-level, never
bitwise. The masked path fuses liveness selection into the reduction, with no
flags temporary.
"""
function _cuda_luminosity_total(lum, rep)
	allow_lost_particles() || return sum(lum)
	return mapreduce(_live_luminosity_value, +,
		lum, rep.x, rep.px, rep.y, rep.py, rep.z, rep.pz)
end

@inline _live_luminosity_value(l, x, px, y, py, z, pz) =
	is_live(x, px, y, py, z, pz) ? l : zero(l)

function track!(rep, elem::ThinStrongBeam, turns, policy::ResolvedCPUExecutionPolicy)
	return _track_thin_strong_beam!(rep, elem, turns, policy, active_live_mask())
end

function _track_thin_strong_beam!(rep, elem::ThinStrongBeam, turns, policy, mask)
	# Fixed chunk grid, contiguous membership, chunk-ordered fold (U5-2's
	# recipe; 2026-08-07 neighbour audit, N4): the fold was sized by
	# policy.threads with STRIDED membership, so both the grouping and the
	# membership of every partial changed with the thread setting and
	# last_luminosity was not thread-count invariant -- the class removed
	# from the strong-strong stack, surviving on this weak-strong path. The
	# per-particle tracking writes are index-local either way; only the
	# luminosity fold order needed to become a property of the data.
	# Chunk grid, in GLOBAL terms. The fixed 64-chunk partition and its
	# chunk-ordered fold are what make this luminosity independent of the
	# worker count; a rank shard is a contiguous run of whole chunks, so the
	# same partition and the same order extend across processes -- each rank
	# folds the chunks it owns, and `_mp_chunk_fold` puts them back in chunk
	# order. Bounds are mapped from the global chunk through the shard offset
	# rather than recomputed locally, so the local partition IS the global one
	# rather than something that happens to agree with it.
	nchunks = _REDUCTION_CHUNKS
	offset, global_n = _mp_current_shard(rep)
	first_chunk, local_chunks = _mp_first_chunk(), _mp_local_chunks()
	for _ in 1:turns
		local_lum = zeros(eltype(rep.x), local_chunks)
		_run_logical_workers(local_chunks) do chunk, _
			lo, hi = _chunk_bounds(global_n, nchunks, first_chunk + chunk - 1)
			first_i, last_i = lo - offset, hi - offset
			value = zero(eltype(rep.x))
			for index in first_i:last_i
				@inbounds begin
					x, px, y, py, z, pz, lum = _thin_strong_beam_track(elem, rep[index]...)
					rep[index] = (x, px, y, py, z, pz)
					value = _add_luminosity(mask, value, lum, x, px, y, py, z, pz)
				end
			end
			local_lum[chunk] = value
		end
		elem.last_luminosity = _mp_chunk_fold(local_lum, first_chunk)
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
	return _track_gaussian_strong_beam!(rep, elem, turns, policy, active_live_mask())
end

function _track_gaussian_strong_beam!(rep, elem::GaussianStrongBeam, turns, policy, mask)
	# Fixed chunk grid, contiguous membership, chunk-ordered fold (U5-2's
	# recipe; 2026-08-07 neighbour audit, N4): the fold was sized by
	# policy.threads with STRIDED membership, so both the grouping and the
	# membership of every partial changed with the thread setting and
	# last_luminosity was not thread-count invariant -- the class removed
	# from the strong-strong stack, surviving on this weak-strong path. The
	# per-particle tracking writes are index-local either way; only the
	# luminosity fold order needed to become a property of the data.
	# Chunk grid, in GLOBAL terms. The fixed 64-chunk partition and its
	# chunk-ordered fold are what make this luminosity independent of the
	# worker count; a rank shard is a contiguous run of whole chunks, so the
	# same partition and the same order extend across processes -- each rank
	# folds the chunks it owns, and `_mp_chunk_fold` puts them back in chunk
	# order. Bounds are mapped from the global chunk through the shard offset
	# rather than recomputed locally, so the local partition IS the global one
	# rather than something that happens to agree with it.
	nchunks = _REDUCTION_CHUNKS
	offset, global_n = _mp_current_shard(rep)
	first_chunk, local_chunks = _mp_first_chunk(), _mp_local_chunks()
	for _ in 1:turns
		local_lum = zeros(eltype(rep.x), local_chunks)
		_run_logical_workers(local_chunks) do chunk, _
			lo, hi = _chunk_bounds(global_n, nchunks, first_chunk + chunk - 1)
			first_i, last_i = lo - offset, hi - offset
			value = zero(eltype(rep.x))
			for index in first_i:last_i
				@inbounds begin
					x, px, y, py, z, pz, lum =
						_track_gaussian_strong_beam_with_luminosity(elem, rep[index]...)
					rep[index] = (x, px, y, py, z, pz)
					value = _add_luminosity(mask, value, lum, x, px, y, py, z, pz)
				end
			end
			local_lum[chunk] = value
		end
		elem.last_luminosity = _mp_chunk_fold(local_lum, first_chunk)
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
					turn_lum = zero(x)
					for turn in 1:turns
						# Reset per turn: `last_luminosity` is the FINAL
						# turn's value, as on the CPU path. Accumulating
						# across the in-kernel turn loop made the CUDA
						# result ~turns x the CPU one (2026-08-05 audit
						# queue, U7-2; measured ratio exactly 3.0 at
						# turns = 3).
						turn_lum = zero(x)
						x, px, y, py, z, pz, l = _cuda_thin_strong_beam_track(
							x, px, y, py, z, pz,
							moments, kbb, klum, xo, yo, zo, pxo, pyo, pzo,
							ppxo, ppyo, ppzo, virtual_drift,
						)
						turn_lum += l
					end
					rep[index] = (x, px, y, py, z, pz)
					lum[index] = turn_lum
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
					turn_lum = zero(x)
					for turn in 1:turns
						# Reset per turn — same U7-2 fix as the thin kernel.
						turn_lum = zero(x)
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
							turn_lum += l * slice_weight[i]
						end
					end
					rep[index] = (x, px, y, py, z, pz)
					lum[index] = turn_lum
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

# ---------------------------------------------------------------------------
# Reused per-element CUDA buffers. Every call previously allocated a fresh
# N-element luminosity buffer and, for the sliced element, rebuilt four to six
# ns-element CuArrays; at 1M particles that host-side work was ~1.2 ms per
# observed turn against ~4 ms of kernel time on an A100 (2026-08-11 record in
# docs/history/weak_strong_cuda_luminosity_2026_08_11.md). The cache is keyed
# by element identity, revalidated against device, eltype, and lengths on
# every call, and entries die with their element through the WeakKeyDict.
#
# The luminosity buffer is handed out UNINITIALIZED: both kernels assign
# lum[index] for every index and the grid-stride loop covers 1:length(rep),
# so no stale value can survive into the reduction. If a kernel ever gains an
# early exit that skips indices, this must go back to zeroing.
# ---------------------------------------------------------------------------
const _WEAK_STRONG_CUDA_WS_LOCK = ReentrantLock()
const _WEAK_STRONG_CUDA_WS = Base.WeakKeyDict{Any,Any}()

function _weak_strong_cuda_workspace(elem::ThinStrongBeam, ::Type{T}, N::Int) where {T}
	device = Int(CUDA.deviceid(CUDA.device()))
	return lock(_WEAK_STRONG_CUDA_WS_LOCK) do
		ws = get(_WEAK_STRONG_CUDA_WS, elem, nothing)
		if !(ws isa NamedTuple) || ws.device != device || ws.T !== T || length(ws.lum) != N
			ws = (device=device, T=T, lum=CUDA.CuVector{T}(undef, N))
			_WEAK_STRONG_CUDA_WS[elem] = ws
		end
		return ws
	end
end

function _weak_strong_cuda_workspace(elem::GaussianStrongBeam, ::Type{T}, N::Int) where {T}
	device = Int(CUDA.deviceid(CUDA.device()))
	ns = elem.ns
	angles = _has_slice_angles(elem)
	return lock(_WEAK_STRONG_CUDA_WS_LOCK) do
		ws = get(_WEAK_STRONG_CUDA_WS, elem, nothing)
		valid = ws isa NamedTuple && ws.device == device && ws.T === T &&
			length(ws.lum) == N && length(ws.stage) == ns && ws.angles == angles
		if !valid
			ws = (device=device, T=T, angles=angles,
				lum=CUDA.CuVector{T}(undef, N),
				stage=Vector{T}(undef, ns),
				slice_center=CUDA.CuVector{T}(undef, ns),
				slice_weight=CUDA.CuVector{T}(undef, ns),
				slice_hoffset=CUDA.CuVector{T}(undef, ns),
				slice_voffset=CUDA.CuVector{T}(undef, ns),
				slice_pxoffset=angles ? CUDA.CuVector{T}(undef, ns) : nothing,
				slice_pyoffset=angles ? CUDA.CuVector{T}(undef, ns) : nothing)
			_WEAK_STRONG_CUDA_WS[elem] = ws
		end
		return ws
	end
end

# Slice data is re-uploaded on EVERY call, not cached until invalidation: the
# host vectors are fields of a mutable runtime element that scheduled actions
# may modify between turns, and the CPU path reads them fresh each turn. The
# staging copy performs the same eltype conversion the old
# `CUDA.CuArray(T.(v))` construction did, so the uploaded values are
# bit-identical to before; only the per-call allocations are gone.
function _upload_slice_values!(stage::Vector{T}, dev, host) where {T}
	stage .= host
	copyto!(dev, stage)
	return nothing
end

function _refresh_gaussian_slice_buffers!(ws, elem::GaussianStrongBeam)
	_upload_slice_values!(ws.stage, ws.slice_center, elem.slice_center)
	_upload_slice_values!(ws.stage, ws.slice_weight, elem.slice_weight)
	_upload_slice_values!(ws.stage, ws.slice_hoffset, elem.slice_hoffset)
	_upload_slice_values!(ws.stage, ws.slice_voffset, elem.slice_voffset)
	if ws.angles
		_upload_slice_values!(ws.stage, ws.slice_pxoffset, elem.slice_pxoffset)
		_upload_slice_values!(ws.stage, ws.slice_pyoffset, elem.slice_pyoffset)
	end
	return nothing
end

function track!(rep, elem::ThinStrongBeam, turns, ::Type{CUDABackend}; threads=256, blocks=256, stream=nothing)
	_HAS_CUDA || error("CUDABackend requires CUDA.jl to be available.")
	N = length(rep)
	T = eltype(rep.x)
	lum = _weak_strong_cuda_workspace(elem, T, N).lum
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
	# Only when a turn actually ran (2026-08-05_b audit, U8-2). The CPU
	# assigns inside `for _ in 1:turns`, so at `turns = 0` it retains the
	# previous value; CUDA allocated a zeroed `lum`, launched a kernel whose
	# accumulator never enters the loop body, and then assigned
	# unconditionally -- so a no-op call ERASED the last real measurement.
	# Measured: CPU 1.5854148099e+05 -> 1.5854148099e+05, CUDA the same value
	# -> 0.0. The U7-2 regression pin covers `turns = 3` only.
	turns > 0 && (elem.last_luminosity = _cuda_luminosity_total(lum, rep))
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
	ws = _weak_strong_cuda_workspace(elem, T, N)
	_refresh_gaussian_slice_buffers!(ws, elem)
	lum = ws.lum
	slice_center = ws.slice_center
	slice_weight = ws.slice_weight
	slice_hoffset = ws.slice_hoffset
	slice_voffset = ws.slice_voffset
	has_slice_angles = Val(_has_slice_angles(elem))
	slice_pxoffset = ws.slice_pxoffset
	slice_pyoffset = ws.slice_pyoffset
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
	# Only when a turn actually ran (2026-08-05_b audit, U8-2). The CPU
	# assigns inside `for _ in 1:turns`, so at `turns = 0` it retains the
	# previous value; CUDA allocated a zeroed `lum`, launched a kernel whose
	# accumulator never enters the loop body, and then assigned
	# unconditionally -- so a no-op call ERASED the last real measurement.
	# Measured: CPU 1.5854148099e+05 -> 1.5854148099e+05, CUDA the same value
	# -> 0.0. The U7-2 regression pin covers `turns = 3` only.
	turns > 0 && (elem.last_luminosity = _cuda_luminosity_total(lum, rep))
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
	Kx, Ky, Hxx, Hyy =
		_cuda_gaussian_beambeam_kick_response(kbb, sigx, sigy, xx, yy)
	expterm = exp(-0.5 * (xx * xx / a + yy * yy / d))
	px += kbb * Kx
	py += kbb * Ky
	pz += 0.25 * (Hxx * au + Hyy * du)
	return x, px, y, py, z, pz, expterm / (TWOPI * sigx * sigy)
end

@inline function _cuda_cp_covariance_kick(m::StrongTransverseMoments{T,true}, kbb,
	S, xx, yy, x, px, y, py, z, pz) where {T}
	a, b, d, au, bu, du = _transport_transverse_moments(m, S)
	detA = a * d - b * b
	(a <= 0 || d <= 0 || detA <= 0) && return x, px, y, py, z, pz, zero(x)
	adiff = a - d
	D = hypot(adiff, 2 * b)
	if D == zero(D)
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
	eta = D / (a + d)
	inner, _ = _near_round_eta_bounds(eta)
	if eta <= inner
		Kxh, Kyh, H11, H22, L_over_D =
			_near_round_series_response(kbb, (a + d) / 2, eta, xh, yh)
	else
		Kxh, Kyh, H11, H22, L_over_D =
			_cuda_gaussian_beambeam_kick_response_principal(
				kbb, sig1, sig2, xh, yh)
	end
	expterm = exp(-0.5 * (xh * xh / lambda1 + yh * yh / lambda2))
	Fxh, Fyh = kbb * Kxh, kbb * Kyh
	px += c * Fxh - s * Fyh
	py += s * Fxh + c * Fyh
	Du = (adiff * (au - du) + 4 * b * bu) / D
	traceu = au + du
	pz += 0.125 * ((H11 + H22) * traceu + (H11 - H22) * Du)
	rotation_projection = (adiff * bu - b * (au - du)) / D
	pz -= 0.5 * kbb * rotation_projection * L_over_D
	return x, px, y, py, z, pz, expterm / (TWOPI * sig1 * sig2)
end

@inline function _cuda_elliptic_gaussian_kick_principal(sig1, sig2, x, y)
	T = typeof(sig1)
	v = (sig1 * sig1 + sig2 * sig2) / 2
	eta = (sig1 * sig1 - sig2 * sig2) / (2 * v)
	if _use_elliptic_near_axis(sig1, sig2, x, y, eta)
		Kx, Ky, _, _ = _elliptic_gaussian_near_axis_response(
			zero(sig1), sig1, sig2, x, y)
		return Kx, Ky
	end
	negx = x < 0
	negy = y < 0
	x = abs(x)
	y = abs(y)
	denominator = T(SQRT2) * sqrt(sig1 * sig1 - sig2 * sig2)
	z1r = x / denominator
	z1i = y / denominator
	z2r = sig2 / sig1 * x / denominator
	z2i = sig1 / sig2 * y / denominator
	w1r, w1i = faddeeva_w_upper_reim(z1r, z1i)
	w2r, w2i = faddeeva_w_upper_reim(z2r, z2i)
	A = T(2) * T(SQRTPI) / denominator
	B = exp(-x * x / (2 * sig1 * sig1) - y * y / (2 * sig2 * sig2))
	retr = A * (w1r - B * w2r)
	reti = A * (w1i - B * w2i)
	Kx = reti
	Ky = retr
	# `Ky` is built from the REAL part of w, which carries no relative accuracy
	# near the real axis: `Re w(x + i0) = exp(-x^2)`, and for x >~ 5 that is far
	# below the ~1e-14 absolute error of the |w| evaluation, so `Re w` is noise
	# there. On the symmetry axis y = 0 the exact answer is Ky = 0 and this
	# returns the noise instead.
	#
	# Measured and NEGLIGIBLE, recorded here so the seam is not rediscovered as
	# an open question (2026-08-05_b audit, U14-11). At sig1 = 106 um,
	# sig2 = 9.5 um, x = 3e-4 m: Ky(y=0) = 6.4e-10 against Kx = 7.9e+03, a ratio
	# of 8.1e-14 -- an effective spurious |y| of ~9e-18 m, about 1e-12 sigma_y.
	# `Ky(y = 1e-9)` is already 7.1e-02, so the floor is only reached below
	# |y| ~ 1e-17 m. Floors at x = 1e-3 and 2e-3 m are 6.0e-10 and 1.6e-10.
	# Nothing in this repository resolves 1e-12 sigma, so there is no repair
	# owed; what would be wrong is discovering this number in a test and
	# treating it as a defect.
	return negx ? -Kx : Kx, negy ? -Ky : Ky
end

@inline function _cuda_gaussian_beambeam_kick_principal(sig1, sig2, x, y)
	v = (sig1 * sig1 + sig2 * sig2) / 2
	eta = (sig1 * sig1 - sig2 * sig2) / (2 * v)
	if eta == zero(eta)
		r2 = x * x + y * y
		scale = _round_gaussian_force_scale(r2, v)
		return scale * x, scale * y
	end
	inner, outer = _near_round_eta_bounds(eta)
	if eta <= inner
		return _near_round_series_kick(v, eta, x, y)
	end
	Kex, Key = _cuda_elliptic_gaussian_kick_principal(sig1, sig2, x, y)
	if eta >= outer
		return Kex, Key
	end
	w, _ = _near_round_blend(eta)
	Ksx, Ksy = _near_round_series_kick(v, eta, x, y)
	return Ksx + w * (Kex - Ksx), Ksy + w * (Key - Ksy)
end

@inline function _cuda_gaussian_beambeam_kick_response_principal(
		kbb, sig1, sig2, x, y)
	T = typeof(sig1)
	v = (sig1 * sig1 + sig2 * sig2) / T(2)
	eta = (sig1 * sig1 - sig2 * sig2) / (T(2) * v)
	if eta == zero(eta)
		r2 = x * x + y * y
		scale = _round_gaussian_force_scale(r2, v)
		expterm = exp(-r2 / (T(2) * v))
		H1, _, H2 = _round_gaussian_hessian(kbb, sqrt(v), x, y, expterm)
		# The limit, matching the CPU twin (2026-08-05_b audit, U8-1): L/D is
		# `-x*y*m1(q)/v^2` as eta -> 0, not zero. Both sides carried the same
		# hard zero, so CPU/CUDA parity could not see it.
		_, m1_round, _, _, _, _, _ = _near_round_moments_0_6(r2 / (T(2) * v))
		return scale * x, scale * y, H1, H2, -x * y / (v * v) * m1_round
	end

	inner, outer = _near_round_eta_bounds(eta)
	if eta <= inner
		return _near_round_series_response(kbb, v, eta, x, y)
	end

	Kex, Key = _cuda_elliptic_gaussian_kick_principal(sig1, sig2, x, y)
	expterm = exp(-T(0.5) * (x * x / (sig1 * sig1) + y * y / (sig2 * sig2)))
	if _use_elliptic_near_axis(sig1, sig2, x, y, eta)
		_, _, He1, He2 = _elliptic_gaussian_near_axis_response(
			kbb, sig1, sig2, x, y)
	else
		He1, He2 = _elliptic_gaussian_hessian_diagonal(
			kbb, sig1, sig2, x, y, Kex, Key, expterm)
	end
	D = T(2) * v * eta
	Le_over_D = (Kex * y - Key * x) / D
	if eta >= outer
		return Kex, Key, He1, He2, Le_over_D
	end

	w, dw = _near_round_blend(eta)
	Ksx, Ksy, Hs1, Hs2, Ls_over_D =
		_near_round_series_response(kbb, v, eta, x, y)
	deltaU = _near_round_potential_residual(v, eta, x, y)
	chain = kbb * dw * deltaU / v
	Kx = Ksx + w * (Kex - Ksx)
	Ky = Ksy + w * (Key - Ksy)
	H1 = Hs1 + w * (He1 - Hs1) + (one(T) - eta) * chain
	H2 = Hs2 + w * (He2 - Hs2) - (one(T) + eta) * chain
	L_over_D = Ls_over_D + w * (Le_over_D - Ls_over_D)
	return Kx, Ky, H1, H2, L_over_D
end

@inline function _cuda_gaussian_beambeam_kick_response(kbb, sigx, sigy, x, y)
	if sigx >= sigy
		Kx, Ky, Hx, Hy, _ = _cuda_gaussian_beambeam_kick_response_principal(
			kbb, sigx, sigy, x, y)
	else
		Ky, Kx, Hy, Hx, _ = _cuda_gaussian_beambeam_kick_response_principal(
			kbb, sigy, sigx, y, x)
	end
	return Kx, Ky, Hx, Hy
end

@inline function _cuda_gaussian_beambeam_kick(sigx, sigy, x, y)
	(sigx == 0 || sigy == 0) && return zero(x), zero(y)
	if sigx >= sigy
		return _cuda_gaussian_beambeam_kick_principal(sigx, sigy, x, y)
	end
	Ky, Kx = _cuda_gaussian_beambeam_kick_principal(sigy, sigx, y, x)
	return Kx, Ky
end
