using Octopus, HDF5
tmp = mktempdir()
mk(n=2) = Phase6DRep([1.0e-3*i for i in 1:n], zeros(n), zeros(n), zeros(n), zeros(n), zeros(n))
d = ElementSpec{:drift}(; L=0.5, tracking_method=Symplectic6DMap())
ap() = ApertureSpec(shape=:rectangle, x_limit=1.5e-3, y_limit=1.0, name="COLL")

println("=== loss_log CONTENT with loss_report on/off ===")
for lr in (true, false)
    r = mk(3); r.x[1] = NaN
    f = joinpath(tmp, "c_$(lr).h5")
    t = TrackingTask((d, ap()); policy=CPUThreadsExecutionPolicy(threads=1),
                     loss_report=lr, loss_log=f)
    execute!(t, r; turns=1)
    h5open(f, "r") do fid
        println("  loss_report=", lr, " keys: ", keys(fid),
                haskey(fid, "summary") ? "  summary attrs: " * string(keys(attrs(fid["summary"]))) : "  (no summary group)")
    end
end

println("\n=== spurious recompile: an UNRELATED knob declaration invalidates every knob task ===")
reset_knobs!()
@knob k1 = 0.25
spec = ElementSpec{:crab_dispersion}(; zeta1=@knob_expr(k1), zeta2=0.0, zeta3=0.0,
                                     zeta4=0.0, tracking_method=Symplectic6DMap())
task = TrackingTask(ntuple(_ -> spec, 50); policy=CPUThreadsExecutionPolicy(threads=1))
execute!(task, mk(); turns=1)
id1 = objectid(task.runtime_entries_cache[][1])
execute!(task, mk(); turns=1)
id2 = objectid(task.runtime_entries_cache[][1])
println("  no mutation:            entries object reused = ", id1 == id2)
@knob unrelated_new_knob = 1.0        # cannot be referenced by any existing expr
execute!(task, mk(); turns=1)
id3 = objectid(task.runtime_entries_cache[][1])
println("  after @knob unrelated:  entries object reused = ", id1 == id3,
        "   (epoch consumers cannot tell a relevant bump from an irrelevant one)")
t0 = time(); for _ in 1:20; execute!(task, mk(); turns=1); end; tnomut = time()-t0
t0 = time(); for i in 1:20
    Octopus._knob_define!(Symbol("spam_$i"), nothing, 1.0, nothing)
    execute!(task, mk(); turns=1)
end; tmut = time()-t0
println("  20 execute! without mutation: ", round(tnomut*1000, digits=1), " ms")
println("  20 execute! each preceded by an unrelated @knob: ", round(tmut*1000, digits=1), " ms")
