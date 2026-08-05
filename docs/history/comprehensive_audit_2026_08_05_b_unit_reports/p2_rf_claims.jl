# U16 probe 2 — the RF cavity's RECORDED CORRECT CLAIMS, re-measured.
#   (i)   symplectic to 1e-14   (ii) kick exactly qV sin/(P0 c)
#   (iii) d(delta)/d(pt) = 1/beta at proton and electron energies
#   (iv)  nu_s ~ sqrt(V)        (v)  strength = 0 is the BITWISE identity
#   (vi)  L -> 0 equals L = 0;  (vii) phase argument is k*z1, not k*z

using ForwardDiff, LinearAlgebra
include("/cfs/ad/dxu/Library/Julia/Octopus/src/Octopus.jl")
using .Octopus
const O = Octopus

const S6 = [0.0 1 0 0 0 0; -1 0 0 0 0 0; 0 0 0 1 0 0; 0 0 -1 0 0 0;
            0 0 0 0 0 1; 0 0 0 0 -1 0]
symp_resid(f, u) = (J = ForwardDiff.jacobian(f, u); maximum(abs, J'*S6*J - S6))

println("="^78); println("U16 P2 — RF cavity recorded claims"); println("="^78)

cases = (
  (name="proton 2.5 GeV",  E0=2.5e9,   mc2=O.PMASS_EV),
  (name="proton 275 GeV",  E0=275.0e9, mc2=O.PMASS_EV),
  (name="electron 10 GeV", E0=10.0e9,  mc2=O.EMASS_EV),
)

u0 = [1.3e-3, 2.1e-4, -7.0e-4, 5.5e-5, 7.0e-3, 2.3e-3]

for cs in cases
    b0, g0 = O.reference_beta_gamma(cs.E0, cs.mc2)
    println("\n--- ", cs.name, "  beta0 = ", b0, "  gamma0 = ", g0, " ---")

    for L in (0.0, 2.0)
        sp = O.ThinRFCavitySpec(400.8e6; voltage=12.0e6, e0=cs.E0, mc2=cs.mc2,
                                phase=0.3, L=L)
        cav = O.compile_runtime(sp)
        f(u) = collect(cav(u[1],u[2],u[3],u[4],u[5],u[6]))
        r = symp_resid(f, u0)
        println("  |J'SJ - S| at L = ", L, "  : ", r, "   (<= 1e-14? ", r <= 1e-14, ")")
    end

    # (ii) kick is exactly qV sin(theta)/(P0 c) in p_t
    sp = O.ThinRFCavitySpec(400.8e6; voltage=12.0e6, e0=cs.E0, mc2=cs.mc2, phase=0.3)
    cav = O.compile_runtime(sp)
    z, d = u0[5], u0[6]
    z1, pt = O.convert_longitudinal(O.PATHLENGTH_DELTA => O.TIME_ENERGY, z, d;
                                    beta0=b0, gamma0=g0)
    pt_hand = pt + (12.0e6/(b0*cs.E0)) * sin(cav.k*z1 + 0.3)
    zh, dh = O.convert_longitudinal(O.TIME_ENERGY => O.PATHLENGTH_DELTA, z1, pt_hand;
                                    beta0=b0, gamma0=g0)
    out = cav(u0[1],u0[2],u0[3],u0[4],z,d)
    println("  hand-built qV sin/(P0 c) sandwich: dz = ", out[5]-zh, "  dpz = ", out[6]-dh,
            "   bitwise? ", out[5] === zh && out[6] === dh)
    println("  transverse untouched bitwise?      ",
            out[1]===u0[1] && out[2]===u0[2] && out[3]===u0[3] && out[4]===u0[4])

    # (iii) d(delta)/d(pt) = 1/beta
    dd_dpt = ForwardDiff.derivative(p -> O._delta_from_pt(p, b0, g0), pt)
    bpart = O.particle_beta(O.TIME_ENERGY, pt; beta0=b0, gamma0=g0)
    println("  d(delta)/d(pt) = ", dd_dpt, "   1/beta = ", 1/bpart,
            "   diff = ", dd_dpt - 1/bpart)

    # (v) strength = 0 is the bitwise identity
    sp0 = O.ThinRFCavitySpec(400.8e6; strength=0.0, beta0=b0, gamma0=g0, phase=0.3)
    c0 = O.compile_runtime(sp0)
    o0 = c0(u0[1],u0[2],u0[3],u0[4],u0[5],u0[6])
    println("  strength = 0 bitwise identity?     ", all(o0[i] === u0[i] for i in 1:6))

    # (vi) L -> 0 vs L = 0
    spL = O.ThinRFCavitySpec(400.8e6; voltage=12.0e6, e0=cs.E0, mc2=cs.mc2,
                             phase=0.3, L=1.0e-9)
    cL = O.compile_runtime(spL); c00 = O.compile_runtime(sp)
    a = cL(u0...); b = c00(u0...)
    println("  |L=1e-9 - L=0| max                 : ", maximum(abs, collect(a) .- collect(b)))

    # (vii) the phase argument really is k*z1, and how far that is from k*z
    println("  k*z1 - k*z                         : ", cav.k*z1 - cav.k*z, " rad")
end

# ---- (iv) nu_s ~ sqrt(V) -------------------------------------------------
println("\n--- nu_s ~ sqrt(V), 2.5 GeV proton ring, alpha_c = 0.2, C = 1000, h = 5 ---")
b0, g0 = O.reference_beta_gamma(2.5e9, O.PMASS_EV)
frf = 5 * b0 * O.CLIGHT / 1000.0
function nus_of(V)
    cav = O.compile_runtime(O.ThinRFCavitySpec(frf; voltage=V, e0=2.5e9,
                                               mc2=O.PMASS_EV, phase=0.0))
    f(u) = begin
        z = u[1] - 0.2*1000.0*u[2]; d = u[2]
        _,_,_,_,zn,dn = cav(0.0,0.0,0.0,0.0,z,d); [zn,dn]
    end
    J = ForwardDiff.jacobian(f, [0.0,0.0])
    acos((J[1,1]+J[2,2])/2)/(2pi)
end
n1 = nus_of(6.0e6); n4 = nus_of(24.0e6); n9 = nus_of(54.0e6)
println("  nu_s(V) = ", n1, "   nu_s(4V) = ", n4, "   nu_s(9V) = ", n9)
println("  nu_s(4V)/nu_s(V) = ", n4/n1, "  (exactly 2 in the small-amplitude limit)")
println("  nu_s(9V)/nu_s(V) = ", n9/n1, "  (exactly 3)")

# ---- corrected tracked tune (P1's accumulator ran the wrong way) ---------
println("\n--- tracked nu_s, finite amplitude, corrected sign ---")
cav = O.compile_runtime(O.ThinRFCavitySpec(frf; voltage=6.0e6, e0=2.5e9,
                                           mc2=O.PMASS_EV, phase=0.0))
function tracked(z0, nturns)
    z, d = z0, 0.0; bz = sqrt(200.0/8.77597784155112e-5); ang = 0.0
    for _ in 1:nturns
        zp, dp = z, d
        z = z - 0.2*1000.0*d
        _,_,_,_,z,d = cav(0.0,0.0,0.0,0.0,z,d)
        da = atan(d*bz, z) - atan(dp*bz, zp)
        da < 0 && (da += 2pi)
        ang += da
    end
    ang/(2pi*nturns)
end
for z0 in (1.0e-5, 1.0e-4, 1.0e-2)
    println("  z0 = ", z0, " m  ->  nu_s = ", tracked(z0, 20000))
end
println("  analytic(eta = alpha_c)     = ", sqrt(5*0.2*6.0e6/(2pi*b0^2*2.5e9)))
println("  analytic(eta = alpha_c-1/g^2)= ", sqrt(5*(0.2-1/g0^2)*6.0e6/(2pi*b0^2*2.5e9)))
