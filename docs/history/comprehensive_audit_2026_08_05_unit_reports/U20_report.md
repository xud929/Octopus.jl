# U20 Report — validation/ field-solver and PIC-stability scripts + theory notes

Repo: /cfs/ad/dxu/Library/Julia/Octopus @ dbefe42. Read-only audit; no repo file touched
(verified: `git status` clean after all probes; probe outputs under scratchpad/U20/ only).

## Coverage

Read every line of the 10 assigned scripts:
- validation/pic_gaussian_field_validation.jl (431)
- validation/near_round_gaussian_transition.jl (412)
- validation/gaussian_pic_zscan.jl (363)
- validation/spectral_poisson_field_validation.jl (300)
- validation/gaussian_pic_bigaussian_validation.jl (196)
- validation/gaussian_pic_field_validation.jl (167)
- validation/pic_grid_extent_stability.jl (157)
- validation/pic_slice_boundary_jitter.jl (129)
- validation/soft_gaussian_pic_comparison.jl (116)
- validation/pic_gaussian_luminosity_validation.jl (158)

and all four theory notes (docs/theory/pic_free_space_kernels.md 454,
gaussian_subtracted_pic_solver.md 790, near_round_bassetti_erskine_switch.md 1150,
spectral_sine_poisson_solver.md 672), the relevant validation/README.md sections, and the
mirroring suite testsets (test/runtests.jl:449 near-round, :5314 GaussianPIC-beats-PIC,
:5354 spectral-reproduces-soft-Gaussian, :7498/:7583 lattice Green, :5702 grid_extent,
:7629 equal-extent invariant). Cross-checked every internal API call
(`_pic_interaction_grids`, `_pic_solve_field`, `_pic_interpolate_kick`, `_pic_deposit!`,
`_pic_deposit_drifted!`, `_pic_green_fft`, `_pic_field`, `_pic_axis_extent`, `_pic_kbb2`,
`_pic_luminosity`, `_gpic_*`, `_near_round_*`, contract helpers) against current src —
all resolve; both probes ran all CPU scripts end-to-end with zero errors.

Probes (CPU, reduced sizes, scratchpad copies with include paths patched; logs
scratchpad/U20/probe1.log, probe2.log):
1. Script-local erf profile vs production `_gpic_gaussian_profile!`: max diff 2e-14 (CIC+TSC).
2. Luminosity gate replication (n=20k, grids 32/128, CIC+TSC incl. luminosity_deposit_method
   override): production `_pic_luminosity` vs independent quadrature ≤ 7e-16 (gate 1e-12).
3. spectral-free domain scaling (NSRC=100 default): d=4 → 8.799e-2 (recorded 8.8e-2),
   d=16 → 1.325e-3 (recorded 1.3e-3).
4. gaussian_pic_field_validation @ grid 48 (OCTOPUS_GPIC_GRIDS=48): reproduces doc §9 table —
   round 1.45e-3/1.59e-4 gain 9.1x, 11:1 4.50e-3/2.19e-4 gain 20.6x, 25:1 gain 17.6x.
5. bigaussian (2 seeds): quantile columns reproduce doc table exactly
   (gains 2.6/2.2/1.8/1.5/1.4).
6. pic_gaussian_field_validation defaults (case data off): runs; medians ~3.5-4.6e-4.
7. zscan @ 20k/grid48: runs through production `_gpic_solve_drifted_field!`; common-grid
   hybrid == pic (recorded conclusion 1); per-slice-grid y-reduction 1.07x (recorded 1.10x);
   x-reduction collapses to 0.94x at low stats — consistent with the shot-noise refutation.
8. jitter @ 20k/12 turns: outer 0.11-0.36 (order-statistics scale, larger at lower n as
   expected), internal equal_area/normal_quantile ratios 1.9x (e) and 16x (p) vs recorded
   1.6x/13x at 100k — structure reproduces.
9. grid-extent @ 20k/3 turns: :sigma ~3x stabler than :extrema (recorded 4-8x at 200k,
   n-dependent), dropped = 0 for both.

## Leads

### U20-1 — near_round_gaussian_transition.jl:407-411 — only-finiteness gate; every accuracy metric is print-only — severity: medium-low
The script's sole mechanical assertion is
`all(result -> all(isfinite, (max_force_relative_error, max_response_relative_error,
max_core_gradient_error)), results) || error(...)`. None of the accuracy metrics is
compared to a tolerance, and the endpoint-continuity gaps, 6D symplectic residual, and
CPU/CUDA parity are not even inside the finiteness gate. A regression inflating the
transition force error from the recorded 6.1e-12 (doc §10.1) to 1e-3 exits 0. README:14-29
describes it as "validates". Mitigation: suite testset "Near-round Gaussian transition"
(test/runtests.jl:449-570) uses the identical 96-point GL reference with binding
tolerances (5e-11 F64 force/response, 32eps core gradients, 2e-8 symplecticity) at reduced
density — the suite, not this script, is the actual gate. Repro: read lines 393-412; flip
any `_near_round_*` constant and run the script — it still exits 0.

### U20-2 — gaussian_pic_field_validation.jl:17-20 — header claims it exercises the solvers' "real internals"; it exercises local reimplementations — severity: medium-low
Header: "Both solvers are exercised through their real internals: PIC via
`_pic_solve_field` and the hybrid via the same integrated-log Green convolution with the
erf-integrated Gaussian subtracted on the grid...". The script never calls
`_pic_solve_field`, never constructs `GaussianPICPoissonSolver`, and never calls any
`_gpic_*` function: the solve is a local `solve_from_charge` (lines 84-92) and the erf
subtraction profile is the local `gauss_profile` (lines 57-72), a reimplementation of
`_gpic_gaussian_profile!`. Probe 1 shows the two currently agree to 2e-14, so the recorded
numbers are genuine — but a production-side change to the subtraction would not move this
"validation", and docs/theory/gaussian_subtracted_pic_solver.md §9 cites this script as
the measured accuracy basis. Mitigation: suite "GaussianPIC beats PIC toward the
soft-Gaussian kick" (runtests.jl:5314) gates the production `collide!` path
(err_h < 0.03 and err_h < 0.95*err_p), round case only. Same caveat applies to
gaussian_pic_bigaussian_validation.jl (local `cic_profile`, CIC only). Repro: grep the
two scripts for `_pic_solve_field|GaussianPICPoissonSolver|_gpic_` — no hits.

### U20-3 — gaussian_pic_bigaussian_validation.jl:28-29 vs 194 — header output claim wrong — severity: low
Header: "Outputs (under result/): - gaussian_pic_bigaussian_validation_summary.tsv".
The script writes only `result/gaussian_pic_bigaussian_validation.md` (line 194); no TSV
is written. Repro: run the script; list result/.

### U20-4 — spectral_poisson_field_validation.jl — README says it "validates the spectral ... solver"; the production `SpectralPoissonSolver` is never touched; three header/comment inaccuracies — severity: low
(a) README.md:130-135 ("validates the spectral sine-series 2D Poisson solver ... for both
the grid (DST) and grid-free variants"): the script implements all spectral variants as
script-local functions (`spectral_free_field`, `spectral_grid_field`,
`spectral_specderiv_field`, `spectral_onmesh_field`) and never constructs
`SpectralPoissonSolver`. Its LSQ shape calibration (`shape_relerr`, line 215-221)
deliberately erases overall-normalization errors — exactly the class of the fitted-constant
bug recorded in spectral_sine_poisson_solver.md §18 history. Mitigation: suite "Spectral
solver reproduces soft-Gaussian kick" (runtests.jl:~5354) gates production kick RMS at 3%
for both methods, and HighEnergyWeakStrongLimitContract covers the tracking path.
(b) Header line 23: "Two solver variants are implemented" — four are.
(c) Comment lines 246-248 say "Ny ~ 2*domsig*(sx/sy)"; code uses
`ceil(6 * domsig * ratio)` capped at 1200.
(d) Line 259: dead branch `label == "spectral-free"` — that label never occurs in the loop.
Repro: grep the script for SpectralPoissonSolver (no hits); read lines 23, 246-259.

### U20-5 — pic_gaussian_field_validation.jl:77-81 — the kernel-comparison harness recorded in pic_free_space_kernels.md §3.4 is not reproducible from the committed script — severity: low
The §3.4 correction table ("Re-measured with that documented harness ... `:lattice`
before/after") requires green_type variation and 5:1/11:1/25:1 cases at grid 64, but the
script hardcodes `green_type=:integrated` (line 79-80, no env override exists among
OCTOPUS_PIC_VALIDATION_*) and its default cases are ratios 1/1.67/2.5/5/0.4. The doc
itself records that "no harness for the note's original table was ever committed"; the
re-measured table is in the same state. Mitigation: the index-unit-sizing regression and
cap-at-64 boundary ARE pinned by suite testsets "PIC green_type=:lattice"
(runtests.jl:7498) and "The lattice Green box is sized in physical units, not index units"
(runtests.jl:7583: mult (8,8)/(8,40)/(8,64 cap at rho=25), rho→1/rho symmetry, coarse-axis
-ln r spread < 1e-2 which pre-fix was 1.4e-1), and the grid-128 cap-bind open item is
recorded in docs/todo.md:28 and the theory note. The end-to-end field-error-vs-aspect
:lattice comparison remains without any runnable harness or gate. Repro: grep script for
green_type / OCTOPUS_PIC_VALIDATION.

### U20-6 — seven of the ten scripts contain zero binding assertions — severity: low (documented class)
spectral_poisson_field_validation.jl, gaussian_pic_zscan.jl,
gaussian_pic_bigaussian_validation.jl, gaussian_pic_field_validation.jl,
pic_grid_extent_stability.jl, pic_slice_boundary_jitter.jl,
soft_gaussian_pic_comparison.jl print/write TSV only. README frames most as
characterizations (accurate), but: pic_grid_extent_stability's own docstring (lines 32-37)
says `dropped` "must stay at zero for a production setting" yet nothing asserts it
(probe: it is 0 today); gaussian_pic_field/bigaussian's "hybrid never worse than PIC"
claims are ungated in the scripts (suite gate covers one round case). gaussian_pic_zscan
is the only measurement of the hybrid's longitudinal-interpolation/mesh-jump behavior and
is gated nowhere. This is the audit's recurring print-only class; recording for the
auditor's tally rather than as individual defects.

### U20-7 — gaussian_pic_zscan.jl:60,88 — documented override OCTOPUS_GPIC_ZSCAN_NSLICES breaks for values < 4 — severity: trivial
`source_slice = 4` is hardcoded; `slices1.center[4]` / `slices1.indices[4]` BoundsError
when the documented env override sets nslices ≤ 3. Also lines 360-362 read
`summary_rows[3]/[4]` positionally (currently correct). Repro:
`OCTOPUS_GPIC_ZSCAN_NSLICES=3 julia --threads=4 --project=. validation/gaussian_pic_zscan.jl`.

### U20-8 — soft_gaussian_pic_comparison.jl:31-32 — hard CUDA requirement undocumented in header — severity: trivial
The script errors ("CUDA is required for this comparison") on any CPU-only host; neither
the header comment (lines 1-17) nor the README run command mentions the requirement
(README only implies it via "synchronized CUDA timings"). Not runnable in this audit
(no GPU); its contract-helper dependencies (`_contract_backends_available`,
`_strong_strong_contract_base_beams`, `_contract_rep_for_backend`) all exist in
src/contracts/Contracts.jl.

## Sound

- pic_gaussian_luminosity_validation.jl has a genuine binding gate (lines 143-150:
  production `_pic_luminosity` vs independently assembled quadrature, 1e-12) and it passes
  (probe: ≤7e-16 across CIC/TSC, grids 32/128, incl. luminosity_deposit_method override);
  README's description of what is and is not gated is exact; graceful "not evaluated"
  path when padding 0.1 is env-overridden away.
- Every recorded number spot-checked reproduces: gaussian_pic_field grid-48 doc table
  (9.1x/20.6x/17.6x), bigaussian quantile table (exact), spectral domain scaling
  (8.8e-2 / 1.3e-3), jitter internal-ratio structure, grid-extent :sigma-stabler direction,
  zscan common-grid hybrid==pic and vertical non-reduction.
- No circularity in the field validations: references are `gaussian_beambeam_kick`
  (Bassetti-Erskine), itself validated against the independent 96-pt Gauss-Legendre
  fixed-interval integral both in the near-round script and, with binding tolerances, in
  suite testset runtests.jl:449; the bigaussian reference is a 2-BE superposition; the
  luminosity reference is the closed-form Gaussian overlap; zscan's "own-solve" reference
  is intentional (isolates longitudinal reconstruction; documented).
- The `:lattice` Green S14-family protections now live in the suite: per-axis rho-scaled
  multiplier, cap-at-64 binding at rho=25, rho→1/rho symmetry, physical-units box property
  with a bound (1e-2) that the pre-fix defect (1.4e-1) violates, plus the
  equal-extent/realignment invariant testsets (runtests.jl:7629+). Grid-128 cap-bind open
  item is recorded (todo.md:28).
- README's claim that `collide!` now warns on non-zero dropped charge is true
  (`_pic_report_dropped`, src/tasks/strongstrong/pic_cpu.jl:145-150), and the grid-extent
  script's note that it computes its own `dropped` column is accurate.
- RNG hygiene is clean in all ten scripts (philox global seeds, per-case MersenneTwister,
  Halton/quantile deterministic sources); no inter-section order dependence found.
- All README/header run commands, env-override names, and output paths verified against
  the code (single exception: U20-3).
- No bitrot: all nine CPU-runnable scripts execute end-to-end against current internals
  (probes 4-9); the zscan exercises the production `_gpic_solve_drifted_field!` path as
  its header claims, correcting the earlier raw-PIC attempt exactly as described in
  docs/todo.md item 4a.
