using Octopus
const O = Octopus

ctx0 = O.with_turn(O.TrackingContext(), 3)

println("== 1. boundary: exactly ON the limit ==")
for shape in (:rectangle, :ellipse, :rectellipse)
    ap = compile_runtime(ApertureSpec(shape=shape, x_limit=2.0e-2, y_limit=5.0e-3))
    for (lbl, x, y) in (("x == x_limit    ", 2.0e-2, 0.0),
                        ("x = nextfloat   ", nextfloat(2.0e-2), 0.0),
                        ("x = prevfloat   ", prevfloat(2.0e-2), 0.0),
                        ("y == y_limit    ", 0.0, 5.0e-3),
                        ("corner (a,b)    ", 2.0e-2, 5.0e-3))
        out = ap(x, 0.0, y, 0.0, 0.0, 0.0)
        println("  ", rpad(String(shape), 12), lbl, " -> ",
                isnan(out[1]) ? "KILLED" : "alive")
    end
end

println()
println("== 2. two overlapping apertures: which claims the loss ==")
# COLL_A is WIDE, COLL_B is TIGHT; a particle outside both meets A first.
a = ApertureSpec(x_limit=1.0e-2, y_limit=1.0e-2, name="COLL_A")
b = ApertureSpec(x_limit=1.0e-3, y_limit=1.0e-3, name="COLL_B")
line = BeamLine("OVL", a, b)
task = TrackingTask(line; loss_log=tempname() * ".h5")
rep = Phase6DRep([5.0e-3, 5.0e-2], [0.0,0.0], [0.0,0.0], [0.0,0.0], [0.0,0.0], [0.0,0.0])
execute!(task, rep; turns=1)
rec = loss_record(task)
println("  names  = ", aperture_names(rec))
println("  counts = ", loss_counts(rec), "   (particle 1 only B can kill; particle 2 both)")
println("  s      = ", O._aperture_s_positions(task.elements))
r = loss_records(rec)
println("  rows   = ", collect(zip(r.particle_id, r.element_id, r.turn)))

println()
println("== 3. reversed order (tight first) ==")
line2 = BeamLine("OVL2", b, a)
task2 = TrackingTask(line2)
rep2 = Phase6DRep([5.0e-3, 5.0e-2], [0.0,0.0], [0.0,0.0], [0.0,0.0], [0.0,0.0], [0.0,0.0])
execute!(task2, rep2; turns=1)
rec2 = loss_record(task2)
println("  names  = ", aperture_names(rec2), " counts = ", loss_counts(rec2))

println()
println("== 4. F15: raw compile_runtime aperture with an out-of-range element_id ==")
rep3 = Phase6DRep([0.0], [0.0], [0.0], [0.0], [0.0], [0.0])
shared = O.LossRecord(["ONLY"], 1, rep3; log=true)
for id in (0, 1, 2, -5, 99)
    apraw = compile_runtime(ApertureSpec(x_limit=1.0e-9, y_limit=1.0e-9,
                                         loss_record=shared, element_id=id))
    before = copy(loss_counts(shared))
    out = try
        apraw(ctx0, 1, 5.0e-3, 0.0, 0.0, 0.0, 0.0, 0.0)
    catch e
        ("THREW", sprint(showerror, e)[1:min(end,120)])
    end
    println("  element_id=", rpad(id, 4), " kill=", out isa Tuple && out[1] isa Float64 ? isnan(out[1]) : out,
            "  counts ", before, " -> ", loss_counts(shared))
end

println()
println("== 5. unattributed warning with NO aperture at all in the line ==")
bad = BeamLine("NOAP", DriftSpec(L=1.0))
task5 = TrackingTask(bad)
rep5 = Phase6DRep([NaN, 0.0], [0.0,0.0], [0.0,0.0], [0.0,0.0], [0.0,0.0], [0.0,0.0])
execute!(task5, rep5; turns=1)
println("  loss_record(task5) = ", loss_record(task5))
println("  summary = ", loss_summary(rep5, task5))

println()
println("== 6. LossRecord with zero apertures: counts length ==")
empty_rec = O.LossRecord(String[], 4, rep3; log=false)
println("  length(counts) = ", length(loss_counts(empty_rec)),
        "   names = ", aperture_names(empty_rec))
println("  loss_summary logged = ", loss_summary(rep3, empty_rec).logged)

println()
println("== 7. an aperture whose loss_record is set BY HAND on the spec ==")
byhand = ApertureSpec(x_limit=1.0e-9, y_limit=1.0e-9, loss_record=shared, name="HAND")
line7 = BeamLine("BYHAND", byhand)
task7 = TrackingTask(line7)
rep7 = Phase6DRep([5.0e-3], [0.0], [0.0], [0.0], [0.0], [0.0])
try
    execute!(task7, rep7; turns=1)
    println("  ran; task record counts = ", loss_counts(loss_record(task7)),
            " shared counts = ", loss_counts(shared))
catch e
    println("  THREW: ", sprint(showerror, e)[1:min(end,200)])
end

println()
println("== 8. dead-on-arrival particle is not attributed to a downstream aperture ==")
line8 = BeamLine("DOA", ApertureSpec(x_limit=1.0, y_limit=1.0, name="WIDE"))
task8 = TrackingTask(line8)
rep8 = Phase6DRep([0.0, 0.0], [NaN, 0.0], [0.0,0.0], [0.0,0.0], [0.0,0.0], [0.0,0.0])
execute!(task8, rep8; turns=1)
println("  counts = ", loss_counts(loss_record(task8)),
        " summary = ", loss_summary(rep8, task8))
println("done")
