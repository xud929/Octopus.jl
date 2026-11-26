> Archived by the stage-5 fold (2026-11-25); the orchestrator's dispositions are in the report [`../audit_machine_description_2026_11_25.md`](../audit_machine_description_2026_11_25.md). The file:line pointers are of the unit's tree (5efe850, the stage-4 tree plus the stage-5 skeleton) and the logs it names sit under the scratch directory of the day as the report's section 5 states.

# U1 -- the lattice, machine, codec and task-constructor layer

Reading unit of [../audit_machine_description_2026_11_25.md] (the orchestrator's report; title per the brief).

Region: `src/lattice/Lattice.jl`, `Machine.jl`, `elements_macro.jl`, `toml.jl`, `toml_hooks.jl`; `_element_tuple` and
its callers in `src/tasks/Tasks.jl`; the `TrackingTask` constructor's machine path and `_task_machine`; the
`StrongStrongTask` machine forms, `_strong_strong_task`, `_strong_strong_machine`, `_split_strong_strong_line`,
`_append_strong_strong_line!` in `src/tasks/strongstrong/interface.jl`; the placement-override guards and
`setproperty!(::LineEntry)` in `src/elements/beam_line.jl`; the knob epoch's readers (`_has_knob_parameters`,
`knob_epoch`, `_spec_epoch`).

Hypothesis: a walker dispatching on a bare type while a `LineEntry` wraps the child (the stage-3 marker defect); a
pin that inspects the stored form without executing; an encoder/decoder pair that disagrees on a value class; a
refusal present on one route and absent on its twin.

Provenance: unit B, machine-description stage 5, 2026-11-25. Commit 37441bf on md5-B over 5efe850 (the stage-4 tree plus the
stage-5 stubs). Every file:line below is of that tree before the unit's fixes unless marked "after".

## Leads

### LEAD B-1 [Minor, confidence med] src/tasks/Tasks.jl:2525, src/tasks/strongstrong/interface.jl:3937
Claim: a walker outside the fixed strong-strong walker dispatches on a child's bare type while a `LineEntry` wraps it,
and mishandles the wrapped hook or marker.
Mechanism: `BeamLine` wraps EVERY child in a `LineEntry` (beam_line.jl:320), hooks and markers included; a walker
with methods for `ScheduledObserver`/`StrongStrongCollision` and a generic fallback sees the `LineEntry` in the
fallback unless it has a `LineEntry` method that unwraps (the stage-3 defect: the marker compiled as a physics
entry).
Repro: `julia --project=WT --startup-file=no /tmp/claude-dxu/md5/B/probe.jl`, the `L1` lines: `s_positions`,
`total_length`, `survey`, `knob_report`, `TrackingTask` construction and `execute!` over a line holding a hook
placement, and `execute!(TrackingTask(BeamLine("KM", d, ip, qf)))` for a marker placement in a TrackingTask line.
Root response: refuted by reading and measurement -- clean. Every walker that can meet a `LineEntry` wrapping a
non-element child was enumerated (the Clean regions list below names each with its line and its treatment); the
probe over a line holding a hook placement that even carries overrides ran `s_positions`, `survey`, `knob_report`,
`TrackingTask` construction (contracts, analyses, stream warners) and `_runtime_entries` without error
(probe_unfixed.log, probe2_unfixed.log: `L1` lines, all `ACCEPTED`; the one refusal is `MomentObserver` demanding an
artifact at `execute!`, unrelated). One neighbour observed, pre-existing and identical on BOTH spellings, so not a
wrapping defect: a `StrongStrongCollision` in a `TrackingTask` line dies at the first turn with the raw
`MethodError: objects of type StrongStrongCollision{Nothing} are not callable` (probe2 `L1`, the placement spelling
`BeamLine("KM", d, ip, qf)` and the tuple `(d, ip, qf)` alike): `_runtime_or_existing(element) = element`
(Tasks.jl:2012) pushes the marker as a physics entry. Ledgered as B-1b [Minor]: a by-name refusal
(`_runtime_or_existing(::StrongStrongCollision)` in interface.jl, after the type exists in the include order, naming
`StrongStrongTask` as the remedy) plus a test; about five lines; not fixed here since the tuple route had it before
the campaign and the brief limits fixes to the campaign's blast radius.

### LEAD B-2 [Moderate, confidence high] src/elements/beam_line.jl:76-85; src/lattice/toml.jl:945-953, 1018-1033
Claim: `entry.k = v` on a placement whose spec is a hook or a marker is stored, bumps the spec epoch, is never read
by any compile, and survives the snapshot round trip; the derived route (`with_overrides`, unit A) refuses it.
Mechanism: `setproperty!(::LineEntry, ...)` runs `_reject_folded_override` and `_reject_line_placement_override`,
both of which return for a spec that is not an `ElementSpec`, then stores and bumps `_SPEC_EPOCH`. The compile walk
(`_append_runtime_line!(out, entry::LineEntry, ...)`, Tasks.jl:2525) routes a non-element placement to the bare
spec, dropping the overrides; `_append_strong_strong_line!(…, entry::LineEntry, …)` cuts at `getfield(entry, :spec)`
(interface.jl:3937). The codec writer prints the overrides of ANY member (toml.jl:945, `meta = nothing` for a
non-element, no key check) and the reader rebuilds them (toml.jl:1018, `ometa = nothing`).
Repro: probe `L2` lines: `line[2].name = "x"` on a `ScheduledObserver` placement prints `ACCEPTED`, overrides
`Dict(:name => "x")`, epoch bump 1; a `schedule = EveryNSteps(step=7)` override compiles the spec's
`EveryNSteps(step=2)`; `machine_toml` prints `overrides = { ... }` on the hook member and `parse_machine` reads it back.
Root response: confirmed and fixed in the batch -- Moderate. Measured on the unfixed tree (probe_unfixed.log `L2`):
`line[2].name = "x"` on a `ScheduledObserver` placement -> `ACCEPTED`, overrides `Dict(:name => "x")`, spec epoch
bumped by 1; `line[4].label = :zzz` on a `StrongStrongCollision` placement -> `ACCEPTED`; a `schedule =
EveryNSteps(step=7)` override on the observer placement compiled the SPEC's schedule (`EveryNSteps(0, typemax, 2)`
on both the clean and the overridden line: stored, never read); `machine_toml` printed the member as
`{ ref = "SCHEDULEDOBSERVER", path = "K/SCHEDULEDOBSERVER", overrides = { name = "x", schedule = { type =
"EveryNSteps", ... step = 7 ... } } }` and `parse_machine` rebuilt the overrides; a `label` override on a marker
placement built a `StrongStrongTask` on the spec's label. Fix (one finding, three routes agreeing with unit A's
derived route): `_reject_hook_placement_override(spec, name)` in beam_line.jl's guard family, called first by
`setproperty!(::LineEntry, ...)` -- refuses by name (`\`name\` cannot be overridden on this placement: its spec is
a ScheduledObserver, an in-line hook or a collision marker, which has no parameters for a placement override to
land on ... Configure the object at its construction (...) and rebuild the line with it.`), stores nothing, leaves the
epoch alone; `_toml_line_table` refuses a hand-built hook or marker member carrying overrides (`... carries 1
placement override(s) (name) that no compile reads; setproperty!(::LineEntry, ...) refuses them, so this entry was
built by hand ...`); `_toml_decode_line` refuses `overrides` on a non-element member (`member "SCHEDULEDOBSERVER"
places a ScheduledObserver (a hook or a marker, not an element) ... Drop \`overrides\` from this member ...`).
Blast radius measured first (Lesson 2): every override writer in the suite, the examples and the harnesses
(`grep "line_entries(.*)\[.*\]\.\w+ *="`, `.overrides[`, direct `LineEntry(` constructions: test/runtests.jl
9459, 9464, 18530, 31237, 20277, 22820, 31317; examples/knob_control.jl:114) writes on element specs or on a line
placement; none on a hook or marker; no doc promises one (grep over docs/design/machine_description.md,
docs/theory/beam_line_composition.md, docs/public_api.md). Regression test "Machine description audit: a placement
override on a hook or marker placement is refused by name on every route": RED on the unfixed tree
(red_run.log: `ACCEPTED` where the refusal is asserted, overrides stored, epoch 2 against 0), GREEN after
(green_run.log). Merge note for the fold: unit A's `_overrides_check_key` can call `_reject_hook_placement_override`
rather than carry a copy of the test.

### LEAD B-3 [Minor, confidence med] src/elements/beam_line.jl:203-205, src/tasks/Tasks.jl:2062-2078
Claim: a knob referenced only through a placement OVERRIDE makes the task knob-dependent and recompiles at retune, so
the tracked coordinates follow the knob.
Mechanism: `_has_knob_parameters(entry::LineEntry)` ORs the spec's knobs with `any(_param_has_knob,
values(overrides))`; `_runtime_entries` caches `(entries, knob_dependent, kepoch, sepoch, record)` and recompiles when
`knob_dependent && kepoch != knob_epoch()`; `compile_runtime(::LineEntry)` merges overrides BEFORE `resolve_knobs`.
Repro: probe `L3`: `ring[1].x_offset = @knob_expr(md5b_ov.dx)`, track 3 turns, `md5b_ov.dx = 1e-3`, track an
identically built beam: `x1 != x2`, and the retuned run equals a task built fresh after the retune.
Root response: refuted by measurement -- clean. probe_unfixed.log `L3`: `_has_knob_parameters(elements) = true` for the
override-only knob; after `md5b_ov.dx = 1e-3` the identically built beam tracks differently (`x1 != x2`,
max |dx| = 1.2350627114862866e-3), the retuned run equals a task built fresh after the retune (`true`), and setting
the knob back to 0 reproduces the first run bitwise (`true`). The property (override knob -> knob-dependent ->
recompile at the epoch) holds on the `TrackingTask` cache gate; the strong-strong gate (interface.jl:3816-3834) reads
the same `_has_knob_parameters(line)` over the same placement tuple. Left as measured, no new pin: the wiring/epoch
agreement for override knobs is pinned by the F-130 testset (test/runtests.jl:31396) and T1 (23707).

### LEAD B-4 [Minor, confidence high] src/tasks/Tasks.jl:287, 1023, 1029, 2249; src/tasks/strongstrong/interface.jl:2643
Claim: a caller of `_element_tuple` (or of a consumer a machine can reach) bypasses the one-lattice door
(`_machine_only_lattice`).
Mechanism: six call sites of `_element_tuple`; `_collect_contracts`/`_collect_analyses` are the constructor's keyword
defaults and run on the RAW `elements` before the body; `_linearizable`, `_describe_map`, `_source_kind` have their own
`Machine` methods; `analyze(analysis, map)` goes through `one_turn_matrix(map)`.
Repro: probe `L4`: `TrackingTask(mach)`, `_collect_contracts(mach)`, `one_turn_matrix(mach)` on a two-lattice machine
each refuse naming the machine, its lattices and the remedy; `one_turn_matrix` of a one-lattice machine returns.
Root response: refuted by reading and measurement -- clean. All six `_element_tuple` call sites dispatch on the
argument; `_collect_contracts(mach)` (the keyword default, run on the raw argument before the body) refuses with the
same door message as `TrackingTask(mach)` (probe2 `L4`: `Machine("md5b_KM"): TrackingTask (one line; analyze and
one_turn_matrix likewise) takes one line, but the machine holds 2 lattices ("md5b_KA", "md5b_KB"). Name the lattice
meant: machine[:md5b_KA] ... or pair two of them with StrongStrongTask(machine, :md5b_KA, :md5b_KB)`);
`one_turn_matrix(mach)` refuses through `_linearizable(::Machine)` naming `one_turn_matrix`; `one_turn_matrix` of a
one-lattice machine returns (`ACCEPTED`). `_task_machine` runs after the door (Tasks.jl:306 after 287).

### LEAD B-5 [Minor, confidence high] src/tasks/strongstrong/interface.jl:2620, 2742, 2746
Claim: an unknown keyword on `StrongStrongTask(line1, line2; ...)` and on both machine forms raises a `MethodError`
naming the private builder `_strong_strong_task`, not the constructor the caller wrote.
Mechanism: the three public forms forward `kwargs...` to `_strong_strong_task`, whose method is the one that fails
to match; Julia's message names the callee.
Repro: probe `L5`: `StrongStrongTask((ip, l6a), (ip, l6b); md5b_bogus=1)` and the three other forms; the message's
first line.
Root response: confirmed and fixed in the batch -- Minor. Measured (probe_unfixed.log `L5`): all four public forms --
the tuple line form, two lattices, `StrongStrongTask(machine, :A, :B)` and `StrongStrongTask(machine)` -- raise
`MethodError: no method matching _strong_strong_task(::Tuple{...}, ::Tuple{...}, ::Nothing; md5b_bogus::Int64)`
(resp. `(::Lattice, ::Lattice, ::Machine; ...)`), while `TrackingTask((qf, d); md5b_bogus=1)` names
`TrackingTask`. Fix: `_strong_strong_refuse_unknown_keywords(kwargs)` as the first statement of the three public
forms, refusing `StrongStrongTask: unknown keyword \`md5b_bogus\`; the keywords are policy, seed,
default_poisson_solver, poisson_solver, luminosity_path, luminosity_append, luminosity, artifact, diagnostics,
record_turn_times`; the roster `_STRONG_STRONG_KEYWORDS` is read from the builder's method
(`Base.kwarg_decl(only(methods(_strong_strong_task)))`, measured to give exactly those ten names), never
hand-copied; the retired keywords stay in it and keep their own precise refusals (the test's `seed=1` arm).
Blast radius: no test asserts a `MethodError` on a `StrongStrongTask` keyword (grep "MethodError.*StrongStrongTask",
"unsupported keyword"). Regression test "Machine description audit: StrongStrongTask refuses an unknown keyword by
its own name on the line and machine forms": RED on the unfixed tree (red_run.log: 8 failed, 1 errored on the absent
roster), GREEN after (green_run.log).

### LEAD B-6 [Minor, confidence med] src/lattice/toml.jl:556, 758-763; src/lattice/toml_hooks.jl:653
Claim: the codec's value seams disagree somewhere: `rng_id` read back as `Int` where it was `UInt64`; a `Float32`
scalar in a nested object not re-narrowed; a `Dict` parameter; `Symbol` keys printed bare by one side and coerced by
the other on different evidence; `_TOML_OBJECT_TYPES` registered at include time with a tripwire that would not notice
a type defined later.
Mechanism: see the sub-items in the Root response (each verified against the function named).
Repro: probe `L6` lines (the stored and reloaded `rng_id` of a `LumpedRadSpec`, the held/unheld state of a fresh id
after decode, the registered methods and enums, the Dict sweep over `ELEMENT_META_BY_KIND`).
Root response: one confirmed sub-finding (B-6a, Minor, ledgered with its price), one tripwire added (B-6e), the rest
clean by reading and measurement.
- B-6a `rng_id` and the claim on decode. A `LumpedRadSpec` built with `rng_id = 0x4d444260` stores a `UInt64`, prints
  `rng_id = 1296319072`, reads back as `Int` 1296319072 (`isequal` true, the machine `==` its reload) because the
  kind's `ParamMeta` default is the `Int` 0 (radiation.jl:480, linear6d.jl:597) and `_toml_decode_value` reads an
  integer by the default's type (toml.jl:556); every consumer converts (radiation.jl:224 `UInt64(...)`, Tasks.jl:495,
  particle_tunes.jl:227/231), and the reloaded spec compiles and tracks (probe `L6`). CONFIRMED, however, that the
  reader does not re-claim an element spec's explicit stream id in the reading process: a text edited to a fresh id
  (1000001, unheld) decodes and the id stays unheld (`_rng_id_held == false`), since the flexible form
  `ElementSpec{Kind}(params)` (Knowledge.jl:59-68) has no per-kind hook and the claim lives in the friendly constructor
  (radiation.jl:97); the rule and BPM constructors the hook decoders call DO claim (turn_modulated.jl:198,
  BPMObserver.jl:168), which is the stage-4 record's "decoding re-claims" statement -- true for hooks and rules, not
  for `:lumped_radiation` and `:linear6d` specs. Consequence: a reloaded radiation or tune spec's stream can coincide
  silently with an id the reading process issued or will issue (an auto-assigned id is as small as 2 in a fresh
  process, probe `L6`). Price: a per-kind consumer class the reader can pass to `claim_rng_id!` (a `rng_consumer`
  beside the kind's `rng_id` `ParamMeta`, or a table derived from the friendly constructors' call sites, never
  hand-copied) and one call in `_toml_decode_element`; a test that a reloaded explicit id is held and that a reload
  onto an id another class holds warns. Not fixed here: the class label is a metadata decision.
- B-6b Float32 scalars: `_toml_decode_value` re-narrows floats by `ctx.numeric_type` (toml.jl:561), the element reader
  rebinds the context to the element's own `numeric_type` first (833-842), the rule decoders narrow their `sigma` the
  same way (toml_hooks.jl:645-666; the suite's `WhiteNoise(1f-3)` arm at 21766), and a nested spec value goes through
  `_toml_element_table`/`_toml_decode_element` with the same context. Clean by reading.
- B-6c Dict parameters: both directions exist (toml.jl:530-538 writes sorted string keys; 612-614 rebuilds `Symbol`
  keys only when the hint's default is a `Dict{Symbol}`); no kind's example holds one (probe2: 0 of 32 kinds), so
  the path is unexercised; the per-kind round trip (21422) would exercise it the day a kind's example holds one, so no
  separate tripwire was added (it would follow from that test).
- B-6d Symbol keys: one function on both sides (`_toml_element_hint`, toml.jl:775, passed by the writer at 810/949/967
  and the reader at 842/993/1032; `_toml_hint_holds(hint, Symbol)` at 495 and 565). Clean by reading.
- B-6e registration: toml.jl registers tracking methods and enums by `subtypes` at its include time (758-763); the
  stage-4 tripwire's roster (21649) derives neither (an `Enum` fails its `isstructtype` arm). Today complete: 6 methods
  and 1 enum registered of 31 object types (probe2 `L6`); a later one would be refused loudly at write (toml.jl:544,
  695). Made permanent by the new derived testset "Machine description audit: every tracking method and enum of the
  module is a registered snapshot object type", injection-verified in the test itself.

### LEAD B-7 [Minor, confidence high] src/lattice/Lattice.jl:214-260; src/tasks/strongstrong/interface.jl:2718-2727
Claim: `_lattice_knob_roots` now refuses nested and duplicate roots and some caller still constructs a nested or
duplicated root tuple (the derived two-lattice machine's shared roots).
Mechanism: callers are `Lattice` (Lattice.jl:192), `Machine` (Machine.jl:90) and the recursion (Lattice.jl:244);
`_strong_strong_machine` returns `nothing` on any dotted-prefix overlap BEFORE deriving `shared`, a subset of the
first lattice's already-validated roots.
Repro: probe `L7`: lattices rooted `md5b_a` and `md5b_a.x`: `_strong_strong_machine` and `StrongStrongTask(..).machine`
are `nothing`; `Machine(...)` refuses by name; two lattices declaring `(md5b_a, md5b_b)` in either order share both.
Root response: refuted by measurement -- clean. probe_unfixed.log `L7`: lattices rooted `md5b_a` and `md5b_a.x` give
`_strong_strong_machine == nothing` and `StrongStrongTask(l7a, l7b).machine == nothing` (the stage-4 silent-nothing
design), `Machine("md5b_M7"; lattices=(l7a, l7b))` refuses: `knob roots md5b_a (declared by lattice "md5b_R7A") and
md5b_a.x (declared by lattice "md5b_R7B") overlap ... (knob_root = :md5b_a)`; two lattices declaring `(md5b_a, md5b_b)`
in either order derive the shared roots `(:md5b_a, :md5b_b)`. No caller constructs a nested or duplicated root tuple:
`shared` is a subset of the first lattice's validated roots, computed only after the overlap pre-check; the TOML
reader passes its roots through the constructors. No test probed the old acceptance.

### LEAD B-8 [Minor, confidence high] src/math/counter_rng.jl:254-262 (the policy), test/runtests.jl (the ids)
Claim: two explicit stream ids claimed by the suite's machine-description testsets collide silently.
Mechanism: `claim_rng_id!` warns for an explicit id auto-assigned earlier and for one claimed by a DIFFERENT class;
same-class explicit reuse is silent by the owner's 2026-10-16 decision (the reproducibility handle).
Repro: `grep -n "rng_id" test/runtests.jl` over the machine-description blocks (lines 20340-22190, 25186-25470,
43478-43900 of the stage-4 tree) and `grep -n "4101\|4111\|4112\|4113\|4121\|4122\|0x4d4442" test/runtests.jl`.
Root response: refuted by reading -- clean. The ids are listed in the Clean regions; no id is claimed by two consumer
classes within the machine-description blocks; 4113 is shared by design under `@test_logs`; the one cross-block
reuse (4112: a Float32 `Beam` at 15119 and the Float64 beam at 21180) is same-class, silent by the owner's recorded
policy (counter_rng.jl:254-257, "the user's reproducibility handle"), and the two beams never meet in one task.
An auto-assigned id cannot land on a claimed one (`next_rng_id!` skips claims), and a claim of an issued one warns
even when the class window has moved on; nothing silent remains in this class.

### LEAD B-9 [Moderate, confidence high] src/elements/beam_line.jl:76-85 (unit A's lead (a))
Claim: `entry.name = "x"` on a `ScheduledObserver` placement is stored and `compile_runtime(entry)` then dies at
`kind(spec)` once `overrides` is non-empty; the stage-3 wording "a marker has no parameters" is wrong for the element
kind `:marker`.
Mechanism: the same mechanism as B-2 (the guards return for a non-`ElementSpec` spec); `compile_runtime(::LineEntry)`
builds `ElementSpec{kind(spec)}(merged)` when overrides exist (beam_line.jl:235), and `kind(::ScheduledObserver)` has no
method. The task compile never reaches it (the compile walk unwraps a non-element placement first), a direct
`compile_runtime(entry)` does.
Repro: probe_unfixed.log `L2` (the stored override); on the unfixed tree `compile_runtime(line[2])` after
`line[2].name = "x"` raises `MethodError: no method matching kind(::ScheduledObserver{...})`.
Root response: the same finding as B-2, fixed there: `_reject_hook_placement_override` refuses the key on any
placement whose spec is not an `AbstractElementSpec` -- an in-line hook or the COLLISION marker
(`StrongStrongCollision <: AbstractOctopusObject`, interface.jl:2440) -- so the `kind` call is unreachable from the
in-place route. The element kind `:marker` (`ElementSpec{:marker}`, thin_elements.jl:274-347) is an element with
declared keys (`name`, the placement keys) and keeps taking overrides; the new messages say "an in-line hook or a
collision marker", never "marker" alone, and unit A's `_overrides_check_key` can call the same guard at the fold.

### LEAD B-10 [Moderate, confidence high] src/elements/beam_line.jl:76-85; src/lattice/toml.jl:945-953 (unit A's lead (b))
Claim: an undeclared override key (`entry.bogus = 1`) is stored by the placement route, read by nothing, written by the
TOML writer and refused by the reader: a snapshot that cannot be read back; the spec route refuses the key by name.
Mechanism: `setproperty!(::ElementSpec, ...)` (Knowledge.jl:160-186) refuses a key that is neither declared by the
kind, nor a placement key, nor already stored; `setproperty!(::LineEntry, ...)` ran only the folded and line guards;
`_toml_line_table` encoded every override with `hint = nothing` for an undeclared key while `_toml_decode_line`
checks `_toml_declared_keys(ometa)` (toml.jl:1028-1030).
Repro: probe3.log / probe4.log `b` lines: spec route `ArgumentError: element kind :quadrupole has no parameter bogus;
valid parameters: ...`; placement route `ACCEPTED`, `overrides = Dict(:bogus => 1)`; `_effective_spec`,
`TrackingTask` and `compile_runtime` each warn "unknown parameter(s) stored as descriptive metadata only"; the writer
prints `{ ref = "QF", path = "U/QF", overrides = { bogus = 1 } }`; `parse_machine` refuses `at
lattices.U.lines.U.members[1].overrides.bogus: unknown override key "bogus" for the kind :quadrupole`.
Root response: confirmed and fixed in the batch -- Moderate ("a refusal present on one route and absent on its twin",
and an unreadable snapshot). `_reject_undeclared_override` joins the guard family, LAST in `setproperty!` so the
older guards keep their messages: it mirrors the spec route's condition exactly (declared parameter, `_PLACEMENT_PARAM_KEYS`,
a key the spec already stores through `set_param!`; a kind without metadata keeps the acceptance) and names the kind,
the key, the valid parameters and the remedy; `_toml_line_table` refuses an undeclared override key by name before
encoding it (`the placement override bogus is not declared by the kind :quadrupole (its declared keys are ...); the
reader would refuse it`), the twin of the element table's stored-key rule. Blast radius (Lesson 2): every override
writer in the suite, examples and harnesses listed under B-2 writes a declared or a placement key, except ONE: the
reflection test "Nested lines have length, reflection keeps state, folded sugar is rejected everywhere" wrote
`ri[1].k1 = 9.9` on the reversed line's DRIFT placement as its write-isolation probe (`k1` is undeclared on a drift);
the probe now writes `x_offset`, a placement key, and asserts the same no-write-through property (test/runtests.jl, the
three lines after `ri, ci = line_entries(rev), line_entries(cryo)`). Regression test "Machine description audit: an
undeclared placement override key is refused by name where the spec route refuses it and is never written": RED on
the tree without this fix (red_run2.log: 4 failed of 8 -- the key stored, the writer printing it), GREEN after
(green_run2.log); the reader's refusal and the spec route's message are its anti-vacuity arms.

### LEAD B-11 [Minor, confidence med] src/lattice/Lattice.jl:_lattice_check_params_eltype (the early return) (unit A's lead (c))
Claim: a `BigFloat` override on a TYPED element (`numeric_type = Float64` stored) passes `Lattice(...)` and is caught, or
not, only at compile.
Mechanism: `_lattice_check_params_eltype` returns when `stored === T` without looking at the merged values; the
compile reads the stored `numeric_type` and converts.
Repro: probe4.log `c`: `QuadrupoleSpec(; numeric_type=Float64, L=0.3, k1=1.2)`, `lt[1].L = big"0.30000000000000000001"`:
`Lattice("T"; line=lt)` -> `ACCEPTED`; `compile_runtime(lt[1])` -> `LatticeMagnet{Symplectic6DMap, Float64, ...}` with
`L = 0.3` (the override narrowed to Float64, silently); `numeric_type(merged) == Float64`. The untyped twin is refused
by the lattice (`C/QF (quadrupole) compiles in BigFloat`, probe3 `c`), as the suite pins at 20649.
Root response: Unconfirmed as a defect, code left unchanged, carried as an owner question. The measured behaviour is
the convention the suite PINS for typed elements ("on a TYPED element the stored type wins ... the compile converts
the override to the element's type", test/runtests.jl 20655-20660: a Float64 literal on a `DriftSpec{Float32}`
compiles to `0.7f0`, probe4 `c`), and a BigFloat-to-Float64 conversion is the same narrowing as that pinned
Float64-to-Float32 one; the lattice's contract (every element compiles in `T`) holds. The competing reading: the
typed constructors refuse a wider-than-`T` TABLE rather than convert it (`rf_cavity.jl`'s construction help), so a
wider-than-`Float64` scalar override on a typed element could be refused at the lattice too. What would decide it:
the owner's rule for typed elements' overrides (convert, as pinned, or refuse what is wider than the floor). Price if
refused: `_lattice_check_entry_eltype` passes `getfield(entry, :overrides)` to a second check (`P =
_lattice_params_numeric_type(overrides)`; refuse when `P !== Float64 && P !== T`), about six lines, plus the pinned
test's wording and a red-first test.

### LEAD B-12 [Minor, confidence high] test/runtests.jl:32357 ("Every exported API name appears in the registry snapshot") (unit A's lead (d))
Claim: the testset passed on unit A's tree although docs/registry_snapshot.md did not contain `with_overrides`.
Mechanism: the testset reads `registry_snapshot_markdown()`, the GENERATED text, and checks every `names(Octopus)`
entry appears in it (plus an injection arm deleting `TuneFunction`); it never opens the committed file, so a stale
file cannot fail it. "Architecture integrity" compares `registry_snapshot_markdown() == read(snapshot_path, String)`
(runtests.jl[Architecture integrity]:28) and is the staleness tripwire.
Repro: green_run.log: "Architecture integrity" 49 passed, 1 failed on that comparison; probe5.log: the generated
and committed snapshots differ in exactly 2 of 481 lines, both the `with_overrides` entry of the Exported API list
(generated has it, committed does not); nothing of unit B's appears (its names are private).
Root response: by design, reported, not changed: the exported-API testset asserts the generator's completeness, the
integrity testset the file's freshness; the failure on this tree is the skeleton's `with_overrides` export, regenerated
by the orchestrator at the fold (ground rule 5).

## Clean regions, with the evidence that makes "clean" checkable

- Every walker that can meet a `LineEntry` wrapping a non-element child, enumerated by
  `grep -rn "LineEntry" src/ | grep -v beam_line.jl` plus the `getfield(entry, :spec)` sites, with how each treats it:
  `_append_runtime_line!` (Tasks.jl:2525) routes the bare spec to the hook path; `_append_strong_strong_line!`
  (interface.jl:3937) cuts at a marker spec, else the compile walk; `_effective_spec` (Tasks.jl:450) returns the raw
  spec for a non-`ElementSpec`, which `_collect_radiation_ids!` (485), `_collect_aperture_specs!` (796),
  `_collect_declared!` (1035) and `_each_turn_rule_spec` (turn_modulated.jl:1744) fall through on their `element`
  fallbacks; `_collect_spec_s!` (Tasks.jl:864-889) forwards a hook placement to the hook arm (F-75) and advances
  nothing; `_collect_whole_line_hooks!` (Tasks.jl:998) reads the spec and tests the compile walk's own
  `_line_entry_or_nothing`; `_validate_reference_chain` (2464) sees cavity events only; `_knob_binding_sites!`
  (beam_line.jl:1027) and `_lattice_check_entry_eltype` (Lattice.jl:346) step over a non-element spec;
  `_lattice_structurally_equal` (Lattice.jl:497) compares the spec, path, tags and overrides generically;
  `_floor_step`/`_survey_walk!`/`_girder_flat_entries!` (floor_plan.jl:66, 154, 203) give a hook no geometry and
  drop it; `_toml_line_table`/`_toml_decode_line` (toml.jl:933, 1036) write and rebuild the member by its id.
  `src/contracts/`, `src/tasks/RunArtifact.jl`, `src/tasks/BeamObservers.jl`, `src/tasks/BPMObserver.jl`: no
  `LineEntry` dispatch and no walk over `task.elements` by bare type (grep "task\.elements|isa ElementSpec"; one hit,
  Contracts.jl:4366, reads a kind's example spec). A `PhaseSpaceReset`/`ParticleLinear6D` child (an
  `AbstractTrackOp`) wrapped by a `BeamLine` reaches the compile walk's fallback as the bare object exactly as the
  tuple spelling does (`_runtime_or_existing(element) = element`, Tasks.jl:2012).
- `_element_tuple`'s six call sites (Tasks.jl:287, 1023, 1029, 2249; interface.jl:2643-2644) all dispatch on the
  argument, so a `Machine` meets `_element_tuple(::Machine)` -> `_machine_only_lattice` at each; the one-turn-matrix
  helpers (`_linearizable`, `_describe_map`, `_source_kind`, one_turn_matrix.jl:193-212) have their own `Lattice`
  and `Machine` methods through the same door; `analyze(analysis, map)` (twiss_dispersion_analysis.jl:1800) is
  `one_turn_matrix(map)`. `_task_machine` (Tasks.jl:950-952) runs after `_element_tuple` in the constructor
  (line 306 after 287), so its `Machine` method never sees a machine the door refused.
- `_lattice_knob_roots`: three callers (Lattice.jl:192, 244; Machine.jl:90); the TOML reader passes its roots
  through `Lattice(...)`/`Machine(...)` (toml.jl:289, 1405); no test probes the old nested acceptance
  (grep "knob_root *= *(" test/runtests.jl: 20493 pins the refusal of `(:ring, "ring.arc")`).
- The codec's Symbol seam: writer `_toml_encode_value` (toml.jl:495) and reader `_toml_decode_value` (565) both
  decide by `_toml_hint_holds(hint, Symbol)` on the hint `_toml_element_hint(meta, key)` (775), which both the
  element table (810/842), the line's own parameters (967/993) and the member overrides (949/1032) pass; the
  option codec (toml_hooks.jl:63, 124) decides by the schema's `option_type`, and no schema declares a
  `Symbol`/`String` union or `Any` (grep over src/). `NamedTuple` values are refused at write (toml.jl:506).
- The explicit stream ids of the machine-description testsets (by block): 4101 beam (21073); 4111, 4112 beams
  (21180); 4113 lumped_radiation, shared on purpose across both lattices under `@test_logs` (21236); 0x4d444201
  bpm_observer, 0x4d444202 WhiteNoise, 0x4d444203 PinkNoise (21703-21709); 0x4d444210 lumped_radiation (21837);
  0x4d444221, 0x4d444222 beams (21934); 4121, 4122 beams (22078). No id is claimed by two classes. 4112 is also a
  `Beam`'s at 15119 (another block): same class, silent by the recorded policy (counter_rng.jl:254-257), and the
  two never meet in one task.

## Not checked, and why

- The 410 bytes per `execute!` of placement-spelled lines: unit C's lead by the brief.
- `src/tasks/RunArtifact.jl`, `BeamObservers.jl`, `BPMObserver.jl`, the solvers' schedule equality and the reference
  readers (`Beam.jl`, `rf_cavity.jl`): unit C's region; grepped only for `LineEntry` dispatch (none) under lead 1.
- `src/lattice/overrides.jl` (`with_overrides`, `_overrides_check_key`): unit A's file, read for its docstring's
  refusal wording only; its stubs were not executed. The derived route's agreement with the in-place guard is asserted
  by unit A's tests, not here.
- CUDA: no kernel-reachable code changed (three refusals and a keyword check at construction); no GPU run.
- The stage records' committed baseline harnesses (result/gates/md3, md4 compare scripts) were not re-run by this
  unit: `result/` exists in the main checkout only, the fixes add refusals and change no numeric path, and the
  stage-3/4 compiled-runtime pins ("StrongStrongTask takes a machine and compiles the runtime the tuple spelling
  compiles", "the strong-strong example's machine round-trips and the reloaded task compiles the tuple spelling's
  runtime") ran green extracted on the fixed tree as the behavioural fingerprint of this region.
- `Base.kwarg_decl` is `Base`-internal (base/methodshow.jl:80 in 1.12.4, present since 1.0); a Julia upgrade that
  renames it fails `const _STRONG_STRONG_KEYWORDS` at include time, loudly. Not a check, a dependency to know.
- A `Dict`-valued element parameter through the codec: no kind holds one (probe2: 0 of 32), so the path ran in no
  test of this unit.


## Test report

Lane: extracted blocks in package mode (`test/run_extracted_testsets.jl`, 4 threads), never the gate. RAN green on the
fixed tree (green_run2.log, green_nested.log): the 4 unit testsets (34 assertions), 27 neighbours (listed in command 10),
the 3 sweeps. Regression tests shown red first: red_run.log (B-2, B-5), red_run2.log (B-10). Skipped or not run: the
full gate (orchestrator), CUDA (nothing kernel-reachable changed), "Architecture integrity" (fails on the skeleton's
`with_overrides` export, attributed by probe5), "Particle tunes: fixed-label symplecticity ..." (runner limit, left
to the gate).

## Commands run (all from the md5-B worktree; logs beside this report's sources under /tmp/claude-dxu/md5/B/)

Reading phase (before the gate flag): `wc -l` of the region's files; the greps named in each LEAD (dispatch sites,
`_element_tuple` callers, epoch readers, `rng_id`, `_TOML_OBJECT_TYPES`, `_lattice_knob_roots`, override writers in
test/, examples/, validation/, test/examples/, `LineEntry` walkers across src/, Symbol/String option types, `@enum`
and tracking-method definitions against the include order, `kwarg_decl` in the installed Julia's base).

1. `julia --project=WT --startup-file=no --threads=4 probe.jl` (unfixed tree) -> probe_unfixed.log: L2 confirmed
   (`ACCEPTED`, overrides stored, epoch +1, spec schedule compiled, writer/reader round trip), L3 refuted (retune moves
   x by 1.235e-3, equals a fresh task), L5 confirmed (four forms name `_strong_strong_task`; `kwarg_decl` = 10 names),
   L7 clean, L6: `UInt64` stored -> `Int` reloaded, `isequal` true, fresh id unheld after decode. Died at `subtypes`
   (script mode needs InteractiveUtils) -> probe2.jl.
2. `... probe2.jl` -> probe2_unfixed.log: 6 methods + 1 enum registered of 31 object types; 0 of 32 kinds with a Dict
   example; L1 walkers `ACCEPTED`; marker in a TrackingTask line: raw `MethodError ... not callable` on both
   spellings; L4 doors refuse by name, one-lattice `one_turn_matrix` returns.
3. `julia --project=WT --threads=4 WT/test/run_extracted_testsets.jl <3 titles>` (src unfixed) -> red_run.log:
   block 1 FAILED (the refusal absent: `ACCEPTED`, overrides stored, epoch 2 vs 0, writer and reader accepting),
   block 2 FAILED (8 failed, 1 errored: `MethodError ... _strong_strong_task`, roster undefined), block 3 passed
   (the tripwire); exit 1.
4. `bash fix/apply_fixes.sh` (B-2, B-5: beam_line.jl, toml.jl, interface.jl).
5. `... run_extracted_testsets.jl <3 unit titles + 20 neighbours + 4 sweeps>` -> green_run.log: 3 unit blocks pass
   (11, 12, 3), 20 neighbours pass, "Every export is documented" 1/1, "No docstring is detached by comment lines" 11/11,
   "No method grows a Core.Box outside the argued allowlist" 5/5; "Architecture integrity" 49/50 (the snapshot file
   comparison), "Particle tunes: fixed-label symplecticity ..." 1 errored (`pt_probe_optics` undefined: the runner's
   documented limit).
6. `... probe3.jl`, `... probe4.jl` -> probe3.log, probe4.log: lead (b) confirmed on all four routes; lead (c)
   measured (typed element narrows the BigFloat override to `L = 0.3`; the untyped twin refused by the lattice;
   `DriftSpec{Float32}` + `0.7` -> `0.7f0`).
7. `... probe5.jl` -> probe5.log: generated vs committed snapshot differ in 2 of 481 lines, both `with_overrides`.
8. `... run_extracted_testsets.jl "<B-10 title>"` (B-10 unfixed) -> red_run2.log: 4 failed of 8 (the key stored,
   the writer printing it), exit 1.
9. `bash fix/apply_fixes2.sh` (B-10: beam_line.jl, toml.jl, and the one incidental test edit at the reflection probe).
10. `... run_extracted_testsets.jl <4 unit titles + 27 neighbours + 3 sweeps>` -> green_run2.log: 4 unit blocks pass
    (11, 12, 3, 8); 26 neighbours pass (per-block counts in the log; the codec blocks 47/226/91/87/18/38/20, the task
    blocks 11/19/15, the guard blocks 43/18/12/36/13/57/9, the lattice blocks 13/29/24/35, the macro blocks 42/26);
    the three sweeps pass (1/1, 11/11, 5/5); "Nested lines have length, reflection keeps state, folded sugar is
    rejected everywhere" 47 passed, 1 errored at its line 82 (`with_logger` undefined under the runner, the suite's
    file-level `using Logging`), the three edited lines among the 47.
11. `OCTOPUS_EXTRACT_PRELUDE=<using Logging> ... run_extracted_testsets.jl "Nested lines ..."` -> green_nested.log
    48 passed of 48, 0 failed blocks: the edited write-isolation probe is green with the suite's own prelude.
12. `git -C WT add -A && git -C WT commit -F commit_msg.txt` -> 37441bf on md5-B (4 files, +268 -5), working tree clean.

Not run: the full gate (the orchestrator's, on the merged tree); any CUDA run (no kernel-reachable change);
result/gates/md3, md4 baseline scripts (main checkout only; see "Not checked").
