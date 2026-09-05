# Octopus Docstring Entry Points

Source docstrings and generated metadata are the public API reference. Use this
file only as a map to the right help query.

## Load Octopus

```julia
include("src/Octopus.jl")
using .Octopus
```

## Discover Objects

```julia
summarize_registry()
build_registry()
```

The generated inventory is `docs/registry_snapshot.md`. Regenerate it with:

```julia
write_registry_snapshot()
```

## Construct Elements

Start with:

```julia
element_help()
element_help(:thin_crab_cavity)
element_help(ThinCrabCavitySpec)
```

Then use focused metadata queries when needed:

```julia
parameter_schema(ThinCrabCavitySpec)
example_spec(ThinCrabCavitySpec)
construction_help(ThinCrabCavitySpec)
supported_tracking_methods(ThinCrabCavitySpec)
```

For the element development pattern, use Julia help:

```julia
?ElementSpec
?@element_spec
?ParamMeta
?ElementMeta
```

## Build And Execute Tracking Workflows

Use Julia help:

```julia
?TrackingTask
?StrongStrongTask
?CPUThreadsExecutionPolicy
?MultiProcessExecutionPolicy
?CUDAExecutionPolicy
?CUDALaunchConfig
?CUDAPICLaunchConfig
?policy_option_schema
?cuda_pic_launch_option_schema
?configuration_report
?ExecutionAudit
?with_execution_audit
?execution_receipts
?validate_configuration_metadata
?StrongStrongDiagnostics
?DiagnosticsOptionMeta
?diagnostics_option_schema
?diagnostics_help
?turn_timings
?pic_phase_timings
?diagnostic_summary
?StrongStrongCollision
?GaussianPoissonSolver
?PICPoissonSolver
?SpectralPoissonSolver
?GaussianPICPoissonSolver
?SolverOptionMeta
?solver_option_schema
?solver_configuration
?solver_help
?LongitudinalSlicing
?longitudinal_slices
?AbstractPoissonSolver
?execute!
?TrackingContext
?ScheduledObserver
?ScheduledAction
?EveryNSteps
?AtTurns
?schedule_option_schema
?observer_option_schema
?Moment
?MomentObserver
?MomentOutput
?column_names
?name
?symbol
?RunArtifact
?TaskOutput
```

Runnable examples live in `examples/` and are self-documenting at the top of
each source file. They are clean precedents with a small top-of-file `config`
block; the matching configurable developer harnesses (driven by `OCTOPUS_*`
environment variables) live in `test/examples/`.

A task's outputs land in ONE run artifact — an HDF5 file the task carries
(`artifact = RunArtifact(path)` or `artifact = path` on `TrackingTask` and
`StrongStrongTask`; design note `docs/design/run_artifact.md`). Probes are
named views into it: `MomentObserver(; name = ...)`,
`CoordinateSnapshotObserver(; name = ...)`, `BPMObserver(...; artifact =
true)`. Common access pattern:

Use `?MomentObserver`, `?Moment`, `?MomentOutput`, `?column_names`,
`?name`, `?symbol`, `?RunArtifact`, and `?TaskOutput` for the complete
output API docstrings. This section is the quick entry point.

```julia
observer = MomentObserver(; name = "proton",
    orders = 1:2,
    extra = (Moment(; pz=4),),
    exclude = (Moment(; z=2),),
)
# ... place it in the line, run the task with artifact = "result/pic_hcc.h5"

moments = MomentOutput("result/pic_hcc.h5"; name = "proton")
data = read(moments)               # column 1 is turn
turns = read(moments, :turn)        # same values as data[:, 1]
mx = read(moments, Moment(; x=1))
sxpx = read(moments, :m110000)
first_second = read(moments; orders = 1:2)
names = column_names(moments)

out = TaskOutput("result/pic_hcc.h5")
read(out)                                 # recursive contents: columns/rows/s per group
read(out, :luminosity; name = "ip")       # one collision's (turn, value)
read(out, :moments; name = "proton", column = Moment(; x = 1))
read(out, :moments; name = "proton", orders = 1:2)   # selection, MomentObserver rules
read(out, :bpm; name = "BPM_07", column = :x)
read(out, :snapshot; name = "inj", turn = 100)
read(out, :losses)                        # rows + apertures + summary
read(out, :execution)                     # per-execute! ledger
read(out, :all)                           # everything, nested by kind
```

Moment names are canonical strings such as `m100000`; if any exponent is
multi-digit, separator form is used, such as `m10_0_0_0_0_0`. The execution
ledger records start turn, planned window, current turn and elapsed wall
time per `execute!`, updated at every flush — live progress from one file.

Developer-facing numerical checks live in `validation/`. They may use internal
helpers and should not be treated as public API examples.
For the physics/method theory behind the beam-beam solvers (longitudinal-kick
formulas and virtual-drift conventions, the weak-strong source model, and the
spectral and Gaussian-subtracted PIC solvers), see the theory notes indexed in
`docs/README.md`, starting from `docs/theory/beam_beam_longitudinal_kick.md`.

## Knob Control

Deferred parameter expressions over named knobs; design note in
`docs/knob_control.md`. Use Julia help:

```julia
?@knob
?@knob_expr
?knobs
?KnobNamespace
?set_knob!
?knob_value
?resolve_knobs
?knob_report
?knob_dependencies
?knob_dependents
?knob_derivative
?knob_symbolic
?knob_from_symbolic
?knob_symbolics_available
?KnobEffectivenessContract
```

## Beam And Runtime Helpers

Use Julia help:

```julia
?Beam
?Phase6DRep
?beam_statistics
?write_beam_coordinates
?read_beam_coordinates
?track_particle
?compile_runtime
?runtime_type
?tracking_method
?TrackingContext
?with_turn
```

## Particle Loss

A non-finite coordinate means a **bug** by default, and every solver chokepoint
fails fast on one. `allow_lost_particles` is the scoped opt-out that reinterprets
it as a *lost particle*: reductions skip the particle and divide by the live
count instead of stopping the run. A particle is live only when all six
coordinates are finite.

```julia
?allow_lost_particles
?is_live
?count_live
?count_dead
```

An `ApertureSpec` is the element that loses particles deliberately: it kills what
is outside its acceptance by marking all six coordinates non-finite, counts what
it killed, and — when given a record — logs the pre-kill coordinates so a loss is
still interpretable after the particle is gone. Loss position is resolved only to
where you place apertures, so guard both faces of a magnet with two of them.

`loss_summary` reports the beam-wide dead count and the aperture-attributed total
separately. The gap between them is particles that went non-finite with no
aperture responsible, which is the diagnostic that keeps a numerical blowup
distinguishable from collimation.

```julia
?ApertureSpec
?LossRecord
?loss_records
?loss_counts
?loss_summary
?write_loss_record
?read_loss_record
```

## Numerical Math Helpers

Use Julia help:

```julia
?counter_philox4x32
?set_global_rng!
?global_rng_seed
?global_rng_method
?global_rng_method_code
?next_rng_id!
?reset_rng_id_counter!
?octopus_normal
?counter_uint64
?counter_uniform01
?counter_normal_pair
?counter_normal
?splitmix_uint64
?splitmix_uniform01
?splitmix_normal_pair
?splitmix_normal
?faddeeva_w
?faddeeva_w_approx_reim
```

Implementation details that are expected to evolve are summarized in
`docs/current_runtime.md`.

## Validation

The package regression suite runs at CI settings: plain `Pkg.test` at
`--threads=4` is the full gate and `lane=fast` is a development checkpoint.
The commands are in `AGENTS.md` (Verification Matrix).

The broader numerical studies and CPU/CUDA consistency checks remain separate
scripts under `validation/`.

Useful beam-beam checks:

```bash
julia --project=. validation/symplecticity_validation.jl
julia --project=. validation/high_energy_weakstrong_limit.jl
julia --project=. validation/soft_gaussian_pic_comparison.jl
```

Use Julia help:

```julia
?ContractResult
?ElementTrackingBackendConsistencyContract
?StrongStrongGaussianBackendConsistencyContract
?StrongStrongPICBackendConsistencyContract
?StrongStrongPICMultiProcessConsistencyContract
?PublicConfigurationEffectivenessContract
?SymplecticityContract
?HighEnergyWeakStrongLimitContract
?CoherentModePhysicsContract
?validate
?turn_timings
```

After public element metadata changes:

```julia
validate_element_metadata()
write_registry_snapshot()
```

Run a relevant `TrackingTask` smoke test or executable example after changing
tracking behavior.
