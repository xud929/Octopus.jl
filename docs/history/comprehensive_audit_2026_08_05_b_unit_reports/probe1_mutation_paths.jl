# U13 probe 1 — re-derive every knob mutation path and assert that a stale
# compiled-task cache is actually invalidated by it.
using Octopus
using Octopus: _forget_knob!, _KNOB_TABLE, _runtime_entries

const R = () -> Phase6DRep([1.0e-4], [1.0e-5], [2.0e-4], [2.0e-5], [1.0e-3], [1.0e-4])

# Build a task whose element parameter is driven by knob `a` through the
# dependent knob `b` (b = a * 3.0), so one probe covers both the compiled
# runtime cache and the dependent-value memo.
function fresh(; bare_ref::Bool=false)
    reset_knobs!()
    Octopus._knob_define!(:a, nothing, 2.0, nothing)
    Octopus._knob_define!(:b, nothing, :(a * 3.0), nothing)
    ex = bare_ref ? Octopus._knob_expression_build(:a) :
                    Octopus._knob_expression_build(:b)
    spec = ElementSpec{:crab_dispersion}(;
        zeta1 = ex, zeta2 = 0.0, zeta3 = 0.0, zeta4 = 0.0,
        tracking_method = Symplectic6DMap())
    task = TrackingTask((spec,); policy = CPUThreadsExecutionPolicy(threads = 1))
    execute!(task, R(); turns = 1)          # compiles + caches the runtime line
    return task, spec
end

compiled(task) = begin
    entries = task.runtime_entries_cache[][1]
    entries[1].element.zeta1
end
knob_dep(task) = task.runtime_entries_cache[][2]

results = Any[]
function check(name, mutate!; expect_compiled, bare_ref::Bool=false, dep_expect=nothing)
    task, spec = fresh(; bare_ref=bare_ref)
    before_compiled = compiled(task)
    before_epoch = knob_epoch()
    before_dep = try knob_value(:b) catch e; :error end
    ok_mut = true
    err = nothing
    try
        mutate!(task, spec)
    catch e
        ok_mut = false
        err = e
    end
    after_epoch = knob_epoch()
    after_dep = try knob_value(:b) catch e; :error end
    # second execute! is what a user would do; it must pick up the change
    try
        execute!(task, R(); turns = 1)
    catch e
        err === nothing && (err = e)
    end
    after_compiled = compiled(task)
    push!(results, (name = name,
                    epoch_bumped = after_epoch != before_epoch,
                    compiled_before = before_compiled,
                    compiled_after = after_compiled,
                    compiled_type = typeof(after_compiled),
                    dep_before = before_dep, dep_after = after_dep,
                    knob_dependent = knob_dep(task),
                    expect = expect_compiled,
                    invalidated = !isequal(after_compiled, before_compiled),
                    matches_expected = isequal(after_compiled, expect_compiled),
                    mutate_threw = !ok_mut,
                    err = err === nothing ? nothing : sprint(showerror, err)))
end

# ---------------------------------------------------------------------------
# M1  set_knob! on the independent input
check("M1 set_knob!(:a, 5.0)", (t, s) -> set_knob!(:a, 5.0); expect_compiled = 15.0)
# M2  namespace assignment through the `knobs` root
check("M2 knobs.a = 5.0", (t, s) -> (knobs.a = 5.0); expect_compiled = 15.0)
# M3  @knob macro reassignment of an independent knob (constant rhs)
check("M3 @knob a = 5.0 (macro path)",
      (t, s) -> Octopus._knob_define!(:a, nothing, 5.0, nothing); expect_compiled = 15.0)
# M4  redefine the DEPENDENT knob's expression
check("M4 redefine b := a * 10.0",
      (t, s) -> Octopus._knob_define!(:b, nothing, :(a * 10.0), nothing);
      expect_compiled = 20.0)
# M5  turn the dependent knob into an independent one
check("M5 redefine b = 99.0 (dependent -> independent)",
      (t, s) -> Octopus._knob_define!(:b, nothing, 99.0, nothing); expect_compiled = 99.0)
# M6  bare retype of an independent knob, value CHANGES
check("M6 @knob a::Float32 (0.1-like value change)", (t, s) -> begin
          set_knob!(:a, 0.1)
          Octopus._knob_define!(:a, Float32, nothing, nothing)
      end; expect_compiled = Float64(0.1f0) * 3.0)
# M7  bare retype, value numerically EQUAL (Float64 -> Float32 of 2.0)
check("M7 @knob a::Float32 (value numerically equal)",
      (t, s) -> Octopus._knob_define!(:a, Float32, nothing, nothing);
      expect_compiled = 6.0, bare_ref = true)
# M8  bare retype Float64 -> Int, value numerically equal
check("M8 @knob a::Int (2.0 -> 2, numerically equal)",
      (t, s) -> Octopus._knob_define!(:a, Int, nothing, nothing);
      expect_compiled = 2, bare_ref = true)
# M9  reset_knobs!
check("M9 reset_knobs!", (t, s) -> reset_knobs!(); expect_compiled = :error)
# M10 _forget_knob!
check("M10 _forget_knob!(:a)", (t, s) -> _forget_knob!(:a); expect_compiled = :error)
# M11 brand-new bare declaration (bumps; nothing can consume it)
check("M11 @knob zzz (new bare decl)",
      (t, s) -> Octopus._knob_define!(:zzz, nothing, nothing, nothing);
      expect_compiled = 6.0)
# M12 bare retype of an UNSET knob (type-only, no value)
check("M12 @knob unset::Int (no value)", (t, s) -> begin
          Octopus._knob_define!(:unset, nothing, nothing, nothing)
          Octopus._knob_define!(:unset, Int, nothing, nothing)
      end; expect_compiled = 6.0)
# M13 non-Real knob redefinition through the thunk path
check("M13 @knob sym::Symbol = :two (thunk path)", (t, s) -> begin
          Octopus._knob_define!(:sym, Symbol, :(:one), () -> :one)
          Octopus._knob_define!(:sym, Symbol, :(:two), () -> :two)
      end; expect_compiled = 6.0)

println("name | epoch_bumped | knob_dependent | compiled before -> after (type) | expected | OK")
for r in results
    println(rpad(r.name, 46), " | ", r.epoch_bumped ? "yes" : "NO ", " | ",
            r.knob_dependent ? "yes" : "NO ", " | ",
            r.compiled_before, " -> ", r.compiled_after, " (", r.compiled_type, ")",
            " | ", r.expect, " | ", r.matches_expected ? "ok" : "MISMATCH",
            r.err === nothing ? "" : "   err=" * first(r.err, 90))
end

println()
println("dependent-knob memo (knob_value(:b)) before -> after mutation:")
for r in results
    println(rpad(r.name, 46), " ", r.dep_before, " -> ", r.dep_after)
end
