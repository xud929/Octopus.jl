#=
Verify that observational task diagnostics do not change tracked coordinates.
The check runs identical deterministic CPU beams with diagnostics disabled and
enabled, requires exact equality of all final coordinates, and checks the
structured timing API. It writes no output files.

Run from the project root:

    julia --threads=4 --project=. validation/strong_strong_diagnostics_consistency.jl
=#
if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus

struct DiagnosticsNoopPoissonSolver <: AbstractPoissonSolver end
Octopus.collide!(::DiagnosticsNoopPoissonSolver, beam1::Beam, beam2::Beam,
                 backend, ctx::TrackingContext) = 0.0

function make_task(diagnostics)
    map = Linear6DSpec{Float64}(beta1=(0.55, 0.056, 12.0), beta2=(0.8, 0.072, 14.0),
                                dmu=(0.17, 0.11, 0.07))
    ip = StrongStrongCollision(:ip; poisson_solver=DiagnosticsNoopPoissonSolver())
    StrongStrongTask((map, ip, map), (map, ip, map); diagnostics)
end

contract = StrongStrongGaussianBackendConsistencyContract(n_particles=2048, turns=2)
set_global_rng!(seed=contract.seed, method=:philox)
base1, base2 = Octopus._strong_strong_contract_base_beams(contract)
plain1 = Octopus._strong_strong_contract_beam(base1, CPUThreadsBackend)
plain2 = Octopus._strong_strong_contract_beam(base2, CPUThreadsBackend)
observed1 = Octopus._strong_strong_contract_beam(base1, CPUThreadsBackend)
observed2 = Octopus._strong_strong_contract_beam(base2, CPUThreadsBackend)

execute!(make_task(StrongStrongDiagnostics()), plain1, plain2; turns=2)
task = make_task(StrongStrongDiagnostics(record_turn_times=true, cache_stats=true))
execute!(task, observed1, observed2; turns=2)
all(a == b for (a, b) in zip(coordinate_arrays(plain1.rep), coordinate_arrays(observed1.rep))) ||
    error("diagnostics changed beam-1 coordinates")
all(a == b for (a, b) in zip(coordinate_arrays(plain2.rep), coordinate_arrays(observed2.rep))) ||
    error("diagnostics changed beam-2 coordinates")
length(turn_timings(task)) == 2 || error("complete-turn timings were not recorded")
diagnostic_summary(task).configuration === task.diagnostics || error("summary lost configuration")
isempty(pic_phase_timings(task)) || error("CPU no-op solver produced PIC phase timings")
println("StrongStrongDiagnostics consistency: passed")
