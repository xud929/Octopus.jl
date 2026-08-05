# U18 probe 5: several small measurements for the 2200-4400 region.
using Octopus, ForwardDiff, LinearAlgebra

println("=== (1) parallel thresholds vs the thread-invariance pin's n ===")
for s in (:_PIC_PARALLEL_DEPOSIT_MIN, :_STRONG_STRONG_PARALLEL_MOMENT_MIN,
          :_PIC_PARALLEL_KICK_MIN, :_SPECTRAL_PARALLEL_MIN)
    println("  ", s, " = ", isdefined(Octopus, s) ? getfield(Octopus, s) : "(undefined)")
end
println("  n=1500 with nslices=3 -> per-slice ~", 1500 ÷ 3)
println("  n=15000 with nslices=3 -> per-slice ~", 15000 ÷ 3)
println("  Threads.nthreads(:default) here = ", Threads.nthreads(:default))
println("  counts = unique((1,2,nthreads)) = ", unique((1, 2, Threads.nthreads(:default))))

println()
println("=== (2) Hessian scale / symmetry tolerance headroom (ForwardDiff testset) ===")
u = [1.0e-3, 1.0e-4, -0.5e-3, 2.0e-4, 0.0, 1.0e-3]
obj(p) = begin
    line = BeamLine("CELL",
        QuadrupoleSpec(L=0.4, k1=p[1], nst=4), DriftSpec(L=0.6),
        SBendSpec(L=1.1, h=p[2], b0=p[2], k1=0.3, e1=0.05, e2=0.05, nst=4),
        DriftSpec(L=0.6), QuadrupoleSpec(L=0.4, k1=-p[1], nst=4, x_offset=p[3]),
        DriftSpec(L=0.6))
    o = foldl((c, e) -> compile_runtime(e)(c...), line; init=Tuple(eltype(p).(u)))
    return o[1]^2 + o[3]^2
end
p0 = [1.7, 0.18, 1.0e-4]
H = ForwardDiff.hessian(obj, p0)
asym = maximum(abs, H .- H')
tol = 8 * eps() * max(1.0, maximum(abs, H))
println("  maximum(abs, H)      = ", maximum(abs, H))
println("  maximum(abs, H .- H')= ", asym)
println("  tolerance 8eps*max(1,|H|) = ", tol, "   headroom = ", tol / max(asym, eps(0.0)))
for (j, h) in ((1, 1e-5), (2, 1e-5), (3, 1e-7))
    e = zeros(3); e[j] = h
    fd = (ForwardDiff.gradient(obj, p0 .+ e) .- ForwardDiff.gradient(obj, p0 .- e)) ./ 2h
    rel = maximum(abs.(H[:, j] .- fd) ./ max.(abs.(fd), eps()))
    println("  column ", j, ": max relative FD disagreement = ", rel, "  (rtol asserted 1e-5)")
end

println()
println("=== (3) AD complex-step sweep: today's verified count vs the >= 25 floor ===")
verified = String[]
disagreed = String[]
caught = String[]
for meta in values(Octopus.ELEMENT_META_BY_KIND)
    sch = try Octopus.parameter_schema(meta.spec_type) catch; continue end
    for key in propertynames(sch)
        push!(caught, "$(meta.kind).$(key)")
    end
end
println("  (schema parameter total across kinds = ", length(caught), ")")

println()
println("=== (4) EveryNSteps planner timing assertion headroom ===")
s = EveryNSteps(start=0, stop=typemax(Int), step=1)
Octopus._scheduled_turns(s, 5, 10^8)
ts = [(@elapsed Octopus._scheduled_turns(s, 5, 10^8)) for _ in 1:5]
println("  @elapsed samples = ", ts, "   assertion: < 0.005")

println()
println("=== (5) contracts executed by the coverage-guard testset ===")
r = validate(PublicConfigurationEffectivenessContract())
println("  PublicConfigurationEffectivenessContract -> ", r.status)
println("=== (6) PTC contract status on this host ===")
rp = validate(PTCConsistencyContract())
println("  PTCConsistencyContract -> ", rp.status, "  cases=",
        get(rp.metrics, :cases, "n/a"))
