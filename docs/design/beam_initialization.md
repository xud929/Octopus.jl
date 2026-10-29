# Bounded random and Cartesian-grid beam initialization

Status (2026-10-29): implemented after two independent design reviews and
verified by the four-thread full gate with CUDA active and real MPI checks.
The [implementation and validation record](../history/audit_beam_initialization_2026_10_29.md)
contains the targeted checks and final gate receipts. The reviews
checked the numerical/API and metadata/consumer seams; their clarifications
are incorporated below.

## Scope and existing behavior

At the investigated starting tree, the public
`Beam(N, policy_or_backend, FloatT=Float64; ...)` constructors in
`src/beam/Beam.jl` always generated Gaussian coordinates. There was no
bounded uniform or Cartesian-grid beam constructor. The existing
`octopus_uniform01` counter RNG primitive supplies independent uniform draws;
it is a reusable building block, not an existing beam distribution option.

This change adds distributions through `Beam`, preserving its runtime
representation, physical `BeamParams`, execution policies, and Gaussian default.
It follows the AGENTS task rows “Add or modify a solver, policy, or public
option”, “Change public documentation or APIs”, “Change CUDA-reachable or
concurrent code”, and the targeted neighbour-audit protocol. Construction is
host-side, followed by a CUDA upload; tracking kernels need no new branches.

## API decision

```julia
# Existing calls retain their behavior; the explicit spelling is equivalent.
Beam(10_000, policy, Float64; distribution=:gaussian, beta=beta, emit=emit)

# A random sample in the physical six-dimensional box.
Beam(10_000, policy, Float64;
     distribution=:uniform, lower=lo, upper=hi, rng_id=17)

# A Cartesian grid has no positional macroparticle count.
Beam(policy, Float64; distribution=:grid,
     lower=lo, upper=hi, grid_size=(5, 3, 5, 3, 1, 1))
Beam(policy, Float64; distribution=:grid,
     lower=lo, upper=hi, grid_step=(dx, dpx, dy, dpy, 0, 0))
```

The no-count overload defaults to `distribution=:grid`; other distributions
require `N`. Supplying `N` with `:grid` is refused, even if it equals the
computed product. `grid_size` means **point counts**, not interval counts;
`grid_step` means coordinate spacing. Exactly one is required. These names
avoid overloading “steps” with two incompatible meanings.

All bounds, counts, and spacings are six-component tuples or vectors in
`(x, px, y, py, z, pz)` order. Positions are metres; momenta use Octopus's
existing normalized canonical coordinate convention. The bounds describe the
returned physical coordinates, not normalized Gaussian variables.

`npart`, `charge`, `mc2`, `E0`, and `r0` remain physical beam parameters.
`npart` defaults to the macroparticle count, including the derived grid product;
an explicit `npart` changes represented physical population, never grid size.

## Distribution semantics

### Gaussian

`:gaussian` remains the default on the count-taking constructor. Keep the
current draw, standardization, normalization, maps, offsets, RNG handling, and
floating-point operation order. Bounds and grid options are inactive and are
refused whenever supplied. Existing Gaussian acceptance is unchanged otherwise.

### Uniform random

Each coordinate is independently sampled from its specified interval. Draw
`u` through the existing counter RNG keyed by seed, method, turn zero,
beam stream, particle index, and coordinate index. Map it affinely to the
interval without centering, standardizing, clipping to Gaussian cutoffs, or
Twiss normalization. A fixed axis (`lower == upper`) returns that value.
Floating-point rounding can produce an endpoint even though the underlying
counter draw is in `(0,1)`; the guarantee is containment in `[lower, upper]`.
Clamp only final affine-rounding overshoots to these bounds; this is not
Gaussian truncation or sample standardization.

Retain the existing explicit `rng` override and deprecated `seed` behavior
for random beams. Counter draws are formed on the host and copied to the
requested backend, making CPU and CUDA construction identical. Explicit RNGs
carry no cross-backend reproducibility promise. An explicit RNG may draw on
its native storage; copy its draws to the host before affine mapping.
The uniform override must be an `AbstractRNG`; malformed overrides are refused
before policy activation. Errors inside a user-defined RNG are runtime failures.
Support Float32 and Float64
for the new distributions, matching the counter RNG's concrete draw methods.

### Cartesian grid

For `grid_size`, each nonconstant axis has at least two points, includes both
bounds, and uses uniform spacing `(upper-lower)/(count-1)`. A constant axis
requires count one; a nonconstant axis with count one is refused. This avoids
silently choosing an endpoint or midpoint for an underspecified axis.

For `grid_step`, nonconstant axes require positive finite spacing and an
integral number of intervals. Accept only roundoff-scale disagreement in
`(upper-lower)/step`: at most `min(1/4, 8eps(FloatT)*max(1, abs(ratio)))`
intervals. Resolve to an endpoint-inclusive range and record the realized
spacing. A constant axis requires zero spacing and resolves to one point.
A step that does not divide the span is refused; there is no truncated last
cell or silently extended bound.

The product of the six point counts determines the macroparticle count.
Order is Julia Cartesian order: `x` changes fastest, then `px`, `y`, `py`,
`z`, and `pz`. Each point occurs once. Validate the product and the six-array
storage-size arithmetic with checked integer operations before allocation.
Check the actual generated FloatT axis values are strictly increasing before
full coordinate allocation and policy activation, so a grid whose
spacing is below the coordinate type's resolution cannot contain duplicates.
Grid construction draws nothing and neither assigns nor claims an RNG stream.

## Validation and inactive options

All checks precede policy activation, RNG claims, and coordinate allocation.
Bounds must be finite real values, ordered componentwise, and representable
in FloatT. Refuse distinct input bounds that collapse to one converted value,
and spans whose subtraction overflows FloatT. A positive nonconstant-axis step
that converts to zero or infinity is refused. Counts must be positive
non-Bool integers; invalid shapes, missing bounds, unknown distributions,
overflowing products, and incompatible constructor forms fail by name.

Uniform and grid modes refuse non-default Gaussian optics and transforms:
`beta`, `alpha`, `sigma`, `emit`, `coupling`, `R`, `C`, `mode`, `eta`,
`zeta`, `initial_offset`, and `cutoff`. Neutral defaults remain accepted so
the constructor signatures stay compatible. Test neutrality on the original
values, before conversion can round a non-default request to a default.
Bounds on Gaussian and grid
controls on random modes are refused. Grid mode also refuses non-default
`rng`, `seed`, and `rng_id`; there is no silent RNG consumption or override.

The existing MPI constructor strategy is retained: construct the whole beam,
then take each rank's contiguous shard. The no-count grid overload must use
the same sharding path and keep `npart` as global physical population. This
costs a transient whole beam per rank; scalable distributed initialization
is outside this feature's scope.
Communicator and rank-count validation occurs after keyword checks but before
sampling for every distribution. Sharding precedes the successful receipt,
which still records the global count. A rank mismatch cannot claim a stream
or record a successful initialization.

## Metadata, receipts, and verification

Add `beam_initialization_option_schema()` for the five new keywords:
`distribution`, `lower`, `upper`, `grid_size`, and `grid_step`. Their
`ConfigurationOptionMeta` records declare defaults, valid/active cases,
backends, and the `:beam_initialization` consumer. Keep legacy optics metadata
outside this bounded feature rather than claiming it has been newly certified.
The schema explicitly scopes `distribution`'s default to the count-taking
constructor; its meaning also names the no-count default. Validate both actual
constructor defaults separately through their successful receipts.

At successful construction, record the actual distribution branch, converted
bounds, requested and resolved grid information, global macroparticle count,
coordinate type, and backend. `grid_size` records resolved point counts and
`grid_step` records realized spacing; `requested_grid_size` and
`requested_grid_step` preserve the request separately. Receipts remain transient execution-audit data;
the beam representation is unchanged. A refused constructor records no
initialization receipt. The configuration validator and existing
`PublicConfigurationEffectivenessContract` gain coverage for these options,
checking coordinates as well as receipts. A schema/constructor keyword
tripwire prevents an option from escaping coverage.
Negative controls must detect both missing receipts and correct-looking
receipts paired with wrong coordinates.

Required checks: preserve a pre-change Gaussian fingerprint; assert uniform
support, mean and variance with sampling-error tolerances, independent axes,
seed/stream repeatability and variation; enumerate small grids against an
independent Cartesian product; exercise every invalid/inactive case and stream
nonmutation; verify Float32/Float64 and CPU/CUDA parity; run one-rank and real
multi-rank sharding comparisons; and track both new distributions through a
small weak-strong line. Include consumer-effectiveness negative controls.

Finish with the configuration validator and effectiveness contract, targeted
neighbour audit (Gaussian, explicit RNG, MPI sharding, beam parameters and
storage conversion), backend-consistency scripts, source/docstring tripwires,
and the four-thread full gate with CUDA active. Record measurements, exact
commands and skipped checks in a new dated history note; index this note and
the record, update the live TODO row and reusable lessons. No benchmark speed
claim or changed accelerator-physics model is part of this feature.

## Rejected alternatives

- Standardize uniform coordinates like Gaussian coordinates: changes the
  specified support and couples particles through sample moments.
- Reuse Twiss/offset maps after generating the box: makes final bounds false.
- Use a positional `N` for grids: gives two authorities for one count.
- Silently truncate a spacing-based range: fails the upper-bound request.
- Introduce distribution runtime types or new execution policies: unnecessary
  for an initialization choice; `Beam` and `Phase6DRep` already carry the result.
- Add CUDA sampling kernels now: duplicates host construction and weakens exact
  initialization parity without a demonstrated startup bottleneck.
