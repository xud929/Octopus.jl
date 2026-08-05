# U14 probe B: counter/stream structure.
#   B1 injectivity of the (turn, particle) counter and the (seed,rng_id,component) key
#   B2 measured independence: turn / particle / component / rng_id axes
#   B3 the CONSUMER lattice: do beam init, radiation, and BPM noise ever
#      land on the same (seed, turn, rng_id, particle, component)?
using Octopus, Statistics, Printf

S = UInt64(20260805)
M = Octopus.RNG_PHILOX
n(t, r, p, c) = Octopus.octopus_normal(S, M, t, r, p, c, Float64)
u(t, r, p, c) = Octopus.octopus_uint64(S, M, t, r, p, c)

println("=== B1. counter/key injectivity over the reachable id ranges ===")
# 128-bit counter = (particle, turn); key = f(seed, rng_id, component).
keys = Set{UInt64}()
dup = Ref(0)
for r in 0:4000, c in 1:8
    k = Octopus._counter_rng_splitmix64(UInt64(S)) ⊻
        Octopus._counter_rng_splitmix64(UInt64(r) + 0x9e3779b97f4a7c15) ⊻
        Octopus._counter_rng_splitmix64(UInt64(c) + 0xbf58476d1ce4e5b9)
    k in keys && (dup[] += 1)
    push!(keys, k)
end
@printf("  distinct keys over rng_id 0:4000 x component 1:8 = %d of %d ; duplicates %d\n",
        length(keys), 4001*8, dup[])

# full-tuple distinctness of the actual 64-bit outputs on a dense sub-lattice
vals = Set{UInt64}()
tot = Ref(0)
for t in 0:19, r in 1:10, p in 1:40, c in 1:6
    push!(vals, u(t, r, p, c)); tot[] += 1
end
@printf("  distinct octopus_uint64 over 20 turns x 10 ids x 40 particles x 6 comps = %d of %d\n",
        length(vals), tot[])

println()
println("=== B2. measured independence (Pearson r over N draws; SE = 1/sqrt(N)) ===")
N = 1_000_000
function corr(f, g)
    a = Vector{Float64}(undef, N); b = Vector{Float64}(undef, N)
    @inbounds for i in 1:N
        a[i] = f(i); b[i] = g(i)
    end
    return cor(a, b), mean(a), var(a)
end
@printf("  %-58s %12s %10s %10s\n", "axis (stream A vs stream B)", "corr", "meanA", "varA")
tests = [
 ("adjacent particles      (t=0,r=1,c=1): p=i   vs p=i+1",
   i->n(0,1,i,1),        i->n(0,1,i+1,1)),
 ("adjacent turns          (r=1,c=1,p=i):  t=0   vs t=1",
   i->n(0,1,i,1),        i->n(1,1,i,1)),
 ("far turns               (r=1,c=1,p=i):  t=0   vs t=10^9",
   i->n(0,1,i,1),        i->n(1_000_000_000,1,i,1)),
 ("adjacent elements/ids   (t=0,c=1,p=i):  r=1   vs r=2",
   i->n(0,1,i,1),        i->n(0,2,i,1)),
 ("radiation vs BPM stream (t=3,p=i):      r=7,c=1 vs r=8,c=1",
   i->n(3,7,i,1),        i->n(3,8,i,1)),
 ("different components, DIFFERENT pair    c=1   vs c=3",
   i->n(0,1,i,1),        i->n(0,1,i,3)),
 ("SAME Box-Muller pair                    c=1   vs c=2",
   i->n(0,1,i,1),        i->n(0,1,i,2)),
 ("beam-init stream vs first-turn radiation, DISTINCT ids (r=1 vs r=2)",
   i->n(0,1,i,1),        i->n(0,2,i,1)),
]
for (label, f, g) in tests
    c, m, v = corr(f, g)
    @printf("  %-58s %12.3e %10.3e %10.6f\n", label, c, m, v)
end

println()
println("  Cross-axis SQUARED correlation (catches sign-blind dependence):")
for (label, f, g) in tests[1:6]
    a = [f(i)^2 for i in 1:N]; b = [g(i)^2 for i in 1:N]
    @printf("  %-58s %12.3e\n", label, cor(a, b))
end

println()
println("=== B3. the CONSUMER lattice: same tuple from two different consumers? ===")
println("  Consumers and the tuple each one draws (grepped from src/):")
println("    Beam init            (seed, turn=0,      rng_id_beam, particle=i,      component=1..6)")
println("    LumpedRad excitation (ctx.seed, ctx.turn, elem.rng_id, particle_id,     component=1..6)")
println("    BPMObserver noise    (ctx.seed, ctx.turn, bpm.rng_id,  occurrence,      component=1,2)")
println("  -> ONE namespace. Auto-assigned ids come from the single atomic")
println("     next_rng_id!, so the default path never collides. Explicit ids do")
println("     not consult it. Measured collision when they coincide:")
same = Ref(true)
for i in 1:5, c in 1:6
    beam_draw = Octopus.octopus_normal(S, M, 0, 1, i, c, Float64)   # Beam(rng_id=1), turn 0
    rad_draw  = Octopus.octopus_normal(S, M, 0, 1, i, c, Float64)   # LumpedRad(rng_id=1), ctx.turn=0
    same[] &= (beam_draw === rad_draw)
end
println("    Beam(rng_id=1) init draw === LumpedRad(rng_id=1) first-turn draw, bitwise: ", same[])
b1 = Octopus.octopus_normal(S, M, 0, 1, 1, 1, Float64)
@printf("    both are exactly %.17g\n", b1)
println("    (first tracked turn is ctx.turn = 0: track! uses ctx.turn + (turn-1))")

println()
println("  Does any SHIPPED configuration collide? auto-assigned ids in one session:")
Octopus.reset_rng_id_counter!(0)
ids = [Octopus.next_rng_id!() for _ in 1:5]
println("    next_rng_id! sequence: ", ids, "   (unique: ", length(unique(ids)) == 5, ")")
println("    reset_rng_id_counter! is PUBLIC and re-issues ids already handed out:")
Octopus.reset_rng_id_counter!(0)
println("    after reset, next_rng_id! -> ", Octopus.next_rng_id!(), " (already issued above)")

println()
println("=== B4. next_rng_id! under threads (U15-5 atomic fix) ===")
println("  Threads.nthreads() = ", Threads.nthreads())
Octopus.reset_rng_id_counter!(0)
K = 20000
out = Vector{UInt64}(undef, K)
Threads.@threads for i in 1:K
    out[i] = Octopus.next_rng_id!()
end
@printf("  %d concurrent next_rng_id!: %d distinct, min %d max %d  -> %s\n",
        K, length(unique(out)), minimum(out), maximum(out),
        length(unique(out)) == K ? "NO duplicate stream ids" : "DUPLICATES")
