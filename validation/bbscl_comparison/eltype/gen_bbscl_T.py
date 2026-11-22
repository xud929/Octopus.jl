#!/usr/bin/env python3
"""BBSCL input for the per-element-type timing: a Ph_rot one-turn map plus --count copies
of one element kind (map|drift|quad|sext|bend), with the case L literals (gen_bbscl_L.py).
Ph_rot slots: ({L, ax,bx,nux, ay,by,nuy, az,bz,nuz, 0 x 12}) -- twiss[2],[5],[8] are the tunes."""
import argparse, math, os
MP = 938.2720813e6
ap = argparse.ArgumentParser()
ap.add_argument("--outdir", required=True)
ap.add_argument("--kind", required=True)
ap.add_argument("--count", type=int, default=16)
ap.add_argument("--base", default="bbscl_T")
ap.add_argument("--nturn", type=int, default=40)
ap.add_argument("--itmon", type=int, default=40)
ap.add_argument("--n", type=int, default=1048576)
a = ap.parse_args()
assert a.n % 256 == 0 and a.nturn % a.itmon == 0
def map_optics(kind, count):   # same table as octopus_eltype.jl
    if kind == "drift": b = 400.0 if count > 32 else 100.0; return (b, b, 0.25, 0.26)
    if kind == "quad": return (25.0, 25.0, 0.10, 0.10)
    if kind == "sext": return (16.0, 16.0, 0.25, 0.26)
    if kind == "bend": return (16.0, 100.0, 0.25, 0.26)
    return (16.0, 5.0, 0.31, 0.32)
bx, by, nux, nuy = map_optics(a.kind, a.count)
ax = ay = 0.0
bz = 88.69436505611495 * 8
nuz = 0.0082
E0 = 275.0e9
EX = EY = 1.0e-8
SIGD = 1.0e-7
EZ = (bz * SIGD) * SIGD
OFF = (1.0e-4, 0.0, 1.0e-4, 0.0, 1.0e-3, 0.0)
ANGLE = 2 * math.pi / 16
lines = [
    f"// BBSCL per-element-type timing kind={a.kind} count={a.count} (gen_bbscl_T.py) ;",
    f"Beam Gaussian=({{{E0:.6e}, {MP:.9e}, {EX:.6e}, {EY:.6e}, {EZ:.6e}, 1, {a.n}, {a.nturn}, {a.itmon}, 1.0, 1.0}});",
    "Bunches B=({1.0e11});",
    f"Twiss T=({{{ax:.10g}, {bx:.10g}, 0.0, {ay:.10g}, {by:.10g}, 0.0, 0.0, {bz:.10g}, 0.0, 0,0,0,0, 0,0,0,0, 0,0,0,0}});",
    f"COD C=({{{OFF[0]}, {OFF[1]}, {OFF[2]}, {OFF[3]}, {OFF[4]}, {OFF[5]}, 0.0}});",
    f"Ph_rot ring=({{120.0, {ax:.10g}, {bx:.10g}, {nux}, {ay:.10g}, {by:.10g}, {nuy}, 0.0, {bz:.10g}, {nuz}, 0,0,0,0, 0,0,0,0, 0,0,0,0}});",
]
for k in range(1, a.count + 1):
    odd = (k % 2 == 1)
    if a.kind == "drift":
        lines.append(f"Drift D{k}=({{{1.8 if odd else 2.0}}});")
    elif a.kind == "quad":
        lines.append(f"Quad Q{k}=({{0.5, {0.18 if odd else -0.18}, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0}});")
    elif a.kind == "sext":
        lines.append(f"Sext S{k}=({{0.2, {0.2 if odd else -0.4}, 0, 0, 0, 0, 1}});")
    elif a.kind == "bend":
        lines.append(f"Bend B{k}=({{3.0, {ANGLE:.16g}, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0}});")
    elif a.kind == "map":
        break
    else:
        raise SystemExit("unknown kind " + a.kind)
os.makedirs(a.outdir, exist_ok=True)
p = os.path.join(a.outdir, a.base + ".in")
open(p, "w").write("\n".join(lines) + "\n")
print("wrote", p, "kind", a.kind, "count", a.count if a.kind != "map" else 0)
