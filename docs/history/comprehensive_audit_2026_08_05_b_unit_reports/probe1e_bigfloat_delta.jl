using Octopus
reset_knobs!()
@knob a::Real = 1.7
spec = ElementSpec{:quadrupole}(; L = 0.4, nst = 4, kn = (0.0, @knob_expr(a)))
mk() = Phase6DRep([1.0e-4], [1.0e-5], [2.0e-4], [2.0e-5], [1.0e-3], [1.0e-4])
task = TrackingTask((spec,); policy = CPUThreadsExecutionPolicy(threads = 1))
r1 = mk(); execute!(task, r1; turns = 12)
e0 = knob_epoch()
@knob a::BigFloat
println("epoch ", e0, " -> ", knob_epoch())
r2 = mk(); execute!(task, r2; turns = 12)
tf = TrackingTask((spec,); policy = CPUThreadsExecutionPolicy(threads = 1))
r3 = mk(); execute!(tf, r3; turns = 12)
println("cached-task runtime = ", typeof(task.runtime_entries_cache[][1][1].element))
println("fresh -task runtime = ", typeof(tf.runtime_entries_cache[][1][1].element))
println("x cached = ", r2.x[1])
println("x fresh  = ", r3.x[1])
println("abs delta = ", abs(Float64(r3.x[1]) - Float64(r2.x[1])),
        "   rel = ", abs(Float64(r3.x[1]) - Float64(r2.x[1]))/abs(Float64(r3.x[1])))
