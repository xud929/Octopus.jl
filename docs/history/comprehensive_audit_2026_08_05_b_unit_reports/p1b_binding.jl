using Octopus
const O = Octopus

set_param!(s, k, v) = Octopus.set_param!(s, k, v)

q  = QuadrupoleSpec(L=0.4, k1=1.7, nst=2)
d  = DriftSpec(L=1.0)
mk = MarkerSpec()
apin  = ApertureSpec(x_limit=1.0e-2, y_limit=1.0e-2, name="COLL_IN")
apout = ApertureSpec(x_limit=2.0e-2, y_limit=2.0e-2, name="COLL_OUT")

L3 = BeamLine("L3", mk, q, apin, d; x_offset=2.0e-4)
L2 = BeamLine("L2", L3, d; y_offset=1.0e-4)
L1 = BeamLine("L1", L2, q, apout, d)

println("== task-level binding over the nested line ==")
task = TrackingTask(L1)
rep = Phase6DRep([1.0e-3, 5.0e-2], [0.0, 0.0], [0.0, 0.0], [0.0, 0.0],
                 [0.0, 0.0], [0.0, 0.0])
execute!(task, rep; turns=1)
rec = loss_record(task)
println("counts len = ", length(loss_counts(rec)), " names = ", aperture_names(rec),
        " counts = ", loss_counts(rec))
println("summary = ", loss_summary(rep, task))

println()
println("== placement aliasing through reverse ==")
cell = BeamLine("CELL", q, d; x_offset=1.0e-4)   # own state so it survives
arc  = BeamLine("ARC", q, d)                      # dissolves
rev  = reverse(arc)
println("arc[1] === rev[2] : ", arc[1] === rev[2])
rev[2].x_offset = 3.3e-3
println("after rev[2].x_offset = 3.3e-3 -> arc[1].x_offset = ",
        getparam(arc[1], :x_offset, missing))
println("(a shared LineEntry means an override on the reflection leaks to the source)")

println()
println("== reverse: entries container type ==")
println("typeof(line_entries(arc)) = ", typeof(line_entries(arc)))
println("typeof(line_entries(rev)) = ", typeof(line_entries(rev)))

println()
println("== non-ctx CompositeLine path with mixed tracking methods ==")
mixed = BeamLine("MIX", q, apout; x_offset=1.0e-4)
rt = compile_runtime(mixed)
println("compiled: ", nameof(typeof(rt)))
try
    out = rt(1.0e-3, 0.0, 0.0, 0.0, 0.0, 0.0)
    println("  non-ctx call OK -> ", out)
catch e
    println("  non-ctx call THREW: ", sprint(showerror, e)[1:min(end,300)])
end
ctx = O.with_turn(O.TrackingContext(), 0)
try
    out = rt(ctx, 1, 1.0e-3, 0.0, 0.0, 0.0, 0.0, 0.0)
    println("  ctx call OK -> ", out)
catch e
    println("  ctx call THREW: ", sprint(showerror, e)[1:min(end,300)])
end

println()
println("== same, aperture first (so borrowed method is NonSymplectic) ==")
mixed2 = BeamLine("MIX2", apout, q; x_offset=1.0e-4)
rt2 = compile_runtime(mixed2)
try
    out = rt2(1.0e-3, 0.0, 0.0, 0.0, 0.0, 0.0)
    println("  non-ctx call OK -> ", out)
catch e
    println("  non-ctx call THREW: ", sprint(showerror, e)[1:min(end,300)])
end
println("done")
