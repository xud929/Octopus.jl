"""
Generate the Xsuite (xtrack) twiss reference table of the stage 8 benchmark C.

Reference model
---------------
xtrack 0.112.0 (pinned in the output file name), CPU context, JIT kernels
(the caller exports XSUITE_ALLOW_KERNEL_COMPILATION=1). Three layers:
  C0  convention witnesses: the bare 10 m drift S0 (R[4,5] against
      L/gamma0^2 stated in the line's OWN particle_ref), the lone cavity W1,
      the rolled quadrupole (rot_s_rad == SRotation sandwich), the sign row
      of the stage 8 sign witness (rule X, history section of benchmark C) on U2 (R[4,0], R[4,1]).
  C1  matrix level: xtrack.linear_normal_form.get_linear_normal_form on the
      COMMITTED Octopus one-turn maps (validation/reference/
      twiss_benchmark_maps.tsv), only_4d_block=True on coasting and 4x4 maps,
      the full 6D call on the bunched maps. The W matrix (36 entries), the six
      eigenvalues, and the lattice functions by xtrack's own formulas copied
      verbatim from xtrack/twiss/lattice_functions_from_W.py (betx = W00^2 +
      W01^2 ... dx = dx_pzeta, dx_zeta ...), plus xtrack's 4d dispersion route
      (I - M_rr)^-1 M_r,pzeta of xtrack/twiss/periodic_solution.py, written
      under its own names (dx_4d ...) as the identification of that route.
  C2  lattice level: Line.twiss(method='4d') on twins of U1, U2, K1, K2,
      R(0.1), R(pi/4), Rd(1e-3), Rd(1e-6) built from xt.Quadrupole(rot_s_rad),
      xt.Bend(length=1, angle=0.2), xt.Drift (xtrack defaults: Bend model
      'adaptive', edge_entry_model 'linear'; Quadrupole model 'adaptive').
  C3  the 6D twin T6 = U2 + xt.Cavity(voltage=5.6989983281965137e7,
      frequency=400e6, lag=0) LAST, Line.twiss(method='6d'); the one-turn R
      matrix at the cell entry, the closed orbit, the six |eigenvalue| and
      the tw6 lattice functions.
Nothing here compares against Octopus except the witnesses of C0/C3, which
are printed (GEN-WITNESS lines) so that the table is not frozen from a line
whose conventions moved. The consumer validation/twiss_xsuite_benchmark.jl
owns every gated comparison.

Coordinates
-----------
xtrack's R is in (x, px, y, py, zeta, pzeta), zeta = s - beta0 c t, pzeta =
ptau/beta0; a drift carries R[4,5] = +L/gamma0^2. The reader converts a
lattice-level map to Octopus's BARE compile by M_oct = Sh(-C/gamma0^2) R
(the stage 8 conversion law: J0 = I, F = I), or compares it to the TASK compile with
no conversion. The 4x4 transverse block is convention-free. tw.dx is
dx/dpzeta = dx/ddelta at first order (Jacobian 1); on a bunched map the
canonical eta is h * dx.

Beam pin (stage 8 decision D13)
----------------------
xt.Particles(mass0=938.27208943e6, p0c=2.8494991640982566e9): beta0 =
0.9498330546994187, gamma0 = 3.1973667700405533. The generator asserts
|beta0 - 0.9498330546994187| <= 1e-12 on the line's particle_ref and writes
the residual into the table header.

Inputs / Outputs
----------------
reads   validation/reference/twiss_benchmark_maps.tsv
writes  validation/reference/xsuite_twiss_xtrack_<version>.tsv   (long form:
        layer, fixture, compile, quantity, value; %.17g; atomic partial+mv)
        validation/reference/xsuite_twiss_provenance.txt            (pip
        freeze, sha256 of this driver and of the maps table, the three
        differences to the pinned xtrack commit 384952b, versions)

Run
---
The interpreter comes from the CALLER; nothing in this file names a python.
The stage 8 venv used to freeze the committed table was
result/twiss_impl_2026_09_11/stage8/xsuite_env/venv/bin/python (git-ignored;
the sidecar records it):
    export XSUITE_ALLOW_KERNEL_COMPILATION=1
    <python> validation/generate_xsuite_twiss_reference.py
    OCTOPUS_STAGE8_REGENERATE=1 <python> validation/generate_xsuite_twiss_reference.py
The regenerate mode (stage 8 decision D17) writes into a temporary path and diffs the
table cell by cell against the committed one, printing every differing cell
(REGEN-DIFF) and a REGEN-DIGEST line; exit status 1 if any cell differs.
OCTOPUS_STAGE8_PYTHON is documentation only: if set, its value is recorded
in the sidecar as the interpreter the operator intended.

Environment
-----------
python 3.11.5, xtrack 0.112.0, xobjects 0.6.10, xpart 0.23.18, xdeps
0.10.20, xfields 0.27.2, numpy 2.4.6, scipy 1.17.1 (full list in the sidecar).
"""
import hashlib
import os
import subprocess
import sys
import tempfile
import warnings

import numpy as np
import xtrack as xt

HERE = os.path.dirname(os.path.abspath(__file__))
REFDIR = os.path.join(HERE, "reference")
MAPS_PATH = os.path.join(REFDIR, "twiss_benchmark_maps.tsv")
TABLE_PATH = os.path.join(REFDIR, "xsuite_twiss_xtrack_%s.tsv" % xt.__version__)
SIDECAR_PATH = os.path.join(REFDIR, "xsuite_twiss_provenance.txt")

# Beam pin (stage 8 decision D13); the Octopus proton mass PMASS_EV and p0c at 3.0 GeV total energy.
MASS0_EV = 938.27208943e6
P0C_EV = 2.8494991640982566e9
BETA0_PIN = 0.9498330546994187
BETA0_ATOL = 1e-12
# Cavity twin of the Octopus ThinRFCavitySpec strength -0.02 at 400 MHz: V = 0.02 * p0c (stage 8 decision D5 literal).
CAVITY_VOLTAGE_V = 5.6989983281965137e7
CAVITY_FREQUENCY_HZ = 400.0e6
K_TILT = 0.05
TOL_D = 1e-7          # stage 8 tolerance class TOL-D (history section): any xtrack quantity touching rows/columns 5-6 (finite-difference R)
PINNED_COMMIT = "384952bcb2cd44b500b341b87436f3b1cf3bc817"


def g17(x):
    return "%.17g" % float(x)


def read_maps_table(path):
    """Header lines, column names and a dict {(id, compile): row dict} of the Octopus maps table."""
    header, colnames, rows = [], None, {}
    with open(path) as fh:
        for line in fh:
            line = line.rstrip("\n")
            if line.startswith("#"):
                header.append(line)
                continue
            fields = line.split("\t")
            if colnames is None:
                colnames = fields
                continue
            row = dict(zip(colnames, fields))
            rows[(row["id"], row["compile"])] = row
    return header, colnames, rows


def map_of(row):
    M = np.zeros((6, 6))
    for i in range(6):
        for j in range(6):
            M[i, j] = float(row["m%d%d" % (i + 1, j + 1)])
    return M


# --- xtrack's own formulas, copied from xtrack/twiss/lattice_functions_from_W.py (0.112.0) ---
# lines 55-70 (betx ... gamy1), 72-80 (betx1 = betx ...), 86-101 (Edwards-Teng), 128-145 (dispersion).
def lattice_functions_from_W(W):
    out = {}
    out["betx"] = W[0, 0] ** 2 + W[0, 1] ** 2
    out["bety"] = W[2, 2] ** 2 + W[2, 3] ** 2
    out["gamx"] = W[1, 0] ** 2 + W[1, 1] ** 2
    out["gamy"] = W[3, 2] ** 2 + W[3, 3] ** 2
    out["alfx"] = -W[0, 0] * W[1, 0] - W[0, 1] * W[1, 1]
    out["alfy"] = -W[2, 2] * W[3, 2] - W[2, 3] * W[3, 3]
    out["bety1"] = W[2, 0] ** 2 + W[2, 1] ** 2
    out["betx2"] = W[0, 2] ** 2 + W[0, 3] ** 2
    out["alfx2"] = -W[0, 2] * W[1, 2] - W[0, 3] * W[1, 3]
    out["alfy1"] = -W[2, 0] * W[3, 0] - W[2, 1] * W[3, 1]
    out["gamx2"] = W[1, 2] ** 2 + W[1, 3] ** 2
    out["gamy1"] = W[3, 0] ** 2 + W[3, 1] ** 2
    out["betx1"] = out["betx"]
    out["bety2"] = out["bety"]
    out["alfx1"] = out["alfx"]
    out["alfy2"] = out["alfy"]
    out["gamx1"] = out["gamx"]
    out["gamy2"] = out["gamy"]
    g_squared = np.sqrt(max(out["betx1"] * out["gamx1"] - out["alfx1"] ** 2, 0.0))
    out["g_edw_teng"] = np.sqrt(g_squared)
    out["betx_edw_teng"] = out["betx1"] / g_squared
    out["alfx_edw_teng"] = out["alfx1"] / g_squared
    out["bety_edw_teng"] = out["bety2"] / g_squared
    out["alfy_edw_teng"] = out["alfy2"] / g_squared
    for name, r in (("dx", 0), ("dpx", 1), ("dy", 2), ("dpy", 3)):
        out[name + "_zeta"] = (W[r, 4] - W[r, 5] * W[5, 4] / W[5, 5]) / (
            W[4, 4] - W[4, 5] * W[5, 4] / W[5, 5])
        out[name] = (W[r, 5] - W[r, 4] * W[4, 5] / W[4, 4]) / (
            W[5, 5] - W[5, 4] * W[4, 5] / W[4, 4])
    return out


# xtrack/twiss/periodic_solution.py:161-182 (0.112.0), the 4d route: dx = ((I - M_rr)^-1 M_r,pzeta)[0].
def dispersion_4d_route(RR):
    A_disp = RR[:4, :4]
    delta_disp = np.linalg.solve(A_disp - np.eye(4), RR[:4, 5])
    crab = np.linalg.solve(A_disp - np.eye(4), RR[:4, 4])
    out = {}
    for k, name in enumerate(("dx", "dpx", "dy", "dpy")):
        out[name + "_4d"] = -delta_disp[k]
        out[name + "_zeta_4d"] = -crab[k]
    return out


def normal_form(M, only_4d_block):
    """get_linear_normal_form plus the six eigenvalues ordered mode1, partner1, mode2, partner2, mode3, partner3."""
    W, invW, Rot, eigs = xt.linear_normal_form.get_linear_normal_form(M, only_4d_block=only_4d_block)
    w0, v0 = np.linalg.eig(M if not only_4d_block else _dummy_4d(M))
    six = []
    for lam in eigs:
        j = int(np.argmin(np.abs(w0 - lam)))
        rest = [k for k in range(6) if k != j]
        k = rest[int(np.argmin(np.abs(w0[rest] - np.conj(lam))))]
        six.extend([w0[j], w0[k]])
    return W, invW, Rot, eigs, six


def _dummy_4d(M):
    # linear_normal_form.py:97-104: the 4x4 block completed by the muz_dummy = pi/10 rotation.
    M = M.copy()
    M[4:, :] = 0
    M[:, 4:] = 0
    muz = np.pi / 10
    M[4:, 4:] = np.array([[np.cos(muz), np.sin(muz)], [-np.sin(muz), np.cos(muz)]])
    return M


# --- lattice twins (element numbers from validation/twiss_benchmark_cells.jl specs_*) ---
def quad(L, k1, tilt=0.0):
    return xt.Quadrupole(length=L, k1=k1, rot_s_rad=tilt)


def drift(L):
    return xt.Drift(length=L)


def bend(L, angle):
    return xt.Bend(length=L, angle=angle)


def cavity():
    return xt.Cavity(voltage=CAVITY_VOLTAGE_V, frequency=CAVITY_FREQUENCY_HZ, lag=0.0)


def twin_U1():
    return [quad(0.3, 1.6), drift(1.2), quad(0.3, -1.6 * (1 + 1e-3)), drift(1.2)]


def twin_U2(qf_tilt=0.0):
    return [quad(0.25, -1.1), drift(0.6), bend(1.0, 0.2), drift(0.6), quad(0.35, 1.5, qf_tilt),
            drift(0.6), bend(1.0, 0.2), drift(0.6), quad(0.25, -1.1)]


def twin_K1(tilt=K_TILT):
    return [quad(0.2, 1.0), drift(1.0), quad(0.2, -1.0, tilt), drift(1.0)]


def twin_rolled(theta, kd=-1.0):
    return [quad(0.2, 1.0, theta), drift(1.0), quad(0.2, kd, theta), drift(1.0)]


TWINS_4D = (
    ("U1", 3.0, lambda: twin_U1()),
    ("U2", 5.25, lambda: twin_U2()),
    ("K1", 2.4, lambda: twin_K1()),
    ("K2", 5.25, lambda: twin_U2(qf_tilt=K_TILT)),
    ("R_0.1", 2.4, lambda: twin_rolled(0.1)),
    ("R_pi4", 2.4, lambda: twin_rolled(np.pi / 4)),
    ("Rd_1e-3", 2.4, lambda: twin_rolled(np.pi / 4, kd=-(1 + 1e-3))),
    ("Rd_1e-6", 2.4, lambda: twin_rolled(np.pi / 4, kd=-(1 + 1e-6))),
)


def build_line(elements):
    names = ["e%d" % i for i in range(len(elements))]
    line = xt.Line(elements=dict(zip(names, elements)), element_names=names)
    line.particle_ref = xt.Particles(mass0=MASS0_EV, p0c=P0C_EV)
    line.build_tracker()
    return line


def beam_of(line):
    pr = line.particle_ref
    beta0, gamma0 = float(pr.beta0[0]), float(pr.gamma0[0])
    resid = abs(beta0 - BETA0_PIN)
    assert resid <= BETA0_ATOL, "beta0 pin violated: %s vs %s" % (g17(beta0), g17(BETA0_PIN))
    return beta0, gamma0, resid


def r_matrix(line):
    return np.array(line.get_R_matrix(particle_on_co=line.particle_ref.copy())["R_matrix"], dtype=float)


WITNESSES = []       # (name, value, expected, absdiff, tol, passed)


def witness(name, value, expected, tol, relative=False):
    d = abs(float(value) - float(expected))
    bound = tol * abs(float(expected)) if relative else tol
    ok = d <= bound
    WITNESSES.append((name, float(value), float(expected), d, bound, ok))
    print("GEN-WITNESS %s %s %s %s %s %s" % (name, g17(value), g17(expected), g17(d), g17(bound),
                                             "PASS" if ok else "FAIL"))
    return ok


def matrix_rows(prefix, M):
    return [("%s%d%d" % (prefix, i + 1, j + 1), M[i, j]) for i in range(6) for j in range(6)]


def layer_C0(maps):
    """Convention witnesses on the line's own particle_ref; returns rows and the beam."""
    rows = []
    s0 = build_line([drift(10.0)])
    beta0, gamma0, resid = beam_of(s0)
    R = r_matrix(s0)
    L = 10.0
    witness("S0_R45_vs_L_over_gamma0sq", R[4, 5], L / gamma0 ** 2, TOL_D, relative=True)
    witness("S0_R54_zero", R[5, 4], 0.0, 1e-12)
    # converted map Sh(-C/gamma0^2) R against the committed Octopus bare S0 map (TOL-D absolute, finite-difference R)
    Sh = np.eye(6)
    Sh[4, 5] = -L / gamma0 ** 2
    M_bare = map_of(maps[("S0", "bare")])
    witness("S0_converted_vs_octopus_bare_maxabs", np.abs(Sh @ R - M_bare).max(), 0.0, 1e-8)
    rows += [("C0", "S0", "line4d", q, v) for q, v in matrix_rows("r", R)]
    rows += [("C0", "S0", "line4d", "L_over_gamma0sq", L / gamma0 ** 2)]
    # W1: the lone cavity; xtrack R[5,4] against the FLIPPED Octopus bare M65 (stage 8 decision D5, witness rule W)
    w1 = build_line([cavity()])
    Rw = r_matrix(w1)
    m65 = float(maps[("W1", "bare")]["m65"])
    witness("W1_R54_vs_minus_octopus_M65", Rw[5, 4], -m65, TOL_D, relative=True)
    rows += [("C0", "W1", "line6d", q, v) for q, v in matrix_rows("r", Rw)]
    # rolled quadrupole: rot_s_rad = +t equals SRotation(+t) q SRotation(-t) (angle in degrees), p3 X3
    t = K_TILT
    Rq = r_matrix(build_line([quad(0.2, 1.0, t)]))
    deg = np.degrees(t)
    Rs = r_matrix(build_line([xt.SRotation(angle=deg), quad(0.2, 1.0), xt.SRotation(angle=-deg)]))
    witness("rot_s_rad_vs_SRotation_sandwich_maxabs", np.abs(Rq - Rs).max(), 0.0, 1e-14)
    rows += [("C0", "Q_rot0.05", "line4d", q, v) for q, v in matrix_rows("r", Rq)]
    return rows, (beta0, gamma0, resid)


def layer_C1(maps):
    """Matrix level on the committed Octopus maps."""
    rows = []
    plan = [("U1", "bare", True), ("U2", "bare", True), ("K1", "bare", True), ("K2", "bare", True),
            ("R_0.1", "bare", True), ("R_pi4", "bare", True), ("Rd_1e-3", "bare", True), ("Rd_1e-6", "bare", True),
            ("B4", "bare", False), ("B5", "bare", False), ("T6", "task", False),
            ("D6_1", "matrix", False), ("D6_2", "matrix", False), ("D6_3", "matrix", False),
            ("D8_1", "matrix", True), ("D8_2", "matrix", True), ("D8_3", "matrix", True)]
    for fid, compile_, only4d in plan:
        M = map_of(maps[(fid, compile_)])
        W, invW, Rot, eigs, six = normal_form(M, only4d)
        out = [("only_4d_block", 1.0 if only4d else 0.0)]
        out += matrix_rows("W", W)
        for k, lam in enumerate(six):
            out += [("eig%d_re" % (k + 1), lam.real), ("eig%d_im" % (k + 1), lam.imag)]
        for j in range(3):
            out += [("mu%d" % (j + 1), np.log(eigs[j]).imag)]
        out += sorted(lattice_functions_from_W(W).items())
        out += sorted(dispersion_4d_route(M).items())
        Mchk = _dummy_4d(M) if only4d else M
        out += [("normal_form_residual_maxabs", np.abs(Mchk - W @ Rot @ invW).max())]
        rows += [("C1", fid, compile_, q, v) for q, v in out]
        print("GEN-C1 %s %s only_4d_block=%d eig |.|=%s" % (fid, compile_, only4d, " ".join(g17(abs(l)) for l in six)))
    return rows


def twiss_rows(tw, R):
    out = matrix_rows("r", R)
    out += matrix_rows("W", np.array(tw.W_matrix[0], dtype=float))
    for k in ("betx", "bety", "alfx", "alfy", "gamx", "gamy", "betx1", "bety1", "betx2", "bety2",
              "alfx1", "alfy1", "alfx2", "alfy2", "gamx1", "gamy1", "gamx2", "gamy2",
              "betx_edw_teng", "bety_edw_teng", "alfx_edw_teng", "alfy_edw_teng", "g_edw_teng",
              "dx", "dpx", "dy", "dpy", "dx_zeta", "dpx_zeta", "dy_zeta", "dpy_zeta",
              "x", "px", "y", "py", "zeta", "delta"):
        out.append((k, float(tw[k][0])))
    out += [("qx", float(tw.qx)), ("qy", float(tw.qy)), ("qs", float(tw.qs)),
            ("cos_mux", np.cos(2 * np.pi * float(tw.qx))), ("sin_mux", np.sin(2 * np.pi * float(tw.qx))),
            ("cos_muy", np.cos(2 * np.pi * float(tw.qy))), ("sin_muy", np.sin(2 * np.pi * float(tw.qy))),
            ("c_minus", float(tw.c_minus)), ("momentum_compaction_factor", float(tw.momentum_compaction_factor)),
            ("slip_factor", float(tw.slip_factor))]
    moduli = np.sort(np.abs(np.linalg.eigvals(R)))[::-1]
    out += [("eigmod%d" % (k + 1), moduli[k]) for k in range(6)]
    return out


def layer_C2(maps):
    """Line.twiss(method='4d') on the coasting twins; the sign row of rule X on U2."""
    rows = []
    for fid, C, make in TWINS_4D:
        line = build_line(make())
        beam_of(line)
        tw = line.twiss(method="4d")
        R = np.array(tw.R_matrix, dtype=float)
        out = twiss_rows(tw, R) + [("C", C)]
        rows += [("C2", fid, "line4d", q, v) for q, v in out]
        print("GEN-C2 %s qx=%s qy=%s betx=%s bety=%s dx=%s R45=%s" % (
            fid, g17(tw.qx), g17(tw.qy), g17(tw.betx[0]), g17(tw.bety[0]), g17(tw.dx[0]), g17(R[4, 5])))
        if fid == "U2":
            m51, m52 = float(maps[("U2", "bare")]["m51"]), float(maps[("U2", "bare")]["m52"])
            witness("U2_sign_R40_vs_octopus_M51", np.sign(R[4, 0]), np.sign(m51), 0.0)
            witness("U2_sign_R41_vs_octopus_M52", np.sign(R[4, 1]), np.sign(m52), 0.0)
    return rows


def layer_C3(maps):
    """The 6D twin T6: U2 + cavity LAST, Line.twiss(method='6d'), the one-turn map at the cell entry."""
    rows = []
    line = build_line(twin_U2() + [cavity()])
    beam_of(line)
    R = r_matrix(line)
    moduli = np.sort(np.abs(np.linalg.eigvals(R)))[::-1]
    print("GEN-C3 T6 eig moduli %s" % " ".join(g17(m) for m in moduli))
    # the longitudinal 2x2 witness against the Octopus TASK-compiled T6 (stage 8 layer C3), TOL-D
    T = maps[("T6", "task")]
    for (i, j) in ((4, 4), (4, 5), (5, 4), (5, 5)):
        witness("T6_R%d%d_vs_octopus_task_m%d%d" % (i, j, i + 1, j + 1), R[i, j], float(T["m%d%d" % (i + 1, j + 1)]),
                TOL_D if abs(float(T["m%d%d" % (i + 1, j + 1)])) > 1e-3 else 1e-8,
                relative=abs(float(T["m%d%d" % (i + 1, j + 1)])) > 1e-3)
    stable = bool(np.all(np.abs(moduli - 1) < 1e-6))
    rows += [("C3", "T6", "line6d", q, v) for q, v in matrix_rows("r", R)]
    rows += [("C3", "T6", "line6d", "eigmod%d" % (k + 1), moduli[k]) for k in range(6)]
    rows += [("C3", "T6", "line6d", "stable", 1.0 if stable else 0.0), ("C3", "T6", "line6d", "C", 5.25)]
    if not stable:
        print("GEN-C3 T6 UNSTABLE: twiss(6d) skipped; C3 falls back to RECORDED (stage 8 decision D5)")
        return rows
    # xtrack's free closed-orbit search stops at |delta| ~ 1e-8 (recorded below as co_free_*), which moves the
    # finite-difference R by ~1e-7; the lag=0 cavity makes the origin the EXACT fixed point, so the tw6 rows are
    # computed with particle_on_co pinned to the particle_ref (the same point get_R_matrix used above).
    tw6_free = line.twiss(method="6d")
    R6_free = np.array(tw6_free.R_matrix, dtype=float)
    for k in ("x", "px", "y", "py", "zeta", "delta"):
        rows.append(("C3", "T6", "line6d", "co_free_" + k, float(tw6_free[k][0])))
    rows.append(("C3", "T6", "line6d", "co_free_R_shift_maxabs", float(np.abs(R6_free - R).max())))
    print("GEN-C3 T6 free closed orbit x=%s delta=%s |R_free - R|max=%s" % (
        g17(tw6_free.x[0]), g17(tw6_free.delta[0]), g17(np.abs(R6_free - R).max())))
    tw6 = line.twiss(method="6d", particle_on_co=line.particle_ref.copy())
    R6 = np.array(tw6.R_matrix, dtype=float)
    out = twiss_rows(tw6, R6)
    rows += [("C3", "T6", "line6d", "tw6_" + q, v) for q, v in out]
    print("GEN-C3 T6 qx=%s qy=%s qs=%s betx=%s bety=%s dx=%s dx_zeta=%s |R-R6|max=%s" % (
        g17(tw6.qx), g17(tw6.qy), g17(tw6.qs), g17(tw6.betx[0]), g17(tw6.bety[0]), g17(tw6.dx[0]),
        g17(tw6.dx_zeta[0]), g17(np.abs(R - R6).max())))
    return rows


def record_future_warning(maps):
    M = map_of(maps[("K1", "bare")])
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        xt.linear_normal_form.compute_linear_normal_form(M, only_4d_block=True)
    # backticks of the message are rendered as apostrophes (the tables carry no backtick characters)
    texts = ["%s: %s" % (w.category.__name__, str(w.message).replace("\n", " ").replace("`", "'"))
             for w in caught]
    return texts[0] if texts else "(no warning raised)"


def header_lines(beam, fw_text):
    beta0, gamma0, resid = beam
    return [
        "# Xsuite twiss reference of the stage 8 twiss benchmark C (design note docs/design/twiss_dispersion_analysis.md staging item 8; the 2026-09-15 stage 8 history sections)",
        "# purpose: the xtrack side of the Octopus twiss benchmark; consumer: validation/twiss_xsuite_benchmark.jl",
        "# producer: validation/generate_xsuite_twiss_reference.py (interpreter chosen by the caller; sidecar xsuite_twiss_provenance.txt)",
        "# tool: xtrack %s, xobjects %s, xpart %s, numpy %s, python %s" % (
            xt.__version__, __import__("xobjects").__version__, __import__("xpart").__version__,
            np.__version__, sys.version.split()[0]),
        "# flags: C1 get_linear_normal_form(only_4d_block=True) on coasting and 4x4 maps, full 6D call on B4, B5, T6 task, D6_*;",
        "#   C2 Line.twiss(method='4d'); C3 Line.twiss(method='6d') and get_R_matrix at the cell entry; xtrack element defaults",
        "#   (Bend model 'adaptive', edge_entry_model 'linear'; Quadrupole model 'adaptive'); R by 13-particle central differences",
        "#   (steps dx 1e-6, dpx 1e-7, dy 1e-6, dpy 1e-7, dzeta 1e-5, ddelta 1e-6), so rows/columns 5-6 are TOL-D (1e-7) quantities",
        "# beam: protons, mass0 938.27208943e6 eV, p0c 2.8494991640982566e9 eV, beta0 %s, gamma0 %s (line particle_ref);" % (g17(beta0), g17(gamma0)),
        "#   |beta0 - 0.9498330546994187| = %s (asserted <= 1e-12)" % g17(resid),
        "# coordinates: xtrack (x, px, y, py, zeta, pzeta), zeta = s - beta0 c t, pzeta = ptau/beta0; a drift has R[4,5] = +L/gamma0^2;",
        "#   rot_s_rad=+t equals the Octopus tilt=t (Rt(t) M Rt(t)^T, Rt = kron([c -s; s c], I2)); xt.Cavity lag=0 is the Octopus strength -0.02",
        "# conversion the reader applies: C1 rows read the Octopus maps themselves (NO conversion; W, eig, lattice functions by xtrack's formulas);",
        "#   C2/C3 lattice maps: M_oct(bare) = Sh(-C/gamma0^2) R with Sh(u) = I except (5,6) = u; M_oct(task) = R; the 4x4 block is convention-free;",
        "#   tw.dx = dx/dpzeta = dx/ddelta at first order (Jacobian 1); canonical eta of a bunched map = h * dx; dx_zeta is the first (X2) column",
        "# quantities: rIJ / WIJ = matrix entries (1-based); eigK_re/im = eigenvalue K in the order mode1, partner1, mode2, partner2, mode3, partner3;",
        "#   muJ = log(eig_modeJ).imag; betx..gamy2, betx_edw_teng..g_edw_teng, dx..dpy_zeta as xtrack/twiss/lattice_functions_from_W.py;",
        "#   *_4d = xtrack's periodic_solution.py 4d route (I - M_rr)^-1 M_r,pzeta on the same map; eigmodK = sorted |eigenvalue| of r;",
        "#   tw6_* = the Line.twiss(method='6d', particle_on_co=particle_ref) outputs on T6 (the origin is the exact fixed point of the",
        "#   lag=0 cavity twin); co_free_* = the orbit xtrack's free closed-orbit search returns and the R shift it causes;",
        "#   stable = 1 when all |eigenvalue| within 1e-6 of 1; xtrack's finite-difference maps carry |eigenvalue| - 1 up to ~4e-11",
        "# deprecation recorded (compute_linear_normal_form called once on K1): %s" % fw_text,
        "# numbers: %.17g; only_4d_block and stable are 0/1 flags",
    ]


COLNAMES = ["layer", "fixture", "compile", "quantity", "value"]


def atomic_write(path, text):
    tmp = "%s.partial-%d" % (path, os.getpid())
    with open(tmp, "w") as fh:
        fh.write(text)
    os.replace(tmp, path)


def table_text(header, rows):
    lines = list(header) + ["\t".join(COLNAMES)]
    lines += ["\t".join((la, fi, co, q, g17(v))) for la, fi, co, q, v in rows]
    return "\n".join(lines) + "\n"


def sha256_of(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def sidecar_text(driver_sha, fw_text, beam):
    freeze = subprocess.run([sys.executable, "-m", "pip", "freeze"], capture_output=True, text=True).stdout.strip()
    intended = os.environ.get("OCTOPUS_STAGE8_PYTHON", "")
    if intended:   # recorded repo-relative, so no machine path enters a tracked file: under this checkout by
        repo = os.path.dirname(HERE)   # relpath, otherwise (a worktree sharing the main tree's git-ignored
        absint = os.path.abspath(intended)   # result/ scratch) from its result/ component onward
        if absint.startswith(repo + os.sep):
            intended = os.path.relpath(absint, repo)
        elif os.sep + "result" + os.sep in absint:
            intended = absint[absint.index(os.sep + "result" + os.sep) + 1:]
    lines = [
        "stage 8 benchmark C (Xsuite twiss) provenance sidecar",
        "table: validation/reference/xsuite_twiss_xtrack_%s.tsv" % xt.__version__,
        "driver: validation/generate_xsuite_twiss_reference.py sha256 %s" % driver_sha,
        "input maps: validation/reference/twiss_benchmark_maps.tsv sha256 %s" % sha256_of(MAPS_PATH),
        "interpreter that froze the table: result/twiss_impl_2026_09_11/stage8/xsuite_env/venv/bin/python (git-ignored venv; the driver takes its interpreter from the caller)",
        "OCTOPUS_STAGE8_PYTHON (documentation only): %s" % (intended or "(unset)"),
        "python %s" % sys.version.split()[0],
        "beam pin: beta0 %s gamma0 %s residual %s" % (g17(beam[0]), g17(beam[1]), g17(beam[2])),
        "deprecation text: %s" % fw_text,
        "xtrack formulas checked line by line against the theory note's (X1)-(X3) at the pinned commit %s;" % PINNED_COMMIT,
        "three differences: (1) compute_linear_normal_form is a deprecated wrapper of get_linear_normal_form (linear_normal_form.py:150-157);",
        "  (2) betx_edw_teng/alfx_edw_teng/bety_edw_teng/alfy_edw_teng/g_edw_teng and f1001/f1010 are derived from W (lattice_functions_from_W.py:86-116);",
        "  (3) the use_full_inverse branch (lattice_functions_from_W.py:240-282) is new; the default branch is the one this table uses",
        "pip freeze:",
    ] + ["  " + l for l in freeze.splitlines()]
    return "\n".join(lines) + "\n"


def parse_table(text):
    header, cells, colnames = [], {}, None
    for line in text.splitlines():
        if line.startswith("#"):
            header.append(line)
        elif colnames is None:
            colnames = line.split("\t")
        else:
            f = line.split("\t")
            cells[tuple(f[:4])] = f[4]
    return header, cells


def regenerate_diff(new_text, committed_path):
    old_h, old_c = parse_table(open(committed_path).read())
    new_h, new_c = parse_table(new_text)
    ndiff = 0
    for k in sorted(set(old_c) | set(new_c)):
        a, b = old_c.get(k, "(missing)"), new_c.get(k, "(missing)")
        if a != b:
            ndiff += 1
            print("REGEN-DIFF %s %s %s" % (" ".join(k), a, b))
    hdiff = sum(1 for a, b in zip(old_h, new_h) if a != b) + abs(len(old_h) - len(new_h))
    print("REGEN-DIGEST cells %d differing %d header_lines_differing %d" % (len(old_c | new_c), ndiff, hdiff))
    return ndiff


def main():
    regen = os.environ.get("OCTOPUS_STAGE8_REGENERATE", "") == "1"
    _, _, maps = read_maps_table(MAPS_PATH)
    fw_text = record_future_warning(maps)
    rows, beam = layer_C0(maps)
    rows += layer_C1(maps)
    rows += layer_C2(maps)
    rows += layer_C3(maps)
    text = table_text(header_lines(beam, fw_text), rows)
    nfail = sum(1 for w in WITNESSES if not w[5])
    print("GEN-DIGEST rows %d witnesses %d failing %d" % (len(rows), len(WITNESSES), nfail))
    if regen:
        tmpdir = tempfile.mkdtemp(prefix="xsuite_regen_")
        tmp_path = os.path.join(tmpdir, os.path.basename(TABLE_PATH))
        atomic_write(tmp_path, text)
        print("regenerated table written to %s" % tmp_path)
        ndiff = regenerate_diff(text, TABLE_PATH)
        sys.exit(1 if (ndiff or nfail) else 0)   # a red GEN-WITNESS fails the regenerate run as well
    if nfail:   # never freeze a table from a red run: nothing is written
        print("GEN-ABORT %d witness(es) failed; table and sidecar NOT written" % nfail)
        sys.exit(1)
    atomic_write(TABLE_PATH, text)
    atomic_write(SIDECAR_PATH, sidecar_text(sha256_of(os.path.abspath(__file__)), fw_text, beam))
    print("xtrack %s -> %s (%d rows); sidecar %s" % (xt.__version__, TABLE_PATH, len(rows), SIDECAR_PATH))
    sys.exit(0)


if __name__ == "__main__":
    main()
