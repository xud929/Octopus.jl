# Unit report U1: the artifact, the reference and the beam (batch units U1, U2, U3)

Tree read: the cp1 worktree at the end of the batch (c52d80e plus the batch's
diff). Probe logs: `/tmp/claude-dxu/cp1/audit_probes3.log` (L1, L2, L7),
`/tmp/claude-dxu/cp1/audit_probes_b.log` (the untyped BigFloat override, the
cavity's reference route, `show`). Every lead was reproduced by the auditor in
a fresh process; the line numbers are of the batch tree.

## Leads and dispositions

- **L1 (U1) The in-memory artifact and the content-addressed snapshot.**
  `RunArtifact(; storage = :memory)` writes through the same HDF5 image the
  disk path writes (`_ra_write_machine_snapshot!`, `src/tasks/RunArtifact.jl`),
  and `save_run_artifact` copies the image. Repro: a `TrackingTask(lattice;
  artifact = RunArtifact(; storage = :memory))`, three `execute!` windows,
  `save_run_artifact(task.artifact, path)`; the saved file holds the groups
  `execution`, `luminosity`, `machine_snapshots` with ONE digest
  (`979b85e9...`), the `execution` group has the `machine_sha256` column and
  no `machine_toml` column, `read(TaskOutput(path), :machine)` equals
  `machine_toml(Machine(lattice))` and `read_machine(out) == Machine(lattice)`.
  **Clean.**
- **L2 (U2) A knob-expression energy through the snapshot and the beam.**
  `ReferenceParticle(:proton; E0 = @knob_expr(ap2.E0))` keeps `E0` and the
  derived `gamma0` as expressions (`energy_key = :E0`); the snapshot writes
  `reference = { charge = 1.0, mc2 = 9.3827208943e8, E0 = { expr = "ap2.E0" } }`
  and reads back `==`; `Beam(16, cpu; reference = ref, npart = 1.0e10)` resolves
  the energy at construction (`E0 = 2.75e11`, `r0 = 1.5347e-18`), and after
  `set_knob!("ap2.E0", 100.0e9)` a new beam reads `1.0e11`. The beam's
  parameters are `(:charge, :mc2, :E0, :r0, :npart)`; a beam built before the
  retune keeps its value, as every beam does (the ramp is batch C's subject).
  **Clean.**
- **L7 (U2) The accessors and the two equalities.** `reference_energy` returns
  the typed quantity (`p0c` for an electron built from `p0c`), `brho` derives
  (33.356 T m at 10 GeV/c), and a reference from `E0` is structurally `!=`
  one from the equivalent `p0c` (the record's choice; the physical equality is
  pinned separately in the U2 testset). `show` prints
  `ReferenceParticle(charge = -1.0, mc2 = 510998.95069 eV, E0 = 1.0e10 eV)`.
  **Clean.**
- **L8 (U3) The untyped element's wide override.** `lu[1].L =
  big"0.30000000000000000001"` on an UNTYPED quadrupole is refused at
  `Lattice(...)` by the stage-2 eltype tripwire ("compiles in BigFloat, not
  the lattice's numeric type Float64"), the promotion rule R6 leaves in
  place; the typed element's refusal is R6's own (`_lattice_check_typed_values`).
  **Clean, pre-existing.**
- **L9 (U2) The cavities' reference route.** `ThinRFCavitySpec(400.0e6; ...,
  reference = ref)` accepts the richer record (its stored `beta0`, derived
  once). **Clean.**
- **L10 (U2) The `r0` sweep's neighbours.** The grep of `r0 =` over
  `examples/`, `test/`, `validation/`, `profiling/`, `src/contracts/` after
  the sweep finds no `Beam` keyword left; the only `r0` uses are the derived
  field's readers (`params.r0`, `_strong_strong_kbb1/2`). The examples'
  CPU fingerprints are identical to the stage-5 baseline on all 20 rows, so
  the derived value is the value the examples passed. **Clean.**
- **L11 (U1) The receipts' blast radius.** The new option at its default
  appears in every `:run_artifact_output` receipt, which moved the receipts
  testset's fixture and `propertynames` pin (adapted in the batch); the
  extracted receipts block cannot run outside the suite (a file-level helper,
  `_st4b_a_dense6`), so it is the gate's. **Left to the gate, by the
  runner's stated limit.**

## Coverage

Read: `src/tasks/RunArtifact.jl` (the snapshot paths, the readers, the TOC),
`src/lattice/Lattice.jl` (the reference block), `src/lattice/toml.jl` (the
reference table and decoder), `src/beam/Beam.jl` (`_beam_params`,
`_numeric_reference`, the three positional sites),
`src/tasks/strongstrong/interface.jl` (`_preflight_solver_kbb`,
`_check_derived_kick`, `_solver_report_with_derived_kicks`),
`src/knowledge/Knowledge.jl` (`_as_numeric_type`, `_numeric_type_holds`).
Not read: the MPI extension's artifact path (`ext/`), unchanged by the batch;
the CUDA twin of the beam constructors, which share `_beam_params`.
