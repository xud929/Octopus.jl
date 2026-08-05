# U26 — Documentation tree as claims about the code

Reading unit of the comprehensive audit protocol. Repository
`/cfs/ad/dxu/Library/Julia/Octopus`, HEAD `c55d2e0` (working tree clean at
session start; `7de4d81` + two audit-session commits). Julia 1.12.4.

## Region

`docs/README.md`, `docs/public_api.md`, `docs/current_runtime.md`,
`docs/registry_snapshot.md`, `docs/knob_control.md`, and all 17 notes in
`docs/theory/` (~9,000 lines). Plus AGENTS.md's own layout claims (task item f).
Excluded by brief: `docs/todo.md`, `docs/history/`, `docs/comprehensive_audit.md`.

## Provenance

**Read in full** (every line): AGENTS.md; `docs/comprehensive_audit.md`
§"Phase 6" and §"Measured Lessons"; `docs/README.md`; `docs/public_api.md`;
`docs/current_runtime.md`; `docs/knob_control.md`; all 17 theory notes.

**Read in part** (targeted against a doc claim): `src/elements/rf_cavity.jl`,
`src/elements/strong_beam.jl`, `src/elements/solenoid.jl`,
`src/elements/misalignment.jl`, `src/elements/beam_line.jl`,
`src/tasks/BPMObserver.jl`, `src/tasks/strongstrong/{interface,pic_cpu,pic_cuda,
spectral,gaussian_pic,slicing}.jl`, `src/track/longitudinal.jl`,
`validation/coherent_mode_vlasov_theory.jl`,
`validation/pic_gaussian_field_validation.jl`.

**Executed**: two Julia probes under
`scratchpad/audit/` (`u26_probe1.jl`, `u26_probe2.jl`) plus shell diffs.
No repository file was modified.

## Leads

### LEAD U26-1 [Major, confidence high] docs/theory/gaussian_longitudinal_slicing.md § "Measured ranking"
Claim: the note states the shipped default slicing rule is `:equal_area` and
that changing it is an open call; the default has been `:sqrt_density` since
2026-07-31 and `docs/todo.md` records the change as DONE.
Mechanism: §10's table row already annotates `:sqrt_density` as "(default since
2026-07-31; this table once said `:equal_area`)", but the "Measured ranking"
subsection forty lines later still labels `:equal_area` "(default)" in its table
and asserts in bold "**The default is still `:equal_area`** … `docs/todo.md`
records that as an open call." The sentence "`:sqrt_density` is … 10.6x more
accurate than the shipped default" is then self-contradictory, since
`:sqrt_density` *is* the shipped default. A reader taking the later paragraph at
face value will believe production runs use the rule the note ranks 4th.
Repro: `grep -n "slice_method=:sqrt_density" src/elements/strong_beam.jl`
→ lines 250, 312 (constructor defaults) and 1566 (`ParamMeta(default=:sqrt_density)`);
`grep -n "DONE: default changed to" docs/todo.md` → line 1263.

### LEAD U26-2 [Major, confidence high] docs/theory/slice_longitudinal_interpolation.md §7.5, §10.6, §12
Claim: the note says CUDA `:quadratic` exists only on the sequential
non-batched-FFT route (2.87x the production default, "wait for wavefront
support") and that `:node` "throws" on the wavefront and batched-FFT routes.
Both CUDA ports have since landed.
Mechanism: `pic_cuda.jl` defines
`_cuda_pic_interaction_wavefront_quadratic_indexed_batched_fft!`, whose own
docstring calls it "the production route", and `:node` is supported on the
indexed wavefront route (only the *non-indexed* sub-routes throw, and only
because `pic_timing_detail=true` disables the indexed one — F11, 2026-08-05).
The solver docstring in `interface.jl` is current and correct; the theory note
is not. Cost: a CUDA user following §12 runs the 2.48x-slower sequential route
for no reason, and a reader of §10.6 believes `:node` is unavailable in
production.
Repro: `grep -n "quadratic_indexed_batched_fft\|the production route" src/tasks/strongstrong/pic_cuda.jl`;
`sed -n '1047,1052p' src/tasks/strongstrong/interface.jl` → "On CUDA,
`:quadratic` runs on the sequential non-async route **and on the batched-FFT
routes — including the production indexed wavefront**".

### LEAD U26-3 [Major, confidence high] docs/README.md (theory index entries for aperture and RF cavity)
Claim: the index describes two implemented subsystems as unimplemented —
"Design only; no implementation yet" (`aperture_and_particle_loss.md`) and
"Design only; not implemented" (`rf_cavity_and_reference_energy.md`).
Mechanism: `ApertureSpec`, `LossRecord`, `loss_records`, `loss_counts`,
`loss_summary`, `write_loss_record`, `read_loss_record` are all exported,
documented, and routed by `docs/public_api.md`'s own "Particle Loss" section;
`ThinRFCavitySpec` is exported, carries a full `@element_spec` block for kind
`:thin_rf_cavity`, and appears in the generated `docs/registry_snapshot.md`.
AGENTS.md makes `docs/README.md` the index every agent orients from, so an agent
asked to "add an aperture" or "add an RF cavity" is told from the index that
neither exists.
Repro: `julia --startup-file=no --project=. -e 'include("src/Octopus.jl"); using .Octopus; println(isdefined(Octopus,:ApertureSpec), " ", isdefined(Octopus,:ThinRFCavitySpec))'`
→ `true true`; `grep -c thin_rf_cavity docs/registry_snapshot.md` → nonzero.

### LEAD U26-4 [Major, confidence med] docs/theory/coherent_beam_beam_modes.md §2
Claim: §2 states the equilibrium potential is "normalized to $\hat V_0''(0)=1$ so
that the small-amplitude incoherent shift is exactly $\xi$", gives $u(0)=1$, and
gives the incoherent continuum as $[Q_0, Q_0+\xi]$. The implementing script now
asserts the opposite.
Mechanism: `validation/coherent_mode_vlasov_theory.jl` self-check 4 documents
that normalizing by the reduction's own averaged curvature is *circular* — "it
forces u(0)=1 whatever the kernel does" — and that after the fix `u(0)` "must
therefore be BELOW 1 and aspect-dependent; a value of exactly 1 means the
circular normalization has returned". The check's exact target is
`u0_exact = (1+r)/(1+√2 r)`, i.e. 0.8284 at r=1. The note also lists only three
structural checks where the script now has five, and never mentions check 4 —
the one that changed the physics — even though §3's footnote credits "the
normalization fix" for regenerating its table. So the note's normalization
statement, its `u(0)=1`, and its continuum edge are all pre-fix text.
Repro: `grep -n "u0_exact" validation/coherent_mode_vlasov_theory.jl` →
`u0_exact = (1.0 + r) / (1.0 + sqrt(2.0) * r)`; evaluate at r=1 → 0.828427.

### LEAD U26-5 [Minor, confidence med] docs/theory/coherent_beam_beam_modes.md §4 (EIC eigen-solve table)
Claim: the x-plane continuum edges quoted in the theory table are set by the
grid artifact the note's own §3 footnote disowns, and the note quotes two
different e-continua for the same plane two tables apart.
Mechanism: the script computes `e_band = (Q_e, Q_e + xi_e * maximum(res.u1))`.
For the x plane the averaged (vertical) plane gives s ≈ 0.12 in witness-sigma
units — squarely in the flat regime where §3's footnote records "the radial
detuning u(J) exceeds its physical maximum of 1 (measured max u ≈ 1.8 … growing
to ≈ 2.9 … i.e. an artifact)". Back-solving the note's own numbers,
(0.2549 − 0.08)/0.088211 = 1.982 and (0.2509 − 0.228)/0.009368 = 2.44 — both
u_max well above 1. Under the physical band $[Q_e, Q_e+\xi_e] = [0.080, 0.168]$
— which is exactly what the note's *next* table uses for the same plane — the
top x-plane mode at 0.25488 lies far outside both continua, reversing §4's
"none (top mode at the e-continuum edge)" conclusion for x. §4's correction box
already reversed the y-plane conclusion for the same underlying reason; the
x-plane half was not revisited.
Repro: `grep -n "e_band = " validation/coherent_mode_vlasov_theory.jl`; then
`awk -F'\t' '$1=="x"{print $6}' result/eic_coherent_modes.tsv | tail -1` →
0.25488421957292384, and (0.25488 − 0.08)/0.08821 = 1.982 > 1.

### LEAD U26-6 [Minor, confidence high] docs/theory/pic_free_space_kernels.md §3.5
Claim: §3.4's correction block states plainly that at grid 128 `:lattice` "comes
out at par with `:integrated` (1.18e-3 vs 1.16e-3) rather than the 1.48x better
claimed above", but §3.5 restates the superseded figures as current.
Mechanism: §3.5's ρ-quantization table still carries "| exact | 1.348e-2 |
**1.48x better** |" at the grid-128 production point, and its Recommendation
still reads "1.30x lower systematic field error for 1.74x runtime". Neither
carries a pointer to the correction one section above. The briefed question —
"is the note honest about that now?" — answers *half yes*: §3.4 is honest,
§3.5 is not.
Repro: read §3.4's "**Still open:**" block against §3.5's ρ table and
Recommendation; both quote the grid-128 production point.

### LEAD U26-7 [Minor, confidence high] docs/theory/pic_free_space_kernels.md §3.4 correction table vs src/tasks/strongstrong/pic_cpu.jl
Claim: the note and the source carry the same re-measurement and disagree on the
round-beam row; the source's value is the one that cannot be right.
Mechanism: the note's "after" column gives round-64 = 1.74e-3 (identical to
"before", 1.81x worse); the source comment's "aspect-aware" column gives
1.48e-3. At ρ = 1, `_pic_lattice_box_mult(1.0)` returns
`(clamp(round(8·max(1,1)),8,64), clamp(round(8·max(1,1)),8,64)) = (8,8)`, which is
exactly the flat mult-8 box, so the two columns *must* be bit-identical at round
— the note's row is self-consistent, the source comment's is not. The 5:1 and
11:1 rows also drift in the last digit (1.93e-3 vs 1.92e-3; 2.63e-3 vs 2.64e-3).
Repro: `sed -n '1630,1640p' src/tasks/strongstrong/pic_cpu.jl` (the
`aspect :integrated :lattice(mult 8) :lattice(aspect-aware)` table) against the
note's §3.4 correction table; and `_pic_lattice_box_mult(1.0) == (8,8)`.

### LEAD U26-8 [Minor, confidence high] docs/theory/misalignment_and_patch_maps.md §6a
Claim: §6a names two `misalign_convention` values that do not exist.
Mechanism: the paragraph reads "Octopus therefore exposes
`misalign_convention`, defaulting to `:center` (Bmad, and what survey data
means) with `:entrance` available to reproduce MAD-X", and the *measured* table
immediately below is captioned "with `misalign_convention = :entrance`". The
implemented values are `:bmad` and `:madx` — as the same section says two
subsections later, and as every `@element_spec` `construction_help` string says.
A reader following §6a's first statement gets an `ArgumentError`.
Repro: `grep -n "conv in (:bmad, :madx)" src/elements/misalignment.jl` → line 286,
error message "misalign_convention must be :bmad or :madx".

### LEAD U26-9 [Minor, confidence high] docs/theory/slice_longitudinal_interpolation.md §10.5 + §12
Claim: the note advertises `grid_extent = :sigma` as complementary to
`interaction_grid = :node`; the constructor rejects the combination.
Mechanism: §10.5 says "`:sigma` addresses a *different* breaker than `:node`:
node indexing removes the slice-boundary jump exactly but does nothing about
**turn-to-turn** mesh jitter … `:sigma` cuts that by 5×", and §12 recommends
`:node` for dynamics work — the natural reading is "enable both". But
`_pic_validate` throws unless `interaction_grid === :slice_pair ||
grid_extent === :extrema`, because `:node` sizes its mesh from per-node extrema
and would silently ignore the estimator. The note never records the exclusion.
Repro: `julia --startup-file=no --project=. -e 'include("src/Octopus.jl"); using .Octopus; PICPoissonSolver(interaction_grid=:node, grid_extent=:sigma)'`
→ ArgumentError "grid_extent = :sigma is not implemented for interaction_grid = :node".

### LEAD U26-10 [Low, confidence high] docs/theory/slice_longitudinal_interpolation.md (file:line citations)
Claim: nearly every `file:line` pointer in the note has rotted, and the note
leans on them for its implementation-level argument.
Mechanism: `pic_cpu.jl:938` (the `Kz += w * (phiL - phiR)` line the whole of §4
rests on) is now line 1884; `_pic_interaction_grids` is cited at
`pic_cpu.jl:315` and is defined at 1057; `pic_cpu.jl:54-57` (the
`param = (lb=…, center=…, rb=…)` construction) and `pic_cpu.jl:242-244` (the
per-particle drifted position) now point at node-cache and error-message code;
`interface.jl:487`/`494` (`center_position` default and validation) point at
`_nonfinite_coordinate_error`; `slicing.jl:337-344` points at equal-width
binning; `interface.jl:768-775` points at the `GaussianPoissonSolver` docstring.
Only `pic_cpu.jl:42-43` still resolves.
Repro: `grep -n "phiL\[ii, jj\] - phiR\[ii, jj\]" src/tasks/strongstrong/pic_cpu.jl`
→ 1884, not 938.

### LEAD U26-11 [Low, confidence high] docs/theory/solenoid.md §14.2
Claim: "Contract now 41 cases"; the committed PTC reference table carries 55.
Repro: `grep -v '^#' validation/reference/ptc_madx_5.03.06.tsv | awk -F'\t' 'NR>1{print $1}' | sort -u | wc -l`
→ 55.

### LEAD U26-12 [Low, confidence high] AGENTS.md "Source Ownership" (out-of-hypothesis; task item f)
Claim: the directory list names 7 of the 13 directories under `src/`.
Mechanism: AGENTS.md lists `src/elements/`, `src/track/`, `src/policies/`,
`src/contracts/`, `src/analysis/`, `src/tasks/`, `src/constants/`. The tree also
has `src/beam/`, `src/examples/`, `src/knobs/`, `src/knowledge/`, `src/math/`,
`src/registry/`. `src/knobs/` in particular carries an entire public API surface
and its own indexed design note (`docs/knob_control.md`, which cites
`src/knobs/Knobs.jl` and `src/knobs/symbolic.jl`), so an agent orienting from
AGENTS.md alone has no ownership rule for six directories including the knob
subsystem.
Repro: `ls -d src/*/ | wc -l` → 13; `grep -c '^- \`src/' AGENTS.md` → 7.
(The single-module claim itself is true: `grep -c '^module ' src/**/*.jl` → 1.)

### LEAD U26-13 [Low, confidence med] docs/theory/rf_cavity_and_reference_energy.md §6
Claim: the note reads as a pending proposal for an element that is implemented,
and its quoted signature is stale.
Mechanism: §6 is headed "**Scope A — `ThinRFCavitySpec`, constant reference
energy. Do this now.**" and §9's open questions are phrased prospectively, while
the element exists, is exported, is metadata-registered and appears in the
registry snapshot. Every other implemented note in `docs/theory/` carries an
explicit "**Implemented**" marker (`beam_line_composition.md`,
`misalignment_and_patch_maps.md`, `solenoid.md`), so the absence reads as a
status claim. The signature quoted, `ThinRFCavitySpec(frequency; voltage, e0,
mc2, phase=0, L=0)`, omits `charge` and the second accepted form
(`strength, beta0, gamma0`). Same root cause as U26-3's RF half.
Repro: `grep -n "^function ThinRFCavitySpec" src/elements/rf_cavity.jl`; the
constructor takes `strength, beta0, gamma0, voltage, e0, mc2, charge, phase, L,
tracking_method`.

### LEAD U26-14 [Low/style, confidence high] docs/theory/spectral_sine_poisson_solver.md §2
Claim: "$\sin(\alpha_l\cdot 0)=\sin(l\pi)=0$" conflates the two edges — the
first equality is only true because both sides are zero, not because
$\alpha_l\cdot 0 = l\pi$. Style; the mathematics is right.

### LEAD U26-15 [Low/style, confidence high] docs/theory/beam_line_composition.md §5, §7
Claim: nomenclature drift — the note recommends `find(line, sel)` throughout
(§5, §5a, §7); the implementation exports `find_entries`. A design report is
allowed to drift from what shipped, but the note carries no marker and README
calls it "**Implemented**".
Repro: `grep -n "^export" src/elements/beam_line.jl` → `find_entries`, no `find`.

## Note-to-implementation consistency table

| note | implementing / cited file | verdict |
|---|---|---|
| `aperture_and_particle_loss.md` | `src/elements/aperture.jl` | **sound** as a note; README status wrong (U26-3) |
| `beam_beam_longitudinal_kick.md` | `src/elements/strong_beam.jl`, `paper/*` | **clean** — every boxed result re-derived |
| `beam_line_composition.md` | `src/elements/beam_line.jl` | sound; `find`→`find_entries` drift (U26-15) |
| `bpm_measurement_model.md` | `src/tasks/BPMObserver.jl` | **clean** — model matches term for term |
| `coherent_beam_beam_modes.md` | `validation/coherent_mode_*.jl`, `Contracts.jl` | **defects**: U26-4, U26-5; tables match the committed TSVs |
| `gaussian_longitudinal_slicing.md` | `src/elements/strong_beam.jl` | **defect**: U26-1; all five Furman rules re-derived correct |
| `gaussian_subtracted_pic_solver.md` | `src/tasks/strongstrong/gaussian_pic.jl` | **clean** — all `erf` moment algebra and option defaults verified |
| `lattice_hamiltonian_and_conventions.md` | `src/track/longitudinal.jl`, `src/elements/lattice_magnets.jl`, `Contracts.jl` | **clean** — conventions, recursion, Yoshida-4 all verified |
| `misalignment_and_patch_maps.md` | `src/elements/{misalignment,patch,ref_tilt}.jl` | **defect**: U26-8; W-composition conventions correct |
| `near_round_bassetti_erskine_switch.md` | `src/elements/strong_beam.jl`, `src/track/strong_beam_track.jl` | **clean** — series cross-checked against exact core gradient to O(η³); every threshold reproduced |
| `node_interaction_grid.md` | `src/tasks/strongstrong/pic_cpu.jl` | sound; both referenced validation scripts exist |
| `pic_free_space_kernels.md` | `src/tasks/strongstrong/{pic_cpu,interface}.jl` | **defects**: U26-6, U26-7; kernels and constants verified |
| `rf_cavity_and_reference_energy.md` | `src/elements/rf_cavity.jl` | **defect**: U26-13; F16 correction is present and accurate |
| `slice_longitudinal_interpolation.md` | `src/tasks/strongstrong/{interface,pic_cpu,pic_cuda}.jl` | **defects**: U26-2, U26-9, U26-10; all interpolation algebra correct |
| `solenoid.md` | `src/elements/solenoid.jl`, `Contracts.jl` | sound; stale case count (U26-11) |
| `spectral_sine_poisson_solver.md` | `src/tasks/strongstrong/spectral.jl` | **clean** — `-2π`/`+4π` scales and `min_domain_halfwidth` verified |
| `weak_strong_6d_model.md` | `src/elements/strong_beam.jl` (via `validation/README.md`) | **clean** — every conditional-Gaussian formula re-derived |
| `knob_control.md` | `src/knobs/{Knobs,symbolic}.jl` | **clean** — every named symbol exists |
| `current_runtime.md` | whole tree | **clean** — see clean list |
| `public_api.md` | whole tree | **clean** — 114/114 symbols resolve |
| `registry_snapshot.md` | generated | **clean** — byte-identical |

## Orphan numbers (quoted figures with no committed harness)

Reproducible (harness named and committed): `coherent_beam_beam_modes.md` (all
tables; the three committed `result/*.tsv` match the quoted digits),
`gaussian_longitudinal_slicing.md` §4/§5/§5.1/§7.1/§10
(`validation/gaussian_slicing_convergence.jl`),
`gaussian_subtracted_pic_solver.md` §9
(`gaussian_pic_field_validation.jl`, `gaussian_pic_bigaussian_validation.jl`),
`spectral_sine_poisson_solver.md` §16 (`spectral_poisson_field_validation.jl`),
`slice_longitudinal_interpolation.md` §10.1–§10.5, §11
(`slice_longitudinal_zscan.jl`, `pic_grid_extent_stability.jl`,
`slice_interpolation_emittance_growth.jl`, `pic_option_consistency.jl`),
`misalignment_and_patch_maps.md` §6a/6b (PTC reference table +
`PTCConsistencyContract`).

Orphans — no committed harness can reproduce these:

1. `pic_free_space_kernels.md` §2, gradient table (3.03e-3/1.83e-3 = 1.65x;
   7.50e-4/4.66e-4 = 1.61x; 2.03e-4/1.69e-4 = 1.20x). No committed script sweeps
   `field_derivative` for field accuracy; `test/runtests.jl:6105` only checks the
   flag is consumed.
2. `pic_free_space_kernels.md` §3.2, kernel-sensitivity table (48²–256² × 4
   aspect ratios). No committed `green_type` accuracy sweep exists —
   `validation/pic_gaussian_field_validation.jl` hardcodes
   `green_type=:integrated` at line 80 with no env override.
3. `pic_free_space_kernels.md` §3.3, the VGF table. VGF is not implemented; the
   note is explicit that it was rejected, so this is unreproducible by
   construction rather than by omission.
4. `pic_free_space_kernels.md` §3.4, the main measured table (7.79e-3 … 5.13e-2)
   — the note's own correction says "no harness for it was ever committed".
   **This is the recorded lesson-6 orphan; it is still an orphan.**
5. `pic_free_space_kernels.md` §3.4 correction table (the "re-measured with that
   documented harness" `:lattice` before/after columns). The named harness
   cannot produce the `:lattice` columns as committed (item 2), so this
   *replacement* for the orphan table is itself unreproducible.
6. `pic_free_space_kernels.md` §3.4 lattice asymptotics (a(1,0)=0.2499997616,
   C=1.6162246, residual 4.47–4.54e-2) and validity-window sweep
   (6.2e-3 / 7.1e-4 / 3.5e-3 at r=4/16/48, M=1024). No harness.
7. `pic_free_space_kernels.md` §3.5 ρ-quantization table, CUDA cost table
   (0.191/0.249; 0.253/0.440), the 645 MB / 306-table figure and the 6.8x cache
   thrash. Duplicated verbatim in `pic_cpu.jl` comments — that is provenance,
   not reproduction.
8. `slice_longitudinal_interpolation.md` §7.5 CUDA route table
   (0.3201 / 0.7940 / 0.9190 s/turn). No named harness.
9. `node_interaction_grid.md` §5, the CUDA interaction-stage figures
   (0.3912 s against 0.3110 s, "~26% excess"). No named harness.
10. `gaussian_subtracted_pic_solver.md` §7.5 (brute-force quadrature table and
    the end-to-end coupled/uncoupled table) and §9's CPU cost table
    (2.8e-5 … 2.68e-2 s). No named harness.
11. `spectral_sine_poisson_solver.md` §18 history sequence
    (+4.9e-2, +2.3e-3, −1.3e-2, −1.9e-2 → +4.1e-2, +9.9e-3, +1.9e-3, −5.4e-5).
    Pre-fix numbers; unreproducible from current code by construction.
12. `gaussian_longitudinal_slicing.md` §6.1 virtual-drift group-structure table
    (round trip / T-dependence / group property / p_z change residuals). No
    named harness.
13. `solenoid.md` §6.1 verification table. The note is honest that it came from
    "a throwaway reference implementation"; not committed.
14. `lattice_hamiltonian_and_conventions.md` §4.4, §5.1, §5.3, §6.2, §6.3.1,
    §6.4 per-map residuals (2.6e-23 … 9e-19 … 1.5e-18 vs 1.3e-5, etc.). The PTC
    contract covers end-to-end agreement but none of these intermediate
    residuals; no harness.
15. `bpm_measurement_model.md` §2 marker-map table. Trivially reproducible but
    no committed script.

Answer to the briefed open item: **`:lattice` at grid 128 — the note is honest
in §3.4 and not honest in §3.5.** See LEAD U26-6.

## README index diff (both directions)

Tracked files under `docs/`: 74 (`git ls-files docs/ | wc -l`).
Distinct link targets in `docs/README.md`: 44 (42 files + 2 directories).

**Index entries pointing at files that do not exist: NONE.** All 44 targets
resolve (`while read p; do [ -e "$p" ] || echo MISSING; done`). A whole-tree
sweep of every markdown link in `docs/*.md` and `docs/theory/*.md` also found
zero broken intra-docs links.

**Documents missing from the index: none that AGENTS.md's rule reaches.**
74 − 42 = 32 unlinked tracked files, accounted for exactly:
- `docs/README.md` itself (the index);
- 21 files under `docs/history/comprehensive_audit_2026_08_05_unit_reports/`;
- 10 files under `docs/history/comprehensive_audit_2026_08_05_b_unit_reports/`
  (3 `.md`, 6 `.jl`, 1 `.txt`).
Both unit-report directories are indexed *as directories*, which is the
established convention. The `_b` directory is the one the brief said to ignore.
`.ipynb_checkpoints/` copies under `docs/`, `docs/theory/` and `docs/history/`
are gitignored and correctly not indexed.

Not an index defect but worth recording: the index's *descriptions* of two
entries are wrong (LEAD U26-3), which is the failure the index exists to
prevent.

## Registry snapshot byte-diff verdict

**Clean — byte-identical.** Regenerated to
`scratchpad/audit/registry_snapshot_regen.md` via
`Octopus.write_registry_snapshot(outpath)` and compared:

```
diff docs/registry_snapshot.md <regen>   → exit 0
cmp  docs/registry_snapshot.md <regen>   → exit 0
md5  8b7e8f167adf4927a9088b492b0119c6    (both)
```

No drift. AGENTS.md's "Regenerate … after public architecture objects change"
rule is currently satisfied.

## Unresolved-symbol list

**Empty.** 114 symbols were extracted mechanically from `docs/public_api.md`
(every `?Symbol` entry plus every leading call in a code fence) and a further
53 named in prose or in `current_runtime.md`/`knob_control.md` were checked by
hand. Every one is `isdefined`, every one is in `names(Octopus)`, and every one
has a real docstring — checked by asking `Base.Docs.doc(Base.Docs.Binding(...))`
and rejecting the "No documentation found" fallback, per the recorded Julia 1.12
interposed-comment gotcha, rather than by reading source.

One near-miss worth recording: `total_length` is defined and documented but
**not exported**. It is named in `rf_cavity_and_reference_energy.md` §6 ("The
line knows C — `total_length` already exists") but is *not* in
`public_api.md`'s `?` list, so this is not a `public_api.md` defect.

Full table: `scratchpad/audit/probe1.log`, `scratchpad/audit/probe2.log`.

## Clean list, with the evidence

- **`docs/registry_snapshot.md`** — regenerated and byte-compared (md5 above).
- **`docs/public_api.md`** — 114/114 symbols defined + exported + documented,
  by Julia query.
- **`docs/README.md` link graph** — 44/44 targets resolve; zero broken links
  anywhere in `docs/*.md` + `docs/theory/*.md`; index coverage complete.
- **`docs/current_runtime.md`** — verified live, not read: `Phase6DRep` fields
  `(x,px,y,py,z,pz)`; `TrackingContext` `isbitstype` with
  `turn::Int64, seed::UInt64, rng_method::UInt8`; `LorentzBoostSpec` and
  `RevLorentzBoostSpec` both compile with `NonSymplectic6DMap()`;
  `PICPoissonSolver` defaults `green_cache=:slice_pair`, `batch_mode=:wavefront`,
  `cuda_indexed_wavefront=true`, `slice_pair_green_min_ratio=0.5`,
  `slice_pair_green_growth=0.25`, `luminosity_deposit_method=nothing`,
  `luminosity_grid=nothing`; `GaussianPoissonSolver` `batch_mode=:wavefront`,
  `include_sigma_xy=false`; `CUDAExecutionPolicy().launch ==
  CUDALaunchConfig(256, :auto)`; `CPUThreadsExecutionPolicy(:auto)`;
  the CUDA reclaim policy is literally `(check_every=16, threshold=0.12)`;
  `method=:grid_free` is documented and validated CPU-only;
  `test/nightly_suite.sh` exists, carries the `47 2 * * *` crontab line, keeps
  14 logs and writes the `date/commit/testsets/verdict/exit` row it claims.
- **`docs/knob_control.md`** — every named entry point exists
  (`list_knobs`, `knob_expression`, `knob_to_expr`, `knob_epoch`,
  `reset_knobs!`, `knob_symbolics_available`, plus the whole `?` list);
  `docs/registry_snapshot.md` does contain the "## Knob Control" section the
  note points at.
- **`weak_strong_6d_model.md`** — `A(u)=A_0+u(B_0+B_0^T)+u^2Q_0`, `A_u`,
  the conditional mean/covariance, `dμ/dz = ζ + η σ_zpz/σ_z²`,
  `Σ_{w|z} = Σ_β + ηη^T(σ_pz² − σ_zpz²/σ_z²)` and the finite-bin term
  `Σ_wz Σ_zw Var(z|bin)/Σ_zz²` all re-derived independently and correct.
- **`beam_beam_longitudinal_kick.md`** — re-derived: `S=(z−z_*)/2` and
  `u_z=−1/2`; the four Poisson brackets of §3; `Δp_z^CP = ½F·C_u + ¼H_U:A_u`;
  the whole principal-axis machinery (`θ_u`, `R_u=RJθ_u`,
  `R^TA_uR = Λ_u + θ_u(JΛ−ΛJ)`, `∂U/∂θ = (λ₁−λ₂)Û₁₂`); the paraxial slingshot
  and its expansion; the chromatic flow (`P⁻=√(P²−q/2)`, the `S/P` invariant,
  `z⁻=z+2SΦ`) and its slingshot; the exact-drift `S`, `G₃`, `H_r=q/2P` and the
  vanishing of the slingshot at `q⁺=q⁻`; the uncoupled-Twiss limit
  `dσ_x²/du = −2ε(α+γS)`. Code cross-checks: `pz -= 0.25*(px²+py²)` and
  `pz += 0.25*(Hxx a_u + 2Hxy b_u + Hyy d_u)` in `strong_beam.jl` carry the
  note's ¼; `:hirata` is the default and both
  `UnsafeVirtualDrift(:paraxial_frozen_longitudinal)` /
  `(:chromatic_frozen_energy)` exist exactly as §7 names them.
- **`near_round_bassetti_erskine_switch.md`** — the strongest note in the tree.
  `η = 2δ_σ/(1+δ_σ²)` and its inverse verified; `M_0=(1−e^{−q})/q`, the series
  and the upward recurrence verified; the q=0 coefficients
  `C_{1,j}=∓½, C_{2,j}=½, C_{3,j}=∓⅜` verified **and** independently confirmed
  by expanding the exact core gradient `2/(σ₁(σ₁+σ₂))` in η, which reproduces
  `1 − η/2 + η²/2 − 3η³/8` term for term; `η_* = (8C_BE ε/3)^{1/4}` reproduces
  all four boundary values (4.4121e-4 / 2.2061e-4 Float64; 3.9934e-2 /
  1.9967e-2 Float32) and both estimated response errors (3.2209e-11 /
  2.3881e-5) to the printed digits; `ρ⁷ ≤ ε/√η` follows from the stated orders;
  `J^{(x)}_{10}` re-derived from `G_x` and matches the code's `j10` exactly.
  Code: `_near_round_conditioning_factor` = 64.0 / 8.0f0, `outer =
  sqrt(sqrt((8/3)·conditioning·eps(T)))`, `q ≤ 2` with 17/25 series terms,
  `_use_elliptic_near_axis` comparing `rho2^3·√rho2` to `eps/√η`. One apparent
  factor mismatch (`0.625`/`0.75` in `_elliptic_gaussian_axis_component`) was
  chased and **is not a defect**: that line is `∂(x·scale)/∂x`, and
  differentiating the note's `K_x` gives exactly 0.625 and 0.75.
  `src/track/strong_beam_track.jl` (the "CUDA counterpart") exists.
- **`gaussian_subtracted_pic_solver.md`** — `m_0,m_1,m_2` re-derived; the CIC
  node value and the full TSC node value re-derived from `W_2`'s three branches;
  the `c_k` recursion, the `W_k` CIC combination and the `M^{(1)},M^{(2)}`
  binomial shifts re-derived; `g'=∫GW'`, `g''=∫GW''` and the CIC distributional
  `W''` re-derived; `η=1−r_xy²`, `η>√ε ⟺ s/σ_y>ε^{1/4}` with 1.22e-4 (Float64)
  and 1.86e-2 (Float32) confirmed numerically; the §7.5 expansion parameter
  `½r²/(1−r²)` reproduces 0.005 / 0.05 / 0.28; the §6 `erfc(m/√2)` row
  reproduces 2.7e-3 / 6.3e-5 / 5.7e-7 / 2.0e-9. Code:
  `margin_sigma=5.0, neutralize=true, coupling_tol=Inf` as documented.
- **`lattice_hamiltonian_and_conventions.md`** — all four longitudinal
  conventions and their generating functions re-derived (`z₂=β₀z₁`, `z₄=βz₁`,
  `z₃=βz₁−s(β/β₀−1)`, `dδ/dp_t=1/β`); the `â_s` normalization checked against
  `B_y+iB_x`; `λ = K₂/2` and the sign correction against the MAD-X thin-sextupole
  kick; the curved-frame PDE derived from the curvilinear curl; `Ψ(x,0)`, the
  exact recursion, and **all five** of `Ψ_0,Ψ_2,Ψ_4,Ψ_6,Ψ_8` for the curved
  quadrupole reproduced independently, including the dipole termination; the
  Yoshida-4 coefficients (0.675604 / −0.175604 / 1.351207 / −1.702414)
  reproduced from `a = 1−2^{1/3}`. Code: `TIME_ENERGY`, `SIGMA_PSIGMA`,
  `PATHLENGTH_DELTA`, `TIME_DELTA` singletons carry the note's numbering and
  definitions verbatim.
- **`solenoid.md`** — `k_s/2` in the potential vs `k_s` in the momentum
  equation, `κ = 2k/p_s = k_s/p_s`, the Larmor half-angle factorization of
  `(1−e^{−iθ})/(iκ)`, the `L=0` identity, the curved-frame gauge
  `g(x)=(2/h)ln(1+hx)−x` and its field check `k g'(x)+k = k_s/(1+hx)` all
  re-derived correct. Code: `Solenoid{M,T,N,CURVED,MC,NC}` carries curvature as
  a type parameter exactly as §15.4a claims, with the implicit-midpoint
  integrator on the curved branch.
- **`bpm_measurement_model.md`** — `bpm_reading` is
  `G·R(tilt)·[(x̄,ȳ)−d] + b + σξ` term for term, with the rotation
  `[[c,s],[−s,c]]` matching the note's AT/Bmad orientation claim, and the noise
  drawn from `octopus_normal(ctx.seed, ctx.rng_method, ctx.turn, bpm.rng_id,
  occurrence, component)` — reproducible and chunk-invariant as §5 requires.
- **`spectral_sine_poisson_solver.md`** — the eigenbasis, orthogonality, the
  `4/(ab)` coefficient, the mode division, the kick signs, and the DST-I
  collocation all re-derived; `K_BE = −4πE` verified from
  `φ=(1/2π)ln r`; both derived scales confirmed in code as
  `_SPECTRAL_FIELD_SCALE_GRID = -2π` and `_SPECTRAL_FIELD_SCALE_FREE = 4π`;
  `min_domain_halfwidth` default 0.0 as documented (and
  `min_transverse_extent=(0.0,0.0)` for the PIC note's counterpart).
- **`node_interaction_grid.md`** — internally consistent with its companion;
  `validation/slice_interpolation_emittance_growth.jl` and
  `validation/pic_option_consistency.jl` both exist as referenced.
- **`slice_longitudinal_interpolation.md` mathematics** — despite three status
  defects, every formula checks: the linear-interpolation `Δ²/32` envelope, the
  quadratic Lagrange basis and its unit sum, the `Δp_z` weight set
  `(4t−3, 4−8t, 4t−1)` summing to zero and collapsing to
  `2k_bb(φ_L−φ_R)/Δ` at `t=½`, the `Δ³/998` constant from `h³/(9√3)` at
  `h=Δ/4`, the overshoot `−1/8` at `t=3/4` and `Σ|L_i| = 1.25`, and the
  endpoint nodal error `h²g'''/3`. `grid_extent` accepts exactly
  `(:extrema, :sigma)` — confirming §10.5's claim that `:quantile` was
  implemented, measured and removed.
- **AGENTS.md**, verified true: one public module only (`grep -c '^module '` → 1);
  `docs/theory/` and `docs/history/` hold what it says; `docs/todo.md`,
  `docs/comprehensive_audit.md`, `docs/README.md`, `docs/{public_api,
  registry_snapshot,current_runtime}.md` all exist; `validation/README.md`
  exists; `validation/tracking_backend_consistency.jl` exists;
  `test/examples/strong_strong_tracking.jl` exists and cites its clean
  counterpart; `element_help`, `summarize_registry`, `validate_element_metadata`,
  `write_registry_snapshot`, `validate_configuration_metadata`,
  `PublicConfigurationEffectivenessContract`, `PlaceholderPolicy`,
  `PlaceholderAnalysis`, `friendly_constructor` (not `friendly`) all exist and
  behave as described. The one incomplete claim is the directory list
  (LEAD U26-12).

## Unchecked, and why

- **The full-suite gate** (`julia --project=. --threads=4 -e 'using Pkg;
  Pkg.test(julia_args=["--threads=4"])'`). Not run: ~19 audit agents share this
  box and the brief asks for correctness probes over timing. Nothing in this
  region's leads depends on it.
- **Every CUDA-specific runtime claim** in `current_runtime.md` and in the PIC /
  spectral / GaussianPIC notes (stream/event ordering, NVTX ranges, the quoted
  CPU/CUDA parity residuals, device memory figures). Not executed; no GPU probe
  was run this session. The *structural* claims behind U26-2 were settled by
  reading `pic_cuda.jl` and the solver docstring, not by running a kernel.
- **Re-measurement of any performance table.** The orphan list is derived from
  harness existence and from the notes' own provenance statements, not from
  re-running the measurements. Where a number was checkable by arithmetic
  (`near_round`, `gaussian_longitudinal_slicing` §4, the Yokoya TSVs) it was.
- **`docs/todo.md`, `docs/history/`, `docs/comprehensive_audit.md`** — excluded
  by the brief. `docs/todo.md` was read only at two greps, to settle U26-1's
  cross-reference.
- **Suspected cross-file seam, noted and stopped at** (auditor's call, not
  mine): U26-7 is a disagreement between a theory note and a source *comment*
  about the same measurement. The source comment is outside my region; I report
  the disagreement and which side the box-multiplier arithmetic favours, and
  stop.
