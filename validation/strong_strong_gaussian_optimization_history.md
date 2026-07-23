# Soft-Gaussian Optimization Benchmark History

This log records dated optimization experiments for the CUDA soft-Gaussian
strong-strong collision (`GaussianPoissonSolver`, `batch_mode = :wavefront`).
The design summary and correctness audit live in
[`strong_strong_gaussian_optimization.md`](strong_strong_gaussian_optimization.md);
this file is the running experiment trail, including rejected and reverted
attempts. The PIC solver is not modified by any entry here.

## 2026-07-23: host-synchronization and launch-overhead reduction

Case: RTX 4500 Ada, `Float64`, `examples/strong_strong_tracking.jl` beam
parameters (2,560,000 electron and 1,024,000 proton macroparticles, 15
normal-quantile slices), `virtual_drift = :hirata`, uncoupled. Production
timings are the mean of turns 100 through 200; baseline pairs were re-measured
interleaved to control run-to-run GPU drift. Every accepted change was gated by
the CPU/CUDA soft-Gaussian consistency contract in both coupling modes and by a
matching 200-turn final RMS before acceptance.

Profiling first: the collision was host-synchronization- and launch-overhead-
bound, not compute-bound. A two-point fit gave `t = 0.061 + 5.4e-8 * N` s, so
the fixed floor was about `0.061` s per collision (about 70% of the collision at
the example size, about 95% at 20,000 particles per beam), from per-wavefront
host round-trips and roughly `960` tiny per-slice-pair kernel launches.

| Stage | Mean (s/turn) | vs baseline | Verdict |
| --- | ---: | ---: | --- |
| Baseline | 0.2778 | reference | -- |
| + defer luminosity reduction to device | 0.2689 | -3.4% | accepted (`313f45c`) |
| + build slice moments on device | 0.2564 | -7.9% | accepted (`313f45c`) |
| + fuse per-wavefront moment/kick launches | 0.2280 | -18.0% | accepted (`315b55a`) |

Each stage was bit-identical: contract coordinate residual `3.09e-17`
(uncoupled) and `3.01e-17` (coupled), luminosity relative error `1.35e-16`, and
200-turn final electron/proton RMS matching the baseline to every printed digit.
The fixed per-collision floor fell about 85%, from about `0.061` s to about
`0.009` s, so the gain is largest in the launch-bound regime: a
20,000-particle-per-beam isolated collision dropped from `0.0635` s to `0.0114`
s (about 5.6x). Turn-to-turn jitter fell from roughly `0.274`-`0.306` s to
`0.227`-`0.229` s once the host/device handshakes were removed.

Fusion detail: the fused moment kernel uses `blockIdx().y` as the slice column
and each column's own block count, so its block reduction is bit-identical to
the per-column kernel; the fused kick kernel uses `blockIdx().y` as a directed
kick segment and per-particle kicks are independent. Fusion is within each
wavefront batch only, and batches still execute sequentially, so the
collision-time ordering from `collision_pair_batches` is unchanged.

### Reverted: contiguous slice storage shared with the PIC path

The first fused-launch implementation built the contiguous slice-index
permutation inside the shared `_cuda_slices_from_boundaries`, so the PIC path
also paid for the concatenation and consumed slice indices as views although it
never uses the fused kernels. A PIC production A/B (200,000 electron / 100,000
proton, 128 x 128 grid) showed a small mean overhead (`0.09784` -> `0.09861`
s/turn; steady-state minimum essentially unchanged). The permutation was moved
into `_cuda_gaussian_collide_wavefront!` via `_cuda_concat_slice_indices`, so
`_cuda_slices_from_boundaries` again returns per-slice index vectors and the PIC
and sequential paths are byte-for-byte unchanged (`efbd3d2`). PIC production
throughput is unchanged: `0.31388` s/turn before the session versus `0.31560`
s/turn after, same 2.56M/1.024M, 128 x 128, 15-slice case, within run-to-run
variance.

### Not pursued: fusion beyond the launch floor

After the three accepted changes the collision is about 96% real physics compute
at production scale (the Weideman-approximation Bassetti-Erskine kick, already
tuned in `src/math/SpecialMath.jl`). The remaining fixed floor is under 4% of
the production collision, so further launch/metadata micro-consolidation was not
pursued. A naive cross-batch fusion is not attempted because it would violate
the wavefront collision-time ordering.
