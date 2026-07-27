#!/usr/bin/env python3
"""Plots for the coherent beam-beam mode theory note.

Reads the TSVs produced by validation/coherent_mode_vlasov_theory.jl and
validation/coherent_mode_scans.jl from result/ and writes three figures there:

  yokoya_vs_aspect.png   — Y versus flatness: 1D-reduced Vlasov theory curve,
                           measured 2D strong-strong PIC points, anchors
  yokoya_vs_xi.png       — Y versus beam-beam parameter: finite-xi map
                           correction curve plus measured PIC points
  eic_coherent_modes.png — EIC-like asymmetric case: coupled-mode eigenvalues
                           against the two incoherent continua, per plane

Run:  /usr/local/anaconda3/bin/python3 validation/plot_coherent_mode_theory.py
"""

import csv
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))
RESULT = os.path.join(HERE, "..", "result")


def read_tsv(name):
    path = os.path.join(RESULT, name)
    with open(path) as fh:
        rows = list(csv.DictReader(fh, delimiter="\t"))
    return rows


def fnum(rows, key):
    return [float(r[key]) for r in rows]


# --- Figure 1: Y versus flatness -------------------------------------------
theory = read_tsv("yokoya_vs_aspect.tsv")
fig, ax = plt.subplots(figsize=(6.4, 4.4))
ax.plot(fnum(theory, "aspect_ratio"), fnum(theory, "Y_m1_matrix"), "o--",
        color="tab:blue", alpha=0.7,
        label="1D model, m=1 Vlasov matrix (truncated)")
ax.plot(fnum(theory, "aspect_ratio"), fnum(theory, "Y_1d_sim"), "^-",
        color="tab:purple", alpha=0.7,
        label="1D model, exact (particle simulation)")
try:
    meas = read_tsv("yokoya_vs_aspect_measured.tsv")
    ax.plot(fnum(meas, "aspect_ratio"), fnum(meas, "Y_measured"), "s",
            color="tab:red", markersize=9, zorder=5,
            label="full 2D strong-strong PIC (measured)")
except FileNotFoundError:
    pass
ax.axhline(1.0, color="gray", lw=0.8, ls=":")
ax.annotate("rigid-bunch (round)", (0.55, 1.02), fontsize=8, color="gray")
ax.axhspan(1.2, 1.33, color="tab:green", alpha=0.12,
           label="literature band (Yokoya & Koiso)")
ax.set_ylim(-0.1, 1.7)
ax.set_xlabel(r"flatness $r = \sigma_y/\sigma_x$")
ax.set_ylabel(r"Yokoya factor $Y = \Delta Q_\pi/\xi$")
ax.set_title("Coherent-mode Yokoya factor versus beam flatness")
ax.legend(fontsize=8)
ax.grid(alpha=0.3)
fig.tight_layout()
fig.savefig(os.path.join(RESULT, "yokoya_vs_aspect.png"), dpi=160)
print("wrote result/yokoya_vs_aspect.png")

# --- Figure 2: Y versus xi --------------------------------------------------
fig, ax = plt.subplots(figsize=(6.4, 4.4))
xi_theory = read_tsv("yokoya_vs_xi_theory.tsv")
ax.plot(fnum(xi_theory, "xi"), fnum(xi_theory, "Y_eff"), "-",
        color="tab:blue",
        label="leading-order Y + discrete-map finite-$\\xi$ correction")
try:
    xi_meas = read_tsv("yokoya_vs_xi_measured.tsv")
    ax.plot(fnum(xi_meas, "xi"), fnum(xi_meas, "Y_measured"), "s",
            color="tab:red", markersize=8, label="2D strong-strong PIC (measured)")
except FileNotFoundError:
    pass
ax.set_xlabel(r"beam-beam parameter $\xi$")
ax.set_ylabel(r"$Y_{\rm eff} = (Q_\pi - Q_0)/\xi$")
ax.set_title("Yokoya factor versus beam-beam parameter (round beams)")
ax.legend(fontsize=8)
ax.grid(alpha=0.3)
fig.tight_layout()
fig.savefig(os.path.join(RESULT, "yokoya_vs_xi.png"), dpi=160)
print("wrote result/yokoya_vs_xi.png")

# --- Figure 3: EIC asymmetric mode spectrum --------------------------------
eic = read_tsv("eic_coherent_modes.tsv")
fig, axes = plt.subplots(1, 2, figsize=(9.6, 4.2), sharey=False)
for ax, plane in zip(axes, ("x", "y")):
    rows = [r for r in eic if r["plane"] == plane]
    if not rows:
        continue
    q_e = float(rows[0]["Q_e"]); xi_e = float(rows[0]["xi_e"])
    q_p = float(rows[0]["Q_p"]); xi_p = float(rows[0]["xi_p"])
    vals = fnum(rows, "eigenvalue")
    ax.axvspan(q_e, q_e + xi_e, color="tab:blue", alpha=0.25,
               label="e incoherent continuum")
    ax.axvspan(q_p, q_p + xi_p, color="tab:red", alpha=0.25,
               label="p incoherent continuum")
    ax.plot(vals, [1.0] * len(vals), "|", color="black", markersize=16,
            label="coupled-mode eigenvalues")
    discrete = [v for r, v in zip(rows, vals)
                if r["in_e_continuum"] == "false" and r["in_p_continuum"] == "false"]
    if discrete:
        ax.plot(discrete, [1.0] * len(discrete), "v", color="tab:green",
                markersize=10, label="discrete (undamped) modes")
    ax.set_yticks([])
    ax.set_xlabel("fractional tune")
    ax.set_title(f"EIC-like coupled modes, {plane} plane\n"
                 f"$\\xi_e$={xi_e:.3f}, $\\xi_p$={xi_p:.4f}")
    ax.legend(fontsize=7, loc="upper center")
fig.tight_layout()
fig.savefig(os.path.join(RESULT, "eic_coherent_modes.png"), dpi=160)
print("wrote result/eic_coherent_modes.png")
