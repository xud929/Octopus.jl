# Neighbour audit, 2026-08-16

Scope: the six commits since the 2026-08-14_b audit — the ParamMeta
`alternatives` keystone (`3542eb6`), the U9-2 body-schema completion
(`0ed664c`), the curved-magnet coordinate-change pins (`80e5b79`), the six PTC
curved-potential cases (`f10f2ac`), the U4-1 aperture repair (`e2232bf`), and
the TODO ledger restructure (`0184746`). Per protocol, the audit examines the
NEIGHBOURS of each change — the places that mirror the changed code but were
not changed — for the same defect class, plus (owner request) a repository
findability pass: every document reachable, every reference resolving, and
`experiences.md` wired into the modification workflow.

## Findings and fixes

1. **`alternatives` was machine-readable but invisible** (keystone neighbour,
   FIXED). `_schema_meta_suffix_param` rendered required/unit/default/meaning
   and skipped the new field entirely, so `element_help` never showed a
   parameter's declared enum — the same shape as declared-but-not-consumed,
   one layer up. Fixed and probed: `element_help(SBendSpec)` now prints
   `alternatives=:exact, :drift_kick` (and the convention, fringe, aperture
   enums); the existing help tests assert substrings only and are unaffected.

2. **`_extra_tracked_keys`'s docstring contradicted its own repair** (U9-2
   neighbour, FIXED). One commit after the schemas were completed, the
   docstring still described completion as future work "recorded on
   docs/todo.md" — stale twice over, since the row had closed AND moved.
   Rewritten: no kind extends the mechanism today, the schema tells the truth,
   and the list stays empty; kept as the stopgap for a kind caught mid-repair.

3. **`validation/README.md` said "the 55 cases"** (PTC neighbour, FIXED) —
   stale since `f10f2ac` took the table to 61. The paragraph now names the
   curved-potential channels, the EFCOMP door for orders above K3 with its
   integrated-units convention, and the measured `k0`-ignored limitation.

4. **~45 references to `docs/todo.md` pointed at content that moved**
   (restructure fallout, FIXED). Swept src (the N1 non-finite chokepoint
   comments, `Tasks.jl`'s observer-identity deferral, `misalignment.jl`'s
   overturned prediction, `aperture.jl`'s design pointer, `rf_cavity.jl`'s
   F16 note), test comments citing closed rows, and the live docs
   (theory/design notes, `validation/README.md` and two validation scripts)
   to `docs/history/todo_ledger_archive.md`. Two references were verified
   LIVE and deliberately kept: `interface.jl`'s U4-18 note and the
   rf-cavity theory note's item-5 rider (both still open in `todo.md`).
   `docs/history/` records were left untouched on purpose: they cite the
   ledger as it stood at their date, which is what a dated record means.

5. **The archive's own 47 relative links broke on the move** (restructure
   neighbour, FIXED): `history/…`, `theory/…`, `design/…` targets were one
   level off after the file moved under `history/`. Retargeted mechanically;
   the preamble records the path-only exception to "frozen verbatim". A
   repository-wide link check now passes: 0 broken relative links across
   docs/, AGENTS.md, README.md and validation/README.md (excluding frozen
   unit-report internals), and 0 documents missing from the `docs/README.md`
   index.

## Checked clean (no action)

- **Solver-option effectiveness contract**: already carries its own
  `alternatives` mechanism (`_default_solver_option_alternatives`) — the
  keystone had a precedent, not a gap — and its comparator is already
  NaN-aware (`isnan(x) && isnan(y) → continue`), so no U4-1-class blindness.
- **Solenoid** (the seventh magnet-like kind): its runtime reads L, ks, kn,
  kskew, h, curved, nst — all declared; no U9-2-class schema gap, which is
  also why it never needed an `_extra_tracked_keys` entry.
- **Thin kinds**: `ThinMultipole` reads knl/ksl only; schemas complete.
- **Generated docs** (`registry_snapshot.md`, `public_api.md`): neither
  embeds parameter-suffix text, so the help-rendering fix requires no regen.
- **`.ipynb_checkpoints` duplicates** under docs/theory and docs/design are
  git-ignored working-tree artifacts, not tracked content.

## Findability wiring (owner request)

`docs/experiences.md` is now reachable at every point an agent starts work:
the AGENTS.md orientation section (read alongside `todo.md`), the Hard-Won
Rules section (**read before any modification or new feature**, with the
relationship to `comprehensive_audit.md`'s Measured Lessons stated), and a
preamble to the Updating-workflows series (each workflow exists because
something went wrong once; that file records what and how much it cost). The
documentation rule now routes closures explicitly: rows close into the
archive, reusable lessons land in `experiences.md`, and both files sit in the
`docs/README.md` index.

Full-suite gate after the fixes: green.
