# U25: Policies.jl + Knowledge.jl + Methods.jl

Reading unit of the 2026-10-18 comprehensive audit; tree `/cfs/ad/dxu/Library/Julia/Octopus`
at commit 24e8683, read-only. Every claim below is a LEAD, not a finding.

## Region

- `src/policies/Policies.jl` lines 1-1517 (whole file)
- `src/knowledge/Knowledge.jl` lines 1-1515 (whole file)
- `src/knowledge/Methods.jl` lines 1-75 (whole file)

Total 3107 lines, all read line by line.

Hypotheses briefed: (1) policy option schemas vs their consumers and constructor defaults, with an
injected defect against `validate_configuration_metadata`; (2) `ElementMeta`/`ParamMeta` validator
blind spots by injection, free-text channels, the one-precision-rule declarations per kind;
(3) the `AbstractTrackingMethod` tags (`Symplectic6DMap` vs `NonSymplectic6DMap`) and what the
registry derives from them.

## Provenance

READ line by line: the three region files in full (Methods.jl 1-75; Knowledge.jl 1-1515 in five
contiguous chunks; Policies.jl 1-1517 in five contiguous chunks).

READ as cross-references, excerpts only, to trace the consumers of what the region declares (seams
are named, not audited): `src/Octopus.jl` 1-60 (include order, backend tags, `AbstractPhaseRep`);
`src/tasks/strongstrong/interface.jl` 1886-1940 and 2240-2256 (the policy block and tail of
`validate_configuration_metadata`); `src/beam/Beam.jl` 330-470 (policy resolution, activation,
`_launcher_rank_count` consumers); `src/contracts/Contracts.jl` 1775-1800, 1920-1965, 3138-3186
(symplecticity case derivation, `_perturb_is_physical`, the Symbol-parameter candidate rule);
`src/registry/Registry.jl` 220-240 (`_runtime_mapping_string`); `src/elements/beam_line.jl`
772-800 (the `:line` block), `src/elements/aperture.jl` 462-475, `src/elements/lattice_magnets.jl`
1097-1112 and 1472-1480, `src/elements/thin_elements.jl` 285-293; `test/runtests.jl` 17820-17960
(the suite's existing element-metadata injection controls) and 21905-21975 (policy coverage
testsets); `docs/guides/configuration.md` and `docs/guides/elements.md` in full;
`docs/history/comprehensive_audit_2026_08_05_b_unit_reports/U12_report.md` sections "Leads"
(U12-2, U12-13..15, U12-17, U12-18), "Not checked" and "Minor notes"; `docs/design/multi_process_policy.md`
356-364.

EXECUTED (scratch `/cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U25/`,
each `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 <script>`, logs beside the scripts):

- `p1_knowledge.jl` -> `p1_knowledge.log` (57 s). Per-kind registry derivations over the 31 kinds;
  free-text and alternatives sweep (663 registry `ParamMeta`s, 0 empty meanings); the declared-default
  check run with and without its `haskey` gate (608 pairs; 77 gated, 531 skipped, 596 comparable,
  12 exception skips, 0 failures); five in-process injections I1-I5 against
  `validate_element_metadata` (I1 MISSED, I2 MISSED, I3 passed clean, I4 MISSED, I5 passed clean),
  registry restored and re-validated (`passed = true`) after each.
- `p2_policies.jl` -> `p2_policies.log`. Constructor-default drift injections against
  `validate_configuration_metadata` (CPU `:auto -> 1` passed; GPU `256/256 -> 128/64` passed;
  `CUDALaunchConfig` threads drift FAILED as it should; MP ranks drift FAILED as it should); schema
  keys vs `configuration_report` names vs consumers for all five policies (all agree); the launcher
  variable ordering (`MPI_LOCALNRANKS=1` + `SLURM_NTASKS=4` -> tripwire silent); the shard verdict
  at 4 ranks with counts (256,256,255,257) (ranks 0,1 proceed, 2,3 throw); `_mp_chunk_fold` has one
  2-argument method; a `_run_logical_workers` receipt under `ResolvedCPUExecutionPolicy(2)` records
  `workers = 2`.
- `p3_followup.jl` -> `p3_followup.log`. Per-kind gated coverage of the declared-default check
  (drift 0/35, marker 0/11, quadrupole 1/37, ...); `quadrupole.nst` is NOT in the quadrupole example;
  the `:line` kind's answers (`tracking_method` = `Symplectic6DMap()`, `supported_tracking_methods`
  = `[]`, `runtime_type` = `nothing`, explicit-method compile throws).
- `p4_placement_drift.jl` -> `p4_placement_drift.log`. 18 kinds splice `_PLACEMENT_PARAMS`
  identically, 13 declare their own placement entries, 79 hand-copied entries differ from the table
  (units dropped on all 79; `alternatives=()` on 7 kinds' `misalign_convention`).
- `p5_policy_rejection.jl` -> `p5_policy_rejection.log`. Invalid values and unknown keywords are
  rejected by every policy constructor; every `configuration_report` status is in
  `CONFIGURATION_STATUSES`.

No repository file was modified; no git command was run in the repository.

## Leads

### LEAD U25-1 [Moderate, confidence high] src/knowledge/Knowledge.jl:1169
Claim: `_check_declared_defaults!` skips every declared default the kind's example does not set, so `validate_element_metadata` verifies 77 of the 608 non-required defaults in the registry (12.7%), none at all on `:drift` and `:marker`, and a wrong default on a parameter the example omits passes validation while changing the compiled map.
Mechanism: the loop at :1165-1177 continues on `haskey(base, key) || continue` (:1169), where `base` is the example's stored parameters. The property the docstring states ("OMITTING a parameter compiles to the same map as passing its declared default", :1146-1147) is checkable whether or not the example stores the key: `without` is then simply the example and `withdef` the example plus the default. The gate therefore excludes exactly the parameters an example leaves at their default -- the common case -- and the kinds with the most defaults (the six lattice magnets, 35-47 each) are checked on 0-2 of them (p3). The docstring's own evidence is one of the skipped pairs: it says the check was "Verified discriminating" on `quadrupole.nst` (:1152-1153), but `nst` is not in the quadrupole example (`[:L, :kn]`, p3), so under the gate that pair is never compared. Injection I1 (p1): with drift's `h` default rewritten from `0` to `6` (a curvature), `validate_element_metadata().passed == true`, 0 errors mention `h`, while the compiled map differs between omitting `h` and passing `6` (`runtime differs ... true`). Running the same comparison ungated over the whole registry (p1 section D) compares 596 pairs and finds 0 lies today, at the cost of 12 constructor refusals (redundant strength spellings such as `k1` beside a nonzero `kn[2]`, and `line.L`) that the current `catch; continue` at :1172-1173 would swallow silently; those 12 want a visible skip, not a silent one. Defect classes 1 and 13.
Repro: `grep -n "haskey(base, key) || continue" src/knowledge/Knowledge.jl` (the gate); `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U25/p1_knowledge.jl` prints `present in the example (checked by the current gate): 77`, `absent ... (SKIPPED by the current gate): 531`, `FAILURES without the gate ...: 0`, and `I1 drift.h default 0 -> 6: passed=true mentions=0 -> MISSED`; `p3_followup.jl` prints `nst in example: false` and `total checked by gate: 77 of 608`.

### LEAD U25-2 [Moderate, confidence high] src/policies/Policies.jl:1419-1426
Claim: the `policy_option_schema` docstring says `validate_configuration_metadata()` "pins these against the constructors", but for `CPUThreadsExecutionPolicy` and `GPUExecutionPolicy` the validator compares the schema default to a literal, never to a constructed instance, so a constructor-default drift on either passes with the message "disagrees with constructor" unable to fire.
Mechanism: the schemas live in this region (:1367-1371 CPU, :1406-1417 legacy GPU); their consumer `validate_configuration_metadata` (seam: `src/tasks/strongstrong/interface.jl:1914-1916` and `:1930-1933`) evaluates `policy_option_schema(default_cpu).threads.default === :auto` and `policy_option_schema(GPUExecutionPolicy).threads.default == 256` -- the schema against a literal copy of itself. `default_cpu` is constructed and then not read. The multi-process and CUDA checks beside them do compare against constructed instances (`mp_schema.ranks.default === default_mp.ranks`; `default_cuda.launch.threads == ...`), which is why the control injections fail correctly. Injected in-process (p2): redefining the CPU keyword constructor default to `threads=1` leaves the validator `passed` with `CPUThreadsExecutionPolicy().threads == 1` against a schema default of `:auto`; redefining the legacy GPU defaults to `128/64` leaves it `passed` against `256/256`. The schema is what `configuration_report` and the registry publish, so the published default would silently disagree with what a user gets. Classes 13 and 5; this is the briefed hypothesis-1 injection, and it reports MISSED on two of the four policies.
Repro: `grep -n "threads.default === :auto\|GPUExecutionPolicy).threads.default == 256" src/tasks/strongstrong/interface.jl`; `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U25/p2_policies.jl` prints `after CPU drift: constructor default=1 schema=:auto validator: passed`, `after GPU drift: constructor default=(128, 64) schema=(256, 256) validator: passed`, and the two controls `FAILED: ... disagrees with constructor`.

### LEAD U25-3 [Moderate, confidence med] src/policies/Policies.jl:757-772 -- out of hypothesis
Claim: `_mp_resolve_shard` takes its "this rank holds the wrong count" verdict on one rank's own count although every rank already holds every rank's count after the all-sum, so a misbuilt beam can throw on some ranks and let the others proceed to the next collective.
Mechanism: `counts` is all-summed (:762), then only `length(expected) == Int(local_n)` for THIS rank is checked (:765). Because the expected shard lengths sum to `global_n` exactly as the local counts do, at two ranks a mismatch is always mutual, but at three or more a beam split off-boundary on a subset of ranks leaves the remaining ranks' counts correct. Measured with the real rule (p2, `_REDUCTION_CHUNKS = 64`): `global_n = 1024`, 4 ranks, local counts `(256, 256, 255, 257)` -> expected `256` each -> ranks 0 and 1 "PROCEEDS to the next collective", ranks 2 and 3 "THROWS". The ranks that proceed block in the next collective until the launcher notices the exited peers (an abort under the usual launchers, a hang under one that does not kill the job); either way the error text exists only on the throwing ranks. The repository's own standard for this situation is stated at `docs/design/multi_process_policy.md:360-362` ("agrees it across the ranks as a count, and throws on every rank or none") and in this file's `_mp_allminmax` docstring (:640-649). The fix is local: validate every entry of `counts` against `_mp_shard_range(global_n, nranks, r)` and throw on all ranks. Classes 6 and 7. A live multi-rank reproduction was not run (it would deadlock or abort; see Unchecked).
Repro: `grep -n "length(expected) == Int(local_n)" src/policies/Policies.jl`; `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U25/p2_policies.jl` section "S" prints the four per-rank verdicts above.

### LEAD U25-4 [Minor, confidence high] src/knowledge/Knowledge.jl:238-285
Claim: the placement-parameter schema entries exist as one table (`_PLACEMENT_PARAMS`) that the comment says is "spliced into every registered kind", but 13 of the 31 kinds carry hand-copied placement entries and 79 of those entries have drifted from the table -- every one lost its unit, and on seven kinds `misalign_convention` lost its `alternatives`, which is the field the effectiveness contract needs to perturb a Symbol parameter at all.
Mechanism: `_PLACEMENT_PARAMS` (:248-285) declares `unit="m"` on the offsets, `unit="rad"` on the pitches, `tilt` and `ref_tilt`, and `alternatives=(:bmad, :madx)` on `misalign_convention`. The six lattice magnets other than drift draw their placement entries from `_COMMON_PARAMS` (`src/elements/lattice_magnets.jl:1097-1112`, no units), the seven thin kinds and the kickers from `_THIN_COMMON` (`src/elements/thin_elements.jl:275`, no `alternatives`), and `:line` writes its own (`src/elements/beam_line.jl:784-791`). Measured over the live registry (p4): 18 kinds splice the table identically, 13 do not, 79 entries differ. The unit drift is display-level today only because the consumer already guards by key (`_perturb_is_physical` at `src/contracts/Contracts.jl:3141-3143` begins `key in _PLACEMENT_PARAM_KEYS ||`, with a comment recording that `sbend.y_offset` was measured with `unit = ""`), so `element_help(:sbend)` prints `y_offset (optional; default=0; ...)` where `element_help(:aperture)` prints `unit=m`. The `alternatives` drift has a behavioural consumer with no such guard: the candidate rule returns `()` for a Symbol parameter without alternatives (`src/contracts/Contracts.jl:3162`, `current isa Symbol && return ()`), so on `hkicker`, `kicker`, `vkicker`, `thin_dipole`, `thin_multipole`, `thin_quadrupole` and `thin_sextupole` the effectiveness contract cannot perturb `misalign_convention` -- the U4-12 gap this field was introduced to close, reopened by copying. The ParamMeta docstring in this region (:213-225) states that role. Nothing checks a kind's placement entries against the one table (the "hand-copied knowledge" invariant asks for a tripwire). Class 2; the declarations and the consumer are a seam outside this region, the table and its design claim are inside it.
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U25/p4_placement_drift.jl` prints `kinds declaring their own placement entries: 13 [...]`, `hand-copied entries whose unit/default/alternatives differ from _PLACEMENT_PARAMS: 79`, and the two `element_help` lines; `grep -n "current isa Symbol && return ()" src/contracts/Contracts.jl` is the consumer that receives no candidates.

### LEAD U25-5 [Minor, confidence high] src/knowledge/Knowledge.jl:1288-1293
Claim: `validate_element_metadata` checks that every declared tracking method has a runtime type but not that every runtime-type entry is a declared tracking method, so a kind can compile under a method that `supported_tracking_methods` denies and the registry snapshot omits.
Mechanism: the loop at :1288-1293 iterates `meta.tracking_methods` and asks `haskey(meta.runtime_types, m)`; nothing iterates `keys(meta.runtime_types)` against `meta.tracking_methods`, and the per-mapping compile at :1345-1360 only confirms each entry compiles. `compile_runtime` (:1483-1486) gates on the runtime map alone, so the map is what executes while `tracking_methods` is what the queries, the Twiss-rule tripwire and `_runtime_mapping_string` (`src/registry/Registry.jl:225-233`, iterates `tracking_methods`) publish. Injection I3 (p1): adding `Damping6DMap => LatticeMagnet` to drift's `runtime_types` with `tracking_methods` unchanged -> `passed=true`, 0 drift errors, `compile_runtime(example, Damping6DMap())` returns `LatticeMagnet{Damping6DMap, Float64, ...}`, `supported_tracking_methods(:drift) == [Symplectic6DMap]`, snapshot string `Symplectic6DMap => LatticeMagnet`. Injection I5 (emptying `tracking_methods` while the map stays) also passes, and the example still compiles. Live exposure: none -- all 31 kinds have `keys(runtime_types) == Set(tracking_methods)` (p1). Classes 5 and 2.
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U25/p1_knowledge.jl` prints `I3 ... passed=true drift errors=String[]`, `compile_runtime(example, Damping6DMap()) -> LatticeMagnet{Damping6DMap, ...}`, and `I5 ... passed=true`; `grep -n "for tracking_method in meta.tracking_methods" src/knowledge/Knowledge.jl`.

### LEAD U25-6 [Minor, confidence med] src/policies/Policies.jl:490-491 -- out of hypothesis
Claim: `_launcher_rank_count` consults `MPI_LOCALNRANKS`, a per-node rank count, before three global counts (`PMIX_SIZE`, `MV2_COMM_WORLD_SIZE`, `SLURM_NTASKS`), so under a launcher that exports the per-node variable without `PMI_SIZE`/`OMPI_COMM_WORLD_SIZE`, a one-rank-per-node job reads as a single process and the "mpiexec without MPI" tripwire stays silent.
Mechanism: the loop at :490-497 returns the first parseable variable in list order. `MPI_LOCALNRANKS` (MVAPICH2 and Intel MPI Hydra export it beside `MPI_LOCALRANKID`) is the number of ranks on the local node, not the communicator size. Its two consumers (`src/beam/Beam.jl:396-408` the warning, `:427-436` the throw when no communicator is loaded) test `launcher[2] > 1`, so a value of `1` from the per-node variable defeats both for every layout with one rank per node, and a value of `2` under-reports an 8-rank job in both messages. Measured (p2): with `PMI_SIZE`/`OMPI_COMM_WORLD_SIZE` unset, `MPI_LOCALNRANKS=1 SLURM_NTASKS=4` -> `("MPI_LOCALNRANKS", 1)`, `tripwire fires? false`; `MPI_LOCALNRANKS=2 MV2_COMM_WORLD_SIZE=8` -> `("MPI_LOCALNRANKS", 2)`; with `PMI_SIZE=8` present it is read first, so Hydra layouts are unaffected. Exposure is launcher-dependent (hence confidence med); the fix is to drop the per-node variable or move it last. Classes 6 and 11.
Repro: `grep -n "MPI_LOCALNRANKS" src/policies/Policies.jl`; `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U25/p2_policies.jl` section "L" prints the three env outcomes above.

### LEAD U25-7 [Minor, confidence high] src/knowledge/Knowledge.jl:1434-1436
Claim: `tracking_method(spec)` answers `Symplectic6DMap()` for a `:line` spec although `supported_tracking_methods(ElementSpec{:line})` is `[]`, `runtime_type(ElementSpec{:line}, Symplectic6DMap)` is `nothing`, and `compile_runtime(line, Symplectic6DMap())` throws, so the documented identity `compile_runtime(spec) == compile_runtime(spec, tracking_method(spec))` (:1481) does not hold for the one kind that has no method.
Mechanism: `tracking_method(spec::ElementSpec)` falls back to `default_method(spec)`, whose generic method (`src/knowledge/Methods.jl:61`) returns `Symplectic6DMap()` for every kind without an override; `:line` declares `tracking_methods = DataType[]` and overrides nothing, so the registry-facing query invents a method the kind rejects. `compile_runtime(::ElementSpec{:line}, args...)` (`src/elements/beam_line.jl:728`) wins dispatch for the one-argument call, which is why `compile_runtime(line)` works and only the composed form fails. Every other kind's `default_method` lies in its `tracking_methods` (p1: `kinds whose default_method is not in tracking_methods: [:line]`). The `default_method` docstring ("the preferred tracking method object for an element spec", Methods.jl:56-60) has no "none" answer. Class 9; registry-query consistency under hypothesis 3.
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U25/p3_followup.jl` prints `tracking_method(line example) = Symplectic6DMap()`, `supported_tracking_methods(ElementSpec{:line}) = DataType[]`, `runtime_type(line, Symplectic6DMap) = nothing`, and `compile_runtime(line example, Symplectic6DMap()) -> ArgumentError: a line has no tracking method of its own ...`.

### LEAD U25-8 [Minor, confidence high] src/knowledge/Knowledge.jl:1225-1252
Claim: the validator has no rule relating a Symbol-valued `ParamMeta.default` to its declared `alternatives`, so an enum default outside the enum (`misalign_convention` defaulting to `:elegant` against `(:bmad, :madx)`) passes validation.
Mechanism: the per-parameter loop checks unit vocabulary, required-with-default, required-in-example and help mention; `alternatives` is read nowhere in `validate_element_metadata`. For Symbol parameters the docstring (:213-225) gives `alternatives` the enum meaning ("the enum for a Symbol/flag parameter"), so `default in alternatives` is a well-defined obligation there; for Real parameters the same field means hand-picked perturbation values and the obligation does not apply (the live registry's only defaults outside their alternatives are `aperture.x_limit/y_limit`, `Inf` against shrunken probe values -- legitimate under the second meaning). Injection I2 (p1): `passed=true -> MISSED`; the declared-default check cannot see it either, because `misalign_convention` is absent from the example (U25-1's gate) and is inert on an unmisaligned element even ungated. Class 5.
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U25/p1_knowledge.jl` prints `I2 drift.misalign_convention default :elegant (alts (:bmad, :madx)): passed=true -> MISSED` and, in section B1/B2, the two aperture limits as the only live `default NOT in alternatives` cases; `grep -c "alternatives" src/knowledge/Knowledge.jl` versus `grep -n "alternatives" src/knowledge/Knowledge.jl | awk -F: '$1>1199 && $1<1425'` (no hit inside the validator).

### LEAD U25-9 [Minor, confidence high] src/knowledge/Knowledge.jl:1212-1218
Claim: the free-text channels `ElementMeta.description` and `ParamMeta.meaning` are never checked for emptiness, so a kind whose description and parameter meanings are empty strings validates clean while `element_help` -- the agent-facing surface these fields exist for -- prints nothing for them.
Mechanism: `validate_element_metadata` reads `meta.description` nowhere and `pmeta.meaning` nowhere (:1199-1425); `construction_help` is checked only for mentioning each key (:1249). Injection I4 (p1): drift with `description=""` and `L.meaning=""` -> `passed=true -> MISSED`. Live registry: 0 empty descriptions, keywords, construction helps or meanings across 663 registry `ParamMeta`s (p1 section B1/B2), so this is a missing tripwire, not a live lie. The previous audit's U12-17 closed the analogous gap for non-element `description()`s with a suite tripwire; the element side has none. Class 13.
Repro: `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U25/p1_knowledge.jl` prints `I4 drift description="" and L.meaning="": passed=true -> MISSED` and `empty meaning=0`; `grep -n "meta.description\|\.meaning" src/knowledge/Knowledge.jl | awk -F: '$1>1199 && $1<1425'` returns nothing.

### LEAD U25-10 [Minor, confidence high] src/policies/Policies.jl:989-1000 -- out of hypothesis
Claim: the `_mp_chunk_fold` docstring declares a three-argument signature `(partials, offset_chunk, nchunks_local)` while the one method takes two, `(partials, first_chunk)`, and all three call sites pass two.
Mechanism: the docstring header (:990) and the function line (:1000) disagree; `methods(Octopus._mp_chunk_fold)` has exactly one entry, `(AbstractVector{T}, Integer)`, and the callers (`src/track/strong_beam_track.jl:124,177`, `src/tasks/Tasks.jl:2411`) pass `(partials, first_chunk)`. The 2026-09-06 neighbour audit corrected two other docstring/body disagreements in this seam (:597-599, :1133-1134) and this one survived. Class 14.
Repro: `grep -n "_mp_chunk_fold(partials" src/policies/Policies.jl` shows the two signatures; `julia --project=. --threads=4 result/comprehensive_audit_2026_10_18/probes/U25/p2_policies.jl` section "M" prints the single method signature.

## Clean

What was compared, against what, and what was measured. "Clean" means the check executed and found
agreement; it does not cover anything listed under Unchecked.

Hypothesis 1 (policy schemas vs consumers):
- For all five policy types, `Set(keys(policy_option_schema(T)))` equals the set of
  `configuration_report(T())` entry names and the schema consumers equal the report consumers (p2
  H1-b; CUDA's schema flattens `launch` into `threads`/`blocks` and both sides agree on that).
- Every consumer symbol a policy schema declares (`:cpu_logical_workers`,
  `:multi_process_communicator`, `:cuda_device`, `:cuda_fused_launch`) is emitted by at least one
  `_record_execution!` site in `src/` (grep of literal `_record_execution!(:...)` sites, 46
  distinct symbols; the one non-literal site at `interface.jl:3078` noted). `:cuda_strong_strong_launch`,
  the second consumer of `threads`/`blocks` named in the `blocks` meaning (:1393-1401), is emitted
  at :1338 and :1345 with `resolved_by` -- U12-11 closed as described.
- Constructor rejection: invalid values (`threads=0`, `threads=nthreads+1`, `:all`, `ranks=0`,
  `:any`, launch `threads=0`, `blocks=0`, `:occupancy`, `device=-1` on both CUDA policies) throw
  `ArgumentError` with the documented messages; unknown keywords throw `MethodError` on every policy
  (no `kwargs...` sink); a `Float64` thread count is a `MethodError`, nothing is clamped (p5).
- The multi-process and CUDA default checks in the validator DO compare against constructed
  instances: both control injections failed as they should (p2 H1-a).
- `_run_logical_workers` records the resolved worker count, not the pool size: under
  `ResolvedCPUExecutionPolicy(2)` the receipt is `(workers = 2, pool_threads = 4)` (p2 W).
- Every `configuration_report` entry status across the five policies is in `CONFIGURATION_STATUSES`
  (p5), and the tuple's six members match its docstring bullets (:68-82).
- `_active_cuda_launch` (:1335-1350): the `:auto` rule (coverage capped at 256) and the no-policy
  fallback `(256, 256)` are both recorded in the receipt with `resolved_by`, matching the `blocks`
  meaning text.

Hypothesis 2 (ElementMeta/ParamMeta validator):
- Live registry: 31 kinds; 0 empty descriptions, keywords, construction helps; 663 registry
  `ParamMeta`s with 0 empty meanings; every kind declares all eight placement keys; 30 of 31 declare
  `numeric_type` with `alternatives == (Float64, Float32)` (the exception is `:line`, the composite;
  see Unchecked). All 608 non-required declared defaults compile identically to omission when
  compared without the gate (596 comparable, 0 failures) -- the registry tells the truth today
  even where the validator does not look (p1 D).
- The validator's existing non-circular checks were re-exercised: the suite's K3/K6, U12-6 and U12-8
  injection controls (`test/runtests.jl:17847-17948`) match the code at :1288-1301, :1232-1235 and
  :1387-1416; the friendly-constructor build check and the per-mapping compile check are as the
  comments describe.
- `_help_mentions_parameter` (:422-437): the identifier-boundary logic was read against its U12-5
  motivation; `ref_tilt` does not satisfy `tilt` (underscore is an identifier character).
- `_warn_unknown_spec_keys` (:113-143): `maxlog = 1` with an `_id` keyed by kind and sorted key set,
  as the U12-18 fix describes; `_extra_tracked_keys` has no extenders in `src/` (grep), consistent
  with its docstring "NO KIND EXTENDS IT TODAY".
- `setproperty!`/`set_param!` (:160-202): both bump `_SPEC_EPOCH`; the placement keys are always
  assignable; unknown names on a schema-carrying kind throw with the valid list.
- `ALLOWED_PARAM_UNITS` (:404-409) matches the units the registry declares (`m`, `rad`, and `Hz`),
  and the consumer `_perturb_is_physical` reads `pmeta.unit in ("m", "rad")` as the docstring says
  (`Contracts.jl:3141-3143`; it additionally guards the placement keys by name).

Hypothesis 3 (tracking-method tags and registry derivations):
- For all 31 kinds `Set(keys(meta.runtime_types)) == Set(meta.tracking_methods)` (p1).
- `default_method(T)` is in `tracking_methods` for 30 of 31 kinds; the eight overrides in `src/`
  (`thin_accelerating_cavity`, `lorentz_boost`, `rev_lorentz_boost`, `lumped_radiation`,
  `thin_strong_beam`, `gaussian_strong_beam`, `aperture`, `patch`) are exactly the eight kinds whose
  methods exclude `Symplectic6DMap`; the exception is `:line` (U25-7).
- The Twiss rule "declare `TwissDispersionAnalysis` iff `Symplectic6DMap` in methods and
  `NonSymplectic6DMap` not, plus `:line`" holds for 31 of 31 kinds; no kind declares both tags;
  every example's `tracking_method` is a declared method (p1).
- The symplecticity contract derives its obligation from `Symplectic6DMap in meta.tracking_methods`
  rather than from `contracts` (`Contracts.jl:1955-1965`, read), as `docs/guides/elements.md` step 4
  claims; `_perturb_is_physical` and the Twiss tripwire likewise derive from the registry.
- `description` is defined for all six method types (Methods.jl:64-75); the six structs are empty
  tags with no behaviour of their own.

Policies seam and include order:
- Every seam operation records through `_record_collective!` before communicating and dispatches its
  passthrough on `::Nothing`, so the extension adds methods on the communicator type (:607-700,
  :1041-1062, :1084-1098, :1227-1234); `_mp_test_all` carries the `:funneled` tripwire by hand as
  its docstring says (:1136-1150); the self-mailbox protocol errors (double send, unsent receive,
  size mismatch) are loud (:1162-1225).
- `AbstractPhaseRep`, `CPUThreadsBackend`, `CUDABackend` are defined in `src/Octopus.jl:18-29`
  before `Policies.jl` is included (line 51), so the include-time uses at :434-446, :942 and
  :1367-1417 resolve; `_REDUCTION_CHUNKS` (`interface.jl:679`, = 64) and `_chunk_bounds`
  (`slicing.jl:631`) are used only at call time.
- `_rethrow_worker_failure` (:1302-1316) unwraps `CompositeException`/`TaskFailedException` to the
  first cause and rethrows the original intact when nothing unwraps, as documented.

## Minor notes (below lead threshold)

- Dated counts in docstrings have moved on: Policies.jl:40-42 says "all 44 `ConfigurationOptionMeta`
  declarations ... exactly ONE is true"; `grep -rho "ConfigurationOptionMeta(" src/ | wc -l` now gives
  67, and the "exactly one `perturbs_timing=true`" statement still holds (`src/tasks/Tasks.jl:296`;
  the five `interface.jl:364-378` trues are `DiagnosticsOptionMeta`). Knowledge.jl:396-397 says
  "233 of the 255 `ParamMeta` declarations" lack a unit; by grep it is now 260 declarations, 23 with
  `unit=`. Both are explicitly dated measurements, so they are notes, not leads.
- Methods.jl:13-19 describes `NonSymplectic6DMap` as the tag for "exact coordinate transformations
  whose Jacobian does not satisfy J'SJ = S"; it is also the tag for `:aperture`, which
  `src/elements/aperture.jl:469-471` calls "a projection, not a map", and for `:patch` and
  `:thin_accelerating_cavity`.
- `MultiProcessExecutionPolicy(ranks=3)` constructs; the rule that 3 does not divide 64 refuses it
  only at `_mp_shard_range`, symmetrically on every rank (p2). Late, not silent.
- `CUDALaunchConfig(threads=2048)` is accepted; the device cap is enforced at resolution
  (`Beam.jl:368-370`), so the refusal is loud but not at construction (p5).
- `_check_declared_defaults!` swallows 12 constructor refusals silently today (p1 D); all are
  legitimate (redundant strength spellings and `line.L`), which is why the skip should be visible.
- The `_PLACEMENT_PARAMS.numeric_type` comment (:259-261) says the number type "is a property of
  EVERY kind"; `:line` declares no `numeric_type` (30/31), consistent with a composite whose type is
  its elements', but the comment does not carve it out.
- `@element_spec` (:597-607) still ignores non-assignment items silently (U12 minor note, unchanged).

## Unchecked

- The `_ON_SPAWNED_WORKER` docstring table (Policies.jl:130-137: thread ids under `--threads=4`,
  `auto`, `JULIA_NUM_THREADS`, `4,0`) was not re-measured; it needs four Julia invocations and is a
  record of a measurement, not code.
- A live multi-rank reproduction of U25-3 (`MPI.mpiexec` with four ranks holding
  `(256, 256, 255, 257)`) was not run: the expected outcome is a deadlock or a launcher abort, which
  is a measurement to report rather than a loop to wait on; the arithmetic reproduction stands.
- `ext/OctopusMPIExt.jl` (the `::MPIBackendTag` and communicator methods this file's seam calls)
  was not read; the passthroughs were.
- Whether `LatticeMagnet{Damping6DMap, ...}` (the object U25-5's injection compiled) actually tracks,
  and how the effectiveness contract reports the seven `misalign_convention` parameters it receives
  no candidates for (U25-4) -- loudly as unprobed or silently -- are both in `src/contracts/` and
  `src/elements/`, outside this region.
- English-word collisions in `_help_mentions_parameter` (a help text that says "constructor name"
  satisfies the `name` key; "tilt" in prose satisfies `tilt`) were not measured per kind; the
  word-boundary rule is sound for identifier-shaped keys.
- Nothing in the region is CUDA-reachable; no device-IR check applied.
- `docs/guides/configuration.md` step 4 ("the validator enumerates policy types by hand (an open
  todo row); its tree guard names any concrete policy that has no block") agrees with
  `interface.jl:1900-1906`; the todo row itself was not consulted.
