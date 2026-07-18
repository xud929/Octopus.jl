if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus

#=
Validate that a tracking line produces consistent coordinates on different
execution backends.

Run from the project root:

    julia --project=. validation/tracking_backend_consistency.jl

The script always runs CPU/CPU checks. It also runs CPU/GPU checks when CUDA is
visible to Julia, or when explicitly requested:

    OCTOPUS_RUN_GPU_CONTRACT=1 julia --project=. validation/tracking_backend_consistency.jl

Useful environment variables:

    OCTOPUS_CONTRACT_N=10000
    OCTOPUS_CONTRACT_TURNS=2
    OCTOPUS_CONTRACT_ATOL=1e-10
    OCTOPUS_CONTRACT_RTOL=1e-10
    OCTOPUS_CONTRACT_SEED=123456789
    OCTOPUS_REQUIRE_GPU_CONTRACT=1

If `OCTOPUS_REQUIRE_GPU_CONTRACT=1`, a skipped CPU/GPU check is treated as an
error. Otherwise, lack of a visible CUDA device is reported as skipped.

The CPU/CPU check runs the same CPU backend twice in the same Julia process.
For elementwise fused tracking it is expected to be bitwise identical, even with
multiple Julia threads, because particles are independent and the Octopus
counter RNG is keyed by particle index rather than thread scheduling order.
=#

function _bool_env(name, default)
    value = lowercase(get(ENV, name, default ? "1" : "0"))
    return value in ("1", "true", "yes", "on")
end

function _cuda_visible()
    try
        isdefined(Octopus, :_HAS_CUDA) && getfield(Octopus, :_HAS_CUDA) || return false
        cuda = getfield(Octopus, :CUDA)
        return Base.invokelatest(getproperty(cuda, :functional), false)
    catch
        return false
    end
end

function _print_result(label, result)
    println(label)
    println("  status = ", result.status)
    println("  message = ", result.message)
    for key in sort!(collect(keys(result.metrics)); by=string)
        println("  ", key, " = ", result.metrics[key])
    end
    println()
end

N = parse(Int, get(ENV, "OCTOPUS_CONTRACT_N", "10000"))
turns = parse(Int, get(ENV, "OCTOPUS_CONTRACT_TURNS", "2"))
atol = parse(Float64, get(ENV, "OCTOPUS_CONTRACT_ATOL", "1e-10"))
rtol = parse(Float64, get(ENV, "OCTOPUS_CONTRACT_RTOL", "1e-10"))
seed = parse(UInt64, get(ENV, "OCTOPUS_CONTRACT_SEED", "123456789"))
run_gpu = get(ENV, "OCTOPUS_RUN_GPU_CONTRACT", "auto")
require_gpu = _bool_env("OCTOPUS_REQUIRE_GPU_CONTRACT", false)

line = (
    Linear6DSpec{Float64}(;
        beta1=(0.8, 0.072, 90.0),
        beta2=(0.82, 0.075, 91.0),
        alpha1=(0.0, 0.0, 0.0),
        alpha2=(0.01, -0.02, 0.0),
        dmu=(0.08, 0.12, 0.02),
    ),
    CrabDispersionSpec{Float64}(zeta1=0.02, zeta2=-0.01, zeta3=0.004, zeta4=0.002),
    MomentumDispersionSpec{Float64}(eta1=0.03, eta2=-0.006, eta3=0.002, eta4=0.01),
    XYCouplingSpec{Float64}(r1=0.01, r2=-0.003, r3=0.002, r4=0.004),
    LorentzBoostSpec(0.01),
    ThinCrabCavitySpec{2}(197.0e6;
        strengthX=(1.0e-5, -2.0e-6),
        strengthY=(3.0e-6, 0.0),
        phase=(0.0, 0.2),
    ),
    RevLorentzBoostSpec(0.01),
    ChromaticityKickSpec{Float64}(;
        xi=(1.2, -0.8),
        beta=(0.82, 0.075),
        alpha=(0.01, -0.02),
        zeta=(0.002, -0.001, 0.0, 0.0),
        eta=(0.001, 0.0, -0.001, 0.0),
        R=(0.001, -0.0005, 0.0003, 0.0007),
    ),
    ThinStrongBeamSpec{Float64}(;
        kbb=1.0e-8,
        klum=1.0,
        beta=(0.82, 0.075),
        alpha=(0.01, -0.02),
        sigma=(110.0e-6, 12.0e-6),
        center=(2.0e-6, -1.0e-6, 0.0),
        angle=(0.0, 0.0, 0.0),
    ),
    GaussianStrongBeamSpec{Float64}(;
        thin=ThinStrongBeamSpec{Float64}(;
            kbb=8.0e-9,
            klum=1.0,
            beta=(0.82, 0.075),
            alpha=(0.01, -0.02),
            sigma=(115.0e-6, 13.0e-6),
            center=(-1.0e-6, 1.5e-6, 0.0),
            angle=(0.0, 0.0, 0.0),
        ),
        ns=3,
        sigz=7.0e-3,
        slice_method=:equal_area,
    ),
    LumpedRadSpec{Float64}(;
        damping_turns=(4000.0, 4000.0, 2000.0),
        beta=(0.8, 0.072, 90.0),
        alpha=(0.0, 0.0, 0.0),
        sigma=(95.0e-6, 8.5e-6, 6.0e-2),
        rng_id=101,
    ),
)

cpu_cpu = ElementTrackingBackendConsistencyContract(;
    line=line,
    n_particles=N,
    turns=turns,
    backend_a=CPUThreadsBackend,
    backend_b=CPUThreadsBackend,
    seed=seed,
    rng_method=:philox,
    atol=atol,
    rtol=rtol,
)
cpu_cpu_result = validate(cpu_cpu)
_print_result("CPU/CPU tracking backend consistency", cpu_cpu_result)
cpu_cpu_result.passed || error("CPU/CPU tracking backend consistency failed")

should_run_gpu = run_gpu == "auto" ? _cuda_visible() : _bool_env("OCTOPUS_RUN_GPU_CONTRACT", false)
if should_run_gpu || require_gpu
    cpu_gpu = ElementTrackingBackendConsistencyContract(;
        line=line,
        n_particles=N,
        turns=turns,
        backend_a=CPUThreadsBackend,
        backend_b=CUDABackend,
        seed=seed,
        rng_method=:philox,
        atol=atol,
        rtol=rtol,
    )
    cpu_gpu_result = validate(cpu_gpu)
    _print_result("CPU/GPU tracking backend consistency", cpu_gpu_result)
    if cpu_gpu_result.status == :skipped && require_gpu
        error("CPU/GPU tracking backend consistency was required but skipped")
    end
    cpu_gpu_result.status == :failed && error("CPU/GPU tracking backend consistency failed")
else
    println("CPU/GPU tracking backend consistency")
    println("  status = skipped")
    println("  message = CUDA check not requested and CUDA is not visible to Julia.")
end

println("tracking backend consistency validation complete")
