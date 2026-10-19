# Unit reports of the 2026-10-18 comprehensive audit

These are the verbatim reading-unit reports of the comprehensive audit recorded in
[`../comprehensive_audit_2026_10_18.md`](../comprehensive_audit_2026_10_18.md), copied unchanged
from the session scratch (`result/comprehensive_audit_2026_10_18/units/`). Every lead in them
is a lead, not a finding: the record's section 4 says which were reproduced by the auditor
and under which F-number. Severities in the table are the agents' guesses as written.

| Unit | Report title | Leads (agent's severity guesses) | File |
|---|---|---|---|
| U1 | U1: pic_cuda.jl, first third | 4: 1 Major, 3 Minor | [U1_report.md](U1_report.md) |
| U2 | U2: pic_cuda.jl, second third | 5: 1 Major, 4 Minor | [U2_report.md](U2_report.md) |
| U3 | U3: pic_cuda.jl, last third (lines 4401-6492) | 6: 1 Major, 5 Minor | [U3_report.md](U3_report.md) |
| U4 | U4: pic_cpu.jl | 6: 2 Moderate, 4 Minor | [U4_report.md](U4_report.md) |
| U5 | U5: pic_cpu_sliced.jl (new since the last audit) | 7: 1 Moderate, 6 Minor | [U5_report.md](U5_report.md) |
| U6 | U6: interface.jl (strong-strong task, options, caches) | 11: 2 Major, 3 Moderate, 6 Minor | [U6_report.md](U6_report.md) |
| U7 | U7: spectral.jl + spectral_cuda.jl (twin pair) | 8: 1 Moderate, 7 Minor | [U7_report.md](U7_report.md) |
| U8 | U8: spectral_sliced.jl + gaussian.jl + slicing.jl | 6: 1 Moderate, 5 Minor | [U8_report.md](U8_report.md) |
| U9 | U9: gaussian_pic.jl + gaussian_pic_cuda.jl (twin pair) | 5: 1 Moderate, 4 Minor | [U9_report.md](U9_report.md) |
| U10 | U10: Contracts.jl, first half | 14: 1 Moderate, 13 Minor | [U10_report.md](U10_report.md) |
| U11 | U11: Contracts.jl, second half + the MPI child | 10: 2 Moderate, 8 Minor | [U11_report.md](U11_report.md) |
| U12 | U12: Tasks.jl | 6: 3 Moderate, 3 Minor | [U12_report.md](U12_report.md) |
| U13 | U13: RunArtifact.jl (new since the last audit) | 10: 2 Major, 2 Moderate, 6 Minor | [U13_report.md](U13_report.md) |
| U14 | U14: BeamObservers.jl + BPMObserver.jl | 13: 2 Major, 3 Moderate, 8 Minor | [U14_report.md](U14_report.md) |
| U15 | U15: turn_modulated.jl + crab_cavity.jl | 6: 1 Moderate, 5 Minor | [U15_report.md](U15_report.md) |
| U16 | U16: strong_beam.jl + strong_beam_track.jl | 8: 3 Moderate, 5 Minor | [U16_report.md](U16_report.md) |
| U17 | U17: lattice_magnets.jl + solenoid.jl + linear6d.jl | 9: 1 Moderate, 8 Minor | [U17_report.md](U17_report.md) |
| U18 | U18: beam_line.jl + aperture.jl + misalignment.jl + ref_tilt.jl + patch.jl + floor_plan.jl | 18: 1 Major, 4 Moderate, 13 Minor | [U18_report.md](U18_report.md) |
| U19 | U19: rf_cavity.jl + thin_elements.jl + linear_maps.jl + lorentz_boost.jl + chromaticity_kick.jl + radiation.jl | 10: 1 Major, 1 Moderate, 8 Minor | [U19_report.md](U19_report.md) |
| U20 | U20: track/ + math/ | 6: 2 Moderate, 4 Minor | [U20_report.md](U20_report.md) |
| U21 | U21: analysis/: the analysis object, Determined, one-turn matrix | 10: 2 Moderate, 8 Minor | [U21_report.md](U21_report.md) |
| U22 | U22: analysis/: dispersion routes, canonical separation, degenerate dispersion | 8: 1 Moderate, 7 Minor | [U22_report.md](U22_report.md) |
| U23 | U23: analysis/: mode clusters, coupled parameterizations, 4D eigenmodes, symplectic algebra | 3: 1 Major, 2 Minor | [U23_report.md](U23_report.md) |
| U24 | U24: contracts/: the three analysis contracts | 9: 2 Moderate, 7 Minor | [U24_report.md](U24_report.md) |
| U25 | U25: Policies.jl + Knowledge.jl + Methods.jl | 10: 3 Moderate, 7 Minor | [U25_report.md](U25_report.md) |
| U26 | U26: Knobs.jl + symbolic.jl + ext/ (ForwardDiff, MPI, Symbolics extensions) | 11: 1 Moderate, 10 Minor | [U26_report.md](U26_report.md) |
| U27 | U27: Beam.jl + Registry.jl + Examples.jl + Octopus.jl + constants + Elements.jl + StrongStrong.jl | 10: 2 Moderate, 8 Minor | [U27_report.md](U27_report.md) |
| U28 | U28: test/runtests.jl lines 1-3242 (lanes, CUDA visibility, architecture integrity, the Twiss analysis stages  | 7: 7 Minor | [U28_report.md](U28_report.md) |
| U29 | U29: test/runtests.jl lines 3243-6447 (Twiss analysis stages 3 A1/B, 4a, 4b Part A) | 8: 8 Minor | [U29_report.md](U29_report.md) |
| U30 | U30: test/runtests.jl lines 6448-9635 (stage 4b Part A/B analysis testsets, tracking-task and luminosity tests | 10: 1 Moderate, 9 Minor | [U30_report.md](U30_report.md) |
| U31 | U31: test/runtests.jl lines 9636-12910 — misalignment and ref_tilt maps, the bend and series numerics, turn mo | 6: 1 Moderate, 5 Minor | [U31_report.md](U31_report.md) |
| U32 | U32: test/runtests.jl lines 12911-16037 (precision rule, cross-backend classes, element/solver effectiveness,  | 13: 3 Moderate, 10 Minor | [U32_report.md](U32_report.md) |
| U33 | U33: test/runtests.jl lines 16038-19586 (BeamLine, loss accounting, observers, thread invariance, metadata val | 5: 5 Minor | [U33_report.md](U33_report.md) |
| U34 | U34: test/runtests.jl lines 19587-22525 — run-artifact record/lock/receipt testsets, the turn-modulation probe | 8: 2 Moderate, 6 Minor | [U34_report.md](U34_report.md) |
| U35 | U35: test/runtests.jl lines 22526-25667 (multi-process seam tests, CUDA pins, contract guards, one_turn_matrix | 5: 1 Moderate, 4 Minor | [U35_report.md](U35_report.md) |
| U36 | U36: test/runtests.jl 25668-28979 -- lost-particle masking, apertures and loss records, solenoid and patch map | 6: 1 Moderate, 5 Minor | [U36_report.md](U36_report.md) |
| U37 | U37: test/runtests.jl lines 28980-32035 (pair-schedule receipts, the GPU-only block, knobs, physics contracts, | 10: 1 Moderate, 9 Minor | [U37_report.md](U37_report.md) |
| U38 | U38: test/examples/ + examples/ | 11: 3 Moderate, 8 Minor | [U38_report.md](U38_report.md) |
| U39 | U39: profiling/ | 13: 2 Major, 3 Moderate, 8 Minor | [U39_report.md](U39_report.md) |
| U40 | U40: validation: crab-cavity noise, turn-modulation spectra, counter RNG, diagnostics benchmark | 15: 4 Moderate, 11 Minor | [U40_report.md](U40_report.md) |
| U41 | U41: validation: Twiss external benchmarks and reference generators | 8: 1 Moderate, 7 Minor | [U41_report.md](U41_report.md) |
| U42 | U42: validation: Twiss acceptance windows, cells, identities, lattice cells, survey reference, symplecticity,  | 15: 15 Minor | [U42_report.md](U42_report.md) |
| U43 | U43: validation: coherent modes, EIC emittance, high-energy limit, near-round transition | 18: 1 Major, 5 Moderate, 12 Minor | [U43_report.md](U43_report.md) |
| U44 | U44: validation: field, luminosity, grid, noise floor, option consistency, kick decomposition, spectral compar | 16: 2 Moderate, 14 Minor | [U44_report.md](U44_report.md) |
| U45 | U45: validation: slicing studies, PTC reference generator, the validation README and reference provenance | 11: 2 Moderate, 9 Minor | [U45_report.md](U45_report.md) |
| U46 | U46: theory notes A: longitudinal kick, near-round switch, slice interpolation, longitudinal slicing | 10: 10 Minor | [U46_report.md](U46_report.md) |
| U47 | U47: theory notes B: subtracted PIC, spectral Poisson, free-space kernels, node grid, coherent modes, weak-str | 11: 3 Moderate, 8 Minor | [U47_report.md](U47_report.md) |
| U48 | U48: theory notes C: lattice Hamiltonian and conventions, solenoid, beam-line composition | 14: 4 Moderate, 10 Minor | [U48_report.md](U48_report.md) |
| U49 | U49: theory notes D: misalignment and patch, aperture and loss, RF cavity and reference energy, arc survey, fl | 15: 1 Moderate, 14 Minor | [U49_report.md](U49_report.md) |
| U50 | U50: theory notes E: twiss_dispersion.md and crab_cavity_noise_response.md | 7: 7 Minor | [U50_report.md](U50_report.md) |
| U51 | U51: design notes as claims about the code | 13: 13 Minor | [U51_report.md](U51_report.md) |
| U52 | U52: top-level docs, guides, AGENTS.md, CI workflow, the open todo rows | 15: 2 Moderate, 13 Minor | [U52_report.md](U52_report.md) |
| U53 | U53: test/: the MPI seam check and fixture, the turn-modulation probe, the nightly suite script | 8: 1 Major, 7 Minor | [U53_report.md](U53_report.md) |
| U54 | U54: validation: consistency, effectiveness and small studies (20 scripts) | 0: 0 | [U54_report.md](U54_report.md) |
| U55 | U55: process documents: the audit protocol and the experiences file | 7: 7 Minor | [U55_report.md](U55_report.md) |
