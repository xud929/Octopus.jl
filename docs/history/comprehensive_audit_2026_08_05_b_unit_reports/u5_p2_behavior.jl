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

function run_solver(solver; turns=2)
    ip = StrongStrongCollision(:ip; poisson_solver=solver)
    l1 = (ip, L6s((0.55, 0.056, 12.7), (0.08, 0.14, -0.069)))
    l2 = (ip, L6s((0.8, 0.072, 90.9), (0.228, 0.210, -0.01)))
    p = tempname() * ".lum"
    t = StrongStrongTask(l1, l2; luminosity_path=p,
                         policy=CPUThreadsExecutionPolicy(threads=1))
    b1, b2 = beams()
    execute!(t, b1, b2; turns=turns)
    coords = vcat((Array(a) for a in coordinate_arrays(b1.rep))...,
                  (Array(a) for a in coordinate_arrays(b2.rep))...)
    lum = readlines(p)[2:end]
    rm(p; force=true)
    return coords, lum
end

println("=== P2: is grid_extent_sigma inert under the default grid_extent=:extrema? ===")
base = (grid=(24, 24), slicing=LongitudinalSlicing(nslices=3, method=:normal_quantile))
a = run_solver(PICPoissonSolver(; base..., grid_extent=:extrema, grid_extent_sigma=6.0))
b = run_solver(PICPoissonSolver(; base..., grid_extent=:extrema, grid_extent_sigma=2.0))
println("  :extrema, sigma 6.0 vs 2.0 -> coordinates bit-identical: ", a[1] == b[1],
        "   luminosity rows identical: ", a[2] == b[2])
c = run_solver(PICPoissonSolver(; base..., grid_extent=:sigma, grid_extent_sigma=6.0))
d = run_solver(PICPoissonSolver(; base..., grid_extent=:sigma, grid_extent_sigma=2.0))
println("  :sigma,   sigma 6.0 vs 2.0 -> coordinates bit-identical: ", c[1] == d[1],
        "   (expected false)")
rep = O.configuration_report(PICPoissonSolver(; base..., grid_extent=:extrema,
                                              grid_extent_sigma=2.0);
                             backend=CPUThreadsBackend)
for e in rep
    e.name === :grid_extent_sigma || continue
    println("  configuration_report status for grid_extent_sigma with :extrema = ", e.status,
            "  (declared dependencies = ",
            O.solver_option_schema(PICPoissonSolver).grid_extent_sigma.dependencies, ")")
end

println()
println("=== P3: does the :strong_strong_output receipt carry luminosity_append? ===")
let
    ip = StrongStrongCollision(:ip)
    l1 = (ip, L6s((0.55, 0.056, 12.7), (0.08, 0.14, -0.069)))
    l2 = (ip, L6s((0.8, 0.072, 90.9), (0.228, 0.210, -0.01)))
    p = tempname() * ".lum"
    t = StrongStrongTask(l1, l2; luminosity_path=p, luminosity_append=true,
                         policy=CPUThreadsExecutionPolicy(threads=1))
    b1, b2 = beams()
    audit = O.ExecutionAudit()
    O.with_execution_audit(audit) do
        execute!(t, b1, b2; turns=2)
    end
    rs = filter(r -> r.consumer === :strong_strong_output, O.execution_receipts(audit))
    println("  :strong_strong_output receipts: ", length(rs))
    for r in rs
        println("    values = ", r.values,
                "  has luminosity_append: ", haskey(r.values, :luminosity_append))
    end
    rm(p; force=true)
end

println()
println("=== P5: is the PIC luminosity schedule evaluated twice per turn? ===")
let
    solver = PICPoissonSolver(grid=(24, 24),
                              slicing=LongitudinalSlicing(nslices=3, method=:normal_quantile),
                              luminosity_schedule=EveryNSteps(step=2))
    ip = StrongStrongCollision(:ip; poisson_solver=solver)
    l1 = (ip, L6s((0.55, 0.056, 12.7), (0.08, 0.14, -0.069)))
    l2 = (ip, L6s((0.8, 0.072, 90.9), (0.228, 0.210, -0.01)))
    p = tempname() * ".lum"
    t = StrongStrongTask(l1, l2; luminosity_path=p,
                         policy=CPUThreadsExecutionPolicy(threads=1))
    b1, b2 = beams()
    audit = O.ExecutionAudit()
    O.with_execution_audit(audit) do
        execute!(t, b1, b2; turns=4)
    end
    rs = filter(r -> r.consumer === :pic_luminosity_schedule, O.execution_receipts(audit))
    println("  turns=4, 1 collision -> :pic_luminosity_schedule receipts = ", length(rs))
    println("  per-turn: ", [(r.values.turn, r.values.evaluated) for r in rs])
    rm(p; force=true)
end

println()
println("=== P6: _collision_solver with a schema-less (Main-defined) solver type ===")
struct ProbeSolver <: O.AbstractPoissonSolver
    knob::Float64
end
let
    s1 = ProbeSolver(1.0)
    s2 = ProbeSolver(999.0)
    c1 = StrongStrongCollision(:ip; poisson_solver=s1)
    c2 = StrongStrongCollision(:ip; poisson_solver=s2)
    ipx = StrongStrongCollision(:ip)
    t = StrongStrongTask((ipx,), (ipx,))
    println("  solver_option_schema(ProbeSolver) = ", O.solver_option_schema(ProbeSolver))
    println("  solver_configuration(s1) = ", O.solver_configuration(s1),
            "   == solver_configuration(s2): ", O.solver_configuration(s1) == O.solver_configuration(s2))
    got = try
        chosen = O._collision_solver(t, c1, c2)
        "ACCEPTED, chose knob=$(chosen.knob) (s2's knob=$(s2.knob) discarded)"
    catch err
        "rejected: $(typeof(err))"
    end
    println("  _collision_solver(differently configured s1, s2): ", got)
end
