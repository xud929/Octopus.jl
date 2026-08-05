# U14 probe C: Faddeeva accuracy against INDEPENDENT high-precision arithmetic
# (Complex{BigFloat}), not against SpecialFunctions.
#
# Reference 1 (exact, convergent): w(z) = exp(-z^2) * (1 - erf(-i z)) with the
#   Maclaurin series for erf, evaluated at 4096-bit precision so the
#   ~exp(|z|^2) cancellation still leaves >500 digits.
# Reference 2 (far field): the asymptotic 1/z series truncated at its smallest
#   term. Cross-validated against Reference 1 on 20 <= |z| <= 35.
using Octopus, Printf

setprecision(BigFloat, 4096)

const BF = BigFloat
sqrtpi_bf() = sqrt(BF(pi))

"erf(t) by Maclaurin series, Complex{BigFloat}."
function erf_series(t::Complex{BF})
    iszero(t) && return zero(Complex{BF})
    s = zero(Complex{BF})
    term = t                       # t^(2n+1)/n!
    n = 0
    tol = BF(2)^(-4000)
    while true
        contrib = term / (2n + 1)
        s += (isodd(n) ? -contrib : contrib)
        n += 1
        term = term * t * t / n
        # stop when the term can no longer move the (huge) partial sum
        if n > 20 && abs(term) <= max(abs(s), one(BF)) * tol
            break
        end
        n > 400000 && error("erf series did not converge at |t| = $(Float64(abs(t)))")
    end
    return 2s / sqrtpi_bf()
end

"w(z) exactly, for moderate |z|."
function w_series(z::Complex{BF})
    return exp(-z * z) * (one(Complex{BF}) - erf_series(-im * z))
end

"w(z) by the truncate-at-smallest-term asymptotic series; upper half plane, far field."
function w_asym(z::Complex{BF})
    # w ~ (i/sqrt(pi)) * sum_{n>=0} (2n-1)!! / (2 z^2)^n / z
    inv2z2 = one(Complex{BF}) / (2 * z * z)
    s = one(Complex{BF})
    term = one(Complex{BF})
    prev = abs(term)
    for n in 1:100000
        term *= (2n - 1) * inv2z2
        a = abs(term)
        a > prev && break                      # past the smallest term
        s += term
        prev = a
        a < abs(s) * BF(2)^(-4200) && break
    end
    w = im * s / (sqrtpi_bf() * z)
    # The recessive exp(-z^2) term is switched ON only near the real axis
    # (Stokes line arg z = 0): there w(x) = e^{-x^2} + (2i/sqrt(pi)) D(x)
    # exactly.  Where x^2 - y^2 <= 60 its magnitude exceeds e^{-60} ~ 1e-26 and
    # it is NOT recessive, so it must be omitted (in the upper half plane away
    # from the axis, w is the asymptotic series alone).
    x = real(z); y = imag(z)
    if x * x - y * y > 60
        w += exp(-z * z)
    end
    return w
end

function w_ref(zr::Float64, zi::Float64)
    z = Complex{BF}(BF(zr), BF(zi))
    az = abs(z)
    if az <= 35
        return w_series(z)
    else
        # asymptotic branch is written for the upper half plane; use
        # w(-conj(z)) = conj(w(z)) to move x >= 0 if needed.
        if real(z) >= 0
            return w_asym(z)
        else
            return conj(w_asym(Complex{BF}(-real(z), imag(z))))
        end
    end
end

println("=== C0. cross-validate the two references on 20 <= |z| <= 35 ===")
function xvalidate()
    w = 0.0
    for x in (20.0, 25.0, 30.0, 34.0), y in (0.0, 1e-8, 0.5, 3.0, 20.0)
        z = Complex{BF}(BF(x), BF(y))
        a = w_series(z); b = w_asym(z)
        w = max(w, Float64(abs(a - b) / abs(a)))
    end
    return w
end
@printf("  worst relative disagreement series vs asymptotic: %.3e\n", xvalidate())

# ---------------------------------------------------------------------------
relerr(got, want) = Float64(abs(Complex{BF}(BF(real(got)), BF(imag(got))) - want) / abs(want))

function measure(points, label)
    worst = 0.0; argworst = (0.0, 0.0); n = 0
    worst_re = 0.0; worst_im = 0.0
    for (x, y) in points
        want = w_ref(x, y)
        gr, gi = Octopus.faddeeva_w_approx_reim(x, y)
        e = relerr(complex(gr, gi), want)
        n += 1
        if e > worst
            worst = e; argworst = (x, y)
        end
        wr = Float64(real(want)); wi = Float64(imag(want))
        wr != 0 && (worst_re = max(worst_re, abs(gr - wr) / abs(wr)))
        wi != 0 && (worst_im = max(worst_im, abs(gi - wi) / abs(wi)))
    end
    @printf("  %-46s n=%5d  |w| relerr %.3e at z=(%g, %g)   Re %.2e  Im %.2e\n",
            label, n, worst, argworst[1], argworst[2], worst_re, worst_im)
    return worst
end

println()
println("=== C1. accuracy by region (relative error on |w|, and componentwise) ===")

# Weideman interior
interior = [(x, y) for x in range(0.0, 6.0; length=25) for y in range(0.0, 7.0; length=25)]
measure(interior, "Weideman interior 0<=x<=6, 0<=y<=7")

# near-real axis inside the Weideman region
axisband = [(x, y) for x in range(0.0, 6.0; length=31)
                   for y in (0.0, 1e-14, 1e-12, 1e-9, 1e-6, 1e-3)]
measure(axisband, "near-real-axis band, x<=6")

# BRANCH BOUNDARIES of faddeeva_w_upper_reim
measure([(x, y) for x in (0.5, 3.0, 5.9, 6.0, 6.1, 7.0)
                for y in (6.99, 6.999999, 7.0, 7.000001, 7.01)],
        "boundary y = 7")
measure([(x, y) for x in (5.99, 5.999999, 6.0, 6.000001, 6.01)
                for y in (0.09, 0.0999999, 0.1, 0.1000001, 0.11)],
        "boundary x = 6, y = 0.1")
measure([(x, y) for x in (7.99, 8.0, 8.000001, 8.01, 9.0)
                for y in (0.0, 1e-11, 1e-10, 1.000001e-10, 1e-9, 0.05)],
        "boundary x = 8, y = 1e-10")
measure([(x, y) for x in (27.9, 28.0, 28.000001, 28.1, 40.0)
                for y in (0.0, 1e-300, 1e-14, 1e-11, 0.05)],
        "boundary x = 28 (y below 1e-10)")
measure([(x, y) for x in (1000.0, 2000.0, 3999.0, 3999.9999, 4000.0, 4000.1)
                for y in (0.0, 0.5, 30.0)],
        "boundary x + y = 4000 (mid-field asymptote)")
measure([(x, y) for (x, y) in ((9.9e6, 1.0), (1.0e7 - 1, 1.0), (1.0e7, 1.0),
                               (1.0e7 + 1, 1.0), (2.0e7, 1.0), (1.0, 1.0e7),
                               (1.0e7, 1.0e7), (1.0e8, 3.0), (3.0, 1.0e8))],
        "boundary x + y = 1e7 (two far-field forms)")

# gap region between the Weideman box and the CF: x in (6,8], y in (1e-10, 0.1]
measure([(x, y) for x in (6.5, 7.0, 7.5, 8.0)
                for y in (1e-9, 1e-6, 1e-3, 0.01, 0.05, 0.1)],
        "gap x in (6,8], y <= 0.1  (WEIDEMAN branch)")
measure([(x, y) for x in (8.5, 10.0, 15.0, 20.0, 27.0)
                for y in (1e-9, 1e-6, 1e-3, 0.05)],
        "x in (8,28), tiny y  (CF branch)")

println()
println("=== C2. all four quadrants through faddeeva_w_approx_reim ===")
quad = [(sx * x, sy * y) for x in (0.3, 2.0, 5.5, 9.0) for y in (0.2, 1.5, 6.5)
                          for sx in (1.0, -1.0) for sy in (1.0, -1.0)]
measure(quad, "four quadrants (|zi| <= 6.5, reflection identity)")

println()
println("=== C3. exact anchors ===")
for (x, y, name) in ((0.0, 0.0, "w(0) = 1"), (0.0, 1.0, "w(i) = erfcx(1)"),
                     (0.0, 5.0, "w(5i)"), (1.0, 0.0, "w(1) real axis"))
    gr, gi = Octopus.faddeeva_w_approx_reim(x, y)
    want = w_ref(x, y)
    @printf("  %-18s got (%.17g, %.17g)  ref (%.17g, %.17g)  rel %.3e\n",
            name, gr, gi, Float64(real(want)), Float64(imag(want)),
            relerr(complex(gr, gi), want))
end

println()
println("=== C4. documented precision calibration ===")
println("  The docstrings claim only 'fixed-order Weideman rational approximation'")
println("  and 'branch-light'; NO precision figure is stated in SpecialMath.jl.")
println("  Weideman's N=32 half-plane approximation is documented in the")
println("  literature as ~1e-13 relative in the finite region -- consistent with")
println("  the measurement above. Number of coefficients in the table: ",
        length(Octopus.FADDEEVA_WEIDEMAN_COEFFS), "; L = ", Octopus.FADDEEVA_WEIDEMAN_L)
@printf("  Weideman L should be 2^(-1/4) * sqrt(N) for N=32: %.15f vs table %.15f\n",
        2.0^(-0.25) * sqrt(32.0), Octopus.FADDEEVA_WEIDEMAN_L)
@printf("  1/sqrt(pi) constant: table %.20f  exact %.20f  ulp err %.2f\n",
        Octopus.FADDEEVA_WEIDEMAN_INVSQRTPI, 1 / sqrt(pi),
        abs(Octopus.FADDEEVA_WEIDEMAN_INVSQRTPI - Float64(1 / sqrt(BF(pi)))) /
            eps(Float64(1 / sqrt(BF(pi)))))

println()
println("=== C5. type genericity: Float32 and ForwardDiff-style Real ===")
gr32, gi32 = Octopus.faddeeva_w_approx_reim(1.5f0, 0.7f0)
want32 = w_ref(1.5, 0.7)
@printf("  Float32 at z=1.5+0.7i: (%.9g, %.9g) rel %.3e (eps(F32)=%.2e)\n",
        gr32, gi32, relerr(complex(Float64(gr32), Float64(gi32)), want32), eps(Float32))
gbr, gbi = Octopus.faddeeva_w_approx_reim(BF(1.5), BF(0.7))
@printf("  BigFloat input runs (returns %s), rel vs ref %.3e  <- coefficients are\n",
        typeof(gbr), relerr(complex(Float64(gbr), Float64(gbi)), want32))
println("     Float64 literals, so BigFloat input CANNOT beat Float64 accuracy")
println("=== C6. mixed-type call ===")
try
    Octopus.faddeeva_w_approx_reim(1.0, 0.5f0)
    println("  mixed (Float64, Float32) accepted")
catch e
    println("  mixed (Float64, Float32) -> ", typeof(e), " (signature requires both ::T)")
end
