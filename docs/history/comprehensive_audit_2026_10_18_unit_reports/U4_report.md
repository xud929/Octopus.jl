# U4: pic_cpu.jl

Reading unit U4 of the comprehensive audit 2026-10-18 (protocol: `docs/comprehensive_audit.md`;
briefs: `result/comprehensive_audit_2026_10_18/plan/BRIEF_COMMON.md`, `plan/U4.md`). Tree under
audit: `/cfs/ad/dxu/Library/Julia/Octopus` at commit 24e8683, read-only. Every claim below is a LEAD,
not a finding. Line numbers are those of commit 24e8683; the Repro lines are the durable identity.

## Region

- `src/tasks/strongstrong/pic_cpu.jl`, lines 1-3061 (3061 lines, the whole file), read line by line.

Cross-file facts consulted only to judge the region (not audited): `src/tasks/strongstrong/interface.jl`
lines 625-775 (threshold constants, `_pic_deposit_parallel`, the `_PICCPUWorkspace` family and
`_pic_cpu_workspace`), 1384-1500 (the `PICPoissonSolver` struct and constructor validation),
1547-1550 (`_pic_luminosity_grid`); `src/tasks/strongstrong/slicing.jl` lines 20-130, 596-700,
703-830 (boundary finiteness, `_chunk_bounds`, collision order, `collision_pair_batches`);
`src/policies/Policies.jl` 453-456 and 1236-1290 (`_cpu_worker_count`, `_run_logical_workers`);
`src/tasks/strongstrong/pic_cuda.jl` 2163-2175 and 2702-2711 (the node twin's dropped accounting and
the CUDA luminosity buffer sizing); `src/tasks/strongstrong/gaussian_pic.jl` 735-742 and 1160-1166
(the two calls into this region); `test/runtests.jl` 17015-17240, 22425-22450, 28900-28960,
31194-31345 (the pins this region's comments cite); the previous audit's
`docs/history/comprehensive_audit_2026_08_05_b_unit_reports/U6_report.md` lead U6-1 only.

## Provenance

READ line by line: `src/tasks/strongstrong/pic_cpu.jl` 1-3061 in eleven consecutive chunks
(1-260, 260-520, 520-800, 800-1060, 1060-1320, 1320-1580, 1580-1840, 1840-2100, 2100-2360,
2360-2620, 2620-2880, 2880-3061). The cross-file ranges above were read as excerpts.

EXECUTED (scratch: `/cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U4/`,
all with `julia --project=/cfs/ad/dxu/Library/Julia/Octopus`; logs beside each script):

- `probe1_node_field_count.jl` (`probe1.log`): redefines `_pic_interaction_node!` from its own source
  text extracted from pic_cpu.jl (nothing hand-copied) plus a tally of field particles outside
  `gR.field_grid` while inside `gL.field_grid`, and of sR-plane source deposits outside
  `gL.source_grid`; bare `:node` collide, 3000 particles/beam, 3 `:equal_count` slices, grid 16, CIC,
  kbb swept 1e-12..3e-10. Result: 18,000 field interpolations tallied per collide, shipped count and
  tally both 0 at every kbb (the synthetic beam's slices share one transverse size, so the two node
  meshes coincide and the kick never crosses the 1.5-cell margin).
- `probe1b_node_field_count_graded.jl` (`probe1b.log`): same, with the transverse size graded with z
  (x0.4 .. x1.6 across +-2e-2) so adjacent node meshes differ, kbb 1e-10..3e-7. At kbb = 3e-7
  (max displacement 1.39 cells): shipped `dropped` = 1284; field outside gL = 400 (counted), outside
  gR = 419, outside gR AND inside gL = 117 (UNCOUNTED), outside gL and inside gR = 98; phiZ plane:
  source at sR outside gL.source_grid = 103 (UNCOUNTED) versus outside gR.source_grid = 38 (counted).
  All coordinates finite.
- `probe1c_node_tsc_band.jl` (`probe1c.log`): probe1b with `deposit_method = :TSC` plus a tally of
  field particles inside gL.field_grid but in the TSC displacement band (u < 0.5 or u > n-1.5 on
  either axis). At kbb = 3e-7 (1.48 cells): shipped 1203; field outside gL 382; in-band 1004
  (UNCOUNTED, stencil displaced one cell); outside gR and inside gL 102; phiZ uncounted 44 vs 13.
- `probe2_lumgrid_alloc.jl` (`probe2.log`): `@allocated` of `_pic_luminosity(solver, ..., workspace)`
  on a grid-32 workspace: `luminosity_grid = nothing` 416 B/call, `(32,32)` 416 B/call,
  `(16,16)` 5392 B/call (fallback taken), `(64,64)` 68,336 B/call (fallback taken; two fresh
  65x65 Float64 grids = 67,600 B). Bare collide, 15 slices (225 pairs), grid 32, 15,000/beam:
  6.2 MiB allocated with `luminosity_grid = nothing`, 20.8 MiB with `(64,64)`; the difference,
  14.6 MiB, is the predicted 225 x 2 x 65 x 65 x 8 B = 14.5 MiB.
- `probe3_threads.jl` (`probe3_t1.log`, `probe3_t4.log`): eleven solver variants (wavefront/sequential
  x CIC/TSC, node, source_slice, quadratic, sigma, fourth+green_none, lumgrid TSC, quantize), grid
  (8,8), 3 slices, 33,000/beam = 11,000/slice, above the kick/map threshold (4096) and the deposit
  threshold (160 x 8 x 8 = 10,240), run once under `--threads=1` and once under `--threads=4` with
  a resolved `CPUThreadsExecutionPolicy(threads=nthreads)`; SHA-256 over both beams' six coordinate
  arrays and the luminosity. All 11 digests identical across the two runs; wavefront and sequential
  share one digest for CIC and one for TSC. Receipts: `:cpu_logical_workers` launches with workers=16
  (the fixed-chunk deposit) in every variant; `:pic_pair_schedule` pair_workers=3/inner_workers=1 for
  wavefront at four threads, inner_workers=4 for sequential, pair_workers=1 at one thread.
  (A first run of this script compared two EMPTY digest sets after a `with_execution_audit` return-value
  mistake; the comparison was re-armed with a non-zero-line check before the result above was taken.)
- `probe3b_threads_lumdeposit.jl` (`probe3b_t1.log`, `probe3b_t4.log`): six variants at
  40,500/beam = 13,500/slice, which also crosses the luminosity deposit's own threshold
  (160 x 9 x 9 = 12,960 for the (8,8) luminosity grid). All 6 digests identical at 1 vs 4 threads;
  wavefront CIC == sequential CIC bit for bit; dropped-charge warnings: node 23,653 and
  `source_slice` at kbb = 3e-5 52,436, identical at both thread counts.

## Leads

### LEAD U4-1 [Moderate, confidence high] src/tasks/strongstrong/pic_cpu.jl:1738
Claim: on `interaction_grid = :node` the dropped-charge tally checks field particles against only one of the two meshes the kick interpolation reads (`gL.field_grid`, not `gR.field_grid`) and never checks the longitudinal `phiZ` deposit (source at drift `sR` onto `gL.source_grid`), so a particle whose right-node kick vanished through the zero-weight branch, and charge lost from the longitudinal plane, go uncounted and unwarned.
Mechanism: `_pic_interaction_node!` interpolates each field particle twice, on `gL.field_grid` (line 1764) and on `gR.field_grid` (line 1766), and blends them with `zL`/`zR`; `_pic_cic_weights` / `_pic_tsc_weights` return zero weights outside either mesh, so a particle outside `gR.field_grid` but inside `gL.field_grid` receives only `zL * K_L` with nothing recorded. The only field-side count (line 1738) uses `gL.field_grid`. Node j's field box is the union of slices j-1 and j, node j+1's the union of j and j+1, so the two boxes differ whenever adjacent slices differ in transverse extent (hourglass, chromatic or crabbed beams), and intra-turn kicks move particles out of one but not the other. Likewise the `phiZ` solve (lines 1752-1754) deposits the source at `sR` onto `gL.source_grid`, while line 1734 counts the `sR` deposit against `gR.source_grid` only; the docstring at 1726-1729 ("the field side is counted against the mesh the interpolation reads") describes one of the two meshes. The CUDA twin (`pic_cuda.jl:2169-2175`, "mirrors the CPU accounting exactly") shares the blind spot, so the parity contracts cannot see it -- a cross-file seam for the auditor. The suite's pin (`test/runtests.jl:31298-31338`) displaces a SOURCE particle only.
Repro: `cd /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U4 && julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 probe1b_node_field_count_graded.jl` -- at kbb = 3e-7 the shipped count is 1284 while the tally shows 117 field interpolations outside gR.field_grid and inside gL.field_grid (zero contribution to the shipped count) and 103 sR-plane source deposits outside gL.source_grid (versus 38 counted against gR.source_grid). Expected after a fix: the shipped count rises by those two tallies (or the phiZ/right-mesh escapes are documented as deliberately uncounted).

### LEAD U4-2 [Moderate (performance), confidence high] src/tasks/strongstrong/pic_cpu.jl:2986
Claim: any `luminosity_grid` that differs from `grid` silently routes every slice pair's luminosity through the ALLOCATING `_pic_luminosity`, two fresh `(lnx+1) x (lny+1)` grids per pair per turn, because the CPU workspace's luminosity buffers are sized from `solver.grid` while the consumer wants `_pic_luminosity_grid(solver)`.
Mechanism: `_pic_luminosity(solver, ..., workspace)` compares `size(workspace.luminosity_q1)` with `_pic_luminosity_grid(solver) .+ 1` and on mismatch returns the workspace-less method (lines 2986-2988), which `zeros` two matrices; `_pic_cpu_workspace(T, nx, ny)` (interface.jl:772, called with `solver.grid...` at pic_cpu.jl:18 and :623) builds `luminosity_q1/q2` as `(nx+1, ny+1)` of the SOLVER grid. The public option `luminosity_grid` (metadata interface.jl:1674) therefore selects a per-pair allocation path with no receipt and no warning -- the class-15 "per-call allocation scaling with pair count" the workspace was introduced to remove (interface.jl:717-726). The CUDA workspace sizes its buffers from `_pic_luminosity_grid(solver)` (pic_cuda.jl:2702-2711), so this is also a CPU/CUDA twin divergence; the same consumer is called from `gaussian_pic.jl:1162` (seam). The fix belongs either in the in-region fallback (allocate once and keep, as `_pic_mid_field!` does) or in the workspace constructor's signature (out of region).
Repro: `cd /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U4 && julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 probe2_lumgrid_alloc.jl` -- `@allocated` per `_pic_luminosity` call on a grid-32 workspace: 416 B with `luminosity_grid = nothing` or `(32,32)`, 5392 B with `(16,16)`, 68,336 B with `(64,64)`; a 225-pair bare collide allocates 20.8 MiB with `luminosity_grid = (64,64)` against 6.2 MiB without (difference 14.6 MiB; predicted 14.5). Expected after a fix: identical bytes per call for every `luminosity_grid`.

### LEAD U4-3 [Minor, confidence high] src/tasks/strongstrong/pic_cpu.jl:2510
Claim: the `_pic_tsc_weights` docstring's claim that the one-cell stencil displacement "does not arise on an interaction mesh" is false for the pre-built meshes (`:node`, `:source_slice`) and for `grid_extent = :sigma`, where particles 1.0-1.5 cells outside the turn-start box sit in the half-cell band and have their deposit or kick displaced by one cell with nothing counting them.
Mechanism: the drop-and-count criterion is `u` outside `[0, n-1]` (lines 2519 and 1854-1863), but TSC clamps `base` into `[1, n-2]` (line 2544) so a particle with `u in [0, 0.5)` or `u in (n-1.5, n-1]` is kept and displaced instead of dropped; the docstring argues this away for interaction meshes by `:extrema` sizing (`u in [1.5, n-2.5]`), which holds only on `:slice_pair`, where the mesh is sized from this slice's own post-drift extrema. Under `:node`/`:source_slice` the mesh is built before the collision and under `:sigma` it is an estimator, exactly the regimes U6-1 made the counter cover; in them the band is populated and invisible to `dropped`. (`grid_quantize > 0` also shrinks the `:extrema` margin below 0.5 cell in the worst case: a 9 % ladder step plus a half-cell origin rounding plus the alignment shift leaves about 0.38 cell -- not measured.)
Repro: `cd /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U4 && julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 probe1c_node_tsc_band.jl` -- at kbb = 3e-7, 1004 of 18,000 field interpolations on `gL.field_grid` are in the band (in box, stencil displaced, uncounted) while 382 are outside and counted. Expected after a fix: either the docstring scopes its claim to `:slice_pair` with `:extrema` and `grid_quantize = 0`, or the band is counted or widened out of.

### LEAD U4-4 [Minor, confidence med, out-of-hypothesis] src/tasks/strongstrong/pic_cpu.jl:461
Claim: when a node mesh lookup returns `nothing` the pair is skipped silently (no kick, no luminosity, no warning), while the sibling check two lines earlier (448-452) treats a missing cache as a loud invariant violation -- and the skip is unreachable for a pair that passed the emptiness test, so the branch is dead code with a silent failure mode.
Mechanism: `_pic_build_node_grids!` stores node `b` only if an adjacent slice has a finite field box (lines 1615-1621); for pair (i, j) with `n2 > 0`, node j's box includes slice j and node j+1's box includes slice j, so `gL1`/`gR1` always exist (symmetrically for `gL2`/`gR2`), and the all-ranks min/max keeps that true when divided. The only route to `nothing` is a slice whose every coordinate is non-NaN infinite (`isfinite(fxlo)` false, `any(isnan)` false), which the surrounding non-finite chokepoints are meant to refuse. If the invariant is ever broken by a future change, the pair vanishes from the fold and the per-pair trace with `ran[p] == false` and the docstring (383-385) calling it a legitimate skip.
Repro: read-only -- `grep -n "return false" src/tasks/strongstrong/pic_cpu.jl` shows two returns in `_pic_collide_pair!`; only the first (empty slice) is a skip the docstring's reader can predict. Expected after a fix: the line-461 branch throws the same kind of error as 448-452, or a comment records it as unreachable-by-construction.

### LEAD U4-5 [Minor, confidence med, out-of-hypothesis] src/tasks/strongstrong/pic_cpu.jl:550
Claim: the single-workspace `_pic_report_dropped(workspace::_PICCPUWorkspace)` method has no caller in `src/` or `test/` and, unlike the pool form beside it, does neither the cross-rank integer sum nor the rank-0 gating, so a future divided caller would warn once per rank with its shard's count.
Mechanism: lines 550-552 route straight to `_pic_report_dropped_count(Int(workspace.dropped[]))`; lines 559-569 (the pool form) do `_mp_global_count` and `_mp_is_root() || return nothing` first. `grep -rn "_pic_report_dropped(" src/ test/` finds only the pool form in use (pic_cpu.jl:375, gaussian_pic.jl:1119). Two entry points with one name and different contracts is the class-3/class-2 shape the previous audit's U6-10 removed from the deposit fallbacks.
Repro: `grep -rn "_pic_report_dropped(" /cfs/ad/dxu/Library/Julia/Octopus/src /cfs/ad/dxu/Library/Julia/Octopus/test` -- expect the definition at pic_cpu.jl:550 and no call of the single-workspace form. Expected after a fix: the method is deleted or forwards to the pool form as `_pic_report_dropped((workspace,))`.

### LEAD U4-6 [Minor (test quality), confidence high] src/tasks/strongstrong/pic_cpu.jl:2332
Claim: the workspace-less `_pic_deposit_threaded!` -- the form the luminosity deposit (line 3042-3043) and `pic_cpu_sliced.jl` reach above 160 particles per luminosity cell -- has no direct thread-invariance pin, and the suite's collide-level pins stay below every deposit threshold, so the only fixed-chunk fold on the collide path that the suite never executes threaded is this one; it measures invariant here.
Mechanism: `test/runtests.jl:17015` pins collide-level invariance at grid 16 with 5000/slice (deposit threshold 40,960/slice) and says so; the direct pin at 17186 exercises `_pic_deposit_drifted_threaded!` with a workspace. The luminosity deposit calls the 10-argument `_pic_deposit!` (line 3042) whose threaded branch allocates `[zero(charge) for _ in 1:16]` (line 2335) and folds in chunk order; by construction it is worker-count invariant, but a check only counts while it executes (Invariant 1), and this path executes only above `160 * (lnx+1) * (lny+1)` particles per slice.
Repro: `cd /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U4 && for t in 1 4; do julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=$t probe3b_threads_lumdeposit.jl > probe3b_t$t.log 2>&1; done; diff <(grep digest probe3b_t1.log) <(grep digest probe3b_t4.log)` -- six variants at 13,500/slice on grid (8,8) (luminosity threshold 12,960): empty diff, 6 digest lines on each side. Expected: the suite gains a direct pin on `_pic_deposit_threaded!` (or the collide-level block crosses the luminosity threshold on a small grid, as this probe does in about a minute).

## Clean

What was checked and found sound, with the evidence.

1. Thread- and chunk-count invariance above the parallel thresholds (hypothesis 1), MEASURED: probe3
   (11 variants, 11,000/slice, above the 4096 map threshold and the 10,240 deposit threshold) and
   probe3b (6 variants, 13,500/slice, also above the 12,960 luminosity-deposit threshold) give
   identical SHA-256 digests of both beams' coordinates plus the luminosity at 1 and 4 threads;
   the receipts prove the thresholds were crossed (`cpu_logical_workers` workers=16 launches in every
   variant; `pic_pair_schedule` pair_workers=3/inner_workers=1 for wavefront at four threads,
   inner_workers=4 for sequential). The design argument read in the code matches: `_pic_map_range`
   partitions by worker count only for index-local maps (kick, virtual positions, Green columns;
   lines 1397-1441, 2759), the deposits use the fixed `_PIC_DEPOSIT_CHUNKS = 16` with a chunk-order
   fold (2332-2420), and `_pic_deposit_parallel` reads data and mesh size only.
2. Batched versus sequential schedule, MEASURED: wavefront and sequential produce one digest for CIC and
   one for TSC in probe3 and probe3b, as lines 59-61 and 184-189 claim (luminosity folded by collision
   position, `pair_pos`; `ran` is a `Vector{Bool}`; `state2[j]`/`scratch2[j]` swapped at distinct j
   within a batch; `chunk_ws = workspaces[chunk]` per worker).
3. The schedule receipt records what ran, MEASURED: at one thread the wavefront variants report
   `batch_mode = :wavefront, pair_workers = 1, inner_workers = 1`; `:source_slice` reports
   `:sequential` under a `:wavefront` request (probe3, `source_slice` line) -- consistent with lines
   299-305 and 335-340.
4. Dropped-charge tripwire reachability under `:node` and `:source_slice` (hypothesis 2), MEASURED:
   shipped counts 1284 (probe1b, node, CIC), 1203 (probe1c, node, TSC), 23,653 (probe3b node) and
   52,436 (probe3b `source_slice` at kbb = 3e-5), identical at 1 and 4 threads; the pool reporter sums
   every workspace (lines 559-569) after a per-collide reset (167-169). The accounting gaps found are
   leads U4-1 and U4-3, not reachability.
5. Drop criterion versus count criterion for CIC, READ and derived: `_pic_cic_weights` drops iff
   `u` is outside `[0, n-1]`, i.e. `x` outside `[x0, x0 + width]`, which is exactly the box
   `_pic_count_outside_box` / `_pic_count_outside_box_drifted` test (lines 1854-1884, 2475-2490);
   the count uses the FINAL grids returned by the Green cache (1309, 1322). In-range indices stay in
   `1:n` for CIC (`base in [1, n-1]`) and TSC (`base in [1, n-2]`, three cells), so the `@inbounds`
   deposits and interpolations never write the padding half of the `2nx x 2ny` charge grid.
6. Performance gates see the quantity they gate (hypothesis 3), READ: the deposit gate is called with
   the dimensions of the grid it deposits on, `(nx, ny)` for interaction planes (2203, 2232) and
   `(nx+1, ny+1)` for the luminosity mesh (3042-3043); the Green build's chunk floor is in cells
   (`cld(_PIC_GREEN_MIN_CHUNK_CELLS, 2nx)` columns, 2759); the maps' floor is in particles; the pool
   width is bounded by the smaller slice count and the policy's worker count (97-104, 234). No gate
   reads the worker count except as a cap. The previous audit's U6-2/U6-3 fixes are in place.
7. Slice-plane geometry, derived by hand: `_slice_interpolation_parameters(lb, rb)` gives
   `zL = (rb - z)/(rb - lb)`, 1 at `z = lb`, and plane L is deposited at `sL = (c_s - lb_f)/2`
   (1143, 1704), so the weight-1 plane is the one at the particle's own boundary; the quadratic basis
   `(2t^2-3t+1, 4t-4t^2, 2t^2-t)` sums to 1 and its derivative weights `(3-4t, 8t-4, 1-4t)` sum to 0,
   collapsing to `phiL - phiR` at `t = 1/2` (2941-2973). Slice boundaries are finite by
   `slicing.jl:647`, so the degenerate `(0, 0.5)` branch of 1792-1800 only fires for a zero-width slice.
8. Field stencils, derived: `_pic_field!` computes `E = -grad(phi)` with the second-order central
   difference, the second-order one-sided boundary formula `(1.5 f0 - 2 f1 + 0.5 f2)/h`, and the
   fourth-order `[(f_{i+2} - f_{i-2}) + 8 (f_{i-1} - f_{i+1})]/(12h)` with the documented fallback rings
   (2824-2884); `_validate_pic_grid` (nx, ny >= 5) makes every boundary index safe.
9. Kernels, derived: `_pic_kernel_integral` is `F` with `d2F/dxdy = ln(r^2)` (checked by
   differentiating `xy ln r^2 - 3xy + x^2 atan(y/x) + y^2 atan(x/y)`), so the four-corner difference
   times `-0.5/(hx hy)` is the cell average of `-ln r`; `:standard` is `-0.5 ln r^2` with the
   integrated value at `r = 0` (2770-2802). `_pic_atan_ratio` returns a finite value on axis.
10. Origin alignment, derived: with `t = (f2 - f1)/2` and the `:standard` adjustment `t' = t -/+ 0.25`,
    the post-shift fractional separation is `(f2 - f1) - 2t' = 2(t - t') = +/-0.5` exactly, and 0 for
    the other kernels, as the comment at 2147-2148 states; the else-branch at 2149-2153 is unreachable
    as U6-9 recorded.
11. Mesh sizing, derived: `_pic_interaction_grids` gives cell size `span/(nx-4)` and 1.5 cells of margin
    on each side (1937-1940, 1962-1965); both grids share `width`/`height`, so the Green table's
    `hx = source_grid.width/(nx-1)` (2184, 2175) is the field grid's spacing too, and the expanded
    cache grids scale both by one factor and are re-aligned (2009-2012).
12. Option validation, READ: every Symbol option is validated in the constructor
    (`interface.jl:1459-1500`, including `grid_extent in (:extrema, :sigma)` and
    `grid_extent_sigma > 0`) and again in `_validate_pic_solver` (646-705); the struct fields are
    `Symbol`, so the `===` comparisons at 78, 728-734, 881-915, 2887 are sound; the inactive
    combinations (`grid_extent` off `:slice_pair`, `:quadratic` with `:node`) are rejected rather than
    ignored.
13. Working-type consistency, READ: `_pic_cpu_scalar_type` (588-594) equals the collide's `T` (142);
    `kbb1` and `kbb2` always share a type (both solver-typed or both products of the same two
    `BeamParams`, slicing.jl:103-117), so the inner `promote_type(source, field, kbb)` equals the
    workspace type and the allocating `_pic_virtual_buffers` fallback (1067) cannot fire on the collide
    path, as its docstring says.
14. Shared structures in the batched loop, READ: `node_cache` is filled before any pair and only read
    (`get`, 446-447) inside pairs; `union_bounds` is written only on the sequential `:source_slice`
    path and asserted so (472-475); the Green cache takes its lock around the Dict and counters only,
    with per-pair keys `(i, j, dir)` so no two workers touch one key within a collide (1981-2030).
15. Luminosity overlap, READ: the mesh has a 0.05-cell margin, the deposit uses `(nx+1, ny+1)` points
    and the overlap sum covers the full extent (3004-3060) as U5-8 recorded; skipped pairs contribute
    neither to the fold nor to the per-pair sink (360-373).

## Unchecked

- The divided (`_mp_nranks() > 1`) branches -- `_mp_allminmax`, `_mp_allsum!`, `_mp_global_count`,
  the globally-first-member reference, the per-pair `:pic_grid_exchange` receipts -- were read but not
  executed; no multi-rank probe was run. The slice-aligned collide they route to (`pic_cpu_sliced.jl`)
  is outside this region.
- The CUDA twin was consulted only for the node-path dropped accounting (mirrors U4-1) and the
  luminosity buffer sizing (differs, U4-2); nothing CUDA was executed.
- The lattice Green table (`_pic_lattice_green_table`, 2666-2742) and the `:integrated` normalization
  were checked only to the mixed-derivative identity and the alignment arithmetic; the theory note's
  tables (`docs/theory/pic_free_space_kernels.md` 3.2, 3.4) were not re-measured.
- The `grid_quantize > 0` margin arithmetic noted under U4-3 (worst-case margin about 0.38 cell with
  TSC) was derived, not measured.
- The `_pic_union_bounds` rep-form entry for `test/`/`validation/` callers treats an all-`+Inf` z
  slice as empty (line 769, non-NaN infinity passes `isnan`) -- exotic, not probed.
- Float32 beams were not executed; the Float32 typing fixes recorded at 2522-2530 and 1900-1909 were
  read only.
- `docs/theory/gaussian_subtracted_pic_solver.md` was read only as an outline; it governs
  `gaussian_pic.jl`, which calls into this region at two sites (listed above) and was not audited.
