# Rank Scaling of a Tracking Task — 2026-09-04

The measurement the multi-process campaign exists for, taken on the tree that
closed step 3a. Instrument: `profiling/benchmark_track_cpu.jl`, the fixed
point that has measured this workload since 2026-08-19, taught here to run
divided (`OCTOPUS_BENCH_MPI=1`) so rank scaling and thread scaling come from
one script rather than two whose physics literals would drift apart.

Production point: 1,024,000 macroparticles GLOBAL, the crab-crossing line with
a 7-slice Gaussian strong beam, radiation excitation on. Two windows of ten
turns after a two-turn warm-up, median per window, and the number quoted is
the SLOWEST rank's, because that is the turn's wall time. Box: 64 physical
cores, 128 hardware threads, `JULIA_THREAD_SLEEP_THRESHOLD=0` throughout.
Baseline: 2.0869 s/turn at one rank, one thread.

## Ranks against threads, unbound

| ranks x threads | s/turn | speedup | parallel efficiency |
|---|---|---|---|
| 1 x 1 | 2.0869 | 1.0x | 100% |
| 1 x 8 | 0.2771 | 7.5x | 94% |
| 1 x 16 | 0.1966 | 10.6x | 66% |
| 2 x 16 | 0.1201 | 17.4x | 54% |
| 4 x 8 | 0.1109 | 18.8x | 59% |
| 16 x 2 | 0.1127 | 18.5x | 58% |
| 1 x 64 | 0.0874 | 23.9x | 37% |
| 2 x 32 | 0.0858 | 24.3x | 38% |
| 4 x 16 | 0.0716 | 29.1x | 46% |
| 8 x 8 | 0.0662 | 31.5x | 49% |
| 16 x 4 | 0.0621 | 33.6x | 53% |
| 32 x 2 | 0.0630 | 33.1x | 52% |
| 64 x 1 | 0.0453 | 46.1x | 72% |

**Processes beat threads, by 1.9x at the same width.** At 64-way parallelism,
64 ranks of one thread is 0.0453 s/turn against 0.0874 for one rank of 64
threads. At 32-way the split barely matters (0.111 to 0.120 across every
division), so the divergence is entirely in what threads do past about 16 per
process -- which is where Phase 0 put the per-process optimum, and which the
2026-08-09 campaign established as memory-bandwidth bound. Ranks do not share
that ceiling because they do not share the memory system's view of one heap.

## Binding, and the hardware threads

| ranks x threads | binding | slowest rank | spread over ranks | speedup |
|---|---|---|---|---|
| 64 x 2 | none | 0.0337 | 35% | **61.9x** |
| 64 x 2 | core | 0.0342 | **5%** | 61.0x |
| 64 x 2 | socket | 0.0352 | 38% | 59.3x |
| 64 x 1 | core | 0.0435 | 2% | 48.0x |
| 64 x 1 | socket | 0.0441 | 4% | 47.3x |
| 64 x 1 | none | 0.0451 | 6% | 46.3x |
| 32 x 2 | core | 0.0660 | 1% | 31.6x |
| 32 x 4 | core | 0.0695 | 5% | 30.0x |
| 64 x 2 | hwthread | 0.0775 | 12% | 26.9x |
| 16 x 4 | core | 0.1150 | 4% | 18.1x |

**Best measured: 64 ranks x 2 threads, 0.0337 s/turn, 61.9x.** That uses all
128 hardware threads, and it is 2.6x better than the best single-process
configuration.

**Binding is worth about 4% here, not the 17-22% Phase 0 measured for
strong-strong PIC.** The difference is the workload: PIC ranks share grids and
their locality decides where the field solve reads from, while tracking ranks
share nothing at all. What binding does buy at every point is PREDICTABILITY:
at 64 x 2 it cuts the spread between the fastest and slowest rank from 35% to
5% at the same speed, and the slowest rank is what a turn costs. For a
production run that is the configuration to use, because an unbound run's
turn time is a draw from a wide distribution.

`-bind-to hwthread` is a trap and is recorded so nobody repeats it: it pins
each rank to ONE hardware thread while the rank runs two Julia threads, so
every rank oversubscribes. 2.3x slower than the same shape unbound.

## What the numbers say about the design

- **Per-turn communication is nil.** A tracking task with no diagnostics
  issues exactly one collective per `execute!`, an integer all-sum of the
  ranks' particle counts used to derive the shard, and none per turn. That is
  why rank scaling stays near-linear where thread scaling does not, and it is
  a property of the workload rather than of any tuning: per-particle maps need
  no communication to be divided.
- **The rank count is capped at 64 by the shard rule**, which requires the
  count to divide `_REDUCTION_CHUNKS`. A 128-rank launch was attempted and
  correctly refused, naming the counts that do divide. On this box the cap
  does not bind, because 64 x 2 already occupies every hardware thread; on a
  larger node it would, and lifting it would mean either changing the chunk
  count -- which moves every recorded number -- or giving up the bitwise
  cross-rank identity. Neither is worth it for a single-node campaign.
- **Memory is about 1.6 GB per rank** at this point, of which the beam is a
  small part; the rest is the Julia runtime and compiled code, paid once per
  rank. Sixty-four ranks is therefore roughly 100 GB on a 503 GB box.
- **Startup dominates a short run**: about 34 s wall for a 22-turn job, most
  of it per-rank load and compilation. It does not enter s/turn, but it sets
  the shortest run for which dividing is worth anything.

## No code change followed

This is a measurement record, not an optimization record: the sweep found
nothing in the multi-process path to optimize. Communication is already zero
per turn, the shards are exactly equal, and the remaining gap to linear
scaling is the single-process thread behaviour the 2026-08-09 campaign already
attributed to memory bandwidth. The actionable output is a launch
configuration, which is now in `docs/current_runtime.md`, and the driver that
reproduces the table.
