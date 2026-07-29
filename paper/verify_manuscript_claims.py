#!/usr/bin/env python3
"""Whitespace-normalized check that claimed-removed phrases are actually gone.

A plain grep on LaTeX misses any phrase the source line-wraps: "ships\nwith the
driver" does not match "ships with the driver".  That failure let a fix be
reported as applied when the sentence was still in the file.  Normalize all
whitespace to single spaces before searching.
"""
import re
import sys

SRC = "/cfs/ad/dxu/Work/Daily/20260727_Octopus_paper/main.tex"
flat = re.sub(r"\s+", " ", open(SRC).read())

MUST_BE_ABSENT = [
    "$1.158$",
    "ships with the driver that produced it",
    "Everything else in the package",
    "plane assignment differs from the wide-plane scan",
    "overestimates the measured 2D value",
    "Quantitative $\\Lambda$ therefore requires the full 2D treatment or direct simulation; the 1D models remain useful for structure",
    "single realizations per entry",
    "the four solver columns share the same sampled source realization",
    "no tested option moves the fluctuation by more than $3\\%$",
    "the fluctuation not at all",
    "rises monotonically by a factor $2.4$",
    "of order $900$ individual",
    "genuinely more transform work",
    "gather/scatter compaction alone",
    "far below both FP64 and bandwidth peaks",
    "Luminosity accounting is a third",
    "three levers the campaign did",
    "$3.2$--$3.4$ in the",
    "$5$--$16\\%$ over the",
    "against $0.306$~s",
    "$\\sim$$70\\times$ smaller",
    "the same realization",
    "3$--$5\\times$ below what independent columns would give.",
]

MUST_BE_PRESENT = [
    "$355$~GFLOP/s",
    "$17.5\\%$",
    "transform staging and normalization",
    "$3600$ host-synchronizing reductions",
    "Page's",
    "$L=42$",
    "1.213",
    "rigid-bunch limit",
    "$1.162$",
    "smallest difference this design could have detected",
    "$14.4\\times$",
    "$1.17\\times$",
    "$0.072$, $0.098$, $0.135$, $0.162$ and $0.085$~pp",
    "four levers",
]

bad = 0
for p in MUST_BE_ABSENT:
    if re.sub(r"\s+", " ", p) in flat:
        print(f"STILL PRESENT: {p[:70]}")
        bad += 1
for p in MUST_BE_PRESENT:
    if re.sub(r"\s+", " ", p) not in flat:
        print(f"MISSING      : {p[:70]}")
        bad += 1
print("ALL CHECKS PASS" if bad == 0 else f"{bad} problem(s)")
sys.exit(1 if bad else 0)
