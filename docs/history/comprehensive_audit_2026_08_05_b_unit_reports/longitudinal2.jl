# U14 probe F': longitudinal conditioning done right.
# The reference evaluates the SAME formula exactly in BigFloat with the code's
# own Float64 beta0/gamma0 promoted, so what is measured is the floating-point
# evaluation, not the rounding of the inputs.
using Octopus, Printf
setprecision(BigFloat, 256)
const BF = BigFloat
const C = (TIME_ENERGY, SIGMA_PSIGMA, PATHLENGTH_DELTA, TIME_DELTA)
const NAMES = ("TIME_ENERGY", "SIGMA_PSIGMA", "PATHLENGTH_DELTA", "TIME_DELTA")

exact_delta(pt, b0, g0) = -1 + sqrt((1 / BF(b0) + BF(pt))^2 - (1 / (BF(b0) * BF(g0)))^2)
exact_pt(d, b0, g0) = -1 / BF(b0) + sqrt((1 + BF(d))^2 + (1 / (BF(b0) * BF(g0)))^2)

println("=== G1. delta = -1 + sqrt(...) : relative accuracy vs amplitude ===")
println("  reference = same expression, exact in BigFloat, same Float64 beta0/gamma0")
@printf("  %-12s %-10s %14s %14s %14s\n", "E0 [GeV]", "pt", "delta", "rel err code", "rel err stable")
for (E0, mc2, lbl) in ((10.0e9, Octopus.EMASS_EV, "10 e-"), (2.5e9, Octopus.PMASS_EV, "2.5 p"))
    b0, g0 = reference_beta_gamma(E0, mc2)
    for pt in (1e-1, 1e-2, 1e-4, 1e-6, 1e-8, 1e-10, 1e-12)
        dref = exact_delta(pt, b0, g0)
        d = Octopus._delta_from_pt(pt, b0, g0)
        u = 2 * pt / b0 + pt * pt                     # exact identity 1/b0^2 - 1/(b0 g0)^2 = 1
        dst = u / (sqrt(1 + u) + 1)
        @printf("  %-12s %-10.0e %14.6e %14.3e %14.3e\n", lbl, pt, d,
                Float64(abs(BF(d) - dref) / abs(dref)),
                Float64(abs(BF(dst) - dref) / abs(dref)))
    end
end

println()
println("=== G2. pt = -1/beta0 + sqrt(...) : same study ===")
@printf("  %-12s %-10s %14s %14s %14s\n", "E0 [GeV]", "delta", "pt", "rel err code", "rel err stable")
for (E0, mc2, lbl) in ((10.0e9, Octopus.EMASS_EV, "10 e-"), (2.5e9, Octopus.PMASS_EV, "2.5 p"))
    b0, g0 = reference_beta_gamma(E0, mc2)
    for d in (1e-1, 1e-2, 1e-4, 1e-6, 1e-8, 1e-10, 1e-12)
        pref = exact_pt(d, b0, g0)
        p = Octopus._pt_from_delta(d, b0, g0)
        num = 2 * d + d * d
        pst = num / (sqrt(1 / b0^2 + num) + 1 / b0)
        @printf("  %-12s %-10.0e %14.6e %14.3e %14.3e\n", lbl, d, p,
                Float64(abs(BF(p) - pref) / abs(pref)),
                Float64(abs(BF(pst) - pref) / abs(pref)))
    end
end

println()
println("=== G3. zero must map to zero ===")
for (E0, mc2, lbl) in ((10.0e9, Octopus.EMASS_EV, "10 GeV e-"),
                       (275.0e9, Octopus.PMASS_EV, "275 GeV p"),
                       (2.5e9, Octopus.PMASS_EV, "2.5 GeV p"))
    b0, g0 = reference_beta_gamma(E0, mc2)
    d0 = Octopus._delta_from_pt(0.0, b0, g0)
    p0 = Octopus._pt_from_delta(0.0, b0, g0)
    z, pz = convert_longitudinal(TIME_ENERGY => PATHLENGTH_DELTA, 0.0, 0.0; beta0=b0, gamma0=g0)
    @printf("  %-11s delta(pt=0) = %-12.4e  pt(delta=0) = %-12.4e  convert(0,0) -> (%.3e, %.3e)\n",
            lbl, d0, p0, z, pz)
end

println()
println("=== G4. round trips: ABSOLUTE error and error RELATIVE to amplitude ===")
println("  12 ordered pairs x 3 energies x 2 arc positions, per amplitude class")
for (zamp, pamp, cls) in ((0.05, 3.0e-3, "large   z=5cm  pz=3e-3"),
                          (1.0e-3, 1.0e-5, "typical z=1mm  pz=1e-5"),
                          (1.0e-6, 1.0e-9, "small   z=1um  pz=1e-9"),
                          (1.0e-9, 1.0e-13, "tiny    z=1nm  pz=1e-13"))
    wabs_z = Ref(0.0); wabs_p = Ref(0.0); wrel_z = Ref(0.0); wrel_p = Ref(0.0)
    for (E0, mc2) in ((10.0e9, Octopus.EMASS_EV), (275.0e9, Octopus.PMASS_EV),
                      (2.5e9, Octopus.PMASS_EV))
        b0, g0 = reference_beta_gamma(E0, mc2)
        for s in (0.0, 3141.59), i in 1:4, j in 1:4
            i == j && continue
            for sz in (-1.0, 1.0), sp in (-1.0, 1.0)
                z = sz * zamp; pz = sp * pamp
                a, b = convert_longitudinal(C[i] => C[j], z, pz; beta0=b0, gamma0=g0, s=s)
                z2, p2 = convert_longitudinal(C[j] => C[i], a, b; beta0=b0, gamma0=g0, s=s)
                wabs_z[] = max(wabs_z[], abs(z2 - z)); wabs_p[] = max(wabs_p[], abs(p2 - pz))
                wrel_z[] = max(wrel_z[], abs(z2 - z) / abs(z))
                wrel_p[] = max(wrel_p[], abs(p2 - pz) / abs(pz))
            end
        end
    end
    @printf("  %-24s |dz| %.2e  |dpz| %.2e   rel z %.2e  rel pz %.2e\n",
            cls, wabs_z[], wabs_p[], wrel_z[], wrel_p[])
end

println()
println("=== G5. reference_beta docstring claim, measured ===")
println("  Docstring: sqrt((g-1)(g+1))/g 'keeps its digits when gamma is large,")
println("  which is the only regime this is ever used in'.")
@printf("  %-16s %-12s %14s %14s %s\n", "case", "gamma", "code err", "naive err", "verdict")
for (E0, mc2, lbl) in ((10.0e9, Octopus.EMASS_EV, "10 GeV e-"),
                       (275.0e9, Octopus.PMASS_EV, "275 GeV p"),
                       (2.5e9, Octopus.PMASS_EV, "2.5 GeV p"),
                       (1.0000001 * Octopus.PMASS_EV, Octopus.PMASS_EV, "gamma->1"),
                       (1.000000001 * Octopus.PMASS_EV, Octopus.PMASS_EV, "gamma->1 hard"))
    g = E0 / mc2
    b_code = sqrt((g - 1) * (g + 1)) / g
    b_naive = sqrt(1 - 1 / g^2)
    G = BF(E0) / BF(mc2)
    B = sqrt((G - 1) * (G + 1)) / G
    ec = Float64(abs(BF(b_code) - B) / B); en = Float64(abs(BF(b_naive) - B) / B)
    @printf("  %-16s %-12.6g %14.3e %14.3e %s\n", lbl, g, ec, en,
            ec < en ? "code BETTER" : ec > en ? "code WORSE" : "identical")
end
