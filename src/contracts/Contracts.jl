export ContractResult, passed, validate,
       ElementTrackingBackendConsistencyContract,
       StrongStrongPICBackendConsistencyContract

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
    ElementTrackingBackendConsistencyContract(; line, initial_rep=nothing,
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
Base.@kwdef struct ElementTrackingBackendConsistencyContract <: AbstractBackendConsistencyContract
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
    StrongStrongPICBackendConsistencyContract(; n_particles=1024, turns=2,
        grid=(32, 32), nslices=3, green_cache=:slice_pair,
        slice_pair_green_min_ratio=0.50, slice_pair_green_growth=0.25,
        batch_mode=:wavefront, seed=123456789, atol=1e-10, rtol=1e-10,
        luminosity_rtol=1e-10)

Validate CPU/CUDA consistency for a live-beam strong-strong PIC collision.
The contract constructs identical electron/proton beams, executes matching
`StrongStrongTask`s, compares both final six-dimensional beam states and
luminosity, and—when `green_cache=:slice_pair`—requires identical cache
hit/miss/rebuild histories with at least one reuse.

If CUDA is unavailable, validation returns `status=:skipped`.
"""
Base.@kwdef struct StrongStrongPICBackendConsistencyContract <: AbstractBackendConsistencyContract
    n_particles::Int = 1024
    turns::Int = 2
    grid::Tuple{Int,Int} = (32, 32)
    nslices::Int = 3
    green_cache::Symbol = :slice_pair
    slice_pair_green_min_ratio::Float64 = 0.50
    slice_pair_green_growth::Float64 = 0.25
    batch_mode::Symbol = :wavefront
    seed::UInt64 = UInt64(123456789)
    atol::Float64 = 1e-10
    rtol::Float64 = 1e-10
    luminosity_rtol::Float64 = 1e-10
end

"""
    validate(contract, args...; kwargs...)

Run a validation contract against the supplied objects. Concrete contracts should
extend this method and return `ContractResult`.
"""
function validate(contract::AbstractContract, args...; kwargs...)
    return ContractResult(false,
        "No validation implementation registered for $(nameof(typeof(contract))).")
end

description(::Type{ElementTrackingBackendConsistencyContract}) =
    "Checks coordinate consistency for the same tracking line across two execution backends."

description(::Type{StrongStrongPICBackendConsistencyContract}) =
    "Checks strong-strong PIC coordinates, luminosity, and cache history across CPU and CUDA."

function validate(contract::ElementTrackingBackendConsistencyContract; kwargs...)
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

function validate(contract::StrongStrongPICBackendConsistencyContract; kwargs...)
    available, reason = _contract_backends_available(CPUThreadsBackend, CUDABackend)
    if !available
        return ContractResult(:skipped, reason; metrics=Dict(
            :backend_a => :CPUThreadsBackend,
            :backend_b => :CUDABackend,
        ))
    end
    contract.n_particles > 0 || return ContractResult(false, "n_particles must be positive.")
    contract.turns > 0 || return ContractResult(false, "turns must be positive.")
    contract.nslices > 0 || return ContractResult(false, "nslices must be positive.")
    if contract.green_cache == :slice_pair && contract.turns < 2
        return ContractResult(false,
            "slice-pair cache consistency requires at least two turns to exercise reuse.")
    end

    old_seed = global_rng_seed()
    old_method = global_rng_method()
    try
        set_global_rng!(seed=contract.seed, method=:philox)
        base1, base2 = _strong_strong_contract_base_beams(contract)
        cpu1 = _strong_strong_contract_beam(base1, CPUThreadsBackend)
        cpu2 = _strong_strong_contract_beam(base2, CPUThreadsBackend)
        gpu1 = _strong_strong_contract_beam(base1, CUDABackend)
        gpu2 = _strong_strong_contract_beam(base2, CUDABackend)

        return mktempdir() do tempdir
            cpu_path = joinpath(tempdir, "cpu.lum")
            gpu_path = joinpath(tempdir, "gpu.lum")
            cpu_task = _strong_strong_contract_task(contract, cpu_path)
            gpu_task = _strong_strong_contract_task(contract, gpu_path)

            execute!(cpu_task, cpu1, cpu2; turns=contract.turns)
            execute!(gpu_task, gpu1, gpu2; turns=contract.turns)
            CUDA.synchronize()

            beam1_metrics = _contract_coordinate_metrics(
                cpu1.rep, gpu1.rep, contract.atol, contract.rtol)
            beam2_metrics = _contract_coordinate_metrics(
                cpu2.rep, gpu2.rep, contract.atol, contract.rtol)
            coordinate_ok = Bool(beam1_metrics[:passed_tolerance]) &&
                            Bool(beam2_metrics[:passed_tolerance])
            max_abs = max(beam1_metrics[:max_abs_error], beam2_metrics[:max_abs_error])
            max_ratio = max(beam1_metrics[:max_allowed_ratio], beam2_metrics[:max_allowed_ratio])
            max_component_rel = max(
                beam1_metrics[:max_component_rel_error],
                beam2_metrics[:max_component_rel_error],
            )

            cpu_luminosity = _strong_strong_contract_last_luminosity(cpu_path)
            gpu_luminosity = _strong_strong_contract_last_luminosity(gpu_path)
            luminosity_rel = abs(gpu_luminosity - cpu_luminosity) /
                             max(abs(cpu_luminosity), eps(Float64))
            luminosity_ok = luminosity_rel <= contract.luminosity_rtol

            cpu_history = _strong_strong_contract_cpu_cache_history(cpu_task)
            gpu_history = _strong_strong_contract_cuda_cache_history(gpu_task)
            cache_history_ok = cpu_history == gpu_history
            cache_reuse_ok = contract.green_cache != :slice_pair || cpu_history[1] > 0

            metrics = Dict{Symbol,Any}(
                :backend_a => :CPUThreadsBackend,
                :backend_b => :CUDABackend,
                :n_particles => contract.n_particles,
                :turns => contract.turns,
                :grid => contract.grid,
                :nslices => contract.nslices,
                :green_cache => contract.green_cache,
                :slice_pair_green_min_ratio => contract.slice_pair_green_min_ratio,
                :slice_pair_green_growth => contract.slice_pair_green_growth,
                :batch_mode => contract.batch_mode,
                :max_abs_error => max_abs,
                :max_allowed_ratio => max_ratio,
                :max_component_rel_error => max_component_rel,
                :coordinate_passed_tolerance => coordinate_ok,
                :cpu_luminosity => cpu_luminosity,
                :gpu_luminosity => gpu_luminosity,
                :luminosity_rel_error => luminosity_rel,
                :luminosity_rtol => contract.luminosity_rtol,
                :luminosity_passed_tolerance => luminosity_ok,
                :cpu_cache_history => cpu_history,
                :gpu_cache_history => gpu_history,
                :cache_histories_match => cache_history_ok,
                :cache_reuse_observed => cache_reuse_ok,
                :cpu_threads => Threads.nthreads(),
            )
            ok = coordinate_ok && luminosity_ok && cache_history_ok && cache_reuse_ok
            message = ok ?
                "Strong-strong PIC CPU and CUDA results agree within tolerance." :
                "Strong-strong PIC CPU and CUDA results disagree or cache histories diverge."
            return ContractResult(ok, message; residual=max_abs, metrics=metrics)
        end
    finally
        set_global_rng!(seed=old_seed, method=old_method)
    end
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

function _strong_strong_contract_base_beams(contract::StrongStrongPICBackendConsistencyContract)
    n = contract.n_particles
    beam1 = Beam(n, CPUThreadsBackend, Float64;
        beta=(0.55, 0.056, 0.7e-2 / 5.5e-4), alpha=(0.0, 0.0),
        sigma=(106e-6, 9.5e-6, 0.7e-2), cutoff=5.0, rng_id=1,
        charge=-1.0, mc2=EMASS_EV, E0=10e9, r0=RE, npart=1.7203e11)
    beam2 = Beam(n, CPUThreadsBackend, Float64;
        beta=(0.8, 0.072, 6e-2 / 6.6e-4), alpha=(0.0, 0.0),
        sigma=(95e-6, 8.5e-6, 6e-2), cutoff=5.0, rng_id=2,
        charge=1.0, mc2=PMASS_EV, E0=275e9,
        r0=RE * ME0 / PMASS_EV, npart=0.6881e11)
    return beam1, beam2
end

function _strong_strong_contract_beam(beam, ::Type{CPUThreadsBackend})
    rep = _contract_rep_for_backend(beam.rep, CPUThreadsBackend)
    return Beam{CPUThreadsBackend,typeof(beam.params),typeof(rep)}(beam.params, rep)
end

function _strong_strong_contract_beam(beam, ::Type{CUDABackend})
    rep = _contract_rep_for_backend(beam.rep, CUDABackend)
    return Beam{CUDABackend,typeof(beam.params),typeof(rep)}(beam.params, rep)
end

function _strong_strong_contract_task(contract::StrongStrongPICBackendConsistencyContract,
                                      luminosity_path)
    slicing = LongitudinalSlicing(
        method=:normal_quantile,
        nslices=contract.nslices,
        center_position=:centroid,
    )
    solver = PICPoissonSolver(
        slicing=slicing,
        grid=contract.grid,
        green_cache=contract.green_cache,
        slice_pair_green_min_ratio=contract.slice_pair_green_min_ratio,
        slice_pair_green_growth=contract.slice_pair_green_growth,
        batch_mode=contract.batch_mode,
        longitudinal_kick=true,
        luminosity_schedule=nothing,
    )
    ip = StrongStrongCollision(:ip; poisson_solver=solver)
    return StrongStrongTask((ip,), (ip,); luminosity_path=luminosity_path)
end

function _strong_strong_contract_last_luminosity(path)
    lines = readlines(path)
    isempty(lines) && error("strong-strong contract produced no luminosity records")
    return parse(Float64, last(split(lines[end], '\t')))
end

function _strong_strong_contract_cpu_cache_history(task)
    caches = [value for value in values(task.runtime_cache)
              if value isa _PICSlicePairGreenCache]
    isempty(caches) && return (0, 0, 0)
    length(caches) == 1 || error("expected one CPU PIC slice-pair cache")
    cache = only(caches)
    return (cache.hits, cache.misses, cache.rebuilds)
end

function _strong_strong_contract_cuda_cache_history(task)
    workspaces = [value for value in values(task.runtime_cache)
                  if hasproperty(value, :slice_pair_green_cache)]
    isempty(workspaces) && return (0, 0, 0)
    length(workspaces) == 1 || error("expected one CUDA PIC workspace")
    cache = only(workspaces).slice_pair_green_cache
    return (cache.hits, cache.misses, cache.rebuilds)
end
