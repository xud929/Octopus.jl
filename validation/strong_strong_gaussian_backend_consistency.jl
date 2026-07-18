#=
Run the public strong-strong soft-Gaussian CPU/CUDA backend consistency contract.

The contract checks both live beams and luminosity. CUDA unavailability is
reported as skipped unless explicitly required.

Run from the Octopus project root:

    julia --threads=4 --project=. validation/strong_strong_gaussian_backend_consistency.jl

Controls:

    OCTOPUS_GAUSSIAN_CONTRACT_N=1000
    OCTOPUS_GAUSSIAN_CONTRACT_TURNS=2
    OCTOPUS_GAUSSIAN_CONTRACT_RTOL=1e-10
    OCTOPUS_REQUIRE_GPU_CONTRACT=1

The contract uses temporary luminosity files and leaves no result artifacts.
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus

const N = parse(Int, get(ENV, "OCTOPUS_GAUSSIAN_CONTRACT_N", "1000"))
const TURNS = parse(Int, get(ENV, "OCTOPUS_GAUSSIAN_CONTRACT_TURNS", "2"))
const RTOL = parse(Float64, get(ENV, "OCTOPUS_GAUSSIAN_CONTRACT_RTOL", "1e-10"))
const REQUIRE_GPU = get(ENV, "OCTOPUS_REQUIRE_GPU_CONTRACT", "0") in
                    ("1", "true", "TRUE", "yes", "YES")

contract = StrongStrongGaussianBackendConsistencyContract(
    n_particles=N,
    turns=TURNS,
    rtol=RTOL,
    luminosity_rtol=RTOL,
)
result = validate(contract)

println("Strong-strong Gaussian backend consistency")
println("  status = ", result.status)
println("  message = ", result.message)
for key in sort!(collect(keys(result.metrics)); by=string)
    println("  ", key, " = ", result.metrics[key])
end

if result.status == :skipped
    REQUIRE_GPU && error("strong-strong Gaussian GPU contract was required but skipped")
elseif !result.passed
    error("strong-strong Gaussian backend consistency failed")
end
