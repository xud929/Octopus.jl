# Contracts and Analyses

Route here from the `AGENTS.md` task table when adding or changing a
validation contract or an analysis.

## Contracts

Contracts define correctness checks; they are the part of the architecture
that decides whether a result is acceptable. Prefer physics-level agreement
criteria over bitwise equality, and state every tolerance explicitly.

1. Put the contract in `src/contracts/` and return a `ContractResult` from
   `validate`.
2. Use `status=:skipped` for unavailable resources such as a missing CUDA
   device. A check that did not run is not a pass, and a comparison with
   nothing in it is not a pass either.
3. Attach the contract to element specs through the `contracts = [...]` field
   of their `@element_spec` block; tasks define a
   `required_contracts(::Type{<:MyTask})` method instead
   (`src/tasks/strongstrong/interface.jl`). `required_contracts` returns a
   copy; mutating it attaches nothing.
4. Changing acceptance or rejection semantics, a contract, or a tolerance has
   a blast radius: find every contract and test that probes the old behavior
   before changing it. This is a full-gate class.

`ElementTrackingBackendConsistencyContract` is one of several implementation
contracts in `src/contracts/Contracts.jl`. After changing generic, fused,
stochastic, or CUDA tracking, or an element implementation it covers, run
`validation/tracking_backend_consistency.jl`. Kinds that declare
`SymplecticityContract` need a case in `_symplecticity_contract_cases()`
(`elements.md`) and are exercised by `validation/symplecticity_validation.jl`.
`PTCConsistencyContract` is checked in the suite against the committed
reference table, which `validation/generate_ptc_reference.jl` regenerates when
MAD-X is on `PATH`.

`StrongStrongPICMultiProcessConsistencyContract` is the three-way statement
for the PIC collide -- CPU against MPI at each rank count, CPU against CUDA
through `StrongStrongPICBackendConsistencyContract`, MPI against CUDA by
composition. Its MPI legs are launched processes, so it needs the launcher
command (`mpiexec=MPICH_jll.mpiexec()` in the suite; `nothing`, the default,
returns `:skipped`) and a project that carries `MPI`; the child is
`src/contracts/mpi_pic_consistency_child.jl`. After changing the divided PIC
collide (`pic_cpu.jl` under `divided`), the seam, or the shard rule, run it at
the rank counts you can launch. See `../design/multi_process_policy.md`.

## Analyses

Analyses define post-processing. No concrete analysis exists yet:
`src/analysis/` holds only `PlaceholderAnalysis`, every element registers
`analyses = [PlaceholderAnalysis]`, and there is no execution API. The first
real analysis:

1. defines the analysis type and its execution API in `src/analysis/`;
2. is declared in the spec's `analyses = [...]` field, replacing the
   placeholder for the specs it applies to, and is discovered through
   `supported_analyses`;
3. ships a small executable example if the output is user-facing.

## Finish

The affected contract's own `validate(...)` run, the relevant validation
script, `write_registry_snapshot()` if a public object changed, and the full
gate (`development_workflow.md`).
