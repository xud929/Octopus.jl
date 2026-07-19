#=
Validate the shared three-plane Beam optics interface. With identical counter
RNG input, legacy `(alpha_x, alpha_y)` construction must exactly match
`(alpha_x, alpha_y, 0)`. Sigma- and emittance-based construction must agree,
and a nonzero longitudinal alpha must add exactly `-alpha_z*z/beta_z` to pz.
The checks run on CPU and CUDA when CUDA is available and write no files.

Run from the project root:

    julia --project=. validation/beam_optics_interface_consistency.jl
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus

const N = 4096
const BETA = (0.8, 0.072, 90.0)
const SIGMA = (95.0e-6, 8.5e-6, 6.0e-2)
const ALPHA_XY = (0.3, -0.2)
const ALPHA_ZERO_Z = (ALPHA_XY..., 0.0)
const ALPHA_Z = 0.4
const EMIT = ntuple(i -> SIGMA[i]^2 / BETA[i], 3)

function make_beam(backend, alpha; sigma=SIGMA, emit=nothing)
    set_global_rng!(seed=0x12345678, method=:philox)
    return Beam(N, backend, Float64; beta=BETA, alpha, sigma, emit,
                cutoff=Inf, rng_id=17)
end

function arrays_on_cpu(beam)
    return map(Array, coordinate_arrays(beam))
end

function legacy_sigma_reference(backend)
    set_global_rng!(seed=0x12345678, method=:philox)
    rep = Octopus._standard_gaussian_rep(backend, Float64, N;
                                         cutoff=Inf, rng_id=17)
    rep.px .= (SIGMA[1] / BETA[1]) .* (rep.px .- ALPHA_XY[1] .* rep.x)
    rep.x .*= SIGMA[1]
    rep.py .= (SIGMA[2] / BETA[2]) .* (rep.py .- ALPHA_XY[2] .* rep.y)
    rep.y .*= SIGMA[2]
    rep.pz .*= SIGMA[3] / BETA[3]
    rep.z .*= SIGMA[3]
    return map(Array, coordinate_arrays(rep))
end

function check_backend(backend)
    legacy = arrays_on_cpu(make_beam(backend, ALPHA_XY))
    shared = arrays_on_cpu(make_beam(backend, ALPHA_ZERO_Z))
    legacy == shared || error("legacy and three-plane alpha differ on $(backend)")
    legacy == legacy_sigma_reference(backend) ||
        error("alpha_z=0 differs from the previous sigma normalization on $(backend)")

    sigma_beam = arrays_on_cpu(make_beam(backend, ALPHA_ZERO_Z))
    emit_beam = arrays_on_cpu(make_beam(backend, ALPHA_ZERO_Z; sigma=nothing, emit=EMIT))
    all(isapprox.(sigma_beam, emit_beam; rtol=2eps(Float64), atol=0.0)) ||
        error("sigma and emittance construction differ on $(backend)")

    tilted = arrays_on_cpu(make_beam(backend, (ALPHA_XY..., ALPHA_Z)))
    expected_pz = shared[6] .- (ALPHA_Z / BETA[3]) .* shared[5]
    isapprox(tilted[6], expected_pz; rtol=4eps(Float64), atol=4eps(Float64)) ||
        error("longitudinal alpha normalization is incorrect on $(backend)")
    tilted[1:5] == shared[1:5] ||
        error("longitudinal alpha changed unrelated coordinates on $(backend)")
    println(backend, ": shared beam optics interface passed")
end

check_backend(CPUThreadsBackend)
available, reason = Octopus._contract_backends_available(CUDABackend)
available ? check_backend(CUDABackend) : println("CUDABackend skipped: ", reason)

chrom2 = ChromaticityKick(ChromaticityKickSpec(xi=(2.0, 1.0), beta=BETA[1:2], alpha=ALPHA_XY))
chrom3 = ChromaticityKick(ChromaticityKickSpec(xi=(2.0, 1.0), beta=BETA, alpha=ALPHA_ZERO_Z))
probe = (1.1e-4, 2.0e-5, -8.0e-6, 3.0e-6, 0.01, 7.0e-4)
chrom2(probe...) == chrom3(probe...) ||
    error("two- and three-plane ChromaticityKickSpec inputs differ")
println("ChromaticityKickSpec shared optics interface passed")
