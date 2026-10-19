# U22: analysis/: dispersion routes, canonical separation, degenerate dispersion

## Region

Tree `/cfs/ad/dxu/Library/Julia/Octopus` at commit 24e8683 (read-only).

- `src/analysis/dispersion_routes.jl` lines 1-1470 (whole file)
- `src/analysis/canonical_separation.jl` lines 1-668 (whole file)
- `src/analysis/degenerate_dispersion.jl` lines 1-380 (whole file)

Total 2518 lines, every line read. Hypotheses briefed: (1) equations (D3), (D7)-(D8), (D10)-(D12), (K2), (K8)
against the code, re-deriving (D8) and (K2), the S_4 sign conventions, the new `_dispersion_graph` /
`_longitudinal_factor`; (2) route agreement, the (I1) tolerance derivation, h = 0 and negative h, ambiguity sets
never collapsing; (3) hand-copied constants with a stated derivation.

## Provenance

READ line by line:
- the three region files in full (ranges above);
- `docs/theory/twiss_dispersion.md` 1086-1530 (8.1-8.7: D1-D27, N16 cited), 1595-1920 (9.1-9.4: K1-K14, O1-O5),
  2108-2126 (10.4), 2160-2188 (11.2, (I1)), 2325-2360 ((N4), (N5)), 2432-2546 (13.6: N10-N15), 2640-2672 ((N20)-(N21));
- `validation/twiss_dispersion_identities.jl` 1-281 (whole file);
- the out-of-region helpers the region calls, read to verify the contracts the region relies on:
  `src/analysis/symplectic_linear_algebra.jl` 20-50 (`_symplectic_form`, `_symplectic_inverse`), 100-130
  (`_symplectic_defect`), 255-350 (`_unscale_*` table), 383-445 (`_invariance_residual`, `_graph_invariance_residual`,
  `_perturbation_scale`), 461-466; `src/analysis/Analysis.jl` 85-110 (`DETERMINATION_REASONS`, `AMBIGUITY_KINDS`),
  126-160 (`AmbiguitySet`), 195-300 (`Determined`, accessors); `src/analysis/eigenmodes_4d.jl` 230-262
  (`_mode_label_order`, `_projected_twiss`); `src/analysis/mode_clusters.jl` 252-300 (`ClusterMode`, the
  `ModeCluster` field docs incl. `signed_basis`), 300-430 (structs, `_canonical_spectrum`), 585-588 (`_chord`),
  696-780 (`_recover_modes`), 1063-1075 (`_mode_clusters` signature); `src/analysis/coupled_parameterizations.jl`
  215-300 (`_courant_snyder_B`, `_twiss_from_block`); `src/analysis/twiss_dispersion_analysis.jl` 398-409
  (option metadata), 1100-1215 (`_analysis_6d`), 1325-1365 (physical unscaling incl. the ambiguity-set rebuild),
  1415-1445 (the diagnostics mirror of the (I1) floor); `src/elements/strong_beam.jl` 1355-1400
  (`gaussian_strong_beam_covariance`, the `_dispersion_graph` consumer); `docs/design/twiss_dispersion_analysis.md`
  350-376 (pipeline steps 8-9); `test/runtests.jl` 4355-4410 (stage-4 fixture helpers), 5000-5052 (the E9 testset),
  plus greps for every testset title and every `_kappa_route` / `partition` use in 4420-5400.
- `docs/history/twiss_dispersion_analysis_history.md` (16130 lines) was NOT read; it was grepped for the claims the
  docstrings cite (hits at lines 4177, 4412, 4882, 4955, 13441). `DERIVATION_KAPPA_ROUTE.md` was not located.

EXECUTED (scratch `/cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U22/`):
- `probe1_identities.jl` -> `probe1.log` (P1-P9; the numbers are quoted under Leads and Clean);
- `probe2_partition.jl` -> `probe2.log` (Q1-Q3; a first run died on a wrong public field name
  `longitudinal_selection`, the file was edited to drop that access and re-run; `probe2_partition.jl.bak` is the
  first version);
- three suite testsets by exact title through the stage runner -> `suite_titles.log`: all three RED with
  `UndefVarError` of top-level suite helpers (`_st3_indefinite_6d`, `_st4_dense`, `_ST4_SEED`), the runner artefact the
  brief names; they contribute NO evidence either way.
- Hand re-derivations (paper, recorded in the Clean section): (D8) from (D3); (D12) from (D10)-(D11); (K2) as
  `M_eta^-1 M_zeta^-1`; (D17) via Newton's identities; the `sylvester` sign of (D15), (D20), (D21); the coasting
  identity `M_zr = M_rpz' S_4 M_rr` from `M' S_6 M = S_6`; the cap 3 of (I1) from the triangle inequality.

## Leads

### LEAD U22-1 [Moderate, confidence high] src/analysis/dispersion_routes.jl:1389
Claim: The projector route's three-trace list treats every multi-member cluster as unresolved, so on a RESOLVED definite m = 2 cluster it feeds (D26) two wrong traces and the route reports a garbage graph as `:not_invariant` while the other four routes are `:none`.
Mechanism: `cluster_tau[ci] = _cluster_trace(c)` takes the FIRST eigenvalue's trace for the whole cluster and lines 1396-1402 repeat it `length(c.half_members)` times; lines 1390-1395 then replace it by the trace identity `(tr M - others) / 2`, i.e. the AVERAGE of the two member traces. The comment (1379-1383) assumes "a definite unresolved betatron pair contributes the same trace twice", but `_recover_modes` resolves any multi-member cluster whose internal chord is below `resolution_chord`, and `degenerate_dispersion.jl` 359-361 documents "a resolved definite cluster with m >= 2" as an accepted configuration. It is reachable publicly: `TwissDispersionAnalysis(clusters = partition)` ("fixes the GROUPING only", twiss_dispersion_analysis.jl:398) with the two same-sign betatron pairs in one block. Measured on dense map 5 (tunes 0.515, 1.64, 5.398): default clustering gives 3 singletons; the partition `[[1,6,3,4],[2,5]]` gives a `:definite`, `resolved`, 2-half-member cluster; `_dispersion_routes` then uses gaps `[0.4654, 0.4654]` (both from the averaged trace 0.8011) where the true gaps are `[0.474, 1.405]`; the formed `P_s` has `||P^2 - P|| = 25.6` and `||P_s - cluster projector|| = 8.33`; the projector route is `:not_invariant` with normalized residual 1.05; eigenplane, polynomial, Newton, fixed point are all `:none` (residuals 1.4e-15, 1.5e-16, 4.0e-17, 4.7e-15). Through `analyze(TwissDispersionAnalysis(clusters=part), M)` the same statuses appear and `degradations` says nothing about the route disagreement (only "another branch" Newton/fixed-point details are degraded, lines 1192-1196 of the analysis). No testset exercises `_dispersion_routes` on a resolved multi-member cluster (grep of test/runtests.jl 4420-5400 for `partition` or `resolution_chord`: no hit; the row-3 testset at 4666 uses an UNRESOLVED equal-tune pair, where the repetition is right). A fix would build `taus` from each resolved mode's `2 cos(tune)` and keep the cluster trace / identity for unresolved clusters only; and the selected cluster's own doubled trace (gap 0 -> `:singular_coefficient`) is the same defect's second symptom when the synchrotron pair shares a resolved cluster (not demonstrated: merging the synchrotron pair with a betatron pair made the cluster `:indefinite` on dense map 5, probe2 Q1).
Repro: `cd /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U22 && julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 probe1_identities.jl | sed -n '/=== P6/,/=== P7/p'` -> `route projector status not_invariant residual 1.05e+00`, `projector gaps (singular_values field) = [0.46543..., 0.46543...]; true gaps |tau_s - tau_k| = [0.47400..., 1.40487...]`, the four other routes `none`, and the public `analyze` line with `(:projector, :not_invariant)`.

### LEAD U22-2 [Minor, confidence high] src/analysis/twiss_dispersion_analysis.jl:1157 (OUT OF REGION: cross-file seam, consumer of this region's `DispersionRoutes`)
Claim: The heuristic-selection text quotes the z-area of the wrong mode whenever a resolved cluster has more than one member, because it indexes the resolved-mode-ordered `weights` by the CLUSTER index `routes.longitudinal_cluster`.
Mechanism: `weights = labels.signed_areas[:, 3]` is ordered like `resolved_modes` (cluster order, modes within), while `routes.longitudinal_cluster` is a position in `clusters.clusters`; the two coincide only when every cluster is a singleton. On the partition of U22-1 the resolved-mode order is `(cluster 1: index 1, index 3), (cluster 2: index 2)`, the z-areas are `[-0.0135, -0.0056, 1.0191]`, the selected mode is the third (h = 1.0191 = kappa_sz by (K12)), yet the detail says "selected canonical eigenvalue 2 (cluster 2; signed z-area -0.00558...)": a betatron mode's z-area. The `weights` field of the selection NamedTuple still carries the full vector, so the data is not lost; only the text and anyone parsing it are wrong. Noted as a seam for the auditor; this unit did not read the rest of that file.
Repro: `cd /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U22 && julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 probe2_partition.jl | sed -n '/=== Q2/,/=== Q3/p'` -> `signed z-areas per resolved mode = [-0.01349..., -0.00558..., 1.01908...]; labels.longitudinal (position) = 3; ... report.longitudinal_cluster = 2` and `the selected mode's z-area = 1.019081; z-area at position longitudinal_cluster = -0.005582`; the public text is the `degradations` line of probe1 P6 ("signed z-area -0.0055818...").

### LEAD U22-3 [Minor, confidence high] src/analysis/dispersion_routes.jl:1346
Claim: On a coasting map `_dispersion_routes` accepts any `longitudinal` value silently, although its docstring (1315-1317) promises an `ArgumentError` for "a bad `longitudinal`".
Mechanism: the coasting branch returns at 1346-1356 before `_longitudinal_candidate` (1357), which is where the `1 <= idx <= length(eigenvalues)` check lives (1245-1248); so `longitudinal = 99`, `0`, `-3`, `7` all return a normal report with `longitudinal = 0`, and a valid `1` is ignored the same way. Reach: kernel-level only. Publicly the constructor refuses `<= 0` (twiss_dispersion_analysis.jl:323) and `_analysis_6d` refuses `> 6` (1107-1109) before calling, and the option is declared "Inactive on 4x4 input and on a coasting map" (401-405), so `analyze(TwissDispersionAnalysis(longitudinal_mode=3), coasting M)` is accepted by design (probe2 Q3). The defect is the kernel contract: a documented refusal that does not execute (class 1), the same shape as a check behind a false condition.
Repro: `cd /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U22 && julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 probe1_identities.jl | grep 'longitudinal = '` -> four lines `accepted silently: coasting.holds = true, longitudinal = 0` for 99, 0, -3, 7; `_dispersion_routes(dense M, cl; longitudinal = 99): threw ArgumentError` for the bunched control.

### LEAD U22-4 [Minor, confidence med] src/analysis/canonical_separation.jl:303
Claim: `_dispersion_graph`, the one conversion the user-facing covariance builder `gaussian_strong_beam_covariance` goes through, refuses only an exactly zero `h` and returns an arbitrarily large slope `eta / h` silently for any `h` within roundoff of zero.
Mechanism: `iszero(h)` is the only guard (303); the analysis side judges the same quantity against a scaled floor (`_route_from_graph`, `_ISOTROPY_MULTIPLIER * rho_M1 * max(1, ||D||_2^2)`, dispersion_routes.jl:825, 840) and the Ohmi factor against `_OHMI_POSITIVITY_MULTIPLIER * eps * max(1, ||zeta|| ||eta||)` (canonical_separation.jl:525), but the consumer boundary has neither: with `zeta = e_x`, `eta = (1 - 2e-16) e_px` the call returns `h = 2.2e-16` and a slope of `4.5e15` (1e12 at `1 - 1e-12`, 1e8 at `1 - 1e-8`), which `gaussian_strong_beam_covariance` (strong_beam.jl:1391-1396) folds into a covariance without comment. Low practical likelihood (a user-supplied pair with `zeta' S_4 eta ~ 1` is unphysical) and no `rho_M1` exists at that boundary, so a floor would have to be `eps`-based like the Ohmi one; reported because the docstring says "`h = 0` is refused by name" and the analysis-side kernels are floored. Out-of-hypothesis beyond "h = 0 handling".
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus -e 'using Octopus; g = Octopus._dispersion_graph([1.0,0,0,0], [0.0, 1 - 2e-16, 0, 0]); println(g.h, " ", maximum(abs, g.graph[:, 2]))'` -> `2.220446049250313e-16 4.503599627370496e15` with no error; also probe1 P7.

### LEAD U22-5 [Minor, confidence high] src/analysis/dispersion_routes.jl:58
Claim: The `_GRAPH_SINGULARITY_MULTIPLIER` docstring's "the multiplier 64 sits inside the gap by twelve decades either way" is false on the rejected side: 64 / 0.26 is 2.4 decades.
Mechanism: the docstring's own numbers are accepted extreme 3.2e14 and rejected extreme 0.26; `log10(3.2e14 / 64) = 12.7` but `log10(64 / 0.26) = 2.39`. The constant is still inside the one-tenth / ten window (`[2.6, 3.2e13]`), so no acceptance changes; this is a documentation claim with no harness behind it (class 14), the kind the next reader copies.
Repro: `julia -e 'println(log10(64 / 0.26), " ", log10(3.2e14 / 64))'` -> `2.391... 12.698...`.

### LEAD U22-6 [Minor, confidence med] src/analysis/degenerate_dispersion.jl:61
Claim: The `_CLUSTER_FRAME_N4_MULTIPLIER` docstring states the window's upper edge without the factor ten its own rule prescribes.
Mechanism: the docstring converts the accepted side with the rule (0.043 x 64 = 2.75, "lower edge is 27" = ten times) but quotes "window upper edge 7.5e8 for the smallest rejected" where the smallest rejected ratio is 1.2e7 x 64 = 7.7e8 and the one-tenth rule makes the edge 7.7e7. 64 is inside either way; the inconsistency is in the stated derivation (hypothesis 3), not the constant.
Repro: `julia -e 'println(0.043 * 64 * 10, " ", 1.2e7 * 64, " ", 1.2e7 * 64 / 10)'` -> `27.52 7.68e8 7.68e7`; compare with the text at degenerate_dispersion.jl:58-61.

### LEAD U22-7 [Minor, confidence low] src/analysis/dispersion_routes.jl:849
Claim: The branch-check floor of the iterative routes, `inv_floor * max(1, ||M||_F)`, carries a second factor `max(1, ||M||_F)` with no stated derivation, unlike every other threshold in the file.
Mechanism: `inv_floor = c_inv eps kappa_route` already contains `max(1, ||M||_F)` through `_kappa_route` (137-148), so the trace residual `tr(M_lr D + M_ll) - tau_s`, whose roundoff is of order `eps ||M|| (1 + ||D||)`, is judged against a floor that grows as `||M||_F^2 gamma`. Measured on dense map 0: trace residual 2.0e-15, (I1) floor 7.5e-13, branch floor 1.9e-12 against mode separations 0.49 and 1.35, so the floor cannot admit a wrong branch at this scale; the lead is the missing derivation (the docstring at 802-803 restates the formula, it does not derive it), which matters only for maps with `||M||_F gamma` large enough that `256 eps ||M||^2 gamma` approaches a trace separation. If all this is is style, it is style.
Repro: `cd /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U22 && julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 probe1_identities.jl | sed -n '/=== P9/,$p'` -> `trace residual 1.998e-15, (I1) floor 7.515e-13, branch floor ... 1.892e-12 (||M||_F = 2.518); |tau_1 - tau_s| = 0.493, |tau_2 - tau_s| = 1.348`.

### LEAD U22-8 [Minor, confidence low] src/analysis/dispersion_routes.jl:456
Claim: `DispersionRoutes.tau_s` is documented as "`2 cos mu_s`" but for a blocked longitudinal cluster it is `Re(rho + 1 / rho)` of a real-class or Krein-quartet eigenvalue, reported as a UNIQUE `Determined`.
Mechanism: line 1420 fills `tau_s` with `Determined(_cluster_trace(c_long))` on the non-definite branch; for a hyperbolic pair that is `rho + 1/rho` (2.5 on the E9 fixture, pinned by the testset at test/runtests.jl 5031) and for a Krein quartet it is a number the docstring of `_cluster_trace` (1210-1214) itself says annihilates no mode. The number is not wrong, the vocabulary is: theory 11.2 asks that invalid quantities not be replaced by plausible numbers, and `2 cos mu_s` is the documented meaning. A docstring fix ("the candidate cluster's trace, `2 cos mu_s` for an elliptic mode") would close it; pinned behaviour, so not a code change on its own.
Repro: `grep -n 'tau_s. (.2 cos mu_s.)' /cfs/ad/dxu/Library/Julia/Octopus/src/analysis/dispersion_routes.jl` -> line 456; the E9 testset's `abs(_st4_val(rh.rep.tau_s) - 2.5) <= 64eps()` at test/runtests.jl:5031 shows the value for the hyperbolic pair.

## Clean

Each item names what was compared and the measured number (probe1.log / probe2.log unless stated).

- (D3) and its displayed block form: `_dispersion_transformation` against the block `[I + zeta eta' S4, zeta, eta; eta' S4, 1, 0; -zeta' S4, 0, h]` and against an independent test-local product, worst 1.28e-15 over 50 random triples including h < 0 and the exact h = 0 triple `zeta = e_x, eta = e_px`. The S_4 sign convention `(S_4 a)' = -a' S_4` is honoured: rows `eta' S_4` and `-zeta' S_4` are stored as the columns `S_4' eta`, `-S_4' zeta` (canonical_separation.jl 255-256), and the product reproduces (D3) by hand: row 6 of `M_zeta M_eta` is `(-zeta' S_4, 0, 1 - zeta' S_4 eta)`.
- (K2) re-derived as `M_eta^-1 M_zeta^-1` with `M_eta^-1 = [I, 0, -eta; -eta' S_4, 1, 0; 0, 0, 1]` (the (5,6) entry `eta' S_4 eta` vanishes by antisymmetry) and matched entry by entry with `_dispersion_transformation_inverse` (315-327); numerically `||M_cal M_cal^-1 - I||` worst 4.52e-15 over 50 triples and exactly 0.0 at h = 0 ("no 1/h", as documented). (K1) symplecticity worst 4.09e-15 for every sign of h.
- (D8) re-derived from (D3): `h = 1 - zeta' S_4 eta` with `eta = h D_2` gives `h (1 + D_1' S_4 D_2) = 1`; `_graph_to_dispersion` (506-514) and `_longitudinal_factor` / `_dispersion_graph` (279-307) implement it; (D7)-(D8) round trip relative error 9.17e-16; `_dispersion_graph` agrees with `_dispersion_to_graph` to 0 on the same inputs.
- (D11)-(D12) re-derived: with `U_ls = [Re u_5, -Im u_5; Re u_6, -Im u_6]`, `det U_ls = -Im(conj(u_5) u_6)`; the (D10) inverse gives `zeta_a = -Im(conj(u_a) u_6) / h` and `eta_a = -Im(conj(u_5) u_a)`, matching dispersion_routes.jl 899, 906-907. Numerically on 20 dense maps with an (E3)-normalized longitudinal eigenvector: `U_s' S_6 U_s = S_2` to 4.71e-16, `D' S_4 D = (1-h)/h S_2` to 4.12e-16, (D12) versus (D8) of the (D10) graph: zeta 2.78e-17, eta 5.55e-17, h 3.33e-16 (both the complex-product h and `det U_ls`).
- (D17) re-derived via Newton's identities (`e_2 = (t1^2 - t2)/2 - 3`, `e_3 = (t1^3 - 3 t1 t2 + 2 t3)/6 - 2 t1`) and the companion matrix orientation; roots versus `2 cos mu_j` worst 3.77e-15 on 20 dense maps.
- (D15), (D20), (D21) against Julia's `sylvester(A, B, C)` solving `AX + XB + C = 0`: (D15) `sylvester(M_rr, -M_ll, M_rl)`; (D20) `sylvester(M_rr, -M_ll, M_rl - D M_lr D)`; the Newton correction `(M_rr - D M_lr) delta - delta (M_ll + M_lr D) = -F(D)` expanded by hand from (D21) with `D_{n+1} = D + delta` (the two `D M_lr D` terms collect into `-F(D)`), matching line 1107.
- (D23)-(D25): the four structure residuals cover every constrained entry of (D23); the symplectic-consistency identity `M_zr = M_rpz' S_4 M_rr` re-derived from the (i in 1:4, j = 6) block of `M' S_6 M = S_6`; on a symplectic coasting fixture the code's residual is 6.80e-17 while the opposite-sign form is 0.335, the recovered eta differs from the built one by 3.1e-14, the shear equals the built 0.3.
- (K7), (K8), (K12)-(K14), (O2)-(O5): operator placement checked line by line (canonical_separation.jl 368-379, 445-461, 500-501, 533-553); (O3) inverse 7.13e-16, `M_O` symplecticity 7.13e-16, (O1) off-diagonal 1.15e-15, (O5) computed chart change against its displayed form 7.69e-16, (O5) block symplecticity 9.43e-16, (O4) 0, over 20 random positive-h triples.
- `_kappa_route`'s hand-copied normalizer: the bracket `max(1, ||D||_F^2 / N)` recomputed with `N = raw / normalized` from `_graph_invariance_residual` agrees with the copy to relative difference 0.0 on 20 dense maps; the suite pins the helper's algebra at test/runtests.jl 4480-4507. The cap `_INVARIANCE_RESIDUAL_CAP = 3` follows from `||A + M_rl - B|| <= ||A|| + ||M_rl|| + ||B|| <= 3N`.
- The chain on 20 dense maps: 100 of 100 route results `:none`; largest route disagreement (inf-norm of zeta, eta, h) 1.23e-14; (K4) off-diagonal 3.17e-15; U_6 reconstruction 1.64e-15. `ProjectedOptics6D.reconstruction` is measured against `M_cal Mbar M_cal^-1` rather than the caller's M (canonical_separation.jl 443): the difference to the direct residual is 1.0e-16 on the dense maps and 3% (7.87e-9 versus 8.14e-9) at `cond(M_cal) = 4.7e4`, `h = -201`, so the shortcut is not a lead.
- Candidate rule (dossier E9) on the N15 indefinite fixture `diag(R(0.73), R(1.41), R(-0.73))`: the `signed_basis` columns of an indefinite cluster are already oriented (mode_clusters.jl 289-291: "each normalized to -2i after conjugating the negative-sign ones"), so the summed signed z-area is the cluster's true z-content: +1.000000 for the indefinite x-z cluster (Krein signs [-1, 1]), -0.000000 for the resolved y singleton; `_longitudinal_candidate` returns the indefinite cluster, as the E9 testset pins.
- h = 0 and negative h: exact zero is an `ArgumentError` in all three kernels (`_graph_to_dispersion`, `_dispersion_to_graph`, `_dispersion_graph`); the eigenplane route floors `sigma_min(U_ls)`, the polynomial route floors `sigma_min(A_s)` (N16), the projector route floors `|h|`; negative h passes every route and the separation ((K1) holds for every h; `k7_difference` is guarded by `hh != 0`), and the Ohmi factor refuses it as `:form_inadmissible` with the positive-root detail. The prescribed-h testset (4617) covers h in (-2, -1, -0.3, 0.05, 0.5, 1, 2) by title (not run here).
- Ambiguity sets never collapse: `_dispersion_routes` returns `Determined{Vector{Float64}}(set, :cluster_unresolved, ...)` (1445); `_canonical_separation(M, routes)` refuses any non-unique member of the triple with the reason (592-595); the analysis rebuilds the set after unscaling center and every factor column with `shape = F F'` (twiss_dispersion_analysis.jl 1343-1346); a repo grep finds no other consumer of `.center` and the identity contract reads it through `dispersion_interval` (twiss_dispersion_identity.jl:475). (N11) center `P[1:4, 6]/2` and shape `(G_55 G_rr - G_r5 G_5r)/4`, the `2m - 1` factor columns and the (N5) forms `P_c = -Im(U U') S`, `G_c = Re(U U')` match the theory text.
- Positional constructors: all eight structs' construction sites were matched against their field order (`DispersionRoute` 16 fields, `CoastingStructure` 12, `ModeLabels6D` 10, `DispersionRoutes` 16, `CanonicalSeparation` 18, `ProjectedOptics6D` 16, `MatchedCovariance6D` 9, `OhmiFactorization` 9); the `common[2:end]...` splice in `_route_from_graph` lands on fields 8-16.
- Window arithmetic of the PROVISIONAL constants' docstrings recomputed from their own numbers: c_coef `[3.76, 1.55e8]`; c_inv's H15 value `max(8, 2^ceil(log2(53.4))) = 64`; c_coast margin `2.2e8 / 64 = 3.4e6`; c_sep `[10.3, 5.14e3]`; c_triple `[9.14, 450]`; c_ell `[28.3, 2.0e8]` (64 is 2.26x the edge); c_ohmi `[44.0, 2.25e13]` (1.45x); c_exact `[5.87, 68.1]`; c_psd lower edge 2.7. All consistent except the two instances in U22-5 and U22-6. The empty rejected side of the c_inv window (`_ROUTE_INVARIANCE_MULTIPLIER` 168-184) is a documented, carried owner decision, not re-opened here.
- `_mode_labels_6d`: (K12) signed areas `-Im(conj(u_{2a-1}) u_{2a})`, the tie rule and the explicit-selection exemption match the docstring; `sortperm(rev=true)` is stable, so a declared z-area tie keeps the given order as documented.
- The trace-identity substitution (1390-1395) is algebraically right for the case it names (one UNRESOLVED multiple cluster, three half members in all): `tr M = tau_1 + tau_2 + tau_s` with the double trace counted twice; U22-1 is about the case it does not name.

## Unchecked

- Suite testsets could not be executed through the stage runner (runner artefact: `UndefVarError` of the suite's
  top-level fixture helpers in all three titles tried); every claim above rests on the probes and on reading, not on
  the suite's pins.
- `docs/history/twiss_dispersion_analysis_history.md` was only grepped; the kappa_route derivation
  (`DERIVATION_KAPPA_ROUTE.md`, cited at dispersion_routes.jl:119) was not located or read, so the (I1) floor's
  `beta(D)` bound is accepted as recorded, not re-derived (hypothesis 2's "tolerance derivation" is therefore
  checked only for the normalizer copy and the cap, not for the first-order error analysis).
- Not probed: the Newton and fixed-point stall and cap paths (`_MAX_HALVINGS`, `_FIXED_POINT_MAX_ITERATIONS`) on a
  crab fixture; the S2b-1 cap-refusal fixture; the Krein-quartet `:unstable` trace path (U5-2-3, read only); the
  `h_alternative = Determined(h8)` division in `_projector_route` (1017), which could yield `Inf` only for an exactly
  isotropic garbage graph (judged unreachable on a formed projector and left as an observation).
- `_matched_covariance_6d` (K10), (K14) and `_full_normalizer_6d` (K13) were read, not measured; the identity
  contract covers them by title (`r_k13_*`, `r_k14_*` rows, not run here).
- The P8 extreme fixture (`||zeta|| ||eta|| ~ 2e4`, `h = -20199`) was classified `:unit_eigenvalue` by
  `_mode_clusters` (tau_real of 9.7e7): mode_clusters.jl behaviour on an extreme map, out of this region, not pursued.
- The three region files were read in full; nothing in them is unread.
