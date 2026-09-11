# The first analysis: coupled Twiss and canonical dispersion from a one-turn matrix

**Status: decided 2026-09-11 (design review, three judged designs, four
adversarial verifications; the owner adopted every recommendation); not
implemented.** No type, function, option, contract, or keyword named in this
note exists in the source yet: `src/analysis/` still holds only
`PlaceholderAnalysis`, and there is no analysis execution API. This note
records which architecture was chosen and why. The mathematics it builds on is
[the theory note](../theory/twiss_dispersion.md), Sections 1–13; the
degeneracy theory of its Section 13 and the reproducible checks behind it are
in [the degeneracy-theory record](../history/twiss_dispersion_degeneracy_theory_2026_09_11.md).
When implementation lands, the landing record and the todo row will say so;
this paragraph is the only place that should be updated to reflect it.

## The problem

The theory note derives three things an optics analysis must produce from a
real symplectic one-turn matrix: the normal-mode basis and tunes, the
Edwards–Teng and Mais–Ripken parameterizations of the transverse block, and
the canonical crab and momentum dispersion of the longitudinal mode together
with the canonical separation of betatron and synchrotron motion. It also
derives, in Section 13, what a conventional periodic Twiss initializer gets
wrong: when two normal modes share an eigenvalue pair, the individual modes are
not determined by the map, a coupled-optics formula whose denominator is the
mode separation returns a finite wrong answer, and MAD-X reports a perfectly
stable rolled FODO cell as unstable. Octopus has none of this yet. It has the
forward construction (the optics form of `Linear6DSpec` builds a one-turn
matrix from Twiss, coupling, and dispersion parameters), three duplicated
complex-step Jacobian closures in tests and a validation script, no
closed-orbit finder, and an analysis layer with one placeholder type.

The decisions below have to satisfy the repository's own rules at the same
time: a check only counts while it executes; a configuration the code did not
read is a defect; every public option lands with its consumer, metadata,
invalid and inactive behaviour, and an effectiveness test; loud beats silent;
derive lists, do not hand-copy them; and never return a plausible number where
the physics does not determine one.

## The decision

**One non-parametric analysis object, one execution verb, six pure-math files,
a cluster-first pipeline.** The analysis consumes a real symplectic 4×4 or 6×6
matrix in `(x, px, y, py, z, pz)` order with Octopus's `(s − ℓ, δ)`
longitudinal pair, and returns the coupled normal-mode optics, the canonical
dispersion, and a diagnostic record covering every bullet of theory
Section 11.2 except the scan bullet. It does not track, scan, or transport.

### Scope of the first landing

| Area | First landing | Deferred, and why |
|---|---|---|
| Dimension | 4×4 (Section 3 directly) and 6×6 bunched maps, both real symplectic (C3). | Damped or diffusive maps: the theory excludes non-Hamiltonian maps. |
| Input | A matrix; or a one-turn Jacobian of a compiled line by complex step (default) or central finite difference; ForwardDiff only through the package extension. Symplectic defect, reciprocal canonical scaling, closed-orbit assumption with a recorded residual (11.1 steps 1–3). | A closed-orbit finder: none exists in the repo; benchmark 12.2-3 uses a test-local Newton solve. |
| 4D | Eigenvector route primary (E1–E9); closed forms (E10–E14) as a cross-check guarded against coincident traces; complete Mais–Ripken set (M1–M8); both Edwards–Teng forms (T2–T17, B2–B11); covariance identities (M9–M16). | Nothing. |
| Degeneracy | Coasting test first; clusters from complex-eigenvalue gaps; Gram and Krein classification with the minimal-polynomial residual in the rule; collective normalization; group projector and covariance; signed basis for certified indefinite groups; individual-mode recovery when the restricted map resolves; the dispersion ambiguity set (Section 13). | Selection by continuation data (13.8, "additional information"): needs scans. |
| 6D dispersion | Eigenplane route (D10)/(D12) primary; polynomial (D19), projector (D26)–(D27), Newton (D21), and fixed-point (D20) routes as cross-checks, every route accepted only on the (I1) residual; coasting branch (D24) when the (D23) structure is detected. | The scan predictor (D28)–(D29): needs a parameter-scan API. |
| Canonical separation | (D3), (K2)–(K5), (K7); the 4D pipeline on the barred betatron block; full normalizer (K9); signed-area array with the (K12) sums; (K13). | Nothing. |
| Covariance | Matched Σ from user emittances (K10)/(K12); Σ_c = ε G_c for a definite group with equal emittances (N8). | Selection of modes by a supplied covariance: needs a matched-beam input contract. |
| Transport | Deferred: (F1)–(F6), (P1)–(P6), 11.1 step 7. The result type exposes U₆, the graph, the form, and the labels so a later stage consumes them without a type change. | Needs per-section Jacobians and a phase-unwrapping policy. |
| Ohmi | (O2)–(O5) as a pure function plus identity test, h > 0 only. | Nothing. |
| Xsuite | Out: (X2) after longitudinal conversion needs the Jacobian of `convert_longitudinal` and an external reference. | Benchmark 12.2-7, second half. |

Benchmarks of theory Section 12.2 covered by the first landing: 1, 2 (except
the transport form switch), 3, 4, 5, 6, and 9; 7 for Ohmi only; 8 open.

The eigenvector route is primary because the theory names it so (Section 1) and
because the degeneracy machinery is itself an eigenbasis construction; every
other route is a cross-check whose disagreement is reported, never averaged.
Every route, primary included, is accepted only if its normalized invariance
residual (I1) is below tolerance. A small polynomial residual or a small Newton
update is never sufficient (Sections 8.6 and 13.7).

### Input boundary

Three entry forms, all resolving to one 4×4 or 6×6 matrix plus a provenance
record.

1. A bare matrix. Finite entries, canonical coordinates only; slopes are not
   accepted. A bare matrix carries no closed-orbit information, so the
   closed-orbit residual is recorded as missing and the reference point as
   supplied by the caller.
2. A linearized map produced by a one-turn-matrix helper from any callable
   `(x,px,y,py,z,pz) → 6-tuple`: a compiled line, a tuple of compiled runtime
   elements folded in order, or any element spec compiled through
   `compile_runtime`. The provenance records the source, the method, the step,
   the expansion point, and a map-uncertainty estimate. The helper replaces the
   three identical complex-step closures now in `validation/lattice_cells.jl`
   and two suite tests, so the Jacobian rule lives in one place.
3. The linearization method is a core tag type dispatched through one internal
   function:
   - complex step (default): perturb each coordinate by `1e-30im` and read the
     imaginary part, exact to roundoff, the pattern the repo already uses;
   - central finite difference with `h = step·max(|q_j|, 1)` and the default
     step of the symplecticity contract, truncation of order `step²` and a
     declared map uncertainty of `step²·‖M‖`;
   - ForwardDiff: core defines the tag and a fallback that throws a directed
     error naming both activation routes; the extension **adds** a method on
     the tag, never redefines a core method; the body lives in the shared rules
     file so package mode and script mode share one implementation. Core never
     imports ForwardDiff.
   Elements that cannot be differentiated by the chosen method (apertures and
   strong-beam evaluators under complex step, the solenoid under complex step)
   raise a directed error naming the alternatives. The original error is
   rethrown unchanged unless its argument types involve a complex number, so an
   unrelated bug in a user map is never relabelled as a differentiation
   limitation.
4. Closed orbit. The first landing **assumes** the expansion point (default the
   origin) is a fixed point. It evaluates the fixed-point residual of the map in
   scaled coordinates, records it, and under the default mode throws when the
   residual exceeds its tolerance; a warning mode emits one rate-limited
   warning and marks the result degraded. The closed-orbit options are inactive
   on a bare matrix and say so in the configuration report.
5. Scaling. A reciprocal canonical scaling `C = diag(a₁, 1/a₁, a₂, 1/a₂, a₃, 1/a₃)`
   satisfies `CᵀSC = S` exactly, so the scaled matrix is symplectic with respect
   to the unchanged form (Section 2). The default factors balance the row norms
   of each position and momentum pair; a tuple of explicit factors must have
   length `d/2`. Every residual and tolerance is evaluated on the scaled matrix
   (Section 11.2); physical quantities are transformed back by the table below,
   which a scaling-invariance test pins row by row.

| Scaled | Physical |
|---|---|
| U₆ | C⁻¹ Ũ₆ |
| Σ | C⁻¹ Σ̃ C⁻ᵀ |
| P_j | C⁻¹ P̃_j C |
| G_j | C⁻¹ G̃_j C⁻ᵀ |
| graph 𝒟 | C_r⁻¹ 𝒟̃ C_ℓ |
| ζ | a₃ C_r⁻¹ ζ̃ |
| η | C_r⁻¹ η̃ / a₃ |
| h | unchanged (det C_ℓ = 1) |
| tunes, traces, det R, λ, κ | unchanged |
| Edwards–Teng R | diag(a₂, 1/a₂)⁻¹ R̃ diag(a₁, 1/a₁) |
| β_ja, α_ja, γ_ja | β̃_ja / a_a², α̃_ja, γ̃_ja a_a² |
| residuals | reported in scaled coordinates, never transformed back |

Rejected: a non-reciprocal scaling, which changes the represented symplectic
form and would have to be tested against `C S Cᵀ` rather than `S`.

### Types and availability

The analysis object is a non-parametric `Base.@kwdef` struct subtyping
`AbstractAnalysis` and carrying options only. Non-parametric is forced by the
repo: element metadata and `TrackingTask` store analyses as
`Vector{DataType}`, which a parametric type cannot enter. Its options and
their defaults:

| Option | Default | Meaning |
|---|---|---|
| scaling | `:auto` | reciprocal canonical scaling; `:none`; or explicit per-plane factors |
| symplectic_rtol | `nothing` | `nothing` means the roundoff-derived default for exact provenance; a finite-difference input **requires** an explicit value, else an argument error |
| nonsymplectic | `:error` | or `:flag`; never a repair |
| closed_orbit, closed_orbit_atol | `:require`, roundoff-derived | inactive on a bare matrix |
| map_uncertainty | `0.0` | user-declared map error, folded into ρ_M |
| resolution_chord | `1e-4`, provisional | see the resolution criterion |
| clusters | `:auto` | or an explicit partition of oriented-eigenvalue indices |
| longitudinal_mode | maximum signed longitudinal area | or an explicit mode index |
| preferred_form | `:auto` | Edwards–Teng form 1 or 2 |
| dispersion_routes | eigenplane, polynomial, projector, newton, fixed_point | eigenplane is always primary |
| newton_max_iterations | 50 | inactive unless a Newton route is selected |
| emittances | `nothing` | rms mode emittances for the matched covariance |
| strict | `true` | residual failure throws an error that carries the result |

The `nothing` sentinel on `symplectic_rtol` is deliberate: with a plain
floating default, an explicitly supplied value is indistinguishable from the
default, so "required for finite-difference input" could not be enforced.

Every quantity that the physics may leave undetermined is wrapped in an
availability type with a pinned status vocabulary, unique, ambiguous set, or
unavailable, and a pinned reason vocabulary: none, cluster unresolved,
indefinite cluster, unresolved (possibly defective), singular longitudinal
projection, unstable spectrum, unit eigenvalue, coasting structure, form
inadmissible, zero projection, singular coefficient, not invariant, not
derived for a cluster, not requested, route not selected, graph isotropic. The
last is the reviewer-found case of a finite graph whose canonical area
`1 + 𝒟₁ᵀS₄𝒟₂` vanishes, distinct from a singular projection. Accessing the
value of a non-unique quantity throws with the reason. No field is ever a NaN
standing in for "unknown".

The result is a tree of named structs, no anonymous tuples in the public
surface: spectrum report; mode clusters (members, eigenvalues, classification,
Gram eigenvalues and Krein signs, Schur basis, normalized frame or signed
basis, projector, covariance or nothing, restricted map, three residuals,
resolved and forced flags); normal modes (oriented eigenvalue, phase, tune,
complex vector, real pair, projector, covariance, per-plane projected Twiss
with signed κ, eigenvector residual); dispersion routes (graph, ζ, η, h, the
normalized and the raw invariance residual, trace residual, coefficient
condition, iteration count, canonical area) with a primary route, the checks,
the ambiguity set, and a route-agreement matrix; canonical separation; the
transverse optics (normalizer, phases, the Mais–Ripken set with both
evaluations of u and the phase-validity flags, both Edwards–Teng forms with
admissibility, the closed-form check); covariance; Ohmi factor; the scaling
record; and the diagnostics record with one field group per bullet of theory
Section 11.2. The ambiguity set carries the center, the shape matrix, its
factor, the multiplicity, and whether it is an exact set or an orientation
envelope. An ambiguity set is never formed for multiplicity one, and the
scalar-interval accessor refuses it, since a single mode has a unique
dispersion (Section 13.6); for an orientation envelope the interval endpoints
are containing, not sharp, and the docstring says so. The error thrown under
strict mode is `OpticsAnalysisError`, carrying the full result, and is listed
in the public API map. Result structs are documented as runtime representation
that may change; the analysis object and its option schema are the stable
surface.

### Execution API and option certification

One exported verb, `analyze`, dispatching on the analysis object and the input
form, plus `one_turn_matrix`, `matched_covariance`, `dispersion_interval`, a
mode accessor, the two availability predicates, the option schema, and the
configuration report. Generic names such as `value` and `mode` are not
exported. Every export carries a docstring; the registry discovers the type by
reflection, so `description` is defined and the snapshot is regenerated.

Discovery. The analysis is declared in the `analyses = [...]` field of every
element kind whose tracking methods contain `Symplectic6DMap` and do not
contain `NonSymplectic6DMap`, plus `:line`. That rule is the exact-identity
rule the symplecticity contract already uses. It yields 22 kinds today and
excludes the aperture and both Lorentz boosts by construction; a substring
match would count 27 because `Symplectic6DMap` is a substring of
`NonSymplectic6DMap`. Two tripwires assert the declared set equals the derived
set in both directions and that the analysis is never declared beside the
non-symplectic method. The five kinds declaring only the non-symplectic method (the
aperture, both Lorentz boosts, the patch, and the thin accelerating cavity)
keep `PlaceholderAnalysis`, so the guide text that "every element registers
the placeholder" becomes a statement about a mixed state. The element-metadata
validator already asserts that every declared analysis is an `AbstractAnalysis`
subtype; the two tripwires add the set equalities. On a single element the
result is still honest: a drift lands in the coasting branch with η
unavailable for a singular coefficient, a quadrupole in the unstable-spectrum
branch. `TrackingTask` already collects declared analyses; it does not execute
them, and this landing does not change that.

Certification. Every option has structured metadata with a real consumer, and
that consumer records a receipt in the executing branch with the backend type
(`CPUThreadsBackend`) and a named tuple of what it actually read, through the
execution-audit instrument the repo already uses for policies and solvers. The
named-tuple fields are fixed per consumer so the effectiveness probe can assert
them: scaling `(mode, factors)`; symplectic check `(rtol, defect, action)`;
closed orbit `(mode, atol, residual)`; cluster resolution
`(chord, rho_M0, rho_M1, user_clusters, forced)`; labels
`(rule, selected, weights)`; Edwards–Teng `(requested, reported, admissible)`;
dispersion routes `(requested, executed)`; Newton `(max_iterations, used)`;
covariance `(emittances,)`; strictness `(strict, outcome)`. The configuration
report lists every option with a status from the existing vocabulary, and
inactivity is a predicate on the branch actually taken, not a static rule:
closed-orbit options are inactive on a bare matrix; the Newton iteration cap is
inactive when no Newton route is selected and on any 4×4 input; the
longitudinal-mode rule is inactive on 4×4 input and on a coasting map; the
form preference and the route list are inactive when the transverse optics or
the dispersion are unavailable; an explicit partition makes the resolution
chord inactive. Duplicate or empty route tuples and an emittance tuple of the
wrong length are argument errors. The metadata validator gets a block for the
analysis and a tree guard over `AbstractAnalysis` so a second analysis without
a block fails, and a tripwire derives the set of exported option schemas and
asserts each has an effectiveness probe table. The effectiveness contract runs
`analyze` under an execution audit and asserts, per option, the receipts from
the named consumer with the alternative value, the observable change where the
option's category demands one, and the inactive status where declared.

Throw versus status. Argument errors at the boundary: wrong size, non-finite
entries, unknown option symbols, a partition that is not one, a scaling tuple
of wrong length, finite-difference provenance without an explicit symplectic
tolerance, a map the chosen method cannot differentiate, a non-symplectic
matrix under the error mode, a closed-orbit defect under the require mode.
Physically undetermined quantities are statuses with reasons, never numbers.
Residual or classification failures throw an error carrying the full result
under strict mode, and return a failed status otherwise; both branches have
fixtures.

### Pipeline

All norms are Frobenius for matrices and infinity for vectors, evaluated on the
scaled matrix. Every threshold below is provisional policy until the
measurement protocol of the next subsection has run.

1. **Scale and symplectic defect** (11.1 steps 2–3). Compute the defect
   `‖MᵀSM − S‖_F / max(1, ‖M‖_F²)` and the row-scaled ratio of the existing
   Linear6D validator, by embedding a 4×4 input as `diag(M₄, I₂)`. Accept, or
   throw, or flag and mark degraded. Never symplectify.
2. **First perturbation scale**, before anything consumes it:
   `ρ_M0 = max(defect·‖M‖_F, d·ε·‖M‖₂, user uncertainty, provenance uncertainty)`.
3. **Coasting test** (D23), before any spectral classification, because a
   coasting map's unit-eigenvalue pair has real eigenvectors that a Krein test
   would misread as defective. The structure test uses a roundoff-scale
   tolerance and reports its margin. If it holds: ζ = 0, h = 1, η from (D24) by
   a linear solve with a singular-coefficient status when `I − M_rr` is
   ill-conditioned, the shear (D25), and the transverse optics of `M_rr`, which
   is symplectic by (K8) under (D23). A weak-cavity ring must not take this
   branch; a fixture with a `1e-6` cavity term takes the bunched path with a
   unit-eigenvalue flag.
4. **Clusters on the unoriented spectrum.** The gap between two eigenvalues is
   the smaller of the distance to the partner and the distance to its
   conjugate, since equal traces can mean `μ_j = −μ_k`. Clusters are the
   connected components of the unresolved relation, closed under conjugation; a
   self-conjugate cluster means an eigenvalue at ±1 and is flagged.
5. **Gram, classification, normalization** (13.8). Ordered complex Schur on one
   member of each conjugate pair gives the half-cluster basis; the Gram matrix
   (N2) is formed on it, and its inertia decides the orientation of the whole
   cluster. A negative-definite Gram selects the conjugate half. The second
   perturbation scale adds the Schur backward error:
   `ρ_M1 = max(ρ_M0, ‖MQ − QT‖_F)`. For a single conjugate pair the Gram test
   is exactly (E4): a one-by-one Gram is the sign of `Im(v†Sv)`. Rule, applied
   only when the invariant-subspace residual is itself below its tolerance
   (else the cluster is unresolved): all Gram eigenvalues above the
   floor gives definite, with the frame (N20), the checks of (N4), and the
   group quantities (N5); mixed signs above the floor **and** a minimal-polynomial
   residual (N19) below its tolerance gives indefinite, with the signed basis
   whose conjugated columns carry their conjugate eigenvalue and branch and no
   covariance; anything else is unresolved with a stated sub-reason, and the
   word defective is never asserted. For a non-definite cluster the projector
   is taken from the Schur spectral projector rather than from (N5).
6. **Stability, per cluster.** The unit-modulus test is evaluated on the
   cluster's Schur block, not on raw eigenvalues: eigenvalues of a defective or
   near-defective block leave the unit circle by the square root of the
   perturbation, so a raw test would call a bounded degenerate map unstable
   (Section 13.9). Only a cluster whose whole block leaves the circle is
   flagged unstable, and then all modal outputs of that cluster are unavailable
   for that reason. The `diag(2, 1/2, ℛ(1.2))` counterexample of Section 4.4
   lands here.
7. **Mode recovery** (N21). The restricted map is diagonalized and the frame
   rotated only when its internal eigenvalues satisfy the same resolution
   criterion; a cluster resolved here leaves the ambiguity row and returns
   unique per-mode values with their eigenvector residuals, normalized in the
   (I1) form `‖MU − UR(μ)‖ / max(1, ‖MU‖, ‖U‖)`.
8. **Labels** (K12, 10.4). Signed areas `κ_ja = −Im(u_ja* u_j,pa)`; the row
   and column sums of the signed array are checked; labels by maximum-weight
   assignment on the signed array; the longitudinal mode by maximum signed
   longitudinal area, or by explicit index. Ties are declared with their own
   tolerance and leave the modes unlabelled. Labelling is a heuristic recorded
   in the diagnostics; it never feeds a Twiss value.
9. **Dispersion.** Primary eigenplane route: graph by (D10) with a linear solve,
   `h = det U_ℓs`, ζ and η by (D12); graph regular iff the smallest scaled
   singular value of `U_ℓs` exceeds the floor, else singular projection with
   the full mode retained. Cross-check routes: polynomial (D19) with the
   coefficient condition and a singular-coefficient status near coincident
   traces (N16); projector (D26)–(D27) with the repeated betatron factor
   retained; Newton from the Sylvester initializer, with Julia's convention
   `sylvester(A, B, C)` solving `AX + XB + C = 0`, so (D15) is
   `sylvester(M_rr, −M_ℓℓ, M_rℓ)` and the (D21) correction step is
   `sylvester(M_rr − 𝒟M_ℓr, −(M_ℓℓ + M_ℓr𝒟), F(𝒟))`, halving on residual
   increase; fixed point (D20) from the same initializer. Cross-check routes
   convert their graph to ζ, η, h by (D8). Every route stores the normalized
   (I1) residual, the raw residual, the trace difference, and the canonical
   area; (I1) above tolerance means not invariant, a vanishing canonical area
   means graph isotropic.
10. **Separation** (D3), (K2), (K4), (K5), (K7); the Ohmi factor when h > 0;
    the 4D pipeline (E1–E8) on the barred betatron block with its
    reconstruction residual; the closed-form check (E10–E14) skipped with a
    stated reason at coincident traces.
11. **Mais–Ripken and Edwards–Teng** (M1–M6; B10 by linear solves; B5/B9;
    T11; T15/T16; T5 reconstruction; T9 as a benchmark at well-conditioned
    points). The phase fix applies only to nonzero position components;
    admissibility of a form is `1 + det R > 0` of the reported form together
    with its positive area weight, never the sign of det R alone. Covariance
    (K10)/(K12) when emittances are given; `Σ_c = ε G_c` only for equal
    emittances within a cluster.

What is returned in each case:

| Case | Returned | Unavailable, with reason |
|---|---|---|
| All modes resolved | every quantity unique; primary route, checks, agreement matrix | none |
| Definite cluster containing the longitudinal candidate | P_c, G_c, the frame; η as an ambiguity set with center and shape (N11), scalar intervals (N14), exact-set or envelope kind | ζ, h, graph, separation, transverse optics; per-member quantities |
| Definite betatron cluster, longitudinal pair isolated | dispersion unique; G_c; Σ_c for equal emittances | per-mode transverse optics of the cluster |
| Indefinite cluster | projector, signed basis, Krein signs; status degraded | all modal quantities of the cluster |
| Unresolved cluster | projector, minimal-polynomial residual, sub-reason | all modal outputs of the cluster |
| Singular longitudinal projection | the mode's complex vector, real pair, projector, covariance, tunes, (K12) projections | graph, ζ, η, h, separation, Edwards–Teng |
| Non-symplectic input | throws, or a degraded result with the defect | — |
| Coasting map | η, ζ = 0, h = 1, the shear, the transverse optics of M_rr | the synchrotron mode |

### Resolution criterion

The criterion decides whether the analysis names individual modes or reports
the cluster they belong to. It uses three quantities, all on the scaled
matrix: the complex-eigenvalue gap `g = min(|ρ_j − ρ_k|, |ρ_j − ρ̄_k|)`, the
map perturbation scale `ρ_M1` above, and the normalizer conditioning
`κ = ‖U‖₂²` computed from the Gram-normalized cluster frame (for a definite
split cluster the individually normalized eigenvectors are already
Krein-orthogonal, so κ stays bounded there and only `ρ_M / g` grows; κ blows up
only on the indefinite approach, which the classification step catches). The
finite-resolution chord of theory (N22),

    q = min(2, 2·κ·ρ_M1 / g)

is the largest rotation of the mode orientation that the map's own error can
produce. A pair is resolved iff `q ≤ resolution_chord`. No floating-point
equality and no fixed tune threshold appear anywhere (Section 13.8): the same
tune split is resolved for a complex-step matrix and unresolved for a
finite-difference one, which is the physically correct answer.

**Default value.** The default is policy, not physics, and the theory note gives
none. It is provisional at `1e-4` and frozen from a measured bracket before it
ships. The bracket comes from the detuned rolled FODO of theory Section 13.10,
`K_1D = −(1 + ε)`, whose complex gaps are `2.13×10⁻⁹` at `ε = 10⁻⁹` and
`2.13×10⁻¹²` at `ε = 10⁻¹²` with `‖M‖₂ = 2.98`; with a roundoff-level
`ρ_M ≈ 2.6×10⁻¹⁵` the chords at unit κ are `2.5×10⁻⁶` and `2.5×10⁻³`. The
working notes report a periodic tune error of `4.45×10⁻⁹` in the first case
and `5.89×10⁻⁶` in the second, so the first must resolve and the second must
not. The geometric mean of the two chords is `7.9×10⁻⁵`, which rounds to
`1e-4`. An earlier draft's `1e-6` would have declared the first pair unresolved
at unit κ and contradicted its own test. Before the value is frozen, the
landing record tabulates κ, `ρ_M0`, `ρ_M1`, g, and q for the exact FODO, its
four detuned controls, the isospectral family of the working notes at
`ε = 10⁻⁹`, the dense oracle maps of the canonical-dispersion note, and the
crab map of that note's collision trial near its critical strength; the
default is set at the geometric mean between the largest q of a control that
must resolve and the smallest q of one that must not, rounded to one digit,
and that arithmetic travels with the tolerance. If the bracket does not contain
`1e-4`, the measured value wins and this paragraph records the change.

The same `ρ_M1` drives the Gram floor, the graph-singularity ratio, the
coincident-trace guards, the minimal-polynomial tolerance, and the exact-set
versus envelope kind of an ambiguity set; each multiplier is measured on the
same fixtures with the rule that the largest residual-to-threshold ratio on an
accepted fixture stays below one tenth and the smallest on a rejected fixture
exceeds ten.

Overrides: an explicit chord (`Inf` forces resolution and marks the cluster
forced and the result degraded), an explicit cluster partition, and a declared
map uncertainty. Reporting: both gaps, the chord matrix, every component of
`ρ_M`, both κ estimates, the degeneracy status, the per-cluster resolved and
forced flags, and the resolution receipt with the decision actually taken.

Rejected alternative: shipping no default and making the chord a required
argument. It would break the one-line matrix-in, result-out call this note
adopts as the entry form, and it buys nothing the diagnostics do not already
show.

### Verification plan

Tolerances are stated per test in scaled coordinates as `c·ε·κ` with `c`
measured and floored; physical-unit pins are compared after
back-transformation. Manufactured normalizers are `exp(S₆H)` with symmetric H,
seed 20260911. Two-route tests assert each arm's route; every tripwire is shown
red on an injected defect. Fixtures and what each catches:

| Fixture | Check | Catches |
|---|---|---|
| any map, three scalings | every back-transformation row equal | a wrong h, ζ/a₃, or a₃η rule |
| cross-plane shear `M[1,3] = 0.3` | argument error; flag mode records the defect; FD input without a tolerance is an error | silent acceptance |
| `diag(2, 1/2, ℛ(1.2))` | unstable spectrum, no Twiss | acceptance on (T14) alone |
| `ℛ(2π·0.7)` | tune 0.7, oriented member by `Im(v†Sv) < 0` | tune-branch loss |
| random blocks | `sylvester` initializer satisfies (D15); a Newton step satisfies (D22) | the Julia/SciPy sign flip |
| uncoupled FODO of `validation/lattice_cells.jl` | β, α equal its `twiss()`; μ equals `acos(tr/2)` on the (E5) branch; κ_1y = κ_2x = 0; R = 0 | benchmark 12.2-1 |
| `Linear6DSpec` optics form conjugated by `XYCouplingSpec` mode A or B | R, λ, β_j, α_j, μ_j recovered; admissibility keyed on the constructing form via `1 + det R > 0` and the area weights; `det R ∈ (−0.5, 0, 0.3, 1)` | benchmark 12.2-2 |
| `Linear6DSpec` with ζ, η, C, and the same map as a line of the three linear-map elements | ζ, η, h, C recovered; line equals matrix | the line-versus-matrix boundary |
| the canonical-dispersion note's oracle: 24 dense, 7 prescribed-h, 3 coasting maps | all routes agree to its tolerance `2e-10`; a poorly conditioned Sylvester case reports its condition | benchmarks 12.2-6 and 12.2-9 |
| rolled equal-tune FODO, analytic rebuild pinned to the exported map | definite cluster, tune `0.0360896443733161`, Gram minimum `0.0838222432933016`, projector `I₄`, not unstable; detuned `10⁻³, 10⁻⁶, 10⁻⁹` resolved, `10⁻¹²` unresolved | the TWCPIN false instability; the chord default |
| `diag(ℛ(0.73), ℛ(1.41), ℛ(0.73))` | center 0, shape `diag(1/4, 1/4, 0, 0)`, interval on `e_x` is `(−0.5, 0.5)`; the isospectral family at `10⁻⁹` splitting gives an envelope containing each member's η | convention drift, midpoint reported as dispersion |
| false graph `[diag(1, −0.5); 0]` on that map; crab similarity `k = 0.3` | raw residual `1.5√2 sin 0.73`, normalized residual stated with its divisor, status not invariant; pseudoinverse graph rejected with raw residual `0.28293` | polynomial-kernel acceptance |
| `diag(ℛ(μ), ℛ(γ), ℛ(−μ))`; near-collision `diag(ℛ(μ), ℛ(γ), ℛ(−μ − 10⁻⁹))`; defective spectator | indefinite with signed basis and no covariance; never two definite modes; unresolved with the minimal-polynomial sub-reason while the isolated longitudinal mode stays unique | dropped Krein signs, per-vector orientation |
| `ζ = e_x, η = e_px` (h = 0); isotropic graph `diag(1, −1)` | singular projection with the mode retained; graph isotropic | a division by h |
| FODO plus RF and a thin crab cavity with `strengthX = −k` | routes agree, ζ ≠ 0 | benchmark 12.2-4 and the kernel sign |
| coasting DBA cell | η against a central difference of the closed orbit at `δ = ±10⁻⁴` from a test-local Newton solve | benchmark 12.2-3 |
| (K10) covariance | closes under the map; entries equal (M10)–(M16); signed (K12) sums are one; (K14) | benchmark 12.2-5 |
| (O2)–(O5) | identities to `1e-12`; h < 0 makes the factor unavailable | benchmark 12.2-7, Ohmi part |
| 200 random maps | the 42 checkable identities of Sections 2–7 plus (D14), (K4); scaling invariance | regressions anywhere in the algebra |
| a solenoid-bearing line under the default method | directed error naming both alternatives | a silent fallback |
| one fixture per reason and flag | every status fires; strict false gives a failed result; strict true throws carrying the result | a diagnostic that can never fire |
| one probe per option | receipt from the named consumer, observable change where required, inactive status where declared | an option the code did not read |
| metadata | validator clean; snapshot equals generated; declared set equals derived set both ways; description present; both vocabularies pinned | a stale snapshot or a hand-copied list |

A physics contract runs the manufactured fixtures through `analyze`, records
per-identity maxima, and fails both when an identity drifts and when an
expected diagnostic stays silent. An implementation contract is the option
probe table. A validation script reproduces the identity table with the
digest convention of the profiling drivers and gets its own section in
`validation/README.md`. An executable example analyzes a DBA ring with RF as a
`BeamLine` and is catalogued and added to the example runner list.

### Staging

Seven commits, every one a full-gate class, one full gate on the assembled tree
before the push. Because the Definition of Done requires each commit message to
name the gate that covered it, the gate runs on the assembled tree **before**
the last messages are finalized, and each body names it; commits accumulate
locally until then. Ledgers travel with the work: the campaign record
`docs/history/twiss_dispersion_analysis_history.md` (the guide's form for
ongoing work) is created in the first commit with its index entry and appended
in each later commit, the todo row advances in each commit, and any new
document is indexed in the commit that creates it, since the docs-index
tripwire runs in the fast lane.

1. `feat(analysis)`: symplectic kernel, the availability vocabularies, the
   one-turn-matrix helper with the three method tags, the extension method,
   the two suite closures switched to the helper. The symplectic-defect and
   closed-orbit tolerances are measured here on the FODO, DBA, and oracle
   fixtures and recorded before they are frozen. Snapshot unchanged.
2. `feat(analysis)`: 4D eigenmode, Mais–Ripken, Edwards–Teng; measured
   multipliers appended to the record.
3. `feat(analysis)`: clusters, Krein classification, ambiguity set; the
   chord-measurement table and the frozen default.
4. `feat(analysis)`: 6D routes and the analysis object, schema, receipts,
   configuration report, validator block and tree guard, effectiveness
   contract, `description`, snapshot; the design-note status line, public API
   entries, and the rewording of every place that says analyses are
   placeholder-only (the `AGENTS.md` source-map bullet, the contracts guide,
   the README clause, the theory note's status and Section 11). The targeted
   checks include the public-configuration effectiveness contract.
5. `feat(elements)`: the declaration on the derived kind set and `:line`, the
   two tripwires, the element-side text, snapshot.
6. `feat(contracts)`: the identity contract in its own source file with its
   include line, snapshot, the contract-coverage guard entry, the validation
   script with its README section and record, the example with catalogue and
   runner entries; the todo row closes its implemented parts.
7. `refactor(validation)`: `lattice_cells.jl` derives its Jacobian from the
   helper, with a re-run record. Optional and separable; a todo row if not
   landed.

A neighbour audit follows the last commit of the batch and is recorded in the
same history record. Because commits 1 and 7 replace independent complex-step
closures with the shared helper, the audit re-runs the Jacobian property with
an inline closure in its record, so the helper is not the only witness of its
own correctness.

**Stage 8, external benchmarks.** After the first landing, and as its own
batch with its own gate: each benchmark is a validation script with stated
tolerances and a history record, run at the external code's printed precision
(`set, format` for MAD-X TFS output; the PTC reference generator shows how the
repo drives `madx`). MAD-X `twiss` on uncoupled and coupled cells, comparing
Edwards–Teng `r11..r22`, `betx`, `bety`, and dispersion against the analysis
of the exported one-turn map, including the rolled equal-tune FODO where
MAD-X reports a false instability and the analysis reports a definite
cluster. PTC `ptc_twiss` coupled Ripken functions and dispersion, with the
longitudinal pair converted to `(s − ℓ, δ)`. Xsuite `twiss`, comparing the
W-matrix normalizer and the (X2) dispersion readout after the
longitudinal-coordinate conversion of theory Section 9.5; Xsuite is not
installed on the development machine and gets a scratch virtual environment
whose versions the record pins. These benchmarks close theory Section 12.2
item 7 and the MAD-X and PTC comparisons of item 3; they are the "benchmarked
against other codes" criterion the owner set on 2026-09-11.

### Alternatives rejected

- **Euclidean normalization of eigenvectors** and **selection by the sign of
  the imaginary part of the eigenvalue**: both rejected by the theory
  (Sections 3.2); the symplectic norm fixes the action scale and the branch.
- **Symplectifying a non-symplectic input**: rejected by Section 11.1 step 3;
  the defect is reported or the input refused.
- **Reporting the midpoint of an ambiguity set as the dispersion**: rejected by
  Section 13.8; the midpoint need not be a mode.
- **Labelling or summing absolute signed areas**: rejected by Section 9.3; the
  (K12) sums hold for signed areas only.
- **Orienting eigenvectors one by one before clustering**: rejected because the
  orientation of a single vector is arbitrary near a Krein collision; inertia
  of the half-cluster Gram decides.
- **Judging stability from raw eigenvalue moduli before clustering**: rejected
  because a near-defective cluster's eigenvalues leave the unit circle by the
  square root of the perturbation.
- **Certifying options through a field on the result**: rejected in favour of
  the repo's receipt instrument; a result field proves storage, not use.
- **Overriding a core method from the extension**: rejected; extensions add
  methods on types they own, and a redefinition fails to precompile.
- **Declaring the analysis on the five linear-map kinds only**: rejected in
  favour of the derived rule with tripwires; a hand-picked list is a copy.
- **A required resolution chord with no default**: rejected above.
- **Porting the research prototype's complex conventions verbatim**: the
  prototype uses `e^{+iμ}` and `+2i`; only its real outputs are pinned, and the
  conjugation key `V = conj(U)` is recorded in the degeneracy-theory record.

### Deferred and recorded leads

Transport through a lattice (Section 10), scan continuation (Section 8.8),
mode selection by a supplied covariance, and a public closed-orbit finder are
later stages; the Xsuite comparison (X2) is stage 8 above; the result type
reserves the fields the later stages need. One lead goes to the todo ledger rather than being fixed: the
strong-beam covariance builder treats its `momentum_dispersion` parameter as
the slope `η/h` on the physical longitudinal plane, which equals the canonical
`η` of (D8) only when `ζᵀS₄η = 0`; the analysis, once landed, is the canonical
source to compare against.

### Provenance

The decision emerged from a design review on 2026-09-11: ten reader reports
over the theory note, the degeneracy working notes and prototype, the
canonical-dispersion note and its verification oracle, and the repository's
object, option, tracking, testing, and ledger conventions; three independent
designs; three judges; a synthesis; and four adversarial verifications
(repository facts, theory fidelity, degeneracy robustness, process compliance).
The corrections those verifications forced are the sentinel default on the
symplectic tolerance, the per-cluster stability test, the half-cluster Gram
with unoriented clustering, the branch-predicate inactivity rule, the
receipt shape, the admissibility rule keyed on the constructing form, the
fixed-point route, the commit and ledger rearrangement, and the Jacobian
error-relabelling guard. The theory behind the degeneracy handling is
Section 13 of the theory note and its probe record.
