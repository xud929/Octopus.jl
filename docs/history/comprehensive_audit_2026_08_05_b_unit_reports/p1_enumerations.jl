using Octopus
using InteractiveUtils: subtypes
const O = Octopus

_rec(T) = (out = Any[]; for S in subtypes(T); push!(out, S); append!(out, _rec(S)); end; unique(out))

println("=== A. CONTRACT TYPE TREE (derived) vs exports ===")
allc = _rec(O.AbstractContract)
concrete = [T for T in allc if !isabstracttype(T)]
println("abstract subtypes: ", [T for T in allc if isabstracttype(T)])
println("concrete contracts (", length(concrete), "):")
for T in sort(concrete; by=string)
    hasval = try
        length(methods(O.validate, (T,))) > 0
    catch; false end
    hasdesc = try
        applicable(O.description, Type{T}) && (O.description(T) isa AbstractString)
    catch; false end
    exported = Base.isexported(O, nameof(T))
    println("  ", rpad(string(nameof(T)), 46),
            " defined_in=", parentmodule(T),
            " exported=", exported,
            " description=", hasdesc)
end

println()
println("=== B. POISSON SOLVER TREE (derived) vs _solver_contract_types() and probes ===")
solvers = _rec(O.AbstractPoissonSolver)
println("full tree: ", solvers)
conc = [T for T in solvers if !isabstracttype(T) && parentmodule(T) === O]
println("concrete Octopus-defined: ", conc)
println("_solver_contract_types(): ", O._solver_contract_types())
println("probes keys: ", sort(collect(keys(O._default_solver_option_probes())); by=string))
println("alternatives keys: ", sort(collect(keys(O._default_solver_option_alternatives())); by=string))
missing_from_sweep = [T for T in conc if !(T in O._solver_contract_types())]
println("CONCRETE SOLVERS MISSING FROM _solver_contract_types(): ", missing_from_sweep)
# the tripwire iterates subtypes() NON-recursively:
println("subtypes(AbstractPoissonSolver) (non-recursive, what the tripwire walks): ", subtypes(O.AbstractPoissonSolver))
println("recursive-only members (invisible to the tripwire): ",
        setdiff(Set(solvers), Set(subtypes(O.AbstractPoissonSolver))))

println()
println("=== C. SYMPLECTICITY: declared vs cases ===")
cases = O._symplecticity_contract_cases()
println("case names: ", [c.name for c in cases])
println("case runtime types: ", unique([typeof(c.element) for c in cases]))
declaring = Symbol[]
for T in O.registered_element_specs()
    m = O._element_meta_or_nothing(T)
    m === nothing && continue
    any(C -> C === O.SymplecticityContract, m.contracts) || continue
    push!(declaring, m.kind)
end
println("kinds DECLARING SymplecticityContract (", length(declaring), "): ", sort(declaring))
# which case runtime types map to which declaring kinds
for k in sort(declaring)
    T = first(t for t in O.registered_element_specs() if O._element_meta_or_nothing(t) !== nothing && O._element_meta_or_nothing(t).kind === k)
    RT = O._element_meta_or_nothing(T).runtime_type
    hit = [c.name for c in cases if c.element isa RT]
    println("  ", rpad(string(k), 26), " runtime=", RT, " covered_by=", hit)
end
# reverse: which registered kinds have a Symplectic6DMap tracking method but do NOT declare
println("--- kinds that could plausibly declare but do not:")
for T in O.registered_element_specs()
    m = O._element_meta_or_nothing(T); m === nothing && continue
    m.kind in declaring && continue
    tm = m.tracking_methods
    if any(t -> occursin("Symplectic", string(t)), tm)
        println("  ", rpad(string(m.kind), 26), " methods=", tm, " contracts=", m.contracts)
    end
end
