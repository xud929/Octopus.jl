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
# form of stage 1's `_graph_invariance_residual`. The digest of Section 8
# (result/twiss_impl_2026_09_11/stage4/digests/theory_sec8_routes.md)
# transcribes every equation in ASCII.
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
fixture; the multiplier 64 sits inside the gap by twelve decades either way.
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
extending `kappa_route` by the coefficient condition is carried (stage 4a
record, "Carried forward", item 3). PROVISIONAL; measured 2026-09-12 (stage
4a record, "Derived windows"): must-accept extreme `sigma_min / (rho_M1
max(1, ||A||_2)) = 1.546e9` (the weak-cavity map's projector trace gap;
its `A_s`, condition 1.1e4, also stays above the floor and is judged by
(I1)); must-reject extremes `0.376` on the `zeta = e_x, eta = e_px` (h = 0)
fixture's polynomial `A_s`, exactly 0 on `diag(R(0.73), R(1.41), R(0.73))`
(coincident selected trace: `A_s` and the trace gap) and on the (D24)
coefficient of the y-shear coasting map. Window by the one-tenth / ten
rule `[3.76, 1.55e8]`; 64 lies inside it. The LAPACK-singular (D15)
operators at ratio 0.012 are outside this guard's reach (see above).
"""
const _COEFFICIENT_CONDITION_MULTIPLIER = 64.0

"""
    _ROUTE_INVARIANCE_MULTIPLIER

`c_inv` of a route's acceptance: a graph whose normalized (I1) residual
exceeds `c_inv * eps * kappa_route` is `:not_invariant` (its graph, zeta,
eta and h are still REPORTED beside the status so a disagreement is
visible), where `kappa_route = max(1, ||M||_F) * max(1, ||D||_F)^2`.
PROVISIONAL; measured: accepted extreme `normalized / (eps kappa_route) =
94` over the 200 dense maps and all five routes (the fixed point's slow
tail sets it; the direct routes stay below 60); rejected extreme `1.9e15` on
the false graph `[diag(1, -0.5); 0]` of theory 13.7 (raw residual `1.5
sqrt(2) sin 0.73`); a Newton iterate one step short of convergence on the
dense maps sits at `>= 1.5e-6` normalized, also rejected.
"""
const _ROUTE_INVARIANCE_MULTIPLIER = 256.0

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
runner-up) and `transverse_margin` (the x-area difference); `tie` when either
margin is at or below `tie_tolerance` (design: ties are declared and leave the
modes unlabelled; a tie keeps the given order and is flagged).

The default rule is a HEURISTIC, not a certification (theory 10.4, 13.5:
"a small tune is not a universal longitudinal-mode identifier", and no
endpoint-map rule is): by (K12) `kappa_sz = h`, the synchrotron mode's z-area
IS `h` and the two betatron z-areas sum to `1 - h`, so for `h <= 1/2` a
betatron mode carries the larger z-area and is selected (the prescribed-h
fixtures with `h = 0.05, 0.5` and every negative `h`). Labelling never feeds
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
`:route_not_selected`) and `detail`; `graph` (4x2, (D7)), `zeta`, `eta`
(4-vectors), `h`, `canonical_area` (`1 + D[:, 1]' S_4 D[:, 2]`), each a
`Determined`; `invariance_residual` (the (I1) graph form, normalized and
raw, available whenever a graph was formed, invariant or not);
`trace_residual` (`tr(M_lr D + M_ll) - tau_s`); `coefficient_condition` (the
2-norm condition of the route's linear solve: `U_ls`, `A_s`, the Sylvester
operator, or the trace separations; unavailable for a route with none, and
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
(the canonical eigenvalue index of the selected oriented longitudinal
member, 0 when none was selected) and `longitudinal_cluster` (its cluster's
position in `clusters.clusters`); `tau_s` (`2 cos mu_s`), `tunes` (the
three oriented tunes in label order when labelled); `trace_cubic_roots` (the
three roots of (D17) from the trace identities) and `trace_cubic_residual`
(their largest distance to a cluster trace `2 cos mu_j`; a diagnostic of the
cubic against the eigenvalues; a `ModeClusters` report without a single
cluster trace is an ArgumentError, never an `Inf`); `routes` in the requested order, one [`DispersionRoute`](@ref)
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
`eta` is unique; `graph` is unavailable with `eta`'s reason otherwise).
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
condition of 8.6. An `ArgumentError` names the singular operator (spectra of
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
    return (D0=Matrix{Float64}(D0), condition=cond(op))
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
`tie` is set when the longitudinal margin or the transverse margin is at or
below `tie_multiplier * eps * kappa_frame`; a tie keeps the given order.
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
    tie = long_margin <= tie_tolerance || trans_margin <= tie_tolerance
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
exactly zero (the mathematical condition is infinite; the dossier forbids an `Inf` standing in for it).
"""
function _condition_number(sigma_max::Real, sigma_min::Real, what::AbstractString)
    sigma_min > 0 && return Determined(Float64(sigma_max) / Float64(sigma_min))
    return Determined{Float64}(:singular_coefficient, "$(what) has smallest singular value (or gap) exactly 0: the condition number is infinite")
end

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
`trace_residual` are always unique; `:graph_isotropic` when `|area| <= _ISOTROPY_MULTIPLIER * rho_M1
* max(1, ||D||_2^2)`; else `(zeta, eta, h)` by (D8); `:not_invariant` when the normalized (I1) residual
exceeds `_ROUTE_INVARIANCE_MULTIPLIER * eps * kappa_route`, `kappa_route = max(1, ||M||_F) * max(1, ||D||_F)^2`
(an iteration that stopped with `converged = false` is judged by the same floor: its graph is `:none` when
the residual is nevertheless within it); in both cases `zeta`, `eta`, `h` are unavailable with the status's reason.
With `check_branch` (the iterative routes) a CONVERGED graph whose `trace_residual` exceeds
`inv_floor * max(1, ||M||_F)` is `:not_invariant` too: it is an invariant plane of another mode (theory 8.6).
"""
function _route_from_graph(route::Symbol, M::AbstractMatrix{<:Real}, D::AbstractMatrix{<:Real}, tau_s::Real; rho_M1::Real,
                           coefficient_condition::Determined{Float64}=Determined{Float64}(:not_derived_for_cluster, "no linear solve in this route"),
                           h_alternative::Determined{Float64}=Determined{Float64}(:not_derived_for_cluster, "no second evaluation of h in this route"),
                           singular_values::Vector{Float64}=Float64[], detail::AbstractString="", iterations::Integer=0,
                           halvings::Integer=0, converged::Bool=true, check_branch::Bool=false)
    Df = Matrix{Float64}(D)
    res = _route_residuals(M, Df, tau_s)
    inv_res = Determined{_ROUTE_RESIDUAL_T}(:unique, res.invariance, nothing, :none, "")
    kappa_route = max(1.0, norm(M)) * max(1.0, norm(Df))^2
    inv_floor = _ROUTE_INVARIANCE_MULTIPLIER * eps(Float64) * kappa_route
    iso_floor = _ISOTROPY_MULTIPLIER * rho_M1 * max(1.0, opnorm(Df)^2)
    common = (Determined(Df), Determined(res.area), inv_res, Determined(res.trace_residual), coefficient_condition, h_alternative,
              singular_values, Int(iterations), Int(halvings), converged)
    if abs(res.area) <= iso_floor
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
    if res.invariance.normalized > inv_floor
        reason = :not_invariant
        d = "normalized (I1) residual $(res.invariance.normalized) exceeds the floor $(inv_floor) (kappa_route = $(kappa_route)); the graph is reported but is not a dispersion" *
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
`coefficient_condition = cond(A_s)` and its singular values reported;
`:singular_coefficient` when `sigma_min(A_s) <= _COEFFICIENT_CONDITION_MULTIPLIER
* rho_M1 * max(1, ||A_s||_2)` ((N16): coincident traces or a singular
projection); otherwise the (D8) conversion and the residuals as in E4.
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
    condition = _condition_number(sv[1], sv[end], "the (D19) coefficient A_s")
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
    _projector_route(M, taus, selected; rho_M1, cluster_projector=nothing) -> DispersionRoute

Dossier E6, theory 8.5 (D26)-(D27): with `Z = M + M^-1` (the symplectic
inverse `_symplectic_inverse`) and the three traces `taus` (the selected one
at index `selected`), `P_s = prod_{k != s} (Z - tau_k I) / (tau_s - tau_k)`
with the repeated betatron factor RETAINED (no division by `tau_1 - tau_2`);
`:singular_coefficient` when any `|tau_s - tau_k|` is at or below
`_COEFFICIENT_CONDITION_MULTIPLIER * rho_M1 * max(1, ||Z||_2)`; the projector
residuals `||P_s^2 - P_s||`, `||M P_s - P_s M||` in `detail`; `h = tr((P_s)_ll)
/ 2` (D27) with `h_alternative` from (D8) of the graph `D = (P_s)_rl / h`;
`:singular_longitudinal_projection` when `|h|` is at or below the graph
floor; then the residuals as in E4.
"""
function _projector_route(M::AbstractMatrix{<:Real}, taus::AbstractVector{<:Real}, selected::Integer; rho_M1::Real,
                          cluster_projector::Union{Nothing,AbstractMatrix{<:Real}}=nothing)
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
                  (cluster_projector === nothing ? "" : ", ||P_s - cluster projector|| $(norm(Ps - cluster_projector))")
    gfloor = _GRAPH_SINGULARITY_MULTIPLIER * rho_M1 * max(1.0, opnorm(Ps))
    if abs(h) <= gfloor
        d = "|h| = tr((P_s)_ll) / 2 = $(abs(h)) at or below the floor $(gfloor): the projector is finite but has no physical graph; " * diag_detail
        return _unavailable_route(:projector, :singular_longitudinal_projection, d; coefficient_condition=condition, singular_values=gaps)
    end
    D = Ps[1:4, 5:6] / h
    h8 = 1 / (1 + dot(D[:, 1], _symplectic_form(4) * D[:, 2]))
    r = _route_from_graph(:projector, Mf, D, tau_s; rho_M1=rho_M1, coefficient_condition=condition, h_alternative=Determined(h8),
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
condition in both cases; a LAPACK-singular (D15) operator returns `D = nothing` with the named detail
(the caller reports `:singular_coefficient`).
"""
function _iteration_start(M::AbstractMatrix{<:Real}, D0, who::AbstractString)
    Mrr = M[1:4, 1:4]; Mll = M[5:6, 5:6]
    op = kron(Matrix{Float64}(I, 2, 2), Mrr) - kron(transpose(Mll), Matrix{Float64}(I, 4, 4))
    condition = cond(op)
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
    start.D === nothing && return _unavailable_route(:newton, :singular_coefficient, start.detail)
    D = start.D
    stop = _ITERATION_STOP_MULTIPLIER * eps(Float64) * max(1.0, norm(Mf))
    F(X) = Mrr * X + Mrl - X * (Mlr * X + Mll)
    current = _graph_invariance_residual(Mf, D).normalized
    iterations = 0; halvings = 0; converged = current <= stop; stalled = false
    condition = Determined(start.condition)
    while !converged && iterations < max_iterations
        Aop = Mrr - D * Mlr; Bop = Mll + Mlr * D
        op = kron(Matrix{Float64}(I, 2, 2), Aop) - kron(transpose(Bop), Matrix{Float64}(I, 4, 4))
        condition = Determined(cond(op))
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
    detail = "Newton from $(start.source) (initializer condition $(start.condition)); final normalized (I1) residual $(current), stop floor $(stop)" *
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
sigma_min(operator)` goes into `detail`), no halving (`halvings = 0`).
"""
function _fixed_point_route(M::AbstractMatrix{<:Real}, tau_s::Real; rho_M1::Real, max_iterations::Integer=50, D0=nothing)
    size(M) == (6, 6) || throw(ArgumentError("_fixed_point_route takes a 6x6 matrix, got $(size(M))"))
    isfinite(tau_s) || throw(ArgumentError("_fixed_point_route: tau_s must be finite, got $(tau_s)"))
    (isfinite(rho_M1) && rho_M1 >= 0) || throw(ArgumentError("_fixed_point_route: rho_M1 must be a non-negative finite number, got $(rho_M1)"))
    max_iterations >= 1 || throw(ArgumentError("_fixed_point_route: max_iterations must be >= 1, got $(max_iterations)"))
    Mf = Matrix{Float64}(M)
    Mrr = Mf[1:4, 1:4]; Mrl = Mf[1:4, 5:6]; Mlr = Mf[5:6, 1:4]; Mll = Mf[5:6, 5:6]
    start = _iteration_start(Mf, D0, "_fixed_point_route")
    start.D === nothing && return _unavailable_route(:fixed_point, :singular_coefficient, start.detail)
    D = start.D
    op = kron(Matrix{Float64}(I, 2, 2), Mrr) - kron(transpose(Mll), Matrix{Float64}(I, 4, 4))
    sigma_min = svdvals(op)[end]
    condition = Determined(start.condition)
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
    detail = "fixed point from $(start.source) (operator condition $(start.condition)); contraction ratio 2 ||M_lr|| ||D|| / sigma_min(op) = $(ratio); " *
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
    _cluster_trace(c) -> Float64

The trace `tau = Re(rho + 1 / rho)` shared by the half members of a cluster (`2 cos mu` on the unit
circle); the projector route's factor `(Z - tau I)` annihilates the cluster's modes for any modulus.
"""
function _cluster_trace(c::ModeCluster)
    isempty(c.eigenvalues) && throw(ArgumentError("_cluster_trace: cluster $(c.members) has no eigenvalues"))
    rho = c.eigenvalues[1]
    return real(rho + 1 / rho)
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
        idx = Int(longitudinal)
        1 <= idx <= length(clusters.eigenvalues) || throw(ArgumentError(
            "_dispersion_routes: longitudinal = $(idx) is not a canonical eigenvalue index in 1:$(length(clusters.eigenvalues))"))
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
and the requested routes run with `rho_M1 = clusters.rho_M1`; a route not
requested is present with `:route_not_selected`. When the longitudinal
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
an empty or repeated `routes` tuple, an unknown route, a bad `longitudinal`.
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
    rho_M1 = clusters.rho_M1
    # Design step 3: the coasting test before any spectral classification (E1, E2).
    coasting = _coasting_structure(Mf; rho_M1=rho_M1)
    # (D17) diagnostics: the cubic roots against every cluster trace.
    cubic = _trace_cubic_roots(Mf)
    cluster_traces = [_cluster_trace(c) for c in clusters.clusters if !isempty(c.eigenvalues)]
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
                                _AGREEMENT_T[], coasting)
    end
    cand = _longitudinal_candidate(clusters, longitudinal)
    c_long = clusters.clusters[cand.cluster]
    # Labels (E3): exactly three resolved modes, else the blocking cluster's reason.
    labels = if length(resolved_modes) == 3
        kf = maximum((is_determined(c.kappa_frame) ? determined_value(c.kappa_frame) : 1.0) for c in clusters.clusters)
        li = (longitudinal === nothing || cand.mode === nothing) ? nothing : findfirst(m -> m.index == cand.mode.index, resolved_modes)
        lb = _mode_labels_6d([m.vector for m in resolved_modes], resolved_tunes; longitudinal=li, kappa_frame=max(1.0, kf))
        d_lb = lb.rule === :explicit ? "longitudinal mode named by the caller (canonical index $(cand.index)); the transverse labels by the x-area rule are a heuristic" :
            "uncertified heuristic: the longitudinal mode is the largest signed z-area, but by (K12) kappa_sz = h a betatron mode carries more z-area when h < 1/2 (theory 10.4, 13.5); an explicit `longitudinal` index certifies the selection"
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
    # The three traces for the projector route: every cluster's trace repeated by its half multiplicity
    # (a definite unresolved betatron pair contributes the same trace twice, the repeated factor retained).
    # A single multiple cluster (an unresolved or defective pair) gets its common trace from the trace identity
    # tr M = sum_j tau_j instead of its computed eigenvalues (a defective eigenvalue is only sqrt(eps) accurate;
    # tr M and the resolved singletons' traces are eps accurate, so the retained repeated factor stays exact).
    cluster_tau = [isempty(c.eigenvalues) ? NaN : _cluster_trace(c) for c in clusters.clusters]
    multiples = [ci for (ci, c) in enumerate(clusters.clusters) if length(c.half_members) >= 2]
    if length(multiples) == 1 && all(!isnan, cluster_tau) && sum(length(c.half_members) for c in clusters.clusters) == 3
        mi = multiples[1]
        others = sum(cluster_tau[ci] for ci in eachindex(clusters.clusters) if ci != mi; init=0.0)
        cluster_tau[mi] = (tr(Mf) - others) / length(clusters.clusters[mi].half_members)
    end
    taus = Float64[]; tau_positions = Int[]
    for (ci, c) in enumerate(clusters.clusters)
        isnan(cluster_tau[ci]) && continue
        for _ in 1:length(c.half_members)
            push!(taus, cluster_tau[ci]); push!(tau_positions, ci)
        end
    end
    selected_tau = findfirst(==(cand.cluster), tau_positions)
    # The projector route needs exactly three traces (one per oriented mode); a real-class (unstable or
    # unit-eigenvalue) cluster breaks the count and the route is unavailable with that cluster's reason.
    projector_blocker = (length(taus) == 3 && selected_tau !== nothing) ? nothing :
        begin
            bc = findfirst(c -> c.reason !== :none && c.classification !== :definite, clusters.clusters)
            bc === nothing ? (:singular_coefficient, "the projector route needs three mode traces, found $(length(taus))") :
                (clusters.clusters[bc].reason, "the projector route needs three mode traces, found $(length(taus)): cluster $(clusters.clusters[bc].members) is $(clusters.clusters[bc].classification)")
        end
    run_projector(cp) = projector_blocker === nothing ? _projector_route(Mf, taus, selected_tau; rho_M1=rho_M1, cluster_projector=cp) :
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
                                _AGREEMENT_T[], coasting)
    end
    tau_s = cluster_tau[cand.cluster]
    if cand.mode === nothing
        # Definite UNRESOLVED longitudinal cluster (theory 13.5-13.6, design rows 2 and 4): eta is the ambiguity set;
        # the two algebraic routes run with the common trace and land in :singular_coefficient by (N16).
        d_unres = "the longitudinal candidate cluster $(c_long.members) is definite but unresolved (multiplicity $(length(c_long.half_members))): the dispersion is an ambiguity set, not a vector"
        rv = DispersionRoute[]
        for r in DISPERSION_ROUTES
            if !(r in routes)
                push!(rv, _unavailable_route(r, :route_not_selected, "route :$(r) not requested"))
            elseif r === :polynomial
                push!(rv, _polynomial_route(Mf, tau_s; rho_M1=rho_M1))
            elseif r === :projector
                push!(rv, run_projector(is_determined(c_long.projector) ? determined_value(c_long.projector) : nothing))
            else
                push!(rv, _unavailable_route(r, :cluster_unresolved, d_unres))
            end
        end
        set = _dispersion_ambiguity_set(c_long)
        return DispersionRoutes(Mf, labels, 0, cand.cluster, Determined(tau_s), tunes, cubic, cubic_residual, rv, :eigenplane,
                                Determined{Matrix{Float64}}(:cluster_unresolved, d_unres), Determined{Vector{Float64}}(:cluster_unresolved, d_unres),
                                Determined{Vector{Float64}}(set, :cluster_unresolved, d_unres), Determined{Float64}(:cluster_unresolved, d_unres),
                                _route_agreement(rv), coasting)
    end
    # The normal path (design row 1 and row 3): a resolved longitudinal mode; the requested routes run.
    u_s = cand.mode.vector
    tau_s = 2 * cos(cand.mode.tune)
    rv = DispersionRoute[]
    for r in DISPERSION_ROUTES
        if !(r in routes)
            push!(rv, _unavailable_route(r, :route_not_selected, "route :$(r) not requested"))
        elseif r === :eigenplane
            push!(rv, _eigenplane_route(Mf, u_s, tau_s; rho_M1=rho_M1))
        elseif r === :polynomial
            push!(rv, _polynomial_route(Mf, tau_s; rho_M1=rho_M1))
        elseif r === :projector
            push!(rv, run_projector(is_determined(c_long.projector) ? determined_value(c_long.projector) : nothing))
        elseif r === :newton
            push!(rv, _newton_route(Mf, tau_s; rho_M1=rho_M1, max_iterations=newton_max_iterations))
        else
            push!(rv, _fixed_point_route(Mf, tau_s; rho_M1=rho_M1, max_iterations=fixed_point_max_iterations))
        end
    end
    primary = rv[findfirst(r -> r.route === :eigenplane, rv)]
    return DispersionRoutes(Mf, labels, cand.index, cand.cluster, Determined(tau_s), tunes, cubic, cubic_residual, rv, :eigenplane,
                            primary.graph, primary.zeta, primary.eta, primary.h, _route_agreement(rv), coasting)
end
