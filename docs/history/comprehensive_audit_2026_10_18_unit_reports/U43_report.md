# U43: validation: coherent modes, EIC emittance, high-energy limit, near-round transition

Tree under audit: `/cfs/ad/dxu/Library/Julia/Octopus` at commit 24e8683, read-only. No repository
file was modified and nothing was written under the repository's `result/`: every script that
writes files was executed from a scratch COPY under
`result/comprehensive_audit_2026_10_18/probes/U43/mirror/validation/` (so `@__DIR__` resolves
into `probes/U43/mirror/result/`), and the two scripts that write nothing
(`high_energy_weakstrong_limit.jl`, `near_round_gaussian_transition.jl`,
`coherent_beam_beam_modes_beambeam3d.jl`) were run in place. Hypotheses briefed: (1) reference
independence vs local reimplementation and table regeneration; (2) the near-round script
validates its instrument against the recorded defect before trusting a clean sweep (Phase 12);
(3) print-only gates.

## Region

| file | lines | read |
|---|---|---|
| `validation/coherent_mode_vlasov_theory.jl` | 948 | 1-948 |
| `validation/coherent_beam_beam_modes.jl` | 215 | 1-215 |
| `validation/coherent_mode_eic_comparison.jl` | 175 | 1-175 |
| `validation/eic_emittance_benchmark.jl` | 753 | 1-753 |
| `validation/high_energy_weakstrong_limit.jl` | 438 | 1-438 |
| `validation/near_round_gaussian_transition.jl` | 466 | 1-466 |
| `validation/plot_coherent_mode_theory.py` | 151 | 1-151 |
| `validation/coherent_mode_scans.jl` | 114 | 1-114 |
| `validation/coherent_beam_beam_modes_beambeam3d.jl` | 68 | 1-68 |

Total 3328 lines, every line read.

References read for comparison (outside the region): `docs/theory/coherent_beam_beam_modes.md`
1-450 (whole); `docs/theory/near_round_bassetti_erskine_switch.md` 1000-1150 (sections 10-11,
the validation record; sections 1-9 NOT read); the previous audit's
`docs/history/comprehensive_audit_2026_08_05_b_unit_reports/U22_report.md` 1-996 (whole);
`docs/comprehensive_audit.md` 561-586 (Phase 12); `test/runtests.jl` 8540-8720 (near-round
twin reference and testset), 21680-21741 (constants tripwire, near-round twin tripwire),
29200-29238 (high-energy testset); `src/contracts/Contracts.jl` 2000-2120
(`HighEnergyWeakStrongLimitContract`) and 2180-2320 (`CoherentModePhysicsContract`);
`src/tasks/BeamObservers.jl` 648-672 (retired `MomentObserver(path; ...)`);
`src/elements/strong_beam.jl` 940-963 (`_near_round_eta_bounds`, `_near_round_blend`) and the
`_gaussian_beambeam_kick_response` definition at 1285; `src/beam/Beam.jl` 29-55, 512-515;
`src/constants/Constants.jl` 11-20; `docs/history/todo_ledger_archive.md` 2695-2730 (the
2026-08-18 writer retirement); `validation/README.md` 1-30, 710-745, 975-1095, 1890-1935; the
first 250 diff lines of `validation/eic_emittance_benchmark.jl` against
`test/examples/strong_strong_tracking.jl` (the harness it was copied from).

## Provenance

READ line by line: the nine region files in full (ranges above) plus the references listed.

EXECUTED (all logs under `/cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U43/`):

1. `logs/vlasov_full.log` — full default run of a scratch copy of
   `coherent_mode_vlasov_theory.jl` (`julia --project=... --threads=4`, 7 min 32 s wall /
   733 s CPU, rc=0, "all self-checks PASS"). Five TSVs regenerated into `mirror/result/`. Every
   number the theory note §3/§4 and U22 quote reproduces (Clean 1).
2. `logs/probe_vlasov_quick.log` (`probe_vlasov_quick.jl`) — LIB_ONLY include of the copy:
   `erfcx_pos` against `SpecialFunctions.erfcx` (max rel. err. 2.871e-9 at z = 1.0000; 1e-16
   for z < 1 and z >= 2); self-check 4 standalone at the 11 shipped aspect ratios (all PASS,
   max |u(0) - exact| = 4.76e-4 at r = 5, max relative 6.4e-4; rigid diagnostic 1.000000 to
   1.000253). Its part 3 died with `UndefVarError: EMASS` because the EIC constants sit inside
   the LIB_ONLY guard — moved to probe 3.
3. `logs/probe_eic_normalization.log` (`probe_eic_normalization.jl`) — the EIC coupled solve
   with the shipped normalizer (`sigma_o = s_t/sqrt2`) against the same solve with the source's
   own other-plane sigma, constants read from the script text by the suite's regex (LEAD U43-3).
4. `logs/near_round_defaults.log` — `near_round_gaussian_transition.jl` in place at defaults
   (75 s, rc=0; Float64 force rel 6.1096e-12, response rel 1.2449e-8, symplectic 1.6001e-10,
   observed conditioning 61.937 / 4.948, CUDA parity 1.33e-11 / 1.15e-5).
5. `logs/probe_near_round_injection.log` (`probe_near_round_injection.jl`) — Phase 12: the
   script's own sweep with a more-specific method of `Octopus._gaussian_beambeam_kick_response`
   installed in the session that multiplies the evaluator by 1.1 over a chosen blend window
   (LEADs U43-4, U43-5).
6. `logs/high_energy_defaults_cuda.log` — `high_energy_weakstrong_limit.jl` in place at defaults
   with `OCTOPUS_HIGH_ENERGY_SPECTRAL_CUDA=1` (108 s, rc=0, all four `*_passed` true; numbers in
   Clean 4).
7. `logs/eic_emittance_tiny.log`, `mirror/result/eic_emit_tiny.tsv` — scratch copy of
   `eic_emittance_benchmark.jl` with `OCTOPUS_TURNS=2 OCTOPUS_N_MACRO=200`, CPU (45 s, rc=0):
   `MESHSCAN ... pro_ex_growth_pct=0.0 pro_ey_growth_pct=0.0 ele_ex_growth_pct=0.0
   ele_ey_growth_pct=0.0` while its own TSV records ele_ex 2.0390e-8 -> 2.2197e-8 (LEAD U43-2).
8. `logs/cbb_tiny.log` — scratch copy of `coherent_beam_beam_modes.jl` with
   `OCTOPUS_CBB_TURNS=8 OCTOPUS_CBB_N_MACRO=200 OCTOPUS_CBB_SOLVERS=gaussian`: rc=1,
   `ArgumentError: the standalone moment file writer was retired (2026-08-18)` thrown from
   `run_case` (LEAD U43-1).
9. `logs/bb3d_run.log` — `coherent_beam_beam_modes_beambeam3d.jl` in place against its default
   run directory (exists on this host): Lambda = 1.197 / 1.21, sigma drift 1.5e-6 / -3.8e-6.
10. `mirror/result/{yokoya_vs_aspect,yokoya_vs_xi,eic_coherent_modes}.png` —
    `plot_coherent_mode_theory.py` (copy) run with `/usr/local/anaconda3/bin/python3` against
    the regenerated TSVs; three figures written, Figure 4 skipped by design (no
    `eic_mode_spectra.tsv`). The y panel of `eic_coherent_modes.png` was inspected (LEAD U43-6).
11. `logs/eic_comparison_defaults.log` — scratch copy of `coherent_mode_eic_comparison.jl` at
    defaults (4096 turns, 20k/beam): see the addendum at the end of this report.

NOT executed: `coherent_mode_scans.jl` (12 min of PIC at defaults; U22 ran it at defaults and
found the flat rows drift at 1e-3 from outside the region — nothing in it changed since, by
the `grep` in U22 and by reading). The full `coherent_beam_beam_modes.jl` cannot run at HEAD
(U43-1), so its headline numbers were not re-measured.

## Leads

### LEAD U43-1 [Major, confidence high] validation/coherent_beam_beam_modes.jl:161-164
Claim: The "community-standard physics acceptance test" cannot run at HEAD — `run_case`
constructs `MomentObserver(path1; orders = 1:1, capacity = config.turns + 1)`, the standalone
moment-file writer that was retired on 2026-08-18 and now throws, so every solver case aborts
before tracking and the documented run command (`validation/README.md:1018`) exits 1.
Mechanism: `src/tasks/BeamObservers.jl:658-665` keeps `MomentObserver(path::AbstractString;
...)` only as a throwing migration pointer ("construct MomentObserver(; name=..., ...) as a view
into the task's artifact=RunArtifact(path; ...) and read it back with MomentOutput(path;
name=...)"). The 2026-08-18 retirement migrated "six validation scripts"
(`docs/history/todo_ledger_archive.md:2726-2729`) but not this one — it is the only remaining
caller of the path form (`grep -rn "MomentObserver([a-z_0-9]*path" validation/ examples/
test/examples/` returns exactly these two lines). Nothing exercises the script: the suite runs
`CoherentModePhysicsContract` (which loops `execute!` per turn and reads `beam.rep.x`, so it is
unaffected), `validation/README.md:978-1020` and the contract docstring
(`src/contracts/Contracts.jl:2195`) present the script as the runnable benchmark the contract
"mirrors", and the header's "First-run headline" numbers can no longer be regenerated. This is
drift of a hand-maintained caller after an API retirement (defect class 2) and a check that
no longer executes (class 1 / "a check only counts while it executes"). The read side
(`MomentOutput(path1)` + `read(m1, Moment(; x = 1))`) would need the `name=` form too.
Repro: `OCTOPUS_CBB_TURNS=8 OCTOPUS_CBB_N_MACRO=200 OCTOPUS_CBB_SOLVERS=gaussian julia
--project=. --threads=4 validation/coherent_beam_beam_modes.jl` → `ERROR: LoadError:
ArgumentError: the standalone moment file writer was retired (2026-08-18) ...` from `run_case`,
exit 1 (measured, `probes/U43/logs/cbb_tiny.log`); `grep -n "MomentObserver(path"
validation/coherent_beam_beam_modes.jl` → 2 hits.

### LEAD U43-2 [Moderate, confidence high] validation/eic_emittance_benchmark.jl:693-701
Claim: The `MESHSCAN` receipt's four emittance-growth percentages are identically zero by
construction — the "before" and "after" emittances are both evaluated on the final beam state,
after the single `execute!`.
Mechanism: `_e0 = _emit(beam_pro); _ele0 = _emit(beam_ele)` (line 693) and `_e1 =
_emit(beam_pro); _ele1 = _emit(beam_ele)` (lines 694-695) are all computed after
`execute!(task, ...; turns = turns)` (line 686), so `100*(_e1[1]/_e0[1] - 1)` is 0.0 for every
grid, seed, damping and turn count. The initial emittances that would make the line meaningful
exist (`_ele_i`, `_pro_i`, line 685, written to the TSV) and are not used by it. A diagnostic
named for a mesh scan that cannot see the quantity it reports (class 15), silently (class 6).
Repro: `OCTOPUS_TURNS=2 OCTOPUS_N_MACRO=200 julia --project=. --threads=4
validation/eic_emittance_benchmark.jl` → `MESHSCAN seed=1 grid=128 damp=100.0 turns=2
pro_ex_growth_pct=0.0 pro_ey_growth_pct=0.0 ele_ex_growth_pct=0.0 ele_ey_growth_pct=0.0`, while
the run's own `eic_emit_octopus_matched.tsv` shows `ele_ex` 2.0390e-8 (turn 0) → 2.2197e-8
(turn 2), i.e. +8.9% (measured, `probes/U43/logs/eic_emittance_tiny.log`,
`probes/U43/mirror/result/eic_emit_tiny.tsv`). (Run from a copy outside the repo: the script
writes `result/pic_hcc.h5` beside itself.)

### LEAD U43-3 [Moderate, confidence med] validation/coherent_mode_vlasov_theory.jl:356-361
Claim: For unequal beams the normalizing on-axis gradient is built from `sigma_o = s_t/sqrt2`
— the rms mean of BOTH beams' other-plane sigmas — although the comment four lines above and
the `xi_bb` definition (lines 862-863) both specify the SOURCE's own sizes; the two coincide
only in the symmetric case, so the EIC table's detuning scale is off by about 5% in the y
plane.
Mechanism: `analytic_gradient(s_src) = 1/(s_src (s_src + sigma_o))` with `sigma_o = s_t /
sqrt(2.0)` is applied as `N01 = analytic_gradient(scale2) * scale1^2` (beam 1 kicked by 2) and
`N02 = analytic_gradient(scale1) * scale2^2`. The comment justifying `s_t/sqrt(2)` ("one beam's
is s_t/sqrt(2)") holds only for equal beams. In the EIC y plane s_t/sqrt2 = 100.66 µm against
the proton's 95 µm (electron kicked by proton) and the electron's 106 µm (proton kicked by
electron), so `N01` is 0.948x and `N02` 1.049x the source-sized values; `u(J) ∝ 1/N0` and the
cross kernels scale the same way, so the electron's effective detuning/coupling is inflated
5.5% and the proton's deflated 4.6%. `xi_e`, `xi_p` are computed with the source's own sizes, so
the eigenproblem's `Q + xi·u` mixes two conventions (class 9). The symmetric tables are
unaffected; only `eic_coherent_modes.tsv`, the note's §4 table and the comparison script's
header numbers inherit it. Which normalizer is intended is the owner's call — the lead is that
the code, its comment and `xi_bb` disagree for the one case where it matters.
Repro: `julia --project=. --threads=4
result/comprehensive_audit_2026_10_18/probes/U43/probe_eic_normalization.jl` → y plane: as
shipped max u_e/u_p = 0.7227/0.7248, e-band top 0.21254, discrete mode 0.22432,
(Q−Q_e)/ξ_e = 0.840, (Q−Q_p)/ξ_p = 1.523; with the source's own other-plane sigma
0.6853/0.7600, 0.20879, 0.22377, 0.835, 1.464 (exact small-amplitude ratios
(σ_s+s_t/√2)/(σ_s+s_t) = 0.7236/0.7254 vs (σ_s+σ_s,other)/(σ_s+s_t) = 0.6862/0.7607); x plane
moves ≤ 4e-4 (0.23795 → 0.23798), conclusions unchanged in both planes.

### LEAD U43-4 [Moderate, confidence high] validation/near_round_gaussian_transition.jl:443-465
Claim: Of the roughly fifteen metrics the script computes, three are gated (Float64 force and
response maxima, the conditioning ratio for both types, plus CUDA parity when a GPU exists);
the endpoint continuity gaps, the core-gradient error, the symplectic residual, the
transition-only errors and every Float32 error are print-only — and the continuity gaps are the
only instrument that sees the first and last few percent of the blend interval.
Mechanism: the gates at lines 443-452 and 459-465 test `observed/nominal` conditioning,
`f64.max_force_relative_error < 2.0e-11`, `f64.max_response_relative_error < 4.0e-8` and
parity; `_continuity_metrics` (lines 70-141), the core gradient (264-278) and
`_transition_symplectic_residual` (149-169) are printed by `print_near_round_transition_result`
and never asserted, although the header lists them as the script's metrics and the theory
note's §10.2 table is built from them. The main sweep samples the blend at t = k/18
(k = 1..17), so t ∈ (0, 0.056) and (0.944, 1) are covered only by the ±h, ±2h continuity
probes (h = 0.01·η_b) — whose result is not gated (hypothesis 3; class 1). The suite's
"Near-round Gaussian transition" testset gates force/response at five η values and the
symplectic residual but not the endpoint continuity either.
Repro: `julia --project=. --threads=4
result/comprehensive_audit_2026_10_18/probes/U43/probe_near_round_injection.jl` → a x1.1
evaluator error confined to t ∈ [0.01, 0.04] (4356 Float64 evaluations hit) leaves every gated
number at its baseline (force_rel 6.1096e-12, response_rel 1.2449e-8, core 2.22e-16) and shows
only as `inner_continuity.force_value_gap` 1.770e-15 → 1.000e-1; the same error at
t ∈ [0.96, 0.99] shows only as `outer_continuity.force_value_gap` 9.469e-13 → 2.000e-1. A run
with either defect present exits 0 (`probes/U43/logs/probe_near_round_injection.log`).

### LEAD U43-5 [Moderate, confidence med] validation/near_round_gaussian_transition.jl:173-185
Claim: The Phase-12 instrument validation this script relies on exists only as a comment
describing a one-off measurement whose recorded magnitude does not match its recorded defect;
nothing in the script or the suite re-feeds the recorded defect to the sweep, so the clean
sweep is trusted on the strength of an unreproducible record.
Mechanism: the comment records that injecting "a x1.1 evaluator error over t in [0.30, 0.40]"
left the old sweep bit-identical while "the same injection at t in [0.45, 0.55] was caught at
1.0000e-03". A x1.1 error is a 10% relative error: measured against the current sweep both
windows report 1.0000e-01, not 1.0000e-03 (the recorded number corresponds to a x1.001
injection, or to a different quantity). The 17 interior points were then justified by a
sampling argument ("a sample within 0.03 of every t"), not by re-running the injection. The
protocol's Phase 12 asks that the metric be fed the recorded defect at its recorded magnitude
and checked; here the record cannot be re-executed from what is written (class 13). The fix
itself works — the current sampling does catch the recorded window (same probe, 67080 hits,
1.0000e-01 in both Float64 and Float32) — which is what makes the gap a process defect rather
than a physics one.
Repro: `grep -n "caught at 1.0000e-03" validation/near_round_gaussian_transition.jl` → 1 hit;
`julia --project=. --threads=4
result/comprehensive_audit_2026_10_18/probes/U43/probe_near_round_injection.jl` → "x1.1
injected at t in [0.30, 0.40]" force_rel = 1.0000e-01 and "[0.45, 0.55]" force_rel =
1.0000e-01 for both arithmetic types; no `inject`/`known defect` harness exists in the script
(`grep -n "inject" validation/near_round_gaussian_transition.jl` → comment lines only).

### LEAD U43-6 [Moderate, confidence high] validation/plot_coherent_mode_theory.py:100-110 (and validation/coherent_mode_eic_comparison.jl:101-104,159-168)
Claim: The overlay figure and the comparison script draw the "incoherent continua" as
[Q, Q+ξ] while the theory TSV they plot classifies eigenvalues against [Q, Q+ξ·max u]; in the
regenerated `eic_coherent_modes.png` the green "discrete (undamped) modes" marker at 0.22432
is drawn inside the blue shaded electron continuum, so the figure contradicts its own legend
(carried from U22's provenance table item 8, unchanged at HEAD).
Mechanism: `plot_coherent_mode_theory.py:100-103` shades `axvspan(q_e, q_e + xi_e)` and
`:106-107` marks as discrete the rows whose `in_e_continuum`/`in_p_continuum` are "false" —
columns the theory script computes with the band top `Q_e + xi_e·maximum(res.u1)` plus a
0.02·ξ tolerance (`coherent_mode_vlasov_theory.jl:878-889`). For the y plane the shaded band
ends at 0.140 + 0.1004 = 0.2404 and the classified band at 0.2125 (max u = 0.7227), so the one
detached mode at 0.22432 lies between them. `coherent_mode_eic_comparison.jl:101-104` prints
and `:159-168` classifies with the same full-ξ bands ("theory continua y: e (0.14, 0.2404)"),
so the comparison's "in e-band" verdicts for a line near 0.224 would also disagree with the
theory TSV. One quantity, two conventions across the producer and both consumers (class 9).
Repro: regenerate `result/eic_coherent_modes.tsv` (or use
`probes/U43/mirror/result/`), then `awk -F'\t' 'NR>1 && $7=="false" && $8=="false"'
result/eic_coherent_modes.tsv` → one row, plane y, eigenvalue 0.22432320002385767, and
`awk -F'\t' 'NR>1 && $1=="y" {print $2+$3; exit}'` → 0.240381; run
`validation/plot_coherent_mode_theory.py` and look at the y panel of
`result/eic_coherent_modes.png` (archived: `probes/U43/mirror/result/eic_coherent_modes.png`).

### LEAD U43-7 [Minor, confidence high] validation/coherent_mode_vlasov_theory.jl:33-39
Claim: The header still says "only one condition stops it (the kernel-sign criterion ...)" and
that failing self-checks "do not exit nonzero", while the body (lines 560-569, 930-946) makes
the run FAIL at the end on any self-check failure or not-a-mode row; two sibling claims are
stale the same way.
Mechanism: the end gate (`SELF_CHECK_FAILURES`, `error(message)` unless
`OCTOPUS_VLASOV_ALLOW_SELF_CHECK_FAILURE=1`) was added after the header paragraph was written
(the body cites U22-11) and the header was not revised. Line 775 writes into
`yokoya_vs_aspect_narrow.tsv` "Self-check 4 passes throughout this range (it fails only for
r <= 0.3)" — measured: self-check 4 PASSES at all 11 aspect ratios (max |u(0) − exact|
4.8e-4), and had it failed the run would now abort, so the TSV comment describes the
pre-U22-1 state. Lines 74-75 say the rigid diagnostic "measures 1.0000-1.0085 across the scan";
it now measures 1.0000-1.0003. `validation/README.md:1042-1049` repeats the "one hard stop"
claim (seam, outside the region) and says "All four coherent-mode scripts" while listing five.
Documentation as claims about behaviour the code no longer has (class 14).
Repro: `julia --project=. --threads=4 validation/coherent_mode_vlasov_theory.jl` (from a copy)
→ eleven `PASS` lines under "Self-check 4", `rigid=1.0`/`1.0003`/`1.0001`, and the closing
`all self-checks PASS`; `grep -n "do not exit nonzero\|fails only for r <= 0.3\|1.0000-1.0085"
validation/coherent_mode_vlasov_theory.jl` → 3 hits; `grep -n "error(message)"
validation/coherent_mode_vlasov_theory.jl` → the gate.

### LEAD U43-8 [Minor, confidence high] validation/coherent_mode_eic_comparison.jl:9-19
Claim: The header's x-plane prediction quotes the retracted numbers ("top mode 0.25488 at the
electron-continuum edge") and its "therefore both beams' centroid responses should be
Landau-damped ... no persistent narrow lines" conclusion contradicts both its own y-plane
bullet (one detached mode) and the measurement the note records (a persistent line at 0.2109).
Mechanism: the 2026-08-06 correction (U22-3) moved the x-plane top mode to 0.23795 at the
PROTON edge ((Q−Q_p)/ξ_p = 1.06) after the quadrature repair; the header's y bullet was updated
(U19-2) but the x bullet and the "therefore" sentence that followed from "no detachment in
either plane" were not. The regenerated TSV gives top x eigenvalue 0.23795 (class 14).
Repro: `grep -n "0.25488\|electron-continuum edge\|therefore both beams"
validation/coherent_mode_eic_comparison.jl` → 3 hits; `awk -F'\t' 'NR>1 && $1=="x" {if($6>m)
m=$6} END{print m}' result/eic_coherent_modes.tsv` → 0.23795221412154816.

### LEAD U43-9 [Minor, confidence high] validation/eic_emittance_benchmark.jl:697
Claim: The `MESHSCAN` receipt prints `damp=` from `SST_DAMP` (default "100.0"), a variable
nothing in the script reads, while the run's radiation damping is the hard-coded
`radiation_damping_turns = (400.0, 400.0, 200.0)` (line 191).
Mechanism: a receipt line that reports an unread environment variable asserts a configuration
the code never consumed — the inverse of "assert what the run recorded" (class 11). The default
"100.0" is also not the 400 the header documents.
Repro: `grep -n "SST_DAMP" validation/eic_emittance_benchmark.jl` → exactly one hit (the
print); the tiny run prints `damp=100.0` (`probes/U43/logs/eic_emittance_tiny.log`) with
`radiation_damping_turns = (400.0, 400.0, 200.0)` in the config.

### LEAD U43-10 [Minor, confidence high] validation/eic_emittance_benchmark.jl:30-159
Claim: The benchmark is a frozen copy of `test/examples/strong_strong_tracking.jl` that
carries that harness's entire header verbatim (run command `julia --project=.
test/examples/strong_strong_tracking.jl`, "Output is written to `test/result/`",
`test/result/pic_hcc.h5`) under its own header, and did not receive the harness's later fixes.
Mechanism: `diff validation/eic_emittance_benchmark.jl test/examples/strong_strong_tracking.jl`
shows the harness gained `env_bool` (U21-15/16: an unrecognised boolean silently disabled
default-on switches, and `OCTOPUS_USE_GPU` alone used `== "1"` so `=true` ran on CPU),
`OCTOPUS_RESULT_DIR`, the `OCTOPUS_MP` refusal and the MPI arm; the copy still uses `get(ENV,
"OCTOPUS_USE_GPU", "0") == "1"` (line 244) beside `in ("1", "true", "TRUE", "yes", "YES")`
for every other switch (lines 266-365). Hand-copied knowledge drifting (class 2) plus a header
describing a different file (class 14). The documented run command (`OCTOPUS_USE_GPU=1`) uses
the accepted spelling, so the default path is unaffected.
Repro: `grep -n "test/examples/strong_strong_tracking.jl\|test/result" validation/eic_emittance_benchmark.jl
| wc -l` → 20+ hits inside the validation script; `grep -n 'OCTOPUS_USE_GPU", "0") == "1"'
validation/eic_emittance_benchmark.jl` → 1 hit while the harness has none.

### LEAD U43-11 [Minor, confidence high] validation/eic_emittance_benchmark.jl:170,601-605
Claim: The moment schedule stops at the hard-coded `total_turns = 50000` while the run length
comes from `OCTOPUS_TURNS`, so a run longer than 50000 turns silently stops recording moments.
Mechanism: `EveryNSteps(; start = ..., stop = input.total_turns, step = ...)` is independent
of `turns = parse(Int, get(ENV, "OCTOPUS_TURNS", "2"))`; nothing checks `turns <=
input.total_turns`. The documented 8192-turn run is inside the cap, so this is inert today
(class 6).
Repro: `grep -n "total_turns" validation/eic_emittance_benchmark.jl` → the constant and the
schedule `stop`; no comparison against `turns`.

### LEAD U43-12 [Minor, confidence high] validation/high_energy_weakstrong_limit.jl:395-397
Claim: The soft-Gaussian and PIC arms never assert that the infinite-energy electron beam is
unchanged — `gaussian_electron_max_abs_change` is computed (line 347) and reported but absent
from `gaussian_passed`, and the PIC arm has no electron check at all — while the spectral twin
asserts `electron_change <= limit_atol` (lines 242-244); the header also calls the Gaussian
reference a comparison "against a frozen-source weak-strong reference" where the contract
docstring (`Contracts.jl:2004-2020`) correctly says both sides share their arithmetic.
Mechanism: `gaussian_passed = gaussian_proton_error <= gaussian_atol && gaussian_lum_rel <=
gaussian_lum_rtol` (hypothesis 3: a computed, printed, ungated quantity). Measured at defaults
the electron change is 5.42e-20 and the Gaussian luminosity error exactly 0.0 — the gate is
missing, not failing; the 0.0 is the same-arithmetic comparison the docstring admits.
Repro: `grep -n "gaussian_passed=" -A 2 validation/high_energy_weakstrong_limit.jl` → no
`electron` term; `julia --project=. validation/high_energy_weakstrong_limit.jl` →
`gaussian_electron_max_abs_change = 5.421010862427522e-20`,
`gaussian_luminosity_relative_error = 0.0` (`probes/U43/logs/high_energy_defaults_cuda.log`).

### LEAD U43-13 [Minor, confidence high] validation/high_energy_weakstrong_limit.jl:79-80
Claim: The default spectral grid `(128, 1024)` is one the spectral solver itself warns against
— every default run emits four "spectral mesh width makes the DST slow ... suggested_points =
127 / 1023" warnings — and the README already notes the recommended grid is `(127, 383)`.
Mechanism: a hard-coded default that contradicts the solver's own guidance
(`src/tasks/strongstrong/spectral.jl:441`) and the documented recommendation
(`validation/README.md:723-726`); correctness is unaffected (the arm passes), the cost is run
time and noise in the log (class 14/15).
Repro: `julia --project=. validation/high_energy_weakstrong_limit.jl 2>&1 | grep -c "DST
slow"` → 4.

### LEAD U43-14 [Minor, confidence high] validation/coherent_mode_vlasov_theory.jl:900-910
Claim: The "highest mode near e-band" diagnostic selects `v <= e_band[2] + 5*xi_e`, a window
(0.44 in x) wider than the whole span between the two bands (0.148), so it never excludes
anything and prints the proton-edge mode as "(Q − Q_e)/ξ_e = 1.791" — a ratio with no meaning.
Mechanism: the filter was meant to find the top of the electron sector; with 5·ξ_e it returns
`maximum(vals)` in both shipped planes, so the printed ratio measures the proton-edge mode
from the electron tune (the successor of the "1.98" U22-3 called a tautology). A diagnostic
that cannot see what it names (class 15); print-only.
Repro: run the script → `highest mode near e-band: 0.23795 -> (Q - Q_e)/xi_e = 1.791` and
`highest mode overall: 0.23795` in the x plane (`probes/U43/logs/vlasov_full.log`).

### LEAD U43-15 [Minor, confidence high] validation/plot_coherent_mode_theory.py:40-47
Claim: Figure 1 plots every row of `yokoya_vs_aspect.tsv` as a Yokoya factor; the `is_mode`
and `mesh_ok` columns the theory script writes "for the figure pipeline" are consumed by
nothing, so a not-a-mode row (written before the end gate fires, or under
`OCTOPUS_VLASOV_ALLOW_SELF_CHECK_FAILURE=1`) would be plotted although the script says such
rows "must not be plotted or quoted".
Mechanism: `fnum(theory, "Y_m1_matrix")` over all rows; `coherent_mode_vlasov_theory.jl:703-709`
states the 1/0 columns exist so downstream can act on the verdict. Inert today (all nine rows
are modes; measured) — the gate's verdict does not reach its consumer (class 1/14).
Repro: `grep -n "is_mode\|mesh_ok" validation/plot_coherent_mode_theory.py` → 0 hits.

### LEAD U43-16 [Minor, confidence high] docs/theory/near_round_bassetti_erskine_switch.md:1067-1084 (reference, outside the region)
Claim: The §10.1 results table ("The run on 2026-07-30 produced") and the §11 bound
("transition-force errors of ... 4.8e-6 or less in Float32 over the declared scan") no longer
match the script's declared scan: six cells differ, and the Float32 bound is exceeded.
Mechanism: the sweep gained 17 interior blend samples (U23-3), so maxima are now attained
inside the blend rather than at its outer endpoint; measured at defaults: Float32 transition
force relative 5.4797e-6 (table 4.7557e-6), Float32 force natural 1.1852e-6 (8.4271e-7),
Float32 response natural 1.7500e-5 (1.4771e-5), Float32 response relative 3.0642e-3
(1.7781e-3), Float64 force natural 9.8139e-14 (6.3707e-14), Float64 response natural
3.9900e-11 (3.1170e-11). The old "transition response natural" values equal the current
"outer exact response natural-scale error" (1.4771e-5 / 3.1170e-11), which is how the drift
identifies itself. The §10.2 continuity table, the core gradients, the symplectic residual
and the CUDA parity reproduce exactly (class 14). Out-of-hypothesis.
Repro: `julia --project=. validation/near_round_gaussian_transition.jl` → the Float32 line
`transition-only max force relative error = 5.479682906508171e-6` against the note's
4.7557e-6 (`probes/U43/logs/near_round_defaults.log`).

### LEAD U43-17 [Minor, confidence high] validation/coherent_beam_beam_modes_beambeam3d.jl:67-68 (and validation/coherent_beam_beam_modes.jl:56)
Claim: Two U22 observations are unchanged at HEAD — the cross-code "comparison" is a
`println` of a hard-coded string literal (U22-12), so nothing connects the BeamBeam3D Lambda
to the Octopus numbers, and the benchmark header's "~10-20 min at defaults" is understated by
roughly 3x (U22 measured ≥ 60 min).
Mechanism: carried forward; both are documentation-as-claims (class 14). The literal now also
quotes a benchmark that cannot run (U43-1).
Repro: `grep -n "PIC 1.199/1.206" validation/coherent_beam_beam_modes_beambeam3d.jl` → the
literal; `julia --project=. validation/coherent_beam_beam_modes_beambeam3d.jl` → Lambda
1.197 / 1.21 (measured, `probes/U43/logs/bb3d_run.log`).

### LEAD U43-18 [Minor, confidence med] test/runtests.jl:29223-29233 (seam, outside the region)
Claim: The suite runs `run_high_energy_weakstrong_limit` with model tolerances of 0.60 (PIC)
and 0.80 (spectral) at n=256, 3 slices, grid 48 — tolerances that can only fail on a gross
defect, so the suite's "High-energy weak-strong strong-strong limit" testset gates the limit
arms (5e-12) but effectively only smoke-tests the model arms.
Mechanism: the script's own defaults are 0.08 and the measured model errors at defaults are
0.30-0.64% (luminosity) and 0.008-0.18% (size), so the suite's values are 100x the measured
error at the script's resolution; whether 0.6/0.8 is reasonable at n=256 was not measured here
(class 8, tolerance widened to the resolution rather than the floor). Seam for the auditor.
Repro: `sed -n '29223,29233p' test/runtests.jl` → `pic_luminosity_rtol=0.60, pic_size_rtol=0.60,
spectral_model_luminosity_rtol=0.80, spectral_model_size_rtol=0.80`;
`probes/U43/logs/high_energy_defaults_cuda.log` → `pic_luminosity_relative_error =
0.003010079459429147`.

## Clean

1. **The Vlasov tables regenerate exactly (hypothesis 1).** A full default run of the script
   (copy, 7 min 32 s wall, rc=0, "all self-checks PASS") reproduces every number the theory
   note §3 and §4 and the U22 report quote: `Y_m1_matrix` 1.3211 / 1.3082 / 1.2898 / 1.2604 /
   1.2380 / 1.2060 / 1.1842 / 1.1719 / 1.1620 and `Y_1d_sim` 1.2971 / 1.2893 / 1.2736 / 1.2462
   / 1.2233 / 1.1899 / 1.1674 / 1.1528 / 1.1427 at r = 0.02 ... 1.0 (note §3: 1.321/1.308,
   1.290, 1.260/1.238, 1.206, 1.184, 1.172, 1.162; 1.297/1.289, 1.274, 1.246/1.223, 1.190,
   1.167, 1.153, 1.143); max u 0.9901 → 0.8273 (note: 0.990 → 0.827); mode gap 0.327-0.335
   (note: ≈ 0.33); sigma drift −2.86e-4 / −1.29e-4 at r = 0.02 / 0.05 flagged `mesh_ok=0`
   (note: 2.9e-4, 1.3e-4, mesh-limited) and ≤ 6.9e-5 elsewhere; narrow branch 1.1394 / 1.1257 /
   1.1099 / 1.0956 / 1.0824 / 1.0772 / 1.0733 / 1.0719 / 1.0708 at r = 1.5 ... 500 (U22 Clean 2:
   1.1394 / 1.1099 / 1.0956 / 1.0824; r = 500 1.0708); box convergence to 0.12% (r=1), 0.03%
   (r=11.111), 0.20% (r=50) at L=192 (U22 Clean 7); `yokoya_vs_xi_theory.tsv` 1.2093862 /
   1.2196884 / 1.2434387 at ξ = 0.005 / 0.01 / 0.02 (note §3 correction block: 1.2094,
   1.2434); EIC x: e [0.080, 0.1650], p [0.228, 0.2371], none detached, top 0.23795,
   (Q−Q_p)/ξ_p = 1.062; EIC y: e [0.140, 0.2125], p [0.210, 0.2168], one mode 0.22432,
   0.840 / 1.523 (note §4 table, to its quoted digits). No committed copy of the TSVs exists in
   this repository (the paper data moved to its own repository, `validation/README.md:1905`),
   so "committed" here means the note's tables and U22's recorded numbers.
2. **The self-checks bind and pass with margin.** Self-check 4: all 11 rows PASS, max
   |u(0) − (1+r)/(1+√2 r)| = 4.8e-4 (r = 5), relative ≤ 6.4e-4 against a 2e-2 tolerance (the
   note's "better than 0.2%" holds at 0.064%); the rigid diagnostic is 1.000000-1.000253
   (analytic 1). Self-check 5: kernel vs closed form 1.18e-14, q_σ − Q0 = 1.25e-7,
   (q_π − Q0)/ξ = 1.999988, Λ = 1.999975 — and it now drives `kernel_matrix_potential`, the
   production assembly, not a copy (U22-4 closed; verified by reading lines 308-330, 426).
   Sign selector: drift/ξ = −1.14e-5 for +1 against 1.16 for −1, 9x inside the 1e-4 criterion.
   ξ-independence: Y(ξ) = Y(2ξ) = 1.162. The per-row invariants (max u ≤ 1 + 1e-3, gap ≥ 0.02,
   drift ≤ 1e-4) are evaluated on every aspect row and feed the end gate (lines 697-763,
   930-946): the U22-1/U22-11 repairs are in place and executed.
3. **`erfcx_pos` is adequate for its use.** Against `SpecialFunctions.erfcx` the max relative
   error is 2.871e-9 at z = 1.0000 (the continued-fraction side's worst point), 1e-16 for
   z < 1 and z ≥ 2, 1.9e-13 at 1.5; four to five orders below the 1e-4 precision at which the
   tables are quoted.
4. **The high-energy limit holds at defaults, CUDA arm included.** `gaussian_passed`,
   `pic_passed`, `spectral_limit_passed`, `spectral_model_passed` all true (108 s):
   Gaussian proton max abs error 5.42e-20, luminosity error 0.0 (same arithmetic both sides, as
   the contract docstring states); PIC luminosity error 3.01e-3 and size error 8.50e-5 against
   0.08; spectral grid (128,1024) limit errors 1.08e-19 abs / 7.4e-16 rel luminosity, model
   errors 3.29e-3 / 1.29e-4; grid-free (48,48) limit 1.08e-19 / 0.0, model 6.38e-3 / 1.82e-3;
   CUDA spectral grid vs the CPU frozen-source reference 1.36e-19 abs, 1.3e-15 rel luminosity
   against 5e-13 / 1e-12. The suite's reduced-settings call at 29221-29238 and the contract's
   `_wsl_*` helpers mirror the script's `weakstrong_limit_reference!` line for line (read).
5. **The near-round sweep is green at defaults and its continuity record reproduces.** Float64
   force rel 6.1096e-12 (< 2e-11), response rel 1.2449e-8 (< 4e-8), observed/nominal
   conditioning 61.937/64 = 0.968 and 4.948/8 = 0.619 (inside 0.4-2.5), CUDA parity 1.33e-11 /
   1.15e-5 (< 5e-11 / 4e-5), symplectic residual 1.6001e-10; the §10.2 continuity table of the
   theory note reproduces to every quoted digit (Float32 inner 7.7843e-7 / 6.9510e-7 /
   7.9523e-5 / 7.8000e-5, outer 2.9019e-6 / 2.2866e-5 / 3.7581e-4 / 4.5829e-3; Float64 inner
   1.5779e-15 / 1.2439e-14 / 1.5682e-13 / 2.2658e-13, outer 1.6606e-13 / 4.6786e-11 /
   1.6423e-11 / 4.6862e-9). The script's own `_transition_reference` agrees with the suite's
   twin to ≤ 1e-18 (suite tripwire at 21707-21741, read). The current sampling catches the
   recorded x1.1 defect at t ∈ [0.30, 0.40] (1.0000e-01, both types) — the U23-3 fix works.
6. **The constants tripwire holds and the EIC inputs agree across scripts.** `RE_M`, `EMASS`,
   `PMASS` in the theory script equal `Octopus.RE`, `EMASS_EV`, `PMASS_EV`
   (2.8179403205e-15, 0.51099895069e6, 938.27208943e6; read against
   `src/constants/Constants.jl:11-20`; suite tripwire 21686-21705 read). The hand-copied
   `xi_pair` of the comparison script and the theory script's `xi_bb` give the same ξ
   (0.0882/0.1004 and 0.0094/0.0094; probe 3 prints 0.08821/0.10038, 0.00937/0.00941). The
   beam parameters (sizes, betas, tunes, populations, energies) are identical across
   `coherent_mode_vlasov_theory.jl:856-858`, `coherent_mode_eic_comparison.jl:50-55`,
   `eic_emittance_benchmark.jl:174-211`, `high_energy_weakstrong_limit.jl:84-96` and the
   contract (`Contracts.jl:2099-2108`), compared field by field.
7. **The particle referee's Fourier kernel and normalization are the corrected ones.**
   `Ghat = -iπ sign(k) erfcx(s_t|k|/√2)` (line 498) matches the note §2 transform and the
   retracted Gaussian-suppression comment is gone (U22-8 closed); `N0 = 1/(1·(1 + s_t/√2))`
   (line 492) equals `analytic_gradient(1)` of the matrix path for the symmetric case the
   referee is used in; the CIC deposit, the kick sign and the rotation were checked by hand
   (small-amplitude tune shift ξ·u(0) per turn, consistent with the matrix diagonal).
8. **The BeamBeam3D anchor reproduces.** Against the host's run directory the script gives
   Λ = 1.197 / 1.21 with σ drift 1.5e-6 / −3.8e-6 (U22 Clean 9: identical).
9. **The plot pipeline runs on the current TSV layout.** All three figures are written from the
   regenerated tables with the current column names (`Y_m1_matrix`, `Y_1d_sim`, `Y_eff`,
   `in_e_continuum`/`in_p_continuum` as "true"/"false"); the optional measured-scan overlays
   and Figure 4 are skipped cleanly when their TSVs are absent.
10. **Repairs recorded by U22 that are present and executed at HEAD** (read, and exercised by
    the full run): the panel Gauss-Legendre `gauss_avg` with `structure = s_t` (U22-1); the
    per-row invariants written into the TSV as numeric columns (U22-1/-11); self-check 5 on
    the real assembly (U22-4); header item 1 stating u(0) = (1+r)/(1+√2 r) (U22-2); the dead
    `PlaneKernel` and the stale FT comment removed (U22-8); the guarded `near_e` maximum
    (U22-18); the five-TSV closing line (U22-14); the header paragraph replacing the stale
    rigid-bunch "1.21-1.41" block (U22-9).

## Unchecked

- `validation/coherent_mode_scans.jl` was read but not executed (≈ 12 min of PIC at defaults;
  U22 ran it at defaults and attributed the flat-row drift to `src/`; the file is unchanged
  since). Its numbers in the note (1.19 round, 1.25-1.27 flat) were not re-measured.
- The full-resolution `coherent_beam_beam_modes.jl` headline (8192 turns, 100k/beam, three
  solvers) was not re-measured: the script cannot run at HEAD (U43-1), and a migrated copy
  would test my edit rather than the file.
- `docs/theory/near_round_bassetti_erskine_switch.md` sections 1-9 (derivation, constants)
  were not read; only the validation record (§10-11) was compared.
- The CUDA parity numbers were measured on this host's RTX 4500 Ada only; the near-round
  script's bounds are explicitly sized for that GPU.
- Whether 0.60/0.80 model tolerances are appropriate at n = 256 (U43-18) was not measured.
- No committed copy of the Vlasov TSVs exists in this repository to diff against; regeneration
  was compared with the note's tables and U22's recorded numbers, not with a byte-identical
  archive.

## Addendum: `coherent_mode_eic_comparison.jl` at defaults (executed item 11)

Scratch copy, 4096 turns, 20k macroparticles/beam, `--threads=4`, 95 s wall, rc=0
(`probes/U43/logs/eic_comparison_defaults.log`, TSVs in `probes/U43/mirror/result/`). The
note's §4 measurement row reproduces: centroid decoherence 48 / 112 turns (e_x / p_x) and
"persists over the full run" for both y centroids; both y spectra peak at 0.2109 (the proton
bare tune); p_x peaks at 0.231. The broad e_x line peaks at 0.0938 here against 0.09546 in the
archive and 0.10571 in U22's fresh run — a third near-degenerate maximum, all inside
[0.080, 0.168], exactly the sensitivity the note's first boxed paragraph warns about (U22-17;
quote the band, not the peak). The theory's one falsifiable EIC prediction remains absent from
the measurement: in [0.220, 0.229] the y amplitudes are 2.894e-6 (e) and 2.093e-5 (p), i.e.
7.8e-4 and 1.1e-3 of their global peaks 3.714e-3 / 1.823e-2 (U22-7 measured 8.5e-4 / 1.2e-3).
The script prints its continua as `y: e (0.14, 0.2404)`, the full-ξ convention of LEAD U43-6,
so the "in e-band: true" verdict it prints for the 0.2109 line would also be "true" under the
theory TSV's ξ·max u band (0.2125) — the two conventions happen to agree for the observed line
and disagree only for the predicted one. Clean item 11, with the convention caveat.
