include("/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/prelude.jl")
reset_knobs!()
@knob t_m.x = 1.0e16
@knob t_m.y = -1.0e16
@knob t_m.z = 1.0
e  = knob_expression("t_m.x + (t_m.y + t_m.z)")
p  = string(e)
e2 = knob_expression(p)
println("source string          : t_m.x + (t_m.y + t_m.z)")
println("string(e)              : ", p)
println("knob_value(e)          : ", knob_value(e))
println("knob_value(reparsed)   : ", knob_value(e2))
println("documented contract knob_expression(string(e)) == e : ", e2 == e)
println("value preserved        : ", knob_value(e) == knob_value(e2))
reset_knobs!()
