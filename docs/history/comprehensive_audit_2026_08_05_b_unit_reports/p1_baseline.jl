using Octopus

const SCRATCH = "/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit"
const REPO = "/cfs/ad/dxu/Library/Julia/Octopus"

println("== validate_element_metadata ==")
r = validate_element_metadata()
println("passed=", r.passed, " nerrors=", length(r.errors))
for e in r.errors; println("  ERR: ", e); end

println("== validate_configuration_metadata ==")
try
    println("returned ", validate_configuration_metadata())
catch err
    println("THREW: ", sprint(showerror, err))
end

println("== registry snapshot ==")
gen = registry_snapshot_markdown()
committed = read(joinpath(REPO, "docs", "registry_snapshot.md"), String)
println("byte-identical = ", gen == committed)
println("len gen=", length(gen), " len committed=", length(committed))
write(joinpath(SCRATCH, "registry_snapshot_regen.md"), gen)

println("== exports ==")
ns = filter(n -> n !== :Octopus, names(Octopus))
println("n exports = ", length(ns))
undoc = [n for n in ns if occursin("No documentation found",
            string(Base.Docs.doc(Base.Docs.Binding(Octopus, n))))]
println("undocumented = ", length(undoc), " -> ", undoc)
unresolved = [n for n in ns if !isdefined(Octopus, n)]
println("unresolved exports = ", unresolved)

println("== registry counts ==")
s = summarize_registry()
for k in keys(s)
    println("  ", k, " = ", length(getfield(s, k)))
end

println("== registered kinds ==")
println(length(Octopus.ELEMENT_META_BY_KIND), " kinds")
