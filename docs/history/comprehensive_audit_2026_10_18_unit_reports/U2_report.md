# U2: pic_cuda.jl, second third

Reading unit U2 of the 2026-10-18 comprehensive audit. Tree: `/cfs/ad/dxu/Library/Julia/Octopus`
at commit 24e8683, read-only. No repository file was modified; no git command was run in the
repository. Probe scripts and logs:
`/cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U2/`.

## Region

`src/tasks/strongstrong/pic_cuda.jl` lines 2201-4400 (2200 lines). Contents, by function:
kick launchers (`_cuda_pic_launch_kick_quadratic!` tail, `_cuda_pic_launch_kick!`,
`_cuda_pic_launch_kick_node_indexed!`, `_cuda_pic_launch_kick_pair_indexed!`,
`_cuda_pic_launch_kick_quadratic_indexed!`) and the node/quadratic indexed kick kernels; the
slice-pair Green cache (`_cuda_pic_slice_pair_cached_prep!` and its usable/covers/expand helpers);
the bounds value helpers; the per-pair and batched field solves; the wavefront workspaces
(`:standard` and `:node` entries); the four batched wavefront field solves (slice-pair 4-plane,
indexed 4-plane, node 6-plane, quadratic 6-plane gathered and indexed); the wavefront Green stack
builders; the deposit launch wrappers; the two quadratic wavefront interaction routes; the Green FFT
builders; the three wavefront luminosity functions and `_cuda_pic_luminosity`; the gather/scatter
and mask-index kernels; the Green kernels and kernel integral; the count-outside kernels; and the
deposit kernels up to the first half of `_cuda_pic_deposit_drifted_plane_kernel!` (the region ends
at line 4400 inside that kernel's TSC branch).

## Provenance

READ line by line: `pic_cuda.jl` 2150-4400 (the region plus the 50 lines above it, so the
count-kernel host wrappers and `_cuda_pic_interaction_node!` that feed the region were not read
half-way). Cross-read for contract verification only (not line-audited): `pic_cuda.jl` 1-130
(header claim, `_cuda_launch_capped!`, `collide!`), 186-306 (sequential route), 535-800 (structs,
flags, pair-luminosity helper, workspace key, `_cuda_pic_green_cache`), 826-1000 (slice extract,
async pair route), 1439-1460, 1500-1530, 1690-1800, 1801-1960 (indexed prepare, non-finite
chokepoint, `_cuda_pic_finish_interaction_indexed`), 4489-4580, 4672-4950, 5032-5110, 5182-5290,
5338-5437 (weights, spectral/field/kick kernels, interpolators); `pic_cpu.jl` 574-600, 870-950,
1160-1420, 1698-1925, 1926-2170, 2475-2580, 2744-2800, 2970-3061 (every CPU twin of a region
function); `interface.jl` 91-340, 1240-1335, 1545-1680; `Contracts.jl` 1095-1210, 1405-1475,
1670-1682; `gaussian_pic_cuda.jl` 415-435, 705-725, 1068-1090; the previous audit's
`docs/history/comprehensive_audit_2026_08_05_b_unit_reports/U2_report.md`;
`docs/history/todo_ledger_archive.md` item 14 (2591-2615).

EXECUTED (RTX 4500 Ada, `CUDA.functional() == true`, Julia `--project=<repo> --threads=4`):

- `probe_zero_blocks.jl`: a `CUDA.@cuda blocks=0` launch throws
  `Grid dimensions CuDim3(0x0,...) are not positive` (loud, not silent).
- `probe_routes.jl` (log `probe_routes.log`): 24 solver configurations, N=4000/beam, 5 slices,
  grid 32x32, 2 turns, through `StrongStrongTask`/`execute!` on both backends with the per-pair
  luminosity sink installed. For 23 routes: sink CPU=50 GPU=50, keys match, per-pair relative
  difference <= 5.0e-14, sum of the GPU trace vs the recorded series <= 4.2e-16, luminosity
  <= 2.6e-15, coordinates <= 2.3e-13 of the beam rms. The 24th (`green_type=:standard`):
  coordinates 7.8e-3, luminosity 3.8e-6, per-pair 1.8e-4 -- LEAD U2-1. The `:node` +
  `cuda_indexed_wavefront=false` row throws the documented `ArgumentError` guard.
- `probe_standard.jl` (`probe_standard.log`): the `:standard` divergence is present on every CUDA
  sub-route (indexed, gathered, async pair, sequential: 7.8e-3 to 1.0e-2) and absent with
  `green_cache=:none` (5.3e-14, 5.8e-14, 1.1e-13); present with one slice per beam (1.4e-3) and at
  grid 64 (7.8e-3); `:integrated` and `:lattice` controls 9.8e-14 and 5.6e-14.
- `probe_green.jl`: the region's Green kernels against the CPU `_pic_green` table on identical
  parameters: Float64 `:standard` max 1.8e-15 abs (2.2e-16 rel), Float64 `:integrated` 3.7e-12
  abs (4.8e-13 rel), `_cuda_pic_green_stack_kernel!` bit-identical to the single-plane kernel;
  Float32 `:integrated` 3.1e-4 rel (LEAD U2-5), Float32 `:standard` 1.2e-7 rel.
- `probe_align.jl` part (1): `_pic_realign_expanded_grids(:standard, ...)` on grids expanded by
  1.25 from a `(k + 1/2)`-cell separation: for k = 2, 7, 12 the decision variable `t` is
  0, +8.9e-16 or +4.4e-16 and a one-ulp change of the field origin flips the applied shift from
  -0.25/+0.25 to +0.25/-0.25 cells (post-shift separation 2.5 vs 1.5 cells, 5.5 vs 6.5); for every
  other k, `t` = +-0.1 or +-0.2 and the ulp change does nothing.
- `probe_align2.jl` part (2): the device evaluates `x + px*s` as a fused multiply-add: 18373 of
  100000 values differ from the host's two-rounding form, 0 differ from `fma(px, s, x)`;
  `_cuda_pic_source_bounds_value` 17315/100000. Part (3): CUDA run-to-run in one process, same
  beams, `green_cache=:slice_pair`: `:integrated` 1.9e-13, `:lattice` 9.4e-15, `:standard`
  7.2e-3 of the rms (luminosity 7.6e-6).
- `probe_dropped.jl` (`probe_dropped.log`): (A) the region's count-outside kernels against the
  CPU helpers on 20000 random particles with NaN/Inf entries, whole-slice and index-list modes,
  Float64 and Float32: 8/8 exact matches (counts 909/470/319/178 and 918/474/324/160). (B) charge
  conservation of the region's deposit kernels on an `_pic_interaction_grids` mesh, Float64:
  relative deficit 0.0 for CIC and TSC on the plane, pair-L, pair-R and indexed-M kernels;
  Float32: 5e-9 to 6e-8 (summation rounding); luminosity mesh (0.05-cell margin, (nx+1)x(ny+1)
  nodes): deficit -1.8e-16 CIC, 0.0 TSC, with 0.12/0.10 charge units landing in row nx+1 / column
  ny+1 under TSC and 0.0 under CIC. (C) end-to-end dropped-charge warnings, 2 turns: `:slice_pair`
  none on either backend (npart x1 and x30); `:node` indexed wavefront CPU `[3]` GPU `[3]` at x1,
  CPU `[1336, 3225]` GPU `[1336, 3225]` at x30; `:node` sequential GPU `[1336, 3225]` = CPU.

## Leads

### LEAD U2-1 [Major, confidence high] src/tasks/strongstrong/pic_cuda.jl:2453
Claim: with `green_type=:standard` and the default `green_cache=:slice_pair`, the CUDA PIC
collision diverges from the CPU by ~1e-2 of the beam rms and is not reproducible run to run on
CUDA (7.2e-3), while every other option combination agrees to <= 2.3e-13 and `green_cache=:none`
restores `:standard` agreement to 5e-14.
Mechanism: `_cuda_pic_slice_pair_cached_prep!` (and its CPU twin `_pic_slice_pair_green!`) expand
the pair's grids by `1 + slice_pair_green_growth` and call the shared
`_pic_realign_expanded_grids`, whose `:standard` branch (`_pic_align_grid_origins`,
pic_cpu.jl:2133-2134) decides the half-cell shift by the sign test `t > 0 ? -0.25 : 0.25`. Its own
docstring (pic_cpu.jl:2093-2095) records that the expansion maps a `k + 1/2` separation to
`0.8k + 0.4`, an integer whenever `k == 2 (mod 5)` -- and exactly there `t` is zero in exact
arithmetic, so the sign is decided by rounding noise (`probe_align.jl`: k = 2, 7, 12 give
t in {0, 4e-16, 9e-16} and a one-ulp change of an origin flips the shift, i.e. moves the deposit
mesh by half a cell). The two backends feed that test different last bits: the device contracts
`x + px*s` into an FMA in every bounds reduction (`_cuda_pic_source_bounds_value`,
pic_cuda.jl:2519-2525, and the `mapreduce` closures in `_cuda_pic_prepare_interaction`), 17-18% of
values differing from the host's two-rounding form, and the atomic depositions make later pairs'
coordinates differ at 1e-16 between any two CUDA runs. A half-cell mesh displacement is an
O(h^2)-level discretization change, hence the 1e-2 coordinate and 1e-5 luminosity divergences. For
colliding beams with a common centroid, |k| is a few cells, so a sizeable fraction of pairs sits on
the boundary. Consequences: `StrongStrongPICBackendConsistencyContract` has no `green_type` field
and the suite never runs `:standard` on CUDA (`grep -n 'green_type *= *:standard' test/runtests.jl`
is empty), so the divergence was unmeasured; the file header (pic_cuda.jl:1-36) states the CUDA
run-to-run spread is "at rounding level, so no physics result is affected", which is false for this
configuration (class 8/10 amplification, class 14 claim). Seam: the discontinuity lives in
`pic_cpu.jl` (`_pic_align_grid_origins`) and the FMA in the bounds kernels outside this region;
the auditor owns the fix (a rounding-robust decision, e.g. deciding the shift from the integer
pre-expansion separation rather than from `t`'s sign, or snapping `t`).
Repro: `cd /cfs/ad/dxu/Library/Julia/Octopus && julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U2/probe_standard.jl`
-- expected "standard: defaults" coord_rel ~1e-2 and "standard: green_cache=:none" ~5e-14;
`probe_align.jl` -- for k = 2, 7, 12 the `f0+1ulp`/`f0-1ulp` rows show opposite shifts;
`probe_align2.jl` -- part (3) `standard coord_rel run1-run2` ~7e-3 against `integrated` ~2e-13.

### LEAD U2-2 [Minor, confidence high] src/tasks/strongstrong/pic_cuda.jl:2891
Claim: `_cuda_pic_solve_wavefront_fields_node_indexed!` still deposits, Green-multiplies, inverse
FFTs and differentiates the two longitudinal `Z` planes of every slice pair when
`longitudinal_kick=false`, which the kick never reads; this is the previous audit's U2-2, archived
as `docs/history/todo_ledger_archive.md` item 14 with its fix sketched, and it is unchanged at
24e8683 (known; reported so the auditor can decide whether the archive records a deferral).
Mechanism: the `specs` tuple at 2891-2898 lists planes `offset+3` and `offset+6` unconditionally
and the function contains no reference to `solver.longitudinal_kick`; `_cuda_pic_apply_indexed_node_kick!`
reads `phiZ` only inside `if longitudinal` (2294). The sequential twin `_cuda_pic_interaction_node!`
(2183-2186) and the CPU `_pic_interaction_node!` (pic_cpu.jl:1749-1755) skip the third solve.
Correctness is unaffected (measured parity `:node` + `longitudinal_kick=false`: 1.4e-13).
Repro: `grep -n 'longitudinal' src/tasks/strongstrong/pic_cuda.jl | awk -F: '$1>2870 && $1<2944'`
prints nothing; the archived timing table (item 14) is the cost.

### LEAD U2-3 [Minor, confidence high] src/tasks/strongstrong/pic_cuda.jl:2576
Claim: the region carries unreachable host code that nothing can verify, the class the file's own
U1-6 note at 4054-4059 removes on sight: `_cuda_pic_solve_field_with_green_fft` (2576-2607, no
caller anywhere in `src/`, `test/`, `validation/`, `profiling/`, `examples/`),
`_cuda_pic_bounds_pair_combine` (2539-2544, no caller), `_cuda_pic_apply_green_plane!`
(3268-3274) together with the per-plane `else` branches at 3045-3054 and 3161-3168 (dead because
`_cuda_pic_stack_cached_green_enabled()` is the constant `true`, 617), and
`_cuda_pic_wavefront_luminosity_batched` (3819-3907, dead because
`_cuda_pic_batched_luminosity_enabled()` is the constant `false`, 612).
Mechanism: a dead twin drifts without a tripwire; `_cuda_pic_wavefront_luminosity_batched` in
particular returns a total from one reduction (`_cuda_pic_luminosity_wavefront_kernel!`, a single
atomic) while its trace comes from another (the partials kernel), a divergence nothing exercises;
and `_cuda_pic_solve_field_with_green_fft` is a non-drifted copy of the drifted solve beside it.
Repro: `for f in _cuda_pic_solve_field_with_green_fft _cuda_pic_bounds_pair_combine; do grep -rn "$f" src test validation profiling examples | grep -v 'function ' | wc -l; done`
prints 0 and 0; `grep -n '_cuda_pic_stack_cached_green_enabled() = \|_cuda_pic_batched_luminosity_enabled() = ' src/tasks/strongstrong/pic_cuda.jl`
shows the constants.

### LEAD U2-4 [Minor, confidence med] src/tasks/strongstrong/pic_cuda.jl:4020
Claim: the luminosity overlap mesh arithmetic (`_pic_resolve_transverse_extent`, `tx = width/(nx-1.1)`,
`+0.1 tx`, `-0.05 tx`, `hx = width/(nx-1)`) is hand-copied three times on the CUDA side
(`_cuda_pic_luminosity` 4020-4030, `_cuda_pic_wavefront_luminosity_indexed` 3953-3963,
`_cuda_pic_wavefront_luminosity_batched` 3854-3864) instead of calling `_pic_luminosity_mesh`,
the one function the CPU introduced (pic_cpu.jl:2997-3017) precisely "so the two cannot drift
apart by a rounding".
Mechanism: hand-copied knowledge with no coverage tripwire (defect class 2); today the three copies
agree with the CPU helper expression for expression (measured luminosity parity <= 2.6e-15 on
every route, including `luminosity_grid=(129,129)` and TSC), so this is a maintenance exposure,
not a present defect. Out of hypothesis.
Repro: `grep -n '_pic_luminosity_mesh' src/tasks/strongstrong/pic_cuda.jl` prints nothing;
`grep -n 'nx - 1.1' src/tasks/strongstrong/pic_cuda.jl` prints three sites.

### LEAD U2-5 [Minor, confidence med] src/tasks/strongstrong/pic_cuda.jl:4147
Claim: in Float32 the `:integrated` Green kernel built by `_cuda_pic_green_kernel!` differs from
the CPU table by up to 3.1e-4 relative (2.5e-3 absolute on values ~8), against 4.8e-13 in Float64
and 1.2e-7 for Float32 `:standard`, so a Float32 CPU/CUDA PIC comparison with the default kernel
cannot agree better than ~1e-4 even before any deposition noise.
Mechanism: the four-corner difference `I(x+h/2,y+h/2) + I(x-h/2,y-h/2) - I(x+h/2,y-h/2) - I(x-h/2,y+h/2)`
cancels three to four digits of its ~O(1) terms (class 12), so the 1-2 ulp differences between
libdevice and Julia `log`/`atan` in Float32 are amplified by the cancellation ratio; both backends
compute the same expression, the difference is the transcendental implementations. No Float32
CPU/CUDA PIC pin exists to catch it. Out of hypothesis; kernel lives in the region, the CPU twin
`_pic_green_columns!` is identical in form.
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U2/probe_green.jl`
-- row `green T=Float32 integrated` max|rel| ~3e-4; row `green T=Float64 integrated` ~5e-13.

## Clean

1. **Per-pair luminosity trace (hypothesis 3).** Every CUDA route that resolves a per-pair value
   pushes through `_cuda_pic_push_pair_luminosity!` (region sites 3812, 3901, 3992; callers at
   279, 498, 991, 1075 outside), the helper warns when a route supplies no `(i, j)` key, and the
   contract decides "trace expected" from the CPU trace (Contracts.jl:1170). Measured
   (`probe_routes.jl`, 24 configurations, 25 pairs x 2 turns): GPU sink length 50 = CPU on all
   routes that run, keys `(turn, i, j)` identical, per-pair values within 5.0e-14 (6.5e-15 on the
   default), and the GPU trace's per-turn sum reproduces the recorded luminosity series to
   <= 4.2e-16. The 2026-08-05_b U1-1 gap is closed on every route, including `pic_timing_detail`-free
   sequential, async-pair, batched-pair, gathered and indexed wavefront, node and quadratic.

2. **Dropped-charge tripwire (hypothesis 2).** Reachability: on CUDA `grid_extent` is forced to
   `:extrema` and `interaction_grid` to `:slice_pair`/`:node` (`_require_cuda_pic_options`), so the
   CPU counting gate `ge !== :extrema || interaction_grid !== :slice_pair` is live exactly for
   `:node`; both CUDA `:node` routes count (sequential 2173-2175 via `dropped=workspace.dropped`,
   indexed wavefront 1612-1623), and both report through `_cuda_pic_report_dropped` ->
   `_pic_report_dropped_count`, the CPU's message. Measured end to end: identical warnings on both
   backends, `[3]` per collide at nominal charge and `[1336, 3225]` at 30x, for both `:node` routes;
   none on `:slice_pair` at either charge. Kernel twins: the region's
   `_cuda_pic_count_outside_drifted_kernel!`/`_zdrift_kernel!` match
   `_pic_count_outside_box_drifted`/`_pic_count_outside_box` exactly on 20000 random particles with
   NaN/Inf entries in both index modes and both precisions (8/8). Deposits: zero relative deficit in
   Float64 for CIC and TSC on every region deposit kernel on a production-margin mesh, and on the
   0.05-cell-margin luminosity mesh; the `(nx+1, ny+1)` extent captures TSC's top row/column
   (0.12/0.10 charge units of 20000) that CIC never reaches (0.0), consistent with U5-8. The
   `:slice_pair` "covered by construction" argument holds on every CUDA route: bounds are taken at
   the same drifts the deposits and kicks use (`_cuda_pic_source_bounds_value`,
   `_cuda_pic_field_bounds_value`, the fused bounds kernels), the quadratic M plane is affine in
   `s`, and every cached-mesh reuse passes `_cuda_pic_grid_covers_bounds` with the 1.5-cell margin
   on the pair's own bounds (2477-2478).

3. **Option consumers inside the region (hypothesis 1).** `longitudinal_kick` selects the kernel in
   `_cuda_pic_launch_kick!` (2228) and `_cuda_pic_launch_kick_pair_indexed!` (2388) and is passed as
   a kernel argument by the quadratic, node-indexed and quadratic-indexed launchers (2214, 2349,
   3753); `deposit_method` -> `method_code` at every deposit and interpolation site;
   `luminosity_deposit_method` via `_pic_luminosity_deposit_method` at 3837, 3924, 4037;
   `green_type` -> `green_code`/lattice host build at 3222, 3240, 3768, 3783;
   `field_derivative` via `_pic_fourth_order` at every field-kernel launch; `slice_pair_green_min_ratio`
   and `slice_pair_green_growth` at 2447-2448 and 2474; `grid`, `luminosity_grid`,
   `min_transverse_extent` via the shared helpers. Measured: `longitudinal_kick=false`,
   `deposit_method=:TSC`, `luminosity_deposit_method=:TSC`, `green_type=:lattice`,
   `field_derivative=:fourth`, `luminosity_grid=(129,129)`, `green_cache=:none`,
   `slice_interpolation=:quadratic` (three sub-routes), `interaction_grid=:node` (two sub-routes),
   `batch_mode=:sequential`, `cuda_async=false`, `cuda_batch_fft=false`, `cuda_wavefront_fft=false`,
   `cuda_indexed_wavefront=false` each agree with the CPU run of the same options to <= 2.3e-13
   (coordinates, of the rms) and <= 2.6e-15 (luminosity), so no option in the region is accepted
   and ignored. `interaction_grid=:node` with a non-indexed wavefront flag set throws the F11 guard.

4. **Plane layouts, Green mappings and kick pairings.** Checked index by index against the kick call
   sites: slice-pair 4-plane (2966-2993 and 3091-3112: `+1,+2` <- beam 1 at sL,sR on prep12 mesh,
   `+3,+4` <- beam 2 on prep21; stack copies two Greens per pair, 3184-3193; multiply kernel maps
   plane `p` to Green `p ÷ 2 + 1`); node 6-plane (2891-2898, Green per plane 2917-2921, `hx/hy`
   from the deposited mesh 2904-2905; kick 1655-1662 pairs `o+1..3` with `rep2`/`gL1,gR1` and
   `o+4..6` with `rep1`); quadratic 6-plane gathered (3399-3411) and indexed (3461-3480), Green
   duplicated into three slots (3364-3375), kicks 3576-3587 and 3664-3673 pair `o+1..3` with
   `rep2`/`prep12.field_grid` and `o+4..6` with `rep1`/`prep21.field_grid`, the convention the
   2354-2371 docstring states. The `:node` and `:quadratic` 6-plane solves share the
   `wavefront_cache[:node]` entry but both overwrite every plane they use (`fill!` at 2879/3386/3448,
   Green stack and `hx/hy` written per plane) so no stale plane can be read.

5. **Workspace sizing.** `overlap_length = cld(prod(lgrid .+ 1), threads) * npairs` (2764) equals
   the `blocks_per_pair * npairs` the overlap kernel is launched with (3979-3980), and the kernel
   writes every block's partial (4802-4804), so `sum(wf.luminosity_overlap_partials)` reads exactly
   what this call wrote. `luminosity_q1/q2` are `(lnx+1, lny+1, npairs)` against `Int32(nx+1),
   Int32(ny+1)` deposits (3965-3972). The power-of-two requirement of the shared-memory tree
   reduction (4794-4801) is enforced at `CUDAPICLaunchConfig` construction and resolution
   (interface.jl:141, 223); the bare-`collide!` fallback is 256. Capacity growth synchronises
   before dropping the old buffers (2749, 2829); `bounds_host` is a full-capacity host array read
   only in the first `2*npairs` columns a contiguous linear `copyto!` fills (1871).

6. **Slice-pair Green cache bookkeeping vs the CPU.** `_cuda_pic_slice_pair_cached_prep!`
   2432-2470 against `_pic_slice_pair_green!` pic_cpu.jl:1984-2028: same hit test, same
   `hits/misses/rebuilds`, `entry.uses`, `entry.rebuilds` carry-over, same expand -> realign -> build
   sequence (the realignment's ill-conditioning is U2-1, a property of the shared helper, not of
   this transcription). `_cuda_pic_grid_size_usable`, `_cuda_pic_grid_covers_bounds`,
   `_cuda_pic_expand_grid_by` are expression-equivalent to their CPU twins (the CPU's
   `factor <= 1` early return is inert for the validated `growth >= 0`).

7. **Kick formulas vs the CPU.** `_cuda_pic_apply_indexed_node_kick!` (2264-2305) against
   `_pic_interaction_node!` (pic_cpu.jl:1707-1781): same drift `0.5(z - c)`, same clamp of `zL`,
   transverse kicks on the two nodes' own meshes (`gL.field_grid`, `gR.field_grid`), longitudinal
   `Kz` from `phiL - phiZ` on the left mesh with `pz += 2 kbb Kz hzi`, the `-0.25(px^2+py^2)` before
   and `+0.25(px'^2+py'^2)` after; `_cuda_pic_interpolate_kick` returns `Kz = sum w (phiL - phiR)`
   independently of `zL/zR` (5406-5418). The R-mesh transverse call passes `phiL` in both `phi`
   slots (2286), which is harmless because `_cuda_pic_interpolate_field` never reads `phi`
   (5182-5233) -- the latent trap the previous two passes noted, still only a trap. Quadratic
   indexed kick (3681-3714) mirrors `_cuda_pic_kick_quadratic_kernel!` (5338-5378) statement for
   statement.

8. **Green kernels vs the CPU.** `_cuda_pic_green_kernel!`/`_cuda_pic_green_stack_kernel!`
   (4127-4219) against `_pic_green_columns!` (pic_cpu.jl:2770-2800): same `hxihyi = -0.5/(hx hy)`,
   same four-corner integrated form, same `-0.5 log(r2)` with the integrated fallback at `r2 == 0`,
   same `_cuda_pic_atan_ratio`/`_cuda_pic_kernel_integral` expressions; measured Float64 agreement
   2.2e-16 (`:standard`) and 4.8e-13 (`:integrated`, libdevice vs Julia transcendental ulps),
   stack kernel bit-identical to the single-plane kernel. `:lattice` is built on the host from the
   CPU table (3222-3238, 3768-3780), bit-identical by construction (measured end-to-end parity
   2.2e-14, the tightest of all kernels).

9. **Deposit and weight twins.** `_cuda_pic_cic_weights`/`_cuda_pic_tsc_weights` (4672-4716) and
   `_pic_cic_weights`/`_pic_tsc_weights` (pic_cpu.jl:2475-2545): same out-of-range contract
   `!(0 <= u <= n-1)` -> zero weights at index 1, same clamped-base CIC fraction (U5-7), same TSC
   closed form and `[1, n-2]` clamp; the count kernels' box `[x0, x0+width]` is the same set as
   `u in [0, n-1]` up to rounding.

10. **Zero-length launches.** `_cuda_pic_launch_kick!`, `_cuda_pic_launch_kick_quadratic!`,
    `_cuda_pic_deposit_drifted_plane!` and `_cuda_pic_luminosity` compute `blocks = cld(n, threads)`
    without a guard, and a zero-block launch throws (measured). Unreachable from this file's
    routes: `_cuda_pic_extract_slice` returns `nothing` for an empty slice and the sequential loop
    `continue`s (851, 222), the gathered wavefronts filter `slice !== nothing`, the indexed ones
    filter `length(idx) > 0` (1446, 3602), and the two indexed launchers guard themselves (2333,
    3739). Loud if ever reached, never silent.

11. **Non-finite chokepoint on the indexed route.** `_cuda_pic_prepare_interaction_wavefront_indexed!`
    checks the host copy of every bounds row (1876-1893) and raises `_nonfinite_coordinate_error`
    with the pair context, so a NaN coordinate cannot deposit nowhere silently on the production
    route (the gathered route checks at 1770-1775).

## Unchecked

- Lines outside 2201-4400 were cross-read only where a region call required it; the slicing
  kernels that decide `:equal_area` membership (hypothesis 2's second clause) are not in this
  region and were not read -- that clause is U1/U3's line-by-line job.
- `_cuda_pic_wavefront_luminosity_batched` (3819-3907) and the per-plane spectral branch
  (3045-3054, 3161-3168) were read but not executed; both are unreachable (LEAD U2-3).
- The `gpic_subtract` branches of the two 4-plane wavefront solves (3002-3019, 3119-3136) launch
  kernels defined in `gaussian_pic_cuda.jl`; the kernels and the GaussianPIC routes that pass
  `green12 === nothing` (the on-device wavefront Green build, 3023-3025, 3140-3142, 3195-3253)
  were not exercised here beyond reading; `probe_routes.jl` runs plain PIC only.
- Float32 end-to-end CPU/CUDA collisions were not run (LEAD U2-5 is a kernel-level measurement).
- The `pic_timing_detail=true` diagnostic route was not run; its pair-trace behaviour follows from
  the same helper every route calls, but that is an argument, not a measurement.
- `_cuda_pic_bounds_block_reduce` and the fused bounds kernels (4521-4660) that feed
  `_cuda_pic_finish_interaction_indexed` are outside the region and were read only to establish the
  FMA observation in U2-1.
