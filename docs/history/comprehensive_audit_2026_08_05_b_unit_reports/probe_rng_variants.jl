# U25 probe (hypothesis e): does validation/counter_rng_validation.jl's `ok` gate
# detect an implementation change in the generator?  Replicates the script's EIGHT
# acceptance criteria verbatim, but feeds them a deliberately WRONG Philox:
# 3 rounds instead of 10 and no Weyl key bump.  If `ok` is still true, the gate
# is a statistics test, not a generator test.
using Statistics
const NR = parse(Int, get(ENV,"NR","10"))
const BUMP = get(ENV,"BUMP","1")=="1"

const M0 = UInt32(0xD2511F53)
const M1 = UInt32(0xCD9E8D57)
const TWO_NEG_52 = 2.220446049250313e-16
const TWO_PI = 6.283185307179586476925286766559

lo32(x::UInt64) = UInt32(x & 0xffffffff)
hi32(x::UInt64) = UInt32((x >> 32) & 0xffffffff)
function sm64(x::UInt64)
    x += 0x9e3779b97f4a7c15
    x = (x ⊻ (x >> 30)) * 0xbf58476d1ce4e5b9
    x = (x ⊻ (x >> 27)) * 0x94d049bb133111eb
    return x ⊻ (x >> 31)
end
function mulhilo(a::UInt32, b::UInt32)
    p = UInt64(a) * UInt64(b)
    return hi32(p), lo32(p)
end
function round1(c0, c1, c2, c3, k0, k1)
    hi0, lo0 = mulhilo(M0, c0)
    hi1, lo1 = mulhilo(M1, c2)
    return hi1 ⊻ c1 ⊻ k0, lo1, hi0 ⊻ c3 ⊻ k1, lo0
end
# BROKEN: 3 rounds, key bump removed.
function broken_philox(seed, turn, rng_id, particle, component)
    p = UInt64(particle); t = UInt64(turn)
    c0, c1, c2, c3 = lo32(p), hi32(p), lo32(t), hi32(t)
    key = sm64(UInt64(seed)) ⊻ sm64(UInt64(rng_id) + 0x9e3779b97f4a7c15) ⊻
          sm64(UInt64(component) + 0xbf58476d1ce4e5b9)
    k0, k1 = lo32(key), hi32(key)
    for _ in 1:NR
        c0, c1, c2, c3 = round1(c0, c1, c2, c3, k0, k1)
        if BUMP; k0 += UInt32(0x9E3779B9); k1 += UInt32(0xBB67AE85); end
    end
    return c0, c1, c2, c3
end
function broken_u64(seed, turn, rng_id, particle, component)
    a, b, _, _ = broken_philox(seed, turn, rng_id, particle, component)
    return (UInt64(a) << 32) | UInt64(b)
end
broken_uniform(seed, turn, rng_id, particle, component) =
    (Float64(broken_u64(seed, turn, rng_id, particle, component) >> 12) + 0.5) * TWO_NEG_52
function broken_normal(seed, turn, rng_id, particle, pair_id)
    u1 = broken_uniform(seed, turn, rng_id, particle, 2 * pair_id - 1)
    u2 = broken_uniform(seed, turn, rng_id, particle, 2 * pair_id)
    r = sqrt(-2 * log(u1)); th = TWO_PI * u2
    return r * cos(th)
end

N = 1_000_000; seed = 123456789; turn = 7; rng_id = 11
samples  = [broken_normal(seed, turn, rng_id, i, 1) for i in 1:N]
samples2 = [broken_normal(seed, turn, rng_id, i, 2) for i in 1:N]
uniforms = [broken_uniform(seed, turn, rng_id, i, 1) for i in 1:N]

mean_normal = mean(samples); var_normal = var(samples; corrected=true)
mean_uniform = mean(uniforms); var_uniform = var(uniforms; corrected=true)
corr_pair = cor(samples, samples2)
corr_neighbor = cor(samples[1:end-1], samples[2:end])
repro_ok  = broken_normal(seed, turn, rng_id, 123, 4) == broken_normal(seed, turn, rng_id, 123, 4)
stream_sep = broken_normal(seed, turn, rng_id, 123, 4) != broken_normal(seed, turn, rng_id + 1, 123, 4)
turn_sep   = broken_normal(seed, turn, rng_id, 123, 4) != broken_normal(seed, turn + 1, rng_id, 123, 4)

ok = abs(mean_normal) < 5e-3 && abs(var_normal - 1) < 1e-2 &&
     abs(mean_uniform - 0.5) < 5e-3 && abs(var_uniform - 1/12) < 5e-3 &&
     abs(corr_pair) < 5e-3 && abs(corr_neighbor) < 5e-3 &&
     repro_ok && stream_sep && turn_sep

println("Philox variant: rounds=", NR, " weyl_bump=", BUMP)
println("  normal mean      = ", mean_normal)
println("  normal variance  = ", var_normal)
println("  uniform mean     = ", mean_uniform)
println("  uniform variance = ", var_uniform)
println("  corr_pair        = ", corr_pair)
println("  corr_neighbor    = ", corr_neighbor)
println("  repro/stream/turn= ", (repro_ok, stream_sep, turn_sep))
println("SCRIPT GATE `ok` ON THE BROKEN GENERATOR = ", ok)
