#=
Validate that public execution configuration is structurally registered and
reaches actual CPU/CUDA runtime consumers. The contract checks CPU logical
workers, fused CUDA launch geometry, CUDA device mismatch rejection, and every
CUDA PIC launch family. CUDA absence is reported as skipped, never passed,
and under OCTOPUS_REQUIRE_GPU_CONTRACT=1 -- the repository's one switch for
insisting on a GPU leg, parsed by `Octopus._require_gpu_contract()` as in the
sibling contract scripts -- a skip is an error with exit 1. Until 2026-10-22
this was the only contract-running script in `validation/` that printed
`status = skipped` and exited 0 under the flag, so the flag silently did
nothing here (2026-10-18 comprehensive audit, F-243/U54-4).

Run from the project root:

    julia --threads=4 --project=. validation/public_configuration_effectiveness.jl

Environment: OCTOPUS_REQUIRE_GPU_CONTRACT=1 makes a CUDA skip fatal.

The gate's CUDA arm runs this script with the GPU leg required (the testset
"CUDA-requiring validation scripts run in the gate's CUDA arm" in
test/runtests.jl reads the line below; validation/README.md):

GATE-CUDA-ARM: env OCTOPUS_REQUIRE_GPU_CONTRACT=1 ; verdict "cuda_status = passed"
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
# A skip is fatal under the require flag (the shape of the sibling scripts'
# `_gpu_skip_or_error`): "loud beats silent" needs the skip to be assertable.
result.status === :skipped && Octopus._require_gpu_contract() && error(
    "public configuration effectiveness requires a CUDA device and OCTOPUS_REQUIRE_GPU_CONTRACT is set: " *
    result.message)
println("public configuration effectiveness validation complete")
