using Octopus, Printf
include(joinpath(@__DIR__, "quadref.jl"))
const O = Octopus
setprecision(BigFloat, 260)

# TRUE branch jump = evaluate the two branches at (essentially) the SAME point:
# q = 2.0 (series side) vs q = nextfloat(2.0) (recurrence side).  One ulp of q
# accounts for <= 5e-16 relative smooth variation, so anything larger is the
# branch discontinuity itself.
println("=== q == 2 seam in _near_round_moments_* : TRUE jump (1 ulp apart) ===")
bmom(k, q) = cgl(u -> u^BigFloat(k) * exp(-BigFloat(q) * u), 400, BigFloat)
let q = 2.0, qp = nextfloat(2.0)
    a = O._near_round_moments_0_6(q)     # series branch
    b = O._near_round_moments_0_6(qp)    # recurrence branch
    println("  _near_round_moments_0_6:")
    for k in 0:6
        t = Float64(bmom(k, q))
        @printf("    m%-2d series=%.17e  recur=%.17e  jump=%.3e | err(series)=%.3e err(recur)=%.3e\n",
                k, a[k+1], b[k+1], abs(b[k+1] - a[k+1]) / abs(a[k+1]),
                abs(a[k+1] - t) / abs(t), abs(b[k+1] - t) / abs(t))
    end
    a2 = O._near_round_moments_3_11(q)
    b2 = O._near_round_moments_3_11(qp)
    println("  _near_round_moments_3_11:")
    for (i, k) in enumerate(3:11)
        t = Float64(bmom(k, q))
        @printf("    m%-2d series=%.17e  recur=%.17e  jump=%.3e | err(series)=%.3e err(recur)=%.3e\n",
                k, a2[i], b2[i], abs(b2[i] - a2[i]) / abs(a2[i]),
                abs(a2[i] - t) / abs(t), abs(b2[i] - t) / abs(t))
    end
end
println("  recurrence accuracy away from the seam (m11):")
for q in (2.0, 3.0, 5.0, 10.0, 20.0, 50.0)
    b2 = O._near_round_moments_3_11(nextfloat(q))
    t = Float64(bmom(11, q))
    @printf("    q=%-5g m11 recur=%.17e truth=%.17e rel err=%.3e\n", q, b2[9], t,
            abs(b2[9] - t) / abs(t))
end

# --------------------------------------------------- u = 1e-2 round-Hessian
println()
println("=== u == 1e-2 seam in _round_gaussian_hessian: TRUE jump (1 ulp apart) ===")
let sigma = 1e-3, kbb = 1.0
    for frac in (0.0, 0.25, 0.5)
        u = 1.0e-2
        r2 = u * 2 * sigma^2
        r2p = nextfloat(r2)
        f(r2v) = begin
            x = sqrt(r2v * (1 - frac)); y = sqrt(r2v * frac)
            O._round_gaussian_hessian(kbb, sigma, x, y, exp(-r2v / (2 * sigma^2)))
        end
        A = f(r2); B = f(r2p)
        truth = let X = BigFloat(sqrt(r2 * (1 - frac))), Y = BigFloat(sqrt(r2 * frac)),
                    S = BigFloat(sigma)
            R2 = X * X + Y * Y; U = R2 / (2 * S * S); E = exp(-U)
            ff = 2 * (1 - E) / R2
            fp = 2 * (E * U - (1 - E)) / (R2 * R2)
            (Float64(-(ff + 2 * X * X * fp)), Float64(-(2 * X * Y * fp)),
             Float64(-(ff + 2 * Y * Y * fp)))
        end
        for (i, nm) in enumerate(("Hxx", "Hxy", "Hyy"))
            truth[i] == 0 && continue
            @printf("  frac=%.2f %-4s series=%.17e closed=%.17e jump=%.3e | err(series)=%.3e err(closed)=%.3e\n",
                    frac, nm, A[i], B[i], abs(B[i] - A[i]) / max(abs(A[i]), 1e-300),
                    abs(A[i] - truth[i]) / abs(truth[i]), abs(B[i] - truth[i]) / abs(truth[i]))
        end
    end
end

# ------------------------------------------- near-axis TRUE jump (same point)
println()
println("=== near-axis rho^7 seam: TRUE jump, both branches at the SAME point ===")
for eta in (1e-3, 1e-2, 0.1, 0.5, 0.9)
    v = (1e-3)^2
    s1 = sqrt(v * (1 + eta)); s2 = sqrt(v * (1 - eta))
    target = (eps(Float64) / sqrt(eta))^(1 / 7)
    fac = sqrt(1.25)
    x = target / fac * s1
    y = 0.5 * x * s2 / s1
    # branch A: near-axis polynomial
    Ax, Ay, AH1, AH2 = O._elliptic_gaussian_near_axis_response(1.0, s1, s2, x, y)
    # branch B: Faddeeva.  Force it by inlining the same body without the switch.
    Bx, By = let T = Float64
        den = sqrt(2.0) * sqrt(s1 * s1 - s2 * s2)
        z1 = complex(x / den, y / den)
        z2 = complex(s2 / s1 * x / den, s1 / s2 * y / den)
        A = 2 * sqrt(pi) / den
        Bfac = exp(-x * x / (2 * s1 * s1) - y * y / (2 * s2 * s2))
        ret = A * (O.faddeeva_w(z1) - Bfac * O.faddeeva_w(z2))
        (imag(ret), real(ret))
    end
    expt = exp(-0.5 * (x * x / (s1 * s1) + y * y / (s2 * s2)))
    BH1, BH2 = O._elliptic_gaussian_hessian_diagonal(1.0, s1, s2, x, y, Bx, By, expt)
    R = be_reference(s1, s2, x, y; panels=600)
    ref = (Float64(R[1]), Float64(R[2]), -Float64(R[3]), -Float64(R[4]))
    got = ((Ax, Bx), (Ay, By), (AH1, BH1), (AH2, BH2))
    @printf("  eta=%-6g rho_seam=%.4e\n", eta, target)
    for (i, nm) in enumerate(("Kx", "Ky", "H1", "H2"))
        a, b = got[i]
        @printf("    %-3s nearaxis=%.17e faddeeva=%.17e JUMP=%.3e | err(na)=%.3e err(fad)=%.3e\n",
                nm, a, b, abs(b - a) / max(abs(a), 1e-300),
                abs(a - ref[i]) / abs(ref[i]), abs(b - ref[i]) / abs(ref[i]))
    end
end

# ------------------------------------------------- H1 + H2 divergence identity
println()
println("=== exact Poisson identity H1 + H2 == -2*kbb*expterm/(sig1*sig2) ===")
let worst = 0.0, wat = (0.0, 0.0, 0.0, 0.0, 0.0)
    for eta in (0.0, 1e-8, 1e-6, 1e-4, 2.2e-4, 3.3e-4, 4.4e-4, 5e-4, 1e-3, 0.01, 0.3, 0.7, 0.99)
        v = (1e-3)^2
        s1 = sqrt(v * (1 + eta)); s2 = sqrt(v * (1 - eta))
        for (px, py) in ((0.001, 0.001), (0.05, 0.03), (0.3, 0.2), (1.0, 0.7), (3.0, 2.0), (6.0, 5.0))
            x = px * sqrt(v); y = py * sqrt(v)
            K = O._gaussian_beambeam_kick_response_principal(1.0, s1, s2, x, y)
            expt = exp(-0.5 * (x * x / (s1 * s1) + y * y / (s2 * s2)))
            want = -2 * expt / (s1 * s2)
            rel = abs((K[3] + K[4]) - want) / max(abs(want), 1e-300)
            if rel > worst
                worst = rel; wat = (eta, px, py, K[3] + K[4], want)
            end
        end
    end
    @printf("  worst rel violation = %.3e at eta=%g (x,y)/sig=(%g,%g): got %.10e want %.10e\n",
            worst, wat[1], wat[2], wat[3], wat[4], wat[5])
end

# ------------------------------------------ sigx >= sigy wrapper symmetry seam
println()
println("=== gaussian_beambeam_kick wrapper: sigx>=sigy vs sigy>sigx at the seam ===")
let s = 1e-3, x = 3e-4, y = 2e-4
    for h in (0.0, 1e-16, 1e-15, 1e-13)
        a = O.gaussian_beambeam_kick(s * (1 + h), s, x, y)
        b = O.gaussian_beambeam_kick(s, s * (1 + h), x, y)
        @printf("  h=%.0e  A=(%.17e,%.17e)\n           B=(%.17e,%.17e) rel=(%.3e,%.3e)\n",
                h, a[1], a[2], b[1], b[2],
                abs(a[1] - b[1]) / abs(a[1]), abs(a[2] - b[2]) / abs(a[2]))
    end
end

# ---------------------------------------------------------- limiting cases
println()
println("=== limiting cases ===")
@printf("  sigx==sigy exactly, on axis (0,0): %s\n",
        string(O.gaussian_beambeam_kick(1e-3, 1e-3, 0.0, 0.0)))
@printf("  elliptical, on axis (0,0):        %s\n",
        string(O.gaussian_beambeam_kick(2e-3, 1e-3, 0.0, 0.0)))
@printf("  sigy == 0 (line charge!):         %s   [true field 2x/r^2 = %g]\n",
        string(O.gaussian_beambeam_kick(1e-3, 0.0, 1e-4, 1e-4)),
        2 * 1e-4 / (2e-8))
@printf("  sigx == 0:                        %s\n",
        string(O.gaussian_beambeam_kick(0.0, 1e-3, 1e-4, 1e-4)))
@printf("  sigy = 1e-300 (denormal-ish):     %s\n",
        string(O.gaussian_beambeam_kick(1e-3, 1e-300, 1e-4, 1e-4)))
@printf("  large amplitude 50 sigma round:   %s  [asymptote 2x/r^2 = %g]\n",
        string(O.gaussian_beambeam_kick(1e-3, 1e-3, 5e-2, 0.0)), 2 * 5e-2 / 2.5e-3)
@printf("  large amplitude 50 sigma ellipt:  %s  [asymptote %g]\n",
        string(O.gaussian_beambeam_kick(2e-3, 1e-3, 1e-1, 0.0)), 2 * 1e-1 / 1e-2)
@printf("  negative x,y round:               %s\n",
        string(O.gaussian_beambeam_kick(1e-3, 1e-3, -3e-4, -2e-4)))
@printf("  negative x,y elliptical:          %s\n",
        string(O.gaussian_beambeam_kick(2e-3, 1e-3, -3e-4, -2e-4)))
@printf("  antisymmetry check elliptical:    %s\n",
        string(O.gaussian_beambeam_kick(2e-3, 1e-3, 3e-4, 2e-4) .+
               O.gaussian_beambeam_kick(2e-3, 1e-3, -3e-4, -2e-4)))
@printf("  extreme flat sigy/sigx=1e-6:      %s\n",
        string(O.gaussian_beambeam_kick(1e-3, 1e-9, 1e-4, 1e-9)))
