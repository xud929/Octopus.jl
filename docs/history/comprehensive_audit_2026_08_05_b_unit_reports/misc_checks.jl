# U14 probe J: remaining region checks.
using Octopus, Printf
import CUDA

println("=== J1. U15-7 guard: is it on BOTH documented entry points? ===")
println("  Beam(N, policy, FloatT) has the AbstractFloat guard (Beam.jl:449).")
println("  Beam(N, backend, FloatT) (Beam.jl:457) is `where {RT<:Real}` with no guard.")
println("  The docstring lists CPUThreadsBackend / CUDABackend as accepted forms.")
for (ctor, label) in ((() -> Beam(4, CPUThreadsExecutionPolicy(), Rational{Int}), "policy   + Rational"),
                      (() -> Beam(4, CPUThreadsBackend, Rational{Int}),          "backend  + Rational"))
    try
        ctor()
        println("  ", label, " -> constructed (unexpected)")
    catch e
        m = sprint(showerror, e)
        println("  ", label, " -> ", typeof(e), ": ", first(replace(m, "\n" => " "), 150))
    end
end

println()
println("=== J2. contextless CUDA track! skips _reject_contextless_tracking ===")
println("  _reject_contextless_tracking is called from exactly one place:")
run(pipeline(`grep -rn "_reject_contextless_tracking" /cfs/ad/dxu/Library/Julia/Octopus/src`,
             stdout=stdout))
println("  -> the CPU contextless path only. The CUDA contextless path")
println("     (phase6d_track.jl track!(rep, elems, turns, ::ResolvedCUDAExecutionPolicy))")
println("     has no such guard, so the same line that is REFUSED on the CPU runs")
println("     silently on the GPU with an empty loss log.")
println("  _requires_tracking_context of an aperture-with-record line:")
try
    ap = compile_runtime(ApertureSpec(:rectangular; x_max=1e-3, y_max=1e-3,
                                      loss_record=LossRecord()))
    println("     _requires_tracking_context((ap,)) = ", Octopus._requires_tracking_context((ap,)))
    r = Phase6DRep(zeros(4), zeros(4), zeros(4), zeros(4), zeros(4), zeros(4))
    try
        Octopus.track!(r, (ap,), 2, Octopus.ResolvedCPUExecutionPolicy(1))
        println("     CPU contextless: ran (guard did NOT fire)")
    catch e
        println("     CPU contextless: REFUSED (", typeof(e), ") <- guard fired")
    end
    if CUDA.functional()
        rg = Phase6DRep((CUDA.zeros(Float64, 4) for _ in 1:6)...)
        pol = Octopus._resolve_execution_policy(CUDAExecutionPolicy(), rg)
        try
            Octopus._with_execution_policy(pol) do
                Octopus.track!(rg, (ap,), 2, pol)
            end
            CUDA.synchronize()
            println("     CUDA contextless: RAN with no refusal  <- guard missing")
        catch e
            println("     CUDA contextless: ", typeof(e), " ", first(sprint(showerror, e), 200))
        end
    end
catch e
    println("     (aperture construction differs: ", typeof(e), " ",
            first(sprint(showerror, e), 200), ")")
end

println()
println("=== J3. counter-RNG throw message really is static (no interpolation) ===")
try
    Octopus.octopus_uint64(1, UInt8(99), 2, 3, 4, 5)
    println("  no throw (regression!)")
catch e
    println("  ", typeof(e), ": ", e.msg)
    println("  contains the offending code value 99: ", occursin("99", e.msg))
end
println("  rng_method_symbol(0x63) message (host-only path, interpolation allowed):")
try
    Octopus.rng_method_symbol(UInt8(99))
catch e
    println("    ", e.msg)
end

println()
println("=== J4. splitmix method reaches the same consumers ===")
Octopus.set_global_rng!(seed=20260805, method=:splitmix)
println("  global method now ", Octopus.global_rng_method())
a = Octopus.octopus_normal(20260805, Octopus.RNG_SPLITMIX, 0, 1, 1, 1, Float64)
b = Octopus.octopus_normal(20260805, Octopus.RNG_PHILOX, 0, 1, 1, 1, Float64)
@printf("  splitmix %.17g   philox %.17g   different: %s\n", a, b, a != b)
Octopus.reset_rng_id_counter!(0)
bs = Beam(1000, CPUThreadsBackend, Float64; sigma=(1.0,1.0,1.0), rng_id=3)
Octopus.set_global_rng!(seed=20260805, method=:philox)
Octopus.reset_rng_id_counter!(0)
bp = Beam(1000, CPUThreadsBackend, Float64; sigma=(1.0,1.0,1.0), rng_id=3)
@printf("  Beam under :splitmix differs from :philox: %s\n", bs.rep.x != bp.rep.x)

println()
println("=== J5. Float32 counter RNG uses 24 source bits, Float64 52 ===")
for T in (Float32, Float64)
    vals = [Octopus.octopus_uniform01(20260805, Octopus.RNG_PHILOX, 0, 1, i, 1, T)
            for i in 1:200000]
    @printf("  %-8s min %.10g  max %.10g  strictly inside (0,1): %s\n",
            T, minimum(vals), maximum(vals), all(0 .< vals .< 1))
end
u_lo = Octopus._uniform_open01(UInt64(0), Float64)
u_hi = Octopus._uniform_open01(typemax(UInt64), Float64)
@printf("  extreme UInt64 inputs -> %.17g and %.17g (both in (0,1): %s)\n",
        u_lo, u_hi, 0 < u_lo && u_hi < 1)

println()
println("=== J6. Beam I/O append default and record indexing ===")
p = tempname()
r1 = Phase6DRep(fill(1.0, 3), fill(2.0, 3), fill(3.0, 3), fill(4.0, 3), fill(5.0, 3), fill(6.0, 3))
r2 = Phase6DRep(fill(9.0, 3), fill(8.0, 3), fill(7.0, 3), fill(6.0, 3), fill(5.0, 3), fill(4.0, 3))
write_beam_coordinates(p, r1)
write_beam_coordinates(p, r2)
println("  after two writes, read record=0 -> x = ", read_beam_coordinates(p; record=0).x)
println("                    read record=1 -> x = ", read_beam_coordinates(p; record=1).x)
try
    read_beam_coordinates(p; record=2)
catch e
    println("  read record=2 (past the end) -> ", typeof(e), " (loud)")
end
rm(p; force=true)
println("  npart larger than the rep silently clamps:")
p2 = tempname()
n = write_beam_coordinates(p2, r1; npart=99, append=false)
println("    requested npart=99, wrote n=", n, " (min with length); no warning")
rm(p2; force=true)
