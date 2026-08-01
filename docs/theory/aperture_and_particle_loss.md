# Aperture and Particle Loss

Design note. How four established codes model an aperture, and what that implies
for doing it here without adding a per-particle status array.

Sources read, all under `Library/AcceleratorCodes/`:

| code | where |
|---|---|
| MAD-X | `madx-5.03.06/src/mad_dict.c` (`apertype`, `aperture`, `aper_tol`) |
| Bmad | `bmad-ecosystem/bmad/modules/bmad_struct.f90` (`aperture_type`, `aperture_at`) |
| Xsuite | `xtrack/xtrack/beam_elements/apertures_src/*.h`, `headers/particle_states.h` |
| Elegant | `elegant/src/limit_amplitudes.c`, aperture element names in `src/*.c` |

## 1. What the four codes do

**Shapes.** All four settle on the same small set of analytic shapes plus one
escape hatch:

| | shapes | arbitrary shape |
|---|---|---|
| MAD-X | `circle`, `ellipse`, `rectangle`, `rectellipse`, `racetrack`, `octagon`, `rectcircle` | — |
| Bmad | `rectangular`, `elliptical` | `wall3d`, `custom_aperture` |
| Xsuite | `LimitRect`, `LimitEllipse`, `LimitRectEllipse`, `LimitRacetrack` | `LimitPolygon` |
| Elegant | `MAXAMP`, `RCOL`, `ECOL`, `SCRAPER` | `APCONTOUR` |

So the proposed split — parameters for the regular cases, a predicate for the
rest — is what every one of them converged on. The regular set worth having is
rectangle, ellipse, and their intersection (`rectellipse`); racetrack and octagon
are conveniences expressible as the general case.

**Where the aperture lives** is the first real design split:

- **An attribute of every element** — MAD-X (`apertype` on each element) and Bmad
  (`aperture_type` plus `aperture_at`, which selects entrance, exit, both, or
  continuous). Nothing has to be inserted into the lattice, and the aperture
  travels with the magnet it belongs to.
- **A separate element** — Xsuite (`LimitRect` &c. are ordinary beam elements)
  and Elegant (`RCOL`, `ECOL`, …). Simpler, composable, and explicit about where
  the check happens.

**How a lost particle is recorded** is the second, and here they diverge
sharply:

- **Xsuite** sets an integer state field: `LocalParticle_set_state(part,
  XT_LOST_ON_APERTURE)` with `XT_LOST_ON_APERTURE = 0`. Distinct codes for
  distinct loss causes. It also has a bypass flag,
  `XS_FLAG_IGNORE_LOCAL_APERTURE`.
- **Bmad** sets `orbit%state` to one of several `lost_*_aperture$` values, so the
  plane and side that lost the particle survive.
- **Elegant** does not flag at all — it **compacts the array**. From
  `limit_amplitudes.c`: `swapParticles(initial[ip], initial[itop])` then
  `itop--`, moving the dead particle past the live count. Before doing so it
  writes the loss data into the dead particle's own slots: `initial[itop][4] = z`
  (the `s` at which it was lost), `[5]` the momentum, plus global `X`, `Z`,
  `theta` when requested.
- **MAD-X** proper is mostly an *analysis*: the aperture module computes `n1`
  beam-stay-clear rather than killing particles during tracking.

The point worth carrying: **three of the four preserve where and why a particle
was lost**, and Elegant goes further and repurposes the dead particle's own
coordinate slots to store it. Nobody discards that information.

## 2. NaN as the loss marker

The proposal is to mark loss by setting the coordinates to NaN, avoiding a new
array. Assessed honestly:

**What it genuinely buys.**

- No change to the particle representation, so no change to every kernel
  signature, no new allocation, no new CPU/CUDA transfer.
- It propagates for free. NaN is absorbing under every arithmetic map in this
  code, so a dead particle stays dead through drifts, kicks and frame changes
  without a single branch.
- It is idempotent and branch-free at the aperture itself: `x > xmax` is `false`
  for NaN, so an already-dead particle is not re-killed and needs no guard.
- It costs nothing on the GPU in divergence terms, unlike a masked write.

**What it costs, and this is not small.**

1. **It destroys the loss location and cause.** All three tracking codes above
   keep them; this keeps neither. "How many survived" is answerable, "where did
   they hit and in which plane" is not. Aperture studies mostly ask the second
   question.
2. **It poisons every reduction.** A sum over a beam containing one NaN is NaN,
   so beam moments, emittances and luminosity all become NaN for the whole beam.
   Every reduction must therefore skip non-finite particles. That is the hidden
   cost: the saved status array is paid for with an `isfinite` test in every
   observer and every solver moment.
3. **It collides with existing guards in this codebase.** This is concrete, not
   hypothetical. `src/tasks/strongstrong/gaussian.jl:93` requires the slice
   moments to be finite before the soft-Gaussian kick will run, and the
   `Non-finite coordinates fail fast at solver chokepoints` testset asserts
   `all(isfinite, coordinate_arrays(...))` for both beams. A NaN-poisoned
   particle inside a strong-strong run would therefore either trip the guard or
   silently NaN the beam, depending on which path it reaches first. Those guards
   exist because non-finite coordinates have historically meant a *bug*; using
   NaN as a legitimate signal overloads a value the code currently treats as an
   error.

**Consequence.** NaN is workable, but only together with an explicit rule that
non-finite means *lost*, applied consistently: every reduction masks it, and the
existing fail-fast guards must be re-expressed as "no *unexpected* NaN" rather
than "no NaN". That is a change to the meaning of a value that several
subsystems already interpret, so it should be a deliberate, documented decision
rather than a side effect of adding an element.

### The resolution: the aperture logs, like an observer

The objection in (1) is answered by making the aperture element *record* rather
than making the particle *carry*. Tracking already has a context —
`TrackingContext` in `src/track/Track.jl` holds `turn`, and the context-aware
path already reaches per-particle identity, which is how counter-RNG keys a
stochastic sample on particle index, turn, seed and stream. An aperture element
can therefore log `(particle, turn)` into a buffer it owns at the moment it kills
a particle, exactly as a `ScheduledObserver` logs a moment.

That recovers everything NaN erased **for losses at an aperture**:

| what | where it comes from |
|---|---|
| which particle | the index the context-aware kernel already carries |
| which turn | `TrackingContext.turn` |
| which aperture, so which `s` | the element doing the logging *is* the location |
| why | the element's own shape, and the fact that it was this element |

and it costs no change to the particle representation, because the record lives
in the element, not in the beam. NaN then does only the one job it is good at:
marking the particle dead so every subsequent map leaves it alone.

### What this still cannot do, and why

Attributing a loss to an **arbitrary element** — a particle that leaves the
aperture inside an ordinary quadrupole, with no aperture element there — is out
of reach in this design, and not by oversight. Nothing per-particle records
provenance, so there is no way to ask "which element lost this one" unless every
element checks and logs, which is the same as saying every element is an
aperture. Answering that question properly needs a different phase-space
representation: one carrying, per particle, at least a loss flag and an element
or `s` identifier.

The practical consequence is worth stating plainly, because it decides how
lattices are built rather than how the element is coded: **loss position is
resolved only to where you place aperture elements.** That is exactly the
bargain Xsuite and Elegant make — `LimitRect` and `RCOL` are things you insert —
and it is why MAD-X and Bmad, which hang an aperture on *every* element, get
finer resolution at the cost of every element carrying aperture state.

Deferring the representation change is the right call now: it is a large,
cross-cutting change to every kernel signature, and inserted aperture elements
answer the question most studies actually ask.

## 3. Can a function live in `ElementSpec.params`?

**Yes.** `params` is a `Dict{Symbol,Any}`; storing and calling a closure works
today, verified directly:

```julia
s = MarkerSpec(alive = (x,px,y,py,z,pz) -> x*x + y*y < 1e-4)
getparam(s, :alive, nothing)(1e-3, 0, 0, 0, 0, 0)   # true
```

Three caveats decide whether it is a good idea:

1. **The runtime must take it as a type parameter, not a field typed `Any`.**
   `Aperture{F}` with the predicate's type in `F` specializes and inlines;
   a field of type `Any` is type-unstable and will not compile for the GPU. This
   is the same pattern `Marker{M}` already uses.
2. **The predicate must be a pure scalar function.** A closure capturing an
   array cannot be used on the device. Analytic shapes are fine; a polygon
   lookup table is not, without more work.
3. **It is opaque to the metadata machinery.** A function has no meaningful
   perturbation, so `ElementParameterEffectivenessContract` cannot probe it, and
   it will not serialize into `registry_snapshot.md`. Both are acceptable if
   declared, but they need declaring rather than discovering later.

## 4. Recommendation

1. **A separate `aperture` element**, following Xsuite and Elegant rather than
   MAD-X and Bmad. It composes with what exists, needs no change to any other
   element, and makes the check location explicit. If aperture-as-attribute is
   wanted later, it can wrap through `compile_runtime` exactly as misalignment
   now does — that path is already built and is the natural second step.
2. **Shapes as parameters:** `:rectangle`, `:ellipse`, `:rectellipse`, with
   `x_limit`/`y_limit` and asymmetric variants only if a case needs them.
   Racetrack and octagon can wait; both are expressible through the predicate.
3. **An `alive` predicate for everything else**, carried as a type parameter.
4. **NaN as the loss marker, with the rule written down**, and the two
   consequences handled in the same change rather than deferred: reductions mask
   non-finite particles, and the existing fail-fast guards are restated so a
   deliberately-killed particle is not read as a solver bug.
5. **The aperture logs `(particle, turn)` through the tracking context**, like
   an observer, so NaN marks the particle dead and the element records the
   event. Per-element loss attribution is explicitly out of scope and needs a
   different phase-space representation; loss position is resolved to where
   aperture elements are placed.

## 5. Open questions

- **What shape should the loss log take?** A per-element growable buffer is the
  simplest, but it has to work on the GPU, where appending from a kernel needs
  either an atomic counter or a preallocated per-particle slot written once.
  The second is a fixed cost proportional to the beam, not the losses, which may
  be the better trade at low loss fractions.
- **Does a lost particle stay in the beam?** NaN implies yes, at full cost, for
  the rest of the run. Elegant compacts precisely to avoid tracking dead weight.
  At large loss fractions this is the difference between a cheap and an
  expensive study.
- **Where is the aperture checked?** Bmad's `aperture_at` exists because
  entrance-only is wrong for a long magnet. A separate element checks at a point;
  a wrapped one could check both faces.
- **Interaction with misalignment.** An aperture belongs to the *magnet body*,
  so a displaced magnet carries a displaced aperture. Checking in design
  coordinates is wrong for a misaligned element by exactly the offset. If the
  aperture is a separate element this is the user's problem; if it wraps, it
  should sit inside the misalignment frames rather than outside.
- **Strong-strong.** A NaN particle interacts with nothing, but it still occupies
  a slice and a grid cell. Slicing and deposition need to agree that it does not
  contribute, which is the reduction-masking point again, in a place where it is
  easy to miss.
