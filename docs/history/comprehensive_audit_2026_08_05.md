# Comprehensive Audit — 2026-08-05 (full re-read)

**Status: IN PROGRESS.** This is the live working ledger of a full-repository
line-by-line audit under [`docs/comprehensive_audit.md`](../comprehensive_audit.md),
running as one driving session. It becomes the final report at the Phase 16 halt.

- Commit under audit: `6a3f39ab71a2f076e2c0964a8c014d8e4140b88b` (clean tree).
- Environment: Linux 5.14.0-570.21.1.el9_6, Julia 1.12.4, 128 cores, 503 GB RAM,
  NVIDIA RTX 4500 Ada (24 GB, driver 580.119.02, CUDA 13.0) — GPU checks run for
  real, not skipped.
- Prior audit: [`comprehensive_audit_2026_08_04.md`](comprehensive_audit_2026_08_04.md)
  (parts 1–9). This pass re-reads everything regardless of prior coverage, at the
  human owner's explicit direction; the prior ledger is used only to sharpen
  hypotheses, never to skip a line.

## 0. Declared scope

Line-by-line coverage of every Julia source line at the audited commit:

| tree | lines | treatment |
|---|---|---|
| `src/` | 32,915 | line-by-line, every file |
| `test/` | 8,608 | line-by-line (tests are claims; circularity and never-failing guards are in scope) |
| `examples/` | 712 | line-by-line + executed |
| `validation/` | 8,076 | line-by-line + executed where runtime permits (the two known >420 s scripts get a longer cap or an honest skip) |
| `ext/` | 19 | line-by-line |

Plus: all contracts run and checked that they prove what they claim (Phase 7);
full suite with `--threads=4` on CPU+CUDA (Phase 8); every example executed
(Phase 10); targeted independent derivation (Phase 5/12) of equations the prior
ledger does **not** record as independently derived, and spot re-derivation of a
sample it does; docs checked for consistency against source (Phase 6) — theory
notes are checked where implementing code cites them, not re-derived front to
back where already recorded as derived (each such reliance is noted in the
ledger).

**Not covered, and why:** the Bmad reference case for
`misalign_convention=:bmad` (blocked on an external tool; stays on `todo.md`);
`docs/history/` archives as such (records of past states, not claims about
current code — consulted, not audited); `Manifest.toml` / dependency internals.

## 0a. Method (binding for this pass)

- One driving session; sub-agents multiply reading bandwidth only. **A sub-agent
  claim is a lead, not a finding** (measured series survival ~60%); the auditor
  reproduces every lead before it enters Findings, and no sub-agent ever fixes.
- Behavioural fingerprint captured **before the first source modification**;
  every fix carries a negative control (stash-based or marker-injection per the
  recorded workflow — never `git checkout` over uncommitted state).
- Fix while the reproduction is live; ledger, `todo.md`, and fix land in the
  same commit.
- Corrections to this audit's own analysis are recorded beside the original
  claim, not over it.

## 0b. Reading units and assignment

Provenance: **auditor** = read directly in this session's driving context;
**agent** = briefed sub-agent line-by-line read (lead-generating only).
Status moves pending → reading → reported → **verified** (auditor has
disposed of every lead from that unit).

| unit | files (lines) | reader | status |
|---|---|---|---|
| U1 | `src/tasks/strongstrong/pic_cuda.jl` 1–3000 | agent | pending |
| U2 | `src/tasks/strongstrong/pic_cuda.jl` 3000–5966 | agent (+auditor for 5490–5966) | pending |
| U3 | `src/contracts/Contracts.jl` (2,544) | agent | pending |
| U4 | `src/tasks/strongstrong/interface.jl` (2,310) | agent (+auditor for the `luminosity_append` delta) | reported (4 leads, 2 observations; §7) |
| U5 | `src/tasks/strongstrong/pic_cpu.jl` (1,902) + `slicing.jl` (715) | agent | pending |
| U6 | `src/tasks/BeamObservers.jl` (1,582) + `BPMObserver.jl` (324) + `Tasks.jl` (827) | agent (+auditor for the `append` delta) | pending |
| U7 | `src/elements/strong_beam.jl` (1,547) + `src/track/strong_beam_track.jl` (495) + `src/tasks/strongstrong/gaussian.jl` (195) | agent | pending |
| U8 | `src/tasks/strongstrong/gaussian_pic.jl` (869) + `gaussian_pic_cuda.jl` (1,232) — twin pair, parity brief | agent | pending |
| U9 | `src/tasks/strongstrong/spectral.jl` (1,148) + `spectral_cuda.jl` (806) — twin pair, parity brief | agent | pending |
| U10 | `src/elements/lattice_magnets.jl` (1,222) + `solenoid.jl` (436) + `linear6d.jl` (306) + `linear_maps.jl` (236) | agent | pending |
| U11 | `src/elements/beam_line.jl` (587) + `aperture.jl` (583) + `thin_elements.jl` (346) + `radiation.jl` (313) + `misalignment.jl` (293) | agent | pending |
| U12 | `src/elements/rf_cavity.jl` (223) + `patch.jl` (209) + `chromaticity_kick.jl` (192) + `crab_cavity.jl` (181) + `lorentz_boost.jl` (163) + `ref_tilt.jl` (126) + `Elements.jl` (15) + `src/track/phase6d_track.jl` (359) + `longitudinal.jl` (232) + `fused_track.jl` (77) + `radiation_track.jl` (67) + `Track.jl` (64) | agent | pending |
| U13 | `src/knowledge/Knowledge.jl` (955) + `Methods.jl` (75) + `src/registry/Registry.jl` (218) + `src/examples/Examples.jl` (35) + `src/Octopus.jl` (76) + `src/policies/Policies.jl` (352) | agent | pending |
| U14 | `src/knobs/Knobs.jl` (916) + `symbolic.jl` (319) + `ext/OctopusSymbolicsExt.jl` (19) | agent | pending |
| U15 | `src/beam/Beam.jl` (729) + `src/math/counter_rng.jl` (336) + `SpecialMath.jl` (161) + `src/constants/Constants.jl` (32) | agent | pending |
| U16 | `test/runtests.jl` 1–3800 | agent | pending |
| U17 | `test/runtests.jl` 3800–7613 | agent | pending |
| U18 | `test/examples/` (995) + `examples/` (712) | agent | pending |
| U19 | `validation/` coherent-modes cluster: `coherent_mode_vlasov_theory.jl` (713), `coherent_beam_beam_modes.jl` (215), `coherent_mode_eic_comparison.jl` (171), `coherent_mode_scans.jl` (114), `coherent_beam_beam_modes_beambeam3d.jl` (68), `counter_rng_validation.jl` (118) | agent | pending |
| U20 | `validation/` field cluster: `pic_gaussian_field_validation.jl` (430), `near_round_gaussian_transition.jl` (412), `gaussian_pic_zscan.jl` (363), `spectral_poisson_field_validation.jl` (300), `gaussian_pic_bigaussian_validation.jl` (196), `gaussian_pic_field_validation.jl` (167), `pic_grid_extent_stability.jl` (157), `pic_slice_boundary_jitter.jl` (129), `soft_gaussian_pic_comparison.jl` (116), `pic_gaussian_luminosity_validation.jl` (158) | agent | pending |
| U21 | `validation/` remainder: `slice_longitudinal_zscan.jl` (618), `high_energy_weakstrong_limit.jl` (420), `generate_ptc_reference.jl` (396), `gaussian_slicing_convergence.jl` (286), `strong_strong_spectral_comparison.jl` (276), `slice_interpolation_emittance_growth.jl` (239) + `_summary` (116), `lattice_cells.jl` (235), `pic_option_consistency.jl` (233) + `_summary` (137), `symplecticity_validation.jl` (196), `tracking_backend_consistency.jl` (168), + all remaining small scripts | agent | pending |
| U22 | Post-audit delta: the four commits after `f55cf82` (diffs in `BeamObservers.jl`, `interface.jl`, `test/runtests.jl`, `examples/knob_control.jl`) | **auditor** | all four diffs read + flush/prepare context; produced F1, A-1, A-4, A-5 |
| U23 | Seam-class passes over the seam map (§3) | **auditor** | pending |

## 1. Inherited open queue (from the prior audit, to disposition this pass)

1. Two `validation/` scripts that exceeded the prior 420 s cap — re-run with a
   longer cap.
2. `AbstractGPUExecutionPolicy` and `ElementParameterEffectivenessContract`
   lack docstrings (AGENTS.md requires them).
3. `beam_statistics` covariance loop computes all 36 entries of a symmetric
   matrix — unmeasured performance hypothesis.
4. `Patch._patch_map` recomputes its rotation per particle per turn —
   unmeasured performance hypothesis.
5. Metadata validator remainder: defaults-vs-constructor, declared-parameter-
   is-read, and `validate_configuration_metadata`'s hardcoded type enumeration.

## 2. Traceability matrix

(built during Phase 3; see §3 seam map first — the matrix rows are added as
units report)

## 3. Seam map

(auditor-owned; populated before/while wave results arrive)

## 4. Findings

**F2 (Major, auditor-confirmed, FIXED).** `test/runtests.jl:2939-2942` (the
h≠0 sweep, `baf0255`): the solenoid content loop includes the empty content —
the pure curved solenoid at `nst=4` — under the 1e-12 tolerance, while the
testset's own comment and its dedicated pair (`< 1.0e-8` at nst=4, `< 1.0e-12`
at nst=16) document that configuration's implicit-midpoint floor at 1.1e-9.
Probe (`scratchpad/F2_solenoid_residual_probe.jl`): empty content
`1.1121181016539064e-9` — bit-identical across calls, equal to the suite
failure's value to 17 digits; all nine non-empty contents 8.7e-15..1.0e-14;
nst=16 `1.1e-16`. The failure is deterministic, so **every genuine full-suite
run since `baf0255` has failed and aborted at this testset** (top-level
testsets abort the script on their `TestSetException`), leaving everything
after `runtests.jl:2953` — the CUDA half, the examples testset, both append
testsets, ~4,660 lines — unexecuted; the "full suite green at --threads=4"
claims in `80cadbf`/`6a3f39a` cannot have come from a full run of this exact
tree. The prior audit's own first rule — checks that exist, are correct, and
are never executed — reproduced at HEAD within a day. Fix: the loop skips the
empty content (asserted by the dedicated pair); coverage lost: none. The
sweep's discriminating power is unchanged (instrument negative control at
`runtests.jl:2915` still reproduces the recorded 2.5e-3 defect).

**F1 (Moderate, auditor-confirmed, fix pending with U4-1/U4-2).**
`src/tasks/strongstrong/interface.jl:1991-1992`
(`_prepare_strong_strong_luminosity_file!`): a torn last line from a
hard-killed writer whose turn field is a prefix of the true turn ("1" from
"12") parses as a smaller turn, slips under the `< first_turn` drop on the
retry, and is kept forever — the file then carries two rows labelled turn 1
(one with the wrong field count), violating the function's own "a file
carrying two rows for one turn is corrupt for every reader" docstring.
Reproduced: `scratchpad/A2_lum_torn_write_probe.jl` — retry threw nothing;
final turn column `[0..11, 1, 12, 13]`; duplicated labels `["1"]`; field
counts `[2, 1]`. Independently found by sub-agent U4 (U4-3). The HDF5
MomentObserver twin is crash-safe here by `record_count` ordering
(`BeamObservers.jl:1088-1103`, verified sound).

## 5. Corrections to this audit's own analysis

(none yet)

## 6. Test, contract, validation, and execution log

- **Suite run 1** (Phase 8): `julia --startup-file=no --project=. -e
  Pkg.test(julia_args=["--threads=4"])` at `6a3f39a`, background task. Result:
  **aborted** at "Curved frame x transverse field" (31/32 passed; the F2
  failure), after 40 top-level testset summaries. All testsets after
  `runtests.jl:2953` unexecuted in this invocation. Rerun after the F2 fix.
- **Fingerprint baseline** (Phase 13 gate): `scratchpad/fingerprint.jl` →
  `fp_run1.txt`, 57 lines, CPU-only: per-kind tracked coordinates for every
  registered element spec (zero throws), `:equal_area`/`:equal_count` slice
  objects, 2-turn strong-strong minis on all four solvers (.lum rows +
  coordinate sums, both beams), `beam_statistics`. Two runs **bit-identical**;
  sha256 `d6ab7170f3a2c62d83bcbadbd3476019829b3ddab28f1a90e22b47586cfb3520`.
  Captured before the first source modification of this audit.

## 7. Lead queue

From U4 (reported; agent report at `scratchpad/reports/U4_report.md`):

- **U4-1 (HIGH, unverified by auditor).** `interface.jl:1717-1722,1854-1855,
  1991-1992`: `luminosity_append` continuation state is *not* in the file —
  `first_turn` comes from the fresh task's `next_turn` Ref (0), so a second
  task sharing the path or a process restart *without explicit `start_turn`*
  silently truncates all prior rows (agent measured a 10-row file wiped);
  docstring and commit message promise the opposite. MomentObserver shares
  the trap. Repro: `scratchpad/U4/u4_1_restart_truncation.jl`.
- **U4-2 (Medium, auditor-confirmed by inspection).** `interface.jl:1986,
  1993-1998`: append-mode prepare rewrites the whole file non-atomically
  (`readlines` → `open(path, "w")`) on every continuation; a kill in that
  window loses the entire history the flag exists to preserve. The HDF5 twin
  shrinks in place with no such window.
- **U4-4 (Low, unverified).** `interface.jl:1885-1888` vs `1987-1990`:
  observer tables are truncated before the .lum header guard can refuse, so
  an aborted execute! leaves the two companion outputs diverged.
- U4 observations (dispositions pending): mixed-IP luminosity schedule drops
  sibling IPs' evaluated values for that row (`interface.jl:2052`);
  `_collision_solver` compares solvers by identity (`interface.jl:2281`).

From the auditor's own U22 read:

- **A-1 (Minor).** `examples/knob_control.jl:151` gates on the internal
  `Octopus._symbolics_adapter_active()` — a public example teaching an
  internal call (AGENTS.md: examples tie to public APIs).
- **A-4 (Minor, confirmed by read).** `BeamObservers.jl:1092`:
  `throw(BoundsError("MomentObserver received more records than planned"))`
  abuses `BoundsError` (first field is the accessed object) — displays as
  "attempt to access String".
- **A-5 (Minor).** `BeamObservers.jl:961` continue path: `append=true` onto
  an existing **zero-byte** file (crash at create, `touch`) hits a raw HDF5
  open error instead of a directed refusal; the .lum twin checks
  `filesize(path) == 0` explicitly.

U4 sound-areas (agent-verified, provenance: agent): option→consumer tracing
complete (no stored-and-never-read option in `interface.jl`); knob/spec-epoch
gate matches `Tasks.jl:529` across task families; no `Core.Box` captures; the
luminosity schedule dispatch is specialized by all three grid solvers.

## 8. Change log

| file | change | finding |
|---|---|---|
| `test/runtests.jl` | h≠0 solenoid loop skips the empty content (pure case asserted by its dedicated pair) | F2 |
