# U1 report — src/tasks/strongstrong/pic_cuda.jl lines 1–3000 (host-side CUDA PIC)

Repo: /cfs/ad/dxu/Library/Julia/Octopus @ 6a3f39a. Read-only audit; no repo files modified.

## Coverage

- **Read in full, line by line: src/tasks/strongstrong/pic_cuda.jl lines 1–3009** (assignment
  range 1–3000; the containing function boundary runs to 3009).
- Cross-contract verification reads (U2/U3 territory, read only to check calls made *from* my
  region): pic_cuda.jl 3440–3540, 3574–3712, 4318–4370, 5075–5185, 5509–5698, 5766–5957.
- CPU twin pic_cpu.jl read: 1–919, 920–1420, 1536–1663, 1840–1902 (validation, interaction,
  node build, green cache, realign, lattice table, luminosity — everything my region mirrors).
- interface.jl: 60–380 (launch config machinery), 470–560, 1137–1200, 1290–1320, 2100–2140.
- slicing.jl: 60–140, 490–600. Theory notes: slice_longitudinal_interpolation.md §1,
  node_interaction_grid.md §6, pic_free_space_kernels.md (skim for conventions).

## Leads

### U1-1 — interaction_grid=:node silently dropped on every CUDA wavefront sub-route except the fully-indexed one; StrongStrongDiagnostics(pic_timing_detail=true) then changes tracking results

- **Where:** pic_cuda.jl:199–202 (route flags), 218–219 (`use_indexed_wavefront`), 251–255
  (the ONLY wavefront branch that reads `node_cache`), 296–302 / 312–322 / 324–330 / 331–353
  (four sub-routes that ignore node meshes and use per-slice-pair `_cuda_pic_prepare_interaction`
  grids instead), 204–212 (node caches prebuilt unconditionally — cost paid, result unused).
  Gate: pic_cpu.jl:344–355 (`_require_cuda_pic_options`) accepts `:node` whenever
  `batch_mode == :wavefront`, with no condition on `cuda_async`/`cuda_batch_fft`/
  `cuda_wavefront_fft`/`cuda_indexed_wavefront`, although its own docstring says
  ":node runs on the indexed wavefront route".
- **Invariant violated:** (a) repo rule (AGENTS.md, cited verbatim in this file's own history
  comments): a silently ignored non-default public configuration is not acceptable — `:node`
  selects a *different discretization* (node-continuous meshes), not a performance variant;
  (b) interface.jl:293–296: StrongStrongDiagnostics options "observe execution and must not
  change tracking results" — with ALL-DEFAULT cuda flags, `pic_timing_detail=true` forces
  `use_async=false` (line 200) which cascades `use_indexed_wavefront=false`, so a node-mode
  run under detailed timing silently switches to per-pair meshes, i.e. the diagnostic changes
  the physics. (c) CPU/CUDA parity: CPU honors `:node` on every route (pic_cpu.jl:79–94).
- **Evidence (probe, CPU-only, run):**
  `scratchpad/U1/probe_node_wavefront_gate.jl` — output: 10 combos tested; 9 print
  `validation_accepts=true  route_uses_node=false  <-- ACCEPTED BUT :node SILENTLY DROPPED`
  (each of cuda_indexed_wavefront/wavefront_fft/batch_fft/async = false, each × detail on/off,
  plus defaults+detail); only defaults+no-detail uses node.
- **GPU repro recipe for the auditor:** bare
  `collide!(PICPoissonSolver(interaction_grid=:node, batch_mode=:wavefront, cuda_indexed_wavefront=false), b1, b2, CUDABackend)`
  → the `:cuda_pic_algorithm` receipt reports `cuda_indexed_wavefront=false`, and coordinates
  match an `interaction_grid=:slice_pair` run, not the CPU `:node` reference. Same with
  defaults plus `StrongStrongDiagnostics(pic_timing_detail=true)` through a task.
- **Severity guess:** high (silent config drop + diagnostics perturb physics).

### U1-2 — slice_interpolation=:quadratic silently ignored whenever interaction_grid=:node, on BOTH backends (parity test shares the mistake)

- **Where:** CPU `_pic_interaction_node!` pic_cpu.jl:820–888 — kick loop is the two-plane
  zL/zR blend regardless of `slice_interpolation`; CUDA `_cuda_pic_interaction_node!`
  pic_cuda.jl:1870–1893, `_cuda_pic_apply_indexed_node_kick!` 1960–2001, and
  `_cuda_pic_interaction_wavefront_node_indexed!` 1332–1435 likewise (at pic_cuda.jl:251 the
  `if node_mode ... elseif _pic_quadratic_slice(solver)` makes node take precedence).
  Neither `_validate_pic_solver` (pic_cpu.jl:188–231) nor `_require_cuda_pic_options`
  (pic_cpu.jl:332–367) cross-checks the pair.
- **Invariant violated:** same repo rule as U1-1 (non-default request silently dropped —
  the repo *rejects* this combination class elsewhere, e.g. grid_extent × interaction_grid at
  pic_cpu.jl:223–230). The theory note (node_interaction_grid.md §6) explicitly tells users
  node indexing "does nothing for the longitudinal sawtooth ... that is what
  `slice_interpolation = :quadratic` addresses", inviting exactly this combination.
  Because both twins drop it identically, the CPU/CUDA parity contract cannot catch it
  (defect class 6/2).
- **Evidence (probe, CPU-only, run):**
  `scratchpad/U1/probe_node_quadratic_dropped.jl` — output:
  `luminosity linear = 8.575995299685612e9`, `luminosity quadratic = 8.575995299685612e9`,
  `coordinates bit-identical across :linear/:quadratic under :node = true`,
  and `_require_cuda_pic_options accepts :node + :quadratic + :wavefront (no throw)`.
- **Severity guess:** medium (validation gap; fix is either reject or implement).

### U1-3 — CUDA workspace cache key omits the options the embedded slice-pair Green cache depends on (CPU twin keys them)

- **Where:** pic_cuda.jl:566–585 `_cuda_pic_workspace!` key =
  (label, device, T, grid, lum grid, deposit_method, lum_deposit_method, green_type,
  longitudinal_kick, batch_mode). The workspace owns `slice_pair_green_cache` (line 404),
  but the key omits `Symbol(solver.green_cache)`, `slice_pair_green_min_ratio`,
  `slice_pair_green_growth` (and the slicing), which the CPU twin's green-cache key includes
  explicitly (pic_cpu.jl:170–186) — precisely because entries built under one growth/min_ratio
  regime otherwise get served to a solver with another.
- **Invariant risked:** reproducibility, not correctness: `_cuda_pic_slice_pair_entry_usable`
  (2168–2175) checks coverage/size against the *current* solver, and any usable entry carries
  its own self-consistent (grid, green) pair, so physics stays valid; but mesh choice — and
  hence bit-level results — depends on which solver populated the shared workspace first,
  a coupling the CPU backend deliberately keyed away. Defect class 3, mild instance.
- **Repro (GPU, task path):** one StrongStrongTask, collide with solver A
  (slice_pair_green_growth=0.25), then a same-label solver B (growth=0.0, all keyed fields
  equal): `cache_stats` diagnostics show B hitting A-sized entries; a fresh task with B alone
  produces different meshes.
- **Severity guess:** low.

### Minor notes (not counted as leads)

- `include_hi` in the p1/p2 NamedTuples (pic_cuda.jl:95–98, 242–245, 281–284) is built and
  read by nothing anywhere in src/ (the slicing mask at 5465 computes its own local). Dead
  field; CPU params don't carry it. Inert — cleanup candidate, Phase 6.
- `_cuda_pic_maybe_reclaim`'s `:fixed` branch (621–624) is dead: `_cuda_pic_reclaim_policy`
  hardcodes `:adaptive` (616–618).
- `green_cache` is always `nothing` on the CUDA path (`_cuda_pic_green_cache`/`!` return
  nothing, 587–594) so the `green_cache` parameter threaded through every prepare/green call,
  and the `cache` argument of `_cuda_pic_green_fft` (3449–3452) and
  `_cuda_pic_cached_interaction_grids` (2116–2121), are vestigial. No behavior consequence;
  only the `:slice_pair` workspace cache is live.
- Workspace key stores `solver.luminosity_deposit_method` raw where `deposit_method` is
  `Symbol(...)`-normalized (576–577); field is typed `Union{Nothing,Symbol}` so no effect.
- Feature switches hardwired: `_cuda_pic_wavefront_green_fft_enabled()=true`,
  `_cuda_pic_async_luminosity_enabled()=false`, `_cuda_pic_batched_luminosity_enabled()=false`,
  `_cuda_pic_stack_cached_green_enabled()=true` (451–460) — keep the dead branches in mind
  when reasoning about reachability (the async-luminosity fetch at 997–1001 is currently
  unreachable; correct if ever enabled).

## Checked and found sound

1. **S18 fix (part 5) present and complete.** `_warn_inactive_pic_launch_config` runs at the
   head of `_cuda_pic_collide!` (line 55), covering bare, ctx-nothing, and ctx paths (all
   three collide! entry points funnel through it); short-circuits when the scoped
   `ResolvedCUDAPICLaunchConfig` is installed (interface.jl:268); the composed
   GaussianPIC route also warns (gaussian_pic_cuda.jl:81). Records `:inactive_path` receipt
   plus maxlog=1 warning. No un-warned sibling entry path into `_cuda_pic_threads` found
   in region 1–3000: every launch site goes through `_cuda_pic_threads(family)` which reads
   only the scoped value.
2. **S1 fix (part 2) present.** `_pic_launch_solver` dispatch (interface.jl:221 fallback,
   1298 PICPoissonSolver, gaussian_pic.jl:163 composed) — no `isa PICPoissonSolver` gate
   remains on the install path (`_with_solver_execution_configuration`, interface.jl:223–236).
3. **S14 fix (part 3) present and shared.** `_pic_realign_expanded_grids` invoked by both
   twins after expansion (CPU pic_cpu.jl:1043, CUDA pic_cuda.jl:2148, with an explanatory
   comment); `:integrated` deliberately exempt; `_pic_align_grid_origins` verified idempotent
   for both the `:standard` (±0.25) and default branches (second application computes shift 0).
   `_pic_green_lattice!` now *throws* on fractional cell separation (tol 1e-6 cells,
   pic_cpu.jl:1636–1645) instead of rounding; CUDA lattice routes reuse this checked host
   builder (pic_cuda.jl:2915–2925 wavefront stack, 3460–3472 per-pair). Lattice table cache
   key (nx, ny, quantized rho) covers every quantity the table depends on (scale-invariant in
   h; rho tol 0.5% with measured sensitivity documented); per-axis box mult clamped [8, 64],
   entry cap 384 with lock.
4. **Drift/kick conventions match theory and CPU.** sL=½(c_src−lb_fld), sR=½(c_src−rb_fld)
   identical at pic_cpu.jl:477–478 / pic_cuda.jl:1506–1507, 1374–1378, 1582–1585, 1653–1656,
   1874–1875; field-particle drift ½(z−c) and inverse drift with *new* momentum (Hirata
   synchro-beam) in the indexed node kick 1970–1987 match CPU 528–530/617–619 and
   slice_longitudinal_interpolation.md §1; kick scale 2·kbb everywhere (1969, CPU 594/851);
   pz bookkeeping −¼(px²+py²) old / +¼ new identical (1994–1998 vs CPU 832–834, 864–873);
   longitudinal Kz evaluated from phiL/phiZ on the SAME (left-node) mesh on both backends
   (1877–1885 vs CPU 839–848), as §10.4.1 requires.
5. **Stream/event protocol of the async and batched pair paths.** prep_done recorded after
   green FFTs enqueue (743/846); field tasks and luminosity wait on it; the four field
   streams are host-synchronized before any kick launch (783), so cross-stream phi reads
   (kick on stream 1 reading stream-2-produced phiR) are ordered; luminosity is fetched and
   its stream synchronized BEFORE the in-place kicks in all three pair paths (790–796,
   873–879, 997–1001) — the pre-collision-luminosity data dependency is enforced, and the
   comments record the measured 1.8e-4 regression that motivated it; both collide functions
   end with `CUDA.synchronize(CUDA.stream())` before post-collision tracking on independent
   beam streams (182, 379).
6. **Plane ↔ Green ↔ kick pairing consistent in all four batched layouts.** Batch kernel
   (4318): planes 1–2←green12, 3–4←green21, matching deposits (2352–2363: planes 1–2 from
   source12); stack kernel `plane0÷2+1` arithmetic (4350) matches both the cached-green copy
   layout (2877–2886) and the fused build layout (2900–2905); kick consumption: slice2/rep2
   gets planes offset+1..2 with kbb2 on prep12.field_grid, slice1/rep1 gets offset+3..4 with
   kbb1 on prep21.field_grid (884–903, 1010–1031, 1298–1315), consistent with the documented
   reversed-pairing contract of `_cuda_pic_launch_kick_pair_indexed!` (2049–2066). Node
   6-plane layout (2551–2599): L/Z on gL, R on gR, hx/hy and Green stack filled per-plane
   from the mesh each plane was deposited on.
7. **Batch conflict-freedom.** `collision_pair_batches` (slicing.jl:540–588) never repeats a
   beam-1 or beam-2 slice within a batch (used_i/used_j sets) and preserves per-slice order
   (next_i/next_j readiness), so in-place kicks within a wavefront batch cannot alias, and
   the source-copy protection is only needed on the plain-sequential path — exactly what the
   comment at pic_cuda.jl:41–44 claims; both batched paths deposit all sources before any
   kick (verified by construction of the solve→kick sequence).
8. **Node-mesh prebuild parity.** Turn-start prebuild on both backends (CPU pic_cpu.jl:776–791,
   CUDA 1833–1858) with matching sizing arithmetic: node b's source box unions drifts b and
   min(b+1,nb); field box unions adjacent slices (b−1, b) skipping empty (±Inf) slices;
   NaN (fail fast) vs ±Inf (legitimate empty) distinguished identically (1798–1805 vs
   CPU 728–735); empty-slice pairs skip store and luminosity on both (142–145 vs CPU 90).
9. **Non-finite chokepoints.** Host bound-reductions checked before deposit on both backends
   (1532–1537 vs CPU 516–519/548–551); indexed wavefront checks the fused bounds rows on the
   host copy with correct 8/12-row selection (1629–1644); `_nonfinite_coordinate_error`
   explicitly handles the all-finite "derived quantity" case (interface.jl:503–527), so the
   fused-Gaussian beam2 fallback at 1214 cannot assert what its own scan disproved; empty
   Gaussian slices yield floored moments, not NaN (n==0 branch 5542–5550; fused moment kernel
   guards the anchor read with len>0 at 5813) so the moment poison flag has no false trigger
   from empty slices.
10. **Fused vs plain Gaussian wavefront agree at the host level.** Segment metadata: recipient
    beam's kick = opposing slice weight × own kbb (1148/1159 ≡ 5115/5122); luminosity
    kernel writes density·TWOPI·scale with seg_scale = weight·klum/TWOPI (1151/1162,
    5951) ≡ plain path sum/TWOPI·weight·klum (5126–5132); sampled-beam selection
    (`gaussian_when_luminosity == 1` ⇒ sample beam-2 particles) consistent in max_lum sizing,
    complum flags, and offsets; per-batch lum region [1:lum_offset] exactly covered by the
    complum segments' lengths; `_cuda_gaussian_moment_launch` threads are policy-fixed
    (independent of n), so the shared-memory sizing at 1101–1102 matches the per-column block
    counts at 1129–1130; partials/device_sums/col arrays reuse across batches never reads
    stale planes (kernels bounded by this batch's block_counts/ncolumns/nsegments).
11. **Slice-pair Green cache CPU↔CUDA behavioral parity.** Same key shape (i,j,dir), same
    usability predicate (width/height ≥ requested, requested ≥ min_ratio·cached, coverage
    with 1.5-cell margin — 2168–2197 ≡ CPU 1059–1087), same expand-then-realign on
    miss/rebuild, same hit/miss/rebuild accounting (rebuild count carried into the new
    entry on both, 2154–2160 ≡ CPU 1046–1053); `_cuda_pic_expand_grid_by` lacks CPU's
    factor≤1 early-return but is numerically identical at growth=0.
12. **Luminosity grid construction identical across backends** (nx−1.1 padding, +0.1·tx,
    −0.05·tx, h=(width)/(nx−1)); indexed route pushes per-pair sink records with the same
    schema as the CPU sink (turn, i, j, Float64 luminosity) at 3647–3661 ≡ CPU 114–118.
13. **Workspace lifecycle.** Wavefront cache entries invalidate on capacity growth or
    luminosity-thread change and synchronize the stream before dropping the sole owner of
    queued buffers (2436–2452, 2519–2523); views are contiguous prefixes so linear copyto!
    (bounds → 12-row host array) maps columns correctly; reserve pass pre-sizes both standard
    and node/quadratic (6-plane) workspaces (2485–2495) so no reallocation mid-wavefront.
14. **Closure capture (defect class 4).** All @async closures in the region
    (`_cuda_pic_interaction_pair_async!` 745–753, `_cuda_pic_interaction_pair_batched_fft!`
    848–856, wavefront batched 953–960, `_cuda_pic_field_task` 1439–1449) capture only
    single-assignment locals/arguments; no variable assigned in two scopes is captured, so
    no shared Core.Box race. Timing-stats mutation from concurrent tasks has no yield point
    between read and write (single-threaded task scheduler), and the async-mode caveat is
    printed (525–528).
15. **Reclaim policy** direction correct (`free/total < 0.12` ⇒ pressure ⇒ sync+GC+reclaim);
    adaptive check every 16 pairs; final unconditional pressure check per collide.
16. **Validation coverage** (`_require_cuda_pic_options`): correctly rejects :source_slice on
    CUDA, non-:extrema grid_extent (with accurate reasoning — CUDA bounds are pure mapreduce),
    quadratic on the 2-plane non-batched async route, and node on the sequential batched
    route; `_validate_pic_solver` runs on both entry paths (line 53 covers bare and task).
    Gather/scatter kernels exist with matching arities (gather 11/13 args, scatter 9/11);
    scatter correctly omits z (unchanged by collision).

## Probes

- `scratchpad/U1/probe_node_quadratic_dropped.jl` — run, LEAD CONFIRMED (U1-2).
- `scratchpad/U1/probe_node_wavefront_gate.jl` — run, 9/10 accepted combos drop :node (U1-1);
  includes the GPU repro recipe in its header comment.
