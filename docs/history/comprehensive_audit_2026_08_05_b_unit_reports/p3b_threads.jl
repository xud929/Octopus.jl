using Octopus
const O = Octopus

set_global_rng!(seed=987654321)
spec = LumpedRadSpec{Float64}(damping_turns=(1.0e4,1.0e4,1.0e4),
                              sigma=(1.0e-3,1.0e-3,1.0e-3), rng_id=777)
tsk = TrackingTask(BeamLine("RING", spec, DriftSpec(L=1.0)))
N = 20000
rep = Phase6DRep(zeros(N), zeros(N), zeros(N), zeros(N), zeros(N), zeros(N))
audit = O.ExecutionAudit()
O.with_execution_audit(audit) do
    execute!(tsk, rep; turns=3)
end
recs = [r for r in O.execution_receipts(audit) if r.consumer === :cpu_logical_workers]
println("nthreads = ", Threads.nthreads(),
        "  worker receipts = ", isempty(recs) ? "NONE" : recs[1].values,
        "  n = ", length(recs))
println("hash = ", hash((rep.x, rep.px, rep.y, rep.py, rep.z, rep.pz)))
println("sum|x| = ", sum(abs, rep.x))
