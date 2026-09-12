# Twiss and Dispersion Analysis: Implementation History

Campaign record for the first analysis, the coupled Twiss and canonical
dispersion of a one-turn matrix. The architecture is decided in
[`design/twiss_dispersion_analysis.md`](../design/twiss_dispersion_analysis.md)
(its "Staging" section names this file); the mathematics is
[`theory/twiss_dispersion.md`](../theory/twiss_dispersion.md); the todo row is
the first row of [`todo.md`](../todo.md). One dated section per stage, in the
form of the other `*_history.md` records: what landed with its file list, the
measurements behind every tolerance, the exact commands, the injected defects
that showed each tripwire red, what was NOT verified, and the gate. Numbers a
decision rests on live here, not in the git-ignored `result/` scratch that
produced them.

Gate posture for the batch (owner decision 2026-09-04, `AGENTS.md` "Definition
of Done"): the stage commits accumulate locally and ONE full gate runs on the
assembled tree before the push; each commit message names that gate, and the
run is recorded in this file when the batch is pushed. Until that line exists
below, no stage of this campaign has been gated.

## 2026-09-11: stage 1 landed (symplectic kernel, availability vocabularies, `one_turn_matrix`)

Stage 1 of the design note's staging: `feat(analysis)`. Registry snapshot
UNCHANGED (no new subtype of a registry root; `Determined` and `AmbiguitySet`
are plain types). Nothing in this stage claims an analysis exists: no
`TwissDispersionAnalysis`, no `analyze`, `summarize_registry().analyses` is
still `[:PlaceholderAnalysis]`, and a stage-guard testset asserts all three
(three marked lines that stage 4 deletes).

### What landed

| File | Change | Content |
|---|---|---|
| `src/analysis/Analysis.jl` | 6 -> 328 lines | `AbstractAnalysisResult`; `DETERMINATION_STATUSES` (3), `DETERMINATION_REASONS` (16, `:not_invariant` included), `AMBIGUITY_KINDS` (2); `Determined{T}` with an inner constructor refusing every inconsistent status/value/set/reason combination; `AmbiguitySet` (center, shape, factor, multiplicity >= 2, kind; `F F' == shape` checked at `16 eps` scale); `UndeterminedQuantityError`; `is_determined`, `is_ambiguous`, `determined_value`, `ambiguity_set` (both throw carrying the reason), `dispersion_interval` (refuses multiplicity one, a unique or unavailable quantity, a wrong-length direction). `PlaceholderAnalysis` and its `description` unchanged. |
| `src/analysis/symplectic_linear_algebra.jl` | new, 462 lines, internal `_` names | `_symplectic_form(d)` for d in (2, 4, 6), `_symplectic_inverse`, `_adjugate2`, `_rotation2`, `_embed_4to6`, `_symplectic_defect` (Frobenius form and the Linear6D row-scaled ratio through the 6x6 embedding), `ReciprocalScaling` with `_reciprocal_scaling(M, :auto / :none / tuple)`, `_auto_scaling_factors`, `_scaling_matrix`, `_scaling_inverse`, `_scale_map`, the back-transformation table as `_unscale_*` (normalizer, covariance, projector, graph, crab and momentum dispersion, longitudinal factor, Edwards-Teng R, Twiss), `_invariance_residual` (matrix and vector forms, normalized and raw), `_graph_invariance_residual`, `_perturbation_scale` (rho_M0 with its four arms), `_manufactured_symplectic_map` (`exp(S H)`). The header explains the `src/analysis/` placement (the design's "six pure-math files") and the late-bound call into `linear6d.jl`. |
| `src/analysis/one_turn_matrix.jl` | new, 399 lines | `AbstractLinearizationMethod`; tags `ComplexStepLinearization` (default, `1e-30im`), `FiniteDifferenceLinearization(step)` (central, `h = step max(abs(q_j), 1)`, default step derived from `SymplecticityContract().step`, declared uncertainty `step^2 norm(J)`), `ForwardDiffLinearization` (core fallback throws a directed error naming both activation routes); `one_turn_matrix(map; method, point)` for a callable, a tuple of runtime maps, or an element spec; `LinearizedMap` and `LinearizationProvenance` (source kind, method, step, point, map uncertainty, fixed-point residual vector); the relabelling guard `_differentiation_limit` (error class, then argument types walked by `_involves_method_number` through Union and DataType parameters, array eltypes and elements, tuple elements; `InexactError` read through `err.args`); `_alternative_method_names` derived from the concrete Octopus subtypes of the tag root. |
| `src/Octopus.jl` | +13 lines | include of the kernel right after `analysis/Analysis.jl` (line 55); include of the helper after every element and track include and before `tasks/RunArtifact.jl` (line 90), with the position justified in a comment (it calls `compile_runtime`). |
| `ext/OctopusForwardDiffRules.jl` | +19 lines | `Octopus._linearize(::ForwardDiffLinearization, f, point)` via `ForwardDiff.jacobian` and the guard leaf `_is_method_number(::ForwardDiffLinearization, x)`; both ADD methods on core-owned tags, none redefines a core method; shared by the package extension and the script-mode include. |
| `test/runtests.jl` | +1217 / -4 lines | 11 kernel testsets (lines 270-944, after "Architecture integrity"); the two suite Jacobian closures switched to the helper with the former inline closures kept as witnesses and bit identity asserted (`cs_jacobian_witness`, "Lattice magnets", 12 magnets; `jac_witness`, "Lattice cells track and stay symplectic", 6 cells); 4 helper testsets plus their top-level fixtures (lines 10912-11430, outside the lane gate). |

Not touched: `validation/lattice_cells.jl` (its closure is stage 7), the design
note, the theory note, `docs/registry_snapshot.md` (regenerated and
byte-identical), any `analyses = [...]` field, any "placeholder-only" wording.

### Standalone verification on the assembled tree (no lane, no gate)

Every run below is standalone in the sense of `development_workflow.md`
"Iterating on one testset": a scratch runner does `using Octopus, Test` and
includes the exact suite blocks. `J` = `julia --startup-file=no`, REPO = the
repository root, OUT = `result/twiss_impl_2026_09_11/stage1` (git-ignored),
fdenv = a scratch environment holding `ForwardDiff v1.4.6` for the package-mode
extension arm (`JULIA_LOAD_PATH="REPO:OUT/fdenv:@stdlib"`). Before every
package-mode run `ps` confirmed no `runtests`/`Pkg.test` process.

| run | command shape | result |
|---|---|---|
| kernel testsets, package mode | `J --project=REPO --threads=4 OUT/run_kernel.jl` | 1618 pass / 0 fail |
| helper testsets, package + fdenv | `JULIA_LOAD_PATH=REPO:OUT/fdenv:@stdlib J --threads=4 OUT/run_otm.jl` | 134/134, ForwardDiff arm ACTIVE, `Base.get_extension(Octopus, :OctopusForwardDiffExt) !== nothing` |
| helper testsets, package plain | `J --project=REPO --threads=4 OUT/run_otm.jl` | 121/121, FALLBACK arm (extension absent, directed error exercised) |
| helper testsets, script mode plain | `OTM_SCRIPT_MODE=1 OTM_REPO=REPO J --project=REPO --threads=4 OUT/run_otm.jl` | 121/121, FALLBACK |
| helper testsets, script mode + fdenv | same with the stacked load path | 133/133, ACTIVE through the script-route include (the extension assertion is package-mode only) |
| suite extract: kernel 270-944, "Lattice magnets" 2391-2607, "Lattice cells track and stay symplectic" 10818-10909, helper 10912-11430; package + fdenv; `CUDA_TESTS_ACTIVE = true` on a GPU host | `J --project=REPO --threads=4 <extract runner>` | 1876/1876 in 1m40 |
| suite tripwires: "Architecture integrity" (incl. `validate_configuration_metadata()`), "No method grows a Core.Box outside the argued allowlist", "Every export is documented", "No docstring is detached by comment lines" | same | 32/32; no new Core.Box, no undocumented or detached docstring |
| script-mode smoke | `J --project=REPO -e 'include("src/Octopus.jl"); using .Octopus; println(summarize_registry())'` | exit 0, `analyses = [:PlaceholderAnalysis]` |
| snapshot and validators, package mode | `write_registry_snapshot(tmp)` byte-compared to `docs/registry_snapshot.md`; `validate_element_metadata()`; `validate_configuration_metadata()` | identical; passed; true |

Count history: the kernel block was 1615 assertions and the helper block
90/94 (plain/ForwardDiff) before the review fixes; the +3 and +31/+40 are the
review-driven fixtures listed under "Review findings" below.

### Part A: kernel tolerances, every one `c eps kappa` with `c` measured

Probe `measure_kernel.jl` (seed 20260911, the suite's own fixtures). "ratio" =
largest observed residual / tolerance over the fixture set; an accepted check
wants it well below one, a rejected fixture wants it well above.

| check | tolerance | why c | measured ratio |
|---|---|---|---|
| symplectic inverse `M^-1 M - I` | `64 eps norm(M)^2` | d-term product bound times the Linear6D validator's margin 64 | 9.9e-3 |
| (E3) normalization `u' S u + 2i` | `64 eps norm(u)^2` | same | 1.4e-2 |
| rotation identity `M U - U R(mu)` | `1e3 eps max(1, norm(M))` | eigen backward error x eigenvector conditioning (~10) x normalization (~10) | 3.0e-3 |
| Frobenius defect of `exp(S H)`, 200 maps | `64 eps` | d eps product bound plus `exp` roundoff, margin 64 | 1.0e-2 |
| row ratio of `exp(S H)`, 200 maps | `<= 1` (the validator's verdict) | its own `64 eps` row scale | 2.2e-2 |
| REJECTED: `I + 0.3 e13` / random + 0.3 shear / random + 1e-10 entry | row ratio `> 10` | design rule "smallest rejected above ten" | 1.6e13 / 1.1e13 / 1.5e3 |
| `C' S C - S`, general factors | `4 eps` | two roundings per `a (1/a)` | 0 (exact on this machine) |
| scaled-map defect | `64 eps cond(C)^2` | the similarity amplifies roundoff by cond(C)^2 | 1.4e-4 |
| similarity round trip | `8 eps norm(M) cond(C)^2` | two diagonal scalings each way | 4.5e-4 |
| back-transformation rows | `1000 eps cond(V) max(1, norm(M~)) max(1, norm(x))` | eigenvector error = backward error x cond(V), measured per run; quadratic rows (G, Sigma, Twiss) double it; at c = 100 the worst ratio was 0.51, so c = 1000 buys a decade | worst 5.1e-2 (G row, `:auto`); amplifier range 9.4 to 5.3e3 |
| (D8) = (D12) h, (D14) of (D10), (K10) closure | same | same | 1.1e-4, 2.7e-4, 7.1e-4 |
| false-graph raw pin `1.5 sqrt(2) sin 0.73`, divisor `sqrt(1.25)` | `16 eps` | a handful of O(1) operations | 0 |

First-run lesson recorded by the implementer: the first back-transformation
tolerance was `1e4 eps max(1, norm(x))` with no conditioning factor and one of
six manufactured maps exceeded it by 2.5x (its scaled map had cond(V) ~ 5e3);
the kappa now carries cond(V), the actual amplifier.

Injected defects (script-mode harness on a patched copy of `src/`; the
unpatched control is 1615 pass / 0 fail):

| id | injection | fails |
|---|---|---|
| 01 | `_symplectic_form`: `S[c, c+1] = -1` | 698 fail, 2 error |
| 02 | `_symplectic_defect`: `row_ratio = err.tolerance` | 7 |
| 03 | `_unscale_crab_dispersion`: `/ a3` instead of `* a3` | 24 |
| 04 | `_invariance_residual`: divisor without the `1` floor | 1 |
| 05 | `_perturbation_scale`: roundoff arm with `norm(M)` instead of `opnorm(M, 2)` | 4 |
| 06 | `:not_invariant` removed from `DETERMINATION_REASONS` | 4 |
| 07 | `determined_value` returns `d.value` silently | 18 fail, 4 error |
| 08 | `AmbiguitySet` multiplicity guard `>= 1` | 1 |
| 09 | `function analyze end` stub in Analysis.jl | 1 |
| 10 | `_embed_4to6`: `M6[6,6] = 0` | 202 |
| 11 | `_unscale_twiss`: `(beta a^2, alpha, gamma / a^2)` | 217 |
| 12 | `_unscale_graph`: `C_l^-1` instead of `C_l` | 36 |
| 13 | `_unscale_momentum_dispersion`: `* a3` instead of `/ a3` | 24 |

### Part B: the helper, measured facts the tests rest on

Complex-step behaviour of the elements the design names (package mode probe):

| map | real evaluation | complex step |
|---|---|---|
| Solenoid (L = 1.3, ks = 0.35) | ok | ok, defect 1.13e-16, bit-identical to the inline closure |
| Drift + Solenoid line | ok | ok, defect 2.22e-16 |
| Aperture, point inside | ok | ok, J = I (limit comparisons act on `abs`) |
| Aperture, particle killed at the point | NaN coordinates | refused BEFORE differentiation (ArgumentError naming the aperture case) |
| ThinStrongBeam, GaussianStrongBeam | ok | `MethodError: isless(::ComplexF64, ::Int64)` -> directed error naming the alternatives |
| Quadrupole | ok | ok, defect 2.22e-16 |

So the design note's "the solenoid under complex step" is STALE: the solenoid
was rewritten in real arithmetic (audit F17) and complex-steps cleanly; the
suite pins that. The strong-beam evaluators are the genuine complex-step
failures. Stage 4 rewords the design's "Input boundary" item 3 and the
verification-plan row.

Finite differences against the complex step, FODO(kq = 1.6) + octupole
(L = 0.15, k3 = 220), point (1e-4, 2e-5, -0.8e-4, -1.5e-5, 3e-4, 2e-4):

| step | `norm(FD - CS)` | declared `step^2 norm(J)` | error / declared |
|---|---|---|---|
| 1e-3 | 3.43e-4 | 5.28e-6 | 65 |
| 1e-4 | 3.43e-6 | 5.28e-8 | 65 |
| 3e-7 (default) | 1.00e-9 | 4.75e-13 | 2100 (roundoff floor) |

Ratio 1e-3 / 1e-4 = 100.0: order `step^2` confirmed. FODO + ThinStrongBeam
(kbb = 1e-4, sigma = (106e-6, 9.5e-6)) against ForwardDiff (`norm(J) = 2.19e4`):
FD error 366.6 / 3.71 / 0.334 / 3.34e-3 / 3.34e-5 at steps 1e-5 / 1e-6 /
3e-7 / 3e-8 / 3e-9, order `step^2` across four decades, and 1.7e8 times the
declared uncertainty. The declared `step^2 norm(M)` is therefore a
truncation-order SCALE, not an error bound; the docstrings say so (see the
review findings) and the FD-input measurement below quantifies both arms.

Injected defects (nine at once in build 1, then one alone), every tripwire red
at least once: (a) complex-step read-out divided by `2e-30`: every bit-identity
line and the 18 suite witnesses red; (b) forward instead of central
difference: the order and default-step pins red; (c) `_is_method_number` always
true: caught only after the `_otm_int_only` MethodError-without-complex fixture
was added (build 2); (d) fixed-point residual zeroed; (e) uncertainty
`step norm(J)`; (f) extension `_linearize` removed (`available` false while
the extension is loaded); (g) fallback message without "script mode"; (h)
arity check `>= 4`; (i) point finiteness unchecked (the Inf case; the NaN case
is caught by the non-finite-output guard instead and is not a witness of (i)).
Build 1: 62 pass / 26 fail and 84 pass / 40 fail in the two runners.

### Review findings and fixes (four reviewers: theory, repository facts, runner, tests)

Fourteen findings, every runtime claim reproduced before it was acted on. Ten
fixes:

1. FD `map_uncertainty` docstrings (`FiniteDifferenceLinearization`,
   `LinearizationProvenance.map_uncertainty`) reworded: the design's
   truncation-order scale, not a bound; formula KEPT per the design note
   ("Input boundary" item 3). The reviewer's proposed two-arm formula
   `max(step^2, eps/(2 step)) max(1, norm(J))` is measured below and left to
   stage 4.
2. The relabelling guard was blind to complex numbers inside containers
   (`Vector{ComplexF64}`, `NTuple{2, ComplexF64}`): new `_involves_method_number`
   walks Union and DataType parameters, array eltypes and elements, tuple
   elements; fixtures added, plus an `Int`-vector control.
3. `_auto_scaling_factors` docstring: factors that WOULD balance if only rows
   were scaled; the column effect is not iterated (measured FODO pair-1 rows
   (3.82, 1.72) -> (1.72, 1.83)).
4. Five suite comments that cited git-ignored `result/` files now cite this
   record.
5. `_alternative_method_names` derives the alternatives from the concrete
   Octopus subtypes of `AbstractLinearizationMethod` instead of a hand-typed
   tuple; tripwire asserts the derived set and that every name appears in a
   real message.
6. The guard read `err.val` on `InexactError`, whose fields on Julia 1.12.4 are
   `(:func, :args)`: a genuine `InexactError` from a map made the guard itself
   throw a `FieldError`, under complex step AND finite difference. Fixed to
   read `err.args`; fixtures for `Float64(x)` under the step (directed error)
   and `Int(1.5)` (unchanged under both methods); the field names are pinned.
7. The ForwardDiff arm of the suite only printed which arm ran: it now asserts
   `available` whenever ForwardDiff is defined and `ext_loaded` in package mode.
8. FD relative step `h = step max(abs(q_j), 1)` pinned by a recording map at
   z = 2.0, x = 1e-4, step 1e-3 (abscissae `[2 - 2e-3, 2, 2 + 2e-3]` and
   `[1e-4 - 1e-3, 1e-4, 1e-4 + 1e-3]` exactly).
9. The `norm(M_rl)` divisor arm of the graph residual pinned (M = I with
   `M[1,5] = 10`, `M[2,6] = -4`, D = 0: raw `norm(M_rl)`, normalized 1.0).
10. Extension guard leaf and `TypeError` branch fixtured in the ACTIVE arm
    (Float64 typeassert under ForwardDiff -> directed error naming the other
    two tags; `Vector{Dual}` MethodError relabelled; plain error unchanged).

Skipped, with reasons: creating this file (Part D, below); the integrator's
stale scratch extract header (another agent's record); the two-arm formula
(design conflict, measured below). Refuted: "scalar ComplexF64 argument not
relabelled" (that fixture also fails in real arithmetic, so the error is the
map's own).

Injected defects for the new tripwires (patched copies of `src/` and `ext/`,
unpatched controls green):

| id | injection | fails |
|---|---|---|
| f01 | `_differentiation_limit`: InexactError branch returns false | 2 / 121 |
| f02 | `_involves_method_number` reduced to the leaf | 7 / 121 |
| f03 | FD `h = step` (relative factor dropped) | 1 / 121 |
| f04 | graph divisor without `norm(M_rl)` | 2 / 1618 |
| f05 | extension leaf `_is_method_number(::ForwardDiffLinearization, x) = false`, ACTIVE arm | 5 / 133 |
| f06 | hand-typed alternatives list missing `ForwardDiffLinearization` | 4 / 121 |
| f07 | package-mode tree whose rules file throws at load (Julia logs "Error during loading of extension" and continues) | 2 / 123, was 90/90 green before finding 7 |

### Part D: measurement of the symplectic-defect and closed-orbit tolerances

Fixtures: the FODO, DBA and TBA cells of `validation/lattice_cells.jl` and
their `+sext` variants, rebuilt inline with the script's constants (nst 4,
integrator order 4) and its stability scan (working points FODO kq = 1.6, DBA
kf = 1.5 kd = -1.1, TBA kf = 0.9 kd = -1.0); the 39 oracle maps of the
canonical-dispersion note (24 dense elliptic, 7 prescribed-h with h in
{-2, -1, -0.3, 0.05, 0.5, 1, 2}, 4 repeated-betatron, 1 defective spectator,
3 coasting), regenerated by replaying `verify_dispersion.py`'s fixture loop
with its own helpers and RNG order (seed 20260911; python 3.11.5, numpy 1.23.5,
scipy 1.11.4; script sha256
`2b66098bf27b508a1099e76376cae8c464a82bccec190b21a70ee26eae094f12`), every map
passed through the note's `check_map`, whose evaluation counts (117, 180, 78,
78, 234) equal the note's `verification_table.tex` rows. Measured: the
Frobenius defect `norm(M' S M - S) / max(1, norm(M)^2)`, the Linear6D
row-scaled ratio, both raw and under the `:auto` reciprocal scaling; rho_M0 on
the scaled map with its winning arm; the fixed-point residual in raw and scaled
infinity norm; under complex step and central finite differences at the derived
default step 3e-7 and at 1e-5. The cells are coasting (no RF), so their
longitudinal block is the (D23) structure. Tables 1-6 below are the script's
output verbatim (`measurement_table.md`).

Commands (from the repository root; package mode so the extension arm is the
suite's):

```bash
/opt/anaconda3_2024_02/bin/python3 dump_oracle_maps.py oracle_maps.tsv
julia --startup-file=no --project=. --threads=4 measure_stage1.jl oracle_maps.tsv measurement_table.md
```

Both scripts are reproduced in the appendix of this section; until stage 6
moves them under `validation/`, this record is their committed home.

### Derived defaults (rule: largest accepted ratio below one tenth, smallest rejected above ten; arithmetic in the "Derived defaults" block of the table)

| default | proposed | window from the rule | accepted max ratio | rejected min ratio |
|---|---|---|---|---|
| `symplectic_rtol` for exact provenance, Frobenius form | `64 eps` = 1.42e-14 (the Linear6D validator's constant) | [1.88e-15, 5.76e-14], geometric mean 1.04e-14 -> 1e-14 = 45 eps; `64 eps` is inside and reuses the precedent's constant | 1.32e-2 (oracle "repeated 2", scaled) | 40.6 (TBA CS + 1e-10 in one entry) |
| row-scaled ratio, verdict `<= k` | `k = 1` (the validator's verdict) | [1.08, 1.37], geometric mean 1.22 -> 1 | 0.108 (DBA+sext raw), which MISSES the one-tenth rule by 8% | 13.7 (the 1e-12 perturbations, which the Frobenius form cannot decide: 0.4 .. 2.3 x 64 eps) |
| FD input | an explicit `symplectic_rtol` stays REQUIRED (design); the recommended value for a user is `10 (eps / (2 step) + step^2)`: 3.7e-9 at the default step, 1.1e-9 at 1e-5 | measured cell FD defects sit at 0.017 .. 1.0 x `eps/(2h)` | 1.0e-2 | the 0.3 shears by >= 4.6e5; a 1e-8 single-entry error is NOT rejected (<= 0.049), the price of FD input |
| `closed_orbit_atol`, scaled infinity norm | roundoff-derived `64 eps max(1, norm(M~))`: 1.42e-14 at unit norm, 5.3e-14 .. 1.6e-13 on the cells | [1.33e-14, 7.93e-8] (the accepted side is the roundoff floor, so the seven-decade midpoint 3e-11 is weakly determined; the roundoff form sits at the lower edge, where the design's "roundoff-derived" text puts it) | 1.7e-3 (TBA at the origin, 2.79e-16) | 5.8e6 (FODO at the scan point (1e-6, 0, 1e-6, 0, 0, 0), 7.93e-7; that point already moves the Jacobian by 7e8 rho_M0) |

Measured facts behind the FD decisions, for stage 4:

- At the default step 3e-7 the FD matrix error is 340 .. 1430 times the
  declared `step^2 norm(M)` and 0.08 .. 0.35 times the roundoff model
  `eps/(2h) norm(M)`; at 1e-5 it is 0.84 .. 4.7 times the declared value and
  7.6 .. 42 times the roundoff model. The two-arm candidate
  `max(step^2, eps/(2 step)) norm(M)` is within 0.08 .. 4.7 of the measured
  error on every cell (the one-arm formula: 0.84 .. 1430). Recommendation for
  the stage 4 design-note update: adopt the two-arm formula for the declared
  uncertainty; the suite pin `10 < err/uncertainty < 1000` at the default step
  moves with it.
- The FD matrices of the LINEAR oracle maps are symplectic to roundoff
  (defect 2e-17 .. 1.6e-16; their error is 3.4e-9 .. 7.6e-6 of the roundoff
  model because at the origin both evaluations of a linear map are themselves
  O(h) and nothing O(1) cancels, so the error is O(eps norm(M)), a fraction
  2h of the model), so an FD input is refused by the provenance rule and never
  by the defect: correct, since a symplectic FD matrix of a nonlinear cell is
  still only accurate to 1e-9 (Table 2).

Open design items recorded for stage 4 (this record does not edit the design
note):

1. The declared FD uncertainty formula (above).
2. "The solenoid under complex step" is stale (Part B).
3. A coasting cell at delta != 0 has a genuine z slip per turn (-3.9e-5 at
   delta = 1e-4 on the DBA, Table 4) while its transverse orbit is a fixed
   point to 3e-17: the fixed-point test must act on the transverse components
   when the (D23) structure holds, or every off-momentum coasting analysis is
   refused.
4. The `:auto` scaling is a one-pass row balance (cond C = 6 on the FODO, 48
   on the DBA, 99 on the TBA; the scaled defects and row ratios stay within
   a factor 3 of the raw ones): adequate for stage 1, policy to revisit if a
   fixture ever needs the iterated balance.

### Not verified in stage 1

- No lane and no gate ran on this tree; every count above is standalone. The
  full gate on the assembled batch is owed before the push and is recorded in
  this file when it runs.
- `validation/tracking_backend_consistency.jl` and `validation/lattice_cells.jl`
  were not run (no kernel, element, or tracking code changed; the helper is
  host-only and not reachable from a CUDA kernel).
- No injected-defect re-run after the integration fold; the 13 + 9 + 7
  injections stand as recorded from the worktrees and the fixed tree.
- The measurement script's Newton solve is test-local (design: no public
  closed-orbit finder in this landing).
- The oracle dump reproduces the note's maps by replaying its RNG order; bit
  identity with the note's own run was not asserted (the note stores no
  matrices), only the identical `check_map` counts and its passing checks.

### Measurement tables (output of `measure_stage1.jl`, verbatim)

Julia 1.12.4, 4 threads, host acnlinj4.pbn.bnl.gov; eps = 2.220446049250313e-16.
Working points (same scan as validation/lattice_cells.jl): FODO kq=1.6 | DBA kf=1.5 kd=-1.1 | TBA kf=0.9 kd=-1.0.
FD steps: 3.0e-7 (the derived default, SymplecticityContract().step) and 1.0e-5.

#### Table 1: cells at the origin, complex step (exact provenance)

| cell | elems | bit-identical to inline closure | ||M||_F | ||M||_2 | defect_F raw | row ratio raw | auto factors | cond C | defect_F scaled | row ratio scaled | rho_M0 (scaled) | winning arm | fp residual raw inf | fp residual scaled inf |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| FODO | 4 | true | 5.08e+00 | 4.19e+00 | 2.90e-17 | 2.01e-02 | 6.70e-01, 4.07e-01, 1.00e+00 | 6.05e+00 | 3.41e-17 | 1.33e-02 | 3.31e-15 | roundoff | 0.00e+00 | 0.00e+00 |
| FODO+sext | 5 | true | 5.35e+00 | 4.50e+00 | 4.54e-17 | 3.45e-02 | 6.42e-01, 4.06e-01, 1.00e+00 | 6.07e+00 | 1.03e-16 | 3.13e-02 | 3.34e-15 | roundoff | 0.00e+00 | 0.00e+00 |
| DBA | 9 | true | 8.76e+00 | 8.39e+00 | 2.26e-17 | 7.70e-02 | 6.54e-01, 1.26e-01, 8.76e-01 | 4.83e+01 | 3.04e-17 | 8.46e-02 | 9.96e-15 | roundoff | 2.30e-17 | 1.51e-17 |
| DBA+sext | 10 | true | 8.78e+00 | 8.40e+00 | 2.79e-17 | 1.08e-01 | 6.47e-01, 1.26e-01, 8.76e-01 | 4.83e+01 | 3.60e-17 | 1.08e-01 | 9.97e-15 | roundoff | 2.43e-17 | 1.57e-17 |
| TBA | 13 | true | 1.29e+01 | 1.25e+01 | 1.10e-17 | 5.05e-02 | 5.62e-01, 8.42e-02, 8.36e-01 | 9.86e+01 | 1.60e-17 | 5.62e-02 | 1.50e-14 | roundoff | 3.33e-16 | 2.79e-16 |
| TBA+sext | 14 | true | 1.29e+01 | 1.25e+01 | 2.12e-17 | 8.15e-02 | 5.58e-01, 8.42e-02, 8.36e-01 | 9.87e+01 | 2.75e-17 | 1.01e-01 | 1.50e-14 | roundoff | 3.33e-16 | 2.79e-16 |

#### Table 2: cells at the origin, central finite difference at two steps

The roundoff model is eps/(2h) with h = step (|q_j| <= 1 at the origin): the entrywise roundoff of a central difference relative to ||M||, which is what defect_F (normalized by ||M||_F^2) measures. declared = the provenance's step^2 ||M||_F.

| cell | step | ||M_fd - M_cs||_F | declared uncertainty | error / declared | roundoff model eps/(2h) ||M||_F | error / roundoff | defect_F raw | defect_F / (eps/2h) | row ratio raw | defect_F scaled | rho_M0 (scaled) | winning arm | fp residual raw inf |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| FODO | 3.0e-7 | 1.56e-10 | 4.57e-13 | 3.42e+02 | 1.88e-09 | 8.31e-02 | 8.56e-12 | 2.31e-02 | 1.10e+04 | 1.58e-11 | 5.90e-11 | defect | 0.00e+00 |
| FODO | 1.0e-5 | 4.28e-10 | 5.08e-10 | 8.43e-01 | 5.64e-11 | 7.59e+00 | 6.91e-12 | 6.22e-01 | 5.49e+03 | 1.27e-11 | 5.08e-10 | provenance | 0.00e+00 |
| FODO+sext | 3.0e-7 | 1.56e-10 | 4.81e-13 | 3.25e+02 | 1.98e-09 | 7.90e-02 | 7.73e-12 | 2.09e-02 | 1.10e+04 | 1.58e-11 | 5.91e-11 | defect | 0.00e+00 |
| FODO+sext | 1.0e-5 | 6.10e-10 | 5.35e-10 | 1.14e+00 | 5.94e-11 | 1.03e+01 | 1.12e-11 | 1.01e+00 | 1.52e+04 | 1.61e-11 | 5.35e-10 | provenance | 0.00e+00 |
| DBA | 3.0e-7 | 1.12e-09 | 7.89e-13 | 1.42e+03 | 3.24e-09 | 3.46e-01 | 1.20e-11 | 3.24e-02 | 1.94e+04 | 1.08e-11 | 8.45e-11 | defect | 2.30e-17 |
| DBA | 1.0e-5 | 1.83e-09 | 8.76e-10 | 2.09e+00 | 9.73e-11 | 1.88e+01 | 3.33e-12 | 3.00e-01 | 1.21e+04 | 4.11e-12 | 8.76e-10 | provenance | 2.30e-17 |
| DBA+sext | 3.0e-7 | 1.13e-09 | 7.91e-13 | 1.43e+03 | 3.25e-09 | 3.47e-01 | 1.20e-11 | 3.23e-02 | 1.94e+04 | 1.07e-11 | 8.41e-11 | defect | 2.43e-17 |
| DBA+sext | 1.0e-5 | 3.33e-09 | 8.78e-10 | 3.79e+00 | 9.75e-11 | 3.42e+01 | 1.69e-12 | 1.53e-01 | 3.24e+03 | 1.58e-12 | 8.78e-10 | provenance | 2.43e-17 |
| TBA | 3.0e-7 | 1.39e-09 | 1.16e-12 | 1.20e+03 | 4.76e-09 | 2.91e-01 | 6.33e-12 | 1.71e-02 | 2.58e+04 | 7.91e-12 | 9.10e-11 | defect | 3.33e-16 |
| TBA | 1.0e-5 | 4.28e-09 | 1.29e-09 | 3.33e+00 | 1.43e-10 | 2.99e+01 | 2.50e-12 | 2.25e-01 | 2.03e+04 | 3.12e-12 | 1.29e-09 | provenance | 3.33e-16 |
| TBA+sext | 3.0e-7 | 1.40e-09 | 1.16e-12 | 1.21e+03 | 4.76e-09 | 2.94e-01 | 6.32e-12 | 1.71e-02 | 2.35e+04 | 7.93e-12 | 9.13e-11 | defect | 3.33e-16 |
| TBA+sext | 1.0e-5 | 6.06e-09 | 1.29e-09 | 4.71e+00 | 1.43e-10 | 4.24e+01 | 1.21e-12 | 1.09e-01 | 8.84e+03 | 1.47e-12 | 1.29e-09 | provenance | 3.33e-16 |

#### Table 3: cells at points that are not fixed points, complex step

Scaled residual uses the origin's :auto scaling of the same cell. ||J(p) - J(0)||_F / rho_M0(0) says whether the Jacobian moved by more than the map's own roundoff scale (> 10 means the point must be rejected as a closed orbit).

| cell | point | fp residual raw inf | fp residual scaled inf | ||J(p) - J(0)||_F | / rho_M0(0) |
|---|---|---|---|---|---|
| FODO | P6 (1e-6, 0, 1e-6, 0, 0, 0) | 1.14e-06 | 7.93e-07 | 2.33e-06 | 7.03e+08 |
| FODO | U0 (1e-4, 2e-5, -8e-5, -1.5e-5, 1e-3, 2e-4) | 5.55e-05 | 9.11e-05 | 1.03e-03 | 3.11e+11 |
| FODO+sext | P6 (1e-6, 0, 1e-6, 0, 0, 0) | 1.20e-06 | 7.95e-07 | 9.98e-06 | 2.99e+09 |
| FODO+sext | U0 (1e-4, 2e-5, -8e-5, -1.5e-5, 1e-3, 2e-4) | 5.11e-05 | 9.13e-05 | 1.66e-03 | 4.97e+11 |
| DBA | P6 (1e-6, 0, 1e-6, 0, 0, 0) | 1.00e-06 | 9.44e-07 | 3.91e-06 | 3.92e+08 |
| DBA | U0 (1e-4, 2e-5, -8e-5, -1.5e-5, 1e-3, 2e-4) | 7.41e-05 | 1.87e-04 | 2.13e-03 | 2.14e+11 |
| DBA+sext | P6 (1e-6, 0, 1e-6, 0, 0, 0) | 1.13e-06 | 9.55e-07 | 4.32e-06 | 4.33e+08 |
| DBA+sext | U0 (1e-4, 2e-5, -8e-5, -1.5e-5, 1e-3, 2e-4) | 7.89e-05 | 1.87e-04 | 3.69e-03 | 3.71e+11 |
| TBA | P6 (1e-6, 0, 1e-6, 0, 0, 0) | 1.07e-06 | 9.45e-07 | 3.97e-06 | 2.65e+08 |
| TBA | U0 (1e-4, 2e-5, -8e-5, -1.5e-5, 1e-3, 2e-4) | 1.14e-04 | 2.47e-04 | 3.44e-03 | 2.30e+11 |
| TBA+sext | P6 (1e-6, 0, 1e-6, 0, 0, 0) | 1.17e-06 | 9.46e-07 | 4.98e-06 | 3.33e+08 |
| TBA+sext | U0 (1e-4, 2e-5, -8e-5, -1.5e-5, 1e-3, 2e-4) | 1.21e-04 | 2.46e-04 | 6.81e-03 | 4.55e+11 |

#### Table 4: dispersive cells at delta = 1e-4 and 1e-3, transverse closed orbit from a test-local Newton solve

Newton on (x, px, y, py) with z = 0 and pz = delta fixed, Jacobian from one_turn_matrix at the iterate, stopped when the transverse residual stops decreasing (at most 12 steps). The transverse residual at convergence is the roundoff a genuine fixed point leaves (an accepted fixture); the z component is the path-length slip of a coasting cell and is reported separately.

| cell | delta | iterations | x_co | px_co | transverse residual raw inf | transverse residual scaled inf | z residual raw (path slip) | defect_F scaled at the orbit | rho_M0 at the orbit |
|---|---|---|---|---|---|---|---|---|---|
| DBA | 0.0001 | 4 | 7.06e-05 | 1.60e-17 | 1.17e-17 | 1.79e-17 | -3.90e-05 | 1.07e-17 | 9.95e-15 |
| DBA | 0.001 | 8 | 7.07e-04 | -5.15e-18 | 4.34e-18 | 6.63e-18 | -3.90e-04 | 2.17e-17 | 9.89e-15 |
| DBA+sext | 0.0001 | 7 | 7.06e-05 | -2.00e-09 | 2.45e-17 | 3.11e-17 | -3.90e-05 | 1.49e-17 | 9.93e-15 |
| DBA+sext | 0.001 | 10 | 7.07e-04 | -2.00e-07 | 2.26e-17 | 3.50e-17 | -3.90e-04 | 2.39e-17 | 9.57e-15 |
| TBA | 0.0001 | 6 | 8.53e-05 | 1.41e-16 | 5.55e-17 | 5.22e-17 | -5.05e-05 | 1.26e-17 | 1.49e-14 |
| TBA | 0.001 | 8 | 8.54e-04 | 1.34e-16 | 7.73e-18 | 1.38e-17 | -5.06e-04 | 9.93e-18 | 1.48e-14 |
| TBA+sext | 0.0001 | 8 | 8.53e-05 | -2.91e-09 | 4.63e-17 | 2.58e-17 | -5.05e-05 | 2.01e-17 | 1.48e-14 |
| TBA+sext | 0.001 | 11 | 8.53e-04 | -2.91e-07 | 6.61e-18 | 1.01e-17 | -5.05e-04 | 9.53e-18 | 1.34e-14 |

#### Table 5: oracle maps of the canonical-dispersion note (bare matrices, then re-linearized as the callable u -> M u)

Seed 20260911, generated by dump_oracle_maps.py replaying verify_dispersion.py's fixture loop; every map passed the note's own check_map. CS = complex step of the linear callable (exact up to the 1e-30 scaling), FD at the two steps: for a linear map the FD error is pure roundoff, so error / (eps/(2h) ||M||_F) is the roundoff constant of the central difference itself.

| family | idx | parameter | ||M||_F | defect_F raw | row ratio raw | auto factors | defect_F scaled | row ratio scaled | rho_M0 (scaled) | arm | ||J_cs - M||_F | FD err/roundoff @3e-7 | FD defect_F raw @3e-7 | FD err/roundoff @1e-5 | FD defect_F raw @1e-5 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| dense | 0 | -0.87 | 2.92e+00 | 7.94e-17 | 1.53e-02 | 9.72e-01, 1.31e+00, 5.61e-01 | 1.31e-16 | 1.77e-02 | 2.19e-15 | roundoff | 1.40e-16 | 3.28e-08 | 7.82e-17 | 4.33e-06 | 1.01e-16 |
| dense | 1 | -0.873 | 3.01e+00 | 9.43e-17 | 1.62e-02 | 9.57e-01, 8.06e-01, 1.01e+00 | 1.33e-16 | 1.87e-02 | 2.63e-15 | roundoff | 1.49e-16 | 1.16e-07 | 8.88e-17 | 4.18e-06 | 9.67e-17 |
| dense | 2 | -0.876 | 3.11e+00 | 8.40e-17 | 1.70e-02 | 8.85e-01, 5.83e-01, 1.73e+00 | 1.27e-16 | 2.33e-02 | 2.42e-15 | roundoff | 3.00e-16 | 2.18e-07 | 7.00e-17 | 7.64e-06 | 7.09e-17 |
| dense | 3 | -0.879 | 3.34e+00 | 7.68e-17 | 1.22e-02 | 1.29e+00, 8.84e-01, 1.83e+00 | 9.04e-17 | 1.06e-02 | 3.15e-15 | roundoff | 1.36e-16 | 1.61e-07 | 7.74e-17 | 3.35e-06 | 7.68e-17 |
| dense | 4 | -0.882 | 3.16e+00 | 6.20e-17 | 8.57e-03 | 1.11e+00, 1.31e+00, 1.03e+00 | 9.62e-17 | 1.39e-02 | 2.51e-15 | roundoff | 1.01e-16 | 9.51e-08 | 6.83e-17 | 4.82e-06 | 5.43e-17 |
| dense | 5 | -0.885 | 3.07e+00 | 1.55e-16 | 1.81e-02 | 7.04e-01, 9.85e-01, 7.86e-01 | 1.67e-16 | 2.13e-02 | 2.39e-15 | roundoff | 3.40e-17 | 7.42e-08 | 1.58e-16 | 3.75e-06 | 1.55e-16 |
| dense | 6 | -0.888 | 2.88e+00 | 8.10e-17 | 7.01e-03 | 1.25e+00, 1.26e+00, 7.19e-01 | 7.74e-17 | 1.02e-02 | 2.32e-15 | roundoff | 1.25e-16 | 1.41e-07 | 7.40e-17 | 5.30e-06 | 5.62e-17 |
| dense | 7 | -0.891 | 4.02e+00 | 1.05e-16 | 1.89e-02 | 7.88e-01, 5.90e-01, 7.14e-01 | 1.57e-16 | 1.55e-02 | 3.01e-15 | roundoff | 1.18e-16 | 7.92e-08 | 1.04e-16 | 1.56e-06 | 1.11e-16 |
| dense | 8 | -0.894 | 3.03e+00 | 1.08e-16 | 1.17e-02 | 9.58e-01, 9.84e-01, 6.88e-01 | 1.11e-16 | 9.57e-03 | 2.44e-15 | roundoff | 1.59e-16 | 1.55e-07 | 1.23e-16 | 6.24e-06 | 1.19e-16 |
| dense | 9 | -0.897 | 3.37e+00 | 8.97e-17 | 1.40e-02 | 8.66e-01, 7.88e-01, 5.27e-01 | 1.10e-16 | 1.90e-02 | 3.10e-15 | roundoff | 1.72e-16 | 2.02e-07 | 1.04e-16 | 4.51e-06 | 1.03e-16 |
| dense | 10 | -0.9 | 2.83e+00 | 9.58e-17 | 1.01e-02 | 1.03e+00, 1.24e+00, 1.43e+00 | 9.88e-17 | 8.51e-03 | 2.20e-15 | roundoff | 1.28e-16 | 8.50e-08 | 9.54e-17 | 2.03e-06 | 9.56e-17 |
| dense | 11 | -0.903 | 3.17e+00 | 1.28e-16 | 1.53e-02 | 9.69e-01, 1.20e+00, 5.98e-01 | 1.50e-16 | 1.75e-02 | 2.95e-15 | roundoff | 1.26e-16 | 1.02e-07 | 1.29e-16 | 1.83e-06 | 1.04e-16 |
| dense | 12 | -0.906 | 3.05e+00 | 1.26e-16 | 1.38e-02 | 9.60e-01, 7.18e-01, 1.39e+00 | 1.56e-16 | 1.87e-02 | 2.65e-15 | roundoff | 6.94e-18 | 9.28e-08 | 1.27e-16 | 2.49e-06 | 1.20e-16 |
| dense | 13 | -0.909 | 3.13e+00 | 6.72e-17 | 7.51e-03 | 8.48e-01, 8.15e-01, 9.97e-01 | 9.03e-17 | 1.38e-02 | 2.74e-15 | roundoff | 1.24e-16 | 1.08e-07 | 6.61e-17 | 3.34e-06 | 8.75e-17 |
| dense | 14 | -0.912 | 3.44e+00 | 5.96e-17 | 1.21e-02 | 8.38e-01, 1.67e+00, 1.62e+00 | 5.88e-17 | 1.63e-02 | 3.57e-15 | roundoff | 2.28e-16 | 2.00e-07 | 7.50e-17 | 3.00e-06 | 5.30e-17 |
| dense | 15 | -0.915 | 3.18e+00 | 1.36e-16 | 2.55e-02 | 8.48e-01, 8.20e-01, 1.22e+00 | 1.35e-16 | 1.94e-02 | 2.59e-15 | roundoff | 2.08e-16 | 9.72e-08 | 1.08e-16 | 5.75e-06 | 1.11e-16 |
| dense | 16 | -0.918 | 2.91e+00 | 7.38e-17 | 9.05e-03 | 9.91e-01, 1.04e+00, 1.01e+00 | 6.42e-17 | 7.80e-03 | 2.50e-15 | roundoff | 1.30e-16 | 1.06e-07 | 9.25e-17 | 5.37e-06 | 7.27e-17 |
| dense | 17 | -0.921 | 3.01e+00 | 6.61e-17 | 1.08e-02 | 1.78e+00, 9.13e-01, 9.28e-01 | 8.48e-17 | 1.55e-02 | 3.08e-15 | roundoff | 1.30e-16 | 3.75e-08 | 6.57e-17 | 4.87e-06 | 6.49e-17 |
| dense | 18 | -0.924 | 3.36e+00 | 5.29e-17 | 9.95e-03 | 8.89e-01, 6.24e-01, 7.69e-01 | 6.60e-17 | 1.04e-02 | 2.41e-15 | roundoff | 6.21e-17 | 1.79e-07 | 5.03e-17 | 3.00e-06 | 5.14e-17 |
| dense | 19 | -0.927 | 2.86e+00 | 8.84e-17 | 9.55e-03 | 9.79e-01, 8.27e-01, 9.18e-01 | 7.27e-17 | 8.89e-03 | 2.40e-15 | roundoff | 1.15e-16 | 1.51e-07 | 7.65e-17 | 5.06e-06 | 7.53e-17 |
| dense | 20 | -0.9299999999999999 | 3.14e+00 | 1.08e-16 | 1.55e-02 | 1.33e+00, 1.29e+00, 1.00e+00 | 1.57e-16 | 2.11e-02 | 2.62e-15 | roundoff | 3.93e-17 | 5.34e-08 | 1.08e-16 | 7.16e-06 | 9.51e-17 |
| dense | 21 | -0.933 | 2.99e+00 | 7.93e-17 | 8.70e-03 | 8.98e-01, 1.10e+00, 1.13e+00 | 6.18e-17 | 8.76e-03 | 2.86e-15 | roundoff | 8.99e-17 | 5.21e-08 | 8.31e-17 | 3.88e-06 | 8.21e-17 |
| dense | 22 | -0.9359999999999999 | 2.80e+00 | 1.14e-16 | 1.72e-02 | 9.27e-01, 8.71e-01, 8.68e-01 | 1.67e-16 | 2.24e-02 | 2.08e-15 | roundoff | 1.22e-16 | 2.78e-08 | 1.16e-16 | 1.72e-06 | 1.17e-16 |
| dense | 23 | -0.9390000000000001 | 3.52e+00 | 7.40e-17 | 1.16e-02 | 6.39e-01, 9.19e-01, 7.66e-01 | 8.76e-17 | 9.02e-03 | 2.94e-15 | roundoff | 6.21e-17 | 1.32e-07 | 8.82e-17 | 2.36e-06 | 8.47e-17 |
| prescribed_h | 0 | -2.0 | 1.15e+01 | 4.74e-17 | 6.28e-03 | 1.54e+00, 9.18e-01, 9.43e-01 | 6.47e-17 | 7.27e-03 | 1.13e-14 | roundoff | 9.18e-16 | 2.10e-07 | 4.40e-17 | 4.89e-07 | 4.73e-17 |
| prescribed_h | 1 | -1.0 | 4.08e+00 | 3.32e-17 | 1.02e-02 | 2.11e+00, 9.83e-01, 7.79e-01 | 6.73e-17 | 9.42e-03 | 2.91e-15 | roundoff | 0.00e+00 | 9.26e-09 | 3.32e-17 | 2.54e-06 | 3.30e-17 |
| prescribed_h | 2 | -0.3 | 2.59e+00 | 6.79e-17 | 4.81e-03 | 9.12e-01, 9.97e-01, 8.82e-01 | 9.79e-17 | 1.02e-02 | 1.96e-15 | roundoff | 3.18e-17 | 3.31e-08 | 7.15e-17 | 9.71e-07 | 6.78e-17 |
| prescribed_h | 3 | 0.05 | 2.75e+00 | 3.40e-17 | 3.81e-03 | 7.75e-01, 9.99e-01, 9.45e-01 | 4.99e-17 | 6.19e-03 | 2.29e-15 | roundoff | 1.67e-16 | 3.40e-09 | 3.40e-17 | 6.29e-06 | 4.40e-17 |
| prescribed_h | 4 | 0.5 | 2.91e+00 | 5.31e-17 | 6.07e-03 | 8.35e-01, 1.00e+00, 9.04e-01 | 7.81e-17 | 6.61e-03 | 2.55e-15 | roundoff | 1.69e-16 | 1.48e-07 | 4.93e-17 | 6.93e-06 | 6.62e-17 |
| prescribed_h | 5 | 1.0 | 2.70e+00 | 4.72e-17 | 6.62e-03 | 8.79e-01, 1.00e+00, 8.32e-01 | 5.82e-17 | 7.35e-03 | 2.23e-15 | roundoff | 1.92e-16 | 1.12e-07 | 3.72e-17 | 3.81e-06 | 4.99e-17 |
| prescribed_h | 6 | 2.0 | 4.10e+00 | 1.60e-17 | 5.03e-03 | 9.03e-01, 1.00e+00, 2.24e+00 | 4.36e-17 | 5.50e-03 | 2.99e-15 | roundoff | 1.57e-16 | 7.76e-08 | 2.51e-17 | 2.51e-06 | 2.79e-17 |
| repeated | 0 | -1.3 | 2.86e+00 | 1.05e-16 | 1.42e-02 | 1.49e+00, 9.43e-01, 8.32e-01 | 1.18e-16 | 1.69e-02 | 2.02e-15 | roundoff | 2.78e-17 | 5.85e-08 | 1.05e-16 | 4.30e-06 | 1.03e-16 |
| repeated | 1 | -1.3 | 2.62e+00 | 7.76e-17 | 9.97e-03 | 1.05e+00, 8.37e-01, 1.08e+00 | 7.39e-17 | 8.74e-03 | 1.76e-15 | roundoff | 8.44e-17 | 2.95e-08 | 7.86e-17 | 4.83e-06 | 9.06e-17 |
| repeated | 2 | -1.3 | 2.80e+00 | 1.40e-16 | 2.03e-02 | 1.21e+00, 1.06e+00, 1.45e+00 | 1.88e-16 | 2.84e-02 | 1.96e-15 | roundoff | 1.28e-16 | 1.52e-07 | 1.57e-16 | 4.02e-06 | 1.22e-16 |
| repeated | 3 | -1.3 | 2.63e+00 | 9.92e-17 | 1.82e-02 | 9.91e-01, 1.22e+00, 9.49e-01 | 8.58e-17 | 1.39e-02 | 2.09e-15 | roundoff | 1.95e-16 | 1.62e-07 | 8.82e-17 | 5.47e-06 | 9.64e-17 |
| defective | 0 | -1.3 | 2.77e+00 | 9.07e-17 | 1.38e-02 | 1.02e+00, 9.74e-01, 6.78e-01 | 9.98e-17 | 1.43e-02 | 2.36e-15 | roundoff | 3.47e-17 | 1.20e-07 | 9.17e-17 | 5.17e-06 | 9.16e-17 |
| coasting | 0 | -0.4 | 2.51e+00 | 6.53e-17 | 1.15e-02 | 1.00e+00, 9.84e-01, 9.54e-01 | 9.33e-17 | 1.75e-02 | 1.70e-15 | roundoff | 1.57e-16 | 1.69e-07 | 2.38e-17 | 2.49e-07 | 6.53e-17 |
| coasting | 1 | 0.0 | 2.48e+00 | 6.69e-17 | 1.17e-02 | 9.98e-01, 1.01e+00, 9.84e-01 | 6.30e-17 | 1.39e-02 | 1.52e-15 | roundoff | 1.59e-16 | 1.76e-07 | 2.53e-17 | 3.57e-07 | 6.69e-17 |
| coasting | 2 | 0.7 | 2.63e+00 | 6.12e-17 | 1.29e-02 | 1.00e+00, 1.01e+00, 8.67e-01 | 8.79e-17 | 1.70e-02 | 1.91e-15 | roundoff | 1.93e-16 | 1.98e-07 | 2.02e-17 | 1.06e-06 | 6.00e-17 |

Per-family maximum defect_F (raw and scaled): coasting 9.33e-17; defective 9.98e-17; dense 1.67e-16; prescribed_h 9.79e-17; repeated 1.88e-16.

#### Table 6: non-symplectic fixtures (must be rejected)

| fixture | defect_F raw | row ratio raw | defect_F scaled | row ratio scaled |
|---|---|---|---|---|
| I + 0.3 e13 (design shear) | 6.97e-02 | 1.62e+13 | 6.82e-02 | 1.60e+13 |
| FODO CS + 0.3 shear in [1,3] | 2.81e-02 | 1.74e+13 | 9.00e-02 | 1.24e+13 |
| FODO+sext CS + 0.3 shear in [1,3] | 2.54e-02 | 1.77e+13 | 8.78e-02 | 1.18e+13 |
| DBA CS + 0.3 shear in [1,3] | 4.17e-03 | 1.68e+13 | 5.40e-02 | 4.40e+13 |
| DBA+sext CS + 0.3 shear in [1,3] | 4.15e-03 | 1.68e+13 | 5.43e-02 | 4.74e+13 |
| TBA CS + 0.3 shear in [1,3] | 1.74e-03 | 1.64e+13 | 3.65e-02 | 5.02e+13 |
| TBA+sext CS + 0.3 shear in [1,3] | 1.73e-03 | 1.65e+13 | 3.67e-02 | 5.32e+13 |
| FODO CS + 1.0e-8 in [1,2] | 1.77e-10 | 1.46e+05 | 3.25e-10 | 1.37e+05 |
| DBA CS + 1.0e-8 in [1,2] | 1.39e-10 | 3.05e+05 | 1.53e-10 | 3.36e+05 |
| TBA CS + 1.0e-8 in [1,2] | 5.76e-11 | 2.15e+05 | 5.91e-11 | 2.60e+05 |
| FODO CS + 1.0e-10 in [1,2] | 1.77e-12 | 1.46e+03 | 3.25e-12 | 1.37e+03 |
| DBA CS + 1.0e-10 in [1,2] | 1.39e-12 | 3.05e+03 | 1.53e-12 | 3.36e+03 |
| TBA CS + 1.0e-10 in [1,2] | 5.76e-13 | 2.15e+03 | 5.91e-13 | 2.60e+03 |
| FODO CS + 1.0e-12 in [1,2] | 1.77e-14 | 1.46e+01 | 3.26e-14 | 1.37e+01 |
| DBA CS + 1.0e-12 in [1,2] | 1.39e-14 | 3.06e+01 | 1.54e-14 | 3.36e+01 |
| TBA CS + 1.0e-12 in [1,2] | 5.76e-15 | 2.15e+01 | 5.90e-15 | 2.59e+01 |

#### Derived defaults (rule: largest accepted ratio below one tenth, smallest rejected above ten)

##### symplectic_rtol for exact provenance (Frobenius form, defect_F)

- accepted fixtures: 129 values (6 cells raw+scaled, 39 oracle maps raw+scaled, 39 complex-step re-linearizations); largest defect_F = 1.88e-16 (repeated 2 scaled).
- rejected fixtures: 50 values (the 12 cell finite-difference matrices at both steps, raw+scaled; the 0.3 shears; the single-entry perturbations at 1e-8 and 1e-10); smallest defect_F = 5.76e-13 (TBA CS + 1.0e-10 in [1,2] raw).
- window: [10 x 1.88e-16, 5.76e-13 / 10] = [1.88e-15, 5.76e-14]; geometric mean 1.04e-14; one digit 1.0e-14 = 4.50e+01 eps.
- proposed default: 64 eps = 1.42e-14 (the Linear6D validator's constant, inside the window): largest accepted ratio 1.32e-02, smallest rejected ratio 4.06e+01.
- the 1e-12 single-entry perturbations (defect_F 5.76e-15 .. 3.26e-14, ratios to 64 eps 4.05e-01 .. 2.29e+00) are below what the Frobenius form can decide against the accepted maximum of 1.88e-16; the row-scaled form flags them (ratios 13.7 .. 33.6), which is why the design evaluates both forms.
- the finite-difference matrices of the LINEAR oracle maps are symplectic to roundoff (defect_F 2.02e-17 .. 1.58e-16, row ratio up to 2.42e-02): an FD matrix is refused by the provenance rule, never by the defect; they are not rejection fixtures of this rule.

##### row-scaled ratio (Linear6D validator form; accept iff row_ratio <= k)

- largest accepted ratio 1.08e-01; smallest rejected ratio 1.37e+01 (the 1e-12 perturbations, Table 6); window for k: [1.08e+00, 1.37e+00]; geometric mean 1.22e+00; one digit 1.0 = the validator's own verdict k = 1, which misses the one-tenth rule on the accepted side by 1.08e+00 x (margin 1/1.08e-01 instead of 10).

##### FD-input requirement

- cells: ||M_fd - M_cs||_F / (eps/(2h) ||M_cs||_F) ranges 7.90e-02 .. 4.24e+01; defect_F / (eps/(2h)) ranges 1.71e-02 .. 1.01e+00; error / declared step^2 ||M||_F ranges 8.43e-01 .. 1.43e+03.
- oracle linear maps (pure roundoff): FD error / (eps/(2h) ||M||_F) ranges 3.40e-09 .. 7.64e-06.
- candidate explicit tolerance for FD input, 10 (eps/(2 step) + step^2): 3.70e-09 at step 3.0e-7, 1.11e-09 at 1.0e-5; largest cell FD defect_F / candidate = 1.00e-02; the 0.3 shears (>= 1.7e-3) are rejected by >= 4.59e+05 x; a 1e-8 single-entry perturbation (5.8e-11 .. 1.8e-10) is NOT rejected at FD precision (ratio <= 4.86e-02), which is the price of a finite-difference input.
- two-arm map_uncertainty candidate max(step^2, eps/(2 step)) ||M||_F against the measured ||M_fd - M_cs||_F: ratio error/candidate ranges over the cells:
  7.90e-02 .. 4.71e+00 (the current one-arm formula: 8.43e-01 .. 1.43e+03).

##### closed_orbit_atol (scaled infinity norm of the fixed-point residual)

- accepted: 53 values (6 cells at the origin, 8 Newton-converged off-momentum orbits, 39 linear maps at the origin); largest scaled residual = 2.79e-16 (TBA at the origin); roundoff floor used when smaller: 6 eps = 1.33e-15.
- rejected: 12 values (the 1e-6 scan point and the 1e-4 tracked point on all six cells; Table 3 shows each moves the Jacobian by >= 2.6e8 rho_M0); smallest scaled residual = 7.93e-07 (FODO at P6 (1e-6, 0, 1e-6, 0, 0, 0)).
- window: [10 x 1.33e-15, 7.93e-07 / 10] = [1.33e-14, 7.93e-08]; geometric mean 3.25e-11; one digit: 3.0e-11. The window spans seven decades because the accepted side is the roundoff floor, so the midpoint is weakly determined.
- proposed roundoff-derived default: 64 eps max(1, ||M~||_F) on the scaled map (= 1.42e-14 at unit norm, 5.32e-14 .. 1.64e-13 on the cells; the lower window edge is 1.33e-14): largest accepted ratio 1.70e-03, smallest rejected ratio 5.78e+06.
- z component of a coasting cell's residual at delta != 0 is the path-length slip (Table 4: -3.9e-5 at delta 1e-4 on the DBA), not a closed-orbit defect: the fixed-point test must act on the transverse components when the (D23) coasting structure holds (open design item for stage 4).

### Appendix: the measurement scripts

`dump_oracle_maps.py` (run with `/opt/anaconda3_2024_02/bin/python3`; it imports the note's `verify_dispersion.py` from its directory):

```python
"""Dump the oracle maps of the canonical-dispersion note for the stage 1 measurement.

Imports the note's own verify_dispersion.py (its rotation, inverse_symplectic,
elementary_factors, S6, SEED, check_map) and replays run()'s fixture loop with
the SAME random-number consumption order (verify_dispersion.py lines 200-277):
per dense map one normal(6,6) for the normalizer and one for the transport
section; the prescribed-h maps draw nothing; the four repeated-betatron maps
and the defective spectator draw one normal(6,6) each; each coasting map draws
normal(4). Every map is passed through the oracle's check_map so a construction
drift would raise here instead of being measured downstream.

Run:  /opt/anaconda3_2024_02/bin/python3 dump_oracle_maps.py <out.tsv>
Columns: family, index, parameter, then the 36 row-major entries as
shortest round-trip reprs (exact for binary64).
"""
import hashlib
import platform
import sys
from pathlib import Path

import numpy as np
import scipy
from scipy.linalg import block_diag, expm

NOTE = Path('/home/cfsd/dxu/Paper/2026_twiss_dispersion/dispersion_note')
sys.path.insert(0, str(NOTE))
import verify_dispersion as vd  # noqa: E402

out = Path(sys.argv[1])
rows = []

def add(family, index, parameter, mat):
    rows.append([family, str(index), repr(parameter)] + [repr(float(v)) for v in mat.reshape(-1)])

rng = np.random.default_rng(vd.SEED)
for index in range(24):
    generator = rng.normal(size=(6, 6))
    generator = .12*(generator+generator.T)
    w = expm(vd.S6 @ generator)
    phases = [.47+.009*index, 1.6+.008*index, -.87-.003*index]
    traces = 2*np.cos(phases)
    mat = w @ block_diag(*map(vd.rotation, phases)) @ vd.inverse_symplectic(w)
    vd.check_map(mat, w, traces, phases[2])
    add('dense', index, phases[2], mat)
    rng.normal(size=(6, 6))  # the transport section generator: consumed, not dumped
phases = [.63, 1.74, -.94]
for index, h in enumerate([-2., -1., -.3, .05, .5, 1., 2.]):
    mz, me = vd.elementary_factors(np.array([1., .2, .1, 0.]), np.array([0., 1-h, 0., 0.]))
    w = mz @ me
    mat = w @ block_diag(*map(vd.rotation, phases)) @ vd.inverse_symplectic(w)
    vd.check_map(mat, w, 2*np.cos(phases), phases[2])
    add('prescribed_h', index, h, mat)
for index in range(4):
    gen = rng.normal(size=(6, 6))
    w = expm(.1*vd.S6 @ (gen+gen.T))
    ph = [.72, .72, -1.3]
    mat = w @ block_diag(*map(vd.rotation, ph)) @ vd.inverse_symplectic(w)
    vd.check_map(mat, w, 2*np.cos(ph), ph[2])
    add('repeated', index, ph[2], mat)
rr = vd.rotation(.72)
grouped = np.block([[rr, .2*rr], [np.zeros((2, 2)), rr]])
beta = grouped[np.ix_([0, 2, 1, 3], [0, 2, 1, 3])]
gen = rng.normal(size=(6, 6))
w = expm(.08*vd.S6 @ (gen+gen.T))
mat = w @ block_diag(beta, vd.rotation(-1.3)) @ vd.inverse_symplectic(w)
vd.check_map(mat, w, 2*np.cos([.72, .72, -1.3]), -1.3)
add('defective', 0, -1.3, mat)
for index, shear in enumerate([-.4, 0., .7]):
    eta = rng.normal(size=4)*.2
    mz, me = vd.elementary_factors(np.zeros(4), eta)
    w = mz @ me
    mat = w @ block_diag(vd.rotation(.57), vd.rotation(1.43), np.array([[1., shear], [0., 1.]])) @ vd.inverse_symplectic(w)
    vd.check_map(mat, w, np.array([2*np.cos(.57), 2*np.cos(1.43), 2.]))
    add('coasting', index, shear, mat)

header = ['family', 'index', 'parameter'] + [f'm{i}{j}' for i in range(1, 7) for j in range(1, 7)]
out.write_text('\n'.join(['\t'.join(header)] + ['\t'.join(r) for r in rows]) + '\n')
sha = hashlib.sha256((NOTE/'verify_dispersion.py').read_bytes()).hexdigest()
print(f'maps written: {len(rows)} -> {out}')
print(f'seed {vd.SEED}; python {platform.python_version()}; numpy {np.__version__}; scipy {scipy.__version__}')
print(f'verify_dispersion.py sha256 {sha}')
print('check_map evaluations by name:', {k: v["count"] for k, v in vd.CHECKS.items()})
```

`measure_stage1.jl` (package mode, `julia --startup-file=no --project=. --threads=4 measure_stage1.jl oracle_maps.tsv measurement_table.md`):

```julia
# Stage 1 measurement: symplectic defect (both forms), row-scaled ratio, rho_M0,
# and the fixed-point residual on the FODO, DBA, TBA cells of
# validation/lattice_cells.jl (rebuilt inline, same constants and the same
# stability scan) and on the oracle maps of the canonical-dispersion note
# (dumped by dump_oracle_maps.py), under complex step and central finite
# differences at two steps. Writes a markdown table and derives the
# roundoff-based defaults with the rule "largest accepted ratio below one
# tenth, smallest rejected above ten".
#
# Package mode (extensions active), from the repo root:
#   julia --startup-file=no --project=. --threads=4 measure_stage1.jl <oracle_maps.tsv> <out.md>
using Octopus, LinearAlgebra, Printf

const ORACLE_TSV = ARGS[1]
const OUT_MD = ARGS[2]
const EPS = eps(Float64)
const NST = 4
const ORDER = 4
const STEPS = (FiniteDifferenceLinearization().step, 1.0e-5)   # default (derived) and a coarse step
@assert STEPS[1] == 3.0e-7 "the derived default step moved; re-read SymplecticityContract"

# --- cells, verbatim from validation/lattice_cells.jl -------------------------
fodo_cell(kq) = (
    compile_runtime(QuadrupoleSpec(L=0.3, kn=(0.0, kq), nst=NST, integrator_order=ORDER)),
    compile_runtime(DriftSpec(L=1.2)),
    compile_runtime(QuadrupoleSpec(L=0.3, kn=(0.0, -kq), nst=NST, integrator_order=ORDER)),
    compile_runtime(DriftSpec(L=1.2)))
function dba_cell(kf, kd; Lb=1.0, angle=0.20)
    bend = compile_runtime(SBendSpec(L=Lb, h=angle / Lb, b0=angle / Lb, nst=NST, integrator_order=ORDER))
    qf = compile_runtime(QuadrupoleSpec(L=0.35, kn=(0.0, kf), nst=NST, integrator_order=ORDER))
    qd = compile_runtime(QuadrupoleSpec(L=0.25, kn=(0.0, kd), nst=NST, integrator_order=ORDER))
    d = compile_runtime(DriftSpec(L=0.6))
    return (qd, d, bend, d, qf, d, bend, d, qd)
end
function tba_cell(kf, kd; Lb=0.9, angle=0.14)
    bend = compile_runtime(SBendSpec(L=Lb, h=angle / Lb, b0=angle / Lb, nst=NST, integrator_order=ORDER))
    qf = compile_runtime(QuadrupoleSpec(L=0.3, kn=(0.0, kf), nst=NST, integrator_order=ORDER))
    qd = compile_runtime(QuadrupoleSpec(L=0.25, kn=(0.0, kd), nst=NST, integrator_order=ORDER))
    d = compile_runtime(DriftSpec(L=0.5))
    return (qd, d, bend, d, qf, d, bend, d, qf, d, bend, d, qd)
end
with_sextupole(cell; L=0.2, k2=8.0) =
    (cell..., compile_runtime(SextupoleSpec(L=L, kn=(0.0, 0.0, k2), nst=NST, integrator_order=ORDER)))
track_cell(cell, u) = foldl((c, e) -> e(c...), cell; init=u)
const S6 = kron(Matrix{Float64}(I, 3, 3), [0.0 1.0; -1.0 0.0])
function one_turn_jacobian(cell, u0)            # the script's inline closure: the independent witness
    J = zeros(6, 6)
    for j in 1:6
        u = ComplexF64[u0...]
        u[j] += 1e-30im
        J[:, j] = imag.(collect(track_cell(cell, Tuple(u)))) ./ 1e-30
    end
    return J
end
traces(J) = (abs(J[1, 1] + J[2, 2]), abs(J[3, 3] + J[4, 4]))
function find_stable(build, kfs, kds)
    best = nothing
    for kf in kfs, kd in kds
        cell = build(kf, kd)
        J = try
            one_turn_jacobian(cell, (1.0e-6, 0.0, 1.0e-6, 0.0, 0.0, 0.0))
        catch
            continue
        end
        all(isfinite, J) || continue
        tx, ty = traces(J)
        (tx < 2 && ty < 2) || continue
        score = max(tx, ty)
        (best === nothing || score < best[3]) && (best = (kf, kd, score))
    end
    return best
end
fodo_k = find_stable((kf, _) -> fodo_cell(kf), 0.3:0.05:1.6, (0.0,))
dba_k = find_stable(dba_cell, 0.6:0.1:3.0, -3.0:0.1:-0.2)
tba_k = find_stable(tba_cell, 0.6:0.1:3.0, -3.0:0.1:-0.2)
const CELLS = (
    ("FODO", fodo_cell(fodo_k[1])),
    ("FODO+sext", with_sextupole(fodo_cell(fodo_k[1]))),
    ("DBA", dba_cell(dba_k[1], dba_k[2])),
    ("DBA+sext", with_sextupole(dba_cell(dba_k[1], dba_k[2]))),
    ("TBA", tba_cell(tba_k[1], tba_k[2])),
    ("TBA+sext", with_sextupole(tba_cell(tba_k[1], tba_k[2]))),
)
const U0 = (1.0e-4, 2.0e-5, -0.8e-4, -1.5e-5, 1.0e-3, 2.0e-4)      # the script's tracked point
const P6 = (1.0e-6, 0.0, 1.0e-6, 0.0, 0.0, 0.0)                    # the script's scan point

# --- measurement helpers -------------------------------------------------------
e2(x) = @sprintf("%.2e", x)
"defect (both forms) raw and under :auto scaling, rho_M0 on the scaled map, and its winning arm"
function measure(M::AbstractMatrix; provenance_uncertainty=0.0)
    raw = Octopus._symplectic_defect(M)
    rec = Octopus._reciprocal_scaling(M, :auto)
    Ms = Octopus._scale_map(rec, M)
    sc = Octopus._symplectic_defect(Ms)
    rho = Octopus._perturbation_scale(Ms, sc.frobenius; provenance_uncertainty=provenance_uncertainty)
    arm = argmax(k -> rho.arms[k], keys(rho.arms))
    return (raw=raw, scaled=sc, rec=rec, Ms=Ms, rho=rho.scale, arm=arm, arms=rho.arms,
            normF=norm(M), norm2=opnorm(M, 2), condC=maximum(rec.factors)^2 / minimum(rec.factors)^2)
end
scaled_residual(rec, r) = maximum(abs, Octopus._scaling_matrix(rec) * collect(r))

io = IOBuffer()
pr(args...) = (println(io, args...); println(args...))

pr("# Stage 1 measurement table (generated by measure_stage1.jl)\n")
pr("Julia $(VERSION), $(Threads.nthreads()) threads, host $(gethostname()); eps = $(EPS).")
pr("Working points (same scan as validation/lattice_cells.jl): FODO kq=$(fodo_k[1]) | DBA kf=$(dba_k[1]) kd=$(dba_k[2]) | TBA kf=$(tba_k[1]) kd=$(tba_k[2]).")
pr("FD steps: $(STEPS[1]) (the derived default, SymplecticityContract().step) and $(STEPS[2]).\n")

# --- Table 1: cells at the origin, complex step --------------------------------
# every value travels with the name of its fixture, so the derivation names its own extremes
accepted_frob = Float64[]; accepted_row = Float64[]; acc_names = String[]
rejected_frob = Float64[]; rejected_row = Float64[]; rej_names = String[]
accepted_co = Float64[]; rejected_co = Float64[]; acc_co_names = String[]; rej_co_names = String[]
named_extreme(vals, names, f) = (i = f(vals); "$(e2(vals[i])) ($(names[i]))")
accepted_co_norm = Float64[]; rejected_co_norm = Float64[]
oracle_fd_frob = Float64[]; oracle_fd_row = Float64[]
cs_maps = Dict{String,Any}()
pr("## Table 1: cells at the origin, complex step (exact provenance)\n")
pr("| cell | elems | bit-identical to inline closure | ||M||_F | ||M||_2 | defect_F raw | row ratio raw | auto factors | cond C | defect_F scaled | row ratio scaled | rho_M0 (scaled) | winning arm | fp residual raw inf | fp residual scaled inf |")
pr("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
for (name, cell) in CELLS
    lm = one_turn_matrix(cell)
    M, prov = lm
    same = M == one_turn_jacobian(cell, ntuple(_ -> 0.0, 6))
    m = measure(M; provenance_uncertainty=prov.map_uncertainty)
    cs_maps[name] = (M=M, m=m)
    push!(accepted_frob, m.raw.frobenius, m.scaled.frobenius); push!(acc_names, "$name CS raw", "$name CS scaled")
    push!(accepted_row, m.raw.row_ratio, m.scaled.row_ratio)
    rres = maximum(abs, prov.fixed_point_residual)
    sres = scaled_residual(m.rec, prov.fixed_point_residual)
    push!(accepted_co, sres); push!(accepted_co_norm, norm(m.Ms)); push!(acc_co_names, "$name at the origin")
    pr("| $name | $(length(cell)) | $same | $(e2(m.normF)) | $(e2(m.norm2)) | $(e2(m.raw.frobenius)) | $(e2(m.raw.row_ratio)) | $(join(map(e2, m.rec.factors), ", ")) | $(e2(m.condC)) | $(e2(m.scaled.frobenius)) | $(e2(m.scaled.row_ratio)) | $(e2(m.rho)) | $(m.arm) | $(e2(rres)) | $(e2(sres)) |")
end

# --- Table 2: cells at the origin, finite differences --------------------------
pr("\n## Table 2: cells at the origin, central finite difference at two steps\n")
pr("The roundoff model is eps/(2h) with h = step (|q_j| <= 1 at the origin): the entrywise roundoff of a central difference relative to ||M||, which is what defect_F (normalized by ||M||_F^2) measures. declared = the provenance's step^2 ||M||_F.\n")
pr("| cell | step | ||M_fd - M_cs||_F | declared uncertainty | error / declared | roundoff model eps/(2h) ||M||_F | error / roundoff | defect_F raw | defect_F / (eps/2h) | row ratio raw | defect_F scaled | rho_M0 (scaled) | winning arm | fp residual raw inf |")
pr("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
fd_ratio_roundoff = Float64[]; fd_defect_over_model = Float64[]; fd_err_over_declared = Float64[]
for (name, cell) in CELLS, step in STEPS
    lm = one_turn_matrix(cell; method=FiniteDifferenceLinearization(step))
    M, prov = lm
    Mcs = cs_maps[name].M
    err = norm(M - Mcs)
    model = EPS / (2step) * norm(Mcs)
    m = measure(M; provenance_uncertainty=prov.map_uncertainty)
    push!(rejected_frob, m.raw.frobenius, m.scaled.frobenius); push!(rej_names, "$name FD step $step raw", "$name FD step $step scaled")
    push!(rejected_row, m.raw.row_ratio, m.scaled.row_ratio)
    push!(fd_ratio_roundoff, err / model); push!(fd_defect_over_model, m.raw.frobenius / (EPS / (2step)))
    push!(fd_err_over_declared, err / prov.map_uncertainty)
    pr("| $name | $(step) | $(e2(err)) | $(e2(prov.map_uncertainty)) | $(e2(err / prov.map_uncertainty)) | $(e2(model)) | $(e2(err / model)) | $(e2(m.raw.frobenius)) | $(e2(m.raw.frobenius / (EPS / (2step)))) | $(e2(m.raw.row_ratio)) | $(e2(m.scaled.frobenius)) | $(e2(m.rho)) | $(m.arm) | $(e2(maximum(abs, prov.fixed_point_residual))) |")
end

# --- Table 3: off-fixed-point expansion points (closed-orbit rejection fixtures)
pr("\n## Table 3: cells at points that are not fixed points, complex step\n")
pr("Scaled residual uses the origin's :auto scaling of the same cell. ||J(p) - J(0)||_F / rho_M0(0) says whether the Jacobian moved by more than the map's own roundoff scale (> 10 means the point must be rejected as a closed orbit).\n")
pr("| cell | point | fp residual raw inf | fp residual scaled inf | ||J(p) - J(0)||_F | / rho_M0(0) |")
pr("|---|---|---|---|---|---|")
for (name, cell) in CELLS, (pname, p) in (("P6 (1e-6, 0, 1e-6, 0, 0, 0)", P6), ("U0 (1e-4, 2e-5, -8e-5, -1.5e-5, 1e-3, 2e-4)", U0))
    M, prov = one_turn_matrix(cell; point=p)
    base = cs_maps[name]
    sres = scaled_residual(base.m.rec, prov.fixed_point_residual)
    dJ = norm(M - base.M)
    push!(rejected_co, sres); push!(rejected_co_norm, norm(base.m.Ms)); push!(rej_co_names, "$name at $pname")
    pr("| $name | $pname | $(e2(maximum(abs, prov.fixed_point_residual))) | $(e2(sres)) | $(e2(dJ)) | $(e2(dJ / base.m.rho)) |")
end

# --- Table 4: off-momentum closed orbit by a test-local Newton solve ------------
pr("\n## Table 4: dispersive cells at delta = 1e-4 and 1e-3, transverse closed orbit from a test-local Newton solve\n")
pr("Newton on (x, px, y, py) with z = 0 and pz = delta fixed, Jacobian from one_turn_matrix at the iterate, stopped when the transverse residual stops decreasing (at most 12 steps). The transverse residual at convergence is the roundoff a genuine fixed point leaves (an accepted fixture); the z component is the path-length slip of a coasting cell and is reported separately.\n")
pr("| cell | delta | iterations | x_co | px_co | transverse residual raw inf | transverse residual scaled inf | z residual raw (path slip) | defect_F scaled at the orbit | rho_M0 at the orbit |")
pr("|---|---|---|---|---|---|---|---|---|---|")
for (name, cell) in CELLS[3:6], delta in (1.0e-4, 1.0e-3)
    x = zeros(4)
    best = (Inf, x, 0, nothing)
    for it in 1:12
        p = (x[1], x[2], x[3], x[4], 0.0, delta)
        M, prov = one_turn_matrix(cell; point=p)
        r4 = collect(prov.fixed_point_residual)[1:4]
        rn = maximum(abs, r4)
        rn < best[1] && (best = (rn, copy(x), it, (M, prov)))
        rn == 0.0 && break
        x = x - (M[1:4, 1:4] - I) \ r4
    end
    rn, xco, it, (M, prov) = best
    m = measure(M)
    sres = maximum(abs, (Octopus._scaling_matrix(m.rec) * collect(prov.fixed_point_residual))[1:4])
    push!(accepted_co, sres); push!(accepted_co_norm, norm(m.Ms)); push!(acc_co_names, "$name Newton orbit at delta $delta")
    pr("| $name | $delta | $it | $(e2(xco[1])) | $(e2(xco[2])) | $(e2(rn)) | $(e2(sres)) | $(e2(prov.fixed_point_residual[5])) | $(e2(m.scaled.frobenius)) | $(e2(m.rho)) |")
end

# --- Table 5: oracle maps -------------------------------------------------------
lines = readlines(ORACLE_TSV)
hdr = split(lines[1], '\t')
oracle = map(lines[2:end]) do l
    f = split(l, '\t')
    (family=f[1], index=parse(Int, f[2]), parameter=f[3],
     M=permutedims(reshape(parse.(Float64, f[4:39]), 6, 6)))
end
pr("\n## Table 5: oracle maps of the canonical-dispersion note (bare matrices, then re-linearized as the callable u -> M u)\n")
pr("Seed 20260911, generated by dump_oracle_maps.py replaying verify_dispersion.py's fixture loop; every map passed the note's own check_map. CS = complex step of the linear callable (exact up to the 1e-30 scaling), FD at the two steps: for a linear map the FD error is pure roundoff, so error / (eps/(2h) ||M||_F) is the roundoff constant of the central difference itself.\n")
pr("| family | idx | parameter | ||M||_F | defect_F raw | row ratio raw | auto factors | defect_F scaled | row ratio scaled | rho_M0 (scaled) | arm | ||J_cs - M||_F | FD err/roundoff @3e-7 | FD defect_F raw @3e-7 | FD err/roundoff @1e-5 | FD defect_F raw @1e-5 |")
pr("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
oracle_fd_ratio = Float64[]
fam_max = Dict{String,Vector{Float64}}()
for o in oracle
    M = o.M
    m = measure(M)
    push!(accepted_frob, m.raw.frobenius, m.scaled.frobenius); push!(acc_names, "$(o.family) $(o.index) raw", "$(o.family) $(o.index) scaled")
    push!(accepted_row, m.raw.row_ratio, m.scaled.row_ratio)
    f = (u...) -> Tuple(M * collect(u))
    Jcs, pcs = one_turn_matrix(f)
    mcs = measure(Jcs)
    push!(accepted_frob, mcs.raw.frobenius); push!(acc_names, "$(o.family) $(o.index) CS re-linearized"); push!(accepted_row, mcs.raw.row_ratio)
    push!(accepted_co, maximum(abs, pcs.fixed_point_residual)); push!(accepted_co_norm, norm(mcs.Ms)); push!(acc_co_names, "$(o.family) $(o.index) linear map at the origin")
    fd = map(STEPS) do step
        J, p = one_turn_matrix(f; method=FiniteDifferenceLinearization(step))
        mm = measure(J; provenance_uncertainty=p.map_uncertainty)
        push!(oracle_fd_frob, mm.raw.frobenius); push!(oracle_fd_row, mm.raw.row_ratio)
        r = norm(J - M) / (EPS / (2step) * norm(M))
        push!(oracle_fd_ratio, r)
        (ratio=r, defect=mm.raw.frobenius)
    end
    push!(get!(fam_max, o.family, Float64[]), m.raw.frobenius, m.scaled.frobenius)
    pr("| $(o.family) | $(o.index) | $(o.parameter) | $(e2(m.normF)) | $(e2(m.raw.frobenius)) | $(e2(m.raw.row_ratio)) | $(join(map(e2, m.rec.factors), ", ")) | $(e2(m.scaled.frobenius)) | $(e2(m.scaled.row_ratio)) | $(e2(m.rho)) | $(m.arm) | $(e2(norm(Jcs - M))) | $(e2(fd[1].ratio)) | $(e2(fd[1].defect)) | $(e2(fd[2].ratio)) | $(e2(fd[2].defect)) |")
end
pr("\nPer-family maximum defect_F (raw and scaled): " * join(["$k $(e2(maximum(v)))" for (k, v) in sort(collect(fam_max))], "; ") * ".")

# --- Table 6: rejected symplectic fixtures ---------------------------------------
pr("\n## Table 6: non-symplectic fixtures (must be rejected)\n")
pr("| fixture | defect_F raw | row ratio raw | defect_F scaled | row ratio scaled |")
pr("|---|---|---|---|---|")
undecided_frob = Float64[]      # the 1e-12 perturbations: rejected by the row form, below the Frobenius form's resolution
function rej!(name, M; undecided=false)
    m = measure(M)
    push!(undecided ? undecided_frob : rejected_frob, m.raw.frobenius, m.scaled.frobenius)
    undecided || push!(rej_names, "$name raw", "$name scaled")
    push!(rejected_row, m.raw.row_ratio, m.scaled.row_ratio)
    pr("| $name | $(e2(m.raw.frobenius)) | $(e2(m.raw.row_ratio)) | $(e2(m.scaled.frobenius)) | $(e2(m.scaled.row_ratio)) |")
end
let M = Matrix{Float64}(I, 6, 6); M[1, 3] = 0.3; rej!("I + 0.3 e13 (design shear)", M) end
for (name, cell) in CELLS
    M = copy(cs_maps[name].M); M[1, 3] += 0.3; rej!("$name CS + 0.3 shear in [1,3]", M)
end
for pert in (1.0e-8, 1.0e-10, 1.0e-12), (name, cell) in (CELLS[1], CELLS[3], CELLS[5])
    M = copy(cs_maps[name].M); M[1, 2] += pert; rej!("$name CS + $pert in [1,2]", M; undecided=(pert == 1.0e-12))
end

# --- derived defaults -----------------------------------------------------------
one_digit(x) = round(x, sigdigits=1)
pr("\n## Derived defaults (rule: largest accepted ratio below one tenth, smallest rejected above ten)\n")
maxacc = maximum(accepted_frob); minrej = minimum(rejected_frob)
lo = 10maxacc; hi = minrej / 10
g = sqrt(lo * hi)
pr("### symplectic_rtol for exact provenance (Frobenius form, defect_F)\n")
pr("- accepted fixtures: $(length(accepted_frob)) values (6 cells raw+scaled, 39 oracle maps raw+scaled, 39 complex-step re-linearizations); largest defect_F = $(named_extreme(accepted_frob, acc_names, argmax)).")
pr("- rejected fixtures: $(length(rejected_frob)) values (the 12 cell finite-difference matrices at both steps, raw+scaled; the 0.3 shears; the single-entry perturbations at 1e-8 and 1e-10); smallest defect_F = $(named_extreme(rejected_frob, rej_names, argmin)).")
pr("- window: [10 x $(e2(maxacc)), $(e2(minrej)) / 10] = [$(e2(lo)), $(e2(hi))]; geometric mean $(e2(g)); one digit $(one_digit(g)) = $(e2(one_digit(g) / EPS)) eps.")
prop = 64EPS
pr("- proposed default: 64 eps = $(e2(prop)) (the Linear6D validator's constant, inside the window): largest accepted ratio $(e2(maxacc / prop)), smallest rejected ratio $(e2(minrej / prop)).")
pr("- the 1e-12 single-entry perturbations (defect_F $(e2(minimum(undecided_frob))) .. $(e2(maximum(undecided_frob))), ratios to 64 eps $(e2(minimum(undecided_frob) / prop)) .. $(e2(maximum(undecided_frob) / prop))) are below what the Frobenius form can decide against the accepted maximum of $(e2(maxacc)); the row-scaled form flags them (ratios 13.7 .. 33.6), which is why the design evaluates both forms.")
pr("- the finite-difference matrices of the LINEAR oracle maps are symplectic to roundoff (defect_F $(e2(minimum(oracle_fd_frob))) .. $(e2(maximum(oracle_fd_frob))), row ratio up to $(e2(maximum(oracle_fd_row)))): an FD matrix is refused by the provenance rule, never by the defect; they are not rejection fixtures of this rule.")
pr("\n### row-scaled ratio (Linear6D validator form; accept iff row_ratio <= k)\n")
racc = maximum(accepted_row); rrej = minimum(rejected_row)
pr("- largest accepted ratio $(e2(racc)); smallest rejected ratio $(e2(rrej)) (the 1e-12 perturbations, Table 6); window for k: [$(e2(10racc)), $(e2(rrej / 10))]; geometric mean $(e2(sqrt(10racc * rrej / 10))); one digit $(one_digit(sqrt(10racc * rrej / 10))) = the validator's own verdict k = 1, which misses the one-tenth rule on the accepted side by $(e2(racc / 0.1)) x (margin 1/$(e2(racc)) instead of 10).")
pr("\n### FD-input requirement\n")
pr("- cells: ||M_fd - M_cs||_F / (eps/(2h) ||M_cs||_F) ranges $(e2(minimum(fd_ratio_roundoff))) .. $(e2(maximum(fd_ratio_roundoff))); defect_F / (eps/(2h)) ranges $(e2(minimum(fd_defect_over_model))) .. $(e2(maximum(fd_defect_over_model))); error / declared step^2 ||M||_F ranges $(e2(minimum(fd_err_over_declared))) .. $(e2(maximum(fd_err_over_declared))).")
pr("- oracle linear maps (pure roundoff): FD error / (eps/(2h) ||M||_F) ranges $(e2(minimum(oracle_fd_ratio))) .. $(e2(maximum(oracle_fd_ratio))).")
fdtol(step) = 10 * (EPS / (2step) + step^2)
worst = 0.0
for (name, cell) in CELLS, step in STEPS
    M, prov = one_turn_matrix(cell; method=FiniteDifferenceLinearization(step))
    d = Octopus._symplectic_defect(M).frobenius
    global worst = max(worst, d / fdtol(step))
end
pr("- candidate explicit tolerance for FD input, 10 (eps/(2 step) + step^2): $(e2(fdtol(STEPS[1]))) at step $(STEPS[1]), $(e2(fdtol(STEPS[2]))) at $(STEPS[2]); largest cell FD defect_F / candidate = $(e2(worst)); the 0.3 shears (>= 1.7e-3) are rejected by >= $(e2(1.7e-3 / fdtol(STEPS[1]))) x; a 1e-8 single-entry perturbation (5.8e-11 .. 1.8e-10) is NOT rejected at FD precision (ratio <= $(e2(1.8e-10 / fdtol(STEPS[1])))), which is the price of a finite-difference input.")
pr("- two-arm map_uncertainty candidate max(step^2, eps/(2 step)) ||M||_F against the measured ||M_fd - M_cs||_F: ratio error/candidate ranges over the cells:")
lo_r = Inf; hi_r = 0.0
for (name, cell) in CELLS, step in STEPS
    M, prov = one_turn_matrix(cell; method=FiniteDifferenceLinearization(step))
    err = norm(M - cs_maps[name].M)
    cand = max(step^2, EPS / (2step)) * norm(M)
    global lo_r = min(lo_r, err / cand); global hi_r = max(hi_r, err / cand)
end
pr("  $(e2(lo_r)) .. $(e2(hi_r)) (the current one-arm formula: $(e2(minimum(fd_err_over_declared))) .. $(e2(maximum(fd_err_over_declared)))).")
pr("\n### closed_orbit_atol (scaled infinity norm of the fixed-point residual)\n")
maxco = maximum(accepted_co); minco = minimum(rejected_co)
floor_co = 6EPS
lo3 = 10max(maxco, floor_co); hi3 = minco / 10; g3 = sqrt(lo3 * hi3)
pr("- accepted: $(length(accepted_co)) values (6 cells at the origin, 8 Newton-converged off-momentum orbits, 39 linear maps at the origin); largest scaled residual = $(named_extreme(accepted_co, acc_co_names, argmax)); roundoff floor used when smaller: 6 eps = $(e2(floor_co)).")
pr("- rejected: $(length(rejected_co)) values (the 1e-6 scan point and the 1e-4 tracked point on all six cells; Table 3 shows each moves the Jacobian by >= 2.6e8 rho_M0); smallest scaled residual = $(named_extreme(rejected_co, rej_co_names, argmin)).")
pr("- window: [10 x $(e2(max(maxco, floor_co))), $(e2(minco)) / 10] = [$(e2(lo3)), $(e2(hi3))]; geometric mean $(e2(g3)); one digit: $(one_digit(g3)). The window spans seven decades because the accepted side is the roundoff floor, so the midpoint is weakly determined.")
form(n) = 64EPS * max(1.0, n)
acc_ratio = maximum(accepted_co ./ form.(accepted_co_norm)); rej_ratio = minimum(rejected_co ./ form.(rejected_co_norm))
pr("- proposed roundoff-derived default: 64 eps max(1, ||M~||_F) on the scaled map (= $(e2(form(1.0))) at unit norm, $(e2(form(minimum(rejected_co_norm)))) .. $(e2(form(maximum(rejected_co_norm)))) on the cells; the lower window edge is $(e2(lo3))): largest accepted ratio $(e2(acc_ratio)), smallest rejected ratio $(e2(rej_ratio)).")
pr("- z component of a coasting cell's residual at delta != 0 is the path-length slip (Table 4: -3.9e-5 at delta 1e-4 on the DBA), not a closed-orbit defect: the fixed-point test must act on the transverse components when the (D23) coasting structure holds (open design item for stage 4).")

write(OUT_MD, String(take!(io)))
println("\nwritten: ", OUT_MD)
```

## 2026-09-11: stage 2 landed (4D eigenmode route, Mais-Ripken, Edwards-Teng)

Stage 2 of the design note's staging: `feat(analysis)`. Registry snapshot
UNCHANGED (the eight new result structs are plain types, none a subtype of a
registry root). Nothing in this stage claims an analysis exists: no
`TwissDispersionAnalysis`, no `analyze`, `summarize_registry().analyses` is
still `[:PlaceholderAnalysis]`, the stage-guard testset of stage 1 stayed
green on the folded tree, and nothing new is exported (the public verb is
stage 4). Every kernel computes on the (already scaled) matrix it is given;
undetermined outputs are `Determined` values with a pinned reason from the
stage 1 vocabulary (no reason added).

### What landed

| File | Change | Content |
|---|---|---|
| `src/analysis/eigenmodes_4d.jl` | new, 651 lines, internal `_` names | `SpectrumReport4D` (always available: eigenvalues, moduli, unit-circle departure, unit-eigenvalue distance, the conjugate-class gap `g = min(abs(rho_j - rho_k), abs(rho_j - conj rho_k))`, trace, the (T7) and (E10) discriminants, `tau_+, tau_-`, `t14_holds`); `NormalModeFrame4D` (two oriented (E3)/(E4) vectors, eigenvalues `e^{-i mu_j}`, tunes in `[0, 2 pi)`, U_4 by (E6), the (E7) symplecticity residual, the (I1) reconstruction residual, projectors `P_j = -Im(u u') S`, covariances `G_j = Re(u u')`, signed areas (M1) with row and column sums (M2)/(M3), per-plane beta/alpha/gamma by (M1), both (M4) evaluations of u and their difference, `label_margin`); `Eigenmodes4D`; `_eigenmodes_4d(M; min_gap, stability_atol)` (both keywords required) with the PROVISIONAL guards `:unstable_spectrum`, `:unit_eigenvalue`, `:cluster_unresolved` and the `:unresolved_defective` branch, each marked for stage 3; `_orient_eigenvector`, `_mode_label_order` (mode 1 = larger kappa_jx), `_projected_twiss`; `_normal_coordinates`, `_mode_actions` (both (E9) evaluations); `ClosedFormEigenmodes4D` and `_closed_form_eigenmodes_4d(M; min_trace_gap, stability_atol)` ((E10)-(E14), guard `:singular_coefficient` at coincident traces, the (E12) sign by `tr G_j > 0`, its own (E6) normalizer and (I1) residual); `ClosedFormCheck4D` and `_closed_form_check_4d(frame; ...)` matching modes by eigenvalue trace (`_closed_form_mode_permutation`) and reporting `mode_permutation`, both `label_margins` and five differences. |
| `src/analysis/coupled_parameterizations.jl` | new, 851 lines, internal `_` names | Mais-Ripken: `MaisRipkenSet`, `_mais_ripken(u1, u2)` / `(U4)` ((M1)-(M5), (M6) phases as `Determined` with `:zero_projection` below `projection_rtol ||u_j||^2`, the (M7) rephasing, both (M4) evaluations), `_mais_ripken_normalizer` (M8), `_matched_covariance_4d` (M9, both expressions), `_mais_ripken_covariance` (M10)-(M16), `_mais_ripken_gamma_identities` (M13). Edwards-Teng: `EdwardsTengForm`, `EdwardsTengPair`; `_edwards_teng_from_normalizer` ((B10) by linear solves, (B5)/(B9), the second (B10) expression as `consistency_residual`), `_edwards_teng_from_map` ((T7)-(T9), (T11), (T15)/(T16), form 2 as the other sign of (T8) under the same labels, guards `:unstable_spectrum` and `:singular_coefficient`, `_map_route_label_sign`), `_edwards_teng_direct` (B11), `_edwards_teng_normalizer` ((B2)/(B6)), `_edwards_teng_V`, `_twiss_from_block`, `_twiss_block`; admissibility = `1 + det R > 0` of the reported form AND positive area weight, an inadmissible form `:form_inadmissible`; the (T5) residual against the caller's `M4`. Thin methods on `NormalModeFrame4D` for `_mais_ripken`, `_matched_covariance_4d`, `_edwards_teng_from_normalizer`, `_edwards_teng_from_map` (passing `mode_traces = 2 cos mu_j` so the frame's labels win), `_edwards_teng_direct` (reading the frame's `P_j`, `G_j`); no `kwargs...` splat, so a caller cannot override the frame's labels. |
| `src/Octopus.jl` | +5 lines | both includes right after `analysis/symplectic_linear_algebra.jl` (A before B), each with a one-line comment. |
| `test/runtests.jl` | +1197 lines | Part A block (lines 946-1531, 7 testsets) and Part B block (1533-2136, 7 testsets, incl. the Sagan-Rubin (T12) testset), pasted right after the stage-guard testset; both headers list the injected defects below and point at this record for the measured ratios. |

Not touched: the design note, the theory note, `docs/registry_snapshot.md`
(regenerated and byte-identical), `AGENTS.md` (its "placeholder-only today"
bullet is stale since stage 1 and is reworded in stage 4 by the design's
Staging item 4; the runner reviewer wanted it here, the repository reviewer
read the design as deferring it; recorded, not edited), `validation/`.

### Standalone verification on the folded and fixed tree (no lane, no gate)

Same conventions as stage 1 (`J` = `julia --startup-file=no`, OUT =
`result/twiss_impl_2026_09_11/stage2`, `ps` checked for `runtests`/`Pkg.test`
before every package-mode run). Counts are the fixer's final runs.

| run | command shape | result |
|---|---|---|
| Part A testsets, package mode | `J --project=REPO --threads=4 OUT/run_eig4d.jl` | 21872 pass / 0 fail (7 testsets: 38, 12602, 6891, 904, 28, 48, 1361), 17 s |
| Part B testsets, package mode | `J --project=REPO --threads=4 OUT/run_param.jl` | 45608 / 0 (7 testsets: 8018, 1208, 33862, 450, 101, 1969 and the loud-input checks), 19 s |
| suite extract: every analysis testset of `test/runtests.jl` 270-2136 (stage 1 kernel + vocabularies + stage guard, stage 2 A, stage 2 B), package + fdenv | `J --threads=4 OUT/fixer/extract/run_suite_extract.jl` | 69098 / 69098 in 24 testsets, 32 s; "Stage 1 claims no analysis" 34/34 |
| suite tripwires: "Architecture integrity" (incl. `validate_configuration_metadata()`), Core.Box allowlist, "Every export is documented", "No docstring is detached" | `OUT/fixer/extract/run_tripwires.jl` | 32 / 32 |
| script-mode smoke | `include("src/Octopus.jl"); using .Octopus; summarize_registry()` | exit 0, `analyses = [:PlaceholderAnalysis]`; `_mais_ripken` 3 methods, `_edwards_teng_direct` 3, `_edwards_teng_from_map` 2, `_edwards_teng_from_normalizer` 2 |
| snapshot and validators | `write_registry_snapshot()` then `git diff --quiet docs/registry_snapshot.md`; `validate_element_metadata()` | exit 0 (byte-identical); passed; undocumented exports `Symbol[]` |

Count history: Part A was 19448 in the worktree, 19451 after three fixture
assertions added under injection e01b, 21872 after the review fixes; Part B
was 40881 in the worktree, 44481 after the integrator's 18 thin-method
assertions on 200 maps, 45608 after the review fixes. The integrator's first
tripwire run was 31/32: a `Core.Box` at `_edwards_teng_from_map` (the label
sign assigned in two branches and captured by the `ntuple` closure), fixed by
the one-assignment helper `_map_route_label_sign` before any count above.

### Part A: eigenmode tolerances, every one `c eps kappa` with `c` measured

Probe `measure_eig4d.jl` (seed 20260911, the suite's own fixtures; the table
is reproduced verbatim under "Measurement tables"). Test thresholds for the
provisional guards: `min_gap = 1e-6`, `stability_atol = 1e-8`, closed form
`min_trace_gap = 1e-8`. Kappa vocabulary: `kq = max(1, ||M||_2) ||U||_2^2 / g`
is the design's chord amplifier (eigenvector direction error per eps, `g` the
conjugate-class gap), carried by every CROSS-mode identity; per-mode
identities carry the polynomial `||u||^2` or `||u||^4`; the closed form
carries `kc = max(1, ||M||^2) max(1, ||U||_F^2) (1 + 1/(2 root)) / root`
with `root = |tau_+ - tau_-|` (the (E11) division; the `1/(2 root)` is the
error of `tau_k` through the square root of the radicand), `kcf = kq ||U||_F^2 + kc`
for either route's error, `kcf / min sin^2 mu_j` for G-derived quantities
(`d sin = d tau / (2 sin)`) and `kcf / min |sin mu_j|` for the tune; scaling
rows carry `cond(C)^2 max(kq, kq~) max(||U||_F^2, ||U~||_F^2)` at `c = 1000`
(as stage 1's back-transformation rows); the FODO rows `kq ||U||_F^2 / |sin mu|`.

"ratio to used" = largest observed residual / the suite's threshold over the
fixture set; the rule wants it below one tenth on every accepted check.

| check family | c used | worst ratio to used (fixture) |
|---|---|---|
| (E3) normalization, (E7) symplecticity of U_4, (E8) reconstruction (I1), per-vector (I1) | 64 | 0.0226, 0.0185, 0.0586, 0.0732 (map 102: the largest of the whole part) |
| projectors: idempotent, complete, disjoint; `G_j = U_j U_j'` (c = 16); G positive semidefinite | 64 / 16 | 0.0205, 0.0173, 0.0131, 0.0132, 0.0226 |
| (M2) row sums, (M3) column sums, (M4) two evaluations of u, (M5) per plane, (M1) kappa against `(P S)_{a, pa}` (c = 16) | 64 / 16 | 0.0135, 0.0036, 0.0030, 0.0053, 0 (exact) |
| closed form: (E10) traces against `2 cos mu` / kc; P residuals, kappa and projector differences / kcf; covariance and outer-product differences, (E3) on the (E14) vector, G PSD margin, the (I1) residual on the closed form's own (E6) normalizer / (kcf / min sin^2); tune difference / (kcf / min sin) | 64 | 0.0031; 0.0072, 0.0033, 0.0107; 0.0018, 0.0012, 0.0006, 8.4e-5; 0.0005 (the covariance and outer rows peak on the detuned FODO, whose `kcf` is 1.2e4 from `g = 2.3e-3`) |
| actions (E9): xi against u, invariance under M | 64 | 0.0087, 0.0096 |
| scaling invariance of beta/alpha/gamma, kappa, tunes, P, G | 1000 | 0.0087, 7.5e-5, 9.6e-5, 2.8e-4, 0.0164 (map 17, `:auto`; measured 16.4 at c = 1, the same amplifier stage 1 met) |
| FODO (detuned) beta/alpha against T15, tune against the acos branch, `kappa_1y = kappa_2x = 0` | 64 | 1.8e-6, 2.8e-7, 0 |
| rotation fixture: tunes 0.7 and 0.31 (c = 16), phase-fixed `U_4 = I` | 16 / 64 | 0.0156, 0.0156 |

Lessons the implementer recorded while measuring: the cross-mode identities
first carried only `||U||^2` and needed c = 75 on map 190; the closed-form G
rows first carried `1/root` only and needed c = 6e5 on a tune-2e-5 map, 12.2
with `1/sin`; both now carry the amplifier that was missing. Before the fixer's
change the closed form's "reconstruction residual" was the (E14) sum, an
algebraic identity that measured 7.9e-16 on a matrix with symplectic defect 2.9;
it is now the (I1) residual on the closed form's own normalizer (0.00538 at
c = 1, 8.4e-5 of the threshold).

Rejected fixtures of the guards (value / threshold; every one landed in the
reason the test pins): `diag(2, 1/2, R(1.2))` departure 1 against 1e-8
(1e8, `:unstable_spectrum`); `diag(1 + 1e-6, 1/(1 + 1e-6), R(1.2))` 1e-6 (100);
the identity distance 0 (`:unit_eigenvalue`); `R(0.9) (+) R(0.9)`,
`R(0.9) (+) R(-0.9)` gap 0 (`:cluster_unresolved`, closed form
`:singular_coefficient`); the exact symmetric FODO gap 4.4e-16 (2.2e9);
`R(0.9) (+) R(0.9 + 1e-7)` gap 1e-7 (10.0, the deliberate 10x control, which
the closed form ACCEPTS at root 1.63e-7; Part D below).

The symmetric FODO of `validation/lattice_cells.jl` (kf = -kd = 1.6) is
exactly degenerate: `tr(F D Dq D) = tr(Dq D F D)` by cyclicity, so the x and
y tunes are equal (gap 4.4e-16, equal traces to 2e-16). The generic route
refuses it (`:cluster_unresolved`; closed form and map route
`:singular_coefficient`) and the tests pin that; the quantitative
Courant-Snyder comparison of benchmark 12.2-1 runs on the design's own
detuning `kd = -1.6 (1 + 1e-3)` (gap 2.3e-3, its "resolved" control), which is
still exactly uncoupled. The design's fixture row "uncoupled FODO: beta, alpha
equal `twiss()`" as written names the symmetric cell, which belongs to stage
3's definite-cluster path (`P_c = I_4`, individual modes a convention).

Convention facts pinned: for `R(2 pi 0.7)` the oriented member has
`Im(v'Sv) < 0`, `rho = e^{-i 2 pi 0.7}`, tune 0.7 (the rejected conjugate
would give 0.3). LAPACK's eigenvector phase is not zero on the rotation
fixture (`u_1 = (i, 1)`, so `U_1 = R(-pi/2)`): the test asserts rotation
diagonal blocks, zero off-diagonal blocks and `U_4 = I` after the Section 6.2
phase fix; "U_4 = I up to the (E6) column signs" holds only up to a rotation
of each column pair.

Injected defects (script-mode harness on a patched copy of `src/`, one exact
replacement each; the unpatched control was green at the count of its day;
e01a-e07 recorded from the worktree at 19448/19451 assertions and re-run
red on the folded tree by the runner reviewer, e08-e11 from the fixed tree
at 21872):

| id | injection | fails |
|---|---|---|
| e01a | orientation rule inverted (keeps the member with `Im(v'Sv) > 0`) | 4386 (4389 on the folded tree) |
| e01b | selection by `Im(rho) < 0` instead of `Im(v'Sv) < 0` (tune 0.3 on the 0.7 fixture) | 2 before, 5 after three fixture assertions were added |
| e02 | the minus of (E6) dropped, `U = [Re u, +Im u, ...]` | 1152 |
| e03 | (M1) signed area with Re instead of Im | 4034 |
| e04 | stability guard inverted (`departure < atol` rejects) | 215 fail + 6 errors of 267 reached (the accessor throws abort the testsets) |
| e05 | closed-form coincident-trace guard reduced to `radicand < 0` | 2 (the two exact equal-trace fixtures) |
| e06 | (E12) sign forced, `sj = s0` (tunes above one half lost) | 1 (2 on the folded tree) |
| e07 | the 1/2 of (E9) dropped in the eigenvector evaluation | 151 |
| e08 | closed-form check matched mode j to mode j by label instead of by trace | 9 / 21872 (the det R = 1 label-tie fixtures) |
| e09 | the minus of (E6) dropped in the closed form's own `U_cf` | 403 / 21872 |
| e10 | `from_vectors` aliased to `from_normal_coordinates` in `_mode_actions` | 99 / 21872 |
| e11 | all five `ClosedFormCheck4D` differences set to 0.0 | 1009 / 21872 |

The scaling testset went red only through the shared frame (e01a, e03): it
compares two frames of the same code and cannot see a symmetric defect on
its own, so it is not an independent witness of the frame.

### Part B: Mais-Ripken and Edwards-Teng tolerances, `c = 64` unless stated, measured

Probe `measure_param.jl` (the file-level helpers of the Part B block, so the
eigen frames are Part A's; table verbatim under "Measurement tables"). It
prints, per check family, the largest residual / (eps kappa) = the c the check
REQUIRES with the argmax fixture's own name, and `64 / required` = the margin
of the suite's constant. Kappa families: `nU = ||U||_F^2` (identities
quadratic in U), `nU^2` for the (M5) quartic, `1 / min beta_ja` where (M8) or
(M11)-(M16) divide by `sqrt(beta)`, `kR = nU / |w|` for the (B10) solve that
divides a block by its determinant `w`, `kq` (Part A's chord) whenever the map
route is compared with a frame-based route, `kT = 1 / min |sin mu_j|` for
(T15), `sR = max(1, ||R||)`, `nM = max(1, ||M||_F)`.

| check family | required c (argmax fixture) | margin 64 / required |
|---|---|---|
| Mais-Ripken on 200 normalizers: (M2), (M3), (M4), (M5), phase norm, rephasing, (M8) rebuild / symplecticity / (I1), (M9) two forms, (M12) vs (M9), (M13), closure `M Sigma M' = Sigma` | 0.05 .. 1.09 (worst: (M9) two forms, normalizer 50) | 59 .. 1680 |
| Edwards-Teng, three routes on 200 maps: R, weights, blocks, Twiss and tunes agree pairwise; `det R_1 det R_2 = 1`, `R_2 = -R_1 / det R_1`; `lambda^2 = w`; unit area of each Q_j; (T5) on every route; V symplectic; (T1) rebuild; (T11) traces; `Uet` (I1); phases against (M6); the 7.2/7.3 conversion tables; (M8) -> (B10) R and (B5)/(B9) Twiss | 0.02 .. 4.99 (worst: "twiss n-d", map 134; next "twiss n-m" 1.74, "T11 trace" 1.66) | 12.8 .. 3120 |
| (B10) consistency residual `||adj(R) - U_x U_y^{-1}||` (two solves each dividing by w, adj of a solved R) | 12.4 (map 8) | 5.2 at c = 64, so the suite checks it at `4c = 256` (margin 20.7) |
| coupled construction (benchmark 12.2-2), 8 cases x 3 routes: R, lambda, weight, beta, alpha, mu, (T5), u, the other form's det and lambda^2, tunes | 0.003 .. 0.19 | 340 .. 18400 |
| detuned FODO against Courant-Snyder (beta, alpha, mu), `kappa_1y = kappa_2x = 0`, R = 0, lambda = 1, form-2 weight 0 | <= 5.7e-5 | >= 1.1e6 |

Rule check: at c = 64 the largest accepted ratio is 0.078 ("twiss n-d",
map 134) and at c = 256 the (B10) consistency ratio is 0.048; every family
is below one tenth. Rejected side: the exact FODO's `sqrt(Delta) = 2.2e-16`
against the 1e-8 guard (4.5e7); the detuned cell's 2.86e-3 is accepted at
2.9e5 times the guard. On the exactly uncoupled cell LAPACK returns plane
eigenvectors, so R, u, the form-2 weight and the secondary projections are
EXACT zeros there; the det R = 0 coupled construction's zero weight arrives
at 15 eps through the eigen frame, which is why the floor `weight_rtol` was
raised from 64 eps to 256 eps after the first measurement (Part D re-measures
both floors per route below).

Derivations the tests rest on (recorded by the implementer; the tests pin
every line): form 2 from the map is the other sign of (T8) under the SAME
labels (`V_2(R) = V_1(R) P` with P the column-pair swap exchanges the blocks;
cross-checked from (B2): `R_2 = -adj(R_1)^{-1} = -R_1 / det R_1`,
`det R_2 = 1 / det R_1`). With `u = kappa_1y`: form 1 weight `1 - u =
1/(1 + det R_1)`, form 2 weight `u = 1/(1 + det R_2)`, so form 1 is admissible
iff `u < 1`, form 2 iff `u > 0`; an UNCOUPLED cell under the x-first labelling
has exactly one admissible form (form 2 has weight 0 and no finite R), the
other labelling makes form 2 the admissible one: the dossier's "both forms
admissible" holds across the two labellings, not within one, and the test
asserts exactly that. `XYCouplingSpec` mode A on (x, px, y, py) is exactly
`V_1(Rm)` of (T2)/(T3) with `Rm = [r1 r2; r3 r4]`, `g = 1/sqrt(1 + det Rm)`,
mode B is `V_2(Rm)`; the design row `det R in (-0.5, 0, 0.3, 1)` is realized by
`(r1, r2, r3, r4) = (0.5, 0.5, 1.5, 0.5)`, `(0.4, 0.2, 0.6, 0.3)` (rank one),
`(0.5, 0.2, -0.1, 0.56)`, `(0.8, 0.3, -0.6, 1.025)`; inverses `V_1(R)^{-1} =
V_1(-R)` (mode A with the negated r's) and `V_2(R)^{-1} = V_2(adj R)` (mode B
with `(r4, -r2, -r3, r1)`). Expected from the construction: `R = Rm`,
`lambda = 1/sqrt(1 + det Rm)`, `(beta_j, alpha_j, mu_j)` the optics form's,
`u = det Rm / (1 + det Rm)` (form 1) or `1 / (1 + det Rm)` (form 2).

Injected defects (`OUT/inject_all_B.sh`, one exact string replacement each,
refused unless the old string occurs once; b01-b10 recorded from the worktree
at 40881 assertions and re-run red on the folded tree by the runner reviewer
at 44481; b11-b15 from the fixed tree at 45608):

| id | injection (theory label) | fails / errors |
|---|---|---|
| b01 | (M1) signed area with Re instead of Im | 2730 / 7 |
| b02 | (M6) zero-projection floor inverted | 6 / 4 |
| b03 | (B10) `R = +U_y U_x^{-1}` (the minus dropped) | 4200 / 0 |
| b04 | admissibility from the sign of det R alone (weight and `1 + det R` ignored) | 57 / 3 |
| b05 | form-2 map-route denominator `D + s sqrt(Delta)` (same as form 1) | 2945 / 2 |
| b06 | (B11) form 2 divided by `kappa_1x = 1 - u` instead of `kappa_2x = u` | 379 / 2 |
| b07 | (M8) entry `-sqrt(beta_1y) sin nu_1` with a plus | 611 / 1 |
| b08 | (M16) `u(1 - u)` term dropped | 100 / 0 |
| b09 | (T15) `sin mu` forced positive | 24 / 0 |
| b10 | map-route coincident-trace guard reduced to `sqrt(Delta) < 0` | 3 / 0 |
| b11 | `area_weight = NaN` restored on the map route's guard path | 2 / 45608 |
| b12 | the `Real` test of `_check_tunes` dropped (a String pair gives a MethodError) | 2 / 45608 |
| b13 | `kwargs...` restored on `_edwards_teng_from_map(frame)`: a caller's `mode_traces` wins silently | 1 / 45608 |
| b14 | normalizer route ignores `M4` and measures its own (E8) rebuild | 373 / 45608 |
| b15 | direct route ignores `M4` and measures its own (E14) rebuild | 373 / 45608 |

Not injected, with the reason: the `weight > 0` conjunct of admissibility
cannot be shown red alone because under fixed labels `1 + det R = 1 / weight`
for both routes, so the two conditions are algebraically equivalent; the code
keeps both because the design states both, and b04 shows the pair red against
"the sign of det R alone".

### Review findings and fixes (four reviewers: theory, repository facts, runner, tests)

Sixteen findings, every runtime claim reproduced before it was acted on
(`OUT/fixer/verify_findings.log`). Thirteen source or test fixes, all within
the design's decisions (eigenvector route primary, closed form a cross-check
whose disagreement is reported, guards provisional, no new reason, no export):

1. (theory, major) The closed-form check compared mode j to mode j by label;
   at a label tie (u = 1/2, det R = 1) the two routes' labels can cross and
   an O(1) "disagreement" between identical modes was reported
   (`tune_difference` 2.07 on the det R = 1 design row). Fixed: modes are
   matched by eigenvalue trace (`_closed_form_mode_permutation`), the check
   reports `mode_permutation` and both `label_margins`; the closed-form
   testset is restructured around one `check_agreement`, asserts
   `n_labels_clear == 200` on the manufactured maps and `n_tie_clear == 0`
   on two tie fixtures (the det R = 1 design row through `V_1(R)`, a
   45-degree roll of an uncoupled cell). Injection e08.
2. (theory) The closed form's `reconstruction_residual` was the (E14) sum,
   an identity that holds for any matrix (7.9e-16 at symplectic defect 2.9;
   8.1e-17 against the frame's 8.7e-7 on a 1e-6 perturbation). Fixed: the
   (I1) residual `_invariance_residual(M, U_cf, diag(R(mu)))` on the closed
   form's own (E6) normalizer (new field `normalizer`); the docstring records
   why the sum is not reported; the test pins the field to its recomputation.
   Injection e09.
3. (theory + repo) `SpectrumReport4D` docstring said `diag(2, 1/2, R(1.2))`
   satisfies (T14); it has `tau_+ = 2.5` and `t14_holds = false`. Reworded.
4. (repo) `_check_tunes` gave a `MethodError` on a String pair; now an
   `ArgumentError` ("two finite reals"). Injection b12.
5. (repo) The 64 eps `||v||^2` floor of the `:unresolved_defective` branch
   was unmarked: now commented PROVISIONAL and unmeasured (no fixture reaches
   it past the three guards; stage 3 owns the fixture).
6. (repo) The Part A test header listed e01 while the record has e01a/e01b;
   split, and both headers now carry e08-e11 / b11-b15 with counts.
7. (tests) The (T5) residual was never pinned against the caller's `M4`:
   now `== _invariance_residual(M, V_form(R), blockdiag(blocks))` on all
   three routes. Injections b14, b15.
8. (tests) The second (E9) evaluation could have been a copy of the first:
   `from_vectors` is pinned to its formula. Injection e10.
9. (tests) The five `ClosedFormCheck4D` differences were only bounded: each
   is asserted `==` its recomputation over the matched modes. Injection e11.
10. (tests) `area_weight` was `NaN` on the map route's guard path: now 0.0
    with the reason on R / det_R / lambda (not made `Determined`: every
    `area_weight` test compares a plain Float64). Injection b11.
11. (tests) The Sagan-Rubin loop never pinned its count: `n_sr == 100`.
12. (runner) The frame thin methods accepted `kwargs...`, so a caller's
    `mode_traces` or `tunes` silently overrode the frame's labels (swapped R
    and Twiss returned without error). Splat removed on all four, the one
    remaining keyword spelled out; `mode_traces` / `tunes` now a
    `MethodError`. Injection b13.
13. (integrator) `Core.Box` at `_edwards_teng_from_map` (above).

Skipped, with reasons: the test headers pointing at this record (fixed by
this append landing in the same commit as the tests: a sequencing constraint,
not a tree edit); the integrator's stale line numbers (a git-ignored report);
the `AGENTS.md` "placeholder-only today" wording (design Staging item 4 defers
it to stage 4; the two reviewers disagreed, recorded above); the `Inf` values
of `_mais_ripken_gamma_identities` at a zero beta and of the normalizer
route's `consistency_residual` at the floor (documented and asserted; a
`Determined` shape for them is a stage 4 result-shape decision, open).

### Part D: measurement of every stage-2 multiplier and provisional guard on the fixtures

Fixtures: the 200 manufactured stable 4x4 maps of the design's verification
plan (seed 20260911), the 200 manufactured normalizers of Part B (seed
20260912), the detuned FODO (`kd = -1.6 (1 + 1e-3)`), the rotation
`R(2 pi 0.7) (+) R(2 pi 0.31)`, the two label-tie fixtures of the closed-form
testset (the det R = 1 design row through `V_1(R)`, the 45-degree roll), the
eight coupled constructions of benchmark 12.2-2 (212 accepted frames); the
seven guard fixtures of the Part A testsets (rejected); the zero-projection
fixtures of the Part B testsets. Driver `measure_stage2.jl` (package mode)
runs the two probes above in place (their tables are its Tables A and B,
verbatim), then measures the guard quantities on every fixture (Table D1),
the two provisional floors per route on Part A's frames (Table D2), the
REJECTED side of the `c eps kappa` checks (Table D3: the residual a wrong
quantity produces on the accepted frames, divided by the suite's threshold;
the injections show the same defects red through the tests, this table shows
by how much) and the one-tenth rule over every check (Table D4), and derives
the windows. Every extreme is printed with the name of the fixture that
produced it, taken from the data.

Commands (from the repository root; package mode):

```bash
julia --startup-file=no --project=. --threads=4 measure_stage2.jl measurement_table.md
```

The three scripts are reproduced in the appendix of this section; until stage
6 moves them under `validation/`, this record is their committed home. The
Part B probe copy differs from the worktree original in one line (the include
path of the test helpers, `..`).

Iterations of the driver, kept visible because each was a classification
error of the kind stage 1 also met: (1) the exactly uncoupled fixtures were
counted on the ACCEPTED side of the projection floor (their secondary
projections are exact zeros, i.e. rejected) and the zero-weight form was
assigned by the constructing form instead of by the frame's labels (under
"mode 1 = larger x-area" a zero weight is always form 2; the first table
reported a "rejected" weight of 1); (2) the rejected side of the (B10) sign
and of the gamma formula was measured on fixtures where the wrong formula
coincides with the right one (`R = 0` has no sign; on a plane with
`kappa^2 = 1` the wrong gamma `(1 + alpha^2)/beta` IS the (M1) gamma, and the
det R = -0.5 form-2 construction has such a plane by algebra, `u = 2`,
`1 - u = -1`), reporting rejected ratios 0, 0.034, 0.104 before the witness
condition `|1 - kappa^2| > 64 eps kq ||U||^2` was stated and its 12 excluded
planes counted; (3) the e08 rejected row first looked for maps whose label
match is crossed and found none of 200 (both routes label alike), so it now
measures the residual of the WRONG mode assignment on every frame (107 at
its smallest, map 50), and the sin-branch row first ran over the 200 maps,
none of which has a tune above one half (the rotation, tie and construction
fixtures supply 11 such modes).

### Derived windows (rule: largest accepted ratio below one tenth, smallest rejected above ten; arithmetic in the "Derived windows" block of the table)

Nothing here is frozen: every guard and floor is a PROVISIONAL test choice
that stage 3 replaces (`min_gap` by the resolution chord, `stability_atol` by
the per-cluster Schur-block test) or stage 4 shapes.

| threshold | test choice | window from the rule | accepted extreme (ratio) | rejected extreme (ratio) |
|---|---|---|---|---|
| `min_gap` (frame, reject iff `g <= min_gap`) | 1e-6 | [10 x 1e-7, 2.26e-3 / 10] = [1e-6, 2.26e-4], geometric mean 1.5e-5; the choice sits AT the lower edge because `R(0.9) (+) R(0.9 + 1e-7)` was built as its 10x control | smallest g 2.26e-3 (detuned FODO; 0.032 on the manufactured maps, map 8), ratio 4.4e-4 | largest g 1e-7 (the 1e-7 control), ratio 10.0; exact FODO 4.4e-16 (2.3e9), equal pairs 0 |
| `stability_atol` (frame, reject iff departure > atol) | 1e-8 | [10 x 7.55e-15, 1e-6 / 10] = [7.6e-14, 1e-7], geometric mean 8.7e-11 | largest departure 7.55e-15 (construction det -0.5, form 2), ratio 7.6e-7 | smallest departure 1e-6 (`diag(1 + 1e-6, ...)`), ratio 100; `diag(2, 1/2, ...)` 1e8 |
| `min_trace_gap`, closed form (reject iff root <= gap) | 1e-8 | [10 x 0, 2.86e-3 / 10] = [0, 2.86e-4]; with the 1e-7 control counted as rejected [1.63e-6, 2.86e-4], which EXCLUDES 1e-8 | smallest root 2.86e-3 (detuned FODO), ratio 3.5e-6 | every `:singular_coefficient` fixture has root 0 (equal pairs, the identity, the exact FODO), ratio Inf |
| `min_trace_gap`, map route ((T9) conditioning, reject iff `sqrt(Delta) <= gap`) | 1e-8 | [10 x 2.22e-16, 2.86e-3 / 10] = [2.2e-15, 2.86e-4], geometric mean 8.0e-10 | smallest `sqrt(Delta)` 2.86e-3 (detuned FODO), ratio 3.5e-6 | largest 2.22e-16 (exact FODO), ratio 4.5e7 |
| `projection_rtol` (M6 floor, relative to `||u_j||^2`) | 64 eps = 1.42e-14 | [0, 1.56e-4]: the rejected side (820 accepted projections, 8 rejected: the identity normalizer, the rank-one `Ur` exactly and through the eigen frame, the detuned FODO and the rotation through the eigen frame) is EXACTLY zero on every fixture, so the lower edge is the roundoff floor and the default is a roundoff-scale choice | smallest genuine projection 1.56e-3 (map 136 mode 1), ratio 9.1e-12 | 0, ratio Inf |
| `weight_rtol` (zero area weight; normalizer route relative to `||U_x||^2`, direct route absolute on `kappa_jx`, map route relative to `|D| + sqrt(Delta)`) | 256 eps = 5.68e-14 | normalizer [4.97e-14, 3.72e-5]; direct [3.33e-14, 2.32e-4]; map [9.98e-15, 2.33e-4]; the default is inside all three | smallest nonzero weight 3.7e-4 (map 50 form 1, normalizer route), 2.3e-3 (map 180 form 2, direct and map routes) | the det R = 0 constructions' zero form through the eigen frame: 4.97e-15 (normalizer, ratio 11.4), 3.33e-15 (direct, 17.1), 9.98e-16 (map, 57); the uncoupled cells 0 exactly |

The 1e-7 control: the frame refuses `R(0.9) (+) R(0.9 + 1e-7)` (g = 1e-7)
while both trace guards accept it (root 1.63e-7, `sqrt(Delta)` 1.57e-7
against 1e-8). The two guard families measure different quantities (an
eigenvalue gap against a trace gap, which scale alike here but need not near
a tie of the OTHER kind, `R(a) (+) R(-a)`, where the traces coincide while the
eigenvalues are conjugate pairs at distance 0 in the conjugate class); the
frame is the primary route and the closed form and map route are
cross-checks, so the disagreement is recorded, not reconciled. The
`weight_rtol` margin on the normalizer route (11.4 against the required 10)
is the thinnest of the stage and rests on ONE near-miss fixture; a
`Determined` weight rather than a floor is a stage 4 shape question.

The one-tenth rule over the `c eps kappa` checks (Table D4): Part A's worst
accepted ratio is 0.0732 (the per-vector (I1) residual, map 102), Part B's
0.078 ("twiss n-d", map 134) at c = 64 and 0.048 for the (B10) consistency
residual at c = 256; the rejected side (Table D3) is at least 107 (the wrong
mode assignment of the closed-form check, map 50) and otherwise 8.6e5 or
more. Not measured: the 64 eps `||v||^2` floor of the `:unresolved_defective`
branch (no fixture reaches it; stage 3).

Open items recorded for the next stages (this record edits neither note):

1. Stage 3: the symmetric FODO of `validation/lattice_cells.jl` is exactly
   degenerate and belongs to the definite-cluster path; the design's fixture
   row for benchmark 12.2-1 names it and should say so, and the detuned
   control (1e-3) is what stage 2 tests. Pitfall 13's trial-012 control
   (g = 2.13e-9 at detuning 1e-9) must be a fixture of the chord table.
2. Stage 3: a fixture for the `:unresolved_defective` branch (a near-defective
   Jordan-type map with a tiny `min_gap`) and the Schur-block test that
   replaces its floor; the raw-modulus `stability_atol` is sqrt-sensitive
   near +-1.
3. Stage 4 (result shape): labels at a tie (`label_margin = 0`, no
   `Determined`); the `Inf` gamma identities at a zero beta and the
   normalizer route's `consistency_residual` at the floor; a `Determined`
   area weight; whether form 2 is presented as form 1 with exchanged labels
   ((T4) reading), since under one labelling an uncoupled cell has exactly
   one admissible form; one status for coincident traces across routes
   (frame `:cluster_unresolved`, closed form and map route
   `:singular_coefficient`; no reason was added); the `AGENTS.md`
   "placeholder-only today" bullet (Staging item 4).

### Not verified in stage 2

- No lane and no gate ran on this tree; every count above is standalone. The
  full gate on the assembled batch is owed before the push and is recorded in
  this file when it runs. After the ledger edits of Part D (this section, the
  todo row, the README entry, the experiences bullet) the four suite
  tripwires were re-run in package mode: 32/32.
- `validation/tracking_backend_consistency.jl` and `validation/lattice_cells.jl`
  were not run (no kernel, element or tracking code changed; pure host matrix
  algebra, nothing CUDA-reachable).
- The Part A/B injections e01a-e07 and b01-b10 were re-run on the folded tree
  by the runner reviewer (every one red, counts above); e08-e11 and b11-b15
  ran on the fixed tree; none was re-run after the ledger edits (markdown
  only).
- The `:unresolved_defective` branch and its floor (no fixture).
- The closed-form and map-route guards were not exercised on a coincident
  trace of the `R(a) (+) R(-a)` kind with UNEQUAL eigenvalue classes (none
  exists in 4D: equal traces of two stable modes mean equal or conjugate
  eigenvalue pairs), so the "different quantities" remark above is an
  argument, not a measurement.

### Measurement tables (output of `measure_stage2.jl`, verbatim; the fenced blocks are the two probes' stdout)

#### Contents

#### Part A probe (measure_eig4d.jl), stdout verbatim

```

| check | required c (max ratio / eps kappa) | argmax fixture | max raw | c used | ratio to used |
|---|---|---|---|---|---|
| E3 normalization |u'Su+2i| / ||u||^2 | 1.45 | manufactured map 112 | 8.88e-16 | 64 | 0.0226 |
| E7 ||U'SU-S|| / (kq ||U||^2) | 1.18 | manufactured map 80 | 3.42e-15 | 64 | 0.0185 |
| E8 (I1) normalized / max(1,||M||) | 3.75 | manufactured map 50 | 2.51e-15 | 64 | 0.0586 |
| FODO beta,alpha vs T15 / kfodo | 0.000113 | FODO plane 2 | 4.88e-15 | 64 | 1.76e-06 |
| FODO kappa_1y, kappa_2x / ||U||^2 | 0 | FODO | 0 | 64 | 0 |
| FODO tune vs acos branch / kfodo | 1.8e-05 | FODO plane 2 | 7.77e-16 | 64 | 2.81e-07 |
| G = U_j U_j' / ||U||^2 | 0.212 | manufactured map 181 | 4.44e-16 | 16 | 0.0132 |
| G PSD: -eigmin(G) / ||G|| | 1.45 | manufactured map 180 | 9.58e-16 | 64 | 0.0226 |
| M2 row sums / ||u||^2 | 0.866 | manufactured map 129 | 4.44e-16 | 64 | 0.0135 |
| M3 column sums / (kq ||U||^2) | 0.231 | manufactured map 80 | 6.66e-16 | 64 | 0.0036 |
| M4 u difference / (kq ||U||^2) | 0.192 | manufactured map 80 | 5.55e-16 | 64 | 0.003 |
| M5 |bg-a^2-k^2| / ||u||^4 | 0.338 | manufactured map 174 | 7.44e-15 | 64 | 0.00528 |
| P complete ||P1+P2-I|| / (kq ||U||^2) | 1.11 | manufactured map 80 | 3.2e-15 | 64 | 0.0173 |
| P disjoint ||P1P2|| / (kq ||U||^2) | 0.837 | manufactured map 80 | 2.42e-15 | 64 | 0.0131 |
| P idempotent ||P^2-P|| / ||P||^2 | 1.31 | manufactured map 131 | 6.81e-16 | 64 | 0.0205 |
| R(0.7)+R(0.31) phase-fixed U = I / 1 | 1 | rotation | 2.22e-16 | 64 | 0.0156 |
| R(0.7)+R(0.31) tunes / 1 | 0.25 | rotation | 5.55e-17 | 16 | 0.0156 |
| actions invariance / (||U||^2 max(1,||M||)^2 ||r||^2) | 0.611 | map 2 point 3 | 1.33e-14 | 64 | 0.00955 |
| actions xi vs u / (||U||^2 ||r||^2) | 0.556 | map 16 point 1 | 7.11e-15 | 64 | 0.00868 |
| cf (I1) on E14 normalizer / (kcf/min sin^2) | 0.00538 | manufactured map 133 | 2.38e-15 | 64 | 8.4e-05 |
| cf E10 traces vs 2cos(mu) / kc | 0.2 | manufactured map 177 | 9.99e-16 | 64 | 0.00312 |
| cf E3 on E14 vector / (kcf/min sin^2) | 0.0784 | R(0.7)+R(0.31) | 1.55e-14 | 64 | 0.00123 |
| cf G PSD margin / (kcf/min sin^2) | 0.0367 | manufactured map 62 | 4.46e-14 | 64 | 0.000573 |
| cf P residuals / kcf | 0.461 | manufactured map 134 | 1.77e-12 | 64 | 0.0072 |
| cf covariance diff / (kcf/min sin^2) | 0.116 | detuned FODO kq=1.6, eps=1e-3 | 9.93e-10 | 64 | 0.00181 |
| cf kappa diff / kcf | 0.214 | manufactured map 36 | 5.4e-14 | 64 | 0.00334 |
| cf outer diff / (kcf/min sin^2) | 0.104 | detuned FODO kq=1.6, eps=1e-3 | 8.89e-10 | 64 | 0.00162 |
| cf projector diff / kcf | 0.687 | manufactured map 36 | 1.74e-13 | 64 | 0.0107 |
| cf tune diff / (kcf/min|sin|) | 0.031 | manufactured map 54 | 5.09e-15 | 64 | 0.000485 |
| eigenvector (I1) normalized / max(1,||M||) | 4.69 | manufactured map 102 | 2.35e-15 | 64 | 0.0732 |
| kappa (M1) vs (PS)_{a,pa} / ||u||^2 | 0 | manufactured map 1 | 0 | 16 | 0 |
| scaling G / ksc | 16.4 | map 17 scaling auto | 2.23e-11 | 1000 | 0.0164 |
| scaling P / ksc | 0.284 | map 4 scaling auto | 9.14e-15 | 1000 | 0.000284 |
| scaling beta,alpha,gamma / ksc | 8.72 | map 17 scaling auto | 1.19e-11 | 1000 | 0.00872 |
| scaling kappa / ksc | 0.0749 | map 8 scaling auto | 4.69e-14 | 1000 | 7.49e-05 |
| scaling tunes / ksc | 0.096 | map 19 scaling auto | 5.55e-16 | 1000 | 9.6e-05 |

| rejected fixture | quantity | value | threshold | ratio | reason |
|---|---|---|---|---|---|
| diag(2, 1/2, R(1.2)) | unit-circle departure | 1 | 1e-08 | 1e+08 | unstable_spectrum |
| R(0.9) (+) R(0.9) | min_gap / gap | 0 | 1e-06 | Inf | cluster_unresolved |
| R(0.9) (+) R(-0.9) | min_gap / gap | 0 | 1e-06 | Inf | cluster_unresolved |
| R(0.9) (+) R(0.9 + 1e-7) | min_gap / gap | 1e-07 | 1e-06 | 10 | cluster_unresolved |
| identity | unit-eigenvalue distance | 0 | 1e-08 | 1e+292 | unit_eigenvalue |
| symmetric FODO kq=1.6 (exact) | min_gap / gap | 4.44e-16 | 1e-06 | 2.25e+09 | cluster_unresolved |
| diag(1+1e-6, 1/(1+1e-6), R(1.2)) | unit-circle departure | 1e-06 | 1e-08 | 100 | unstable_spectrum |
| closed form R(0.9) (+) R(0.9) | |tau+ - tau-| | 0 | 1e-08 | Inf | singular_coefficient |
| closed form R(0.9) (+) R(-0.9) | |tau+ - tau-| | 0 | 1e-08 | Inf | singular_coefficient |
| closed form R(0.9) (+) R(0.9 + 1e-7) | |tau+ - tau-| | 1.63e-07 | 1e-08 | 0.0613 | none |
| closed form symmetric FODO kq=1.6 (exact) | |tau+ - tau-| | 0 | 1e-08 | Inf | singular_coefficient |

accepted side: largest unit-circle departure 1.67e-15 (map 4), ratio to STAB 1.67e-07; smallest gap 0.0322 (map 8), ratio to MIN_GAP 3.22e+04; smallest |tau+ - tau-| 0.00436 (map 8), ratio to TRACE_GAP 4.36e+05
```

#### Part B probe (measure_param.jl), stdout verbatim

```
FODO exact: sqrt(Delta) = 2.220446049250313e-16 (guard 1e-8: rejected ratio = guard / sqrtDelta)
FODO detuned: sqrt(Delta) = 0.002858939262204485 accepted ratio = sqrtDelta / guard = 285893.9262204485
FODO detuned: kq = 11869.559513281038, nU = 10.390774255193092, gap = 0.0022627650456965914, phase floors: sqrt(b1x b1y) = 0.0 vs 64 eps ||u||^2 = 9.337051834757788e-14

| check (residual / (eps kappa)) | required c (max ratio) | argmax fixture | 64 / required |
|---|---|---|---|
| 7.2/7.3 tables / (kR nU sT) | 0.295 | map 180 | 217.0 |
| B10 consistency / (kR sR) | 12.4 | map 8 | 5.17 |
| FODO alpha vs CS / (kq nU sa) | 5.68e-5 | FODO n | 1.13e6 |
| FODO beta vs CS / (kq nU b) | 5.39e-5 | FODO n | 1.19e6 |
| FODO mu vs CS / (kq nU) | 3.24e-5 | FODO n | 1.97e6 |
| M12 vs M9 / (nU ne/minbeta) | 0.391 | normalizer 50 | 164.0 |
| M13 / (nU/minbeta) | 0.514 | normalizer 56 | 124.0 |
| M2 row sum / nU | 0.531 | normalizer 164 | 121.0 |
| M3 col sum / nU | 0.619 | normalizer 164 | 103.0 |
| M4 diff / nU | 0.292 | normalizer 56 | 220.0 |
| M5 / nU^2 | 0.111 | normalizer 163 | 575.0 |
| M8 (I1) / (nM nU/minbeta) | 0.0528 | normalizer 181 | 1210.0 |
| M8 -> B10 R / (kR nU sR/minbeta) | 0.0205 | map 39 | 3120.0 |
| M8 -> B5/B9 twiss / (kR nU sc/minbeta) | 0.0294 | map 158 | 2180.0 |
| M8 rebuild / (nU/minbeta) | 0.264 | normalizer 56 | 242.0 |
| M8 sympl / (nU^2/minbeta) | 0.0382 | normalizer 56 | 1680.0 |
| M9 two forms / (nU ne) | 1.09 | normalizer 50 | 58.6 |
| R n-d / (kR sR) | 0.193 | map 1 | 332.0 |
| R n-m / (kq kR sR) | 0.402 | map 80 | 159.0 |
| R2 + R1/d1 / (nU^2/wmin^2) | 0.461 | map 194 | 139.0 |
| REJECTED zero weight (other form) |w| / (kq nU) [want > 10 x floor... reported raw] | 15.0 | construction form 2 det 0.0 n | 4.27 |
| T1 rebuild / (kR nM sV^2) | 0.406 | map 114 | 158.0 |
| T11 trace / (kq nU) | 1.66 | map 130 | 38.5 |
| T5 rec / (kq kR nM) | 0.173 | map 80 | 369.0 |
| Uet (I1) / (kq kR nM) | 0.169 | map 80 | 378.0 |
| V sympl / sV^2 | 0.995 | map 62 | 64.3 |
| blocks n-m / (kq kR sB) | 0.438 | map 80 | 146.0 |
| closure / (nU ne nM^2) | 0.433 | normalizer 8 | 148.0 |
| construction R / (kq nU sR/w) | 0.186 | construction form 2 det 0.0 d | 344.0 |
| construction T5 / (kq nU nM/w) | 0.0269 | construction form 2 det 0.0 d | 2380.0 |
| construction alpha / (kq nU sa/w) | 0.0979 | construction form 1 det 1.0 n | 653.0 |
| construction beta / (kq nU b/w) | 0.157 | construction form 2 det 0.0 n | 407.0 |
| construction lambda / (kq nU/w^2) | 0.0536 | construction form 2 det -0.5 d | 1190.0 |
| construction mu / (kq nU) | 0.0139 | construction form 1 det 0.3 n | 4600.0 |
| construction other det / (kq nU sR^2/(w d)^2) | 0.0141 | construction form 1 det 0.3 d | 4550.0 |
| construction other lambda^2 / (kq nU/min(w,1-w)^2) | 0.00349 | construction form 1 det 1.0 n | 18400.0 |
| construction tunes / kq | 0.0659 | construction form 1 det 0.3 | 971.0 |
| construction u / (kq nU) | 0.0639 | construction form 1 det 1.0 n | 1000.0 |
| construction weight / (kq nU/w) | 0.1 | construction form 2 det 0.0 n | 639.0 |
| detR1 detR2 - 1 / (nU^2/wmin^2) | 0.421 | map 88 | 152.0 |
| lambda^2 - w / kR | 0.424 | map 12 | 151.0 |
| mu n-m / (kq kT nU) | 0.613 | map 130 | 104.0 |
| phase norm / nU | 0.48 | normalizer 48 | 133.0 |
| phases vs M6 / (kq? kR nU/minbeta) | 0.449 | map 192 | 143.0 |
| rephase imag / norm(u) | 0.336 | normalizer 163 | 190.0 |
| twiss n-d / (kR sc) | 4.99 | map 134 | 12.8 |
| twiss n-m / (kq kR kT sc) | 1.74 | map 192 | 36.7 |
| u n-m / (kq nU) | 0.19 | map 176 | 336.0 |
| unit area / kR^2 | 0.0483 | map 181 | 1330.0 |
| w n-m / (kq nU w^2) | 0.204 | map 176 | 314.0 |

WORST accepted required c: 12.382502182260561 -> 64 / worst = 5.168583785245584
```

#### Part D tables (output of measure_stage2.jl, verbatim)

Fixtures: the 200 manufactured stable maps (seed 20260911), the detuned FODO (kd = -1.6 (1 + 1e-3)), the rotation R(2 pi 0.7) (+) R(2 pi 0.31), the two label-tie fixtures, the 8 coupled constructions of benchmark 12.2-2 (accepted, 212 frames); the 200 manufactured normalizers (seed 20260912, Part B); the guard fixtures of the Part A testsets (rejected, 7). Test thresholds: min_gap = 1.0e-6, stability_atol = 1.0e-8, min_trace_gap = 1.0e-8 (closed form and map route); floors projection_rtol = 64 eps = 1.42e-14, weight_rtol = 256 eps = 5.68e-14.

#### Table D1: guard quantities, accepted fixtures (extremes only) and every rejected fixture

| quantity | accepted extreme (fixture) | ratio to threshold |
|---|---|---|
| conjugate-class gap g (smallest) | 0.00226 (detuned FODO kq=1.6, eps=1e-3) | min_gap / g = 0.000442 |
| unit-circle departure (largest) | 7.55e-15 (construction form 2 det -0.5) | departure / stability_atol = 7.55e-07 |
| closed form |tau+ - tau-| (smallest) | 0.00286 (detuned FODO kq=1.6, eps=1e-3) | min_trace_gap / root = 3.5e-06 |
| map route sqrt(Delta) (T7) (smallest) | 0.00286 (detuned FODO kq=1.6, eps=1e-3) | min_trace_gap / sqrt(Delta) = 3.5e-06 |

| rejected fixture | frame reason | g | departure | unit-eigenvalue distance | closed form reason | |tau+ - tau-| | map route reason | sqrt(Delta) |
|---|---|---|---|---|---|---|---|---|
| R(0.9) (+) R(0.9 + 1e-7) | cluster_unresolved | 1e-07 | 1.11e-16 | 0.87 | available | 1.63e-07 | available | 1.57e-07 |
| R(0.9) (+) R(0.9) | cluster_unresolved | 0 | 0 | 0.87 | singular_coefficient | 0 | singular_coefficient | 0 |
| R(0.9) (+) R(-0.9) | cluster_unresolved | 0 | 0 | 0.87 | singular_coefficient | 0 | singular_coefficient | 0 |
| symmetric FODO kq=1.6 (exact) | cluster_unresolved | 4.44e-16 | 2.22e-16 | 0.67 | singular_coefficient | 0 | singular_coefficient | 2.22e-16 |
| identity | unit_eigenvalue | 0 | 0 | 0 | singular_coefficient | 0 | singular_coefficient | 0 |
| diag(2, 1/2, R(1.2)) | unstable_spectrum | 0.942 | 1 | 0.5 | unstable_spectrum | 1.78 | unstable_spectrum | 1.78 |
| diag(1+1e-6, 1/(1+1e-6), R(1.2)) | unstable_spectrum | 1.13 | 1e-06 | 1e-06 | unstable_spectrum | 1.28 | unstable_spectrum | 1.28 |

The control R(0.9) (+) R(0.9 + 1e-7) is refused by the frame (g = 1e-07 <= min_gap) and ACCEPTED by both trace guards (root 1.63e-07, sqrt(Delta) 1.57e-07 > 1.0e-8); the two guard families measure different quantities (an eigenvalue gap versus a trace gap, sqrt-related near a tie), and the frame is the primary route (design pipeline step 10). Window arithmetic below treats it as rejected for min_gap only.

#### Table D2: provisional floors projection_rtol (M6) and weight_rtol (B10 / B11 / T8) on Part A's frames

| floor | accepted smallest (fixture) | rejected largest (fixture) | threshold | accepted ratio (thr / smallest) | rejected ratio (thr / largest) | rule window [10 max rej, min acc / 10] |
|---|---|---|---|---|---|---|
| projection_rtol: sqrt(beta_jx beta_jy) / ||u_j||^2, 820 accepted, 8 rejected | 0.00156 (manufactured map 136 mode 1) | 0 (identity normalizer mode 1) | 1.42e-14 | 9.11e-12 | Inf | [0, 0.000156] |
| weight_rtol, normalizer route: |w| / ||U_x||^2 | 0.000372 (manufactured map 50 form 1) | 4.97e-15 (construction form 1 det 0.0 form 2) | 5.68e-14 | 1.53e-10 | 11.4 | [4.97e-14, 3.72e-05] |
| weight_rtol, direct route: |kappa_jx| (absolute) | 0.00232 (manufactured map 180 form 2) | 3.33e-15 (construction form 2 det 0.0 form 2) | 5.68e-14 | 2.45e-11 | 17.1 | [3.33e-14, 0.000232] |
| weight_rtol, map route: |den| / (|D| + sqrt Delta) | 0.00233 (manufactured map 180 form 2) | 9.98e-16 (construction form 1 det 0.0 form 2) | 5.68e-14 | 2.44e-11 | 57 | [9.98e-15, 0.000233] |

Zero-weight forms (rejected side): detuned FODO kq=1.6, eps=1e-3 form 2; R(0.7)+R(0.31) form 2; construction form 1 det 0.0 form 2; construction form 2 det 0.0 form 2. Rejected projections: identity normalizer mode 1; identity normalizer mode 2; rank-one Ur (exact) mode 1; rank-one Ur through the eigen frame mode 1; detuned FODO through the eigen frame mode 1; detuned FODO through the eigen frame mode 2; R(0.7)+R(0.31) through the eigen frame mode 1; R(0.7)+R(0.31) through the eigen frame mode 2.

#### Table D3: rejected side of the c eps kappa checks (a wrong quantity's residual / the suite's threshold; smallest over the accepted frames)

| wrong quantity on a check | smallest ratio to the suite's threshold | fixture |
|---|---|---|
| b03 (B10) R = +U_y U_x^-1 vs direct / (64 eps kR sR) | 5.53e+09 | manufactured map 50 form 2 |
| e02 on E7: ||U'SU - S|| / (64 eps kq ||U||^2) | 3.93e+06 | manufactured map 50 |
| e02 on E8: (I1) of U_bad / (64 eps max(1,||M||)) | 1.02e+12 | manufactured map 50 |
| e03 on M2: |sum_a kappa_Re - 1| / (64 eps ||u||^2) | 2.11e+11 | manufactured map 186 mode 2 |
| e08 wrong mode assignment on cf tune diff / (64 eps kcf/min|sin|) | 107 | manufactured map 50 |
| gamma = (1+alpha^2)/beta on M5 / (64 eps ||u||^4) | 8.55e+05 | manufactured map 50 mode 1 plane 1 |
| sin mu > 0 forced on tunes above 1/2: |mu_bad - mu| / (64 eps max(1,||M||)) | 9.94e+12 | construction form 2 det -0.5 mode 2 |

Rows run over the 212 accepted frames, except that the (B10)-sign row skips the two exactly uncoupled fixtures (R = 0 has no sign) and the gamma row skips the 12 planes with kappa^2 = 1 within kappa's uncertainty (there (1 + alpha^2)/beta IS the (M1) gamma: the uncoupled cells, the unit-weight plane of the rank-one constructions, the kappa = -1 plane of the det R = -0.5 form-2 construction): the wrong formula coincides with the right one on those fixtures and cannot be witnessed; the first three versions of this script counted them and reported smallest rejected ratios of 0, 0.034 and 0.104. The trace match is crossed (mode_permutation = (2, 1)) on 2 of them [label tie det R = 1 (design row); construction form 2 det 1.0]: on every manufactured map both routes label alike, so a label match is red only where the labels cross, which is why the suite's tie fixtures exist; the e08 row measures the residual of the wrong assignment on every frame. The sin-branch row runs over the 11 modes with tune above one half (the 200 manufactured maps have none; the rotation, tie and construction fixtures do).

#### Table D4: the one-tenth rule over every c eps kappa check

| part | checks | worst accepted ratio to the c used | where |
|---|---|---|---|
| A (eigenmodes_4d.jl) | 36 | 0.0732 | eigenvector (I1) normalized / max(1,||M||) [manufactured map 102] |
| B (coupled_parameterizations.jl) | 49 | 0.078 | twiss n-d / (kR sc) [map 134] at c = 64 |
| B, (B10) consistency at the suite's c = 256 | 1 | 0.0484 | map 8 (required c 12.4; at c = 64 the ratio would be 0.193) |
| D3 rejected side, smallest over the rows | 7 | 107 | e08 wrong mode assignment on cf tune diff / (64 eps kcf/min|sin|) |

#### Derived windows (rule: largest accepted ratio below one tenth, smallest rejected above ten)

##### min_gap (frame guard, reject iff g <= min_gap; PROVISIONAL, stage 3 replaces it with the resolution chord)
- accepted: 212 frames, smallest g = 0.00226 (detuned FODO kq=1.6, eps=1e-3); rejected: 4 fixtures, largest g = 1e-07 (R(0.9) (+) R(0.9 + 1e-7)).
- window [10 x 1e-07, 0.00226 / 10] = [1e-06, 0.000226]; geometric mean 1.5e-05. The test choice 1.0e-6 sits at the lower edge because the 1e-7 control was built as the deliberate 10x control of that choice. Pitfall 13 (trial 012, detuning 1e-9: g = 2.13e-9) is a fixture the chord default of stage 3 must resolve; no stage 2 value is frozen.
##### stability_atol (frame guard, reject iff departure > stability_atol; PROVISIONAL, stage 3 replaces it with the per-cluster Schur-block test)
- accepted: largest departure = 7.55e-15 (construction form 2 det -0.5); rejected: 2 fixtures, smallest departure = 1e-06 (diag(1+1e-6, 1/(1+1e-6), R(1.2))).
- window [10 x 7.55e-15, 1e-06 / 10] = [7.55e-14, 1e-07]; geometric mean 8.69e-11; the test choice 1.0e-8 is inside. Not to be frozen: a trace excess delta from roundoff maps to a departure sqrt(delta) near +-1 (Part A finding 2), so a raw-modulus guard at 1e-8 would call I_2 (+) R(1.2) unstable at trace roundoff 1e-16.
##### min_trace_gap, closed form (reject iff |tau+ - tau-| <= min_trace_gap; the coincident-trace guard of theory 3.4)
- accepted: smallest root = 0.00286 (detuned FODO kq=1.6, eps=1e-3); rejected (reason :singular_coefficient): 4 fixtures, largest root = 0 (R(0.9) (+) R(0.9)).
- window [10 x 0, 0.00286 / 10] = [0, 0.000286]; geometric mean NaN; the test choice 1.0e-8 is inside. With the 1e-7 control counted as rejected the window would be [1.63e-06, 0.000286], which excludes 1.0e-8: the closed form's guard is a division guard for (E11), not a resolution criterion.
##### min_trace_gap, map route (the (T9) conditioning guard, reject iff sqrt(Delta) <= min_trace_gap)
- accepted: smallest sqrt(Delta) = 0.00286 (detuned FODO kq=1.6, eps=1e-3); rejected (reason :singular_coefficient): 4 fixtures, largest = 2.22e-16 (symmetric FODO kq=1.6 (exact)).
- window [10 x 2.22e-16, 0.00286 / 10] = [2.22e-15, 0.000286]; geometric mean 7.97e-10; the test choice 1.0e-8 is inside. sqrt(Delta) of (T7) and the closed form's root are the same trace gap computed two ways; their measured extremes agree to the digits shown.
##### projection_rtol = 64 eps (M6 floor, relative to ||u_j||^2)
- window [0, 0.000156] from Table D2; the default 1.42e-14 is inside when the lower edge is below it. Every rejected fixture is an exact zero or a roundoff zero of an exactly vanishing projection; no genuine tiny projection exists among the fixtures, so the lower edge is a roundoff floor and the default is a roundoff-scale choice, as its docstring says.
##### weight_rtol = 256 eps (zero area weight, per route)
- normalizer route window [4.97e-14, 3.72e-05]; direct route [3.33e-14, 0.000232]; map route [9.98e-15, 0.000233]. The default 5.68e-14 is inside a window when its lower edge is below it; Part B raised it from 64 eps after the det R = 0 construction's zero weight arrived at 15 eps through the eigen frame (Table D2 shows the current value of that near-miss per route).
##### Unmeasured
- The 64 eps ||v||^2 floor of the :unresolved_defective branch of _eigenmodes_4d (eigenmodes_4d.jl, marked PROVISIONAL and unmeasured): no fixture reaches the branch past the three guards at the test thresholds; stage 3 owns the fixture and the Schur-block test that replaces it.

### Appendix: the measurement scripts

`measure_stage2.jl` (the Part D driver; runs the two probes below from its own directory and writes the tables):

```julia
# Stage 2 Part D measurement: every stage-2 tolerance multiplier and guard
# threshold on the suite's own fixtures, with the design rule "largest
# residual-to-threshold ratio on an accepted fixture below one tenth, smallest
# on a rejected fixture above ten". Runs the two Part A/B probes (their tables
# are reproduced verbatim), then measures what they did not: the guard
# windows (min_gap, stability_atol, the closed-form coincident-trace guard,
# the (T9) conditioning guard of the map route, the two provisional floors
# projection_rtol and weight_rtol on Part A's frames, per route), and the
# REJECTED side of the c eps kappa checks (the residual a wrong quantity
# produces, divided by the threshold the suite uses). Every extreme carries
# the name of the fixture that produced it (experiences: derive the label
# with the number, never type it).
#
# Package mode, from the repository root:
#   julia --startup-file=no --project=. --threads=4 measure_stage2.jl <out.md>
using Octopus, LinearAlgebra, Random, Printf
const OUT_MD = length(ARGS) >= 1 ? ARGS[1] : joinpath(@__DIR__, "measurement_table.md")
const EPS = eps(Float64)
e2(x) = @sprintf("%.3g", x)

# --- 1. the Part A probe, in its own module so its top-level names stay put ---
const MeasA = Module(:MeasA)
logA = joinpath(@__DIR__, "probe_A_stdout.log")
open(logA, "w") do io
    redirect_stdout(io) do
        Base.include(MeasA, joinpath(@__DIR__, "measure_eig4d.jl"))
    end
end
# --- 2. the Part B probe, in Main (it include_strings the test helpers into Main) ---
logB = joinpath(@__DIR__, "probe_B_stdout.log")
open(logB, "w") do io
    redirect_stdout(io) do
        include(joinpath(@__DIR__, "measure_param.jl"))
    end
end
tableA = read(logA, String)
tableB = read(logB, String)

# --- 3. Part D fixtures ---------------------------------------------------------
val = determined_value
S4 = Octopus._symplectic_form(4)
R2(mu) = Octopus._rotation2(mu)
bd(A, B) = [A zeros(2, 2); zeros(2, 2) B]
MIN_GAP, STAB, TRACE_GAP = MeasA.MIN_GAP, MeasA.STAB, MeasA.TRACE_GAP
W_RTOL = 256 * EPS        # weight_rtol default (coupled_parameterizations.jl)
P_RTOL = 64 * EPS         # projection_rtol default
frame_of(M) = Octopus._eigenmodes_4d(M; min_gap=MIN_GAP, stability_atol=STAB)

# accepted fixtures: (name, M, frame); every one must resolve
accepted = Any[]
for (i, (M, f)) in enumerate(MeasA.frames)
    push!(accepted, ("manufactured map $(i)", M, f))
end
push!(accepted, ("detuned FODO kq=1.6, eps=1e-3", MeasA.M4, MeasA.ff))
push!(accepted, ("R(0.7)+R(0.31)", MeasA.Mrot, MeasA.fr))
# the two label-tie fixtures of the closed-form testset (runtests.jl, "Label ties")
Rtie = [0.8 0.3; -0.6 1.025]; Vtie = Octopus._edwards_teng_V(1, Rtie)
Mtie = Vtie * bd(Octopus._twiss_block(2.3, 0.4, 2pi * 0.28), Octopus._twiss_block(1.7, -0.6, 2pi * 0.61)) * Octopus._symplectic_inverse(Vtie)
th = pi / 4
Wroll = [cos(th) * Matrix(1.0I, 2, 2) sin(th) * Matrix(1.0I, 2, 2); -sin(th) * Matrix(1.0I, 2, 2) cos(th) * Matrix(1.0I, 2, 2)]
Mroll = Wroll * bd(Octopus._twiss_block(2.0, 0.3, 2pi * 0.7), Octopus._twiss_block(1.5, -0.4, 2pi * 0.31)) * transpose(Wroll)
for (nm, M) in (("label tie det R = 1 (design row)", Mtie), ("label tie 45-degree roll", Mroll))
    push!(accepted, (nm, M, val(frame_of(M).frame)))
end
# the coupled construction of benchmark 12.2-2 (the design row det R in (-0.5, 0, 0.3, 1))
constructions = Any[]   # (name, M, frame, form, d, expected tunes)
let
    bx, ax, mux = 2.0, 0.3, 2pi * 0.7; by, ay, muy = 1.5, -0.4, 2pi * 0.31; bz, muz = 10.0, 2pi * 0.05
    Rs = ((0.5, 0.5, 1.5, 0.5), (0.4, 0.2, 0.6, 0.3), (0.5, 0.2, -0.1, 0.56), (0.8, 0.3, -0.6, 1.025))
    m0 = compile_runtime(Linear6DSpec(beta1=(bx, by, bz), alpha1=(ax, ay, 0.0), dmu=(mux, muy, muz)))
    for (mode, form) in ((XY_MODEA, 1), (XY_MODEB, 2)), r in Rs
        Rm = [r[1] r[2]; r[3] r[4]]; d = det(Rm)
        W = compile_runtime(XYCouplingSpec(r1=r[1], r2=r[2], r3=r[3], r4=r[4], mode=mode))
        Winv = form == 1 ? compile_runtime(XYCouplingSpec(r1=-r[1], r2=-r[2], r3=-r[3], r4=-r[4], mode=mode)) :
                           compile_runtime(XYCouplingSpec(r1=r[4], r2=-r[2], r3=-r[3], r4=r[1], mode=mode))
        M = one_turn_matrix((Winv, m0, W)).matrix[1:4, 1:4]
        pf = _pb_frame(M; expected=(mux, muy))
        nm = "construction form $(form) det $(abs(d) < 1e-12 ? 0.0 : round(d, digits=2))"
        push!(constructions, (nm, M, pf.frame, form, d, (mux, muy)))
        push!(accepted, (nm, M, pf.frame))
    end
end
# rejected fixtures of the guards (name, M)
fodo_exact = MeasA.fodo4(1.6, -1.6)
rejected_guard = [
    ("R(0.9) (+) R(0.9 + 1e-7)", bd(R2(0.9), R2(0.9 + 1e-7))),
    ("R(0.9) (+) R(0.9)", bd(R2(0.9), R2(0.9))),
    ("R(0.9) (+) R(-0.9)", bd(R2(0.9), R2(-0.9))),
    ("symmetric FODO kq=1.6 (exact)", fodo_exact),
    ("identity", Matrix(1.0I, 4, 4)),
    ("diag(2, 1/2, R(1.2))", bd([2.0 0; 0 0.5], R2(1.2))),
    ("diag(1+1e-6, 1/(1+1e-6), R(1.2))", bd([1 + 1e-6 0; 0 1 / (1 + 1e-6)], R2(1.2))),
]

named_extreme(vals, names, which) = (k = which(vals); "$(e2(vals[k])) ($(names[k]))")
function window_gap(acc, accn, rej, rejn)     # reject iff q <= t: window [10 max rej, min acc / 10]
    lo = 10 * maximum(rej); hi = minimum(acc) / 10
    return lo, hi, named_extreme(acc, accn, argmin), named_extreme(rej, rejn, argmax)
end
function window_departure(acc, accn, rej, rejn) # reject iff q > t: window [10 max acc, min rej / 10]
    lo = 10 * maximum(acc); hi = minimum(rej) / 10
    return lo, hi, named_extreme(acc, accn, argmax), named_extreme(rej, rejn, argmin)
end
gmean(lo, hi) = lo > 0 ? sqrt(lo * hi) : NaN
io = IOBuffer()
pr(args...) = println(io, args...)

pr("# Stage 2 measurement tables (output of measure_stage2.jl, verbatim)\n")
pr("Fixtures: the 200 manufactured stable maps (seed 20260911), the detuned FODO (kd = -1.6 (1 + 1e-3)), the rotation R(2 pi 0.7) (+) R(2 pi 0.31), the two label-tie fixtures, the 8 coupled constructions of benchmark 12.2-2 (accepted, $(length(accepted)) frames); the 200 manufactured normalizers (seed 20260912, Part B); the guard fixtures of the Part A testsets (rejected, $(length(rejected_guard))). Test thresholds: min_gap = $(MIN_GAP), stability_atol = $(STAB), min_trace_gap = $(TRACE_GAP) (closed form and map route); floors projection_rtol = 64 eps = $(e2(P_RTOL)), weight_rtol = 256 eps = $(e2(W_RTOL)).\n")

# --- 4. Table D1: guard quantities on every fixture -----------------------------
pr("## Table D1: guard quantities, accepted fixtures (extremes only) and every rejected fixture\n")
acc_gap = Float64[]; acc_dep = Float64[]; acc_root = Float64[]; acc_sqd = Float64[]; acc_n = String[]
function trace_quantities(M)
    rad = 2 * tr(M * M) - tr(M)^2 + 8                     # (E10) radicand, closed form
    Mxx, Mxy, Myx, Myy = M[1:2, 1:2], M[1:2, 3:4], M[3:4, 1:2], M[3:4, 3:4]
    Delta = (tr(Mxx) - tr(Myy))^2 + 4 * det(Octopus._adjugate2(Mxy) + Myx)   # (T7), map route
    return sqrt(abs(rad)), sqrt(abs(Delta))
end
for (nm, M, f) in accepted
    s = frame_of(M).spectrum
    root, sqd = trace_quantities(M)
    push!(acc_gap, s.gap); push!(acc_dep, s.unit_circle_departure); push!(acc_root, root); push!(acc_sqd, sqd); push!(acc_n, nm)
end
pr("| quantity | accepted extreme (fixture) | ratio to threshold |")
pr("|---|---|---|")
pr("| conjugate-class gap g (smallest) | $(named_extreme(acc_gap, acc_n, argmin)) | min_gap / g = $(e2(MIN_GAP / minimum(acc_gap))) |")
pr("| unit-circle departure (largest) | $(named_extreme(acc_dep, acc_n, argmax)) | departure / stability_atol = $(e2(maximum(acc_dep) / STAB)) |")
pr("| closed form |tau+ - tau-| (smallest) | $(named_extreme(acc_root, acc_n, argmin)) | min_trace_gap / root = $(e2(TRACE_GAP / minimum(acc_root))) |")
pr("| map route sqrt(Delta) (T7) (smallest) | $(named_extreme(acc_sqd, acc_n, argmin)) | min_trace_gap / sqrt(Delta) = $(e2(TRACE_GAP / minimum(acc_sqd))) |")
pr("")
pr("| rejected fixture | frame reason | g | departure | unit-eigenvalue distance | closed form reason | |tau+ - tau-| | map route reason | sqrt(Delta) |")
pr("|---|---|---|---|---|---|---|---|---|")
rej_gap = Float64[]; rej_gap_n = String[]; rej_dep = Float64[]; rej_dep_n = String[]
rej_root = Float64[]; rej_root_n = String[]; rej_sqd = Float64[]; rej_sqd_n = String[]
for (nm, M) in rejected_guard
    r = frame_of(M); s = r.spectrum
    cf = Octopus._closed_form_eigenmodes_4d(M; min_trace_gap=TRACE_GAP, stability_atol=STAB)
    em = Octopus._edwards_teng_from_map(M; min_trace_gap=TRACE_GAP)
    root, sqd = trace_quantities(M)
    fr_reason = is_determined(r.frame) ? :resolved : r.frame.reason
    freason = string(fr_reason)
    cfreason = is_determined(cf) ? "available" : string(cf.reason)
    emreason = is_determined(em.form1.R) || is_determined(em.form2.R) ? "available" : string(em.form1.R.reason)
    pr("| $(nm) | $(freason) | $(e2(s.gap)) | $(e2(s.unit_circle_departure)) | $(e2(s.unit_eigenvalue_distance)) | $(cfreason) | $(e2(root)) | $(emreason) | $(e2(sqd)) |")
    if fr_reason === :cluster_unresolved
        push!(rej_gap, s.gap); push!(rej_gap_n, nm)
    elseif fr_reason === :unstable_spectrum
        push!(rej_dep, s.unit_circle_departure); push!(rej_dep_n, nm)
    end
    if !is_determined(cf) && cf.reason === :singular_coefficient
        push!(rej_root, root); push!(rej_root_n, nm)
    end
    if !is_determined(em.form1.R) && em.form1.R.reason === :singular_coefficient
        push!(rej_sqd, sqd); push!(rej_sqd_n, nm)
    end
end
# the 1e-7 control: the frame rejects it, the two trace guards accept it (recorded, not hidden)
ctrl = rejected_guard[1]
ctrl_root, ctrl_sqd = trace_quantities(ctrl[2])
pr("")
pr("The control $(ctrl[1]) is refused by the frame (g = $(e2(frame_of(ctrl[2]).spectrum.gap)) <= min_gap) and ACCEPTED by both trace guards (root $(e2(ctrl_root)), sqrt(Delta) $(e2(ctrl_sqd)) > $(TRACE_GAP)); the two guard families measure different quantities (an eigenvalue gap versus a trace gap, sqrt-related near a tie), and the frame is the primary route (design pipeline step 10). Window arithmetic below treats it as rejected for min_gap only.")

# --- 5. Table D2: the two provisional floors on Part A's frames -------------------
pr("\n## Table D2: provisional floors projection_rtol (M6) and weight_rtol (B10 / B11 / T8) on Part A's frames\n")
proj_acc = Float64[]; proj_acc_n = String[]
w_norm_acc = Float64[]; w_norm_n = String[]; w_dir_acc = Float64[]; w_dir_n = String[]; w_map_acc = Float64[]; w_map_n = String[]
function weight_quantities(M, f)
    U = f.normalizer; mu = f.tunes
    etn = Octopus._edwards_teng_from_normalizer(U, mu; M4=M)
    etd = Octopus._edwards_teng_direct(f.projectors[1], f.covariances[1], f.projectors[2], f.covariances[2]; tunes=mu, M4=M)
    Mxx, Mxy, Myx, Myy = M[1:2, 1:2], M[1:2, 3:4], M[3:4, 1:2], M[3:4, 3:4]
    A = Octopus._adjugate2(Mxy) + Myx; D = tr(Mxx) - tr(Myy); sq = sqrt(max(D^2 + 4 * det(A), 0.0))
    s = Octopus._map_route_label_sign(D, (2cos(mu[1]), 2cos(mu[2])))
    rel(w, Ux) = norm(Ux) == 0 ? 0.0 : abs(w) / norm(Ux)^2                 # an all-zero block has weight 0 and no finite R at any floor
    wn = (rel(etn.form1.area_weight, U[1:2, 1:2]), rel(etn.form2.area_weight, U[1:2, 3:4]))                   # normalizer route: |w| / ||U_x||^2
    wd = (abs(etd.form1.area_weight), abs(etd.form2.area_weight))                                                # direct route: |kappa_jx| absolute
    wm = (abs(D + s * sq) / (abs(D) + sq), abs(D - s * sq) / (abs(D) + sq))                                       # map route: |den| / (|D| + sqrt Delta)
    return wn, wd, wm
end
# exactly uncoupled fixtures: both secondary projections and the form-2 weight are zero in exact arithmetic
uncoupled_fixtures = Set(["detuned FODO kq=1.6, eps=1e-3", "R(0.7)+R(0.31)"])
for (nm, M, f) in accepted
    nm in uncoupled_fixtures && continue
    mr = Octopus._mais_ripken(f)
    for j in 1:2
        push!(proj_acc, sqrt(mr.beta[j, 1] * mr.beta[j, 2]) / norm(mr.vectors[j])^2); push!(proj_acc_n, "$(nm) mode $(j)")
    end
end
for (i, (U, mu)) in enumerate(_PB_NORMALIZERS)
    mr = Octopus._mais_ripken(U)
    for j in 1:2
        push!(proj_acc, sqrt(mr.beta[j, 1] * mr.beta[j, 2]) / norm(mr.vectors[j])^2); push!(proj_acc_n, "normalizer $(i) mode $(j)")
    end
end
# weights: every form that is admissible on an accepted fixture (the uncoupled cell's form 2 and the
# det R = 0 constructions' other form have weight 0 by construction and are the rejected side)
# Fixtures with a weight that is zero in exact arithmetic: the uncoupled cells (u = 0) and the
# det R = 0 constructions (one of u, 1 - u is zero). WHICH form carries the zero depends on the
# labels: under the frame's labels (mode 1 = larger x-area) it is the smaller of the two direct-route
# weights, derived from the data below rather than from the constructing form (a first version of
# this script assigned it by the constructing form and measured a "rejected" weight of 1).
zero_weight_fixtures = copy(uncoupled_fixtures)
for (nm, M, f, form, d, _) in constructions
    abs(d) < 1e-12 && push!(zero_weight_fixtures, nm)
end
zero_weight_names = String[]
for (nm, M, f) in accepted
    nm in zero_weight_fixtures || continue
    wn, wd, wm = weight_quantities(M, f)
    push!(zero_weight_names, "$(nm) form $(argmin(wd))")
end
for (nm, M, f) in accepted
    wn, wd, wm = weight_quantities(M, f)
    for form in 1:2
        "$(nm) form $(form)" in zero_weight_names && continue
        push!(w_norm_acc, wn[form]); push!(w_norm_n, "$(nm) form $(form)")
        push!(w_dir_acc, wd[form]); push!(w_dir_n, "$(nm) form $(form)")
        push!(w_map_acc, wm[form]); push!(w_map_n, "$(nm) form $(form)")
    end
end
# rejected side of the floors: quantities that are zero in exact arithmetic, as the routes see them
proj_rej = Float64[]; proj_rej_n = String[]
w_norm_rej = Float64[]; w_norm_rej_n = String[]; w_dir_rej = Float64[]; w_dir_rej_n = String[]; w_map_rej = Float64[]; w_map_rej_n = String[]
Ur = Octopus._edwards_teng_normalizer(1, [0.0 0.0; 0.0 0.4], 2.0, 0.3, 1.5, -0.2)      # rank-one coupling, u_1y = 0 exactly (test fixture)
Mr = Ur * bd(R2(2pi * 0.7), R2(2pi * 0.31)) * Octopus._symplectic_inverse(Ur)
proj_fixtures = [("identity normalizer", Octopus._mais_ripken(Matrix(1.0I, 4, 4)), 1:2),
                 ("rank-one Ur (exact)", Octopus._mais_ripken(Ur), 1:1),
                 ("rank-one Ur through the eigen frame", Octopus._mais_ripken(val(frame_of(Mr).frame)), 1:1),
                 ("detuned FODO through the eigen frame", Octopus._mais_ripken(MeasA.ff), 1:2),
                 ("R(0.7)+R(0.31) through the eigen frame", Octopus._mais_ripken(MeasA.fr), 1:2)]
for (nm, mr, modes) in proj_fixtures, j in modes
    push!(proj_rej, sqrt(mr.beta[j, 1] * mr.beta[j, 2]) / norm(mr.vectors[j])^2); push!(proj_rej_n, "$(nm) mode $(j)")
end
for (nm, M, f) in accepted
    wn, wd, wm = weight_quantities(M, f)
    for form in 1:2
        "$(nm) form $(form)" in zero_weight_names || continue
        push!(w_norm_rej, wn[form]); push!(w_norm_rej_n, "$(nm) form $(form)")
        push!(w_dir_rej, wd[form]); push!(w_dir_rej_n, "$(nm) form $(form)")
        push!(w_map_rej, wm[form]); push!(w_map_rej_n, "$(nm) form $(form)")
    end
end
pr("| floor | accepted smallest (fixture) | rejected largest (fixture) | threshold | accepted ratio (thr / smallest) | rejected ratio (thr / largest) | rule window [10 max rej, min acc / 10] |")
pr("|---|---|---|---|---|---|---|")
function floor_row(label, acc, accn, rej, rejn, thr)
    lo, hi, a, r = window_gap(acc, accn, rej, rejn)
    rr = maximum(rej) == 0 ? "Inf" : e2(thr / maximum(rej))
    pr("| $(label) | $(a) | $(r) | $(e2(thr)) | $(e2(thr / minimum(acc))) | $(rr) | [$(e2(lo)), $(e2(hi))] |")
    return lo, hi
end
win_proj = floor_row("projection_rtol: sqrt(beta_jx beta_jy) / ||u_j||^2, $(length(proj_acc)) accepted, $(length(proj_rej)) rejected", proj_acc, proj_acc_n, proj_rej, proj_rej_n, P_RTOL)
win_wn = floor_row("weight_rtol, normalizer route: |w| / ||U_x||^2", w_norm_acc, w_norm_n, w_norm_rej, w_norm_rej_n, W_RTOL)
win_wd = floor_row("weight_rtol, direct route: |kappa_jx| (absolute)", w_dir_acc, w_dir_n, w_dir_rej, w_dir_rej_n, W_RTOL)
win_wm = floor_row("weight_rtol, map route: |den| / (|D| + sqrt Delta)", w_map_acc, w_map_n, w_map_rej, w_map_rej_n, W_RTOL)
pr("")
pr("Zero-weight forms (rejected side): $(join(zero_weight_names, "; ")). Rejected projections: $(join(proj_rej_n, "; ")).")

# --- 6. Table D3: rejected side of the c eps kappa checks ---------------------------
pr("\n## Table D3: rejected side of the c eps kappa checks (a wrong quantity's residual / the suite's threshold; smallest over the accepted frames)\n")
rej_rows = Dict{String,Tuple{Float64,String}}()
crossed_names = String[]
n_above_half = 0
n_unit_kappa = 0
function rejmin!(name, ratio, fx)
    cur = get(rej_rows, name, (Inf, ""))
    ratio < cur[1] && (rej_rows[name] = (ratio, fx))
end
for (nm, M, f) in accepted
    U = f.normalizer; nU = norm(U)^2; nM = max(1, norm(M))
    kq = max(1, opnorm(M)) * opnorm(U)^2 / frame_of(M).spectrum.gap
    u1, u2 = f.vectors
    Ubad = hcat(real(u1), imag(u1), real(u2), imag(u2))                        # e02: the (E6) minus dropped
    rejmin!("e02 on E7: ||U'SU - S|| / (64 eps kq ||U||^2)", norm(transpose(Ubad) * S4 * Ubad - S4) / (64 * EPS * kq * nU), nm)
    Rb = bd(R2(f.tunes[1]), R2(f.tunes[2]))
    rejmin!("e02 on E8: (I1) of U_bad / (64 eps max(1,||M||))", Octopus._invariance_residual(M, Ubad, Rb).normalized / (64 * EPS * nM), nm)
    for j in 1:2
        u = f.vectors[j]; nu = norm(u)^2
        kre = sum(-real(conj(u[2a - 1]) * u[2a]) for a in 1:2)                 # e03/b01: (M1) with Re
        rejmin!("e03 on M2: |sum_a kappa_Re - 1| / (64 eps ||u||^2)", abs(kre - 1) / (64 * EPS * nu), "$(nm) mode $(j)")
        for a in 1:2
            # the two gammas differ by (1 - kappa^2)/beta: a plane with kappa^2 = 1 within kappa's own
            # uncertainty (the chord-amplified 64 eps kq ||U||^2 the suite uses for kappa) cannot witness the
            # defect: every plane of an uncoupled cell, the unit-weight plane of a rank-one construction, and
            # the kappa = -1 plane of the det R = -0.5 construction (u = 1/(1 + det R) = 2, so 1 - u = -1)
            if abs(1 - f.signed_areas[j, a]^2) <= 64 * EPS * kq * nU
                global n_unit_kappa += 1
                continue
            end
            gbad = (1 + f.alpha[j, a]^2) / f.beta[j, a]                       # gamma by (1 + alpha^2)/beta instead of (M1)
            m5 = abs(f.beta[j, a] * gbad - f.alpha[j, a]^2 - f.signed_areas[j, a]^2)
            rejmin!("gamma = (1+alpha^2)/beta on M5 / (64 eps ||u||^4)", m5 / (64 * EPS * nu^2), "$(nm) mode $(j) plane $(a)")
        end
        if f.tunes[j] > pi                                                     # e06/b09: sin mu forced positive
            global n_above_half += 1
            mu_bad = 2pi - f.tunes[j]
            rejmin!("sin mu > 0 forced on tunes above 1/2: |mu_bad - mu| / (64 eps max(1,||M||))", abs(mu_bad - f.tunes[j]) / (64 * EPS * nM), "$(nm) mode $(j)")
        end
    end
    # e08: the closed-form check with the WRONG mode assignment (the permutation the trace match rejects);
    # a label match produces exactly this residual whenever the two routes' labels cross (the tie fixtures)
    c = val(Octopus._closed_form_check_4d(f; min_trace_gap=TRACE_GAP, stability_atol=STAB))
    root = abs(c.closed_form.traces[1] - c.closed_form.traces[2])
    kc = max(1, norm(M)^2) * max(1, nU) * (1 + 1 / (2 * root)) / root
    kcf = kq * nU + kc; smin = minimum(abs.(c.closed_form.sines))
    q = (c.mode_permutation[2], c.mode_permutation[1])
    td = maximum(abs(c.closed_form.tunes[q[j]] - f.tunes[j]) for j in 1:2)
    rejmin!("e08 wrong mode assignment on cf tune diff / (64 eps kcf/min|sin|)", td / (64 * EPS * kcf / smin), nm)
    c.mode_permutation == (1, 2) || push!(crossed_names, nm)
    # b03: (B10) with the sign dropped, against the direct route's R (R = 0 on an uncoupled cell has no sign: no witness there)
    etd = Octopus._edwards_teng_direct(f; M4=M)
    for form in 1:2
        nm in uncoupled_fixtures && continue
        Ux = form == 1 ? U[1:2, 1:2] : U[1:2, 3:4]; Uy = form == 1 ? U[3:4, 1:2] : U[3:4, 3:4]
        w = det(Ux); kR = nU / abs(w)
        g = form == 1 ? etd.form1 : etd.form2
        is_determined(g.R) || continue
        Rd = val(g.R); sR = max(1, norm(Rd))
        rejmin!("b03 (B10) R = +U_y U_x^-1 vs direct / (64 eps kR sR)", norm(Uy / Ux - Rd) / (64 * EPS * kR * sR), "$(nm) form $(form)")
    end
end
pr("| wrong quantity on a check | smallest ratio to the suite's threshold | fixture |")
pr("|---|---|---|")
for k in sort(collect(keys(rej_rows)))
    r, fx = rej_rows[k]
    pr("| $(k) | $(e2(r)) | $(fx) |")
end
pr("")
pr("Rows run over the $(length(accepted)) accepted frames, except that the (B10)-sign row skips the two exactly uncoupled fixtures (R = 0 has no sign) and the gamma row skips the $(n_unit_kappa) planes with kappa^2 = 1 within kappa's uncertainty (there (1 + alpha^2)/beta IS the (M1) gamma: the uncoupled cells, the unit-weight plane of the rank-one constructions, the kappa = -1 plane of the det R = -0.5 form-2 construction): the wrong formula coincides with the right one on those fixtures and cannot be witnessed; the first three versions of this script counted them and reported smallest rejected ratios of 0, 0.034 and 0.104. The trace match is crossed (mode_permutation = (2, 1)) on $(length(crossed_names)) of them [$(join(crossed_names, "; "))]: on every manufactured map both routes label alike, so a label match is red only where the labels cross, which is why the suite's tie fixtures exist; the e08 row measures the residual of the wrong assignment on every frame. The sin-branch row runs over the $(n_above_half) modes with tune above one half (the 200 manufactured maps have none; the rotation, tie and construction fixtures do).")

# --- 7. Summary of the one-tenth rule for the c multipliers ----------------------------
pr("\n## Table D4: the one-tenth rule over every c eps kappa check\n")
worstA = -1.0; worstA_n = ""
for (name, (ratio, fx, raw)) in MeasA.rows
    q = ratio / MeasA.C_USED[name]
    q > worstA && (global worstA = q; global worstA_n = "$(name) [$(fx)]")
end
cB(k) = startswith(k, "B10 consistency") ? 256 : 64
worstB = -1.0; worstB_n = ""
for (k, (r, who)) in req
    startswith(k, "REJECTED") && continue
    q = r / cB(k)
    q > worstB && (global worstB = q; global worstB_n = "$(k) [$(who)] at c = $(cB(k))")
end
pr("| part | checks | worst accepted ratio to the c used | where |")
pr("|---|---|---|---|")
pr("| A (eigenmodes_4d.jl) | $(length(MeasA.rows)) | $(e2(worstA)) | $(worstA_n) |")
pr("| B (coupled_parameterizations.jl) | $(count(!startswith(k, "REJECTED") for k in keys(req))) | $(e2(worstB)) | $(worstB_n) |")
pr("| B, (B10) consistency at the suite's c = 256 | 1 | $(e2(req["B10 consistency / (kR sR)"][1] / 256)) | $(req["B10 consistency / (kR sR)"][2]) (required c $(e2(req["B10 consistency / (kR sR)"][1])); at c = 64 the ratio would be $(e2(req["B10 consistency / (kR sR)"][1] / 64))) |")
pr("| D3 rejected side, smallest over the rows | $(length(rej_rows)) | $(e2(minimum(v[1] for v in values(rej_rows)))) | $(first(k for (k, v) in rej_rows if v[1] == minimum(v[1] for v in values(rej_rows)))) |")

# --- 8. Derived windows for the guard thresholds -------------------------------------------
pr("\n## Derived windows (rule: largest accepted ratio below one tenth, smallest rejected above ten)\n")
lo, hi, a, r = window_gap(acc_gap, acc_n, rej_gap, rej_gap_n)
pr("### min_gap (frame guard, reject iff g <= min_gap; PROVISIONAL, stage 3 replaces it with the resolution chord)")
pr("- accepted: $(length(acc_gap)) frames, smallest g = $(a); rejected: $(length(rej_gap)) fixtures, largest g = $(r).")
pr("- window [10 x $(e2(maximum(rej_gap))), $(e2(minimum(acc_gap))) / 10] = [$(e2(lo)), $(e2(hi))]; geometric mean $(e2(gmean(lo, hi))). The test choice $(MIN_GAP) sits at the lower edge because the 1e-7 control was built as the deliberate 10x control of that choice. Pitfall 13 (trial 012, detuning 1e-9: g = 2.13e-9) is a fixture the chord default of stage 3 must resolve; no stage 2 value is frozen.")
lo, hi, a, r = window_departure(acc_dep, acc_n, rej_dep, rej_dep_n)
pr("### stability_atol (frame guard, reject iff departure > stability_atol; PROVISIONAL, stage 3 replaces it with the per-cluster Schur-block test)")
pr("- accepted: largest departure = $(a); rejected: $(length(rej_dep)) fixtures, smallest departure = $(r).")
pr("- window [10 x $(e2(maximum(acc_dep))), $(e2(minimum(rej_dep))) / 10] = [$(e2(lo)), $(e2(hi))]; geometric mean $(e2(gmean(lo, hi))); the test choice $(STAB) is inside. Not to be frozen: a trace excess delta from roundoff maps to a departure sqrt(delta) near +-1 (Part A finding 2), so a raw-modulus guard at 1e-8 would call I_2 (+) R(1.2) unstable at trace roundoff 1e-16.")
lo, hi, a, r = window_gap(acc_root, acc_n, rej_root, rej_root_n)
pr("### min_trace_gap, closed form (reject iff |tau+ - tau-| <= min_trace_gap; the coincident-trace guard of theory 3.4)")
pr("- accepted: smallest root = $(a); rejected (reason :singular_coefficient): $(length(rej_root)) fixtures, largest root = $(r).")
pr("- window [10 x $(e2(maximum(rej_root))), $(e2(minimum(acc_root))) / 10] = [$(e2(lo)), $(e2(hi))]; geometric mean $(e2(gmean(lo, hi))); the test choice $(TRACE_GAP) is inside. With the 1e-7 control counted as rejected the window would be [$(e2(10 * ctrl_root)), $(e2(minimum(acc_root) / 10))], which excludes $(TRACE_GAP): the closed form's guard is a division guard for (E11), not a resolution criterion.")
lo, hi, a, r = window_gap(acc_sqd, acc_n, rej_sqd, rej_sqd_n)
pr("### min_trace_gap, map route (the (T9) conditioning guard, reject iff sqrt(Delta) <= min_trace_gap)")
pr("- accepted: smallest sqrt(Delta) = $(a); rejected (reason :singular_coefficient): $(length(rej_sqd)) fixtures, largest = $(r).")
pr("- window [10 x $(e2(maximum(rej_sqd))), $(e2(minimum(acc_sqd))) / 10] = [$(e2(lo)), $(e2(hi))]; geometric mean $(e2(gmean(lo, hi))); the test choice $(TRACE_GAP) is inside. sqrt(Delta) of (T7) and the closed form's root are the same trace gap computed two ways; their measured extremes agree to the digits shown.")
pr("### projection_rtol = 64 eps (M6 floor, relative to ||u_j||^2)")
pr("- window [$(e2(win_proj[1])), $(e2(win_proj[2]))] from Table D2; the default $(e2(P_RTOL)) is inside when the lower edge is below it. Every rejected fixture is an exact zero or a roundoff zero of an exactly vanishing projection; no genuine tiny projection exists among the fixtures, so the lower edge is a roundoff floor and the default is a roundoff-scale choice, as its docstring says.")
pr("### weight_rtol = 256 eps (zero area weight, per route)")
pr("- normalizer route window [$(e2(win_wn[1])), $(e2(win_wn[2]))]; direct route [$(e2(win_wd[1])), $(e2(win_wd[2]))]; map route [$(e2(win_wm[1])), $(e2(win_wm[2]))]. The default $(e2(W_RTOL)) is inside a window when its lower edge is below it; Part B raised it from 64 eps after the det R = 0 construction's zero weight arrived at 15 eps through the eigen frame (Table D2 shows the current value of that near-miss per route).")
pr("### Unmeasured")
pr("- The 64 eps ||v||^2 floor of the :unresolved_defective branch of _eigenmodes_4d (eigenmodes_4d.jl, marked PROVISIONAL and unmeasured): no fixture reaches the branch past the three guards at the test thresholds; stage 3 owns the fixture and the Schur-block test that replaces it.")

# --- 9. write -------------------------------------------------------------------------------
out = IOBuffer()
println(out, "# Stage 2 measurement tables\n")
println(out, "## Part A probe (measure_eig4d.jl), stdout verbatim\n")
println(out, "```")
print(out, tableA)
println(out, "```\n")
println(out, "## Part B probe (measure_param.jl), stdout verbatim\n")
println(out, "```")
print(out, tableB)
println(out, "```\n")
print(out, String(take!(io)))
write(OUT_MD, String(take!(out)))
println("written: ", OUT_MD)
```

`measure_eig4d.jl` (the Part A probe, byte-identical to the worktree original):

```julia
# Measurement probe behind the stage 2 Part A tolerances (eig4d_testsets.jl).
# For every check the testsets state as c * eps * kappa it prints the largest
# residual / (eps * kappa) over the fixtures (seed 20260911), i.e. the c the
# fixtures REQUIRE, with the argmax fixture's own name (experiences: carry the
# name with the value), and the same ratio against the c the testsets use.
# Rejected fixtures print residual / threshold, which must exceed ten.
# Package mode: julia --startup-file=no --project=<tree> --threads=4 measure_eig4d.jl
using Octopus, LinearAlgebra, Random, Printf

const S4 = Octopus._symplectic_form(4)
const MIN_GAP = 1e-6
const STAB = 1e-8
const TRACE_GAP = 1e-8
R(mu) = Octopus._rotation2(mu)
blockdiag(A, B) = [A zeros(2, 2); zeros(2, 2) B]

# c used by the testsets (keep in step with eig4d_testsets.jl)
const C_USED = Dict(
    "E3 normalization |u'Su+2i| / ||u||^2" => 64,
    "eigenvector (I1) normalized / max(1,||M||)" => 64,
    "E7 ||U'SU-S|| / (kq ||U||^2)" => 64,
    "E8 (I1) normalized / max(1,||M||)" => 64,
    "P idempotent ||P^2-P|| / ||P||^2" => 64,
    "P complete ||P1+P2-I|| / (kq ||U||^2)" => 64,
    "P disjoint ||P1P2|| / (kq ||U||^2)" => 64,
    "G = U_j U_j' / ||U||^2" => 16,
    "G PSD: -eigmin(G) / ||G||" => 64,
    "M2 row sums / ||u||^2" => 64,
    "M3 column sums / (kq ||U||^2)" => 64,
    "M5 |bg-a^2-k^2| / ||u||^4" => 64,
    "M4 u difference / (kq ||U||^2)" => 64,
    "kappa (M1) vs (PS)_{a,pa} / ||u||^2" => 16,
    "cf projector diff / kcf" => 64,
    "cf covariance diff / (kcf/min sin^2)" => 64,
    "cf outer diff / (kcf/min sin^2)" => 64,
    "cf kappa diff / kcf" => 64,
    "cf tune diff / (kcf/min|sin|)" => 64,
    "cf (I1) on E14 normalizer / (kcf/min sin^2)" => 64,
    "cf P residuals / kcf" => 64,
    "cf E3 on E14 vector / (kcf/min sin^2)" => 64,
    "cf G PSD margin / (kcf/min sin^2)" => 64,
    "cf E10 traces vs 2cos(mu) / kc" => 64,
    "actions xi vs u / (||U||^2 ||r||^2)" => 64,
    "actions invariance / (||U||^2 max(1,||M||)^2 ||r||^2)" => 64,
    "scaling beta,alpha,gamma / ksc" => 1000,
    "scaling kappa / ksc" => 1000,
    "scaling tunes / ksc" => 1000,
    "scaling P / ksc" => 1000,
    "scaling G / ksc" => 1000,
    "FODO beta,alpha vs T15 / kfodo" => 64,
    "FODO tune vs acos branch / kfodo" => 64,
    "FODO kappa_1y, kappa_2x / ||U||^2" => 64,
    "R(0.7)+R(0.31) tunes / 1" => 16,
    "R(0.7)+R(0.31) phase-fixed U = I / 1" => 64,
)
rows = Dict{String,Tuple{Float64,String,Float64}}()
function record!(name, ratio, fixture, raw)
    haskey(C_USED, name) || error("unnamed check $(name)")
    cur = get(rows, name, (-1.0, "", 0.0))
    ratio > cur[1] && (rows[name] = (ratio, fixture, raw))
    return nothing
end
E = eps(Float64)

function measure_frame!(M, name)
    r = Octopus._eigenmodes_4d(M; min_gap=MIN_GAP, stability_atol=STAB)
    is_determined(r.frame) || error("$(name): frame unavailable, $(r.frame)")
    f = determined_value(r.frame)
    U = f.normalizer; nU = norm(U)^2; nM = max(1, norm(M))
    g = r.spectrum.gap
    kq = max(1, opnorm(M)) * opnorm(U)^2 / g        # the design's chord amplifier: eigenvector direction error / eps
    for j in 1:2
        u = f.vectors[j]; nu = norm(u)^2
        record!("E3 normalization |u'Su+2i| / ||u||^2", f.normalization_residuals[j] / (E * nu), name, f.normalization_residuals[j])
        record!("eigenvector (I1) normalized / max(1,||M||)", f.eigenvector_residuals[j].normalized / (E * nM), name, f.eigenvector_residuals[j].normalized)
        P = f.projectors[j]; G = f.covariances[j]
        record!("P idempotent ||P^2-P|| / ||P||^2", norm(P * P - P) / (E * norm(P)^2), name, norm(P * P - P))
        Uj = U[:, 2j - 1:2j]
        record!("G = U_j U_j' / ||U||^2", norm(G - Uj * transpose(Uj)) / (E * nU), name, norm(G - Uj * transpose(Uj)))
        record!("G PSD: -eigmin(G) / ||G||", -eigmin(Symmetric(G)) / (E * norm(G)), name, -eigmin(Symmetric(G)))
        record!("M2 row sums / ||u||^2", abs(f.signed_area_row_sums[j] - 1) / (E * nu), name, abs(f.signed_area_row_sums[j] - 1))
        for a in 1:2
            m5 = abs(f.beta[j, a] * f.gamma[j, a] - f.alpha[j, a]^2 - f.signed_areas[j, a]^2)
            record!("M5 |bg-a^2-k^2| / ||u||^4", m5 / (E * nu^2), name, m5)
            kd = abs(f.signed_areas[j, a] - (P * S4)[2a - 1, 2a])
            record!("kappa (M1) vs (PS)_{a,pa} / ||u||^2", kd / (E * nu), name, kd)
        end
    end
    record!("E7 ||U'SU-S|| / (kq ||U||^2)", f.symplecticity_residual / (E * kq * nU), name, f.symplecticity_residual)
    record!("E8 (I1) normalized / max(1,||M||)", f.reconstruction_residual.normalized / (E * nM), name, f.reconstruction_residual.normalized)
    P1, P2 = f.projectors
    record!("P complete ||P1+P2-I|| / (kq ||U||^2)", norm(P1 + P2 - I) / (E * kq * nU), name, norm(P1 + P2 - I))
    record!("P disjoint ||P1P2|| / (kq ||U||^2)", norm(P1 * P2) / (E * kq * nU), name, norm(P1 * P2))
    for a in 1:2
        record!("M3 column sums / (kq ||U||^2)", abs(f.signed_area_column_sums[a] - 1) / (E * kq * nU), name, abs(f.signed_area_column_sums[a] - 1))
    end
    record!("M4 u difference / (kq ||U||^2)", abs(f.u_difference) / (E * kq * nU), name, abs(f.u_difference))
    # closed form
    cf = Octopus._closed_form_check_4d(f; min_trace_gap=TRACE_GAP, stability_atol=STAB)
    is_determined(cf) || error("$(name): closed form unavailable, $(cf)")
    c = determined_value(cf)
    root = abs(c.closed_form.traces[1] - c.closed_form.traces[2])
    kc = max(1, norm(M)^2) * max(1, nU) * (1 + 1 / (2 * root)) / root   # the (E11) arm: roundoff of M + M^-1 and of tau_k (eps ||M||^2 / (2 root)) over the trace gap
    kcf = kq * nU + kc                                   # either route's error
    smin = minimum(abs.(c.closed_form.sines))            # (E12) divides by sin mu_j
    record!("cf projector diff / kcf", c.projector_difference / (E * kcf), name, c.projector_difference)
    record!("cf covariance diff / (kcf/min sin^2)", c.covariance_difference / (E * kcf / smin^2), name, c.covariance_difference)
    record!("cf outer diff / (kcf/min sin^2)", c.outer_product_difference / (E * kcf / smin^2), name, c.outer_product_difference)
    record!("cf kappa diff / kcf", c.signed_area_difference / (E * kcf), name, c.signed_area_difference)
    record!("cf tune diff / (kcf/min|sin|)", c.tune_difference / (E * kcf / smin), name, c.tune_difference)
    record!("cf (I1) on E14 normalizer / (kcf/min sin^2)", c.closed_form.reconstruction_residual.normalized / (E * kcf / smin^2), name, c.closed_form.reconstruction_residual.normalized)   # fixer: the (E14) sum was an identity; the (I1) residual on U_cf replaces it
    record!("cf P residuals / kcf", max(c.closed_form.projector_residuals...) / (E * kcf), name, max(c.closed_form.projector_residuals...))
    record!("cf E3 on E14 vector / (kcf/min sin^2)", maximum(c.closed_form.normalization_residuals) / (E * kcf / smin^2), name, maximum(c.closed_form.normalization_residuals))
    record!("cf G PSD margin / (kcf/min sin^2)", -minimum(c.closed_form.covariance_min_eigenvalues) / (E * kcf / smin^2), name, -minimum(c.closed_form.covariance_min_eigenvalues))
    dtr = maximum(abs.(sort(collect(c.closed_form.traces)) .- sort([2cos(f.tunes[1]), 2cos(f.tunes[2])])))
    record!("cf E10 traces vs 2cos(mu) / kc", dtr / (E * kc), name, dtr)
    return f
end

# 1. 200 manufactured stable maps (seed 20260911), the suite's fixture set.
rng = Xoshiro(20260911)
frames = Any[]
for i in 1:200
    M, _ = Octopus._manufactured_symplectic_map(rng, 4; stable=true)
    push!(frames, (M, measure_frame!(M, "manufactured map $(i)")))
end
# 2. actions on random points (first 50 maps, 3 points each)
rng2 = Xoshiro(20260911 + 1)
for (i, (M, f)) in enumerate(frames[1:50]), k in 1:3
    r = randn(rng2, 4)
    J = Octopus._mode_actions(f, r)
    JM = Octopus._mode_actions(f, M * r)
    nU = norm(f.normalizer)^2; nr = norm(r)^2
    d1 = maximum(abs.(J.from_normal_coordinates .- J.from_vectors))
    record!("actions xi vs u / (||U||^2 ||r||^2)", d1 / (E * nU * nr), "map $(i) point $(k)", d1)
    d2 = maximum(abs.(JM.from_normal_coordinates .- J.from_normal_coordinates))
    record!("actions invariance / (||U||^2 max(1,||M||)^2 ||r||^2)", d2 / (E * nU * max(1, norm(M))^2 * nr), "map $(i) point $(k)", d2)
end
# 3. scaling invariance on the first 20 maps, three scalings
for (i, (M, f)) in enumerate(frames[1:20]), sc in ((2.0, 0.5), (0.3, 4.0), :auto)
    rec = Octopus._reciprocal_scaling(M, sc)
    C = Octopus._scaling_matrix(rec); condC = cond(Matrix(C))
    Ms = Octopus._scale_map(rec, M)
    rs = Octopus._eigenmodes_4d(Ms; min_gap=MIN_GAP, stability_atol=STAB)
    fs = determined_value(rs.frame)
    kqM = max(1, opnorm(M)) * opnorm(f.normalizer)^2 / Octopus._eigenmodes_4d(M; min_gap=MIN_GAP, stability_atol=STAB).spectrum.gap
    kqS = max(1, opnorm(Ms)) * opnorm(fs.normalizer)^2 / rs.spectrum.gap
    ksc = condC^2 * max(kqM, kqS) * max(norm(f.normalizer)^2, norm(fs.normalizer)^2)
    nm = "map $(i) scaling $(sc)"
    dtw = 0.0
    for j in 1:2, a in 1:2
        b, al, g = Octopus._unscale_twiss(rec, a, fs.beta[j, a], fs.alpha[j, a], fs.gamma[j, a])
        dtw = max(dtw, abs(b - f.beta[j, a]), abs(al - f.alpha[j, a]), abs(g - f.gamma[j, a]))
    end
    record!("scaling beta,alpha,gamma / ksc", dtw / (E * ksc), nm, dtw)
    dk = maximum(abs.(fs.signed_areas - f.signed_areas))
    record!("scaling kappa / ksc", dk / (E * ksc), nm, dk)
    dt = maximum(abs.(fs.tunes .- f.tunes))
    record!("scaling tunes / ksc", dt / (E * ksc), nm, dt)
    dP = maximum(norm(Octopus._unscale_projector(rec, fs.projectors[j]) - f.projectors[j]) for j in 1:2)
    record!("scaling P / ksc", dP / (E * ksc), nm, dP)
    dG = maximum(norm(Octopus._unscale_covariance(rec, fs.covariances[j]) - f.covariances[j]) for j in 1:2)
    record!("scaling G / ksc", dG / (E * ksc), nm, dG)
end
# 4. the uncoupled FODO of validation/lattice_cells.jl (kq = 1.6), rebuilt inline
# The SYMMETRIC cell (kd = -kf) has exactly equal x and y traces (cyclicity of
# the trace) and is a degenerate cluster; the design's detuning K_1D = -(1 + eps)
# with eps = 1e-3 (its "resolved" control) is the accepted fixture here.
kq = 1.6
function fodo4(kf, kd)
    qf = compile_runtime(QuadrupoleSpec(L=0.3, kn=(0.0, kf), nst=4, integrator_order=4))
    qd = compile_runtime(QuadrupoleSpec(L=0.3, kn=(0.0, kd), nst=4, integrator_order=4))
    dr = compile_runtime(DriftSpec(L=1.2))
    M6, _ = one_turn_matrix((qf, dr, qd, dr))
    return M6[1:4, 1:4]
end
M4 = fodo4(kq, -kq * (1 + 1e-3))
ff = measure_frame!(M4, "detuned FODO kq=1.6, eps=1e-3")
for (a, blk) in ((1, M4[1:2, 1:2]), (2, M4[3:4, 3:4]))
    t = blk[1, 1] + blk[2, 2]
    smu = sign(blk[1, 2]) * sqrt(1 - (t / 2)^2)
    beta_ref = blk[1, 2] / smu; alpha_ref = (blk[1, 1] - blk[2, 2]) / (2smu)
    mu_ref = blk[1, 2] > 0 ? acos(t / 2) : 2pi - acos(t / 2)
    gf = Octopus._eigenmodes_4d(M4; min_gap=MIN_GAP, stability_atol=STAB).spectrum.gap
    kfodo = max(1, opnorm(M4)) * opnorm(ff.normalizer)^2 / gf * norm(ff.normalizer)^2 / abs(smu)
    d = max(abs(ff.beta[a, a] - beta_ref), abs(ff.alpha[a, a] - alpha_ref))
    record!("FODO beta,alpha vs T15 / kfodo", d / (E * kfodo), "FODO plane $(a)", d)
    record!("FODO tune vs acos branch / kfodo", abs(ff.tunes[a] - mu_ref) / (E * kfodo), "FODO plane $(a)", abs(ff.tunes[a] - mu_ref))
end
dk = max(abs(ff.signed_areas[1, 2]), abs(ff.signed_areas[2, 1]))
record!("FODO kappa_1y, kappa_2x / ||U||^2", dk / (E * norm(ff.normalizer)^2), "FODO", dk)
# 5. the rotation fixture
Mrot = blockdiag(R(2pi * 0.7), R(2pi * 0.31))
fr = measure_frame!(Mrot, "R(0.7)+R(0.31)")
dt = max(abs(fr.tunes[1] / (2pi) - 0.7), abs(fr.tunes[2] / (2pi) - 0.31))
record!("R(0.7)+R(0.31) tunes / 1", dt / E, "rotation", dt)
Ufix = zeros(4, 4)
for j in 1:2
    u = fr.vectors[j]; b = 2j - 1
    u = u * (conj(u[b]) / abs(u[b]))
    Ufix[:, b] = real(u); Ufix[:, b + 1] = -imag(u)
end
record!("R(0.7)+R(0.31) phase-fixed U = I / 1", norm(Ufix - I) / E, "rotation", norm(Ufix - I))

println("\n| check | required c (max ratio / eps kappa) | argmax fixture | max raw | c used | ratio to used |")
println("|---|---|---|---|---|---|")
for name in sort(collect(keys(C_USED)))
    haskey(rows, name) || (println("| $(name) | NOT MEASURED |"); continue)
    ratio, fx, raw = rows[name]
    @printf("| %s | %.3g | %s | %.3g | %d | %.3g |\n", name, ratio, fx, raw, C_USED[name], ratio / C_USED[name])
end

# Rejected fixtures: residual / threshold must exceed ten.
println("\n| rejected fixture | quantity | value | threshold | ratio | reason |")
println("|---|---|---|---|---|---|")
function rej(name, M)
    r = Octopus._eigenmodes_4d(M; min_gap=MIN_GAP, stability_atol=STAB)
    s = r.spectrum
    if r.frame.reason === :unstable_spectrum
        @printf("| %s | unit-circle departure | %.3g | %.1g | %.3g | %s |\n", name, s.unit_circle_departure, STAB, s.unit_circle_departure / STAB, r.frame.reason)
    elseif r.frame.reason === :cluster_unresolved
        @printf("| %s | min_gap / gap | %.3g | %.1g | %s | %s |\n", name, s.gap, MIN_GAP, s.gap == 0 ? "Inf" : @sprintf("%.3g", MIN_GAP / s.gap), r.frame.reason)
    else
        @printf("| %s | unit-eigenvalue distance | %.3g | %.1g | %.3g | %s |\n", name, s.unit_eigenvalue_distance, STAB, STAB / max(s.unit_eigenvalue_distance, 1e-300), r.frame.reason)
    end
end
rej("diag(2, 1/2, R(1.2))", blockdiag([2.0 0; 0 0.5], R(1.2)))
rej("R(0.9) (+) R(0.9)", blockdiag(R(0.9), R(0.9)))
rej("R(0.9) (+) R(-0.9)", blockdiag(R(0.9), R(-0.9)))
rej("R(0.9) (+) R(0.9 + 1e-7)", blockdiag(R(0.9), R(0.9 + 1e-7)))
rej("identity", Matrix(1.0I, 4, 4))
rej("symmetric FODO kq=1.6 (exact)", fodo4(kq, -kq))
rej("diag(1+1e-6, 1/(1+1e-6), R(1.2))", blockdiag([1 + 1e-6 0; 0 1 / (1 + 1e-6)], R(1.2)))
# closed-form guard at the equal-trace fixture
for (nm, M) in (("R(0.9) (+) R(0.9)", blockdiag(R(0.9), R(0.9))), ("R(0.9) (+) R(-0.9)", blockdiag(R(0.9), R(-0.9))),
                ("R(0.9) (+) R(0.9 + 1e-7)", blockdiag(R(0.9), R(0.9 + 1e-7))),
                ("symmetric FODO kq=1.6 (exact)", fodo4(kq, -kq)))
    cf = Octopus._closed_form_eigenmodes_4d(M; min_trace_gap=TRACE_GAP, stability_atol=STAB)
    rad = 2 * tr(M * M) - tr(M)^2 + 8
    @printf("| closed form %s | |tau+ - tau-| | %.3g | %.1g | %s | %s |\n", nm, sqrt(abs(rad)), TRACE_GAP, sqrt(abs(rad)) == 0 ? "Inf" : @sprintf("%.3g", TRACE_GAP / sqrt(abs(rad))), cf.reason)
end
# accepted side of the guards: worst departure and smallest gap over the 200 maps
worst_dep = 0.0; worst_name = ""; small_gap = Inf; small_name = ""; small_root = Inf; small_root_name = ""
for (i, (M, f)) in enumerate(frames)
    s = Octopus._eigenmodes_4d(M; min_gap=MIN_GAP, stability_atol=STAB).spectrum
    s.unit_circle_departure > worst_dep && (global worst_dep = s.unit_circle_departure; global worst_name = "map $(i)")
    s.gap < small_gap && (global small_gap = s.gap; global small_name = "map $(i)")
    rt = sqrt(abs(s.discriminant_e10))
    rt < small_root && (global small_root = rt; global small_root_name = "map $(i)")
end
@printf("\naccepted side: largest unit-circle departure %.3g (%s), ratio to STAB %.3g; smallest gap %.3g (%s), ratio to MIN_GAP %.3g; smallest |tau+ - tau-| %.3g (%s), ratio to TRACE_GAP %.3g\n",
        worst_dep, worst_name, worst_dep / STAB, small_gap, small_name, small_gap / MIN_GAP, small_root, small_root_name, small_root / TRACE_GAP)
```

`measure_param.jl` (the Part B probe; includes the file-level helpers of the Part B test block from `param_testsets.jl`, the byte-identical source of `test/runtests.jl` 1533-1572):

```julia
# Measurement of the Part B tolerance constants: for every check of
# param_testsets.jl the ratio (observed residual) / (eps kappa) is the c the
# check REQUIRES; the file's c must be >= 10x the largest required c on the
# accepted fixtures (design "Verification plan"). Package mode:
#   julia --startup-file=no --project=<tree> --threads=4 measure_param.jl
# Prints the max required c per check family with the argmax fixture index.
using Octopus, LinearAlgebra, Random
# The file-level helpers and fixtures of param_testsets.jl (everything before its first testset).
include_string(Main, split(read(joinpath(@__DIR__, "..", "param_testsets.jl"), String), "\n@testset")[1])
req = Dict{String, Tuple{Float64, String}}()
function bump!(k, ratio, who)
    r = get(req, k, (0.0, ""))
    ratio > r[1] && (req[k] = (ratio, who))
end
val = determined_value
# --- Mais-Ripken identities on the 200 normalizers
for (i, (U, mu)) in enumerate(_PB_NORMALIZERS)
    nU = norm(U)^2; mr = Octopus._mais_ripken(U); who = "normalizer $i"
    for j in 1:2
        bump!("M2 row sum / nU", abs(mr.kappa_row_sums[j] - 1) / (eps() * nU), who)
        bump!("M3 col sum / nU", abs(mr.kappa_column_sums[j] - 1) / (eps() * nU), who)
        for a in 1:2; bump!("M5 / nU^2", abs(mr.m5_residuals[j, a]) / (eps() * nU^2), who); end
        p = val(mr.phases[j]); bump!("phase norm / nU", abs(p.cos^2 + p.sin^2 - 1) / (eps() * nU), who)
    end
    bump!("M4 diff / nU", abs(mr.u_difference) / (eps() * nU), who)
    v1, v2 = mr.vectors
    bump!("rephase imag / norm(u)", max(abs(imag(v1[1])) / norm(v1), abs(imag(v2[3])) / norm(v2)) / eps(), who)
    U8 = val(Octopus._mais_ripken_normalizer(mr)); mb = minimum(mr.beta)
    bump!("M8 rebuild / (nU/minbeta)", norm(U8 - Octopus._vectors_to_normalizer(v1, v2)) / (eps() * nU / mb), who)
    bump!("M8 sympl / (nU^2/minbeta)", norm(transpose(U8) * _PB_S4 * U8 - _PB_S4) / (eps() * nU^2 / mb), who)
    Rb = _pb_blockdiag(_pb_R(mu[1]), _pb_R(mu[2])); M = U * Rb * Octopus._symplectic_inverse(U)
    bump!("M8 (I1) / (nM nU/minbeta)", Octopus._invariance_residual(M, U8, Rb).normalized / (eps() * max(1, norm(M)) * nU / mb), who)
    e = (1.3, 0.4); ne = maximum(e)
    S9 = Octopus._matched_covariance_4d(U, e); u1, u2 = Octopus._normalizer_to_vectors(U)
    bump!("M9 two forms / (nU ne)", norm(S9 - Octopus._matched_covariance_4d(u1, u2, e)) / (eps() * nU * ne), who)
    bump!("M12 vs M9 / (nU ne/minbeta)", norm(val(Octopus._mais_ripken_covariance(mr, e)) - S9) / (eps() * nU * ne / mb), who)
    bump!("M13 / (nU/minbeta)", maximum(abs, Octopus._mais_ripken_gamma_identities(mr)) / (eps() * nU / mb), who)
    bump!("closure / (nU ne nM^2)", norm(M * S9 * transpose(M) - S9) / (eps() * nU * ne * max(1, norm(M))^2), who)
end
# --- Edwards-Teng routes on the 200 maps (eigen frame from the test-local builder)
for (i, M) in enumerate(_PB_MAPS)
    f = _pb_frame(M); U = f.U; mu = f.tunes; who = "map $i"
    nU = norm(U)^2; nM = max(1, norm(M))
    kq = max(1, opnorm(M)) * opnorm(U)^2 / f.gap
    kT = 1 / minimum(abs.(sin.(mu)))
    etn = Octopus._edwards_teng_from_normalizer(U, mu; M4=M)
    etd = Octopus._edwards_teng_direct(f.u1, f.u2; tunes=mu, M4=M)
    etm = Octopus._edwards_teng_from_map(M; min_trace_gap=_PB_TRACE_GAP, mode_traces=(2cos(mu[1]), 2cos(mu[2])))
    bump!("u n-m / (kq nU)", abs(val(etn.u) - val(etm.u)) / (eps() * kq * nU), who)
    f1, f2 = etn.form1, etn.form2
    wmin = min(abs(f1.area_weight), abs(f2.area_weight))
    bump!("detR1 detR2 - 1 / (nU^2/wmin^2)", abs(val(f1.det_R) * val(f2.det_R) - 1) / (eps() * nU^2 / wmin^2), who)
    bump!("R2 + R1/d1 / (nU^2/wmin^2)", norm(val(f2.R) + val(f1.R) / val(f1.det_R)) / (eps() * nU^2 / wmin^2), who)
    for (fn, fd, fm) in ((etn.form1, etd.form1, etm.form1), (etn.form2, etd.form2, etm.form2))
        w = fn.area_weight; kR = nU / abs(w); Rn = val(fn.R); sR = max(1, norm(Rn))
        bump!("R n-d / (kR sR)", norm(Rn - val(fd.R)) / (eps() * kR * sR), who)
        bump!("R n-m / (kq kR sR)", norm(Rn - val(fm.R)) / (eps() * kq * kR * sR), who)
        bump!("w n-d / nU", abs(w - fd.area_weight) / (eps() * nU), who)
        bump!("w n-m / (kq nU w^2)", abs(w - fm.area_weight) / (eps() * kq * nU * max(1, abs(w))^2), who)
        bump!("B10 consistency / (kR sR)", fn.consistency_residual / (eps() * kR * sR), who)
        fn.admissible || continue
        lam = val(fn.lambda)
        bump!("lambda^2 - w / kR", abs(lam^2 - w) / (eps() * kR), who)
        tn, td, tm = val(fn.twiss), val(fd.twiss), val(fm.twiss)
        for j in 1:2
            bump!("mu n-m / (kq kT nU)", abs(mod(tm[j].mu - mu[j] + pi, 2pi) - pi) / (eps() * kq * kT * nU), who)
            bump!("unit area / kR^2", abs(tn[j].beta * tn[j].gamma - tn[j].alpha^2 - 1) / (eps() * kR^2), who)
            for k in (:beta, :alpha, :gamma)
                sc = max(1, abs(tn[j][k]))
                bump!("twiss n-d / (kR sc)", abs(tn[j][k] - td[j][k]) / (eps() * kR * sc), who)
                bump!("twiss n-m / (kq kR kT sc)", abs(tn[j][k] - tm[j][k]) / (eps() * kq * kR * kT * sc), who)
            end
        end
        bn, bd, bm = val(fn.blocks), val(fd.blocks), val(fm.blocks)
        for j in 1:2
            bump!("blocks n-d / (kR sB)", norm(bn[j] - bd[j]) / (eps() * kR * max(1, norm(bn[j]))), who)
            bump!("blocks n-m / (kq kR sB)", norm(bn[j] - bm[j]) / (eps() * kq * kR * max(1, norm(bn[j]))), who)
            bump!("T11 trace / (kq nU)", abs(tr(bm[j]) - 2cos(mu[j])) / (eps() * kq * nU), who)
        end
        for g in (fn, fd, fm)
            bump!("T5 rec / (kq kR nM)", val(g.reconstruction_residual).normalized / (eps() * kq * kR * nM), who)
        end
        V = Octopus._edwards_teng_V(fn.form, Rn)
        bump!("V sympl / sV^2", norm(transpose(V) * _PB_S4 * V - _PB_S4) / (eps() * max(1, norm(V))^2), who)
        bump!("T1 rebuild / (kR nM sV^2)", norm(V * _pb_blockdiag(bn...) * Octopus._symplectic_inverse(V) - M) / (eps() * kR * nM * max(1, norm(V))^2), who)
        Uet = Octopus._edwards_teng_normalizer(fn.form, Rn, tn[1].beta, tn[1].alpha, tn[2].beta, tn[2].alpha)
        mret = Octopus._mais_ripken(Uet); mb = minimum(mret.beta)
        for g in (fn, fd, fm), j in 1:2
            pg = val(g.phases)[j]; pm = val(mret.phases[j])
            bump!("phases vs M6 / (kq? kR nU/minbeta)", hypot(pg.cos - pm.cos, pg.sin - pm.sin) / (eps() * (g.route === :map ? kq : 1) * kR * nU / mb), who)
        end
        Rb = _pb_blockdiag(_pb_R(mu[1]), _pb_R(mu[2]))
        bump!("Uet (I1) / (kq kR nM)", Octopus._invariance_residual(M, Uet, Rb).normalized / (eps() * kq * kR * nM), who)
        Q1 = [tn[1].beta -tn[1].alpha; -tn[1].alpha tn[1].gamma]; Q2 = [tn[2].beta -tn[2].alpha; -tn[2].alpha tn[2].gamma]
        A = Octopus._adjugate2(Rn); proj(K, Q) = lam^2 * K * Q * transpose(K)
        tab = fn.form == 1 ? ((lam^2 * Q1, proj(Rn, Q1)), (proj(A, Q2), lam^2 * Q2)) : ((proj(A, Q1), lam^2 * Q1), (lam^2 * Q2, proj(Rn, Q2)))
        for j in 1:2, a in 1:2
            T = tab[j][a]; sc = max(1, norm(T))
            bump!("7.2/7.3 tables / (kR nU sT)", max(abs(mret.beta[j, a] - T[1, 1]), abs(mret.alpha[j, a] + T[1, 2]), abs(mret.gamma[j, a] - T[2, 2])) / (eps() * kR * nU * sc), who)
        end
        U8 = val(Octopus._mais_ripken_normalizer(mret))
        et8 = Octopus._edwards_teng_from_normalizer(U8, mu; M4=M)
        g8 = fn.form == 1 ? et8.form1 : et8.form2
        bump!("M8 -> B10 R / (kR nU sR/minbeta)", norm(val(g8.R) - Rn) / (eps() * kR * nU * sR / mb), who)
        t8 = val(g8.twiss)
        for j in 1:2, k in (:beta, :alpha, :gamma)
            bump!("M8 -> B5/B9 twiss / (kR nU sc/minbeta)", abs(t8[j][k] - tn[j][k]) / (eps() * kR * nU * max(1, abs(tn[j][k])) / mb), who)
        end
    end
end
# --- Coupled construction (benchmark 12.2-2)
let
    bx, ax, mux = 2.0, 0.3, 2pi * 0.7; by, ay, muy = 1.5, -0.4, 2pi * 0.31; bz, muz = 10.0, 2pi * 0.05
    Rs = ((0.5, 0.5, 1.5, 0.5), (0.4, 0.2, 0.6, 0.3), (0.5, 0.2, -0.1, 0.56), (0.8, 0.3, -0.6, 1.025))
    m0 = compile_runtime(Linear6DSpec(beta1=(bx, by, bz), alpha1=(ax, ay, 0.0), dmu=(mux, muy, muz)))
    for (mode, form) in ((XY_MODEA, 1), (XY_MODEB, 2)), r in Rs
        Rm = [r[1] r[2]; r[3] r[4]]; d = det(Rm); w = 1 / (1 + d); who = "construction form $form det $(round(d, digits=2))"
        W = compile_runtime(XYCouplingSpec(r1=r[1], r2=r[2], r3=r[3], r4=r[4], mode=mode))
        Winv = form == 1 ? compile_runtime(XYCouplingSpec(r1=-r[1], r2=-r[2], r3=-r[3], r4=-r[4], mode=mode)) :
                           compile_runtime(XYCouplingSpec(r1=r[4], r2=-r[2], r3=-r[3], r4=r[1], mode=mode))
        M = one_turn_matrix((Winv, m0, W)).matrix[1:4, 1:4]
        f = _pb_frame(M; expected=(mux, muy)); nU = norm(f.U)^2; kq = max(1, opnorm(M)) * opnorm(f.U)^2 / f.gap
        bump!("construction tunes / kq", max(abs(f.tunes[1] - mux), abs(f.tunes[2] - muy)) / (eps() * kq), who)
        for (et, rn) in ((Octopus._edwards_teng_from_normalizer(f.U, f.tunes; M4=M), "n"), (Octopus._edwards_teng_direct(f.u1, f.u2; tunes=f.tunes, M4=M), "d"),
                         (Octopus._edwards_teng_from_map(M; min_trace_gap=_PB_TRACE_GAP, mode_traces=(2cos(mux), 2cos(muy))), "m"))
            g = form == 1 ? et.form1 : et.form2; other = form == 1 ? et.form2 : et.form1
            bump!("construction R / (kq nU sR/w)", norm(val(g.R) - Rm) / (eps() * kq * nU * max(1, norm(Rm)) / w), who * " " * rn)
            bump!("construction lambda / (kq nU/w^2)", abs(val(g.lambda) - 1 / sqrt(1 + d)) / (eps() * kq * nU / w^2), who * " " * rn)
            bump!("construction weight / (kq nU/w)", abs(g.area_weight - w) / (eps() * kq * nU / w), who * " " * rn)
            t = val(g.twiss)
            for (j, (b, a, mu)) in enumerate(((bx, ax, mux), (by, ay, muy)))
                bump!("construction beta / (kq nU b/w)", abs(t[j].beta - b) / (eps() * kq * nU * b / w), who * " " * rn)
                bump!("construction alpha / (kq nU sa/w)", abs(t[j].alpha - a) / (eps() * kq * nU * max(1, abs(a)) / w), who * " " * rn)
                bump!("construction mu / (kq nU)", abs(mod(t[j].mu - mu + pi, 2pi) - pi) / (eps() * kq * nU), who * " " * rn)
            end
            bump!("construction T5 / (kq nU nM/w)", val(g.reconstruction_residual).normalized / (eps() * kq * nU * max(1, norm(M)) / w), who * " " * rn)
            uexp = form == 1 ? d / (1 + d) : 1 / (1 + d)
            bump!("construction u / (kq nU)", abs(val(et.u) - uexp) / (eps() * kq * nU), who * " " * rn)
            if d > 0
                bump!("construction other det / (kq nU sR^2/(w d)^2)", abs(val(other.det_R) - 1 / d) / (eps() * kq * nU * max(1, norm(Rm))^2 / (w * d)^2), who * " " * rn)
                bump!("construction other lambda^2 / (kq nU/min(w,1-w)^2)", abs(val(other.lambda)^2 - (1 - w)) / (eps() * kq * nU / min(w, 1 - w)^2), who * " " * rn)
            elseif d == 0
                bump!("REJECTED zero weight (other form) |w| / (kq nU) [want > 10 x floor... reported raw]", abs(other.area_weight) / eps(), who * " " * rn)
            end
        end
    end
end
# --- Uncoupled FODO (detuned kd (1 + 1e-3)) and the exact cell's guard
let
    function pb_fodo4(kf, kd)
        qf = compile_runtime(QuadrupoleSpec(L=0.3, kn=(0.0, kf), nst=4, integrator_order=4))
        qd = compile_runtime(QuadrupoleSpec(L=0.3, kn=(0.0, kd), nst=4, integrator_order=4))
        dr = compile_runtime(DriftSpec(L=1.2))
        return one_turn_matrix((qf, dr, qd, dr)).matrix[1:4, 1:4]
    end
    Mexact = pb_fodo4(1.6, -1.6)
    Mxx, Mxy, Myx, Myy = Mexact[1:2, 1:2], Mexact[1:2, 3:4], Mexact[3:4, 1:2], Mexact[3:4, 3:4]
    println("FODO exact: sqrt(Delta) = ", sqrt(max(0, (tr(Mxx) - tr(Myy))^2 + 4det(Octopus._adjugate2(Mxy) + Myx))), " (guard 1e-8: rejected ratio = guard / sqrtDelta)")
    M = pb_fodo4(1.6, -1.6 * (1 + 1e-3))
    Mxx, Myy = M[1:2, 1:2], M[3:4, 3:4]
    println("FODO detuned: sqrt(Delta) = ", abs(tr(Mxx) - tr(Myy)), " accepted ratio = sqrtDelta / guard = ", abs(tr(Mxx) - tr(Myy)) / 1e-8)
    f = _pb_frame(M); nU = norm(f.U)^2; kq = max(1, opnorm(M)) * opnorm(f.U)^2 / f.gap
    mr = Octopus._mais_ripken(f.U)
    bump!("FODO kappa_1y, kappa_2x / (kq nU)", max(abs(mr.kappa[1, 2]), abs(mr.kappa[2, 1])) / (eps() * kq * nU), "FODO detuned")
    for (et, rn) in ((Octopus._edwards_teng_from_normalizer(f.U, f.tunes; M4=M), "n"), (Octopus._edwards_teng_direct(f.u1, f.u2; tunes=f.tunes, M4=M), "d"),
                     (Octopus._edwards_teng_from_map(M; min_trace_gap=_PB_TRACE_GAP), "m"))
        g = et.form1
        bump!("FODO R / (kq nU)", norm(val(g.R)) / (eps() * kq * nU), "FODO " * rn)
        bump!("FODO lambda - 1 / (kq nU)", abs(val(g.lambda) - 1) / (eps() * kq * nU), "FODO " * rn)
        bump!("FODO form-2 weight / (kq nU)", abs(et.form2.area_weight) / (eps() * kq * nU), "FODO " * rn)
        t = val(g.twiss)
        for (j, blk) in enumerate((M[1:2, 1:2], M[3:4, 3:4]))
            cs = val(Octopus._twiss_from_block(blk))
            bump!("FODO beta vs CS / (kq nU b)", abs(t[j].beta - cs.beta) / (eps() * kq * nU * cs.beta), "FODO " * rn)
            bump!("FODO alpha vs CS / (kq nU sa)", abs(t[j].alpha - cs.alpha) / (eps() * kq * nU * max(1, abs(cs.alpha))), "FODO " * rn)
            bump!("FODO mu vs CS / (kq nU)", abs(mod(t[j].mu - cs.mu + pi, 2pi) - pi) / (eps() * kq * nU), "FODO " * rn)
        end
    end
    println("FODO detuned: kq = $kq, nU = $nU, gap = $(f.gap), phase floors: sqrt(b1x b1y) = $(sqrt(mr.beta[1,1]*mr.beta[1,2])) vs 64 eps ||u||^2 = $(64eps()*norm(f.u1)^2)")
end
# --- Table: required c per check family (the file uses c = 64 everywhere; rule: 64 >= 10 x required)
println("\n| check (residual / (eps kappa)) | required c (max ratio) | argmax fixture | 64 / required |")
println("|---|---|---|---|")
for k in sort(collect(keys(req)))
    r, who = req[k]
    println("| ", k, " | ", round(r, sigdigits=3), " | ", who, " | ", round(64 / max(r, 1e-300), sigdigits=3), " |")
end
println("\nWORST accepted required c: ", maximum(v[1] for (k, v) in req if !startswith(k, "REJECTED")), " -> 64 / worst = ",
        64 / maximum(v[1] for (k, v) in req if !startswith(k, "REJECTED")))
```

## 2026-09-11: full gate on the stage 1 and stage 2 batch (1f6f9b7)

Both stage commits (1bb75e4, 1f6f9b7) named this run as their gate: one full
gate on the assembled tree of the batch before the push (AGENTS.md Definition
of Done, owner decision 2026-09-04). It ran on 2026-09-11 on the clean tree
at 1f6f9b7, CUDA active (RTX 4500 Ada, an unrelated IJulia kernel holding
about 12 of 24 GiB), on acnlinj4 at four threads, launched detached by a
fresh agent so nothing else compiled against the depot while it ran:

    julia --project=. --threads=4 -e 'using Pkg; Pkg.test(julia_args=["--threads=4"])'

| item | value |
|---|---|
| tree | 1f6f9b7 (`git status` clean) |
| start / end / wall | 22:44:47 / 23:25:41 EDT / 40 min 54 s (about 5 min of it precompilation) |
| exit code | 0 (`Testing Octopus tests passed`) |
| test summary | 252 top-level testset rows, every one `Pass == Total`; summed 108556 passed of 108556; no Fail, Error or Broken column anywhere in the log |
| skipped or unrunnable | none: no `LANE SKIP` banner (full lane), no skipped or broken testset; the CUDA (35 rows, e.g. `CUDA PIC parity across every execution route`), ForwardDiff (`ForwardDiff differentiates the lattice` 15/15, extension loaded), MPI launcher (`The multi-process seam runs under an MPI launcher` 1710/1710) and example-execution (`Every example script runs against the current interface` 5/5) sections all ran |
| CUDA | active (`CUDA coverage status` passed; the test process held 412 MiB of device memory); 40 non-fatal `Warning:` lines of 11 distinct texts (launch-threads reductions, deprecations, the two known `observer_option_schema` test-side overwrites), none new to this batch |
| log | `result/gates/full_gate_stage12_2026_09_11.log` (git-ignored; the counts above are copied from it) |

This section is the only change between the gated tree and the pushed tree;
the commit carrying it is markdown-only and finishes with the fast lane on
its own tree (matrix row "markdown only"), `result/gates/fast_lane_gate_record_2026_09_11.log`; its exit code is named in that commit's message.

## 2026-09-12: stage 3 landed (mode clusters, Krein classification, ambiguity set, resolution chord)

Stage 3 of the design note's staging: `feat(analysis)`. Registry snapshot
UNCHANGED (the three new result structs `ClusterMode`, `ModeCluster`,
`ModeClusters` are plain types, none a subtype of a registry root). Nothing in
this stage claims an analysis exists: no `TwissDispersionAnalysis`, no
`analyze`, `summarize_registry().analyses` is still `[:PlaceholderAnalysis]`,
the stage-guard testset stayed green on the folded tree, nothing new is
exported (the public verb is stage 4). No `DETERMINATION_REASONS` member was
added; the cluster classification vocabulary `CLUSTER_CLASSIFICATIONS =
(:definite, :indefinite, :unresolved, :unstable, :unit_eigenvalue)` is new and
pinned the way `DETERMINATION_REASONS` is. Every kernel computes on the
(already scaled) matrix it is given; undetermined outputs are `Determined`
values with a pinned reason, never NaN. The stage 2 PROVISIONAL guards of the
4D frame (`min_gap`, `stability_atol`, the 64 eps orientation floor) are gone:
the frame is built on the clusters (D11). The resolution chord's default is
FROZEN by measurement at `1e-3` (the provisional `1e-4` lay inside the bracket
but the rounded geometric mean differed, so the measured value won; the
arithmetic is below and in the constant's docstring).

Work of 2026-09-12 (parts A1, A2, B in two worktrees at c488dff; integrator,
four reviewers, fixer, measurement D1 and this record on the main tree). The
dates in the todo row and the README distinguish stages 1-2 (2026-09-11) from
stage 3 (2026-09-12).

### What landed

| File | Change | Content |
|---|---|---|
| `src/analysis/mode_clusters.jl` | new, 1323 lines, internal `_` names | `CLUSTER_CLASSIFICATIONS` (pinned); `ClusterMode` (index, eigenvalue, tune, vector, eigenvector_residual (normalized, raw), normalization_residual); `ModeCluster` (35 fields: members, half_members, oriented eigenvalues and tunes, classification, reason, detail, conjugated, Schur basis and half/full blocks, departure from normality, stability scale, unit-circle departures, Gram matrix, eigenvalues, Krein signs and floor, `frame`, `signed_basis`, Schur spectral `projector`, `projector_n5_difference`, `covariance`, `restricted_map`, `residuals` (subspace, minimal_polynomial, projector_idempotent, projector_commutes, projector_adjoint) and `frame_residuals` (normalization, isotropy, unitarity, eigenvector), rho_M1, both kappa estimates, internal and external gap, chord_matrix, resolved, forced, `modes`); `ModeClusters` (matrix, canonical eigenvalues, conjugate_partner, real_class, tau_real, schur_backward_error, rho_M0, rho_M1, resolution_chord, partition_source, clusters, resolution_receipt, inter_cluster_chords, degeneracy_status); `_mode_clusters(M; rho_M0, resolution_chord=_DEFAULT_RESOLUTION_CHORD, partition=nothing)` with the kernels `_canonical_spectrum` (one complex Schur decomposition, canonical order), `_real_class_mask`, `_conjugate_pairs`, `_pair_gap`, `_cluster_gap`, `_external_gap`, `_ordered_schur_basis(F, select, M)`, `_gram_matrix`, `_krein_classification`, `_cluster_stability(...; kappa)`, `_cluster_frame` (N20 + N4), `_group_quantities` (N5, N21, N19), `_schur_spectral_projector` (D7d, `sylvester`), `_recover_modes` (D7e, eigenvalues snapped to the oriented Schur values), `_chord`, `_agglomerate` (D6), `_check_partition`, `_column_eigenvector_residual`, `_evaluate_component`, `_component_basis` and the smaller helpers, every one documented; six PROVISIONAL constants with their measurement in the docstring: `_DEFAULT_RESOLUTION_CHORD = 1.0e-3` (frozen), `_REAL_CLASS_MULTIPLIER = 1.0`, `_STABILITY_MULTIPLIER = 64.0`, `_GRAM_FLOOR_MULTIPLIER = 64.0`, `_MINIMAL_POLYNOMIAL_MULTIPLIER = 64.0`, `_SUBSPACE_RESIDUAL_MULTIPLIER = 64.0`. |
| `src/analysis/degenerate_dispersion.jl` | new, 378 lines, internal `_` names | `_check_cluster_frame(U_c; multiplier)` (N4 residuals, `ArgumentError` above `c eps m max(1, kappa)`), `_sampled_mode_dispersion(U_c, c)` ((N10)/(D12) readout of one member, unit `c` required), `_ambiguity_factor(A, columns; tol_psd)` (PSD eigen-factorization, negative eigenvalues below `-tol_psd` an error, rank asserted, zero-padded to `2m - 1`; no Cholesky), `_ambiguity_kind(internal_gap, rho_M1; exact_set_multiplier)` (:exact_set iff `gap <= c rho_M1`, else :orientation_envelope), `_dispersion_ambiguity_set(U_c; kind)` and `(P_c, G_c, multiplicity; kind)` per D9 (center `P_c[1:4, 6] / 2`, shape (N11) symmetrized and reported as `F F'`, factor `4 x (2m - 1)`; every refusal named before any set is built; the midpoint is never a dispersion), the thin methods `_dispersion_ambiguity_set(c::ModeCluster; kind=nothing)` and `(r::ModeClusters, index; kind=nothing)` (kind from `_ambiguity_kind(c.internal_gap, c.rho_M1)`; refuse a non-definite cluster or m = 1 with the cluster's reason in the message); three PROVISIONAL constants `_EXACT_SET_MULTIPLIER = 10.0`, `_CLUSTER_FRAME_N4_MULTIPLIER = 64.0`, `_AMBIGUITY_PSD_MULTIPLIER = 8.0`. |
| `src/analysis/eigenmodes_4d.jl` | 651 -> 677 lines | D10-D11: `_eigenmodes_4d(M; rho_M0, resolution_chord=_DEFAULT_RESOLUTION_CHORD)` calls `_mode_clusters` and takes its two oriented vectors from the clusters' `modes`; `Eigenmodes4D` gains `clusters::ModeClusters`; `SpectrumReport4D` loses `min_gap` and `stability_atol` (eigenvalues now in the clusters' canonical order); new `_frame_availability(clusters)` with the D11 order; the raw-modulus stability guard, the unit-eigenvalue distance guard, the `min_gap` guard, the 64 eps orientation floor and the `eigen` call are DELETED; `_orient_eigenvector`, the (E9) helpers, the closed-form route and check kept, their `min_trace_gap` / `stability_atol` documented as DIVISION guards of the closed form's own algebra; header and docstrings rewritten, no PROVISIONAL wording left in the file. |
| `src/Octopus.jl` | +5 lines | includes in the order symplectic_linear_algebra -> mode_clusters -> degenerate_dispersion -> eigenmodes_4d -> coupled_parameterizations, each new include with a one-line comment (the two worktrees' insertions at the same line were merged by hand). |
| `test/runtests.jl` | 19060 -> 20759 lines | stage 2 blocks (946-2193) updated by A2: every `_eigenmodes_4d` call passes `rho_M0` through `_eig4d_rho(M)`, the guard testset rewritten per D11 (1404-1511), `_EIG4D_CF_STAB` for the closed-form guard, two pins re-expressed as `c eps ||u||^2` / `c eps ||U||_F^2` (F8 below), `_pb_rho = _eig4d_rho`; @test lines 425 -> 442, nothing dropped. Stage 3 block 2194-3841 (1648 lines, 19 testsets: 12 "Mode clusters: ...", 7 "Ambiguity set: ..."; 512 @test lines, 20490 assertions) pasted right after the stage 2 Part B block, before "Non-symplectic Lorentz method classification" (3842): the `_st3_` fixture library (23 builders incl. the rolled FODO of 13.10 verbatim from the design probe, the trial-015 isospectral family, the trial-011 crab map, the defective spectator) and `_st3_cluster(M, center, radius; explicit)` selecting a cluster of `_mode_clusters` by a circle in the canonical eigenvalue list; file-level `using` unchanged, no lane gate, no git-ignored input. |

Not touched: the design note, the theory note, `docs/registry_snapshot.md`
(regenerated and byte-identical), `AGENTS.md` (its "the placeholder is still
the only registered analysis" bullet at line 75 stays true until stage 4, when
Staging item 4 rewords every placeholder-only statement), `validation/`,
`Analysis.jl`.

### Standalone verification on the folded, fixed and measured tree (no lane, no gate)

Same conventions as stages 1 and 2 (`J` = `julia --startup-file=no`, OUT =
`result/twiss_impl_2026_09_11/stage3`, `ps` checked for `runtests`/`Pkg.test`
before every package-mode run, `--project=REPO --threads=4`). Counts are the
measurement part's final chain (`OUT/measure/chain.sh`, third pass, logs
`OUT/measure/chain/`), run after the two constants were frozen and the tests
that pinned the provisional values were re-derived.

| run | command shape | result |
|---|---|---|
| suite extract: EVERY analysis testset of `test/runtests.jl` 270-3841 (stage 1 kernel + vocabularies + stage guard, stage 2 A and B, stage 3), plain arm (ForwardDiff not stacked, CUDA active) | `J OUT/measure/chain/extract/run_suite_extract.jl` | 89634 / 89634; `one_turn_matrix` block 121 / 121 (fallback arm); exit 0, 71 s |
| the same, ForwardDiff stacked (`JULIA_LOAD_PATH` with `stage1/fdenv`) | same runner | 89634 / 89634; `one_turn_matrix` 134 / 134; exit 0, 88 s |
| suite tripwires: "Architecture integrity" (incl. the docs index and `validate_configuration_metadata()`), Core.Box allowlist, "Every export is documented", "No docstring is detached" | `J OUT/measure/chain/extract/run_tripwires.jl` | 32 / 32 (28 + 2 + 1 + 1) |
| docs + snapshot probe (cwd = main tree) | `int_probe_docs_snapshot.jl`, then `git diff --quiet -- docs/registry_snapshot.md`; `validate_element_metadata()` | byte-identical (exit 0); passed, `errors = String[]`; undocumented exports `Symbol[]` |
| script-mode smoke | `include("src/Octopus.jl"); using .Octopus; summarize_registry()` + the thin methods | exit 0; `analyses = [:PlaceholderAnalysis]`; `_dispersion_ambiguity_set` 4 methods; `diag(R(0.7), R(1.41), R(0.7))` -> clusters [1,2,5,6] definite unresolved and [3,4] definite resolved, status :degenerate, set :exact_set, `dispersion_interval(set, e_x) == (-0.5, 0.5)` |
| stage 3 block, extracted from `test/runtests.jl` at run time (2194-3841, 19 testsets) | `J OUT/run_stage3_block.jl` | 20490 / 20490, 35 s (per testset: 91, 71, 37, 11406, 725, 30, 16, 70, 11, 98, 46, 34; 144, 5431, 1685, 42, 46, 419, 88) |
| A2's updated stage 2 extract (stage guard 920-945 + lines 946-3841, i.e. stage 2 + stage 3) | `OCTOPUS_TEST_TREE=REPO J OUT/run_stage2_updated.jl` | 88050 / 88050 (= 67560 stage 2 + guard, + 20490 stage 3), 53 s |
| Part B's standalone testsets | `J OUT/run_ambiguity.jl` (OUT/ambiguity_testsets.jl) | 7811 / 7811 in 7 testsets |
| Part A1's standalone testsets | `J OUT/run_clusters.jl` (OUT/clusters_testsets.jl) | 11479 / 11479 in 11 testsets |
| stage 1 kernel regression | `J result/twiss_impl_2026_09_11/stage1/run_kernel.jl` | 1618 / 1618 |

Count history: A1's testsets 11468 -> 11479 in the worktree (two kernel pins
added under injections a02/a03); B's 7811 from its second run on; A2's stage 2
extract 67555 / 5 fail -> 67558 / 2 -> 67560 / 0 (F7, F8 below); the pasted
stage 3 block 19313 / 1 (a `kappa >= 2` pin met exactly 2 - 4e-16 on the
block-diagonal fixture) -> 19314 at integration (A1 11479 + B 7811 + 24
integrator assertions) -> 20485 after the review fixes -> 20490 after the
measurement's two derived pins; the suite extract 88458 at integration ->
89629 after the fixes -> 89634 final (stages 1-2 contribute 69144, up from the
stage 2 landing's 69098 by A2's guard-testset rewrite). The integrator's first
tripwire run was 31 / 32: two new `Core.Box` sites in `mode_clusters.jl`
(`_recover_modes`, a comprehension capturing a twice-assigned `theta`;
`_agglomerate`, a comprehension capturing loop-reassigned `components`, `n`,
`best`), both rewritten as explicit loops before any count above. The
measurement's first pass after freezing the constants was 89629 / 3 fail, all
three expected: the PROVISIONAL tripwire on the two rewritten docstrings and
the crab-ladder split hard-coded at `1e-4`; its second pass had one `KeyError`
of its own (a `10 * 1e-6 != 1e-5` key), replaced by a sorted-keys pin.

### The decisions that closed the design's open points (orchestrator, 2026-09-12; amendments by the review marked)

The design fixes the criterion and the outputs but left the algorithm's order
of operations open in places. The stage 3 dossier closed them as follows; a
part that found one wrong implemented it anyway and recorded the objection,
and the fixer applied the one objection that contradicted theory Section 13.

1. **Entry point.** `_mode_clusters(M; rho_M0, resolution_chord=_DEFAULT_RESOLUTION_CHORD, partition=nothing) -> ModeClusters`, d = 4 or 6, finite, already scaled. `rho_M0` is REQUIRED (data: stage 1's `_perturbation_scale(M, _symplectic_defect(M).frobenius).scale`); `resolution_chord` in (0, 2] or `Inf`; `partition` a conjugation-closed partition of 1:d or `nothing`; with a partition the chord does not drive the merging but mode recovery still evaluates it. AMENDED (A1, then the fixer): under `Inf` the agglomeration runs at the frozen default and recovery is forced inside the identified cluster; `forced = true` marks only the clusters the default chord would have left unresolved (the exact FODO under `Inf` is forced, the coupled `R(0.9) (+) R(0.9 + 1e-7)` under partition + `Inf` is not, q = 5e-7).
2. **Spectrum.** One complex Schur decomposition, eigenvalues in canonical order (angle mod 2 pi ascending, then modulus), global backward error reported; real-class iff `|Im rho| <= tau_real = c_real sqrt(rho_M1_global) max(1, ||M||_2)` (the square root for a +-1 Jordan pair); complex-class members paired by nearest conjugate, a failed perfect matching makes the whole class one :unresolved cluster ("conjugate pairing failed"). Consequence measured by A2 (F8): the two members of a pair are computed SEPARATELY, so a modulus is known only to `eps ||u||^2 / 2` (the eigenvalue's condition number), not to `eps ||M||^2` as stage 2's real `eigen` gave; two stage 2 pins carry that kappa now.
3. **Gaps.** `g_jk = min(|rho_j - rho_k|, |rho_j - conj rho_k|)`; component gap the minimum over members; external gap of a cluster the minimum distance from its half to every other eigenvalue (scales the Gram floor). RECORDED (A1 F3, fixer 20): the conjugate distance is INERT for complex-class clustering because the component gap runs over full components (both conjugates present); `R(a) (+) R(-a)` is one cluster because the pairs share eigenvalues (gap 0). Its injection is red only through the kernel pin `_pair_gap(e^{ia}, e^{-ia}) == 0`; `_pair_gap` is also the D4 real-class metric, so the definition stays.
4. **Real-class clusters.** Components under `g_jk <= tau_real`; :unit_eigenvalue when every member is within `delta_c` of +-1, :unstable when every member's `||rho| - 1|` exceeds `delta_c`, else :unresolved ("real-class members straddle the unit circle"; fixture `diag(1, 1, 1 + 1e-7, 1/(1 + 1e-7))`, its departure now derived from `tau_real`). A real-class cluster is a flag, never a mode (stage 4's coasting test runs first).
5. **Stability on the Schur half block.** Henrici departure `dep_c`, scale `delta_c = c_stab * kappa_c * max(rho_M1(c), (rho_M1(c) dep_c^(m-1))^(1/m))`, `rho_M1(c) = max(rho_M0, ||M Q_c - Q_c T_c||_F)` measured against the INPUT matrix (fixer 3: the reconstruction `Z T Z'` hid the error); a cluster is :unstable iff every member leaves the circle by more than `delta_c`. AMENDED by the theory review and applied (fixer 1): the dossier's scale had no `kappa_c`; the crab ladder `k = k_c (1 - eps)` (both colliding pairs ON the circle for every eps > 0, proved in 256-bit arithmetic) came out :unstable at eps = 1e-7 .. 1e-9 because its singleton eigenvalues leave the circle by `eps_mach ||M|| kappa / 2` with `kappa = ||u||^2` up to 1.4e5. Theory 13.8 asks for the normalizer conditioning in the tolerances and 13.9 says a degenerate but bounded map is not unstable, so `kappa_c` = `kappa_frame` for a Gram-definite half, `kappa_eig` when every member is orientable alone, 1 for real-class or Krein-isotropic blocks (whose off-circle eigenvectors carry no Krein bound: the quartet, the hyperbolic pairs and the crab ladder's k > k_c side stay rejected). `c_stab` moved 4 (dossier) -> 256 (A1, fitted without kappa) -> 64 (fixer, window [5.2, 189]; Part D1 [5.18, 188.6]). No raw-modulus decision anywhere.
6. **Agglomeration.** Conjugate pairs as components; every candidate union evaluated by `q = min(2, 2 kappa rho_M1(u) / g)` with `kappa = kappa_frame = 1 / lambda_min |H_u|` when the union's Gram is definite above the floor, else `kappa_eig = ||[B_1 B_2]||_2^2` from each component's OWN normalized basis (A1's amendment: the literal per-pair test gives `Inf` for an exactly repeated pair and merged the indefinite fixture's 1.41 singleton into it), else `Inf`; merge the largest q first, repeat; every candidate in `resolution_receipt`; Gram floor `c_gram rho_M1(c) / g_ext(c)`.
7. **Classification and recovery.** (a) subspace residual `<= c_sub d eps`; (b) Gram eigenvalues and Krein signs above the floor: all positive DEFINITE, all negative DEFINITE after conjugating the half (`conjugated = true`), mixed with `r_mp <= mp_tol = c_mp max(rho_M1, g_int) ||P_c||_2 / ||M||_F` INDEFINITE with the signed basis, anything else :unresolved with the sub-reason in `detail` (the word defective never asserted); (c) N20 frame, N4 residuals, N5 `P_c`, `G_c`, N21 `T_c`, N19 `r_mp`; (d) Schur spectral projector by `sylvester` for every stable cluster, `P_c = 2 Re(Pi_c)`, three residuals; (e) recovery for a definite m >= 2 cluster: eigen-decompose `T_c`, internal chords `2 kappa_frame rho_M1 / |theta_j - theta_k|`, resolved iff all `<= resolution_chord`. AMENDED (A2 F7): the recovered eigenvalue read from `T_c` carries `eps ||M|| kappa_frame` (map 50 of the manufactured set: 1766 eps ||M|| against the stage 2 pin 64), so each `theta_j` is snapped to the nearest oriented Schur eigenvalue when the assignment is one-to-one; the chords still come from `T_c`. Partial splitting of a cluster of m >= 3 is not done (carried).
8. **Outputs.** As designed, with two recorded deviations: the eight-field residual tuple is split into `residuals` (5, every stable cluster) and `frame_residuals` (4, definite or indefinite clusters only), the fourth frame residual `eigenvector` (the largest (I1) residual of a column against its by-index eigenvalue) added by the fixer (4); reason mapping for fields a cluster does not derive: a definite cluster's `signed_basis` is `:not_derived_for_cluster`, `kappa_eig` of a cluster whose members are not orientable alone is `:cluster_unresolved`, and no `Determined` of a :definite cluster carries `:indefinite_cluster` or `:unresolved_defective` (pinned; fixer 5, 6).
9. **Ambiguity set.** `_dispersion_ambiguity_set(U_c; kind)` and `(P_c, G_c, m; kind)`, center `P_c[1:4, 6] / 2`, shape (N11), PSD factor `4 x (2m - 1)` by eigen-decomposition (never Cholesky), `_ambiguity_kind` :exact_set iff `g_int <= c rho_M1`; the (D12) convention `eta_a = -Im(conj(u_z) u_a)`; the midpoint is never presented as a dispersion; the docstring states the graph qualification of 13.6. Part B's recorded decisions: `kind` is a required keyword of the frame methods (the thin methods derive it), the reported shape is `F F'` (the (N11) matrix with its roundoff-null eigenvalues zeroed, reconciled by construction with the `AmbiguitySet` constructor's check), the frame checker's tolerance is `c eps m max(1, kappa)` (the dossier's `c eps m` would refuse the FODO's kappa 11.9 frame), a rank-2 shape is a filled disc (13.6), the paper's `readouts` works on `conj(U)` and flips `n_2`. The thin method ACCEPTS a resolved two-mode cluster under an explicit partition (the split isospectral endpoint wants its envelope); whether stage 4 presents such an envelope is open.
10. **Cross-check routes keep their algebraic guards.** The closed-form `min_trace_gap` and the map route's `sqrt(Delta) <= min_trace_gap` are DIVISION guards of (E11) and (T9), not resolution criteria; they stay. The stage 2 carry item (the frame refused `R(0.9) (+) R(0.9 + 1e-7)` while both trace guards accepted it) is closed: at roundoff rho_M0 the pair is RESOLVED by the chord (q = 5e-8), the physically correct answer for an exact map, and unresolved at a declared `rho_M0 = 1e-6` or at `resolution_chord = 1e-9` (pinned: "the chord and rho_M0 are READ").
11. **The 4D frame on the clusters.** `_eigenmodes_4d(M; rho_M0, resolution_chord)`; availability in order: any :unstable cluster -> `:unstable_spectrum`; any :unit_eigenvalue -> `:unit_eigenvalue`; every cluster definite and resolved with exactly two modes -> the frame; a definite unresolved cluster -> `:cluster_unresolved`; an indefinite cluster -> `:indefinite_cluster`; an unresolved cluster -> `:unresolved_defective`. Consequences pinned in the stage 2 tests: `R(0.9) (+) R(0.9)` is `:cluster_unresolved` (as before), `R(0.9) (+) R(-0.9)` is `:indefinite_cluster` (stage 2 said `:cluster_unresolved`; the design's return table row "Indefinite cluster" agrees), `diag(1 + 1e-6, 1/(1 + 1e-6), R(1.2))` is `:unstable_spectrum` at roundoff and `:unit_eigenvalue` at `rho_M0 = 1e-5`. `SpectrumReport4D.eigenvalues` changed from eigensolver order to the canonical order; `Eigenmodes4D` positional order is (spectrum, clusters, frame); no caller depended on either.

Objection recorded, not applied (A1 deviation 3, fixer 21, D1): the fixture
table's row for the block-diagonal near collision `diag(R(0.73), R(1.41),
R(-0.73 - 1e-9))` said "one cluster (q = 2 through kappa_eig), never two
definite modes", and the design's verification row 450 says the same. The
data: for this exactly separable map the individually normalized eigenvectors
are exact, `kappa_eig = 2`, `q = 2 * 2 * 1.3e-15 / 1e-9 = 5.3e-6`, and the
automatic route returns THREE resolved definite singletons at roundoff rho_M0
(one indefinite cluster at a declared `rho_M0 = 1e-12` or under an explicit
partition; both pinned). A Krein collision needs a COUPLING to make the
eigenvectors neutral; the trial-011 crab ladder supplies it and behaves as the
row says (one non-definite cluster for eps <= 1e-11 at the frozen default,
eps <= 1e-10 under the provisional 1e-4). The row should name the crab ladder;
the design and dossier wording is the orchestrator's to change.

### Parts A1 and A2: cluster and frame tolerances, every one `c eps kappa` with `c` measured

A1 measured its test tolerances on the 200 + 200 manufactured stable maps
(seed 20260911) and the fixture table (worktree stage3-A, `OUT/report_A1.md`;
the ratios are residual / (eps kappa) with kappa the frame's `||U||_2^2`):
normalization 1.99, isotropy 0.35, unitarity 1.78, `kappa_frame` vs
`kappa_eig` on singletons 23.9, `G` closes under `M` 6.3, the N5 projectors
sum to `I` at 88 (bounded at 256), the Schur spectral projector's sum and its
difference from N5 at 0.46 / 0.48 in units `eps kappa (||M||_F / g_ext)^2`
(bounded at 4 with that factor); everything else at 64. Two measured facts
behind those factors:

- A1 F1: the Schur spectral projector (D7d, a Sylvester solve) is far less
  accurate than the N5 projector when a cluster member sits near a unit
  eigenvalue: manufactured 6D map trial 1 (tune 1.55e-4, kappa 1154,
  `g_ext = 3.1e-4`) has the Sylvester and complement routes agreeing to
  2.5e-10 with each other but 3.4e-7 from N5 and from `eigen`, while N5 and
  `eigen` agree to 2e-11. Empirical conditioning over the 400 maps:
  difference `<= 0.48 eps kappa (||M||_F / g_ext)^2`. D8 says Schur, so the
  `projector` field stays Schur (unavailable only for :unstable and
  :unit_eigenvalue) and the N5 difference is reported; the recommendation to
  report N5 for definite clusters is carried to stage 4.
- A1 F2 / A2 F8 / fixer 1, one phenomenon met three times: a simple
  eigenvalue of a symplectic map with (E3)-normalized eigenvector `u` has
  condition number `||u|| ||S u|| / |u' S u| = ||u||^2 / 2 = kappa / 2`, so
  a perturbation of size `rho_M1` moves the computed eigenvalue (and its
  modulus) by `rho_M1 kappa / 2`. A1 saw it as departure/rho_M1 up to 21.3
  on a stable manufactured map and raised `c_stab` to 256; A2 saw it as the
  complex Schur moduli of map 50 at 1268 eps (`kappa = 2873`) and as the
  recovered eigenvalue read from `T_c` at 1766 eps ||M|| (F7, the snap to the
  oriented Schur value fixed it: worst frame residual over the 200 maps 9.1
  eps ||M||, worst `|rho| - 1` 9.2 eps after the fix); the theory review saw
  it as the crab ladder flagged :unstable. The D5 amendment (`kappa_c` in the
  scale) is the fix at the decision; the two stage 2 pins `|rho_j - e^{-i
  mu_j}| <= 64 eps ||u||^2` and `recon <= 64 eps ||U||_F^2` (measured ratios
  3.76 / 1.24 at c = 1, i.e. 0.06 / 0.02 at 64) are the fix at the
  assertion. A paired modulus (a real Schur form, or averaging the pair)
  would restore `eps ||M||^2` but redesigns D2 (one complex Schur
  decomposition) and was not done (fixer 8, skipped with that reason).

A2's stage 2 update kept every other assertion byte-identical (lines
946-2193 of the worktree's runtests.jl diffed against the main tree: equal;
@test lines 425 -> 442, none removed). The rewritten guard testset
(1404-1511) pins, per D11: `diag(2, 1/2, R(1.2))` :unstable_spectrum with an
:unstable cluster and `degeneracy_status === :unstable`; `R(0.9) (+) R(0.9)`
one :definite unresolved cluster, `R(0.9) (+) R(-0.9)` one :indefinite
cluster with `sort(krein_signs) == [-1, 1]`; the 1e-7 control resolved at
roundoff and unresolved at `rho_M0 = 1e-6` and at `resolution_chord = 1e-9`
with the fields reading the values passed; the hyperbolic 1e-6 pair
:unstable_spectrum at roundoff and :unit_eigenvalue at `rho_M0 = 1e-5`;
`I_4`, `+-I_2 (+) R(1.2)` :unit_eigenvalue and never :unstable; a vocabulary
loop over six fixtures asserting the frame reason is the D11 image of
`degeneracy_status`; the argument errors (3x3, 6x6, `Inf`, `rho_M0 < 0` or
NaN, chord 0 or 3, missing `rho_M0` -> `UndefKeywordError`; `rho_M0 = 0.0`
legal); `!hasfield(SpectrumReport4D, :min_gap)` and `:stability_atol`;
`!isdefined(Octopus, :analyze)`.

### Part B: ambiguity-set tolerances, `c = 64` unless stated, measured (`OUT/probes_B/measure_B.log`)

Accepted side: the largest residual / threshold over the fixtures the testset
uses, the argmax fixture printed from the data row. Rule: below one tenth.

| check (tolerance) | worst accepted ratio | at |
|---|---|---|
| (N4) refusal, `64 eps m kappa` | 0.043 | conjugated pair 11 |
| `P_c` idempotency refusal of the `(P_c, G_c)` method, `8 eps 6 max(||G||^2, ||P||^2)` | 0.070 | conjugated pair 11 |
| zero / negative shape eigenvalue vs `tol_psd = 8 eps ||G||^2` | 0.019 | family limit 1 (0.034 on the split `M_plus` at 1e-9, not a set fixture) |
| `F F' - shape` vs the `AmbiguitySet` constructor tolerance | 0 by construction (0.25 before the shape-by-construction change) | - |
| center vs `P[1:4, 6] / 2`, `16 eps kappa` | 0 | diag pair |
| N12 affine readout `eta = center + F n`, `64 eps kappa` | 0.0094 | conjugated pair 17 |
| N12 surface `(eta - c)' A^+ (eta - c) = 1`, `2048 eps kappa` (raised from 512: ratio 0.21) | 0.052 | conjugated pair 8 |
| N12 range `A A^+ dev = dev`, `256 eps kappa^2` (raised from 64: ratio 0.27) | 0.068 | conjugated pair 11 |
| N14 endpoints = eigenvalues of the Hermitian form, `64 eps kappa ||a||`; attained by its eigenvectors | 0.031 / 0.028 | family limit 3 |
| unitary mixing invariance of center / shape, `64 eps kappa` / `kappa^2` | 0.010 / 0.012 | conjugated pairs 11 / 15 |
| N13 `P_c = I`, center 0, `64 eps kappa` | 0.074 / 0.021 | conjugated triple 3 |
| N13 sampled `q <= 1 + 2048 eps kappa cond(A)` | never exceeded | - |
| (D12) vs the (D8) graph route, `64 eps kappa max(1, ||D||^2) max(1, |h|)`; `h = det U_ls` | 0.0043; 0.0049 / 0.0054 | manufactured 6x6 maps 35, 18, 17 |
| isospectral family: spectra equal, `256 eps kappa_W`; eigenvector-route eta vs expected, `256 eps kappa_W ||M|| / g`; diameter `64 eps kappa_W`; envelope containment | 0.0032; 0.0037; 0.028 / 0.036; 0 | eps = 1e-7, 1e-7 minus, 1e-3 / 1e-5 |

The two `pinv`-based checks were the only ones above one tenth at their first
constants (both go through `pinv(A; rtol = 1e-10)`, amplified by the
conditioning of A's nonzero part). Integrator additions when B's test-local
frame builder was replaced by `_mode_clusters` (`_st3_cluster`): ONE witness
that the probe builder and the cluster agree on `P_c`, `G_c`, `kappa_frame`
at 64 eps kappa (pins fixture); the cluster's N5 `P_c` against its Schur
`projector` at 64 eps kappa; `chk.kappa >= 2 - 64 eps` (the rotated frame
gives 1.9999999999999996 on the block-diagonal fixture). The paper's case-3
dump (`OUT/dump_trial015_case3.py`, `trial015_case3.tsv`: limit map, both
endpoint maps and their eta at eps in (1e-3, 1e-5, 1e-7, 1e-9), python
3.11.5 / numpy 1.23.5 / scipy 1.11.4, seed 150926, `2 sigma_1(F) =
1.2476901122751427`, the theory's "1.25") is Part D's input only; the suite
reads no git-ignored file.

### Review findings and fixes (four reviewers: theory, repository facts, runner, tests)

Twenty-eight findings (theory 5, repository 9, tests 11, runner 3), every
runtime claim reproduced on the pre-fix source before it was acted on
(`OUT/fixer/probe_verify1-3.log`); twenty-four applied within the design and
the decisions above, four skipped with reasons. Twenty-one injections re-run
after the fixes (below).

1. (theory, major) D5's stability scale was blind to the eigenvalue's
   conditioning: the crab ladder `k = k_c (1 - eps)`, a STABLE map for every
   eps > 0, came out :unstable at eps = 1e-7, 1e-8, 1e-9. Applied as the D5
   amendment (`kappa_c`), `c_stab` 256 -> 64, new testset (98 assertions).
2. (theory) The `kappa_eig` vectors were anti-oriented (`h = +Im(q' S q)/2`
   is minus the Gram): `h = -Im(...)/2`; `_evaluate_component` returns the
   oriented `eigenvector_estimate`, pinned `Im(u' S u) = -2` at 64 eps.
3. (theory) The per-cluster Schur backward error was measured against the
   reconstruction `Z T Z'` (1.10e-15 reported, 7.9e-16 true): now against
   the input matrix, `_ordered_schur_basis(F, select, M)` at all five sites.
4. (theory, minor) A split :indefinite cluster's signed basis is not an
   eigenbasis and the 13.8 reconstruction check was not reported: fourth
   frame residual `eigenvector` (`_column_eigenvector_residual`), pinned on
   the FODO (0.57 eps kappa), N15 (3.6e-16), the crab union (between
   `g_int / 10` and `10 g_int`) and every manufactured singleton.
5. (theory) `kappa_eig` of a definite degenerate cluster carried
   `:unresolved_defective`: now `:cluster_unresolved` for every
   non-orientable case.
6. (repo) A definite cluster's `signed_basis` carried `:indefinite_cluster`:
   now `:not_derived_for_cluster`; pinned that no `Determined` of a :definite
   cluster carries `:indefinite_cluster` or `:unresolved_defective`.
7. (repo) The suite pinned the PROVISIONAL default literally (`== 1.0e-4`):
   replaced by `0 < chord <= 2` and by the must-resolve / must-not-resolve
   statements (`chords[1e-9] < default`, `chords[1e-12] > 10 default`), valid
   for any default in the bracket; this is what let Part D1 move the constant
   with three expected failures instead of a rewrite.
8. (repo) Two stage 2 pins loosened by A2 to `c eps ||U||_F^2` / `c eps
   ||u||^2`: SKIPPED (the proposed fix redesigns D2; the loosened form IS
   `c eps kappa` with `kappa(lambda) = ||u||^2 / 2`, recorded in D2 above).
9. (repo) Six undocumented internals and a hand-copied docstring list in the
   suite: docstrings added; the list replaced by a derived loop over
   `names(Octopus; all=true)` filtered by the two files (35 functions seen,
   `undocumented == []`); injection fDoc.
10. (repo) The PROVISIONAL tripwire covered A1's six constants only: now a
    derived loop over `^const _NAME = ` of both files, count pinned at 9,
    plus two behavioural pins per Part B multiplier with eps-literal
    perturbations (N4: `1 + 4 eps` accepted, `1 + 1e-13` refused; PSD:
    `-4 eps` a zero, `-32 eps` an error); injections fN4, fPSD, fProv.
11. (repo) Eight residual checks with absolute literals: rewritten as
    `c eps kappa` with measured c (`P - I` 128 eps kappa at 17.6 measured,
    `G - N7` 256 at 32.4, `M G M' - G` 64 at 8.4, `T - e^{-i mu} I` 64 at
    0.33, (T7) `Delta` 64 eps ||M||^2, `dep - 0.2` 64 eps at 2.1, ...); the
    pins of published numbers (tune, Gram minimum, `k_c`, 0.28293, 2.980, the
    gaps) stay literal as the fixture table sanctions.
12. (repo) D8's residual tuple split into `residuals` and `frame_residuals`
    without a record: RECORDED (D8 above).
13. (repo) Duplicated test-local builders: `_mc_rolled_fodo`,
    `_mc_defective`, `_mc_randsymp`, `_mc_rho0` now delegate to the `_st3_`
    library; `_pb_rho = _eig4d_rho`.
14. (repo) 50 direct `.value` reads of `Determined` in the block: all
    `determined_value(...)`.
15. (tests) D5's Jordan term had no fixture that could fail: the rotated
    defective spectator (4D, 6D) and the rotated drift pin `departure >
    c_stab rho_M1` and `< scale / 10`; injection f34.
16. (tests) kappa in the chord was detected only by a margin pin: the FODO
    `eps = 2.8e-11` control (q = 1.06e-3 merged; without kappa 8.9e-5) pins
    `e.chord > default > _chord(1, rho_M1, g)`, `kappa > 10`, `kappa_source
    === :frame`, and flips under both 1e-4 and 1e-3; injection f03.
17. (tests) `mp_tol`'s `g_int` arm decided on two fixtures whose assertions
    accepted either verdict: `=== :indefinite` pinned at three sites; the
    wide-union vacuity (crab `k_c / 2` union: `mp_tol` 2.26 unreachable by
    `r_mp` 0.027) recorded for the `c_mp` window; injection f18.
18. (tests) The Gram floor and the D4 straddle branch had no fixture: the
    exact FODO under partition `[[1, 3], [2, 4]]` (two :unresolved clusters
    "at or below the floor", `gram_floor > 1`, `krein_signs == [0]`) and
    `diag(1, 1, 1 + 1e-7, 1/(1 + 1e-7))`; injections f22, f25.
19. (tests) `degeneracy_status` precedence and D11's order untested:
    `diag(2, 1/2, 1, 1)` and its block swap; injection f15.
20. (tests) The conjugate distance of D3 inert: RECORDED (D3 above).
21. (tests) The near-collision test pins the automatic route as resolved
    singletons, opposite of the fixture-table row: RECORDED for the
    orchestrator (objection above); the coupled version is pinned through
    the crab ladder.
22. (tests) "measured: see report" labels without a measurement, a hand-set
    `* 64` (c = 4096), a `rho_M0 = 0` comment without substance: labelled with
    the measured ratios (0.84, 1.22, 0.87, 0.73 eps kappa), the factor
    dropped (measured 0.15 / 0.25), `rho_M1 > 0` and `schur_backward_error >
    0` pinned at `rho_M0 = 0`; injection f40.
23. (tests) The thin method's default `kind` exercised only on an exact
    fixture: default-kind pins on every detuned control's 6D embedding as one
    explicit group (`:orientation_envelope`); injection f01. Second half
    (refuse a resolved two-mode cluster): SKIPPED, the integrator's
    documented semantics, carried to stage 4.
24. (tests) `forced` set on every m >= 2 cluster under `Inf`: now only where
    the default chord would have left it unresolved (D1 above); injection fF.
25. (tests) `kappa_eig` orientation barely detected: pinned through
    `eigenvector_estimate` (row 2; injections f35, fH). The wish for a
    fixed-atol detector: SKIPPED, the rotated spectator's departures (4e-9)
    sit below 1e-8; the D11 READ pins and the crab ladder are the detectors.
26. (runner) `report_integrator.md` misstated the extract environment
    (ForwardDiff stacked, CUDA inactive) and copied the fallback count 121:
    corrected (plain arm 121, stacked 134, CUDA active); both arrangements
    run in every chain since.
27. (runner) The default-kind branch of `_dispersion_ambiguity_set(c::
    ModeCluster)` could not fail: the pins of row 23.
28. (runner) `test/runtests.jl` line count off by one in the integrator's
    report: corrected.

Skipped, with reasons: 8, 21 (wording owned by the orchestrator), the second
half of 23, the detector wish of 25 (all above). Skipped by the integrator
and carried: A1 F1 (N5 vs Schur projector), the `_AMBIGUITY_PSD_MULTIPLIER`
lower-edge margin (1.4x on the idempotency use; Part B open issue 2).

### Part D: the chord table and the frozen default (design "Default value")

Driver `OUT/measure/measure_stage3.jl` (480 lines, package mode; Part B's
scaffold wired to `_mode_clusters`) tabulates, for every fixture of the
dossier's list, one row per cluster: `kappa_frame`, `kappa_eig`, `rho_M0` and
its winning arm (`argmax(ps.arms)`, printed from the row: "roundoff" on every
fixture), `rho_M1`, `g_int`, `g_ext`, the deciding chord `q` with its source
(the receipt chord of the merge that formed the cluster, its internal chord
matrix, or the last round's chord to every other final cluster, whichever is
largest), classification, resolved, ambiguity kind, label. Fixtures: the
exact rolled FODO of 13.10; its four detuned controls (`K_1D = -(1 + eps)`,
eps in 1e-3, 1e-6, 1e-9, 1e-12); the paper's case-3 dump (limit map + 8
endpoints); the 39 oracle maps of stage 1's TSV (24 dense, 7 prescribed_h, 4
repeated, 1 defective, 3 coasting; family and index carried); the crab ladder
`k = k_c (1 - eps)`, eps = 1e-1 .. 1e-11 (1e-10 and 1e-11 added as data: the
coupled near collision the fixer pinned); the block-diagonal near collision;
the defective spectator; 200 + 200 manufactured stable maps (seed 20260911).
466 fixtures, 1182 cluster rows (the table below omits the manufactured
maps' 996 rows; the extremes over them appear in the windows).

Labels come from the design and the theory and from nothing else: MUST
RESOLVE = FODO 1e-3, 1e-6, 1e-9 (the working notes' periodic tune error
4.45e-9 at 1e-9) and the 24 dense oracle maps (distinct tunes by
construction), 27 fixtures; MUST NOT RESOLVE = FODO 1e-12 (tune error
5.89e-6). All 27 must-resolve fixtures have every cluster resolved; the 1e-12
control is one definite unresolved m = 2 cluster.

| quantity | value | row (printed from the data) |
|---|---|---|
| largest must-resolve q | 2.960e-5 (`kappa_frame` 11.93, `rho_M1` 2.647e-15, g 2.134e-9) | "rolled FODO detuned eps = 1.0e-9" |
| next must-resolve chords | 2.960e-8, 2.974e-11, then the dense oracle maps at 9.435e-14 and below | FODO 1e-6, FODO 1e-3, "oracle dense 23 (parameter -0.939)" |
| smallest must-not-resolve q | 2.959e-2 (internal chord of the m = 2 cluster; `kappa_frame` 11.93, g 2.135e-12) | "rolled FODO detuned eps = 1.0e-12" |
| bracket | [2.960e-5, 2.959e-2]; contains the provisional 1e-4 | |
| geometric mean | `sqrt(2.960e-5 * 2.959e-2) = 9.358e-4` | |
| rounding | to one significant digit 9e-4; to a power of ten 1e-3 | |
| FROZEN default | `_DEFAULT_RESOLUTION_CHORD = 1.0e-3` (mode_clusters.jl line 80) | margins: the 1e-9 control resolves at ratio 0.030 of the default, the 1e-12 control stays merged at 29.6 |
| unlabelled fixtures inside the bracket | crab ladder eps = 1e-10 (q 2.822e-4: two definite singletons at 1e-3, one cluster at 1e-4) and eps = 1e-11 (q 2.822e-3: one unresolved cluster, `kappa_eig` 4.5e5) | the two rungs added as data; none of the dossier's own list |

The rounding rule, stated here so the next re-measurement does not re-argue
it: the design's paragraph says "rounded to one digit" and its own worked
example rounds `7.9e-5` to `1e-4`, i.e. to the nearest power of ten (the
strict one-significant-digit reading would give `8e-5` there and `9e-4` here).
The example is the rule as the design applied it, so the default is the
geometric mean rounded to the nearest power of ten: `1e-3`. The provisional
`1e-4` lay inside the bracket, but the rounded mean differs from it, and the
design says the measured value wins in that case ("If the bracket does not
contain 1e-4, the measured value wins and this paragraph records the change";
the dossier extended the rule to a different rounded mean inside the bracket).
Why the bracket sits a decade above the design's sketch: the design's chords
`2.5e-6` / `2.5e-3` assumed unit kappa; the rolled FODO's Gram in the
orthonormal Schur basis has minimum eigenvalue 0.0838 (pinned in 13.10), so
`kappa_frame = 1 / 0.0838 = 11.93` on the exact cell and on every detuned
control (`kappa_eig` of the EXACT cell is 21.7: individually normalized
eigenvectors of a degenerate pair are arbitrary).

Consequences in source and tests (all re-verified by the chain above):
`_DEFAULT_RESOLUTION_CHORD` 1e-4 -> 1e-3 with this arithmetic in its
docstring (the word PROVISIONAL is kept because the derived tripwire pins it
on all nine constants; the docstring says "PROVISIONAL in the design's sense
... FROZEN by the stage 3 measurement"); the crab-ladder testset's hard-coded
split (two singletons for eps >= 1e-9, one cluster at 1e-10 and 1e-11, which
pinned the provisional value and carried the wrong comment "(q = 2 through
kappa_eig)") is now derived: `qcoll[e]` is the colliding pair's own chord,
`ncoll[e] == (qcoll[e] > default ? 1 : 2)` for every rung, both branches must
occur, q monotone down the sorted ladder; the D4 straddle fixture's departure
is derived from `tau_real` (`ds = tau_real / 2` with `ds > c_stab rho_M0`)
instead of a literal tuned to `c_real = 4`; A1's standalone runner took the
fixer's F7 form. First pass after the constant change: 89629 pass / 3 fail,
exactly the three expected consequences (kept in
`OUT/measure/chain1_first_pass/`).

Objection recorded (also under the decisions): labelling the block-diagonal
near collision must-not-resolve, as the fixture table and the design's
verification row do, inverts the bracket to [2.960e-5, 5.329e-6]
(`OUT/measure/measurement_table_run1.md`, kept): that map is three definite
resolved singletons at q = 5.329e-6 through `kappa_eig = 2` exactly. The
final table leaves it unlabelled and prints the bracket it would impose
beside it. Whether a 2.8e-4 relative eigenvector uncertainty (the crab rung
eps = 1e-10) should count as resolved is policy, exactly the design's word
for the default.

### Derived windows (rule: largest accepted ratio below one tenth, smallest rejected above ten; arithmetic in section 2 of the table)

Ratio = the decision quantity at multiplier 1 over its threshold. For
`c_real`, `c_stab`, `c_mp`, `c_sub` and the exact-set multiplier the accepted
side must sit below the threshold: window `[10 x max accepted, min rejected /
10]`. For the Gram floor the accepted side (a definite Gram eigenvalue) must
sit ABOVE the floor: window `[10 x max rejected, min accepted / 10]`. Every
name is the argmax row's own (printed by `window_lines`). `c_stab` was first
re-measured by the fixer with `kappa_c` in the scale (`OUT/fixer/
probe_measure.log`, window [5.2, 189]); D1's independent run agrees.

| multiplier | source (before -> after) | accepted extreme (row) | rejected extreme (row) | window | inside |
|---|---|---|---|---|---|
| `c_real` `_REAL_CLASS_MULTIPLIER`, `tau_real = c sqrt(rho_M1) max(1, ||M||_2)` | 4 -> **1** | 0.0204 "rotated drift (+) R(1.2), W4 seed 20260911, eigenvalue 4" (a +1 Jordan pair split by sqrt(roundoff); 22 accepted rows) | 33.55 "R(1e-6) (+) R(1.2), eigenvalue 1" (2466 rejected rows; the FODO controls and the crab ladder at 1e6 and above) | [0.204, 3.355] | 4 was OUTSIDE (rejected margin 8.4 < 10, as A1's docstring already said); moved to 1 (margins 49 / 33.6) |
| `c_stab` `_STABILITY_MULTIPLIER`, `delta_c = c kappa_c max(rho_M1, (rho_M1 dep^(m-1))^(1/m))` | 4 -> 256 (A1) -> **64** (fixer) | 0.518 "rotated defective spectator, W4 seed 20260911, cluster [1, 2, 3, 4]" (1200 accepted rows incl. the crab ladder to 1e-11 and the 400 manufactured maps, best of those 0.479) | 1886 "crab ladder k = k_c (1 - -1.0e-7), cluster [1, 2, 5, 6]" (11 rejected rows: the hyperbolic 1e-6 pair 1.1e9, the quartet, diag(2, 1/2)) | [5.18, 188.6] | yes (8.1e-3 / 29) |
| `c_gram` `_GRAM_FLOOR_MULTIPLIER`, `floor = c rho_M1 / g_ext` | 64 | smallest accepted 7111 "crab ladder k = k_c (1 - 1.0e-10), cluster [2, 5]" (1254 definite clusters) | largest rejected 0.197 "trial-015 case 3 limit eps = 0.0, crosswise partition [[1, 5], [2, 6], [3, 4]], cluster [1, 5]" (8 rows: single copies of an exactly degenerate eigenspace under a crosswise partition derived from the eigenvalue data; Gram value arbitrary in [-1/2, 1/2], floor > 1, `krein_signs [0]`) | [1.97, 711] | yes; A1 had no rejected fixture (F4), this one is derived |
| `c_mp` `_MINIMAL_POLYNOMIAL_MULTIPLIER`, `mp_tol = c max(rho_M1, g_int) ||P||_2 / ||M||_F` | 64 | 0.545 "near collision diag(R(0.73), R(1.41), R(-0.73 - 1e-9)), partition x/z union [1, 2, 5, 6]" (53 groups: 30 conjugated pairs, 10 triples, the indefinite fixture, the FODO controls under partition, the case-3 limit) | 6.4e6 "rotated defective spectator (+) R(1.1), W6 seed 20260911, cluster [1, 2, 5, 6]" (4 defective rows; the plain spectator 1.9e14) | [5.45, 6.4e5] | yes |
| `c_sub` `_SUBSPACE_RESIDUAL_MULTIPLIER`, `sub_tol = c d eps` | 64 | 1.308 "manufactured stable 4x4 seed 20260911 index 31, cluster [2, 3]" (1263 rows) | none reachable by a fixture (an ordered Schur basis is backward stable); the injected non-invariant basis of section 3 rejects at 2.4e5 | [13.1, open) | yes |
| exact-set `_EXACT_SET_MULTIPLIER`, `:exact_set iff g_int <= c rho_M1` | 10 | 0.5875 "diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 trial 19, cluster [1, 2, 5, 6]" (33 rows: FODO 6D embedding 0.538, case-3 limit 0.421) | 537.7 "rolled FODO detuned eps = 1.0e-12 (+) R(1.1), 6D embedding, cluster [1, 2, 3, 4, 5, 6]" | [5.87, 53.8] | yes (Part B's own measurement: [5.87, 68.1]) |
| `_CLUSTER_FRAME_N4_MULTIPLIER` (Part B; refusal above `c eps m kappa`) | 64 | 0.043 x 64 = 2.7 eps m kappa, conjugated pair 11 | a column rescaled by 1 + 1e-6: 1.2e7 x; the N15 frame 1.7e13 x; a conjugate partner 7.0e12 x | [27, 7.5e7] | yes (Part B's measurement; not re-measured by D1) |
| `_AMBIGUITY_PSD_MULTIPLIER` (Part B; `tol_psd = c eps ||G||^2`, also the `G` symmetry and `P` idempotency refusals) | 8 | zero / negative eigenvalue 0.019 x 8 = 0.15 eps ||G||^2 (family limit 1); idempotency 0.070 (conjugated pair 11) | eigenvalue -1e-3 on a unit shape: 5.6e11 x | [1.5, 5.6e10] for the eigenvalue use; the idempotency use pins the lower edge at 5.6 | yes, thinnest margin of the stage (1.4x on the idempotency use) |

Kernel refusals recorded as data on `c_gram`'s rejected side: the
bit-identical repeated eigenvalues of `diag(R(0.73), R(1.41), R(0.73))`,
`diag(R(0.9), R(0.9), R(0.9))`, the defective spectator and the oracle
`repeated` maps have no spectral projector onto ONE copy;
`_schur_spectral_projector` refuses loudly (LAPACK `trsyl` info 1) and the
rows say so. The FODO and the case-3 limit map (computed, so their copies
differ at 1e-16) go through and give the rejected extremes. Unlabelled row
for `c_stab`: the crab ladder at eps = -1e-9 is :unstable (correct) by 2.2e-6
against a Jordan-term scale 7.7e-7 at 64, margin 2.9 below ten.

### The rejected side of every `c eps kappa` check family, and the paper cross-check

`OUT/measure/measure_stage3_tol.jl` (section 3 of the table): the stage 3
block holds 175 `EPS` tolerance lines in 55 check families (same quantity,
same threshold form); each family gets one row: the wrong quantity a
plausible defect produces (the a01-a07 and i01-i07 injections where one
exists: Gram `-i/2`, `Q Q'` as projector, `tau` from the tune sum, the
unnormalized Schur basis, the conjugate orientation, a conjugate partner as a
column, the same spinor at both endpoints, `Re` instead of `-Im` in (D12), `F`
without the sqrt, the midpoint instead of the endpoints, ...) on a fixture
where the defect ACTS, divided by the check's own threshold with its c and
kappa. Result: 55 / 55 above ten; the smallest 67.1 (the hyperbolic 1e-6
pair's departure against the defective spectator's `sqrt(eps)` pin), then 601
(the SPLIT 1e-12 control's receipt gap against the exact-degeneracy pin
`16 eps`); every other row 2.4e5 (the backward error against a matrix
perturbed by 1e-8) to 1.6e15.

Five first-choice defects were INERT and replaced (the lesson of 2026-09-11,
recorded in the script beside each row): (a) N6 closure `M G M' = G` holds
for `Re(Q Q')` of ANY orthonormal invariant basis with unitary restricted map
-> the covariance of the WRONG map (the 1e-3 control's G under the exact
FODO); (b) `P G = G` holds for any G with range in the cluster's real
invariant subspace -> the y singleton's covariance paired with the pair's P;
(c) N5 on the conjugated signed basis of the block-diagonal indefinite fixture
reproduces P -> the UNconjugated signed basis; (d) the (N16) polynomial with
the y tune annihilates the y block -> a tune outside the spectrum; (e) "the
betatron cluster has no pz column" is a structural zero of the block-diagonal
embedding -> the COUPLED embedding `W6 (FODO (+) R(1.1)) W6^-1`, whose
betatron cluster carries dispersion (3.4e9 times the tolerance). Three rows
report that the production guard REFUSES the wrong input (the N4 checker on a
scaled column, the set constructor on a non-unitary mixing and on `P^T`),
with the guard's residual over its tolerance as the ratio.

Paper cross-check (`OUT/measure/paper_crosscheck.py`, run once from the
driver; python 3.11.5, numpy 1.23.5, scipy 1.11.4, `mode_degeneracy.py` from
`/cfs/ad/dxu/Paper/2026_twiss_dispersion/research`; Julia 1.12.4). Only REAL
outputs are compared (pitfall 10: the prototype's circle is centred on
`e^{+i mu}`); rows and maximum absolute differences:

| row | m | Gram min (py / jl) | P | G | center | shape | eta vs dump |
|---|---|---|---|---|---|---|---|
| rolled FODO exact 4x4 | 2 | 0.083822243293302 / 0.08382224329330203 | 4.1e-14 | 7.1e-15 | (4D: no longitudinal plane) | | |
| its 6D embedding (+) R(1.1) | 2 | same | 4.1e-14 | 7.1e-15 | 0 | 0 | |
| trial-015 case 3 limit | 2 | 0.43256473072538343 / 0.4325647307253834 | 6.0e-16 | 1.3e-15 | 1.1e-16 | 3.3e-16 | |
| case 3 endpoints plus / minus, eps = 1e-3 .. 1e-9 (8 rows, the selected member isolated by eps / 2) | 1 | agree to 1e-15 | 6.8e-14 .. 2.8e-7 | <= 4.4e-16 | | | 5.8e-14 .. 6.1e-8 |

The three m >= 2 rows agree to 4.1e-14 (the dossier asked 1e-12). The eight
singleton rows carry the conditioning of a copy isolated from a pair split by
eps on BOTH routes (`kappa rho_M1 / eps` = 5.2e-12 .. 5.2e-6, the row's own q,
printed) and sit at 0.03 q; the dump's eta (exact by construction) is matched
by Julia's `P[1:4, 6]` of the selected member at that scale. Two conventions
had to be stated: `split_map` puts the selected member `v @ u` on
`rotation(MU + eps)` in BOTH endpoint maps (plus / minus name the spinor
axis), and a single mode's eta is the pz column itself (the `/2` belongs to
the m >= 2 center, N11); run 1 shows both slips before they were understood.

### Injected defects, each shown red once (script mode on a patched copy of `src/` or of the block; harnesses under OUT)

| id | part | defect | result |
|---|---|---|---|
| a01 | A1 | Gram with `-i/2` (orientation flips) | 8227 pass / 3241 fail |
| a02 | A1 | conjugate distance dropped from `_pair_gap` | 11477 / 2 (the kernel pin only; D3 above) |
| a03 | A1 | `kappa_frame` replaced by 1 in the candidate evaluation | 11474 / 5 (receipt kappa pins; the 2.8e-11 control of fixer 16 adds f03 below) |
| a04 | A1 | stability on raw moduli | 205 pass / 46 fail / 28 errors |
| a05 | A1 | Schur spectral projector taken as `Q Q'` | 10205 / 1263 |
| a06 | A1 | mode recovery without the `qr` re-orthonormalization | 11466 / 2 (the coupled 1e-7 pair under partition + Inf) |
| a07 | A1 | mp residual with the wrong `tau` (tune sum) | 11413 / 50 / 5 errors |
| a201 | A2 | frame built when a cluster is unresolved (guard removed) | 67552 / 8 |
| a202 | A2 | reason mapping swapped (`:indefinite_cluster` reported as `:cluster_unresolved`) | 67558 / 2 |
| i01 | B | center from the z column `P[1:4, 5]` | 4564 / 3247 |
| i02 | B | shape without the 1/4 | 5802 / 2009 |
| i03 | B | factor by Cholesky of the rank-deficient shape | 116 pass / 6 errors (`PosDefException` aborts six testsets) |
| i04 | B | (D12) with `Re` instead of `-Im` | 4253 / 3558 |
| i05 | B | isospectral family with the SAME spinor at both endpoints (fixture file) | 7799 / 12, all in the family testset |
| i06 | B | (N4) check with `-2i` | 111 pass / 6 errors |
| i07 | B | `_ambiguity_kind` branches swapped | 7797 / 14 |
| f01 | fixer | thin method's default kind := `:exact_set` | 20473 / 8 |
| f03 | fixer | kappa dropped from `_chord` | 20480 / 5 |
| f34 | fixer | D5 Jordan term dropped | 20475 / 6 |
| f05 | fixer | `kappa_c` dropped from D5 (the pre-amendment scale) | 20455 / 21 / 5 errors (the crab ladder goes :unstable) |
| f22 | fixer | Gram floor := 0 | 20478 / 3 |
| f25 | fixer | "any member leaves the circle" stability rule | 20479 / 2 |
| f15 | fixer | `degeneracy_status` rank swap | 20479 / 2 |
| f18 | fixer | `mp_tol` without the `g_int` arm | 20472 / 3 / 1 |
| f35, fH | fixer | `kappa_eig` columns not oriented; the Gram sign of `h` reverted | 20480 / 1 each |
| f40 | fixer | Schur backward error dropped from `rho_M1` | 20480 / 1 |
| fF | fixer | `forced = true` under Inf regardless | 20480 / 1 |
| fR1, fR2 | fixer | the old reasons restored on `kappa_eig` / `signed_basis` | 20477 / 4; 20479 / 2 |
| fDoc, fProv | fixer | an undocumented function added; PROVISIONAL removed from one docstring | 20480 / 1 each |
| fN4, fPSD | fixer | `_CLUSTER_FRAME_N4_MULTIPLIER` 64 -> 4096; `_AMBIGUITY_PSD_MULTIPLIER` 8 -> 64 | 20480 / 1 each |
| fEig | fixer | `_column_eigenvector_residual := 0` | 19480 / 1001 |
| fBE, fBE2 | fixer | backward error against `Z T Z'` | fBE GREEN at first (rho_M0 dominates every maximum, as the review predicted) -> kernel pin on a 1e-6-perturbed matrix added -> fBE2 20484 / 1 |

Part B's first injection sweep had six of seven patches silently REFUSED
("0 matches"): `inject_B.sh` copied `src/` with `cp -r` into an existing
`inj_B/<id>/src`, nesting `src/src` and leaving the already patched copy as
the target, while the report claimed "every injection re-run on the final
source". B's second pass found it from the log, fixed the harness (`rm -rf`
before the copy) and re-ran all seven; the counts above are from that run.
The a01-a07, a201, a202 and i01-i07 harnesses were re-run on the main tree's
pasted block by the runner reviewer (every one red,
`OUT/review_runner/inject_summary.txt`); the f-series ran on the fixed tree.
None was re-run after the measurement's constant change or after the ledger
edits (the constant change touched two docstrings, two tests and one
scratch runner; the extract and the block re-ran green).

### Not verified in stage 3

- No lane and no gate ran on this tree; every count above is standalone. One
  full gate on the assembled stage 3 tree is owed before the push and is
  recorded in this file when it runs. After the ledger edits of Part D2
  (this section, the todo row, the README sentence, the experiences lesson)
  the four suite tripwires were re-run in package mode: 32 / 32 (Architecture integrity 28 incl. the docs index and the snapshot, Core.Box 2, exports 1, detached docstrings 1; plain arm, exit 0; `OUT/ledgers/run_tripwires_after_ledgers.log`).
- `validation/tracking_backend_consistency.jl` and `validation/lattice_cells.jl`
  were not run (no kernel, element or tracking code changed; host matrix
  algebra only, nothing CUDA-reachable).
- The injections were not re-run after the measurement's constant change or
  the ledger edits (above).
- The rounding rule of the default rests on the design's worked example
  (power of ten), not on a sentence that says so; recorded above as the rule
  applied. If the owner reads "one digit" strictly, the default is `9e-4`
  and the bracket margins (0.033 / 32.9) are essentially the same.
- The fixture-table and design row for the block-diagonal near collision
  contradict the data (three definite singletons); the wording is the
  orchestrator's and the design note was not edited. The coupled near
  collision that does not resolve at 1e-3 is the crab ladder eps <= 1e-11
  (eps = 1e-10 resolves at q = 2.8e-4, one decade below the default; it
  merged under 1e-4).
- `c_sub` has no fixture-reachable rejected side (window one-sided [13.1,
  open)); only the injected non-invariant basis rejects (2.4e5).
- `c_gram`'s rejected side exists only for COMPUTED degeneracies (the FODO,
  the case-3 limit); bit-identical repeated eigenvalues are refused by
  `_schur_spectral_projector` before the floor is reached (recorded rows). A
  rejected fixture with a coupled, computed degenerate eigenspace at larger
  `g_ext` is a lead.
- Part B's `_CLUSTER_FRAME_N4_MULTIPLIER` and `_AMBIGUITY_PSD_MULTIPLIER`
  were measured by Part B only (windows above); D1's section 3 exercises the
  N4 guard's rejected side (1.2e7) but did not re-derive the windows.
- Section 3 covers each of the 55 check FAMILIES once (175 `EPS` lines), not
  every line; the mapping is the `runtests lines` column of the table.
- Paper cross-check: the m >= 2 rows agree to 4.1e-14; the eight
  isolated-singleton endpoint rows agree only to their own conditioning q
  (5e-12 .. 5e-6), not to 1e-12, by the nature of the comparison.
- The `(cd $P && run ...)` snapshot step of the fixer's and D1's `chain.sh`
  wrote to a relative path inside the subshell and silently did not run;
  the docs + snapshot probe was run by hand from the main tree in both
  chains and again for this record. Fix the script before reusing it.
- The Schur spectral projector's accuracy near a unit eigenvalue (A1 F1) is
  bounded by a measured empirical factor `eps kappa (||M||_F / g_ext)^2`, not
  by a derived one.
- Stage 2's remark that the closed-form and map-route guards were not
  exercised on a coincident trace with unequal eigenvalue classes still
  stands (none exists in 4D).

### Carried forward to stage 4 (this record edits neither note)

1. Partial splitting of a definite cluster of m >= 3 whose restricted map
   resolves some but not all modes: not done (D7e); every unresolved chord
   leaves the whole cluster's `modes` unavailable with `:cluster_unresolved`.
2. The `projector` field of a definite cluster is the Schur spectral
   projector (D8); A1 F1 measured N5's `P_c` to be far more accurate near a
   unit eigenvalue (3.4e-7 vs 2e-11 on manufactured 6D trial 1). Stage 4
   decides which one `TwissDispersionAnalysis` presents; `projector_n5_difference`
   is reported on every definite cluster for that decision.
3. The thin method `_dispersion_ambiguity_set(c::ModeCluster)` accepts a
   RESOLVED two-mode cluster under an explicit partition (the split
   isospectral endpoint wants its envelope); stage 4's presentation rules
   decide whether such an envelope is shown beside the resolved modes.
4. Result-shape items carried from stage 2, still open: labels at a tie
   (`label_margin = 0`, no `Determined`); the `Inf` gamma identities at a
   zero beta and the normalizer route's `consistency_residual` at the floor;
   a `Determined` area weight; whether form 2 is presented as form 1 with
   exchanged labels ((T4) reading); one status for coincident traces across
   routes (frame `:cluster_unresolved`, closed form and map route
   `:singular_coefficient`).
5. `AGENTS.md` line 75 ("the placeholder is still the only registered
   analysis") and every placeholder-only statement: reworded by Staging item
   4 when `analyze` lands.
6. The fixture-table and design verification-row wording for the
   near-collision fixture (name the crab ladder; the block-diagonal map is
   three resolved singletons), the orchestrator's.
7. The eigenvalue condition number `||u||^2 / 2` (D2 above): the frame's
   moduli are known to `eps kappa(lambda)`; a paired modulus (real Schur
   form, or averaging the pair) would restore `eps ||M||^2` and let the two
   stage 2 pins return to `64 eps`, at the price of redesigning D2. Stage 4
   should decide whether `TwissDispersionAnalysis` reports `|rho| - 1` at
   all (the design rejects raw-modulus decisions; a reported diagnostic is a
   different question).
8. The `_AMBIGUITY_PSD_MULTIPLIER` lower-edge margin (1.4x on the
   idempotency use of the `(P_c, G_c)` method): split the idempotency
   multiplier off if stage 4 exercises that method on worse-conditioned
   frames.
9. A `c_gram` rejected fixture with a coupled computed degeneracy at larger
   `g_ext`; a `c_sub` rejected fixture (none reachable: backward-stable
   Schur).
10. The `c_mp` window was measured on narrow splits; for wide explicit unions
    (`g_int` of order 0.1) `mp_tol` is unreachable by `r_mp` (crab `k_c / 2`
    union: 2.26 vs 0.027), so an explicit partition of far-apart pairs is
    always :indefinite when the Gram is mixed. Stage 4's option schema should
    say what a user-supplied partition promises.
11. Stage 4 runs the coasting test (design D23) BEFORE `_mode_clusters`; the
    real-class code path of D4 is a flag, and the 3 coasting oracle maps
    (chord table rows, `:unit_eigenvalue` clusters) are its fixtures.
12. The measurement scripts of stages 1-3 live inline in this record until
    stage 6 moves them under `validation/`; D1's `chain.sh` snapshot step
    needs the `cd` fix before reuse.
13. Ledger dates: stages 1-2 landed 2026-09-11 and stage 3 on 2026-09-12; the
    todo row and the README carry both dates (the dossier's draft wording
    said "stages 1-3 landed 2026-09-11").

### Measurement tables (output of `measure_stage3.jl` sections 1, 1a, 2, 4 and `measure_stage3_tol.jl` section 3, verbatim except that the 996 rows of the 200 + 200 manufactured maps are omitted from section 1; the full file is `OUT/measure/measurement_table.md`, 1400 lines)

#### Stage 3 measurement table (Part D1), header

Produced by measure_stage3.jl (sections 1, 2, 4; package mode, main tree, FINAL constants: chord 1e-3, c_real 1) and measure_stage3_tol.jl (section 3); this file is their concatenation (run3 + section3), assembled as described in report_D1.md.

Julia 1.12.4; threads 4; seed 20260911; oracle TSV /cfs/ad/dxu/Library/Julia/Octopus/result/twiss_impl_2026_09_11/stage1/measure/oracle_maps.tsv; case-3 TSV /cfs/ad/dxu/Library/Julia/Octopus/result/twiss_impl_2026_09_11/stage3/trial015_case3.tsv.
Source constants at run time: _DEFAULT_RESOLUTION_CHORD = 0.001, c_real = 1.0, c_stab = 64.0, c_gram = 64.0, c_mp = 64.0, c_sub = 64.0, exact-set = 10.0.
q = min(2, 2 kappa rho_M1 / g) as `_mode_clusters` evaluated it (q_source names which chord decided the row: merge, internal, between); rho_M1 = max(rho_M0, Schur backward error of the half). Every name in this file is printed from its data row.

#### 1. Chord table

| name | cluster | m | kappa_frame | kappa_eig | rho_M0 | rho_arm | rho_M1 | g_int | g_ext | q | q_source | classification | resolved | kind | label |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| rolled FODO exact (theta = pi/4) | 1.000e+00 | 2.000e+00 | 1.193e+01 | nothing | 2.647e-15 | roundoff | 2.647e-15 | 2.136e-15 | 4.496e-01 | 2.000e+00 | merge | definite | false | none | unlabelled |
| rolled FODO detuned eps = 0.001 | 1.000e+00 | 1.000e+00 | 1.198e+01 | 1.198e+01 | 2.647e-15 | roundoff | 2.647e-15 | Inf | 2.133e-03 | 2.974e-11 | between | definite | true | none | must_resolve |
| rolled FODO detuned eps = 0.001 | 2.000e+00 | 1.000e+00 | 9.745e+00 | 9.745e+00 | 2.647e-15 | roundoff | 2.647e-15 | Inf | 2.133e-03 | 2.974e-11 | between | definite | true | none | must_resolve |
| rolled FODO detuned eps = 1.0e-6 | 1.000e+00 | 1.000e+00 | 1.193e+01 | 1.193e+01 | 2.647e-15 | roundoff | 2.647e-15 | Inf | 2.134e-06 | 2.960e-08 | between | definite | true | none | must_resolve |
| rolled FODO detuned eps = 1.0e-6 | 2.000e+00 | 1.000e+00 | 9.795e+00 | 9.795e+00 | 2.647e-15 | roundoff | 2.647e-15 | Inf | 2.134e-06 | 2.960e-08 | between | definite | true | none | must_resolve |
| rolled FODO detuned eps = 1.0e-9 | 1.000e+00 | 1.000e+00 | 1.193e+01 | 1.193e+01 | 2.647e-15 | roundoff | 2.647e-15 | Inf | 2.134e-09 | 2.960e-05 | between | definite | true | none | must_resolve |
| rolled FODO detuned eps = 1.0e-9 | 2.000e+00 | 1.000e+00 | 9.795e+00 | 9.795e+00 | 2.647e-15 | roundoff | 2.647e-15 | Inf | 2.134e-09 | 2.960e-05 | between | definite | true | none | must_resolve |
| rolled FODO detuned eps = 1.0e-12 | 1.000e+00 | 2.000e+00 | 1.193e+01 | 1.193e+01 | 2.647e-15 | roundoff | 2.647e-15 | 2.135e-12 | 4.496e-01 | 2.959e-02 | internal | definite | false | none | must_not_resolve |
| trial-015 case 3 limit eps = 0.0 | 1.000e+00 | 2.000e+00 | 2.312e+00 | nothing | 2.237e-15 | roundoff | 2.237e-15 | 9.421e-16 | 6.670e-01 | 2.000e+00 | merge | definite | false | exact_set | unlabelled |
| trial-015 case 3 limit eps = 0.0 | 2.000e+00 | 1.000e+00 | 2.200e+00 | 2.200e+00 | 2.237e-15 | roundoff | 2.237e-15 | Inf | 6.670e-01 | 1.608e-14 | between | definite | true | none | unlabelled |
| trial-015 case 3 minus eps = 0.001 | 1.000e+00 | 1.000e+00 | 2.139e+00 | 2.139e+00 | 2.237e-15 | roundoff | 2.237e-15 | Inf | 2.000e-03 | 5.172e-12 | between | definite | true | none | unlabelled |
| trial-015 case 3 minus eps = 0.001 | 2.000e+00 | 1.000e+00 | 2.303e+00 | 2.303e+00 | 2.237e-15 | roundoff | 2.237e-15 | Inf | 2.000e-03 | 5.172e-12 | between | definite | true | none | unlabelled |
| trial-015 case 3 minus eps = 0.001 | 3.000e+00 | 1.000e+00 | 2.200e+00 | 2.200e+00 | 2.237e-15 | roundoff | 2.237e-15 | Inf | 6.660e-01 | 1.608e-14 | between | definite | true | none | unlabelled |
| trial-015 case 3 plus eps = 0.001 | 1.000e+00 | 1.000e+00 | 2.303e+00 | 2.303e+00 | 2.237e-15 | roundoff | 2.237e-15 | Inf | 2.000e-03 | 5.171e-12 | between | definite | true | none | unlabelled |
| trial-015 case 3 plus eps = 0.001 | 2.000e+00 | 1.000e+00 | 2.139e+00 | 2.139e+00 | 2.237e-15 | roundoff | 2.237e-15 | Inf | 2.000e-03 | 5.171e-12 | between | definite | true | none | unlabelled |
| trial-015 case 3 plus eps = 0.001 | 3.000e+00 | 1.000e+00 | 2.200e+00 | 2.200e+00 | 2.237e-15 | roundoff | 2.237e-15 | Inf | 6.660e-01 | 1.603e-14 | between | definite | true | none | unlabelled |
| trial-015 case 3 minus eps = 1.0e-5 | 1.000e+00 | 1.000e+00 | 2.139e+00 | 2.139e+00 | 2.237e-15 | roundoff | 2.237e-15 | Inf | 2.000e-05 | 5.172e-10 | between | definite | true | none | unlabelled |
| trial-015 case 3 minus eps = 1.0e-5 | 2.000e+00 | 1.000e+00 | 2.303e+00 | 2.303e+00 | 2.237e-15 | roundoff | 2.237e-15 | Inf | 2.000e-05 | 5.172e-10 | between | definite | true | none | unlabelled |
| trial-015 case 3 minus eps = 1.0e-5 | 3.000e+00 | 1.000e+00 | 2.200e+00 | 2.200e+00 | 2.237e-15 | roundoff | 2.237e-15 | Inf | 6.670e-01 | 1.605e-14 | between | definite | true | none | unlabelled |
| trial-015 case 3 plus eps = 1.0e-5 | 1.000e+00 | 1.000e+00 | 2.303e+00 | 2.303e+00 | 2.237e-15 | roundoff | 2.237e-15 | Inf | 2.000e-05 | 5.172e-10 | between | definite | true | none | unlabelled |
| trial-015 case 3 plus eps = 1.0e-5 | 2.000e+00 | 1.000e+00 | 2.139e+00 | 2.139e+00 | 2.237e-15 | roundoff | 2.237e-15 | Inf | 2.000e-05 | 5.172e-10 | between | definite | true | none | unlabelled |
| trial-015 case 3 plus eps = 1.0e-5 | 3.000e+00 | 1.000e+00 | 2.200e+00 | 2.200e+00 | 2.237e-15 | roundoff | 2.237e-15 | Inf | 6.670e-01 | 1.605e-14 | between | definite | true | none | unlabelled |
| trial-015 case 3 minus eps = 1.0e-7 | 1.000e+00 | 1.000e+00 | 2.139e+00 | 2.139e+00 | 2.237e-15 | roundoff | 2.237e-15 | Inf | 2.000e-07 | 5.172e-08 | between | definite | true | none | unlabelled |
| trial-015 case 3 minus eps = 1.0e-7 | 2.000e+00 | 1.000e+00 | 2.303e+00 | 2.303e+00 | 2.237e-15 | roundoff | 2.237e-15 | Inf | 2.000e-07 | 5.172e-08 | between | definite | true | none | unlabelled |
| trial-015 case 3 minus eps = 1.0e-7 | 3.000e+00 | 1.000e+00 | 2.200e+00 | 2.200e+00 | 2.237e-15 | roundoff | 2.237e-15 | Inf | 6.670e-01 | 1.689e-14 | between | definite | true | none | unlabelled |
| trial-015 case 3 plus eps = 1.0e-7 | 1.000e+00 | 1.000e+00 | 2.303e+00 | 2.303e+00 | 2.237e-15 | roundoff | 2.237e-15 | Inf | 2.000e-07 | 5.172e-08 | between | definite | true | none | unlabelled |
| trial-015 case 3 plus eps = 1.0e-7 | 2.000e+00 | 1.000e+00 | 2.139e+00 | 2.139e+00 | 2.237e-15 | roundoff | 2.237e-15 | Inf | 2.000e-07 | 5.172e-08 | between | definite | true | none | unlabelled |
| trial-015 case 3 plus eps = 1.0e-7 | 3.000e+00 | 1.000e+00 | 2.200e+00 | 2.200e+00 | 2.237e-15 | roundoff | 2.237e-15 | Inf | 6.670e-01 | 1.605e-14 | between | definite | true | none | unlabelled |
| trial-015 case 3 minus eps = 1.0e-9 | 1.000e+00 | 1.000e+00 | 2.139e+00 | 2.139e+00 | 2.237e-15 | roundoff | 2.237e-15 | Inf | 2.000e-09 | 5.172e-06 | between | definite | true | none | unlabelled |
| trial-015 case 3 minus eps = 1.0e-9 | 2.000e+00 | 1.000e+00 | 2.303e+00 | 2.303e+00 | 2.237e-15 | roundoff | 2.237e-15 | Inf | 2.000e-09 | 5.172e-06 | between | definite | true | none | unlabelled |
| trial-015 case 3 minus eps = 1.0e-9 | 3.000e+00 | 1.000e+00 | 2.200e+00 | 2.200e+00 | 2.237e-15 | roundoff | 2.237e-15 | Inf | 6.670e-01 | 1.605e-14 | between | definite | true | none | unlabelled |
| trial-015 case 3 plus eps = 1.0e-9 | 1.000e+00 | 1.000e+00 | 2.303e+00 | 2.303e+00 | 2.237e-15 | roundoff | 2.237e-15 | Inf | 2.000e-09 | 5.172e-06 | between | definite | true | none | unlabelled |
| trial-015 case 3 plus eps = 1.0e-9 | 2.000e+00 | 1.000e+00 | 2.139e+00 | 2.139e+00 | 2.237e-15 | roundoff | 2.237e-15 | Inf | 2.000e-09 | 5.172e-06 | between | definite | true | none | unlabelled |
| trial-015 case 3 plus eps = 1.0e-9 | 3.000e+00 | 1.000e+00 | 2.200e+00 | 2.200e+00 | 2.237e-15 | roundoff | 2.237e-15 | Inf | 6.670e-01 | 1.605e-14 | between | definite | true | none | unlabelled |
| oracle dense 0 (parameter -0.87) | 1.000e+00 | 1.000e+00 | 2.124e+00 | 2.124e+00 | 2.495e-15 | roundoff | 2.495e-15 | Inf | 3.973e-01 | 3.454e-14 | between | definite | true | none | must_resolve |
| oracle dense 0 (parameter -0.87) | 2.000e+00 | 1.000e+00 | 2.691e+00 | 2.691e+00 | 2.495e-15 | roundoff | 2.495e-15 | Inf | 3.973e-01 | 3.454e-14 | between | definite | true | none | must_resolve |
| oracle dense 0 (parameter -0.87) | 3.000e+00 | 1.000e+00 | 2.184e+00 | 2.184e+00 | 2.495e-15 | roundoff | 2.495e-15 | Inf | 7.139e-01 | 1.895e-14 | between | definite | true | none | must_resolve |
| oracle dense 1 (parameter -0.873) | 1.000e+00 | 1.000e+00 | 2.317e+00 | 2.317e+00 | 2.702e-15 | roundoff | 2.702e-15 | Inf | 3.915e-01 | 3.556e-14 | between | definite | true | none | must_resolve |
| oracle dense 1 (parameter -0.873) | 2.000e+00 | 1.000e+00 | 2.326e+00 | 2.326e+00 | 2.702e-15 | roundoff | 2.702e-15 | Inf | 3.915e-01 | 3.556e-14 | between | definite | true | none | must_resolve |
| oracle dense 1 (parameter -0.873) | 3.000e+00 | 1.000e+00 | 2.491e+00 | 2.491e+00 | 2.702e-15 | roundoff | 2.702e-15 | Inf | 7.186e-01 | 1.903e-14 | between | definite | true | none | must_resolve |
| oracle dense 2 (parameter -0.876) | 1.000e+00 | 1.000e+00 | 2.722e+00 | 2.722e+00 | 2.608e-15 | roundoff | 2.608e-15 | Inf | 3.856e-01 | 4.357e-14 | between | definite | true | none | must_resolve |
| oracle dense 2 (parameter -0.876) | 2.000e+00 | 1.000e+00 | 2.653e+00 | 2.653e+00 | 2.608e-15 | roundoff | 2.608e-15 | Inf | 3.856e-01 | 4.357e-14 | between | definite | true | none | must_resolve |
| oracle dense 2 (parameter -0.876) | 3.000e+00 | 1.000e+00 | 2.389e+00 | 2.389e+00 | 2.608e-15 | roundoff | 2.608e-15 | Inf | 7.232e-01 | 2.046e-14 | between | definite | true | none | must_resolve |
| oracle dense 3 (parameter -0.879) | 1.000e+00 | 1.000e+00 | 2.634e+00 | 2.634e+00 | 3.026e-15 | roundoff | 3.026e-15 | Inf | 3.797e-01 | 5.156e-14 | between | definite | true | none | must_resolve |
| oracle dense 3 (parameter -0.879) | 2.000e+00 | 1.000e+00 | 3.146e+00 | 3.146e+00 | 3.026e-15 | roundoff | 3.026e-15 | Inf | 3.797e-01 | 5.156e-14 | between | definite | true | none | must_resolve |
| oracle dense 3 (parameter -0.879) | 3.000e+00 | 1.000e+00 | 2.252e+00 | 2.252e+00 | 3.026e-15 | roundoff | 3.026e-15 | Inf | 7.279e-01 | 2.654e-14 | between | definite | true | none | must_resolve |
| oracle dense 4 (parameter -0.882) | 1.000e+00 | 1.000e+00 | 2.902e+00 | 2.902e+00 | 2.962e-15 | roundoff | 2.962e-15 | Inf | 3.738e-01 | 4.615e-14 | between | definite | true | none | must_resolve |
| oracle dense 4 (parameter -0.882) | 2.000e+00 | 1.000e+00 | 2.035e+00 | 2.035e+00 | 2.962e-15 | roundoff | 2.962e-15 | Inf | 3.738e-01 | 4.615e-14 | between | definite | true | none | must_resolve |
| oracle dense 4 (parameter -0.882) | 3.000e+00 | 1.000e+00 | 2.612e+00 | 2.612e+00 | 2.962e-15 | roundoff | 2.962e-15 | Inf | 7.325e-01 | 2.118e-14 | between | definite | true | none | must_resolve |
| oracle dense 5 (parameter -0.885) | 1.000e+00 | 1.000e+00 | 3.423e+00 | 3.423e+00 | 2.784e-15 | roundoff | 2.784e-15 | Inf | 3.679e-01 | 5.395e-14 | between | definite | true | none | must_resolve |
| oracle dense 5 (parameter -0.885) | 2.000e+00 | 1.000e+00 | 2.335e+00 | 2.335e+00 | 2.784e-15 | roundoff | 2.784e-15 | Inf | 3.679e-01 | 5.395e-14 | between | definite | true | none | must_resolve |
| oracle dense 5 (parameter -0.885) | 3.000e+00 | 1.000e+00 | 2.297e+00 | 2.297e+00 | 2.784e-15 | roundoff | 2.784e-15 | Inf | 7.372e-01 | 1.878e-14 | between | definite | true | none | must_resolve |
| oracle dense 6 (parameter -0.888) | 1.000e+00 | 1.000e+00 | 2.276e+00 | 2.276e+00 | 2.351e-15 | roundoff | 2.351e-15 | Inf | 3.620e-01 | 3.186e-14 | between | definite | true | none | must_resolve |
| oracle dense 6 (parameter -0.888) | 2.000e+00 | 1.000e+00 | 2.312e+00 | 2.312e+00 | 2.351e-15 | roundoff | 2.351e-15 | Inf | 3.620e-01 | 3.186e-14 | between | definite | true | none | must_resolve |
| oracle dense 6 (parameter -0.888) | 3.000e+00 | 1.000e+00 | 2.332e+00 | 2.332e+00 | 2.351e-15 | roundoff | 2.351e-15 | Inf | 7.418e-01 | 1.544e-14 | between | definite | true | none | must_resolve |
| oracle dense 7 (parameter -0.891) | 1.000e+00 | 1.000e+00 | 2.391e+00 | 2.391e+00 | 4.449e-15 | roundoff | 4.449e-15 | Inf | 3.561e-01 | 6.808e-14 | between | definite | true | none | must_resolve |
| oracle dense 7 (parameter -0.891) | 2.000e+00 | 1.000e+00 | 2.720e+00 | 2.720e+00 | 4.449e-15 | roundoff | 4.449e-15 | Inf | 3.561e-01 | 6.808e-14 | between | definite | true | none | must_resolve |
| oracle dense 7 (parameter -0.891) | 3.000e+00 | 1.000e+00 | 3.833e+00 | 3.833e+00 | 4.449e-15 | roundoff | 4.449e-15 | Inf | 7.465e-01 | 4.997e-14 | between | definite | true | none | must_resolve |
| oracle dense 8 (parameter -0.894) | 1.000e+00 | 1.000e+00 | 2.535e+00 | 2.535e+00 | 2.531e-15 | roundoff | 2.531e-15 | Inf | 3.502e-01 | 4.345e-14 | between | definite | true | none | must_resolve |
| oracle dense 8 (parameter -0.894) | 2.000e+00 | 1.000e+00 | 2.630e+00 | 2.630e+00 | 2.531e-15 | roundoff | 2.531e-15 | Inf | 3.502e-01 | 4.345e-14 | between | definite | true | none | must_resolve |
| oracle dense 8 (parameter -0.894) | 3.000e+00 | 1.000e+00 | 2.427e+00 | 2.427e+00 | 2.531e-15 | roundoff | 2.531e-15 | Inf | 7.511e-01 | 1.848e-14 | between | definite | true | none | must_resolve |
| oracle dense 9 (parameter -0.897) | 1.000e+00 | 1.000e+00 | 2.443e+00 | 2.443e+00 | 3.097e-15 | roundoff | 3.097e-15 | Inf | 3.443e-01 | 6.116e-14 | between | definite | true | none | must_resolve |
| oracle dense 9 (parameter -0.897) | 2.000e+00 | 1.000e+00 | 3.242e+00 | 3.242e+00 | 3.097e-15 | roundoff | 3.097e-15 | Inf | 3.443e-01 | 6.116e-14 | between | definite | true | none | must_resolve |
| oracle dense 9 (parameter -0.897) | 3.000e+00 | 1.000e+00 | 2.421e+00 | 2.421e+00 | 3.097e-15 | roundoff | 3.097e-15 | Inf | 7.557e-01 | 2.771e-14 | between | definite | true | none | must_resolve |
| oracle dense 10 (parameter -0.9) | 1.000e+00 | 1.000e+00 | 2.265e+00 | 2.265e+00 | 2.224e-15 | roundoff | 2.224e-15 | Inf | 3.384e-01 | 3.177e-14 | between | definite | true | none | must_resolve |
| oracle dense 10 (parameter -0.9) | 2.000e+00 | 1.000e+00 | 2.304e+00 | 2.304e+00 | 2.224e-15 | roundoff | 2.224e-15 | Inf | 3.384e-01 | 3.177e-14 | between | definite | true | none | must_resolve |
| oracle dense 10 (parameter -0.9) | 3.000e+00 | 1.000e+00 | 2.204e+00 | 2.204e+00 | 2.224e-15 | roundoff | 2.224e-15 | Inf | 7.604e-01 | 1.356e-14 | between | definite | true | none | must_resolve |
| oracle dense 11 (parameter -0.903) | 1.000e+00 | 1.000e+00 | 2.144e+00 | 2.144e+00 | 2.954e-15 | roundoff | 2.954e-15 | Inf | 3.324e-01 | 5.042e-14 | between | definite | true | none | must_resolve |
| oracle dense 11 (parameter -0.903) | 2.000e+00 | 1.000e+00 | 2.770e+00 | 2.770e+00 | 2.954e-15 | roundoff | 2.954e-15 | Inf | 3.324e-01 | 5.042e-14 | between | definite | true | none | must_resolve |
| oracle dense 11 (parameter -0.903) | 3.000e+00 | 1.000e+00 | 2.759e+00 | 2.759e+00 | 2.954e-15 | roundoff | 2.954e-15 | Inf | 7.650e-01 | 2.365e-14 | between | definite | true | none | must_resolve |
| oracle dense 12 (parameter -0.906) | 1.000e+00 | 1.000e+00 | 2.064e+00 | 2.064e+00 | 2.458e-15 | roundoff | 2.458e-15 | Inf | 3.265e-01 | 3.956e-14 | between | definite | true | none | must_resolve |
| oracle dense 12 (parameter -0.906) | 2.000e+00 | 1.000e+00 | 2.602e+00 | 2.602e+00 | 2.458e-15 | roundoff | 2.458e-15 | Inf | 3.265e-01 | 3.956e-14 | between | definite | true | none | must_resolve |
| oracle dense 12 (parameter -0.906) | 3.000e+00 | 1.000e+00 | 2.370e+00 | 2.370e+00 | 2.458e-15 | roundoff | 2.458e-15 | Inf | 7.696e-01 | 1.669e-14 | between | definite | true | none | must_resolve |
| oracle dense 13 (parameter -0.909) | 1.000e+00 | 1.000e+00 | 2.354e+00 | 2.354e+00 | 2.833e-15 | roundoff | 2.833e-15 | Inf | 3.206e-01 | 4.297e-14 | between | definite | true | none | must_resolve |
| oracle dense 13 (parameter -0.909) | 2.000e+00 | 1.000e+00 | 2.318e+00 | 2.318e+00 | 2.833e-15 | roundoff | 2.833e-15 | Inf | 3.206e-01 | 4.297e-14 | between | definite | true | none | must_resolve |
| oracle dense 13 (parameter -0.909) | 3.000e+00 | 1.000e+00 | 2.564e+00 | 2.564e+00 | 2.833e-15 | roundoff | 2.833e-15 | Inf | 7.742e-01 | 1.895e-14 | between | definite | true | none | must_resolve |
| oracle dense 14 (parameter -0.912) | 1.000e+00 | 1.000e+00 | 2.285e+00 | 2.285e+00 | 3.283e-15 | roundoff | 3.283e-15 | Inf | 3.147e-01 | 7.588e-14 | between | definite | true | none | must_resolve |
| oracle dense 14 (parameter -0.912) | 2.000e+00 | 1.000e+00 | 3.445e+00 | 3.445e+00 | 3.283e-15 | roundoff | 3.283e-15 | Inf | 3.147e-01 | 7.588e-14 | between | definite | true | none | must_resolve |
| oracle dense 14 (parameter -0.912) | 3.000e+00 | 1.000e+00 | 2.411e+00 | 2.411e+00 | 3.283e-15 | roundoff | 3.283e-15 | Inf | 7.788e-01 | 3.018e-14 | between | definite | true | none | must_resolve |
| oracle dense 15 (parameter -0.915) | 1.000e+00 | 1.000e+00 | 2.924e+00 | 2.924e+00 | 3.059e-15 | roundoff | 3.059e-15 | Inf | 3.088e-01 | 6.233e-14 | between | definite | true | none | must_resolve |
| oracle dense 15 (parameter -0.915) | 2.000e+00 | 1.000e+00 | 2.332e+00 | 2.332e+00 | 3.059e-15 | roundoff | 3.059e-15 | Inf | 3.088e-01 | 6.233e-14 | between | definite | true | none | must_resolve |
| oracle dense 15 (parameter -0.915) | 3.000e+00 | 1.000e+00 | 2.420e+00 | 2.420e+00 | 3.059e-15 | roundoff | 3.059e-15 | Inf | 7.834e-01 | 2.098e-14 | between | definite | true | none | must_resolve |
| oracle dense 16 (parameter -0.918) | 1.000e+00 | 1.000e+00 | 2.260e+00 | 2.260e+00 | 2.521e-15 | roundoff | 2.521e-15 | Inf | 3.028e-01 | 3.869e-14 | between | definite | true | none | must_resolve |
| oracle dense 16 (parameter -0.918) | 2.000e+00 | 1.000e+00 | 2.269e+00 | 2.269e+00 | 2.521e-15 | roundoff | 2.521e-15 | Inf | 3.028e-01 | 3.869e-14 | between | definite | true | none | must_resolve |
| oracle dense 16 (parameter -0.918) | 3.000e+00 | 1.000e+00 | 2.528e+00 | 2.528e+00 | 2.521e-15 | roundoff | 2.521e-15 | Inf | 7.880e-01 | 1.709e-14 | between | definite | true | none | must_resolve |
| oracle dense 17 (parameter -0.921) | 1.000e+00 | 1.000e+00 | 3.178e+00 | 3.178e+00 | 2.747e-15 | roundoff | 2.747e-15 | Inf | 2.969e-01 | 6.024e-14 | between | definite | true | none | must_resolve |
| oracle dense 17 (parameter -0.921) | 2.000e+00 | 1.000e+00 | 2.251e+00 | 2.251e+00 | 2.747e-15 | roundoff | 2.747e-15 | Inf | 2.969e-01 | 6.024e-14 | between | definite | true | none | must_resolve |
| oracle dense 17 (parameter -0.921) | 3.000e+00 | 1.000e+00 | 2.319e+00 | 2.319e+00 | 2.747e-15 | roundoff | 2.747e-15 | Inf | 7.926e-01 | 1.702e-14 | between | definite | true | none | must_resolve |
| oracle dense 18 (parameter -0.924) | 1.000e+00 | 1.000e+00 | 2.173e+00 | 2.173e+00 | 3.208e-15 | roundoff | 3.208e-15 | Inf | 2.910e-01 | 7.185e-14 | between | definite | true | none | must_resolve |
| oracle dense 18 (parameter -0.924) | 2.000e+00 | 1.000e+00 | 3.235e+00 | 3.235e+00 | 3.208e-15 | roundoff | 3.208e-15 | Inf | 2.910e-01 | 7.185e-14 | between | definite | true | none | must_resolve |
| oracle dense 18 (parameter -0.924) | 3.000e+00 | 1.000e+00 | 2.280e+00 | 2.280e+00 | 3.208e-15 | roundoff | 3.208e-15 | Inf | 7.972e-01 | 2.609e-14 | between | definite | true | none | must_resolve |
| oracle dense 19 (parameter -0.927) | 1.000e+00 | 1.000e+00 | 2.561e+00 | 2.561e+00 | 2.534e-15 | roundoff | 2.534e-15 | Inf | 2.850e-01 | 4.660e-14 | between | definite | true | none | must_resolve |
| oracle dense 19 (parameter -0.927) | 2.000e+00 | 1.000e+00 | 2.321e+00 | 2.321e+00 | 2.534e-15 | roundoff | 2.534e-15 | Inf | 2.850e-01 | 4.660e-14 | between | definite | true | none | must_resolve |
| oracle dense 19 (parameter -0.927) | 3.000e+00 | 1.000e+00 | 2.403e+00 | 2.403e+00 | 2.534e-15 | roundoff | 2.534e-15 | Inf | 8.018e-01 | 1.567e-14 | between | definite | true | none | must_resolve |
| oracle dense 20 (parameter -0.9299999999999999) | 1.000e+00 | 1.000e+00 | 2.595e+00 | 2.595e+00 | 2.768e-15 | roundoff | 2.768e-15 | Inf | 2.791e-01 | 5.191e-14 | between | definite | true | none | must_resolve |
| oracle dense 20 (parameter -0.9299999999999999) | 2.000e+00 | 1.000e+00 | 2.205e+00 | 2.205e+00 | 2.768e-15 | roundoff | 2.768e-15 | Inf | 2.791e-01 | 5.191e-14 | between | definite | true | none | must_resolve |
| oracle dense 20 (parameter -0.9299999999999999) | 3.000e+00 | 1.000e+00 | 2.517e+00 | 2.517e+00 | 2.768e-15 | roundoff | 2.768e-15 | Inf | 8.064e-01 | 1.756e-14 | between | definite | true | none | must_resolve |
| oracle dense 21 (parameter -0.933) | 1.000e+00 | 1.000e+00 | 2.299e+00 | 2.299e+00 | 2.740e-15 | roundoff | 2.740e-15 | Inf | 2.731e-01 | 4.666e-14 | between | definite | true | none | must_resolve |
| oracle dense 21 (parameter -0.933) | 2.000e+00 | 1.000e+00 | 2.052e+00 | 2.052e+00 | 2.740e-15 | roundoff | 2.740e-15 | Inf | 2.731e-01 | 4.666e-14 | between | definite | true | none | must_resolve |
| oracle dense 21 (parameter -0.933) | 3.000e+00 | 1.000e+00 | 2.437e+00 | 2.437e+00 | 2.740e-15 | roundoff | 2.740e-15 | Inf | 8.110e-01 | 1.661e-14 | between | definite | true | none | must_resolve |
| oracle dense 22 (parameter -0.9359999999999999) | 1.000e+00 | 1.000e+00 | 2.551e+00 | 2.551e+00 | 2.392e-15 | roundoff | 2.392e-15 | Inf | 2.672e-01 | 6.245e-14 | between | definite | true | none | must_resolve |
| oracle dense 22 (parameter -0.9359999999999999) | 2.000e+00 | 1.000e+00 | 2.986e+00 | 2.986e+00 | 2.392e-15 | roundoff | 2.392e-15 | Inf | 2.672e-01 | 6.245e-14 | between | definite | true | none | must_resolve |
| oracle dense 22 (parameter -0.9359999999999999) | 3.000e+00 | 1.000e+00 | 2.122e+00 | 2.122e+00 | 2.392e-15 | roundoff | 2.392e-15 | Inf | 8.155e-01 | 1.795e-14 | between | definite | true | none | must_resolve |
| oracle dense 23 (parameter -0.9390000000000001) | 1.000e+00 | 1.000e+00 | 3.586e+00 | 3.586e+00 | 3.212e-15 | roundoff | 3.212e-15 | Inf | 2.613e-01 | 9.435e-14 | between | definite | true | none | must_resolve |
| oracle dense 23 (parameter -0.9390000000000001) | 2.000e+00 | 1.000e+00 | 2.307e+00 | 2.307e+00 | 3.212e-15 | roundoff | 3.212e-15 | Inf | 2.613e-01 | 9.435e-14 | between | definite | true | none | must_resolve |
| oracle dense 23 (parameter -0.9390000000000001) | 3.000e+00 | 1.000e+00 | 2.660e+00 | 2.660e+00 | 3.212e-15 | roundoff | 3.212e-15 | Inf | 8.201e-01 | 2.232e-14 | between | definite | true | none | must_resolve |
| oracle prescribed_h 0 (parameter -2.0) | 1.000e+00 | 1.000e+00 | 1.549e+01 | 1.549e+01 | 1.286e-14 | roundoff | 1.286e-14 | Inf | 3.088e-01 | 1.473e-12 | between | definite | true | none | unlabelled |
| oracle prescribed_h 0 (parameter -2.0) | 2.000e+00 | 1.000e+00 | 1.505e+01 | 1.505e+01 | 1.286e-14 | roundoff | 1.286e-14 | Inf | 3.088e-01 | 1.473e-12 | between | definite | true | none | unlabelled |
| oracle prescribed_h 0 (parameter -2.0) | 3.000e+00 | 1.000e+00 | 2.010e+00 | 2.010e+00 | 1.286e-14 | roundoff | 1.286e-14 | Inf | 7.788e-01 | 4.971e-13 | between | definite | true | none | unlabelled |
| oracle prescribed_h 1 (parameter -1.0) | 1.000e+00 | 1.000e+00 | 7.240e+00 | 7.240e+00 | 4.453e-15 | roundoff | 4.453e-15 | Inf | 3.088e-01 | 2.410e-13 | between | definite | true | none | unlabelled |
| oracle prescribed_h 1 (parameter -1.0) | 2.000e+00 | 1.000e+00 | 7.050e+00 | 7.050e+00 | 4.453e-15 | roundoff | 4.453e-15 | Inf | 3.088e-01 | 2.410e-13 | between | definite | true | none | unlabelled |
| oracle prescribed_h 1 (parameter -1.0) | 3.000e+00 | 1.000e+00 | 2.010e+00 | 2.010e+00 | 4.453e-15 | roundoff | 4.453e-15 | Inf | 7.788e-01 | 8.072e-14 | between | definite | true | none | unlabelled |
| oracle prescribed_h 2 (parameter -0.3) | 1.000e+00 | 1.000e+00 | 3.904e+00 | 3.904e+00 | 1.916e-15 | roundoff | 1.916e-15 | Inf | 3.088e-01 | 5.548e-14 | between | definite | true | none | unlabelled |
| oracle prescribed_h 2 (parameter -0.3) | 2.000e+00 | 1.000e+00 | 3.830e+00 | 3.830e+00 | 1.916e-15 | roundoff | 1.916e-15 | Inf | 3.088e-01 | 5.548e-14 | between | definite | true | none | unlabelled |
| oracle prescribed_h 2 (parameter -0.3) | 3.000e+00 | 1.000e+00 | 2.010e+00 | 2.010e+00 | 1.916e-15 | roundoff | 1.916e-15 | Inf | 7.788e-01 | 1.889e-14 | between | definite | true | none | unlabelled |
| oracle prescribed_h 3 (parameter 0.05) | 1.000e+00 | 1.000e+00 | 2.990e+00 | 2.990e+00 | 2.277e-15 | roundoff | 2.277e-15 | Inf | 3.088e-01 | 4.935e-14 | between | definite | true | none | unlabelled |
| oracle prescribed_h 3 (parameter 0.05) | 2.000e+00 | 1.000e+00 | 2.955e+00 | 2.955e+00 | 2.277e-15 | roundoff | 2.277e-15 | Inf | 3.088e-01 | 4.935e-14 | between | definite | true | none | unlabelled |
| oracle prescribed_h 3 (parameter 0.05) | 3.000e+00 | 1.000e+00 | 2.010e+00 | 2.010e+00 | 2.277e-15 | roundoff | 2.277e-15 | Inf | 7.788e-01 | 1.733e-14 | between | definite | true | none | unlabelled |
| oracle prescribed_h 4 (parameter 0.5) | 1.000e+00 | 1.000e+00 | 2.552e+00 | 2.552e+00 | 2.412e-15 | roundoff | 2.412e-15 | Inf | 3.088e-01 | 4.224e-14 | between | definite | true | none | unlabelled |
| oracle prescribed_h 4 (parameter 0.5) | 2.000e+00 | 1.000e+00 | 2.550e+00 | 2.550e+00 | 2.412e-15 | roundoff | 2.412e-15 | Inf | 3.088e-01 | 4.224e-14 | between | definite | true | none | unlabelled |
| oracle prescribed_h 4 (parameter 0.5) | 3.000e+00 | 1.000e+00 | 2.010e+00 | 2.010e+00 | 2.412e-15 | roundoff | 2.412e-15 | Inf | 7.788e-01 | 1.582e-14 | between | definite | true | none | unlabelled |
| oracle prescribed_h 5 (parameter 1.0) | 1.000e+00 | 1.000e+00 | 3.040e+00 | 3.040e+00 | 2.219e-15 | roundoff | 2.219e-15 | Inf | 3.088e-01 | 4.385e-14 | between | definite | true | none | unlabelled |
| oracle prescribed_h 5 (parameter 1.0) | 2.000e+00 | 1.000e+00 | 3.050e+00 | 3.050e+00 | 2.219e-15 | roundoff | 2.219e-15 | Inf | 3.088e-01 | 4.385e-14 | between | definite | true | none | unlabelled |
| oracle prescribed_h 5 (parameter 1.0) | 3.000e+00 | 1.000e+00 | 2.010e+00 | 2.010e+00 | 2.219e-15 | roundoff | 2.219e-15 | Inf | 7.788e-01 | 1.738e-14 | between | definite | true | none | unlabelled |
| oracle prescribed_h 6 (parameter 2.0) | 1.000e+00 | 1.000e+00 | 7.090e+00 | 7.090e+00 | 4.509e-15 | roundoff | 4.509e-15 | Inf | 3.088e-01 | 2.081e-13 | between | definite | true | none | unlabelled |
| oracle prescribed_h 6 (parameter 2.0) | 2.000e+00 | 1.000e+00 | 7.050e+00 | 7.050e+00 | 4.509e-15 | roundoff | 4.509e-15 | Inf | 3.088e-01 | 2.081e-13 | between | definite | true | none | unlabelled |
| oracle prescribed_h 6 (parameter 2.0) | 3.000e+00 | 1.000e+00 | 2.010e+00 | 2.010e+00 | 4.509e-15 | roundoff | 4.509e-15 | Inf | 7.788e-01 | 8.165e-14 | between | definite | true | none | unlabelled |
| oracle repeated 0 (parameter -1.3) | 1.000e+00 | 2.000e+00 | 2.775e+00 | nothing | 2.407e-15 | roundoff | 2.407e-15 | 2.220e-16 | 5.719e-01 | 2.000e+00 | merge | definite | false | exact_set | unlabelled |
| oracle repeated 0 (parameter -1.3) | 2.000e+00 | 1.000e+00 | 2.341e+00 | 2.341e+00 | 2.407e-15 | roundoff | 2.407e-15 | Inf | 5.719e-01 | 2.371e-14 | between | definite | true | none | unlabelled |
| oracle repeated 1 (parameter -1.3) | 1.000e+00 | 2.000e+00 | 2.557e+00 | nothing | 2.015e-15 | roundoff | 2.015e-15 | 2.483e-16 | 5.719e-01 | 2.000e+00 | merge | definite | false | exact_set | unlabelled |
| oracle repeated 1 (parameter -1.3) | 2.000e+00 | 1.000e+00 | 2.289e+00 | 2.289e+00 | 2.015e-15 | roundoff | 2.015e-15 | Inf | 5.719e-01 | 1.908e-14 | between | definite | true | none | unlabelled |
| oracle repeated 2 (parameter -1.3) | 1.000e+00 | 2.000e+00 | 2.502e+00 | nothing | 2.195e-15 | roundoff | 2.195e-15 | 8.951e-16 | 5.719e-01 | 2.000e+00 | merge | definite | false | exact_set | unlabelled |
| oracle repeated 2 (parameter -1.3) | 2.000e+00 | 1.000e+00 | 2.384e+00 | 2.384e+00 | 2.195e-15 | roundoff | 2.195e-15 | Inf | 5.719e-01 | 2.040e-14 | between | definite | true | none | unlabelled |
| oracle repeated 3 (parameter -1.3) | 1.000e+00 | 2.000e+00 | 2.434e+00 | nothing | 2.055e-15 | roundoff | 2.055e-15 | 1.570e-16 | 5.719e-01 | 2.000e+00 | merge | definite | false | exact_set | unlabelled |
| oracle repeated 3 (parameter -1.3) | 2.000e+00 | 1.000e+00 | 2.073e+00 | 2.073e+00 | 2.055e-15 | roundoff | 2.055e-15 | Inf | 5.719e-01 | 1.765e-14 | between | definite | true | none | unlabelled |
| oracle defective 0 (parameter -1.3) | 1.000e+00 | 2.000e+00 | nothing | nothing | 2.246e-15 | roundoff | 2.246e-15 | 1.553e-08 | 5.719e-01 | 2.000e+00 | merge | unresolved | false | none | unlabelled |
| oracle defective 0 (parameter -1.3) | 2.000e+00 | 1.000e+00 | 2.401e+00 | 2.401e+00 | 2.246e-15 | roundoff | 2.246e-15 | Inf | 5.719e-01 | 2.308e-14 | between | definite | true | none | unlabelled |
| oracle coasting 0 (parameter -0.4) | 1.000e+00 | 0.000e+00 | nothing | nothing | 1.718e-15 | roundoff | 1.718e-15 | 0.000e+00 | 5.623e-01 | 0.000e+00 | merge | unit_eigenvalue | false | none | unlabelled |
| oracle coasting 0 (parameter -0.4) | 2.000e+00 | 1.000e+00 | 2.009e+00 | 2.009e+00 | 1.718e-15 | roundoff | 1.718e-15 | Inf | 5.623e-01 | 8.476e-15 | between | definite | true | none | unlabelled |
| oracle coasting 0 (parameter -0.4) | 3.000e+00 | 1.000e+00 | 2.048e+00 | 2.048e+00 | 1.718e-15 | roundoff | 1.718e-15 | Inf | 8.337e-01 | 8.476e-15 | between | definite | true | none | unlabelled |
| oracle coasting 1 (parameter 0.0) | 1.000e+00 | 0.000e+00 | nothing | nothing | 1.533e-15 | roundoff | 1.533e-15 | 0.000e+00 | 5.623e-01 | 0.000e+00 | merge | unit_eigenvalue | false | none | unlabelled |
| oracle coasting 1 (parameter 0.0) | 2.000e+00 | 1.000e+00 | 2.050e+00 | 2.050e+00 | 1.533e-15 | roundoff | 1.533e-15 | Inf | 5.623e-01 | 7.639e-15 | between | definite | true | none | unlabelled |
| oracle coasting 1 (parameter 0.0) | 3.000e+00 | 1.000e+00 | 2.028e+00 | 2.028e+00 | 1.533e-15 | roundoff | 1.533e-15 | Inf | 8.337e-01 | 7.639e-15 | between | definite | true | none | unlabelled |
| oracle coasting 2 (parameter 0.7) | 1.000e+00 | 0.000e+00 | nothing | nothing | 2.096e-15 | roundoff | 2.096e-15 | 0.000e+00 | 5.623e-01 | 0.000e+00 | merge | unit_eigenvalue | false | none | unlabelled |
| oracle coasting 2 (parameter 0.7) | 2.000e+00 | 1.000e+00 | 2.051e+00 | 2.051e+00 | 2.096e-15 | roundoff | 2.096e-15 | Inf | 5.623e-01 | 1.066e-14 | between | definite | true | none | unlabelled |
| oracle coasting 2 (parameter 0.7) | 3.000e+00 | 1.000e+00 | 2.068e+00 | 2.068e+00 | 2.096e-15 | roundoff | 2.096e-15 | Inf | 8.337e-01 | 1.066e-14 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 0.1) | 1.000e+00 | 1.000e+00 | 4.597e+00 | 4.597e+00 | 1.394e-15 | roundoff | 1.394e-15 | Inf | 4.353e-02 | 3.727e-13 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 0.1) | 2.000e+00 | 1.000e+00 | 4.597e+00 | 4.597e+00 | 1.394e-15 | roundoff | 1.394e-15 | Inf | 4.353e-02 | 3.727e-13 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 0.1) | 3.000e+00 | 1.000e+00 | 2.000e+00 | 2.000e+00 | 1.394e-15 | roundoff | 1.394e-15 | Inf | 1.192e+00 | 1.118e-14 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 0.01) | 1.000e+00 | 1.000e+00 | 1.421e+01 | 1.421e+01 | 1.400e-15 | roundoff | 1.400e-15 | Inf | 1.408e-02 | 2.834e-12 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 0.01) | 2.000e+00 | 1.000e+00 | 1.421e+01 | 1.421e+01 | 1.400e-15 | roundoff | 1.400e-15 | Inf | 1.408e-02 | 2.834e-12 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 0.01) | 3.000e+00 | 1.000e+00 | 2.000e+00 | 2.000e+00 | 1.400e-15 | roundoff | 1.400e-15 | Inf | 1.204e+00 | 3.306e-14 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 0.001) | 1.000e+00 | 1.000e+00 | 4.484e+01 | 4.484e+01 | 1.401e-15 | roundoff | 1.401e-15 | Inf | 4.464e-03 | 2.823e-11 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 0.001) | 2.000e+00 | 1.000e+00 | 4.484e+01 | 4.484e+01 | 1.401e-15 | roundoff | 1.401e-15 | Inf | 4.464e-03 | 2.823e-11 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 0.001) | 3.000e+00 | 1.000e+00 | 2.000e+00 | 2.000e+00 | 1.401e-15 | roundoff | 1.401e-15 | Inf | 1.208e+00 | 1.040e-13 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 0.0001) | 1.000e+00 | 1.000e+00 | 1.418e+02 | 1.418e+02 | 1.401e-15 | roundoff | 1.401e-15 | Inf | 1.412e-03 | 3.091e-10 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 0.0001) | 2.000e+00 | 1.000e+00 | 1.418e+02 | 1.418e+02 | 1.401e-15 | roundoff | 1.401e-15 | Inf | 1.412e-03 | 3.091e-10 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 0.0001) | 3.000e+00 | 1.000e+00 | 2.000e+00 | 2.000e+00 | 1.401e-15 | roundoff | 1.401e-15 | Inf | 1.209e+00 | 3.285e-13 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 1.0e-5) | 1.000e+00 | 1.000e+00 | 4.483e+02 | 4.483e+02 | 1.401e-15 | roundoff | 1.401e-15 | Inf | 4.465e-04 | 2.822e-09 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 1.0e-5) | 2.000e+00 | 1.000e+00 | 4.483e+02 | 4.483e+02 | 1.401e-15 | roundoff | 1.401e-15 | Inf | 4.465e-04 | 2.822e-09 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 1.0e-5) | 3.000e+00 | 1.000e+00 | 2.000e+00 | 2.000e+00 | 1.401e-15 | roundoff | 1.401e-15 | Inf | 1.209e+00 | 1.039e-12 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 1.0e-6) | 1.000e+00 | 1.000e+00 | 1.418e+03 | 1.418e+03 | 1.401e-15 | roundoff | 1.401e-15 | Inf | 1.412e-04 | 2.822e-08 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 1.0e-6) | 2.000e+00 | 1.000e+00 | 1.418e+03 | 1.418e+03 | 1.401e-15 | roundoff | 1.401e-15 | Inf | 1.412e-04 | 2.822e-08 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 1.0e-6) | 3.000e+00 | 1.000e+00 | 2.000e+00 | 2.000e+00 | 1.401e-15 | roundoff | 1.401e-15 | Inf | 1.209e+00 | 3.284e-12 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 1.0e-7) | 1.000e+00 | 1.000e+00 | 4.483e+03 | 4.483e+03 | 1.401e-15 | roundoff | 1.401e-15 | Inf | 4.465e-05 | 3.175e-07 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 1.0e-7) | 2.000e+00 | 1.000e+00 | 4.483e+03 | 4.483e+03 | 1.401e-15 | roundoff | 1.401e-15 | Inf | 4.465e-05 | 3.175e-07 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 1.0e-7) | 3.000e+00 | 1.000e+00 | 2.000e+00 | 2.000e+00 | 1.401e-15 | roundoff | 1.401e-15 | Inf | 1.209e+00 | 1.075e-11 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 1.0e-8) | 1.000e+00 | 1.000e+00 | 1.418e+04 | 1.418e+04 | 1.401e-15 | roundoff | 1.401e-15 | Inf | 1.412e-05 | 2.822e-06 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 1.0e-8) | 2.000e+00 | 1.000e+00 | 1.418e+04 | 1.418e+04 | 1.401e-15 | roundoff | 1.401e-15 | Inf | 1.412e-05 | 2.822e-06 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 1.0e-8) | 3.000e+00 | 1.000e+00 | 2.000e+00 | 2.000e+00 | 1.401e-15 | roundoff | 1.401e-15 | Inf | 1.209e+00 | 3.284e-11 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 1.0e-9) | 1.000e+00 | 1.000e+00 | 4.483e+04 | 4.483e+04 | 1.401e-15 | roundoff | 1.401e-15 | Inf | 4.465e-06 | 2.822e-05 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 1.0e-9) | 2.000e+00 | 1.000e+00 | 4.483e+04 | 4.483e+04 | 1.401e-15 | roundoff | 1.401e-15 | Inf | 4.465e-06 | 2.822e-05 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 1.0e-9) | 3.000e+00 | 1.000e+00 | 2.000e+00 | 2.000e+00 | 1.401e-15 | roundoff | 1.401e-15 | Inf | 1.209e+00 | 1.038e-10 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 1.0e-10) | 1.000e+00 | 1.000e+00 | 1.418e+05 | 1.418e+05 | 1.401e-15 | roundoff | 1.401e-15 | Inf | 1.412e-06 | 2.822e-04 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 1.0e-10) | 2.000e+00 | 1.000e+00 | 1.418e+05 | 1.418e+05 | 1.401e-15 | roundoff | 1.401e-15 | Inf | 1.412e-06 | 2.822e-04 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 1.0e-10) | 3.000e+00 | 1.000e+00 | 2.000e+00 | 2.000e+00 | 1.401e-15 | roundoff | 1.401e-15 | Inf | 1.209e+00 | 3.284e-10 | between | definite | true | none | unlabelled |
| crab ladder k = k_c (1 - 1.0e-11) | 1.000e+00 | 2.000e+00 | nothing | 4.498e+05 | 1.401e-15 | roundoff | 1.401e-15 | 4.466e-07 | 1.209e+00 | 2.822e-03 | merge | unresolved | false | none | unlabelled |
| crab ladder k = k_c (1 - 1.0e-11) | 2.000e+00 | 1.000e+00 | 2.000e+00 | 2.000e+00 | 1.401e-15 | roundoff | 1.401e-15 | Inf | 1.209e+00 | 4.664e-15 | between | definite | true | none | unlabelled |
| near collision diag(R(0.73), R(1.41), R(-0.73 - 1e-9)) | 1.000e+00 | 1.000e+00 | 2.000e+00 | 2.000e+00 | 1.332e-15 | roundoff | 1.332e-15 | Inf | 1.000e-09 | 5.329e-06 | between | definite | true | none | unlabelled |
| near collision diag(R(0.73), R(1.41), R(-0.73 - 1e-9)) | 2.000e+00 | 1.000e+00 | 2.000e+00 | 2.000e+00 | 1.332e-15 | roundoff | 1.332e-15 | Inf | 1.000e-09 | 5.329e-06 | between | definite | true | none | unlabelled |
| near collision diag(R(0.73), R(1.41), R(-0.73 - 1e-9)) | 3.000e+00 | 1.000e+00 | 2.000e+00 | 2.000e+00 | 1.332e-15 | roundoff | 1.332e-15 | Inf | 6.670e-01 | 7.990e-15 | between | definite | true | none | unlabelled |
| defective spectator (mu = 0.72) | 1.000e+00 | 2.000e+00 | nothing | nothing | 9.814e-16 | roundoff | 9.814e-16 | 0.000e+00 | 1.319e+00 | 2.000e+00 | merge | unresolved | false | none | unlabelled |


#### 1a. Bracket (design "Default value")

- must-resolve fixtures: 27; all their clusters resolved: true
- must-not-resolve fixture "rolled FODO detuned eps = 1.0e-12": clusters m = 2 definite resolved = false
- (objection record) "near collision diag(R(0.73), R(1.41), R(-0.73 - 1e-9))": clusters m = 1 definite resolved = true, m = 1 definite resolved = true, m = 1 definite resolved = true; q = 5.329e-06; labelled must-not-resolve it would give the bracket [2.960e-05, 5.329e-06]
- largest q of a must-resolve fixture: 2.960e-05 at "rolled FODO detuned eps = 1.0e-9"
- smallest q of a must-not-resolve fixture: 2.959e-02 at "rolled FODO detuned eps = 1.0e-12"
- bracket [2.960e-05, 2.959e-02]; geometric mean sqrt(2.960e-05 * 2.959e-02) = 9.358e-04; rounded to one significant digit 0.0009; rounded to a power of ten (the design's own example 7.9e-5 -> 1e-4) 0.001
- source constant 0.001 equals the power-of-ten rounding: true; margins at the source constant: must-resolve extreme ratio 2.960e-02, must-not-resolve extreme ratio 2.959e+01
- provisional 1e-4 inside the bracket: true; rounded mean equals the source constant 0.001: false
- unlabelled fixtures with q inside the bracket (2): "crab ladder k = k_c (1 - 1.0e-10)" (2.822e-04); "crab ladder k = k_c (1 - 1.0e-11)" (2.822e-03)
- must-resolve chords, descending: "rolled FODO detuned eps = 1.0e-9" 2.960e-05; "rolled FODO detuned eps = 1.0e-6" 2.960e-08; "rolled FODO detuned eps = 0.001" 2.974e-11; "oracle dense 23 (parameter -0.9390000000000001)" 9.435e-14; "oracle dense 14 (parameter -0.912)" 7.588e-14; "oracle dense 18 (parameter -0.924)" 7.185e-14
- must-not-resolve chords, ascending: "rolled FODO detuned eps = 1.0e-12" 2.959e-02

Rows: 1182; fixtures: 466.

#### 2. PROVISIONAL multiplier windows (one tenth / ten rule)

Fixture sets: the chord table's 466 fixtures plus the fixtures each docstring names (built in `extra_fixtures`, `measure_gram_mp_sub_exact`); every name printed from its row. Crosswise partitions are derived from the eigenvalue data (see `crosswise_partition`).

##### c_real (_REAL_CLASS_MULTIPLIER)

- ratio at multiplier 1: |Im rho_j| / (sqrt(rho_M1) max(1, ||M||_2)); accepted = real-class eigenvalues, rejected = complex-class eigenvalues
- source value: 1.0
- largest accepted ratio: 2.039e-02 at "rotated drift (+) R(1.2), W4 seed 20260911, eigenvalue 4"
- smallest rejected ratio: 3.355e+01 at "R(1e-6) (+) R(1.2), eigenvalue 1"
- window [2.039e-01, 3.355e+00]; source value inside: true
  - accepted "rotated drift (+) R(1.2), W4 seed 20260911, eigenvalue 4" 2.039e-02
  - accepted "rotated drift (+) R(1.2), W4 seed 20260911, eigenvalue 1" 2.039e-02
  - accepted "I_2 (+) R(1.2), eigenvalue 2" 0.000e+00
  - accepted "-I_2 (+) R(1.2), eigenvalue 3" 0.000e+00
  - rejected "R(1e-6) (+) R(1.2), eigenvalue 1" 3.355e+01
  - rejected "R(1e-6) (+) R(1.2), eigenvalue 4" 3.355e+01
  - rejected "manufactured stable 6x6 seed 20260911 index 9, eigenvalue 6" 5.906e+02
  - rejected "manufactured stable 6x6 seed 20260911 index 9, eigenvalue 1" 5.906e+02

##### c_stab (_STABILITY_MULTIPLIER)

- ratio at multiplier 1: departure / (kappa_c max(rho_M1, (rho_M1 dep^(m-1))^(1/m))); accepted = max departure of every cluster of a stable fixture, rejected = min departure of the off-circle clusters
- source value: 64.0
- largest accepted ratio: 5.179e-01 at "rotated defective spectator, W4 seed 20260911, cluster [1, 2, 3, 4]"
- smallest rejected ratio: 1.886e+03 at "crab ladder k = k_c (1 - -1.0e-7), cluster [1, 2, 5, 6]"
- window [5.179e+00, 1.886e+02]; source value inside: true
  - accepted "rotated defective spectator, W4 seed 20260911, cluster [1, 2, 3, 4]" 5.179e-01
  - accepted "manufactured stable 6x6 seed 20260911 index 134, cluster [3, 4]" 4.785e-01
  - accepted "manufactured stable 4x4 seed 20260911 index 33, cluster [2, 3]" 4.697e-01
  - accepted "manufactured stable 4x4 seed 20260911 index 42, cluster [2, 3]" 4.486e-01
  - rejected "crab ladder k = k_c (1 - -1.0e-7), cluster [1, 2, 5, 6]" 1.886e+03
  - rejected "crab ladder k = k_c (1 - -1.0e-6), cluster [1, 2, 5, 6]" 5.962e+03
  - rejected "crab ladder k = k_c (1 - -1.0e-5), cluster [1, 2, 5, 6]" 1.885e+04
  - rejected "crab ladder k = k_c (1 - -0.0001), cluster [1, 2, 5, 6]" 5.688e+04

##### c_gram (_GRAM_FLOOR_MULTIPLIER)

- ratio at multiplier 1: min |lambda(H)| / (rho_M1 / g_ext); accepted = every definite cluster (must exceed 10 c), rejected = single-copy halves of an exactly degenerate eigenspace under a crosswise partition (must stay below c / 10)
- source value: 64.0
- refused: "oracle repeated 3 (parameter -1.3), crosswise partition [[1, 5], [2, 6], [3, 4]]: REFUSED by the kernel: ArgumentError: _schur_spectral_projector: the selected block shares an eigenvalue with its"
- refused: "diag(R(0.73), R(1.41), R(0.73)), crosswise partition [[1, 5], [2, 6], [3, 4]]: REFUSED by the kernel: ArgumentError: _schur_spectral_projector: the selected block shares an eigenvalue with its"
- refused: "diag(R(0.9), R(0.9), R(0.9)), crosswise partition [[1, 4], [2, 5], [3, 6]]: REFUSED by the kernel: ArgumentError: _schur_spectral_projector: the selected block shares an eigenvalue with its"
- refused: "oracle repeated 0 (parameter -1.3), crosswise partition [[1, 6], [2, 5], [3, 4]]: REFUSED by the kernel: ArgumentError: _schur_spectral_projector: the selected block shares an eigenvalue with its"
- refused: "defective spectator (mu = 0.72), crosswise partition [[1, 3], [2, 4]]: REFUSED by the kernel: ArgumentError: _schur_spectral_projector: the selected block shares an eigenvalue with its"
- smallest accepted ratio (must exceed 10 c): 7.111e+03 at "crab ladder k = k_c (1 - 1.0e-10), cluster [2, 5]"
- largest rejected ratio (must stay below c / 10): 1.966e-01 at "trial-015 case 3 limit eps = 0.0, crosswise partition [[1, 5], [2, 6], [3, 4]], cluster [1, 5]"
- window [1.966e+00, 7.111e+02]; source value inside: true
  - accepted "crab ladder k = k_c (1 - 1.0e-10), cluster [2, 5]" 7.111e+03
  - accepted "crab ladder k = k_c (1 - 1.0e-10), cluster [1, 6]" 7.111e+03
  - accepted "rolled FODO detuned eps = 1.0e-9, cluster [1, 4]" 6.757e+04
  - accepted "crab ladder k = k_c (1 - 1.0e-9), cluster [1, 6]" 7.111e+04
  - rejected "trial-015 case 3 limit eps = 0.0, crosswise partition [[1, 5], [2, 6], [3, 4]], cluster [1, 5]" 1.966e-01
  - rejected "trial-015 case 3 limit eps = 0.0, crosswise partition [[1, 5], [2, 6], [3, 4]], cluster [2, 6]" 1.854e-01
  - rejected "oracle repeated 2 (parameter -1.3), crosswise partition [[1, 6], [2, 5], [3, 4]], cluster [2, 5]" 1.794e-01
  - rejected "oracle repeated 2 (parameter -1.3), crosswise partition [[1, 6], [2, 5], [3, 4]], cluster [1, 6]" 1.654e-01

##### c_mp (_MINIMAL_POLYNOMIAL_MULTIPLIER)

- ratio at multiplier 1: r_mp / (max(rho_M1, g_int) ||P_c||_2 / ||M||_F); accepted = definite and indefinite groups m >= 2 (incl. explicit partitions of the split controls), rejected = the defective spectators
- source value: 64.0
- largest accepted ratio: 5.445e-01 at "near collision diag(R(0.73), R(1.41), R(-0.73 - 1e-9)), partition x/z union [1, 2, 5, 6], cluster [1, 2, 5, 6]"
- smallest rejected ratio: 6.404e+06 at "rotated defective spectator (+) R(1.1), W6 seed 20260911, cluster [1, 2, 5, 6]"
- window [5.445e+00, 6.404e+05]; source value inside: true
  - accepted "near collision diag(R(0.73), R(1.41), R(-0.73 - 1e-9)), partition x/z union [1, 2, 5, 6], cluster [1, 2, 5, 6]" 5.445e-01
  - accepted "diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 trial 24, cluster [1, 2, 5, 6]" 3.499e-01
  - accepted "diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 trial 15, cluster [1, 2, 5, 6]" 2.984e-01
  - accepted "oracle repeated 2 (parameter -1.3), cluster [1, 2, 5, 6]" 2.654e-01
  - rejected "rotated defective spectator (+) R(1.1), W6 seed 20260911, cluster [1, 2, 5, 6]" 6.404e+06
  - rejected "rotated defective spectator, W4 seed 20260911, cluster [1, 2, 3, 4]" 1.180e+07
  - rejected "defective spectator (+) R(1.1), cluster [1, 2, 5, 6]" 1.039e+14
  - rejected "defective spectator (mu = 0.73), cluster [1, 2, 3, 4]" 1.903e+14

##### c_sub (_SUBSPACE_RESIDUAL_MULTIPLIER)

- ratio at multiplier 1: r_sub / (d eps); accepted = every cluster of every fixture; rejected = none reachable by a fixture (an ordered Schur basis is backward stable; the rejected side is an injected non-invariant basis, section 3)
- source value: 64.0
- largest accepted ratio: 1.308e+00 at "manufactured stable 4x4 seed 20260911 index 31, cluster [2, 3]"
- window [1.308e+01, Inf]; source value inside: true (no rejected fixture: the upper edge is open)
  - accepted "manufactured stable 4x4 seed 20260911 index 31, cluster [2, 3]" 1.308e+00
  - accepted "manufactured stable 4x4 seed 20260911 index 176, cluster [2, 3]" 1.286e+00
  - accepted "manufactured stable 4x4 seed 20260911 index 103, cluster [1, 4]" 1.218e+00
  - accepted "manufactured stable 4x4 seed 20260911 index 102, cluster [1, 4]" 1.201e+00

##### exact-set multiplier (_EXACT_SET_MULTIPLIER)

- ratio at multiplier 1: g_int / rho_M1; accepted = exactly degenerate definite m >= 2 clusters of 6D maps (FODO embedding, diag(R(0.73), R(1.41), R(0.73)) and 30 conjugations, the case-3 limit map), rejected = the 1e-12 control's 6D embedding
- source value: 10.0
- largest accepted ratio: 5.875e-01 at "diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 trial 19, cluster [1, 2, 5, 6]"
- smallest rejected ratio: 5.377e+02 at "rolled FODO detuned eps = 1.0e-12 (+) R(1.1), 6D embedding, cluster [1, 2, 3, 4, 5, 6]"
- window [5.875e+00, 5.377e+01]; source value inside: true
  - accepted "diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 trial 19, cluster [1, 2, 5, 6]" 5.875e-01
  - accepted "rolled FODO exact (+) R(1.1), 6D embedding, cluster [1, 2, 5, 6]" 5.379e-01
  - accepted "trial-015 case 3 limit eps = 0.0, cluster [1, 2, 5, 6]" 4.211e-01
  - accepted "diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 trial 24, cluster [1, 2, 5, 6]" 3.849e-01
  - rejected "rolled FODO detuned eps = 1.0e-12 (+) R(1.1), 6D embedding, cluster [1, 2, 3, 4, 5, 6]" 5.377e+02

| multiplier | source | window low | window high | inside | accepted rows | rejected rows |
|---|---|---|---|---|---|---|
| c_real | 1.0 | 2.039e-01 | 3.355e+00 | true | 22 | 2466 |
| c_stab | 64.0 | 5.179e+00 | 1.886e+02 | true | 1200 | 11 |
| c_gram | 64.0 | 1.966e+00 | 7.111e+02 | true | 1254 | 8 |
| c_mp | 64.0 | 5.445e+00 | 6.404e+05 | true | 53 | 4 |
| c_sub | 64.0 | 1.308e+01 | Inf | true | 1263 | 0 |
| exact_set | 10.0 | 5.875e+00 | 5.377e+01 | true | 33 | 1 |

#### 3. Rejected side of the c eps kappa check families (stage 3 block of test/runtests.jl)

Julia 1.12.4; seed 20260911. ratio = wrong-quantity residual / the check's threshold; every ratio must exceed 10. Rows whose fixture gives the defect nothing to act on are stated as such in section 3a of the report.

| runtests lines | fixture | wrong quantity (the defect) | residual | threshold | ratio | > 10 |
|---|---|---|---|---|---|---|
| 2648 | rolled FODO exact (theta = pi/4) | P from the unnormalized Schur basis Q (H^-1/2 skipped): \|\|P_Q - I\|\| | 1.814e+00 | 3.391e-13 | 5.350e+12 | true |
| 2650 | rolled FODO exact (theta = pi/4) | G from the unnormalized Schur basis: \|\|G_Q - Sigma_closed_form\|\| | 1.391e+01 | 6.781e-13 | 2.051e+13 | true |
| 2652, 2866 | rolled FODO exact (theta = pi/4) against the 1e-3 control's covariance | N6 closure under the exact map of the SPLIT control's G: \|\|M G_3 M' - G_3\|\| | 5.738e-03 | 1.695e-13 | 3.385e+10 | true |
| 2654, 2877 | rolled FODO exact (theta = pi/4) | restricted map of the conjugate orientation: \|\|T_conj - e^{-i mu} I\|\| | 2.756e+00 | 1.695e-13 | 1.626e+13 | true |
| 2655, 2875 | rolled FODO exact (theta = pi/4) | restricted map from Q (unnormalized): \|\|T_Q' T_Q - I\|\| | 1.402e+00 | 1.695e-13 | 8.269e+12 | true |
| 2656, 2878, 2905 | rolled FODO exact (theta = pi/4) | minimal-polynomial residual with tau = 2 cos(sum of tunes) | 3.818e-02 | 1.421e-14 | 2.687e+12 | true |
| 2659 | rolled FODO exact (theta = pi/4) | kappa_frame from 1 / max lambda instead of 1 / min lambda | 2.135e+00 | 1.695e-13 | 1.259e+13 | true |
| 2663 | rolled FODO detuned eps = 0.001 | (T7) discriminant of the SPLIT control (equal tunes assumed) | 9.203e-07 | 1.262e-13 | 7.292e+06 | true |
| 2737, 2829, 2900, 2903, 3453, 3648, 3720 | rolled FODO exact (theta = pi/4) | normalization of the CONJUGATE vector: \|conj(u)' S conj(u) + 2i\| | 4.000e+00 | 1.695e-13 | 2.359e+13 | true |
| 2742, 2770, 2858 | rolled FODO exact (theta = pi/4) | N4 first relation on Q (unnormalized): \|\|Q' S Q + 2i I\|\| | 2.566e+00 | 1.695e-13 | 1.513e+13 | true |
| 2771, 2859 | rolled FODO exact (theta = pi/4) | isotropy with a conjugate partner as second column: \|\|U^T S U\|\| | 2.828e+00 | 1.695e-13 | 1.668e+13 | true |
| 2739, 2906, 2973, 3005 | rolled FODO exact (theta = pi/4) | tune of the conjugate eigenvalue: \|(2 pi - mu) - mu\| | 5.830e+00 | 3.553e-15 | 1.641e+15 | true |
| 2725, 2941 | rolled FODO exact (theta = pi/4) | 13.8 reconstruction check with the frame's columns assigned the CONJUGATE eigenvalues | 4.496e-01 | 1.695e-13 | 2.652e+12 | true |
| 2808, 2861, 2872, 3252 | diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 seed 20260911 | Schur projector taken as 2 Re(Q Q') (a05): \|\|P_QQ - P_N5\|\| | 1.728e+00 | 1.703e-13 | 1.015e+13 | true |
| 2862 | diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 seed 20260911 | idempotency of 2 Re(Q Q') | 2.081e+00 | 1.703e-13 | 1.222e+13 | true |
| 2817, 2863 | diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 seed 20260911 | commutation of Re(Q Q') with M | 3.664e+00 | 7.975e-13 | 4.595e+12 | true |
| 2864 | diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 seed 20260911 | symplectic adjointness of Re(Q Q'): \|\|P^T S - S P\|\| | 1.617e+00 | 1.703e-13 | 9.499e+12 | true |
| 2868 | diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 seed 20260911 | P G = G with the y singleton's covariance paired with the pair's P | 1.714e+00 | 1.380e-13 | 1.242e+13 | true |
| 2814 | diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 seed 20260911 | PSD of Re(U U^T) (transpose instead of adjoint): -min eigenvalue | 2.850e+00 | 8.053e-14 | 3.539e+13 | true |
| 2818, 2937, 2938, 3076, 3514 | diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 seed 20260911 | kappa from the Frobenius norm squared instead of the 2-norm squared | 2.782e+00 | 8.053e-14 | 3.455e+13 | true |
| 2873 | diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 seed 20260911 | covariance without the real part's partner: \|\|Re(U U^T) - G\|\| | 7.688e+00 | 4.790e-13 | 1.605e+13 | true |
| 2879 | diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 seed 20260911 | tunes of the conjugate half | 4.823e+00 | 3.772e-13 | 1.279e+13 | true |
| 3149 | diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 seed 20260911, reciprocal scaling (3, 0.2, 7) | scaled P compared WITHOUT _unscale_projector | 1.199e+01 | 1.123e-10 | 1.068e+11 | true |
| 3150 | diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 seed 20260911, reciprocal scaling (3, 0.2, 7) | scaled G compared WITHOUT _unscale_covariance | 7.787e+01 | 3.160e-10 | 2.464e+11 | true |
| 2894, 3730, 3738 | diag(R(0.73), R(1.41), R(-0.73)) | Gram without the factor 1/2: \| \|lambda\| - 1/2 \| | 5.000e-01 | 3.553e-15 | 1.407e+14 | true |
| 2900 | diag(R(0.73), R(1.41), R(-0.73)) | signed basis with the negative column unconjugated: \|\|W' S W + 2i I\|\| | 4.000e+00 | 1.421e-14 | 2.815e+14 | true |
| 2904, 2966 | diag(R(0.73), R(1.41), R(-0.73)) | N5 formula on the unconjugated signed basis: \|\|-Im(W_u W_u') S - P\|\| | 2.828e+00 | 1.421e-14 | 1.990e+14 | true |
| 2954, 2985, 3091, 3567, 3632, 3784, 3796, 3826 | defective spectator (mu = 0.73) | fixture built without the interleaving permutation: \|\|J' S J - S\|\| | 4.040e-01 | 3.553e-15 | 1.137e+14 | true |
| 2961, 3800 | diag(1 + 1e-6, 1/(1 + 1e-6)) (+) R(1.2) | unit-circle departures of the hyperbolic pair against sqrt(eps) | 1.000e-06 | 1.490e-08 | 6.711e+01 | true |
| 2963 | defective spectator (mu = 0.73) | departure from normality of the FULL block (both halves) instead of the half block | 8.284e-02 | 1.421e-14 | 5.830e+12 | true |
| 2738, 2757, 2774, 2827, 3365 | W R(0.9) (+) R(0.9 + 1e-7) W^-1, partition [[1,2,3,4]], chord Inf | (I1) eigenvector residual with the two modes' eigenvalues SWAPPED | 1.000e-07 | 1.304e-13 | 7.668e+05 | true |
| 2773 | W R(0.9) (+) R(0.9 + 1e-7) W^-1, partition [[1,2,3,4]], chord Inf | normalization of a mode vector scaled by (1 + 1e-6) | 4.000e-06 | 1.304e-13 | 3.067e+07 | true |
| 2947 | rolled FODO detuned eps = 1.0e-12 | receipt gap of the SPLIT control against the exact-degeneracy pin 16 eps | 2.135e-12 | 3.553e-15 | 6.008e+02 | true |
| 3184, 3207 | rolled FODO exact (theta = pi/4) | backward error measured against a matrix perturbed by 1e-8 (fBE2) | 1.000e-08 | 4.234e-14 | 2.362e+05 | true |
| 3192 | _chord(2, 1e-15, 1e-9) | chord without the factor 2: \|kappa rho / g - 4e-6\| | 2.000e-06 | 3.553e-21 | 5.629e+14 | true |
| 3262, 3345, 3390, 3425, 3659 | diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 seed 20260911 | center from the z column P[1:4, 5] / 2 instead of the pz column P[1:4, 6] / 2 | 1.461e-01 | 2.013e-14 | 7.256e+12 | true |
| 3263, 3346, 3358 | diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 seed 20260911 | shape without the 1/4 | 4.111e+00 | 1.141e-13 | 3.604e+13 | true |
| 3265, 3285, 3319, 3348, 3391, 3660 | diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 seed 20260911 | factor F = V Lambda (sqrt forgotten): \|\|F F^T - A\|\| | 5.094e-01 | 1.141e-13 | 4.466e+12 | true |
| 3269, 3271, 3380, 3381, 3442, 3673, 3674 | diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 seed 20260911 | interval endpoints replaced by the midpoint (the rejected alternative): \|mid - hi\| | 6.701e-01 | 8.053e-14 | 8.322e+12 | true |
| 3380, 3381 | diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 seed 20260911 | N14 endpoint with the shape's quadratic form unrooted: \|hi_nosqrt - hi\| | 2.211e-01 | 8.053e-14 | 2.745e+12 | true |
| 3291-3302, 3462, 3463, 3722 | diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 seed 20260911 | (D12) readout with Re(conj(u_z) u_a) instead of -Im | 1.321e-01 | 3.553e-15 | 3.719e+13 | true |
| 3368, 3435 | diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 seed 20260911 | ellipsoid membership of a member scaled by 1.1 (\|\|c\|\| != 1) | 2.100e-01 | 2.577e-12 | 8.150e+10 | true |
| 3312, 3313, 3369 | diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 seed 20260911 | A A^+ dev = dev with A^+ replaced by inv(A + I) (rank ignored) | 4.144e-01 | 1.825e-12 | 2.271e+11 | true |
| 3357 | diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 seed 20260911 | frame with a column scaled by 2 (non-unitary mixing): the (N4) guard's normalization residual (set constructor refuses it: true) | 6.000e+00 | 5.179e-13 | 1.159e+13 | true |
| 3394, 3395 | diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 seed 20260911 | (P, G) method with P^T instead of P: center shift (method refuses P^T: false) | 1.415e-01 | 8.053e-14 | 1.758e+12 | true |
| 3255-3257, 3339, 3340, 3821 | diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 seed 20260911 | (N4) normalization residual of a column scaled by 1 + 1e-6 against one tenth of the refusal (the checker refuses it: true) | 4.000e-06 | 1.611e-14 | 2.484e+08 | true |
| 3323, 3399-3406 | diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 seed 20260911 | Bloch readout with the spinor sign flipped: \|\|F n - F (-n)\|\| | 2.099e-01 | 8.053e-14 | 2.607e+12 | true |
| 3636-3652, 3707 | isospectral family seed 20260920, eps = 1e-7 | SAME spinor at both endpoints (Part B's injection): \|diameter_wrong - 2 sigma_1\| | 1.204e+00 | 2.342e-14 | 5.140e+13 | true |
| 3719 | diag(R(0.73), R(1.41), R(-0.73)) | N15 vector against the CONJUGATE eigenvalue e^{-i mu} | 2.181e+00 | 3.801e-14 | 5.739e+13 | true |
| 3722, 3723 | diag(R(0.73), R(1.41), R(-0.73)) | N15 eta_x with the sign flipped: \|+sinh t cosh t - (-sinh t cosh t)\| | 8.881e-01 | 3.801e-14 | 2.336e+13 | true |
| 3758 | diag(R(0.73), R(1.41), R(0.73)) | (N16) determinant of the polynomial block with a tune outside the spectrum (1.0) | 9.707e-02 | 1.421e-14 | 6.831e+12 | true |
| 3764, 3790 | diag(R(0.73), R(1.41), R(0.73)), graph residual pin | (D14) residual expected with \|1 - t\| instead of \|2 - t\| at t = 0.3 | 9.431e-01 | 2.278e-14 | 4.139e+13 | true |
| 3788 | crab map k = 0.3 on diag(R(0.73), R(1.41), R(0.73)) | graph from a regularized solve instead of pinv: \|\|D\|\| | 4.939e-05 | 1.663e-14 | 2.970e+09 | true |
| 3574 | rolled FODO exact (+) R(1.1), 6D embedding | P of the betatron cluster compared with I_6 (the whole space) instead of diag(I_4, 0) | 1.414e+00 | 3.391e-13 | 4.171e+12 | true |
| 3588, 3589 | W6 (rolled FODO exact (+) R(1.1)) W6^-1, seed 20260911 | center of the betatron cluster of the COUPLED embedding (nonzero dispersion) against the block-diagonal zero pin | 5.441e-01 | 3.547e-13 | 1.534e+12 | true |

Rows: 55; below ten: 0.

#### 4. Paper cross-check (mode_degeneracy.py analyze_cluster, real outputs, 1e-12 absolute)

python 3.11.5 numpy 1.23.5 scipy 1.11.4; mode_degeneracy.py from /cfs/ad/dxu/Paper/2026_twiss_dispersion/research/mode_degeneracy.py; Julia 1.12.4. Only real outputs are compared (pitfall 10: the prototype's frame is the conjugate of ours). Endpoint rows compare the isolated single mode's projector, covariance and the pz column eta = P[1:4, 6] / 2 against the dump's expected eta.

| name | m (py) | m (jl) | Gram min py | Gram min jl | max|P diff| | max|G diff| | max|center diff| | max|shape diff| | max|eta - dump| | q of the row | ok |
|---|---|---|---|---|---|---|---|---|---|---|---|
| rolled FODO exact (theta = pi/4) | 2 | 2 | 0.083822243293302 | 0.08382224329330203 | 4.086e-14 | 7.105e-15 | NaN | NaN | NaN | 0.000e+00 | true |
| rolled FODO exact (+) R(1.1), 6D embedding | 2 | 2 | 0.083822243293302 | 0.08382224329330203 | 4.086e-14 | 7.105e-15 | 0.000e+00 | 0.000e+00 | NaN | 0.000e+00 | true |
| trial-015 case 3 limit eps = 0.0 | 2 | 2 | 0.43256473072538343 | 0.4325647307253834 | 6.037e-16 | 1.332e-15 | 1.110e-16 | 3.331e-16 | NaN | 0.000e+00 | true |
| trial-015 case 3 minus eps = 0.001 | 1 | 1 | 0.43423562795242504 | 0.43423562795242504 | 6.777e-14 | 1.110e-16 | 2.670e-14 | NaN | 5.829e-14 | 5.172e-12 | true |
| trial-015 case 3 plus eps = 0.001 | 1 | 1 | 0.4674336623794959 | 0.467433662379496 | 1.102e-13 | 1.665e-16 | 4.785e-14 | NaN | 1.031e-13 | 5.171e-12 | true |
| trial-015 case 3 minus eps = 1.0e-5 | 1 | 1 | 0.4342356279527478 | 0.4342356279527476 | 2.014e-11 | 4.441e-16 | 8.290e-12 | NaN | 1.090e-11 | 5.172e-10 | true |
| trial-015 case 3 plus eps = 1.0e-5 | 1 | 1 | 0.46743366237969897 | 0.46743366237969897 | 4.785e-11 | 1.110e-16 | 1.610e-11 | NaN | 1.066e-11 | 5.172e-10 | true |
| trial-015 case 3 minus eps = 1.0e-7 | 1 | 1 | 0.43423562795306947 | 0.43423562795306936 | 2.185e-09 | 2.220e-16 | 8.150e-10 | NaN | 1.765e-09 | 5.172e-08 | true |
| trial-015 case 3 plus eps = 1.0e-7 | 1 | 1 | 0.46743366242139384 | 0.4674336624213938 | 1.391e-09 | 2.220e-16 | 6.250e-10 | NaN | 1.528e-09 | 5.172e-08 | true |
| trial-015 case 3 minus eps = 1.0e-9 | 1 | 1 | 0.4342356268670648 | 0.43423562686706474 | 1.566e-07 | 0.000e+00 | 4.753e-08 | NaN | 3.020e-08 | 5.172e-06 | true |
| trial-015 case 3 plus eps = 1.0e-9 | 1 | 1 | 0.4674336620161902 | 0.46743366201619024 | 2.767e-07 | 2.776e-17 | 8.678e-08 | NaN | 6.061e-08 | 5.172e-06 | true |

Rows: 11; worst difference over the m >= 2 rows 4.086e-14; all m >= 2 rows within 1e-12: true; singleton rows are judged against their own q (conditioning of a copy isolated from a split pair). Input /cfs/ad/dxu/Library/Julia/Octopus/result/twiss_impl_2026_09_11/stage3/measure/paper_input.tsv, output /cfs/ad/dxu/Library/Julia/Octopus/result/twiss_impl_2026_09_11/stage3/measure/paper_output.tsv.

### Appendix: the measurement scripts

`measure_stage3.jl` (the Part D1 driver: sections 1, 1a, 2 and 4 of the table; package mode from `OUT/measure`, reads stage 1's oracle TSV and the case-3 TSV, runs `paper_crosscheck.py` once):

```julia
# Stage 3 measurement (Part D1): the scaffold of Part B wired to `_mode_clusters`.
# Tabulates, for the fixture list of the dossier, the resolution-chord
# quantities of the design ("Default value"): kappa_frame, kappa_eig, rho_M0
# and its winning arm (named from the data), rho_M1, the internal and external
# gaps, the chord q that decided the cluster, the classification and the
# resolved flag; prints the bracket with the argmax rows' OWN names; then
# measures every PROVISIONAL multiplier's window by the one-tenth / ten rule
# (section 2), and cross-checks the paper's mode_degeneracy.py real outputs
# (section 4) by running Python once from here.
#
# Package mode, from the tree under test:
#   julia --startup-file=no --project=<tree> --threads=4 measure_stage3.jl <oracle_maps.tsv> <trial015_case3.tsv> <out.md>
using Octopus, LinearAlgebra, Random, Printf
include(joinpath(@__DIR__, "..", "fixtures_stage3.jl"))

const ORACLE_TSV = ARGS[1]
const CASE3_TSV = ARGS[2]
const OUT_MD = ARGS[3]
const EPS = eps(Float64)
const SEED = 20260911
const PYTHON = "/opt/anaconda3_2024_02/bin/python3"
const RESEARCH = "/cfs/ad/dxu/Paper/2026_twiss_dispersion/research"
e2(x) = x isa Bool ? string(x) : x isa Real ? @sprintf("%.3e", x) : string(x)
dv(d) = Octopus.is_determined(d) ? determined_value(d) : nothing   # unavailable -> nothing (printed as such)
rho0(M) = Octopus._perturbation_scale(M, Octopus._symplectic_defect(M).frobenius)
bd(ms...) = cat(ms...; dims=(1, 2))
R(mu) = Octopus._rotation2(mu)

# --- loaders (family and index carried with every map) -----------------------
function load_oracle_maps(path)
    lines = readlines(path)
    hdr = split(lines[1], '\t')
    @assert hdr[1:3] == ["family", "index", "parameter"] "oracle TSV header moved: $(hdr[1:3])"
    return [(f = split(l, '\t');
             (family=String(f[1]), index=parse(Int, f[2]), parameter=String(f[3]),
              M=permutedims(reshape(parse.(Float64, f[4:39]), 6, 6))))
            for l in lines[2:end] if !isempty(l)]
end
function load_case3(path)
    lines = filter(l -> !isempty(l) && !startswith(l, '#'), readlines(path))
    hdr = split(lines[1], '\t')
    @assert hdr[1:2] == ["kind", "epsilon"] "case-3 TSV header moved: $(hdr[1:2])"
    return [(f = split(l, '\t');
             (kind=String(f[1]), epsilon=parse(Float64, f[2]),
              M=permutedims(reshape(parse.(Float64, f[3:38]), 6, 6)), eta=parse.(Float64, f[39:42])))
            for l in lines[2:end]]
end

# --- the fixture list: (name, map, label) ---------------------------------------
# Labels come from the design ("Default value") and the theory only: the FODO
# controls at 1e-3, 1e-6, 1e-9 must resolve (periodic tune error 4.45e-9 at
# 1e-9), the 1e-12 control must not (tune error 5.89e-6); every dense oracle
# map must resolve (distinct tunes by construction); the near collision must
# not ("never two definite modes"). Nothing else is labelled.
struct Fixture
    name::String
    M::Matrix{Float64}
    label::Symbol            # :must_resolve, :must_not_resolve, :unlabelled
end
function fixture_list()
    pins = st3_fodo_pins()
    fx = Fixture[]
    push!(fx, Fixture("rolled FODO exact (theta = pi/4)", st3_rolled_fodo(pins.theta), :unlabelled))
    for ep in (1e-3, 1e-6, 1e-9, 1e-12)
        lab = ep == 1e-12 ? :must_not_resolve : :must_resolve
        push!(fx, Fixture("rolled FODO detuned eps = $(ep)", st3_rolled_fodo(pins.theta; eps=ep), lab))
    end
    for r in load_case3(CASE3_TSV)
        push!(fx, Fixture("trial-015 case 3 $(r.kind) eps = $(r.epsilon)", r.M, :unlabelled))
    end
    for o in load_oracle_maps(ORACLE_TSV)
        lab = o.family == "dense" ? :must_resolve : :unlabelled
        push!(fx, Fixture("oracle $(o.family) $(o.index) (parameter $(o.parameter))", o.M, lab))
    end
    kc = st3_crab_kc()
    for ep in (1e-1, 1e-2, 1e-3, 1e-4, 1e-5, 1e-6, 1e-7, 1e-8, 1e-9, 1e-10, 1e-11)   # 1e-10, 1e-11: the fixer's coupled near collision, added as data
        push!(fx, Fixture("crab ladder k = k_c (1 - $(ep))", st3_crab_map(kc * (1 - ep)), :unlabelled))
    end
    # The fixture table labelled the block-diagonal near collision "never two definite modes"; the fixer's F21
    # showed the wording wrong for THIS fixture (block-diagonal: kappa_eig = 2 exactly, the modes are separable and
    # the chord resolves them), and the coupled crab ladder is the near collision that must not resolve. It is
    # therefore UNLABELLED here (design + theory label nothing else); the bracket it would impose is printed below.
    push!(fx, Fixture("near collision diag(R(0.73), R(1.41), R(-0.73 - 1e-9))", st3_near_collision_6d(1e-9), :unlabelled))
    push!(fx, Fixture("defective spectator (mu = 0.72)", st3_defective_spectator(0.72), :unlabelled))
    rng = MersenneTwister(SEED)
    for d in (4, 6), i in 1:200
        push!(fx, Fixture("manufactured stable $(d)x$(d) seed $(SEED) index $(i)",
                          Octopus._manufactured_symplectic_map(rng, d; stable=true).M, :unlabelled))
    end
    return fx
end

# --- one row per cluster, from `_mode_clusters` ---------------------------------
# q is the chord that decided the cluster: the largest of (a) the receipt chord of
# the merge that formed it, (b) its internal chord matrix (mode recovery), (c) the
# last round's chord between it and every other final cluster. For a resolved
# singleton this is the chord that kept it apart; for a merged cluster the chord
# that merged it or that keeps its modes unresolved.
const ROW_FIELDS = (:name, :cluster, :m, :kappa_frame, :kappa_eig, :rho_M0, :rho_arm, :rho_M1,
                    :g_int, :g_ext, :q, :q_source, :classification, :resolved, :kind, :label)
function cluster_rows(fx::Fixture; chord=Octopus._DEFAULT_RESOLUTION_CHORD)
    M = fx.M
    ps = rho0(M)
    arm = string(argmax(ps.arms))                 # the winning arm NAMED from the data
    r = Octopus._mode_clusters(M; rho_M0=ps.scale, resolution_chord=chord)
    rows = NamedTuple[]
    for (i, c) in enumerate(r.clusters)
        q_merge = maximum((e.chord for e in r.resolution_receipt
                           if e.merged && issubset(vcat(e.first, e.second), c.members)); init=0.0)
        q_int = isempty(c.chord_matrix) ? 0.0 : maximum(c.chord_matrix)
        q_ext = length(r.clusters) > 1 ? maximum(r.inter_cluster_chords[i, :]) : 0.0
        q, which = findmax((merge=q_merge, internal=q_int, between=q_ext))
        m = length(c.half_members)
        kind = (c.classification === :definite && m >= 2 && size(M, 1) == 6) ?
               Octopus._ambiguity_kind(c.internal_gap, c.rho_M1) : :none
        push!(rows, (name=fx.name, cluster=i, m=m, kappa_frame=dv(c.kappa_frame), kappa_eig=dv(c.kappa_eig),
                     rho_M0=ps.scale, rho_arm=arm, rho_M1=c.rho_M1, g_int=c.internal_gap, g_ext=c.external_gap,
                     q=q, q_source=which, classification=c.classification, resolved=c.resolved, kind=kind, label=fx.label))
    end
    return (rows=rows, result=r)
end

# --- section 1: the chord table and the bracket -----------------------------------
function chord_table(io, fixtures)
    rows = NamedTuple[]; results = Dict{String,Any}()
    for fx in fixtures
        out = cluster_rows(fx)
        append!(rows, out.rows); results[fx.name] = out.result
    end
    pr(s) = println(io, s)
    pr("# Stage 3 measurement table (Part D1)\n")
    pr("Julia $(VERSION); threads $(Threads.nthreads()); seed $(SEED); oracle TSV $(ORACLE_TSV); case-3 TSV $(CASE3_TSV).")
    pr("Source constants at run time: _DEFAULT_RESOLUTION_CHORD = $(Octopus._DEFAULT_RESOLUTION_CHORD), c_real = $(Octopus._REAL_CLASS_MULTIPLIER), c_stab = $(Octopus._STABILITY_MULTIPLIER), c_gram = $(Octopus._GRAM_FLOOR_MULTIPLIER), c_mp = $(Octopus._MINIMAL_POLYNOMIAL_MULTIPLIER), c_sub = $(Octopus._SUBSPACE_RESIDUAL_MULTIPLIER), exact-set = $(Octopus._EXACT_SET_MULTIPLIER).")
    pr("q = min(2, 2 kappa rho_M1 / g) as `_mode_clusters` evaluated it (q_source names which chord decided the row: merge, internal, between); rho_M1 = max(rho_M0, Schur backward error of the half). Every name in this file is printed from its data row.\n")
    pr("## 1. Chord table\n")
    pr("| " * join(string.(ROW_FIELDS), " | ") * " |")
    pr("|" * repeat("---|", length(ROW_FIELDS)))
    for r in rows
        pr("| " * join([e2(getfield(r, f)) for f in ROW_FIELDS], " | ") * " |")
    end
    # Bracket: the design's rule. A must-resolve fixture's q is the largest chord
    # over its clusters (all must be resolved); a must-not-resolve fixture's q is
    # the chord of the cluster that must stay merged (the largest over its clusters).
    byname = Dict{String,Vector{NamedTuple}}()
    for r in rows; push!(get!(byname, r.name, NamedTuple[]), r); end
    fixq(name) = maximum(r.q for r in byname[name])
    must = unique([r.name for r in rows if r.label === :must_resolve])
    mustnot = unique([r.name for r in rows if r.label === :must_not_resolve])
    unl = unique([r.name for r in rows if r.label === :unlabelled])
    pr("\n## 1a. Bracket (design \"Default value\")\n")
    pr("- must-resolve fixtures: $(length(must)); all their clusters resolved: $(all(all(r.resolved for r in byname[n]) for n in must))")
    for n in mustnot
        pr("- must-not-resolve fixture \"$(n)\": clusters $(join(["m = $(r.m) $(r.classification) resolved = $(r.resolved)" for r in byname[n]], ", "))")
    end
    for n in unl
        occursin("near collision", n) || continue
        pr("- (objection record) \"$(n)\": clusters $(join(["m = $(r.m) $(r.classification) resolved = $(r.resolved)" for r in byname[n]], ", ")); q = $(e2(fixq(n))); labelled must-not-resolve it would give the bracket [$(e2(maximum(fixq(x) for x in must))), $(e2(fixq(n)))]")
    end
    n_lo = must[argmax([fixq(n) for n in must])]; lo = fixq(n_lo)
    n_hi = mustnot[argmin([fixq(n) for n in mustnot])]; hi = fixq(n_hi)
    gm = sqrt(lo * hi); rounded = round(gm; sigdigits=1)
    pr("- largest q of a must-resolve fixture: $(e2(lo)) at \"$(n_lo)\"")
    pr("- smallest q of a must-not-resolve fixture: $(e2(hi)) at \"$(n_hi)\"")
    pow10 = 10.0^round(log10(gm))
    pr("- bracket [$(e2(lo)), $(e2(hi))]; geometric mean sqrt($(e2(lo)) * $(e2(hi))) = $(e2(gm)); rounded to one significant digit $(rounded); rounded to a power of ten (the design's own example 7.9e-5 -> 1e-4) $(pow10)")
    pr("- source constant $(Octopus._DEFAULT_RESOLUTION_CHORD) equals the power-of-ten rounding: $(pow10 == Octopus._DEFAULT_RESOLUTION_CHORD); margins at the source constant: must-resolve extreme ratio $(e2(lo / Octopus._DEFAULT_RESOLUTION_CHORD)), must-not-resolve extreme ratio $(e2(hi / Octopus._DEFAULT_RESOLUTION_CHORD))")
    pr("- provisional 1e-4 inside the bracket: $(lo < 1e-4 < hi); rounded mean equals the source constant $(Octopus._DEFAULT_RESOLUTION_CHORD): $(rounded == Octopus._DEFAULT_RESOLUTION_CHORD)")
    inside = [n for n in unl if lo < fixq(n) < hi]
    pr("- unlabelled fixtures with q inside the bracket ($(length(inside))): " * (isempty(inside) ? "none" : join(["\"$(n)\" ($(e2(fixq(n))))" for n in inside], "; ")))
    # Sorted list of the must-resolve chords (the dense oracle maps and the FODO controls).
    pr("- must-resolve chords, descending: " * join(["\"$(n)\" $(e2(fixq(n)))" for n in sort(must; by=n -> -fixq(n))[1:min(6, end)]], "; "))
    pr("- must-not-resolve chords, ascending: " * join(["\"$(n)\" $(e2(fixq(n)))" for n in sort(mustnot; by=fixq)], "; "))
    pr("\nRows: $(length(rows)); fixtures: $(length(fixtures)).")
    return (rows=rows, results=results, lo=lo, hi=hi, gm=gm, rounded=rounded, n_lo=n_lo, n_hi=n_hi)
end

# --- section 2: PROVISIONAL multiplier windows (design: one tenth / ten) ------------
# Every ratio is the decision quantity at multiplier 1 (quantity / threshold with
# the multiplier divided out). For a check where the ACCEPTED side must sit below
# the threshold (c_real, c_stab, c_mp, c_sub, exact-set) the window is
# [10 * max accepted, min rejected / 10]; for the Gram floor, where the accepted
# side (a definite Gram eigenvalue) must sit ABOVE the floor, the roles swap:
# [10 * max rejected, min accepted / 10]. Names are printed from the rows.
function window_lines(title, formula, acc::Dict{String,Float64}, rej::Dict{String,Float64}, current; accepted_below::Bool=true)
    out = String["### $(title)", "", "- ratio at multiplier 1: $(formula)", "- source value: $(current)"]
    refused = [k for (k, v) in rej if isnan(v)]
    rej = Dict(k => v for (k, v) in rej if !isnan(v))
    for k in refused; push!(out, "- refused: \"$(k)\""); end
    ka = isempty(acc) ? nothing : argmax(acc); kr = isempty(rej) ? nothing : argmin(rej)
    if accepted_below
        ka === nothing || push!(out, "- largest accepted ratio: $(e2(acc[ka])) at \"$(ka)\"")
        kr === nothing || push!(out, "- smallest rejected ratio: $(e2(rej[kr])) at \"$(kr)\"")
        lo = ka === nothing ? 0.0 : 10 * acc[ka]; hi = kr === nothing ? Inf : rej[kr] / 10
    else
        kr2 = isempty(rej) ? nothing : argmax(rej); ka2 = isempty(acc) ? nothing : argmin(acc)
        ka2 === nothing || push!(out, "- smallest accepted ratio (must exceed 10 c): $(e2(acc[ka2])) at \"$(ka2)\"")
        kr2 === nothing || push!(out, "- largest rejected ratio (must stay below c / 10): $(e2(rej[kr2])) at \"$(kr2)\"")
        lo = kr2 === nothing ? 0.0 : 10 * rej[kr2]; hi = ka2 === nothing ? Inf : acc[ka2] / 10
    end
    inside = lo <= current <= hi
    push!(out, "- window [$(e2(lo)), $(e2(hi))]; source value inside: $(inside)" * (isempty(rej) ? " (no rejected fixture: the upper edge is open)" : ""))
    for k in (accepted_below ? sort(collect(keys(acc)); by=k -> -acc[k]) : sort(collect(keys(acc)); by=k -> acc[k]))[1:min(4, length(acc))]
        push!(out, "  - accepted \"$(k)\" $(e2(acc[k]))")
    end
    for k in (accepted_below ? sort(collect(keys(rej)); by=k -> rej[k]) : sort(collect(keys(rej)); by=k -> -rej[k]))[1:min(4, length(rej))]
        push!(out, "  - rejected \"$(k)\" $(e2(rej[k]))")
    end
    push!(out, "")
    return (lines=out, lo=lo, hi=hi, inside=inside, n_acc=length(acc), n_rej=length(rej))
end

# Extra fixtures named by the constants' docstrings (built here, names carried).
function extra_fixtures()
    rng = MersenneTwister(SEED)
    W4 = st3_random_symplectic(rng, 4, 0.2); W6 = st3_random_symplectic(rng, 6, 0.2)
    pins = st3_fodo_pins()
    fodo6 = bd(st3_rolled_fodo(pins.theta), R(1.1))
    A = (1 + 1e-4) * R(0.6); quartet = bd(A, inv(A)')[[1, 3, 2, 4], [1, 3, 2, 4]]
    kc = st3_crab_kc()
    unit = [("I_4", Matrix(1.0I, 4, 4)), ("I_2 (+) R(1.2)", bd(Matrix(1.0I, 2, 2), R(1.2))),
            ("-I_2 (+) R(1.2)", bd(-Matrix(1.0I, 2, 2), R(1.2))), ("drift [1 3; 0 1] (+) R(1.2)", bd([1.0 3.0; 0 1], R(1.2))),
            ("rotated drift (+) R(1.2), W4 seed $(SEED)", W4 * bd([1.0 3.0; 0 1], R(1.2)) * inv(W4))]
    defect = [("defective spectator (mu = 0.73)", st3_defective_spectator(0.73)),
              ("rotated defective spectator, W4 seed $(SEED)", W4 * st3_defective_spectator(0.73) * inv(W4)),
              ("defective spectator (+) R(1.1)", bd(st3_defective_spectator(0.73), R(1.1))),
              ("rotated defective spectator (+) R(1.1), W6 seed $(SEED)", W6 * bd(st3_defective_spectator(0.73), R(1.1)) * inv(W6))]
    offcircle = [("diag(1 + 1e-6, 1/(1 + 1e-6)) (+) R(1.2)", bd([1 + 1e-6 0; 0 1 / (1 + 1e-6)], R(1.2))),
                 ("diag(2, 1/2) (+) R(1.2)", bd([2.0 0; 0 0.5], R(1.2))),
                 ("complex quartet (1 + 1e-4) R(0.6) (+) its inverse adjoint", quartet)]
    crab_unstable = [("crab ladder k = k_c (1 - $(e))", st3_crab_map(kc * (1 - e))) for e in (-1e-2, -1e-3, -1e-4, -1e-5, -1e-6, -1e-7)]
    crab_deep = [("crab ladder k = k_c (1 - $(e))", st3_crab_map(kc * (1 - e))) for e in (1e-10, 1e-11)]
    tiny = [("R(1e-6) (+) R(1.2)", bd(R(1e-6), R(1.2)))]
    return (unit=unit, defect=defect, offcircle=offcircle, crab_unstable=crab_unstable, crab_deep=crab_deep, tiny=tiny,
            fodo6=("rolled FODO exact (+) R(1.1), 6D embedding", fodo6),
            fodo6_12=("rolled FODO detuned eps = 1.0e-12 (+) R(1.1), 6D embedding", bd(st3_rolled_fodo(pins.theta; eps=1e-12), R(1.1))),
            W4=W4, W6=W6)
end
runmc(M; kw...) = Octopus._mode_clusters(M; rho_M0=rho0(M).scale, kw...)

# c_real and c_stab over the chord-table results plus the docstring fixtures.
function measure_real_stab(results::Dict{String,Any}, ex)
    acc_r = Dict{String,Float64}(); rej_r = Dict{String,Float64}(); acc_s = Dict{String,Float64}(); rej_s = Dict{String,Float64}()
    c_real = Octopus._REAL_CLASS_MULTIPLIER; c_stab = Octopus._STABILITY_MULTIPLIER
    function real!(name, r)
        for (j, z) in enumerate(r.eigenvalues)
            (r.real_class[j] ? acc_r : rej_r)["$(name), eigenvalue $(j)"] = abs(imag(z)) / (r.tau_real / c_real)
        end
    end
    stab_acc!(name, r) = for c in r.clusters
        acc_s["$(name), cluster $(c.members)"] = maximum(c.unit_circle_departures) / (c.stability_scale / c_stab)
        c.classification === :unstable && println("  !! accepted fixture $(name) has an :unstable cluster $(c.members)")
    end
    stab_rej!(name, r, pred) = for c in r.clusters
        pred(c) || continue
        rej_s["$(name), cluster $(c.members)"] = minimum(c.unit_circle_departures) / (c.stability_scale / c_stab)
        c.classification === :unstable || println("  !! rejected fixture $(name) cluster $(c.members) is $(c.classification)")
    end
    for (name, r) in results; real!(name, r); stab_acc!(name, r); end
    for (name, M) in vcat(ex.unit, ex.defect, ex.crab_deep, [ex.fodo6, ex.fodo6_12]); r = runmc(M); real!(name, r); stab_acc!(name, r); end
    for (name, M) in vcat(ex.offcircle, ex.tiny); r = runmc(M); real!(name, r); end
    for (name, M) in ex.offcircle; stab_rej!(name, runmc(M), c -> isempty(c.half_members) || startswith(name, "complex quartet")); end
    # crab k > k_c: the colliding x/z pair leaves the circle (Krein collision); the y block R(2.1) is a spectator.
    for (name, M) in ex.crab_unstable; r = runmc(M); real!(name, r); stab_rej!(name, r, c -> length(c.half_members) != 1 || abs(c.tunes[1] - 2.1) > 0.1); end
    return (acc_r=acc_r, rej_r=rej_r, acc_s=acc_s, rej_s=rej_s)
end

# Degenerate copies split into their own pairs: for an exactly degenerate group
# of half members {j1, j2, ...} (equal eigenvalues to 1e-12) the partition
# [[j1, partner(j1)], [j2, partner(j2)], ...] makes every cluster's half a single
# member of the degenerate eigenspace, whose Gram value is arbitrary in
# [-1/2, 1/2] and whose external gap is the copy distance (roundoff), so its
# floor exceeds 1: the Gram-floor REJECTED fixture (fixer F18, derived here from
# the eigenvalue data and the report's own conjugate pairing).
function crosswise_partition(r)
    d = length(r.eigenvalues)
    half = [j for j in 1:d if !r.real_class[j] && imag(r.eigenvalues[j]) > 0]
    groups = Vector{Vector{Int}}()
    for j in half
        g = findfirst(G -> abs(r.eigenvalues[G[1]] - r.eigenvalues[j]) <= 1e-12, groups)
        g === nothing ? push!(groups, [j]) : push!(groups[g], j)
    end
    parts = Vector{Vector{Int}}()
    for G in groups
        for j in G
            push!(parts, sort([j, r.conjugate_partner[j]]))
        end
    end
    for j in 1:d
        r.real_class[j] && push!(parts, [j])
    end
    return (parts=parts, degenerate=any(G -> length(G) >= 2, groups))
end

function measure_gram_mp_sub_exact(results::Dict{String,Any}, ex)
    acc_g = Dict{String,Float64}(); rej_g = Dict{String,Float64}()
    acc_m = Dict{String,Float64}(); rej_m = Dict{String,Float64}()
    acc_s = Dict{String,Float64}()
    acc_e = Dict{String,Float64}(); rej_e = Dict{String,Float64}()
    mp_ratio(c, M) = determined_value(c.residuals).minimal_polynomial /
                     (max(c.rho_M1, c.internal_gap) * opnorm(determined_value(c.projector), 2) / norm(M))
    function gather!(name, r; mp_accept=true)
        for c in r.clusters
            key = "$(name), cluster $(c.members)"
            Octopus.is_determined(c.residuals) && (acc_s[key] = determined_value(c.residuals).subspace / (size(r.matrix, 1) * EPS))
            if c.classification === :definite
                acc_g[key] = minimum(abs, c.gram_eigenvalues) / (c.rho_M1 / c.external_gap)
            end
            # accepted: the groups the minimal polynomial let through; rejected: the groups it refused
            # (:unresolved with the minimal-polynomial sub-reason), both with the residual available.
            if length(c.half_members) >= 2 && Octopus.is_determined(c.residuals) && Octopus.is_determined(c.projector)
                if mp_accept && c.classification in (:definite, :indefinite)
                    acc_m[key] = mp_ratio(c, r.matrix)
                elseif !mp_accept && c.classification === :unresolved && occursin("minimal-polynomial", c.detail)
                    rej_m[key] = mp_ratio(c, r.matrix)
                elseif !mp_accept
                    println("  !! rejected mp fixture $(key) is $(c.classification): $(c.detail)")
                end
            end
        end
    end
    for (name, r) in results; gather!(name, r); end
    # Gram floor, rejected: crosswise partitions of the exactly degenerate fixtures.
    rng = MersenneTwister(SEED + 1)
    degenerate = Any[(n, r.matrix) for (n, r) in results if crosswise_partition(r).degenerate]
    push!(degenerate, ("diag(R(0.73), R(1.41), R(0.73))", st3_definite_pair_6d()), ("diag(R(0.9), R(0.9), R(0.9))", st3_definite_triple_6d(0.9)))
    for (name, M) in degenerate
        r0 = runmc(M); cp = crosswise_partition(r0)
        # A bit-identical repeated eigenvalue has no spectral projector onto one copy: the
        # kernel refuses loudly (LAPACK trsyl); the refusal is recorded as data, not skipped.
        rp = try
            runmc(M; partition=cp.parts)
        catch e
            rej_g["$(name), crosswise partition $(cp.parts): REFUSED by the kernel: $(first(sprint(showerror, e), 90))"] = NaN
            continue
        end
        degenerate_half = [j for j in 1:length(r0.eigenvalues) if imag(r0.eigenvalues[j]) > 0 &&
                           count(k -> abs(r0.eigenvalues[k] - r0.eigenvalues[j]) <= 1e-12, 1:length(r0.eigenvalues)) >= 2]
        for c in rp.clusters
            (length(c.half_members) == 1 && c.half_members[1] in degenerate_half) || continue   # a copy of the degenerate eigenspace only
            key = "$(name), crosswise partition $(cp.parts), cluster $(c.members)"
            rej_g[key] = minimum(abs, c.gram_eigenvalues) / (c.rho_M1 / c.external_gap)
            c.krein_signs == [0] || println("  !! crosswise cluster $(key) has signs $(c.krein_signs)")
        end
    end
    # Minimal polynomial: accepted (definite / indefinite groups, incl. the conjugated 6D fixtures and
    # the resolved controls forced into one cluster by an explicit partition), rejected (defective spectators).
    conj = [("diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 trial $(t)", (W = st3_random_symplectic(rng, 6, 0.2); W * st3_definite_pair_6d() * inv(W))) for t in 1:30]
    trip = [("diag(R(0.9), R(0.9), R(0.9)) conjugated by W6 trial $(t)", (W = st3_random_symplectic(rng, 6, 0.2); W * st3_definite_triple_6d(0.9) * inv(W))) for t in 1:10]
    for (name, M) in vcat(conj, trip, [("diag(R(0.73), R(1.41), R(-0.73))", st3_indefinite_6d())]); gather!(name, runmc(M)); end
    pins = st3_fodo_pins()
    for ep in (1e-3, 1e-6, 1e-9, 1e-12)
        gather!("rolled FODO detuned eps = $(ep), partition [[1, 2, 3, 4]]", runmc(st3_rolled_fodo(pins.theta; eps=ep); partition=[[1, 2, 3, 4]]))
    end
    rn = runmc(st3_near_collision_6d(1e-9)); xz = [j for j in 1:6 if abs(abs(rn.eigenvalues[j]) - 1) < 1e-8 && abs(mod(-angle(rn.eigenvalues[j]), 2pi) - 1.41) > 0.1 && abs(mod(angle(rn.eigenvalues[j]), 2pi) - 1.41) > 0.1]
    gather!("near collision diag(R(0.73), R(1.41), R(-0.73 - 1e-9)), partition x/z union $(sort(xz))", runmc(st3_near_collision_6d(1e-9); partition=[sort(xz), sort(setdiff(1:6, xz))]))
    for (name, M) in ex.defect; gather!(name, runmc(M); mp_accept=false); end
    # Exact-set multiplier: accepted = exactly degenerate m >= 2 clusters of 6D maps; rejected = the 1e-12 control's embedding.
    for (name, M) in vcat([ex.fodo6, ("diag(R(0.73), R(1.41), R(0.73))", st3_definite_pair_6d())], conj, [(n, r.matrix) for (n, r) in results if occursin("limit", n)])
        for c in runmc(M).clusters
            length(c.half_members) >= 2 && c.classification === :definite && (acc_e["$(name), cluster $(c.members)"] = c.internal_gap / c.rho_M1)
        end
    end
    for c in runmc(ex.fodo6_12[2]).clusters
        length(c.half_members) >= 2 && (rej_e["$(ex.fodo6_12[1]), cluster $(c.members)"] = c.internal_gap / c.rho_M1)
    end
    return (acc_g=acc_g, rej_g=rej_g, acc_m=acc_m, rej_m=rej_m, acc_s=acc_s, acc_e=acc_e, rej_e=rej_e)
end

function multiplier_section(io, results::Dict{String,Any})
    ex = extra_fixtures()
    rs = measure_real_stab(results, ex)
    gm = measure_gram_mp_sub_exact(results, ex)
    println(io, "\n## 2. PROVISIONAL multiplier windows (one tenth / ten rule)\n")
    println(io, "Fixture sets: the chord table's $(length(results)) fixtures plus the fixtures each docstring names (built in `extra_fixtures`, `measure_gram_mp_sub_exact`); every name printed from its row. Crosswise partitions are derived from the eigenvalue data (see `crosswise_partition`).\n")
    ws = Dict{String,Any}()
    ws["c_real"] = window_lines("c_real (_REAL_CLASS_MULTIPLIER)", "|Im rho_j| / (sqrt(rho_M1) max(1, ||M||_2)); accepted = real-class eigenvalues, rejected = complex-class eigenvalues",
                                rs.acc_r, rs.rej_r, Octopus._REAL_CLASS_MULTIPLIER)
    ws["c_stab"] = window_lines("c_stab (_STABILITY_MULTIPLIER)", "departure / (kappa_c max(rho_M1, (rho_M1 dep^(m-1))^(1/m))); accepted = max departure of every cluster of a stable fixture, rejected = min departure of the off-circle clusters",
                                rs.acc_s, rs.rej_s, Octopus._STABILITY_MULTIPLIER)
    ws["c_gram"] = window_lines("c_gram (_GRAM_FLOOR_MULTIPLIER)", "min |lambda(H)| / (rho_M1 / g_ext); accepted = every definite cluster (must exceed 10 c), rejected = single-copy halves of an exactly degenerate eigenspace under a crosswise partition (must stay below c / 10)",
                                gm.acc_g, gm.rej_g, Octopus._GRAM_FLOOR_MULTIPLIER; accepted_below=false)
    ws["c_mp"] = window_lines("c_mp (_MINIMAL_POLYNOMIAL_MULTIPLIER)", "r_mp / (max(rho_M1, g_int) ||P_c||_2 / ||M||_F); accepted = definite and indefinite groups m >= 2 (incl. explicit partitions of the split controls), rejected = the defective spectators",
                              gm.acc_m, gm.rej_m, Octopus._MINIMAL_POLYNOMIAL_MULTIPLIER)
    ws["c_sub"] = window_lines("c_sub (_SUBSPACE_RESIDUAL_MULTIPLIER)", "r_sub / (d eps); accepted = every cluster of every fixture; rejected = none reachable by a fixture (an ordered Schur basis is backward stable; the rejected side is an injected non-invariant basis, section 3)",
                               gm.acc_s, Dict{String,Float64}(), Octopus._SUBSPACE_RESIDUAL_MULTIPLIER)
    ws["exact_set"] = window_lines("exact-set multiplier (_EXACT_SET_MULTIPLIER)", "g_int / rho_M1; accepted = exactly degenerate definite m >= 2 clusters of 6D maps (FODO embedding, diag(R(0.73), R(1.41), R(0.73)) and 30 conjugations, the case-3 limit map), rejected = the 1e-12 control's 6D embedding",
                                   gm.acc_e, gm.rej_e, Octopus._EXACT_SET_MULTIPLIER)
    for k in ("c_real", "c_stab", "c_gram", "c_mp", "c_sub", "exact_set")
        foreach(l -> println(io, l), ws[k].lines)
    end
    println(io, "| multiplier | source | window low | window high | inside | accepted rows | rejected rows |")
    println(io, "|---|---|---|---|---|---|---|")
    for (k, cur) in (("c_real", Octopus._REAL_CLASS_MULTIPLIER), ("c_stab", Octopus._STABILITY_MULTIPLIER), ("c_gram", Octopus._GRAM_FLOOR_MULTIPLIER),
                     ("c_mp", Octopus._MINIMAL_POLYNOMIAL_MULTIPLIER), ("c_sub", Octopus._SUBSPACE_RESIDUAL_MULTIPLIER), ("exact_set", Octopus._EXACT_SET_MULTIPLIER))
        w = ws[k]
        println(io, "| $(k) | $(cur) | $(e2(w.lo)) | $(e2(w.hi)) | $(w.inside) | $(w.n_acc) | $(w.n_rej) |")
    end
    return ws
end

# --- section 4: the paper's mode_degeneracy.py on the same matrices ---------------
# Julia hands the matrices (shortest round-trip reprs) and the prototype's circle
# (center e^{+i mu} in ITS convention, pitfall 10) to paper_crosscheck.py, runs
# Python once, and compares the REAL outputs to `_mode_clusters` +
# `_dispersion_ambiguity_set` at 1e-12 absolute (the dossier's figure).
function paper_section(io, results::Dict{String,Any})
    pins = st3_fodo_pins(); mu = acos(pins.cos_mu)
    fodo = st3_rolled_fodo(pins.theta)
    jobs = Any[("rolled FODO exact (theta = pi/4)", fodo, exp(im * mu), 0.1),
               ("rolled FODO exact (+) R(1.1), 6D embedding", bd(fodo, R(1.1)), exp(im * mu), 0.1)]
    for r in load_case3(CASE3_TSV)
        if r.kind == "limit"
            push!(jobs, ("trial-015 case 3 $(r.kind) eps = $(r.epsilon)", r.M, exp(im * 0.73), 0.2))
        else
            # the endpoint's selected member: trial_015_verify.py `split_map` puts `v @ u` on rotation(MU + eps)
            # in BOTH endpoint maps (plus / minus name the spinor axis, not the eigenvalue), isolated by eps / 2
            push!(jobs, ("trial-015 case 3 $(r.kind) eps = $(r.epsilon)", r.M, exp(im * (0.73 + r.epsilon)), r.epsilon / 2, r.eta))
        end
    end
    src = joinpath(@__DIR__, "paper_input.tsv"); dst = joinpath(@__DIR__, "paper_output.tsv")
    open(src, "w") do f
        for j in jobs
            println(f, join(vcat([j[1], string(size(j[2], 1)), repr(real(j[3])), repr(imag(j[3])), repr(j[4])], [repr(x) for x in vec(permutedims(j[2]))]), '\t'))
        end
    end
    run(pipeline(`$(PYTHON) $(joinpath(@__DIR__, "paper_crosscheck.py")) $(src) $(dst)`; stdout=devnull))
    lines = readlines(dst)
    versions = lines[1]
    println(io, "\n## 4. Paper cross-check (mode_degeneracy.py analyze_cluster, real outputs, 1e-12 absolute)\n")
    println(io, versions[3:end] * "; Julia $(VERSION). Only real outputs are compared (pitfall 10: the prototype's frame is the conjugate of ours). Endpoint rows compare the isolated single mode's projector, covariance and the pz column eta = P[1:4, 6] / 2 against the dump's expected eta.\n")
    println(io, "| name | m (py) | m (jl) | Gram min py | Gram min jl | max|P diff| | max|G diff| | max|center diff| | max|shape diff| | max|eta - dump| | q of the row | ok |")
    println(io, "|---|---|---|---|---|---|---|---|---|---|---|---|")
    worst = 0.0; nrows = 0
    for l in lines[3:end]
        isempty(l) && continue
        f = split(l, '\t'); name = String(f[1]); mpy = parse(Int, f[2]); kmin_py = parse(Float64, f[3])
        j = jobs[findfirst(x -> x[1] == name, jobs)]; d = size(j[2], 1)
        Ppy = permutedims(reshape(parse.(Float64, f[4:3 + d * d]), d, d)); Gpy = permutedims(reshape(parse.(Float64, f[4 + d * d:3 + 2d * d]), d, d))
        cpy = parse.(Float64, f[4 + 2d * d:3 + 2d * d + (d - 2)]); Apy = permutedims(reshape(parse.(Float64, f[4 + 2d * d + (d - 2):end]), d - 2, d - 2))
        r = haskey(results, name) ? results[name] : runmc(j[2])
        # the Julia cluster whose oriented eigenvalues are the conjugates of the circle's content
        ci = findfirst(c -> c.classification === :definite && all(abs(conj(z) - j[3]) < j[4] for z in c.eigenvalues) &&
                            length(c.half_members) == mpy, r.clusters)
        c = r.clusters[ci]
        dP = maximum(abs, determined_value(c.projector) - Ppy); dG = maximum(abs, determined_value(c.covariance) - Gpy)
        dk = abs(minimum(c.gram_eigenvalues) - kmin_py)
        dc = NaN; dA = NaN; de = NaN
        if d == 6 && mpy >= 2
            set = Octopus._dispersion_ambiguity_set(c)
            dc = maximum(abs, set.center - cpy); dA = maximum(abs, set.shape - Apy)
        elseif d == 6 && mpy == 1 && length(j) == 5
            # a single (E3) mode's dispersion is the pz column itself (D12; test 3301); the /2 is the m >= 2 center (N11)
            eta = determined_value(c.projector)[1:4, 6]
            de = maximum(abs, eta - j[5]); dc = maximum(abs, eta / 2 - cpy)
        end
        # A singleton isolated from a pair split by eps carries the conditioning error kappa rho_M1 / eps on both
        # routes; its rows are judged against that scale (q of the row), the m >= 2 rows against 1e-12 absolute.
        qrow = mpy == 1 ? maximum(r.inter_cluster_chords[ci, :]) : 0.0
        vals = filter(!isnan, [dP, dG, dk, dc, dA, de]); wv = maximum(vals)
        ok = mpy >= 2 ? wv <= 1e-12 : wv <= max(1e-12, qrow)
        mpy >= 2 && (worst = max(worst, wv)); nrows += 1
        println(io, "| $(name) | $(mpy) | $(length(c.half_members)) | $(repr(kmin_py)) | $(repr(minimum(c.gram_eigenvalues))) | $(e2(dP)) | $(e2(dG)) | $(e2(dc)) | $(e2(dA)) | $(e2(de)) | $(e2(qrow)) | $(ok) |")
    end
    println(io, "\nRows: $(nrows); worst difference over the m >= 2 rows $(e2(worst)); all m >= 2 rows within 1e-12: $(worst <= 1e-12); singleton rows are judged against their own q (conditioning of a copy isolated from a split pair). Input $(src), output $(dst).")
    return worst
end

function main()
    fixtures = fixture_list()
    open(OUT_MD, "w") do io
        t = chord_table(io, fixtures)
        println("bracket [$(t.lo), $(t.hi)] gm $(t.gm) rounded $(t.rounded); lo at \"$(t.n_lo)\", hi at \"$(t.n_hi)\"")
        ws = multiplier_section(io, t.results)
        for (k, w) in ws; println("window $(k): [$(w.lo), $(w.hi)] inside $(w.inside)"); end
        worst = paper_section(io, t.results)
        println("paper cross-check worst difference $(worst)")
    end
    println("wrote $(OUT_MD)")
end
main()
```

`measure_stage3_tol.jl` (section 3: the rejected side of the 55 check families):

```julia
# Stage 3 measurement, section 3 (Part D1): the REJECTED side of every c eps kappa
# check family of the stage 3 testsets (test/runtests.jl, stage 3 block). For
# each family the wrong quantity a plausible defect produces (the quantity the
# check exists to catch) is formed on a fixture where the defect acts, and its
# residual is divided by the check's own threshold: the ratio must exceed ten
# (experiences 2026-09-11: "A rejected fixture must be one the defect can
# reach"). Fixture names travel with the rows. Package mode:
#   julia --startup-file=no --project=<tree> --threads=4 measure_stage3_tol.jl <out.md>
using Octopus, LinearAlgebra, Random, Printf
include(joinpath(@__DIR__, "..", "fixtures_stage3.jl"))
const OUT_MD = ARGS[1]
const EPS = eps(Float64)
const SEED = 20260911
e2(x) = x isa Real ? @sprintf("%.3e", x) : string(x)
dv = determined_value
bd(ms...) = cat(ms...; dims=(1, 2))
R(mu) = Octopus._rotation2(mu)
S4 = Octopus._symplectic_form(4); S6 = Octopus._symplectic_form(6)
rho0(M) = Octopus._perturbation_scale(M, Octopus._symplectic_defect(M).frobenius).scale
runmc(M; kw...) = Octopus._mode_clusters(M; rho_M0=rho0(M), kw...)
const ROWS = NamedTuple[]
# lines: the runtests.jl lines of the family; fixture: the row's own name; defect: the wrong quantity;
# residual / threshold: the check's tolerance with its c and kappa as the test states them.
function rec!(lines, fixture, defect, residual, threshold)
    push!(ROWS, (lines=lines, fixture=fixture, defect=defect, residual=residual, threshold=threshold, ratio=residual / threshold))
end

# --- fixtures ---------------------------------------------------------------------
pins = st3_fodo_pins(); mu0 = acos(pins.cos_mu)
fodo = st3_rolled_fodo(pins.theta); fodo_name = "rolled FODO exact (theta = pi/4)"
rng = MersenneTwister(SEED)
W6 = st3_random_symplectic(rng, 6, 0.2); W4 = st3_random_symplectic(rng, 4, 0.2)
pair6 = W6 * st3_definite_pair_6d() * inv(W6); pair6_name = "diag(R(0.73), R(1.41), R(0.73)) conjugated by W6 seed $(SEED)"
indef = st3_indefinite_6d(); indef_name = "diag(R(0.73), R(1.41), R(-0.73))"
defect = st3_defective_spectator(0.73); defect_name = "defective spectator (mu = 0.73)"
Wn = st3_random_symplectic(MersenneTwister(SEED + 7), 4, 0.3)
near = Wn * bd(R(0.9), R(0.9 + 1e-7)) * inv(Wn); near_name = "W R(0.9) (+) R(0.9 + 1e-7) W^-1, partition [[1,2,3,4]], chord Inf"

# --- family A: the exact FODO's definite m = 2 cluster (runtests 2644-2663) -----------
r = runmc(fodo); c = r.clusters[1]; kap = dv(c.kappa_frame); U = dv(c.frame); Q = c.schur_basis
Sig = -(fodo - pins.cos_mu * I) * S4 / sin(mu0)
P_Q = -imag(Q * Q') * S4                     # N5 applied to the UNNORMALIZED Schur basis (H^{-1/2} skipped)
G_Q = real(Q * Q')
rec!("2648", fodo_name, "P from the unnormalized Schur basis Q (H^-1/2 skipped): ||P_Q - I||", norm(P_Q - I), 128 * EPS * kap)
rec!("2650", fodo_name, "G from the unnormalized Schur basis: ||G_Q - Sigma_closed_form||", norm(G_Q - Sig), 256 * EPS * kap)
# Any orthonormal basis of an invariant subspace with unitary restricted map closes (M Q Q' M^T = Q T T' Q'), so a
# normalization defect is inert for N6; the defect N6 catches is a covariance of the WRONG map (a fixture mismatch).
G_3 = dv(runmc(st3_rolled_fodo(pins.theta; eps=1e-3)).clusters[1].covariance)   # the split control: two singletons, the first one
rec!("2652, 2866", fodo_name * " against the 1e-3 control's covariance", "N6 closure under the exact map of the SPLIT control's G: ||M G_3 M' - G_3||", norm(fodo * G_3 * fodo' - G_3), 64 * EPS * kap)
T_conj = (im / 2) * conj(U)' * S4 * fodo * conj(U)   # the restricted map of the CONJUGATE orientation
rec!("2654, 2877", fodo_name, "restricted map of the conjugate orientation: ||T_conj - e^{-i mu} I||", norm(T_conj - exp(-im * mu0) * I), 64 * EPS * kap)
T_Q = (im / 2) * Q' * S4 * fodo * Q
rec!("2655, 2875", fodo_name, "restricted map from Q (unnormalized): ||T_Q' T_Q - I||", norm(T_Q' * T_Q - I), 64 * EPS * kap)
tau_wrong = 2 * cos(2 * mu0)                  # the a07 injection: tau from the SUM of the tunes
Pc = dv(c.projector)
rec!("2656, 2878, 2905", fodo_name, "minimal-polynomial residual with tau = 2 cos(sum of tunes)", norm((fodo^2 - tau_wrong * fodo + I) * Pc) / norm(fodo)^2, 64 * EPS)
rec!("2659", fodo_name, "kappa_frame from 1 / max lambda instead of 1 / min lambda", abs(kap - 1 / maximum(c.gram_eigenvalues)), 64 * EPS * kap)
J2 = [0.0 1.0; -1.0 0.0]; adj(K) = -J2 * K' * J2
disc(M) = (tr(M[1:2, 1:2]) - tr(M[3:4, 3:4]))^2 + 4det(adj(M[1:2, 3:4]) + M[3:4, 1:2])
f3 = st3_rolled_fodo(pins.theta; eps=1e-3)
rec!("2663", "rolled FODO detuned eps = 0.001", "(T7) discriminant of the SPLIT control (equal tunes assumed)", abs(disc(f3)), 64 * EPS * opnorm(f3)^2)
rec!("2737, 2829, 2900, 2903, 3453, 3648, 3720", fodo_name, "normalization of the CONJUGATE vector: |conj(u)' S conj(u) + 2i|", abs(dot(conj(U[:, 1]), S4 * conj(U[:, 1])) + 2im), 64 * EPS * kap)
rec!("2742, 2770, 2858", fodo_name, "N4 first relation on Q (unnormalized): ||Q' S Q + 2i I||", norm(Q' * S4 * Q + 2im * I), 64 * EPS * kap)
Uc = hcat(U[:, 1], conj(U[:, 1]))              # a conjugate partner as second column (Part B's injection)
rec!("2771, 2859", fodo_name, "isotropy with a conjugate partner as second column: ||U^T S U||", norm(transpose(Uc) * S4 * Uc), 64 * EPS * kap)
rec!("2739, 2906, 2973, 3005", fodo_name, "tune of the conjugate eigenvalue: |(2 pi - mu) - mu|", abs((2pi - mu0) - mu0), 16 * EPS)
rec!("2725, 2941", fodo_name, "13.8 reconstruction check with the frame's columns assigned the CONJUGATE eigenvalues", Octopus._column_eigenvector_residual(fodo, U, conj.(c.eigenvalues)), 64 * EPS * kap)

# --- family B: a coupled definite m = 2 cluster in 6D (runtests 2808-2879, 3149-3150) -----
r6 = runmc(pair6); c6 = r6.clusters[findfirst(c -> length(c.half_members) == 2, r6.clusters)]
kap6 = dv(c6.kappa_frame); U6 = dv(c6.frame); Q6 = c6.schur_basis; P6 = dv(c6.projector); G6 = dv(c6.covariance)
PQQ = 2 * real(Q6 * Q6')                       # the a05 injection: the Schur spectral projector taken as Q Q'
rec!("2808, 2861, 2872, 3252", pair6_name, "Schur projector taken as 2 Re(Q Q') (a05): ||P_QQ - P_N5||", norm(PQQ - P6), 64 * EPS * kap6 * norm(P6))
rec!("2862", pair6_name, "idempotency of 2 Re(Q Q')", norm(PQQ * PQQ - PQQ), 64 * EPS * kap6 * norm(P6))
rec!("2817, 2863", pair6_name, "commutation of Re(Q Q') with M", norm(pair6 * real(Q6 * Q6') - real(Q6 * Q6') * pair6), 64 * EPS * kap6 * norm(pair6) * norm(P6))
rec!("2864", pair6_name, "symplectic adjointness of Re(Q Q'): ||P^T S - S P||", norm(transpose(real(Q6 * Q6')) * S6 - S6 * real(Q6 * Q6')), 64 * EPS * kap6 * norm(P6))
# Re(Q Q') has its range inside the cluster's real invariant subspace whatever the normalization (P G_Q = G_Q holds),
# so the defect that acts is a covariance of ANOTHER cluster (the y singleton's) paired with this P.
G_y = dv(r6.clusters[findfirst(c -> length(c.half_members) == 1, r6.clusters)].covariance)
rec!("2868", pair6_name, "P G = G with the y singleton's covariance paired with the pair's P", norm(P6 * G_y - G_y), 64 * EPS * kap6 * norm(G_y))
rec!("2814", pair6_name, "PSD of Re(U U^T) (transpose instead of adjoint): -min eigenvalue", -minimum(eigvals(Symmetric(real(U6 * transpose(U6))))), 64 * EPS * kap6)
rec!("2818, 2937, 2938, 3076, 3514", pair6_name, "kappa from the Frobenius norm squared instead of the 2-norm squared", abs(norm(U6)^2 - kap6), 64 * EPS * kap6)
rec!("2873", pair6_name, "covariance without the real part's partner: ||Re(U U^T) - G||", norm(real(U6 * transpose(U6)) - G6), 64 * EPS * kap6 * norm(G6))
rec!("2879", pair6_name, "tunes of the conjugate half", maximum(abs.((2pi .- c6.tunes) .- 0.73)), 64 * EPS * kap6 * norm(pair6))
# scaling (3149-3150): compare the SCALED projector directly, skipping `_unscale_projector`
rec_sc = Octopus._reciprocal_scaling(pair6, (3.0, 0.2, 7.0)); C = Octopus._scaling_matrix(rec_sc); Ms = C * pair6 * inv(C)
rs6 = runmc(Ms); cs6 = rs6.clusters[findfirst(c -> length(c.half_members) == 2, rs6.clusters)]
kk = max(kap6, dv(cs6.kappa_frame)) * opnorm(C) * opnorm(inv(C))
rec!("3149", pair6_name * ", reciprocal scaling (3, 0.2, 7)", "scaled P compared WITHOUT _unscale_projector", norm(dv(cs6.projector) - P6), 64 * EPS * kk * norm(P6))
rec!("3150", pair6_name * ", reciprocal scaling (3, 0.2, 7)", "scaled G compared WITHOUT _unscale_covariance", norm(dv(cs6.covariance) - G6), 64 * EPS * kk * norm(G6))

# --- family C: the indefinite fixture (2894-2906, 3730, 3738) --------------------------
ri = runmc(indef); ci = ri.clusters[findfirst(c -> c.classification === :indefinite, ri.clusters)]
Wi = dv(ci.signed_basis); Qi = ci.schur_basis; Hi = Hermitian((im / 2) * Qi' * S6 * Qi)
rec!("2894, 3730, 3738", indef_name, "Gram without the factor 1/2: | |lambda| - 1/2 |", maximum(abs.(abs.(eigvals(Hermitian(im * Qi' * S6 * Qi))) .- 0.5)), 16 * EPS)
Wu = hcat(Wi[:, 1], conj(Wi[:, 2]))            # the negative-sign column NOT conjugated
rec!("2900", indef_name, "signed basis with the negative column unconjugated: ||W' S W + 2i I||", norm(Wu' * S6 * Wu + 2im * I), 64 * EPS)
Pi_signed = -imag(Wu * Wu') * S6              # N5 on the signed basis WITHOUT conjugating the negative column: P_+ - P_-
rec!("2904, 2966", indef_name, "N5 formula on the unconjugated signed basis: ||-Im(W_u W_u') S - P||", norm(Pi_signed - dv(ci.projector)), 64 * EPS)
# --- family D: the defective spectator (2954-2966) --------------------------------------
rd = runmc(defect); cd_ = rd.clusters[1]
Jd_wrong = [R(0.73) 0.2 * R(0.73); zeros(2, 2) R(0.73)]   # the interleaving permutation forgotten
rec!("2954, 2985, 3091, 3567, 3632, 3784, 3796, 3826", defect_name, "fixture built without the interleaving permutation: ||J' S J - S||", norm(Jd_wrong' * S4 * Jd_wrong - S4), 16 * EPS)
hyp = bd([1 + 1e-6 0; 0 1 / (1 + 1e-6)], R(1.2))
rec!("2961, 3800", "diag(1 + 1e-6, 1/(1 + 1e-6)) (+) R(1.2)", "unit-circle departures of the hyperbolic pair against sqrt(eps)", 1e-6, sqrt(EPS))
rec!("2963", defect_name, "departure from normality of the FULL block (both halves) instead of the half block", abs(sqrt(max(0.0, norm(cd_.full_block)^2 - sum(abs2, eigvals(cd_.full_block)))) - 0.2), 64 * EPS)
# --- family E: the coupled 1e-7 pair under partition + Inf (2770-2774) --------------------
rn = runmc(near; partition=[[1, 2, 3, 4]], resolution_chord=Inf); cn = rn.clusters[1]; Un = dv(cn.frame); kn = dv(cn.kappa_frame)
modes = dv(cn.modes)
rec!("2738, 2757, 2774, 2827, 3365", near_name, "(I1) eigenvector residual with the two modes' eigenvalues SWAPPED", maximum(Octopus._invariance_residual(near, modes[1].vector, modes[2].eigenvalue).normalized for _ in 1:1), 64 * EPS * kn)
rec!("2773", near_name, "normalization of a mode vector scaled by (1 + 1e-6)", abs(dot((1 + 1e-6) * modes[1].vector, S4 * ((1 + 1e-6) * modes[1].vector)) + 2im), 64 * EPS * kn)
# --- family F: kernel pins (2947, 3184, 3192, 3207) ---------------------------------------
r12 = runmc(st3_rolled_fodo(pins.theta; eps=1e-12))
rec!("2947", "rolled FODO detuned eps = 1.0e-12", "receipt gap of the SPLIT control against the exact-degeneracy pin 16 eps", r12.resolution_receipt[1].gap, 16 * EPS)
spec = Octopus._canonical_spectrum(fodo); sel = falses(4); sel[spec.order[1]] = true
rec!("3184, 3207", fodo_name, "backward error measured against a matrix perturbed by 1e-8 (fBE2)", Octopus._ordered_schur_basis(spec.schur, sel, fodo + 1e-8 * I).backward_error, 64 * EPS * opnorm(fodo))
rec!("3192", "_chord(2, 1e-15, 1e-9)", "chord without the factor 2: |kappa rho / g - 4e-6|", abs(2.0 * 1e-15 / 1e-9 - 4e-6), 4 * EPS * 4e-6)

# --- family G: the ambiguity set on the coupled definite pair (3248-3302, 3319-3401, 3422-3442, 3659-3674) ----
set6 = Octopus._dispersion_ambiguity_set(c6); A6 = set6.shape; F6 = set6.factor
rec!("3262, 3345, 3390, 3425, 3659", pair6_name, "center from the z column P[1:4, 5] / 2 instead of the pz column P[1:4, 6] / 2", norm(P6[1:4, 5] / 2 - set6.center), 16 * EPS * kap6)
A_no4 = G6[5, 5] * G6[1:4, 1:4] - G6[1:4, 5] * transpose(G6[5, 1:4])
rec!("3263, 3346, 3358", pair6_name, "shape without the 1/4", norm(A_no4 - A6), 16 * EPS * kap6^2)
lam6, V6 = eigen(Symmetric(A6)); F_wrong = V6 * Diagonal(lam6)   # F = V Lambda instead of V sqrt(Lambda), zero columns kept
rec!("3265, 3285, 3319, 3348, 3391, 3660", pair6_name, "factor F = V Lambda (sqrt forgotten): ||F F^T - A||", norm(F_wrong * transpose(F_wrong) - A6), 16 * EPS * max(1.0, kap6^2))
a = normalize(randn(MersenneTwister(SEED + 3), 4))
lo, hi = dispersion_interval(set6, a)
mid = dot(a, set6.center)
rec!("3269, 3271, 3380, 3381, 3442, 3673, 3674", pair6_name, "interval endpoints replaced by the midpoint (the rejected alternative): |mid - hi|", abs(mid - hi), 64 * EPS * kap6 * norm(a))
hi_nosqrt = mid + dot(a, A6 * a)
rec!("3380, 3381", pair6_name, "N14 endpoint with the shape's quadratic form unrooted: |hi_nosqrt - hi|", abs(hi_nosqrt - hi), 64 * EPS * kap6 * norm(a))
cvec = normalize(randn(MersenneTwister(SEED + 4), 2) + im * randn(MersenneTwister(SEED + 5), 2))
u = U6 * cvec
eta_d12 = Octopus._sampled_mode_dispersion(U6, cvec)
eta_re = [real(conj(u[5]) * u[k]) for k in 1:4]      # (D12) with Re instead of -Im
rec!("3291-3302, 3462, 3463, 3722", pair6_name, "(D12) readout with Re(conj(u_z) u_a) instead of -Im", norm(eta_re - eta_d12), 16 * EPS)
Ap = pinv(A6; rtol=1e-10)
dev = eta_d12 - set6.center
rec!("3368, 3435", pair6_name, "ellipsoid membership of a member scaled by 1.1 (||c|| != 1)", abs(dot(1.1 * dev, Ap * (1.1 * dev)) - 1), 2048 * EPS * kap6)
rec!("3312, 3313, 3369", pair6_name, "A A^+ dev = dev with A^+ replaced by inv(A + I) (rank ignored)", norm(A6 * (inv(A6 + I) * dev) - dev), 256 * EPS * kap6^2)
Um = U6 * [1.0 0.0; 0.0 2.0]                          # a NON-unitary column scaling instead of a unitary mixing
refused_mix = try; Octopus._dispersion_ambiguity_set(Um; kind=:exact_set); false; catch e; e isa ArgumentError; end
rec!("3357", pair6_name, "frame with a column scaled by 2 (non-unitary mixing): the (N4) guard's normalization residual (set constructor refuses it: $(refused_mix))", norm(Um' * S6 * Um + 2im * I), 64 * EPS * 2 * max(1.0, opnorm(Um)^2))
center_T = transpose(P6)[1:4, 6] / 2                  # P^T instead of P in the (P, G) method
refused_T = try; Octopus._dispersion_ambiguity_set(Matrix(transpose(P6)), G6, 2; kind=:exact_set); false; catch e; e isa ArgumentError; end
rec!("3394, 3395", pair6_name, "(P, G) method with P^T instead of P: center shift (method refuses P^T: $(refused_T))", norm(center_T - set6.center), 64 * EPS * kap6)
Us = hcat(U6[:, 1] * (1 + 1e-6), U6[:, 2])
refused_s = try; Octopus._check_cluster_frame(Us); false; catch e; e isa ArgumentError; end
rec!("3255-3257, 3339, 3340, 3821", pair6_name, "(N4) normalization residual of a column scaled by 1 + 1e-6 against one tenth of the refusal (the checker refuses it: $(refused_s))", norm(Us' * S6 * Us + 2im * I), 64 * EPS * 2 * kap6 / 10)
rec!("3323, 3399-3406", pair6_name, "Bloch readout with the spinor sign flipped: ||F n - F (-n)||", 2 * norm(F6 * [1.0, 0.0, 0.0]), 64 * EPS * kap6)
# --- family H: the isospectral family and the N15 / N16 controls (3636-3707, 3719-3723, 3758-3790) --------------
fam = st3_isospectral_family(MersenneTwister(SEED + 9), 1e-7)
rec!("3636-3652, 3707", "isospectral family seed $(SEED + 9), eps = 1e-7", "SAME spinor at both endpoints (Part B's injection): |diameter_wrong - 2 sigma_1|", abs(0.0 - fam.diameter), 64 * EPS * opnorm(fam.W)^2)
t = 0.4; uN = st3_n15_vector(t)
rec!("3719", indef_name, "N15 vector against the CONJUGATE eigenvalue e^{-i mu}", norm(indef * uN - exp(-im * 0.73) * uN), 64 * EPS * norm(uN)^2)
rec!("3722, 3723", indef_name, "N15 eta_x with the sign flipped: |+sinh t cosh t - (-sinh t cosh t)|", 2 * sinh(t) * cosh(t), 64 * EPS * norm(uN)^2)
Mdp = bd(R(0.73), R(1.41), R(0.73)); poly = Mdp * Mdp - 2cos(0.73) * Mdp + I
poly_wrong = Mdp * Mdp - 2cos(1.0) * Mdp + I            # a polynomial of a tune NOT in the spectrum (2 cos 1.41 would annihilate the y block: inert)
rec!("3758", "diag(R(0.73), R(1.41), R(0.73))", "(N16) determinant of the polynomial block with a tune outside the spectrum (1.0)", abs(det(poly_wrong[1:4, 1:4])), 64 * EPS * max(1.0, opnorm(poly_wrong))^4)
rec!("3764, 3790", "diag(R(0.73), R(1.41), R(0.73)), graph residual pin", "(D14) residual expected with |1 - t| instead of |2 - t| at t = 0.3", abs(sqrt(2) * sin(0.73) * abs(1 - 0.3) - sqrt(2) * sin(0.73) * abs(2 - 0.3)), 64 * EPS * sqrt(2) * sin(0.73) * 1.7)
k = 0.3; Ck = Matrix{Float64}(I, 6, 6); Ck[2, 5] = -k; Ck[6, 1] = -k; Mk = Ck * Mdp / Ck; polyk = Mk * Mk - 2cos(0.73) * Mk + I
D_solve = -(polyk[1:4, 1:4] + 1e-13 * I) \ polyk[1:4, 5:6]    # a regularized solve instead of the minimum-norm pseudoinverse
rec!("3788", "crab map k = 0.3 on diag(R(0.73), R(1.41), R(0.73))", "graph from a regularized solve instead of pinv: ||D||", norm(D_solve), 64 * EPS * opnorm(polyk))
# --- family I: the exact-degeneracy pins on the 6D FODO embedding (3574, 3588, 3589) -----------------------------
fodo6 = bd(fodo, R(1.1)); r66 = runmc(fodo6); c66 = r66.clusters[findfirst(c -> length(c.half_members) == 2, r66.clusters)]
rec!("3574", "rolled FODO exact (+) R(1.1), 6D embedding", "P of the betatron cluster compared with I_6 (the whole space) instead of diag(I_4, 0)", norm(dv(c66.projector) - I), 128 * EPS * dv(c66.kappa_frame))
# The pin 'the betatron cluster has no pz column' is a structural zero of the block-diagonal embedding; on the
# COUPLED embedding W6 (FODO (+) R(1.1)) W6^-1 the betatron cluster carries dispersion, which is what the pin would catch.
fodo6c = W6 * fodo6 * inv(W6); r66c = runmc(fodo6c); c66c = r66c.clusters[findfirst(c -> length(c.half_members) == 2, r66c.clusters)]
rec!("3588, 3589", "W6 (rolled FODO exact (+) R(1.1)) W6^-1, seed $(SEED)", "center of the betatron cluster of the COUPLED embedding (nonzero dispersion) against the block-diagonal zero pin", norm(dv(c66c.projector)[1:4, 6] / 2), 64 * EPS * dv(c66c.kappa_frame))

# --- table ------------------------------------------------------------------------------
open(OUT_MD, "w") do io
    println(io, "\n## 3. Rejected side of the c eps kappa check families (stage 3 block of test/runtests.jl)\n")
    println(io, "Julia $(VERSION); seed $(SEED). ratio = wrong-quantity residual / the check's threshold; every ratio must exceed 10. Rows whose fixture gives the defect nothing to act on are stated as such in section 3a of the report.\n")
    println(io, "| runtests lines | fixture | wrong quantity (the defect) | residual | threshold | ratio | > 10 |")
    println(io, "|---|---|---|---|---|---|---|")
    for x in ROWS
        println(io, "| $(x.lines) | $(x.fixture) | $(replace(x.defect, "|" => "\\|")) | $(e2(x.residual)) | $(e2(x.threshold)) | $(e2(x.ratio)) | $(x.ratio > 10) |")   # pipes inside a cell are escaped for the markdown table
    end
    bad = [x for x in ROWS if !(x.ratio > 10)]
    println(io, "\nRows: $(length(ROWS)); below ten: $(length(bad))" * (isempty(bad) ? "" : " -> " * join(["$(x.lines) ($(e2(x.ratio)))" for x in bad], "; ")) * ".")
end
println("wrote $(OUT_MD) with $(length(ROWS)) rows; below ten: $(count(x -> !(x.ratio > 10), ROWS))")
```

`paper_crosscheck.py` (the prototype's `analyze_cluster` on the maps the driver writes to `paper_input.tsv`; real outputs only):

```python
"""Part D1 cross-check: run the paper's mode_degeneracy.analyze_cluster once on the
matrices Julia hands over and dump its REAL outputs (pitfall 10: the prototype
uses e^{+i mu}, +2i; only projector, covariance, center, shape and the Gram
minimum are comparable).

Input TSV (from measure_stage3.jl): name, d, center_re, center_im, radius, then
d*d row-major entries. Output TSV: name, multiplicity, krein_minimum, then the
d*d projector, the d*d covariance, the 4 center entries and the 16 shape entries
(center and shape are the prototype's z = d - 2 readout; for d = 4 they are
NOT dispersion quantities and Julia ignores them). The header records versions.
"""
import platform
import sys

import numpy as np
import scipy

sys.path.insert(0, '/cfs/ad/dxu/Paper/2026_twiss_dispersion/research')
import mode_degeneracy as md  # noqa: E402

src, dst = sys.argv[1], sys.argv[2]
rows = []
for line in open(src):
    if not line.strip() or line.startswith('#'):
        continue
    f = line.rstrip('\n').split('\t')
    name, d = f[0], int(f[1])
    center = complex(float(f[2]), float(f[3]))
    radius = float(f[4])
    mat = np.array([float(x) for x in f[5:5 + d * d]]).reshape(d, d)
    res = md.analyze_cluster(mat, center, radius)
    out = [name, str(res['multiplicity']), repr(res['krein_minimum'])]
    out += [repr(x) for x in res['projector'].ravel()]
    out += [repr(x) for x in res['covariance'].ravel()]
    out += [repr(x) for x in np.asarray(res['center']).ravel()]
    out += [repr(x) for x in np.asarray(res['shape']).ravel()]
    rows.append('\t'.join(out))
with open(dst, 'w') as fh:
    fh.write('# python %s numpy %s scipy %s; mode_degeneracy.py from %s\n' % (
        platform.python_version(), np.__version__, scipy.__version__, md.__file__))
    fh.write('# columns: name, multiplicity, krein_minimum, projector (d*d), covariance (d*d), center (d-2), shape ((d-2)^2)\n')
    fh.write('\n'.join(rows) + '\n')
print('wrote', dst, len(rows), 'rows')
```
