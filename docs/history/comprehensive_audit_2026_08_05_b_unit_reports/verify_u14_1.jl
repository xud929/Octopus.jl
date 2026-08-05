# AUDITOR VERIFICATION of U14-1 and a second defect found while verifying it.
#
# phase6d_track.jl:304-314, the CONTEXTLESS CUDA track!, differs from its CPU
# sibling (line 38) in two ways:
#   (1) it fabricates `TrackingContext()` INSIDE the turn loop, so ctx.turn is 0
#       every turn -- while the ctx-taking sibling (line 316) advances it;
#   (2) it omits the `_reject_contextless_tracking(elems)` guard the CPU path
#       calls, whose own docstring says a silent run "reads as 'nothing was
#       lost' rather than 'nothing was recorded' -- the failure mode this whole
#       design is trying to avoid".
#
# Reachable from the deprecated but exported `track!(rep, elems, turns, CUDABackend)`.
using Octopus
using Octopus: CUDABackend, CPUThreadsBackend
using Statistics
import CUDA

set_global_rng!(seed = 20260805, method = :philox)

# A pure stochastic element: damping off, so x_out is exactly the accumulated
# excitation and the turn structure is visible with nothing else in the way.
rad = LumpedRadSpec{Float64}(; damping_turns = (1e12, 1e12, 1e12),
                              beta = (1.0, 1.0, 1.0), alpha = (0.0, 0.0, 0.0),
                              sigma = (1.0e-3, 1.0e-3, 1.0e-3),
                              is_damping = false, rng_id = 4242)
elem = Octopus.compile_runtime(rad)

mkrep(n, backend) = begin
    z = zeros(n)
    backend === CUDABackend ? Phase6DRep(CUDA.zeros(Float64, n), CUDA.zeros(Float64, n), CUDA.zeros(Float64, n),
                                         CUDA.zeros(Float64, n), CUDA.zeros(Float64, n), CUDA.zeros(Float64, n)) :
                              Phase6DRep(copy(z), copy(z), copy(z), copy(z), copy(z), copy(z))
end
host(v) = Array(v)

const N = 20000
println("### (1) does each turn draw a FRESH stream, or repeat turn 0?")
println("Independent turns => var(x after T turns) ~ T * var(x after 1 turn).")
for backend in (CPUThreadsBackend, CUDABackend)
    r1 = mkrep(N, backend); track!(r1, (elem,), 1, backend)
    v1 = var(host(r1.x))
    r16 = mkrep(N, backend); track!(r16, (elem,), 16, backend)
    v16 = var(host(r16.x))
    c = cor(host(r16.x), host(r1.x))
    println("  ", rpad(string(backend), 22),
            " var(1 turn) = ", round(v1, sigdigits = 6),
            "   var(16 turns) = ", round(v16, sigdigits = 6),
            "   ratio = ", round(v16 / v1, sigdigits = 6),
            "   corr(x16,x1) = ", round(c, sigdigits = 8))
    println("       expected ratio if turns are independent: 16.0",
            "   |  if every turn repeats turn 0: 256.0 (16^2)")
    # exact-multiple test: if every turn is identical, x16 == 16*x1 exactly
    println("       max|x16 - 16*x1| = ", maximum(abs, host(r16.x) .- 16 .* host(r1.x)),
            "   (0 => every turn drew the same numbers)")
end

println()
println("### (2) the missing _reject_contextless_tracking guard on the CUDA path")
println("A recording aperture needs turn+particle id; CPU REFUSES a contextless run.")
ap = ApertureSpec(shape = :ellipse, x_limit = 1.0e-3, y_limit = 1.0e-3, name = "COLL")
for backend in (CPUThreadsBackend, CUDABackend)
    rep = mkrep(64, backend)
    rec = LossRecord(["COLL"], 64, rep)
    apr = Octopus.compile_runtime(ap)
    bound = Octopus._bind_apertures((apr,), rec)
    try
        track!(rep, bound, 3, backend)
        println("  ", rpad(string(backend), 22),
                " ACCEPTED a contextless run; loss_counts = ", loss_counts(rec),
                "  <= empty log with no error")
    catch e
        println("  ", rpad(string(backend), 22),
                " REFUSED: ", first(sprint(showerror, e), 90), "...")
    end
end
