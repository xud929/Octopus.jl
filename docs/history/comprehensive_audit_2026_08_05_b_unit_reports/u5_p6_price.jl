using Octopus, Logging
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

mk(g) = PICPoissonSolver(grid=g,
                         slicing=LongitudinalSlicing(nslices=3, method=:normal_quantile))

println("=== P7b: turn-time price of the per-turn _collision_solver comparison ===")
for g in ((16, 16), (24, 24), (64, 64))
    s1, s2 = mk(g), mk(g)
    shared = StrongStrongCollision(:ip; poisson_solver=s1)
    d1 = StrongStrongCollision(:ip; poisson_solver=s1)
    d2 = StrongStrongCollision(:ip; poisson_solver=s2)
    function timeit(c1, c2; turns=20)
        t = StrongStrongTask((c1, A), (c2, B);
                             policy=CPUThreadsExecutionPolicy(threads=1),
                             diagnostics=StrongStrongDiagnostics(record_turn_times=true))
        b1, b2 = beams(); execute!(t, b1, b2; turns=3)          # warm
        b1, b2 = beams(); execute!(t, b1, b2; turns=turns)
        return sum(turn_timings(t)) / turns
    end
    ts = timeit(shared, shared)
    td = timeit(d1, d2)
    println("  grid=", g, ": shared-object ", round(ts * 1e3; digits=3), " ms/turn, ",
            "distinct-but-equal ", round(td * 1e3; digits=3), " ms/turn, ratio ",
            round(td / ts; digits=3))
end

println()
println("=== P8b: how many mixed-schedule dropped rows are announced? ===")
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
struct CountingLogger <: Logging.AbstractLogger
    n::Base.RefValue{Int}
end
Logging.min_enabled_level(::CountingLogger) = Logging.Warn
Logging.shouldlog(::CountingLogger, args...) = true
Logging.catch_exceptions(::CountingLogger) = false
function Logging.handle_message(l::CountingLogger, level, message, _mod, group, id,
                                file, line; kwargs...)
    occursin("luminosity row dropped", string(message)) && (l.n[] += 1)
    return nothing
end
Logging.with_logger(CountingLogger(nwarn)) do
    execute!(t2, b1, b2; turns=30)
end
rows = readlines(p2)
println("  30 turns, mixed schedules: rows written = ", length(rows) - 1,
        ", rows dropped = ", 30 - (length(rows) - 1),
        ", warnings emitted = ", nwarn[], " (maxlog = 4)")
rm(p2; force=true)
