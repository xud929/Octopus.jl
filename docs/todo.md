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
   **1.1988 -> 1.0026 s/turn**. CPU, full lattice: **1.18x at
   50k/grid64 but 0.87x at 640k/256k/grid128** -- `:node` crosses over and becomes
   *faster* than the baseline at production-scale particle counts, because the
   baseline recomputes bounds per pair (N^2) while node does it per source slice
   (N), and bounds cost scales with particle count while solves scale with grid.
   **CPU has reached the goal.** The "1.5x floor" claim is retired. (An earlier
   `collide!`-only figure of 0.71x was a microbenchmark artefact and should not
   have been reported; all three cost claims in this work that came from
   `collide!` in isolation were later inverted.)

   Also fixed a correctness issue found by the parity test: lazy per-node building
   sized meshes from different source states (the source is kicked between pairs).
   All of a source slice's nodes are now built together from one state.

   **Remaining gap is the route** -- see 2b.
2b. ~~**Port `:node` to the CUDA wavefront route.**~~ **DONE (2026-07-26).**
   `:node` now runs on the indexed wavefront route via its own 6-plane path
   (`nplanes = 6 * npairs`, L/R/Z per direction), with a per-plane Green stack that
   removes the fixed two-planes-per-Green arithmetic. All three CUDA routes match
   CPU at ~6e-16; the sequential batched-FFT sub-route still assumes one mesh per
   pair and correctly throws.

   Measured at the production point, single process, same lattice:

       config                wall/turn  interaction  fields   lum   outside
       slice_pair wavefront     0.3238       0.3110  0.1471 0.0243   0.0128
       node wavefront           0.8097       0.3912  0.2145 0.0909   0.4185
       node sequential          1.0797       0.6377  0.4298 0.0966   0.4420

   The port is worth 25% (0.81 vs 1.08), and node's *interaction* is only 26%
   above base -- the 6-plane batching is efficient.

2c. ~~**Node prebuild: host-sync latency.**~~ **CONFIRMED AND PARTLY FIXED
   (2026-07-26).** Component decomposition of the 0.3812 s/turn prebuild:

       component      count    each      total   share
       mapreduce       3720  58.7 us   0.2185 s   57%
       green FFT        480   191 us   0.0915 s   24%
       slice gather      60  59.8 us   0.0036 s    1%
       (unaccounted)                   0.0675 s   18%

   Reductions confirmed dominant. Each `mapreduce` returns a scalar to the host
   and forces a device-to-host sync; the prebuild issued 3720 per turn. Fixed by
   broadcasting to a `K x n` matrix and reducing along the particle axis: 4
   kernels and 4 syncs per slice regardless of `K`.

       prebuild   0.3812 -> 0.1944 s   (predicted saving 0.2185, measured 0.1868)
       turn       1.1196 -> 1.0124 s

   Note the earlier estimate of 110 us per reduction was 2x too high; the ranking
   was right, the magnitude was not.

2d. **Remaining CUDA node gap, and an honest ceiling.** `:node` is 1.0124 s/turn
   against base 0.3238 (3.13x). What is left, in order:

   1. **Green FFT, ~0.09 s.** 480 builds per turn where the baseline's slice-pair
      cache persists. A geometry-keyed memo was tried and measured no gain even
      with `grid_quantize` (1.0981 / 1.1312 / 1.0852 at q = 0 / 1/8 / 1/4 against
      1.1196) -- the component measurement says the cost is real, so the memo
      likely had a key-matching bug. Worth one careful retry with an assertion on
      the hit rate.
   2. **Interaction excess, ~0.08 s.** Node's interaction is 0.3912 against base's
      0.3110 -- the third field solve.
   3. **Unaccounted prebuild, ~0.07 s.**

   **Correction: parity IS reachable; the 1.5x floor was a mis-count.** Comparing
   per-pair solve counts (3 vs 2) is the wrong accounting. Per source slice, over
   all `N` field slices:

       baseline                 2N planes
       :node, algorithmically   (N+1) node planes + N longitudinal = 2N+1
       :node, as implemented    3N

   Node planes are **shared between adjacent slices**: `F_R` for slice `s` *is*
   `F_L` for slice `s+1` -- same node, same drift, same mesh, same source. There
   are only `N+1` distinct node planes, not `2N`. The implementation recomputes
   each one twice. So the method needs **one extra solve per source slice** (~3%
   at N=15), not 50%.

   **Why the third solve exists at all:** node mode has two conflicting
   requirements. Transverse continuity needs each node's plane read on *that
   node's* mesh (so adjacent slices agree at their shared boundary); the
   longitudinal `phi_L - phi_R` needs both values on *one* mesh or its
   discretization error stops cancelling (measured 20-50% error, and the
   discrepancy is not a constant -- relative spread 1.51 -- so no gauge fix). The
   baseline never faces this because it puts every plane of a pair on one mesh,
   which is exactly why it has the discontinuity.

   **DECISION (2026-07-26): plane sharing is REJECTED. Do not implement it.**
   `:node` exists to remove a *numerical* discontinuity. Sharing a node's plane
   between its two adjacent slices would pay for that by freezing the source
   between the two uses -- trading away *physical* strong-strong
   self-consistency to fix a numerical artefact, which defeats the purpose of the
   option. Self-consistency is not negotiable for a performance number. `3N`
   solves stands; item 4e is closed, not deferred.

   Consequently `:node`'s solve cost is inherently 1.5x the baseline's `2N`, which
   shows up as the measured ~26% excess on the interaction stage (0.3912 vs
   0.3110). **All remaining optimization must come from the prebuild and Green
   FFTs, which are pure implementation and touch no physics.**

   Original blocker note, retained for the record: `F_R` computed for slice `s` is one step
   stale when slice `s+1` uses it, because the source is kicked in between. That
   is continuity breaker #3, measured at 2.2e-5 (`Dpx`) / 8.1e-5 (`Dpy`) -- an
   order of magnitude *below* the 1e-3 grid jump `:node` removes. Plausibly a good
   trade, but it is a **modelling** change to strong-strong self-consistency and
   should be decided on physics grounds, not for a benchmark. Note that pinning
   node *meshes* to turn start is geometry and is not the same thing as freezing
   the field.

2. ~~**CUDA `slice_interpolation=:quadratic`.**~~ **DONE (2026-07-26).**
   Ported to the batched-FFT routes — the production indexed wavefront, the
   gathered wavefront, and the sequential batched-FFT sub-route — via an
   additive 6-planes-per-pair path (L/M/R per direction with a per-plane Green
   stack, the same mechanism as the `:node` port; the 4-plane functions are
   untouched). CPU parity 2-4e-11 relative on coordinates and ~5e-16 on
   luminosity on all three new routes; the sequential non-async route keeps its
   earlier support. The one remaining unsupported combination is the non-batched
   async route (`cuda_async=true, cuda_batch_fft=false`), which throws.
   Measured cost on the indexed wavefront route (640k/256k, 15 slices, grid 128,
   collision + one-turn maps, mean over turns 11-30): linear 0.137 s/turn,
   quadratic 0.240 s/turn — **1.75x**, down from the 2.87x a CUDA user paid on
   the old sequential-only support. The excess over the CPU's +5% is the third
   solve on a route where field solves dominate the turn.
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
5. ~~**Per-turn re-slicing jitter.**~~ **QUANTIFIED (2026-07-26)**,
   `validation/pic_slice_boundary_jitter.jl` (example beams, PIC(64) collision +
   one-turn maps, 100k macros, 15 slices, 64 turns; std over turns / `sigma_z`):

       boundary set                     equal_area      normal_quantile
       outermost (z extrema, shared)    0.13-0.17       0.13-0.17
       internal, mean (electron)        0.0036          0.0022
       internal, mean (proton)          0.0027          0.00022

   The **extrema-pinned outermost boundaries dominate** by ~40x, exactly as
   suspected — they modulate the outer slices' widths (and so the longitudinal
   kick scale `1/(rb-lb)`) by ~15% of `sigma_z` every turn under *both* methods.
   Internal boundaries: `:normal_quantile` is 1.6x (electron) to 13x (proton)
   stabler than `:equal_area`. Remaining open question (new): whether pinning the
   outer boundaries to a robust estimator (e.g. `mu +- k*sigma`, mirroring
   `grid_extent=:sigma`) moves the emittance-growth measurement; that is an
   emittance-growth-harness arm, not another jitter measurement. Distinct from
   the grid-determination program below: that concerns the *transverse* mesh,
   this concerns the *longitudinal* slice boundaries.
6. **Duplicate boundary-plane solves** — folded into phase 4 of the
   grid-determination program below, which is what unlocks it.

## STATUS: CUDA `:node` optimization (2026-07-26)

Design rationale: [`docs/theory/node_interaction_grid.md`](theory/node_interaction_grid.md).

**Where it stands, production point** (2.56M e- / 1.024M p, 15 slices, grid 128,
CUDA, 120 turns, mean over 60-120):

    base (slice_pair, wavefront)   0.3238 s/turn
    :node, wavefront               1.0124 s/turn   3.13x     <- current
    :node, sequential non-async    1.0286 s/turn
    (:node at session start)       1.1988 s/turn   3.52x

CPU has **met** the goal: 0.87x base at 640k/256k, grid 128, full lattice.

**Done this round**
- Ported `:node` to the CUDA indexed wavefront route (own 6-plane path). All
  three CUDA routes match CPU at ~6e-16.
- Node meshes built at turn start, not lazily: lazy building made the mesh depend
  on how much of the turn had been applied, which differs between routes and made
  CPU/CUDA disagree by 3.8e-5.
- Hoisted redundant field-slice gathers (225 -> 15 per direction per turn).
- Batched the bounds reductions: 3720 host-syncing `mapreduce` calls per turn ->
  240. Prebuild 0.3812 -> 0.1944 s.
- Green memo **tried twice and reverted both times.** The kernel is
  `G(r_field - r_source)`, so the first memo's absolute-origin key never repeated;
  re-keying on the relative offset was correct but bought only 0.009 s (prebuild
  0.1944 -> 0.1856, turn unchanged at 1.0124), and pairing it with
  `grid_quantize=0.125` measured **worse** (1.0417). Each of the 480 node meshes
  has a genuinely distinct relative offset, so there is nothing to reuse. The
  0.0915 s of Green construction is real but **not cacheable** -- it would need
  meshes to coincide, and node meshes are sized per node from distinct
  bounding boxes by construction.

**Remaining budget to base (0.3238)**

    node interaction excess   ~0.08 s   inherent: 3N solves vs 2N (see below)
    green FFT construction    ~0.09 s   480 builds/turn; NOT cacheable (see above)
    prebuild, other           ~0.10 s   unaccounted portion of the 0.1944 s
    (measured 1.0124 total; the above do not yet sum -- some is lattice/overlap)

**Hard constraint, decided 2026-07-26: `:node` will not go below ~1.5x the
baseline's solve count.** Only `2N+1` of its `3N` planes are distinct, but
realizing that requires sharing a node's plane between its two adjacent slices,
which freezes the source between the two uses. That trades *physical*
self-consistency for a *numerical* fix and defeats the option's purpose. Rejected;
item 4e is closed, not deferred.

**Methodological note for whoever continues.** Six hypotheses formed by reading
code were refuted by measurement in this work: persistent Green cache (slower),
geometry-keyed memo v1 (no gain -- wrong key), geometry-keyed memo v2 with the
correct key (0.009 s, and worse with quantization), luminosity gathering
(0.002 s),
"0.77 s outside instrumentation" (invalid cross-harness comparison), and a 2x-off
per-reduction latency estimate. What worked every time was the per-phase
instrumentation and component decomposition against call counts. **Profile, do not
reason from the source.** And never quote a cost from a `collide!`-only
microbenchmark -- every such number in this work was later inverted.

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
replaced. ~~**This is the next thing to attack.**~~ **Attacked and closed
negative (2026-08-01)** -- the obvious fix, node-solve caching, removes this
discontinuity but introduces a larger systematic error in its place. See 4e.

Still open from this phase:

- ~~**4a. Z-scan the hybrid solver**~~ — **DONE (2026-07-26)**,
  `validation/gaussian_pic_zscan.jl`, this time through the hybrid's own solve
  path (`_gpic_solve_drifted_field!` + the analytic add-back with production
  zL/zR blending). Two results. (1) On a **common grid** the hybrid's
  longitudinal interpolation error and boundary jump **equal pure PIC's** — the
  analytic term carries the total field's z-curvature, so the reconstruction
  error is a property of the total field, not of what sits on the mesh.
  (2) On **per-slice-pair meshes** (identical boxes for both solvers) the
  mesh-resizing jump falls 2.8x in x but only **1.10x in y**, against the ~11x
  the residual-fraction argument predicted (`||dQ||/||Q|| = 0.088` at 28k
  macroparticles/slice). **The prediction is refuted for the flat-beam-critical
  vertical component**: at these statistics the deposited residual is mostly
  shot noise, whose mesh dependence does not scale with the smooth-residual
  amplitude. Consistent with the recurring lesson that systematic field-accuracy
  gains do not transfer to noise-driven quantities; `:node`/`grid_quantize`
  remain the discontinuity fixes for the hybrid too.
- ~~**4d. CUDA `:node`**~~ **DONE (2026-07-26)** on the sequential non-async route
  (`batch_mode=:sequential`, `cuda_async=false`), CPU parity 9.5e-16 and luminosity
  parity 2.7e-16. ~~The wavefront and batched-FFT routes assume one mesh per slice
  pair and throw.~~ **Stale as of 2b (2026-07-26), re-verified 2026-08-01:**
  `:node` runs on wavefront-async, wavefront-sync and sequential-sync alike, so
  no CUDA route *errors* on it.

  **That does not make it a default candidate on CUDA, and it is worth being
  explicit because the CPU and CUDA answers point opposite ways.** Per 2b at the
  production point, `slice_pair` wavefront is `0.3238 s/turn` against `:node`
  wavefront at `0.8097` -- **2.5x slower**. The "36% faster" result is CPU only
  (1M/beam, 15 slices, grid 128), where `:node` crosses over because the baseline
  recomputes bounds per pair. Quoting the CPU crossover as though it held on GPU
  is a mistake that has now been made once; on CUDA the 7.4%/30% emittance gain
  costs 2.5x wall time and is a trade, not a free win.
- ~~**4e. Node-solve caching**~~ — **CLOSED NEGATIVE (2026-08-01), and it had
  already been closed on principle by 2d on 2026-07-26** ("plane sharing is
  REJECTED... item 4e is closed, not deferred"). This entry still read "gated on
  the residual proving worth removing", so the document contradicted itself and
  the stale half got implemented before the decision was found. The measurement
  below is therefore redundant as a *decision* and useful only as the number 2d
  asserted without one: 2d rejected sharing because it trades physical
  self-consistency for a numerical artefact; the measurement says how much --
  `3.0e-4` introduced against `8.1e-5` removed at a production kick.

  **Lesson for the reader: check the decision items (2b-2d) before implementing
  a phase-4 sub-item.** The phase list is older than the decisions taken during
  the CUDA optimization, and where they disagree the decision wins.

  Implemented, measured, and reverted. Both halves of the promise held: a one-slot rolling
  cache per (source slice, direction) made the shared boundary `C^0` exact
  including the source state, and cut solves from 324 to 180 (`0.556x`, exactly
  `n/2 + one cold start per source slice`). One slot suffices because
  `_slice_collision_order` visits a fixed source slice's field slices
  monotonically, so ~12 MB at 15 slices and grid 128 rather than the ~190 MB a
  full per-node cache would need.

  **Caching the *solve* is a different thing from the caching already in place,
  and only the former touches physics.** `_pic_build_node_grids!` already stores
  `(source_grid, field_grid, green_fft)` per node -- the same contract
  `green_cache` has for `:slice_pair`. That is physics-neutral **because the
  charge is re-deposited from the current source on every pair**, so a kicked
  source is fully accounted for; only the mesh geometry and the Green kernel are
  reused, and neither depends on the source state. 4e asked to cache the solved
  field (`phi, Ex, Ey`) instead, which skips the re-deposition -- and skipping
  the re-deposition *is* freezing the source. The safe caching was already done;
  what 4e proposed was precisely the part that is not safe to cache.

  **It is still wrong, and the reason is sharper than "staleness": caching
  deletes a real effect rather than smoothing it.**

  The source evolution between adjacent field slices **is physics.** The source
  slice really is deflected by field slice `j` before it meets `j+1`. What is
  *not* physics is the shape: two field particles an infinitesimal distance
  either side of a slice boundary meet the source at collision points differing
  by `eps/2`, so the true variation across that boundary is `O(eps)` and
  continuous. Slicing concentrates it into a finite step. **The effect is real;
  the step is the discretization.**

  That distinction decides the fix. Re-solving gets the right *amount* of
  evolution in the wrong (stepped) distribution. Caching gets **too little** --
  the second slice never sees the intervening kick at all -- so it does not
  smooth the step, it removes the physics that produces it. Which is why it cost
  `3.0e-4` instead of being roughly neutral. Measured against kick strength, 40k
  macroparticles, 9 slices, grid 64:

      kick/divergence   luminosity diff   relative dpy error introduced
      33.4              7.5e-3            0.229
      0.447             4.7e-6            3.0e-3
      0.045             4.9e-8            3.0e-4
      0.0045            5.0e-10           3.0e-5

  The introduced error scales as the kick (luminosity as its square), while the
  discontinuity being removed is fixed at `Dpy 8.1e-5`. **At a production-like
  kick (`~0.05` of the divergence) caching introduces `3.0e-4`, roughly 3.7x
  more error than the `8.1e-5` it removes** -- and introduces it as a systematic
  field bias everywhere rather than as a jump at one boundary. The two only
  cross over near `kick/divergence ~ 0.005`, which is not a collision anyone
  runs.

  The first attempt measured `7.5e-3` on luminosity and looked catastrophic;
  that run had `rms px` going 0.002 -> 0.066, i.e. **33x the beam divergence**,
  which is a stress test rather than a collision and maximally penalizes
  staleness. The scaling table is the honest version, and the conclusion
  survives it.

  Not gated on the emittance-growth run, deliberately: confirming that a change
  which introduces more error than it removes also fails to help dynamics is not
  worth the compute. Reverted rather than kept behind a flag -- a knob nobody
  should turn is a maintenance cost, and the measurement lives here instead.

**With 4e closed, the `~1e-4` node floor is the accuracy limit of the node route,
and the framing above says what a real fix would have to do: distribute the
source evolution rather than delete it.** Reusing a solve removes the effect;
re-solving steps it. The continuous version is to interpolate the *source state*
across the node -- solve the shared node from a source drifted/kicked to the
boundary rather than from either adjacent slice's endpoint state -- so the
`O(eps)` physical variation is represented as `O(eps)` instead of as a step. Not
designed, not costed, and gated on the dynamics evidence below, which says the
payoff is likely unmeasurable.

A consistency check that supports leaving it alone: if the jump is the
discretization of a real effect, more slices means a smaller kick per slice and
therefore a smaller jump. The record measured doubling the slice count and found
**no** emittance improvement (t = +1.56, marginally worse), which is what you
would expect if the effect is real but small.

**The dynamics case for attacking this floor at all is weak**, and that should be
weighed before anyone spends more on it.
[`docs/history/slice_longitudinal_interpolation_record.md`](history/slice_longitudinal_interpolation_record.md)
Section 4 measured that artificial vertical emittance growth here is driven by
*transverse field noise and mesh discontinuity*, not by longitudinal
reconstruction error: `:TSC` deposition moved it 12.7%, a continuous mesh moved
it 7.4%/30%, while more nodes, more slices, and both together moved it not at
all. The jump that bought those gains was `~1e-3`; this residual is `2.2e-5` to
`8.1e-5`, 12-45x smaller. Expect any dynamics payoff to sit below the noise floor
of that measurement.

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

**STATUS: DONE (2026-07-26).** N1 and N4 are implemented; N2 is decided
(fail-fast, not configurable — see below); N3 is closed as redundant.

- **N1 (chokepoint detection):** `isfinite` checks on the O(1) *results* of the
  reductions that already scan every coordinate — the PIC grid-bound reductions
  (CPU and every CUDA route, including the indexed-wavefront fused bounds and
  the node-mesh builds), the slicing boundary extrema/quantiles (the earliest
  scan of `z`, both backends), the soft-Gaussian slice moments (CPU, CUDA
  sequential, and a device poison flag folded into the fused wavefront
  moment-build kernel and read back with the once-per-turn luminosity
  transfer), the hybrid's margin-box bounds, and the spectral Dirichlet box.
  Zero hot-path cost; the offending slice is scanned for particle
  identification only on the failure path. The error names the collision
  label, turn, slice pair, particle index, and every coordinate of the first
  offending particle (`_nonfinite_coordinate_error` in
  `src/tasks/strongstrong/interface.jl`).
- **N2 (policy):** fail-fast is the policy, deliberately **not** configurable.
  Quarantine would introduce a lost-particle concept the solvers do not have:
  `_pic_kbb1`/`_pic_kbb2` normalize by the macroparticle count, so silently
  dropping particles would change the kick scale and luminosity normalization.
  A single-value configuration option would be speculative surface (AGENTS.md).
- **N3 (periodic sweep):** closed as redundant — the chokepoint checks already
  run every turn for every coordinate that reaches a mesh (`x, px, y, py, z`).
  The one gap is a non-finite `pz` with all other coordinates finite, which is
  caught one turn later when the ring map propagates it into `z`.
- **N4 (tests):** 21 CPU and 18 CUDA assertions in `test/runtests.jl`
  ("Non-finite coordinates fail fast at solver chokepoints") cover every
  solver, every CUDA route, `NaN` and `Inf`, both beams, and verify the
  luminosity-schedule `NaN` sentinel is not mistaken for a failure.

Original analysis retained below for the record.

Nothing in tracking or the Poisson solvers checks for `NaN`/`Inf` coordinates, and
the two backends disagree about what happens when one appears. This is a
correctness-and-safety item in its own right, but it should land **with phase 1 of
the grid-determination program**, because both are the same question — what to do
with a particle that is not representable on the mesh — and both live in the same
deposition code path.

**What happens today (pre-fix)**

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

## Gaussian longitudinal slicing rules (weak-strong)

**Phases 1 and 2 are DONE (2026-07-31).** All five Furman rules plus
Gauss-Hermite are implemented in `GaussianStrongBeamSpec`, verified against
Table 1 of Ref. [1], and ranked at EIC weak-strong parameters. Full record:
[`docs/history/gaussian_slicing_convergence_2026_07_31.md`](history/gaussian_slicing_convergence_2026_07_31.md).
Derivation: [`docs/theory/gaussian_longitudinal_slicing.md`](theory/gaussian_longitudinal_slicing.md).
Measurement: `validation/gaussian_slicing_convergence.jl`.

Two results from that study close or change what follows:

- **`:sqrt_density` (#4) wins decisively** — 10.6x more accurate than the shipped
  default at `ns=15`, 20x at `ns=31`, same cost, and it is Xsuite's default.
- **Gauss-Hermite loses** despite moment exactness (order 1.0, 11x worse than #4
  at `ns=61`). Moment fidelity is the wrong objective for this integrand.
- **The tail mechanism carries over to `Q`**, so the binding error is quadrature.

### DONE: default changed to `:sqrt_density` (2026-07-31)

Changed from `:equal_area` after the measurement. Pinned by `test/runtests.jl`
so it cannot drift silently; `slice_method = :equal_area` reproduces earlier
results. Metadata, docstring and `construction_help` updated together.

### DECIDED: keep `:hirata` as the `virtual_drift` default (2026-07-31)

The slicing study made the paraxial drift the dominant remaining error, so
changing this default was proposed and **declined**. The reason is a real
distinction, not just user-selectability:

- `slice_method` is a **numerical discretization** of a fixed model. "More
  accurate at the same cost" is uncontroversial -- everyone wants the same
  physics computed better, so its default was moved to `:sqrt_density`.
- `virtual_drift` selects **which Hamiltonian is integrated**. Hirata's paraxial
  map is the canonical published synchro-beam map and what cross-code
  comparisons assume, so defaulting to it is a reproducibility position. It is
  exposed, documented, and one symbol to change.

What was done instead: the measured cost is now stated where a user meets the
option -- the `ThinStrongBeamSpec` docstring and the `virtual_drift` `ParamMeta`
both carry the numbers and say plainly that the choice is an accuracy floor no
slice count removes.

Measurements, for anyone revisiting this. Contribution to Furman `Q` at
converged slicing (`ns = 601`):

    direction              |hirata - exact|   |chromatic - exact|
    electron on proton          2.9e-4              2.8e-8
    proton on electron          3.9e-5              1.4e-9

`ChromaticDrift` is the exact flow of `(px^2+py^2)/2(1+pz)`; it costs no `sqrt`,
only `1/(1+pz)` recomputed after each kick. Note `:hirata` is also the default
for the strong-strong solvers (`GaussianPoissonSolver` and friends), so any
future change is wider than one element.

### Phase 3a -- high-order composition: CLOSED, not deferred

The gate was whether the tail mechanism survived in `Q`. It does (theory note
Section 5.1), so the binding error is node placement and composition -- which
raises the order of the *splitting* -- has nothing to fix. Retired.

The supporting results stand on their own and are recorded in theory note
Section 6: the telescoped inter-slice map is an exact one-parameter group to
round-off for all three virtual-drift models, and Section 6.3 lists what a
composition scheme would require (negative weights, `slice_weight` split into
physical charge vs kick coefficient, telescoped drifts, chromatic or exact
drift). Reopen only if a different motivation appears.

### Phase 3b -- implicit symplectic integrator as a reference oracle

Independent of 3a and still worth doing. Not a production tracker: per-particle
Newton iteration diverges across a CUDA warp, and truncating the iteration
destroys the exact symplecticity it was chosen for. Its value is validating the
6D longitudinal and energy terms by integrating the continuous Hamiltonian
rather than assembling them term by term. Cost stops mattering when it runs once
per parameter point instead of 1e9 times.

Note the convergence study no longer *needs* it for a reference: the circularity
in Ref. [1]'s "algorithm #4 at 300 kicks" is already removed by qualifying the
`ns=601` reference with a self-convergence and a cross-family agreement figure
(4.0e-7 and 1.6e-5 respectively, electron on proton).

### Phase 3c -- observable-matched nodes (open question, one experiment)

Every rule implemented so far approximates the *source*. Minimizing `Q` (or a
luminosity-weighted error) directly over `{z_k, w_k}` at fixed `ns` would give
the true lower bound to score the others against. The Gauss-Hermite result makes
this more interesting, not less: it is direct evidence that source-fidelity
objectives and kick accuracy come apart. Result is per-machine, not universal --
acceptable for a fixed design point. Hypothesis, not established practice.

### Follow-ups left open by the study

- The hadron-side stopping criterion is still unresolved. Furman's
  `Q ~ 4/sqrt(tau)` applies to the electron ring (`6.3e-2` at `tau=4000`, cleared
  by `ns=5` for every rule but #1); the proton ring has no comparable `tau`, so
  nothing masks its residual. Pick a long-term emittance-growth rate or diffusion
  coefficient instead.
- `:equal_width` keeps a second convergence parameter (`slice_width`). The
  validation script ties it to Furman #1's growing span so `ns` alone drives it;
  a user who fixes the width will see convergence stall. Consider either deriving
  the width from `ns` by default or rejecting a fixed width above some `ns`.

## Aperture and particle loss: in progress (2026-08-01)

Design is settled and written up in
[`docs/theory/aperture_and_particle_loss.md`](theory/aperture_and_particle_loss.md):
a separate aperture element, regular shapes as parameters plus an `alive`
predicate for the rest, NaN marking a dead particle, log-once by detecting the
`newly_lost` transition, one per-particle record holding turn, element id and the
six pre-kill coordinates, and no compaction.

Sequenced deliberately, because a partly-applied NaN mask is silently wrong and
looks finished. **Do not start a later step before the earlier one is green.**

**Step 1 -- coordinate-to-index safety. DONE** (`7df88fc`, `5779e6c`). This gated
everything else: `floor(Int, NaN)` throws and `unsafe_trunc` returns an undefined
index, both *before* the bounds checks that would otherwise have caught them. PIC
deposition was already safe and documented; slicing (3 sites) and `spectral.jl`
(7) threw; `spectral_cuda.jl` (5) was correct only by accident. All now route
through `_slice_bin`/`_grid_floor`, which reject non-finite input using the
`!(lo <= u <= hi)` idiom `_pic_cic_weights` established.

**Step 2 -- reductions. DONE (2026-08-01).** `is_live` (all six coordinates
finite) plus `allow_lost_particles`, a `Base.ScopedValues` flag that is **off by
default**. Off, every chokepoint fails fast exactly as before and the reductions
run unmasked; on, dead particles are skipped and `n_live` is the denominator.

The flag exists because the aperture that makes a NaN legitimate does not land
until step 3. Masking unconditionally now would have surrendered NaN-means-bug
detection for a whole step with nothing yet able to produce a deliberate loss.

The mask is a compile-time switch (`LiveMask{ON}`, or `flags === nothing` where a
call makes several passes), so the default path constant-folds back to the
original loop -- measured at 0.595 vs 0.597 ms on a 1e6-element reduction, i.e.
no cost. The masked path costs ~3.4x there, all of it from loading six arrays
instead of one, which the all-six rule requires.

Masked on `!isfinite`, never on `isnan`, so `Inf` (overflow) stays
distinguishable from `NaN` (invalid operation, and deliberate kill).

Sites, beyond the three the plan listed:

- `BeamObservers.jl` moment rows, CPU and CUDA, plus `_compute_moment` /
  `_cuda_compute_moment!`. Also `beam_statistics`, same family, and its `n`
  field now reports the denominator actually used.
- `strong_beam_track.jl` luminosity, all four sums. Liveness is judged on the
  coordinates the map *returned*, not the ones it consumed: a particle that goes
  non-finite mid-turn yields a NaN contribution, and testing the input would let
  that into the sum.
- `gaussian.jl` `_gaussian_moments_finite` -- guard body unchanged, meaning
  restated. Dead particles never reach it because slicing drops them, so a
  non-finite moment now means a *live* particle produced one, still a bug.
- **Slicing, which the plan did not list and which gated the rest.** Step 1
  fixed the index conversion; the boundary reductions (`minimum`/`maximum`/`sum`
  over `z`, 11 sites plus 5 CUDA twins) were still unmasked, and each of the
  five methods failed differently and silently: equal-width got NaN boundaries
  so `_slice_bin` dropped *every* particle; `_slices_from_boundaries` sent NaN to
  `searchsortedlast`, which orders it above every boundary and filed it into the
  *last* slice; equal-count's `sortperm` piled the dead there too. Slice weights
  are now a fraction of the live beam, so they still sum to one.
- Spectral Dirichlet box (`_spectral_box`, `_spectral_box_drifted`). Unlike the
  PIC meshes, it is built from whole coordinate arrays rather than from slice
  membership, so the mask slicing applies for free does not reach it.

Masking slicing turned out to cover `_slice_transverse_moments` for free: it only
ever sees `slices.indices[i]`, so pre-filtered membership excludes the dead
without touching the moment kernels. Verified bit-exact against a survivor-only
beam rather than assumed.

**`_pic_kbb1`/`_pic_kbb2` were deliberately left dividing by the full
macroparticle count.** A lost particle stops depositing, so the bunch carries
proportionally less charge -- which is what losing a particle physically means.
Renormalizing by the survivor count would hold bunch charge fixed while particles
disappear. The `_nonfinite_coordinate_error` docstring, which asserted the
solvers have no lost-particle concept, was updated to say this.

Verification: masked results are bit-exact against a beam that simply omits the
dead particles (slicing under all five methods, slice moments, `beam_statistics`,
moment observer rows), and all five solvers return bit-identical luminosity
across three wildly different corpse states -- including one where the dead carry
finite transverse coordinates of ±1e3, seven orders of magnitude outside the
beam. 127 assertions in five new testsets; the original fail-fast testset passes
unchanged.

One testing trap worth keeping, found while writing the acceptance test: **PIC
luminosity at small N is dominated by discretization noise**, enough to make
"masked vs survivor beam" useless as a correctness test there. At n=32 with a
64x64 grid, dropping particle 5 versus particle 9 changes the answer by 46%. The
test therefore uses n=4000 and asserts corpse-state invariance instead, which is
the property actually wanted. This is a property of PIC, not a defect.

The gap that fail-fast still has is its own item below.

Step 3 should turn `allow_lost_particles` on for itself: an aperture in the
lattice is exactly the evidence that a NaN can be deliberate, so the element (or
the task holding the loss record) is the natural thing to enable the scope rather
than leaving it to the caller.

**Step 3 -- the aperture element. DONE (2026-08-01)**, `src/elements/aperture.jl`;
see the sub-step record below for what the plan did not anticipate. The
constraints it was planned against, all of which held: non-symplectic, so it
declares
`NonSymplectic6DMap` rather than `Symplectic6DMap`; needs a probe in
`DEFAULT_ELEMENT_PARAM_PROBES`, and the `alive` predicate needs an entry in
`DEFAULT_INACTIVE_ELEMENT_PARAMS` because a function has no meaningful
perturbation. The predicate must be a **type parameter** on the runtime, not an
`Any` field, or it will not compile for the GPU. `Marker{M}` is the precedent but
is parameterized on the tracking method only, so this needs `Aperture{F,M}`.

Sequenced like step 2, and for the same reason: a half-built loss record reports
plausible numbers and looks finished. **Do not start a later sub-step before the
earlier one is green.**

### Decisions taken up front

The four questions left open in the design note are answered here, because (Q1)
and (Q3) determine the element's signature and are awkward to retrofit.

**Q3 -- where the check happens: at the element, one point, no `aperture_at`.**
The aperture is **thin** and checks where you place it. A magnet or drift that
needs both faces guarded gets two aperture elements, one on each side. This is
the Xsuite/Elegant bargain the design note already accepted, and
entrance/exit/both only becomes meaningful when an aperture *wraps* a magnet,
which is deferred.

Two consequences, both improvements over a single element carrying an
`aperture_at` flag. The two apertures are **distinct elements with distinct
ids**, so the log already distinguishes an entrance loss from an exit loss
without any extra field -- Bmad needs `aperture_at` precisely because its
aperture is one element and cannot. And a thin element composes: it can be
dropped between any two elements without knowing what they are.

The limit is unchanged and worth restating: a particle that leaves the aperture
*inside* the magnet body is not caught until the exit element, so it is logged at
the exit `s` rather than where it actually left. Resolution is where you place
apertures. Narrowing it means placing more of them.

**Q4 -- misalignment: the aperture carries its own `dx`/`dy` offset.** As a
separate element a displaced magnet's aperture is nominally the user's problem,
but making them re-derive an offset invites silent error, and an offset is two
subtractions. It is checked in the aperture's own frame. It does **not** go
through `_misalign_frames`: an aperture has no body to tilt through, and a
rotation of a transverse limit is a shape change, not a frame change. Document
that a rotated collimator needs the predicate.

**Q1 -- the record is per beam, owned by the task, handed to the element.** It
cannot be per element: the per-particle slot below is `O(N)`, so a hundred
apertures would be a hundred copies. The task allocates one `LossRecord` per
beam and injects it at `compile_runtime`, the same way a `ScheduledObserver` is
handed its buffer. A particle is lost at most once, so one shared record across
every aperture in the lattice is exactly right.

**Q2 -- reconciliation is reported by the task, not the aperture.** No single
aperture can know the total. See sub-step 3e.

**Q5 in the design note is already answered** by step 2 and can be struck: a NaN
particle no longer occupies a slice or a grid cell, under all five slicing
methods, verified bit-exact.

### Storage and output are different decisions

The design note runs these together -- it argues for one record per particle at
`~64 N` bytes, which is about how to *write* without contention, not about what
lands in the file. Separated:

**In memory: one slot per particle**, written at most once, no atomics. Two
reasons, and neither is the one the note gives. The note says an atomic "would
fire for every particle"; that is wrong, since the atomic would sit inside the
rare `newly_lost` branch -- the same argument the note itself uses to accept an
atomic for the counter. The real reasons are:

- **Determinism.** Slot `i` is always particle `i`, so CPU and CUDA produce
  byte-identical logs. An atomic append orders records by thread scheduling, and
  this codebase enforces CPU/CUDA identity by contract.
- **It cannot overflow.** A particle is lost at most once, so `N` slots is an
  exact bound. A compact append buffer has to guess a capacity and either
  over-allocate or drop records.

The cost is `~60 N` bytes per beam (`6` coordinates + turn + element id), and it
is paid **only when a log path is given**. At `1e6` particles that is 60 MB and
fine; at `1e8` it is 6 GB and not. Record that crossover: past roughly `1e7`
particles, switch to an atomic append sized at the expected loss fraction and
sort by particle index before writing, which restores deterministic *output*
while giving up deterministic *layout*.

**On disk: only the particles that were actually lost.** `element_id == 0` is the
never-lost sentinel, so the flush is a filter on that column. A run losing 1% of
`1e6` particles writes ~10k rows, not `1e6`.

**Format: HDF5, matching `MomentObserver`.** The record is exactly the table that
observer already writes, so it reuses the preallocate/buffer/`record_count`
pattern and the same reader tooling. Columns:

    particle_id, turn, element_id, x, px, y, py, z, pz

`particle_id` is a column **because** the output is filtered. In memory it is
implicit -- slot `i` is particle `i` -- but the flush drops the never-lost rows,
so row `k` is no longer particle `k` and the identity would be lost with it. The
in-memory layout therefore stores 8 values per slot and the file carries 9.
Keeping the slot free of the id is not a micro-optimization: it is what makes the
slot writable without reading anything back.

`particle_id` and `element_id` answer different questions and both are needed --
which particle was lost, and which aperture stopped it, hence at which `s`.

**Where `element_id` comes from, given that elements are anonymous.** There is no
name, label, or id field on any element spec in this codebase today; a lattice is
a tuple identified only by position. So `element_id` is the aperture's **index in
the compiled line**, assigned by the task when it builds the lattice: automatic,
unique, and collision-free without touching any other element type.

A bare index makes the log say "aperture 7" rather than "COLL_IP6_H", so the
aperture also takes a **`name`**, and the task writes a companion dataset mapping
`element_id` to that name, the lattice index, the element kind, and `s` if it can
accumulate lengths. The file is then self-describing instead of interpretable
only next to the script that produced it.

Nothing blocks this. `ElementSpec{Kind}` is a `Dict{Symbol,Any}`, so
`ElementSpec{:drift}(L=0.5, name="COLL_IP6_H")` already constructs today and
`validate_element_metadata()` passes with an undeclared `name` present. The name
also cannot leak into execution: `compile_runtime` on such a spec returns the
usual `isbits` runtime with no name field, which is the two-layer split doing its
job -- **the spec carries the name, the runtime carries only the integer id.**

Two details make it work rather than half-work:

- Declaring `name` in the aperture's `@element_spec` block is what makes
  `spec.name` and post-construction `spec.name = ...` legal. Undeclared, it is
  readable only as `getparam(spec, :name, "")`, because `setproperty!` rejects
  keys absent from the metadata.
- It needs an entry in `DEFAULT_INACTIVE_ELEMENT_PARAMS`, for the same reason the
  `alive` predicate does: perturbing a string produces no observable change, so
  `ElementParameterEffectivenessContract` cannot probe it and must be told so.

**Scope: the aperture only.** Naming every element kind is a fleet-wide change
(~25 metadata blocks, plus a schema row each) and genuinely useful beyond
apertures, but it is not required here and must not be smuggled into an aperture
commit. Its own item is below.

**No path, no output, and no allocation.** `loss_log=nothing` is the default and
means the aperture kills and counts and nothing else -- a dynamic-aperture scan
needs survival counts, not per-particle forensics, and that path must cost no
memory. Giving a path is what allocates the record.

### Sub-steps -- ALL DONE (2026-08-01), `src/elements/aperture.jl`

Every green condition below was met. What the plan did not anticipate:

- **The aperture loads after `Beam.jl`, not with the other elements.** It is the
  only element owning beam-scale storage -- its record is sized by particle count
  and allocated on the beam's backend -- so it needs `Phase6DRep` and the CUDA
  flags, which the spec layer does not. The file stays in `src/elements/`; only
  the include position moved.
- **`Adapt` needed hand-writing, not `@adapt_structure`.** The record's `names`
  is a `Vector{String}` with no device representation, so the adapt rule *drops*
  it rather than converting: the kernel writes an integer id and turning that
  back into "COLL_IP6_H" is the host's job at flush. `Aperture` itself also
  needed adapting, or its record reached the kernel as a host `CuArray`.
- **The public `track!` already carries a context**, so logging works through the
  normal API without the caller doing anything. Only the bare positional
  `track!(rep, elems, turns, policy)` lacks one, and that now throws rather than
  producing a correct run with a silently empty log
  (`_reject_contextless_tracking`).
- **`allow_lost_particles` is not enabled by the element.** The aperture kills
  and records without it; the flag governs *reductions*, so it belongs where a
  reduction runs. Turning it on globally because a lattice contains an aperture
  would change strong-strong behaviour as a side effect of lattice composition,
  which is exactly the coupling the non-interference requirement forbids.

**Non-interference is the load-bearing guarantee** and is now a test: an aperture
that kills nothing leaves coordinates *bit-identical* under plain tracking, under
weak-strong (coordinates **and** the luminosity diagnostic), and under all four
strong-strong solvers (luminosity and both beams). Not "close" -- identical.

69 assertions across five testsets; 85 testsets pass overall. Backend consistency
0.0 and 9.4e-16. Registry, element metadata, configuration metadata, and both
effectiveness contracts pass.

**3a -- the element, kill only.** `ApertureSpec` with `:rectangle`, `:ellipse`,
`:rectellipse`, `x_limit`/`y_limit`, `dx`/`dy`, and an `alive` predicate for the
rest; `Aperture{F,M}` runtime. `newly_lost = was_alive & !inside` with
`was_alive` testing all six coordinates. Enables `allow_lost_particles` for
itself. Green when: a particle outside is all-NaN afterwards and one inside is
bit-unchanged; the kill is idempotent across turns; the predicate path and the
equivalent analytic shape agree; CPU and CUDA produce identical survivors; and a
particle that arrives already non-finite is **not** attributed to the aperture.

**3b -- the survival counter.** `O(1)` per loss on the `newly_lost` transition.
Green when the counter equals the number of particles the aperture actually
killed, across turns and across several apertures, on both backends.

**3c -- the shared record.** `LossRecord` allocated by the task, one per beam,
injected through `compile_runtime`; per-particle slot; written once. Green when
every killed particle has exactly one row with the **pre-kill** coordinates, no
row is overwritten by a later aperture or a later turn, and CPU and CUDA records
are byte-identical.

**3d -- HDF5 output.** Filtered flush, lost particles only. Green when the file
contains exactly the killed particles, the coordinates round-trip, and
`loss_log=nothing` creates no file and allocates no record.

**3e -- the reconciliation diagnostic.** Task-level summary reporting both
`count_dead` and the aperture-logged total, so the gap -- particles lost to
numerical blowup, which no aperture can claim -- stays visible rather than
silently reducing the survivor count. Green when an injected non-finite particle
that never meets an aperture shows up in the gap and not in the log.

**Step 4 -- the acceptance test. DONE (2026-08-01).** Both halves are in place.
The reduction half: the moment observer, `beam_statistics`, luminosity and all
five solvers produce correct finite output over survivors, checked against a
survivor-only beam. The end-to-end half: a beam tracked through a lattice with
real aperture elements, losses produced by the apertures rather than injected,
and the loss log reconciled against `count_dead` -- including hand-killed
particles that no aperture can claim showing up in the gap and *not* in the log.

Remaining, and deliberately not done here:

- **Wiring `loss_summary` into `TrackingTask`'s automatic diagnostics.** It is a
  public function today and the task can call it; making it fire on the observer
  schedule without being asked is a task-diagnostics change, not an aperture one.
- **A task-owned record.** The record is allocated by the caller and passed to
  `ApertureSpec(loss_record=...)`, with `element_id` assigned by hand. Having the
  task allocate one per beam and stamp ids from lattice position is the
  ergonomic finish; the mechanism it would use is already here.
- **Element names fleet-wide**, its own item below.

## `curved` keyword for every magnet: DONE (2026-08-02)

`SolenoidSpec(; curved)` selects the tracking path explicitly instead of the
path being inferred from `h != 0`. `nothing` (default) lets the frame decide;
`true` and `false` override it. Both overrides earn their place:

- **`curved = true, h = 0`** runs the integrator on a straight frame, where the
  exact closed form *also* exists. That is a **direct** validation of the
  integrator against a reference with no error of its own, rather than an
  `h -> 0` limit where the two disagree at `O(hL)` for physical reasons and the
  integration error has to be disentangled from the physics. Measured: second
  order against the exact map, `8.0e-6 / 5.1e-7 / 3.2e-8 / 2.0e-9` at
  `nst = 8/32/128/512`, ratios 15.8/16.0/16.0. This is a strictly better test
  than the limit it replaces and is the reason the keyword exists.
- **`curved = false, h != 0`** ignores the curvature and tracks straight — a
  legitimate approximation to ask for, and it **warns** rather than doing it
  silently.

**DONE for the lattice magnets too (2026-08-02).** `LatticeMagnet{...,CURVED}`
carries the choice, resolved in `compile_runtime`, and `_lattice_drift` split
into `Val{false}`/`Val{true}` methods. The runtime `h == 0` test that lived
inside the drift kernel is gone: nothing about curvature is decided during
tracking. `DriftSpec` and `SBendSpec` (hence quadrupole, sextupole, octupole and
multipole, which share the runtime) take `curved`.

Behaviour-preserving, which was the risk: **PTC still passes at 5e-13 across all
41 cases**, backend consistency unchanged, and `curved = true` at `h = 0` agrees
with the straight closed form to 1.1e-16 for drift, quadrupole and sextupole.
That last one is the check the keyword buys here -- both paths are exact for
these elements, so it validates the code path rather than an approximation, and
it would have caught the curved branch silently disagreeing.

A value-dispatched `_lattice_drift(h, L, ...)` shim remains for callers holding
`h` as a number (tests, the solenoid's drift-limit check).

**Still a runtime branch, and deliberately left:** `_body_step` tests
`elem.b0 == 0` to choose drift versus bend. That is a different question from
curvature -- dipole or not, rather than which frame -- and folding it into the
type would double the specializations again. Worth doing under the same
principle if a measurement ever justifies it.

~~**Remaining: the same keyword on every other magnet.**~~ Superseded: `DriftSpec`,
`QuadrupoleSpec`, `SextupoleSpec`, `OctupoleSpec`, `MultipoleSpec` and
`SBendSpec` all take `h` already, and all branch on `h == 0` at *runtime* inside
`_lattice_drift`/`_lattice_bend`. Two things to weigh before doing it, because
they cut in opposite directions:

- **Lower payoff than the solenoid.** For those elements *both* branches are
  exact, so `curved = true, h = 0` validates a code path but not an
  approximation — there is no integrator whose convergence needs proving. The
  test value that motivated the keyword is largely specific to the solenoid.
- **Higher cost.** Their curvature branch lives inside the shared
  `_lattice_drift`/`_lattice_bend` kernels rather than at dispatch, so making it
  a type parameter means threading `CURVED` through `LatticeMagnet{...}` and its
  helpers — a change to the most heavily validated element in the codebase,
  currently at 5e-13 against PTC across 41 cases.

Worth doing for interface uniformity, which is the stated reason, but it should
be a deliberate refactor with the PTC contract re-run rather than a ride-along.
Do it when something else already requires touching `LatticeMagnet`.

## Patch element: DONE (2026-08-01), `src/elements/patch.jl`

Implemented per the specification below. Translate the origin, rotate the axes,
drift to the new entrance face — exact in `(1+delta)` and in amplitude, because
it is geometry rather than an expansion.

**A naming collision had to be resolved, and it was a real bug first.** The
obvious spellings `x_pitch`/`y_pitch`/`tilt` are **misalignment** parameter
names, so `compile_runtime` silently wrapped the patch in a `MisalignedElement`
and applied the rotation twice. Renamed to `angle_x`/`angle_y`/`angle_s`, which
is unambiguous and also matches MAD-X's `patch_ang = {θx, θy, θs}`. Worth
knowing generally: any new element whose parameters collide with the
misalignment set will be silently wrapped rather than rejected.

Verification, all self-contained:

- **Patch ∘ patch⁻¹ = identity** to `1e-18` for each of translation, `angle_x`,
  `angle_y`, `angle_s` and `t_offset`. This is the check that catches an
  inverted `W`, which passes almost everything else.
- **A pure `dz` patch is bit-identical to `DriftSpec(L=dz)`.** The
  drift-to-the-face step is what gives a patch an effective length, so this
  fails if `dz` merely relabels `s`.
- **Which frame changes a drift is invariant under, and which it is not.** A
  transverse shift and a roll leave a drift unchanged (`1e-16` and `2e-19`);
  a *pitch* does not, and moves the endpoint by `L*theta` — measured
  `7.5e-3` against `1.5 * 5e-3`. Getting this backwards is what happens if the
  position is not rotated along with the momentum, which the round-trip test
  alone would not catch.
- Symplectic to `1e-8` (finite-difference Jacobian), effectiveness and
  metadata contracts pass, dead particles stay dead.

**MAD-X validation was attempted and does not work.** MAD-X has `changeref`
with `patch_ang`/`patch_trans`, which is the right element, but it aborts with
*"memory access outside program range, fatal"* in the PTC tracking harness. Not
pursued: the self-contained checks above are stronger than a single reference
orbit would be, and the round-trip and drift-equivalence tests need no external
code. Worth one retry if a MAD-X version that survives `changeref` appears.

Still open, inherited from the misalignment note's Section 8: the rotation
**order** is `R_z R_x R_y` here, and PTC composes x-pitch, y-pitch, roll while
Bmad forms `R_y R_x R_z` with a sign flip. Single-axis rotations agree by
construction; the three-axis composition differs at second order in the angles
and is **not** pinned against a reference. That is the same open question that
blocks bend misalignments, and it should be settled once for both.

### Original specification, retained

## Patch element: original scoping (2026-08-01)

Recommended by Section 7.5 of
[`misalignment_and_patch_maps.md`](theory/misalignment_and_patch_maps.md) and
never built. Confirmed absent: nothing in `src/` implements it, the registry has
no `:patch`, and the only occurrence of the word is a doc-reference comment in
`misalignment.jl`.

**A patch is not a misalignment, and `MisalignedElement` cannot stand in for
one.** The distinction is what the element *means*, not how it is coded:

| | misalignment | patch |
|---|---|---|
| intent | an **error**: the magnet is not where it was meant to be | **deliberate**: the reference frame genuinely changes here |
| attaches to | one element, referenced to its centre | nothing — it is its own element |
| afterwards | the frame is **restored**; the error is local | the new frame **persists** downstream |
| carries a time offset | no | yes (Bmad's `t_offset`) |
| survey meaning | a deviation from the design geometry | *is* the design geometry |

Using a misalignment to express a crossing angle would be wrong in both
directions: it would restore the frame at the element exit when the geometry says
it should not, and it would record a deliberate design choice as a machine error
in anything that reports alignment.

**What it is for:** crossing angles, beamline junctions, spectrometer arms,
injection/extraction geometry — and, concretely today, the straight solenoid
traversed by a curved orbit that the curved-frame item below has no other way to
express.

**Specification exists and is complete.** Bmad's `track_a_patch`
(`bmad/low_level/track_a_patch.f90`) is the reference:

- parameters `x_offset, y_offset, z_offset`, `x_pitch, y_pitch, tilt`,
  `t_offset`, plus upstream/downstream direction flags;
- form the full 3-momentum
  `p_vec = [px, py, sqrt((1+delta)^2 - px^2 - py^2)]` and the offset position
  `r_vec`, rotate **both** by the frame matrix `W` from
  `floor_angles_to_w_mat`, then drift to the exit face;
- the drift-to-exit is what gives a patch an effective length and makes
  `z_offset` change path length rather than merely relabel.

Notes for whoever builds it. `_rot_xz` in `lattice_magnets.jl` already matches
PTC bit for bit and should be reused rather than re-derived (Section 7.3 of the
note). The rotation order and signs must be pinned against a reference case
first — the same open question that still blocks bend misalignments, since PTC
composes x-pitch, y-pitch, roll while Bmad forms `R_y R_x R_z` with a sign flip,
and the two differ at second order in the angles. And Section 7.6's contract is
the right validation and needs no external reference: **misalign an entire cell
by one rigid transform, apply the inverse patch at both ends, and the aligned map
must come back to roundoff.**

## Solenoid in a curved frame: REOPENED then DONE (2026-08-02)

**The 2026-08-01 closure below was wrong on its central claim and is
withdrawn.** It said adding `h` "would build a tokamak magnet and call it a
solenoid". That is not model-mixing: **a solenoid bent around an arc *is* a
toroidal field.** The 1/R falloff is what bending a solenoid physically does,
not a different magnet substituted for it.

The physics the closure got right still stands and is worth keeping: constant
`B_s` in a curved frame is not a vacuum field (curl `= B_s/R`, measured 0.4348
against the predicted 0.4348), and the Maxwell-consistent field is
`B_s = B_0/(1+hx)`, curl-free to 2.5e-11. What the closure got wrong was calling
that the wrong object. It is the *right* object, and by exactly the construction
Octopus already uses for curved multipoles: a field that satisfies Maxwell **in
the curved frame** and reduces to the intended straight field on the reference
orbit (`x=0`, where `B_s = B_0`) and as `h -> 0`. That is what the `psi`
curved-frame potential table is for, and there is no reason the solenoid should
be exempt.

So the standing request — **nonzero `h` for every element**, matching the
existing nonzero-`h` drift and bend — is correct, and the solenoid is not a
counterexample.

What remains true, and is cost rather than obstruction:

- **No closed form.** `a_y = (k_s/h) ln(1+hx)` puts a logarithm inside the
  Hamiltonian's square root, so `p_s` no longer closes the system the way
  Section 4 of the theory note relies on. The curved solenoid needs an
  integrator with `nst` and an integrator order, exactly as the curved
  multipoles do. It stops being exact; that is the same trade the curved
  multipoles already made.
- **Nothing external validates it.** PTC's `SOL5` carries no curvature at all
  and `GETMULB_SOL` has no `(1+hx)`; Bmad, MAD-X and Elegant are straight-frame
  only. The validation is therefore the one the request already names:
  **agreement with the `h=0` map as `h -> 0`**, plus symplecticity and the
  curl-free check on whatever field the potential implies.

**IMPLEMENTED (2026-08-02)**, `src/elements/solenoid.jl`, derived in Section 15
of the theory note. `SolenoidSpec(; h, nst)`; `h = 0` still takes the exact
closed form untouched.

The obstruction turned out to be sharper than "no closed form": **`H` does not
split into two exactly-solvable pieces either.** Every other curved element in
Octopus splits as (exact curved drift) + (kick from `a_s`), which works because a
multipole's potential is purely longitudinal. A solenoid's is transverse, sits
inside the square root, and no gauge moves it out. Composing the exact curved
drift with the exact straight solenoid -- the tempting shortcut -- converges to
the **wrong Hamiltonian**, since those two carry two square roots where `H` has
one. So a *general* symplectic integrator was needed, not a splitting one.

Implemented with **implicit midpoint**: symplectic for any Hamiltonian, second
order, time-reversible. The gauge was chosen so `g(x) -> x` as `h -> 0`, which
makes the flat limit the *same* map as the exact straight one rather than merely
a close one.

**The fixed-point sweep count is a correctness parameter, not a tuning knob**, and
this was nearly shipped wrong. Implicit midpoint is symplectic only when the
implicit stage is solved to convergence; a truncated solve is a convergent
explicit method wearing the name. Measured `|M'JM - J|`:

    sweeps    nst=4      nst=16     nst=64
    4         4.2e-3     4.5e-6     4.3e-9
    8         2.6e-5     5.1e-10    4.9e-10
    16        1.4e-9     3.0e-10    5.2e-10

At 4 and 8 sweeps the symplectic error tracks the *truncation* error, so it
would have passed every accuracy test while quietly not being symplectic. Set to
16, where it sits on the finite-difference noise floor at every step count --
a coarse `nst` now gives a less accurate but still symplectic map, which is what
a ring needs. That is the cost accepted deliberately.

**`nst` defaults to 1 straight but 16 curved**, and that asymmetry is a
correctness fix rather than a convenience. A straight solenoid is the exact flow
and ignores `nst`; a curved one is integrated, and `nst = 1` there does not
merely lose accuracy -- at `h = 0.18` over `L = 1.3` the implicit stage fails to
converge and returns an error of **1.09 against coordinates of 1e-3**. A single
shared default of 1 would have let `SolenoidSpec(L=..., ks=..., h=...)` silently
return nonsense. An explicit `nst = 1` is still honoured.

Cost, measured: **165 ns/particle straight against 5524 ns at `h != 0`,
`nst = 8`** -- 33x. That is 16 fixed-point sweeps over 8 steps, so ~136
derivative evaluations against one closed-form map; 33x is the price of
curvature here and is better than the naive count suggests.

Verification: `ks=0` reproduces `_lattice_drift(h, L, ...)`; `h -> 0` converges
to the exact straight map at second order; the residual at finite `h` is linear
in `h`, which is the curvature doing its job rather than an error; second-order
convergence in `nst` measured at 15.8/16.0/16.1; symplectic at `nst` 4, 16 and
64; and curvature composes with the superimposed multipoles. 15 assertions.

## Solenoid in a curved frame: withdrawn closure, retained for the record (2026-08-01)

Asked for on the grounds that every other lattice element takes a frame
curvature and the conventions note says $h$ belongs to the frame rather than the
magnet. Derived in [`docs/theory/solenoid.md`](theory/solenoid.md) Section 13,
and the answer is that **a solenoid with $h\neq0$ is not a solenoid.**

**Constant $B_s$ in a curved frame is not a vacuum field.** In cylindrical
coordinates about the bend centre,
$(\nabla\times\mathbf B)_Y = \tfrac{1}{R}\partial_R(R\,B_\varphi)$, which for
constant $B_s$ is $B_s/R\neq0$ — it needs a current density throughout the beam
pipe. Verified numerically at $\rho=2$, $x=0.3$: $|\nabla\times\mathbf B|=0.4348$
against the predicted $B_s/R=0.4348$, with $\nabla\cdot\mathbf B=0$ exactly, so
it is the curl that fails and not the divergence.

**What is consistent is $B_s = B_0/(1+hx)$** — curl-free to $2.5\times10^{-11}$
numerically — but that is a **toroidal** field, the field of a current filament
along the bend axis. Adding `h` to `Solenoid` would build a tokamak magnet and
call it a solenoid, which is the same silent model-mixing that got the paraxial
matrix rejected.

**The case that actually motivates the request is different again.** A detector
solenoid with a crossing angle is a *straight* solenoid whose axis does not
follow a curved reference orbit. Its field is longitudinal about *its own* axis;
expanded in the curved frame it is not longitudinal at all. The clean expression
is a **patch, a straight solenoid, a patch back** — and the patch element does
**not exist yet**; see the item below. `MisalignedElement` is not a substitute,
for the reason given there. So this case currently has no clean expression in
Octopus, which argues for building the patch rather than for adding `h`.

If a genuine toroidal element is ever wanted it needs its own name and its own
integrator: the potential $\hat a_y=(k_s/h)\ln(1+hx)$ puts a logarithm inside
the Hamiltonian's square root, so $p_s$ no longer closes the system and the map
is not exact. And nothing validates it — PTC's `SOL5` carries no curvature at
all (`GETMULB_SOL` has no $(1+hx)$ anywhere), and Bmad, MAD-X and Elegant are
straight-frame only, so the only check is agreement with the $h=0$ map as
$h\to0$.

**Recommendation: closed. Do not add `h` to `Solenoid`.** Reach for the patch
maps if a curved-orbit solenoid study appears.

## Soft-fringe solenoid (2026-08-01)

The exact solenoid ([`docs/theory/solenoid.md`](theory/solenoid.md)) is
**hard edge**: $B_s$ is constant on $[0,L]$ and zero outside, so the entrance and
exit fringes collapse to the impulsive canonical-to-kinetic conversion. A real
solenoid's $B_s$ rises over a finite length, and in that transition the radial
field $B_r=-\tfrac{r}{2}\,\mathrm dB_s/\mathrm ds$ acts over a finite distance
rather than as an impulse — a difference that grows with radius and is therefore
worst exactly where a final-focus solenoid matters.

**Survey of the four benchmark codes, read from source (2026-08-01), because the
answer decides whether this is portable work or original work:**

| code | element | fringe |
|---|---|---|
| PTC | `SOL5`/`kind5` | hard edge, buried in `KICK_SOL`; **no fringe routine exists** |
| Bmad | solenoid | hard edge, and **mandatory** — *"must always apply the fringe kick due to the longitudinal field"* |
| MAD-X | `SOLENOID` | hard edge (dispatches to PTC) |
| Elegant | `SOLE` | hard edge, 2nd-order **matrix**, no fringe parameter at all |
| Elegant | `MAPSOLENOID` | **numerically integrated $(B_z,B_r)$ field map** |

So exactly one of the four has anything soft, and it is a **field-map
integrator, not an analytic soft-edge map**. There is no closed-form soft
solenoid fringe in the literature these codes implement that we could port and
benchmark against. That splits the work in two, and they are not the same size:

**(a) An analytic soft-edge model.** Pick a profile — Enge, `tanh`, or Bmad's
higher-order edge treatment — and derive the map for it. Cheap to implement and
it stays symplectic, but **nothing to validate against**: none of the four codes
has the same model, so the only check would be against (b) or against a field map
built to match the chosen profile. Expect to spend the effort on validation
design rather than on the map.

**(b) A field-map solenoid, matching `MAPSOLENOID`.** Read $(B_r,B_z)$ vs
$(r,z)$, integrate numerically. Directly benchmarkable against Elegant, which is
its main attraction. But it is a much larger piece: field-map I/O, off-axis
interpolation (or on-axis expansion when only $r=0$ data is given, as Elegant
supports), an adaptive integrator, and an accuracy tolerance — and the result is
**not symplectic**, so it would be the first non-symplectic magnet in Octopus and
would need `NonSymplectic6DMap` plus a story about what that costs over many
turns.

**Recommendation: do neither until a study needs it.** The hard-edge map is
exact, symplectic, and matches PTC to $4.9\times10^{-13}$; it is the same model
three of the four codes ship as their only option. Revisit if a detector-region
or final-focus study cares about the fringe region at large radius, and prefer
**(b)** when that happens — being able to check against Elegant is worth more
than the symplecticity given the model is an approximation of a measured field
anyway.

One prerequisite either way: the hard-edge map should stay wrappable, so a fringe
model composes with it rather than being interleaved into the body integrator.
That is how it is written today.

## `ref_tilt` for bends: NOT STARTED (2026-08-02)

Octopus can misalign a bend but **cannot express a vertical one**, and the two
are different things that a single `tilt` keyword currently conflates.

**The mapping between the codes, read from source:**

| meaning | Bmad | MAD-X | Octopus |
|---|---|---|---|
| roll the magnet **body**; design orbit unchanged, field rotated — an *error* | `roll` | `EALIGN, dpsi` | `tilt` (misalignment) ✅ |
| roll the **design orbit plane**; the reference trajectory itself bends elsewhere — a *design choice* | `ref_tilt` | `sbend, tilt=` | **missing** ❌ |

So MAD-X's `tilt` **on a bend** is Bmad's `ref_tilt`, not Octopus's `tilt`, and
that is the trap: the same word means the error in one place and the design in
another. A vertical bend is a horizontal bend with `ref_tilt = pi/2`, and today
that is inexpressible.

**Why it is not simply another misalignment.** `ref_tilt` changes the *survey* —
where the lattice goes in space — and Octopus has no geometry layer (the
misalignment note's Section 8 says so). Bmad threads it through `bend_shift`,
i.e. through the geometry, not the body map.

**What is implementable now, and what is not.** Locally, `ref_tilt` on one bend
is a conjugation: rotate `(x, px, y, py)` by `-ref_tilt`, track the bend, rotate
back. That is small, and directly checkable against `sbend, l=..., angle=...,
tilt=...` in the existing PTC harness. What that does *not* give is the
downstream geometric consequence — after a vertical bend the whole lattice is in
a different plane — which needs the survey Octopus does not have. The same
limitation the patch already carries.

**Ordering matters and must be pinned:** `ref_tilt` is design geometry, so it
composes **outside** the misalignment frames, not inside them. A rolled *and*
misaligned bend gets `ref_tilt` applied to the design orbit first, then the body
error relative to that. Getting this inverted is invisible unless both are
nonzero — the same second-order trap the rotation convention just turned out to
be, so it needs a two-parameter PTC case rather than a one-parameter one.

## Element names, fleet-wide (2026-08-01)

Split out of the step-3 aperture work, which needs a name for **one** element and
should not drag the other twenty-five along.

Today a lattice is anonymous: no element spec has a name, label, or id field, so
an element is identified only by its position in the tuple. Every diagnostic that
wants to say *where* something happened is therefore reduced to an index --
the aperture loss log is just the first place this has bitten.

Nothing structural is in the way, which is why this is a chore rather than a
design problem. `ElementSpec{Kind}` wraps a `Dict{Symbol,Any}`, so a name already
constructs and stores, `validate_element_metadata()` already passes with one
present, and `compile_runtime` already drops it -- the runtime stays `isbits` and
GPU-safe because the two-layer split keeps descriptive fields in the spec layer.
Verified on `:drift`.

What it actually costs:

- A `name` entry in each element's `@element_spec` block, which is what makes
  `spec.name` readable and `spec.name = ...` assignable. Undeclared it is still
  reachable as `getparam(spec, :name, "")`, so this buys ergonomics and schema
  visibility, not capability.
- One `DEFAULT_INACTIVE_ELEMENT_PARAMS` entry per element: a string has no
  meaningful perturbation, so the effectiveness contract has to be told not to
  probe it. Same treatment as the aperture's `alive` predicate.
- A row per element in `parameter_schema` and the registry snapshot.

Not needed: a change to any constructor. Absent-means-unnamed via `getparam`
covers every existing call site, so no element's signature has to move.

Worth doing when a second consumer appears -- lattice serialization, a survey
listing, or any diagnostic that reports a position. One consumer (the loss log)
is served adequately by the aperture-only version, and doing it fleet-wide on
that evidence alone would be speculative.

## Fail-fast does not cover every coordinate (logged, not fixed, 2026-08-01)

Pre-existing, found while doing the step-2 reduction masking above, and
**deliberately left open** -- see the decision at the end.

**The gap.** A chokepoint only detects a non-finite value in a coordinate some
reduction actually reads. Slicing reads `z`; the transverse moments read
`x, px, y, py`. Nothing reads `pz`. So with `allow_lost_particles` **off**, a
particle that goes non-finite in `pz` alone passes every guard and is silently
included:

    NaN pz, flag off:  luminosity 2.604e8   (correct value 2.573e8, 1.2% wrong)

It does not throw, and the number it returns looks perfectly ordinary. The same
shape appears in any reduction that reads a subset of the six: the `mean_y` of a
beam whose particles died in `py` comes back finite and **2x wrong**, because `y`
itself is fine and the corpse is still in the average. The existing fail-fast
testset never poisoned `pz`, which is why this survived.

**Not a regression, and not what the mask fixed.** With the flag **on** this is
already correct: liveness tests all six coordinates, so a `pz`-dead particle is
excluded from every reduction exactly like an `x`-dead one -- verified by
poisoning each of the six in turn and getting bit-identical luminosity. The gap
exists only on the fail-fast path, which is untouched by that work.

**Step 3 does not close it either.** The aperture element adds a place where a
NaN is *created*, not detection coverage on the flag-off path. What Step 3 does
add is the unattributed-death reconciliation (`count_dead` minus what the
apertures logged), which tests all six coordinates and would therefore surface a
`pz` blowup as a death no aperture claims -- but as a post-hoc count, not as a
fail-fast throw, and only when the flag is on.

**What closing it would cost.** A real liveness scan at solver entry: one O(N)
pass over six arrays per collide per turn. That is precisely the cost the current
chokepoint design avoids by piggybacking on reductions that were happening
anyway, so it is a performance-versus-safety trade rather than a patch.

**Decision (2026-08-01): log it, do not fix it.** Production runs are expected to
have the flag on, where the gap does not apply. Revisit if that assumption
changes -- specifically if any of these become true:

- A workflow runs with the flag **off** on a beam that can diverge numerically,
  where a silently-wrong result is worse than a stopped run.
- The unattributed-death count from step 3 starts being used as the *primary*
  divergence signal, at which point post-hoc counting may not be prompt enough.
- The measured cost of an entry scan turns out to be negligible against the
  solve, which is plausible: masking measured 0.99x on a 20k-particle PIC collide
  because the FFTs dominate. That number is for the mask, not for an entry scan,
  but it suggests the trade may be cheaper than the design assumed.

## Lattice magnets: remaining work

### Element coverage (2026-08-01)

Added: `marker` (identity placeholder), `rbend`, `thin_multipole`,
`thin_dipole`, `thin_quadrupole`, `thin_sextupole`, `hkicker`, `vkicker`,
`kicker`. All nine share existing machinery -- RBEND is the sector-bend map with
`angle/2` on each face, exactly MAD-X's conversion, and the thin family is one
`ThinMultipole` runtime. Four new PTC cases (`rbend`, `rbend_k1`,
`thin_multipole`, `thin_multipole_skew`) agree to 5e-13; the contract now covers
36 cases.

Every one of them that is a magnet takes misalignments through the same
`_misalign_frames`/`_frame_change` path the thick magnets use, so a thin element
and a thick one cannot drift apart in convention. At zero length the entrance,
centre and exit coincide, so the reference point cannot matter and `:bmad` and
`:madx` differ only in the rotation composition order. `marker` is the exception
and takes none: a rigid displacement of a zero-length identity map is still the
identity, so there is nothing to store.

Misalignment composes with an element rather than living inside it
(`src/elements/misalignment.jl`). `compile_runtime` wraps whatever runtime an
element produces in a `MisalignedElement` when the spec carries a displacement,
and returns it untouched otherwise:

    aligned     LatticeMagnet{...}                     ThinMultipole{...}
    misaligned  MisalignedElement{LatticeMagnet{...}}  MisalignedElement{ThinMultipole{...}}

So a new element type gets misalignments for free and cannot get the convention
subtly wrong, and an aligned element is byte-identical to what it was before
misalignments existed. The first implementation put the frames and branches
inside `LatticeMagnet` and then duplicated them into `ThinMultipole`, which is
exactly the duplication this avoids -- a solenoid or a cavity would have needed
a third copy.

Two conventions are worth keeping straight, and both are enforced by tests:
`knl[i]` is the **integrated** `K_{i-1} L`, not the thick `kn`; and a corrector
gives `dpx = +hkick` while a dipole field of the same magnitude gives
`dpx = -k0l`. Folding the second into the first would flip every corrector in a
lattice.

`ElementParameterEffectivenessContract` closes the class of bug that let the
thin elements accept `x_offset` and drop it: it builds each element through its
friendly constructor, perturbs one declared parameter at a time, and reports any
whose perturbation leaves the tracked map bitwise identical. **208 parameters
across every element kind with a friendly constructor**; kinds without an
explicit probe fall back to their own curated `example_spec`.

Two lessons from getting it green, both recorded in the source. First, probing
must go through the friendly constructor: `Linear6D` uses a stored `matrix` when
there is one, so probing its example -- which stores the folded matrix -- reports
every optics input as ignored, exactly as a raw probe reports `k1` as ignored
because it folds into `kn`. Second, "declared but not consumed" and "consumed
somewhere this probe cannot see" are different findings and the `inactive` list
says which: `thin_strong_beam.klum` reaches the runtime but feeds the luminosity
diagnostic rather than the coordinate map, and the `lumped_radiation` excitation
parameters are on the stochastic path a single deterministic call never takes.
Those are limits of a map-based probe, not inert parameters, and closing them
needs a diagnostic-boundary and a stochastic check respectively.

**Still missing, and deliberately not attempted here** -- each needs work beyond
adding an element spec:

- ~~**Solenoid.**~~ **DONE (2026-08-01)**, `src/elements/solenoid.jl`, derived
  first in [`docs/theory/solenoid.md`](theory/solenoid.md). The exact map from
  the same Hamiltonian, benchmarked against PTC as the bends were:
  **4.9e-13 across three cases including both polarities**, and the contract now
  covers 39 cases. The concern that motivated the entry is answered directly --
  `ks = 0` reproduces `_lattice_drift(h=0)` to **8.7e-17**, i.e. roundoff rather
  than a tolerance, so a switched-off solenoid is the same drift the rest of the
  lattice uses.

  The physics that made this element different from every other one: a
  longitudinal field has a *transverse* vector potential, so inside a solenoid
  the stored canonical `px`/`py` are **not** the particle's transverse momenta.
  Everything else follows from that -- most usefully, the textbook entrance and
  exit fringe kicks turn out not to be a separate model at all but the
  canonical-to-kinetic conversion forced by `a` jumping at a hard edge, so they
  are included by construction and cannot be switched off or given inconsistent
  signs at the two faces.

  Because `p_s` is conserved the map is closed-form, and because `kappa`
  depends on `p_s` the chromatic and amplitude dependence come out with no extra
  terms. `2 sin(kappa L/2)/kappa` is `sin(uL)/u` at `u = kappa/2`, so the
  existing `_curv_sin` small-argument branch is reused rather than a second
  series written.

  Two consequences recorded in the note rather than discovered later: **do not
  split a solenoid** (a split point sits where the vector potential is non-zero,
  so the halves would have to exchange kinetic rather than canonical momenta),
  and coordinates read inside a solenoid are canonical, which only becomes
  reachable if one is split.

  **Superimposed multipoles are also done (2026-08-01)**, matching PTC's
  `SOL5`, which carries `AN`/`BN` natively. Second-order Strang over `nst`
  steps, since the solenoid rotates the frame the multipole kicks in and the two
  do not commute — the one place the element is not exact. PTC agreement
  **4.7e-13 at `nst=8` and 3.6e-13 at `nst=32`** (41 cases now); `ks=0` with
  `k1` reproduces `QuadrupoleSpec` to 7e-18; the interior fringes cancel in
  pairs because the kick moves momenta and not positions.

  Strengths are thick `K_n` with named `k0/k1/k2…`, aligned with
  `QuadrupoleSpec`. That forced a rename — `ks` cannot mean both the solenoid
  strength and the skew tuple — and **MAD-X hit the identical clash**, its
  dictionary carrying the comment *"was: ksl, but that clashes with naming
  conventions of multipoles"*. Octopus keeps `ks` for the solenoid and spells
  the skew tuple `kskew`. Note MAD-X's solenoid takes the **integrated**
  `knl`/`ksl` and rejects `k1` outright, so benchmark bodies carry `knl = k1*L`.

  Still deferred: soft fringe (own item below), curved frame (own item below,
  closed), and MAD-X's thin solenoid, which holds `ks*L` fixed and is a
  genuinely different element.
- ~~**Aperture and particle loss.** Not an element at all: it needs a lost/alive
  state in the particle representation.~~ **DONE (2026-08-01)**, and the premise
  was wrong. No representation change was needed: `NaN` in all six coordinates
  marks a dead particle, every downstream map absorbs it for free, and the
  reductions were taught to skip it (step 2 of the aperture work). What did have
  to be built was the *reduction* masking, not the representation -- the cost of
  overloading `NaN` lands on every sum, not on the particle. See
  `docs/theory/aperture_and_particle_loss.md` and the aperture section above.
- **BPM monitors.** Also not an element in the tracking sense: a monitor records
  a beam moment rather than transforming a particle. Octopus already has an
  observation layer (`ScheduledObserver`, `MomentObserver`), so the question is
  whether a BPM is an element that happens to observe, or an observer bound to a
  position. That is an architecture decision, not a map.


Implemented and validated (2026-07-31): drift, quadrupole, sextupole, octupole,
multipole, sector bend and **combined-function bend**, with exact maps, PTC
fringe fields, and Strang/Forest-Ruth integrators. `PTCConsistencyContract`
matches MAD-X 5.03.06 to **~5e-13 across all 22 cases**, uniform over every
element type, and since 2026-08-01 that includes the pole-face and hard-edge
multipole-fringe paths rather than only the bodies. FODO/DBA/TBA cells are symplectic to ~1e-15 and bit-identical on
CPU and CUDA. Derivations:
[`docs/theory/lattice_hamiltonian_and_conventions.md`](theory/lattice_hamiltonian_and_conventions.md).

That `~5e-13` is the *reference table's* resolution, not a measured error: MAD-X
prints 10 significant digits, so a coordinate of order `1e-3` carries a rounding
quantum of `5e-13`, and every case sits just under it. Re-running the contract
against an independently generated table (different initial conditions, 6 mm and
`8e-3` amplitudes against the committed table's 4 mm and `3e-3`) gives the same
`4.97e-13`, so the agreement is at the floor the comparison can resolve rather
than tuned to the stored points. Going finer needs more digits out of MAD-X.

Construction (2026-08-01): each named kind takes the strength that defines it --
`k1` on a quadrupole, `k2` on a sextupole, `k3` on an octupole, with `k1s`,
`k2s`, `k3s` skew partners -- and `SBendSpec` takes `angle`, which sets
`h = b0 = angle / L`, plus `k1`/`k2` for combined-function bends. The positional
`kn`/`ks` tuples stay available for measured field errors and feed-down, so a
sextupole with a K3 error keeps its descriptive kind instead of having to become
a `MultipoleSpec`. Setting the same order both ways throws rather than letting
one spelling win silently.

Two findings from getting the bend to agree, both recorded in the theory note:

- **The hard-edge dipole fringe is not optional.** PTC applies it at both faces
  of an exact bend regardless of the pole-face angle; with `FINT = HGAP = 0` the
  generalized entrance angle is still `atan(x'/(1+y'^2))`. Omitting it leaves a
  bend exact on axis at any momentum but wrong at transverse amplitude -- the
  original 5.7e-7 residual. `bend_fringe = true` enables it.
- **Tabulate the potential, not the field.** Truncating the curved-frame *field*
  breaks the cross-derivative symmetry that makes the kick a gradient, and the
  map stops being symplectic at the truncation level (measured 1.5e-4).
  Differentiating one truncated *potential* keeps the kick an exact gradient at
  any `curved_order`, so truncation costs accuracy but never symplecticity.

Remaining:

1. ~~**`wedge_coeff`**~~ **RESOLVED (2026-08-01)** by reading PTC 5.03.06. The
   declaration really does carry no initializer (`Sh_def_kind.f90:124`), but the
   variable is only reachable on the fringes-on branch; with fringes off, control
   falls to `ELSEIF(MAD8_WEDGE)`, which hardcodes the same expression at
   `(w1,w2) = (1,2)`. Implemented as `_wedge_quad` with `wedge_coeff` defaulting
   to `(1,2)`; `(0,0)` reproduces the other branch.

2. ~~**Pole-face angles implemented but not benchmarked.**~~ **DONE
   (2026-08-01)**: `sbend_edge`, `cfbend_edge` and `sbend_fint` reference cases
   added, all agreeing to ~5e-13. `cfbend_edge` is the only one that exercises
   the wedge term, which needs a nonzero edge angle *and* a quadrupole
   component. RBEND is still not covered.

3. **Cavity map.** Convention #1 chosen (Section 3), map not derived. Needed to
   close a ring, not for magnets.

4. **Misalignments — implemented and validated (2026-08-01).** Six keywords
   on every element kind (`x_offset`, `y_offset`, `z_offset`, `x_pitch`,
   `y_pitch`, `tilt`) plus `misalign_convention`. One kernel, `_frame_change`,
   moves the particle between frames and drifts it onto the new face; everything
   that distinguishes entrance from exit, or straight from curved, is in the
   `(Q, o)` pairs `_misalign_frames` computes from the survey at compile time.
   A magnet with no misalignment compiles to exactly the code it had before.

   **The survey uses `h` and never `b0`**, so a bend off its design orbit
   (`h != b0`) gets the geometry its frame actually has; there is a test that
   two bends differing only in `b0` receive identical misalignment frames.

   Validated: seven PTC cases (`quad_mis_*`, `sext_mis_dx`) agree to ~5e-13, one
   degree of freedom at a time, pinning the MAD-X keyword mapping. Internally:
   symplectic to 1e-15 across nine configurations including bends with pole
   faces and fringes; exactly the identity at zero misalignment; a rolled
   upright quadrupole reproduces the equivalent skew magnet to 3.5e-18; a rigid
   displacement of a whole cell cancels to 1e-19.

   **Both open items are now resolved (2026-08-01).**
   - *Rotation composition.* `GEO_ROTB` builds
     `basis^-1 R_z(a3) R_y(a2) R_x(a1) basis`, and `MAD_MISALIGN_FIBRE` calls it
     three times with `ent1 = ent2 = ent` reset each time, so the rotations are
     **intrinsic** -- each about the already-rotated axes -- giving
     `W = R_z R_x R_y`, the reverse of Bmad's fixed-axis `R_y R_x R_z`. Same
     elementary rotations, same signs, opposite order; identical for any single
     rotation, different at second order for two. Both are implemented and
     selected by `misalign_convention` (`:bmad` default, `:madx`), which carries
     the reference point too, since the halves of a convention are not
     independently meaningful. All six degrees of freedom now agree to 4.96e-13.
   - *Bends.* They were never wrong. The comparison was: it omitted
     `bend_model = :drift_kick`, so an exact-splitting bend was being checked
     against PTC's `MODEL=1`, giving an O(1e-3) residual that scaled with the
     bend angle and looked exactly like a bad exit patch. With the right
     splitting, misaligned bends agree to 4.5e-13 for a pure translation and for
     all six at once.

   The contract now covers 32 cases, eleven of them misalignments.

   Superseded design note, still the reference for the derivation:

5. ~~**Misalignments — designed, not implemented.**~~ The comparison of
   PTC and Bmad is written up in
   [`docs/theory/misalignment_and_patch_maps.md`](theory/misalignment_and_patch_maps.md),
   including the primitive maps from both codes and the recommended design:
   Bmad's factorization (one rotation matrix applied to position and momentum,
   then a single exact drift onto the displaced plane, referenced to the element
   centre) with PTC's bookkeeping (entry and exit transforms stored and computed
   independently). Field errors remain free via `kn`/`ks`.

   The load-bearing result: **for a bend the exit transform is not the inverse of
   the entry transform**, because the body rotates the reference frame by the
   bend angle. PTC sidesteps this by computing both patches from surveyed frames;
   Bmad handles it with an explicit `bend_shift` along the arc plus a `ref_tilt`
   conjugation. Getting it wrong is invisible on a straight magnet and wrong at
   first order on every bend in a ring, so a FODO test would not catch it.

   Still open before implementing: pinning the rotation order and signs against a
   reference case (PTC applies x-pitch, y-pitch, roll; Bmad forms
   `R_y(theta) R_x(-phi) R_z(psi)`, and the two are not obviously the same
   composition at second order in the angles), and settling `ref_tilt` versus
   `tilt` for bends -- rolling the design orbit is not the same as rolling the
   magnet, and the distinction only exists for bends.

6. **`VA`/`VS` extraction** from a measured gradient profile: evaluate the first
   and second moments `J1`, `J2` numerically. Small utility.

7. **Fringe defaults are measured, not assumed** (2026-07-31). The hard-edge
   *multipole* fringe is purely nonlinear -- it leaves the linear map unchanged
   to 0 ulp -- so `fringe` defaults off and can be enabled per magnet, which is
   what a final-focus quadrupole study wants. `:soft_quad` is different: it is a
   linear map and does move the tune. The *bend* fringe now defaults ON: with
   perpendicular faces it too is purely nonlinear, but at `e1 = e2 = 0.1` it
   moves `J[4,3]` from 0 to -0.036, i.e. first-order optics. Open question: what
   the analogous default should be once misalignments exist, since a rolled
   magnet turns a "perpendicular" face into an angled one.

8. **`curved_order` default.** Currently 8, which converges to round-off by 4
   for a gradient dipole. A measured default at a realistic aperture and
   multipole content would be better than a safe guess.

9. **The hard-edge multipole fringe is now benchmarked (2026-08-01), and three
   PTC behaviours had to be reproduced to get there.** All found by reading
   `MULTIPOLE_FRINGER`; the first two were outright defects, and the theory note
   had already described both without the code following.
   - `IF(EL%NMUL<=1) RETURN`: a pure dipole gets no multipole fringe, because
     `FRINGE_dipole` already handles it exactly. We computed one.
   - `IF(J==1.AND.EL%BEND_FRINGE)` drops the normal dipole from the sum, keeping
     the skew. We included it, so `bend_model = :drift_kick` — which folds the
     dipole into `kn[1]`, and is exactly the PTC-matching configuration —
     double-counted the dipole fringe. Worth 2.1e-6, i.e. seven orders above
     tolerance.
   - `MIN(EL%NMUL, HIGHEST_FRINGE)` with `HIGHEST_FRINGE = 2` truncates at the
     quadrupole. Exposed as `highest_fringe`, but **defaulting to uncapped**,
     deliberately: enabling a sextupole's fringe and silently getting nothing
     back is the worse failure. Reference cases set 2 to match PTC; uncapped
     costs 4.2e-10 there, so the cap is load-bearing, not cosmetic.

   A trap worth remembering, since it cost a full debugging cycle: the fringe
   must be enabled per element with `permfringe=true`, **not** with
   `ptc_setswitch, fringe=true`. The global switch ends with
   `default = intstate; call update_states`, so after `ptc_create_layout` it
   silently reverts `TIME` to true and changes the longitudinal variable itself;
   before `ptc_create_layout` the layout resets it and the fringe never runs.
   The tell was a `z` error of `L·pt·(1/beta0² − 1)` on a particle with no
   transverse coordinates, which no fringe map can produce.

10. **Gaps against PTC, mostly closed (2026-08-01).**
   - ~~`KILL_ENT_FRINGE`/`KILL_EXI_FRINGE`~~ **DONE**: `kill_ent_fringe` and
     `kill_exi_fringe` suppress all three fringe mechanisms at one face, and
     deliberately leave the geometry maps (pole-face rotation, face curvature,
     wedge) running, which is what PTC does. This was more than cosmetic: MAD-X
     sets the exit flag automatically when `FINTX=0`, so a lattice with
     asymmetric fringe integrals would silently have disagreed.
   - ~~`CHARGE`~~ **RESOLVED, no action needed**: tracking the same
     combined-function bend with `beam, particle=electron` and
     `particle=proton` gives bit-identical PTC output, because the strengths are
     already normalized by the reference rigidity, so the charge is absorbed.
     Our `+1` assumption cannot be observed through anything MAD-X can express.
   - `DIR` is still unmodelled, but it is reversed-direction propagation --
     tracking a fibre backwards -- which Octopus does not support at all. That
     is a feature we do not have, not a defect in the maps we do have.
   - ~~`_dipole_edge` dead code~~ **REMOVED**.
   - `METHOD=6` (Yoshida 6th order, `MAKE_YOSHIDA` in `a_scratch_size.f90`)
     remains unimplemented; we support orders 2 and 4. Speculative until asked
     for.

11. **PTC validation stops at K3, and cannot easily go higher.** MAD-X's thick
   elements top out at the octupole term -- `sbend, l=.., angle=0, k3=..` is how
   `generate_ptc_reference.jl` builds its thick multipole cases, and adding `k4`
   is rejected outright (`+=+=+= fatal: illegal keyword: k4`). MAD-X's own
   `multipole` element is thin, so it would check the kick coefficients but not
   the thick integration. Orders K4 and up are therefore validated *by
   construction* rather than against a reference: `_lattice_kick` is generic in
   `N`, and K4-K9 measure symplectic to 2e-16..7e-15 straight, skew, with the
   hard-edge fringe, and inside a combined-function bend (see the "Named magnet
   strength keywords" testset). That is weaker than a measured comparison and
   should be read as such. A real check needs a reference code with thick
   higher-order multipoles, or driving PTC directly rather than through MAD-X's
   element keywords.

12. **`element_help` shows the folded example.** `SextupoleSpec(L=0.2, k2=12.0)`
   displays as `ElementSpec{:sextupole}(; L=0.2, kn=(0.0, 0.0, 12.0))`, because
   the spec stores only the folded `kn`. That is the honest content of the
   object and `construction_help` directly above it shows the `k2` spelling, so
   this is cosmetic -- but it does show the positional form to a user being told
   to use the named one. Fixing it means keeping the original keyword alongside
   the folded tuple, i.e. redundant state the runtime never reads, which is
   worse. Revisit only if it confuses someone.

## Earlier Completed

- Soft-Gaussian CUDA optimization (host-sync removal, device moments, fused
  wavefront launches): 0.2778 -> 0.2280 s/turn, bit-identical. See
  `docs/history/strong_strong_gaussian_optimization_history.md`.
- PIC `kbb1/kbb2` override switched to physical units, consistent across all
  solvers and frozen-beam elements.
- Strong-strong example and task notebook default to the PIC solver with the
  soft-Gaussian solver as a commented alternative.
- Lorentz crossing maps classified as Hirata quasi-symplectic (`NonSymplectic6DMap`).
