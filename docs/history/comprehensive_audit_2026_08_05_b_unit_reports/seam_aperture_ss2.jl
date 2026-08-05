# SEAM PROBE 2 (auditor, U27): the escape hatch the strong-strong fail-fast
# points users at.  Probe 1 REFUTED the silent-kill hypothesis: the solver
# throws a detailed, actionable error.  It names `allow_lost_particles` as the
# supported way to proceed.  The remaining question is whether that path comes
# WITH loss accounting, or whether accounting is what you trade away — because
# interface.jl binds no LossRecord (no _bind_apertures call anywhere outside
# Tasks.jl:614).
using Octopus

set_global_rng!(seed = 20260805, method = :philox)

ap = ApertureSpec(shape = :ellipse, x_limit = 5.0e-5, y_limit = 5.0e-6, name = "tight_collimator")
ip = StrongStrongCollision(:ip; poisson_solver = GaussianPoissonSolver())

# Physically complete beams: E0/mass/charge/npart supplied, as examples/ does.
# Without them the solver (correctly) refuses -- see probe 1's second throw.
mkbeam(id) = Beam(4000, CPUThreadsBackend, Float64; beta = (0.8, 0.072, 90.0),
                  alpha = (0.0, 0.0, 0.0), sigma = (95.0e-6, 8.5e-6, 6.0e-2),
                  rng_id = id, charge = -1.0, mc2 = ME0, E0 = 1.0e10,
                  r0 = RE, npart = 1.0e11)

b1, b2 = mkbeam(11), mkbeam(12)
task = StrongStrongTask((ap, ip), (ap, ip))
before = count(isfinite, Array(b1.rep.x))

println("### strong-strong inside allow_lost_particles")
println("alive before = ", before)
allow_lost_particles() do
    execute!(task, b1, b2; turns = 2)
end
after = count(isfinite, Array(b1.rep.x))
println("alive after  = ", after)
println("killed       = ", before - after)
println()
println("--- is any loss accounting available for this task? ---")
for (nm, thunk) in (
        ("loss_summary(b1.rep, task)", () -> loss_summary(b1.rep, task)),
        ("loss_counts on task",        () -> loss_counts(getfield(task, :loss_record)[])),
    )
    try
        println(nm, " => ", thunk())
    catch e
        println(nm, " => THREW ", typeof(e), ": ", first(sprint(showerror, e), 200))
    end
end
println()
println("StrongStrongTask fieldnames = ", fieldnames(typeof(task)))

println()
println("--- what IS available: count_dead (the docstring's recommended cross-check) ---")
try
    println("count_dead(b1.rep) = ", count_dead(b1.rep))
catch e
    println("count_dead THREW: ", first(sprint(showerror, e), 200))
end
println("aperture_names on a StrongStrongTask? ",
        hasmethod(aperture_names, Tuple{typeof(task)}) ? "yes" : "NO METHOD")
println("loss_summary methods that accept a StrongStrongTask: ",
        count(m -> any(t -> task isa t, m.sig.parameters[2:end]), methods(loss_summary)))
