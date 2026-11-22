#!/usr/bin/env python3
"""Table of the per-element-type arms: BBSCL s/turn (gpu_time/turns), Octopus mean and median
s/turn after warm-up, per-element ns after subtracting the map-only baseline, ratios, rms final."""
import re, glob, os, sys
R = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "results", "eltype", "runs")
NP = 1048576
def bb(d):
    try:
        log = open(os.path.join(d, "run.log")).read()
        t = float(re.search(r"gpu_time:\s*([0-9.eE+-]+)", log).group(1)) / 1e3
        nt = int(re.search(r"Nb,Nt=\s*\d+\s+(\d+)", log).group(1))
        return t / nt
    except Exception as e:
        return None
def oct(path):
    log = open(path).read()
    m = re.search(r"mean/turn \(turns \d+-\d+\) = ([0-9.]+) s\s+median = ([0-9.]+) s.*?min = ([0-9.]+)", log)
    rms = re.search(r"rms final\s*=\s*\[(.*?)\]", log)
    occ = re.search(r"active blocks/SM=(\d+)\s+resident warps/SM=(\d+)", log)
    cnt = re.search(r"kind=\w+ count=(\d+)", log)
    return (float(m.group(1)), float(m.group(2)), float(m.group(3))) if m else None, rms.group(1) if rms else "", occ.groups() if occ else None, int(cnt.group(1)) if cnt else None
base_bb = bb(os.path.join(R, "map"))
base_oct = {}
for p in glob.glob(os.path.join(R, "map", "octopus_*.log")):
    r = oct(p); base_oct = r
print(f"baseline (one-turn map only): BBSCL {base_bb*1e3 if base_bb else float('nan'):.3f} ms/turn   Octopus median {base_oct[0][1]*1e3 if base_oct and base_oct[0] else float('nan'):.3f} ms/turn")
print(f"{'arm':10s} {'count':>5s} | {'BBSCL ms/turn':>13s} {'ns/part-el':>10s} | {'Octopus cfg':12s} {'median ms':>9s} {'mean ms':>8s} {'ns/part-el':>10s} {'oct/bb':>6s} {'occ(blk,warps)':>14s}")
for d in sorted(glob.glob(os.path.join(R, "*"))):
    arm = os.path.basename(d)
    if arm == "map": continue
    tb = bb(d)
    logs = sorted(glob.glob(os.path.join(d, "octopus_*.log")))
    first = True
    for p in logs:
        (tm, occ_rms, occ, cnt) = oct(p)
        cfg = os.path.basename(p)[len("octopus_"):-4]
        if tm is None or cnt is None:
            print(f"{arm:10s} {'?':>5s} | {cfg:12s} FAILED ({p})"); continue
        nb = (tb - base_bb) / cnt / NP * 1e9 if (tb and base_bb) else float('nan')
        no = (tm[1] - base_oct[0][1]) / cnt / NP * 1e9 if base_oct and base_oct[0] else float('nan')
        bbcol = f"{tb*1e3:13.3f} {nb:10.2f}" if first and tb else (f"{'':13s} {'':10s}")
        print(f"{arm if first else '':10s} {cnt if first else '':>5} | {bbcol} | {cfg:12s} {tm[1]*1e3:9.3f} {tm[0]*1e3:8.3f} {no:10.2f} {no/nb if nb else float('nan'):6.2f} {str(occ) if occ else '':>14s}")
        first = False
print()
print("beam size at the end (physics beside timing): BBSCL f10 last line cols 6,7 = sigma_x^2, sigma_y^2; Octopus rms final x, y:")
import math
for d in sorted(glob.glob(os.path.join(R, "*"))):
    arm = os.path.basename(d)
    try:
        last = [l.split() for l in open(os.path.join(d, "bbscl_T.f10")) if l.strip()][-1]
        print(f"  {arm:10s} BBSCL   turn {last[0]:>4s}: sigma_x = {math.sqrt(float(last[5])):.4e}  sigma_y = {math.sqrt(float(last[6])):.4e}  <x> = {float(last[2]):+.3e}  <z> = {float(last[4]):+.3e}")
    except Exception as e:
        print(f"  {arm:10s} BBSCL   f10 unreadable: {e}")
    for p in sorted(glob.glob(os.path.join(d, "octopus_*.log"))):
        r = oct(p)
        try:
            v = [float(x) for x in r[1].split(",")]
            print(f"  {arm:10s} Octopus {os.path.basename(p)[8:-4]:8s}: sigma_x = {v[0]:.4e}  sigma_y = {v[2]:.4e}")
        except Exception:
            print(f"  {arm:10s} Octopus {os.path.basename(p)[8:-4]:8s}: rms final = {r[1]}")
