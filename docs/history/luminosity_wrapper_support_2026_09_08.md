# The fused route carries luminosity through wrappers — 2026-09-08

A strong beam behind a `CompositeLine`, `MisalignedElement` or `RefTilted` could
not report luminosity at all. The top-level scan does not see through a wrapper,
so no `IsolatedSegment` was built, `last_luminosity` was never written, and the
artifact opened with no channel — silently, until the 2026-09-07 guard made it
refuse. This closes it: on `luminosity_tracking = :fused` those cases now work,
because each wrapper forwards the accumulator it used to drop.

See [`luminosity_tracking_route_2026_09_08.md`](luminosity_tracking_route_2026_09_08.md)
for the route option itself.

## The order was the whole risk, and the ledger was right about it

`strong_beams`, the artifact's channel labels and the per-turn push loop all
derive from ONE scan, and that scan was as wrapper-blind as the isolation
predicate. Relaxing the guard first would have handed a wrapped beam a channel
that is never written — the same silent empty-channel bug the guard exists to
prevent, reintroduced by the fix for it.

So discovery went first. `_strong_beams_of` walks depth-first in line order
through all three wrappers, and the three consumers follow from it at once. The
order is not cosmetic: `fusedTrackLuminous` concatenates its per-element
accumulators depth-first in the same order, so the walk and the expansion must
agree or beam 1's number lands in beam 2's dataset with nothing to notice.

## The wrappers

All three have the same shape, so each luminous form mirrors the method beside
it:

| wrapper | ordinary form | luminous form |
|---|---|---|
| `CompositeLine` | `fusedTrack(ctx, ops, …)` | `fusedTrackLuminous(mask, ctx, ops, …)` |
| `MisalignedElement` | frame change → `inner` → frame change | the same, forwarding `inner`'s accumulators |
| `RefTilted` | `s`-rotate → `inner` → `s`-rotate | the same |

For a wrapped beam, liveness is judged in the INNER frame, immediately after the
kick — the direct analogue of the unwrapped case's "judge the kick's output".
That defines the semantics rather than preserving them: a wrapped strong beam
had no luminosity to preserve.

## The guard is scoped, not lifted

`:isolated` still refuses wrapped beams. It genuinely cannot serve them — a
wrapper cannot be taken apart to isolate what is inside without destroying the
rigid-body semantics a sub-line exists for — so a channel on that route would
never be written. The refusal now names the way out.

## Measured

| line | `:isolated` | `:fused` |
|---|---|---|
| flat | 7.108441689640181e+11 | the same, by `===` |
| nested in `BeamLine` | refused | **the same as flat** |
| misaligned (`x_offset`) | refused | 5.991222566028994e+11 |
| misaligned inside a line | refused | the same as misaligned, by `===` |
| ref-tilted | refused | reports |

A wrapper that does not move the beam does not move the number; one that does,
does. That pair is what separates "it produces a number" from "it produces the
right number".

`RefTilted` is pinned for the first time. It had been declared in
`_hidden_strong_beam_count` since that helper was written and never fixtured, and
the same walk now decides which beams get artifact channels — so a miss would be
a missing channel, not merely a missed guard.

## A fixture that looked exactly like a wiring bug

The attribution test — two strong beams, one wrapped, each keeping its own
number — first read `1.8192e11` and `0.0`. An accumulator that fills only for the
first luminosity-producing element would look identical, so the zero had to be
explained rather than asserted away.

Removing the drift between the two beams settled it:

| arrangement | beam 1 | beam 2 |
|---|---|---|
| plain, drift, offset | 1.8192e11 | 0.0 |
| plain, offset back to back | 1.8192e11 | 1.8192e11 |

Both accumulators fill. The zero is the 0.5 m drift after the first kick carrying
the bunch out of the second beam's overlap. The pin therefore uses the
back-to-back arrangement, and says so with both numbers, because the obvious
tidy-up — adding a drift between them — silently destroys the test's power.

That is the third fixture-not-code failure in this campaign, after
`last_luminosity` holding the FINAL turn's value and a fresh rep recompiling the
line into a different element object. All three shared a shape: an assertion that
looked like it tested the implementation but encoded an assumption about the
fixture, and whose failure was plausible physics rather than nonsense — which is
exactly when to measure instead of loosening the assertion until it passes.
