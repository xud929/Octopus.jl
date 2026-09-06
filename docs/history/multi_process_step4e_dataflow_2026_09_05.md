# Dataflow Across Batches — Step 4e, 2026-09-05

Step 4d's slice-aligned collide ran its pairs in wavefront batches, every
rank walking the same eight stages together. Its clocks said what that cost
([`multi_process_step4d_sliced_2026_09_05.md`](multi_process_step4d_sliced_2026_09_05.md)):
at sixteen ranks, one slice per rank, a batch's critical path was one whole
slice's deposits and kicks on one rank while its peers waited, and at
sixty-four 72% of the wall was waiting -- mostly owners on coordinators, and
the skew of the wavefront's tail. Nothing in the physics asked for the
barrier: a pair depends only on its two slices' previous pairs. This step
replaces the batch loop with a per-rank event loop. Design, and the
adversarial review that shaped it, in
[`../design/multi_process_policy.md`](../design/multi_process_policy.md)
("Step 4e").

## What was built

`_pic_collide_dataflow!` in `src/tasks/strongstrong/pic_cpu_sliced.jl`. Each
rank scans its pairs in the collision order and runs every stage whose
receives have arrived and whose gate is open, relay duties first; when a whole
scan runs nothing it blocks on the union of what is outstanding. Three rules
carry it:

- **The gate is the collision order**, read from `order` and never computed
  from indices. The collision time is `-(c1 + c2)/2` ascending, so with
  ascending slice centres the pair before `(i, j)` on slice `i` is
  `(i, j + 1)`; the review found the design's `(i, j - 1)` and it would have
  gated every pair on one that had not run.
- **A buffer belongs to its send** until MPI says the send completed. The
  batched loop's per-stage wait covered that; nothing else does, and a plane
  reused early corrupts a peer's charge silently. A pair returns its buffers
  to the free lists only once its send list tests complete.
- **A pair that meets a non-finite extent releases its slices** without
  kicking, so its successors run and the collide reaches the count that makes
  every rank throw. A bad pair that simply stopped would hang its slices.

The `:sigma` origins moved into per-pair buffers under two codes inside the
pair's tag space: their own band collided with the pair band a few hundred
pairs in (the review's blocker), and a slice-keyed tag leaned on MPI's
non-overtaking rule besides. The collide now checks its largest tag against
the communicator's limit. The seam gained `_mp_test_all` and `_mp_wait_any`
(with self-delivery at one rank, so the same loop runs there), and a
tag-bound check.

**Two loops, one set of leaves.** The arithmetic of both loops now lives in
shared functions -- a direction's deposits, an owner's fold-and-solve of one
plane, a field part's gradient-drift-kick, the luminosity's fold and overlap
-- so the loops differ only in when they run them. `batch_mode = :sequential`
keeps the 4d batched loop and is the permanent cross-loop pin.

## Bit for bit, against the loop it replaces

The strongest statement available, and it was taken directly: the launcher
child's every result line on the 4d commit (d677931) against the same child
on this tree, at 1, 2 and 4 ranks -- the task's luminosity series and
fingerprints, all eighteen option arms, the per-rank luminosity lines, the
dropped counts, the threaded-deposit arm. **Zero differing lines** at every
rank count. The fixed-point benchmark's one-rank coordinate digest is
0xc8af3cf19999b79c on both trees.

The permanent pins: `:sequential` (batched loop, owners dealt from width-1
batches) equals the default (dataflow loop, owners dealt from the wavefront)
bit for bit at 1, 2 and 4 ranks; the `:skewed` and `:sparse` arms each run
twice in the child and must give the same bits, so an arrival order cannot
move a number; every arm names the loop it ran, so a fallback to the batched
loop cannot pass as the dataflow one.

The overlap is real and counted rather than assumed. On the child's fixture
(three slices, nine pairs, five batches per turn):

| ranks | pairs started while an earlier batch was still in flight | widest set of batches in flight |
|---|---|---|
| 1 | 8 | 5 |
| 2 | 16 | 10 |
| 4 | 28 | 18 |

## Measured

Both loops exist, so the honest measurement is an A/B of the two on the same
box at the same moment -- the machine is shared and its load average ran 15
to 24 during these runs, and the run-to-run spread is larger than the effect.
An internal switch (`_PIC_SLICED_LOOP`, a scoped value, not a solver keyword)
forces either loop; the benchmark exposes it as `OCTOPUS_BENCH_PIC_LOOP`, and
the arms alternate at each rank count so a busy stretch hits both.

Production point (2,560,000 electrons against 1,024,000 protons, 15 slices,
grid 128, one thread per rank, cores bound), six timed collides after two
warm, rank 0's wall per collide in order:

| ranks | loop | s per collide, in order | best | median |
|---|---|---|---|---|
| 16 | dataflow | 2.06, 2.04, 1.96, 1.79, 1.98, 2.05 | 1.79 | 1.98 |
| 16 | batched | 3.38, 1.23, 1.50, 2.19, 0.84, 0.83 | 0.83 | 1.24 |
| 32 | dataflow | 1.01, 1.05, 1.69, 1.33, 0.60, 0.57 | 0.57 | 1.01 |
| 32 | batched | 1.61, 1.24, 1.12, 1.00, 0.58, 0.59 | 0.58 | 1.00 |
| 64 | dataflow | 3.30, 1.11, 0.66, 0.53, 0.76, 0.40 | 0.40 | 0.66 |
| 64 | batched | 4.43, 1.78, 0.74, 0.77, 0.55, 0.89 | 0.55 | 0.77 |

(The second round of each; the first round agrees on the direction at every
rank count.) The dataflow loop is **1.4x faster at sixty-four ranks**, a tie
at thirty-two, and **2x SLOWER at sixteen**.

**Corrected the same day.** These numbers carry 0.149 GiB per rank per
collide of garbage, which was fixed immediately afterwards
([`multi_process_pic_allocations_2026_09_05.md`](multi_process_pic_allocations_2026_09_05.md));
a good part of what reads here as a scheduling penalty was GC. Re-measured
with the buffers pooled, the two loops are much closer -- medians 0.55-0.66
against 0.63-0.99 at thirty-two ranks, 0.46-0.88 against 0.48-0.94 at
sixty-four, 0.91-0.94 against 0.85-0.95 at sixteen, and best-of-six a tie
above sixteen. The rule below is unchanged and its direction still holds;
its margin is a few percent to a quarter, not 1.4x and 2x.

The clocks say why, and the reason is the gate rather than the loop. A pair
may not start until each of its slices has been kicked by the pair before it,
so the pairs on one slice are strictly a chain. At sixteen ranks over fifteen
slices a rank holds a WHOLE slice: its fifteen pairs on that slice are that
chain, there is nothing to overlap, and the dataflow loop only adds a wake
per hop -- rank 0 blocked 5.70 s of its 11.89 s wall, against 1.4 s under the
batched loop, and the ranks were all equally slow (1.79 to 2.06) where the
batched loop's spread was 0.83 to 3.38. Once a slice spans a group the
picture inverts: each rank holds a fraction of the chain's work and owns
planes of pairs it is not a member of, so there is independent work between
the hops. The waits the step set out to remove did go -- at sixteen ranks the
batched loop spends 0.84 s in `wait_potentials` and 0.53 s in
`wait_deposits`, the dataflow loop 0.02 s and 0.38 s -- but at that layout
the time reappears as idle in the chain.

So the loop is chosen by the layout, and the rule is the measurement:
**groups wider than one rank run the dataflow loop, whole slices per rank the
batched one.** `batch_mode = :sequential` always runs the batched loop.

## What is left

1. ~~The warm-up~~ **done the same day**
   ([`multi_process_pic_allocations_2026_09_05.md`](multi_process_pic_allocations_2026_09_05.md)):
   an allocation profile named three sites in one run -- the one-rank
   passthrough copying every send, the virtual positions rebuilt per pair,
   the migration rebuilding its scratch -- and pooling all three took the
   collide from 0.149 GiB per rank per collide to 0.004-0.013 GiB and
   removed the warm-up entirely.
2. **The chain itself**, which binds at `P ~ nslices`: fifteen pairs in
   series per slice, each a deposit, a solve and a kick. More slices would
   lengthen it; splitting a slice's pairs across the ranks of its group --
   different pairs of the same slice to different ranks, rather than every
   rank a fraction of every pair -- would shorten it, at the cost of a
   second migration per turn.
3. **Threading inside a rank that holds a whole slice**: the deposit's
   threaded path needs 160 particles per cell (2.6M at grid 128), so a
   170k-particle slice deposits on one thread while the kick threads.
4. Gaussian-PIC and spectral on the sliced layout; the node mesh on it; the
   campaign's neighbour audit when the last solver divides.
