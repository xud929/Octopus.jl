# U25 probe: are counter_rng_validation.jl's FIXED absolute thresholds safe at the
# smaller N the README itself suggests?  The gate uses |mean|<5e-3, |corr|<5e-3
# regardless of N, while the sampling error of each is ~1/sqrt(N).
# Runs the script's exact statistics over many seeds at several N and counts how
# often a HEALTHY generator would trip the gate.
if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "runroot", "src", "Octopus.jl"))
end
using .Octopus
using Statistics
using Printf

function gate(normal_value, uniform_value, N, seed, turn, rng_id)
    s1 = Vector{Float64}(undef, N); s2 = similar(s1); u = similar(s1)
    for i in 1:N
        s1[i] = normal_value(seed, turn, rng_id, i, 1, Float64)
        s2[i] = normal_value(seed, turn, rng_id, i, 2, Float64)
        u[i]  = uniform_value(seed, turn, rng_id, i, 1, Float64)
    end
    mn = mean(s1); vn = var(s1; corrected=true)
    mu = mean(u);  vu = var(u; corrected=true)
    cp = cor(s1, s2); cn = cor(s1[1:end-1], s1[2:end])
    ok = abs(mn) < 5e-3 && abs(vn - 1) < 1e-2 && abs(mu - 0.5) < 5e-3 &&
         abs(vu - 1/12) < 5e-3 && abs(cp) < 5e-3 && abs(cn) < 5e-3
    return ok, (mn, vn, mu, vu, cp, cn)
end

for (name, nv, uv) in (("philox", counter_normal, counter_uniform01),
                       ("splitmix", splitmix_normal, splitmix_uniform01))
    for N in (1_000_000, 200_000, 100_000)
        fails = 0; worst = ""
        for seed in UInt64.(1:12)
            ok, m = gate(nv, uv, N, seed, 7, 11)
            ok || (fails += 1)
            ok || (worst = @sprintf("seed=%d mean=%.4g var=%.4g umean=%.4g uvar=%.4g cp=%.4g cn=%.4g",
                                    seed, m...))
        end
        @printf("%-9s N=%-8d healthy-generator gate failures: %d/12   %s\n", name, N, fails, worst)
    end
end
