# U13 probe 8 — derive the derivative-coverage list from the authoritative
# source (`_KNOB_OPERATORS`) instead of hand-copying it, and check every
# differentiable operator against central differences. Operators that must
# REFUSE are asserted to refuse.
using Octopus, Printf

reset_knobs!()
@knob a = 0.6
@knob b = 1.4

# one probe expression per operator, keyed by the whitelist name
probe = Dict{Symbol,String}(
    :+     => "a + b + 0.5",
    :-     => "a - b",
    :*     => "a * b * 2.0",
    :/     => "a / b",
    :^     => "a ^ b",              # wrt the BASE, variable exponent branch
    :sqrt  => "sqrt(a + 1.0)",
    :cbrt  => "cbrt(a + 1.0)",
    :abs   => "abs(a)",
    :inv   => "inv(a + 1.0)",
    :exp   => "exp(a)",
    :log   => "log(a + 1.0)",
    :log10 => "log10(a + 1.0)",
    :sin   => "sin(a)",
    :cos   => "cos(a)",
    :tan   => "tan(a)",
    :asin  => "asin(a / 2.0)",
    :acos  => "acos(a / 2.0)",
    :atan  => "atan(a)",
    :sinh  => "sinh(a)",
    :cosh  => "cosh(a)",
    :tanh  => "tanh(a)",
)
must_refuse = Set([:sign, :min, :max])

ops = sort!(collect(keys(Octopus._KNOB_OPERATORS)); by = string)
uncovered = Symbol[]
worst = 0.0
println("operator coverage derived from _KNOB_OPERATORS (", length(ops), " entries)")
for op in ops
    if op in must_refuse
        s = op === :sign ? "sign(a)" : "$(op)(a, b)"
        ok = try
            knob_derivative(knob_expression(s), :a); false
        catch err
            err isa ArgumentError
        end
        @printf("  %-6s REFUSE expected: %s\n", op, ok ? "refused (ok)" : "DID NOT REFUSE")
        continue
    end
    if !haskey(probe, op)
        push!(uncovered, op)
        println("  ", op, "  NO PROBE EXPRESSION -- coverage gap")
        continue
    end
    s = probe[op]
    d = knob_derivative(knob_expression(s), :a)
    ad = knob_value(d)
    h = 1.0e-6
    v0 = knob_value(:a)
    set_knob!(:a, v0 + h); fp = knob_value(knob_expression(s))
    set_knob!(:a, v0 - h); fm = knob_value(knob_expression(s))
    set_knob!(:a, v0)
    cd = (fp - fm) / (2h)
    rel = abs(ad - cd) / max(abs(cd), 1e-30)
    global worst = max(worst, rel)
    @printf("  %-6s d/da  sym=%+.10e  cd=%+.10e  rel=%.2e\n", op, ad, cd, rel)
end
println("uncovered operators: ", isempty(uncovered) ? "none" : string(uncovered))
println("worst relative error: ", worst)

println("\n-- multi-branch forms that must refuse --")
for s in ("log(a, b)", "atan(a, b)")
    ok = try
        knob_derivative(knob_expression(s), :a); "DID NOT REFUSE"
    catch err
        err isa ArgumentError ? "refused (ok)" : "wrong error"
    end
    println("  ", rpad(s, 12), ok)
end
println("\n-- abs at 0, documented as returning sign(0)=0 --")
set_knob!(:a, 0.0)
println("  d(abs(a))/da at a=0 -> ", knob_value(knob_derivative(knob_expression("abs(a)"), :a)))
set_knob!(:a, 0.6)
println("\n-- derivative wrt an unreferenced knob --")
println("  d(sin(b))/da = ", knob_value(knob_derivative(knob_expression("sin(b)"), :a)))
