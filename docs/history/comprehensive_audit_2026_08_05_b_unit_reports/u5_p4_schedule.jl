using Octopus
const O = Octopus

mkb(rng_id, charge, mc2, E0) = begin
    set_global_rng!(seed=5, method=:philox)
    Beam(300, CPUThreadsExecutionPolicy(), Float64;
        beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
        sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0, rng_id=rng_id,
        charge=charge, mc2=mc2, E0=E0, r0=RE * ME0 / mc2, npart=1.0e10)
end
beams() = (mkb(1, -1.0, EMASS_EV, 10.0e9), mkb(2, 1.0, PMASS_EV, 275.0e9))
L6s(b, t) = Linear6DSpec{Float64}(; beta1=b, beta2=b, alpha1=(0.0, 0.0, 0.0),
                                  alpha2=(0.0, 0.0, 0.0), dmu=2pi .* t)
A = L6s((0.55, 0.056, 12.7), (0.08, 0.14, -0.069))
B = L6s((0.8, 0.072, 90.9), (0.228, 0.210, -0.01))

println("=== P5b: the luminosity gate and the solver evaluate the schedule SEPARATELY ===")
calls = Ref(0)
pred = ctx -> (calls[] += 1; isodd(calls[]))
solver = PICPoissonSolver(grid=(24, 24),
                          slicing=LongitudinalSlicing(nslices=3, method=:normal_quantile),
                          luminosity_schedule=O.PredicateSchedule(pred))
ip = StrongStrongCollision(:ip; poisson_solver=solver)
p = tempname() * ".lum"
t = StrongStrongTask((ip, A), (ip, B); luminosity_path=p,
                     policy=CPUThreadsExecutionPolicy(threads=1))
b1, b2 = beams()
execute!(t, b1, b2; turns=4)
println("  predicate invocations for 4 turns / 1 collision: ", calls[], " (one per turn would be 4)")
println("  luminosity file rows:")
for l in readlines(p)
    println("    ", l)
end
println("  -> every written row is NaN even though the file-gate said 'evaluated': ",
        all(l -> occursin("NaN", l), readlines(p)[2:end]))
rm(p; force=true)

println()
println("=== P7: per-turn cost of _collision_solver's new configuration comparison ===")
# The two lines carry DISTINCT but structurally identical solver objects, which
# is exactly the case the identity->configuration change was made to support.
s1 = PICPoissonSolver(grid=(24, 24),
                      slicing=LongitudinalSlicing(nslices=3, method=:normal_quantile))
s2 = PICPoissonSolver(grid=(24, 24),
                      slicing=LongitudinalSlicing(nslices=3, method=:normal_quantile))
c1 = StrongStrongCollision(:ip; poisson_solver=s1)
c2 = StrongStrongCollision(:ip; poisson_solver=s2)
tt = StrongStrongTask((c1, A), (c2, B); policy=CPUThreadsExecutionPolicy(threads=1))
O._collision_solver(tt, c1, c2)                       # warm up
alloc = @allocated O._collision_solver(tt, c1, c2)
n = 10_000
el = @elapsed for _ in 1:n
    O._collision_solver(tt, c1, c2)
end
println("  distinct-but-equal solvers: ", alloc, " bytes/call, ",
        round(el / n * 1e9; digits=1), " ns/call")
cshared = StrongStrongCollision(:ip; poisson_solver=s1)
ts = StrongStrongTask((cshared, A), (cshared, B); policy=CPUThreadsExecutionPolicy(threads=1))
O._collision_solver(ts, cshared, cshared)
alloc2 = @allocated O._collision_solver(ts, cshared, cshared)
el2 = @elapsed for _ in 1:n
    O._collision_solver(ts, cshared, cshared)
end
println("  shared solver object      : ", alloc2, " bytes/call, ",
        round(el2 / n * 1e9; digits=1), " ns/call")
println("  NOTE: called once per collision per TURN at interface.jl _execute_strong_strong_turns!")

println()
println("=== P8: mixed-IP dropped-row warning is capped at maxlog=4 ===")
sched_solver = PICPoissonSolver(grid=(16, 16),
    slicing=LongitudinalSlicing(nslices=2, method=:normal_quantile),
    luminosity_schedule=O.AtTurns([0]))
plain_solver = PICPoissonSolver(grid=(16, 16),
    slicing=LongitudinalSlicing(nslices=2, method=:normal_quantile))
ip1 = StrongStrongCollision(:ip1; poisson_solver=sched_solver)
ip2 = StrongStrongCollision(:ip2; poisson_solver=plain_solver)
p2 = tempname() * ".lum"
t2 = StrongStrongTask((ip1, A, ip2), (ip1, B, ip2); luminosity_path=p2,
                      policy=CPUThreadsExecutionPolicy(threads=1))
b1, b2 = beams()
nwarn = Ref(0)
logger = Base.CoreLogging.SimpleLogger(devnull, Base.CoreLogging.Warn)
counting = Base.CoreLogging.ConsoleLogger(devnull)
Base.CoreLogging.with_logger(counting) do
    execute!(t2, b1, b2; turns=10)
end
rows = readlines(p2)
println("  10 turns, mixed schedules -> rows written: ", length(rows) - 1,
        " (expected 1: only turn 0 has both evaluated)")
println("  rows: ", rows[2:end])
rm(p2; force=true)
