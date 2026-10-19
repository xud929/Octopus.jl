# U3: pic_cuda.jl, last third (lines 4401-6492)

## Region
`/cfs/ad/dxu/Library/Julia/Octopus/src/tasks/strongstrong/pic_cuda.jl` lines 4401-6492 (2092 lines) at
commit 24e8683. Contents: the tail of the drifted plane deposit kernel; the indexed/pair deposit kernels
and `_cuda_pic_deposit_point!`; the bounds tuple/warp/block reduction and its four partial/finalize
kernels; CIC/TSC weights; the three spectral Green multiply kernels; the two luminosity overlap kernels;
the three field (gradient) kernels; the kick kernels (plain, longitudinal, pair-indexed x2, node,
quadratic) and the three interpolators; the CUDA `GaussianPoissonSolver` `collide!` dispatcher and the
sequential route; device liveness flags; the canonical lane-fold kernels and `_cuda_live_z_stats`; the
five slicing methods with their shared tails (`_cuda_slices_from_indices`, `_cuda_slices_from_boundaries`,
`_cuda_degenerate_slices`, `_cuda_concat_slice_indices`); the slice transverse-moment reduction
(`_cuda_slice_transverse_moments`, `_cuda_gaussian_moments_from_sums`, the fixed 256/256 launch, the
partials/reduce kernels); the slice kick kernel; the fused wavefront moment/build/kick kernels; and the
two CUDA-absent `collide!` stubs.

Briefed hypotheses: (1) moment/kick kernel numerics (reduction order, float atomics, FMA contraction) and
whether the declared cross-backend classes cover what is measured; (2) the register-pressure/launch-cap
seam and whether every launch is capped; (3) workspace caches keyed by fewer parameters than the CPU
twin's key.

## Provenance

READ line by line: pic_cuda.jl 4401-6492 (the whole region). READ for comparison only (not audited):
pic_cuda.jl 40-80 (`_cuda_launch_capped!`), 612-622, 725-790 (workspace key), 1238-1420 selected lines
(wavefront Gaussian launcher), 1812-1872 (bounds stage launches), 2510-2570 (bounds value helpers),
2698-2802 (wavefront workspace), 3799-3834, 3838-3900, 3909-3992 (luminosity launches); pic_cpu.jl
2475-2560, 2804-2995; slicing.jl 60-135, 136-235, 240-345, 360-404, 444-636, 637-700, 810-830, 855-900,
980-1060; gaussian.jl 55-105, 105-275, 360-420; interface.jl 120-330, 967-1020; Policies.jl 332-362,
1300-1360; strong_beam.jl 88-120, 780-830; strong_beam_track.jl 750-800; Track.jl 160-240; Beam.jl 29-35;
test/runtests.jl 14440-14500, 26040-26140, 31872-32035; the previous audit's `U3_report.md` (header,
leads 6-8); docs/history/cuda_lastbit_fma_2026_09_07.md (head).

EXECUTED (all under `/cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U3/`,
Julia 1.12.4, RTX 4500 Ada; every `.jl` has a `.log` beside it):
- `launch_sites.sh`: every kernel defined in the region located at its launch site(s) in `src/`.
- `probe1_host_rules.jl` (host): equal-width membership CPU rule vs CUDA rule on 200,000 z at ns=3,5,7,15
  for Float64/Float32, continuous and quantised; Float32 weight rule on 5e6 (count,total) pairs; the 1/12
  stencil literal. Result: 1 disagreement in 200,000 (Float32 continuous, ns=7), all other 19 cases 0;
  weights 0 of 5,000,000 differ; `Float32(1/12) == 1f0/12f0`.
- `probe1b_equal_width_witness.jl` (host): the disagreeing particle and a constructed Float32 witness
  (5 of 6 boundary-sitting particles disagree; Float64 0 of 6).
- `probe2_bounds_warp.jl` (GPU): `_cuda_pic_force_bounds_indexed_kernel!` + finalize at threads
  256,128,64,32,100,96,48,20,16,7,1, three repeats, positive and negative data, against a host fold of
  the same scalar functions. Result: 32/64/96/128/256 bitwise equal; 100/48/20/16/7/1 return 0.0 in the
  min rows (positive data) or the max rows (negative data), every repeat.
- `probe3_e2e_field_threads.jl` (GPU, end to end): bare PIC `collide!` with the resolved launch config
  installed, `field_threads` 128/96/64/100/100, centred beams: all within 1.5e-15 of each other.
- `probe3b_e2e_offset_beams.jl` (GPU, end to end): same with both beams displaced +1 mm in x and y:
  ft=96,64 vs 128 within 1.7e-15 / lum 1.4e-16; ft=100 vs 128: max|dpx|/max|px| = 0.0384,
  max|dpy|/max|py| = 0.199, luminosity 1.01657e30 -> 5.5482e29 (rel 0.454), identical on two repeats.
- `probe4_moments_and_floor.jl` (GPU): CPU vs CUDA slice moments on 200,003 Float64 particles (max 3072
  ulps on a cancelling mean `mpx`, rel 6.2e-13; sigmas within 1-6 ulps); bounds reduce at 1024 and 512
  threads bitwise; `min_sigma` floor arithmetic of the two Gaussian routes (rel 2.3e-8 to 7.1e-8).
- `probe5_f32_solver_return_type.jl` (GPU): `collide!` return type for `GaussianPoissonSolver{Float32}`
  on Float32 beams, sequential vs wavefront. Result: sequential `Float64`, wavefront `Float32`; the Float64 solver returns `Float64` on both routes.

## Leads

### LEAD U3-1 [Major, confidence high] src/tasks/strongstrong/pic_cuda.jl:4536-4567
Claim: `_cuda_pic_bounds_block_reduce` returns extents contaminated by 0.0 whenever its block has a thread count that is not a multiple of 32, and the `field_threads` that reaches the four bounds kernels (any integer in 1:1024, inherited from `CUDALaunchConfig.threads` which only requires > 0) is never validated for that, so a legal launch configuration silently corrupts the interaction-grid bounds of every slice pair -- invisible for beams centred on the origin, a 4-20% kick error and a 45% luminosity error for beams displaced off it.
Mechanism: the first stage (4540-4544) shuffles `values` with `shfl_down_sync(0xffffffff, ...)` for offsets 16..1; in the last partial warp the lanes beyond `blockDim.x` do not exist, the shuffle reads 0.0 from them on this device, and `_cuda_pic_bounds_tuple_combine` absorbs it as a min (positive data) or a max (negative data); `neutral` only covers thread indices past `length(idx)` in the strided loop (4587-4595), never a nonexistent lane. The second stage (`nwarps = cld(blockDim.x, 32)`, 4554-4565) is correct. Launch site 1819/1835-1858: `threads = _cuda_pic_threads(:field)`; validation covers only `1 <= threads <= 1024` (interface.jl 138) and the device maximum (interface.jl 230); the power-of-two rule exists for `:luminosity` alone (interface.jl 141, 223); the launch-geometry sweep uses (64, 128, 256, 512) (Contracts.jl 767), all warp multiples. A centred beam hides the defect because its true min is negative and its max positive, so a stray 0.0 is inside both; the luminosity bounds (rows 9-12, `_cuda_pic_force_luminosity_bounds_indexed_kernel!`) are contaminated the same way. The finalize kernels launch with `threads = _CUDA_PIC_BOUNDS_PARTIAL_BLOCKS = 64` and are safe.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 result/comprehensive_audit_2026_10_18/probes/U3/probe2_bounds_warp.jl` -> threads 100/48/20/16/7/1 print `got (0.0, 5.5055…, 0.0, …)` against `ref (4.9937…, 5.5055…, …)` on every repeat, threads 32/64/96/128/256 print `true`. End to end: `probe3b_e2e_offset_beams.jl` -> `field_threads=100 vs 128: max|dpx|/max|px| = 0.0384  max|dpy|/max|py| = 0.199  lum rel diff = 0.454` (luminosity 1.0165665e30 at 128/96/64, 5.548181e29 at 100, both 100-runs identical), while `probe3_e2e_field_threads.jl` (centred beams) shows 1.5e-15 for the same comparison.

### LEAD U3-2 [Minor, confidence high] src/tasks/strongstrong/pic_cuda.jl:5670-5679, 5932-5938
Claim: CUDA `:equal_width` slicing assigns membership by comparison (`lb <= z < rb`, last slice closed) against `collect(range(zmin, zmax; length=ns+1))` while the CPU twin bins by `_slice_bin` (division + clamp, slicing.jl 496-499), and the two rules disagree for a Float32 z within an ulp of a boundary, so the suite's "Slice geometry is bit-identical across backends" pin for `:equal_width` holds on its continuous 50,000-particle fixture by not landing on a boundary rather than by construction.
Mechanism: `range` evaluates the Float32 boundaries in Float64 and rounds; `(zi - zmin) / width` evaluated in Float32 for a `zi` equal to such a boundary comes out 0.9999999, 1.9999999, ... so `floor` files it one slice below where `z >= lb` files it. The equal-area HISTOGRAM was transcribed to `_slice_bin` for exactly this disagreement (comment at 5681-5692, audit U2-2); the equal-width MEMBERSHIP was left on the comparison rule. Float64 boundaries from `range` are exact in twice precision and the quotient lands on the integer, so no Float64 witness was found. The visible effect is one particle's slice (a weight change of 1/n in two slices and a flake of the bitwise pin), not a physics error.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus result/comprehensive_audit_2026_10_18/probes/U3/probe1b_equal_width_witness.jl` -> `particle 193241: z = -0.79249066f0 ... CPU _slice_bin -> slice 4 ((z-zmin)/width = 3.0f0) / CUDA comparison -> slice 3 (boundaries[4] = -0.7924902f0)` for `randn(MersenneTwister(2026), Float32, 200_000)`, ns=7; constructed `zmin=-3.1f0, zmax=2.7f0, ns=7`: `5 of 6 boundary-sitting particles disagree` (Float64: 0 of 6). `probe1_host_rules.jl`: 19 of 20 (type, distribution, ns) cases agree 200,000/200,000.

### LEAD U3-3 [Minor, confidence high] src/tasks/strongstrong/pic_cuda.jl:6020-6033, 6064 (seam with pic_cuda.jl:1410)
Claim: the wavefront Gaussian route passes `_cuda_gaussian_moments_from_sums` a `min_sigma` already rounded to the BEAM's element type (`T(solver.min_sigma)` at 1410, `T = eltype(beam1.rep.x)` at 1247) while the sequential route (5494, 5498) and the CPU twin (`_slice_moments_finalize`, slicing.jl 1012) pass the solver's own scalar, so for a Float32 beam under a Float64 solver with a nonzero `min_sigma` the two CUDA routes and the CPU apply sigma floors that differ by ~5e-8 relative.
Mechanism: inside the function `floor2 = T(min_sigma) * T(min_sigma)` with `T = eltype(sums) = MT = Float64`; the wavefront argument is `Float32(min_sigma)`, so `floor2 = Float64(Float32(m))^2 != m^2`, and the empty-slice branch returns `sx = sy = T(min_sigma)` rounded the same way. Inert at the default `min_sigma = zero(T)` and for Float64 beams; it binds whenever a slice's variance falls below the floor (`varx = max(sx2, floor2)`, 6065-6066). One quantity, two conventions across routes.
Repro: `probe4_moments_and_floor.jl` section (c): `min_sigma=1.0e-5  sequential floor^2=1.0000000000000002e-10  wavefront floor^2=9.99999949475751e-11  rel diff=5.05e-8`; `3.0e-6 -> rel 7.07e-8`; `1.0e-7 -> rel 2.34e-8`. Code: `grep -n "T(solver.min_sigma)" src/tasks/strongstrong/pic_cuda.jl` (one hit, the wavefront build-kernel launch) against `grep -n "solver.min_sigma, Val(COUPLED)" src/tasks/strongstrong/pic_cuda.jl` (the sequential route).

### LEAD U3-4 [Minor, confidence high] src/tasks/strongstrong/pic_cuda.jl:5490, 5527-5531
Claim: the sequential CUDA Gaussian route's luminosity accumulator is rebound from `MT` to `Float64` by the Float64 constant `TWOPI` whenever `MT = Float32`, so `collide!`'s return type depends on `batch_mode` for `GaussianPoissonSolver{Float32}` on Float32 beams -- the previous audit's U3-7, narrowed by the MT promotion (U3-4 fix) to the Float32-solver case rather than closed.
Mechanism: `luminosity = zero(MT)` (5490) then `luminosity += sum(@view lum[...]) / TWOPI * weight * klum` (5527-5531) promotes through `TWOPI::Float64` and Julia rebinds the variable; the wavefront route accumulates in `CUDA.zeros(MT, 1)` and scales by `weight * klum / TWOPI` stored in a `Vector{MT}` (1304, 1366, 1377), staying in `MT`. For the default `GaussianPoissonSolver{Float64}` `MT = Float64` on every beam type and nothing differs. A type-unstable host accumulator either way.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 result/comprehensive_audit_2026_10_18/probes/U3/probe5_f32_solver_return_type.jl` -> `GaussianPoissonSolver{Float32}, Float32 beams, batch_mode=sequential: typeof(lum) = Float64, lum = 1.0265266371987304e30` and `batch_mode=wavefront: typeof(lum) = Float32, lum = 1.0265266f30`; the default `GaussianPoissonSolver` (Float64) on the same Float32 beams returns `Float64` on both routes (1.0265267157896906e30 sequential, 1.0265267165130403e30 wavefront).

### LEAD U3-5 [Minor, confidence med, OUT OF HYPOTHESIS] src/tasks/strongstrong/pic_cuda.jl:4810-4826
Claim: `_cuda_pic_luminosity_wavefront_kernel!` (one `CUDA.@atomic accum[1] +=` per node over the whole plane stack) has no live launch: its only launch (3879) sits in `_cuda_pic_wavefront_luminosity_batched`, which is reached only when `_cuda_pic_batched_luminosity_enabled()` is true, and that function is the constant `false` (612) with no option behind it -- the shape the previous audit deleted as U3-5 because unlaunched device code is never compiled and the "every branch compiles as device IR" rule has no purchase on it.
Mechanism: `_cuda_pic_batched_luminosity_enabled() = false` at 612; the `if` at 3801 is its only consumer; no solver option, policy, or environment variable sets it. The kernel is also the one source of coarse run-to-run non-reproducibility the file header (lines 2-34) documents for the route, so if it is ever re-enabled that header is already true of it; if it is not, it is 17 lines of device code kept honest by nothing.
Repro: `grep -n "_cuda_pic_batched_luminosity_enabled\|_cuda_pic_luminosity_wavefront_kernel!" src/tasks/strongstrong/pic_cuda.jl` -> the definition returning `false`, the single `if` at 3801, one kernel definition and one launch inside that branch.

### LEAD U3-6 [Minor, confidence low, SEAM, OUT OF HYPOTHESIS] src/track/strong_beam_track.jl:760-772 vs src/elements/strong_beam.jl:785-798 (consumers in region: pic_cuda.jl:6260, 6458)
Claim: the uncoupled CP covariance-kick twins the slice kick kernels call are written in different algebraic forms -- device `exp(-T(0.5) * (xx*xx/a + yy*yy/d))` and `expterm / (T(TWOPI) * sigx * sigy)`, host `exp(-T(0.5) * (xx*xx/(sigx*sigx) + yy*yy/(sigy*sigy)))` and `expterm / T(TWOPI) / sigx / sigy` -- so the Gaussian slice kick's density (hence luminosity) and `pz` differ between backends by rounding for Float64 beams, while the suite's only bitwise cross-backend pin for this route is at Float32 (runtests.jl 32015-32018), where Float64 working-type differences vanish in coordinate rounding.
Mechanism: `sqrt(a)^2 != a` in the last bit and a left-to-right chain of divisions is not the division by a product; both files are outside this region and were read only to the extent quoted, so this is a seam note, not an audited finding, and no claim of Float64 bitwise identity for the Gaussian route was found to be violated.
Repro: on the host, call `Octopus._cp_covariance_kick(m, kbb, S, xx, yy, x, px, y, py, z, pz)` and `Octopus._cuda_cp_covariance_kick(m, kbb, S, xx, yy, x, px, y, py, z, pz)` with the same `StrongTransverseMoments{Float64,false}` and random arguments and count unequal `density`/`pz` results (not executed this session).

## Clean

What was compared against what, and what was measured:

- Deposit weights. `_cuda_pic_cic_weights` (4672-4686) against `_pic_cic_weights` (pic_cpu.jl 2475-2490): identical guard `!(0 <= u <= n-1)`, identical clamp `[1, n-1]`, identical fraction from the clamped base; `_cuda_pic_tsc_weights` (4688-4716) against `_pic_tsc_weights` (2518-2545): identical typed literals, closed-form `w3`, clamp `[1, n-2]`. Index ranges: CIC writes/reads nodes `base..base+1 <= n`, TSC `base..base+2 <= n`; the out-of-range return `(1, zeros)` deposits and interpolates nothing.
- Field stencils. `_cuda_pic_field_kernel!`, `_wavefront_`, `_batch_` (4828-4948) against `_pic_field!` (2824-2884): same one-sided boundary formulas in the same operation order, same second-order fallback on the ring inside the boundary, same fourth-order interior; `typeof(h)(1/12)` equals `T(1)/T(12)` at Float32 (probe1 (c)). The `_validate_pic_grid` floor of 5 nodes makes the `@inbounds` boundary indices safe (CPU comment 2834).
- Interpolation. All three CUDA interpolators (5182-5233, 5291-5336, 5380-5437) accumulate x-index outer, matching the CPU `for m, n` order; the quadratic basis `aL,aM,aR` is the Lagrange basis on t = 0, 1/2, 1 and `bL,bM,bR` its negated derivative (sums to zero), matching `_pic_interpolate_kick_quadratic` (2941-2973) and the sign convention of the linear `phiL - phiR` form. The CPU divides by `h` where the device multiplies by `inv(h)`, so coordinates differ by rounding there; no test in the region asserts PIC bitwise CPU/CUDA coordinates (the file header documents the route as non-reproducible; the parity pins are tolerances).
- Kick kernels. Every kick kernel in the region is grid-strided (the previous audit's U3-8 fix is in place at 5086-5107) and every launch goes through `_cuda_launch_capped!` (pic_cuda.jl 1964, 2206, 2229, 2240, 2389, 2403, 5512, 5519, 1412), which caps threads by `CUDA.maxthreads(kernel)` and rescales blocks. Hypothesis 2 therefore holds for the kicks; the one launch-shape hazard in the region is LEAD U3-1.
- Moment reduction. Slot layout of `values` (6161-6179, 6356-6374) against `_cuda_gaussian_moments_from_sums` (6034-6063) against `_slice_moments_finalize` (slicing.jl 982-1030): identical; `StrongTransverseMoments{T,COUPLED}(varx, covxy, vary, covxpx, covxpy, covpxy, covypy, qxx, covpxpy, qyy)` matches the struct's field order (strong_beam.jl 91-102) and `transverse_covariance`; the n == 0 branch matches `_slice_empty_moments`. `_shifted_second_moment`/`_shifted_cross_moment` are explicit `fma` on both backends (slicing.jl 815-819). Launch geometry is fixed at (256, min(cld(n,256),256)) and recorded (6129-6136); the fused kernel strides by the column's own block count (6348), so the two CUDA routes partition identically. Measured CPU vs CUDA on 200,003 Float64 particles (probe4 (a)): sigmas within 1-6 ulps, means and covariances within 6.2e-13 relative (3072 ulps of a mean that is 1e-3 of its coordinate scale) -- inside the "~1e-9 envelope from per-backend fold shapes" the suite declares for the sequential route (runtests.jl 31986-31991, lum_tol 1e-8). The fold shape, not FMA, is the documented residual.
- Lane folds. `_cuda_lane_z_moment_kernel!` POW=2 contracts `acc += d*d` to one FMA; the CPU `_lane_z_moment` accumulates with `fma(d, d, acc)` for that reason (slicing.jl 269-299, docs/history/cuda_lastbit_fma_2026_09_07.md) and the suite pins sigma bitwise (runtests.jl 31955). `_cuda_lane_indexed_sum_kernel!` and `_lane_indexed_sum_local` are bare adds in the same lane order. Division by the count is `T / Int` on both.
- Slicing methods. The method enumeration (5655-5667) matches slicing.jl 88-100 symbol for symbol including the aliases; `_cuda_equal_area_slices` (5712-5772) is line-identical arithmetic to `_longitudinal_slices_equal_area` (136-189) with the histogram bin rule transcribed from `_slice_bin`; `:specified` and `:normal_quantile` share `_gaussian_slice_boundaries` and clamp identically; `:equal_count` ranks with the same `sortperm` / `sort!(findall(flags); by=...)` (both stable, so ties order alike), cuts at the same `floor(Int, s*n/ns)`, and centres via `_lane_indexed_sum` on the host copy; the degenerate zero-width convention is slice 1 on both (5921-5922, 562-568). Float32 weights: `T(count)/T(total)` (CUDA) against `Int/Int -> Float64 -> T` (CPU) agree on 5,000,000 random pairs (probe1 (b)). Live masks: `_cuda_live_flags` uses the same `is_live` predicate; an all-dead beam throws before slicing (5652-5654); non-finite boundaries throw at `_cuda_slices_from_boundaries`/`_from_indices` as on the CPU.
- Luminosity reductions. `_cuda_pic_luminosity_overlap_partials_kernel!`'s power-of-two tree (4794-4801) is guarded: both launch sites use `_cuda_pic_threads(:luminosity)` (3834, 3922), validated power-of-two at construction and at resolution (interface.jl 141, 223), and the fallback is 256; the partials buffer is sized with the same `luminosity_threads` the cache entry is keyed by (2742-2745, 2764). The suite pins this (runtests.jl 14442-14455).
- Bounds reduction at warp multiples. 32, 64, 96, 128, 256, 512, 1024 threads: bitwise equal to the host fold (probe2, probe4 (b)); the `CuStaticSharedArray(T, (N, 32))` suffices for 1024.
- Workspace keys (hypothesis 3, seam read only). The PIC workspace key carries device, T, grid, luminosity grid, deposit methods, green type, longitudinal flag, batch mode, the three green-cache parameters and `interaction_grid` (725-782); the wavefront cache entry is keyed by capacity and `luminosity_threads` and rebuilt when either grows/changes (2743-2759); the sequential Gaussian route allocates `lum` and `moment_partials` per call, sized by the maximum over all slices (5483-5489), so no stale reuse was found in or adjacent to the region.
- Configuration consumers. `batch_mode` is validated to `(:sequential, :wavefront)` (interface.jl 1015) and both routes emit the `:gaussian_pair_schedule` receipt naming what ran (5466-5469); `_cuda_gaussian_moment_launch` records `resolved_by=:fixed_for_reproducibility`.
- No throw in any kernel body of the region (device IR hazard class 4): all `throw`s are in host functions (5648-5666, 5713, 5896, 5957); the in-kernel paths carry no interpolated messages.
- Previous audit's U3-1 (grid-dependent moments), U3-2 (thread cap), U3-3 (CIC order), U3-4 (Float32 working type), U3-5 (dead kick kernels), U3-6 (non-reproducibility undocumented: now the file header), U3-8 (grid stride) are closed in this tree; U3-7 persists in the narrowed form of LEAD U3-4.

## Unchecked

- The wavefront Gaussian launcher (pic_cuda.jl 1238-1420) and the PIC wavefront/indexed routes that call the region's kernels were read only at the lines quoted; their correctness is another unit's. The fused kernels' claim "bit-identical to the per-column kernel" (6314-6317) was verified by reading the stride rule only, not measured.
- `_cuda_gaussian_beambeam_kick_response`, `_forward_virtual_drift`/`_reverse_virtual_drift`, `_cuda_pic_luminosity_bounds_value` and `_pic_resolve_transverse_extent` were not read (outside the region); LEAD U3-6 is the one seam noted there.
- The run-to-run spread of the deposit atomics was not re-measured (documented in the file header; the previous audit measured it).
- The end-to-end effect of LEAD U3-2 on kicks was not measured, only the membership rules.
- Device-IR compilation of every branch was not re-run; the statement above (no throws in kernels) is from reading.
- Hypothesis 1's FMA question for the kick kernels (`Kx += w * (...)` fuses on the device) was judged by reading against the suite's tolerance pins; no PIC bitwise CPU/CUDA coordinate pin exists to be violated, and none was added or measured here.
