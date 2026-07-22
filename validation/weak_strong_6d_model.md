# Weak–Strong Six-Dimensional Model Validation

This record covers the coupled-covariance and six-dimensional Gaussian-source
change relative to `HEAD` `d85f61e`. The mathematical model is documented in
[`docs/weak_strong_6d_model.md`](../docs/weak_strong_6d_model.md), and the
longitudinal-kick limits are derived in
[`docs/beam_beam_longitudinal_kick.md`](../docs/beam_beam_longitudinal_kick.md).

## Correctness coverage

`test/runtests.jl` exercises every limiting case listed in Section 10 of the
longitudinal-kick note:

1. zero transverse force;
2. constant source centroid;
3. constant transverse covariance;
4. reduction to the uncoupled Twiss formula;
5. fixed nonzero transverse tilt;
6. changing tilt and the invariant Hessian contraction;
7. the exactly round covariance limit;
8. the centroid and Hirata slingshot terms; and
9. a finite-difference six-dimensional symplecticity check.

Separate tests verify Gaussian conditioning, pure crab dispersion, momentum
dispersion, composed crab waveforms, covariance validation, and coupled
CPU/CUDA parity for both thin and longitudinally sliced strong beams.
All three physical virtual-drift strategies have golden-value regression
tests. The two historical non-symplectic maps are rejected as ordinary
symbols and tested only through `UnsafeVirtualDrift`; CPU/CUDA parity is
checked separately for all physical and diagnostic strategies.

## Performance regression check

Measurements were made on 22 July 2026 with Julia 1.12.4, an Intel Xeon Gold
6430 host, eight Julia threads, and an NVIDIA RTX 4500 Ada Generation GPU. The
benchmark tracks an unchanged uncoupled seven-slice Gaussian source, so it
measures the compatibility hot path rather than the additional coupled physics.

The CPU case used 500,000 macroparticles and 21 measured one-turn samples in
each process. Two interleaved repetitions produced:

| implementation | median range (s) | first-quartile range (s) |
|---|---:|---:|
| `HEAD` | 0.2106–0.2141 | 0.2064–0.2121 |
| six-dimensional model | 0.2108–0.2158 | 0.2078–0.2146 |

The CUDA case used 1,000,000 macroparticles, three turns per sample, and nine
measured samples in each process. Two interleaved repetitions produced:

| implementation | median range (s) | first-quartile range (s) |
|---|---:|---:|
| `HEAD` | 0.0810–0.0815 | 0.0795–0.0797 |
| six-dimensional model | 0.0812–0.0828 | 0.0795–0.0799 |

The distributions overlap; no CPU or CUDA regression is resolved above normal
run-to-run variation. This result depends on compile-time specialization:
uncoupled transverse moments bypass the coupled eigensystem, and sources with
no slice-angle dispersion do not load or transfer angle-offset arrays.

These timings are regression evidence for the measured workload, not a claim
of universal speedup. Performance should be remeasured when the kernel,
compiler, hardware, or production slice count changes.

The subsequent replacement of the numeric drift selector by named,
compile-time drift strategies was remeasured with the same workload. The
`:hirata` case gave 0.2167 s CPU median (0.2062 s first quartile) and 0.0798 s
CUDA median (0.0797 s first quartile). These remain within the original
measurement distributions. An inference test guards that a sliced Gaussian
beam retains the concrete drift strategy of its thin source.
