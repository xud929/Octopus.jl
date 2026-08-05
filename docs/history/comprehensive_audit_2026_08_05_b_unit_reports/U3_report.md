# U3 — reading-unit report

**Region:** `src/tasks/strongstrong/pic_cuda.jl`, lines **4000–6009** (2,010 lines), at
`HEAD = 7de4d81`.

**Briefed hypotheses:** (a) moment/kick kernel numerics in ~5490–5966; (b) reduction-order
dependence on the launch decomposition; (c) device-IR compilability of every branch.

**Provenance summary.** Every line 4000–6009 was read. Fifteen probe scripts were written
and executed on the real device (RTX 4500 Ada, CUDA 13.0, Julia 1.12) in
`…/scratchpad/audit/`; no repository file was modified. Cross-file reads for reference only:
`pic_cpu.jl` (`_pic_field!`, `_pic_interpolate_kick`, `_pic_interpolate_kick_quadratic`, the
node/quadratic kick loops), `slicing.jl` (`_slice_transverse_moments`, `_shifted_*_moment`,
`_slice_bin`), `gaussian.jl` (`_apply_slice_kick_one!`), `interface.jl` and `Policies.jl`
(launch-config resolution), `Contracts.jl` (the launch-geometry sweep).

---

## The provenance note this unit was given

The brief flagged 5490–5966 as the one block the previous audit left on its honest
remainder ("agent-read, backed by U2's bit-reproduction checks and measured CPU parity
7.2e-15..1.4e-14"). Those ~450 lines were read line by line and then **measured** against
three independent references: the CPU twin, an exact-arithmetic (`BigFloat`) population
moment, and an exact-integer construction that would expose any dropped thread in the tree
reduction. The arithmetic is correct and the tree reduction is exact. What the earlier
"bit-reproduction" framing did **not** cover, and what this unit found, is that the
*result depends on the launch grid* (U3-1) and that the whole route *is not run-to-run
bit-reproducible at all* (U3-6). Both are measured below.

---

## LEADS

### LEAD U3-1 [medium, confidence high] src/tasks/strongstrong/pic_cuda.jl:5564-5578, 5660-5668
Claim: The CUDA slice transverse moments change with the launch grid rather than only with
the data, which is exactly the invariant the CPU twin was rewritten to guarantee (U5-2,
"the chunk-ordered fold must not depend on the worker count"); nothing on the GPU side
enforces or tests it.
Mechanism: `_cuda_gaussian_moment_launch` (5660) derives `threads` and `blocks` from the
active `ResolvedCUDAExecutionPolicy`, so the *partition* of a slice's particles across
threads and blocks — and hence the summation order of `Σdx`, `Σdx²`, `Σdx·dpx` … — is a
function of the policy, not of the beam. Inside a block the fold is the shared-memory tree
(5717-5727), whose shape is `blockDim().x`; across blocks the host folds
`sum(host_partials; dims=2)` (5575) over `blocks` columns. The CPU deliberately pinned both:
a fixed `_REDUCTION_CHUNKS` grid and a serial/chunked decision by *data size only*. The CUDA
path pinned neither. `_active_cuda_launch` also lets an explicit `blocks` exceed 256, so the
block count is user-reachable too.
Repro: with a 200,003-particle single slice (`randn` beam, seed 20260805), call
`Octopus._cuda_slice_transverse_moments` inside
`Octopus._with_resolved_policy(Octopus.ResolvedCUDAExecutionPolicy(0, threads, blocks))`
and compare the returned fields bitwise across configurations
(`scratchpad/audit/p2_launch.jl`, `p3b_blocks_large.jl`). Measured, all against the
threads=256/blocks=:auto result on identical data:

| varied | `varx` ulps | `covxpx` ulps | `mpy` ulps | `sx` ulps |
|---|---|---|---|---|
| threads 64  | 2  | 44   | 192 | 1 |
| threads 128 | 1  | 12   | 256 | 0 |
| threads 256 | 0  | 0    | 0   | 0 |
| blocks 512  | 5  | 2303 | 48  | 3 |
| blocks 1024 | 15 | 5502 | 192 | 7 |

End to end (`p4_e2e.jl`, 200,003 particles/beam, 5 slices, `GaussianPoissonSolver`,
`longitudinal_kick=true`): threads 64 vs 256 gives `max|Δpx| = 4.26e-18`
(`6.80e-15` relative), `Δlum/lum = -4.6e-16`. Block count alone changes nothing whenever
`N ≤ blocks·threads` (each thread then owns ≤1 particle and the partition is the same
contiguous 256-chunking), which is why `p3_blocks.jl` at N=1,000/20,000 reports 0 ulps —
the dependence is on the *thread* count in production sizes and on the *block* count only
above `blocks·threads` particles per slice.
Blast radius (seam, not chased): `gaussian_pic_cuda.jl:175-188, 290-291` reuses
`_cuda_gaussian_moment_launch`, `_cuda_launch_gaussian_moment_partials!` and
`_cuda_gaussian_moments_from_sums`, so the hybrid solver inherits the same property.
No test pins it: `test/runtests.jl:1994` sweeps threads only to assert `ispow2` on the
*luminosity* family, and `Contracts.jl:484`'s `(64,128,256,512)` sweep is on fused
*tracking*, not on strong-strong moments.

### LEAD U3-2 [medium, confidence high] src/tasks/strongstrong/pic_cuda.jl:5158, 5165, 2101, 1214
Claim: `threads = 512` — a value the repository's own launch-geometry contract sweeps and
which the example harness accepts from `OCTOPUS_CUDA_THREADS` — makes **every** strong-strong
CUDA route (Gaussian sequential, Gaussian wavefront, and PIC) fail at kernel launch with a
register-limit error; the configuration validator checks only the 1024 thread ceiling.
Mechanism: `_cuda_gaussian_moment_launch` (5664) deliberately caps threads at 256 ("Fourteen
shared Float64 accumulators per thread make 256 the portable ceiling"), but the *kick*
kernels take the raw policy thread count: `_cuda_slice_kick_kernel!` is launched with
`_active_cuda_launch(n).threads` (5158, 5165), `_cuda_gaussian_fused_kick_kernel!` with
`kick_launch.threads` (1214), and `_cuda_pic_kick_pair_indexed_longitudinal_kernel!` with
`_cuda_pic_threads(:kick)` (2101). Those kernels need 130–163 registers/thread, so
`regs × 512 > 65536` registers/block on every Ampere/Ada-class device. The only validation
is `_resolve_cuda_pic_configuration` (`interface.jl:207-213`), which compares against
`DEVICE_ATTRIBUTE_MAX_THREADS_PER_BLOCK` (=1024) and cannot see register pressure. This is
the "correct check, never executed" class: the strong-strong contracts pin
`cuda_threads = 128` (`Contracts.jl:139`) and `= 64` (`:2332`), so 512 is never exercised on
this path.
Repro: `scratchpad/audit/p5_threads512.jl` —
`execute!(StrongStrongTask((ip,),(ip,); policy=CUDAExecutionPolicy(launch=CUDALaunchConfig(threads=512))), b1, b2; turns=1)`.
Measured on RTX 4500 Ada:

```
Gaussian batch_mode=:sequential threads=384 OK ; threads=512 FAIL
    Block register count exceeds device limit (149 regs/thread * 512 = 76288 > 65536)
Gaussian batch_mode=:wavefront  threads=384 OK ; threads=512 FAIL  (163 regs/thread)
PIC (any route)                                threads=512 FAIL  (130 regs/thread,
    kernel _cuda_pic_kick_pair_indexed_longitudinal_kernel!, pic_cuda.jl:2101)
```

Mitigating: the failure is loud and lands before any particle is written
(`p6_pickernel.jl` reports `beam mutated before the throw? false`). The remedy is either a
`maxregs`/thread cap on the kick launches mirroring 5664, or a resolve-time check against
the kernel's own register requirement.

### LEAD U3-3 [low-medium, confidence high] src/tasks/strongstrong/pic_cuda.jl:4885-4898, 5073-5090
Claim: The CIC branch of `_cuda_pic_interpolate_field` and `_cuda_pic_interpolate_kick` is
hand-unrolled in the *transposed* nesting relative to the CPU twin, so 22.5% of CIC
interpolations differ from the CPU in the last bits for a purely notational reason — the
same class of gratuitous divergence the 2026-08-05 U2-3 fix removed from `_pic_tsc_weights`.
Mechanism: CPU `_pic_interpolate_kick` (`pic_cpu.jl:1877`) accumulates
`for m in eachindex(wx), n in eachindex(wy)` → `(1,1),(1,2),(2,1),(2,2)` (x index outer).
The CUDA CIC branch is written out as `wx1*wy1`, `wx2*wy1`, `wx1*wy2`, `wx2*wy2` →
`(1,1),(2,1),(1,2),(2,2)` (y index outer). The two middle terms are swapped, so the
four-term running sum is grouped differently. The TSC branches of both backends use
`for m in 1:3, n in 1:3` and agree; and this file's own
`_cuda_pic_interpolate_kick_quadratic` (4991) uses `for m in 1:2, n in 1:2` and therefore
*already matches* the CPU. Three CIC interpolators in one file, two transposed and one not.
Repro: `scratchpad/audit/p14_cic_order.jl` compares
`((0+t11)+t12+t21)+t22` (CPU order) with `((0+t11)+t21+t12)+t22` (CUDA order) over 200,000
random CIC weight/field draws. Measured: **44,940 / 200,000 (22.5%)** samples differ,
max ulp gap 32,768, max relative gap 4.914e-12. The end-to-end effect is buried under the
deposition atomics (U3-6), so this shows up as part of the residual 9e-17 relative CPU/CUDA
coordinate gap rather than as a separate signal.

### LEAD U3-4 [low, confidence high] src/tasks/strongstrong/pic_cuda.jl:5580-5584
Claim: For a `Float32` beam the CPU builds the slice moments in `Float64` and the CUDA
backend builds them in `Float32`, so the two backends disagree by 5.3e-7 relative on the
kick — five orders of magnitude worse than the 1.1e-13 they achieve for `Float64` beams —
purely because the two twins choose their working type differently.
Mechanism: CPU `_slice_transverse_moments` (`slicing.jl:612`) takes
`T = promote_type(eltype(x), typeof(min_sigma))`. `GaussianPoissonSolver()` defaults to
`GaussianPoissonSolver{Float64}`, so `min_sigma::Float64` and the CPU silently computes the
moments — and hence `StrongTransverseMoments{Float64}` and the whole kick — in double
precision even for a single-precision beam. The CUDA
`_cuda_gaussian_moments_from_sums` (5584) takes `T = eltype(sums) = eltype(rep.x)`, i.e.
`Float32`, and never sees `min_sigma`'s type.
Repro: `scratchpad/audit/p7_f32.jl` (overwritten in the shared scratch after the run;
reconstruct as: identical 20,000-particle beams on both backends, default
`GaussianPoissonSolver(slicing=nslices=3 normal_quantile)`, compare `px` kick). Measured:

```
beam Float32 : CPU moments StrongTransverseMoments{Float64}  sx=1.0000351675065032e-4
               GPU moments StrongTransverseMoments{Float32}  sx=1.0000351e-4
               max|kick_gpu-kick_cpu| / max|kick_cpu| = 5.2683e-07
beam Float64 : both Float64                                  = 1.1101e-13
```

Whichever convention is right, the two twins must pick the same one. (Constructing
`GaussianPoissonSolver{Float32}(...)` would align them; nothing enforces or documents that.)

### LEAD U3-5 [low, confidence high, OUT OF HYPOTHESIS] src/tasks/strongstrong/pic_cuda.jl:4661-4738
Claim: `_cuda_pic_kick_indexed_kernel!` (4661-4696) and
`_cuda_pic_kick_indexed_longitudinal_kernel!` (4698-4738) — 78 lines — are launched from
nowhere in the repository, so no gate ever device-compiles them and they can rot silently;
they also duplicate the live `_cuda_pic_apply_indexed_kick!` /
`_cuda_pic_apply_indexed_longitudinal_kick!` (4804, 4837) line for line.
Mechanism: dead device code is not compiled by Julia until launched, so the "every branch
must compile as device IR, throws included" rule (Measured Lesson 2) has no purchase on it;
and duplicated kick arithmetic is exactly the hand-copied knowledge the Hard-Won Rules
forbid — a future fix to the live pair would leave these two silently stale.
Repro: `grep -rn "_cuda_pic_kick_indexed_kernel\|_cuda_pic_kick_indexed_longitudinal_kernel" .`
returns exactly the two `function` lines and nothing else. They still compile today —
`scratchpad/audit/p10_deadcompile.jl` launches both directly via `CUDA.@cuda launch=false`
for `T ∈ {Float32,Float64}` × `method_code ∈ {1,2}`: 8/8 "compiles+runs". So the lead is
"unreachable and ungated", not "already broken".

### LEAD U3-6 [low-medium, confidence high, OUT OF HYPOTHESIS] src/tasks/strongstrong/pic_cuda.jl:4002-4010, 4034-4051, 4077-4094, 4139-4156, 4463
Claim: The CUDA PIC route is **not** run-to-run bit-reproducible: the same process, the same
input beam and the same launch configuration produce different luminosity and different
particle coordinates on repeated calls. Nothing in the region documents this.
Mechanism: every deposition writes with `CUDA.@atomic charge[...] += w`
(`_cuda_pic_deposit_drifted_plane_kernel!` 4002-4010/4034-4051,
`_cuda_pic_deposit_drifted_indexed_plane_kernel!` 4077-4094, `_cuda_pic_deposit_point!`
4139-4156). Floating-point atomic addition is not associative and the hardware ordering of
concurrent atomics is not fixed, so the charge grid — and everything downstream of it —
varies between launches. `_cuda_pic_luminosity_wavefront_kernel!` (4463) adds a second,
coarser source: a *single* `CUDA.@atomic accum[1] +=` over the whole `(nx+1)(ny+1)·npairs`
plane stack. The indexed wavefront route avoids that one by using the shared-memory partials
kernel (4416), and its luminosity was indeed stable in the measurement below — the
coordinates still were not.
Repro: `scratchpad/audit/p13_repro.jl` — 60,000 particles/beam, grid 32², 4 slices,
`green_cache=:none`, six repetitions of the same `collide!` in one process, threads=256:

```
route                                  lum bit-identical (6 runs)   px bit-identical
wavefront, non-indexed (atomic accum)  false  spread/mean 3.08e-16  false  rel 4.05e-15
wavefront, indexed (shmem partials)    true                          false  rel 1.90e-15
sequential                             false  spread/mean 1.54e-16  false  rel 2.28e-15
```

The magnitudes are at rounding level; the point is that "bit-reproducible" is not a property
this route has, and any claim resting on it (including the previous audit's
"U2's bit-reproduction checks") needs re-reading in that light.

### LEAD U3-7 [low, confidence high, OUT OF HYPOTHESIS] src/tasks/strongstrong/pic_cuda.jl:5136, 5173-5177
Claim: For a `Float32` beam, `_cuda_gaussian_collide_sequential!` returns a `Float64`
luminosity while `_cuda_gaussian_collide_wavefront!` returns `Float32` — the return type of
`collide!` depends on `solver.batch_mode`, which is documented as a scheduling choice.
Mechanism: `luminosity = zero(T)` (5136) is then updated by
`luminosity += sum(@view lum[...]) / TWOPI * slices1.weight[i] * klum2` (5173-5177). `TWOPI`
is a `Float64` constant, so the right-hand side promotes and Julia rebinds `luminosity` to
`Float64` on the first iteration. The wavefront path accumulates into
`luminosity_acc = CUDA.zeros(T, 1)` (1128) and stays in `T`. Also a type-unstable accumulator
in a host loop.
Repro: `scratchpad/audit/p15_f32routes.jl`, `Float32` beams — `Gaussian seq coupled lk=1`
prints `lum=2.3136926291102045e29` (Float64 formatting) while `Gaussian wf coupled lk=0`
prints `lum=2.3136927e29` (Float32). Same split appears on the PIC side between the
gathered (`iw=0`) and indexed routes.

### LEAD U3-8 [low, confidence med, OUT OF HYPOTHESIS] src/tasks/strongstrong/pic_cuda.jl:4774-4802
Claim: `_cuda_pic_kick_pair_indexed_longitudinal_kernel!` is the only kick kernel in the
region without a grid-stride loop, so it is correct only because its single launcher happens
to size `blocks = cld(max(len1,len2), threads)`; any future block cap silently drops the tail.
Mechanism: its non-longitudinal twin `_cuda_pic_kick_pair_indexed_kernel!` (4740) wraps the
body in `while index <= max(length(idx1), length(idx2)) … index += stride`; the longitudinal
version (4784-4800) computes `index` once and returns. The launcher at 2093-2113 currently
supplies full coverage, but the file already caps blocks elsewhere
(`_CUDA_PIC_BOUNDS_PARTIAL_BLOCKS = 64` at 478, `min(cld(n, threads), 256)` in
`_active_cuda_launch`), so the asymmetry is a live trap rather than a style point. Failure
mode would be silent: unkicked particles, no warning — the "loud beats silent" rule's
opposite.
Repro: no failure at HEAD. To confirm the exposure: launch the kernel directly with
`blocks = 1` and `threads = 32` on `length(idx1) = 1000` and observe that only 32 particles
are kicked, while the same call to `_cuda_pic_kick_pair_indexed_kernel!` kicks all 1000.

---

## CLEAN LIST — what was checked, and the evidence

**C1. Moment arithmetic is mathematically correct and matches the host twin term for term.**
Read `_cuda_gaussian_moment_partials_kernel!` (5670), `_cuda_gaussian_fused_moment_kernel!`
(5839) and `_cuda_gaussian_moments_from_sums` (5580) against `slicing.jl`'s
`_slice_transverse_moments` (609). The accumulator slots agree
(`values[11..14] = dx·dy, dx·dpy, dpx·dy, dpx·dpy`, consumed as
`covxy, covxpy, covpxy, covpxpy` with the matching mean offsets), the anchor is `idx[1]` on
both, and both call the *same* `_shifted_second_moment` / `_shifted_cross_moment` helpers,
so the shifted-origin algebra cannot drift. `StrongTransverseMoments` is constructed with an
identical 10-argument order on both sides.
Measured (`p1_moments.jl`, N=200,003, `COUPLED ∈ {false,true}`): GPU vs CPU relative error
≤ 6.5e-16 on every mean/sigma and ≤ 3.5e-13 on the covariances (the covariance gap is
cancellation in the shifted formula, present identically on both backends).

**C2. The covariance denominator is the population `n`, on both backends, and that is
the right answer for this algorithm.** Independent `BigFloat` reference over the same data:
`varx_pop = 9.97842239083283260e-07` — which the GPU reproduces **exactly** — against
`varx_(n-1) = 9.97847228244587124e-07`, differing in the 5th significant digit. No
Bessel correction anywhere; host and device agree.

**C3. The shared-memory tree reduction is exact for every block size, including
non-powers-of-two, odd sizes, primes, and non-multiples of 32 — there is no tail bug.**
The fold `offset = (active+1)÷2; if tid ≤ active÷2: shared[tid] += shared[tid+offset]`
folds `[offset+1 … active]` (exactly `active÷2` elements) into `[1 … active÷2]` and sets
`active = ceil(active/2)`, which is lossless for any starting `active`.
Measured (`p11_tree.jl`): with `x[i] = i` so that `Σdx = N(N-1)/2` and `Σdx² = Σ(i-1)²` are
exactly representable, over `N ∈ {1237, 100003}` × `threads ∈ {1,2,3,5,7,31,32,33,96,127,128,255,256}`
× `blocks ∈ {1,3,7,64}` = **104 configurations, 0 lossy** (absolute error exactly 0.0 in both
sums, anchor row exactly 1.0 in all). `__syncthreads()` placement is correct: it sits outside
the divergent `if`, and the loop bound `active` is uniform across the block.

**C4. The block-count reduction is consistent between the two CUDA Gaussian routes.**
The host path folds with `sum(host_partials; dims=2)` (5575); the fused path folds with
`_cuda_gaussian_reduce_partials_kernel!` (5743), a plain `for block in 1:nblocks`. Measured
(`p12_lum_and_reduce.jl`, 14 stats × 37 blocks of random data): **0 / 14** stats differ, and
both equal a left-to-right `foldl`. So sequential and wavefront produce identical moments at
the same policy — confirmed end to end in `p4_e2e.jl` (`max|Δpx| = 0.0` between
`:sequential` and `:wavefront` at threads=256; only luminosity differs, at 1.5e-16, from the
different accumulation shape).

**C5. `_cuda_gaussian_fused_moment_kernel!` really is partition-identical to the per-column
kernel.** `stride = nb * threads` with `nb = block_counts[col]` and
`position = (bx-1)*threads + tid` reproduce exactly the `gridDim().x * blockDim().x` stride
of the per-column kernel when it is launched with `blocks = nb`; the caller sets
`block_counts[col] = _cuda_gaussian_moment_launch(len).blocks` (1146-1157) and
`moment_threads = _cuda_gaussian_moment_launch(1).threads` (1118), which is `n`-independent.
Blocks beyond `nb` return before writing, and the reduce kernel reads only `1:nb`, so no
uninitialised partial is ever summed (`partials` is `CUDA.zeros`, 1075).

**C6. No device-reachable throw carries an interpolated message; no non-isbits capture.**
Every `throw`/`error` in 4000-6009 (13 sites, listed by
`awk 'NR>=4000&&NR<=6009' … | grep -n "throw\|error(\|\$("`) is in a *host* function —
`_cuda_longitudinal_slices` (5225-5243), `_cuda_equal_area_slices` (5290),
`_cuda_slices_from_boundaries` (5486, 5520), `_cuda_slices_from_indices` (5449, 5471) — or in
the `_HAS_CUDA == false` stubs (6004, 6007). The device-reachable
`_cuda_gaussian_moments_from_sums`, called from `_cuda_gaussian_build_moments_kernel!` (5819),
is throw-free and type-stable across its `n == 0` / `n > 0` branches.
Measured: all 5 PIC route families + `:equal_area` + `:equal_count` slicing + 3 Gaussian
configurations compile and run in **Float32** as well as Float64 (`p15_f32routes.jl`,
10/10 ok, all luminosities finite).

**C7. CPU/CUDA parity of every kick, field, deposit and luminosity kernel in the region.**
`p8_kick_parity.jl` — 6,000 particles/beam, grid 32², 4 slices, `green_cache=:none`, CPU vs
CUDA over `interaction_grid ∈ {slice_pair, node, source_slice}` ×
`deposit_method ∈ {CIC, TSC}` × `slice_interpolation ∈ {linear, quadratic}` ×
`longitudinal_kick ∈ {true,false}` × `batch_mode ∈ {wavefront, sequential}` (48 cells).
Every *supported* cell passes at **relative max coordinate error ≤ 1.6e-16** and relative
luminosity error ≤ 3.1e-16. The rejected cells all throw documented `ArgumentError`s
(`:source_slice` unimplemented on CUDA; `:node` needs the indexed wavefront route; `:node`
+ `:quadratic` unimplemented) — loud, not silent.
`p9_routes.jl` extends this to the **full 64-way** sub-route matrix
(`batch_mode` × `cuda_indexed_wavefront` × `cuda_async` × `cuda_batch_fft` ×
`cuda_wavefront_fft` × `longitudinal_kick`): **64/64 ok, all at 8.99e-17 relative**. This
exercises `_cuda_pic_kick_kernel!`, `_cuda_pic_kick_longitudinal_kernel!`,
`_cuda_pic_kick_pair_indexed*`, `_cuda_pic_kick_node_kernel!`,
`_cuda_pic_kick_quadratic_kernel!`, all three field kernels, all three Green/spectral
kernels, all three deposit kernels and both luminosity kernels.

**C8. `_cuda_pic_field_kernel!` / `_cuda_pic_field_wavefront_kernel!` /
`_cuda_pic_field_batch_kernel!` (4469, 4505, 4548) transcribe `pic_cpu.jl:_pic_field!`
exactly**, including the one-sided boundary stencils, the second-order fallback ring at
`j = 2` and `j = ny-1` under `fourth`, the interior `1/12` fourth-order stencil, and the
left-to-right association `T(0.5) * hyi * (…)`. The CPU's `fourth && ny >= 5` guard and the
CUDA `fourth && j >= 3 && j <= ny-2` guard select the same branch for every `ny` (checked
for `ny = 4, 5` by hand; `_validate_pic_grid` forces `≥ 5` anyway).

**C9. The quadratic longitudinal weights are correct and match the CPU.**
`aL = 2t²-3t+1, aM = 4t-4t², aR = 2t²-t` sum to 1 exactly and collapse to `(1,0,0)` /
`(0,0,1)` at the slice boundaries; `bL = 3-4t, bM = 8t-4, bR = 1-4t` sum to **0** (so the
mesh potential's additive constant cancels, as the docstring claims) and satisfy
`b = -da/dt` term by term, which is what makes `Kz = -∂φ/∂t` and reduces to the two-node
`φL - φR` at `t = 1/2`. Character-for-character identical to
`pic_cpu.jl:_pic_interpolate_kick_quadratic` (1917), including the loop nesting.

**C10. The luminosity overlap tree reduction's power-of-two requirement is real, and the
guard that enforces it is airtight.** `_cuda_pic_luminosity_overlap_partials_kernel!`
(4432-4445) uses `step = blockDim().x ÷ 2` halving, which is lossy for non-powers-of-two.
Measured (`p12_lum_and_reduce.jl`, 9×7 unit grid, exact overlap = 63.0):
threads 16/32/64/128 → 63.0 (exact); threads **24/48/96 → 42.0, losing 33% of the overlap**.
So the guard is load-bearing — and it holds: `ispow2` is checked at
`CUDAPICLaunchConfig` construction (`interface.jl:122`) *and* after inheritance in
`_resolve_cuda_pic_configuration` (`:204`), which is the sole constructor of
`ResolvedCUDAPICLaunchConfig`; with no config installed `_cuda_pic_threads` falls back to a
hard-coded 256. There is no reachable path to a non-power-of-two luminosity blockDim.

**C11. `_cuda_pic_bounds_block_reduce` (4177) and its four callers are sound.** The warp
shuffle uses the full mask and every launcher supplies a multiple of 32 (`threads = 256`
at 1587 for the accumulating kernels, `threads = block_cap = 64` at 1631/1635 for the
finalizers), so no inactive lane participates. `nwarps = cld(blockDim().x, 32)` correctly
neutralises the unwritten shared slots; `CuStaticSharedArray(T,(N,32))` is used once per
kernel so no barrier is missing. `_cuda_pic_init_wavefront_bounds_partials_kernel!` (4210)
seeds `row = (index-1) % 12 + 1` with `Inf`/`-Inf`, which is correct exactly because
`bounds_partials` is allocated `(12, 64, 2·npairs)` (2441); the 8-row kernels leave rows
9-12 at their neutral seeds and the 8-row finalizer never reads them.

**C12. `_cuda_equal_area_histogram_kernel!` (5270) is a faithful inline of the CPU
`_slice_bin`.** Read against `slicing.jl:172`: same `d = (zi - zmin)/width`, same
`!(d > -Inf && d < Inf)` NaN/Inf rejection (deliberately comparison-based, not `isfinite`),
same `clamp(… + 1, 1, bins)`. `unsafe_trunc(Int, floor(d))` equals `floor(Int, d)` for every
`|d| < 2^63` because `floor(d)` is already integer-valued — the comment's claim holds. The
bin counter is an **integer** atomic, so the histogram itself is deterministic.

**C13. `_cuda_slice_kick_kernel!` (5763) and `_cuda_gaussian_fused_kick_kernel!` (5934) are
line-for-line transcriptions of `gaussian.jl:_apply_slice_kick_one!` (147)**, including the
untyped `0.5` literal in the `pz` synchro-beam term, the `px0/py0/pz0` save-restore, and the
`LONGITUDINAL ? … : pz = pz0` branch. The `lum` buffer is written by exactly one of the two
per-pair launches (`Val(!sample_beam1)` / `Val(sample_beam1)`, 5163/5170) and both go to the
default stream, so there is no race. Per-particle kicks are independent, so the fused
ordering really is bit-identical to the per-slice ordering (confirmed in C4).

**C14. Accumulation significance.** With the production decomposition (2.56M particles,
15 slices, threads=256, blocks=256) each thread's naive partial covers ≈ 39 terms before the
exact tree fold, versus 64 chunks of ≈ 40,000 naive terms on the CPU. The GPU is the more
accurate of the two here — visible in C2, where the GPU matched the `BigFloat` population
variance exactly and the CPU did not. No compensated summation is needed at this decomposition.

**C15. Green/spectral index arithmetic** (`_cuda_pic_apply_green_batch_kernel!` 4359,
`_cuda_pic_multiply_spectral_stack_kernel!` 4379, `_cuda_pic_apply_green_plane_kernel!` 4398):
`plane0 < 2 ? green12 : green21` matches the 4-plane batch layout, `green_plane = plane0÷2+1`
matches the two-planes-per-Green stacking, and all three recover `(i,j)` from the linear
index with the same column-major decomposition. Covered by C7's 64-way sweep.

---

## Not checked, and why

- **The CPU-side halves of the seams.** `_cp_covariance_kick` / `_soft_gaussian_covariance`
  vs `_cuda_cp_covariance_kick` (`track/strong_beam_track.jl`), `_forward_virtual_drift` /
  `_reverse_virtual_drift`, `_gaussian_moments_finite`, `is_live`,
  `_slice_interpolation_parameters`, `_pic_luminosity_grid`. All are outside the region and
  outside the file; they are device-reachable from region kernels and evidently compile and
  agree (C7, C13 measured 1e-16 parity), but their internals were not read. Seam — the
  auditor's.
- **`gaussian_pic_cuda.jl`'s reuse of the moment machinery** (lines 175-188, 290-291). Named
  as the blast radius of U3-1; not opened.
- **Lines 1–3999 of `pic_cuda.jl`.** Read only where a region kernel's launcher had to be
  identified (671-695, 1057-1230, 1580-1640, 1723-1965, 2093-2113, 2410-2500, 3530-3700).
  Those excerpts are not claimed as audited.
- **Multi-GPU / multi-device behaviour, and devices other than RTX 4500 Ada.** U3-2's
  register numbers (149/163/130 regs/thread) are device- and compiler-version-specific; the
  *existence* of the failure at `threads=512` will hold on any device with a
  65,536-register-per-block limit, which is every Ampere/Ada/Hopper part, but the exact
  threshold between 384 (passes here) and 512 (fails here) was not swept on other hardware.
- **Whether U3-1's launch dependence is large enough to matter physically over many turns.**
  Single-collision effect measured (6.8e-15 relative in `px`); the turn-to-turn amplification
  in a chaotic beam-beam map was not measured. That is a Phase-9-style study, not a reading
  unit's.
- **Performance.** No timing was taken; nothing in this report claims a performance effect.
  U3-2's remedy (a thread cap or `maxregs`) has an occupancy cost that was not measured.
