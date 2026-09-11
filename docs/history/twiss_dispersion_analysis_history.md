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
