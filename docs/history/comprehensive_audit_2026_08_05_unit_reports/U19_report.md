# U19 Audit Report — coherent-mode / RNG validation scripts

Repo: /cfs/ad/dxu/Library/Julia/Octopus @ dbefe42 (read-only; no repo files touched).

## Coverage

Read line-by-line, in full:
- validation/coherent_mode_vlasov_theory.jl (713 lines)
- validation/coherent_beam_beam_modes.jl (215)
- validation/coherent_mode_eic_comparison.jl (171)
- validation/coherent_mode_scans.jl (114)
- validation/coherent_beam_beam_modes_beambeam3d.jl (68)
- validation/counter_rng_validation.jl (118)
- docs/theory/coherent_beam_beam_modes.md (264)
- validation/README.md entries: lines 167-199 (counter RNG) and 572-678 (coherent modes block)
Supporting reads: src/math/counter_rng.jl (full), src/contracts/Contracts.jl:1380-1538
(CoherentModePhysicsContract + validate), test/runtests.jl:135-144, 7280-7301,
paper/README.md excerpts, result/ and paper/data TSVs, AGENTS.md:336, .gitignore.

Probes run (scratch only, all < 120 s each):
1. probe_vlasov.jl — LIB_ONLY include at NJ=40/NPHI=64: harmonic_Y, symmetric_Y(r),
   EIC coupled_modes with max-u diagnostics.
2. Warm timing of simulate_1d_model (512/1024 turns; L=192/ngrid=32768 box case)
   and symmetric_Y at default NJ=72/NPHI=128.
3. probe_rng_weak.jl — faithful reimplementation of counter_philox4x32 (verified
   bit-exact vs committed code at 10 rounds over 1000 tuples), gate of
   counter_rng_validation.jl applied at rounds = 10/3/2/1, N = 1e6.
4. Ran validation/coherent_beam_beam_modes_beambeam3d.jl against the committed
   paper/data/bb3d_decks/singleslice_fort.{24,25,34,35} (copied to scratch as fort.*).
5. Ran validation/counter_rng_validation.jl at N=200000 (rc=0, passed).
Full runs of the long scripts (benchmark, scans, EIC comparison, full vlasov main
body) were NOT executed per instructions; their runtime claims are flagged below.

## Leads

### U19-1 — docs/theory/coherent_beam_beam_modes.md:121-127 (also 145-152) — Section 3 results table is stale pre-normalization-fix data the current code no longer produces — HIGH (stale reference)
The note was last touched at 917e63a (2026-07-28). The xi-normalization fix
(0c53d07), self-check-4 hardening (16975b2) and box-convergence archive (467548b,
2026-07-29) all touched only the validation script + validation/README.
Current code (fresh Aug-3 result/ TSVs, identical to committed
paper/data/yokoya_vs_aspect.tsv, diff rc=0; reproduced by probe at NJ=40):

| r | note says (m=1 / sim) | current code (m=1 / sim) |
|---|---|---|
| 0.02-0.05 | 0.86-0.91 "buried" / "no discrete mode" | 23.16, 5.51 (unconverged) / 1.297, 1.289 |
| 0.09-0.1 | 0.89 / 0.66 | 1.923 / 1.274 |
| 0.5 | 1.35 / 1.55 | 1.206 / 1.190 |
| 1.0 | 1.40 / 1.25 | 1.162 / 1.143 |

The note's own conclusion 2 ("agree to 1-2% wherever a discrete pi mode exists")
matches the CURRENT data but contradicts the stale table 15 lines above it, and
conclusion 3 ("the exact 1D solution loses the discrete pi mode below r≈0.1")
is contradicted by the current sim column (1.27-1.30 there). validation/README.md:677
records the corrected round-beam value ("1.40 before, 1.162 after") — the README
was updated, the theory note was not.
Repro: `cat result/yokoya_vs_aspect.tsv` (or `paper/data/yokoya_vs_aspect.tsv`)
vs the note's table; or run scratchpad/U19/probe_vlasov.jl.

### U19-2 — validation/coherent_mode_eic_comparison.jl:8-15 and docs/theory/coherent_beam_beam_modes.md:198-216 — "theory predicts NO detached mode; top y eigenvalue 0.2415 at the e-continuum edge" no longer matches the theory code's output — MEDIUM-HIGH (stale prediction)
Current eigen-solve (committed-code output result/eic_coherent_modes.tsv, Aug 3;
probe reproduces at NJ=40): y-plane top eigenvalue = 0.22432 with
in_e_continuum=false AND in_p_continuum=false — exactly one eigenvalue flagged
OUTSIDE both continua (band tops 0.2124 e / 0.2168 p, tol 0.002), i.e. the
current model predicts a (marginally) DETACHED y mode, not "top mode exactly at
the electron continuum edge" (old value 0.2415, old bands [0.14,0.24]).
The comparison script's header therefore states as "the theory prediction" a
claim the referenced theory script no longer produces. (The measured persistent
y line at 0.2109 arguably agrees BETTER with the new detached-mode prediction —
the text is stale, not the physics.)
Repro: `awk -F'\t' 'NR>1 && $7=="false" && $8=="false"' result/eic_coherent_modes.tsv`
→ one y row at 0.2243; probe_vlasov.jl prints band tops.

### U19-3 — validation/coherent_mode_vlasov_theory.jl:667-709 (EIC section) — x-plane EIC "continua" are computed in the quadrature regime self-check 4 declares non-quantitative; detuning u(J) reaches ~1.8-2.9 (unphysical, grid-dependent) — MEDIUM
The EIC x-plane has s_t = 12.75 um against in-plane sigmas ~100 um, i.e.
r ≈ 0.12-0.13 in witness units — inside the r <= 0.3 range where self-check 4
FAILS and the script itself warns values "must not be plotted or quoted"
(lines 506-511, and yokoya_vs_aspect_narrow.tsv header comment). Probe at NJ=40:
max u_e = 1.13, max u_p = 1.775; at NJ=72 (committed TSV) the top x eigenvalue
0.2549 is flagged inside the p continuum, which requires max u_p ≈ 2.9.
u(J) > 1 is unphysical (u(0)=1 is the analytic maximum) and grows with NJ — a
quadrature artifact that inflates the continuum bands used for the
inside/outside classification archived in result/eic_coherent_modes.tsv and
quoted by the theory note and README. The EIC section carries no cross-reference
to the failed self-check regime.
Repro: probe_vlasov.jl EIC lines; compare max eigenvalue vs Q_p + xi_p.

### U19-4 — five of six scripts cannot fail mechanically (the F7 lesson) — MEDIUM
- coherent_beam_beam_modes.jl:199-210 — prints Lambda only; zero assertions.
- coherent_mode_scans.jl:86-114 — prints + TSVs only.
- coherent_mode_eic_comparison.jl — prints + TSVs only (entire file).
- coherent_beam_beam_modes_beambeam3d.jl:50-68 — prints only; the "comparison"
  with Octopus is a hardcoded println of 1.199/1.206 etc. (lines 67-68), no
  tolerance is applied to anything.
- coherent_mode_vlasov_theory.jl — self-checks 4 and 5 print PASS/FAIL and
  @warn (499-511, 524-532) but never error/exit non-zero; self-checks 1-3
  (sigma-mode drift 536-544, xi-independence 552-555) print with NO tolerance
  at all. validation/README.md:676 ("Self-check 4 ... fails if the circular
  normalization returns") overstates: the script's exit code is 0 regardless.
Mitigation on record: CoherentModePhysicsContract (Contracts.jl:1420-1538) gates
the benchmark physics in the suite (lambda_band (1.12, 1.30),
sigma_mode_atol 2e-4; runtests.jl:7293-7300 asserts PIC passes AND gaussian
fails). Nothing gates the theory script's self-checks, the scans, or the EIC
comparison.
Repro: grep -n 'error\|exit\|@assert\|@test' on each script.

### U19-5 — validation/counter_rng_validation.jl:86-92 — gate passes a 3-round Philox; tail fractions computed but never gated; no known-answer vectors anywhere — LOW-MEDIUM
Probe (bit-exact reimplementation, verified == counter_uint64 at 10 rounds):
rounds=3 → gate ok=TRUE (mean -2.6e-4, var 1.001, corrs < 4e-3);
rounds=2/1 caught only because the output degenerates (var ~0, corr_nb = 1).
Philox4x32 needs 7+ rounds for Crush-quality output; the script cannot see the
difference between 3 and 10 rounds. tail2/tail3/tail4 are computed (57-58) and
printed with expected values (79-81) but are NOT in the `ok` conjunction
(86-92). No known-answer test exists in the script or the suite
(test/runtests.jl:135-144 checks only reproducibility/separation), so a silent
change to PHILOX4X32_ROUNDS or a multiplier constant that preserves coarse
moments passes everything. Single-point stream/turn separation checks (60-65)
do catch total-drop key bugs; key collisions are structurally unlikely
(splitmix-hashed XOR key, counter words disjoint — reviewed
src/math/counter_rng.jl:145-166). The script honestly self-describes as
"intentionally lightweight" (24-26), so this is a scope gap, not a false claim.
Repro: scratchpad/U19/probe_rng_weak.jl.

### U19-6 — validation/coherent_mode_vlasov_theory.jl:67-68 — header run-note stale on both counts: "needs only LinearAlgebra" (FFTW imported at line 396) and "~1-2 min at default resolution" (measured ≈8-10 min) — LOW
Warm timings on this host: simulate_1d_model 4096-turn default ≈ 8.4 s, box
case (L=192, ngrid=32768) ≈ 19 s; the main body makes 39 simulate_1d_model
calls (9 aspect + 10 narrow + 20 box) plus ~30 symmetric_Y (~0.6 s each) plus
self-check-4 loop and 2 EIC coupled solves → ≈ 8-10 min single-threaded, 4-8x
the claim. Both stale claims predate the referee-sim addition. Also line 711's
closing println lists 3 of the 5 TSVs the header (64-65) correctly lists.
Also lines 38-40 (self-check 3 description) still promise "reproducing the
literature anchors (~1.2 round, ~1.33 flat)" which the post-fix model does not
(1.162 round; flat side unconverged) — corrected only later in the same header
(56-62), leaving the header internally inconsistent.
Repro: timing probe transcript (this report's Coverage section, probe 2).

### U19-7 — validation/coherent_beam_beam_modes_beambeam3d.jl:29-30 + validation/README.md:667-669 — default reference is the uncommitted external checkout; neither points at the committed copy — LOW (provenance/discoverability)
Default rundir /cfs/ad/dxu/Library/BeamBeam3D/coherent_modes exists only on
this host. The raw centroids ARE committed at
paper/data/bb3d_decks/singleslice_fort.{24,25,34,35} (paper/README.md:171-176),
and I verified they reproduce the claimed values exactly — script output:
Lambda = 1.197 (x) / 1.210 (y), sigma drift 1.5e-6 / -3.8e-6 — matching
README:664 and the contract docstring. But the validation script's header and
README entry never mention the committed copy (which also needs renaming to
fort.24 etc.), so a fresh clone would conclude the cross-code anchor is
irreproducible. No mechanical comparison/tolerance either (see U19-4).
Repro: cp paper/data/bb3d_decks/singleslice_fort.24 <dir>/fort.24 (etc.);
julia --project=. validation/coherent_beam_beam_modes_beambeam3d.jl <dir>.

### U19-8 — validation/counter_rng_validation.jl:95 — WRITE_CSV output goes into validation/ (tracked, not gitignored), against AGENTS.md:336 "save summaries under result/" — INFO
joinpath(@__DIR__, "counter_rng_validation_summary.csv") writes into the
validation/ source directory; .gitignore covers only result/. Also
coherent_mode_eic_comparison.jl writes the dense 204 KB per-frequency
eic_mode_spectra.tsv by default (borderline vs "avoid writing dense per-case
data by default", though the overlay figure needs it).

### U19-9 — dead code weakening a stated independence claim — INFO
- coherent_mode_vlasov_theory.jl:401 — simulate_1d_model constructs a
  PlaneKernel `k` that is never used (force is spectral). The claim at 393-394
  "shares NO code with the matrix eigenproblem" is also slightly overstated:
  erfcx_pos (123-140) is shared by both solvers (kernel via PlaneKernel,
  referee via Ghat at 412) — a small common-mode failure channel.
- coherent_mode_eic_comparison.jl:53-57 — xi_of is defined, never called
  (the convoluted `3 - i == 2 ? 2 : 1` index is actually correct); xi_pair is
  what runs.

### U19-10 — validation/coherent_mode_vlasov_theory.jl:546-550 — SIGN_KERNEL auto-selection would silently compensate a kernel sign error — INFO
The script picks whichever sign puts the sigma mode nearer Q0 and proceeds;
combined with the unbounded sigma-drift print (U19-4), an assembly sign bug
would be absorbed, not flagged.

## Sound (verified good)

- Harmonic-limit self-check is real and tight: probe gives Y = 1.99998,
  assembled kernel vs closed form -sqrt(JJ')/2 max rel err 5.4e-15, sigma mode
  at Q0 to 1.2e-7 — it would bind hard on any assembly-constant regression
  (when someone reads the output; see U19-4).
- Self-check 4's exact target (1+r)/(1+sqrt2 r) is correct algebra; probe
  reproduces u0 = 0.826 at r=1 (exact 0.8284) within the 2e-2 tolerance, and
  the tolerance genuinely binds on the converged side.
- The referee sim's spectral kernel (erfcx form, line 412) matches the theory
  note's corrected FT (note lines 105-110); the 2026-07-28 correction is
  documented in both places.
- No circularity against the framework: the Vlasov script never loads Octopus —
  own quadratures, own erfcx, own eigen-solve; the referee particle solver uses
  a disjoint spectral force path (modulo shared erfcx_pos, U19-9).
- CoherentModePhysicsContract mirrors the benchmark faithfully (same constants,
  same seed 20260727, same estimator) and the suite asserts PIC passes, the
  soft-Gaussian FAILS, and the lambda ordering (runtests.jl:7293-7300).
- Measured-scan numbers quoted in README/theory-note conclusion 1 match
  result/yokoya_vs_aspect_measured.tsv and yokoya_vs_xi_measured.tsv exactly
  (1.188 round, 1.266 at r=0.09; xi scan 1.183/1.188/1.185/1.152).
- BB3D deck claim npart = 8.9141e9 reproduces xi = 0.005 analytically
  (4pi*gamma*sigma^2*xi/(r0*beta) = 8.914e9).
- Committed BB3D raw centroids reproduce Lambda = 1.197/1.210 through the
  script's own estimator (run verified, probe 4).
- RNG hygiene: every script seeds the global RNG explicitly at start;
  coherent_beam_beam_modes.jl reseeds per solver case (run_case:131) so cases
  are order-independent and solvers see identical beams; none depends on
  post-contract RNG state, and validate(CoherentModePhysicsContract) now
  saves/restores the global RNG (Contracts.jl:1511-1537).
- counter_rng_validation.jl is the one script with a real gate (line 117
  errors on failure) and it runs green end-to-end today (probe 5, rc=0).
- paper/data archives the post-fix theory TSVs bit-identical to a fresh
  result/ generation (diff rc=0) plus a three-seed converged-lambda
  re-measurement (1.199/1.206 etc.) backing the headline numbers.
- Run commands in all six headers/README are correct as written (verified for
  the two fast scripts by execution; syntax/paths checked for the rest).
