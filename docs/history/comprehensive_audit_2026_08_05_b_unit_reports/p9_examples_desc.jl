using Octopus

println("== summarize_registry().examples ==")
s = summarize_registry()
println("  ", s.examples)
reg = build_registry()
for T in reg.examples
    println("  ", nameof(T), "  fieldnames=", fieldnames(T),
            "  description=", repr(description(T)))
end

println()
println("== registry types with an EMPTY description() ==")
for fld in (:tracking_methods, :solvers, :policies, :contracts, :analyses, :examples, :tasks)
    bare = String[]
    for T in getfield(reg, fld)
        d = try
            description(T)
        catch
            "<throws>"
        end
        (d isa AbstractString && isempty(d)) && push!(bare, string(nameof(T)))
    end
    println("  ", rpad(string(fld), 18), length(getfield(reg, fld)), " types; ",
            length(bare), " with no description: ", bare)
end

println()
println("== docstring presence for the three Example types ==")
for n in (:ReferenceExample, :BenchmarkExample, :ResearchStudyExample)
    d = string(Base.Docs.doc(Base.Docs.Binding(Octopus, n)))
    println("  ", rpad(string(n), 22), occursin("No documentation found", d) ? "NO DOC" : "documented")
end
