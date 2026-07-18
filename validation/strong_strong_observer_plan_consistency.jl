#=
Check that adding a read-only observer after a strong-strong collision does not
change tracking. This guards the per-block tracking-plan cache key.

Run from the project root:

    julia --threads=4 --project=. validation/strong_strong_observer_plan_consistency.jl
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus
import CUDA

const N = parse(Int, get(ENV, "OCTOPUS_OBSERVER_PLAN_N", "2048"))
const TURNS = parse(Int, get(ENV, "OCTOPUS_OBSERVER_PLAN_TURNS", "1"))
const RTOL = parse(Float64, get(ENV, "OCTOPUS_OBSERVER_PLAN_RTOL", "1e-12"))

struct ValidationNoopPoissonSolver <: AbstractPoissonSolver end
Octopus.collide!(::ValidationNoopPoissonSolver, beam1::Beam, beam2::Beam,
                 backend, ctx::TrackingContext) = 0.0

function make_task(with_observer)
    pre = Linear6DSpec{Float64}(
        beta1=(0.55, 0.056, 12.0), beta2=(0.8, 0.072, 14.0),
        dmu=(0.17, 0.11, 0.07),
    )
    post = Linear6DSpec{Float64}(
        beta1=(0.8, 0.072, 14.0), beta2=(0.62, 0.061, 13.0),
        dmu=(0.23, 0.19, 0.09),
    )
    solver = ValidationNoopPoissonSolver()
    ip = StrongStrongCollision(:ip; poisson_solver=solver)
    observer = ScheduledObserver(MomentObserver(""; capacity=0))
    tail = with_observer ? (post, observer) : (post,)
    return StrongStrongTask((pre, ip, tail...), (pre, ip, tail...))
end

function check_backend(backend)
    contract = StrongStrongGaussianBackendConsistencyContract(n_particles=N, turns=TURNS)
    set_global_rng!(seed=contract.seed, method=:philox)
    base1, base2 = Octopus._strong_strong_contract_base_beams(contract)
    plain1 = Octopus._strong_strong_contract_beam(base1, backend)
    plain2 = Octopus._strong_strong_contract_beam(base2, backend)
    observed1 = Octopus._strong_strong_contract_beam(base1, backend)
    observed2 = Octopus._strong_strong_contract_beam(base2, backend)

    execute!(make_task(false), plain1, plain2; turns=TURNS)
    execute!(make_task(true), observed1, observed2; turns=TURNS)
    backend === CUDABackend && CUDA.synchronize()

    metrics1 = Octopus._contract_coordinate_metrics(plain1.rep, observed1.rep, 0.0, RTOL)
    metrics2 = Octopus._contract_coordinate_metrics(plain2.rep, observed2.rep, 0.0, RTOL)
    passed = metrics1[:passed_tolerance] && metrics2[:passed_tolerance]
    println(backend, ": max errors = ", metrics1[:max_abs_error], ", ", metrics2[:max_abs_error])
    passed || error("read-only observer changed strong-strong tracking on $(backend)")
end

check_backend(CPUThreadsBackend)
available, reason = Octopus._contract_backends_available(CUDABackend)
available ? check_backend(CUDABackend) : println("CUDABackend skipped: ", reason)
