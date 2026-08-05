# U26 probe 1: registry snapshot regeneration + public_api symbol/docstring resolution
const REPO = "/cfs/ad/dxu/Library/Julia/Octopus"
const SCRATCH = "/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit"

include(joinpath(REPO, "src", "Octopus.jl"))
using .Octopus

# ---- (d) regenerate registry snapshot to scratch ----
outpath = joinpath(SCRATCH, "registry_snapshot_regen.md")
try
    Octopus.write_registry_snapshot(outpath)
    println("REGEN_OK ", outpath)
catch e
    println("REGEN_ERR ", sprint(showerror, e))
    # try keyword / no-arg form
    try
        m = collect(methods(Octopus.write_registry_snapshot))
        for mm in m; println("  method: ", mm); end
    catch
    end
end

# ---- (e) public_api symbols ----
txt = read(joinpath(REPO, "docs", "public_api.md"), String)
syms = String[]
for m in eachmatch(r"^\?([A-Za-z@_][A-Za-z0-9_!@]*)"m, txt)
    push!(syms, m.captures[1])
end
# also bare call entries in code fences like foo(...)
for m in eachmatch(r"^([a-z_][A-Za-z0-9_!]*)\(", txt)
    push!(syms, m.captures[1])
end
syms = unique(syms)
println("NSYMS ", length(syms))

exported = Set(string.(names(Octopus)))
println("--- SYMBOL TABLE (name | defined | exported | hasdoc) ---")
for s in sort(syms)
    sym = Symbol(s)
    isdef = isdefined(Octopus, sym)
    isexp = s in exported
    hasdoc = false
    docstr = ""
    if isdef
        try
            b = Base.Docs.Binding(Octopus, sym)
            d = Base.Docs.doc(b)
            docstr = string(d)
            hasdoc = !occursin("No documentation found", docstr)
        catch e
            docstr = "DOCERR " * sprint(showerror, e)
        end
    end
    println(rpad(s, 46), " | ", rpad(string(isdef), 5), " | ", rpad(string(isexp), 5), " | ", hasdoc)
end
println("--- END SYMBOL TABLE ---")
