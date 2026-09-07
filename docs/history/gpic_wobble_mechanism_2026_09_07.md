# Member 2 solved: it was the nondeterminism documented in the same file — 2026-09-07

The CUDA near-identity wobble ledger's member 2 — "the gpic A/B coin" — is
closed. The mechanism is the CUDA PIC route's float-atomic deposition
nondeterminism, which has been documented, measured and judged not-a-defect at
the top of `src/tasks/strongstrong/pic_cuda.jl` since the 2026-08-05_b audit
(U3-6). The investigation was looking for a new phenomenon; there was none.

This record exists because the row spent three accounts and several probe
campaigns on a question that a comment in the file under investigation already
answered, and because two of my own intermediate conclusions here were wrong and
had to be withdrawn by measurement. Both are recorded rather than tidied away.

## What the row claimed, and what is true

| the row | measured 2026-09-07 |
|---|---|
| "exactly TWO bit-identical profiles A/B" | two is a small-sample artifact; the `sequential` route showed **three** |
| "each collide call draws one" — of a gpic-vs-pic mismatch | it is not a mismatch between routes; a single route disagrees **with itself** call to call |
| the coin belongs to the gpic fallback | which route shows it **flips** between configurations |
| `norm(A-B) = 6.3e-16` | 7.36e-16 here — and `pic_cuda.jl` recorded 6.9e-16 to 8.3e-16 for this phenomenon on 2026-08-05 |
| "NEXT INSTRUMENT must come from the suite, not a standalone probe" | reproduced standalone, in about a minute, once the right question was asked |

## The measurement that dissolved it

Every previous probe compared PIC against GPIC. None had ever compared a route
against **itself**. One process, the failing geometry (n = 64, the zero-width
route), the same solver called repeatedly:

```
PIC  self-consistency over 12 calls: 2 distinct results
GPIC self-consistency over 12 calls: 2 distinct results
union of all PIC and GPIC results:  2
```

A single route is two-valued on its own. So the test's "gpic does not match pic"
was never a statement about the fallback: it compares one draw against another
draw and reports the difference as a route defect.

Quantified against what the test actually measures:

| quantity | value |
|---|---|
| PIC's own call-to-call spread | 0.000e+00 (that process) |
| GPIC's own call-to-call spread | 7.358e-16 |
| pic-vs-gpic spread — what the pin asserts on | **7.358e-16** |

The number the pin is testing IS a route's own spread, to the digit.

## Why it hides from standalone probes, and why the suite sees it

It is contention-dependent. Same configuration, varying only the particle count:

| n | distinct results / 10 |
|---|---|
| 2, 4, 8, 16, 64 | 1 |
| 256 | **10** |

At n = 256 the route is nondeterministic on essentially every call — the
documented behaviour at full strength. At n = 64 the deposit's atomic collisions
are rare enough that the ordering usually repeats, so a quiet process reads
"frozen" (the ledger's 20/20, and the later 160/160). Prior CUDA work in the
process changes occupancy and scheduling enough to expose it, which is exactly
the "only in-suite / only with suite history" signature the row recorded for a
year without a cause.

## Which route shows it is not stable — the fact that kills the A/B framing

Five configurations, each in **its own process** (see the correction below for
why that matters), 8 calls per route after identical warm-up:

| configuration | PIC | GPIC |
|---|---|---|
| async + `green_cache=:slice_pair` | 1 profile, 0.00e+00 | **2 profiles, 7.36e-16** |
| async, `green_cache=:none` | 1, 0.00e+00 | 1, 0.00e+00 |
| async, plain (non-indexed) wavefront | **2, 7.36e-16** | 1, 0.00e+00 |
| sequential | **3, 7.36e-16** | 1, 0.00e+00 |

The spread is the same 7.36e-16 wherever it appears; the route it appears in
changes. A phenomenon belonging to the gpic fallback cannot show up in PIC while
gpic is clean, twice.

## Two accounts of my own, withdrawn by measurement

**A cached-grid account.** `_cuda_pic_slice_pair_cached_prep!` returns
`entry.source_grid` on a hit and a freshly expanded grid on a miss, and
`_cuda_pic_slice_pair_entry_usable` deliberately accepts a cached grid larger
than requested. Two grids would give two profiles. It is wrong: instrumenting
the cache showed the grid **bit-identical on every call**
(`(-0.0015625, -0.0005625, 0.003125, 0.003125)`), always a fresh build, never a
hit. Written down before it was tested, and refuted by the instrument.

**A `slice_pair_green_growth` lever.** A table showed growth = 0.25 giving two
profiles and growth = 0.0 giving one, twice over. It does not survive: the four
configurations ran **sequentially in one process**, so the knob and the position
in the process were varied together, and `n = 64, growth = 0.25` later gave one
profile in a fresh process. The confound is the same one this repository already
records for A/B measurement, committed again here in a new form. Every
configuration after that was run in its own process, which is what produced the
table above.

Both are kept because the row's earlier withdrawn accounts are kept, and for the
same reason: the wrong turns are the part that is expensive to rediscover.

## What was fixed

Nothing in the solver. Making the route deterministic means ordered reductions
in place of atomic deposition, which `pic_cuda.jl` prices and declines
("costs more than the property is worth here"), and that is an owner-level
trade-off, not something to reverse from inside a wobble investigation. The
physics is unaffected: the magnitudes are at rounding level.

What was wrong is the pin. `CUDA GaussianPIC singular-reference fallback matches
PIC` asserted near-equality between two draws of a nondeterministic route, and
its `atol = 2e-15` was derived as "3x the measured wobble norm" of a phenomenon
it had misidentified — a constant tuned until the gate stopped failing, resting
on an unexplained coin.

The tolerance is now **derived in-process**: a second PIC draw at identical
inputs measures the route's own call-to-call spread at that geometry, and the
comparison admits four times it, with the old 2e-15 kept as a floor for the
common case where two draws coincide. The check keeps all of its discriminating
power for what it is for — a wrong fallback diverges wholesale at O(kick) ~ 1e-15
and is caught by `rtol = 2e-12` regardless of `atol` — and loses only its ability
to fail because the hardware summed the same atomic adds in a different order.

## The lesson worth keeping

The answer was a comment at the top of the file the investigation was reading,
written five weeks earlier by an audit, stating the phenomenon, its cause, its
measured magnitude (6.9e-16 to 8.3e-16, against the 6.3e-16 the row called
unexplained) and the decision not to fix it. Three accounts were built and
withdrawn without anyone comparing a route against itself — the one-line
experiment that dissolves the question.

When a near-identity pin wobbles, the first measurement is not "how do these two
things differ" but **"is either of them reproducible on its own?"**
