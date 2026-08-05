# U12 Report — metadata / registry / policy architecture layer

Commit audited: `7de4d81` (HEAD). Prior full audit declared `6a3f39ab`; 64 commits
have landed since (`git rev-list --count 6a3f39ab..HEAD` = 64). The regional diff
`git diff 6a3f39ab HEAD -- src/knowledge/ src/registry/ src/policies/ src/Octopus.jl
src/constants/ src/examples/ src/analysis/ src/elements/Elements.jl
src/tasks/StrongStrong.jl` touches four files (+209/-9): `src/Octopus.jl` (+47),
`src/knowledge/Knowledge.jl` (+131), `src/policies/Policies.jl` (+28),
`src/registry/Registry.jl` (+12). It was read first, in full.

Predecessor report: `docs/history/comprehensive_audit_2026_08_05_unit_reports/U13_report.md`
(commit `7a8e9ca`). This pass re-verified its open items rather than inheriting them.

Julia 1.12.4. CUDA present and functional on this host, so the CUDA legs of the
policy probes actually ran.

## Region and provenance

READ, every line:

| file | lines | read |
| --- | --- | --- |
| `src/knowledge/Knowledge.jl` | 1072 | all |
| `src/knowledge/Methods.jl` | 75 | all |
| `src/registry/Registry.jl` | 226 | all |
| `src/policies/Policies.jl` | 380 | all |
| `src/Octopus.jl` | 123 | all |
| `src/constants/Constants.jl` | 32 | all |
| `src/examples/Examples.jl` | 35 | all |
| `src/analysis/Analysis.jl` | 6 | all |
| `src/elements/Elements.jl` | 15 | all |
| `src/tasks/StrongStrong.jl` | 13 | all |

Supporting reads (targeted, for consumer tracing only — NOT audited):
`src/tasks/strongstrong/interface.jl` 1595–1795 (`validate_configuration_metadata`),
`src/beam/Beam.jl` 320–395 (`_resolve_execution_policy`),
`src/track/phase6d_track.jl` 240–300 (`_cuda_resolve_fused_blocks`),
`src/elements/misalignment.jl` 229–290, `src/elements/ref_tilt.jl` 99–137,
`src/knobs/Knobs.jl` 982–995 (`resolve_knobs`), `src/track/Track.jl` 1–64,
`src/tasks/strongstrong/pic_cuda.jl` 1195–1220 & 5650–5670,
`src/tasks/strongstrong/gaussian_pic_cuda.jl` 188–200,
`test/runtests.jl` 40–60 & 3390–3410, `AGENTS.md` (full),
`docs/comprehensive_audit.md` "Measured Lessons", `docs/public_api.md`,
`docs/registry_snapshot.md`.

EXECUTED (all under `julia --startup-file=no --project=/cfs/ad/dxu/Library/Julia/Octopus`;
probe scripts in session scratch `…/scratchpad/audit/`, no repository file touched):

| probe | what it measures |
| --- | --- |
| `p1_baseline.jl` | validators, snapshot identity, export/docstring counts, registry counts |
| `p2_inject.jl` | 22 temporary lying `ElementMeta` registrations + negative control |
| `p3_inject2.jl` | corrected D21, new D23, multi-method exposure, placement-key coverage |
| `p4_sweeps.jl` | per-declared-method compile sweep; `validate_configuration_metadata` tree-guard completeness (injects concrete types **inside** the Octopus module) |
| `p5_constants.jl` | 256-bit BigFloat CODATA-2022 / exact-math check of all 9 constants |
| `p6_docstring.jl` | Julia-1.12 interposed-comment docstring detachment, with synthetic control |
| `p7_policy_consumers.jl` | executed policy-field → consumer-boundary receipts, CPU **and** CUDA |
| `p8b_dup_and_warn.jl` | duplicate `@element_spec` for an existing kind; warning re-fire |
| `p9_examples_desc.jl` | `AbstractExample` instantiation; `description()` coverage over the registry |
| `p10_tautology.jl` | friendly-vs-raw check tautology; kinds skipping the runtime-match check |
| `p11_active_launch.jl` | `_active_cuda_launch` as an undeclared second consumer of the policy launch |

No repository file was modified. Every injected defect was registered into the
in-process registry and unregistered again inside the same probe.

---

## Injected-defect measurement: **15 caught of 23**

Method: a temporary honest `ElementMeta` for kind `:u12_fake` (Main-defined
tracking method, runtime type, and friendly constructor) is registered, one lie
at a time, and `validate_element_metadata()` is run; errors are filtered to the
fake kind. `D0` is the negative control and validates clean (0 errors), so every
CAUGHT below is attributable to the injected lie alone.

Repro: `julia --startup-file=no --project=. …/audit/p2_inject.jl` (prints
`CAUGHT 16 of 22`, of which D21 is a probe artifact — see below) and
`…/audit/p3_inject2.jl` (D21 corrected → MISSED, plus D23 → MISSED).
Corrected tally: **15 caught, 8 missed, 23 injected.**

### Caught (15)

| # | injected lie | error message emitted |
| --- | --- | --- |
| D1 | `tracking_methods` holds a non-`AbstractTrackingMethod` | "declares tracking method Int64, which is not an AbstractTrackingMethod" |
| D2 | `contracts` holds a non-`AbstractContract` | "declares contract Int64…" |
| D3 | `analyses` holds a non-`AbstractAnalysis` | "declares analysis Int64…" |
| D4 | `runtime_type` absent from the `runtime_types` map | "runtime_type Float64 is not in its runtime_types map" |
| D5 | unapproved physics keyword | "has unapproved physics keyword u12_not_a_keyword" |
| D6 | parameter both `required` and defaulted | "parameter a is required but has a default" |
| D7 | example missing a required parameter | "example is missing required parameter ghost" |
| D8 | example carries an undeclared parameter | "example contains undeclared parameter zz" |
| D9 | `construction_help` omits a declared parameter | "construction_help does not mention parameter a/b/tracking_method" |
| D10 | declared method with no runtime type | "has no runtime type for Symplectic6DMap" |
| D11 | example does not compile | "example does not compile: MethodError…" |
| D12 | example compiles to an undeclared type | "example compiles to U12Runtime, which is not a declared runtime type" |
| D13 | example is a spec of another kind | "example kind is drift" (+3 more) |
| D14 | duplicate kind under a second `spec_type` | "duplicate ElementMeta kind u12_fake" |
| D15 | friendly constructor resolves to a different meta | "friendly_constructor schema disagrees with raw spec" (+2 more) |

### Missed (8) — each named

| # | injected lie | why nothing sees it | lead |
| --- | --- | --- | --- |
| **D16** | declared `default=99.0` while the friendly constructor applies `2.0` | `ParamMeta.default` is display-only; no code compares it with a constructed spec | U12-1 |
| **D17** | declared parameter `ghost` that no code ever reads | nothing records what `compile_runtime` consumes | U12-2 |
| **D18** | the runtime constructor **reads** an undeclared key (`getparam(spec, :secret, …)`) | the inverse check does not exist either | U12-2 |
| **D19** | declared `unit="furlong"` on a length used as metres | units are free text | U12-6 |
| **D20** | approved-but-false keywords (`:radiation, :beam_beam, :collimation` on a drift-like kick) | keyword membership is checked, keyword *truth* is not | U12-6 |
| **D21** | `construction_help = "Absolutely tracking_method."` — every schema key is only an accidental substring | the check is `occursin(string(key), help)` | U12-5 |
| **D22** | `description` says "Thick quadrupole magnet with fringe fields" on a thin kick | descriptions are free text | U12-6 |
| **D23** | a *second* declared method maps to a nonsense runtime type; the single example uses the first method | the match is `any(rt -> …, values(runtime_types))` and only one example exists | U12-4 |

Three of the eight (D16, D17, D18) are exactly the blind spots the prior pass
recorded as still open. Five (D19–D23) are additional shapes this pass measured.

**Hypothesis (a)(iii) — `validate_configuration_metadata`'s hardcoded type
enumeration — is HALF closed.** Injecting a concrete type *inside* the Octopus
module (`p4_sweeps.jl`):

| injected type | caught? |
| --- | --- |
| concrete `AbstractPoissonSolver` with no schema block | **CAUGHT** ("is a concrete AbstractPoissonSolver with no validate_configuration_metadata block") |
| concrete `AbstractBeamObserver` with no schema block | tree guard present (interface.jl:1770–1780) |
| concrete `AbstractExecutionPolicy` with no schema block | **MISSED** — validator returned `true` |
| concrete `AbstractSchedule` with no schema block | **MISSED** — validator returned `true` |

---

## Constants: verified independently against CODATA-2022, max **0.4630 ulp**

Repro: `julia --startup-file=no --project=. …/audit/p5_constants.jl`.
Reference values entered independently of the source, compared in 256-bit
`BigFloat`; "ULP" is `|stored − exact| / eps(stored)`.

| name | stored | reference (CODATA-2022 / exact) | ulp | rel. err | documented unit | verdict |
| --- | --- | --- | --- | --- | --- | --- |
| `CLIGHT` | 299792458.0 | 299 792 458 (SI, exact) | 0.0000 | 0 | "meters per second" | exact, correct |
| `RE` | 2.8179403205e-15 | r_e = 2.817 940 3205(13)e-15 m | 0.2656 | 3.72e-17 | "meters (2022 CODATA)" | correct |
| `EMASS_EV` | 0.51099895069e6 | m_e c² = 0.510 998 950 69(16) MeV | 0.4630 | 5.27e-17 | "eV (2022 CODATA)" | correct |
| `ME0` | = `EMASS_EV` | alias | 0.4630 | 5.27e-17 | "Compatibility alias" | correct |
| `PMASS_EV` | 938.27208943e6 | m_p c² = 938.272 089 43(29) MeV | 0.4400 | 5.59e-17 | "eV (2022 CODATA)" | correct |
| `TWOPI` | 6.283185307179586 | 2π | 0.2758 | 3.90e-17 | dimensionless | correct |
| `SQRT2PI` | 2.5066282746310007 | √(2π) | 0.4127 | 7.31e-17 | dimensionless | correct |
| `SQRTPI` | 1.772453850905516 | √π | 0.3453 | 4.33e-17 | dimensionless | correct |
| `SQRT2` | 1.4142135623730951 | √2 | 0.4354 | 6.84e-17 | dimensionless | correct |

All nine are **bit-identical to the correctly-rounded nearest `Float64`** of their
reference value (probe prints `YES` for each), i.e. the deviations above are pure
representation error, not transcription error. Max 0.4630 ulp — this independently
reproduces the prior pass's "≤ 0.47 ulp".

Independent cross-checks (not just re-reading the same CODATA row):

- `r_e = α · ƛ_C` (α = 7.2973525643e-3, ƛ_C = 3.8615926744e-13 m) → 2.817940320481e-15,
  relative difference from `RE` = **6.57e-12** (CODATA u_r(r_e) ≈ 4.6e-10).
- `r_e = α² · a₀` (a₀ = 5.29177210544e-11 m) → 2.817940320432e-15, rel. diff = **2.41e-11**.
- `PMASS_EV / EMASS_EV` = 1836.152673431 vs CODATA m_p/m_e = 1836.152673426,
  rel. diff = **2.85e-12** (CODATA u_r ≈ 1.7e-11).

All three sit well inside the CODATA uncertainties, so the four physical
constants are mutually consistent as well as individually correct. The four
mathematical constants carry 43 source digits each, far beyond `Float64`, so the
literals cannot be mis-rounded. **No lead against `src/constants/Constants.jl`.**

---

## Registry snapshot: byte-identical

`registry_snapshot_markdown()` regenerated into scratch and compared:

```
diff docs/registry_snapshot.md …/audit/registry_snapshot_regen.md   → exit 0
cmp  …                                                             → identical
md5  8b7e8f167adf4927a9088b492b0119c6  (both files, 16 186 bytes)
```

No drift. Freshness is additionally gated in the suite at `test/runtests.jl:58`
(`registry_snapshot_markdown() == read(snapshot_path, String)`), and that testset
("Architecture integrity") sits near the top of `runtests.jl`, so it is not in the
abort-shadow the file's own header warns about.

Totalization check on the one hand-maintained part: all **21** concrete
`AbstractTrackOp` subtypes appear in the snapshot's Runtime Objects section
(`p8_misc.jl`, "absent = 0"). The U13-6 staleness is closed. What remains is the
absence of a *tripwire* — see U12-19.

---

## Policy type / field → runtime consumer table

Every row below was **executed**, not grepped: the field was set to a non-default
value and the execution audit was asked whether that value reached a consumer
boundary (`p7_policy_consumers.jl`, on this CUDA host).

| type | field | declared consumer | observed at the boundary | evidence |
| --- | --- | --- | --- | --- |
| `PlaceholderPolicy` | (none) | — | `backend_type` raises the documented error; `execute!` raises the same; `configuration_report` = `()`; `policy_option_schema` = `NamedTuple()` | executed |
| `CPUThreadsExecutionPolicy` | `threads` | `:cpu_logical_workers` | receipt ×2, `(workers = 3, pool_threads = 4)` | executed |
| `CUDALaunchConfig` | `threads` | `:cuda_fused_launch` | `(threads = 128, …)` and `(threads = 64, …)` and `(threads = 32, …)` | executed |
| `CUDALaunchConfig` | `blocks` | `:cuda_fused_launch` | explicit `7` → `blocks = 7, requested_blocks = 7`; `:auto` → `blocks = 64, requested_blocks = :auto` | executed |
| `CUDAExecutionPolicy` | `device` | `:cuda_device` | receipt `(device = 0,)` | executed |
| `CUDAExecutionPolicy` | `launch` | (container) | forwarded, both fields observed above | executed |
| `GPUExecutionPolicy` | `threads`,`blocks`,`device` | `:cuda_fused_launch`, `:cuda_device` | `(threads = 32, blocks = 5, …)`, `(device = 0,)` via `_legacy_cuda_policy` | executed |
| `AbstractGPUExecutionPolicy` | — | — | **no method anywhere dispatches on it** (4 repo occurrences, none a signature) | grep |
| `ResolvedCPUExecutionPolicy` | `threads` | — | `_run_logical_workers` / `_cpu_worker_count` (11 call sites) | grep + executed |
| `ResolvedCUDAExecutionPolicy` | `device` | — | `Beam.jl:366` `CUDA.device!`, `interface.jl:207,2188` | grep |
| `ResolvedCUDAExecutionPolicy` | `threads`,`blocks` | — | `_cuda_resolve_fused_blocks`, `_active_cuda_launch` | grep + executed |
| `ConfigurationOptionMeta` | `option_type` | — | `solver_help`/`policy` printers (interface.jl:372,444) | grep |
| `ConfigurationOptionMeta` | `default` | — | `validate_configuration_metadata` (≈12 sites) | grep |
| `ConfigurationOptionMeta` | `meaning` | — | help printers, `Knowledge.jl:812,821` | grep |
| `ConfigurationOptionMeta` | `category` | — | `Contracts.jl:2341,2551,2558,2648` | grep |
| `ConfigurationOptionMeta` | `supported_backends` | — | `Contracts.jl:2509,2596`, `interface.jl:1505,1554,1574,2068,2081`, `spectral.jl:230` | grep |
| `ConfigurationOptionMeta` | `dependencies` | — | `interface.jl:450` (display only) | grep |
| `ConfigurationOptionMeta` | `consumer` | — | `Contracts.jl:2552,2651`, receipt matching | grep |
| `ConfigurationEntry` | `name`,`requested`,`resolved`,`status`,`consumer` | — | `Contracts.jl:401–411`, `interface.jl:1789`, `runtests.jl:7100` | grep |
| `ConfigurationEntry` | **`reason`** | — | **read by nothing** in `src/`, `test/`, `validation/`, `examples/` | grep (0 hits for `.reason`) |
| `ExecutionAuditReceipt` | `consumer`,`values` | — | every effectiveness contract | grep |
| `ExecutionAuditReceipt` | **`backend`** | — | **read by nothing** (0 hits for `.backend` and `:backend`) | grep → U12-13 |

No policy **type** is speculative in the AGENTS.md sense — every one either
executes (`CPUThreads`, `CUDA`, legacy `GPU`) or is the sanctioned
`PlaceholderPolicy`. Two *fields* (`ConfigurationEntry.reason`,
`ExecutionAuditReceipt.backend`) and one *abstract type*
(`AbstractGPUExecutionPolicy`) have no consumer; see U12-13 and U12-15.

---

## Leads

### LEAD U12-1 [Medium, confidence high] src/knowledge/Knowledge.jl:891-902 (declared-defaults check absent)
Claim: `ParamMeta.default` is decoration — nothing in the repository compares a
declared default with the value the friendly constructor actually stores, so a
schema may advertise a default the element does not use.
Mechanism: `validate_element_metadata` reads `pmeta.default` in exactly one place
(`pmeta.required && pmeta.default !== nothing`, Knowledge.jl:893) and otherwise
only for display (`_schema_meta_suffix_param`, `_omit_example_key`). The
machinery to do better already exists one layer over:
`validate_configuration_metadata` does
`isequal(getproperty(default_slicing, name), meta.default)` for every policy,
solver, schedule, diagnostics and observer option. Elements get no such pass, so
`element_help`, `parameter_schema` and every generated doc can state a default
the constructor contradicts — the same "declared schema vs the runtime that
consumes it" seam class the audit history names as this repository's densest.
Repro: `julia --startup-file=no --project=. …/audit/p2_inject.jl`; case D16
declares `b=ParamMeta(default=99.0)` while the constructor applies `2.0` and the
validator reports **0 errors** for the kind (line prints `MISSED  D16 …`).

### LEAD U12-2 [Medium, confidence high] src/knowledge/Knowledge.jl:904-910, 948-965 (parameter-is-read and read-is-declared both absent)
Claim: nothing verifies that a declared element parameter is consumed by the
compile, nor that every key the compile consumes is declared — a schema can carry
inert parameters and the runtime can read undeclared ones, both silently.
Mechanism: the only schema/example cross-check is set containment in ONE
direction over the *example's* keys (`key in schema_keys`, line 907). The compile
check (948–965) asserts only the *type* of the product. A runtime constructor is
free to `getparam(spec, :secret, default)` for a key no schema mentions — the
user has no way to discover it and `element_help` will never print it — and a
schema is free to declare a key that no constructor reads, which the drift's own
honestly-documented `nst`/`integrator_order` show is a real shape (they are inert
by design and there is no declared-inactive annotation to distinguish "inert on
purpose" from "silently dropped").
Repro: `…/audit/p2_inject.jl`; case D17 adds a schema key `ghost` no code reads
and case D18 makes the runtime read an undeclared `:secret`; both print
`MISSED`. The complementary positive control: `…/audit/p3_inject2.jl` reports
"kinds missing at least one placement key = 0", i.e. the *specific* instance of
this class the prior pass found (U13-2, x_offset undeclared on 17 of 30 kinds,
ref_tilt on 29 of 30) is now closed for all 30 kinds — but only by hand-splicing
`_PLACEMENT_PARAMS`, with no check that would notice the next one.

### LEAD U12-3 [Medium, confidence high] src/tasks/strongstrong/interface.jl:1617 and :1743 — hardcoded POLICY and SCHEDULE lists (declared in src/policies/Policies.jl)
Claim: `validate_configuration_metadata`'s type enumeration was totalized for
solvers and observers but **not** for execution policies or schedules; a new
concrete `AbstractExecutionPolicy` or `AbstractSchedule` is unchecked until
someone edits a tuple.
Mechanism: the solver and observer loops now walk `subtypes(...)` and fail on any
concrete Octopus-owned type lacking a block (interface.jl:1712–1724, 1768–1780 —
the U3-4 repair). The policy loop is still
`for policy_type in (CPUThreadsExecutionPolicy, CUDAExecutionPolicy, GPUExecutionPolicy)`
and the schedule loop is still
`for schedule_type in (AlwaysSchedule, EveryNSteps, AtTurns)`; neither has a
counterpart guard. `PlaceholderPolicy` is already outside the policy tuple today
(harmlessly, since its schema is empty), which shows the omission is live rather
than theoretical. This is a seam — the declaration lives in my region
(`policy_option_schema`, Policies.jl:321–328), the enumeration in another unit's
file — and I stop at naming it.
Repro: `julia --startup-file=no --project=. …/audit/p4_sweeps.jl`. It `@eval`s a
concrete `U12FakePolicy <: AbstractExecutionPolicy` and a concrete
`U12FakeSchedule <: AbstractSchedule` **inside the Octopus module** (so the
`parentmodule(T) === @__MODULE__` gate cannot excuse them); the probe prints
`MISSED` for both and `CAUGHT` for the equivalent `AbstractPoissonSolver`.

### LEAD U12-4 [Medium, confidence med] src/knowledge/Knowledge.jl:960-964
Claim: for an element declaring more than one tracking method, only the
mapping used by its single registered example is ever exercised; the other
`runtime_types` entries can name anything.
Mechanism: the check is
`any(rt -> rt isa Type && _compiled_matches_runtime(compiled, rt), values(meta.runtime_types))`
over ONE compiled example. `compile_runtime(example)` selects the example's own
`:tracking_method`, so a map entry for any other declared method is never
constructed. `haskey(meta.runtime_types, tracking_method)` (line 922) proves an
entry *exists*, never that it is *right*. Live exposure: `:lumped_radiation`
declares `Radiation6DMap, Damping6DMap, Diffusion6DMap` and its example uses
`Radiation6DMap`, so two of its three declared mappings are unvalidated.
Repro: `…/audit/p3_inject2.jl` — case D23 maps `Symplectic6DMap => Int` beside an
honest `U12Method => U12Runtime` and prints `MISSED`; the same script lists the
in-repo multi-method kinds. The totalized version of the check
(`…/audit/p4_sweeps.jl`, part 1) compiles every example under **every** declared
method: **31 (kind, method) pairs, 0 failures** — so extending the check costs
nothing today and closes the hole permanently.

### LEAD U12-5 [Low, confidence high] src/knowledge/Knowledge.jl:899-900
Claim: the "construction_help mentions every parameter" check is a bare substring
test, so help text that documents nothing can satisfy it — a single-letter
parameter name is matched by almost any English sentence.
Mechanism: `occursin(string(key), construction_help(T))`. For schema keys `a` and
`b`, the help string `"Absolutely tracking_method."` contains every key as an
accidental substring and passes.
Repro: `…/audit/p3_inject2.jl`, D21 → `MISSED`. (The same case in the earlier
`p2_inject.jl` run printed `CAUGHT`; that was a probe artifact — dropping
`tracking_method` from the schema also removed it from the example, so the
example failed to compile for an unrelated reason. `p3_inject2.jl` is the clean
measurement.)

### LEAD U12-6 [Low, confidence high] src/knowledge/Knowledge.jl:173-180, 886-889
Claim: three metadata channels the framework presents as authoritative —
parameter `unit`, `physics_keywords`, and `description` — are unvalidated free
text; a wrong one is indistinguishable from a right one.
Mechanism: `ParamMeta.unit` is only ever concatenated into help output
(`_schema_meta_suffix_param`); keywords are checked for *membership* in
`ALLOWED_PHYSICS_KEYWORDS` but never for truth; `description` is stored and
echoed. AGENTS.md stakes agent orientation on exactly these fields ("Agents use
these tags to locate related implementations and examples", Knowledge.jl:559–560).
Severity is Low because no automated consumer acts on them, but it bounds what
"self-describing source" currently guarantees.
Repro: `…/audit/p2_inject.jl` cases D19 (`unit="furlong"` on a length), D20
(`keywords = [:radiation, :beam_beam, :collimation]` on a kick), D22
(`description = "Thick quadrupole magnet with fringe fields"` on a thin element)
— all three print `MISSED`.

### LEAD U12-7 [Low, confidence high] src/knowledge/Knowledge.jl:316-323
Claim: a second `@element_spec` block for an already-registered kind silently
replaces the first; nothing warns, and `validate_element_metadata()` passes.
Mechanism: `register_element_meta!` does `ELEMENT_META_BY_KIND[meta.kind] = meta`
and `ELEMENT_META_BY_SPEC_TYPE[meta.spec_type] = meta` unconditionally, while
`register_element_spec!` de-duplicates the type list. The validator's duplicate
detector keys on `seen_kinds` while iterating `registered_element_specs()`, so
two blocks sharing one `spec_type` are seen exactly once and the loser is
invisible. A copy-pasted or merge-duplicated declaration therefore wins or loses
by include order with no signal — the "loud beats silent" rule inverted.
Repro: `julia --startup-file=no --project=. …/audit/p8b_dup_and_warn.jl`. It
re-registers `:drift` with only the `description` changed and prints
`description now = "HIJACKED: a second block silently replaced the first"`,
`registered specs = 30`, `validate passed = true errors=0`.

### LEAD U12-8 [Low, confidence high] src/knowledge/Knowledge.jl:967-982
Claim: three of the validator's checks — friendly schema, friendly
`construction_help`, friendly example kind — are tautological for all 30
registered kinds, because both sides read the same `ElementMeta` object.
Mechanism: `parameter_schema(T)` and `parameter_schema(friendly)` both route
through `_element_meta_or_nothing`, which returns the identical meta for a
`spec_type` and its `friendly_constructor`. The comparison is therefore
`x == x`. The checks only bite when `register_friendly_alias!` points a friendly
type at a *different* meta (which D15 confirms they do catch) — i.e. they guard
alias misregistration, not the schema agreement their error messages claim. This
is a residue of the circular-validation class the 2026-08-04 rewrite targeted.
Repro: `julia --startup-file=no --project=. …/audit/p10_tautology.jl` →
"kinds whose friendly_constructor resolves to the SAME ElementMeta object:
30 / 30", "kinds where it resolves to a DIFFERENT meta: String[]".

### LEAD U12-9 [Low, confidence high] src/knowledge/Knowledge.jl:834-839
Claim: the docstring on `_compiled_matches_runtime` is **detached** — the four
explanatory comment lines the U13-4 fix inserted between the docstring and the
`function` line silently break the attachment on Julia 1.12, which is the exact
gotcha that same audit recorded.
Mechanism: on this Julia a string literal followed by comment lines and then a
definition attaches to nothing, with no warning. `test/runtests.jl:3397` ("Every
export is documented") is the tripwire that closed the class, but it iterates
`names(Octopus)`, and `_compiled_matches_runtime` is not exported — so the
tripwire structurally cannot see this instance. A repo-wide scan finds exactly
two occurrences of the pattern, both non-exported:
`src/knowledge/Knowledge.jl:834` (mine) and `src/beam/Beam.jl:61`
(`_alloc_randn`, another unit's region — noted, not audited).
Repro: `julia --startup-file=no --project=. …/audit/p6_docstring.jl` prints
`DETACHED = true` for `Octopus._compiled_matches_runtime`, alongside a synthetic
control pair in a fresh module where the comment-free twin reads `HAS DOC` and
the comment-separated twin reads `NO DOC`.

### LEAD U12-10 [Low, confidence med] src/knowledge/Knowledge.jl:839-845, 955-959
Claim: the knowledge layer hard-codes the list of generic placement wrappers
(`MisalignedElement`, `RefTilted`); `CompositeLine` is not unwrapped, and `:line`
is the one kind whose declared-runtime match is skipped entirely — so the U13-4
defect regenerates the moment a third wrapper or a `:line` runtime declaration
appears.
Mechanism: `_compiled_matches_runtime` names two element-layer types explicitly
inside `src/knowledge/`. Any future generic wrapper (a girder, a slice container)
must be hand-added here or every example carrying it is falsely rejected — the
same hand-copied-knowledge shape, with no declaration-to-coverage tripwire. And
the new fallback at 955–959 is gated on `meta.runtime_type isa Type`, so a kind
declaring neither `runtime_types` nor a `runtime_type` gets its example
**compiled but not type-checked**. `:line` is exactly that kind today (verified),
which means U13-3 is only half closed: the example now compiles (good), but what
it compiles to is still unasserted.
Repro: `julia --startup-file=no --project=. …/audit/p10_tautology.jl` →
"line: runtime_types empty AND runtime_type=nothing -> only the COMPILE is
checked, not what it compiles to" and "CompositeLine … unwrapped? false".

### LEAD U12-11 [Medium, confidence high] src/policies/Policies.jl:259-264
Claim: `_active_cuda_launch` is an **undeclared second consumer** of
`CUDAExecutionPolicy`'s `threads`/`blocks`: it applies them to real strong-strong
kernels, emits no execution receipt, is named by no schema, resolves `:auto` by a
different rule than the documented one, and silently substitutes `(256, 256)`
when no CUDA policy is in scope.
Mechanism: `_CUDA_POLICY_OPTION_SCHEMA` (Policies.jl:287–298) declares
`consumer=:cuda_fused_launch` for both `threads` and `blocks`, and only
`_cuda_launch_track_policy!` (phase6d_track.jl:266) emits that receipt.
`_active_cuda_launch` reads the same `_ACTIVE_RESOLVED_POLICY` fields and its
result launches `_cuda_gaussian_reduce_partials_kernel!`,
`_cuda_gaussian_build_moments_kernel!` and `_cuda_gaussian_fused_kick_kernel!`
(pic_cuda.jl:1205,1208,1213, 5661; gaussian_pic_cuda.jl:194) with no receipt at
all — so `configuration_report` under-reports where the value goes and the
effectiveness contracts cannot observe it there. Two further divergences from the
`CUDALaunchConfig` docstring ("`blocks=:auto` uses occupancy and particle
coverage"): this path uses `min(cld(nitems, threads), 256)` — coverage only, hard
cap 256, no occupancy query — whereas the fused path uses
`CUDA.active_blocks × SM count` (phase6d_track.jl:240–253). One documented option,
two resolution semantics. The `policy isa ResolvedCUDAExecutionPolicy || return
(threads=256, blocks=256)` fallback additionally discards a user's explicit
request without a word if the scope is ever missing. Seam: declaration here,
consumption in `src/tasks/strongstrong/` — I stop at naming it.
Repro: `julia --startup-file=no --project=. …/audit/p11_active_launch.jl`. Inside
`_with_resolved_policy(ResolvedCUDAExecutionPolicy(0, 64, 3))` it prints
`(threads = 64, blocks = 3)` for n = 100/1e5/1e7 with
`receipts emitted by these calls: 0`; with `blocks=:auto` it prints
`blocks = 256` at n = 1e5 where coverage alone wants 1563; and outside any scope
it prints `(threads = 256, blocks = 256)`.

### LEAD U12-12 [Low, confidence high] src/policies/Policies.jl:330-338
Claim: the public `configuration_report` docstring states a six-item status
vocabulary of which one value is never produced anywhere and another does not
exist under the name given.
Mechanism: the docstring says entries report "resolved, inherited, inactive,
library-managed, deprecated, or still awaiting runtime information". Enumerating
every `ConfigurationEntry` construction in `src/` yields exactly six symbols:
`:resolved`, `:unresolved`, `:inherited`, `:deprecated`, `:inactive_backend`,
`:inactive_dependency`. There is **no** `:library_managed` status anywhere (the
only "library-managed" text in the repo is a *meaning* string about cuFFT in
interface.jl:151), and "inactive" is two distinct symbols, neither of which is
`:inactive`. The vocabulary is prose, hand-copied, and unchecked — the drift
shape Measured Lesson 4 names.
Repro: `grep -rn "ConfigurationEntry(" src/ | grep -o ":[a-z_]*,"` plus
`grep -rni "library.managed\|:library" src/ test/` (one hit, and it is not a
status).

### LEAD U12-13 [Low, confidence high] src/policies/Policies.jl:45-50, 83-87
Claim: `ExecutionAuditReceipt.backend` is written at every one of the ~30
consumer boundaries and read by nothing, so the effectiveness contracts — whose
whole purpose is to prove a value reached the right consumer — cannot tell a CPU
receipt from a CUDA one.
Mechanism: `_record_execution!(consumer, backend, values)` stores the backend tag;
every consumer in `src/contracts/Contracts.jl` and `validation/` filters on
`r.consumer` and reads `r.values` only (`grep -rn "\.backend\b" src/ test/` → 0
hits; `grep -rn ":backend\b"` → 0 hits). Several consumer symbols are genuinely
backend-polymorphic — `:observer_output`, `:hook_schedule`, `:isolated_tracking`,
`:solver_runtime`, `:strong_strong_diagnostics/_output/_collision`,
`:spectral_luminosity_schedule`, `:pic_luminosity_schedule` all pass a computed
backend — so a CUDA-declared option could in principle be certified effective by
a receipt emitted on CPU. The discriminator exists in the data and is simply not
consulted. Seam to the contracts region.
Repro: `grep -rn "\.backend\b" src/ test/ validation/ examples/` → no matches;
`…/audit/p7_policy_consumers.jl` shows the field is populated
(`backend=DataType[CPUThreadsBackend]`, `backend=DataType[CUDABackend]`).
`ConfigurationEntry.reason` is the same shape (`grep -rn "\.reason\b"` → 0 hits
repo-wide), one severity lower because it is human-facing prose.

### LEAD U12-14 [Low, confidence high] src/policies/Policies.jl:96-102, 185-210
Claim: `PlaceholderPolicy` and the deprecated `GPUExecutionPolicy` — both
exported public types with behaviour (an error contract, a depwarn, a
compatibility adapter, three `configuration_report` entries each) — have **zero**
coverage outside `src/`.
Mechanism: `grep -rl` over `test/`, `validation/`, `examples/`, `profiling/`
returns nothing for either name, nor for `_legacy_cuda_policy` or
`activate_policy!`. `validate_configuration_metadata` touches
`policy_option_schema(GPUExecutionPolicy)` but never constructs one, so the
constructor, the `Base.depwarn`, `backend_type(::GPUExecutionPolicy)`,
`_legacy_cuda_policy`, and `configuration_report(::GPUExecutionPolicy)` are
executed by no gate. Measured Lesson 1's class ("correct check, never executed")
applied to code rather than to checks: the paths are correct today — this pass
executed them by hand and they behaved as documented — but nothing would notice
if they stopped being.
Repro: `for p in PlaceholderPolicy GPUExecutionPolicy _legacy_cuda_policy
activate_policy!; do grep -rln "$p" test/ validation/ examples/ profiling/; done`
→ empty for all four. `…/audit/p7_policy_consumers.jl` executes both paths and
shows them correct: PlaceholderPolicy raises the documented message from both
`backend_type` and `execute!`; `GPUExecutionPolicy(threads=32, blocks=5, device=0)`
reaches `(threads = 32, blocks = 5, requested_blocks = 5, …)` and `(device = 0,)`.

### LEAD U12-15 [Low, confidence high] src/policies/Policies.jl:131-138
Claim: `AbstractGPUExecutionPolicy` is a taxonomy node whose documented purpose is
unrealised — no method in the repository dispatches on it — and it is the one
registry-listed policy with no `description`.
Mechanism: its docstring (added by the prior audit) says it exists "so GPU-generic
code can dispatch on the family without naming a vendor", but the type appears in
exactly four places repo-wide: the export list, its own declaration, and the two
`<:` supertype positions. Zero method signatures. It is nevertheless published in
`docs/registry_snapshot.md:280` as an execution policy. AGENTS.md's "do not add
speculative policy types" is written about concrete policies; this is the same
principle one level up — a published abstraction that documents a capability the
code does not have.
Repro: `grep -rn "AbstractGPUExecutionPolicy" . --include="*.jl"` → 4 hits, none a
signature; `…/audit/p9_examples_desc.jl` lists it as the only policy with an
empty `description()`.

### LEAD U12-16 [Low, confidence high] src/examples/Examples.jl:1-35
Claim: `Example` is one of AGENTS.md's seven Core Objects, and its entire runtime
realisation is three structs that are never instantiated anywhere — so the
reflection registry's answer to "Which examples should an agent imitate?" is three
empty type names.
Mechanism: `ReferenceExample`, `BenchmarkExample`, `ResearchStudyExample` each
carry `title::String, summary::String, objects::Vector{DataType}`. `grep -rlw`
over `src/`, `test/`, `examples/`, `validation/`, `profiling/` finds each name in
exactly one file — its own definition. `build_registry()` discovers them by type
tree and `summarize_registry().examples` returns
`[:BenchmarkExample, :ReferenceExample, :ResearchStudyExample]`; the snapshot
lists the same three names under "## Examples". The actual curated precedents
live as scripts in `examples/`, which the registry does not know about. AGENTS.md
§Self-Describing Source names this query explicitly as one the registry should
answer.
Repro: `julia --startup-file=no --project=. …/audit/p9_examples_desc.jl` prints
the three type names, `fieldnames`, and `description=""` for each; the grep above
shows one file per name.

### LEAD U12-17 [Low, confidence high] src/knowledge/Knowledge.jl:538-554 — **out of hypothesis**
Claim: `description()` silently returns `""` for 15 of the 35 types the registry
publishes, although its own docstring says these types "should extend this
method"; there is no tripwire, in contrast with the 336/336 export-docstring one.
Mechanism: `description(T::Type)` falls back to `_element_meta_or_nothing(T)`,
which is `nothing` for every non-element type, and returns `""` rather than
signalling. Measured per registry section: tracking_methods 0/6 bare,
analyses 0/1, policies 1/5 (`AbstractGPUExecutionPolicy`), contracts 5/14
(`AbstractPhysicsContract`, `AbstractImplementationContract`,
`AbstractBackendConsistencyContract`, `ElementParameterEffectivenessContract`,
`PTCConsistencyContract`), solvers **4/4**, examples **3/3**, tasks **2/2**
(`TrackingTask`, `StrongStrongTask`). The two flagship task types and every
Poisson solver describe themselves as the empty string to any agent that asks the
registry.
Repro: `julia --startup-file=no --project=. …/audit/p9_examples_desc.jl`, section
"registry types with an EMPTY description()".

### LEAD U12-18 [Low, confidence med] src/knowledge/Knowledge.jl:84-104 — **out of hypothesis**
Claim: the unknown-spec-key warning re-fires on **every** `compile_runtime` of a
knob-carrying spec, contradicting its own design note ("One warning at
construction names the unrecognized keys").
Mechanism: the warning lives in the `ElementSpec{Kind}(params::Dict)` inner
constructor — the correct choke point for construction — but `resolve_knobs`
(Knobs.jl:994) rebuilds `ElementSpec{Kind}(resolved)` on every compile of a spec
that carries a knob expression, so the constructor (and its warning) runs again
each time. It is `@warn` without `maxlog`, so a knob sweep that recompiles a
lattice per epoch bump emits one warning per typo-carrying element per
`execute!`. Only reachable when a typo already exists, hence Low; but the warning
that exists to make a typo noticeable becomes log noise that trains a user to
ignore it.
Repro: `julia --startup-file=no --project=. …/audit/p8b_dup_and_warn.jl` —
`DriftSpec(L=0.5, typo_key=1.0)` warns once and three `compile_runtime` calls add
nothing; `DriftSpec(L=@knob_expr(U12.k), typo_key=1.0)` warns once at construction
and then **once more per compile** (3 additional identical warnings for 3 calls).

### LEAD U12-19 [Low, confidence med] src/registry/Registry.jl:6-16 vs 211-226
Claim: the `OctopusRegistry` docstring still enumerates exactly three
hand-maintained snapshot pieces, but `_runtime_object_types` hand-appends six
types — a fourth hand-maintained piece the docstring does not declare — and no
tripwire ties it to the type tree.
Mechanism: the docstring (the audit-part-7 K7 correction) names "Task
Diagnostics, Knob Control, and the Runtime Objects **preamble**". The
hand-appended `Any[BeamParams, Phase6DRep, Beam, MisalignedElement, RefTilted,
CompositeLine]` is not the preamble and is not in
`registry_snapshot_markdown` at all; it is in a different function. U13-6's
*staleness* was repaired (the three wrappers were added) but its *structural*
complaint was not: the next beam-scale or wrapper runtime type still needs a hand
edit at Registry.jl:223, with nothing that fails when it is forgotten. The check
that would close it is one line and passes today.
Repro: `julia --startup-file=no --project=. …/audit/p8_misc.jl`, section (2) —
21 concrete `AbstractTrackOp` subtypes, "absent from the Runtime Objects section
= 0". That comparison is precisely the missing tripwire.

### LEAD U12-20 [Low, confidence high] src/Octopus.jl:107-121
Claim: the script-mode ForwardDiff branch is dead under every committed
invocation — `--project=.` cannot import ForwardDiff, and the test suite runs in
package mode where the flag is `false` — so the branch is executed by no gate.
Mechanism: `_HAS_FORWARDDIFF_SCRIPT_MODE = try @eval import ForwardDiff; true
catch false end`. ForwardDiff is a weak dependency and does **not** appear in
`Manifest.toml`, so under `--project=.` (the invocation AGENTS.md §Minimal
Verification prescribes, and the one every `validation/*.jl` script uses via
`include("src/Octopus.jl")`) the import fails and the rules file is never
included. In package mode the import fails by design and the extension takes over.
The only remaining route is a user whose *own* project happens to carry
ForwardDiff — a path no CI, suite, validation script or example exercises. I
executed it by hand and it is correct: in a scratch environment carrying
ForwardDiff, script mode sets the flag `true`, the module loads, and
`validate_element_metadata()` and the snapshot comparison both pass. Correct
today, gated by nothing. Seam to the U7 region, which owns the rules file.
Repro (both legs):
`julia --startup-file=no --project=. -e 'include("src/Octopus.jl"); using .Octopus;
println(Octopus._HAS_FORWARDDIFF_SCRIPT_MODE)'` → `false`;
same command with `--project=<env containing ForwardDiff>` → `true`, and
`validate_element_metadata = true`, `registry snapshot identical = true`.
Also: `grep -n ForwardDiff Manifest.toml` → no output.

---

## Clean list (what was checked, and the evidence)

1. **`validate_element_metadata()` passes with 0 errors** on the live registry
   (`p1_baseline.jl`), and runs in the suite with `throw_on_error=true`
   (`test/runtests.jl:44`) — the check executes.
2. **`validate_configuration_metadata()` returns `true`** (`p1_baseline.jl`), and
   is asserted at `test/runtests.jl:58`.
3. **`docs/registry_snapshot.md` is byte-identical** to `registry_snapshot_markdown()`
   — `diff` exit 0, `cmp` identical, matching md5 `8b7e8f16…`, 16 186 bytes.
4. **All 9 constants correct to ≤ 0.4630 ulp**, each bit-identical to the
   correctly-rounded double of its reference; every documented unit is right; the
   four physical constants are mutually consistent under three independent
   relations (see the constants table). Max deviation reproduces the prior
   pass's ≤ 0.47 ulp independently.
5. **Export surface: 336 exports, 0 unresolved, 0 undocumented** (`p1_baseline.jl`).
   The tripwire at `test/runtests.jl:3397` computes the same set and still binds.
   The Julia-1.12 detached-docstring gotcha it was built for has exactly two live
   instances repo-wide, both **non-exported** (U12-9), so the tripwire's own
   coverage boundary is exports, not bindings.
6. **Include list: complete, no duplicates, order sound.** All 50 `.jl` files under
   `src/` are included exactly once (49 `include` targets + `Octopus.jl` itself);
   `ext/OctopusForwardDiffRules.jl` is included twice **by design**, once per
   activation route, and the two routes share one file so they cannot drift.
   `src/track/fused_track.jl` is reached via `Track.jl:64`; the nine
   `strongstrong/*` files via `StrongStrong.jl`; the 15 element files via
   `Elements.jl`; `elements/aperture.jl` deliberately after `beam/Beam.jl` with
   the reason in a comment. Order is sufficient at load time in both modes
   (package mode `using Octopus` and script mode `include("src/Octopus.jl")` both
   load and both report 30 elements and a passing validator). Forward references
   in the knowledge layer (`_reject_folded_override`, `MisalignedElement`,
   `RefTilted`, `_misalignment_wrap`, `_ref_tilt_wrap`, `ELEMENT_META_BY_KIND`)
   are all inside function bodies and resolve at call time.
7. **Placement-key schema coverage is total**: all 30 registered kinds now declare
   all 8 placement parameters (`x_offset, y_offset, z_offset, x_pitch, y_pitch,
   tilt, misalign_convention, ref_tilt`) — "kinds missing at least one placement
   key = 0" (`p3_inject2.jl`). U13-2 is closed as an instance.
8. **The per-declared-method compile sweep is clean today**: 31 (kind, method)
   pairs, every example compiles under every declared method and matches its
   declared runtime type, 0 failures (`p4_sweeps.jl`). The declared→actual runtime
   map is honest; only the *check* is narrower than the map (U12-4).
9. **Runtime Objects section is complete**: all 21 concrete `AbstractTrackOp`
   subtypes appear in the snapshot (`p8_misc.jl`). U13-6's staleness is closed.
10. **Every policy field reaches a real consumer boundary with the requested
    value**, measured on CPU *and* CUDA (`p7_policy_consumers.jl`): see the table
    above. No policy type is speculative; `PlaceholderPolicy` behaves exactly as
    AGENTS.md's placeholder sanction requires (errors from `backend_type` and from
    `execute!`, empty schema, empty report) and has not quietly become real.
11. **Every `ConfigurationOptionMeta` field has a consumer** (option_type, default,
    meaning, category, supported_backends, dependencies, consumer) — traced to
    file:line in the policy table. Only `ConfigurationEntry.reason` and
    `ExecutionAuditReceipt.backend` are consumer-less (U12-13).
12. **Registry copy discipline holds**: `registered_element_specs`,
    `physics_keywords`, `supported_tracking_methods`, `supported_analyses`,
    `required_contracts`, `allowed_physics_keywords`, `execution_receipts` all
    return `copy(...)` (Knowledge.jl:299,308,564,580,595,618; Policies.jl:73).
13. **`@element_spec` rejects a mistyped metadata field loudly**: `ElementMeta`'s
    keyword constructor has no `kwargs...` catch-all, so the AGENTS.md rule "use
    `friendly_constructor`, not `friendly`" is enforced by a `MethodError` rather
    than by convention.
14. **Methods.jl is complete and self-consistent**: all 6 tracking-method tags plus
    `default_method` are documented, and each of the 6 has a matching
    `description` method (0 bare descriptions in that section, `p9_examples_desc.jl`).
15. **`Analysis.jl` is honest**: `PlaceholderAnalysis` is documented, has a
    `description`, and is the declared analysis for the kinds that have no real
    one — the placeholder discipline AGENTS.md prescribes.
16. **`_HAS_FORWARDDIFF_SCRIPT_MODE` is `false` in package mode** and
    `Base.get_extension(Octopus, :OctopusForwardDiffExt)` is `nothing` without
    ForwardDiff loaded, so the two activation routes cannot both fire and
    double-define (the overwrite trap of audit part 6 §8.7).

---

## Not checked, and why

- **The full CI-settings suite** (`Pkg.test(julia_args=["--threads=4"])`) was not
  run: that is the orchestrator's gate, not a reading unit's, and it would not
  have discriminated any lead above (each has its own reproduction).
- **Numerical correctness of anything a policy launches.** U12-11 is a claim about
  declaration and observability, not about whether the PIC/Gaussian kernels
  compute the right answer under a 256-block cap. Verifying that needs a
  strong-strong GPU convergence run and belongs to the solver units.
- **`src/contracts/Contracts.jl` and `src/tasks/strongstrong/interface.jl`** were
  read only in the specific ranges listed under provenance, purely to trace
  consumers. U12-3, U12-11 and U12-13 are flagged as seams and stop at naming.
- **`src/beam/Beam.jl:61`** (`_alloc_randn`, the second detached-docstring
  instance) is outside the region; reported as a pointer only.
- **`docs/public_api.md` completeness** was not audited against the export list:
  it is an explicitly curated map (116 `?` entries against 336 exports), not an
  index, so absence is not drift. One minor note below threshold: `set_param!`,
  the newly exported deliberate-metadata door that the `ElementSpec` docstring
  directs users to, is not listed in its "Construct Elements" section.
- **Whether any element's declared physics keywords are physically right** —
  U12-6 establishes that nothing checks them; adjudicating 30 kinds' keyword sets
  is a physics-review task, not a metadata-layer one.

## Minor notes (below lead threshold)

- `@element_spec` silently ignores non-assignment items and assignments whose LHS
  is not a `Symbol` inside its block (Knowledge.jl:415–425).
- A parameter literally named `params` is shadowed by the storage-field
  short-circuit in `getproperty`/`setproperty!` (Knowledge.jl:113,122).
- `_element_meta_or_nothing(T::Type)`'s subtype scan (Knowledge.jl:448–453)
  swallows errors in a bare `catch` and takes the first `IdDict` match — benign
  while friendly types stay disjoint, order-dependent if they ever overlap.
- `compile_runtime` builds its `MethodError` from the *original* `method`
  argument, which may be a `Type` rather than an instance (Knowledge.jl:1051) —
  cosmetic.
- `_runtime_mapping_string` (Registry.jl:198–206) iterates `meta.tracking_methods`,
  so a `runtime_types` entry keyed by a method not in that list is silently
  omitted from the snapshot.

## Probe index

All under `…/scratchpad/audit/`:
`p1_baseline.jl`, `p2_inject.jl`, `p3_inject2.jl`, `p4_sweeps.jl`,
`p5_constants.jl`, `p6_docstring.jl`, `p7_policy_consumers.jl`, `p8_misc.jl`,
`p8b_dup_and_warn.jl`, `p9_examples_desc.jl`, `p10_tautology.jl`,
`p11_active_launch.jl`, plus `registry_snapshot_regen.md` and `detached.txt`.
