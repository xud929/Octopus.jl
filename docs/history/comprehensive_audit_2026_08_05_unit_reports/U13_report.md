# U13 Report — metadata/registry layer + execution policies

Commit audited: 7a8e9cade48ee70297c0ef4308f588bdef927b19.

## Coverage

Read every line of:
- src/knowledge/Knowledge.jl lines 1-955 (all)
- src/knowledge/Methods.jl lines 1-75 (all)
- src/registry/Registry.jl lines 1-218 (all)
- src/examples/Examples.jl lines 1-35 (all)
- src/Octopus.jl lines 1-76 (all)
- src/policies/Policies.jl lines 1-352 (all)

Supporting reads (targeted, for consumer tracing): src/elements/linear_maps.jl (1-30),
src/elements/lattice_magnets.jl (930-1230), src/elements/thin_elements.jl (100-125),
src/elements/misalignment.jl (190-300), src/elements/ref_tilt.jl (84-135),
src/elements/beam_line.jl (515-600), src/tasks/strongstrong/interface.jl (1542-1615),
src/track/Track.jl (1-40), plus greps over src/, test/, docs/.

Probes (all run, `julia --startup-file=no --project=.`, CPU-only, each < 60 s after
precompile): scratchpad/U13/p1_unknown_keyword.jl, p2_registry_enum.jl,
p3_validator_blindspots.jl, p4_snapshot_diff.jl, p5_docstrings.jl. Regenerated
snapshot written only to scratchpad/U13/registry_snapshot_regen.md. No repo file
was modified.

## Leads

### U13-1 — src/elements/linear_maps.jl:8 + src/knowledge/Knowledge.jl:57-58 — unknown-keyword acceptance: mechanism and blast radius (Medium; confirms U3-10)

Mechanism: `_spec_params(; kwargs...)` (linear_maps.jl:8) copies EVERY keyword into
the `Dict{Symbol,Any}` params store, and the raw constructor
`ElementSpec{Kind}(; kwargs...)` (Knowledge.jl:57-58) does the same. All 32
exported friendly constructors end in a `kwargs...` passthrough into one of these
two paths (verified per-file: linear_maps 31/99/169, chromaticity_kick 28,
crab_cavity 23, lorentz_boost 19/29, linear6d 34, solenoid 352, lattice_magnets
944/982, thin_elements 107/116, radiation 36, strong_beam 174/310, patch 164,
aperture 401, rf_cavity, beam_line). No constructor consults `meta.parameters`.

Probe p1 numbers: `QuadrupoleSpec(L=0.3, k1=1.2, this_keyword_does_not_exist=1.0)`
constructs (`hasparam` true) and compiles to
`LatticeMagnet{Symplectic6DMap, Float64, 2, 2, 12, 0, 0, false}`. The raw path
`ElementSpec{:quadrupole}(; bogus=2.0)` also stores the key. The SAME name is
rejected by `setproperty!` (Knowledge.jl:80-90) with
"element kind :quadrupole has no parameter this_keyword_does_not_exist" — the
asymmetry is construction-open / assignment-strict.

What a strict-keyword guard would touch: the single choke point is
`_spec_params` (or the `ElementSpec{Kind}` kwargs constructor), validating against
`meta.parameters` when the meta is registered and non-empty — exactly the
condition `setproperty!` already uses. Legitimate open-keyword uses that a strict
guard would break today:
1. misalignment/ref_tilt keys consumed by `compile_runtime` but undeclared in
   most schemas (see U13-2 — the guard would reject physically meaningful input);
2. docstring-promised metadata storage: "Extra keyword arguments are stored as
   descriptive spec metadata" (linear_maps.jl:22-23 and siblings);
3. registration order: `@element_spec` blocks run AFTER the constructors are
   defined and the `example =` expressions inside the block CALL those
   constructors, so a guard reading the registry would see no meta while the
   block's own example is being built (self-bootstrapping) — the guard must
   no-op when meta is absent, as `setproperty!` does.

### U13-2 — src/knowledge/Knowledge.jl:80-90 vs src/elements/misalignment.jl:261 and src/elements/ref_tilt.jl:117 — parameters READ by compile_runtime are rejected by the documented post-construction binding path (Medium)

`compile_runtime` (Knowledge.jl:948-949) wraps EVERY element through
`_misalignment_wrap` (reads x_offset, y_offset, z_offset, x_pitch, y_pitch, tilt,
misalign_convention, L, h) and `_ref_tilt_wrap` (reads ref_tilt). But schemas
declare these unevenly, and `setproperty!` rejects assignment of any name not in
a non-empty schema:

Probe p1 numbers:
- `DriftSpec(L=0.5, x_offset=1e-3)` accepted and compiles to `MisalignedElement`;
  `parameter_schema(DriftSpec)` has no `x_offset`; `d.x_offset = 1e-3` after
  construction throws ArgumentError.
- `QuadrupoleSpec(L=0.3, k1=1.2, ref_tilt=0.1)` compiles to `RefTilted`;
  quad schema has no `ref_tilt`; `q.ref_tilt = 0.1` throws ArgumentError.
- x_offset undeclared in 17 of 30 kinds: aperture, chromaticity_kick,
  crab_dispersion, drift, gaussian_strong_beam, linear6d, lorentz_boost,
  lumped_radiation, marker, momentum_dispersion, patch, rev_lorentz_boost,
  solenoid, thin_crab_cavity, thin_rf_cavity, thin_strong_beam, xy_coupling.
  (Note solenoid is a thick magnet yet omits them while quadrupole declares them;
  marker omits them while the other thin elements declare them.)
- ref_tilt undeclared in 29 of 30 kinds (sbend only).

Violated invariant: the ElementSpec docstring (Knowledge.jl:44-49) sells
`spec.param = value` as "the natural way to bind an existing element to a knob"
and calls unknown names "typos" — but x_offset on a drift and ref_tilt on a
quadrupole are not typos; the compiler consumes them. Knob binding
(`spec.ref_tilt = @knob_expr(...)`) is therefore impossible post-construction on
those kinds except via the `spec.params[:key] =` escape hatch, which skips the
epoch... no — the escape hatch also skips nothing; `params[:key] =` does NOT bump
`_SPEC_EPOCH` (only `setproperty!` line 92 does), so the escape hatch additionally
loses the recompile-on-next-execute! guarantee the docstring promises for
parameter mutation. Repro: scratchpad/U13/p1_unknown_keyword.jl.

### U13-3 — src/knowledge/Knowledge.jl:811-815,828-831,836-848 — empty `tracking_methods` disables the validator's runtime-map, runtime-type-consistency, AND example-compile checks (Medium)

All three post-rebuild consumer checks are gated on non-empty declarations:
- 811: `for tracking_method in meta.tracking_methods` — empty loop;
- 828: `!isempty(meta.runtime_types)` guard skips the runtime_type-in-map check;
- 836: `!isempty(meta.runtime_types)` guard skips the compile check.

Probe p3 numbers: an in-memory lying meta (kind=:u13_fake,
runtime_type=Int, tracking_methods=DataType[], example=ElementSpec{:u13_fake}())
passes `validate_element_metadata()` with 0 errors while
`compile_runtime(ElementSpec{:u13_fake}())` throws MethodError and the declared
runtime_type is the nonsense `Int`.

In-repo instance: kind `:line` (src/elements/beam_line.jl:565-571) declares
`tracking_methods = DataType[]` and no runtime_type, yet HAS a real compile path
(`compile_runtime(::ElementSpec{:line})`, beam_line.jl:546) producing
`CompositeLine`. Its example (`BeamLine("CELL", QuadrupoleSpec(...))`) is the one
registered example the validator never compiles. A broken :line example would
validate clean. Repro: scratchpad/U13/p3_validator_blindspots.jl.

### U13-4 — src/knowledge/Knowledge.jl:736-737 — `_compiled_matches_runtime` docstring claims "is (or wraps)" but the only method is `compiled isa rt` (Low, latent)

Probe p3: `compile_runtime(DriftSpec(L=0.5, x_offset=1e-3))` returns a
`MisalignedElement` wrapping a `LatticeMagnet`; declared rt is `LatticeMagnet`;
`_compiled_matches_runtime(compiled, rt) == false`. No specialization exists
anywhere (grep: 2 hits, both Knowledge.jl). Consequence: the moment any
ElementMeta example carries a misalignment or ref_tilt, validate_element_metadata
falsely reports "example compiles to MisalignedElement{...}, which is not a
declared runtime type". Today no example does, so this is docstring drift plus a
tripwire for the next girder/misalignment example.

### U13-5 — missing public docstrings vs AGENTS.md:342 "Public architecture APIs need docstrings." (Low)

Probe p5 numbers: 76 of 335 exported names have no docstring. Within the
assigned files:
- src/policies/Policies.jl:124 `AbstractGPUExecutionPolicy` (inherited item —
  CONFIRMED still undocumented), :208-214 `backend_type` (exported, no docstring),
  :66 `execution_receipts` (exported, no docstring), :293-300
  `policy_option_schema` (exported, no docstring anywhere — its solver sibling
  `solver_option_schema` is likewise bare in interface.jl).
- src/Octopus.jl:13-17 `AbstractExecutionBackend`, `CPUThreadsBackend`,
  `CUDABackend`, `AbstractPhaseRep` — all exported at Octopus.jl:10-11,
  none documented (`track!` IS documented elsewhere; it is not in the
  undocumented list).
Out-of-scope bulk (other units' files): generated friendly constructors
(DriftSpec, QuadrupoleSpec, MarkerSpec, ...), runtime objects (LatticeMagnet,
MisalignedElement, RefTilted, ...), RNG/longitudinal constants.
Full list: scratchpad/U13/p5_out.txt.

### U13-6 — src/registry/Registry.jl:210-218 — Runtime Objects section: a fourth hand-maintained piece the docstring doesn't declare, and it omits real runtime objects (Low)

`_runtime_object_types` = union of `meta.runtime_types` values plus a
hand-appended `Any[BeamParams, Phase6DRep, Beam]` (line 216). The OctopusRegistry
docstring (Registry.jl:11-16, the K7 correction) enumerates the hand-maintained
parts as exactly "Task Diagnostics, Knob Control, and the Runtime Objects
preamble" — the hand-appended type triple is a fourth, undeclared. Staleness is
real, not hypothetical: exported runtime tracking objects `MisalignedElement` and
`RefTilted`, and `CompositeLine` (the compile product of every
`ElementSpec{:line}`), appear nowhere in docs/registry_snapshot.md (grep: 0 hits;
Runtime Objects section lists 21 entries ending BeamParams/Phase6DRep/Beam)
because none of them sits in any meta.runtime_types map. Any future beam-scale
type would likewise need a hand edit at line 216.

## Defect-class 1 characterization (validator: current scope and the two missing checks)

What validate_element_metadata (Knowledge.jl:757-873) validates now, per
registered spec: meta exists; kind uniqueness; spec_type identity;
example is an ElementSpec of the right kind; keywords in the controlled set;
required params: present in example, no default; every schema key mentioned
(substring) in construction_help; example params ⊆ schema; tracking methods /
contracts / analyses are subtypes of their architectural roots (non-circular,
against the DECLARATIONS); per-method runtime type exists; runtime_type
(singular) is in the runtime_types map; example COMPILES to a declared runtime
type; friendly/raw schema, help, and example-kind agreement.

What it cannot catch (verified):
1. declared-defaults-vs-constructor: `ParamMeta.default` is display-only; nothing
   compares it to what the friendly constructor actually stores. (Contrast:
   `validate_configuration_metadata`, interface.jl:1552-1563, DOES this for
   policies/solvers with `isequal(getproperty(default, name), meta.default)`.)
2. declared-parameter-IS-READ: nothing verifies the runtime constructor consumes
   each schema key (drift honestly documents nst/integrator_order as "unused" —
   an is-read check needs a declared-unused annotation or allowlist).
3. The inverse, read-parameter-IS-DECLARED: U13-2 (x_offset 17/30, ref_tilt
   29/30 undeclared yet consumed).
4. Empty tracking_methods bypass: U13-3.
5. Wrapper-blind compile check: U13-4.
6. construction_help "mention" is substring-level (line 791): key `L` is matched
   by any help text containing the letter L.

What the two missing checks would need:
- defaults-vs-constructor: build the example call from schema (required keys
  only), call `meta.friendly_constructor`, compare `params(spec)[key]` against
  `pmeta.default` for optional keys — needs conventions for folded/renamed keys
  (k1 -> kn at construction in magnets), for defaults the ctor doesn't store,
  and for `nothing`-defaults; the machinery precedent already exists in
  validate_configuration_metadata.
- declared-parameter-IS-READ: capture the read set during
  `compile_runtime(example)` — e.g., a recording Dict (or spec wrapper) that
  logs `param`/`getparam` keys — then require schema keys ⊆ reads ∪
  declared-unused, and (closing U13-2) reads ⊆ schema. The misalignment/ref_tilt
  wrapper reads would surface on every kind immediately.

## Sound (invariants verified, and how)

1. Defect class 2 CLOSED: all 30 registered spec types have exactly one
   ElementMeta; all 32 exported `*Spec` type names resolve metadata (probe p2:
   "exported *Spec types with NO ElementMeta: String[]"); RBendSpec resolves via
   `register_friendly_alias!(RBendSpec, :sbend)` (lattice_magnets.jl:1222) and
   runtests.jl:1196 pins the once-invented kind.
2. `validate_element_metadata()` passes with 0 errors on the live registry
   (probe p2) and runs in the suite with `throw_on_error=true` (test/runtests.jl:44)
   — the check IS executed.
3. Defect class 6: docs/registry_snapshot.md is byte-identical to the
   regenerated snapshot (probe p4 + `diff`, exit 0); freshness is enforced by
   test/runtests.jl:48-49 comparing `registry_snapshot_markdown()` to the file.
4. Defect class 4: every policy field traced to a real consumer, none
   stored-never-read: CPU `threads` -> Beam.jl:337
   (`ResolvedCPUExecutionPolicy`) -> `_run_logical_workers(policy.threads)`
   (phase6d_track.jl:29,41; strong_beam_track.jl:47,78) and
   `_cpu_worker_count()` via `_ACTIVE_RESOLVED_POLICY` (pic_cpu.jl, slicing.jl,
   spectral.jl, gaussian.jl); CUDA `device` -> Beam.jl:339-349 +
   `activate_policy!` at Beam.jl:438; `launch.threads/blocks` ->
   `_cuda_resolve_fused_blocks` (phase6d_track.jl:256) and `_active_cuda_launch`
   (pic_cuda.jl:1197,1200,1205,5119-5120,5627; gaussian_pic_cuda.jl:194);
   GPUExecutionPolicy -> `_legacy_cuda_policy` (Beam.jl:339,
   interface.jl:1481); `backend_type` -> Beam.jl:330,332,439, Tasks.jl:780,
   BeamObservers.jl:116,208,765, spectral.jl:223,270;
   `ConfigurationOptionMeta.category` -> Contracts.jl:2209,2398,2405,2495;
   `.consumer`/`.default` -> interface.jl:1546-1563; `ConfigurationEntry` /
   `ExecutionAuditReceipt` -> Contracts effectiveness contracts.
5. Defect class 5: element_help (Knowledge.jl:593-649) prints exclusively from
   registry queries; summarize_registry/build_registry derive from
   `registered_element_specs()` + `_subtypes_recursive` over the six abstract
   roots; solver_help derives from `solver_option_schema` (interface.jl:420-446).
   Hand-maintained parts of the snapshot are the documented Task Diagnostics and
   Knob Control sections plus the line-216 triple (U13-6).
6. Registry copy discipline holds: `registered_element_specs()`,
   `physics_keywords`, `supported_tracking_methods`, `supported_analyses`,
   `required_contracts`, `allowed_physics_keywords` all return copies
   (Knowledge.jl:201,210,466,482,497,520).
7. Policy constructor validation matches docstrings: CPU threads `:auto` or
   1..nthreads rejected-not-clamped (Policies.jl:109-121); CUDA
   threads/blocks positivity (135-147); device nonnegative-or-nothing (161-167);
   GPUExecutionPolicy emits depwarn and validates through CUDALaunchConfig
   (181-192). PlaceholderPolicy's backend_type error message names both real
   policies (213-214).
8. `summarize_registry`'s `name.()` is safe on all eight lists:
   AbstractPoissonSolver <: AbstractOctopusObject (interface.jl:70), and Registry.jl
   is included last (Octopus.jl:73-74) so every referenced root exists.
9. Error paths interpolate no `nothing`: Registry.jl:104-110 handles
   `friendly_constructor === nothing` explicitly ("(no friendly constructor)",
   pinned by runtests.jl:3254); Knowledge.jl:828 and 713 guard their
   interpolations; Policies error strings use `repr` on user input.
10. Methods.jl: all 6 tracking-method tags + `default_method` documented, each
    with a matching `description` method (64-75); Examples.jl: all 3 example
    types documented and discovered by `build_registry` (probe p4: examples
    (3)). `@element_spec`'s two grep hits inside Knowledge.jl are docstring text,
    not registrations: real blocks = 30, matching 30 registered kinds (probe p2).

Minor notes (below lead threshold): `@element_spec` silently ignores
non-assignment items in its block (Knowledge.jl:320-325); a parameter literally
named `params` would be shadowed by the storage-field short-circuit
(Knowledge.jl:67); `_element_meta_or_nothing(T::Type)`'s subtype scan (350-356)
swallows subtype errors in a bare catch and takes the first match in IdDict
order (benign while friendly types are disjoint);
`validate_configuration_metadata`'s hardcoded policy tuple (interface.jl:1544)
is the already-tracked U3-4 (docs/todo.md:26).

## Probe index

- scratchpad/U13/p1_unknown_keyword.jl — U13-1, U13-2
- scratchpad/U13/p2_registry_enum.jl — class 2 closure, validator pass, counts
- scratchpad/U13/p3_validator_blindspots.jl — U13-3, U13-4
- scratchpad/U13/p4_snapshot_diff.jl (+ diff) — class 6 freshness
- scratchpad/U13/p5_docstrings.jl, p5_out.txt — U13-5
