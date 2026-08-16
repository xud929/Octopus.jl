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

### Logging exactly once: detect the transition, not the condition

A particle killed at turn `n` stays NaN, and will meet every aperture element on
every later turn. It must be logged once, not every time.

The naive check re-logs forever, and for a subtle reason: every comparison with
NaN is false, so `x^2 + y^2 < r^2` is false for a dead particle and it reads as
"outside the aperture" again. The same property supplies the fix, because a dead
particle also fails `isfinite`. Testing both identifies the *edge* rather than
the state:

```julia
was_alive  = isfinite(x) & isfinite(y)      # a dead particle is already NaN
inside     = predicate(x, y, ...)
newly_lost = was_alive & !inside            # true exactly once, ever
```

This is branch-free, needs no memory and no per-particle flag, and is exactly
idempotent: once a particle is NaN, `was_alive` is false at this aperture and at
every other one, on this turn and every later turn. It is the same `isfinite`
test the reductions need anyway, so it costs nothing new.

**Test all six coordinates, not just `x` and `y`.** Tracking itself can produce a
non-finite particle -- an exact drift takes `sqrt((1+pz)^2 - px^2 - py^2)`, which
goes imaginary once the transverse momentum exceeds the total, and overflow can
give `Inf` -- and such a particle may arrive with, say, `px` non-finite while `x`
is still finite. A two-coordinate test would call it alive, log it as an aperture
loss, and attribute a numerical blowup to whatever aperture happened to be
downstream. All six is the honest test and costs four more comparisons.

That gives the right behaviour for a particle that died inside a magnet: it
reaches the aperture already non-finite, `was_alive` is false, and **the aperture
does not log it**. It should not -- it did not lose that particle. The aperture
logs only what it stopped.

Two consequences of that follow, and both are worth building in rather than
discovering later.

**Unattributed deaths must stay visible.** A particle lost to a numerical blowup
is logged by nobody, so the aperture logs under-report the dead:

    dead at end of run  -  logged at apertures  =  lost elsewhere, unattributed

That difference is not noise, it is a diagnostic. Non-finite coordinates have so
far meant a *bug* in this codebase, and the whole point of overloading NaN is
that they now sometimes mean *lost*; a run where the two counts disagree is
telling you the old meaning still applies somewhere. A task-level summary should
report both numbers so the gap is visible instead of silently reducing the
survivor count.

**Do not canonicalize `Inf` to `NaN`.** It is tempting to have the aperture
normalize any non-finite particle to all-NaN so "dead" has one representation and
every downstream mask is a single test. That would erase information: `Inf`
signals an overflow, `NaN` an invalid operation such as the imaginary square root
above, and a deliberate kill is also `NaN`. Keeping them distinct is what lets
someone tell a diverging trajectory from a particle that hit a collimator.
Reductions should therefore mask on `!isfinite`, not on `isnan`.

### What to log: the coordinates, not a verdict

Recording the six coordinates *before* they are overwritten lets the reader infer
why a particle was lost, rather than trusting the element to have classified it.
The element knows the shape; only the coordinates say how far outside, in which
plane, and with what angle — and those distinguish a genuine aperture loss from
a particle that was already diverging.

Because a particle is lost **at most once**, one record per particle suffices for
an entire run, shared across every aperture in the lattice:

    turn, element id, x, px, y, py, z, pz      per particle, written once

That storage has the property GPU logging usually lacks: **no atomics and no
counter**. Each particle writes its own slot, `newly_lost` guarantees exactly one
write, and there is no contention because no two particles share a slot. The cost
is proportional to the beam rather than the losses -- roughly `64 N` bytes -- which
is the trade already identified as preferable at low loss fractions, and it also
recovers *which element* for aperture losses, since the element stamps its own
id.

### Reporting survival: wanted, but not worth a reduction

A loss log that has to be post-processed to answer "how many are left after turn
`n`" is a log nobody uses. Survival versus turn is the output of a
dynamic-aperture or lifetime study, so the count belongs in the record.

The cost has to be looked at, though, because "reduce the beam whenever the log
is written" is more expensive than it sounds. A beam-wide `isfinite` count is
`O(N)`; doing it per aperture per turn costs

    O(N) x n_apertures x n_turns

which for `1e5` particles, 100 apertures and `1e5` turns is `1e12` operations --
enough to dominate the run. A per-particle kernel also cannot perform a beam-wide
reduction, so it would have to be a separate pass, per aperture, per turn.

The number can be had for nothing instead. Each aperture already knows exactly
when it kills a particle, so a **running counter** incremented on the
`newly_lost` transition gives the same information at `O(1)` per loss rather than
`O(N)` per turn:

    alive = N - cumulative_killed

Losses are rare relative to particles, so even an atomic increment is negligible
here -- the opposite of the per-particle record, where an atomic would fire for
every particle and a private slot was cheaper. The two mechanisms differ because
their frequencies differ.

One honest limit: a counter only knows about aperture losses. Particles that go
non-finite inside a magnet are counted by no aperture, so `N - cumulative_killed`
overstates the survivors by exactly the unattributed deaths of the previous
section. The recommendation is therefore both, at their natural rates:

| quantity | how | when |
|---|---|---|
| killed at apertures | running counter, `O(1)` per loss | every turn, free |
| true alive count | beam-wide `!isfinite` reduction, `O(N)` | on the observer schedule |

Reporting both is what makes the gap between them visible, which is the
diagnostic the previous section argues for. Running the full reduction on the
existing observer cadence rather than on every aperture crossing keeps it off the
per-turn critical path while still giving a curve dense enough to plot.

### Should lost particles be compacted?

Xsuite moves lost particles to the tail so kernels can run over a shorter active
range. Whether that pays here is a different question from whether it pays there,
and for this codebase there is a specific obstacle.

Against compaction:

- **It breaks the counter-RNG determinism.** Stochastic samples here are keyed by
  particle *index* (`Contracts.jl:60`: "samples are keyed by particle index,
  turn, seed, and `rng_id`"), which is what makes CPU and CUDA bit-identical and
  results reproducible. Moving a particle to a different slot changes its key and
  therefore its noise history, unless the particle carries its original id --
  which is precisely the phase-space representation change being deferred.
- **Dead particles do not diverge.** They execute the same branch-free arithmetic
  as everyone else, so the waste is idle FLOPs, not warp divergence. At a few
  percent loss this is far below noise.
- The reorganize is itself an `O(N)` partition with data movement, so it only
  pays once the saved work exceeds it.

For compaction, at high loss fractions: a study that loses most of the beam
spends most of its time tracking corpses, and there the argument reverses.

**Recommendation: do not compact.** Keep lost particles in place, which the
determinism story requires anyway, and revisit only if a measurement shows loss
fraction dominating runtime. It is a performance optimization with a correctness
coupling, and it should be driven by a measurement rather than by symmetry with
another code.

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

   **Implemented 2026-08-01** as `allow_lost_particles`, off by default. The
   rule is not applied unconditionally, because the aperture that makes a NaN
   legitimate does not exist yet: switching the meaning globally now would
   surrender bug detection with nothing able to produce a deliberate loss. Off,
   non-finite still means bug everywhere; on, it means lost. See the archived
   non-finite program (`../history/todo_ledger_archive.md`) for what was masked.

   With the flag **on** the masking is complete over all six coordinates. With it
   **off**, fail-fast detection is not: a chokepoint only sees coordinates some
   reduction reads, and nothing reads `pz`. That gap is pre-existing, is a standing
   decision in `docs/experiences.md` (deliberately not done: production runs
   have the flag on; the full record is in `../history/todo_ledger_archive.md`).
5. **The aperture logs `(particle, turn)` through the tracking context**, like
   an observer, so NaN marks the particle dead and the element records the
   event. Per-element loss attribution is explicitly out of scope and needs a
   different phase-space representation; loss position is resolved to where
   aperture elements are placed.

## 5. Open questions

- **Where does the shared loss record live?** It is per beam, not per element,
  since a particle is lost once. That makes it a property of the tracking task
  rather than of any aperture, so the element needs a handle to it -- the same
  question a `ScheduledObserver` already answers, and the place to copy from.
- **Where should the dead-versus-logged reconciliation be reported?** It belongs
  with whatever summarizes a run, not with the aperture, since no single aperture
  can know the total. The natural home is the task's own diagnostics.
- **Where is the aperture checked?** Bmad's `aperture_at` exists because
  entrance-only is wrong for a long magnet. A separate element checks at a point;
  a wrapped one could check both faces.
- **Interaction with misalignment.** An aperture belongs to the *magnet body*,
  so a displaced magnet carries a displaced aperture. Checking in design
  coordinates is wrong for a misaligned element by exactly the offset. If the
  aperture is a separate element this is the user's problem; if it wraps, it
  should sit inside the misalignment frames rather than outside.
- ~~**Strong-strong.** A NaN particle interacts with nothing, but it still
  occupies a slice and a grid cell.~~ **ANSWERED (2026-08-01) by the step-2
  masking.** A dead particle now joins no slice under any of the five slicing
  methods and therefore reaches no grid cell, verified bit-exact against a beam
  that omits it. It was indeed easy to miss: the boundary reductions were
  unmasked, and each slicing method dropped or misfiled the dead differently.

The remaining four are answered in `docs/history/todo_ledger_archive.md` under step 3, since two of them
fix the element's signature.

## 6. Storage is not output

Section 2 argues for one record per particle at `~64 N` bytes. That is a claim
about how to **write** without contention on a GPU; it is not a claim about what
belongs in the file, and the two should not be read together. The file should
carry only the particles that were actually lost -- a run losing 1% writes 1% of
`N` rows.

The justification given there for private slots over an atomic append is also
wrong as stated: an atomic "would fire for every particle" only if it sat outside
the `newly_lost` branch, and it does not. Inside that branch it fires once per
loss, which is the same rarity argument used to accept an atomic for the survival
counter. The defensible reasons for private slots are **determinism** -- slot `i`
is always particle `i`, so CPU and CUDA logs are byte-identical, which this
codebase enforces by contract -- and that `N` slots is an exact bound no run can
overflow. Both are good reasons; neither is the one originally given.
