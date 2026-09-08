# The luminosity route becomes an option — 2026-09-08

A `TrackingTask` that writes a luminosity channel could not fuse its line. With
an artifact attached and a strong beam present, `task_diagnostics` is set and
`requires_isolated_tracking` lifts the beam-beam element out of the fused
traversal into its own plan segment, so one pass over the beam becomes three:
`FusedSegment -> IsolatedSegment -> FusedSegment`. That is the only way the
per-element luminosity was ever obtained, because the fused kernel computes the
value and throws it away.

`luminosity_tracking = :isolated | :fused` now selects the route, default
`:isolated`.

## The number does not move, and that is asserted exactly

The fused route reuses the isolated route's reduction **verbatim**: the fixed
`_REDUCTION_CHUNKS` partition in GLOBAL terms, one scalar partial per chunk,
`_mp_chunk_fold` in chunk order. Per-chunk accumulation runs over the same
indices in the same order, so the rounding is identical.

| route | plan | luminosity |
|---|---|---|
| `:isolated` | 3 segments | 1.77722075185275293e+12 |
| `:fused` | 1 segment (`LuminousFusedSegment`) | the same, by `===` |

Coordinates are bit-identical too, and the suite asserts both with `==`/`===`
rather than a tolerance. Anything else is a bug, not a judgement call. The
thread-count invariance the fixed partition exists for is pinned at 1, 2 and 4
workers.

The masking is the subtle half. `_add_luminosity` judges liveness from the
coordinates it is handed, and the rule is to judge the kick's OUTPUT. In a fused
pass the caller holds only end-of-line coordinates, so a caller that applied the
mask would drop a particle that was alive at the beam and lost at a downstream
aperture -- a plausible, slightly wrong luminosity with every coordinate digest
still bit-identical. `track_luminous` therefore masks INSIDE the kernel, at each
element's own position, which is both correct and more natural: the generator
already holds the coordinate symbols there.

## The performance case, measured and much smaller than first claimed

Medians of three interleaved replicates, production fixed point, 1.024M
macroparticles:

| threads | `:fused` | `:isolated` | |
|---|---|---|---|
| 16 | 0.1553 | 0.1752 | fused 1.13x |
| 64 | 0.0697 | 0.0752 | fused 1.08x |

**Two earlier figures of mine are retracted.** A 3.4-4.5x penalty measured on a
synthetic three-element line (drift, strong beam, drift) did not survive contact
with the production line, where the beam-beam element is a large share of the
per-turn work and the extra traversal boundaries cost little. And a single-run
1.39x at 64 threads, plus a single-run "split wins at 16 threads", were both
noise: the 16-thread comparison flipped sign between replicate 1 and replicate 2.
One run per arm is what produced the retracted 2026-09-06 benchmark claim, and it
produced two more wrong readings here before replicates settled it.

The honest number is a consistent ~10%.

## CUDA keeps the split, permanently

Measured on an RTX 4500 Ada, same line and particle count, artifact on versus
off: `split/fused = 0.959x` -- the split is marginally FASTER on the device.
That is the expected shape: the CUDA isolated path is asynchronous kernel
launches plus an on-device reduction, not extra passes through a host chunk
grid, so breaking the traversal is nearly free there.

So `:fused` is CPU-only by design rather than by omission, the metadata says so
(`supported_backends=(CPUThreadsBackend,)`), and asking for it on a device
THROWS. It does not warn and degrade: the numbers would still be right, so
nothing would ever surface, and a timing comparison would silently measure the
other route. The refusal sits at the consumer boundary in `_execute_tracking_task!`,
not in the constructor, because `policy=nothing` defers the backend to
`execute!` -- a construction-time check could not know it and would read as
covered while never firing.

The refusal fires only when a route is actually taken. With no artifact or no
strong beam neither route runs, so there is no request to ignore, and no receipt
is emitted.

## What the design review caught that I had wrong

- **The plan key.** The route changes plan SHAPE, so it has to key the plan
  cache; without it a task would be handed the other route's cached plan.
- **A second caller.** `_execute_strong_strong_segment!` builds
  `(block_index, _active_plan_key(entries, ctx, false))` and destructures
  `plan_key[2]`. Widening the key without it is a `MethodError` in the
  strong-strong path -- a weak-strong change breaking strong-strong.
- **The keyword.** `batch_mode` looks like the option to widen and is a false
  friend: it means slice-pair scheduling inside a strong-strong collide, and its
  declared dependencies are meaningless on a tracking plan. `tracking_method` is
  the tree's real "how is this computed" keyword but is per-element and changes
  the physics, which this option must never do. The live `luminosity_*` family
  (`luminosity_grid`, `luminosity_deposit_method`, `luminosity_schedule`) already
  means "the luminosity path may differ from the force path", and
  `luminosity_tracking` is that pattern.
- **The receipt must name the route that RAN**, not the request. A receipt
  echoing the request passes while the run takes the other path -- the same
  lesson as the `fast_path` field added with the turn-timing work.

## Deliberately not in this landing

**The wrapper guard is untouched.** A strong beam behind a `CompositeLine`,
`MisalignedElement` or `RefTilted` is refused when an artifact is attached
(2026-09-07), and the fused route would in principle make those cases work. It
is not relaxed here, because `strong_beams`, the artifact's channel labels and
the per-turn push loop are all as wrapper-blind as the isolation scan was:
lifting the guard before those are wrapper-aware would reproduce the silent
empty-channel bug the guard exists to prevent. Wrapper support is a follow-up
row, and the order is fixed -- discovery first, guard second.

**No `:auto`.** A crossover threshold interpolated from two thread counts on one
fixed point is a guess, and a default that depends on the machine is what this
repository has spent the week retracting.
