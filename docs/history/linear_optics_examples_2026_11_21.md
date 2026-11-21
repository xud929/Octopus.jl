# The shipped examples in the LinearOptics form (2026-11-21)

Follow-up of [`linear_optics_2026_11_21.md`](linear_optics_2026_11_21.md), at
the owner's request after that batch's push ("update the examples to use the
new optics settings"). Design: [`../design/linear_optics.md`](../design/linear_optics.md).
Guide: `../guides/examples_and_validation.md`.

## 1 What changed

- `examples/weak_strong_tracking.jl` and `examples/crab_cavity_noise.jl`: the
  weak beam's linear optics are two `LinearOptics` points, `ip_point` (beta,
  alpha, the canonical dispersion and the Edwards-Teng R of the `weak_beam`
  input) and `crab_point` (the crab cavities' beta, uncoupled and
  dispersion-free at alpha = 0). `Beam(; optics = ip_point)`, the transfer maps
  `Linear6DSpec{Float64}(crab_point, ip_point; dmu)`, `(ip_point, crab_point;
  dmu)` and the one-turn map `(ip_point, ip_point; dmu)`, the chromaticity kick
  and the lumped radiation (`optics = ip_point`) flatten the same points. The
  input's `radiation` block lost its own `alpha`, `zeta`, `eta`, `coupling`
  (the IP point carries them; a field the code no longer reads is not kept).
  The strong beam keeps its flat transverse `beta`/`alpha` pairs, with the
  reason in a comment: its longitudinal plane is the slicing's, and a 6D point
  would carry an inert third plane.
- `examples/strong_strong_tracking.jl`: per beam, `ele_ip`/`ele_crab` and
  `pro_ip`/`pro_crab`; both `Beam`s, the six transfer maps, the two one-turn
  maps, both chromaticity kicks and the electron radiation element take the
  points.
- `examples/twiss_dispersion_dba_ring.jl`: after the matched sizes, the
  certified result becomes the constructible point, `linear_optics(r; frame =
  :ring)::LinearOptics`, and its Twiss, Edwards-Teng R with form, canonical
  dispersion and h are printed.
- `src/examples/Examples.jl`: the four entries list `LinearOptics` among the
  objects they are precedents for (the suite's word-boundary tripwire reads
  each script for every listed name); the weak-strong and DBA summaries name
  the point and the accessor.
- Not changed: `examples/knob_control.jl` spells no linear optics; the
  developer harnesses under `test/examples/` keep the flat keyword form, so a
  precedent of each spelling remains in the tree.

What the object form changes beyond spelling: in the flat scripts the transfer
maps, the chromaticity kick and the radiation element carried zero dispersion
and coupling whatever the `weak_beam` input said, so a user who set `coupling`
or `eta` on the beam got a lattice that did not match it; the points make the
maps and the beam one description.

## 2 Verification

- The four updated scripts run at their shipped small `config` on CPU threads
  (2026-11-21, 15:04 to 15:08 EST, `execution = :threads`, output under
  scratch): exit 0 each; the DBA script prints the point (beta (1.722, 8.406,
  1.531), alpha (-0.030, 0, -0.138), Edwards-Teng R at 1e-16, form 1, eta_x
  0.757, zeta (-0.068, 0.042, 0, 0)).
- The updated weak-strong and strong-strong scripts against the flat versions,
  by the compare recipe of `linear_optics_2026_11_21.md` section 4 (10,000
  macroparticles and 50 turns; 2,000 + 2,000 and 20 turns; seed 123456789;
  SHA-256 of the final coordinates, the rms, the luminosity and the moment
  tables): on CPU threads all ten hashes identical to the flat versions'
  (`result/gates/linopt/compare/fingerprints_post.txt`), so the object form
  flattens to the same physics bit for bit.
- The five scripts under `examples/` at their shipped `config` with the tree's
  `:auto` device line, as the suite's example testset runs them (2026-11-21,
  15:43 to 15:50 EST): the three tracking scripts on `CUDAExecutionPolicy`,
  the DBA and knob scripts on the CPU, exit 0 each.
- The same compare recipe with `execution = :cuda` against the flat versions'
  CUDA run (`fingerprints_post_cuda1.txt`): the four weak-strong hashes
  identical; the six strong-strong hashes differ within the GPU's run-to-run
  noise measured in the LinearOptics record (largest relative difference
  5.2e-9, on the smallest electron moment `m001010` at scale 1.3e-9; the
  run-to-run spread of one tree reached 6.1e-9 there), so nothing
  attributable to the spelling is visible on CUDA either.
- `write_registry_snapshot()` after the catalogue change: four `Objects`
  lines gain `LinearOptics`, nothing else moves; the snapshot is committed.
- Extracted from the suite after the change (`using Octopus`, the blocks cut
  out by title): "the Example core object answers with real scripts" (52 of
  52: every listed object is named in its script, every script catalogued),
  "Stage 5: every kind that declares the analysis analyzes its own example"
  (64 of 64). Two example-named blocks cannot run extracted, "Stage 9
  follow-up (the DBA-ring example check)" (a file-level helper) and "Every
  example script runs against the current interface" (it resolves
  `examples/` from the test file's own directory); both run in the full gate,
  which is the lane that executes the examples.

## 3 The gate

Examples execute in the full lane only (AGENTS.md matrix), so the full gate
with CUDA active ran on this batch's working tree after this record was
written, and the tree was committed unchanged; its numbers (testsets,
assertions, skips, wall clock) are in the commit message of this batch, as a
record cannot carry the gate that covers it without a second commit and lane.

## 4 Ledger and the previous batch's push

`docs/README.md`: this record. `docs/todo.md`: the LinearOptics row (pushed,
and the examples in the object form). `docs/registry_snapshot.md`: regenerated
for the catalogue summaries. The LinearOptics batch (c84ed93 design note,
9fb9a2d feature, 06b64f0 record) was pushed on 2026-11-21 at 15:42 EST as
9c48589..06b64f0; its CI run was pending when this record's gate started, and
its number and result are in this batch's commit message.
