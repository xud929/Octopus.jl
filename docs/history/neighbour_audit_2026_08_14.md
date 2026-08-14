# Targeted Neighbour Audit — the survey/velocity-slip/Scope-B campaign

Range audited: `cc1094b` … `f66a129` (the CI-diagnosis correction, the
design-note pair, the `lane=fast` mechanism, the geometric survey channel
with the F16 velocity-slip closure and its MAD-X contract, the CUDA parity
pin, the rbend `chord` bridge, and the Scope B accelerating cavity).
Method per [`../comprehensive_audit.md`](../comprehensive_audit.md)
("the post-campaign standard"): for each fix, re-walk call sites and sibling
surfaces, and re-run the property the fix was about on the neighbours it did
not change. This campaign's audit was run inline by the driving session
(the diffs were hours old and already load-bearing); the probes are in the
session scratchpad and their numbers below were taken from live runs, not
recalled.

## Campaign-wide properties, re-run at final HEAD

- Full-suite gate at CI settings, CUDA active: green at every landing
  commit; final suite 188 testsets.
- `validation/tracking_backend_consistency.jl` with the accelerating cavity
  added to its case list: CPU/CPU exact, CPU/GPU max_abs_error 2.8e-16,
  zero lost-on-one-backend slots.
- `MADXSurveyConsistencyContract`: 6 fixture lines, worst deviation **0.0**
  at full TFS precision (after the `set, format` fix — MAD-X's default
  10-significant-digit table format had masqueraded as a 3.9e-10
  "deviation" against its own rounding).
- The F16 ring physics: `nu_s` on the full-`eta` prediction (rtol 5e-3
  suite pin), the 1.84x corrected-vs-bare A/B, the transition-side flip,
  and CPU/CUDA bit identity for the surveyed cavity.

## Per-fix neighbour walks

**The arc walker generalization (`_collect_spec_s!`).** Call-site sweep:
every consumer is in `Tasks.jl` (aperture arc positions, the cavity `ds`
bind, the reference-chain walk) plus one suite testset — all updated when
the payload widened to `(s, L, element)`; no stragglers. The aperture
consumer's behavior is pinned by the pre-existing aperture testsets (gate
green), and the walker's agreement with `s_positions` is a suite assertion.

**The F16 z-shift.** `convert_longitudinal` callers: only
`longitudinal.jl` itself and `rf_cavity.jl` — no other element consumes the
conversion, so no sibling inherits the slip question silently. The one
sibling that inherits it *conceptually* is `ThinCrabCavity` (phase read
from a path coordinate): ledgered as a todo row during the campaign rather
than fixed in passing, with the assessment framing (the observable is
crabbing phase/luminosity, not `nu_s`). `examples/` sweep: **no example
uses an RF cavity**, so no published output shifts.

**`_requires_tracking_context` wrapper recursion** (landed inside the
survey commit as a neighbour fix). Audit finding: it landed **without a
test** — the exact "fix with no pin" gap this protocol exists to catch.
Closed in this audit's commit: the aperture loss testset now asserts the
requirement is seen through `CompositeLine`, `MisalignedElement`, and
`RefTilted` wrappers.

**The `lane=fast` mechanism.** Full-mode transparency re-verified at every
gate (zero `LANE SKIP` lines, all testsets present); CI and
`test/nightly_suite.sh` pass no `test_args`, so neither can select a lane.
The measured numbers in `testing_lanes.md` are dated measurements, not
live claims. During this campaign the lane checkpoints caught, in order: a
stale registry snapshot, a closure-capture bug (an inner `k` assignment
clobbering the enclosing RF wavenumber — the `Core.Box` class, in a test),
FFT estimator bias masquerading as physics, a missing registry
description, and an undocumented export; the full gate caught what the
lane deliberately skips (the effectiveness-contract ceilings).

**The rbend `chord` bridge.** Sibling of the `angle` fold: the
folded-override guard gained the mirrored `chord` case (message carries
the conversion). Stray `chord` on `SBendSpec` itself takes the existing
loud unknown-key warning ("NOT being tracked") — adequate; upgrading it to
a throw with "did you mean RBendSpec(chord=…)?" is priced as a
nice-to-have, not done. The convention itself is pinned by the
`rbend_chord` fixture: a true MAD-X RBEND against the construction fold,
deviation 0.0.

**Scope B (`ThinAcceleratingCavitySpec`).** Probed beyond its own testset:
a *misaligned* accelerating cavity compiles wrapped and tracks; an
accelerating cavity's `L` correctly advances the ring cavities' `ds`
partition in a mixed line (measured `[30, 70]` on a 100 m fixture); a
*placement override* of `gamma0` reaches the chain validation (the walker
reads merged params), refusing the broken chain. The
kind's registration tripped three suite ratchets, each closed by its own
documented protocol: the differentiable-parameter count (25 → 29, four new
complex-steppable derivatives), the effectiveness `checked` floor
(369 → 382) with `beta0`/`gamma0` **coupled-perturbed** like the ring
cavity's (a reference pair is one particle — U14-4 — rather than bumping
the `rejected` ceiling), and one structural `unperturbable` (73 → 74).

## Dispositions

| finding | disposition |
|---|---|
| wrapper-recursion refusal had no pin | **fixed here** (testset extension) |
| `SBendSpec(chord=…)` warns, does not throw | priced, not done (warning is loud and names the key) |
| Scope-A rf cavity mid-chain is not checked against the local reference | ledgered on the Scope B todo row |
| a closed ring containing an accelerating cavity is documented, not detected | ledgered on the Scope B todo row |
| PTC/MAD-X reference case for the accelerating kind | ledgered on the Scope B todo row |
| crab-cavity velocity-slip class | ledgered (campaign-time todo row) |
| commit messages `d534d0b`/`0606fb4` lost backtick-quoted words to zsh substitution | process note: write `-F` files; history not rewritten |
