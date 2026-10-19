# U24: contracts/: the three analysis contracts

## Region

Tree `/cfs/ad/dxu/Library/Julia/Octopus` at 24e8683 (read-only).

- `src/contracts/twiss_dispersion_identity.jl` lines 1-1308 (1308 lines)
- `src/contracts/twiss_external_reference.jl` lines 1-1034 (1034 lines)
- `src/contracts/analysis_effectiveness.jl` lines 1-678 (678 lines)

Total 3020 lines, read line by line (every line of all three files).

Hypotheses briefed: (1) does each contract prove its property, or are identities checked
against the analysis's own output circular; (2) external reference provenance (pinned versions,
coordinate conversions, the slope-vs-canonical dispersion convention (X2) after 2026-10-18);
(3) effectiveness by injection: an ignored analysis option is detected.

## Provenance

READ line by line: the three region files in full (ranges 1-1308, 1-1034, 1-678).

READ in support (outside the region, by grep or short range, to judge the region's claims; not
audited): `src/analysis/twiss_dispersion_analysis.jl` 365-372 (`_with_longitudinal_mode`), 374-420
(the option schema and categories), 700-800 (`normal_mode`, `matched_covariance`), 1309
(`physical.tunes = collect(Float64, o.tunes)`), 1455-1495 (`_analysis_verdict`,
`_VERDICT_RESIDUALS`, the failure-text format `"<name> residual <v> exceeds its acceptance <t>"`);
`src/analysis/dispersion_routes.jl` 125-150 (`_kappa_route`), 388/436 (`coefficient_condition ::
Determined{Float64}` on the route records; the diagnostics tuple carries a Float64, line 1427 of
the analysis); `test/runtests.jl` 1195-1380 (the stage 6 testset and its negatives n1-n8),
7356-7440 (the 4b-B injected-run negatives), 30655-30695 (the external-reference tests);
`docs/theory/twiss_dispersion.md` 1185-1215 (the (D8) paragraph and the 2026-10-18 convention),
1918-2000 (9.5), 2213-2235 (12.2); `docs/experiences.md` 690-730; `docs/design/
twiss_dispersion_analysis.md` 596-622; `docs/history/beam_beam_fixes_2026_10_18.md` 1-70;
`docs/history/twiss_external_benchmarks_2026_09_15.md` by grep (versions, TOL-B);
`validation/twiss_{madx,ptc,xsuite}_benchmark.jl` by grep (fixture constants, dispersion rows);
`validation/reference/` listing, the four tables' `#` headers, `xsuite_twiss_provenance.txt`.

EXECUTED (scripts and logs under
`/cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U24/`; Julia 1.12.4,
4 threads, host sapphirerapids, native arm only):

- `probe_contracts.jl` -> `probe_contracts.log`:
  - `validate(TwissExternalReferenceContract())`: `:passed`, 692 rows (madx 81, ptc 112,
    xtrack 499), failed 0, worst ratio 0.3568 (xtrack Rd_1e-3 ET_bety_edw_teng, TOL-F);
    worst_TOL_A 0.139, worst_TOL_A_cond 0.0456, worst_TOL_B 1.94e-4, worst_TOL_C 4.16e-3,
    worst_TOL_D 6.71e-3, worst_witness 0.113, worst_assert 0; tables
    `twiss_madx_5.03.06.tsv`, `ptc_twiss_madx_5.03.06.tsv`, `xsuite_twiss_xtrack_0.112.0.tsv`,
    `twiss_benchmark_maps.tsv`; 4.9 s.
  - `validate(AnalysisOptionEffectivenessContract())`: `:passed`, 19 probes, 16 inactive entries
    applied, 32 receipts checked, 15 moved, 4 fixed, stale 0; 10.9 s.
  - `validate(TwissDispersionIdentityContract())`: `:passed`, 57 identities on 160 fixture runs
    (31 judged results, 3 `:degraded`), worst ratio 0.1317 (`k_longitudinal_block_symplecticity`
    on F4 DBA + RF), 17 diagnostics fired, 23 declaring kinds = 18 analyzed + 5 refused,
    dense6_unresolved 0, dense4_skipped 0, verdicts 54 consistent / 0 inconsistent,
    absolute_pins_checked 3, normalizer ratios 2.473 / 1.803; the only slug with count 1 is
    `c_line_equals_matrix`; 31.0 s.
  - `_identity_contract_record!(m, :c_caller_symplecticity, 1.0, Inf, ...)` -> `ok = true`,
    `max = 0.0`, count 1, no failure text; with kappa `NaN` -> `ok = true`, no `max_` key written,
    count 1, no failure text.
  - Dense effectiveness fixture: the default run selects `dispersion.longitudinal = 2`
    (uncertified) and the contract's alternative is 2; `longitudinal_mode = 1 / 2 / 3` give
    `dispersion.longitudinal = 1 / 2 / 3`, status degraded / passed / degraded, eta
    (-0.0162, 0.0372, 0.0758, 0.2559) / (0.4282, 0.3366, -0.1311, -0.1603) /
    (-0.4119, -0.3738, 0.0553, -0.0956).
  - Doubling `emittances` doubles the physical covariance exactly: `||Sb - 2 Sa|| / ||Sb|| = 0.0`.
- `probe_second.jl` -> `probe_second.log`:
  - The MAD-X A1 fixtures after `_extref_convert(:madx, ...)`: U1, U2, K1, K2, Rd_1e-3 all
    `coasting.holds = true`, `h = 1.0`, `zeta = 0`, `M[6,1:5] = 0`, `M[1:4,5] = 0`.
  - PTC 6D rows: h = 1.03176 (B4), 1.03432 (B4K), 0.9999972 (G6_2.0MV), 0.9999997 (G6_0.2MV).
  - `_identity_contract_probe` with a verb that diverts every F6a dense map to the
    definite-degenerate map `diag(R(0.73), R(1.41), R(0.73))`: `passed = true`, message
    "twiss identities certified: 57 identities on 100 fixture runs (0 of the 11 judged results
    :degraded), worst ratio 0.13167 ...", `dense6_unresolved = 20`, no slug ran on zero fixtures.

## Leads

### LEAD U24-1 [Moderate, confidence high] src/contracts/twiss_dispersion_identity.jl:1247
Claim: An F6a dense map whose certification or frame fails is skipped silently at the contract level: with all twenty diverted to an unresolved result, `validate` still answers `:passed` with the "certified" message, and only the suite's `dense6_unresolved == 0` pin can see it.
Mechanism: In `_identity_contract_probe`, a `:bunched` fixture with `index == 0 || !frame_unique(r)` is a failure for F4/F5 but, for a name starting with "F6a", only increments `metrics[:dense6_unresolved]` and `continue`s; no row, pin, or message term depends on that counter, every slug still finds a fixture among F1-F5/F6b/F8 (the row-coverage guard is satisfied), and the pass message counts "fixture runs", not judged results against `dense_maps`. The public verdict therefore claims a certification over `dense_maps = 20` maps while judging 11 results instead of 31 (class 6, silent degradation; the design says a skip must be visible).
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U24/probe_second.jl` (part b) -> `F6a diverted: passed=true status=passed dense6_unresolved=20 fixtures=100 folded judged=11`; a sound contract would be `:failed` (or at least name the 20 unresolved maps in the message) when `dense6_unresolved > 0`.

### LEAD U24-2 [Moderate, confidence med] src/contracts/analysis_effectiveness.jl:54
Claim: The `longitudinal_mode` effectiveness probe cannot tell "explicit index honoured" from "explicit index ignored, heuristic used" because its alternative (2) is the index the uncertified heuristic selects on the same fixture; the verdict rests on the consumer's own `rule`/`certified` flags and the receipt echo.
Mechanism: `_ANALYSIS_CONTRACT_LONGITUDINAL_INDEX = 2` is documented as "the canonical eigenvalue index of the dense 6D fixture's longitudinal mode" and the measured default run selects 2 uncertified; `_analysis_contract_observable(:longitudinal_mode, ...)` checks `field(ap, :selected) == 2`, `rule === :explicit`, `certified === true` and the mirror flags on the default run, all of which an implementation that sets the flags from `longitudinal_mode isa Integer` but keeps the heuristic's selection would also produce. An unambiguous observable exists: `longitudinal_mode = 1` or `3` moves `dispersion.longitudinal` to 1 / 3 and moves eta from (0.428, 0.337, -0.131, -0.160) to (-0.016, 0.037, 0.076, 0.256) / (-0.412, -0.374, 0.055, -0.096), with `:degraded` status, which the probe could assert directly from the result. Hypothesis 3; the suite's 4b-B negatives (`_st4b_b_fake_run` defects `wrong_consumer`, `echo_option`, `no_move` on `preferred_form`, ...) contain no "index dropped" verb.
Repro: `julia --project=. -e 'using Octopus; fx = Octopus._analysis_contract_fixtures(UInt64(20260911)); r0 = analyze(TwissDispersionAnalysis(), fx.matrix); println(r0.dispersion.longitudinal, " == ", Octopus._ANALYSIS_CONTRACT_LONGITUDINAL_INDEX)'` -> `2 == 2`; then `analyze(TwissDispersionAnalysis(strict=false, longitudinal_mode=1), fx.matrix).dispersion.longitudinal` -> `1`.

### LEAD U24-3 [Minor, confidence high] src/contracts/twiss_dispersion_identity.jl:667
Claim: `_identity_contract_record!` has no finite-kappa guard, so an infinite kappa turns the row into an unconditional pass and a NaN kappa into a pass that records no maximum.
Mechanism: `tol = c * eps() * max(1.0, kappa)`; with `kappa = Inf`, `tol = Inf` and `ratio = v / Inf = 0`, so `ratio > 1` is false and `max_<slug>` is recorded as 0 for a value of 1.0; with `kappa = NaN`, `max(1.0, NaN)` is NaN, `ratio` is NaN, every comparison is false, nothing is pushed to `failure_texts` and no `max_` key is written while `count_<slug>` still advances (the row counts as run). The kappas are products of `cond(U)`, `cond(Uls)`, `cond(Mcal)`, `norm(T) norm(T^-1)`, `1/|h|`; `cond` of an exactly singular matrix returns Inf. Reachability on the current fixtures is unproven (class 1, a correct check that stops executing).
Repro: `julia --project=. -e 'using Octopus; c = TwissDispersionIdentityContract(); m = Dict{Symbol,Any}(); println(Octopus._identity_contract_record!(m, :c_caller_symplecticity, 1.0, Inf, "p", c), " ", m[:max_c_caller_symplecticity]); m2 = Dict{Symbol,Any}(); println(Octopus._identity_contract_record!(m2, :c_caller_symplecticity, 1.0, NaN, "p", c), " ", haskey(m2, :max_c_caller_symplecticity))'` -> `true 0.0` and `true false`; a sound implementation returns `false` (or throws) for a non-finite kappa.

### LEAD U24-4 [Minor, confidence high] src/contracts/twiss_dispersion_identity.jl:976
Claim: Two Layer 3 rows are circular or near-circular and one physical output is never tied to anything independent: `c_normal_mode_tunes` compares `normal_mode(result, j).tune` with `physical.tunes[j]`, which are the same numbers, and `physical.beta/alpha/gamma` are checked by no identity against the normalizer or the matrix.
Mechanism: `normal_mode` returns `o.tunes[j]` and `physical.tunes = collect(Float64, o.tunes)` (analysis line 1309), so the row measures 0 exactly on every fixture (the frozen table records `0.000e+00 | 0.000e+00`), its `count_` satisfies the coverage guard, and it cannot drift; `c_matched_covariance_accessor` re-runs the same `_matched_covariance_6d` on the same normalizer with the same emittances (also 0 | 0); `c_normal_mode_kappa` compares only the per-plane invariant `beta gamma - alpha^2` between two arrays that are the same data before and after unscaling; `c_x2_graph_readout` re-applies the eigenplane route's own formula in physical coordinates (an unscaling-consistency check, not a physics check); `c_tune_consistency` uses `result.clusters.eigenvalues` (the analysis's own eigensolve) rather than `eigvals(result.matrix)`. The rows that do prove physics from the caller's matrix are E8 (`M U = U R(mu)`), D14, D8, K4, the covariance closure and D24; none of them involves `physical.beta/alpha/gamma`, whose correctness rests on the external-reference contract's fixtures only (cross-file seam, not pursued). Hypothesis 1.
Repro: `julia --project=. -e 'using Octopus; r = validate(TwissDispersionIdentityContract()); println(r.metrics[:maxval_c_normal_mode_tunes], " ", r.metrics[:maxval_c_matched_covariance_accessor])'` -> `0.0 0.0`; `grep -n "tunes = collect(Float64, o.tunes)" src/analysis/twiss_dispersion_analysis.jl` names the shared source.

### LEAD U24-5 [Minor, confidence high] src/contracts/twiss_dispersion_identity.jl:766
Claim: The V1 verdict re-derivation (`verdicts_consistent` / `verdicts_inconsistent`) has never executed its non-empty branch: on the default fixtures no judged result carries a failure, and no suite negative feeds it a result whose status disagrees with its residual triples.
Mechanism: `recomputed` collects `_VERDICT_RESIDUALS` names whose value exceeds the reported tolerance and `reported` the names found by `startswith(f, n * " residual")` in `result.failures`; on the 54 consistent verdicts measured both lists are empty (`folded_passed + folded_degraded = 31`, no `folded_failed`), so the string-format dependency on `_analysis_verdict`'s text and the `status_consistent` test have only ever compared empty with empty. The stage 6 negatives n1-n8 inject tolerances, missing multipliers, liar kinds, silent certification, perturbations, throws and failing kinds, none a doctored verdict (class 13: an instrument never fed a known defect).
Repro: `grep -n "verdicts_inconsistent" test/runtests.jl` -> only the `== 0` pin at 1283 and the TW-PINS line; `julia --project=. -e 'using Octopus; r = validate(TwissDispersionIdentityContract()); println(get(r.metrics, :folded_failed, 0), " ", r.metrics[:verdicts_consistent])'` -> `0 54`.

### LEAD U24-6 [Minor, confidence med] src/contracts/twiss_external_reference.jl:411
Claim: The MAD-X TOL-B rows compare the canonical `physical.eta` with MAD-X's slope `beta0 * DX` without the (D8) factor `h`, which is right only because every A1 fixture is coasting, and the rows assert neither the coasting structure nor `h = 1`.
Mechanism: The 2026-10-18 convention (theory note after (D8); `docs/experiences.md` "One quantity, one convention") states that MAD-X's `deltap` dispersion is the slope `eta / h` and "must be converted by (D8)"; the row `eta_<k>_vs_beta0*<K>` applies no conversion. Measured: U1, U2, K1, K2 and Rd_1e-3 analyze with `coasting.holds = true`, `h = 1.0`, `zeta = 0` after the bare conversion, so the two quantities coincide (worst_TOL_B = 1.9e-4 of 1e-12). The xtrack C1 layer pins its precondition with `coasting_structure_present/absent` assert rows and gates `physical_eta_vs_h*dx` on bunched maps; the MAD-X layer has no such row, so a bunched MAD-X fixture added to the hand list would compare a canonical quantity with a slope (and the PTC 6D rows, where h = 1.032 and 1.034 on B4 and B4K, are correctly left unglued). Hypothesis 2; latent, not a wrong number today.
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U24/probe_second.jl` (part a) -> `madx U1: coasting.holds=true h=1.0 zeta=[0.0, 0.0, 0.0, 0.0]` for all five fixtures; `grep -n "coasting_structure" src/contracts/twiss_external_reference.jl` shows the assert rows exist for xtrack only.

### LEAD U24-7 [Minor, confidence high] src/contracts/twiss_external_reference.jl:732
Claim: The contract's fixture lists are hand copies of the validation scripts' constants with no tripwire, and the xtrack C1 layer has no table-coverage row, so a C1 fixture present in the table but absent from `_EXTREF_XT_C1_FIXTURES` is uncompared without any sign.
Mechanism: `_EXTREF_XT_C1_FIXTURES` duplicates `C1_FIXTURES` of `validation/twiss_xsuite_benchmark.jl` (17 entries), `_EXTREF_PTC_EXPECTED_IDS` duplicates `EXPECTED_IDS` of the PTC script (10), and the MAD-X loop `("U1", "U2", "K1", "K2")` duplicates `A1_FIXTURES` (4); all three agree today (checked against the scripts and the tables: the xtrack table's C1 layer carries exactly the 17 listed fixtures). The PTC side learned this lesson (`layer_rows_present`, stage 9 U10a-1-1, 97 of 111 rows vanished silently); the xtrack side selects by list only, and nothing in `test/runtests.jl` or the scripts compares the lists (class 2, hand-copied knowledge without a coverage tripwire).
Repro: `grep -n "_EXTREF_XT_C1_FIXTURES\|_EXTREF_PTC_EXPECTED_IDS" test/runtests.jl validation/*.jl` -> no match; `awk -F'\t' '!/^#/ && $1=="C1" {print $2}' validation/reference/xsuite_twiss_xtrack_0.112.0.tsv | sort -u | wc -l` -> 17, the list's length, with no row in the contract that would fail at 18.

### LEAD U24-8 [Minor, confidence med] src/contracts/twiss_external_reference.jl:195
Claim: The versions the contract claims to certify (MAD-X 5.03.06, PTC of the same binary, xtrack 0.112.0 at commit 384952bc in theory 9.5) are not read from the tables: the newest file by numeric fields is taken and its header's `# MAD-X version:` / `# tool:` line is never compared with the claim.
Mechanism: `_extref_table_path` sorts `<prefix>*.tsv` by the integers in the file name and returns the last; `validate` records only the path in `metrics[:table_<code>]`. A `twiss_madx_5.04.00.tsv` dropped beside the current table re-targets the docstring's and theory 12.2's "exactly one version" claim with no failure; the header lines carry the version and are parsed into `_ExtRefTable.header` but not inspected (class 14, documentation as claim; class 11, the configuration read is not asserted).
Repro: `grep -n "header" src/contracts/twiss_external_reference.jl | grep -v "^.*#"` shows `header` stored and never read after construction; `julia --project=. -e 'using Octopus; d = mktempdir(); for f in ("twiss_madx_5.03.06.tsv", "twiss_madx_9.99.99.tsv"); touch(joinpath(d, f)); end; println(basename(Octopus._extref_table_path(d, "twiss_madx_")))'` -> `twiss_madx_9.99.99.tsv`.

### LEAD U24-9 [Minor, confidence med] src/contracts/analysis_effectiveness.jl:468
Claim: The `emittances` observable is presence-only (`covariance.status === :unique`), so the values of the tuple are pinned by nothing but the consumer's receipt echo.
Mechanism: `_analysis_contract_observable(:emittances, ...)` compares the default run's undetermined covariance with the alternative run's determined one; an implementation that reads `emittances !== nothing` and then uses unit emittances would pass the observable and fail only if its receipt were honest about the tuple it used. The value effect is exact and cheap to assert: doubling the tuple doubles `physical.covariance` with relative difference 0.0 (measured), so `matched_covariance(result, 2 .* alt) == 2 Sigma` or a trace ratio would make the option's value observable at the consumer boundary. Hypothesis 3; sibling receipt-only verdicts: `dispersion_routes` reads the `executed` tuple from the receipt rather than `result.diagnostics.routes`, `closed_orbit_atol` reads the receipt (its binding is covered by branch probe 4), `map_uncertainty` reads the receipt field `rho_M0`.
Repro: `julia --project=. -e 'using Octopus, LinearAlgebra; fx = Octopus._analysis_contract_fixtures(UInt64(20260911)); S(e) = Octopus.determined_value(analyze(TwissDispersionAnalysis(emittances=e), fx.matrix).physical.covariance); println(norm(S((2e-6,4e-6,6e-6)) - 2S((1e-6,2e-6,3e-6))) / norm(S((2e-6,4e-6,6e-6))))'` -> `0.0`; `grep -n "name === :emittances" -A1 src/contracts/analysis_effectiveness.jl` shows the status-only test.

## Clean

- Hypothesis 2, coordinate conversions and the (X2) convention: `_extref_convert` implements
  `M_oct = Sh(u) J0 F M F^-1 J0^-1` exactly as the docstring and the table headers state (MAD-X
  `J0 = diag(1,1,1,1,beta0,1/beta0)`, `u = -C/gamma0^2` bare; xtrack `J0 = I`; PTC `F =
  diag(1,1,1,1,-1,1)`, `u = +C/gamma0^2` task only); measured agreement on the committed tables:
  xtrack transverse at TOL-A worst 0.139 of 1e-12, the T6 longitudinal block at TOL-D worst 6.7e-3
  of 1e-7, PTC at TOL-C worst 4.2e-3 of 1e-9. The xtrack dispersion rows follow the 2026-10-18
  convention: `dx` (the slope) against `graph[:,2] = eta/h`, `physical.eta` against `h * dx`, and
  `h` against `det(U_ls)` of xtrack's normalizer (lines 859-871, 956-959); the PTC 6D `DISP` rows,
  where h = 1.032 / 1.034 on B4 / B4K, are recorded in the script and not gated here (docstring
  447-449, confirmed by reading 662-695); the PTC 5D rows run on the coasting completion, where h = 1
  structurally. The `_extref_ptc_coasting_completion` row `r = -A' S4 d` was re-derived from
  `(M' S M)[1:4, 6] = A' S4 d + r = 0` and is gated by the 1e-12 symplectic residual row.
- Provenance recorded: `metrics[:table_<code>]` names the file used; the table headers name MAD-X
  5.03.06, xtrack 0.112.0 (xobjects 0.6.10, xpart 0.23.18, numpy 2.4.6, python 3.11.5) and the
  sidecar pins the commit 384952bc, the driver sha256 and the maps-table sha256, matching the
  docstring, theory 9.5 and the 2026-09-15 record (the gap is only that the contract never asserts
  them, U24-8).
- The no-silent-pass rules of the external contract hold: a code with zero rows fails (991-994), a
  NaN Octopus value fails its row (284), a `bound == 0` row with a nonzero difference gives ratio
  Inf (977), the PTC `table_rows_present` and `layer_rows_present` rows fail on a 5D-only or a
  relabelled table (suite 30670-30679 proves the latter red), `analyze_threw` / `analysis_determined`
  / `two_tunes_present` / `mode_matching_margin` are failing rows rather than skips.
- Hypothesis 1, the parts that are not circular: Layer 3 recomputes from the caller's matrix the
  E8 reconstruction (`M U = U R(mu)` with `R = [cos sin; -sin cos]`, the (E8) eigenvalue
  `exp(-i mu)`), the (D14) graph invariance on the caller's blocks, the (D8) round trip
  (`h = 1/(1 + zeta' S4 D2)`, consistent with `Mcal[6,6] = 1 - zeta' S4 eta` which the
  `c_d3_determinant` row pins), the (K4) block diagonality of `Mcal^-1 M Mcal`, the covariance
  closure `M Sigma M' = Sigma` and (D24) on coasting maps; these would fail on a wrong U, graph,
  triple or Sigma independently of the kernel's own residual arithmetic. Layers 1 and 2 are
  re-judgements of the analysis's residual values under contract-owned tolerances (independent
  tolerance, shared value), as the file states; the design intends that split.
- The identity contract's loudness rules verified by reading and by the suite's negatives n1-n8:
  a missing multiplier fails by name, a non-slug multiplier key fails, a slug that runs on no
  fixture fails, a predicate that throws counts as silent, a declaring kind without an example or
  without a result fails by name, an F4/F5 certification failure fails (only F6a is exempt,
  U24-1). The diagnostic table's 17 rows fired on this host; the D3 pins are the theory's
  0.0360896443733161 and 0.0838222432933016 at 1e-13 / 1e-12 and are marked seen by tag.
- `_identity_contract_certified` carries every other option by derivation over the fields
  (`_with_longitudinal_mode`), and the scaling-pair runs keep every keyword except `scaling`,
  `strict`, `longitudinal_mode` (1282); the `Core.Box` discipline (Refs in `do` blocks, no local
  kwarg function captured) is followed where the comments claim it.
- The multiplier table: all 57 rows have a frozen `c`, the measured ratios at frozen `c` on this
  host (sapphirerapids, native) are at most 0.1317, below the 0.25 re-open line and the 0.5 suite
  pin; `_default_identity_multipliers` has exactly the 57 slugs of `_IDENTITY_CONTRACT_SLUGS`
  (9 + 28 + 20), and `metrics[:identities] = 57`.
- Hypothesis 3, what does detect an ignored option: `scaling` (the scaled matrix must equal the
  input under `:none` and differ under `:auto`), `clusters` (the partition the report groups by),
  `resolution_chord` (the forced flag on the repeated-betatron input), `preferred_form` (the
  presented form), `newton_max_iterations` (the recorded iteration count against the cap in both
  directions), the four branch probes (rtol binds at 1e-20, `:flag` vs `:error`, `:warn` vs
  `:require`, `atol = 1.0` accepts), and `strict` on the failing fixture; an alternative equal to the
  default and a missing alternative fail the contract; the 4b-B negatives prove eleven defect
  verbs red. The schemas swept are derived from `_concrete_octopus_subtypes(AbstractAnalysis)`.
- `D12` compares `coefficient_condition > 1e3` on the diagnostics tuple, whose field is a
  Float64 (analysis 1427), not the route record's `Determined{Float64}`; no MethodError path.

## Unchecked

- The haswell arm (`OPENBLAS_CORETYPE=Haswell julia -C haswell`) of the multiplier table was not
  re-measured; the frozen `c` values were compared only with this host's native ratios.
- The validation scripts (`validation/twiss_*_benchmark.jl`, `twiss_benchmark_cells.jl`,
  `convert_map`) and the generators were read by grep only, to compare the hand-copied lists and
  the dispersion rows; their own correctness and the stage 8 conversion law's derivation are
  outside the region and were not re-derived.
- The analysis kernels the contracts call (`analyze`, the route kernels, `_matched_covariance_6d`,
  the scaling back-transformation) were not audited; only the lines named under Provenance were
  read to judge the contracts' claims about them.
- Reachability of a non-finite kappa (U24-3) on a result the analysis marks `:unique` was not
  established; the lead is the missing guard, measured on a direct call.
- The kind sweep's 23 declaring kinds were not enumerated one by one; the counts (18 analyzed, 5
  refused, 0 without example) were taken from the measured run.
- No CUDA or MPI angle applies to this region (CPU-only contracts); none was run.
