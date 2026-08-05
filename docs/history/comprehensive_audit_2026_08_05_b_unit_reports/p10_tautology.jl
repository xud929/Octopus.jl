using Octopus
using Octopus: ELEMENT_META_BY_KIND, _element_meta_or_nothing

println("== are the friendly-vs-raw validator checks tautological? ==")
same = 0
diff = String[]
for (kind, meta) in sort(collect(ELEMENT_META_BY_KIND); by = p -> string(p[1]))
    f = meta.friendly_constructor
    f === nothing && continue
    fm = _element_meta_or_nothing(f)
    if fm === meta
        global same += 1
    else
        push!(diff, string(kind))
    end
end
println("  kinds whose friendly_constructor resolves to the SAME ElementMeta object: ",
        same, " / ", count(m -> m.friendly_constructor !== nothing,
                           values(ELEMENT_META_BY_KIND)))
println("  kinds where it resolves to a DIFFERENT meta: ", diff)
println("  => the three friendly-vs-raw checks compare an object with itself for all ",
        same, " kinds")

println()
println("== which kinds skip the declared-runtime MATCH check entirely? ==")
for (kind, meta) in sort(collect(ELEMENT_META_BY_KIND); by = p -> string(p[1]))
    skip_map = isempty(meta.runtime_types)
    skip_single = !(meta.runtime_type isa Type)
    if skip_map && skip_single
        println("  ", kind, ": runtime_types empty AND runtime_type=", meta.runtime_type,
                " -> only the COMPILE is checked, not what it compiles to")
    elseif skip_map
        println("  ", kind, ": runtime_types empty; falls back to runtime_type=",
                meta.runtime_type)
    end
end

println()
println("== wrapper types _compiled_matches_runtime knows about ==")
println("  hard-coded: MisalignedElement, RefTilted")
println("  CompositeLine is a compile product too; unwrapped? ",
        hasproperty(compile_runtime(BeamLine("C", DriftSpec(L=0.5))), :inner))
