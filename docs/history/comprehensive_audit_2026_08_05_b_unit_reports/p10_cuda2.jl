using Octopus, CUDA
const O = Octopus
N = 64
cz() = CUDA.zeros(Float64, N)

function gputry(line, x0=1.0e-3; turns=1)
    tc = TrackingTask(line); rc = Phase6DRep(fill(x0,N), zeros(N), zeros(N), zeros(N), zeros(N), zeros(N))
    execute!(tc, rc; turns=turns)
    tg = TrackingTask(line)
    rg = Phase6DRep(CUDA.CuArray(fill(x0,N)), cz(), cz(), cz(), cz(), cz())
    try
        execute!(tg, rg; turns=turns)
        d = maximum(abs, rc.x .- Array(rg.x))
        return "OK  max|cpu-gpu| = $(d)  bit-identical = $(all(rc.x .== Array(rg.x)))"
    catch e
        return "FAILS: " * first(replace(sprint(showerror, e), "\n" => " | "), 150)
    end
end

println("== j1. which composite lines compile for CUDA ==")
q1 = QuadrupoleSpec(L=0.4, k1=1.0, nst=2)
q2 = QuadrupoleSpec(L=0.6, k1=-1.0, nst=2)
d  = DriftSpec(L=1.0)
cases = [
 "girder, 1 magnet"          => BeamLine("G1", q1; x_offset=2e-4),
 "girder, 2 SAME-type quads" => BeamLine("G2", q1, q2; x_offset=2e-4),
 "girder, quad + drift"      => BeamLine("G3", q1, d; x_offset=2e-4),
 "girder, 3 quads"           => BeamLine("G4", q1, q2, q1; x_offset=2e-4),
 "dissolving line (control)" => BeamLine("G5", q1, d),
]
for (lbl, ln) in cases
    println("  ", rpad(lbl, 28), gputry(BeamLine("W", ln, DriftSpec(L=0.1))))
end

println()
println("== j2. isolate the CPU/GPU last-bit difference ==")
set_global_rng!(seed=13579)
rad = LumpedRadSpec{Float64}(damping_turns=(1.0e4,1.0e4,1.0e4),
                             sigma=(1.0e-3,1.0e-3,1.0e-3), rng_id=555)
println("  radiation only        ", gputry(BeamLine("RO", rad), 0.0; turns=3))
println("  drift only            ", gputry(BeamLine("DO", DriftSpec(L=1.0)), 1.0e-3; turns=3))
println("  quad only             ", gputry(BeamLine("QO", q1), 1.0e-3; turns=3))
println("  radiation + drift     ", gputry(BeamLine("RD", rad, DriftSpec(L=1.0)), 0.0; turns=3))
println("done")
