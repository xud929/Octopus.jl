# Paper reproduction package

Frozen data and scripts reproducing every figure and table of
"A GPU-accelerated framework for multi-slice, multi-turn strong-strong
beam-beam simulation" (CPC submission).

- `make_figures.py` regenerates all seven figures into `figs/` from
  `data/` (matplotlib; no network or absolute paths). Run:
  `python3 make_figures.py`.
- `data/` holds the frozen measurement TSVs. Provenance (scripts in
  `../validation/`, run at tag v0.1.1 settings):
  - Table 1 / Fig. 1: `flat_beam_noise_floor.tsv` (400^2 quantile lattice,
    CIC; stochastic rows single realizations).
  - Fig. 2: `gaussian_pic_field_validation_summary.tsv`
    (gaussian_pic_field_validation.jl, OCTOPUS_GPIC_GRIDS=48,...,256) and
    `pic_analytic_floor.tsv` (analytic expected-deposition floors).
  - Fig. 3: `pic_gaussian_field_validation_random_summary.tsv`
    (pic_gaussian_field_validation.jl random sweep; 160^2 lattice, TSC).
  - Fig. 4 / Sec. 4.2-4.3 statistics: `emittance_growth_*_s[1-4].tsv`
    (slice_interpolation_emittance_growth.jl; 800 turns, 4 seeds,
    including the node-indexed arm).
  - Fig. 5: `coherent_spectrum_pic_{x,y}.tsv`
    (coherent_beam_beam_modes.jl; single seed shown).
  - Fig. 6: `yokoya_vs_aspect{,_measured}.tsv`,
    `yokoya_vs_xi_{theory,measured}.tsv` (coherent_mode_vlasov_theory.jl
    with the corrected erfcx spectral kernel; coherent_mode_scans.jl).
  - Fig. 7: `eic_mode_spectra.tsv` (coherent_mode_eic_comparison.jl).
  - Sec. 5.3 / Fig. 8: `multislice_centroids_{octopus_kicked,octopus_noise,bb3d}.tsv`
    (5-slice cross-code benchmark; BB3D built from source, deck in
    `../validation/` notes; identical Hann+parabolic tune estimator).
  - Sec. 5.4: `crossing_lum_anchor.tsv`
    (validation/crossing_luminosity_anchor.jl; analytic Piwinski anchor).
  - Sec. 4.3 quadratic+TSC arm: `emittance_growth_quadratic_n15_tsc_s[1-4].tsv`.
  - Table 1 repeat scatter: `nf_seed_{11..66}.tsv` (six-seed repeats of the
    noise-floor table; deterministic rows are seed-independent).
  - Sec. 4.3 production A/B + Sec. 6 timing: `production_ab_growth.tsv`
    (CIC vs TSC, 3 shared seeds, 1000 turns, crab-crossing production
    point) and `cpu_gpu_timing_summary.tsv` (thread sweep + observer A/B).
  - Tune-estimator calibration: `../validation/tune_estimator_calibration.jl`
    (500 synthetic two-tone trials).
  - Sec. 5.1 tune-swap control: `lambda_tuneswap_control.tsv`; Sec. 4.1
    reference-noise bound: `softgauss_count_scan.tsv`.
  - Sec. 5.4 crossing-angle dynamical cross-check:
    `multislice_centroids_{octopus_kicked,bb3d}_crossing.tsv` (half angle
    3.855e-4, Piwinski phi=1; BB3D deck note: the deck field labeled
    "alpha" is the crossing-plane azimuth - PHI is the half angle);
    9-slice convergence run `multislice_centroids_octopus_kicked_n9.tsv`.
- Tables 2-4 values come from the runs recorded in the paper text and the
  validation logs; Table 1 numbers are exactly `flat_beam_noise_floor.tsv`.
