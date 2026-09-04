# Rank Scaling of the Soft-Gaussian Collide — 2026-09-04

The strong-strong half of the campaign's motivating measurement, taken on the
tree that closed step 4a. Instrument: `profiling/benchmark_collide_cpu.jl`, the
fixed point that has measured this collide since the 2026-08-09 threading
campaign, taught here to run divided (`OCTOPUS_BENCH_MPI=1`).

Production point: 640,000 electrons against 256,000 protons, 15 slices,
`:normal_quantile` slicing with centroid centres, soft-Gaussian solver. Median
of two timed collides after two warm ones, the slowest rank quoted. Box: 64
physical cores, 128 hardware threads, `JULIA_THREAD_SLEEP_THRESHOLD=0`.
Baseline 3.4587 s per collide at one rank of one thread.

## Ranks, one thread each

| ranks | s/collide | speedup | efficiency | luminosity vs one rank |
|---|---|---|---|---|
| 1 | 3.4587 | 1.00x | 100% | reference |
| 2 | 1.7919 | 1.93x | 97% | 1.4e-16 |
| 4 | 0.9006 | 3.84x | 96% | 1.4e-16 |
| 8 | 0.6368 | 5.43x | 68% | 1.4e-16 |
| 16 | **0.2950** | **11.72x** | 73% | 0 |
| 32 | 0.5813 | 5.95x | 19% | 0 |
| 64 | 1.9065 | 1.81x | 3% | 2.7e-16 |

## Threads, one rank

| threads | s/collide | speedup |
|---|---|---|
| 1 | 3.4587 | 1.00x |
| 4 | 1.6061 | 2.15x |
| 16 | 2.5041 | 1.38x |

**This settles an open rider.** The ledger recorded a "gaussian collide
flatline": Phase 0 measured 2.42, 2.46 and 2.52 s at one, two and four ranks of
sixteen threads and could not explain why dividing the particles four ways
bought nothing. The thread axis above is the flatline, and it is real —
threading this solver caps at 2.15x and turns over by sixteen. The rank axis is
not flat at all. At sixteen ranks the collide is 11.72x faster than serial and
**5.4x faster than the best threaded configuration**. Phase 0 saw no rank
scaling because every rank was running sixteen threads, which put it past the
thread turnover before the rank axis could show anything.

## Why it turns over past sixteen ranks

Counted, not guessed. The collective seam records a receipt per call, so one
collide under an execution audit reports exactly what it issued:

| kind | calls | bytes |
|---|---|---|
| `allsum` | 1388 | 54,312 |
| `allminmax` | 452 | 7,232 |
| `lane_fold` | 34 | 1,114,112 |
| **total** | **1874** | **1.18 MB** |

Eighteen hundred and forty of those carry an average of 33 bytes. The collide
is not moving data; it is paying latency, 1874 times, and every floating-point
reduction is an Allgather followed by a fold in rank order, which costs O(P) in
both message volume and fold work. Per-collective cost therefore rises linearly
with the rank count while the compute per rank falls as 1/P, and the two cross
between sixteen and thirty-two ranks.

At one rank the same run issues ZERO collectives: the passthrough short-circuits
before any of them, which is what makes an undivided run cost exactly what it
did before this campaign.

The count breaks down per slice pair, of which there are 225: two global member
counts, two minimum-finds and two coordinate exchanges for the shift
references, and two packed moment sums. Six sums and two minimum-finds per
pair, or eight messages where two would do — the membership of a slice does not
change during a collide, so its global count and the identity of its
globally-first member are fixed for the whole loop and are being recomputed 225
times each. That is the optimization the numbers point at, and it is orthogonal
to the O(P) cost of an individual collective: fewer messages helps at every
rank count, a cheaper reduction tree helps most at large ones. Phase 0
anticipated both, recording that "the O(P) fold wants interleaving now and a
deterministic tree past ~16 ranks".

## Optimized, and re-measured

Two changes followed the diagnosis. Neither moves a number: the reduced-point
digest and the luminosity are identical before and after.

**A pool of one cannot run two things at once.** `_run_logical_workers` spawned
a task per chunk whatever the pool held, and the fixed grids are 16 and 64 wide
however many threads exist -- so at one thread a collide spawned about 57,600
tasks for no parallelism. It now runs the grid inline, in worker order, writing
the same disjoint slots, so the fold that follows is unchanged. One thread per
rank is the configuration that scales best here, which is why this mattered.

**The lane folds exchange a scalar, not 4096 lanes.** Exchanging lane partials
would preserve the fold's shape across processes, except that the shape is
already broken by the split within a lane: a rank's partial starts from zero
where the undivided accumulation would have carried in everything before it. So
it bought precision that was not there, at 4096 times the bytes.

Re-measured, same instrument, same point, five repeats, idle box:

| ranks | before | after | gain | speedup | spread before → after |
|---|---|---|---|---|---|
| 1 | 3.4552 | 3.3891 | 1.02x | 1.00x | 5% → 4% |
| 2 | 1.8703 | 1.7106 | 1.09x | 1.98x | 23% → 10% |
| 4 | 1.0227 | 0.9040 | 1.13x | 3.75x | 35% → 4% |
| 8 | 0.5978 | 0.4420 | 1.35x | 7.67x | 84% → 11% |
| 16 | 0.3786 | 0.2327 | 1.63x | 14.56x | 176% → 66% |
| 32 | 2.6897 | 0.1570 | **17.1x** | 21.59x | 130% → 34% |
| 64 | 0.6546 | 0.1028 | **6.4x** | **32.97x** | 1760% → 153% |

**The turnover is gone.** Scaling is monotone to sixty-four ranks at 32.97x,
52% efficient, and the luminosity still agrees to 4.1e-16. The run-to-run
spread collapsed with it, which is the same cause seen from the other side:
1874 synchronisation points per collide amplify any one rank's jitter, and a
collective that moves 8 bytes instead of 32 KB spends far less time exposed to
it.

Attribution is clean because the two changes act in different places. At one
rank there are no collectives at all, so the 2% there is the inline grid and
nothing else; everything beyond it is the lane folds. The counted traffic says
the same: the call count is unchanged at 1874, while the bytes fell from
1,175,656 to 61,816, a factor of 19.

**Still available, and not done.** The call count is untouched, and 1840 of
those calls carry an average of 33 bytes, costing a measured 30% of the
sixty-four-rank time.

The largest lever is the one the other solvers already use.
`collision_pair_batches` groups slice pairs that share no slice, and the
soft-Gaussian path is the only one still colliding strictly sequentially. Its
correctness argument is written down for PIC and applies here: batching
preserves each slice's own collision order, so a pair sees exactly the partner
state it saw sequentially, and the batched path reproduces the sequential
result bit for bit. The mode it does not hold for is the one whose mesh depends
on how much of the turn has been applied, and soft-Gaussian has no mesh. All
pairs within a batch are independent, so their reductions travel in one
message.

| stage | calls per collide |
|---|---|
| now | 1874 |
| hoist what is fixed for a collide (a slice's global count and its globally-first member, recomputed 225 times each) | ~970 |
| merge the two beams' messages per pair | ~520 |
| wavefront batching, about 29 batches | ~130 |

At sixty-four ranks that would take the collective term from 0.0298 s to about
0.0021 s and the collide from 0.1009 s to about 0.0731 s: 46x rather than 34x,
and more at higher rank counts, since the term it removes grows with P. It
should also shrink the run-to-run spread, which is jitter admitted through
1874 synchronisation points.

Two further levers, in order. A deterministic reduction tree would make each
message O(log P) instead of O(P), which the table above shows is worth about
3x per message at sixty-four ranks; Phase 0 asked for exactly this "past ~16
ranks". And non-blocking exchange of the next batch overlapped with the
current batch's kick is the "interleaving" Phase 0 also named, though after
batching there are only about 29 exchanges left for it to hide.

What will NOT help, and why, so it is not tried: a communicator per slice. The
shard is contiguous in particle index, so every rank holds members of every
slice and a per-slice reduction is still an all-ranks reduction. It would pay
only under a longitudinally aligned decomposition, where a slice lives on few
ranks -- and that conflicts with the chunk-aligned shard rule that buys the
bit-identical folds, and would need re-partitioning every turn as z evolves.

The floor is worth naming too. At sixty-four ranks each rank holds about 667
members per slice, so the work behind each message is small and the per-rank
inefficiency (18%) is already comparable to the communication. This problem
size runs out of parallelism not far past here, whatever the seam does.

## Where the remaining time goes, measured two ways

Two independent measurements, because a budget built from one is an estimate.

**The seam's own latency**, timed directly at each rank count on 2000 calls
after a warm-up, at the sizes one collide actually uses:

| ranks | one float | ten floats | min/max pair | the collide's 1874 calls |
|---|---|---|---|---|
| 2 | 1.4 us | 1.4 us | 1.3 us | 0.0026 s |
| 8 | 6.0 | 6.0 | 3.5 | 0.0102 |
| 16 | 8.6 | 8.9 | 4.2 | 0.0146 |
| 32 | 12.0 | 13.7 | 5.4 | 0.0219 |
| 64 | 18.6 | 22.6 | 7.1 | 0.0353 |

Per-message cost rises roughly linearly with the rank count, which is the
Allgather-plus-ordered-fold being O(P). Payload barely matters: ten floats cost
what one does, so this is latency and not bandwidth.

**The size scaling**, which separates the two terms without trusting the first
measurement at all. At a fixed 64 ranks the collective COUNT depends on the
slice count, not the particle count, so shrinking the beam shrinks compute and
leaves communication alone. Best of five repeats:

| beam | s/collide |
|---|---|
| 640,000 x 256,000 | 0.1009 |
| halved | 0.0647 |
| quartered | 0.0476 |

Fitting the full and quarter points gives compute 0.0711 s and a
size-independent 0.0298 s, and that fit predicts the half point at 0.0654
against 0.0647 measured, 1% out. The size-independent term agrees with the
0.0353 s timed directly.

So the budget at sixty-four ranks, on 0.1009 s:

| term | time | share |
|---|---|---|
| ideal compute (serial / 64) | 0.0530 s | 52% |
| per-rank inefficiency | 0.0181 s | 18% |
| collectives | 0.0298 s | 30% |

## The levers the budget points at

Two of the three terms have a named lever; the third is the floor.

**The 30% collectives are a CALL-COUNT problem, not a payload problem** — the
latency table above shows ten floats costing what one does. One collide issues
1874 calls. Hoisting what is fixed for a whole collide takes that to ~970,
sending the two beams' moments in one buffer instead of two to ~520, and
batching independent slice pairs with `collision_pair_batches` (~29 batches
instead of 225 pairs) to ~130. At the measured 18.6 us per message that is
0.0298 s falling to about 0.0024, and the collide to 0.0731 s — 46x rather than
34x, with the gain growing at higher rank counts because the per-message cost
grows with P.

Batching is safe here for the reason PIC already recorded: a batch preserves
each slice's OWN collision order, so the batched path reproduces the sequential
result bit for bit. PIC's one exception is a shared mesh, which the grid-free
soft-Gaussian does not have. The CPU soft-Gaussian is in fact the only collide
path in the tree still strictly sequential — the CUDA soft-Gaussian, PIC on
both backends, Gaussian-PIC and spectral all batch already.

**The 18% per-rank inefficiency is a WIDTH problem, and the two beams are the
lever** (owner-raised, 2026-09-04). Within a slice pair the two beams are
independent: the two moment reductions read different beams and neither reads
the other's result, and the two kicks write disjoint arrays from moments both
computed before either kick. Today they run one after the other, each over its
own 64-chunk grid. A shard's slice is small — at 15 slices and 64 ranks a rank
holds roughly a 960th of the beam per slice — so a 64-chunk grid over it is
thin and most of the per-worker cost is grid overhead. Issuing both beams as
one grid of 128 doubles the width exactly where it is thinnest, and the merged
moment buffer is the same edit that turns two all-sums into one. The
bit-identity constraint: each beam keeps its OWN luminosity accumulator and
each fold stays in chunk order. Widen the grid, never merge the folds. The CUDA
wavefront route is the existence proof that the shape works — it already
carries both beams in one array dimension, `2 * max_batch` columns.

**The switch is an existing keyword.** Owner constraint: reuse the public
option keywords, invent none. `GaussianPoissonSolver` already carries
`batch_mode` (`:sequential` or `:wavefront`, defaulting to `:wavefront`); only
its CPU method declines to read it. Landing this means the CPU method starts
honoring the field it already has, and the schema entry gains a CPU consumer
beside its CUDA one. It also forces a correction that is already owed:
`interface.jl` documents `batch_mode` as CUDA-only, "the CPU paths always use
collision-time order", and that is not true today — CPU PIC and CPU
Gaussian-PIC batch by their own `_pic_batchable` rule.

**The 52% is the floor** for this decomposition. Past it come a deterministic
reduction tree, worth roughly 3x per message at 64 ranks given how latency
grows from 1.4 to 18.6 us between 2 and 64 ranks, and non-blocking overlap. A
communicator per slice does NOT help: the shard is contiguous in particle
index, so every rank holds members of every slice. That would need a
longitudinally aligned decomposition, which conflicts with the chunk-aligned
bit-identity and would have to re-partition every turn.

## What was measured and what was not

Measured: the rank axis at one thread, the thread axis at one rank, and the
luminosity agreement at every point. Not measured: mixed rank-and-thread
configurations, which a first attempt confounded — binding each rank to a core
confines all of that rank's threads to it, so every cell with more than one
thread per rank was oversubscribed and the table said more about the binding
flag than about Octopus. The rank and thread axes above are unbound and
independent, which is what makes them comparable.

Not covered: the other three solvers. PIC, Gaussian-PIC and spectral still
refuse at more than one rank; they need per-slice-pair grid all-sums and global
mesh extrema, which are the later parts of step 4.
