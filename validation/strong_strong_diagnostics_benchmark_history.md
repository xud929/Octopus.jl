# Strong-Strong Diagnostic Benchmark History

This log records diagnostic-only optimization experiments. The PIC solver is
held fixed at the fastest validated configuration: CUDA `Float64`, indexed
wavefront, asynchronous batch and wavefront FFT paths, slice-pair Green cache,
`pic_slice_pair_green_min_ratio = 0.50`, and
`pic_slice_pair_green_growth = 0.25`.

## 2026-07-18: 200-turn moment and luminosity study

The case used 2.56 million electron macroparticles, 1 million proton
macroparticles, a 128 x 128 grid, and 15 x 15 slice pairs. All timings below
are the mean of turns 100 through 199 unless noted otherwise.

| Configuration | Mean (s/turn) | Median (s/turn) | Change from baseline |
| --- | ---: | ---: | ---: |
| No diagnostics | 0.35682 | 0.35641 | reference |
| Moments, GPU reduction, capacity 100 | 0.37143 | 0.36970 | +4.1% |
| Luminosity calculation only, original bounds | 0.47190 | 0.47160 | +32.2% |
| Luminosity calculation and text output, original bounds | 0.47030 | 0.46957 | +31.8% |
| Moments and luminosity output, original bounds | 0.46954 | 0.46907 | +31.6% |
| Luminosity output, combined bounds reductions | 0.42408 | 0.42350 | +18.8% |
| Moments and luminosity output, combined bounds reductions | 0.44082 | 0.44090 | +23.5% |

The luminosity text write was below run-to-run noise; the expensive part was
the GPU calculation. Combining the electron and proton min/max calculations
reduced eight scalar GPU reductions per slice pair to two tuple reductions.
This improved the luminosity-output workload by 9.8% and the complete
moments-plus-luminosity workload by 6.1%. The solver, field calculation, and
particle kicks were not changed.

The former CUDA moment path copied all six particle-coordinate arrays to the
host before reduction. A production-size 200-turn trial remained CPU-bound
for several minutes and was stopped before completing; it is retained only as
the `OCTOPUS_CUDA_MOMENT_REDUCTION=0` debugging fallback. The accepted path
keeps coordinates and reusable scratch storage on the GPU and transfers only
the 27 reduced scalar moments per beam and observation.

The optimized and original 200-turn luminosity series differed by at most
`7.69e-15` relative. Final electron and proton RMS coordinates for every
configuration agreed with the no-diagnostic reference at floating-point
roundoff. A direct CPU/CUDA comparison of all default first- and second-order
moment columns had maximum relative error `1.50e-13`.

### Moment buffer capacity

| Capacity | Mean (s/turn) | Median (s/turn) | Observation |
| ---: | ---: | ---: | --- |
| 1 | 0.37789 | 0.37699 | Per-turn HDF5 flush costs 1.7% versus capacity 100. |
| 100 | 0.37143 | 0.36970 | Best balance for the 200-turn run. |
| 200 | 0.37608 | 0.37050 | Similar steady state, with a large final-flush outlier. |

Capacity 100 remains the example default. It amortizes HDF5 writes without
deferring all durable output until finalization.

### Rejected indexed luminosity stream overlap

An experimental indexed-wavefront path launched luminosity on the dedicated
CUDA luminosity stream, overlapped it with the PIC field solve, and joined it
before kicks could mutate either beam. It measured `0.43567 s/turn`, compared
with `0.42408 s/turn` for the accepted synchronous combined-bounds path: 2.7%
slower. Both operations compete for the same GPU execution and memory
resources, so overlap did not hide the luminosity work. The experimental path
was removed. Its 200-turn luminosity series and final beam RMS coordinates
agreed with the synchronous reference at floating-point roundoff.

A device-side bounds prototype using one reduction block per slice pair was
also rejected during implementation: it underutilized the GPU for large
slices and did not provide a valid improvement over CUDA.jl's parallel
map-reductions. It was not retained in production code. A future device-only
bounds attempt should use multi-block segmented reductions across all pairs,
not one block per pair.

### Rejected fused two-beam deposition

A fused kernel deposited both beams for each slice pair in one launch while
preserving the same CIC weights, grids, and overlap reduction. It measured
`0.45988 s/turn`, 8.4% slower than `0.42408 s/turn`. The fusion removed one
launch per pair but retained all atomic operations and introduced divergent
work for unequal slice populations. The luminosity series agreed with the
reference within `7.18e-15` relative. The kernel was removed.
