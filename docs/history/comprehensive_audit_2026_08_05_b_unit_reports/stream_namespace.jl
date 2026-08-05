# U14 probe B2: the rng_id NAMESPACE is shared by three consumer classes, but
# explicit ids never advance the atomic counter that auto ids draw from.
# Reproduce the collision that follows.
using Octopus, Statistics, Printf

Octopus.set_global_rng!(seed=20260805, method=:philox)

println("=== C1. explicit ids do not reserve themselves in the auto counter ===")
Octopus.reset_rng_id_counter!(0)          # fresh session
N = 20000
beam = Beam(N, CPUThreadsBackend, Float64; sigma=(1.0,1.0,1.0), rng_id=1)  # EXPLICIT id 1
radspec = LumpedRadSpec{Float64}(; damping_turns=(1000.0,1000.0,1000.0),
                                   sigma=(1.0,1.0,1.0))                    # AUTO id
rad_id = Octopus.getparam(radspec, :rng_id, 0)
println("  Beam given explicit rng_id = 1")
println("  LumpedRadSpec auto-assigned rng_id = ", rad_id,
        rad_id == 1 ? "   <-- SAME STREAM as the beam" : "")

println()
println("=== C2. consequence, measured ===")
S = Octopus.global_rng_seed(); M = Octopus.global_rng_method_code()
# raw beam draws (before _standardize! and the Twiss scaling)
raw = [Octopus.octopus_normal(S, M, 0, 1, i, 1, Float64) for i in 1:N]
# first-turn radiation excitation draw for the same particles, component 1
radn = [Octopus.octopus_normal(S, M, 0, UInt64(rad_id), i, 1, Float64) for i in 1:N]
@printf("  corr(beam raw x-draw, first-turn radiation nx) = %.6f\n", cor(raw, radn))
@printf("  bitwise identical for all %d particles: %s\n", N, all(raw .== radn))
println("  and against the FINAL beam coordinates (standardized + scaled):")
@printf("  corr(beam.rep.x, first-turn radiation nx) = %.6f\n", cor(Array(beam.rep.x), radn))

println()
println("=== C3. same trap for BPMObserver ===")
Octopus.reset_rng_id_counter!(0)
b2 = Beam(1000, CPUThreadsBackend, Float64; sigma=(1.0,1.0,1.0), rng_id=1)
bpm = BPMObserver("m1"; x_noise=1.0e-5)
println("  Beam explicit rng_id=1 ; BPMObserver auto rng_id = ", bpm.rng_id,
        bpm.rng_id == 1 ? "   <-- SAME STREAM" : "")

println()
println("=== C4. what the repository DOES check ===")
println("  Tasks._warn_duplicate_radiation_streams covers radiation-vs-radiation")
println("  placements inside one line only. Demonstration that it fires there:")
r1 = LumpedRadSpec{Float64}(; damping_turns=(1000.0,1000.0,1000.0), sigma=(1.0,1.0,1.0), rng_id=0x77)
try
    TrackingTask(BeamLine(:l, (r1, r1)); turns=1)
    println("  (constructed; look for the @warn above)")
catch e
    println("  construction path differs: ", typeof(e))
end
println("  No equivalent check exists across beam / radiation / BPM ids.")

println()
println("=== C5. what a disjointness tripwire would cost: nothing ===")
Octopus.reset_rng_id_counter!(0)
b3 = Beam(100, CPUThreadsBackend, Float64; sigma=(1.0,1.0,1.0))   # AUTO
r3 = LumpedRadSpec{Float64}(; damping_turns=(1000.0,1000.0,1000.0), sigma=(1.0,1.0,1.0))
p3 = BPMObserver("m2"; x_noise=1.0e-5)
println("  all-auto session ids: beam=1(implicit) rad=", Octopus.getparam(r3,:rng_id,0),
        " bpm=", p3.rng_id, "  -> disjoint by construction")
