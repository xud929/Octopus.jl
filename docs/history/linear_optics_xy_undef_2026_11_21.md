# Retiring `XY_UNDEF` (2026-11-21)

The third batch of [`linear_optics_2026_11_21.md`](linear_optics_2026_11_21.md),
the owner item 2 of the design note's section 4, closed as its own commit at
the owner's choice (2026-11-21), since it removes an exported enum member.
Design: [`../design/linear_optics.md`](../design/linear_optics.md), D14.

## 1 What changed

- `XYCouplingMode` is `XY_MODEA = 1`, `XY_MODEB = 2`; `XY_UNDEF = 0` and its
  docstring are gone, and the export list with them. Zero coefficients in
  form 1 (the default) give the identity, the only meaning the member had; in
  form 2 they give the exchange of the transverse planes (V2 at R = 0 is the
  block swap), which the first extracted run of the LinearOptics testset
  pointed out when a pin claimed the identity for both forms.
- The three runtime branches on it: `track_particle(::Symplectic6DMap,
  ::XYCoupling, ...)`, `_inverse(::XYCoupling, ...)` (chromaticity_kick.jl)
  and `_cross_backend_rounding(::XYCoupling)`. The device code of every kind
  that carries an `XYCoupling` (`xy_coupling`, `chromaticity_kick`,
  `lumped_radiation`) loses one branch.
- `_check_undef_coefficients` (the D8 refusal of nonzero coefficients beside
  `XY_UNDEF`) and its three call sites (`XYCouplingSpec{T}`, the `XYCoupling`
  inner constructor, `Beam`'s Gaussian path); the determinant check no longer
  carries the mode condition.
- Docstrings and metadata: the `XYCouplingMode` and `XYCoupling` docstrings,
  the `Beam` docstring's sentence, the `mode` ParamMeta's meaning and its
  derivation comment (the alternatives stay derived from the enum).
- Tests: the D8 refusals in the LinearOptics testset and the F-97 metadata
  testset became D14 pins (no `XY_UNDEF` binding, the enum's two instances,
  `XYCouplingMode(0)` refused, zero coefficients the identity in form 1 and
  the plane exchange in form 2).
- Ledgers: this record, the README entries, the todo row, the design note's
  section 4, one experiences lesson, the registry snapshot (the Exported API
  index loses the name).

Repo-wide grep before the change (`XY_UNDEF`, case-sensitive): src/ (Beam.jl
2, linear_maps.jl 11, chromaticity_kick.jl 1), test/runtests.jl (9), docs/
(registry_snapshot.md, README.md, todo.md, design/linear_optics.md; the frozen
history records keep their mentions), nothing under examples/, validation/,
profiling/, ext/.

## 2 Verification

- After the patch, `grep -rn XY_UNDEF` over the repository finds the name
  only where it is spoken of: the enum and mode docstrings and the metadata
  comment that record the retirement, the design note (D8's history and D14),
  the README, the todo row, the experiences lesson, this record, the tests'
  D14 pins, and the frozen history records (one of them,
  `comprehensive_audit_2026_08_05_b_unit_reports/p2_symplecticity.jl`, a
  reproduction script that would no longer run as written; frozen records are
  not rewritten). `isdefined(Octopus, :XY_UNDEF)` is false and
  `instances(XYCouplingMode)` is `(XY_MODEA, XY_MODEB)`.
- `validate_element_metadata()` and `validate_configuration_metadata()` pass;
  `write_registry_snapshot()` changed the Exported API index only (the name
  gone, the index re-flowed), and the regenerated snapshot is committed.
- Extracted from the suite after the change (2026-11-21, 20:01 to 20:17
  EST): "LinearOptics: the shared optics object feeds every consumer by one
  flattening rule" (114; its first run failed one new pin, which claimed the
  identity for zero coefficients in form 2 -- form 2 at R = 0 is the plane
  exchange -- and the pin, the docstrings, the metadata, the design note and
  this record were corrected before the second run), "Owner items 1, 4, 5"
  (49), the F-97 metadata testset (49: the derived alternatives equal the two
  instances, `XYCouplingMode(0)` refused), "Linear6D rejects non-symplectic
  matrices" (17), "Cross-backend rounding classes declared per kind and
  checked by measurement" (204), "CUDA surveyed cavity matches CPU within its
  derived rounding class" (13), "CUDA tracks a wrapped strong beam elementwise
  and matches CPU within its declared rounding class" (96), the two Beam
  refusal testsets (16, 36), the five sweeps (Core.Box 5, every export
  documented 1, detached docstrings 11, every export in the snapshot 17,
  Architecture integrity 49 with the regenerated snapshot). The Edwards-Teng
  coupled-construction testset needs file-level helpers and runs in the gate.
- `validation/tracking_backend_consistency.jl` with the GPU contract
  required, CPU and CUDA: "tracking backend consistency validation complete",
  exit 0, every case passed, the 36 per-kind rounding-class instances within
  their declared classes on CPU/CPU and CPU/GPU; the `XYCoupling` kernel lost
  its identity branch on both backends.

## 3 The gate

Symbol removal and CUDA-reachable code (the matrix: full, CUDA active). The
full gate ran on this batch's working tree after this record was written and
the tree was committed unchanged; its numbers are in the commit message.

## 4 Ledger and the previous batch's CI

The owner-items batch pushed before this one (9f3c8c3..ee62d3e, 2026-11-21 20:00 EST):
CI run 481 (id 44969418853) completed with success at 2026-11-22T02:41:56Z, the CPU full
lane on the GitHub runner standing in for the AVX2 parity arm as on 2026-11-03; its
annotations report the stage 6 identity pins 6/6 and 5/6 on a znver3 runner, the runner's
own table (the two runs before it reported sapphirerapids).
