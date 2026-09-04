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
  - Physics keywords: `:thin_element`, `:lorentz_boost`, `:coordinate_transform`, `:quasi_symplectic`
  - Supported tracking methods: `NonSymplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `NonSymplectic6DMap => LorentzBoost`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:rev_lorentz_boost}` via `RevLorentzBoostSpec`
  - Physics keywords: `:thin_element`, `:reverse_lorentz_boost`, `:coordinate_transform`, `:quasi_symplectic`
  - Supported tracking methods: `NonSymplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `NonSymplectic6DMap => RevLorentzBoost`
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

- `ElementSpec{:drift}` via `DriftSpec`
  - Physics keywords: `:lattice_magnet`, `:thick_element`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`, `PTCConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `Symplectic6DMap => LatticeMagnet`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:quadrupole}` via `QuadrupoleSpec`
  - Physics keywords: `:lattice_magnet`, `:thick_element`, `:nonlinear_interaction`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`, `PTCConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `Symplectic6DMap => LatticeMagnet`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:sextupole}` via `SextupoleSpec`
  - Physics keywords: `:lattice_magnet`, `:thick_element`, `:nonlinear_interaction`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`, `PTCConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `Symplectic6DMap => LatticeMagnet`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:octupole}` via `OctupoleSpec`
  - Physics keywords: `:lattice_magnet`, `:thick_element`, `:nonlinear_interaction`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`, `PTCConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `Symplectic6DMap => LatticeMagnet`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:multipole}` via `MultipoleSpec`
  - Physics keywords: `:lattice_magnet`, `:thick_element`, `:nonlinear_interaction`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`, `PTCConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `Symplectic6DMap => LatticeMagnet`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:sbend}` via `SBendSpec`
  - Physics keywords: `:lattice_magnet`, `:thick_element`, `:coordinate_transform`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`, `PTCConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `Symplectic6DMap => LatticeMagnet`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:marker}` via `MarkerSpec`
  - Physics keywords: `:thin_element`, `:placeholder`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `Symplectic6DMap => Marker`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:thin_multipole}` via `ThinMultipoleSpec`
  - Physics keywords: `:lattice_magnet`, `:thin_element`, `:nonlinear_interaction`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`, `PTCConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `Symplectic6DMap => ThinMultipole`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:thin_dipole}` via `ThinDipoleSpec`
  - Physics keywords: `:lattice_magnet`, `:thin_element`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`, `PTCConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `Symplectic6DMap => ThinMultipole`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:thin_quadrupole}` via `ThinQuadrupoleSpec`
  - Physics keywords: `:lattice_magnet`, `:thin_element`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`, `PTCConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `Symplectic6DMap => ThinMultipole`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:thin_sextupole}` via `ThinSextupoleSpec`
  - Physics keywords: `:lattice_magnet`, `:thin_element`, `:nonlinear_interaction`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`, `PTCConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `Symplectic6DMap => ThinMultipole`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:hkicker}` via `HKickerSpec`
  - Physics keywords: `:lattice_magnet`, `:thin_element`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `Symplectic6DMap => ThinMultipole`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:vkicker}` via `VKickerSpec`
  - Physics keywords: `:lattice_magnet`, `:thin_element`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `Symplectic6DMap => ThinMultipole`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:kicker}` via `KickerSpec`
  - Physics keywords: `:lattice_magnet`, `:thin_element`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `Symplectic6DMap => ThinMultipole`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:solenoid}` via `SolenoidSpec`
  - Physics keywords: `:lattice_magnet`, `:thick_element`, `:coordinate_transform`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`, `SymplecticityContract`, `PTCConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `Symplectic6DMap => Solenoid`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:patch}` via `PatchSpec`
  - Physics keywords: `:coordinate_transform`, `:thin_element`
  - Supported tracking methods: `NonSymplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `NonSymplectic6DMap => Patch`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:thin_rf_cavity}` via `ThinRFCavitySpec`
  - Physics keywords: `:harmonic`, `:thick_element`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `Symplectic6DMap => ThinRFCavity`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:thin_accelerating_cavity}` via `ThinAcceleratingCavitySpec`
  - Physics keywords: `:harmonic`, `:thick_element`, `:acceleration`, `:quasi_symplectic`
  - Supported tracking methods: `NonSymplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `NonSymplectic6DMap => ThinAcceleratingCavity`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:line}` via `BeamLine`
  - Physics keywords: `:beam_line`, `:thick_element`
  - Supported tracking methods: `[]`
  - Required contracts: `[]`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `[]`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:aperture}` via `ApertureSpec`
  - Physics keywords: `:thin_element`, `:collimation`, `:particle_loss`
  - Supported tracking methods: `NonSymplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `NonSymplectic6DMap => Aperture`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

## Tracking Methods

- `Damping6DMap`
- `Diffusion6DMap`
- `NonSymplectic6DMap`
- `Radiation6DMap`
- `Symplectic6DMap`
- `WeakStrongBeamBeamMap`

## Strong-Strong Solvers

- `GaussianPICPoissonSolver`
  - Construction metadata: `solver_option_schema`, `solver_help`
- `GaussianPoissonSolver`
  - Construction metadata: `solver_option_schema`, `solver_help`
- `PICPoissonSolver`
  - Construction metadata: `solver_option_schema`, `solver_help`
- `SpectralPoissonSolver`
  - Construction metadata: `solver_option_schema`, `solver_help`

## Execution Policies

- `AbstractGPUExecutionPolicy`
- `CUDAExecutionPolicy`
- `GPUExecutionPolicy`
- `CPUThreadsExecutionPolicy`
- `MultiProcessExecutionPolicy`
- `PlaceholderPolicy`

## Contracts

- `AbstractImplementationContract`
- `AbstractBackendConsistencyContract`
- `ElementTrackingBackendConsistencyContract`
- `StrongStrongGaussianBackendConsistencyContract`
- `StrongStrongPICBackendConsistencyContract`
- `ElementParameterEffectivenessContract`
- `KnobEffectivenessContract`
- `MADXSurveyConsistencyContract`
- `PTCConsistencyContract`
- `PublicConfigurationEffectivenessContract`
- `SolverOptionEffectivenessContract`
- `AbstractPhysicsContract`
- `CoherentModePhysicsContract`
- `HighEnergyWeakStrongLimitContract`
- `SymplecticityContract`

## Analyses

- `PlaceholderAnalysis`

## Examples

- `BenchmarkExample`
- `ReferenceExample`
- `ResearchStudyExample`

## Tasks

- `StrongStrongTask`
- `TrackingTask`

## Task Diagnostics

- `StrongStrongDiagnostics`
  - Construction metadata: `diagnostics_option_schema`, `diagnostics_help`

## Knob Control

- `@knob`, `@knob_expr`, `knobs`/`KnobNamespace` (plain-assignment access),
  `set_knob!`, `knob_value` (deferred parameter expressions stored as
  data; see `docs/knob_control.md`)
  - Introspection: `list_knobs`, `knob_report`, `knob_dependencies`,
    `knob_dependents`
  - Symbolic layer: `knob_derivative`, `knob_to_expr`/`knob_expression`,
    `knob_symbolic`/`knob_from_symbolic` (optional Symbolics.jl adapter;
    `knob_symbolics_available` reports whether it is active)
  - Element binding: construction-time (`param=@knob_expr(...)`) or
    post-construction (`spec.param = @knob_expr(...)`)
  - Runtime consumer: `compile_runtime` via `resolve_knobs`; verified by
    `KnobEffectivenessContract`

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
- `LatticeMagnet`
- `Marker`
- `ThinMultipole`
- `Solenoid`
- `Patch`
- `ThinRFCavity`
- `ThinAcceleratingCavity`
- `Aperture`
- `BeamParams`
- `Phase6DRep`
- `Beam`
- `MisalignedElement`
- `RefTilted`
- `CompositeLine`
