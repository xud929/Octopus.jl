# U13 probe 1d — the no-bump retype path with a MEASURABLE tracking difference:
# widening Float32 -> Float64 leaves the stored value numerically identical
# (`isequal` true) so no epoch is bumped, but every freshly compiled line now
# tracks in double precision while the already-built task stays single.
using Octopus

reset_knobs!()
@knob a::Float32 = 1.7
spec = ElementSpec{:quadrupole}(; L = 0.4f0, nst = 4, kn = (0.0f0, @knob_expr(a)))
mk() = Phase6DRep(Float32[1.0e-4], Float32[1.0e-5], Float32[2.0e-4],
                  Float32[2.0e-5], Float32[1.0e-3], Float32[1.0e-4])
task = TrackingTask((spec,); policy = CPUThreadsExecutionPolicy(threads = 1))
r1 = mk(); execute!(task, r1; turns = 20)
println("before: knob_value(:a)::", typeof(knob_value(:a)),
        "  runtime ", typeof(task.runtime_entries_cache[][1][1].element))
e0 = knob_epoch()

@knob a::Float64          # widen the declared type; value is unchanged

println("@knob a::Float64: epoch ", e0, " -> ", knob_epoch(),
        knob_epoch() == e0 ? "   <== NOT BUMPED" : "")
println("  knob_value(:a) = ", knob_value(:a), "::", typeof(knob_value(:a)))
println("  fresh compile  = ", typeof(compile_runtime(spec)))
r2 = mk(); execute!(task, r2; turns = 20)
println("  cached task runtime after re-execute = ",
        typeof(task.runtime_entries_cache[][1][1].element))

task_fresh = TrackingTask((spec,); policy = CPUThreadsExecutionPolicy(threads = 1))
r3 = mk(); execute!(task_fresh, r3; turns = 20)
println("  fresh task runtime = ", typeof(task_fresh.runtime_entries_cache[][1][1].element))
println("  x (cached task) = ", r2.x[1])
println("  x (fresh  task) = ", r3.x[1])
println("  |delta|         = ", abs(Float64(r3.x[1]) - Float64(r2.x[1])))
println("  relative        = ",
        abs(Float64(r3.x[1]) - Float64(r2.x[1])) / abs(Float64(r3.x[1])))
