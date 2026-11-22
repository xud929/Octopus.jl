# One strong-beam element: `GaussianStrongBeamSpec` self-contained

> Design note of the strong-beam consolidation, decided with the owner on
> 2026-11-21 and 2026-11-22 after the LinearOptics campaign
> ([`linear_optics.md`](linear_optics.md), whose open item 3 this note
> absorbs). Stage 1 is implemented by the batch this note opens; stages 2 and
> 3 are decided in outline and wait for their own batches.

## 1. The problem

The weak-strong strong beam is two public specs for one physical object.
`ThinStrongBeamSpec` is the zero-length kick of one rigid Gaussian slice
(the 4D beam-beam lens of every code), and `GaussianStrongBeamSpec` slices it
in z, taking the thin spec as its `thin` argument. Measured before this
design (2026-11-21):

- A `GaussianStrongBeamSpec` with `ns = 1` reproduces `ThinStrongBeamSpec`
  bit for bit, for `:equal_area` and `:sqrt_density`, on a 2000-particle beam
  through one collision. The thin spec is redundant as a user-facing concept;
  what remains of it is the per-slice kernel, which is internal.
- Dispersion was attached to the wrong level. For one slice at fixed z,
  momentum dispersion only widens the transverse covariance, which a physical
  `sigma` already contains, and crab dispersion shifts the centroid by zeta
  times the slice's own z, nothing at z = 0. Both appear only with slicing:
  per-slice offsets and a per-slice conditional covariance, which the
  Gaussian element's 6×6 `covariance` route already computes. The thin spec's
  refusal of a dispersive `LinearOptics` point was therefore at a level where
  dispersion cannot mean anything.
- The footprint of the thin spec as a public name: 28 mentions in `src/`, 44
  of its kind symbol, 45 of its runtime type, 76 in the suite, 9 in
  validation scripts, 4 in examples and harnesses, its own contracts,
  effectiveness probe, CUDA luminosity route and metadata.

## 2. Decisions

- **S1 The Gaussian element is self-contained (stage 1).**
  `GaussianStrongBeamSpec{T}(; ...)` takes the thin parameters directly:
  `kbb`, `klum`, the optics as a `LinearOptics` point (`optics`, the
  recommended spelling) or as `beta`/`alpha`/`sigma` or as a 4×4
  `covariance`, with `coupling`, `center`, `angle`, `curvature` and
  `virtual_drift`, beside `ns`, `sigz`, the slice options and `hvoffset`.
  `thin =` stays accepted and is exclusive with every thin parameter (refused
  by name beside any of them). The stored representation does not change:
  the constructor builds the `ThinStrongBeamSpec{T}` itself and stores it as
  `thin`, so every stored spec, every kick fingerprint and the runtime are
  untouched, and the new form and the `thin =` form build one spec exactly.
  `ns` stays required; `ns = 1` is the 4D case.
- **S2 A point's dispersion is consumed at the slice level.** When `optics`
  carries a nonzero `zeta` or `eta`, the constructor builds the 6×6
  covariance through `gaussian_strong_beam_covariance(transverse4,
  longitudinal2; crab_dispersion = zeta, momentum_dispersion = eta)`: the
  intrinsic transverse covariance from `beta`, `alpha`, `R` and `sigma`, and
  `longitudinal2 = diagm(sigz^2, sigma_delta^2)` from `sigz` and the new
  keyword `sigma_delta`, the strong beam's rms relative momentum spread. With
  a dispersive point `sigma` is the intrinsic (betatron) rms size and the
  physical size comes out larger by the dispersive term; without dispersion
  the two coincide and no 6×6 is built, so the spec equals today's. A
  dispersive point without `sigma_delta` is refused by name; `sigma_delta`
  without a dispersive point is refused by name, since nothing would read it;
  a dispersive point beside an explicit 6×6 `covariance` is refused by name
  (two sources of one covariance).
- **S3 Offsets: the bunch's tilt, and the user's through two functions.** A
  slice's centroid at compile is the covariance's crab slope times the slice
  centre, the bunch's own tilt (from a dispersive point's `zeta` or a given
  6×6), plus the user's stored per-slice offsets. The user's offsets are
  written by `offset_slices!(spec, shape; mode)` in place and
  `offset_slices(spec, shape; mode)` on a copy (the owner's design,
  2026-11-22, replacing an additive rule inside the constructor): `mode =
  :add` accumulates them, `:replace` resets them; `shape` is a `NamedTuple` of
  per-slice tuples, a function `z -> (x, px, y, py)` evaluated at the slice
  centres, or the crab-waveform `Dict` that `hvoffset` takes, the RF
  nonlinearity `coef (z - sum_h rel_h sin(h k z)/(h k))`. The functions store
  numbers, never a closure: the slicing is frozen into the spec
  (`slice_center`, `slice_weight`) and a stored legacy `hvoffset` is folded
  into the tuples, so the spec stays describable and `:replace` means what it
  says. The tilt is not an offset of the user's: `:replace` cannot remove it;
  removing the dispersion from the point does. No priority rule and no
  refusal: a waveform whose weights do not sum to one carries a linear tilt
  `coef (1 - sum_h rel_h) z` of its own, which is the user's to give or not
  (stated in the docstring). The constructor keeps `hvoffset` and
  `slice_*offset` for this batch as the legacy spelling of the same stored
  offsets (they add at compile exactly as before); stage 2 removes them.
- **S4 `ThinStrongBeamSpec` is unchanged in stage 1.** It keeps refusing a
  dispersive point; the Gaussian element consumes the dispersion and builds
  the thin kernel from the per-slice conditional covariance. Stage 2 adds the
  deprecation warning and may document the thin spec's dispersion as inert.
- **S5 `mean` beside `center` and `angle`.** The 6-vector `mean` and the pair
  `center`/`angle` are one quantity spelled twice; today `mean` silently
  replaces the thin spec's centre and angle. Stage 1 refuses `mean` beside a
  `center` or `angle` given to the self-contained form, keeps `mean` with
  `thin =` as before, and leaves its retirement to stage 2.

## 3. Stages

1. This batch: S1-S5 with `offset_slices!` and `offset_slices`; the examples,
   harnesses, validation and profiling scripts move to the self-contained
   form; the help and docstrings present it as the one strong-beam element.
2. Retire the public `ThinStrongBeamSpec` (a deprecation warning first, then
   the symbol-removal class), retire `mean`, retire the constructor's
   `hvoffset` and `slice_*offset` in favour of the two functions, consider
   `ns = 1` as a default.
3. Candidates: a turn-dependent offset through a scheduled task action (never
   the element), as the turn-modulation design already provides for cavities.

## 4. Verification of stage 1

The new form against `thin =` for the examples' parameters, bit for bit
(`params`, the compiled kernel, the tracked coordinates);
`validation/strong_beam_kick_fingerprint.jl` unchanged; the dispersive point
against the explicit 6×6 built by `gaussian_strong_beam_covariance`, bit for
bit; the offset rule (the sum, the refusal, the zero-slope tripwire); every
refusal by name; `validate_element_metadata()`, both `element_help` forms;
the full gate with CUDA active (the kernels are unchanged, the CUDA arm runs
the backend-consistency script).
