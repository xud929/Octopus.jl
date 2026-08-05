# U2 report — pic_cuda.jl lines 3000–5966 (commit 6a3f39a)

## Coverage

Read every line of `/cfs/ad/dxu/Library/Julia/Octopus/src/tasks/strongstrong/pic_cuda.jl`
3000–5966 (chunks 3000–3499, 3500–3999, 4000–4519, 4520–5019, 5020–5499,
5499–5966; the 5490–5966 Gaussian moment/kick region was read within the last
two chunks and re-examined function by function). Cross-read for twin/launch
verification (context, not full-line audit): pic_cuda.jl 60–170, 195–330,
405–470, 540–720, 1452–1500, 1520–1727, 1855–2130, 2390–2545, 2969–2998;
pic_cpu.jl 100–260, 356–400, 480–660, 880–1000, 1280–1500, 1719–1930;
slicing.jl 104–520, 560–720; gaussian.jl 1–200; gaussian_pic.jl (moment spot
checks); elements/strong_beam.jl 75–130, 590–660; track/strong_beam_track.jl
300–400; interface.jl 100–300, 720–1160; test/runtests.jl 1855–1911,
3087–3135, 4120–4230.

Probes (all CPU-only, run `julia --startup-file=no --project=<repo> <script>`):
- `scratchpad/U2/probe_equal_area_and_reductions.jl` (P1 histogram membership,
  P2 TSC w3 drift, P3 reductions). NOTE: P3's ceil-halving number in this
  combined script is invalid — the script itself hit the Core.Box shared-`v`
  closure bug this codebase documents twice; superseded by:
- `scratchpad/U2/probe_ceil_halving.jl` — isolated, correct.

## Leads

### U2-1 — gathered CUDA quadratic/node kick launchers crash for `longitudinal_kick=false` (docstring says supported)
- Files/lines: pic_cuda.jl:1906,1908 (`_cuda_pic_launch_kick_quadratic!` passes
  `out.pz`, `field.pz` unconditionally); pic_cuda.jl:1716-1717
  (`_cuda_pic_launch_kick_node!`, same); root cause interplay:
  `_cuda_pic_extract_slice` (pic_cuda.jl:~646-668) builds coords WITHOUT a
  `pz` field when `solver.longitudinal_kick == false`, and every gathered
  route passes `solver.longitudinal_kick` (pic_cuda.jl:101-102, 285-286).
- Reachable call sites: pic_cuda.jl:1486 (`_cuda_pic_interaction!`, the
  sequential non-async route, `cuda_async=false`); 3269/3275 (gathered
  quadratic batched-FFT, i.e. sequential `cuda_batch_fft` route line ~109-118
  and wavefront with `cuda_indexed_wavefront=false` line ~296-330); the node
  gathered route reaches 1716 the same way. The production default (indexed
  wavefront, all four cuda_* flags default true) passes `rep.pz` (full
  Phase6DRep always has pz) and is NOT affected.
- Violated invariant: a configuration that passes `_validate_pic_solver`
  (`slice_interpolation=:quadratic` or `interaction_grid=:node`, with
  `longitudinal_kick=false` — all individually legal, no cross-validation)
  must run or be rejected loudly at validation. Instead the launcher throws
  `ErrorException("type NamedTuple has no field pz")` on the host at argument
  marshalling. The CPU twin handles the identical configuration (every `.pz`
  access guarded by `solver.longitudinal_kick`, pic_cpu.jl:614-620, 636-642).
  Docstring contradiction (defect class 10): interface.jl:1004-1009 states
  ":quadratic runs on the sequential non-async route and on the batched-FFT
  routes" and names the ONE unsupported combination as async+non-batched —
  `longitudinal_kick=false` is not excluded.
- Severity: medium (loud crash of a documented-legal config; no silent
  corruption).
- Repro recipe (GPU, for the driving auditor):
  `PICPoissonSolver(grid=(32,32), slice_interpolation=:quadratic,
  longitudinal_kick=false, cuda_async=false)` (or `cuda_async=true,
  cuda_batch_fft=true, cuda_indexed_wavefront=false`), then
  `collide!(solver, beam1, beam2, CUDABackend)` → expect
  `type NamedTuple has no field pz` from `_cuda_pic_launch_kick_quadratic!`.
  Same with `interaction_grid=:node` via `_cuda_pic_launch_kick_node!`.
  No CPU probe possible (path requires device arrays); claim is static but the
  field-access mismatch is mechanical: 5-field NamedTuple vs `.pz` access.

### U2-2 — `:equal_area` histogram membership diverges CPU vs CUDA (R8 claim itself is TRUE)
- Files/lines: CUDA kernel pic_cuda.jl:5222-5244 (edge-comparison membership,
  drops rounding orphans); CPU `_slice_bin` slicing.jl:174-178 via
  `_threaded_histogram` slicing.jl:246-283 (pure `clamp(floor((z-zmin)/width)+1,
  1, bins)`, counts every finite live particle).
- Verified TRUE first: the R8 one-pass kernel is bit-identical to the per-bin-
  mask oracle. Statically: `lo(b+1)` and `hi(b)` are the same expression
  `T(zmin + b*width)`, fl is monotone so the intervals partition exactly, the
  correction loops converge to the unique comparison bin, last bin closed,
  orphans dropped — and test/runtests.jl:3087-3135 pins kernel == mask oracle
  on quantized and non-quantized data. Degenerate `zmin == zmax` goes to
  slice 1 on both backends (pic_cuda.jl:5253-5256 → `_cuda_degenerate_slices`
  5486-5503; CPU slicing.jl:113-119) — R7 upheld.
- The lead: the ORACLE is the old CUDA mask semantics, not the CPU rule. CPU
  assigns by division+clamp; CUDA by edge comparisons. Measured (probe P1,
  real `Octopus._slice_bin` vs transcribed kernel rule, quantized z as from a
  gridded initial condition, seed 42):
  - Float64: 2138 / 260000 samples (0.82%) land in a different bin; 85 dropped
    entirely by CUDA (CPU clamps them into an extreme bin). First interior
    divergence: (zmin=-0.9129233863399265, width=0.024387361037225087,
    bins=30, zi=-0.5471129707815503) → CPU bin 15, CUDA bin 16.
  - Float32: 1848 / 260000 divergent; 104 dropped. Example:
    (zmin=0.85947186f0, width=0.0037843056f0, bins=44, zi=0.9010992f0) →
    CPU 11, CUDA 12.
  Divergent counts shift `cumulative` (pic_cuda.jl:5272-5273 vs slicing.jl:123)
  and hence the interpolated slice boundaries, then slice weights (which
  multiply kbb directly). Same defect family as the FIXED `:equal_count` tie
  bug the file itself documents with 15.8–27.8% weight errors
  (pic_cuda.jl:5367-5385); here the effect is O(1/n_live) per affected edge —
  small, but systematic for quantized/Float32 z, and it makes cross-backend
  `:equal_area` boundaries non-bit-comparable. Existing CPU↔CUDA slicing
  parity test (runtests.jl:4198-4213, atol=1e-15) uses smooth z and would not
  see it.
- Severity: low (documented-drift; tolerance-level on realistic beams).
- Repro: `scratchpad/U2/probe_equal_area_and_reductions.jl` (P1 output above);
  GPU confirmation recipe: run `_cuda_longitudinal_slices` vs
  `longitudinal_slices` with `method=:equal_area` on z quantized to bins/nq
  sharing factors, compare `boundary` and `weight` exactly.

### U2-3 — TSC third weight not bit-identical CPU vs CUDA (1 ulp)
- Files/lines: pic_cuda.jl:4304,4311 (`w3 = one(u) - w1 - w2`) vs
  pic_cpu.jl:1462,1468 (`w3 = 0.125 + 0.5*(t ± f)` closed form).
- Measured (probe P2): max |w3_cpu − w3_cuda| = 1.1102230246251565e-16
  (= eps(0.75)) at f = 6.75e-6, over 2×10^6 samples of f∈[0,0.5].
  Algebraically identical; CUDA guarantees Σw = 1 exactly, CPU does not.
  Per-axis 1-ulp deposit-weight drift; informational for anyone chasing
  bit-level CPU↔CUDA parity of TSC deposits. Severity: info.

## Observations (not defects, worth a glance)

- pic_cuda.jl:4728-4756 `_cuda_pic_kick_pair_indexed_longitudinal_kernel!` has
  NO grid-stride loop while its non-longitudinal sibling (4694-4726) strides.
  Correct only because the launcher (2077-2078) sizes
  `blocks = cld(max(len1,len2), threads)`; a future caller reusing the kernel
  with capped blocks silently skips particles. Fragile asymmetry.
- pic_cuda.jl:4904-4906 `_cuda_pic_kick_node_kernel!` passes `phiL` into both
  phi slots of the R-node `_cuda_pic_interpolate_field` call. Harmless today
  (that function never reads its phi arguments, 4829-4869); becomes a wrong-
  mesh potential read if it ever does.
- My combined probe initially reported ceil-halving(1:100) = 21279 — that was
  the probe's own Core.Box shared-closure-variable bug (the exact
  `chunk_counts NOT counts` pattern documented at slicing.jl:252-262 and
  gaussian.jl:80-90). The isolated probe proves the kernel pattern exact.

## Checked and found sound

1. Luminosity overlap tree reduction (pic_cuda.jl:4372-4403): floor-halving is
   pow2-only; probe P3 confirms 36 of 100 elements orphaned at blockDim=100
   (matches the ledger's number, result 3168 vs 5050). Guarded twice
   (interface.jl:122-124 constructor, interface.jl:195-197 resolution;
   fallback thread count 256), and both guards are now pinned by
   test/runtests.jl:1858-1911. Launch shmem `threads*sizeof(T)` matches
   `CuDynamicSharedArray(_, blockDim)`; partials length == launched blocks
   (`cld(lnx*lny, luminosity_threads)*npairs`, workspace invalidates when
   luminosity_threads changes, pic_cuda.jl:2436-2452, 2455-2468).
2. Gaussian moment shared-memory reductions (5673-5684 per-column, 5860-5871
   fused): ceil-halving `offset=(active+1)÷2` is exact for ARBITRARY blockDim
   — probe verified n ∈ {1,2,3,5,7,13,25,64,100,256,1000} all exact. Shmem
   `centered_nstats*threads*sizeof(T)` matches launch (5604); 256-thread cap
   (5621) keeps 14×256×8B = 28 KB under the static limit. Anchor trick
   (anchor written only by block 1 with `anchor_scale`, zeros elsewhere, then
   summed over blocks) reconstructs x0 exactly; fused reducer sums only
   `block_counts[col]` blocks (5710-5713) so stale partials are never read;
   fused stride `nb*threads` reproduces the per-column launch bit-for-bit.
3. Bounds reductions: pass-1 kernels launched with threads=256, finalize with
   threads = `_CUDA_PIC_BOUNDS_PARTIAL_BLOCKS` = 64 (pic_cuda.jl:462,
   1570-1620) — both multiples of 32, so the full-mask
   `shfl_down_sync(0xffffffff, …)` in `_cuda_pic_bounds_block_reduce`
   (4138-4177) has no inactive lanes; 32-warp static shared array covers ≤1024
   threads. `bounds_partials` is ALWAYS 12×64×2npairs (2421-2424), so the init
   kernel's `(index-1) % 12` row parity (4184) is correct for both the 8-row
   and 12-row uses; blocks beyond `min(cld(len,256), 64)` retain neutral init;
   the non-luminosity finalize reads only rows 1:8.
4. Deposit kernels (3909-4129): CIC/TSC out-of-range/NaN → zero weight,
   matching the CPU contract exactly (guard expressions identical,
   pic_cpu.jl:1421-1428, 1456-1474); index bounds proven for every launch in
   range: interaction deposits with dims (nx,ny) into 2nx×2ny padded planes
   (CIC max ix+1 = nx, TSC max base+2 = nx); luminosity deposits with dims
   (lnx+1, lny+1) into exactly (lnx+1, lny+1[, npairs]) buffers; plane index ≤
   npairs/4·npairs/6·npairs per route matches workspace plane counts
   (:standard 4·npairs, :node 6·npairs, separate cache entries — no aliasing,
   2512-2545).
5. `:equal_area` one-pass kernel == per-bin-mask oracle (R8): verified
   statically (see U2-2) and pinned by runtests.jl:3087-3135. Degenerate-z
   slice-1 convention (R7) verified on both backends. `ns==1` skip returns the
   identical [zmin, zmax] boundaries.
6. `:equal_count` (5342-5394): rank-based membership with position arithmetic
   `floor(Int, s*n/ns)` and midpoint boundary formulas identical to CPU
   (slicing.jl:281-316); both slice the sort permutation, so the documented
   tie bug stays fixed.
7. Quadratic kick math (3374-3407, 4927-5014): aL/aM/aR are the quadratic
   Lagrange basis (sum 1; collapse to (1,0,0)/(0,0,1) at t=0/1), bL/bM/bR =
   −d/dt of it (sum 0, reduces to phiL−phiR at t=1/2) — coefficient
   expressions and `t = 1 − clamp(−z·hzi + zbias)` match CPU
   (pic_cpu.jl:606-623, 1822-1854) term for term. Midpoint-plane containment
   in the L/R box is sound (drift affine in s). Half-drift/kick/half-drift
   composition and the longitudinal ∓0.25(px²+py²) bookkeeping match the CPU
   ordering.
8. Field stencils (4423-4543): E = −∇φ with one-sided boundary, 2nd-order
   fallback at j∈{2, ny−1} under `fourth`, and the 4th-order interior — all
   coefficient-identical to `_pic_field!` (pic_cpu.jl:1719-1765); relies on
   the same `_validate_pic_grid` nx,ny ≥ 5.
9. Luminosity: padding arithmetic (`nx−1.1`, +0.1tx, −0.05tx) and the
   [1:nx,1:ny] overlap-sum convention identical to CPU `_pic_luminosity!`
   (pic_cpu.jl:1874-1930); scale differs only in ulp
   (`/ (hx*hy)` vs `* hxi * hyi`). Indexed-wavefront per-pair sink partial
   sums use exactly `blocks_per_pair` blocks per pair — offsets consistent.
   `_cuda_pic_wavefront_luminosity_batched` is dead code by default
   (`_cuda_pic_batched_luminosity_enabled() = false`, line 455) but its
   plane/bounds arithmetic checks out; its accumulation kernel (4405-4421) is
   properly atomic.
10. Gaussian sequential collide (5064-5135): luminosity bookkeeping
    (sample_beam1 selection, weight·klum pairing, /TWOPI) matches the CPU
    twin exactly (gaussian.jl:7-100); `_cuda_slice_kick_kernel!` (5720-5761)
    is a line-for-line twin of `_apply_slice_kick_one!` (gaussian.jl:144-177)
    including the longitudinal 0.5·((px−px0)·mpx + (py−py0)·mpy) term and
    density·TWOPI staging; `_forward/_reverse_virtual_drift` are single
    shared definitions (elements/strong_beam.jl) — parity by construction.
    `_cuda_cp_covariance_kick` (track/strong_beam_track.jl:320-402) differs
    from `_cp_covariance_kick` (elements/strong_beam.jl:600-671) only in
    ulp-level expression order (xx²/a vs xx²/sigx², /(2π·σxσy) grouping).
11. `_cuda_gaussian_moments_from_sums` (5537-5597): term-for-term identical to
    CPU `_slice_transverse_moments` (slicing.jl:603-720) including
    `StrongTransverseMoments` field ORDER verified against the struct
    definition (elements/strong_beam.jl:79-90: a0,b0,d0,bxx,bxpy,bypx,bypy,
    qxx,qxy,qyy ← varx,covxy,vary,covxpx,covxpy,covpxy,covypy,spx2,covpxpy,
    spy2 — correct), min_sigma floor, spx2/spy2 clamps, ignore_centroid
    zeroing AFTER covariance computation.
12. Pair-kick field pairing (rep1←phi21 on grid1, rep2←phi12 on grid2): the
    documented convention (2049-2067) is honored at the quadratic call sites
    3357-3366 and 3269-3280 (beam-2 kick gets prep12's planes o+1..3 and
    field grid, source center p1.center, recipient params p2).
13. Non-atomic `flag[1] = Int32(1)` in `_cuda_gaussian_build_moments_kernel!`
    (5778): multiple writers, identical idempotent value — benign.
14. `grid_extent ≠ :extrema` is rejected loudly for CUDA PIC
    (pic_cpu.jl:356-360) — no silent estimator drop; the R9 dropped-charge
    concern does not apply to the always-extrema CUDA bounds, and the
    quadratic route's deposits use bounds computed in the same call before
    any kick of that batch (no intra-batch staleness).
15. Slice membership assignment: CPU `searchsortedlast`+clamp and CUDA
    left-closed masks (5462-5468) agree for sorted boundaries including ties
    on boundaries and duplicated (empty-slice) boundaries; live extrema
    guarantee no out-of-range live z, where the two rules would differ.
16. Gather/scatter/mask-index kernels (3714-3796): index sets derive from the
    same arrays they index; `_cuda_indices_from_mask` (698-710) sizes idx from
    the cumsum total — no out-of-bounds writes possible.
17. Green kernels (3798-3906): plane/row-major index decompositions correct
    for column-major layout; `_cuda_pic_atan_ratio`/`_cuda_pic_kernel_integral`
    expression-identical to CPU (pic_cpu.jl:1475-1493); `:lattice` values
    built on host — bit-identical to CPU by construction (3460-3472).
