# The Divided PIC Collide Made Fast — Step 4c, Performance Phase, 2026-09-05

Phase 1 of step 4c ([`multi_process_step4c_pic_2026_09_05.md`](multi_process_step4c_pic_2026_09_05.md))
divided the PIC collide correctly and left two things on the table, both
counted rather than guessed: every pair issued about twenty-four collectives,
six of them a whole padded charge plane (512 KB at grid 128) through an
all-sum whose volume grew with the rank count, and every pair ran alone on
the main thread because a collective sat inside it. The owner's direction for
this phase was to reuse what the soft-Gaussian and the CUDA PIC had already
learned: allocate the workspace once, batch the wavefront, carry both beams in
one exchange.

## What changed

1. **The all-sum moves `2n` per rank instead of `nP`.** Above 2048 elements
   the extension computes the seam's rank-ordered sum as a reduce-scatter --
   an `Alltoall` of `P` equal blocks, each rank folding the `P` blocks it
   received in rank order, then an `Allgather` of the folded blocks. Element
   by element that is the same sequence of additions the gather-and-fold
   performed, so the bits are the same; measured identical at every size and
   rank count tried (`n` from 1 to 65536 at 2, 4 and 8 ranks, identical on
   every rank). Per 512 KB plane: 6.31 -> 0.25 ms at 2 ranks, 5.78 -> 0.52 at
   4, 10.02 -> 0.88 at 8. Views of the staging arrays cross the seam, so the
   extension copies through cached vectors rather than handing MPI a raw
   buffer. The seam's byte receipts now count elements times element size.
   The first cut of the cache held its vectors as abstract `Vector`, and the
   fold dispatched per element: 42 ms per plane, the divided collide at two
   ranks 9.4 s against 2.5 s serial -- found in one run by the per-kind
   collective clocks the extension now keeps (`_mp_collective_times`, which
   the benchmark prints: 162 all-sums, 7.47 s, 78% of the wall) and fixed by
   a type assertion on the way out of the cache (0.16 ms per plane after,
   against 0.09 ms of MPI).
2. **One exchange per wavefront batch, for every pair and both directions,
   and every plane solved ONCE.** `src/tasks/strongstrong/pic_cpu_divided.jl`:
   a batch's pairs are conflict-free, so they reach each collective
   together. Stage A computes every pair's local mesh extents (the field's
   from `x + s*px` without writing it -- the in-place drift moves to the
   stage that kicks, the same two operations on the same two numbers); one
   all-max of the stacked `[-min; max]` values and one all-sum of the stacked
   `:sigma` sums, counts and non-finite flags follow. Stage B forms the grids
   and Green tables and deposits the nx x ny INTERIOR of every plane of both
   directions into slots of one staging array -- the padding of the FFT
   plane is zero on every rank and is not sent. A reduce-scatter by whole
   planes (`_mp_reduce_scatter_blocks!`: an Alltoall laid out so each rank
   receives whole planes, then the rank-ordered fold) hands each plane's
   partials to ONE rank, which solves it; an all-gather of the potentials
   (`_mp_allgather_blocks!`, nx x ny each, a quarter of the padded plane)
   gives every rank every plane, and stage C takes the gradient locally --
   every rank from the same numbers -- then drifts, kicks and forms the
   virtual positions. The luminosity takes one all-max of the overlap
   extents, a reduce-scatter of every pair's two deposits to an owner that
   forms the overlap sum, and an all-gather of those scalars. Seven
   collectives per batch (eight under `:sigma`) where the per-pair exchange
   issued about twenty-four per pair; the FFT work per rank divided by the
   rank count (900 planes per collide serial, 900/P divided); the traffic per
   rank about a third of the all-summed padded planes'. The staging (~40 MB
   at the production point) is allocated once per collide label and kept,
   like the workspace pool.
3. **The pairs of a batch run on the worker pool again.** No collective sits
   inside a pair any more, so the one-worker forcing applies only to the node
   mesh, which still runs the per-pair exchange.

The first cut of this phase all-summed the padded planes of a batch in one
message and left the solves redundant; measured, it did not scale at all --
2.48 s serial, 2.53 at two ranks, 2.31 at four, 2.85 at sixteen, 4.03 at
sixty-four -- because the redundant solves were most of the serial time and
the per-rank traffic (~1 GB per collide) did not fall with the rank count;
and at 30 MB a message moved fewer bytes per second than at 512 KB (the
per-pair schedule's 16-rank collectives cost 0.55 s per collide, the batched
one's 1.16 s). The owner-solve is what answers both.

The batched exchange runs for `interaction_grid = :slice_pair` under
`batch_mode = :wavefront`. `:node` keeps the per-pair exchange (its planes
come from prebuilt node meshes with a third, longitudinal plane -- a different
staging, not yet written); `:source_slice` never batches; `:sequential` IS the
per-pair exchange, kept as the batched one's bitwise reference.

## Bit for bit

The batched exchange re-associates nothing, and that is asserted rather than
argued. Before the change the launcher child's two-rank lines were saved;
after it, every result line -- the task's luminosity series and fingerprints,
the fifteen option arms and the 32768-particle threaded-deposit arm -- is
byte-identical (a sorted diff of 46 lines is empty). The child now also runs
a `:sequential` arm at both rank counts and the parent holds it to the
default's bits, so the equivalence is pinned on every gate, not only once.

## Measured

Instrument: `profiling/benchmark_collide_cpu.jl` with `OCTOPUS_BENCH_MPI=1
OCTOPUS_BENCH_SOLVER=pic`, taught this phase to run PIC divided. Fixed point:
640,000 electrons against 256,000 protons, 15 slices, grid 128, one thread per
rank, `-bind-to core`, `JULIA_THREAD_SLEEP_THRESHOLD=0`, median of three timed
collides after two warm ones. Box: 64 physical cores.

| ranks x threads | s/collide | speedup | in MPI calls (rank 0) | of which reduce-scatter / all-gather |
|---|---|---|---|---|
| 1 x 1 | 2.468 | 1.00x | -- | -- |
| 2 x 1 | 1.419 | 1.74x | 10% | 1.65 ms / 0.70 ms per call |
| 4 x 1 | 0.840 | 2.94x | 18% | 1.82 / 0.82 |
| 16 x 1 | 0.818 (0.733 on a second run) | 3.0-3.4x | 57% | 4.66 / 1.62 |
| 32 x 1 | 1.250 | 1.97x | 69% | 11.2 / 2.96 |
| 64 x 1 | 1.989 | 1.24x | 84% | 22.8 / 4.15 |
| 16 x 4 | 0.986 | 2.50x | 61% | 5.73 / 3.67 |
| 32 x 2 | 1.397 | 1.77x | 76% | -- |
| 8 x 8 | 1.120 | 2.20x | 52% | 5.96 / 3.20 |

Per collide the batched exchange issues 58 reduce-scatters, 58 all-gathers,
58 all-maxes, 32 all-min-maxes and 104 small all-sums (the slicing's and the
plan's), against ~5400 collectives on the per-pair exchange, which at the same
point runs 2.110 s at 16 ranks and 3.780 s at 64.

The shape of the curve is the decomposition's. Every rank holds a chunk of
every slice, so every rank must send its partial of every plane and receive
every plane's potential: about 115 MB out and 115 MB in per rank per collide
whatever the rank count, plus the luminosity deposits. At two ranks that is
nothing; at sixteen the Alltoall behind the reduce-scatter is 4.7 ms per
call and the collectives are half the wall; at sixty-four it is 23 ms per
call -- 64 ranks moving 8 MB each per call through shared memory -- and the
collectives are 84% of the wall. Threads inside a rank do not help (16 x 4
and 8 x 8 lose to 16 x 1): the particle work per rank is already small, and
the pool's overhead is paid on every stage of every batch. The all-gather
moves the same bytes three times cheaper than the Alltoall, so the
reduce-scatter is the lever if there is a next one; the other is overlap --
the luminosity's reduce-scatter and all-gather feed nothing downstream and
could run under the next batch's deposits.

At the production point (2,560,000 electrons against 1,024,000 protons, the
same 15 slices and grid 128, one thread per rank, cores bound, median of
three after two warm):

| ranks x 1 thread | s/collide | speedup | in MPI calls (rank 0) | reduce-scatter / all-gather per call |
|---|---|---|---|---|
| 1 | 6.267 | 1.00x | -- | -- |
| 16 | 1.068 | **5.87x** | 41% | 4.56 ms / 1.62 ms |
| 32 | 1.575 | 3.98x | 66% | 10.8 / 2.87 |
| 64 | 2.524 | 2.48x | 84% | 23.5 / 3.81 |

Four times the particles of the fixed point, the same planes: the particle
work divides and the traffic does not, so the curve peaks higher and at the
same rank count. The luminosity at 64 ranks agrees with the serial one to
3e-16 (1.0254361754701657e30 against 1.025436175470166e30). Serial, the
production collide is 6.27 s; the first division of this step ran it slower
than that at every rank count.

## What is left, in the order the numbers suggest

1. **Overlap.** The luminosity's reduce-scatter and all-gather feed nothing
   the next batch reads, so posted non-blocking they would run under the
   next batch's extents and deposits: at 64 ranks that is about a third of
   the collective time. Needs an asynchronous pair on the seam
   (`Ialltoall`/`Iallgather` with a wait before the overlap sums).
2. **The reduce-scatter's Alltoall**, three times dearer per byte than the
   all-gather on this MPICH; a pairwise or tree exchange written by hand may
   do better, and must keep the rank-ordered fold.
3. **The decomposition.** Past sixteen ranks the wall is the per-rank
   traffic, which a chunk-aligned shard cannot reduce: every rank holds
   members of every slice and needs every plane. A longitudinally aligned
   decomposition -- ranks owning whole slices -- would give each rank only
   its slices' planes, at the price of the chunk-aligned bit-identity and a
   re-partition every turn (the 4a design's "will not help" entry, revisited
   with the reason it would). An owner decision.
4. The node mesh's batched staging (three planes, prebuilt grids);
   Gaussian-PIC and spectral division; the campaign's neighbour audit when
   the last solver divides.
