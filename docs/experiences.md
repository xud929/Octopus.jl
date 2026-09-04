# Experiences

The recurring lessons this project has paid for, distilled from the completed
work now frozen in
[`history/todo_ledger_archive.md`](history/todo_ledger_archive.md) and the
audit records beside it. AGENTS.md states the working rules; this file is the
evidence base — each lesson names the incidents that taught it, so a future
session can weigh the rule against what actually happened. When new work
teaches something reusable, it lands here (dated), and the full record goes to
`history/`.

## A check must be able to fail

- The effectiveness contract's original success message counted 353 checked
  while 112 declared parameters were dropped by two `continue`s with no trace —
  an unrun check reported as a pass, in the file whose job is to forbid that
  (U4-2). Every verdict the contract does not reach is now a counted metric.
- The aperture half could not fail at all: the probe killed its particle,
  `NaN <= atol` is false, and all 11 aperture parameters fell through both
  comparisons into "checked" whatever the map did (U4-1, closed 2026-08-16
  with the NaN-aware comparator and the survivable corner probe).
- The element metadata validator caught 1 of 13 injected defects because its
  checks compared values that route through the same object — `x == x` in
  three different costumes (U12-8, two remain open).
- Every can-fail control the suite carries exists because an earlier control
  could not fail: `status in (:passed, :failed)` asserts nothing (U16-2).
  Corollary learned twice since: the control's exemplar must be chosen so no
  probe improvement can un-inert it — `drift.nst` stopped serving when the
  drift probe gained kick content, and `marker.x_offset` never could serve
  because its exemption exists precisely for last-bit hair the sweep counts as
  consumed.

## Measure before designing, and record the negatives

- The F16 velocity-slip closure shipped only on its third design; the first
  two were plausible and measurably wrong, and both dead ends are recorded in
  the theory note so nobody rediscovers them (arc_survey_and_velocity_slip.md §4).
- The `tune()` "physics discrepancy" was an FFT interpolation bias growing as
  1/ν — instrument error masquerading as physics until measured down.
- Node-solve caching / the ~1e-4 interpolation floor closed NEGATIVE twice: it
  introduces more error than it removes. Standing decision; reopen only with
  new evidence.
- The CPU-threading campaign mis-attributed its ceiling twice before measuring
  it (CPU-time inflation was GC threads, a red herring; the wall ceiling is
  memory bandwidth, established by three independent tests including a
  cache-resident positive control).
- The curved-magnet-vs-patches question (2026-08-16) split exactly along
  measurement lines: free-space patches stall at the field-free wedge
  aggregate; the pole-face wedge maps converge like 1/N to the Ψ₂ floor. The
  wrong construction's stall value is pinned in the suite as a negative
  control.

## Derive, don't hand-copy — and give every derived list a tripwire

- The one-place fold-site table fell behind twice in two days (U11-3, U15-7),
  each miss turning a placement override into a written-reported-never-read
  no-op; fold sites are now declared BESIDE each fold and verified at every
  construction.
- An unread duplicate WILL drift: the PTC generator once carried its own copy
  of each case's Octopus spec that nothing read, and it had already drifted
  (U21-6). The spec table lives in exactly one place now.
- `_LATTICE_BODY_KEYS` is `keys(_LATTICE_BODY_PARAMS)` — the list cannot
  disagree with the table it indexes (U9-2). The curved-frame symplecticity
  sweep DERIVES the set of kinds carrying both curvature and field, and that
  tripwire fired correctly the moment the U9-2 schemas landed, demanding the
  five new routing cases on the spot.
- The registry snapshot is regenerated, never hand-edited; a stale snapshot
  aborts the suite loudly.

## Loud beats silent — and loud-but-wrong is worse than silent

- A typo'd physics key stored as silent metadata is silent wrong physics; the
  unknown-key warning exists for that. But before the schemas told the truth,
  that warning claimed keys the runtime READS were "NOT being tracked" —
  measured shifts up to 5.8e-2 — loud AND wrong (U9-2). A warning that lies is
  worse than none.
- Count tripwires catch what silence hides: the dropped-charge tripwire caught
  83% of a slice silently discarded the day it landed; the accelerating-cavity
  count tripwire caught a kept-whole hidden cavity that compiled and ran
  multi-turn.
- Fast-lane skips print a banner naming every skipped gate: a checkpoint that
  looks like a finish line is how coverage quietly narrows.

## Exemptions and allowlists age

- An exemption for a parameter that has become effective excuses it forever,
  silently — the direction that matters. The stale-exemption tripwire (U4-17)
  catches entries the sweep never reaches; nothing mechanical catches a wrong
  one, so retiring exemptions beats accumulating them (drift.nst and
  drift.integrator_order were retired the day a loaded drift genuinely split).
- Thirty copies of one reason is worse than one: kind-independent facts
  (`name` is carried, never consumed) get one entry, not per-kind copies each
  needing its own staleness bookkeeping.

## A probe must put the parameter where it can act

- `highest_fringe` at a pure-k1 quadrupole capped nothing; `fringe` at
  highest_fringe=1 compiled four bitwise-identical maps (U4-4). The probe
  table's own rule: conditional parameters sit in a configuration where they
  can act.
- The misalignment CONVENTION is observable only with all six placement
  degrees of freedom nonzero — measured 0.0 at single offsets, 1.294e-4 at the
  full shape (U4-12). One central merge enriches every probe identically.
- The curved-frame truncation taught the two-sided version: a normal K_n needs
  `curved_order >= n+1` to reach the curved body at all, while the truncation
  STEP is invisible without high-order content to correct — the multipole
  probe needed its own working point where both are simultaneously visible
  (U9-2).
- An aperture's map is the identity for survivors, so its only strong
  observable is the alive/dead flip — which requires a baseline that LIVES,
  and shrinking-limit alternatives, because the generic perturbation only ever
  grows a value (U4-1).

## Two spellings of one truth are reconciled by construction, not convention

- `k1` and a nonzero `kn[2]` together THROW rather than letting one spelling
  silently win; `angle` contradicts `h`/`b0` and throws; a `harmon` cavity
  compiled without its ring context carries a NaN sentinel and REFUSES to
  track rather than guessing a frequency.
- A constrained pair is one degree of freedom: `beta0`/`gamma0` are perturbed
  JOINTLY on the physical manifold, after the generic sweep "checked" beta0
  at 1.12 — faster than light (U14-4).

## External codes: measure their conventions, never read them

- MAD-X RBEND `L` is the CHORD by default (`rbarc`); MAD-X `sbend, tilt=` is
  Octopus `ref_tilt`, NOT `tilt` — the keyword trap the whole ref_tilt feature
  exists for; PTC's `T` is conjugate to delta with opposite orientation; MAD-X
  TFS output truncates to 10 digits unless `set, format="22.16e"` — which once
  masqueraded as a 3.9e-10 physics deviation.
- MAD-X 5.03.06 IGNORES `k0` on SBEND for PTC (measured bit-identical with k0
  absent, 0, 0.12, 1e-6), so `h != b0` has no spelling there; EFCOMP field
  errors DO transfer, take INTEGRATED strengths, and are the only door to
  orders above K3 on a thick element — the k3 ceiling is MAD-X's attribute
  surface, not PTC's.
- PTC's wedge branch reads a module variable left with no initializer; its
  MAD8_WEDGE branch hardcodes (1,2). Both are now declared behavior in
  `wedge_coeff`'s metadata because they were measured, not because any manual
  says so.

## Mechanics that bit more than once

- `Core.Box` closure captures broke performance or correctness THREE times in
  one campaign (reused variable names, both-branch assignment); the tripwire
  that hunts it earns its keep.
- A docstring is detached by any expression inserted between it and its
  target: the tripwire caught the same mistake twice in two days
  (`_PLACEMENT_PROBE_DOF`, `_LATTICE_BODY_PROBE`). Put new consts ABOVE the
  docstring block.
- Backticks in `git commit -m` are command-substituted by the shell; commit
  messages go through `git commit -F <file>`.
- Test pins must use representable arithmetic: `(1.0 + 1e-9) - 1.0` is not
  1e-9, and `isapprox` at tiny magnitudes fails on the representation error of
  the pin itself.
- A NamedTuple iterates VALUES; iterate `pairs(...)` for key-value loops.
- Generated artifacts are written to a temp file and renamed on success —
  truncating the committed reference before the first of 55 jobs runs leaves a
  partial artifact on any mid-run failure (U24-10).
- Warnings that fire per compile need `maxlog` and a content-keyed `_id`: a
  knob sweep recompiles thousands of times, and a warning that repeats
  thousands of times is silence with extra steps.
- Marker-span deletion scripts overshoot: deleting `LuminosityObserver`
  (2026-08-18) by from-marker-to-marker cuts also swallowed the neighbouring
  `observer_option_schema` stub, two other observers' schemas, and the
  snapshot prepare/discard machinery — and the module still LOADED, because
  Julia only misses a method at call time. After any type-level deletion, run
  a survival probe of the neighbours' surface (their schemas, constructors,
  reports), and recover swallowed text from `git diff`, which still holds it
  verbatim.
- A mutable object built per particle inside a hot loop and handed to a
  non-inlined callee escapes to the heap, one pool allocation per copy: the
  sliced strong beam did this per slice per particle -- 7 x 192 B = 1344 B per
  particle per turn, all but the per-call constants of the weak-strong line's
  1.282 GiB/turn (1344 B x 1,024,000 is the whole figure) and the
  whole reason its thread scaling capped with half of wall in GC (multi-process
  step 1, 2026-09-04). The fix-1 shape again: an isbits carrier, the
  arithmetic untouched, the digest unmoved. Two habits sharpened: divide a
  per-turn allocation by the particle count before reading it (the Phase 0
  record's "1.25 KB" was the decimal reading of the same 1344 B), and check
  the sibling copy of the loop -- the elementwise luminosity path every
  observer and artifact run takes had the same site, and the benchmark
  exercised only the fused copy.
- A refusal's blast radius includes the validation scripts that construct
  what it refuses: the accelerating cavity's single-pass refusal (2026-08-14)
  broke `validation/tracking_backend_consistency.jl` at its two-turn default
  the same day the cavity joined that script's line, and nothing ran the
  script for three weeks -- found 2026-09-04 when multi-process step 1 ran it
  as the matrix's targeted check. Second time for this script (the U14-4
  reference-pair invariant did the same for three days). A targeted check is
  only a check while something runs it; a change to acceptance or rejection
  semantics re-walks the validations, not only the suite.
- A sweep that covers the file you are editing and not its sibling: U3-2
  capped 4 of 12 kick launches (3a395ae); U1-6 updated 8 call sites in
  `pic_cuda.jl` and missed 4 in `gaussian_pic_cuda.jl` (81430eb). Both were
  caught by the full gate, not the edit. Grep the whole `src/` tree for the
  old name or arity (Measured Lesson 12 in `comprehensive_audit.md`).

## A type inner code dispatches on is a bad thing to wrap

- The multi-process policy was designed as a wrapper around
  `ResolvedCPUExecutionPolicy` and an unwrap at "the task drivers"; an
  adversarial read of the draft found the public keyword `track!` entry
  resolves and passes the resolved object positionally into a method typed on
  the concrete CPU type, so the published entry point would have thrown a
  `MethodError` (2026-09-04, step 2). Eight methods and the worker-count
  accessor dispatch on that type and four call sites pass it on. A SLOT on the
  existing type instead of a wrapper around it made "at one rank nothing
  changes" true by construction rather than by an argument that had to be
  right at every site.
- Resolution must stay pure. `configuration_report` resolves a policy only to
  describe it and the strong-strong task resolves once per beam, so a side
  effect at resolution (initialising MPI) fires when someone asks a question.
  Side effects belong at activation, which happens once, where the run
  actually begins.
- A package extension must ADD a method, never redefine one its parent
  already defined for the same signature -- that fails to precompile. Core
  declares the fallback on `::Any` (or on `::Nothing` for the communicator
  argument) and the extension the specific method; the dispatch, not a
  mutable hook, is what selects it.

## Re-price accepted limitations after every campaign

- The curved-girder exit patch was measured wrong at dx·θ, documented, warned
  about, and ACCEPTED in 2026-08-05 — correctly, because closing it "needs a
  real accumulated-frame survey, which is a feature, not a patch". The
  floor-plan campaign then built exactly that feature for a different reason,
  and the limitation's price collapsed: the closure (2026-08-16) was one
  generalised frames function plus a walker over machinery that already
  existed, exact at 2.3e-16 where the acceptance had tolerated 4e-4. An
  accepted limitation is a decision priced against the machinery of its day;
  when a campaign lands new machinery, re-read the accepted list — one of its
  prices has usually just dropped.
- Second instance (2026-08-19): `GaussianPoissonSolver` was deliberately
  denied `luminosity_schedule` because scheduling could save no compute (the
  by-product, ~0%). The run artifact changed what the schedule MEANS — which
  turns get a row — and that half applies to every solver, so the refusal's
  price collapsed and the keyword completed the set with reporting-only
  semantics. A refusal is priced against what a knob DID at the time; when a
  campaign changes what the knob means, re-read the refusals too.

## Process habits that earned their place

- The full-suite gate runs before EVERY commit; the fast lane is a checkpoint,
  never a finish line. One derived exception since 2026-09-03: a diff that
  `git diff --name-only` shows to be markdown-only (no `.jl`, no `.toml`, no
  `.yml`, not the registry snapshot) finishes with the fast lane on the final
  tree, because the fast lane already runs every docs check the suite has.
- A neighbour audit follows every campaign; each one so far has found and
  fixed a real gap the campaign itself missed.
- A recorded claim can be wrong: the curved-frame solenoid was closed on a
  wrong argument, reopened, and implemented — the withdrawn closure is kept
  readable so the mistake stays visible. Corrections live BESIDE originals,
  never replacing them.
- Decisions outrank stale plans: a phase list written before a decision does
  not override it — check the decision items before implementing a
  predecessor's sub-item.

## Standing decisions, deliberately not being done

Closed with reasons; reopen only if the stated condition changes.

- **Soft-fringe solenoid** — only Elegant has one and it is a field-map
  integrator, not a portable analytic model. Revisit if a fringe-region study
  appears.
- **`pz` fail-fast gap** — accepted because production runs use
  `allow_lost_particles`; the conditions that would reverse it are recorded in
  the archive.
- **Node-solve caching / the ~1e-4 interpolation floor** — closed negative,
  twice: it introduces more error than it removes.
- **Nightly scheduled jobs on the shared 128-thread box** — the 2026-08-07
  system-manager directive stands; benchmark and nightly scripts ship inert
  and opt-in per machine, and nothing unattended writes to shared history.
- **`AGENTS.md` carries stable invariants and routing only** (2026-09-03
  restructure, owner decision). Dates, campaign identifiers, directory
  counts, and incident narratives live in generated registries, this file,
  the Measured Lessons, and `docs/history/`; procedures live in
  `docs/guides/`, one guide per routing row. A fact that will age does not
  go in the entry point; a tripwire test replaces any hand-maintained count.
