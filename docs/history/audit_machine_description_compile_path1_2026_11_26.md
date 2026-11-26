# Scoped neighbour audit of the machine-description compile-path batch A, 2026-11-26

> **Status: closed 2026-11-26 (the record commit of the batch). The
> post-campaign standard of [`../comprehensive_audit.md`](../comprehensive_audit.md)
> ("The targeted neighbour audit", owner direction 2026-08-08; `AGENTS.md`,
> "A fix's neighbours are where the next defect is") applied to batch A of
> [`../design/machine_description_followups.md`](../design/machine_description_followups.md),
> recorded in
> [`machine_description_compile_path1_2026_11_26.md`](machine_description_compile_path1_2026_11_26.md),
> conducted by the batch's own session on 2026-11-26 with three reading
> units (U1: the artifact, the reference and the beam -- batch units U1 to
> U3; U2: the compile walk, the flags and the streams -- U4 to U6; U3: the
> readers and the class form -- U7 and U8), 16 leads, 4 confirmed findings
> (all fixed in the batch before its gate, each with a red-first test or a
> registry-derived tripwire), 2 corrections to the batch's own analysis, 10
> clean by reproduction; every reproduction re-run in a fresh process before
> recording (the probe logs named in the unit reports). The gate numbers are
> in the batch's commit messages and its record.** Unit reports:
> [`U1_report.md`](audit_machine_description_compile_path1_2026_11_26_unit_reports/U1_report.md),
> [`U2_report.md`](audit_machine_description_compile_path1_2026_11_26_unit_reports/U2_report.md),
> [`U3_report.md`](audit_machine_description_compile_path1_2026_11_26_unit_reports/U3_report.md),
> the queue's file:line ground truth (their pointers are of the batch tree).

## 1 Executive summary and repository

Tree audited: the cp1 worktree at the end of the batch, c52d80e (the
follow-ups note on the pushed stage-5 tree f877ac1) plus the batch's diff
(the record's section 1 lists it by unit). The batch's commit range is the
record's. Scaled to the campaign: one session, one worktree, the units'
neighbours re-walked as each unit landed and once more at the end over the
whole diff, with sub-agents not used (the diff is one session's and its
author re-walked it; every lead below was reproduced in a fresh Julia process,
not taken from memory).

Findings by severity: no Major. Four Moderate, all fixed in the batch before
its gate:

- **A-1 (U8) The class form missed the aperture.** The methods were generated
  by a loop over `ELEMENT_META_BY_KIND` in `src/elements/templates.jl`,
  included last in `Elements.jl`; `src/elements/aperture.jl` registers from
  `src/Octopus.jl:114`, after `Elements.jl` (line 93). Repro: the first
  registry-derived smoke run, 30 kinds deriving and `MethodError: no method
  matching ApertureSpec(::ElementSpec{:aperture}; name)`. Fix: the
  registration installs the method (`_install_class_form!`,
  `src/knowledge/Knowledge.jl`, called where `ELEMENT_META_BY_KIND[kind] =
  meta` is written); the suite's tripwire derives every registered kind with
  a type as its friendly constructor (31 kinds, the aperture asserted by
  name).
- **A-2 (U8) The ruling's RBEND clause landed on a kind that does not
  exist.** `_derive_spec` had a `kind === :rbend` arm and the fold hook a
  `chord` arm for `:rbend`, both dead: `RBendSpec` builds an
  `ElementSpec{:sbend}` (`src/elements/lattice_magnets.jl:1667`), and
  `RBendSpec(template; ...)` had no method. Repro: the first smoke run's
  `MethodError: no method matching RBendSpec(::ElementSpec{:rbend}; name,
  angle)` (the flexible form accepts any kind symbol, which is pre-existing
  and compiles to nothing). Fix and decision: the record's section 2 -- the
  alias's own method reading its template as an RBEND, `SBendSpec(template;
  ...)` keeping the faces as stored, the dead arms removed; pinned in the U8
  testset.
- **A-3 (U5) The flexible form's claim would have warned about a spec's own
  stream.** Found by reading `LumpedRadSpec` (`src/elements/radiation.jl:96`:
  the constructor stores the stream `next_rng_id!` resolved for `rng_id =
  0`) before the testset ran: every rebuild through the flexible form passes
  that auto-assigned id, and `claim_rng_id!`'s policy warns on an explicit
  claim of an auto-assigned id. Fix: `_rng_id_held_by(id, class)`
  (`src/math/counter_rng.jl`) and the form claiming only what its class does
  not hold; pinned (a `LumpedRadSpec` built with `rng_id = 0` rebuilt raw,
  retyped and copied into a derived lattice, zero warnings; another class's
  auto id still warns).
- **A-4 (U8) A docstring on a `(::Type{RBendSpec})` method attached to
  `Core.Type`.** Repro: the suite's detached-docstring sweep extracted,
  `isempty(foreign)` false with `Core.Type <- Union{Tuple{ElementSpec{K}},
  Tuple{K}} where K`. Fix: the text is a comment, the rule documented on
  `_derive_spec`; the sweep passes extracted.

Two corrections to the batch's own analysis, recorded beside the claims they
replace (the protocol's rule): the U6 cost pin was first written as an
allocation equality between the tuple and the lattice spelling, which does
not hold (17520 against 17488 bytes; different runtime shapes), and is now
the executor's text plus the measured bytes in the record; the U7 testset
first expected `read_machine(pa, pb; name = ...)` without `knob_root` to
assemble a machine with no shared root, which `Machine`'s tripwire refuses
(a root two lattices declare must be declared shared), and the pin is now
that refusal.

Clean by reproduction (the unit reports' L1 to L14): the in-memory artifact's
snapshot group reaching disk through `save_run_artifact`; a knob-expression
energy through the snapshot and the beam; the accessors and the two
equalities of the reference; the untyped element's wide override (refused by
the stage-2 eltype tripwire, as before); the cavities' reference route; the
`r0` sweep's neighbours (the CPU fingerprints identical); every walker over a
line holding a collision marker (`total_length`, `find_entries`,
`entry_path`, `knob_report`, the codec, `_has_accelerating_cavity`,
`with_overrides`, `one_turn_matrix`, `analyze`, the whole-line task); the
strong-strong route (the parity driver's `ss` case equal digests); a
placement override's `rng_id` through compile and execution (no warning);
the routes into the flexible form; the flag's readers (4 bytes per turn
between the lattice and tuple routes where C-3 measured 416 per call); the
old snapshots' `stop`; typed templates; the fold under the knob rebuild; the
flexible form's blast radius (one suite site, still refusing); three files
through `read_machine`; the one-file reader.

## 2 Declared scope and coverage ledger

| Region | Files read in full or by function | Property re-run | Unit |
|---|---|---|---|
| the artifact's snapshot | `src/tasks/RunArtifact.jl` (`_ra_machine_snapshot`, `_ra_write_machine_snapshot!`, `_ra_machine_text`, `_ra_contents`, the constructors, the receipt) | memory storage saved to disk; the stage-4 layout read; the TOC | U1 |
| the reference and the beam | `src/lattice/Lattice.jl` (the reference block), `src/lattice/toml.jl` (reference codec), `src/beam/Beam.jl` (`_beam_params`, `_numeric_reference`), `src/tasks/strongstrong/interface.jl` (the preflight) | a knob energy end to end; the accessors; the cavities' route; the `r0` grep | U1 |
| the numeric type | `src/knowledge/Knowledge.jl` (`_as_numeric_type`, `_numeric_type_holds`), `src/lattice/Lattice.jl` (`_lattice_check_typed_values`) | the untyped wide override | U1 |
| the compile walk | `src/elements/beam_line.jl` (whole-line compile), `src/tasks/Tasks.jl` (`_append_runtime_line!`, the binding), `interface.jl` (`_inert_in_single_beam`, `_binding_report`) | every walker on a marker-bearing line; the parity `ss` case | U2 |
| the streams | `src/knowledge/Knowledge.jl` (the inner constructor, the claims, the validator tripwire), `src/math/counter_rng.jl`, `src/lattice/overrides.jl`, `src/elements/beam_line.jl` (`setproperty!`) | an override's id through compile; the routes enumerated | U2 |
| the flags and the codec details | `src/tasks/Tasks.jl` (constructor, executor), `src/lattice/toml_hooks.jl`, `src/tasks/BeamObservers.jl` | the parity `ws` bytes; the old `stop` | U2 |
| the readers | `src/lattice/toml.jl` (`read_lattice`, multi-path `read_machine`) | three files; the shared-root refusal | U3 |
| the class form and the fold | `src/elements/templates.jl`, `Knowledge.jl` (`_install_class_form!`, `element_help`), the fold tables, `_rbend_params`, `_sbend_params`, `src/lattice/elements_macro.jl` | the registry-derived derivation; typed templates; the knob rebuild; the blast-radius grep; the docstring sweep | U3 |

Not read, stated: the CUDA kernels and the MPI extension (no kernel or
collective changed; the CUDA fingerprints are bitwise on the deterministic
rows and within the same-tree noise on the PIC rows); the strong-strong
solvers' interiors (the preflight sits before them); the translators (none).

## 3 Traceability

| Ruling | Unit | Neighbours re-walked | Tests pinning it |
|---|---|---|---|
| R9 | U1 | both artifact constructors, the memory store, the readers of both layouts, the receipts | the artifact testset; the receipts testset; the ledger-columns block |
| R3, R4, R5 | U2 | `Beam`'s three construction sites, the cavities, the snapshot's reference codec, the preflight, 180 call sites | the two U2 testsets; the reference-batch pins |
| R6 | U3 | `_as_numeric_type`'s callers (typed params, the fold hook, the codec's scalar reader), the lattice tripwire | the U3 testset; the numeric-type tripwire block |
| R2 | U4 | the walkers over a line (B-1's enumeration), the strong-strong route, the analyses | the U4 testset; the parity driver |
| R8b | U5 | the routes into the flexible form, the three assignment routes, the registry's policy and its call-site tripwire | the U5 testset; the rng-policy block |
| R8c, R8d | U6 | the executor, the constructor, the codec round trip, the moment parser's callers | the U6 testset; the codec blocks |
| R10 | U7 | the one-file reader, `Machine`'s tripwires | the U7 testset |
| R11 | U8 | every registered kind, the fold tables, the bends, the `@elements` rewrite, the snapshot reader, the help | the U8 testset; the `@elements` blocks; the docstring and export sweeps |

## 4 Findings (the queue)

All four confirmed findings (A-1 to A-4, section 1) are fixed in the batch;
nothing is ledgered from this audit. One item for the owner, carried in the
record and the follow-ups note: the RBEND template convention (A-2's
decision), a convention of the authoring form the owner may overrule.

## 5 Formula and contract verification

- `r0 = RE * ME0 / mc2`: `RE * ME0 / EMASS_EV == RE` holds bitwise (the
  electron's classical radius is the constant itself), and the proton's
  `1.5347e-18 m` is `RE * (m_e / m_p)`; the examples' CPU fingerprints are
  identical to the baseline, so the derived value is the value the examples
  used to pass.
- `brho = p0c / c` per unit charge: 33.356 T m at 10 GeV/c (1e10 / 299792458),
  as the probe printed.
- The effectiveness contract `validate(PublicConfigurationEffectivenessContract())`
  passed on the batch tree ("Public configuration reached CPU, fused CUDA,
  and CUDA PIC consumers"), the new `machine_snapshot` option included
  through its receipt.

## 6 Test, validation and performance report

- The extracted neighbours (49 titles, `/tmp/claude-dxu/cp1/extracted_final.log`
  and the rerun of the blocks the fixes touched, `extracted_final2.log`):
  the blocks that cannot run outside the suite by the runner's stated limit
  (a file-level helper, `with_logger`, `Symbolics`) are the gate's; every
  other block passed. The validators and the snapshot: the record's
  section 3.
- Fingerprints: CPU identical (20 rows); CUDA within the same-tree noise
  (the record's table).
- The parity driver: `ss` and `ws` on CPU pass with equal digests and a zero
  control floor; `ws` shows the lattice and machine routes at 46426 bytes per
  turn against the tuple's 46422; the CUDA `ss` run is in the record.
- Performance: R9's table (the A500 fixture, 200 single-turn calls: 12.3 MB
  and 18.9 ms per call to 0.91 MB and 5.03 ms); U6's walk gone (above).

## 7 Change log and remaining risks

Changed by this audit: nothing beyond the four fixes, which are the batch's.

Remaining risks: the RBEND convention (owner's call); `_rng_id_held_by`'s
reading of a forgotten auto class as the claimant's own (an old cross-class
collision reaching the flexible form after 65536 automatic assignments goes
unwarned, as it did before R8b); the full gate was still to run when this
report was written -- its result is in the record and the commit messages,
and a failure there reopens this audit.
