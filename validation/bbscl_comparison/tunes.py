#!/usr/bin/env python3
"""Fractional tunes from a centroid series by FFT with parabolic peak interpolation.
Usage: tunes.py bbscl <file.f10>   (columns: turn Nsurvive <x> <y> <z> ...)
       tunes.py octopus <moments.tsv> (columns named in the '# columns:' header: m100000 m001000 m000010)
"""
import sys, numpy as np

def tune(series):
    s = np.asarray(series, float); s = s - s.mean(); n = len(s)
    w = np.hanning(n); f = np.abs(np.fft.rfft(s * w)); k = int(np.argmax(f[1:])) + 1
    if 1 <= k < len(f) - 1:
        a, b, c = np.log(f[k - 1] + 1e-300), np.log(f[k] + 1e-300), np.log(f[k + 1] + 1e-300)
        d = 0.5 * (a - c) / (a - 2 * b + c) if (a - 2 * b + c) != 0 else 0.0
    else:
        d = 0.0
    return (k + d) / n

kind, path = sys.argv[1], sys.argv[2]
if kind == "bbscl":
    d = np.loadtxt(path)
    x, y, z = d[:, 2], d[:, 3], d[:, 4]
else:
    cols = None; rows = []
    for line in open(path):
        if line.startswith("# columns:"):
            cols = line.split(":", 1)[1].split()
        elif not line.startswith("#"):
            rows.append([float(v) for v in line.split()])
    d = np.array(rows)
    x, y, z = d[:, cols.index("m100000")], d[:, cols.index("m001000")], d[:, cols.index("m000010")]
print(f"{kind}: turns={len(x)}  Qx={tune(x):.6f}  Qy={tune(y):.6f}  Qz={tune(z):.6f}  "
      f"<x> amplitude {x.std()*np.sqrt(2):.3e}  <y> {y.std()*np.sqrt(2):.3e}  <z> {z.std()*np.sqrt(2):.3e}")
