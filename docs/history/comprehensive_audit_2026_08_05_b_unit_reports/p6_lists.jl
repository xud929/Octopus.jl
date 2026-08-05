using Octopus
using InteractiveUtils: subtypes
const O = Octopus

println("=== L. every solver-option CATEGORY in use vs the two hardcoded category lists ===")
docd_physics = (:physics, :numerical, :physics_override, :accuracy_performance, :diagnostic)
docd_exec    = (:execution, :performance)       # _solver_option_is_execution
cats = Set{Symbol}()
for T in O._solver_contract_types(), (_, m) in pairs(O.solver_option_schema(T))
    push!(cats, m.category)
end
println("  categories in the solver schemas: ", sort(collect(cats)))
println("  unclassified by _solver_option_is_execution's two lists: ",
        sort(collect(setdiff(cats, Set(docd_physics) ∪ Set(docd_exec)))))
println("  (an unclassified category silently falls into the MUST-MOVE branch)")

println()
println("=== M. DEFAULT_INACTIVE_SOLVER_OPTIONS staleness ===")
live = Set{Tuple{Symbol,Symbol}}()
for T in O._solver_contract_types(), (n, _) in pairs(O.solver_option_schema(T))
    push!(live, (nameof(T), n))
end
for k in sort(collect(keys(O.DEFAULT_INACTIVE_SOLVER_OPTIONS)))
    println("  ", k, "  -> ", k in live ? "live" : "STALE (no such (solver,option))")
end

println()
println("=== N. deposit-method enumeration hand-copied into the PIC contract ===")
for m in (:CIC, :TSC, :NGP, :typo)
    ok = try (O.PICPoissonSolver(grid=(16,16), deposit_method=m); "accepted") catch e; "rejected" end
    println("  PICPoissonSolver(deposit_method=:", m, ") -> ", ok,
            "  | contract's own list (:CIC,:TSC) accepts: ", m in (:CIC, :TSC))
end

println()
println("=== O. symplecticity coverage vs the symplectic-map kinds ===")
cases = O._symplecticity_contract_cases()
covered = Symbol[]; uncovered = Symbol[]; nonsympl = Symbol[]
for T in O.registered_element_specs()
    m = O._element_meta_or_nothing(T); m === nothing && continue
    if !any(t -> t === O.Symplectic6DMap, m.tracking_methods)
        push!(nonsympl, m.kind); continue
    end
    RT = m.runtime_type
    (RT !== nothing && any(c -> c.element isa RT, cases)) ?
        push!(covered, m.kind) : push!(uncovered, m.kind)
end
println("  kinds whose declared tracking methods include Symplectic6DMap: ",
        length(covered) + length(uncovered))
println("  WITH a symplecticity case (", length(covered), "): ", sort(covered))
println("  WITHOUT a case  (", length(uncovered), "): ", sort(uncovered))
println("  the declaration tripwire constrains only kinds whose ElementMeta lists")
println("  SymplecticityContract, which today is exactly: ",
        [m.kind for m in (O._element_meta_or_nothing(T) for T in O.registered_element_specs())
         if m !== nothing && any(C -> C === O.SymplecticityContract, m.contracts)])
println("  non-Symplectic6DMap kinds (out of scope): ", sort(nonsympl))

println()
println("=== P. KnobEffectivenessContract cleanup list vs the knobs it defines ===")
src = read(joinpath(pkgdir(O), "src", "contracts", "Contracts.jl"), String)
i0 = findfirst("function validate(contract::KnobEffectivenessContract", src)[1]
i1 = findfirst("function validate(contract::PublicConfigurationEffectivenessContract", src)[1]
body = src[i0:i1]
defined = Set(m.captures[1] for m in eachmatch(r"__knob_contract__\.(\w+)", body))
listed = Set(["current","transfer","brho","k1","unset"])
println("  knob paths mentioned in the contract body: ", sort(collect(defined)))
println("  paths in the hand-written contract_paths cleanup tuple: ", sort(collect(listed)))
println("  mentioned-but-not-cleaned: ", sort(collect(setdiff(defined, listed))))

println()
println("=== Q. PTC reference table + generator derivation ===")
p = O._ptc_reference_path(PTCConsistencyContract())
println("  resolved table: ", p)
println("  files in validation/reference: ",
        readdir(joinpath(pkgdir(O), "validation", "reference")))
gen = read(joinpath(pkgdir(O), "validation", "generate_ptc_reference.jl"), String)
println("  generator consumes _ptc_reference_specs()? ",
        occursin("_ptc_reference_specs", gen))
println("  declared specs: ", length(O._ptc_reference_specs()))
