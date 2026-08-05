include("/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/prelude.jl")
reset_knobs!()
@knob t_m.a = 2.0
@knob t_m.b = 3.0

println("=== 1. parser flattens n-ary chains ===")
e = knob_expression("(t_m.a * t_m.b) * 2.0")
println("parsed `(t_m.a * t_m.b) * 2.0` -> ", typeof(e), " nargs=", length(e.args))
println("  string = ", string(e), "   round trip == : ", knob_expression(string(e)) == e)

println("\n=== 2. a DERIVATIVE tree is built binary, so it does NOT round trip ===")
d = knob_derivative(knob_expression("tanh(exp(t_m.a) * tanh(-1.5))"), Symbol("t_m.a");
                    through_registry=false)
p = string(d)
d2 = knob_expression(p)
println("derivative printed   : ", p)
println("reparsed printed     : ", string(d2))
println("strings identical    : ", p == string(d2))
println("trees equal (contract): ", d2 == d)
v1 = knob_value(d); v2 = knob_value(d2)
println("knob_value(d)  = ", repr(v1))
println("knob_value(d2) = ", repr(v2))
println("identical value      : ", isequal(v1, v2), "   ulp gap = ", v1 == v2 ? 0 : abs(v1-v2)/eps(abs(v1)))

println("\n=== 3. shape of the two trees ===")
shape(x, ind="") = begin
    if x isa Octopus.KnobCall
        println(ind, x.op, "  (", length(x.args), " args)")
        for a in x.args; shape(a, ind * "  "); end
    else
        println(ind, string(x))
    end
end
println("-- derivative tree --"); shape(d)
println("-- reparsed tree --");   shape(d2)
reset_knobs!()
