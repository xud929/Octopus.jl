# U14 probe K: the contextless-tracking refusal exists on the CPU path only.
using Octopus, Printf
import CUDA

n = 64
mkrep() = Phase6DRep(collect(range(-5e-3, 5e-3; length=n)), zeros(n),
                     zeros(n), zeros(n), zeros(n), zeros(n))

rep_cpu = mkrep()
rec_cpu = LossRecord(["A"], n, rep_cpu)
line_cpu = (compile_runtime(DriftSpec(L=0.5)),
            compile_runtime(ApertureSpec(shape=:rectangle, x_limit=2.0e-3, y_limit=1.0,
                                         name="A", element_id=1, loss_record=rec_cpu)))
println("_requires_tracking_context(line) = ", Octopus._requires_tracking_context(line_cpu))

println()
println("=== CPU, contextless ===")
try
    pol = Octopus.ResolvedCPUExecutionPolicy(1)
    Octopus._with_execution_policy(pol) do
        Octopus.track!(rep_cpu, line_cpu, 3, pol)
    end
    println("  RAN. loss_counts = ", loss_counts(rec_cpu), "  <- guard did NOT fire")
catch e
    println("  REFUSED: ", typeof(e))
    println("  ", first(replace(sprint(showerror, e), "\n" => " "), 200))
end

if CUDA.functional()
    println()
    println("=== CUDA, contextless (same line) ===")
    rep_gpu = Phase6DRep((CUDA.CuArray(a) for a in coordinate_arrays(mkrep()))...)
    rec_gpu = LossRecord(["A"], n, rep_gpu)
    line_gpu = (compile_runtime(DriftSpec(L=0.5)),
                compile_runtime(ApertureSpec(shape=:rectangle, x_limit=2.0e-3, y_limit=1.0,
                                             name="A", element_id=1, loss_record=rec_gpu)))
    try
        pol = Octopus._resolve_execution_policy(CUDAExecutionPolicy(), rep_gpu)
        Octopus._with_execution_policy(pol) do
            Octopus.track!(rep_gpu, line_gpu, 3, pol)
        end
        CUDA.synchronize()
        println("  RAN with no refusal. loss_counts = ", loss_counts(rec_gpu))
        println("  <- the SAME line the CPU refuses runs here, and the loss log is:")
        lr = loss_records(rec_gpu)
        println("     recorded rows = ", length(lr.particle_id))
    catch e
        println("  REFUSED / errored: ", typeof(e))
        println("  ", first(replace(sprint(showerror, e), "\n" => " "), 300))
    end

    println()
    println("=== CUDA, WITH context (the supported path), for reference ===")
    rep_gpu2 = Phase6DRep((CUDA.CuArray(a) for a in coordinate_arrays(mkrep()))...)
    rec2 = LossRecord(["A"], n, rep_gpu2)
    line2 = (compile_runtime(DriftSpec(L=0.5)),
             compile_runtime(ApertureSpec(shape=:rectangle, x_limit=2.0e-3, y_limit=1.0,
                                          name="A", element_id=1, loss_record=rec2)))
    Octopus.track!(rep_gpu2, line2, 3; policy=CUDAExecutionPolicy())
    CUDA.synchronize()
    println("  loss_counts = ", loss_counts(rec2), "  recorded rows = ",
            length(loss_records(rec2).particle_id))
end
