#=
Validate that public execution configuration is structurally registered and
reaches actual CPU/CUDA runtime consumers. The contract checks CPU logical
workers, fused CUDA launch geometry, CUDA device mismatch rejection, and every
CUDA PIC launch family. CUDA absence is reported as skipped, never passed.

Run from the project root:

    julia --threads=4 --project=. validation/public_configuration_effectiveness.jl
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus

validate_configuration_metadata()
result = validate(PublicConfigurationEffectivenessContract())

println("Public configuration effectiveness")
println("  status = ", result.status)
println("  message = ", result.message)
for key in sort!(collect(keys(result.metrics)); by=string)
    println("  ", key, " = ", result.metrics[key])
end

result.status === :failed && error(result.message)
println("public configuration effectiveness validation complete")
