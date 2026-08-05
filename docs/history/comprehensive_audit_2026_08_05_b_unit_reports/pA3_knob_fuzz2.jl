include("/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/prelude.jl")
using Random
# A3: the DOCUMENTED contract, fuzzed: for any expression the parser can
# produce, knob_expression(string(e)) == e  AND  knob_value agrees.
# Sources of trees: (i) random parsed strings, (ii) their symbolic derivatives.
reset_knobs!()
@knob t_fz.a = 2.0
@knob t_fz.b = 3.0
ops = sort(collect(keys(Octopus._KNOB_OPERATORS)); by=string)
rng = MersenneTwister(20260805)
atoms = ["t_fz.a", "t_fz.b", "2.0", "-1.5", "0.5", "3.0"]
function gen(depth)
    (depth == 0 || rand(rng) < 0.3) && return rand(rng, atoms)
    op = rand(rng, ops)
    (_, ar) = Octopus._KNOB_OPERATORS[op]
    n = rand(rng, first(ar):min(last(ar), 3))
    return string(op) * "(" * join([gen(depth - 1) for _ in 1:n], ", ") * ")"
end
nrt = 0; nval = 0; shown = 0; ntrees = 0
for trial in 1:30000
    s = gen(3)
    e = try; knob_expression(s); catch; continue; end
    trees = Any[e]
    d = try; knob_derivative(e, Symbol("t_fz.a"); through_registry=false); catch; nothing; end
    d === nothing || push!(trees, d)
    for t in trees
        global ntrees += 1
        p = string(t)
        t2 = try
            knob_expression(p)
        catch err
            global nrt += 1
            global shown; if shown < 10; println("PARSE FAIL from `", s, "`: printed `", p, "` : ", sprint(showerror, err)); shown += 1; end
            continue
        end
        if t2 != t
            global nrt += 1
            global shown; if shown < 10; println("TREE MISMATCH from `", s, "`: printed `", p, "` reparsed `", string(t2), "`"); shown += 1; end
        end
        v1 = try; knob_value(t); catch; nothing; end
        v2 = try; knob_value(t2); catch; nothing; end
        if !(v1 === nothing || v2 === nothing) && !isequal(v1, v2)
            global nval += 1
            global shown; if shown < 10; println("VALUE CHANGE from `", s, "`: printed `", p, "`  ", v1, " -> ", v2); shown += 1; end
        end
    end
end
println("trees round-tripped = ", ntrees, "   tree mismatches = ", nrt, "   value changes = ", nval)
reset_knobs!()
