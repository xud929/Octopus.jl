using Octopus
const O = Octopus

c0 = (1.0e-3, 2.0e-4, -5.0e-4, 1.0e-4, 0.0, 1.0e-3)

println("== e1. girder-vs-element misalignment, scanned in bend angle ==")
for ang in (0.0, 1.0e-3, 1.0e-2, 0.05, 0.198, 0.4)
    b = SBendSpec(L=1.1, angle=ang, k1=0.0, nst=8)
    a = compile_runtime(BeamLine("G", b; x_offset=1.0e-3))
    e = compile_runtime(SBendSpec(L=1.1, angle=ang, k1=0.0, nst=8, x_offset=1.0e-3))
    d = maximum(abs, collect(a(c0...)) .- collect(e(c0...)))
    println("  angle = ", rpad(ang, 8), "  max|girder - element| = ", d)
end

println()
println("== e2. same, but a STRAIGHT element (h = 0 for both paths) ==")
q = QuadrupoleSpec(L=1.1, k1=0.7, nst=8)
a = compile_runtime(BeamLine("GQ", q; x_offset=1.0e-3, x_pitch=2.0e-3, tilt=1.5e-3))
e = compile_runtime(QuadrupoleSpec(L=1.1, k1=0.7, nst=8, x_offset=1.0e-3,
                                   x_pitch=2.0e-3, tilt=1.5e-3))
println("  max|girder - element| = ", maximum(abs, collect(a(c0...)) .- collect(e(c0...))))

println()
println("== e3. a user-set :L on a line -- which walker sees which number ==")
qq = QuadrupoleSpec(L=0.4, k1=1.0, nst=1); dd = DriftSpec(L=1.0)
cryoL = BeamLine("CRYOL", qq, dd; x_offset=1.0e-4, L=99.0)
ap = ApertureSpec(x_limit=1.0e-2, y_limit=1.0e-2, name="AFTER")
println("  total_length(cryoL)                 = ", O.total_length(cryoL))
println("  _placement_length(cryoL)            = ", O._placement_length(cryoL))
parent = BeamLine("PARENT", cryoL, ap)
println("  s_positions(parent)                 = ", s_positions(parent))
tsk = TrackingTask(parent)
println("  _aperture_s_positions(task.elements)= ", O._aperture_s_positions(tsk.elements))
println("  survey L used by compile_runtime    = ", O.total_length(cryoL),
        "   (geom merge overwrites the stored :L)")
println("  --> arc-position walkers say 99.0, the survey says 1.4")

println()
println("== e4. element `name` is an undeclared parameter on every kind but 2 ==")
for f in (:QuadrupoleSpec, :DriftSpec, :MarkerSpec, :ApertureSpec, :SBendSpec)
    sch = try
        keys(Octopus.parameter_schema(getfield(Octopus, f)))
    catch
        ()
    end
    println("  ", rpad(String(f), 16), " declares :name = ", :name in sch)
end
println("  (beam_line.jl `_entry_label` uses getparam(child, :name) for the path)")

println()
println("== e5. wrapper table: does each forward the tracking context? ==")
ms = LumpedRadSpec{Float64}(damping_turns=(1e6,1e6,1e6), sigma=(1e-3,1e-3,1e-3),
                            is_damping=false, rng_id=901)
ctx = O.with_turn(O.TrackingContext(), 2)
wraps = Any[
  "LumpedRad (leaf)"   => compile_runtime(ms),
  "MisalignedElement"  => O._misalignment_wrap(
        QuadrupoleSpec(L=0.0, k1=0.0, nst=1, x_offset=1e-9), compile_runtime(ms)),
  "RefTilted"          => O._ref_tilt_wrap(
        QuadrupoleSpec(L=0.0, k1=0.0, nst=1, ref_tilt=0.2), compile_runtime(ms)),
  "CompositeLine"      => O.CompositeLine((compile_runtime(ms),)),
]
for (lbl, el) in wraps
    r1 = el(ctx, 3, 0.0,0.0,0.0,0.0,0.0,0.0)
    r2 = el(ctx, 3, 0.0,0.0,0.0,0.0,0.0,0.0)
    println("  ", rpad(lbl, 20), rpad(String(nameof(typeof(el))), 20),
            " ctx-repeatable = ", r1 == r2)
end
println("done")
