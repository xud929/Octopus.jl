export ContractResult, passed, validate,
       PublicConfigurationEffectivenessContract,
       ElementTrackingBackendConsistencyContract,
       StrongStrongGaussianBackendConsistencyContract,
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
    StrongStrongGaussianBackendConsistencyContract(; n_particles=1024, turns=2,
        nslices=3, seed=123456789, atol=1e-10, rtol=1e-10,
        luminosity_rtol=1e-10)

Validate CPU/CUDA consistency for a live-beam strong-strong soft-Gaussian
collision. The contract constructs identical electron/proton beams, executes
matching `StrongStrongTask`s, and compares both final six-dimensional beam
states and luminosity.

If CUDA is unavailable, validation returns `status=:skipped`.
"""
Base.@kwdef struct StrongStrongGaussianBackendConsistencyContract <: AbstractBackendConsistencyContract
    n_particles::Int = 1024
    turns::Int = 2
    nslices::Int = 3
    seed::UInt64 = UInt64(123456789)
    atol::Float64 = 1e-10
    rtol::Float64 = 1e-10
    luminosity_rtol::Float64 = 1e-10
end

"""
    StrongStrongPICBackendConsistencyContract(; n_particles=1024, turns=2,
        grid=(32, 32), nslices=3, deposit_method=:CIC,
        luminosity_deposit_method=nothing,
        green_cache=:slice_pair,
        slice_pair_green_min_ratio=0.50, slice_pair_green_growth=0.25,
        batch_mode=:wavefront, seed=123456789, atol=1e-10, rtol=1e-10,
        luminosity_rtol=1e-10)

Validate CPU/CUDA consistency for a live-beam strong-strong PIC collision.
The contract constructs identical electron/proton beams, executes matching
`StrongStrongTask`s, compares both final six-dimensional beam states and
luminosity, and—when `green_cache=:slice_pair`—requires identical cache
hit/miss/rebuild histories with at least one reuse.
Set `deposit_method=:CIC` or `:TSC` to validate either force deposition path.
`luminosity_deposit_method=nothing` inherits that method; explicit `:CIC` or
`:TSC` validates an independent luminosity-deposition choice. Wavefront mode
also compares every nonempty slice-pair luminosity contribution; sequential
mode compares the complete per-turn luminosity series.

If CUDA is unavailable, validation returns `status=:skipped`.
"""
Base.@kwdef struct StrongStrongPICBackendConsistencyContract <: AbstractBackendConsistencyContract
    n_particles::Int = 1024
    turns::Int = 2
    grid::Tuple{Int,Int} = (32, 32)
    nslices::Int = 3
    deposit_method::Symbol = :CIC
    luminosity_deposit_method::Union{Nothing,Symbol} = nothing
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
    PublicConfigurationEffectivenessContract(; n_particles=256,
        cuda_threads=128, cuda_blocks=3)

Verify that public execution configuration reaches actual runtime consumers.
The contract checks CPU logical-worker receipts, explicit and automatic fused
CUDA launch receipts, policy/storage mismatch rejection before mutation, and
all CUDA PIC launch-family overrides. Execution-geometry changes must preserve
the deterministic fused tracking result.

If CUDA is unavailable, CPU/schema checks run and the overall result is
`status=:skipped`; an unavailable CUDA check is never reported as passed.
"""
Base.@kwdef struct PublicConfigurationEffectivenessContract <: AbstractImplementationContract
    n_particles::Int = 256
    cuda_threads::Int = 128
    cuda_blocks::Int = 3
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

description(::Type{StrongStrongGaussianBackendConsistencyContract}) =
    "Checks strong-strong soft-Gaussian coordinates and luminosity across CPU and CUDA."

description(::Type{StrongStrongPICBackendConsistencyContract}) =
    "Checks strong-strong PIC coordinates, luminosity, and cache history across CPU and CUDA."

description(::Type{PublicConfigurationEffectivenessContract}) =
    "Checks that public configuration values reach their declared runtime consumers."

function validate(contract::PublicConfigurationEffectivenessContract; kwargs...)
    metrics = Dict{Symbol,Any}()
    try
        validate_configuration_metadata()
    catch err
        return ContractResult(false, "configuration metadata validation failed: $(sprint(showerror, err))";
                              metrics=metrics)
    end

    base = _contract_default_initial_rep(contract.n_particles, Float64)
    line = (CrabDispersionSpec{Float64}(zeta1=0.02, zeta3=-0.01),)
    worker_sweep = unique((1, min(2, Threads.nthreads(:default)),
                           Threads.nthreads(:default)))
    rep_cpu = nothing
    cpu_receipt_counts = Dict{Int,Int}()
    cpu_coordinate_error = 0.0
    for workers in worker_sweep
        candidate = _contract_rep_for_backend(base, CPUThreadsBackend)
        cpu_audit = ExecutionAudit()
        with_execution_audit(cpu_audit) do
            execute!(TrackingTask(line; policy=CPUThreadsExecutionPolicy(threads=workers)),
                     candidate; turns=2)
        end
        cpu_receipts = filter(r -> r.consumer === :cpu_logical_workers,
                              execution_receipts(cpu_audit))
        effective = !isempty(cpu_receipts) &&
                    all(r -> r.values.workers == workers, cpu_receipts)
        effective || return ContractResult(false,
            "CPUThreadsExecutionPolicy($(workers)) did not reach the logical-worker consumer.";
            metrics=metrics)
        cpu_receipt_counts[workers] = length(cpu_receipts)
        if rep_cpu === nothing
            rep_cpu = candidate
        else
            comparison = _contract_coordinate_metrics(rep_cpu, candidate, 0.0, 0.0)
            cpu_coordinate_error = max(cpu_coordinate_error, comparison[:max_abs_error])
            comparison[:max_abs_error] == 0.0 || return ContractResult(false,
                "CPU logical-worker count changed independent-particle tracking results.";
                residual=comparison[:max_abs_error], metrics=metrics)
        end
    end
    metrics[:cpu_workers_tested] = worker_sweep
    metrics[:cpu_worker_receipts] = cpu_receipt_counts
    metrics[:cpu_worker_coordinate_max_abs_error] = cpu_coordinate_error
    metrics[:cpu_worker_effective] = true

    invalid_rejected = try
        CPUThreadsExecutionPolicy(threads=Threads.nthreads(:default) + 1)
        false
    catch err
        err isa ArgumentError
    end
    metrics[:invalid_cpu_threads_rejected] = invalid_rejected
    invalid_rejected || return ContractResult(false,
        "invalid CPU thread count was not rejected."; metrics=metrics)

    beam_typo_rejected = try
        Beam(4, CPUThreadsExecutionPolicy(threads=1), Float64; typo_option=1)
        false
    catch err
        err isa ArgumentError
    end
    metrics[:unknown_beam_keyword_rejected] = beam_typo_rejected
    beam_typo_rejected || return ContractResult(false,
        "unknown Beam keyword was silently ignored."; metrics=metrics)

    schedule_effective = mktempdir() do dir
        observer = MomentObserver(joinpath(dir, "moments.h5"); orders=1, capacity=2)
        scheduled = ScheduledObserver(observer, EveryNSteps(start=0, stop=5, step=2))
        rep = _contract_rep_for_backend(base, CPUThreadsBackend)
        audit = ExecutionAudit()
        with_execution_audit(audit) do
            execute!(TrackingTask((line..., scheduled);
                                  policy=CPUThreadsExecutionPolicy(threads=first(worker_sweep))),
                     rep; turns=5)
        end
        receipts = execution_receipts(audit)
        schedule_receipts = filter(r -> r.consumer === :hook_schedule, receipts)
        output_receipts = filter(r -> r.consumer === :observer_output &&
                                      r.values.observer === :MomentObserver, receipts)
        active_turns = [r.values.turn for r in schedule_receipts if r.values.active]
        return active_turns == [0, 2, 4] && length(output_receipts) == 3 &&
               all(r -> r.values.capacity == 2, output_receipts)
    end
    metrics[:schedule_and_capacity_effective] = schedule_effective
    schedule_effective || return ContractResult(false,
        "observer schedule or buffer capacity did not reach its runtime consumer.";
        metrics=metrics)

    report_solver = PICPoissonSolver(grid=(16, 16), deposit_method=:TSC,
        backend_configurations=(CUDAPICLaunchConfig(deposition_threads=64),))
    report_entries = configuration_report(report_solver;
        policy=CPUThreadsExecutionPolicy(threads=first(worker_sweep)),
        backend=CPUThreadsBackend)
    report_by_name = Dict(entry.name => entry for entry in report_entries)
    inherited_reported = report_by_name[:luminosity_grid].status === :inherited &&
                         report_by_name[:luminosity_grid].resolved == (16, 16) &&
                         report_by_name[:luminosity_deposit_method].status === :inherited &&
                         report_by_name[:luminosity_deposit_method].resolved === :TSC
    inactive_reported = report_by_name[:backend_configurations].status === :inactive_backend
    metrics[:inherited_configuration_reported] = inherited_reported
    metrics[:inactive_configuration_reported] = inactive_reported
    (inherited_reported && inactive_reported) || return ContractResult(false,
        "configuration report did not distinguish inherited and inactive settings.";
        metrics=metrics)

    mismatch_beam1 = Beam(16, CPUThreadsExecutionPolicy(threads=first(worker_sweep)),
                          Float64; rng_id=101)
    mismatch_beam2 = Beam(16, CPUThreadsExecutionPolicy(threads=first(worker_sweep)),
                          Float64; rng_id=102)
    mismatch_before1 = map(copy, coordinate_arrays(mismatch_beam1.rep))
    mismatch_before2 = map(copy, coordinate_arrays(mismatch_beam2.rep))
    mismatch_ip1 = StrongStrongCollision(:mismatch;
        poisson_solver=GaussianPoissonSolver())
    mismatch_ip2 = StrongStrongCollision(:mismatch;
        poisson_solver=GaussianPoissonSolver())
    solver_mismatch_rejected = try
        execute!(StrongStrongTask((line[1], mismatch_ip1), (line[1], mismatch_ip2);
            policy=CPUThreadsExecutionPolicy(threads=first(worker_sweep))),
            mismatch_beam1, mismatch_beam2; turns=1)
        false
    catch err
        err isa ArgumentError
    end
    solver_mismatch_unchanged =
        all(map(==, mismatch_before1, coordinate_arrays(mismatch_beam1.rep))) &&
        all(map(==, mismatch_before2, coordinate_arrays(mismatch_beam2.rep)))
    metrics[:solver_mismatch_rejected] = solver_mismatch_rejected
    metrics[:solver_mismatch_unchanged] = solver_mismatch_unchanged
    (solver_mismatch_rejected && solver_mismatch_unchanged) || return ContractResult(false,
        "strong-strong solver mismatch was not rejected before line mutation.";
        metrics=metrics)

    available, reason = _contract_backends_available(CUDABackend)
    if !available
        metrics[:cuda_status] = :skipped
        return ContractResult(:skipped,
            "CPU configuration checks passed; CUDA effectiveness was skipped: $(reason)";
            metrics=metrics)
    end

    cuda_threads_sweep = (64, 128, 256, 512)
    cuda_launch_receipts = Dict{Tuple{Int,Any},Int}()
    cuda_coordinate_error = 0.0
    rep_cuda = nothing
    for threads in cuda_threads_sweep, requested_blocks in (contract.cuda_blocks, :auto)
        candidate = _contract_rep_for_backend(base, CUDABackend)
        cuda_audit = ExecutionAudit()
        policy = CUDAExecutionPolicy(launch=CUDALaunchConfig(
            threads=threads, blocks=requested_blocks))
        with_execution_audit(cuda_audit) do
            execute!(TrackingTask(line; policy=policy), candidate; turns=2)
            CUDA.synchronize()
        end
        receipts = filter(r -> r.consumer === :cuda_fused_launch,
                          execution_receipts(cuda_audit))
        effective = !isempty(receipts) && all(r ->
            r.values.threads == threads &&
            r.values.requested_blocks == requested_blocks &&
            (requested_blocks === :auto ? r.values.blocks > 0 :
                                          r.values.blocks == requested_blocks), receipts)
        effective || return ContractResult(false,
            "CUDA launch ($(threads), $(requested_blocks)) did not reach fused tracking.";
            metrics=metrics)
        cuda_launch_receipts[(threads, requested_blocks)] = length(receipts)
        comparison = _contract_coordinate_metrics(rep_cpu, candidate, 1e-12, 1e-12)
        cuda_coordinate_error = max(cuda_coordinate_error, comparison[:max_abs_error])
        comparison[:passed_tolerance] || return ContractResult(false,
            "CUDA launch geometry changed deterministic fused tracking results.";
            residual=comparison[:max_abs_error], metrics=metrics)
        rep_cuda = candidate
    end
    metrics[:cuda_threads_tested] = cuda_threads_sweep
    metrics[:cuda_fused_receipts] = cuda_launch_receipts
    metrics[:cuda_explicit_launch_effective] = true
    metrics[:cuda_auto_launch_effective] = true
    metrics[:cuda_coordinate_max_abs_error] = cuda_coordinate_error

    before = Array(rep_cuda.x)
    wrong_device = CUDA.deviceid(CUDA.device(rep_cuda.x)) + 1
    mismatch_rejected = try
        execute!(TrackingTask(line; policy=CUDAExecutionPolicy(device=wrong_device)),
                 rep_cuda; turns=1)
        false
    catch err
        err isa ArgumentError
    end
    mismatch_unchanged = before == Array(rep_cuda.x)
    metrics[:cuda_device_mismatch_rejected] = mismatch_rejected
    metrics[:cuda_device_mismatch_unchanged] = mismatch_unchanged
    (mismatch_rejected && mismatch_unchanged) || return ContractResult(false,
        "CUDA device mismatch was not rejected before particle mutation."; metrics=metrics)

    base_beam1, base_beam2 = _strong_strong_contract_base_beams(
        StrongStrongPICBackendConsistencyContract(n_particles=contract.n_particles,
            turns=2, grid=(16, 16), nslices=3, green_cache=:none))
    invalid_beam1 = _strong_strong_contract_beam(base_beam1, CUDABackend)
    invalid_beam2 = _strong_strong_contract_beam(base_beam2, CUDABackend)
    invalid_before1 = map(Array, coordinate_arrays(invalid_beam1.rep))
    invalid_before2 = map(Array, coordinate_arrays(invalid_beam2.rep))
    invalid_solver = PICPoissonSolver(grid=(16, 16), green_cache=:none,
        slicing=LongitudinalSlicing(method=:normal_quantile, nslices=3,
                                    center_position=:centroid))
    invalid_ip = StrongStrongCollision(:invalid; poisson_solver=invalid_solver)
    invalid_pic_rejected = try
        execute!(StrongStrongTask((line[1], invalid_ip), (line[1], invalid_ip);
            policy=CUDAExecutionPolicy(launch=CUDALaunchConfig(threads=96, blocks=3))),
            invalid_beam1, invalid_beam2; turns=1)
        false
    catch err
        err isa ArgumentError
    end
    invalid_pic_unchanged = all(map(==, invalid_before1,
                                    map(Array, coordinate_arrays(invalid_beam1.rep)))) &&
                            all(map(==, invalid_before2,
                                    map(Array, coordinate_arrays(invalid_beam2.rep))))
    metrics[:invalid_cuda_pic_launch_rejected] = invalid_pic_rejected
    metrics[:invalid_cuda_pic_launch_unchanged] = invalid_pic_unchanged
    (invalid_pic_rejected && invalid_pic_unchanged) || return ContractResult(false,
        "invalid inherited CUDA PIC launch was not rejected before line mutation.";
        metrics=metrics)

    beam1 = _strong_strong_contract_beam(base_beam1, CUDABackend)
    beam2 = _strong_strong_contract_beam(base_beam2, CUDABackend)
    pic_launch = CUDAPICLaunchConfig(
        gather_scatter_threads=contract.cuda_threads,
        deposition_threads=contract.cuda_threads,
        kick_threads=contract.cuda_threads,
        field_threads=contract.cuda_threads,
        spectral_threads=contract.cuda_threads,
        green_threads=contract.cuda_threads,
        luminosity_threads=contract.cuda_threads,
    )
    slicing = LongitudinalSlicing(method=:normal_quantile, nslices=3,
                                  center_position=:centroid)
    solver = PICPoissonSolver(grid=(16, 16), slicing=slicing, green_cache=:none,
        cuda_indexed_wavefront=false, backend_configurations=(pic_launch,))
    ip = StrongStrongCollision(:ip; poisson_solver=solver)
    explicit_policy = CUDAExecutionPolicy(
        launch=CUDALaunchConfig(threads=contract.cuda_threads,
                                blocks=contract.cuda_blocks))
    pic_task = StrongStrongTask((ip,), (ip,); policy=explicit_policy)
    pic_audit = ExecutionAudit()
    with_execution_audit(pic_audit) do
        execute!(pic_task, beam1, beam2; turns=1)
        CUDA.synchronize()
    end
    pic_receipts = filter(r -> r.consumer === :cuda_pic_launch,
                          execution_receipts(pic_audit))
    families = Set(r.values.family for r in pic_receipts)
    required_families = Set(_CUDA_PIC_LAUNCH_FAMILIES)
    pic_effective = required_families <= families &&
                    all(r -> r.values.threads == contract.cuda_threads, pic_receipts)
    algorithm_receipts = filter(r -> r.consumer === :cuda_pic_algorithm,
                                execution_receipts(pic_audit))
    wavefront_algorithm_effective = !isempty(algorithm_receipts) && all(r ->
        r.values.batch_mode === :wavefront && r.values.cuda_async &&
        r.values.cuda_batch_fft && r.values.cuda_wavefront_fft &&
        !r.values.cuda_indexed_wavefront, algorithm_receipts)
    metrics[:cuda_pic_families_observed] = sort!(collect(families))
    metrics[:cuda_pic_launch_effective] = pic_effective
    metrics[:cuda_pic_wavefront_algorithm_effective] = wavefront_algorithm_effective
    (pic_effective && wavefront_algorithm_effective) || return ContractResult(false,
        "CUDA PIC launch or wavefront algorithm settings did not reach their consumers.";
        metrics=metrics)

    sequential_beam1 = _strong_strong_contract_beam(base_beam1, CUDABackend)
    sequential_beam2 = _strong_strong_contract_beam(base_beam2, CUDABackend)
    sequential_solver = PICPoissonSolver(grid=(16, 16), slicing=slicing,
        green_cache=:none, batch_mode=:sequential, cuda_async=false,
        cuda_batch_fft=false, cuda_wavefront_fft=false,
        cuda_indexed_wavefront=false, backend_configurations=(pic_launch,))
    sequential_ip = StrongStrongCollision(:sequential; poisson_solver=sequential_solver)
    sequential_audit = ExecutionAudit()
    with_execution_audit(sequential_audit) do
        execute!(StrongStrongTask((sequential_ip,), (sequential_ip,);
            policy=explicit_policy), sequential_beam1, sequential_beam2; turns=1)
        CUDA.synchronize()
    end
    sequential_receipts = filter(r -> r.consumer === :cuda_pic_algorithm,
                                 execution_receipts(sequential_audit))
    sequential_effective = !isempty(sequential_receipts) && all(r ->
        r.values.batch_mode === :sequential && !r.values.cuda_async &&
        !r.values.cuda_batch_fft && !r.values.cuda_wavefront_fft &&
        !r.values.cuda_indexed_wavefront, sequential_receipts)
    metrics[:cuda_pic_sequential_algorithm_effective] = sequential_effective
    sequential_effective || return ContractResult(false,
        "non-default sequential CUDA PIC settings did not reach their consumer.";
        metrics=metrics)

    metrics[:cuda_status] = :passed
    return ContractResult(true,
        "Public configuration reached CPU, fused CUDA, and CUDA PIC consumers.";
        residual=cuda_coordinate_error, metrics=metrics)
end

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

function validate(contract::StrongStrongGaussianBackendConsistencyContract; kwargs...)
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
            cpu_task = _strong_strong_gaussian_contract_task(contract, cpu_path)
            gpu_task = _strong_strong_gaussian_contract_task(contract, gpu_path)

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

            cpu_luminosity_series = _strong_strong_contract_luminosity_series(cpu_path)
            gpu_luminosity_series = _strong_strong_contract_luminosity_series(gpu_path)
            length(cpu_luminosity_series) == length(gpu_luminosity_series) ||
                error("CPU/CUDA luminosity series lengths differ")
            luminosity_rel = maximum(
                abs(gpu - cpu) / max(abs(cpu), eps(Float64))
                for (cpu, gpu) in zip(cpu_luminosity_series, gpu_luminosity_series)
            )
            luminosity_ok = luminosity_rel <= contract.luminosity_rtol
            cpu_luminosity = last(cpu_luminosity_series)
            gpu_luminosity = last(gpu_luminosity_series)
            metrics = Dict{Symbol,Any}(
                :backend_a => :CPUThreadsBackend,
                :backend_b => :CUDABackend,
                :n_particles => contract.n_particles,
                :turns => contract.turns,
                :nslices => contract.nslices,
                :max_abs_error => max_abs,
                :max_allowed_ratio => max_ratio,
                :max_component_rel_error => max_component_rel,
                :coordinate_passed_tolerance => coordinate_ok,
                :cpu_luminosity => cpu_luminosity,
                :gpu_luminosity => gpu_luminosity,
                :luminosity_records_compared => length(cpu_luminosity_series),
                :luminosity_rel_error => luminosity_rel,
                :luminosity_rtol => contract.luminosity_rtol,
                :luminosity_passed_tolerance => luminosity_ok,
                :cpu_threads => Threads.nthreads(),
            )
            ok = coordinate_ok && luminosity_ok
            message = ok ?
                "Strong-strong Gaussian CPU and CUDA results agree within tolerance." :
                "Strong-strong Gaussian CPU and CUDA results disagree beyond tolerance."
            return ContractResult(ok, message; residual=max_abs, metrics=metrics)
        end
    finally
        set_global_rng!(seed=old_seed, method=old_method)
    end
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
    contract.deposit_method in (:CIC, :TSC) || return ContractResult(false,
        "deposit_method must be :CIC or :TSC; got $(contract.deposit_method).")
    (contract.luminosity_deposit_method === nothing ||
     contract.luminosity_deposit_method in (:CIC, :TSC)) || return ContractResult(false,
        "luminosity_deposit_method must be nothing, :CIC, or :TSC; got $(contract.luminosity_deposit_method).")
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

            cpu_pair_luminosities = Any[]
            gpu_pair_luminosities = Any[]
            Base.ScopedValues.with(
                _ACTIVE_PIC_LUMINOSITY_PAIR_SINK => cpu_pair_luminosities,
            ) do
                execute!(cpu_task, cpu1, cpu2; turns=contract.turns)
            end
            Base.ScopedValues.with(
                _ACTIVE_PIC_LUMINOSITY_PAIR_SINK => gpu_pair_luminosities,
            ) do
                execute!(gpu_task, gpu1, gpu2; turns=contract.turns)
            end
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

            cpu_luminosity_series = _strong_strong_contract_luminosity_series(cpu_path)
            gpu_luminosity_series = _strong_strong_contract_luminosity_series(gpu_path)
            length(cpu_luminosity_series) == length(gpu_luminosity_series) ||
                error("CPU/CUDA luminosity series lengths differ")
            luminosity_rel = maximum(
                abs(gpu - cpu) / max(abs(cpu), eps(Float64))
                for (cpu, gpu) in zip(cpu_luminosity_series, gpu_luminosity_series)
            )
            luminosity_ok = luminosity_rel <= contract.luminosity_rtol
            cpu_luminosity = last(cpu_luminosity_series)
            gpu_luminosity = last(gpu_luminosity_series)
            cpu_pair_map = Dict((row.turn, row.i, row.j) => row.luminosity
                                for row in cpu_pair_luminosities)
            gpu_pair_map = Dict((row.turn, row.i, row.j) => row.luminosity
                                for row in gpu_pair_luminosities)
            pair_trace_expected = contract.batch_mode == :wavefront
            pair_keys_match = !pair_trace_expected || keys(cpu_pair_map) == keys(gpu_pair_map)
            pair_luminosity_rel = pair_trace_expected && pair_keys_match ? maximum(
                abs(gpu_pair_map[key] - cpu_pair_map[key]) /
                max(abs(cpu_pair_map[key]), eps(Float64)) for key in keys(cpu_pair_map)
            ) : pair_trace_expected ? Inf : 0.0
            pair_luminosity_ok = pair_keys_match &&
                (!pair_trace_expected || pair_luminosity_rel <= contract.luminosity_rtol)

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
                :deposit_method => contract.deposit_method,
                :luminosity_deposit_method => contract.luminosity_deposit_method,
                :resolved_luminosity_deposit_method =>
                    something(contract.luminosity_deposit_method, contract.deposit_method),
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
                :luminosity_records_compared => length(cpu_luminosity_series),
                :slice_pair_luminosity_records_compared =>
                    pair_trace_expected ? length(cpu_pair_map) : 0,
                :slice_pair_luminosity_rel_error => pair_luminosity_rel,
                :slice_pair_luminosity_passed_tolerance => pair_luminosity_ok,
                :luminosity_rel_error => luminosity_rel,
                :luminosity_rtol => contract.luminosity_rtol,
                :luminosity_passed_tolerance => luminosity_ok,
                :cpu_cache_history => cpu_history,
                :gpu_cache_history => gpu_history,
                :cache_histories_match => cache_history_ok,
                :cache_reuse_observed => cache_reuse_ok,
                :cpu_threads => Threads.nthreads(),
            )
            ok = coordinate_ok && luminosity_ok && pair_luminosity_ok &&
                 cache_history_ok && cache_reuse_ok
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
_contract_policy(::Type{CUDABackend}) = CUDAExecutionPolicy()

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

function _strong_strong_contract_base_beams(contract::Union{
        StrongStrongGaussianBackendConsistencyContract,
        StrongStrongPICBackendConsistencyContract})
    n = contract.n_particles
    beam1 = Beam(n, CPUThreadsBackend, Float64;
        beta=(0.55, 0.056, 0.7e-2 / 5.5e-4), alpha=(0.0, 0.0, 0.0),
        sigma=(106e-6, 9.5e-6, 0.7e-2), cutoff=5.0, rng_id=1,
        charge=-1.0, mc2=EMASS_EV, E0=10e9, r0=RE, npart=1.7203e11)
    beam2 = Beam(n, CPUThreadsBackend, Float64;
        beta=(0.8, 0.072, 6e-2 / 6.6e-4), alpha=(0.0, 0.0, 0.0),
        sigma=(95e-6, 8.5e-6, 6e-2), cutoff=5.0, rng_id=2,
        charge=1.0, mc2=PMASS_EV, E0=275e9,
        r0=RE * ME0 / PMASS_EV, npart=0.6881e11)
    return beam1, beam2
end

function _strong_strong_gaussian_contract_task(
        contract::StrongStrongGaussianBackendConsistencyContract, luminosity_path)
    slicing = LongitudinalSlicing(
        method=:normal_quantile,
        nslices=contract.nslices,
        center_position=:centroid,
    )
    solver = GaussianPoissonSolver(slicing=slicing)
    ip = StrongStrongCollision(:ip; poisson_solver=solver)
    return StrongStrongTask((ip,), (ip,); luminosity_path=luminosity_path)
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
        deposit_method=contract.deposit_method,
        luminosity_deposit_method=contract.luminosity_deposit_method,
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
    return last(_strong_strong_contract_luminosity_series(path))
end

function _strong_strong_contract_luminosity_series(path)
    lines = readlines(path)
    length(lines) > 1 || error("strong-strong contract produced no luminosity records")
    return [parse(Float64, last(split(line, '\t'))) for line in @view(lines[2:end])]
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
