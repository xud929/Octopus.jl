# U1: pic_cuda.jl, first third

Tree: `/cfs/ad/dxu/Library/Julia/Octopus` at `24e8683` (read-only; no repository file was
modified, no git command was run). Probes and logs:
`/cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U1/`.
GPU: NVIDIA RTX 4500 Ada Generation (`DEVICE_ATTRIBUTE_MAX_THREADS_PER_BLOCK = 1024`).

## Region

`src/tasks/strongstrong/pic_cuda.jl` lines 1-2200 of 6492 (2200 lines). The whole file is one
`if _HAS_CUDA; @eval begin ... end; end` block, so every definition is indented eight spaces
and none of the file's kernels (`function _cuda_*_kernel!`) lie inside the region: lines
1-2200 are the host-side orchestration of the CUDA PIC route — the three `collide!` entry
points, the sequential and wavefront collide drivers, the workspace/timing/reclaim plumbing,
slice gather/scatter, the per-pair interaction drivers (async, batched-FFT, wavefront,
indexed, node-indexed), the fused Gaussian wavefront driver, the bounds/prepare stage, the
node-mesh builders, and the dropped-charge wrappers. The region ends mid-function inside
`_cuda_pic_launch_kick_quadratic!` (2196-2218); lines 2196-2200 were read, the rest of that
function belongs to the next unit.

## Provenance

READ line by line: `src/tasks/strongstrong/pic_cuda.jl` 1-2200 (all of it).

READ out of region, only to validate what the region calls (nothing below is reported as a
finding against those lines): pic_cuda.jl 2219-2420 (kick launchers and the indexed node
kick the region's plane layout feeds), 2698-2870 (wavefront workspace allocation and sizing
the region's bounds launches index into), 3799-4060 (`_cuda_pic_wavefront_luminosity*`,
`_cuda_pic_luminosity` — the region's luminosity callees, checked for the per-pair sink push),
4061-4125 (gather/scatter/mask kernels), 4248-4297 (count-outside kernels), 4569-4664 (the
four bounds kernels the region launches), 6129-6136 and 6216-6330 (moment launch, reduce and
build-moments kernels launched from the fused Gaussian driver).
CPU twin `src/tasks/strongstrong/pic_cpu.jl`: 183, 225-345 (collide loop, `:pic_pair_schedule`
receipt, `npairs`), 394-470 (`_pic_collide_pair!`), 560-644 (dropped report, workspace and
Green-cache keys), 646-734 (`_validate_pic_solver`, flags), 870-959
(`_require_cuda_pic_options`), 1116-1200 (`_pic_interaction!` bounds), 1546-1760
(`_pic_build_node_grids!`, `_pic_prebuild_node_caches!`, `_pic_node_grid!`,
`_pic_interaction_node!`), 1792-1800, 1854-1896, 1926-1970 (`_pic_interaction_grids`).
`src/tasks/strongstrong/interface.jl` 85-240, 240-340, 556-600, 3020-3035;
`src/policies/Policies.jl` 180-215, 1325-1350; `src/tasks/strongstrong/slicing.jl` 690-770;
`src/tasks/BeamObservers.jl` 36-75; `test/runtests.jl` 23995-24080 (the thread-cap pin);
`docs/theory/node_interaction_grid.md` sections 3-4;
`docs/history/comprehensive_audit_2026_08_05_b_unit_reports/U1_report.md` in full.

EXECUTED (all under `probes/U1/`, logs beside the scripts):

- `probe_launch_1024.jl` → `probe_launch_1024.log`. Part 1 compiles the twelve light kernels
  the region launches without `_cuda_launch_capped!` and reads `CUDA.maxthreads` /
  `CUDA.registers`: eleven report `maxthreads = 1024` (8-62 registers);
  `_cuda_pic_force_luminosity_bounds_indexed_kernel!` reports **68 registers, maxthreads 896**.
  Part 2 runs eight strong-strong routes through `StrongStrongTask` with every PIC launch family
  = 1024 and `CUDAExecutionPolicy(threads=1024)`, 3 slices, 4000 particles/beam, 1 turn:
  seven ran (with the kick kernels capped to 512/640/384 by `_cuda_launch_capped!` and the
  cap receipts present); **the default route (PIC wavefront, fully indexed) failed** with
  `Block register count exceeds device limit (68 regs/thread * 1024 threads/block = 69632 >
  65536 regs/block)`.
- `repro_field_threads.jl` → `repro_field_threads.log`. Minimal repro of the lead above:
  `field_threads=896` RAN; `field_threads=1024` FAILED; plain
  `CUDAExecutionPolicy(launch=CUDALaunchConfig(threads=1024))` with no `CUDAPICLaunchConfig`
  FAILED (every family inherits 1024); `field_threads=1024` with
  `luminosity_schedule=AtTurns(Int[])` RAN (the 48-register non-luminosity bounds kernel fits).
- `probe_float32_twin.jl` → `probe_float32_twin.log`. CPU vs CUDA, default PIC route, one
  collision, Float64 and Float32 beams, 3 slices, 4000 particles/beam, grid 32×32, default
  flags. Float64: `max|dx|/sigma_x = 5.1e-16`, `max|dpx|/max|px| = 4.4e-15`,
  `max|dy|/sigma_y = 3.3e-14`, `max|dpy|/max|py| = 4.8e-14`. Float32: `3.4e-7`, `2.0e-6`,
  `1.9e-5`, `3.5e-5` respectively — nine orders of magnitude above the Float64 gap and 6-600
  Float32 ulps of the beam scale, both backends returning `Float32` coordinates.

## Leads

### LEAD U1-1 [Major, confidence high] src/tasks/strongstrong/pic_cuda.jl:1839
Claim: the wavefront bounds launch in `_cuda_pic_prepare_interaction_wavefront_indexed!` passes the raw `:field` family thread count straight to `CUDA.@cuda`, and `_cuda_pic_force_luminosity_bounds_indexed_kernel!` compiles to 68 registers (maxthreads 896 on the RTX 4500 Ada), so the default production route (`batch_mode = :wavefront`, fully indexed, luminosity on) dies at this line for any `field_threads` in 897:1024 — including the plain `CUDAExecutionPolicy(threads=1024)` with no PIC launch config at all — although that value passes the only upstream validation.
Mechanism: `_resolve_cuda_pic_configuration` (interface.jl:226-232) validates each family only against `DEVICE_ATTRIBUTE_MAX_THREADS_PER_BLOCK` (1024), which cannot see register pressure; `CUDAPICLaunchConfig` admits 1:1024 (interface.jl:138); and `nothing` for a family inherits `policy.threads`, so a user who sets only the generic CUDA thread count to 1024 reaches this launch with 1024. The file's own answer to exactly this failure class — `_cuda_launch_capped!` (lines 65-92, written for the 2026-08-05_b U3-2 defect, "a value that is legal by that check is not launchable") — wraps the five kick launchers but not this site. The launch at 1839/1844 (and the non-luminosity twin at 1850/1855, 48 registers, which does fit today) was a literal `256` until the 2026-08-05_b U1-3 repair rerouted it through `_cuda_pic_threads(:field)`; that repair made the public option reach the launch and thereby made the launch able to fail, while the comment it left (1808-1818) states that the shared array is "sized for up to 1024 threads" — true, but register use, not shared memory, is the binding limit. The failure is loud (an exception) but late: it fires inside the first batch of the first collision, after the task has started, and the suite's pin for this class ("A launch the device accepts but the kernel cannot run", runtests.jl:24011) sweeps 512 only and, for PIC, only `kick_threads`, so it cannot see any non-kick family. The 68-register count is 4 registers over the 64-per-thread ceiling that 1024 threads allow (65536/1024), i.e. this kernel sat just past the edge and nothing measured it; `_cuda_pic_finalize_force_luminosity_bounds_kernel!` sits at 62, two registers under, saved only by its fixed 64-thread launch.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U1/repro_field_threads.jl` prints `registers=68 maxthreads=896 device max=1024`, then `field_threads=896 (explicit) RAN`, `field_threads=1024 (explicit) FAILED: Block register count exceeds device limit (68 regs/thread * 1024 threads/block = 69632 > 65536 regs/block)`, `policy threads=1024, no CUDAPICLaunchConfig FAILED: ...` and `field_threads=1024, luminosity disabled RAN`. The durable identity: `CUDA.maxthreads(CUDA.@cuda launch=false Octopus._cuda_pic_force_luminosity_bounds_indexed_kernel!(args...))` is below the device maximum while the launch site passes `_cuda_pic_threads(:field)` to `CUDA.@cuda` without consulting it.

### LEAD U1-2 [Minor, confidence med] src/tasks/strongstrong/pic_cuda.jl:65
Claim: the launch cap exists at two of the region's eighteen launch sites (thirteen of seventy-three file-wide), no tripwire derives the set of launch sites or the per-kernel ceiling, and the only pin sweeps one value (512) on one PIC family (`kick_threads`), so a kernel crossing the 64-register line anywhere else is invisible until a user's run dies — which is how U1-1 reached 24e8683.
Mechanism: `_cuda_launch_capped!` is opt-in per call site; the region's raw `CUDA.@cuda threads=` sites are 870, 881, 886, 901 (`:gather_scatter`), 1398 (fixed 256), 1404, 1407 (policy threads via `_active_cuda_launch`), 1824, 1839, 1844, 1850, 1855 (`:field`), 1863, 1867 (fixed 64), 2133, 2146 (`:deposition`), against `_cuda_launch_capped!` at 1412 and 1964. The public surface admits 1024 for every family and for the generic policy, so every raw site is a latent U1-1 whose margin is a register count nobody records: measured today, gather 40, scatter 26, mask 17, count 24, bounds-init 8, bounds 48 / 68, finalize 46 / 62, with 64 the ceiling for 1024 threads. This is the hand-copied-knowledge class (AGENTS.md: derive from one source, add a coverage tripwire) applied to launch sites, the same shape the file already names for "launch sites" in its invariants, and the test-quality class (a pin whose instrument was never fed the defect it now harbours: the pin asserts caps "conditionally" and passes with zero caps).
Repro: `awk 'NR<=2200 && /CUDA\.@cuda/ && !/launch *= *false/' /cfs/ad/dxu/Library/Julia/Octopus/src/tasks/strongstrong/pic_cuda.jl | wc -l` → 16 raw sites in the region versus `awk 'NR<=2200 && /_cuda_launch_capped!\(/ && !/function/' ... | wc -l` → 2; and `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 .../probes/U1/probe_launch_1024.jl` Part 1 prints the per-kernel `maxthreads`/`registers` table above (one row below 1024), Part 2 the route table (one of eight routes FAILED at 1024). A tripwire would compile every `_cuda_*_kernel!` the file launches raw and assert `maxthreads >= 1024`, or route every launch through the cap.

### LEAD U1-3 [Minor, confidence med] src/tasks/strongstrong/pic_cuda.jl:1743
Claim: the region's host bookkeeping runs at the beam's element type (`T = eltype(source.x)` in `_cuda_pic_prepare_interaction`, `_cuda_pic_interaction_node!`, `_cuda_pic_build_node_grids!`, and `T(kbb)` in every kick launcher), while the CPU twin promotes through the kick constant (`T = promote_type(eltype(source.x), eltype(field.x), typeof(kbb))`, pic_cpu.jl:1141 and 1703), so for a Float32 beam the two backends size their meshes and scale their kicks in different precisions and no contract or declared rounding class covers it — the parity contracts never instantiate a Float32 beam (`grep -c Float32 src/contracts/Contracts.jl` → 0).
Mechanism: identity for Float64 beams (the only precision the suite compares), so the twin agreement the previous audit measured (1.3e-13) says nothing about Float32; at Float32 the CPU computes `sL`, `sR`, the drifted bounds, `_pic_interaction_grids` and `kick_scale = 2*kbb` in Float64 and rounds once at the particle, whereas the CUDA path rounds `kbb` and every bound to Float32 first, so the meshes (`x0`, `width`) can differ by a Float32 ulp and land on different quantized ladders when `grid_quantize > 0`. Out of hypothesis 1's "fused or reordered arithmetic", in its "without a declared class" clause. Measured (`probe_float32_twin.log`, same configuration for both precisions): the Float64 CPU/CUDA gap is `5.1e-16` (x/sigma_x), `4.4e-15` (px), `3.3e-14` (y/sigma_y), `4.8e-14` (py); the Float32 gap is `3.4e-7`, `2.0e-6`, `1.9e-5`, `3.5e-5` — up to 600 Float32 ulps of the beam scale, i.e. not the rounding floor of a shared algorithm but two algorithms carried at different working precisions, and no document, contract or tolerance table states which is the reference or what the bound is.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U1/probe_float32_twin.jl` prints, per element type, `max|dx|/sigma_x`, `max|dpx|/max|px|`, `max|dy|/sigma_y`, `max|dpy|/max|py|` between the CPU and CUDA beams after one collision; the durable identity is the ratio of the Float32 gap to the Float64 gap on the same configuration, together with the absence of any Float32 instantiation in `src/contracts/Contracts.jl`.

### LEAD U1-4 [Minor, confidence low] src/tasks/strongstrong/pic_cuda.jl:1569 — OUT OF HYPOTHESIS
Claim: `_cuda_pic_interaction_wavefront_node_indexed!` keeps a silent lazy node-mesh build (`if isempty(nc1)` → gather the source slice now → `_cuda_pic_build_node_grids!` with `field_slices = nothing`, lines 1569-1581) on the path where the CPU twin deliberately throws (`_pic_collide_pair!`, pic_cpu.jl:446-452: "An insert here would ... build the mesh from a partially kicked beam, the 3.8e-5 CPU/CUDA divergence that the prebuild exists to prevent"), so the two backends answer the same broken invariant in opposite ways: one loud, one with a schedule-dependent mesh.
Mechanism: dead today by construction — `_cuda_pic_collide_wavefront!` (330-336) prebuilds both directions before the batch loop, and `_cuda_pic_build_node_grids!` fills nodes `j` and `j+1` for every non-empty field slice `j`, so a `valid` pair (both index sets non-empty) always finds its caches populated and `keep[n]` is never cleared. But the function takes `node_cache` as a parameter and does nothing to ensure the prebuild ran; the lazy branch gathers `rep1`/`rep2` mid-turn (after earlier batches' kicks, which rewrite `x`, `y`, `px`, `py` in place, see 2290-2293), which is exactly the state-dependence the CPU made an error. A future caller that forgets the prebuild (or a prebuild that starts skipping slices) degrades silently on CUDA and fails loudly on CPU — the twin-divergence class in its "silent vs loud" form, and the neighbour of a fix (the prebuild was added to close a measured divergence; its guard was added on one backend only).
Repro: static — `sed -n '1565,1587p' src/tasks/strongstrong/pic_cuda.jl` shows the `isempty(nc1)`/`isempty(nc2)` rebuild branches and the `keep[n] = false` skip, versus `sed -n '438,452p' src/tasks/strongstrong/pic_cpu.jl` showing the `error(...)`; dynamic — call `Octopus._cuda_pic_interaction_wavefront_node_indexed!` with an empty `Dict{Tuple{Int,Int},Dict{Int,Any}}()` after a first collision has kicked the beams: it returns a luminosity and kicks with meshes built from the post-kick state, where the CPU path with an empty cache throws `PIC node mesh cache is missing or empty`.

## Clean

Hypothesis 2 (device IR): the region contains no kernel body. The only `throw` in lines
1-2200 is the host-side `ArgumentError` at 353 (a concatenation of string literals, no
interpolation); there is no `@assert` and no `error(`; the seven other error sites
(1427, 1430, 1771, 1774, 1885, 2049, 2053) call `_nonfinite_coordinate_error`, which is
host-side, converts device arrays with `Array(a)` before scanning (interface.jl:558), and
has a `bad == 0` branch whose message explains the cross-beam moment case (interface.jl:581-600)
— so the fused Gaussian driver's unconditional beam-2 report at 1430-1433 cannot mis-describe
a finite beam. Every kernel argument marshalled from the region is isbits (`Bool`
`longitudinal_kick`, `Int32` codes and extents, `T`-typed grid geometry, `Val(COUPLED)`,
`Val(LONGITUDINAL)`) or a device array/view; `nothing` as `idx` (2128-2152) selects a kernel
specialization that the probe compiled (`_cuda_pic_count_outside_drifted_kernel! (nothing)`,
24 registers). `_pic_slice_context` at 1890 is defined (interface.jl:617-620, a
`Tuple{Int,Int}` method matches the call).

Hypothesis 3 (indexing and coverage): every kernel the region launches raw is grid-strided
(`while index <= length(...)`: gather/scatter/mask 4063-4123, count 4250-4294, bounds
4585-4624, reduce-partials 6219-6232, build-moments 6292-6308) or exactly covered
(`_cuda_pic_init_wavefront_bounds_partials_kernel!` at `blocks = cld(length, threads)` with an
`index <= length` guard; the finalize kernels at one block per column with `threads =
_CUDA_PIC_BOUNDS_PARTIAL_BLOCKS = 64` reading `partials[row, thread, column]` whose second
extent is exactly 64, 2730); `blocks1/blocks2 = min(cld(n, threads), 64)` (1835-1836) relies on
the grid stride, and untouched partial slots keep the neutral `(Inf, -Inf, ...)` the init pass
wrote (row parity at 4572-4574 matches the 12-row leading dimension at 2728-2732). Capped
launches rescale an `Integer` block count (`cld(blocks*requested, threads)`, 84) and leave
tuple grids alone, which is correct because both call sites (1412, 1964) are grid-strided. The
empty-slice launches the previous audit flagged as unreachable are still guarded: 222 and
513-514 skip `_cuda_pic_store_slice!` on `nothing` slices; `_cuda_pic_extract_slice` returns
`nothing` at `n == 0` (851); `_cuda_pic_count_outside_*!` return at `n == 0` (2130, 2143).
Measured (probe Part 2): all eight routes launch and complete at 1024 threads except the one
in U1-1, with `_cuda_launch_capped!` recording `(_cuda_pic_kick_longitudinal_kernel!, 1024, 512)`,
`(_cuda_pic_kick_node_kernel!, 1024, 512)`, `(_cuda_pic_kick_node_indexed_kernel!, 1024, 640)`,
`(_cuda_gaussian_fused_kick_kernel!, 1024, 384)`, `(_cuda_slice_kick_kernel!, 1024, 384)`;
`_cuda_gaussian_reduce_partials_kernel!` and `_cuda_gaussian_build_moments_kernel!` (raw,
policy threads 1024) ran. Launch configuration is read, not assumed: every thread count in
the region comes from `_cuda_pic_threads(family)` (seven families, interface.jl:91-93, device
max validated at 226-232, receipt per read), `_active_cuda_launch` (receipted), or the two
documented fixed values (`_cuda_gaussian_moment_launch` 256 "fixed_for_reproducibility",
receipted at 6132; `_CUDA_PIC_BOUNDS_PARTIAL_BLOCKS` 64, a reduction width). `grep "threads *=
*[0-9]"` over 1-2200 returns only the comment at 52. The bare `collide!` path warns and records
`:cuda_pic_configuration => :inactive_path` when a solver carries a config it cannot install
(159, interface.jl:292-304); the `:cuda_pic_algorithm` and `:pic_pair_schedule` receipts record
what RAN (`use_async`, `use_batch_fft`, `use_wavefront_fft`, `use_indexed_wavefront` are the
runtime values after the `pic_timing_detail` downgrade, 175-185, 323-367), with `pairs` equal
to the CPU's `npairs = length(order)` (pic_cpu.jl:183): the full slice product on the
sequential route (194) and `sum(length, batches)` on the wavefront route (372).

Hypothesis 1 (twin bookkeeping, Float64): compared expression by expression against pic_cpu.jl.
`sL = T(0.5)*(T(center) - T(lb))`, `sR` likewise (1744-1745 vs 1143-1144, 2167-2168 vs
1704-1705); source bounds as the min/max over both planes `x + px*sL`, `x + px*sR` (1747-1750
vs 1165-1174); field bounds at `x + px*0.5*(z - c)` (1756-1763 vs 1576-1578 — the two
association orders differ only by an exact scaling by 0.5, and min/max are exact, so identical
bounds reach the shared `_pic_interaction_grids`, whose `width/(nx-1)` spacing (tx after the
`3*tx` widening, pic_cpu.jl:1937-1940) is what every launcher in the region passes as
`T(width)/T(nx-1)`, 1970-1972, 2235, 2246). Node meshes: source box = union of node drifts `b`
and `min(b+1, nb)`, field box = union of adjacent slices `b-1, b`, `±Inf` empty → skip, NaN →
error (2044-2072 vs 1554-1626); the three-plane rule `F_L` on `G_s`, `F_R` on `G_{s+1}`,
`F_Z` = node `s+1` at drift `sR` on **`G_s`** (2178-2186 vs 1743-1755) matches
`docs/theory/node_interaction_grid.md` section 4's table and the six-plane wavefront layout
(`pp(o+1), pv(Ex,o+1), pv(Ey,o+1), pv(Ex,o+2), pv(Ey,o+2), pp(o+3)` at 1655-1667 against the
`_cuda_pic_launch_kick_node!` argument order `phiL, ExL, EyL, ExR, EyR, phiZ`, 1955-1957, and the
documented layout at 2858-2865). Dropped-charge accounting mirrors the CPU count for count:
each drift plane against the mesh it deposits into (`(sL, sL)` on `gL`, `(sR, sR)` on `gR`),
the field side against `gL.field_grid` after the `0.5*(z - c)` drift (2173-2175 and 1612-1623
vs 1730-1741), with the kernels implementing the same one-count-per-particle predicate
(4254-4266 vs 1871-1884); the device counter is zeroed per collide (206, 381), read once after
the closing `synchronize` (2156-2159), and routed to the CPU's own warning. Measured: both node
routes at 3 slices / 4000 particles reported `dropped = 8` in the probe log — the same count on
the sequential and the wavefront-indexed route. Direction/kick bookkeeping: `kbb2` is applied
to beam-2 particles with beam-1 planes (`phi12`) and `kbb1` to beam 1 with `phi21` on every
route (263-273, 997-1004, 1082-1101, 1208-1229, 1514-1531, 1655-1667), consistent with the
`_cuda_pic_launch_kick_pair_indexed!` docstring's pairing (2354-2370) and with
`host_seg_kbb[s1] = slices2.weight[j]*kbb1` for beam-1 segments in the fused Gaussian driver
(1363, 1374). Pre-collision reads: the plain-sequential paths copy both slices and kick the
copies (245-246, 282-283, 480-481, 502-503); the async and batched-FFT paths fetch the
luminosity task and synchronize `luminosity_stream` before the in-place kicks (986-993,
1070-1077); the wavefront paths compute luminosity before the field solve and kicks (1159-1161,
1474-1478, 1631-1634); the node routes prebuild every mesh at turn start before any pair
(199-205, 330-336) as the CPU does. Per-pair luminosity records (the 2026-08-05_b U1-1 gap)
are pushed on every route: 279, 498, 991, 1075 in the region, and 3812, 3901, 3992 inside the
three wavefront luminosity callees; the sink stamps `turn` from the scoped context that all
three `collide!` entry points now install (121-124, 134-136; U1-4 repaired).

Workspace and cache keys (class 7): `_cuda_pic_workspace!` keys on label, device, `T`, both
grids, deposit methods, Green type, `longitudinal_kick`, `batch_mode`, `green_cache`, the two
slice-pair cache parameters and `interaction_grid` (748-778) — a superset of the CPU pool key
`(label, T, grid)` (pic_cpu.jl:620) and of the CPU Green-cache key (630-640); the fields it
omits (`slice_interpolation`, the `cuda_*` flags) do not change any buffer shape, and the
wavefront entries it owns are keyed and regrown internally by capacity and by
`luminosity_threads` (2743-2758, 2826-2842). `_cuda_pic_green_cache`/`_cuda_pic_green_cache!`
return `nothing` on CUDA (784-791), so every `green_cache` parameter threaded through the
region is always `nothing` and the slice-pair cache lives in the workspace; the branches
read correctly under that invariant (207-208, 337-338, 1133, 1163-1164, 1480-1481).

Gates: `_require_cuda_pic_options` (pic_cpu.jl:880-927) rejects every flag combination under
which the region's dispatch would silently drop `:quadratic` (the non-batched async route,
238-243 and 472-478, carries two planes) or `:node` (every non-indexed wavefront sub-route and
the sequential batched-FFT sub-route); the one runtime downgrade the static gate cannot see
(`pic_timing_detail` clearing `use_async`) lands on routes that still honour `:quadratic`
(`_cuda_pic_interaction!`, 1715-1730) and throws for `:node` (344-359). All callees the region
dispatches to exist (`_cuda_pic_interaction_wavefront_quadratic_indexed_batched_fft!` 3596,
`..._quadratic_batched_fft!`, `_cuda_pic_solve_pair_fields_batched_fft!` 2643,
`_cuda_pic_solve_wavefront_fields_{batched,indexed_batched,node_indexed}!` 2945/3069/2870,
`_cuda_pic_slice_pair_cached_prep!` 2428, `_cuda_pic_kick_node_kernel!` 5245).

Previously filed and now repaired in this region (verified present): U1-1 per-pair sink on
every route; U1-2 `interaction_grid` in the workspace key (777); U1-3 the bounds stage reads
`_cuda_pic_threads(:field)` (1819) — which is what exposes the new U1-1 above; U1-4 the
`ctx::TrackingContext` entry installs the timing context (107-125); U1-5 the device
`dropped` counter (566, 2128-2160); U1-6 `_cuda_pic_extract_slice` lost its dead parameter
(849) and the five-plane gather kernel is gone (4054-4059). The hard-wired switches
(`_cuda_pic_wavefront_green_fft_enabled() = true`, `_cuda_pic_async_luminosity_enabled() =
false`, `_cuda_pic_batched_luminosity_enabled() = false`, `_cuda_pic_stack_cached_green_enabled()
= true`, 608-617) are unchanged since the 2026-08-04 audit named them "dead but correct"; the
branches behind them (1149-1158, 3801-3802) remain unexercised by any test, which is noted and
not re-filed.

Receipts under an `ExecutionAudit` (measured, probe Part 2): one collision of 3×3 slices emits
112-271 `:cuda_pic_launch` receipts (one per `_cuda_pic_threads` read, i.e. per launch and per
workspace sizing read), appended to an unbounded vector (Policies.jl:188-199). Only the
contracts install an audit (`with_execution_audit` callers: Contracts.jl and the two analysis
contracts, none in `execute!`), so growth is bounded by contract length; not filed. Seam
note for the auditor: the `:luminosity => [1024]` receipt in the FAILED run was emitted by
`_cuda_pic_wavefront_workspace!` (2742, out of region) sizing a buffer, not by a launch — a
receipt named `cuda_pic_launch` that records a read rather than a launch.

## Unchecked

- Lines 2201-6492 are other units' regions; functions there were read only to validate the
  region's calls (listed under Provenance) and nothing is reported against them. In
  particular the deposit, Green, spectral and interpolation kernels that hypothesis 1 names
  ("deposit, interpolation, solve bookkeeping") are not in lines 1-2200; the region's share of
  that hypothesis is the host-side bounds, grid, plane and drift bookkeeping checked above.
- `_cuda_pic_slice_bounds_multi` (1992-2005) materializes a `K × n` broadcast per source slice
  per direction per turn (`K = nslices+1`); at the recorded production point (15 slices,
  2.56M/1.024M particles) that is of order 40 MB per slice and ~650 MB of pool churn per
  direction per turn. The docstring records the measured reason (K reductions → 4); the
  production-scale cost was not measured here (shared GPU, and a cost question, not a
  correctness one), as the previous audit also left it.
- The bare `collide!(solver, b1, b2, CUDABackend)` entry (94-105) builds a fresh
  `_CUDAPICWorkspace` — five `CuStream`s, one `CuEvent`, the padded charge and batch buffers —
  per call and relies on GC finalizers to release them. Not measured; the path is documented as
  non-production and warns when a launch config is attached, so this is noted, not filed.
- `docs/theory/pic_free_space_kernels.md` was not read: it derives the Green/deposit kernels,
  none of which are in the region.
- `_cuda_gaussian_collide_wavefront!` (1238-1437) was read line by line and its sizing and
  segment bookkeeping checked (see Clean), but its arithmetic twin (`gaussian.jl`) was not
  compared term by term here; it is a Gaussian route that happens to live in this file and the
  previous audit's item 16 covered the sizing. Measured only that it runs at 1024 threads with
  the fused kick capped to 384.
