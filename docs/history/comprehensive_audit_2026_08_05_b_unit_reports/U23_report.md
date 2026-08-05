# U23 Report — validation/ PIC + Gaussian-subtracted + near-round + spectral field cluster

Repo: `/cfs/ad/dxu/Library/Julia/Octopus`. **HEAD at audit time = `c55d2e0`** (the brief
said `7de4d81`; two audit commits, `84db01b` and `c55d2e0`, landed on top before this unit
started — noted so a later reader can date the measurements).

Read-only audit. **No repository file was modified** (`git status --porcelain` empty at
start and at end of this unit). All probes ran against a pristine `git archive HEAD`
snapshot in session scratch (`scratchpad/audit/repo/`), so a *concurrent* uncommitted edit
by another audit agent to `src/tasks/strongstrong/interface.jl`, observed mid-session and
since gone, could not contaminate any measurement. All script `result/` output landed in
the snapshot, never in the working tree.

Julia 1.12.4, `--threads=4`, CPU + a functional CUDA device (RTX 4500 Ada, **shared with
~19 other agents** — the wall-clock numbers below are indicative only; every physics number
is deterministic and shared-load-independent).

## Region (every line read)

| file | lines |
|---|---:|
| `validation/pic_gaussian_field_validation.jl` | 430 |
| `validation/near_round_gaussian_transition.jl` | 412 |
| `validation/gaussian_pic_zscan.jl` | 363 |
| `validation/spectral_poisson_field_validation.jl` | 300 |
| `validation/gaussian_pic_bigaussian_validation.jl` | 196 |
| `validation/gaussian_pic_field_validation.jl` | 167 |
| `validation/pic_gaussian_luminosity_validation.jl` | 158 |
| `validation/pic_grid_extent_stability.jl` | 157 |

(2183 lines total, `wc -l` at `c55d2e0` — matches the brief exactly.)

Also read for cross-checking (not part of the region, seams only): `AGENTS.md` §Hard-Won
Rules/§Updating Validations, `docs/comprehensive_audit.md` §Measured Lessons,
`docs/history/comprehensive_audit_2026_08_05_unit_reports/U20_report.md`,
`validation/README.md` §§14-29/52-160/306-322/536-563/708-740,
`docs/theory/gaussian_subtracted_pic_solver.md` §9,
`docs/theory/near_round_bassetti_erskine_switch.md` §§10-11,
`docs/theory/spectral_sine_poisson_solver.md` §§15-16, `docs/todo.md` item 4a,
`paper/README.md`, `src/tasks/strongstrong/pic_cpu.jl`,
`src/tasks/strongstrong/interface.jl`, `src/elements/strong_beam.jl`,
`test/runtests.jl` testsets at 461, 5945, 5985, 6368, 6512, 8666.

`git diff 6a3f39ab HEAD -- validation/` touches exactly one region file:
`gaussian_pic_bigaussian_validation.jl` (header output line, closing U20-3). Six caveat
paragraphs were added to `validation/README.md` for region scripts. Everything else in the
region is byte-identical to the state U20 audited, so U20's open leads were re-verified at
HEAD rather than assumed.

---

## (a) Reference-provenance table — what every comparison is measured against

| # | script | subject under test | reference | class | independent? |
|---|---|---|---|---|---|
| 1 | `pic_gaussian_field_validation` | **production** `_pic_solve_field` + `_pic_interaction_grids` + `_pic_interpolate_kick` | `gaussian_beambeam_kick` | closed-form analytic (Bassetti-Erskine / Faddeeva) | **YES** |
| 2 | `near_round_gaussian_transition` sweep | **production** `_gaussian_beambeam_kick_response` | script-local 96-point Gauss-Legendre quadrature of the fixed-interval Gaussian integral | independent numerical quadrature, *different algorithm*, no shared code | **YES** (but hand-copied, see U23-13) |
| 3 | `near_round` core gradients | `gaussian_beambeam_kick` | `2/(σ₁(σ₁+σ₂))` | closed form | **YES** |
| 4 | `near_round` symplecticity | `ThinStrongBeam` 6D map | `JᵀSJ = S` | structural identity | **YES** |
| 5 | `near_round` CUDA parity | `_cuda_gaussian_beambeam_kick_response` | `_gaussian_beambeam_kick_response` | same-algorithm cross-backend | **NO — and correctly labelled "parity"**, not accuracy |
| 6 | `near_round` endpoint continuity | evaluator vs itself across the branch switch | one-sided extrapolations | self-consistency | **NO — correct construction for a continuity claim** |
| 7 | `gaussian_pic_zscan` | **production** `_gpic_solve_drifted_field!`, `_gpic_source_moments`, `_gpic_drifted_gaussian`, `_pic_solve_drifted_field_with_green_fft!` | each scheme's *own* solve at the exact drift σ(z) | deliberate self-reference to isolate the longitudinal reconstruction; stated in the header | **NO, by design and disclosed** |
| 8 | `spectral_poisson_field_validation`, 3 spectral rows | **script-local** `spectral_onmesh_field` / `spectral_specderiv_field` / `spectral_grid_field` / `spectral_free_field` | `gaussian_beambeam_kick` | closed form | reference YES; **subject is a local reimplementation — production `SpectralPoissonSolver` is never constructed** |
| 9 | `spectral…`, `pic` row | **production** `_pic_solve_field` | `gaussian_beambeam_kick` | closed form | **YES** |
| 10 | `gaussian_pic_bigaussian_validation` | local hybrid (`PICPoissonSolver` pieces + local `cic_profile` + BE at *empirical* moments) | superposition of **two** `gaussian_beambeam_kick` fields | closed form; genuinely ≠ the single BE the hybrid adds back | reference YES; subject is a local reimplementation of `GaussianPICPoissonSolver` |
| 11 | `gaussian_pic_field_validation`, **PIC** column | local `solve_from_charge` (production `_pic_green_fft` + `_pic_deposit!` + `_pic_field`, hand-wired FFT) | `gaussian_beambeam_kick` | closed form | reference YES; subject local |
| 12 | `gaussian_pic_field_validation`, **HYBRID** column | local hybrid | **the identical `gaussian_beambeam_kick` call that is also the hybrid's analytic add-back** | — | **NO — CIRCULAR. See U23-2.** |
| 13 | `pic_gaussian_luminosity_validation`, `relative_error` column | `_pic_deposit!` grid quadrature | closed-form Gaussian overlap | closed form | **YES** — but PRINT-ONLY |
| 14 | `pic_gaussian_luminosity_validation`, **the one enforced gate** | **production** `_pic_luminosity` | script-local `deposited_overlap` | **local reimplementation of the thing under test, and it has DRIFTED** | **NO. See U23-1.** |
| 15 | `pic_grid_extent_stability` | production `_pic_axis_extent` | none — "There is no analytic reference" (honest); metric is box relative variation | — | n/a; its `dropped` column is a *local* count that no longer matches production's |

**Named circular cases: #12 (proved algebraically and measured) and #14 (a copy that has
since diverged from the original).** #5, #6 and #7 are self-referential by construction and
each is correctly labelled as such in its own header. #8 and #10/#11 are the
"local reimplementation, independent reference" pattern U20 named; the reference is sound,
the *subject* is not the production object the header names.

---

## (b) Instrument validation — feeding each metric a known defect

All injections ran on scratch copies; no repository file was touched.

### b1. `gaussian_pic_field_validation.jl` — the hybrid column cannot see an error in its own reference

Probe: `scratchpad/audit/probe_gpic_instrument.jl` (replicates `run_case` verbatim, round
case, grid 128, CIC). Two injection modes: `:be` = the Bassetti-Erskine evaluator itself is
wrong by (1+δ), so *both* the reference and the hybrid's add-back are wrong; `:ref` = only
the comparison reference is wrong.

| injection | PIC med | PIC max | **HYB med** | HYB max |
|---|---:|---:|---:|---:|
| none (baseline) | 4.5850e-04 | 3.9095e-03 | **1.7468e-04** | 3.9263e-03 |
| BE evaluator ×(1+1e-6) | 4.5931e-04 | 3.9088e-03 | **1.7468e-04** | 3.9263e-03 |
| BE evaluator ×(1+1e-4) | 4.7908e-04 | 3.8384e-03 | **1.7467e-04** | 3.9259e-03 |
| BE evaluator ×(1+1e-2) | 6.4427e-03 | 1.2593e-02 | **1.7295e-04** | 3.8875e-03 |
| **BE evaluator ×2 (100 % wrong)** | **3.3339e-01** | 5.0124e-01 | **8.7342e-05** | 1.9632e-03 |
| reference only ×(1+1e-6) | 4.5931e-04 | 3.9088e-03 | 1.7460e-04 | 3.9256e-03 |
| reference only ×(1+1e-4) | 4.7908e-04 | 3.8384e-03 | 1.3786e-04 | 3.8550e-03 |
| reference only ×(1+1e-2) | 6.4427e-03 | 1.2593e-02 | 6.1732e-03 | 1.0465e-02 |

A **100 % error in the Bassetti-Erskine evaluator makes the reported hybrid error two times
BETTER** (1.7468e-04 → 8.7342e-05 = exactly half). Exactly half, because the metric
reduces algebraically to `|2·deX/ns| / max|K_exact|` and only the normalisation moves.

### b2. `pic_gaussian_field_validation.jl` — a working instrument

Probe: `scratchpad/audit/probe_metrics_instrument.jl`, round case, reduced
(160×160 source, 61 field axis, grid 128; baseline median 8.7968e-04).

| injection | median | ratio to baseline |
|---|---:|---:|
| reference ×(1+1e-6) | 8.7933e-04 | 1.00 (below the metric's own floor) |
| reference ×(1+1e-4) | 8.9952e-04 | 1.02 |
| reference ×(1+1e-3) | 1.0415e-03 | 1.18 |
| reference ×(1+1e-2) | 5.5962e-03 | 6.4 |
| evaluation mesh shifted 0.01 cell | 9.1333e-04 | 1.04 |
| evaluation mesh shifted 0.1 cell | 1.7034e-03 | 1.9 |
| **evaluation mesh shifted 1 cell** | **1.2328e-02** | **14.0** |

Verdict: sound instrument, with a stated detection floor — being an *absolute*-difference
metric normalised by max|K|, its sensitivity floor is its own baseline error (~1e-4 relative
here), so it reports a 1e-3 reference error but not a 1e-6 one.

### b3. `spectral_poisson_field_validation.jl` — `shape_relerr` is exactly blind to normalisation, *including sign*

| "solver output" fed to `shape_relerr` | median | p95 | max |
|---|---:|---:|---:|
| 1.0 × exact reference | 0.000e+00 | 0.000e+00 | 0.000e+00 |
| (1+1e-6) × exact | 0.000e+00 | 1.274e-16 | 1.424e-16 |
| **2.0 × exact** | **0.000e+00** | 0.000e+00 | 0.000e+00 |
| **0.5 × exact** | **0.000e+00** | 0.000e+00 | 0.000e+00 |
| **−1.0 × exact (field inverted)** | **0.000e+00** | 0.000e+00 | 0.000e+00 |

And with a genuinely shape-wrong solver, scaling the *reference* by (1+d) leaves the metric
bit-identical for d = 1e-6, 1e-2 and **1.0**: 6.112342e-03 / 1.053454e-02 / 1.313443e-02 in
all four runs. A solver that returns an attractive field where the physics is repulsive
scores a perfect zero.

This is a *known, mitigated* blindness — `test/runtests.jl` testset **"Spectral field
absolute normalization is derived, not fitted"** exists precisely because of it and says so
in its own comment. Recorded here with the measured magnitude, not as a new defect.

### b4. `near_round_gaussian_transition.jl` — the accuracy metric works; the *coverage* does not

Probe: `scratchpad/audit/probe_nearround_instrument.jl` (script's exact η/q/angle grid).

**A. Reference scaled by (1+d)** — the metric reports d faithfully, three decades below the
recorded magnitude:

| d | max force rel. error | max response rel. error |
|---:|---:|---:|
| 0 (baseline) | 6.1096e-12 | 1.2449e-08 |
| 1e-9 | 1.0045e-09 | 1.2372e-08 |
| 1e-6 | 1.0000e-06 | 1.0009e-06 |
| 1e-3 | 9.9900e-04 | 9.9900e-04 |

**B. Defect confined to the blend interior** (Float64 blend η ∈ [2.206060e-04, 4.412119e-04],
`t` = normalised position in the blend):

| injected band | amplitude | sweep max force rel. | inner continuity gap | outer continuity gap |
|---|---:|---:|---:|---:|
| — (baseline) | — | 6.1096e-12 | 9.446e-13 | 6.735e-09 |
| t ∈ [0.30, 0.40] | **1e-3** | **6.1096e-12** (unchanged) | 9.446e-13 | 6.735e-09 |
| t ∈ [0.30, 0.40] | **1e-1 (10 %)** | **6.1096e-12** (unchanged) | 9.446e-13 | 6.735e-09 |
| t ∈ [0.05, 0.95] | 1e-3 | 1.0000e-03 (caught) | 9.446e-13 | 6.735e-09 |
| t ∈ [0.45, 0.55] | 1e-3 | 1.0000e-03 (caught) | 9.446e-13 | 6.735e-09 |

**A 10 % error in the blended evaluator over t ∈ [0.30, 0.40] moves no printed metric at
all** and the script exits 0. See U23-3.

**C. Float32 outer response-derivative gap vs step size** (is the 0.609 relative gap a real
kink or roundoff?):

| h/η_b | rel. deriv gap | natural deriv gap | rel. value gap |
|---:|---:|---:|---:|
| 0.01 (the script's value) | 6.0872e-01 | 4.5829e-03 | 4.0004e-03 |
| 0.03 | 1.6006e-01 | 1.2323e-03 | 3.8973e-03 |
| 0.10 | 4.2148e-02 | 4.3261e-04 | 5.7475e-03 |
| 0.30 | 1.7140e-02 | 1.5344e-04 | 3.7073e-03 |

The derivative gap falls as 1/h (0.609/30 = 0.020 ≈ 0.0171 at 30h) → **finite-precision
artefact, not a symbolic jump**, exactly as `near_round_bassetti_erskine_switch.md` §10.2
claims. The *value* gap is h-independent at ~4e-3 relative, matching the Float32 response's
own relative error (recorded 1.7781e-3) — an evaluation noise floor, not a jump. In Float64
the same quantity is 6.7e-9, matching the Float64 response error 1.2449e-08. Both precisions
track their own arithmetic; the branch switch is genuinely continuous.

### b5. `pic_gaussian_luminosity_validation.jl` — the only enforced gate, fed its own recorded defect

Probes: `probe_lum_extent.jl`, `probe_lum_gate.jl`. Production `_pic_luminosity!` sums the
**full** (nx+1)×(ny+1) deposit extent since the U5-8 fix; the script's `deposited_overlap`
still sums `q1[1:nx, 1:ny]` — the pre-fix extent. Injected defect = exactly U5-8, at its
recorded magnitude (8.0e-5 relative luminosity deficit).

| configuration | method | grid | production-vs-script rel. error | gate (≤1e-12) |
|---|---|---:|---:|---|
| committed cases (offset_flat) | CIC | 32 | 7.45e-16 | PASS |
| committed cases (offset_flat) | CIC | 128 | 1.10e-15 | PASS |
| committed cases (offset_flat) | TSC | 32 | 1.25e-16 | PASS |
| committed cases (offset_flat) | TSC | 128 | 2.94e-15 | PASS |
| both beams identical | CIC | 32 | 7.50e-16 | PASS |
| both beams identical | CIC | 128 | 2.39e-15 | PASS |
| **both beams identical** | **TSC** | **32** | **5.07e-09** | **FAIL** |
| **both beams identical** | **TSC** | **128** | **8.88e-08** | **FAIL** |

Charge *is* deposited on the excluded edge in the committed cases (up to 5.06e-6 of q1 under
TSC) — the product `q1·q2` there is zero only because no committed case puts both beams'
extreme particles on the same edge. See U23-1.

---

## (c) Every tolerance / threshold in the region — ENFORCED vs PRINT-ONLY

| # | file:line | quantity / threshold | status |
|---:|---|---|---|
| 1 | `pic_gaussian_field_validation.jl:59` | `sigma_min > 0` → `ArgumentError` | **ENFORCED** (input validation, not physics) |
| 2 | `pic_gaussian_field_validation.jl:60` | `sigma_max > sigma_min` → `ArgumentError` | **ENFORCED** (input validation) |
| 3 | `pic_gaussian_field_validation.jl:135` | `global_exact_norm > 0` → `error` | **ENFORCED** (degenerate-reference guard; no accuracy content) |
| 4 | `pic_gaussian_field_validation.jl:168-172, 396-429` | min / median / mean / p95 / max relative field error, per case and aggregated | **PRINT-ONLY** |
| 5 | `pic_gaussian_field_validation.jl:391, 393` | `python3` missing / case data disabled | `@warn` / `@info` — loud, not a gate |
| 6 | `near_round_gaussian_transition.jl:407-411` | `all(isfinite, (max_force_relative_error, max_response_relative_error, max_core_gradient_error))` → `error` | **ENFORCED — finiteness ONLY, no magnitude bound** |
| 7 | `near_round_gaussian_transition.jl:368-375` | max force / response relative + natural error, transition-only variants (8 numbers) | **PRINT-ONLY** |
| 8 | `near_round_gaussian_transition.jl:380-385` | outer series / exact response natural error, observed outer conditioning factor | **PRINT-ONLY** |
| 9 | `near_round_gaussian_transition.jl:386` | max core-gradient relative error | **PRINT-ONLY** (its finiteness *is* gated, its magnitude is not) |
| 10 | `near_round_gaussian_transition.jl:387-388` | inner + outer endpoint continuity — 8 gaps each, 16 numbers | **PRINT-ONLY, and not even inside the finiteness gate** |
| 11 | `near_round_gaussian_transition.jl:389-390` | 6D symplectic residual | **PRINT-ONLY, not inside the finiteness gate** |
| 12 | `near_round_gaussian_transition.jl:400-405` | CUDA parity max relative + natural error (both precisions) | **PRINT-ONLY, not inside the finiteness gate** |
| 13 | `gaussian_pic_zscan.jl` (whole file) | residual fraction, `rel_err_px/py`, `jump_px/py`, per-slice-grid jump reduction, the "~1/residual_fraction" prediction | **PRINT-ONLY — file contains no `error`, `throw`, or `@assert`** |
| 14 | `spectral_poisson_field_validation.jl` (whole file) | median / p95 / max shape error × 4 methods × 3 cases, domain-size scaling (5 rows), thin-grid scaling (4 rows), timings | **PRINT-ONLY — no `error`, `throw`, or `@assert`** |
| 15 | `gaussian_pic_bigaussian_validation.jl` (whole file) | quantile + random PIC/hybrid medians, gains, isolated shot-noise floors | **PRINT-ONLY — no `error`, `throw`, or `@assert`** |
| 16 | `gaussian_pic_field_validation.jl` (whole file) | PIC/hybrid median + max, median_gain, max_gain, 12 rows | **PRINT-ONLY — no `error`, `throw`, or `@assert`** |
| 17 | `pic_gaussian_luminosity_validation.jl:148-149` | `maximum_interface_relative_error <= 1e-12` → `error` | **ENFORCED — the only physics-adjacent binding gate in the entire region** (and see U23-1) |
| 18 | `pic_gaussian_luminosity_validation.jl:127, 142, 155-156` | `relative_error` vs the *analytic* Gaussian overlap; max 2.81e-02 today | **PRINT-ONLY** |
| 19 | `pic_gaussian_luminosity_validation.jl:143-144` | padding-0.1 omitted → "not evaluated" | loud, not a gate (correct behaviour) |
| 20 | `pic_grid_extent_stability.jl` (whole file) | slice-to-slice / turn-to-turn relative variation, **`dropped`** | **PRINT-ONLY — no `error`, `throw`, or `@assert`, despite the docstring's "It must stay at zero for a production setting"** |
| 21 | `pic_grid_extent_stability.jl:26` | ":sigma … Measured: 4-8x, against a prediction of >=10x" | **PRINT-ONLY** — nothing in the code compares |
| 22 | `gaussian_pic_zscan.jl:22-24` | "should be smaller than pure PIC's jump by roughly the residual fraction" | **PRINT-ONLY** — nothing in the code compares |

**Summary: 8 files, 5 with zero assertions of any kind. Exactly one numeric physics
threshold in the whole region (#17, 1e-12), and it compares production to a stale copy of
itself. Two more `error(...)`s exist (#3, #6) and neither bounds an accuracy number.**

Mitigations that *are* binding live in the suite, not here:
`test/runtests.jl:461` "Near-round Gaussian transition" (force/response 5e-11 F64, 3e-5 F32;
core gradients 32eps; symplectic residual < 2e-8), `:5945` "GaussianPIC beats PIC toward the
soft-Gaussian kick" (`err_h < 0.03`, `err_h < 0.95·err_p`, round case only), `:5985`
"Spectral solver reproduces soft-Gaussian kick", `:6368` PIC grid_extent/quantize,
`:6512` "PIC luminosity overlap sums the full deposit extent", `:8666` grid_extent rejection.

---

## (d) Header drift — every disagreement, quoted

**D1. `gaussian_pic_field_validation.jl:17-20` (U20-2, still open in the file at HEAD).**
Header: *"Both solvers are exercised through their real internals: PIC via `_pic_solve_field`
and the hybrid via the same integrated-log Green convolution with the erf-integrated Gaussian
subtracted on the grid and the exact Bassetti-Erskine field added back."*
`grep -n '_pic_solve_field' validation/gaussian_pic_field_validation.jl` returns **only line
18, the header itself**. The solve is the local `solve_from_charge` (lines 84-92); the
subtraction profile is the local `gauss_profile` (57-72). `GaussianPICPoissonSolver` appears
only in header line 2. `validation/README.md:104-109` now carries the correct caveat; the
file's own header still asserts the opposite.

**D2. `gaussian_pic_bigaussian_validation.jl:21-26`, `validation/README.md:118-123`, and
`docs/theory/gaussian_subtracted_pic_solver.md:695-701` — the weakest case is misidentified.**
Header: *"The weakest gain is for a diagonally offset perturbation, which introduces x-y
coupling the uncoupled subtraction cannot remove -- motivating the coupled (rotated)
subtraction branch gated by `coupling_tol`."* Theory doc: *"The weakest case is a *diagonally*
offset perturbation … an x-only offset (no coupling) keeps a 2.2–3.4x gain."*
The script's own reproduced table (and the doc's own table) say otherwise:

| case | quant gain |
|---|---:|
| `pert_f0.2_off(2,2)_coupled` (**diagonal**) | **1.5** |
| `pert_f0.1_off(3,0)` (**x-only, no coupling**) | **1.4** ← the weakest |

The x-only far perturbation keeps **1.4x**, not "2.2–3.4x". The stated motivation for the
coupled/rotated subtraction branch is not supported by the measurement it cites. See U23-5.

**D3. `spectral_poisson_field_validation.jl:23` (U20-4b, still open).** *"Two solver variants
are implemented"* — four are (`spectral_free_field`, `spectral_grid_field`,
`spectral_specderiv_field`, `spectral_onmesh_field`), and the two the header names are not
the two the main table reports (the table reports onmesh / specderiv / grid-fd / pic;
grid-free appears only in the domain-scaling appendix).

**D4. `spectral_poisson_field_validation.jl:244-245` (U20-4c, still open).** Comment:
*"anisotropic grid resolving the thin direction with Ny ~ 2*domsig*(sx/sy)"*; code line 248 is
`Ny = max(128, ceil(Int, 6 * domsig * (smax / min(sx, sy))))`, capped at 1200 — a factor 3
apart. For flat25 the comment predicts 800; the code asks 2400 and delivers 1200.

**D5. `spectral_poisson_field_validation.jl:259` (U20-4d, still open).** Dead branch
`label == "spectral-free" ? "d=16 L=M=96" : …` — that label is never produced by the loop at
250-254. Confirmed in the run: no `spectral-free` row in the main table.

**D6. `pic_gaussian_field_validation.jl:20-24` — the output list is wrong and incomplete.**
Header lists three outputs. The script also writes `result/pic_gaussian_field_validation_plot.py`
(line 178-349, unconditionally, before any case runs) and, when
`OCTOPUS_PIC_VALIDATION_RANDOM_CASES > 0`, writes
`pic_gaussian_field_validation_random_summary.tsv` — **a different filename from the one the
header promises**, and the one `paper/make_figures.py:317` consumes for manuscript Figure 3.
The header documents none of the nine `OCTOPUS_PIC_VALIDATION_*` environment overrides
(lines 48-56), contrary to AGENTS.md §Updating Validations ("Keep a concise top-of-file
comment with the reference model, error metric, **inputs**, outputs, and run command").

**D7. `pic_grid_extent_stability.jl:26` and `src/tasks/strongstrong/pic_cpu.jl:951-952`.**
Both say *"Measured: 4-8x"*. Reproduced at HEAD: 8.2x / 3.9x slice-to-slice (x/y) and
5.1x / 3.5x turn-to-turn (x/y) — the range is **3.5-8.2x**; both vertical ratios sit below
the quoted floor.

**D8. `validation/README.md:141-149` (U20-4a, still open).** *"`spectral_poisson_field_validation.jl`
validates the spectral sine-series 2D Poisson solver … for both the grid (DST) and grid-free
variants"*, followed by two sentences describing `method=:grid` / `method=:grid_free` solver
settings. The script constructs no `SpectralPoissonSolver`, has no `method` argument, and its
main table contains no grid-free row.

**D9. `validation/README.md:86-88` internally contradicts itself.** Opening sentence:
*"`gaussian_pic_field_validation.jl` compares the `GaussianPICPoissonSolver` transverse
field…"*; the caveat paragraph 18 lines later: *"never a `GaussianPICPoissonSolver` object"*.

**D10. `docs/theory/spectral_sine_poisson_solver.md:418-420` names the wrong script.**
*"`validation/pic_gaussian_field_validation.jl`: compare the spectral field to the
Bassetti-Erskine field…"* — the spectral comparison lives in
`spectral_poisson_field_validation.jl`; `pic_gaussian_field_validation.jl` has no spectral
code path. Cross-file seam, flagged not chased.

**Headers verified CORRECT (no drift found):** `near_round_gaussian_transition.jl:1-21`
(reference model, every one of the six metric families, run command — all match);
`gaussian_pic_zscan.jl:1-40` (reference model, metrics, all four env overrides, output path,
run command — all match, and the "drives `_gpic_solve_drifted_field!`" claim is true);
`pic_gaussian_luminosity_validation.jl:1-21` (the analytic overlap formula in the docstring
is the formula at line 53-59); `pic_grid_extent_stability.jl:14-47` apart from D7 (the
"no analytic reference" statement, the two relative-variation formulas, the `:quantile`
removal note with its 7.2e-2 vs 5.3e-2 numbers, all three env overrides, the output path);
`gaussian_pic_bigaussian_validation.jl:28-29` (U20-3's fix is correct — the script writes
exactly the `.md` the header now names).

---

## (e) Do the recorded numbers reproduce? — every script run at HEAD

All eight region scripts executed end-to-end at their **committed defaults**, exit 0, with a
CUDA device present. Runtimes (shared GPU/CPU box, indicative): grid_extent 73 s, near_round
54 s, spectral 61 s, pic_field 29 s, zscan 30 s, bigaussian 29 s, gpic_field 25 s, luminosity
(reduced, see below). **No script in this region exceeded the 420 s cap; nothing was skipped.**

The one reduction: `pic_gaussian_luminosity_validation.jl` was run at
`PARTICLES=20000 GRIDS=32 PADDING=0.1` rather than its default 3×4×3 sweep at up to 400 k
particles, purely for turnaround; its gate and both its columns were then probed exhaustively
by `probe_lum_extent.jl` / `probe_lum_gate.jl` at grids 32 and 128, both deposit methods, all
five committed cases. Its full-default run is the one measurement in this region I did not
take, and it is a runtime, not a correctness, gap.

### Reproduces exactly

**`near_round_gaussian_transition.jl` vs `docs/theory/near_round_bassetti_erskine_switch.md`
§10.1/§10.2/§8 — 27 of 27 recorded numbers match to every printed digit** (the doc dates
its reference run 2026-07-30; this is 2026-08-05, same machine class, plus CUDA):

| quantity | recorded | measured |
|---|---|---|
| F32 transition interval | [1.9967e-2, 3.9934e-2] | [0.019966973, 0.039933946] |
| F64 transition interval | [2.2061e-4, 4.4121e-4] | [2.2060595791255979e-4, 4.4121191582511957e-4] |
| F32 / F64 max transition force rel. error | 4.7557e-6 / 6.1096e-12 | 4.755703848753814e-6 / 6.109630934116456e-12 |
| F32 / F64 max transition force natural error | 8.4271e-7 / 6.3707e-14 | 8.427070389223421e-7 / 6.370651360361042e-14 |
| F32 / F64 max transition response natural error | 1.4771e-5 / 3.1170e-11 | 1.4771319176310286e-5 / 3.1170268286632506e-11 |
| F32 / F64 max core-gradient rel. error | 1.1921e-7 / 2.2204e-16 | 1.1920928955078125e-7 / 2.220446049250313e-16 |
| F64 6D symplectic residual | 1.6001e-10 | 1.6001065750170795e-10 |
| F32 / F64 CPU-CUDA natural difference | 1.0541e-5 / 1.9150e-11 | 1.0541370958705691e-5 / 1.9149849430184703e-11 |
| F32 / F64 response rel. error maxima | 1.7781e-3 / 1.2449e-8 | 1.7780618537735847e-3 / 1.2449244799202257e-8 |
| observed conditioning factors (§ p.793) | 61.937 / 4.948 | 61.93662661685207 / 4.9482474420982525 |
| §10.2 continuity table, all 16 entries | e.g. F64 outer 1.6606e-13 / 4.6786e-11 / 1.6423e-11 / 4.6862e-9 | 1.6605941055289173e-13 / 4.67859285925669e-11 / 1.6423237770834766e-11 / 4.686157498911346e-9 |

**`gaussian_pic_field_validation.jl` vs `docs/theory/gaussian_subtracted_pic_solver.md` §9
— 5 of 5 rows, 15 of 15 numbers:** round/48 1.5e-3 · 1.6e-4 · 9.1x → 1.445e-3 · 1.593e-4 ·
9.07x; round/128 4.6e-4 · 1.8e-4 · 2.6x → 4.585e-4 · 1.747e-4 · 2.62x; ~11:1/48 4.5e-3 ·
2.2e-4 · 20.6x → 4.498e-3 · 2.188e-4 · 20.56x; ~11:1/128 1.3e-3 · 3.2e-4 · 4.1x → 1.282e-3 ·
3.148e-4 · 4.07x; 25:1/48 5.0e-3 · 2.8e-4 · 17.6x → 4.950e-3 · 2.816e-4 · 17.58x.

**`gaussian_pic_bigaussian_validation.jl` vs the same doc §9 bi-Gaussian table — 5 of 5 rows,
15 of 15 numbers:** 4.7e-4/1.8e-4/2.6 → 4.68e-4/1.77e-4/2.6; 5.5e-4/2.6e-4/2.2 →
5.51e-4/2.56e-4/2.2; 3.3e-4/1.9e-4/1.8 → 3.30e-4/1.88e-4/1.8; 6.5e-4/4.4e-4/1.5 →
6.47e-4/4.40e-4/1.5; 6.1e-4/4.5e-4/1.4 → 6.08e-4/4.45e-4/1.4.

**`spectral_poisson_field_validation.jl` vs `docs/theory/spectral_sine_poisson_solver.md`
§16 — 9 of 9:** domain-size 8.8e-2 / 2.2e-2 / 4.0e-3 / 1.3e-3 / 1.0e-3 → 8.799e-2 / 2.168e-2 /
4.001e-3 / 1.325e-3 / 1.020e-3; thin-grid 8.1e-2 / 3.4e-2 / 1.3e-2 / 7.8e-3 → 8.071e-2 /
3.386e-2 / 1.341e-2 / 7.767e-3.

**`gaussian_pic_zscan.jl` vs `validation/README.md:715-728` and `docs/todo.md:419-433` —
3 of 3:** residual fraction 0.088 → 0.0876; per-slice-grid jump reduction 2.8x / 1.10x →
2.82x / 1.10x. Conclusion (1) also holds: on the common grid hybrid ≡ pic (5.758e-6 vs
5.772e-6 in x, 2.339e-4 vs 2.345e-4 in y).

**`pic_gaussian_field_validation.jl` vs `docs/history/comprehensive_audit_2026_08_04.md:2079`
("median relative error 3.46e-4 … 4.60e-4 across five aspect ratios"):** measured
3.4649e-4 / 3.5897e-4 / 3.9000e-4 / 4.5987e-4 / 3.9000e-4 → range 3.46e-4 to 4.60e-4. ✔

**`pic_grid_extent_stability.jl` vs its own docstring:** `:extrema` slice-to-slice 5.3e-2
(docstring's comparison anchor for the removed `:quantile`) → 5.3131e-2 ✔; `dropped = 0` for
both estimators ✔; the `:sigma`-stabler direction ✔.

**`paper/data/gaussian_pic_field_validation_summary.tsv` (manuscript Figure 2, Sec. 4.1)**
reproduces to 12 significant digits for the three grids the committed default emits
(48/64/128, 12 rows). Example: frozen `round 48 … 0.001445020712970878` vs fresh
`0.00144502071296999`.

### Does NOT reproduce

| claim | source | measured |
|---|---|---|
| ":sigma is **4-8x** stabler than :extrema" | `pic_grid_extent_stability.jl:26`, `src/tasks/strongstrong/pic_cpu.jl:951` | **3.5-8.2x** (y-plane 3.9x slice-to-slice, 3.5x turn-to-turn) |
| "The weakest gain is for a **diagonally** offset perturbation" | `gaussian_pic_bigaussian_validation.jl:24-26`; `gaussian_subtracted_pic_solver.md:695`; `README.md:121` | weakest is `pert_f0.1_off(3,0)` at **1.4x**; the diagonal case is 1.5x |
| "an x-only offset (no coupling) keeps a **2.2–3.4x** gain" | `gaussian_subtracted_pic_solver.md:698-700` | the x-only far offset keeps **1.4x** |
| "The hybrid is **never worse than PIC**" | `gaussian_subtracted_pic_solver.md:693`; `gaussian_pic_bigaussian_validation.jl:21-22` | `max_gain` **0.9957** at round/grid 128 in the script's own TSV (and 0.9988 / 0.9982 at 25:1 grid 96/256 in the paper's frozen copy); random-draw coupled case HYB 1.30e-3 > PIC 1.25e-3 |
| paper Fig. 2 rows at grids **96 / 192 / 256** | `paper/data/gaussian_pic_field_validation_summary.tsv` | not produced by the committed default `OCTOPUS_GPIC_GRIDS=48,64,128`; the required override is documented nowhere |

---

## (f) The near-round Bassetti-Erskine branch switch — does the script see it?

`_gaussian_beambeam_kick_response_principal` (`src/elements/strong_beam.jl:1051-1095`) has
**two** switch points, not one: `η ≤ inner` → pure series; `inner < η < outer` → quintic
smoothstep blend `w = t³(10 − 15t + 6t²)` plus a `dw`-proportional covariance chain term;
`η ≥ outer` → pure elliptic. Both `w` and `dw` vanish at t=0 and t=1 (and so does `d²w/dt²`),
so the value, first derivative and the chain term are continuous at both ends by construction.

**Does the script sample both sides?** Yes, at both switch points. `_continuity_metrics(T, b)`
(lines 70-141) evaluates at `b−2h, b−h, b, b+h, b+2h` with `h = 0.01·b`, over 132 radii ×
33 angles, so it straddles `inner` (below → series, above → blend) and `outer` (below →
blend, above → elliptic), and it estimates both a value gap (linear extrapolation from each
side) and a first-derivative gap (second-order one-sided differences).

**Is the field continuous across it?** Measured yes, in both precisions, at both endpoints:

| arithmetic | endpoint | force value gap | response value gap | η-scaled force deriv gap | η-scaled response deriv gap |
|---|---|---:|---:|---:|---:|
| Float64 | inner | 1.578e-15 | 1.244e-14 | 1.568e-13 | 2.266e-13 |
| Float64 | outer | 1.661e-13 | 4.679e-11 | 1.642e-11 | 4.686e-09 |
| Float32 | inner | 7.784e-7 | 6.951e-7 | 7.952e-5 | 7.800e-5 |
| Float32 | outer | 2.902e-6 | 2.287e-5 | 3.758e-4 | 4.583e-3 |

(natural-scale; all sixteen match the theory note's §10.2 table digit for digit). The Float32
outer *relative* response-derivative gap is 0.609, which looks alarming; probe C above shows
it scales as 1/h, so it is a finite-difference roundoff artefact, and the h-independent value
gap tracks the Float32 response's own 1.78e-3 relative error. **No discontinuity.**

**Is it sampled *densely enough*? No — this is the finding.** Across the whole script, the
blend interval is evaluated at exactly five normalised positions:
**t ∈ {0.010, 0.020, 0.500, 0.960, 0.980}** — two from `_continuity_metrics(inner)`, two from
`_continuity_metrics(outer)`, and the single `(inner+outer)/2` entry of the accuracy sweep's
η list (lines 173-184; every other entry — 0, inner/4, inner, outer, 2·outer, 1e-3, 1e-2,
0.1, 0.5 — is at or outside an endpoint in both precisions). **About 92 % of the blend
interval is never evaluated by any part of the script.** The mirroring suite testset
(`test/runtests.jl:519`) uses η ∈ (0, inner, 0.75·outer, outer, 1.2·outer), i.e. the *same*
single interior point t = 0.5. Probe B measured the consequence: a **10 % evaluator error
confined to t ∈ [0.30, 0.40] leaves every printed metric bit-identical** and the script
exits 0. See U23-3.

---

## Leads

### LEAD U23-1 [medium, confidence high] validation/pic_gaussian_luminosity_validation.jl:81-82 (+148-149)
Claim: The region's only enforced numeric gate compares production `_pic_luminosity` against
a *stale local copy* of it — the copy still truncates the overlap sum to `q1[1:nx,1:ny]`
while production has summed the full `(nx+1)×(ny+1)` extent since the U5-8 fix — so the gate
is now structurally incapable of detecting the very defect U5-8 recorded, and passes today
only by an accident of the committed case set.
Mechanism: `deposited_overlap` (lines 61-83) hand-reimplements `_pic_luminosity!`
(`src/tasks/strongstrong/pic_cpu.jl:1970-2007`). Every other line agrees exactly — the
padding algebra reduces to `hx == tx`, verified — but line 81 sums
`@view(q1[1:nx,1:ny]) .* @view(q2[1:nx,1:ny])` where production loops
`for j in 1:(ny+1), i in 1:(nx+1)`. Under TSC a particle at the mesh's upper edge
(`u_max = nx − 1.05`) deposits into node `nx+1`: measured 5.06e-6 of q1's charge in
`offset_flat`, 5.06e-6 in `centered_flat`, 1.60e-7 in `centered_round`. The *product*
`q1·q2` on that edge is zero in all five committed cases only because no case puts both
beams' extreme particles on the same edge. Because the script's copy computes exactly the
pre-U5-8 quantity, a regression that re-truncated production would make the two agree
*better*, and the gate would still pass. `validation/README.md:314-317` calls this an
"independently assembled discrete quadrature"; it is neither independent nor current.
Repro: `julia --startup-file=no --project=. scratchpad/audit/probe_lum_gate.jl` (self-
contained; replicates `deposited_overlap` verbatim and calls production `_pic_luminosity`).
Committed cases → 1.2e-16 … 2.9e-15, PASS. Same code with `x2,y2 = x1,y1` → TSC grid 32
**5.07e-09**, TSC grid 128 **8.88e-08**, both FAIL the script's own 1e-12. Also
`probe_lum_extent.jl` prints the excluded edge charge per case.

### LEAD U23-2 [medium, confidence high] validation/gaussian_pic_field_validation.jl:124-131
Claim: The "HYB" column of the table that `docs/theory/gaussian_subtracted_pic_solver.md` §9
and manuscript Figure 2 both rest on is a comparison of the code to a copy of itself: the
hybrid's analytic add-back is the *identical* `gaussian_beambeam_kick` call that supplies the
reference, so the reported hybrid error is algebraically the magnitude of the residual grid
field measured against zero, and carries no information about the Bassetti-Erskine evaluator,
the moment estimate, or the consistency between the subtracted profile and the added-back
field — which is exactly where a production bug would live.
Mechanism: line 124 computes `ekx, eky = gaussian_beambeam_kick(sigx, sigy, x, y)`; line 128
computes `hkx = 2*(deX + (ns/2)*ekx)/ns`; line 130 pushes `hypot(hkx − ekx, …)`. Substituting,
`hkx − ekx = 2·deX/ns + ekx − ekx = 2·deX/ns` identically. Production `_gpic_interaction!`
derives the add-back's `(μ, σ)` from `_gpic_source_moments`/`_gpic_drifted_gaussian` and the
subtraction profile from `_gpic_gaussian_profile!`; the script forces both to the *nominal*
`(0, 0, sigx, sigy)`, so an add-back/subtraction moment mismatch is unrepresentable here.
The PIC column is a genuine analytic comparison; only the hybrid column is circular.
Repro: `julia --startup-file=no --project=. scratchpad/audit/probe_gpic_instrument.jl`.
Round case, grid 128, CIC: scaling the Bassetti-Erskine evaluator by ×2 moves PIC med
4.5850e-04 → 3.3339e-01 while HYB med moves 1.7468e-04 → **8.7342e-05, i.e. exactly two
times better**; at ×(1+1e-2) HYB med is 1.7295e-04 against a 1.7468e-04 baseline.

### LEAD U23-3 [medium-low, confidence high] validation/near_round_gaussian_transition.jl:173-188 and 407-411
Claim: The script that is the theory note's declared validation of the near-round/elliptic
branch switch samples the blend interval at five normalised positions
(t ≈ 0.010, 0.020, 0.500, 0.960, 0.980), leaving ~92 % of it unevaluated, and its sole
mechanical assertion is a finiteness check on three of its twenty-nine printed numbers — so a
10 % evaluator error inside the blend passes with every printed metric bit-identical.
(Extends U20-1, which named the print-only gate; this adds the coverage half and measures both.)
Mechanism: the η list at 173-184 is `{0, inner/4, inner, (inner+outer)/2, outer, 2·outer,
1e-3, 1e-2, 0.1, 0.5}`; for Float64 (`inner`=2.206e-4, `outer`=4.412e-4) and Float32
(1.997e-2, 3.993e-2) alike, every entry but `(inner+outer)/2` lies at or outside an endpoint,
so the blend interior gets one accuracy sample. `_continuity_metrics` adds only ±1 % and ±2 %
neighbourhoods of each endpoint. Lines 407-411 gate `isfinite` on
`max_force_relative_error`, `max_response_relative_error`, `max_core_gradient_error` only —
the 16 continuity gaps, the 6D symplectic residual and both CUDA parity numbers are outside
even that. The mirroring suite testset (`test/runtests.jl:519`) uses the same single interior
point `0.75·outer` (t = 0.5), so the gap is not covered elsewhere.
Repro: `julia --startup-file=no --project=. scratchpad/audit/probe_nearround_instrument.jl`.
Section B: injecting a ×1.1 factor for t ∈ [0.30, 0.40] leaves the sweep at **6.1096e-12**
(baseline 6.1096e-12) and both continuity gaps at 9.446e-13 / 6.735e-09 (baseline identical);
the same injection at 1e-3 over t ∈ [0.45, 0.55] *is* caught (1.0000e-03), proving the metric
works and the sampling is what fails. Section A confirms the metric reports a reference error
of 1e-9 as 1.0045e-09.

### LEAD U23-4 [low, confidence high] validation/gaussian_pic_field_validation.jl:17-20
Claim: The header asserts the script exercises "real internals … PIC via `_pic_solve_field`";
the only occurrence of that name in the file is the header line itself. U20-2 was closed in
`validation/README.md` (a correct caveat paragraph was added at 104-109) but not in the file
whose header makes the claim, so a reader who opens the script is still told the opposite of
what `README.md` says.
Mechanism: the PIC solve is `solve_from_charge` (84-92, a hand-wired `fft!`/`ifft!` around
production `_pic_green_fft` and `_pic_field`); the hybrid profile is `gauss_profile` (57-72),
a reimplementation of `_gpic_gaussian_profile!`. Neither `_pic_solve_field` nor
`GaussianPICPoissonSolver` is ever constructed or called.
Repro: `grep -n '_pic_solve_field\|GaussianPICPoissonSolver\|_gpic_' validation/gaussian_pic_field_validation.jl`
→ two hits, both inside the `#= … =#` header block (lines 2 and 18), zero in code.

### LEAD U23-5 [low, confidence high] docs/theory/gaussian_subtracted_pic_solver.md:695-701 + validation/gaussian_pic_bigaussian_validation.jl:24-26
Claim: The documented motivation for the coupled (rotated) subtraction branch — "the weakest
case is a diagonally offset perturbation … an x-only offset (no coupling) keeps a 2.2–3.4x
gain" — is contradicted by the table immediately above it and by a fresh run of the script it
cites: the weakest gain is the **x-only** far perturbation at 1.4x, and the diagonal case is
1.5x. Out-of-region file quoted because the script header and `validation/README.md:121`
carry the identical claim.
Mechanism: the doc's table lists the coupled `(2,2)σ` row before the far `(3,0)σ` row, and the
narrative reads "weakest" off the last row rather than the smallest gain. The reproduced
numbers are the doc's own: coupled 6.5e-4 → 4.4e-4 = 1.5x; far x-only 6.1e-4 → 4.5e-4 = 1.4x.
Repro: `julia --startup-file=no --threads=4 --project=. validation/gaussian_pic_bigaussian_validation.jl`
→ quant gain column 2.6 / 2.2 / 1.8 / **1.4** (`pert_f0.1_off(3,0)`) / **1.5**
(`pert_f0.2_off(2,2)_coupled`).

### LEAD U23-6 [low, confidence high] validation/spectral_poisson_field_validation.jl:215-221
Claim: `shape_relerr` returns **exactly 0.000e+00** for a "solver" whose field is the exact
reference scaled by 2, by 0.5, or **by −1 (sign-inverted, attractive instead of repulsive)**,
and is bit-invariant to scaling the reference by up to 100 %. The script header (9-17) and
`validation/README.md:154-158` disclose the calibration but neither states that the blindness
is *exact and unbounded*, so "median rel error 1.3e-3" reads as a field-accuracy statement
when it is a shape-only statement.
Mechanism: `c = argmin_c ‖cE − K‖²` absorbs any scalar exactly, including a negative one; the
residual and the normaliser then scale together, so the ratio is invariant. Already known and
*mitigated in the suite*: `test/runtests.jl` "Spectral field absolute normalization is derived,
not fitted" exists for this reason and says so. Recorded here with the measured magnitude, and
because `validation/README.md:141-149` still describes the script as validating "the spectral
sine-series 2D Poisson solver … for both the grid (DST) and grid-free variants" while
`SpectralPoissonSolver` is never constructed and no grid-free row appears in the main table
(U20-4a, unclosed).
Repro: `julia --startup-file=no --project=. scratchpad/audit/probe_metrics_instrument.jl`,
section S1 → all three statistics 0.000e+00 for s ∈ {2.0, 0.5, −1.0}; section S2 → the metric
is 6.112342e-03 / 1.053454e-02 / 1.313443e-02 for d = 0, 1e-6, 1e-2 and 1.0 alike.

### LEAD U23-7 [low, confidence medium] validation/pic_grid_extent_stability.jl:109-110
Claim: The `dropped` column double-counts a corner escapee and measures a different box from
the one production drops against, so the column the docstring calls the production-critical
one ("It must stay at zero") is not the production quantity. It is 0 today, so this is latent.
Mechanism: `drop += count(i -> !(ax[1] <= x[i] <= ax[2]), idx) + count(i -> !(ay[1] <= y[i] <= ay[2]), idx)`
is a per-**axis** sum — precisely the defect the 2026-08-05 audit fixed on the production side
(`_pic_count_outside_box`, `src/tasks/strongstrong/pic_cpu.jl:997-1003`: *"the old per-axis
pair of counts reported a corner escapee — outside in both x and y — as 2 … U5-6"*). Further,
it tests against the raw `_pic_axis_extent` interval, whereas production drops against the box
`_pic_interaction_grids` builds — which adds 3 cells of padding (`width += 3*tx`) and may
quantise — and against *drifted* source coordinates (`_pic_count_outside_box_drifted`,
`x + px·s`), not the undrifted `beam.rep.x` this script reads. `README.md:548-553` discloses
that the column is script-local but not that it is per-axis, unpadded, and undrifted.
Repro: read lines 107-111 beside `src/tasks/strongstrong/pic_cpu.jl:995-1003`; or place one
particle outside in both x and y and observe the column report 2.
`julia --startup-file=no --threads=4 --project=. validation/pic_grid_extent_stability.jl`
prints `dropped = 0` for both estimators today.

### LEAD U23-8 [low, confidence high] validation/pic_gaussian_field_validation.jl:20-24
Claim: The header's "Outputs are written under `result/`" list omits a file the script always
writes and names a file the script does not write in the mode manuscript Figure 3 depends on;
and it documents none of the nine environment inputs, contrary to AGENTS.md §Updating
Validations ("reference model, error metric, **inputs**, outputs, and run command").
Mechanism: lines 178-349 unconditionally write `result/pic_gaussian_field_validation_plot.py`,
absent from the header list. Lines 363-366 switch the summary filename to
`pic_gaussian_field_validation_random_summary.tsv` whenever
`OCTOPUS_PIC_VALIDATION_RANDOM_CASES > 0` — and that is the file
`paper/make_figures.py:317` reads for Figure 3 (`paper/README.md:19`). The nine
`OCTOPUS_PIC_VALIDATION_*` overrides (lines 48-56) appear only in `validation/README.md:67-68`
(two of them) and in `docs/history/`.
Repro: `julia --startup-file=no --threads=4 --project=. validation/pic_gaussian_field_validation.jl`
then `ls result/` → six files including the undocumented `_plot.py`; rerun with
`OCTOPUS_PIC_VALIDATION_RANDOM_CASES=100 OCTOPUS_PIC_VALIDATION_WRITE_CASE_DATA=false` → the
`_random_summary.tsv` the header never mentions.

### LEAD U23-9 [trivial, confidence high] validation/gaussian_pic_zscan.jl:60, 88
Claim: The documented override `OCTOPUS_GPIC_ZSCAN_NSLICES` throws `BoundsError` for any
value below 4 (U20-7, unclosed at HEAD).
Mechanism: `source_slice = 4` is hardcoded in the `config` NamedTuple (line 60) and indexed
without a bound check at lines 88 and 89 (`slices1.indices[si]`, `slices1.center[si]`), while
`nslices` is env-driven. Lines 360-362 additionally read `summary_rows[3]`/`[4]` positionally.
Repro: `OCTOPUS_GPIC_ZSCAN_NSLICES=3 OCTOPUS_GPIC_ZSCAN_NPART=20000 julia --startup-file=no --threads=4 --project=. validation/gaussian_pic_zscan.jl`
→ `ERROR: LoadError: BoundsError: attempt to access 3-element Vector{Vector{Int64}} at index [4]`
at `gaussian_pic_zscan.jl:88`.

### LEAD U23-10 [low, confidence medium] validation/gaussian_pic_field_validation.jl:90 and validation/gaussian_pic_bigaussian_validation.jl:68
Claim: Both local-reimplementation scripts hardcode the second-order field derivative, so the
public solver option `field_derivative = :fourth` is silently ignored by the studies that
carry the hybrid's documented accuracy table; and the frozen paper Figure 2 table cannot be
regenerated from the committed defaults. Same drift class as U23-1: a copy that has fallen
behind the original.
Mechanism: both call `O._pic_field(phi, hx, hy)`, whose `fourth::Bool=false` default is taken;
production calls `_pic_field!(…, _pic_fourth_order(solver))` with
`_pic_fourth_order(solver) = solver.field_derivative === :fourth`
(`src/tasks/strongstrong/pic_cpu.jl:1307, 1863`). Today both scripts construct
`PICPoissonSolver` with defaults so the value agrees, but the option is unreachable from
these harnesses. Separately, `paper/data/gaussian_pic_field_validation_summary.tsv` carries
24 rows at grids 48/64/96/128/192/256 while `OCTOPUS_GPIC_GRIDS` defaults to `48,64,128`
(12 rows); the override needed for the paper table is recorded in neither the script header,
`validation/README.md`, nor `paper/README.md`.
Repro: `grep -n '_pic_field(' validation/gaussian_pic_field_validation.jl validation/gaussian_pic_bigaussian_validation.jl`
vs `grep -n '_pic_fourth_order' src/tasks/strongstrong/pic_cpu.jl`; and
`wc -l paper/data/gaussian_pic_field_validation_summary.tsv` (25) vs the default run's
`result/gaussian_pic_field_validation_summary.tsv` (13).

### LEAD U23-11 [low, confidence high] validation/spectral_poisson_field_validation.jl:23, 244-245, 259
Claim: Three header/comment statements disagree with the code beneath them (U20-4b/c/d, all
unclosed at HEAD).
Mechanism: (b) line 23 "Two solver variants are implemented" — four are defined (56, 88, 126,
172) and the two the header describes are not the two the main table reports. (c) lines
244-245 "Ny ~ 2*domsig*(sx/sy)" vs line 248 `ceil(Int, 6 * domsig * (smax/min(sx,sy)))`, a
factor 3; for flat25 the comment predicts 800, the code requests 2400 and the cap delivers
1200. (d) line 259 `label == "spectral-free" ? "d=16 L=M=96" : …` is dead — the loop at
250-254 never produces that label.
Repro: `julia --startup-file=no --threads=4 --project=. validation/spectral_poisson_field_validation.jl`
→ main table has rows `spectral-onmesh`, `spectral-specderiv`, `spectral-grid-fd`, `pic` and
no `spectral-free`; the flat25 rows read `d=16 Nx=128 Ny=1200`.

### LEAD U23-12 [low, confidence high] docs/theory/gaussian_subtracted_pic_solver.md:693 + validation/gaussian_pic_bigaussian_validation.jl:21-22
Claim: "The hybrid is **never worse than PIC**" is contradicted by the max-error column of the
very TSV the sentence's table is drawn from, and by the random-draw columns of the bi-Gaussian
script. Out-of-region doc quoted because both region script headers repeat the claim.
Mechanism: the doc's table shows medians only; `gaussian_pic_field_validation.jl` also writes
`max_gain`, which is **0.9957** at round/grid 128 in a fresh run (and 0.9988 / 0.9982 at
25:1 grid 96/256 in `paper/data/`), i.e. the hybrid's worst-point error exceeds PIC's once the
residual and the discretisation floor cross. In `gaussian_pic_bigaussian_validation.jl`'s
random-draw columns the coupled case is HYB 1.30e-3 vs PIC 1.25e-3. The doc's own shot-noise
paragraph explains why, but the unqualified sentence sits above it.
Repro: `julia --startup-file=no --threads=4 --project=. validation/gaussian_pic_field_validation.jl`
→ `round 128 … max_gain 0.9957049338369836`; `… validation/gaussian_pic_bigaussian_validation.jl`
→ `pert_f0.2_off(2,2)_coupled | … | rand PIC 1.25e-03 | rand HYB 1.30e-03`.

### LEAD U23-13 [low, confidence high] validation/near_round_gaussian_transition.jl:29-60 (cross-file seam)
Claim: The 96-point Gauss-Legendre reference — the independent standard the whole near-round
validation rests on — exists as two hand-copied verbatim implementations, one in the script
and one inside `test/runtests.jl:461-489`, with no shared source and no tripwire. This is the
recorded "do not hand-copy knowledge" class (AGENTS.md §Hard-Won Rules; Measured Lesson 4).
Seam noted, not chased.
Mechanism: `_transition_gauss_legendre` + `_transition_reference` (lines 29-60) and
`transition_reference` + its inline Golub-Welsch eigen-decomposition (runtests.jl:462-489) are
character-for-character the same algorithm, including the `(1+ηz)^1.5` / `(1−ηz)^0.5`
weightings and the `−(ix/v − x²/v²·jx)` response assembly. A correction to one would not
propagate; a divergence would show up as a silent disagreement between the script's numbers
and the suite's tolerances.
Repro: `diff <(sed -n '29,60p' validation/near_round_gaussian_transition.jl) <(sed -n '461,490p' test/runtests.jl)`
— the quadrature body is identical modulo names and indentation.

### LEAD U23-14 [trivial, confidence high] validation/pic_grid_extent_stability.jl:26 and src/tasks/strongstrong/pic_cpu.jl:951-952
Claim: Both the validation docstring and the production docstring record ":sigma … measured
4-8x stabler than :extrema"; the reproduced range at the committed defaults is 3.5-8.2x, with
both vertical-plane ratios below the quoted floor.
Mechanism: the recorded range was taken from one run; the y-plane ratios (3.9x slice-to-slice,
3.5x turn-to-turn) sit under 4 at the committed 200 k / 15-slice / 8-turn settings. A pin
without its measurement envelope (Measured Lesson 5).
Repro: `julia --startup-file=no --threads=4 --project=. validation/pic_grid_extent_stability.jl`
→ extrema 5.3131e-02 / 5.1446e-02 / 5.1687e-02 / 4.8031e-02; sigma 6.4639e-03 / 1.3305e-02 /
1.0233e-02 / 1.3832e-02 → ratios 8.2 / 3.9 / 5.1 / 3.5.

---

## Clean — what audits sound, with the evidence

1. **The physics references are real closed forms, not copies of the code** in 13 of the 15
   comparisons in the region (table (a)). Bassetti-Erskine via `gaussian_beambeam_kick`, the
   two-BE superposition, the closed-form Gaussian overlap, the closed-form core gradient
   `2/(σ₁(σ₁+σ₂))`, the symplectic identity `JᵀSJ = S`, and — for the near-round evaluator —
   an independent 96-point Gauss-Legendre quadrature of a *different* integral representation.
   The two circular cases are named (U23-1, U23-2) and neither is the region's physics core.
2. **The near-round branch switch is genuinely continuous in value and first derivative at
   both switch points, in both precisions** (§(f) table; all sixteen natural-scale gaps match
   the theory note digit for digit), and the alarming Float32 0.609 relative derivative gap is
   proved to be a 1/h finite-difference artefact, not a kink (probe C).
3. **Two of the region's metrics were fed known defects and reported them at the right
   magnitude**: `pic_gaussian_field_validation`'s field error (1e-3 reference error → ×1.18
   median; 1-cell mesh shift → ×14.0) and `near_round`'s relative error (1e-9 → 1.0045e-09;
   1e-6 → 1.0000e-06). These are working instruments.
4. **Every recorded number in the region reproduces**, and there are a lot of them: 27/27 in
   `near_round_bassetti_erskine_switch.md` §10 (including CUDA parity, which needed a GPU and
   got one), 15/15 in `gaussian_subtracted_pic_solver.md` §9's PIC-vs-hybrid table, 15/15 in
   its bi-Gaussian table, 9/9 in `spectral_sine_poisson_solver.md` §16's two scaling tables,
   3/3 for the z-scan in `README.md`/`todo.md`, the 3.46e-4…4.60e-4 band from the 2026-08-04
   audit, and `paper/data/gaussian_pic_field_validation_summary.tsv` to 12 significant digits.
   The five that do not reproduce are narrative claims, not measurements (§(e), and U23-5,
   U23-12, U23-14).
5. **No bitrot.** All eight scripts run end-to-end at HEAD at their committed defaults with
   exit 0 and no deprecation warnings. Every internal API they call resolves:
   `_pic_interaction_grids`, `_pic_solve_field`, `_pic_solve_drifted_field_with_green_fft!`,
   `_pic_interpolate_kick`, `_pic_deposit!`, `_pic_deposit_drifted!`, `_pic_green_fft`,
   `_pic_field`, `_pic_axis_extent`, `_pic_kbb2`, `_pic_extract_slice`, `_pic_luminosity`,
   `_pic_cpu_workspace`, `_PICFieldWorkspace`, `_gpic_solve_drifted_field!`,
   `_gpic_source_moments`, `_gpic_drifted_gaussian`, `_gpic_gaussian_profile!`,
   `_near_round_eta_bounds`, `_near_round_series_response`, `_near_round_conditioning_factor`,
   `_gaussian_beambeam_kick_response`, `_cuda_gaussian_beambeam_kick_response`,
   `longitudinal_slices`.
6. **`gaussian_pic_zscan.jl` is the region's best-constructed study**: it drives the production
   hybrid path end to end (`_gpic_solve_drifted_field!` + `_gpic_source_moments` +
   `_gpic_drifted_gaussian` + `_pic_interpolate_kick` with the production zL/zR weights),
   its self-referential "exact" is deliberate and stated, its header lists reference model,
   metrics, all four env inputs, output and run command correctly, and it reproduced the
   `todo.md` item-4a numbers to three digits (0.0876 vs 0.088; 2.82x vs 2.8x; 1.10x vs 1.10x)
   — including the *refutation* it records, which is the harder thing to keep honest.
7. **`pic_grid_extent_stability.jl` is honest about having no reference** ("There is no
   analytic reference"), states its estimator-noise prediction (`O(1)` vs `O(1/√n)`) before
   measuring, and records a *removed* estimator with the number that got it removed
   (`:quantile` 7.2e-2 vs `:extrema` 5.3e-2 — and `:extrema` reproduced at 5.3131e-2).
8. **RNG hygiene is clean** in all eight: `set_global_rng!(seed=…, method=:philox)` where a
   beam is drawn, per-case `MersenneTwister(seed)` in the two random sweeps, deterministic
   Halton and Gaussian-quantile lattices elsewhere. No inter-section ordering dependence found:
   each `run_case` / `sweep` constructs its own source.
9. **Normalisation conventions are mutually consistent across the region.** The `2·K/n_source`
   convention in `pic_gaussian_field_validation` (line 120), `gaussian_pic_field_validation`
   (127), `gaussian_pic_bigaussian_validation` (129) and `gaussian_pic_zscan` (157, `2·kbb·(n/2)·BE`)
   all reduce to the same physical scale as production's `2·kbb·K` with `kbb = kbb_phys/n_src`
   (`_pic_kbb2`, `src/tasks/strongstrong/pic_cpu.jl:378`), and both independent-reference arms
   land at ~1e-4 relative against the closed form, which would not happen if the constant were
   wrong.
10. **U20-3 is genuinely closed**: `gaussian_pic_bigaussian_validation.jl:29` now names
    `gaussian_pic_bigaussian_validation.md`, and that is the only file line 194-196 writes.

## Unchecked, and why

- **`pic_gaussian_luminosity_validation.jl` at full committed defaults** (3 particle counts ×
  5 cases × 2 methods × 4 grids × 3 paddings, up to 400 k particles/beam) was not run — only
  a reduced sweep plus two exhaustive targeted probes. Reason: turnaround on a box shared with
  ~19 agents. The gate and both metric columns were probed at grids 32 and 128, both deposit
  methods, all five committed cases, so nothing in my findings depends on the omission; the
  script's own `maximum_relative_error` at full statistics is the only number I cannot quote.
- **CUDA-specific behaviour beyond `near_round`'s parity leg** was not exercised; none of the
  other seven scripts has a GPU path. `near_round`'s CUDA parity *did* run and reproduced.
- **`docs/theory/pic_free_space_kernels.md` §3.4's `:lattice` kernel-comparison table**
  (U20-5) remains unreproducible from the committed script — `green_type=:integrated` is
  hardcoded at `pic_gaussian_field_validation.jl:80` with no override among the nine
  `OCTOPUS_PIC_VALIDATION_*` names. I re-verified the absence but did not re-derive the table;
  the theory note itself already records that no harness was ever committed, and the
  `:lattice` regression properties are pinned by `test/runtests.jl:7498/7583`. Carried forward
  from U20 rather than re-opened.
- **Cross-file seams noted and stopped at** (auditor's call, per the standing rules): U23-13
  (duplicated quadrature reference in `test/runtests.jl`), D10 (`spectral_sine_poisson_solver.md`
  §15 naming the wrong validation script), U23-10's paper-provenance half, and U23-5/U23-12's
  doc-side halves.
- **`src/tasks/strongstrong/interface.jl` was under concurrent uncommitted edit by another
  audit agent** during this session (luminosity-file prepare/commit split, `_plan_strong_strong_luminosity_file`).
  Nothing in my region calls that code, and every measurement was taken against a pristine
  `git archive HEAD` snapshot, so no result is affected — recorded so a later reader knows the
  working tree was not quiescent.
