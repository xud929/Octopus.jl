# Beam-beam fix batch (2026-10-18): canonical dispersion, the wrapped strong beam on CUDA, the aperture rebind

**Status:** complete 2026-10-18: three units merged, both CPU arms of the full
gate green with CUDA active on e255415; push pending the owner's word (an
addendum records the push and its CI run).

Three ledger rows in or beside the beam-beam physics focus, chosen on 2026-10-18
after the crab-cavity noise campaign closed: the strong beam's dispersion
convention (row "Strong-beam `momentum_dispersion` is a slope, not canonical
η", a 2026-09-11 lead), the misaligned strong beam on CUDA (found 2026-10-12)
and the unbound aperture under a placement offset (found 2026-10-13). Units L
(the integrator's own) and M, N (sub-agents proposing commits on their
branches, verified by the integrator before the merge) worked in separate
worktrees from main at 3a04d90. Unit reports, probes and logs:
`result/beam_beam_fixes_2026_10_18/{L,M,N}/` (git-ignored scratch; the numbers
are quoted here).

## 1 Owner decisions (2026-10-18)

1. **The dispersion convention (unit L):** the strong beam's
   `momentum_dispersion` is the canonical `eta` the Twiss analysis reports, not
   the slope `eta / h` of the physical longitudinal graph it had been; the
   builder converts. The deciding argument was a principle, recorded in
   `docs/experiences.md` ("One quantity, one convention"): within Octopus a
   parameter named for an optics quantity means what the analysis reports, and
   consumers convert inside. The alternative weighed and declined: keep the
   slope, which is what Xsuite's `dx` and MAD-X's `deltap` dispersion are and
   what a fitted beam exhibits.
2. **Rows 38 and 36 fanned out to sub-agents** that propose; the integrator
   verifies (reproduction, red/green, targeted testsets, sweeps) before merging.
3. The row "Derive the beam-beam-mediated vertical response to horizontal
   offset noise" is not an Octopus task (physics research); retired the same
   day with the batch-3 ledger commit, 3a04d90 (pushed 2026-10-18, CI run 463
   green: znver3, 59 min, the identity-pin notices 6, 5 and 4 of 6 by their
   three tables).

## 2 Units and what landed

### Unit L: the strong beam's momentum dispersion is canonical (row 39)

Branch `fix-canonical-dispersion`, commit b980bfc, 5 files. Reproduced on
3a04d90: `gaussian_strong_beam_covariance` formed `D = [zeta eta]` from its
keywords, reading `momentum_dispersion` as the slope `d r / d pz` of the
physical graph (D7), while `TwissDispersionAnalysis` reports the canonical
`eta` of (D8), `eta = h slope`, `h = 1 - zeta' S_4 eta`; on the suite's own
fixture (zeta = (0.12, -0.03, 0.04, 0.02), eta = (0.5, 0.1, -0.2, 0.3))
h = 0.957, a 4.5 % difference in the dispersive part depending on which layer
one read. Landed: the parameter means the canonical `eta`; the builder forms
the physical graph itself through the analysis's new `_dispersion_graph`
(`src/analysis/canonical_separation.jl`), whose `h` comes from a shared
`_longitudinal_factor` that `_dispersion_transformation` now reads too (one
source); `h = 0`, the isotropic graph, is refused by name; the pure limits and
a pair confined to one coordinate are unchanged bit for bit (h is exactly one).
The docstring states the convention, the conversion and how Xsuite's and
MAD-X's slopes map by (D8); theory note 8.2 and the design note's lead carry
the decision. Testset "The strong beam's momentum dispersion is canonical: the
builder forms the physical slope by (D7) and agrees with the Twiss analysis"
(the analysis run on a decoupled ring dressed by the (D3) transformation returns
the triple in `r.physical`, its graph is the builder's, and the builder fed the
analysis's own pair reproduces that graph): red on 3a04d90 (1 pass, 5 fail, 1
error), green 19 of 19; "Conditional 6D Gaussian strong-beam slicing"
re-derived for the canonical input, red on 3a04d90 (7 of 13), green 13 of 13.
Targeted, CUDA active: the slicing rules 470/470, the weak-strong limit with
its CUDA parity 4/4, the pinned-vocabulary tripwire 161/161 (the two new
functions documented), "Architecture integrity" 28/28, and -- with the suite's
own fixtures supplied to the stage runner -- every dispersion-route and
canonical-separation testset (11,805 and 2,800 assertions among them), 0
failures; sweeps green. Open: a one-line helper converting an external slope
to `eta` was not added (no caller yet; the docstring gives the formula).

### Unit M: the wrapped strong beam tracks on CUDA (row 38)

Branch `fix-cuda-wrapped-strong-beam`, commit 742431a, 6 files; proposed by
the sub-agent, verified by the integrator (its red/green re-run, its 23
targeted testsets and the three fixture re-runs, the sweeps, the backend
script with the GPU contract required, the snapshot and both validators).
Reproduced on 3a04d90: a strong beam behind a `MisalignedElement`, a
`RefTilted`, a `TurnModulated` or a kept-whole `CompositeLine` failed every
CUDA launch with `KernelError: passing non-bitstype argument`, through bare
`track!` and `execute!` alike -- `_requires_cuda_elementwise` had no wrapper
method, so the wrapper answered the generic `false`, was never lifted out of
the fused launch, and the MUTABLE element inside it reached the kernel as an
argument -- while the bare beam beside it tracked. Landed: the four wrappers
forward the predicate in both forms (`src/track/phase6d_track.jl`); the
elementwise walker hands a lifted element to the new
`_track_cuda_elementwise!` (bare beams to their own launch, a `CompositeLine`
walked member by member under the same context, a frame or turn-modulation
wrapper to the new wrapped-strong-beam kernel, the fallback throwing by name);
the whole wrapper goes to the device with every strong beam inside replaced by
an isbits device view (`ThinStrongBeamDeviceView`,
`GaussianStrongBeamDeviceView`, substituted by `Adapt.adapt` under a new
adaptor through the wrappers' existing `adapt_structure`), the kernel threads
each particle through the wrapper with `track_luminous`, and the host folds
one luminosity per beam into `last_luminosity` in line order
(`_collect_strong_beams!`, moved from the task layer to
`src/track/strong_beam_track.jl`: the track layer must not reach into the
task layer). Measured over 3 turns on 400 particles, every wrapped shape
within its declared cross-backend class: misaligned thin px 466, misaligned
sliced 483, ref-tilted thin 427 and the elliptic beam in a misaligned sub-line
630 ulps of scale against 2048; a round beam in a sub-line 2 to 3 against 8;
identity-frame wrappers reproduce the bare launch's coordinates and
`last_luminosity` to the bit through every wrapper and a nested pair; two
beams in one misaligned sub-line keep their numbers in line order within
1e-12 of the CPU fused route. The backend-consistency script's line gained a
misaligned thin strong beam (per-kind arm 34 instances within their classes,
the misaligned instance px 366, py 164 against 2048). Testset "CUDA tracks a
wrapped strong beam elementwise and matches CPU within its declared rounding
class": red on 3a04d90 13 pass, 17 fail, 1 error (the kernel error); green 96
of 96. `(_requires_cuda_elementwise, 1)` joined the wrapper-walk tripwire.
Side effects measured and kept: a bare beam handed alone to the keyword
`track!` on CUDA now tracks (it was a `MethodError`), and a wrapped
`LumpedRad` on the contextless route now takes the per-turn context launches
like a bare one. Open, pre-existing and found by the unit's measurement: the
flat `(drift, elliptic strong beam, drift)` line over 3 turns exceeds the
line-composition bound on the EXISTING CUDA path (px 3007 ulps of scale
against 2048; within class at one turn and for the sub-line) -- the class
composition rule does not model a strong beam's gradient amplifying its
neighbours' last bits over turns; a todo row. Also open: the two device views
mirror the bare kernels' per-particle bodies (the identity pin guards the
mirror; one shared body is a follow-up with its own re-measurement), and the
wrapped Gaussian route re-uploads its slice vectors per launch as the bare one
does (no new allocation measured against).

### Unit N: aperture ids thread through the frame wrappers and kept-whole lines (row 36)

Branch `fix-aperture-rebind`, commit 0b08cd8, 5 files; proposed by the
sub-agent, verified by the integrator (its red/green re-run, its 25 targeted
testsets re-run with the suite's fixtures, the sweeps, the backend script, the
snapshot and both validators: all green). Reproduced on 3a04d90 with a
200-particle fixture built to the row's numbers: the bare aperture attributes
129 of 200 to "A"; the same aperture with `x_offset = 1e-4`
(`MisalignedElement`) or `ref_tilt` (`RefTilted`) is refused with the
two-walker message "loss record sized for 1 apertures but the compiled line
contains 0"; and the row's presumption measured true: an aperture inside a
`BeamLine` placed in the task tuple (kept whole as one `CompositeLine`) was
sized out of the record by both walks, `loss_record === nothing`, 129 deaths
unattributed behind the construction warning the 2026-10-16 audit had widened
(S3-1). Landed (`src/tasks/Tasks.jl`): `_aperture_rebind`, the binder's twin
of `_survey_rebind`, binds an `Aperture` and descends `CompositeLine`,
`MisalignedElement`, `RefTilted` and `TurnModulated` (constructor for
constructor the survey walk's shapes); the spec-side collector
`_collect_aperture_specs!` and the ONE arc traversal `_collect_spec_s!`
descend a line spec entry by entry, so the record is sized and named for every
aperture and `aperture_s` stays aligned with the names (the accumulated arc is
unchanged, a line's length being its contents'); the count refusal stays and
names what still reaches it (a runtime element handed to the task directly;
pinned with a raw runtime `CompositeLine`). Accepted consequence, pinned both
ways: the survey shares the traversal, so an RF cavity inside a kept-whole
line is now surveyed through the line and bound to the same `ds_turn` as the
flat placement ([10.0, 5.0] either way; 3.0 for the single cavity) where the
survey's count check refused it, and an accelerating cavity inside one is
seen by the chain validation and the single-pass refusal that both walk specs
-- a silent hole closed. The hidden-aperture construction warning
(`_warn_hidden_apertures`, U11-8 and S3-1) retired with the limitation it
announced; the `loss_record` ParamMeta no longer claims "kill and count" for
the bare `track!` path (kill only, by design, unchanged); the RF cavity's
construction help and `docs/theory/arc_survey_and_velocity_slip.md` no longer
claim the refusal. Testset "Aperture ids thread through the frame wrappers and
kept-whole lines": red on 3a04d90 13 pass, 29 fail of 42 (every failure the
row's reason); green 49 of 49, CUDA active (the translation and composite
placements bitwise with the CPU). Three suite pins of the old behaviour
flipped in the same commit: the "(c) apertures inside a bare line placed in a
tuple" sub-testset, the hidden-aperture pin of "Nested lines have length,
...", and the two kept-whole cavity refusals of "RF velocity slip closes the
full slip factor (F16)" -- two of them matched by exception type, which the
sub-agent's text grep missed and the targeted run caught (its lesson). Open:
the wrapper-walk tripwire's list gains `(_aperture_rebind, 1)` at the merge
with unit M, whose territory that testset is; the frozen 2026-10-16 records
describe the retired warning as the behaviour of their day.

## 3 Verification

- Each unit: its regression testset red on 3a04d90 and green on its tree; its
  targeted testsets through the stage runner with the suite's fixtures
  supplied, CUDA active; the source sweeps; the backend-consistency script
  with the GPU contract required; the registry snapshot unchanged and both
  metadata validators green. The sub-agents' proposals (units M and N) were
  verified by the integrator by re-running those checks on their committed
  trees before the merge, not taken from their reports.
- The merged tree (`fix-canonical-dispersion` at a41cc7e, then the
  integration commit): the tripwire "Turn modulation: rules, wrapper and the
  pure hook" 582 of 582 with the two new walks; the three units' testsets 19,
  49 and 96; the walker agreement, misalignment, nested-line, F16 slip,
  surveyed-cavity, fused-luminosity, wrapped-stochastic, cross-backend class
  (182) and "Architecture integrity" testsets, 0 failures; the backend script
  (34 per-kind instances within their classes, the misaligned strong beam
  among them); the sweeps.
- The fast lane on the merged tree (`result/gates/turnmod/fast_lane_canon_F1.log`):
  exit 0, 336 testset rows, 16 loud lane skips, 26 min.
- The two-arm full gate, the arms one after the other in the integration
  worktree (native, then `OPENBLAS_CORETYPE=Haswell julia -C haswell`), four
  threads, CUDA active, on e255415: native arm exit 0, 351 testset rows, 153,846
  passes, 58 min (10:02 to 11:00); AVX2 arm exit 0, the same 351 rows and
  153,846 passes, 58 min (11:00 to 11:58); no failed, errored, broken or
  skipped row in either (`result/gates/turnmod/full_gate_{native,avx2}_canon_gateE.log`).
  The record commit that follows is markdown only and carries a fast lane on
  the final tree.
- Not verified here: the CI runner's identity table (read from the check-run
  annotations after the push); a GPU other than this machine's RTX 4500 Ada.

## 4 Ledger

- `docs/todo.md`: three rows retired to
  [`todo_ledger_archive.md`](todo_ledger_archive.md) under "Rows retired by
  the beam-beam fix batch — closed 2026-10-18" with their closing
  measurements (the strong-beam dispersion convention; the misaligned strong
  beam on CUDA; the unbound aperture), and one row opened from unit M's
  measurement (the cross-backend class composition rule does not model
  gradient amplification over turns).
- `docs/experiences.md`: "One quantity, one convention: the analysis owns the
  meaning of an optics parameter".
- `docs/README.md`: this record indexed.
