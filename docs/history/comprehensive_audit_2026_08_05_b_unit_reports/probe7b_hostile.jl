using Octopus
reset_knobs!()
@knob u = 1.0
@knob v = 1.0
@knob w = 1.0
kc(op, args...) = Octopus.KnobCall(op, Octopus.AbstractKnobExpression[args...])
U, V, W = Octopus.KnobRef(:u), Octopus.KnobRef(:v), Octopus.KnobRef(:w)
cases = [
  ("u + (v + w)", kc(:+, U, kc(:+, V, W)), (1.0, 1.0e-16, 1.0e-16)),
  ("u + (v - w)", kc(:+, U, kc(:-, V, W)), (1.0, 1.0e-16, 1.0e-16)),
  ("u * (v * w)", kc(:*, U, kc(:*, V, W)), (1.0e300, 1.0e300, 1.0e-300)),
  ("u * (v / w)", kc(:*, U, kc(:/, V, W)), (1.0e300, 1.0e300, 1.0e300)),
  ("(u + v) + w", kc(:+, kc(:+, U, V), W), (1.0, 1.0e-16, 1.0e-16)),
  ("(u * v) * w", kc(:*, kc(:*, U, V), W), (1.0e300, 1.0e-300, 1.0e300)),
]
for (label, e, (a, b, c)) in cases
    set_knob!(:u, a); set_knob!(:v, b); set_knob!(:w, c)
    s = string(e); e2 = knob_expression(s)
    println(rpad(label, 14), " prints \"", s, "\"  tree-equal=", e2 == e,
            "   value ", knob_value(e), "  vs reparsed ", knob_value(e2),
            isequal(knob_value(e), knob_value(e2)) ? "" : "   <== DIFFERENT NUMBER")
end
