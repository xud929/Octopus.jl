# TODO

## Slice longitudinal interpolation (from the 2026-07-25 z-scan)

Measurements and rationale:
[`docs/history/slice_longitudinal_interpolation_record.md`](history/slice_longitudinal_interpolation_record.md);
derivation: [`docs/theory/slice_longitudinal_interpolation.md`](theory/slice_longitudinal_interpolation.md).

1. ~~**Per-slice-pair interaction grid resizing.**~~ **DONE (2026-07-25)** as
   `interaction_grid = :slice_pair|:source_slice`. Sharing one mesh per (source
   slice, direction) drops the transverse boundary jump from `~1e-3` to `~2e-9`
   relative — the ideal common-grid floor — lowers emittance growth on both beams,
   and is 10-39% *faster* (Green cache 450 -> 30 entries). CPU only; CUDA throws.
1b. **`:source_slice` does not generalize — superseded by the grid-determination
   program below.** The shared mesh must cover the source slice drifted across the
   field beam's *entire* longitudinal range, and a drifted slice grows as
   `sigma*sqrt(1+(s/beta*)^2)`. The drift span comes from the **field** beam's
   bunch length, the blow-up from the **source** beam's optics, so the governing
   ratio is `sigma_z,field / beta*,source` — and both directions run every turn.
   Measured at 15 slices on the real EIC pair:

       proton -> electron   ratio 0.10   hy 1.26-1.32
       electron -> proton   ratio 1.07   hy 2.70

   i.e. 2.7x coarser vertical cells (~7x worse `O(h^2)` field error) in one of the
   two production directions. Synthetic sweep: `hy` = 1.26 / 1.33 / 1.76 / 3.06 /
   5.87 at ratio 0.12 / 0.36 / 0.89 / 1.79 / 3.57. Arm F still showed reduced
   emittance growth *with* that penalty present, so the trade was net positive at
   `grid=(64,64)`, but it is unverified at production grids.

   An earlier plan here proposed **bounded-group sharing** (one mesh per `G`
   adjacent field slices). That is **withdrawn**: it only reduces the jump from
   every slice transition to every `G`-th, and node indexing (phase 4 below)
   removes it exactly at the same cost. Keep `:source_slice` as a
   weak-hourglass-only option until the program below lands.
2a. ~~**Why `:node` costs 3.52x at production.**~~ **PROFILED AND PARTLY FIXED
   (2026-07-26).** Decomposition (all at the production point, using
   `:slice_pair` and `:quadratic` on the same slow route to separate terms):
   route +0.4148 s/turn (48% of the gap), third solve +0.1754 (20%), node mesh
   building +0.2678 (31%).

   Mesh building fixed: the builder made `nb` passes over the source (one per
   node) and scanned each field slice twice. Now one pass each. CUDA production
   **1.1988 -> 1.0026 s/turn**. CPU: `collide!`-only at 200k/grid64 gave 0.71x,
   but the **full lattice at 50k/grid64 gives 1.18x** -- the microbenchmark was
   an artefact and `:node` is *not* faster on CPU at that size. The mechanism is
   real (baseline recomputes bounds per pair, N^2; node per source slice, N) but
   it only wins when particles per slice are high enough for bounds to dominate
   the solve. The "1.5x floor" claim is retired; so is "CPU node is faster".

   Also fixed a correctness issue found by the parity test: lazy per-node building
   sized meshes from different source states (the source is kicked between pairs).
   All of a source slice's nodes are now built together from one state.

   **Remaining gap is the route** -- see 2b.
2b. **Extend the CUDA wavefront route to carry per-node meshes and a third field
   plane — now the highest-value remaining optimization.** Measured at the
   production point (2.56M/1.024M, 15 slices, grid 128, CUDA indexed wavefront,
   200 turns): base 0.3408 s/turn, `grid_quantize` 0.3379 (0.99x), `:TSC` 0.3668
   (1.08x), but `:quadratic` **0.9310 (2.73x)**. The penalty is the *route*, not
   the extra solve: `:quadratic` and `:node` are implemented only on the CUDA
   sequential non-async path, which is itself ~2.5x the wavefront default. Until
   the wavefront route supports them, neither is affordable in production on GPU.
2. ~~**CUDA `slice_interpolation=:quadratic`.**~~ **PARTIALLY DONE
   (2026-07-25)**: implemented on the CUDA sequential, non-batched-FFT route
   (`batch_mode=:sequential`, `cuda_async=false`) with 7.5e-16 CPU parity.
   **Still open: the wavefront and batched-FFT routes.** They pack two field
   planes per slice-pair direction (`nplanes = 4 * npairs`, with `÷2`/`÷4` plane
   arithmetic in the deposit, solve, Green and luminosity kernels) and would need
   that indexing generalized to three. Until then CUDA `:quadratic` costs **2.87x**
   the production wavefront default (the supported route is itself 2.48x), so a
   CUDA user is better off on the CPU path (+5%). This is the main remaining
   implementation gap.
3. ~~**Does `:TSC` gain more than `:CIC` from `:quadratic`?**~~ **ANSWERED
   (2026-07-25): emphatically yes, and the two are multiplicative.** `:quadratic`
   gains 5.2x with `:CIC` but **105-188x** with `:TSC`, and the longitudinal
   boundary jump falls from 55% of peak to 0.1% (580x) instead of 13x. The `:CIC`
   result was measuring the deposition floor, not the interpolation order.
   `:quadratic` without `:TSC` captures about a twentieth of the available gain.
4. ~~**Multi-turn emittance growth.**~~ **MEASURED (2026-07-25)**, see the history
   record. Six arms, 4 seeds each. `slice_interpolation=:quadratic` does **not**
   resolve above seed noise (t=-0.09), and **neither does doubling the slice
   count** at 4x the cost (t=+1.56). `deposit_method=:TSC` (t=-6.93) and
   `interaction_grid=:source_slice` (t=-3.44 electron, -2.79 proton) both do.
   Conclusion: growth is driven by transverse field noise and mesh discontinuity,
   not by longitudinal reconstruction error. **This retires the premise behind
   the three-node work** — keep `:quadratic` as a field-accuracy tool only.
5. **Per-turn re-slicing jitter.** Boundaries are rebuilt every turn from the
   instantaneous distribution, and under `:equal_area` the outermost boundaries
   are pinned to single extreme macroparticles. This converts a deterministic
   interpolation error into a fluctuating one. Not yet quantified; the z-scan
   freezes the slicing by construction and so cannot see it. Given that the two
   options which *did* move emittance growth are both about field smoothness
   rather than interpolation order, this is now the most promising untested
   mechanism. Distinct from the grid-determination program below: that concerns
   the *transverse* mesh, this concerns the *longitudinal* slice boundaries.
6. **Duplicate boundary-plane solves** — folded into phase 4 of the
   grid-determination program below, which is what unlocks it.

## Interaction-grid determination (the smoothness program)

The transverse mesh is currently a function of the *slice index*, while the
physics it discretizes is smooth in `z`. That is the root cause of the
`~1e-3` transverse kick discontinuity at every slice boundary, and of the
turn-to-turn grid jitter. Two independent defects feed it:

- **Where the grid sits** depends on the field particle's slice, so it is a step
  function of `z` (phase 4 fixes this).
- **How big the grid is** is set by a *sample extremum* (`min`/`max` over
  macroparticles), which is `O(1)`-noisy: for `n` per slice the maximum is
  `sigma*sqrt(2 ln n)` with Gumbel fluctuation `sigma/sqrt(2 ln n)`, about **6-7%
  of a 4-sigma box** from shot noise alone, plus a systematic drift with slice
  population (`n=2000 -> 3.9 sigma`, `n=4000 -> 4.07 sigma`). Phases 0-3 fix this.

Run the phases in order; phase 1 is a hard prerequisite for phase 2.

### Phase 0 ~~(open)~~ **DONE (2026-07-26)** — the premise, measured

`validation/pic_grid_extent_stability.jl`. Relative variation of the mesh box,
200k/beam, 15 slices, 8 turns:

    estimator   slice2slice x/y        turn2turn x/y        dropped
    :extrema    5.3e-2 / 5.1e-2        5.2e-2 / 4.8e-2      0
    :sigma      6.5e-3 / 1.3e-2        1.0e-2 / 1.4e-2      0
    :quantile   7.2e-2 / 6.6e-2        6.9e-2 / 6.2e-2      0

The predicted ~6-7% extrema jitter is confirmed. `:sigma` is **4-8x stabler**,
against a prediction of >=10x -- the prediction was optimistic.

### Phase 1 ~~(open)~~ **DONE (2026-07-26)** — out-of-range deposition

Both stencils on both backends now return **zero weights** outside `[0, n-1]` or
for non-finite input, instead of clamping the index while keeping the weight (a
spurious boundary charge sheet) or throwing `InexactError` (CPU) / poisoning the
whole charge grid through the atomic add (CUDA). The CPU/CUDA divergence on
non-finite coordinates is closed. Dropped particles are counted in
`_PICCPUWorkspace.dropped`, never silent. Default path bit-identical: the branch is
unreachable under `:extrema` sizing.

This does **not** close the wider non-finite task below — it makes robust sizing
safe, but detection, reporting and policy for diverging particles remain open.

### Phase 2 ~~(open)~~ **DONE (2026-07-26)** — `grid_extent`

`grid_extent = :extrema` (default, bit-compatible) or `:sigma` with
`grid_extent_sigma = 6.0`. `:sigma` addresses a *different* breaker than `:node`:
node indexing removes the slice-boundary jump exactly but does nothing about
turn-to-turn mesh jitter, which `:sigma` cuts 5x.

**`:quantile` was implemented, measured and removed.** At a coverage target tight
enough to avoid charge loss the target rounds to *all* particles for realistic
slice populations, so it degenerates to the extremum and adds histogram
quantization noise -- measured worse than `:extrema`. Its useful regime needs loose
coverage, which the charge-loss arithmetic rules out (dropping `f` of charge at
radius `R` costs `~ f*(sigma/R)`; `f=1e-3` at `5 sigma` is `2e-4`, the same order
as the discontinuity being removed). Shipping a dominated option would have been
speculative surface.

### Phase 3 ~~(open)~~ **DONE (2026-07-26)** — `grid_quantize`

Snaps the extent to a `2^q` ladder and origins to whole cells; `0` disables
(default, bit-compatible). A mesh differing by 1% from its neighbour produces
essentially the same jump as one differing by 50% -- only *identical* meshes
cancel. Distinct meshes across 225 slice pairs:

    :extrema q=0     225        :extrema q=1/8    29
    :sigma   q=0     225        :sigma   q=1/8     7

The two compose: `:sigma` alone collapses nothing, quantization alone gives 29,
together 7.

### Phase 4 — index the grid by the interpolation node ~~(open)~~ **DONE (2026-07-25)**

Shipped as `interaction_grid = :node`. Default unchanged and bit-identical to
HEAD (luminosity, coordinate hash and Green-cache counters all match exactly).
Results are in the theory note Section 10.4 and the history record Section 3.4.

- Transverse boundary jump `1.0-1.6e-3` -> **`1.1e-9`** (roundoff floor).
- Cell coarsening **1.11x / 1.05-1.08x** against per-slice-pair meshes, with no
  hourglass sensitivity — against `:source_slice`'s up to **2.70x**.
- Turn time at 1M/beam, 15 slices, grid 128: **0.64x** (36% *faster*), because
  each node's Green FFT is built once and reused by both adjacent slices.
- **`:node` supersedes `:source_slice` on every axis.**

**The longitudinal trap (recorded so it is not re-discovered).** Putting each of a
slice's two planes on its own node mesh makes the longitudinal jump explode to
**14x** the peak kick. `Delta p_z ~ phi_L - phi_R` is a small difference of large
numbers whose discretization error only cancels within one mesh. The gauge-offset
hypothesis was tested and refuted (relative spread 1.51 across transverse
positions, so it is not a constant). The fix is a third solve: node `s+1` is
re-solved on node `s`'s mesh for the longitudinal difference, and each node mesh
must cover the next node's drift as well as its own.

**Residual, now the leading term:** continuity breaker #3 — the shared node is
solved once per adjacent slice with the source kicked in between. Measured `Dpx`
2.2e-5, `Dpy` 7.6-8.1e-5, i.e. a `~1e-4` floor roughly 40x below the mesh jump it
replaced. **This is the next thing to attack.**

Still open from this phase:

- **4a. Z-scan the hybrid solver** — attempted and **inconclusive**: the quick
  harness called the raw PIC solve path and never exercised
  `GaussianPICPoissonSolver`'s control-variate subtraction, so it measured the PIC
  jump twice. Needs to go through the hybrid's own solve path. The prediction
  stands untested: the jump should scale with the PIC'd residual, so the hybrid
  should already show a much smaller one.
- ~~**4d. CUDA `:node`**~~ **DONE (2026-07-26)** on the sequential non-async route
  (`batch_mode=:sequential`, `cuda_async=false`), CPU parity 9.5e-16 and luminosity
  parity 2.7e-16. The wavefront and batched-FFT routes assume one mesh per slice
  pair and throw. Extending them is the same reindexing job as CUDA `:quadratic`.
- **4e. Node-solve caching** — with node indexing in place, caching a node's solve
  for both adjacent slices would make `C^0` exact including the source state *and*
  cut solves. Gated on the residual above proving worth removing.

### Metrics and acceptance (all phases)

- boundary jump -> `validation/slice_longitudinal_zscan.jl` (already has a
  grid-mode dimension)
- field error vs a fine reference -> `validation/pic_gaussian_field_validation.jl`
- does it matter -> `validation/slice_interpolation_emittance_growth.jl`, adding
  one arm per estimator

**Acceptance bar, learned the hard way:** measure **both collision directions**
(the `:source_slice` cost was understated ~2x by testing only one), compare
against the grids production actually builds rather than a convenience reference,
and confirm the field error did not degrade while the jump improved.

## Non-finite coordinate detection (independent task)

Nothing in tracking or the Poisson solvers checks for `NaN`/`Inf` coordinates, and
the two backends disagree about what happens when one appears. This is a
correctness-and-safety item in its own right, but it should land **with phase 1 of
the grid-determination program**, because both are the same question — what to do
with a particle that is not representable on the mesh — and both live in the same
deposition code path.

**What happens today**

- **CUDA silently poisons.** `_cuda_pic_cic_weights` clamps `base` into
  `[1, n-1]`, so there is no out-of-bounds write; but the weight
  `min(max(u - floor(u), 0), 1)` stays `NaN` and flows into
  `CUDA.@atomic charge[ix,iy] += NaN`. One bad particle turns the whole charge
  grid `NaN`, hence the field, hence every particle in that slice pair — and it
  spreads on later turns.
- **CPU throws.** The same input reaches `floor(Int, NaN)` in `_pic_cic_weights`
  and raises `InexactError` from deep inside a kernel, with no indication of which
  particle, slice, or turn.
- So identical physics **crashes loudly on CPU and silently corrupts on GPU.**
  That divergence is the strongest argument for doing this.
- Downstream, reductions launder the failure: luminosity, `beam_statistics` and
  `MomentObserver` all produce `NaN` with no indication of the origin, and a run
  can emit `NaN` for thousands of turns without stopping.

**Design constraints**

1. **`NaN` is already a sentinel.** `compute_luminosity ? ... : T(NaN)` means
   "not evaluated this turn" and `StrongStrongTask` omits those rows. Detection
   must therefore key on **coordinates**, not on reduction outputs, or it will
   fire on every unscheduled turn. Do not repurpose the sentinel.
2. **Near-zero hot-path cost.** Fold `isfinite` into reductions that already scan
   every coordinate — the grid-bound `min`/`max` in `_pic_interaction!` and
   `_pic_prepare_interaction`, and `_slice_transverse_moments`. No extra pass.
3. **Backend parity.** Whatever the policy, CPU and CUDA must do the same thing;
   a CPU/CUDA consistency test should cover the non-finite case explicitly.

**Plan**

- **N1. Detect at the existing chokepoints.** Add `isfinite` to the bound and
  moment reductions. On failure report turn, beam, slice, particle index and which
  coordinate — not just "NaN encountered".
- **N2. Decide the policy** and make it explicit configuration rather than
  emergent behaviour: fail fast (default) versus quarantine. Quarantine implies a
  **lost-particle concept**, which the code does not have today and which is a
  real design change: `_pic_kbb1`/`_pic_kbb2` normalize by `length(beam.rep)`, so
  removing particles changes the kick scale and the luminosity normalization.
  Do not add it casually.
- **N3. Optional periodic check.** A full `isfinite` sweep every `n` turns
  catches divergence early at negligible amortized cost, for runs where the
  chokepoint checks are considered too weak.
- **N4. Tests.** Inject a non-finite coordinate and assert it is caught at the
  right place with a useful message, on **both** backends, plus a test that the
  luminosity sentinel is not mistaken for a failure.

Related: phase 1 of the grid-determination program replaces the silent
out-of-range clamp with a defined policy and a counter. `NaN` handling should
reuse that same mechanism and counter rather than inventing a second one.

## New items from the 2026-07-24 Poisson-solver review

See [`docs/history/poisson_solver_review_2026_07_24.md`](history/poisson_solver_review_2026_07_24.md)
for the measurements behind each of these.

1. ~~**Fourth-order gradient in `_pic_field!`.**~~ **DONE (2026-07-25)** as the
   opt-in `field_derivative=:second|:fourth`; `:second` is the default and is
   bit-identical to all earlier results. CPU plus all three CUDA kernels, with
   CPU/CUDA parity tests for both settings. Gives ~1.6x lower median field error.
   **It does not reduce multi-turn emittance growth** (Section 11 of the review):
   it removes systematic truncation error, not shot noise. Enable it for
   field-accuracy work, not for dynamics.
   *(An earlier version of this list recommended a Vico-Greengard-Ferrando kernel
   here as the highest-value item. That is **withdrawn for round and mild-aspect
   beams**: swapping the integrated log kernel for a node-sampled one changes the
   round-beam field error by 0%, so the kernel is not the bottleneck there. VGF
   remains worth evaluating for high-aspect-ratio beams, where the kernel does
   matter — 3.1x at 25:1 — but Octopus's integrated kernel already captures most
   of that gain. See Section 3.3.)*
2. ~~**Measure multi-turn artificial emittance growth per solver and per grid.**~~
   **DONE (2026-07-25)**, Section 11 of the review: 1000 turns = 10 electron
   damping times at production statistics, with the undamped proton beam as the
   noise integrator and a no-collision control. Headline: `grid=(64,64)` is the
   only configuration still growing at the end of the run; everything at
   `grid >= 128` is indistinguishable. **The single-seed caveat is now resolved:**
   Section 18 repeated the configurations the recommendation depends on at three
   seeds. The conclusions survive the error bars -- PIC(64,64) is separated by
   ~30 sigma (1.29 +- 0.18 against 0.632 +- 0.021) and is the only run still
   rising, while PIC(128,128) and GaussianPIC(64,64) remain indistinguishable
   (0.632 +- 0.021 against 0.653 +- 0.016, within one combined sigma), so the
   recommendation to prefer PIC(128,128) on cost stands.
   Original text follows.
   Measure multi-turn artificial emittance growth per solver and per grid.
   The production case is many turns in a ring, where correlated PIC noise drives
   artificial emittance growth. Single-turn field error (the only thing currently
   validated) is not the right figure of merit. This is the highest-value *physics*
   follow-up, and it is the measurement that would confirm or refute the hybrid
   solver's main selling point.
3. ~~**CPU indexed-slice path.**~~ **CLOSED NEGATIVE (2026-07-25).** Implemented
   as a `cpu_indexed_slices` flag, verified bit-identical, measured **4-8%
   slower** at every size and grid, and reverted. Each slice's arrays are
   traversed several times per interaction, so gathering pays one indirection and
   then gets contiguous access, while views pay it on every access. CUDA benefits
   (2.3x) because there the gather is a separate kernel launch and coalescing
   dominates. The earlier "~23% of a CPU turn" estimate is withdrawn. See
   Section 19 of
   [`poisson_solver_review_2026_07_24.md`](history/poisson_solver_review_2026_07_24.md).
4. ~~**Add `luminosity_schedule` to `SpectralPoissonSolver`.**~~ **DONE** (CPU +
   CUDA, with a 32-assertion effectiveness test at the consumer boundary).
   `GaussianPoissonSolver` was deliberately left without it: its luminosity is a
   by-product of the per-particle kick and costs 0%, so the knob would be a no-op.
   Documented as intentional in `?AbstractPoissonSolver`.

5. ~~**Document that TSC is the right deposition for the hybrid.**~~ **DONE** in
   the `GaussianPICPoissonSolver` docstring. Original text:
   Document that TSC is the right deposition for the hybrid. `gpic_TSC` beats
   `gpic_CIC` at nearly every grid and aspect ratio, while `pic_TSC` never beats
   `pic_CIC`. Neither the docstring nor the theory note mentions this.
6. ~~**Strengthen the `green_type=:standard` warning.**~~ **DONE** in the
   `PICPoissonSolver` docstring. Original text:
   Strengthen the `green_type=:standard` warning. At 25:1 aspect ratio its p95
   field error is 17x worse than `:integrated`. The docstring currently only calls
   `:integrated` "the robust default".
7. ~~**Guard the spectral Dirichlet box against drifted sources.**~~ **DONE
   (2026-07-25)**: `_spectral_box_drifted` bounds the drift by
   `(max|z1| + max|z2|)/2` and is used by both the CPU and CUDA 6D paths. It can
   only enlarge the box and is a no-op at the recommended `domain_factor=8`, so
   the production configuration is unchanged. Covered by a test.

## Gaussian-Subtracted PIC Solver (Hybrid Analytic-PIC)

**Status (2026-07-24): CPU and CUDA both complete and validated.**
`GaussianPICPoissonSolver{T} <: AbstractPoissonSolver`
(`src/tasks/strongstrong/gaussian_pic.jl`) composes `PICPoissonSolver` plus
`margin_sigma`, `neutralize`, `coupling_tol`, auto-registers, and reuses the PIC
CPU leaf helpers (grid, integrated-log Green FFT + slice-pair cache,
interpolation, luminosity). It implements the erf-integrated Gaussian subtraction
(CIC + TSC), the exact Bassetti-Erskine transverse add-back, and the
covariance-transport + centroid longitudinal add-back. The full `test/runtests.jl`
suite passes with three added testsets; `validation/gaussian_pic_field_validation.jl`
shows the systematic field-accuracy gain (hybrid at grid 48 matches/beats PIC at
128; 9-20x median at coarse grids, 2.6-4.1x at 128). The method and formulas are
in [`gaussian_subtracted_pic_solver.md`](theory/gaussian_subtracted_pic_solver.md).

**CUDA path complete and optimized (2026-07-24).**
`src/tasks/strongstrong/gaussian_pic_cuda.jl` implements the indexed wavefront
path (default, no gather/scatter) plus a non-indexed wavefront fallback and a
sequential reference path. It reuses the PIC batched-FFT solve (with an injected
per-plane Gaussian subtraction), the soft-Gaussian batched device moment kernels,
and the batched-bounds prepare; the kick adds the Bassetti-Erskine field per
particle. **CPU/CUDA bit-parity** (lum ~2e-16, coords ~5e-13; a "CUDA GaussianPIC
solver matches CPU" testset covers both wavefront paths and 6D on/off).
Performance (512k/256k, RTX 4500 Ada): GaussianPIC@128 **0.37 s (1.6x PIC)**,
GaussianPIC@64 **0.28 s (1.2x PIC@128) with equal-or-better accuracy** — since the
hybrid's systematic accuracy is grid-independent (hybrid@64 ≈ PIC@128). See
`docs/history/strong_strong_gaussian_pic_optimization_history.md`.

**Scaling caveat (2026-07-24 review).** Those ratios were measured at **512k/256k**
macroparticles, one fifth of the production case. The hybrid's extra cost is the
per-field-particle Bassetti-Erskine add-back, which scales with the particle count
while the grid work does not, so the ratio degrades with beam size. Re-measured at
the full production case (2.56M/1.024M) over 200 turns, the hybrid is ~2x the PIC
time, not 1.2-1.6x. The accuracy claim (hybrid@64 ≈ or better than PIC@128) is
independently confirmed. See
[`poisson_solver_review_2026_07_24.md`](history/poisson_solver_review_2026_07_24.md).

**Status (updated 2026-07-25): complete.** The coupled (rotated) subtraction
branch (`coupling_tol < Inf`) is implemented and validated on the CPU path **and
on the default CUDA route** (`batch_mode=:wavefront`, `cuda_indexed_wavefront=true`),
with CPU/CUDA parity at 3.5e-17; the two non-default CUDA routes raise rather than
silently running the uncoupled subtraction. Steps 1-8 below are DONE.

Also fixed in the same pass: GaussianPIC's CUDA routes silently ignored
`green_cache`, so the CPU expanded each slice-pair grid by
`1 + slice_pair_green_growth` and CUDA did not, costing backend reproducibility at
the *default* settings. See Section 21.2 of the review. Both remaining sub-items are now closed:
GaussianPIC CUDA phase timing is implemented (with `gpic_moments`/`gpic_profiles`
counters), and it shows the host-side erf profile build is only **3.3%** of
interaction time against the kick's 36%, so tuning it is not worthwhile. See
Section 22 of the review.

Key files to touch (mirror the existing PIC structure):
`src/tasks/strongstrong/interface.jl` (solver struct + option schema),
`src/tasks/strongstrong/pic_cpu.jl` (`_pic_interaction!`, deposition, field
solve, interpolation), `src/tasks/strongstrong/pic_cuda.jl` (CUDA parity),
reusing `gaussian_beambeam_kick` / `faddeeva_w`
(`src/elements/strong_beam.jl`, `src/math/SpecialMath.jl`) and the slice-moment
helpers in `src/tasks/strongstrong/slicing.jl`.

### Implementation plan (priority order)

1. **Expose the options, CPU-first.** *(Historical: this step describes an
   abandoned design. The implementation is a separate `GaussianPICPoissonSolver`
   type composing a `PICPoissonSolver`, with the shorter field names
   `margin_sigma`, `neutralize`, `coupling_tol` — not a mode of `PICPoissonSolver`
   with `gaussian_subtract_*` fields.)* Add a mode to `PICPoissonSolver` with these
   public fields (all with explicit off/default so behavior is user-controlled):
   - `gaussian_subtract::Bool=false` — master flag; `false` is bit-identical to
     the current PIC path.
   - `gaussian_subtract_margin_sigma::Real` — box margin $m$ of Section 6
     (default ~5; `0` = off, i.e. keep the ordinary particle-wrapping box).
   - `gaussian_subtract_neutralize::Bool` — discrete charge neutralization of
     Section 6 (default `true`; `false` relies on the margin alone).
   - `gaussian_subtract_coupling_tol::Real` — correlation-coefficient threshold
     $r_{\text{tol}}$ of Section 7 (default `Inf` in the first cut = always
     uncoupled; finite value enables the coupled branch once implemented).

   Note this is a **fixed grid-point count** feature: `grid` ($N_x\times N_y$) is
   unchanged; only the adaptive box grows, so the FFT cost is untouched. Register
   each field in `_PIC_SOLVER_OPTION_SCHEMA` with a runtime consumer, add activity
   rules in `_pic_option_active` (the subtraction options are inactive when
   `gaussian_subtract=false`; `coupling_tol` is inactive until the coupled branch
   exists), and default so the current path is bit-identical when off. Run
   `validate_configuration_metadata()` and the public-configuration effectiveness
   contract afterward (per `AGENTS.md`).

2. **Shape-consistent Gaussian grid `Q_G` (the `erf` term).** Implement the
   separable node arrays `g_x`, `g_y` from Section 5 for `:CIC` (needs `E0,E1`)
   and `:TSC` (needs `E0,E1,E2`), using `SpecialFunctions.erf` (CPU) and a device
   `erf` on CUDA. Build them from the slice's **drifted** moments at the left and
   right field-slice boundaries (transport `mu, Sigma` by the drift `s`, matching
   the drifted-source deposition already in `_pic_deposit_drifted!`). Subtract the
   outer product `N_s * g_x ⊗ g_y` from the deposited particle grid *before* the
   Green-FFT convolution in `_pic_solve_drifted_field_with_green_fft!`. Cost is
   `O(Nx+Ny)` to build plus `O(Nx*Ny)` to subtract — negligible vs. the FFT.

3. **Analytic add-back at the field particles.** In the field-particle kick loop
   of `_pic_interaction!`, add `2*kbb * N_s * gaussian_beambeam_kick(sigx', sigy',
   x-mux', y-muy')` (drifted moments, interpolated between L/R boundaries in `z`
   the same way the grid field is) to the interpolated residual kick. Pin the
   overall constant by the pure-Gaussian limit (step V1).

4. **Longitudinal kick by linearity (Section 8).** Split `pz` into (a) the
   analytic soft-Gaussian synchro-beam `pz` term from the drifted Gaussian moments
   (reuse the moment formula used in `gaussian.jl` / `docs/theory/beam_beam_longitudinal_kick.md`)
   and (b) the residual potential-difference term `phi_delta,L - phi_delta,R`
   already computed by `_pic_interpolate_kick` (Kz). Gate on the existing
   `longitudinal_kick` flag.

5. **Domain sizing (Section 6), fixed `N_x,N_y`.** In `_pic_interaction_grids`,
   when subtraction is on, enlarge the **adaptive box** (not the mesh-point count)
   so the half-width is at least `max(particle_extent, margin_sigma * sigma)`
   about the slice centroid; `margin_sigma = gaussian_subtract_margin_sigma`
   (default ~5 → `erfc(5/sqrt2) ≈ 6e-7` leaked mass; `0` = off). Keep grid-origin
   alignment (`_pic_align_grid_origins`) unchanged. When
   `gaussian_subtract_neutralize=true`, rescale `Q_G` so
   `sum(Q_G) = sum(Q_part)`, removing the spurious monopole and relaxing the
   margin. Because the box tracks `sigma` (smoother than particle extrema), the
   slice-pair Green cache stays reusable (see the Green-cache item below).

6. **Coupled slices (Section 7), `gaussian_subtract_coupling_tol`.** Switch on the
   correlation coefficient `r_xy = sigma_xy / (sigma_x*sigma_y)`: `|r_xy| <=
   tol` uses the separable uncoupled subtraction (default), `|r_xy| > tol` uses
   the principal-axis rotated subtraction. First cut ships the uncoupled path
   (`tol = Inf`); implement the rotated Bassetti-Erskine add-back plus the rotated
   `Q_G` (rotated-frame `erf` resampled to nodes, or a small 2D quadrature) as a
   gated extension.

7. **Green cache: reuse unchanged (Section 11).** No new cache work. The Green
   kernel depends only on grid geometry, not on the deposited charge, so the
   hybrid only swaps `Q -> delta_Q` in the convolution and the existing
   `green_cache=:slice_pair` FFT cache applies as-is on CPU and CUDA. Confirm the
   backend-consistency and cache-history contracts still pass with subtraction on.

8. **CUDA parity (`pic_cuda.jl`).** Port `Q_G` (device `erf`, separable build),
   the grid subtraction, and the per-particle `faddeeva_w` add-back
   (`faddeeva_w_upper_reim` is already used in `strong_beam_track.jl`). Preserve
   the wavefront/async/indexed paths and the Green cache. Gate under
   `StrongStrongPICBackendConsistencyContract` for CPU/CUDA agreement.

### Validation plan (use the strong-strong example parameters)

The reference case is `examples/strong_strong_tracking.jl`: 10 GeV e- (2.56M
macro, `sigma=(106,9.5,7000) um`) vs 275 GeV p (1.024M macro,
`sigma=(95,8.5,60000) um`), 12.5 mrad crab crossing, 15 normal-quantile slices,
`grid=(128,128)`, CIC, integrated Green. These are ~11:1 flat beams — the
regime where the accuracy gain should be largest.

- **V1 pure-Gaussian limit (pins normalization).** Deposit deterministic Gaussian
  quantile macroparticles (as in `validation/pic_gaussian_field_validation.jl`)
  with the example's transverse sigmas; the hybrid kick must reproduce
  `GaussianPoissonSolver` / `gaussian_beambeam_kick` to ~1e-3 or better and the
  residual grid must be ~0. Also assert the `gaussian_subtract=false` path is
  bit-identical to current PIC.
- **V2 field accuracy vs. Bassetti-Erskine (headline metric).** Extend
  `validation/pic_gaussian_field_validation.jl` with a hybrid solver column and
  report median / p95 / max normalized field error at the example's aspect ratios
  (round, 5:1, ~11:1, 25:1) at a **fixed** `grid=(128,128)`. Expected: the hybrid
  median/p95/max are well below pure PIC at the same grid; quantify the factor.
  Sweep macroparticle count to separate shot-noise floor from grid error.
- **V3 domain-margin sweep.** Vary `margin_sigma` (3,4,5,6) with and without
  neutralization; confirm the residual net charge and the field error follow the
  `erfc(m/sqrt2)` prediction of Section 6, and that neutralization removes the
  monopole at small margin.
- **V4 full-beamline tracking A/B.** Run
  `OCTOPUS_TURNS=... examples/strong_strong_tracking.jl` with pure PIC vs. hybrid
  at identical grid/seed; compare luminosity, RMS moments, and per-turn timing.
  Also run the high-energy weak-strong limit
  (`validation/high_energy_weakstrong_limit.jl`,
  `OCTOPUS_WEAK_STRONG_LIMIT=1`) where the analytic answer is known.
- **V5 backend consistency.** CPU/CUDA agreement via
  `validation/strong_strong_pic_cache_backend_consistency.jl` and the
  `StrongStrongPICBackendConsistencyContract` extended to cover the hybrid mode.
- Record results in a dated `docs/history/strong_strong_gaussian_pic_optimization_history.md`
  and add a `test/runtests.jl` guard for V1 (normalization + off-path identity)
  and a small V2 accuracy-vs-PIC assertion.

### Performance plan

- **Confirm the fixed-grid claim.** A/B complete-turn timing (V4) must show the
  hybrid within a few percent of pure PIC at the same grid on CPU and GPU. The
  only new costs are the separable `erf` subtraction (`O(Nx+Ny)`, once per solve)
  and one `faddeeva_w` per field particle. Budget the per-particle analytic term
  against the grid interpolation it runs beside; if it dominates on GPU, fuse it
  into the existing kick kernel rather than a separate pass.
- **Reuse, do not duplicate.** Build `g_x,g_y` into the existing CPU workspace
  buffers (extend `_PICCPUWorkspace`) and the CUDA slice buffers; avoid new
  per-solve allocation. The subtraction is an in-place `charge .-= N_s .* gx *
  gy'` on the already-zeroed deposit grid.
- **Coarser-grid study (optional upside).** Because the residual is smooth, test
  whether the hybrid at `grid=(64,64)` matches pure PIC at `(128,128)`; if so it
  is a *speed* win on top of the accuracy win. Gate on V2/V4 before claiming it.
- Follow the same "no silently ignored option" rule as the rest of the solver:
  every new public field lands with its runtime consumer, an effectiveness test
  that observes it at the consumer boundary, and metadata.

## PIC Solver Core

Open items carried over from the former `pic_solver_improvement_plan.md` (its
implemented items are recorded in
`docs/history/strong_strong_pic_optimization_history.md`).

1. ~~**Improve GPU deposition.**~~ **CLOSED (2026-07-25).** CUDA PIC deposition
   uses atomics throughout (all 79 accumulation sites). Three measurements close
   this: deposition is **3.1%** of a CUDA turn, so the ceiling on any replacement
   is 3%; two identical 1000-turn CUDA runs gave **identical** emittance growth
   despite 3.6e-16 per-collide differences, so atomic nondeterminism does not
   reach the physics observable; and the phase timing added in Section 22 shows
   the kick, not deposition, is where the hybrid's time goes. Revisit only if a
   future run uses enough macroparticles per cell for atomic contention to show up
   in the deposition phase timing.
2. ~~**Add a lattice Green-function variant.**~~ **IMPLEMENTED (2026-07-25) as
   `green_type=:lattice`, marked EXPERIMENTAL: flat-beam field-accuracy studies
   only, explicitly NOT a recommended production configuration.** CPU + all CUDA
   routes, parity 1e-17. Accuracy is as evaluated (1.30x better than `:integrated`
   at the 11:1 production aspect with the shipped 0.5% aspect quantization; worse
   for round beams), but the cost is **1.74x runtime at grid 128 and ~645 MB**.
   Implementing it refuted the affordability argument: production needs **306**
   distinct aspect-ratio tables, not the ~18 a single-turn probe suggested, and
   the quantization cannot be coarsened to shrink that because beyond ~2% aspect
   error the kernel is *worse* than `:integrated`. The route to making it cheap
   (small lattice patch + analytic far field) is recorded in Section 3.5 of
   [`pic_free_space_kernels.md`](theory/pic_free_space_kernels.md); its
   anisotropic part is underived and is the remaining open work.
   **Superseded evaluation note:** Derived, constructed and measured against
   `:integrated` and `:standard` over round, 11:1 and 25:1 beams; see Section 3.4
   of [`pic_free_space_kernels.md`](theory/pic_free_space_kernels.md). Result
   splits by aspect ratio: **1.36-1.48x better at the 11:1 production aspect
   ratio** and at 25:1, but up to **2.8x worse for round beams**, consistent with
   the kernel contributing ~none of the round-beam error (Section 3.2).
   Worth adding as a `green_type=:lattice` option, with two caveats recorded in
   the derivation: the gain is in systematic field error, which the analogous
   `:fourth` gradient showed does **not** reduce shot-noise-driven emittance
   growth; and it is only affordable because the kernel depends solely on the grid
   size and aspect ratio `hx/hy`, not the absolute spacing, so it can be cached
   per (grid, aspect) like the slice-pair Green cache.

## Spectral Sine-Series Poisson Solver

**Status (2026-07-23): production-ready 6D solver, correctness-validated against
PIC and CUDA-optimized to near-PIC throughput.** `SpectralPoissonSolver` is
implemented, registered, validated, and optimized on both CPU and CUDA. It is a
documented (commented) option in `examples/strong_strong_tracking.jl`. Recommended
CUDA production setting for the ~11:1 flat beams: **`grid=(127, 383)`,
`domain_factor=8`, `method=:grid`** (odd sizes are intentional: a grid dimension
`N` gives a DST/DCT extension `2(N+1)`, so `N=2^k-1` is FFT-optimal). Measured on
the **full example beamline** (the correct benchmark -- isolated collide-only loops
inflate PIC because blown-up beams churn its adaptive green cache) at the production
case (2.56M e- / 1.024M p, 15 slices, RTX 4500 Ada, steady state): PIC 0.310 s/turn,
spectral **0.431 -> ~1.39x PIC** (after the index-based field solve + luminosity
preallocation), down from 6.05x slower at `(128,1024)/16`. Kick matches PIC to ~1%
on both beams in x/y/z and luminosity to 0.01% (~1.0e30). Absolute times are
workstation-GPU (weak FP64); the ratio is the portable metric.

**FP64 speed ceiling (measured):** at the fixed physics grid, the Dirichlet-box
field solve does several times more FFT work per solve than PIC's adaptive-box
`(128,128)` (7 transforms with the exact derivative vs PIC's 2 FFTs + finite-
difference derivatives), and PIC already batches its FFTs, so spectral cannot beat
PIC on raw throughput -- wavefront FFT batching and the Makhoul transform were both
tried and are slower. **Accuracy caveat:** at production settings both solvers sit on
the same macroparticle/CIC graininess floor (~1% vs theory), so spectral shows NO
demonstrated accuracy advantage here -- it matches PIC and analytic to ~1% (parity).
Spectral's exact derivative is mathematically more accurate at the field level, but
that is below the graininess floor at production statistics/grid and has not been
shown to improve the kicks in this regime; it would need a dedicated high-statistics
field-vs-analytic test to demonstrate. So at this production case spectral is ~1.4x
slower with no proven accuracy gain. An opt-in `field_precision=:single` reaches
~parity on FP64-weak GPUs but is
not a fair comparison (PIC could use Float32 too) and is not for production. See the
optimization history.

**Correctness note (2026-07-23):** the grid-path longitudinal `pz` kick was found
~2x too large (the on-mesh potential reconstruction carried a factor 2 relative to
the field because both shared one fitted `scale`); fixed with an explicit `1/2` in
`Phig` on CPU and CUDA. The grid `pz` kick now matches PIC to ~0.5% and grid-free
to ~1%. See the optimization history for the derivation and regression guards. In the grid solver this means both a `128x1024` interior mesh and
a `128x1024` sine-mode expansion; in `method=:grid_free`, the same option is a
direct mode-count tuple and no mesh is used. Transverse-kick headline numbers: kick matches the analytic
soft-Gaussian solver to ~0.2% (round) / ~0.4% (production flat); transverse-only
CPU 2.0 s/turn (100k/beam, 15 slices, 8 threads); transverse-only CUDA 0.62
s/turn at 2.56M/beam, ~4x faster than PIC on GPU. The default
`longitudinal_kick=true` path now applies the PIC-style synchro-beam drift and
potential-difference `pz` kick on CPU and CUDA; see the dated optimization
history for current 6D timing and solver-difference records.

References: method + measured accuracy in `docs/theory/spectral_sine_poisson_solver.md`;
performance + validation history in
`docs/history/strong_strong_spectral_optimization_history.md`; reference field
implementations in `validation/spectral_poisson_field_validation.jl`. Code:
`src/tasks/strongstrong/spectral.jl` (CPU) and `spectral_cuda.jl` (CUDA).

The longitudinal synchro-beam kick and midpoint luminosity refinement are now
complete and validated against PIC. Remaining Open items are performance/accuracy
refinements.

### Open (priority order)

The full 6D map needs **four** source-boundary spectral solves per slice pair
(left/right x two directions). The CUDA 6D path has been optimized to near-PIC
throughput at production scale (~1.24x PIC at 1e6/beam; see the 2026-07-23 CUDA
campaign in the optimization history: rfft DST/DCT, fused build/extract kernels,
right-sized FFT-friendly grid, drift-folded deposit). The **CPU** 6D path has not
had the same campaign and remains the top open performance item.

1. **CPU 6D performance campaign (DEMOTED, 2026-07-24 review).** Re-measured at the
   *recommended* production grid `(127,383)/d=8` rather than the over-resolved
   `(128,1024)/16`, the CPU spectral 6D path is **faster** than PIC(128,128), not
   slower, so the premise of this item no longer holds. It is also the least
   accurate solver at production settings once the coupling is not fitted away.
   Keep spectral as an independent cross-check; do not invest further in its CPU
   throughput. See
   [`poisson_solver_review_2026_07_24.md`](history/poisson_solver_review_2026_07_24.md).
   Original text follows. The CPU `longitudinal_kick=true`
   grid path never got the throughput campaign the CUDA path did. Measured baseline
   (20k/beam, 15 slices, `grid=(128,1024)/16`, 8 threads, one turn): spectral 6D
   `5.06 s/turn` vs PIC `4.23` and Gaussian `0.15` (see the 2026-07-23 6D-map entry
   in the optimization history). Concrete plan:
   - **Easy win first: adopt the smaller FFT-friendly grid.** The CUDA campaign
     showed `(128,1024)/16` is heavily over-resolved; `(127,383)/domain_factor=8`
     matches PIC to ~1% on both beams in x/y/z. That is ~2.7x fewer transform points
     in the thin direction and should transfer directly to CPU (FFTW `r2r` cost
     scales with the transform length, and `2(N+1)` is a power of two at
     `N=2^k-1`). Re-benchmark CPU 6D at `(127,383)/8` before anything deeper.
   - Then profile complete 6D turns and attack the dominant costs (deposit, the
     four `r2r` transforms/mode-multiplies per pair, interpolation/scatter,
     luminosity, worker sync, allocation). Note the CPU path already uses FFTW `r2r`
     RODFT00 (a real DST), so it does **not** carry the complex-extension overhead
     the CUDA path had — the "rfft" win there is CUDA-specific and not applicable.
   - Structural levers: reduce redundant transforms (share `DST_x(philm)` between
     the potential and Ey, as the CUDA path now does — 7 transforms/solve, not 8),
     preallocate the L/R potential/field output buffers (the allocating
     `_spectral_field_grid_potential!` still returns fresh arrays per solve), and
     fold the drift into the deposit to avoid the drifted-source snapshots. The CPU
     collide already parallelizes over dependency-safe collision wavefronts with a
     per-worker workspace pool; the remaining win is per-solve transform/allocation
     cost, not scheduling.
   - Gate any change on complete-turn A/B timing plus the CPU accuracy-vs-PIC and
     CPU/CUDA parity tests (both already in `test/runtests.jl`).
2. **Wavefront FFT batching -- TRIED AND REJECTED (does not help).** Implemented a
   full batched path (stack all field solves in a dependency-safe wavefront along a
   batch dimension, 3D build/extract kernels, per-batch-size rfft plans, batched
   solve; parity verified 9e-15). It was *slower* on the beamline (0.465 vs 0.431).
   Reason: although a batched rfft is ~1.64x more efficient in isolation, the DST/DCT
   transform is dominated (~75%) by the memory-bound extension build/extract (the
   `2(N+1)` real extension), not the FFT compute (~25%). Batching only speeds the FFT
   fraction, and the batching overhead (3D grids, per-wavefront setup) outweighs it.
   This is also why `field_precision=:single` helps (it halves the extension *bytes*
   and speeds the FFT) while batching does not.
   **Makhoul N-point transform -- also TRIED AND REJECTED.** The half-length DST-I
   (NR `sinft`: pre-weight + length-`M` rfft + repack + prefix-sum) was verified
   correct (matches a brute-force sine transform to 3e-13), but on GPU it is ~5.5x
   *slower* than the current 2M-extension transform: the post-processing prefix-sum
   scan (sequential per column, batched over Ny) plus the extra pre-weight/repack
   passes cost far more than halving the FFT saves. Same lesson as batching -- the
   transform is memory/pass-bound and Makhoul adds passes. No known cuFFT-based lever
   reduces the FP64 transform cost further; spectral is ~1.39x PIC at production and
   at production settings it shows no demonstrated accuracy advantage either (both
   sit on the same ~1% macroparticle/CIC graininess floor); the exact-derivative edge
   is a field-level property below that floor here.
3. **Add FP32 to PIC as an optional flag too.** Spectral now has
   `field_precision=:single` (Float32 field solve, ~1e-6 kick error, big win on
   FP64-weak GPUs). For a fair single-precision comparison PIC should expose the same
   option (a `field_precision`/`:single` flag that runs its deposit/FFT/Green/field
   in Float32 while keeping coordinates in Float64). Not for production either;
   purely so PIC-vs-spectral A/B tests can be run at matched precision.
4. **FP64 ceiling (documented, likely fundamental).** The field-solve transforms
   are the wall. PIC does exactly **2 FFTs per solve**: `fft(charge)` -> multiply by a
   cached Fourier Green function (the Poisson solve baked in) -> `ifft` -> phi, then
   Ex/Ey by **finite difference** on phi (no FFT). The spectral method does **7
   transforms per solve**: 2 forward DST (-> mode coefficients), the cached mode
   divide, then 5 reconstruction transforms because it uses the **exact spectral
   derivative** -- phi (sin*sin), Ex (cos*sin), Ey (sin*cos) each need a distinct 2D
   DST/DCT (d/dx turns sin->cos), and each 2D transform is two 1-D rfft passes.
   Spectral's extra transforms are exactly the price of the exact derivative that
   makes it beat PIC on flat-beam accuracy; using PIC-style finite-difference
   derivatives would drop it to ~4 transforms but forfeit that advantage. Combined
   with the taller Dirichlet-box grid (768 vs 256 in the extension), spectral does
   several times PIC's transform work at matched accuracy. So at matched accuracy/precision spectral cannot beat PIC on raw
   throughput; even wavefront batching (item 2) only reaches ~1.1-1.2x. A *fixed*
   large Dirichlet box does not help here -- the box is already shared across a turn,
   so the FFT graph is already fixed and batchable; a fixed-across-turns box would
   only save the tiny per-turn `al/bm/G` recompute, not FFT work. The genuine
   work-reduction lever is the adaptive box (item 5), which conflicts with holding
   the grid fixed for resolution. The Makhoul N-point real transform was tried (item
   2) and is ~5.5x slower on GPU (the prefix-sum scan dominates), so it is not a
   lever either. Conclusion: at fixed grid and FP64, no cuFFT-based transform change
   beats PIC; spectral is ~1.39x PIC. Accuracy is at parity too at production
   settings (~1% graininess floor for both), so its theoretical exact-derivative edge
   is not a demonstrated production advantage. See the accuracy caveat in the status.
5. Adaptive spectral Dirichlet-box strategy: the current spectral kick solve uses
  one shared global square box for both source and field beams across all slice
  pairs. This is conservative and keeps DST/DCT plans and workspaces simple, but
  it can leave many empty cells/modes for individual slice-pair solves. Explore a
  slice-pair or wavefront adaptive box that remains much larger than the local
  source/field particle domain, e.g. `max(domain_factor * local_sigma_max,
  extrema_margin * local_extrema_max)` with a floor from the full-beam RMS. Unlike
  PIC, the spectral Dirichlet box must not tightly wrap particles because
  `phi=0` at the boundary changes the physics; accuracy must be checked against
  Gaussian/PIC comparisons and the high-energy weak-strong limit. Reuse the PIC
  `green_cache=:slice_pair` design as the implementation pattern: fixed
  `grid=(Nx,Ny)` keeps transform plans reusable, while mode-Green arrays
  `1/(alpha_l^2+beta_m^2)` are cached by slice-pair or quantized box size with
  min-ratio/growth-style rebuild controls.
6. Grid-free spectral performance campaign: keep the direct-mode solver as a
  serious optimized reference path, not just a correctness fallback. Profile and
  optimize the harmonic recurrence, dense mode products, allocation reuse, and
  slice-pair scheduling for representative mode counts such as `48x48`. Note that
  grid-free needs `~64x256` modes (not `48x48`) to resolve the ~11:1 flat beam's
  `pz` kick to ~1% of PIC, so the representative flat-beam reference is heavier
  than the round-beam case.
7. Optional precision refinement: TSC field interpolation (or a finer mesh) to
  close the round-beam gap between the interpolated on-mesh result (~2.7e-3) and
  the per-point analytic (~1.6e-3).

### Completed

- CUDA 6D throughput campaign: rfft-based DST/DCT (real extension, ~2.6x/transform,
  bit-identical), fused 2D-indexed build/extract kernels with folded scaling,
  preallocated L/R output buffers, drift-folded deposit (no drifted-source arrays),
  shared DST_x(philm) (7 transforms/solve), and a right-sized FFT-friendly grid
  (`N=2^k-1` so the `2(N+1)` extension is a power of two). Brought the 6D CUDA grid
  solver from 6.05x slower than PIC to ~1.24x at 1e6/beam (fair interleaved median)
  with unchanged ~1% accuracy and preserved CPU/CUDA parity (~1e-14). New
  recommended production grid `(127,383)/d=8`. See the optimization history for
  measurements and the interleaved-timing caveat.
- Grid longitudinal-potential factor-of-2 fix (CPU and CUDA): the on-mesh
  potential `Phig` needed an explicit `1/2` (2D DST reconstruction carries factor
  4, each field component factor 2, sharing one fitted `scale`). Before the fix the
  grid `pz` kick was ~2x too large. After: grid `pz` matches PIC to ~0.5%,
  grid-free to ~1%, and `E = -grad(phi)` finite-difference consistency holds.
  Guarded by a CPU round-beam `rms(dpz)`-vs-PIC test and by the CUDA parity test
  now covering `longitudinal_kick=true`. Removed the dead CPU
  `_spectral_midpoint_luminosity_pair` helpers (superseded by
  `_spectral_midpoint_source` + `_spectral_luminosity_pair`).
- Full 6D synchro-beam map (CPU and CUDA): `longitudinal_kick=true` drifts source
  slices to field-slice boundaries, interpolates left/right spectral fields,
  applies the potential-difference `pz` kick, and reverses the field-particle
  virtual drift. `longitudinal_kick=false` keeps the original transverse-only map.
- Midpoint density-overlap luminosity for the full 6D path: both slices are
  drifted to the common collision midpoint before the spectral/PIC-style density
  overlap. The transverse-only comparison path keeps its original order-
  independent x/y overlap.
- Solver-comparison harness:
  `validation/strong_strong_spectral_comparison.jl` records timing, luminosity,
  final beam moments, and particle-coordinate differences against PIC/Gaussian
  references under `result/strong_strong_spectral_*`.
- Grid-free performance pass: direct mode coefficients and field evaluation now
  use harmonic recurrence plus dense matrix products, cutting the measured
  48x48 direct-mode reference case while preserving the grid-free API.
- Density-overlap luminosity (CPU and CUDA): CIC-deposit both source slices on a
  shared grid, sum the product, scale `npart1*npart2/(nmacro1*nmacro2)` over the
  cell area. Matches `_pic_luminosity!` to machine precision on identical inputs and
  agrees with PIC/Gaussian to ~4% on the production beams.
- CPU caching + parallelism: reusable per-worker workspace pool (deposit/mode/
  derivative buffers + FFTW plans, mode-Green recomputed only when the box changes),
  cutting per-solve allocation ~18 MiB -> 105 KiB; collision parallelized over field
  slices. 100k/beam, 15 slices, grid 128x1024: 9.7 -> 2.0 s/turn (~4.1x on 8
  threads), bit-consistent across thread counts.
- CUDA `collide!` for the grid path (`spectral_cuda.jl`): DST-I/DCT-I built from
  complex cuFFT of symmetric extensions (verified to machine precision vs FFTW),
  one in-place plan per dimension, cached workspace, custom deposit/interp-scatter/
  luminosity kernels. Agrees with the CPU path to ~4e-16 (kicks) and ~9e-16
  (luminosity); 0.62 s/turn at 2.56M/beam, ~4x faster than PIC CUDA at matched grid.
- Validation tests in `test/runtests.jl`: spectral-vs-Gaussian accuracy (both
  variants, round beam, <3%) and CPU/CUDA consistency (rtol 1e-9).
- Production parameter selection: grid `(128, 1024)`, `domain_factor=16` for ~11:1
  beams (grid-converged kick to ~1%, at the graininess floor). See the dated
  `docs/history/strong_strong_spectral_optimization_history.md`.

### Completed (solver core)

- `SpectralPoissonSolver{T} <: AbstractPoissonSolver`
  (`src/tasks/strongstrong/spectral.jl`): auto-registered, structured option
  schema (`slicing`/`slicing1`/`slicing2`, physical `kbb1`/`kbb2`,
  `luminosity_scale`, `grid`, `domain_factor`, `method`), both `:grid` (CIC deposit
  -> 2D DST -> mode solve -> on-mesh DST/DCT derivative -> interpolate) and
  `:grid_free` (direct converged mode sums) field solves, and a transverse CPU
  `collide!` over slice pairs in collision order.
- Field-solve normalization pinned to physical units. The source deposit is
  normalized to unit charge inside the field solve, so the field is the
  per-unit-charge Bassetti-Erskine field and the caller applies physical
  `kbb * slice_weight` **identically to `GaussianPoissonSolver`** (no `/n_macro`;
  kbb means the same across Gaussian/PIC/spectral). Two separately pinned scale
  constants: grid folds in the DST inverse-normalization and grows with mode count;
  grid-free uses a mode-count-independent constant (the direct sum is converged).
  Verified: round-beam kick matches the soft-Gaussian solver to ~0.2% for both
  variants, and stays within ~0.3% across `domain_factor` 10-16 (drift at larger
  `d` is fixed-grid resolution loss, not normalization).
- Flat-beam box fix. `_spectral_box` was sizing the Dirichlet box anisotropically
  (`Ly ~ d*sigma_y`), which clips the wide field of a flat beam (its transverse
  field extends on the `sigma_large` scale in both directions) and biased the
  wide-direction kick by ~9% at 5:1 (plateauing, not a resolution effect). Fixed
  to a square box sized to `sigma_max` in both directions, matching the docs and
  the earlier validation, with the thin direction resolved by the grid (`Ny`).
  Verified against the soft-Gaussian solver: flat 5:1 now matches to ~0.5% at
  `(128,512)`, and the production ~11:1 flat beam matches to ~0.4% at `(128,1024)`
  (`N_thin ~ 5*d*sigma_x/sigma_y`); round-beam accuracy is unchanged.
- Derivation of the 2D Fourier sine-series Poisson solver, discrete DST/FFT form,
  open-boundary discussion, circular/elliptical generalization, and correctness
  checks (manufactured band-limited solution recovered to 1e-15).
- Accuracy validation against Bassetti-Erskine for round and flat beams, with
  domain-size and thin-direction scaling regressions and parameter-selection
  guidance (domain `d ~ 12-16*max(sigma)`; anisotropic grid).
- Grid and grid-free variants with a computational-complexity comparison
  (grid/DST is 100-1000x faster than grid-free).
- Exact spectral field derivative: 2-3x more accurate than finite differences;
  the solver beats PIC on flat beams (25:1 median ~30% lower, max ~3x better) and
  ties on round. **Caveat: this is a FIELD-LEVEL result vs the smooth Bassetti-
  Erskine formula (no macroparticle noise).** In a real strong-strong sim at
  production statistics/grid, both solvers sit on the same ~1% CIC graininess floor,
  so this field-level edge is NOT a demonstrated production accuracy advantage (see
  the status accuracy caveat). It would only matter at very high macroparticle counts
  with a coarse/anisotropic grid.
- Fast on-mesh spectral-derivative field pipeline (O(Nx*Ny*log)) validated to
  retain the accuracy advantage at ~4x lower cost than PIC. The DST-I mesh cosine
  derivative equals a zero-padded DCT-I (verified to machine precision).

## Earlier Completed

- Soft-Gaussian CUDA optimization (host-sync removal, device moments, fused
  wavefront launches): 0.2778 -> 0.2280 s/turn, bit-identical. See
  `docs/history/strong_strong_gaussian_optimization_history.md`.
- PIC `kbb1/kbb2` override switched to physical units, consistent across all
  solvers and frozen-beam elements.
- Strong-strong example and task notebook default to the PIC solver with the
  soft-Gaussian solver as a commented alternative.
- Lorentz crossing maps classified as Hirata quasi-symplectic (`NonSymplectic6DMap`).
