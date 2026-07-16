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

The checks are intentionally lightweight. They verify reproducibility and basic
standard-normal statistics; they are not a full statistical test suite.
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

repro_ok = normal_value(seed, turn, rng_id, 123, 4, Float64) ==
           normal_value(seed, turn, rng_id, 123, 4, Float64)
stream_sep = normal_value(seed, turn, rng_id, 123, 4, Float64) !=
             normal_value(seed, turn, rng_id + 1, 123, 4, Float64)
turn_sep = normal_value(seed, turn, rng_id, 123, 4, Float64) !=
           normal_value(seed, turn + 1, rng_id, 123, 4, Float64)

println("Counter RNG validation")
println("N = ", N)
println("seed = ", seed)
println("turn = ", turn)
println("rng_id = ", rng_id)
println("backend = ", backend)
println("normal mean = ", mean_normal)
println("normal variance = ", var_normal)
println("uniform mean = ", mean_uniform)
println("uniform variance = ", var_uniform)
println("corr(normal component 1, component 2) = ", corr_pair)
println("corr(neighbor particles, component 1) = ", corr_neighbor)
println("P(|N| > 2) = ", tail2, " expected about 0.0455003")
println("P(|N| > 3) = ", tail3, " expected about 0.0026998")
println("P(|N| > 4) = ", tail4, " expected about 6.334e-5")
println("reproducible same counter = ", repro_ok)
println("different rng_id separates stream = ", stream_sep)
println("different turn separates stream = ", turn_sep)

ok = abs(mean_normal) < 5e-3 &&
     abs(var_normal - 1) < 1e-2 &&
     abs(mean_uniform - 0.5) < 5e-3 &&
     abs(var_uniform - 1 / 12) < 5e-3 &&
     abs(corr_pair) < 5e-3 &&
     abs(corr_neighbor) < 5e-3 &&
     repro_ok && stream_sep && turn_sep

if write_csv
    out = joinpath(@__DIR__, "counter_rng_validation_summary.csv")
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
        println(io, "reproducible,$repro_ok")
        println(io, "stream_separated,$stream_sep")
        println(io, "turn_separated,$turn_sep")
        println(io, "passed,$ok")
    end
    println("wrote ", out)
end

ok || error("counter RNG validation failed")
println("counter RNG validation passed")
