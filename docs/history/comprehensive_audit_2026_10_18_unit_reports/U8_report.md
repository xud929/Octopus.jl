# U8: spectral_sliced.jl + gaussian.jl + slicing.jl

Reading unit of the comprehensive audit 2026-10-18 (protocol: `docs/comprehensive_audit.md`;
brief: `result/comprehensive_audit_2026_10_18/plan/BRIEF_COMMON.md`, `plan/U8.md`). Tree under
audit: `/cfs/ad/dxu/Library/Julia/Octopus` at commit 24e8683, read-only. Every claim below is a
LEAD, not a finding. Probe scripts and their logs are under
`result/comprehensive_audit_2026_10_18/probes/U8/` (`p1_slicing_invariants.jl` + `p1.log`,
`p1f_schedule.jl` + `p1f.log`, `p2_sliced_pin_regime.jl` + `p2.log`,
`p2b_float32_bare_collide.jl` + `p2b.log`, `p3_gaussian_luminosity.jl` + `p3.log`,
`p4_near_round_continuity.jl` + `p4.log`, `p4b_near_round_steps.jl` + `p4b.log`). Julia 1.12.4,
4 threads, one rank, CUDA not exercised by this unit.

## Region

- `src/tasks/strongstrong/spectral_sliced.jl` lines 1-1343 (whole file)
- `src/tasks/strongstrong/gaussian.jl` lines 1-558 (whole file)
- `src/tasks/strongstrong/slicing.jl` lines 1-1060 (whole file)

Total 2961 lines, every line read.

## Provenance

READ line by line (the region): `spectral_sliced.jl` 1-1343; `gaussian.jl` 1-558; `slicing.jl`
1-1060.

READ as comparison references (outside the region, not audited): `spectral.jl` 294-335, 548-780,
846-1036, 1124-1146, 1280-1421, 1707-1877 (the undivided 6D collide and every leaf the sliced
collide claims to mirror); `interface.jl` 777-888 (`LongitudinalSlicing`), 994-1039
(`GaussianPoissonSolver` constructor); `pic_cpu_sliced.jl` 27-150, 1079-1084, 1438-1450,
1691-1735, 2108-2119; `pic_cpu.jl` 1028-1062, 1792-1800; `elements/strong_beam.jl` 85-130,
600-700, 760-905; `track/strong_beam_track.jl` 700-760; `pic_cuda.jl` 6236-6283;
`policies/Policies.jl` 1136-1150, 1214-1225; `test/runtests.jl` 9058-9100, 22646-22779,
25935-26010, 31641-31685; `docs/theory/gaussian_longitudinal_slicing.md` 137-370, 805-900;
`docs/theory/slice_longitudinal_interpolation.md` 78-114, 177-244;
`docs/theory/near_round_bassetti_erskine_switch.md` 1-40, 978-1047;
`docs/design/multi_process_policy.md` 703-772, 929-980; prior unit reports
`docs/history/comprehensive_audit_2026_08_05_b_unit_reports/U8_report.md` 461-530, 605-640 and
`U19_report.md` 95-150.

EXECUTED (numbers quoted in the sections below):

- `p1.log`: `gaussian_slice_centers(5)` vs the Furman-Zholents Table 1 row for algorithm #3:
  max |dz| = 2.020e-7 (table printed to 7 digits); interior quantile boundaries vs an
  inverse_erf-free bisection: max |db| = 6.131e-13; centers vs a 400k-panel midpoint-rule
  conditional mean: max |dz| = 6.638e-11. For all 8 accepted `method` symbols x {Float64, Float32}
  x {no dead particles, every 7th particle dead under `allow_lost_particles`}: indices partition
  the live set exactly, sum(weight) - 1 in {0, -1.1e-16}, boundaries sorted, centroid centers
  inside their slice, nslices honoured; aliases `:equal_spaced == :equal_width` and
  `:gaussian == :Gaussian == :normal_quantile` bit-identical. `:specified` with
  `positions=[NaN,0,0.5,1]` throws the derived-quantity diagnosis; `[-Inf,0,0.5,Inf]` and
  `[-0.5,0.5,100,200]` are accepted with counts `[0,244,101,154,1]` and `[163,182,154,0,1]`.
- `p1f.log`: `_slice_collision_order == _slice_collision_order_from_centers` (35 and 225 pairs);
  `collision_pair_batches` conflict-free, per-slice order preserved, covers every pair, batch
  times monotone, for 7x5 (11 batches, widest 5) and 15x15 with exact time ties (29, widest 15);
  the docstring example gives 29 batches, widest 15.
- `p2.log`, `p2b.log`: CPU policy vs multi-process policy at one rank. Float64 beams: 0/2688
  coordinates differ, luminosity equal, for `:grid` and `:grid_free`, through the task (2 turns)
  and through a bare `collide!` (Float64 and Float32 solver scalars). Float32 beams through a bare
  `collide!`: Float64 solver 1025/2688 (`:grid`, max 55 ulps) and 1067/2688 (`:grid_free`, 89
  ulps) coordinates differ, luminosity 3.1148286882e12 vs 3.1148287189e12; Float32 solver
  1054/2688 (504 ulps) and 350/2688 (2048 ulps). Receipt keys of `:spectral_slice_exchange` are
  identical under `:batched` and `:dataflow` and lack `max_in_flight, wait_calls, wait_ns, scans,
  high_planes, cross_batch_starts, batches_in_flight_max`, which the PIC twin's
  `:pic_slice_exchange` carries.
- `p3.log`: soft-Gaussian luminosity vs the closed form N1 N2 / (2 pi Sigma_x Sigma_y) from the
  sample moments: ratio 1.00289 (`gaussian_when_luminosity=1`) and 1.00129 (`=2`), 40000
  particles a beam, one slice. Half of beam 2 dead (x = NaN) under `allow_lost_particles`:
  L/L0 = 0.49976 for `gaussian_when_luminosity=1`, 1.00087 for `=2`; the beam-1 px-kick rms ratio
  lossy/no-loss is 1.00132 in both. `batch_mode=:sequential` vs `:wavefront` at 4 threads, 6000 x
  5000 particles, 5 x 5 slices: luminosity and every coordinate bit-identical (receipts
  `sequential`/`wavefront`).
- `p4.log`, `p4b.log` (out of region): `_cp_covariance_kick` across both near-round eta bounds
  (2.206e-4, 4.412e-4): the step across a bound is 2.000 x an equal-size step inside either
  branch for px, py, density and 1.88-2.00 x for pz (i.e. smooth, no switch jump); coupled with
  b0 = 0 vs the uncoupled specialisation: <= 3.4e-16 relative.

## Leads

### LEAD U8-1 [Moderate, confidence high] src/tasks/strongstrong/slicing.jl:119
Claim: Under `allow_lost_particles` the soft-Gaussian solver's default luminosity scale divides by the macroparticle count INCLUDING the dead, while every kick weight renormalises to the live count, so the reported luminosity falls with the survival fraction of whichever beam `gaussian_when_luminosity` samples and not with the other's -- a factor 2 between the two settings at 50% loss -- and the suite's semantics pin cannot see it.
Mechanism: `_strong_strong_luminosity_scales` (slicing.jl 119-134) returns `p1.npart * p2.npart / n1` with `n1 = last(_mp_current_shard(beam1.rep))`, the whole array length, dead particles included; `_finish_longitudinal_slices` (656-657, 691) makes `weight = members / total_live`, so the kick a half-dead beam delivers is the full-charge kick (measured 1.00132 rms ratio) and the Gaussian-side luminosity is unchanged, but the sampled side sums over live particles only against a scale per total particle. The solver's documented semantics ("RENORMALIZES -- a masked beam collides bit-identically to a beam that simply does not contain the corpses", `test/runtests.jl` 25943-25945, pinned 25983-25987) therefore holds for the kick and fails for the default-scaled luminosity on the sampled side; the pin passes only because it sets `luminosity_scale=1.0` (25984), which bypasses the `N1 N2 / n` default entirely, and the lossy beam is the Gaussian side under the default `gaussian_when_luminosity=2`. One quantity, two conventions in the same solver (brief class 9), invisible to its test (class 13). Seam, not audited here: `_spectral_luminosity_scale` (spectral.jl 300-309) divides by both totals while spectral's kicks renormalise too (the U19-3 table), so the family carries the same split.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 result/comprehensive_audit_2026_10_18/probes/U8/p3_gaussian_luminosity.jl` -- the `P3b` lines: `L/L0=0.49976` for `gaussian_when_luminosity=1` and `1.00087` for `=2` with the first 20000 of 40000 beam-2 particles set to `x = NaN`, kick rms ratio `1.00132` in both; under the pinned "renormalises" semantics both should read ~1.0, under a charge-loss semantics both ~0.5.

### LEAD U8-2 [Minor, confidence high] src/tasks/strongstrong/spectral_sliced.jl:31
Claim: The header's unconditional "at one rank ... that run is the CPU collide bit for bit, which is the pin the launcher child holds this code to" (also `docs/design/multi_process_policy.md` 4g/4h) holds for Float64 beams only; for Float32 beams the sliced route differs from the undivided collide by up to 55 ulps (default solver) and 2048 ulps (Float32 solver, `:grid_free`) and in the luminosity's 8th digit, and the pin runs Float64 beams only.
Mechanism: `_spectral_sliced_transport!` (726-728) migrates both beams into `_PICSlicedBeam{T}` with `T = LT = promote_type(eltype(x1), eltype(x2), typeof(klum))`, so a Float32 beam's slice states are Float64 and the in-place drift-in/kick/drift-out of `_spectral_sliced_drift_in!`/`_spectral_sliced_kick!` (275-305) accumulate across pairs in Float64, whereas the undivided `collide_pair!` (spectral.jl 1808-1836) works on `_pic_slice_states` copies in the beam's own eltype and rounds to Float32 after every pair. With a Float32 solver `LT` is Float32 and the opposite happens: the `_SpectralSlicedScratch{T}` payloads (243-255) round the Float64 workspace meshes `Phig/Exg/Eyg` -- and, for `:grid_free`, the mode sums written into a `Matrix{Float32}` plane (237) -- to Float32 before evaluation, where the undivided route evaluates the Float64 `ws.Phig` and a `Matrix{Float64}` `rho_modes` (spectral.jl 885). Neither rounding is wrong; the claim and its pin (`test/runtests.jl` 22646-22762, `Beam(..., Float64; ...)`) are quoted outside the regime they were measured in (class 8). Float32 beams are a supported configuration (owner decision 2026-10-16, one precision rule per element kind).
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 result/comprehensive_audit_2026_10_18/probes/U8/p2b_float32_bare_collide.jl` -- Float64 rows `differing=0/2688`; `beam=Float32 solver=Float64 grid` row `differing=1025/2688 maxulps=55 lum_cpu=3.1148286882e+12 lum_mp=3.1148287189e+12`; `beam=Float32 solver=Float32 grid_free` row `differing=350/2688 maxulps=2048`.

### LEAD U8-3 [Minor, confidence high] src/tasks/strongstrong/spectral_sliced.jl:1336
Claim: The spectral dataflow loop accumulates `scans`, `wait_calls`, `wait_ns`, `c.max_in_flight` and `pool.high_planes` and records none of them, so its `:spectral_slice_exchange` receipt cannot show how often the event loop blocked or how deep the in-flight pair count went, and its shape has drifted from the PIC twin it was copied from.
Mechanism: `wait_calls = 0; wait_ns = 0; scans = 0` (1084), `scans += 1` (1290), `wait_ns += ...; wait_calls += 1` (1329-1330), `c.max_in_flight = max(...)` (1095) and `pool.high_planes = max(...)` (919) are written but the `_record_execution!(:spectral_slice_exchange, ...)` at 1336-1341 lists only the message counts, `schedule` and `ranks`. `_pic_collide_dataflow!` records all of them (`pic_cpu_sliced.jl` 2108-2117: `max_in_flight, wait_calls, wait_ns, scans, high_planes, cross_batch_starts, batches_in_flight_max`) and its batched loop writes zeros for them (1445-1446) so the two loops share one receipt shape; spectral's two loops share a shape only because both omit the fields. Hand-copied receipt shape without a tripwire (class 2), instrumentation the receipt cannot see (class 15).
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 result/comprehensive_audit_2026_10_18/probes/U8/p2_sliced_pin_regime.jl` -- the three `P2 receipt` lines: spectral `keys=[:partials_sent, :partials_received, :payloads_sent, :payloads_received, :lum_sent, :lum_received, :messages, :pairs_coordinated, :planes_solved, :schedule, :ranks]` under both `:batched` and `:dataflow`; PIC twin additionally `:cross_batch_starts, :batches_in_flight_max, :max_in_flight, :wait_calls, :wait_ns, :scans, :high_planes`. Static form: `grep -n "wait_calls\|scans\|max_in_flight\|high_planes" src/tasks/strongstrong/spectral_sliced.jl` shows writes and no read.

### LEAD U8-4 [Minor, confidence high] src/tasks/strongstrong/slicing.jl:514
Claim: `:specified` slicing accepts non-finite and out-of-range `positions`: a `NaN` position reaches `_finish_longitudinal_slices` and is diagnosed as a non-finite DERIVED beam quantity ("a drifted position that overflowed ... or a slice moment ... inspect the slice separation and the slice moments"), and a position beyond the beam's extent is silently clamped to `zmax`, which manufactures a zero-width top slice holding exactly the extremum particle while the slice below it is empty.
Mechanism: `LongitudinalSlicing` (interface.jl 831-846, seam) checks only `length(positions) == nslices - 1`; `_longitudinal_slices_specified` (slicing.jl 503-517) computes `clamp(T(mu + p*sigma), zmin, zmax)`, `clamp(NaN, lo, hi)` is `NaN`, and the chokepoint at 647-648 raises `_nonfinite_coordinate_error(:beam, ...)`, whose message is written for drift overflow. For `p` large, `boundaries = [..., zmax, zmax]` and `_slices_from_boundaries` (569-572) files the particle with `z == zmax` via `searchsortedlast -> ns+1 -> clamp -> ns` into the last slice alone -- a one-particle slice whose transverse variance is zero, so under the soft-Gaussian solver (`_cp_covariance_kick` returns a zero kick for `a <= 0`) that slice's share of the charge (`1/n_live`) silently delivers no kick. A bottom-side clamp behaves differently (slice 1 empty, the `zmin` particle in slice 2). `_gaussian_slice_boundaries` (534-543) uses the same clamp, so `:normal_quantile` on a beam whose sample extremum lies inside the outer quantile (tiny beams) does the same. Declared option without defined invalid behaviour (class 5); quiet degenerate geometry (class 6).
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 result/comprehensive_audit_2026_10_18/probes/U8/p1_slicing_invariants.jl` -- the `P1e` lines: `positions=[NaN, 0.0, 0.5, 1.0] -> ArgumentError: non-finite value detected ... but all 500 beam macroparticle coordinates (z) are finite. The non-finite value is therefore in a DERIVED quantity ...`; `positions=[-0.5, 0.5, 100.0, 200.0] -> accepted; counts=[163, 182, 154, 0, 1]`; `positions=[-Inf, 0.0, 0.5, Inf] -> accepted; counts=[0, 244, 101, 154, 1]` (full message in `p1f.log`).

### LEAD U8-5 [Minor, confidence med] src/tasks/strongstrong/slicing.jl:88
Claim: The set of accepted `LongitudinalSlicing.method` values is hand-copied between the constructor's membership test and `longitudinal_slices`' dispatch chain with no derivation from one source and no coverage tripwire, and two of the three declared aliases (`:equal_spaced`, `:Gaussian`) are exercised by no test.
Mechanism: interface.jl 837-838 lists `(:equal_area, :equal_count, :equal_width, :equal_spaced, :normal_quantile, :gaussian, :Gaussian, :specified)`; slicing.jl 88-100 re-enumerates them in `if/elseif` arms with a terminal `throw(ArgumentError("unknown longitudinal slicing method"))` that the keyword constructor makes unreachable; the two lists agree today (probe: every alias bit-identical to its canonical method) but nothing fails if one gains a member the other lacks, and `grep -n "equal_spaced\|:Gaussian\b" test/runtests.jl` finds no use (only `:gaussian` at 26043). Class 2 and class 13.
Repro: `grep -n "equal_spaced\|:Gaussian\b" /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl` returns nothing; `grep -n "equal_spaced" src/tasks/strongstrong/interface.jl src/tasks/strongstrong/slicing.jl` shows the two independent lists. The P1 probe's `aliases:` lines show `true, true, true` at both precisions.

### LEAD U8-6 [Minor, confidence low] src/tasks/strongstrong/gaussian.jl:232
Claim: The moving-centroid longitudinal term `pz += 0.5 * ((px - px0) * mpx + (py - py0) * mpy)` uses a bare Float64 literal where its weak-strong twins `_cp_kick` (strong_beam.jl 781) and `_cuda_cp_kick` (strong_beam_track.jl 755) were changed by fix H (2026-10-16) to `oftype(S, 0.5)` so the arithmetic stays in the drift's working type; for a Float32 solver on a Float32 beam this promotes `pz` to Float64 mid-kick and rounds it back at the store.
Mechanism: `W = promote_type(typeof(kbb_slice), typeof(min_sigma))` (222) is the solver's scalar type and `S` is `W`; with `W === Float32` the literal widens the sum, so the kick body returns a `(Float32 x5, Float64)` tuple where fix H's rule asks for one type. The CUDA twin `_cuda_slice_kick_kernel!` (pic_cuda.jl 6264-6265) carries the same literal, so CPU and CUDA agree with each other and nothing was measured to diverge; this is the one-precision-rule consistency the twins already adopted, not a measured defect. Out of hypothesis; style-adjacent.
Repro: `grep -n "0.5 \* ((px - px0)" src/tasks/strongstrong/gaussian.jl src/tasks/strongstrong/pic_cuda.jl` (bare literal) against `grep -n "oftype(S, 0.5) \* ((px - px0)" src/elements/strong_beam.jl src/track/strong_beam_track.jl` (fix H form). No numerical consequence measured; a Float32 solver was not run on CUDA by this unit.

Out-of-hypothesis style note (no lead): `_slice_collision_order` (slicing.jl 703-710) and `_slice_collision_order_from_centers` (712-720) are two hand-written walkers of the same rule; the first could delegate to the second. Measured equal on 35 and 225 pairs (p1f), so no present defect.

## Clean

Hypothesis 1 -- `spectral_sliced.jl` against `spectral.jl`:

- Per-pair arithmetic compared term for term: `_spectral_sliced_drift_in!` (275-283) ==
  `_spectral_interaction!` 1325-1330; `_spectral_sliced_kick!` (286-305) == 1337-1352 including
  `Kz = phiL - phiR` scaled by `hzi`, the `clamp` of `zL`, the drift-out and the `0.25` terms;
  `_spectral_sliced_source!` (229-240) drifts by `0.5*(source.center - field.lb|rb)` == 1320-1323
  and deposits with the same `_spectral_grid_deposit!` / `_spectral_free_modes!`;
  `_spectral_sliced_virtual!` (211-222) == `_spectral_midpoint_source` 1302-1314;
  `_spectral_sliced_payload!` (243-255) calls `_spectral_grid_potential_from_rho!` with the slice's
  GLOBAL count exactly as `_spectral_field_grid_potential!` calls it with `length(sx)`;
  `_spectral_sliced_eval` (258-272) uses `_spectral_grid_potential_eval!` on the payload planes
  and `_spectral_free_potential_from_modes` with the global count. Both directions deposit and
  take virtual positions before either kick, matching the undivided order where direction 1 reads
  `coord1` and direction 2 reads the un-swapped `state2[j]`.
- Charge accounting: the kick scale is `T(weight_source) * kbb_field` (617-618, 1239-1240) ==
  `slices.weight * kbb` (spectral.jl 1829, 1832); `ns` passed to the solve and the `:grid_free`
  evaluation is the source slice's global count (`counts1[pr.i]` for direction 1); the deposit
  tripwire runs on the folded plane with that count (spectral.jl 695-700). Skips are decided from
  global counts (380-381, 1060), matching `isempty(idx1) || isempty(idx2)`.
- Luminosity: extents folded from every member's `(min, max)` records equal the undivided
  `min(minimum(x1), minimum(x2))` (negation round-trips exactly); mesh construction 519-526 is
  `_spectral_luminosity_pair` 995-1000 line for line; deposits via the same `_spectral_cic_deposit!`;
  `lum * T(klum) / (hx*hy)`; written by collision position, all-summed as one nonzero plus zeros
  (exact), folded `for p in 1:npairs` like the undivided path. Measured: Float64 luminosity equal
  to the last bit on both routes (`p2.log`, `p2b.log`).
- Message protocol enumerated: for each (direction, plane) every source member sends one plane
  to `solvers[d][m]` and that rank posts one receive per source member with the same tag
  (`_SPEC_TAG_PARTIAL + 2(d-1) + m-1`); each solver sends its payload to every field member, who
  posts a receive from `solvers[d][m]`; luminosity extents go from every member of `g1`/`g2` to
  `first(g1)`, which posts one receive per member; the mesh goes to the deduplicated
  `_pic_sliced_members(g1, g2)` and every participant posts exactly one receive. Tag bound checks:
  batched `(widest-1)*16 + 12 < widest*16`; dataflow `(ns1*ns2 - 1)*16 + 12 < ns1*ns2*16`.
- Dataflow gate: `_pic_df_predecessors` yields the previous non-empty pair on each slice in
  collision order; a rank in `g1` holds slice `i` for every pair on it, so `index_of[prev]` always
  resolves when `in1`; a pair runs DEPOSIT only after both predecessors passed KICK; a rank only in
  `g2` is gated implicitly by the payload arriving after `g1`'s gated deposits. Measured: the two
  loops agree bit for bit at one rank for every sliced variant (suite pin, re-run in `p2.log`).
- Scratch discipline: receive targets are fully overwritten; `planes_out` are `fill!`ed before
  deposit; records are zero-filled; `virts` resized and fully written; the batched scratch is
  reset only after every message of the batch was waited; dataflow buffers return only after
  `_mp_test_all(pr.sends)`.
- Closures: the `let` re-bindings (448, 569, 606) give each closure names assigned once; in the
  dataflow loop `wait_calls/wait_ns/scans/stage/union` are reassigned at function scope but
  captured by no closure.

Hypothesis 2 -- `slicing.jl` against the Furman-Zholents table and the theory note:

- The note's `slice_method` table and the corrected `w_2 = 0.137503` (algorithm #4) belong to
  `GaussianStrongBeamSpec` in `src/elements/strong_beam.jl` and are pinned at `test/runtests.jl`
  9058-9086 -- outside this region. What `slicing.jl` implements is algorithm #3's node
  (`gaussian_slice_centers`, the conditional mean `N_s[phi(lambda_k) - phi(lambda_{k+1})]`) and
  #2/#3's quantile edges (`_gaussian_slice_boundaries`): measured 2.020e-7 against the table row,
  6.638e-11 against an independent quadrature, 6.131e-13 against bisection edges (`p1.log`).
- Weights normalise (sum - 1 in {0, -1.1e-16}), boundaries ordered, centers inside their slice,
  indices an exact partition of the live set, for all 8 accepted methods x 2 precisions x mask
  on/off; `:equal_count` ordering by rank, the `:equal_area` interpolation (monotone `current`,
  `y2 > y1` strictly on every reachable branch), the empty-slice midpoint centre, and the slice-1
  convention for a zero-width beam were checked by reading. Every accepted method symbol reaches a
  dispatch arm (the `unknown method` throw is unreachable from the keyword constructor).
- `_live_z_stats` lane fold keyed by the global index; `_lane_z_moment` `fma` for `Val(2)`;
  `_threaded_histogram` and `_threaded_indices_by_function` use distinct names inside the worker
  closures (no `Core.Box`); `_finish_longitudinal_slices` weights over the live total; one exchange
  per slice vector when divided.
- `collision_pair_batches`: conflict-free, order-preserving per slice, complete, monotone in time,
  including the 15x15 exact-tie case (`p1f.log`).

Hypothesis 3 -- `gaussian.jl` moments, kick, luminosity:

- `_slice_moments_finalize` -> `StrongTransverseMoments{T,COUPLED}(varx, covxy, vary, covxpx,
  covxpy, covpxy, covypy, spx2, covpxpy, spy2)` matches the struct's `(a0, b0, d0, bxx, bxpy, bypx,
  bypy, qxx, qxy, qyy)` order with `bxpy = cov(x, py)` from `sum(dx*dpy)` and `bypx = cov(px, y)`
  from `sum(dpx*dy)`; `_slice_empty_moments` and the `Val(false)` `_soft_gaussian_covariance` use
  the same order; shifted moments via `fma`, variance floored at `min_sigma^2`.
- `_apply_slice_kick_one!`: `xx = x - mx + mpx*S` and the centroid term `0.5*(dpx*mpx + dpy*mpy)`
  match `_cp_kick` with zero curvature terms; drift working type is the solver's (fix H);
  `LONGITUDINAL=false` restores `pz0` and uses the paraxial drift. Luminosity `sum(density*2pi)/2pi
  * w * N1N2/n` equals `N1 N2 int rho1 rho2` (closed form check: ratios 1.00289 and 1.00129 with
  ~0.3% statistical error, `p3.log`), consistent with the prior U8 report's 0.999980.
- Sequential and wavefront schedules: moments for a batch are taken before any kick of the batch
  and the batch shares no slice, so each pair sees exactly the state the sequential loop would;
  per-kick accumulators with the same `_chunk_bounds` grid and `sum` of 64 partials; luminosity by
  slot. Measured bit-identical in luminosity and every coordinate at 4 threads (`p3.log` P3c), as
  the receipt confirms both schedules ran.
- `_gaussian_moments_finite` covers the coupled cross terms implicitly (`|dx*dy| <= max(dx^2, dy^2)`
  so a finite `sx, sy` implies finite `covxy`).
- Near-round switch (out of region, named by the hypothesis): no value jump at either eta bound
  (across/inside step ratio 2.000 for px, py, density; 1.88-2.00 for pz), coupled `b0 = 0` equals
  the uncoupled specialisation to 3.4e-16 (`p4.log`, `p4b.log`).

## Unchecked

- Multi-rank execution. Every probe ran at one rank; `_mp_isend/_mp_irecv!/_mp_wait_any/
  _mp_test_all` semantics (Policies.jl), the migration (`_pic_sliced_migrate_pair_in/out!`), and
  `_pic_sliced_layout`'s group arithmetic were read for their docstrings and signatures only. The
  dataflow loop's correctness at two or more ranks rests on the suite's launcher pins, not on this
  unit.
- CUDA twins of `gaussian.jl` and `slicing.jl` (`pic_cuda.jl`, `strong_beam_track.jl`,
  `_cuda_live_z_stats`) were not compared beyond the one literal in LEAD U8-6; no GPU probe ran.
- `_cp_covariance_kick`'s elliptical and blend branches: only continuity across the bounds was
  probed; their accuracy was the previous audit's U8 and is out of this region.
- The theory notes were read in the sections named under Provenance, not whole; the rest of
  `gaussian_longitudinal_slicing.md` (sections 5-9) concerns rules `slicing.jl` does not implement.
- `docs/todo.md` was not searched broadly for open rows on these files (a broad grep returned 59 KB
  of unrelated rows); a narrow grep for "charge semantics"/"renormaliz" found nothing, so whether
  LEAD U8-1 is already an open row is not established.
- `_spectral_collide_dataflow!` was not run under `requested === :sequential` with
  `_SPECTRAL_SLICED_LOOP = :dataflow` by this unit; the suite's loop pin covers that variant.
- The `:equal_area` histogram's `cumulative[end] = one(T)` override and `_slice_bin`'s clamp of the
  `z == zmax` particle into the last bin were checked by reading, not measured.
