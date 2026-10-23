using Statistics

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus

#=
Validate the counter-based RNG used by stochastic tracking prototypes.

Run from the project root:

    julia --project=. validation/counter_rng_validation.jl

Optional environment variables:

    OCTOPUS_RNG_VALIDATION_N=1000000
    OCTOPUS_RNG_VALIDATION_SEED=123456789
    OCTOPUS_RNG_VALIDATION_TURN=7
    OCTOPUS_RNG_VALIDATION_RNG_ID=11
    OCTOPUS_RNG_VALIDATION_BACKEND=philox
    OCTOPUS_RNG_VALIDATION_WRITE_CSV=true

Output: nothing unless `OCTOPUS_RNG_VALIDATION_WRITE_CSV=true`, which writes
`result/counter_rng_validation_summary.csv`. That destination moved out of the
tracked `validation/` tree in the 2026-08-05 audit (U19-8) and was recorded in
neither this header nor the README (2026-08-05_b audit, U25-8).

What each half of this script can and cannot detect (2026-08-05_b audit, U25-2):

  * The MOMENT checks below (means, variances, the two correlations, the tail
    fractions) are a statistics test, not a generator test. They are satisfied
    by any generator with good low-order behaviour, whatever its round
    function. Measured: a Philox4x32 with the Weyl key bump REMOVED, and a
    3-round variant, both pass every one of them. Do not read a pass here as
    evidence that the generator is the algorithm it claims to be.
  * The KNOWN-ANSWER check does exactly that, and is the anchor: it drives the
    production block function against the upstream Random123 `kat_vectors` for
    philox4x32-10 and reproduces them bit-for-bit or fails. It runs first here,
    and again in `test/runtests.jl` ("Philox4x32-10 matches the Random123
    known-answer vectors"), from one shared implementation.

The moment checks remain useful for what they are: they catch a driver that
mis-maps counters onto the block function, which a known-answer vector on the
block alone would not see. Neither half is a full statistical test suite.

Every bound is SIX SIGMA of the statistic's own sampling sd at the run's N and
is printed beside the value: the means and correlations 1/sqrt(N) (the uniform
mean over sqrt(12)), the normal variance sqrt(2/N), the uniform variance
sqrt((mu_4 - sigma^4)/N) = 1/sqrt(180 N), and the three tail fractions
P(|N| > 2, 3, 4) their binomial sd sqrt(p (1 - p)/N), with p from the
package's own normal CDF. Until 2026-10-22 the uniform-variance bound was the
normal-case sqrt(2/N) scaled by the variance (1.58 times too loose) and the
tail fractions were printed, never judged (2026-10-18 comprehensive audit,
F-209: U40-6, U40-7).
=#

N = parse(Int, get(ENV, "OCTOPUS_RNG_VALIDATION_N", "1000000"))
seed = parse(UInt64, get(ENV, "OCTOPUS_RNG_VALIDATION_SEED", "123456789"))
turn = parse(Int, get(ENV, "OCTOPUS_RNG_VALIDATION_TURN", "7"))
rng_id = parse(UInt64, get(ENV, "OCTOPUS_RNG_VALIDATION_RNG_ID", "11"))
backend = Symbol(lowercase(get(ENV, "OCTOPUS_RNG_VALIDATION_BACKEND", "philox")))
write_csv = lowercase(get(ENV, "OCTOPUS_RNG_VALIDATION_WRITE_CSV", "false")) in ("1", "true", "yes")

normal_value = backend == :philox ? counter_normal :
               backend == :splitmix ? splitmix_normal :
               error("unknown OCTOPUS_RNG_VALIDATION_BACKEND=$(backend); use philox or splitmix")
uniform_value = backend == :philox ? counter_uniform01 : splitmix_uniform01

# The generator identity check, first and loudest: everything below it is a
# statistics test that a wrong Philox passes (U25-2).
kat_ok = philox4x32_self_test()
println("Philox4x32-10 known-answer vectors = ", kat_ok)
kat_ok || error("Philox4x32-10 does not reproduce the Random123 known-answer " *
                "vectors: the generator is not the algorithm it claims to be. " *
                "No moment statistic below can substitute for this.")

samples = Vector{Float64}(undef, N)
samples2 = Vector{Float64}(undef, N)
uniforms = Vector{Float64}(undef, N)

for i in 1:N
    samples[i] = normal_value(seed, turn, rng_id, i, 1, Float64)
    samples2[i] = normal_value(seed, turn, rng_id, i, 2, Float64)
    uniforms[i] = uniform_value(seed, turn, rng_id, i, 1, Float64)
end

mean_normal = mean(samples)
var_normal = var(samples; corrected=true)
mean_uniform = mean(uniforms)
var_uniform = var(uniforms; corrected=true)
corr_pair = cor(samples, samples2)
corr_neighbor = cor(samples[1:end-1], samples[2:end])
tail2 = count(x -> abs(x) > 2, samples) / N
tail3 = count(x -> abs(x) > 3, samples) / N
tail4 = count(x -> abs(x) > 4, samples) / N
tails = Dict(2 => tail2, 3 => tail3, 4 => tail4)
# The expected two-sided tail fractions P(|N| > k) = 2 (1 - Phi(k)) of a unit
# normal, from the package's own normal CDF rather than three typed constants.
tail_expected = Dict(k => 2 * (1 - Octopus._snorm_cdf(float(k))) for k in (2, 3, 4))

repro_ok = normal_value(seed, turn, rng_id, 123, 4, Float64) ==
           normal_value(seed, turn, rng_id, 123, 4, Float64)
stream_sep = normal_value(seed, turn, rng_id, 123, 4, Float64) !=
             normal_value(seed, turn, rng_id + 1, 123, 4, Float64)
turn_sep = normal_value(seed, turn, rng_id, 123, 4, Float64) !=
           normal_value(seed, turn + 1, rng_id, 123, 4, Float64)

# Tolerances SCALE with N, because the statistics they bound do.
#
# These were fixed absolute constants (5e-3 on the means and correlations, 1e-2
# on the normal variance) while every one of those quantities has a sampling
# error of order 1/sqrt(N). At the default N = 1e6 that made |mean| < 5e-3 a 5
# sigma bound, which is fine -- but at N = 2e5, which validation/README.md
# itself advertises as "a smaller check", it is 2.2 sigma, and at N = 1e5 it is
# 1.6 sigma. A perfectly healthy generator fails the gate at the smaller N the
# documentation recommends (2026-08-05_b audit, U25-3).
#
# 6 sigma keeps a healthy generator passing at every N while still catching a
# real bias, which a fixed constant cannot do at both ends of the range.
sigma_mean = 1 / sqrt(N)                 # sd of a mean of unit-variance samples
sigma_var = sqrt(2 / N)                  # sd of a variance estimate, normal case
sigma_corr = 1 / sqrt(N)                 # sd of a correlation at rho = 0
tol_mean_normal = 6 * sigma_mean
tol_var_normal = 6 * sigma_var
tol_mean_uniform = 6 * sigma_mean / sqrt(12)      # uniform sd is 1/sqrt(12)
# The sd of a sample variance is sqrt((mu_4 - sigma^4)/N) for ANY distribution;
# for U(0, 1) mu_4 = 1/80 and sigma^2 = 1/12, so it is sqrt(1/(180 N)) =
# 0.0745/sqrt(N). Until 2026-10-22 this line read `6 * (1/12) * sqrt(2/N)`
# (0.1179/sqrt(N) per sigma): the NORMAL-case sqrt(2/N) scaled by the uniform
# variance, which the comment presented as the derivation; 1.58 times too
# loose, so the "6 sigma" gate on the uniform variance was a 9.5-sigma gate
# (2026-10-18 comprehensive audit, F-209/U40-6).
sigma_var_uniform = sqrt((1 / 80 - 1 / 144) / N)
tol_var_uniform = 6 * sigma_var_uniform
tol_corr = 6 * sigma_corr
# A tail fraction is a binomial proportion with sd sqrt(p (1 - p)/N); the same
# six sigma. Until 2026-10-22 the three fractions were printed "expected about
# ..." and never entered `ok`, although the header counted them among the
# moment checks: a generator with clipped or inflated tails (a truncated
# inverse CDF, a Box-Muller with a bad logarithm) passed this script
# (F-209/U40-7).
tol_tail(p) = 6 * sqrt(p * (1 - p) / N)

println("Counter RNG validation")
println("N = ", N)
println("seed = ", seed)
println("turn = ", turn)
println("rng_id = ", rng_id)
println("backend = ", backend)
println("normal mean = ", mean_normal, "   (|.| <= ", tol_mean_normal, ": 6 sigma of 1/sqrt(N))")
println("normal variance = ", var_normal, "   (|. - 1| <= ", tol_var_normal, ": 6 sigma of sqrt(2/N))")
println("uniform mean = ", mean_uniform, "   (|. - 1/2| <= ", tol_mean_uniform, ": 6 sigma of 1/sqrt(12 N))")
println("uniform variance = ", var_uniform, "   (|. - 1/12| <= ", tol_var_uniform, ": 6 sigma of sqrt((mu_4 - sigma^4)/N) = 1/sqrt(180 N))")
println("corr(normal component 1, component 2) = ", corr_pair, "   (|.| <= ", tol_corr, ": 6 sigma of 1/sqrt(N))")
println("corr(neighbor particles, component 1) = ", corr_neighbor, "   (|.| <= ", tol_corr, ")")
for k in (2, 3, 4)
    println("P(|N| > ", k, ") = ", tails[k], "   (expected ", tail_expected[k], ", |. - expected| <= ",
            tol_tail(tail_expected[k]), ": 6 sigma of the binomial sd sqrt(p (1 - p)/N))")
end
println("reproducible same counter = ", repro_ok)
println("different rng_id separates stream = ", stream_sep)
println("different turn separates stream = ", turn_sep)

tails_ok = all(abs(tails[k] - tail_expected[k]) <= tol_tail(tail_expected[k]) for k in (2, 3, 4))
ok = abs(mean_normal) < tol_mean_normal &&
     abs(var_normal - 1) < tol_var_normal &&
     abs(mean_uniform - 0.5) < tol_mean_uniform &&
     abs(var_uniform - 1 / 12) < tol_var_uniform &&
     abs(corr_pair) < tol_corr &&
     abs(corr_neighbor) < tol_corr &&
     tails_ok &&
     repro_ok && stream_sep && turn_sep

if write_csv
    # result/, not the tracked validation/ tree (AGENTS.md output discipline;
    # 2026-08-05 audit, U19-8).
    out = joinpath(@__DIR__, "..", "result", "counter_rng_validation_summary.csv")
    mkpath(dirname(out))
    open(out, "w") do io
        println(io, "metric,value")
        println(io, "N,$N")
        println(io, "backend,$backend")
        println(io, "normal_mean,$mean_normal")
        println(io, "normal_variance,$var_normal")
        println(io, "uniform_mean,$mean_uniform")
        println(io, "uniform_variance,$var_uniform")
        println(io, "corr_pair,$corr_pair")
        println(io, "corr_neighbor,$corr_neighbor")
        println(io, "tail2,$tail2")
        println(io, "tail3,$tail3")
        println(io, "tail4,$tail4")
        println(io, "tails_passed,$tails_ok")
        println(io, "reproducible,$repro_ok")
        println(io, "stream_separated,$stream_sep")
        println(io, "turn_separated,$turn_sep")
        println(io, "passed,$ok")
    end
    println("wrote ", out)
end

ok || error("counter RNG validation failed")
println("counter RNG validation passed")
