# Slice Longitudinal Interpolation and Field Smoothness (2026-07-25)

Full record of the investigation into the sliced beam-beam kick's smoothness:
what was asked, what the derivation found, everything that was measured
(including the results that contradicted the initial recommendation), what was
implemented, and what was deliberately not done.

Theory: [`../theory/slice_longitudinal_interpolation.md`](../theory/slice_longitudinal_interpolation.md).
Measurements: `validation/slice_longitudinal_zscan.jl`,
`validation/slice_interpolation_emittance_growth.jl` (+ `_summary.jl`).

**Headline, stated up front because it reverses the initial recommendation:**
the three-node interpolation is a large *field-accuracy* win and **not** a
dynamics win. It does not reduce artificial emittance growth. Two other options
found along the way — `deposit_method = :TSC` and the new
`interaction_grid = :source_slice` — do.

## 1. Question

Whether the two-node (left/right field-slice boundary) longitudinal interpolation
of the source-slice field could be extended to three nodes for a higher-order
error, and whether the sliced kick is smooth in `z` at all — since particles
execute synchrotron motion, a non-smooth kick would drive artificial emittance
growth.

## 2. What the derivation found

The two questions have opposite answers for the two planes, which was not the
expected outcome.

- **The transverse kick is already `C^0` across slice boundaries, exactly.**
  Adjacent field slices share a boundary, so the right node of one slice and the
  left node of the next are the same source drift, hence the same physical source
  configuration. The kick is continuous piecewise-linear with a kink, not a jump.
- **The longitudinal kick is discontinuous at first order in the slice width.**
  `_pic_interpolate_kick` applies `Kz = phiL - phiR` with no `t` weighting, so
  `Delta p_z` is a single secant slope held constant across the slice. Adjacent
  slices use secants centred on different midpoints, giving an `O(dz)` step at
  every boundary. Inherited from the standard Hirata-style synchro-beam map.

Three implementation-level effects break continuity independently of
interpolation order: per-slice-pair grid sizing, per-turn re-slicing, and source
evolution between collisions in the ordered slice-pair schedule.

The derivation also separated two distinct `O(dz^2)` errors that a convergence
study in `nslices` alone cannot tell apart: the *interpolation* error (removed by
adding nodes) and the *slicing* error (not removed).

## 3. Measured — frozen z-scan (field accuracy)

`validation/slice_longitudinal_zscan.jl`. Flat EIC-like pair, 200k
macroparticles/beam, `grid=(64,64)`, `:integrated`, 7 normal-quantile slices,
3 slices swept at 61 samples each, against a per-particle exact solve on the same
mesh. Full tables in the theory note, Section 10.

### 3.1 With `:CIC` (production default)

| source slice | component | peak exact | max err `:linear` | max err `:quadratic` | gain |
|---|---|---|---|---|---|
| 4 | `Dpx` | 1.7e-5 | 7.5e-11 | 4.4e-11 | 1.7 |
| 4 | `Dpy` | 1.0e-5 | 2.3e-9 | 3.2e-10 | 7.3 |
| 4 | `Dpz` | 3.9e-11 | 1.29e-11 | 2.5e-12 | 5.2 |
| 6 | `Dpx` | 1.7e-5 | 2.2e-10 | 4.0e-11 | 5.5 |
| 6 | `Dpy` | 8.5e-6 | 1.2e-9 | 5.0e-10 | 2.4 |
| 6 | `Dpz` | 4.4e-10 | 1.24e-11 | 2.4e-12 | 5.2 |

Boundary discontinuities, normalized by peak exact kick:

| grid mode | scheme | `Dpx` | `Dpy` | `Dpz` |
|---|---|---|---|---|
| common | `:linear` | ~2e-9 | ~2e-8 | **0.45-0.52** |
| common | `:quadratic` | ~2e-9 | ~2e-8 | 0.039-0.11 |
| per-slice | `:linear` | 1.0-1.6e-3 | 0.3-4.8e-3 | 0.04-0.69 |

- The derived `C^0` cancellation is confirmed to roundoff (~1e-8).
- The longitudinal sawtooth is **45-52% of the peak longitudinal kick**.
- Transversely the per-slice-pair *grid* jump (~1e-3) is ~5x larger in absolute
  terms than the interpolation error beside it, and is untouched by adding nodes.

### 3.2 With `:TSC` — deposition is the limiter

Section 9 of the theory note predicted the `:CIC` gain was capped by deposition
smoothness (`:CIC` is only `C^0` in the source drift; `:TSC` is `C^1`).
Confirmed, by a much larger margin than anticipated:

| source slice | component | gain `:CIC` | gain `:TSC` |
|---|---|---|---|
| 4 | `Dpx` | 1.7 | 18.7 |
| 4 | `Dpy` | 7.3 | 36.5 |
| 4 | `Dpz` | 5.2 | **188** |
| 6 | `Dpx` | 5.5 | 45.0 |
| 6 | `Dpy` | 2.4 | 18.7 |
| 6 | `Dpz` | 5.2 | **105** |

Longitudinal boundary jump: `:CIC` 0.52 -> 0.039 (13x); `:TSC` 0.55 -> 9.5e-4
(**580x**). The two options are **multiplicative, not additive** — `:TSC` alone
barely changes the `:linear` error (0.277 vs 0.332) and slightly *worsens* the
jump; `:quadratic` alone gives 5x; together they essentially eliminate the
discontinuity.

### 3.3 Shared interaction grid

Sizing one mesh per (source slice, direction) from the union over all its field
slices, via the production helper `_pic_union_bounds`:

| grid mode | jump `Dpx` | jump `Dpy` |
|---|---|---|
| per-slice-pair (default) | 1.0-1.6e-3 | 0.3-4.8e-3 |
| shared per source slice | 2.4e-9 | 1.9-3.0e-8 |
| common grid (ideal) | 2.1e-9 | 1.6-2.9e-8 |

Reaches the ideal floor exactly.

Cost, **corrected**: the first figures reported here (11-36%) were measured
against the z-scan's own multi-slice span reference, not against the
per-slice-pair meshes production actually builds. Against the right denominator,
for this EIC-like pair: 1.14x (7 slices), 1.30x (15), 1.33x (30) horizontally and
1.12/1.18/1.26x vertically — it grows with slice count and saturates near 1.3x.

**And it does not generalize — including for the production case.** The shared
mesh must cover the source slice drifted across the field beam's *entire*
longitudinal range, and a drifted slice grows as `sigma*sqrt(1+(s/beta*)^2)`. The
drift span is set by the **field** beam's bunch length while the blow-up is
evaluated on the **source** beam's optics, so the governing ratio is
`sigma_z,field / beta*,source`, and a collider runs both directions every turn.

The first version of this record measured only proton-source -> electron-field and
concluded the EIC case was benign. That was wrong. Both directions, 15 slices:

| direction | `sigma_z,field/beta*,source` | src slice | `hx` | `hy` |
|---|---|---|---|---|
| proton -> electron | 0.10 | centre | 1.28 | 1.26 |
| proton -> electron | 0.10 | tail | 1.27 | 1.32 |
| **electron -> proton** | **1.07** | centre | 1.06 | **2.70** |
| **electron -> proton** | **1.07** | tail | 1.10 | **2.69** |

In the electron-source direction the vertical cells are **2.7x coarser**, roughly
7x worse `O(h^2)` field error, on the real production parameters.

Synthetic sweep confirming the scaling (field `sigma_z` varied, tail source slice):

| `sigma_z,field/beta*` | 0.12 | 0.36 | 0.89 | 1.79 | 3.57 |
|---|---|---|---|---|---|
| `hy` ratio | 1.26 | 1.33 | 1.76 | 3.06 | 5.87 |

The horizontal is nearly flat (`beta*_x` an order of magnitude larger); the
blow-up is entirely in the small-`beta*` plane, which for a flat beam is the one
that matters.

**This does not invalidate arm F.** That run used the same two-beam pair and
therefore already paid the 2.7x penalty in one direction, and emittance growth
still fell (-7.4% electron, -30% proton). So the discontinuity removal won on net
at `grid=(64,64)`. But the margin is far thinner than the one-directional figures
implied, and the balance is **not** verified at production grids, where the
systematic `h^2` term weighs more against a shot-noise-scale discontinuity.

Safe below `sigma_z,field/beta*,source ~ 0.5`; measure above ~1. The fix is to
index the mesh by the interpolation *node* rather than the slice, which restores
exact continuity at every boundary with no union over the field beam and at
neutral cost. A bounded-group variant was considered and withdrawn (it only
reduces the jump from every transition to every `G`-th). The full
grid-determination program is in `todo.md`.

### 3.4 Node-indexed meshes (`interaction_grid = :node`)

Indexing the mesh by the interpolation *node* rather than the slice. Slices `s`
and `s+1` share boundary node `z_s`, so giving that node its own mesh makes both
sides read the same plane on the same mesh at every boundary. Each node mesh
covers only its own source drift (plus the next node's) and the two adjacent
slices — no union over the field beam, hence no hourglass sensitivity.

| quantity | per-slice-pair | `:source_slice` | `:node` |
|---|---|---|---|
| `Dpx` boundary jump | 1.0-1.6e-3 | 2.4e-9 | **1.1e-9** |
| `Dpy` boundary jump | 1.3-3.1e-3 | 1.9-3.0e-8 | **2.2-2.6e-8** |
| `hx` coarsening | 1.00 | 1.14-1.33 (2.7 other direction) | **1.11** |
| `hy` coarsening | 1.00 | 1.12-1.26 (**2.70**) | **1.05-1.08** |
| turn time, 1M/15sl/grid128 | 24.389 s | 22.601 s | **15.726 s (0.64x)** |

`:node` is faster at production scale because each node's Green FFT is built once
and reused by both adjacent slices. It supersedes `:source_slice` on every axis.

**The longitudinal trap, found by measurement.** The first prototype put each of a
slice's two planes on its own node mesh, and the longitudinal jump **exploded to
14x the peak kick** (from 0.52). `Delta p_z ~ phi_L - phi_R` is a small difference
of large numbers whose discretization error only cancels within one mesh; across
meshes it is wrong by 20-50%.

The obvious hypothesis — an additive gauge offset, removable by subtracting a
constant — was **tested and refuted**: sampled over a 5x3 grid of transverse
positions the discrepancy has mean 5.1e-2 and standard deviation 7.7e-2, a
relative spread of **1.51**. It varies more than its own mean, so no gauge fix
exists.

The implementation therefore does three solves per slice-pair direction: `F_L`
(node `s` on mesh `s`), `F_R` (node `s+1` on mesh `s+1`), and `F_Z` (node `s+1` on
mesh **`s`**). Transverse blends `F_L`/`F_R` on their own meshes for exact
continuity; longitudinal uses `F_L`/`F_Z` on a shared mesh so the error
cancellation survives. Each node mesh must therefore also cover the next node's
drift.

**Residual.** With the mesh term gone the remaining discontinuity is continuity
breaker #3 — the shared node is solved once per adjacent slice with the source
kicked in between. Measured by applying one slice-pair's worth of kick to the
source and re-solving the same node on the same mesh: `Dpx` 2.2e-5, `Dpy`
7.6-8.1e-5. So node indexing lowers the transverse jump from `~1e-3` to a `~1e-4`
floor set by a different mechanism, roughly **40x**, and that floor is what to
attack next.

### 3.5 Mesh extent: estimator, quantization, out-of-range safety

Sections 3.3-3.4 fix *where* the mesh sits; these concern *how big* it is, and
persist under every indexing scheme.

**Phase 0 — the premise, measured.** `validation/pic_grid_extent_stability.jl`,
relative variation of the mesh box (200k/beam, 15 slices, 8 turns):

| estimator | slice-to-slice x / y | turn-to-turn x / y | dropped |
|---|---|---|---|
| `:extrema` | 5.3e-2 / 5.1e-2 | 5.2e-2 / 4.8e-2 | 0 |
| `:sigma` (k=6) | 6.5e-3 / 1.3e-2 | 1.0e-2 / 1.4e-2 | 0 |
| `:quantile` | 7.2e-2 / 6.6e-2 | 6.9e-2 / 6.2e-2 | 0 |

The predicted ~6-7% extrema jitter is confirmed. `:sigma` is 4-8x stabler, against
a prediction of >=10x — **the prediction was optimistic**.

**Phase 1 — out-of-range deposition (prerequisite).** `_pic_cic_weights` clamped
the cell index while keeping the weight, so a particle outside the mesh deposited
its full charge onto the boundary cell — a spurious charge sheet, strictly worse
than dropping it. On CUDA a `NaN` coordinate produced a `NaN` weight that poisoned
the whole charge grid through the atomic add; on CPU it threw `InexactError` from
inside the kernel. Identical physics **crashed loudly on CPU and silently corrupted
on GPU**. Both stencils on both backends now return zero weights outside
`[0, n-1]` or for non-finite input, and drops are counted in
`_PICCPUWorkspace.dropped`. Unreachable under `:extrema`, so the default path is
bit-identical.

**Phase 2 — `grid_extent`.** `:extrema` (default) or `:sigma`
(`grid_extent_sigma = 6.0`). `:sigma` addresses a *different* breaker than
`:node`: node indexing removes the slice-boundary jump exactly but does nothing
about turn-to-turn mesh jitter, which `:sigma` cuts 5x.

`:quantile` was implemented, **measured, and removed**. At a coverage target tight
enough to avoid charge loss it rounds to *all* particles for realistic slice
populations, degenerating to the extremum plus histogram quantization noise —
measured worse than `:extrema`. Its useful regime needs loose coverage, ruled out
by the charge-loss arithmetic: dropping `f` of charge at radius `R` costs
`~ f*(sigma/R)`, so `f=1e-3` at `5 sigma` is `2e-4`, the same order as the
discontinuity being removed. Dropping is a counted safety valve, never a sizing
strategy.

**Phase 3 — `grid_quantize`.** A mesh differing by 1% from its neighbour produces
essentially the same jump as one differing by 50%; only *identical* meshes cancel.
Snapping the extent to a `2^q` ladder and origins to whole cells collapses distinct
meshes across 225 slice pairs:

| configuration | distinct meshes |
|---|---|
| `:extrema`, q=0 | 225 |
| `:sigma`, q=0 | 225 |
| `:extrema`, q=1/8 | 29 |
| **`:sigma`, q=1/8** | **7** |

The two compose: `:sigma` alone collapses nothing (the box varies continuously),
quantization alone gives 29, together 7.

**CUDA `:node`** is implemented on the sequential non-async route, CPU parity
9.5e-16, luminosity parity 2.7e-16. Wavefront and batched-FFT assume one mesh per
slice pair and throw.

## 4. Measured — multi-turn emittance growth (dynamics)

`validation/slice_interpolation_emittance_growth.jl`. Head-on, linear one-turn
maps, no chromaticity, no dispersion, **no radiation damping or excitation**, so
the Poisson solver is the only non-symplectic element and all growth is
numerical. 30k macroparticles/beam, `grid=(64,64)`, 800 turns, 4 seeds per arm
(3 for the 30-slice arm C). `boundary_cross_fraction = 0.470`: 47% of particles
change slice index per turn, so the discontinuity is heavily sampled and a null
result is meaningful.

`t_like` is the separation from baseline in pooled standard errors; |t| < 2 is
not resolved. The **electron** is the sensitive probe: `Qs = -0.069` against the
proton's `-0.01`, so ~7x more synchrotron periods in a fixed run.

| arm | scheme | slices | deposit | grid | ele `eps_y'` | t_ele | pro `eps_y'` | t_pro | cross |
|---|---|---|---|---|---|---|---|---|---|
| A | `:linear` | 15 | CIC | slice_pair | 8.201e-5 | — | 3.273e-6 | — | 0.470 |
| B | `:quadratic` | 15 | CIC | slice_pair | 8.185e-5 | **-0.09** | 2.962e-6 | -1.10 | 0.470 |
| C | `:linear` | **30** | CIC | slice_pair | 8.464e-5 | **+1.56** | 3.082e-6 | -0.37 | 0.621 |
| D | `:linear` | 15 | **TSC** | slice_pair | 7.160e-5 | **-6.93** | 3.028e-6 | -0.91 | 0.470 |
| E | `:quadratic` | 15 | **TSC** | slice_pair | 7.057e-5 | **-5.22** | 2.746e-6 | -1.77 | 0.470 |
| F | `:linear` | 15 | CIC | **source_slice** | 7.591e-5 | **-3.44** | 2.291e-6 | **-2.79** | 0.470 |

**This is the decisive result, and it contradicts what Section 3 predicts.**

1. **`slice_interpolation = :quadratic` does not reduce emittance growth.**
   t = -0.09 (electron), -1.10 (proton). Not resolved. And it adds nothing on top
   of `:TSC` either (E vs D: 7.057 vs 7.160, within noise). The
   `field_derivative = :fourth` precedent repeats exactly: a large field-accuracy
   gain with no dynamical consequence.
1b. **Neither does doubling the slice count (arm C).** 30 slices costs 4x and
   gives t = +1.56 — marginally worse, certainly not better, despite the
   boundary-crossing fraction rising from 0.470 to 0.621 so the discontinuity is
   sampled *more*. This is the decisive control: more slices refines the
   interpolation error and the slicing error simultaneously, and neither matters.
   **Longitudinal discretization is not the growth driver at all**, which retires
   the entire premise that motivated the three-node work.
2. **`deposit_method = :TSC` does** — 12.7% lower electron vertical emittance
   growth, t = -6.93. The single largest effect measured.
3. **`interaction_grid = :source_slice` does** — 7.4% on the electron
   (t = -3.44) and 30% on the proton (t = -2.79). The only arm resolved on both
   beams, and it is also 10-39% *faster* (Section 3.3). Strict win on three axes:
   smoothness, dynamics, and speed; the only cost is the coarser mesh.

**Field-accuracy metrics did not predict dynamics here, and the ranking is close
to inverted.** The z-scan ranks `:quadratic` + `:TSC` as a 100-190x improvement in
longitudinal field error; that combination is statistically indistinguishable
from `:TSC` alone in emittance growth. Conversely `:TSC` alone, which the z-scan
rates as barely better than `:CIC` for `:linear`, produces the biggest dynamics
improvement.

The coherent reading across all six arms: **artificial vertical emittance growth
in this configuration is driven by transverse field noise and mesh discontinuity,
not by longitudinal reconstruction error.** The two options that move it —
smoother deposition and a continuous mesh — both act on the transverse field. The
three that refine the longitudinal reconstruction — more nodes, more slices, and
both together — do nothing. Consistent with Section 11 of the 2026-07-24
Poisson-solver review.

## 4b. 200-turn option consistency and cost (2026-07-26)

`validation/pic_option_consistency.jl`, on the crab-crossing EIC case of
`examples/strong_strong_tracking.jl` (same beams, crab cavities, Lorentz boost
pair, one-turn optics, chromaticity, electron radiation). 50k macroparticles/beam,
grid 64, 15 slices, 200 turns, 6 CPU threads; timing is the mean over turns
100-200. Differences are against the `base` run at the *same* particle count.

| tag | s/turn | vs base | lum mean | lum worst | eps_y | eps_x | drift |
|---|---|---|---|---|---|---|---|
| base | 1.184 | 1.00 | - | - | - | - | - |
| srcslice | 1.092 | **0.92** | 1.2e-3 | 3.3e-3 | 5.6e-4 | 1.0e-3 | 3.9e-4 |
| sigmaq | 1.109 | **0.94** | 1.7e-3 | 5.9e-3 | 3.2e-3 | 4.2e-3 | 5.3e-4 |
| tsc | 1.281 | 1.08 | 1.1e-3 | 2.8e-3 | 5.9e-4 | 7.9e-4 | -1.9e-4 |
| quad | 1.319 | 1.11 | **2.0e-4** | 8.0e-4 | **5.4e-5** | 5.1e-5 | 1.0e-4 |
| node | 1.452 | 1.23 | 1.0e-3 | 2.6e-3 | 1.6e-3 | 1.2e-3 | 4.4e-4 |
| all | 1.639 | 1.38 | 1.4e-3 | 3.0e-3 | 4.3e-4 | 4.3e-4 | 1.6e-4 |
| node_gpu | 0.885 | 0.75 | 1.0e-3 | 2.6e-3 | 1.6e-3 | 1.2e-3 | 4.4e-4 |

**Every option agrees with the default to ~1e-3 in luminosity and ~1e-3 in
emittance** -- the size the discretization change implies -- and the `drift`
column (second-half minus first-half mean relative difference) is ~1e-4, so the
differences bound rather than grow.

**CPU and CUDA `:node` are indistinguishable over 200 turns**: `node` and
`node_gpu` produce identical summary statistics to every displayed digit. Their
per-turn parity is 9.5e-16, and 200 turns is far too few for that seed to grow to
anything visible.

### Production-point timing (CUDA, the operating point that matters)

The 50k / grid-64 CPU table above is **not** the production point and its cost
ordering does not carry over. The production configuration, from
`examples/strong_strong_tracking.jl` and the 2026-07-24 Poisson-solver review, is
2_560_000 electrons, 1_024_000 protons, 15 slices, grid (128,128), CUDA with the
default indexed wavefront path. Measured there, 200 turns, mean over turns
100-200, one job at a time so the GPU is uncontended, including luminosity and
moment output:

| tag | s/turn | vs base | CUDA route |
|---|---|---|---|
| base | **0.3408** | 1.00 | wavefront, indexed |
| `grid_quantize=0.125` | 0.3379 | **0.99** | wavefront, indexed |
| `deposit_method=:TSC` | 0.3668 | 1.08 | wavefront, indexed |
| `slice_interpolation=:quadratic` | 0.9310 | **2.73** | sequential, non-async |
| `interaction_grid=:node` | **1.1988** | **3.52** | sequential, non-async |

Two things this changes:

1. **`grid_quantize` is effectively free at production scale** (0.99x), where at
   2000 particles on CPU it looked like a 2.2x speedup. The quantization win is a
   Green-cache win, and the wavefront path already amortizes Green FFTs well, so
   the win shrinks as the field solve stops dominating.
1b. **`:node` is not expected to be faster, and the first explanation for its
   3.52x was wrong.** Per source slice it builds `N+1` meshes against
   `:slice_pair`'s `N`, and 3 field solves per slice pair against 2 -- ~1.5x work
   is the floor, so the earlier "0.64x at 1M/grid128" figure (measured on
   `collide!` in isolation, where neither path had cross-turn cache reuse) does
   not describe a real run and is retracted.

   The hypothesis that the remaining gap came from rebuilding 480 Green FFTs per
   turn (the node cache being local to the collide call, where the baseline's
   slice-pair cache persists) was **tested and refuted**: making it persistent
   with the same expand-and-cover guard measured **1.4226 s/turn, 19% slower**,
   and was reverted. The remaining suspect -- the ~960 per-node slice gathers and
   ~5760 reduction launches per turn needed to size each node mesh -- is untested;
   see `todo.md` item 2a. Profile before guessing again.
2. **`:quadratic` and `:node` cost 2.7x or more**, not the ~1.1-1.2x the CPU table
   suggests -- because on CUDA they are only implemented on the sequential
   non-async route, which is itself ~2.5x the wavefront default. Their real price
   on CUDA is the *route*, not the extra solve. Extending the wavefront route to
   carry a third plane / per-node meshes is therefore the single highest-value
   remaining optimization for anyone who wants these options in production.

### Correction: the `:node` speedup is operating-point dependent

Section 3.4 reports `:node` at **0.64x** turn time, measured at 1M particles/beam,
grid 128, `collide!` only. Here, at 50k/beam, grid 64, with the full lattice, it is
**1.23x**. Both are correct measurements of different points, and the earlier
figure should not be read as a general claim.

The mechanism: `:node` trades one extra field solve for a halving of Green-FFT
builds (each node's mesh serves two slices). The Green FFT scales with grid size
while the extra solve scales with particle count, so `:node` wins at large grid and
loses at small. Quote the operating point with the number.

`:source_slice` (0.92x) and `grid_extent=:sigma` + `grid_quantize=1/8` (0.94x) are
both *faster* than the default here, the latter because quantization collapses 225
distinct slice-pair meshes to 7 and nearly every Green FFT becomes a cache hit.

### Per-particle coordinates: chaotic divergence, not instability

Coordinates were dumped at turns 1, 50, 100 and 200 from a parallel 2000-particle
set. RMS difference against `base_c`, normalized by beam size:

| tag | turn 1 | turn 50 | turn 100 | turn 200 |
|---|---|---|---|---|
| quad_c | 6.3e-4 | 2.8e-2 | 2.2e-1 | 8.6e-1 |
| tsc_c | 3.0e-3 | 1.1e-1 | 4.6e-1 | 9.3e-1 |
| node_c | 5.7e-3 | 2.3e-1 | 7.1e-1 | 9.8e-1 |
| sigmaq_c | 1.3e-2 | 4.1e-1 | 8.4e-1 | 9.8e-1 |

(`rms dy / sigma_y`.) The turn-1 values are at the discretization level and rank
in the expected order -- `:quadratic` perturbs the kick least, `:sigma`+quantize
most. The growth to ~1 sigma by turn 200 is the **Lyapunov divergence of
strong-strong beam-beam**, which amplifies *any* perturbation including a changed
random seed; it is not evidence of instability in an option.

Per-particle coordinate agreement at late turns is therefore **not a usable
acceptance criterion** for this system. The usable ones are the turn-1
per-particle difference and the statistical observables above, both of which are
bounded and at the expected size. The clean demonstration is `node` vs `node_gpu`:
a 1e-15 seed that has *not* grown visibly by turn 200, against a 1e-3 seed that
saturates by turn ~100.

## 4c. Optimizing `:node` (2026-07-26)

`:node` measured 3.52x base at the production point. Profiling first -- after two
wrong guesses -- gave a full decomposition, using `:slice_pair` and `:quadratic`
run on the *same* sequential non-async route to separate the terms:

| component | s/turn | share of gap |
|---|---|---|
| base (wavefront, indexed) | 0.3408 | - |
| + CUDA sequential non-async route | +0.4148 | 48% |
| + third field solve | +0.1754 | 20% |
| + node mesh building | +0.2678 | 31% |
| = `:node` | 1.1988 | |

**Node mesh building fixed.** The builder ran one pass over the source *per node*
(`nb` passes per source slice) and scanned each field slice *twice* (once per
adjacent node). Both loops are memory-bound. Restructured so the source is read
once with all `nb` drift accumulators updated per particle, and the field beam
once into per-slice boxes that are unioned pairwise -- same arithmetic, `nb`x and
2x fewer passes.

| | before | after |
|---|---|---|
| CUDA, production point | 1.1988 | **1.0026** |
| CPU, `collide!` only, 200k/grid64 | 1.23x base | **0.71x base** |

**The "1.5x floor" claim is retired: `:node` crosses over and becomes faster than
the baseline at production-scale particle counts.** It trades an N-fold reduction
in bounds passes (the baseline recomputes source and field bounds for every
*pair*, N^2 times; node does it once per *source slice*, N times) against 1.5x the
field solves. Bounds cost scales with particle count, solves with grid size, so
there is a crossover: at 50k over 15 slices (~3300 particles per slice) the solve
dominates and node loses at 1.18x; at 640k/256k it wins at 0.87x.

**Methodological warning, learned the hard way three times here.** A
`collide!`-only microbenchmark at 200k/grid64 reported 0.71x and was published
before the full-lattice check, which then gave 1.18x at 50k. The final 0.87x is
from a full-lattice run at production-shaped counts. Every cost claim in this work
that came from `collide!` in isolation was later inverted -- the `:node` "0.64x",
the Green-cache hypothesis, and this one. **Measure with the full lattice, at the
particle count that will actually be run, or do not report the number.**

**A correctness improvement fell out of it.** The CPU/CUDA parity test failed
after the CPU restructure, for a substantive reason: building node meshes lazily
sized them from *different source states*, because the source slice is kicked
between its collisions with different field slices. Building the whole set at once
pins one state for all of a source slice's nodes, which is what node indexing
means. Ported to CUDA; parity, the full suite and the 1.1e-9 boundary jump all
hold.

**Remaining:** the route. `:node` still runs only on the CUDA sequential non-async
path, which alone accounts for 0.4148 s/turn. Porting it to the wavefront route
requires generalizing the fixed two-planes-per-Green arithmetic
(`ngreen = nplanes / 2`, `green_plane = plane0 / 2 + 1`) to an explicit
`green_of[plane]` lookup, since node mode groups planes non-uniformly (L and Z
share the left node's mesh, R uses the right node's). The wavefront workspace
already carries per-plane geometry (`wf.hx`, `wf.hy`), so the change is narrower
than the plane-count arithmetic suggests.

## 5. What was implemented

### 5.1 `slice_interpolation = :linear | :quadratic`

Default `:linear`, bit-compatible with all prior results. `:quadratic` adds a
third solve at the field-slice midpoint, uses the quadratic Lagrange basis for
the transverse field and its `z`-derivative for the longitudinal kick. Two
identities are enforced by test: transverse weights sum to 1; longitudinal
weights sum to 0, so the mesh potential's arbitrary additive constant still
cancels exactly. At `t=1/2` the longitudinal weights reduce to `(-1,0,+1)/dz` —
the two-node kick is the three-node formula frozen at mid-slice.

Cost: +50% of the field-solve stage. Measured CPU turn time 1.01-1.14x, *falling*
with particle count because deposition and the kick loop dominate: **+5%** at
1M/beam, 15 slices, grid 128. (An earlier estimate of +30-40% was wrong.)

CUDA: implemented on the **sequential, non-batched-FFT route only**
(`batch_mode=:sequential`, `cuda_async=false`), CPU parity 7.5e-16. The wavefront
and batched-FFT routes pack two field planes per slice-pair direction
(`nplanes = 4*npairs`, with `÷2`/`÷4` plane arithmetic through the deposit,
solve, Green and luminosity kernels) and throw rather than dropping the midpoint
plane. Measured at 1M/beam, 15 slices, grid 128:

| CUDA route | s/turn | vs production |
|---|---|---|
| wavefront `:linear` (production default) | 0.3201 | 1.00x |
| sequential non-async `:linear` | 0.7940 | 2.48x |
| sequential non-async `:quadratic` | 0.9190 | **2.87x** |

So CUDA `:quadratic` really costs 2.87x today, not the 1.14x its own route
suggests.

### 5.2 `interaction_grid = :slice_pair | :source_slice`

Default `:slice_pair`, bit-compatible. `:source_slice` sizes one mesh per
(source slice, direction) from `_pic_union_bounds` and keys the slice-pair Green
cache without the field-slice index, so adjacent field slices reuse one mesh.
Per-slice actual bounds are still handed to the cache's coverage test, so a slice
whose particles have moved outside the shared mesh triggers a rebuild rather than
being silently clipped. CPU only; all CUDA paths and both Gaussian-PIC paths
throw.

## 6. Deliberately not done

- **Chebyshev two-node placement.** Moving the two existing nodes inward to
  `m +- dz/(2*sqrt2)` halves the linear-interpolation maximum error at zero cost,
  but destroys the shared-endpoint cancellation and converts the continuous
  transverse kick into one with a step at every boundary. Wrong trade for a code
  whose failure mode of concern is artificial emittance growth.
- **Centroid as the third node.** Correct as the source plane's first moment,
  wrong as an interpolation node; under `:equal_area` it sits off-centre and
  clusters the nodes. For three points the Chebyshev-Gauss-Lobatto set *is* the
  equispaced set, so the midpoint is both optimal and simplest.
- **CUDA wavefront/batched `:quadratic`.** Needs the two-planes-per-direction
  indexing generalized across three routes. Guarded by an explicit throw.

## 7. Process notes (things that went wrong)

- Two runs (`A` seed 4, `C` seed 4) crashed with a `MethodError` because they
  started while the package source was mid-edit and loaded an inconsistent
  precompiled build. They were re-run against the final build. The arms that
  completed on earlier builds are unaffected: the Step-2 changes add an inactive
  code path and leave `:slice_pair` numerics bit-identical, which is asserted by
  the `PIC interaction_grid flag` test (`e_def == e_sp`). Both reruns completed
  against the final build and are included above; only arm C is at n=3, because
  its fourth seed was still running when the table was frozen (it does not change
  the conclusion — arm C is the one arm pointing the *wrong* way).
- The first cost estimate for `:quadratic` (+30-40% turn time) was derived from
  the field-solve share of a CUDA timing dump and was wrong for CPU by ~7x. Cost
  claims are now measured, not apportioned.
- The `:source_slice` coarsening cost was got wrong **twice**: first measured
  against the z-scan's own span reference instead of the per-slice-pair meshes
  production builds, then measured in only one of the two collision directions.
  The corrected worst case for the production EIC pair is 2.70x vertical, against
  the 1.11-1.36x first reported. Both errors shared a cause — generalizing from a
  single convenient configuration instead of enumerating the cases the option
  actually runs in.

## 8. Recommendations

- **For emittance-growth / dynamics work:** enable `deposit_method = :TSC` and
  `interaction_grid = :node`, and consider `grid_extent = :sigma` with
  `grid_quantize = 0.125` for the turn-to-turn jitter that node indexing does not
  address. `:node` supersedes `:source_slice` on every axis:
  same discontinuity removal, 1.05-1.11x coarsening instead of up to 2.70x, no
  hourglass sensitivity, and 36% faster at production scale. Do **not** enable `:quadratic` expecting a
  dynamics benefit.
- **For longitudinal field accuracy** (synchro-betatron detail, longitudinal
  diffusion studies, anything reading `Delta p_z` directly): enable `:quadratic`
  **together with** `:TSC`; alone it captures about a twentieth of the available
  gain. Note this is a field-accuracy justification, not a dynamics one.
- **On CUDA:** `:quadratic` costs 2.87x until the wavefront route supports it.
  Prefer the CPU path (+5%) or wait.

## 9. Open items

Carried into [`../todo.md`](../todo.md): CUDA wavefront `:quadratic`; per-turn
re-slicing jitter (now the most promising untested mechanism, since both options
that moved emittance growth were about field smoothness rather than interpolation
order); and whether the duplicate boundary-plane solves can be shared now that
`:source_slice` removes the per-pair mesh obstacle — which would make three-node
interpolation *cheaper* than the current two-node scheme rather than +5%.
