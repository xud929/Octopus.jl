# U18 probe 3: is the h != 0 sweep's case list derived, or hand-asserted?
# test/runtests.jl "Curved frame x transverse field: every routing is a gradient"
# claims: "this pins the whole content grid on the only two kinds whose schemas
# offer both curvature and field (derived, not assumed: no other registered kind
# carries both)".
using Octopus

curv_keys = (:h, :curved, :b0)
field_keys = (:kn, :ks, :kskew, :k1, :k2, :k3, :knl, :ksl, :k0l, :k1l, :k2l)

kinds = sort(collect(keys(Octopus.ELEMENT_META_BY_KIND)))
println("registered kinds: ", length(kinds))
both = Symbol[]
for k in kinds
    sch = try
        Octopus.parameter_schema(ElementSpec{k})
    catch e
        println("  ", k, ": schema error ", e); continue
    end
    ks = propertynames(sch)
    c = [x for x in curv_keys if x in ks]
    f = [x for x in field_keys if x in ks]
    if !isempty(c) && !isempty(f)
        push!(both, k)
        println("  BOTH: ", rpad(String(k), 26), " curvature=", c, "  field=", f)
    elseif !isempty(c)
        println("  curv only: ", rpad(String(k), 22), c)
    end
end
println()
println("kinds carrying BOTH curvature and field in their schema: ", both)
println("the testset sweeps: [:sbend, :solenoid] (+ a raw :quadrupole with an undeclared h)")
println("NOT swept but carrying both: ", setdiff(both, [:sbend, :solenoid, :quadrupole]))

println()
println("--- runtime types that the SymplecticityContract covers ---")
r = validate(SymplecticityContract())
println("status=", r.status, " passed=", r.passed)
println("kinds_declaring_without_case = ", r.metrics[:kinds_declaring_without_case])
println("metric keys: ", sort(collect(String.(keys(r.metrics)))))
