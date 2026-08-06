# AUDITOR VERIFICATION of U14-2: an explicit rng_id never advances the
# auto-assign counter, so a beam and an auto-assigned stochastic element can
# silently share one counter-RNG stream.
using Octopus
O = Octopus
O.reset_rng_id_counter!(0)
set_global_rng!(seed = 20260805, method = :philox)

println("counter after reset            = ", O._GLOBAL_RNG_ID_COUNTER[])
b = Beam(8, CPUThreadsBackend; beta=(1.0,1.0,1.0), alpha=(0.0,0.0,0.0),
         sigma=(1e-3,1e-3,1e-3), rng_id = 1)          # EXPLICIT id 1
println("after Beam(rng_id=1), counter  = ", O._GLOBAL_RNG_ID_COUNTER[])
rad = LumpedRadSpec{Float64}(; damping_turns=(1e12,1e12,1e12), beta=(1.0,1.0,1.0),
                              alpha=(0.0,0.0,0.0), sigma=(1e-3,1e-3,1e-3),
                              is_damping=false)        # rng_id defaults to 0 => AUTO
e = O.compile_runtime(rad)
println("auto-assigned radiation id     = ", e.rng_id, "   <- collides with the beam if 1")

# Do they actually draw the same numbers?
rep = Phase6DRep(zeros(8), zeros(8), zeros(8), zeros(8), zeros(8), zeros(8))
track!(rep, (e,), 1; policy = CPUThreadsExecutionPolicy())
beam_x = Array(b.rep.x); rad_x = Array(rep.x)
println("beam x[1:3]      = ", round.(beam_x[1:3], sigdigits=8))
println("radiation x[1:3] = ", round.(rad_x[1:3] ./ 1.0e-3, sigdigits=8), "  (scaled by sigma)")
println("bitwise identical draws? ", beam_x ≈ rad_x ./ 1.0e-3 * 1.0e-3 || isapprox(beam_x, rad_x; rtol=1e-12),
        "   corr = ", round(sum(beam_x .* rad_x)/sqrt(sum(beam_x.^2)*sum(rad_x.^2)), sigdigits=8))
