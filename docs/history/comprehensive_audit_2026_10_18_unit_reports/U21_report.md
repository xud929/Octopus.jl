# U21: analysis/: the analysis object, Determined, one-turn matrix

Reading unit of the comprehensive audit 2026-10-18 (protocol `docs/comprehensive_audit.md`; common
brief `result/comprehensive_audit_2026_10_18/plan/BRIEF_COMMON.md`; unit brief `plan/U21.md`).
Tree under audit: `/cfs/ad/dxu/Library/Julia/Octopus` at commit 24e8683, read-only. Every claim
below is a LEAD, not a finding. Julia 1.12.4, four threads, CUDA present but not exercised (nothing
in this region is CUDA-reachable).

## Region

| File | Lines read |
|---|---|
| `src/analysis/twiss_dispersion_analysis.jl` | 1-1658 (all) |
| `src/analysis/twiss_dispersion_type.jl` | 1-91 (all) |
| `src/analysis/Analysis.jl` | 1-333 (all) |
| `src/analysis/one_turn_matrix.jl` | 1-401 (all) |

Total 2483 lines, every line read. Hypotheses briefed: (1) every option of `TwissDispersionAnalysis`
is read at its consumer; (2) Determined/ambiguity semantics -- no spurious unique value, physical
fields unscaled while `separation` is scaled; (3) linearization provenance -- complex step, finite
difference and ForwardDiff agree; the closed-orbit fixed-point check and its `:require`/`:warn` modes.

## Provenance

READ line by line: the four region files in full (ranges above). Reference material read for
comparison: `docs/design/twiss_dispersion_analysis.md` lines 20-44 (the frozen-body paragraph),
102-470 (Input boundary, Types and availability, Execution API and option certification, Pipeline,
return table, Resolution criterion), 570-628; `docs/theory/twiss_dispersion.md` 2160-2188 (11.2) and
2416-2432 (13.5); `docs/public_api.md` 530-620. Out-of-region definitions read only to resolve seams
the region calls into: `symplectic_linear_algebra.jl` (`_unscale_*` 295-343, `_perturbation_scale`
431-), `dispersion_routes.jl` (`_kappa_route` 103-150, the coasting branch 1337-1355, `canonical_area`
at 407), `canonical_separation.jl` 330-370 (the K5/K7 tolerances), `mode_clusters.jl` 812-831
(partition validation), `eigenmodes_4d.jl` 317-334 (`_frame_availability`), the tune convention
`mod(-angle(rho), 2pi)` at `mode_clusters.jl` 1201/1310/1370 and `eigenmodes_4d.jl` 413,
`src/contracts/analysis_effectiveness.jl` 14-160, `src/policies/Policies.jl` 85-200, and the suite
pins the leads touch (`test/runtests.jl` 1037-1066, 4666, 5815, 6357-6358, 6629-6634, 6765-6790,
7250-7282, 7356).

EXECUTED (scratch `result/comprehensive_audit_2026_10_18/probes/U21/`, logs `probe_[a-f].log`; each
run is `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 <script>`; probe A additionally
puts the ForwardDiff-only environment `probes/U21/fdenv` on `JULIA_LOAD_PATH` so the
`OctopusForwardDiffExt` extension activates without touching the project):

- `probe_a_linearization.jl` (hypothesis 3). DBA ring (`examples/twiss_dispersion_dba_ring.jl`
  layout, RF 0.02): complex step vs ForwardDiff `||J - J_cs||_F = 2.97e-15`, tunes agree to
  1.3e-15; finite difference at the default step 3e-7 `||J - J_cs||_F = 1.66e-12`, declared
  uncertainty 7.89e-13 (declared/actual 0.47); at 1e-5 `1.85e-9` vs declared 8.77e-10 (0.47); spec
  input and tuple-of-runtime-maps input give bitwise-equal Jacobians; an FD `LinearizedMap` without
  `symplectic_rtol` is an `ArgumentError`; FODO + sextupole linearized at `x = 0, 1e-14, 1e-13, 1e-12,
  1e-9, 1e-3`: accepted, accepted (scaled residual 7.72e-15 against atol 1.42e-14, ratio 35),
  refused, refused, refused, refused under `:require`; `:warn` on two different displaced maps in
  one process: both results `:degraded` with the degradation string, ONE warning emitted
  (`maxlog=1` with a fixed `_id`); receipt `:analysis_closed_orbit -> (closed_orbit = :warn,
  closed_orbit_atol = nothing, residual = 7.726e-4, action = :warned)`; bare matrix: no
  closed-orbit receipt, both options `:inactive_dependency`.
- `probe_b_options.jl` (hypotheses 1, 2). `validate(AnalysisOptionEffectivenessContract())`:
  passed in 50.1 s, "19 probes, 16 inactive entries applied, 32 receipts checked, 15 moved, 4
  fixed", `stale_exemptions = 0`. Per-option hand probes on the DBA ring: scaling `:auto` vs `:none`
  leaves every physical field equal to <= 2.6e-15 relative (tunes 4.1e-16, beta 9.0e-16, alpha
  2.3e-15, gamma 2.6e-15, zeta 1.7e-15, eta 1.2e-15, h 2.2e-16, graph 2.1e-15, Sigma 1.0e-20
  absolute, Edwards-Teng R 1.5e-16) while `separation.eta` (scaled) differs from `physical.eta` by
  0.32 under `:auto` and 0.0 under `:none`; `physical.covariance == matched_covariance(result,
  em)` exactly; `preferred_form = 2` on the uncoupled ring reports form 0 with reason
  `:form_inadmissible` (area weight -8e-46); `dispersion_routes = (:eigenplane,)` leaves one
  diagnostics row and `newton_max_iterations` inactive; `newton_max_iterations = 1` gives the Newton
  row `(:not_invariant, 1 iteration, converged = false)` with receipt `used = 1`; explicit
  `clusters` equal to the automatic partition reproduces the result with `partition_source =
  :explicit`; `resolution_chord = Inf` forces nothing on this ring (all resolved); `map_uncertainty
  = 1e-9` sets `rho_M0 = 1e-9` under both scalings; `symplectic_rtol = 1e-20` throws under
  `:error` and degrades under `:flag`; a 1e-6-perturbed matrix is `:failed` (K5 separation) and
  `strict = true` throws `OpticsAnalysisError` carrying it; constructor: `nonsymplectic = "flag"`,
  `closed_orbit = 1`, `newton_max_iterations = 2.0` raise `TypeError`, `strict = 1` an
  `ArgumentError`, `emittances = (true, 1.0, 1.0)` is ACCEPTED.
- `probe_c_conventions.jl` (crashed at a print of the symmetric FODO's normalizer, which is
  legitimately `:cluster_unresolved` because that cell has exactly equal betatron tunes; its first
  lines measured the coasting `canonical_area`) and `probe_e_followup.jl` (its rerun plus follow-ups):
  coasting FODO maps report `diagnostics.projection.canonical_area = 0.0` while
  `1 + zeta' S4 (eta/h) = 1.0`; the bunched DBA ring reports 0.96921 = `1 + zeta' S4 (eta/h)`
  (`zeta' S4 (eta/h) = -0.03079`); `longitudinal_mode = tunes[3] = 6.00915` is rejected by the
  constructor, `2pi - tunes[3] = 0.27404` certifies canonical index 1 with chords (1.06e-15,
  1.159); theory-13.6 family `diag(R(0.7), R(1.3), R(0.7))` with explicit scaling (2, 0.5, 3):
  `physical.eta` is an `:exact_set` of multiplicity 2, unscaled shape and center match
  `A = C_r^-1 / a_3` applied to the scaled set to 0.0, `dispersion_interval(e_x)` = (-0.5, 0.5)
  physical vs (-3, 3) scaled, `determined_value`, `normal_mode`, `matched_covariance` all throw
  `UndeterminedQuantityError(:cluster_unresolved)`; eight `Determined`/`AmbiguitySet` guard probes
  all throw as documented; a hand-built 4x4 `LinearizedMap` dies with `DimensionMismatch`.
- `probe_d_uncertainty_scaling.jl`: for `map_uncertainty = 1e-9`, `rho_M0 = 1e-9` under `:auto` and
  `:none`; the per-entry gain `C_ii / C_jj` of the reciprocal scaling spans [1.6e-2, 63] on the DBA
  ring (factors (0.654, 0.126, 0.882)) and [6.9e-4, 1.46e3] on an uncoupled toy with beta = (1000,
  100, 200) m; Frobenius gain over 500 random perturbations [2.2, 28.8] (DBA) and [39.9, 726]
  (toy); FD provenance: declared 7.89e-13, raw `||J_fd - J_cs||_F` 1.66e-12, scaled `||C dJ C^-1||_F`
  5.43e-13.
- `probe_f_clusters.jl`: `diag(R(0.7), R(0.7), R(0.05))` (equal betatron tunes, isolated
  longitudinal pair): one six-member `:definite, unresolved` cluster, `physical.eta` an `:exact_set`
  of multiplicity 3, resolution receipt chords all 2.0 including `([1,6],[3,5], 2.0)` (the
  longitudinal pair against a betatron pair whose eigenvalue gap is 0.64); the same under a
  symplectic similarity `W = exp(S6 H)`; detuning the second betatron tune by 1e-9, 1e-6, 1e-3, 1e-1
  resolves all three pairs (chords <= 8.3e-15) and `eta` is unique; the contract's own `repeated`
  fixture `W diag(R(0.72), R(0.72), R(-1.3)) W^-1` keeps the longitudinal pair separate (merge order
  `([1,6],[2,5])` first, then `([1,2,5,6],[3,4], 1.2e-14)`) and reports a unique eta; Newton on the
  equal-tune map: row `(:cluster_unresolved, 0 iterations, converged = true)`, receipt `used = 0`,
  configuration `newton_max_iterations :resolved`; stable coasting FODO cells (kd = -1.4, -1.5):
  4x4 normalizer, two tunes, beta equal to the Courant-Snyder values of the 2x2 blocks to all
  printed digits (5.274966 / 4.959831; 5.629644 / 3.921468), auto-vs-none differences <= 4.1e-15.

## Leads

### LEAD U21-1 [Moderate, confidence med] src/analysis/twiss_dispersion_analysis.jl:1563
Claim: `map_uncertainty` (schema: "a declared absolute error of the matrix entries") and the provenance's `map_uncertainty` (`step^2 ||J||_F` of the RAW Jacobian) are folded into `rho_M0` of the SCALED matrix unchanged, although a raw entry error `dM` becomes `C dM C^-1` whose entries are amplified or shrunk by `C_ii / C_jj`, measured between 1.6e-2 and 63 on the DBA ring and between 6.9e-4 and 1.46e3 at beta = 1000 m.
Mechanism: `_analyze_matrix` computes `rho_M0 = _perturbation_scale(Ms, defect.frobenius; user_uncertainty=analysis.map_uncertainty, provenance_uncertainty=input.provenance.map_uncertainty)` on `Ms = C M C^-1`; `_perturbation_scale` takes `max(defect*||Ms||, d eps ||Ms||_2, user, provenance)` with the two declared arms as plain numbers, so a declaration made in the caller's coordinates (the only ones the schema, the type docstring and the design table name) is compared with scaled residuals without the conjugation; the result is identical under `scaling = :auto` and `:none` (`rho_M0 = 1e-9` in both runs) while the scaled perturbation it stands for differs by up to the entry gain. Neither the option schema (line 391-393), the type docstring (twiss_dispersion_type.jl:43) nor the design's "Input boundary" item 5 states the coordinates the uncertainty is declared in. Class 9 (one quantity, two conventions across layers).
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U21/probe_d_uncertainty_scaling.jl` -> "DBA ring: ... per-entry gain in [1.59e-02, 6.29e+01] | rho_M0(auto, u=1e-9)=1.000e-09"; the toy row "beta=(1000,100,200): rho_M0 auto=1.000e-09 none=1.000e-09 ... per-entry gain C_ii/C_jj in [6.87e-04, 1.46e+03]". Inline: `r = analyze(TwissDispersionAnalysis(map_uncertainty=1e-9, strict=false), M); C = Octopus._scaling_matrix(r.scaling); maximum(C[i,i]/C[j,j] for i in 1:6, j in 1:6)` against `r.rho_M0 == 1e-9`.

### LEAD U21-2 [Moderate, confidence high] src/analysis/twiss_dispersion_analysis.jl:1567
Claim: (Cross-file seam into mode_clusters.jl, out of hypothesis.) On a 6x6 map whose two betatron tunes are exactly equal while the synchrotron pair is isolated (theory 13.5 row 1, design return-table row "definite betatron cluster, longitudinal pair isolated: dispersion unique"), the analysis absorbs the longitudinal pair into one six-member cluster and reports `eta` as an ambiguity set of multiplicity 3 with `zeta`, `h`, separation and transverse optics unavailable, i.e. a unique quantity is reported as a set.
Mechanism: `_analysis_clusters` hands the matrix to `_mode_clusters`; its agglomeration evaluates every candidate union by `q = min(2, 2 kappa rho_M1 / g)` and, for a member of an exactly repeated pair that is "not orientable alone", `kappa` is infinite (history, "Agglomeration": "else Inf"), so EVERY candidate involving such a pair gets the capped chord 2.0 regardless of its eigenvalue gap (the receipt shows `([1,6],[3,5], 2.0)` for a gap of 0.64); which candidate merges first is then decided by order among ties. When the longitudinal pair sorts first (tune 0.05 < 0.7 in `mod(angle, 2pi)` order) it is merged into a betatron pair before the two betatron pairs are merged with each other, after which the remaining lone betatron pair is again "not orientable alone" and joins, leaving one cluster that contains the longitudinal candidate. The contract's `repeated` fixture happens to merge the two repeated pairs first and keeps `eta` unique, which is why the suite rows "design row 3: the dispersion is unique" (test/runtests.jl:4666, 5815, 6868) pass. Any detuning >= 1e-9 restores three resolved pairs. The driver (this region) then correctly follows its blocked-triple branch (:1196-1206); the defect is the clustering's tie-breaking, in `mode_clusters.jl` -- noted as a seam, not pursued further.
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U21/probe_f_clusters.jl` -> first block "clusters=[([1, 2, 3, 4, 5, 6], :definite, 0)] ... eta=Determined{Vector{Float64}}(:ambiguous_set, :cluster_unresolved, multiplicity=3, :exact_set)" and "resolution receipt: [([1, 6], [2, 4], 2.0), ([1, 6], [3, 5], 2.0), ([2, 4], [3, 5], 2.0), ([1, 2, 4, 6], [3, 5], 2.0)]"; the "detuned by 1.0e-9" block gives `eta=Determined([0.0, 0.0, 0.0, 0.0])`. Inline: `R(t)=[cos(t) sin(t); -sin(t) cos(t)]; M=cat(R(0.7),R(0.7),R(0.05); dims=(1,2)); analyze(TwissDispersionAnalysis(strict=false), M).physical.eta.status` -> `:ambiguous_set` (expected `:unique`).

### LEAD U21-3 [Minor, confidence high] src/analysis/twiss_dispersion_analysis.jl:1442
Claim: The projection diagnostic's fallback canonical area is `dot(zeta, S4 * (eta/h))` while the kernel defines `canonical_area = 1 + D[:,1]' S4 D[:,2]` (dispersion_routes.jl:407; `DETERMINATION_REASONS` `:graph_isotropic` names the same `1 + ...`), so on every coasting map `diagnostics.projection.canonical_area` reads 0.0 where the kernel convention gives 1.0.
Mechanism: `_analysis_diagnostics` uses the primary route's `canonical_area` when it is determined and otherwise recomputes from the separation; the coasting branch of `_dispersion_routes` (dispersion_routes.jl:1346-1355) marks every route `:coasting_structure` with `canonical_area` unavailable while supplying the determined triple `(0, eta, 1)`, so the fallback is reached on every coasting map and differs from the kernel's definition by exactly 1. Nothing is judged on this value (the kernel judges isotropy on its own number), so the effect is a wrong diagnostic, not a wrong verdict; no suite pin covers the coasting projection row (test/runtests.jl:6776 pins the bunched run only). Class 9.
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U21/probe_e_followup.jl` -> "symmetric FODO kq=1.6: ... projection diagnostic canonical_area=0.0 | kernel convention 1 + zeta'S4(eta/h) = 1.0" (also the asymmetric FODO row); the bunched row shows "projection canonical_area=0.9692138861413988  1+zeta'S4(eta/h)=0.9692138861413988", i.e. the `1 +` convention is the one the primary route uses.

### LEAD U21-4 [Minor, confidence high] src/analysis/twiss_dispersion_analysis.jl:1426
Claim: `diagnostics.routes` rows for a route that never ran carry `normalized_residual = 0.0`, `raw_residual = 0.0`, `coefficient_condition = 0.0` and `converged = true`, numbers standing in for "unavailable" in a record whose design says "no field is ever a NaN standing in for unknown" and whose docstring says `converged` is `false` for an iterative route that stopped short.
Mechanism: lines 1426-1427 substitute `(normalized=0.0, raw=0.0)` and `0.0` when `r.invariance_residual` / `r.coefficient_condition` are not determined, and `r.converged` is passed through from a route object that was never iterated (its default `true`); a reader filtering rows by residual or by `converged` cannot distinguish "ran and matched to zero" (which the uncoupled fixtures genuinely produce) from "did not run". The `status` column is the only discriminator. Class 6/hypothesis 2 (a spurious value where none exists).
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U21/probe_e_followup.jl` -> the "degenerate family" block prints `(:newton, :cluster_unresolved, 0.0, 0.0, 0.0, 0, true)` and `(:fixed_point, :cluster_unresolved, 0.0, 0.0, 0.0, 0, true)`; the equal-tune block prints `(:polynomial, :none, 0.0, 0.0, 38.48, 0, true)` beside `(:eigenplane, :cluster_unresolved, 0.0, 0.0, 0.0, 0, true)`, the genuine and the placeholder zero side by side.

### LEAD U21-5 [Minor, confidence high] src/analysis/twiss_dispersion_analysis.jl:1424
Claim: On a coasting map the `:analysis_dispersion_routes` receipt says `executed = ()` and no route runs, yet `diagnostics.routes` lists all five routes (status `:coasting_structure`, zero residuals), contradicting the `AnalysisDiagnostics` docstring "one row per executed dispersion route".
Mechanism: `_analysis_6d` (line 1171) defines executed routes as "not coasting and status !== :route_not_selected", while `_analysis_diagnostics` (line 1425) filters only on `status !== :route_not_selected`; two walkers over `dispersion.routes` disagree on what "executed" means (class 3), and the coasting rows then also carry the U21-4 placeholders.
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U21/probe_e_followup.jl` -> "symmetric FODO kq=1.6: ... diagnostics.routes rows=[(:eigenplane, :coasting_structure, 0.0, 0.0, 0.0), ...] ... (5 rows)"; `probe_c.log` shows the receipt side on the same map class via the contract's `coasting` form; inline: `r = analyze(TwissDispersionAnalysis(strict=false), one_turn_matrix(fodo)); length(r.diagnostics.routes)` -> 5 while `with_execution_audit` records `executed = ()`.

### LEAD U21-6 [Minor, confidence high] src/analysis/twiss_dispersion_analysis.jl:326
Claim: The `Float64` form of `longitudinal_mode` is confined to `(0, pi)` while every tune the result reports is `mod(-angle(rho), 2pi)` in `[0, 2pi)`, so the analysis's own synchrotron tune (6.00915 rad on the DBA ring, whose oriented eigenvalue has positive imaginary part) is rejected by the constructor and the user must know to pass `2pi - tunes[3]`, which no docstring states.
Mechanism: the constructor (line 326) and the type docstring (twiss_dispersion_type.jl:55) demand `0 < mu_s < pi`; `_analysis_6d` matches `exp(-i mu_s)` to the nearest eigenvalue and the kernel maps either conjugate member to the same oriented mode, so widening the domain to `(0, 2pi)` would select the same mode (the probe shows `2pi - 6.00915 = 0.27404` certifies index 1 with chord 1.06e-15); the restriction is a validation choice inconsistent with the result's tune convention (`NormalMode`/`PhysicalOptics` docstrings say only "mu in radians per turn"). Class 9.
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U21/probe_e_followup.jl` -> "synchrotron mode: physical.tunes[3]=6.009149255548609 ... imag>0: true" then "longitudinal_mode=tunes[3]=6.009... -> ArgumentError: ... must lie in (0, pi)" and "longitudinal_mode=2pi - tunes[3]=0.27403605163097744 -> status=passed certified=true selected=1".

### LEAD U21-7 [Minor, confidence high] src/analysis/twiss_dispersion_analysis.jl:923
Claim: When `closed_orbit_atol === nothing` the tolerance the closed-orbit check actually applied (`64 eps max(1, max|C point|)`) is recorded nowhere a reader can recover it -- the receipt echoes `closed_orbit_atol = nothing`, `result.closed_orbit` holds the residual only, and no `(name, value, tolerance)` triple for the closed orbit is in `diagnostics.residuals` -- so an ACCEPTED check cannot be recomputed from the result and the receipt does not carry what the branch read.
Mechanism: line 923 resolves the default into the local `atol`; the receipt at 937-939 records `closed_orbit_atol=analysis.closed_orbit_atol` (the request) and `residual`, not `atol`; only the `:warn` degradation string (935) and the `:require` error message (929-931) interpolate the effective value. The design's receipt shape for this consumer is `(mode, atol, residual)`. The schema text (line 389) and the multiplier docstring (line 198) also give the default as `eps * max(1, max|point|)` without the scaling `C` the code applies. Class 11 (assert what the run recorded).
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U21/probe_a_linearization.jl` -> "receipt :analysis_closed_orbit -> (closed_orbit = :warn, closed_orbit_atol = nothing, residual = 0.0007726060821129292, action = :warned)"; `probe_e.log` "bunched DBA residual names" lists seven names, none for the closed orbit.

### LEAD U21-8 [Minor, confidence high] src/analysis/twiss_dispersion_analysis.jl:1171
Claim: On a bunched map whose longitudinal cluster is blocked, the Newton route is counted as executed (status `:cluster_unresolved`, 0 iterations), so `:analysis_newton` records `used = 0` and the configuration report marks `newton_max_iterations` `:resolved` although no iteration ever read the cap.
Mechanism: `executed = Tuple(r.route for r in routes.routes if r.status !== :route_not_selected)` treats every selected route as executed whatever its status; `newton_executed = :newton in executed` then drives both the receipt (1175-1178) and `_analysis_configuration` (1523). The schema says the cap is "inactive unless :newton is among the executed routes"; a route that returned before iterating did not consume the option. Class 11/5.
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U21/probe_f_clusters.jl` -> "newton config: [(:newton_max_iterations, :resolved, \"\")] newton row: [(:newton, :cluster_unresolved, 0, 1)]" and "receipts newton/routes: ... (:analysis_newton, (newton_max_iterations = 50, used = 0))".

### LEAD U21-9 [Minor, confidence high] src/analysis/twiss_dispersion_analysis.jl:1652
Claim: `analyze(::TwissDispersionAnalysis, lm::LinearizedMap)` hardcodes `dimension = 6`, and `LinearizedMap` has no size check, so a hand-built 4x4 `LinearizedMap` fails with a `DimensionMismatch` inside `_analysis_closed_orbit` (a 4x4 `C` times a 6-vector) instead of a directed `ArgumentError`, and would otherwise carry `input.dimension = 6` beside a 4x4 matrix.
Mechanism: `_ANALYSIS_INPUT_T((:linearized, 6, lm.provenance))` at 1652 ignores `size(lm.matrix)`; `_analyze_matrix` derives `d` from the matrix, so the two disagree; `one_turn_matrix` always produces 6x6 so the path is reachable only by constructing the (documented runtime-representation) struct directly. Loud, so low impact. Out of hypothesis.
Repro: `R(t)=[cos(t) sin(t); -sin(t) cos(t)]; M4=cat(R(0.7),R(1.3); dims=(1,2)); lm=one_turn_matrix(compile_runtime(DriftSpec(L=1.0))); analyze(TwissDispersionAnalysis(strict=false), LinearizedMap(M4, lm.provenance))` -> `DimensionMismatch: ... matrix of size (4, 4) with a vector of length 6` (probe_e.log, "4x4 LinearizedMap").

### LEAD U21-10 [Minor, confidence high] src/analysis/twiss_dispersion_analysis.jl:288
Claim: Four docstring or comment statements in the region describe behaviour or numbers the code or the evidence does not have: (a) line 288 "every rejected keyword is an ArgumentError naming it" while `nonsymplectic`, `closed_orbit` and `newton_max_iterations` are typed keywords whose mismatches raise `TypeError`, and a `Bool` is accepted as an emittance (`emittances = (true, 1.0, 1.0)`) and as any `_analysis_number`; (b) line 28, `ANALYSIS_STATUSES` degrades for "an uncertified longitudinal selection that could not be cross-checked" while the code degrades EVERY uncertified selection with no cross-check (1167; the suite's "Stage 9 follow-up" testset pins the message as unconditional); (c) lines 198 and 389 give the default closed-orbit tolerance as `eps * max(1, max|point|)` while line 923 scales the point by `C`; (d) one_turn_matrix.jl:58 quotes "the matrix error is 2.1e3 times the declared value at step 3e-7" from a 2026-09-11 FODO measurement with no committed harness (the string occurs only in that docstring), and the same ratio on the DBA ring measures 2.1.
Mechanism: statements copied from an earlier stage and not re-derived from the code (class 14; for (d) class 13/14, a number without a harness). None affects a verdict.
Repro: (a) `TwissDispersionAnalysis(nonsymplectic="flag")` -> `TypeError`; `TwissDispersionAnalysis(emittances=(true,1.0,1.0))` -> accepted (probe_b.log, "constructor" lines); (b) `grep -n "could not be cross-checked" src/analysis/twiss_dispersion_analysis.jl` against `grep -n "uncertified longitudinal selection" src/analysis/twiss_dispersion_analysis.jl`; (c) `grep -n "max(1, max|point|)" src/analysis/twiss_dispersion_analysis.jl` against the `C * collect(Float64, prov.point)` expression in `_analysis_closed_orbit`; (d) `grep -rn "2.1e3" docs validation test src` -> only `src/analysis/one_turn_matrix.jl`; probe_a.log "fd default declared/actual(|J-Jcs|) = 0.4747" (actual/declared 2.1).

## Clean

Checked and found sound, with the evidence.

Hypothesis 1 (every option reaches its consumer):
- The repository's own instrument, `validate(AnalysisOptionEffectivenessContract())`, passed on this tree: 19 probes, 16 inactive entries applied, 32 receipts checked, 15 observables moved, 4 fixed, 0 stale exemptions (probe_b.log, 50.1 s).
- `_ANALYSIS_CONSUMERS` lists ten consumers; the file records exactly those ten (`_record_execution!` at lines 847, 894, 937, 958, 1027, 1162, 1172, 1177, 1241/1247/1251, 1487), each receipt keyed by the option's own name as the docstring at 256-262 promises.
- Hand probes, option by option, each showed the documented observable (Provenance, probe B): scaling (physical fields invariant to <= 2.6e-15, `matrix_scaled` differs), symplectic_rtol and nonsymplectic (throw vs `:degraded`, rule `:frobenius`), closed_orbit and closed_orbit_atol (refuse / warn / explicit atol = 1.0 accepts, probe A), map_uncertainty (`rho_M0` moves to the declared value), resolution_chord (receipt `chord = Inf`; forced flags on the contract's `repeated` fixture, probe F), clusters (`partition_source = :explicit`; an explicit union re-resolves on both the 4x4 and the 6x6 path, `_frame_availability` returning `nothing` on both), longitudinal_mode (Int, its conjugate partner, and a tune in `(0, pi)` all certify the same mode; `:max_signed_z_area` degrades), preferred_form (1 presented, 2 reported inadmissible with its reason), dispersion_routes (row count and the Newton cap's inactivity follow the tuple), newton_max_iterations (`used = 1`, `converged = false` at cap 1), emittances (`physical.covariance == matched_covariance` exactly; `:not_requested` and `:inactive_dependency` when `nothing`; a 2-tuple on 6x6 is an `ArgumentError`), strict (`OpticsAnalysisError` carrying the `:failed` result vs the result returned; receipt `(strict, outcome)`).
- Inactivity predicates of `_analysis_configuration` match the branches taken: bare matrix -> closed-orbit pair inactive and no closed-orbit receipt; 4x4 -> longitudinal_mode, dispersion_routes, newton, closed_orbit, emittances inactive with receipts `[scaling, symplectic_check, cluster_resolution, edwards_teng, strictness]`; coasting -> longitudinal_mode, dispersion_routes, newton inactive, preferred_form resolved (probe_e.log, probe_f.log).
- Partition validation at the consumer (mode_clusters.jl 812-831) rejects incomplete, out-of-range and non-conjugation-closed partitions loudly (probe_b.log), complementing the constructor's uniqueness check.

Hypothesis 2 (Determined semantics; scaled vs physical):
- `Determined`/`AmbiguitySet` are consistent by construction: `Determined{Float64}(:none)`, `Determined{T}(set, :none)`, `Determined(nothing)`, an `AmbiguitySet` of multiplicity 1 or with an asymmetric shape all throw `ArgumentError`; `determined_value` on unavailable, `ambiguity_set` and `dispersion_interval` on unique throw `UndeterminedQuantityError` (probe_e.log, eight probes).
- On the theory-13.6 family `diag(R(0.7), R(1.3), R(0.7))`: `physical.eta` is an `:exact_set` of multiplicity 2 with `zeta`, `h`, separation and transverse optics unavailable under `:cluster_unresolved`, exactly the design's return-table row 2; `normal_mode`, `matched_covariance` and `determined_value` throw with that reason; the result is `:degraded` with the "primary dispersion unavailable" string.
- The unscaling of an ambiguity set is linear and consistent: with explicit scaling (2, 0.5, 3) the physical set's center and shape equal `A center` and `A shape A'` for `A = C_r^-1 / a_3` to 0.0, and `dispersion_interval(e_x)` = (-0.5, 0.5) physical vs (-3, 3) scaled, the ratio 1/6 = (1/2)/3 (probe_e.log). `_unscale_longitudinal_factor` returns `h` unchanged, matching the design table "h unchanged (det C_l = 1)"; `physical.h == separation.h`.
- `result.separation` is in scaled coordinates and `physical.*` in the caller's: on the DBA ring `||sep.eta - physical.eta|| = 0.32` under `:auto` and 0 under `:none`; every physical field is invariant between the two scalings to <= 2.6e-15 relative (tunes, beta, alpha, gamma, zeta, eta, h, graph, Sigma, Edwards-Teng R), and on stable coasting FODO cells (the `rec4` back-transform row, lines 1313-1324) to <= 4.1e-15 with beta equal to the Courant-Snyder values of the 2x2 blocks to all printed digits (probe_f.log).
- `_analysis_verdict` treats a non-finite residual as a failure (`isfinite(value) && value <= tolerance`), so a NaN cannot pass.

Hypothesis 3 (linearization provenance; closed orbit):
- Complex step, ForwardDiff (package mode through the extension, `_forward_diff_linearization_available() == true`) and finite differences agree on the DBA ring: CS vs ForwardDiff `||dJ||_F = 2.97e-15`, tunes to 1.3e-15; CS vs FD `1.66e-12` at step 3e-7 and `1.85e-9` at 1e-5, both of order `step^2`, with the declared uncertainty 0.47 of the actual matrix error in both cases (so the docstring's qualitative claim "sits below the actual error" holds here; the quoted 2.1e3 does not, see U21-10 d). Spec input and tuple-of-runtime-maps input give bitwise-equal Jacobians (the design's "one Jacobian rule" promise). `InexactError` has fields `(:func, :args)` on this Julia, as the comment at one_turn_matrix.jl:292-296 asserts.
- An FD `LinearizedMap` without `symplectic_rtol` is refused with the directed message; with `1e-6` the rule is `:frobenius`, and `rho_M0 = 7.89e-13` is the provenance arm (arms printed in probe_a.log).
- Closed orbit: the FODO + sextupole boundary reproduces the `_CLOSED_ORBIT_ATOL_MULTIPLIER` docstring (x = 1e-14 accepted at ratio 35, x = 1e-13 and above refused under `:require`); `:warn` returns `:degraded` with the degradation string and the receipt `action = :warned`; `closed_orbit_atol = 1.0` accepts x = 1e-3 with the residual recorded (7.726e-4, scaled). The warning is emitted once per PROCESS (`maxlog=1` with a fixed `_id`): two analyses of different displaced maps produced one warning; the second result still carries its degradation, which is the design's "one rate-limited warning", noted here so a reader does not expect one warning per call.

Seams checked at their definitions (not audited further): `_kappa_route` has the `Determined{Float64}` method line 1434 relies on; the K5 tolerance formula in `_analysis_diagnostics` (1389-1390) is identical to the kernel's (`canonical_separation.jl:363-364`); the K7 row carries the kernel's own tolerance as its comment says; `_unscale_crab_dispersion`, `_unscale_momentum_dispersion`, `_unscale_graph` are the design table's rows; `partition_source` takes `:auto`/`:explicit` as the 4x4 branch at 982 assumes.

Design-versus-code: the design note states (lines 34-38) that its body is frozen and that the amendments the implementation forced are recorded in the campaign history; the receipt field names, the `resolution_chord`/`dispersion_routes` inactivity amendments and the `clusters` receipt value are indeed in the history's F-series (history lines 6366-6540), so those differences are drift by policy, not leads. The one pipeline-order deviation (the coasting test inside `_dispersion_routes`) is documented in the driver's docstring (1545-1553).

Observations recorded, not leads (by-design behaviour a reader may not expect): a coasting or 4x4 map whose betatron cluster is definite but degenerate returns `:passed` with every Twiss quantity unavailable under `:cluster_unresolved` (the symmetric FODO cell: equal tunes), because only `:indefinite`/`:unresolved` classifications and an unavailable primary dispersion are degradations (1574, 1203-1206) -- consistent with the design's return table, which names a degraded status for the indefinite row only; requesting an inadmissible Edwards-Teng form (`preferred_form = 2` on an uncoupled ring) yields `:passed` with `physical.edwards_teng_R` unavailable `:form_inadmissible` and the receipt `reported = 0`. Style only: the detail string at 1157 indexes the z-area weights (one per mode) by the cluster number.

## Unchecked

- The complex-step relabelling guard (`_differentiation_limit`, `_involves_method_number`) was read, not executed on a map that compares a coordinate against a threshold (a strong-beam evaluator); its logic and the `InexactError` layout were checked, the directed error text was not exercised.
- ForwardDiff was exercised in package mode only (secondary environment on `JULIA_LOAD_PATH`); the script-mode include route named in the `ForwardDiffLinearization` docstring was not run.
- The `_FRAME_ACCEPTANCE_MULTIPLIER`, `_NORMALIZER_ACCEPTANCE_MULTIPLIER` and `_COVARIANCE_ACCEPTANCE_MULTIPLIER` windows quoted in their docstrings (stage 4b D1 tables) were not re-measured; only one failing fixture (the 1e-6-perturbed DBA matrix, failing through K5) and passing fixtures were run, so the covariance-closure and (K14) rows were seen passing, never failing.
- An explicit partition that is definite-but-unresolved on the 6x6 path (where the 4x4-only `_frame_availability` guard at 982-984 has no counterpart) was not constructed; both paths were compared on a resolvable union only.
- A coupled map on which Edwards-Teng form 2 is admissible was not run, so the `preferred_form` presentation difference between forms 1 and 2 was not observed (form 2 is inadmissible on the uncoupled ring).
- The FD docstring's FODO measurement (2.1e3 at 3e-7, 0.84 at 1e-5) could not be reproduced because its expansion point and cell are not recorded; the DBA ring was measured instead (U21-10 d).
- Thread-count invariance and allocation behaviour of `analyze` were not measured (not in the unit's hypotheses; the region has no worker closures).
- Line numbers in the LEAD headers are those of commit 24e8683; the Repro lines are the durable identity.
