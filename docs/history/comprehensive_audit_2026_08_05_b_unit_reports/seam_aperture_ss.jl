# SEAM PROBE (auditor, U27): apertures in a StrongStrongTask line.
#
# Tasks.jl:614 binds apertures to a per-beam LossRecord and execute! reconciles
# two independent loss counts, warning when `unattributed != 0`.
# interface.jl's _strong_strong_runtime_blocks has NO _bind_apertures call and
# the strong-strong file mentions neither aperture nor loss record.
#
# Question: what does a user get when an aperture sits in a strong-strong line
# and actually kills particles?  Silent kill = the "loud beats silent" class.
using Octopus

set_global_rng!(seed = 20260805, method = :philox)

# A tight aperture that WILL kill: beams are 100 um / 10 um, limit is 1 sigma-ish.
ap = ApertureSpec(shape = :ellipse, x_limit = 5.0e-5, y_limit = 5.0e-6, name = "tight_collimator")
ip = StrongStrongCollision(:ip; poisson_solver = GaussianPoissonSolver())

line1 = (ap, ip)
line2 = (ap, ip)

mkbeam() = Beam(4000, CPUThreadsBackend; beta = (0.8, 0.072, 90.0), alpha = (0.0, 0.0, 0.0),
                sigma = (95.0e-6, 8.5e-6, 6.0e-2), rng_id = 11)

println("### 1. StrongStrongTask with an aperture that kills")
b1, b2 = mkbeam(), mkbeam()
task = StrongStrongTask(line1, line2)
alive_before = count(isfinite, Array(b1.rep.x))
println("alive before      = ", alive_before)
try
    execute!(task, b1, b2; turns = 2)
    alive_after = count(isfinite, Array(b1.rep.x))
    println("alive after       = ", alive_after)
    println("killed            = ", alive_before - alive_after)
    println("=> any warning or summary printed above this line? (that is the question)")
catch e
    println("THREW: ", sprint(showerror, e))
end

println()
println("### 2. control: the SAME aperture in a TrackingTask")
set_global_rng!(seed = 20260805, method = :philox)
b3 = mkbeam()
t2 = TrackingTask((ap,))
a_before = count(isfinite, Array(b3.rep.x))
println("alive before      = ", a_before)
execute!(t2, b3.rep; turns = 2)
a_after = count(isfinite, Array(b3.rep.x))
println("alive after       = ", a_after)
println("killed            = ", a_before - a_after)
println("loss_summary      = ", loss_summary(t2))
