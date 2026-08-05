using Octopus
const O = Octopus
println("=== P9: is _record_solver_configuration! free when no ExecutionAudit is active? ===")
println("  (docstring at interface.jl `_record_solver_configuration!`: \"Costs nothing unless an ExecutionAudit is active.\")")
println("  _ACTIVE_EXECUTION_AUDIT[] = ", O._ACTIVE_EXECUTION_AUDIT[])
for s in (PICPoissonSolver(grid=(16,16)), GaussianPoissonSolver(),
          O.SpectralPoissonSolver(grid=(16,16)), O.GaussianPICPoissonSolver(grid=(16,16)))
    O._record_solver_configuration!(s, CPUThreadsBackend)               # warm
    a = @allocated O._record_solver_configuration!(s, CPUThreadsBackend)
    n = 2000
    t = @elapsed for _ in 1:n; O._record_solver_configuration!(s, CPUThreadsBackend); end
    println("  ", rpad(nameof(typeof(s)), 26), " no audit active -> ", a, " bytes, ",
            round(t/n*1e6; digits=2), " us per call")
end
println()
println("  for comparison, the small receipts in the same loop:")
O._record_execution!(:strong_strong_collision, CPUThreadsBackend, (solver=:X, turn=0))
a2 = @allocated O._record_execution!(:strong_strong_collision, CPUThreadsBackend, (solver=:X, turn=0))
println("  :strong_strong_collision receipt -> ", a2, " bytes")
