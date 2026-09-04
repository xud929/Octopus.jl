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
