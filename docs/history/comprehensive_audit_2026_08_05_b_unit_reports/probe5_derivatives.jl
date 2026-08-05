# U13 probe 5 — hypothesis (c): the symbolic/AD path reproduces central
# differences.  Shapes chosen independently of the prior pass, plus two
# tracking-level checks: one knob feeding MULTIPLE elements, and one knob
# inside a BeamLine.
using Octopus
using Printf

reset_knobs!()
@knob a = 0.7
@knob b = 1.3

# central difference of a knob expression wrt an independent knob
function central(exprstr::String, path::Symbol, h::Float64)
    v0 = knob_value(path)
    set_knob!(path, v0 + h); fp = knob_value(knob_expression(exprstr))
    set_knob!(path, v0 - h); fm = knob_value(knob_expression(exprstr))
    set_knob!(path, v0)
    return (fp - fm) / (2h)
end

shapes = [
    ("atan(a) * exp(-b)",                  :a),
    ("atan(a) * exp(-b)",                  :b),
    ("log(a^3 + b) / cosh(a * b)",         :a),
    ("sqrt(abs(a) + 1.0) * sinh(b / a)",   :b),
    ("(a + b)^2.5 - cbrt(a * b)",          :a),
    ("inv(1.0 + a^2)",                     :a),
    ("a^b",                                :b),
    ("tanh(a) * log10(b)",                 :b),
    ("a * a * a",                          :a),
    ("exp(sin(cos(a)))",                   :a),
    ("asin(a / 2.0) + acos(b / 4.0)",      :a),
    ("tan(a * b) + a / (b + 2.0)",         :a),
]
println("== expression-level: knob_derivative vs central differences ==")
maxrel = 0.0
for (s, p) in shapes
    d = knob_derivative(knob_expression(s), p)
    ad = knob_value(d)
    cd = central(s, p, 1.0e-6)
    rel = abs(ad - cd) / max(abs(cd), 1e-30)
    global maxrel = max(maxrel, rel)
    @printf("  %-34s d/d%-2s  sym=%+.12e  cd=%+.12e  rel=%.2e\n", s, p, ad, cd, rel)
end

println("\n== registry chain (2 levels) ==")
@knob c = sin(a) * b
@knob d2 = c^2 + log(c)
dsym = knob_derivative(:d2, :a)
ad = knob_value(dsym)
h = 1.0e-6
v0 = knob_value(:a)
set_knob!(:a, v0 + h); fp = knob_value(:d2)
set_knob!(:a, v0 - h); fm = knob_value(:d2)
set_knob!(:a, v0)
@printf("  d(d2)/d(a) sym=%+.12e  cd=%+.12e  rel=%.2e\n", ad, (fp - fm)/(2h),
        abs(ad - (fp - fm)/(2h)) / abs((fp - fm)/(2h)))
println("  expression: ", dsym)
# partial (through_registry=false) must be exactly 0 -- `a` is not referenced
println("  through_registry=false -> ", knob_value(knob_derivative(:d2, :a; through_registry=false)))

println("\n== tracking level: ONE knob feeding TWO elements ==")
reset_knobs!()
@knob bus = 1.0
focus = ElementSpec{:crab_dispersion}(; zeta1 = @knob_expr(2.0 * bus),
    zeta2 = 0.0, zeta3 = 0.0, zeta4 = 0.0, tracking_method = Symplectic6DMap())
defocus = ElementSpec{:crab_dispersion}(; zeta1 = @knob_expr(-(0.5 * bus)),
    zeta2 = 0.0, zeta3 = 0.0, zeta4 = 0.0, tracking_method = Symplectic6DMap())
z0 = 1.0e-3
task = TrackingTask((focus, defocus); policy = CPUThreadsExecutionPolicy(threads = 1))
function trackx(k)
    set_knob!(:bus, k)
    r = Phase6DRep([1.0e-4], [0.0], [0.0], [0.0], [z0], [0.0])
    execute!(task, r; turns = 1)
    return r.x[1]
end
hk = 1.0e-4
cd = (trackx(1.0 + hk) - trackx(1.0 - hk)) / (2hk)
pred = (knob_value(knob_derivative(@knob_expr(2.0 * bus), :bus)) +
        knob_value(knob_derivative(@knob_expr(-(0.5 * bus)), :bus))) * z0
@printf("  d(x_out)/d(bus): tracked cd=%+.12e   knob_derivative prediction=%+.12e   rel=%.2e\n",
        cd, pred, abs(cd - pred) / abs(pred))
println("  (exact analytic value 1.5*z0 = ", 1.5 * z0, ")")
println("  both elements really recompiled: focus zeta1=",
        compile_runtime(focus).zeta1, ", defocus zeta1=", compile_runtime(defocus).zeta1)

println("\n== tracking level: a knob inside a BeamLine ==")
reset_knobs!()
@knob busl = 1.0
f2 = ElementSpec{:crab_dispersion}(; zeta1 = @knob_expr(2.0 * busl),
    zeta2 = 0.0, zeta3 = 0.0, zeta4 = 0.0, tracking_method = Symplectic6DMap())
d2e = ElementSpec{:crab_dispersion}(; zeta1 = @knob_expr(-(0.5 * busl)),
    zeta2 = 0.0, zeta3 = 0.0, zeta4 = 0.0, tracking_method = Symplectic6DMap())
line = BeamLine("CELL", [f2, d2e])
taskl = TrackingTask(line; policy = CPUThreadsExecutionPolicy(threads = 1))
println("  _has_knob_parameters(task.elements) = ",
        Octopus._has_knob_parameters(taskl.elements),
        "   (element types: ", map(typeof, taskl.elements), ")")
function trackxl(k)
    set_knob!(:busl, k)
    r = Phase6DRep([1.0e-4], [0.0], [0.0], [0.0], [z0], [0.0])
    execute!(taskl, r; turns = 1)
    return r.x[1]
end
cdl = (trackxl(1.0 + hk) - trackxl(1.0 - hk)) / (2hk)
@printf("  d(x_out)/d(busl): tracked cd=%+.12e  vs exact 1.5*z0=%+.12e  rel=%.2e\n",
        cdl, 1.5 * z0, abs(cdl - 1.5 * z0) / (1.5 * z0))

# kept-whole (own-state) line: the knob must still reach the task
line_ws = BeamLine("CRYO", [f2, d2e]; x_offset = 1.0e-6)
taskw = TrackingTask(line_ws; policy = CPUThreadsExecutionPolicy(threads = 1))
println("  own-state line: _has_knob_parameters = ",
        Octopus._has_knob_parameters(taskw.elements))
function trackxw(k)
    set_knob!(:busl, k)
    r = Phase6DRep([1.0e-4], [0.0], [0.0], [0.0], [z0], [0.0])
    execute!(taskw, r; turns = 1)
    return r.x[1]
end
cdw = (trackxw(1.0 + hk) - trackxw(1.0 - hk)) / (2hk)
@printf("  own-state line d(x)/d(busl) = %+.12e  vs exact %+.12e  rel=%.2e\n",
        cdw, 1.5 * z0, abs(cdw - 1.5 * z0) / (1.5 * z0))
println("\nmax expression-level relative error = ", maxrel)
