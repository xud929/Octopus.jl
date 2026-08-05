## (1) Totalized version of the validator's compile check: compile every
##     registered example under EVERY declared tracking method and compare with
##     the declared runtime type for that method. The shipped check only tests
##     the example's own method.
## (2) validate_configuration_metadata()'s type-enumeration completeness:
##     inject a concrete policy / schedule / observer / solver type INSIDE the
##     Octopus module and see which enumerations notice.

using Octopus
using Octopus: compile_runtime, ELEMENT_META_BY_KIND, MisalignedElement, RefTilted

println("== (1) per-declared-method compile sweep ==")
nchecked = 0
nfail = 0
matches(c, rt) = c isa rt || ((c isa MisalignedElement || c isa RefTilted) &&
                              matches(c.inner, rt))
for (kind, meta) in sort(collect(ELEMENT_META_BY_KIND); by = p -> string(p[1]))
    ex = meta.example
    ex isa Octopus.ElementSpec || continue
    for (m, rt) in sort(collect(meta.runtime_types); by = p -> string(nameof(p[1])))
        global nchecked, nfail
        nchecked += 1
        got = try
            compile_runtime(ex, m())
        catch err
            nfail += 1
            println("  FAIL ", kind, " / ", nameof(m), ": does not compile: ",
                    first(split(sprint(showerror, err), '\n')))
            continue
        end
        if !(rt isa Type && matches(got, rt))
            nfail += 1
            println("  FAIL ", kind, " / ", nameof(m), ": compiles to ", typeof(got),
                    ", declared ", rt)
        end
    end
end
println("  checked ", nchecked, " (kind, declared method) pairs; failures = ", nfail)

println()
println("== (2) validate_configuration_metadata enumeration completeness ==")

function check(label)
    try
        validate_configuration_metadata()
        println("  MISSED  ", label, "  (validator returned true)")
    catch err
        msg = sprint(showerror, err)
        println("  CAUGHT  ", label)
        for l in split(msg, '\n')
            occursin("U12", l) && println("        | ", strip(l))
        end
    end
end

@eval Octopus struct U12FakePolicy <: AbstractExecutionPolicy
    knob::Int
end
@eval Octopus U12FakePolicy() = U12FakePolicy(1)
check("new concrete AbstractExecutionPolicy in Octopus with no schema block")

@eval Octopus struct U12FakeSchedule <: AbstractSchedule
    every::Int
end
check("new concrete AbstractSchedule in Octopus with no schema block")

@eval Octopus struct U12FakeSolver <: AbstractPoissonSolver
    grid::Int
end
check("new concrete AbstractPoissonSolver in Octopus with no schema block")

println()
println("== declared subtype trees as the validator sees them ==")
using InteractiveUtils: subtypes
for R in (Octopus.AbstractExecutionPolicy, Octopus.AbstractSchedule,
          Octopus.AbstractPoissonSolver, Octopus.AbstractBeamObserver)
    println("  ", nameof(R), ": ", [nameof(T) for T in Octopus._subtypes_recursive(R)])
end
