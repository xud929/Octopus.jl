include("/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/prelude.jl")
reset_knobs!()
@knob t_m.a = 2.0
@knob t_m.b = 3.0
@knob t_m.c = 5.0
println("op   |  input string                    | printed                    | ==")
for s in ("(t_m.a * t_m.b) * t_m.c", "t_m.a * (t_m.b * t_m.c)",
          "(t_m.a + t_m.b) + t_m.c", "t_m.a + (t_m.b + t_m.c)",
          "min(min(t_m.a, t_m.b), t_m.c)", "max(t_m.a, max(t_m.b, t_m.c))",
          "(t_m.a - t_m.b) - t_m.c", "(t_m.a / t_m.b) / t_m.c",
          "(t_m.a ^ t_m.b) ^ t_m.c")
    e = knob_expression(s)
    p = string(e)
    ok = knob_expression(p) == e
    println(rpad(s, 34), " | ", rpad(p, 30), " | ", ok)
end
# value consequence: floats are not associative
println()
x = 1e16; y = -1e16; z = 1.0
@knob t_m.x = 1.0e16
@knob t_m.y = -1.0e16
@knob t_m.z = 1.0
e = knob_expression("(t_m.x + t_m.y) + t_m.z")
e2 = knob_expression(string(e))
println("e  = (x+y)+z  printed as `", string(e), "`")
println("knob_value(e)  = ", knob_value(e))
println("knob_value(reparse(string(e))) = ", knob_value(e2))
println("trees equal = ", e2 == e, "   values equal = ", knob_value(e) == knob_value(e2))
reset_knobs!()
