# AUDITOR VERIFICATION of U13-2 and U13-3: cleanup code in execute! that can
# REPLACE the exception that actually stopped the run.
#
#   U13-2  Tasks.jl:396-407 -- the catch block runs _task_loss_summary,
#          _write_task_loss_log and _report_losses BEFORE rethrow(). Any throw
#          from those propagates out of the catch and discards the original.
#   U13-3  Tasks.jl:519-528 -- the finally block runs finalizers; Julia's
#          `finally` semantics make a throw there replace the in-flight
#          exception.
#
# Both hide the physics error that stopped the run behind an I/O or teardown
# error, which is the opposite of what a user needs after a crash.
using Octopus
import Octopus: AbstractBeamAction, AbstractBeamObserver, apply_action!,
                observe!, finalize_observer!

const REAL = "REAL_TRACKING_ERROR"

struct BoomAction <: AbstractBeamAction end
Octopus.apply_action!(::BoomAction, ctx, rep) = error(REAL)

struct BoomFinalizeObserver <: AbstractBeamObserver end
Octopus.observe!(::BoomFinalizeObserver, ctx, rep) = nothing
Octopus.finalize_observer!(::BoomFinalizeObserver) = error("FINALIZER_ERROR")

mkrep() = Phase6DRep([1.0e-4], [0.0], [1.0e-4], [0.0], [0.0], [0.0])

function surfaced(f)
    try
        f(); return "NO ERROR RAISED"
    catch e
        return sprint(showerror, e)
    end
end

println("### U13-2: an unwritable loss_log on the crash path")
msg = surfaced() do
    dir = mktempdir()
    task = TrackingContext === nothing ? nothing : TrackingTask(
        (ApertureSpec(shape = :ellipse, x_limit = 1.0, y_limit = 1.0),);
        hooks = (BoomAction(),),
        loss_log = joinpath(dir, "no_such_dir", "loss.h5"))
    execute!(task, mkrep(); turns = 2)
end
println("  surfaced: ", first(msg, 130))
println("  contains the REAL error? ", occursin(REAL, msg),
        "   <- false means the real error was replaced")

println()
println("### U13-3: a throwing observer finalizer while a real error is in flight")
msg2 = surfaced() do
    task = TrackingTask((MarkerSpec(),);
                        hooks = (BoomAction(), ScheduledObserver(BoomFinalizeObserver())))
    execute!(task, mkrep(); turns = 2)
end
println("  surfaced: ", first(msg2, 130))
println("  contains the REAL error? ", occursin(REAL, msg2),
        "   <- false means the real error was replaced")

println()
println("### control: the real error alone must surface cleanly")
msg3 = surfaced() do
    task = TrackingTask((MarkerSpec(),); hooks = (BoomAction(),))
    execute!(task, mkrep(); turns = 2)
end
println("  surfaced: ", first(msg3, 90))
println("  contains the REAL error? ", occursin(REAL, msg3))

println()
println("### success path must STILL raise a finalizer failure (not swallow it)")
msg4 = surfaced() do
    task = TrackingTask((MarkerSpec(),);
                        hooks = (ScheduledObserver(BoomFinalizeObserver()),))
    execute!(task, mkrep(); turns = 2)
end
println("  surfaced: ", first(msg4, 90))
println("  raises FINALIZER_ERROR on a clean run? ", occursin("FINALIZER_ERROR", msg4),
        "   <- must be true; swallowing it would lose data silently")
