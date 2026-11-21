# Baseline fingerprints of the flat-keyword optics paths of the LinearOptics batch (docs/design/linear_optics.md;
# audit protocol "baseline fingerprint first"): SHA-256 of the matrices, tracked coordinates and beams every consumer
# builds from its FLAT keywords. Run on the pre-batch tree 9c48589 and again on the batch tree; the 14 hashes must agree,
# since the object form is flattened into the flat form and the flat form itself must not move. The recorded tables are
# beside this file (linear_optics_2026_11_21_baseline_fingerprints.txt: identical before and after, 2026-11-21).
#   julia --project=. docs/history/linear_optics_2026_11_21_baseline.jl [cuda]
using Octopus, SHA, LinearAlgebra, Printf
hexhash(v) = bytes2hex(sha256(collect(reinterpret(UInt8, Vector{Float64}(vec(collect(v)))))))
rows = Pair{String,String}[]
function fp!(name, v); push!(rows, name => hexhash(v)); end

set_global_rng!(seed = 20261121, method = :philox)
β = (0.8, 0.072, 90.9); α = (0.3, -0.2, 0.05)
ζ = (1e-3, 2e-4, -3e-4, 5e-5); η = (0.2, 0.01, -0.03, 2e-3); C = (0.05, 0.01, -0.02, 0.03)
# Linear6DSpec optics form, with and without coupling/dispersion, entrance != exit
s1 = Linear6DSpec{Float64}(; beta1 = β, dmu = (0.7, 1.3, -0.06))
s2 = Linear6DSpec{Float64}(; beta1 = β, beta2 = (1.1, 0.05, 80.0), alpha1 = α, alpha2 = (-0.1, 0.4, 0.0), dmu = (0.7, 1.3, -0.06),
                            zeta1 = ζ, eta1 = η, R1 = C, zeta2 = ζ .* 0.5, eta2 = η .* 2, R2 = C .* -1)
fp!("linear6d_plain_matrix", Matrix(Linear6D(s1)))
fp!("linear6d_coupled_dispersive_matrix", Matrix(Linear6D(s2)))
u = (1e-4, 2e-5, -3e-5, 4e-6, 0.01, -1e-4)
fp!("linear6d_coupled_track", collect(compile_runtime(s2)(u...)))
# the three elementary maps
fp!("xycoupling_modeA", collect(compile_runtime(XYCouplingSpec(r1 = 0.05, r2 = 0.01, r3 = -0.02, r4 = 0.03))(u...)))
fp!("xycoupling_modeB", collect(compile_runtime(XYCouplingSpec(r1 = 0.05, r2 = 0.01, r3 = -0.02, r4 = 0.03, mode = XY_MODEB))(u...)))
fp!("momentum_dispersion", collect(compile_runtime(MomentumDispersionSpec(eta1 = η[1], eta2 = η[2], eta3 = η[3], eta4 = η[4]))(u...)))
fp!("crab_dispersion", collect(compile_runtime(CrabDispersionSpec(zeta1 = ζ[1], zeta2 = ζ[2], zeta3 = ζ[3], zeta4 = ζ[4]))(u...)))
# chromaticity kick with the full quintuple
ck = ChromaticityKickSpec{Float64}(; xi = (2.0, 1.5), beta = β, alpha = α, zeta = ζ, eta = η, R = C)
fp!("chromaticity_kick_track", collect(compile_runtime(ck)(u...)))
# radiation: damping only (deterministic), full quintuple
rd = LumpedRadSpec{Float64}(; damping_turns = (4000.0, 4000.0, 2000.0), beta = β, alpha = α, sigma = (1e-4, 1e-5, 0.01),
                              zeta = ζ, eta = η, R = C, is_damping = true, is_excitation = false, rng_id = 77)
fp!("lumped_rad_damping_track", collect(compile_runtime(rd)(u...)))
# thin strong beam covariance through the transverse optics + coupling
ts = ThinStrongBeamSpec{Float64}(; kbb = -1e-6, beta = (0.45, 0.056), alpha = (0.1, -0.1), sigma = (1e-4, 1e-5), coupling = XYCouplingSpec(r1 = C[1], r2 = C[2], r3 = C[3], r4 = C[4]))
fp!("thin_strong_beam_track", collect(compile_runtime(ts)(u...)))
# Beam: Gaussian with coupling + dispersion (CPU, counter RNG), uniform and grid forms
pol = CPUThreadsExecutionPolicy()
b = Beam(2000, pol, Float64; beta = β, alpha = α, sigma = (1e-4, 1e-5, 0.01), coupling = C, mode = XY_MODEA, eta = η, zeta = ζ, rng_id = 5)
fp!("beam_gaussian_coupled_dispersive", vcat(collect(b.rep.x), collect(b.rep.px), collect(b.rep.y), collect(b.rep.py), collect(b.rep.z), collect(b.rep.pz)))
b2 = Beam(2000, pol, Float64; beta = β, alpha = α, sigma = (1e-4, 1e-5, 0.01), coupling = C, mode = XY_MODEB, rng_id = 6)
fp!("beam_gaussian_coupled_modeB", vcat(collect(b2.rep.x), collect(b2.rep.px), collect(b2.rep.y), collect(b2.rep.py)))
b3 = Beam(pol, Float64; distribution = :grid, lower = (-1e-4, 0.0, -1e-5, 0.0, 0.0, 0.0), upper = (1e-4, 0.0, 1e-5, 0.0, 0.0, 0.0), grid_size = (5, 1, 4, 1, 1, 1))
fp!("beam_grid", vcat(collect(b3.rep.x), collect(b3.rep.y)))
if "cuda" in ARGS
    import CUDA
    gp = CUDAExecutionPolicy(device = 0)
    bg = Beam(2000, gp, Float64; beta = β, alpha = α, sigma = (1e-4, 1e-5, 0.01), coupling = C, mode = XY_MODEA, eta = η, zeta = ζ, rng_id = 5)
    fp!("beam_gaussian_coupled_dispersive_cuda", vcat(Array(bg.rep.x), Array(bg.rep.px), Array(bg.rep.y), Array(bg.rep.py), Array(bg.rep.z), Array(bg.rep.pz)))
end
for (k, v) in rows; @printf("%-44s %s\n", k, v); end
