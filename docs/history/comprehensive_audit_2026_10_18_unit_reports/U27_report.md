# U27: Beam.jl + Registry.jl + Examples.jl + Octopus.jl + constants + Elements.jl + StrongStrong.jl

Tree under audit: `/cfs/ad/dxu/Library/Julia/Octopus` at commit 24e8683, read-only. Every
claim below is a LEAD, not a finding. Severity guesses: Critical/Major/Moderate/Minor.

## Region

| File | Lines |
|---|---|
| `src/beam/Beam.jl` | 1-962 |
| `src/registry/Registry.jl` | 1-360 |
| `src/examples/Examples.jl` | 1-144 |
| `src/Octopus.jl` | 1-189 |
| `src/constants/Constants.jl` | 1-32 |
| `src/elements/Elements.jl` | 1-17 |
| `src/tasks/StrongStrong.jl` | 1-15 |

Total 1719 lines, all read line by line.

## Provenance

READ line by line (complete): all seven region files above.

READ as cross-file excerpts, to verify what the region late-binds or claims (not audited as
regions; seams are noted as such):
`src/policies/Policies.jl` 470-500, 725-800 (`_mp_open_communicator`, `_launcher_rank_count`,
`_mp_shard_range`, `_mp_resolve_shard`); `src/track/phase6d_track.jl` 20-50 (`_shard_context`);
`src/tasks/strongstrong/interface.jl` 1855-1885 (`_concrete_octopus_subtypes`);
`src/tasks/strongstrong/slicing.jl` 100-140, 631-635 (`npart` consumers, `_chunk_bounds`);
`src/math/counter_rng.jl` definition list; `src/knowledge/Knowledge.jl` 667-677 (`name`);
`src/elements/beam_line.jl` 167-170, 402-405; `ext/` (grep for subtypes of registry roots);
`test/runtests.jl` 183-195, 255-268, 11248-11264, 15660-15748, 15748-15762, 17588-17632,
21868-21910, 24588-24612, 25770-25845; `docs/registry_snapshot.md` (sections); `docs/public_api.md`
440-490; `Project.toml`; `.gitignore`; `examples/` listing;
`docs/history/comprehensive_audit_2026_08_05_b_unit_reports/LEAD_INDEX.md` rows naming region files.

EXECUTED (scratch `/cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U27/`,
`julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4`, CUDA functional):

- `probe1_registry_constants.jl` -> `probe1.log` (exit 0). Package mode:
  `_HAS_FORWARDDIFF_SCRIPT_MODE = false`; `registry_snapshot_markdown() == docs/registry_snapshot.md`
  is `true` both before and after loading the Symbolics and MPI extensions (ForwardDiff is not
  importable from the project environment, as the suite's own comment says); every
  `summarize_registry()` name (6 tracking methods, 4 solvers, 6 policies, 19 contracts, 2 analyses,
  2 tasks, 31 elements, 5 examples) appears in the snapshot; for all seven walked roots the
  concrete Octopus-owned sets of `_subtypes_recursive` and `_concrete_octopus_subtypes` agree
  (6/4/5/16/2/2/3), with abstract taxonomy nodes published for policies (1) and contracts (3) and no
  non-Octopus types; `runtime_object_types_missing_from_snapshot()` and
  `registry_types_without_description()` are empty; `CLIGHT`, `RE`, `EMASS_EV`, `PMASS_EV` equal
  the CODATA 2022 values bitwise; `TWOPI`, `SQRT2PI`, `SQRTPI`, `SQRT2` equal `Float64` of their
  256-bit BigFloat values; `RE` vs `alpha^2 a_0` (CODATA 2022) relative difference 2.4e-11 (within
  CODATA's 4.7e-10 relative uncertainty on r_e); `COUNTER_RNG_TWO_PI == TWOPI`; every catalogue
  entry resolves to a file; no element has a `runtime_types` key outside its `tracking_methods`;
  the `Beam(N, ::Type{CPUThreadsBackend}, Float64)` method's keywords are
  `beta, alpha, sigma, emit, zeta, eta, coupling, R, C, mode, cutoff, rng, seed, rng_id, initial_offset, execution_policy, kwargs...`.
- `probe2_beam_statistics.jl` -> `probe2.log` (exit 0). Numbers quoted in the leads and the clean
  list below; the headline ones: `beam_statistics` vs 512-bit BigFloat at N = 1e6: |mean error|/rms
  5.2e-19 and 7.2e-19; diagonal covariance relative error 2.8e-14 and 4.9e-14; off-diagonal error
  over rms_i rms_j 6.3e-17 and 3.9e-14; emittance relative error 6.2e-15 (alpha = 0) and 3.4e-12
  (alpha = (10, -10, 3)); masked-with-zero-losses vs unmasked: means and covariance NOT bitwise
  (max |dmean|/rms 4.4e-17, max |dcov|/|cov| 1.2e-14); CPU vs CUDA beams at one seed and rng_id NOT
  bitwise (x 1.55e-15 of rms, others <= 8.3e-18, z bitwise); rng-id counter 3 -> 4 across a refused
  `beta=(1.0, 2.0)` call, 4 -> 4 across a refused unknown keyword, 4 -> 5 across a refused
  `initial_offset=(1.0, 2.0)`; `sigma=1e-3` with `emit=1e-8` gives rms 1.0e-4 silently;
  `write_beam_coordinates(io, rep; npart=10)` on 2 particles writes header 2 and returns 2 silently.

Suite testsets were not re-run through the stage runner; the lost-particle pin was instead
replicated in probe 2 from the fixture's definition (`loss_test_coords`, `loss_test_rep`,
`loss_survivor_rep`, test/runtests.jl 25774-25796).

## Leads

### LEAD U27-1 [Moderate, confidence high] src/beam/Beam.jl:642-648
Claim: `Beam(...)` silently ignores a non-default `sigma` when `emit` is also given, and silently ignores `R` and `coupling` when `C` is given (and `coupling` when `R` is given), with no warning or refusal.
Mechanism: line 642 branches on `emit === nothing` only, so `_normalize_sigma!` never sees a `sigma` passed beside `emit`; line 648 is `C === nothing ? (R === nothing ? coupling : R) : C`, a pure precedence chain. Nothing compares the losing argument against its default. AGENTS.md's invariant "a silently ignored non-default request is a defect" (defect class 5/11) applies; the suite has no test passing `sigma=` and `emit=` together (grep of `test/runtests.jl` for both on one line: none), and `R`/`C`/`mode` are not in the docstring at all (U27-6).
Repro: `julia --project=. -e 'using Octopus; b = Beam(100_000, CPUThreadsBackend; beta=(1.0,1.0,1.0), sigma=(1e-3,1e-3,1e-3), emit=(1e-8,1e-8,1e-8)); println(beam_statistics(b).rms[1])'` prints `9.999999999999992e-5` (emit wins; `sigma` asked for `1e-3`) with no warning; `Beam(1000, CPUThreadsBackend; coupling=(0.1,0,0,0), R=(0.5,0,0,0), C=(0.9,0,0,0))` constructs silently.

### LEAD U27-2 [Moderate, confidence high] src/beam/Beam.jl:753-791
Claim: the "exactly" invariant behind the lost-particle statistics pin (test/runtests.jl:25833-25836, `atol=1e-18/1e-24/1e-30`, which sets `rtol=0`) is not structural: the masked reductions and the plain ones are different reduction orders, and the pin holds only for the suite's sinusoidal n=200 fixture.
Mechanism: `_mean(v)` is `sum(v)/length(v)` (Base's `@simd` loop below 1024 elements, pairwise above), while `_mean(v, flags, nlive)` and the masked `_covariance`/`_fourth_central` are strictly sequential `s += ...` loops; the unmasked `_covariance` is a sequential fold over `zip` and `_fourth_central(v, μ)` is Base's pairwise `sum`. So "masked over the poisoned beam" and "unmasked over the survivors" round differently in general, and even with zero losses switching `allow_lost_particles` on moves the statistics (defect class 8: a pin resting on rounding). Policies.jl:789-792 records the same invariant as the reason a chunk-grid fold was rejected, so the belief that masked == survivors bit for bit is load-bearing elsewhere.
Repro: run `probe2_beam_statistics.jl` section 2/2b: with zero losses at N=200000, `mean bitwise equal = false`, `max|dcov|/|cov| = 1.2e-14`; the suite fixture at n=200 passes every pin (max |dmean| 1.0e-20, max |dcov| 5.2e-26, fourth 0.0); randn values at n=200 FAIL the covariance pin (max |dcov| 1.3e-23 > 1e-24); the suite's own fixture at n=5000 FAILS the fourth-moment pin (3.3e-24 > 1e-30); randn at n=5000 and 200000 fail both. The structural statement that does hold is agreement to a few ulps of the moment.

### LEAD U27-3 [Minor, confidence high] src/beam/Beam.jl:636-656
Claim: a `Beam` construction refused for a malformed `beta`, `alpha`, `sigma`, `emit`, `coupling`, `eta`, `zeta` or `initial_offset` has already drawn 6N normals and consumed a counter-RNG stream id (or claimed the explicit one), and through the policy entry point has already activated the policy.
Mechanism: line 639 (`_standard_gaussian_rep`, which calls `next_rng_id!`/`claim_rng_id!` and allocates) runs before the `_tuple_typed`/`_beam_alpha` validation at 641-656; only the beam-parameter keywords (`_beam_params`, line 638) are validated first. In the policy method (572-579) `activate_policy!` runs before `N > 0` and before every keyword check, although the comment at 573-575 states the intent that refusals land before global state is mutated. Consequence: a caught construction error shifts every later auto-assigned stream (defect class 6), and the failing call costs a full draw.
Repro: `julia --project=. -e 'using Octopus; c0 = Octopus._GLOBAL_RNG_ID_COUNTER[]; try Beam(10, CPUThreadsBackend; beta=(1.0,2.0)) catch; end; println(Octopus._GLOBAL_RNG_ID_COUNTER[] - c0)'` prints `1` (probe 2: 3 -> 4; `initial_offset=(1.0,2.0)`: 4 -> 5; an unknown keyword: 0, because that check precedes the draw).

### LEAD U27-4 [Minor, confidence high] src/beam/Beam.jl:891-892
Claim: `write_beam_coordinates(io, rep; npart)` silently clamps `npart` to `length(rep)` instead of refusing, unlike its twin `CoordinateSnapshotObserver`, which throws when `npart` exceeds the particle count.
Mechanism: `n = min(Int(npart), length(rep))` on line 892 writes a header of `n` and returns `n`; nothing warns. `src/tasks/BeamObservers.jl:891-892` refuses the same request by name. A caller asking for more particles than exist gets a smaller record and no signal (defect class 6, "loud beats silent"; two writers of one format disagree on what the request means, class 3).
Repro: `julia --project=. -e 'using Octopus; rep = Phase6DRep([1.0,2.0],[1.0,2.0],[1.0,2.0],[1.0,2.0],[1.0,2.0],[1.0,2.0]); io = IOBuffer(); println(write_beam_coordinates(io, rep; npart=10))'` prints `2` with no warning (probe 2 section 6: header `UInt32(2)`).

### LEAD U27-5 [Minor, confidence med] src/beam/Beam.jl:139-146 and 171-175
Claim: CPU and CUDA beams built from the same seed and `rng_id` are not bitwise equal, although the CUDA counter path is written to make the raw draws identical.
Mechanism: `_alloc_counter_randn(::Type{CUDABackend}, ...)` builds the draws on the host via the CPU method and copies them (so the raw normals are identical across backends), but `_standard_gaussian_rep` then applies `_standardize!` to the `CuArray`, whose `sum` reduces in device order; μ and σ differ in the last bits and every coordinate moves by O(ulp). Either the host build is pointless or the standardization should finish on the host before the copy. The documented divergence (lines 63-71, U15-3) covers only clip-vs-resample at the cutoff; no document states whether same-seed cross-backend beams are meant to be bitwise, and `docs/current_runtime.md` 175-210 covers kernels only (defect class 4/14).
Repro: `probe2_beam_statistics.jl` section 3 (N = 100000, seed 11, rng_id 4242): `x: bitwise=false max|d|/rms=1.55e-15`, `px 4.4e-18`, `y 6.2e-18`, `py 8.3e-18`, `pz 2.0e-18`, `z: bitwise=true`.

### LEAD U27-6 [Minor, confidence high] src/beam/Beam.jl:538-571
Claim: the `Beam` docstring's signature line omits six keywords the method accepts (`R`, `C`, `mode`, `cutoff`, `seed`, `rng_id`), and `R`, `C`, `mode`, `cutoff` are documented nowhere in it.
Mechanism: the signature on 539-541 lists `beta, alpha, sigma, emit, rng, zeta, eta, coupling, initial_offset`; `Base.kwarg_decl` of the method (probe 1) lists 16 keywords plus `kwargs...`. `rng_id` and `seed` are described in prose, the other four not at all, so the only route to them is reading the source (defect class 14; `docs/public_api.md:442` points readers at `?Beam`).
Repro: `julia --project=. -e 'using Octopus; m = first(methods(Beam, (Int, Type{CPUThreadsBackend}, Type{Float64}))); println(Base.kwarg_decl(m))'` lists `:R, :C, :mode, :cutoff, :seed, :rng_id` among the keywords; `grep -c "cutoff" src/beam/Beam.jl` inside the docstring block 538-571 is 0.

### LEAD U27-7 [Minor, confidence med] src/examples/Examples.jl:70-124
Claim: the catalogue's `objects` fields are a hand list with no coverage tripwire against the scripts; one claim is not borne out by its script (`KnobRef` for `examples/knob_control.jl`).
Mechanism: `example_script_path` and the suite (test/runtests.jl:17616-17623) hold the catalogue to `examples/` in both directions by file name, but nothing checks that a listed object is what the script exercises. `examples/knob_control.jl` never names `KnobRef` (it declares knobs with `@knob` and `@knob_expr`, which build `KnobRef`s internally); the other 23 object names each appear in their script (grep -cw, 1 to 8 mentions). A reader sent by the snapshot's "Objects: `KnobRef`, ..." line finds no `KnobRef` (defect class 2).
Repro: `grep -cw KnobRef examples/knob_control.jl` prints `0`; `grep -n KnobRef src/examples/Examples.jl` shows the claim.

### LEAD U27-8 [Minor, confidence low] src/beam/Beam.jl:167, 932-962, 49-54
Claim: three refusals in a file whose policy is directed errors (U14-9, U15-7) are undirected: `seed=-1` dies in `UInt64(seed)` with `InexactError`, a `record` index past the file's last record raises a bare `EOFError`, and mixed-eltype arrays passed to `Phase6DRep` raise a `MethodError`.
Mechanism: `UInt64(seed)` on line 167 has no sign check; `_framed_count` guards only a declared count against the remaining bytes, so `read(io, UInt32)` at EOF is the error a too-large `record` produces (the message names neither the record nor how many exist); the inner constructor's `where {A}` signature rejects mixed array types by dispatch rather than by message. Style-level unless a caller hits them (defect class 6).
Repro: `probe2_beam_statistics.jl` sections 7-8: `seed=-1: InexactError`, `record beyond EOF: EOFError`, `mixed eltype: MethodError`.

### LEAD U27-9 [Minor, confidence low] src/Octopus.jl:33-34 vs AGENTS.md "Every directory under `src/` has a bullet below; the suite checks" (out of hypothesis)
Claim: the suite's source-map tripwire checks only the top level of `src/`, while AGENTS.md states the rule for every directory under `src/`; the nested `src/tasks/strongstrong/` has no bullet of its own (it is named inside the tasks bullet's prose) and nested directories are unchecked.
Mechanism: test/runtests.jl:264-267 iterates `readdir("src")` with `isdir`, not `walkdir`. Harmless today (the two nested `.ipynb_checkpoints` directories are empty and gitignored, and `strongstrong/` is mentioned), but the sentence promises more than the check delivers (defect class 14).
Repro: `find src -mindepth 2 -type d` lists `src/tasks/strongstrong` (plus two empty gitignored checkpoint dirs); `grep -c '^- \`src/tasks/strongstrong/\`' AGENTS.md` prints `0`.

### LEAD U27-10 [Minor, confidence low] src/registry/Registry.jl:33-62 vs AGENTS.md "summarize_registry() lists every category's concrete members"
Claim: `summarize_registry()` and the snapshot list abstract taxonomy nodes alongside concrete members (one of six policies, three of nineteen contracts), so the AGENTS.md sentence is imprecise.
Mechanism: `_subtypes_recursive` pushes every subtype, abstract or not, and no section filters; the published abstract nodes carry `description` methods (Registry.jl:283-290), so this is deliberate taxonomy publication, but a consumer counting "concrete members" from the summary over-counts (defect class 14; measured, not harmful).
Repro: `probe1_registry_constants.jl`: `AbstractExecutionPolicy: walk=6 concrete-octopus=5 ... abstract-nodes-published=[:AbstractGPUExecutionPolicy]`; `AbstractContract: walk=19 concrete-octopus=16 ... abstract-nodes-published=[:AbstractImplementationContract, :AbstractBackendConsistencyContract, :AbstractPhysicsContract]`.

## Clean

- Hypothesis 2 (registry derivation): every root is walked by `subtypes`, element specs come from `register_element_spec!` (the only registration mechanism, Knowledge.jl:440-476), examples from `example_catalog()`. No extension defines a subtype of any walked root (`grep "<: *Abstract" ext/*.jl` empty), and the snapshot regenerated identically with Symbolics and MPI loaded, so the committed snapshot does not depend on which extensions are present. The two independent walkers (`_subtypes_recursive`, `_concrete_octopus_subtypes`) agree on the concrete Octopus-owned set of all seven roots (probe 1). `summarize_registry` and `registry_snapshot_markdown` consume the same `OctopusRegistry`; every summary name is in the snapshot. The freshness tripwire (test/runtests.jl:190) compares the whole file by string equality; it is green on this tree. `runtime_object_types_missing_from_snapshot` and `registry_types_without_description` are empty and their tests (21868-21910) include a "can fail" probe. `_runtime_mapping_string` would silently drop a `runtime_types` key absent from `tracking_methods`; measured: no element has one.
- Hypothesis 3 (include order): every `include` target exists; every `.jl` under `src/` is included by some `include` except `src/contracts/mpi_pic_consistency_child.jl`, which is a child-process script launched by `Contracts.jl:1515` and existence-tested at test/runtests.jl:24273 (by design). `aperture.jl` loading after `Beam.jl` is explained at Octopus.jl:92-96. `Examples.jl` is included before elements and tasks but references them only inside `example_catalog()` (call-time resolution, deliberate). `__init__`'s target `_forget_rng_id_holders!` exists (counter_rng.jl:350). `_HAS_FORWARDDIFF_SCRIPT_MODE` is `false` in package mode as the comment states (measured), and the suite exercises the branch in a subprocess with a loud skip (15662-15714). Elements.jl includes 17 files + aperture.jl = all 18 element files; StrongStrong.jl includes all 11 files of `src/tasks/strongstrong/`.
- Constants (hypothesis 3): `CLIGHT` is the exact SI value; `RE`, `EMASS_EV`, `PMASS_EV` equal CODATA 2022 bitwise; the four irrationals equal `Float64` of their BigFloat values; `RE` is consistent with `alpha^2 a_0` to 2.4e-11 (CODATA uncertainty 4.7e-10). Units are stated for every dimensional constant. `ME0` is an alias used three times in `src/contracts/Contracts.jl`. `COUNTER_RNG_TWO_PI` (counter_rng.jl:16) duplicates `TWOPI`'s digits but has the same `Float64` value (measured), so it is a style duplicate, not a drift.
- Hypothesis 1 (statistics vs BigFloat): at N = 1e6 the two-pass moments agree with 512-bit BigFloat to 5e-14 relative on the diagonal and 4e-14 off-diagonal; emittance to 6e-15 (alpha = 0) and 3.4e-12 at alpha = (10, -10, 3), the latter the expected (1+alpha^2) ~ 100 cancellation factor in `sqrt(c_ii c_jj - c_ij^2)`. The sequential `zip` fold in `_covariance` is a worse reduction class than the pairwise `_mean`/`_fourth_central`, but its measured error is 50x below the N*eps bound; physics-level agreement with every tolerance stated. The normalization `_normalize_sigma!`/`_normalize_emit!` derives to var(x) = σ², var(px) = σ²(1+α²)/β², cov(x,px) = -αε, and the measured cov(z,pz) = -1.0802e-4 against -αz εz = -1.08e-4 (sample, N = 1e6) confirms the documented sign.
- Hypothesis 1 (Phase6DRep invariants): the inner constructor refuses unequal lengths with a directed message (measured: `got (2, 3, 2, 2, 2, 2)`), and the `where {A}` signature forces one array type for all six, so eltype agreement is structural; `Adapt.@adapt_structure` goes through that constructor. `length`, `keys`, `firstindex`, `lastindex` are consistent with `OneTo`; no `iterate`/`eltype` methods exist anywhere in `src/` (grep), which is a non-feature, not a defect.
- MPI shard construction (`Beam(N, ::MultiProcessExecutionPolicy)`): whole draw then copy of the chunk-aligned range (`_shard_rep` copies, docstring's bit-identity claim holds by construction). The initial maps (`coupling`/`eta`/`zeta`) are applied to the WHOLE beam under the multi-process policy before sharding; by reading, `_mp_resolve_shard(N)` with every rank holding N particles sums to P*N and `_chunk_bounds` gives each rank exactly fld(per_rank*P*N/64) = N, so the verification passes and the deterministic linear maps give the same particles regardless (reasoned, not executed under mpiexec; see Unchecked). `params.npart` stays the whole-beam count on each shard, and the solvers read global macro counts through `_mp_current_shard` (slicing.jl:124-133), so the kick strengths are not divided by the rank count.
- Policy resolution and activation: resolution is pure (records the request, opens no communicator); the launcher-without-policy warning fires on both the CPU and CUDA activation branches; `_open_multi_process_context` matches an explicit rank count exactly and records a receipt; a CUDA policy's `threads` is checked against the device limit. Consistent with `Policies.jl` 470-500 by reading.
- Compact coordinate format: the torn-record guard checks the declared count against the remaining bytes and is exercised by test/runtests.jl:15716-15747 (write twice, truncate, assert the record-naming message, earlier record still readable).
- Catalogue vs `examples/`: both directions are `@test`s (17622-17623) with population floors (17627-17628), inside the full-lane example-execution gate; the five catalogued scripts are exactly the five files in `examples/`, and the harness paths named in the summaries exist.
- `.ipynb_checkpoints` directories under `src/elements/` and `src/knobs/` are empty and covered by `.gitignore` (`**/.ipynb_checkpoints/`): a local artefact, not a repository defect.
- Prior-audit leads touching this region (U12-16, U12-19, U12-20, U14-2, U14-5, U14-9) remain fixed on this tree: the catalogue is populated and pinned, the structural runtime-objects check exists and is empty, the script-mode branch is tested, the sampling-float refusal is reached from both entry points (`_require_sampling_float` at 576, 601, 636), and the empty-rep statistics error is directed (824-829).

## Unchecked

- `Beam(N, MultiProcessExecutionPolicy(...); coupling=...)` under a real multi-rank communicator was reasoned from `_mp_resolve_shard`/`_chunk_bounds`, not executed with `mpiexec -n 2`; a measurement would need the child-launch recipe from the MPI contract.
- `_resolve_execution_policy`'s CUDA device-mismatch and `_cuda_storage_device`'s multi-device refusal: one GPU on this machine, so those branches were read only.
- `_alloc_randn(::Type{CUDABackend}, ...)` with an explicit CUDA RNG (the deprecated `rng=` path on the device) was not executed; only the counter path was.
- The suite testsets named above were not re-run through the stage runner; the lost-particle pin's behaviour was reproduced from the fixture definition in probe 2 instead.
- Whether `src/elements/beam_line.jl` has been edited since the 2026-08-05 note at Octopus.jl:142-145 ("fold them onto the definitions at the next beam_line.jl edit") could not be checked: git is off limits in the tree. The definitions at beam_line.jl:170 and 405 still carry no docstring of their own, so the Octopus.jl attachment is the only one (no duplicate).
- The previous audit's full U12/U14 reports were not read; only the LEAD_INDEX rows naming region files were consulted.
