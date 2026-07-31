# Stable Strong-Strong Moment Reductions - 2026-07-30

This record closes the second major issue from the pre-release review:
strong-strong source variances and covariances were computed as differences of
large raw moments. For a coordinate with a large centroid and a small physical
spread, the former expression

```text
variance = sum(x_i^2) / n - (sum(x_i) / n)^2
```

can lose the spread entirely through floating-point cancellation. In Float64,
a deterministic `1e8 +/- 1` sample returned zero variance instead of one.
That can silently collapse a Gaussian source size, corrupt a coupled
covariance, or produce the wrong `grid_extent=:sigma` PIC mesh.

## Implemented method

For each sample, the implementation now chooses the first in-sample value
`a = x_1` as an anchor and accumulates shifted values `d_i = x_i - a`:

```text
D  = sum(d_i)
Q  = sum(d_i^2)
mu = a + D / n
var(x) = Q / n - (D / n)^2
```

For two coordinates with anchors `a` and `b`,

```text
D_x = sum(x_i - a)
D_y = sum(y_i - b)
Q_xy = sum((x_i - a)(y_i - b))
cov(x,y) = Q_xy / n - (D_x / n)(D_y / n)
```

These are algebraically identical to the population variance and covariance.
The final subtraction is evaluated with `muladd` where supported. Its
intermediate scale is set by the beam spread rather than by the absolute
centroid.

An online Welford recurrence was not selected. Although stable, its
loop-carried dependency and per-particle division inhibit CPU vectorization,
GPU parallel reduction, and the existing one-pass multi-block layout. The
shifted-data identity keeps independent per-particle work, one particle pass,
and associative partial sums. CPU worker chunks and CUDA blocks all use the
same anchor, so their partial sums can be added directly.

The method cannot reconstruct information absent from the input type. If two
physical coordinates round to the same Float32 or Float64 value before the
reduction, their sub-ULP separation is already lost. For a clustered beam,
however, subtraction from an in-sample anchor avoids the large raw-square
cancellation and is usually exact under Sterbenz's lemma.

## Changed paths

- CPU soft-Gaussian slicing, including all coupled transverse covariances.
- CUDA soft-Gaussian sequential and fused wavefront moment kernels.
- CPU and CUDA Gaussian-subtracted PIC source moments.
- CPU PIC `grid_extent=:sigma` accumulation and extent reconstruction.
- The default PIC `grid_extent=:extrema` path now skips unused second-moment
  products.

The CUDA Gaussian partial layout adds four anchor slots but retains the same
10 or 14 shared-memory reduction statistics and the same production kernel
count. The compact CUDA Gaussian-subtracted PIC source path first selects an
anchor and then reduces shifted products.

## Accuracy verification

New deterministic tests cover:

- Float32 coordinates centered at `1e4` and Float64 coordinates centered at
  `1e8`, with exactly known variances and covariances.
- Small (`n=8`) and multi-worker (`n=8192`) CPU reductions.
- Multi-block CUDA reductions in coupled and uncoupled modes.
- CPU and CUDA Gaussian-subtracted PIC source moments.
- CPU PIC sigma-based extents.
- The separate fused CUDA Gaussian wavefront solver path.

The cancellation regressions recover `var(x)=1`, `cov(x,px)=-2`, and the
other constructed second moments at both precisions. The complete package test
suite passes, including 96 new CPU assertions and 48 new CUDA assertions, all
existing strong-strong backend parity checks, weak-strong tracking, non-finite
handling, and MomentObserver tests.

### Direct comparison with the pre-fix implementation

A deterministic three-slice, 1,000-particle-per-beam, two-turn run compared the
final 12 coordinate arrays and luminosity series from baseline commit
`5d31308` with the shifted implementation. `State RMS relative` is the maximum
over the 12 arrays of `rms(candidate - baseline) / rms(baseline)`.

| Solver/backend | Bitwise identical | Maximum absolute state difference | State RMS relative | Luminosity relative |
| --- | --- | ---: | ---: | ---: |
| Gaussian CPU | no | 3.79e-19 | 4.06e-16 | 5.53e-16 |
| Gaussian CUDA | no | 2.17e-19 | 2.35e-16 | 0 (bitwise identical) |
| PIC CPU | yes | 0 | 0 | 0 |
| PIC CUDA | no | 1.00e-16 | 3.98e-14 | 1.92e-15 |

The nonzero differences are floating-point reduction-order effects, not a
model change. All are far below the production validation tolerances.

The dedicated current-version validation programs also pass:

- Soft-Gaussian CPU/CUDA final-state and luminosity consistency:
  maximum absolute coordinate difference `1.52e-17`, luminosity relative
  difference `5.53e-16`, configured tolerance `1e-10`.
- PIC CPU/CUDA final-state, luminosity, and cache-history consistency:
  maximum absolute coordinate difference `7.64e-17`, luminosity relative
  difference `5.47e-15`, slice-pair luminosity relative difference `2.60e-14`,
  configured tolerance `1e-10`.
- MomentObserver CPU/CUDA consistency over all 28 output columns and 100,000
  particles: maximum relative difference `1.49e-13`, configured tolerance
  `5e-12`.

## Production performance experiment

Hardware and runtime:

- NVIDIA RTX 4500 Ada GPU
- Julia 1.12.4
- CUDA Float64 tracking
- Baseline source commit `5d31308`

The benchmark uses the physics and workflow from
`examples/strong_strong_tracking.jl`: 2,560,000 electron macroparticles,
1,000,000 proton macroparticles, 15 slices per beam, a 128 x 128 PIC grid where
applicable, and two HDF5 `MomentObserver` streams sampled every turn. Each run
tracks 200 turns and reports the last 100 turns (turns 100-199), including the
representative capacity-100 HDF5 flush.

Commands:

```bash
OCTOPUS_DIAGNOSTIC_BENCHMARK_MODE=moments \
  julia --project=. validation/strong_strong_diagnostics_benchmark.jl

OCTOPUS_SOLVER=gaussian OCTOPUS_DIAGNOSTIC_BENCHMARK_MODE=moments \
  julia --project=. validation/strong_strong_diagnostics_benchmark.jl
```

| Solver | Version | Mean (s/turn) | Median (s/turn) | Minimum (s/turn) | Std. dev. (s) |
| --- | --- | ---: | ---: | ---: | ---: |
| PIC | baseline | 0.2882479 | 0.2871482 | 0.2776152 | 0.0045370 |
| PIC | shifted | 0.2862663 | 0.2865644 | 0.2673584 | 0.0080835 |
| Gaussian | baseline | 0.2476917 | 0.2479937 | 0.2343947 | 0.0018182 |
| Gaussian | shifted | 0.2490967 | 0.2493626 | 0.2386789 | 0.0016501 |

PIC changed by -0.69% in mean and -0.20% in median, which is not a measurable
regression at the observed run variance. Gaussian directly exercises the
changed CUDA source-moment reduction and changed by +0.57% in mean and +0.55%
in median. Both moment files remained 51,408 bytes and completed normally.

A matched eight-thread CPU microbenchmark used a 170,000-particle coupled
slice, close to the average production electron slice population. Nine samples
of 200 reductions gave:

| Version | Median per reduction | Minimum per reduction |
| --- | ---: | ---: |
| baseline | 1.0698 ms | 0.9998 ms |
| shifted | 1.0320 ms | 0.9392 ms |

The CPU result establishes no regression; the apparent 3.5% median improvement
should not be treated as a guaranteed speedup because process-level variation
is comparable to the difference.

## Decision

Keep the shifted-data implementation. It fixes a deterministic silent
correctness failure while preserving the existing parallel structure. The
measured production cost is negligible for PIC and approximately 0.6% for the
Gaussian solver with per-turn HDF5 moment output.
