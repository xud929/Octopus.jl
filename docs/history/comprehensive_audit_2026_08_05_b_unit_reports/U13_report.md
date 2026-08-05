# U13 — Knob engine, symbolic layer, weakdep extensions, and the `execute!` driver

Reading unit report. Repository `/cfs/ad/dxu/Library/Julia/Octopus`, **HEAD
`7de4d81`**. Prior pass over the knob half: `U14_report.md` at `7a8e9ca`;
prior declared full-audit commit `6a3f39ab`.

Julia 1.12.4. Every probe below was **executed**, not reasoned about; probe
sources are in the session scratch directory
`…/scratchpad/audit/` (`probe1…probe11`, `ext_check.jl`) and each lead's
`Repro` line is written to be reconstructible without them.

---

## 1. Region and provenance

| File | Lines | Read | Provenance |
|---|---|---|---|
| `src/knobs/Knobs.jl` | 995 | all | direct, line by line |
| `src/knobs/symbolic.jl` | 335 | all | direct, line by line |
| `src/tasks/Tasks.jl` | 906 | all | direct, line by line |
| `ext/OctopusForwardDiffRules.jl` | 32 | all | direct |
| `ext/OctopusSymbolicsExt.jl` | 19 | all | direct |
| `ext/OctopusForwardDiffExt.jl` | 15 | all | direct |

Diff read first, as briefed: `git diff 6a3f39ab HEAD -- src/knobs/
src/tasks/Tasks.jl ext/` (+274/−53; both ForwardDiff ext files are new in the
window; `Tasks.jl` gained `_warn_hidden_apertures` and
`_warn_duplicate_radiation_streams` and switched the aperture-`s` walk to
`_placement_length`).

Reference material read but **not** audited (other units own it):
`docs/knob_control.md` (all 250 lines), `examples/knob_control.jl` (all 159),
`src/elements/beam_line.jl` §§ LineEntry / `_has_knob_parameters` /
`_placement_length` / `compile_runtime(::LineEntry)`,
`src/tasks/BeamObservers.jl` §§ schedules, `prepare_*`/`finalize_*`,
`run_observers!`/`run_actions!`, `src/tasks/strongstrong/interface.jl:2396-2416`
(the second epoch gate), `src/elements/strong_beam.jl:755-775, 1010-1032`,
`src/Octopus.jl:107-121`, `test/runtests.jl` knob/BeamLine/aperture testsets.

Environments used:
- **package mode, weakdeps absent**: `--project=/cfs/ad/dxu/Library/Julia/Octopus`
- **package mode, weakdeps present**: a scratch env with `Octopus` dev'ed +
  `ForwardDiff` + `Symbolics` (both extensions precompiled cleanly)
- **script mode**: `include("src/Octopus.jl")` under both of the above, and
  once with `JULIA_LOAD_PATH="@:@stdlib"`.

---

## 2. Leads

### LEAD U13-1 [Medium, confidence high] src/knobs/Knobs.jl:394-418
Claim: `@knob p::T` on an existing knob whose converted value is `isequal` to
the old one changes the registry entry's declared type **and** the stored
value's Julia type without bumping the epoch, so every already-built task keeps
compiling its line at the old numeric type indefinitely.
Mechanism: the bare-declaration branch gates both `_invalidate_dependents_locked!`
and `_KNOB_EPOCH[] += 1` on `changed = !isequal(entry.value, v)`. `isequal`
compares *values across types*, so `Float64 1.7 → BigFloat`, `Float32 1.7f0 →
Float64`, and `2.0 → Int 2` all report "unchanged" while `entry.type` and
`typeof(entry.value)` do change. The knob's value type is exactly what
`numeric_type(resolve_knobs(spec))` promotes over (pinned by
`test/runtests.jl` "a knob is a machine control … that needs the knob to hold
the seeded type"), so a fresh `compile_runtime` now yields a *different element
type* while `_runtime_entries`' gate (`Tasks.jl:608`) sees no epoch motion.
Widening a knob's declared type is the documented way to seed an AD or
extended-precision sweep; doing it on a live task silently does nothing.
Repro: declare `@knob a::Real = 1.7`; build
`ElementSpec{:quadrupole}(; L=0.4, nst=4, kn=(0.0, @knob_expr(a)))` into a
`TrackingTask`; `execute!` once; record `knob_epoch()`; then `@knob a::BigFloat`.
Expect epoch **unchanged** (measured 2 → 2), `compile_runtime(spec)` now
`LatticeMagnet{Symplectic6DMap, BigFloat, …}` while the task's cached entry
stays `…, Float64, …`; over 12 turns the cached task and a freshly built task
differ by rel `2.7e-16`. Control: `@knob b::Float32` after `@knob b::Real = 0.1`
(value really changes) does bump (4 → 5).

### LEAD U13-2 [Major, confidence high] src/tasks/Tasks.jl:391-407
Claim: An exception raised inside `execute!`'s failure-path loss report
**replaces** the original tracking exception — `rethrow()` is never reached and
the real error is lost entirely.
Mechanism: the `catch` block runs `_task_loss_summary` → `_write_task_loss_log`
→ `_report_losses` *before* `rethrow()`. Any throw from those three (an
unwritable `loss_log` path, an HDF5 failure, or U13-5's knob-driven `:L`)
propagates out of the `catch` block, so the in-flight exception is discarded.
Repro: a task with `loss_log = joinpath(mktempdir(), "no_such_dir", "loss.h5")`
and a `ScheduledAction` whose `apply_action!` throws `error("REAL_TRACKING_ERROR")`.
Expect the surfaced error to be `HDF5.API.H5Error: Error creating file …` and
`occursin("REAL_TRACKING_ERROR", msg) == false` (measured).

### LEAD U13-3 [Major, confidence high] src/tasks/Tasks.jl:519-528
Claim: An exception from `finalize_observers!` (or `_finalize_line_observers!`)
replaces the in-flight tracking exception, so a broken observer finalizer hides
the physics error that actually stopped the run.
Mechanism: the nested `try … finally` at the end of `_execute_tracking_task!`
was written (part 7, T7) so that every finalizer runs and the *first finalizer
error* surfaces. Julia's `finally` semantics then make that finalizer error
replace whatever exception was propagating from the turn loop — the repository's
own "loud beats silent" rule is violated in the direction that matters most,
since the primary error is the one the user needs.
Repro: a task with `hooks = (BoomAction(), ScheduledObserver(obs))` where
`apply_action!(::BoomAction, …)` throws `"REAL_TRACKING_ERROR"` and
`finalize_observer!(obs)` throws `"FINALIZER_ERROR"`. Expect the surfaced error
to be `FINALIZER_ERROR` with `occursin("REAL_TRACKING_ERROR", msg) == false`
(measured), observer finalized once.

### LEAD U13-4 [Major, confidence high] src/knobs/Knobs.jl:895-918
Claim: The documented lossless round trip `knob_expression(string(e)) == e`
(`docs/knob_control.md:29-30`, and §3:166-169 "the round trip is **total**")
fails for **6 of the 50** binary×binary×operand-position nestings, and 4 of the
6 can change the evaluated **number** — including a finite value becoming `Inf`.
Mechanism: the 2026-08-05 U14-2 fix gave the extra precedence level to `^`'s
base and to the right operand of `-` and `/` only. The general rule is broader:
for a *left-associative* operator, any operand after the first that is itself an
operator of the **same precedence class** must be parenthesized, because
printing erases the tree's association and Julia's parser re-associates left
(and flattens `+`/`*` into n-ary calls). Missed cases: outer `+` with inner `+`
or `-` in position 2; outer `*` with inner `*` or `/` in position 2; and the
position-1 `(u+v)+w` / `(u*v)*w` flattening. Floating-point addition and
multiplication are not associative, so this is not cosmetic.
Repro: build the trees directly (`Octopus.KnobCall(:+, [KnobRef(:u),
KnobCall(:-, [KnobRef(:v), KnobRef(:w)])])`) or write `@knob_expr(u + (v - w))`,
then compare `knob_expression(string(e)) == e` and `knob_value` of both.
Measured, with `u,v,w` set as shown:

| tree | prints | tree-equal | value | reparsed value |
|---|---|---|---|---|
| `u + (v + w)` (1, 1e-16, 1e-16) | `u + v + w` | false | 1.0000000000000002 | 1.0 |
| `u + (v - w)` (1, 1e-16, 1e-16) | `u + v - w` | false | 1.0 | 0.9999999999999999 |
| `u * (v * w)` (1e300, 1e300, 1e-300) | `u * v * w` | false | 1.0e300 | **Inf** |
| `u * (v / w)` (1e300, 1e300, 1e300) | `u * v / w` | false | 1.0e300 | **Inf** |
| `(u + v) + w` | `u + v + w` | false | — | same value |
| `(u * v) * w` | `u * v * w` | false | — | same value |

A totalizing check over the whole grid (50 shapes) is the right tripwire here;
it is what found these.

### LEAD U13-5 [Medium, confidence high] src/tasks/Tasks.jl:429 (and 242)
Claim: A line whose `:L` is a knob expression makes every `execute!` that was
given a `loss_log` throw **after all tracking has completed**, destroying the
run at the reporting step.
Mechanism: `_write_task_loss_log` calls `_aperture_s_positions(task.elements)`,
which walks the **unresolved** specs; `_placement_length` (`beam_line.jl:384`)
is `Float64(getparam(e, :L, 0.0))`, and `Float64` of an `AbstractKnobExpression`
raises the directed eager-conversion error (`Knobs.jl:928`). Knob-driven lengths
are a first-class documented feature. The same construction-time hazard exists
at `Tasks.jl:242`, `UInt64(getparam(element, :rng_id, 0))` in
`_warn_duplicate_radiation_streams`. Because this walk also runs in `execute!`'s
`catch` block, it is one of the triggers for U13-2.
Repro: `@knob len = 0.5`;
`drift = ElementSpec{:drift}(; L=@knob_expr(len), tracking_method=Symplectic6DMap())`;
`TrackingTask((drift, ApertureSpec(shape=:rectangle, x_limit=1.5e-3, y_limit=1.0,
name="COLL")); loss_log="…h5")`; `execute!(task, rep; turns=1)`. Expect
`ArgumentError: a knob expression cannot be converted to a number eagerly`.
Controls measured: numeric `L` + `loss_log` writes the file fine; knob `L`
**without** `loss_log` runs fine.
Cross-file seam (auditor's call): the fix belongs either in `_placement_length`
(resolve knobs there) or in `_aperture_s_positions`; `_placement_length` is
owned by another unit.

### LEAD U13-6 [Low, confidence high] src/tasks/Tasks.jl:503-518 (seam with BeamObservers.jl:74-80)
Claim: A scheduled hook whose schedule cannot fire anywhere in the requested
turn window runs zero times, silently — the diagnostic nobody fires that
`Tasks.jl:436` itself warns about.
Mechanism: `should_run` is consulted per turn and each decision is recorded as a
`:hook_schedule` execution record, but nothing checks the *window*. `execute!`
already hands `prepare_observers!`/`prepare_line_observers!` both `turns` and
`first_turn` (Tasks.jl:503-504), so the driver has exactly what a warning would
need.
Repro: `ScheduledObserver(obs, AtTurns([500]))` on a task run with `turns=10`
from turn 0. Expect `observe!` called 0 times and **no** warning. Same for
`EveryNSteps(start=0, stop=0)` (0 calls). Control: `EveryNSteps(step=1000)`
fires once, at turn 0.

### LEAD U13-7 [Low, confidence high] src/knobs/Knobs.jl:390-393
Claim: Declaring a brand-new knob bumps the global epoch, so every
knob-dependent task recompiles its whole runtime line for a knob that no
existing expression can possibly reference (declaration-before-use is enforced
at `_validate_refs_locked`).
Mechanism: the new-entry branch of the bare declaration bumps unconditionally;
`_runtime_entries` cannot distinguish a relevant bump from an irrelevant one, so
`compile_runtime` re-runs over the entire line and `task.plan_cache` is emptied.
Repro: a 50-element knob-driven line; time 20 `execute!` calls with no mutation
against 20 calls each preceded by an unrelated `@knob spam_i = 1.0`. Measured
10.6 ms vs 50.4 ms (≈4.8×). Correctness is unaffected; this is the
performance-is-first-class axis.

### LEAD U13-8 [Low, confidence high] src/knobs/Knobs.jl:196-202, 913-916
Claim: `@knob_expr(-(5.0))` prints as `"-5.0"`, which reparses as the *literal*
`KnobConst(-5.0)`, so `knob_expression(string(e)) == e` is `false`. Value is
preserved; only the tree differs.
Mechanism: `_lower_knob` folds a unary minus into the constant only for
**non-finite** operands (the U14-2 `-Inf` fix); a finite negated literal stays a
`KnobCall`, while the printer emits the same text Julia's parser reads as a
negative literal.
Repro: `e = Octopus.KnobCall(:-, Octopus.AbstractKnobExpression[Octopus.KnobConst(5.0)]);
knob_expression(string(e)) == e` → `false`. Controls that DO round-trip:
`-(-5.0)`, `-u`, `+(5.0)`, `NaN`, `Inf`, `-Inf`, `-0.0`, `(-u) * v`, 3-ary `+`
and `*`, `min(u,v)`, `log(u,v)`, `atan(u,v)`.

### LEAD U13-9 [Low, confidence high] src/knobs/Knobs.jl:957-968 (out of hypothesis)
Claim: A knob expression inside a **nested** tuple or a **vector**-valued spec
parameter is invisible to `_param_has_knob`, so `resolve_knobs` returns the spec
unchanged, the raw expression object reaches the runtime constructor, and the
epoch gate treats the task as knob-free — silently.
Mechanism: `_param_has_knob` tests one level (`v isa Tuple && any(x -> x isa
AbstractKnobExpression, v)`), while the *resolver* `_resolve_knob_param(v::Tuple)
= map(_resolve_knob_param, v)` is fully recursive. The detector, not the
resolver, is the binding constraint, and the two disagree.
`docs/knob_control.md:225-227` documents "no array-valued knobs" as a
limitation, but the limitation is enforced by nothing — it degrades silently
rather than loudly.
Repro: `s.params[:probe_nested] = ((@knob_expr(a*3.0), 0.0), 1.0)` and
`s.params[:probe_vector] = [@knob_expr(a*3.0), 0.0]`. Expect
`Octopus._has_knob_parameters(s) == false` and the expression object still
present in `Octopus.params(Octopus.resolve_knobs(s))` for both, versus `true`
/ resolved for a scalar param and a flat tuple param.

---

## 3. Mutation-path → invalidation table (hypothesis (a))

Mutation paths **re-derived from the code**, not from the prior report's count
of 11. Every write to `_KNOB_TABLE` or to a `_KnobEntry` field was enumerated:
`_install_dependent_locked!` (:336), `_install_independent_locked!` (:354),
`_knob_define!` new-bare (:393), `_knob_define!` retype (:416, conditional),
`set_knob!` (:575), `reset_knobs!` (:861), `_forget_knob!` (:878), plus the
cache fill in `_knob_value_locked` (:613, deliberately not a mutation).
That yields **13 reachable public paths** (three of them sub-cases of the
retype branch that the prior pass counted as one).

Probe: for each path, build `TrackingTask` over an element whose parameter is a
knob expression through a dependent knob (`b = a*3.0`), `execute!` once so both
the runtime-entry cache and the dependent memo are warm, mutate, then `execute!`
again and read the compiled element back out of
`task.runtime_entries_cache[][1][1].element.zeta1`.

| # | Mutation path | epoch bumped | compiled value before → after | dependent memo | verdict |
|---|---|---|---|---|---|
| M1 | `set_knob!(:a, 5.0)` | yes | 6.0 → 15.0 | 6.0 → 15.0 | invalidated |
| M2 | `knobs.a = 5.0` (namespace `setproperty!`) | yes | 6.0 → 15.0 | 6.0 → 15.0 | invalidated |
| M3 | `@knob a = 5.0` (independent, const rhs) | yes | 6.0 → 15.0 | 6.0 → 15.0 | invalidated |
| M4 | `@knob b = a * 10.0` (redefine dependent) | yes | 6.0 → 20.0 | 6.0 → 20.0 | invalidated |
| M5 | `@knob b = 99.0` (dependent → independent) | yes | 6.0 → 99.0 | 6.0 → 99.0 | invalidated |
| M6 | `@knob a::Float32`, value changes (0.1) | yes | 6.0 → 0.30000000447034836 | ditto | invalidated |
| M7 | `@knob a::Float32`, value `isequal` | **NO** | type stays stale | unchanged | **LEAD U13-1** |
| M8 | `@knob a::Int` (2.0 → 2), value `isequal` | **NO** | type stays stale | unchanged | **LEAD U13-1** |
| M9 | `reset_knobs!()` | yes | next `execute!` raises `unknown knob b` | error | invalidated, loudly |
| M10 | `_forget_knob!(:a)` | yes | next `execute!` raises `unknown knob a` | error | invalidated, loudly |
| M11 | `@knob zzz` (new bare declaration) | yes | 6.0 → 6.0 (nothing to invalidate) | — | **LEAD U13-7** (bump nothing consumes) |
| M12 | `@knob unset::Int` on an unset knob | yes (from the *declaration*), no second bump for the retype | 6.0 → 6.0 | — | sound (no value existed) |
| M13 | `@knob sym::Symbol = :two` (non-Real thunk) | yes | 6.0 → 6.0 | — | invalidated |

Consumers re-derived: `Tasks.jl:595-619` (`_runtime_entries`) and
`strongstrong/interface.jl:2396-2416` (`_strong_strong_runtime_blocks`) are the
only two epoch gates in the tree; `resolve_knobs` records `knob_epoch()` in its
`:knob_resolution` receipt but does not gate on it. Both gates read
`knob_epoch()`/`_spec_epoch()` **before** compiling, so a concurrent mutation
costs at worst one spurious recompile, and both empty their plan cache on
rebuild. Both consult `_has_knob_parameters`, whose `LineEntry` and
`ElementSpec{:line}` methods live in `beam_line.jl:168-173` — verified present
and effective (see §5, BeamLine checks).

Reverse direction ("epoch bumped where nothing consumes it"): M11 is the one
real instance, quantified in U13-7. `reset_knobs!` on an already-empty table
also bumps; harmless.

---

## 4. Extension load-mode verdicts (hypothesis (b))

`ext_check.jl` run in seven configurations. `knob_derivative` was exercised in
every one (it must never need either weakdep), and the elliptical
Bassetti–Erskine kick `Octopus._elliptic_gaussian_kick_principal` was
differentiated with ForwardDiff wherever ForwardDiff was present.

| Configuration | `knob_symbolics_available()` | `_HAS_SYMBOLICS_SCRIPT_MODE` | `_HAS_FORWARDDIFF_SCRIPT_MODE` | Symbolics round trip | ForwardDiff BE-kick rule | verdict |
|---|---|---|---|---|---|---|
| pkg, weakdeps installed, neither loaded | false | false | false | refuses with the directed error | n/a | correct |
| pkg + `using Symbolics` | **true** | false | false | value-identical | n/a | correct |
| pkg + `using ForwardDiff` | false | false | false | refuses | rel 4.2e-10 / 1.2e-10 | correct |
| pkg, `using ForwardDiff` **before** `using Octopus` | false | false | false | refuses | identical numbers | correct (order-independent) |
| pkg + both | true | false | false | value-identical | identical numbers | correct |
| script mode, env with both | true | **true** | **true** | value-identical | identical numbers | correct |
| script mode, `--project=Octopus` | **true** | **true** | false | value-identical | n/a | see note |
| script mode, `JULIA_LOAD_PATH="@:@stdlib"` | false | false | false | refuses | n/a | correct |

- Package mode never sets the script-mode flags, in **any** environment
  (including one where both weakdeps are installed and precompiled): the
  `@eval import Symbolics` / `import ForwardDiff` inside the module body
  correctly fails against the package's `[deps]` and is caught. The R3 trap
  (adapter alive only for developers) has not regenerated.
- Extension ordering is irrelevant: loading ForwardDiff before Octopus gives
  bit-identical derivatives to loading it after.
- No method defined only in an extension is assumed to exist elsewhere: the
  base `_near_round_conditioning_factor(::Type{T}) where {T<:Real}`
  (`strong_beam.jl:767`) throws a directed `ArgumentError` and the base
  `faddeeva_w(z) = erfcx(-im*z)` (`SpecialMath.jl:14`) is total for `Complex`
  of a real; the extension only *adds* `Dual` methods. `knob_symbolic` /
  `knob_from_symbolic` go through the `Ref`-based adapter and refuse with
  instructions when it is unset. Nothing in `src/` calls the extension-only
  methods unconditionally.
- **Note (Low, doc drift, out of hypothesis):** `symbolic.jl:53-55` and
  `docs/knob_control.md:213-216` both say the script-mode adapter activates
  "when Symbolics is importable **from the active project**". It actually
  resolves against the whole `LOAD_PATH`. Measured: with
  `--project=/cfs/ad/dxu/Library/Julia/Octopus` (where Symbolics is only a
  *weak* dep) script mode still reports `_HAS_SYMBOLICS_SCRIPT_MODE == true`,
  because Symbolics sits in this machine's `~/.julia/environments/v1.12`;
  dropping the shared env with `JULIA_LOAD_PATH="@:@stdlib"` flips it to
  `false`. Same command, two answers, depending on a file outside the
  repository. The test suite is not exposed (`test/runtests.jl:8066` asserts
  `knob_symbolics_available()` unconditionally, as it should), but a user
  script's behavior is machine-dependent.

---

## 5. Derivative agreement (hypothesis (c))

All numbers measured against central differences (step `1e-6` for expressions,
`1e-4` for the tracked knob sweeps).

**(a) Operator coverage, derived not hand-copied.** The probe enumerates
`keys(Octopus._KNOB_OPERATORS)` (24 entries) and fails on any operator without a
probe expression, so the coverage list cannot drift from the whitelist.

- 21 differentiable operators (`+ - * / ^ sqrt cbrt abs inv exp log log10 sin
  cos tan asin acos atan sinh cosh tanh`) — **all** agree, worst relative error
  **3.22e-10** (`cbrt`), best 1.7e-12 (`sqrt`). `^` was probed w.r.t. the
  **base** with a non-constant exponent, exercising the general
  `a^b·(db·log a + b·da/a)` branch that a constant-exponent probe misses.
- `sign`, `min`, `max`, `log(a,b)`, `atan(a,b)` all refuse with the documented
  `ArgumentError`. `d|a|/da` at `a = 0` is exactly `0.0`, as documented.
  Derivative w.r.t. an unreferenced knob is exactly `0.0`.
- `uncovered operators: none`.

**(b) Twelve independently chosen composite shapes** (different from the prior
pass's list): `atan(a)exp(−b)` (w.r.t. both), `log(a³+b)/cosh(ab)`,
`sqrt(|a|+1)·sinh(b/a)`, `(a+b)^2.5 − cbrt(ab)`, `inv(1+a²)`, `a^b`,
`tanh(a)log₁₀(b)`, `a·a·a` (3-ary product rule with a repeated argument),
`exp(sin(cos a))`, `asin(a/2)+acos(b/4)`, `tan(ab)+a/(b+2)`.
Worst relative error **1.94e-10**, best 1.13e-11.

**(c) Two-level registry chain.** `c = sin(a)·b`, `d2 = c² + log(c)`;
`knob_derivative(:d2, :a)` returns `2.0 * c * cos(a) * b + cos(a) * b / c` and
evaluates to `+2.852651875807e+00` against a central difference of
`+2.852651875773e+00` — rel **1.19e-11**. With `through_registry=false` the
result is exactly `0.0`, as the partial-derivative semantics require.

**(d) One knob feeding MULTIPLE elements.** `bus` drives
`focus.zeta1 = 2.0*bus` and `defocus.zeta1 = −(0.5*bus)` in one task;
`crab_dispersion` gives `x_out = x₀ + (2·bus − 0.5·bus)·z₀`, so the exact
response is `1.5·z₀ = 1.5e-3`. Tracked central difference
`+1.500000000000e-03`; `knob_derivative` prediction summed over the two elements
`+1.500000000000e-03` — rel **1.56e-13**. Both compiled parameters really moved
(`focus.zeta1 = 1.9998`, `defocus.zeta1 = −0.49995` at `bus = 0.9999`).

**(e) A knob inside a BeamLine.** Same two elements assembled as
`BeamLine("CELL", [f2, d2e])`. `task.elements` is a tuple of `LineEntry`;
`_has_knob_parameters(task.elements) == true` (the `beam_line.jl:168` method
carries it), and the tracked response is `+1.500000000000e-03`, rel **1.56e-13**
from exact. Repeated for a **kept-whole (own-state)** line
`BeamLine("CRYO", [f2, d2e]; x_offset=1e-6)`: `_has_knob_parameters == true`,
response again rel **1.56e-13**. Both lines pick up `set_knob!` at the next
`execute!`.

**(f) Dual-number knob, single-pass response.** `Knobs.jl:628-633` claims a knob
may hold a dual number so that "`bus` feeding a whole magnet family gives the
family's response in a single pass". Verified in the weakdep env:
`@knob bus::Real`, seeded with a `ForwardDiff.Dual` and tracked through a
`Dual`-typed `Phase6DRep`, gives `d(x_out)/d(bus) = 0.0015` against the exact
`1.5·z₀ = 0.0015` — relative error **0.0**. The comment's claim holds; a fresh
`TrackingTask` per seed is required because the runtime element type changes.

---

## 6. Clean list (what was checked, and with what evidence)

1. **Epoch reaches both consumers.** M1–M6, M9, M10, M13 all invalidate a warm
   compiled runtime and the dependent memo (table §3). Both gates read the
   epochs before compiling and empty their plan caches on rebuild (read).
2. **`_has_knob_parameters` covers every container the task walks.** Tuple,
   Vector, `ElementSpec`, `LineEntry`, `ElementSpec{:line}` — verified by
   tracking response through a dissolved BeamLine and an own-state BeamLine
   (§5e). The one shape it does **not** cover is nested tuples / vectors inside
   a single parameter (U13-9).
3. **U14's seven leads are all fixed — re-verified by measurement, not by
   reading the fix.** `@knob dep::Float32` on an expression-defined knob throws
   with `knob_value(:dep)` and `knob_epoch()` both bit-unchanged (U14-1);
   `string(@knob_expr((u^v)^w)) == "(u ^ v) ^ w"`, round-trips `== true`, value
   64.0, and `KnobConst(-Inf)`/`KnobConst(NaN)` and the `x/0.0` derivative fold
   all round-trip (U14-2); `pi`, `π`, `ℯ`, `NaN`, `Inf` are each rejected as
   knob names with nothing registered (U14-3); `@knob sin.x = 1.0` throws and
   leaves `list_knobs()` empty with the epoch unmoved (U14-4);
   `knob_symbolics_available()` is exported, documented, and asserted
   unconditionally by the suite (U14-5, U14-6); and all nine of
   `2*e, e*2, e+e, e^2, 2-e, e/2, Int(e), Float64(e), float(e)` raise the
   directed `ArgumentError` (U14-7). The residual gaps in the *same* two
   functions are U13-4 and U13-8.
4. **Derivative correctness** — §5, complete operator sweep plus 12 composite
   shapes plus registry chaining plus three tracking-level checks; worst
   relative error anywhere `3.22e-10`.
5. **Both weakdep extensions, both directions** — §4, seven load
   configurations, including "weakdep installed but not loaded" and reversed
   load order.
6. **`loss_report = false` still switches off DETECTION, and is still
   documented as doing so.** `Tasks.jl:474-491` and the `TrackingTask`
   docstring (`:111-132`) both say it. Measured: with `loss_report = false`,
   `_task_loss_summary` returns `nothing`, no `unattributed` warning is emitted
   for a beam containing a NaN particle, and the HDF5 loss file is written with
   `["aperture_counts", "aperture_names", "aperture_s", "column_names", "data",
   "record_count"]` — the five `summary_*` datasets present under
   `loss_report = true` are absent. Per-particle records are unaffected, as
   documented.
7. **Loss accounting, order and identity.** A three-aperture line
   (`A` 1.5 mm, `B` 2.5 mm, `C` 3.5 mm, at s = 1, 3, 6 m) with five particles at
   1–5 mm gives `aperture_names == ["A","B","C"]`,
   `_aperture_s_positions == [1.0, 3.0, 6.0]`, `loss_counts == [4, 0, 0]`,
   one survivor at 1 mm — id assignment, `s` accounting and per-aperture
   attribution all line up. The `_bind_apertures` count tripwire
   (`Tasks.jl:659-662`) is present and correct.
8. **Crashed-run flush.** A run that throws mid-loop still writes the loss file
   and reports (part 7, T6) and does **not** advance `task.next_turn`
   (measured: `next_turn == 0` after a failure at turn 3). Note the beam *has*
   advanced, so a retry re-tracks the completed turns — documented behavior, but
   worth the auditor's eye.
9. **Observer lifecycle.** `finalize_observer!` runs once per `execute!` call,
   not once per task; the replayed-window discard machinery
   (`_discard_replayed_*`, U6-2) is what makes split runs idempotent, and
   `prepare_observer!(obs, runtime_elems)` called from `_build_tracking_plan`
   is the two-argument form (LuminosityObserver element binding only) and
   resets no buffers, so a mid-run plan rebuild cannot discard readings. Read +
   measured (`turns=0` prepares and finalizes with zero observations).
10. **New-in-window code read and exercised.** `_warn_hidden_apertures` and
    `_warn_duplicate_radiation_streams` walk the same containers as
    `_collect_aperture_specs!` (Tuple / AbstractVector / LineEntry /
    `ElementSpec{:line}`) and fire at construction; the `_placement_length`
    switch in `_collect_aperture_s!` is what makes the `[1.0, 3.0, 6.0]`
    measurement above come out right.
11. **Registry hygiene** — `reset_knobs!` and `_forget_knob!` make a stale task
    fail loudly (`unknown knob …`) rather than track a stale number; cycle
    rejection at install and a second guard at evaluation; `_KNOB_LOCK` held
    across every table mutation.

---

## 7. Minor notes (not leads)

- `_KnobEntry.path` (`Knobs.jl:120`) is still written and never read — same
  observation as U14.
- `rhs_thunk()` (`Knobs.jl:427`) still runs arbitrary user code while holding
  `_KNOB_LOCK`; reentrant on the same thread, theoretically deadlockable across
  threads.
- `knob_derivative(@knob_expr(min(a,b) * 0.0), :a)` refuses even though the
  product-rule term is multiplied by an exact zero — the refusal precedes the
  `_kmul` zero fold. Conservative and safe; noting it because it looks like a
  false positive to a user.
- `_bind_apertures` assigns aperture ids through `map` over a `Tuple` with a
  side-effecting counter. Julia evaluates tuple `map` left to right in practice
  (verified by §6.7), but the id **order** is pinned by no test — only the
  count is (`Tasks.jl:659`). A reversal would silently mislabel per-aperture
  counts.
- `knob_value(x::Real) = Float64(x)` (`Knobs.jl:599`) casts, which sits oddly
  next to the deliberate no-cast comment at `:628-633`; it only applies to a
  bare `Real` argument, so no derivative can reach it.

---

## 8. Not checked, and why

- **GPU / CUDA paths.** No `ResolvedCUDAExecutionPolicy` leg was exercised
  (`_track_fused_runtime!`, `_track_isolated_runtime!`, and
  `_synchronize_segment_stream` stream arguments are read-only in this report).
  Reason: the CUDA leg belongs to the backend units and the brief scoped this
  unit to the driver logic; every probe ran on `CPUThreadsExecutionPolicy`.
- **`StrongStrongTask`'s epoch gate** (`strongstrong/interface.jl:2396-2416`)
  was read and compared line by line with `_runtime_entries`, but not probed:
  it is another unit's file. It shares U13-1's exposure (same
  `!knob_dependent || kepoch == knob_epoch()` predicate) and does **not** share
  U13-2/U13-5 (it has no loss-log path of its own).
- **Thread-parallel knob mutation.** The lock discipline was read (every
  mutation is inside `lock(_KNOB_LOCK)`), but no concurrent-mutation stress
  probe was run; the 2026-08-04 record already covers the handshake.
- **`docs/registry_snapshot.md` / `docs/public_api.md` consistency for the new
  `knob_symbolics_available` export** was not re-derived; the export and
  docstring exist and the doc text was checked, but the snapshot file belongs to
  the documentation unit.
