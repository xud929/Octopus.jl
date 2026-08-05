using Octopus
reset_knobs!()
@knob u = 2.0
@knob v = 3.0
@knob w = 2.0
e = @knob_expr(u * v)
tryit(f) = try f(); "NO ERROR" catch err; err isa ArgumentError ? "directed ArgumentError" : "$(typeof(err))" end
println("U14-7 eager arithmetic:")
for (l, f) in (("2 * e", () -> 2 * e), ("e * 2", () -> e * 2), ("e + e", () -> e + e),
               ("e ^ 2", () -> e ^ 2), ("Int(e)", () -> Int(e)), ("Float64(e)", () -> Float64(e)),
               ("float(e)", () -> float(e)), ("2 - e", () -> 2 - e), ("e / 2", () -> e / 2))
    println("  ", rpad(l, 12), tryit(f))
end
println("\nU14-2 ^ associativity: ", string(@knob_expr((u^v)^w)),
        "   round trip == ", knob_expression(string(@knob_expr((u^v)^w))) == @knob_expr((u^v)^w),
        "   value ", knob_value(@knob_expr((u^v)^w)))
println("U14-2 -Inf/NaN round trip: ",
        knob_expression(string(Octopus.KnobConst(-Inf))) == Octopus.KnobConst(-Inf), " / ",
        knob_expression(string(Octopus.KnobConst(NaN))) == Octopus.KnobConst(NaN))
println("U14-2 derivative NaN fold: ",
        (d = knob_derivative(@knob_expr(u / 0.0), :u); string(d)), " -> round trip ",
        tryit(() -> knob_expression(string(d))) == "NO ERROR")
println("\nU14-3 constant names rejected:")
for n in (:pi, :π, :ℯ, :NaN, :Inf)
    println("  ", rpad(string(n), 4), tryit(() -> Octopus._knob_define!(n, Meta.parse("3.0"))),
            "   registered=", n in list_knobs())
end
println("\nU14-1 retype-on-dependent rejected atomically:")
@knob dep = u * 1.0
v0 = knob_value(:dep); e0 = knob_epoch()
println("  throws: ", tryit(() -> Octopus._knob_define!(:dep, Float32, nothing, nothing)),
        "   value unchanged=", knob_value(:dep) === v0, "   epoch unchanged=", knob_epoch() == e0)
println("\nU14-4 root collision leaves nothing registered:")
e4 = knob_epoch()
println("  throws: ", tryit(() -> Core.eval(@__MODULE__, :(@knob sin.x = 1.0))),
        "   registered=", Symbol("sin.x") in list_knobs(), "   epoch unchanged=", knob_epoch() == e4)
