# Neighbour audit, 2026-08-18

Scope: the three commits since the 2026-08-16 audit — the curved-girder
survey closure (`6a39e2d`), the luminosity-observer unification phase 1
(`a438992`) and the keyword retirement phase 2 (`b654d9e`) — plus the owner's
verification protocol for the examples (updated interface, production speed,
byte identity), whose measurements are recorded in `b654d9e`'s message and
summarized here.

## Findings and fixes

1. **A misaligned parent containing a kept-whole ROLLED sub-line crashed**
   (girder neighbour, pre-existing, FIXED). `_inner_method` carried the
   `MisalignedElement` recursion but not its twin wrapper: the context-free
   call chain on `MisalignedElement(CompositeLine(RefTilted(...)))` resolved
   the tracking method through `first(ops)` — a `RefTilted` — and fell to the
   generic `inner.method`, a `FieldError` at first track. One method fixes it
   (`_inner_method(::RefTilted)` recursing like its sibling). The same
   one-wrapper-without-its-twin shape as U15-7's missing fold site. Pinned:
   the crashing composition now tracks and equals its flat spelling to
   5e-14 (measured 0.0).

2. **A nested sub-line's `ref_tilt` was invisible to both geometry walkers**
   (design-roll gap; pre-existing in `survey` since the floor plan landed,
   inherited by `_girder_design_frames` at `6a39e2d`; FIXED). A rolled
   sub-assembly is expressible (`BeamLine(...; ref_tilt=...)` stays
   kept-whole) and tracking always conjugated it exactly (`RefTilted`; nested
   vs flat tracking measured bitwise 0.0) — but `_survey_walk!` and the
   girder walk descended sub-lines without the roll, laying a rolled cell's
   bends FLAT: measured 6.4e-2 exit-position error at ref_tilt=0.4,
   angle=0.3. Both walkers now conjugate the descent by `R_z(psi)` — the same
   composition the per-element step applies, so a nested rolled bend equals
   its flat spelling (which runs through the MAD-X-pinned path) EXACTLY:
   survey positions and orientations 0.0, girder map 0.0, two nesting levels
   compose additively about a shared entrance axis (pinned). Sub-line
   misalignments and `tilt` stay excluded from the survey — errors, not
   design. One semantics point the pins settled: a per-element row INSIDE a
   rolled sub-line rightly shows the rolled frame, and the zero-length
   sub-line boundary then closes the conjugation — the closed frame is what
   parents attach to, what the walk returns, and what the flat spelling's own
   row carries (its per-element step ends in the trailing transpose), so the
   orientation equivalences are pinned on the closed forms.

3. **`TrackingTask`'s docstring signature line omitted `luminosity`**
   (phase-1 neighbour, FIXED): the kwarg was documented in prose but not in
   the signature block readers copy from.

## Checked clean (no action)

- **Examples on the latest luminosity interface**: both `examples/` scripts
  and both `test/examples/` harnesses use `luminosity=` (weak-strong moved
  its observer from a line entry to the task; the moment observer stays a
  line entry — its position is physical). Remaining `luminosity_path`
  mentions are local path VARIABLES, not keywords. Both updated harnesses
  were executed end-to-end by the production verification.
- **Top-level girder `ref_tilt`**: exact (2.8e-16 against the element
  spelling) — the map-level `RefTilted` conjugation is content-agnostic, so
  the girder closure needed no change there.
- **Production verification** (recorded in `b654d9e`): strong-strong CUDA at
  the examples' parameters 0.304 s/turn vs baseline 0.310 (turns 100–199
  mean; a first 0.79 reading was traced to a foreign co-tenant computing on
  the shared GPU and did not reproduce); weak-strong CUDA 0.0370 vs 0.0363.
  Byte identity on the deterministic paths: weak-strong GPU `.lum`
  byte-identical over 200 turns, strong-strong CPU `.lum` byte-identical
  with moment physics datasets equal; strong-strong GPU is run-to-run
  nondeterministic at 4e-15 relative BY THE BACKEND (atomic deposition),
  identical-binary runs included.
- **Luminosity retirement neighbours**: the schema/report/receipt triplet
  agrees on the single `luminosity` key (metadata validator green); the
  torn/replace/rewind warning bodies kept their pinned texts; the
  can-fail schema pin updated with the retirement dated; no live-tree
  keyword call sites remain (history records untouched, as dated records).

Full-suite gate after the fixes: green.
