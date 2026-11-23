# The multi-process migration leaked one exchange matrix per turn (2026-11-23)

Found from a production failure, measured by reproduction, fixed in one function, guarded by one
receipt. Frozen record; the scripts behind it are `validation/multi_process_memory/` and the
probes under the git-ignored `result/oom_repro/`.

## 1. The failure

The owner's strong-strong scan on NERSC Perlmutter (1296 jobs, each one 512 GB CPU node, 64 MPI
ranks x 2 Julia threads, `--gcthreads=1`, 100,000 turns of a 9 GeV electron / 275 GeV proton
collision: `MultiProcessExecutionPolicy`, PIC 128 x 128 with 15 x 15 slices, crab cavities,
chromaticity, lumped radiation, an every-turn `MomentObserver` per beam, a file `RunArtifact` with
`capacity = 1000`, 2,560,000 and 1,024,000 macroparticles). Slurm: `Detected 1 oom_kill event`,
task 0 killed after 8862 s. The artifact held 4000 flushed turns, `execution/elapsed` 3728 s at
turn 3999 (0.93 s/turn), so the kill fell between turns 4000 and 4999; the last 4900 s of the job
produced no flushed turn, the node thrashing before the kill.

## 2. The reproduction

`validation/multi_process_memory/repro_exchange_leak.jl` is the scan script with the macroparticle
counts and turns from the environment, run under MPICH's `mpiexec` on acnlinj4 (128 cores, 503 GB)
at the Perlmutter per-rank load of 40,000 electrons and 16,000 protons per rank, 300 turns, VmRSS
of every rank sampled every 10 s, Julia's GC log on rank 0 where noted. The runs, in the order they
were made (sizes are per rank unless said):

| run | ranks | Julia flags | what it showed |
|---|---|---|---|
| A | 8 | as submitted | RSS 1.86 GB -> 3.38 GB over the 300 turns, +5.2 MiB per turn per rank, linear, no plateau |
| B | 8 | `--heap-size-hint=1500M` | the same peak (27.1 GB total against A's 27.2), 1143 s instead of 523 |
| C | 8 | `--heap-size-hint=800M` | still growing, slower per turn |
| D | 8 | GC log | heap after FULL collections 365 -> 1706 MB on rank 0; `gc_live_bytes` 1.56-1.86 GB per rank at the end |
| E | 1 | GC log | 2.7-3.2 GB, fluctuating, no growth |
| F | 2 | GC log | 2.1 -> 4.3 GB per rank, +7.5 MiB per turn per rank |
| G, H | 1 | glibc `MALLOC_MMAP_THRESHOLD_=131072 MALLOC_TRIM_THRESHOLD_=131072` / `MALLOC_ARENA_MAX=1` | plateaus like E |
| I | 2 | reports the extension's caches | `_MP_EXCHANGE_BUFFERS`: 530 entries, 1587 MiB per rank; keys `(:recv, Float64, 8, 52249)`, `(8, 52252)`, `(8, 52265)`, ... |

Read together: the growth is retained Julia memory (B equals A; D's live heap rises after every
full collection), it needs more than one rank (E flat, F and A growing), it is not the allocator
(G, H), and run I names the object. Ruled out by reading first: the slice-pair Green cache (keyed
by pair and direction, at most 450 entries), the CPU workspace pool and the dataflow plane pool
(high-water marks, buffers returned on retire), the migration scratch (cursor arenas), the run
artifact (1.9 MB), MPI requests (finalised).

## 3. The defect

`ext/OctopusMPIExt.jl`, `_mp_exchange_buffer(role, E, k, n)`: the send and receive matrices of
`_mp_exchange_columns_impl` (step 4d's migration, `pic_cpu_sliced.jl`) were cached in a global
`Dict` keyed by `(role, E, k, n)`. `n` is the number of columns exchanged: the particles changing
slice or rank this turn on the way in (8 rows: six coordinates, slice, beam) and the same particles
on the way out (6 rows), and the receive side's total. Both change every turn, so every turn added
one or two matrices of `8 x n x 8` bytes that nothing ever released. The cache was introduced to
stop fresh 9 MB matrices four times per collide from being most of a rank's 0.149 GiB per collide
(step 4d's record); its docstring assumed "between the turns of a run their shapes repeat", which
is true of the plane and record buffers of the same file and false of this one.

Rate: at 8 ranks 5.2 MiB per turn per rank; at 2 ranks 7.5 (more pairs and more particles per
rank migrate). On the Perlmutter node, 64 ranks starting near 1.9 GB each had about 390 GB to grow
into; the kill after 4000 to 4999 turns puts the rate there at about 1.3 MiB per turn per rank.

## 4. The fix and its guard

One buffer per `(role, E, k)`, a `Vector{E}` grown to the high-water mark of `k * n`, handed out as
the contiguous view of its first `k * n` elements: the send side as the flat view the `Alltoallv`
reads, the receive side reshaped to `k x total` for the caller. The contract "done with the
receive matrix before the next exchange of the same role" is unchanged; both callers consume the
returned matrix before the next exchange. Performance is unchanged in kind: the matrices were
already reused whenever a count repeated, and `MPI.VBuffer` takes the contiguous view directly.

Guard: `test/mpi_seam_check.jl` runs forty exchanges with forty different column counts inside
the policy scope at 1, 2 and 4 ranks, checks every delivery against the documented layout (sender
rank order, the sender's column order, every value), and prints `MPI-XCHG ... buffers_before
buffers_after bytes allsum_buffers`; the launcher testset asserts at most two new entries per
rank and bounds the all-sum cache (measured 1 entry here) at 64. Unfixed, the receipt read
`buffers_before=0 buffers_after=80 bytes=372000` on both ranks.

After the fix, the same runs. Child receipts: `buffers_after=2 bytes=15864` on both ranks at two
ranks, `buffers_after=2 bytes=15888` or `15936` on all four at four ranks, `allsum_buffers=1`,
exit 0 with every delivery check passed. Reproduction I (2 ranks, 300 turns): the cache holds
4 entries and 12.4 MiB per rank (send and receive for 8 and for 6 rows) against 530 entries and
1587 MiB; rank 0's peak RSS 2445 MiB against 4311; the ranks' total RSS 4.72 GB at turn 30 and
4.74 GB at the end against 4.3 -> 8.3 GB. Reproduction D (8 ranks, 300 turns): 4 entries and
12.4 MiB per rank; rank 0's peak RSS 2026 MiB against 3275; total RSS 16.2 GB at every sample from
turn 30 on against 15.0 -> 26.3 GB. The moments of both beams (28 columns x 300 turns) and the
300-turn luminosity series of both fixed runs are bitwise identical to the unfixed baselines
(`validation/multi_process_memory/compare_fingerprint.py`): the exchange delivers the same columns in the
same order, only without keeping the old ones.

## 5. What was learned

A cache keyed by a quantity that changes every turn is a leak with a long fuse, and only a long
run shows it: the suite's two- and four-rank children run a few turns and were green throughout.
The diagnosis that found it is cheap to repeat and is now a harness: the resident memory of every
rank over a few hundred turns, a heap-hint A/B to separate garbage from retention, a one-rank
control to separate the multi-process path from the rest, and a report of every process-lifetime
cache at exit. `docs/experiences.md` carries the lesson.

## 6. Gate

The two-arm full gate at CI settings ran on this commit's tree (459004f) before the push:

| arm | command | start to end (EST) | exit | summaries | failures |
|---|---|---|---|---|---|
| native (sapphirerapids, CUDA active) | `julia --project=. --threads=4 -e 'using Pkg; Pkg.test(julia_args=["--threads=4"])'` | 2026-11-23 09:17:03 to 10:43:51 | 0 | 465 | 0 |
| AVX2 CI parity (`OPENBLAS_CORETYPE=Haswell julia -C haswell`, test process `-C haswell`) | the same `Pkg.test` with `"-C", "haswell"` | 2026-11-23 10:43:51 to 12:22:43 | 0 | 465 | 0 |

Both arms ran the launcher testset "The multi-process seam runs under an MPI launcher" at one,
two and four ranks with the new `MPI-XCHG` assertions (native: 1766 of 1766 in 12m51s; AVX2:
1766 of 1766 in 14m38s). Logs: `result/gates/mpifix/full_gate_{native,avx2}.log` (git-ignored). The three
commits pushed together with this record's -- `e2a6fa0`, `498af00` (the BBSCL comparison and its
addendum) and `459004f` (the fix) -- are all covered by this gate, which ran on the tree they add
up to.
