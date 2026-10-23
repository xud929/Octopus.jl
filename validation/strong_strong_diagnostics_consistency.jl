#=
Verify that observational task diagnostics do not change tracked coordinates.
The check runs identical deterministic CPU beams with diagnostics disabled and
enabled through a REAL collision -- the CPU PIC solver on the Gaussian
contract's beams (2048 macroparticles per beam, 3 slices, a 32x32 grid, two
turns, seconds of work) -- requires exact equality of all final coordinates,
and checks that the diagnostics observed that collision: the complete-turn
timings and the slice-pair Green cache history are populated, and the
structured summary carries the configuration. It writes no output files.

Until 2026-10-22 the solver was a no-op (`collide!` returning 0.0), so every
diagnostic that could plausibly perturb coordinates (the turn-time wrap, the
cache statistics, memory logging around the solver) had nothing to instrument
and plain-versus-observed equality held by construction; the script even
asserted that no PIC phase ran (2026-10-18 comprehensive audit, F-243/U54-8).
The per-phase PIC timing sink is a CUDA diagnostic: on the CPU solver
`pic_phase_timings` stays empty whatever is requested, which is stated here,
not asserted as coverage.

Run from the project root:

    julia --threads=4 --project=. validation/strong_strong_diagnostics_consistency.jl
=#
if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus

const ONE_TURN_MAP = Linear6DSpec{Float64}(beta1=(0.55, 0.056, 12.0), beta2=(0.8, 0.072, 14.0),
                                           dmu=(0.17, 0.11, 0.07))
function make_task(diagnostics)
    slicing = LongitudinalSlicing(method=:normal_quantile, nslices=3, center_position=:centroid)
    solver = PICPoissonSolver(; slicing, grid=(32, 32), deposit_method=:CIC, green_type=:integrated,
                              green_cache=:slice_pair, longitudinal_kick=false)
    ip = StrongStrongCollision(:ip; poisson_solver=solver)
    StrongStrongTask((ONE_TURN_MAP, ip, ONE_TURN_MAP), (ONE_TURN_MAP, ip, ONE_TURN_MAP); diagnostics)
end

contract = StrongStrongGaussianBackendConsistencyContract(n_particles=2048, turns=2)
set_global_rng!(seed=contract.seed, method=:philox)
base1, base2 = Octopus._strong_strong_contract_base_beams(contract)
plain1 = Octopus._strong_strong_contract_beam(base1, CPUThreadsBackend)
plain2 = Octopus._strong_strong_contract_beam(base2, CPUThreadsBackend)
observed1 = Octopus._strong_strong_contract_beam(base1, CPUThreadsBackend)
observed2 = Octopus._strong_strong_contract_beam(base2, CPUThreadsBackend)

plain_task = make_task(StrongStrongDiagnostics())
execute!(plain_task, plain1, plain2; turns=2)
task = make_task(StrongStrongDiagnostics(record_turn_times=true, cache_stats=true, memory_log_every=1))
execute!(task, observed1, observed2; turns=2)
# The collision did something to compare: the same line WITHOUT the collision
# (the maps alone) must leave the beams somewhere else than the plain run did,
# or the solver is a no-op and the equality below is vacuous (the pre-fix
# shape; the maps alone move the beams, so "beams unchanged" would not see it).
maps_only1 = Octopus._strong_strong_contract_beam(base1, CPUThreadsBackend)
maps_only2 = Octopus._strong_strong_contract_beam(base2, CPUThreadsBackend)
execute!(StrongStrongTask((ONE_TURN_MAP, ONE_TURN_MAP), (ONE_TURN_MAP, ONE_TURN_MAP)), maps_only1, maps_only2; turns=2)
any(a != b for (a, b) in zip(coordinate_arrays(maps_only1.rep), coordinate_arrays(plain1.rep))) ||
    error("the plain run equals the maps-only run on beam 1: the collision is a no-op and this check is vacuous")
all(a == b for (a, b) in zip(coordinate_arrays(plain1.rep), coordinate_arrays(observed1.rep))) ||
    error("diagnostics changed beam-1 coordinates")
all(a == b for (a, b) in zip(coordinate_arrays(plain2.rep), coordinate_arrays(observed2.rep))) ||
    error("diagnostics changed beam-2 coordinates")
length(turn_timings(task)) == 2 || error("complete-turn timings were not recorded")
isempty(turn_timings(plain_task)) || error("the plain run recorded turn timings nobody asked for")
diagnostic_summary(task).configuration === task.diagnostics || error("summary lost configuration")
# The cache statistics observed the real solver: the slice-pair Green cache of
# the observed task has a non-empty history (hits, misses, evictions) -- here
# (0, 18, 18): nine slice pairs per turn built and evicted under the default
# growth rule, no reuse at this size; the no-op solver gives (0, 0, 0).
history = Octopus._strong_strong_contract_cpu_cache_history(task)
sum(history) > 0 || error("cache_stats observed nothing: the slice-pair cache history is $(history)")
# CUDA-only sink, stated: the CPU PIC solver records no per-phase timings.
isempty(pic_phase_timings(task)) || error("the CPU PIC solver produced PIC phase timings (a CUDA-only diagnostic until now: update this statement)")
println("coordinates equal across diagnostics on a real CPU PIC collision; turn timings = ", length(turn_timings(task)),
        "; slice-pair cache history (hits, misses, evictions) = ", history)
println("StrongStrongDiagnostics consistency: passed")
