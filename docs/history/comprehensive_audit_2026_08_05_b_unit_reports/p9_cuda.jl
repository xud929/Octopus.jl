using Octopus, CUDA
const O = Octopus

println("CUDA functional = ", CUDA.functional())

println()
println("== i1. CPU/CUDA identity of a stochastic line (counter RNG) ==")
set_global_rng!(seed=13579)
spec = LumpedRadSpec{Float64}(damping_turns=(1.0e4,1.0e4,1.0e4),
                              sigma=(1.0e-3,1.0e-3,1.0e-3), rng_id=555)
N = 4096
mkrep() = Phase6DRep(zeros(N), zeros(N), zeros(N), zeros(N), zeros(N), zeros(N))
t1 = TrackingTask(BeamLine("R", spec, DriftSpec(L=1.0)))
r1 = mkrep(); execute!(t1, r1; turns=3)
t2 = TrackingTask(BeamLine("R", spec, DriftSpec(L=1.0)))
r2 = Phase6DRep(CUDA.zeros(Float64,N), CUDA.zeros(Float64,N), CUDA.zeros(Float64,N),
                CUDA.zeros(Float64,N), CUDA.zeros(Float64,N), CUDA.zeros(Float64,N))
execute!(t2, r2; turns=3, )
println("  max|cpu - gpu| = ", maximum(abs, r1.x .- Array(r2.x)))
println("  bit-identical  = ", all(r1.x .== Array(r2.x)))

println()
println("== i2. misaligned (wrapped) stochastic element on device ==")
mis = LumpedRadSpec{Float64}(damping_turns=(1.0e4,1.0e4,1.0e4),
                             sigma=(1.0e-3,1.0e-3,1.0e-3), rng_id=556, x_offset=1.0e-6)
tc = TrackingTask(BeamLine("RM", mis, DriftSpec(L=1.0)))
rc = mkrep(); execute!(tc, rc; turns=2)
tg = TrackingTask(BeamLine("RM", mis, DriftSpec(L=1.0)))
rg = Phase6DRep(CUDA.zeros(Float64,N), CUDA.zeros(Float64,N), CUDA.zeros(Float64,N),
                CUDA.zeros(Float64,N), CUDA.zeros(Float64,N), CUDA.zeros(Float64,N))
r = try
    execute!(tg, rg; turns=2)
    "max|cpu-gpu| = " * string(maximum(abs, rc.x .- Array(rg.x))) *
    "  bit-identical = " * string(all(rc.x .== Array(rg.x)))
catch e
    "THREW " * first(sprint(showerror, e), 200)
end
println("  ", r)

println()
println("== i3. F15 guard compiles as device IR (aperture with a loss record) ==")
line = BeamLine("A", ApertureSpec(x_limit=1.0e-3, y_limit=1.0e-3, name="C"),
                DriftSpec(L=1.0))
ta = TrackingTask(line)
xg = CUDA.CuArray(collect(range(-2.0e-3, 2.0e-3; length=N)))
zg = CUDA.zeros(Float64, N)
ra = Phase6DRep(xg, copy(zg), copy(zg), copy(zg), copy(zg), copy(zg))
r = try
    execute!(ta, ra; turns=1)
    "counts = " * string(loss_counts(loss_record(ta))) *
    "  summary = " * string(loss_summary(ra, ta))
catch e
    "THREW " * first(sprint(showerror, e), 300)
end
println("  ", r)

println()
println("== i4. kept-whole (girder) line on device ==")
cryo = BeamLine("CRYO", QuadrupoleSpec(L=0.4, k1=1.0, nst=2), DriftSpec(L=1.0);
                x_offset=2.0e-4)
tg2 = TrackingTask(BeamLine("ARC", cryo, DriftSpec(L=1.0)))
rg2 = Phase6DRep(CUDA.CuArray(fill(1.0e-3, N)), CUDA.zeros(Float64,N),
                 CUDA.zeros(Float64,N), CUDA.zeros(Float64,N),
                 CUDA.zeros(Float64,N), CUDA.zeros(Float64,N))
tc2 = TrackingTask(BeamLine("ARC", cryo, DriftSpec(L=1.0)))
rc2 = Phase6DRep(fill(1.0e-3, N), zeros(N), zeros(N), zeros(N), zeros(N), zeros(N))
execute!(tc2, rc2; turns=2)
r = try
    execute!(tg2, rg2; turns=2)
    "max|cpu-gpu| = " * string(maximum(abs, rc2.x .- Array(rg2.x)))
catch e
    "THREW " * first(sprint(showerror, e), 250)
end
println("  ", r)
println("done")
