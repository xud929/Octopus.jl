using Octopus
const O = Octopus
u = (2.3e-3, 4.1e-4, -1.7e-3, -3.2e-4, 1.5e-3, 9.0e-4)
contract = ElementParameterEffectivenessContract()

println("=== X. _perturb_param on the placement schema: Int 0 -> +1 (metre / radian) ===")
pp = O._PLACEMENT_PARAMS
for (k, m) in pairs(pp)
    println("  ", rpad(string(k), 10), " default=", repr(m.default), "::", typeof(m.default),
            "  unit=", repr(m.unit),
            "  _perturb_param -> ", repr(O._perturb_param(k, m.default)))
end
println("  -> every placement parameter absent from a kind's probe is perturbed by")
println("     ONE METRE or ONE RADIAN, because the schema default is the integer 0.")

println()
println("=== Y. the 29 'rejected' perturbations: why, and what the contract concludes ===")
for T in O.registered_element_specs()
    meta = O._element_meta_or_nothing(T); meta === nothing && continue
    ctor = meta.friendly_constructor; ctor === nothing && continue
    probe = haskey(contract.probes, meta.kind) ?
        Dict{Symbol,Any}(pairs(contract.probes[meta.kind])) :
        (O.example_spec(T) isa ElementSpec ? Dict{Symbol,Any}(O.params(O.example_spec(T))) : nothing)
    probe === nothing && continue
    try O.compile_runtime(ctor(; probe...))(u...) catch; continue end
    for (key, pmeta) in pairs(O.parameter_schema(T))
        pmeta isa O.ParamMeta || continue
        haskey(contract.inactive, (meta.kind, key)) && continue
        current = get(probe, key, pmeta.default === nothing ? 0.0 : pmeta.default)
        new = O._perturb_param(key, current); new === nothing && continue
        try
            O.compile_runtime(ctor(; merge(probe, Dict{Symbol,Any}(key => new))...))(u...)
        catch err
            println("  ", rpad("$(meta.kind).$(key)", 32), " ", repr(current), " -> ", repr(new),
                    "  :: ", first(split(sprint(showerror, err), '\n'))[1:min(96,end)])
        end
    end
end
println()
println("  contract's rule at that catch: `continue   # a rejected value is consumed by definition`")
println("  -> not counted in `checked`, not reported in `ignored`, invisible in `metrics`.")

println()
println("=== Z. a smaller, physical perturbation makes several of them checkable ===")
sb = Dict{Symbol,Any}(pairs(contract.probes[:sbend]))
base = collect(O.compile_runtime(O.SBendSpec(; sb...))(u...))
for (k, v) in ((:y_offset, 1.0e-3), (:x_pitch, 1.0e-3), (:y_pitch, 1.0e-3))
    m = collect(O.compile_runtime(O.SBendSpec(; merge(sb, Dict{Symbol,Any}(k=>v))...))(u...))
    println("  sbend.", rpad(string(k), 10), " perturbed by ", v, " -> max|delta| = ", maximum(abs, m .- base))
end
