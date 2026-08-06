# AUDITOR VERIFICATION of U15-1 (kept-whole beam line cannot compile for CUDA)
# and U15-4 (the context-free path imposes one borrowed method on every op).
using Octopus
using Octopus: CUDABackend, CPUThreadsBackend
import CUDA

U = (1.0e-3, 2.0e-4, -5.0e-4, 1.0e-4, 0.0, 1.0e-3)

println("### U15-1: heterogeneous kept-whole line on CUDA")
# Own-state line (x_offset) => kept whole as a CompositeLine, members of
# DIFFERENT concrete runtime types (quadrupole magnet + drift).
het = BeamLine("G_het", QuadrupoleSpec(L = 0.4, k1 = 1.0, nst = 2),
                        DriftSpec(L = 1.0); x_offset = 2.0e-4)
hom = BeamLine("G_hom", QuadrupoleSpec(L = 0.4, k1 = 1.0, nst = 2),
                        QuadrupoleSpec(L = 0.3, k1 = -0.8, nst = 2); x_offset = 2.0e-4)

for (label, line) in (("heterogeneous (magnet + drift)", het), ("homogeneous (two magnets)", hom))
    task = TrackingTask((line,))
    cpu = Phase6DRep([U[1]], [U[2]], [U[3]], [U[4]], [U[5]], [U[6]])
    execute!(task, cpu; turns = 1)
    gpu = Phase6DRep((CUDA.CuArray([u]) for u in U)...)
    try
        execute!(TrackingTask((line,)), gpu; turns = 1)
        CUDA.synchronize()
        d = maximum(abs, Array(gpu.x) .- cpu.x)
        println("  ", rpad(label, 34), " CUDA OK   max|cpu-gpu| = ", d)
    catch e
        m = sprint(showerror, e)
        println("  ", rpad(label, 34), " CUDA FAILED: ", first(m, 100))
    end
end

println()
println("### U15-4: mixed tracking methods through the CONTEXT-FREE path")
# An aperture is NonSymplectic6DMap, a magnet Symplectic6DMap.
mixed = BeamLine("M1", QuadrupoleSpec(L = 0.4, k1 = 1.0, nst = 1),
                       ApertureSpec(shape = :ellipse, x_limit = 1.0e-2, y_limit = 1.0e-2);
                 x_offset = 1.0e-4)
rt = Octopus.compile_runtime(mixed)
for (label, thunk) in (
        ("context-free  rt(coords...)", () -> rt(U...)),
        ("context path  rt(ctx,1,...)", () -> rt(TrackingContext(), 1, U...)))
    try
        out = thunk()
        println("  ", rpad(label, 30), " OK  x_out = ", round(out[1], sigdigits = 8))
    catch e
        println("  ", rpad(label, 30), " THREW ", first(sprint(showerror, e), 90))
    end
end

println()
println("### control: a straight girder must still equal element-level misalignment")
g = Octopus.compile_runtime(BeamLine("G", QuadrupoleSpec(L = 0.4, k1 = 0.9, nst = 2); x_offset = 1.0e-3))
e = Octopus.compile_runtime(QuadrupoleSpec(L = 0.4, k1 = 0.9, nst = 2, x_offset = 1.0e-3))
println("  max|girder - element| = ", maximum(abs, collect(g(U...)) .- collect(e(U...))))
