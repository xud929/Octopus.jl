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
- **Table 2** (Yokoya factors, Sec. 5.1) comes from the runs recorded in the
  section text; the BeamBeam3D entry uses the deck in `data/bb3d_decks/`.
- **Table 3** (cross-code emittance benchmark, Sec. 5.4) is computed from
  `eic_emittance_{octopus,bb3d}.tsv` as the mean over the final 2048 turns,
  relative to the design emittance sigma*^2/beta*.
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
  `mesh_study_reexecution.tsv` + `mesh_study_driver.jl` --- three seeds at each
  of 64^2, 128^2, 256^2 plus the grid-free soft-Gaussian reference, re-executed
  from the released tag with the driver archived. This supersedes an earlier
  unarchived study; see "Code and data availability" in the manuscript.
- **Sec. 4.1, mesh-swap control.** `noise_floor_meshswap.tsv` +
  `noise_floor_meshswap.jl` (plain PIC at 64^2 against hybrid at 128^2).
- **Sec. 4.1, systematic/fluctuation decomposition.**
  `kick_decomposition_R100.tsv` + `kick_decomposition.jl`. Realization count
  from `OCTOPUS_KD_R` (default 100); the script writes the archived file
  directly. The `bias_floor` column is the sampling-noise floor of the bias
  statistic. Note that `bias` is the magnitude of a 2-D mean vector, so its
  null is Rayleigh and the median floor is `fluct*sqrt(ln 2 / R)`, i.e.
  0.833*fluct/sqrt(R) -- neither `fluct/sqrt(R)` nor the 1-D constant
  0.6745*fluct/sqrt(R), both of which appeared in earlier versions of this
  measurement and are wrong for a vector magnitude.
- **Sec. 4.1, reference-noise bound.** `softgauss_count_scan.tsv`.
- **Sec. 5.1, tune-swap control.** `lambda_tuneswap_control.tsv`.
- **Sec. 5.1, narrow-plane xi control.** `lambda_narrowplane_fixedxiy.tsv` +
  `lambda_fixedxiy.jl` (holds xi_y = 0.005 at every aspect ratio, showing the
  narrow-plane branch is not a xi_y artifact).
- **Sec. 5.1, flat-beam robustness.** `lambda_flatxi.jl`, `lambda_tunescan.jl`
  (Lambda against xi and against working point).
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
- One documented gap: the driver for the *original* mesh/reference
  decomposition of Sec. 4.1 was not archived, and that study is not
  re-executable from the release. `mesh_study_driver.jl` is the archived
  re-execution that carries the section's conclusions.
- Pin turn counts explicitly when re-running validation ensembles; at least one
  script's default drifted during development.
