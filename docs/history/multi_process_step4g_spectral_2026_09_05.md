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
mesh, best of five on a shared box (which carried other work throughout, so these are best-observed rather than means):

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

---

## The second half, 2026-09-06: the rank ceiling, and a lever nobody was pulling

The first cut scaled to sixteen ranks and turned back up at thirty-two. The
owner asked for that to be fixed rather than recorded, on the ground that
"it is quite often we have more CPUs than slices" -- which is the regime the
turn-up sat in.

### What the ceiling actually was

Every step of the collide splits by particle across a slice's group except the
DST solve, which is one indivisible FFT per drifted plane and about 70% of the
work. That solve was pinned to the field slice's group HEAD. So the number of
ranks that could solve was the number of SLICES, and -- because both beams'
layouts are built by the same rule from near-identical counts -- the
direction-1 heads and the direction-2 heads are the same ranks, not two sets.

Read from each rank's own exchange receipt, 90,000 particles a beam, fifteen
slices:

| ranks | solving before | solving after | busiest rank's planes |
|---|---|---|---|
| 8 | 8 of 8 | 8 of 8 | 120 -> 120 |
| 16 | 16 of 16 | 16 of 16 | 60 -> 60 |
| 32 | 20 of 32 | 32 of 32 | 60 -> 30 |
| 64 | 23 of 64 | 64 of 64 | 60 -> 20 |

At sixty-four ranks forty-one did nothing, and the busiest rank carried exactly
the load it had at sixteen. The thirty-two-rank distribution was
`60,0,60,0,...`: `first(group)` is always the even rank.

### The fix

Deal a pair's four solves -- two directions times the two drifted planes --
across the field slice's group, one solver per (direction, plane), offset by
the pair's collision position. A group of one gives that member both planes, so
the regime that already worked is unchanged message for message and bit for
bit; the launcher child's spectral lines are identical across the change at 1,
2 and 4 ranks.

**The timing comparison first published here has been WITHDRAWN** (2026-09-06).
It went through the bare `collide!` entry, which defaults its scratch,
migration and pool refs to fresh ones per call while a `StrongStrongTask` holds
them across turns, so every collide rebuilt every buffer it owns -- a term
invisible at one rank and dominant at sixty-four -- and it ran on a box
carrying other work. It reported 209 ms at sixty-four ranks where the identical
collide measures 40.8 with the refs a task holds, and the conclusion drawn from
it ("the curve turns up past thirty-two ranks") does not survive. The evidence
for the ceiling that stands is the solve distribution above, which no clock
enters. The lesson is in `experiences.md`.

Measured again through the refs a task holds, arms interleaved in one process,
90,000 particles a beam, fifteen slices, a 63x63 mesh:

| ranks | widest group | ms |
|---|---|---|
| 1 | 1 | 379.4 |
| 2 | 1 | 286.1 |
| 4 | 1 | 179.0 |
| 8 | 1 | 100.0 |
| 16 | 2 | 55.6 |
| 32 | 2-3 | 37.4 |
| 64 | 4-5 | 39.0 |

Ten times the one-rank run at thirty-two ranks, and the curve FLATTENS rather
than turning up, which is what sixty concurrent solves predicts for fifteen
slices. Below sixteen ranks the deal changes nothing -- a group of one is the
rule it replaced.

`4 * min(n1, n2)` is the most any schedule can use, because a wavefront batch
holds at most `min(n1, n2)` pairs.

`4 * min(n1, n2)` is an upper bound on solve concurrency and nothing more: it
is NOT what binds this problem size. Measured through the refs a task holds,
fifteen slices reach 10.1x at thirty-two ranks and 9.7x at sixty-four, while
THIRTY slices -- which double the bound -- reach 8.5x at sixty-four rather than
more. The curve flattens near thirty-two ranks for a reason the bound does not
explain, and an earlier claim here that the slice count is the knob, drawn from
a contaminated benchmark, is WITHDRAWN. Attributing the flattening is the next
step, and the instrument exists: `_mp_collective_times` records per-kind wait
clocks that nothing has read for this route.

The tag change stands on the bound being the slice count in principle: the
batch's tags moved from the pair's index in the COLLIDE to its position in the
BATCH. A batch is a barrier, so positions are
all the separation tags need, and the old keying wanted `ns1 * ns2 * 16` tags
against the 32767 the MPI standard guarantees: it would have capped the slice
count near 45, the very number that has to grow.

Three constant factors went with it: the luminosity's extents now ride the
deposit wait and its mesh the payload wait (five barriers a batch down to
three); a field member evaluates straight out of the received payload instead
of copying it through a workspace; and the per-slice counts come from a
counts-only helper rather than `_divided_slice_plan`, whose `owns_reference`
cost two Allreduces per slice for a field spectral never reads.

### The lever that was not in the MPI code at all

A DST-I over `N` interior points has LOGICAL size `2(N + 1)`, and FFTW is fast
only when that is smooth. One thread, `RODFT00` on an `N x N` array: N=63
(logical 128) 39.2 us against N=64 (130) 67.5; N=127 (256) 166.7 against N=128
(258) 663.2; N=255 (512) 634.0 against N=256 (514 = 2*257) 5602.7. So
`grid=(256, 256)` costs 8.8x `grid=(255, 255)` for a mesh one point narrower,
and since `2(2^k + 1)` is twice a Fermat-ish number every power-of-two width is
one of the slow ones -- which is what a reader reaches for. The criterion is
the largest prime factor, not the power of two: N=48 (logical 98 = 2*7^2) beats
N=47 (96). `_spectral_note_grid_size` now records and warns, naming the nearby
smooth width, from 48 points up.

End to end on the same benchmark, moving the mesh one point from 64 to 63:
348 ms against 485 undivided, 57.5 against 68.9 at sixteen ranks, 39.7 against
47.4 at thirty-two. Against the pushed baseline's 227 ms at thirty-two ranks,
the two changes together are 5.7x.

### The review that found the rest

An adversarial pass over the change (five lenses, forty findings, each
refuted independently; eight survived) found what the author had not, mostly in
the TESTS rather than the code: every spectral fixture pinned
`luminosity_scale = 1.0`, which short-circuits the very function step 4g claims
to have fixed; the deny-by-default tripwire's refusing half was asserted
nowhere; every divided arm used a square mesh, so an `(Nx, Ny)` transposition
in a divided-only buffer was invisible; and `MPI-SPECVARWORK` asserted only the
cross-rank SUM, so it could not see the concentration its own comment claimed
to detect. All four now have arms, the last of them the pin that would have
caught the ceiling.

One of those new arms was itself vacuous on its first run -- it read
`_mp_nranks()` outside an execution scope, where the seam correctly reports a
single process, and so asserted `false == false` on all four ranks while
printing its receipt four times. The line count was the tell. That is recorded
in `experiences.md`.

---

## Step 4h, 2026-09-06: the dataflow loop, and two withdrawn measurements

The batched loop makes a wavefront batch a barrier: a rank waits at each stage
for the slowest member and idles when its own pairs are done. Nothing in the
physics asks for that, so `_spectral_collide_dataflow!` runs an event loop
instead -- scan this rank's pairs in the collision order, run every stage whose
receives have arrived, block on the union of what is outstanding only when a
whole scan ran nothing. It is PIC's step 4e applied to spectral's four stages,
and it takes PIC's gate (`_pic_df_predecessors`) unchanged: the hazard belongs
to the layout, not the solver.

Two things are spectral's own. Its tags must separate every pair of the
COLLIDE, where the batched loop separates only the pairs of a batch -- a batch
is a barrier, an event loop is not. And a pair whose luminosity mesh is
degenerate still KICKS and skips only its luminosity, because spectral's
verdict is about the mesh and arrives after the kick; PIC's is about the field
extents and arrives before, so PIC's loop skips the kick and its comment does
not transfer. The first draft copied that comment and the code with it, which
would have made the two loops different collides on a path no test reaches.

### Which loop, measured

Through the refs a task holds, arms INTERLEAVED in one process, 90,000
particles a beam, fifteen slices, a 63x63 mesh:

| ranks | widest group | batched | dataflow |
|---|---|---|---|
| 1 | 1 | **379.4 ms** | 387.7 |
| 2 | 1 | **286.1** | 304.1 |
| 4 | 1 | **179.0** | 191.9 |
| 8 | 1 | **100.0** | 113.7 |
| 16 | 2 | 69.6 | **55.6** |
| 32 | 2-3 | 38.2 | **37.4** |
| 64 | 4-5 | 40.8 | **39.0** |

Groups wider than one rank get the dataflow loop -- 25% at sixteen ranks, where
a slice first spans two -- and whole slices keep the batched one, which also
keeps its four independent solves a batch for the threads. That is the rule 4e
measured for PIC, arrived at independently here.

The two loops are two implementations of one collide, so the suite holds them
to the same BITS rather than the same answer: in process at one rank and under
the launcher at one, two and four, on every 6D arm. Nothing else would catch a
gate that let a pair read a slice before its predecessor kicked it, because the
answer would still look plausible.

### Two measurements withdrawn

Building this exposed that the step-4g rank scan was wrong twice over, and both
faults were the harness rather than the code.

It went through the bare `collide!`, which defaults its scratch, migration and
pool refs to fresh ones per call while a task holds them across turns. Every
collide therefore rebuilt every buffer it owns -- invisible at one rank, where
the collide's own work dominates, and decisive at sixty-four, where each rank's
share is small. It reported 209 ms at sixty-four ranks; the identical collide
measures 40.8 with the refs a task holds. And the arms ran whole-ladder-then-
whole-ladder on a box carrying other work, so at sixteen ranks the same
comparison came out "batched wins by 26%" that way and "dataflow wins by 25%"
interleaved.

What that cost: the claim that the curve TURNS UP past thirty-two ranks, and
the claim that the ceiling tracks the slice count. Neither survives. The clean
numbers flatten near thirty-two ranks (10.1x at 32, 9.7x at 64 with fifteen
slices), and doubling the slices to thirty gives 8.5x at sixty-four rather than
more -- so `4 * min(n1, n2)` is a real upper bound on solve concurrency but is
NOT what binds this size. What still stands is the ceiling evidence that never
had a clock in it: 20 of 32 and 23 of 64 ranks solving before the deal, 32 of
32 and 64 of 64 after.

Attributing the flattening is the next step, and the instrument is already
there and unread: `_mp_collective_times` keeps per-kind wait clocks. Both
lessons are in `experiences.md`.

### One migration exchange for both beams, and a deal that rotates

Two changes made after the attribution, both structural, both measured, and
neither of them moved the clock. That is the finding.

The migration used to run four all-to-alls a collide: beam 1 out, beam 2 out,
beam 1 back, beam 2 back. `_pic_sliced_migrate_pair_in` and
`_pic_sliced_migrate_pair_out!` do it in two. The packed column grows from
seven rows to eight -- six coordinates, the slice, and now the beam -- the two
beams' per-slice counts fold in ONE `_mp_allsum!` over an `(ns1 + ns2, P)`
matrix, and the receiver buckets by the composite key
`(beam - 1) * (maxns + 1) + slice` with a stable sort, which puts a rank's
particles in exactly the order the two separate exchanges left them in. Bit
for bit at one and four ranks. PIC, Gaussian-PIC and spectral all get it,
because all three ride this transport.

It bought nothing. 15.11 ms in the migration at sixteen ranks before, 14.80
after; 9.65 before at thirty-two, 9.76 after. Halving the message count from
4,096 to 2,048 per direction is a real change and the clock did not notice,
which refutes the reading that put it there. The same collide reports a
minimum migration wait of 1.09 ms and a maximum of 37.57 at sixteen ranks: the
exchange is not paying for messages, it is absorbing the spread in when ranks
arrive. Keep the change -- fewer messages is right on a bigger machine, and one
exchange is simpler than two -- but do not claim a speed-up for it.

The second change is a defect fix that also did not pay. `_spectral_sliced_solvers`
deals a pair's two field solves as `group[k % g + 1]` and `group[(k+1) % g + 1]`,
and `k` was the pair's index in the global pair order. The pairs sharing one
slice are scattered through that order, so stepping `k` by one between them is
not stepping the deal by one: over a group of four, a slice whose pairs sat at
global indices 3, 7, 11 hands all three to the same two members.
`_spectral_slice_pair_positions` numbers each pair by its position among the
pairs on its OWN slice, once per direction, and those are what the deal sees.
The solve spread at sixty-four ranks goes from 7-20 planes to 12-16 -- 2.9x
down to 1.33x. The wall: 41.2 ms against 39.5. Unchanged. So the imbalance was
real and was not what the collide was waiting on.

### Where the time actually is: the chain

Vary the slice count at sixty-four ranks and hold everything else:

| slices | batches | wall | per batch | compute in a batch |
|---|---|---|---|---|
| 8 | 15 | 27.1 ms | 1.81 ms | ~0.35 |
| 15 | 29 | 42.0 | 1.45 | ~0.37 |
| 30 | 59 | 225.6 | 3.82 | ~1.03 |

Going from fifteen slices to eight roughly halves the work each rank does. A
work-bound collide would have gone from 42.0 to about 21 ms; a chain-bound one,
paying per batch, to about 27. It measured 27.1. The per-batch cost is roughly
flat and roughly ten times the compute inside it -- three barriers and the skew
they absorb, paid `2 * nslices - 1` times, because the longitudinal map is
order-dependent and slice `i` cannot be a source until the pairs before it have
kicked it.

The luminosity was the last candidate for that per-batch cost and it is not it:
42.6 ms with the luminosity at sixty-four ranks against 37.1 without, 13% of
the wall and 0.19 ms of the 1.45 per batch.

So the sliced route is at its ceiling as specified. The chain length is the
physics; shortening it is a change to what the solver computes, not to how the
ranks are arranged. The levers still inside the contract are per-batch -- fewer
barriers in a batch, or overlapping a batch's sends with the next batch's local
work, and the dataflow loop already takes the second as far as its gates allow.
