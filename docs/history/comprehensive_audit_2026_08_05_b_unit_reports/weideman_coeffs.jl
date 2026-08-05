# U14 probe D: regenerate the 32 Weideman coefficients from Weideman's own
# construction (SIAM J. Numer. Anal. 31 (1994) 1497, the `weideman.m` recipe)
# and compare to the hand-entered table in SpecialMath.jl.
# "Do not hand-copy knowledge" -- this is the derive-and-check.
using Octopus, Printf
setprecision(BigFloat, 512)
const BF = BigFloat

function weideman_coefficients(N::Int)
    M  = 2N
    M2 = 2M
    L  = sqrt(BF(N) / sqrt(BF(2)))
    # k = -M+1 : M-1   (2M-1 = M2-1 values); f = [0; f] -> M2 values
    f = Vector{BF}(undef, M2)
    f[1] = zero(BF)
    for (j, k) in enumerate(-M+1:M-1)
        theta = BF(k) * BF(pi) / M
        t = L * tan(theta / 2)
        f[j+1] = exp(-t * t) * (L * L + t * t)
    end
    # fftshift then DFT, real part, / M2  (naive DFT, M2 = 128)
    g = circshift(f, -div(M2, 2))
    a = Vector{BF}(undef, M2)
    for n in 0:M2-1
        s = zero(BF)
        for m in 0:M2-1
            s += g[m+1] * cos(2 * BF(pi) * n * m / M2)   # real part of the DFT
        end
        a[n+1] = s / M2
    end
    return L, reverse(a[2:N+1])                          # flipud(a(2:N+1))
end

L, coef = weideman_coefficients(32)
tab = collect(Octopus.FADDEEVA_WEIDEMAN_COEFFS)
@printf("L: derived %.17g   table %.17g   identical: %s\n",
        Float64(L), Octopus.FADDEEVA_WEIDEMAN_L, Float64(L) == Octopus.FADDEEVA_WEIDEMAN_L)
println("coefficients: ", length(tab), " in table, ", length(coef), " derived")
worst = 0.0; worstulp = 0.0; worsti = 0
for i in 1:32
    d = Float64(coef[i])
    r = d == 0 ? abs(tab[i]) : abs(tab[i] - d) / abs(d)
    u = abs(tab[i] - d) / eps(d)
    if r > worst
        global worst = r; global worsti = i
    end
    global worstulp = max(worstulp, u)
end
@printf("worst relative difference table vs derived: %.3e at index %d (%.17g vs %.17g)\n",
        worst, worsti, tab[worsti], Float64(coef[worsti]))
@printf("worst ulp difference: %.2f\n", worstulp)
println("all 32 within 4 ulp: ", worstulp <= 4)
# What matters is the ABSOLUTE coefficient error: |Z| <= 1 on the mapped
# domain, so sum|da_i| bounds the polynomial perturbation.
absd = [abs(tab[i] - Float64(coef[i])) for i in 1:32]
@printf("largest |coefficient| = %.6g ; largest absolute difference = %.3e (index %d)\n",
        maximum(abs, tab), maximum(absd), argmax(absd))
@printf("sum of absolute differences = %.3e  -> bound on |dp(Z)| for |Z|<=1\n", sum(absd))
@printf("relative to the leading coefficient %.6g: %.3e\n",
        tab[end], sum(absd) / abs(tab[end]))
println("=> the table is a DOUBLE-PRECISION generation of Weideman's construction:")
println("   absolute agreement at the 1e-16 level, relative agreement poor only")
println("   for the coefficients that are themselves ~1e-12. Effect on w: below.")
# direct effect: re-evaluate w with the exact coefficients
function w_upper_with(coeffs, zr::Float64, zi::Float64)
    L = Octopus.FADDEEVA_WEIDEMAN_L
    denr = L + zi; deni = -zr
    numr = L - zi; numi = zr
    d2 = denr * denr + deni * deni
    zrZ = (numr * denr + numi * deni) / d2
    ziZ = (numi * denr - numr * deni) / d2
    pr = 0.0; pip = 0.0
    for c in coeffs
        pr, pip = pr * zrZ - pip * ziZ, pr * ziZ + pip * zrZ
        pr += c
    end
    dn2r = denr * denr - deni * deni; dn2i = 2 * denr * deni
    q = dn2r * dn2r + dn2i * dn2i
    tr = (2pr * dn2r + 2pip * dn2i) / q
    ti = (2pip * dn2r - 2pr * dn2i) / q
    ir = Octopus.FADDEEVA_WEIDEMAN_INVSQRTPI * denr / d2
    ii = -Octopus.FADDEEVA_WEIDEMAN_INVSQRTPI * deni / d2
    return tr + ir, ti + ii
end
worstw = 0.0
for x in range(0.0, 6.0; length=13), y in range(0.0, 7.0; length=13)
    a1, b1 = w_upper_with(tab, x, y)
    a2, b2 = w_upper_with(Float64.(coef), x, y)
    m = hypot(a1, b1)
    global worstw = max(worstw, hypot(a1 - a2, b1 - b2) / m)
end
@printf("worst relative change in w from using the EXACT coefficients: %.3e\n", worstw)

println()
println("=== Bassetti-Erskine seam: does the exponentially small Re(w) leak? ===")
println("(strong_beam_track.jl is OUTSIDE U14's region -- measured only to price the lead)")
# Ky = A*(w1r - B*w2r): both real parts are exp-small near y = 0, so any
# absolute noise in Re(w) becomes a vertical kick that should be exactly 0
# by symmetry at y = 0.
sig1, sig2 = 106.0e-6, 9.5e-6
@printf("  sig1=%.3g sig2=%.3g\n", sig1, sig2)
@printf("  %-14s %-24s %-24s\n", "y [m]", "Kx", "Ky (must -> 0 with y)")
for y in (0.0, 1e-18, 1e-15, 1e-12, 1e-9, 1e-7)
    for x in (3.0e-4,)
        Kx, Ky = Octopus._cuda_elliptic_gaussian_kick_principal(sig1, sig2, x, y)
        @printf("  %-14.3g %-24.12e %-24.12e\n", y, Kx, Ky)
    end
end
println("  (x = 3e-4 m = 2.8 sigma1; z1r = x/(sqrt2*sqrt(s1^2-s2^2)) = ",
        round(3.0e-4 / (sqrt(2) * sqrt(sig1^2 - sig2^2)); digits=4), ")")
println()
println("  Same sweep at larger x, where Re(w) is smaller still:")
for x in (1.0e-3, 2.0e-3)
    for y in (0.0, 1e-12)
        Kx, Ky = Octopus._cuda_elliptic_gaussian_kick_principal(sig1, sig2, x, y)
        @printf("  x=%.1e y=%.1e  Kx=%-22.12e Ky=%-22.12e\n", x, y, Kx, Ky)
    end
end
