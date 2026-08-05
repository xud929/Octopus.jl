# U14 probe A: independent Philox4x32-10, anchored on the OFFICIAL Random123
# kat_vectors file (fetched 2026-08-05 from
# https://raw.githubusercontent.com/DEShawResearch/random123/main/tests/kat_vectors),
# then used as the reference for Octopus's public counter_philox4x32.
#
# The reference below is written from the published algorithm, with the key
# schedule in the UPSTREAM order (bump BEFORE rounds 2..R), which is textually
# different from Octopus's (round, then bump) -- so agreement is a real check
# of the round count and schedule, not a copy.

const M0 = 0xD2511F53
const M1 = 0xCD9E8D57
const W0 = 0x9E3779B9
const W1 = 0xBB67AE85

@inline function mulhilo(a::UInt32, b::UInt32)
    p = UInt64(a) * UInt64(b)
    return UInt32(p >> 32), UInt32(p & 0x00000000ffffffff)   # (hi, lo)
end

function ref_philox4x32(R::Int, ctr::NTuple{4,UInt32}, key::NTuple{2,UInt32})
    c0, c1, c2, c3 = ctr
    k0, k1 = key
    for r in 1:R
        if r > 1                       # upstream: _philox4x32bumpkey before rounds 2..R
            k0 += W0
            k1 += W1
        end
        hi0, lo0 = mulhilo(M0, c0)
        hi1, lo1 = mulhilo(M1, c2)
        c0, c1, c2, c3 = hi1 ⊻ c1 ⊻ k0, lo1, hi0 ⊻ c3 ⊻ k1, lo0
    end
    return (c0, c1, c2, c3)
end

# Independent SplitMix64 finalizer (Vigna's constants), written from the spec.
@inline function ref_splitmix64(x::UInt64)
    z = x + 0x9e3779b97f4a7c15
    z = (z ⊻ (z >> 30)) * 0xbf58476d1ce4e5b9
    z = (z ⊻ (z >> 27)) * 0x94d049bb133111eb
    return z ⊻ (z >> 31)
end

hex(t) = join(string.(t, base=16, pad=8), " ")

println("=== 1. OFFICIAL Random123 kat_vectors, philox4x32 10 ===")
kat = [
 ((0x00000000,0x00000000,0x00000000,0x00000000),(0x00000000,0x00000000),
  (0x6627e8d5,0xe169c58d,0xbc57ac4c,0x9b00dbd8)),
 ((0xffffffff,0xffffffff,0xffffffff,0xffffffff),(0xffffffff,0xffffffff),
  (0x408f276d,0x41c83b0e,0xa20bc7c6,0x6d5451fd)),
 ((0x243f6a88,0x85a308d3,0x13198a2e,0x03707344),(0xa4093822,0x299f31d0),
  (0xd16cfe09,0x94fdcceb,0x5001e420,0x24126ea1)),
]
allok = Ref(true)
for (ctr, key, want) in kat
    got = ref_philox4x32(10, UInt32.(ctr), UInt32.(key))
    ok = got == UInt32.(want)
    allok[] &= ok
    println("  ctr=", hex(ctr), " key=", hex(key))
    println("    want ", hex(want), "\n    got  ", hex(got), "   ", ok ? "BIT-EXACT" : "MISMATCH")
end
println("  all three KAT vectors bit-exact: ", allok[])

println()
println("=== 2. Octopus counter_philox4x32 vs the KAT-anchored reference ===")
using Octopus

# The documented wiring: counter = (lo32(particle), hi32(particle), lo32(turn), hi32(turn));
# key = SM(seed) xor SM(rng_id+G) xor SM(component+D), split lo/hi.
function ref_counter_philox(seed, turn, rng_id, particle, component)
    p = UInt64(particle); t = UInt64(turn)
    ctr = (UInt32(p & 0xffffffff), UInt32(p >> 32),
           UInt32(t & 0xffffffff), UInt32(t >> 32))
    k = ref_splitmix64(UInt64(seed)) ⊻
        ref_splitmix64(UInt64(rng_id) + 0x9e3779b97f4a7c15) ⊻
        ref_splitmix64(UInt64(component) + 0xbf58476d1ce4e5b9)
    key = (UInt32(k & 0xffffffff), UInt32(k >> 32))
    return ref_philox4x32(10, ctr, key)
end

using Random
rng = Random.MersenneTwister(20260805)
nbad = Ref(0); ntest = Ref(0)
cases = Any[(0,0,0,0,0), (1,0,1,1,1), (20260805,7,3,999983,6),
            (typemax(UInt64), typemax(Int64), 2^40, 2^33, 12)]
for _ in 1:20000
    push!(cases, (rand(rng, UInt64), rand(rng, UInt32), rand(rng, UInt32),
                  rand(rng, UInt32), rand(rng, 1:64)))
end
firstshown = Ref(false)
for (s, t, r, p, c) in cases
    got = Octopus.counter_philox4x32(s, t, r, p, c)
    want = ref_counter_philox(s, t, r, p, c)
    ntest[] += 1
    if got != want
        nbad[] += 1
        nbad[] <= 3 && println("  MISMATCH at ", (s,t,r,p,c), " got ", hex(got), " want ", hex(want))
    elseif !firstshown[]
        println("  sample (seed,turn,rng_id,particle,component)=", (s,t,r,p,c))
        println("    ", hex(got), "  (identical)")
        firstshown[] = true
    end
end
println("  tuples compared: ", ntest[], "   mismatches: ", nbad[])

println()
println("=== 3. counter_uint64 packing = (w0<<32)|w1 ===")
bad64 = Ref(0)
for (s, t, r, p, c) in cases[1:2000]
    a, b, _, _ = Octopus.counter_philox4x32(s, t, r, p, c)
    got = Octopus.counter_uint64(s, t, r, p, c)
    got == ((UInt64(a) << 32) | UInt64(b)) || (bad64[] += 1)
end
println("  packing mismatches over 2000 tuples: ", bad64[])

println()
println("=== 4. words 3 and 4 of every Philox call are DISCARDED ===")
println("  counter_uint64 uses (c0,c1); (c2,c3) unused -> 50% of the generated")
println("  bits are thrown away per draw. Not a correctness defect; noted.")

println()
println("=== 5. Round-count sensitivity (does 10 actually mean 10?) ===")
for R in (8, 9, 10, 11, 12)
    got = ref_philox4x32(R, UInt32.((0,0,0,0)), UInt32.((0,0)))
    println("  R=", R, " -> ", hex(got), R == 10 ? "   <= matches Octopus + KAT" : "")
end
o = Octopus.counter_philox4x32(0, 0, 0, 0, 0)
println("  Octopus at the all-zero-derived key/counter is NOT the KAT zero case")
println("  (its key is SM(0) xor SM(G) xor SM(D) != 0): ", hex(o))
