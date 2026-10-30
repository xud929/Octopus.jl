# Octopus Registry Snapshot

This file is generated from the live Octopus registry, element metadata, and module exports.

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
  - Supported analyses: `TwissDispersionAnalysis`
  - Runtime mappings: `Symplectic6DMap => CrabDispersion`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:momentum_dispersion}` via `MomentumDispersionSpec`
  - Physics keywords: `:momentum_dispersion`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `TwissDispersionAnalysis`
  - Runtime mappings: `Symplectic6DMap => MomentumDispersion`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:xy_coupling}` via `XYCouplingSpec`
  - Physics keywords: `:xy_coupling`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `TwissDispersionAnalysis`
  - Runtime mappings: `Symplectic6DMap => XYCoupling`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:linear6d}` via `Linear6DSpec`
  - Physics keywords: `:coordinate_transform`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `TwissDispersionAnalysis`
  - Runtime mappings: `Symplectic6DMap => Linear6D`, `Symplectic6DMap => ParticleLinear6D`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:thin_crab_cavity}` via `ThinCrabCavitySpec`
  - Physics keywords: `:thin_element`, `:crab_cavity`, `:harmonic`, `:turn_modulation`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `TwissDispersionAnalysis`
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
  - Supported analyses: `TwissDispersionAnalysis`
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
  - Supported analyses: `TwissDispersionAnalysis`
  - Runtime mappings: `Symplectic6DMap => LatticeMagnet`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:quadrupole}` via `QuadrupoleSpec`
  - Physics keywords: `:lattice_magnet`, `:thick_element`, `:nonlinear_interaction`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`, `PTCConsistencyContract`
  - Supported analyses: `TwissDispersionAnalysis`
  - Runtime mappings: `Symplectic6DMap => LatticeMagnet`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:sextupole}` via `SextupoleSpec`
  - Physics keywords: `:lattice_magnet`, `:thick_element`, `:nonlinear_interaction`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`, `PTCConsistencyContract`
  - Supported analyses: `TwissDispersionAnalysis`
  - Runtime mappings: `Symplectic6DMap => LatticeMagnet`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:octupole}` via `OctupoleSpec`
  - Physics keywords: `:lattice_magnet`, `:thick_element`, `:nonlinear_interaction`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`, `PTCConsistencyContract`
  - Supported analyses: `TwissDispersionAnalysis`
  - Runtime mappings: `Symplectic6DMap => LatticeMagnet`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:multipole}` via `MultipoleSpec`
  - Physics keywords: `:lattice_magnet`, `:thick_element`, `:nonlinear_interaction`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`, `PTCConsistencyContract`
  - Supported analyses: `TwissDispersionAnalysis`
  - Runtime mappings: `Symplectic6DMap => LatticeMagnet`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:sbend}` via `SBendSpec`
  - Physics keywords: `:lattice_magnet`, `:thick_element`, `:coordinate_transform`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`, `PTCConsistencyContract`
  - Supported analyses: `TwissDispersionAnalysis`
  - Runtime mappings: `Symplectic6DMap => LatticeMagnet`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:marker}` via `MarkerSpec`
  - Physics keywords: `:thin_element`, `:placeholder`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `TwissDispersionAnalysis`
  - Runtime mappings: `Symplectic6DMap => Marker`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:thin_multipole}` via `ThinMultipoleSpec`
  - Physics keywords: `:lattice_magnet`, `:thin_element`, `:nonlinear_interaction`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`, `PTCConsistencyContract`
  - Supported analyses: `TwissDispersionAnalysis`
  - Runtime mappings: `Symplectic6DMap => ThinMultipole`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:thin_dipole}` via `ThinDipoleSpec`
  - Physics keywords: `:lattice_magnet`, `:thin_element`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`, `PTCConsistencyContract`
  - Supported analyses: `TwissDispersionAnalysis`
  - Runtime mappings: `Symplectic6DMap => ThinMultipole`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:thin_quadrupole}` via `ThinQuadrupoleSpec`
  - Physics keywords: `:lattice_magnet`, `:thin_element`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`, `PTCConsistencyContract`
  - Supported analyses: `TwissDispersionAnalysis`
  - Runtime mappings: `Symplectic6DMap => ThinMultipole`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:thin_sextupole}` via `ThinSextupoleSpec`
  - Physics keywords: `:lattice_magnet`, `:thin_element`, `:nonlinear_interaction`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`, `PTCConsistencyContract`
  - Supported analyses: `TwissDispersionAnalysis`
  - Runtime mappings: `Symplectic6DMap => ThinMultipole`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:hkicker}` via `HKickerSpec`
  - Physics keywords: `:lattice_magnet`, `:thin_element`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `TwissDispersionAnalysis`
  - Runtime mappings: `Symplectic6DMap => ThinMultipole`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:vkicker}` via `VKickerSpec`
  - Physics keywords: `:lattice_magnet`, `:thin_element`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `TwissDispersionAnalysis`
  - Runtime mappings: `Symplectic6DMap => ThinMultipole`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:kicker}` via `KickerSpec`
  - Physics keywords: `:lattice_magnet`, `:thin_element`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `TwissDispersionAnalysis`
  - Runtime mappings: `Symplectic6DMap => ThinMultipole`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:solenoid}` via `SolenoidSpec`
  - Physics keywords: `:lattice_magnet`, `:thick_element`, `:coordinate_transform`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`, `SymplecticityContract`, `PTCConsistencyContract`
  - Supported analyses: `TwissDispersionAnalysis`
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
  - Physics keywords: `:harmonic`, `:thick_element`, `:turn_modulation`
  - Supported tracking methods: `Symplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `TwissDispersionAnalysis`
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
  - Supported analyses: `TwissDispersionAnalysis`
  - Runtime mappings: `[]`
  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`

- `ElementSpec{:phase_space_reset}` via `PhaseSpaceResetSpec`
  - Physics keywords: `:phase_space_reset`, `:noise_response`
  - Supported tracking methods: `NonSymplectic6DMap`
  - Required contracts: `ElementTrackingBackendConsistencyContract`
  - Supported analyses: `PlaceholderAnalysis`
  - Runtime mappings: `NonSymplectic6DMap => PhaseSpaceReset`
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
- `StrongStrongPICMultiProcessConsistencyContract`
- `AnalysisOptionEffectivenessContract`
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
- `TwissDispersionIdentityContract`
- `TwissExternalReferenceContract`

## Analyses

- `PlaceholderAnalysis`
- `TwissDispersionAnalysis`

## Examples

The curated scripts of `example_catalog()` (categories: `BenchmarkExample`, `ReferenceExample`, `ResearchStudyExample`); resolve an
entry's script with `example_script_path`.

- `examples/strong_strong_tracking.jl` (`ReferenceExample`)
  - Objects: `StrongStrongTask`, `StrongStrongCollision`, `PICPoissonSolver`, `LongitudinalSlicing`, `Beam`
- `examples/weak_strong_tracking.jl` (`ReferenceExample`)
  - Objects: `TrackingTask`, `ThinStrongBeamSpec`, `ThinCrabCavitySpec`, `Beam`
- `examples/crab_cavity_noise.jl` (`ReferenceExample`)
  - Objects: `TrackingTask`, `ThinCrabCavitySpec`, `WhiteNoise`, `PinkNoise`, `SpectralNoise`, `TurnTable`, `TurnModulated`, `RunArtifact`
- `examples/knob_control.jl` (`ReferenceExample`)
  - Objects: `TrackingTask`, `ElementSpec`, `BeamLine`
- `examples/twiss_dispersion_dba_ring.jl` (`ReferenceExample`)
  - Objects: `TwissDispersionAnalysis`, `BeamLine`, `ThinRFCavitySpec`, `SBendSpec`

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
- `ParticleLinear6D`
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
- `PhaseSpaceReset`
- `Aperture`
- `BeamParams`
- `Phase6DRep`
- `Beam`
- `MisalignedElement`
- `RefTilted`
- `CompositeLine`
- `TurnModulated`

## Exported API

This alphabetical index includes every exported name, including source helpers,
queries, and lifecycle functions outside the architectural type registry.

- `@element_spec`, `@knob`, `@knob_expr`, `@sel_str`, `AMBIGUITY_KINDS`, `ANALYSIS_STATUSES`
- `AbstractAnalysis`, `AbstractAnalysisResult`, `AbstractBackendConsistencyContract`, `AbstractBeamAction`, `AbstractBeamObserver`, `AbstractContract`
- `AbstractElementSpec`, `AbstractExample`, `AbstractExecutionBackend`, `AbstractExecutionPolicy`, `AbstractGPUExecutionPolicy`, `AbstractImplementationContract`
- `AbstractKnobExpression`, `AbstractLinearizationMethod`, `AbstractOctopusObject`, `AbstractPhaseRep`, `AbstractPhysicsContract`, `AbstractPoissonSolver`
- `AbstractSchedule`, `AbstractTask`, `AbstractTrackOp`, `AbstractTrackingMethod`, `AbstractVirtualDrift`, `AlwaysSchedule`
- `AmbiguitySet`, `AnalysisOptionEffectivenessContract`, `Aperture`, `ApertureSpec`, `AtTurns`, `BPMObserver`
- `Beam`, `BeamLine`, `BeamParams`, `BeamSwapAction`, `BenchmarkExample`, `CLIGHT`
- `CPUThreadsBackend`, `CPUThreadsExecutionPolicy`, `CUDABackend`, `CUDAExecutionPolicy`, `CUDALaunchConfig`, `CUDAPICLaunchConfig`
- `ChromaticDrift`, `ChromaticityKick`, `ChromaticityKickSpec`, `CoherentModePhysicsContract`, `ComplexStepLinearization`, `ConfigurationEntry`
- `ConfigurationOptionMeta`, `ContractResult`, `CoordinateSnapshotObserver`, `CrabDispersion`, `CrabDispersionSpec`, `DETERMINATION_REASONS`
- `DETERMINATION_STATUSES`, `Damping6DMap`, `Determined`, `DiagnosticsOptionMeta`, `Diffusion6DMap`, `DriftSpec`
- `EMASS_EV`, `ElementMeta`, `ElementParameterEffectivenessContract`, `ElementSpec`, `ElementTrackingBackendConsistencyContract`, `EveryNSteps`
- `ExactHamiltonianDrift`, `ExecutionAudit`, `ExecutionAuditReceipt`, `FiniteDifferenceLinearization`, `FloorFrame`, `ForwardDiffLinearization`
- `GPUExecutionPolicy`, `GaussianPICPoissonSolver`, `GaussianPoissonSolver`, `GaussianStrongBeam`, `GaussianStrongBeamSpec`, `HKickerSpec`
- `HighEnergyWeakStrongLimitContract`, `HirataParaxialDrift`, `KickerSpec`, `KnobCall`, `KnobConst`, `KnobEffectivenessContract`
- `KnobNamespace`, `KnobRef`, `LATTICE_INTEGRATOR_ORDERS`, `LatticeMagnet`, `LineEntry`, `Linear6D`
- `Linear6DSpec`, `LinearizationProvenance`, `LinearizedMap`, `LongitudinalConvention`, `LongitudinalSlicing`, `LorentzBoost`
- `LorentzBoostSpec`, `LossRecord`, `LumpedRad`, `LumpedRadSpec`, `MADXSurveyConsistencyContract`, `ME0`
- `Marker`, `MarkerSpec`, `MisalignedElement`, `Moment`, `MomentFile`, `MomentObserver`
- `MomentOutput`, `MomentOutputFile`, `MomentumDispersion`, `MomentumDispersionSpec`, `MultiProcessExecutionPolicy`, `MultipoleSpec`
- `NonSymplectic6DMap`, `NormalMode`, `OctopusRegistry`, `OctupoleSpec`, `OpticsAnalysisError`, `OutputFile`
- `PATHLENGTH_DELTA`, `PICPoissonSolver`, `PMASS_EV`, `PTCConsistencyContract`, `ParamMeta`, `ParticleLinear6D`
- `Patch`, `PatchSpec`, `PathLengthDelta`, `Phase6DRep`, `PhaseSpaceReset`, `PhaseSpaceResetSpec`
- `PinkNoise`, `PlaceholderAnalysis`, `PlaceholderPolicy`, `PredicateSchedule`, `PublicConfigurationEffectivenessContract`, `QuadrupoleSpec`
- `RBendSpec`, `RE`, `RNG_PHILOX`, `RNG_SPLITMIX`, `Radiation6DMap`, `RefTilted`
- `ReferenceExample`, `ResearchStudyExample`, `RevLorentzBoost`, `RevLorentzBoostSpec`, `RunArtifact`, `SBendSpec`
- `SIGMA_PSIGMA`, `SQRT2`, `SQRT2PI`, `SQRTPI`, `ScheduledAction`, `ScheduledObserver`
- `Selector`, `SextupoleSpec`, `SigmaPsigma`, `Solenoid`, `SolenoidSpec`, `SolverOptionEffectivenessContract`
- `SolverOptionMeta`, `SpectralNoise`, `SpectralPoissonSolver`, `StrongStrongCollision`, `StrongStrongDiagnostics`, `StrongStrongGaussianBackendConsistencyContract`
- `StrongStrongGaussianPoissonSolver`, `StrongStrongPICBackendConsistencyContract`, `StrongStrongPICMultiProcessConsistencyContract`, `StrongStrongTask`, `StrongTransverseMoments`, `Symplectic6DMap`
- `SymplecticityContract`, `TIME_DELTA`, `TIME_ENERGY`, `TWOPI`, `TaskOutput`, `ThinAcceleratingCavity`
- `ThinAcceleratingCavitySpec`, `ThinCrabCavity`, `ThinCrabCavitySpec`, `ThinDipoleSpec`, `ThinMultipole`, `ThinMultipoleSpec`
- `ThinQuadrupoleSpec`, `ThinRFCavity`, `ThinRFCavitySpec`, `ThinSextupoleSpec`, `ThinStrongBeam`, `ThinStrongBeamSpec`
- `TimeDelta`, `TimeEnergy`, `TrackingContext`, `TrackingTask`, `TuneDistribution`, `TuneFunction`
- `TuneHistogram`, `TurnModulated`, `TurnTable`, `TwissDispersionAnalysis`, `TwissDispersionIdentityContract`, `TwissDispersionResult`
- `TwissExternalReferenceContract`, `UndeterminedQuantityError`, `UnsafeVirtualDrift`, `VKickerSpec`, `WeakStrongBeamBeamMap`, `WhiteNoise`
- `XYCoupling`, `XYCouplingMode`, `XYCouplingSpec`, `XY_MODEA`, `XY_MODEB`, `XY_UNDEF`
- `activate_policy!`, `add_offset!`, `allow_lost_particles`, `allowed_param_units`, `allowed_physics_keywords`, `ambiguity_set`
- `analysis_option_schema`, `analyze`, `aperture_names`, `apply_action!`, `backend_type`, `beam_initialization_option_schema`
- `beam_statistics`, `bpm_reading`, `build_registry`, `claim_rng_id!`, `clear_particle_tunes!`, `clear_phase_space_reset!`
- `collide!`, `collision_pair_batches`, `column_names`, `compile_runtime`, `configuration_report`, `construction_help`
- `convention_number`, `convert_longitudinal`, `coordinate_array`, `coordinate_arrays`, `count_dead`, `count_live`
- `counter_normal`, `counter_normal_pair`, `counter_philox4x32`, `counter_uint64`, `counter_uniform01`, `cuda_pic_launch_option_schema`
- `default_method`, `description`, `determined_value`, `diagnostic_summary`, `diagnostics_help`, `diagnostics_option_schema`
- `dispersion_interval`, `element_help`, `element_meta`, `entry_path`, `entry_tags`, `example_catalog`
- `example_script_path`, `example_spec`, `execute!`, `execution_receipts`, `faddeeva_w`, `faddeeva_w_approx`
- `faddeeva_w_approx_reim`, `faddeeva_w_upper_reim`, `finalize_observers!`, `find_entries`, `fusedTrack`, `fusedTrackLuminous`
- `gaussian_beambeam_kick`, `gaussian_slice_centers`, `gaussian_strong_beam_covariance`, `getparam`, `global_rng_method`, `global_rng_method_code`
- `global_rng_seed`, `hasparam`, `inverse_erf`, `is_ambiguous`, `is_determined`, `is_live`
- `kind`, `knob_dependencies`, `knob_dependents`, `knob_derivative`, `knob_epoch`, `knob_expression`
- `knob_from_symbolic`, `knob_report`, `knob_symbolic`, `knob_symbolics_available`, `knob_to_expr`, `knob_value`
- `knobs`, `line_entries`, `line_name`, `list_knobs`, `longitudinal_slices`, `loss_counts`
- `loss_record`, `loss_records`, `loss_summary`, `luminosity`, `matched_covariance`, `name`
- `next_rng_id!`, `normal_mode`, `numeric_type`, `observe!`, `observer_option_schema`, `octopus_normal`
- `octopus_normal_pair`, `octopus_uint64`, `octopus_uniform01`, `one_turn_matrix`, `param`, `parameter_schema`
- `params`, `particle_beta`, `particle_tune_tables`, `passed`, `phase_space_reset_summary`, `philox4x32_self_test`
- `physics_keywords`, `pic_phase_timings`, `policy_option_schema`, `prepare_line_observers!`, `prepare_observers!`, `read_beam_coordinates`
- `read_loss_record`, `readings`, `realize`, `reference_beta`, `reference_beta_gamma`, `reference_gamma`
- `reference_pair_residual`, `register_element_meta!`, `register_element_spec!`, `register_friendly_alias!`, `registered_element_specs`, `registry_snapshot_markdown`
- `required_contracts`, `requires_elementwise_tracking`, `reset_knobs!`, `reset_rng_id_counter!`, `resolve_knobs`, `rf_strength`
- `run_actions!`, `run_artifact_option_schema`, `run_observers!`, `runtime_examples`, `runtime_type`, `runtime_variants`
- `s_positions`, `schedule_option_schema`, `set_global_rng!`, `set_knob!`, `set_param!`, `should_run`
- `slicing_option_schema`, `solver_configuration`, `solver_help`, `solver_option_schema`, `spectral_turn_table`, `splitmix_normal`
- `splitmix_normal_pair`, `splitmix_uint64`, `splitmix_uniform01`, `strong_strong_task_option_schema`, `summarize_registry`, `supported_analyses`
- `supported_tracking_methods`, `survey`, `symbol`, `track!`, `track_particle`, `tracking_convention`
- `tracking_method`, `tracking_task_option_schema`, `transverse_covariance`, `turn_modulation_provenance`, `turn_timings`, `update`
- `update_line`, `validate`, `validate_configuration_metadata`, `validate_element_metadata`, `with_execution_audit`, `with_index_offset`
- `with_turn`, `write_beam_coordinates`, `write_loss_record`, `write_registry_snapshot`
