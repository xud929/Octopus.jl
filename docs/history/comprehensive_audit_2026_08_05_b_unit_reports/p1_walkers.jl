using Octopus
const O = Octopus

println("="^78)
println("P1: walker agreement over a 3-deep nested BeamLine")
println("="^78)

q  = QuadrupoleSpec(L=0.4, k1=1.7, nst=2, name="QF")
d  = DriftSpec(L=1.0, name="D")
mk = MarkerSpec(name="MK")                                   # zero length
apin  = ApertureSpec(x_limit=1.0e-2, y_limit=1.0e-2, name="COLL_IN")
apout = ApertureSpec(x_limit=2.0e-2, y_limit=2.0e-2, name="COLL_OUT")

# depth 3: own state (x_offset) -> stays whole
L3 = BeamLine("L3", mk, q, apin, d; x_offset=2.0e-4)
# depth 2: own state (y_offset) -> stays whole, contains the whole-kept L3
L2 = BeamLine("L2", L3, d; y_offset=1.0e-4)
# depth 1: NO own state -> dissolves into the task
L1 = BeamLine("L1", L2, q, apout, d)

println("\n-- structural ------------------------------------------------------")
println("length(L3)          = ", length(L3), "   (expect 4)")
println("length(L2)          = ", length(L2), "   (expect 2)")
println("length(L1)          = ", length(L1), "   (expect 4)")
println("own_state L3/L2/L1  = ", O._line_has_own_state(L3), " ",
        O._line_has_own_state(L2), " ", O._line_has_own_state(L1))

println("\n-- arc length ------------------------------------------------------")
println("total_length(L3)    = ", O.total_length(L3), "   (physical 1.4)")
println("total_length(L2)    = ", O.total_length(L2), "   (physical 2.4)")
println("total_length(L1)    = ", O.total_length(L1), "   (physical 3.8)")
println("s_positions(L3)     = ", s_positions(L3), "   (physical [0.0,0.0,0.4,0.4])")
println("s_positions(L2)     = ", s_positions(L2), "   (physical [0.0,1.4])")
println("s_positions(L1)     = ", s_positions(L1), "   (physical [0.0,2.4,2.8,2.8])")

println("\n-- task walkers ----------------------------------------------------")
et = O._element_tuple(L1)
println("_element_tuple(L1)  n = ", length(et))
println("  paths             = ", [entry_path(e) for e in et])
rt = O._runtime_line_entries(et)
println("_runtime_line_entries n = ", length(rt))
println("  runtime types     = ", [nameof(typeof(e.element)) for e in rt])
aspecs = O._aperture_specs(et)
println("_aperture_specs     n = ", length(aspecs),
        " names = ", [getparam(s, :name, "") for s in aspecs])
asp = O._aperture_s_positions(et)
println("_aperture_s_positions = ", asp)

println("\n-- observer / declaration collection -------------------------------")
println("_collect_contracts  n = ", length(O._collect_contracts(L1)))
println("_collect_analyses   n = ", length(O._collect_analyses(L1)))
hid = Symbol[]
O._collect_hidden_apertures!(hid, et, false)
println("_collect_hidden_apertures = ", hid)

println("\n-- misaligned-parent survey length ---------------------------------")
# compile_runtime builds geom with :L => total_length; check the survey sees 2.4
rtL2 = compile_runtime(L2)
println("compile_runtime(L2) :: ", nameof(typeof(rtL2)))
println("  geom L used       = ", O.total_length(L2))

println("\n-- reverse / repeat round trip -------------------------------------")
r = reverse(L2)
println("reverse(L2) own_state = ", O._line_has_own_state(r),
        "  y_offset = ", getparam(r, :y_offset, missing),
        "  total_length = ", O.total_length(r))
rr = reverse(r)
println("reverse(reverse(L2)) paths = ", [entry_path(e) for e in line_entries(rr)])
println("entries type after reverse  = ", typeof(getparam(r, :entries, nothing)))
rp = repeat(L3, 2)
println("repeat(L3,2) n = ", length(rp), " total_length = ", O.total_length(rp),
        " (physical 2.8)  paths = ", [entry_path(e) for e in line_entries(rp)])

println("\n-- task-level aperture binding -------------------------------------")
task = TrackingTask(L1)
beam = Beam(Phase6DRep(zeros(4), zeros(4), zeros(4), zeros(4), zeros(4), zeros(4)))
execute!(task, beam; turns=1)
rec = loss_record(task)
println("loss_record counts len = ", length(loss_counts(rec)),
        "  names = ", aperture_names(rec))

println("\n-- BARE own-state line as a task element ---------------------------")
task2 = TrackingTask((L2, d))
println("_element_tuple((L2,d)) n = ", length(task2.elements))
println("_aperture_s_positions   = ", O._aperture_s_positions(task2.elements))
println("done")
