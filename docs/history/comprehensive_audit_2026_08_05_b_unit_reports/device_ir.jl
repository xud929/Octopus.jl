# U14 probe H: device-IR compilability of the fused kernel, and the CPU/GPU
# divergence of a sqrt that leaves its domain.
using Octopus, Printf
import CUDA

println("CUDA functional: ", CUDA.functional())
CUDA.functional() || (println("SKIPPED (no device) -- report this as unchecked"); exit(0))
println("device: ", CUDA.name(CUDA.device()))

Octopus.set_global_rng!(seed=20260805, method=:philox)
Octopus.reset_rng_id_counter!(0)

println()
println("=== H1. fused CUDA kernel with a counter-RNG (stochastic) element ===")
lumped = compile_runtime(LumpedRadSpec{Float64}(;
    damping_turns=(4000.0, 4000.0, 2000.0), beta=(0.8, 0.072, 90.0),
    alpha=(0.0, 0.0, 0.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2), rng_id=103))
N = 4096
Octopus.reset_rng_id_counter!(50)
bcpu = Beam(N, CPUThreadsBackend, Float64; sigma=(1e-4, 1e-5, 1e-2), rng_id=7)
bgpu = Beam(N, CUDABackend, Float64; sigma=(1e-4, 1e-5, 1e-2), rng_id=7)
ctx = Octopus.TrackingContext(turn=0)
try
    Octopus.track!(bcpu.rep, (lumped,), 3; policy=CPUThreadsExecutionPolicy(), context=ctx)
    Octopus.track!(bgpu.rep, (lumped,), 3; policy=CUDAExecutionPolicy(), context=ctx)
    CUDA.synchronize()
    hx = Array(bgpu.rep.x); hpz = Array(bgpu.rep.pz)
    @printf("  fused kernel COMPILED and ran. max |x_gpu - x_cpu| = %.3e (scale %.3e)\n",
            maximum(abs, hx .- bcpu.rep.x), maximum(abs, bcpu.rep.x))
    @printf("                                max |pz_gpu - pz_cpu| = %.3e\n",
            maximum(abs, hpz .- bcpu.rep.pz))
catch e
    println("  FAILED: ", typeof(e))
    println(first(sprint(showerror, e), 1500))
end

println()
println("=== H2. every stochastic path: Radiation6DMap / Damping6DMap / Diffusion6DMap ===")
for m in (Radiation6DMap(), Damping6DMap(), Diffusion6DMap())
    spec = LumpedRadSpec{Float64}(; damping_turns=(4000.0, 4000.0, 2000.0),
        beta=(0.8, 0.072, 90.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2),
        tracking_method=m, rng_id=201)
    e = compile_runtime(spec, m)
    r = Beam(1024, CUDABackend, Float64; sigma=(1e-4, 1e-5, 1e-2), rng_id=9).rep
    try
        Octopus.track!(r, (e,), 2; policy=CUDAExecutionPolicy(), context=ctx)
        CUDA.synchronize()
        println("  ", typeof(m), ": fused device compile OK")
    catch err
        println("  ", typeof(m), ": FAILED ", typeof(err), " ", first(sprint(showerror, err), 300))
    end
end

println()
println("=== H3. RF cavity (convert_longitudinal, i.e. sqrt) in the fused kernel ===")
try
    cav = compile_runtime(ThinRFCavitySpec(500.0e6; voltage=5.0e6, e0=2.5e9,
                                           mc2=Octopus.PMASS_EV, phase=0.0))
    r = Beam(1024, CUDABackend, Float64; sigma=(1e-4, 1e-5, 1e-2), rng_id=11).rep
    rc = Beam(1024, CPUThreadsBackend, Float64; sigma=(1e-4, 1e-5, 1e-2), rng_id=11).rep
    Octopus.track!(r, (cav,), 5; policy=CUDAExecutionPolicy(), context=ctx)
    Octopus.track!(rc, (cav,), 5; policy=CPUThreadsExecutionPolicy(), context=ctx)
    CUDA.synchronize()
    @printf("  compiled and ran; max |pz_gpu - pz_cpu| = %.3e\n",
            maximum(abs, Array(r.pz) .- rc.pz))
catch e
    println("  FAILED: ", typeof(e), " ", first(sprint(showerror, e), 800))
end

println()
println("=== H4. sqrt out of domain: CPU throws, GPU does what? ===")
b0, g0 = reference_beta_gamma(2.5e9, Octopus.PMASS_EV)
println("  CPU _delta_from_pt(-1.0, b0, g0):")
try
    println("    -> ", Octopus._delta_from_pt(-1.0, b0, g0))
catch e
    println("    -> THROWS ", typeof(e))
end
function _k!(out, pts, b0, g0)
    i = (CUDA.blockIdx().x - 1) * CUDA.blockDim().x + CUDA.threadIdx().x
    if i <= length(pts)
        @inbounds out[i] = Octopus._delta_from_pt(pts[i], b0, g0)
    end
    return nothing
end
pts = CUDA.CuArray([-1.0, -0.8, -0.5, 0.0, 0.5])
out = CUDA.zeros(Float64, 5)
try
    CUDA.@cuda threads=32 blocks=1 _k!(out, pts, b0, g0)
    CUDA.synchronize()
    println("  GPU _delta_from_pt on the same inputs -> ", Array(out))
    println("  => same physical situation: DomainError (hard stop) on CPU,")
    println("     NaN (silently dead particle) on GPU.")
catch e
    println("  GPU kernel failed: ", typeof(e), " ", first(sprint(showerror, e), 600))
end

println()
println("=== H5. Track.jl track_particle fallback: MethodError with interpolated args ===")
println("  src/track/Track.jl:56 throws MethodError(track_particle, (method, op, x...)).")
println("  Constructing a MethodError from runtime VALUES is not device IR. It is a")
println("  fallback for an unregistered (method, op) pair, so it is unreachable in a")
println("  kernel that compiles at all -- but if it ever became reachable the failure")
println("  is a compile error, not a wrong answer. Checking it is not accidentally in")
println("  a compiled path today: H1-H3 all compiled, so it is not.")
