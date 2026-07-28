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
- Tables 2-4 values come from the runs recorded in the paper text and the
  validation logs; Table 1 numbers are exactly `flat_beam_noise_floor.tsv`.
