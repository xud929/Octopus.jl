"""
    track!(rep, elems, turns; policy=nothing, context=TrackingContext())

Track all particles in `rep` through callable runtime `elems` for `turns`
turns. With `policy=nothing`, the execution policy is inferred from particle
storage. A supplied policy selects execution for existing storage and never
migrates it. `context` supplies turn and counter-RNG state independently of the
execution policy. A `TurnModulated` element in a bare `track!` line tracks its
`inner` element, unchanged across turns -- the NOMINAL element for a freshly
compiled wrapper (`inner === base`), the last realised one for a wrapper that
went through `update_line` by hand or was read back out of a task's plan: the
rules are realised only by a task's `execute!`, which calls `update_line`
before each turn (design decision D5, `docs/design/turn_modulation.md`).
Task-managed operations such as [`PhaseSpaceResetSpec`](@ref) require
[`TrackingTask`](@ref); this entry rejects them before tracking starts,
including when they are nested in a runtime wrapper or composite line.
"""
function track!(rep, elems, turns; policy::Union{Nothing,AbstractExecutionPolicy}=nothing,
                context::TrackingContext=TrackingContext())
	_reject_task_only_tracking(elems)
	resolved = _resolve_execution_policy(policy, rep)
	_with_execution_policy(resolved) do
		# Inside the policy scope, because the shard is a property of the
		# communicator this run has, and deriving it issues a collective.
		track!(rep, elems, turns, resolved, _shard_context(context, rep))
	end
	return nothing
end

"""
Give `ctx` the global index offset of this rank's shard, or leave it alone
outside a multi-process run.

Left alone rather than zeroed: a caller may have set an offset deliberately
(tracking a slice of a beam it split itself), and overwriting that with 0
would silently re-key its random streams.
"""
function _shard_context(ctx::TrackingContext, rep)
	_multi_process_context() === nothing && return ctx
	offset, _ = _mp_resolve_shard(length(rep))
	return with_index_offset(ctx, offset)
end

function track!(rep, elems, turns, policy::AbstractExecutionPolicy;
                context::TrackingContext=TrackingContext())
	Base.depwarn("pass execution policy with policy= instead of as a positional argument", :track!)
	return track!(rep, elems, turns; policy=policy, context=context)
end

function track!(rep, elems, turns, policy::ResolvedCPUExecutionPolicy,
				ctx::TrackingContext)
	_reject_task_only_tracking(elems)
	return _track_admitted!(rep, elems, turns, policy, ctx)
end

# Only a task that has checked storage ownership may admit a bound
# particle-tune runtime. Public tracking keeps its lifecycle guard.
function _track_admitted!(rep, elems, turns, policy::ResolvedCPUExecutionPolicy,
						 ctx::TrackingContext; stream=nothing)
	for turn in 1:turns
		turn_ctx = with_turn(ctx, ctx.turn + Int64(turn - 1))
		_run_logical_workers(policy.threads) do worker, nworkers
			for index in worker:nworkers:length(rep)
				@inbounds rep[index] = fusedTrack(turn_ctx, elems,
				                                  turn_ctx.index_offset + index,
				                                  rep[index]...)
			end
		end
	end
	return nothing
end

function track!(rep, elems, turns, policy::ResolvedCPUExecutionPolicy)
	_reject_task_only_tracking(elems)
	_reject_contextless_tracking(elems)
	for turn in 1:turns
		_run_logical_workers(policy.threads) do worker, nworkers
			for index in worker:nworkers:length(rep)
				@inbounds rep[index] = fusedTrack(elems, rep[index]...)
			end
		end
	end
	return nothing
end

# The host preflight applies even to context-aware tracking: a TrackingContext
# carries stochastic keys, not the beam-level capture and loss lifecycle.
function _reject_task_only_tracking(elems)
	_requires_tracking_task(elems) || return nothing
	throw(ArgumentError("task-managed PhaseSpaceReset or ParticleLinear6D requires TrackingTask; bare track! cannot bind its particle state"))
end

_requires_tracking_task(w::Union{MisalignedElement,RefTilted,TurnModulated}) =
	_requires_tracking_task(w.inner)
_requires_tracking_task(c::CompositeLine) = _requires_tracking_task(c.ops)

"""
Refuse a context-free `track!` for a line that cannot run without a context.

A recording aperture needs the turn and the particle index, and this path has
neither. Silently tracking would give a physically correct run whose loss log is
empty, which reads as "nothing was lost" rather than "nothing was recorded" --
the failure mode this whole design is trying to avoid. Checked once per call on
the host; `_requires_tracking_context` folds to a constant over the tuple.
"""
function _reject_contextless_tracking(elems)
	_requires_tracking_context(elems) || return nothing
	throw(ArgumentError(
		"this line contains an aperture with a loss record attached, which needs " *
		"the turn and particle index that only context-aware tracking carries. " *
		"Pass a context (`track!(rep, elems, turns, policy, ctx)`) or run through " *
		"a TrackingTask, which always does. Tracking without one would produce a " *
		"correct run with a silently empty loss log."))
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

# The four wrappers answer for what they hold, in BOTH forms -- the contextless
# one and the context-taking one, which `LumpedRad` answers differently (true
# contextless, so a context gets built and the counter RNG is keyed by the
# turn; false with one, so it fuses). Without these a strong beam behind a
# misalignment, a design roll, a turn-modulation wrap or a kept-whole sub-line
# answered the generic `false`, was never lifted out of the fused launch, and
# reached it as a kernel argument: the MUTABLE element inside the wrapper
# failed the launch with `KernelError: passing non-bitstype argument` through
# bare `track!` and through `execute!` alike, while the bare beam beside it
# tracked (found 2026-10-12 in the turn-modulation review; measured on every
# wrapped shape 2026-10-18, fix M). The lifted wrapper is tracked by
# `_track_cuda_elementwise!` below. Defined here, outside the CUDA block, so a
# CPU-only machine and the suite's wrapper-walk tripwire ("Turn modulation:
# rules, wrapper and the pure hook", test 7) see the methods the launch reaches.
_requires_cuda_elementwise(w::Union{MisalignedElement,RefTilted,TurnModulated}) =
	_requires_cuda_elementwise(w.inner)
_requires_cuda_elementwise(w::Union{MisalignedElement,RefTilted,TurnModulated}, ctx::TrackingContext) =
	_requires_cuda_elementwise(w.inner, ctx)
_requires_cuda_elementwise(c::CompositeLine) = _requires_cuda_elementwise(c.ops)
_requires_cuda_elementwise(c::CompositeLine, ctx::TrackingContext) =
	_requires_cuda_elementwise(c.ops, ctx)

# The ONE elementwise walker over a CUDA line is `_track_cuda_policy_elementwise!`
# in the CUDA block below. A second, uncalled walker (`_track_line_elementwise!`
# and `_flush_cuda_fused_segment!`, eleven methods over the deprecated backend-tag
# `track!`, 0 call sites) lived here until 2026-10-22; it dropped the context for
# a lifted element and flattened a nested tuple without a flush, so a routing fix
# could land on the wrong function (2026-10-18 audit, F-102). The suite pins the
# symbols absent.

# The per-element launches of the lifted strong beams (src/track/strong_beam_track.jl)
# resolve `blocks=:auto` by PARTICLE COVERAGE capped at `_CUDA_COVERAGE_BLOCK_CAP`
# grid-stride blocks, the rule `_active_cuda_launch` (src/policies/Policies.jl) applies
# to the strong-strong kernels, where the fused launch below reads the occupancy API
# (`_cuda_fused_occupancy_blocks`). One function and one constant: until 2026-10-22
# the rule was spelled by hand at four launch sites, the radiation compatibility
# launch among them, and nothing tied the copies together (2026-10-18 audit, F-104).
# An explicit block count passes through untouched; `_cuda_blocks_resolved_by` names
# the rule that ran for the launch receipt, as the strong-strong receipt does. Defined
# outside the CUDA block, as the launch sites are, so a CPU-only machine sees the
# methods and the suite's tripwire reads the rule.
const _CUDA_COVERAGE_BLOCK_CAP = 256
function _cuda_resolve_coverage_blocks(policy::ResolvedCUDAExecutionPolicy, nitems::Integer)
	policy.blocks isa Int && return policy.blocks
	return min(cld(Int(nitems), policy.threads), _CUDA_COVERAGE_BLOCK_CAP)
end
_cuda_blocks_resolved_by(policy::ResolvedCUDAExecutionPolicy) =
	policy.blocks isa Int ? :explicit : :particle_coverage

if _HAS_ADAPT
	@eval begin
		# The device conversion of a turn-modulated element (design D8,
		# docs/design/turn_modulation.md). The fused element tuple is a kernel
		# ARGUMENT, and `@cuda` converts its arguments through the two-argument
		# `kernel_convert`, i.e. `adapt(KernelAdaptor(managed), x)`, which
		# recurses through a tuple element-wise via `adapt_structure`. THIS is
		# therefore the method the launch reaches for a wrapper inside the
		# tuple -- a `CUDA.cudaconvert(::TurnModulated)` method would not be,
		# because the tuple recursion goes through Adapt, not through
		# `cudaconvert`. No Octopus method extends `CUDA.cudaconvert` at all:
		# the one-argument `cudaconvert(::Phase6DRep)` this file once defined
		# was never on a launch path (0 calls over six launch paths; the
		# representation converts through `Adapt.@adapt_structure` in
		# src/beam/Beam.jl), CUDA documents the function as not to be
		# extended, and the suite pins the method table (2026-10-13 neighbour
		# audit, U3-1). The kernel sees the realised element and never the
		# rule, and a wrapper carrying a host table (not isbits) still launches.
		#
		# The three containers need the same descent, or a wrapper INSIDE them
		# is never reached: Adapt's default `adapt_structure` is the identity
		# for a struct it does not know, so without these a misaligned noisy
		# cavity -- `MisalignedElement(TurnModulated(...))`, the common case --
		# or one in a kept-whole sub-line reached the launch unconverted and
		# failed with "passing non-bitstype argument ... .rule is of type
		# TurnTable" (measured on the RTX 4500 Ada, 2026-10-12; the record is
		# docs/history/turn_modulation_stage1_2026_10_12.md section 3 and the
		# regression test is the suite's testset "Turn modulation: CPU/CUDA
		# identity and the device conversion"). Frame data is isbits and
		# carried as is. The same descent also reaches a recording aperture's
		# DEVICE record inside the two frame wrappers, which the identity
		# default had left unconverted as well (U3-5; the same testset).
		#
		# Defined for ANY adaptor `to`, not only the kernel adaptor: these are
		# kernel semantics (the device never sees a rule), so a host-side
		# `Adapt.adapt(Array, line)` or any future non-kernel adaptor also sees
		# the realised `inner` only, the wrapper and its rule dropped. Inert
		# today -- no in-repo caller adapts an element tuple with another
		# adaptor, and `LossRecord` (src/elements/aperture.jl) sets the same
		# precedent, dropping its names under any adaptor; a structure-
		# preserving generic method with the drop restricted to the kernel
		# adaptor is an owner item (2026-10-13 neighbour audit, U3-2;
		# docs/todo.md).
		#
		# Defined whenever Adapt loads (a hard dependency, imported in
		# src/beam/Beam.jl) rather than inside the CUDA block below, so a
		# CPU-only machine and the suite's wrapper-walk tripwire see exactly the
		# methods the launch reaches.
		Adapt.adapt_structure(to, w::TurnModulated) = Adapt.adapt(to, w.inner)
		Adapt.adapt_structure(to, c::CompositeLine) = CompositeLine(Adapt.adapt(to, c.ops))
		Adapt.adapt_structure(to, e::MisalignedElement) =
			MisalignedElement(Adapt.adapt(to, e.inner), e.qin, e.oin, e.qout, e.oout)
		Adapt.adapt_structure(to, e::RefTilted) = RefTilted(Adapt.adapt(to, e.inner), e.c, e.s)
		Adapt.adapt_structure(to, e::ParticleLinear6D) = _adapt_particle_linear6d(to, e)
	end
end

if _HAS_CUDA
	@eval begin
		const _CUDA_FUSED_OCCUPANCY_CACHE = Dict{Any,Int}()
		const _CUDA_FUSED_OCCUPANCY_LOCK = ReentrantLock()

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
					@inbounds rep[index] = fusedTrack(turn_ctx, elems,
				                                  turn_ctx.index_offset + index,
				                                  rep[index]...)
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
					_track_cuda_elementwise!(rep, elem, policy, ctx, stream)
				else
					push!(fused, elem)
				end
			end
			_flush_cuda_policy_segment!(rep, fused, policy, ctx, stream)
			return nothing
		end

		# A single element handed to the policy `track!` methods above (not a
		# tuple) that requires the elementwise route: a one-element line. A
		# bare strong beam reaches this only through the context-taking
		# `track!` (its own method is the contextless one); a wrapper holding
		# one reaches it through both, and until fix M (2026-10-18) the
		# contextless form had no method for it at all.
		_track_cuda_policy_elementwise!(rep, elem, policy, ctx, stream) =
			_track_cuda_policy_elementwise!(rep, (elem,), policy, ctx, stream)

		"""
		    _track_cuda_elementwise!(rep, elem, policy, ctx, stream)

		Track the one element the elementwise walker lifted out of a fused
		segment, for one turn, under the turn's `ctx`. Every element that
		answers `_requires_cuda_elementwise(elem, ctx) == true` owns a method:
		the strong beams forward to their own per-element `track!`
		(src/track/strong_beam_track.jl), a `CompositeLine` is walked like the
		nested tuple it is, with the SAME context (re-entering `track!` would
		rebuild one at turn 0 and re-key every turn-dependent member), and a
		frame or turn-modulation wrapper holding a strong beam launches the
		wrapped-strong-beam kernel (`_track_cuda_wrapped_strong_beam!`). The
		fallback throws by name rather than re-entering the policy `track!`,
		which for an element without a per-element method would recurse into
		this walker without end.
		"""
		_track_cuda_elementwise!(rep, elem, policy, ctx, stream) = throw(ArgumentError(
			"$(nameof(typeof(elem))) requires the elementwise CUDA route " *
			"(`_requires_cuda_elementwise`) but owns no `_track_cuda_elementwise!` " *
			"method: every element lifted out of the fused CUDA launch must say how " *
			"it is tracked alone (src/track/phase6d_track.jl)"))
		_track_cuda_elementwise!(rep, c::CompositeLine, policy, ctx, stream) =
			_track_cuda_policy_elementwise!(rep, c.ops, policy, ctx, stream)
		_track_cuda_elementwise!(rep, w::Union{MisalignedElement,RefTilted,TurnModulated},
								 policy, ctx, stream) =
			_track_cuda_wrapped_strong_beam!(rep, w, policy, ctx, stream)

		function track!(rep, elems, turns, policy::ResolvedCUDAExecutionPolicy;
						stream=nothing)
			_reject_task_only_tracking(elems)
			_reject_contextless_tracking(elems)
			if _requires_cuda_elementwise(elems)
				# Build the context ONCE and advance its turn, exactly as the
				# ctx-taking sibling below does. Constructing `TrackingContext()`
				# inside the loop pinned every turn to turn 0, and the counter RNG
				# is keyed on the turn, so a stochastic element replayed one draw
				# for the whole run: 16 turns produced 16x the SAME kick rather
				# than a random walk (2026-08-05_b audit). Measured at 16 turns,
				# 20,000 particles, damping off:
				#
				#            var(16)/var(1)   corr(x16,x1)   max|x16 - 16*x1|
				#   CPU          15.60           0.00048         9.76e-8
				#   CUDA (pre)  256.00 = 16^2    1.0             2.6e-23
				#
				# i.e. the excitation was perfectly coherent and its variance too
				# large by a factor of `turns`. The CPU sibling never had this: its
				# contextless path calls the context-free `fusedTrack`, which drew
				# from a stateful RNG, so its turns differed by construction --
				# and since the 2026-10-18 audit (F-95) refuses an excitation draw
				# without a context outright, damping alone staying deterministic.
				base_ctx = TrackingContext()
				for turn in 1:turns
					turn_ctx = with_turn(base_ctx, base_ctx.turn + Int64(turn - 1))
					_track_cuda_policy_elementwise!(rep, elems, policy, turn_ctx, stream)
				end
			else
				_cuda_launch_track_policy!(rep, elems, turns, policy, nothing; stream=stream)
			end
			return nothing
		end

		function track!(rep, elems, turns, policy::ResolvedCUDAExecutionPolicy,
						ctx::TrackingContext; stream=nothing)
			_reject_task_only_tracking(elems)
			return _track_admitted!(rep, elems, turns, policy, ctx; stream=stream)
		end

		function _track_admitted!(rep, elems, turns, policy::ResolvedCUDAExecutionPolicy,
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
