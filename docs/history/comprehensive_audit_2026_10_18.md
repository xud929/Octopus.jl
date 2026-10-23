# Comprehensive Audit — 2026-10-18 (full pass)

**Status:** closed 2026-10-19 as an audit record: 55 of 55 units read and dispositioned, 244 findings plus six auditor items, every one a priced ledger row; no fix applied (the pass was authorized to audit). Phase 8 (the full two-arm gate on 24e8683) is NOT closed: the native arm segfaults deterministically with CUDA active (F-244) while the CPU-only lane passes; the record commit itself is markdown-only and its fast lane is green (§6).

## 0. Declared scope

A uniform-depth full pass over the repository at main 24e8683 (origin/main), the
first since the two full passes of 2026-08-05 (26 units over 53,472 Julia
lines). Since then: 282 commits, source +34,144/−3,071 lines across 65 files
(now 69 files, 68,204 lines), the suite +27,987 lines (32,035; 351 top-level
testsets against 151), nineteen source files that did not exist (the analysis
layer, four contracts, the run artifact, turn modulation, the floor plan, two
strong-strong solvers). Every campaign since was neighbour-audited against its
own diff; nothing read the unchanged half, and the cross-cutting classes the
last batches surfaced (one quantity with two conventions across layers; pins
resting on rounding; a composition rule that does not accumulate; two walkers
over one structure) are what a per-diff audit structurally cannot see.

- **Covered, line by line (sub-agent reading units, auditor reproduction):**
  every `.jl` under `src/`, `ext/`, `test/` (the suite in ten line-range units
  cut at testset starts, the harnesses, the MPI seam check, the probe), the
  nightly scripts, `validation/` (every script, the README as claims about the
  scripts, the two Python generators and the reference provenance),
  `examples/`, `profiling/`.
- **Covered as claims about the code:** every theory note, every design note,
  the top-level docs and guides, `AGENTS.md`, the CI workflow, the open todo
  rows, and the two process documents (the protocol and the experiences file).
- **Auditor-direct:** the seam cross-check passes (Phase 3's seam map), Phase 7
  contract execution, Phase 8 the full gate (both CPU arms, CUDA active), Phase
  10 examples and validation runs, the dependency pins (`Project.toml`,
  `Manifest.toml` against the CI float), `.gitignore`, `LICENSE`.
- **Not covered, and why:** the untracked, git-ignored notebook checkpoint
  copies under `.ipynb_checkpoints/` (local artefacts, not part of the tree);
  `docs/history/` records (frozen instances of past work, consulted where a
  lead touches them, never audited as current state); the `result/` scratch
  (git-ignored, never evidence).
- **Fixing phases (13, 14, 16):** per AGENTS.md's authorization rule the owner's
  request authorised the review; every confirmed finding becomes a priced
  `docs/todo.md` row with a reproduction, and fixes wait for the owner's word,
  as the 2026-10-16 neighbour audit did. The baseline fingerprint of Phase 13
  is captured before the first fix, not before.

## 0a. Method (binding for this pass)

The protocol as written: one driving session; reading delegated to 55
briefed units, each with a distinct hypothesis drawn from the fifteen defect
classes this repository has produced (`plan/BRIEF_COMMON.md`, archived with the
unit reports); every unit claim is a lead until the auditor reproduces it;
seams, contract execution, the gate and every judgement stay with the auditor;
the coverage ledger carries provenance (auditor vs agent); the plan itself
passed a coverage tripwire (every in-scope file assigned to exactly one unit,
or named above as skipped) before the first unit was launched — its first
version had missed 30 files.

## 0b. Reading units and assignment

| unit | region | lines | depth | who | status |
|---|---|---|---|---|---|
| U1 | pic_cuda.jl, first third | 2200 | line-by-line | agent | report in, leads dispositioned in §4 |
| U2 | pic_cuda.jl, second third | 2200 | line-by-line | agent | report in, leads dispositioned in §4 |
| U3 | pic_cuda.jl, last third | 2092 | line-by-line | agent | report in, leads dispositioned in §4 |
| U4 | pic_cpu.jl | 3061 | line-by-line | agent | report in, leads dispositioned in §4 |
| U5 | pic_cpu_sliced.jl (new since the last audit) | 2228 | line-by-line | agent | report in, leads dispositioned in §4 |
| U6 | interface.jl (strong-strong task, options, caches) | 3432 | line-by-line | agent | report in, leads dispositioned in §4 |
| U7 | spectral.jl + spectral_cuda.jl (twin pair) | 2906 | line-by-line | agent | report in, leads dispositioned in §4 |
| U8 | spectral_sliced.jl + gaussian.jl + slicing.jl | 2961 | line-by-line | agent | report in, leads dispositioned in §4 |
| U9 | gaussian_pic.jl + gaussian_pic_cuda.jl (twin pair) | 2834 | line-by-line | agent | report in, leads dispositioned in §4 |
| U10 | Contracts.jl, first half | 2100 | line-by-line | agent | report in, leads dispositioned in §4 |
| U11 | Contracts.jl, second half + the MPI child | 2059 | line-by-line | agent | report in, leads dispositioned in §4 |
| U12 | Tasks.jl | 2465 | line-by-line | agent | report in, leads dispositioned in §4 |
| U13 | RunArtifact.jl (new since the last audit) | 2070 | line-by-line | agent | report in, leads dispositioned in §4 |
| U14 | BeamObservers.jl + BPMObserver.jl | 2052 | line-by-line | agent | report in, leads dispositioned in §4 |
| U15 | turn_modulated.jl + crab_cavity.jl | 2519 | line-by-line | agent | report in, leads dispositioned in §4 |
| U16 | strong_beam.jl + strong_beam_track.jl | 2764 | line-by-line | agent | report in, leads dispositioned in §4 |
| U17 | lattice_magnets.jl + solenoid.jl + linear6d.jl | 2664 | line-by-line | agent | report in, leads dispositioned in §4 |
| U18 | beam_line.jl + aperture.jl + misalignment.jl + ref_tilt.jl + patch.jl + floor_plan.jl | 2711 | line-by-line | agent | report in, leads dispositioned in §4 |
| U19 | rf_cavity.jl + thin_elements.jl + linear_maps.jl + lorentz_boost.jl + chromaticity_kick.jl + radiation.jl | 2744 | line-by-line | agent | report in, leads dispositioned in §4 |
| U20 | track/ + math/ | 2464 | line-by-line | agent | report in, leads dispositioned in §4 |
| U21 | analysis/: the analysis object, Determined, one-turn matrix | 2483 | line-by-line | agent | report in, leads dispositioned in §4 |
| U22 | analysis/: dispersion routes, canonical separation, degenerate dispersion | 2518 | line-by-line | agent | report in, leads dispositioned in §4 |
| U23 | analysis/: mode clusters, coupled parameterizations, 4D eigenmodes, symplectic algebra | 3419 | line-by-line | agent | report in, leads dispositioned in §4 |
| U24 | contracts/: the three analysis contracts | 3020 | line-by-line | agent | report in, leads dispositioned in §4 |
| U25 | Policies.jl + Knowledge.jl + Methods.jl | 3107 | line-by-line | agent | report in, leads dispositioned in §4 |
| U26 | Knobs.jl + symbolic.jl + ext/ (ForwardDiff, MPI, Symbolics extensions) | 1764 | line-by-line | agent | report in, leads dispositioned in §4 |
| U27 | Beam.jl + Registry.jl + Examples.jl + Octopus.jl + constants + Elements.jl + StrongStrong.jl | 1719 | line-by-line | agent | report in, leads dispositioned in §4 |
| U28 | test/runtests.jl lines 1-3242 | 3242 | line-by-line | agent | report in, leads dispositioned in §4 |
| U29 | test/runtests.jl lines 3243-6447 | 3205 | line-by-line | agent | report in, leads dispositioned in §4 |
| U30 | test/runtests.jl lines 6448-9635 | 3188 | line-by-line | agent | report in, leads dispositioned in §4 |
| U31 | test/runtests.jl lines 9636-12910 | 3275 | line-by-line | agent | report in, leads dispositioned in §4 |
| U32 | test/runtests.jl lines 12911-16037 | 3127 | line-by-line | agent | report in, leads dispositioned in §4 |
| U33 | test/runtests.jl lines 16038-19586 | 3549 | line-by-line | agent | report in, leads dispositioned in §4 |
| U34 | test/runtests.jl lines 19587-22525 | 2939 | line-by-line | agent | report in, leads dispositioned in §4 |
| U35 | test/runtests.jl lines 22526-25667 | 3142 | line-by-line | agent | report in, leads dispositioned in §4 |
| U36 | test/runtests.jl lines 25668-28979 | 3312 | line-by-line | agent | report in, leads dispositioned in §4 |
| U37 | test/runtests.jl lines 28980-32035 | 3056 | line-by-line | agent | report in, leads dispositioned in §4 |
| U38 | test/examples/ + examples/ | 5217 | line-by-line | agent | report in, leads dispositioned in §4 |
| U39 | profiling/ | 3336 | line-by-line | agent | report in, leads dispositioned in §4 |
| U40 | validation: crab-cavity noise, turn-modulation spectra, counter RNG, diagnostics benchmark | 2948 | line-by-line | agent | report in, leads dispositioned in §4 |
| U41 | validation: Twiss external benchmarks and reference generators | 4009 | line-by-line | agent | report in, leads dispositioned in §4 |
| U42 | validation: Twiss acceptance windows, cells, identities, lattice cells, survey reference, symplecticity, backend consistency | 2667 | line-by-line | agent | report in, leads dispositioned in §4 |
| U43 | validation: coherent modes, EIC emittance, high-energy limit, near-round transition | 3328 | line-by-line | agent | report in, leads dispositioned in §4 |
| U44 | validation: field, luminosity, grid, noise floor, option consistency, kick decomposition, spectral comparison | 2935 | line-by-line | agent | report in, leads dispositioned in §4 |
| U45 | validation: slicing studies, PTC reference generator, the validation README and reference provenance | 4130 | line-by-line scripts; README as claims about the scripts | agent | report in, leads dispositioned in §4 |
| U46 | theory notes A: longitudinal kick, near-round switch, slice interpolation, longitudinal slicing | 4633 | claims-vs-code; sampled independent derivations | agent | report in, leads dispositioned in §4 |
| U47 | theory notes B: subtracted PIC, spectral Poisson, free-space kernels, node grid, coherent modes, weak-strong 6D | 2879 | claims-vs-code; sampled independent derivations | agent | report in, leads dispositioned in §4 |
| U48 | theory notes C: lattice Hamiltonian and conventions, solenoid, beam-line composition | 2534 | claims-vs-code; sampled independent derivations | agent | report in, leads dispositioned in §4 |
| U49 | theory notes D: misalignment and patch, aperture and loss, RF cavity and reference energy, arc survey, floor plan, BPM | 1824 | claims-vs-code | agent | report in, leads dispositioned in §4 |
| U50 | theory notes E: twiss_dispersion.md and crab_cavity_noise_response.md | 3701 | claims-vs-code; sampled independent derivations | agent | report in, leads dispositioned in §4 |
| U51 | design notes as claims about the code | 4660 | claims-vs-code | agent | report in, leads dispositioned in §4 |
| U52 | top-level docs, guides, AGENTS.md, CI workflow, the open todo rows | 4481 | claims-vs-code | agent | report in, leads dispositioned in §4 |
| U53 | test/: the MPI seam check and fixture, the turn-modulation probe, the nightly suite script | 1985 | line-by-line | agent | report in, leads dispositioned in §4 |
| U54 | validation: consistency, effectiveness and small studies (22 scripts) | 1551 | line-by-line | agent | report in, leads dispositioned in §4 |
| U55 | process documents: the audit protocol and the experiences file | 2653 | claims-vs-code | agent | report in, leads dispositioned in §4 |
| U-seams | seam-class cross-check passes (§3) | — | auditor | pending |
| U-exec | Phase 7 contracts, Phase 8 gate, Phase 10 examples and validation | — | auditor | pending |

## 1. Inherited open queue (to disposition this pass)

The 41 rows of `docs/todo.md` at 24e8683, each to be dispositioned in §7 (still
open with its premise re-verified at HEAD, closed as already fixed, or absorbed
into a finding). Rows whose state cell says CLOSED are ledger debris to be moved
to the archive if their text confirms closure.

1. **Twiss and dispersion analysis** — theory complete incl. mode degeneracy; architecture decided 2026-09-11; stages 1 and 2 landed 2026-09-11, stag...
2. **Turn-by-turn lattice modulation: crab cavity phase and amplitude noise** — stages 1-4 landed (1-2 pushed 2026-10-13 as 148d39a, CI run 447 green 2026-10-13; 3-4 committed 2026-10-13 as ...
3. **Crab cavity noise example and validation** — CLOSED 2026-10-14 (example, harness, theory note, validation landed; sweep done 2026-10-14 (77 acceptance chec...
4. **Crab cavity noise example: the MPI execution policy arm and the cross-backend benchmark** — CLOSED 2026-10-14 (arm, benchmark and record landed; committed 2026-10-14 as f858107, gated the same day in bo...
5. **Turn modulation: record the realised offsets in the run artifact** — stage 1 implementation landed and probe-verified 2026-10-15 (376 of 376 on CPU threads, CUDA and two MPI ranks...
6. **A spectral producer for `TurnTable`** — CLOSED 2026-10-16 by the neighbour audit, nothing owed: stage 1, the whole deliverable of the note's one-batch...
7. **Crab-cavity / RF-cavity noise neighbour audit: the open queue** — record pushed 2026-10-16 as 8ace18b (CI run 459 green); fix batch 1 pushed as ac3fbb2 (CI run 460 green); fix ...
8. **Stateful turn-modulation rules: checkpoint reserved, restart semantics owed** — open (2026-10-15, design decision; nothing to implement until a stateful rule ships)
9. **The effectiveness contract pins `RunArtifact` options only through receipts, with no schema-driven sweep** — open (2026-10-15, found at stage 1 of `design/turn_modulation_record.md`)
10. **The two-harmonic pink-plus-table fixture's plain `update_line` allocates** — CLOSED 2026-10-15 (review F1 of the stage 1 batch; the fix rides that batch)
11. **Two concurrent suites in one worktree race in the example testset's cleanup** — open (2026-10-15, seen at the stage 1 gate of `design/turn_modulation_record.md`)
12. **Turn-modulation receipt and provenance name an element by its type only** — open (2026-10-14, the crab-noise example's friction list)
13. **`rng_id = 0` makes turn-modulation provenance depend on construction order** — open (2026-10-14, the crab-noise example's friction list)
14. **The every-turn `MomentObserver` and artifact row dominate the CPU per-turn cost** — open (2026-10-14, the crab cavity noise MPI benchmark's dry run)
15. **Rank identity after `execute!` and the per-rank `turn_timings` have no public collective form** — open (2026-10-14, the crab-noise MPI arm's friction list)
16. **Quiet-machine benchmark of the per-turn rebuild and the wrapped kernel tuple** — open (2026-10-13, turn-modulation audit U1-4)
17. **The cross-backend class composition rule does not model gradient amplification over turns** — open (2026-10-18, found by the beam-beam fix batch's unit M by measurement)
18. **Multi-process mixed execution policy (MPI x CPUThreads)** — open (2026-09-06, steps 1-4h closed and the neighbour audit run; the ranks > slices regime and the priced leve...
19. **The MPI suite reads its receipts off a merged stdout, and it is lossy** — CLOSED 2026-09-06
20. **Targeted neighbour audit of the multi-process campaign** — CLOSED 2026-09-06 (record: [`history/neighbour_audit_2026_09_06.md`](history/neighbour_audit_2026_09_06.md))
21. **The `:funneled` tripwire tests a thread id, not the driver task** — CLOSED 2026-09-07 (record: [`history/mpi_audit_followups_2026_09_07.md`](history/mpi_audit_followups_2026_09_0...
22. **`_run_logical_workers`' pool-of-one inline path is exercised nowhere** — CLOSED 2026-09-07
23. **The luminosity-schedule broadcast is hand-copied per solver** — CLOSED 2026-09-07, and it found a live defect (record: [`history/mpi_audit_followups_2026_09_07.md`](history/m...
24. **Loss accounting on the artifact's CRASH path is rank-local, and gathers from a rank-local failure** — CLOSED 2026-09-07, NOT A DEFECT; the labelling gap was real and is fixed
25. **The artifact does not record `summary_logged`** — CLOSED 2026-09-07
26. **PIC `:node` / `:source_slice` grid modes take the per-pair route when divided** — CLOSED 2026-09-07, NOT A DEFECT
27. **Tracked `Manifest.toml` predates `Project.toml`** — CLOSED 2026-09-07
28. **Run-artifact niceties deferred at step 4** — open (2026-08-18)
29. **CUDA in-suite vs standalone last-bit divergence: mechanism SOLVED** — CLOSED 2026-09-07 (record: [`history/cuda_lastbit_fma_2026_09_07.md`](history/cuda_lastbit_fma_2026_09_07.md))
30. **The observer schema-vs-report check is an identity for derived reports** — CLOSED 2026-09-07
31. **Three metadata-validator checks are tautologies** — CLOSED 2026-09-07
32. **Observer declared defaults are unchecked, because two are sentinels** — open (2026-09-07, from U4-18)
33. **Three metadata channels are unvalidated free text** — one of three CLOSED 2026-09-07 (2026-08-06, U12-6)
34. **`validate_configuration_metadata` enumerates types by hand** — CLOSED 2026-09-07
35. **CPU threading: remaining measured headroom** — open leads (2026-08-10 campaign remainder)
36. **`TrackingTask` records no per-turn timings, so weak-strong timing is external arithmetic** — CLOSED 2026-09-07
37. **The fused luminosity route does not yet cover WRAPPED strong beams** — CLOSED 2026-09-08
38. **A public `TrackingTask` field can have no schema entry, invisibly** — open (2026-09-08)
39. **Bmad reference cases for `misalign_convention=:bmad`** — blocked on a tool
40. **CUDA near-identity pin wobbles (the family ledger)** — ALL THREE MEMBERS CLOSED 2026-09-07
41. **CI segfault on Julia 1.12.6** — open (2026-08-12)

## 1b. Repository summary (Phase 1)

Octopus is an AI-native accelerator-physics framework for beam-beam
collisions: weak-strong 6D tracking against a rigid Gaussian beam and
strong-strong collisions of two live beams (soft-Gaussian, spectral and PIC
Poisson solvers, sliced and unsliced), on CPU threads, CUDA and MPI. An
element flows from an `ElementSpec{kind}` through a `TrackingMethod` and an
`ExecutionPolicy` into `compile_runtime`; the Knowledge layer carries the
spec metadata, the registry derives the roster, contracts verify, analyses
(the Twiss and dispersion analysis, the first) compute optics from the
one-turn map, tasks compose execution (tracking, strong-strong, the run
artifact, observers, knobs, turn-by-turn modulation). Coordinates
`(x, px, y, py, z, pz)` with `z = s - ct`-type longitudinal convention stated
in the conventions note; the counter RNG keyed by (seed, method, turn,
rng_id, particle, component); cross-backend rounding classes declared per
runtime op; the one precision rule (Float64 floor, mismatched beams refused
by name). Verification: one suite of 351 top-level testsets in two lanes, a
CPU-only CI, GPU gates run locally, validation scripts with committed external
references (MAD-X, PTC, Xsuite), theory notes under `docs/theory/` for every
physics kernel. The physics focus and the invariants are in `AGENTS.md`; the
procedures in `docs/guides/`.

## 2. Traceability matrix

Scientific requirement -> note -> implementation -> suite -> validation -> contract, at
24e8683, built by the auditor from the index and title greps (testset counts are
keyword matches on column-0 titles, a lower bound). Missing links are marked in bold
and are findings about traceability unless a unit shows the link exists under another
name.

| feature | theory / design | implementation | tests (suite) | validation scripts | contracts |
|---|---|---|---|---|---|
| Weak-strong Bassetti-Erskine kick, near-round switch | near_round_bassetti_erskine_switch.md, weak_strong_6d_model.md | elements/strong_beam.jl, track/strong_beam_track.jl | 9 testsets (e.g. "A wrapped strong beam cannot silently lose its luminosity") | high_energy_weakstrong_limit.jl, near_round_gaussian_transition.jl, soft_gaussian_pic_comparison.jl, strong_beam_kick_fingerprint.jl | HighEnergyWeakStrongLimitContract, ElementTrackingBackendConsistencyContract |
| Hirata longitudinal kick, Lorentz boost, slicing | beam_beam_longitudinal_kick.md, gaussian_longitudinal_slicing.md, slice_longitudinal_interpolation.md | elements/lorentz_boost.jl, strongstrong/slicing.jl, pic_cpu_sliced.jl, spectral_sliced.jl | 14 testsets (e.g. "Conditional 6D Gaussian strong-beam slicing") | gaussian_pic_zscan.jl, gaussian_slicing_convergence.jl, pic_slice_boundary_jitter.jl, slice_interpolation_emittance_growth.jl, slice_interpolation_emittance_growth_summary.jl, slice_longitudinal_zscan.jl | SymplecticityContract (boost cases) |
| Strong-strong soft-Gaussian solver | coherent_beam_beam_modes.md | strongstrong/gaussian.jl | 6 testsets (e.g. "GaussianPIC beats PIC toward the soft-Gaussian kick") | coherent_beam_beam_modes.jl, coherent_beam_beam_modes_beambeam3d.jl, coherent_mode_eic_comparison.jl, coherent_mode_scans.jl, coherent_mode_vlasov_theory.jl, eic_emittance_benchmark.jl, soft_gaussian_pic_comparison.jl | StrongStrongGaussianBackendConsistencyContract, CoherentModePhysicsContract |
| Strong-strong spectral Poisson solver | spectral_sine_poisson_solver.md | strongstrong/spectral.jl, spectral_cuda.jl, spectral_sliced.jl | 17 testsets (e.g. "Ambiguity set: the trial-015 isospectral family") | spectral_poisson_field_validation.jl, strong_strong_spectral_comparison.jl | StrongStrongPICBackendConsistencyContract (spectral arm?) -- units to confirm |
| Strong-strong PIC solvers (free-space, subtracted, node grid) | pic_free_space_kernels.md, gaussian_subtracted_pic_solver.md, node_interaction_grid.md | strongstrong/pic_cpu.jl, pic_cuda.jl, gaussian_pic.jl, gaussian_pic_cuda.jl | 29 testsets (e.g. "Dispersion routes: singular projection, isotropic graph, deg") | gaussian_pic_bigaussian_validation.jl, gaussian_pic_field_validation.jl, gaussian_pic_zscan.jl, pic_gaussian_field_validation.jl, pic_gaussian_luminosity_validation.jl, pic_grid_extent_stability.jl, pic_option_consistency.jl, pic_option_consistency_summary.jl, pic_slice_boundary_jitter.jl, soft_gaussian_pic_comparison.jl, strong_strong_pic_cache_backend_consistency.jl, strong_strong_pic_extreme_benchmark.jl | StrongStrongPICBackendConsistencyContract, StrongStrongPICMultiProcessConsistencyContract |
| Lattice magnets (drift, quad, sext, oct, multipole, bend), fringes | lattice_hamiltonian_and_conventions.md | elements/lattice_magnets.jl | 7 testsets (e.g. "Lattice magnets") | generate_ptc_reference.jl, lattice_cells.jl, symplecticity_validation.jl | SymplecticityContract, PTCConsistencyContract |
| Solenoid (straight, curved, superimposed multipoles) | solenoid.md | elements/solenoid.jl | 6 testsets (e.g. "Cancellation-free longitudinal updates for the curved drift,") | symplecticity_validation.jl | SymplecticityContract |
| RF cavity, accelerating cavity, reference energy, velocity slip, survey | rf_cavity_and_reference_energy.md, arc_survey_and_velocity_slip.md | elements/rf_cavity.jl, tasks/Tasks.jl (_bind_survey) | 12 testsets (e.g. "Ambiguity set: 30 conjugated copies (N12 surface, N14 endpoi") | generate_madx_survey_reference.jl | MADXSurveyConsistencyContract |
| Misalignment, design roll, patch, floor plan | misalignment_and_patch_maps.md, floor_plan_survey.md | elements/misalignment.jl, ref_tilt.jl, patch.jl, floor_plan.jl | 6 testsets (e.g. "Mode clusters: rolled equal-tune FODO (13.10) and its detune") | generate_madx_survey_reference.jl | MADXSurveyConsistencyContract; floor plan: **no validation script** |
| Beam lines: composition, kept-whole lines, walkers | beam_line_composition.md | elements/beam_line.jl, tasks/Tasks.jl walkers | 4 testsets (e.g. "knob_report over a container reports the wiring") | **none** | **none** (suite only) |
| Apertures and particle loss | aperture_and_particle_loss.md | elements/aperture.jl, tasks/Tasks.jl (_bind_apertures, _aperture_rebind) | 12 testsets (e.g. "Aperture ids thread through the frame wrappers and kept-whol") | tracking_backend_consistency.jl | ElementTrackingBackendConsistencyContract (killing arm) |
| Lumped radiation (damping, excitation) | **no theory note** | elements/radiation.jl, track/radiation_track.jl | 4 testsets (e.g. "Lumped radiation method and flag semantics") | **none** | **none** |
| Dispersion maps, chromaticity kick, Linear6D | twiss_dispersion.md (D7)-(D8) for the convention | elements/linear_maps.jl, chromaticity_kick.jl, linear6d.jl | 3 testsets (e.g. "Edwards-Teng: the coupled construction of benchmark 12.2-2 (") | beam_optics_interface_consistency.jl | SymplecticityContract (linear6d cases?) -- units to confirm |
| Counter RNG (Philox), streams and provenance | **design-level only (no theory note)** | math/counter_rng.jl | 5 testsets (e.g. "Counter RNG smoke tests") | counter_rng_validation.jl | **none** (tests against KAT vectors) |
| Turn-by-turn modulation (rules, wrapper, record, spectral table) | design/turn_modulation.md, turn_modulation_record.md, spectral_turn_table.md; crab_cavity_noise_response.md | elements/turn_modulated.jl, crab_cavity.jl, tasks/RunArtifact.jl | 14 testsets (e.g. "Turn modulation: effectiveness at the kernel boundary, chunk") | crab_cavity_noise_response.jl, turn_modulation_spectra.jl | PublicConfigurationEffectivenessContract (rules' options?) -- units to confirm |
| Run artifact (HDF5), receipts, ledger, lock | design/run_artifact.md | tasks/RunArtifact.jl | 14 testsets (e.g. "Mode clusters: argument errors and the receipt lists every c") | strong_strong_luminosity_schedule_output.jl | PublicConfigurationEffectivenessContract (through receipts only: todo row) |
| Observers (moments, BPM) and append/restart | bpm_measurement_model.md | tasks/BeamObservers.jl, BPMObserver.jl | 7 testsets (e.g. "Observer finalizers, BPM noise keys, and the schedule planne") | moment_observer_backend_consistency.jl, strong_strong_observer_plan_consistency.jl | **none** |
| Knobs (epochs, symbolic) | knob_control.md | knobs/Knobs.jl, symbolic.jl | 3 testsets (e.g. "knob_report over a container reports the wiring") | **none** | KnobEffectivenessContract |
| Twiss and dispersion analysis | twiss_dispersion.md; design/twiss_dispersion_analysis.md | analysis/*.jl | 42 testsets (e.g. "Stage 5 declares the analysis: the placeholder and TwissDisp") | generate_madx_twiss_reference.jl, generate_ptc_twiss_reference.jl, twiss_benchmark_cells.jl, twiss_dispersion_acceptance_windows.jl, twiss_dispersion_identities.jl, twiss_dispersion_route_dump.jl, twiss_madx_benchmark.jl, twiss_ptc_benchmark.jl, twiss_xsuite_benchmark.jl | TwissDispersionIdentityContract, TwissExternalReferenceContract, AnalysisOptionEffectivenessContract |
| Execution policies (CPU threads, CUDA, MPI), launch config, backends | design/multi_process_policy.md; current_runtime.md | policies/Policies.jl, track/*.jl, ext/OctopusMPIExt.jl | 40 testsets (e.g. "CUDA coverage status") | strong_strong_pic_cache_backend_consistency.jl, tracking_backend_consistency.jl, tracking_context_policy_consistency.jl | the four backend-consistency contracts, SolverOptionEffectivenessContract |
| Element metadata, registry, snapshot, help | guides/elements.md, guides/configuration.md | knowledge/Knowledge.jl, registry/Registry.jl | 12 testsets (e.g. "Stage 6 registers TwissDispersionIdentityContract: descripti") | public_configuration_effectiveness.jl | ElementParameterEffectivenessContract |
| Examples and harnesses | guides/examples_and_validation.md | examples/*.jl, test/examples/*.jl, src/examples/Examples.jl | 4 testsets (e.g. "Stage 5: every kind that declares the analysis analyzes its ") | **none** | n/a |

Missing links at a glance: lumped radiation has no theory note and no validation
script; the floor-plan survey has no validation script; beam-line composition and the
observers are covered by the suite alone; the counter RNG's provenance is design-level
(its Philox is checked against KAT vectors in the suite and `validation/counter_rng_validation.jl`).

## 3. Seam map

The implicit cross-module contracts at 24e8683, each with its participants; the
seam cross-check passes (U-seams, §4 and §7) run against this inventory. Anchors
are `file:line` at 24e8683.

**S1. Several walkers over one line structure** (the T3 class). The runtime compile
`_append_runtime_line!` (`src/tasks/Tasks.jl:2034-2058`) and `compile_runtime(::ElementSpec{:line})`
(`src/elements/beam_line.jl:728`) decide what a container is; the spec-side
collectors must agree: `_collect_aperture_specs!` (Tasks.jl:736-752), the one arc
traversal `_collect_spec_s!` (793-835; `s_positions` beam_line.jl:474,
`_placement_length` 438-461), `_collect_radiation_ids!` (435-447), `_collect_declared!`
(882-888), `_collect_turn_modulation_ids!` (`src/elements/turn_modulated.jl:1775`),
`_element_tuple` (Tasks.jl:856-862); the runtime-side rebinds `_bind_apertures` /
`_aperture_rebind` (1788, 1829-1837) and `_bind_survey` / `_survey_rebind` (1860,
1912-1953), `_collect_strong_beams!` / `_descend_strong_beams!`
(`src/track/strong_beam_track.jl:17-24`, read by `_strong_beams_of` Tasks.jl:2262 and
the CUDA wrapped launch), and every per-wrapper forwarding method the tripwire
"Turn modulation: rules, wrapper and the pure hook" lists in `wrapper_walks`
(`_inner_method`, `_hidden_strong_beam_count`, `_descend_strong_beams!`,
`_survey_rebind`, `_requires_tracking_context`, `update`, `_check_turn_window`,
`_turn_modulation_provenance!`, `_turn_modulation_columns!`, `_each_modulated`,
`_check_beam_eltype`, `_required_beam_eltype`, `_cross_backend_rounding`,
`_requires_cuda_elementwise`, `_aperture_rebind`, `track_luminous`, `track_particle`).
Changed three times in the last ten days (U2-5, S3-1, fix N); the pass checks every
walker on the same nested fixture, not the tripwire's product alone.

**S2. CPU/CUDA twin implementations bound only by parity.** `pic_cpu.jl` <-> `pic_cuda.jl`;
`gaussian_pic.jl` <-> `gaussian_pic_cuda.jl`; `spectral.jl` <-> `spectral_cuda.jl`; the
sliced solvers `pic_cpu_sliced.jl` and `spectral_sliced.jl` against their unsliced
twins and against whatever CUDA sliced path exists (units U5, U8 to say); the bare
strong-beam kernels <-> the new device views' `track_luminous` bodies
(strong_beam_track.jl, fix M's mirror, guarded by identity pins); the CPU fused route
<-> the CUDA fused and elementwise routes (`src/track/phase6d_track.jl:108-133,
136-203, 379-428`); the beam-statistics folds on CPU, CUDA and MPI (`src/beam/Beam.jl`,
observers). The declared classes (`_cross_backend_rounding`, 30+ methods across
`src/elements/*.jl`, composed in beam_line.jl:679) are the stated bound; the
measurement tripwire and the backend script's per-kind arm are the check.

**S3. Producer/consumer protocol pairs.** The knob epoch (`src/knobs/Knobs.jl`) and
the spec epoch against every compiled cache: `_strong_strong_cache_current`
(`src/tasks/strongstrong/interface.jl:3241`, `_strong_strong_runtime_blocks` 2359,
2646) and the TrackingTask caches in Tasks.jl; the run artifact's writers against
its reader and schema (`src/tasks/RunArtifact.jl`: the sidecar lock `_ra_take_lock!`
~234, `_ra_output_receipt` 355, `_ra_artifact_entry` 396, the turn-modulation
columns writer turn_modulated.jl:1909-1930 and `_turn_modulation_provenance!`
1880-1888); the observers' append/restart (`src/tasks/BeamObservers.jl`,
`BPMObserver.jl`); the execution receipts (`/execution` ledger) against the tests
and contracts that assert them (lesson 11).

**S4. Declared schemas and metadata against their runtime consumers.** 41
`ConfigurationOptionMeta(` declarations (Policies.jl, interface.jl, Tasks.jl,
RunArtifact.jl, BeamObservers.jl) against `getparam`/`param` reads;
`ElementMeta`/`ParamMeta` against constructors (`validate_element_metadata`
`src/knowledge/Knowledge.jl:1199`); the registry (`src/registry/Registry.jl:73, 92`)
against `docs/registry_snapshot.md`; `_required_beam_eltype` (beam_line.jl:664,
misalignment.jl:248, ref_tilt.jl:62, turn_modulated.jl:1439) against
`_check_beam_eltype`; the effectiveness contracts against the options they claim to
sweep.

**S5. Task-type asymmetry** (added by the 2026-08-05_b pass): machinery that exists
for `TrackingTask` and not for `StrongStrongTask` or vice versa -- loss accounting,
observers, the artifact, turn modulation, the survey; the pass enumerates the
features per task type.

**S6. Convention seams across layers** (added by this pass): one physical quantity
named in two layers -- dispersion (the analysis's canonical `eta` vs the strong beam
and the dispersion maps), the longitudinal coordinate and sign conventions across
the theory notes, the cross-backend class composition over a line and over turns.

## 4. Findings

Findings are confirmed by auditor reproduction; unit claims stay leads (§7)
until then. Auditor-direct observations from the execution phases are listed
first as leads of their own (A-n), with their disposition filled in as the
pass proceeds.

### Auditor-direct leads from Phases 7, 8 and 10 (reproduction in progress)

- **A-1 [Moderate, lead]** `validation/twiss_dispersion_identities.jl` exits 1 at
  its defaults on 24e8683: `TW-TENTH above_one=1`, the identity
  `c_scaling_invariance` on dense 6x6 map 98 at 6.707e-12 against its bound
  `c eps kappa = 6.031e-12` (ratio 1.11), while the suite's
  `TwissDispersionIdentityContract` (20 + 5 maps) passes (57 identities, 160
  fixture runs). The stage 9 record of the Twiss campaign
  (`history/twiss_dispersion_analysis_history.md`, "OPEN, unchanged") documents
  the script exiting 1 at its defaults for a DIFFERENT reason
  (`k_route_agreement` 1.29e32 on dense maps 89 and 157, a diverged fixed-point
  route passing the (I1) floor) and lists the 200 + 20 multipliers as an open
  item; today's failing identity is the scaling-invariance one at 1.11x, and
  `k_route_agreement` no longer fails. Measured since: the run is deterministic
  (a rerun reproduces 6.706850093838689e-12 to the digit) and identical at
  3a04d90, so the beam-beam batch did not move it; the validation README states
  the design ("the script's larger set can put a row ... on a map that exposes
  an analysis defect, over it; the gate then exits non-zero naming the row"),
  so the exit is the instrument naming a candidate, not a broken script. Left to
  disposition in §7: whether `c_scaling_invariance` at 1.11x on map 98 is the
  recorded open item (the multipliers frozen on 20 + 5 maps, `_REAL_CLASS_MULTIPLIER`
  in the Twiss row's owner items) or a scaling-invariance defect of the analysis
  on an ill-conditioned dense map. The stage 9 record decides it: its row 19
  (measurer M3) already records `c_scaling_invariance` over budget on the
  200-map set with the multiplier frozen on 20 + 5 maps, "RECORDED for the
  owner: re-freeze on the 200-map set (c doubling on ~15 rows)", and the Twiss
  todo row carries it among the owner items (`_REAL_CLASS_MULTIPLIER`). So A-1
  is the recorded open item measured again (1.11x on 6x6 map 98 today; the
  record's table shows 1.339 on 4x4 map 1 at the time), not a new defect; it
  goes to §7 as the owner decision it already is, with today's numbers.
- **A-2 [Minor, lead]** The full gate's log carries 25 `rng_id ... is already held
  in this process` warnings (counter_rng.jl:280), the collision warning the
  2026-10-16 batch made loud; the Phase 7 single-process contract run emits the
  same for beams and radiation claiming `rng_id = 1` after a BPM observer
  auto-assigned it. Either the fixtures intend the collision (and a `@test_logs`
  pins it) or the suite is noisy where a real collision would hide; the test
  units (U28-U37) say which, and the seam pass checks whether any shared
  stream is a real one.
- **A-3 [info]** Phase 7 on 24e8683, CUDA active: all 16 registered contracts
  pass their own `validate` (`exec/contracts.log`, `exec/contracts_2.log`): the
  element backend-consistency contract on a four-element line, the PIC
  multi-process contract under the MPI launcher (one rank bitwise with the CPU
  policy, two ranks within 5.48e-17 absolute), the two effectiveness contracts
  (530 element parameters, 73 + 10 solver options reached their consumers), the
  identity contract (57 identities, 160 fixture runs), the external reference
  contract (692 rows, worst ratio 0.357), PTC (61 cases, 5.0e-13), the MAD-X
  survey (9 lines, 7.1e-15), symplecticity, the coherent-mode and high-energy
  physics contracts, the three backend-consistency contracts and the knob
  contract. Phase 10: all five example scripts exit 0 (`exec/examples.log`).
- **A-4 [Moderate, confirmed]** `validation/moment_observer_backend_consistency.jl`
  cannot run on 24e8683: line 42 constructs `MomentObserver(tempname() * ".h5")`,
  the standalone writer form retired on 2026-08-18 (`BeamObservers.jl:660`
  throws naming the retirement), so it exits 1 before measuring anything
  (`exec/validation_moment_observer_backend_consistency.log`), while
  `validation/README.md` lines 817-824 document it as a runnable CUDA check and
  CI, having no GPU, never reaches it. Its last commit is d768001 (2026-08-06),
  before the retirement: the constructor's acceptance change was not measured
  against `validation/` (invariant 2). The suite has no CPU-versus-CUDA
  `MomentObserver` reduction parity testset (grep of `test/runtests.jl`), so the
  backend parity of the default moments has had no executing check since
  2026-08-18. Phase 10 total: 11 validation scripts exit 0, two exit 1 (A-1, A-4).
- **A-5 [observation, Phase 8]** the native arm of the full gate on canon-A
  (24e8683, CUDA active, 4 threads, `full_gate_native_canon_gateAudit.log`)
  died with `received signal: 11` at 00:28 EDT on 2026-10-19 inside the
  "Elements and scripts follow-ups" testset, after every earlier testset
  passed (the last printed summary: "Turn modulation: rules, wrapper and the
  pure hook | 582 582"), while ten reading agents ran CUDA probes on the same
  machine. The sequential script therefore did not start the AVX2 arm. The
  same tree passed this arm in the two-arm gates of 2026-10-18 before the
  push. Disposition: re-run both arms on a quiet machine after the reading
  waves finish (Phase 8 is owed on the final tree in any case); a second
  segfault at the same testset would be a finding (that testset redefines
  `observer_option_schema(::Type{BPMObserver})` at `runtests.jl:17769` while
  the suite runs at four threads, the method-overwrite warning printed just
  before the crash). **Re-run 2026-10-19 02:07-02:39 on a quiet machine (load
  0.45, no agent running, GPU idle but for the owner's notebook kernel
  holding 11.9 GB): signal 11 again, same place, 32 min in
  (`full_gate_native_canon_gateAudit2.log`, 602 lines, the same 577 summary
  lines then the two method-overwrite warnings then the Pkg error).** A-5 is
  therefore a confirmed finding, F-244 below; the diagnosis runs of §6 say
  what is known.
- **A-6 [Minor, confirmed]** `src/beam/Beam.jl:29` the documented constructor
  `BeamParams(; charge, mc2, E0, r0, npart)` works only when all five keywords
  are given: with any omitted, the `@kwdef` default `zero(FloatT)` references
  the type parameter the keyword method does not bind and the call dies with
  `UndefVarError: FloatT not defined in Octopus` (auditor one-liner: four of
  five given fails, all five succeed, `BeamParams{Float64}(...)` works). An
  undirected error on a documented public form (the class U27-8 names).

### Confirmed findings (auditor reproduction on 24e8683, CUDA active, 4 threads; probe re-runs under `result/comprehensive_audit_2026_10_18/probes/auditor/`)

Each entry names the unit lead it confirms, the anchor, the mechanism read in
the source by the auditor, and the auditor's own measurement. Severity is the
auditor's.

- **F-1 [Major] U3-1** `src/tasks/strongstrong/pic_cuda.jl:4536-4567`
  `_cuda_pic_bounds_block_reduce` shuffles with the full warp mask and the
  first warp then reads `cld(blockDim, 32)` partial slots, so a block whose
  thread count is not a multiple of 32 folds undefined lanes (0.0 on this
  device) into min/max interaction-grid bounds. `CUDAPICLaunchConfig` accepts
  any `field_threads` in 1:1024 (interface.jl:138-139) and the launch-geometry
  sweep tests only 64/128/256/512. Auditor re-run of `probes/U3/probe2_bounds_warp.jl`:
  threads 100/48/20/16/7/1 wrong on every repeat, 32..1024 warp multiples
  bitwise equal to the host reference; `probe3b_e2e_offset_beams.jl`: offset
  beams at `field_threads=100` vs 128 differ by max|dpx|/max|px| = 3.8e-2,
  max|dpy|/max|py| = 0.199, luminosity 45.4% (5.548e29 vs 1.0166e30), while 96
  and 64 agree to 5e-15 and 3e-14. Centred beams hide it because min < 0 < max
  absorbs the stray zero. Class: unvalidated public option reaching a kernel
  with a precondition the option schema does not state.
- **F-2 [Major] U1-1** `src/tasks/strongstrong/pic_cuda.jl:1839` (and the
  sibling launch two lines below) launch `_cuda_pic_force_luminosity_bounds_indexed_kernel!`
  with the raw `:field` thread count; the kernel compiles to 68 registers
  (maxthreads 896 on this device), so `field_threads=1024`, or a plain
  `CUDAExecutionPolicy(launch=CUDALaunchConfig(threads=1024))` with no PIC
  launch config, fails the default production route (indexed wavefront,
  luminosity on) with `Block register count exceeds device limit`. The cap
  `_cuda_launch_capped!` (pic_cuda.jl:65) that the 2026-08 audit introduced for
  this class is applied at two of the region's eighteen launch sites and not
  here. Auditor re-run of `probes/U1/repro_field_threads.jl`: 896 RAN, 1024
  FAILED, policy threads=1024 FAILED, 1024 with luminosity disabled RAN.
  Severity Major because a legal public value crashes a default route at run
  time with a device error, not a message naming the option.
- **F-3 [Major] U2-1** `src/tasks/strongstrong/pic_cuda.jl:2447-2453` with
  `green_type=:standard` and the default `green_cache=:slice_pair`: the cache
  entry expands the grids by `1 + slice_pair_green_growth` and realigns with
  `_pic_realign_expanded_grids` on both backends; the half-cell sign test in
  `_pic_align_grid_origins` (pic_cpu.jl:2129) sits exactly on `t == 0` after
  the 1.25x expansion and the device's FMA-contracted bounds flip it. Auditor
  re-run of `probes/U2/probe_standard.jl` (CPU vs CUDA, same beams, 25 slice
  pairs, 2 turns): defaults pair_rel 1.4e-4, coord_rel 7.8e-3, lum_rel 6.5e-6;
  `cuda_indexed_wavefront=false` coord_rel 1.0e-2; grid (64,64) pair_rel
  3.7e-4; `green_cache=:none` restores pair_rel 2.5e-15 / coord_rel 5.5e-14;
  the `:integrated` and `:lattice` controls agree to 1e-13. The agent also
  measured CUDA run-to-run non-reproducibility (7e-3) on this route; the
  auditor's re-run did not repeat that part. Class: CPU/CUDA twin divergence
  through a sign test on an exactly representable boundary (the fusion class of
  fix I, here landing on a branch).
- **F-4 [Major] U6-1, U6-2, U6-3** `src/tasks/strongstrong/interface.jl:3270-3314`
  `_split_strong_strong_line` compiles each element straight through
  `_append_runtime_line!` and never runs the three binding steps the
  TrackingTask compile performs at `Tasks.jl:1666-1668` (`_bind_apertures`,
  `_bind_survey`, `_validate_reference_chain`). This is seam S5 of §3 measured.
  Auditor re-run of `probes/U6/p1_rf_survey_twin.jl`: a `ThinRFCavity` in a
  strong-strong line reports `ds_turn = NaN` where the same line through a
  TrackingTask reports 100.0; one turn differs by max|dz| = 0.1986 at sigma_z =
  1e-2 (the slip term `ds_turn (beta/beta0 - 1)` the survey binds), the
  cavity-free control is bitwise equal. `p7_followups.jl`: the two-E0 lattice
  the TrackingTask refuses ("cavity reference chain broken") is ACCEPTED and
  tracked by the StrongStrongTask; `loss_summary(rep, ::StrongStrongTask)`
  throws a `MethodError` (no `loss_counts` method), so an aperture in a
  strong-strong line has no loss record route at all. `p2_aperture_record.jl`
  (auditor re-run): an aperture placing 2 of 8 particles outside, in a
  strong-strong line, without `allow_lost_particles` is refused at the
  collision with a message blaming "non-finite particle coordinate(s) ... in
  the beam particles" (loud, but naming the beam, not the aperture); with
  `allow_lost_particles` the two particles are NaN after one turn with no loss
  record, no count, no `/losses` group in the artifact (top-level groups
  `execution`, `luminosity` only) and zero construction-time warnings, while
  the same beam through `TrackingTask((ap,))` reports 2 lost, by name.
  Severity Major: a line that is correct through one task type tracks a
  different model, silently, through the other; the `harmon=` cavity form is
  the one case that refuses loudly.
- **F-5 [Moderate] U7-1** `src/tasks/strongstrong/spectral_cuda.jl:882` the
  CUDA 6D route adds `length(idx1) + n2` luminosity deposits to the tripwire
  denominator `ndep` under `compute_luminosity`, while the transverse route
  (690, 696) counts only the clippable deposits and the comment at 717 states
  the luminosity deposits cannot clip. Auditor re-run of
  `probes/U7/p2b_ndep_schedule.jl`: the same 298.876726 units of dropped charge
  read `dropped_fraction = 9.72906e-02` on a turn where luminosity runs
  (nsource = 3072) and a larger fraction on a turn where the schedule skips it;
  the suite's testset (runtests.jl:29706) asserts only that a warning fires.
  Class: one quantity, two denominators across a schedule boundary.
- **F-6 [Moderate] U6-4** `src/tasks/strongstrong/interface.jl:3024,3049-3058`
  `_LUM_SCHEDULE_MEMO` is one process-global slot keyed by `(objectid(schedule),
  turn)`; it ignores the task, the `execute!` and every other field of the
  `TrackingContext`. Auditor re-run of `probes/U6/p4_receipts.jl`: task A at
  turn 0 consults its predicate once; task B, sharing the schedule object, at
  turn 0 consults it zero times (memo hit from A). By the comment's own design
  the sharing is intended within one turn of one task; across tasks it hands a
  verdict to a context the predicate never saw.
- **F-7 [Moderate] A-4** the stale CUDA validation script (above).
- **F-8 [Moderate] U8-1** `src/tasks/strongstrong/slicing.jl:119-131`
  `_strong_strong_luminosity_scales` divides by the shard's full macroparticle
  count (`last(_mp_current_shard(...))`, dead particles included) while every
  slicing weight and kick renormalises to the live count (slicing.jl:65-70,
  156). Under `allow_lost_particles` the soft-Gaussian luminosity therefore
  halves when half of beam 2 is dead while its own kicks do not, and the PIC
  luminosity of the same solver does not. Auditor re-run of
  `probes/U8/p3_gaussian_luminosity.jl`: half of beam 2 dead, L/L0 = 0.49976
  (`gaussian_when_luminosity=1`) vs 1.00087 (`=2`), beam-1 px-kick rms ratio
  1.0013 in both; without losses both routes agree with the sample-moment
  closed form to 0.3%. The suite's "renormalises" pin sets
  `luminosity_scale=1.0` and cannot see it. Class: two conventions for one
  quantity inside one solver.
- **F-9 [Moderate] U4-1** `src/tasks/strongstrong/pic_cpu.jl:1730-1741` on
  `interaction_grid=:node` the dropped-charge tally counts field particles
  against `gL.field_grid` only, never against `gR.field_grid` the right-plane
  interpolation also reads, and never against the longitudinal `phiZ` plane.
  Auditor re-run of `probes/U4/probe1b_node_field_count_graded.jl` (3000/beam,
  3 slices, grid 16x16, CIC, graded transverse size): at kbb = 3e-7 the tally
  ships 1284 while 117 right-plane-only and 103 phiZ outside-mesh
  interpolations go uncounted (the lower kbb rows ship 0 with 0 uncounted, so
  the tally is complete exactly when nothing is dropped). Class: incomplete
  tripwire; "loud beats silent" holds for one of three meshes.
- **F-10 [Moderate] U10-1** `src/contracts/Contracts.jl:850-878` the
  `PublicConfigurationEffectivenessContract`'s CUDA PIC launch-family check
  builds the `CUDAPICLaunchConfig` overrides AND the policy's
  `CUDALaunchConfig` from the same `contract.cuda_threads`, so the receipts
  read `contract.cuda_threads` whether the override reached the consumer or
  the fallback did. Auditor re-run of `probes/U10/probe_d_pic_families.jl`:
  the predicate is `true` with the overrides and `true` with no override at all
  (every family 128 under a 128-thread policy); with every family set to 64
  under a 128-thread policy the receipts do read 64, so the option itself
  works and only the contract cannot fail. Class: a contract that verifies
  nothing (invariant: contracts verify).

- **F-11 [Moderate, latent] U5-1** `src/tasks/strongstrong/pic_cpu_sliced.jl:1259`
  the non-finite verdict of a slice pair is per direction on the two plane
  owners but joint on the members (`red[61]`), so a pair with finite extents in
  one direction and non-finite in the other leaves a non-member owner waiting
  for partials that never come. Auditor re-run of `probes/U5/verdict_split.jl`
  reproduces the precondition at the unit level (direction 1 finite grids,
  direction 2 `nothing`, joint verdict 0.0: `SPLIT VERDICT = true`) in Float32
  `:sigma`; the agent and the auditor agree the trigger needs coordinates no
  physical beam reaches, so this is priced as a latent deadlock, not a live one.

### Confirmed Minor findings (static, verified by the auditor against the source)

| Id | Lead | Anchor | What the auditor verified |
|---|---|---|---|
| F-12 | U1-2 | `pic_cuda.jl` | 60 raw `CUDA.@cuda` launch sites file-wide against 13 `_cuda_launch_capped!` sites; no tripwire derives the set, the one pin sweeps one value on one family. Sibling of F-2. |
| F-13 | U2-3 | `pic_cuda.jl:2576` | `_cuda_pic_solve_field_with_green_fft` and `_cuda_pic_bounds_pair_combine` have zero callers in `src/`, `test/`, `validation/`, `profiling/`, `examples/`. |
| F-14 | U2-4 | `pic_cuda.jl:4020` | the luminosity overlap mesh arithmetic (`nx - 1.1`) is hand-copied three times in the CUDA file; the CPU file has a shared `_pic_luminosity_mesh` the CUDA file never calls. |
| F-15 | U3-5 | `pic_cuda.jl:4810` | `_cuda_pic_batched_luminosity_enabled() = false` (line 612) leaves `_cuda_pic_luminosity_wavefront_kernel!`'s only launch (3801 branch) unreachable: device code nothing executes. |
| F-16 | U4-4 | `pic_cpu.jl:461` | a `nothing` node-mesh lookup skips the pair silently (`return false`, no kick, no luminosity, no warning) while the sibling check at 448-452 is a loud invariant violation. |
| F-17 | U4-5 | `pic_cpu.jl:550` | the single-workspace `_pic_report_dropped(::_PICCPUWorkspace)` has no caller (the two call sites pass pools); it lacks the pool form's cross-rank sum and rank-0 gating. |
| F-18 | U5-3 | `pic_cpu_sliced.jl:208` | `_pic_sliced_migrate_in` and `_pic_sliced_migrate_out!` have zero callers; two hand-maintained twins of the live pair migration. |
| F-19 | U5-7 | `docs/design/multi_process_policy.md:452,470` | the Step 4d narrative ("to every rank involved in the pair", "each PLANE of the pair") describes a protocol the code no longer runs (the reduced record goes to the two owners only). |
| F-20 | U6-11 | `interface.jl:891-902` | the `GaussianPoissonSolver` docstring signature block omits `luminosity_schedule`, which the constructor takes. |
| F-21 | U8-5 | `slicing.jl:88` | the slicing method list is hand-copied between the constructor's membership test and the dispatch chain; `:equal_spaced` and `:Gaussian` appear in no test (0 hits in `runtests.jl`). |
| F-22 | U8-6 | `gaussian.jl:232` | bare `0.5` literal in the moving-centroid pz term where the 15 weak-strong twin sites use `oftype(S, 0.5)` (fix H); CPU and CUDA agree today, style-level. |
| F-23 | U10-8 | `Contracts.jl:1699` | the `SymplecticityContract` docstring signature omits `lorentz_inverse_tolerance` and `lorentz_determinant_tolerance` (fields at 1740-1741). |
| F-24 | U10-9 | `Contracts.jl:1982` | the tripwire's failure message says "kinds declare SymplecticityContract" while the code derives the obligation from `Symplectic6DMap` membership. |
| F-25 | U10-10 | `Contracts.jl:1076` | `deposit_method in (:CIC, :TSC)` hand-copied at 3 sites in `src/` with no shared source and no tripwire. |

### Confirmed findings from the auditor's probe re-runs (wave 1, Moderate and Minor)

| Id | Lead | Anchor | Auditor's measurement (re-run of the unit's probe on 24e8683) |
|---|---|---|---|
| F-26 [Moderate, performance] | U4-2 | `pic_cpu.jl:2986` | any `luminosity_grid != grid` routes every pair through the allocating `_pic_luminosity`: 5.3 kB/call at (16,16), 68 kB/call at (64,64) vs 416 B when the grids match; a 225-pair bare collide allocates 21.6 MiB vs 6.2 MiB. |
| F-27 [Minor] | U1-3 | `pic_cuda.jl:1743` | Float32 beams: CPU/CUDA gap 4.1e-7 (dx/sigma_x) to 2.6e-5 (dpy/max py) with no declared cross-backend class; Float64 beams 1e-14. |
| F-28 [Minor] | U3-2 | `pic_cuda.jl:5670` | CUDA `:equal_width` membership by comparison vs CPU `_slice_bin` division: 5 of 6 constructed Float32 boundary-sitting particles land in different slices; 0 of 6 in Float64; the suite pin says bit-identical. |
| F-29 [Minor] | U3-3 | `pic_cuda.jl:6020` | wavefront Gaussian route rounds `min_sigma` to the beam type before squaring: floor^2 differs 5.1e-8 / 7.1e-8 / 2.3e-8 relative from the sequential route at 1e-5 / 3e-6 / 1e-7; inert at the default 0. |
| F-30 [Minor] | U3-4 | `pic_cuda.jl:5490` | `GaussianPoissonSolver{Float32}` on Float32 beams returns Float64 luminosity under `batch_mode=:sequential` and Float32 under `:wavefront` (`TWOPI` rebinding). |
| F-31 [Minor] | U4-3 | `pic_cpu.jl:2510` | the `_pic_tsc_weights` docstring claim that the one-cell displacement cannot arise on an interaction mesh is false on `:node`: at kbb = 3e-7 the uncounted right-plane (102) and phiZ (93) interpolations recur with TSC. |
| F-32 [Minor] | U5-2 | `pic_cpu_sliced.jl:390` | pair migration allocates 1.17 MB (20000/beam) to 4.80 MB (80000/beam) per collide, 72% from two `push!`-grown `Int[]` buckets, against the pooled-buffer design intent. |
| F-33 [Minor] | U7-2 | `spectral_cuda.jl:191` | under `field_precision=:single` the 6D luminosity buffers (`qlum1/2`, the snapshot) are Float32: pair-level 1.9e-8 relative vs a Float64 workspace; the transverse luminosity is bitwise. |
| F-34 [Minor] | U7-3 | `spectral_cuda.jl:200` | the mesh-width advisory and `:spectral_grid_transform` receipt exist only on the CPU constructor; cuFFT measured 2.7x per solve at (256,256) vs (255,255) (529 vs 197 us) with no note on CUDA. |
| F-35 [Minor] | U7-6 | `spectral.jl:856` | `:grid_free` evaluates a field point past the Dirichlet wall through the odd extension with no guard: Phi(1.05L) = -0.130, Ex = +2.63e3 (growing to 4.0e3 at 1.5L), no warning; `:grid` returns 0 there. |
| F-36 [Minor] | U7-8 | `spectral.jl:570` | the dropped-charge tripwire's `@warn maxlog = 8` goes silent for the process: 4, 4, 0, 0, 0 warnings over five identical clipping collides; no execution receipt names dropped charge. |
| F-37 [Minor] | U8-2 | `spectral_sliced.jl:31` | the "bit for bit at one rank" header holds for Float64 beams only (0/2688 differ); Float32 beams differ in 350-1067 of 2688 coordinates, up to 55 ulps (Float64 solver) and 2048 ulps (Float32 solver, grid_free). |
| F-38 [Minor] | U7-4 | `spectral.jl:171` | `domain_factor=Inf` and `1e308` are accepted; `Inf` fails later with the misleading "DERIVED quantity" error on both backends, `1e308` runs silently (agent's `p4_box_receipts.jl` section 3; auditor re-run exit 0, same sections). |
| F-39 [Minor] | U7-5 | `spectral_cuda.jl:671` | the `:spectral_pair_schedule` receipt has 8 keys on CPU and 5 on CUDA against the "one receipt shape across the routes" comment (same probe, section 4). |
| F-40 [Minor] | U7-7 | `spectral_cuda.jl:803` | the 6D CUDA luminosity allocates exactly 4 n1 N2 8 bytes per collide (19.2 MiB at 40000 particles, 15 slices); the transverse route allocates per-pair luminosity grids (25.2 MiB). |

Clean on re-run, recorded for the clean ledger: `U8/p4_near_round_continuity` (coupled vs uncoupled CP kick at the eta bounds, 0 to 2e-16), `U3/probe4` section (b) (bounds reduction bitwise at 512 and 1024 threads), `U5/bitwise_*` (sliced route bitwise vs undivided, agent logs).

### Confirmed findings, units U9 and U10 (auditor re-runs and source reading)

| Id | Lead | Anchor | Auditor's verification |
|---|---|---|---|
| F-41 [Moderate] | U9-1 | `gaussian_pic.jl:1292-1297` | `_gpic_profile_buffers` carves length-`ny` views along the first (2nx) dimension of `workspace.green`; any legal grid with ny > 2nx throws `BoundsError` on the multi-process (slice-aligned) route while the undivided CPU route runs it. Re-run of `probes/U9/p1_sliced_profile_buffers.jl`: five square/wide configurations bitwise CPU = MP at one rank; `tall_8x32` and `tall_8x32_tsc_coupled`: CPU ok, MP policy THROWS. |
| F-42 [Minor] | U9-2 | `gaussian_pic_cuda.jl:949-987` | the two indexed gpic kick kernels are not grid-strided but go through `_cuda_launch_capped!`, whose contract says every routed kernel is; the longitudinal kernel is capped 1024 to 256 on every launch and coverage survives only through the blocks rescale (re-run of `p3b_cap_control.jl`: capped vs CPU 1.4e-13, 0 of 4000 particles off). |
| F-43 [Minor] | U9-3 | `gaussian_pic.jl:1344-1350` | reduced-record slot literals (`red[61]`, `o + 9`, `o + 21..24`) hand-copied from `pic_cpu_sliced.jl` (729, 1027) with no accessor or tripwire; consistent today (`p4_kernel_stride_and_lists.sh`). |
| F-44 [Minor] | U9-4 | `gaussian_pic.jl:150-153` | `_GPIC_INERT_PIC_OPTIONS` (the previous audit's U10-1 fix) is a hand list named at two rejection sites and in no test (`grep` of `src/` and `test/`). |
| F-45 [Minor] | U9-5 | `gaussian_pic_cuda.jl:227,1149,1159` | three bare `CUDA.@cuda` launches beside four capped ones in the same file (twin-consistent with pic_cuda.jl, loud failure mode; sibling of F-2/F-12). |
| F-46 [Minor] | U10-2 | `Contracts.jl:1170-1178` | the PIC backend contract derives its slice-pair expectation from the CPU output (`cpu_pair_map`), so zero compared rows would pass; today 18 of 18 compare (re-run: `slice_pair_luminosity_records_compared = 18`). |
| F-47 [Minor] | U10-3 | `Contracts.jl:542-552` | on `-t1` the public-configuration contract returns `:passed` with "reached CPU, fused CUDA, and CUDA PIC consumers" while `cpu_worker_effective = not_measured` (re-run of `probe_j_t1_public_config.jl`, 91.5 s). |
| F-48 [Minor] | U10-4 | `Contracts.jl:1267` | an unsupported backend type is reported as `:skipped` ("Unsupported backend Int64." / "Float64."), the status reserved for unavailable resources (re-runs of the one-liner and `probe_k_margins.jl`). |
| F-49 [Minor] | U10-5 | `Contracts.jl:610-620` | a fresh `-t1` `validate(PublicConfigurationEffectivenessContract())` emits 2 counter-RNG registry warnings the comment at 612-616 says the probe avoids (re-run log: 2). Sibling of A-2. |
| F-50 [Minor] | U10-6 | `Contracts.jl:90-98` | the Gaussian and PIC backend contracts' allowances `atol = rtol = luminosity_rtol = 1e-10` sit six orders above the measured 6.5e-16 / 2.3e-15 (global_rel_error) with no derivation recorded. |
| F-51 [Minor] | U10-7 | `Contracts.jl:1814-1850` | the twelve older symplecticity cases keep tolerances 7.5e-5 to 1.3e-2 of their residuals (ratio column of `probe_f_symplecticity.jl`), against the file's stated ~100x principle for the newer cases. |
| F-52 [Minor] | U10-11 | `Contracts.jl:645-651` | the output-boundary check records gaps, not coverage: `isempty(_output_receipt_gaps(Any[], Pair[]))` is `true`, so a run with no output consumer passes identically to one where every option is carried. |
| F-53 [Minor] | U10-12 | `Contracts.jl:1476-1506` | `_mpi_pic_contract_base`, `_mpi_pic_contract_args`, `_mpi_pic_contract_spec` are three hand-written field lists (the base omits `threads_per_rank` and the tolerances; the args/spec pair must agree key by key) with no derivation from `fieldnames` and no tripwire (read by the auditor). |
| F-54 [Minor] | U10-13 | `Contracts.jl:711-730` | (cross-file seam) a `StrongStrongTask` whose Gaussian solver cannot derive `kbb` refuses only when the collision is reached, after upstream elements mutated the beams (`probe_b_misc.jl` section B: `beams unchanged after that throw => false`). |
| F-55 [Minor] | U10-14 | `Contracts.jl:352-359` | (cross-file seam) `compile_runtime(ElementSpec{:crab_dispersion}(; zeta1=0.0, ...))` fails with a raw `KeyError: key :zeta2 not found` (re-run of the one-liner and `probe_a_knob_unset_guard.jl` rows 1 and 5), not an `ArgumentError` naming the missing parameter; same class as U19-3. |

Clean on re-run: `probe_c2_device_mismatch` (device mismatch refused, beams unchanged; CPU storage under a CUDA policy refused), `probe_k_margins` CPU/CPU exact zero, `probe_l_rng_warning` (one warning per process, as the comment says).

### Confirmed findings, unit U13 (the run artifact) and U15 (turn modulation), auditor re-runs from `probes/auditor/U13_rerun/`

- **F-56 [Major] U13-1** `src/tasks/RunArtifact.jl:688` under `append=true` four
  by-name refusals of `prepare_run_artifact!` fire AFTER the replay truncation
  has dropped every luminosity row at or beyond `first_turn`. Re-run of
  `probes/U13/probe_A_artifact.jl` sections A1/A1b: 100 rows and cursor 99
  before; the `/execution` ledger refusal and the `/turn_modulation/1`
  partial-slot refusal both leave 50 rows, cursor 49, file closed, no lock. A
  refused continuation damages the file it claims to leave as found. Class:
  ordering of validation after mutation (the same class as the strong-strong
  kbb refusal, F-54, one level down in the artifact).
- **F-57 [Major] U13-2** `src/tasks/RunArtifact.jl:1190` `/losses` does not
  follow the replay rule under `append=true` across task objects: a continued
  window written by a NEW task deletes the group and rewrites it from an empty
  record. Re-run of `probe_B_losses_restart.jl`: window 1 (task A) 1 loss row,
  window 2 (same task) 1 row at turn 3, window 3 (new task B) 0 rows,
  `aperture_counts = [0]`, `summary.dead = 0`, while the ledger records three
  windows. The design's "append=true across process restarts" promise is the
  claim the measurement falsifies.
- **F-58 [Moderate] U13-3** `RunArtifact.jl:1346` probe groups are truncated
  one bind at a time, so a later probe's bind refusal leaves every earlier
  probe cut back to `first_turn - 1`. Re-run of `probe_E_bind_and_attrs.jl`
  E1: m1 and m2 at 10 rows; a refused window 2 (duplicate `/moments/m2`)
  leaves m1 at 5 rows and m2 at 10. Sibling of F-56.
- **F-59 [Moderate] U13-4, U14-3** `RunArtifact.jl:1539`, `BeamObservers.jl:1487`
  no public reader applies or exposes `rows_valid_through_turn`: a file with 20
  rows on disk and cursor 9 reads as 20 rows in the table of contents and in
  `read(TaskOutput(p), :luminosity)`; the writer, continuing at
  `first_turn = 1000`, truncates to 10 (probe A section A2; U14's
  `p4_reader_cursor.jl` re-run reports record_count 8 for 6 valid rows).
- **F-60 [Minor] U13-5** `RunArtifact.jl:1434` under a lock `_ra_open` replaces
  the open's own error with the fixed "failed twice while a live Octopus writer
  holds its lock" diagnosis: a stale lock beside a missing file or a text file
  is misreported as a flush race (section A3, both cases).
- **F-61 [Minor] U13-6** `RunArtifact.jl:1736` one stray non-numeric group
  under `/turn_modulation` makes `read(out)` and `turn_modulation_provenance`
  fail with `invalid base 10 digit 'f' in "foo"`, an error that does not name
  the group; a foreign top-level group fails `read(out, :all)` with "unknown
  artifact product :foreign" (section A5).
- **F-62 [Minor] U13-7** `RunArtifact.jl:918` the `/turn_modulation/<slot>/<k>`
  element group carries attributes `beam`, `element`, `slot_count` only (no
  spec label, no `s`), so two cavities of one type in one line are told apart
  by order alone (re-run of `probe_D_recording.jl` D1).
- **F-63 [Minor] U13-8** `RunArtifact.jl:412` the cursor is advanced by
  delete-then-create; a group whose cursor attribute is absent is truncated to
  0 rows by the next append-open, rows below `first_turn` included (section A7:
  10 rows, all below `first_turn = 1000`, become 0).
- **F-64 [Minor] U13-9** `docs/design/run_artifact.md:90` the schema table
  declares an `s` attribute on `/luminosity/<label>` and a provenance path on
  `/moments/<name>` that the writer never stamps (`/luminosity/ip attrs =
  ["label", "rows_valid_through_turn"]`, section A6).
- **F-65 [Minor] U13-10** `docs/design/run_artifact.md:444` the concurrent-reader
  claim cites its evidence in the git-ignored `result/` tree and no committed
  harness reproduces it (grep: two prose mentions, no script). Invariant:
  `result/` is never evidence.
- **F-66 [Moderate] U15-1** `src/elements/turn_modulated.jl:1965` the
  provenance slot entry of a `WhiteNoise`/`PinkNoise` slot records neither
  `sigma` nor `octaves`: re-run of `probes/U15/probe3_pink_receipt.jl`: white
  sigma 1e-5 vs 2e-5 under one id, receipt entries equal = true; pink 8 vs 16
  octaves, equal = true (entry = slot, kind, rng_id, digest 0, name "", length
  0). Two runs that differ in a rule's rms are indistinguishable from their
  receipts and from the artifact.
- **F-67 [Minor] U15-2** `src/elements/crab_cavity.jl:460` a live rule on a
  complex-typed cavity passes construction and `compile_runtime` and dies at
  the first update with `MethodError: no method matching octopus_normal(...,
  ::Type{ComplexF64})` (re-run of `probe1_alloc_keys.jl`), while a table on
  the same cavity is refused by name at construction.
- **F-68 [Minor] U15-3** `turn_modulated.jl:1763` the shared-`rng_id` warning
  asserts "identical values ... fully correlated noise" for a white rule and a
  spectral table sharing an id that share no RNG cell: measured correlation
  0.054 over 1024 turns (re-run of `probe2_spectral.jl`).
- **F-69 [Minor] U15-4** `src/track/phase6d_track.jl:428` `_track_cuda_elementwise!`
  on the three wrappers is a wrapper-descending walk the wrapper-walk tripwire's
  single source (`runtests.jl:10751-10769`) does not list (grep: no entry in
  `wrapper_walks`). Seam S1 of §3, the same class the 2026-10-18 batch closed
  for `_aperture_rebind`.
- **F-70 [Minor] U15-5** `turn_modulated.jl:690` the `spectral_turn_table`
  docstring and design note D5 key the Rayleigh moduli on `0` in the turn field;
  the code keys them on the table's `slot` (grep of both files).
- **F-71 [Minor] U15-6** `turn_modulated.jl:760` `spectral_turn_table` prints
  the fewer-than-32-bins warning before refusing `rng_id = 0` (one-liner).
- **F-72 [Minor] U8-4** `slicing.jl:514` `:specified` accepts a `NaN`
  position and diagnoses it as a non-finite DERIVED beam quantity ("but all 500
  beam macroparticle coordinates (z) are finite", re-run of
  `probes/U8/p1_slicing_invariants.jl` P1e); the agent's clamping measurement
  (out-of-range positions into a zero-width top slice) stands on its log.

### Confirmed findings, units U12 (Tasks.jl) and U14 (the observers), auditor re-runs from `probes/auditor/U12_rerun/`, `U14_rerun/`

- **F-73 [Major] U14-1** `src/tasks/BeamObservers.jl:851` `observe!(::MomentObserver)`
  increments `buffer_length` before the row is computed, so an exception inside
  `_moment_observer_row` leaves a stale or undefined row that the best-effort
  finalize pushes; the artifact stamps its cursor from that row and the retry
  of a chunked run destroys chunk 1. Re-run of `probes/U14/p2_garbage_row.jl`:
  after the injected chunk-2 crash the turn column is `[0,1,2,3,4,5,0]` (S2) or
  `[0,...,5,6.9e-310]` (S3) with cursor 0; after the retry (owed turns 0:7) the
  file holds `[0,4,5,6,7]`, cursor 7. Clean-finishing data loss.
- **F-74 [Major] U14-2** `src/tasks/RunArtifact.jl:1293` `_ra_truncate_probe!`
  keys the torn-tail rule on the turn VALUE (`searchsortedlast(turns,
  keep_through)`), so a tail of HDF5 fill rows (turn 0) is never removed and a
  continuation appends after it. Re-run of `p4_reader_cursor.jl`: 6 rows,
  cursor 5; a simulated torn tail of two fill rows survives the continuing
  `execute!`: turn column `[0,1,2,3,4,5,0,0,6,7]`, cursor 7. Seam of F-73 with
  F-59.
- **F-75 [Moderate] U12-1** `src/tasks/Tasks.jl:818` an in-line observer placed
  through `BeamLine` (the flattened `LineEntry` form) is invisible to the probe
  arc-position walk: `/moments/m` attribute `s = 1.0` from the flat tuple, `s =
  missing` (probe map size 0) from the `BeamLine` form (re-run of
  `probe_u12.jl` P4). Seam S1 (walkers disagree on a container).
- **F-76 [Moderate] U12-2** `Tasks.jl:1385` the unfireable-schedule warning
  covers task-level observers only: `AtTurns([500])` on a 10-turn window warns
  for the task-hook observer and is silent for the line-placed observer, the
  task action and the line action (P3), with no suite pin.
- **F-77 [Moderate] U12-3** `Tasks.jl:1051` a failure in the success path's
  output step after `task.next_turn[] = next_turn` advances the stored turn
  against the documented "a failed call does not advance the stored turn" and
  leaves the artifact open and locked; the retry is refused "already open"
  (re-run of `probe_u12_p5b.jl`: after the 1st, next_turn 3, open, locked; the
  2nd refused; the 3rd runs from turn 3).
- **F-78 [Moderate, performance] U14-4** `BeamObservers.jl:1066` the CPU
  `_moment_observer_row` costs 27.6 ms/call at N = 1e5 for the default 27
  moments (75% of a harness-like turn at four threads; tracking 17%), 4.80 MB
  allocated per call from six `collect` copies (re-run of `p3_cost.jl`; the
  agent measured 38 ms). This is the open todo row's number, measured.
- **F-79 [Moderate, performance] U14-5** `BeamObservers.jl:907`
  `observe!(::CoordinateSnapshotObserver)` copies all six whole arrays
  device-to-host per fire: `npart=16` costs 29.4 ms/fire and 122.9 MB D2H at N
  = 2.56e6 on CUDA, against 0.05 ms for six 16-element views (re-run of
  `p6b_snapshot_cuda.jl`); the `npart` knob does not control the cost.
- **F-80 [Minor] U12-4** `Tasks.jl:1376` the `:tracking_output` receipt is
  recorded ahead of the observers' prepare refusal (a duplicate probe name):
  receipts `[:run_artifact_output, :tracking_output]`, no turn tracked (P2).
- **F-81 [Minor] U12-5** `Tasks.jl:859` an in-line hook inside a line that
  compiles whole dies at the first `execute!` with a raw `MethodError: no
  method matching compile_runtime(::ScheduledObserver{...})` (P1, both forms).
- **F-82 [Minor] U12-6** `Tasks.jl:1036` the crash path computes the loss
  summary twice (2 calls vs 1 on the success path, P7).
- **F-83 [Minor] U14-6** `Tasks.jl:1557` the "cannot fire" `@warn` has the
  line-continuation `\` outside the string literal, so `schedule = schedule \
  turns = turns` parses as one argument and the warning prints a closure in
  place of the schedule and omits `turns` (read by the auditor; the agent's
  parse probe counts 3 keyword arguments).
- **F-84 [Minor] U14-7** `BeamObservers.jl:847` `observe!(::MomentObserver)`
  records its `:observer_output` receipt before the `initialized` refusal (one
  receipt after two refused fires, `p1_protocol.jl` R); the snapshot twin
  refuses first.
- **F-85 [Minor] U14-8** `BeamObservers.jl:215` the path registry warns once on
  a legitimate sequential continuation with the wording "a second live
  observer" (p1, one warning before block E whose turns are exactly 0:11).
- **F-86 [Minor] U14-9** `BPMObserver.jl:76` "the memory arrays and the artifact
  cannot disagree" is false under the default `append=false`: after two
  `execute!(turns=3)` the file holds turns `[3,4,5]`, memory `[0..5]` (p1 D).
- **F-87 [Minor] U14-10** `BeamObservers.jl:971` `planned_records` is written
  at prepare and read nowhere (grep: two hits, both writes).
- **F-88 [Minor] U14-11** `BPMObserver.jl:273` a Float32 beam's BPM centroid is
  accumulated in Float32 (2.6e-11 from the Float64 moment, 1.2e8 Float64 ulps)
  while the moment observer promotes to Float64 (`p5_bpm.jl`).
- **F-89 [Minor] U14-12** `BPMObserver.jl:387` one BPM placed twice works in
  memory mode and is refused in artifact mode as "duplicate probe name" (p5).
- **F-90 [Minor] U14-13** `BPMObserver.jl:403` the nine device-model options
  declare consumer `:bpm_reading`, under which no receipt is recorded, and
  `/bpm/<name>` carries attributes `name`, `rows_valid_through_turn`, `s` only
  (p5): neither the receipts nor the file say which error model ran.

### Confirmed findings, units U19 (RF cavity, thin kinds, linear maps, radiation) and U20 (Track.jl, phase6d, rounding classes)

- **F-91 [Major] U19-1** `src/elements/rf_cavity.jl:139` `_rf_kick` returns
  early on `iszero(elem.strength)` BEFORE the `_has_survey` velocity-slip
  z-shift, so a survey-bound cavity at zero voltage drops its share of the
  slip. Re-run of `probes/U19/probe_B_task.jl` (task-compiled two-cavity ring,
  F16 fixture): strengths (S/2, S/2) give nu_s/nu_s(eta_full) = 0.9996;
  (S, 0) gives 1.633 and (0, S) gives 1.309, exactly the ratios of the slip
  fractions 0.3 and 0.7 the dead cavity owned. A ring with one cavity switched
  off tracks the wrong slip factor silently. Read by the auditor at 125-160:
  the early return predates the F16 closure, which added the survey branch
  below it (invariant 3: a fix's neighbours).
- **F-92 [Moderate] U19-2** `src/elements/thin_elements.jl:130` the shared
  `ThinMultipole` runtime reads `knl`/`ksl` on the kicker kinds and
  `hkick`/`vkick` on the multipole kinds, none of which declare those keys, so
  an undeclared key is tracked: `HKickerSpec(hkick=0.0, knl=(0.0, 0.1))` kicks
  px by -1e-4 at x = 1e-3; `ThinQuadrupoleSpec` with `hkick=1e-3` kicks px by
  1e-3 (re-run of `probe_A_specs.jl` A3; only `VKickerSpec(hkick=...)` warns).
  The unknown-key tripwire cannot see a key another kind declares.
- **F-93 [Minor] U19-3, U10-14 (F-55)** `src/elements/linear_maps.jl:17` the
  runtime constructors of `crab_dispersion`, `momentum_dispersion`,
  `xy_coupling`, `chromaticity_kick`, `lumped_radiation` read declared-default
  parameters through a bare `spec.params[key]`, so a raw `ElementSpec` with
  only its required keys fails with `KeyError` (A1: five FAIL rows; the
  friendly forms and `thin_rf_cavity`, `lorentz_boost`, `quadrupole` pass).
- **F-94 [Minor] U19-4** `src/elements/chromaticity_kick.jl:18` the untyped
  `ChromaticityKickSpec` hard-codes `Float64`: a complex `xi` throws
  `InexactError: Float64(1.0 + 0.1im)` where the three linear-map constructors
  promote (A2).
- **F-95 [Minor] U19-5** `src/elements/radiation.jl:250` the contextless
  `track_particle` methods of `LumpedRad` draw `Random.randn()` (not the
  counter RNG): the deprecated CPU backend-tag route differs from the CUDA
  route by max|dx| = 4.7e-4 after 3 turns where the context routes agree to 1
  ulp (re-run of `probe_C_radiation.jl` C3).
- **F-96 [Minor] U19-6** `radiation.jl:172` a `LumpedRad` whose only requested
  component is unavailable compiles to the identity with no warning
  (`Diffusion6DMap` with the default sigma; `Radiation6DMap` with
  `is_damping=false` and the default sigma: A6, warned? false, identity? true).
- **F-97 [Minor] U19-7** `linear_maps.jl:355` `xy_coupling` declares
  `alternatives=(XY_MODEA, XY_MODEB)` while the runtime accepts `XY_UNDEF`
  (the identity) (A4).
- **F-98 [Minor] U19-8** `rf_cavity.jl:496` the `L` ParamMeta of
  `thin_rf_cavity` still says "no velocity-slip term" (grep: one hit), false for
  a task-compiled cavity since the F16 closure.
- **F-99 [Minor] U19-10** `chromaticity_kick.jl:228` the `zeta`/`eta`
  parameters of `chromaticity_kick`, `lumped_radiation` and the `eta1..eta4` of
  `momentum_dispersion` are the canonical dispersion pair of (D6)-(D8), and no
  docstring or ParamMeta states the convention (grep "canonical": 0 hits in the
  three files). The 2026-10-18 lesson "one quantity, one convention" asks for
  exactly this statement.
- **F-100 [Moderate] U20-1** `src/track/Track.jl:343` the `CrossBackendRounding`
  bounds are 2-3-turn figures and the line rule (members' maximum) models
  neither accumulation nor amplification: re-run of `probes/U20/probe_cuda.jl`
  B3, `MarkerSpec(x_pitch=1e-3)` alone, px declared `:ulp` within 1024 ulps:
  95.5 (1 turn), 671.5 (10), 1951.5 (30, VIOLATION), 6431.5 (100). This is the
  todo row the 2026-10-18 batch opened ("the class composition rule does not
  model gradient amplification over turns"), now measured on a single element.
- **F-101 [Moderate] U20-2** `src/math/SpecialMath.jl:14` the two backends
  evaluate the elliptic beam-beam Faddeeva function with two algorithms
  (`erfcx(-im z)` from SpecialFunctions on the CPU, the N = 32 Weideman form on
  the device): same arithmetic, two routes, one backend: Kx differs by 599.5
  ulps of its scale, Ky by 209.9; bitwise-equal kicks 14 of 400 (re-run of
  `probe_cpu2.jl`). The elliptic class is set by the algorithm swap, not by
  the rounding the rule names.
- **F-102 [Minor] U20-3** `src/track/phase6d_track.jl:136-210`
  `_track_line_elementwise!` and `_flush_cuda_fused_segment!` (eleven methods)
  are a second, uncalled walker (grep outside the file: 0 hits) whose
  semantics differ from the live `_track_cuda_policy_elementwise!`.
- **F-103 [Minor] U20-4** `Track.jl:394` `_cross_backend_agreement` states
  `ulps_of_scale` in Float64 ulps for every element type: two Float32 reps one
  Float32 ulp apart measure 5.4e8 ulps (A3), so no class can be checked on a
  Float32 beam; two NaNs with different payloads violate an `:untouched` class
  with "max |a - b| = 0.0".
- **F-104 [Minor] U20-5** `src/track/radiation_track.jl:52` the radiation
  compatibility launch is a third copy of the grid-stride loop with four
  hardcoded 256-block caps across `radiation_track.jl` and
  `strong_beam_track.jl` and no `index_offset` (grep).
- **F-105 [Minor] U20-6** `Track.jl:315` `_rounding_written_over` keeps the
  inner `:bitwise` class for coordinates outside the wrapper's `written` set:
  `lumped_radiation` under a pitched or rolled frame keeps `:bitwise` on `z`,
  `pz` where the line rule would make them `:ulp` (A5).

- **F-106 [Moderate] U19-9** `thin_elements.jl:130` a raw
  `ElementSpec{:thin_quadrupole}(; k1l=0.1)` compiles to a `ThinMultipole` with
  `knl = ()` and tracks as the identity silently (A4: px after x = 1e-3 is 0.0,
  -1e-4 if folded): the key is declared, so the unknown-key warning does not
  fire, and only the friendly constructor folds it. A silently ignored
  non-default request (invariant 4).

### Confirmed findings, unit U11 (Contracts.jl second half, the MPI child)

- **F-107 [Moderate] U11-1** `src/contracts/Contracts.jl:3057-3070` twelve
  `DEFAULT_INACTIVE_ELEMENT_PARAMS` exemptions state structural reasons the
  contract's own probe falsifies (the `x_offset`/`y_offset` of `thin_dipole`,
  `hkicker`, `vkicker`, `kicker`, `thin_rf_cavity`; the `y_offset` of
  `lorentz_boost`, `rev_lorentz_boost`; movements 1e-8 to 2.3e-6). Auditor
  re-run of `probes/U11/probe_gh_element_exemptions.jl` section G: shipped
  `checked = 530, exemptions_declared = 38`; with the twelve removed,
  `checked = 542, exemptions_declared = 26, ignored = 0`, status passed. An
  exemption table that excuses effective parameters is a contract verifying
  less than it says.
- **F-108 [Moderate] U11-2** `Contracts.jl:3931-3940` on a process with no
  visible CUDA device `_validate_solver_options` returns `:skipped` before its
  stale-exemption tripwire (4087-4094) runs, so a stale `(solver, option)` row
  in `DEFAULT_INACTIVE_SOLVER_OPTIONS` is never reported where CI runs (read by
  the auditor; the agent measured it under `CUDA_VISIBLE_DEVICES=""`, the
  auditor's re-run `probe_ef_solver_cpu_only.jl` is recorded in §6 when it
  completes).
- **F-109 [Minor] U11-3** `Contracts.jl:3879-3883` the vacuity guard compares
  a declared alternative with the probe's value only, so an alternative equal
  to a schema default the probe does not set compares the solver against
  itself and counts as "checked" (read; agent's section F with
  `batch_mode = :wavefront`).
- **F-110 [Minor] U11-4** `Contracts.jl:3695-3705` `_solver_contract_spread`
  propagates NaN through `max`, and the device half's `spread > cuda_floor` is
  `false` for NaN, so an option that turns a coordinate into NaN passes "must
  not move" (read; latent, baselines are NaN-free).
- **F-111 [Minor] U11-5** `Contracts.jl:3347-3350, 3390-3399` the undecided
  buckets (`unperturbable`, `rejected`) are reported as counts only, so the
  pass message cannot tell a structurally unperturbable parameter from an enum
  whose alternatives were never declared (read).
- **F-112 [Minor] U11-6** `Contracts.jl:3188` with `atol = 0.0`, 22 of the 530
  "checked" parameters are credited on movements below 1e-12 (twelve below
  1e-15), roundoff of an inert conjugation (agent's `probe_a.log` section
  "moved only at roundoff"; the candidate rule at 3188 read by the auditor).
- **F-113 [Minor] U11-8** `Contracts.jl:3764-3767` the `:configuration` branch
  of `_solver_contract_receipt_carries` (reading the requested value back out
  of a dump of the solver under test) is still present: a dormant circular
  acceptance path with no tripwire (read).
- **F-114 [Minor] U11-9** `Contracts.jl:2128-2153` the PIC half of
  `HighEnergyWeakStrongLimitContract` asserts nothing about the infinite-energy
  electron (re-run of `probe_k_wsl_pic_electron.jl`: pic electron max|change|
  5.4e-20, NOT asserted; the Gaussian half asserts <= 2e-14).
- **F-115 [Minor] U11-10** `Contracts.jl:2602` `length(f) == 14 || continue`
  drops a malformed PTC row silently; the coverage check catches a case with no
  rows, not one that lost some (read).
- **F-116 [Minor] U11-7, U16-5** (cross-file seam) `GaussianStrongBeamSpec`
  accepts an ill-typed `hvoffset` at construction and fails at
  `compile_runtime` with an internal `MethodError` (agent's sweep log; U16's
  Float32 + hvoffset `convert` MethodError is the same seam, auditor re-run in
  batch 7).

### Confirmed findings, units U16 (strong_beam.jl, the weak-strong element) and U18 (aperture, misalignment, beam line, floor plan, patch)

- **F-117 [Major] U18-1** `src/elements/aperture.jl:139` `_loss_record_matches_rep`
  requires `eltype(record.slots) == eltype(rep.x)` while the allocator widens
  the slots to Float64, so a Float32 beam with a run artifact never reuses its
  loss record. Auditor re-run of `probes/U18/probe4.jl`: Float32 beam with
  artifact, after `execute!` #2: record reused = false, counts `[1]` (should be
  `[2]`), summary (dead, logged, unattributed) = (2, 1, 1) with the "no
  aperture responsible" warning; both controls (Float64 with artifact, Float32
  without) reuse the record and report (2, 2, 0). Silent loss of loss history
  for one precision.
- **F-118 [Moderate] U16-1** `src/elements/strong_beam.jl:242` `_strong_beam_round`
  declares the round cross-backend class from IP moments only; a beam round at
  the IP but elliptic at the collision point (`alpha=(0.5, 0)`, Cov(x,py) = 0.3
  at b0 = 0) measures px 261.5 and py 503.5 ulps against the declared 8 (re-run
  of `probe_A_round_class.jl`; the agent's fixture measured 504/1000).
- **F-119 [Moderate] U16-2** `strong_beam.jl:612-618` `virtual_drift=:chromatic`
  is not symplectic: the kick receives S from the IP z while the chromatic
  drift moves z. Re-run of `probe_H_chromatic.jl` (ForwardDiff Jacobians at
  EIC-like kbb = 2.63e-9): residual max|J'SJ - S| hirata 1.7e-17, exact
  2.2e-16, chromatic 1.2e-12 (thin), 1.7e-12 (ns = 5), 1.8e-12 (ns = 15),
  scaling linearly with kbb; recomputing S from z* restores the floor. The
  suite's finite-difference symplecticity test (5e-7) cannot see it.
- **F-120 [Moderate] U16-3** `strong_beam.jl:745` the forward
  `ExactHamiltonianDrift` forms `H = 1 + pz - ps` (a 4e-5 relative
  cancellation) where the reverse drift uses the small-quantity form: with
  `:exact` the declared CPU/CUDA classes are violated (re-run of
  `probe_J_drift_classes.jl`: elliptic thin, exact, pz 1024 ulps at 1 turn and
  3072 at 3 turns against the 2048 bound, violations = 1; hirata and chromatic
  0 violations).
- **F-121 [Moderate, regression of the 2026-10-18 batch] U16-6** `strong_beam.jl:1391`
  `gaussian_strong_beam_covariance` refuses ForwardDiff duals through its
  dispersions since the canonical-dispersion builder (unit L of the 2026-10-18
  beam-beam batch) converts `zeta`, `eta` to `Vector{Float64}` in
  `_dispersion_graph`: `MethodError: no method matching Float64(::Dual)`
  (re-run of `probe_C_options.jl` C4; BigFloat fails further down in
  `eigvals!`). The auditor of this pass wrote that builder; the regression is
  recorded here as such.
- **F-122 [Minor] U16-4** `strong_beam.jl:514-527` an `hvoffset` Dict with a
  misspelled or missing key (`coef` without `frequency`, `:freq`) is silently
  defaulted: `hoffset = voffset = 0`, identical to no hvoffset (C1).
- **F-123 [Minor] U16-5, U11-7 (F-116)** `strong_beam.jl:517-519` a Float32
  Gaussian strong beam with `hvoffset` dies with a `convert` MethodError at
  compile (C3).
- **F-124 [Minor] U16-7** `strong_beam.jl:1767-1768` `angle[3]` (pzo),
  `curvature[3]` (ppzo) and `mean[6]` are accepted, stored and inert:
  coordinates and luminosity bitwise identical with and without them (C2); not
  documented as inert.
- **F-125 [Minor] U16-8** `strong_beam.jl:613` an explicit all-zero covariance
  compiles silently to the identity with zero luminosity
  (`probe_G_views_coverage.jl`, final block).
- **F-126 [Moderate] U18-2** `src/elements/misalignment.jl:378` a Dual
  alignment parameter on a BEAM LINE throws `MethodError: Float64(::Dual)` in
  `_misalignment_wrap` because `_wrap_numeric_type` takes the members' Float64
  over the line's promoted type; single elements differentiate (AD = FD = 0.68
  for `x_offset`, the pitch, tilt and ref_tilt derivatives all agree; re-run
  of `probe2.jl`).
- **F-127 [Moderate] U18-3** `src/elements/floor_plan.jl:117` `survey(line)`
  drops the line's own `ref_tilt`: exit position (-0.7399, 0.0, 2.8957) against
  `survey((line,))` and tracking (-0.6815, -0.2881, 2.8957) for a 0.4 rad roll
  (auditor one-liner).
- **F-128 [Moderate] U18-4** `floor_plan.jl:137,171` the survey walkers read a
  kept-whole sub-line's `ref_tilt` from the spec, ignoring the placement
  override tracking honours: `probe1b.jl` P8, max |difference| = 0.288 m at the
  exit (the compiled placement is a `RefTilted`).
- **F-129 [Moderate] U18-5** `floor_plan.jl:62` `_floor_step` ignores a patch's
  `ref_tilt` that `_ref_tilt_wrap` applies in tracking: a patch `angle_y=0.1,
  ref_tilt=pi/2` surveys as (-0.0998, 0, 0.995), the unrolled plane, where the
  vertical patch tracking makes it equivalent to surveys as (0, -0.0998, 0.995)
  (`probe5.jl`).
- **F-130 [Minor] U18-6** `beam_line.jl:897` `knob_report` says "No knob-driven
  parameters" for a girder whose own `x_offset` is a knob expression or whose
  placement carries a knob override, while `_has_knob_parameters` is true for
  both (`probe1.jl` P3).
- **F-131 [Minor] U18-7** `beam_line.jl:81` an `L` override on a line
  placement is accepted at assignment (stored 5.0) and refused only by the next
  arc-length walk, against the docstring's "the placement refuses it too" (P4).
- **F-132 [Minor] U18-8** `beam_line.jl:372` `BeamLine(; entries=arc[1:2])`
  aliases the given `LineEntry` objects: writing `h[1].x_offset` writes
  `arc[1].x_offset` (same object, auditor one-liner).
- **F-133 [Minor] U18-9** `floor_plan.jl:69` vs `patch.jl:263` a String
  `convention` is accepted and normalised differently: `_floor_step` tests
  `=== :madx` (a String reads as `:bmad`), `Patch` applies `Symbol(...)` (read
  by the auditor), so the tracked patch composes in `:madx` order and the
  survey in `:bmad` order.
- **F-134 [Minor] U18-10** `floor_plan.jl:87` `_floor_arc_step` forms the
  sagitta as `rho * (cos(alpha) - 1)`, the cancellation-prone form
  `_survey_frame` avoids with `_curv_vers` (fix K of 2026-10-17 closed this class
  in the tracking kernels, not here).
- **F-135 [Minor] U18-11** `patch.jl:234` "composing a patch with its exact
  inverse is the identity" holds for the transverse coordinates only; `z`
  shifts by the constant R1 + R2 of the two reference particles (measured and
  predicted -1.033905e-3, `probe1b.jl` P11).
- **F-136 [Minor] U18-12, U18-13, U18-14, U18-17** documentation drift: the
  `:line` `x_offset` metadata still says the assembly survey is STRAIGHT
  (`beam_line.jl:785`); `floor_plan.jl` opens with a "Draft ... installed only
  after the audit commit lands" header; the `survey` docstring's "opposite
  choice from the arc walker" predates the 2026-10-18 descent of kept-whole
  sub-lines by the task's arc walker; the aperture theory note §6 (line 403)
  still claims byte-identical CPU/CUDA logs the `LossRecord` docstring
  retracted.
- **F-137 [Minor] U18-15, U18-16** `patch.jl:190` `_patch_reference_length`
  (live-sounding docstring) and `floor_plan.jl:94` `_floor_children` have no
  callers (grep).
- **F-138 [Minor] U18-18** `beam_line.jl:77` `setproperty!` on a line
  placement accepts an `entries` override; the compiled placement tracks the
  override (a 7 m drift: x = 0.002396) while `total_length`, `s_positions` and
  `survey` read the spec (0.4 m quad: 1.4, [0.0, 0.4]) (`probe6.jl`, `probe5.jl` E1).

### Confirmed findings, units U24 (the Twiss contracts), U28, U29, U30 (test regions 1-9635)

Test-region leads are test-quality items: no silenced check inside the suite
was found by any of the three units (each read its region in full and traced
every bitwise pin to a structural source). Verification here is the auditor's
reading of the cited lines (`sed -n` on 24e8683) plus the probe named.

- **F-139 [Moderate] U24-1** `src/contracts/twiss_dispersion_identity.jl:1247`
  an F6a dense map whose certification or frame fails is skipped silently at
  the contract level: with all twenty diverted to an unresolved result,
  `validate` still answers `:passed` ("certified ... 100 fixture runs",
  `dense6_unresolved = 20`); only the suite's pin sees the count (agent's
  `probe_second.jl` part b; auditor re-run in batch 8, §6). A check only
  counts while it executes.
- **F-140 [Moderate] U24-2** `src/contracts/analysis_effectiveness.jl:54` the
  `longitudinal_mode` effectiveness alternative (2) equals the heuristic's own
  choice on the fixture, so "index ignored" and "index honoured" produce the
  same optics and the probe can only read the consumer's self-reported flag;
  modes 1 and 3 demonstrably move the selection (agent's one-liner). Same
  class as F-10.
- **F-141 [Minor] U24-3** `twiss_dispersion_identity.jl:667`
  `_identity_contract_record!` has no finite-kappa guard: `kappa = Inf` passes
  with ratio 0, `NaN` passes recording no maximum (agent's one-liner; latent).
- **F-142 [Minor] U24-4, U24-5** `twiss_dispersion_identity.jl:976, 766` two
  Layer 3 rows are circular (`c_normal_mode_tunes` compares an array with
  itself, `c_matched_covariance_accessor` the same path, both exactly 0) and
  the V1 verdict re-derivation has never executed its non-empty branch (54
  empty-vs-empty verdicts, no doctored-verdict negative).
- **F-143 [Minor] U24-6** `twiss_external_reference.jl:411` the MAD-X TOL-B
  rows compare canonical `eta` with MAD-X's slope `beta0 DX` without the (D8)
  factor h, valid only because all five A1 fixtures are coasting with h = 1.0
  exactly (`probe_second.jl` part a: `coasting.holds = true, h = 1.0` for U1,
  U2, K1, K2, Rd), a precondition no row asserts (the xtrack side does).
  Convention seam S6 of §3.
- **F-144 [Minor] U24-7, U24-8** `twiss_external_reference.jl:732, 195` the
  fixture lists are hand copies of the validation scripts' constants with no
  tripwire and the xtrack C1 layer has no table-coverage row; the versions the
  contract claims (MAD-X 5.03.06, xtrack 0.112.0) are never read from the table
  headers (`header` stored, not read).
- **F-145 [Minor] U24-9** `analysis_effectiveness.jl:468` the `emittances`
  observable is presence-only; an exact doubling of the values would pass.
- **F-146 [Minor] U28-1** `test/runtests.jl:152` the no-GPU banner's hand list
  "Twelve source files carry CUDABackend code" has drifted: 13 do, `Tasks.jl`
  missing (auditor grep: 13, 1).
- **F-147 [Minor] U28-2** `runtests.jl:1316-1334` the n3/n3b registry restores
  hand-list three of the four containers `register_element_meta!` writes; the
  leaked fourth entry is invisible to `validate_element_metadata` and the
  identity contract (agent's `probe1.jl` P6: all four containers written,
  both validators pass after the leak).
- **F-148 [Minor] U28-3, U30-10** `runtests.jl:1097, 1125, 7432` the on-disk
  snapshot comparisons sit behind `if isfile(ondisk)` with no `else
  @test_skip`; the path is derived by three `dirname` calls from a method's
  file and the same recipe on `Knowledge.jl` resolves to a non-existent path
  (agent's `probe1.jl`): a relocation would silence the check.
- **F-149 [Minor] U28-4** `runtests.jl:228` the docs-index tripwire's name
  clause is a basename substring test (`occursin(f, index)`): 21 duplicated
  basenames under `docs/`, three files pass through another file's link.
- **F-150 [Minor] U28-5** `runtests.jl:86` the hoisted TSC-weights CUDA testset
  is gated by `if Octopus._HAS_CUDA` with no `else @test_skip` (0
  `test_skip` in 86-130), the shape the header's own rule forbids.
- **F-151 [Minor] U28-6, U28-7** `runtests.jl:1198, 2430` the 0.25 re-open rule
  for the stage 6 identity pins has no instrument (worst ratio today 0.1317,
  two rows above 0.1); the det R = 0 branch is selected by `d == 0` on a
  computed determinant, exact today by literal rounding.
- **F-152 [Minor] U29-1, U29-2, U29-3** `runtests.jl:5130, 3460, 3462` `abs(tr
  M_ll) < 2.3` bounds a non-witness widened to the data (2.02, 2.20 measured);
  `1 <= length(rq.clusters) <= 2` hedges a count the same line's comment
  asserts; a 1e-8 tolerance passing with a 1e-12 margin.
- **F-153 [Minor] U29-4, U29-5, U29-6** `runtests.jl:3611, 3756, 4453` a
  crab-ladder receipt check implied by the solver's own merge rule; `norm(cf.G
  - determined_value(cf.cluster.covariance)) == 0` where `_st3_cluster` (3006)
  defines `G` as that value (tautology, read); the per-route (I1)-floor
  assertions re-evaluate the kernel's own acceptance inequality.
- **F-154 [Minor] U29-7** `runtests.jl:6212` "every export is documented"
  iterates a hand-typed list of nine names equal to the file's `export` line
  (read): a tenth export is not covered.
- **F-155 [Minor] U29-8** `runtests.jl:6302` the dry-run testset defines
  `const IDENT_DRY_RUN = true` in `Main` for the rest of the process, after
  which a later `include` of the identities script is a silent no-op
  (cross-file seam with `validation/`).
- **F-156 [Moderate] U30-1** `runtests.jl:7143-7149` the explicit-partition
  frame-blocking check selects its branch from the artifact
  (`_frame_availability(ru4.clusters)`), and on its fixture the blocking `else`
  arm is dead (agent's `probe_branches.jl`: branch taken = IF), leaving
  `src/analysis/twiss_dispersion_analysis.jl:984` untested by the whole suite.
- **F-157 [Minor] U30-2, U30-5** `runtests.jl:7132, 6763` the union-of-pairs
  degradation assertion sits behind a data condition false on its fixture
  (block entered = false); the "another branch" loop iterates an empty set.
- **F-158 [Minor] U30-3, U30-4, U30-9** `runtests.jl:6643, 7209, 6838` a
  tautology (`multiplier * eps() * 1.0 > 0`, the constant's only use in the
  suite) standing in for the closed-orbit tolerance rule; a guard loop the
  test writes itself; a "docstrings claim" title over a hand-written literal.
- **F-159 [Minor] U30-6, U30-7, U30-8** `runtests.jl:6716, 8468, 8398` a
  2.2x-margin pin inside the window the neighbouring Scaling testset's
  one-tenth rule forbids; five virtual-drift selectors pinned by `==` against
  17-digit literals; the CUDA LumpedRad parity asserts x, px only (never y,
  py, z, each with its own counter stream).

### Confirmed findings, units U17 (lattice magnets, solenoid, linear6d) and U25 (Knowledge.jl, Policies.jl)

- **F-160 [Moderate] U17-1** `src/elements/lattice_magnets.jl:1073` `bend_fringe`
  defaults to `true` for every lattice-magnet kind, so a straight magnet
  carrying a dipole component with `fringe=:multipole` departs from PTC by the
  whole fringe effect. Auditor re-run of `probes/U17/probeE2_ptc_compare.jl`
  against the agent's MAD-X 5.03.06 PTC runs (`probes/U17/madx/`): four
  particles, default max|PTC - Octopus| over (x, px, y, py) 4.0e-6 to 1.1e-5;
  `bend_fringe=false` 1.3e-12 to 4.0e-12; `fringe=:none` 4.4e-6 to 9.8e-6.
  A PTC-fidelity default right for bends and wrong for the straight kinds.
- **F-161 [Minor] U17-2** `lattice_magnets.jl:350` the bend's path-length
  excess has a second exact cancellation at `b0 = 2h` that fix K's regime test
  `abs(b0) > abs(h)/2` does not guard: `_lattice_bend(0.3, 0.6, 2.0, ...)` on a
  z = 2e-3 particle returns z = 2.0000000000000577e-3 (auditor one-liner; the
  agent measured up to 2136 ulps of z across the regime).
- **F-162 [Minor] U17-3, U17-4** `lattice_magnets.jl:974, 966` two declared
  cross-backend classes quoted outside the regime they were measured in: a bend
  turning more than a quarter turn in one step measures x at 294 ulps against
  the declared 64 (re-run of `probeC2_cuda_scale.jl`); a straight quadrupole
  with a pole-face angle and no dipole measures x 103 / px 121 ulps against the
  declared 32 (`probeC3_straight_k0_edge.jl`; with a dipole component 7/4).
  Siblings of F-100.
- **F-163 [Minor] U17-5** `lattice_magnets.jl:232` the curved drift has no guard
  for a frame rotation past a quarter turn per step: `DriftSpec(L=1, h=1.6)`
  returns exit x = -22.03 m silently (one-liner), where the bend path handles
  the regime.
- **F-164 [Minor] U17-6** `docs/theory/lattice_hamiltonian_and_conventions.md:881`
  the SAD cubic fringe term in the note omits the `1/(1+delta)` the code and
  PTC carry (agent's PTC comparison at delta = 0.09, `probeE2` first block);
  the committed pin barely resolves it. Theory-note drift.
- **F-165 [Minor] U17-7** `src/elements/linear6d.jl:52` `Linear6DSpec(matrix=...,
  beta1=...)` stores the matrix and silently discards the optics keywords
  (one-liner: params keys `[:matrix, :tracking_method]`).
- **F-166 [Minor] U17-8** `src/elements/solenoid.jl:117` `_sol_g` uses the
  u^7-truncated series of `ln(1+hx)/h` while `_sol_gp` is the exact derivative
  of the untruncated form, so the curved solenoid's vector field is not exactly
  Hamiltonian: exact-arithmetic symplecticity floor 1e-17 (code) vs 1e-61
  (consistent log form), invisible at double precision (re-run of
  `probeI_solenoid_nst.jl`).
- **F-167 [Minor] U17-9** `lattice_magnets.jl:227` one unphysical particle
  aborts the whole run with a nameless `DomainError` from `sqrt` (CPU) or a
  `KernelException` (CUDA) (agent's `probeD.log`; no twin divergence).
- **F-168 [Moderate] U25-1** `src/knowledge/Knowledge.jl:1169`
  `_check_declared_defaults!` skips every declared default the kind's example
  does not set (`haskey(base, key) || continue`), so `validate_element_metadata`
  verifies 77 of the 608 non-required defaults. Re-run of `probes/U25/p1_knowledge.jl`
  I1: `drift.h` default changed 0 to 6 in the live registry, `passed = true`,
  0 mentions (MISSED). The validator's own docstring example is among the
  skipped.
- **F-169 [Moderate] U25-2, U6-9 (same defect)** `src/policies/Policies.jl:1419`,
  `interface.jl:1914-1933` `validate_configuration_metadata` compares the CPU
  policy's `threads` default and the legacy GPU policy's `threads`/`blocks`
  defaults to literals (`:auto`, 256), not to constructed objects, while the
  `policy_option_schema` docstring says it "pins these against the
  constructors" (grep of the literals; agent's `p2_policies.jl`).
- **F-170 [Moderate] U25-3** `Policies.jl:757-772` `_mp_resolve_shard` takes
  the "this rank holds the wrong count" verdict on one rank's own count after
  an all-sum that already gives every rank every count, so the verdict is
  asymmetric across ranks: re-run of `p2_policies.jl`, expected [256, 256, 256,
  256], rank 2 holding 255 and rank 3 holding 257 THROW while ranks 0 and 1
  PROCEED to the next collective (a deadlock shape, the class the luminosity
  schedule memo exists to avoid).
- **F-171 [Minor] U25-4** `Knowledge.jl:238-285` 13 of 31 kinds carry their own
  copies of the placement-parameter entries drifted from `_PLACEMENT_PARAMS`
  (79 entries): `misalign_convention` with `alternatives=()` against `(:bmad,
  :madx)` on `thin_dipole`, `thin_multipole`, `thin_quadrupole`,
  `thin_sextupole`, `vkicker` and two more (re-run of `p4_placement_drift.jl`),
  leaving those kinds' convention unperturbable in the effectiveness sweep.
- **F-172 [Minor] U25-5, U25-8, U25-9** `Knowledge.jl:1288, 1225, 1212`
  `validate_element_metadata` does not check runtime-type entries against the
  declared methods (I3: `drift` runtime_types += `Damping6DMap` passes), nor a
  Symbol default against its `alternatives` (I2: `misalign_convention` default
  `:elegant` passes), nor emptiness of `description`/`meaning` (I4: empty
  strings pass) (re-run of `p1_knowledge.jl`, all three MISSED).
- **F-173 [Minor] U25-6** `Policies.jl:490-491` `_launcher_rank_count` consults
  the per-node `MPI_LOCALNRANKS` before the global `PMIX_SIZE`,
  `MV2_COMM_WORLD_SIZE`, `SLURM_NTASKS` (read; a launcher exporting only those
  reads the node's count).
- **F-174 [Minor] U25-7** `Knowledge.jl:1434-1436` `tracking_method(spec)`
  answers `Symplectic6DMap()` for a `:line` spec whose
  `supported_tracking_methods` is `[]` and whose `compile_runtime(spec,
  Symplectic6DMap())` is refused by name (re-run of `p3_followup.jl`).
- **F-175 [Minor] U25-10** `Policies.jl:989-1000` the `_mp_chunk_fold`
  docstring declares a three-argument signature; the one method takes two
  (grep).

### Confirmed findings, units U22 (analysis kernels), U26 (knobs, extensions), U27 (beam, constants, registry, examples)

- **F-176 [Moderate] U22-1** `src/analysis/dispersion_routes.jl:1389` the
  projector route's three-trace list treats every multi-member cluster as
  unresolved, so a RESOLVED definite m = 2 cluster (reachable through
  `TwissDispersionAnalysis(clusters=partition)`) gets both betatron traces
  replaced by their average and the projector route reports a garbage graph as
  `:not_invariant` while the other routes stay `:none` and `degradations` is
  silent. Auditor re-run of `probes/U22/probe2_partition.jl`: projector gaps
  used `Float64[]` against the true gaps [0.474, 1.405]; the newton and
  fixed-point routes report the cluster indefinite.
- **F-177 [Minor] U22-2** `src/analysis/twiss_dispersion_analysis.jl:1157`
  (seam) the heuristic-selection text quotes the z-area of the wrong mode when
  a resolved cluster has more than one member (indexes the resolved-mode-ordered
  weights by cluster position): quoted -0.005582 where the selected mode's
  z-area is 1.019081 (probe 2, Q2).
- **F-178 [Minor] U22-3** `dispersion_routes.jl:1346` on a coasting map any
  `longitudinal` value is accepted silently against the docstring's promised
  `ArgumentError` (`longitudinal_mode = 3` accepted, probe 2).
- **F-179 [Minor] U22-4** `src/analysis/canonical_separation.jl:303`
  `_dispersion_graph` refuses only an exactly zero h: h = 2.2e-16 returns a
  slope of 4.5e15 silently, h = 1e-12 returns 1e12 (probe 1). The 2026-10-18
  builder (unit L) owns this boundary; sibling of F-121.
- **F-180 [Minor] U22-5, U22-6, U22-7, U22-8** docstring and derivation drift in
  the analysis kernels: the `_GRAPH_SINGULARITY_MULTIPLIER` "twelve decades
  either way" is 2.4 decades on the rejected side; the `_CLUSTER_FRAME_N4_MULTIPLIER`
  window edge omits its own factor ten; the branch-check floor carries an
  underived `max(1, ||M||_F)`; `tau_s` is documented as `2 cos mu_s` but is
  `Re(rho + 1/rho)` for a blocked cluster (agent's arithmetic one-liners,
  read).
- **F-181 [Moderate] U26-1** `src/knobs/symbolic.jl:168` `knob_derivative(expr,
  path)` never consults the registry for `path`, so a mistyped, undeclared or
  forgotten knob path yields a constant (0.0, or a tree naming a forgotten
  knob) where every other knob API refuses by name (re-run of
  `probes/U26/derivative_path_probe.jl`: `knob_dependents`, `set_knob!`,
  `@knob_expr`, `knob_value` all refuse `m.curent`; the derivative does not
  complain).
- **F-182 [Minor] U26-2, U26-3, U26-6, U26-7, U26-9** `src/knobs/Knobs.jl:946,
  748, 477, 813, 646` a negative-zero base of `^` breaks the documented
  `knob_expression(string(e)) == e` round trip and flips the sign; `propertynames`
  slices a byte index by a character count (non-ASCII roots); a constant-only
  right-hand side installs an input-less dependent knob; `list_knobs(prefix)`
  filters by string prefix, not namespace; `knob_value(::Real)` casts to
  Float64 (agent's `knob_semantics_probe.log`, re-run exit 0).
- **F-183 [Minor] U26-4** `ext/OctopusMPIExt.jl:227-265` `_mp_bcast_impl!`,
  `_mp_bcast_scalar_impl`, `_mp_barrier_impl`, `_mp_gather_rows_impl` call MPI
  without `_mp_timed`, so `_mp_collective_times` omits them (agent's two-rank
  `mpi_ext_probe.sh`: timed kinds allmax/allmin/allminmax/allsum/exchange_columns;
  NOT timed although called: bcast, bcast_scalar, barrier, gather_rows).
- **F-184 [Minor] U26-5, U26-8, U26-10, U26-11** the `knob_derivative`
  docstring example `:m.k1` cannot run (parses as `getproperty(:m, :k1)`); the
  documented declare-then-use inside one function hits Julia 1.12's world-age
  deprecation; the script-mode Symbolics gate swallows every error; `resolve_knobs`
  reads the epoch after the values (read).
- **F-185 [Moderate] U27-1** `src/beam/Beam.jl:642-648` `Beam(...)` silently
  lets `emit` override a non-default `sigma` (requested sigma 1e-3 with emit
  1e-8 at beta 1: measured rms x = 1.0e-4, no warning; auditor one-liner) and
  `C` override `R`/`coupling`. A silently ignored non-default request.
- **F-186 [Moderate] U27-2** `Beam.jl:753-791` the lost-particle statistics pin
  (`runtests.jl:25833-25836`, `atol = 1e-18/1e-24/1e-30`, so rtol 0) rests on
  rounding: the masked reductions are sequential while the plain `_mean`,
  `_fourth_central` are Base's pairwise sums. Auditor re-run of
  `probe2_beam_statistics.jl`: random values at n = 200000, mean pin true,
  covariance pin FALSE (1.1e-23), fourth-moment pin FALSE (4.5e-22); the
  suite's fixture keeps it green.
- **F-187 [Minor] U27-3** `Beam.jl:636-656` a `Beam` refused for a malformed
  `beta` has already drawn its normals and consumed a stream id (counter 1 to
  2 across the refusal; one-liner).
- **F-188 [Minor] U27-4** `Beam.jl:891-892` `write_beam_coordinates(io, rep;
  npart=5)` on two particles writes 0 lines and no error (clamps) where its
  observer twin refuses (one-liner).
- **F-189 [Minor] U27-5** `Beam.jl:139-146` CPU and CUDA beams from one seed and
  `rng_id` are not bitwise equal (x 1.6e-15 of rms, px 4.4e-18, z bitwise):
  `_standardize!` runs on the device after a host-identical draw.
- **F-190 [Minor] U27-6, U27-7, U27-8** the `Beam` docstring signature omits six
  accepted keywords; the catalogue claims `KnobRef` for `examples/knob_control.jl`
  which names it 0 times (one-liner); three refusals are undirected
  (`seed=-1` InexactError, a record past EOF EOFError, mixed eltype
  MethodError; re-run section 8).
- **F-191 [Minor] U27-9, U27-10** `src/Octopus.jl:33` the source-map tripwire
  checks the top level of `src/` only (AGENTS.md states the rule for every
  directory; `src/tasks/strongstrong/` is nested); `summarize_registry()` lists
  abstract taxonomy nodes among "concrete members" (one of six policies, three
  of nineteen contracts; agent's `probe1_registry_constants.jl`, re-run exit 0:
  constants equal CODATA 2022, snapshot complete).

### Confirmed findings, units U21 (the analysis driver) and U23 (mode clusters, coupled parameterizations)

- **F-192 [Major] U23-1** `src/analysis/mode_clusters.jl:775` `_recover_modes`
  tags the j-th recovered mode of a resolved multi-member cluster with `index =
  half[j]`, a canonical eigenvalue index taken by POSITION, while the j-th
  eigenvector of `eigen(T_c)` is the other member in every resolved m = 2
  cluster the agent measured (26/26 under `resolution_chord = Inf`, 16/16 under
  an explicit partition). Through the consumer seam `dispersion_routes.jl:1253`
  the public `analyze(clusters=..., longitudinal_mode=<canonical index>)`
  computes the betatron mode's "dispersion" (`tau_s = 1.4903` where the
  requested mode has 1.9975, wrong `eta`) while the receipt says "certified
  selection of canonical eigenvalue 1" (agent's `probe3_analyze_index.jl`:
  modes 1 and 2 report `|eigenvalue - ev[index]| = 0.667`). Auditor re-run of
  the same probe: requesting canonical index 1 yields `tau_s = 1.490349`
  (expected 1.997501 for the requested mode), requesting index 2 yields
  1.997501 (expected 1.490349): the two members are swapped, and the
  mis-selected run reports `status = failed` with a "converged to another
  invariant plane" degradation rather than naming the swap. The default-chord
  path is unaffected and the suite pins the index only for m = 1. Sibling of
  F-176 (the same resolved-cluster seam).
- **F-193 [Minor] U23-2, U23-3** `mode_clusters.jl:121`,
  `coupled_parameterizations.jl:328` `_REAL_CLASS_MULTIPLIER = 1` lies outside
  its own documented window (empty on the accepted side; margin 0.46 of the
  floor on 384 rotated Jordan pairs, no misclassification) and its
  re-measurement driver is not in the tree; the theory-6.2 phase convention is
  implemented with two floors (`sqrt(eps)` vs `64 eps`), inert today.
- **F-194 [Moderate] U21-1** `src/analysis/twiss_dispersion_analysis.jl:1563`
  `map_uncertainty` and the FD provenance uncertainty are declared in caller
  coordinates but folded into the SCALED matrix's `rho_M0` unchanged: auditor
  re-run of `probes/U21/probe_d_uncertainty_scaling.jl`, per-entry gain
  `C_ii/C_jj` in [1.6e-2, 63] on the DBA ring and [6.9e-4, 1.46e3] at beta =
  1000 m while `rho_M0 = 1e-9` under both scalings.
- **F-195 [Moderate] U21-2** `twiss_dispersion_analysis.jl:1567` (seam into
  `mode_clusters.jl`) on `diag(R(0.7), R(0.7), R(0.05))` (equal betatron tunes,
  isolated synchrotron pair) the agglomeration's infinite kappa for an exactly
  repeated pair caps every chord at 2.0 and the tie order absorbs the
  longitudinal pair into one six-member cluster, so eta is an ambiguity set of
  multiplicity 3; any detuning >= 1e-9 restores a unique eta; the contract's
  `repeated` fixture merges in the other order and passes (agent's
  `probe_f_clusters.jl`; the auditor's re-run reproduces the fixture's
  [1,2,5,6] + [3,4] merge with unique eta).
- **F-196 [Minor] U21-3, U21-4, U21-5** `twiss_dispersion_analysis.jl:1442,
  1426, 1424` on a coasting map `diagnostics.projection.canonical_area` omits
  the kernel's `1 +` (0.0 against the kernel convention's 1.0); route rows that
  never ran carry 0.0 residuals and `converged = true`; the receipt says
  `executed = ()` while diagnostics lists five "executed" rows (re-run of
  `probe_e_followup.jl`).
- **F-197 [Minor] U21-6** `twiss_dispersion_analysis.jl:326` the
  `longitudinal_mode` tune domain (0, pi) rejects the result's own reported
  synchrotron tune 6.009 (tunes are reported mod 2pi) while `2pi - t`
  certifies (re-run: `ArgumentError` then `certified = true, selected = 1`).
- **F-198 [Minor] U21-7, U21-8** `twiss_dispersion_analysis.jl:923, 1171` the
  effective default closed-orbit tolerance is recorded nowhere (receipt echoes
  `closed_orbit_atol = nothing` beside a residual judged against 1.42e-14;
  re-run of `probe_a_linearization.jl`); `newton_max_iterations` is reported
  `:resolved` with `used = 0` when Newton never iterated.
- **F-199 [Minor] U21-9, U21-10** `twiss_dispersion_analysis.jl:1652, 288`
  `analyze(::LinearizedMap)` hardcodes dimension 6 (a 4x4 `LinearizedMap` dies
  with `DimensionMismatch`); four docstring statements the code does not have
  (an ArgumentError-only claim beside a `TypeError`, a Bool accepted as an
  emittance, "could not be cross-checked", the FD "2.1e3 times" number with no
  harness, 2.1x measured).

### Confirmed findings, wave 4: test regions U31-U37 (`runtests.jl` 9636-32036), harnesses and examples (U38), profiling drivers (U39), validation scripts (U40)

Verification: the auditor's `sed -n`/`grep` on 24e8683 for every static claim,
the agent's probe re-run by the auditor (`probes/auditor/`) where named, and the
agent's own log where the probe is a long harness run (so marked).

- **F-200 [Major] U39-1, U39-2** `profiling/benchmark_strong_strong_pic.jl:174, 120-133`
  the driver is dead on arrival: its task construction passes the luminosity
  path keywords retired on 2026-08-17 and dies with `ArgumentError: the
  standalone luminosity outputs were retired` (agent's `p2_pic_configs_identical.log`,
  same class as A-4); and its eleven CUDA "configurations" set environment
  switches no runtime code reads, so only four are distinct. A profiling
  driver the development guide names as the fixed point for PIC benchmarks
  cannot run on this tree.
- **F-201 [Moderate] U39-3, U39-5, U39-6** `profiling/cuda_device_profile.jl`
  is a 533-of-629-line drifted fork of the strong-strong harness that runs only
  with both outputs disabled; `profiling/crab_cavity_noise_backends.jl` exits 0
  when every arm fails (agent's `p6_crab_driver_exit_code.log`: "ARMS WITHOUT A
  ROW: threads:1", exit 0, the F8 class of the crab-noise audit);
  `profiling/benchmark_collide_cpu.jl` records `grid = 128` for the spectral
  (hard-coded (127, 383)) and Gaussian (no grid) rows of the committed history.
- **F-202 [Minor] U39-4, U39-7..U39-13** profiling drivers: a deprecated
  two-component `alpha` in the PIC driver (depwarn), a `-mmin +1440` lock test
  off by one minute, hand-copied `OCTOPUS_BENCH_*` lists (five names missing
  from the header), nightly exit-code and negative-control details, and the
  development guide the routing table names for benchmarks carrying one
  benchmark-related line (AGENTS.md seam).
- **F-203 [Moderate] U38-1** `test/examples/strong_strong_tracking.jl:679-694`
  with `OCTOPUS_SOLVER=gaussian_pic` the harness parses and PRINTS
  `OCTOPUS_PIC_SLICE_PAIR_GREEN_MIN_RATIO`, `..._GROWTH`, `OCTOPUS_PIC_LUMINOSITY_GRID`
  and `OCTOPUS_PIC_LUMINOSITY_DEPOSIT_METHOD` and never passes them to the
  solver (solver fields stay 0.5 / 0.25 / nothing / nothing; agent's `p1.log`,
  auditor's env re-run `U38_1_harness.log` recorded in §6). Invariant 4: a
  configuration you set is not a configuration the code read.
- **F-204 [Moderate] U38-2** `examples/weak_strong_tracking.jl:166-199` (and
  the strong-strong example) a `config.execution` outside the four documented
  symbols falls back to CPU threads silently (`execution = :gpu` prints
  `execution policy = CPUThreadsExecutionPolicy`, exit 0; auditor re-run of
  `p4_weak_strong_execution_typo.jl`), and `ranks`/`gpu_device`/`threads` are
  never read outside their mode; only `crab_cavity_noise.jl` refuses by name.
- **F-205 [Moderate] U38-3** `test/examples/strong_strong_tracking.jl:420-450`
  six `OCTOPUS_*` variables (`OCTOPUS_CUDA_DEVICE`, `_CUDA_THREADS`,
  `_CUDA_BLOCKS`, `_RANKS`, `_TURN_TIMING_PATH`, `_CUDA_PIC_DEPOSITION_THREADS`)
  are read only inside a branch whose switch is off by default, so a set value,
  even `OCTOPUS_CUDA_BLOCKS=banana`, is silently ignored (agent's `p5.log`:
  exit 0 on CPU threads, no timing file; auditor's env re-run
  `U38_3_harness.log`, §6); the crab harness refuses each by name.
- **F-206 [Minor] U38-4..U38-11** harness and example details: three
  resolution rules and TSV layouts for `OCTOPUS_TURN_TIMING_PATH`; a dead
  finiteness clause in `_energy_env` (`||` for `&&`); a negative
  `OCTOPUS_MOMENT_CAPACITY` silently replaced by 1024; the weak-strong header
  omits three switches it reads; `INDEXED_WAVEFRONT=1` documented as an A/B
  though it is the default; hand-copied crab strengths and `beta_z` in the
  strong-strong example; the harness/example physics identity resting on five
  hand copies with no tripwire (zero differences today); the crab example's four
  non-default rule paths executed by nothing committed (all four ran clean in
  the agent's `p7_*.log`).
- **F-207 [Moderate] U40-1, U40-2, U40-3** `validation/crab_cavity_noise_response.jl:2247, 450`,
  `validation/strong_strong_diagnostics_benchmark.jl:147` part `control`
  has no `mkpath` and crashes after the centroid verdict when `out=` names a
  new directory; every part accepts an unknown `key=value` override silently
  (`tol_ration=0.01` gives 60/60 PASS where `tol_ratio=0.01` FAILS); the
  documented `OCTOPUS_SOLVER=gaussian` benchmark mode must error at the
  launch-family loop after the full run (the Gaussian solver's
  `configuration_report` has 0 of 7 `cuda_pic_*` entries) (agent's logs, all
  four scripts otherwise reproducing their recorded verdicts: noise 273/273,
  report 60/60, control 3/3, spectra PASS, RNG PASS).
- **F-208 [Moderate] U40-4, U40-11** `validation/README.md:558`,
  `docs/theory/crab_cavity_noise_response.md:667` the README describes report
  verdicts and defaults the script no longer has (A1 y, 9.5e-7, 0.17 y, A4 as
  verdicts; `ref_amp_white_y` now refused); the theory note's acceptance list
  and sweep table drifted from what the script enforces.
- **F-209 [Minor] U40-5..U40-10, U40-12..U40-15** validation-script details:
  `turns` provenance under a pre-set `OCTOPUS_TURNS`; the counter-RNG uniform
  variance tolerance 1.58x too loose (a 9.5-sigma gate called 6); tail
  fractions print-only; the spectra header's "13.8 % at 16384" matching
  neither its formula (15.3 %) nor the Monte Carlo (13.4 %); a "same
  tolerances" contradiction; "committed with the record" pointing into the
  git-ignored `result/`; a default `cases=` that cannot deliver acceptance item
  2; hard-coded turn counts in report labels; `noise_pink_bands.tsv` top band
  `trusted = true` with `z = NaN`; `git_commit` read from the caller's cwd.
- **F-210 [Moderate] U31-3** `test/runtests.jl:11585` the flat-table negative
  control `@test abs(slope_flat) > 0.02 * 50` passes only because rounding put
  `slope_flat` 30 ulp above the exact 1.0 (agent's `probe3_flat_slope.jl`); a
  sign flip would false-red and abort the suite.
- **F-211 [Minor] U31-1, U31-2, U31-4, U31-5, U31-6** `runtests.jl:10032,
  11307, 10751, 11287, 9711` the `_atan_over` seam check straddles a hand-copied
  `1e-4` (two bare literals in the source); the text pin
  `occursin("derived = _forwarding_track_ops(octopus_track_ops)", suite)`
  matches its own literal (2 hits, cannot fail); `wrapper_walks` omits
  `_track_cuda_elementwise!` (= F-69); the harness-seed loop has no
  visited-count tripwire; an invalid `misalign_convention` (`:middle`, the
  string `"madx"`) is accepted silently whenever no offset is set, through
  spec, compile and task (seam with F-133).
- **F-212 [Moderate] U32-1, U32-2, U32-3** `runtests.jl:13765, 15806, 13688`
  the cross-backend checker `_cross_backend_violations` behind three
  measurement testsets is never fed a known defect in-suite (0 negative
  controls; the auditor's re-run of `probe1_registry_and_checker.jl` shows it
  fires on synthetic defects: 4-ulp part of an untouched class 1 violation, 8
  ulps against a 4-ulp class 1, one NaN on one side 2); the `tracking_task_option_schema()`
  key pin is a hand list whose comment claims a keyword tripwire nothing
  provides (`kwarg_decl`: 0 hits in `src/`; = todo row "A public TrackingTask
  field can have no schema entry"); the 8192/16384 declared bounds for the
  pole-face bend and the Lorentz boost cover a cancellation class no todo row
  tracks.
- **F-213 [Minor] U32-4..U32-13** `runtests.jl:15580, 15031, 13323, 14519,
  15678, 13814, 13809, 13675, 14687, 15833` rounding-luck pins
  (`reference_pair_residual(...) == 0` exact for 29.6% of energies; `op90.rho ==
  1` through `1 + 1.5e-18`), an unreachable guard, a CUDA gate without `else`,
  `@test true` under `OCTOPUS_SKIP_SCRIPT_MODE_TEST`, a skip text counting 25
  fixtures where there are 24 (auditor count), an anti-vacuity pin on the
  device compiler's FMA choice, a class table covering 28 of 31 kinds with no
  tripwire, a phantom `caught` bucket in a comment, a source-reading tripwire
  bounded from below only.
- **F-214 [Minor] U33-1..U33-5** `runtests.jl:17569, 16931, 17736, 18201,
  16433` "Spectral solve/eval split is exact" is circular (the auditor's
  re-run of `probe_spectral_split_circular.jl`: the pin holds with an injected
  all-zero field); the Core.Box allowlist carries `_initialize_moment_file!`
  (removed 2026-08-11; re-run: 0 hits, never used, no used-entry tripwire);
  the `OCTOPUS_MP` refusal testset hand-lists two of three harnesses; a
  crash-recovery log capture asserted on nothing; nine testsets mutate the
  process-wide RNG.
- **F-215 [Moderate] U34-1, U34-2** `runtests.jl:21843, 21638` the
  configuration-status testset's comment promises `declared ⊆ found` and the
  check does not exist (grep: 0; its regex also misses `:inherited`); "Every
  register-heavy kick launch goes through the thread cap" scans two hand-listed
  files while the spectral solver's kick kernels launch raw with a hardcoded 256
  in a third (sibling of F-12, F-45).
- **F-216 [Minor] U34-3..U34-8** `runtests.jl:21904, 21762, 21740, 19829,
  22480, 22300` a literal `x == x` anti-vacuity (read); a docstring scanner
  blind to `Base.`-qualified and `where` short forms; a 1e-18 "round-off" pin
  that is bitwise at the compared magnitudes; a slot-insensitive TurnTable
  replay pin; `with_logger(NullLogger())` over 28 runs; a `:funneled` arm gated
  on `nthreads(:default) > 1` with no skip.
- **F-217 [Moderate] U35-1** `runtests.jl:22912-22915` the "both branches over
  the SAME members agree" check compares the serial moment branch with itself
  (`same` repeats the `serial` call; the chunked branch is only checked for
  finiteness); the auditor's re-run of `probe_chunked_vs_serial.jl` shows the
  two branches agree to 1.9e-16 (sx) and 7.7e-16 (sy), so the code is sound
  and the claim is unexecuted.
- **F-218 [Minor] U35-2..U35-5** `runtests.jl:22583, 24586, 24280, 23605` an
  `all(...)` over a receipt list with no `!isempty` guard; a misaligned-marker
  "bit-identical" pin that holds at its one point and fails by 1 ulp on
  6884/20000 random coordinate sets (re-run of `probe_marker_bitwise.jl`; the
  BPM theory note generalises the same single measurement); `status === :passed
  || (status === :skipped && !CUDA_TESTS_ACTIVE)` recording an unrun CUDA leg as
  a Pass; `armloop(P)` deriving its expectation from beam 1 only (0 mismatches
  today, re-run).
- **F-219 [Minor] U36-1, U36-3..U36-6** `runtests.jl:25834, 25738, 28909,
  28933, 25756` the sub-ulp `atol` pins are bitwise pins between two
  non-identical reductions (= F-186); "EVERY solver" lists hand-enumerated at
  four sites; a `haskey(:pair_workers)` guard that silently skips the spectral
  family; `if nthr > 1` without a skip marker; the four-solver "gate == own"
  assertion compares a function with itself (`gate = _strong_strong_luminosity_evaluated(sv, c)`,
  read). U36-2 is F-6 seen from the test side.
- **F-220 [Moderate] U37-5** `runtests.jl:29227` the in-suite high-energy
  weak-strong limit widens the PIC tolerances to 0.60 and the spectral ones to
  0.80 against the validation script's 0.08 (measured errors 0.058 / 0.013): a
  1.5x-wrong PIC luminosity passes (agent's `p1_cpu_probes.jl` section (c);
  auditor re-run in batch 13, §6).
- **F-221 [Minor] U37-1..U37-4, U37-6..U37-10** `runtests.jl:30237, 31672,
  31616, 31314, 30125, 31829, 32015, 31711, 29053` the GPU-only block's skip
  text says 17 testsets / 358 assertions where there are 15 / 415 (auditor
  count 15); one CUDA gate shrinks 12 to 4 assertions silently; four host-only
  grid-typing checks hidden behind the device gate; a node-mesh fixture built
  from `1:nf` (295 benign drops where the comment claims 0); an unbounded
  self-derived `route_noise` tolerance; bitwise rms/sigma pins resting on
  NVPTX FMA contraction; a Float32 bit-identity pin with flip margin 0.27; a
  thin-beam thread-invariance arm without its anti-vacuity guard; hand-copied
  solver arm lists.

### Confirmed findings, waves 5 and 6: validation scripts and reference generators (U41-U45), theory and design notes (U46, U47, U49, U51), the top-level documents and ledgers (U52, U55), the MPI seam child and the nightly script (U53)

- **F-222 [Major] U53-1** `test/mpi_seam_check.jl:248-260, 385-401` the one-rank
  direction of both action-refusal arms cannot fail: `threw = try ... false
  catch err; err isa ArgumentError && occursin("task actions", ...) end`
  folds every other exception into `false`, which at one rank equals the
  expected value, so a fixture that CRASHES at one rank passes its "runs at
  one rank" half (read by the auditor; the agent's `probeB.log` under
  `mpiexec -n 1` shows both arms throwing: 3c a `MethodError` from
  `BeamSwapAction(identity)` handing the context back as the beam, 4b an
  `ArgumentError` from observers without an artifact; auditor re-run
  `U53_onerank_direction.log`, §6). A check only counts while it executes.
- **F-223 [Minor] U53-2..U53-8** `test/nightly_suite.sh:75-137`,
  `mpi_seam_check.jl:223`, `mpi_seam_check_fixture.jl:494`, `runtests.jl:23503`
  the stale-lock reclaim leaves the superseded run's `EXIT` trap on the lock;
  `status.tsv`'s header is written only when the file is new (the `cuda`
  column migration gap); stale calibration prose; the `cuda` column inferred
  from the absence of a hand-copied banner string; fixed artifact names under
  the shared `tempdir()`; a logger that swallows every record of the variant
  collides; migration counts printed but not asserted.
- **F-224 [Moderate] U45-1, U45-2** `validation/slice_interpolation_emittance_growth.jl:122`,
  `validation/slice_longitudinal_zscan.jl:121` the default output tag maps
  both non-default `interaction_grid` arms (`:source_slice`, `:node`) to one
  `_srcgrid` file name (`emittance_growth_<tag>.tsv`, tag at line 122; read),
  so the two arms overwrite each other silently (agent measured); the theory
  note's "source slice 6" z-scan rows have no committed setting that reaches
  them since the U24-8 fix.
- **F-225 [Minor] U45-3..U45-11** the emittance-growth meta row records no
  dropped charge; `OCTOPUS_ZSCAN_NSLICES < 3` dies with a raw `BoundsError`;
  contradictory PTC generator comments; the PTC coverage tripwire is
  one-directional (`Contracts.jl:2601`, sibling of F-115); stale README z-scan
  prose and line counts; the oracle tables carry no in-file provenance; two
  recorded numbers (the proton-on-electron ordering, the slice-4 h_x ratio
  1.23 vs the measured 1.144) differ from what the committed scripts produce.
- **F-226 [Moderate] U44-1, U44-2** `validation/kick_decomposition.jl:1-28`,
  `validation/noise_floor_meshswap.jl:251-263` the kick-decomposition script
  carries the mesh-swap script's header and a 160-line byte-identical dead copy
  of its body; the mesh-swap "correctness gate" is print-only and quotes the
  review's PIC-128/hybrid-64 columns for a run that executes PIC-64/hybrid-128
  (agent measured 7.98e-4 / 1.77e-4 against the printed 4.1e-4 / 1.6e-4).
- **F-227 [Minor] U44-3..U44-16** validation-script and note details in the
  beam-beam family: headers naming `data/` outputs the code writes to
  `result/`; a hard-coded `R100` in a filename; a padding sweep of a local
  quadrature only; a gate-only probe case dominating a headline error; a hand
  copy of the CIC profile with no tripwire; a `fourth=false` default where the
  solver's order should be read (the U23-10 class); four scripts reading
  `OCTOPUS_*` inputs their headers omit; no dropped-charge receipt in a run that
  dropped particles; hand-copied sigmas in a summary; a CUDA arm omitted
  silently; one script without the include guard; two notes naming the wrong
  validation script and pre-fix gain numbers; a script validating four local
  solvers against each other.
- **F-228 [Moderate] U41-1** `validation/twiss_xsuite_benchmark.jl:732` the
  gated C2 TOL-E "fitted order" on U2 and K2 is a pin on xtrack's
  finite-difference floor rather than a measurement of the Octopus integrator
  order, passing by 0.94 % / 1.7 % of its band (agent's
  `probe_u2_order_sensitivity.out`); the three consumers otherwise reproduce
  their recorded digests and the three generators regenerate their tables with
  0 differing cells (agent's `launch_all.out`, MAD-X 5.03.06, xtrack 0.112.0).
- **F-229 [Minor] U41-2..U41-8, U42-1..U42-15** the documented D5 fallback is
  unreachable (a forced witness miss still exits 1); the PTC frozen-cap
  provenance, the xtrack generator's non-failing header diff, literal
  `method`/`nst` columns, the MAD-X consumer recording the class tolerance
  rather than the applied bound, stale README line counts, hand-enumerated
  fixture lists (U41); a roundoff-stale committed Twiss maps table (14 of 45
  rows at up to 2.4e-15 after unit K), the identities script's exit 1 not
  announced by the README (A-1), a `lattice_cells` CUDA leg that cannot be
  required (exit 0 with six "skipped" under `REQUIRE=1`), a stale README
  symplecticity entry ("12 cases ... 7 of 22" against 27 and 22 of 22), copied
  literals, three thick kinds measured only through their misaligned wrappers
  (U42).
- **F-230 [Moderate] U47-1, U47-2, U47-3** `docs/theory/gaussian_subtracted_pic_solver.md:130`,
  `docs/theory/pic_free_space_kernels.md:325`, `docs/theory/coherent_beam_beam_modes.md:41`
  the hybrid note's Bassetti-Erskine display assigns the complex
  expression's real and imaginary parts to the wrong components (K_x and K_y
  swapped relative to the code and to the standard form; the agent measured
  the code against an independent evaluation, the auditor read the displayed
  equation at line 130); the lattice-kernel "re-measured with that documented harness"
  claim names a harness that measures something else; the coherent-modes note
  asserts committed `paper/data/*.tsv` are post-fix for a directory and files
  that do not exist in the tree.
- **F-231 [Minor] U47-4..U47-11, U46-1..U46-10** theory-note drift in the
  beam-beam family: a sign on the displayed lattice Green function; `max_gain`
  values cited from a non-existent `paper/data/`; a pre-fix rigid-bunch
  statement; remedies named for node-grid artefacts the code handles
  differently; `eta` called "momentum dispersion" where the API's convention
  is canonical (sibling of F-99); the spectral note's §15 written as future
  work for a landed solver and §14 verification numbers with no committed
  harness; a stale cost table; the near-round note's harness maxima moved
  (Float32 5.48e-6 vs the quoted 4.76e-6), a stale CUDA `:node` statement, a
  nonexistent `_pic_validate`, misattributed functions, two tables with no
  committed harness, an unqualified symplecticity statement for the chromatic
  composite (= F-119 seen from the note), two docstrings writing the Hirata
  energy term as `S/2 (px^2 + py^2)`, a removed `:quantile` estimator still
  listed.
- **F-232 [Moderate] U49-1 (= F-128)** `src/elements/floor_plan.jl:137` the
  floor-plan walkers read a kept-whole sub-line's `ref_tilt` from the spec, not
  the placement's merged params: the agent measured a 1.505e-2 tracking
  difference with a misaligned parent and 0.0 without (U18 measured the same
  defect from the other side; one finding, two units).
- **F-233 [Minor] U49-2..U49-15** stale status banners and pointers in the
  geometry notes (floor-plan "future work" and "written BEFORE the
  implementation"; the RF note's "question 3 remains open" against its own
  struck-through settlement, a dangling "open in todo.md" pointer, an
  over-claimed §8; the BPM note's "no naming scheme"; the arc-survey note's
  probe numbers with no committed receipt; a wrong cross-reference section; a
  recommended factorisation the implementation did not take; three inaccurate
  implementation statements; a stale closure snippet; `patch.jl` citing a
  "Section 7.5" that does not exist; `survey`/`FloorFrame` absent from
  `docs/public_api.md`).
- **F-234 [Moderate] U52-2, U52-4, U55-3** `docs/todo.md`, `docs/README.md:312`
  the "open work only" ledger carries about twenty rows whose state cell begins
  `**CLOSED` (auditor grep: 19 by the strict pattern; §7a lists 20 plus row 7),
  against the protocol's "closures move to the archive"; the index entry for
  the RF-cavity theory note still says Scope B "remains design only" and the
  F16 closure open, both landed.
- **F-235 [Minor] U52-1, U52-3, U52-5..U52-15, U51-1..U51-13, U55-1, U55-2,
  U55-4..U55-7** documentation drift at the top level and in the design notes:
  the retired "gate before every commit" rule surviving in five to seven
  places including the fast lane's closing banner (auditor grep: 5 in the
  markdown and the suite banner), "13" heavyweight sections against 15
  registered, the configuration guide's "enumerates policy types by hand (an
  open row)" for a closed row, the run-artifact index entry's status, the
  `TrackingContext` field list missing `index_offset`, a self-contradiction on
  the per-turn hook, a design default (`resolution_chord` 1e-4) ten times off
  the shipped 1e-3 with only the history recording it, a decided-but-unledgered
  probe-name default, two stale status lines, five superseded-behaviour
  paragraphs and two contradicted numbers in the multi-process note, the
  protocol's stale "newest neighbour-audit" pointer, a lesson describing ledger
  state that ended 2026-09-07, a measured-false `get_extension` sentence, one
  date in AGENTS.md against the invariants-only decision, one unindexed
  history `.txt` (`gpic_wobble_capture_2026_08_19.txt`, auditor grep: 0 index
  hits), six lesson numbers with no receipt outside `experiences.md`, the
  root README's "two cases" for three harnesses and its grid citation pointing
  at the wrong note.

- **F-236 [Major] U43-1** `validation/coherent_beam_beam_modes.jl:161-164` the
  "community-standard physics acceptance test" cannot run at HEAD: `run_case`
  constructs `MomentObserver(path1; orders=1:1, capacity=...)`, the standalone
  writer retired on 2026-08-18. Auditor re-run: `ERROR: LoadError:
  ArgumentError: the standalone moment file writer was retired (2026-08-18)`,
  exit 1 (`probes/auditor/U43_coherent_modes.log`). Third instance of the
  retirement's unmeasured blast radius (A-4, F-200): three committed scripts
  died on one constructor change and nothing executing noticed for two months.
- **F-237 [Moderate] U43-2, U43-3** `validation/eic_emittance_benchmark.jl:693-701`,
  `validation/coherent_mode_vlasov_theory.jl:356-361` the `MESHSCAN` receipt's
  four emittance-growth percentages compare the final state with itself (always
  0.0 by construction; agent measured); the asymmetric EIC normaliser builds
  the on-axis gradient from `s_t/sqrt2` (the rms mean of both beams' other-plane
  sigmas) where its own comment specifies the source's sizes, about 5 % in the
  y-plane detuning.
- **F-238 [Moderate] U43-4, U43-5, U43-6** `validation/near_round_gaussian_transition.jl:443-465,
  173-185`, `validation/plot_coherent_mode_theory.py:100-110` of about
  fifteen metrics the near-round script computes, three are gated and the rest
  print-only; its Phase-12 instrument validation exists only as a comment
  describing a one-off measurement whose magnitude does not match its reference;
  the overlay figure draws the incoherent continua as `[Q, Q + xi]` while the
  theory TSV classifies against `[Q, Q + xi*max]`.
- **F-239 [Minor] U43-7..U43-18** stale headers (one condition "stops it";
  retracted x-plane numbers still quoted; a frozen harness header), `damp=`
  printed from a variable nothing reads, a hard-coded 50000-turn moment
  schedule under a configurable run length, the electron beam never asserted
  unchanged in the limit script (sibling of F-114), a default spectral grid
  the solver warns against, a diagnostic window wider than the span it
  selects in, figure rows plotted regardless of their `is_mode`/`mesh_ok`
  flags, a note table whose numbers the committed script no longer produces,
  a cross-code "comparison" that prints a literal, and the in-suite limit
  tolerances (= F-220).
- **F-240 [Moderate] U48-2, U48-3, U48-4** `src/tasks/Tasks.jl:861`,
  `src/elements/beam_line.jl:616`, `docs/theory/beam_line_composition.md:422`
  an in-line `ScheduledObserver` inside a `BeamLine` throws a `MethodError` at
  `execute!` unless the line is the task's bare `elements` argument (=
  F-81, seen through the design note's promise); `find_entries(line,
  QuadrupoleSpec)`, the design note's own example, returns `Int[]` silently
  (`ElementSpec{:quadrupole}` is not a subtype of the friendly type); the
  note's matching recipe `qf.params[:k1] = ...` neither bumps `_SPEC_EPOCH`
  (agent measured 0 to 0) nor is read (`k1` is folded into `kn`), so a reader
  following it tracks a stale compile. U48-1 is F-128/F-232.
- **F-241 [Minor] U48-5..U48-14** the conventions note's SAD cubic formulas
  each lack `1/(1+delta)` against PTC (= F-164); section 6.4 reuses `p_z`
  for PTC's `1 + delta`; `n_wedge` named for a PTC version that lacks it; the
  suite's solenoid transverse pin (64 ulp) fails under other seeds of its own
  distribution (110, 215 measured by the agent); the bitwise `L = 0` solenoid
  identity pin holds for 44 % of random particles; "55 cases" is 61; the floor
  plan's `rho (cos a - 1)` form (= F-134); the solenoid misalignment check the
  note calls for was never written; stale design-note statements; open items in
  the notes with no todo rows.
- **F-242 [Minor] U50-1..U50-7** `docs/theory/crab_cavity_noise_response.md`,
  `docs/theory/twiss_dispersion.md` a doubling-time column low by ln 2; an
  approximate "residual rms" column; section 4.5's stale pointer to the owner
  row the 2026-10-18 decision closed; a sweep plan (A1/A4) the script replaced
  with A05/A1/A2 (= F-208); an overstated "gated" on the forced-4D/6D
  distinction; an unverified MAD-X `deltap` clause; hand-copied prediction
  defaults with no tripwire. The two notes' 166 numerical identities check to
  roundoff (agent's probes 1 to 4) and the canonical-eta convention is what
  the code does (eta canonical to 1.5e-15 on an h = 1.23 map).

- **F-243 [Minor] U54-2..U54-10** (U54-1 is A-4, found independently; the
  agent also measured that the underlying CPU/CUDA reduction check PASSES
  through the current constructor: 28 columns, max relative difference
  1.67e-13 against rtol 5e-12, so the dead script hid a green check)
  `validation/strong_beam_kick_fingerprint.jl:71` passes `hvoffset` as a tuple
  where the spec wants a Dict, so that branch has never been fingerprinted
  (the nine other digests reproduce the committed 2026-09-04 record bit for
  bit, compared by nobody in suite or CI); `strong_strong_pic_extreme_benchmark.jl:76`
  calls `CUDA.*` unconditionally after a harness that imports CUDA only under
  `use_gpu`; `public_configuration_effectiveness.jl:27` prints `status =
  skipped` and exits 0 under `OCTOPUS_REQUIRE_GPU_CONTRACT=1` with CUDA hidden
  (its two sibling scripts exit non-zero); hand-typed benchmark provenance; two
  unguarded includes; a tune estimator hand-copied in six files; a vacuous
  coordinate gate on a no-op solver; four print-only paper drivers; the
  effectiveness contract warning about its own fixtures' `rng_id` sharing (=
  F-49).

- **F-244 [Major] A-5, todo row 41** the full gate's native arm (CUDA active,
  four threads) dies with `signal 11` on 24e8683 on this machine at the same
  point in two runs 2.6 hours apart, one under agent load and one on a quiet
  machine, after the two `observer_option_schema(::Type{BPMObserver})`
  overwrite warnings (`runtests.jl:17769`, `17781`) printed on stderr, with
  the block-buffered stdout of the heavyweight section lost, so the crashing
  testset is somewhere after line 17781 in execution order. The same code
  (e255415, which 24e8683 extends by one docs-only commit) passed the same arm
  at 10:02 on 2026-10-18 (`full_gate_native_canon_gateE.log`, exit 0, 351
  summaries). Measured not to be the cause: machine memory (311 GB free, no
  OOM event since 2026-09-10), torn files in the shared `tempdir()` (none), a
  changed test environment (the `Pkg.test` status blocks of the green and the
  crashed runs are identical package for package), uncommitted changes
  (`dirty=0`). Candidates still open: the GPU state (half the device's memory
  held by another process since before the first crash), the depot's
  recompiled caches (new `.ji` files for `Octopus`, the MPI family and the
  extensions since the green run), the `result/` leftovers of this audit's
  Phase 10 runs inside the gate worktree. Two diagnosis runs were started at
  02:48 and are recorded in §6: the native arm under a pseudo-terminal
  (line-flushed stdout, so the crash site prints) and the CPU-only full lane
  in the main checkout (`CUDA_VISIBLE_DEVICES=""`). CI (CPU only) is green
  on 24e8683 (run 464). Same shape as todo row 41's CI segfault class.
  **Diagnosis results (02:48 to 03:41):** under a pseudo-terminal the crash
  site is visible (`full_gate_native_canon_pty_gateAudit3.log`, 195
  summaries, signal 11 at 03:20:53, 32 min in): the last completed top-level
  testset is "Turn modulation at execute!: the global-seed drift warning ..."
  (`runtests.jl:18861`) and the crash falls inside the next one, "One rng_id
  policy: zero assigns a fresh stream everywhere ..." (`runtests.jl:19046`),
  with no native stack trace (the fault handler printed nothing: the shape of
  a fault in a foreign thread or a finalizer). That testset alone is green in
  a fresh process (36 of 36, 10 s, `isolate_rng_policy_gateAudit3.log`); the
  five artifact and turn-modulation testsets from 18094 to 19046 run in one
  process with a forced full GC after each block are green
  (`isolate_artifact_gc_gateAudit3.log`; the one error is a runner fixture
  artefact). **The CPU-only full lane in the main checkout PASSED**
  (`full_gate_cpuonly_main_gateAudit2.log`, `CUDA_VISIBLE_DEVICES=""`, 02:48
  to 03:35, exit 0, 337 summaries, "Testing Octopus tests passed"): the
  crash needs CUDA active and the state of the full suite before line 19046.
  Not tried, priced for the fix campaign: clear the depot's compiled caches
  for Octopus and the CUDA family (regenerable) and run the native arm again;
  if it still dies, bisect the suite's first 19046 lines with the stage
  runner at four threads under a pseudo-terminal; the finalizer suspicion of
  row 41 (HDF5, now also CUDA) stands.

### Totals

244 confirmed findings (F-1 to F-244) plus six auditor-direct items (A-1 to
A-6): 14 Major (F-1, F-2, F-3, F-4, F-56, F-57, F-73, F-74, F-91, F-117,
F-192, F-200, F-222, F-236, F-244; F-236 and F-200 are the retirement class
with A-4), the rest Moderate and Minor as marked; every unit's leads were
re-run or read by the auditor except where a finding says "agent's log".

## 5. Corrections to this audit's own analysis

- The first Phase 0 plan missed 30 files (the MPI and Symbolics extensions, four
  test scripts, 22 validation scripts, two Python helpers); the coverage
  tripwire in `plan/coverage_check.json` caught it before any unit was
  launched, and the units were re-cut to 55. `.ipynb_checkpoints` copies
  (untracked, ignored) are deliberately outside the declared scope.
- `plan/leads.py`, the lead extractor, first required `[<severity>, confidence
  <c>]` exactly and single-line Claim fields; reports with tags (`OUT OF
  HYPOTHESIS`, `SEAM`) or wrapped claims were under-counted (U3 1 of 6, U7 2 of
  8). The pattern was relaxed to the header shape plus free-form bodies; the
  counts in §0b are from the relaxed extractor.
- A-1 was first drafted as possibly a new scaling-invariance defect; the stage
  9 record's row 19 shows it is the recorded owner item (re-freeze the
  multipliers on the 200-map set) measured again. The draft was corrected in
  place before the disposition.
- F-121 (the covariance builder refusing ForwardDiff duals) is a regression
  introduced by unit L of the 2026-10-18 beam-beam batch, written by this
  auditor. It is recorded as a finding of this pass, not softened; the fix
  belongs with the unit L neighbour audit the batch owed and did not run on
  the AD path.
- The auditor's one-liner for U17-9 used a `Beam` constructor form that does
  not exist; the lead stands on the agent's `probeD.log` (a `DomainError` from
  `sqrt`), and the attempt surfaced A-6 instead.
- The auditor's U18-9 one-liner first guessed a `Patch(s).m` field; the
  re-run compares `_floor_step` and `compile_runtime` under a String versus a
  Symbol convention directly (0.0587 rotation difference in the survey, 0.0 in
  tracking).
- Unit reports reached the auditor at about 95 % of their leads reproducing
  on re-run (the agents measured, and their Repro lines ran); the leads not
  re-run by the auditor are marked "agent's log" in §4. Two agent probes
  needed the agent's own ForwardDiff environment on `LOAD_PATH` (U16, U21)
  and one needed `CUDA_VISIBLE_DEVICES=""` (U11); the auditor's batch scripts
  record how each was invoked.

## 6. Test, contract, validation, and execution log

All on 24e8683 (the audited commit), the main checkout or the canon-A
worktree at that commit, this machine (Sapphire Rapids host, one CUDA device,
Julia 1.12.4), unless stated. Scratch: `result/comprehensive_audit_2026_10_18/`
(git-ignored; the per-unit reports are archived beside this record).

- **Phase 7, contracts (`exec/contracts.log`, `exec/contracts_2.log`):** all
  16 registered contracts pass their own `validate`, CUDA active; the
  element backend-consistency contract on a four-element `line=`, the PIC
  multi-process contract under `mpiexec=` (two ranks, 5.48e-17 absolute).
- **Phase 10, examples (`exec/examples.log`):** 5 of 5 example scripts exit 0.
- **Phase 10, validation (`exec/validation.log`, 13 scripts with committed
  references):** 11 exit 0; `twiss_dispersion_identities.jl` exit 1 (A-1,
  deterministic, identical at 3a04d90); `moment_observer_backend_consistency.jl`
  exit 1 (A-4, stale constructor).
- **Phase 8, the gate (`result/gates/turnmod/full_gate_native_canon_gateAudit.log`):**
  the native arm died with signal 11 at 00:28 inside "Elements and scripts
  follow-ups" while ten reading agents ran CUDA probes on the machine (A-5);
  the AVX2 arm did not start. **Re-run on a quiet machine
  (`full_gate_native_canon_gateAudit2.log`, 02:07 to 02:39, load 0.45 at
  start): signal 11 again at the same point; the AVX2 arm did not start.**
  F-244. Phase 8 is therefore NOT closed by this pass: no full-gate result
  exists for 24e8683 on this machine after 2026-10-18 10:02, and the audit
  record's own commit is markdown-only (its gate is the fast lane, below).
  Diagnosis runs started 02:48 (`full_gate_native_canon_pty_gateAudit3.log`,
  the native arm under a pseudo-terminal; `full_gate_cpuonly_main_gateAudit2.log`,
  the CPU-only full lane in the main checkout): the pseudo-terminal arm
  crashed at 03:20 inside "One rng_id policy ..." (`runtests.jl:19046`); the
  CPU-only lane PASSED (exit 0, 03:35, 337 summaries). Details in F-244.
- **The record commit's own gate:** every file this pass changes is markdown
  (`docs/`, `docs/history/`), `docs/registry_snapshot.md` untouched, so the
  matrix's class is "markdown only": targeted check = the index entry (the
  record and the unit-report directory are in `docs/README.md`, the wholesale
  marker names the directory), gate = the fast lane on the final tree:
  GREEN (`result/gates/turnmod/fast_lane_auditB_audit1.log`, 03:41 to 04:08,
  exit 0, 336 testset summaries, 16 `LANE SKIP` lines for the heavyweight
  sections, "Testing Octopus tests passed"). The fast lane earns no authority
  over the heavyweight sections; the full gate owed by Phase 8 is F-244's
  open item and the first task of the fix campaign.
- **Reproduction batches (`probes/auditor/`, sequential, fresh logs):**
  `run_wave1_repros.sh`, `_2.sh`, `_3.sh` (wave 1, 44 probe runs),
  `run_wave2_repros_1..4.sh` (wave 2, 36 runs plus the U13 runs from a
  scratch cwd), `run_wave3_repros_1..4.sh` (wave 3, 32 runs),
  `run_wave4_repros_1..2.sh` (wave 4), `run_u38_env.sh` (the two harness
  environment re-runs), and the auditor's own `u10_oneliners.jl`,
  `u17_oneliners.jl`, `u18_oneliners.jl`, `u27_oneliners.jl`, `u17_9.jl`.
  Every exit code is in the `wave*_repros*.log` files; a non-zero exit was
  in every case a probe-script artefact after the measurement printed
  (U6/p1, U8/p1, U13/probe_A, U18/probe1, U18/probe2, U26 three env-bound
  probes, U17/probeI) and is noted beside the finding it serves.
- **Reading coverage:** 55 units, 55 reports in `units/` (archived), every
  region read line by line by its agent; the auditor's seam passes S1 to S6
  are the cross-unit findings F-4 (S5), F-69 and F-75 (S1), F-3 and F-101 (S2),
  F-56 and F-77 (S3), F-203 and F-205 (S4), F-143 and F-179 (S6).

## 7. Open queue — dispositioned, priced, with reproductions

### 7a. The 41 inherited rows of `docs/todo.md` at 24e8683

Numbering follows §1. "Open" means the premise was re-read at HEAD and
stands; "closed" cells are ledger debris whose text confirms closure and which
this pass moves to `history/todo_ledger_archive.md`; findings named are this
pass's evidence.

| # | Row | Disposition |
|---|---|---|
| 1 | Twiss and dispersion analysis | open (owner items). A-1 re-measures the recorded re-freeze item (`c_scaling_invariance` 1.11x on 6x6 map 98 at the 20 + 5 multipliers). New under this family: F-192 (Major, canonical index swapped in resolved m = 2 clusters), F-176, F-177 (resolved-cluster seam), F-139, F-140 (contract blind spots), F-194 to F-199 (driver diagnostics), F-121 and F-179 (the 2026-10-18 builder's Float64 graph and its h boundary). |
| 2 | Turn-by-turn lattice modulation | open (owner items). F-66 to F-71 (provenance entry without sigma/octaves, complex-typed cavity dies at the first update, the mixed-kind warning, the untracked wrapper walk, two docstring keys). |
| 3 | Crab cavity noise example and validation | closed 2026-10-14; archive. |
| 4 | Crab noise example: MPI arm and benchmark | closed 2026-10-14; archive. |
| 5 | Turn modulation: record the realised offsets | open (owner decisions in the row). The artifact findings F-56 to F-65 and F-73, F-74 sit on the same file; F-62 is row 12 measured. |
| 6 | A spectral producer for `TurnTable` | closed 2026-10-16; archive. |
| 7 | Crab/RF noise neighbour audit: the open queue | closable: fix batches 1 to 3 are pushed (c061088, 9a4e3d6 and the batch 3 record abc7e38, CI 462 and 463 green), row 24 retired by owner decision (3a04d90); its surviving items are rows 8 to 17 of this list. Moves to the archive with the pointer to its record. |
| 8 | Stateful turn-modulation rules | open; premise unchanged (no shipped rule carries state). |
| 9 | Effectiveness contract pins `RunArtifact` options through receipts only | open, premise partly stale (U52-11): at HEAD the contract does sweep `run_artifact_option_schema()` and reads the `:strong_strong_output` receipt (`Contracts.jl:645-669`), so the row's two "nothing" sentences are false; what remains is F-52 (the output-boundary check records gaps, not coverage) and F-10 (the launch-family check cannot fail). The row text is corrected in this pass. |
| 10 | Two-harmonic fixture's `update_line` allocates | closed 2026-10-15; archive. |
| 11 | Two concurrent suites race in the example cleanup | open; the gate arms of this pass ran sequentially, so A-5 is not this race; the premise stands. |
| 12 | Receipt and provenance name an element by type only | open, measured: F-62 (`/turn_modulation/<slot>/<k>` attributes `beam`, `element`, `slot_count` only). |
| 13 | `rng_id = 0` makes provenance depend on construction order | open; widened by F-66 (the entry records neither sigma nor octaves, so two runs differing in rms are byte-identical in their receipts) and F-71. |
| 14 | Every-turn `MomentObserver` dominates the CPU per-turn cost | open, measured: F-78 (27.6 ms per row at N = 1e5, 75 % of a harness-like turn at four threads, 4.80 MB per call from six `collect` copies) and F-79 (the snapshot copies six whole arrays per fire). |
| 15 | Rank identity and per-rank `turn_timings` have no collective form | open; F-183 (four untimed collectives) is adjacent. |
| 16 | Quiet-machine benchmark of the per-turn rebuild | open; not run this pass (the machine was never quiet). |
| 17 | The class composition rule does not model gradient amplification | open and widened: F-100 measures it on a single element (`MarkerSpec(x_pitch=1e-3)`: 1951 ulps at 30 turns against 1024), F-118, F-120, F-162 are per-kind siblings, F-101 shows the elliptic class is set by an algorithm swap, not rounding. |
| 18 | Multi-process mixed execution policy | open; new rows from F-41 (Moderate: tall grids crash the MP gaussian-PIC route), F-170 (asymmetric rank verdict in `_mp_resolve_shard`), F-11 (latent per-direction verdict split), F-19 (design note Step 4d drift), F-173, F-183. |
| 19 | MPI suite reads receipts off a lossy stdout | closed 2026-09-06; archive. |
| 20 | Targeted neighbour audit of the multi-process campaign | closed 2026-09-06; archive. |
| 21 | `:funneled` tripwire tests a thread id | closed 2026-09-07; archive. |
| 22 | `_run_logical_workers` pool-of-one path | closed 2026-09-07; archive. |
| 23 | Luminosity-schedule broadcast hand-copied per solver | closed 2026-09-07; archive. The memo it introduced is F-6. |
| 24 | Loss accounting on the crash path is rank-local | closed 2026-09-07 (not a defect); archive. |
| 25 | The artifact does not record `summary_logged` | closed 2026-09-07; archive. |
| 26 | PIC `:node`/`:source_slice` take the per-pair route when divided | closed 2026-09-07 (not a defect); archive. |
| 27 | Tracked `Manifest.toml` predates `Project.toml` | closed 2026-09-07; archive. |
| 28 | Run-artifact niceties deferred at step 4 | open; F-64 (the schema's `s` and provenance attributes never stamped) touches the landed nicety. |
| 29 | CUDA in-suite vs standalone last-bit divergence | closed 2026-09-07; archive. |
| 30 | Observer schema-vs-report check is an identity | closed 2026-09-07; archive. |
| 31 | Three metadata-validator checks are tautologies | closed 2026-09-07; archive. F-172 and F-168 are the next tautology class (defaults verified for 77 of 608). |
| 32 | Observer declared defaults are unchecked | open; F-168 is the general form of the same gap. |
| 33 | Three metadata channels are unvalidated free text | open (two of three): F-172 (U25-9) measures that empty `description` and `meaning` pass. |
| 34 | `validate_configuration_metadata` enumerates types by hand | closed 2026-09-07; archive. |
| 35 | CPU threading: remaining measured headroom | open; the allocation findings F-26, F-32, F-78 are adjacent, no new timing. |
| 36 | `TrackingTask` records no per-turn timings | closed 2026-09-07; archive. |
| 37 | Fused luminosity route does not cover wrapped strong beams | closed 2026-09-08; archive (unit M of 2026-10-18 extended it to CUDA). |
| 38 | A public `TrackingTask` field can have no schema entry | open, example stale (U52-10): `loss_report` IS in `tracking_task_option_schema()` at HEAD (`(:record_turn_times, :luminosity_tracking, :artifact, :loss_report)`, auditor one-liner), so the row's named example no longer holds; the converse check it asks for still does not exist and the suite's key pin is a hand list (F-212). The row text is corrected in this pass. |
| 39 | Bmad reference cases for `misalign_convention=:bmad` | blocked on a tool; F-133 and F-211 (a String or invalid convention accepted and read two ways) are its neighbours. |
| 40 | CUDA near-identity pin wobbles | closed 2026-09-07; archive. |
| 41 | CI segfault on Julia 1.12.6 | open; A-5 adds a local data point of the same shape (signal 11 after every printed testset passed, inside the script-running testset, on 1.12.4 under machine load). |

Twenty rows (3, 4, 6, 10, 19 to 27, 29 to 31, 34, 36, 37, 40) are closed
cells and row 7 is closable with them: the twenty-one moved to
`history/todo_ledger_archive.md` under "Rows archived by the 2026-10-18
comprehensive audit" in this pass; nineteen stay open (the thirteen whose
premise this pass measured or corrected carry a dated note); one (39) is
blocked.

### 7b. New rows from this pass (written to `docs/todo.md` in the same commit)

Every Major finding is its own row; Moderate findings are grouped by the file
or seam a fix would touch, each row naming its findings; Minor findings are
one pointer row to §4 (a ledger of 150 rows would stop being read). Prices
are the auditor's estimate of the fix shape, not a promise. Fixes wait for the
owner's word (Phase 13).

| New row | Findings | Price |
|---|---|---|
| The full gate's native arm segfaults on 24e8683 on this machine, twice at the same point | F-244 (todo row 41's class) | first: the two diagnosis runs of §6 (crash site under a pseudo-terminal; CUDA hidden) decide CUDA-side or host-side; then bisect the heavyweight section with the stage runner; the gate is owed before the next push whatever the cause |
| CUDA PIC bounds reduction corrupts results for a thread count that is not a multiple of 32 | F-1 | small: validate `field_threads % 32 == 0` in `CUDAPICLaunchConfig` and `CUDALaunchConfig` for the bounds kernels, or pad the last warp with the neutral element; regression test at threads 100 on offset beams; neighbour audit of every warp-shuffle reduction |
| A legal `threads=1024` crashes the default CUDA PIC route on register count | F-2, F-12, F-45, F-215 | small-medium: route the two bounds launches (and the 47 other raw sites) through `_cuda_launch_capped!`; a launch-site tripwire derived from `grep CUDA.@cuda`; a sweep test at 1024 |
| `green_type=:standard` with the default slice-pair cache diverges CPU/CUDA by 1e-2 | F-3 | medium: move the half-cell sign test off the exactly representable boundary (fix I's class), or realign before expansion; backend-consistency case for `:standard` + `:slice_pair` |
| Strong-strong lines skip survey, aperture and reference-chain binding | F-4 | medium: run `_bind_apertures`, `_bind_survey`, `_validate_reference_chain` in `_split_strong_strong_line`, give `StrongStrongTask` a loss record route; every probing test first (invariant 2) |
| A refused `append=true` continuation has already truncated the file | F-56, F-58 | medium: validate every by-name refusal before the replay truncation; one ordering tripwire over the prepare steps |
| `/losses` is rewritten empty by a restarted task under `append=true` | F-57 | medium: replay `/losses` like the other groups; a restart test with a new task object |
| `observe!(::MomentObserver)` leaves a garbage row on a mid-row exception | F-73, F-84 | small: compute the row, then increment; the receipt after the refusal |
| The artifact cursor is keyed on a turn value and cannot see a fill-value torn tail | F-74, F-59, F-63 | medium: key the truncation on row count (the cursor's own row index), expose `rows_valid_through_turn` in the readers, refuse a missing cursor |
| A zero-voltage survey-bound RF cavity drops its velocity slip | F-91 | small: move the `iszero(strength)` return below the survey z-shift (or shift and return); the two-cavity ring test with one cavity off |
| A Float32 beam with an artifact never reuses its loss record | F-117 | small: compare the slots' eltype to the allocator's widened type; the Float32 + artifact test |
| Canonical eigenvalue index swapped in resolved multi-member clusters | F-192, F-176, F-177 | medium: tag recovered modes by eigenvalue match, not position; fix the projector route's trace list for resolved clusters; pin the index for m = 2 |
| Three committed scripts die on the 2026-08-18 `MomentObserver(path)` retirement | A-4, F-200, F-236; F-201, F-202 ride along (the other profiling drivers) | small each: port the three to the artifact form; add every CUDA-requiring validation script to the gate's CUDA arm (the class fix) |
| The MPI seam child's one-rank action arms cannot fail | F-222 | small: rethrow or fail on any exception that is not the expected refusal; fix the two fixtures that crash at one rank |
| Strong-strong solver stack: tripwires, conventions, dead code | F-5, F-6, F-8, F-9, F-11, F-26, F-41, F-13..F-25 | medium, several small fixes: the 6D CUDA tripwire denominator, the schedule memo keyed by task, the soft-Gaussian luminosity under losses, the node-path dropped tally, the latent verdict split, the allocating luminosity-grid path, the tall-grid `BoundsError` on the multi-process gpic route |
| Contracts that cannot fail or skip where CI runs | F-10, F-107, F-108, F-139, F-140, F-46..F-55 | medium: distinct override and fallback values in the effectiveness contracts; the twelve false exemptions removed; the stale-exemption tripwire before the CUDA early return; the F6a diversion counted as a failure |
| Tasks.jl walkers and the output tail | F-75, F-76, F-77, F-80..F-83, F-106 | medium: the `LineEntry` probe arm, the unfireable-schedule warning for all four hook kinds, the stored-turn rule on the output path, the raw-`ElementSpec` thin-kind fold |
| Observers: cost and provenance | F-78, F-79, F-66, F-85..F-90 | medium: a fused single-pass moment row (the open cost row 14), views for the snapshot's D2H copy, sigma/octaves in the provenance entry |
| Element kinds: silent reads and conventions | F-92, F-93..F-99, F-160, F-161..F-167 | medium: undeclared keys refused on the thin kinds, declared defaults read through `getparam`, `bend_fringe` default by kind, the second bend cancellation, the curved-drift quarter-turn guard, the convention stated on the dispersion parameters |
| Cross-backend rounding classes: composition, regime, algorithm | F-100, F-101, F-118, F-120, F-162, F-103, F-105 | medium, a design decision first: per-turn growth in the class rule or a turn-count-qualified declaration; one Faddeeva algorithm on both backends or a declared algorithm class; Float32 ulps |
| Weak-strong element option values `:chromatic` and `:exact` | F-119, F-120, F-121, F-122..F-125 | medium: recompute S from z* in the chromatic composite, the small-quantity form in the forward exact drift, the Dual-capable dispersion graph (the 2026-10-18 regression), hvoffset key validation |
| Floor plan and beam-line geometry | F-126..F-129, F-130..F-138, F-232, F-240 | medium: `ref_tilt` from the merged placement params and on patches and the top-level line, Dual promotion on lines, `find_entries` by kind, the design note's mutation recipe |
| Knowledge layer and policies: validators that skip | F-168, F-169, F-170, F-171..F-175 | medium: declared defaults checked for every key, policy defaults against constructed objects, a symmetric rank verdict in `_mp_resolve_shard` |
| Beam construction and statistics | F-185, F-186, F-187..F-191, A-6 | small each: refuse `sigma` with `emit` (and `C` with `R`), a structural statistics pin or one reduction order, `BeamParams` keyword defaults typed |
| Knobs: the derivative path and the edges | F-181, F-182..F-184 | small: registry lookup in `knob_derivative`; the five edge fixes |
| Analysis driver diagnostics and uncertainty fold | F-194, F-195, F-196..F-199 | medium: scale `map_uncertainty` with the matrix, the repeated-pair tie order, the mod-2pi tune domain, receipts that say what ran |
| Harnesses and examples: assert what the run recorded | F-203, F-204, F-205, F-206 | small-medium: pass the four gaussian-PIC options, refuse unknown `config.execution`, read the six switch-gated variables or refuse them by name (the crab harness as the template) |
| Validation scripts: gates, outputs, defaults | F-207, F-224, F-226, F-228, F-237, F-238, F-225, F-227, F-229, F-239 | medium: `mkpath`, unknown-key refusal, distinct output tags per arm, a receipt that compares two states, gated metrics where print-only, header/output drift |
| Test suite: checks that cannot fail or skip silently | F-156, F-210, F-212, F-215, F-217, F-220, F-211, F-213, F-214, F-216, F-218, F-219, F-221 | medium, many small: the listed tautologies, circular pins, gates without `else`, hand lists without tripwires, tolerances widened to data |
| Documentation drift: notes, design notes, index, ledgers | F-208, F-230, F-234, F-19, F-64, F-65, F-136, F-180, F-231, F-233, F-235, F-241, F-242 | small each, one sweep: the Bassetti-Erskine display, the retired "before every commit" rule in five places, the CLOSED rows out of the open ledger, stale status banners and pointers |
| Minor findings of the 2026-10-18 comprehensive audit (pointer) | every Minor F-id of §4 not named above | the record's tables are the queue; close by batch with a neighbour audit per file |

U54's leads (F-243) join the pointer row and the validation-scripts row; U54-1 is the retirement row above.

## 8. Change log

This pass was authorized to audit, not to fix (AGENTS.md, Change
Authorization: the owner's words were "go ahead with the comprehensive
review of the whole repo, following the protocol"). No file under `src/`,
`test/`, `validation/`, `examples/`, `profiling/`, `ext/` or `docs/` other
than the ledgers below changed. The repository changes of this pass are:

- this record and its unit-report archive
  (`docs/history/comprehensive_audit_2026_10_18_unit_reports/`, 55 reports);
- `docs/README.md`: the index entries for both;
- `docs/todo.md`: the new rows of §7b, the dispositions of §7a written into
  the open rows' state cells where they add evidence, and the twenty closed
  rows plus row 7 moved to `history/todo_ledger_archive.md` under a dated
  heading;
- `docs/experiences.md`: the lessons of §9 that are new (each cites the
  finding that paid for it).

Phase 13 (fix confirmed findings) is deferred to the owner's word; §7b prices
every finding as a row so the fixing campaign can be cut from it.

## 9. Remaining risks

- **The gate.** Until the quiet-machine two-arm gate of §6 is green on
  24e8683, Phase 8 is not closed: A-5's segfault is either machine load or a
  second instance of todo row 41's class, and the record says which once the
  re-run exists.
- **Reproduction depth.** About one lead in twenty stands on the agent's log
  alone (so marked); every Major and every Moderate was re-run or read by the
  auditor. Minor leads in the test regions were verified by reading the cited
  lines, not by executing the suite around them.
- **What was not measured.** The multi-process protocol beyond two ranks and
  one rank-death case (U11); the quiet-machine benchmark (row 16); the Bmad
  convention (row 39); Float32 end to end on CUDA beyond the parity probes;
  the AVX2 parity arm of anything in this pass.
- **Blast radius of the Majors.** F-4 (strong-strong lines skip three binding
  steps), F-56/F-57/F-73/F-74 (artifact data loss under append and on the
  crash path) and F-192 (canonical index swapped) each change what a user's
  file or result means; fixing them changes acceptance semantics and every
  probing test must be found first (invariant 2). F-1/F-2 (CUDA thread
  counts) are launch-site fixes whose neighbours are the 60 raw launch sites
  F-12 counts.
- **The audit's own fix.** F-121 is a regression by the auditor's 2026-10-18
  unit; it is priced in §7b like every other finding and should not be
  fixed outside the owner-authorized campaign.
- **Lessons for `docs/experiences.md`** (each paid for here): a fix's
  neighbours include the walker and the twin that did not change (F-4, F-75,
  F-91: the strong-strong compile, the `BeamLine` probe walk, the zero-voltage
  early return the F16 closure sat below); a contract whose override and
  fallback coincide verifies nothing (F-10, F-140); a cursor keyed on a
  value cannot see a torn tail of fill values (F-74); a validation script
  that CI cannot run must be run by the gate's CUDA arm or it rots (A-4,
  F-200); a convention stated once must be stated at every consumer (F-99,
  F-133, F-143).

## Addendum 2026-10-19 (fix campaign, step 2): F-244, the gate's CUDA-arm segfault

Written after the record closed, at the owner's word ("hold the push and
start second step"). Nothing above this heading was changed. Every run below
is the full native arm (`Pkg.test`, CUDA active, four threads) on 24e8683 in
a clean worktree; from gateAudit3 on, under a pseudo-terminal so the crash
site prints (logs under `result/gates/turnmod/`, the run table is also in the
auditor's scratch `addendum_draft.md`).

| run | start | compiled caches | files directly under the worktree's `result/` | other load | result |
|---|---|---|---|---|---|
| gateAudit | 23:54 (10-18) | pre-audit set | 5 Phase-10 TSVs (written 00:08-00:12, during the run) | ten reading agents | signal 11 at 34 min |
| gateAudit2 | 02:07 | same | same | none | signal 11 at 32 min |
| pty gateAudit3 | 02:48 | same | same | the CPU-only lane in the main checkout | signal 11 at 32 min; site: inside "One rng_id policy ..." (`runtests.jl:19046`), no native trace |
| gateAudit4 | 08:40 | cleared (Octopus, its extensions, the CUDA family moved aside; 35 packages recompiled) | none (moved to scratch) | none | PASS, exit 0, 351 summaries |
| gateAudit5 | 09:48 | the old set restored | none | none | PASS, exit 0 |
| gateAudit6 | 10:49 | old set | the 5 TSVs copied back | none | signal 11 at 32 min, same site |
| core1 (canon-A) | 11:31 | old set | 5 TSVs | half1 concurrently | passed the site; FAILED later in "The multi-process seam runs under an MPI launcher": the two concurrent suites' MPI children collided on the fixed names under the shared `tempdir()` (F-223 / U53-6, measured live) |
| half1 (bisect-B) | 11:31 | old set | 3 TSVs | core1 concurrently | PASS, exit 0 |
| loopA_1 .. loopA_4 (canon-A, core dumps armed) | 12:14, 13:12, 14:10, 15:08 | old set | 5 TSVs | none | all four passed the site; all four PASS, exit 0, no core |
| AVX2 arm gateAudit7 (canon-A, `OPENBLAS_CORETYPE=Haswell`, `-C haswell`) | 16:05 | old set | 5 TSVs | none | PASS, exit 0, 351 summaries (17:12) |

What the runs say. The crash is intermittent: four of twelve native-arm runs
died, every one at the same testset, the last at 11:22, none in the six
runs since; the CPU-only full lane passed twice (02:48 run, CI 464). The two
hypotheses the record named are both excluded as THE cause: the compiled
caches (gateAudit5 passed with the old set) and the leftover `result/` files
(six passes with them present; they remain a weak correlate, no crash
occurred without them, but no run without them crashed either because none
was attempted before 08:40). Excluded by reading: a plain data race on the
counter-RNG registry the testset mutates (`counter_rng.jl:100`, every path
under `_RNG_ID_REGISTRY_LOCK`). Excluded by a probe: the suite's `@eval`
redefinition of `observer_option_schema(::Type{BPMObserver})` that precedes
the site (`probes/auditor/f244/redef_repro.jl`, steps 0-5 clean). The crash
site alone is green in a fresh process; the five artifact and turn-modulation
testsets before it, run in one process with a forced full GC between blocks,
are green. No core was captured: the four capture runs (`ulimit -c unlimited`,
`core_pattern = core`, 12:14 to 16:05) all passed.

Disposition: F-244 stays open as an intermittent fault of unknown mechanism
with a fixed site. Mitigations in force from this step: (1) the gate scripts
run with core dumps enabled and under a pseudo-terminal
(`run_full_gate_native_pty_wt.sh`, `f244_core_loop.sh`, `f244_gdb_core.sh` in
`result/gates/turnmod/`), so the next occurrence yields a native backtrace;
(2) one suite at a time on one machine, whatever the worktree (the MPI seam
child's fixed `tempdir()` names, F-223, now measured to fail a concurrent
suite); (3) a signal-11 gate is re-run once before anything else is
concluded, and the re-run's pseudo-terminal log is kept. The guide carries the
procedure. Phase 8 for 24e8683: the native arm is green six times since
08:40 (eight runs passed the crash site) and the AVX2 arm is green (gateAudit7,
exit 0): the two-arm gate stands for 24e8683, with F-244 open as the
intermittent fault it is. The record commit 2f5acfd and this addendum are
markdown-only; the fast lane on the final tree is their gate: GREEN
(`result/gates/turnmod/fast_lane_auditB_audit2.log`, 17:12 to 17:38, exit 0,
336 testset summaries, 16 `LANE SKIP` lines).

## Addendum 2026-10-20 (fix campaign, batch 1)

The thirteen Major rows of section 7b were closed by the fix batch recorded in
[`comprehensive_audit_fixes_2026_10_19.md`](comprehensive_audit_fixes_2026_10_19.md) (ten units P to Y, merged and gated on the
integrated tree); their closings are in the ledger archive, and the pointer row
of `todo.md` carries what that batch left for the owner. The Moderate and
Minor rows of 7b stay open for the next batches.

## Addendum 2026-10-21 (fix campaign, batch 2)

The five instrument rows of section 7b (contracts that cannot fail, suite checks, the validators, validation scripts and harnesses) were closed by the fix batch recorded in [`comprehensive_audit_fixes_2026_10_20_batch2.md`](comprehensive_audit_fixes_2026_10_20_batch2.md); the runtime rows and the documentation and Minor rows stay open for batches 3 and 4.

## Addendum 2026-10-22 (fix campaign, batch 3)

Eight runtime rows of section 7b (the strong-strong solver stack, the task walkers, the observers, the weak-strong option values, the floor plan, the beam, the knobs, the analysis driver) were closed by the fix batch recorded in [`comprehensive_audit_fixes_2026_10_21_batch3.md`](comprehensive_audit_fixes_2026_10_21_batch3.md); the rounding-class row waits on the owner's two design decisions, the element-kinds row did not land in this batch, and the documentation and Minor rows (batch 4) remain. The closings are in the ledger archive; the pointer row of `todo.md` carries what the batch left for the owner.

## Addendum 2026-10-22 (fix campaign, batch 4a: the record's own arithmetic)

Four corrections to this record's bookkeeping, found by the markdown-only documentation sweep of fix batch 4a; the body above is unchanged.

- The Totals paragraph of section 4 reads "14 Major (F-1, F-2, F-3, F-4, F-56, F-57, F-73, F-74, F-91, F-117, F-192, F-200, F-222, F-236, F-244; F-236 and F-200 are the retirement class with A-4)" and lists fifteen ids. Counted by the severity tag of every entry in section 4 (the bullets and the table rows, qualified tags such as `[Moderate, performance]` included, the fourteen untagged rows of the table "Confirmed Minor findings (static, verified by the auditor against the source)" taken as Minor by their heading), this record holds 15 Major, 64 Moderate and 165 Minor findings, F-1 to F-244 each exactly once, 244 in all. The Major findings fill fourteen rows of section 7b (F-200 and F-236 share the retirement row), thirteen of them closed by batch 1 and F-244's handled as step 2, which is where "13" and "14" come from. `docs/todo.md`'s campaign row ("its 243 findings and six auditor items were priced in rows of this ledger") and this record's index entry in `docs/README.md` ("243 confirmed findings plus six auditor-direct items, 13 of them Major") said 243 and 13; batch 4a corrected both to 244 and 15.
- F-7, the line "- **F-7 [Moderate] A-4** the stale CUDA validation script (above).", closed with fix batch 1's unit X (`comprehensive_audit_fixes_2026_10_19.md`, "### Unit X: three dead scripts (A-4, F-200, F-236; F-201 in part)"), which named A-4 and never the id; no fix record, archive row or `todo.md` row names F-7.
- F-243's first item (U54-2: "`validation/strong_beam_kick_fingerprint.jl:71` passes `hvoffset` as a tuple where the spec wants a Dict, so that branch has never been fingerprinted") closed with fix batch 3's unit I (`comprehensive_audit_fixes_2026_10_21_batch3.md`: "`hvoffset` validated by name with `coef` and `frequency` required and its waveform computed in the element's type (F-122, F-123)"); at 3056167 the script's line 79 passes `hvoffset=Dict(:dim => :x, :coef => 1.0e-6, :frequency => 197.0e6)`. No fix record names F-243; its other items are not re-examined here.
- The markdown items of the documentation-drift row (F-208, F-230, F-234, F-64, F-65, F-231, F-233, F-235, F-241, F-242) were swept by batch 4a, record [`comprehensive_audit_fixes_2026_10_22_batch4a.md`](comprehensive_audit_fixes_2026_10_22_batch4a.md); F-19 and F-136 of that row had already closed with batch 3 (units E and K); the `.jl` remainders (F-180; the docstrings, suite pins and script tripwire of F-231, F-233, F-241, F-242) belong to batch 4b.
