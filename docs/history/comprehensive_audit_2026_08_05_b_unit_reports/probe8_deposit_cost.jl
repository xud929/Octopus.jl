using Octopus
using Printf
const O = Octopus

workers(f, k) = O._with_execution_policy(f, O.ResolvedCPUExecutionPolicy(k))

function bench(f, reps)
    f(); GC.gc()
    t = @elapsed for _ in 1:reps; f(); end
    return 1000 * t / reps
end

println("Deposit cost: serial vs the fixed 16-chunk threaded path (workspace variant)")
println("nchunks = _PIC_DEPOSIT_CHUNKS = ", O._PIC_DEPOSIT_CHUNKS)
for grid in (32, 64, 128)
    ws = O._pic_cpu_workspace(Float64, grid, grid)
    for n in (4096, 20000, 68000, 200000)
        x = [1.0e-4 * sin(0.7i) for i in 1:n]; y = [1.0e-5 * sin(0.31i) for i in 1:n]
        px = [1.0e-6 * sin(1.1i) for i in 1:n]; py = [1.0e-7 * sin(0.53i) for i in 1:n]
        x0 = -2.0e-4; y0 = -2.0e-5
        hx = 4.0e-4 / (grid - 1); hy = 4.0e-5 / (grid - 1)
        ser = bench(10) do
            fill!(ws.charge, 0.0)
            O._pic_deposit_drifted_serial!(ws.charge, :CIC, x, px, y, py, 1.0e-3, x0, y0, hx, hy, grid, grid)
        end
        for k in (1, 8)
            thr = workers(k) do
                bench(10) do
                    fill!(ws.charge, 0.0)
                    O._pic_deposit_drifted_threaded!(ws.charge, :CIC, x, px, y, py, 1.0e-3,
                                                     x0, y0, hx, hy, grid, grid, ws)
                end
            end
            @printf("  grid=%-4d n=%-7d workers=%d   serial %8.3f ms   threaded16 %8.3f ms   ratio %6.2fx\n",
                    grid, n, k, ser, thr, thr / ser)
        end
    end
end
