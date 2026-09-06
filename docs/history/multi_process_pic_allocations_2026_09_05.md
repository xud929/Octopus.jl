# The Sliced Collide Stops Rebuilding Its Buffers — 2026-09-05

Step 4e left one item at the top of its list: the divided PIC collide
allocated 0.149 GiB per rank per collide at the production point, and its
first two timed collides ran two to four times the later ones -- in BOTH of
its loops, so it was not the schedule. The Green cache had already been
ruled out by reading the task's own counters (rank 0 hit 42 of 42 owned
tables on every collide after the first). This is the heap, and it is fixed.

## What the profile said

One allocation profile of the collide (`Profile.Allocs`, 2% sampling, one
rank, both loops) named the whole of it in a single run. Of 560 MiB per
collide:

| MiB | site | what |
|---|---|---|
| 250-290 | `_mp_isend_impl` (passthrough) | every send COPIED its buffer at one rank |
| 86-94 | `_pic_sliced_virtual!` | the virtual positions, rebuilt per pair per direction |
| 122-171 | `_pic_sliced_migrate_in` | the migration's columns, permutations and slice states, rebuilt per collide |

## The three fixes

1. **The one-rank passthrough holds the sent buffer by reference.** The
   seam's contract already says a send's buffer stays untouched until the
   send completes, and both loops honour it -- the batched one waits per
   stage, the dataflow one tests its send list before returning a buffer to
   its pool. Copying bought nothing and cost the whole protocol.
2. **The virtual positions come from a free list**, like the planes: one per
   direction per pair, returned when the pair retires.
3. **The migration keeps its scratch** in the run's cache, one set per beam:
   the packed columns, the destination and home indices, both sort
   permutations, the received-column bucketing, and the per-slice coordinate
   vectors, all resized in place. The home index no longer travels through a
   permuted copy either -- the return trip indexes `home[order[k]]`.

## Measured

Per rank per collide at the production point (2,560,000 against 1,024,000,
15 slices, grid 128, one thread per rank, cores bound), six timed collides:

| | allocation per collide | first collide | last collide |
|---|---|---|---|
| before, 16 ranks | 0.149 GiB | 2.11 s | 0.74 s |
| after, 16 ranks | **0.009-0.013 GiB** | 0.98 s | 0.90 s |
| after, 64 ranks | **0.004-0.009 GiB** | 0.44 s | 0.45 s |

The warm-up is gone: the first timed collide is now within noise of the
last, where it had been two to four times slower. In the one-rank profile
the collide fell from 559 MiB to 88 MiB, and what remains there is the Green
cache rebuilding as that probe's beams evolve -- pre-existing behaviour of
the slice-pair cache, absent when the grids are stable.

## What it did to the schedule question

Step 4e chose between its two loops by measurement, and the measurement was
taken with this garbage in it. Re-run afterwards -- the same interleaved A/B,
three rounds, both loops alternating at each rank count -- the picture is
much closer, because a good part of what looked like a scheduling penalty
was GC:

| ranks | dataflow, median of 6 (3 rounds) | batched, median of 6 (3 rounds) |
|---|---|---|
| 16 | 0.94, 0.91, 0.94 | 0.88, 0.95, 0.85 |
| 32 | 0.66, 0.55, 0.63 | 0.99, 0.85, 0.63 |
| 64 | 0.88, 0.46, 0.62 | 0.48, 0.94, 0.85 |

Best-of-six is a tie at 32 and 64 ranks (0.54 against 0.54, 0.35 against
0.35) and favours the batched loop at 16 (0.80 against 0.88). The medians --
the statistic that includes the rank skew a real run meets every turn --
still favour the dataflow loop where a slice spans a group (25% at 32 ranks,
13% at 64) and the batched loop where a rank holds whole slices (5% at 16).
So **the layout rule stands, on a margin of a few percent to a quarter
rather than the 1.4x and 2x measured before**; 4e's record carries the
correction.

## What is left

The chain itself at `P ~ nslices` (fifteen pairs in series per slice), the
deposit's threading rule (a whole slice deposits on one thread), and then
Gaussian-PIC and spectral on the sliced layout.
