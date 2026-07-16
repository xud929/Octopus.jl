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
?StrongStrongCollision
?GaussianPoissonSolver
?PICPoissonSolver
?LongitudinalSlicing
?longitudinal_slices
?AbstractPoissonSolver
?execute!
?TrackingContext
?ScheduledObserver
?ScheduledAction
?EveryNSteps
?AtTurns
?JLD2BeamMomentObserver
?LuminosityObserver
```

Runnable examples live in `examples/` and are self-documenting at the top of
each source file.

`JLD2BeamMomentObserver` writes columnar files. Common access pattern:

```julia
using JLD2

jldopen("result/pic_hcc.pro.jld2", "r") do io
    turns = io["turn"]
    data = io["data"]
    emittance = read_moment(io, :emittance)
    column_names = io["metadata/column_names"]
end
```

Developer-facing numerical checks live in `validation/`. They may use internal
helpers and should not be treated as public API examples.

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

Use Julia help:

```julia
?ContractResult
?TrackingBackendConsistencyContract
?validate
```

After public element metadata changes:

```julia
validate_element_metadata()
write_registry_snapshot()
```

Run a relevant `TrackingTask` smoke test or executable example after changing
tracking behavior.
