# Mutation controls for testset "Series helpers hold full precision across their
# crossovers" (test/runtests.jl 1586-1658). Each helper is re-implemented here in
# its RECORDED PRE-FIX form and the testset's own assertions are applied to it:
# if the assertion does not fail on the pre-fix form, the test guards nothing.
using Octopus
using ForwardDiff
using LinearAlgebra

relerr(v, ref) = Float64(abs((big(v) - ref) / ref))

# ---------------------------------------------------------------- U10-5 -----
# pre-fix _curv_vers: crossover 1e-4, series only through u^4 (the shape the
# sibling _curv_sin still uses).
@inline function curv_vers_old(h, L)
    u = h * L
    T = typeof(u)
    abs(u) < real(T)(1e-4) && return h * L * L / 2 * (one(T) - u * u / 12 * (one(T) - u * u / 30))
    return (one(T) - cos(u)) / h
end
vers_ref(h) = (1 - cos(big(h))) / big(h)

println("=== U10-5 _curv_vers ===")
for h in (1.001e-4, 1.0e-2)
    println("  h=", h, "  fixed relerr=", relerr(Octopus._curv_vers(h, 1.0), vers_ref(h)),
            "   PRE-FIX relerr=", relerr(curv_vers_old(h, 1.0), vers_ref(h)),
            "   bound 1e-15  -> pre-fix fails: ",
            !(relerr(curv_vers_old(h, 1.0), vers_ref(h)) < 1.0e-15))
end
for h in (prevfloat(0.125), nextfloat(0.125), 0.13, 0.15)
    println("  h=", h, "  fixed relerr=", relerr(Octopus._curv_vers(h, 1.0), vers_ref(h)),
            "   PRE-FIX relerr=", relerr(curv_vers_old(h, 1.0), vers_ref(h)),
            "   bound 1e-14")
end

# ---------------------------------------------------------------- U10-6 -----
# pre-fix _sol_log_over_h: series truncated at O(u^2), crossover 1e-4.
@inline function sol_log_old(h, x)
    u = h * x
    T = typeof(u)
    abs(u) < real(T)(1e-4) && return x * (one(T) - u / 2 * (one(T) - 2u / 3))
    return log1p(u) / h
end
log_ref(h) = log1p(big(h)) / big(h)
dlog_ref(h) = (1 / (1 + big(h)) / big(h)) - log1p(big(h)) / big(h)^2
g(h) = Octopus._sol_log_over_h(h, 1.0)
gold(h) = sol_log_old(h, 1.0)

println("\n=== U10-6 _sol_log_over_h ===")
for h in (1.001e-4, prevfloat(1.0e-2), nextfloat(1.0e-2), 2.0e-2)
    println("  h=", h)
    println("     value  fixed=", relerr(g(h), log_ref(h)),
            "  PRE-FIX=", relerr(gold(h), log_ref(h)), "   bound 1e-15")
    println("     deriv  fixed=", relerr(ForwardDiff.derivative(g, h), dlog_ref(h)),
            "  PRE-FIX=", relerr(ForwardDiff.derivative(gold, h), dlog_ref(h)),
            "   bound 1e-13")
end
println("  seam jump fixed  = ", abs(g(prevfloat(1e-2)) - g(nextfloat(1e-2))) / abs(g(1e-2)),
        "   bound 1e-15")
println("  seam jump PREFIX = ", abs(gold(prevfloat(1e-4)) - gold(nextfloat(1e-4))) / abs(gold(1e-4)),
        "  (at ITS OWN 1e-4 seam)")
println("  PRE-FIX evaluated at the seam the test uses (1e-2, both closed): ",
        abs(gold(prevfloat(1e-2)) - gold(nextfloat(1e-2))) / abs(gold(1e-2)))

# ---------------------------------------------------------------- U10-7 -----
println("\n=== U10-7 _wedge ===")
let A = 0.1, x = 1e-3, px = 2e-3, y = -1.5e-3, py = 1.2e-3, z = 5e-4, pz = 1e-3
    function wedge_ref(b1, ::Type{TT}) where {TT}
        Ab, b1b, xb, pxb, yb, pyb, zb, pzb = TT.((A, b1, x, px, y, py, z, pz))
        ps = sqrt((1 + pzb)^2 - pxb^2 - pyb^2)
        pxn = pxb * cos(Ab) + (ps - b1b * xb) * sin(Ab)
        w = sqrt((1 + pzb)^2 - pyb^2)
        psn = sqrt((1 + pzb)^2 - pxn^2 - pyb^2)
        xn = xb * cos(Ab) + (xb * pxb * sin(2Ab) + sin(Ab)^2 * (2xb * ps - b1b * xb^2)) /
                            (psn + ps * cos(Ab) - pxb * sin(Ab))
        D = (Ab + asin(pxb / w) - asin(pxn / w)) / b1b
        return xn, pxn, yb + pyb * D, pyb, zb - D * (1 + pzb), pzb
    end
    for b1 in (1e-6, 1e-8, 1e-10)
        o = Octopus._wedge(A, b1, x, px, y, py, z, pz)
        fixed = maximum(abs.(big.(collect(o)) .- collect(wedge_ref(b1, BigFloat))))
        old = maximum(abs.(big.(collect(wedge_ref(b1, Float64))) .-
                           collect(wedge_ref(b1, BigFloat))))
        println("  b1=", b1, "  fixed err=", Float64(fixed), "  PRE-FIX(closed Float64) err=",
                Float64(old), "   bound 1e-16  -> pre-fix fails: ", !(old < 1.0e-16))
    end
    r = collect(Octopus._rot_xz(A, x, px, y, py, z, pz))
    slope = maximum(abs.(collect(Octopus._wedge(A, 1e-3, x, px, y, py, z, pz)) .- r)) / 1e-3
    println("  slope = ", slope)
    for b1 in (1e-5, 1e-7, 1e-9)
        d = maximum(abs.(collect(Octopus._wedge(A, b1, x, px, y, py, z, pz)) .- r))
        println("  b1=", b1, "  d=", d, "  slope*b1=", slope * b1,
                "  rel dev=", abs(d - slope * b1) / (slope * b1), "  rtol 1e-3")
    end
    println("  b1=0 exactly equals _rot_xz: ",
            collect(Octopus._wedge(A, 0.0, x, px, y, py, z, pz)) == r)
    S6 = kron(Matrix{Float64}(I, 3, 3), [0.0 1.0; -1.0 0.0])
    for b1 in (0.3, 1e-8)
        J = zeros(6, 6)
        for j in 1:6
            v = ComplexF64[x, px, y, py, z, pz]
            v[j] += 1e-30im
            J[:, j] = imag.(collect(Octopus._wedge(A, b1, v...))) ./ 1e-30
        end
        println("  symplectic residual b1=", b1, " : ", maximum(abs, J' * S6 * J - S6),
                "  bound 1e-13")
    end
end

# --------------------------------------------------------- _atan_over seam --
println("\n=== _atan_over (testset 'bend map is cancellation-free', line ~1580) ===")
println("  crossover in src is 1e-4; test compares 1e-4±eps() -> straddles: ",
        (1.0e-4 - eps()) < 1.0e-4 <= (1.0e-4 + eps()))
println("  _atan_over(1e-5) = ", Octopus._atan_over(1.0e-5),
        "  1 - 1e-10/3 = ", 1.0 - 1.0e-10 / 3,
        "  relerr = ", abs(Octopus._atan_over(1.0e-5) - (1 - 1.0e-10 / 3)) / 1.0)
println("  seam jump = ", abs(Octopus._atan_over(1.0e-4 + eps()) - Octopus._atan_over(1.0e-4 - eps())))
