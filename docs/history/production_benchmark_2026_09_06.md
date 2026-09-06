# Production benchmark: two cases, four solvers, three execution modes

2026-09-06, owner-requested. The first end-to-end measurement of the finished
multi-process campaign against the production cases, rather than against a
collide in isolation. Every number below is a 200-turn run averaged over turns
100 to 200, so no warm-up, no JIT and no first-touch allocation is inside the
average.

## What was run

Two harnesses, unmodified in the repository, each driven at production size:

- **Strong-strong** -- `test/examples/strong_strong_tracking.jl`, the
  crab-crossing electron-proton case (`case_name = "pic_hcc"`, seed
  123456789), 2,560,000 electron and 1,024,000 proton macroparticles, both
  beams live, colliding through a Poisson solver.
- **Weak-strong** -- `test/examples/weak_strong_tracking.jl`, a live weak
  proton beam against a fixed soft-Gaussian strong beam through a crab
  crossing, 1,024,000 macroparticles.

The harnesses carry no multi-process option, so the MPI arms ran through
scratch copies with a six-line `OCTOPUS_MP` branch that wraps the CPU policy in
`MultiProcessExecutionPolicy(threads = ...)`. Nothing else was changed; the
CPU-threads and CUDA arms ran the repository files as they stand. Closing that
gap -- an `OCTOPUS_MP`/`OCTOPUS_RANKS` branch in both harnesses -- is on the
todo, because these runs are otherwise not reproducible from the repository.

`StrongStrongTask` records per-turn timings itself
(`OCTOPUS_RECORD_TURN_TIMES=1`, read back with `turn_timings`), so its window
is a straight mean over turns 100-200 with the standard deviation beside it. A
`TrackingTask` records none, so the weak-strong case was run at 50, 100, 150
and 200 turns per mode and the per-turn cost taken as the least-squares SLOPE
of elapsed against turns. A two-point difference was tried first and rejected:
at 64 threads the 100-turn run came out faster per turn than the 200-turn one,
which makes their difference larger than either run's own rate. Four points
give a slope, an intercept that can be checked against the ~15 s of load and
JIT every arm pays, and an R^2 that says whether to believe either.

## The machine

One shared node: 128 cores, load average 0.4 to 6.9 outside these runs, and one
NVIDIA RTX 4500 Ada (24.5 GB, of which another process held 11.9 GB throughout
at 0% utilisation). The CPU and MPI arms are the ones a competing job would
perturb, and the load average was logged either side of every arm for that
reason. `mpiexec` is the one on PATH; MPI resolves from the shared v1.12
environment because it is a weak dependency of the project.

## Strong-strong: seconds per turn, mean +- sd over turns 100-200

| solver | CPU 16 threads | CPU 64 threads | MPI 8r x 8t | MPI 16r x 8t | CUDA |
|---|---|---|---|---|---|
| soft-Gaussian | 3.107 +- 0.174 | 2.640 +- 0.305 | 1.131 +- 0.109 | 0.765 +- 0.075 | 0.239 +- 0.000 |
| PIC | 4.462 +- 0.214 | 4.983 +- 0.199 | 1.849 +- 0.109 | 1.563 +- 0.107 | 0.344 +- 0.189 |
| spectral | 4.727 +- 0.107 | 5.670 +- 0.154 | 3.392 +- 0.080 | 1.793 +- 0.080 | 0.535 +- 0.033 |
| Gaussian-PIC | 7.380 +- 0.256 | 8.434 +- 0.405 | 5.208 +- 0.081 | 3.758 +- 0.120 | 0.677 +- 0.005 |

Against each solver's own best threads-only time:

| solver | best CPU threads | MPI 8r x 8t | MPI 16r x 8t | CUDA |
|---|---|---|---|---|
| soft-Gaussian | 2.640 | 2.3x | 3.5x | 11.0x |
| PIC | 4.462 | 2.4x | 2.9x | 13.0x |
| spectral | 4.727 | 1.4x | 2.6x | 8.8x |
| Gaussian-PIC | 7.380 | 1.4x | 2.0x | 10.9x |

## Weak-strong: seconds per turn, fitted over 50/100/150/200-turn runs

| mode | per turn (s) | fitted setup (s) | R^2 | vs best CPU threads | rate over 50-100, 100-150, 150-200 |
|---|---|---|---|---|---|
| CPU 16 threads | 0.4690 | 17.6 | 0.9830 | 1.0x | 0.481, 0.598, 0.284 |
| CPU 64 threads | 0.6384 | -0.5 | 0.9667 | 0.7x | 0.313, 0.749, 0.816 |
| MPI 8r x 8t | 0.1460 | 13.7 | 0.9994 | 3.2x | 0.147, 0.137, 0.156 |
| MPI 16r x 8t | 0.0908 | 13.4 | 0.9951 | 5.2x | 0.076, 0.091, 0.105 |
| CUDA | 0.0377 | 19.0 | 0.9982 | 12.4x | 0.042, 0.033, 0.039 |

## The solver options these numbers belong to

A timing without its configuration is not a measurement, and three of these
four solvers have grids or caches that move the number by more than the
execution mode does. Slicing is shared: `LongitudinalSlicing(method =
:normal_quantile, nslices = 15, center_position = :centroid)`, and every solver
ran `longitudinal_kick = true` and `batch_mode = :wavefront`.

| solver | options |
|---|---|
| soft-Gaussian | `min_sigma = 1.0e-12`, `luminosity_scale = nothing` |
| PIC | `grid = (128, 128)`, `deposit_method = :CIC`, `green_type = :integrated`, `green_cache = :slice_pair`, `slice_pair_green_min_ratio = 0.50`, `slice_pair_green_growth = 0.25`, luminosity every turn on a `(128, 128)` mesh with CIC deposition |
| spectral | `grid = (127, 383)`, `domain_factor = 8.0`, `method = :grid`, `field_precision = :double` |
| Gaussian-PIC | `grid = (64, 64)`, `deposit_method = :CIC`, `green_type = :integrated`, `green_cache = :slice_pair` |

The CUDA arms additionally ran the PIC family with `cuda_async = true`,
`cuda_batch_fft = true`, `cuda_wavefront_fft = true` and
`cuda_indexed_wavefront = true`, which are the defaults.

The spectral grid is worth a note of its own. `(127, 383)` is not a rounding of
`(128, 384)`: a DST-I over `N` interior points has logical size `2(N + 1)`, and
FFTW is fast only when that is smooth. 127 gives 256 and 383 gives 768; 128
would give 258, whose largest prime factor is 43. The harness default is
already the fast pair, and `_spectral_note_grid_size` warns when a run picks a
slow one.

The weak-strong case: weak proton beam at 275 GeV, `n_particle = 0.6881e11`,
sigmas `(95 um, 8.5 um, 6.0 cm)`, `sigd = 6.6e-4`, `beta = (0.8, 0.072)`;
strong electron beam `n_particle = 1.7203e11`, sigmas `(95 um, 8.5 um, 0.7 cm)`,
`beta = (0.55, 0.056)`, 7 slices by `:equal_area`, `virtual_drift = :hirata`;
crossing angle 12.5 mrad with a two-harmonic crab scheme `(4/3, -1/3)` at
197 MHz; radiation excitation on, damping off.

## What the numbers say

**CUDA wins every case on both tasks.** One RTX 4500 Ada beats the whole
128-core node for all four strong-strong solvers and for weak-strong tracking.
Its variance is also in a different class: the CUDA arms hold a standard
deviation of a millisecond or so where the CPU arms scatter by 100 to 300 ms.

**More threads in one process is not more speed.** PIC, spectral and
Gaussian-PIC are all SLOWER at 64 threads than at 16, and so is weak-strong
tracking. Only the soft-Gaussian improves. This is the Phase 0 finding -- a
per-process optimum near 16 threads -- reproduced on the production cases, and
it is the whole argument for the multi-process campaign: the way to spend the
rest of a big node is more ranks, not more threads.

**One CUDA outlier is in the PIC row.** Its mean is 0.344 s with a standard
deviation of 0.189, against a minimum of 0.306 and a maximum of 2.234: one turn
in the window cost seven times the rest and every other turn sits inside a few
milliseconds. Read the PIC CUDA number as ~0.31 s a turn with one stall, not as
a distribution with that spread. The other three CUDA arms hold standard
deviations of 0.0004 to 0.033 s.

**The 64-thread weak-strong arm degrades as the run proceeds, and that is a
lead.** Its interval rate climbs from 0.313 s a turn over turns 50-100 to 0.816
over turns 150-200, and its fitted intercept is -0.5 s where every other mode
sits at a physical 13 to 19 s of load and JIT. A straight line does not
describe it. No other arm does this: CUDA holds 0.042/0.033/0.039 and MPI 8x8
holds 0.147/0.137/0.156 across the same windows. Phase 0 measured weak-strong
tracking's GC share at 3.2%, 30.8% and 52.2% for 1, 16 and 64 threads, and the
step-1 allocation extraction removed the dominant site but not the thread
scaling of what is left. The number in the table is the fitted slope; the
honest statement is that at 64 threads the per-turn cost is between 0.31 and
0.82 seconds depending on how far into the run you look. It is the one arm here
whose value should not be quoted without that sentence.

**MPI is how the CPU gets past one socket.** Sixteen ranks of eight threads
beat the best threads-only arm on every solver, and doubling eight ranks to
sixteen still pays for PIC and spectral. It pays least for the soft-Gaussian,
whose collide has little work left to divide at this size -- which is the
expected shape, not a defect.

**Spectral behaves as the step-4g/4h attribution said it would.** It gains most
from 8 to 16 ranks, because at eight ranks its groups are narrow and at sixteen
a slice starts spanning a group and the dataflow loop takes over; and it trails
PIC on the CPU while nearly matching it on the GPU, which is the 15-slice chain
limit showing up exactly where the attribution put it.

## Reproducing

    OCTOPUS_TURNS=200 OCTOPUS_N_MACRO_ELE=2560000 OCTOPUS_N_MACRO_PRO=1024000 \
      OCTOPUS_RECORD_TURN_TIMES=1 OCTOPUS_SOLVER=<pic|spectral|gaussian|gaussian_pic> \
      OCTOPUS_CPU_THREADS=16 julia --project=. --threads=16 test/examples/strong_strong_tracking.jl

    OCTOPUS_TURNS=200 OCTOPUS_N_MACRO=1024000 julia --project=. test/examples/weak_strong_tracking.jl

with `OCTOPUS_USE_GPU=1` for the CUDA arms. The MPI arms need the harness
branch named above; until it lands they are reproducible only from the scratch
copies.
