# Gaussian-PIC Divides — Step 4f, 2026-09-05

The slice-aligned transport was built for PIC and always meant to carry more
than one solver. This is the second: `GaussianPICPoissonSolver`, which is PIC
with a control variate, now runs divided across MPI ranks on the same layout,
the same migration, the same pair protocol and the same two loops.

## What the transport had to grow

One seam, dispatched on the solver: how long its record, its folded record
and its owner's grids message are; whether it needs the slice's first member
at every pair; and four leaves -- the record it builds, what its owner makes
of the folded record, the plane solve and the kick. Everything else is
shared. The refactor is bit-neutral for PIC and that is checked rather than
argued: the launcher child's PIC lines are byte-identical to the 4d commit's
at 1, 2 and 4 ranks, across the extraction and after it.

## What Gaussian-PIC contributes

- **Fourteen shifted sums per member per pair**, about the slice's
  globally-first member, folded by the coordinator in group rank order. The
  moments come from one expression shared with the undivided path
  (`_gpic_moments_from_sums`), so a whole slice and a folded group compute
  the same thing; the split was checked bitwise both ways before anything
  else was built.
- **The subtraction on the plane's owner.** With `neutralize = true` the
  amplitude is the deposited grid's total over the profile sums, which does
  not exist before the group's partials are summed -- a per-rank residual is
  not defined, so members deposit what PIC deposits and the owner subtracts.
  Both the uncoupled profile and the coupled one (three outer products) run
  there.
- **The control-variate mode**, decided once on the owner from the folded
  moments and carried in the grids message with the moments, the slice's
  global count and the two boundary drifts -- the field members need the
  SOURCE slice's moments for the analytic add-back and are not in the source
  group.

The slice's global count comes from the layout, which already carries it.

## Measured

Bit for bit against the CPU policy at one rank on every option route: the
default subtraction, the coupled one (`coupling_tol = 1e-3`, which resolves
every slice of the fixture to `:coupled` -- measured, not assumed), no
Gaussian margin, the un-neutralised amplitude, and the sequential schedule.
Across rank counts, against that one-rank run:

| arm | worst relative difference at 2 and 4 ranks |
|---|---|
| default | 7.5e-16 |
| coupled | 3.7e-16 |
| no margin | 1.4e-15 |
| un-neutralised | 5.1e-16 |
| sequential schedule | 7.5e-16 |

The same parity class as PIC's, and the layout rule picks the loop for it as
it does for PIC: batched at one and two ranks on this fixture, dataflow at
four, where a slice is split across a group. A separate probe ran it at 8
ranks and agrees to the same class.

## Tests

Five Gaussian-PIC arms in the launcher child at 1, 2 and 4 ranks, checked by
the same rules as the PIC arms: one rank bit for bit against the CPU run,
the other counts at the parity tolerance, every rank's luminosity the same
bits, the `z` round trip, the loop each arm ran, and `:sequential` equal to
the default. The dropped-count arm is deliberately NOT mirrored: Gaussian-PIC
forces `grid_extent = :extrema`, under which the count is structurally zero,
so an arm would assert a guardrail rather than evidence of division, and the
fixture says so. In process, the same five routes are pinned bitwise at one
rank, each shown to differ from the default except the sequential schedule,
which must match it.

## What is left

Spectral, the last solver, and it will not use this transport: its collide is
order-free -- it records `batch_mode = :order_free`, has no pair schedule and
solves each source slice once rather than once per pair -- so the per-pair
protocol is the wrong shape for it. Its division belongs on the home layout:
one reduction for the Dirichlet box, each slice's mesh folded to an owner and
gathered, then every rank kicks its own particles. Its luminosity scale still
divides by `length(beam.rep)`, the shard's count -- the 4c defect, still
live there, and the first thing that step must fix.
