# U14 probe I: the CONTEXTLESS CUDA track! (phase6d_track.jl) constructs a
# FRESH TrackingContext() inside its own turn loop, so every turn draws at
# turn = 0.  Measure: is the stochastic excitation identical on every turn?
using Octopus, Statistics, Printf
import CUDA

Octopus.set_global_rng!(seed=20260805, method=:philox)
println("CUDA functional: ", CUDA.functional())

spec = LumpedRadSpec{Float64}(; damping_turns=(1000.0, 1000.0, 1000.0),
                                beta=(1.0, 1.0, 1.0), sigma=(1.0, 1.0, 1.0),
                                is_damping=false, is_excitation=true, rng_id=777)
elem = compile_runtime(spec)
@printf("excitation coefficients: %s\n", string(elem.excitation))

N = 20000
TURNS = 16

function zero_rep(N)
    Phase6DRep(zeros(N), zeros(N), zeros(N), zeros(N), zeros(N), zeros(N))
end

println()
println("=== I1. CPU, WITH context (the supported path) ===")
r = zero_rep(N)
Octopus.track!(r, (elem,), TURNS; policy=CPUThreadsExecutionPolicy(),
               context=Octopus.TrackingContext(turn=0))
vc = var(r.x)
@printf("  var(x) after %d turns = %.6f   (random walk predicts %d * exc^2 = %.6f)\n",
        TURNS, vc, TURNS, TURNS * elem.excitation[1]^2)
@printf("  ratio measured/linear = %.4f\n", vc / (TURNS * elem.excitation[1]^2))

if CUDA.functional()
    println()
    println("=== I2. CUDA, WITH context ===")
    rg = Phase6DRep(CUDA.zeros(Float64, N), CUDA.zeros(Float64, N), CUDA.zeros(Float64, N),
                    CUDA.zeros(Float64, N), CUDA.zeros(Float64, N), CUDA.zeros(Float64, N))
    Octopus.track!(rg, (elem,), TURNS; policy=CUDAExecutionPolicy(),
                   context=Octopus.TrackingContext(turn=0))
    CUDA.synchronize()
    xg = Array(rg.x)
    @printf("  var(x) = %.6f   ratio to linear = %.4f ; max|gpu-cpu| = %.3e\n",
            var(xg), var(xg) / (TURNS * elem.excitation[1]^2), maximum(abs, xg .- r.x))

    println()
    println("=== I3. CUDA, WITHOUT context  <-- phase6d_track.jl:304-314 ===")
    rg2 = Phase6DRep(CUDA.zeros(Float64, N), CUDA.zeros(Float64, N), CUDA.zeros(Float64, N),
                     CUDA.zeros(Float64, N), CUDA.zeros(Float64, N), CUDA.zeros(Float64, N))
    resolved = Octopus._resolve_execution_policy(CUDAExecutionPolicy(), rg2)
    Octopus.track!(rg2, (elem,), TURNS, resolved)
    CUDA.synchronize()
    x2 = Array(rg2.x)
    @printf("  var(x) after %d turns = %.6f\n", TURNS, var(x2))
    @printf("  ratio to LINEAR  (turns * exc^2)   = %.4f   <- 1.0 is correct\n",
            var(x2) / (TURNS * elem.excitation[1]^2))
    @printf("  ratio to QUADRATIC (turns^2 * exc^2) = %.4f   <- 1.0 means every turn\n",
            var(x2) / (TURNS^2 * elem.excitation[1]^2))
    println("     drew the SAME noise")
    # direct: one turn vs TURNS turns, contextless
    rg1 = Phase6DRep(CUDA.zeros(Float64, N), CUDA.zeros(Float64, N), CUDA.zeros(Float64, N),
                     CUDA.zeros(Float64, N), CUDA.zeros(Float64, N), CUDA.zeros(Float64, N))
    Octopus.track!(rg1, (elem,), 1, resolved)
    CUDA.synchronize()
    x1 = Array(rg1.x)
    @printf("  x(%d turns) == %d * x(1 turn) bitwise-ish: max|x_T - T*x_1| = %.3e (scale %.3e)\n",
            TURNS, TURNS, maximum(abs, x2 .- TURNS .* x1), maximum(abs, x2))
    @printf("  corr(x_T, x_1) = %.10f\n", cor(x2, x1))

    println()
    println("=== I4. deprecated backend-tag contextless path (same code path) ===")
    rg3 = Phase6DRep(CUDA.zeros(Float64, N), CUDA.zeros(Float64, N), CUDA.zeros(Float64, N),
                     CUDA.zeros(Float64, N), CUDA.zeros(Float64, N), CUDA.zeros(Float64, N))
    Octopus.track!(rg3, (elem,), TURNS, CUDABackend)
    CUDA.synchronize()
    x3 = Array(rg3.x)
    @printf("  var(x) = %.6f  ratio to quadratic = %.4f\n",
            var(x3), var(x3) / (TURNS^2 * elem.excitation[1]^2))

    println()
    println("=== I5. is radiation_track.jl's cuda_track_lumped_rad_kernel! reachable? ===")
    println("  It is selected by _requires_cuda_elementwise(elem::LumpedRad) (no ctx) = ",
            Octopus._requires_cuda_elementwise(elem))
    println("  but _track_cuda_policy_elementwise! consults the CTX method, which is ",
            Octopus._requires_cuda_elementwise(elem, Octopus.TrackingContext()))
    println("  so a LumpedRad inside a policy track! is always FUSED, never routed to")
    println("  that kernel. Direct single-element call still reaches it:")
    rg4 = Phase6DRep(CUDA.zeros(Float64, N), CUDA.zeros(Float64, N), CUDA.zeros(Float64, N),
                     CUDA.zeros(Float64, N), CUDA.zeros(Float64, N), CUDA.zeros(Float64, N))
    Octopus.track!(rg4, elem, TURNS, CUDABackend)   # elem, not (elem,)
    CUDA.synchronize()
    x4 = Array(rg4.x)
    @printf("  single-element CUDABackend track!: var(x) = %.6f  ratio to linear = %.4f\n",
            var(x4), var(x4) / (TURNS * elem.excitation[1]^2))
    println("  (that path uses CUDA.default_rng(), NOT the Octopus counter RNG:")
    println("   reproducible only from CUDA's own seed, and it advances per turn.)")
end

println()
println("=== I6. CPU contextless path, for comparison ===")
r5 = zero_rep(N)
resolved_cpu = Octopus.ResolvedCPUExecutionPolicy(1)
Octopus.track!(r5, (elem,), TURNS, resolved_cpu)
@printf("  var(x) = %.6f  ratio to linear = %.4f  (uses Random.randn(), advances)\n",
        var(r5.x), var(r5.x) / (TURNS * elem.excitation[1]^2))
println("  -> CPU contextless is statistically correct but seeded by Julia's")
println("     task-local RNG, so set_global_rng! does NOT reproduce it.")
