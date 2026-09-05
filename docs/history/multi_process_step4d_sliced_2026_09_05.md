# The Slice-Aligned Collide — Step 4d, 2026-09-05

Step 4c's performance phase ([`multi_process_pic_scaling_2026_09_05.md`](multi_process_pic_scaling_2026_09_05.md))
ended on a wall: 5.9x at sixteen ranks at the production point and 2.5x at
sixty-four, the collectives 84% of the wall, because every rank held a chunk
of every slice and so every plane was a sum of `P` partials and every
potential had to reach `P` ranks. The owner lifted the constraint that made
that layout necessary -- the collide need not be bit-identical across rank
counts, it must agree with the serial result in the parity class -- and this
step lays the particles out by slice for the collide. Design, with the
adversarial review that shaped it, in
[`../design/multi_process_policy.md`](../design/multi_process_policy.md)
("Step 4d").

## What was built

`src/tasks/strongstrong/pic_cpu_sliced.jl`, which a multi-process policy
runs on the `:slice_pair` mesh at every rank count:

1. **The layout.** Live particles of each beam sorted by slice and cut
   slice-aligned: whole slices to ranks when `P <= nslices`, a proportional
   group of ranks per slice when `P > nslices`, never a rank holding parts
   of two slices. Derived on every rank from the plan's global counts.
2. **The migration.** One all-to-all of columns in (six coordinates and the
   slice index) and one back, no index travelling: the home rank remembers
   the destination sort it applied and the slice rank the bucketing by
   slice, and each inverts its own. Dead particles stay home. The collide
   never writes `z`, so `z` returning to its home slot bit for bit is the
   migration's own check, printed per rank by the launcher child.
3. **The pair**, point-to-point between two small groups: records of
   extents to a coordinator (the first rank of the source group), the
   reduced record to the two direction owners (dealt round-robin over all
   ranks from the pair's position in its batch), the final grids -- after
   the owner's slice-pair Green cache has had its say -- to the members,
   partial interiors to the owners, potentials to the field members, who
   take the gradient and kick; then the luminosity's extrema, mesh and
   deposits through the coordinator. Eight hops per batch, none of them
   collective; the seam gained `_mp_exchange_columns`, `_mp_isend`,
   `_mp_irecv!` and a stage-named `_mp_wait_all`, with self-delivery in the
   passthrough so the same code runs at one rank.
4. **What stays collective**, per collide: the slicing and the plan on the
   home layout, the two migrations, one all-sum of the pair luminosity
   vector, the dropped count, and one count of non-finite flags so every
   rank throws or none.

The 4c batched exchange (`pic_cpu_divided.jl`) and its two block
collectives are retired; `:node` and `:source_slice` keep the 4c per-pair
paths.

## What the one-rank pin found

At one rank the sliced collide must be the CPU collide bit for bit, and the
in-process check holds it to that on fourteen option arms. Thirteen were,
first time; `:sigma` was off by 4e-4. The `:sigma` estimator is shifted
about the slice's first member -- as that member IS at the pair, kicked by
the pairs before it -- and the first cut exchanged the origins once at the
collide's start. They are exchanged before every batch now (one small hop
under `:sigma` only). The lesson is recorded in the experiences ledger: an
origin is a moving particle.

## Measured

Instrument and protocol as in the 4c record (`profiling/benchmark_collide_cpu.jl`,
`OCTOPUS_BENCH_MPI=1 OCTOPUS_BENCH_SOLVER=pic`, one thread per rank unless
stated, cores bound, median of three timed collides after two warm, the
slowest rank quoted; the extension's clocks now name every wait by stage).

**The launcher fixture** (256/192 particles, 3 slices, grid 16, the
seventeen option arms of the child) at 2 and 4 ranks against the one-rank
run, which is the CPU's bit for bit: at most 6.0e-15 relative on the option
arms and 8.8e-14 on the 64-slice `:sparse` arm (4c's numbers, as the design
predicted); `z` back in its home slot on every rank at every rank count;
`:sequential` equal to `:wavefront` bit for bit at 1, 2 and 4 ranks; the
`:skewed` arm (its middle slice split over two ranks at four) the same bits
twice. **The contract** at 1, 2, 4 and 8 ranks: bitwise at one; 5.8e-17
absolute on the coordinates, 0.12 of the 1e-11 pointwise allowance, 1.9e-15
relative on the luminosity, the same class at every rank count.

**The fixed point** (640k/256k, 15 slices, grid 128):

| ranks x threads | s/collide (step 4d) | step 4c | speedup |
|---|---|---|---|
| 1 x 1 | 2.613 | 2.468 | 1.0x |
| 2 x 1 | 1.944 | 1.419 | 1.3x |
| 4 x 1 | 0.918 | 0.840 | 2.8x |
| 16 x 1 | 0.472 | 0.733-0.818 | 5.5x |
| 32 x 1 | 0.762 | 1.250 | 3.4x |
| 64 x 1 | 1.015 | 1.989 | 2.6x |
| 32 x 2 | 0.520 | 1.397 | 5.0x |
| 16 x 4 | 0.665 | 0.986 | 3.9x |

**The production point** (2.56M/1.024M):

| ranks x 1 thread | s/collide (step 4d) | step 4c | speedup |
|---|---|---|---|
| 1 | 6.713 | 6.267 | 1.0x |
| 16 | 3.116 (1.501 on its best collide) | 1.068 | 2.2x |
| 32 | 0.885 | 1.575 | **7.6x** |
| 64 | 0.900 | 2.524 | 7.5x |

The sixteen-rank point re-measured with five timed collides, `-bind-to
core` against `-bind-to socket -map-by socket` (ranks spread over the
sockets rather than filling one), per collide in order:

| binding, ranks x threads | collides (s) | median | best |
|---|---|---|---|
| core, 16 x 1 | 4.17, 1.74, 1.66, 1.16, 1.18 | 1.66 | 1.16 |
| socket, 16 x 1 | 3.97, 1.91, 0.76, 0.72, 1.13 | 1.13 | 0.72 |
| socket, 16 x 4 | 1.20, 1.37, 2.02, 1.16, 0.98 | 1.23 | 0.98 |
| socket, 32 x 2 | 4.73, 1.49, 1.35, 1.03, 1.43 | 1.43 | 1.03 |

Two things to read there. Spread over the sockets, sixteen ranks reach
0.72 s -- better than 4c's 1.07 -- and the median 1.13 is level with it; the
first measurement's 3.1 s was a slow-collide median. And in every
configuration the collides get faster over the run (2.6, 2.0, 2.1, 1.1 s on
one sixteen-rank run with four timed collides): two warm collides are not
enough for this path. The Green cache is NOT it -- read from the task's own
cache after each collide (`OCTOPUS_BENCH_CACHE_STATS=1`, which now enters
the task's diagnostics scope, without which the collide's own cache print
never fires: the 3c lesson met by this instrument a second time), rank 0
hits 42 of 42 owned tables on every collide after the first. What the run
does show is 0.149 GiB allocated per rank per collide, the first paying
0.36 s of GC: the migration's four matrices, the sort permutations, the
per-batch pair records and the exchange primitive's own send and receive
matrices are fresh every collide, and a heap that grows over the first
collides is the shape of the trend. That is the third lever below, and the
open item is closed into it. The medians above include the slow collides.

The curve no longer turns over: 32 and 64 ranks are the best points, at
7.6x, where 4c's best was 5.9x at sixteen. The clocks say what bounds it
now. At 64 ranks 72% of rank 0's wall is waiting, mostly `wait_reduced`
(5.5 ms per batch, the owners waiting for the coordinator's fold) and the
end-of-collide all-sums (1.2 ms per call: the skew the wavefront's tail
leaves, when the last batches occupy few ranks); the migration is 45 ms per
call. At sixteen ranks -- one slice per rank -- the run is SLOWER than 4c's
(1.5-3.1 s against 1.07), because a batch's critical path there is one whole
slice's deposits and kicks on one rank while its peers wait (`wait_deposits`
8.7 ms, `wait_potentials` 12.9 ms, `wait_reduced` 11.2 ms per batch), and
the wavefront's duty cycle leaves half the ranks idle on the average batch.
That floor is the schedule's, not the layout's: the reviewer's "hops per
batch" note priced the latency at ~0.5 ms a batch and it is indeed not the
lever; the lever is letting a rank start its next pair when its own inputs
are ready rather than when the batch's slowest member is (dataflow across
batches), which the point-to-point form was built to allow.

## What is left, in the order the numbers suggest

1. **Dataflow across batches.** A rank in batch `b + 1` needs only its own
   pairs' messages, so the batch barrier can go: post the next batch's
   records as soon as this rank's slices are kicked, and let the
   coordinators and owners serve pairs as their inputs arrive. At `P ~
   nslices` that doubles the throughput (the duty cycle) and removes the
   16-rank regression; at 64 ranks it removes the `wait_reduced` and the
   tail skew.
2. **Threads inside a rank where a rank holds a whole slice.** The deposit's
   threaded path is gated at 160 particles per cell (2.6M at grid 128), so a
   170k-particle slice deposits serially; the kick threads. `32 x 2` already
   beats `32 x 1` (0.52 against 0.76 at the fixed point); a data-size rule
   for the deposit that admits a 170k slice would do the same for `16 x 4`.
3. **The allocations** (0.149 GiB per rank per collide at the production
   point: the migration's matrices and permutations, the exchange primitive's
   own send and receive matrices, the per-batch pair records): cache them,
   which is also what the warm-up trend asks for.
4. Gaussian-PIC and spectral on the sliced layout; the node mesh on it; the
   campaign's neighbour audit when the last solver divides.
