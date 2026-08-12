# Paper Reproduction Package Migration (2026-08-12)

Owner decision: the publication is its own project, so the `paper/`
reproduction package moved to its own public repository,
https://github.com/xud929/2026_octopus_cpc, assembled from the audited
`paper/` tree and the manuscript of the frozen submission snapshot at
`~/Work/Daily/20260727_Octopus_paper/submission_candidate` (which stays
untouched as the archival record of what was submitted, with its own
`SHA256SUMS`).

## What went where

- **To the paper repository**: `data/` (184 files including the BeamBeam3D
  decks and their `PROVENANCE.md`), `make_figures.py`,
  `verify_manuscript_claims.py`, the package README (extended, provenance
  narrative intact), a copy of `manuscript/` from the submission snapshot,
  and eight paper-specific drivers under `drivers/` (`lambda_tunescan`,
  `lambda_flatxi`, `lambda_fixedxiy`, `lambda_narrowplane`, `emit_deriv`,
  `emit_gaussctrl`, `deriv_order_arm`, `mesh_study_driver`), converted from
  `include`-relative loading to the repository's own project environment,
  which pins Octopus by commit.
- **To `validation/`** (reusable correctness measurements, documented in
  `validation/README.md` "Paper Reproduction Drivers"):
  `lambda_round_converged.jl`, `lambda_flat_converged.jl`,
  `eic_emittance_benchmark.jl`, `emit_xcode.jl`, `noise_floor_meshswap.jl`,
  `kick_decomposition.jl`. Their outputs move from the package-local `data/`
  to the repo convention `result/` (with `mkpath`); the frozen archived
  copies live in the paper repository.
- **To `profiling/`**: `cuda_device_profile.jl` (Table 6's device-time
  decomposition) — a performance harness, not a validation.
- **Deleted**: `texput.log` (LaTeX debris).

## Findings on the way

- `verify_manuscript_claims.py` read the manuscript from a hard-coded
  absolute path into the owner's working directory — the package's
  self-containment claim ("no absolute paths") was false for exactly the
  script whose job is verifying claims. In the paper repository it reads
  `manuscript/main.tex` relatively, and manuscript and data are in one place
  for the first time.
- The submission snapshot's `supplement/` is an earlier generation of the
  package (five figures, different layout, `reproduction/{raw,derived}`
  data); it shares **no files** with the audited nine-figure package, so
  there was nothing to merge — the paper repository's package supersedes it,
  and the snapshot remains the record of what the journal received.

## Octopus-side reference updates

`validation/gaussian_pic_field_validation.jl`,
`validation/crossing_luminosity_anchor.jl`, and
`validation/coherent_mode_vlasov_theory.jl` cited `paper/...` paths in
comments; all now cite the paper repository. `validation/README.md` carries
the updated citations and the new driver section; the top-level `README.md`
gains a Publication section. The dated audit records that reference
`paper/...` paths describe the tree at the commits they audited and are
unchanged, per the convention that history is not retrofitted.
