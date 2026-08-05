using Octopus
const O = Octopus
mkb(rng_id, charge, mc2, E0) = begin
    set_global_rng!(seed=5, method=:philox)
    Beam(300, CPUThreadsExecutionPolicy(), Float64;
        beta=(0.55,0.056,12.7), alpha=(0.0,0.0,0.0), sigma=(106.0e-6,9.5e-6,7.0e-3),
        cutoff=5.0, rng_id=rng_id, charge=charge, mc2=mc2, E0=E0,
        r0=RE*ME0/mc2, npart=1.0e10)
end
beams() = (mkb(1,-1.0,EMASS_EV,10.0e9), mkb(2,1.0,PMASS_EV,275.0e9))
L6s(b,t) = Linear6DSpec{Float64}(; beta1=b, beta2=b, alpha1=(0.0,0.0,0.0),
                                  alpha2=(0.0,0.0,0.0), dmu=2pi .* t)
A = L6s((0.55,0.056,12.7),(0.08,0.14,-0.069)); B = L6s((0.8,0.072,90.9),(0.228,0.210,-0.01))
mk(g) = PICPoissonSolver(grid=g, slicing=LongitudinalSlicing(nslices=3, method=:normal_quantile))
println("=== P7c: turn-time price, median of 40 turns, repeated 3x ===")
for g in ((16,16), (32,32))
    s1, s2 = mk(g), mk(g)
    shared = StrongStrongCollision(:ip; poisson_solver=s1)
    d1 = StrongStrongCollision(:ip; poisson_solver=s1)
    d2 = StrongStrongCollision(:ip; poisson_solver=s2)
    function med(c1,c2)
        t = StrongStrongTask((c1,A),(c2,B); policy=CPUThreadsExecutionPolicy(threads=1),
                             diagnostics=StrongStrongDiagnostics(record_turn_times=true))
        b1,b2 = beams(); execute!(t,b1,b2; turns=5)
        best = Inf
        for _ in 1:3
            b1,b2 = beams(); execute!(t,b1,b2; turns=40)
            v = sort(turn_timings(t)); best = min(best, v[div(end,2)])
        end
        best
    end
    ts = med(shared, shared); td = med(d1, d2)
    println("  grid=",g,": shared ",round(ts*1e3;digits=3)," ms/turn  distinct ",
            round(td*1e3;digits=3)," ms/turn  delta ",round((td-ts)*1e6;digits=1)," us  ratio ",
            round(td/ts;digits=4))
end
println()
println("=== P8c: maxlog under the DEFAULT logger (stderr) ===")
sched = PICPoissonSolver(grid=(16,16), slicing=LongitudinalSlicing(nslices=2,method=:normal_quantile),
                         luminosity_schedule=O.AtTurns([0]))
plain = PICPoissonSolver(grid=(16,16), slicing=LongitudinalSlicing(nslices=2,method=:normal_quantile))
ip1 = StrongStrongCollision(:ip1; poisson_solver=sched)
ip2 = StrongStrongCollision(:ip2; poisson_solver=plain)
p = tempname()*".lum"
t = StrongStrongTask((ip1,A,ip2),(ip1,B,ip2); luminosity_path=p,
                     policy=CPUThreadsExecutionPolicy(threads=1))
b1,b2 = beams()
execute!(t,b1,b2; turns=30)
rows = readlines(p)
println("  30 turns -> rows written = ", length(rows)-1, ", rows dropped = ", 30-(length(rows)-1))
rm(p; force=true)
