# Paper reproduction package

Frozen data and scripts reproducing every figure and table of
"A GPU-accelerated framework for multi-slice, multi-turn strong-strong
beam-beam simulation" (CPC submission).

`python3 make_figures.py` regenerates all **nine** manuscript figures into
`figs/` from `data/`. It uses matplotlib only, with no network access and no
absolute paths.

## Figures

Numbered as in the manuscript.

| # | file | section | data |
|---|---|---|---|
| 1 | `fig_noise_floor.pdf` | 4.1 | `flat_beam_noise_floor.tsv` |
| 2 | `fig_error_vs_grid.pdf` | 4.1 | `gaussian_pic_field_validation_summary.tsv`, `pic_analytic_floor.tsv` |
| 3 | `fig_error_vs_aspect.pdf` | 4.1 | `pic_gaussian_field_validation_random_summary.tsv` |
| 4 | `fig_boundary_jump.pdf` | 4.2 | `slice_longitudinal_zscan_jumps.tsv`, `slice_longitudinal_zscan_tsc_jumps.tsv` |
| 5 | `fig_coherent_fft.pdf` | 5.1 | `coherent_spectrum_pic_{x,y}.tsv` |
| 6 | `fig_yokoya_scans.pdf` | 5.1 | `yokoya_vs_aspect{,_measured}.tsv`, `yokoya_vs_xi_{theory,measured}.tsv`, `lambda_narrowplane.tsv` |
| 7 | `fig_multislice_spectra.pdf` | 5.3 | `multislice_centroids_{octopus_kicked,octopus_noise,bb3d}.tsv` |
| 8 | `fig_eic_emittance.pdf` | 5.4 | `eic_emittance_{octopus,bb3d}.tsv` |
| 9 | `fig_eic_modes.pdf` | 5.6 | `eic_mode_spectra.tsv` |

## Tables

- **Table 1** (single-kick error budget, Sec. 4.1) is exactly
  `flat_beam_noise_floor.tsv`. Six-seed repeat scatter: `nf_seed_{11..66}.tsv`.
- **Table 2** (Yokoya factors, Sec. 5.1): the PIC row is
  `lambda_round_converged.tsv`, an independent three-seed re-measurement from
  `lambda_flat_converged.jl` (aspect 1.0) that reproduces the printed entries;
  the BeamBeam3D entry uses the deck in `data/bb3d_decks/`.
- **Table 3** (cross-code emittance benchmark, Sec. 5.4) is computed from
  `eic_emittance_{octopus,bb3d}.tsv` as the mean over the final 2048 turns.
  NOTE the two beams use different baselines, deliberately: the DAMPED electron
  is referenced to the design emittance sigma*^2/beta* (damping erases its
  initial sample), while the UNDAMPED proton is referenced to each code's own
  initial value. Referencing the proton to design would permanently import the
  two codes' initial sampling difference (-0.28 and +0.42 pp in x and y),
  which is larger than the growth differences being compared.
- **Tables 4 and 5** (CUDA waterfall and ablation, Sec. 6.2) are wall-clock A/B
  measurements recorded in the paper text; `cpu_gpu_timing_summary.tsv` and
  `gpu_size_scaling.tsv` hold the thread sweep, observer A/B and size scans.
- **Table 6** (device-time decomposition, Sec. 6.3) is
  `cuda_device_time_decomposition.tsv`, produced by CUDA.jl 6.2.1's in-process
  CUPTI profiler (`CUDA.@profile`) over 10 steady-state turns after 20 warm-up
  turns at the production point. The file header records the uninstrumented
  wall-clock per turn, the profiler's own inflation factor, and the device-busy
  fraction of the turn.

## Section-level supporting data

- **Sec. 4.1, mesh study (the measurement that carries the section).**
  `mesh_study_reexecution.tsv` + `mesh_study_driver.jl` --- seeds 1/2222/3333 at
  64^2, 256^2 and the grid-free soft-Gaussian reference, and seeds 1/2222 at
  128^2 (the coverage is uneven; the third seed is the largest wherever it
  exists, so the 128^2 mean is the one most likely biased low). Re-executed
  from the released tag with the driver archived. This supersedes an earlier
  unarchived study; see "Code and data availability" in the manuscript.
  See also the Green-cache confound control below: about half the apparent
  mesh trend in this file is the cache, not the mesh.
- **Sec. 4.1, mesh-swap control.** `noise_floor_meshswap.tsv` +
  `noise_floor_meshswap.jl` (plain PIC at 64^2 against hybrid at 128^2).
- **Sec. 4.1, systematic/fluctuation decomposition.**
  `kick_decomposition_R100.tsv` + `kick_decomposition.jl`. Realization count
  from `OCTOPUS_KD_R` (default 100), bootstrap draws from `OCTOPUS_KD_NBOOT`
  (default 200); the script writes the archived file directly.
  `bias_floor_bootstrap` is the sampling-noise floor of the bias statistic
  MEASURED by a sign-flip (Rademacher) bootstrap: flipping each realization's
  sign preserves the per-point fluctuation structure and destroys any true
  systematic, so the flipped ensemble's median |mean| is the floor, with no
  distributional assumption. `bias_floor_rayleigh` is the Gaussian-isotropic
  closed form `fluct*sqrt(ln 2 / R)` for comparison only -- it agrees with the
  measured floor to just -15%/+18% across the eight configurations, which is
  why the manuscript uses the bootstrap.
- **Sec. 4.1, reference-noise bound.** `softgauss_count_scan.tsv`.
- **Sec. 5.1, tune-swap control.** `lambda_tuneswap_control.tsv`.
- **Sec. 5.1, narrow-plane xi control.** `lambda_narrowplane_fixedxiy.tsv` +
  `lambda_fixedxiy.jl` (holds xi_y = 0.005 at every aspect ratio, showing the
  narrow-plane branch is not a xi_y artifact).
- **Sec. 5.1, flat-beam robustness.** `lambda_flatxi.jl`, `lambda_tunescan.jl`
  (Lambda against xi and against working point).
- **Sec. 4.1, Green-cache confound control.** `mesh_study_cache_none.tsv` --
  the identical mesh study re-run with `OCTOPUS_PIC_GREEN_CACHE=none`, three
  seeds at each of 64^2/128^2/256^2. The cache's tight-fit penalty is
  mesh-dependent (+5.4% at 64^2 against +0.4%/+0.3% at 128^2/256^2), so it
  contributes about half the apparent mesh trend; the paper reports the trend
  both with and without it. This arm also carries the full three-seed coverage
  at 128^2 that the cached study lacks.
- **Sec. 5.1, Table 2 re-measurement.** `lambda_round_converged.tsv` +
  `lambda_flat_converged.jl` (aspect 1.0) -- the round-beam PIC row of Table 2
  re-measured from an archived driver at three fresh seeds.
- **Sec. 5.1, converged flat-beam point.** `lambda_flat_converged.tsv` +
  `lambda_flat_converged.jl` -- the r = 0.09 point re-measured at the converged
  settings of Table 2 (8192 turns, 1e5 macroparticles/beam, three seeds),
  reporting BOTH planes. This is what keeps the flat-limit statement from
  resting on the single-seed reduced-settings scan.
- **Sec. 5.4, cross-code emittance benchmark.**
  `eic_emittance_octopus.tsv` (Octopus moment-observer output, every 16 turns)
  and `eic_emittance_bb3d.tsv` (BeamBeam3D `fort.24/25/34/35` column 7,
  subsampled to the same cadence). Head-on, 15 slices, 128^2 mesh, 10^5
  macroparticles per beam in both codes, 8192 turns, electron damping
  shortened to 400 turns. The BeamBeam3D deck is the `eicdamp` case; note that
  the crab cavities and crossing angle must BOTH be off for a head-on
  comparison -- zeroing the crossing angle alone while leaving the crab
  strength at its compensating value tears the beams apart.
- **Sec. 5.2/5.3, cross-code.** BeamBeam3D input decks and raw centroid outputs
  in `data/bb3d_decks/`. Convergence runs:
  `multislice_centroids_octopus_kicked_n{9,15}.tsv`,
  `multislice_centroids_bb3d_n9.tsv`, and the 16384-turn sigma-resolution pair
  `multislice_centroids_{octopus_kicked,bb3d}_16k.tsv`.
- **Sec. 5.4, luminosity anchor.** `crossing_lum_anchor.tsv`
  (`../validation/crossing_luminosity_anchor.jl`; analytic Piwinski reference).
- **Sec. 5.4, crossing-angle dynamical cross-check.**
  `multislice_centroids_{octopus_kicked,bb3d}_crossing.tsv` (half angle
  3.855e-4, Piwinski phi = 1). Deck note: the BeamBeam3D field labeled `alpha`
  is the crossing-plane azimuth; `phi` is the half angle. Setting `alpha` alone
  silently runs head-on.
- **Sec. 5.5, weak-strong reduction anchor.**
  `weakstrong_limit_anchor_compensated.tsv` (400 turns at the compensated
  point).
- **Tune-estimator calibration.** `../validation/tune_estimator_calibration.jl`
  (500 synthetic two-tone trials).

## Not used by the manuscript

`data/multiturn_deferred/` holds 80 multi-turn emittance-growth ensemble TSVs
that no figure or table of this paper uses. They support a planned separate
study; see the README in that directory, which also records a driver-level
correctness constraint worth reading before extending them.

## Reproducibility notes

- Scripts in this directory use paths relative to their own location, so the
  package is self-contained.
- Documented gaps, of two kinds. (a) The driver for the *original*
  mesh/reference decomposition of Sec. 4.1 was not archived, and that study is
  not re-executable; `mesh_study_driver.jl` is the archived re-execution that
  carries the section's conclusions, and the original's claim is withdrawn in
  the manuscript. (b) A few datasets are frozen without their generating
  driver -- `flat_beam_noise_floor.tsv` and its `nf_seed_*` repeats,
  `pic_analytic_floor.tsv`, and the `slice_longitudinal_zscan*` files. These
  are checkable and re-plottable but not re-executable, and the manuscript
  rests no conclusion on any of them alone.
- Pin turn counts explicitly when re-running validation ensembles; at least one
  script's default drifted during development.
