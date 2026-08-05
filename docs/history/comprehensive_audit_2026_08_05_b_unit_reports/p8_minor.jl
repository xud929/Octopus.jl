using Octopus
const O = Octopus

println("="^110)
println("A. XYCoupling convenience constructor: strict same-type signature")
println("="^110)
for args in ((0.01, 0.0, 0.0, 0.0), (0.01, 0, 0, 0), (1//100, 0.0, 0.0, 0.0))
    try
        e = XYCoupling(args...)
        println("  XYCoupling", args, " -> ok  ", typeof(e))
    catch err
        println("  XYCoupling", args, " -> FAIL ", string(typeof(err)), ": ",
                first(sprint(showerror, err), 90))
    end
end
println("  spec path (promotes correctly):")
println("    ", typeof(compile_runtime(XYCouplingSpec(r1=0.01, r2=0, r3=0, r4=0))))

println("\n" * "="^110)
println("B. XYCoupling: `g = inv(sqrt(1 + r1 r4 - r2 r3))` is recomputed for EVERY particle")
println("="^110)
e = compile_runtime(XYCouplingSpec{Float64}(r1=0.031, r2=0.017, r3=-0.023, r4=0.041))
u = (1.3e-3, 4.1e-4, -8.7e-4, -2.3e-4, 6.5e-4, 1.7e-3)
crab = compile_runtime(CrabDispersionSpec{Float64}(zeta1=0.11, zeta2=-0.07, zeta3=0.05, zeta4=0.03))
function bench(f, n)
    s = 0.0
    f(u...)                                  # warm up
    t = time_ns()
    for _ in 1:n
        s += f(u...)[1]
    end
    return (time_ns() - t) / n, s
end
tx, _ = bench((a...) -> e(a...), 3_000_000)
tc, _ = bench((a...) -> crab(a...), 3_000_000)
println("  XYCoupling      : ", round(tx, digits=3), " ns/particle")
println("  CrabDispersion  : ", round(tc, digits=3), " ns/particle  (same shape, no sqrt)")
println("  difference      : ", round(tx - tc, digits=3), " ns/particle")

println("\n  domain: 1 + r1 r4 - r2 r3 < 0 gives a bare DomainError with no element context")
bad = compile_runtime(XYCouplingSpec{Float64}(r1=2.0, r2=0.0, r3=0.0, r4=-1.0))
try
    bad(u...)
catch err
    println("    ", string(typeof(err)), ": ", first(sprint(showerror, err), 130))
end

println("\n" * "="^110)
println("C. solenoid `nst` ParamMeta default vs the compile-path default")
println("="^110)
sch = parameter_schema(ElementSpec{:solenoid})
println("  ParamMeta default declared      : ", sch[:nst].default)
println("  actual default, straight (h=0)  : ", Solenoid(SolenoidSpec(L=1.3, ks=1.7)).nst)
println("  actual default, curved (h=0.18) : ", Solenoid(SolenoidSpec(L=1.3, ks=1.7, h=0.18)).nst)

println("\n" * "="^110)
println("D. `_curv_vers` seam vs its own recorded bound (comment says closed side <= 5.9e-15 on [0.125,0.5])")
println("="^110)
setprecision(BigFloat, 400)
rel(g, e) = Float64(abs(BigFloat(g) - e) / abs(e))
function worst(lo, hi, n)
    b = 0.0; bu = lo
    for k in 0:n
        u = lo + (hi - lo) * k / n
        v = rel(O._curv_vers(u, 1.0), (1 - cos(BigFloat(u))) / BigFloat(u))
        v > b && ((b, bu) = (v, u))
    end
    (b, bu)
end
b, bu = worst(0.125, 0.5, 400000)
println("  measured closed-branch max relerr on [0.125, 0.5] = ", b, " at u = ", bu)
println("  recorded in the source comment                    = 5.9e-15")
