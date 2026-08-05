# U13 probe 2 — Tasks.jl driver seams:
#   A. knob-expression :L reaching `_aperture_s_positions` through the loss log
#   B. an exception raised inside the failure-path loss report masking the
#      original exception
#   C. loss_report=false really switching off DETECTION (not just printing)
using Octopus

tmp = mktempdir()
mk(n=4) = Phase6DRep([1.0e-3 * i for i in 1:n], zeros(n), [1.0e-3 * i for i in 1:n],
                     zeros(n), zeros(n), zeros(n))
ap() = ApertureSpec(shape = :rectangle, x_limit = 1.5e-3, y_limit = 1.0, name = "COLL")

println("=== A. knob-driven :L + aperture + loss_log ===")
reset_knobs!()
@knob len = 0.5
drift = ElementSpec{:drift}(; L = @knob_expr(len), tracking_method = Symplectic6DMap())
logA = joinpath(tmp, "lossA.h5")
taskA = TrackingTask((drift, ap()); policy = CPUThreadsExecutionPolicy(threads = 1),
                     loss_log = logA)
try
    execute!(taskA, mk(); turns = 1)
    println("  execute! OK; loss log written = ", isfile(logA))
catch e
    println("  execute! THREW: ", first(sprint(showerror, e), 200))
end
drift2 = ElementSpec{:drift}(; L = 0.5, tracking_method = Symplectic6DMap())
logA2 = joinpath(tmp, "lossA2.h5")
taskA2 = TrackingTask((drift2, ap()); policy = CPUThreadsExecutionPolicy(threads = 1),
                      loss_log = logA2)
try
    execute!(taskA2, mk(); turns = 1)
    println("  control (numeric L) OK; loss log written = ", isfile(logA2))
catch e
    println("  control THREW: ", first(sprint(showerror, e), 200))
end
# and without a loss_log the same knob-driven line is fine?
taskA3 = TrackingTask((drift, ap()); policy = CPUThreadsExecutionPolicy(threads = 1))
try
    execute!(taskA3, mk(); turns = 1)
    println("  knob L, no loss_log: OK")
catch e
    println("  knob L, no loss_log THREW: ", first(sprint(showerror, e), 200))
end

println()
println("=== B. exception inside the failure-path loss report ===")
struct BoomAction <: AbstractBeamAction end
Octopus.apply_action!(::BoomAction, ctx, rep) = error("THE REAL PHYSICS ERROR")
logB = joinpath(tmp, "lossB.h5")
taskB = TrackingTask((drift, ap()); policy = CPUThreadsExecutionPolicy(threads = 1),
                     hooks = (BoomAction(),), loss_log = logB)
try
    execute!(taskB, mk(); turns = 1)
    println("  no error (unexpected)")
catch e
    msg = sprint(showerror, e)
    println("  surfaced error: ", first(msg, 200))
    println("  original error preserved? ", occursin("THE REAL PHYSICS ERROR", msg))
end

println()
println("=== C. loss_report=false switches off detection ===")
for lr in (true, false)
    r = mk(2); r.x[1] = NaN
    t = TrackingTask((drift2, ap()); policy = CPUThreadsExecutionPolicy(threads = 1),
                     loss_report = lr)
    println("  loss_report=", lr, " -> execute!:")
    execute!(t, r; turns = 1)
    s = Octopus._task_loss_summary(t, r)
    println("    _task_loss_summary = ", s === nothing ? "nothing (detection OFF)" : string(s))
end
for lr in (true, false)
    r = mk(2); r.x[1] = NaN
    f = joinpath(tmp, "lossC_$(lr).h5")
    t = TrackingTask((drift2, ap()); policy = CPUThreadsExecutionPolicy(threads = 1),
                     loss_report = lr, loss_log = f)
    execute!(t, r; turns = 1)
    println("  loss_log with loss_report=", lr, ": file=", isfile(f))
end
println("tmpdir = ", tmp)
