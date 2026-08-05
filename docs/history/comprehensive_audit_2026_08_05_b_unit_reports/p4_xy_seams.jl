using Octopus, Printf
include(joinpath(@__DIR__, "quadref.jl"))
const O = Octopus
setprecision(BigFloat, 220)

# ---------------------------------------------------------------- near-axis
println("=== near-axis switch: which SIDE is wrong? (vs independent quadrature) ===")
for eta in (1e-3, 1e-2, 0.1, 0.5, 0.9)
    v = (1e-3)^2
    s1 = sqrt(v * (1 + eta)); s2 = sqrt(v * (1 - eta))
    target = (eps(Float64) / sqrt(eta))^(1 / 7)
    fac = sqrt(1.25)
    xs = target / fac * s1
    ys = 0.5 * xs * s2 / s1
    for (tag, xq) in (("below(near-axis series)", xs * (1 - 1e-10)),
                      ("above(Faddeeva)", xs * (1 + 1e-10)))
        got = O._gaussian_beambeam_kick_response_principal(1.0, s1, s2, xq, ys)
        R = be_reference(s1, s2, xq, ys; panels=600)
        ref = (Float64(R[1]), Float64(R[2]), -Float64(R[3]), -Float64(R[4]), Float64(R[5]))
        @printf("  eta=%-6g %-24s relerr Kx=%.3e Ky=%.3e H1=%.3e H2=%.3e L/D=%.3e\n",
                eta, tag,
                abs(got[1] - ref[1]) / abs(ref[1]), abs(got[2] - ref[2]) / abs(ref[2]),
                abs(got[3] - ref[3]) / abs(ref[3]), abs(got[4] - ref[4]) / abs(ref[4]),
                abs(got[5] - ref[5]) / abs(ref[5]))
    end
end

# ---------------------------------------------------------- q = 2 moment seam
println()
println("=== _near_round_moments_0_6 / _3_11: q == 2 series<->recurrence seam ===")
for q in (2.0,)
    for h in (1e-12, 1e-14, 1e-16)
        below = O._near_round_moments_0_6(q - q * h)
        above = O._near_round_moments_0_6(q + q * h)
        w = maximum(abs.(above .- below) ./ abs.(below))
        below2 = O._near_round_moments_3_11(q - q * h)
        above2 = O._near_round_moments_3_11(q + q * h)
        w2 = maximum(abs.(above2 .- below2) ./ abs.(below2))
        @printf("  h=%.0e  max rel jump m0..m6 = %.3e   m3..m11 = %.3e\n", h, w, w2)
    end
    # absolute accuracy of each side vs BigFloat truth
    bmom(k, q) = Float64(cgl(u -> BigFloat(u)^k * exp(-BigFloat(q) * u), 400, BigFloat))
    for qq in (2.0 - 1e-13, 2.0 + 1e-13)
        m = O._near_round_moments_0_6(qq)
        e = maximum(abs(m[i + 1] - bmom(i, qq)) / abs(bmom(i, qq)) for i in 0:6)
        @printf("  q=%.15g  worst rel err vs BigFloat = %.3e\n", qq, e)
    end
end

# ------------------------------------------- u = 1e-2 round-Hessian seam
println()
println("=== _round_gaussian_hessian: u == 1e-2 series<->closed-form seam ===")
let sigma = 1e-3, kbb = 1.0
    ustar = 1.0e-2
    r2star = ustar * 2 * sigma^2
    for frac in (0.0, 0.25, 0.5)     # y^2/r^2 mix
        for h in (1e-12, 1e-14)
            for (tag, r2) in (("below", r2star * (1 - h)), ("above", r2star * (1 + h)))
                nothing
            end
            r2m = r2star * (1 - h); r2p = r2star * (1 + h)
            xm = sqrt(r2m * (1 - frac)); ym = sqrt(r2m * frac)
            xp = sqrt(r2p * (1 - frac)); yp = sqrt(r2p * frac)
            em = exp(-r2m / (2 * sigma^2)); ep = exp(-r2p / (2 * sigma^2))
            Hm = O._round_gaussian_hessian(kbb, sigma, xm, ym, em)
            Hp = O._round_gaussian_hessian(kbb, sigma, xp, yp, ep)
            rel = maximum(abs(Hp[i] - Hm[i]) / max(abs(Hm[i]), 1e-300) for i in 1:3)
            @printf("  frac=%.2f h=%.0e  max rel jump (Hxx,Hxy,Hyy) = %.3e\n", frac, h, rel)
        end
    end
    # accuracy of each side vs BigFloat
    println("  accuracy vs BigFloat evaluation of the same closed form:")
    for uu in (1.0e-2 * (1 - 1e-13), 1.0e-2 * (1 + 1e-13))
        r2 = uu * 2 * sigma^2
        x = sqrt(r2 * 0.75); y = sqrt(r2 * 0.25)
        e = exp(-r2 / (2 * sigma^2))
        H = O._round_gaussian_hessian(kbb, sigma, x, y, e)
        B = let X = BigFloat(x), Y = BigFloat(y), S = BigFloat(sigma)
            R2 = X * X + Y * Y
            U = R2 / (2 * S * S)
            E = exp(-U)
            f = 2 * (1 - E) / R2
            fp = 2 * (E * U - (1 - E)) / (R2 * R2)
            (-(f + 2 * X * X * fp), -(2 * X * Y * fp), -(f + 2 * Y * Y * fp))
        end
        @printf("    u=%.15g rel err = (%.3e, %.3e, %.3e)\n", uu,
                abs(H[1] - Float64(B[1])) / abs(Float64(B[1])),
                abs(H[2] - Float64(B[2])) / abs(Float64(B[2])),
                abs(H[3] - Float64(B[3])) / abs(Float64(B[3])))
    end
end

# ------------------------------------------------- H1 + H2 divergence identity
println()
println("=== exact identity H1 + H2 == -2*kbb*expterm/(sig1*sig2) (Poisson) ===")
worst = 0.0; wat = ()
for eta in (0.0, 1e-6, 2.2e-4, 3.3e-4, 4.4e-4, 1e-3, 0.01, 0.3, 0.7, 0.99)
    v = (1e-3)^2
    s1 = sqrt(v * (1 + eta)); s2 = sqrt(v * (1 - eta))
    for (px, py) in ((0.001, 0.001), (0.3, 0.2), (1.0, 0.7), (3.0, 2.0), (6.0, 5.0))
        x = px * sqrt(v); y = py * sqrt(v)
        K = O._gaussian_beambeam_kick_response_principal(1.0, s1, s2, x, y)
        expt = exp(-0.5 * (x * x / (s1 * s1) + y * y / (s2 * s2)))
        want = -2 * expt / (s1 * s2)
        rel = abs((K[3] + K[4]) - want) / max(abs(want), 1e-300)
        if rel > worst; worst = rel; wat = (eta, px, py, K[3] + K[4], want); end
    end
end
@printf("  worst rel violation = %.3e at eta=%g (x,y)/sig=(%g,%g): got %.10e want %.10e\n",
        worst, wat[1], wat[2], wat[3], wat[4], wat[5])

# --------------------------------------------------- sigx >= sigy wrapper seam
println()
println("=== gaussian_beambeam_kick: sigx >= sigy wrapper seam at sigx == sigy ===")
let s = 1e-3, x = 3e-4, y = 2e-4
    for h in (0.0, 1e-16, 1e-14, 1e-12)
        a = O.gaussian_beambeam_kick(s * (1 + h), s, x, y)
        b = O.gaussian_beambeam_kick(s, s * (1 + h), x, y)
        @printf("  h=%.0e  sigx>sigy: (%.17e, %.17e)\n", h, a[1], a[2])
        @printf("          sigy>sigx: (%.17e, %.17e)  rel diff (%.3e, %.3e)\n",
                b[1], b[2], abs(a[1] - b[1]) / abs(a[1]), abs(a[2] - b[2]) / abs(a[2]))
    end
end
