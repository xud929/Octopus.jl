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

`TwissDispersionIdentityContract` is the physics contract of
`TwissDispersionAnalysis` (its implementation contract is
`AnalysisOptionEffectivenessContract`). Its `validate` runs `analyze` on a
deterministic fixture set -- a DBA cell as compiled elements and as a
`BeamLine`, a detuned FODO, the DBA with thin RF and with a crab cavity,
seeded manufactured symplectic maps (6x6 and 4x4), the coasting map and the
metadata examples of every kind that declares the analysis -- and re-judges
the identities of the theory note on their VALUES: the reported residual
triples, the kernel residuals the analysis computes but does not surface,
the physical back-transformations, the verdict re-derivation, and the
absolute pins. Each identity row has its own multiplier `c` (tolerance
`c * eps() * kappa`); a row that exceeds it, a row that ran on no fixture, a
verdict the contract cannot re-derive, or an expected diagnostic that does
not fire FAILS the contract. It is mirrored by
`validation/twiss_dispersion_identities.jl` (section "Twiss and Dispersion
Identities" of `validation/README.md`), which prints the per-row ratios. Run
both after changing any file of `src/analysis/`.

`StrongStrongPICMultiProcessConsistencyContract` is the three-way statement
for the PIC collide -- CPU against MPI at each rank count, CPU against CUDA
through `StrongStrongPICBackendConsistencyContract`, MPI against CUDA by
composition. Its MPI legs are launched processes, so it needs the launcher
command (`mpiexec=MPICH_jll.mpiexec()` in the suite; `nothing`, the default,
returns `:skipped`) and a project that carries `MPI`; the child is
`src/contracts/mpi_pic_consistency_child.jl`. After changing the divided PIC
collide (`pic_cpu_sliced.jl`, or `pic_cpu.jl` under `divided`), the seam, or
the layout rule, run it at the rank counts you can launch. See `../design/multi_process_policy.md`.

## Analyses

Analyses define post-processing. The first concrete analysis is
`TwissDispersionAnalysis` (the type in `src/analysis/twiss_dispersion_type.jl`,
its constructor, option schema and `analyze` method in
`src/analysis/twiss_dispersion_analysis.jl`): a
non-parametric analysis object whose options are public configuration
(`analysis_option_schema`, `configuration_report`), executed by `analyze` on
a real symplectic 4x4 or 6x6 matrix, a `LinearizedMap`, a compiled line or an
element tuple, returning a `TwissDispersionResult`; its option probe table is
`AnalysisOptionEffectivenessContract`. The element declaration is a mixed
state: every element kind whose `tracking_methods` contain `Symplectic6DMap`
by exact identity and not `NonSymplectic6DMap`, plus `:line`, declares
`analyses = [TwissDispersionAnalysis]`; the kinds without an analysis keep
`analyses = [PlaceholderAnalysis]` (today the aperture, both Lorentz boosts,
the patch, the thin accelerating cavity, the lumped radiation and both strong
beams; `../registry_snapshot.md` is the source per kind, and the stage 5
section of the campaign history lists both sets). The suite does not carry
that list: two set tripwires derive the required set from the tracking
methods and assert the declared set equals it in both directions and that the
analysis is never declared beside `NonSymplectic6DMap`
(`../design/twiss_dispersion_analysis.md`, "Discovery"). The next analysis
joins by:

1. defining the analysis type with a `description` method, its
   `analysis_option_schema` (a runtime `consumer` per option) and its
   `analyze` method in `src/analysis/`, exporting each with a docstring;
2. adding its block to `validate_configuration_metadata()` (the tree guard
   names any concrete analysis without one) and one probe per option to the
   `AnalysisOptionEffectivenessContract` table, with a receipt from the named
   consumer;
3. declaring it in the spec's `analyses = [...]` field, replacing the
   placeholder for the specs it applies to (as stage 5 did for
   `TwissDispersionAnalysis`), so that `supported_analyses` discovers it,
   and regenerating the registry snapshot; once a spec declares it, the
   type (struct and docstring) must be included before
   `src/elements/Elements.jl`, as `src/analysis/twiss_dispersion_type.jl`
   is, because `@element_spec` registers its metadata at include time; the
   constructor and `analyze` may follow the elements;
4. shipping a small executable example if the output is user-facing
   (`examples/twiss_dispersion_dba_ring.jl` is the precedent: the two
   `analyze` runs of a DBA ring with RF, every undetermined quantity
   printed as its reason, catalogued in `example_catalog()` and run by
   the suite's example runner).

## Finish

The affected contract's own `validate(...)` run, the relevant validation
script, `write_registry_snapshot()` if a public object changed, and the full
gate (`development_workflow.md`).
