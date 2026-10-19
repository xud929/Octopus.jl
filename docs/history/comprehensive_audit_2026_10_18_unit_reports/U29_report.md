# U29: test/runtests.jl lines 3243-6447 (Twiss analysis stages 3 A1/B, 4a, 4b Part A)

## Region

`test/runtests.jl` lines 3243-6447 (3205 lines, commit 24e8683), read line by line in
full. Content: 48 `@testset`s plus three top-level helper blocks:

- 3243-3712: Mode clusters (stage 3 Part A1), 9 testsets.
- 3713-3738: Part B helper block (`_AMB_*`, `_amb_*`).
- 3740-4332: Ambiguity set (stage 3 Part B), 7 testsets.
- 4334-4418: stage 4a fixture library (`_st4_*`, `_st4_chain`).
- 4420-5395: Dispersion routes incl. four nested stage-9 testsets, 14 top-level testsets.
- 5397-5978: Canonical separation, the stage 4a chain, the vocabulary pins, 13 testsets.
- 5980-6191: stage 4b helper block (`_st4b_a_*` fixtures, `_st4b_b_fake_run` scratch verb,
  `_st4b_b_block_errors`).
- 6193-6446: Analysis object, `_with_longitudinal_mode`, the identities-script dry run, the dense
  6D map through `analyze`, 4 testsets.

No `_lane_gate` and no `CUDA_TESTS_ACTIVE` gate touches the region (the only `_lane_gate(`
occurrences are its definition at line 23 and sites from line 13948 on), so all 48 testsets
run in both lanes and no GPU gate exists here to report as skipped.

## Provenance

READ line by line: runtests.jl 3243-6447 (the whole region), plus context outside the region
needed to judge it: 2674-2960 and 2960-3242 (the `_st3_*` builders and `_mc_*` aliases the
region calls; every helper the region uses is defined before line 3243 or at line 1152
(`_st6_with_longitudinal`)); src/analysis/mode_clusters.jl 676-692, 760-790, 945-1000,
1066-1071, 1290-1320; src/analysis/degenerate_dispersion.jl 100-135, 285-345;
src/analysis/canonical_separation.jl 263-280, 452, 499; src/analysis/dispersion_routes.jl
642-665; src/analysis/twiss_dispersion_analysis.jl 1-8, 1405;
validation/twiss_dispersion_identities.jl 92-100, 255-262; docs/design/testing_lanes.md
sections 3-4; docs/comprehensive_audit.md Phase 9; the headers of the previous audit's
U17-U20 reports (they cover runtests.jl at 7de4d81, 2026-08-05, lines 1-8759: the Twiss
blocks of this region did not exist then, so no previous lead touches this region).

EXECUTED (scratch `/cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U29/`):

- `probe1.jl` -> `probe1.log`: the Krein-quartet fixture of line 3456 gives 1 cluster
  (`:unstable`); its minimum unit-circle departure is 9.999000100e-5, `|md - 1e-4| =
  9.998999861e-9` against the tolerance 1e-8 (margin 1.0001e-12); `svdvals(I - Msing_rr)[end]
  = 0.0` exactly and `Msing_rr == blockdiag` exactly (line 4845); the DBA + RF + thin crab maps
  of lines 5126-5143 have `tr(M[5:6, 5:6]) = 2.020311959` (k = 0.05) and `2.197523156`
  (k = 0.3), sub-block eigenvalue moduli 1.0176 and 1.1012; `U * U'` for a complex 6x2 `U`
  is exactly Hermitian in 200/200 draws (herk dispatch) while `U * Matrix(U')` (gemm) is not.
- `probe2.jl` -> `probe2.log`: the crab ladder of lines 3584-3611 at the default chord 1e-3:
  `ncoll = 2` with `qcoll` from 3.7e-13 (eps = 1e-1) rising to 2.82e-4 (eps = 1e-10), `ncoll = 1`
  with `qcoll = 2.82e-3` at eps = 1e-11; the receipt has exactly one `merged` entry in that
  last row and none elsewhere; in every two-cluster row the maximal inter-cluster chord is the
  x-z pair `[1, 6]-[2, 5]` (the y spectator never carries it).
- `probe3.jl` -> `probe3.log`: with `Main.IDENT_DRY_RUN` defined (as the testset at line 6302
  leaves it), `include("validation/twiss_dispersion_identities.jl")` prints nothing at all: no
  TW-IDENT rows and no skip line.

No repository file was modified; no git command was run.

## Leads

### LEAD U29-1 [Minor, confidence high] test/runtests.jl:5130
Claim: `@test abs(tr(M[5:6, 5:6])) < 2 + 0.3` bounds a quantity that is not a stability witness and the bound was widened to admit the data (measured 2.0203 at k = 0.05, 2.1975 at k = 0.3), so the line asserts nothing physical while reading like an "elliptic longitudinal plane" check.
Mechanism: in the coupled one-turn map the (z, pz) sub-block is not the synchrotron mode's block; its trace exceeds 2 for both fixtures (sub-block eigenvalue moduli 1.018 and 1.101) while the 6D map is stable (line 5132 `:all_resolved` carries the actual stability content). A bound of 2.3 passes for every trace in (-2.3, 2.3) and fails spuriously once the crab strength grows a little (the k = 0.3 value sits 0.10 below it); the comment above it ("a FODO ... parabolic with any RF") describes a different quantity. Defect class 8 (a tolerance widened to fit a floor), hypothesis 3.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U29/probe1.jl` prints `k = 0.05: tr(M_ll) = 2.020311959379251` and `k = 0.3: tr(M_ll) = 2.197523156141248`; `grep -n 'tr(M\[5:6, 5:6\])) < 2 + 0.3' test/runtests.jl` locates the assertion.

### LEAD U29-2 [Minor, confidence high] test/runtests.jl:3460
Claim: `@test !any(rq.real_class) && 1 <= length(rq.clusters) <= 2` hedges the cluster count of the Krein-quartet fixture while the comment on the same line asserts that the off-circle pairs merge; the solver returns one cluster, and a regression that split the quartet into two `:unstable` clusters would pass.
Mechanism: the test accepts both outcomes of the very decision the comment claims ("Krein-neutral (kappa = Inf), so they merge"); with `_chord(Inf, rho, g) = 2 > merge_chord` the merge is deterministic, so the hedge buys nothing and removes the only assertion on the quartet's grouping. Hypothesis 2 (a test that cannot fail on its defect).
Repro: `probe1.jl` (path above) prints `n_clusters = 1  classifications = [:unstable]`; `grep -n '1 <= length(rq.clusters) <= 2' test/runtests.jl`.

### LEAD U29-3 [Minor, confidence high] test/runtests.jl:3462
Claim: `abs(minimum(c.unit_circle_departures) - 1e-4) <= 1e-8` passes with a margin of 1.0e-12 because the tolerance equals the exact second-order term of the fixture (the 1/(1 + 1e-4) member departs by 9.999e-5, i.e. 1e-4 - 9.999e-9), not any roundoff budget.
Mechanism: the quartet has members at modulus 1 + 1e-4 and 1/(1 + 1e-4); `minimum` picks the latter, whose distance from 1e-4 is (1e-4)^2/(1 + 1e-4) = 9.999e-9; the 1e-8 tolerance therefore leaves 1.0e-12 for eigenvalue roundoff and for any legitimate change of the departure definition. The pin rests on a coincidence of the fixture's arithmetic with the tolerance (defect class 8); `abs(maximum(...) - 1e-4) <= 1e-12` or a pin on 1 - 1/(1 + 1e-4) would say what is meant.
Repro: `probe1.jl` prints `min departure = 9.999000100013866e-5  |md - 1e-4| = 9.998999861342913e-9  tolerance 1e-8, margin = 1.0001386570876816e-12`.

### LEAD U29-4 [Minor, confidence high] test/runtests.jl:3611
Claim: `@test all(e -> ncoll[e] == (qcoll[e] > Octopus._DEFAULT_RESOLUTION_CHORD ? 1 : 2), keys(ncoll))` is implied by the solver's own merge rule and cannot fail independently of it: both the decision (`ncoll`) and the deciding number (`qcoll`) are read from the same report.
Mechanism: line 3592 takes `qcoll` from the receipt entry whose `merged` flag the solver set by `do_merge = r.chord > merge_chord` (src/analysis/mode_clusters.jl, `_resolve_clusters` loop, merge_chord = `_DEFAULT_RESOLUTION_CHORD` here) in the one-cluster branch, and from the chord matrix the solver declined to merge on in the two-cluster branch; so `qcoll > default` iff a merge happened iff `ncoll == 1`, by construction. The independent content of the ladder is on lines 3598 (max chord below the default when two singletons), 3612 (both branches exercised) and 3614 (q monotone down the ladder). Hypothesis 2 (circular: consults the artifact it validates).
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U29/probe2.jl` prints eleven rows; `merged entries` is 1 exactly in the one row where `qcoll > default: true` (eps = 1e-11, qcoll 2.82e-3) and 0 in every other.

### LEAD U29-5 [Minor, confidence high] test/runtests.jl:3756
Claim: `@test norm(cf.G - determined_value(cf.cluster.covariance)) == 0` compares a value with itself: `_st3_cluster` (line 3006) defines `G = determined_value(c.covariance)`.
Mechanism: the helper copies the cluster's covariance into the field `G`; the comment "G IS the cluster covariance" describes the helper, not a property of the source, so the test passes for any covariance the solver produces (hypothesis 2, tautology). The agreement witness the testset wants is line 3752 (`cf_probe.G` from the design probe's builder against `cf.G`), which does carry content.
Repro: `sed -n 3006p test/runtests.jl` shows `G=has_frame ? determined_value(c.covariance) : nothing`; `sed -n 3756p test/runtests.jl` the assertion.

### LEAD U29-6 [Minor, confidence med] test/runtests.jl:4453
Claim: the per-route (I1)-floor assertions at 4453 and 5254 re-evaluate the kernel's own acceptance inequality (`_ROUTE_INVARIANCE_MULTIPLIER * eps() * _kappa_route(...)`) and so cannot fail for a route whose status is `:none` (asserted on the preceding line); they pin nothing beyond what the status already says.
Mechanism: `_route_from_graph` returns `:none` iff the normalized (I1) residual is at or below exactly this floor computed with the route's graph; the test repeats the inequality with the exact graph `f.D` (whose agreement with the route's graph is already bounded at 2048 eps kappa). The comment at 4450-4452 concedes "a :none status already implies this bound". A moved multiplier or a changed `_kappa_route` moves both sides together, so neither the test nor the kernel can see such a change here; the independent coverage of the floor lives in the edge test at 4557-4558 and the garbage-graph test at 5267-5275, which is why this is Minor.
Repro: `grep -n '_ROUTE_INVARIANCE_MULTIPLIER \* eps() \* Octopus._kappa_route' test/runtests.jl` lists the sites (4453, 4958, 5254, 5268 at 24e8683); compare with the kernel's floor in `grep -n '_ROUTE_INVARIANCE_MULTIPLIER' src/analysis/dispersion_routes.jl`.

### LEAD U29-7 [Minor, confidence high] test/runtests.jl:6212
Claim: "every export of the file is documented" iterates a hand-typed list of nine names rather than the file's `export` statement, so a tenth export added to src/analysis/twiss_dispersion_analysis.jl without a docstring would pass.
Mechanism: hand-copied knowledge without a coverage tripwire (defect class 2; the AGENTS "derive, don't hand-copy" invariant), in a file whose sibling checks already derive their lists from the method tables (3050-3065, 5931-5943). Today the list equals the export line (`TwissDispersionAnalysis, TwissDispersionResult, OpticsAnalysisError, NormalMode, ANALYSIS_STATUSES, analyze, analysis_option_schema, matched_covariance, normal_mode`), so no current export is missed; the defect is the absence of the tie.
Repro: `sed -n 1,2p src/analysis/twiss_dispersion_analysis.jl` against `sed -n 6212,6213p test/runtests.jl` shows the same nine names and no derivation; adding an undocumented name to the export line would leave the testset green.

### LEAD U29-8 [Minor, confidence med] test/runtests.jl:6302 (cross-file seam: validation/twiss_dispersion_identities.jl:99 and :259)
Claim: the dry-run testset defines `const IDENT_DRY_RUN = true` in `Main` for the rest of the Julia process, after which any `include` of validation/twiss_dispersion_identities.jl runs no contract and prints no skip line.
Mechanism: the script reads `isdefined(Main, :IDENT_DRY_RUN)` at include time (line 99) and its `if !IDENT_DRY_RUN` block (line 259) has no else branch and no message; a `const` cannot be removed. Inside `Pkg.test` nothing includes the script a second time, but in the stage runner or a REPL session that ran this testset the TW-IDENT record run becomes a silent no-op: an unrun check without a visible skip (defect class 1; the "a skip is loud, always" rule of docs/design/testing_lanes.md section 4). The fix belongs to the script (print a loud `IDENT_DRY_RUN` banner) or to the test (a flag the script reads from the `dry` module instead of `Main`); the auditor owns the seam.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U29/probe3.jl` prints only `--- include begins` and `--- include ended; IDENT_DRY_RUN = true` (no TW-IDENT, no skip line); `grep -n IDENT_DRY_RUN validation/twiss_dispersion_identities.jl test/runtests.jl`.

Style-only observations (not leads; listed so the reader knows they were seen): 4186 the
single-iteration `for (phase, eta_exp) in ((mu + ep, fam.eta_plus),)` binds `eta_exp` and never
uses it (the block tests `r.eta` containment, not the fixture's eta); 4929 `max(1, 1.0)` is a
constant 1.0; 4826 `c.residuals.z_column == 0 ||` is redundant with `<= c.tolerance`; 5969 the
`:([a-z_]+)` sweep counts reason symbols that appear only in comments as "used"; 6196 pins the
source text of a `const` line already pinned at runtime on 6194; 6425 `string(round(...;
digits=6))[1:6]` throws (loudly) if the tune ever prints in fewer than six characters.

## Clean

Checked and found sound, with what was compared:

- Hypothesis 1 (checks that never execute). No lane or CUDA gate encloses the region (the
  `_lane_gate(` sites are at line 23 and from 13948 on); every conditional that can bypass
  assertions is either counted or preceded by a loud test: 3338 (`m == 3 &&`, 11 fixtures run
  it), 3594-3605 (both branches asserted exercised at 3612), 3954/3959 `continue` (counted,
  `n_modes >= 100` at 3971), 4439-4444 `continue` (counted, `<= 8` at 4479), 4588-4590 `while`
  (followed by `is_determined` tests), 4602/4607 nested `if`s (guarded by `@test` on 4601, 4604,
  4606), 4643-4649 if/else (both branches assert), 4651, 5140, 5480 one-sided `&&` tests on named
  fixtures, 5291/5295 `continue` after `@test`, 5300 (`n_unconverged >= 3` at 5314),
  5319/5322 (`n_analyses == 2 * c.dense_maps` at 5329), 6302 `isdefined` guard (see U29-8).
  No testset body sits behind a false condition; no `@test_skip`/`@test_broken` in the region.
- Hypothesis 3, bitwise pins: each `==` between two routes was traced to the source and found
  structural (same expression on the same object), not rounding coincidence: 3294 and 3297
  (`frame_residuals.eigenvector` is `_column_eigenvector_residual(M, U, evals)` = the max of the
  very `_invariance_residual` calls the modes store; `ClusterMode.eigenvalue`/`tune` and the
  cluster's `eigenvalues`/`tunes` are the same `theta_out` and the same `mod(-angle, 2pi)`,
  mode_clusters.jl 775, 1296-1307); 3700/3706 (receipt `chord` and `inter_cluster_chords[a, b]`
  are one `r.chord`, mode_clusters.jl 965-985); 3509/3711 (`tau_real` formula identical to
  mode_clusters.jl 1069-1071); 3779/3856 (the U-method forms `P_c = -imag(U*U')*S`,
  `G_c = (real(U*U') + ')/2` and calls the (P, G) method, degenerate_dispersion.jl 296-302, and
  the cluster covariance is formed the same way in `_group_quantities`, mode_clusters.jl
  683-687; `U*U'` is exactly Hermitian through herk, 200/200 in probe1, so the symmetrization is
  an identity and the equality is structural); 4016 (tolerance expression identical to
  degenerate_dispersion.jl 120); 5403 and 5413 (`h` and `M_cal` identical to
  canonical_separation.jl 280 and 269); 5587 (`row_sums = vec(sum(kappa; dims=2))`,
  canonical_separation.jl 452 and dispersion_routes.jl 642); 5622 (bunch length is the same
  `sum(eps3[j] * covariances[j][5, 5] for j in 1:3)`, canonical_separation.jl 499); 6412 (the
  closure tolerance formula at twiss_dispersion_analysis.jl 1405). 4845 `svdvals(...)[end] == 0`
  is exact on this fixture (`Mrr == blockdiag` bitwise, probe1) and is a fixture precondition,
  not a solver pin.
- Hypothesis 3, widened tolerances: the aggregate worst-ratio pins at 3306-3311 (psum 8 vs
  0.46/0.60, pn5 8 vs 0.48/0.61, n5sum 128 vs 10.7/7.0, closes 64 vs 6.3, kappa 1024 vs
  23.9/55.7, norm/iso/unit 64) each carry both measured values (native / AVX2) and at least the
  stated tenfold margin; the kappa widening from 64 is explained by the two-chain relative
  roundoff and the CI record it cites. The stage 4a constants (4425: 1024/2048/64/4096 against
  401/935/11; 4621; 4668; 5055; 5774) carry their measured c. Not hidden floors.
- Hypothesis 3, derived case lists: 3053-3065 and 5931-5943 derive the function lists from the
  method tables; 5914-5922 and 5947-5962 derive files, structs and consts from the source text
  and pin the counts (8 structs, 19 consts, 13 thresholds, 16 reasons); 6201/6210 derive the
  option schema from `fieldnames` and `_ANALYSIS_CONSUMERS`. The one hand list without a tie is
  U29-7.
- Hypothesis 2, negative controls present and read: 4206-4211 (i05 same-spinor witness),
  4116 (`exact_set_multiplier` flips the kind), 4019-4027 (N4 and PSD multipliers READ with
  eps-literal perturbations on both sides), 3509-3510 (both real-class floors recomputed on a
  fixture that tells them apart), 3514-3518, 4557-4558 (the floor edge at 0.99/1.01 g_edge),
  5165-5176 and 5188-5192 (iteration and halving caps READ), 5200-5207 (rho_M1 READ),
  5300-5314 and 5316-5332 (the M1 census: 5 of 6 unconverged runs, 0 offenders over 400
  analyses), 5512, 5686 (a wrong graph is seen), 5754 (monotone residual), 5737-5758,
  6273-6286 (every option away from its default before the carry test).
- Helper availability: every `_st3_*`, `_ST3_*`, `_mc_*`, `_st4_*`, `_st4b_*` and
  `_st6_with_longitudinal` symbol the region calls is defined above its first use (lines 1152,
  2674-3029, 4347-4418, 5996-6191).
- Vocabulary pins (3032 outside, 4421-4422, 4061, 5911-5912, 5977, 6194) agree with the source
  constants at 24e8683 (`DISPERSION_ROUTES`, `AMBIGUITY_KINDS`, `ANALYSIS_STATUSES`,
  `_INVARIANCE_RESIDUAL_CAP == 3.0`).

## Unchecked

- Whether each regression testset in the region was ever shown red on its defect (Phase 9's
  negative-control rule): the comments cite commits (180ce70, 7711a8a) and history records for
  4531-4571, 4737-4769, 4771-4787, 5227-5333; I did not rebuild those trees to re-observe the
  failures. The claims are read, not re-measured.
- The Part B consumers of the scratch verb `_st4b_b_fake_run` and `_st4b_b_block_errors`
  (defined in the region at 6105-6191, used at 7177-7452, outside the region): whether the
  verb's hand-typed receipt consumer names and option-activity rules still mirror `analyze` is a
  seam between this region and U30's; noted, not audited.
- Runtime of the heavy loops (400 manufactured maps at 3243, 200 dense maps at 4427/5434, the
  400 `analyze` calls at 5316-5328, six Newton closed orbits at 4907) in the fast lane was not
  measured; the region has no lane gate, so these run in both lanes.
- The testsets themselves were not re-run through the stage runner; all leads are measured by
  the three probes above, which rebuild the fixtures from the same seeds and builders.
