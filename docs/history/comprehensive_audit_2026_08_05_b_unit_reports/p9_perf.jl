using Octopus
const O = Octopus

# Tight, type-stable loops: no closures, no tuple boxing.
function loop_xy(e, n)
    x, px, y, py, z, pz = 1.3e-3, 4.1e-4, -8.7e-4, -2.3e-4, 6.5e-4, 1.7e-3
    s = 0.0
    for i in 1:n
        a, b, c, d, f, g = Octopus.track_particle(Symplectic6DMap(), e, x, px, y, py, z, pz)
        s += a + b + c + d + f + g
        x = a * 1.0000000001
    end
    return s
end

e  = compile_runtime(XYCouplingSpec{Float64}(r1=0.031, r2=0.017, r3=-0.023, r4=0.041))
cr = compile_runtime(CrabDispersionSpec{Float64}(zeta1=0.11, zeta2=-0.07, zeta3=0.05, zeta4=0.03))
md = compile_runtime(MomentumDispersionSpec{Float64}(eta1=0.21, eta2=-0.13, eta3=0.09, eta4=-0.04))

const N = 50_000_000
for (name, el) in (("XYCoupling (recomputes inv(sqrt(...)) per particle)", e),
                   ("CrabDispersion (no sqrt)", cr),
                   ("MomentumDispersion (no sqrt)", md))
    loop_xy(el, 1000)                       # warm up / compile
    best = Inf
    for _ in 1:5
        t = time_ns(); loop_xy(el, N); best = min(best, (time_ns() - t) / N)
    end
    println(rpad(name, 54), " ", round(best, digits=3), " ns/particle (best of 5)")
end

# Isolate the sqrt: same map, g precomputed.
struct XYPre; r1::Float64; r2::Float64; r3::Float64; r4::Float64; g::Float64; end
@inline function trk(e::XYPre, x0, px0, y0, py0, z0, pz0)
    g = e.g
    (g*(x0 + e.r4*y0 - e.r2*py0), g*(px0 - e.r3*y0 + e.r1*py0),
     g*(-e.r1*x0 - e.r2*px0 + y0), g*(-e.r3*x0 - e.r4*px0 + py0), z0, pz0)
end
function loop_pre(e, n)
    x, px, y, py, z, pz = 1.3e-3, 4.1e-4, -8.7e-4, -2.3e-4, 6.5e-4, 1.7e-3
    s = 0.0
    for i in 1:n
        a, b, c, d, f, gg = trk(e, x, px, y, py, z, pz)
        s += a + b + c + d + f + gg
        x = a * 1.0000000001
    end
    return s
end
pre = XYPre(0.031, 0.017, -0.023, 0.041, inv(sqrt(1 + 0.031*0.041 - 0.017*(-0.023))))
loop_pre(pre, 1000)
best = Inf
for _ in 1:5
    t = time_ns(); loop_pre(pre, N); global best = min(best, (time_ns() - t) / N)
end
println(rpad("SAME map with g precomputed (control)", 54), " ", round(best, digits=3), " ns/particle (best of 5)")
