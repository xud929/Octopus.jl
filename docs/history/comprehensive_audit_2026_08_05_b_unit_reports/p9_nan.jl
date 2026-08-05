using Octopus
const O = Octopus
u = (2.3e-3, 4.1e-4, -1.7e-3, -3.2e-4, 1.5e-3, 9.0e-4)
contract = ElementParameterEffectivenessContract()

println("=== U. NaN-poisoned baselines make the `ignored` test unfalsifiable ===")
println("  the contract's decision is `maximum(abs, moved .- baseline) <= atol`  (atol = 0.0)")
println("  NaN <= 0.0 is FALSE, so a NaN comparison is scored 'the parameter moved the map'.")
println()
nan_kinds = Symbol[]
for T in O.registered_element_specs()
    meta = O._element_meta_or_nothing(T); meta === nothing && continue
    ctor = meta.friendly_constructor; ctor === nothing && continue
    probe = haskey(contract.probes, meta.kind) ?
        Dict{Symbol,Any}(pairs(contract.probes[meta.kind])) :
        (O.example_spec(T) isa ElementSpec ? Dict{Symbol,Any}(O.params(O.example_spec(T))) : nothing)
    probe === nothing && continue
    base = try collect(O.compile_runtime(ctor(; probe...))(u...)) catch; continue end
    if !all(isfinite, base)
        push!(nan_kinds, meta.kind)
        println("  BASELINE NOT FINITE: ", rpad(string(meta.kind), 14), " -> ", base)
    end
end
isempty(nan_kinds) && println("  (none)")

println()
println("=== V. proof the aperture half of the contract cannot fail ===")
ap = Dict{Symbol,Any}(pairs(contract.probes[:aperture]))
base = collect(O.compile_runtime(O.ApertureSpec(; ap...))(u...))
println("  aperture probe          = ", contract.probes[:aperture])
println("  baseline map            = ", base)
n_ap = 0; n_nan = 0
for (key, pmeta) in pairs(O.parameter_schema(O.ElementSpec{:aperture}))
    pmeta isa O.ParamMeta || continue
    haskey(contract.inactive, (:aperture, key)) && continue
    current = get(ap, key, pmeta.default === nothing ? 0.0 : pmeta.default)
    new = O._perturb_param(key, current); new === nothing && continue
    moved = try collect(O.compile_runtime(O.ApertureSpec(; merge(ap, Dict{Symbol,Any}(key=>new))...))(u...))
            catch; continue end
    global n_ap += 1
    d = maximum(abs, moved .- base)
    isnan(d) && (global n_nan += 1)
    println("    ", rpad(string(key), 22), " perturbed->", rpad(repr(new), 10),
            " max|delta| = ", d, isnan(d) ? "   <-- NaN, scored as 'moved'" : "")
end
println("  aperture parameters counted as `checked`: ", n_ap, ";  of those NaN-decided: ", n_nan)
println("  a genuinely ignored aperture parameter would be scored EFFECTIVE by this rule.")

println()
println("=== W. control: does the contract notice a deliberately inert aperture param? ===")
# Force one: give aperture a huge limit so the particle survives and the map is
# the identity; every limit then IS inert, and the contract must say so.
ap2 = Dict{Symbol,Any}(:shape=>:ellipse, :x_limit=>1.0, :y_limit=>1.0, :dx=>1.0e-5, :dy=>2.0e-5)
probes2 = copy(contract.probes); probes2[:aperture] = NamedTuple(ap2)
r = validate(ElementParameterEffectivenessContract(probes=probes2))
println("  with a generous aperture (particle survives, map is identity): ", r.status)
println("  ", r.message[1:min(240, end)])
