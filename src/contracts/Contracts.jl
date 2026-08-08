export ContractResult, passed, validate,
       PublicConfigurationEffectivenessContract,
       KnobEffectivenessContract,
       ElementTrackingBackendConsistencyContract,
       StrongStrongGaussianBackendConsistencyContract,
       StrongStrongPICBackendConsistencyContract,
       SymplecticityContract,
       HighEnergyWeakStrongLimitContract,
       PTCConsistencyContract,
       ElementParameterEffectivenessContract,
       CoherentModePhysicsContract,
       SolverOptionEffectivenessContract

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
    KnobEffectivenessContract(; n_particles=64)

Verify that knob control reaches its runtime consumer (`compile_runtime` via
`resolve_knobs`): a knob-expression element parameter produces identical
tracking to the directly-parameterized element; assigning an independent input
(through the `knobs` namespace) recompiles the *same task object* through the
knob-epoch cache invalidation; binding a knob to an element *after
construction* (`spec.zeta1 = @knob_expr(...)`) reaches an already-built task
through the spec-epoch cache invalidation; a `:knob_resolution` audit receipt
is emitted; and the definition-time guards fire (unset knob evaluation,
dependency cycles, and assigning a dependent knob are all rejected). Uses a
private `__knob_contract__` namespace and removes it afterwards.
"""
Base.@kwdef struct KnobEffectivenessContract <: AbstractImplementationContract
    n_particles::Int = 64
end

"""
    validate(contract, args...; kwargs...)

Run a validation contract against the supplied objects. Concrete contracts should
extend this method and return `ContractResult`.
"""
function validate(contract::AbstractContract, args...; kwargs...)
    _reject_unknown_validate_kwargs(contract, kwargs)
    return ContractResult(false,
        "No validation implementation registered for $(nameof(typeof(contract))).")
end

"""
    _reject_unknown_validate_kwargs(contract, kwargs)

Refuse keyword arguments no `validate` method reads.

Every `validate` signature is `(contract; kwargs...)` and no body has ever read
`kwargs`, so a misspelled or invented keyword was silently accepted and dropped
-- `validate(SymplecticityContract(); tolerance=1e-30, this_kwarg_does_not_exist=42)`
returned a result byte-identical to the no-keyword call (2026-08-05_b audit,
U4-13). That is the unknown-keyword family, inside the file whose job is to catch
it, and the contracts themselves assert the opposite for everyone else:
`PublicConfigurationEffectivenessContract` FAILS if `Beam` silently ignores an
unknown keyword. Contract structs are `Base.@kwdef` and already `MethodError`;
only this entry point was permissive.

Tuning belongs in the contract's own fields, which is why nothing reads kwargs.
"""
function _reject_unknown_validate_kwargs(contract, kwargs)
    isempty(kwargs) && return nothing
    names = join(sort!(collect(String.(keys(kwargs)))), ", ")
    throw(ArgumentError(
        "validate($(nameof(typeof(contract)))) does not accept keyword arguments; " *
        "got $(names). Contract settings are fields: construct the contract with " *
        "them, e.g. $(nameof(typeof(contract)))(; ...)."))
end


description(::Type{ElementTrackingBackendConsistencyContract}) =
    "Checks coordinate consistency for the same tracking line across two execution backends."

description(::Type{StrongStrongGaussianBackendConsistencyContract}) =
    "Checks strong-strong soft-Gaussian coordinates and luminosity across CPU and CUDA."

description(::Type{StrongStrongPICBackendConsistencyContract}) =
    "Checks strong-strong PIC coordinates, luminosity, and cache history across CPU and CUDA."

description(::Type{PublicConfigurationEffectivenessContract}) =
    "Checks that public configuration values reach their declared runtime consumers."

description(::Type{KnobEffectivenessContract}) =
    "Checks that knob expressions reach compiled runtime elements and that knob changes recompile them."

function validate(contract::KnobEffectivenessContract; kwargs...)
    _reject_unknown_validate_kwargs(contract, kwargs)
    metrics = Dict{Symbol,Any}()
    contract_paths = (
        Symbol("__knob_contract__.current"), Symbol("__knob_contract__.transfer"),
        Symbol("__knob_contract__.brho"), Symbol("__knob_contract__.k1"),
        Symbol("__knob_contract__.unset"),
    )
    try
        @knob __knob_contract__.current = 1000.0
        @knob __knob_contract__.transfer = 0.05
        @knob __knob_contract__.brho = 81.1
        @knob __knob_contract__.k1 =
            __knob_contract__.current * __knob_contract__.transfer / __knob_contract__.brho
        expected(current) = current * 0.05 / 81.1

        base = _contract_default_initial_rep(contract.n_particles, Float64)
        policy = CPUThreadsExecutionPolicy(threads=1)
        # The flexible form requires every parameter the runtime constructor
        # reads, exactly as the element's construction_help documents.
        knob_spec = ElementSpec{:crab_dispersion}(;
            zeta1=@knob_expr(__knob_contract__.k1),
            zeta2=0.0, zeta3=0.0, zeta4=0.0,
            tracking_method=Symplectic6DMap())
        knob_task = TrackingTask((knob_spec,); policy=policy)
        run_knob!() = begin
            rep = _contract_rep_for_backend(base, CPUThreadsBackend)
            execute!(knob_task, rep; turns=1)
            rep
        end
        run_reference!(zeta1) = begin
            rep = _contract_rep_for_backend(base, CPUThreadsBackend)
            execute!(TrackingTask((CrabDispersionSpec{Float64}(zeta1=zeta1),);
                                  policy=policy), rep; turns=1)
            rep
        end

        audit = ExecutionAudit()
        local rep_initial
        with_execution_audit(audit) do
            rep_initial = run_knob!()
        end
        initial = _contract_coordinate_metrics(rep_initial, run_reference!(expected(1000.0)), 0.0, 0.0)
        receipt_emitted = any(r -> r.consumer === :knob_resolution, execution_receipts(audit))

        knobs.__knob_contract__.current = 400.0   # namespace assignment => set_knob!
        updated = _contract_coordinate_metrics(run_knob!(), run_reference!(expected(400.0)), 0.0, 0.0)

        # Post-construction binding: a task built from a plainly-parameterized
        # spec picks up a knob bound afterwards via property assignment (the
        # spec epoch recompiles its runtime line at the next execute!).
        bind_spec = ElementSpec{:crab_dispersion}(;
            zeta1=0.0, zeta2=0.0, zeta3=0.0, zeta4=0.0,
            tracking_method=Symplectic6DMap())
        bind_task = TrackingTask((bind_spec,); policy=policy)
        rep_bind0 = _contract_rep_for_backend(base, CPUThreadsBackend)
        execute!(bind_task, rep_bind0; turns=1)
        bind_spec.zeta1 = @knob_expr(__knob_contract__.k1)
        rep_bind = _contract_rep_for_backend(base, CPUThreadsBackend)
        execute!(bind_task, rep_bind; turns=1)
        bound = _contract_coordinate_metrics(rep_bind, run_reference!(expected(400.0)), 0.0, 0.0)

        unset_rejected = try
            @knob __knob_contract__.unset
            compile_runtime(ElementSpec{:crab_dispersion}(;
                zeta1=@knob_expr(__knob_contract__.unset),
                tracking_method=Symplectic6DMap()))
            false
        catch err
            err isa ArgumentError
        end
        cycle_rejected = try
            _knob_define!(Symbol("__knob_contract__.brho"),
                          Meta.parse("__knob_contract__.k1 * 2.0"))
            false
        catch err
            err isa ArgumentError
        end
        dependent_set_rejected = try
            set_knob!("__knob_contract__.k1", 1.0)
            false
        catch err
            err isa ArgumentError
        end

        metrics[:initial_max_abs_error] = initial[:max_abs_error]
        metrics[:updated_max_abs_error] = updated[:max_abs_error]
        metrics[:post_bind_max_abs_error] = bound[:max_abs_error]
        metrics[:knob_resolution_receipt] = receipt_emitted
        metrics[:unset_rejected] = unset_rejected
        metrics[:cycle_rejected] = cycle_rejected
        metrics[:dependent_set_rejected] = dependent_set_rejected
        metrics[:n_particles] = contract.n_particles

        ok = initial[:max_abs_error] == 0.0 && updated[:max_abs_error] == 0.0 &&
             bound[:max_abs_error] == 0.0 &&
             receipt_emitted && unset_rejected && cycle_rejected && dependent_set_rejected
        message = ok ?
            "Knob expressions reach compiled runtime elements, knob changes and post-construction bindings recompile them, and definition-time guards fire." :
            "Knob control did not reach its runtime consumer or a definition-time guard failed."
        return ContractResult(ok, message;
                              residual=max(initial[:max_abs_error], updated[:max_abs_error],
                                           bound[:max_abs_error]),
                              metrics=metrics)
    finally
        for path in contract_paths
            _forget_knob!(path)
        end
    end
end

function validate(contract::PublicConfigurationEffectivenessContract; kwargs...)
    _reject_unknown_validate_kwargs(contract, kwargs)
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
    # The INVARIANCE comparison needs two worker counts to compare. On a
    # single-threaded Julia the sweep collapses to [1], the comparison branch
    # never runs, `cpu_coordinate_error` keeps its 0.0 initialiser -- and this
    # used to publish `max_abs_error = 0.0` and `effective = true` regardless,
    # i.e. a measurement that was never taken, reported as passed
    # (2026-08-05_b audit, U4-10). Measured at `-t1`: `status = passed`,
    # `cpu_workers_tested = [1]`, error 0.0, effective true. `validate` is
    # public API, and the CI gate's --threads=4 is what kept the suite honest,
    # not the contract.
    if length(worker_sweep) >= 2
        metrics[:cpu_worker_coordinate_max_abs_error] = cpu_coordinate_error
        metrics[:cpu_worker_effective] = true
    else
        metrics[:cpu_worker_coordinate_max_abs_error] = :not_measured
        metrics[:cpu_worker_effective] = :not_measured
        metrics[:cpu_worker_invariance_note] =
            "only one logical-worker count is available on this Julia " *
            "(--threads=$(Threads.nthreads(:default))); worker-invariance was " *
            "not compared. Run with at least two threads to measure it."
    end

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
    # A GENUINE configuration mismatch: same type, different resolved
    # configuration. Two identical GaussianPoissonSolver() objects sat here
    # before the U4-observation fix — the old identity rule threw on them,
    # but identical configurations are the same solver in every observable
    # way and are accepted by design now, so the probe must disagree in
    # substance, not in objectid (2026-08-05 queue session).
    mismatch_ip1 = StrongStrongCollision(:mismatch;
        poisson_solver=GaussianPoissonSolver())
    mismatch_ip2 = StrongStrongCollision(:mismatch;
        poisson_solver=GaussianPoissonSolver(min_sigma=1.0e-12))
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

    # The complement pins the other half of the rule: equal configurations
    # in DISTINCT objects are the same solver and must be ACCEPTED, so the
    # rejection above keys on the configuration and not on the object.
    equal_beam1 = Beam(16, CPUThreadsExecutionPolicy(threads=first(worker_sweep)),
                       Float64; rng_id=103)
    equal_beam2 = Beam(16, CPUThreadsExecutionPolicy(threads=first(worker_sweep)),
                       Float64; rng_id=104)
    # Explicit kbb on both: the contract's bare probe beams carry no E0, and
    # a beam-derived kbb would throw AFTER the solver-equality gate — this
    # probe must reach the collide itself to prove acceptance.
    equal_ip1 = StrongStrongCollision(:equalcfg;
        poisson_solver=GaussianPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6))
    equal_ip2 = StrongStrongCollision(:equalcfg;
        poisson_solver=GaussianPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6))
    solver_equal_config_accepted = try
        execute!(StrongStrongTask((line[1], equal_ip1), (line[1], equal_ip2);
            policy=CPUThreadsExecutionPolicy(threads=first(worker_sweep))),
            equal_beam1, equal_beam2; turns=1)
        true
    catch
        false
    end
    metrics[:solver_equal_config_accepted] = solver_equal_config_accepted
    solver_equal_config_accepted || return ContractResult(false,
        "structurally identical solver objects were rejected as a configuration mismatch.";
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
    _reject_unknown_validate_kwargs(contract, kwargs)
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
    _reject_unknown_validate_kwargs(contract, kwargs)
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
            # The pointwise ratio is a diagnostic, not the criterion: it is
            # divided by each component's own magnitude, so a near-zero
            # coordinate inflates it without any disagreement. `global_rel` is
            # the one to read -- the same difference against the beam scale --
            # and `max_component_rel_scale` says what the pointwise ratio was
            # divided by. The pass/fail test is `max_allowed_ratio <= 1`.
            worst_beam = beam1_metrics[:max_component_rel_error] >=
                         beam2_metrics[:max_component_rel_error] ?
                         beam1_metrics : beam2_metrics
            max_component_rel = worst_beam[:max_component_rel_error]
            max_component_rel_scale = worst_beam[:max_component_rel_scale]
            global_rel = max(beam1_metrics[:global_rel_error],
                             beam2_metrics[:global_rel_error])

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
                :global_rel_error => global_rel,
                :max_component_rel_error => max_component_rel,
                :max_component_rel_scale => max_component_rel_scale,
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
    _reject_unknown_validate_kwargs(contract, kwargs)
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
            # The pointwise ratio is a diagnostic, not the criterion: it is
            # divided by each component's own magnitude, so a near-zero
            # coordinate inflates it without any disagreement. `global_rel` is
            # the one to read -- the same difference against the beam scale --
            # and `max_component_rel_scale` says what the pointwise ratio was
            # divided by. The pass/fail test is `max_allowed_ratio <= 1`.
            worst_beam = beam1_metrics[:max_component_rel_error] >=
                         beam2_metrics[:max_component_rel_error] ?
                         beam1_metrics : beam2_metrics
            max_component_rel = worst_beam[:max_component_rel_error]
            max_component_rel_scale = worst_beam[:max_component_rel_scale]
            global_rel = max(beam1_metrics[:global_rel_error],
                             beam2_metrics[:global_rel_error])

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
            # Whether a per-pair trace is expected is decided by what the CPU
            # reference actually produced, NOT by `batch_mode`. Keying it off
            # `batch_mode == :wavefront` was wrong twice over (2026-08-05_b
            # audit, U1-1): with `:sequential` the whole comparison was skipped
            # and the contract still reported `passed`, having compared nothing
            # -- an unrun check reported as a passed one, which the repository
            # forbids -- and even under `:wavefront` the flag does not predict
            # the trace, because only the fully-indexed sub-route populates the
            # sink (measured: 16 records on the indexed default, 0 on
            # `indexed=false`, `wavefront_fft=false` and `async=false`, against
            # 16 on every CPU route).
            #
            # The CPU pushes one record per slice pair from the single loop that
            # serves every configuration, so an empty CPU trace means the run had
            # no pairs at all; a non-empty CPU trace with an empty GPU one is a
            # real backend divergence and is reported as such rather than
            # silently waived.
            pair_trace_expected = !isempty(cpu_pair_map)
            pair_keys_match = !pair_trace_expected || keys(cpu_pair_map) == keys(gpu_pair_map)
            pair_records_compared = pair_keys_match ? length(cpu_pair_map) : 0
            pair_luminosity_rel = pair_trace_expected && pair_keys_match ? maximum(
                abs(gpu_pair_map[key] - cpu_pair_map[key]) /
                max(abs(cpu_pair_map[key]), eps(Float64)) for key in keys(cpu_pair_map)
            ) : pair_trace_expected ? Inf : :not_applicable
            pair_luminosity_ok = !pair_trace_expected ? :not_applicable :
                (pair_keys_match && pair_luminosity_rel <= contract.luminosity_rtol)

            cpu_history = _strong_strong_contract_cpu_cache_history(cpu_task)
            gpu_history = _strong_strong_contract_cuda_cache_history(gpu_task)
            # `:not_applicable`, not `true`, when there is nothing to compare
            # (2026-08-05_b audit, U4-9). With `green_cache = :none` neither
            # side has a cache, so `cpu_history == gpu_history` reduces to
            # `(0,0,0) == (0,0,0)` and `cache_reuse_ok` short-circuits on the
            # mode -- and the contract then published
            # `cache_reuse_observed = true` with zero caches, which is exactly
            # the misreport AGENTS.md forbids. Same for the pair-luminosity
            # trace under `batch_mode = :sequential`, where 0 records compared
            # were reported as a passing 0.0 relative error.
            cache_compared = contract.green_cache === :slice_pair
            cache_history_ok = cache_compared ? cpu_history == gpu_history : :not_applicable
            cache_reuse_ok = cache_compared ? cpu_history[1] > 0 : :not_applicable

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
                :global_rel_error => global_rel,
                :max_component_rel_error => max_component_rel,
                :max_component_rel_scale => max_component_rel_scale,
                :coordinate_passed_tolerance => coordinate_ok,
                :cpu_luminosity => cpu_luminosity,
                :gpu_luminosity => gpu_luminosity,
                :luminosity_records_compared => length(cpu_luminosity_series),
                # The number of pairs actually compared, not the number the CPU
                # offered: if the keys disagree nothing was compared, and that
                # must read as 0 rather than as the CPU's count (U1-1).
                :slice_pair_luminosity_records_compared => pair_records_compared,
                :slice_pair_luminosity_cpu_records => length(cpu_pair_map),
                :slice_pair_luminosity_gpu_records => length(gpu_pair_map),
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
            # `:not_applicable` does not block the verdict, and does not
            # contribute a passing one either -- it says the question was not
            # asked (U4-9). Anything that WAS compared must still pass.
            _decided(v) = v === :not_applicable ? true : v
            ok = coordinate_ok && luminosity_ok && _decided(pair_luminosity_ok) &&
                 _decided(cache_history_ok) && _decided(cache_reuse_ok)
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

"""
    _require_gpu_contract() -> Bool

Whether `OCTOPUS_REQUIRE_GPU_CONTRACT` demands that a skipped GPU check be an
error rather than a printed skip.

One definition, because the alternative is what was here: six validation
scripts each parsing the same variable, in three different ways, and three of
them not honouring it at all -- so on a CPU-only machine those three exited 0
having run a fraction of their documented checks, indistinguishable from a full
pass (2026-08-05_b audit, U25-10). "Loud beats silent" needs the skip to be
assertable, not just visible.
"""
_require_gpu_contract() =
    lowercase(get(ENV, "OCTOPUS_REQUIRE_GPU_CONTRACT", "0")) in ("1", "true", "yes", "on")

"""
    _gpu_skip_or_error(label, reason)

Report an unavailable GPU leg: `error` when `OCTOPUS_REQUIRE_GPU_CONTRACT` is
set, otherwise print `label skipped: reason` and return.
"""
function _gpu_skip_or_error(label::AbstractString, reason::AbstractString)
    _require_gpu_contract() && error(
        "$(label) requires a CUDA device and OCTOPUS_REQUIRE_GPU_CONTRACT is set: $(reason)")
    println(label, " skipped: ", reason)
    return nothing
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
    max_component_rel_scale = 0.0
    max_allowed_ratio = 0.0
    lost_both = 0        # both backends killed this coordinate: agreement
    lost_mismatch = 0    # exactly one did: the worst kind of disagreement
    compared = 0         # coordinate pairs that actually entered a tolerance
    for dim in 1:6
        a = Array(arrays_a[dim])
        b = Array(arrays_b[dim])
        length(a) == length(b) || throw(ArgumentError("coordinate length mismatch in dimension $dim"))
        for i in eachindex(a)
            av = Float64(a[i])
            bv = Float64(b[i])
            # A lost particle is a comparison, not a poison pill (2026-08-05_b
            # audit, U25-4). `_aperture_kill` writes NaN into all six
            # coordinates, `abs(NaN - NaN)` is NaN, and `max(x, NaN)` is NaN in
            # Julia -- so a single lost particle turned every metric into NaN
            # and `passed_tolerance` into false, EVEN WHEN both backends lost
            # exactly the same particles. That made the aperture untestable: the
            # validation line had to keep limits no particle could ever reach,
            # so `:aperture` was covered by name and by nothing else.
            #
            # Both NaN means the two backends agree that this particle is gone,
            # which is the agreement this contract exists to measure. Exactly
            # one NaN is a real disagreement of the worst kind -- one backend
            # kept a particle the other killed -- and is counted separately and
            # forced to fail below, rather than being averaged into a tolerance.
            if isnan(av) && isnan(bv)
                lost_both += 1
                continue
            elseif isnan(av) || isnan(bv)
                lost_mismatch += 1
                continue
            end
            compared += 1
            diff = abs(av - bv)
            scale = max(abs(av), abs(bv))
            allowed = Float64(atol) + Float64(rtol) * scale
            max_abs = max(max_abs, diff)
            max_scale = max(max_scale, scale)
            component_rel = diff / max(scale, eps(Float64))
            if component_rel > max_component_rel
                max_component_rel = component_rel
                # Keep the magnitude this ratio was divided by. Without it the
                # ratio is uninterpretable: a round-off difference on a
                # coordinate near a zero crossing produces a large number that
                # says nothing about agreement.
                max_component_rel_scale = scale
            end
            max_allowed_ratio = max(max_allowed_ratio, diff / max(allowed, eps(Float64)))
        end
    end
    global_rel = max_abs / max(max_scale, eps(Float64))
    # `compared > 0` is not pedantry. Skipping NaN pairs means a run in which
    # EVERY particle died on both backends would leave max_allowed_ratio at its
    # initial 0.0 and report a pass having compared nothing -- the green lie
    # AGENTS.md forbids. A comparison with nothing in it is not a pass.
    return Dict{Symbol,Any}(
        :max_abs_error => max_abs,
        :global_rel_error => global_rel,
        :max_component_rel_error => max_component_rel,
        :max_component_rel_scale => max_component_rel_scale,
        :max_allowed_ratio => max_allowed_ratio,
        :atol => Float64(atol),
        :rtol => Float64(rtol),
        :lost_both_backends => lost_both,
        :lost_one_backend => lost_mismatch,
        :compared_coordinates => compared,
        :passed_tolerance => max_allowed_ratio <= 1.0 && lost_mismatch == 0 && compared > 0,
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

# ---------------------------------------------------------------------------
# Physics contracts (concrete AbstractPhysicsContract implementations)
# ---------------------------------------------------------------------------

"""
    SymplecticityContract(; step=3.0e-7, default_tolerance=5.0e-8, lorentz_angle=0.01)

Finite-difference symplecticity of the six-dimensional runtime maps: for each
checked element the Jacobian `J` of the map at a reference phase-space point
must satisfy `norm(J' * S * J - S) <= tol`. Covers the `Symplectic6DMap`
elements (`Linear6D`, `CrabDispersion`, `MomentumDispersion`, `XYCoupling`,
`ThinCrabCavity`, `ChromaticityKick`) and the weak-strong beam-beam maps
(`ThinStrongBeam`, `GaussianStrongBeam`, whose synchro-beam slingshot term
exists precisely to keep the sliced 6D kick symplectic). Hirata's crossing
Lorentz maps are checked separately as *quasi*-symplectic: exact inverse
transformations with Jacobian determinants `sec(angle)^3` / `cos(angle)^3`,
which must not be judged by `J' * S * J`. The stochastic radiation map is
intentionally out of scope. Mirrors `validation/symplecticity_validation.jl`.

Reading the residuals: linear maps sit at roundoff (~1e-13) because central
differences are exact for them; the nonlinear beam-beam kicks sit at ~8e-8 at
the default step, and a step scan shows that number scales exactly as
`step^2` (7.9e-10 at 3e-8 through 7.9e-4 at 3e-5) — it is the finite
difference's truncation error, not the map's defect, which is bounded below
~1e-9.
"""
Base.@kwdef struct SymplecticityContract <: AbstractPhysicsContract
    step::Float64 = 3.0e-7
    # A floor, applied as `max(case.tolerance, default_tolerance)`, so raising
    # it relaxes every case at once. It must therefore sit at or below the
    # tightest per-case tolerance, or that case's declared value never binds:
    # at the former 5.0e-7 the four 5.0e-8 linear-map cases were judged ten
    # times looser than they declare, against measured residuals of ~1.5e-13.
    default_tolerance::Float64 = 1.0e-11
    lorentz_angle::Float64 = 0.01
    # The Lorentz half's two criteria, as FIELDS (2026-08-05_b audit, U4-16).
    # They were literals in the function body -- `inverse_residual <= 1.0e-10 &&
    # determinant_error <= 2.0e-7` -- so `default_tolerance`, which the struct
    # documents as the knob, reached only the twelve case residuals and not the
    # crossing-map half of what this contract checks. A caller tightening it to
    # probe a regression saw the Lorentz verdict never move. Values unchanged;
    # they are simply reachable now, and the boost pair is quasi-symplectic by
    # construction (det = sec^3 / cos^3), so these are not the case tolerance
    # under another name and are deliberately separate knobs.
    lorentz_inverse_tolerance::Float64 = 1.0e-10
    lorentz_determinant_tolerance::Float64 = 2.0e-7
end

description(::Type{SymplecticityContract}) =
    "Checks finite-difference 6D symplecticity of the runtime maps, including the weak-strong beam-beam kicks."

"""
The single probe point every `SymplecticityContract` case is evaluated at, and
the one `validation/symplecticity_validation.jl` mirrors.

Named rather than written out three times (twice here, once in the validation
script) so the mirror cannot drift -- the same reasoning that made the case list
itself shared (2026-08-05_b audit, U24-7). Off-axis in all six coordinates, so
no term of a map can vanish by accident of the probe.
"""
const SYMPLECTICITY_PROBE_POINT = [4.0e-4, 1.0e-4, -2.0e-4, -1.5e-4, 1.2e-3, 2.0e-4]

function _symplectic_form6()
    S = zeros(Float64, 6, 6)
    for coordinate in (1, 3, 5)
        S[coordinate, coordinate + 1] = 1.0
        S[coordinate + 1, coordinate] = -1.0
    end
    return S
end

function _contract_fd_jacobian6(map, q0, step)
    q = collect(Float64, q0)
    jacobian = Matrix{Float64}(undef, 6, 6)
    for column in 1:6
        h = step * max(abs(q[column]), 1.0)
        dq = zeros(Float64, 6)
        dq[column] = h
        plus = collect(Float64, map(q .+ dq))
        minus = collect(Float64, map(q .- dq))
        jacobian[:, column] .= (plus .- minus) ./ (2h)
    end
    return jacobian
end

function _symplecticity_contract_cases()
    linear = Linear6D(Linear6DSpec{Float64}(;
        beta1=(0.8, 0.072, 90.0), beta2=(0.82, 0.075, 91.0),
        alpha1=(0.0, 0.0, 0.0), alpha2=(0.01, -0.02, 0.0),
        dmu=(0.08, 0.12, 0.02),
        zeta1=(0.002, -0.001, 0.0, 0.0), eta1=(0.001, 0.0, -0.001, 0.0),
        R1=(0.001, -0.0005, 0.0003, 0.0007),
        zeta2=(0.001, 0.0005, -0.0003, 0.0002),
        eta2=(-0.0004, 0.0001, 0.0002, -0.0001),
        R2=(0.0006, 0.0002, -0.0001, 0.0005)))
    covariance = [
        1.21e-8   1.0e-9   2.4e-9  -3.0e-10
        1.0e-9    4.0e-8   2.0e-10  1.5e-9
        2.4e-9    2.0e-10  6.4e-9  -6.0e-10
       -3.0e-10   1.5e-9  -6.0e-10  2.25e-8
    ]
    # One builder, three drifts: `ThinStrongBeamSpec` documents all three named
    # virtual drifts as "exact flows of their own Hamiltonian, so all three are
    # symplectic", and only `:hirata` was ever checked. Measured residuals are
    # identical across the three (7.908e-8 at step 3e-7, scaling as step^2), so
    # the shared Gaussian kick sets the truncation floor and the drift choice
    # adds nothing to it.
    thin_with(drift) = ThinStrongBeam(ThinStrongBeamSpec{Float64}(;
        kbb=1.0e-8, covariance=covariance, center=(2.0e-5, -1.0e-5, 3.0e-4),
        angle=(3.0e-4, -2.0e-4, 0.0), virtual_drift=drift))
    thin = thin_with(:hirata)
    gaussian = GaussianStrongBeam(GaussianStrongBeamSpec{Float64}(;
        thin=ThinStrongBeamSpec{Float64}(;
            kbb=8.0e-9, covariance=covariance, center=(-1.0e-5, 2.0e-5, -2.0e-4),
            angle=(2.0e-4, -1.0e-4, 0.0), virtual_drift=:hirata),
        ns=3, sigz=7.0e-3, slice_method=:equal_area))
    q0 = copy(SYMPLECTICITY_PROBE_POINT)
    return (
        (name=:Linear6D, element=linear, q0=q0, tolerance=5.0e-8),
        (name=:CrabDispersion,
         element=CrabDispersion(CrabDispersionSpec{Float64}(
             zeta1=0.02, zeta2=-0.01, zeta3=0.004, zeta4=0.002)),
         q0=q0, tolerance=5.0e-8),
        (name=:MomentumDispersion,
         element=MomentumDispersion(MomentumDispersionSpec{Float64}(
             eta1=0.03, eta2=-0.006, eta3=0.002, eta4=0.01)),
         q0=q0, tolerance=5.0e-8),
        (name=:XYCoupling, element=XYCoupling(0.01, -0.003, 0.002, 0.004),
         q0=q0, tolerance=5.0e-8),
        (name=:ThinCrabCavity,
         element=ThinCrabCavity{2}(197.0e6; strengthX=(1.0e-5, -2.0e-6),
             strengthY=(3.0e-6, 0.0), phase=(0.0, 0.2)),
         q0=q0, tolerance=5.0e-7),
        (name=:ChromaticityKick,
         element=ChromaticityKick(ChromaticityKickSpec{Float64}(;
             xi=(1.2, -0.8), beta=(0.82, 0.075), alpha=(0.01, -0.02),
             zeta=(0.002, -0.001, 0.0, 0.0), eta=(0.001, 0.0, -0.001, 0.0),
             R=(0.001, -0.0005, 0.0003, 0.0007))),
         q0=q0, tolerance=5.0e-6),
        (name=:ThinStrongBeam, element=thin, q0=q0, tolerance=5.0e-7),
        (name=:ThinStrongBeamChromatic, element=thin_with(:chromatic), q0=q0,
         tolerance=5.0e-7),
        (name=:ThinStrongBeamExact, element=thin_with(:exact), q0=q0,
         tolerance=5.0e-7),
        (name=:GaussianStrongBeam, element=gaussian, q0=q0, tolerance=5.0e-7),
        # The solenoid DECLARES this contract in its metadata; the tripwire in
        # `validate` fails when a declaring kind is missing from this list —
        # the declaration existed with no case and nothing noticed
        # (2026-08-05 audit, U3-3).
        (name=:Solenoid,
         element=Solenoid(SolenoidSpec(L=1.3, ks=1.7, nst=1)), q0=q0,
         tolerance=5.0e-7),
        (name=:SolenoidCurvedMultipole,
         element=Solenoid(SolenoidSpec(L=1.3, ks=1.7, h=0.18, kskew=(0.05,),
                                       nst=8)), q0=q0, tolerance=5.0e-7),
        # The other fifteen kinds that declare Symplectic6DMap (2026-08-05_b
        # audit, U4-8). Before this the list held 12 cases for 7 of the 22
        # declaring kinds, and the tripwire below derived its obligation from
        # `meta.contracts` -- a set containing exactly ONE element, :solenoid --
        # so removing any of the other eleven cases would not have tripped it.
        # The lattice magnets among these are checked against PTC, which is a
        # different claim (agreement with an external code, not
        # ||J'SJ - S|| <= tol); the thin kickers, marker and RF cavity were
        # checked by neither.
        #
        # Tolerances are ~100x the measured residual rather than the file's
        # older round numbers, so they can actually catch a break: measured
        # here, thin elements 1.3e-13, drift/quad/sext/oct/multipole 2.0e-11 to
        # 7.8e-11, sbend 2.6e-10, thin RF cavity 5.5e-11.
        (name=:Drift, element=compile_runtime(DriftSpec(L=0.35, h=0.02)),
         q0=q0, tolerance=1.0e-8),
        (name=:Quadrupole,
         element=compile_runtime(QuadrupoleSpec(L=0.4, k1=0.8, nst=2)),
         q0=q0, tolerance=1.0e-8),
        (name=:Sextupole,
         element=compile_runtime(SextupoleSpec(L=0.25, k2=6.0, nst=2)),
         q0=q0, tolerance=1.0e-8),
        (name=:Octupole,
         element=compile_runtime(OctupoleSpec(L=0.15, k3=80.0, nst=2)),
         q0=q0, tolerance=1.0e-8),
        (name=:Multipole,
         element=compile_runtime(MultipoleSpec(L=0.3, k1=0.5, k2=4.0, nst=2)),
         q0=q0, tolerance=1.0e-8),
        (name=:SBend,
         element=compile_runtime(SBendSpec(L=1.1, angle=0.05, k1=0.2, e1=0.02,
                                           e2=0.015, nst=2)),
         q0=q0, tolerance=1.0e-8),
        # beta0 DERIVED from gamma0, not chosen alongside it. This case
        # carried `beta0=0.99, gamma0=100.0` -- a pair no particle can have,
        # since gamma0 = 100 means beta0 = 0.99994999... The two conversions it
        # exercises are mutual inverses only on a consistent pair, so the
        # fixture was asking the contract to certify a map built on impossible
        # physics; it passed at 1.5e-10 by accident of how the old cancelling
        # forms were written. On the consistent pair the same case measures
        # 1.8e-13 (2026-08-05_b audit, U14-4). `ThinRFCavitySpec` now refuses
        # an inconsistent pair outright, so this fixture cannot drift back.
        (name=:ThinRFCavity,
         element=compile_runtime(ThinRFCavitySpec(197.0e6; strength=1.0e-4,
                                                  beta0=sqrt(99.0 * 101.0) / 100.0,
                                                  gamma0=100.0)),
         q0=q0, tolerance=1.0e-11),
        (name=:ThinMultipole,
         element=compile_runtime(ThinMultipoleSpec(knl=(0.0, 0.05, 1.2))),
         q0=q0, tolerance=1.0e-11),
        (name=:ThinDipole, element=compile_runtime(ThinDipoleSpec(k0l=1.0e-3)),
         q0=q0, tolerance=1.0e-11),
        (name=:ThinQuadrupole,
         element=compile_runtime(ThinQuadrupoleSpec(k1l=0.05)),
         q0=q0, tolerance=1.0e-11),
        (name=:ThinSextupole, element=compile_runtime(ThinSextupoleSpec(k2l=1.2)),
         q0=q0, tolerance=1.0e-11),
        (name=:HKicker, element=compile_runtime(HKickerSpec(hkick=1.0e-4)),
         q0=q0, tolerance=1.0e-11),
        (name=:VKicker, element=compile_runtime(VKickerSpec(vkick=1.0e-4)),
         q0=q0, tolerance=1.0e-11),
        (name=:Kicker,
         element=compile_runtime(KickerSpec(hkick=1.0e-4, vkick=-5.0e-5)),
         q0=q0, tolerance=1.0e-11),
        # Structurally trivial -- the identity is symplectic by inspection --
        # but the obligation is derived, and an exemption here would be a
        # hand-maintained hole of exactly the kind this tripwire exists to close.
        (name=:Marker, element=compile_runtime(MarkerSpec()),
         q0=q0, tolerance=1.0e-11),
    )
end

function validate(contract::SymplecticityContract; kwargs...)
    _reject_unknown_validate_kwargs(contract, kwargs)
    metrics = Dict{Symbol,Any}()
    S = _symplectic_form6()
    worst_ratio = 0.0
    all_passed = true
    cases = _symplecticity_contract_cases()
    for case in cases
        J = _contract_fd_jacobian6(q -> case.element(q...), case.q0, contract.step)
        residual = norm(transpose(J) * S * J - S, Inf)
        tolerance = max(case.tolerance, contract.default_tolerance)
        metrics[Symbol(case.name, :_residual)] = residual
        worst_ratio = max(worst_ratio, residual / tolerance)
        all_passed &= residual <= tolerance
    end

    # Hirata Lorentz crossing maps: quasi-symplectic pair.
    q0 = copy(SYMPLECTICITY_PROBE_POINT)
    forward = LorentzBoost(contract.lorentz_angle)
    reverse = RevLorentzBoost(contract.lorentz_angle)
    forward_det = det(_contract_fd_jacobian6(q -> forward(q...), q0, contract.step))
    reverse_det = det(_contract_fd_jacobian6(q -> reverse(q...), q0, contract.step))
    inverse_residual = max(
        norm(collect(reverse(forward(q0...)...)) .- q0, Inf),
        norm(collect(forward(reverse(q0...)...)) .- q0, Inf))
    determinant_error = max(abs(forward_det - sec(contract.lorentz_angle)^3),
                            abs(reverse_det - cos(contract.lorentz_angle)^3))
    metrics[:lorentz_inverse_residual] = inverse_residual
    metrics[:lorentz_determinant_error] = determinant_error
    lorentz_passed = inverse_residual <= contract.lorentz_inverse_tolerance &&
                     determinant_error <= contract.lorentz_determinant_tolerance
    all_passed &= lorentz_passed

    # Declaration↔case tripwire (2026-08-05 audit, U3-3), derived from the
    # STRUCTURAL declaration rather than the contract list (2026-08-05_b audit,
    # U4-8).
    #
    # The obligation used to be `SymplecticityContract ∈ meta.contracts`, and
    # that set was measured to be exactly `[:solenoid]` -- one kind. Eleven of
    # the twelve cases could have been deleted without tripping anything, and a
    # new symplectic element added the way the existing 21 were (declaring only
    # ElementTrackingBackendConsistencyContract) was invisible. Deriving from
    # `Symplectic6DMap ∈ meta.tracking_methods` moves the obligation from a
    # declaration nobody maintains to one the element cannot avoid making: it is
    # how the element says how it tracks. That took the guarded set from 1 kind
    # to 22, of which 7 had a case.
    uncovered = Symbol[]
    for T in registered_element_specs()
        meta = _element_meta_or_nothing(T)
        meta === nothing && continue
        any(M -> M === Symplectic6DMap, meta.tracking_methods) || continue
        RT = meta.runtime_type
        (RT !== nothing && any(case -> case.element isa RT, cases)) ||
            push!(uncovered, meta.kind)
    end
    metrics[:kinds_declaring_without_case] = length(uncovered)
    all_passed &= isempty(uncovered)

    message = if !isempty(uncovered)
        "kinds declare SymplecticityContract but have no case in the contract's list: " *
        join(sort(uncovered), ", ")
    elseif all_passed
        "All 6D runtime maps are finite-difference symplectic within tolerance; the Lorentz crossing pair is exact-inverse quasi-symplectic."
    else
        "A runtime map failed the finite-difference symplecticity check."
    end
    return ContractResult(all_passed, message; residual=worst_ratio, metrics=metrics)
end

"""
    HighEnergyWeakStrongLimitContract(; n_particles=20000, nslices=5, pic_grid=96,
                                      electron_gev=1.0e100,
                                      gaussian_atol=2.0e-14,
                                      gaussian_luminosity_rtol=2.0e-12,
                                      pic_luminosity_rtol=0.08, pic_size_rtol=0.08)

Verify the high-energy weak-strong limit of the strong-strong collision: with
the electron energy made effectively infinite, the electron beam must be
unchanged and the proton beam must receive exactly the frozen-source
weak-strong kick.

The soft-Gaussian half is held to machine precision (2e-14) against a
frozen-source reference, and what that establishes is precise: at infinite
source energy the strong-strong SCHEDULING reduces to the weak-strong
construction -- slice ordering, slice weights, `kbb`, `klum` and the virtual
drift plumbing. It is **not** an independent check of the kick itself.
`_wsl_weakstrong_reference!` calls `_slice_collision_order`,
`_slice_transverse_moments` and `_slice_slice_gaussian_kick!`, and each has
exactly one method in the package -- the same ones `_gaussian_collide_pair!`
calls. The reference differs only in loop structure, so a defect inside the
kick cancels exactly on both sides and this tolerance cannot see it. The
docstring previously called this "the analytic weak-strong reference (this is
the sharp limit statement)", which reads as a claim about the kick
(2026-08-05_b audit, U4-11).

The PIC half IS a genuine cross-implementation comparison -- a grid solver
against the soft-Gaussian construction -- and its 8% tolerance is where this
contract's independent evidence about the kick actually lives. The spectral
solvers' high-energy limit remains covered by
`validation/high_energy_weakstrong_limit.jl`, which this contract mirrors.
"""
Base.@kwdef struct HighEnergyWeakStrongLimitContract <: AbstractPhysicsContract
    n_particles::Int = 20000
    nslices::Int = 5
    pic_grid::Int = 96
    electron_gev::Float64 = 1.0e100
    gaussian_atol::Float64 = 2.0e-14
    gaussian_luminosity_rtol::Float64 = 2.0e-12
    pic_luminosity_rtol::Float64 = 0.08
    pic_size_rtol::Float64 = 0.08
end

description(::Type{HighEnergyWeakStrongLimitContract}) =
    "Checks that the strong-strong collision reduces to the frozen-source weak-strong kick at infinite source energy."

function _wsl_clone_cpu_beam(beam)
    rep = Phase6DRep((copy(Array(a)) for a in coordinate_arrays(beam.rep))...)
    return Beam{CPUThreadsBackend,typeof(beam.params),typeof(rep)}(beam.params, rep)
end

_wsl_mean(values) = sum(values) / length(values)

function _wsl_centered_rms(rep)
    return [begin
        center = _wsl_mean(a)
        sqrt(_wsl_mean(abs2.(a .- center)))
    end for a in coordinate_arrays(rep)]
end

_wsl_max_abs(rep_a, rep_b) =
    maximum(maximum(abs.(Array(a) .- Array(b)))
            for (a, b) in zip(coordinate_arrays(rep_a), coordinate_arrays(rep_b)))

function _wsl_weakstrong_reference!(source, probe, solver)
    slices_source = longitudinal_slices(source.rep, solver.slicing1)
    slices_probe = longitudinal_slices(probe.rep, solver.slicing2)
    kbb = _strong_strong_kbb2(solver, source, probe)
    _, klum_probe = _strong_strong_luminosity_scales(solver, source, probe)
    luminosity = zero(eltype(probe.rep.x))
    for (_, i, j) in _slice_collision_order(slices_source, slices_probe)
        moments = _slice_transverse_moments(
            source.rep, slices_source.indices[i],
            solver.ignore_centroid1, solver.min_sigma,
            Val(solver.include_sigma_xy))
        luminosity += _slice_slice_gaussian_kick!(
            probe.rep, slices_probe.indices[j],
            moments, slices_source.center[i],
            slices_source.weight[i] * kbb,
            slices_source.weight[i] * klum_probe,
            solver.min_sigma, solver.virtual_drift,
            Val(solver.longitudinal_kick), true)
    end
    return luminosity
end

function validate(contract::HighEnergyWeakStrongLimitContract; kwargs...)
    _reject_unknown_validate_kwargs(contract, kwargs)
    metrics = Dict{Symbol,Any}()
    # The global RNG is contract input, not contract property: save and
    # restore it, as every other RNG-touching contract in this file does
    # (2026-08-05 audit, U3-1: this validate left its fixed seed behind
    # for whatever ran next).
    old_seed = global_rng_seed()
    old_method = global_rng_method()
    try
        set_global_rng!(seed=0x123456789abcdef, method=:philox)
        electron = Beam(contract.n_particles, CPUThreadsBackend, Float64;
            beta=(0.55, 0.056, 0.7e-2 / 5.5e-4), alpha=(0.0, 0.0, 0.0),
            sigma=(106e-6, 9.5e-6, 0.7e-2), cutoff=5.0, rng_id=11,
            charge=-1.0, mc2=EMASS_EV, E0=contract.electron_gev * 1.0e9,
            r0=RE, npart=1.7203e11)
        proton = Beam(contract.n_particles, CPUThreadsBackend, Float64;
            beta=(0.8, 0.072, 6e-2 / 6.6e-4), alpha=(0.0, 0.0, 0.0),
            sigma=(95e-6, 8.5e-6, 6e-2), cutoff=5.0, rng_id=12,
            charge=1.0, mc2=PMASS_EV, E0=275e9,
            r0=RE * ME0 / PMASS_EV, npart=0.6881e11)
        slicing = LongitudinalSlicing(
            method=:normal_quantile, nslices=contract.nslices, center_position=:centroid)
        gaussian = GaussianPoissonSolver(
            slicing=slicing, virtual_drift=:hirata, include_sigma_xy=false,
            gaussian_when_luminosity=1, batch_mode=:wavefront)
        pic = PICPoissonSolver(
            slicing=slicing, grid=(contract.pic_grid, contract.pic_grid),
            deposit_method=:CIC, green_type=:integrated, green_cache=:slice_pair,
            longitudinal_kick=true, batch_mode=:wavefront)

        reference_electron = _wsl_clone_cpu_beam(electron)
        reference_proton = _wsl_clone_cpu_beam(proton)
        reference_luminosity = _wsl_weakstrong_reference!(
            reference_electron, reference_proton, gaussian)

        gaussian_electron = _wsl_clone_cpu_beam(electron)
        gaussian_proton = _wsl_clone_cpu_beam(proton)
        gaussian_luminosity = collide!(gaussian, gaussian_electron, gaussian_proton,
                                       CPUThreadsBackend)
        pic_electron = _wsl_clone_cpu_beam(electron)
        pic_proton = _wsl_clone_cpu_beam(proton)
        pic_luminosity = collide!(pic, pic_electron, pic_proton, CPUThreadsBackend)

        gaussian_proton_error = _wsl_max_abs(gaussian_proton.rep, reference_proton.rep)
        gaussian_electron_change = _wsl_max_abs(gaussian_electron.rep, electron.rep)
        gaussian_lum_rel = abs(gaussian_luminosity - reference_luminosity) /
            max(abs(reference_luminosity), eps(Float64))
        reference_rms = _wsl_centered_rms(reference_proton.rep)
        pic_size_rel = maximum(abs.(_wsl_centered_rms(pic_proton.rep) .- reference_rms) ./
                               max.(reference_rms, eps(Float64)))
        pic_lum_rel = abs(pic_luminosity - reference_luminosity) /
            max(abs(reference_luminosity), eps(Float64))

        metrics[:gaussian_proton_max_abs_error] = gaussian_proton_error
        metrics[:gaussian_electron_max_abs_change] = gaussian_electron_change
        metrics[:gaussian_luminosity_relative_error] = gaussian_lum_rel
        metrics[:pic_luminosity_relative_error] = pic_lum_rel
        metrics[:pic_proton_size_relative_error] = pic_size_rel
        metrics[:n_particles] = contract.n_particles

        gaussian_passed = gaussian_proton_error <= contract.gaussian_atol &&
                          gaussian_electron_change <= contract.gaussian_atol &&
                          gaussian_lum_rel <= contract.gaussian_luminosity_rtol
        pic_passed = pic_lum_rel <= contract.pic_luminosity_rtol &&
                     pic_size_rel <= contract.pic_size_rtol
        passed = gaussian_passed && pic_passed
        message = passed ?
            "Strong-strong collisions reduce to the frozen-source weak-strong kick at infinite source energy (soft-Gaussian exact; PIC within model tolerance)." :
            "The high-energy weak-strong limit failed (soft-Gaussian exactness or PIC model tolerance)."
        return ContractResult(passed, message;
                              residual=max(gaussian_proton_error, pic_lum_rel),
                              metrics=metrics)
    finally
        set_global_rng!(seed=old_seed, method=old_method)
    end
end

"""
    CoherentModePhysicsContract(; solver=:pic, turns=1024, n_macro=20000,
                                grid=(64, 64), xi_target=0.005,
                                offset_sigma=0.1, tune=(0.31, 0.32),
                                lambda_band=(1.12, 1.30),
                                sigma_mode_atol=2.0e-4)

Coherent beam-beam mode physics for one solver: two identical round e+ e-
beams collide at one IP (single slice, rigid linear lattice); beam 1 is
launched with a small dipole offset; the sigma/pi mode tunes come from
Hann-windowed FFTs of the sum/difference centroid signals. The contract states
the *physics*, per plane:

- the sigma mode sits at the bare tune (unshifted for identical beams);
- the Yokoya factor `Lambda = (Q_pi - Q_sigma)/xi` falls inside the
  self-consistent Vlasov band (1.2-1.3 at converged settings, round beams at
  the low end; the default band is widened for the contract's reduced turn
  count).

`solver` selects what is judged against that physics: `:pic`
(`PICPoissonSolver`), `:gaussian_pic` (`GaussianPICPoissonSolver`), or
`:gaussian` (`GaussianPoissonSolver`). The PIC-based solvers pass. The
soft-Gaussian solver **fails, and is expected to fail**: a moment closure
cannot carry the pi mode beyond the rigid-bunch value (it measures
Lambda ~ 1.10, below the Vlasov band) — the pi-mode excess is carried by
distribution-shape feedback the closure does not represent. The regression
suite asserts this failure as the documented model limitation; it is a
statement about the model, not a defect in the solver implementation.

Mirrors `validation/coherent_beam_beam_modes.jl` (full-resolution first run:
PIC Lambda = 1.199/1.206 x/y, GaussianPIC 1.200/1.207, soft-Gaussian
1.096/1.101, against the round-beam Vlasov value ~1.2 of Yokoya & Koiso and a
BeamBeam3D cross-code run at 1.197/1.210). The symmetric configuration is
essential: the Vlasov band applies to equal beams, tunes, and xi.
"""
Base.@kwdef struct CoherentModePhysicsContract <: AbstractPhysicsContract
    solver::Symbol = :pic
    turns::Int = 1024
    n_macro::Int = 20000
    grid::Tuple{Int,Int} = (64, 64)
    xi_target::Float64 = 0.005
    offset_sigma::Float64 = 0.1
    tune::Tuple{Float64,Float64} = (0.31, 0.32)
    lambda_band::Tuple{Float64,Float64} = (1.12, 1.30)
    sigma_mode_atol::Float64 = 2.0e-4
end

description(::Type{CoherentModePhysicsContract}) =
    "Checks that a strong-strong solver reproduces the Vlasov-band coherent-mode Yokoya factor (moment closures fail by design)."

function _coherent_fractional_tune(signal)
    n = length(signal)
    center = _wsl_mean(signal)
    w = [0.5 - 0.5 * cospi(2 * (i - 1) / n) for i in 1:n]
    a = abs.(FFTW.rfft((signal .- center) .* w))
    interior = 2:(length(a) - 1)
    k = interior[argmax(view(a, interior))]
    y1, y2, y3 = a[k - 1], a[k], a[k + 1]
    denom = y1 - 2y2 + y3
    delta = denom == 0 ? 0.0 : 0.5 * (y1 - y3) / denom
    return (k - 1 + delta) / n
end

function _coherent_mode_lambdas(contract::CoherentModePhysicsContract, kind::Symbol)
    set_global_rng!(seed=20260727, method=:philox)
    policy = CPUThreadsExecutionPolicy()
    beta = (0.55, 0.55, 0.7e-2 / 5.5e-4)
    sigma = (106.0e-6, 106.0e-6, 0.7e-2)
    energy = 10.0e9
    gamma_rel = energy / EMASS_EV
    r0 = RE * ME0 / EMASS_EV
    npart = contract.xi_target * 4pi * gamma_rel * sigma[1]^2 / (r0 * beta[1])
    xi = (npart * r0 * beta[1] / (4pi * gamma_rel * sigma[1]^2),
          npart * r0 * beta[2] / (4pi * gamma_rel * sigma[2]^2))

    offset1 = (contract.offset_sigma * sigma[1], 0.0,
               contract.offset_sigma * sigma[2], 0.0, 0.0, 0.0)
    beam1 = Beam(contract.n_macro, policy, Float64;
        beta=beta, alpha=(0.0, 0.0, 0.0), sigma=sigma, cutoff=5.0, rng_id=1,
        charge=-1.0, mc2=EMASS_EV, E0=energy, r0=r0, npart=npart,
        initial_offset=offset1)
    beam2 = Beam(contract.n_macro, policy, Float64;
        beta=beta, alpha=(0.0, 0.0, 0.0), sigma=sigma, cutoff=5.0, rng_id=2,
        charge=+1.0, mc2=EMASS_EV, E0=energy, r0=r0, npart=npart)

    slicing = LongitudinalSlicing(; method=:normal_quantile, nslices=1,
                                  center_position=:centroid)
    solver = if kind === :gaussian
        GaussianPoissonSolver(; slicing=slicing, longitudinal_kick=false)
    elseif kind === :pic
        PICPoissonSolver(; slicing=slicing, grid=contract.grid,
            deposit_method=:CIC, green_type=:integrated,
            green_cache=:slice_pair, longitudinal_kick=false)
    elseif kind === :gaussian_pic
        GaussianPICPoissonSolver(; slicing=slicing, grid=contract.grid,
            longitudinal_kick=false)
    else
        throw(ArgumentError(
            "CoherentModePhysicsContract solver must be :pic, :gaussian_pic, " *
            "or :gaussian; got $(kind)"))
    end
    ip = StrongStrongCollision(:ip; poisson_solver=solver)
    one_turn = Linear6DSpec{Float64}(;
        beta1=beta, beta2=beta, alpha1=(0.0, 0.0, 0.0), alpha2=(0.0, 0.0, 0.0),
        dmu=2pi .* (contract.tune[1], contract.tune[2], -0.01))
    task = StrongStrongTask((ip, one_turn), (ip, one_turn); policy=policy)

    n = contract.turns
    x1 = Vector{Float64}(undef, n); x2 = Vector{Float64}(undef, n)
    y1 = Vector{Float64}(undef, n); y2 = Vector{Float64}(undef, n)
    for t in 1:n
        execute!(task, beam1, beam2; turns=1)
        x1[t] = _wsl_mean(beam1.rep.x); x2[t] = _wsl_mean(beam2.rep.x)
        y1[t] = _wsl_mean(beam1.rep.y); y2[t] = _wsl_mean(beam2.rep.y)
    end
    out = Dict{Symbol,Any}()
    for (plane, c1, c2, q0, xip) in ((:x, x1, x2, contract.tune[1], xi[1]),
                                     (:y, y1, y2, contract.tune[2], xi[2]))
        q_sigma = _coherent_fractional_tune(c1 .+ c2)
        q_pi = _coherent_fractional_tune(c1 .- c2)
        out[Symbol(plane, :_sigma_drift)] = q_sigma - q0
        out[Symbol(plane, :_lambda)] = (q_pi - q_sigma) / xip
    end
    return out
end

function validate(contract::CoherentModePhysicsContract; kwargs...)
    _reject_unknown_validate_kwargs(contract, kwargs)
    metrics = Dict{Symbol,Any}()
    # Save/restore the global RNG around _coherent_mode_lambdas, which
    # seeds it (2026-08-05 audit, U3-1).
    old_seed = global_rng_seed()
    old_method = global_rng_method()
    try
        result = _coherent_mode_lambdas(contract, contract.solver)
        metrics[:solver] = contract.solver
        passed = true
        worst_drift = 0.0
        for plane in (:x, :y)
            lambda = result[Symbol(plane, :_lambda)]
            drift = result[Symbol(plane, :_sigma_drift)]
            metrics[Symbol(:lambda_, plane)] = lambda
            metrics[Symbol(:sigma_drift_, plane)] = drift
            worst_drift = max(worst_drift, abs(drift))
            passed &= contract.lambda_band[1] <= lambda <= contract.lambda_band[2]
        end
        passed &= worst_drift <= contract.sigma_mode_atol
        message = passed ?
            "The $(contract.solver) solver reproduces the Vlasov-band coherent-mode Yokoya factor with the sigma mode unshifted." :
            "The $(contract.solver) solver does not reproduce the Vlasov-band Yokoya factor (expected for moment-closure solvers: the pi-mode excess over the rigid value requires distribution-shape feedback)."
        return ContractResult(passed, message; residual=worst_drift, metrics=metrics)
    finally
        set_global_rng!(seed=old_seed, method=old_method)
    end
end

"""
    PTCConsistencyContract(; path=nothing, atol=Dict(), default_atol=1e-11)

Compare `LatticeMagnet` tracking against a committed PTC reference table.

PTC is Forest's code, distributed inside MAD-X, and it uses convention #3
natively under `TIME=FALSE` -- the same longitudinal pair Octopus tracks -- so a
comparison needs no coordinate conversion and cannot hide a convention error
inside one. The reference is generated once by
`validation/generate_ptc_reference.jl` and committed, so this contract runs
without MAD-X installed.

The table stores Octopus coordinates: PTC's `T` column is negated on write,
because its longitudinal variable is conjugate to `delta` with the opposite
orientation (theory note Sections 2.1, 5.3, 6.4).

`atol` overrides the tolerance per case name; `_PTC_DEFAULT_ATOL` is the
hook for future per-case defaults and is currently EMPTY, so every case runs
at `default_atol = 1e-11` unless overridden (this docstring once pointed at
"per-case defaults below" that never existed; 2026-08-05 audit, U3-9).
Agreement is not uniform across elements and the differences are physical,
not numerical -- see `docs/theory/lattice_hamiltonian_and_conventions.md`.
"""
Base.@kwdef struct PTCConsistencyContract <: AbstractImplementationContract
    path::Union{Nothing,String} = nothing
    default_atol::Float64 = 1e-11
    atol::Dict{String,Float64} = Dict{String,Float64}()
end

"Specs matching the cases in the committed PTC reference table."
function _ptc_reference_specs()
    return Dict{String,Any}(
        "drift" => DriftSpec(L=0.7),
        # Both polarities: a solenoid sign error is invisible in anything even
        # in ks, so one working point proves nothing. See docs/theory/solenoid.md.
        "solenoid_pos" => SolenoidSpec(L=1.3, ks=0.35),
        "solenoid_neg" => SolenoidSpec(L=1.3, ks=-0.35),
        "solenoid_strong" => SolenoidSpec(L=2.0, ks=1.7),
        # Strang splitting against PTC's KICK_SOL/KICKMUL interleave. Two step
        # counts, so the comparison tests convergence rather than one lucky
        # working point.
        "solenoid_k1_n8" => SolenoidSpec(L=1.3, ks=0.35, k1=0.6, nst=8),
        "solenoid_k1_n32" => SolenoidSpec(L=1.3, ks=0.35, k1=0.6, nst=32),
        "quadrupole_m2_n1" => QuadrupoleSpec(L=0.4, kn=(0.0, 1.7), nst=1, integrator_order=2),
        "quadrupole_m2_n8" => QuadrupoleSpec(L=0.4, kn=(0.0, 1.7), nst=8, integrator_order=2),
        "quadrupole_m4_n3" => QuadrupoleSpec(L=0.4, kn=(0.0, 1.7), nst=3, integrator_order=4),
        "quadrupole_skew" => QuadrupoleSpec(L=0.4, ks=(0.0, 0.9), nst=4, integrator_order=2),
        "sextupole_m2_n4" => SextupoleSpec(L=0.25, kn=(0.0, 0.0, 14.0), nst=4, integrator_order=2),
        "sextupole_m4_n2" => SextupoleSpec(L=0.25, kn=(0.0, 0.0, 14.0), nst=2, integrator_order=4),
        "octupole_m2_n4" => OctupoleSpec(L=0.15, kn=(0.0, 0.0, 0.0, 220.0), nst=4, integrator_order=2),
        "multipole_m2_n4" => MultipoleSpec(L=0.3, kn=(0.0, 1.2, 8.0), nst=4,
                                           integrator_order=2),
        "multipole_m4_n2" => MultipoleSpec(L=0.3, kn=(0.0, 1.2, 8.0, 90.0), nst=2,
                                           integrator_order=4),
        # Two settings are required for a bend to match PTC, and both are
        # physics rather than tuning. MODEL=1 splits a bend into curved drift
        # plus dipole kick, so bend_model must match. And PTC applies the
        # hard-edge dipole fringe at both faces of an exact bend regardless of
        # the pole-face angle -- it is Maxwell-required, and omitting it leaves
        # a bend exact on axis but wrong at transverse amplitude.
        "sbend_m2_n1" => SBendSpec(L=1.1, h=0.18, b0=0.18, nst=1,
                                   bend_model=:drift_kick, bend_fringe=true),
        "sbend_m2_n4" => SBendSpec(L=1.1, h=0.18, b0=0.18, nst=4,
                                   bend_model=:drift_kick, bend_fringe=true),
        "sbend_m4_n2" => SBendSpec(L=1.1, h=0.18, b0=0.18, nst=2, integrator_order=4,
                                   bend_model=:drift_kick, bend_fringe=true),
        "cfbend_m2_n4" => SBendSpec(L=1.1, h=0.18, b0=0.18, kn=(0.0, 0.6), nst=4,
                                    bend_model=:drift_kick, bend_fringe=true),
        "cfbend_m4_n2" => SBendSpec(L=1.1, h=0.18, b0=0.18, kn=(0.0, 0.6, 5.0), nst=2,
                                    integrator_order=4,
                                    bend_model=:drift_kick, bend_fringe=true),
        # Hard-edge multipole fringe. `highest_fringe=2` is PTC's own
        # HIGHEST_FRINGE default, not a tuning knob: without it the comparison
        # would include sextupole and higher fringe terms that PTC truncates.
        "quadrupole_fringe" => QuadrupoleSpec(L=0.4, k1=1.7, nst=4,
                                              fringe=:multipole, highest_fringe=2),
        "multipole_fringe" => MultipoleSpec(L=0.3, k1=1.2, k2=8.0, nst=4,
                                            fringe=:multipole, highest_fringe=2),
        # A pure dipole has one multipole order, so PTC skips the multipole
        # fringe entirely (NMUL<=1); with bend_model=:drift_kick the dipole sits
        # in kn[1], which is exactly the case that used to be double-counted.
        "sbend_fringe" => SBendSpec(L=1.1, angle=0.198, nst=4,
                                    bend_model=:drift_kick, bend_fringe=true,
                                    fringe=:multipole, highest_fringe=2),
        "cfbend_fringe" => SBendSpec(L=1.1, angle=0.198, k1=0.6, nst=4,
                                     bend_model=:drift_kick, bend_fringe=true,
                                     fringe=:multipole, highest_fringe=2),
        # Pole-face angles. Fringes off, which selects PTC's MAD8_WEDGE branch,
        # so wedge_coeff keeps its (1,2) default.
        "sbend_edge" => SBendSpec(L=1.1, angle=0.198, e1=0.1, e2=0.1, nst=4,
                                  bend_model=:drift_kick, bend_fringe=true),
        "cfbend_edge" => SBendSpec(L=1.1, angle=0.198, k1=0.6, e1=0.1, e2=0.1, nst=4,
                                   bend_model=:drift_kick, bend_fringe=true),
        "sbend_fint" => SBendSpec(L=1.1, angle=0.198, e1=0.1, e2=0.1,
                                  fint1=0.5, fint2=0.5, hgap1=0.03, hgap2=0.03, nst=4,
                                  bend_model=:drift_kick, bend_fringe=true),
        # Misalignments, one degree of freedom each. MAD-X references a
        # misalignment to the ENTRANCE frame (MAD_MISALIGN_FIBRE), not the
        # centre, so these pin misalign_convention = :madx along with the
        # keyword mapping. One rotation at a time cannot distinguish the two
        # composition orders, which agree there; the cases that separate them
        # are quad_mis_all and cfbend_mis_all below.
        "quad_mis_dx" => QuadrupoleSpec(L=0.4, k1=1.7, nst=4,
                                        misalign_convention=:madx, x_offset=1.0e-3),
        "quad_mis_dy" => QuadrupoleSpec(L=0.4, k1=1.7, nst=4,
                                        misalign_convention=:madx, y_offset=-8.0e-4),
        "quad_mis_ds" => QuadrupoleSpec(L=0.4, k1=1.7, nst=4,
                                        misalign_convention=:madx, z_offset=2.0e-3),
        "quad_mis_dtheta" => QuadrupoleSpec(L=0.4, k1=1.7, nst=4,
                                            misalign_convention=:madx, x_pitch=3.0e-3),
        "quad_mis_dphi" => QuadrupoleSpec(L=0.4, k1=1.7, nst=4,
                                          misalign_convention=:madx, y_pitch=3.0e-3),
        "quad_mis_dpsi" => QuadrupoleSpec(L=0.4, k1=1.7, nst=4,
                                          misalign_convention=:madx, tilt=0.03),
        "sext_mis_dx" => SextupoleSpec(L=0.25, k2=14.0, nst=4,
                                       misalign_convention=:madx, x_offset=1.0e-3),
        # All six together, which is the only thing that distinguishes MAD-X's
        # intrinsic R_z R_x R_y composition from Bmad's fixed-axis R_y R_x R_z.
        "quad_mis_all" => QuadrupoleSpec(L=0.4, k1=1.7, nst=4, misalign_convention=:madx,
                                         x_offset=1.0e-3, y_offset=-8.0e-4, z_offset=2.0e-3,
                                         x_pitch=1.0e-3, y_pitch=-7.0e-4, tilt=0.02),
        # Misaligned bends. The survey follows h, so the exit transform is built
        # from a design frame that has turned by hL since the entrance.
        "cfbend_mis_dx" => SBendSpec(L=1.1, angle=0.198, k1=0.6, nst=4,
                                     bend_model=:drift_kick, bend_fringe=true,
                                     misalign_convention=:madx, x_offset=1.0e-3),
        "cfbend_mis_all" => SBendSpec(L=1.1, angle=0.198, k1=0.6, nst=4,
                                      bend_model=:drift_kick, bend_fringe=true,
                                      misalign_convention=:madx,
                                      x_offset=1.0e-3, y_offset=-8.0e-4, z_offset=2.0e-3,
                                      x_pitch=1.0e-3, y_pitch=-7.0e-4, tilt=0.02),
        # ref_tilt: the design-orbit roll, which MAD-X spells as the bend's own
        # `tilt` keyword. Note what these specs do NOT say -- `tilt=0.3` would
        # be a body roll and a different magnet. Getting that mapping backwards
        # is the whole reason these cases exist.
        "sbend_reftilt" => SBendSpec(L=1.1, angle=0.198, nst=4,
                                     bend_model=:drift_kick, bend_fringe=true,
                                     ref_tilt=0.3),
        # A vertical bend: inexpressible before ref_tilt existed, and the case
        # a sign error cannot survive, since the dispersion moves plane.
        "sbend_reftilt_vertical" => SBendSpec(L=1.1, angle=0.198, nst=4,
                                              bend_model=:drift_kick, bend_fringe=true,
                                              ref_tilt=pi / 2),
        "cfbend_reftilt" => SBendSpec(L=1.1, angle=0.198, k1=0.6, nst=4,
                                      bend_model=:drift_kick, bend_fringe=true,
                                      ref_tilt=0.3),
        # The ordering cases. `ref_tilt` composes OUTSIDE the misalignment, so
        # the body error is taken relative to the already-rolled design orbit;
        # MAD_MISALIGN_FIBRE displaces a fibre whose frames already carry the
        # tilt. Both parameters must be nonzero for the composition order to be
        # observable at all, which is why there is no one-parameter version.
        "cfbend_reftilt_mis_dx" => SBendSpec(L=1.1, angle=0.198, k1=0.6, nst=4,
                                             bend_model=:drift_kick, bend_fringe=true,
                                             ref_tilt=0.3,
                                             misalign_convention=:madx, x_offset=1.0e-3),
        "cfbend_reftilt_mis_all" => SBendSpec(L=1.1, angle=0.198, k1=0.6, nst=4,
                                              bend_model=:drift_kick, bend_fringe=true,
                                              ref_tilt=0.3, misalign_convention=:madx,
                                              x_offset=1.0e-3, y_offset=-8.0e-4,
                                              z_offset=2.0e-3, x_pitch=1.0e-3,
                                              y_pitch=-7.0e-4, tilt=0.02),
        # A spread of roll angles. The map has no branch and no quadrant logic,
        # so these test MAD-X's freedom to normalise or special-case `tilt` more
        # than they test ours. `quarter` is the angle where cos = sin and a swap
        # of the two would hide; `neg_mis_all` repeats the ordering case at a
        # negative roll, where a sign slip in the R_z(-psi) conjugation would
        # survive every positive-angle case above.
        "sbend_reftilt_neg" => SBendSpec(L=1.1, angle=0.198, nst=4,
                                         bend_model=:drift_kick, bend_fringe=true,
                                         ref_tilt=-0.7),
        "cfbend_reftilt_quarter" => SBendSpec(L=1.1, angle=0.198, k1=0.6, nst=4,
                                              bend_model=:drift_kick, bend_fringe=true,
                                              ref_tilt=pi / 4),
        "sbend_reftilt_obtuse" => SBendSpec(L=1.1, angle=0.198, nst=4,
                                            bend_model=:drift_kick, bend_fringe=true,
                                            ref_tilt=2.4),
        "sbend_reftilt_pi" => SBendSpec(L=1.1, angle=0.198, nst=4,
                                        bend_model=:drift_kick, bend_fringe=true,
                                        ref_tilt=pi),
        "sbend_reftilt_small" => SBendSpec(L=1.1, angle=0.198, nst=4,
                                           bend_model=:drift_kick, bend_fringe=true,
                                           ref_tilt=1.0e-3),
        "cfbend_reftilt_neg_mis_all" => SBendSpec(L=1.1, angle=0.198, k1=0.6, nst=4,
                                                  bend_model=:drift_kick, bend_fringe=true,
                                                  ref_tilt=-0.7, misalign_convention=:madx,
                                                  x_offset=1.0e-3, y_offset=-8.0e-4,
                                                  z_offset=2.0e-3, x_pitch=1.0e-3,
                                                  y_pitch=-7.0e-4, tilt=0.02),
        # RBEND is the sector-bend map with angle/2 on each face.
        "rbend" => RBendSpec(L=1.1, angle=0.198, nst=4,
                             bend_model=:drift_kick, bend_fringe=true),
        "rbend_k1" => RBendSpec(L=1.1, angle=0.198, k1=0.6, nst=4,
                                bend_model=:drift_kick, bend_fringe=true),
        # A rolled RBEND reaches the sector map through the angle/2 face
        # conversion, so the roll has to survive that and compose with the
        # resulting pole faces. Tested rather than inherited from the SBEND.
        "rbend_reftilt" => RBendSpec(L=1.1, angle=0.198, nst=4,
                                     bend_model=:drift_kick, bend_fringe=true,
                                     ref_tilt=0.3),
        "rbend_reftilt_vertical" => RBendSpec(L=1.1, angle=0.198, nst=4,
                                              bend_model=:drift_kick, bend_fringe=true,
                                              ref_tilt=pi / 2),
        "rbend_k1_reftilt_mis_all" => RBendSpec(L=1.1, angle=0.198, k1=0.6, nst=4,
                                                bend_model=:drift_kick, bend_fringe=true,
                                                ref_tilt=0.3, misalign_convention=:madx,
                                                x_offset=1.0e-3, y_offset=-8.0e-4,
                                                z_offset=2.0e-3, x_pitch=1.0e-3,
                                                y_pitch=-7.0e-4, tilt=0.02),
        # Thin elements: MAD-X MULTIPOLE, integrated strengths.
        "thin_multipole" => [ThinMultipoleSpec(knl=(0.0, 0.05, 1.2)), DriftSpec(L=0.2)],
        "thin_multipole_skew" => [ThinMultipoleSpec(knl=(0.0, 0.05), ksl=(0.0, 0.0, 0.8)), DriftSpec(L=0.2)],
    )
end

const _PTC_DEFAULT_ATOL = Dict{String,Float64}()

function _ptc_reference_path(contract::PTCConsistencyContract)
    contract.path !== nothing && return contract.path
    # @__DIR__ rather than pkgdir, so the contract resolves whether Octopus was
    # loaded as a package or by include.
    dir = normpath(joinpath(@__DIR__, "..", "..", "validation", "reference"))
    isdir(dir) || return nothing
    files = filter(f -> startswith(f, "ptc_madx_") && endswith(f, ".tsv"), readdir(dir))
    isempty(files) && return nothing
    # Newest by NUMERIC version fields, not lexicographic: as strings,
    # "5.10" sorts before "5.09" and a newer table would be silently
    # shadowed (2026-08-05 audit, U21-7).
    natkey(f) = [something(tryparse(Int, m.match), 0) for m in eachmatch(r"\d+", f)]
    return joinpath(dir, last(sort(files; by=natkey)))
end

function validate(contract::PTCConsistencyContract; kwargs...)
    _reject_unknown_validate_kwargs(contract, kwargs)
    path = _ptc_reference_path(contract)
    if path === nothing || !isfile(path)
        return ContractResult(:skipped,
            "no committed PTC reference table found; regenerate with " *
            "validation/generate_ptc_reference.jl on a machine with MAD-X")
    end
    specs = _ptc_reference_specs()
    version = "unknown"
    worst = Dict{String,Float64}()
    rows = 0
    for line in eachline(path)
        if startswith(line, "#")
            m = match(r"MAD-X version:\s*(\S+)", line)
            m === nothing || (version = m.captures[1])
            continue
        end
        startswith(line, "case") && continue
        isempty(strip(line)) && continue
        f = split(line, '\t')
        length(f) == 14 || continue
        name = f[1]
        haskey(specs, name) || continue
        v = parse.(Float64, f[3:14])
        # A case may name one spec or a short line: MAD-X cannot hold a
        # zero-length sequence, so a thin element is referenced as itself
        # followed by a drift.
        entry = specs[name]
        line = entry isa AbstractVector ? entry : (entry,)
        out = collect(foldl((c, s) -> compile_runtime(s)(c...), line;
                            init=(v[1], v[2], v[3], v[4], v[5], v[6])))
        worst[name] = max(get(worst, name, 0.0), maximum(abs, out .- v[7:12]))
        rows += 1
    end
    rows == 0 && return ContractResult(false, "PTC reference table $(path) had no usable rows")
    # Every declared spec must have been compared. The row loop skips a name the
    # table does not carry (`haskey(specs, name) || continue`), which is right
    # for a stale row but silently narrows coverage when a spec is added and the
    # table is not regenerated -- and the contract would still report PASS on
    # the cases that remain. Coverage was 55 of 55 when this was added.
    untested = sort!(collect(setdiff(keys(specs), keys(worst))))
    isempty(untested) || return ContractResult(false,
        "PTC reference table $(path) has no rows for $(length(untested)) declared " *
        "case(s): " * join(untested, ", ") * ". Regenerate it with " *
        "validation/generate_ptc_reference.jl on a machine with MAD-X.")

    failures = String[]
    for (name, d) in worst
        tol = get(contract.atol, name, get(_PTC_DEFAULT_ATOL, name, contract.default_atol))
        d <= tol || push!(failures, "$(name): $(d) > $(tol)")
    end
    metrics = Dict{Symbol,Any}(:madx_version => version, :rows => rows,
                               :cases => length(worst),
                               :max_deviation => maximum(values(worst)))
    for (name, d) in worst
        metrics[Symbol("dev_", name)] = d
    end
    isempty(failures) && return ContractResult(true,
        "matches PTC (MAD-X $(version)) across $(length(worst)) cases, " *
        "worst deviation $(round(maximum(values(worst)); sigdigits=3))";
        residual=maximum(values(worst)), metrics=metrics)
    return ContractResult(false,
        "PTC comparison (MAD-X $(version)) failed: " * join(failures, "; ");
        residual=maximum(values(worst)), metrics=metrics)
end


"""
    ElementParameterEffectivenessContract(; probes=DEFAULT_ELEMENT_PARAM_PROBES,
                                          inactive=DEFAULT_INACTIVE_ELEMENT_PARAMS,
                                          atol=0.0)

Check that every declared element parameter reaches the compiled map.

For each element kind with a probe, this builds a representative element
**through its friendly constructor**, perturbs one declared parameter at a time,
compiles, and tracks a test particle. A parameter whose perturbation leaves the
coordinates bitwise identical is declared but not consumed -- the failure mode
AGENTS.md calls a silently ignored non-default request, and exactly what let
thin elements accept `x_offset` and drop it while `validate_element_metadata`
still passed. Metadata validation checks that a parameter is declared and
documented, not that anything reads it; this closes that gap mechanically.

Construction goes through the friendly constructor on purpose. Several
parameters are construction-time sugar -- `k1` folds into `kn`, `angle` into
`h`/`b0` -- and setting them on a raw `ElementSpec` correctly does nothing, so a
raw probe would report a design property as a defect.

`probes` gives the base keywords per kind, chosen so conditional parameters are
in a configuration where they can act: `va` needs a soft-edge fringe enabled,
`wedge_coeff` needs both a pole-face angle and a quadrupole component. A kind
with no probe is skipped and counted, rather than silently passing.

`inactive` lists `(kind, parameter)` pairs that are genuinely inert and must say
why -- a drift's `nst` is the honest example, since an exact map has no steps.
"""
const DEFAULT_ELEMENT_PARAM_PROBES = Dict{Symbol,Any}(
    :drift => (L=0.7, h=0.05),
    :quadrupole => (L=0.4, k1=1.7, nst=2, fringe=:all, va=0.03, vs=1.0e-4,
                    highest_fringe=1, x_offset=1.0e-3),
    :sextupole => (L=0.25, kn=(0.0, 1.2, 14.0), nst=2, fringe=:all, va=0.03, vs=1.0e-4,
                   highest_fringe=1, x_offset=1.0e-3),
    :octupole => (L=0.15, kn=(0.0, 1.2, 0.0, 220.0), nst=2, fringe=:all, va=0.03, vs=1.0e-4,
                  highest_fringe=1, x_offset=1.0e-3),
    :multipole => (L=0.3, k1=1.2, k2=8.0, nst=2, fringe=:all, va=0.03, vs=1.0e-4,
                   highest_fringe=1, x_offset=1.0e-3),
    # `highest_fringe = 2`, not 1. At 1 the multipole fringe is capped below the
    # quadrupole order, so `fringe` in {:none, :multipole, :soft_quad, :all} all
    # compile to a BITWISE IDENTICAL map -- measured 0.0 difference for all four
    # -- which violates this table's own stated rule that probes are "chosen so
    # conditional parameters are in a configuration where they can act". At 2
    # (PTC's own default, and what the PTC contract's sbend_fringe/cfbend_fringe
    # cases use) `:none` and `:soft_quad` separate from `:all` by 7.8e-9, so the
    # parameter is reachable (2026-08-05_b audit, U4-4).
    #
    # This makes the probe capable; it does not by itself make the contract
    # check `fringe`, because `_perturb_param` returns nothing for every Symbol
    # and the pair is dropped before the count (U4-2, still open).
    :sbend => (L=1.1, angle=0.198, k1=0.6, k2=5.0, nst=2, e1=0.1, e2=0.1,
               fint1=0.5, fint2=0.5, hgap1=0.03, hgap2=0.03, hface1=0.02,
               hface2=0.02, fringe=:all, highest_fringe=2, curved_order=3,
               x_offset=1.0e-3),
    # The optics form, deliberately without `matrix`: Linear6D uses a stored
    # matrix when there is one, so probing the example (which stores the folded
    # matrix) would report every optics input as ignored.
    :linear6d => (beta1=(3.0, 5.0, 90.0), beta2=(3.2, 4.7, 88.0),
                  alpha1=(0.1, -0.2, 0.0), alpha2=(0.05, -0.15, 0.0),
                  dmu=(0.31, 0.27, 0.011), eta1=(0.4, 0.02, 0.0, 0.0),
                  eta2=(0.38, 0.03, 0.0, 0.0), zeta1=(0.01, 0.0, 0.0, 0.0),
                  zeta2=(0.012, 0.0, 0.0, 0.0), R1=(0.02, 0.01, 0.0, 0.0),
                  R2=(0.021, 0.011, 0.0, 0.0)),
    :marker => NamedTuple(),
    :thin_multipole => (k1l=0.05, k2l=1.2, x_offset=1.0e-3),
    :thin_dipole => (k0l=1.0e-3, x_offset=1.0e-3),
    :thin_quadrupole => (k1l=0.05, x_offset=1.0e-3),
    :thin_sextupole => (k2l=1.2, x_offset=1.0e-3),
    :hkicker => (hkick=1.0e-4, x_offset=1.0e-3),
    :vkicker => (vkick=1.0e-4, x_offset=1.0e-3),
    :kicker => (hkick=1.0e-4, vkick=-5.0e-5, x_offset=1.0e-3),
    # Limits tight enough that the probe particle sits outside and is killed, so
    # perturbing any of them changes the map. A generous aperture would pass
    # every probe unchanged and report all four as ignored.
    :aperture => (shape=:ellipse, x_limit=1.0e-4, y_limit=2.0e-4,
                  dx=1.0e-5, dy=2.0e-5),
    # Multipoles must be present for `nst` to do anything: a pure solenoid is
    # the exact flow and ignores the step count, so probing it without them
    # would report `nst` ignored when it is only inapplicable.
    :solenoid => (L=1.3, ks=0.35, kn=(0.0, 0.6), kskew=(0.0, 0.2), nst=2),
    :patch => (dx=1.0e-3, dy=-2.0e-3, dz=0.05,
               angle_x=1.2e-2, angle_y=-0.8e-2, angle_s=0.3, t_offset=2.0e-3),
    # All four coefficients nonzero, unlike the one-coefficient curated
    # examples: a placement offset acts on these linear maps only through the
    # coordinates the map READS (a zeta2/eta2/r-coefficient channel), so the
    # single-coefficient examples leave most placement conjugations exactly
    # inert when the physics is not (2026-08-05 audit, U13-2 completion).
    :crab_dispersion => (zeta1=0.1, zeta2=0.07, zeta3=-0.06, zeta4=0.05),
    :momentum_dispersion => (eta1=0.4, eta2=0.02, eta3=0.05, eta4=-0.01),
    :xy_coupling => (r1=0.01, r2=0.02, r3=-0.015, r4=0.012),
    # Unequal transverse damping rates: the curated example damps x and y
    # equally, and an isotropic transverse map commutes with a roll about s,
    # so `tilt` would read as inert when it is only unprobeable there.
    :lumped_radiation => (damping_turns=(1000.0, 800.0, 500.0), rng_id=1),
)
"""
Parameters that every kind CARRIES rather than consumes.

`DEFAULT_INACTIVE_ELEMENT_PARAMS` is keyed by `(kind, parameter)`, which is
right for an exemption that depends on the map -- `marker.x_offset` is inert
because the identity commutes with a placement, and that is a statement about
markers. `:name` is not like that: no tracking kernel reads it for ANY kind, by
design, and it became a parameter of all thirty when the beam-line walker's
provenance paths were made declarable (2026-08-05_b audit, U15-12). Thirty
copies of one reason is worse than one, and each copy would need its own
staleness bookkeeping.

Counted in its own `:carried` metric rather than dropped, because what the
contract does not decide has to be visible (U4-2).
"""
const CARRIED_ELEMENT_PARAMS = Dict{Symbol,String}(
    :name => "a label carried into beam-line provenance paths and into diagnostics that name an element rather than an index; no tracking kernel reads it, for any kind",
)

const DEFAULT_INACTIVE_ELEMENT_PARAMS = Dict{Tuple{Symbol,Symbol},String}(
    (:drift, :nst) => "the drift is exact, so there are no integration steps",
    (:drift, :integrator_order) => "the drift is exact, so there is nothing to split",
    (:marker, :tracking_method) => "a marker is the identity under every method",
    (:line, :L) => "survey metadata, not tracking input: consumed by the arc-length walkers (s_positions, total_length, aperture_s and the misaligned-parent survey), not by the coordinate map this contract measures — declared by the 2026-08-05 campaign so nested own-state lines survey at their real length",
    # These are consumed, but not through the single deterministic
    # coordinate map this contract measures. The distinction matters: they are
    # not inert, they are invisible to this probe, and a stronger check would
    # need a stochastic path and a diagnostic boundary rather than one call.
    (:lumped_radiation, :sigma) => "feeds the stochastic excitation, which one deterministic call does not exercise",
    (:lumped_radiation, :is_excitation) => "gates the stochastic excitation path, not the damping map probed here",
    (:lumped_radiation, :rng_id) => "selects a counter-RNG stream, observable only through stochastic samples",
    (:lumped_radiation, :alpha) => "optics input used to build the damping/excitation moments, folded before the map",
    (:lumped_radiation, :beta) => "optics input folded before the map, as alpha is",
    (:thin_strong_beam, :klum) => "reaches the runtime but feeds the luminosity diagnostic, not the coordinate map",
    (:thin_strong_beam, :alpha) => "used only when the strong beam is given through beta/alpha optics rather than kbb, which this probe does not do",
    # A function, a string and an output handle have no meaningful perturbation:
    # there is no "slightly different" predicate or label whose effect this
    # contract could measure. They are declared inert here rather than left to
    # look ignored, which is the distinction the contract exists to draw.
    (:aperture, :alive) => "a predicate has no perturbation this contract can form; its effect is covered by the shape-versus-predicate equivalence test",
    (:aperture, :element_id) => "stamped into loss records by the task; does not enter the coordinate map",
    (:aperture, :loss_record) => "an output handle written on the loss transition, not an input to the map",
    # Placement parameters (declared for every kind since the schemas learned
    # to carry them; 2026-08-05 audit, U13-2 completion). These entries are
    # derived from MAP STRUCTURE, not from a bitwise sweep: a mathematically
    # inert conjugation can still move the last bit through the (v - d) + d
    # frame round trip, so a sweep splits hairs the physics does not.
    (:marker, :x_offset) => "the identity map commutes with every rigid placement: the exit frame change undoes the entrance one exactly",
    (:marker, :y_offset) => "identity map; see marker.x_offset",
    (:marker, :z_offset) => "identity map; see marker.x_offset",
    (:marker, :x_pitch) => "identity map; the rotation conjugation cancels to roundoff",
    (:marker, :y_pitch) => "identity map; the rotation conjugation cancels to roundoff",
    (:marker, :tilt) => "identity map; the rotation conjugation cancels to roundoff",
    (:marker, :ref_tilt) => "identity map; the design-roll conjugation cancels to roundoff",
    (:thin_dipole, :x_offset) => "a constant kick commutes with transverse displacements: shift in, kick by the same constant, shift back",
    (:thin_dipole, :y_offset) => "constant kick; see thin_dipole.x_offset",
    (:hkicker, :x_offset) => "constant kick; see thin_dipole.x_offset",
    (:hkicker, :y_offset) => "constant kick; see thin_dipole.x_offset",
    (:vkicker, :x_offset) => "constant kick; see thin_dipole.x_offset",
    (:vkicker, :y_offset) => "constant kick; see thin_dipole.x_offset",
    (:kicker, :x_offset) => "constant kick; see thin_dipole.x_offset",
    (:kicker, :y_offset) => "constant kick; see thin_dipole.x_offset",
    (:thin_rf_cavity, :x_offset) => "the thin RF kick reads z and writes pt only, so a transverse displacement conjugates to exactly nothing",
    (:thin_rf_cavity, :y_offset) => "reads z, writes pt; see thin_rf_cavity.x_offset",
    (:thin_rf_cavity, :tilt) => "the map is independent of the transverse coordinates, so a roll about s commutes (cancels to roundoff)",
    (:thin_rf_cavity, :ref_tilt) => "transverse-independent map; a design roll commutes like tilt does",
    (:lorentz_boost, :y_offset) => "the horizontal-crossing boost writes y without reading it, so a vertical displacement conjugates to exactly nothing",
    (:rev_lorentz_boost, :y_offset) => "writes y without reading it, as the forward boost does; the sweep sees roundoff here, not physics",
)

"""
Keys merged ONTO a kind's probe (whether that probe is curated or the kind's own
example), for conditional parameters that are structurally inert in the shipped
configuration.

This is a merge rather than a probe entry because the value that unlocks the
parameter often sits beside required keywords the probe would otherwise have to
restate -- and because those keywords are element types that are not yet defined
where `DEFAULT_ELEMENT_PARAM_PROBES` is evaluated.

`gaussian_strong_beam.slice_width` is consumed only by `:equal_width` slicing
(its own declared meaning says so), while the example spec slices by
`:sqrt_density`. It was therefore reported declared-but-not-consumed the moment
the sweep widened enough to reach it, when it is in fact perfectly effective at
the configuration where it applies (2026-08-05_b audit, U4-2/U4-3).
"""
const ELEMENT_PARAM_PROBE_OVERRIDES = Dict{Symbol,Any}(
    :gaussian_strong_beam => (slice_method=:equal_width, slice_width=3.0e-3),
)

"""
    ElementParameterEffectivenessContract <: AbstractImplementationContract

Contract checking that every declared element parameter reaches the compiled
map. `validate(contract)` builds each probed kind through its friendly
constructor, perturbs one declared parameter at a time, and tracks a test
particle through the compiled runtime; a perturbation that moves no
coordinate by more than `atol` (default `0.0`, i.e. bitwise identical) is
reported as declared-but-ignored unless its `(kind, parameter)` pair is
listed in `inactive` with a reason. The probe keywords and default inactive
list, and why probing goes through the friendly constructor, are documented
on [`DEFAULT_ELEMENT_PARAM_PROBES`](@ref).
"""
Base.@kwdef struct ElementParameterEffectivenessContract <: AbstractImplementationContract
    probes::Dict{Symbol,Any} = DEFAULT_ELEMENT_PARAM_PROBES
    inactive::Dict{Tuple{Symbol,Symbol},String} = DEFAULT_INACTIVE_ELEMENT_PARAMS
    atol::Float64 = 0.0
end

# Candidate perturbations for a declared parameter, most physical first. The
# CONSTRUCTOR arbitrates: the caller tries them in order and keeps the first one
# accepted, so validity is decided by the element rather than guessed here. An
# empty tuple means the parameter is not something this contract can vary (a
# tracking method, a symbol enum).
#
# A single guess left ~15 parameters permanently unverifiable while the
# "a rejected value is consumed by definition" reasoning counted them as fine
# (2026-08-05_b audit, U4-3):
#
#   * Placement parameters declare an INTEGER default of `0` with unit "m" or
#     "rad", so the `Integer` branch perturbed them by 1 metre or 1 radian.
#     Seven threw DomainError inside the map and were dropped -- yet a 1e-3
#     perturbation moves the sbend map by 6.8e-4 (y_offset), 4.1e-5 (x_pitch),
#     4.7e-5 (y_pitch). They were checkable all along, at a physical amplitude.
#   * `curved` declares a default of `nothing`, which the caller substitutes
#     with `0.0`; the `Real` branch then produced `0.13` and the constructor
#     raised `InexactError: Bool(0.13)`. `drift.curved`, `sbend.curved` and
#     `solenoid.curved` were never verified -- the parameter audit F17 was
#     about.
#   * `integrator_order` accepts only `(2, 4)`, so `2 -> 3` was rejected on
#     quadrupole, sextupole, octupole, multipole and sbend -- while
#     `(:drift, :integrator_order)` sits in the inactive table WITH a reason,
#     which reads as a claim that the others are checked.
# A placement parameter is physical whatever its ParamMeta says. The unit is
# consulted first because it is the general signal, but several kinds carry the
# spliced placement entries with an EMPTY unit (measured: `sbend.y_offset` has
# `unit = ""` while `_PLACEMENT_PARAMS` declares "m"), so the authoritative key
# list backs it up rather than a hand-copied name list here.
_perturb_is_physical(key, pmeta) =
    key in _PLACEMENT_PARAM_KEYS ||
    (pmeta isa ParamMeta && pmeta.unit in ("m", "rad"))

function _perturb_candidates(key::Symbol, current, pmeta)
    key === :tracking_method && return ()
    current isa Bool && return (!current,)
    current isa Symbol && return ()
    if current isa Tuple
        isempty(current) && return ((0.0, 0.31),)
        return (ntuple(i -> Float64(current[i]) + 0.17 * i, length(current)),)
    end
    # A `nothing` default carries no type at all, so offer the shapes an element
    # parameter actually takes and let the constructor pick.
    current === nothing && return (true, false, 1.0e-3, 1)
    if current isa Integer
        # An integer-declared physical quantity is still a physical quantity:
        # perturb it by a physical amount before trying the enum-style step.
        return _perturb_is_physical(key, pmeta) ? (1.0e-3, Int(current) + 1) :
                                                  (Int(current) + 1, Int(current) + 2)
    end
    # Additive AND multiplicative. A fixed +0.13 is unphysical for any
    # small-scale quantity, and unphysical is not the same as ineffective:
    # `gaussian_strong_beam.slice_width` is a length in metres against a 7 mm
    # bunch, so +0.13 m puts every particle in one slice and the map does not
    # move -- the parameter looks dead when it is only being asked the wrong
    # question. A relative perturbation is scale-correct for exactly these
    # (2026-08-05_b audit, U4-3).
    current isa Real && return (Float64(current) + 0.13, Float64(current) * 1.37)
    return ()
end

# Parameters that are not INDEPENDENTLY variable, and the joint moves that
# perturb them legally.
#
# `beta0` and `gamma0` on `:thin_rf_cavity` are two views of one reference
# energy, constrained by `beta0^2 = (gamma0^2-1)/gamma0^2`. Moving one alone
# builds a reference particle that cannot exist, and `ThinRFCavitySpec` now
# refuses it. Before that refusal the generic perturbation "checked" `beta0` by
# setting it to `0.99 + 0.13 = 1.12` -- faster than light -- so the evidence
# that the parameter reached the map came from a value no beam can have
# (2026-08-05_b audit, U14-4).
#
# The effectiveness question for a constrained pair is necessarily JOINT: there
# is no perturbation that moves one and not the other. Both keys therefore get
# the same joint move, and what is proved is that the reference energy reaches
# the map -- which is the strongest true statement available here, and strictly
# more than an exemption would say. Returns `nothing` for the ordinary case.
function _perturb_coupled_overrides(kind::Symbol, key::Symbol, probe)
    (kind === :thin_rf_cavity && (key === :beta0 || key === :gamma0)) || return nothing
    g0 = Float64(get(probe, :gamma0, 100.0))
    return [begin
                g = 1 + factor * (g0 - 1)
                Dict{Symbol,Any}(:gamma0 => g,
                                 :beta0 => sqrt((g - 1) * (g + 1)) / g)
            end for factor in (1.37, 3.0)]
end

# Retained for callers and tests that want the single primary perturbation.
function _perturb_param(key::Symbol, current, pmeta=nothing)
    candidates = _perturb_candidates(key, current, pmeta)
    return isempty(candidates) ? nothing : first(candidates)
end

function validate(contract::ElementParameterEffectivenessContract; kwargs...)
    _reject_unknown_validate_kwargs(contract, kwargs)
    u = (2.3e-3, 4.1e-4, -1.7e-3, -3.2e-4, 1.5e-3, 9.0e-4)
    ignored = String[]
    broken = String[]
    checked = 0
    skipped = Symbol[]
    # Every parameter this contract does NOT decide has to be visible
    # (2026-08-05_b audit, U4-2). Of 501 declared parameters, 353 were checked,
    # 36 were documented-inactive, and 112 were dropped by the two `continue`s
    # below without being counted anywhere -- while the success message read
    # "every declared element parameter reached the map (353 checked, 0 kinds
    # without a probe)", which a reader takes for completeness. That is the
    # AGENTS.md rule "do not report an unrun check as passed", in the file whose
    # job is to enforce it.
    unperturbable = String[]   # no perturbation this contract can form
    rejected = String[]        # constructor refused the perturbed value
    carried = String[]         # carried by every kind, consumed by none (see CARRIED_ELEMENT_PARAMS)
    exemptions_seen = Set{Tuple{Symbol,Symbol}}()   # U4-17: which `inactive` entries applied
    for T in registered_element_specs()
        meta = _element_meta_or_nothing(T)
        meta === nothing && continue
        ctor = meta.friendly_constructor
        if ctor === nothing
            push!(skipped, meta.kind)
            continue
        end
        # Without an explicit probe, fall back to the kind's own curated
        # example: it is already the representative element, and for elements
        # with no construction-time sugar its stored parameters are exactly the
        # constructor keywords.
        probe = if haskey(contract.probes, meta.kind)
            Dict{Symbol,Any}(pairs(contract.probes[meta.kind]))
        else
            ex = example_spec(T)
            ex isa ElementSpec ? Dict{Symbol,Any}(params(ex)) : nothing
        end
        if probe === nothing
            push!(skipped, meta.kind)
            continue
        end
        if haskey(ELEMENT_PARAM_PROBE_OVERRIDES, meta.kind)
            merge!(probe, Dict{Symbol,Any}(
                pairs(ELEMENT_PARAM_PROBE_OVERRIDES[meta.kind])))
        end
        baseline = try
            collect(compile_runtime(ctor(; probe...))(u...))
        catch err
            # A throwing baseline is a BROKEN kind, not an unprobeable one:
            # silently skipping it converted a defect on the probe path into
            # lost coverage under a passing report, guarded only by the
            # zero-headroom skipped-count pin (2026-08-05 audit, U3-7).
            push!(broken, "$(meta.kind): $(sprint(showerror, err))")
            continue
        end
        for (key, pmeta) in pairs(parameter_schema(T))
            pmeta isa ParamMeta || continue
            # Record which exemptions were consulted, so a stale one can be
            # reported (2026-08-05_b audit, U4-17). An exemption for a
            # (kind, parameter) pair that no longer exists excuses nothing and
            # nobody notices; worse, an exemption whose parameter later becomes
            # genuinely ignored keeps excusing it forever, silently, which is
            # the direction that matters.
            # Kind-independent exemptions first: a per-kind `inactive` entry for
            # one of these would never be consulted and would then read as
            # stale (see `CARRIED_ELEMENT_PARAMS`).
            if haskey(CARRIED_ELEMENT_PARAMS, key)
                push!(carried, "$(meta.kind).$(key)")
                continue
            end
            if haskey(contract.inactive, (meta.kind, key))
                push!(exemptions_seen, (meta.kind, key))
                continue
            end
            # The raw default, INCLUDING `nothing`. Substituting 0.0 here threw
            # away the only type information a `nothing`-defaulted parameter
            # has, sending `curved` down the Real branch to `InexactError:
            # Bool(0.13)` (U4-3). `_perturb_candidates` handles `nothing` by
            # offering the shapes an element parameter takes.
            current = get(probe, key, pmeta.default)
            coupled = _perturb_coupled_overrides(meta.kind, key, probe)
            candidates = coupled === nothing ?
                _perturb_candidates(key, current, pmeta) : coupled
            if isempty(candidates)
                push!(unperturbable, "$(meta.kind).$(key)")
                continue
            end
            # The question is "does this parameter reach the map AT ALL", so
            # every valid alternative gets a turn and the largest movement wins.
            # Taking only the first accepted candidate answers a narrower
            # question and gets it wrong: `drift`'s probe has `h = 0.05`, so
            # `curved = true` is what the frame already chose and moves nothing,
            # while `curved = false` -- the value audit F17 was about -- moves
            # the map. "A rejected value is consumed by definition" was the old
            # reasoning for skipping outright, and it is wrong for a
            # perturbation that is unphysical rather than invalid, so the
            # constructor arbitrates validity and the map arbitrates effect
            # (2026-08-05_b audit, U4-3).
            accepted = false
            deviation = 0.0
            for candidate in candidates
                override = candidate isa Dict{Symbol,Any} ?
                    candidate : Dict{Symbol,Any}(key => candidate)
                moved = try
                    collect(compile_runtime(ctor(; merge(probe, override)...))(u...))
                catch
                    nothing
                end
                moved === nothing && continue
                accepted = true
                deviation = max(deviation, maximum(abs, moved .- baseline))
                deviation > contract.atol && break
            end
            if !accepted
                push!(rejected, "$(meta.kind).$(key)")
                continue
            end
            checked += 1
            deviation <= contract.atol && push!(ignored, "$(meta.kind).$(key)")
        end
    end
    # An exemption naming a pair the sweep never reaches is stale: the kind or
    # the parameter is gone, or a probe change moved it out of range, and the
    # entry now documents something that does not exist (U4-17).
    stale_exemptions = sort!([string(k, ".", p) for (k, p) in keys(contract.inactive)
                              if !((k, p) in exemptions_seen)])
    metrics = Dict{Symbol,Any}(:checked => checked, :ignored => length(ignored),
                               :skipped_kinds => length(skipped),
                               :broken_kinds => length(broken),
                               :unperturbable => length(unperturbable),
                               :rejected => length(rejected),
                               :carried => length(carried),
                               :undecided => length(unperturbable) + length(rejected),
                               :exemptions_declared => length(contract.inactive),
                               :exemptions_applied => length(exemptions_seen),
                               :stale_exemptions => length(stale_exemptions))
    isempty(broken) || return ContractResult(false,
        "probe baselines threw (a broken kind, not a missing probe): " *
        join(sort(broken), "; "); metrics=metrics)
    isempty(stale_exemptions) || return ContractResult(false,
        "declared inactive but never reached by the sweep (stale exemptions -- the " *
        "kind or parameter is gone, or a probe change moved it out of range): " *
        join(stale_exemptions, ", "); metrics=metrics)
    isempty(ignored) && return ContractResult(true,
        "every parameter this contract could decide reached the map " *
        "($(checked) checked, $(length(skipped)) kinds without a probe; " *
        "$(length(unperturbable)) with no formable perturbation, " *
        "$(length(rejected)) whose perturbation the constructor rejected -- " *
        "neither group is verified)"; metrics=metrics)
    return ContractResult(false,
        "declared but not consumed: " * join(sort(ignored), ", "); metrics=metrics)
end

# ---------------------------------------------------------------------------
# Solver option effectiveness
# ---------------------------------------------------------------------------

"""
Base keywords per solver, chosen so conditional options sit in a configuration
where they can act: `grid_extent_sigma` needs `grid_extent = :sigma`, the
slice-pair Green ratios need `green_cache = :slice_pair`, and every slicing
option needs more than one slice.
"""
_default_solver_option_probes() = Dict{Symbol,Any}(
    :GaussianPoissonSolver => (
        slicing=LongitudinalSlicing(nslices=3, method=:normal_quantile),),
    :PICPoissonSolver => (
        grid=(24, 24), green_cache=:slice_pair, grid_extent=:sigma,
        slicing=LongitudinalSlicing(nslices=3, method=:normal_quantile)),
    # No `grid_extent = :sigma` here: the hybrid rejects it outright, since it
    # sizes its own box. The PIC probe keeps it so `grid_extent_sigma` can act.
    :GaussianPICPoissonSolver => (
        grid=(24, 24), green_cache=:slice_pair, deposit_method=:TSC,
        slicing=LongitudinalSlicing(nslices=3, method=:normal_quantile)),
    :SpectralPoissonSolver => (
        grid=(24, 24),
        slicing=LongitudinalSlicing(nslices=3, method=:normal_quantile)),
)

"""
A valid non-default value for each declared solver option.

There is no generic perturbation for a solver option the way there is for a
numeric element parameter: most are `Symbol` enumerations whose alternatives are
constrained by the constructor. The table is explicit for that reason, and the
contract **fails** when an option has neither an entry here nor a stated reason
in `DEFAULT_INACTIVE_SOLVER_OPTIONS`, so it cannot silently fall behind the
schema.
"""
_pic_family_alternatives() = Dict{Symbol,Any}(
    :kbb1 => 2.0e-8, :kbb2 => 2.0e-8, :luminosity_scale => 3.0e7,
    :grid => (32, 32),
    :deposit_method => :TSC,
    :green_type => :standard,
    :green_cache => :none,
    :field_derivative => :fourth,
    :slice_interpolation => :quadratic,
    # A NamedTuple alternative carries a companion setting: `:source_slice` sizes
    # its mesh from `_pic_union_bounds`, which applies no extent estimator, so it
    # now rejects the probe's `grid_extent = :sigma` instead of dropping it
    # silently. The companion is applied to the *baseline* too, so the check still
    # isolates `interaction_grid`.
    :interaction_grid => (interaction_grid=:source_slice, grid_extent=:extrema),
    :grid_extent => :extrema,
    :grid_extent_sigma => 4.0,
    :min_transverse_extent => (2.0e-3, 2.0e-3),
    :grid_quantize => 0.125,
    :slice_pair_green_min_ratio => 0.9,
    :slice_pair_green_growth => 0.6,
    :longitudinal_kick => false,
    :batch_mode => :sequential,
    :cuda_async => false,
    :cuda_batch_fft => false,
    :cuda_wavefront_fft => false,
    :cuda_indexed_wavefront => false,
    :luminosity_grid => (32, 32),
    :luminosity_deposit_method => :TSC,
    :luminosity_schedule => EveryNSteps(step=2),
    :slicing => LongitudinalSlicing(nslices=4, method=:equal_count),
    :slicing1 => LongitudinalSlicing(nslices=5, method=:equal_width),
    :slicing2 => LongitudinalSlicing(nslices=5, method=:equal_width),
    :backend_configurations => (CUDAPICLaunchConfig(kick_threads=64),),
)

_default_solver_option_alternatives() = Dict{Symbol,Any}(
    :GaussianPoissonSolver => Dict{Symbol,Any}(
        :kbb1 => 2.0e-8, :kbb2 => 2.0e-8, :luminosity_scale => 3.0e7,
        :slicing => LongitudinalSlicing(nslices=4, method=:equal_count),
        :slicing1 => LongitudinalSlicing(nslices=5, method=:equal_width),
        :slicing2 => LongitudinalSlicing(nslices=5, method=:equal_width),
        :min_sigma => 1.0e-3,
        :gaussian_when_luminosity => 1,
        :ignore_centroid1 => true, :ignore_centroid2 => true,
        :longitudinal_kick => false,
        :virtual_drift => :chromatic,
        :include_sigma_xy => true,
        :batch_mode => :sequential,
    ),
    :PICPoissonSolver => _pic_family_alternatives(),
    :GaussianPICPoissonSolver => merge(_pic_family_alternatives(), Dict{Symbol,Any}(
        :margin_sigma => 2.0, :neutralize => false, :coupling_tol => 0.0,
        # The probe sets :TSC (the docstring recommends it for the hybrid), so
        # these alternatives have to move away from the probe, not from the
        # schema default -- luminosity_deposit_method inherits deposit_method,
        # so :TSC would have resolved to the probe's own value.
        :deposit_method => :CIC,
        :luminosity_deposit_method => :CIC,
    )),
    :SpectralPoissonSolver => Dict{Symbol,Any}(
        :kbb1 => 2.0e-8, :kbb2 => 2.0e-8, :luminosity_scale => 3.0e7,
        :grid => (32, 32),
        :domain_factor => 8.0,
        :min_domain_halfwidth => 2.0e-3,
        :method => :grid_free,
        :longitudinal_kick => false,
        :field_precision => :single,
        :luminosity_schedule => EveryNSteps(step=2),
        :slicing => LongitudinalSlicing(nslices=4, method=:equal_count),
        :slicing1 => LongitudinalSlicing(nslices=5, method=:equal_width),
        :slicing2 => LongitudinalSlicing(nslices=5, method=:equal_width),
    ),
)

"""
`(solver, option)` pairs that cannot be judged by this contract, each with the
reason. Being listed here is a claim that the option is covered elsewhere or has
no observable this contract can form -- not that it is inert.
"""
const DEFAULT_INACTIVE_SOLVER_OPTIONS = Dict{Tuple{Symbol,Symbol},String}(
    (:SpectralPoissonSolver, :field_precision) =>
        "CUDA field-solve precision; the CPU path is always double, and CPU/CUDA parity covers it",
    # Both are rejected outright by the hybrid with a message naming the
    # supported paths, which is the correct handling of an unsupported request
    # and leaves nothing for this contract to observe.
    (:GaussianPICPoissonSolver, :interaction_grid) =>
        "GaussianPICPoissonSolver throws for :source_slice and :node; only the CPU PIC path implements them",
    (:GaussianPICPoissonSolver, :slice_interpolation) =>
        "GaussianPICPoissonSolver throws for :quadratic; only the CPU PIC path implements it",
    # Read by the plain PIC CUDA routes only; the hybrid picks its route from
    # batch_mode and cuda_indexed_wavefront and now rejects the rest rather than
    # dropping them, so there is nothing left for this contract to observe.
    (:GaussianPICPoissonSolver, :cuda_async) =>
        "the CUDA GaussianPIC route is chosen by batch_mode and cuda_indexed_wavefront; it rejects a non-default value",
    (:GaussianPICPoissonSolver, :cuda_batch_fft) =>
        "the CUDA GaussianPIC route is chosen by batch_mode and cuda_indexed_wavefront; it rejects a non-default value",
    (:GaussianPICPoissonSolver, :cuda_wavefront_fft) =>
        "the CUDA GaussianPIC route is chosen by batch_mode and cuda_indexed_wavefront; it rejects a non-default value",
    (:GaussianPICPoissonSolver, :grid_extent) =>
        "GaussianPICPoissonSolver sizes its box from margin_sigma and now throws rather than dropping a non-default estimator",
    (:GaussianPICPoissonSolver, :grid_extent_sigma) =>
        "half-width of an estimator GaussianPICPoissonSolver does not use; rejected with grid_extent itself",
    # Both ratios steer when a cached Green entry is rebuilt. Their effect is on
    # the cache hit/miss/rebuild history rather than on one collision's output,
    # and StrongStrongPICBackendConsistencyContract already compares that history
    # between CPU and CUDA and requires at least one reuse.
    (:PICPoissonSolver, :slice_pair_green_min_ratio) =>
        "steers Green-cache rebuild decisions; observable in the cache history, which StrongStrongPICBackendConsistencyContract compares",
    (:GaussianPICPoissonSolver, :slice_pair_green_min_ratio) =>
        "steers Green-cache rebuild decisions; observable in the cache history, which StrongStrongPICBackendConsistencyContract compares",
)

"""
    SolverOptionEffectivenessContract(; n_particles=256, probes=..., alternatives=...,
                                      inactive=..., cuda_threads=64)

Check that every declared strong-strong solver option reaches a runtime
consumer — the solver-level analogue of
[`ElementParameterEffectivenessContract`](@ref).

For each solver and each option in its `solver_option_schema`, the option is set
to a declared non-default value and one collision is run against a baseline:

- **Physics and numerical categories** (`:physics`, `:numerical`,
  `:physics_override`, `:accuracy_performance`, `:diagnostic`) must change the
  observable — the six coordinate arrays of both beams *or* the returned
  luminosity. Luminosity is part of the observable because
  `gaussian_when_luminosity`, `luminosity_grid` and `luminosity_deposit_method`
  are meant to move it and nothing else.
- **Execution categories** (`:execution`, `:performance`) must *not* change the
  observable — that is what makes them execution choices — but must appear in an
  execution receipt named by the option's declared `consumer`.

The execution half is the part that matters. `GaussianPICPoissonSolver`
discarded every `CUDAPICLaunchConfig` and the inherited policy thread count
while `configuration_report` called them resolved, because the installer tested
`isa` against a solver that *composes* `PICPoissonSolver` rather than subtyping
it; and a CUDA-only `batch_mode` on the soft-Gaussian solver was inactive on CPU
with no warning anywhere. Neither is visible to a coordinate comparison, and
`validate_configuration_metadata()` passed throughout — it checks that a
consumer is named, not that it runs.

An option with neither an alternative nor a stated reason **fails** the
contract, so the tables cannot fall behind the schema.

CUDA-only options are checked on CUDA; if no device is visible the contract
returns `status=:skipped` rather than reporting an unrun check as passed.
"""
Base.@kwdef struct SolverOptionEffectivenessContract <: AbstractImplementationContract
    n_particles::Int = 256
    seed::UInt64 = UInt64(123456789)
    probes::Dict{Symbol,Any} = _default_solver_option_probes()
    alternatives::Dict{Symbol,Any} = _default_solver_option_alternatives()
    inactive::Dict{Tuple{Symbol,Symbol},String} = DEFAULT_INACTIVE_SOLVER_OPTIONS
    cuda_threads::Int = 64
end

description(::Type{SolverOptionEffectivenessContract}) =
    "Checks that every declared strong-strong solver option reaches a runtime consumer."

"""
Concrete Poisson solvers the option sweep iterates.

DERIVED, not listed (2026-08-05_b audit, U4-7). This was a four-element
hand-written tuple while the enumeration tripwire beside it guarded
`contract.probes` — two different sets. `probes ⊇ derived` does not imply
`swept ⊇ derived`, so the natural response to a firing tripwire (add a probe
entry) made the contract report `:passed` with its unchanged "68 on CPU, 10
CUDA-only options, 2 launch surfaces" while the new solver's schema was never
read once. Demonstrated with an injected Octopus-defined solver.

`_concrete_octopus_subtypes` recurses, which `subtypes` does not: a future
intermediate abstract solver type would otherwise hide every concrete leaf
beneath it, the same trap U12-3 fixed for execution policies.
"""
_solver_contract_types() = Tuple(_concrete_octopus_subtypes(AbstractPoissonSolver))

_solver_option_is_execution(meta) = meta.category in (:execution, :performance)

# A declared alternative is normally the bare non-default value. It may instead be
# a `NamedTuple` when that value is only legal alongside a companion setting --
# `interaction_grid = :source_slice` requires `grid_extent = :extrema`, because
# that mode applies no extent estimator and now rejects a non-default rather than
# ignoring it. The companion is folded into the option's baseline as well, so the
# comparison still isolates the option under test.
# A plain `Tuple` (`grid = (32, 32)`) is a value, not a settings bundle.
_solver_alternative_value(name::Symbol, alt) = alt isa NamedTuple ? getproperty(alt, name) : alt
_solver_alternative_companions(name::Symbol, alt) =
    alt isa NamedTuple ? Base.structdiff(alt, NamedTuple((name => nothing,))) : NamedTuple()

"""
Run two consecutive collisions and return `(coordinates, luminosities, receipts)`.

Two, not one, and through the `TrackingContext` method rather than the bare
`collide!`, because a single context-free collision cannot see two whole classes
of option. `luminosity_schedule` is evaluated against a context, and the
context-free path passes `nothing`, which means "every turn"; and the slice-pair
Green cache has nothing to reuse until a second collision, so
`slice_pair_green_min_ratio` and `slice_pair_green_growth` never bind. Both
looked like ignored options until the probe was fixed rather than the code.
"""
function _solver_contract_observable(solver, base1, base2, backend)
    beam1 = _strong_strong_contract_beam(base1, backend)
    beam2 = _strong_strong_contract_beam(base2, backend)
    audit = ExecutionAudit()
    luminosities = Float64[]
    with_execution_audit(audit) do
        base_ctx = TrackingContext()
        for turn in 0:1
            push!(luminosities,
                  Float64(collide!(solver, beam1, beam2, backend,
                                   with_turn(base_ctx, turn))))
        end
    end
    coords = vcat((Array(a) for a in coordinate_arrays(beam1.rep))...,
                  (Array(a) for a in coordinate_arrays(beam2.rep))...)
    return coords, luminosities, execution_receipts(audit)
end

"""
Largest relative difference between two observables, over coordinates and
luminosities together. Used instead of an exact comparison wherever float atomic
reordering makes bitwise equality unavailable.
"""
function _solver_contract_spread(a, b)
    worst = 0.0
    for (x, y) in zip(a[1], b[1])
        worst = max(worst, abs(x - y) / max(abs(x), abs(y), eps()))
    end
    for (x, y) in zip(a[2], b[2])
        (isnan(x) && isnan(y)) && continue
        worst = max(worst, abs(x - y) / max(abs(x), abs(y), eps()))
    end
    return worst
end

"""
Run one CUDA turn through a `StrongStrongTask` and return
`(coordinates, luminosities, receipts)`.

A task rather than a bare `collide!`, because the scoped launch configuration
and the resolved policy are installed by `execute!`; calling the solver directly
would test a configuration the device never sees.
"""
function _solver_contract_cuda_observable(solver, base1, base2)
    beam1 = _strong_strong_contract_beam(base1, CUDABackend)
    beam2 = _strong_strong_contract_beam(base2, CUDABackend)
    ip = StrongStrongCollision(:solver_option; poisson_solver=solver)
    audit = ExecutionAudit()
    luminosities = Float64[]
    mktempdir() do dir
        path = joinpath(dir, "lum.tsv")
        with_execution_audit(audit) do
            execute!(StrongStrongTask((ip,), (ip,);
                policy=CUDAExecutionPolicy(launch=CUDALaunchConfig(threads=256)),
                luminosity_path=path), beam1, beam2; turns=1)
            CUDA.synchronize()
        end
        append!(luminosities, _strong_strong_contract_luminosity_series(path))
    end
    coords = vcat((Array(a) for a in coordinate_arrays(beam1.rep))...,
                  (Array(a) for a in coordinate_arrays(beam2.rep))...)
    return coords, luminosities, execution_receipts(audit)
end

_solver_contract_moved(a, b) =
    a[1] != b[1] || !isequal(a[2], b[2])

# Did a receipt named by the option's declared consumer carry the requested
# value? For :solver_runtime the whole configuration travels in the receipt; the
# specialised consumers publish their own fields.
function _solver_contract_receipt_carries(receipts, consumer::Symbol,
                                          name::Symbol, value,
                                          backend::Union{Nothing,DataType}=nothing)
    # The BACKEND tag is finally read (2026-08-05_b audit, U12-13). Every
    # `_record_execution!` writes it at all ~30 consumer boundaries and nothing
    # in src/, test/ or validation/ had ever consulted it -- the contracts
    # filtered on `r.consumer` and read `r.values` only. Several consumer
    # symbols are genuinely backend-polymorphic (`:observer_output`,
    # `:hook_schedule`, `:isolated_tracking`, `:solver_runtime`, the
    # strong-strong and schedule ones), so a CUDA-declared option could be
    # certified effective by a receipt emitted on CPU. The discriminator was in
    # the data all along.
    receipts = backend === nothing ? receipts :
               filter(r -> r.backend === backend, receipts)
    # Handled across the whole receipt set, not per receipt: one receipt per
    # family means the evidence for a multi-family configuration is spread over
    # several of them (U4-5).
    consumer === :cuda_pic_launch &&
        return _cuda_pic_launch_receipts_carry(receipts, value)
    for r in receipts
        r.consumer === consumer || continue
        if haskey(r.values, :configuration)
            cfg = r.values.configuration
            haskey(cfg, name) && isequal(getproperty(cfg, name), value) && return true
        end
        haskey(r.values, name) && isequal(getproperty(r.values, name), value) && return true
        # cuda_pic_launch publishes one receipt per FAMILY rather than per
        # option, so the generic paths above cannot match. See
        # `_cuda_pic_launch_receipts_carry` before the loop -- this branch used
        # to short-circuit to `true` for every option name that was not the
        # literal `:threads` or `:blocks`, and no option in the entire schema is
        # named either (2026-08-05_b audit, U4-5). The two options that reach
        # here are `PICPoissonSolver.backend_configurations` and
        # `GaussianPICPoissonSolver.backend_configurations`, so the branch was
        # vacuous for 100% of its traffic and the arm comparing against
        # `getproperty(r.values, name)` was dead code that could only ever have
        # thrown FieldError.
    end
    return false
end

"""
    _cuda_pic_launch_receipts_carry(receipts, configurations) -> Bool

Whether the `:cuda_pic_launch` receipts show every per-family thread count that
`configurations` requested.

This is the real question for `backend_configurations`, whose declared consumer
is `:cuda_pic_launch`: the receipts are published one per family with
`(family, threads)`, so no field on them is named after the option. Asking
whether a receipt merely EXISTS is what the previous form amounted to
(2026-08-05_b audit, U4-5).

A configuration requesting nothing is not evidence of anything, so it returns
`false` rather than vacuously `true`.
"""
function _cuda_pic_launch_receipts_carry(receipts, configurations)
    requested = Dict{Symbol,Int}()
    for cfg in (configurations isa Tuple ? configurations : (configurations,))
        cfg isa CUDAPICLaunchConfig || continue
        for family in _CUDA_PIC_LAUNCH_FAMILIES
            want = getproperty(cfg, Symbol(family, :_threads))
            want === nothing || (requested[family] = Int(want))
        end
    end
    isempty(requested) && return false
    for (family, want) in requested
        any(r -> r.consumer === :cuda_pic_launch &&
                 haskey(r.values, :family) && r.values.family === family &&
                 haskey(r.values, :threads) && r.values.threads == want,
            receipts) || return false
    end
    return true
end

function validate(contract::SolverOptionEffectivenessContract; kwargs...)
    _reject_unknown_validate_kwargs(contract, kwargs)
    # Solver enumeration guard (2026-08-05 audit, U3-4's sibling): every
    # concrete Poisson solver must carry a probe entry, or a NEW solver is
    # silently outside the sweep — the staleness mode the contract otherwise
    # only guards per-option.
    # The guarded set and the SWEPT set are now the same function
    # (`_solver_contract_types`), so a probe entry can no longer satisfy the
    # tripwire for a solver the sweep never visits (U4-7).
    for T in _solver_contract_types()
        haskey(contract.probes, nameof(T)) || return ContractResult(false,
            "$(nameof(T)) has no solver-option probe entry; the sweep would silently skip it")
    end
    old_seed = global_rng_seed()
    old_method = global_rng_method()
    try
        return _validate_solver_options(contract)
    finally
        set_global_rng!(seed=old_seed, method=old_method)
    end
end

function _validate_solver_options(contract::SolverOptionEffectivenessContract)
    metrics = Dict{Symbol,Any}()
    failures = String[]
    checked = 0
    deferred_cuda = Tuple{Symbol,Symbol}[]
    solver_exemptions_seen = Set{Tuple{Symbol,Symbol}}()   # U4-17
    # Pin the RNG, as every other strong-strong contract does. Without this the
    # probe beams depend on whatever global state the caller left behind: this
    # contract passed standalone and failed inside the test suite, where earlier
    # testsets had moved the global seed. A contract whose result depends on its
    # caller is not a contract.
    set_global_rng!(seed=contract.seed, method=:philox)
    base1, base2 = _strong_strong_contract_base_beams(
        StrongStrongPICBackendConsistencyContract(n_particles=contract.n_particles))

    for T in _solver_contract_types()
        kind = nameof(T)
        probe = get(contract.probes, kind, NamedTuple())
        alternatives = get(contract.alternatives, kind, Dict{Symbol,Any}())
        baseline_solver = T(; probe...)
        baseline = _solver_contract_observable(baseline_solver, base1, base2,
                                               CPUThreadsBackend)
        for (name, meta) in pairs(solver_option_schema(T))
            if haskey(contract.inactive, (kind, name))
                push!(solver_exemptions_seen, (kind, name))    # U4-17
                continue
            end
            if !haskey(alternatives, name)
                push!(failures,
                      "$(kind).$(name) has no declared alternative and no stated reason")
                continue
            end
            if !(CPUThreadsBackend in meta.supported_backends)
                push!(deferred_cuda, (kind, name))
                continue
            end
            alt_value = _solver_alternative_value(name, alternatives[name])
            companions = _solver_alternative_companions(name, alternatives[name])
            option_probe = merge(NamedTuple(probe), companions)
            if haskey(option_probe, name) &&
               isequal(getproperty(option_probe, name), alt_value)
                push!(failures,
                      "$(kind).$(name) declares an alternative equal to its own probe value")
                continue
            end
            solver = try
                T(; merge(option_probe, NamedTuple((name => alt_value,)))...)
            catch err
                push!(failures, "$(kind).$(name) rejected its declared alternative: " *
                                first(split(sprint(showerror, err), '\n')))
                continue
            end
            # With a companion setting the baseline has to move with it, or the
            # comparison would measure the companion rather than the option.
            option_baseline = try
                isempty(companions) ? baseline :
                    _solver_contract_observable(T(; option_probe...), base1, base2,
                                                CPUThreadsBackend)
            catch err
                push!(failures, "$(kind).$(name) companion baseline threw: " *
                                first(split(sprint(showerror, err), '\n')))
                continue
            end
            observed = try
                _solver_contract_observable(solver, base1, base2, CPUThreadsBackend)
            catch err
                push!(failures, "$(kind).$(name) threw during collision: " *
                                first(split(sprint(showerror, err), '\n')))
                continue
            end
            checked += 1
            moved = _solver_contract_moved(option_baseline, observed)
            if _solver_option_is_execution(meta)
                moved && push!(failures,
                    "$(kind).$(name) is declared $(meta.category) but changed the collision result")
                _solver_contract_receipt_carries(observed[3], meta.consumer, name,
                                                 alt_value, CPUThreadsBackend) ||
                    push!(failures,
                        "$(kind).$(name) reached no receipt named by its consumer $(meta.consumer)")
            else
                moved || push!(failures,
                    "$(kind).$(name) is declared $(meta.category) but changed nothing " *
                    "(coordinates and luminosity both identical)")
            end
        end
    end

    metrics[:cpu_options_checked] = checked
    metrics[:cuda_only_options] = length(deferred_cuda)

    available, reason = _contract_backends_available(CUDABackend)
    if !available
        metrics[:cuda_status] = :skipped
        isempty(failures) || return ContractResult(false,
            "solver options did not reach their consumers: " * join(sort(failures), "; ");
            metrics=metrics)
        return ContractResult(:skipped,
            "$(checked) CPU-visible solver options reached a consumer; " *
            "$(length(deferred_cuda)) CUDA-only options were skipped: $(reason)";
            metrics=metrics)
    end

    # The CUDA half: a launch configuration must reach the launch families, for
    # every solver that has a launch surface. This is the S1 regression.
    cuda_checked = 0
    cuda_options_checked = 0
    for T in _solver_contract_types()
        kind = nameof(T)
        probe = get(contract.probes, kind, NamedTuple())
        alternatives = get(contract.alternatives, kind, Dict{Symbol,Any}())
        # Every CUDA-only option, on the device. These are execution and
        # performance categories, so the assertion is the mirror of the CPU
        # half: the result must NOT move, and the value must appear in a
        # receipt named by the option's declared consumer.
        # `grid_extent` only where the solver declares it -- the soft-Gaussian
        # solver has no such keyword and rejected it.
        cuda_probe = haskey(solver_option_schema(T), :grid_extent) ?
            merge(NamedTuple(probe), (grid_extent=:extrema,)) : NamedTuple(probe)
        cuda_only = [(name, meta) for (name, meta) in pairs(solver_option_schema(T))
                     if !(CPUThreadsBackend in meta.supported_backends) &&
                        !haskey(contract.inactive, (kind, name)) &&
                        haskey(alternatives, name)]
        if !isempty(cuda_only)
            # Run the baseline TWICE and take the spread as the noise floor.
            # The CUDA grid solvers are not bitwise reproducible run to run --
            # float atomic deposition reorders -- so an exact comparison calls
            # every option a change, which is exactly what a first version of
            # this loop reported. Calibrating against the solver's own repeat
            # spread separates a reordered sum from an algorithmic difference
            # without hard-coding a tolerance.
            cuda_baseline, cuda_floor = try
                a = _solver_contract_cuda_observable(T(; cuda_probe...), base1, base2)
                b = _solver_contract_cuda_observable(T(; cuda_probe...), base1, base2)
                # Floor at the tolerance the strong-strong backend-consistency
                # contracts already use for "the same result" across routes
                # (rtol = 1e-10); self-calibration can only raise it if the
                # hardware is noisier than that. A route change reorders float
                # atomic sums, and the repository's own convention -- quoted
                # throughout the optimization histories as "bit-parity
                # (~1e-15)" with coordinate residuals ~1e-12 -- is that such a
                # difference is not a change. A genuine algorithmic difference
                # sits seven or more orders above it: green_cache moved the CPU
                # result by 2e-3 and the spectral method switch by 5e-3.
                a, max(_solver_contract_spread(a, b) * 100, 1.0e-10)
            catch err
                push!(failures, "$(kind) CUDA baseline threw: " *
                                first(split(sprint(showerror, err), '\n')))
                nothing, 0.0
            end
            if cuda_baseline !== nothing
                for (name, meta) in cuda_only
                    cuda_alt = _solver_alternative_value(name, alternatives[name])
                    solver = try
                        T(; merge(cuda_probe,
                                  _solver_alternative_companions(name, alternatives[name]),
                                  NamedTuple((name => cuda_alt,)))...)
                    catch err
                        push!(failures, "$(kind).$(name) rejected its alternative: " *
                                        first(split(sprint(showerror, err), '\n')))
                        continue
                    end
                    observed = try
                        _solver_contract_cuda_observable(solver, base1, base2)
                    catch err
                        push!(failures, "$(kind).$(name) threw on CUDA: " *
                                        first(split(sprint(showerror, err), '\n')))
                        continue
                    end
                    cuda_options_checked += 1
                    spread = _solver_contract_spread(cuda_baseline, observed)
                    spread > cuda_floor && push!(failures,
                        "$(kind).$(name) is declared $(meta.category) but moved the CUDA " *
                        "result by $(round(spread; sigdigits=3)), above this solver's own " *
                        "repeat spread of $(round(cuda_floor; sigdigits=3))")
                    _solver_contract_receipt_carries(observed[3], meta.consumer, name,
                                                     cuda_alt, CUDABackend) ||
                        push!(failures,
                            "$(kind).$(name) reached no receipt named by its consumer " *
                            "$(meta.consumer) on CUDA")
                end
            end
        end
        # Decide what to test from the SCHEMA, never from `_pic_launch_solver`.
        # Asking the installer which solvers have a launch surface makes the
        # check circular: the defect this contract exists to catch is precisely
        # that the installer failed to recognise a solver, and a first version
        # written that way silently skipped GaussianPICPoissonSolver instead of
        # failing it. The declaration is the obligation.
        haskey(solver_option_schema(T), :backend_configurations) || continue
        config = CUDAPICLaunchConfig(
            gather_scatter_threads=contract.cuda_threads,
            deposition_threads=contract.cuda_threads,
            kick_threads=contract.cuda_threads,
            field_threads=contract.cuda_threads,
            spectral_threads=contract.cuda_threads,
            green_threads=contract.cuda_threads,
            luminosity_threads=contract.cuda_threads)
        # The CPU probe sets `grid_extent = :sigma` so `grid_extent_sigma` can
        # act; the CUDA PIC backend rejects it outright rather than ignoring it
        # silently, which is the behaviour this whole contract is about. Use the
        # CUDA-supported estimator here -- the launch families are what is under
        # test, and they do not depend on it.
        solver = T(; merge(NamedTuple(probe),
                           (grid_extent=:extrema, backend_configurations=(config,)))...)
        ip = StrongStrongCollision(:solver_option; poisson_solver=solver)
        beam1 = _strong_strong_contract_beam(base1, CUDABackend)
        beam2 = _strong_strong_contract_beam(base2, CUDABackend)
        audit = ExecutionAudit()
        with_execution_audit(audit) do
            execute!(StrongStrongTask((ip,), (ip,);
                policy=CUDAExecutionPolicy(launch=CUDALaunchConfig(threads=256))),
                beam1, beam2; turns=1)
            CUDA.synchronize()
        end
        receipts = filter(r -> r.consumer === :cuda_pic_launch,
                          execution_receipts(audit))
        cuda_checked += 1
        if isempty(receipts)
            push!(failures,
                "$(kind) emitted no :cuda_pic_launch receipt, so its CUDAPICLaunchConfig " *
                "never reached a launch family")
        elseif !all(r -> r.values.threads == contract.cuda_threads, receipts)
            push!(failures,
                "$(kind) launched with thread counts other than the requested " *
                "$(contract.cuda_threads)")
        end
    end
    metrics[:cuda_launch_solvers_checked] = cuda_checked
    metrics[:cuda_options_checked] = cuda_options_checked

    # Same staleness tripwire as the element table (U4-17): an exemption naming
    # a (solver, option) pair the sweep never reaches excuses nothing, and an
    # entry whose option later becomes genuinely ignored would keep excusing it
    # forever with no signal.
    stale = sort!([string(k, ".", n) for (k, n) in keys(contract.inactive)
                   if !((k, n) in solver_exemptions_seen)])
    metrics[:exemptions_declared] = length(contract.inactive)
    metrics[:exemptions_applied] = length(solver_exemptions_seen)
    metrics[:stale_exemptions] = length(stale)
    isempty(stale) || return ContractResult(false,
        "declared inactive but never reached by the sweep (stale exemptions): " *
        join(stale, ", "); metrics=metrics)

    isempty(failures) || return ContractResult(false,
        "solver options did not reach their consumers: " * join(sort(failures), "; ");
        metrics=metrics)
    return ContractResult(true,
        "every declared solver option reached a runtime consumer " *
        "($(checked) on CPU, $(cuda_options_checked) CUDA-only options, " *
        "$(cuda_checked) launch surfaces)";
        metrics=metrics)
end
