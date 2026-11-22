#!/usr/bin/env python3
"""Generate the BBSCL single-ring input <base>.in for comparison case W (weak-strong):
a live proton beam against a rigid sliced Gaussian electron beam (the physics of
examples/weak_strong_tracking.jl without crab cavities, chromaticity and radiation),
run with the single-ring program prmb (TrackGPU, element.cu:684), whose IP element
applies bb_map (bb.cu:329): Hirata boost, per-slice synchro-beam drift, Bassetti-Erskine
kick through the gridw table, longitudinal kick, luminosity density per particle.

IP slots (IPParamSet, bb.cu:56-182): K0=alpha_x*, K1=beta_x*, K2=alpha_y*, K3=beta_y*,
K20=half crossing angle [rad], K21=eps_x, K22=eps_y (strong beam, geometric),
K23=sigma_delta, K26=sigma_z, K27=nslice, K28=N_strong. The kick coefficient is
Cp = 2 N_strong r_e/gamma_weak (IPBeamSet, bb.cu:885-889): for a proton weak beam the
strong population is scaled by m_e/m_p so that 2 (N m_e/m_p) r_e = 2 N r_p.
Printed luminosity (element.cu:795-797): (1/np) sum_p sum_i w_i rho_i(x_p) * f_rev * 1e-4
[cm^-2 s^-1 per particle pair]; Octopus's per-crossing L[m^-2] = that * N_s N_w 1e4 / f_rev.
"""
import argparse, os

ME = 0.510998950e6
MP = 938.2720813e6

ap = argparse.ArgumentParser()
ap.add_argument("--outdir", required=True)
ap.add_argument("--base", default="bbscl_W")
ap.add_argument("--nturn", type=int, default=200)
ap.add_argument("--itmon", type=int, default=10)
ap.add_argument("--n", type=int, default=1024000)
ap.add_argument("--nslice", type=int, default=7)
ap.add_argument("--angle", type=float, default=12.5e-3)
ap.add_argument("--aperture", type=float, default=1.0)
ap.add_argument("--scale-ns", type=int, default=1)
a = ap.parse_args()
assert a.n % 256 == 0 and a.nturn % a.itmon == 0

# weak proton beam
Ep, Np = 275.0e9, 0.6881e11
sxp, syp, szp, sdp = 95.0e-6, 8.5e-6, 6.0e-2, 6.6e-4
bxp, byp = 0.8, 0.072
nup = (0.228, 0.210, 0.01)       # Ph_rot rotates by -2 pi nu_z: +0.01 here = Octopus -0.01
# strong electron beam
Ns = 1.7203e11
sxs, sys_, szs, sds = 95.0e-6, 8.5e-6, 0.7e-2, 5.5e-4
bxs, bys = 0.55, 0.056
circ = 3833.8

exp_, eyp, ezp, bzp = sxp**2 / bxp, syp**2 / byp, szp * sdp, szp / sdp
exs, eys = sxs**2 / bxs, sys_**2 / bys
Ns_in = Ns * (ME / MP) if a.scale_ns else Ns

def twiss(ax, bx, nux, ay, by, nuy, az, bz, nuz):
    return f"{ax}, {bx}, {nux}, {ay}, {by}, {nuy}, {az}, {bz}, {nuz}, 0,0,0,0, 0,0,0,0, 0,0,0,0"

K = [0.0] * 29
K[0], K[1], K[2], K[3] = 0.0, bxs, 0.0, bys
K[20] = a.angle
K[21], K[22], K[23], K[26], K[27], K[28] = exs, eys, sds, szs, a.nslice, Ns_in
ipk = ", ".join(f"{v:.6e}" if isinstance(v, float) and v != 0.0 else str(int(v)) if float(v).is_integer() else f"{v:.6e}" for v in K)

lines = [
    "// BBSCL comparison case W, weak proton ring against a rigid electron beam (gen_bbscl_W.py) ;",
    "// Beam <dist>=({E[eV], mass[eV], eps_x, eps_y, eps_z [m], Nbucket, NMacroP, NTurn, ITMon, Ax, Ay}) ;",
    f"Beam Gaussian=({{{Ep:.6e}, {MP:.9e}, {exp_:.6e}, {eyp:.6e}, {ezp:.6e}, 1, {a.n}, {a.nturn}, {a.itmon}, {a.aperture}, {a.aperture}}});",
    f"Bunches B=({{{Np:.6e}}});",
    f"Twiss IP=({{{twiss(0.0, bxp, 0.0, 0.0, byp, 0.0, 0.0, bzp, 0.0)}}});",
    "COD cod=({0,0,0,0,0,0, 0.0, 0,0,0});",
    "// IP: ax*,bx*,ay*,by* of the STRONG beam, K20 half angle, K21 eps_x, K22 eps_y, K23 sigma_delta, K26 sigma_z, K27 nslice, K28 N_strong ;",
    f"// N_strong handed to BBSCL = {Ns_in:.6e} ({'Ns m_e/m_p, proton-kick scaling' if a.scale_ns else 'physical'}; physical Ns = {Ns:.5e}) ;",
    f"IP ip=({{{ipk}}});",
    "// one-turn linear map: L[m], then the 21 twiss values with the fractional tunes ;",
    f"Ph_rot ring=({{{circ}, {twiss(0.0, bxp, nup[0], 0.0, byp, nup[1], 0.0, bzp, nup[2])}}});",
]
os.makedirs(a.outdir, exist_ok=True)
open(os.path.join(a.outdir, a.base + ".in"), "w").write("\n".join(lines) + "\n")
frev = 299792458.0 / circ
print("wrote", os.path.join(a.outdir, a.base + ".in"),
      f"| p: eps=({exp_:.4e},{eyp:.4e},{ezp:.4e}) beta_z={bzp:.4f} | strong eps=({exs:.4e},{eys:.4e}) Ns_in={Ns_in:.5e}",
      f"| L_octopus[m^-2/crossing] = Lum_printed * {Ns:.5e} * {Np:.5e} * 1e4 / f_rev({frev:.3f} Hz)")
