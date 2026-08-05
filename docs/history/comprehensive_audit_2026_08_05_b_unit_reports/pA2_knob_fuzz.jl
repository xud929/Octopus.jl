include("/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/prelude.jl")
using Random
using Octopus: AbstractKnobExpression
# A2: randomized round-trip property test over the FULL operator whitelist,
# building nested trees directly as KnobCall objects (so the printer, not the
# parser, is the thing under test).
reset_knobs!()
@knob t_fz.a = 2.0
@knob t_fz.b = 3.0
ops = sort(collect(keys(Octopus._KNOB_OPERATORS)); by=string)
leaves = Any[Octopus.KnobRef(Symbol("t_fz.a")), Octopus.KnobRef(Symbol("t_fz.b")),
             Octopus.KnobConst(2.0), Octopus.KnobConst(-1.5), Octopus.KnobConst(0.0),
             Octopus.KnobConst(Inf), Octopus.KnobConst(-Inf), Octopus.KnobConst(NaN)]
rng = MersenneTwister(20260805)
function build(depth)
    (depth == 0 || rand(rng) < 0.25) && return rand(rng, leaves)
    op = rand(rng, ops)
    (_, ar) = Octopus._KNOB_OPERATORS[op]
    n = rand(rng, first(ar):min(last(ar), 3))
    return Octopus.KnobCall(op, AbstractKnobExpression[build(depth - 1) for _ in 1:n])
end
global bad = 0; global shown = 0
for trial in 1:20000
    e = build(3)
    s = string(e)
    e2 = try
        knob_expression(s)
    catch err
        global bad += 1
        global shown; if shown < 8; println("PARSE FAIL  `", s, "` : ", sprint(showerror, err)); shown += 1; end
        continue
    end
    if e2 != e; global bad, shown
        global bad += 1
        global shown; if shown < 8; println("MISMATCH    `", s, "` -> `", string(e2), "`"); shown += 1; end
    end
end
println("fuzz trials = 20000, round-trip failures = ", bad)
reset_knobs!()
