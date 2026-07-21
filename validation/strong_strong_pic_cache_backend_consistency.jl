#=
Run the public strong-strong PIC CPU/CUDA backend consistency contract.

The contract checks both live beams, luminosity, persistent cache reuse, and
identical CPU/CUDA cache hit/miss/rebuild histories. CUDA unavailability is
reported as skipped unless explicitly required.

Run from the Octopus project root:

    julia --threads=4 --project=. validation/strong_strong_pic_cache_backend_consistency.jl

Controls:

    OCTOPUS_CACHE_CONTRACT_N=1000
    OCTOPUS_CACHE_CONTRACT_TURNS=2
    OCTOPUS_CACHE_CONTRACT_DEPOSIT_METHOD=CIC
    OCTOPUS_CACHE_CONTRACT_RTOL=1e-10
    OCTOPUS_REQUIRE_GPU_CONTRACT=1

The contract uses temporary luminosity files and leaves no result artifacts.
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus

const N = parse(Int, get(ENV, "OCTOPUS_CACHE_CONTRACT_N", "1000"))
const TURNS = parse(Int, get(ENV, "OCTOPUS_CACHE_CONTRACT_TURNS", "2"))
const DEPOSIT_METHOD = Symbol(uppercase(
    get(ENV, "OCTOPUS_CACHE_CONTRACT_DEPOSIT_METHOD", "CIC"),
))
const RTOL = parse(Float64, get(ENV, "OCTOPUS_CACHE_CONTRACT_RTOL", "1e-10"))
const REQUIRE_GPU = get(ENV, "OCTOPUS_REQUIRE_GPU_CONTRACT", "0") in
                    ("1", "true", "TRUE", "yes", "YES")

contract = StrongStrongPICBackendConsistencyContract(
    n_particles=N,
    turns=TURNS,
    deposit_method=DEPOSIT_METHOD,
    rtol=RTOL,
    luminosity_rtol=RTOL,
)
result = validate(contract)

println("Strong-strong PIC backend consistency")
println("  status = ", result.status)
println("  message = ", result.message)
for key in sort!(collect(keys(result.metrics)); by=string)
    println("  ", key, " = ", result.metrics[key])
end

if result.status == :skipped
    REQUIRE_GPU && error("strong-strong PIC GPU contract was required but skipped")
elseif !result.passed
    error("strong-strong PIC backend consistency failed")
end
