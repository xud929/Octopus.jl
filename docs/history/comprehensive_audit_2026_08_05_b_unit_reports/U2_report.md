# U2 report — `src/tasks/strongstrong/pic_cuda.jl` lines 2000–4000 @ HEAD 7de4d81

Reading unit U2 of the comprehensive audit protocol. Region assigned:
`/cfs/ad/dxu/Library/Julia/Octopus/src/tasks/strongstrong/pic_cuda.jl`
lines 2000–4000 only. No repository file was modified. All probe scripts live in
`/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/`.

## Provenance

**Read line by line (every line):** pic_cuda.jl 1990–4014 (the region plus the two
containing-function tails at each end, so no function was audited half-way).

**Cross-read for contract verification only (not line-audited):** pic_cuda.jl
190–400 (route selection + the new F11 gate), 400–500 (workspace struct, feature
flags), 563–620 (workspace cache key), 1349–1470 (node-indexed wavefront caller),
1520–1580 (`_cuda_pic_prepare_interaction`), 1855–1965 (kick launchers),
4305–4360 (CIC/TSC weights, as consumed by the region's deposit kernels);
pic_cpu.jl 100–130, 330–400 (`_require_cuda_pic_options`), 488–710
(`_pic_interaction!` twin), 820–900 (node twin), 1057–1180 (grid sizing + CPU
slice-pair Green cache twin), 1440–1500 (CPU weights), 1940–2005 (CPU
luminosity twin); interface.jl 280–330, 1180–1320, 1370–1490;
Contracts.jl 600–632, 760–900, 967–1102.

**Executed (real RTX 4500 Ada, CUDA 13.0, Julia project `--project=<repo>`):**
- `probe_quadratic.jl` — CPU↔CUDA parity for `:quadratic`, `:node`,
  `longitudinal_kick=false`, `green_cache=:none`, across five CUDA sub-routes.
- `probe_lum.jl` — CPU↔CUDA parity for `luminosity_deposit_method=:TSC`,
  `deposit_method=:TSC`, `luminosity_grid=(129,129)` across six CUDA routes.
- `probe_twins.jl` — 200 000 random cases × {Float64, Float32} comparing the
  region's host-side grid-cache twins against their `pic_cpu.jl` originals;
  direct charge-conservation measurement of the region's deposit kernels.
- `probe_nodeZ.jl` — wall-clock measurement at N=2e5, 9 slices, grid 64×64 of the
  node wavefront route with `longitudinal_kick` on/off vs its sequential twin.
- (`probe_routes.jl` in this directory was overwritten by another session mid-run;
  its numbers are reproduced by `probe_quadratic.jl` / `probe_lum.jl`.)

The prior-pass reports `U1_report.md` and `U2_report.md` (commit 6a3f39a) were
read to sharpen hypotheses; every line of the region was still read.

---

## Leads

### LEAD U2-1 [low, confidence high] src/tasks/strongstrong/pic_cuda.jl:3672
Claim: the per-pair luminosity diagnostic trace `_ACTIVE_PIC_LUMINOSITY_PAIR_SINK`
is populated on exactly one of the six CUDA PIC routes — the fully-indexed
wavefront one — and is silently empty on every other route, including the default
route whenever the pure diagnostic `pic_timing_detail = true` is set, while the
CPU backend populates it on every route.

Mechanism: the only `push!` into the sink on the CUDA side is inside
`_cuda_pic_wavefront_luminosity_indexed` (pic_cuda.jl:3672–3686). Its gathered
sibling `_cuda_pic_wavefront_luminosity` (pic_cuda.jl:3510–3525) and the per-pair
`_cuda_pic_luminosity` (pic_cuda.jl:3697–3743) — which together serve the
sequential, async-pair, batched-pair, non-indexed-wavefront and gathered-quadratic
routes — never touch the sink. On the CPU the push sits in the generic pair loop
(`pic_cpu.jl:114–119`), so it covers all CPU routes by construction. Because
`pic_timing_detail = true` forces `use_async = false` (pic_cuda.jl:200) and
therefore `use_indexed_wavefront = false` (pic_cuda.jl:217–218), enabling a
diagnostic silently deletes a *different* diagnostic's entire output. This is the
F11 family in its observability form: the F11 fix at pic_cuda.jl:220–233 throws
for `interaction_grid = :node` under that same cascade but leaves the
default `:slice_pair` configuration to lose its pair trace in silence. The
consumer, `StrongStrongPICBackendConsistencyContract`
(Contracts.jl:867–876), gates its pair-trace comparison on
`contract.batch_mode == :wavefront` and would fail loudly on an empty GPU trace —
but the only invocation in the suite (`test/runtests.jl:3786`) uses default
`cuda_*` flags and no diagnostics, so the check has never covered any route but
the indexed one. AGENTS.md: "data and coverage never disappear without a signal".

Repro: run a `StrongStrongTask` PIC collision on `CUDABackend` for 2 turns with 5
slices under `Base.ScopedValues.with(Octopus._ACTIVE_PIC_LUMINOSITY_PAIR_SINK => sink)`
and count `length(sink)`. Expected today (`probe_quadratic.jl` /
`probe_lum.jl`, N=4000, nslices=5, grid=(32,32), turns=2 — 25 pairs × 2 turns = 50
rows):

    CPU (any route) ................................. sink = 50
    CUDA batch_mode=:wavefront, all cuda_* default ... sink = 50
    CUDA cuda_indexed_wavefront=false ............... sink =  0
    CUDA cuda_wavefront_fft=false ................... sink =  0
    CUDA cuda_batch_fft=false ....................... sink =  0
    CUDA cuda_async=false ........................... sink =  0
    CUDA defaults + pic_timing_detail=true .......... sink =  0
    CUDA batch_mode=:sequential ..................... sink =  0

The luminosity totals themselves are correct on every one of those routes (they
agree with CPU to ≤ 5.6e-16 relative); only the per-pair trace vanishes.

---

### LEAD U2-2 [low, confidence high, out-of-hypothesis — efficiency] src/tasks/strongstrong/pic_cuda.jl:2603
Claim: the node-indexed wavefront field solve deposits, Green-multiplies,
inverse-FFTs and differentiates the two longitudinal `Z` planes of every slice
pair even when `longitudinal_kick = false`, when the kick kernel then never reads
them — 2 of 6 planes of wasted field work that both its own sequential twin and
the CPU twin skip.

Mechanism: `_cuda_pic_solve_wavefront_fields_node_indexed!`
(pic_cuda.jl:2582–2655) contains no reference to `solver.longitudinal_kick`: its
`specs` tuple (pic_cuda.jl:2603–2610) unconditionally lists planes `offset+3` and
`offset+6` (the `Z` planes, source drifted by `sR` onto the *left* node's mesh),
the Green stack copies a plane for each (pic_cuda.jl:2629–2631), the batched FFT
and `_cuda_pic_field_wavefront_kernel!` run over all `6 * npairs` planes
(pic_cuda.jl:2639–2652). The consumer
`_cuda_pic_apply_indexed_node_kick!` reads `phiZ` only inside
`if longitudinal` (pic_cuda.jl:2007–2016), and the caller passes only `pp(o+3)` /
`pp(o+6)` — so the `Ex`/`Ey` derivatives of those two planes are dead work even
when the longitudinal kick *is* on. The sequential twin
`_cuda_pic_interaction_node!` guards the third solve correctly
(pic_cuda.jl:1899–1902), as does the CPU `_pic_interaction_node!`
(pic_cpu.jl:~893–897, `phiZ = nothing` unless `solver.longitudinal_kick`).
Correctness is unaffected — measured CPU↔CUDA node parity with
`longitudinal_kick=false` is 1.2e-16 relative.

Repro: `probe_nodeZ.jl` — N=200 000, nslices=9, grid=(64,64), 6 timed turns after
a warm-up, comparing seconds/turn with `longitudinal_kick` true vs false:

    interaction_grid=:node        batch_mode=:wavefront   0.12595 -> 0.11991 s   saving  4.8%
    interaction_grid=:node        batch_mode=:sequential  0.31471 -> 0.19964 s   saving 36.6%
    interaction_grid=:slice_pair  batch_mode=:wavefront   0.05284 -> 0.03333 s   saving 36.9%

The node wavefront route recovers 4.8% where every route that honours the flag
recovers ~37%; the gap is the two `Z` planes it computes and discards.

---

### LEAD U2-3 [low, confidence high, seam] src/tasks/strongstrong/pic_cuda.jl:2140
Claim: the CUDA workspace cache key — which is also the identity of the embedded
slice-pair Green cache this region reads and writes — omits
`solver.interaction_grid`, while the CPU twin key for the same cache carries it;
two solvers differing only in `interaction_grid` (or in `slice_interpolation`)
under the same collision-element label share one Green cache and one `:node`
wavefront workspace.

Mechanism: `_cuda_pic_slice_pair_cached_prep!` (pic_cuda.jl:2140–2183) and
`_cuda_pic_slice_pair_entry_usable` (pic_cuda.jl:2185–2192) operate on
`workspace.slice_pair_green_cache`, which is a field of the `_CUDAPICWorkspace`
obtained from `_cuda_pic_workspace!` (pic_cuda.jl:582–609). That key is
`(:cuda_pic_workspace, label, device, T, grid, luminosity_grid, deposit_method,
luminosity_deposit_method, green_type, longitudinal_kick, batch_mode, green_cache,
slice_pair_green_min_ratio, slice_pair_green_growth)` — the last three added by
the 2026-08-05 fix for U1-3. The CPU's corresponding key,
`_pic_green_cache!` (pic_cpu.jl:181–195), additionally carries
`Symbol(solver.interaction_grid)`. Same defect shape as U1-3, one field short:
the fix derived the missing fields by hand rather than from the CPU key
(Measured Lesson 4, "hand-copied knowledge always drifts"). The `wavefront_cache[:node]`
entry is likewise shared between `interaction_grid=:node` and
`slice_interpolation=:quadratic` (both request `6 * npairs` planes —
pic_cuda.jl:1415, 3271, 3359) although only the former is what its docstring
(pic_cuda.jl:2516–2530) describes. No correctness impact is expected: the
`:node` route never writes slice-pair entries, and every reuse is re-validated by
`_cuda_pic_grid_size_usable` / `_cuda_pic_grid_covers_bounds` before it is
returned (pic_cuda.jl:2185–2214). The exposure is reproducibility drift of the
cache hit/miss/rebuild history, which
`_strong_strong_contract_cuda_cache_history` compares against the CPU's.

Repro: static — diff the two key tuples:
`sed -n '585,605p' src/tasks/strongstrong/pic_cuda.jl` against
`sed -n '181,195p' src/tasks/strongstrong/pic_cpu.jl`; the CPU tuple's last
element is `Symbol(solver.interaction_grid)` and the CUDA tuple has no
counterpart. Behavioural repro: build one `StrongStrongTask` containing two
`StrongStrongCollision(:ip; poisson_solver=…)` elements whose solvers differ only
in `interaction_grid`, run on `CUDABackend`, and read
`Octopus._strong_strong_contract_cuda_cache_history(task)` — the hit/miss counts
are those of the merged cache, not of either solver alone. The pointer that
survives line drift: "the CUDA workspace cache key lacks the
`interaction_grid` element that `_pic_green_cache!` has".

---

## Clean list — what was checked and what makes the claim checkable

1. **CPU↔CUDA physics parity of every route reachable from this region.** Measured,
   not argued. Two-turn strong-strong PIC, N=4000, nslices=5, grid=(32,32),
   `normal_quantile` slicing with `center_position=:centroid`, `green_cache=:slice_pair`,
   comparing all six phase-space coordinates of both beams against the CPU run of
   the *same* solver options (beam scale 0.248):

   | configuration | routes covered | max coord rel. diff | max luminosity rel. diff |
   |---|---|---|---|
   | `:linear`, `:slice_pair` | indexed wf / gathered wf / per-pair batched / async pair / sequential / +`pic_timing_detail` | 1.6e-16 | 2.8e-16 |
   | `slice_interpolation=:quadratic` (region's 6-plane paths, pic_cuda.jl:3089–3466) | same 5 sub-routes | 1.5e-16 | 2.8e-16 |
   | `interaction_grid=:node` | indexed wf, sequential | 1.1e-16 | 4.1e-16 |
   | `:node` + `longitudinal_kick=false` | indexed wf, sequential | 1.2e-16 | 2.8e-16 |
   | `:quadratic` + `longitudinal_kick=false` (F10 regression) | indexed wf, gathered wf | 1.3e-16 | 0.0 |
   | `deposit_method=:TSC` | indexed wf, gathered wf, sequential | 1.4e-16 | 7.0e-16 |
   | `luminosity_deposit_method=:TSC` | 6 routes incl. `:node` | 1.7e-16 | 5.6e-16 |
   | `luminosity_grid=(129,129)` + TSC | indexed wf, gathered wf | 1.5e-16 | 3.5e-15 |
   | `green_cache=:none` | indexed wf, gathered wf | 1.9e-16 | 2.8e-16 |

   No route in this region degrades a requested option's physics. `:node` under
   `pic_timing_detail=true` throws the new F11 `ArgumentError`, as designed.
   (`probe_quadratic.jl`, `probe_lum.jl`.)

2. **The U5-8 luminosity fix inside this region is correct and load-bearing.**
   `_cuda_pic_luminosity`'s `lum = sum(q1 .* q2)` over the full `(nx+1)×(ny+1)`
   plane (pic_cuda.jl:3735–3742) and the node-count launches at
   pic_cuda.jl:3584–3588 and 3661–3670 were checked against the CPU
   `_pic_luminosity!` (pic_cpu.jl:1969–2005) expression by expression — same
   `nx-1.1` / `+0.1tx` / `−0.05tx` padding, same `hx = width/(nx-1)`, same full
   extent, scale differing only in ulp (`/(hx*hy)` vs `*hxi*hyi`). Directly
   measured (`probe_twins.jl` T3, n=20 000 particles, luminosity grid 128×128):
   TSC deposits 0.2667 of 20 000 charge units (1.33e-5) into the row/column the
   *old* `1:nx, 1:ny` window excluded, which the current code captures; CIC
   deposits 0.0 there (Float64) so CIC is bit-identical, exactly as the code
   comment claims. Total deposited charge on the luminosity plane: relative
   deficit 1.8e-16 (Float64 TSC), 0.0 (Float64 CIC, Float32 TSC).

3. **No dropped charge from any deposit launched in this region.**
   `probe_twins.jl` T2 reconstructs the exact mesh the code builds
   (`_pic_interaction_grids`, then `_cuda_pic_expand_grid_by` +
   `_pic_realign_expanded_grids` for the cached path), deposits 20 000 drifted
   particles with `_cuda_pic_deposit_drifted_nomask_kernel!`
   (pic_cuda.jl:3977–4014) and sums the padded plane: relative deficit **0.0** for
   Float64 × {CIC, TSC} × growth ∈ {0, 0.25} and Float32/CIC; 1.95e-7 for
   Float32/TSC, which is Float32 summation rounding over 20 000 adds, not a drop.
   The structural reason: `_pic_interaction_grids` places the origin at
   `min − 1.5·tx` with `width` grown by `3·tx`, so every particle sits at
   `u ∈ [1.5, nx−2.5]`, inside both the CIC (`[0, n−1]`) and TSC guard windows at
   pic_cuda.jl:4313–4331; and every cached-mesh reuse is gated by
   `_cuda_pic_grid_covers_bounds` with the same 1.5-cell margin.

4. **Hypothesis (b), "box sized before the kicks, deposit after", does not apply
   in this region.** Every wavefront entry point here computes all bounds and
   preps, then *all* deposits, and only then *all* kicks — verified by reading
   the statement order of `_cuda_pic_interaction_wavefront_quadratic_batched_fft!`
   (pic_cuda.jl:3221–3305) and `…_quadratic_indexed_batched_fft!`
   (pic_cuda.jl:3308–3391); slice pairs inside one wavefront batch are disjoint by
   construction (`collision_pair_batches`), and each batch re-preps. Luminosity is
   evaluated before the in-place kicks at pic_cuda.jl:3252–3256 and 3341–3344,
   matching the CPU, whose `vx/vy` are the pristine source coordinates drifted by
   `sM = 0.5(c_source − c_field)` (pic_cpu.jl:698–708) — identical to the CUDA
   `s1 = 0.5(p1.center − p2.center)`, `s2 = −s1` (pic_cuda.jl:3701–3702, 3614–3615).

5. **Slice-pair Green cache host arithmetic is an exact twin of the CPU's.**
   `probe_twins.jl` T1: 200 000 randomized (grid, request, bounds) triples per
   precision, Float64 and Float32, comparing
   `_cuda_pic_grid_size_usable` ↔ `_pic_grid_size_usable`,
   `_cuda_pic_grid_covers_bounds` ↔ `_pic_grid_covers_bounds`, and
   `_cuda_pic_expand_grid_by` ↔ `_pic_expand_grid_by` at growth ∈ {0, 0.25, 1.0}.
   Mismatches: **0 / 0 / 0** in every category. (The CPU's extra
   `factor <= one(factor) && return grid` early exit is inert because
   `slice_pair_green_growth >= 0` is validated at interface.jl:1249–1251 and
   `width * 1.0 == width` exactly; the probe covers growth = 0 explicitly.)
   Cache-statistics bookkeeping (`hits`/`misses`/`rebuilds`, `entry.uses`,
   `entry.rebuilds` carry-over) at pic_cuda.jl:2146–2177 matches
   `_pic_slice_pair_green!` (pic_cpu.jl:1111–1135) statement for statement.

6. **Plane layouts, Green→plane mappings and kick pairings of the region's four
   batched field solves are internally consistent.** Checked index by index:
   - node, 6 planes/pair (pic_cuda.jl:2603–2610 + 2629–2631 + caller 1434–1445):
     `+1 L/gL`, `+2 R/gR`, `+3 Z drift sR on gL`, `+4..+6` the same for direction 2;
     `hx/hy` per plane come from the mesh that plane was deposited on
     (pic_cuda.jl:2616–2617). The `Z` plane's `sR` drift on `gL`'s mesh matches
     `_cuda_pic_interaction_node!` (pic_cuda.jl:1900–1901) and the theory note's
     requirement that `phiL − phiZ` be differenced within one mesh.
   - quadratic, 6 planes/pair (pic_cuda.jl:3111–3123 gathered, 3173–3192 indexed):
     `L / M=(sL+sR)/2 / R` per direction, all three on that direction's mesh and
     Green (justified: `x + px·s` is affine in `s`, so the L/R box contains the
     midpoint plane); `hx_host[offset+1..3] ← prep12`, `[offset+4..6] ← prep21`
     agrees with the deposit assignment; the kicks at 3288/3294 and 3376/3381 pair
     `rep2 ← planes o+1..3 (prep12, source_center = p1.center, field_grid =
     prep12.field_grid)` and `rep1 ← planes o+4..6 (prep21)`, i.e. the convention
     documented at pic_cuda.jl:2066–2083 is honoured.
   - slice-pair, 4 planes/pair (pic_cuda.jl:2678–2705, 2803–2824) and its Green
     stack `_cuda_pic_copy_green_spectral_stack!` (2896–2905, two Greens per pair).
   - `_cuda_pic_copy_green_spectral_stack_quadratic!` (3076–3087) duplicates each
     direction's Green into its three slots, making the spectral multiply a 1:1
     elementwise product against `_cuda_pic_multiply_spectral_perplane_kernel!`
     (3013–3022), whose linear-index sweep is valid because both operands are
     contiguous `1:requested` views of equal length.

7. **Workspace sizing and view arithmetic are sound.**
   `_cuda_pic_allocate_wavefront_workspace` (2410–2446) and
   `_cuda_pic_wavefront_workspace!` (2448–2502): `overlap_length =
   cld(prod(lgrid .+ 1), luminosity_threads) * npairs` is exactly the
   `blocks_per_pair * npairs` the overlap kernel is launched with
   (3665–3666), so `sum(wf.luminosity_overlap_partials)` reads only blocks written
   this call and no stale tail; the entry is invalidated when
   `luminosity_threads` changes (2456–2457) and a `CUDA.synchronize` precedes the
   drop of the previous buffers (2458–2462). `luminosity_q1/q2` are
   `(lnx+1, lny+1, npairs)`, matching the `Int32(nx+1), Int32(ny+1)` deposit
   dimensions at 3576/3580 and 3653/3657 and the workspace's single-pair
   `(lnx+1, lny+1)` buffers used by `_cuda_pic_luminosity` (3722–3723, allocated at
   pic_cuda.jl:574–575, size pinned by the workspace key's `_pic_luminosity_grid`
   element). The `:node` workspace (2531–2565) is a separate cache entry, so the
   `:standard` slice-pair workspace is never disturbed;
   `_cuda_pic_reserve_wavefront_workspaces!` (2504–2514) reserves it for both
   `:node` and `:quadratic` (caller, pic_cuda.jl:244–249).

8. **Option plumbing in the region has no silent replacement.** Every branch in
   2000–4000 that selects behaviour was enumerated: cache hit/miss (2146),
   workspace (re)allocation (2456, 2539), `gpic_subtract` presence and coupled
   variant (2714, 2717, 2831, 2834), Green-stack source (2734/2742/2748/2757,
   2851/2860/2865/2873), `green_type == :lattice` host build (2934, 3479),
   `_cuda_pic_batched_luminosity_enabled()` (3512), `prepared_bounds === nothing`
   (3616), sink presence (3673). Of these only the last two depend on anything but
   a compile-time constant or a genuinely equivalent alternative, and neither
   changes physics. The `method_code = … == :CIC ? 1 : 2` and
   `green_code = … == :integrated ? 1 : 2` ternaries (2050, 2096, 2297, 2330, 2365,
   2592, 2668, 2793, 2952, 3099, 3161, 3455, 3494, 3545, 3610, 3728) map an unknown
   symbol onto TSC/standard rather than throwing, but `deposit_method`,
   `luminosity_deposit_method` and `green_type` are closed enumerations validated at
   interface.jl:1255–1258 and 1257, and `:lattice` is intercepted by the preceding
   `if`, so no reachable value is misrouted. `interaction_grid = :source_slice` and
   `grid_extent ≠ :extrema` are rejected loudly by `_require_cuda_pic_options`
   (pic_cpu.jl:358–400), so the CPU's estimator/union machinery has no silent
   CUDA counterpart to drop.

9. **Green-function construction (2907–2978, 3468–3508, 3829–3937) and the field
   solves (2288–2408).** `_pic_interaction_grids` (pic_cpu.jl:1057–1101) gives the
   source and field grids *identical* `width`/`height`, and both the per-pair
   expansion (2159–2166) and the wavefront stack scale them by the same factor, so
   the single `hx = source_grid.width/(nx−1)` handed to
   `_cuda_pic_field_kernel!` / `_cuda_pic_field_wavefront_kernel!` is the common
   cell size — the discrete convolution's precondition holds on every route here.
   `:lattice` is built on the host from the same `_pic_green_lattice!` the CPU
   uses (2937–2944, 3483–3486), so its values are bit-identical to CPU by
   construction; `_cuda_pic_green_stack_kernel!` (3873–3921) decomposes
   `plane0 = (index−1) ÷ plane_size` and `i0/j0` correctly for column-major
   `(2nx, 2ny, nplanes)`, and is expression-identical to the single-plane
   `_cuda_pic_green_kernel!` (3829–3871) modulo the per-plane parameter fetch.

10. **Deposit kernels (3940–4014) index in range on every launch reachable from
    this region.** Interaction deposits pass `(Int32(nx), Int32(ny))` into
    `2nx × 2ny` padded planes — CIC reaches `ix+1 ≤ nx`, TSC `base+2 ≤ nx`;
    luminosity deposits pass `(Int32(nx+1), Int32(ny+1))` into exactly
    `(nx+1, ny+1[, npairs])` — CIC reaches `nx+1`, TSC `base+2 ≤ nx+1`. Confirmed
    by the guards at pic_cuda.jl:4313 and 4329 plus the `max(1, min(base, n−1))` /
    `max(1, min(base, n−2))` clamps.

---

## Not checked, and why

- **Everything outside 2000–4000.** The kick kernels themselves
  (`_cuda_pic_kick_quadratic_kernel!`, `_cuda_pic_kick_pair_indexed_*`), the
  interpolators, the field stencils, the CIC/TSC weight functions, the
  `:equal_area` / `:equal_count` slicing kernels and the Gaussian moment
  reductions were read only where a call from my region required verifying a
  contract; they belong to U1 and U3. The one thing I relied on and could not
  re-derive in-region is that `_cuda_pic_interpolate_field` never reads its `phi`
  arguments — the R-node call at pic_cuda.jl:1997–1999 passes `phiL` into both
  `phi` slots, which the previous pass flagged as a latent trap (its observation
  §2) and which is still present. Restated here only because the caller
  `_cuda_pic_apply_indexed_node_kick!` straddles my region's lower edge.
- **The `equal_area` slice-membership lead (prior U2-2).** The kernel it concerns
  is at pic_cuda.jl:5259+, outside my region; the 63-commit diff shows it was
  rewritten to transcribe the CPU `_slice_bin` rule exactly, so the lead reads as
  closed, but verifying that is U3's line-by-line job, not mine.
- **`interaction_grid = :node` + `slice_interpolation = :quadratic`** (prior
  U1-2: node silently wins on both backends). Reproduced incidentally — the
  4.1e-5 coordinate difference in my first `:node` table is `:node` vs
  `:quadratic` physics, not a backend defect — but the precedence itself lives at
  pic_cuda.jl:251 and pic_cpu.jl:820+, outside my region.
- **`_cuda_pic_wavefront_luminosity_batched` (3527–3593) was not exercised on the
  device.** `_cuda_pic_batched_luminosity_enabled()` is a hard `false`
  (pic_cuda.jl:471), so the function is unreachable; its plane and block
  arithmetic was verified statically only (it now uses the `(nx+1)·(ny+1)` node
  counts consistently with the live path).
- **Float32 end-to-end collisions.** The parity table above is Float64. Float32 was
  covered only at the kernel/host-function level (`probe_twins.jl` T1–T3);
  a full Float32 CPU↔CUDA collision comparison was not run.
