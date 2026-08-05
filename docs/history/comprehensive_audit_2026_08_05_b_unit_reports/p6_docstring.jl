## Does a comment interposed between a docstring and its definition detach the
## docstring on this Julia? Measured (a) on the one instance in the U12 region,
## (b) on a synthetic control pair.

using Octopus
println("Julia ", VERSION)

d = string(Base.Docs.doc(Base.Docs.Binding(Octopus, :_compiled_matches_runtime)))
println("\n_compiled_matches_runtime doc =\n", d)
println("DETACHED = ", occursin("No documentation found", d))

module U12Ctl
"""attached: no comment between docstring and definition."""
f_attached(x) = x

"""detached?: a comment sits between this docstring and the definition."""
# an interposed comment
# and a second one
f_commented(x) = x
end

for n in (:f_attached, :f_commented)
    s = string(Base.Docs.doc(Base.Docs.Binding(U12Ctl, n)))
    println("\n", n, " -> ", occursin("No documentation found", s) ? "NO DOC" : "HAS DOC")
    println("   ", first(split(s, '\n'; limit=4)))
end
