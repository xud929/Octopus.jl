# U25 probe: enumerate the kinds that declare ElementTrackingBackendConsistencyContract
# and compare with the kinds covered by validation/tracking_backend_consistency.jl's line.
if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "runroot", "src", "Octopus.jl"))
end
using .Octopus

declaring = Symbol[]
for T in Octopus.registered_element_specs()
    meta = Octopus._element_meta_or_nothing(T)
    meta === nothing && continue
    any(C -> C === ElementTrackingBackendConsistencyContract, meta.contracts) &&
        push!(declaring, meta.kind)
end
sort!(declaring)
println("DECLARING (", length(declaring), "): ", join(declaring, ", "))

alltypes = Octopus.registered_element_specs()
println("REGISTERED SPEC TYPES: ", length(alltypes))
kinds = Symbol[]
for T in alltypes
    meta = Octopus._element_meta_or_nothing(T)
    meta === nothing && continue
    push!(kinds, meta.kind)
end
sort!(kinds)
println("ALL KINDS (", length(kinds), "): ", join(kinds, ", "))
println("NON-DECLARING (", length(setdiff(kinds, declaring)), "): ",
        join(sort(setdiff(kinds, declaring)), ", "))
