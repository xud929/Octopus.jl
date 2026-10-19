# U15: turn_modulated.jl + crab_cavity.jl

Tree: `/cfs/ad/dxu/Library/Julia/Octopus` at 24e8683, read-only. Unit brief:
`result/comprehensive_audit_2026_10_18/plan/U15.md`; standing rules: `plan/BRIEF_COMMON.md`.

## Region

- `src/elements/turn_modulated.jl` lines 1-1974 (1974 lines)
- `src/elements/crab_cavity.jl` lines 1-545 (545 lines)

Total 2519 lines, every line read.

## Provenance

READ line by line: both region files in full. Reference material read for comparison:
`src/math/counter_rng.jl` 1-712 in full; `docs/design/turn_modulation.md` sections 3 (lines 121-194),
4.5 (376-391), 5 (391-600) and 7 (654-693); `docs/design/spectral_turn_table.md` section 3, D1-D11
(85-346); `docs/theory/crab_cavity_noise_response.md` 2.1 (108-141), 3.1 (213-251), 5.2-5.3
(487-547). Targeted excerpts outside the region, read to settle seams the hypotheses name:
`src/track/phase6d_track.jl` 120-135, 250-272, 418-450; `src/tasks/Tasks.jl` 450-530 (the
duplicate-stream warning) and the `TurnModulated` method list (1717, 1837, 1953, 2295);
`src/track/Track.jl` 20-32 (`TrackingContext`); `test/runtests.jl` 10470-10530 (allocation pins) and
10740-10815 (the wrapper-walk tripwire's single source); `test/examples/crab_cavity_noise.jl` 900-980
(the fixed point's rule factory); `profiling/crab_cavity_noise_backends.jl` header; `docs/todo.md`
row 32; `Project.toml`; `ext/OctopusForwardDiffExt.jl` (grep for RNG methods: none).

EXECUTED (scratch `result/comprehensive_audit_2026_10_18/probes/U15/`, logs beside the scripts):

- `probe1_alloc_keys.jl` -> `probe1.log`: catalogue derivation; `@allocated` of `update`,
  `realize`, `update_line` on six container shapes, a 40-element line of five distinct runtime types
  and the harness's fixed-point shape; bitwise key identities of the white and pink draws; the pink
  stride bound at 64 and 66 slots; the window check at its boundary; a complex-typed cavity with a
  live rule and with a table.
- `probe2_spectral.jl` -> `probe2.log`: exact rms and periodogram under `:fixed` (three bands),
  Rayleigh rms scatter over 200 tables, resolved `SpectralNoise` against the offline factory slot
  by slot, the hertz path, the tamper refusal, the mixed-kind shared-id warning against the measured
  correlation, a twelve-case refusal sweep, the factory's warn-then-refuse ordering.
- `probe3_pink_receipt.jl` -> `probe3.log`: the shipped `PinkNoise` periodogram over 2^16 turns per
  octave band against the theory note's analytic rho(nu); the per-turn rms of both live rules; the
  provenance slot entries of rules differing only in `sigma` or `octaves`.

Numbers are quoted under Leads and Clean.

## Leads

### LEAD U15-1 [Moderate, confidence med] src/elements/turn_modulated.jl:1965
Claim: The provenance slot entry of a `WhiteNoise` or `PinkNoise` slot records neither `sigma` nor `octaves`, so the `:turn_modulation` receipt and the artifact's per-slot attributes are byte-identical for two runs that differ only in a rule's rms or in a pink rule's octave count.
Mechanism: `_push_rule_slot!` builds the entry generically from the fields `rng_id`, `digest`, `name`, `offsets` (length); a table slot is thereby identified by digest and canonical name, but a live rule's only free parameters, `sigma` (both kinds) and `octaves` (pink), are not read, and `src/tasks/RunArtifact.jl` writes no `sigma`/`octaves` attribute either (grep: none). `(seed, rng_id, slot, kind)` regenerates the normalised draws but not their scale or spectrum, so the receipt cannot assert the configuration the run read (invariant: assert what the run recorded). Neither `docs/design/turn_modulation_record.md` nor `docs/design/run_artifact.md` records the omission as a decision (grep `octaves`: no hit). The series dataset, when `record_turn_modulation` is on, does hold the realised values, so the artifact is complete and the receipt is not.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus result/comprehensive_audit_2026_10_18/probes/U15/probe3_pink_receipt.jl` -> `white sigma 1e-5 vs 2e-5, same id: receipt entries equal = true` and `pink octaves 8 vs 16, same id: receipt entries equal = true`; the entry's fields are `(:slot, :kind, :rng_id, :digest, :name, :length)`.

### LEAD U15-2 [Minor, confidence high] src/elements/crab_cavity.jl:460
Claim: A live rule on a cavity whose numeric type is not an `AbstractFloat` (a complex or dual `T`, which the kind's `T<:Number` bound admits and `_linear_map_eltype` produces from a complex or dual strength) passes construction and `compile_runtime` and dies with a `MethodError` at the first `update`; a `TurnTable` on the same cavity is refused with a remedy that cannot be followed.
Mechanism: `_turn_modulation_wrap` checks only bound tables (`_check_rule_numeric_types`, line 478); `_turn_offset(::WhiteNoise)` (line 1086) and `_turn_offset(::PinkNoise)` call `octopus_normal(..., T)`, whose methods in `src/math/counter_rng.jl` require `T<:AbstractFloat`, and `ext/OctopusForwardDiffExt.jl` adds none, so a `Dual` fails the same way as `ComplexF64`. The table refusal says "convert the table to ComplexF64" although `TurnTable{T<:AbstractFloat}` cannot be built in that type. The failure is loud but late (first turn of `execute!`, after the task compiled) and carries no remedy. Out of hypothesis (class 5: accepted at compile, refused at run).
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus result/comprehensive_audit_2026_10_18/probes/U15/probe1_alloc_keys.jl`, section "complex-typed cavity" -> `compiled: TurnModulated base T = ComplexF64` then `update on complex cavity: MethodError -- no method matching octopus_normal(::UInt64, ::UInt8, ::Int64, ::UInt64, ::Int64, ::Int64, ::Type{ComplexF64})`; and `table on complex cavity: ArgumentError -- ... convert the table to ComplexF64`.

### LEAD U15-3 [Minor, confidence high] src/elements/turn_modulated.jl:1763
Claim: The stream collector drops the rule kind, so the task constructor's shared-`rng_id` warning asserts "slots of the same index draw identical values ... fully correlated noise" for a `WhiteNoise`/`PinkNoise` on one cavity and a `SpectralNoise` on another sharing one explicit id, although by the key layout the two never share a counter-RNG cell.
Mechanism: `_collect_turn_modulation_streams!` pushes `(rng_id, spec)` for every rule with an `rng_id` field regardless of kind; `_warn_duplicate_turn_modulation_streams` (`src/tasks/Tasks.jl:472-487`, seam) words every duplicate as identical draws. A live rule draws particle slot 0, components >= 1025, at the run's turn; a resolved spectral table draws particle k >= 1, components 1 and 3-4, at turn = slot (the layout above `_RULE_COMPONENT_BASE`, lines 110-162), so the pair is independent and the diagnostic is false for it (true for white/white, pink/pink and spectral/spectral of equal length). Harmless in effect, misleading in content (class 14).
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus result/comprehensive_audit_2026_10_18/probes/U15/probe2_spectral.jl`, section "mixed-kind shared id" -> the warning `multiple turn-modulation rules on distinct elements share an rng_id: slots of the same index draw identical values ...` prints, and `corr(white draws, spectral table) over 1024 turns = 0.054` (null scatter 1/sqrt(1024) = 0.031).

### LEAD U15-4 [Minor, confidence high] src/track/phase6d_track.jl:428
Claim: `_track_cuda_elementwise!(rep, w::Union{MisalignedElement,RefTilted,TurnModulated}, ...)` is a wrapper-descending walk that the wrapper-walk tripwire's single source (`test/runtests.jl:10751-10769`, "THE SINGLE SOURCE of the walks a wrapper joins") does not list.
Mechanism: Every other `MisalignedElement`-dispatching method in `src/` has its `TurnModulated` sibling and sits in the list (checked: `_descend_strong_beams!`, `_requires_cuda_elementwise` both forms, `adapt_structure`, `_check_beam_eltype`, `_aperture_rebind`, `_survey_rebind`, `_hidden_strong_beam_count`, `_inner_method`, `_requires_tracking_context`, `_required_beam_eltype`, `_cross_backend_rounding`, `track_particle`, `track_luminous`, the call operators). The elementwise tracker is defined inside `if _HAS_CUDA`, which is why it was not added when fix M added the predicate; today all three wrappers are in its Union, so nothing is wrong now, but a fourth wrapper would pass the tripwire and reach the generic fallback's throw only at the first elementwise CUDA launch on a GPU machine (class 2: a hand list beside the derived one). Seam, out of the region; reported and stopped.
Repro: `grep -n "_track_cuda_elementwise!" /cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl` shows no entry in the `wrapper_walks` vector (only the fallback-message test at ~15466), while `grep -n "_track_cuda_elementwise!(rep, w::Union" /cfs/ad/dxu/Library/Julia/Octopus/src/track/phase6d_track.jl` shows the walk.

### LEAD U15-5 [Minor, confidence high] src/elements/turn_modulated.jl:690
Claim: The `spectral_turn_table` docstring states the Rayleigh moduli are keyed `octopus_normal_pair(seed, RNG_PHILOX, 0, rng_id, k, 2)`; the code keys them on the table's `slot` in the turn field, and the design note's D5 post-landing remark carries the same stale `0`.
Mechanism: Review F1 (2026-10-16) moved the slot into the turn field of both the phase and the pair (`_spectral_synthesis`, lines 554-583, `octopus_normal_pair(seed, RNG_PHILOX, slot, rng_id, k, 2)`); the phase sentence of the same docstring (line 660) and the `_spectral_synthesis` docstring were updated, this sentence and `docs/design/spectral_turn_table.md:190` were not. A reader regenerating a Rayleigh table of a resolved rule (slot >= 1) from the docstring would key the moduli wrongly (class 14).
Repro: `grep -n "RNG_PHILOX, 0, rng_id, k, 2\|^0, rng_id, k, 2" /cfs/ad/dxu/Library/Julia/Octopus/src/elements/turn_modulated.jl /cfs/ad/dxu/Library/Julia/Octopus/docs/design/spectral_turn_table.md` -> `turn_modulated.jl:691` and `spectral_turn_table.md:190`; against `grep -n "octopus_normal_pair(seed, RNG_PHILOX, slot" /cfs/ad/dxu/Library/Julia/Octopus/src/elements/turn_modulated.jl`.

### LEAD U15-6 [Minor, confidence high] src/elements/turn_modulated.jl:760
Claim: `spectral_turn_table` builds the plan, and prints the fewer-than-32-bins warning, before refusing `rng_id = 0` or a malformed `seed`/`rng_id`/`slot`, so a refused call still warns about a table that is never built; the `SpectralNoise` constructor orders the same checks the other way for exactly this reason.
Mechanism: `_spectral_table` calls `_spectral_plan(..., warn)` first and `_spectral_key`/the `rng_key == 0` refusal/`_spectral_slot` after; the constructor's comment (line 822) states the opposite order is deliberate "so that no plan is built (and no few-bins warning printed) for a rule that is refused anyway". Cosmetic (a stray warning), out of hypothesis.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus -e 'using Octopus; try spectral_turn_table(:flat, 1e-5, (0.4, 0.5); turns=16, seed=1, rng_id=0) catch e; println(typeof(e)) end'` -> the warning `only 2 bin(s) lie in the band 0.4..0.5 ...` followed by `ArgumentError`.

## Clean

Hypothesis 3, allocation (probe1, measured after warm-up, Julia with 4 threads): `update` and
`realize` allocate 0 B on `(nothing, WhiteNoise)`, `(nothing, PinkNoise)`, a `TurnTable` strength
slot, the mixed `(WhiteNoise, PinkNoise)` + `(TurnTable, nothing)` container, and homogeneous
containers of 33 and 40 harmonics; `update_line` allocates 0 B on a 40-element line of five distinct
runtime types (`CrabDispersion`, bare white cavity, `RefTilted` pink cavity, `MisalignedElement` white
cavity, table cavity), on both the plain and the `sink = nothing` form, and the output type equals the
input type; the harness's fixed-point container `(WhiteNoise, nothing, WhiteNoise)` on both parameters
allocates 0 B per `update` and per line. The rebuild of that 40-element line costs 5.8 us per turn,
which is the 7 pink cavities' 16 Philox draws each plus 12 white draws (about 124 draws, ~47 ns per
draw), not the 20 ns of the noiseless rebuild the design note's section 7 quotes; no claim conflicts.

Hypothesis 2, keys (probe1): the white draw on slot 2 equals `sigma * octopus_normal(seed,
RNG_PHILOX, turn, rng_id, 0, 1024 + 2)` bitwise; the pink draw equals `sigma * sum_k
octopus_normal(seed, RNG_PHILOX, turn >> k, rng_id, 0, 1024 + 2 + 64 (k + 1)) / sqrt(16)` bitwise;
two cavities sharing an explicit id produce identical slot-1 values and distinct slots within one
cavity; a 64-slot container carrying a `PinkNoise` is accepted and a 66-slot one refused by the
stride message; white slot 64 is component 1088 and pink slot 1 generator 0 is 1089 (disjoint). By
reading: white components occupy 1025..1088 and pink components 1089.., and two pink cells coincide
only if `s - s' = 64 (k' - k)`, impossible below 65 slots; adjacent slots are the two outputs of one
Box-Muller pair, which are independent normals; a resolved spectral table (particle k >= 1,
components 1, 3-4, turn = slot) shares no cell with any live rule, as documented. The cross-class
claim warnings of `claim_rng_id!` were read, not run. The auto-id order dependence is the open
owner item `docs/todo.md` row 32 (dated 2026-10-14, "rng_id = 0 makes turn-modulation provenance
depend on construction order"); nothing beyond it was found: the id is drawn once at rule
construction by `_rule_stream_id`, refused for negative or non-integer input before any claim, and
the registry floor covers the precompile process's claims.

Hypothesis 1, the spectral producer (probe2): under `:fixed` the rms over the period equals `sigma`
to 2e-15 (flat and pink over `(2^-10, 1/2)`, pink over `(1e-3, 1e-2)`), the periodogram divided by
`S(f_k)` is constant across the band to 1.1e-14 relative, off-band bins are below 1e-16 of the
in-band peak, and the Nyquist entry is real; under `:rayleigh` the rms over 200 flat tables of 2^12
turns is 1.0002 sigma with standard deviation 0.0115 against the predicted `1 / (2 sqrt K)` =
0.0111 at K = 2045; a `SpectralNoise` shared by phase slots 1 and 2 and strength slot 2 (slot 4)
resolves to tables bitwise equal to `spectral_turn_table(...; slot)` under the same seed and id, with
equal digest and canonical name and `resolved_seed = 777`; slots 1 and 2 are distinct under one id
(correlation 0.20 on a 51-bin pink band whose `K_eff` is about 13, inside the design's
`4 / sqrt(2 K_eff)` bound); the compiled container holds no `SpectralNoise`; the hertz path equals
the tune path to 2e-20 with identical canonical names; a table whose entries were written after
construction is refused at compile by name; twelve refusal cases (`rng_id = 0`, `ub > 1/2`, no bin,
a preset's label on a custom shape, negative `S`, vanishing `S` with `sigma > 0`, `turns = 1`,
`T = Int`, a bad `amplitudes`, a non-callable `S`, a negative `slot`, a negative rule `rng_id`) all
raise `ArgumentError`. Spectral tables are keyed on `RNG_PHILOX` whatever the global method; this
is stated in the docstring and in D4 and the canonical name regenerates the table without the
method, so it is noted, not led.

Hypothesis 1, the pink rule (probe3): the octave-band periodogram of the shipped `PinkNoise(1.0;
octaves = 16)` over 2^16 turns, divided by the band mean of the theory note's analytic
`rho(nu) = (1/K) sum_k sin^2(pi nu 2^k) / (2^k sin^2(pi nu))`, is 0.992-1.037 on the six bands
holding 512 or more bins, 0.977-1.289 on the 64-256-bin bands and 0.72-1.42 on the 8- and 16-bin
bands (the band scatter is about `1 / sqrt(bins)`); the analytic `rho(0.228)` evaluates to 0.1547,
the note's number. The sample rms over 2^16 turns is 1.047 sigma for pink (inside the documented
7.3 % one-sigma scatter) and 0.996 sigma for white. The implemented construction is the aligned
`turn >> k` form that design 5.2 and theory 5.2 describe and derive; the "McCartney" attribution is
loose (McCartney's variant updates one generator per step), but no document claims the staggered
form, so there is no drift to lead. No rule carries state: every `_turn_offset` returns its rule.

Semantics and consistency (read, plus probe1): the strength slot realises `S (1 + d)` exactly and a
zero nominal `strengthY` stays exactly zero; the phase slot is additive; the slot numbering (phase
`i` -> `i`, strength `i` -> `N + i`) agrees in `_slot_rules`, `_realize_draws`, `_turn_rule_values`
and both `_resolve_turn_rules` call sites; `_slot_nominals` has `2N` entries and the columns walk
checks the lengths; the window check passes `(first_turn, turns) = (0, 8)` and `(3, 5)` on an
8-entry table and refuses `(0, 9)` and `(3, 6)`, and the by-hand path raises `BoundsError` on turn 8;
`_turn_rule_kinds()` is `(:pink, :spectral, :table, :white)` and `_turn_rule_names()` lists the four
types, both derived. The kernel's kick is the theory note's "coded kick" (`dpx = -s sin(theta)/(ik)`,
`dpz = -(s_x x + s_y y) cos(theta)`), a position-only potential, hence symplectic.

Walk coverage (read): every `src/` method dispatching on `MisalignedElement` outside the region has a
`TurnModulated` sibling (listed under U15-4); the five in-region walks share one five-method shape
over `Tuple`, `TurnModulated`, `Union{MisalignedElement,RefTilted}` and `CompositeLine`;
`_foreach_unrolled`, `_update_line_unrolled`, `_slot_draws`, `_slot_values`, `_slot_successors` and
`_slot_concat` index with literals; the closures handed to `_each_modulated`, `_check_turn_window`,
`_each_turn_rule_spec` capture vectors and scalars without rebinding them. Every check in the region
executes (class 1): the slot-table check in the two-argument constructor, the numeric-type check, the
tamper check, the window check, the spectral refusals and the `applicable` check were each seen to
refuse in the probes.

Style only, not leads: the prose "more than 32 harmonics" in `crab_cavity.jl:54` and its
`construction_help` is hand-written where the refusal message derives it from
`_PINK_COMPONENT_STRIDE`; `TurnTable`'s `T<:AbstractFloat` bound admits `BigFloat`, on which
`reinterpret` fails with a non-`ArgumentError`; `update` and `realize` are exported under very
generic names.

## Unchecked

- The recording hook with a live `TurnModulationRecorder` sink: allocation was measured with
  `sink = nothing` only; the suite's pins cover the sink form (read at `test/runtests.jl:10521`).
- CUDA execution of a modulated line: the device drop (`adapt_structure`) and the elementwise route
  were read, no GPU probe was run.
- The RF cavity twin (`src/elements/rf_cavity.jl`) and the Tasks.jl consumers (`execute!`'s window
  call, `_warn_resolved_duplicate_tables`, `_warn_resolved_seed_drift`, `ReportedSharing`): outside
  the region; the seams the hypotheses touch are reported under U15-3 and U15-4.
- The suite's turn-modulation testsets were not run; only their allocation pins and the tripwire's
  single source were read, so class 13 (tests shown to fail on their defect) is not assessed.
- Agreement of the spec-side walk (`_each_turn_rule_spec`, with `LineEntry` and kept-whole lines)
  with the compiled-side walks was read, not exercised.
- A Dual-typed cavity under U15-2 is inferred from the method table (the extension adds no RNG
  methods); only the `ComplexF64` case was executed, ForwardDiff not being in the project
  environment.
