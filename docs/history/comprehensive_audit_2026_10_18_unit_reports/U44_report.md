# U44: validation: field, luminosity, grid, noise floor, option consistency, kick decomposition, spectral comparison

Tree: `/cfs/ad/dxu/Library/Julia/Octopus` at 24e8683, read-only. Nothing in the repository was
modified; `git status --porcelain` was empty after every probe (the reproductions write only to the
git-ignored `result/`, which is where the scripts hardcode their output). Scratch:
`result/comprehensive_audit_2026_10_18/probes/U44/` (probe scripts, every log, and `result_outputs/`
with copies of every file the reproductions wrote).

## Region

All eleven files read line by line, 2935 lines total:

| file | lines |
|---|---:|
| `validation/pic_gaussian_field_validation.jl` | 1-455 |
| `validation/spectral_poisson_field_validation.jl` | 1-329 |
| `validation/gaussian_pic_field_validation.jl` | 1-250 |
| `validation/gaussian_pic_bigaussian_validation.jl` | 1-209 |
| `validation/pic_gaussian_luminosity_validation.jl` | 1-185 |
| `validation/pic_grid_extent_stability.jl` | 1-186 |
| `validation/noise_floor_meshswap.jl` | 1-263 |
| `validation/pic_option_consistency.jl` | 1-277 |
| `validation/pic_option_consistency_summary.jl` | 1-190 |
| `validation/kick_decomposition.jl` | 1-302 |
| `validation/strong_strong_spectral_comparison.jl` | 1-289 |

Hypotheses briefed: (1) instrument validation by injection; enforced vs print-only thresholds; header
drift (documented commands run as written); (2) options swept are options read (receipts), the
silent-degradation class; (3) GPU legs run where CUDA is required, skipped visibly otherwise.

## Provenance

READ (every line): the eleven region files above. READ for comparison (targeted ranges, not whole
files): `src/tasks/strongstrong/pic_cpu.jl` 1180-1215, 1833-1853, 1926-1990, 2159-2192, 2261-2330,
2889-2940, 2975-3070; `src/tasks/strongstrong/gaussian_pic.jl` 200-230; `src/tasks/strongstrong/spectral.jl`
63-64, 80-110, 529, 760-800, 1023, 1150-1215; `src/tasks/strongstrong/interface.jl` 891-912, 1125-1230,
1650-1656; `src/policies/Policies.jl` 1362; `src/beam/Beam.jl` constructors 572/599/618 and
`beam_statistics` 812-861; `src/tasks/RunArtifact.jl` (grep only); `test/runtests.jl` 28276-28325;
`validation/README.md` 40-200, 640-680, 920-950, 1125-1190, 1920-1939; `docs/guides/examples_and_validation.md`
1-45; `docs/theory/gaussian_subtracted_pic_solver.md` 650-750; `docs/theory/pic_free_space_kernels.md`
315-330, 370-382; `docs/theory/spectral_sine_poisson_solver.md` 432-447, 520-545;
`docs/history/poisson_solver_review_2026_07_24.md` 909-937; `examples/strong_strong_tracking.jl` 79-120,
120-194 (grep), 195-330; previous `U23_report.md` 80-260, 340-420, 462-781 (lead list, instrument,
threshold, reproduction, clean, unchecked sections); `U25_report.md` lead titles (grep).

EXECUTED (all from the scratch dir; `julia --project=<tree> --threads=4`; logs under `probes/U44/`):

| probe | command (relative to the tree) | result |
|---|---|---|
| `lum_default.log` | `validation/pic_gaussian_luminosity_validation.jl` at committed defaults (3 particle counts x 6 cases x 2 methods x 4 grids x 3 paddings) | exit 0; `maximum_production_interface_relative_error = 1.035e-14` (gate 1e-12 passed); `maximum_relative_error = 9.076e-2`; CIC/TSC finest-grid max 3.84e-4 / 5.77e-4 |
| `lum_inject.log` (`probe_lum_inject.jl`) | the script's quadrature vs production `_pic_luminosity`, current full-extent sum and the pre-U5-8 truncated sum, identical_edge_probe and offset_flat, CIC/TSC, grids 32/128 | current: all <= 1.5e-15 PASS; truncated: FAIL only identical_edge_probe/TSC at 5.067e-9 (32) and 8.876e-8 (128), the magnitudes U23 b5 recorded |
| `spectral_default.log` | `validation/spectral_poisson_field_validation.jl` as documented | exit 0; domain scaling 8.799e-2/2.168e-2/4.001e-3/1.325e-3/1.020e-3; thin-grid 8.071e-2/3.386e-2/1.341e-2/7.767e-3; main table round on-mesh 2.660e-3/1.390e-2, PIC 1.643e-3/1.260e-2; 5:1 4.457e-3/2.327e-2, PIC 2.198e-3/2.843e-2; 25:1 6.846e-3/4.157e-2, PIC 9.408e-3/1.408e-1 |
| `spectral_copy.log` (`probe_spectral_copy.jl`) | the script's local `spectral_onmesh_field` vs production `_spectral_field_grid`, round (128^2) and flat25 (128x1200), one least-squares constant removed | max shape residual 5.977e-16 (round), 6.058e-16 (flat25); production absolute scale needed vs BE 1.0036 / 1.0114 |
| `picfield_default.log` | `validation/pic_gaussian_field_validation.jl` as documented (writes 5 case TSV+PNG, runs python3) | exit 0; medians 3.4649e-4 / 3.5897e-4 / 3.9000e-4 / 4.5987e-4 / 3.9000e-4 |
| `gpic_default.log` | `validation/gaussian_pic_field_validation.jl` as documented | exit 0; profile tripwire max diff 1.251e-14 (gate 1e-12); 12-row table, see Clean 2 |
| `bigauss_default.log` | `validation/gaussian_pic_bigaussian_validation.jl` as documented | exit 0; 5 rows, see Clean 2 |
| `extent_default.log` | `validation/pic_grid_extent_stability.jl` as documented (200k, 15 slices, 8 turns) | exit 0; extrema 5.3131e-2/5.1446e-2/5.1687e-2/4.8031e-2, sigma 6.4639e-3/1.3305e-2/1.0233e-2/1.3832e-2, dropped 0/0 |
| `noise_default.log` | `validation/noise_floor_meshswap.jl` as documented (~3 min) | exit 0; round deterministic row soft-G 6.27e-5, PIC(64) 7.98e-4, hybrid(128) 1.77e-4, spectral 1.23e-3 |
| `kd_reduced.log` | `OCTOPUS_KD_R=4 OCTOPUS_KD_NBOOT=10 OCTOPUS_KD_SEED=1 validation/kick_decomposition.jl` | exit 0; 12 rows; wrote `result/kick_decomposition_R100_seed1.tsv` with R column = 4 |
| `opt_*.log`, `opt_summary.log` (`run_opt.sh`) | `validation/pic_option_consistency.jl` arms base/tsc/quad/node (CPU), mismatch (npart 1000), gpu_base/gpu_node (CUDA), gpu_hidden (`CUDA_VISIBLE_DEVICES=` with `OCTOPUS_OPT_BACKEND=gpu`), all at TURNS=6 NPART=2000 GRID=32 TIMING_FROM=3 DUMP_TURNS=6; then `pic_option_consistency_summary.jl` | 7 arms exit 0, gpu_hidden exit 1 (`CUDA_ERROR_NO_DEVICE`, no output files); summary refuses `mismatch vs base -> npart: 1000 vs 2000, ...`; gpu_base vs base luminosity 2.9e-15, coords <= 6e-14 sigma; gpu_node == node to 4 digits in every column |
| `ssc_cpu.log`, `ssc_cuda.log`, `ssc_cuda_hidden.log` (`run_ssc.sh`) | `validation/strong_strong_spectral_comparison.jl` at N=4000 TURNS=2 GRID=64,256 FREE_GRID=24,24, backend cpu / cuda / cuda with hidden device, output prefix under scratch | cpu and cuda exit 0 (PIC final luminosity 1.0241031712323575e30 vs 1.024103171232394e30); cuda_hidden exit 1 with the script's own "CUDA is not functional" error; cuda run prints `free_grid = (24, 24)` while its timing TSV has no grid-free row and `cuda_field_microprofile.tsv` is header-only |

Machine: 128 cores, load ~6.5, RTX 4500 Ada (CUDA functional), Julia 1.12.4. Timings quoted from the
scripts are indicative only.

## Leads

### LEAD U44-1 [Moderate, confidence high] validation/kick_decomposition.jl:1-28
Claim: The header describes a different script's behaviour (four-solver table, "round-beam correctness gate", PIC 128^2 / hybrid 64^2, output `data/flat_beam_noise_floor.tsv`), none of which this file does; lines 30-189 are a byte-identical dead copy of `noise_floor_meshswap.jl` 40-199.
Mechanism: The file was derived from the noise-floor script and its body replaced by the systematic/fluctuation decomposition (lines 192-302), but the header was not rewritten. `case_medians` is defined at 171 and called nowhere; `hybrid_kicks`/`spectral_kicks` are called only inside it; the only solver the live code runs is `pic_kicks`. The script prints no gate block, no soft-G/hybrid/spectral columns, and writes `result/kick_decomposition_R100*.tsv`. The README (validation/README.md:1934-1936) describes the body correctly, so the header is the stale copy (defect class 14; also class 2 for the duplicated helper block, which U23-10's fix history shows drifting independently).
Repro: `diff <(sed -n '40,199p' validation/noise_floor_meshswap.jl) <(sed -n '30,189p' validation/kick_decomposition.jl); echo $?` -> `0`; `grep -n "case_medians(" validation/kick_decomposition.jl` -> one line (the definition); `OCTOPUS_KD_R=4 OCTOPUS_KD_NBOOT=10 OCTOPUS_KD_SEED=1 julia --startup-file=no --project=. validation/kick_decomposition.jl | grep -c "round (gate)\|soft-G"` -> `0`, last line `wrote .../result/kick_decomposition_R100_seed1.tsv`.

### LEAD U44-2 [Moderate, confidence high] validation/noise_floor_meshswap.jl:251-263
Claim: The "correctness gate" is print-only, and the reference it prints is the review's PIC 128^2 / hybrid 64^2 columns while the run uses PIC 64^2 / hybrid 128^2, so a reader following the header compares the run against numbers for a configuration it did not execute.
Mechanism: Lines 29-30 promise "The round-beam case is run first as a correctness gate against the review's recorded numbers"; nothing in the code compares anything. Lines 261-263 print "PIC128 3.8e-3/1.2e-3/4.8e-4/4.1e-4, hyb64 3.6e-3/1.1e-3/4.5e-4/1.6e-4", but `run_family("round (gate)", ...; picgrid=64, hybgrid=128)` at 252-254 is the swapped assignment (the header's own point, lines 20-27). The review table (`docs/history/poisson_solver_review_2026_07_24.md:911-916`) has the matching PIC 64^2 (…/8.0e-4) and hybrid 128^2 (…/1.8e-4) columns. Measured deterministic row: PIC 7.98e-4 and hybrid 1.77e-4, which match the review's PIC-64/hyb-128 columns to two digits and disagree with the printed "reference" by 2x and 10% respectively. Only the deterministic row is seed-independent; the stochastic rows differ from the review by sampling (e.g. 1e5 soft-G 6.01e-4 vs 9.3e-4), so even a correct reference would need a stated tolerance (class 1: a check that never executes; class 14).
Repro: `julia --startup-file=no --project=. validation/noise_floor_meshswap.jl | grep -A5 "round (gate)" | grep deterministic` -> `deterministic  6.27e-05  7.98e-04  1.77e-04  1.23e-03`; compare with the script's last three printed lines (4.1e-4 / 1.6e-4) and with `sed -n '911,916p' docs/history/poisson_solver_review_2026_07_24.md`.

### LEAD U44-3 [Minor, confidence high] validation/noise_floor_meshswap.jl:36-37
Claim: The header names `data/noise_floor_meshswap.tsv` (and `data/flat_beam_noise_floor.tsv`) as the output; the code writes `result/noise_floor_meshswap.tsv` and no `data/` directory exists in this repository (same in `kick_decomposition.jl:27`).
Mechanism: The `data/` paths belong to the paper repository (per `gaussian_pic_field_validation.jl:209-212` and README:97); the header was not updated when the output moved to `result/` (line 247). Header drift against `docs/guides/examples_and_validation.md:36-39` ("states ... the inputs and outputs").
Repro: `ls data` -> `No such file or directory`; `grep -n "data/" validation/noise_floor_meshswap.jl validation/kick_decomposition.jl` (4 header lines) vs `grep -n '"result"' validation/noise_floor_meshswap.jl validation/kick_decomposition.jl`.

### LEAD U44-4 [Minor, confidence high] validation/kick_decomposition.jl:270-273
Claim: The output filename hardcodes `R100` regardless of `OCTOPUS_KD_R`, so a reduced run produces a file whose name claims 100 realizations while its rows say otherwise.
Mechanism: `OUT2` is built from `KD_SEED` only; `R` (line 283) is read per row. Receipt-vs-name mismatch (class 11/14): the comment at 268-269 says the default seed protects "the archived draw", but a non-default `R` at the default seed overwrites `kick_decomposition_R100.tsv` with non-R100 content.
Repro: `OCTOPUS_KD_R=4 OCTOPUS_KD_NBOOT=10 OCTOPUS_KD_SEED=1 julia --startup-file=no --project=. validation/kick_decomposition.jl >/dev/null; cut -f5 result/kick_decomposition_R100_seed1.tsv | grep -v '^#' | sort -u` -> `4` and `R`.

### LEAD U44-5 [Minor, confidence high] validation/pic_gaussian_luminosity_validation.jl:128,140-142
Claim: The `padding` sweep (0.1, 1.0, 2.0) varies a parameter of the script's local quadrature only; production hardcodes 0.1 and exposes no padding option, so two thirds of the TSV rows characterize a quadrature production never performs.
Mechanism: `_pic_luminosity_mesh` (`src/tasks/strongstrong/pic_cpu.jl:3004-3017`) has `tx = width / T(nx - 1.1)`, `width += T(0.1) * tx`, `xmin -= T(0.05) * tx`; the `PICPoissonSolver` keyword list (`interface.jl:1130-1157`) has `luminosity_grid`, `luminosity_deposit_method`, `luminosity_schedule` and nothing for padding. The interface tripwire at line 142 runs only when `padding == 0.1`, so the 1.0/2.0 rows are never tied to production. The header ("several grid resolutions and padding values") and README:647 present padding as swept configuration. Hypothesis 2: an option swept that nothing reads. (Measured at grid 256 / 400k: 5.77e-4, 5.81e-4, 5.86e-4 for 0.1/1.0/2.0, so no production conclusion rests on it today.)
Repro: `grep -n "padding" src/tasks/strongstrong/interface.jl src/tasks/strongstrong/pic_cpu.jl` -> only the hardcoded constants in `_pic_luminosity_mesh`; `grep -n "padding == 0.1" validation/pic_gaussian_luminosity_validation.jl`.

### LEAD U44-6 [Minor, confidence med] validation/pic_gaussian_luminosity_validation.jl:121-122,169
Claim: The gate-only `identical_edge_probe` case dominates the headline `maximum_relative_error` (9.08e-2) and is non-monotone in grid, while the five physical cases' maximum is 4.30e-2; nothing marks the probe case as non-physical in the TSV or the printout.
Mechanism: With both beams the same particle set, `sum(q1 .* q2) = sum(q1.^2)` includes each particle's self-overlap, a positive bias that grows as the mesh becomes finer than the sampling: measured CIC/padding 0.1/20000 particles 1.08e-2, 1.96e-3, 7.93e-3, 9.08e-2 at grids 32/64/128/256. The case was added (U23-1) to give the interface gate teeth, but it is pooled into the analytic-convergence characterization the README describes (class 14: a number whose regime is not stated).
Repro: `julia --project=. validation/pic_gaussian_luminosity_validation.jl | grep maximum_relative_error` -> `0.0907...`; `awk -F'\t' 'NR>1 && $1!="identical_edge_probe" && $8>m{m=$8} END{print m}' result/pic_gaussian_luminosity_validation.tsv` -> `0.0429...`.

### LEAD U44-7 [Minor, confidence high] validation/gaussian_pic_bigaussian_validation.jl:51-56
Claim: `cic_profile` is a hand copy of the shipped `_gpic_gaussian_profile!` CIC branch with no drift tripwire, although the sibling `gaussian_pic_field_validation.jl:71-88` received exactly that tripwire (U10-5) for the same reason.
Mechanism: The theory note's bi-Gaussian table (`gaussian_subtracted_pic_solver.md:700-708`) rests on this script's hybrid column; a regression in the shipped CIC profile (`gaussian_pic.jl:208-226`) leaves the table green because the script never calls production's profile. Today the two formulas are textually identical (`m0 + (m1 - m1)/h`), so no numeric effect (class 2).
Repro: `grep -c "_gpic_gaussian_profile!" validation/gaussian_pic_bigaussian_validation.jl` -> `0`; `grep -c "_gpic_gaussian_profile!" validation/gaussian_pic_field_validation.jl` -> `>=2`.

### LEAD U44-8 [Minor, confidence high] validation/noise_floor_meshswap.jl:106
Claim: The hybrid path's `O._pic_field(phi, hx, hy)` takes the `fourth=false` default instead of `_pic_fourth_order(solver)`, the U23-10 defect that was fixed in two siblings but left standing in this third copy (and in the dead `kick_decomposition.jl:96`).
Mechanism: `solve_from_charge` here is the same local reimplementation as `gaussian_pic_field_validation.jl:117-133`, whose fix comment explains that the public `field_derivative` option was silently ignored by the copy. No numeric effect at committed defaults (`field_derivative=:second`), but the hand copy is one option behind production (class 2/5).
Repro: `grep -n "_pic_field(" validation/*.jl` -> `noise_floor_meshswap.jl:106` and `kick_decomposition.jl:96` without `_pic_fourth_order`, the two siblings with it.

### LEAD U44-9 [Minor, confidence high] validation/spectral_poisson_field_validation.jl:250-251
Claim: Four region scripts read `OCTOPUS_*` inputs their headers do not state, the header-drift class U23-8 fixed in one sibling: `OCTOPUS_SPECTRAL_NSRC`/`OCTOPUS_SPECTRAL_FIELD_AXIS` (spectral, 250-251), `OCTOPUS_BIGAUSS_GRID`/`OCTOPUS_BIGAUSS_SEEDS` (bigaussian, 161-162), `OCTOPUS_PIC_LUMINOSITY_VALIDATION_PARTICLES`/`_GRIDS`/`_PADDING` (luminosity, 125-128), `OCTOPUS_KD_NBOOT`/`OCTOPUS_KD_SEED`/`OCTOPUS_KD_R` (kick_decomposition, 241/270/283; named in README:1936 but not in the header).
Mechanism: `docs/guides/examples_and_validation.md:36-39` requires each script's top comment to state the inputs; a reader cannot reproduce a reduced or extended run from the header alone (class 14).
Repro: `for f in spectral_poisson_field_validation gaussian_pic_bigaussian_validation pic_gaussian_luminosity_validation kick_decomposition; do echo $f; grep -o "OCTOPUS_[A-Z_]*" validation/$f.jl | sort -u; done` and compare each list against that file's header block.

### LEAD U44-10 [Minor, confidence med] validation/pic_option_consistency.jl:266-273
Claim: The recorded run carries no receipt of dropped charge: the `:node` arms dropped particles (CPU: `dropped = 2`; CUDA: 6/2/1/1/2 across turns) with a console `@warn` only, so the summary's luminosity/moment/coordinate deltas cannot separate an option effect from a coverage loss.
Mechanism: `meta.tsv`, the per-turn TSV and the h5 artifact record options, timing, luminosity and moments; `_pic_report_dropped` (`pic_cpu.jl:550-576`) only warns; `grep -i dropped src/tasks/RunArtifact.jl` finds no dataset. At the probe settings `node` differed from `base` by 7.4e-4 in luminosity and 1.6e-2 sigma RMS in x, with dropped particles contributing an unknown share (hypothesis 2 / class 6). Receipts are the script's stated purpose (U25-1 added them for batching).
Repro: `OCTOPUS_OPT_TAG=node OCTOPUS_OPT_INTERACTION_GRID=node OCTOPUS_OPT_TURNS=6 OCTOPUS_OPT_NPART=2000 OCTOPUS_OPT_GRID=32 OCTOPUS_OPT_TIMING_FROM=3 julia --threads=4 --project=. validation/pic_option_consistency.jl 2>&1 | grep -c "dropped ="` -> `>= 1`; `grep -c -i dropped result/pic_option_node.meta.tsv result/pic_option_node.tsv` -> `0`.

### LEAD U44-11 [Minor, confidence med] validation/pic_option_consistency_summary.jl:161
Claim: The coordinate-level metric is normalized by hand-copied beam sigmas (`106e-6, 9.5e-6` / `95e-6, 8.5e-6`) that `meta.tsv` does not record, so a change to the run script's beams silently mis-scales the "strict" per-particle check.
Mechanism: Two independent copies of the same numbers (`pic_option_consistency.jl:105,110` and the summary's `sig`) with no shared source and no tripwire; the summary already refuses mismatched conditions it CAN read from meta (U25-11), but sigmas are not among the recorded columns (class 2).
Repro: `grep -n "106.0e-6\|95.0e-6" validation/pic_option_consistency.jl validation/pic_option_consistency_summary.jl`; `head -1 result/pic_option_base.meta.tsv | grep -c sigma` -> `0`.

### LEAD U44-12 [Minor, confidence high] validation/strong_strong_spectral_comparison.jl:206-209,261-263,277
Claim: On `OCTOPUS_SPECTRAL_COMPARE_BACKEND=cuda` the grid-free arm and the field micro-profile are omitted silently, yet the summary prints `free_grid = (Nx, Ny)` from the request flag rather than from what ran.
Mechanism: Line 206 adds the grid-free solver only for `CPUThreadsBackend`; line 263 `continue`s out of the micro-profile on CUDA; line 277 prints `INCLUDE_GRID_FREE ? string(FREE_GRID) : "disabled"`. Measured: the CUDA run printed `free_grid = (24, 24)`, its `_timing.tsv` has three rows (no `spectral_grid_free`), and `_field_microprofile.tsv` is a header line only. Hypothesis 3 (skipped, not visibly) and class 11 (report what ran).
Repro: `OCTOPUS_SPECTRAL_COMPARE_N=4000 OCTOPUS_SPECTRAL_COMPARE_TURNS=2 OCTOPUS_SPECTRAL_COMPARE_BACKEND=cuda OCTOPUS_SPECTRAL_COMPARE_OUTPUT=/tmp/ssc julia --project=. validation/strong_strong_spectral_comparison.jl | grep free_grid` -> `free_grid = (48, 48)`; `wc -l /tmp/ssc_field_microprofile.tsv` -> `1`; `grep -c grid_free /tmp/ssc_timing.tsv` -> `0`.

### LEAD U44-13 [Minor, confidence high] validation/pic_option_consistency.jl:69
Claim: The script uses `using Octopus` instead of the `isdefined(Main, :Octopus)` include guard that 40 of the 61 validation scripts carry, so it cannot be `include`d after a sibling in one process, the U25-14 rationale the guarded siblings cite.
Mechanism: After a sibling has done `include("src/Octopus.jl"); using .Octopus`, `using Octopus` loads a second package instance from the environment (or fails outside `--project`). Three scripts outside this region share the pattern (`twiss_dispersion_route_dump.jl`, `slice_interpolation_emittance_growth.jl`, `twiss_dispersion_acceptance_windows.jl`); cross-file note, not audited here. The documented single-script command works (verified: 7 arms ran).
Repro: `grep -ln "^using Octopus" validation/*.jl` -> 4 files; `grep -L "isdefined(Main, :Octopus)" validation/*.jl | wc -l`.

### LEAD U44-14 [Minor, confidence high] docs/theory/spectral_sine_poisson_solver.md:439 (cross-file seam, out of hypothesis)
Claim: The spectral note's validation plan still names `validation/pic_gaussian_field_validation.jl` as the spectral-field check; the spectral check is `spectral_poisson_field_validation.jl` (U23 D10 seam, still present at 24e8683).
Mechanism: Stale pointer in an indexed theory note (class 14); `pic_gaussian_field_validation.jl` never constructs a spectral solver (`grep -c -i spectral validation/pic_gaussian_field_validation.jl` -> 0).
Repro: `sed -n '439,441p' docs/theory/spectral_sine_poisson_solver.md`.

### LEAD U44-15 [Minor, confidence high] docs/theory/gaussian_subtracted_pic_solver.md:660-664
Claim: The table's gain column (9.1x, 20.6x, 17.6x at grid 48) is the pre-U23-2 value; the post-fix script gives 9.2x, 20.0x, 17.2x, and the note's own paragraph at line 683 already says 9.2x.
Mechanism: The U23-2 fix changed the hybrid column (add-back from sample moments); the medians reproduce to two significant figures as the note promises (1.57e-4 vs 1.6e-4; 2.25e-4 vs 2.2e-4; 2.88e-4 vs 2.8e-4) but the ratios drift up to 3% and were not refreshed (class 14; README:106 "9-20x" remains true).
Repro: `julia --project=. validation/gaussian_pic_field_validation.jl | grep -E "^(round|production_e|25:1) +48"` -> `x med` 9.2 / 20.0 / 17.2 vs the table's 9.1x / 20.6x / 17.6x.

### LEAD U44-16 [Minor, confidence high] validation/spectral_poisson_field_validation.jl:183-221
Claim: The script validates four LOCAL spectral solvers (its own `spectral_onmesh_field`, `spectral_specderiv_field`, `spectral_grid_field`, `spectral_free_field`) and never calls production `_spectral_field_grid`/`_spectral_field_free`, while describing `spectral_onmesh_field` as "the O(Nx*Ny*log) production field path" (194-195) and README:155 as validating "the spectral sine-series 2D Poisson solver"; there is no tripwire tying the copy to production.
Mechanism: Measured today the copy is faithful: after one least-squares constant the max residual against `_spectral_field_grid` is 5.98e-16 (round, 128^2) and 6.06e-16 (flat25, 128x1200). But the §16 tables rest on the copy, and a production change (deposit floor, derivative transform, interpolation) would leave them green, the same class-2 situation U10-5 closed for the Gaussian profile with a tripwire. The absolute normalization IS pinned on production by the suite ("Spectral field absolute normalization is derived, not fitted", `test/runtests.jl:28276`), as the header says.
Repro: `grep -c "_spectral_field_grid\|_spectral_field_free" validation/spectral_poisson_field_validation.jl` -> `0`; `julia --project=. result/comprehensive_audit_2026_10_18/probes/U44/probe_spectral_copy.jl` -> residuals ~6e-16.

Style only (no lead): `noise_floor_meshswap.jl:32` says "Run from this folder" above a root-relative path; `pic_option_consistency.jl:27` uses `--threads=6` where every sibling documents 4; `gaussian_pic_field_validation.jl:69` quotes a tripwire agreement of 2.36e-16/4.27e-15 where today's run gives 1.25e-14 (still three orders inside the 1e-12 gate).

## Clean

1. **Every documented command runs as written at HEAD.** Eight scripts at committed defaults (`pic_gaussian_field_validation`, `spectral_poisson_field_validation`, `gaussian_pic_field_validation`, `gaussian_pic_bigaussian_validation`, `pic_gaussian_luminosity_validation` at FULL defaults, the measurement U23 did not take, `pic_grid_extent_stability`, `noise_floor_meshswap`, and `kick_decomposition` with reduced R/NBOOT only) and the three multi-arm scripts with small env overrides, all exit 0, no deprecation warnings. Every internal API they call resolves with the arity used: `_pic_interaction_grids` (9 args), `_pic_solve_field` (5), `_pic_interpolate_kick` (12; with `zL,zR = 1,0` the weights reduce to `ExL` exactly, so passing the same field twice is sound), `_pic_deposit!` (10), `_pic_green_fft` (4), `_pic_field` (3/4), `_pic_fourth_order`, `_gpic_gaussian_profile!` (6), `_pic_luminosity` (6), `_pic_axis_extent` (8), `longitudinal_slices`, `_spectral_field_grid` (8), `_spectral_box` (5 positional), `_spectral_grid_ws`, `_spectral_field_ws`, `collide!(solver, b1, b2, backend)`, `beam_statistics`, `coordinate_arrays`, `read(TaskOutput(path), :luminosity; name=)`, both `Beam` constructor forms. The grid spacing convention `hx = width/(nx-1)` used by the local `solve_from_charge` copies is the one `_pic_green_fft` uses.
2. **The recorded numbers reproduce** (what was compared): `pic_gaussian_field_validation` medians 3.4649e-4 .. 4.5987e-4 identical to the 2026-08-04 band and to U23's digits; `gaussian_pic_field_validation` vs theory §9 medians 15/15 at two significant figures (round/48 1.45e-3 / 1.57e-4; round/128 4.58e-4 / 1.75e-4; 11:1/48 4.50e-3 / 2.25e-4; 11:1/128 1.28e-3 / 3.16e-4; 25:1/48 4.95e-3 / 2.88e-4), gains drift per U44-15; `gaussian_pic_bigaussian_validation` vs theory §9 and README 15/15 to every printed digit (4.68e-4/1.77e-4/2.6; 5.51e-4/2.56e-4/2.2; 3.30e-4/1.88e-4/1.8; 6.47e-4/4.40e-4/1.5; 6.08e-4/4.45e-4/1.4), including the random coupled row HYB 1.30e-3 > PIC 1.25e-3 and 1.0 random gains the README's median qualifier rests on; `spectral_poisson_field_validation` vs theory §16: domain-size 5/5, thin-grid 4/4, main shape table 6/6 (round on-mesh 2.660e-3/1.390e-2 vs 2.7e-3/1.4e-2 etc.); `pic_grid_extent_stability` header ratios 8.2x/5.1x/3.9x/3.5x -> 8.22/5.05/3.87/3.47, `:extrema` 5.3131e-2, dropped 0; `noise_floor_meshswap` deterministic round row vs the review's MATCHING columns 4/4 (soft-G 6.27e-5 vs 6.3e-5, PIC-64 7.98e-4 vs 8.0e-4, hybrid-128 1.77e-4 vs 1.8e-4, spectral 1.23e-3 vs 1.2e-3).
3. **The two enforced gates have teeth.** Luminosity interface gate: current quadrature vs production <= 1.5e-15 on all 16 probe rows; the pre-U5-8 truncated copy fails exactly where and by how much U23 recorded (identical_edge_probe/TSC: 5.067e-9 at 32, 8.876e-8 at 128) and nowhere else, so `identical_edge_probe` is doing the job it was added for. The full-default run passes at 1.035e-14. The gpic profile tripwire compares both CIC and TSC branches against the shipped profile at three node/spacing/moment settings with atol 1e-12 before any table is printed; measured agreement 1.25e-14.
4. **Receipts in `pic_option_consistency.jl` are what the run used** (hypothesis 2): `meta.tsv` for `gpu_node` records `batch_mode=sequential`, `cuda_async=false` read off the solver, and the downgrade `@warn` at line 160 fired with both effective values; the swept options are read by the runtime (tsc/quad/node arms differ from base by 1.96e-3 / 4.9e-5 / 7.4e-4 in luminosity, in the order the discretizations imply); the summary refuses the arm whose particle count differs, naming `npart`, `npart_e`, `npart_p`, and compares the rest; the h5 append-mode luminosity read-back returns the series. CPU/CUDA `base` arms agree to 2.9e-15 (luminosity) and <= 6e-14 sigma (coordinates); the CPU and CUDA `:node` arms agree to four digits in every reported column.
5. **GPU legs fail loudly, never silently** (hypothesis 3): `OCTOPUS_OPT_BACKEND=gpu` with the device hidden dies at the first `CuArray` allocation (`CUDA_ERROR_NO_DEVICE`, `Beam.jl:144`) with no output files; `OCTOPUS_SPECTRAL_COMPARE_BACKEND=cuda` with the device hidden dies at the script's own `clone_beam` check with its documented message. `CUDAExecutionPolicy()` itself refuses when CUDA.jl is absent (`Policies.jl:1362`). The one non-visible skip is U44-12.
6. **The hand copy of the example in `pic_option_consistency.jl` matches `examples/strong_strong_tracking.jl`** parameter by parameter (energies, charges, `n_particle`, sigma/beta/alpha, crab beta, tunes, chromaticities, crab frequencies and strengths, damping turns 4000/4000/2000, half-crossing 12.5e-3, slicing 15/`:normal_quantile`/`:centroid`, `green_cache=:slice_pair` with the example's 0.50/0.25 cache ratios as defaults) and in ring order (tccb2ip_inv, cavity, tccb2ip, boost, IP, rev-boost, ip2tcca, cavity, ip2tcca_inv, one-turn, chromaticity, radiation) minus the example's observers.
7. **Normalization conventions are consistent across the region**: `2E/n_source` in four PIC scripts, `(ns/2)*BE` add-back in the hybrids, and `_spectral_field_grid`'s unit-charge `-2pi` convention consumed WITHOUT a fitted constant in `noise_floor_meshswap.jl` (its spectral column lands at 1.23e-3 against BE, the review's 1.2e-3); the production absolute scale needed against BE is 1.0036 (round, 128^2) and 1.0114 (flat25), inside what the suite's 0.5%-at-511^2 pin implies for coarser meshes. The header's claim that the suite testset "Spectral field absolute normalization is derived, not fitted" exists is true (`test/runtests.jl:28276`), and that testset drives production functions.
8. **Luminosity local quadrature at padding 0.1 is algebraically the production mesh**: `tx = width0/(nx-1.1)`, `+0.1*tx`, `-0.05*tx`, `hx = width/(nx-1)` line for line with `_pic_luminosity_mesh`, and both deposit into `(nx+1) x (ny+1)` with limits `nx+1, ny+1`, summing the full extent.
9. **The extent script's use of `_pic_axis_extent`** passes shifted sums `(x - origin)`, `(x - origin)^2` and the count, the same convention as production's call at `pic_cpu.jl:1204-1207` (production doubles both sums and count for its two drifted copies; the script is self-consistent with one copy); the `:sigma` half-width is `grid_extent_sigma` read from the constructed solver, not a literal.
10. **Metric mechanics checked by reading**: the python plot helper's `rel_norm[j][i] = r[9]` row/column mapping matches the Julia writer's `for y in ygrid, x in xgrid` order (k div nx is the y index) and column 10 is `rel_to_max_exact_norm`; `kick_decomposition.jl`'s Rayleigh comparator `f*sqrt(ln2/R)` is the median of the magnitude of an isotropic 2D mean with `f = hypot(std_x, std_y)`; its sign-flip bootstrap centers the residuals first as the comment argues; the bi-Gaussian script's `fr1`/`fr2` are actual sample fractions (not the nominal `f2`) and its hybrid add-back uses empirical moments against a nominal superposition reference, so the column is not circular (the U23-2 pattern does not recur); `noise_floor_meshswap.jl`'s 5/5/3 draws shared across the four columns match the header; `pic_gaussian_field_validation.jl`'s header lists all nine `OCTOPUS_PIC_VALIDATION_*` inputs and both summary filenames (U23-8 closed).
11. **Print-only vs enforced, the full inventory for hypothesis 1**: enforced numeric gates are exactly two (luminosity interface 1e-12; gpic profile 1e-12), plus input/degeneracy guards (`sigma_min > 0`, `sigma_max > sigma_min`, `global_exact_norm > 0`, `grid must be nx,ny`, backend name) and the two CUDA-availability errors. Everything else is print-only, and for `pic_gaussian_field`, `gaussian_pic_field`, `bigaussian`, `spectral`, and `grid_extent` the README says so in words ("Characterization, not a gate"). The two scripts that claim a gate they do not enforce are U44-1 and U44-2.

## Unchecked

- `noise_floor_meshswap.jl`'s claim (header 20-27, README 1930-1933) that the production mesh assignment "regenerates Table 1 (`data/flat_beam_noise_floor.tsv`) bit-for-bit in all eight rows": the archived table lives in the paper repository, not in this tree, and I did not run the swapped-back configuration. Unverifiable here; the deterministic row of the swapped run matching the review to two digits is the nearest evidence.
- `kick_decomposition.jl` at its archived `R=100`, `NBOOT=200` (12 rows x 100 PIC solves up to 256^2, 1e5 particles): not run; only the R=4/NBOOT=10 smoke run. The comment's "+15.6% here and +16.9..+19.3% over six fresh ensembles" is therefore unreproduced.
- `pic_option_consistency.jl` at its documented production reference point (2.56M/1.02M particles, 200 turns, grid 128, CUDA) and the README's GPU cost numbers (0.0940 vs 0.0641 s/turn at 2000/32^2): not re-measured; I ran 6 turns at 2000/32^2 and did not run a wavefront-forced `:node` arm, so the batching-cost ratio is not re-quoted. Timings are machine-specific in any case.
- `strong_strong_spectral_comparison.jl` at its documented defaults (N=20000, GRID=128,1024, 3 turns): not run; N=4000, GRID=64,256, 2 turns only.
- `pic_gaussian_field_validation.jl` random-sweep mode (`OCTOPUS_PIC_VALIDATION_RANDOM_CASES > 0`, the manuscript Figure 3 file): not run.
- Injection into the field metrics of `pic_gaussian_field_validation` / `gaussian_pic_field_validation` and into the gpic profile tripwire: not repeated this session; U23 b1/b2 measured the former (working instrument with a ~1e-4 detection floor), and the tripwire is a direct max-abs comparison whose mechanism I verified by reading plus the measured 1.25e-14 agreement.
- The dead helper block in `kick_decomposition.jl` (30-189) was read and diffed, not executed (nothing calls it).
- MPI/divided paths: none of the eleven scripts has one.
- Side effect for the auditor: my reproductions left the scripts' regenerable outputs in the git-ignored `result/` (listed in `probes/U44/result_outputs/`, 35 files copied; notably `result/pic_option_{base,tsc,quad,node,mismatch,gpu_base,gpu_node}.*` and `result/pic_option_consistency_summary.tsv`). A later owner run of `pic_option_consistency_summary.jl` would read those meta files; delete them if that matters. Nothing tracked changed.
