# U14 probe F: longitudinal conventions -- round trips, the beta/gamma factors
# against the theory note derived independently, conditioning, and the domain
# boundary of the sqrt.
using Octopus, Printf
setprecision(BigFloat, 256)
const BF = BigFloat
const C = (TIME_ENERGY, SIGMA_PSIGMA, PATHLENGTH_DELTA, TIME_DELTA)
const NAMES = ("TIME_ENERGY", "SIGMA_PSIGMA", "PATHLENGTH_DELTA", "TIME_DELTA")

println("=== F1. reference kinematics against BigFloat ===")
for (E0, mc2, label) in ((10.0e9, Octopus.EMASS_EV, "10 GeV electron"),
                         (275.0e9, Octopus.PMASS_EV, "275 GeV proton"),
                         (2.5e9, Octopus.PMASS_EV, "2.5 GeV proton"),
                         (0.94e9 * 1.0000001, Octopus.PMASS_EV, "near rest proton"))
    b0, g0 = reference_beta_gamma(E0, mc2)
    G = BF(E0) / BF(mc2)
    B = sqrt(1 - 1 / (G * G))
    @printf("  %-18s gamma=%.17g (rel %.2e)  beta=%.17g (rel %.3e)\n",
            label, g0, abs(g0 - Float64(G)) / Float64(G), b0,
            abs(BF(b0) - B) / B)
    # the naive form the docstring says it avoids
    naive = sqrt(1 - 1 / g0^2)
    @printf("  %-18s naive sqrt(1-1/g^2) = %.17g  rel err %.3e  (code's form is %s)\n",
            "", naive, Float64(abs(BF(naive) - B) / B),
            abs(BF(b0) - B) <= abs(BF(naive) - B) ? "better or equal" : "WORSE")
end
println("  gamma < 1 refused:")
try
    reference_beta(0.5e6, Octopus.EMASS_EV)
catch e
    println("    ", typeof(e), ": ", sprint(showerror, e)[1:min(end, 120)])
end

println()
println("=== F2. round trips over EVERY ordered pair (12), at three energies ===")
println("    and two arc positions; errors are relative to the coordinate scale.")
@printf("  %-22s %-22s %10s %12s %12s\n", "from", "to", "E0 [GeV]", "|dz|/scale", "|dpz|/scale")
worst_rt = 0.0
for (E0, mc2) in ((10.0e9, Octopus.EMASS_EV), (275.0e9, Octopus.PMASS_EV),
                  (2.5e9, Octopus.PMASS_EV))
    b0, g0 = reference_beta_gamma(E0, mc2)
    for s in (0.0, 3141.59)
        for i in 1:4, j in 1:4
            i == j && continue
            we = 0.0
            for z in (-0.05, -1e-6, 0.0, 1e-6, 0.05), pz in (-3e-3, -1e-9, 0.0, 1e-9, 3e-3)
                a, b = convert_longitudinal(C[i] => C[j], z, pz; beta0=b0, gamma0=g0, s=s)
                z2, p2 = convert_longitudinal(C[j] => C[i], a, b; beta0=b0, gamma0=g0, s=s)
                sz = max(abs(z), 1e-6); sp = max(abs(pz), 1e-9)
                we = max(we, abs(z2 - z) / sz, abs(p2 - pz) / sp)
            end
            global worst_rt = max(worst_rt, we)
            if E0 == 2.5e9 && s == 0.0
                @printf("  %-22s %-22s %10.1f %12.3e\n", NAMES[i], NAMES[j], E0/1e9, we)
            end
        end
    end
end
@printf("  WORST round-trip error over all 12 pairs x 3 energies x 2 arc positions: %.3e\n", worst_rt)

println()
println("=== F3. the two momentum relations against an independent derivation ===")
# delta = sqrt((1/b0+pt)^2 - 1/(b0 g0)^2) - 1  and its inverse; check both
# against BigFloat AND against the physical definitions E = E0 + pt*P0c,
# delta = P/P0 - 1, beta = Pc/E.
for (E0, mc2) in ((10.0e9, Octopus.EMASS_EV), (2.5e9, Octopus.PMASS_EV))
    b0, g0 = reference_beta_gamma(E0, mc2)
    P0c = BF(E0) * BF(b0)                    # P0 c = beta0 E0
    worstd = 0.0; worstb = 0.0
    for pt in (-0.4, -1e-3, 0.0, 1e-3, 0.4)
        E = BF(E0) + BF(pt) * P0c
        Pc = sqrt(E * E - BF(mc2)^2)
        dref = Pc / P0c - 1
        bref = Pc / E
        d = Octopus._delta_from_pt(pt, b0, g0)
        b = Octopus._beta_of(d, pt, b0)
        worstd = max(worstd, Float64(abs(BF(d) - dref) / max(abs(dref), BF(1e-30))))
        worstb = max(worstb, Float64(abs(BF(b) - bref) / bref))
        # exact inverse?
        pt2 = Octopus._pt_from_delta(d, b0, g0)
        @printf("  E0=%5.1f GeV pt=%9.2e -> delta=%.17g  (ref %.17g)  beta=%.17g\n",
                E0/1e9, pt, d, Float64(dref), b)
        @printf("      inverse pt: %.17g   abs err %.3e\n", pt2, abs(pt2 - pt))
    end
    @printf("  E0=%5.1f GeV: worst RELATIVE delta err %.3e ; beta err %.3e\n",
            E0/1e9, worstd, worstb)
end

println()
println("=== F4. conditioning: delta = -1 + sqrt(...) is a cancellation ===")
println("  Identity (exact): 1/beta0^2 - 1/(beta0 gamma0)^2 = 1, so")
println("    delta = sqrt(1 + u) - 1 with u = 2 pt/beta0 + pt^2 -- cancellation-free.")
println("  The code evaluates the cancelling form. Measured relative error vs BigFloat:")
@printf("  %-14s %-14s %14s %14s %14s\n", "E0", "pt", "delta", "rel err (code)", "rel err (stable)")
for (E0, mc2) in ((10.0e9, Octopus.EMASS_EV), (2.5e9, Octopus.PMASS_EV))
    b0, g0 = reference_beta_gamma(E0, mc2)
    P0c = BF(E0) * BF(b0)
    for pt in (1e-2, 1e-4, 1e-6, 1e-8, 1e-10, 1e-12)
        E = BF(E0) + BF(pt) * P0c
        Pc = sqrt(E * E - BF(mc2)^2)
        dref = Pc / P0c - 1
        d = Octopus._delta_from_pt(pt, b0, g0)
        u = 2 * pt / b0 + pt * pt
        dstable = u / (sqrt(1 + u) + 1)
        @printf("  %-14.1e %-14.1e %14.6e %14.3e %14.3e\n", E0, pt, d,
                Float64(abs(BF(d) - dref) / dref), Float64(abs(BF(dstable) - dref) / dref))
    end
end
println()
println("  Same for the inverse (pt from delta); stable form")
println("    pt = (2 delta + delta^2) / (sqrt(1/beta0^2 + 2 delta + delta^2) + 1/beta0):")
for (E0, mc2) in ((10.0e9, Octopus.EMASS_EV), (2.5e9, Octopus.PMASS_EV))
    b0, g0 = reference_beta_gamma(E0, mc2)
    P0c = BF(E0) * BF(b0)
    ibg = 1 / (BF(b0) * BF(g0))
    for delta in (1e-2, 1e-4, 1e-6, 1e-8, 1e-10)
        ptref = -1 / BF(b0) + sqrt((1 + BF(delta))^2 + ibg * ibg)
        p = Octopus._pt_from_delta(delta, b0, g0)
        num = 2 * delta + delta * delta
        pstable = num / (sqrt(1 / b0^2 + num) + 1 / b0)
        @printf("  E0=%.1e delta=%.1e  pt=%.6e  rel err code %.3e  stable %.3e\n",
                E0, delta, p, Float64(abs(BF(p) - ptref) / ptref),
                Float64(abs(BF(pstable) - ptref) / ptref))
    end
end

println()
println("=== F5. sqrt domain: a particle decelerated below rest energy ===")
b0, g0 = reference_beta_gamma(2.5e9, Octopus.PMASS_EV)
@printf("  beta0=%.10f gamma0=%.6f ; pt at which the radicand vanishes: %.10f\n",
        b0, g0, -1/b0 + 1/(b0*g0))
for pt in (-0.5, -0.6, -0.62, -1/b0 + 1/(b0*g0) - 1e-12, -1.0)
    try
        d = Octopus._delta_from_pt(pt, b0, g0)
        @printf("  pt=%-14.6f delta=%.10g\n", pt, d)
    catch e
        @printf("  pt=%-14.6f THROWS %s: %s\n", pt, typeof(e),
                sprint(showerror, e)[1:min(end, 90)])
    end
end
println("  A DomainError is a hard stop, not a dead particle: it cannot be")
println("  masked by allow_lost_particles and it is not device-compilable.")
println()
println("  convert_longitudinal on the same input (the tracking entry point):")
for pt in (-0.62, -1.0)
    try
        r = convert_longitudinal(TIME_ENERGY => PATHLENGTH_DELTA, 0.01, pt; beta0=b0, gamma0=g0)
        println("    pt=", pt, " -> ", r)
    catch e
        println("    pt=", pt, " -> THROWS ", typeof(e))
    end
end

println()
println("=== F6. the F16 boundary: is it stated where the reader is? ===")
println("  longitudinal.jl convert_longitudinal docstring on `s`:")
println("    \"Leave `s` at its default and you are working with `-l`; pass the")
println("     arc position and you get `s - l`.\"  -- correct, and the s-term")
println("     algebra checks out below.")
b0, g0 = reference_beta_gamma(2.5e9, Octopus.PMASS_EV)
for (z, pz, s) in ((0.01, 1e-3, 0.0), (0.01, 1e-3, 1000.0))
    z1, pt = convert_longitudinal(PATHLENGTH_DELTA => TIME_ENERGY, z, pz; beta0=b0, gamma0=g0, s=s)
    beta = particle_beta(PATHLENGTH_DELTA, pz; beta0=b0, gamma0=g0)
    hand = z / beta + s * (1 / b0 - 1 / beta)     # -c dt derived by hand
    @printf("  s=%8.1f : z1 = %.17g   hand-derived %.17g   diff %.3e\n",
            s, z1, hand, abs(z1 - hand))
end
println("  slip factor a ring closed by this cavity sees (F16):")
for (E0, ac) in ((2.5e9, 0.2), (10.0e9, 0.2))
    _, g = reference_beta_gamma(E0, E0 == 10.0e9 ? Octopus.EMASS_EV : Octopus.PMASS_EV)
    @printf("    E0=%5.1f GeV: eta_full = %.6g ; eta_with_s=0 = %.6g ; ratio nu_s %.4f\n",
            E0/1e9, ac - 1/g^2, ac, sqrt(ac / (ac - 1/g^2)))
end
