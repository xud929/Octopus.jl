# U23: analysis/: mode clusters, coupled parameterizations, 4D eigenmodes, symplectic algebra

Tree under audit: `/cfs/ad/dxu/Library/Julia/Octopus` at commit 24e8683, read-only. Every claim below is a
LEAD, not a finding. Written 2026-10-19 for a reader who was not in this session.

## Region

| File | Lines read | Lines |
|---|---|---|
| `src/analysis/mode_clusters.jl` | 1-1377 (all) | 1377 |
| `src/analysis/coupled_parameterizations.jl` | 1-856 (all) | 856 |
| `src/analysis/eigenmodes_4d.jl` | 1-720 (all) | 720 |
| `src/analysis/symplectic_linear_algebra.jl` | 1-466 (all) | 466 |

Total 3419 lines, every line read. References read for comparison: `docs/theory/twiss_dispersion.md`
sections 3 (lines 156-335), 4 (336-545), 6 (632-865), 7 (866-1085), 13.2-13.4 (2276-2415),
13.8-13.10 (2617-2832); `validation/twiss_benchmark_cells.jl` lines 1-260 (header, beam pin, cell builders;
the remainder is table I/O that no lead touches). Consulted outside the region, by grep only, to locate the
consumer of one lead: `src/analysis/dispersion_routes.jl` 1205-1290 (`_cluster_trace`,
`_longitudinal_candidate`), `src/analysis/twiss_dispersion_analysis.jl` 275-300, 655-700, 1095-1170,
`src/analysis/Analysis.jl` 200-246 (`Determined`), `test/runtests.jl` 2705-2748 (the rolled-FODO fixture,
copied into the probes) and the grep hits for `.index`, `half_members`, `_unscale_twiss`.

## Provenance

READ line by line: the four region files in full; the theory sections above; the benchmark header.

Hand derivations performed while reading (recorded so the "Clean" claims are checkable):
- `_adjugate2`: `-S_2 K' S_2 = [K22 -K12; -K21 K11]`; `_rotation2`: `M U = U R(mu)` from `M u = e^{-i mu} u`,
  `U = [Re u, -Im u]`; `_symplectic_inverse = -S M' S`.
- Every back-transformation row (`_unscale_twiss`, `_unscale_covariance`, `_unscale_projector`,
  `_unscale_graph`, `_unscale_crab_dispersion`, `_unscale_momentum_dispersion`, `_unscale_edwards_teng_R`)
  from `X~ = C X`, `C = diag(a, 1/a, ...)`.
- The oriented 2D example `u = (1, -i)`: `u' S u = -2i`, `U = I`, `P = -Im(u u') S = I`, `G = I`, `kappa = 1`,
  `beta = gamma = 1`, `alpha = 0`; (E9) both evaluations give `(x^2 + p^2)/2`.
- (E10) radicand `= (tau_1 - tau_2)^2`; (E11) `M + M^-1 = sum tau_j P_j`; (E12)
  `(M - M^-1) P_j S = -2 sin(mu_j) G_j` with `U^-1 = -S U' S`; (E13) `u u' = G + i P S`, so the pivot
  column divided by `sqrt(G_bb)` is `u` with `u_b` real positive.
- (T7) `det(adj(M_xy) + M_yx) = det(M_xy + adj(M_yx))`; (T2)-(T4) `V_1^-1 = lambda [I -adj(R); R I]`,
  `V_2 = V_1 Pi`; (T11) for form 1 by direct multiplication `V_1^-1 M V_1`, which gives
  `Mbar_1 = M_xx - M_xy R`, `Mbar_2 = M_yy + R M_xy`, and from (T5) `R M_xy = M_yx adj(R)`, so the code's
  `M_yy + M_yx adj(R)` is the same block; form 2 blocks by `Pi (.) Pi`; `R_2 = -2A/(D - s sqrt(Delta))` is
  (T8) with the other trace sign under the SAME labels, consistent with (T4).
- (M6)/(M7)/(M8): `u_px = (-alpha - i kappa)/conj(u_x)` reproduces every entry of the (M8) matrix in
  `_mais_ripken_normalizer`; (M11), (M14), (M15), (M16) reproduced entry by entry from
  `Sigma = sum eps_j Re(u_j u_j')` with the (M7) vectors; (M13) from (M5).
- (B4) and (B8) re-derived from `V_1 B` and `V_2 B` (not only compared with the theory text): form 1
  `u_1y conj(u_1x) = lambda^2 [(alpha_1 R_12 - beta_1 R_11) + i R_12]`, form 2
  `u_1y conj(u_1x) = lambda^2 [(alpha_1 R_12 + beta_1 R_22) - i R_12]`, likewise for mode 2.
- (B10), (B11): `(P_1)_{yx} = -lambda^2 R` for form 1, `(P_2)_{yx} = -lambda^2 R` for form 2,
  `(G_1)_{xx} = lambda^2 Q_1` (form 1), `(G_1)_{yy} = lambda^2 Q_1` (form 2); `det U_xj = kappa_jx`.
- (N2), (N20), (N21): `T_c = (i/2) U' S M U` is the restricted map because `U' S U = -2i I`; conjugation of
  the half gives Gram `-conj(H)` (code line 1299); `_component_basis` columns satisfy `w' S w = -2i sign(lambda)`
  before the conjugation of negative columns; the Sylvester call `sylvester(T11, -T22, -T12)` solves
  `T11 X - X T22 = T12`, the projector `[I X; 0 0]` commutes with `T` exactly then.

EXECUTED (all scripts and logs under
`/cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U23/`; package loaded with
`julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4`):
- `probe1_routes.jl` (log `probe1_routes.log`): 200 manufactured stable 4x4 maps (seed 20260911,
  `_manufactured_symplectic_map(rng, 4; stable=true)`); 200/200 frames formed; worst values over the set,
  in units of `eps()`: frame reconstruction (I1) normalized 17.3, `U' S U - S` 422, normalization residual
  55, row sums 27, column sums 234; `u_1x`, `u_2y` imaginary part 1 and real part positive on all 200;
  closed-form check tune difference 7008, projector 1.09e5, signed-area 4.8e4, covariance and outer-product
  2.6e8 absolute (ill-conditioned maps, no relative normalization), permutation `(1,2)` always, PSD margin
  below -1e-12 flagged on at least one map (reported value, not judged); Mais-Ripken (M5) 2282,
  `u` difference 233, (M8) vs `frame.normalizer` 150 relative, (M12) vs (M9) 118 relative, (M13) 2000,
  `M Sigma M' - Sigma` 35; the three Edwards-Teng routes: `u` identical (normalizer, direct) and 174 (map),
  `R` normalizer-vs-direct 5 (form 1) and 26 (form 2), normalizer-vs-map 1506 and 3328, admissibility never
  disagreeing, mode tunes of the normal blocks equal to the frame tunes exactly on the normalizer and direct
  routes and within 2.3e4 (map route), (B4)/(B8) phases vs (M6) within 2.6e4 at worst, (T5) reconstruction
  normalized at most 626, (E9) two action evaluations within 14 relative.
- `probe2_clusters.jl` (log `probe2_clusters.log`): the design fixtures through `_mode_clusters`
  (classifications listed under Clean) and the `ClusterMode.index` pairing under `resolution_chord = Inf`
  (26 modes in 13 resolved m = 2 clusters, 4x4 and 6x6) and under an explicit partition (16 modes): every one
  MISPAIRED (numbers in LEAD U23-1).
- `probe3_analyze_index.jl` (log `probe3_analyze_index.log`): the public `analyze` with
  `clusters = [[1,2,5,6],[3,4]]` and `longitudinal_mode = <canonical index>` on `diag(R(0.73), R(1.41), R(0.05))`
  and on a weakly coupled conjugate of it (LEAD U23-1).
- `probe4_misc.jl` (log `probe4_misc.log`): the minimal repro of U23-1; scaling invariance of the frame
  through the back-transformation table over `:none`, `:auto`, `(3.0, 0.2)` on 50 manufactured maps (worst
  relative differences: `U` 2.4e4 eps, `P` 954, `G` 4.9e4, beta 4.9e4, gamma 4.9e4, alpha 6.8e5 absolute,
  kappa 517, tunes 284, `R_1` 1483, `R_2` 1.2e4); the two rephasing floors on rolled uncoupled cells; the
  `tau_real` regime for a synchrotron pair (`beta_z` 160 and 1e4, `Q_s` 1e-3 .. 1e-5, scaled and unscaled).
- `probe5_jordan_floor.jl` (log `probe5_jordan_floor.log`): 384 rotated +1 Jordan pairs
  (`W ([1 L; 0 1] (+) R(1.2)) W^-1`, `L` in 1 .. 100, conjugation strength 0.2 .. 3, 16 seeds each):
  0 classified complex; worst `|Im rho| / tau_real = 0.46` (`L = 100`, strength 0.5, `||M||_2 = 399`).

## Leads

### LEAD U23-1 [Major, confidence high] src/analysis/mode_clusters.jl:775
Claim: `_recover_modes` tags the j-th recovered mode of a resolved multi-member cluster with `index = half[j]`, a canonical eigenvalue index taken by POSITION, while the j-th column and its eigenvalue come from `eigen(T_c)` in LAPACK's order, so `ClusterMode.index` names the other member in every resolved m = 2 cluster measured, and the public `analyze(longitudinal_mode = <canonical index>)` then computes the dispersion of the wrong mode while its receipt says "certified selection of canonical eigenvalue <index>".
Mechanism: `half` is sorted in the canonical order (ascending `mod(angle, 2 pi)`, `_half_of` over `members`); `theta` is `eigen(Matrix(T)).values` (line 733), whose order is unrelated to `half`, and the snapping at lines 762-770 replaces each `theta[j]` by the NEAREST oriented Schur value but never re-derives which canonical index that value is; line 775 then writes `ClusterMode(half[j], theta_out[j], ..., U_rotated[:, j], ...)`. The vector, eigenvalue and tune inside one `ClusterMode` are mutually consistent (the (I1) residual against the mode's own eigenvalue is 4e-16 .. 1.3e-15 in the probes); only `index` is wrong, so nothing inside `_mode_clusters` notices. The cluster's `eigenvalues`/`tunes` follow the same `eigen` order while `half_members` stays canonical (probe 3 prints `half=[1, 2] tunes=[0.73, 0.05]` where canonical eigenvalue 1 has angle 0.05). Reachability: a resolved m >= 2 cluster arises under `resolution_chord = Inf` (forced, `_recover_modes` line 750) and under an explicit `partition` (public `clusters` option); at the default chord a merged cluster re-evaluates to the same chord and stays unresolved, so the default path is not affected. The consumer that turns the wrong receipt into a wrong physical result is outside this region: `src/analysis/dispersion_routes.jl:1253`, `_longitudinal_candidate`, selects `findfirst(m -> m.index == idx || m.index == partner, modes)` and reports `modes[k].index` as the certified selection (a seam for the auditor; the suite pins `m.index == c.half_members[1]` only for m = 1, `test/runtests.jl:3296`, so no tripwire covers m >= 2: defect class 13 beside classes 3 and 6). Partly out of hypothesis: a receipt/consumer-protocol defect rather than a convention error.
Repro: `cd /cfs/ad/dxu/Library/Julia/Octopus && julia --project=. -e 'using Octopus, LinearAlgebra; R(m)=Octopus._rotation2(m); M=[R(0.73) zeros(2,2); zeros(2,2) R(1.41)]; c=Octopus._mode_clusters(M; rho_M0=1e-15, partition=[[1,2,3,4]]); for m in Octopus.determined_value(c.clusters[1].modes); println((m.index, round(m.tune; digits=3), round(abs(angle(c.eigenvalues[m.index])); digits=3))); end'` prints `(1, 1.41, 0.73)` and `(2, 0.73, 1.41)` (a correct pairing prints equal second and third entries). Under `resolution_chord = Inf` the rolled FODO detuned 1e-12, 2.8e-11, 1e-10 and 11 of 18 random conjugations of `R(0.73) (+) R(0.73 + 1e-11)` (4x4 and 6x6) show the same (`probe2_clusters.jl`, "MISPAIRED" lines, 26 of 26 modes). End to end: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U23/probe3_analyze_index.jl` prints, for `longitudinal_mode = 1` whose eigenvalue angle is 0.05, `routes.longitudinal = 1`, `tau_s = 1.490349` (expected `1.997501`), the receipt "certified selection of canonical eigenvalue 1", and on the block-diagonal map a `:singular_longitudinal_projection` degradation for a regular map; on the coupled map `eta = [-0.02106, -0.02042, 0.001551, 0.0002357]` against the auto-cluster reference `[0.022386, 0.018797, -0.0025146, -0.039826]`, status `:failed` only because the Newton and fixed-point routes landed on "another invariant plane". Requesting index 2 (the betatron eigenvalue) returns the synchrotron mode with status `:passed` and `eta = 0`.

### LEAD U23-2 [Minor, confidence high] src/analysis/mode_clusters.jl:121
Claim: `_REAL_CLASS_MULTIPLIER = 1.0` lies outside the admissible window of the repository's own one-tenth/ten rule once the extended Jordan family counts (the docstring records the window as `[3.87, 3.36]`, "EMPTY on the accepted side by the margin 2.6"), the constant is held "until the owner decides", and the re-measurement it cites (`stage9/verify/orch_major_v3.jl`) is not in the tree, so the real-class floor's accepted margin is a factor 2 to 3 rather than 10 and cannot be re-derived from committed material.
Mechanism: `tau_real = sqrt(rho_M1 max(1, ||M||_2))` classifies `|Im rho| <= tau_real` as real-class; a rotated +1 Jordan pair splits by `sqrt(g e)` with `g` up to `||M||_2`, and under strong symplectic conjugation the computed split reaches 0.39 (docstring) to 0.46 (probe 5) of `tau_real`, so a slightly larger perturbation would make a drift-like unit pair "complex", and a slightly larger multiplier would make the smallest genuine complex pairs of the fixture table (`R(1e-6) (+) R(1.2)`, ratio 33.6) real-class; no single constant satisfies both by the window rule. Defect classes 8 and 14 (hypothesis 3: the threshold is fitted, not derived, and its fit is documented as unresolved). No misclassification was found; the lead is the margin and the provenance, not a wrong verdict.
Repro: `grep -n 'EMPTY on the accepted side' /cfs/ad/dxu/Library/Julia/Octopus/src/analysis/mode_clusters.jl` (the docstring's own statement); `find /cfs/ad/dxu/Library/Julia/Octopus -name orch_major_v3.jl -not -path '*/result/*'` (nothing); `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U23/probe5_jordan_floor.jl` prints `cases: 384; Jordan pairs NOT real-class: 0; worst |Im rho| / tau_real = 0.46`.

### LEAD U23-3 [Minor, confidence low] src/analysis/coupled_parameterizations.jl:328
Claim: the theory-6.2 position convention (`u_1x > 0`, `u_2y > 0` real) is implemented twice with two different vanishing floors, `_rephase_mode` switching to the (E14) pivot at `|u_b| <= sqrt(eps) ||u||` (`eigenmodes_4d.jl:465`, `_PHASE_REFERENCE_FLOOR`) and `_mais_ripken`'s (M7) `vectors` rephasing on the reference component down to `64 eps ||u||`, so `MaisRipkenSet.vectors` and `NormalModeFrame4D.vectors` are two conventions for one quantity (defect class 9).
Mechanism: `_mais_ripken(frame)` receives the already rephased frame vectors and rephases them again with its own floor; between the two floors the two results differ by an O(1) phase, and even above both floors they can differ in the last bits (probe 4: at rolls 1e-7 and 1e-9 the frame's mode-2 reference component has imaginary part -5.6e-17, so `mr.vectors[2] != frame.vectors[2]` bitwise). Inert in practice: no `src/` consumer reads `mr.vectors` (grep: only `test/runtests.jl:2117, 2503`), and from a frame the between-floors regime is unreachable, because the reference component carries signed area `kappa >= 1/2` (`kappa_1x = kappa_2y >= 1/2` by the label rule and (M3)), `|u_b| |u_pb| >= kappa` forces `||u||^2 >= 1/(2 sqrt(eps)) = 3.4e7` for `|u_b| <= sqrt(eps) ||u||`.
Repro: `grep -n '_PHASE_REFERENCE_FLOOR = \|projection_rtol) \* norm(v\[j\])' /cfs/ad/dxu/Library/Julia/Octopus/src/analysis/eigenmodes_4d.jl /cfs/ad/dxu/Library/Julia/Octopus/src/analysis/coupled_parameterizations.jl` shows `sqrt(eps(Float64))` against `64 * eps()`; `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U23/probe4_misc.jl` section "the two rephasing floors" prints `mr.vectors==frame.vectors: false` for mode 2 at rolls 1e-7 and 1e-9 with `frame ref comp imag=-5.6e-17`.

## Clean

What was compared against what, and what was measured. Anything not listed here is under Unchecked.

- `symplectic_linear_algebra.jl` (hypothesis 1, "reciprocal canonical scaling and its back-transformation
  table"): every row of the table re-derived by hand from `X~ = C X` (see Provenance) and measured: the
  frame quantities of 50 manufactured maps computed under `:none`, `:auto` and the explicit `(3.0, 0.2)`
  scaling and transformed back agree to at most 6.8e5 eps (alpha, absolute, on the worst-conditioned map) and
  typically 1e3 eps (`probe4_misc.jl`). `_auto_scaling_factors` matches its docstring (`sqrt(p/q)`, factor 1
  on a vanishing, non-finite or overflowing quotient). `_manufactured_symplectic_map`: `S H` is Hamiltonian
  for symmetric `H` (checked: `(SH)'S + S(SH) = 0`), so the fixture is exactly symplectic up to `exp`.
- `eigenmodes_4d.jl` (hypothesis 2): the orientation rule is the sign of `Im(v' S v)`, never the sign of
  `Im rho` (`_orient_eigenvector`, and in the cluster route `_evaluate_component` line 889-896 and
  `_krein_classification`), as theory 3.2 requires; `u' S u = -2i` holds to 55 eps on 200 maps; `mu =
  mod(-arg rho, 2 pi)` by `atan(-imag, real)`; `U_4 = [Re u, -Im u, ...]`, `P_j = -Im(u u') S`,
  `G_j = Re(u u')`, `kappa_ja = -Im(conj(u_a) u_pa)` all match (E6), (E13), (M1), and the stored arrays are
  the (M1) formulas on the stored (rephased) vectors as the comment at line 408 claims (`mr.beta == f.beta`
  bitwise on 200 maps). The closed-form route (E10)-(E14) agrees with the eigenvector route on 200 maps with
  the trace-based permutation always `(1, 2)`; its "(E14) sum is an identity" remark is correct
  (`sum tau_j P_j = M + M^-1` and `sum P_j = I` hold for any two distinct traces). Labelling is the
  maximum-weight rule on `kappa_jx` (`_mode_label_order`, margin reported); there is NO continuity rule in
  this region and none is claimed: theory 8.8/10.4 continuation lives elsewhere, (T9) is used only as the
  initialization branch at `D = 0` (`_map_route_label_sign`, `+1` convention stated).
- `coupled_parameterizations.jl` (hypothesis 1, "Mais-Ripken and Edwards-Teng conventions ... position
  convention, phase branch, det R signs"): (M6) phases are `(cos, sin)` pairs with no angle evaluated and
  the primary/secondary assignment of the theory (x for mode 1, y for mode 2); (M8) reproduces the theory
  matrix entry by entry; (M11)-(M16) reproduce `sum eps_j Re(u_j u_j')` entry by entry and agree with
  `_matched_covariance_4d` to 118 eps relative on 200 maps; (B4)/(B8) match the theory and a first-principles
  derivation from `V_1 B`, `V_2 B`, and agree with the (M6) phases of the same vectors on 200 maps; (B10) is
  evaluated by right division, the second expression of each row is reported; (B5)/(B9) divide the
  projected functions by `1 - u` (form 1) or `u` (form 2) with the plane assignment of the theory; (T11)
  blocks for both forms are correct (hand derivation plus the (T5) residual at most 626 eps normalized); form
  2 under the SAME labels uses `R_2 = -2A/(D - s sqrt(Delta))` and its normal block for mode 1 carries
  `mu_1` (measured `tr(block_1) - 2 cos(mu_1)` at most 427 eps, mode tunes equal to the frame's on every
  route). Admissibility is `1 + det R > 0 AND area weight > 0` on every route, never the sign of `det R`
  alone; `1 + det R = 0` cannot occur with a non-vanishing (T8) denominator (shown: it requires `|D| =
  sqrt(Delta)`, which the denominator floor catches), so `area_weight` stays finite. The frame methods take
  no `kwargs...`, so a caller cannot override the frame's labels through a splat.
- `mode_clusters.jl` (hypothesis 3, "cluster resolution near degeneracy: thresholds derived or fitted"):
  the thresholds are fitted policy constants, each docstring naming its bracket or window and the fixtures;
  the tables behind them are committed verbatim in `docs/history/twiss_dispersion_analysis_history.md`
  (sections "Measurement tables" and the appendix carrying `measure_stage3.jl`), except as LEAD U23-2 says.
  The design fixtures reproduce their documented verdicts (`probe2_clusters.jl`): the exact rolled FODO at
  `pi/4` is one definite cluster, `kappa_frame = 11.930007605509969` (`1 / 0.0838222432933016` of theory
  13.10 is 11.9300076), chord 2.0, `:cluster_unresolved`; detuned 1e-3, 1e-6, 1e-9 resolve into two
  singletons; detuned 1e-12 merges with chord 0.029590539868219357 (docstring 2.959e-2) and stays
  unresolved; `R(0.9) (+) R(-0.9)` is `:indefinite` with Gram signs `[-1, 1]`; `R(0.9) (+) R(0.9)` chord 2,
  unresolved; `diag(2, 1/2, R(1.2))` `:unstable`; `diag(1 + 1e-6, 1/(1 + 1e-6), R(1.2))` `:unstable` at the
  roundoff `rho_M0` and `:unit_eigenvalue` at `rho_M0 = 1e-6`; `R(0.9) (+) R(0.9 + 1e-7)` resolved at
  roundoff and unresolved at `rho_M0 = 1e-6` (the `_eigenmodes_4d` docstring's two examples); a 6D map with
  a drift `(z, pz)` block gives a real-class `:unit_eigenvalue` cluster `[1, 2]`. The real-class floor has
  margin >= 1.3e3 for a synchrotron pair down to `Q_s = 1e-5` (scaled) and >= 2.7e3 unscaled at
  `beta_z = 1e4` (`probe4_misc.jl`), and no rotated Jordan pair of 384 crosses it (`probe5`). Read and found
  consistent with their docstrings: the Krein classification order (floor, then both signs with
  `r_mp <= mp_tol`), the Gram-conjugation `-conj(H)`, the `m = 1` `mp_tol` branch, the stability scale with
  `kappa_c` (frame, eigenvector estimate, or 1 for an isotropic or real-class block), the receipt and
  `inter_cluster_chords` bookkeeping including the `invperm` after sorting the clusters, the `Inf` chord
  merging at the frozen default with `forced` set only where the default would not have resolved, the
  indefinite basis' Rayleigh-quotient pairing, `_check_partition` (loud on an unclosed or overlapping
  block), and the Sylvester-singular projector (`ArgumentError`, never a silent partial projector).

Style only, not leads: `EdwardsTengForm.consistency_residual` is documented as "`0.0` on the other
routes" but `_edwards_teng_from_normalizer` stores `Inf` when the second (B10) block is at the floor
(line 596); since `det U_yk = kappa_ky = weight` exactly by (M3), that branch needs roundoff to straddle the
floor and was not observed. The map route reports `|tau| >= 2` as `:unstable_spectrum` where the cluster
route would say `:unit_eigenvalue`; the file header documents the choice and the map route runs only on a
resolved frame.

## Unchecked

- `src/elements/linear6d.jl` (`_linear6d_symplectic_error`, `_matrix66_tuple`), the late-bound validator
  behind `_symplectic_defect.row_ratio`: another unit's region; only its outputs were used.
- The consumers of this region in `twiss_dispersion_analysis.jl`, `canonical_separation.jl`,
  `dispersion_routes.jl`, `degenerate_dispersion.jl`: read only at the lines named under Region, to locate
  the one seam measured in LEAD U23-1. Whether other consumers pair `ModeCluster.eigenvalues`/`tunes` with
  `half_members` by position was not audited (grep found `length(c.half_members)` uses only).
- The suite's testsets for the region were not audited (test quality, defect class 13) beyond the one pin
  at `test/runtests.jl:3296` that LEAD U23-1 names.
- The provenance of `_STABILITY_MULTIPLIER` (window `[5.2, 189]`, driver `OUT/fixer/probe_measure.jl`): the
  history cites only its log; not re-measured here.
- Edwards-Teng forms with `u < 0` or `u > 1` (negative `det R`, form 2 `u > 1`) and the `:zero_projection`
  branches were read but not exercised numerically; the manufactured stable maps produced no inadmissible
  form disagreement in 200 trials, and I did not count how many forms were inadmissible.
- Nothing in the region is CUDA-reachable or concurrent; no device-IR or thread checks apply.
