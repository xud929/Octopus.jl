# U16 probe 1 — F16 independent reproduction: the RF cavity's missing velocity-slip term.
#
# Independent construction (does NOT reuse U12's harness):
#   * ring: a single arc map in the TRACKED convention #3 (PATHLENGTH_DELTA),
#     z = s - l, so over one turn  Dz = C - l(delta) = -alpha_c*C*delta.
#     This is the "convention-#3 lattice maps carry no velocity term" statement.
#   * cavity: ThinRFCavitySpec built through the public friendly constructor.
#   * synchrotron tune from the EIGENVALUE of the one-turn 2x2 Jacobian in
#     (z, delta), by ForwardDiff — no FFT, no fitting.
#   * analytic:  nu_s = sqrt(h |eta| qV |cos phi_s| / (2 pi beta0^2 E0)).
#
# Also: the "correct claims" recorded for this element.

using ForwardDiff
using LinearAlgebra
include("/cfs/ad/dxu/Library/Julia/Octopus/src/Octopus.jl")
using .Octopus

const O = Octopus

println("="^78)
println("U16 P1 — RF cavity F16 reproduction")
println("="^78)

# ---------------------------------------------------------------------------
# Case: 2.5 GeV total-energy proton ring, alpha_c = 0.2, C = 1000 m, h = 5,
# V = 6 MV, phi_s = 0.  (Same physical point F16 quotes, built independently.)
# ---------------------------------------------------------------------------
const E0     = 2.5e9          # eV, total
const MC2    = O.PMASS_EV
const C_RING = 1000.0
const HARM   = 5
const VOLT   = 6.0e6
const ALPHAC = 0.2

beta0, gamma0 = O.reference_beta_gamma(E0, MC2)
println("beta0  = ", beta0)
println("gamma0 = ", gamma0)
println("1/gamma0^2 = ", 1/gamma0^2)
frev = beta0 * O.CLIGHT / C_RING
frf  = HARM * frev
println("f_rev = ", frev, "   f_rf = ", frf)

cav_spec = O.ThinRFCavitySpec(frf; voltage=VOLT, e0=E0, mc2=MC2, phase=0.0)
cav = O.compile_runtime(cav_spec)
println("strength (compiled) = ", cav.strength)
println("qV/(P0 c) by hand   = ", VOLT / (beta0 * E0))
println("  strength - qV/(P0c) = ", cav.strength - VOLT/(beta0*E0))

# ---- one-turn map: arc (convention #3, geometric only) then cavity ---------
arc(z, d) = (z - ALPHAC * C_RING * d, d)
function oneturn(u)
    z, d = u[1], u[2]
    z, d = arc(z, d)
    _, _, _, _, zn, dn = cav(0.0, 0.0, 0.0, 0.0, z, d)
    return [zn, dn]
end

J = ForwardDiff.jacobian(oneturn, [0.0, 0.0])
println("\none-turn Jacobian at the fixed point:")
println(J)
println("det J - 1 = ", det(J) - 1)
tr = J[1,1] + J[2,2]
nus_map = acos(tr/2) / (2pi)
println("cos(2 pi nu_s) = tr/2 = ", tr/2)
println("nu_s from the linearised map = ", nus_map)

# ---- tracked tune, finite amplitude, by turn-by-turn phase advance ---------
function tracked_tune(z0, d0, nturns)
    z, d = z0, d0
    # scale delta to the same units as z using the map's own beta_z
    bz = sqrt(abs(J[1,2] / J[2,1]))
    ang = 0.0
    for _ in 1:nturns
        zp, dp = z, d
        z, d = arc(z, d)
        _, _, _, _, z, d = cav(0.0, 0.0, 0.0, 0.0, z, d)
        a0 = atan(dp*bz, zp); a1 = atan(d*bz, z)
        da = a0 - a1
        da < 0 && (da += 2pi)
        ang += da
    end
    return ang / (2pi * nturns)
end
nus_track = tracked_tune(1.0e-4, 0.0, 20000)
println("nu_s tracked (z0 = 0.1 mm, 20000 turns) = ", nus_track)

# ---- analytic -------------------------------------------------------------
analytic(eta) = sqrt(HARM * abs(eta) * VOLT / (2pi * beta0^2 * E0))
eta_wrong = ALPHAC
eta_true  = ALPHAC - 1/gamma0^2
println("\neta as implemented (alpha_c)        = ", eta_wrong)
println("eta true (alpha_c - 1/gamma0^2)     = ", eta_true)
println("analytic nu_s @ eta = alpha_c       = ", analytic(eta_wrong))
println("analytic nu_s @ eta = true          = ", analytic(eta_true))
println("\nRATIO tracked / analytic(alpha_c)   = ", nus_track/analytic(eta_wrong), "   <- should be ~1")
println("RATIO tracked / analytic(true eta)  = ", nus_track/analytic(eta_true),  "   <- F16's 1.84x")
println("RATIO map      / analytic(true eta) = ", nus_map/analytic(eta_true))
println("sqrt(alpha_c/eta_true)              = ", sqrt(ALPHAC/eta_true))

# ---- the mechanism, isolated: d(phase argument)/d(delta) ------------------
function phase_arg(d; s)
    z1, _ = O.convert_longitudinal(O.PATHLENGTH_DELTA => O.TIME_ENERGY, 0.0, d;
                                   beta0=beta0, gamma0=gamma0, s=s)
    return cav.k * z1
end
g0 = ForwardDiff.derivative(d -> phase_arg(d; s=0.0), 0.0)
gC = ForwardDiff.derivative(d -> phase_arg(d; s=C_RING), 0.0)
println("\nd(k z1)/d(delta) at s = 0     : ", g0)
println("d(k z1)/d(delta) at s = C     : ", gC)
missing_term = gC - g0
expect = cav.k * C_RING / (beta0 * gamma0^2)
println("difference                    : ", missing_term)
println("k*C/(beta0*gamma0^2)          : ", expect)
println("ratio                         : ", missing_term/expect)

# ---- wrong transition side: alpha_c < 1/gamma0^2 --------------------------
println("\n--- below transition: alpha_c = 0.05 < 1/gamma0^2 = ", 1/gamma0^2, " ---")
const AC2 = 0.05
arc2(z, d) = (z - AC2 * C_RING * d, d)
function oneturn2(u)
    z, d = u[1], u[2]
    z, d = arc2(z, d)
    _, _, _, _, zn, dn = cav(0.0, 0.0, 0.0, 0.0, z, d)
    return [zn, dn]
end
J2 = ForwardDiff.jacobian(oneturn2, [0.0, 0.0])
tr2 = J2[1,1] + J2[2,2]
println("tr/2 = ", tr2/2, "   |tr/2| <= 1 (stable)? ", abs(tr2/2) <= 1)
println("true eta here = ", AC2 - 1/gamma0^2, " (NEGATIVE: below transition)")
println("=> at phase = 0 the model says STABLE; the true eta says the fixed")
println("   point at phase = 0 is UNSTABLE (phi_s must move to pi).")
