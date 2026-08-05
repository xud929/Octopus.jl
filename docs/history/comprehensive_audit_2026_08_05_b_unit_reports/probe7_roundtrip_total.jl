# U13 probe 7 — TOTALIZE the documented round-trip invariant
#   knob_expression(string(e)) == e            (docs/knob_control.md:29-30, 166)
# over every binary-operator nesting, in both operand positions, plus the
# unary-minus and named-constant cases. The 2026-08-05 U14-2 fix covered `^`
# (right-associative base) and the `-`/`/` RIGHT operand; this enumerates the
# whole grid.
using Octopus

reset_knobs!()
@knob u = 3.0
@knob v = 7.0
@knob w = 2.0

const OPS = (:+, :-, :*, :/, :^)
leaf(i) = i == 1 ? Octopus.KnobRef(:u) : i == 2 ? Octopus.KnobRef(:v) : Octopus.KnobRef(:w)
kc(op, args...) = Octopus.KnobCall(op, Octopus.AbstractKnobExpression[args...])

fails = Tuple[]
total = 0
for outer in OPS, inner in OPS, pos in (1, 2)
    e = pos == 1 ? kc(outer, kc(inner, leaf(1), leaf(2)), leaf(3)) :
                   kc(outer, leaf(1), kc(inner, leaf(2), leaf(3)))
    s = string(e)
    e2 = try
        knob_expression(s)
    catch err
        push!(fails, (outer, inner, pos, s, "PARSE ERROR: " * sprint(showerror, err), NaN, NaN))
        continue
    end
    global total += 1
    structural = e2 == e
    v1 = knob_value(e); v2 = knob_value(e2)
    numeric = isequal(v1, v2)
    if !structural || !numeric
        push!(fails, (outer, inner, pos, s, structural ? "value" : "structure", v1, v2))
    end
end
println("binary x binary x position grid: ", total, " shapes")
if isempty(fails)
    println("  all round-trip exactly")
else
    println("  ", length(fails), " FAIL:")
    for f in fails
        println("    outer=", f[1], " inner=", f[2], " pos=", f[3],
                "  printed \"", f[4], "\"  broke=", f[5],
                "  values ", f[6], " vs ", f[7])
    end
end

println("\n-- the same shapes, checked for a NUMERIC difference with hostile values --")
set_knob!(:u, 1.0); set_knob!(:v, 1.0e-16); set_knob!(:w, 1.0e-16)
for (outer, inner, pos) in ((:+, :-, 2), (:*, :/, 2), (:-, :+, 2), (:/, :*, 2))
    e = pos == 1 ? kc(outer, kc(inner, leaf(1), leaf(2)), leaf(3)) :
                   kc(outer, leaf(1), kc(inner, leaf(2), leaf(3)))
    s = string(e); e2 = knob_expression(s)
    println("  ", outer, "/", inner, " pos", pos, ": \"", s, "\"  ",
            knob_value(e), "  vs reparsed  ", knob_value(e2),
            isequal(knob_value(e), knob_value(e2)) ? "" : "   <== DIFFERENT NUMBER")
end
set_knob!(:u, 3.0); set_knob!(:v, 7.0); set_knob!(:w, 2.0)

println("\n-- unary minus and constants --")
cases = Any[
    ("unary minus of a positive literal", kc(:-, Octopus.KnobConst(5.0))),
    ("unary minus of a negative literal", kc(:-, Octopus.KnobConst(-5.0))),
    ("unary minus of a ref",              kc(:-, leaf(1))),
    ("unary plus of a literal",           kc(:+, Octopus.KnobConst(5.0))),
    ("NaN const",                         Octopus.KnobConst(NaN)),
    ("Inf const",                         Octopus.KnobConst(Inf)),
    ("-Inf const",                        Octopus.KnobConst(-Inf)),
    ("-0.0 const",                        Octopus.KnobConst(-0.0)),
    ("nested unary in product",           kc(:*, kc(:-, leaf(1)), leaf(2))),
    ("3-ary +",                           kc(:+, leaf(1), leaf(2), leaf(3))),
    ("3-ary *",                           kc(:*, leaf(1), leaf(2), leaf(3))),
    ("min call",                          kc(:min, leaf(1), leaf(2))),
    ("2-arg log",                         kc(:log, leaf(1), leaf(2))),
    ("2-arg atan",                        kc(:atan, leaf(1), leaf(2))),
]
for (name, e) in cases
    s = string(e)
    r = try
        e2 = knob_expression(s)
        (e2 == e ? "ok" : "STRUCTURE DIFFERS -> " * string(e2)) *
        (isequal(knob_value(e), knob_value(e2)) ? "" :
            "  VALUE " * string(knob_value(e)) * " -> " * string(knob_value(e2)))
    catch err
        "THREW: " * first(sprint(showerror, err), 70)
    end
    println("  ", rpad(name, 34), " \"", s, "\"   ", r)
end
