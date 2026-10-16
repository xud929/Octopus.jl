# U9 localisation-unit report: lead U1-3, the general turn loop's per-turn allocation (crab cavity noise campaign audit, 2026-10-16)

Repository: Octopus main checkout `/cfs/ad/dxu/Library/Julia/Octopus` at commit `3126908`
(worktrees untouched; the only untracked file is the pre-existing
`docs/history/audit_crab_cavity_noise_neighbours_2026_10_16.md`). Julia 1.12.4,
`julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=1`, host `acnlinj4` (Xeon Gold 6430,
one NVIDIA RTX 4500 Ada present; every probe ran the CPU threads policy except the example's own
`execution = :auto`, which resolved to `CUDAExecutionPolicy` as the probe recorded). Nothing in
the repository was modified; probes and logs live in `result/audit_crab_noise_2026_10_16/U9/`.
Measurement only; the fix below was evaluated into probe processes with `include_string`, never
written to a source file.

## Result in one paragraph

The lead is confirmed and localised, and its hypothesis is corrected: the cost has nothing to do
with the artifact, the `record_turn_modulation` switch, the sink keyword or the recorder. Any
task that leaves the fast loop (an artifact, an observer, an action or an in-line hook) pays it,
and it is a property of the LINE: on a line whose compiled runtime-entry tuple holds two or more
distinct element types, `_active_plan_key` (`src/tasks/Tasks.jl:1667-1676`, called every turn at
line 1116) walks the tuple with a runtime index, and each of its N iterations boxes the WHOLE
isbits tuple (`sizeof(entries)` bytes) plus one element -- 185.9 of the 199.7 kB/turn on the
8-type line, 89.8 of 97.8 kB/turn on the suite's two-type fixture, 32.6 kB/turn on the
crab-noise example's own 13-entry task. The remainder is the `get!(task.plan_cache, plan_key)
do ... end` closure at line 1118, which captures the entries tuple by value and is heap-allocated
every turn (two copies of the tuple: 9.3 / 4.5 / 2.7 kB/turn; the one-type line's whole 3.2 kB).
Every piece of the segment path -- `update_line` with a `Nothing` or `TurnModulationRecorder`
sink, `track!`, the segment and plan calls, even with the plan read out of the `Dict{Any,Any}`
and a `Union`-typed sink -- allocates 0 B. A two-statement fix (hoist the hook scan out of the
turn loop; replace the `get!` closure by `get`/`setindex!`) measured 199,728 -> 448 B/turn on the
8-type line, 98,415 -> 1,071 on the fixture, 3,200 -> 448 on the one-type line, and 59,022 ->
21,613 on the example's task; the time per turn with the physics negligible fell from 39.5 to
6.8 us (GC 13.5 -> 0 us).

## Region and provenance

- READ, every line: `src/tasks/Tasks.jl` 38-60 (`TrackingTask`), 178-215 (constructor), 657-800
  (`execute!`), 970-1180 (`_execute_tracking_task!`, the general loop), 1215-1245
  (`_execute_fast_tracking_turns!`), 1280-1325 (entry structs, `_runtime_entries`), 1618-1720
  (`_physics_line`, `_has_line_hooks`, the segment structs, `_active_plan_key`,
  `_build_tracking_plan`, `_append_tracking_segments!`, `_flush_fused_segment!`), 1780-1900
  (`_strong_beams_of`, `_execute_tracking_plan_turn!` and the five segment methods), 1925-1978
  (`_track_fused_runtime!`, `_track_isolated_runtime!`, `_finalize_line_observers!`);
  `src/tasks/RunArtifact.jl` 15-50 (`TurnModulationRecorder`), 150-192 (`RunArtifact`), 504-660
  (`_ra_create_turn_modulation_series!`, `_turn_modulation_sink`, `_record_turn_draws!`,
  `_tm_begin_turn!`/`_tm_end_turn!`, `_ra_flush_turn_modulation!`, `push_luminosity!`,
  `_ra_flush_luminosity!`); `src/track/phase6d_track.jl` 1-120; `src/track/fused_track.jl`
  100-140; `src/policies/Policies.jl` 188-215, 1236-1275; `src/tasks/BeamObservers.jl` 150-200,
  375-402; `src/elements/turn_modulated.jl` 1390-1420 (`update_line`); `test/runtests.jl`
  7899-8010 and 10025-10085 (the allocation pins); `examples/crab_cavity_noise.jl` 155-185,
  236-340, 655-700; `docs/design/turn_modulation.md` 640-720 and
  `docs/design/turn_modulation_record.md` 380-395 (the cost tables); U1's report, `probe_slope.jl`,
  `alloc_helpers.jl` and its logs; Base `tuple.jl` 31-35, 71-75 (`getindex`, `iterate`).
- EXECUTED (read-only; script and `.log` side by side in `U9/`):
  `step1_probe_slope_t1.log` (U1's `probe_slope.jl` re-run), `probe_split.jl` (artifact /
  switch / general-loop separation), `probe_pieces.jl` (the segment path taken apart, typed IR),
  `probe_loop.jl` (the loop's other per-turn statements, the loop body's typed IR),
  `probe_allocs.jl` (`Profile.Allocs`, `sample_rate = 1`, 200 turns), `probe_fix.jl` (pure-Julia
  mechanism, candidate shapes, `_active_plan_key` patched alone), `probe_fix2.jl` (the closure in
  isolation; the complete fix patched; end-to-end slopes), `probe_example.jl` (the example's own
  task before/after), `probe_timing.jl` (time and GC per turn before/after).

## The five steps, with numbers

1. Reproduction (U1's probe, one thread, `step1_probe_slope_t1.log`): identical to U1 --
   recording 3200.0 (40 x crab1), 199728.0 (crab1..crab8 cycled), 98415.2 (crab1 white + disp)
   B/turn; plain -472.7 B/turn (zero) for all three. Note U1's "plain" column had NO artifact and
   so took the fast loop, while its "recording" column attached an artifact with
   `record_turn_modulation = true`: the comparison conflated three switches.
   Separated (`probe_split.log`, same lines):

   | line | fast loop (no artifact) | general loop, no artifact, one no-op action | artifact, record = false | artifact, record = true |
   |---|---|---|---|---|
   | 40 x crab1 (1 type, 0 modulated) | 0.0 | 3264.0 | 3200.0 | 3200.0 |
   | crab1..crab8 (8 types, 0 modulated) | 0.0 | 199792.0 | 199728.0 | 199728.0 |
   | crab1 white + disp (2 types, 20 modulated) | 0.0 | 97856.0 | 97792.0 | 98415.2 |

   The artifact adds nothing measurable; the recording switch adds 623 B/turn on the fixture
   (the recorder's buffer growth, lead U9-5) and nothing elsewhere -- on the 8-type line the
   sink is `nothing` (`_turn_modulation_sink` returns a recorder only for a beam with a
   modulated element; `_turn_modulation_entries(elems, 1)` is empty there).

2. Localisation (`probe_allocs.log`, `Profile.Allocs` at `sample_rate = 1` over 200 turns after
   warm-up, artifact attached, `record_turn_modulation = true`; the innermost Octopus frame):

   8-type line, 203,455 B/turn recorded (the figure includes the per-call constant):
   - `tasks/Tasks.jl:1674  _active_plan_key` -- 37,176,000 B in 15,600 allocations = 185,880
     B/turn; the type is the whole entries tuple `Tuple{PhysicsEntry{ThinCrabCavity{1,..}},
     ..., PhysicsEntry{ThinCrabCavity{8,..}}}` (8,119 allocations of 4,648 B = sizeof 4,640 +
     8) plus one box per entry type (`PhysicsEntry{ThinCrabCavity{k,..}}`, 1,015 each).
   - `tasks/Tasks.jl:1118  _execute_tracking_task!` -- 1,860,800 B in 400 allocations = 9,304
     B/turn: the `get!` do-block closure `var"#1107#1108"{Tuple{PhysicsEntry...}, Tuple{Tuple{},
     Bool, Symbol}}` (200 x 4,656 B) plus one boxed copy of the entries tuple.
   - once per `execute!`, not per turn (78 allocations each over the call): `Tasks.jl:1619
     _physics_line`, `1788 _strong_beams_of`, `1972 _finalize_line_observers!`,
     `BeamObservers.jl:293 prepare_line_observers!`, `turn_modulated.jl:1607
     _turn_modulation_columns!`, `1578 _turn_modulation_provenance!`, `1432 _check_turn_window`,
     `Tasks.jl:1017` -- about 186 kB per call each, the same mechanism (lead U9-4).
   - `Tasks.jl:1122` (the plan kwcall) 144 B/turn, `1113`/`1124`/`1114` about 270 B/turn
     together: the boxes of `ctx`, the policy and the key for the dynamic dispatches.

   Two-type fixture, 100,525 B/turn recorded: `Tasks.jl:1674 _active_plan_key` 89,832 B/turn;
   `Tasks.jl:1118` 4,504 B/turn; `RunArtifact.jl:570 _record_turn_draws!` 580 B/turn
   (`Memory{Float64}` growth of the 20 unsized buffers); `RunArtifact.jl:621` 239 B/turn; the
   rest per call. One-type control, 3,333 B/turn recorded: `Tasks.jl:1118` 2,656 B/turn
   (`NTuple{40, PhysicsEntry{..}}` 202 x 1,359 B and the closure 200 x 1,296 B), `1669`
   32 B/turn (the `Int[]`), `1675` 16 B/turn.

   Direct measurement of the loop's other per-turn statements (`probe_loop.log`, entries
   concretely typed as inside the loop): `_active_plan_key(entries, ctx, false, :isolated)`
   189,840 B (8 types) / 92,704 B (fixture) / 64 B (1 type); a bare `for e in entries; e isa
   Union{LineObserverEntry,LineActionEntry}; end` 189,776 / 92,640 / 0 B; `get!(plan_cache,
   key)` with a concrete key 0 B; `run_actions!`, `run_observers!`,
   `requires_elementwise_tracking`, `_has_line_hooks` 0 B. Arithmetic: 40 x (4,640 + 8) =
   185,920 plus 40 element boxes of about 98 B = 189,840; 40 x (2,240 + 8) = 89,920 plus 40 x
   about 70 B = 92,704; the example's 13 x (2,384 + 8) = 31,096 plus 13 boxes = 32,640.

3. The sink keyword does not destabilise the plan path (`probe_pieces.log`): `Base.return_types`
   of `update_line` with a `Nothing` and with a `TurnModulationRecorder` sink is the concrete
   tuple type on all three lines; the typed IR of `Core.kwcall((sink = rec,),
   _execute_tracking_segment_turn!, rep, seg, policy, ctx)` and of the `sink = nothing` form
   (101 statements each; 95 for the positional method) shows `update_line` inlined, the
   rebuilt tuple and the `Ref` store concretely typed, and `_run_logical_workers` statically
   `:invoke`d with a concrete closure type `var"#track!##0#track!##1"{Phase6DRep{Vector{Float64}},
   Tuple{ThinCrabCavity{1,..}, ...}, ...}`; the only `Any` is that call's unused return. Measured:
   `update_line(elems, ctx)`, `update_line(elems, ctx, nothing)`, `update_line(elems, ctx, rec)`,
   `track!(rep, elems, 1, policy, ctx)`, `ref[] = update_line(elems, ctx)`, the segment call and
   the plan call with either sink, and the plan read out of a `Dict{Any,Any}` with a
   `Union{Nothing,TurnModulationRecorder}`-typed sink argument: 0 B on all three lines.

4. `_turn_modulation_sink(art, 1)` is `Union{Nothing,TurnModulationRecorder}` in the loop, but
   no closure captures it: the loop's only closure is the `get!` do-block, which captures
   `runtime_entries` and `plan_key`; the sink reaches `_tm_begin_turn!`, `_tm_end_turn!` and the
   plan kwcall as a direct argument, where the dynamic dispatch costs the boxes counted at
   lines 1113/1114/1122/1124 above (below 500 B/turn in total). No `Core.Box`: no local of the
   loop is reassigned inside a closure. The loop body's typed IR (`probe_loop.log`, 978
   statements) has no dynamic call in the per-turn region other than the kwcall itself.

5. Fix and expected allocation (`probe_fix.log`, `probe_fix2.log`, `probe_example.log`,
   `probe_timing.log`): see "Minimal fix" below. Pure-Julia mechanism check: a 40-tuple of two
   isbits struct types (sizeof 4,000) iterated with `for e in t` allocates 164,112 B = 40 x
   (4,000 + a box); the homogeneous 40-tuple 0 B; `count(f, t)` 159,904 B; the LLVM IR of the
   heterogeneous loop is `%"box::Tuple" = call @ijl_gc_big_alloc(ptls, 4008, ...)`, a 4,000-byte
   `memcpy` of `t` into the box and `call @ijl_get_nth_field_checked(%"box::Tuple", i)` per
   iteration (`iterate(@nospecialize(t::Tuple), i)` at Base `tuple.jl:71`, `getindex` at 33).

## Leads

### LEAD U9-1 [medium, confidence high] src/tasks/Tasks.jl:1667-1676 (`_active_plan_key`, called per turn at 1116)
Claim: every turn of the general loop, `_active_plan_key` iterates the compiled runtime-entries
tuple with a runtime index, and on any line whose entries hold two or more distinct element
types each of the N iterations boxes the entire tuple (sizeof(entries) bytes) plus one element,
costing N x (sizeof(entries) + box) per turn: 185.9 of the 199.7 kB/turn U1 measured on the
8-type line, 89.8 of the 97.8 kB/turn on the suite's two-type fixture, 32.6 kB/turn on the
crab-noise example's own task (13 entries, 8 types, sizeof 2,384 B) -- independent of the
artifact, of `record_turn_modulation` and of the sink, taken by every task that has an
artifact, an observer, an action or an in-line hook, zero on a homogeneous line, and quadratic
in the line length.
Mechanism: `for entry in entries` lowers to `Base.iterate(@nospecialize(t::Tuple), i)` ->
`getfield(t, i)` with an index unknown at compile time; codegen has an unboxed indexed load only
for homogeneous tuples, so a heterogeneous tuple is boxed (`ijl_gc_big_alloc(sizeof + 8)` and a
`memcpy` of the whole tuple) and read through `ijl_get_nth_field_checked`, which boxes the
element too; the entries tuple is isbits (1,280 / 2,240 / 4,640 B here) and lives unboxed in
the loop, so the copy is paid at every iteration of every turn. The fast loop never calls
`_active_plan_key`, which is why U1's "plain" column (no artifact, fast loop) read zero.
Repro: `julia --project=. --threads=1 result/audit_crab_noise_2026_10_16/U9/probe_loop.jl` ->
`_active_plan_key(entries, ctx, false, :isolated)  189840 B` (8 types), `92704 B` (fixture),
`64 B` (1 type); `probe_allocs.jl` -> `tasks/Tasks.jl:1674  _active_plan_key  185880.0` B/turn,
type `Tuple{Octopus.PhysicsEntry{ThinCrabCavity{1,...}}, ...}` 8119 x 4648 B. Pure Julia, no
Octopus: `julia -e 'struct PA; a::NTuple{12,Float64}; end; struct PB; a::NTuple{12,Float64}; b::Int; end; f(t)=(c=0; for e in t; c+=e isa PB; end; c); t=ntuple(i->isodd(i) ? PA(ntuple(Float64,12)) : PB(ntuple(Float64,12),i), Val(40)); f(t); println(@allocated(f(t)), " B, sizeof ", sizeof(typeof(t)))'`
-> `164112 B, sizeof 4000`; with every element a `PA` -> `0`.

### LEAD U9-2 [low, confidence high] src/tasks/Tasks.jl:1118-1120
Claim: the `get!(task.plan_cache, plan_key) do _build_tracking_plan(runtime_entries, plan_key) end`
closure captures the entries tuple by value and is heap-allocated every turn together with a
boxed copy of the tuple, 2 x sizeof(entries) per turn: 9.3 kB (8 types), 4.5 kB (fixture) and
2.7 kB (one type -- essentially the whole 3.2 kB/turn U1 saw on the homogeneous line).
Mechanism: `plan_key = (Tuple(active_hooks), ...)` has the abstract type `Tuple{Tuple{Vararg{Int64}},
Bool, Symbol}` (`Tuple(::Vector{Int})`), so the `get!` call is dynamic; the closure is then
built and boxed for `jl_apply_generic`, its captured 4.6 kB tuple copied twice. With a concrete
key in isolation the same `get!` costs 0 B (`probe_fix2.log`), which is why it hid.
Repro: `julia --project=. --threads=1 result/audit_crab_noise_2026_10_16/U9/probe_allocs.jl` ->
`tasks/Tasks.jl:1118 ... 9304.0` B/turn (8 types), `4504.0` (fixture), `2656.0` (1 type), types
`Octopus.var"#1107#1108"{Tuple{PhysicsEntry...}, Tuple{Tuple{}, Bool, Symbol}}` 200 x 4656 B;
`probe_fix.jl` (only `_active_plan_key` patched) leaves 9920 / 5743 / 3168 B/turn, `probe_fix2.jl`
(closure replaced as well) 448 / 1071 / 448 B/turn.

### LEAD U9-3 [medium, confidence med] src/tasks/strongstrong/interface.jl:3116-3119 (seam, outside the region)
Claim: the strong-strong segment loop calls the same `_active_plan_key(entries, ctx, false,
:isolated)` and the same `get!(plan_cache, plan_key) do` closure per block per turn, so each
beam's heterogeneous block pays U9-1 and U9-2 (N_block x sizeof(block entries) plus two copies)
on every turn; not measured here (no strong-strong fixture was built, the region is U9-1's).
Mechanism: identical code shape; `grep -n "_active_plan_key\|get!(plan_cache" src/tasks/strongstrong/interface.jl`.
Repro: build any strong-strong task whose block entries mix element types and measure
`@allocated Octopus._active_plan_key(block.entries, ctx, false, :isolated)` as `probe_loop.jl`
does; expected N x (sizeof(entries) + about 100) B per block per turn, 0 B for a homogeneous
block.

### LEAD U9-4 [low, confidence high] out of hypothesis: the once-per-`execute!` walks over heterogeneous tuples -- src/tasks/Tasks.jl:1619 (`_physics_line`), 1694 (`_count_active_line_diagnostics`), 1708 (`_append_tracking_segments!`), 1786 (`_strong_beams_of`), 1965 (`_finalize_line_observers!`); src/tasks/BeamObservers.jl:293 (`prepare_line_observers!`); src/elements/turn_modulated.jl:1432, 1578, 1607
Claim: every `for x in tuple` walk over the entries or elements tuple boxes the whole tuple per
element by the mechanism of U9-1, about 186 kB per walk per `execute!` on the 8-type line
(`_physics_line` 201,568 B per call at `Tasks.jl:671`, `_strong_beams_of` 185,880, the
turn-modulation walks 181,176-181,240 each, `prepare_line_observers!` and
`_finalize_line_observers!` 185,880 each); harmless for one long call, about 1.1 MB per call for
a run that executes turn by turn or in short chunks.
Mechanism: as U9-1; these run once per call, not per turn, so they are not the lead's cost.
Repro: `probe_allocs.jl` rows with 76-78 allocations per 200-turn call; `probe_loop.jl` ->
`_physics_line(entries) 206240 B`, `_strong_beams_of(elems) 189808 B`, `_turn_modulation_entries
185008 B` per call on the 8-type line, 9304 / 32 / 32 B on the one-type line.

### LEAD U9-5 [low, confidence high] src/tasks/RunArtifact.jl:531 (recorder buffers) and 570 (`_record_turn_draws!`)
Claim: the recorder's buffers are created as `Float64[]` with no `sizehint!`, so the recording
hook's `push!` grows them by doubling: 116,000 B in 120 allocations over 200 turns on the fixture
(580 B/turn averaged), the one cost the recording switch itself adds (98,415 - 97,792 = 623
B/turn in `probe_split.log`); a `sizehint!(buf, capacity * ncols)` at creation would make the
hook allocation-free up to the flush, as the design note's "a few copies into the row buffer"
reads.
Mechanism: `TurnModulationRecorder(file, art.capacity, beam, keys_b, active_b, [Float64[] for _ in keys_b], 0, 0)`
sizes nothing; `_ra_flush_turn_modulation!` `empty!`s the buffers, which keeps their capacity, so
the growth is paid once per execute! up to `capacity` rows, not per flush.
Repro: `probe_allocs.jl` fixture block -> `tasks/RunArtifact.jl:570  _record_turn_draws!
116000  120  580.0`, type `Memory{Float64}` 122 allocations.

### LEAD U9-6 [low, confidence high] test/runtests.jl:7999-8001 and 10040-10070; docs/design/turn_modulation.md:654-656
Claim: no existing pin can catch U9-1 or U9-2, with or without an artifact: the only
`execute!`-level allocation pin (testset "TrackingTask records per-turn timings on BOTH of its
turn loops", `a_on <= a_off + 8 * 64 + 1024`) uses `line = (DriftSpec(L=1.0),)`, a one-element
and therefore homogeneous line, and compares `record_turn_times` ON against OFF on the same
loop, so the loop's own per-turn cost cancels by construction; the `update_line` pins (testset
"Turn modulation: rules, wrapper and the pure hook", `alloc_update` / `alloc_update_sink`) have
exactly the fixture that allocates 97.8 kB/turn through `execute!` (`line40`: 40 elements, two
types) but pin the hook alone; the design table's "40 elements ... 0 bytes" per turn is the
hook's number, not the loop's.
Mechanism: the hook is allocation-free (confirmed, step 3); the loop around it was never
measured on a heterogeneous line.
Repro: `grep -n "@allocated" test/runtests.jl | grep -i "execute!"` -> only lines 7999-8000;
`sed -n '7913p' test/runtests.jl` -> `line = (DriftSpec(L=1.0),)`.

## Minimal fix (proposed, not applied) and the allocation after it

Two statements in `_execute_tracking_task!` (`src/tasks/Tasks.jl`), one helper and one method:

1. Once per `execute!`, before the turn loop (beside `_tm_sink = _turn_modulation_sink(art, 1)`):
   `hook_entries = _line_hook_entries(runtime_entries)` with
   `_line_hook_entries(entries::Tuple) = Any[e for e in entries if e isa Union{LineObserverEntry,LineActionEntry}]`
   (this walk boxes too, once per call, lead U9-4; a `@generated` or `any`-style per-position
   walk would make it free).
2. Per turn: `plan_key = _active_plan_key(hook_entries, ctx, task_diagnostics, task.luminosity_tracking)`
   with a new method
   `_active_plan_key(hooks::Vector{Any}, ctx, task_diagnostics::Bool, luminosity_tracking::Symbol=:isolated)`
   that returns `((), task_diagnostics, luminosity_tracking)` when `hooks` is empty and otherwise
   loops over the hooks only, pushing `entry.hook_index` where `_line_entry_active(entry, ctx)`.
   The tuple method stays for the strong-strong caller until U9-3 is treated the same way.
3. `plan = get(task.plan_cache, plan_key, nothing); if plan === nothing; plan =
   _build_tracking_plan(runtime_entries, plan_key); task.plan_cache[plan_key] = plan; end` in
   place of the `get!` do-block (no closure, nothing captured).

Measured with exactly this text evaluated into the probe process (`probe_fix2.log`,
`probe_example.log`, `probe_timing.log`; artifact attached, `record_turn_modulation = true`,
one thread):

| line | before, B/turn | after, B/turn |
|---|---|---|
| 40 x crab1 (1 type) | 3200.0 | 448.0 |
| crab1..crab8 cycled (8 types) | 199728.0 | 448.0 |
| crab1 white + disp (suite fixture, 2 types) | 98415.2 | 1071.2 (580 of it lead U9-5) |
| 8 types + one in-line `MomentObserver` (2 segments) | 208279.9 | 4231.9 (the observer's rows) |
| the example's task (13 entries, 8 types, 10,000 particles, CUDA by `:auto`) | 59022.1 | 21612.6 |

Time per turn on the 8-type line with four particles (physics negligible), best of three runs
of 2000 turns: 39.49 us (GC 13.54 us) before, 6.80 us (GC 0) after; the fast loop on the same
line 6.03 us; the one-type line 2.50 -> 1.87 us. On the example's task 566.6 -> 545.8 us/turn,
within the shared host's noise. The remaining 448 B/turn are the dynamic-dispatch boxes
(`ctx`, policy, key, the plan kwcall); the hooks-case key `Tuple(active_hooks)` stays abstract and
could be made concrete separately.

A pin that would have caught it, and would guard the fix: an `execute!`-level slope on a
heterogeneous line -- the suite's own `line40` fixture (two types, 40 elements) through
`TrackingTask(...; artifact=RunArtifact(path; capacity=10^6))`, `(@allocated 250 turns -
@allocated 50 turns) / 200` after warm-up, bounded at a few hundred bytes per turn (or at the fast
loop's slope plus a constant), asserting `fast_path === false` through the
`:tracking_turn_timing` receipt as the timing testset already does. The strong-strong twin
(U9-3) needs its own.

## Clean (checked and sound, with what was compared)

- The sink keyword path: `_execute_tracking_plan_turn!(...; sink)` and the segment methods are
  type-stable for `sink::Nothing` and `sink::TurnModulationRecorder` alike (typed IR, step 3);
  `update_line` with either sink returns the concrete tuple type and allocates 0 B on all three
  lines (U1's hook-level finding confirmed on the compiled runtime tuples).
- `_turn_modulation_sink(art, 1)`: returns `nothing` on the 8-type line (no modulated element),
  the recorder on the fixture; the Union is dispatched directly, captured by no closure, no
  `Core.Box` in the loop body.
- `track!(rep, elems, 1, policy, ctx)`, the `FusedSegment` `Ref` store, the plan call with the
  plan read out of the `Dict{Any,Any}`: 0 B each on all three lines.
- `run_actions!`, `run_observers!` (empty hooks), `requires_elementwise_tracking`,
  `_has_line_hooks` (`any(f, t)`, per-position): 0 B per turn.
- The artifact's own per-turn costs with no strong beam: no luminosity rows (`push_luminosity!`
  not reached), no flush within 250 turns at `capacity = 10^6`; `_tm_begin_turn!`/`_tm_end_turn!`
  0 B; the recording switch adds only the 623 B/turn of U9-5.
- The recording changes no number: the probes' lines produced identical `plan_cache` keys and
  the example's end-of-run summary printed as shipped.

## Unchecked, and why

- Four threads: not re-measured here; the mechanism is host-side and thread-independent, and
  U1's four-thread column (221,136 B/turn on the 8-type line against 199,728 at one thread) is
  the one-thread number plus the `_run_logical_workers` spawn cost it also shows on the plain
  line (7.7 kB/turn).
- The strong-strong loop (U9-3): not measured, outside the region.
- The CUDA general loop: not measured separately; only the example's `:auto` run touched it, and
  its 37.4 kB/turn attributable to the lead matches the host-side arithmetic.
- The fix was evaluated by `include_string` into probe processes and exercised by `execute!` on
  five tasks (including a line with an in-line observer, whose second plan key was built and
  cached); it was not run through the suite.
