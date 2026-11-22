#!/usr/bin/env python3
"""Summarise the BBSCL/Octopus comparison runs under runs/ into markdown tables (stdout and
results_tables.md). BBSCL per-turn time = gpu_time (ms, the cudaEvent pair around the turn loop) /
NTurn; Octopus per-turn time = mean of turn_timings over the turns after the warm-up window.
Luminosity: the collider's f10 column 12 is the overlap integral per particle pair (cm^-2), scaled by
Ne Np 1e4 to m^-2 per crossing; the single-ring weak-strong f10 column 12 is sum/np * f_rev * 1e-4
(cm^-2 s^-1 per particle pair), scaled by Ns Np 1e4 / f_rev to m^-2 per crossing."""
import glob, os, re
import numpy as np

import sys
HERE = os.path.dirname(os.path.abspath(__file__))
# The results directory: the argument if given, else results/ beside this file (the committed tree),
# else runs/ in a scratch directory that holds this script under inputs/.
RUNS = sys.argv[1] if len(sys.argv) > 1 else (os.path.join(HERE, "results") if os.path.isdir(os.path.join(HERE, "results"))
                                                else os.path.join(os.path.dirname(HERE), "runs"))
R = os.path.dirname(RUNS.rstrip("/"))
NE, NP, NS = 1.7203e11, 6.881e10, 1.7203e11
FREV = 299792458.0 / 3833.8
out = []
def P(s=""): out.append(s); print(s)

def bbscl_time(d, log="run.log", tlog="time.log"):
    txt = open(os.path.join(d, log)).read()
    m = re.search(r"gpu_time:\s+([0-9.eE+-]+)", txt); gpu_ms = float(m.group(1)) if m else float("nan")
    m = re.search(r"NTurn=(\d+)", txt) or re.search(r"Nb,Nt=\s*\d+\s+(\d+)", txt); nturn = int(m.group(1)) if m else None
    wall = float("nan")
    for l in open(os.path.join(d, tlog)):
        if "Elapsed (wall clock)" in l:
            parts = l.split()[-1].split(":"); wall = sum(float(p) * 60 ** i for i, p in enumerate(reversed(parts)))
    return gpu_ms / 1000.0, nturn, wall

def octopus_tsv(path):
    hdr = [l for l in open(path) if l.startswith("#")]
    rows = [l.split() for l in open(path) if not l.startswith("#") and not l.startswith("turn")]
    return hdr, np.array(rows, float)

def load_moments(path):
    cols = None; rr = []
    for l in open(path):
        if l.startswith("# columns:"): cols = l.split(":", 1)[1].split()
        elif not l.startswith("#"): rr.append([float(v) for v in l.split()])
    return cols, np.array(rr)

def sig(c, m, i, a, b): return np.sqrt(max(m[i, c.index(a)] - m[i, c.index(b)] ** 2, 0.0))

def case_S(solver, bdir, odir):
    B, O = os.path.join(RUNS, bdir), os.path.join(RUNS, odir)
    if not (os.path.isdir(B) and os.path.isdir(O) and os.path.exists(os.path.join(B, "run.log"))): return
    tsvs = glob.glob(os.path.join(O, "octopus_S_*_timing.tsv"))
    if not tsvs: return
    gpu_s, nturn, wall = bbscl_time(B)
    e = np.loadtxt(os.path.join(B, "bbscl_S_e.f10")); p = np.loadtxt(os.path.join(B, "bbscl_S_p.f10"))
    Lb = e[:, 11] * NE * NP * 1e4
    hdr, a = octopus_tsv(tsvs[0]); t = a[:, 1]; Lo = a[:, 2]; w = 20
    P(f"#### Case S, {solver} strong-strong, 2,560,000 e / 1,024,000 p, 15 slices, {nturn} turns")
    P(); P("| quantity | BBSCL | Octopus |"); P("|---|---|---|")
    P(f"| seconds per turn | {gpu_s/nturn:.3f} (gpu_time {gpu_s:.1f} s / {nturn}; wall {wall:.0f} s) | {t[w:].mean():.4f} mean, {np.median(t[w:]):.4f} median, sd {t[w:].std():.4f} (turns {w+1}-{len(t)}) |")
    P(f"| luminosity per crossing, turn 1 [m^-2] | {Lb[0]:.4e} | {Lo[0]:.4e} |")
    P(f"| luminosity, mean of turns {w+1}-{nturn} [m^-2] | {Lb[w:].mean():.4e} (sd {Lb[w:].std():.2e}) | {Lo[w:].mean():.4e} (sd {Lo[w:].std():.2e}) |")
    P(f"| luminosity, last turn [m^-2] | {Lb[-1]:.4e} | {Lo[-1]:.4e} |")
    P(f"| electron sigma_x, sigma_y, sigma_z at turn 1 [m] | {np.sqrt(e[0,5]):.4e}, {np.sqrt(e[0,6]):.4e}, {np.sqrt(e[0,7]):.4e} | see moments table |")
    P(f"| electron sigma_x, sigma_y, sigma_z at turn {nturn} [m] | {np.sqrt(e[-1,5]):.4e}, {np.sqrt(e[-1,6]):.4e}, {np.sqrt(e[-1,7]):.4e} | see moments table |")
    P(f"| proton sigma_x, sigma_y, sigma_z at turn {nturn} [m] | {np.sqrt(p[-1,5]):.4e}, {np.sqrt(p[-1,6]):.4e}, {np.sqrt(p[-1,7]):.4e} | see moments table |")
    mom = glob.glob(os.path.join(O, "*moments_moments_electron.tsv"))
    if mom:
        ce, me = load_moments(mom[0]); cp, mp = load_moments(mom[0].replace("electron", "proton"))
        P(); P(f"Octopus {solver} rms sizes from the moment observer (a separate run with the observer every turn), beside BBSCL's f10 moments:"); P()
        P("| turn | Octopus e sigma_x | e sigma_y | e sigma_z | p sigma_x | p sigma_y | p sigma_z | BBSCL e sigma_x | e sigma_y | p sigma_y |"); P("|---|---|---|---|---|---|---|---|---|---|")
        for i in (0, 50, 100, 150, len(me) - 1):
            tb = min(i, len(e) - 1)
            P(f"| {int(me[i,0])} | {sig(ce,me,i,'m200000','m100000'):.4e} | {sig(ce,me,i,'m002000','m001000'):.4e} | {sig(ce,me,i,'m000020','m000010'):.4e} | {sig(cp,mp,i,'m200000','m100000'):.4e} | {sig(cp,mp,i,'m002000','m001000'):.4e} | {sig(cp,mp,i,'m000020','m000010'):.4e} | {np.sqrt(e[tb,5]):.4e} | {np.sqrt(e[tb,6]):.4e} | {np.sqrt(p[tb,6]):.4e} |")
    P()

def case_repeat():
    Rp = os.path.join(RUNS, "S_pic_60_repeat")
    if not os.path.exists(os.path.join(Rp, "run.log")): return
    gpu_s, nturn, wall = bbscl_time(Rp)
    tsv = glob.glob(os.path.join(Rp, "octopus_S_pic_repeat.tsv"))
    if not tsv: return
    hdr, a = octopus_tsv(tsv[0]); t = a[:, 1]
    P(f"#### Repeat (PIC, {nturn} turns, both arms adjacent): BBSCL {gpu_s/nturn:.3f} s/turn (gpu_time {gpu_s:.1f} s); Octopus {t[10:].mean():.4f} s/turn (turns 11-{len(t)}), sd {t[10:].std():.4f}"); P()

def case_W():
    B, O = os.path.join(RUNS, "W_200"), os.path.join(RUNS, "W_200_octopus")
    if not os.path.exists(os.path.join(B, "run.log")): return
    gpu_s, nturn, wall = bbscl_time(B)
    f = np.loadtxt(os.path.join(B, "bbscl_W.f10")); Lb = f[:, 11] * NS * NP * 1e4 / FREV
    P(f"#### Case W, weak-strong, 1,024,000 protons against a rigid 7-slice electron beam, half angle 12.5 mrad, {nturn} turns")
    P(); P("| quantity | BBSCL (prmb, TrackGPU) | Octopus (TrackingTask) |"); P("|---|---|---|")
    tsvs = glob.glob(os.path.join(O, "octopus_W_timing.tsv"))
    if tsvs:
        hdr, a = octopus_tsv(tsvs[0]); t = a[:, 1]; Lo = a[:, 2]; w = 20
        P(f"| seconds per turn | {gpu_s/nturn:.4f} (gpu_time {gpu_s:.2f} s / {nturn}; wall {wall:.0f} s) | {t[w:].mean():.5f} mean, {np.median(t[w:]):.5f} median, sd {t[w:].std():.5f} (turns {w+1}-{len(t)}) |")
        P(f"| luminosity per crossing, turn 1 [m^-2] | {Lb[0]:.4e} | {Lo[0]:.4e} |")
        P(f"| luminosity, mean of turns {w+1}-{nturn} [m^-2] | {Lb[w:].mean():.4e} (sd {Lb[w:].std():.2e}) | {Lo[w:].mean():.4e} (sd {Lo[w:].std():.2e}) |")
    else:
        P(f"| seconds per turn | {gpu_s/nturn:.4f} (gpu_time {gpu_s:.2f} s / {nturn}) | pending |")
        P(f"| luminosity per crossing, turn 1 [m^-2] | {Lb[0]:.4e} | pending |")
    P(f"| proton sigma_x, sigma_y, sigma_z at turn 1 [m] | {np.sqrt(f[0,5]):.4e}, {np.sqrt(f[0,6]):.4e}, {np.sqrt(f[0,7]):.4e} | see moments table |")
    P(f"| proton sigma_x, sigma_y, sigma_z at turn {nturn} [m] | {np.sqrt(f[-1,5]):.4e}, {np.sqrt(f[-1,6]):.4e}, {np.sqrt(f[-1,7]):.4e} | see moments table |")
    mom = glob.glob(os.path.join(O, "octopus_W_moments_moments.tsv"))
    if mom:
        c, m = load_moments(mom[0])
        P(); P("| turn | Octopus sigma_x | sigma_y | sigma_z | sigma_delta | BBSCL sigma_x | sigma_y | sigma_z |"); P("|---|---|---|---|---|---|---|---|")
        for i in (0, 50, 100, 150, len(m) - 1):
            tb = min(i, len(f) - 1)
            P(f"| {int(m[i,0])} | {sig(c,m,i,'m200000','m100000'):.4e} | {sig(c,m,i,'m002000','m001000'):.4e} | {sig(c,m,i,'m000020','m000010'):.4e} | {sig(c,m,i,'m000002','m000001'):.4e} | {np.sqrt(f[tb,5]):.4e} | {np.sqrt(f[tb,6]):.4e} | {np.sqrt(f[tb,7]):.4e} |")
    P()

def case_L():
    for sub in sorted(glob.glob(os.path.join(RUNS, "L_*"))):
        name = os.path.basename(sub)
        for log, tlog in (("run.log", "time.log"), ("run_repeat.log", "time_repeat.log")):
            if os.path.exists(os.path.join(sub, log)):
                gpu_s, nturn, wall = bbscl_time(sub, log, tlog)
                P(f"#### {name}: BBSCL prmb ({log}) {gpu_s/nturn:.4f} s/turn (gpu_time {gpu_s:.2f} s / {nturn} turns, wall {wall:.0f} s)")
        for tsv in sorted(glob.glob(os.path.join(sub, "octopus_L_*.tsv"))):
            if tsv.endswith("_moments.tsv"): continue
            hdr, a = octopus_tsv(tsv); t = a[:, 1]; w = min(20, len(t) // 4)
            P(f"#### {name}: Octopus {os.path.basename(tsv)}: {t[w:].mean():.5f} s/turn mean (turns {w+1}-{len(t)}), median {np.median(t[w:]):.5f}, sd {t[w:].std():.5f}; {hdr[0].strip()}")
        tn = os.path.join(sub, "tunes.txt")
        if os.path.exists(tn):
            P(); P("```"); P(open(tn).read().strip()); P("```")
        P()

def case_diag():
    rows = []
    for sub in sorted(glob.glob(os.path.join(RUNS, "S_diag_*"))):
        if not os.path.exists(os.path.join(sub, "run.log")): continue
        gpu_s, nturn, wall = bbscl_time(sub)
        gen = open(os.path.join(sub, "gen.txt")).read() if os.path.exists(os.path.join(sub, "gen.txt")) else ""
        e = np.loadtxt(os.path.join(sub, "bbscl_S_e.f10"), ndmin=2)
        rows.append((os.path.basename(sub), gpu_s / nturn, nturn, e[0, 11] * NE * NP * 1e4))
    if not rows: return
    P("#### BBSCL strong-strong cost decomposition (20 turns each, production mesh)"); P()
    P("| run | slices | macroparticles e / p | solver | s/turn | luminosity turn 1 [m^-2] |"); P("|---|---|---|---|---|---|")
    meta = {"S_diag_pic_ns1_full": ("1", "2,560,000 / 1,024,000", "PIC"), "S_diag_pic_ns15_quarter": ("15", "640,000 / 256,000", "PIC"),
            "S_diag_gau_ns1_full": ("1", "2,560,000 / 1,024,000", "Gaussian"), "S_diag_gau_ns15_quarter": ("15", "640,000 / 256,000", "Gaussian"),
            "S_diag_pic_ns15_nonano": ("15", "2,560,000 / 1,024,000", "PIC, nanobeam=0, dy=1.8e-6")}
    for name, spt, nturn, L in rows:
        ns, npart, solver = meta.get(name, ("?", "?", "?"))
        P(f"| {name} | {ns} | {npart} | {solver} | {spt:.3f} | {L:.4e} |")
    P()

case_S("PIC", "S_pic_200", "S_pic_200_octopus")
case_S("Gaussian", "S_gau_200", "S_gau_200_octopus")
case_repeat(); case_W(); case_L(); case_diag()
open(os.path.join(R, "results_tables.md"), "w").write("\n".join(out) + "\n")
print("written", os.path.join(R, "results_tables.md"))
