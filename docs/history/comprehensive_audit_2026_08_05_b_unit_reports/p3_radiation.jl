using Octopus
const O = Octopus

set_global_rng!(seed=20260805)
ctx = O.with_turn(O.TrackingContext(), 7)

mkspec(id) = LumpedRadSpec{Float64}(damping_turns=(1.0e6, 1.0e6, 1.0e6),
                                    beta=(1.0, 1.0, 1.0), alpha=(0.0, 0.0, 0.0),
                                    sigma=(1.0e-3, 1.0e-3, 1.0e-3),
                                    is_damping=false, rng_id=id)

println("== c1. two placements of ONE spec object ==")
s1 = mkspec(0)
println("  auto rng_id = ", getparam(s1, :rng_id, 0))
line = BeamLine("RAD2", s1, s1)
task = TrackingTask(line)                       # expect the F14 warning
e = compile_runtime(s1)
o1 = e(ctx, 5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
o2 = e(ctx, 5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
println("  two calls, same (turn,pid): identical = ", o1 == o2, "  dx = ", o1[1])

println()
println("== c2. two DISTINCT specs ==")
sa, sb = mkspec(0), mkspec(0)
println("  rng_ids = ", getparam(sa,:rng_id,0), " ", getparam(sb,:rng_id,0))
ea, eb = compile_runtime(sa), compile_runtime(sb)
oa = ea(ctx, 5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
ob = eb(ctx, 5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
println("  dx_a = ", oa[1], "  dx_b = ", ob[1], "  equal = ", oa[1] == ob[1])
tsk2 = TrackingTask(BeamLine("RADAB", sa, sb))   # expect NO warning

println()
println("== c3. independence over many particles (distinct specs) ==")
n = 4000
xa = [ea(ctx, i, 0.0,0.0,0.0,0.0,0.0,0.0)[1] for i in 1:n]
xb = [eb(ctx, i, 0.0,0.0,0.0,0.0,0.0,0.0)[1] for i in 1:n]
mx(v) = sum(v)/length(v)
cov = sum((xa .- mx(xa)) .* (xb .- mx(xb)))/n
sd(v) = sqrt(sum((v .- mx(v)).^2)/n)
println("  corr(a,b) = ", cov/(sd(xa)*sd(xb)), "   (want ~0, 1/sqrt(n)=", 1/sqrt(n), ")")
println("  sd_a = ", sd(xa), " sd_b = ", sd(xb), "  (want ~1e-3)")
xs = [e(ctx, i, 0.0,0.0,0.0,0.0,0.0,0.0)[1] for i in 1:n]
println("  corr(shared-spec placement 1 vs 2) = ",
        let c = sum((xs .- mx(xs)).*(xs .- mx(xs)))/n; c/(sd(xs)*sd(xs)) end,
        "   (identical stream by construction)")

println()
println("== c4/c5/c6. wrapper context forwarding ==")
wrapped = Dict{String,Any}()
wrapped["MisalignedElement"]  = compile_runtime(mkspec(101); )
misspec = LumpedRadSpec{Float64}(damping_turns=(1.0e6,1.0e6,1.0e6),
                                 sigma=(1.0e-3,1.0e-3,1.0e-3), is_damping=false,
                                 rng_id=101, x_offset=1.0e-9)
reftspec = LumpedRadSpec{Float64}(damping_turns=(1.0e6,1.0e6,1.0e6),
                                  sigma=(1.0e-3,1.0e-3,1.0e-3), is_damping=false,
                                  rng_id=102, ref_tilt=0.3)
bothspec = LumpedRadSpec{Float64}(damping_turns=(1.0e6,1.0e6,1.0e6),
                                  sigma=(1.0e-3,1.0e-3,1.0e-3), is_damping=false,
                                  rng_id=103, x_offset=1.0e-9, ref_tilt=0.3)
cryo = BeamLine("CRYO", LumpedRadSpec{Float64}(damping_turns=(1.0e6,1.0e6,1.0e6),
                                               sigma=(1.0e-3,1.0e-3,1.0e-3),
                                               is_damping=false, rng_id=104);
                x_offset=1.0e-9)
plain = BeamLine("PLAIN", LumpedRadSpec{Float64}(damping_turns=(1.0e6,1.0e6,1.0e6),
                                                 sigma=(1.0e-3,1.0e-3,1.0e-3),
                                                 is_damping=false, rng_id=105);
                 tags=(:x,))   # own state via tags? no -> use a param
cases = ["bare"            => compile_runtime(mkspec(100)),
         "MisalignedElem"  => compile_runtime(misspec),
         "RefTilted"       => compile_runtime(reftspec),
         "RefTilted(Mis)"  => compile_runtime(bothspec),
         "Mis(Composite)"  => compile_runtime(cryo)]
for (lbl, el) in cases
    a1 = el(ctx, 11, 0.0,0.0,0.0,0.0,0.0,0.0)
    a2 = el(ctx, 11, 0.0,0.0,0.0,0.0,0.0,0.0)
    println("  ", rpad(lbl, 16), nameof(typeof(el)), "  repeatable = ", a1 == a2,
            "   dx = ", a1[1])
end

println()
println("== c7. thread invariance of a stochastic task ==")
set_global_rng!(seed=987654321)
spec = LumpedRadSpec{Float64}(damping_turns=(1.0e4,1.0e4,1.0e4),
                              sigma=(1.0e-3,1.0e-3,1.0e-3), rng_id=777)
tsk = TrackingTask(BeamLine("RING", spec, DriftSpec(L=1.0)))
N = 20000
rep = Phase6DRep(zeros(N), zeros(N), zeros(N), zeros(N), zeros(N), zeros(N))
execute!(tsk, rep; turns=3)
h = hash((rep.x, rep.px, rep.y, rep.py, rep.z, rep.pz))
println("  nthreads = ", Threads.nthreads(), "  hash = ", h,
        "  sum|x| = ", sum(abs, rep.x))
println("done")
