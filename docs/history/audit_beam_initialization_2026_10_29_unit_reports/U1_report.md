# U1: Beam initialization neighbour review

Provenance: independent agent, read-only. No Julia processes or edits. Scope:
the new constructor diff, Gaussian helpers, counter-RNG claim path, storage
conversion, and MPI sharding, against the reviewed initialization design.

## Leads delivered to the implementer

### BI-1 — late MPI refusal (Moderate, high confidence)

The initial MPI wrappers constructed the whole beam before validating the
communicator. A two-rank request in a serial process could therefore claim
a uniform stream and retain a `:beam_initialization` success receipt before
throwing. The reviewer supplied a `with_execution_audit` reproduction using
`MultiProcessExecutionPolicy(ranks=2)` and a one-point grid. The implementer
reproduced and fixed this; the parent record contains the red/green evidence.

### BI-2 — invalid explicit uniform RNG activates policy (Minor, high confidence)

`rng=:invalid` reached `rand(::Symbol,T,n)` after policy activation. The reviewer
supplied a custom CPU policy whose activation increments a `Ref`, predicting
one activation and a `MethodError`. The implementer reproduced this and added
an early `AbstractRNG` check for uniform mode.

## Clean properties inspected

Checked count/storage arithmetic precedes allocations. Grid uniqueness checks
walk actual generated range values before activation. Singleton-axis behavior,
endpoint rules, and x-fastest Cartesian ordering match the design. Uniform
sampling clamps affine rounding and bypasses Gaussian normalization. Host
arrays upload unchanged to CUDA. Physical population is independent of grid
point count. Gaussian draw/normalization/map/upload arithmetic is preserved.

## Closure review

After the implementer's fixes, `_prepare_beam_initialization(policy,n)` resolves
the communicator and shard range before sampling; all three branches shard
before recording successful initialization, retaining global `n_macro` in the
receipt. Uniform mode rejects malformed RNG objects before activation.
The subsequent source-sweep finding was addressed with a once-assigned
`grid_n` capture. No new concrete defect was found in the reread.

These are source-inspection conclusions. Runtime parity, contract behavior,
and gate results were executed and recorded by the implementer, not this unit.
