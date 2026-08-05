using Octopus
using Printf
const O = Octopus

mkb(n) = begin
    s(scale, phase, k) = [scale * sin(k * i + phase) for i in 1:n]
    rep = O.Phase6DRep(s(1.0e-4, 0.0, 0.7), s(1.0e-6, 0.3, 1.1), s(1.0e-5, 0.9, 0.53),
                       s(1.0e-7, 1.2, 1.7), s(2.0e-2, 2.0, 0.31), s(1.0e-4, 2.5, 2.3))
    params = O.BeamParams{Float64}(charge=1.0, mc2=1.0, E0=1.0, r0=1.0e-9, npart=n)
    O.Beam{O.CPUThreadsBackend,typeof(params),typeof(rep)}(params, rep)
end
workers(f, k) = O._with_execution_policy(f, O.ResolvedCPUExecutionPolicy(k))

NS = 15
println("End-to-end _pic_collide! cost across the _PIC_PARALLEL_DEPOSIT_MIN = 4096 cliff")
println("(15 equal_count slices; per-slice population straddles the threshold)")
for grid in (64, 128)
    for per_slice in (4000, 4200)
        n = NS * per_slice
        solver = O.PICPoissonSolver(kbb1=1.0e-9, kbb2=1.0e-9, luminosity_scale=1.0,
            grid=(grid, grid), green_cache=:none,
            slicing=O.LongitudinalSlicing(nslices=NS, method=:equal_count))
        for k in (1, 8)
            b1 = mkb(n); b2 = mkb(n)
            T = Float64
            ws = O._pic_cpu_workspace(T, grid, grid)
            gc = O._pic_green_cache(solver, T)
            workers(k) do
                O._pic_collide!(solver, b1, b2, nothing, ws, gc)   # warm up
            end
            t = workers(k) do
                @elapsed for _ in 1:3
                    O._pic_collide!(solver, b1, b2, nothing, ws, gc)
                end
            end
            @printf("  grid=%-4d per_slice=%-5d n=%-7d workers=%d   %8.3f s/turn   %8.4f us/particle\n",
                    grid, per_slice, n, k, t / 3, 1e6 * (t / 3) / n)
        end
    end
end
