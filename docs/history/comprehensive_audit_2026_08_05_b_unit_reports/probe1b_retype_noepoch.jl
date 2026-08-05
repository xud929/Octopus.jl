# U13 probe 1b — the one mutation path that does NOT bump the epoch:
# `@knob a::T` where the converted value is `isequal` to the old one.
# Knobs.jl `_knob_define!`, bare-declaration branch: `changed = !isequal(...)`.
using Octopus

reset_knobs!()
@knob a = 2.0
spec = ElementSpec{:crab_dispersion}(;
    zeta1 = @knob_expr(a), zeta2 = 0.0, zeta3 = 0.0, zeta4 = 0.0,
    tracking_method = Symplectic6DMap())
task = TrackingTask((spec,); policy = CPUThreadsExecutionPolicy(threads = 1))
r = Phase6DRep([1.0e-4], [1.0e-5], [2.0e-4], [2.0e-5], [1.0e-3], [1.0e-4])
execute!(task, r; turns = 1)
cached_before = task.runtime_entries_cache[][1][1].element
println("before: knob_value(:a) = ", knob_value(:a), "::", typeof(knob_value(:a)))
println("before: cached runtime = ", typeof(cached_before), " zeta1=", cached_before.zeta1)
e0 = knob_epoch()

@knob a::Float32                      # bare retype, value exactly representable

println("after @knob a::Float32:")
println("  knob_epoch  ", e0, " -> ", knob_epoch(), knob_epoch() == e0 ? "   (NOT BUMPED)" : "")
println("  knob_value(:a) = ", knob_value(:a), "::", typeof(knob_value(:a)))
fresh_rt = compile_runtime(spec)
println("  a FRESH compile_runtime(spec) gives ", typeof(fresh_rt), " zeta1=", fresh_rt.zeta1)

execute!(task, r; turns = 1)
cached_after = task.runtime_entries_cache[][1][1].element
println("  the TASK after a second execute! still holds ", typeof(cached_after),
        " zeta1=", cached_after.zeta1)
println("  stale? ", typeof(cached_after) !== typeof(fresh_rt))

# Same thing with a declared-type change that alters the numeric TYPE of a
# whole element: Float64 -> Int.
reset_knobs!()
@knob c = 2.0
spec2 = ElementSpec{:crab_dispersion}(;
    zeta1 = @knob_expr(c), zeta2 = 0.0, zeta3 = 0.0, zeta4 = 0.0,
    tracking_method = Symplectic6DMap())
task2 = TrackingTask((spec2,); policy = CPUThreadsExecutionPolicy(threads = 1))
execute!(task2, r; turns = 1)
e0 = knob_epoch()
@knob c::Int
println()
println("Float64 -> Int retype: epoch ", e0, " -> ", knob_epoch())
println("  knob_value(:c) = ", knob_value(:c), "::", typeof(knob_value(:c)))
println("  fresh compile   = ", typeof(compile_runtime(spec2)))
execute!(task2, r; turns = 1)
println("  task after re-execute = ", typeof(task2.runtime_entries_cache[][1][1].element))

# And the same for a knob whose retype changes a DEPENDENT knob's cached type.
reset_knobs!()
@knob p = 4.0
@knob q = sqrt(p)
println()
println("dependent memo before: ", knob_value(:q), "::", typeof(knob_value(:q)))
e0 = knob_epoch()
@knob p::Float32
println("after @knob p::Float32 epoch ", e0, " -> ", knob_epoch(),
        "; knob_value(:q) = ", knob_value(:q), "::", typeof(knob_value(:q)))
