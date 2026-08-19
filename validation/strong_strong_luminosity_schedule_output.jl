#=
Check that the run artifact's scheduled strong-strong luminosity channels
contain only evaluated turns (skipped turns leave no row, not a NaN marker),
that an EVALUATED NaN is retained honestly, and that each collision keeps its
own turn axis. Run from the project root:

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

path = tempname() * ".h5"
schedule = EveryNSteps(step=100)
ip1 = StrongStrongCollision(:ip1; poisson_solver=ScheduledValidationSolver(schedule, 0.0))
ip2 = StrongStrongCollision(:ip2; poisson_solver=ScheduledValidationSolver(schedule, 1000.0))
task = StrongStrongTask((ip1, ip2), (ip1, ip2); artifact=path)
beam1 = Beam(1, CPUThreadsExecutionPolicy(), Float64)
beam2 = Beam(1, CPUThreadsExecutionPolicy(), Float64)
execute!(task, beam1, beam2; turns=201)

series = read(TaskOutput(path), :luminosity)
println("Strong-strong scheduled luminosity artifact channels")
println("ip1 = ", series["ip1"])
println("ip2 = ", series["ip2"])
series["ip1"].turn == [0, 100, 200] && series["ip2"].turn == [0, 100, 200] ||
    error("scheduled luminosity channels contain skipped turns or omit evaluated ones")
v1, v2 = series["ip1"].value, series["ip2"].value
(v1[1] == 1.0 && isnan(v1[2]) && v1[3] == 201.0) ||
    error("ip1 channel altered its evaluated values (an evaluated NaN must be retained)")
v2 == [1001.0, 1101.0, 1201.0] ||
    error("ip2 channel altered its evaluated values")
println("passed = true")
