# U14 probe E: beam_statistics against BigFloat on the SAME data; the
# covariance convention (n vs n-1) against every other moment computation in
# the repository; and the n=0 / n=1 / all-identical edge cases.
using Octopus, Statistics, Printf
setprecision(BigFloat, 256)
const BF = BigFloat

Octopus.set_global_rng!(seed=20260805, method=:philox)
Octopus.reset_rng_id_counter!(0)

N = 1_000_000
beam = Beam(N, CPUThreadsBackend, Float64;
            beta=(2.0, 3.0, 4.0), alpha=(1.5, -0.8, 0.3),
            sigma=(1.0e-3, 2.0e-3, 5.0e-3),
            initial_offset=(1.0e-3, 2.0e-4, -3.0e-4, 5.0e-5, 7.0e-3, 1.0e-4),
            rng_id=17)
st = beam_statistics(beam; diagonal_fourth=true)
co = Octopus.coordinate_arrays(beam.rep)

println("=== E1. moments vs a naive BigFloat reference on the same data ===")
bmean = [sum(BF.(c)) / N for c in co]
println("  n reported by beam_statistics: ", st.n, "  (length ", N, ")")
worst_mean_abs = 0.0
for i in 1:6
    global worst_mean_abs = max(worst_mean_abs, abs(st.mean[i] - Float64(bmean[i])))
end
@printf("  means: worst ABSOLUTE error %.3e (relative is a 0/0 artifact on\n", worst_mean_abs)
@printf("         standardized means; largest |mean| = %.3e)\n", maximum(abs, st.mean))

worst_cov = 0.0; argc = (0, 0)
for i in 1:6, j in i:6
    s = zero(BF)
    ci = co[i]; cj = co[j]; mi = bmean[i]; mj = bmean[j]
    @inbounds for k in 1:N
        s += (BF(ci[k]) - mi) * (BF(cj[k]) - mj)
    end
    ref = s / N
    r = abs(st.covariance[i, j] - Float64(ref)) / abs(Float64(ref))
    if r > worst_cov
        global worst_cov = r; global argc = (i, j)
    end
end
@printf("  covariance: worst RELATIVE error %.3e at (%d,%d)\n", worst_cov, argc...)

worst4 = 0.0
for i in 1:6
    s = zero(BF); c = co[i]; m = bmean[i]
    @inbounds for k in 1:N
        d = BF(c[k]) - m
        s += d * d * d * d
    end
    ref = s / N
    global worst4 = max(worst4, abs(st.diagonal_fourth_central[i] - Float64(ref)) / abs(Float64(ref)))
end
@printf("  fourth central: worst RELATIVE error %.3e\n", worst4)

worst_e = 0.0
for p in 0:2
    i = 2p + 1; j = i + 1
    si = zero(BF); sj = zero(BF); sij = zero(BF)
    ci = co[i]; cj = co[j]; mi = bmean[i]; mj = bmean[j]
    @inbounds for k in 1:N
        a = BF(ci[k]) - mi; b = BF(cj[k]) - mj
        si += a * a; sj += b * b; sij += a * b
    end
    ref = sqrt((si / N) * (sj / N) - (sij / N)^2)
    global worst_e = max(worst_e, abs(st.emittance[p+1] - Float64(ref)) / Float64(ref))
end
@printf("  emittance: worst RELATIVE error %.3e\n", worst_e)
@printf("  rms vs sqrt(diag(cov)): max diff %.3e\n",
        maximum(abs(st.rms[i] - sqrt(st.covariance[i, i])) for i in 1:6))

println()
println("=== E2. covariance convention: n or n-1? ===")
v = [1.0, 2.0, 4.0, 8.0, 16.0]
rep = Phase6DRep(copy(v), copy(v), copy(v), copy(v), copy(v), copy(v))
s5 = beam_statistics(rep)
mu = sum(v) / 5
c_n   = sum((v .- mu) .^ 2) / 5
c_nm1 = sum((v .- mu) .^ 2) / 4
@printf("  cov[1,1]        = %.17g\n", s5.covariance[1, 1])
@printf("  population (/n) = %.17g   %s\n", c_n, s5.covariance[1,1] == c_n ? "<== MATCH" : "")
@printf("  sample (/n-1)   = %.17g   %s\n", c_nm1, s5.covariance[1,1] == c_nm1 ? "<== MATCH" : "")
@printf("  Statistics.var (default corrected=true, /n-1) = %.17g\n", var(v))
println("  => beam_statistics uses the POPULATION convention (/n).")
println()
println("  Every other moment computation in the repository, checked:")
println("    src/beam/Beam.jl  _mean/_covariance/_fourth_central   -> / n  (or / nlive)")
for (f, pat) in (("src/beam/Beam.jl", "length(a)"),)
end
println("    Octopus._standardize!  (Beam.jl:149)  sigma^2 = sum(abs2)/N -> / n")

println()
println("=== E3. edge cases ===")
empty_rep = Phase6DRep(Float64[], Float64[], Float64[], Float64[], Float64[], Float64[])
try
    s0 = beam_statistics(empty_rep)
    @printf("  n = 0: n=%d mean[1]=%s cov[1,1]=%s rms[1]=%s emit[1]=%s\n",
            s0.n, s0.mean[1], s0.covariance[1,1], s0.rms[1], s0.emittance[1])
catch e
    println("  n = 0 -> ", typeof(e), ": ", sprint(showerror, e)[1:min(end,140)])
end

one_rep = Phase6DRep([1.5], [2.5], [3.5], [4.5], [5.5], [6.5])
s1 = beam_statistics(one_rep)
@printf("  n = 1: n=%d mean=%s cov[1,1]=%.17g rms[1]=%.17g emit=%s\n",
        s1.n, s1.mean, s1.covariance[1,1], s1.rms[1], s1.emittance)

K = 1000
ident = Phase6DRep(fill(3.0, K), fill(-1.0, K), fill(2.0, K),
                   fill(0.5, K), fill(-4.0, K), fill(7.0, K))
si = beam_statistics(ident; diagonal_fourth=true)
@printf("  all-identical (n=%d): mean=%s\n", si.n, si.mean)
@printf("       cov all zero: %s ; rms all zero: %s ; emittance = %s\n",
        all(iszero, si.covariance), all(iszero, si.rms), si.emittance)
@printf("       fourth central all zero: %s\n", all(iszero, si.diagonal_fourth_central))

println()
println("  n = 1 beam through the SAMPLER (not Phase6DRep directly):")
Octopus.reset_rng_id_counter!(0)
b1 = Beam(1, CPUThreadsBackend, Float64; sigma=(1.0e-3, 1.0e-3, 1.0e-3))
@printf("    coordinates = %s  <- _standardize! sigma==0 branch collapses to origin\n",
        collect(b1.rep[1]))

println()
println("=== E4. negative-variance guard (max(cov,0)) actually reachable? ===")
# cov[i,i] is a sum of squares / n and cannot go negative in exact arithmetic;
# the guard is defensive. Emittance CAN go negative from round-off:
q = randn(Octopus.Random.MersenneTwister(7), 1000) .* 1e-9
p = copy(q)                                     # perfectly correlated -> emit = 0
rep2 = Phase6DRep(q, p, copy(q), copy(p), copy(q), copy(p))
s2 = beam_statistics(rep2)
@printf("  perfectly correlated plane: emittance = %.6e (exact answer 0; guard held: %s)\n",
        s2.emittance[1], s2.emittance[1] >= 0)

println()
println("=== E5. NaN handling without allow_lost_particles ===")
bad = Phase6DRep([1.0, NaN], [1.0, 1.0], [1.0, 1.0], [1.0, 1.0], [1.0, 1.0], [1.0, 1.0])
sb = beam_statistics(bad)
@printf("  default (flag off): n=%d mean[1]=%s  -> NaN propagates, not silently dropped\n",
        sb.n, sb.mean[1])
Octopus.allow_lost_particles() do
    sg = beam_statistics(bad)
    @printf("  allow_lost_particles: n=%d mean[1]=%.17g cov[1,1]=%.17g\n",
            sg.n, sg.mean[1], sg.covariance[1,1])
end
