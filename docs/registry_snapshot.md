# Octopus Registry Snapshot

This file is generated from the live Octopus registry and element metadata.

Regenerate it from the project root with:

```julia
include("src/Octopus.jl")
using .Octopus
write_registry_snapshot()
```

Element specs are registered as flexible `ElementSpec{kind}` types. Friendly
constructor names remain the user-facing way to build those specs.

## Element Specs

- `ElementSpec{:crab_dispersion}` via `CrabDispersionSpec`
  - Physics keywords: `:crab_dispersion`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `Symplectic6DMap => CrabDispersion`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:momentum_dispersion}` via `MomentumDispersionSpec`
  - Physics keywords: `:momentum_dispersion`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `Symplectic6DMap => MomentumDispersion`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:xy_coupling}` via `XYCouplingSpec`
  - Physics keywords: `:xy_coupling`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `Symplectic6DMap => XYCoupling`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:linear6d}` via `Linear6DSpec`
  - Physics keywords: `:coordinate_transform`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `Symplectic6DMap => Linear6D`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:thin_crab_cavity}` via `ThinCrabCavitySpec`
  - Physics keywords: `:thin_element`, `:crab_cavity`, `:harmonic`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `Symplectic6DMap => ThinCrabCavity`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:lorentz_boost}` via `LorentzBoostSpec`
  - Physics keywords: `:thin_element`, `:lorentz_boost`, `:coordinate_transform`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `Symplectic6DMap => LorentzBoost`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:rev_lorentz_boost}` via `RevLorentzBoostSpec`
  - Physics keywords: `:thin_element`, `:reverse_lorentz_boost`, `:coordinate_transform`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `Symplectic6DMap => RevLorentzBoost`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:chromaticity_kick}` via `ChromaticityKickSpec`
  - Physics keywords: `:thin_element`, `:coordinate_transform`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `Symplectic6DMap => ChromaticityKick`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:lumped_radiation}` via `LumpedRadSpec`
  - Physics keywords: `:thin_element`, `:radiation`
  - Supported tracking methods: `Radiation6DMap`, `Damping6DMap`, `Diffusion6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `Radiation6DMap => LumpedRad`, `Damping6DMap => LumpedRad`, `Diffusion6DMap => LumpedRad`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:thin_strong_beam}` via `ThinStrongBeamSpec`
  - Physics keywords: `:beam_beam`, `:nonlinear_interaction`
  - Supported tracking methods: `WeakStrongBeamBeamMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `WeakStrongBeamBeamMap => ThinStrongBeam`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:gaussian_strong_beam}` via `GaussianStrongBeamSpec`
  - Physics keywords: `:beam_beam`, `:nonlinear_interaction`
  - Supported tracking methods: `WeakStrongBeamBeamMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `WeakStrongBeamBeamMap => GaussianStrongBeam`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

## Tracking Methods

- `Damping6DMap`
- `Diffusion6DMap`
- `Radiation6DMap`
- `Symplectic6DMap`
- `WeakStrongBeamBeamMap`

## Execution Policies

- `CPUThreadsExecutionPolicy`
- `GPUExecutionPolicy`
- `PlaceholderPolicy`

## Contracts

- `AbstractImplementationContract`
- `AbstractBackendConsistencyContract`
- `ElementTrackingBackendConsistencyContract`
- `StrongStrongGaussianBackendConsistencyContract`
- `StrongStrongPICBackendConsistencyContract`
- `AbstractPhysicsContract`

## Analyses

- `PlaceholderAnalysis`

## Examples

- `BenchmarkExample`
- `ReferenceExample`
- `ResearchStudyExample`

## Tasks

- `StrongStrongTask`
- `TrackingTask`

## Runtime Objects

Runtime element objects live under `src/elements/`. Generic tracking helpers
live under `src/track/`.

- `CrabDispersion`
- `MomentumDispersion`
- `XYCoupling`
- `Linear6D`
- `ThinCrabCavity`
- `LorentzBoost`
- `RevLorentzBoost`
- `ChromaticityKick`
- `LumpedRad`
- `ThinStrongBeam`
- `GaussianStrongBeam`
- `BeamParams`
- `Phase6DRep`
- `Beam`
