export BeamParams, Phase6DRep, Beam,
       coordinate_arrays, coordinate_array, add_offset!, beam_statistics,
       write_beam_coordinates,
       read_beam_coordinates

using Random

const _HAS_CUDA = try
	@eval import CUDA
	true
catch
	false
end

const _HAS_ADAPT = try
	@eval import Adapt
	true
catch
	false
end

"""
    BeamParams(; charge, mc2, E0, r0, npart)

Physical beam parameters. Energies are in eV, `charge` is in units of electron
charge, and `npart` is the represented particle count.
"""
@kwdef struct BeamParams{FloatT}
	charge::FloatT = zero(FloatT) # in unit of electron charge e
	mc2::FloatT = zero(FloatT) # rest mass mc^2 in unit of eV
	E0::FloatT = zero(FloatT) # in unit of eV
	r0::FloatT = zero(FloatT) # classical radius
	npart::FloatT = zero(FloatT) # number of particles
end

"""
    Phase6DRep(x, px, y, py, z, pz)

Structure-of-arrays six-dimensional phase-space representation. Indexing a
`Phase6DRep` returns one particle as `(x, px, y, py, z, pz)`. All six arrays
must have equal lengths. Empty representations are allowed for storage and I/O,
but operations such as longitudinal slicing may require at least one particle.
"""
struct Phase6DRep{FloatArray} <: AbstractPhaseRep
	x::FloatArray; px::FloatArray
	y::FloatArray; py::FloatArray
	z::FloatArray; pz::FloatArray
	function Phase6DRep(x::A, px::A, y::A, py::A, z::A, pz::A) where {A}
		lengths = map(length, (x, px, y, py, z, pz))
		all(==(first(lengths)), lengths) || throw(ArgumentError(
			"Phase6DRep coordinate arrays must have equal lengths; got $(lengths)"))
		return new{A}(x, px, y, py, z, pz)
	end
end

if _HAS_ADAPT
	@eval Adapt.@adapt_structure Phase6DRep
end

"""Allocate `N` normally distributed random coordinates on the requested backend."""
function _alloc_randn(::Type{CUDABackend}, T, N; cutoff=Inf, rng=nothing)
	_HAS_CUDA || error("CUDABackend requires CUDA.jl to be available.")
	rng = rng === nothing ? CUDA.default_rng() : rng
	values = Random.randn(rng, T, N)
	if !(values isa CUDA.CuArray)
		values = CUDA.CuArray(values)
	end
	if isfinite(cutoff)
		c = T(cutoff)
		# GPU initialization keeps allocation vectorized. Clipping is a practical
		# bounded-Gaussian default and the coordinates are standardized below.
		values = clamp.(values, -c, c)
	end
	return values
end

function _alloc_randn(::Type{CPUThreadsBackend}, T, N; cutoff=Inf, rng=nothing)
	rng = rng === nothing ? Random.default_rng() : rng
	if isfinite(cutoff)
		c = T(cutoff)
		out = Vector{T}(undef, N)
		for i in eachindex(out)
			x = randn(rng, T)
			while abs(x) > c
				x = randn(rng, T)
			end
			out[i] = x
		end
		return out
	end
	return randn(rng, T, N)
end

function _default_rng(::Type{CPUThreadsBackend})
	return Random.default_rng()
end

function _default_rng(::Type{CUDABackend})
	_HAS_CUDA || error("CUDABackend requires CUDA.jl to be available.")
	return CUDA.default_rng()
end

function _rng_from_seed(::Type{CPUThreadsBackend}, seed)
	return Random.MersenneTwister(seed)
end

function _rng_from_seed(::Type{CUDABackend}, seed)
	rng = _default_rng(CUDABackend)
	Random.seed!(rng, seed)
	return rng
end

function _resolve_rng(::Type{BTAG}, rng, seed, rng_id) where {BTAG<:AbstractExecutionBackend}
	if rng !== nothing
		seed !== nothing && @warn "Beam seed keyword is ignored because an explicit rng was provided." seed
		rng_id != 0 && @warn "Beam rng_id is ignored because an explicit rng was provided." rng_id
		return rng
	end
	seed !== nothing && @warn "Beam seed keyword is deprecated for Octopus counter RNG; use set_global_rng!(seed=...) instead." seed
	return nothing
end

function _alloc_counter_randn(::Type{CPUThreadsBackend}, T, N, dim::Integer;
                              cutoff=Inf, seed::Integer=global_rng_seed(),
                              rng_method=global_rng_method_code(),
                              rng_id::Integer=0)
	out = Vector{T}(undef, Int(N))
	for i in eachindex(out)
		x = octopus_normal(seed, rng_method, 0, rng_id, i, dim, T)
		out[i] = isfinite(cutoff) ? clamp(x, -T(cutoff), T(cutoff)) : x
	end
	return out
end

function _alloc_counter_randn(::Type{CUDABackend}, T, N, dim::Integer;
                              cutoff=Inf, seed::Integer=global_rng_seed(),
                              rng_method=global_rng_method_code(),
                              rng_id::Integer=0)
	_HAS_CUDA || error("CUDABackend requires CUDA.jl to be available.")
	return CUDA.CuArray(_alloc_counter_randn(CPUThreadsBackend, T, Int(N), dim;
		cutoff=cutoff, seed=seed, rng_method=rng_method, rng_id=rng_id))
end

function _standardize!(values)
	N = length(values)
	μ = sum(values) / N
	values .-= μ
	σ2 = sum(abs2, values) / N
	σ = sqrt(max(σ2, zero(σ2)))
	if σ == 0
		values .= zero(eltype(values))
	else
		values ./= σ
	end
	return values
end

function _standard_gaussian_rep(::Type{BTAG}, ::Type{T}, N::Integer;
                                cutoff=5, rng=nothing, seed=nothing,
                                rng_id::Integer=0) where {BTAG<:AbstractExecutionBackend,T<:Real}
	resolved_rng = _resolve_rng(BTAG, rng, seed, rng_id)
	if resolved_rng === nothing
		counter_seed = seed === nothing ? global_rng_seed() : UInt64(seed)
		counter_method = global_rng_method_code()
		counter_rng_id = rng_id == 0 ? next_rng_id!() : UInt64(rng_id)
		coords = ntuple(i -> begin
			_standardize!(_alloc_counter_randn(BTAG, T, Int(N), i;
				cutoff=cutoff, seed=counter_seed, rng_method=counter_method,
				rng_id=counter_rng_id))
		end, 6)
		return Phase6DRep(coords...)
	end
	coords = ntuple(i -> begin
		_standardize!(_alloc_randn(BTAG, T, Int(N); cutoff=cutoff, rng=resolved_rng))
	end, 6)
	return Phase6DRep(coords...)
end

@inline function Base.getindex(rep::Phase6DRep, index)
	return rep.x[index],rep.px[index],rep.y[index],rep.py[index],rep.z[index],rep.pz[index]
end
@inline function Base.setindex!(rep::Phase6DRep, coord, index)
	rep.x[index],rep.px[index],rep.y[index],rep.py[index],rep.z[index],rep.pz[index] = coord
	return nothing
end

@inline Base.length(rep::Phase6DRep) = length(rep.x)
@inline Base.keys(rep::Phase6DRep) = Base.OneTo(length(rep))
@inline Base.firstindex(rep::Phase6DRep) = 1
@inline Base.lastindex(rep::Phase6DRep) = length(rep)

"""Return the six coordinate arrays as `(x, px, y, py, z, pz)`."""
coordinate_arrays(rep::Phase6DRep) = (rep.x, rep.px, rep.y, rep.py, rep.z, rep.pz)

"""Return coordinate array `dim`, where `dim` is 1-based: `1=>x`, ..., `6=>pz`."""
coordinate_array(rep::Phase6DRep, dim::Integer) = coordinate_arrays(rep)[Int(dim)]

function _infer_backend(rep::Phase6DRep)
	if _HAS_CUDA && rep.x isa CUDA.CuArray
		all(array -> array isa CUDA.CuArray, coordinate_arrays(rep)) || throw(ArgumentError(
			"all Phase6DRep coordinate arrays must use the same CPU or CUDA storage backend"))
		return CUDABackend
	end
	any(array -> _HAS_CUDA && array isa CUDA.CuArray, coordinate_arrays(rep)) &&
		throw(ArgumentError(
			"all Phase6DRep coordinate arrays must use the same CPU or CUDA storage backend"))
	return CPUThreadsBackend
end

function _cuda_storage_device(rep::Phase6DRep)
	_HAS_CUDA || error("CUDA storage requires CUDA.jl to be available.")
	_infer_backend(rep) === CUDABackend || throw(ArgumentError("particle storage is not CUDA storage"))
	devices = map(array -> CUDA.deviceid(CUDA.device(array)), coordinate_arrays(rep))
	all(==(first(devices)), devices) || throw(ArgumentError(
		"all Phase6DRep CUDA arrays must reside on the same device; got $(devices)"))
	return first(devices)
end

function _resolve_execution_policy(policy::Union{Nothing,AbstractExecutionPolicy}, rep::Phase6DRep)
	backend = _infer_backend(rep)
	if policy === nothing
		policy = backend === CPUThreadsBackend ? CPUThreadsExecutionPolicy() : CUDAExecutionPolicy()
	elseif policy isa PlaceholderPolicy
		backend_type(policy) # raises the public, specific error
	end
	requested = backend_type(policy)
	requested === backend || throw(ArgumentError(
		"execution policy requests $(requested), but particle storage requires $(backend); " *
		"policies never migrate storage"))
	if policy isa CPUThreadsExecutionPolicy
		return ResolvedCPUExecutionPolicy(_resolved_cpu_threads(policy))
	end
	cuda_policy = policy isa GPUExecutionPolicy ? _legacy_cuda_policy(policy) : policy
	cuda_policy isa CUDAExecutionPolicy || throw(ArgumentError(
		"unsupported execution policy $(typeof(policy))"))
	device = _cuda_storage_device(rep)
	cuda_policy.device === nothing || cuda_policy.device == device || throw(ArgumentError(
		"CUDA policy requests device $(cuda_policy.device), but particle storage is on device $(device)"))
	dev = CUDA.CuDevice(device)
	max_threads = CUDA.attribute(dev, CUDA.DEVICE_ATTRIBUTE_MAX_THREADS_PER_BLOCK)
	cuda_policy.launch.threads <= max_threads || throw(ArgumentError(
		"CUDA threads $(cuda_policy.launch.threads) exceed device $(device) maximum $(max_threads)"))
	return ResolvedCUDAExecutionPolicy(device, cuda_policy.launch.threads, cuda_policy.launch.blocks)
end

function _activate_resolved_policy!(policy::ResolvedCPUExecutionPolicy)
	return policy
end

function _activate_resolved_policy!(policy::ResolvedCUDAExecutionPolicy)
	_HAS_CUDA || error("CUDA execution requires CUDA.jl to be available.")
	CUDA.device!(policy.device)
	_record_execution!(:cuda_device, CUDABackend, (device=policy.device,))
	return policy
end

function _with_execution_policy(f::F, policy::AbstractResolvedExecutionPolicy) where {F}
	_activate_resolved_policy!(policy)
	return _with_resolved_policy(f, policy)
end

function configuration_report(policy::AbstractExecutionPolicy, rep::Phase6DRep)
	resolved = _resolve_execution_policy(policy, rep)
	if resolved isa ResolvedCPUExecutionPolicy
		return (ConfigurationEntry(:threads,
			policy isa CPUThreadsExecutionPolicy ? policy.threads : resolved.threads,
			resolved.threads, :resolved, "validated for CPU storage",
			:cpu_logical_workers),)
	end
	requested = policy isa GPUExecutionPolicy ? _legacy_cuda_policy(policy) : policy
	status = policy isa GPUExecutionPolicy ? :deprecated : :resolved
	reason_suffix = policy isa GPUExecutionPolicy ? " through deprecated compatibility adapter" : ""
	return (
		ConfigurationEntry(:device, requested.device, resolved.device, status,
			"validated against CUDA particle storage" * reason_suffix, :cuda_device),
		ConfigurationEntry(:threads, requested.launch.threads, resolved.threads, status,
			"validated against the CUDA device limit" * reason_suffix, :cuda_fused_launch),
		ConfigurationEntry(:blocks, requested.launch.blocks, resolved.blocks,
			policy isa GPUExecutionPolicy ? :deprecated :
			resolved.blocks === :auto ? :unresolved : :resolved,
			resolved.blocks === :auto ? "resolved per compiled kernel and particle count" :
			                            "explicit CUDA block count" * reason_suffix,
			:cuda_fused_launch),
	)
end

"""
    Beam

Runtime beam container pairing physical `BeamParams` with a phase-space
representation and an execution backend tag.
"""
struct Beam{BTAG <: AbstractExecutionBackend, BPAR <: BeamParams, REP<:AbstractPhaseRep}
	params::BPAR
	rep::REP
end

coordinate_arrays(beam::Beam) = coordinate_arrays(beam.rep)
coordinate_array(beam::Beam, dim::Integer) = coordinate_array(beam.rep, dim)

"""
    Beam(N, policy_or_backend, FloatT=Float64; beta, alpha=(0,0,0), sigma=nothing,
         emit=nothing, rng=..., zeta=zeros(...), eta=zeros(...),
         coupling=zeros(...), initial_offset=zeros(...))

Construct a beam with randomized six-dimensional coordinates on either the CPU
threaded backend or CUDA backend:

1. generate standardized Gaussian coordinates,
2. normalize by Twiss/sigma or Twiss/emittance parameters,
3. apply optional `XYCoupling`, `MomentumDispersion`, and `CrabDispersion`,
4. apply an optional six-coordinate `initial_offset`.

`N` must be positive. Construct `Phase6DRep` directly when an empty
representation is needed.

`beta=(βx,βy,βz)` and `alpha=(αx,αy,αz)` use the same three-plane Twiss
convention as `Linear6DSpec` and `LumpedRadSpec`. For sigma-based construction,
the longitudinal covariance is `cov(z,pz) = -αz*σz^2/βz`. A legacy
two-component `alpha=(αx,αy)` is accepted temporarily and interpreted as
`(αx,αy,0)`.

`policy_or_backend` may be `CPUThreadsExecutionPolicy()`,
`CUDAExecutionPolicy()`, a deprecated `GPUExecutionPolicy()`,
`CPUThreadsBackend`, or `CUDABackend`.
If `rng` is omitted, coordinates are generated with the Octopus global counter
RNG using `global_rng_seed()`, `global_rng_method()`, and the beam `rng_id`.
If `rng_id == 0`, a stream id is assigned with `next_rng_id!()`. Passing an
explicit `rng` uses that RNG as a convenience override and ignores `rng_id`.
"""
function Beam(N::Integer, policy::AbstractExecutionPolicy, FloatT::Type{RT}=Float64; kwargs...) where {RT<:Real}
	activate_policy!(policy)
	return Beam(Int(N), backend_type(policy), RT; execution_policy=policy, kwargs...)
end

function Beam(N::Integer, backend::Type{BTAG}, FloatT::Type{RT}=Float64;
              beta=(one(RT), one(RT), one(RT)),
              alpha=(zero(RT), zero(RT), zero(RT)),
              sigma=nothing,
              emit=nothing,
              zeta=zeros(RT, 4),
              eta=zeros(RT, 4),
              coupling=zeros(RT, 4),
              R=nothing,
              C=nothing,
              mode::XYCouplingMode=XY_MODEA,
              cutoff=5,
              rng=nothing,
              seed=nothing,
              rng_id=0,
              initial_offset=zeros(RT, 6),
              execution_policy::Union{Nothing,AbstractExecutionPolicy}=nothing,
              kwargs...) where {BTAG<:AbstractExecutionBackend,RT<:Real}
	N > 0 || throw(ArgumentError("random Beam construction requires a positive particle count; got $(N)"))
	params = _beam_params(RT, Int(N); kwargs...)
	rep = _standard_gaussian_rep(BTAG, RT, Int(N);
		cutoff=cutoff, rng=rng, seed=seed, rng_id=rng_id)
	α = _beam_alpha(alpha, RT)
	if emit === nothing
		σ = sigma === nothing ? ntuple(_ -> one(RT), 3) : _tuple_typed(sigma, 3, RT)
		_normalize_sigma!(rep, _tuple_typed(beta, 3, RT), α, σ)
	else
		_normalize_emit!(rep, _tuple_typed(beta, 3, RT), α, _tuple_typed(emit, 3, RT))
	end
	coupling_values = C === nothing ? (R === nothing ? coupling : R) : C
	_apply_initial_maps!(rep, BTAG, RT;
		coupling=_tuple_typed(coupling_values, 4, RT),
		eta=_tuple_typed(eta, 4, RT),
		zeta=_tuple_typed(zeta, 4, RT),
		mode=mode,
		policy=execution_policy,
	)
	add_offset!(rep, _tuple_typed(initial_offset, 6, RT))
	return Beam{BTAG, typeof(params), typeof(rep)}(params, rep)
end

function _beam_alpha(alpha, ::Type{T}) where {T}
	if length(alpha) == 2
		Base.depwarn("two-component Beam alpha is deprecated; pass (alpha_x, alpha_y, alpha_z)", :Beam)
		return (T(alpha[1]), T(alpha[2]), zero(T))
	end
	return _tuple_typed(alpha, 3, T)
end

function _beam_params(::Type{T}, N::Int; kwargs...) where {T}
	allowed = (:charge, :mc2, :E0, :r0, :npart)
	unknown = setdiff(Tuple(keys(kwargs)), allowed)
	isempty(unknown) || throw(ArgumentError(
		"unknown Beam keyword(s): $(join(string.(unknown), ", ")). " *
		"Beam-parameter keywords are $(join(string.(allowed), ", "))."))
	return BeamParams{T}(;
		charge=T(get(kwargs, :charge, 0)),
		mc2=T(get(kwargs, :mc2, 0)),
		E0=T(get(kwargs, :E0, 0)),
		r0=T(get(kwargs, :r0, 0)),
		npart=T(get(kwargs, :npart, N)),
	)
end

function _tuple_typed(values, n::Int, ::Type{T}) where {T}
	length(values) == n || throw(ArgumentError("expected $n values, got $(length(values))"))
	return ntuple(i -> T(values[i]), n)
end

function _normalize_sigma!(rep::Phase6DRep, beta, alpha, sigma)
	rep.px .= (sigma[1] / beta[1]) .* (rep.px .- alpha[1] .* rep.x)
	rep.x .*= sigma[1]
	rep.py .= (sigma[2] / beta[2]) .* (rep.py .- alpha[2] .* rep.y)
	rep.y .*= sigma[2]
	rep.pz .= (sigma[3] / beta[3]) .* (rep.pz .- alpha[3] .* rep.z)
	rep.z .*= sigma[3]
	return rep
end

function _normalize_emit!(rep::Phase6DRep, beta, alpha, emit)
	sigma = ntuple(i -> sqrt(beta[i] * emit[i]), 3)
	rep.px .= (sigma[1] / beta[1]) .* (rep.px .- alpha[1] .* rep.x)
	rep.x .*= sigma[1]
	rep.py .= (sigma[2] / beta[2]) .* (rep.py .- alpha[2] .* rep.y)
	rep.y .*= sigma[2]
	rep.pz .= (sigma[3] / beta[3]) .* (rep.pz .- alpha[3] .* rep.z)
	rep.z .*= sigma[3]
	return rep
end

function _apply_initial_maps!(rep::Phase6DRep, backend::Type{BTAG}, ::Type{T};
                              coupling, eta, zeta, mode,
                              policy=nothing) where {BTAG<:AbstractExecutionBackend,T}
	if any(!iszero, coupling)
		policy === nothing ?
			track!(rep, XYCoupling(Symplectic6DMap(), coupling..., mode), 1, backend) :
			track!(rep, XYCoupling(Symplectic6DMap(), coupling..., mode), 1; policy=policy)
	end
	if any(!iszero, eta)
		policy === nothing ?
			track!(rep, MomentumDispersion(Symplectic6DMap(), eta...), 1, backend) :
			track!(rep, MomentumDispersion(Symplectic6DMap(), eta...), 1; policy=policy)
	end
	if any(!iszero, zeta)
		policy === nothing ?
			track!(rep, CrabDispersion(Symplectic6DMap(), zeta...), 1, backend) :
			track!(rep, CrabDispersion(Symplectic6DMap(), zeta...), 1; policy=policy)
	end
	return rep
end

"""
    add_offset!(rep_or_beam, offsets)

Add six coordinate offsets in place.
"""
function add_offset!(rep::Phase6DRep, offsets)
	offs = _tuple_typed(offsets, 6, eltype(rep.x))
	for (coord, offset) in zip(coordinate_arrays(rep), offs)
		coord .+= offset
	end
	return rep
end
add_offset!(beam::Beam, offsets) = (add_offset!(beam.rep, offsets); beam)

function _host_array(v)
	_HAS_CUDA && v isa CUDA.CuArray && return Array(v)
	return v
end

function _host_coordinate_arrays(rep::Phase6DRep)
	return map(_host_array, coordinate_arrays(rep))
end

_mean(v) = sum(v) / length(v)
function _variance(v, μ)
	return sum(x -> (x - μ) * (x - μ), v) / length(v)
end
function _covariance(a, μa, b, μb)
	return sum(((x, y),) -> (x - μa) * (y - μb), zip(a, b)) / length(a)
end
function _fourth_central(v, μ)
	return sum(x -> (x - μ)^4, v) / length(v)
end

"""
    beam_statistics(rep_or_beam; diagonal_fourth=false)

Return named beam statistics for a `Phase6DRep` or `Beam`. This is the single
public statistics entry point and works for both CPU and CUDA coordinate
storage. CUDA arrays are copied to host for the reduction in the current
implementation.

The return value contains:

- `labels`: `(:x, :px, :y, :py, :z, :pz)`
- `n`: number of particles
- `mean`: six coordinate means
- `covariance`: full 6x6 covariance matrix
- `rms`: square root of the covariance diagonal
- `emittance`: three rms emittances for `(x,px)`, `(y,py)`, `(z,pz)`
- `xz_covariance`, `yz_covariance`
- `diagonal_fourth_central`: six fourth central moments, or `nothing`
"""
function beam_statistics(rep::Phase6DRep; diagonal_fourth::Bool=false)
	coords = _host_coordinate_arrays(rep)
	T = promote_type(map(eltype, coords)...)
	means = collect(T, map(_mean, coords))
	cov = Matrix{T}(undef, 6, 6)
	for i in 1:6, j in 1:6
		cov[i, j] = _covariance(coords[i], means[i], coords[j], means[j])
	end
	rms = [sqrt(max(cov[i, i], zero(T))) for i in 1:6]
	emit = Vector{T}(undef, 3)
	for plane in 0:2
		i = 2plane + 1
		j = i + 1
		emit[plane + 1] = sqrt(max(cov[i, i] * cov[j, j] - cov[i, j] * cov[j, i], zero(T)))
	end
	fourth = diagonal_fourth ? [_fourth_central(coords[i], means[i]) for i in 1:6] : nothing
	return (
		labels = (:x, :px, :y, :py, :z, :pz),
		n = length(rep),
		mean = means,
		covariance = cov,
		rms = rms,
		emittance = emit,
		xz_covariance = cov[1, 5],
		yz_covariance = cov[3, 5],
		diagonal_fourth_central = fourth,
	)
end
beam_statistics(beam::Beam; kwargs...) = beam_statistics(beam.rep; kwargs...)

"""
    write_beam_coordinates(io_or_path, rep_or_beam; npart=length(rep))

Write the Octopus compact coordinate record format: `UInt32(npart)` followed
by six contiguous `Float64` coordinate arrays.
"""
function write_beam_coordinates(io::IO, rep::Phase6DRep; npart=length(rep))
	n = min(Int(npart), length(rep))
	write(io, UInt32(n))
	for coord in _host_coordinate_arrays(rep)
		write(io, Float64.(view(coord, 1:n)))
	end
	return n
end
write_beam_coordinates(io::IO, beam::Beam; npart=length(beam.rep)) =
	write_beam_coordinates(io, beam.rep; npart=npart)
function write_beam_coordinates(path::AbstractString, rep_or_beam; npart=length(rep_or_beam isa Beam ? rep_or_beam.rep : rep_or_beam), append=true)
	open(path, append ? "a" : "w") do io
		write_beam_coordinates(io, rep_or_beam; npart=npart)
	end
end

"""
    read_beam_coordinates(path; record=0, FloatT=Float64)

Read one Octopus compact coordinate record into a `Phase6DRep`.
"""
function read_beam_coordinates(path::AbstractString; record::Integer=0, FloatT=Float64)
	open(path, "r") do io
		return read_beam_coordinates(io; record=record, FloatT=FloatT)
	end
end
function read_beam_coordinates(io::IO; record::Integer=0, FloatT=Float64)
	for _ in 1:Int(record)
		n = Int(read(io, UInt32))
		skip(io, 6 * n * sizeof(Float64))
	end
	n = Int(read(io, UInt32))
	coords = ntuple(_ -> FloatT.(read!(io, Vector{Float64}(undef, n))), 6)
	return Phase6DRep(coords...)
end
