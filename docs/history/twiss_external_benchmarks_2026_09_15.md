# Stage 8: the twiss analysis against three external codes (2026-09-15)

Stage 8 of the twiss/dispersion work benchmarks `TwissDispersionAnalysis`
against three external codes on one shared set of lattice fixtures: MAD-X
5.03.06 `twiss`, the PTC `ptc_twiss` distributed with the same MAD-X binary,
and xtrack 0.112.0. Each code is run once by a generator that freezes a
committed reference table under `validation/reference/`; each benchmark is
then a pure-Julia consumer that reads the committed table, converts the
external one-turn map into Octopus coordinates by a single measured law, runs
the analysis, and gates or records every row. This record carries the beam,
the fixtures, the law and its measurement, the tolerance classes, the three
benchmarks, the findings, the decisions, the re-run commands and what is not
verified.

## 1 Purpose and scope

What the batch proves: that the Octopus twiss/dispersion analysis reproduces,
on the same matrices, the lattice functions, coupling parameterization,
dispersion and tunes that three independent codes print, once the coordinate
conventions are converted by an explicitly measured law; and that the law is
not a fit, because each of its factors is pinned by a separate witness row
that turns red on its own when the factor is dropped (three injected-defect
modes do exactly that).

What it does not prove. This is a *matrix-level* benchmark on one-turn maps
one code exported and the other consumed, or on two maps of the same analytic
cell; it is not a tracking benchmark, it does not exercise nonlinear optics
(`no=1` in PTC, linear maps elsewhere), and it certifies exactly one version
of each external tool.

The three codes and versions (the `tool:` lines of the three table headers):

| code | version | invoked as | reference table |
|---|---|---|---|
| MAD-X `twiss` | 5.03.06 | `twiss, betx=1, bety=1, rmatrix` (initial rows) and `twiss, rmatrix` (periodic rows) | `validation/reference/twiss_madx_5.03.06.tsv` |
| PTC `ptc_twiss` | PTC as distributed with MAD-X 5.03.06 | `ptc_create_layout, model=1, method=6, nst=10, exact=true, time=false` | `validation/reference/ptc_twiss_madx_5.03.06.tsv` |
| xtrack | 0.112.0 (xobjects 0.6.10, xpart 0.23.18, numpy 2.4.6, python 3.11.5) | `get_linear_normal_form`, `Line.twiss(method='4d')` and `(method='6d')` | `validation/reference/xsuite_twiss_xtrack_0.112.0.tsv` with sidecar `xsuite_twiss_provenance.txt` |

The tracked files of the batch: the shared fixture module
`validation/twiss_benchmark_cells.jl`, the three generators and three
consumers named in sections 5-7, the four tables under `validation/reference/`
with the xtrack sidecar, and the suite contract
`src/contracts/twiss_external_reference.jl` (section 11).

## 2 The beam and the fixtures

**The pinned beam.** Every fixture in every code is a proton at 3.0 GeV TOTAL
energy with the Octopus proton mass: `reference_beta_gamma(3.0e9, PMASS_EV)`
gives `beta0 = 0.9498330546994187`, `gamma0 = 3.1973667700405533`, `p0c =
2.8494991640982566e9` eV (`validation/twiss_benchmark_cells.jl`, constants
`BENCH_BETA0_PIN`, `BENCH_GAMMA0_PIN`, `BENCH_P0C_EV`). The deck lines are
pinned literally (D13):

    MAD-X / PTC   beam, mass=0.93827208943, charge=1, energy=3.0;
    xtrack        xt.Particles(mass0=938.27208943e6, p0c=2.8494991640982566e9)

The MAD-X line carries **no** `particle=`: MAD-X 5.03.06 silently ignores
`mass=` when `particle=proton` is also given and falls back to its own proton
mass, which moves `beta0` by 8.86e-10 -- three decades above the 1e-12 pin and
enough to shift the dispersion rows. Every driver reads `beta0` and `gamma0`
from the external code's OWN printed header (TFS `PC`/`ENERGY`/`GAMMA`, or the
xtrack `particle_ref`) and asserts `|beta0_header - 0.9498330546994187| <=
1e-12`; the MAD-X and xtrack tables record the residual
`1.1102230246251565e-16` in their headers, and the PTC consumer prints it as
its `beta0_header_vs_pin` witness on every row.

**The fixtures.** Every element number lives once, in
`validation/twiss_benchmark_cells.jl`, copied from the identity contract
recipes in `src/contracts/twiss_dispersion_identity.jl` and from
`validation/lattice_cells.jl`; each Octopus cell is a Tuple of compiled
runtime maps with `nst` (default 64) and `integrator_order` (default 4).

| id | recipe | external twin | used by | role |
|---|---|---|---|---|
| `S0` | `DriftSpec(L=10.0)` | `dr: drift, l=10;`; `xt.Drift(length=10)` | A, B, C | the conversion witness, run first in every driver |
| `U1` | FODO: qf `(L=0.3, kn=(0,1.6))`, drift 1.2, qd `(L=0.3, kn=(0,-1.6016))`, drift 1.2 | `quadrupole, l=0.3, k1=1.6` / `k1=-1.6016` | A, B (5D), C | the uncoupled control and the first ladder point |
| `U2` | DBA: qd(0.25,-1.1) d(0.6) sbend(L=1.0, angle=0.2) d(0.6) qf(0.35,1.5) d(0.6) sbend d(0.6) qd; cell length 5.25 m | `sbend, l=1.0, angle=0.2`, e1=e2=fint=0, `option, rbarc=false` | A, B, C | the dispersive cell; carries the row-5 sign witness |
| `K1` | coupled FODO: qf(0.2,+1) dr(1.0) qd(0.2,-1,tilt=0.05) dr(1.0) | `tilt=0.05`; xtrack `rot_s_rad=0.05` | A, C | the well-separated Edwards-Teng fixture and the free cross-code row |
| `K2` | `U2` with qf `tilt=0.05` | same | A, B, C | coupling on a dispersive cell |
| `R_0`, `R_0.01`, `R_0.1`, `R_pi8`, `R_pi4` | rolled equal-tune FODO qf(0.2,+1,tilt=theta) dr(1.0) qd(0.2,-1,tilt=theta) dr(1.0) | same tilts | A3, C3 | the degenerate pair: the TWCPIN branch hazard and the cluster reason symbols |
| `Rd_1e-3`, `Rd_1e-6` | `R(pi/4)` with kd detuned, kd = -(1+eps) | same | A3, C3 | the detuned controls that show the approach to degeneracy |
| `W1` | `ThinRFCavitySpec(400.0e6; strength=0.02)` ALONE | PTC `rfcavity, l=0, volt=60.0, freq=400.0, lag=0.5`; xtrack `xt.Cavity(voltage=5.6989983281965137e7, frequency=400e6, lag=0)` | witness rows only | pins the sixth coordinate: V = strength * E_total for PTC, V = strength * p0c for xtrack |
| `W2` | `QuadrupoleSpec(L=0.2, kn=(0,1.0), tilt=pi/4)` ALONE | `quadrupole, l=0.2, k1=1, tilt=pi/4` | witness rows only | pins the tilt rotation sense |
| `B4` | `U2` + `W1`, cavity last, BARE compile | PTC `use, period=cell`, `icase=6`, `time=false` | B (6D) | the single-cell 6D row |
| `B4K` | `K2` + `W1`, bare | same | B (6D) | 6D with transverse coupling: the `BETA_jk` index-order row |
| `G6` | six `U2` cells (C = 31.5 m) + `ThinRFCavitySpec` last, bare; h = 12, frf = 1.0847725186970942e8 Hz, strength = V/E_total = 0.00066666666666666664 at V = 2.0 MV | PTC `ring6` at 2.0 and 0.2 MV | B (6D) | the 6D periodic ring; the 4-cell ring is resonance-poisoned and is not used |
| `T6` | `U2` + `ThinRFCavitySpec(400e6; strength=-0.02)`, TASK-compiled | xtrack twin line with `xt.Cavity(lag=0)` | C3 | the 6D lattice twin; the strength flip is mandatory (see section 7) |
| `B5` | `B4` + `ThinCrabCavitySpec{1}(400e6; strengthX=(-0.05,))`, bare | none | C1 | crab block, matrix level only |
| `D6_*`, `D8_*` | the first three dense 6x6 and three dense 4x4 draws of `MersenneTwister(20260911)` in the identity contract's draw order, plus the single manufactured coasting map | none | C1 | convention-free dense maps |

`K1`, `K2` and `B4K` use tilt 0.05 (`K_TILT` in the fixture module). The
rolled angles are `theta` in `{0, 0.01, 0.1, pi/8, pi/4}` and the detuned
controls `eps` in `{1e-3, 1e-6}` (`ROLLED_THETAS`, `RD_EPSILONS`).

The Octopus side of every fixture is exported once to
`validation/reference/twiss_benchmark_maps.tsv` (one row per fixture and
compile mode: id, compile, nst, beta0, gamma0, C, m11..m66 at `%.17g`), the
interface between the fixture module, the MAD-X and xtrack consumers and the
xtrack generator; any fixture change re-freezes it and the sidecar digest.

## 3 The conversion law

Every external one-turn map enters the analysis through one law, stated once
in `validation/twiss_benchmark_cells.jl` (`convert_map`, with `shear(u)`,
`FLIP` and `J0(beta0)` exposed) and repeated in the header of
`validation/reference/twiss_benchmark_maps.tsv`:

    M_oct = Sh(u) . J0 . F . M_ext . F^-1 . J0^-1

with `Sh(u)` the identity except entry (5,6) = u, and C the cell length. Per
code, with the Octopus compile mode it partners:

| external code | `J0` | `F` | `u` (bare partner) | `u` (task partner) |
|---|---|---|---|---|
| MAD-X `twiss` | `diag(1,1,1,1,beta0,1/beta0)` | `I` | `-C/gamma0^2` | 0 |
| xtrack | `I` | `I` | `-C/gamma0^2` | 0 |
| PTC `time=false` | `I` | `diag(1,1,1,1,-1,1)` | 0 | `+C/gamma0^2` |

The two Octopus compile modes are the reason `u` exists. A *bare* cell has no
velocity slip: a drift has (5,6) = 0 exactly. The same specs through
`TrackingTask` (the *task* compile, survey-bound cavity; a cavity-free cell
gets a marker cavity of strength 1.0e-30) gain (5,6) = +C/gamma0^2. So PTC
`time=false` partners the bare compile while MAD-X-after-`J0` and xtrack
partner the task compile, and no 6D tune, longitudinal beta or Q_s row may
cross that boundary. Each driver asserts the partnership: benchmark A
recomputes `u` from the MAD-X header's own C and `gamma0` and compares the
converted (5,6) with the Octopus bare (5,6) on U2, reading
`-0.081412323090219285` against `-0.081412323096546585`, a difference of
`6.3272997952168453e-12`.

The law deliberately does **not** close into a similarity: `zeta = z + s
delta/gamma0^2` advances by C per turn, so the no-slip and the slip machine
are different dynamical systems, not one system in two coordinates; `Sh` is a
LEFT factor and the partnership rule replaces a similarity argument. `F`,
`J0` and `Sh` act only on rows and columns 5 and 6, so the 4x4 transverse
block is identical in all four conventions and every quantity built from it
alone -- transverse tunes of a coasting map, the Edwards-Teng R, lambda, det
R, the ET mode Twiss functions, the Mais-Ripken projections of a coasting map
-- is convention-free and compared with NO conversion at TOL-A. Not invariant:
the dispersion columns and, for a bunched map, the spectrum.

### How each factor was measured

**The drift (5,6).** `S0` is a lone 10 m drift at the pinned beam, run first
in all three drivers, each asserting it as a FORMULA in its own header's
`beta0`, `gamma0` and L, never as a pinned digit string. MAD-X prints
`RE56 = 1.0842277723823459`, matching the analytic `L/(beta0^2 gamma0^2)` to 0
in the table's witness line; converted that becomes `+L/gamma0^2`, the shear
derived from the header is `-0.97817168200370863` (matched to 0), and the
converted `S0` map equals the Octopus bare map to `1.1102230246251565e-16`.
xtrack's drift prints `+0.97817168361909312` against the analytic
`0.97817168200370863`, i.e. `1.6153844928368244e-09` -- already
`+L/gamma0^2`, and the reason there is a TOL-D class at all. PTC `time=false`
prints an identically zero (5,6): hence `u = 0` there, and the bare compile is
its partner.

**The cavity (6,5).** `W1`, a lone 400 MHz cavity of strength 0.02, pins the
sixth coordinate's scale, which no drift row can. The same kick is `V = strength * E_total` for PTC (60.0 MV, sixth
coordinate `delta`) and `V = strength * p0c` for xtrack (5.6989983281965137e7
V, sixth coordinate `pzeta = ptau/beta0`), the twins differing by exactly
`1/beta0`. The Octopus bare `M65` is `0.18584658879140892`; PTC's flipped
`RE65` reads `0.185846588444706` (section 6 for the remaining 3.467e-10) and
xtrack's `r65` `-0.18584658855011466` against `-0.18584658879140895`, a
relative `2.4129429010422143e-10`.

**The sign of row 5.** The drift (5,6) entry and symplecticity are both
invariant under a flip of row and column 5, so no drift row decides between
`z = +beta0 T` and `-beta0 T`; a dispersive-cell SIGN row runs before any
converted map is analysed: on U2 MAD-X prints `RE51 =
-0.4594575987361017` and `RE52 = -0.74627886420805112`, whose signs the
table's witnesses compare against Octopus, reading `-1` against `-1`; the
xtrack generator records `-1 -1` on its `zeta` row. If either fails, the
driver stops.

**The T orientation of PTC.** `ptc_twiss` prints its `RE` rows in the
`ptc_track` T orientation, where row 5 is the +path-length excess, the
opposite of `twiss`'s T. The flip `F = diag(1,1,1,1,-1,1)` is therefore
applied by the reader, and the table is committed exactly as PTC printed it
(decision D7) so a future reader can re-derive the flip. Two rows pin it: the
symplectic residual of the B4 map is `1.4176806664743553` before `F` and
`4.6629367034256575e-15` after it -- the un-flipped matrix is not a symplectic
map at all -- and `ALFA33`, being odd under `F`, matches the sign-flipped
Octopus mode-3 alpha, `0.14225874842551697` against `0.14225874842495717`,
`5.5980220459161956e-13`.

**The `J0` of MAD-X.** MAD-X's sixth coordinate is `PT`, not `delta`, so its
`DX` column is `dx/dPT` and the Octopus `eta = dx/ddelta` is `beta0 * DX` --
the same `beta0` in `J0 = diag(1,1,1,1,beta0,1/beta0)`. The generator measures
this: on U2 the printed `DX` at the cell start is `0.74357707720782673`,
`beta0 * DX` is `0.70627408664877567`, and the central finite difference of
the closed orbit at `deltap = +-0.0001` gives `0.70627408378814105`. Their
ratio `0.94983305085229297` reproduces the header `beta0`
`0.94983305469941881` to `3.8471258401173714e-09`, the truncation -- which is
why the two rows `U2_FD/DX_vs_beta0_header` and `U2_FD_vs_beta0*DX_relative`
are gated at their own coarser constant `TOL_FD = 1e-8`
(`validation/twiss_madx_benchmark.jl`), not at TOL-B. Dropping `J0` (the `drop_J` defect) moves
the partnership witness to `-0.034559825812292666`.

**The tilt sense.** `W2`, a lone quadrupole at `tilt=pi/4`, pins the rotation
sense of every coupled fixture: MAD-X's `tilt=t` map equals `Rt(t) M(0) Rt(t)'`
with `Rt = kron([c -s; s c], I2)` to `5.5511151231257827e-17` (the other sense
misses by `0.40000533333615529`), and xtrack's `rot_s_rad=+t` equals the
`SRotation(+t)` sandwich to `8.2399365108898337e-18`, not `k1s`.

## 4 Tolerance classes

Six classes, named constants at the top of each consumer. A row's class is set
by the SOURCE of its matrix, not by the quantity's name: a purely transverse
xtrack quantity of a linear cell is round-off exact, so it stays at TOL-A.

| class | value | applies to | rationale |
|---|---|---|---|
| TOL-A | 1e-12 relative; 1e-13 absolute on `cos mu`, `sin mu` | beta, alpha, gamma, the four Edwards-Teng R entries, the normalizer projectors -- everything built from the convention-free 4x4 block, in all three benchmarks | both sides are the same input matrix; the observed spread is a few units in the last place to a few 1e-14 on the coupled fixtures. The tightest gated row of benchmark A is `K1 ET_bety`, `38.365210045104469` against `38.365210045102693`, `1.7763568394002505e-12` against the printed bound `9.9999999999999998e-13`, relative -- about a decade of margin, no more |
| TOL-B | 1e-12 relative | MAD-X's momentum column, `beta0 * DX` and `beta0 * DPX` | MAD-X's two routes to the same number agree to round-off and `set, format="22.16e"` prints 16 digits; `beta0` comes from the header, so its own provenance does not enter. The U2 finite-difference witness has its own coarser constant `TOL_FD = 1e-8` in the same consumer, sized to the `deltap = +-0.0001` truncation |
| TOL-C | 1e-9 relative on `DISP1..DISP4`, `BETA_jk`, `ALFA_jk`, `GAMA_jk`; 1e-10 absolute on `cos mu`; 1e-12 on the symplectic residual of `F RE F` | every gated optics row of benchmark B | PTC at `method=6, nst=10` integrates thick elements; its symplectic residual sits at a few 1e-14 on the rings, about 1.4 decades under the 1e-12 gate. The W1 cavity row has its own tighter 1e-10 (`TOL_W1`) |
| TOL-D | 1e-7 relative | anything in benchmark C that touches rows or columns 5-6 of an xtrack map | xtrack's `R` is a 13-particle central difference with steps `dx 1e-6, dpx 1e-7, dy 1e-6, dpy 1e-7, dzeta 1e-5, ddelta 1e-6` (table header). On the exactly-known drift at the fixture beam the miss is `1.6153844928368244e-09`; on the W1 cavity row `2.4129429010422143e-10`. No xtrack longitudinal row can ever pass 1e-12, and 1e-7 keeps about 1.8 decades over the measured floor |
| TOL-E | fitted convergence order `4.0 +- 0.3` over the ladder `nst in (4, 8, 16, 32, 64)` at `integrator_order=4`, plus an `nst=64` residual cap | the model layers of all three benchmarks | the gate is the fitted ORDER, not a residual: a thick-element model residual is a physical discretization error, and its absolute size depends on the cell. The cap is an upper bound only, frozen at ten times the maximum measured on the first passing native run with its provenance line in the script (decision D6): `NST64_CAP = 10 * 7.8839690331733436e-10` in benchmark A, `LADDER_CAP_64 = 8.4916074172269873e-09` in benchmark B, `min(10 * 2.3920456726500561e-09, 1e-8)` in benchmark C |
| TOL-F | 1e-10 absolute | the degenerate rolled cells `R_*` and their detuned controls `Rd_*` | near a degenerate eigenvalue pair the two gate arms differ at sqrt(eps), so a tighter pin would be a single-arm observation rather than a physics statement. The measured two-arm spread is recorded |

Two deviations from the plan: benchmark C gates its C1 dispersion rows at
TOL-A rather than TOL-D (both sides are the Octopus map itself, no finite
difference involved), and D6 replaced the plan's `nst=32 < 1e-9` residual
gate with the fitted order plus a frozen cap, because the `nst=32` residuals
do not reach 1e-9 (section 12).

## 5 Benchmark A: MAD-X twiss

Generator `validation/generate_madx_twiss_reference.jl`, table
`validation/reference/twiss_madx_5.03.06.tsv` (92 lines: 67 header lines, one
column row, 24 data rows, 56 columns), consumer
`validation/twiss_madx_benchmark.jl`, tag `TW-MADX`. The generator runs MAD-X
with `option, -echo, -info, -warn; option, rbarc=false; set, format="22.16e";
use, period=cell;` and writes per fixture an `initial` row (the one-turn map,
NaN optics) and a `periodic` row (the optics and its own map), the two maps
agreeing to between `3.3306690738754696e-16` and `3.5527136788005009e-15`; a
third row type (`fd_deltap`, U2 only) carries central finite differences of
the closed orbit at `deltap = +-0.0001`.

**Layers.** A0, the convention witnesses of section 3, run before anything
else; A1, the transverse optics -- `betx`, `alfx`, `bety`, `alfy`, which in
MAD-X are the Edwards-Teng MODE functions, and the R entries `r11..r22`, which
are `C^+/gamma` of `M = V U V^-1` and equal Octopus's `form1.R` with no
transpose; A2, the `nst` model ladder; A3, the rolled family; A4, the
recorded cross-code `K1` row (MAD-X `q1`, `q2`, `betx`, `alfx`, `bety`, `alfy`
beside xtrack's `qx`, `qy`, `betx_edw_teng`, `alfx_edw_teng`, `bety_edw_teng`,
`alfy_edw_teng`, `betx`, `bety`, and `madx_lambda_from_detR_vs_xtrack_g_edw_teng`);
A5, the recorded seed row of the rolled family, both signs of `tan theta`.

**What is gated.** The convention witnesses at 1e-12 or 1e-14; A1's mode Twiss
and `cos mu`/`sin mu` at TOL-A; the `K1` block entries `r11..r22` =
`0.86201121670608871, -0.020416340718808941, -0.19140492597569572,
1.0534161426817839` at TOL-A; `beta0 * DX` at TOL-B and the U2
finite-difference witness at `TOL_FD = 1e-8`; the ladder's fitted order
at TOL-E under the frozen `nst=64` cap; and the rolled-family analytic anchor
at TOL-F. In total 98 gated rows, 121 witness lines, 110 recorded lines.

The A3 anchor `rolled_exact_anchor` evaluates `cos mu = tr(Dr Qd Dr Qf)/2` from the
fixture's own thick-quadrupole and drift 2x2 blocks (L=0.2, k=+-1, drift 1.0),
giving `0.97440039720586435` and `q = 0.036089644373316153`, and the gated
rows read `1.1102230246251565e-16` and `8.3266726846886741e-17`.

**What is recorded and why.** MAD-X's rolled-cell tunes for `R_0.01`, `R_0.1`
and `R_pi8` are a DIRECTIONAL SENTINEL of TWCPIN's failure (section 8), never
pinned digits; `R_pi4` has no periodic solution and only its initial-condition
map is kept; `S0` and `W2` have no periodic file because a lone drift or
quadrupole is not a stable cell. `Rd_1e-6` is recorded because `analyze`
returns `:failed` on it, the detuning being below the analysis's own cluster
resolution (`Rd_1e-3` resolves at `3.009598136315693e-12`); the `nst=32`
residuals because they sit above 1e-9 (`U2 1.2613734057254078e-08`), which is
why only `nst=64` is capped.

**The digest line** (comparisons made, failed, worst value-over-tolerance
ratio), one line per consumer that a gate can diff:

    TW-MADX-DIGEST 387 0 0.40503179603364126

with fitted ladder orders `U1
4.0013414895306783`, `U2 3.9988016758485325`, `K1 4.0004537849572168`, `K2
3.9987980534024454`.

**Injected defects.** `drop_J` sets `J0 = I` in the conversion: four witnesses
fail, digest `35 4 10605609037863.729`, exit 1. `transpose_R` transposes
`form1.R` before the R rows: `r12` and `r21` on K1 turn red
(`0.17098858525688368`, `0.17098858525688457`), digest `387 2
170988585256.88458`, exit 1.

## 6 Benchmark B: PTC ptc_twiss

Generator `validation/generate_ptc_twiss_reference.jl`, table
`validation/reference/ptc_twiss_madx_5.03.06.tsv` (27 lines: 16 header lines,
one column row, 10 data rows, 91 columns), consumer
`validation/twiss_ptc_benchmark.jl`, printed tag `TW-PTC`. The PTC flags are
`ptc_create_layout, model=1, method=6, nst=10, exact=true, time=false`
(decision D4). `method=2`, which the older
`validation/generate_ptc_reference.jl` keeps, carries an orbit artifact: on U2
at `icase=5` the closed orbit falls off as `nst^-order` with fitted order
`1.9858063694406614` over `nst = 1, 10, 40, 160`, and `method=6, nst=10`
removes it (recorded in the table header and in `validation/README.md`).

**Rows.** 5D rows (`icase=5, no=1, closed_orbit=true, rmatrix`) on U1, U2 and
K2; 6D rows (`icase=6`) on B4 and B4K at 60 MV / 400 MHz and on G6 at 2.0 and
0.2 MV with h = 12, `lag=0.5` (the stable phase with `time=false`); and
witness rows (`icase=6, closed_orbit=false, betx=bety=betz=1`) on `S0`,
`S0_pt` (a `pt=1e-3` initial condition) and `W1`.

**Layers.** B0, the conversion witnesses and the header pins; B1, the 5D
optics of U1, U2 and K2 at TOL-C; B2, the 6D optics at TOL-C; B3, the
`BETA_jk` index-order decision on the coupled rows; B4L, the `nst` ladder on
6D rows. **Gated:** the header `beta0` against the pin
(`0.94983305469941881` against `0.9498330546994187`,
`1.1102230246251565e-16`); the symplectic residual of `F RE F` at 1e-12; the
cavity rows against the Octopus twins at 1e-10; the 5D rows
`DISP$(k)_vs_physical.eta[$(k)]` (k = 1..4), `BETA11`, `BETA22`, `ALFA11`,
`ALFA22`, `cos_mu1`, `cos_mu2`, the PTC modes matched to the Octopus tunes
by `cos mu`; the 6D `BETA_jk`, `ALFA_jk`, `GAMA_jk` at TOL-C -- `B4 BETA22`
`8.4062705380446641` against `8.4062705380116149` and `G6_0.2MV BETA33`
`117.96964928170352` against `117.96964928121247` are representative;
`ALFA33` sign-flipped; and the ladder's fitted order. Digest:

    TW-PTC-DIGEST 257 0 0.59499739575161859

with fitted orders `U1 3.9571693644344288`, `U2 3.9789324501096024`, `K2
3.9789636821507823`, `B4 3.9764988582412593`, `B4K 3.9766859084864121`,
`G6_2.0MV` and `G6_0.2MV` both `3.9481404510869567`, and the largest `nst=64`
residual `5.0524842989951857e-09` against the frozen cap
`8.4916074172269873e-09`.

**What is recorded.** The 6D `DISP` rows of B4, B4K, G6_2.0MV and G6_0.2MV
(name `DISP$(p)_fixed_z_dx_ddelta_vs_physical.graph[$(p),2]`; `B4 DISP1
0.73354515845480206` against `0.73354515845480184`) are recorded, not gated,
because the twin dispersion at PTC's effective beam has not been derived --
the 5D `DISP1..DISP4` rows of U1, U2 and K2 are gated at TOL-C; and the W1
witness evaluated at the
HEADER `beta0` is recorded for the reason below.

### The PTC internal proton mass (decision D19)

The W1 thin-cavity witness compares PTC's flipped `M65` with the analytic
`strength * k / beta0^2` at the table header's own `beta0`, and it MISSES:
`0.185846588444706` against `0.18584658879140892`, a difference of
`3.4670291637617368e-10`, above the 1e-10 cavity bound. The cause is neither
the conversion nor Octopus. PTC 5.03.06 evaluates the
cavity kick at its OWN internal proton mass, `0.938272081358` GeV, whatever
the deck's `beam, mass=...` says, while the TFS header still prints
`PC/ENERGY` from the deck mass: decks with mass `0.93827208943`, the MAD-X
default, `0.9383` and `0.93837` all print the same `RE65` bit-identically,
while mass `0.95` is honoured. At the internal mass the effective beam is
`beta0_ptc = 0.94983305558539111`, `gamma0_ptc = 3.1973667975476534`; the
header `beta0` is `8.8597229552789258e-10` below it, and since `beta0` enters
`M65` squared the miss is twice that relative gap. The fixture module derives
`PTC_BETA0` and `PTC_GAMMA0` with `reference_beta_gamma` from
`PTC_INTERNAL_PROTON_MASS_GEV = 0.938272081358` rather than pinning a digit
string, asserting them against `PTC_BETA0_PIN = 0.94983305558539122`.

The decision: a benchmark compares Octopus to the external code AS IT RAN, so
the Octopus twin of every PTC row WITH A CAVITY (`W1`, `B4`, `B4K`,
`G6_2.0MV`, `G6_0.2MV`) is compiled with `cavity_beta0 = PTC_BETA0`,
`cavity_gamma0 = PTC_GAMMA0` -- the table header's "twin rule". Those twin
rows agree to `1.1102230246251565e-16` on B4, `4.3368086899420177e-19` on
`G6_2.0MV` and `5.4210108624275222e-20` on `G6_0.2MV`, while the witness at
the header `beta0` stays RECORDED with its `3.467e-10`, labelled as the PTC
internal-mass effect, so a future PTC that changes the behaviour shows up as a
changed number. The D13 header pin still asserts the deck beam. Two
consequences propagated: the G6 cavity strength was re-derived as `V/E_total =
0.00066666666666666664` (W1's law), not `V/p0c`, which moved eight cells of
the maps table (`m65` now `0.0016800106017876653`, bare `m66`
`0.99606115620863456`) and re-froze it with the xtrack sidecar that gates its
sha256.

### The coasting completion of `icase=5` maps

At `icase=5`, the coasting case, PTC prints `RE55 = 0` and does not fill row
5 of `RE`. The consumer completes the 5D maps of U1, U2 and K2 to a coasting
6x6: row 5 is not read from the table, only the 4x4 block and the momentum
column carry information, and the table header says so. The `icase=6` rows
certify the longitudinal block.

**Injected defects.** `drop_F` omits the flip: digest `180 30
2824760677698.0918`, exit 1, the first red line the W1 row at
`-0.185846588444706` against `0.18584658844470603`. `cavity_57MV` scales every
Octopus cavity twin by 57/60: digest `257 14 92923294.222352341`, exit 1, the
W1 twin reading `0.17655425902247079`.

## 7 Benchmark C: xtrack

Generator `validation/generate_xsuite_twiss_reference.py`, table
`validation/reference/xsuite_twiss_xtrack_0.112.0.tsv` (2881 lines: 23 header
lines, one column row, 2857 long-form rows with the columns `layer fixture
compile quantity value`) with the sidecar
`validation/reference/xsuite_twiss_provenance.txt`, consumer
`validation/twiss_xsuite_benchmark.jl`, printed tag `TW-XSUITE`. The generator
is the only python in the batch; the consumer is pure Julia and never shells
out.

**The generator reads the Octopus maps.** Unlike A and B, benchmark C builds
most fixtures' one-turn maps from
`validation/reference/twiss_benchmark_maps.tsv` and runs xtrack's normal-form
and lattice-function code on them, which is why the C1 rows -- two readouts
of the SAME matrix -- sit at TOL-A. The sidecar records the
generator's sha256, the input maps sha256
(`5417a9a604123973f0320b4f7d756923d4ab5d48a1beedcb4cfab91226f278f7`), the
interpreter and the pinned commit, and the consumer GATES the maps digest
against it, so a re-frozen maps table with a stale xtrack table fails loudly.

**Layers.** C1, the normalizer and dispersion:
`get_linear_normal_form(only_4d_block=True)` on the coasting and 4x4 maps and
the full 6D call on B4, B5, T6-task and the dense `D6_*` draws, reading `betx`
= `W00^2 + W01^2` (Mais-Ripken), `betx_edw_teng`, `g_edw_teng`, the `dx`
family and the `dx_zeta` first (X2) column. C2, rows and columns 5-6 with the
`nst` ladder (`Line.twiss(method='4d')` on real element lines). C3, the 6D
lattice twin `T6` (`Line.twiss(method='6d')` and `get_R_matrix`).

**The finite-difference map and TOL-D.** xtrack's `R` for a real element line
is the 13-particle central difference of section 4 (steps in the table
header), so every C2 and C3 quantity touching rows or columns 5-6 is a TOL-D
(1e-7) quantity by construction. The measured
floor is `1.6153844928368244e-09` on the drift and `2.4129429010422143e-10` on
the W1 cavity row, and the maps carry `|eigenvalue| - 1` up to about 4e-11.
Purely transverse quantities of a linear cell stay at TOL-A.

**The Edwards-Teng form by label.** xtrack prints no R matrix; it prints
`betx_edw_teng` (the (T15) ET beta) and `g_edw_teng` (lambda alone) BY LABEL,
with labels assigned by projection (mode 3 = largest `|v[5]|`, then mode 2 =
largest `|v[2]|`). A label does not say which Edwards-Teng form the number
belongs to, and in a degenerate pair the labels are projection-decided and
discontinuous in the roll angle. The form is therefore selected from
Octopus's own internal (T15) lambda, never from the external labels, which puts `Rd_1e-3`, `D6_3` and `D8_3`
in form 2 with `|lambda_internal - g|` at worst `4.2743586448068527e-13`
(`physical_h_vs_det(U_ls)` is gated alongside, worst
`1.6819878823071122e-14`). The general rule: modes are matched by EIGENVALUE,
never by label position, and `cos mu`/`sin mu` are compared, never a
fractional tune -- Octopus can orient the synchrotron mode negatively, PTC
prints `QS` signed and can print `Q1` as `1 - q`, xtrack folds to `(-pi,
pi]`.

**The 6D twin (decision D5).** C3 is the one place where a real 6D lattice is
twinned element by element: `T6` is U2 plus a 400 MHz cavity, TASK-compiled,
against an xtrack line with `xt.Cavity(lag=0)`; D5 admits it as a GATED
layer. The four longitudinal witnesses pass at TOL-D -- `r55` `1` against
`0.99999999999999978`, `r56` `0.43212780506815801` against
`0.43212780995540045`, `r65` `-0.18584658855011463` against
`-0.18584658879140895`, `r66` `0.91969052150635877` against
`0.91969052059788692` -- and the T6 longitudinal mode is certified at
`0.14974352568848381` against `0.14974352201203292`. The Octopus cavity
strength in T6 is `-0.02`, the FLIP of the B4 recipe, and the flip is
mandatory: the B4 recipe task-compiled at 3 GeV is longitudinally UNSTABLE
(`:unstable_spectrum`) because the fixture's `gamma0` sits below its
transition gamma, while `-0.02` (bit-identical to a phase of pi) is stable.

**Gated, recorded, digest.** 623 gated, 357 recorded, identical on both arms,
exit 0:

    TW-XSUITE-DIGEST 1060 0 0.99100645626558559
    TW-XSUITE-NOTE digest gated=623 recorded=357 defect=none PASS

Fitted ladder orders `U1 4.0013416877743504`, `U2 3.7026980631203243`, `K1
4.00046327507245`, `K2 3.7049247094295761`; the worst row is the U2 fitted
order at `0.29730193687967565` against the TOL-E bound `0.29999999999999999`,
the digest's third field. `Rd_1e-6` is recorded, as in A.

**Injected defect.** `drop_shear` leaves xtrack's slip in the converted map:
the eight C2 `rows_cols_5_6_maxscaled_nst64` lines fail (`U1
0.2934515050746257`, `U2 0.51354012806127169`, the `K1`/`R_`/`Rd_` family
`0.23476120405192902`, `K2 0.5135401282209735`), digest `1060 8
5135401.2822097354`, exit 1. C3 and the C0 witness are not reached -- itself a
statement about where the shear is load-bearing.

## 8 Findings a future reader needs

**TWCPIN on the degenerate rolled cell.** MAD-X's `twcpin` computes the
Edwards-Teng R as `R = -U/(t + sign(t) sqrt g)` with `t = (trA - trD)/2`,
`U = C + adj(B)`, `g = det U + t^2`. That branch degenerates exactly at
`trA = trD`, the rolled equal-tune FODO: on `R_pi4` MAD-X's periodic `twiss`
fails and writes no periodic TFS file, and on `R_0.01`, `R_0.1` and `R_pi8` it
writes wrong tunes. Octopus does not fail there -- its pass returns `status
:passed` with empty tunes and reason `:cluster_unresolved` on beta, alpha,
gamma and the ET R, cluster `:definite` (D8). MAD-X's rolled tunes are
therefore committed as a DIRECTIONAL SENTINEL (D9): the table records that
MAD-X got them wrong, so a later MAD-X that fixes `twcpin` turns the sentinel
red. R rows are gated only where the branch is well separated (`K1`, `K2`);
xtrack succeeds on the same cells, so the failure is MAD-X's.

**`BETA_jk` index order.** PTC prints a Ripken beta matrix with two indices
and its documentation does not settle which is which. The order was decided by
measurement on the coupled rows: `j` = plane, `k` = mode, i.e. `BETA_jk` =
Octopus `physical.beta[mode k, plane j]`. The other reading is not marginally
worse -- it misses by `2.4808469094089958` on B4K and `4.7146912630910229` on
K2, both in the table header so nobody re-derives it by guessing.

**MAD-X and `ptc_twiss` accept unknown columns silently.** Both put a
misspelled column name in the `*` header and write zero in every row, rc=0,
no warning, so "the header carries every requested column" is a VACUOUS gate;
the load-bearing one is "no requested column is identically zero in every
row", run per fixture by both generators beside eigenvalue-modulus,
closed-orbit and symplectic-residual gates. Relatedly, MAD-X 5.03.06's `twiss` table has NO
Edwards-Teng gamma column, so the benchmark compares lambda recomputed as
`1/sqrt(1 + det R)` from MAD-X's printed `r11..r22` against the Sagan-Rubin
gamma recomputed from MAD-X's exported map. And MAD-X returns rc=0 when
`twiss` fails, so every gate here asserts on numbers, never on exit codes.

**The xtrack deprecation.** `compute_linear_normal_form` is a deprecated
wrapper around `get_linear_normal_form` in xtrack 0.112.0 (`FutureWarning`,
removal before 1.0). The generator calls it once, on K1, and records the
warning verbatim in the table header, so when the call disappears the table
names the site.

**The shear and the task compile.** Pairing an external map with the wrong
Octopus compile mode presents as the `drop_shear` defect does: differences of
order `0.51354012806127169` confined to rows and columns 5-6. `Sh` is a left
factor, not a similarity, so more than `Q_s` shifts with the slip convention.

**Never compare a route field to an external number.** `coasting.eta` is
reciprocal-SCALED, not the physical dispersion, so every script runs
`TwissDispersionAnalysis(strict=false, scaling=:none)` and reads `physical.*`;
`physical.edwards_teng_R` is the PRESENTED form and only form 1's R equals
MAD-X's `C^+/gamma`, so the scripts read form 1 explicitly and PRINT the form.

## 9 Decisions condensed

| id | decision | reason |
|---|---|---|
| D4 | PTC flags `model=1, method=6, nst=10, exact=true, time=false`; `generate_ptc_reference.jl` keeps `method=2` | `method=2` carries a closed-orbit artifact falling off as `nst^-1.9858063694406614`; `method=6` removes it |
| D5 | C3, the 6D xtrack lattice twin with the flipped cavity, is INCLUDED and gated | the owner wants a cavity behind the 6D canonical dispersion; the twin proved stable and its four longitudinal witnesses pass at TOL-D |
| D6 | TOL-E is the fitted order `4.0 +- 0.3` over `nst in (4,8,16,32,64)` plus a frozen `nst=64` cap | a model residual's absolute size is cell-dependent; the order is the physics claim. The plan's `nst=32 < 1e-9` gate is unreachable |
| D7 | the PTC table is committed AS PRINTED; the reader applies `F` | so a future reader can re-derive the flip from the committed numbers instead of trusting the generator |
| D8 | the rolled `R(theta)` Octopus pass is a REASON SYMBOL set (`:passed`, empty tunes, `:cluster_unresolved`, cluster `:definite`); no Octopus tune is asserted | the pair is genuinely unresolved; asserting a tune there would pin an artifact |
| D9 | MAD-X's rolled tunes are a DIRECTIONAL SENTINEL, not pinned digits | MAD-X is wrong there (TWCPIN); pinning its digits would freeze a bug as a reference |
| D13 | the beam pin: `beam, mass=0.93827208943, charge=1, energy=3.0;` with no `particle=`, and the 1e-12 header assert in every driver | with `particle=proton` MAD-X 5.03.06 silently ignores `mass=`, moving `beta0` by 8.86e-10 |
| D15 | one shared fixture module, `validation/twiss_benchmark_cells.jl`; the maps table is the interface | three scripts must not implement one conversion law three ways |
| D16 | each consumer accepts one tracked `OCTOPUS_STAGE8_DEFECT` override (`drop_J`, `transpose_R`, `drop_F`, `cavity_57MV`, `drop_shear`) | a benchmark that cannot be made to fail on demand has not been shown to test anything |
| D17 | `OCTOPUS_STAGE8_REGENERATE=1` on a generator re-runs the external tool and diffs cell by cell; consumers never shell out | the suite must run on a machine with no MAD-X and no python |
| D19 | the Octopus twin of every PTC row with a cavity is compiled at PTC's effective beam (internal proton mass `0.938272081358` GeV); the header-`beta0` witness is recorded | PTC ran its cavity at that mass; a benchmark compares against the code AS IT RAN |

## 10 How to re-run and regenerate

**The consumers** read only committed tables, so they run anywhere; run each
in both gate arms (native, and `OPENBLAS_CORETYPE=Haswell julia -C haswell`);
the three digests of sections 5-7 are identical on both arms with exit 0:

```bash
env CUDA_VISIBLE_DEVICES="" julia --project=. validation/twiss_madx_benchmark.jl
env CUDA_VISIBLE_DEVICES="" julia --project=. validation/twiss_ptc_benchmark.jl
env CUDA_VISIBLE_DEVICES="" julia --project=. validation/twiss_xsuite_benchmark.jl
env CUDA_VISIBLE_DEVICES="" OPENBLAS_CORETYPE=Haswell julia -C haswell --project=. validation/twiss_madx_benchmark.jl
```

Each prints its `TW-*` rows, a `-DIGEST` line and an exit code; a passing run
has zero failures and exit 0. Setting `OCTOPUS_STAGE8_DEFECT` to `drop_J` or
`transpose_R` (A), `drop_F` or `cavity_57MV` (B), `drop_shear` (C) turns named
rows red and exits 1.

**The generators** are the only things needing the external tools: MAD-X
5.03.06 (binary `/usr/local/bin/madx`, overridable with `OCTOPUS_MADX`) for A
and B, an xtrack 0.112.0 environment for C.

```bash
env CUDA_VISIBLE_DEVICES="" julia --project=. validation/generate_madx_twiss_reference.jl
env CUDA_VISIBLE_DEVICES="" julia --project=. validation/generate_ptc_twiss_reference.jl
env XSUITE_ALLOW_KERNEL_COMPILATION=1 <python-with-xtrack-0.112.0> validation/generate_xsuite_twiss_reference.py
```

**Regenerate mode** re-runs the external tool into a temporary path and diffs
every cell against the committed table instead of overwriting it:

```bash
env CUDA_VISIBLE_DEVICES="" OCTOPUS_STAGE8_REGENERATE=1 julia --project=. validation/generate_madx_twiss_reference.jl
env CUDA_VISIBLE_DEVICES="" OCTOPUS_STAGE8_REGENERATE=1 julia --project=. validation/generate_ptc_twiss_reference.jl
env XSUITE_ALLOW_KERNEL_COMPILATION=1 OCTOPUS_STAGE8_REGENERATE=1 <python-with-xtrack-0.112.0> validation/generate_xsuite_twiss_reference.py
```

On the committed tree these print `MADX-REGENERATE-DIFF <committed> <fresh>
differing_cells=0 PASS`,
`TW-PTC-REGEN-DIGEST header_lines=16 cells=910 differing=0 PASS` and
`REGEN-DIGEST cells 2857 differing 0 header_lines_differing 0`.
`OCTOPUS_STAGE8_PYTHON` only records the interpreter in the sidecar.
`OCTOPUS_STAGE8_WORKDIR` names the directory for the decks and TFS files of
the MAD-X and PTC generators (default a git-ignored work directory for MAD-X,
a fresh `mktempdir` for PTC); `OCTOPUS_STAGE8_PTC_TABLE` points the PTC
consumer at a table other than the committed one (development only; the suite
reads the committed table).
Re-freezing the maps table invalidates the xtrack sidecar, so benchmark C's
generator must be re-run after any fixture change.

## 11 The suite contract TwissExternalReferenceContract

`src/contracts/twiss_external_reference.jl` carries the light suite contract
that keeps the batch alive in the test suite without MAD-X, PTC, python or a
fixture compile. It re-runs, on committed numbers only, every CONVENTION row
of the three consumers whose two sides both sit in a committed table: the
optics an external code printed against `analyze` applied to a matrix read
from `validation/reference/` -- either the external one-turn map put through
the stage 8 conversion law, or the Octopus map xtrack was handed. In scope:
benchmark A's A1 layer (its `assert_row` and `witness_row` calls as rows of
class `assert` and `witness`), the PTC `table_rows_present` guard, the
`S0`/`S0_pt`/`W1` `RE`-only witnesses of B0, the 5D rows of B1, the 6D rows
of B2 and the B3 index-order decision,
and benchmark C's C1 and C3 (assert and witness rows included). Out of scope,
left in the scripts: every twin (any compile), the `nst` ladders, the A3
analytic anchors, the MAD-X-internal table-vs-map pins, C2, and every recorded
row. Tables are read at their newest version by numeric fields (the
`PTCConsistencyContract` rule). Tolerances are the scripts' classes times
`tolerance_scale`; `metrics` carries `rows`, `rows_<code>`, `failed`,
`failed_<code>`, `worst_ratio`, `worst_row`, `worst_<class>` and
`table_<code>`, with `residual = worst_ratio`.

The conversion law lives twice on purpose -- in `src` and as `convert_map` in
the validation module, which `src` cannot include -- and the two copies are
checked equal by review. Two rules stop a wrong-reason pass: a code
contributing ZERO rows FAILS the contract (a silent pass is not a pass), and a
MISSING table yields `ContractResult(:skipped, ...)` naming the generator that
writes it.

## 12 Not verified and carried

Not verified:

- One version of each tool: MAD-X 5.03.06 only (a later MAD-X printing
  different `22.16e` digits makes the regenerate diff report cells, not a
  physics change), xtrack 0.112.0 in one pinned environment, PTC only at
  `time=false`.
- PTC's internal proton mass is INFERRED from the effective beam that makes
  the W1 witness close to round-off; no PTC source line was read.
- Recorded, not gated: the `Rd_1e-6` fixture in A and C (`analyze` returns
  `:failed`); B's 6D `DISP` rows (`DISP$(p)_fixed_z_dx_ddelta_vs_physical.graph[$(p),2]`
  on B4, B4K, G6_2.0MV, G6_0.2MV). A's U2 finite-difference witness is gated
  only at the coarse `TOL_FD = 1e-8`.
- Twenty of benchmark C's 623 gated rows assert a structural zero on both
  sides and cannot fail; they are named as such in the log.
- Benchmark C's TOL-E band is marginal on the dispersive cells (fitted orders
  `3.7026980631203243` on U2 and `3.7049247094295761` on K2, the U2 diff at 99
  percent of the 0.3 bound); the cause -- xtrack's finite-difference twiss vs
  the exported map's fourth-order ladder -- is an owner item.

Carried forward:

- The `nst=32` residuals sit above the 1e-9 model tolerance
  (`1.2613734057254078e-08` on U2 in benchmark A), so only `nst=64` is capped;
  a finer ladder or a tighter MAD-X integrator flag would make the whole
  ladder gateable. Benchmark B's cap is frozen from the G6 residual and would
  fall if the generator ran a higher `nst`.
- Tighten the FD dispersion witness's class `TOL_FD = 1e-8` once a
  `deltap`-independent extraction (a Richardson pair at `deltap` 1e-4 and
  5e-5) is frozen.
- Gate benchmark B's 6D `DISP` rows once the twin dispersion at PTC's effective
  beam is derived; a `ptc_twiss time=true` row would pin the `(T, PT)` partner
  directly.
- Widen or re-derive benchmark C's C2 TOL-E band for the dispersive cells, or
  fit the order on `nst` in `(16, 32, 64)` only; review the C1 dispersion
  rows' TOL-A choice; gate the sidecar's generator sha256 against the
  committed generator (today only the maps digest is gated).
