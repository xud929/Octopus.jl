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
