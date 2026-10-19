# U50: theory notes E: twiss_dispersion.md and crab_cavity_noise_response.md

Tree under audit: `/cfs/ad/dxu/Library/Julia/Octopus` at 24e8683, read-only. Unit brief:
`result/comprehensive_audit_2026_10_18/plan/U50.md`. Depth: claims-vs-code with sampled
independent re-derivations.

## Region

- `docs/theory/twiss_dispersion.md`, lines 1-2917 (whole file).
- `docs/theory/crab_cavity_noise_response.md`, lines 1-784 (whole file).

Total 3701 lines, every line read.

References read in part, for comparison only (not audited as regions): `src/analysis/canonical_separation.jl`
265-340; `src/elements/strong_beam.jl` 1290-1420; `src/elements/crab_cavity.jl` 1-60, 130-140, 230-240,
315-330, 370-460 (grep windows); `docs/design/twiss_dispersion_analysis.md` 1-60, 350-385, 590-628 and
grep hits; `validation/twiss_madx_benchmark.jl` 15-50, 120-125, 315-345; `validation/twiss_xsuite_benchmark.jl`
12-60, 122-126, 265-301, 515-600, 800-870; `validation/twiss_ptc_benchmark.jl` 10-70, 137-138, 625-640;
`validation/generate_madx_twiss_reference.jl` grep hits; `validation/twiss_benchmark_cells.jl` constants;
`validation/crab_cavity_noise_response.jl` 1-60, 297-302, 440-520, 1160-1202, 1440-1451, 1636-1662,
1680-1700, 1736-1745, 1770-1790, 1840-1916, 1995-2060, 2109-2123, 2158, 2242-2249; `docs/history/`
`twiss_external_benchmarks_2026_09_15.md` 180-200, 436-452 and grep hits; `twiss_dispersion_degeneracy_theory_2026_09_11.md`
grep hits and probe output 427-433; `crab_cavity_noise_validation_2026_10_14.md` and
`crab_cavity_noise_relative_strength_2026_10_15.md` grep hits; `todo_ledger_archive.md` 2990-3012;
`beam_beam_fixes_2026_10_18.md` 24-42; `docs/experiences.md` 703-715; `docs/todo.md` grep;
`docs/public_api.md` grep; `examples/weak_strong_tracking.jl` and `test/examples/crab_cavity_noise.jl` grep.

## Provenance

READ line by line: both region files in full (twiss 1-500, 501-1000, 1001-1500, 1501-2000, 2001-2250,
2251-2500, 2501-2917; crab 1-400, 401-784).

EXECUTED (scratch `result/comprehensive_audit_2026_10_18/probes/U50/`, outputs beside each script):

- `probe1_twiss_identities.jl` -> `probe1_output.txt`: 138 checks, ALL PASS. Pure LinearAlgebra, no Octopus.
  Random stable 6x6 symplectic map with a known normalizer (tunes 0.31, 0.72, 0.045; the 0.72 puts one
  mode above one half so the orientation rule is exercised); random 4+2 section map; the Section 13 fixtures;
  the thick-lens FODO of 13.10. Residuals 1e-17 to 1e-13 except (D28) vs central finite difference 1.2e-10
  and the pinned 0.28293 to 1.2e-6 (five printed digits). Equations verified numerically: (D3), (D7)-(D8),
  (D10)-(D12), (D14), (D15)-(D17), (D19)-(D22), (D26)-(D28), (D29) O(dt^2) [6.3e-6, 1.58e-6, 3.9e-7 at
  dt = 1e-2, 5e-3, 2.5e-3], (K1)-(K5), (K7)-(K8), (K12)-(K14), (I1) [9.8e-16], (O1)-(O5) [h = 0.806 > 0],
  (X2) both component formulas, (E3)-(E8), (E10)-(E14) in 4D and 6D, (M1)-(M5), (M6), (M9)-(M16), (T1)-(T11),
  (T15)-(T16), (P5), (B3)-(B5), (B7)-(B11), (F4)-(F6), (A1), (N7), (N15), (N16), (N17) incl. the aI+bS2
  invariant family and the pseudoinverse rejection, (N18), 13.10 (cos mu = 0.9744003972058644,
  Q = 0.0360896443733161, Gram minimum 0.0838222432933016 all to <= 6e-17; the four detuned rows
  3.394e-4/2.133e-3, 3.396e-7/2.134e-6, 3.396e-10/2.134e-9, 3.396e-13/2.134e-12 with |M|_2 = 2.980 and
  q = 2.48e-6 at 1e-9, 2.48e-3 at 1e-12).
- `probe2_octopus_convention.jl` -> `probe2_output.txt`: ALL PASS, Octopus loaded. On a bunched map with
  h = 1.2255 (slope and canonical eta differ by 18 %): `analyze` returns `physical.eta` equal to the canonical
  (D12) eta to 1.5e-15 and `physical.graph[:,2] = eta/h` to 1.3e-15 (|eta_an - eta/h| = 0.169, so the
  analysis does NOT report the slope); `Octopus._dispersion_graph(zeta, eta)` reproduces U_rs U_ls^-1 and
  h = det U_ls exactly; h = 0 is refused by name; `gaussian_strong_beam_covariance` forms cov6[1:4,5:6] =
  graph * L exactly and is bit-identical to the pre-2026-10-18 slope form at zeta = 0. Crab note 4.3:
  compiled kick slope -0.183227 m^-1 (note -0.18323), relative gap to 2 k_bb/(sx(sx+sy)) 3.5e-11 (note "1e-6");
  <F'>/F'(0) = 0.5000, rms(F')/|F'(0)| = 0.6447 (note 0.645).
- `probe3_crab_numbers.jl` -> `probe3_output.txt`: every number of the crab note recomputed from its own
  inputs (listed under Clean), with two disagreements (leads U50-1 and U50-2).
- `probe4_degeneracy_sets_transport.jl` -> `probe4_output.txt`: ALL PASS. (N2), (N4)-(N6), (N9)-(N12), (N14),
  (N20)-(N22) on diag(R(0.73), R(1.41), R(0.73)) conjugated by a random symplectic matrix (200 random unit
  c on the ellipsoid surface to 1e-15; sampled (N14) extremes within 2e-5 of the predicted endpoints), the
  un-conjugated oracle (center 0, shape diag(1/4,1/4,0,0)), and (F1)-(F3).

No repository file was modified; git was not run.

## Leads

### LEAD U50-1 [Minor, confidence high] docs/theory/crab_cavity_noise_response.md:555
Claim: The "doubling time" column of the section 6 table (and the "doubles in a minute" / "eight seconds" statements at lines 579, 735-736) is ln 2 / R rather than 1 / R, i.e. every entry is low by the factor 0.693.
Mechanism: d<J>/dn = (eps/2)<a^2> is a constant rate R relative to the design emittance (section 4.1), so <J>(n) = eps (1 + R n) grows linearly and doubles after 1/R turns; the column applies the exponential-growth formula ln 2 / R. With R = 1.724e-7 per turn and f_rev = 78 196.75 Hz the doubling time is 74.2 s, not 51 s; the other rows give 495-512 s (note 350), 11.7 s (8), 78 s (55), 126 s (87). The per-turn and per-hour columns, the 1 %-per-hour point (0.14 urad, 5.7e-7) and every acceptance threshold are unaffected: no script consumes the column.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus result/comprehensive_audit_2026_10_18/probes/U50/probe3_crab_numbers.jl | grep "time to double"` -> phase white x: 1/R = 74.2 s, ln2/R = 51.4 s (the note prints 51 s); or by hand 1/(1.72e-7 * 78196.75) = 74.3.

### LEAD U50-2 [Minor, confidence high] docs/theory/crab_cavity_noise_response.md:131
Claim: The "residual rms / dipole" column of the section 2.1 table (0.043, 0.174) is computed from the small-argument approximation of the residual, not from the exact Gaussian averages listed in the two columns beside it, and is 13 % high on harmonic 2.
Mechanism: the residual is (s delta_phi / ik)(1 - cos ikz); its centered rms over the Gaussian bunch, using the table's own <cos ikz> and <cos^2 ikz>, is sqrt(<cos^2> - <cos>^2) = 0.0421 (i = 1) and 0.1539 (i = 2); the quoted values equal (ik sigma_z)^2 / sqrt 2 = 0.0434 and 0.1736, the centered rms of the quadratic approximation (ikz)^2/2. Section 4.4 uses the exact form ((<cos^2> - <cos>^2)/<cos^2> = 0.19 %, 2.9 %), so the two sections disagree in method; nothing downstream reads the column.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus result/comprehensive_audit_2026_10_18/probes/U50/probe3_crab_numbers.jl | grep "residual rms"` -> i=2: exact centered 0.1539, quadratic-approx centered 0.1736, note 0.174.

### LEAD U50-3 [Minor, confidence high] docs/theory/crab_cavity_noise_response.md:410
Claim: Section 4.5 is internally stale after the 2026-10-18 decision it cites: it still points to "an owner row in `docs/todo.md`" that the same decision closed and archived, and it calls the measured ratio "the validation's explicit input" although the script has no default for it and uses it only as an INFO annotation.
Mechanism: lines 412-414 cite the owner decision of 2026-10-18; line 441 says the ratio "is not derived here (an owner row in `docs/todo.md`)". The row "Derive the beam-beam-mediated vertical response to horizontal offset noise" was closed by that decision and moved to `docs/history/todo_ledger_archive.md` (section at line 2993, "closed 2026-10-18"); `docs/todo.md` contains no such row. `validation/crab_cavity_noise_response.jl` line 23 documents `ref_y_over_x_phase=<none>`, line 1778 reads it only when supplied, and line 1868 prints "measured/predicted" as INFO with no verdict, so the measured 0.205 is not wired in anywhere; the archive entry (line 2996-2997) repeats the same "explicit input" wording. Documentation-as-claims (class 14) inside the paragraph that records the decision.
Repro: `grep -c "vertical response" /cfs/ad/dxu/Library/Julia/Octopus/docs/todo.md` -> 0; `grep -n "not an Octopus task" /cfs/ad/dxu/Library/Julia/Octopus/docs/history/todo_ledger_archive.md` -> 2993; `grep -n "ref_y_over_x_phase=<none>" /cfs/ad/dxu/Library/Julia/Octopus/validation/crab_cavity_noise_response.jl` -> 23.

### LEAD U50-4 [Minor, confidence med] docs/theory/crab_cavity_noise_response.md:653
Claim: The section 7 sweep table and acceptance item 2 describe an amplitude arm (A1, A4 at 10^5 turns; exponent from "A1, A4") that the validation script no longer runs that way: the script's acceptance fits the exponent on A05, A1, A2 and demotes A4 (25 000 turns) and A4s (12 500) to INFO as "the small-growth regime's edge".
Mechanism: `validation/crab_cavity_noise_response.jl` SWEEP_CASES (lines 1181-1200) carry A4 with `tkind = :Ta4` (turns_a4 = 25_000, line 1640), A4s (12_500), A2 and A05; the report fits `exponent(["A05", "A1", "A2"], ...)` (line 1914) and prints A4/A4s as INFO (lines 1849-1857). The note's plan ("this section is its plan, written in the present tense", line 587) was not brought current with the 2026-10-15 re-validation whose record lists A05/A1/A2. Cross-file seam for the auditor, outside this region: `SWEEP_DEFAULT_ORDER` (line 1201) omits A05 and A2, so a default-order sweep cannot evaluate acceptance 2 for the amplitude arm (the fit falls to "fewer than two resolved points", line 1905).
Repro: `grep -n 'exponent(\["A05"\|A4.*25_000\|turns_a4 = \|SWEEP_DEFAULT_ORDER = ' /cfs/ad/dxu/Library/Julia/Octopus/validation/crab_cavity_noise_response.jl` -> 1640, 1914, 1201; compare with the note's table rows for A1 A4 and acceptance item 2.

### LEAD U50-5 [Minor, confidence med] docs/theory/twiss_dispersion.md:2221
Claim: Benchmark 12.2-7's discharge note says "the forced-4D versus full-6D distinction by the C3 T6 cell, gated", but no gated row in any committed benchmark compares a forced-4D response with the full-6D one; C3 gates only the 6D route, and the sole side-by-side of the two objects is a recorded (ungated) C1 row.
Mechanism: in `validation/twiss_xsuite_benchmark.jl` the C3 layer (lines 811-870) gates `physical_eta_vs_h*tw6_dx` and records `tw6_dx_vs_graph[:,2]` and the zeta rows; it never reads a 4d-route quantity. The forced-4D object appears only as `recorded_row("C1", fixture, "xtrack_4d_route_dx_4d_beside_eta_x(different_object)", ...)` (line 547) and, on coasting maps where the two coincide, as a gated equality (line 550). The requirement's "distinguish" clause is therefore discharged by a recorded row, not a gate; the record `twiss_external_benchmarks_2026_09_15.md` (436-448) describes C3 as gating the longitudinal witnesses and the mode, not a 4D/6D distinction. The (X2) and PTC clauses of the same sentence are gated as stated (TOL-A/TOL-D rows; BETA_jk/ALFA_jk at TOL-C; PTC DISP rows recorded only, line 629).
Repro: `grep -n "dx_4d\|4d_route" /cfs/ad/dxu/Library/Julia/Octopus/validation/twiss_xsuite_benchmark.jl` -> 523 (comment), 547 (recorded_row), 550 (coasting equality); `awk 'NR>=811 && NR<=870' validation/twiss_xsuite_benchmark.jl | grep -c "4d"` -> 0.

### LEAD U50-6 [Minor, confidence low] docs/theory/twiss_dispersion.md:1196
Claim: The 2026-10-18 convention paragraph states that "MAD-X's `deltap` dispersion [is] the slope eta/h of (X2) and must be converted by (D8)", a claim about an external code that the committed benchmarks verify only where the conversion is the identity.
Mechanism: the MAD-X benchmark fixtures are coasting cells (U1, U2, K1, K2; `generate_madx_twiss_reference.jl` runs `twiss, deltap=+-1e-4` on U2 only and declares no cavity), where zeta = 0 and h = 1 by (D24), so eta/h = eta and (D8) is a no-op; no bunched or crab-coupled MAD-X case exists. For a lattice whose 6x6 map is not of the coasting form (D23) with RF off (a crab kick couples z and the transverse plane), the deltap closed-orbit derivative is a forced 4D response of the kind the note's own (X3) discussion calls "neither a full 6D symplectic normalizer nor a basis for the invariant graph", not eta/h. The sentence propagates verbatim to `src/elements/strong_beam.jl` 1376-1378 and `docs/history/beam_beam_fixes_2026_10_18.md` 27. Class 14 (documentation as claims); the instruction it gives is harmless where it has been tested.
Repro: `grep -n -i "deltap\|cavity" /cfs/ad/dxu/Library/Julia/Octopus/validation/generate_madx_twiss_reference.jl` -> deltap rows for U2 only, no cavity; `grep -n "deltap" /cfs/ad/dxu/Library/Julia/Octopus/docs/theory/twiss_dispersion.md` -> 1196, 2217.

### LEAD U50-7 [Minor, confidence low] docs/theory/crab_cavity_noise_response.md:557
Claim: The production-point predictions (1.72e-7, 1.10e-6 per turn; rho_bar 0.15, 0.17) exist as two hand-copies, the note's table and the script's command-line defaults, with no derivation in code and no tripwire between them (defect class 2); there is no drift today.
Mechanism: `validation/crab_cavity_noise_response.jl` lines 23 and 1774-1777 hard-code `ref_phase_white_x=1.72e-7 ref_amp_white_x=1.10e-6 ref_pink_ratio_x=0.15 ref_pink_ratio_y=0.17` although the script already holds every ingredient (CC_STRENGTH_X, CRAB_BETA_X, BETA_X_STAR, SIGMA_PHASE, REL_AMPLITUDE at 473-487; the Gaussian bunch factors at 2158; the per-harmonic weights at 1736 and 1745). My independent recomputation gives 1.7242e-7 and 1.0976e-6, and rho(0.228) = 0.1547 with band means 0.146/0.169, so both copies are currently right; a future change of the production point (strengths, k, sigma_z) would leave the defaults silently stale.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus result/comprehensive_audit_2026_10_18/probes/U50/probe3_crab_numbers.jl | grep "white x rate"` -> 1.7242e-07 and 1.0976e-06; `grep -n "ref_phase_white_x=1.72e-7" /cfs/ad/dxu/Library/Julia/Octopus/validation/crab_cavity_noise_response.jl` -> 23.

## Clean

Hypothesis 1 (equations the analysis implements; Discharged/Verified claims):

- (D3)-(D28), (K1)-(K14), (I1), (X1)-(X2), (O2)-(O5) re-derived numerically in probe 1 (and (N2)-(N22) in
  probe 4) on random symplectic maps and the Section 13 fixtures; every identity holds to roundoff (list and
  residuals in Provenance). Sign conventions checked analytically as well: (E3)/(E6) give U_j^T S U_j = S_2;
  (E5) with rho = e^{-i mu} yields M U_j = U_j R(mu_j) as (E8) states; (E12) G_j = U_j U_j^T follows from
  (M - M^-1) U_j = 2 sin mu U_j S_2 and P_j = U_j(-S_2 U_j^T S_4); (E13) Im(u u^dagger) = U_j S_2 U_j^T = P_j S_4;
  (D11) h = det U_ls; (D12) and the (X2) component formulas agree with U_rs U_ls^-1; Xsuite's orientation
  rule (Re v)^T S Im v > 0 selects v = u^* so that [Re v, Im v] = [Re u, -Im u]; (N15) eigenvalue e^{+i mu} and
  norm -2i by hand and by probe; the (N17) true-graph family eta = (b, a, 0, 0)/(1+a^2+b^2) with |eta|^2 <= 1/4.
- The Edwards-Teng form 2 on the probe's map is inadmissible (u = kappa_1y = -0.24 < 0, 1 + det R_2 = -4.15),
  exactly as 7.3 says ("form 2 requires u > 0, form 1 requires 1 - u > 0; at least one holds"); after exchanging
  the labels form 2 carries the form-1 R by (T4), u' = 1 - u, and (B7)-(B9), (B8) hold.
- 12.2 item 3 "Discharged": `validation/twiss_madx_benchmark.jl` gates `U2_FD/DX_vs_beta0_header` and
  `U2_FD_vs_beta0*DX_relative` at TOL_FD = 1e-8 (lines 323-324; `ok &=`) and eta vs beta0*DX at TOL_B_REL = 1e-12
  (line 122); the quoted 3.8471258401173714e-09 is the recorded FD/DX-vs-beta0 residual in
  `twiss_external_benchmarks_2026_09_15.md` 189-195. The note says "recorded"; the row is in fact gated (an
  understatement, not a defect).
- 12.2 item 7: the (X2) clause (C1 rows `dx_vs_graph[:,2]`, `physical_h_vs_det(U_ls)`, `physical_eta_vs_h*dx`
  gated at TOL-A, lines 526-547; C3 `physical_eta_vs_h*tw6_dx` at TOL-D, line 867) and the PTC clause
  (BETA_jk/ALFA_jk at TOL-C after F = diag(1,1,1,1,-1,1); DISP rows recorded, line 629) are as stated; only the
  "distinction ... gated" wording is overstated (lead U50-5).
- Line 2240 and 2813: the degeneracy record embeds its probe (lines 72-418) and its output (427-433); my probes
  reproduce the quoted FODO constants to <= 6e-17, the Gram minimum to 4e-17, the four detuned rows to the printed
  digits, and q = 2.48e-6 / 2.48e-3 at eps = 1e-9 / 1e-12.
- 12.1's three audit records exist under `docs/history/` (theory 2026-09-08, notation 2026-09-09, literature 2026-09-09).
- Design-note consistency: deferred transport (design 88 vs theory 2133-2135); dispersion routes (design 359-381
  vs theory 8.3-8.6); (I1) normalization identical.

Hypothesis 2 (the 2026-10-18 convention paragraph):

- The paragraph (1191-1197), `_dispersion_graph` docstring (`canonical_separation.jl` 282-296), the strong-beam
  docstring (`strong_beam.jl` 1357-1380), the design note's resolution (604-612), `docs/experiences.md` 703-715
  and the archived ledger row (`todo_ledger_archive.md` 3010-3012) all say the same thing: the analysis reports
  canonical eta; the builder forms (D7) through `_dispersion_graph`; Xsuite's dx is eta/h. Probe 2 confirms the
  code does what the paragraph says on a map with h = 1.2255 (analysis eta canonical to 1.5e-15, graph = [zeta eta/h],
  builder block = graph * L exactly, bitwise unchanged at zeta = 0, h = 0 refused). The external benchmarks encode
  the same slope statement for Xsuite (`physical_eta_vs_h*dx`, `physical_h_vs_det(U_ls)`) and PTC (DISP vs
  graph[:,2]). The only unverified clause is the MAD-X one (lead U50-6).

Hypothesis 3 (crab note formulas vs the script; section 4.5 status):

- Coded kick (crab note 70-74) equals `src/elements/crab_cavity.jl` 135-137; `realize` scales both planes by
  (1 + d) (424-425, 435) as sections 1 and 3.2 say; the example's production point matches
  `examples/weak_strong_tracking.jl` (tunes 0.228/0.210/-0.01, chromaticity 2/2, 197 MHz, N = 1.7203e11,
  sigma_delta 6.6e-4, damping_turns 1e100, dmu = (pi/2, 0, 0)).
- Probe 3 reproduces: r_p 1.5347e-18, gamma 293.09, beta 0.99999418, eps 1.128e-8/1.004e-9, k 4.1288,
  k sigma_z 0.2477/0.4955, s_i 5.1684e-4/-1.2921e-4, f_rev 78196.75 and 2.815e8 turns/h; <cos>, <cos^2>, <sin^2>
  to four digits; 2.5e-6 and 5e-11; dx_IP/dphi 4.037e-3/5.046e-4, 4.04e-8 m, 4.25e-4 sigma; -0.138; common timing
  3.02e-3 vs 3.94e-3 and 0.588 (the exact second-moment ratio is 0.587); amplitude table 5.168e-8/1.292e-8,
  3.01e-9/6.89e-10, 1.021e-3/2.34e-4, 1.67/0.42 urad; 2.5 and 6.4; 0.93 and 0.865; kbb -9.008e-10, slope -0.18323,
  xi 0.01166/0.01173, 0.0215; Q' 0.2396/0.2216, beta*'/beta* 0.9926/0.984, +1.0 %/-1.9 %; decoherence dip 0.966
  and 6.7 %; <F'>/F'(0) = 0.5 and rms 0.597 (round, probe 3) and 0.5000, 0.6447 (elliptic code kick, probe 2);
  rho(0.228/0.210/0.240) = 0.1547/0.1800/0.1384, sidebands 0.164 and 0.141 (at Q - Q_s and Q + Q_s respectively;
  the note lists them unordered), band means 0.146/0.169, the "ideal 1/f" 0.198 (reproduced with the band
  [2^-16, 1]); E[sample variance] 0.9375 sigma^2 for aligned blocks over 2^16 turns (the note's Monte-Carlo
  0.936); statistical floor 4.9 %/11.1 %; rates 1.7242e-7 and 1.0976e-6 with harmonic-2 shares 1.3 %/5.0 %;
  per-hour 48.5/309/28.6; PSD 2.56e-15; the 1 %/h point 0.144 urad / 5.69e-7; residual shares 0.19 %/2.9 %;
  growth 1.7 %/11 % over 1e5 turns; 2^17; 2.1 h at 5 ms/turn; tol_halves 0.20 = 2 sqrt 2 / sqrt(204) = 0.198;
  1.4e-50.
- Section 7 against the script: estimators J_raw, eps_c, J_c identical (script 297-302, 1443-1451); n_0 = 2000;
  thresholds 1.25, 0.05, 0.1, 0.25 ([0.11, 0.19]), 1e-10, 0.8, 0.10, 0.01 (eps_c and centroid), 0.20, 0.05 all
  equal the script's defaults (lines 23, 1779-1790, 2123); pink runs at 2^17 turns (1639); the control's
  vertical falsifier at 5 % of the predicted x rate (2035, 2058-2060); A1's vertical rate reported as INFO
  (1873). Section 4.5's measured ratios (0.205, 0.128, 0.072, 0.389; 0.296/0.187/0.085; 0.247; 1.180e-6 vs
  9.5e-7 and 1.16; 0.97/0.84/0.63) agree with `crab_cavity_noise_validation_2026_10_14.md` 143, 302, 319-331
  and `crab_cavity_noise_relative_strength_2026_10_15.md` 33-34, 178, 197, 218-236. The section's heading and
  item 6 of section 8 correctly state the 2026-10-18 decision (measured, not derived; not an Octopus task);
  the stale pointer is lead U50-3.

Style only (not leads): the Twiss note's header (lines 5-7) dates the landing "2026-09-11 to 2026-09-13"
while its own 12.2 and the design note record stage 8 on 2026-09-15; "0.164 and 0.141" for Q +- Q_s is
listed in the reverse order of the +- sign.

## Unchecked

- Numbers attributed to the unpublished working notes [13] (twiss 2541-2544, 2789-2794, 2826-2827, 2732-2738):
  the MAD-X 5.03.06/5.09.03 warning text and the drifting tunes 0.0363/0.0431, the periodic tune errors 4.45e-9
  and 5.89e-6, the two maps at 1e-9 with dispersions differing by 1.25, the Hausdorff bound. Not reproducible
  from the repository; the degeneracy record states the same.
- The xtrack commit pin 384952bc (twiss 1920-1921) against the version 0.112.0 named in 12.2 and the record:
  no network access, not checked.
- (N13) (three coincident definite modes, rank-four filled ellipsoid): only the two-mode set (N11)-(N12), (N14)
  was probed.
- The four-case Edwards-Teng transport table of Section 5 (P3)-(P4) beyond (P5) and the periodic case; the
  notation record claims all four were checked, not re-done here.
- Literature equation numbers (Ohmi Eqs. 79, 100-105, 109; Lebedev-Bogacz 2.19, 3.2, 3.6-3.7, 4.12-4.13, 7.16,
  6.1-6.3; Sagan-Rubin 8-10; Parzen 22-25; Dieci-Friedman 7-10, 12-14, 16; Xu-Luo-Hao 2-8, 11-12, 17, 23, 28-32):
  not compared with the papers.
- Crab note 5.2 finite-window Monte-Carlo statistics (sd 0.0737, 99.9 % quantile 1.324, P = 0.085 %, the
  2^17-2^20 convergence 1.188/1.080/1.030/0.995, sd 0.0194, band [0.9545, 1.0594]) and the 2000-realisation
  pink periodogram means (0.1560 +- 0.0035 etc.): not re-run (the analytic rho was reproduced).
- The measured rates and ratios of sections 4.5 and 8 (hours of GPU sweeps) were checked against the two
  history records only, not re-measured; the benchmark scripts (MAD-X, PTC, xtrack, crab validation) were read
  for their gating logic, not executed.
