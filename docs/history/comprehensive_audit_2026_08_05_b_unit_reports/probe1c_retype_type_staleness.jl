# U13 probe 1c — the no-epoch retype path made observable: the declared type
# drives `numeric_type` and therefore the compiled element's numeric type, so a
# retype whose VALUE is unchanged still changes the physics precision of every
# freshly compiled line, while an already-built task keeps the old one forever.
using Octopus

reset_knobs!()
@knob a::Real = 1.7
spec = ElementSpec{:quadrupole}(; L = 0.4, nst = 4, kn = (0.0, @knob_expr(a)))
task = TrackingTask((spec,); policy = CPUThreadsExecutionPolicy(threads = 1))
r() = Phase6DRep([1.0e-4], [1.0e-5], [2.0e-4], [2.0e-5], [1.0e-3], [1.0e-4])
r1 = r(); execute!(task, r1; turns = 1)
println("before: knob_value(:a) = ", knob_value(:a), "::", typeof(knob_value(:a)))
println("before: task runtime  = ", typeof(task.runtime_entries_cache[][1][1].element))
println("before: x after 1 turn = ", r1.x[1])
e0 = knob_epoch()

@knob a::BigFloat        # declared-type change; converted value isequal the old

println("\n@knob a::BigFloat")
println("  epoch ", e0, " -> ", knob_epoch(), knob_epoch() == e0 ? "   <== NOT BUMPED" : "")
println("  knob_value(:a) = ", knob_value(:a), "::", typeof(knob_value(:a)))
println("  FRESH compile_runtime(spec) = ", typeof(compile_runtime(spec)))
r2 = r(); execute!(task, r2; turns = 1)
println("  task runtime after 2nd execute! = ",
        typeof(task.runtime_entries_cache[][1][1].element))
println("  stale = ",
        typeof(task.runtime_entries_cache[][1][1].element) !== typeof(compile_runtime(spec)))

# The same object built fresh AFTER the retype -- what the user gets on a
# restart -- versus the cached task: two different numeric types, one script.
task_fresh = TrackingTask((spec,); policy = CPUThreadsExecutionPolicy(threads = 1))
r3 = r(); execute!(task_fresh, r3; turns = 1)
println("\nfresh task runtime = ", typeof(task_fresh.runtime_entries_cache[][1][1].element))
println("cached task x = ", r2.x[1])
println("fresh  task x = ", r3.x[1])
println("difference    = ", Float64(r3.x[1]) - r2.x[1])

# Control: a retype that DOES change the value bumps and recompiles.
reset_knobs!()
@knob b::Real = 0.1
spec2 = ElementSpec{:quadrupole}(; L = 0.4, nst = 4, kn = (0.0, @knob_expr(b)))
task2 = TrackingTask((spec2,); policy = CPUThreadsExecutionPolicy(threads = 1))
execute!(task2, r(); turns = 1)
e0 = knob_epoch(); @knob b::Float32
println("\ncontrol (value changes 0.1 -> 0.1f0): epoch ", e0, " -> ", knob_epoch())
