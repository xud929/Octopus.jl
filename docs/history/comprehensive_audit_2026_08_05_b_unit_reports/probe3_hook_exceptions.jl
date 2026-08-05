# U13 probe 3 — hypothesis (d): swallowed hook exceptions, and schedules that
# silently do nothing.
using Octopus

tmp = mktempdir()
mk(n=2) = Phase6DRep([1.0e-4 * i for i in 1:n], zeros(n), [1.0e-4 * i for i in 1:n],
                     zeros(n), zeros(n), zeros(n))
drift = ElementSpec{:drift}(; L = 0.5, tracking_method = Symplectic6DMap())
ap() = ApertureSpec(shape = :rectangle, x_limit = 1.0, y_limit = 1.0, name = "COLL")

struct BoomAction <: AbstractBeamAction end
Octopus.apply_action!(::BoomAction, ctx, rep) = error("REAL_TRACKING_ERROR")

mutable struct CountingObserver <: AbstractBeamObserver
    n::Int
    finalized::Int
    boom_finalize::Bool
end
CountingObserver(; boom = false) = CountingObserver(0, 0, boom)
Octopus.observe!(o::CountingObserver, ctx, rep) = (o.n += 1; nothing)
Octopus.finalize_observer!(o::CountingObserver) =
    (o.finalized += 1; o.boom_finalize && error("FINALIZER_ERROR"); nothing)

println("=== D1. exception in the FAILURE-PATH loss report masks the real error ===")
# loss_log in a directory that does not exist -> the writer throws while the
# real tracking error is in flight.
badlog = joinpath(tmp, "no_such_dir", "loss.h5")
t1 = TrackingTask((drift, ap()); policy = CPUThreadsExecutionPolicy(threads = 1),
                  hooks = (BoomAction(),), loss_log = badlog)
try
    execute!(t1, mk(); turns = 1)
catch e
    m = sprint(showerror, e)
    println("  surfaced: ", first(m, 120))
    println("  REAL error preserved? ", occursin("REAL_TRACKING_ERROR", m))
end

println()
println("=== D2. exception in finalize_observers! masks the real tracking error ===")
obs = CountingObserver(; boom = true)
t2 = TrackingTask((drift,); policy = CPUThreadsExecutionPolicy(threads = 1),
                  hooks = (BoomAction(), ScheduledObserver(obs)))
try
    execute!(t2, mk(); turns = 1)
catch e
    m = sprint(showerror, e)
    println("  surfaced: ", first(m, 120))
    println("  REAL error preserved? ", occursin("REAL_TRACKING_ERROR", m))
    println("  observer finalized ", obs.finalized, " time(s)")
end

println()
println("=== D3. an every-N schedule with N larger than the run ===")
o3 = CountingObserver()
t3 = TrackingTask((drift,); policy = CPUThreadsExecutionPolicy(threads = 1),
                  hooks = (ScheduledObserver(o3, EveryNSteps(start = 0, step = 1000)),))
execute!(t3, mk(); turns = 10)
println("  10 turns, EveryNSteps(step=1000): observe! ran ", o3.n, " time(s)")
o3b = CountingObserver()
t3b = TrackingTask((drift,); policy = CPUThreadsExecutionPolicy(threads = 1),
                   hooks = (ScheduledObserver(o3b, AtTurns([500])),))
execute!(t3b, mk(); turns = 10)
println("  10 turns, AtTurns([500]):          observe! ran ", o3b.n, " time(s)")
o3c = CountingObserver()
t3c = TrackingTask((drift,); policy = CPUThreadsExecutionPolicy(threads = 1),
                   hooks = (ScheduledObserver(o3c, EveryNSteps(start = 0, stop = 0)),))
execute!(t3c, mk(); turns = 10)
println("  10 turns, EveryNSteps(stop=0):     observe! ran ", o3c.n, " time(s)")
println("  (any warning above? if not, the schedule is silently inert)")

println()
println("=== D4. turns=0 still prepares and finalizes ===")
o4 = CountingObserver()
t4 = TrackingTask((drift,); policy = CPUThreadsExecutionPolicy(threads = 1),
                  hooks = (ScheduledObserver(o4),))
execute!(t4, mk(); turns = 0)
println("  turns=0: observe! ", o4.n, ", finalize ", o4.finalized,
        ", next_turn ", t4.next_turn[])
execute!(t4, mk(); turns = 2)
println("  then turns=2: observe! ", o4.n, ", finalize ", o4.finalized,
        ", next_turn ", t4.next_turn[])
println("  NOTE: finalize_observer! runs once per execute! call, not once per task.")

println()
println("=== D5. a failed call leaves the beam advanced but the turn counter not ===")
struct BoomOnTurn <: AbstractBeamAction
    turn::Int
end
Octopus.apply_action!(a::BoomOnTurn, ctx, rep) =
    ctx.turn == a.turn ? error("BOOM_AT_TURN_$(a.turn)") : nothing
t5 = TrackingTask((drift,); policy = CPUThreadsExecutionPolicy(threads = 1),
                  hooks = (BoomOnTurn(3),))
r5 = mk()
x0 = r5.x[1]
try
    execute!(t5, r5; turns = 5)
catch e
    println("  threw: ", first(sprint(showerror, e), 60))
end
println("  next_turn after failure = ", t5.next_turn[], " (documented: not advanced)")
println("  beam x advanced from ", x0, " to ", r5.x[1],
        "  => a retry re-tracks turns 0..2 a second time")
