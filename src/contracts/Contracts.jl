export ContractResult, passed, validate,
       TrackingBackendConsistencyContract

"""
    ContractResult(passed, message; residual=nothing, metrics=Dict())
    ContractResult(status, message; residual=nothing, metrics=Dict())

Result returned by physics-contract validation.

`status` is normally `:passed`, `:failed`, or `:skipped`. `residual` is an
optional scalar error norm, and `metrics` holds contract-specific diagnostics.
"""
struct ContractResult
    passed::Bool
    status::Symbol
    message::String
    residual::Union{Nothing,Float64}
    metrics::Dict{Symbol,Any}
end
ContractResult(passed::Bool, message::AbstractString; residual=nothing,
               metrics=Dict{Symbol,Any}()) =
    ContractResult(passed, passed ? :passed : :failed, String(message),
                   residual === nothing ? nothing : Float64(residual),
                   Dict{Symbol,Any}(metrics))
ContractResult(status::Symbol, message::AbstractString; residual=nothing,
               metrics=Dict{Symbol,Any}()) =
    ContractResult(status == :passed, status, String(message),
                   residual === nothing ? nothing : Float64(residual),
                   Dict{Symbol,Any}(metrics))

"""Return `true` when a `ContractResult` passed."""
passed(result::ContractResult) = result.passed

"""
    TrackingBackendConsistencyContract(; line, initial_rep=nothing,
        n_particles=1024, turns=1, backend_a=CPUThreadsBackend,
        backend_b=CPUThreadsBackend, seed=123456789, rng_method=:philox,
        atol=1e-10, rtol=1e-10)

Validate that the same tracking line produces consistent coordinates on two
execution backends. The contract constructs identical initial phase-space
coordinates, snapshots the same Octopus global RNG state, executes a
`TrackingTask` on each backend, and compares all six coordinates.

Use `backend_b=CUDABackend` for a CPU/CUDA check. If CUDA is unavailable to
Julia, validation returns `status == :skipped` instead of failing.

When both backends are `CPUThreadsBackend`, this is a same-process deterministic
repeatability check. Exact zero coordinate error is expected for the current
elementwise fused path because particles do not share reductions and stochastic
samples are keyed by particle index, turn, seed, and `rng_id`.
"""
Base.@kwdef struct TrackingBackendConsistencyContract <: AbstractPhysicsContract
    line
    initial_rep = nothing
    n_particles::Int = 1024
    turns::Int = 1
    backend_a::DataType = CPUThreadsBackend
    backend_b::DataType = CPUThreadsBackend
    seed::UInt64 = UInt64(123456789)
    rng_method::Symbol = :philox
    atol::Float64 = 1e-10
    rtol::Float64 = 1e-10
end

"""
    validate(contract, args...; kwargs...)

Run a physics contract against the supplied objects. Concrete contracts should
extend this method and return `ContractResult`.
"""
function validate(contract::AbstractPhysicsContract, args...; kwargs...)
    return ContractResult(false,
        "No validation implementation registered for $(nameof(typeof(contract))).")
end

description(::Type{TrackingBackendConsistencyContract}) =
    "Checks coordinate consistency for the same tracking line across two execution backends."

function validate(contract::TrackingBackendConsistencyContract; kwargs...)
    available, reason = _contract_backends_available(contract.backend_a, contract.backend_b)
    if !available
        return ContractResult(:skipped, reason; metrics=Dict(
            :backend_a => nameof(contract.backend_a),
            :backend_b => nameof(contract.backend_b),
        ))
    end

    base = contract.initial_rep === nothing ?
        _contract_default_initial_rep(contract.n_particles, Float64) :
        contract.initial_rep
    rep_a = _contract_rep_for_backend(base, contract.backend_a)
    rep_b = _contract_rep_for_backend(base, contract.backend_b)

    old_seed = global_rng_seed()
    old_method = global_rng_method()
    try
        set_global_rng!(seed=contract.seed, method=contract.rng_method)
        execute!(TrackingTask(contract.line; policy=_contract_policy(contract.backend_a)),
                 rep_a; turns=contract.turns)
        set_global_rng!(seed=contract.seed, method=contract.rng_method)
        execute!(TrackingTask(contract.line; policy=_contract_policy(contract.backend_b)),
                 rep_b; turns=contract.turns)
    finally
        set_global_rng!(seed=old_seed, method=old_method)
    end

    metrics = _contract_coordinate_metrics(rep_a, rep_b, contract.atol, contract.rtol)
    metrics[:backend_a] = nameof(contract.backend_a)
    metrics[:backend_b] = nameof(contract.backend_b)
    metrics[:cpu_threads] = Threads.nthreads()
    metrics[:turns] = contract.turns
    metrics[:n_particles] = length(rep_a)
    metrics[:seed] = contract.seed
    metrics[:rng_method] = contract.rng_method

    ok = Bool(metrics[:passed_tolerance])
    message = ok ?
        "Tracking backends agree within tolerance." :
        "Tracking backends disagree beyond tolerance."
    return ContractResult(ok, message; residual=metrics[:max_abs_error], metrics=metrics)
end

function _contract_backends_available(backends::DataType...)
    for backend in backends
        backend === CPUThreadsBackend && continue
        if backend === CUDABackend
            if !(isdefined(@__MODULE__, :_HAS_CUDA) && _HAS_CUDA)
                return false, "CUDA backend requested, but CUDA.jl is not loaded."
            end
            functional = try
                CUDA.functional(false)
            catch err
                false
            end
            functional || return false, "CUDA backend requested, but no functional CUDA device is visible to Julia."
            continue
        end
        return false, "Unsupported backend $(backend)."
    end
    return true, ""
end

_contract_policy(::Type{CPUThreadsBackend}) = CPUThreadsExecutionPolicy()
_contract_policy(::Type{CUDABackend}) = GPUExecutionPolicy()

function _contract_default_initial_rep(N::Integer, ::Type{T}=Float64) where {T}
    n = Int(N)
    s(i, scale, phase=0) = T(scale) * sin(T(0.017) * T(i) + T(phase))
    c(i, scale, phase=0) = T(scale) * cos(T(0.013) * T(i) + T(phase))
    return Phase6DRep(
        [s(i, 1.0e-4) for i in 1:n],
        [c(i, 2.0e-5, 0.1) for i in 1:n],
        [s(i, 8.0e-5, 0.2) for i in 1:n],
        [c(i, 1.5e-5, 0.3) for i in 1:n],
        [s(i, 1.0e-2, 0.4) for i in 1:n],
        [c(i, 5.0e-4, 0.5) for i in 1:n],
    )
end

function _contract_rep_for_backend(rep, ::Type{CPUThreadsBackend})
    return Phase6DRep((_contract_host_copy(a) for a in coordinate_arrays(rep))...)
end

function _contract_rep_for_backend(rep, ::Type{CUDABackend})
    _HAS_CUDA || error("CUDABackend requires CUDA.jl to be available.")
    return Phase6DRep((CUDA.CuArray(_contract_host_copy(a)) for a in coordinate_arrays(rep))...)
end

_contract_host_copy(a::AbstractArray) = copy(Array(a))

function _contract_coordinate_metrics(rep_a, rep_b, atol, rtol)
    arrays_a = coordinate_arrays(rep_a)
    arrays_b = coordinate_arrays(rep_b)
    max_abs = 0.0
    max_scale = 0.0
    max_component_rel = 0.0
    max_allowed_ratio = 0.0
    for dim in 1:6
        a = Array(arrays_a[dim])
        b = Array(arrays_b[dim])
        length(a) == length(b) || throw(ArgumentError("coordinate length mismatch in dimension $dim"))
        for i in eachindex(a)
            av = Float64(a[i])
            bv = Float64(b[i])
            diff = abs(av - bv)
            scale = max(abs(av), abs(bv))
            allowed = Float64(atol) + Float64(rtol) * scale
            max_abs = max(max_abs, diff)
            max_scale = max(max_scale, scale)
            max_component_rel = max(max_component_rel, diff / max(scale, eps(Float64)))
            max_allowed_ratio = max(max_allowed_ratio, diff / max(allowed, eps(Float64)))
        end
    end
    global_rel = max_abs / max(max_scale, eps(Float64))
    return Dict{Symbol,Any}(
        :max_abs_error => max_abs,
        :global_rel_error => global_rel,
        :max_component_rel_error => max_component_rel,
        :max_allowed_ratio => max_allowed_ratio,
        :atol => Float64(atol),
        :rtol => Float64(rtol),
        :passed_tolerance => max_allowed_ratio <= 1.0,
    )
end
