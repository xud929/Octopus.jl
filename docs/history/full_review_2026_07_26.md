# Full Project Review — 2026-07-26

A complete line-by-line review of the source tree, a cross-file consistency
audit (code, examples, tests, validation scripts, markdown), re-derivation of
every code-facing formula in the theory notes, a full contract/test run on CPU
and CUDA, and completion of the actionable items in `docs/todo.md`. The
simulation checks use the strong-strong example beam parameters
(`examples/strong_strong_tracking.jl`: 10 GeV e⁻ vs 275 GeV p, EIC-like,
12.5 mrad crab crossing, 15 normal-quantile slices).

## 1. Verification status

All green, on the RTX 4500 Ada workstation (Julia 1.12.4, 8 threads):

- `test/runtests.jl`: **passes** before the session's changes (baseline) and
  after every change, including 39 new assertions (non-finite fail-fast, CPU +
  CUDA) and the extended CUDA `:quadratic` parity checks.
- `validate_element_metadata()`, `validate_configuration_metadata()`: pass.
- `validate(PublicConfigurationEffectivenessContract())`: **passed** —
  configuration reaches CPU, fused CUDA, and CUDA PIC consumers.
- `validate(ElementTrackingBackendConsistencyContract(...))` on a line
  containing crab dispersion, a 2-harmonic crab cavity, the Lorentz boost pair,
  a chromaticity kick, and stochastic lumped radiation: CPU/CPU residual 0.0;
  CPU/CUDA passes at `atol=rtol=1e-10`.
- `validate(StrongStrongGaussianBackendConsistencyContract())` and
  `validate(StrongStrongPICBackendConsistencyContract(...))` (CIC wavefront and
  TSC sequential, cache-history comparison included): **passed**.

## 2. Line-by-line source review (37 files, ~21k lines)

**No correctness bug was found in `src/`.** The physics kernels were re-derived
independently and match:

- `linear_maps.jl` / `linear6d.jl`: symplecticity of CrabDispersion,
  MomentumDispersion, XYCoupling (modes A and B), and the R-matrix verified by
  canonical 2-forms; the optics-form composition
  `ζ₂η₂R₂·B·R₁⁻¹η₁⁻¹ζ₁⁻¹` and both normalization constants
  (`g² = 1 + r₁r₄ − r₂r₃` vs `g² = 1 − C₁C₄ + C₂C₃`) are each internally
  consistent.
- `lorentz_boost.jl`: the Hirata boost satisfies the
  `h² − 2(1+p_z)h + p_x² + p_y² = 0` self-consistency identity after the
  forward map, and `RevLorentzBoost` composes with `LorentzBoost` to the exact
  identity (verified algebraically, both position and momentum parts).
- `chromaticity_kick.jl`: `z += 2π(ξxJx + ξyJy)` is the exact canonical term
  for a `pz`-dependent phase advance; the dispersion/coupling `_inverse`
  helpers compose exactly (the antisymmetric cross terms cancel).
- `radiation.jl`: the excitation coefficients reproduce the equilibrium
  covariance `(σ², σ²(1+α²)/β², −σ²α/β)` exactly.
- `strong_beam.jl` / `strong_beam_track.jl`: Bassetti-Erskine via Faddeeva
  (quadrant reflection, `σx≶σy` swap) correct; the counter-propagating
  centroid sign and the `¼(H:A_u)` transport verified against the theory note
  (Section 3); CPU and CUDA kick helpers are line-identical in math.
- `pic_cpu.jl`: integrated Green kernel matches the closed-form antiderivative
  `(ln r²−3)xy + x²atan(y/x) + y²atan(x/y)` with the `−1/(2hxhy)` cell
  average; CIC/TSC weights re-derived; origin alignment (integer-cell for
  `:integrated`/`:lattice`, half-cell for `:standard`) consistent; quadratic
  Lagrange weights sum to 1 (transverse) and 0 (longitudinal).
- `gaussian_pic.jl`: every erf moment integral (m₀/m₁/m₂ against the CIC tent
  and TSC kernel), the c_k recursion, the assignment-weighted moments, the
  mean-derivatives g′/g″, the ½N_s normalization, and the coupled conditional
  expansion (λ = b/a, s² = d − b²/a) match the theory note exactly.
- `spectral.jl` / `spectral_cuda.jl`: derived scale constants (−2π grid, +4π
  grid-free), the Φ_g ½ factor, and the 7-transform CUDA solve verified.
- `pic_cuda.jl` / `gaussian_pic_cuda.jl` (fully read): all kernels match the
  verified CPU math; plane-indexing layouts (4-plane standard, 6-plane node)
  mapped and consistent.

Minor observations (recorded, not bugs):

- `_pic_cic_weights` at exactly `u == n−1` deposits its unit weight one cell
  left of the last node (the index clamps but the fraction is not recomputed).
  Measure-zero and unreachable under `:extrema` sizing with the 1.5-cell
  margin.
- `_pic_luminosity!` sums the density product over `[1:nx, 1:ny]` of an
  `(nx+1)×(ny+1)` node grid; TSC can place a boundary sliver of weight on the
  skipped last row/column. Negligible.
- `LumpedRad` tracked with an explicit `Damping6DMap()` applies damping even if
  `is_damping=false` (the method tag wins). Semantics judged intentional.

## 3. Theory-note verification

Every boxed, code-facing formula in the seven `docs/theory/` notes was
re-derived and compared with the implementation; **all match**, including:

- `beam_beam_longitudinal_kick.md`: `Δp_z = ½F·C_u + ¼H_U:A_u`
  (`A_u = B₀+B₀ᵀ+2uQ₀` at `u=−S` equals the code's `2(b−Sq)` forms), the
  principal-axis equivalent with the `−½θ_u(F̂xŷ−F̂yx̂)` rotation term, the
  chromatic drift (`Φ = √(1−q/2P²)−1`, `p_z += PΦ`), the exact-Hamiltonian
  drift (the note's `S = (z−z_*)p_s/(2p_s+H)` equals the code's implicit
  `z₂/(1+rr)` form), and the slingshot decomposition.
- `weak_strong_6d_model.md`: conditional-Gaussian slope `Σ_wz/Σ_zz` and
  covariance match `_conditional_transverse_gaussian`.
- `gaussian_subtracted_pic_solver.md`: Sections 5–7 formula-for-formula.
- `slice_longitudinal_interpolation.md` Section 7: the quadratic weights match
  including sign (the note's leading minus against the code's negated
  bracket); the two-node form is the boxed expression at `t=½`.
- `spectral_sine_poisson_solver.md`, `pic_free_space_kernels.md`,
  `node_interaction_grid.md`: scale constants, kernel integrals, and the
  three-solve node structure all verified.

One stale line-number citation fixed
(`slice_longitudinal_interpolation.md` → `_pic_interpolate_kick`).

## 4. Cross-file consistency audit — findings and fixes

All found issues were fixed in this session:

| severity | location | issue |
|---|---|---|
| WRONG | `test/examples/strong_strong_tracking.jl` | unconditional print of `resolved_luminosity_deposit_method` crashed the documented `OCTOPUS_SOLVER=spectral`/`gaussian` runs after tracking; now guarded by `hasproperty` |
| WRONG | `test/examples/*` headers | claimed outputs in `result/`; they write to `test/result/` — headers corrected |
| STALE | `docs/current_runtime.md` (4 sites) | `OCTOPUS_*` variables attributed to `examples/strong_strong_tracking.jl`, which reads none; re-pointed at the `test/examples/` harness |
| STALE | `validation/strong_strong_pic_extreme_benchmark.jl` | same attribution; corrected |
| STALE | `README.md` | feature list named only two of the four solvers |
| MINOR | `examples/strong_strong_tracking.jl` | "all solvers share `grid`" — soft-Gaussian is grid-free; reworded |
| MINOR | `validation/pic_gaussian_field_validation.jl` | machine-specific absolute Julia path in the run command |
| MINOR | `validation/slice_interpolation_emittance_growth.jl` | header omitted `OCTOPUS_EMIT_GRIDMODE` |
| MINOR | `validation/README.md` (2 sites) | mixed path base; "(128,1024) is the production setting" label predating the `(127,383)/8` recommendation |

Everything else checked clean: all example/test/validation API usage against
source signatures, all ~40 `OCTOPUS_*` variables, `validation/README.md`
coverage (29 scripts), `docs/README.md` and `docs/public_api.md` link/name
completeness, `docs/registry_snapshot.md` against live exports, and
`Project.toml` against actual imports.

## 5. Todo items completed this session

### 5.1 Non-finite coordinate detection (N1–N4)

Implemented as fail-fast detection at the reduction chokepoints on both
backends (see the closed section in `docs/todo.md` for the design record):
`isfinite` checks on the O(1) results of reductions that already scan every
coordinate — PIC bounds on every route, slicing boundaries (earliest `z`
scan), soft-Gaussian slice moments (with a device poison flag on the fused
CUDA wavefront path, read back with the existing once-per-turn luminosity
transfer), hybrid bounds, and the spectral Dirichlet box. On failure the slice
is scanned once and an `ArgumentError` names the collision label, turn, slice
pair, particle index, and coordinates. Quarantine was deliberately not added
(it would change the kick normalization); the luminosity-schedule `NaN`
sentinel is untouched and covered by a test. 21 CPU + 18 CUDA assertions.

### 5.2 CUDA `slice_interpolation=:quadratic` on the batched routes

The former "main remaining implementation gap". Ported as an additive
6-planes-per-pair path (L/M/R per direction, per-plane Green stack — the
`:node` port's mechanism; the 4-plane production functions are untouched) on
the indexed wavefront, gathered wavefront, and sequential batched-FFT routes.
CPU parity 2–4e-11 (coordinates) and ~5e-16 (luminosity) on all three; the
non-batched async route throws. Measured cost on the indexed wavefront route
(640k/256k, 15 slices, grid 128, collision + one-turn maps): linear
0.137 s/turn → quadratic 0.240 s/turn, **1.75×**, down from the 2.87× of the
sequential-only support.

### 5.3 Per-turn re-slicing jitter (quantified)

New `validation/pic_slice_boundary_jitter.jl`. Headline: the extrema-pinned
**outermost boundaries jitter at 0.13–0.17 σ_z per turn** under both slicing
methods — ~40× the internal-boundary jitter — modulating the outer slices'
widths and longitudinal kick scale every turn. Internal boundaries:
`:normal_quantile` is 1.6× (electron) to 13× (proton) stabler than
`:equal_area`. Numbers and the follow-up (a robust outer-boundary estimator as
an emittance-growth arm) are recorded in `docs/todo.md` item 5.

### 5.4 Hybrid z-scan through its own solve path (4a)

New `validation/gaussian_pic_zscan.jl`, exercising
`_gpic_solve_drifted_field!` plus the analytic add-back with production
blending. The standing prediction — "the boundary jump should scale with the
PIC'd residual" — is **refuted for the vertical component**: on identical
per-slice-pair meshes the jump falls 2.8× in x but only 1.10× in y against a
predicted ~11× (residual fraction 0.088), because the residual at these
statistics is mostly shot noise, whose mesh dependence does not scale with the
smooth-residual amplitude. On a common grid the hybrid's longitudinal
interpolation error equals pure PIC's (the analytic term carries the total
field's z-curvature). Details in `docs/todo.md` 4a.

## 6. Files changed

- `src/tasks/strongstrong/interface.jl` — `_nonfinite_coordinate_error`,
  `_pic_slice_context`, `:quadratic` CUDA docstring note.
- `src/tasks/strongstrong/pic_cpu.jl` — chokepoint checks; `:quadratic` route
  gate rewritten for the new CUDA support.
- `src/tasks/strongstrong/slicing.jl`, `gaussian.jl`, `gaussian_pic.jl`,
  `spectral.jl` — chokepoint checks (`_gaussian_moments_finite` helper).
- `src/tasks/strongstrong/pic_cuda.jl` — chokepoint checks (incl. fused-moment
  poison flag); the 6-plane `:quadratic` solve/kick/driver additions.
- `src/tasks/strongstrong/gaussian_pic_cuda.jl`, `spectral_cuda.jl` —
  chokepoint checks.
- `test/runtests.jl` — two non-finite testsets; `:quadratic` CUDA testset
  extended from throw-assertions to parity assertions on the new routes.
- `validation/pic_slice_boundary_jitter.jl`, `validation/gaussian_pic_zscan.jl`
  — new; registered in `validation/README.md`.
- Documentation fixes listed in Section 4; `docs/todo.md` status updates;
  `docs/README.md` index updates.
