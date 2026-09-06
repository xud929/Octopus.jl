# Spectral Divides — Step 4g, 2026-09-05

The last solver. `SpectralPoissonSolver` now runs divided across MPI ranks,
and with it `_reject_undivided_solver` has nothing left in the roster to
refuse.

Spectral is the one solver with TWO collides, and they divide by different
means because they are different algorithms.

## The 6D map takes the slice-aligned layout

`longitudinal_kick = true` is the default and the production route, and it is
order-DEPENDENT in exactly the way the PIC collide is: a slice is kicked by
the pairs before it and then serves as a source at its kicked positions. So it
takes the transport 4d built — the layout, the two migrations, the buffers,
the wavefront batches — and `spectral_sliced.jl` is its batch loop.

An earlier reading in the 4f note said spectral would divide on the home
layout because "its collide is order-free — it records
`batch_mode = :order_free`, has no pair schedule, and solves each source
slice once rather than once per pair". Every clause of that is true of the
TRANSVERSE route and none of it is true of the default one. The 4f note has
been corrected.

## Who solves, and why it matters more here than for PIC

Spectral negotiates almost nothing. The Dirichlet box is ONE box for the
whole collide, so there is no per-pair geometry to reduce, no extents record,
no owner deal, no Green table to publish: stages 0 and 1 of the PIC loop do
not exist. That freedom picks a better owner. The solver of a directed
interaction is the FIELD slice's group head, not a dealt third party: the
source group sends its TWO drifted deposits (the L and R planes of
`_spectral_interaction!`), the head folds and solves them, and the potentials
never leave the group that needs them. Under `P <= nslices` that is two
messages per direction per pair and no broadcast at all, against the six a
source-solves scheme would send (three mesh arrays for each of the two
drifted planes).

Dealing the solve out at all is the point. Measured at 64x64 with 6000
particles: one DST solve 271 us, one mesh evaluation against a slice 64 us.
A scheme that folded the deposit and let every rank solve it would leave the
dominant term undivided and cap the speed-up near 1.2x however many ranks
ran. Pairs in one wavefront batch share no slice, so the field heads of a
batch are distinct ranks and the batch's solves run at once.

Taking every source deposit and every virtual position BEFORE the pair kicks
anything buys two things: the two directions become independent, and both
slices can be kicked in place. The undivided loop copies slice j only because
it takes its deposits later.

`:grid_free` rides the same protocol with a different payload — sine-mode
sums instead of a CIC deposit, and no mesh to send, because evaluating the
modes is per FIELD particle and already each member's own work.
`_spectral_payload_planes` is the one place that difference lives.

## The transverse map stays on the home layout

`longitudinal_kick = false` reads positions and only accumulates px/py, so
slice-pair order is irrelevant and there is nothing to migrate for. Two
things cross the ranks and nothing else:

- Each source slice's plane, summed once for the collide. The `:grid` solves
  are then dealt round-robin and published by a second all-sum, each mesh
  written by exactly one rank and zero elsewhere, so the fold is that rank's
  value exactly. `:grid_free` needs only the first fold: its evaluation is
  per field particle.
- The density-overlap luminosity, which needs both slices' global extents
  (one all-max) and the product of two FOLDED deposits — no rank can form
  that from its own share. One all-sum per GROUP of field slices, the group
  sized so the buffer stays bounded however many slices a run carries.

The kick never leaves a rank.

## The global scalars both routes needed

The Dirichlet box is the beam's, not the shard's, and every kick is solved on
it. `_lane_z_moment` already returned the folded scalar, so what was still
local was the rms COUNT and the extrema. The non-finite verdict runs BEFORE
either — taken on local data, agreed as an integer count — because a NaN
handed to `_mp_allminmax`/`_mp_allmax!` comes back different on different
ranks, and a rank that decided from an exchanged bound would throw while its
peers walked into the next collective. That is the seam's own rule and the
one the PIC collide follows.

`_spectral_luminosity_scale` divided by `length(beam.rep)` — the 4c
shard-count defect, still live in spectral because nothing had divided it. It
now reads the scoped global count, no collective.

## The refusal became a tripwire

Nothing in the roster refuses any more, so `_reject_undivided_solver` reads
`_solver_divides`, which answers `false` for `AbstractPoissonSolver` and
`true` only where someone divided the collide and said so. A solver added
after the campaign refuses under a multi-process policy until it is divided.
The suite asserts both halves: every solver in the roster answers `true`, and
`invoke` on the fallback answers `false`.

## Measured

Bit for bit against `CPUThreadsExecutionPolicy` at one rank on both routes
and both methods, and last-bit agreement (~1e-15 relative) at two and four
ranks. `z` comes home to its slot bit for bit on every rank. The two
schedules of the 6D map agree bit for bit, and so do the one- and two-thread
runs. Those claims are in the suite, at 1, 2 and 4 ranks under the launcher.

Checked by probe rather than by the suite, because the shared machinery it
exercises has no arm for any solver: a `luminosity_schedule` that declines
returns `NaN` on both routes at one and four ranks and blocks nothing --
the verdict is rank 0's, broadcast, because a schedule predicate is user code
and its answer gates the luminosity exchanges.

Scaling of the 6D map, 90,000 particles per beam, fifteen slices, a 64x64
mesh, best of five on a shared box:

| ranks | ms |
|---|---|
| undivided | 451 |
| 1 | 497 |
| 2 | 372 |
| 4 | 230 |
| 8 | 130 |
| 16 | 74 |
| 32 | 227 |

6.7x over the one-rank divided run at sixteen ranks. Thirty-two ranks is more
ranks than slices, where every slice becomes a group and the protocol pays
for it; that regime is a todo row, not a claim. The box was shared during the
measurement and the spread run to run was large, which is why these are
best-of-five rather than means.
