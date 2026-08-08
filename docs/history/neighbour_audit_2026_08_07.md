# Targeted Neighbour Audit — 2026-08-07

Scope: the blast radius of the ten fixes landed on 2026-08-07 (U1-1, U1-5,
U3-4/U3-7, U6-7, U18-2, U5-8, U10-3, U15-7, U14-7, U7-10; commits `a49138e`
through `6212c05`). Method per the comprehensive-audit protocol's "Measured
Lessons": for each fix, re-walk its call sites and sibling surfaces, and
re-run the property the fix was about on the neighbours it did not change.
Three read agents swept (RNG paths + trace sinks; truncating writers + gpic
counting; worker-count folds + cross-backend reductions + Val gates); every
load-bearing claim below was re-verified against source or by direct
measurement before being recorded. This is the audit the protocol's own
lesson demands after a fix campaign — "a fix's neighbours are where the next
defect is" — and it found real ones.

## Fixed in this audit's closing commit

- **N1 — gpic direct-`collide!` CUDA entry missed the U1-4 timing-context
  installation** (`gaussian_pic_cuda.jl`). The plain-PIC five-argument
  `collide!` wraps its route in
  `ScopedValues.with(_ACTIVE_PIC_TIMING_CONTEXT => ...)` precisely because
  the CUDA per-pair luminosity sink reads the scoped value, not the `ctx`
  argument; the gpic twin did not, so every per-pair record on that entry —
  records that exist since U1-1 — was stamped `turn = -1` while the CPU twin
  stamps `ctx.turn`, collapsing any `(turn, i, j)`-keyed consumer onto one
  bucket. Task execution was unaffected (`_strong_strong_collide!` installs
  the scope); the gap was the documented direct entry point. This is a defect
  in the U1-1 fix's own neighbourhood, found exactly where the lesson said to
  look.
- **N2 — gpic CUDA collide had no dropped-counter reset/readback**
  (`gaussian_pic_cuda.jl`). Behaviourally inert today — gpic forces
  slice_pair + `:extrema` on both backends, so no route can increment — but
  the CPU twin carries the defensive reset/report (U10-2) and the plain-PIC
  CUDA collides do too (U1-5); a future gpic route reaching a counting
  deposit would have warned on CPU and stayed silent on CUDA. Symmetric now.

## Recorded as open rows in docs/todo.md (verified, priced, not rushed)

*(Closure status, 2026-08-08: N4, N5, N6, N7 and N8 were closed the next
day, plus the observer half of N3 — dispositions in their todo rows. Still
open from this audit: the task-level writer-registry design half of N3, and
the pipeline-precision decision recorded inside the closed N7 row.)*

- **N3 — three more truncating observer writers outside the U7-10 registry**:
  `LuminosityObserver` (`initialized ? "a" : "w"` on first observe),
  `BPMObserver` (same latch, plus `_bpm_discard_window!` rewriting the whole
  file from this object's memory), and `CoordinateSnapshotObserver` under
  `append=false` (plus its byte-offset replay truncation trusting this
  object's `written` map). Same U7-10 interleave shape, same registry fix
  shape. Also recorded: the task-level `.lum` path and the loss-log
  (`write_loss_record`, whole-file rewrite that is idempotent per task but
  last-writer-wins across tasks) are outside any registry — a cross-subsystem
  collision (observer vs task on one path) has no signal.
- **N4 — the weak-strong strong-beam luminosity folds are worker-count
  shaped** (`_track_thin_strong_beam!`, `_track_gaussian_strong_beam!`:
  `zeros(T, policy.threads)` with STRIDED membership, then `sum`): the exact
  class U5-1/U18-2 removed from the strong-strong stack, still live on the
  weak-strong path. `last_luminosity` is not thread-count invariant, no pin
  covers it (the thread-invariance testset sweeps strong-strong `collide!`
  only), and the CUDA twin folds in particle order — a third shape.
- **N5 — `_masked_rms` has per-backend reduction shapes** (CPU strict serial
  vs CUDA tree; and the CPU's own masked/unmasked paths differ), feeding the
  spectral Dirichlet box half-width that every spectral kick solves on. The
  U6-7 class; the earlier audit classified it "equivalent" without a row.
  Fix shape established by U6-7 (lane fold).
- **N6 — `Val{COMPUTE_LUMINOSITY}` gates the soft-Gaussian kick bodies**
  (CPU `_apply_slice_kick_one!` and the CUDA sequential
  `_cuda_slice_kick_kernel!`), with both specializations reachable for the
  same beam by flipping `gaussian_when_luminosity` — the U10-3
  second-specialization contraction mechanism, latent because no pin asserts
  coordinates bit-equal across the flip. The CUDA fused route already gates
  at runtime (`seg_complum`), so three routes carry two gating disciplines.
  Also noted: `_slice_transverse_moments`' 14-vs-10 `Val{COUPLED}` loop is
  the surviving sibling of the shape U10-3 converted away in gpic, mitigated
  by `COUPLED` being a per-solver type parameter.
- **N7 — Float32 PIC luminosity return types differ across backends** (CPU
  promotes to Float64 through `kbb`, CUDA returns beam-typed Float32) — the
  U3-7 asymmetry in the solver the Gaussian fix did not touch. Measured
  alongside: Float32 PIC cross-backend kick parity is 1.55e-6 relative
  (3.2e-15 at Float64) — plausibly the honest single-precision PIC envelope,
  since PIC fields are beam-typed on BOTH backends (a symmetric convention,
  unlike the Gaussian case) — but nothing pins it.
- **N8 (minor) — dead global-RNG code in `Beam.jl`**: `_default_rng`
  (both backends) has zero call sites, and `_alloc_randn`'s
  `rng === nothing` fallbacks to `Random.default_rng()`/`CUDA.default_rng()`
  are unreachable from the one guarded caller — live code a future caller
  would silently pick up, outside the counter-RNG guarantee.

## Swept and clean

Non-counter RNG draws (every live tracking path draws through the counter
RNG; the bare `Random.randn()` methods in radiation.jl are the documented
no-context generic path, unreached by task execution). Trace-sink population
symmetry (`_ACTIVE_PIC_PHASE_TIMING_SINK` is CUDA-only by declared metadata
with a validation script asserting CPU emptiness; `_ACTIVE_EXECUTION_AUDIT`
has no cross-backend comparison; the U1-1 sink's every-route claim holds for
gpic through the shared helpers). gpic dropped-charge behavioural parity
(structurally zero on both backends, same reason). Worker-count partitions
elsewhere (integer histograms, contiguous index building, slice/pair-indexed
or fixed-chunk float folds). Slice-geometry reductions beyond the recorded
U6-7 transverse-moment residual. Val gates that carry lengths, per-element
type parameters, or data-determined physics branches. U5-8's turn loop
(remaining per-turn calls are turn-dependent or O(1)). U15-7's neighbour
tables (the `:sbend`/`:angle` special case has no second angle-folding kind;
the hardcoded solver tuple in `validate_configuration_metadata` is already
on the ledger).
