#!/usr/bin/env python3
"""Bitwise comparison of two run artifacts: moments of both beams and the luminosity series."""
import sys, h5py, numpy as np
a, b = sys.argv[1], sys.argv[2]
fa, fb = h5py.File(a, "r"), h5py.File(b, "r")
ok = True
for k in ["moments/ele/data", "moments/pro/data", "luminosity/ip/values", "luminosity/ip/turns"]:
    x, y = fa[k][:], fb[k][:]
    same = x.shape == y.shape and np.array_equal(x.view(np.uint8) if x.dtype.kind == 'f' else x, y.view(np.uint8) if y.dtype.kind == 'f' else y)
    ok &= same
    print(f"{k:28s} shapes {x.shape} {y.shape}  bitwise identical: {same}" + ("" if same else f"  max |diff| {np.max(np.abs(x - y))}"))
print("FINGERPRINT", "IDENTICAL" if ok else "DIFFERS")
