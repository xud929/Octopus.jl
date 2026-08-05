# U5 report — `src/tasks/strongstrong/interface.jl` (2,509 lines) @ 7de4d81

Reading unit U5 of the comprehensive audit protocol.
Region: `/cfs/ad/dxu/Library/Julia/Octopus/src/tasks/strongstrong/interface.jl`, every line.
Hypothesis: the declared-schema-to-runtime-consumer seam — (a) declared but not
consumed, (b) consumed but not declared, (c) unknown-keyword acceptance,
(d) silent option degradation, (e) defaults that disagree.

## Provenance

**Read (whole-file, line by line):** all 2,509 lines of `interface.jl` at 7de4d81,
plus an independent read of `git diff 6a3f39ab HEAD -- src/tasks/strongstrong/interface.jl`
(+223/-24). Context read first, as briefed: `AGENTS.md` "Hard-Won Rules" and the
"Updating Policies" configuration paragraph; `docs/comprehensive_audit.md`
"Measured Lessons"; the prior `U4_report.md`.

**Read (cross-file, for consumer tracing only):** `src/contracts/Contracts.jl`
(§ `PublicConfigurationEffectivenessContract` 130–560, `SolverOptionEffectivenessContract`
2140–2500), `src/policies/Policies.jl:83-87`, `src/tasks/BeamObservers.jl`
(`prepare_observers!` 197, `_moment_append_continue!` 1255–1290, `should_run` 76–82),
`src/tasks/strongstrong/{slicing,gaussian,pic_cpu,pic_cuda,gaussian_pic,spectral}.jl`
(targeted greps for each declared option), `test/runtests.jl` 3506–3560 and 3955–4010,
`docs/public_api.md`, `docs/current_runtime.md`.

**Executed (this box: RTX 4500 Ada, CUDA 13.0, 8 default threads).** All probe
scripts live in
`/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/`
and touch nothing in the repository:

| script | what it measures |
|---|---|
| `u5_p1_static.jl` | unknown-keyword acceptance (12 constructors), task schema vs constructor vs report, `grid_extent_sigma` report status |
| `u5_p2_behavior.jl` | `grid_extent_sigma` bitwise inertness, `:strong_strong_output` receipt contents, schedule receipt count, `_collision_solver` on a schema-less solver |
| `u5_p3_ordering.jl` | luminosity file destroyed by an `execute!` aborted in `prepare_observers!` |
| `u5_p4_schedule.jl` | double schedule evaluation with a counting predicate; `_collision_solver` microbenchmark |
| `u5_p5_contracts.jl` | `validate(PublicConfigurationEffectivenessContract())`, `validate(SolverOptionEffectivenessContract())` on GPU |
| `u5_p6_price.jl`, `u5_p7_price2.jl` | end-to-end turn-time price; `maxlog` count under the default logger |
| `u5_p8_tripwires.jl` | observer/launch-config/schedule default-check coverage; docstring keyword coverage |
| `u5_p9_receipt.jl` | always-on cost of `_record_solver_configuration!` |
| `u5_p10_threads.jl` | bitwise thread invariance above the parallel thresholds; deposit-buffer memory |
| `u5_p11_final.jl` | dependency-vs-gate table; CPU-only option sweep; slicing method aliases; export surface |
| `u5_p12_partial.jl` | partial silent truncation of the append-mode luminosity file |

---

## Leads

### LEAD U5-1 [Medium, confidence high] src/tasks/strongstrong/interface.jl:2015-2025
Claim: the U4-4 ordering fix reversed the truncation window instead of closing it — an
`execute!` aborted inside `prepare_observers!` now destroys the luminosity file having
tracked nothing.
Mechanism: at 6a3f39a `_prepare_strong_strong_luminosity_file!` ran *after*
`prepare_observers!`, so a `.lum` refusal left a truncated moment table (U4-4). HEAD moved
the call to line 2019-2020, *before* `prepare_observers!` and outside the `try`. Both
preparers commit destructively before either has validated, so the failure is symmetric,
not fixed: `_moment_append_continue!` (BeamObservers.jl:1265-1271) refuses a mismatched
moment selection *after* the `.lum` has already been rewritten. In default replace mode
the `.lum` is rewritten header-only, i.e. the whole history is gone; in append mode every
row at or after `first_turn` is gone. No ordering closes this — it needs a validate-all-
then-commit-all split. The suite pins only the one direction (runtests.jl:3983-3987,
"refused BEFORE any companion observer is truncated"); the reverse is uncovered.
Repro: `julia --startup-file=no --project=. scratchpad/audit/u5_p3_ordering.jl` →
replace mode: 3 rows before, `ArgumentError`, **0 rows after**; append mode with
`start_turn=2`: 5 rows before, `ArgumentError`, **2 rows after**.

### LEAD U5-2 [Medium, confidence high] src/tasks/strongstrong/interface.jl:2217-2218
Claim: the luminosity schedule is evaluated twice per collision per turn — once by the
file-writing gate and once by the solver — so the gate's answer and the solver's answer
are independent, and a stateful `PredicateSchedule` makes every written row a `NaN` that
the docstring reserves for "evaluated and numerically failed".
Mechanism: line 2217-2218 calls `_strong_strong_luminosity_evaluated(solver, ctx)` →
`_pic_compute_luminosity` → `should_run(schedule, ctx)`; the collide path then calls
`_pic_compute_luminosity(solver, ctx)` again (pic_cpu.jl:47, pic_cuda.jl:67/197,
gaussian_pic.jl:785, spectral.jl). `should_run(::PredicateSchedule, ctx)` is
`Bool(schedule.predicate(ctx))` (BeamObservers.jl:82) — an arbitrary user function, and
`PredicateSchedule` is public and is itself exercised by `validate_configuration_metadata`
(interface.jl:1754). Nothing shares the first answer with the second. Two independent
consequences, both measured: `:pic_luminosity_schedule` receipts are doubled (8 for 4
turns, one collision), and with a counting predicate the gate says "evaluated" while the
solver returns `NaN`, so the file records a `NaN` on a row it labelled evaluated — the
exact confusion the docstring at interface.jl:1130-1137 says must not happen.
Repro: `julia --startup-file=no --project=. scratchpad/audit/u5_p4_schedule.jl` → for
`turns=4`, 1 collision: predicate invocations **8** (should be 4); luminosity file rows
`0 NaN / 1 NaN / 2 NaN / 3 NaN`.

### LEAD U5-3 [Low-Medium, confidence high] src/tasks/strongstrong/interface.jl:2009-2010 (declaration at 1596-1600)
Claim: `luminosity_append` declares `consumer=:strong_strong_output`, but the only
`:strong_strong_output` receipt carries `luminosity_path` alone, so the declared consumer
boundary never observes the value.
Mechanism: the new `strong_strong_task_option_schema()` (added by the U3-5 fix) names
`:strong_strong_output` as the consumer for both task options. `_execute_strong_strong_task!`
emits `_record_execution!(:strong_strong_output, backend, (luminosity_path=...,))` — one
field. `validate_configuration_metadata` only checks that a consumer is *named*, which is
precisely the gap `SolverOptionEffectivenessContract`'s own docstring calls out; and the
task options are outside every effectiveness contract's schema sweep, so nothing would
catch it. `Contracts.jl`'s `_solver_contract_receipt_carries` would return `false` for
this pair. AGENTS.md: "an effectiveness test that observes the value at the consumer
boundary".
Repro: `julia --startup-file=no --project=. scratchpad/audit/u5_p2_behavior.jl` §P3 →
`:strong_strong_output receipts: 1`, `values = (luminosity_path = "...",)`,
`has luminosity_append: false`.

### LEAD U5-4 [Low-Medium, confidence high] src/tasks/strongstrong/interface.jl:1726-1733
Claim: the task block of `validate_configuration_metadata` compares the schema default to
a hand-written literal in the same function rather than to a constructed task, so its
docstring claim ("metadata defaults match constructor defaults") is unbacked for
`StrongStrongTask`; and there is no key-completeness tripwire for the task schema at all.
Mechanism: line 1727 is `task_defaults = (luminosity_path=nothing, luminosity_append=false)`
— a second copy of the defaults, not a reading of the constructor. Change
`luminosity_append::Bool=false` at line 1929 to `true` and the check still passes. Every
sibling block builds a real object (`solver_configuration(PICPoissonSolver())`,
`LongitudinalSlicing()`, `StrongStrongDiagnostics()`); `StrongStrongTask((ip,), (ip,))`
constructs fine and exposes both fields, so a real probe was available. Separately, the
schema-vs-declaration completeness check that exists for every other surface
(`Set(keys(schema)) == Set(fieldnames(T))`) has no task analogue: 6 of the 8 public
`StrongStrongTask` keywords have no schema entry and nothing notices, which is the same
structural hole U3-5 was filed against. This is Measured Lesson 4 (hand-copied knowledge
drifts; derive plus a tripwire).
Repro: `julia --startup-file=no --project=. scratchpad/audit/u5_p1_static.jl` →
`hand-copied literal present: true`; `StrongStrongTask public keywords:
[:policy, :seed, :default_poisson_solver, :poisson_solver, :luminosity_path,
:luminosity_append, :diagnostics, :record_turn_times]`; `keywords with NO schema entry:
[:policy, :seed, :default_poisson_solver, :poisson_solver, :diagnostics, :record_turn_times]`.

### LEAD U5-5 [Low, confidence high] src/tasks/strongstrong/interface.jl:1484-1494 (declaration at 1413-1417)
Claim: `grid_extent_sigma` declares `dependencies=(:grid_extent,)` but `_pic_option_active`
does not gate it, so `configuration_report` calls it `:resolved` / "validated solver
configuration" under the default `grid_extent=:extrema`, where it is provably inert.
Mechanism: `_pic_option_active` gates `slice_pair_green_min_ratio`/`_growth` on
`green_cache` and the four `cuda_*` on their chain, but returns `true` for
`grid_extent_sigma`. Its only consumer is `pic_cpu.jl:546` (`kext = T(solver.grid_extent_sigma)`)
inside `_pic_axis_extent`'s `:sigma` branch. So the report's `:inactive_dependency`
machinery — which exists precisely to distinguish a value that acts from one that does
not — misclassifies the one PIC option whose declared dependency it does not implement.
Repro: `julia --startup-file=no --project=. scratchpad/audit/u5_p2_behavior.jl` §P2 →
`:extrema, sigma 6.0 vs 2.0 -> coordinates bit-identical: true, luminosity rows identical:
true`; `:sigma, 6.0 vs 2.0 -> bit-identical: false`; `configuration_report status for
grid_extent_sigma with :extrema = resolved`.

### LEAD U5-6 [Low, confidence high] src/tasks/strongstrong/interface.jl:2467-2482
Claim: the identity→configuration change in `_collision_solver` silently accepts and
discards a differently-configured solver whenever the solver type has no registered
`solver_option_schema`.
Mechanism: `solver_option_schema(::Type{<:AbstractPoissonSolver})` falls back to
`NamedTuple()` (line 409), and `_solver_configured_values` iterates its keys, so
`solver_configuration` is `NamedTuple()` for any unregistered subtype. Line 2477-2478 then
finds `typeof(s1) === typeof(s2) && () == ()` → true, accepts, and line 2483 returns `s1`:
line 2's solver, with a different configuration, is discarded with no warning. The old
`s1 !== s2` rule threw. This is a class-(d) silent degradation newly introduced in the
audit window. It affects user-defined solvers only (all four in-repo solvers have schemas),
which is why severity is Low — but the extension point is public and documented
(`AbstractPoissonSolver`'s docstring is the "how to write a solver" surface).
Repro: `julia --startup-file=no --project=. scratchpad/audit/u5_p2_behavior.jl` §P6 →
`solver_option_schema(ProbeSolver) = NamedTuple()`; `_collision_solver(differently
configured s1, s2): ACCEPTED, chose knob=1.0 (s2's knob=999.0 discarded)`.

### LEAD U5-7 [Low, confidence high] src/tasks/strongstrong/interface.jl:2275-2281 (docstring claim at 2273) — OUT OF HYPOTHESIS (performance / false documented claim)
Claim: `_record_solver_configuration!`'s docstring says "Costs nothing unless an
`ExecutionAudit` is active", but it builds the whole resolved configuration on every
collision on every turn regardless.
Mechanism: `_record_execution!` is a plain function (Policies.jl:83-87) that checks
`_ACTIVE_EXECUTION_AUDIT[]` *inside* its body; Julia evaluates the
`(solver=..., configuration=solver_configuration(solver))` NamedTuple argument eagerly at
the call site. `solver_configuration` on a PIC solver builds a 26-key NamedTuple through
generic `getproperty` plus a `merge`. The sibling receipt in the same function
(`:strong_strong_collision`, line 2287) allocates 0 bytes, so the contrast is internal to
the function.
Repro: `julia --startup-file=no --project=. scratchpad/audit/u5_p9_receipt.jl` with
`_ACTIVE_EXECUTION_AUDIT[] === nothing` → PIC **18,512 bytes / 23.5 µs per call**,
GaussianPIC 18,944 B / 17.6 µs, Spectral 7,232 B / 5.1 µs, Gaussian 6,176 B / 4.2 µs;
`:strong_strong_collision receipt -> 0 bytes`.

### LEAD U5-8 [Low, confidence high] src/tasks/strongstrong/interface.jl:2216 + 2467-2482 — OUT OF HYPOTHESIS (performance)
Claim: `_collision_solver`'s new configuration comparison runs once per collision per
*turn*, although solvers are immutable and `_preflight_solver_configurations!` already
walks every collision once per `execute!`; it is a measurable turn-time regression at
small problem sizes.
Mechanism: line 2216 calls `_collision_solver` inside the per-turn, per-block loop. When
the two lines carry distinct solver objects — the case the change exists to support — the
`!==` fast path fails and two full `solver_configuration` NamedTuples are built and
compared, every turn. The answer cannot change between turns.
Repro: `julia --startup-file=no --project=. scratchpad/audit/u5_p4_schedule.jl` §P7 →
distinct-but-equal **58,704 bytes / 78.3 µs per call** vs shared-object 400 B / 0.36 µs.
End-to-end (`u5_p7_price2.jl`, median of 40 turns, best of 3, 300 particles/beam, 3 slices,
1 IP, 1 worker): grid (16,16) 1.796 → 1.994 ms/turn (**1.11x**), grid (32,32)
5.123 → 5.332 ms/turn (**1.04x**) — a size-independent ~200 µs/turn. Negligible at the
production point (~0.3 s/turn); the earlier grid-24 run in `u5_p6_price.jl` was noise and
is superseded by `u5_p7_price2.jl`.

### LEAD U5-9 [Low, confidence high] src/tasks/strongstrong/interface.jl:2235-2245 — OUT OF HYPOTHESIS (observability)
Claim: the mixed-schedule dropped-row warning carries `maxlog = 4`, so a long run loses
rows silently after the fourth turn.
Mechanism: the `elseif any(luminosity_evaluated)` branch was added so the whole-row drop
is "loud rather than silent", but `maxlog = 4` caps the announcement while the drop
continues for the rest of the run, and the file carries no marker of the missing turns.
Measured Lesson 8 is "data and coverage never disappear without a signal".
Repro: `julia --startup-file=no --project=. scratchpad/audit/u5_p7_price2.jl` §P8c, two
IPs with `luminosity_schedule=AtTurns([0])` and `nothing`, 30 turns → rows written 1,
**rows dropped 29**, and `2>&1 | grep -c "luminosity row dropped"` → **4**.

### LEAD U5-10 [Low, confidence high] src/tasks/strongstrong/interface.jl:2160-2166
Claim: the append-mode "replacing the entire existing luminosity history" warning fires
only when *every* row is dropped, so a fresh task with a wrong but nonzero `start_turn`
destroys the tail of the file silently.
Mechanism: the guard is `isempty(kept) && !isempty(rows)`. Partial truncation
(`0 < length(kept) < length(rows)`) is the documented rewind, but the docstring's own
framing of the loud case ("at or before every recorded row") means the U4-1 footgun
survives for every `start_turn` above the file's first turn — precisely the mis-typed-
resume-point mistake the warning was added for.
Repro: `julia --startup-file=no --project=. scratchpad/audit/u5_p12_partial.jl` → file
holds turns 0..9; a fresh task with `start_turn=2, turns=1` leaves `[0, 1, 2]`,
**7 rows destroyed, no warning**.

### LEAD U5-11 [Low, confidence high] src/tasks/strongstrong/interface.jl:1592 (export list at :1-10)
Claim: `strong_strong_task_option_schema` is the only public configuration schema in the
repository that is neither exported nor documented, so the metadata the U3-5 fix added is
undiscoverable through the API that every other configuration surface uses.
Mechanism: `slicing_option_schema`, `cuda_pic_launch_option_schema`,
`diagnostics_option_schema`, `solver_option_schema`, `solver_configuration`,
`observer_option_schema`, `policy_option_schema` and `schedule_option_schema` are all
exported; the task schema is referenced only inside `validate_configuration_metadata`
(line 1728) and appears nowhere in `docs/public_api.md`. AGENTS.md's "Self-Describing
Source" makes reflection the discovery mechanism, so an unexported schema is a declaration
the user cannot reach.
Repro: `julia --startup-file=no --project=. scratchpad/audit/u5_p11_final.jl` §F4 →
`strong_strong_task_option_schema exported: false`, all eight siblings `true`.

### LEAD U5-12 [Low, confidence high] src/tasks/strongstrong/interface.jl:700-702 vs 647-677 — class (b)
Claim: `LongitudinalSlicing` accepts three slicing methods that no docstring or schema
entry mentions.
Mechanism: the constructor's whitelist (line 700-701) admits `:equal_spaced`, `:gaussian`
and `:Gaussian`; `longitudinal_slices` consumes them as aliases (slicing.jl:66 and 68).
The docstring's "Supported methods" list (lines 653-675) names five, and the schema's
`meaning` is "Slice-boundary construction method." So three accepted values are behavior
keyed off something no declaration mentions — the mirror defect. (They are aliases, not
distinct algorithms, so nothing is *wrong*; the declaration is incomplete.)
Repro: `julia --startup-file=no --project=. scratchpad/audit/u5_p11_final.jl` §F3 →
accepted `[:equal_area, :equal_count, :equal_width, :equal_spaced, :normal_quantile,
:gaussian, :Gaussian, :specified]`; `NOT named in the docstring: [:equal_spaced, :gaussian,
:Gaussian]`.

### LEAD U5-13 [Low, confidence high] src/tasks/strongstrong/interface.jl:1545, 2064 — OUT OF HYPOTHESIS (traceability)
Claim: two source comments point the reader at `pic_cuda.jl:5041` for the Gaussian
`batch_mode` consumer; that line is now unrelated code.
Mechanism: both comments hard-code a line number. The actual consumer is
`pic_cuda.jl:5112` (`collide!(solver::GaussianPoissonSolver, ..., ::Type{CUDABackend})`,
`if solver.batch_mode == :wavefront`); `pic_cuda.jl:5041` is inside
`_cuda_pic_interpolate_kick_quadratic`'s call site. Measured Lesson 4/6: a hand-copied
pointer drifts; name the function, not the line.
Repro: `grep -n "pic_cuda.jl:5041" src/tasks/strongstrong/interface.jl` → 2 hits;
`sed -n '5112p' src/tasks/strongstrong/pic_cuda.jl` → the `batch_mode` branch;
`sed -n '5041p'` → `Kx, Ky, Kz = _cuda_pic_interpolate_kick_quadratic(`.

### LEAD U5-14 [Low, confidence med] src/tasks/strongstrong/interface.jl:1649-1654, 1743-1757, 1780-1792
Claim: `validate_configuration_metadata`'s default-vs-constructor check is applied
unevenly across the surfaces it covers, so three of them can drift undetected.
Mechanism: `CUDAPICLaunchConfig` gets a key-set check and a consumer check but **no**
default check (unlike LongitudinalSlicing, the four solvers, the diagnostics and the task);
observers get consumer and schema↔report checks but no default check; among schedules only
`EveryNSteps` gets one (`AlwaysSchedule` gets none, `AtTurns` gets none). Caveat that keeps
confidence at med rather than high: a naive observer default loop trips on legitimate
sentinels — `path` is positional, `MomentObserver.moments` defaults to `nothing` in the
schema and to the 27-moment set in the constructor, and `BPMObserver.rng_id` declares 0
while the constructor auto-assigns a unique id (documented in the schema meaning). So the
repair needs a declared-sentinel convention, not just another loop.
Repro: `julia --startup-file=no --project=. scratchpad/audit/u5_p8_tripwires.jl` §T1/T2/T3
→ the printed CUDAPICLaunchConfig block contains only the key check and the consumer loop;
`AlwaysSchedule() appears in a DEFAULT check: false`; §T1 lists the sentinel-driven
observer mismatches.

### LEAD U5-15 [Low, confidence high] src/tasks/strongstrong/interface.jl:945-1179
Claim: `backend_configurations` is a public `PICPoissonSolver` constructor keyword with a
schema entry, a declared consumer and a validated type check, and it appears nowhere in
the solver's docstring.
Mechanism: the docstring's signature block (lines 946-965) omits `field_derivative`,
`interaction_grid` and `backend_configurations`; the first two are covered in prose (1017,
1054), `backend_configurations` is not mentioned once in lines 945-1179. It is the only
way to attach a `CUDAPICLaunchConfig`, and `CUDAPICLaunchConfig`'s own docstring never says
how to attach it either. Its only public appearance is `docs/current_runtime.md:153`.
Repro: `sed -n '945,1179p' src/tasks/strongstrong/interface.jl | grep -c backend_configurations`
→ **0**; `grep -c field_derivative` → 1; `grep -c interaction_grid` → 2.

---

## Option → consumer table

Every public option, keyword and schema entry declared in `interface.jl`. "Consumer" is
the code that reads it *at the point where it changes behavior*, not where it is stored or
reported. No row is NO CONSUMER FOUND.

### `CUDAPICLaunchConfig` — schema `_CUDA_PIC_LAUNCH_OPTION_SCHEMA` (interface.jl:137)

| option | declared consumer | actual consumer (file:line) |
|---|---|---|
| `gather_scatter_threads` | `:cuda_pic_launch` | interface.jl:198 → :287-295 → pic_cuda.jl:690 |
| `deposition_threads` | `:cuda_pic_launch` | interface.jl:199 → :287-295 → gaussian_pic_cuda.jl:1080 |
| `kick_threads` | `:cuda_pic_launch` | interface.jl:200 → :287-295 → gaussian_pic_cuda.jl:750 |
| `field_threads` | `:cuda_pic_launch` | interface.jl:200 → :287-295 → gaussian_pic_cuda.jl:1091 |
| `spectral_threads` | `:cuda_pic_launch` | interface.jl:201 → :287-295 → pic_cuda.jl:2385 |
| `green_threads` | `:cuda_pic_launch` | interface.jl:201 → :287-295 → pic_cuda.jl:2736 |
| `luminosity_threads` | `:cuda_pic_launch` | interface.jl:202 → :287-295 → pic_cuda.jl:2454 (pow2 guard :204) |

Inert on a bare `collide!` **by design and loudly** — `_warn_inactive_pic_launch_config`
(interface.jl:273-285) warns and records `:inactive_path`; `_with_solver_execution_configuration`
records `:inactive_backend` (interface.jl:240-243). Not a class-(d) case.

### `StrongStrongDiagnostics` — schema at interface.jl:343

| option | consumer (file:line) |
|---|---|
| `record_turn_times` | interface.jl:2202, 2249-2251 |
| `memory_log_every` | interface.jl:2336 → 2339-2352 |
| `pic_timing` | pic_cuda.jl:456 |
| `pic_timing_detail` | pic_cuda.jl:459 (and the `:node` guard at 232-234) |
| `cache_stats` | pic_cpu.jl:1221, pic_cuda.jl:626 |
| `nvtx` | interface.jl:2319 → 2321-2332 |

Non-default values inactive on the selected backend are warned at interface.jl:2078-2086.

### `LongitudinalSlicing` — schema at interface.jl:715

| option | consumer (file:line) |
|---|---|
| `nslices` | slicing.jl:52, 108; pic_cuda.jl:5290ff |
| `method` | slicing.jl:54, 62-73 (dispatch) |
| `resolution` | slicing.jl:105, 109; pic_cuda.jl:5290, 5294 — `:equal_area` only, and the report's `:inactive_dependency` (interface.jl:743-746) is therefore correct |
| `center_position` | slicing.jl:488-491 |
| `positions` | slicing.jl:346; pic_cuda.jl:5359 — `:specified` only, correctly reported inactive |

### `GaussianPoissonSolver` — schema at interface.jl:888

| option | consumer (file:line) |
|---|---|
| `kbb1` / `kbb2` | slicing.jl:78 / :86 (`_strong_strong_kbb1/2`) → gaussian.jl |
| `luminosity_scale` | slicing.jl:94 |
| `slicing` | resolved into `slicing1`/`slicing2` at interface.jl:846-847; consumed through them |
| `slicing1` / `slicing2` | gaussian.jl:8 / :9 |
| `min_sigma` | gaussian.jl:28, 31, 47 |
| `gaussian_when_luminosity` | gaussian.jl:43; pic_cuda.jl:1067 |
| `ignore_centroid1` / `ignore_centroid2` | gaussian.jl:28, 31; pic_cuda.jl:1211, 5144 |
| `longitudinal_kick` | type parameter `Longitudinal` (interface.jl:856) → `Val(LONGITUDINAL)` gaussian.jl:47, 53 |
| `virtual_drift` | gaussian.jl:47, 53 |
| `include_sigma_xy` | type parameter `Coupled` (interface.jl:856) → `Val(COUPLED)` gaussian.jl:29, 32 → slicing.jl:611-698 |
| `batch_mode` | pic_cuda.jl:5112 (CUDA only; CPU inactivity warned at interface.jl:2062-2074) |

### `PICPoissonSolver` — schema at interface.jl:1361

| option | consumer (file:line) |
|---|---|
| `kbb1` / `kbb2` | pic_cpu.jl:450 / :452 |
| `luminosity_scale` | slicing.jl:94 |
| `grid` | pic_cpu.jl:17, 175 |
| `deposit_method` | pic_cpu.jl:202, 1297 |
| `green_type` | pic_cpu.jl:208; pic_cuda.jl:594 |
| `green_cache` | pic_cpu.jl:211 |
| `field_derivative` | pic_cpu.jl:217, 1863 |
| `slice_interpolation` | pic_cpu.jl:220 (guard 252) |
| `interaction_grid` | pic_cpu.jl:223, 234 |
| `grid_extent` | pic_cpu.jl:234, 524 |
| `grid_extent_sigma` | pic_cpu.jl:546 — **`:sigma` branch only**; see LEAD U5-5 |
| `min_transverse_extent` | pic_cpu.jl:1041-1042 |
| `grid_quantize` | pic_cpu.jl:1072 |
| `slice_pair_green_min_ratio` | pic_cuda.jl:603, 2186 |
| `slice_pair_green_growth` | pic_cpu.jl:1121 |
| `longitudinal_kick` | pic_cpu.jl:568, 664 |
| `batch_mode` | pic_cpu.jl:214, 360; pic_cuda.jl:56, 596 |
| `cuda_async` | pic_cuda.jl:461; pic_cpu.jl:360 |
| `cuda_batch_fft` | pic_cuda.jl:463; pic_cpu.jl:361 |
| `cuda_wavefront_fft` | pic_cpu.jl:380, 390 |
| `cuda_indexed_wavefront` | pic_cuda.jl:481; pic_cpu.jl:380 |
| `luminosity_grid` | interface.jl:1343 → pic_cpu.jl:1952/1961/1970, pic_cuda.jl:565/2414/3531 |
| `luminosity_deposit_method` | interface.jl:1346 → pic_cpu.jl:205/1989, pic_cuda.jl:3545/3610/3728 |
| `luminosity_schedule` | interface.jl:2304 (`_pic_compute_luminosity`) → pic_cpu.jl:47, pic_cuda.jl:67/197 |
| `slicing` / `slicing1` / `slicing2` | interface.jl:1242-1243 → pic_cpu.jl:42, :43 |
| `backend_configurations` | interface.jl:188 (`_cuda_pic_configuration`) → :198-203 → `_cuda_pic_threads` |

### `StrongStrongTask` / `StrongStrongCollision` / `execute!`

| option | declared? | consumer (file:line) |
|---|---|---|
| `luminosity_path` | schema :1593 | interface.jl:2019, 2030, 2038, 2131 |
| `luminosity_append` | schema :1596 | interface.jl:2133 **only**; the declared `:strong_strong_output` receipt does not carry it — LEAD U5-3 |
| `policy` | no schema entry | interface.jl:2183-2184 (`_resolve_execution_policy`) |
| `default_poisson_solver` | no schema entry | interface.jl:2485 |
| `poisson_solver` | no schema entry, **undocumented** | interface.jl:1935 (overrides `default_poisson_solver`) |
| `diagnostics` | no schema entry (own schema at :343) | interface.jl:2028, 2202, 2249 |
| `record_turn_times` (task kw) | no schema entry, prose-documented | interface.jl:1936-1941 (compat adapter) |
| `seed` | no schema entry, **undocumented** | interface.jl:1934 — deprecated, warns, otherwise ignored |
| `StrongStrongCollision(; poisson_solver)` | — | interface.jl:2468-2469 |
| `execute!(; turns, start_turn)` | — | Tasks.jl `_task_execution_window` → interface.jl:1985 |

**(b) Consumed but not declared:** the three `LongitudinalSlicing` method aliases
(LEAD U5-12); the six `StrongStrongTask` keywords above with no schema entry, of which
`poisson_solver` and `seed` are also undocumented (LEAD U5-4); `backend_configurations`
declared in the schema but absent from the docstring (LEAD U5-15). No case was found where
runtime behavior is keyed off a value with no declaration *anywhere*.

---

## Clean — what was checked and the evidence

- **(c) Unknown-keyword acceptance is closed for this file's whole public surface.**
  Twelve deliberately misspelled keywords across `PICPoissonSolver`,
  `PICPoissonSolver{Float64}`, `GaussianPoissonSolver`, `SpectralPoissonSolver`,
  `GaussianPICPoissonSolver`, `LongitudinalSlicing` (both methods), `CUDAPICLaunchConfig`,
  `StrongStrongDiagnostics`, `StrongStrongCollision` and `StrongStrongTask` (including
  `luminosity_apend` and a plausible-but-wrong `append`) — **all twelve raise `MethodError`**.
  The `(; kwargs...)` outer constructors forward to explicitly-keyworded inner methods, so
  the slurp does not swallow typos. (`u5_p1_static.jl` §(c).) The open U3-10/U13-1 lead
  family does not reproduce here.
- **(e) Declared defaults agree with the constructors** for every surface that has a real
  default check: `LongitudinalSlicing`, `PICPoissonSolver`, `GaussianPoissonSolver`,
  `SpectralPoissonSolver`, `GaussianPICPoissonSolver`, `StrongStrongDiagnostics`,
  `EveryNSteps`, and both CPU/CUDA policies — `validate_configuration_metadata()` passes
  inside `PublicConfigurationEffectivenessContract`. The exceptions are the *missing*
  checks (LEAD U5-14) and the tautological task check (LEAD U5-4), not a disagreement.
  `StrongStrongTask`'s two schema defaults do match the constructor when compared against a
  real object (`u5_p1_static.jl`: both `agree=true`).
- **Both effectiveness contracts pass at HEAD on this GPU box** (`u5_p5_contracts.jl`,
  `CUDA functional: true`): `PublicConfigurationEffectivenessContract` **passed** in 58.6 s
  ("Public configuration reached CPU, fused CUDA, and CUDA PIC consumers");
  `SolverOptionEffectivenessContract` **passed** in 93.3 s ("every declared solver option
  reached a runtime consumer (68 on CPU, 10 CUDA-only options, 2 launch surfaces)"). So
  every *solver* option in this file is measured to reach a consumer; the gaps found are at
  the task level and in the report/tripwire layer, which those contracts do not sweep.
- **The new fixed-chunk constants deliver the invariance their comment claims.**
  `_PIC_DEPOSIT_CHUNKS = 16` / `_REDUCTION_CHUNKS = 64` (interface.jl:580-581), which
  replaced `_cpu_worker_count()`-dependent chunking, were tested *above* the parallel
  thresholds (20,000 particles/beam ⇒ ~6,600/slice vs a 4,096 threshold), 3 slices,
  2 turns: **bit-identical coordinates and luminosity rows at 1, 2 and 8 workers, for both
  `PICPoissonSolver` and `GaussianPoissonSolver`** (`u5_p10_threads.jl` §P10). The prior
  audit's U5-1/U5-2 defect is measurably fixed at HEAD. Both constants are consumed
  (`_PIC_DEPOSIT_CHUNKS` at interface.jl:637, pic_cpu.jl:1405/1420/1437; `_REDUCTION_CHUNKS`
  at gaussian.jl:70, slicing.jl:637), as are `_STRONG_STRONG_PARALLEL_MOMENT_MIN`,
  `_STRONG_STRONG_PARALLEL_KICK_MIN`, `_PIC_PARALLEL_DEPOSIT_MIN` and
  `_PIC_TEMPLATE_MARGIN_CELLS`.
- **The `:inactive_dependency` classifications that *are* implemented are correct.**
  `resolution` is read only by `_longitudinal_slices_equal_area` (slicing.jl:105/109) and
  its CUDA twin, and `positions` only by `_longitudinal_slices_specified` (slicing.jl:346)
  — both match interface.jl:743-748. `slice_pair_green_min_ratio`/`_growth` correctly report
  `:inactive_dependency` under `green_cache=:none` (`u5_p1_static.jl`). The
  `interaction_grid`×`grid_extent` incompatibility is rejected at construction
  (interface.jl:1281-1286) and again at collide time (pic_cpu.jl:234-240) rather than
  silently ignored. Only `grid_extent_sigma` is ungated (LEAD U5-5).
- **No CPU-only option exists in any schema declared in this file**, so the absence of a
  CUDA-side mirror of `_preflight_solver_configurations!`'s CPU warning is vacuous rather
  than a hole (`u5_p11_final.jl` §F2 prints nothing). The CPU-side warning covers *every*
  solver, not only PIC (interface.jl:2061-2071), which is the U8-era fix holding.
- **The new torn-line / atomic-rename protocol behaves as documented** in the cases the
  suite pins (runtests.jl:3965-3995, re-read): torn last line dropped with a warning; a
  malformed non-last row refused; the whole-history replacement warned; `mv(tmp, path)`
  leaves no `.prepare.tmp` residue after a successful prepare (`u5_p3_ordering.jl` §P4c:
  `tmp exists: false`). The residual risks the docstring itself records (a value-truncating
  torn line with the right field count) are honestly stated.
- **Schema ↔ configuration-report agreement holds for the task's output block**
  (`[:luminosity_path, :luminosity_append]` on both sides, `u5_p1_static.jl`) — although
  nothing *checks* this for the task the way interface.jl:1787-1792 checks it for observers.
- **Luminosity-schedule dispatch is complete**: `_strong_strong_luminosity_evaluated` has
  methods for `PICPoissonSolver` (interface.jl:2316), `GaussianPICPoissonSolver`
  (gaussian_pic.jl:168) and `SpectralPoissonSolver` (spectral.jl:277), matching the three
  solvers whose schemas declare `luminosity_schedule`; `GaussianPoissonSolver` deliberately
  has none (documented at interface.jl:53-60).
- **Deposit-buffer memory is bounded as the comment claims** — 16 buffers regardless of
  worker count: 0.5 MiB at grid (32,32), 8.0 MiB at (128,128), 32.0 MiB at (256,256)
  (`u5_p10_threads.jl` §P11). A single-worker run now pays 16× the old `local_charge`
  footprint, but the absolute numbers are small at production grids; recorded as an
  observation, not a lead.

## Observations (not counted as leads)

- `_execute_strong_strong_turns!` allocates a fresh `Float64[]` and `Bool[]` per turn
  (interface.jl:2204-2205) when a luminosity file is open; hoisting and `empty!`-ing would
  remove two small allocations per turn. Style/perf only.
- `_preflight_solver_configurations!`'s CPU warning (interface.jl:2074) names the option
  set but not which collision or solver produced it; with several IPs carrying different
  solvers the message is ambiguous.
- `configuration_report(task, beam1, beam2)` calls `_strong_strong_runtime_blocks`
  (interface.jl:1888-1889), which can rebuild the block cache and `empty!` the matching
  plan cache — a "report" with a cache side effect.
- `_strong_strong_maybe_log_cuda_memory` logs unconditionally at turn 0 regardless of the
  cadence (interface.jl:2342); pre-existing and noted by U4.
- `BPMObserver.rng_id`'s schema default `0` versus the constructor's auto-assigned unique
  id is a documented sentinel, not a class-(e) disagreement — checked, and it is the reason
  a naive observer default check would fail (see LEAD U5-14).

## Not checked, and why

- **`configuration_report(config::CUDAPICLaunchConfig)` on a CUDA-free machine.** Its
  second parameter defaults to `CUDAExecutionPolicy()` (interface.jl:175), constructed at
  call time; whether that is safe without a device could not be tested here because this
  box has a functional CUDA. Suspected benign; flagged for a CPU-only box.
- **Crash-injection durability of the prepare rewrite.** `mv(tmp, path; force=true)`
  (interface.jl:2174) closes the U4-2 window, but neither the temp file nor the directory
  is fsynced, so a power loss can still leave the rename unpersisted. Not probeable within
  this unit's budget; the residual is smaller than what U4-2 reported.
- **Cross-file seams**, per the standing rule: the two-writer commit protocol shared with
  `BeamObservers.jl` (LEAD U5-1), the double-evaluation contract shared with the PIC/
  spectral/Gaussian-PIC collide paths (LEAD U5-2), and the effectiveness-contract coverage
  boundary in `Contracts.jl` (LEAD U5-3) are noted as leads and stopped there.
- **Numerical/physics content of the solvers** (`gaussian.jl`, `pic_cpu.jl`, `pic_cuda.jl`,
  `spectral*.jl`, `gaussian_pic*.jl`): outside this unit's region; read only far enough to
  locate consumers.
