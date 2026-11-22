# The strong beam as one element, stage 1 (2026-11-22)

Stage 1 of [`../design/strong_beam_element.md`](../design/strong_beam_element.md),
decided with the owner on 2026-11-21 and 2026-11-22: `GaussianStrongBeamSpec`
takes the strong beam's own parameters and a `LinearOptics` point directly,
`thin =` stays accepted, the stored spec does not change, and the user's slice
offsets get their own two functions (S3, the owner's design). The CI run of the push before this batch
(ee62d3e..ee46879, the `XY_UNDEF` retirement and the D15 docs): run 482 (id
44984169999) completed with success at 2026-11-22T05:14:21Z.

## 1 What changed

- `GaussianStrongBeamSpec{T}(; kbb, klum, optics | beta/alpha/sigma |
  covariance (4 x 4), coupling, center, angle, curvature, virtual_drift,
  sigma_delta, ns, sigz, ...)`: the constructor builds the
  `ThinStrongBeamSpec{T}` itself and stores it as `thin`, so the new form and
  the `thin =` form build one spec, bit for bit; `thin =` beside any of the
  strong beam's own parameters is refused by name, as is a spec with neither.
  `covariance` is the slice's 4 x 4 or the sliced Gaussian's 6 x 6, by size.
- A `LinearOptics` point carrying dispersion is consumed at the slice level
  (S2): with `sigz` and the new keyword `sigma_delta` the intrinsic transverse
  covariance and the longitudinal one make the 6 x 6 through
  `gaussian_strong_beam_covariance`, which until now nothing in the source
  called; the kernel takes the point without its dispersion. Refused by name:
  a dispersive point without `sigma_delta` or `sigz`, `sigma_delta` beside a
  point without dispersion, a dispersive point beside an explicit 6 x 6.
- S3: `offset_slices!(spec, shape; mode)` and `offset_slices(spec, shape;
  mode)`, exported, write the user's per-slice offsets (`:add` accumulates,
  `:replace` resets) from a `NamedTuple` of per-slice tuples, a function
  `z -> (x, px, y, py)` or the crab-waveform `Dict`; they freeze the slicing
  into the spec, fold a stored legacy `hvoffset` into the tuples and store
  numbers only. The covariance's crab slope, the bunch's own tilt, is added at
  compile regardless. The constructor keeps `hvoffset` and `slice_*offset`
  as the legacy spelling for this batch. A first draft of this batch added
  the three sources inside the constructor and refused a waveform whose
  weights do not sum to one beside a crab slope; the owner replaced that rule
  with the two functions before the batch was gated.
- S5: `mean` beside `center` or `angle` of the recommended form is refused by
  name; `mean` with `thin =` is unchanged.
- `ThinStrongBeamSpec` is unchanged (S4). The docstring, the `thin` and
  `covariance` meanings and the construction help present the recommended
  form; `docs/public_api.md` names `GaussianStrongBeamSpec(; optics=)` as the
  strong-beam consumer.
- Call sites moved to the recommended form: `examples/weak_strong_tracking.jl`,
  `examples/crab_cavity_noise.jl`, their two harnesses,
  `validation/tracking_backend_consistency.jl` and
  `profiling/benchmark_track_cpu.jl`; the weak-strong catalogue entry lists
  `GaussianStrongBeamSpec` in place of `ThinStrongBeamSpec`.
  `validation/strong_beam_kick_fingerprint.jl` and
  `validation/gaussian_slicing_convergence.jl` keep `thin =` until stage 2
  (their recorded fingerprints are of the stored spec, which is unchanged).
- Tests: "Strong beam element stage 1 (docs/design/strong_beam_element.md
  S1-S5)": both spellings bit for bit (typed and untyped, the 4 x 4 route,
  the point route); `ns = 1` equal to the thin element compiled and tracked;
  every refusal; the dispersive point's 6 x 6 against the helper, the slices
  tilted by the slope and widened by the conditional covariance; the two
  offset functions (`:add`, `:replace`, the three shapes, the frozen slicing,
  the folded legacy `hvoffset`, the untouched argument of the copying form,
  the tilt surviving `:replace`, every refusal) and the waveform's zero linear
  part for weights summing to one; the `mean` rule; the help.

## 2 Verification

- `validate_element_metadata()` and `validate_configuration_metadata()` pass;
  `element_help(:gaussian_strong_beam)` names `sigma_delta`, `thin=`, the
  recommended form and `offset_slices`; the regenerated snapshot differs from
  the committed one by the two exports and the weak-strong example's objects
  only, and is committed.
- Extracted from the suite (2026-11-22, 00:49 to 01:15 EST; the blocks cut
  out by title after `using Octopus`): "Strong beam element stage 1" (47 of 47
  after three fixes to its own first draft: the untyped identity, which led to
  the kernel following the element's typing in the untyped form; a comparison
  of two mutable runtime structs by identity; a tolerance on the waveform's
  own tilt), "hvoffset keys are validated by name and the Float32 Gaussian
  with hvoffset compiles in Float32 (F-122, F-123)" (12), "The strong beam's
  inert longitudinal components and a degenerate transverse covariance are
  refused by name" (19), "Conditional 6D Gaussian strong-beam slicing" (13),
  "The strong beam's momentum dispersion is canonical" (19), "One precision
  rule" (652), "Cross-backend rounding classes declared per kind and checked
  by measurement" (204), "LinearOptics: the shared optics object feeds every
  consumer by one flattening rule" (114), "the Example core object answers
  with real scripts" (52), and the five sweeps (Core.Box 5, every export
  documented 1, detached docstrings 11, every export in the snapshot 17,
  Architecture integrity 49). The Stage 9 DBA-ring block needs a file-level
  helper and runs in the gate.
- `validation/tracking_backend_consistency.jl` with the GPU contract required
  (its Gaussian case in the self-contained form): "tracking backend
  consistency validation complete", exit 0.
- `validation/strong_beam_kick_fingerprint.jl` (unchanged, `thin =`): every
  case's fused and elementwise digests equal, exit 0; the stored spec the two
  forms build is one and the same, so a converted case would print the same
  digests.
- `examples/weak_strong_tracking.jl` and `examples/crab_cavity_noise.jl` in
  the self-contained form at their shipped config, on CUDA: exit 0.

## 3 The gate

The batch changes a public constructor, element metadata, examples and a
validation script (the matrix: full, CUDA active; the kernels are unchanged).
The full gate ran on this batch's working tree after this record was written
and the tree was committed unchanged; its numbers are in the commit message.

## 4 Ledger

`docs/README.md`: the design note and this record. `docs/todo.md`: the new
row "One strong-beam element". `docs/registry_snapshot.md`: regenerated (the
weak-strong example's objects). The design note's section 3 names stages 2
and 3.
