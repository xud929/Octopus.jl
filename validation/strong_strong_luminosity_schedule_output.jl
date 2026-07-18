#=
Check that scheduled strong-strong luminosity output contains only evaluated
turns and never writes skipped-turn NaN markers. Run from the project root:

    julia --project=. validation/strong_strong_luminosity_schedule_output.jl
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus

struct ScheduledValidationSolver <: AbstractPoissonSolver
    schedule::EveryNSteps
    offset::Float64
end

function Octopus.collide!(solver::ScheduledValidationSolver, beam1::Beam, beam2::Beam,
                          backend, ctx::TrackingContext)
    should_run(solver.schedule, ctx) || return NaN
    return ctx.turn == 100 && solver.offset == 0.0 ? NaN : Float64(ctx.turn + 1) + solver.offset
end
Octopus._strong_strong_luminosity_evaluated(solver::ScheduledValidationSolver,
                                            ctx::TrackingContext) =
    should_run(solver.schedule, ctx)

path = tempname() * ".lum"
schedule = EveryNSteps(step=100)
ip1 = StrongStrongCollision(:ip1; poisson_solver=ScheduledValidationSolver(schedule, 0.0))
ip2 = StrongStrongCollision(:ip2; poisson_solver=ScheduledValidationSolver(schedule, 1000.0))
task = StrongStrongTask((ip1, ip2), (ip1, ip2); luminosity_path=path)
beam1 = Beam(1, CPUThreadsExecutionPolicy(), Float64)
beam2 = Beam(1, CPUThreadsExecutionPolicy(), Float64)
execute!(task, beam1, beam2; turns=201)

rows = readlines(path)
expected = [
    "turn\tip1\tip2",
    "0\t1.0\t1001.0",
    "100\tNaN\t1101.0",
    "200\t201.0\t1201.0",
]
println("Strong-strong scheduled luminosity output")
println("rows = ", rows)
println("expected = ", expected)
rows == expected || error("scheduled luminosity output omitted evaluated NaN or contains skipped turns")
println("passed = true")
