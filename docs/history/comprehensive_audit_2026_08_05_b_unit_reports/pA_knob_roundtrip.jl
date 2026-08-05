include("/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/prelude.jl")
# A: derive the round-trip case list from the AUTHORITATIVE operator whitelist
# instead of the hand-picked 6 strings at runtests.jl:7992-7999.
reset_knobs!()
@knob t_rt.a = 2.0
@knob t_rt.b = 3.0
@knob t_rt.c = 0.5

ops = sort(collect(keys(Octopus._KNOB_OPERATORS)); by=string)
println("operators in _KNOB_OPERATORS: ", length(ops))
covered_by_suite = Set([:*, :/, :-, :^, :+, :sin, :atan, :max])
println("covered by runtests.jl:7992-7999 loop: ", length(covered_by_suite), " -> ",
        sort(collect(covered_by_suite); by=string))
println("NOT covered: ", sort(collect(setdiff(Set(ops), covered_by_suite)); by=string))

fails = Tuple{Symbol,String,String}[]
for op in ops
    (f, ar) = Octopus._KNOB_OPERATORS[op]
    for n in unique([first(ar), min(last(ar), 3)])
        n < first(ar) && continue
        args = ["t_rt.a", "t_rt.b", "t_rt.c"][1:n]
        s = string(op) * "(" * join(args, ", ") * ")"
        e = try
            knob_expression(s)
        catch err
            push!(fails, (op, s, "PARSE: " * sprint(showerror, err))); continue
        end
        printed = string(e)
        e2 = try
            knob_expression(printed)
        catch err
            push!(fails, (op, s, "REPARSE of `$printed`: " * sprint(showerror, err))); continue
        end
        e2 == e || push!(fails, (op, s, "MISMATCH: printed `$printed` reparsed to `$(string(e2))`"))
    end
end
# nested forms, one level, for every operator (precedence / parenthesisation)
for op in ops
    (f, ar) = Octopus._KNOB_OPERATORS[op]
    n = first(ar)
    inner = "t_rt.a ^ t_rt.b"
    args = [inner; fill("t_rt.c", n - 1)]
    s = string(op) * "(" * join(args, ", ") * ")"
    e = try; knob_expression(s); catch err; push!(fails,(op,s,"PARSE: "*sprint(showerror,err))); continue; end
    printed = string(e)
    e2 = try; knob_expression(printed); catch err; push!(fails,(op,s,"REPARSE of `$printed`: "*sprint(showerror,err))); continue; end
    e2 == e || push!(fails, (op, s, "NESTED MISMATCH: printed `$printed` reparsed to `$(string(e2))`"))
end
println("\nround-trip failures: ", length(fails))
for f in fails; println("  ", f); end
reset_knobs!()
