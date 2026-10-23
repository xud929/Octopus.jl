"""
    _collect_strong_beams!(acc, elem) -> acc

Every strong beam reachable through `elem`, in LINE ORDER, descending through the
four wrappers that hide one (`CompositeLine`, `MisalignedElement`, `RefTilted`,
`TurnModulated`).

The order matters as much as the membership: `fusedTrackLuminous` concatenates
its per-element accumulators depth-first in the same order, so this walk and that
expansion must agree or the artifact's channels get crossed -- beam 1's number
written to beam 2's dataset, with nothing to notice it. Two consumers read it:
the task layer's wrapper-aware beam list (`_strong_beams_of`,
src/tasks/Tasks.jl) and the CUDA wrapped-strong-beam launch below
(`_track_cuda_wrapped_strong_beam!`), which hands each beam the luminosity the
kernel accumulated for it in that order.
"""
_collect_strong_beams!(acc, elem) =
	elem isa Union{ThinStrongBeam,GaussianStrongBeam} ?
		(push!(acc, elem); acc) : _descend_strong_beams!(acc, elem)

_descend_strong_beams!(acc, elem) = acc
_descend_strong_beams!(acc, elem::Union{MisalignedElement,RefTilted,TurnModulated}) =
	_collect_strong_beams!(acc, elem.inner)
function _descend_strong_beams!(acc, elem::CompositeLine)
	for op in elem.ops
		_collect_strong_beams!(acc, op)
	end
	return acc
end

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

		# The lifted bare strong beams keep their own per-element launch
		# (`_track_cuda_elementwise!`, src/track/phase6d_track.jl): the
		# context is not consulted, the kick has no turn or particle dependence.
		_track_cuda_elementwise!(rep, elem::Union{ThinStrongBeam,GaussianStrongBeam},
								 policy, ctx, stream) =
			track!(rep, elem, 1, policy; stream=stream)

		"""
		    cuda_track_wrapped_strong_beam_kernel!(rep, lums, elem, mask, ctx)

		One turn of a frame- or turn-modulation-wrapped strong beam, the whole
		wrapper on the device with its frames intact and the beam(s) inside it
		as device views (`ThinStrongBeamDeviceView`, `GaussianStrongBeamDeviceView`):
		`track_luminous` threads the coordinates through the wrapper exactly as
		the CPU fused route does and hands back one luminosity per strong beam
		inside, in line order, which the kernel writes to the matching entry of
		`lums` (one per-particle buffer per beam, the elements' reused
		workspaces). The host folds each buffer into its beam's `last_luminosity`
		(`_track_cuda_wrapped_strong_beam!`). A beam count the collector and
		`fusedTrackLuminous` disagree on leaves `_store_luminosities!` without a
		method and fails the device compile by name.
		"""
		function cuda_track_wrapped_strong_beam_kernel!(rep, lums, elem, mask, ctx)
			start_index = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
			stride = CUDA.gridDim().x * CUDA.blockDim().x
			index = start_index
			while index <= length(rep)
				@inbounds begin
					coords, contributions = track_luminous(
						elem, mask, ctx, ctx.index_offset + index, rep[index]...)
					rep[index] = coords
					_store_luminosities!(lums, contributions, index)
				end
				index += stride
			end
			return nothing
		end

		@inline _store_luminosities!(::Tuple{}, ::Tuple{}, index) = nothing
		@inline function _store_luminosities!(lums::Tuple, contributions::Tuple, index)
			@inbounds first(lums)[index] = first(contributions)
			return _store_luminosities!(Base.tail(lums), Base.tail(contributions), index)
		end
	end
end

# ---------------------------------------------------------------------------
# The wrapped strong beam on CUDA (fix M, 2026-10-18). A wrapper cannot be
# taken apart to launch the beam inside it alone -- the frame change around a
# misaligned beam is the physics -- and the bare launches cannot take it
# whole: they unpack the MUTABLE element's fields as scalar kernel arguments,
# and a wrapper holding the element is not a bitstype. So the whole wrapper
# goes to the device with every strong beam inside it replaced by an isbits
# device view, and the kernel above threads the coordinates through it with
# `track_luminous`, the wrappers' own forwarding methods.
# ---------------------------------------------------------------------------

"""
    ThinStrongBeamDeviceView

The device view of a `ThinStrongBeam`: the thirteen fields the CUDA kick chain
reads (`_cuda_thin_strong_beam_track`), immutable and isbits, with no
`last_luminosity` (written on the host from the kernel's per-particle
luminosities). It is what a frame or turn-modulation wrapper holds when the
wrapper itself is the kernel argument. Built by `Adapt.adapt` under
`_StrongBeamDeviceViews`, never placed in a line; not an `AbstractTrackOp`, so
the registry snapshot, the rounding-class declarations and the wrapper walks
never meet it, as for `ThinStrongBeamSlice`.
"""
struct ThinStrongBeamDeviceView{T<:Number,P<:StrongTransverseMoments,D<:AbstractVirtualDrift}
	moments::P
	kbb::T
	klum::T
	xo::T
	yo::T
	zo::T
	pxo::T
	pyo::T
	pzo::T
	ppxo::T
	ppyo::T
	ppzo::T
	virtual_drift::D
end

_thin_strong_beam_device_view(e::ThinStrongBeam) = ThinStrongBeamDeviceView(
	e.moments, e.kbb, e.klum, e.xo, e.yo, e.zo, e.pxo, e.pyo, e.pzo,
	e.ppxo, e.ppyo, e.ppzo, e.virtual_drift)

"""
    GaussianStrongBeamDeviceView

The device view of a `GaussianStrongBeam`: the slice count, the slice vectors
as the element's reused DEVICE buffers (`_weak_strong_cuda_workspace`;
`CuVector`s on the host side of the launch, `CuDeviceVector`s inside the
kernel through `Adapt.@adapt_structure`), the slice-angle flag as a `Val` field
so the implicit constructor infers it, and the thin view of `elem.thin`.
`slice_pxoffset` and `slice_pyoffset` are `nothing` without slice angles, as in
the workspace.
"""
struct GaussianStrongBeamDeviceView{T<:Number,P<:StrongTransverseMoments,
                                    D<:AbstractVirtualDrift,A,V,W}
	ns::Int
	slice_center::V
	slice_weight::V
	slice_hoffset::V
	slice_voffset::V
	slice_pxoffset::W
	slice_pyoffset::W
	has_slice_angles::Val{A}
	thin::ThinStrongBeamDeviceView{T,P,D}
end

# The luminosity-carrying track of the device views: the per-particle bodies
# of the two bare kernels above, written against the view's fields -- the same
# `_cuda_thin_strong_beam_track` chain with the same arguments in the same
# order, so a wrapper that does not move the beam (identity frames) gives the
# bare launch's coordinates to the bit (pinned by the suite). The mask is
# applied HERE, at the element's position, the CPU fused route's rule
# (`track_luminous`, src/track/Track.jl), not in the reduction as the bare
# launches apply it: the host fold of this route is a plain `sum`.
@inline function track_luminous(e::ThinStrongBeamDeviceView, mask, ctx::TrackingContext,
                                particle_id, x, px, y, py, z, pz)
	x1, px1, y1, py1, z1, pz1, l = _cuda_thin_strong_beam_track(
		x, px, y, py, z, pz,
		e.moments, e.kbb, e.klum, e.xo, e.yo, e.zo, e.pxo, e.pyo, e.pzo,
		e.ppxo, e.ppyo, e.ppzo, e.virtual_drift)
	contribution = _add_luminosity(mask, zero(l), l, x1, px1, y1, py1, z1, pz1)
	return ((x1, px1, y1, py1, z1, pz1), (contribution,))
end

@inline function track_luminous(e::GaussianStrongBeamDeviceView, mask, ctx::TrackingContext,
                                particle_id, x, px, y, py, z, pz)
	t = e.thin
	lum = zero(x)
	for i in e.ns:-1:1
		slice_pxo, slice_pyo = _cuda_slice_transverse_angles(
			e.has_slice_angles, t.pxo, t.pyo, e.slice_pxoffset, e.slice_pyoffset, i)
		x, px, y, py, z, pz, l = _cuda_thin_strong_beam_track(
			x, px, y, py, z, pz,
			t.moments,
			t.kbb * e.slice_weight[i], t.klum,
			t.xo + e.slice_hoffset[i], t.yo + e.slice_voffset[i], t.zo + e.slice_center[i],
			slice_pxo, slice_pyo, t.pzo,
			t.ppxo, t.ppyo, t.ppzo, t.virtual_drift)
		lum += l * e.slice_weight[i]
	end
	contribution = _add_luminosity(mask, zero(lum), lum, x, px, y, py, z, pz)
	return ((x, px, y, py, z, pz), (contribution,))
end

"""
    _StrongBeamDeviceViews{T}(N)

The adaptor of the wrapped-strong-beam launch (`_track_cuda_wrapped_strong_beam!`):
`Adapt.adapt(_StrongBeamDeviceViews{T}(N), w)` on the HOST, before `@cuda`,
descends the wrappers by their own `adapt_structure` methods
(src/track/phase6d_track.jl) and replaces every mutable strong beam at the
leaves with its device view -- the thin one from the element's scalars, the
Gaussian one holding the element's reused device slice buffers
(`_weak_strong_cuda_workspace(elem, T, N)`, refreshed from the host vectors
here as the bare launch refreshes them). `T` and `N` are the beam's element
type and particle count, the workspace's key. Everything else passes through,
so the launch's own kernel adaptor then meets only isbits views and the
`CuVector`s it converts. Host-side only; never on a kernel path.
"""
struct _StrongBeamDeviceViews{T}
	N::Int
end

if _HAS_ADAPT
	@eval begin
		Adapt.adapt_storage(::_StrongBeamDeviceViews, e::ThinStrongBeam) =
			_thin_strong_beam_device_view(e)
		function Adapt.adapt_storage(a::_StrongBeamDeviceViews{T}, e::GaussianStrongBeam) where {T}
			ws = _weak_strong_cuda_workspace(e, T, a.N)
			_refresh_gaussian_slice_buffers!(ws, e)
			return GaussianStrongBeamDeviceView(
				e.ns, ws.slice_center, ws.slice_weight, ws.slice_hoffset, ws.slice_voffset,
				ws.slice_pxoffset, ws.slice_pyoffset, Val(_has_slice_angles(e)),
				_thin_strong_beam_device_view(e.thin))
		end
		Adapt.@adapt_structure GaussianStrongBeamDeviceView
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
	blocks = _cuda_resolve_coverage_blocks(policy, length(rep))
	blocks == 0 && return nothing
	_record_execution!(:cuda_weak_strong_launch, CUDABackend,
		(threads=policy.threads, blocks=blocks, requested_blocks=policy.blocks,
		 resolved_by=_cuda_blocks_resolved_by(policy),
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
	blocks = _cuda_resolve_coverage_blocks(policy, length(rep))
	blocks == 0 && return nothing
	_record_execution!(:cuda_weak_strong_launch, CUDABackend,
		(threads=policy.threads, blocks=blocks, requested_blocks=policy.blocks,
		 resolved_by=_cuda_blocks_resolved_by(policy),
		 element=:gaussian, stream=stream === nothing ? :default : :explicit))
	return track!(rep, elem, turns, CUDABackend;
		threads=policy.threads, blocks=blocks, stream=stream)
end

"""
    _track_cuda_wrapped_strong_beam!(rep, w, policy, ctx, stream)

One turn of a strong beam behind a frame or turn-modulation wrapper on CUDA, the
route `_track_cuda_elementwise!` (src/track/phase6d_track.jl) takes for a lifted
`MisalignedElement`, `RefTilted` or `TurnModulated` whose contents require it
(a `CompositeLine` is walked member by member instead). The whole wrapper goes
to the device with every strong beam inside it replaced by its isbits device
view (`Adapt.adapt` under `_StrongBeamDeviceViews`), the kernel
`cuda_track_wrapped_strong_beam_kernel!` threads the coordinates through the
wrapper with `track_luminous`, and the host folds each beam's per-particle
luminosities into its `last_luminosity`, the beams collected in line order by
`_collect_strong_beams!` -- the order `fusedTrackLuminous` emits them in, so
each number lands on its own element, a misaligned sub-line with several beams
included.

Liveness is judged in the kernel at the element's position (the CPU fused
route's rule), so the fold is a plain device `sum` rather than the bare
launches' post-kernel mask (`_cuda_luminosity_total`): with losses disallowed
the two agree, with losses allowed this one counts a particle alive at the beam
and lost later in the same wrapper, as the CPU does. The per-particle buffers
are the elements' reused workspaces (`_weak_strong_cuda_workspace`), so a
wrapped beam allocates no more per turn than a bare one; the Gaussian slice
vectors are re-uploaded per launch as the bare launch re-uploads them. The
receipt is the bare launches' `:cuda_weak_strong_launch` with
`element = :wrapped`, the wrapper's name and the beam count.
"""
function _track_cuda_wrapped_strong_beam!(rep, w, policy::ResolvedCUDAExecutionPolicy,
                                          ctx::TrackingContext, stream)
	_HAS_CUDA || error("CUDABackend requires CUDA.jl to be available.")
	N = length(rep)
	T = eltype(rep.x)
	blocks = _cuda_resolve_coverage_blocks(policy, N)
	blocks == 0 && return nothing
	beams = _collect_strong_beams!(Any[], w)
	isempty(beams) && throw(ArgumentError(
		"$(nameof(typeof(w))) was lifted out of the fused CUDA launch as a wrapped " *
		"strong beam, but no strong beam is reachable inside it: " *
		"`_requires_cuda_elementwise` and `_collect_strong_beams!` disagree about " *
		"what the wrapper holds"))
	lums = Tuple(_weak_strong_cuda_workspace(beam, T, N).lum for beam in beams)
	view = Adapt.adapt(_StrongBeamDeviceViews{T}(N), w)
	mask = active_live_mask()
	_record_execution!(:cuda_weak_strong_launch, CUDABackend,
		(threads=policy.threads, blocks=blocks, requested_blocks=policy.blocks,
		 resolved_by=_cuda_blocks_resolved_by(policy),
		 element=:wrapped, wrapper=Symbol(nameof(typeof(w))), strong_beams=length(beams),
		 stream=stream === nothing ? :default : :explicit))
	if stream === nothing
		CUDA.@cuda threads=policy.threads blocks=blocks cuda_track_wrapped_strong_beam_kernel!(
			rep, lums, view, mask, ctx)
	else
		CUDA.@cuda threads=policy.threads blocks=blocks stream=stream cuda_track_wrapped_strong_beam_kernel!(
			rep, lums, view, mask, ctx)
		CUDA.synchronize(stream)
	end
	for (beam, lum) in zip(beams, lums)
		beam.last_luminosity = sum(lum)
	end
	return nothing
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
	# The literal in the drift's working type (`oftype(S, 0.5)`), as the CPU
	# twin: the Float64 `0.5` of the original code whenever the element or the
	# beam is Float64, a Float32 one only when both are -- the bare literal
	# promoted a Float32 kick to Float64, so the kernel's branches returned
	# tuples of two types and a Float32 strong beam failed device compile (fix
	# H, 2026-10-16).
	xx = x - xo + pxo * S - oftype(S, 0.5) * ppxo * S * S
	yy = y - yo + pyo * S - oftype(S, 0.5) * ppyo * S * S
	px0, py0 = px, py
	x, px, y, py, z, pz, density = _cuda_cp_covariance_kick(
		moments, kbb, S, xx, yy, x, px, y, py, z, pz)
	pz += oftype(S, 0.5) * ((px - px0) * (pxo - ppxo * S) +
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
	expterm = exp(-T(0.5) * (xx * xx / a + yy * yy / d))
	px += kbb * Kx
	py += kbb * Ky
	pz += T(0.25) * (Hxx * au + Hyy * du)
	return x, px, y, py, z, pz, expterm / (T(TWOPI) * sigx * sigy)
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
		expterm = exp(-T(0.5) * (xx * xx + yy * yy) / (sigma * sigma))
		Fx, Fy = kbb * Kx, kbb * Ky
		Hxx, Hxy, Hyy = _round_gaussian_hessian(kbb, sigma, xx, yy, expterm)
		px += Fx
		py += Fy
		pz += T(0.25) * (Hxx * au + 2 * Hxy * bu + Hyy * du)
		return x, px, y, py, z, pz, expterm / (T(TWOPI) * sigma * sigma)
	end
	theta = T(0.5) * atan(2 * b, a - d)
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
	expterm = exp(-T(0.5) * (xh * xh / lambda1 + yh * yh / lambda2))
	Fxh, Fyh = kbb * Kxh, kbb * Kyh
	px += c * Fxh - s * Fyh
	py += s * Fxh + c * Fyh
	Du = (adiff * (au - du) + 4 * b * bu) / D
	traceu = au + du
	pz += T(0.125) * ((H11 + H22) * traceu + (H11 - H22) * Du)
	rotation_projection = (adiff * bu - b * (au - du)) / D
	pz -= T(0.5) * kbb * rotation_projection * L_over_D
	return x, px, y, py, z, pz, expterm / (T(TWOPI) * sig1 * sig2)
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
