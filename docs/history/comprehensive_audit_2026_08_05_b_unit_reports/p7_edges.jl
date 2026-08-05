using Octopus
const O = Octopus

println("== g1. `alive` silently disables shape/x_limit/y_limit ==")
s = ApertureSpec(shape=:ellipse, x_limit=1.0e-3, y_limit=1.0e-3,
                 alive=(x,px,y,py,z,pz) -> abs(x) < 1.0)
ap = compile_runtime(s)
println("  shape code stored = ", ap.shape, "  x_limit = ", ap.x_limit)
println("  x = 0.5 (outside the declared 1e-3 ellipse) -> ",
        isnan(ap(0.5, 0.0, 0.0, 0.0, 0.0, 0.0)[1]) ? "KILLED" : "alive (shape ignored)")
bad = ApertureSpec(shape=:ellipse, x_limit=-1.0, y_limit=1.0e-3,
                   alive=(x,px,y,py,z,pz) -> true)
r = try compile_runtime(bad); "accepted (negative x_limit not validated)"
    catch e; "rejected" end
println("  negative x_limit with alive -> ", r)

println()
println("== g2. Float32 slots: the turn column is stored as a float ==")
N = 1
repf = Phase6DRep(Float32[5.0e-3], Float32[0], Float32[0], Float32[0],
                  Float32[0], Float32[0])
rec = O.LossRecord(["C"], N, repf; log=true)
println("  eltype(slots) = ", eltype(rec.slots))
for t in (10, 16777216, 16777217, 16777219)
    println("    turn ", rpad(t, 10), " -> stored ", Float32(t),
            "  exact = ", Int(Float32(t)) == t)
end

println()
println("== g3. the task's loss record is reused across DIFFERENT beams ==")
line = BeamLine("L", ApertureSpec(x_limit=1.0e-3, y_limit=1.0e-3, name="C"))
task = TrackingTask(line)
rep1 = Phase6DRep([5.0e-3, 0.0], [0.0,0.0], [0.0,0.0], [0.0,0.0], [0.0,0.0], [0.0,0.0])
execute!(task, rep1; turns=1)
println("  beam 1: counts = ", loss_counts(loss_record(task)),
        " summary = ", loss_summary(rep1, task))
rec1 = loss_record(task)
rep2 = Phase6DRep([0.0, 0.0], [0.0,0.0], [0.0,0.0], [0.0,0.0], [0.0,0.0], [0.0,0.0])
execute!(task, rep2; turns=1)
println("  beam 2 (pristine, same size/backend):")
println("    same record object = ", loss_record(task) === rec1)
println("    counts = ", loss_counts(loss_record(task)),
        " summary = ", loss_summary(rep2, task))

println()
println("== g4. non-ctx CompositeLine: mixed methods, three natural mixtures ==")
q = QuadrupoleSpec(L=0.4, k1=1.0, nst=1)
mixes = ["magnet + aperture" => BeamLine("M1", q,
              ApertureSpec(x_limit=1e-2, y_limit=1e-2); x_offset=1e-4),
         "magnet + radiation" => BeamLine("M2", q,
              LumpedRadSpec{Float64}(damping_turns=(1e4,1e4,1e4)); x_offset=1e-4),
         "magnet + drift (same method)" => BeamLine("M3", q, DriftSpec(L=1.0);
              x_offset=1e-4)]
for (lbl, ln) in mixes
    rt = compile_runtime(ln)
    r = try
        rt(1e-3, 0.0, 0.0, 0.0, 0.0, 0.0); "OK"
    catch e
        "THREW " * first(sprint(showerror, e), 90)
    end
    println("  ", rpad(lbl, 30), r)
end

println()
println("== g5. hidden-aperture warning: does it see 3 levels deep? ==")
deep = BeamLine("D3", ApertureSpec(x_limit=1e-3, y_limit=1e-3, name="DEEP"))
mid  = BeamLine("D2", deep, DriftSpec(L=1.0))          # dissolves (no own state)
top  = BeamLine("D1", mid; x_offset=1e-4)               # own state at the TOP
t = TrackingTask(top)
println("  (expect a hidden-aperture warning naming DEEP)")
println("  aperture_specs seen by the binder = ",
        [getparam(s,:name,"") for s in O._aperture_specs(t.elements)])
println("done")
