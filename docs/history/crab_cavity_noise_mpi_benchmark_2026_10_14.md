# Crab cavity noise under the MPI execution policy, and the cross-backend benchmark (2026-10-14)

Status: in progress 2026-10-14. The follow-up batch to the crab cavity noise
campaign ([`crab_cavity_noise_validation_2026_10_14.md`](crab_cavity_noise_validation_2026_10_14.md),
closed and pushed as 20bbfaa, CI run 449 green): the example and its harness
gained the multi-process arm, the harness the per-turn timing instrument,
and the repository a benchmark driver that runs the harness once per
execution policy and compares the outputs. The arm landed on the branch
`crab-noise-example` on top of 371b2df (uncommitted at the time of
writing); the divided-run reproduction facts of section 2 and the dry run
of section 3 are measured; the production benchmark of section 4 ran on
2026-10-14 (sixteen arms); the two-arm full gate ran green on the batch's commit f858107
(section 5). Every verdict
carries its number here; a `result/` path is not evidence and none is cited
as one.

## 1 What landed

- `examples/crab_cavity_noise.jl`: `config.execution` gains `:multiprocess`,
  MPI ranks x CPU threads through
  `MultiProcessExecutionPolicy(threads = config.threads, ranks = config.ranks)`,
  beside `:auto`, `:cuda` and `:threads`; `config.ranks` (`:auto`, or an
  integer the policy asserts against the communicator) is read by
  `:multiprocess` alone and refused under any other choice, where it would
  go unread. The arm needs the file run in PACKAGE mode under a launcher,
  `mpiexec -n 4 julia --project=. -e 'using Octopus, MPI; include("examples/crab_cavity_noise.jl")'`,
  because `MultiProcessExecutionPolicy` reaches a communicator only through
  the `OctopusMPIExt` package extension and an extension attaches to a
  package, not to the `include` of `src/Octopus.jl` at the top of the file;
  the script asserts the extension by name
  (`Base.get_extension(Main.Octopus, :OctopusMPIExt)`) and errors with the
  command rather than letting `mpiexec -n 4` run four whole simulations
  racing on one artifact path with exit 0 and plausible timings. This
  process's rank comes from the `:multi_process_communicator` receipt the
  run recorded at activation (`nranks`, `rank`, `resolved_by`, `threads`),
  not from `_mp_rank()`, which reads the policy in force and answers 0 on
  every rank once `execute!` has closed its scope (`docs/experiences.md`,
  "A collective outside its scope is a silent no-op"); a run under the
  policy that recorded no such receipt is an error. Rank 0 alone holds the
  artifact (the library gates the file) and prints the readback -- the
  receipt, the provenance, the luminosity mean, the emittances -- and every
  other rank prints one line naming itself. The `policy = policy` note now
  says why the keyword is fatal rather than cosmetic under `:multiprocess`:
  an inferred default is a single-process policy, so every rank would track
  the whole beam and write the same path.
- `test/examples/crab_cavity_noise.jl`: four switches brought over from the
  weak-strong harness with its semantics (until this batch the file refused
  them by name). `OCTOPUS_USE_MPI` is read BEFORE Octopus is loaded, because
  it decides how: `using Octopus; using MPI` and
  `MPI.Init(threadlevel = :funneled)` when it is on, the usual `include`
  otherwise; an already-`include`d `Main.Octopus`, whose `PkgId` carries no
  UUID, is refused with the cause, since Julia 1.12's own error there names
  only the conflict. `OCTOPUS_RANKS` (`auto`, or the count the communicator
  must match) passes straight through as the policy's `ranks`.
  `OCTOPUS_RECORD_TURN_TIMES` is the task's own `record_turn_times`, read
  back with `turn_timings(task)`; every rank prints its own series.
  `OCTOPUS_TURN_TIMING_PATH` writes a TSV with the header `turn`, `seconds`,
  `max_over_ranks_seconds` -- turn 1..T, rank 0's own clock of the turn, and
  the maximum over the ranks, which is the turn's wall time (equal to
  `seconds` at one rank) -- from rank 0 only; a relative path resolves
  against the repository root, never into `OCTOPUS_RESULT_DIR`, because the
  suite asserts rank 0's result directory holds exactly one file. The
  per-rank series is reduced to the per-turn maximum with one
  `MPI.Allreduce(series, max, MPI.COMM_WORLD)` the harness issues itself,
  outside Octopus's scope (section 6, the friction row). The `CRAB-NOISE`
  line gains `ranks=` (the communicator size the run RECORDED in its
  receipt, 1 single-process; the harness errors if it differs from
  `MPI.Comm_size(MPI.COMM_WORLD)`), `threads=` (the per-process worker count
  the policy resolved, read from `configuration_report(policy)` and checked
  against the receipt's `threads`; `NA` on CUDA) and `steady_ms_per_turn=`
  (1000 times the median over turns 21..T of `max_over_ranks_seconds`; `NA`
  without the instrument or with T <= 20, and said so). `ms_per_turn=`
  stays the JIT-polluted whole-run figure it was, an upper bound. Refused by
  name, each where it would go unread or would select nothing: `OCTOPUS_MP`
  (the retired spelling the frozen 2026-09-06 record names), `OCTOPUS_RANKS`
  without `OCTOPUS_USE_MPI=1`, `OCTOPUS_TURN_TIMING_PATH` without
  `OCTOPUS_RECORD_TURN_TIMES=1`, and `OCTOPUS_USE_GPU=1` together with
  `OCTOPUS_USE_MPI=1` (the multi-process policy composes the CPU policy and
  is CPU storage only). Rank 0 prints the readback and the summary line,
  built as ONE string (`docs/experiences.md`, "Two ranks printing at the
  same moment merge mid-line"); the other ranks end with one line each.
- The suite: "The developer harnesses run divided under an MPI launcher"
  classifies every `.jl` under `test/examples/` by the exact text of the
  switch line (reads it, or refuses it by name) and launches each reader at
  `-n 2` with `OCTOPUS_RANKS=2`, `OCTOPUS_CPU_THREADS=2`, one turn, 4096
  macroparticles, into a result directory of its own. The crab harness moved
  from the refusing class to the reading class, so the testset now launches
  three harnesses: 10 assertions (one classification test per harness, the
  population floor, and exit 0 plus the one-artifact check per launched
  harness) where there were 8; `test/runtests.jl` itself is unchanged. The
  example-runner testset runs the harness with the switch off, as before.
- `profiling/crab_cavity_noise_backends.jl`, the driver. It runs the harness
  once per arm as a subprocess and answers "how fast is each backend" and
  "do the backends agree" in one table. Its conventions: a FIXED CASE owned
  by the harness, to which the driver passes only switches (white at scale
  1, `OCTOPUS_RADIATION=0` so the crab noise is the only stochastic drive,
  seed 123456789, moments every turn; `n_macro` 1e5 and 1e6 and 2000 turns
  by default; `harness=weak_strong` substitutes
  `test/examples/weak_strong_tracking.jl`, the same case without the noise
  and with radiation on, which carried the switches first and was the
  dry-run target); arms `threads:<T>`, `mpi:<R>x<T>` and `cuda`, one at a
  time in the order given, sizes ascending, the child inheriting the
  environment with every `OCTOPUS_*` variable removed first; the launcher is
  `MPI.mpiexec()` of the `MPI.jl` in the project's load path (MPICH_jll
  5.0.1), never a system `mpiexec`, so the children load the same `libmpi`;
  `load=package` (the default) starts every child as
  `julia -e 'using Octopus; include(<harness>)'` so the three arms'
  whole-process walls are comparable (the harness's own `include` compiles
  Octopus from source in every non-MPI run, about 170 s on the 128-core
  node, while its MPI branch must load the package: 176 s against 27 s
  around a 2 s run, measured 2026-10-14), `load=include` runs the harness as
  it documents, and the TSV records the mode; a STEADY WINDOW, turns
  `skip + 1 .. T` (skip 20), with the median, 10th and 90th percentile of
  the per-turn wall time read from the timing file and never a differenced
  whole-run wall
  ([`weak_strong_rerun_instrumented_2026_09_07.md`](weak_strong_rerun_instrumented_2026_09_07.md));
  under MPI the `seconds` column is rank 0's clock and the max-rank column
  the turn's wall, and the driver rejects an arm whose max-rank median
  disagrees with the harness's own `steady_ms_per_turn`; the whole-process
  wall, the 1-minute load average at launch and at exit, and for the CUDA
  arm `nvidia-smi` utilisation and memory before and after; the OUTPUT read
  back from the artifact with HDF5.jl, not from the printout -- the rms
  emittances at the last moment row (checked against the `CRAB-NOISE` line
  bit for bit), the luminosity mean, and SHA-256 DIGESTS over the raw
  `Float64` bytes of `/moments/<name>/data`,
  `/luminosity/strong_beam_1/turns` and `/values`, whole and per block
  (`digest_lum`, `digest_moments`), so output identity is one string
  comparison; a comparison table per (N, turns) with ms/turn, the speed-up
  against the baseline arm (`threads:16` by default), the walls, the loads,
  the digests and the identity verdict ("bitwise identical", else whether
  the luminosity series and the moments block are each bitwise, the worst
  moment column scaled to its maximum, and the maximum relative difference
  of the two emittances and the luminosity mean); one 34-column TSV row per
  arm, appended as arms finish and resumable on
  `(harness, arm, n_macro, turns, moment_step)`, a failed arm (non-zero
  exit, the 7200 s timeout, a missing artifact or timing file) writing no
  row; and `moment_step=<n>` (crab only, `OCTOPUS_MOMENT_STEP`, asserted
  through the artifact's moment row count) to take the every-turn observer
  and artifact row out of the per-turn cost.

## 2 The divided run against the undivided one

What the arm promises, from the design
(`docs/design/multi_process_policy.md`, "The CPU, MPI and CUDA consistency
statement", the three-execution-modes table): CPU threads against MPI
TRACKING is bitwise at every rank count that divides the chunks; the scalar
diagnostics agree to the accumulation difference between one serial sum and
P of them, 1.7e-14 at two ranks and 8.7e-14 at four as measured there. The
turn-modulation rules add nothing to divide: they are stateless functions
of the absolute turn, realised identically on every rank's host, and each
particle's counter-RNG streams key on its GLOBAL slot, so a divided run
applies the same noise to the same particles as the undivided one.

Measured 2026-10-14 on the harness, CPU only, 200 turns, 20000
macroparticles, the white, table and none rules, at 1, 2 and 4 ranks with 4
threads per process, each divided run against the single-process run of the
same tree and seed:

- The luminosity series is BITWISE identical at 2 and at 4 ranks, every
  turn. So are all final particle coordinates, every particle. The
  `/turn_modulation` provenance (stream ids, table digests, names, lengths)
  is identical.
- The moments table is NOT bitwise: it differs from row 1 (turn 0), column
  `m100000`, on. The worst column is `m000010`, the longitudinal centroid,
  near zero, at 1.0e-12 to 1.5e-12 scaled to the column's own maximum --
  inside the bound of the masked global sum, eps N = 2.2e-16 x 20000 =
  4.4e-12. The rms emittances from the central second moments agree to
  about 3e-15 relative.
- Thread count alone (one process, another `OCTOPUS_CPU_THREADS`) is bitwise
  in every quantity, the moments included: the worker-count invariance of
  the fixed chunk grid.

The mechanism, which is by design and not a defect: each rank reduces its
own shard in the serial left-to-right order and the P partial sums fold in
rank order (`_masked_global_sum`, `src/policies/Policies.jl`, whose
docstring records the trade: folding on the fixed chunk grid would have made
a divided beam's moments bitwise the undivided beam's, and it broke "a lost
particle is excluded from every reduction, exactly", so the masking
invariant won and cross-rank agreement is priced at the accumulation
difference; `docs/experiences.md`, "The attractive uniformity is sometimes
the wrong one"). A centroid column scaled to its own near-zero maximum reads
larger than the design note's 1e-14 figures, which were taken on second
moments at the production size; both sit inside eps N. The luminosity holds
because the collide folds its per-turn sum on the fixed chunk grid in chunk
order, the same order divided or not.

Refusals, each exercised: `OCTOPUS_RANKS` not matching the launcher's count
(the policy's "requests are matched exactly, never adjusted");
`OCTOPUS_USE_MPI=1` in script mode with Octopus already `include`d (the
extension attaches to a package only); `OCTOPUS_MP`; `OCTOPUS_RANKS` without
`OCTOPUS_USE_MPI=1`; `OCTOPUS_TURN_TIMING_PATH` without
`OCTOPUS_RECORD_TURN_TIMES=1`; `OCTOPUS_USE_GPU=1` with `OCTOPUS_USE_MPI=1`.
The launcher throughout was MPI.jl's configured binary, MPICH_jll 5.0.1
through `MPI.mpiexec()`, not the system `mpiexec`.

Throughput at this small point -- steady ms per turn, the median over turns
21..200 of the slowest rank's clock, 20000 macroparticles, 4 threads per
process: 51 at 1 rank, 35 at 2 ranks, 20 at 4 ranks.

## 3 The dry run, and where the CPU per-turn cost sits

The driver's dry run used the weak-strong harness (`harness=weak_strong`:
the same case without the noise, radiation on), N = 1e5, 500 turns, steady
window turns 21-500, on the shared 128-core node with other users' work on
it (the 1-minute load average between 0.6 and 10 across the arms):

| arm | steady ms/turn, median | speed-up vs threads:16 | identity vs threads:16 |
|---|---|---|---|
| threads:16 (baseline) | 117.6 [p10 113.7, p90 121.0] | 1.00x | - |
| threads:8 | 118.1 | 1.00x | bitwise identical, the whole output |
| mpi:4x4 | 72.8 | 1.61x | luminosity series bitwise; emittances to 1.15e-14 |
| cuda | 3.08 | 38x | emittances and luminosity to 7.9e-15 |

Two readings. First, the same threads:16 arm read 147.9 ms/turn in another
run at a different load, a 26 % swing from the host's mood alone, which is
why every TSV row carries the load average at launch and at exit and why
the production run repeats its baseline (section 4); a speed-up quoted
without its loads is not a number. Second, the CPU per-turn cost is not the
tracking: `profiling/benchmark_track_cpu.jl`, which runs the same fixed
point with no observer and no artifact, gives 23.1 ms/turn at N = 1e5 and
16 threads against the harness's 117.6 on the same node (the loads differ,
so the split is approximate): about 80 % of the harness's turn is outside
the tracking, in the every-turn `MomentObserver`, the artifact row and the
task's per-turn bookkeeping. The shape in the source: the CPU
`_moment_observer_row` (`src/tasks/BeamObservers.jl`) collects the six
coordinate arrays (`map(collect, coordinate_arrays(rep))`), builds the live
flags, takes six masked means, and then makes one SERIAL
`_masked_global_sum` pass over the whole beam per requested moment -- 27
moments in the harness's observer -- on one thread while the workers idle.
The CUDA observer is one fused kernel for both passes (its
`_moment_observer_row` comment), so the 38x of the CUDA arm compares a
serial host observer against a device one as much as it compares tracking
kernels; the production run's `moment_step=50` variant separates the two
terms. The finding is a ledger row (section 6), not a fix in this batch.

## 4 The benchmark

The production run of the driver -- the crab harness at N = 1e5 and 1e6,
2000 turns, arms threads:16, threads:32, mpi:4x8, mpi:8x8, mpi:16x8 and
cuda, a `moment_step=50` variant at N = 1e5, and the threads:16 baseline
repeated at the end for the drift -- is running at the time of writing. Its
table (steady ms/turn with the percentile band and the max-rank figure, the
whole-process wall, the loads at launch and exit), the speed-ups against
threads:16, the identity verdicts per arm (for the CPU arms the luminosity
series bitwise and the moments to the fold bound with the worst column
named; for the CUDA arm the relative differences of the emittances and the
luminosity), the GPU utilisation readings before and after the CUDA arm,
and the drift pair of the two baselines follow.

The production benchmark ran on 2026-10-14 between 16:57 and 18:12 EDT on
the shared 128-core host (other users' load average 2 to 31 during the
runs), tree 371b2df plus the uncommitted arm, package load mode for every
arm, one arm at a time: the white rule at scale 1, radiation off, seed
123456789, 2000 turns, moments every turn, the steady window turns 21 to
2000, the launcher MPI.jl's MPICH_jll 5.0.1. The per-turn figures are
medians of the per-turn instrument on rank 0's clock; the slowest-rank
median agreed within 0.1 % on every MPI arm, and the harness's own steady
figure matched the driver's on every arm.

N = 1e5 particles, moments every turn:

| arm | ms per turn, median [p10, p90] | speed-up vs threads:16 | wall s | load at launch and exit | identity against threads:16 |
|---|---|---|---|---|---|
| threads:16 | 118.71 [116.42, 122.46] | 1.00 | 283 | 2.2 and 5.6 | baseline |
| threads:32 | 80.33 [78.79, 97.97] | 1.48 | 202 | 5.6 and 8.8 | whole output bitwise identical |
| mpi:4x8 | 57.91 [57.20, 64.60] | 2.05 | 156 | 8.8 and 12.7 | luminosity series bitwise; moments worst column m000010 at 2.05e-12 scaled; emittances and luminosity mean 1.7e-14 |
| mpi:8x8 | 36.91 [35.79, 45.96] | 3.22 | 115 | 12.7 and 20.5 | luminosity bitwise; m000010 2.40e-12; 1.5e-14 |
| mpi:16x8 | 30.87 [28.10, 41.75] | 3.85 | 106 | 20.5 and 31.4 | luminosity bitwise; m000010 2.06e-12; 1.5e-14 |
| cuda | 3.347 [3.187, 3.397] | 35.5 | 61 | 31.4 and 12.3 | emittances and luminosity mean 1.7e-14; luminosity series 5.0e-14; moments worst m001000 5.6e-12 |

N = 1e6 particles, moments every turn:

| arm | ms per turn, median [p10, p90] | speed-up vs threads:16 | wall s | load at launch and exit | identity against threads:16 |
|---|---|---|---|---|---|
| threads:16 | 560.00 [418.05, 577.91] | 1.00 | 1101 | 12.3 and 3.5 | baseline; bimodal, two regimes near 418 and 575 ms, the median a mixture |
| threads:32 | 417.82 [412.31, 428.46] | 1.34 | 881 | 3.5 and 12.2 | whole output bitwise identical |
| mpi:4x8 | 220.20 [215.79, 229.29] | 2.54 | 479 | 12.2 and 8.4 | luminosity bitwise; m000010 2.62e-12; 1.3e-14 |
| mpi:8x8 | 155.94 [148.50, 165.95] | 3.59 | 352 | 8.4 and 20.3 | luminosity bitwise; m000010 2.15e-12; 1.2e-14 |
| mpi:16x8 | 192.97 [185.51, 205.85] | 2.90 | 428 | 20.3 and 27.5 | luminosity bitwise; m000010 2.39e-12; 1.4e-14; slower than 8x8 with 128 threads on a node at load 20 to 27 |
| cuda | 26.02 [25.96, 26.06] | 21.5 | 104 | 27.5 and 5.9 | 1.5e-14; luminosity series 1.5e-14; moments worst m101000 5.9e-12 |

The luminosity digest takes one value for every CPU arm at a given N, the
step-50 and drift runs included; the CUDA arms' differ at the 1e-14 level.
The MPI arms' moments differ from the threads arms' only in the rank-order
fold (section 2); every emittance and luminosity mean agrees to 1.2 to
1.7e-14.

Moments every 50 turns, N = 1e5, 2000 turns (40 moment rows): threads:16
18.72 [17.96, 20.95] against 118.71 at every turn, so the every-turn
moment observer and artifact row cost about 100 ms per turn, 84 % of the
CPU per-turn time, and tracking alone about 19 ms (the observer-free
instrument of section 3 gave 23.1 ms at the same point); mpi:8x8 9.50
[7.51, 11.35] against 36.91, so 74 % was the observer, which MPI divides
because each rank reduces its own shard while threads cannot (the CPU
moment row is a serial pass per moment); cuda 2.544 [2.516, 2.568] against
3.347, so 0.8 ms per turn, 24 %. Identity at step 50: mpi:8x8 luminosity
bitwise, m000010 1.22e-11 scaled, emittances 7.4e-15; cuda 3.4e-15 and the
luminosity series 5.0e-14. Walls 72, 58 and 56 s.

The drift pair, threads:16 at N = 1e5 with moments every turn: 16:57,
118.71 [116.42, 122.46] at load 2.2 to 5.6, against 18:12, 119.23 [115.49,
123.43] at load 9.0 to 6.3: +0.4 %, the whole-output digest identical, so
a run is bitwise reproducible run to run; the weak-strong dry run of
section 3 (148 against 118 ms ten minutes apart) is the honest bound of the
shared node, and every arm is a single run in a fixed order.

GPU utilisation read before and after each of the three CUDA arms (17:11,
18:06, 18:10): 0 % and 0 %, with 11.9 GB held by another process
throughout, so no competing GPU work during the CUDA arms.

Verdicts: the luminosity series is bitwise identical between threads and
MPI at every rank count and both sizes; the moments stay within the fold
bound with the worst column always m000010, the near-zero mean z, at about
2e-12 scaled to the column's maximum; threads:16 and threads:32 are
bitwise identical in the whole output; CUDA against threads differs by 1.5
to 1.7e-14 on the emittances and the luminosity mean and by at most 5e-14
on the luminosity series. Caveats: one run per arm, the order not
randomised, a shared node (the load columns), the 1e6 threads:16 arm
bimodal, and the whole-process wall including about 25 s of package load.

## 5 Verification

Matrix classes, read from the diff (`examples/crab_cavity_noise.jl`,
`test/examples/crab_cavity_noise.jl`, the new
`profiling/crab_cavity_noise_backends.jl`, and the documents of section 6):
examples (the script runs; the catalogue entry is unchanged and still names
the script; example execution is full-lane only, so the gate is the full
lane); concurrency surfaces (the harness issues a collective of its own and
the suite launches it under MPI: the full gate at four threads); validation,
study or benchmark (the driver reproduces its dry run; this record is
committed with the numbers; the full gate before the commit carrying the
claim); docs plus anything else (full). Not triggered: CUDA-reachable code
(no kernel, `compile_runtime` or conversion changed), public configuration
(no policy, option or observer changed; `config.ranks` and the `OCTOPUS_*`
switches are script switches whose consumer is the script), contracts,
symbol changes, and test infrastructure (`test/runtests.jl` is not in the
diff). Targeted checks before the gate: the harness at its default on CPU;
the divided runs and the refusals of section 2; the dry run of section 3;
the suite's "The developer harnesses run divided under an MPI launcher"
extracted, 10 of 10 (8 before). Not verified at the time of writing: the
full gate on the batch's final tree, CI on it (not pushed), and the
production benchmark's table.

The full gate ran on the committed tree f858107 (working tree clean, the
HEAD recorded in each log header) in both CPU arms, CUDA active, four
threads, one arm after the other on a quiet host (load average about 3 to
6):

| arm | start to end, EDT, 2026-10-14 | rows | assertions | exit |
|---|---|---|---|---|
| native | 18:57:01 to 19:45:10 | 332 | 149351 of 149351 | 0 |
| AVX2 (OpenBLAS Haswell kernels, LLVM target haswell) | 19:45:10 to 20:32:50 | 332 | 149351 of 149351 | 0 |

```bash
julia --project=. --threads=4 -e 'using Pkg; Pkg.test(julia_args=["--threads=4"])'
OPENBLAS_CORETYPE=Haswell julia -C haswell --project=. --threads=4 \
  -e 'using Pkg; Pkg.test(julia_args=["--threads=4", "-C", "haswell"])'
```

Both arms end in "Testing Octopus tests passed"; no summary row carries a
Fail, Error or Broken column; the sorted row sets of the two arms are
identical; nothing was skipped; CUDA was active, 36 rows per arm naming it.
Against the crab-noise gate on 90a15be (332 rows, 149351 - 2 assertions)
the row count is unchanged and two assertions were added, the launcher
testset's pins for this harness: "The developer harnesses run divided
under an MPI launcher" 10/10 (was 8/8; 2 min 12 s in each arm, both
launched harnesses and this one under mpiexec -n 2), "Every example script
runs against the current interface" 21/21 (10 min 30 s native, 10 min 24 s
AVX2, the eight scripts each exit 0). Checks before the gate on the same
tree: the extracted sweeps (exit 0), the fast lane (exit 0, 316 rows,
147178/147178, the fifteen standard loud skips, 18:37 to 18:56) and
"Architecture integrity" 28/28 on the final documents. Not verified: CI on
this tree, which is not pushed at the time of writing. Added after the push: pushed 2026-10-14 as
ef04cfc (this record's commit on top of f858107); CI run 451 on it
completed green (runner znver3, 32 min, the usual stage 6 identity-pin
notices).

## 6 Ledger and owner items

Ledger rows added to `docs/todo.md` on 2026-10-14:

- the follow-up row "Crab cavity noise example: the MPI execution policy
  arm and the cross-backend benchmark", in progress (arm landed, benchmark
  running, gate pending);
- "The every-turn `MomentObserver` and artifact row dominate the CPU
  per-turn cost", open, with section 3's numbers and the shape of a fix: a
  fused parallel reduction that reads each particle's six coordinates once
  and accumulates all requested moments, chunked over the logical workers
  on the fixed chunk grid and folded in chunk order (as the CUDA observer
  already does in one kernel), or at least fewer passes; it must keep "a
  lost particle is excluded from every reduction, exactly" and the one-rank
  identity with the undivided run, it moves the recorded moments in their
  last bits once (which the pins must absorb deliberately, not by widening),
  and it is measured before and after on the digest;
- the friction row from the implementer: a script cannot ask Octopus which
  rank it is after `execute!` -- `_mp_rank()` reads the policy in force and
  answers 0 outside the scope, so the harness reads `MPI.COMM_WORLD`
  directly and the example reads the `:multi_process_communicator` receipt,
  which exists only inside `with_execution_audit`; and `turn_timings(task)`
  is per rank with no collective, so the harness issues its own `Allreduce`
  for the per-turn maximum. The shape: a public accessor for the
  communicator the run recorded (the receipt's `nranks`, `rank`,
  `resolved_by`, `threads`, readable without an audit), and a documented
  reduced form of `turn_timings` or the statement that the per-rank series
  is the deliberate product.

Documents changed in the same batch: `docs/current_runtime.md` (its
multi-process paragraph said a divided run reproduces the undivided one
"bit for bit"; it now says bit for bit in the tracked beam and the
luminosity series, and the moments to the fold bound, citing the design
note); `docs/public_api.md` ("Turn Modulation": the example runs under the
MPI execution policy and this record exists); `docs/README.md` (this record
indexed). No entry in `docs/experiences.md`: the batch confirmed two
recorded lessons (the extension that does not attach to an `include`d
module, and the collective outside its scope) and taught no new one yet;
the observer-cost finding becomes a lesson when its fix lands and is
measured.

Owner items: none new. Reported, not fixed here (not a document): the
comment in the suite's launcher testset (`test/runtests.jl`, "The developer
harnesses run divided under an MPI launcher") still cites
`test/examples/crab_cavity_noise.jl` as the harness "which has no
multi-process arm"; the classification is derived from the files, so the
testset's behaviour is right and only the comment is stale.
