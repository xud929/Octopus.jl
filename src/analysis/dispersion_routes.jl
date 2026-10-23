# The 6D dispersion routes of the coupled Twiss analysis: theory
# docs/theory/twiss_dispersion.md Section 8 (8.1 canonical definitions D1-D4,
# 8.2 the physical graph D5-D8, 8.3 the eigenplane route D9-D12, 8.4 the
# invariance equation D14 and the Sylvester approximation D15-D16, 8.5 the
# exact algebraic route D17-D19 and the projector route D26-D27, 8.6 the
# fixed-point D20 and Newton D21-D22 iterations, 8.7 the coasting structure
# D23-D25) and Section 10.4 / 9.3 (K12) for the mode labels; design
# docs/design/twiss_dispersion_analysis.md "Pipeline" steps 3, 8, 9 and the
# return table. Stage 4a of the campaign (design "Staging", item 4, first
# half). Pure matrix arithmetic on a real 6x6 matrix the caller has ALREADY
# scaled (design "Input boundary" item 5); the stage 1 `_unscale_*` table
# transforms the graph, zeta, eta back (h is invariant). This file defines no
# `analyze`, no analysis type and no export; the public verb is `analyze` of
# twiss_dispersion_analysis.jl (stage 4b).
#
# Conventions (theory 8.1-8.2): coordinates (x, px, y, py, z, pz), r = 1:4,
# l = 5:6 (z = 5, pz = 6); M = M_zeta M_eta (D3) with h = 1 - zeta' S_4 eta;
# the physical graph D = [zeta, eta / h] (D7) and its inverse (D8)
# zeta = D[:, 1], h = 1 / (1 + D[:, 1]' S_4 D[:, 2]), eta = h D[:, 2]; the
# invariance equation M_rr D + M_rl = D (M_lr D + M_ll) (D14) with the raw
# residual F(D) = M_rr D + M_rl - D (M_lr D + M_ll) and the normalized (I1)
# form of stage 1's `_graph_invariance_residual`. The ASCII forms above are
# the note's own equations, cited by label ((D3) in 8.1, (D7)-(D8) in 8.2,
# (D14) in 8.4, (I1) in 11.2); the header lists the labels of 8.1-8.7.
#
# Every threshold constant below is PROVISIONAL until the stage 4a
# measurement freezes it; each docstring names the fixtures that set it.
# The orchestrator's decisions E1-E12 (stage 4a dossier) fix the order of
# operations; the file follows them.

"""
    DISPERSION_ROUTES

Every dispersion route this file can run, in the design's order (design
"Types and availability": the `dispersion_routes` option; eigenplane is
always primary). Pinned in the suite the way `DETERMINATION_REASONS` is.

  * `:eigenplane` -- the graph of the selected longitudinal eigenvector,
    `D = U_rs U_ls^-1` (D10), `h = det U_ls` (D11), the direct (D12) forms.
  * `:polynomial` -- the exact algebraic solve (D19) with the selected trace.
  * `:projector` -- the spectral projector (D26) read by (D27).
  * `:newton` -- Newton (D21)-(D22) from the Sylvester initializer (D15).
  * `:fixed_point` -- the fixed-point iteration (D20) from the same start.
"""
const DISPERSION_ROUTES = (:eigenplane, :polynomial, :projector, :newton, :fixed_point)

"""
    _GRAPH_SINGULARITY_MULTIPLIER

`c_graph` of the eigenplane route's regularity floor: the longitudinal
projection `U_ls` is regular iff its smallest singular value exceeds
`c_graph * rho_M1 * max(1, ||U_s||_2)` (design step 9: "graph regular iff
the smallest scaled singular value of U_ls exceeds the floor"); below it the
route reports `:singular_longitudinal_projection` and retains the mode.
PROVISIONAL; measured (stage 4a Part A, report_A.md): accepted extreme
`sigma_min(U_ls) / (rho_M1 max(1, ||U_s||_2)) = 3.2e14` over the 200 dense
maps; rejected extreme `0.26` on the `zeta = e_x, eta = e_px` (h = 0)
fixture. The one-tenth / ten window is `[10 * 0.26, 3.2e14 / 10] = [2.6,
3.2e13]`, and 64 sits inside it 12.7 decades below the accepted extreme
(`log10(3.2e14 / 64) = 12.70`) and 2.4 decades above the rejected one
(`log10(64 / 0.26) = 2.39`); the earlier "twelve decades either way" counted
the accepted side only (2026-10-18 audit, U22-5; fix batch 4b).
"""
const _GRAPH_SINGULARITY_MULTIPLIER = 64.0

"""
    _ISOTROPY_MULTIPLIER

`c_iso` of the canonical-area floor: a graph whose area
`1 + D[:, 1]' S_4 D[:, 2]` has modulus at or below `c_iso * rho_M1 * max(1,
||D||_2^2)` is `:graph_isotropic` (design: "a vanishing canonical area means
graph isotropic", distinct from a singular projection; the fixture
`diag(1, -1)`). PROVISIONAL; measured: accepted extreme `|area| / (rho_M1
max(1, ||D||_2^2)) = 3.2e14` over the 200 dense maps; rejected: the isotropic
graph `[e_x, -e_px]` has area exactly 0 (ratio 0).
"""
const _ISOTROPY_MULTIPLIER = 64.0

"""
    _COEFFICIENT_CONDITION_MULTIPLIER

`c_coef` of the linear-solve guards: the polynomial route's coefficient
matrix `A_s` (D19), the projector route's trace separations (D26) and the
coasting solve's `I - M_rr` (D24) are `:singular_coefficient` when the
relevant smallest singular value (or trace gap) is at or below `c_coef *
rho_M1 * max(1, ||A||_2)` (theory 8.5: near coincident traces or a singular
projection the solve is ill conditioned; (N16) `det A_s = h^2 (tau_1 -
tau_s)^2 (tau_2 - tau_s)^2`). The Sylvester operators of the Newton and
fixed-point routes (D15), (D21) are NOT tested against this floor: their
solves are guarded by LAPACK failure only (a singular operator is caught as
an exception and reported), and the resulting graph is judged by (I1);
the route's amplification factor enters that floor through `_kappa_route`
(landed 2026-09-14). PROVISIONAL; measured 2026-09-12 (stage
4a record, "Derived windows"): must-accept extreme `sigma_min / (rho_M1
max(1, ||A||_2)) = 1.546e9` (the weak-cavity map's projector trace gap;
its `A_s`, cond(A_s) = 1.1e4, also stays above the floor and is judged by
(I1)); must-reject extremes `0.376` on the `zeta = e_x, eta = e_px` (h = 0)
fixture's polynomial `A_s`, exactly 0 on `diag(R(0.73), R(1.41), R(0.73))`
(coincident selected trace: `A_s` and the trace gap) and on the (D24)
coefficient of the y-shear coasting map. Window by the one-tenth / ten
rule `[3.76, 1.55e8]`; 64 lies inside it. The LAPACK-singular (D15)
operators at ratio 0.012 are outside this guard's reach (see above).
"""
const _COEFFICIENT_CONDITION_MULTIPLIER = 64.0

"""
    _kappa_route(M, D, gamma; map_norm=norm(M)) -> Float64

The conditioning factor of the (I1) invariance floor `_ROUTE_INVARIANCE_MULTIPLIER * eps * _kappa_route(M, D, gamma)`
of a FORMED 4x2 graph `D` of the 6x6 map `M`:

    kappa_route = max(1, map_norm) * max(1, gamma) * max(1, ||D||_F^2 / N(D)),
    N(D) = max(1, ||M_rr D||_F, ||M_rl||_F, ||D (M_lr D + M_ll)||_F)

with `N` the normalizer of `_graph_invariance_residual` (its expressions are copied here so the two agree bit
for bit), `gamma` the route's roundoff amplification into its graph, i.e. its REPORTED `coefficient_condition`
(the `Determined{Float64}` method counts an unavailable condition as 1: the direct kernel call has no solve), and
`map_norm` the map's Frobenius norm (`||M||_F` by default; the identity contract's c_d14 row passes `||M_s||_F`
while `M` is the caller's matrix with the physical normalizer). Every floor in the package (the kernel
`_route_from_graph`, the diagnostics mirror, the identity contract's r_primary and c_d14 rows, the stage 4a
measurement driver and the route dump) calls this function.

Derivation (re-derived 2026-09-14, DERIVATION_KAPPA_ROUTE.md section 3; the history section of that date): to
first order every route's normalized residual obeys `normalized <= c eps max(1, ||M||_F) max(1, gamma) beta(D)`
with `beta = (1 + ||D||_F)^2 / N` for the routes whose graph error is absolute (eigenplane, projector, the
formation half of the polynomial route) and `beta = max(1, ||D||_F) ||D||_F / N` for the relative polynomial
solve; both shapes are covered by the bracket `max(1, ||D||_F^2 / N)` to within a factor 4 absorbed by `c_inv`.
Properties: `kappa_route >= max(1, ||M||_F)`, so `c_stop <= c_inv` still puts a converged iterate inside the
floor; it equals the landed form `max(1, ||M||_F) max(1, ||D||_F)^2` exactly at `N = 1`, which is the RAW
residual's kappa and the wrong one for the normalized residual (multiplier-1 ratio 174.2 on accepted rows of
the derivation's corpus, above the campaign's ">100 means the kappa is wrong" line); and it is bounded on
garbage graphs whose `M_lr D` does not vanish, because there `N = max(1, ||M_rr D||, ||M_rl||, ||D (M_lr D + M_ll)||)`
grows with `||D||_F^2` (over 160 stalled rows per arm `||D||_F` reaches 1.74e21 while the bracket reaches 42.6),
so the floor is no longer vacuous for a diverged iterate there. For `D` in `ker(M_lr)` every non-constant term
of `N` is linear in `||D||_F` and the bracket grows as `||D||_F` (on the stage 9 probe's `M_lr = 0` family
`kappa_route = 2.45 ||D||_F` and a garbage graph's normalized residual crosses its floor near `||D||_F = 3.47e12`;
with `||M_lr|| = 1e-8` the bracket saturates near 7.68e8): that end is what `_route_from_graph`'s residual cap
`_INVARIANCE_RESIDUAL_CAP` refuses (stage 9, S2b-1 and S2b-3). A 6x6 `M`, a 4x2 `D`, a
finite non-negative `gamma` and a finite non-negative `map_norm` are required (`ArgumentError` otherwise).
"""
function _kappa_route(M::AbstractMatrix{<:Real}, D::AbstractMatrix{<:Real}, gamma::Real; map_norm::Real=norm(M))
    size(M) == (6, 6) || throw(ArgumentError("_kappa_route takes a 6x6 matrix, got $(size(M))"))
    size(D) == (4, 2) || throw(ArgumentError("_kappa_route takes a 4x2 graph, got $(size(D))"))
    (isfinite(gamma) && gamma >= 0) || throw(ArgumentError("_kappa_route: gamma must be a non-negative finite number, got $(gamma)"))
    (isfinite(map_norm) && map_norm >= 0) || throw(ArgumentError("_kappa_route: map_norm must be a non-negative finite number, got $(map_norm)"))
    Mrr = M[1:4, 1:4]; Mrl = M[1:4, 5:6]; Mlr = M[5:6, 1:4]; Mll = M[5:6, 5:6]
    # the normalizer N(D) of _graph_invariance_residual, expression for expression
    A = Mrr * D
    B = D * (Mlr * D + Mll)
    N = max(1.0, norm(A), norm(Mrl), norm(B))
    return max(1.0, Float64(map_norm)) * max(1.0, Float64(gamma)) * max(1.0, norm(D)^2 / N)
end
_kappa_route(M::AbstractMatrix{<:Real}, D::AbstractMatrix{<:Real}, gamma::Determined{Float64}; map_norm::Real=norm(M)) =
    _kappa_route(M, D, is_determined(gamma) ? determined_value(gamma) : 1.0; map_norm=map_norm)

"""
    _ROUTE_INVARIANCE_MULTIPLIER

`c_inv` of a route's acceptance: a FORMED graph whose normalized (I1)
residual exceeds `c_inv * eps * kappa_route` is `:not_invariant` (its graph,
canonical area and residuals are still REPORTED beside the status so a
disagreement is visible; zeta, eta and h are unavailable with that reason),
where `kappa_route = _kappa_route(M, D, gamma) = max(1, ||M||_F) * max(1,
gamma) * max(1, ||D||_F^2 / N(D))`, `gamma` the route's reported
amplification factor and `N` the residual's own normalizer (re-derived
2026-09-14; the landed `max(1, ||M||_F) max(1, ||D||_F)^2` was the RAW
residual's kappa: measured 2026-09-12 with it, the one-tenth / ten window
was EMPTY, accepted extreme 151.9 on the weak cavity's eigenplane graph
against rejected extreme 642 on its polynomial graph, and the floor was
vacuous for large `||D||_F` since the normalized residual is at most 3 by
construction while that kappa grows with `||D||_F^2`; stage 4a record,
"Derived windows", and M1, 2026-09-13). PROVISIONAL; the window under the
derived kappa is measured in both CPU arms by
validation/twiss_dispersion_acceptance_windows.jl (2026-09-14, 260 fixtures,
1245 accepted / 23 rejected / 266 unlabelled values per arm): accepted extreme
5.34 native | 5.28 haswell, a converged fixed-point iterate of dense map 197 (an
iterate's ratio is at most `c_stop` = 16 by construction); rejected extreme 3.60
in both arms, the trial-011 crab's stalled fixed-point iterate, rejected by the
converged flag and not by this floor, so the window [53.4, 0.36] native | [52.8,
0.36] haswell is EMPTY on its rejected side, which no graph a route formed
populates any more (the floor alone rejects only the driver's two synthetic
guard graphs, the false and the zero graph, far above the edge; no fixture sits
near its rejecting edge: a coverage gap, carried), and the identity contract's
H15 formula would give `max(8, 2^ceil(log2(10 * 5.34))) = 64`. The constant
stays 256 until the owner decides from that measurement (an acceptance constant
is frozen by the window rule, not by H15). The converged flag, not this floor,
is the iterative routes' acceptance (see `_route_from_graph`). A floor at or
above `_INVARIANCE_RESIDUAL_CAP` judges nothing and is refused there.
"""
const _ROUTE_INVARIANCE_MULTIPLIER = 256.0

"""
    _INVARIANCE_RESIDUAL_CAP

The cap of the normalized (I1) residual, a DERIVED constant (not a measured
one): `_graph_invariance_residual` divides the raw residual `||M_rr D + M_rl -
D (M_lr D + M_ll)||_F` by `N = max(1, ||M_rr D||_F, ||M_rl||_F, ||D (M_lr D +
M_ll)||_F)`, and the triangle inequality bounds the quotient by 3 for EVERY
`(M, D)` (worst 2.19 over 3000 random pairs with `||D||_F` from 1e-8 to 1e8,
stage9/verify/orch_major_v1.jl). A floor `c_inv eps kappa_route` at or above
the cap accepts every graph, the garbage and the zero graph included, so
`_route_from_graph` refuses to judge with it: `:singular_coefficient`, the
graph and its residuals reported, zeta, eta, h unavailable. The amplification
that drives `kappa_route` to `3 / (256 eps) = 5.3e13` is a singular linear
solve in all but name: the projector route's `gamma = cc^2 ||P_s|| / |h|`
reaches it at `cc ~ 5e14` (a synchrotron trace 1e-7 from a betatron trace, the
condition guard admits `cc` up to `1 / (64 rho_M1) ~ 1e13`), the polynomial
route at `cc ~ 5e13` (traces 1e-13 apart). Stage 9 (S2b-1 = U5-1-1,
2026-09-16): on that fixture the floor was 70.7 and a garbage graph with
normalized residual 0.24 was `:none`; in the unfixed tree's route dump (1005
rows, 227 fixtures) exactly one row sat above the cap, the weak cavity's
projector (`cc = 5.1e14`, floor 78; its own residual 6.7e-10 and its status
`:none` were right, the certificate was not). A floor in [1, 3) still admits
the zero graph (`D = 0` has normalized residual at most 1, the first two terms
vanish): an observation for the owner beside K11, not gated here.
"""
const _INVARIANCE_RESIDUAL_CAP = 3.0

"""
    _ITERATION_STOP_MULTIPLIER

`c_stop` of the iterative routes' stopping rule: Newton and the fixed point
stop when the normalized (I1) residual is at or below `c_stop * eps *
max(1, ||M||_F)` or when a step no longer decreases it after
`_MAX_HALVINGS` halvings (theory 8.6: "Stop using the full residual in (I1)
... A small update alone is insufficient"). PROVISIONAL; measured
2026-09-12 (stage 4a record, "Derived windows"): the only labelled side is
the exact-graph floor, the roundoff level of the (I1) residual of the EXACT
graph, whose largest value is `0.579 eps max(1, ||M||_F)` ("dense k=159
(mu_s=-1.347)"; a Newton polish from the exact graph does not move it); a
stopping rule has no must-reject side by definition. Window `[5.79, open)`;
16 lies inside it, a factor 2.8 above the lower edge. UNLABELLED
observations, consequences of the rule rather than measurements of it:
converged Newton and fixed-point iterates end at `<= 15.9`, the iterate one
step short of convergence sits at `>= 16.2` ("trial-011 crab k=kc(1-0.1)",
Newton iterate 4 of 5) and up to `1.4e9`.
"""
const _ITERATION_STOP_MULTIPLIER = 16.0

"""
    _FIXED_POINT_MAX_ITERATIONS

The default cap of the fixed-point iteration (D20) in `_dispersion_routes`
(theory 8.6: linear convergence at the contraction ratio `2 ||M_lr|| ||D|| /
sigma_min(op)`). An integer stopping rule, no window. PROVISIONAL; why 500:
measured 2026-09-12 (stage 4a record, "Derived windows", integer caps) on
the 260 fixtures, the fixed point converges on 239, the slowest in 176
iterations ("trial-011 crab k=kc(1-0.01)"), so the cap is about 2.8 times
the slowest converging fixture and no converging fixture is cut short; the
former cap 50 left 8 of the 200 dense maps short of the stop floor (the
slowest dense map needs 139). The record counts an E7 stall on 23 runs and
the cap reached on 4 (the crab ladder at `eps <= 1e-3`, contraction ratio
2.05..2.14: not contracting, and the detail says so). Newton needs at most
12 iterations on the same fixtures.
"""
const _FIXED_POINT_MAX_ITERATIONS = 500

"""
    _MAX_HALVINGS

The cap on the halved trials of one Newton step (theory 8.6 gives none): a step
none of whose `_MAX_HALVINGS` halved trials decreases the normalized (I1)
residual is a STALL and ends the iteration on the last accepted graph
(`converged = false`, `:not_invariant` with the graph reported); the keyword
`max_halvings` of `_newton_route` overrides it. An integer stopping rule, no
window. PROVISIONAL; measured 2026-09-12 (stage 4a record, "Derived
windows", integer caps): from the (D15) start at most 2 halved trials occur
over a whole run ("dense k=67 (mu_s=-1.071)"; 259 of the 260 fixtures never
halve) and Newton takes at most 12 iterations ("trial-011 crab
k=kc(1-1.0e-6)"); from the far start `D0 = D_exact + 100` on the 200 dense
maps, 38 converge (up to 151 halved trials over the run, "dense k=69
(mu_s=-1.077)"; k = 3 converges with 10 halved trials in 14 steps, the a06
sensor) and 162 stall at the per-step cap (40 in the stalling step, 0..375
accumulated); a trial `2^-40` of the Newton step that still does not
decrease the residual is a stall for any purpose, so the cap is a stopping
rule, not a tolerance.
"""
const _MAX_HALVINGS = 40

"""
    _COASTING_MULTIPLIER

`c_coast` of the coasting structure test (D23): the structure residual
(digest of 8.7) must be at or below `c_coast * rho_M1 * max(1, ||M||_F)`
for the coasting branch (design step 3: a roundoff-scale tolerance with its
margin reported; a `1e-6` cavity term must NOT take the branch). PROVISIONAL;
measured: the three coasting maps and the DBA cell have structure residual
exactly 0 (accepted, margin 0); the dense maps have `residual / (rho_M1
max(1, ||M||_F)) >= 1e12` and the symplectically folded weak cavity
(`M[6, 5] = -1e-6`) `2.2e8` (rejected; margin 3.4e6 at the multiplier 64).
"""
const _COASTING_MULTIPLIER = 64.0

"""
    _LABEL_TIE_MULTIPLIER

`c_tie` of the label-tie declaration: two signed areas competing for a label
are a TIE when their difference is at or below `c_tie * eps * kappa_frame`
(design step 8: "Ties are declared with their own tolerance and leave the
modes unlabelled"). PROVISIONAL; measured on the det R = 1 construction and
the 45-degree roll of stage 2 (ties) against the manufactured maps (clear):
measured accepted extreme `margin / (eps kappa_frame) = 1.8e15` over the
200 dense maps (clear); the 45-degree rolls have margin exactly 0 (tie).
"""
const _LABEL_TIE_MULTIPLIER = 64.0

# ---------------------------------------------------------------------------
# Result structs (runtime representation; the analysis object of stage 4b is
# the stable surface).

"The payload of a route's `invariance_residual`: the (I1) graph residual `normalized` and `raw` (a file-local type alias, not a vocabulary)."
const _ROUTE_RESIDUAL_T = NamedTuple{(:normalized, :raw), Tuple{Float64, Float64}}
"One entry of `DispersionRoutes.agreement`: the two routes `first`, `second` and the infinity-norm differences `zeta`, `eta`, `h` (a file-local type alias)."
const _AGREEMENT_T = NamedTuple{(:first, :second, :zeta, :eta, :h), Tuple{Symbol, Symbol, Float64, Float64, Float64}}

"""
    ModeLabels6D

The physical labels of three resolved 6D modes (theory (K12), 10.4; design
step 8): `signed_areas` (3x3, `[j, a] = -Im(conj(u_ja) u_j,pa)` for mode `j`
in the order of the vectors given and plane `a`, `1 = x`, `2 = y`, `3 = z`);
the `row_sums` (one per mode, (K12)) and `column_sums` (one per plane); the
`longitudinal` mode index (largest signed z-area, or the explicit index the
caller passed, `rule` says which: `:max_signed_z_area` or `:explicit`); the
`transverse` pair `(mode 1, mode 2)` by stage 2's rule on the x column (mode 1
has the larger x-area); `longitudinal_margin` (the winning z-area minus the
runner-up) and `transverse_margin` (the x-area difference); `tie` when the
transverse margin, or under `:max_signed_z_area` the longitudinal margin, is at or
below `tie_tolerance`; an explicit selection has no z-area tie, stage 9 U5-1-2 (design: ties are
declared and leave the modes unlabelled; a tie keeps the given order and is flagged).

The default rule is a HEURISTIC, not a certification (theory 10.4, 13.5:
"a small tune is not a universal longitudinal-mode identifier", and no
endpoint-map rule is): by (K12) `kappa_sz = h`, the synchrotron mode's z-area
IS `h` and the two betatron z-areas sum to `1 - h`, so a betatron mode can
carry the larger z-area and be selected, and must for `h < 1/3` (the
prescribed-h fixtures with `h = 0.05` and every negative `h`; the `h = 1/2`
fixture, z-areas (1/2, 1/2, 0), is the declared tie; a negative betatron
z-area lets it happen at larger `h`). Labelling never feeds
a Twiss value; the caller's explicit index certifies the selection.
"""
struct ModeLabels6D
    signed_areas::Matrix{Float64}
    row_sums::Vector{Float64}
    column_sums::Vector{Float64}
    longitudinal::Int
    transverse::NTuple{2,Int}
    longitudinal_margin::Float64
    transverse_margin::Float64
    tie::Bool
    tie_tolerance::Float64
    rule::Symbol
end

"""
    CoastingStructure

The coasting test of theory 8.7 (D23)-(D25) and design step 3: `holds`
(the structure `residuals` `z_column = ||M[1:4, 5]||`, `pz_row = ||M[6, 1:5]||`,
`m55 = |M[5, 5] - 1|`, `m66 = |M[6, 6] - 1|` all at or below `tolerance`);
`margin` is their maximum over the tolerance, reported either way (the
documented sentinel `Inf` when the caller's `rho_M1 = 0` makes the tolerance
0 and a residual is non-zero: the ratio of a non-zero residual to a zero
tolerance; through `_dispersion_routes` the clusters' `rho_M1` is positive
and the ratio finite); `symplectic_consistency = ||M[5, 1:4] - M[1:4, 6]' S_4
M_rr||` (symplecticity forces `M_zr = M_rpz' S_4 M_rr`, a sanity residual).
When it holds: `zeta = 0`, `h = 1`, `eta` from `(I_4 - M_rr) eta = M[1:4, 6]`
(D24) as a `Determined` (`:singular_coefficient` when the coefficient's
smallest singular value is at or below the D24 floor), `coefficient_condition`
(the 2-norm condition of `I_4 - M_rr`, unique when its smallest singular value
is positive, unavailable with `:singular_coefficient` when it is exactly zero:
no `Inf` stands in for it), `solve_residual`, the shear `Mbar_s = [1, M[5, 6] +
M[5, 1:4]' eta; 0, 1]` (D25) in `longitudinal_map` with its `shear` entry,
`transverse_map` `= M_rr` (symplectic by (K8) because `M_lr = [M_zr; 0]`) with
`transverse_symplecticity`. Every field is present when the structure does
not hold OR the (D24) coefficient is singular: the residuals, tolerance,
margin, `symplectic_consistency`, `transverse_map = M_rr` and its symplecticity
are computed either way; `longitudinal_map` is `zeros(2, 2)` and `shear` is
`0.0` in both cases ((D25) needs `eta`: `M[5, 6]` alone is not the shear), and
`eta`, `solve_residual` (with `coefficient_condition` when the structure is
absent) are unavailable `Determined`s with the reason `:not_derived_for_cluster`
and the detail "coasting structure absent", or `:singular_coefficient` with
the (D24) detail. The caller reads `holds` first, then `eta`.
"""
struct CoastingStructure
    holds::Bool
    residuals::NamedTuple{(:z_column, :pz_row, :m55, :m66), NTuple{4,Float64}}
    tolerance::Float64
    margin::Float64
    symplectic_consistency::Float64
    eta::Determined{Vector{Float64}}
    coefficient_condition::Determined{Float64}
    solve_residual::Determined{Float64}
    longitudinal_map::Matrix{Float64}
    shear::Float64
    transverse_map::Matrix{Float64}
    transverse_symplecticity::Float64
end

"""
    DispersionRoute

One route's result (design "Types and availability": "dispersion routes
(graph, zeta, eta, h, the normalized and the raw invariance residual, trace
residual, coefficient condition, iteration count, canonical area)"). Fields:
`route` in [`DISPERSION_ROUTES`](@ref); `status` (`:none` when the graph is
unique and invariant, else the `DETERMINATION_REASONS` member:
`:singular_longitudinal_projection`, `:singular_coefficient`,
`:graph_isotropic`, `:not_invariant`, `:cluster_unresolved`,
`:unstable_spectrum`, `:coasting_structure`, `:route_not_selected`) and `detail`; `graph` (4x2, (D7)), `zeta`, `eta`
(4-vectors), `h`, `canonical_area` (`1 + D[:, 1]' S_4 D[:, 2]`), each a
`Determined`; `invariance_residual` (the (I1) graph form, normalized and
raw, available whenever a graph was formed, invariant or not);
`trace_residual` (`tr(M_lr D + M_ll) - tau_s`); `coefficient_condition` (the
route's roundoff amplification into its graph, the `gamma` of the (I1)
floor's `_kappa_route`: the 2-norm condition of the linear solve for the
eigenplane (`U_ls`), Newton and fixed-point routes (the Sylvester operator),
`||M||_F^2 / sigma_min(A_s)` for the polynomial route and `max(1, cc)^2
max(1, ||P_s||_2 / |h|)` for a formed projector graph, `cc` the
trace-separation condition that the projector's `:singular_*` returns report
on their own (re-derived 2026-09-14); unavailable for a route with none, and
unavailable with `:singular_coefficient` when the smallest singular value or
trace gap is exactly zero: no `Inf` stands in for an infinite condition);
`h_alternative` (a second evaluation of `h` where the theory gives one:
(D12) against `det U_ls`, `tr((P_s)_ll) / 2` against (D8)); `singular_values`
(of `U_ls` or `A_s`; empty otherwise); `iterations`, `halvings`, `converged`
(iterative routes; zeros and `true` for direct ones).
"""
struct DispersionRoute
    route::Symbol
    status::Symbol
    detail::String
    graph::Determined{Matrix{Float64}}
    zeta::Determined{Vector{Float64}}
    eta::Determined{Vector{Float64}}
    h::Determined{Float64}
    canonical_area::Determined{Float64}
    invariance_residual::Determined{_ROUTE_RESIDUAL_T}
    trace_residual::Determined{Float64}
    coefficient_condition::Determined{Float64}
    h_alternative::Determined{Float64}
    singular_values::Vector{Float64}
    iterations::Int
    halvings::Int
    converged::Bool
end

"""
    DispersionRoutes

What [`_dispersion_routes`](@ref) returns (design return table, rows 1, 2,
6; dossier E1-E10). Fields: `matrix` (the scaled 6x6 map, a copy);
`labels` (a `Determined{ModeLabels6D}`, unique when three resolved modes
exist, its `detail` naming the default rule a heuristic (see
[`ModeLabels6D`](@ref)); unavailable with the blocking cluster's reason
otherwise); `longitudinal`
(the canonical eigenvalue index of the selected longitudinal pair's member
with positive imaginary part, the cluster half's member, whichever member of
the pair was named; 0 when none was selected) and `longitudinal_cluster` (its cluster's
position in `clusters.clusters`); `tau_s`, the selected longitudinal
CANDIDATE's trace: `2 cos mu_s` of the selected mode on the normal path (a
resolved elliptic mode), the common trace `Re(rho + 1 / rho)` of a definite
unresolved candidate's first eigenvalue ([`_cluster_trace`](@ref), the value
the polynomial and projector routes are formed with), and for a candidate
that blocks every route (indefinite, defective, unit-eigenvalue or unstable:
`labels`, `graph`, `zeta`, `eta`, `h` all unavailable with its reason) the
same first-eigenvalue trace `Re(rho + 1 / rho)`, which is `rho + 1 / rho`
for a real hyperbolic pair (2.5 on the suite's E9 fixture, the synchrotron
pair `diag(2, 1/2)` conjugated by a random symplectic `W`; 2 on its
unit-eigenvalue shear pair) and the shared real part of a Krein quartet's
`rho + 1 / rho` -- a diagnostic reported beside the blocking reason, not
the trace `2 cos mu_s` of a mode (no mode exists there; 2026-10-18 audit,
U22-8); unavailable with `:coasting_structure` on a coasting map; `tunes` (the
three oriented tunes in label order when labelled); `trace_cubic_roots` (the
three roots of (D17) from the trace identities) and `trace_cubic_residual`
(their largest distance to a mode trace `2 cos mu_j`: one per recovered mode
of a resolved cluster, the first eigenvalue's for an unresolved or real-class
one; a diagnostic of the cubic against the eigenvalues; a `ModeClusters`
report without a single trace is an ArgumentError, never an `Inf`); `routes` in the requested order, one [`DispersionRoute`](@ref)
each (a route absent from the request is present with `:route_not_selected`
so the vector always has five entries in the [`DISPERSION_ROUTES`](@ref)
order); `primary` (`:eigenplane`); `zeta`, `eta`, `h`, `graph` (the PRIMARY
results: unique from the eigenplane route, `eta` an ambiguity set with
`:cluster_unresolved` for a definite unresolved longitudinal cluster (theory
13.6, stage 3's `_dispersion_ambiguity_set`), unavailable otherwise);
`agreement` (every pair of routes with unique graphs: the infinity-norm
differences of zeta, eta and h; empty when fewer than two routes are unique);
`coasting` (the [`CoastingStructure`](@ref); the test is always run and
reported; when it holds the routes are NOT run, every route carries
`:coasting_structure`, and the coasting branch supplies the report's
`zeta = 0`, `h = 1`, `eta` from (D24) and the (D7) graph `[0, eta]` when
`eta` is unique; `graph` is unavailable with `eta`'s reason otherwise);
`executed` (the routes whose kernel function RAN, in `DISPERSION_ROUTES`
order: none on a coasting map or when the longitudinal candidate is not a
definite cluster, the polynomial and projector routes alone for a definite
unresolved candidate, every requested route on the normal path; a route that
was requested but blocked before running is in `routes` with the blocking
reason and NOT here. The analysis derives its receipt's `executed`, its
diagnostics rows and the Newton cap's activity from this field, so the three
cannot disagree; fix batch 3, 2026-10-21, F-196 and F-198).
"""
struct DispersionRoutes
    matrix::Matrix{Float64}
    labels::Determined{ModeLabels6D}
    longitudinal::Int
    longitudinal_cluster::Int
    tau_s::Determined{Float64}
    tunes::Vector{Float64}
    trace_cubic_roots::Vector{ComplexF64}
    trace_cubic_residual::Float64
    routes::Vector{DispersionRoute}
    primary::Symbol
    graph::Determined{Matrix{Float64}}
    zeta::Determined{Vector{Float64}}
    eta::Determined{Vector{Float64}}
    h::Determined{Float64}
    agreement::Vector{_AGREEMENT_T}
    coasting::CoastingStructure
    executed::Vector{Symbol}
end

# ---------------------------------------------------------------------------
# Conversions and residuals (theory 8.2, 8.4), implemented.

"""
    _graph_to_dispersion(D) -> (zeta, eta, h, area)

(D8) for a 4x2 graph: `zeta = D[:, 1]`, `area = 1 + D[:, 1]' S_4 D[:, 2]`,
`h = 1 / area`, `eta = h D[:, 2]`. The caller decides what a vanishing `area`
means (`:graph_isotropic`); this kernel returns `h = Inf` only through the
caller's guard, never silently: an exactly zero area is an `ArgumentError`.
"""
function _graph_to_dispersion(D::AbstractMatrix{<:Real})
    size(D) == (4, 2) || throw(ArgumentError("_graph_to_dispersion takes a 4x2 graph, got $(size(D))"))
    S4 = _symplectic_form(4)
    zeta = Vector{Float64}(D[:, 1])
    area = 1 + dot(zeta, S4 * D[:, 2])
    area == 0 && throw(ArgumentError("_graph_to_dispersion: the canonical area 1 + D1' S_4 D2 vanishes; the graph is isotropic"))
    h = 1 / area
    return (zeta=zeta, eta=h * Vector{Float64}(D[:, 2]), h=h, area=area)
end

"""
    _dispersion_to_graph(zeta, eta, h) -> Matrix{Float64}

(D7): `D = [zeta, eta / h]`, 4x2; `h == 0` is an `ArgumentError` (the plane
has no graph over the physical longitudinal coordinates, theory 8.3).
"""
function _dispersion_to_graph(zeta::AbstractVector{<:Real}, eta::AbstractVector{<:Real}, h::Real)
    (length(zeta) == 4 && length(eta) == 4) || throw(ArgumentError("_dispersion_to_graph takes two 4-vectors"))
    (isfinite(h) && h != 0) || throw(ArgumentError("_dispersion_to_graph: h = $(h); the longitudinal projection is singular"))
    return hcat(Vector{Float64}(zeta), Vector{Float64}(eta) ./ h)
end

"""
    _route_residuals(M, D, tau_s) -> (invariance, trace_residual, area)

For a 6x6 map and a 4x2 graph: the (I1) graph residual of stage 1's
`_graph_invariance_residual` (normalized and raw), the trace residual
`tr(M_lr D + M_ll) - tau_s` (theory 8.5, unlabelled), and the canonical area
`1 + D[:, 1]' S_4 D[:, 2]`.
"""
function _route_residuals(M::AbstractMatrix{<:Real}, D::AbstractMatrix{<:Real}, tau_s::Real)
    Mlr = M[5:6, 1:4]; Mll = M[5:6, 5:6]
    inv_res = _graph_invariance_residual(M, D)
    trace_res = tr(Mlr * D + Mll) - tau_s
    area = 1 + dot(D[:, 1], _symplectic_form(4) * D[:, 2])
    return (invariance=inv_res, trace_residual=trace_res, area=area)
end

"""
    _trace_cubic_roots(M) -> Vector{ComplexF64}

The three roots of the trace cubic (D17) from `t1 = tr M`, `t2 = tr M^2`,
`t3 = tr M^3`: `tau^3 - t1 tau^2 + ((t1^2 - t2)/2 - 3) tau - (t1^3 - 3 t1 t2
+ 2 t3)/6 + 2 t1 = 0`, by the eigenvalues of the companion matrix. In the
stable nondegenerate domain they are `2 cos mu_j`, real in (-2, 2); the
caller compares them with the modes' tunes (a diagnostic only: the cubic
cannot tell `mu` from `-mu` and is ill conditioned near coincident traces).
"""
function _trace_cubic_roots(M::AbstractMatrix{<:Real})
    size(M) == (6, 6) || throw(ArgumentError("_trace_cubic_roots takes a 6x6 matrix, got $(size(M))"))
    Mf = Matrix{Float64}(M)
    t1 = tr(Mf); M2 = Mf * Mf; t2 = tr(M2); t3 = tr(M2 * Mf)
    c2 = -t1
    c1 = (t1^2 - t2) / 2 - 3
    c0 = -(t1^3 - 3 * t1 * t2 + 2 * t3) / 6 + 2 * t1
    companion = [0.0 0.0 -c0; 1.0 0.0 -c1; 0.0 1.0 -c2]
    return Vector{ComplexF64}(eigvals(companion))
end

"""
    _sylvester_initializer(M) -> (D0, condition)

(D15) `M_rr D - D M_ll = -M_rl`, i.e. `sylvester(M_rr, -M_ll, M_rl)` (Julia's
`sylvester(A, B, C)` solves `A X + X B + C = 0`, pitfall 1), and the 2-norm
condition of the (D16) operator `I_2 kron M_rr - M_ll' kron I_4` (8x8),
whose smallest singular value also enters the fixed-point contraction
condition of 8.6. The condition is a `Determined` (unavailable with
`:singular_coefficient` when it is not a finite Float64, stage 9 U5-1-3). An `ArgumentError` names the singular operator (spectra of
`M_rr` and `M_ll` not disjoint) when LAPACK refuses the solve.
"""
function _sylvester_initializer(M::AbstractMatrix{<:Real})
    size(M) == (6, 6) || throw(ArgumentError("_sylvester_initializer takes a 6x6 matrix, got $(size(M))"))
    Mrr = Matrix{Float64}(M[1:4, 1:4]); Mrl = Matrix{Float64}(M[1:4, 5:6]); Mll = Matrix{Float64}(M[5:6, 5:6])
    op = kron(Matrix{Float64}(I, 2, 2), Mrr) - kron(transpose(Mll), Matrix{Float64}(I, 4, 4))
    D0 = try
        sylvester(Mrr, -Mll, Mrl)
    catch err
        err isa LinearAlgebra.LAPACKException || rethrow()
        throw(ArgumentError("_sylvester_initializer: the (D15) operator is singular (the spectra of M_rr and M_ll share " *
            "an eigenvalue; LAPACK $(err.info)); no weak-coupling initializer exists"))
    end
    return (D0=Matrix{Float64}(D0), condition=_operator_condition(op, "the (D16) Sylvester operator"))
end

"""
    _route_agreement(routes) -> Vector{_AGREEMENT_T}

For every pair of routes whose `zeta`, `eta` and `h` are all unique: the
infinity-norm differences `(zeta, eta, h)` (design step 9: "a route-agreement
matrix"). Empty when fewer than two routes are unique.
"""
function _route_agreement(routes::AbstractVector{DispersionRoute})
    out = _AGREEMENT_T[]
    ok = [r for r in routes if is_determined(r.zeta) && is_determined(r.eta) && is_determined(r.h)]
    for i in eachindex(ok), j in (i + 1):length(ok)
        a, b = ok[i], ok[j]
        push!(out, (first=a.route, second=b.route,
                    zeta=norm(determined_value(a.zeta) - determined_value(b.zeta), Inf),
                    eta=norm(determined_value(a.eta) - determined_value(b.eta), Inf),
                    h=abs(determined_value(a.h) - determined_value(b.h))))
    end
    return out
end

# ---------------------------------------------------------------------------
# Labels, the coasting test, the five routes, the entry point (dossier E2-E10).

"""
    _mode_labels_6d(vectors, tunes; longitudinal=nothing, kappa_frame=1.0, tie_multiplier=_LABEL_TIE_MULTIPLIER) -> ModeLabels6D

Dossier E3. `vectors` are the three (E3)-normalized oriented 6-vectors of the
resolved modes (any order), `tunes` their tunes. The 3x3 signed-area array
`kappa[j, a] = -Im(conj(u_ja) u_j,pa)` (K12) over planes x, y, z; row and
column sums reported; the longitudinal mode is the row with the largest
z-area unless `longitudinal` (an index into `vectors`) is given (`rule`
`:max_signed_z_area` or `:explicit`); the two transverse modes are ordered
by stage 2's `_mode_label_order` on their x-areas (mode 1 = larger x-area).
`tie` is set when the transverse margin, or under `:max_signed_z_area` the
longitudinal margin, is at or below `tie_multiplier * eps * kappa_frame`; a
tie keeps the given order. An explicit selection is never a longitudinal tie:
its z-area margin may be negative (a certified mode with less z-area than a
betatron mode, (K12)) and does not decide the transverse order.
"""
function _mode_labels_6d(vectors::AbstractVector{<:AbstractVector{<:Complex}}, tunes::AbstractVector{<:Real};
                         longitudinal=nothing, kappa_frame::Real=1.0, tie_multiplier::Real=_LABEL_TIE_MULTIPLIER)
    length(vectors) == 3 || throw(ArgumentError("_mode_labels_6d takes exactly three mode vectors, got $(length(vectors))"))
    length(tunes) == 3 || throw(ArgumentError("_mode_labels_6d takes three tunes, got $(length(tunes))"))
    all(length(u) == 6 for u in vectors) || throw(ArgumentError("_mode_labels_6d: every mode vector must have length 6"))
    (isfinite(kappa_frame) && kappa_frame > 0) || throw(ArgumentError("_mode_labels_6d: kappa_frame must be a positive finite number, got $(kappa_frame)"))
    (isfinite(tie_multiplier) && tie_multiplier >= 0) || throw(ArgumentError("_mode_labels_6d: tie_multiplier must be a non-negative finite number, got $(tie_multiplier)"))
    # (K12): kappa[j, a] = -Im(conj(u_ja) u_j,pa), planes x (1:2), y (3:4), z (5:6). Signed, never |.| (pitfall 8).
    kappa = Matrix{Float64}(undef, 3, 3)
    for j in 1:3, a in 1:3
        u = vectors[j]
        kappa[j, a] = -imag(conj(u[2a - 1]) * u[2a])
    end
    row_sums = vec(sum(kappa; dims=2))
    column_sums = vec(sum(kappa; dims=1))
    # One assignment of `s` (the comprehensions below capture it; a variable assigned in two branches and
    # captured would be a Core.Box, the suite's tripwire).
    s, long_margin, rule = if longitudinal === nothing
        zs = kappa[:, 3]
        order = sortperm(zs; rev=true)
        (order[1], zs[order[1]] - zs[order[2]], :max_signed_z_area)
    else
        si = Int(longitudinal)
        1 <= si <= 3 || throw(ArgumentError("_mode_labels_6d: longitudinal index $(si) outside 1:3"))
        (si, kappa[si, 3] - maximum(kappa[j, 3] for j in 1:3 if j != si), :explicit)
    end
    rest = [j for j in 1:3 if j != s]
    first_pos, second_pos, trans_margin = _mode_label_order(kappa[rest[1], 1], kappa[rest[2], 1])
    transverse = (rest[first_pos], rest[second_pos])
    tie_tolerance = tie_multiplier * eps(Float64) * kappa_frame
    # the longitudinal margin is judged under the z-area rule only: an explicit selection with a negative z-area
    # margin is not a tie and keeps the x-area order of its transverse modes (stage 9, U5-1-2)
    tie = (rule === :max_signed_z_area && long_margin <= tie_tolerance) || trans_margin <= tie_tolerance
    if tie
        transverse = (rest[1], rest[2])   # a tie keeps the given order
    end
    return ModeLabels6D(kappa, row_sums, column_sums, s, transverse, long_margin, trans_margin, tie, tie_tolerance, rule)
end

"""
    _coasting_structure(M; rho_M1, multiplier=_COASTING_MULTIPLIER, coefficient_multiplier=_COEFFICIENT_CONDITION_MULTIPLIER) -> CoastingStructure

Dossier E2, theory 8.7 (D23)-(D25): the four structure residuals against
`tolerance = multiplier * rho_M1 * max(1, ||M||_F)`; when they hold, `eta`
from `(I_4 - M_rr) eta = M[1:4, 6]` with the coefficient's smallest singular
value against `coefficient_multiplier * rho_M1 * max(1, ||I - M_rr||_2)`
(`:singular_coefficient` below it: `eta`, `solve_residual` unavailable,
`longitudinal_map = zeros(2, 2)`, `shear = 0.0` because (D25) needs `eta`),
the shear (D25), `M_rr`'s symplecticity (K8). Every field is filled whether
or not the structure holds; `coefficient_condition` is unavailable with
`:singular_coefficient` when `sigma_min(I - M_rr)` is exactly zero.
"""
function _coasting_structure(M::AbstractMatrix{<:Real}; rho_M1::Real, multiplier::Real=_COASTING_MULTIPLIER,
                             coefficient_multiplier::Real=_COEFFICIENT_CONDITION_MULTIPLIER)
    size(M) == (6, 6) || throw(ArgumentError("_coasting_structure takes a 6x6 matrix, got $(size(M))"))
    all(isfinite, M) || throw(ArgumentError("_coasting_structure: the matrix has non-finite entries"))
    (isfinite(rho_M1) && rho_M1 >= 0) || throw(ArgumentError("_coasting_structure: rho_M1 must be a non-negative finite number, got $(rho_M1)"))
    (isfinite(multiplier) && multiplier > 0) || throw(ArgumentError("_coasting_structure: multiplier must be positive, got $(multiplier)"))
    (isfinite(coefficient_multiplier) && coefficient_multiplier > 0) || throw(ArgumentError("_coasting_structure: coefficient_multiplier must be positive, got $(coefficient_multiplier)"))
    Mf = Matrix{Float64}(M)
    Mrr = Mf[1:4, 1:4]
    S4 = _symplectic_form(4)
    # (D23) structure residuals: the z column of the transverse rows, the pz row, the two unit diagonal entries.
    residuals = (z_column=norm(Mf[1:4, 5]), pz_row=norm(Mf[6, 1:5]), m55=abs(Mf[5, 5] - 1), m66=abs(Mf[6, 6] - 1))
    tolerance = multiplier * rho_M1 * max(1.0, norm(Mf))
    worst = max(residuals...)
    margin = tolerance > 0 ? worst / tolerance : (worst == 0 ? 0.0 : Inf)
    holds = worst <= tolerance
    # Symplecticity forces M_zr = M_rpz' S_4 M_rr (reader's inference in the dossier).
    symplectic_consistency = norm(Mf[5, 1:4] - transpose(transpose(Mf[1:4, 6]) * S4 * Mrr))
    transverse_symplecticity = _symplectic_defect(Mrr).frobenius
    if !holds
        d = "coasting structure absent"
        return CoastingStructure(false, residuals, tolerance, margin, symplectic_consistency,
                                 Determined{Vector{Float64}}(:not_derived_for_cluster, d),
                                 Determined{Float64}(:not_derived_for_cluster, d),
                                 Determined{Float64}(:not_derived_for_cluster, d),
                                 zeros(2, 2), 0.0, Mrr, transverse_symplecticity)
    end
    # (D24): (I_4 - M_rr) eta = M[1:4, 6]; the coefficient's smallest singular value against the c_coef floor.
    A = Matrix{Float64}(I, 4, 4) - Mrr
    sv = svdvals(A)
    floor = coefficient_multiplier * rho_M1 * max(1.0, sv[1])
    condition = _condition_number(sv[1], sv[end], "(D24) coefficient I - M_rr")
    if sv[end] <= floor
        d = "(D24) coefficient I - M_rr has sigma_min = $(sv[end]) at or below the floor $(floor) (unit eigenvalue of M_rr); (D25) needs eta, so no shear is reported"
        return CoastingStructure(true, residuals, tolerance, margin, symplectic_consistency,
                                 Determined{Vector{Float64}}(:singular_coefficient, d), condition,
                                 Determined{Float64}(:singular_coefficient, d),
                                 zeros(2, 2), 0.0, Mrr, transverse_symplecticity)
    end
    eta = A \ Mf[1:4, 6]
    solve_residual = norm(A * eta - Mf[1:4, 6]) / max(1.0, norm(Mf[1:4, 6]), norm(A * eta))
    # (D25): the shear of the barred longitudinal map, M[5, 6] + M[5, 1:4] eta.
    shear = Mf[5, 6] + dot(Mf[5, 1:4], eta)
    longitudinal_map = [1.0 shear; 0.0 1.0]
    return CoastingStructure(true, residuals, tolerance, margin, symplectic_consistency, Determined(eta), condition,
                             Determined(solve_residual), longitudinal_map, shear, Mrr, transverse_symplecticity)
end

"""
    _condition_number(sigma_max, sigma_min, what) -> Determined{Float64}

The 2-norm condition `sigma_max / sigma_min` of a linear solve or trace separation as a `Determined`:
unique when `sigma_min > 0`, unavailable with `:singular_coefficient` (detail naming `what`) when it is
exactly zero (the mathematical condition is infinite; the dossier forbids an `Inf` standing in for it). A
quotient that overflows Float64 is unavailable the same way (stage 9, U5-1-3).
"""
function _condition_number(sigma_max::Real, sigma_min::Real, what::AbstractString)
    if sigma_min > 0
        q = Float64(sigma_max) / Float64(sigma_min)
        isfinite(q) && return Determined(q)
        return Determined{Float64}(:singular_coefficient,
            "$(what) has a condition number beyond the largest Float64 (smallest singular value (or gap) $(sigma_min) against $(sigma_max)): singular to working precision")
    end
    return Determined{Float64}(:singular_coefficient, "$(what) has smallest singular value (or gap) exactly 0: the condition number is infinite")
end

"""
    _operator_condition(op, what) -> Determined{Float64}

The 2-norm condition of a matrix operator through [`_condition_number`](@ref): `cond(op)` returns `Inf` for a
singular operator, which the dossier forbids as a value, so the quotient of the extreme singular values is formed
under the same rule as every other condition of the analysis (stage 9, U5-1-3).
"""
function _operator_condition(op::AbstractMatrix, what::AbstractString)
    sv = svdvals(Matrix{Float64}(op))
    return _condition_number(sv[1], sv[end], what)
end

"The condition as text for a route detail: the value, or `infinite` when it is unavailable."
_condition_text(c::Determined{Float64}) = is_determined(c) ? string(determined_value(c)) : "infinite"

# Shared assembly of a route result (dossier E4, E8): the isotropy floor, (D8), the residuals and the status.

"""
    _unavailable_route(route, reason, detail; coefficient_condition, singular_values, iterations, halvings, converged) -> DispersionRoute

A route that formed no graph: every `Determined` field unavailable with `reason` and `detail`
(dossier E8: only the diagnostics stay), `route` in `DISPERSION_ROUTES`.
"""
function _unavailable_route(route::Symbol, reason::Symbol, detail::AbstractString;
                            coefficient_condition::Determined{Float64}=Determined{Float64}(reason, detail),
                            singular_values::Vector{Float64}=Float64[], iterations::Integer=0, halvings::Integer=0,
                            converged::Bool=true)
    route in DISPERSION_ROUTES || throw(ArgumentError("_unavailable_route: unknown route :$(route); DISPERSION_ROUTES = $(DISPERSION_ROUTES)"))
    return DispersionRoute(route, reason, String(detail),
                           Determined{Matrix{Float64}}(reason, detail), Determined{Vector{Float64}}(reason, detail),
                           Determined{Vector{Float64}}(reason, detail), Determined{Float64}(reason, detail),
                           Determined{Float64}(reason, detail), Determined{_ROUTE_RESIDUAL_T}(reason, detail),
                           Determined{Float64}(reason, detail), coefficient_condition, Determined{Float64}(reason, detail),
                           singular_values, Int(iterations), Int(halvings), converged)
end

"""
    _route_from_graph(route, M, D, tau_s; rho_M1, coefficient_condition, h_alternative, singular_values, detail, iterations, halvings, converged=true, check_branch=false) -> DispersionRoute

Dossier E4 and E8 for a FORMED 4x2 graph `D`: `graph`, `canonical_area`, `invariance_residual` and
`trace_residual` are always unique; `:graph_isotropic` when `converged` and `|area| <= _ISOTROPY_MULTIPLIER * rho_M1
* max(1, ||D||_2^2)` (a non-converged iterate is `:not_invariant` whatever its area); else `(zeta, eta, h)` by (D8); `:not_invariant` when `converged` is false OR the
normalized (I1) residual exceeds `_ROUTE_INVARIANCE_MULTIPLIER * eps * kappa_route`, `kappa_route =
_kappa_route(M, D, coefficient_condition) = max(1, ||M||_F) * max(1, gamma) * max(1, ||D||_F^2 / N(D))` with
`gamma` the route's reported `coefficient_condition` (1 when unavailable) and `N` the residual's normalizer
(the `detail` says which of the two fired). An iteration that stopped short of its stop floor (a stall or
the cap, `converged = false`) is `:not_invariant` whatever the floor says: the floor is bounded on garbage
graphs with `M_lr D != 0` (`N` grows with `||D||_F^2` there, so a diverged iterate is no longer inside it by
construction as it was under the landed `||D||_F^2` kappa, M1, 2026-09-13; for `D` in `ker(M_lr)` the bracket
grows as `||D||_F` and the residual cap above refuses the floor, stage 9 S2b-3), but it cannot judge a stall on its own (the trial-011
crab stall sits at ratio 3.60 of `eps kappa_route` in both arms, inside the accepted band), so the converged flag STAYS
the iterative routes' acceptance. Convergence to the stop floor is that acceptance (a converged iterate is
within the (I1) floor by construction: `c_stop <= c_inv` and `kappa_route >= max(1, ||M||_F)`), the (I1)
floor the direct routes' (they call with the default `converged = true`). In every `:not_invariant` case
`zeta`, `eta`, `h` are unavailable with the status's reason and the graph stays reported.
With `check_branch` (the iterative routes) a CONVERGED graph whose `trace_residual` exceeds
`inv_floor * max(1, ||M||_F)` is `:not_invariant` too: it is an invariant plane of another mode (theory 8.6).
Derivation of that floor (re-derived for the 2026-10-18 audit, U22-7, fix batch 4b): the trace residual
`t(D) = tr(M_lr D + M_ll) - tau_s` vanishes on the selected mode's exact graph `D*`, so for a converged iterate
`D = D* + dD` it is `|tr(M_lr dD)| <= ||M_lr||_F ||dD||_F <= ||M||_F ||dD||_F`; the (I1) acceptance admits a
graph error of the order of its own floor `inv_floor = c_inv eps kappa_route` (`kappa_route` carries the route's
amplification `gamma` into the graph), so the branch floor is that admitted graph error times the trace's
Lipschitz constant `||M||_F`, and `max(1, .)` keeps it at least `inv_floor` where `||M||_F < 1` (there the direct
roundoff of the trace, `eps ||M|| (1 + ||D||)`, is below `eps kappa_route`). What the floor must admit is the trace
residual of the exact graph (roundoff), what it must reject is another branch's `|tau_k - tau_s|`, a mode-trace
separation. Measured on the 20 dense maps of `MersenneTwister(20260911)` (probe `d3_branch_floor.jl`, fix batch 4b):
on map 1 (the 4b contract's fixture) Newton's trace residual is 2.2e-16 against the (I1) floor 5.6e-12 and the
branch floor 1.6e-11 (`||M||_F = 2.82`), the mode traces 1.3311, 1.9506 (selected), 1.9868, separations 0.62 and
0.036; over the 20 maps and both iterative routes the largest admitted `|t(D)| / floor` is 1.8e-3 and the smallest
other-branch separation is 7.9 decades above its floor (map 7: 0.0117 against 1.4e-10), so the floor sits more
than two decades above what it admits and more than seven below what it rejects.
Before any of these, a CONVERGED graph whose floor is at or above `_INVARIANCE_RESIDUAL_CAP` (3, the normalized
residual's triangle-inequality cap) is `:singular_coefficient` with the graph reported and zeta, eta, h
unavailable: such a floor accepts every graph, so it certifies none (stage 9, S2b-1, 2026-09-16); an unconverged
iterate keeps the flag's `:not_invariant`.
"""
function _route_from_graph(route::Symbol, M::AbstractMatrix{<:Real}, D::AbstractMatrix{<:Real}, tau_s::Real; rho_M1::Real,
                           coefficient_condition::Determined{Float64}=Determined{Float64}(:not_derived_for_cluster, "no linear solve in this route"),
                           h_alternative::Determined{Float64}=Determined{Float64}(:not_derived_for_cluster, "no second evaluation of h in this route"),
                           singular_values::Vector{Float64}=Float64[], detail::AbstractString="", iterations::Integer=0,
                           halvings::Integer=0, converged::Bool=true, check_branch::Bool=false)
    Df = Matrix{Float64}(D)
    # a graph with a non-finite entry (an overflowed solve or iterate) has no residual to judge: refused up front,
    # never handed to the floors below, whose comparisons would all be false (stage 9, U5-1-4)
    all(isfinite, Df) || return _unavailable_route(route, :singular_coefficient,
        "the graph has a non-finite entry" * (isempty(detail) ? "" : "; " * detail);
        coefficient_condition=coefficient_condition, singular_values=singular_values, iterations=iterations,
        halvings=halvings, converged=false)
    res = _route_residuals(M, Df, tau_s)
    inv_res = Determined{_ROUTE_RESIDUAL_T}(:unique, res.invariance, nothing, :none, "")
    kappa_route = _kappa_route(M, Df, coefficient_condition)
    inv_floor = _ROUTE_INVARIANCE_MULTIPLIER * eps(Float64) * kappa_route
    iso_floor = _ISOTROPY_MULTIPLIER * rho_M1 * max(1.0, opnorm(Df)^2)
    common = (Determined(Df), Determined(res.area), inv_res, Determined(res.trace_residual), coefficient_condition, h_alternative,
              singular_values, Int(iterations), Int(halvings), converged)
    if converged && (!isfinite(inv_floor) || inv_floor >= _INVARIANCE_RESIDUAL_CAP)
        # The normalized residual is at most _INVARIANCE_RESIDUAL_CAP for every graph, so this floor cannot reject
        # one: the route's amplification has made the (I1) acceptance vacuous (stage 9, S2b-1). Refuse, report. A
        # non-finite floor (an overflowed kappa_route) is refused here too: every comparison below would be false
        # and the graph would fall through to :none (stage 9, U5-1-4).
        reason = :singular_coefficient
        gamma_text = is_determined(coefficient_condition) ? string(determined_value(coefficient_condition)) : "unavailable"
        d = "the (I1) floor c_inv eps kappa_route = $(inv_floor) " * (isfinite(inv_floor) ? "is at or above" : "is not finite, so it cannot fall below") * " the normalized residual's cap $(_INVARIANCE_RESIDUAL_CAP) (kappa_route = $(kappa_route), amplification $(gamma_text)): the acceptance cannot fail, so the graph is reported but not certified as a dispersion" *
            (isempty(detail) ? "" : "; " * detail)
        return DispersionRoute(route, reason, d, common[1], Determined{Vector{Float64}}(reason, d), Determined{Vector{Float64}}(reason, d),
                               Determined{Float64}(reason, d), common[2:end]...)
    end
    if converged && abs(res.area) <= iso_floor
        # an iterate that stopped short of its stop floor is :not_invariant below whatever its area: the stall,
        # not a property of the garbage graph, is the finding (M1; stage 9, U5-2-1)
        reason = :graph_isotropic
        d = "canonical area $(res.area) at or below the isotropy floor $(iso_floor); no canonical normalization exists" *
            (isempty(detail) ? "" : "; " * detail)
        return DispersionRoute(route, reason, d, common[1], Determined{Vector{Float64}}(reason, d), Determined{Vector{Float64}}(reason, d),
                               Determined{Float64}(reason, d), common[2:end]...)
    end
    if check_branch && converged && abs(res.trace_residual) > inv_floor * max(1.0, norm(M))
        # An iteration converged on ANOTHER invariant plane (theory 8.6: every invariant plane solves (D14);
        # the branch is told apart by tr(M_lr D + M_ll) = tau_s). Not the dispersion of the selected mode.
        reason = :not_invariant
        d = "the graph is invariant but lies on another branch: tr(M_lr D + M_ll) - tau_s = $(res.trace_residual) exceeds $(inv_floor * max(1.0, norm(M))); the (D15) start did not continue from the selected mode" *
            (isempty(detail) ? "" : "; " * detail)
        return DispersionRoute(route, reason, d, common[1], Determined{Vector{Float64}}(reason, d), Determined{Vector{Float64}}(reason, d),
                               Determined{Float64}(reason, d), common[2:end]...)
    end
    if !converged || res.invariance.normalized > inv_floor
        # An iterate that stopped short of its stop floor is judged by convergence, not by the (I1) floor: the floor
        # is bounded on garbage graphs with M_lr D != 0 (_kappa_route; the ker(M_lr) end is the cap refusal above), but a
        # stall can sit inside the accepted band (M1, 2026-09-13).
        reason = :not_invariant
        d = (converged ? "normalized (I1) residual $(res.invariance.normalized) exceeds the floor $(inv_floor) (kappa_route = $(kappa_route)); the graph is reported but is not a dispersion" :
                         "the iteration stopped short of the stop floor (converged = false): normalized (I1) residual $(res.invariance.normalized) against the floor $(inv_floor) (kappa_route = $(kappa_route)); the graph is reported but is not a dispersion") *
            (isempty(detail) ? "" : "; " * detail)
        return DispersionRoute(route, reason, d, common[1], Determined{Vector{Float64}}(reason, d), Determined{Vector{Float64}}(reason, d),
                               Determined{Float64}(reason, d), common[2:end]...)
    end
    g = _graph_to_dispersion(Df)
    return DispersionRoute(route, :none, String(detail), common[1], Determined(g.zeta), Determined(g.eta), Determined(g.h), common[2:end]...)
end

"""
    _eigenplane_route(M, u_s, tau_s; rho_M1) -> DispersionRoute

Dossier E4, theory 8.3: `U_s = [Re u_s, -Im u_s]`, `U_rs = U_s[1:4, :]`,
`U_ls = U_s[5:6, :]`; regular iff `sigma_min(U_ls) > _GRAPH_SINGULARITY_MULTIPLIER
* rho_M1 * max(1, ||U_s||_2)` (else `:singular_longitudinal_projection`,
graph, zeta, eta, h unavailable, the singular values reported); then
`D = U_rs / U_ls` (D10), `h = det U_ls` with `h_alternative = -Im(conj(u_z)
u_pz)` (D12), `(zeta, eta, h)` by `_graph_to_dispersion` (D8) checked against
the direct (D12) forms (their difference goes into `detail`), the residuals
of `_route_residuals`, `:graph_isotropic` when the area is at or below its
floor, `:not_invariant` when the normalized (I1) residual exceeds
`_ROUTE_INVARIANCE_MULTIPLIER * eps * kappa_route`.
"""
function _eigenplane_route(M::AbstractMatrix{<:Real}, u_s::AbstractVector{<:Complex}, tau_s::Real; rho_M1::Real)
    size(M) == (6, 6) || throw(ArgumentError("_eigenplane_route takes a 6x6 matrix, got $(size(M))"))
    length(u_s) == 6 || throw(ArgumentError("_eigenplane_route takes a 6-vector, got length $(length(u_s))"))
    (isfinite(rho_M1) && rho_M1 >= 0) || throw(ArgumentError("_eigenplane_route: rho_M1 must be a non-negative finite number, got $(rho_M1)"))
    u = Vector{ComplexF64}(u_s)
    # (D9): the real pair U_s = [Re u, -Im u]; U_rs its transverse rows, U_ls the longitudinal 2x2.
    Us = hcat(real.(u), -imag.(u))
    Urs = Us[1:4, :]; Uls = Us[5:6, :]
    sv = svdvals(Uls)
    floor = _GRAPH_SINGULARITY_MULTIPLIER * rho_M1 * max(1.0, opnorm(Us))
    condition = _condition_number(sv[1], sv[end], "the longitudinal projection U_ls")
    # (D12) direct forms: h = -Im(conj(u_z) u_pz), eta_a = -Im(conj(u_z) u_a), zeta_a = -Im(conj(u_a) u_pz) / h.
    h12 = -imag(conj(u[5]) * u[6])
    if sv[end] <= floor
        d = "sigma_min(U_ls) = $(sv[end]) at or below the floor $(floor): the longitudinal projection of the mode is singular (h = 0); the mode is retained in the cluster report"
        return _unavailable_route(:eigenplane, :singular_longitudinal_projection, d; coefficient_condition=condition, singular_values=sv)
    end
    D = Urs / Uls                                 # (D10)
    h_det = det(Uls)                              # (D11)
    eta12 = [-imag(conj(u[5]) * u[a]) for a in 1:4]
    zeta12 = [-imag(conj(u[a]) * u[6]) for a in 1:4] ./ h12
    g = _graph_to_dispersion(D)
    d12 = "(D12) versus (D8): |zeta| $(norm(zeta12 - g.zeta, Inf)), |eta| $(norm(eta12 - g.eta, Inf)), |h| $(abs(h12 - g.h)); det U_ls - (D8) h = $(h_det - g.h)"
    r = _route_from_graph(:eigenplane, M, D, tau_s; rho_M1=rho_M1, coefficient_condition=condition,
                          h_alternative=Determined(h12), singular_values=sv, detail=d12)
    # (D11) h = det U_ls is the route's h; (D8) of the same graph must agree (their difference is in detail).
    if r.status === :none
        r = DispersionRoute(r.route, r.status, r.detail, r.graph, r.zeta, r.eta, Determined(h_det), r.canonical_area,
                            r.invariance_residual, r.trace_residual, r.coefficient_condition, r.h_alternative,
                            r.singular_values, r.iterations, r.halvings, r.converged)
    end
    return r
end

"""
    _polynomial_route(M, tau_s; rho_M1) -> DispersionRoute

Dossier E5, theory 8.5 (D18)-(D19): `A_s = M_rr^2 + M_rl M_lr - tau_s M_rr +
I_4`, `B_s = M_rr M_rl + M_rl M_ll - tau_s M_rl`, `D = -(A_s \\ B_s)`;
`coefficient_condition = ||M||_F^2 / sigma_min(A_s)`, the route's roundoff
amplification into its graph (the singular values of `A_s` reported beside
it; the landed `cond(A_s) = sigma_max(A_s) / sigma_min(A_s)` under-states
it because the formation error of `A_s` is `eps ||M||_F^2`, so `cond(A_s)`
misses the factor `||M||_F^2 / ||A_s||_2`: witness ratio 134.8 at multiplier
1 on the derivation's corpus, 2026-09-14); `:singular_coefficient` when
`sigma_min(A_s) <= _COEFFICIENT_CONDITION_MULTIPLIER * rho_M1 * max(1,
||A_s||_2)` ((N16): coincident traces or a singular projection; the guard
compares `sigma_min(A_s)` with its floor directly, never the reported
condition); otherwise the (D8) conversion and the residuals as in E4.
"""
function _polynomial_route(M::AbstractMatrix{<:Real}, tau_s::Real; rho_M1::Real)
    size(M) == (6, 6) || throw(ArgumentError("_polynomial_route takes a 6x6 matrix, got $(size(M))"))
    isfinite(tau_s) || throw(ArgumentError("_polynomial_route: tau_s must be finite, got $(tau_s)"))
    (isfinite(rho_M1) && rho_M1 >= 0) || throw(ArgumentError("_polynomial_route: rho_M1 must be a non-negative finite number, got $(rho_M1)"))
    Mf = Matrix{Float64}(M)
    Mrr = Mf[1:4, 1:4]; Mrl = Mf[1:4, 5:6]; Mlr = Mf[5:6, 1:4]; Mll = Mf[5:6, 5:6]
    # (D18)-(D19): A_s D = -B_s with the selected trace tau_s = 2 cos mu_s (no cubic solve here).
    As = Mrr * Mrr + Mrl * Mlr - tau_s * Mrr + Matrix{Float64}(I, 4, 4)
    Bs = Mrr * Mrl + Mrl * Mll - tau_s * Mrl
    sv = svdvals(As)
    floor = _COEFFICIENT_CONDITION_MULTIPLIER * rho_M1 * max(1.0, sv[1])
    condition = _condition_number(norm(Mf)^2, sv[end], "the (D19) coefficient A_s (amplification ||M||_F^2 / sigma_min(A_s))")
    if sv[end] <= floor
        d = "sigma_min(A_s) = $(sv[end]) at or below the floor $(floor): (N16) det A_s = h^2 (tau_1 - tau_s)^2 (tau_2 - tau_s)^2 vanishes (coincident selected trace or h = 0)"
        return _unavailable_route(:polynomial, :singular_coefficient, d; coefficient_condition=condition, singular_values=sv)
    end
    D = -(As \ Bs)
    solve_residual = norm(As * D + Bs) / max(1.0, norm(Bs), norm(As * D))
    return _route_from_graph(:polynomial, Mf, D, tau_s; rho_M1=rho_M1, coefficient_condition=condition, singular_values=sv,
                             detail="(D19) solve residual $(solve_residual)")
end

"""
    _projector_route(M, taus, selected; rho_M1, reference_projector=nothing) -> DispersionRoute

Dossier E6, theory 8.5 (D26)-(D27): with `Z = M + M^-1` (the symplectic
inverse `_symplectic_inverse`) and the three traces `taus` (the selected one
at index `selected`), `P_s = prod_{k != s} (Z - tau_k I) / (tau_s - tau_k)`
with the repeated betatron factor RETAINED (no division by `tau_1 - tau_2`);
`:singular_coefficient` when any `|tau_s - tau_k|` is at or below
`_COEFFICIENT_CONDITION_MULTIPLIER * rho_M1 * max(1, ||Z||_2)` (the guard
compares the smallest gap with its floor directly); the projector residuals
`||P_s^2 - P_s||`, `||M P_s - P_s M||` in `detail`; `h = tr((P_s)_ll) / 2`
(D27) with `h_alternative` from (D8) of the graph `D = (P_s)_rl / h`;
`:singular_longitudinal_projection` when `|h|` is at or below the graph
floor; then the residuals as in E4. `reference_projector`, when given, is
the caller's projector onto the selected mode's plane (the longitudinal
cluster's spectral projector for a singleton or an unresolved candidate,
the selected mode's (N5) projector `-Im(u u') S` inside a resolved
multi-member cluster, whose cluster projector has rank `2m`; fix batch
2026-10-19, F-176), and `||P_s - reference projector||` joins `detail`, a
diagnostic that decides nothing. `coefficient_condition`: the two
`:singular_*` early returns report the trace-separation condition `cc =
max(1, ||Z||_2) / min_k |tau_s - tau_k|`; the FORMED graph reports the
route's roundoff amplification into it, `max(1, cc)^2 * max(1, ||P_s||_2 /
|h|)` (the two divisions of (D26) and the division by `h` of (D27); `cc`
alone under-states it by a witness ratio 5.6e3 at multiplier 1 on the
derivation's corpus, 2026-09-14).
"""
function _projector_route(M::AbstractMatrix{<:Real}, taus::AbstractVector{<:Real}, selected::Integer; rho_M1::Real,
                          reference_projector::Union{Nothing,AbstractMatrix{<:Real}}=nothing)
    size(M) == (6, 6) || throw(ArgumentError("_projector_route takes a 6x6 matrix, got $(size(M))"))
    length(taus) == 3 || throw(ArgumentError("_projector_route takes three traces, got $(length(taus))"))
    all(isfinite, taus) || throw(ArgumentError("_projector_route: the traces must be finite, got $(taus)"))
    1 <= selected <= 3 || throw(ArgumentError("_projector_route: selected index $(selected) outside 1:3"))
    (isfinite(rho_M1) && rho_M1 >= 0) || throw(ArgumentError("_projector_route: rho_M1 must be a non-negative finite number, got $(rho_M1)"))
    Mf = Matrix{Float64}(M)
    Z = Mf + _symplectic_inverse(Mf)
    I6 = Matrix{Float64}(I, 6, 6)
    tau_s = Float64(taus[selected])
    others = [Float64(taus[k]) for k in 1:3 if k != selected]
    gaps = abs.(tau_s .- others)
    floor = _COEFFICIENT_CONDITION_MULTIPLIER * rho_M1 * max(1.0, opnorm(Z))
    condition = _condition_number(max(1.0, opnorm(Z)), minimum(gaps), "the (D26) trace separation min |tau_s - tau_k|")
    if minimum(gaps) <= floor
        d = "trace separation min |tau_s - tau_k| = $(minimum(gaps)) at or below the floor $(floor): (D26) divides by a vanishing mode separation"
        return _unavailable_route(:projector, :singular_coefficient, d; coefficient_condition=condition, singular_values=gaps)
    end
    # (D26) with BOTH other factors retained (equal betatron traces never enter a denominator here).
    Ps = I6
    for tk in others
        Ps = Ps * ((Z - tk * I6) / (tau_s - tk))
    end
    idem = norm(Ps * Ps - Ps); comm = norm(Mf * Ps - Ps * Mf)
    # (D27): (P_s)_ll = h I_2, D = (P_s)_rl / h.
    h = tr(Ps[5:6, 5:6]) / 2
    ll_dev = norm(Ps[5:6, 5:6] - h * Matrix{Float64}(I, 2, 2))
    diag_detail = "projector residuals: ||P^2 - P|| $(idem), ||M P - P M|| $(comm), ||(P_s)_ll - h I|| $(ll_dev)" *
                  (reference_projector === nothing ? "" : ", ||P_s - reference projector|| $(norm(Ps - reference_projector))")
    nPs = opnorm(Ps)
    gfloor = _GRAPH_SINGULARITY_MULTIPLIER * rho_M1 * max(1.0, nPs)
    if abs(h) <= gfloor
        d = "|h| = tr((P_s)_ll) / 2 = $(abs(h)) at or below the floor $(gfloor): the projector is finite but has no physical graph; " * diag_detail
        return _unavailable_route(:projector, :singular_longitudinal_projection, d; coefficient_condition=condition, singular_values=gaps)
    end
    D = Ps[1:4, 5:6] / h
    h8 = 1 / (1 + dot(D[:, 1], _symplectic_form(4) * D[:, 2]))
    # The formed graph's amplification factor: the trace-separation condition squared (two (D26) divisions) times the
    # (D27) division by h. `condition` is unavailable only when the smallest gap is exactly 0, caught by the floor above.
    is_determined(condition) || error("_projector_route: the trace-separation condition is unavailable past its own floor ($(condition.reason): $(condition.detail))")
    cc = determined_value(condition)
    amplification = Determined(max(1.0, cc)^2 * max(1.0, nPs / abs(h)))
    r = _route_from_graph(:projector, Mf, D, tau_s; rho_M1=rho_M1, coefficient_condition=amplification, h_alternative=Determined(h8),
                          singular_values=gaps, detail=diag_detail)
    # (D27) h is the route's h; the (D8) evaluation of the same graph is h_alternative.
    if r.status === :none
        r = DispersionRoute(r.route, r.status, r.detail, r.graph, r.zeta, r.eta, Determined(h), r.canonical_area,
                            r.invariance_residual, r.trace_residual, r.coefficient_condition, r.h_alternative,
                            r.singular_values, r.iterations, r.halvings, r.converged)
    end
    return r
end

"""
    _iteration_start(M, D0, who) -> (D, condition, source, detail)

The common start of the iterative routes (dossier E7): `D0` when given (a finite 4x2 matrix, else an
`ArgumentError`), otherwise the Sylvester initializer (D15); `condition` is the (D16) operator's 2-norm
condition as a `Determined` in both cases (unavailable with `:singular_coefficient` when it is not a finite
Float64, stage 9 U5-1-3); a LAPACK-singular (D15) operator returns `D = nothing` with the named detail
(the caller reports `:singular_coefficient`).
"""
function _iteration_start(M::AbstractMatrix{<:Real}, D0, who::AbstractString)
    Mrr = M[1:4, 1:4]; Mll = M[5:6, 5:6]
    op = kron(Matrix{Float64}(I, 2, 2), Mrr) - kron(transpose(Mll), Matrix{Float64}(I, 4, 4))
    condition = _operator_condition(op, "the (D16) Sylvester operator")
    if D0 !== nothing
        (D0 isa AbstractMatrix && size(D0) == (4, 2) && all(isfinite, D0)) || throw(ArgumentError(
            "$(who): D0 must be a finite 4x2 matrix"))
        return (D=Matrix{Float64}(D0), condition=condition, source="the given D0", detail="")
    end
    try
        init = _sylvester_initializer(M)
        return (D=init.D0, condition=init.condition, source="the (D15) Sylvester initializer", detail="")
    catch err
        err isa ArgumentError || rethrow()
        return (D=nothing, condition=condition, source="none", detail="no initializer: " * err.msg)
    end
end

"""
    _newton_route(M, tau_s; rho_M1, max_iterations=50, D0=nothing, max_halvings=_MAX_HALVINGS) -> DispersionRoute

Dossier E7, theory 8.6 (D21)-(D22): start from `D0` (default the Sylvester
initializer (D15)); each step `delta = sylvester(M_rr - D M_lr, -(M_ll + M_lr D), F(D))`
with the raw residual `F(D) = M_rr D + M_rl - D (M_lr D + M_ll)`; accept
`D + delta` when its normalized (I1) residual decreases, else halve `delta`
and try again (at most `max_halvings` halved trials per step; a step none of
whose trials decreases the residual is a STALL: the iteration ends on the
last accepted graph with `converged = false`); `halvings` counts the halved
trials over the whole iteration; stop when the residual is at or
below `_ITERATION_STOP_MULTIPLIER * eps * max(1, ||M||_F)` or after
`max_iterations`. `converged` says which; `coefficient_condition` is the
2-norm condition of the last Sylvester operator `I_2 kron (M_rr - D M_lr) -
(M_ll + M_lr D)' kron I_4`; a singular operator (LAPACK) is
`:singular_coefficient`; an unconverged result is `:not_invariant` with its
graph reported.
"""
function _newton_route(M::AbstractMatrix{<:Real}, tau_s::Real; rho_M1::Real, max_iterations::Integer=50, D0=nothing,
                       max_halvings::Integer=_MAX_HALVINGS)
    size(M) == (6, 6) || throw(ArgumentError("_newton_route takes a 6x6 matrix, got $(size(M))"))
    isfinite(tau_s) || throw(ArgumentError("_newton_route: tau_s must be finite, got $(tau_s)"))
    (isfinite(rho_M1) && rho_M1 >= 0) || throw(ArgumentError("_newton_route: rho_M1 must be a non-negative finite number, got $(rho_M1)"))
    max_iterations >= 1 || throw(ArgumentError("_newton_route: max_iterations must be >= 1, got $(max_iterations)"))
    max_halvings >= 0 || throw(ArgumentError("_newton_route: max_halvings must be >= 0, got $(max_halvings)"))
    Mf = Matrix{Float64}(M)
    Mrr = Mf[1:4, 1:4]; Mrl = Mf[1:4, 5:6]; Mlr = Mf[5:6, 1:4]; Mll = Mf[5:6, 5:6]
    start = _iteration_start(Mf, D0, "_newton_route")
    start.D === nothing && return _unavailable_route(:newton, :singular_coefficient, start.detail;
                                                     coefficient_condition=start.condition, converged=false)
    D = start.D
    stop = _ITERATION_STOP_MULTIPLIER * eps(Float64) * max(1.0, norm(Mf))
    F(X) = Mrr * X + Mrl - X * (Mlr * X + Mll)
    current = _graph_invariance_residual(Mf, D).normalized
    iterations = 0; halvings = 0; converged = current <= stop; stalled = false
    condition = start.condition
    while !converged && iterations < max_iterations
        Aop = Mrr - D * Mlr; Bop = Mll + Mlr * D
        op = kron(Matrix{Float64}(I, 2, 2), Aop) - kron(transpose(Bop), Matrix{Float64}(I, 4, 4))
        condition = _operator_condition(op, "the (D21) Sylvester operator at iteration $(iterations + 1)")
        # a condition beyond Float64 is the singular operator of the LAPACK branch below, refused before the solve
        # with the same reason and the operator's own condition (stage 9, U5-1-3)
        is_determined(condition) || return _unavailable_route(:newton, :singular_coefficient, condition.detail;
                                                              coefficient_condition=condition, iterations=iterations,
                                                              halvings=halvings, converged=false)
        delta = try
            sylvester(Aop, -Bop, F(D))              # (D21): (M_rr - D M_lr) delta - delta (M_ll + M_lr D) = -F(D)
        catch err
            err isa LinearAlgebra.LAPACKException || rethrow()
            d = "the (D21) Sylvester operator is singular at iteration $(iterations + 1) (LAPACK $(err.info))"
            return _unavailable_route(:newton, :singular_coefficient, d; coefficient_condition=condition, iterations=iterations,
                                      halvings=halvings, converged=false)
        end
        iterations += 1
        accepted = false
        for k in 0:max_halvings                      # k = 0 is the full step; k >= 1 the k-th halved trial
            if k > 0
                halvings += 1
                delta = delta / 2
            end
            trial = _graph_invariance_residual(Mf, D + delta).normalized
            if trial < current
                D = D + delta; current = trial; accepted = true
                break
            end
        end
        if !accepted
            stalled = true
            break
        end
        converged = current <= stop
    end
    detail = "Newton from $(start.source) (initializer condition $(_condition_text(start.condition))); final normalized (I1) residual $(current), stop floor $(stop)" *
             (converged ? "; converged" : stalled ? "; stalled: no trial of step $(iterations) decreased the residual within $(max_halvings) halvings ($(halvings) halved trials in all)" : "; iteration cap $(max_iterations) reached")
    r = _route_from_graph(:newton, Mf, D, tau_s; rho_M1=rho_M1, coefficient_condition=condition, detail=detail,
                          iterations=iterations, halvings=halvings, converged=converged, check_branch=true)
    return r
end

"""
    _fixed_point_route(M, tau_s; rho_M1, max_iterations=50, D0=nothing) -> DispersionRoute

Dossier E7, theory 8.6 (D20): `D_next = sylvester(M_rr, -M_ll, M_rl - D M_lr D)`
from the same start, the same stopping rule (the (D16) operator's condition
is `coefficient_condition`; the contraction ratio `2 ||M_lr||_2 ||D||_2 /
sigma_min(operator)` goes into `detail`), no halving (`halvings = 0`). An
unconverged result (a stall: the step no longer decreases the residual; or
the cap `max_iterations`) is `:not_invariant` with its graph reported, like
Newton's: `_route_from_graph` judges an iterate by `converged`, not by the
(I1) floor.
"""
function _fixed_point_route(M::AbstractMatrix{<:Real}, tau_s::Real; rho_M1::Real, max_iterations::Integer=50, D0=nothing)
    size(M) == (6, 6) || throw(ArgumentError("_fixed_point_route takes a 6x6 matrix, got $(size(M))"))
    isfinite(tau_s) || throw(ArgumentError("_fixed_point_route: tau_s must be finite, got $(tau_s)"))
    (isfinite(rho_M1) && rho_M1 >= 0) || throw(ArgumentError("_fixed_point_route: rho_M1 must be a non-negative finite number, got $(rho_M1)"))
    max_iterations >= 1 || throw(ArgumentError("_fixed_point_route: max_iterations must be >= 1, got $(max_iterations)"))
    Mf = Matrix{Float64}(M)
    Mrr = Mf[1:4, 1:4]; Mrl = Mf[1:4, 5:6]; Mlr = Mf[5:6, 1:4]; Mll = Mf[5:6, 5:6]
    start = _iteration_start(Mf, D0, "_fixed_point_route")
    start.D === nothing && return _unavailable_route(:fixed_point, :singular_coefficient, start.detail;
                                                     coefficient_condition=start.condition, converged=false)
    D = start.D
    op = kron(Matrix{Float64}(I, 2, 2), Mrr) - kron(transpose(Mll), Matrix{Float64}(I, 4, 4))
    sigma_min = svdvals(op)[end]
    condition = start.condition
    # the (D20) iteration solves with this operator at every step and its contraction ratio divides by sigma_min:
    # a condition beyond Float64 is refused up front, the same way the LAPACK-singular solve below is (stage 9, U5-1-3)
    is_determined(condition) || return _unavailable_route(:fixed_point, :singular_coefficient,
        "the (D16) Sylvester operator is singular to working precision: " * condition.detail;
        coefficient_condition=condition, converged=false)
    stop = _ITERATION_STOP_MULTIPLIER * eps(Float64) * max(1.0, norm(Mf))
    current = _graph_invariance_residual(Mf, D).normalized
    iterations = 0; converged = current <= stop; stalled = false
    while !converged && iterations < max_iterations
        Dn = try
            sylvester(Mrr, -Mll, Mrl - D * Mlr * D)   # (D20): M_rr D' - D' M_ll = -(M_rl - D M_lr D)
        catch err
            err isa LinearAlgebra.LAPACKException || rethrow()
            d = "the (D20) Sylvester operator is singular (LAPACK $(err.info))"
            return _unavailable_route(:fixed_point, :singular_coefficient, d; coefficient_condition=condition, iterations=iterations, converged=false)
        end
        iterations += 1
        next = _graph_invariance_residual(Mf, Dn).normalized
        if !(isfinite(next)) || next >= current && next > stop
            # a step that no longer decreases the residual ends the iteration on the last accepted graph
            stalled = true
            break
        end
        D = Dn; current = next
        converged = current <= stop
    end
    ratio = sigma_min > 0 ? 2 * opnorm(Mlr) * opnorm(D) / sigma_min : Inf
    detail = "fixed point from $(start.source) (operator condition $(_condition_text(start.condition))); contraction ratio 2 ||M_lr|| ||D|| / sigma_min(op) = $(ratio); " *
             "final normalized (I1) residual $(current), stop floor $(stop)" *
             (converged ? "; converged" : stalled ? "; stalled (the step did not decrease the residual)" : "; iteration cap $(max_iterations) reached")
    return _route_from_graph(:fixed_point, Mf, D, tau_s; rho_M1=rho_M1, coefficient_condition=condition, detail=detail,
                             iterations=iterations, halvings=0, converged=converged, check_branch=true)
end

"""
    _signed_z_area(u) -> Float64

`kappa_z = -Im(conj(u_z) u_pz)` of a 6-vector (theory (K12); dossier E3, E9). Signed, never absolute.
"""
_signed_z_area(u::AbstractVector{<:Complex}) = -imag(conj(u[5]) * u[6])

"""
    _eigenvalue_trace(rho) -> Float64

The trace `tau = Re(rho + 1 / rho)` of one oriented eigenvalue (`2 cos mu` on the unit circle): the projector
route's factor `(Z - tau I)` annihilates the mode of `rho` when `rho + 1 / rho` is real, i.e. on the unit circle
and for a real hyperbolic pair. The per-mode trace of a resolved cluster's recovered modes (fix batch 2026-10-19,
F-176) and, through [`_cluster_trace`](@ref), the common trace of an unresolved one.
"""
_eigenvalue_trace(rho::Number) = real(rho + 1 / rho)

"""
    _cluster_trace(c) -> Float64

The trace [`_eigenvalue_trace`](@ref) of the cluster's first eigenvalue: the common trace shared by the half members
of a definite UNRESOLVED, an unresolved or a defective cluster (a RESOLVED multi-member cluster has one trace per
recovered mode, which `_dispersion_routes` reads from its `modes`, never from this first-member value; fix batch
2026-10-19, F-176). Not for a Krein quartet: there `Im(rho + 1 / rho) = (|rho| - 1 / |rho|) sin mu` is non-zero, so
`_dispersion_routes` takes no trace from an `:unstable` cluster (stage 9, U5-2-3).
"""
function _cluster_trace(c::ModeCluster)
    isempty(c.eigenvalues) && throw(ArgumentError("_cluster_trace: cluster $(c.members) has no eigenvalues"))
    return _eigenvalue_trace(c.eigenvalues[1])
end

"""
    _check_longitudinal_index(clusters, longitudinal) -> Int

The range check of an explicit `longitudinal` (a canonical eigenvalue index into `clusters.eigenvalues`):
the `Int` index, or an `ArgumentError` naming it and the range. ONE check for the two sites that read the
index, `_dispersion_routes` (before its coasting branch) and `_longitudinal_candidate` (the normal path):
the check lived in the candidate rule alone, which the coasting branch returned before reaching, so on a
coasting map `longitudinal = 99` was accepted silently against the documented refusal (2026-10-18 audit,
F-178).
"""
function _check_longitudinal_index(clusters::ModeClusters, longitudinal)
    idx = Int(longitudinal)
    1 <= idx <= length(clusters.eigenvalues) || throw(ArgumentError(
        "_dispersion_routes: longitudinal = $(idx) is not a canonical eigenvalue index in 1:$(length(clusters.eigenvalues))"))
    return idx
end

"""
    _longitudinal_candidate(clusters, longitudinal) -> (cluster, mode, index)

Dossier E9: the longitudinal candidate cluster (position in `clusters.clusters`), the selected
`ClusterMode` (or `nothing` when the cluster is not resolved) and its canonical eigenvalue index (0 when
none). Without `longitudinal`: the cluster whose modes (resolved) or `frame` / `signed_basis` columns
(unresolved) carry the largest TOTAL signed z-area, then, inside a resolved cluster, the mode with the
largest signed z-area. The real-class clusters (unstable or unit-eigenvalue: no frame, no signed basis,
no (K12) area of their own) compete TOGETHER with the z-content the complex-class clusters leave,
`1 - sum_c kappa_cz` (the spectral projectors sum to `I_6`, so `tr((P_c)_ll) / 2 = sum_j kappa_jz`
over the clusters sums to 1; (K12) `kappa_sz = h`): when that share is the largest, the FIRST real-class
cluster is the candidate (no mode, index 0) and `_dispersion_routes` reports everything unavailable with
its reason (E9). When no cluster has a basis, the first cluster. This refines E9's two-step rule so that
a resolved betatron singleton of zero z-area never outranks an unresolved longitudinal pair (the
`diag(R(0.73), R(1.41), R(0.73))` fixture) and a betatron mode never outranks a unit-eigenvalue or
hyperbolic synchrotron pair that carries the z-content (review 2026-09-12). The rule stays a heuristic
(see [`ModeLabels6D`](@ref)). With `longitudinal` (a canonical eigenvalue index in `1:6`): the cluster
containing it or its conjugate partner, and its oriented mode.
"""
function _longitudinal_candidate(clusters::ModeClusters, longitudinal)
    cs = clusters.clusters
    if longitudinal !== nothing
        idx = _check_longitudinal_index(clusters, longitudinal)
        ci = findfirst(c -> idx in c.members, cs)
        ci === nothing && throw(ArgumentError("_dispersion_routes: canonical index $(idx) belongs to no cluster"))
        c = cs[ci]
        c.resolved || return (cluster=ci, mode=nothing, index=idx)
        modes = determined_value(c.modes)
        partner = clusters.conjugate_partner[idx]
        k = findfirst(m -> m.index == idx || m.index == partner, modes)
        k === nothing && return (cluster=ci, mode=nothing, index=idx)
        return (cluster=ci, mode=modes[k], index=modes[k].index)
    end
    # Every cluster competes with its TOTAL signed z-area (the sum over its resolved modes, else over its frame
    # or signed-basis columns; invariant under the within-cluster unitary), so an unresolved longitudinal
    # pair is not passed over for a resolved betatron singleton of zero z-area (E9, theory 13.6).
    totals = Vector{Union{Nothing,Float64}}(nothing, length(cs))
    for (ci, c) in enumerate(cs)
        basis = c.resolved ? hcat((m.vector for m in determined_value(c.modes))...) :
                is_determined(c.frame) ? determined_value(c.frame) :
                is_determined(c.signed_basis) ? determined_value(c.signed_basis) : nothing
        basis === nothing && continue
        totals[ci] = sum(_signed_z_area(basis[:, j]) for j in 1:size(basis, 2); init=0.0)
    end
    # The real-class clusters share the z-content the complex-class clusters leave (the projectors sum to I_6).
    real_class = [ci for ci in eachindex(cs) if totals[ci] === nothing]
    if !isempty(real_class)
        totals[real_class[1]] = 1.0 - sum(Float64[t for t in totals if t !== nothing]; init=0.0)
    end
    best = nothing; best_area = -Inf
    for (ci, c) in enumerate(cs)
        totals[ci] === nothing && continue
        total = totals[ci]::Float64
        if total > best_area
            best_area = total
            if c.resolved
                modes = determined_value(c.modes)
                k = argmax([_signed_z_area(m.vector) for m in modes])
                best = (cluster=ci, mode=modes[k], index=modes[k].index)
            else
                best = (cluster=ci, mode=nothing, index=0)
            end
        end
    end
    return best === nothing ? (cluster=1, mode=nothing, index=0) : best
end

"The argument contract `_dispersion_routes` quotes in every ArgumentError (one string, so every message names the same contract)."
const _DISPERSION_ROUTES_ARGUMENT_HELP = "a real 6x6 matrix with finite entries, a ModeClusters report of the same matrix, routes a non-empty tuple of distinct members of DISPERSION_ROUTES, newton_max_iterations >= 1"

"""
    _dispersion_routes(M, clusters::ModeClusters; longitudinal=nothing, routes=DISPERSION_ROUTES, newton_max_iterations=50, fixed_point_max_iterations=_FIXED_POINT_MAX_ITERATIONS) -> DispersionRoutes

Dossier E1, E8-E10 (design steps 3, 8, 9): the coasting test first (E2;
when it holds every route carries `:coasting_structure` and the report's
zeta = 0, eta, h = 1 and the (D7) graph `[0, eta]` come from it); otherwise
the three resolved modes are collected from `clusters` (every cluster
definite and resolved: `labels` by E3, the longitudinal mode by the largest
signed z-area or the explicit `longitudinal` index into the canonical
eigenvalue list; the default rule is a heuristic and the unique `labels`
says so in its `detail`, see [`ModeLabels6D`](@ref)), `tau_s = 2 cos mu_s`,
the projector route's three traces are the resolved modes' own `Re(rho +
1 / rho)` (a resolved multi-member cluster contributes one per recovered
mode, an unresolved one its common trace repeated by its half
multiplicity; fix batch 2026-10-19, F-176), and the requested routes run
with `rho_M1 = clusters.rho_M1`; a route not requested is present with
`:route_not_selected`, and the report's `executed` names the routes whose
kernel ran (recorded at the call, never inferred from a status; fix batch 3,
2026-10-21). When the longitudinal
candidate lies in a definite UNRESOLVED cluster (m >= 2), no route runs on
a mode: `eta` is the ambiguity set of stage 3's `_dispersion_ambiguity_set`
with `:cluster_unresolved`, the polynomial and projector routes are formed
with the cluster's common trace and land in `:singular_coefficient` by
(N16); an indefinite, unresolved, unstable or unit-eigenvalue longitudinal
cluster leaves everything unavailable with that cluster's reason (a real-class
cluster is the candidate when the z-content the complex-class clusters leave
is the largest, see [`_longitudinal_candidate`](@ref), or by the explicit
index). Argument
errors: size, non-finite entries, a `clusters` report of a different matrix,
an empty or repeated `routes` tuple, an unknown route, a bad `longitudinal`
(an index outside `1:length(clusters.eigenvalues)`, refused on EVERY path by
[`_check_longitudinal_index`](@ref) before the coasting test; a valid index
on a coasting map is accepted and not used: the coasting branch supplies the
report with `longitudinal = 0`, and the public option is declared inactive
there; 2026-10-18 audit, F-178).
The fixed point is linearly convergent (theory 8.6) and gets its own cap
`fixed_point_max_iterations` (>= 1; the dense fixtures need up to 139 steps where Newton needs 5).
"""
function _dispersion_routes(M::AbstractMatrix{<:Real}, clusters::ModeClusters; longitudinal=nothing,
                            routes=DISPERSION_ROUTES, newton_max_iterations::Integer=50,
                            fixed_point_max_iterations::Integer=_FIXED_POINT_MAX_ITERATIONS)
    size(M) == (6, 6) || throw(ArgumentError("_dispersion_routes: expected $(_DISPERSION_ROUTES_ARGUMENT_HELP); got a matrix of size $(size(M))"))
    all(isfinite, M) || throw(ArgumentError("_dispersion_routes: expected $(_DISPERSION_ROUTES_ARGUMENT_HELP); the matrix has non-finite entries"))
    Mf = Matrix{Float64}(M)
    clusters.matrix == Mf || throw(ArgumentError("_dispersion_routes: expected $(_DISPERSION_ROUTES_ARGUMENT_HELP); the ModeClusters report describes a different matrix"))
    routes isa Tuple || throw(ArgumentError("_dispersion_routes: routes must be a tuple of members of DISPERSION_ROUTES, got $(typeof(routes))"))
    isempty(routes) && throw(ArgumentError("_dispersion_routes: routes must be a non-empty tuple of members of $(DISPERSION_ROUTES)"))
    for r in routes
        r in DISPERSION_ROUTES || throw(ArgumentError("_dispersion_routes: unknown route :$(r); DISPERSION_ROUTES = $(DISPERSION_ROUTES)"))
    end
    length(unique(routes)) == length(routes) || throw(ArgumentError("_dispersion_routes: repeated route in $(routes)"))
    newton_max_iterations >= 1 || throw(ArgumentError("_dispersion_routes: newton_max_iterations must be >= 1, got $(newton_max_iterations)"))
    fixed_point_max_iterations >= 1 || throw(ArgumentError("_dispersion_routes: fixed_point_max_iterations must be >= 1, got $(fixed_point_max_iterations)"))
    # a bad explicit index is refused before the coasting branch can return without reading it (F-178)
    longitudinal === nothing || _check_longitudinal_index(clusters, longitudinal)
    rho_M1 = clusters.rho_M1
    # Design step 3: the coasting test before any spectral classification (E1, E2).
    coasting = _coasting_structure(Mf; rho_M1=rho_M1)
    # (D17) diagnostics: the cubic roots against every mode trace. A resolved cluster contributes the trace of each of
    # its recovered modes (a resolved multi-member cluster has two distinct ones; its first eigenvalue alone left the
    # other root unmatched and the residual at the trace gap, 0.507 on the fix-W fixture: the neighbour of F-176, fix
    # batch 2026-10-19), an unresolved or real-class cluster its first eigenvalue's trace.
    cubic = _trace_cubic_roots(Mf)
    cluster_traces = Float64[]
    for c in clusters.clusters
        isempty(c.eigenvalues) && continue
        if c.resolved
            for m in determined_value(c.modes)
                push!(cluster_traces, _eigenvalue_trace(m.eigenvalue))
            end
        else
            push!(cluster_traces, _cluster_trace(c))
        end
    end
    isempty(cluster_traces) && throw(ArgumentError("_dispersion_routes: the ModeClusters report has no cluster with eigenvalues; no trace to compare the (D17) cubic with"))
    cubic_residual = maximum(minimum(abs(r - t) for t in cluster_traces) for r in cubic)
    resolved_modes = ClusterMode[m for c in clusters.clusters if c.resolved for m in determined_value(c.modes)]
    resolved_tunes = [m.tune for m in resolved_modes]
    if coasting.holds
        d_coast = "coasting structure holds (margin $(coasting.margin)): zeta = 0, h = 1, eta from (D24); no route runs (theory 8.7)"
        rv = [_unavailable_route(r, :coasting_structure, d_coast) for r in DISPERSION_ROUTES]
        # (D7) with zeta = 0, h = 1: the graph is [0, eta] whenever the (D24) eta is unique (theory 8.7).
        graph_c = is_determined(coasting.eta) ? Determined(hcat(zeros(4), determined_value(coasting.eta))) :
                  Determined{Matrix{Float64}}(coasting.eta.reason, coasting.eta.detail)
        return DispersionRoutes(Mf, Determined{ModeLabels6D}(:coasting_structure, d_coast), 0, 0,
                                Determined{Float64}(:coasting_structure, d_coast), resolved_tunes, cubic, cubic_residual, rv, :eigenplane,
                                graph_c, Determined(zeros(4)), coasting.eta, Determined(1.0),
                                _AGREEMENT_T[], coasting, Symbol[])
    end
    cand = _longitudinal_candidate(clusters, longitudinal)
    c_long = clusters.clusters[cand.cluster]
    # Labels (E3): exactly three resolved modes, else the blocking cluster's reason.
    labels = if length(resolved_modes) == 3
        kf = maximum((is_determined(c.kappa_frame) ? determined_value(c.kappa_frame) : 1.0) for c in clusters.clusters)
        li = (longitudinal === nothing || cand.mode === nothing) ? nothing : findfirst(m -> m.index == cand.mode.index, resolved_modes)
        lb = _mode_labels_6d([m.vector for m in resolved_modes], resolved_tunes; longitudinal=li, kappa_frame=max(1.0, kf))
        d_lb = lb.rule === :explicit ? "longitudinal mode named by the caller (canonical index $(cand.index)); the transverse labels by the x-area rule are a heuristic" :
            "uncertified heuristic: the longitudinal mode is the largest signed z-area, but by (K12) kappa_sz = h a betatron mode can carry more z-area (it must for h < 1/3) and the theory labels the synchrotron mode by continuation (10.4, 13.5), which no endpoint-map rule supplies; an explicit `longitudinal` index certifies the selection"
        Determined{ModeLabels6D}(:unique, lb, nothing, :none, d_lb)
    else
        blocker = findfirst(c -> !c.resolved, clusters.clusters)
        bc = clusters.clusters[blocker === nothing ? 1 : blocker]
        reason = bc.reason === :none ? :cluster_unresolved : bc.reason
        Determined{ModeLabels6D}(reason, "cluster $(bc.members) is $(bc.classification) and not resolved into single modes" * (isempty(bc.detail) ? "" : "; " * bc.detail))
    end
    tunes = if is_determined(labels)
        lb = determined_value(labels)
        resolved_tunes[[lb.transverse[1], lb.transverse[2], lb.longitudinal]]
    else
        resolved_tunes
    end
    # The three traces for the projector route, one per oriented mode. A RESOLVED cluster contributes the trace
    # Re(rho + 1 / rho) of each of its recovered modes: one for a singleton, the two DISTINCT traces of a resolved
    # multi-member cluster (an explicit partition or the chord Inf produces one; the earlier list repeated the cluster's
    # first trace and then averaged it through the trace identity, so the route ran on wrong factors and reported a
    # garbage graph as :not_invariant while `degradations` stayed silent; fix batch 2026-10-19, F-176). An UNRESOLVED
    # multi-member cluster contributes its common trace repeated by its half multiplicity (a definite unresolved
    # betatron pair: the same trace twice, the repeated factor retained); when it is the only multi-member cluster and
    # all three traces are present, its common trace comes from the trace identity tr M = sum_j tau_j instead of its
    # computed eigenvalues (a defective eigenvalue is only sqrt(eps) accurate; tr M and the resolved traces are eps
    # accurate, so the retained repeated factor stays exact). An :unstable cluster contributes no trace. A Krein quartet
    # (complex rho off the unit circle) has two half members and a shared Re(rho + 1 / rho), but rho + 1 / rho itself is
    # not real, so (Z - tau I) annihilates none of its modes; a three-trace count built from it let the projector route
    # run on a non-projector and report :not_invariant where the real hyperbolic pair reports :unstable_spectrum (stage 9,
    # U5-2-3). The blocker below names the cluster's reason for both.
    taus = Float64[]; tau_positions = Int[]; tau_modes = Int[]   # per trace: the cluster's position, the mode's canonical index (0 for a common trace)
    for (ci, c) in enumerate(clusters.clusters)
        (isempty(c.eigenvalues) || c.classification === :unstable) && continue
        if c.resolved
            for m in determined_value(c.modes)
                push!(taus, _eigenvalue_trace(m.eigenvalue)); push!(tau_positions, ci); push!(tau_modes, m.index)
            end
        else
            for _ in 1:length(c.half_members)
                push!(taus, _cluster_trace(c)); push!(tau_positions, ci); push!(tau_modes, 0)
            end
        end
    end
    unresolved_multiples = [ci for (ci, c) in enumerate(clusters.clusters) if length(c.half_members) >= 2 && !c.resolved]
    if length(unresolved_multiples) == 1 && length(taus) == 3
        mi = unresolved_multiples[1]
        others = sum(taus[k] for k in eachindex(taus) if tau_positions[k] != mi; init=0.0)
        common = (tr(Mf) - others) / length(clusters.clusters[mi].half_members)
        for k in eachindex(taus)
            tau_positions[k] == mi && (taus[k] = common)
        end
    end
    # the selected trace: the selected mode's own inside a resolved cluster, the common one of an unresolved candidate
    selected_tau = cand.mode === nothing ? findfirst(==(cand.cluster), tau_positions) :
        findfirst(k -> tau_positions[k] == cand.cluster && tau_modes[k] == cand.mode.index, eachindex(taus))
    # The projector route needs exactly three traces (one per oriented mode); a real-class (unstable or
    # unit-eigenvalue) cluster breaks the count and the route is unavailable with that cluster's reason.
    projector_blocker = (length(taus) == 3 && selected_tau !== nothing) ? nothing :
        begin
            bc = findfirst(c -> c.reason !== :none && c.classification !== :definite, clusters.clusters)
            bc === nothing ? (:singular_coefficient, "the projector route needs three mode traces, found $(length(taus))") :
                (clusters.clusters[bc].reason, "the projector route needs three mode traces, found $(length(taus)): cluster $(clusters.clusters[bc].members) is $(clusters.clusters[bc].classification)")
        end
    run_projector(cp) = projector_blocker === nothing ? _projector_route(Mf, taus, selected_tau; rho_M1=rho_M1, reference_projector=cp) :
        _unavailable_route(:projector, projector_blocker[1], projector_blocker[2])
    make_unavailable(reason, d) = [_unavailable_route(r, r in routes ? reason : :route_not_selected,
                                                      r in routes ? d : "route :$(r) not requested") for r in DISPERSION_ROUTES]
    if !(c_long.classification === :definite)
        # Indefinite, unresolved (defective), unstable or unit-eigenvalue longitudinal cluster (E9).
        reason = c_long.reason === :none ? :cluster_unresolved : c_long.reason
        d_block = "the longitudinal candidate cluster $(c_long.members) is $(c_long.classification)" * (isempty(c_long.detail) ? "" : ": " * c_long.detail)
        return DispersionRoutes(Mf, labels, cand.index, cand.cluster, Determined(_cluster_trace(c_long)), tunes, cubic, cubic_residual,
                                make_unavailable(reason, d_block), :eigenplane, Determined{Matrix{Float64}}(reason, d_block),
                                Determined{Vector{Float64}}(reason, d_block), Determined{Vector{Float64}}(reason, d_block), Determined{Float64}(reason, d_block),
                                _AGREEMENT_T[], coasting, Symbol[])
    end
    tau_s = taus[findfirst(==(cand.cluster), tau_positions)]
    if cand.mode === nothing
        # Definite UNRESOLVED longitudinal cluster (theory 13.5-13.6, design rows 2 and 4): eta is the ambiguity set;
        # the two algebraic routes run with the common trace and land in :singular_coefficient by (N16).
        d_unres = "the longitudinal candidate cluster $(c_long.members) is definite but unresolved (multiplicity $(length(c_long.half_members))): the dispersion is an ambiguity set, not a vector"
        # `executed` is recorded where a route's kernel is called, never inferred from a status afterwards
        rv = DispersionRoute[]; executed = Symbol[]
        for r in DISPERSION_ROUTES
            if !(r in routes)
                push!(rv, _unavailable_route(r, :route_not_selected, "route :$(r) not requested"))
            elseif r === :polynomial
                push!(executed, r)
                push!(rv, _polynomial_route(Mf, tau_s; rho_M1=rho_M1))
            elseif r === :projector
                push!(executed, r)
                push!(rv, run_projector(is_determined(c_long.projector) ? determined_value(c_long.projector) : nothing))
            else
                push!(rv, _unavailable_route(r, :cluster_unresolved, d_unres))
            end
        end
        set = _dispersion_ambiguity_set(c_long)
        return DispersionRoutes(Mf, labels, 0, cand.cluster, Determined(tau_s), tunes, cubic, cubic_residual, rv, :eigenplane,
                                Determined{Matrix{Float64}}(:cluster_unresolved, d_unres), Determined{Vector{Float64}}(:cluster_unresolved, d_unres),
                                Determined{Vector{Float64}}(set, :cluster_unresolved, d_unres), Determined{Float64}(:cluster_unresolved, d_unres),
                                _route_agreement(rv), coasting, executed)
    end
    # The normal path (design row 1 and row 3): a resolved longitudinal mode; the requested routes run.
    u_s = cand.mode.vector
    tau_s = 2 * cos(cand.mode.tune)
    # The projector route's reference: the longitudinal cluster's spectral projector when the selected mode is its only
    # member; inside a RESOLVED multi-member cluster the cluster's P_c is the group projector of rank 2m, so the reference
    # is the selected mode's own (N5) projector -Im(u u') S (fix batch 2026-10-19, F-176).
    reference = length(c_long.half_members) == 1 ? (is_determined(c_long.projector) ? determined_value(c_long.projector) : nothing) :
                Matrix{Float64}(-imag(u_s * u_s') * _symplectic_form(6))
    rv = DispersionRoute[]; executed = Symbol[]
    for r in DISPERSION_ROUTES
        if !(r in routes)
            push!(rv, _unavailable_route(r, :route_not_selected, "route :$(r) not requested"))
            continue
        end
        push!(executed, r)      # every requested route's kernel runs on this path
        if r === :eigenplane
            push!(rv, _eigenplane_route(Mf, u_s, tau_s; rho_M1=rho_M1))
        elseif r === :polynomial
            push!(rv, _polynomial_route(Mf, tau_s; rho_M1=rho_M1))
        elseif r === :projector
            push!(rv, run_projector(reference))
        elseif r === :newton
            push!(rv, _newton_route(Mf, tau_s; rho_M1=rho_M1, max_iterations=newton_max_iterations))
        else
            push!(rv, _fixed_point_route(Mf, tau_s; rho_M1=rho_M1, max_iterations=fixed_point_max_iterations))
        end
    end
    primary = rv[findfirst(r -> r.route === :eigenplane, rv)]
    return DispersionRoutes(Mf, labels, cand.index, cand.cluster, Determined(tau_s), tunes, cubic, cubic_residual, rv, :eigenplane,
                            primary.graph, primary.zeta, primary.eta, primary.h, _route_agreement(rv), coasting, executed)
end
