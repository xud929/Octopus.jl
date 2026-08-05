# U8 Audit Report — GaussianPICPoissonSolver CPU/CUDA twins (commit 13c2733)

## Coverage

Read in full, line by line:
- `src/tasks/strongstrong/gaussian_pic.jl` lines 1–869 (entire file).
- `src/tasks/strongstrong/gaussian_pic_cuda.jl` lines 1–1232 (entire file).
- `docs/theory/gaussian_subtracted_pic_solver.md` lines 1–790 (entire file).

Targeted supporting reads (seam verification): `pic_cpu.jl` 154–160, 370–660, 888–1120, 1273–1475, 1719+; `pic_cuda.jl` 404–460, 600, 1452–1500, 1563–1705, 2116–2175, 2600–2800, 3449, 3946–3970, 5510–5720; `interface.jl` 150–290, 1298, 1318–1440, 2146; `src/elements/strong_beam.jl` 560–710 (`_cp_covariance_kick`, `_transport_transverse_moments`, `_gaussian_beambeam_kick_response`).

Probes (all CPU, each < 60 s, in `../U8/`): `probe1_profiles.jl`, `probe2_coupled.jl`, `probe3_anchors.jl`, `probe4_modes.jl`, `probe5_sg_guard.jl`.

## Leads

### U8-1 — docs/theory/gaussian_subtracted_pic_solver.md:595-596 — theory note says the coupled branch is "CPU-only; the CUDA path raises", contradicting the shipped CUDA indexed-wavefront implementation — LOW (doc drift)

Section 7.5 ends: "The branch is CPU-only; the CUDA path raises rather than
silently running the uncoupled subtraction." In the code the coupled (rotated)
subtraction IS implemented on the default CUDA route
(`batch_mode=:wavefront, cuda_indexed_wavefront=true`):
- coupled batched moments + profiles: `gaussian_pic_cuda.jl:281-378`;
- device coupled subtraction: `_cuda_gpic_subtract_coupled_kernel!`
  `gaussian_pic_cuda.jl:950-971`, dispatched at `pic_cuda.jl:2698-2705`;
- coupled device kick: `_cuda_gpic_gtuple` / `_cuda_cp_covariance_kick`
  `gaussian_pic_cuda.jl:725-741, 812-821, 870-878`;
- only the two reference routes raise (`_cuda_gpic_require_uncoupled`,
  `gaussian_pic_cuda.jl:41-50`, called at 505 and 978).

The solver docstring (`gaussian_pic.jl:55-63`) and the constructor comment
(`gaussian_pic.jl:103-108`, citing audit part 7 G3) state the correct behavior,
so the theory note is the only stale statement. A user following the theory note
would wrongly conclude `coupling_tol` cannot be used on CUDA at all.
Repro: read the three locations; no execution needed.

## Sound — invariants verified and how

1. **erf deposition integrals exact (theory §5).** `probe1_profiles.jl`:
   `_gpic_gaussian_profile!` vs Simpson quadrature of G·W at interior and edge
   nodes — worst |analytic−quad| 1.24e-15 (CIC), 3.86e-14 (TSC) against profile
   scale 7.5e-2. TSC σ→0 at a node gives exactly (0, 1/8, 3/4, 1/8, 0); CIC gives
   (…, 1, …). Box mass: 1−Σg = 1.16e-9 on a ±6σ box vs erfc(6/√2)=1.97e-9 (same
   order; the tent smoothing exchanges edge mass, as expected).

2. **Coupled conditional expansion correct (theory §7.2/7.4).**
   `probe2_coupled.jl`: W0 from `_gpic_weighted_moments` equals the §5 profile to
   2.8e-17 (CIC) / 3.2e-16 (TSC); mean-derivatives `dg`,`ddg` match central finite
   differences of the profile in μ (7.7e-10·σ and 1.8e-7·σ², FD-limited); the full
   assembled `M0·g + λM1·g' + ½λ²M2·g''` vs 2D Simpson quadrature of the tilted
   Gaussian: worst relative node error 2.9e-5 at r=0.05, 1.8e-3 at r=0.20 —
   consistent with the docs 7.5 table (7.7e-5 / 4.6e-3 worst-case).

3. **Transport consistency and rank test.** `probe3_anchors.jl` (a,e): the
   marginal drift formulas in `_gpic_drifted_gaussian` and the covariance
   transport `_transport_transverse_moments(·, −s)` agree to ≤1.4e-16 relative
   at s = −3e-3, 0, +2.7e-3 (so the coupled branch's `sqrt(b.a)` and the
   uncoupled `sigx` are the same quantity); `sigc² = d − b²/a` to 2.6e-16.

4. **Analytic add-back anchored to the validated soft-Gaussian kick.**
   `probe3_anchors.jl` (b): the hybrid's uncoupled terms
   (kbb_eff·K_BE and `_gpic_cov_pz(Hxx,Hyy,rx,ry)` = (Hxx·rx+Hyy·ry)/4 with
   rx = 2(cxpx + s·varpx)) are **bit-identical** (0.0 relative difference at 4
   test points) to `_cp_covariance_kick` on the uncoupled
   `StrongTransverseMoments` at S=−s — the /4 factor, the rx≡au convention, and
   the S sign are jointly pinned to the independently validated ThinStrongBeam
   path. (c): the coupled `_cp_covariance_kick` converges linearly in b to the
   uncoupled terms (rel diff 2.6e-5→2.6e-7 for px as b/√(ad): 1e-3→1e-5), so the
   two kick branches are mutually continuous. The centroid pz term
   0.5(Δp·μ') mirrors `_cp_kick`'s `centroid_u` term with the slice's linear
   centroid drift (ppxo≡0), on both branches, CPU and CUDA
   (gaussian_pic.jl:724,749; gaussian_pic_cuda.jl:838,1219).

5. **Neutralization identity (theory §6 boxed equation).** `probe3_anchors.jl`
   (d): real deposit through `_pic_deposit_drifted_serial!` of a 40,000-particle
   quantile lattice; amp = qsum/(sgx·sgy) makes Σ(residual)/n = 5.6e-17 (CIC) /
   1.6e-16 (TSC) — exact monopole removal. Deposit conserves count
   (qsum−n = −7.3e-12 CIC, 0.0 TSC): `_pic_cic_weights`/`_pic_tsc_weights` clamp
   indices rather than drop weights, and the grid always carries ≥1-cell margin
   (`_pic_interaction_grids` pads 1.5 cells; quantize shifts ≤0.5). Hence the
   declared CPU(qsum)↔CUDA(N) neutralization divergence
   (gaussian_pic.jl:79-85) is genuinely ~1e-16·N, as documented.

6. **Rank/degenerate fallbacks (release-review item).** `probe4_modes.jl`: all
   10 decision cases behave as documented — n=1 → :pic; σy=0 → :pic; NaN
   variance → :pic; line beam r=1 → :pic; η=0.5√eps → :pic vs η=2√eps →
   :coupled (the √eps threshold of theory §7.3, both sides); tol switching
   :coupled/:uncoupled; negative correlation handled via |rxy|. Empty slices are
   skipped on all routes (CPU `_gpic_collide!:791`; CUDA `valid` filters at
   269/605; sequential `continue` at 1000).

7. **Part-2 S1 fix end-to-end + composition-seam sweep.**
   `_pic_launch_solver(::GaussianPICPoissonSolver) = solver.pic`
   (gaussian_pic.jl:163) feeds the dispatch-based installer
   (`interface.jl:221-236`); the bare-collide gap warns
   (`_warn_inactive_pic_launch_config`, gaussian_pic_cuda.jl:81). All 27 options
   of `_PIC_SOLVER_OPTION_SCHEMA` traced across the seam: consumed via shared
   helpers (grid, deposit_method, green_type/cache + growth/min_ratio,
   field_derivative, min_transverse_extent, grid_quantize, longitudinal_kick,
   kbb1/2, luminosity_{scale,grid,deposit_method,schedule}, slicing/1/2,
   batch_mode, cuda_indexed_wavefront, backend_configurations), or rejected
   loudly (slice_interpolation≠:linear, interaction_grid≠:slice_pair,
   grid_extent≠:extrema via `_require_linear_slice_interpolation` on BOTH
   backends — probe4 confirms ArgumentError at collide for all three; cuda_async
   / cuda_batch_fft / cuda_wavefront_fft = false rejected at
   gaussian_pic_cuda.jl:87-95), or inactive identically to plain PIC
   (grid_extent_sigma under :extrema). No silently dropped option found.
   The part-2 §15 estimator drop is now a loud rejection
   (pic_cpu.jl:388-398, with measurement note).

8. **CPU↔CUDA structural parity.** Plane mapping: deposit planes
   off+1..4 = (p12 sL, p12 sR, p21 sL, p21 sR) (pic_cuda.jl:2656-2674 and
   indexed twin) matches the profile-fill order (gaussian_pic_cuda.jl:339-340,
   647-648) and the kick view mapping (422-425, 703-713; idx2→phi12, idx1→phi21
   at 898-906). Kick argument mapping verified on all three routes (source
   center, field params, kbb, field grid, moments all cross-correctly). Subtract
   kernels use Cartesian `charge[i,j,p]` with i≤nx, j≤ny on the padded array —
   safe and pad-preserving; CPU subtracts only [1:nx,1:ny] likewise. Batched
   moment kernel anchor is `idx[1]` in every block with the anchor rows written
   once (anchor_scale, pic_cuda.jl:5689-5695) — same anchor particle as the CPU
   slice-order anchor; `_cuda_gpic_source_moments` uses the commutative
   lexicographic-min anchor (part-7 C2 fix present, gaussian_pic_cuda.jl:446-459).
   Shared-memory tree reduction handles odd `active` correctly (5673-5684);
   `max_blocks` sizing is consistent with per-column launches. Indexed kick
   launch covers max(len1,len2) exactly. Margin applied only when subtracting on
   both backends (CPU early-returns :pic before the margin block at 602-604;
   CUDA gates on `do_gauss`). Sequential route deposits the unkicked opposing
   slice via explicit copies (1001-1005), matching CPU two-direction semantics;
   wavefront routes solve all fields before any kick. Slice-pair green cache is
   applied after the margin augment (gaussian_pic_cuda.jl:299-321) so cached
   grids cover the Gaussian tail box; the CPU passes margin-enlarged bounds to
   `_pic_slice_pair_green!` (gaussian_pic.jl:659-664) — same coverage contract.

9. **Type-strictness (part-7 G1 pattern).** `_gpic_gaussian_profile!` and
   `_gpic_coupled_profiles!` have strict `::T` scalar signatures; every call
   site either passes same-T values or converts via `T(...)` with
   T = eltype(profile buffer) (gaussian_pic.jl:492-501, 539-550;
   gaussian_pic_cuda.jl:341-348, 1050-1053).

10. **Docstring claims audited.** The six rejected options, the coupled-branch
    availability matrix, the CPU/CUDA neutralization divergence, and the
    margin/neutralize semantics all match code. Theory §6 margin table and the
    default margin_sigma=5, coupling_tol=Inf, neutralize=true match.

## Minor notes (not leads — no demonstrated reachability/impact)

- Coupled neutralization guard is `sg != 0` (gaussian_pic.jl:559;
  gaussian_pic_cuda.jl:354) where the uncoupled twin requires `> 0`
  (gaussian_pic.jl:508; CUDA 367, 658, 1057). A negative/denormal `sg` would
  flip or blow up the subtraction. `probe5_sg_guard.jl`: even at r=0.99 with an
  absurd 0.8σ one-sided box, sg = 0.151 (healthy case: 1.000000, corrections
  ≤1.1e-7); the box always contains the drifted centroid, so sg ≤ 0 was not
  reachable in any tried configuration. Twins agree; asymmetry is cosmetic.
- A slice pair that alternates between hybrid mode and the :pic fallback across
  turns shares one slice-pair green-cache key with two different box conventions
  (margin box vs particle wrap), which can cause cache rebuild thrash
  (performance only; `_pic_slice_pair_entry_usable` min_ratio/coverage checks
  keep it correct).
- `_gpic_collide!` luminosity init mixes `zero(eltype(beam1.rep.x))` and
  `T(NaN)` (gaussian_pic.jl:787) — mild type instability, same shape as plain PIC.
- Indexed CUDA route reports the slice-pair green cache unguarded
  (gaussian_pic_cuda.jl:157) while the sequential route guards it (1020-1022);
  both are safe (the workspace field is concrete, pic_cuda.jl:404) — cosmetic
  inconsistency shared with plain PIC (which also calls unguarded).
- `_cuda_gpic_augment_prep` re-runs `_cuda_pic_finish_interaction_indexed` even
  when `do_gauss=false` or `margin==0` (identical grids recomputed) — wasted
  host work only.

## Probe inventory

| Probe | Checks | Result |
| --- | --- | --- |
| probe1_profiles.jl | §5 erf integrals vs quadrature, mass leak, σ→0 limits | pass (≤3.9e-14) |
| probe2_coupled.jl | §7 W0≡g, mean-derivs vs FD, coupled 2D quadrature | pass (2.9e-5 @ r=0.05) |
| probe3_anchors.jl | transport identity, soft-Gaussian kick/pz anchor, b→0 continuity, neutralization | pass (pz anchor 0.0) |
| probe4_modes.jl | 10 mode-decision cases, 3 collide-time option rejections | pass (all as documented) |
| probe5_sg_guard.jl | coupled sg denominator reachability | sg ≥ 0.15 worst case |
