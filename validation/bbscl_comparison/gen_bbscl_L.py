#!/usr/bin/env python3
"""Generate the BBSCL single-ring input <base>.in for comparison case L (the 64-cell FODO
ring of octopus_lattice_bbscl.jl). Reads the matched optics file that script writes in
OCT_MODE=optics (beta_x alpha_x beta_y alpha_y beta_z ...).
BBSCL slots (quad.cu, bend.cu, sext.cu, cav.cu; SAD integrated strengths K1 = k1 L, K2 = k2 L):
  Quad  ({L, K1, ROTATE, DX, DY, DISRAD, ACHROMA, DISFRIN, F1, F2, FRINGE, EPS})   DISFRIN=1, FRINGE=0: no fringe
  Bend  ({L, ANGLE, E1, E2, ROTATE, DISRAD, K1, DX, DY, K0, DISFRIN, EPS, ...})   sector bend; hard-edge fringe is built in
  Sext  ({L, K2, ROTATE, DX, DY, DISRAD, DISFRIN})                               DISFRIN=1: no fringe
  Cavity({L, VOLT, HARM, PHI, FREQ})                                            FREQ = frev*HARM when FREQ=0
"""
import argparse, math, os

MP = 938.2720813e6
ap = argparse.ArgumentParser()
ap.add_argument("--outdir", required=True)
ap.add_argument("--optics", required=True)
ap.add_argument("--base", default="bbscl_L")
ap.add_argument("--nturn", type=int, default=200)
ap.add_argument("--itmon", type=int, default=10)
ap.add_argument("--n", type=int, default=1048576)
ap.add_argument("--ncell", type=int, default=64)
a = ap.parse_args()
assert a.n % 256 == 0 and a.nturn % a.itmon == 0
vals = [float(x) for line in open(a.optics) if not line.startswith("#") for x in line.split()]
bx, ax, by, ay, bz = vals[:5]
opt_ncell = int(vals[8]) if len(vals) >= 9 else 1
if opt_ncell != a.ncell:
    assert opt_ncell == 1, f"optics file is for ncell={opt_ncell}, not 1 or {a.ncell}"
    bz *= a.ncell      # beta_z = C eta/(2 pi Q_s) scales with the circumference at fixed h, V

NCELL, E0 = a.ncell, 275.0e9
KQ, K2F, K2D = 0.36, 1.0, -2.0
LQ, LS, LB = 0.5, 0.2, 3.0
ANGLE = 2 * math.pi / (2 * NCELL)
RF_V, RF_H = 2.0e6, 320
EX = EY = 1.0e-8
SIGD = 1.0e-7
EZ = (bz * SIGD) * SIGD
OFF = (1.0e-4, 0.0, 1.0e-4, 0.0, 1.0e-3, 0.0)

lines = [
    "// BBSCL comparison case L: 64-cell FODO ring, 275 GeV protons (gen_bbscl_L.py) ;",
    f"Beam Gaussian=({{{E0:.6e}, {MP:.9e}, {EX:.6e}, {EY:.6e}, {EZ:.6e}, 1, {a.n}, {a.nturn}, {a.itmon}, 1.0, 1.0}});",
    "Bunches B=({1.0e11});",
    f"Twiss T=({{{ax:.10g}, {bx:.10g}, 0.0, {ay:.10g}, {by:.10g}, 0.0, 0.0, {bz:.10g}, 0.0, 0,0,0,0, 0,0,0,0, 0,0,0,0}});",
    f"COD C=({{{OFF[0]}, {OFF[1]}, {OFF[2]}, {OFF[3]}, {OFF[4]}, {OFF[5]}, 0.0}});",
    f"Cavity RF=({{0.0, {RF_V:.6e}, {RF_H}, 0.0, 0}});",
]
cell = [
    f"Quad QF=({{{LQ}, {KQ * LQ:.10g}, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0}});",
    f"Sext SF=({{{LS}, {K2F * LS:.10g}, 0, 0, 0, 0, 1}});",
    "Drift D1=({1.8});",
    f"Bend B=({{{LB}, {ANGLE:.16g}, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0}});",
    "Drift D2=({2.0});",
    f"Quad QD=({{{LQ}, {-KQ * LQ:.10g}, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0}});",
    f"Sext SD=({{{LS}, {K2D * LS:.10g}, 0, 0, 0, 0, 1}});",
    "Drift D1=({1.8});",
    f"Bend B=({{{LB}, {ANGLE:.16g}, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0}});",
    "Drift D2=({2.0});",
]
for _ in range(NCELL):
    lines += cell
os.makedirs(a.outdir, exist_ok=True)
open(os.path.join(a.outdir, a.base + ".in"), "w").write("\n".join(lines) + "\n")
print("wrote", os.path.join(a.outdir, a.base + ".in"), f"elements={1 + 10 * NCELL} beta=({bx:.4f},{by:.4f},{bz:.4f}) alpha=({ax:.4f},{ay:.4f}) eps_z={EZ:.3e}")
