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



# --- Structural checks (R5): a fixed phrase list cannot catch a figure that
# --- no longer matches its data, nor a series drawn outside its own axes.
def check_figures():
    """Every committed figure must be byte-reproducible from the archived data,
    and every plotted series must lie inside its axis limits."""
    import glob
    import hashlib
    import os
    import subprocess
    import sys as _sys

    here = os.path.dirname(os.path.abspath(__file__))
    def content_hash(path):
        """Hash PDF content ignoring the embedded creation/modification dates,
        which change on every run and are not part of the figure."""
        raw = open(path, "rb").read()
        raw = re.sub(rb"/(CreationDate|ModDate)\s*\([^)]*\)", b"", raw)
        raw = re.sub(rb"/ID\s*\[[^\]]*\]", b"", raw)
        return hashlib.sha256(raw).hexdigest()

    before = {f: content_hash(f)
              for f in sorted(glob.glob(os.path.join(here, "figs", "*.pdf")))}
    r = subprocess.run([_sys.executable, os.path.join(here, "make_figures.py")],
                       capture_output=True, cwd=here)
    if r.returncode != 0:
        print("FIGURES      : make_figures.py failed")
        return 1
    bad = 0
    for f, h in before.items():
        if content_hash(f) != h:
            print(f"FIGURE STALE : {os.path.basename(f)} is not what its data produces")
            bad += 1
    return bad


def check_axis_limits():
    """Re-run the figure module with an Axes.plot shim that flags any point
    drawn outside the axis limits finally set on that Axes."""
    import os
    import runpy
    import sys as _sys

    here = os.path.dirname(os.path.abspath(__file__))
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.axes as _axes
    import numpy as _np

    drawn = []
    orig_plot = _axes.Axes.plot

    def plot(self, *a, **k):
        # In ax.plot(x, y, [fmt]) only the SECOND positional is the y series;
        # checking the first would test turn numbers against a y-axis.
        if len(a) >= 2 and isinstance(a[1], _np.ndarray) and a[1].dtype.kind == "f":
            drawn.append((self, a[1]))
        return orig_plot(self, *a, **k)

    _axes.Axes.plot = plot
    cwd = os.getcwd()
    try:
        os.chdir(here)
        runpy.run_path(os.path.join(here, "make_figures.py"), run_name="__main__")
    finally:
        os.chdir(cwd)
        _axes.Axes.plot = orig_plot

    bad = 0
    for ax, arr in drawn:
        lo, hi = ax.get_ylim()
        finite = arr[_np.isfinite(arr)]
        span = hi - lo
        if finite.size and (finite.max() > hi + 0.05 * span or
                            finite.min() < lo - 0.05 * span):
            print(f"OFF-AXIS     : series spans [{finite.min():.4g}, {finite.max():.4g}] "
                  f"against ylim ({lo:.4g}, {hi:.4g})")
            bad += 1
    return bad


bad = 0
for p in MUST_BE_ABSENT:
    if re.sub(r"\s+", " ", p) in flat:
        print(f"STILL PRESENT: {p[:70]}")
        bad += 1
for p in MUST_BE_PRESENT:
    if re.sub(r"\s+", " ", p) not in flat:
        print(f"MISSING      : {p[:70]}")
        bad += 1
bad += check_figures()
bad += check_axis_limits()
print("ALL CHECKS PASS" if bad == 0 else f"{bad} problem(s)")
sys.exit(1 if bad else 0)
