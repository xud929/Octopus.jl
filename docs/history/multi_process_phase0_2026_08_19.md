# Multi-Process Execution Policy, Phase 0 — 2026-08-19

Owner-directed: open a campaign for a MIXED execution policy — P processes,
each with T CPU threads — for strong-strong and tracking tasks, and answer
"Distributed or MPI or something else?" before designing anything. This record
is the measure-before-designing phase (the `experiences.md` rule): the missing
weak-strong thread-scaling curve, an on-box MPI cost prototype at the
production point, the transport decision with its measured justification, and
two environment traps that Phase 1 must resolve deliberately.

**Scope decision (owner, 2026-08-19): SINGLE NODE.** No multi-node cluster is
a deployment target. That bounds the feature's value at the on-box numbers
below (~1.9–2.2x for PIC) and removes every fabric concern from Phase 1; the
multi-GPU/rank-per-GPU door stays listed but is not being built.

## Starting point, from the record

- The 2026-08-09 CPU-threading campaign closed at PIC 41.0 -> 3.0 s/collide
  (13.7x) with the wall ceiling MEASURED as memory bandwidth (three ways:
  slice-count widening, NUMA binding, a cache-resident positive control), and
  GC established as a red herring FOR THAT PATH after the allocation fixes
  (43.78 -> 0.26 GiB per collide warm). Optimum at ~16 threads: the pair pool
  caps at the slice count (15) and the memory system saturates past ~16.
- The weak-strong tracking path had NO thread-scaling measurement at all.
- GPU reference (solver matrix, 2026-08-08): PIC 0.331 s/turn f64 on the
  RTX 4500 Ada — the on-box speed to beat is the GPU's, not the CPU's.

## Instruments

- `profiling/benchmark_track_cpu.jl` (new): weak-strong `TrackingTask` turns,
  crab-crossing production case, no observer/artifact; median s/turn over 3
  windows of 20 turns after a 2-turn warm-up; bitwise coordinate digest,
  comparable across thread counts.
- `profiling/mpi_collide_prototype.jl` (new): the strong-strong cost model.
  Per rank: the task-path warm `collide!` of `benchmark_collide_cpu.jl` on
  beams of size N/P, plus one production turn's deterministic collective
  pattern — 450 x (Allgather one 128x128 Float64 grid + fold the P partials
  in rank order; the fold is bit-identical on every rank by construction).
  Additive rather than interleaved (slightly pessimistic). Identical beams
  per rank, not shards: same arithmetic and traffic, no physics meaning.
  Reported number: MAX over ranks — the slowest rank sets the turn.
- Launcher: MPICH_jll's hydra `mpiexec -bind-to socket` (why MPICH_jll and
  not the intended system Open MPI: the traps below). Verified bindings:
  rank r alternates sockets (`0-31,64-95` / `32-63,96-127`); at P > 2 ranks
  share a socket's whole mask, so per-rank core sets are enforced only at
  socket granularity. `JULIA_THREAD_SLEEP_THRESHOLD=0` throughout. Machine
  idle (load < 1). Every arm's repeats agreed bitwise within rank.

## Part A — weak-strong TrackingTask thread scaling (first measurement)

Production point, 1,024,000 macroparticles, median s/turn; digest
`0xbb09efa9e44e2017` after 62 turns, IDENTICAL at every thread count
(worker-count invariance holds on this path):

| threads | s/turn | speedup | GC share | util | alloc |
|---|---|---|---|---|---|
| 1  | 2.2249 | 1.00x | 3.2%  | 99.9% | 1.282 GiB/turn |
| 4  | 0.7688 | 2.89x | 12.5% | 82.4% | 1.282 |
| 8  | 0.4348 | 5.12x | 19.3% | 76.8% | 1.282 |
| 16 | 0.4004 | 5.56x | 30.8% | 66.4% | 1.282 |
| 32 | 0.6588 | 3.38x | 42.9% | 50.9% | 1.282 |
| 64 | 0.6975 | 3.19x | 52.2% | 43.4% | 1.282 |

**The weak-strong path is allocation/GC-bound, unlike post-campaign
strong-strong.** 1.282 GiB allocated per turn — 1.25 KB per particle per
turn, deterministic across thread counts — with GC share climbing
monotonically to half of wall, and the 32/64-thread REGRESSION tracks it.
This is the pre-fix-1 disease: the tracking/element loops never received the
extraction treatment that took the strong-strong collide from 43.78 to
0.26 GiB. The owner's original instinct ("the multi-thread policy is limited
by GC") is CORRECT for this path, and was a red herring only for the one the
campaign already fixed. Consequence: the weak-strong allocation extraction is
step 1 of this campaign — a single-process fix that also multiplies any
later multi-process gain (every rank inherits it).

## Part B — the on-box MPI P x T matrix (production point, total split /P)

Turn cost = collide + 450-collective comm phase, max over ranks, median of 3.
All arms socket-bound except the first; s/collide-equivalent.

PIC (grid solver — the bandwidth-bound case):

| config | turn cost | collide | comm | vs 1x16 bound | vs 1x16 unbound |
|---|---|---|---|---|---|
| 1x16 unbound | 2.572 | 2.566 | 0.006 | — | 1.00x |
| 1x16 socket  | 2.143 | 2.139 | 0.004 | 1.00x | 1.20x |
| 2x16 socket  | 1.581 | 1.521 | 0.103 | 1.36x | 1.63x |
| 4x16 socket  | 1.358 | 1.218 | 0.209 | 1.58x | 1.89x |
| **8x8 socket** | **1.151** | 0.883 | 0.351 | **1.86x** | **2.23x** |
| 2x32 socket  | 1.985 | 1.904 | 0.122 | 1.08x | 1.30x |

Soft-Gaussian (compute-bound):

| config | turn cost | collide | comm |
|---|---|---|---|
| 1x16 unbound | 3.116 | 3.101 | 0.016 |
| 1x16 socket  | 2.437 | 2.421 | 0.016 |
| 2x16 socket  | 2.544 | 2.458 | 0.647 |
| 4x16 socket  | 2.817 | 2.518 | 0.365 |
| 8x8 socket   | 1.650 | 1.228 | 0.544 |

Cross-check: the 1x16 unbound PIC arm (2.57) reproduces the recorded warm
production figure (2.17, `nightly-warm` row) within machine-state variance —
both are the same task-path instrument, and both sit far from the 41 s
pre-campaign baseline, so the instrument is sound.

### Findings

1. **Processes pay on one box, more than the bandwidth ceiling alone
   predicts: PIC 8x8 is 1.86x over socket-bound 1x16, 2.23x over today's
   unbound practice.** The production PIC collide sequence reads 41.0 (2026-08
   start) -> 2.6 (threading campaign) -> 1.15 s (this prototype). Mechanism is
   the SUM of NUMA-local traffic, smaller per-rank working sets (the
   campaign's cache-residency positive control, now arriving as a benefit),
   and per-rank independent GC. The Phase 0 stop-gate ("< 1.3x on-box means
   don't build it") is cleared.
2. **Socket binding alone is 17–22% for free** (PIC 2.572 -> 2.143,
   gaussian 3.116 -> 2.437) with zero code. Worth adopting for any CPU
   production run today; a user-facing note belongs with Phase 1's docs.
3. **The 16-thread optimum is per-process, not just cross-socket traffic:**
   2 ranks x 32 threads, each rank alone on its socket with all memory local,
   still loses to 2 x 16 (1.99 vs 1.58). Wide flat pools cost even at perfect
   locality; the mixed policy's sweet spot on this box is many small ranks
   (8x8 > 4x16 > 2x16).
4. **The deterministic collective costs O(P) by construction** (rank-ordered
   fold): 0.10 / 0.21 / 0.35 s per turn at 2/4/8 ranks — 30% of the 8x8 turn,
   measured additively. The real implementation must interleave it with
   compute, and past ~16 ranks the fold wants a deterministic tree. On-node
   at P <= 8 it is affordable as-is.
5. **Open question — the soft-Gaussian arms are odd twice.** (a) Its collide
   barely moves from 1x16 to 2x16 to 4x16 (2.42 / 2.46 / 2.52) despite
   halving and quartering the per-rank particle count, then drops 2x at 8x8:
   something per-pair and particle-count-independent dominates it at 16
   threads. (b) Its comm phase reads 3–6x PIC's for IDENTICAL comm code
   (0.65 vs 0.10 s at 2x16) — suspected idle-thread spin
   (`JULIA_THREAD_SLEEP_THRESHOLD=0`) competing with the serial fold, but not
   probed. Neither blocks the campaign; both go to the todo row.
6. **Perspective the feature must be sold under:** the best CPU number here
   (1.15 s/turn) is still 3.5x the single GPU's 0.331 s/turn. On this box the
   feature is for CPU-bound production — GPU busy, f64 verification arms,
   parameter scans on cores — not a route past the GPU.

## Transport decision: MPI.jl, and Distributed does not come back

MPI (as a weakdep extension, core never importing it) was recommended over
`Distributed` for the collective pattern, the SPMD topology, and the
launcher-provided binding; single-node scope removes MPI's fabric/SLURM
advantages, but the measurement closes the case the other way: the collective
pattern already costs 0.10–0.35 s/turn over MPI shared memory, 10–30% of the
turn it buys. `Distributed`'s per-message overhead (TCP + serialization,
hand-rolled fan-in/fan-out through a master) on 450 collectives/turn would
multiply that several-fold and eat most of a 2x gain. Verified working here:
4 ranks x 4 threads under `MPI.Init(threadlevel = :funneled)`, Allgather +
rank-ordered fold bit-identical across ranks by digest, 151–172 us per
131 KB collective (MPICH 4.1.1 system, Open MPI 5.0.10 bb env, and MPICH_jll
all in the same class on-node).

## The two environment traps (Phase 1 design inputs, both measured)

1. **HDF5_jll variant flip.** With MPIPreferences preferences visible in the
   Julia load path, HDF5_jll resolves its platform to an MPI variant — the
   failure is `Artifact "HDF5" was not found` from
   `wrappers/x86_64-linux-gnu-...-mpi+openmpi.jl` — and Octopus (whose HDF5
   must stay the serial jll) fails to load. Octopus must be loaded before any
   environment carrying MPIPreferences enters the load path.
2. **Load-order lock.** HDF5.jl itself depends on MPIPreferences, so loading
   Octopus first loads MPIPreferences with its MPICH_jll DEFAULT — after
   which no `use_system_binary()` preference is ever read: MPI.jl runs
   MPICH_jll no matter what was configured. Under a PMIx launcher (the bb
   Open MPI's prterun) MPICH aborts with "unsupported PMI version PMIx"; under
   MPICH's own hydra everything works. Net: in one process, with Octopus's
   HDF5 unpinned, the system Open MPI is UNREACHABLE — the prototype
   therefore ran MPICH_jll + hydra, which is immaterial for on-box timing.
   An MPI-enabled Octopus environment must resolve this deliberately: either
   the matching MPI HDF5_jll variant installed at instantiate time (risking
   two MPI runtimes in-process), or serial HDF5 pinned via Preferences, or
   MPICH_jll accepted as the single-node transport. Phase 1 decides with a
   test, not an argument.

## Verdict and decided order

Proceed, single-node scope, reusing the tuned per-rank core unchanged (the
new policy COMPOSES `CPUThreadsExecutionPolicy` per rank; 1-rank MPI must
reproduce today's digests bit-for-bit):

1. **Weak-strong allocation extraction** (single-process; the fix-1/fix-9
   pattern applied to the tracking path; target the 1.282 GiB/turn and the
   30.8% GC share at the 16-thread optimum).
2. **Policy type + collective seam** (~6 functions: nranks/myrank, grid
   all-sum, lane-fold, bcast, barrier; serial passthrough in core, MPI in an
   extension; full ConfigurationOptionMeta schema with receipts that record
   the rank count read FROM THE COMMUNICATOR at execution).
3. **Weak-strong MPI** (task-level seams only: scheduled moment/luminosity
   reductions, loud cross-rank loss counts, rank-0 artifact writes).
4. **Strong-strong, solver by solver** (soft-Gaussian first — slicing-moment
   seam only, no grids — then PIC's deposit->solve all-sum, then gpic,
   spectral). Determinism posture: fixed-P bit-repeatability and thread-count
   invariance digest-pinned as today; cross-P at the CPU/CUDA parity
   tolerance class, with lane-aligned sharding where the `_SLICE_FOLD_LANES`
   machinery already makes process-count bit-invariance cheap.

Raw sweep logs lived in the session scratchpad and are reproducible from the
two committed instruments and the protocol above; the numbers in this report
are the durable record.
