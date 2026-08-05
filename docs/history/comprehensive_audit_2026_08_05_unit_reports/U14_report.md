# U14 — Knob subsystem audit (commit 7a8e9ca)

## Coverage

Read line-by-line, 100% of assigned files:
- `src/knobs/Knobs.jl` lines 1-916 (all)
- `src/knobs/symbolic.jl` lines 1-319 (all)
- `ext/OctopusSymbolicsExt.jl` lines 1-19 (all)

Context read for verification targets: `src/tasks/Tasks.jl:500-560` (epoch gate),
`src/tasks/strongstrong/interface.jl:2235-2290` (epoch gate),
`src/knowledge/Knowledge.jl:55-97` (spec epoch), `src/elements/beam_line.jl:60-100`
(LineEntry override epoch), `docs/knob_control.md` (all 238 lines),
`examples/knob_control.jl` (all 159 lines), `docs/public_api.md:156-172`,
`Project.toml` ([weakdeps]/[extensions]), `src/beam/Beam.jl:9-16` (CUDA pattern).

Probes (all run, `julia --startup-file=no --project=.`, CPU, < 60 s each after
first compile; probe 5 with `JULIA_LOAD_PATH="@:<scratch env>:@stdlib"` to
activate the script-mode Symbolics adapter):
- `U14/probe1_retype_mutation.jl` — epoch enumeration + retype-throw mutation
- `U14/probe2_string_roundtrip.jl` — printing round trip
- `U14/probe3_derivative_fd.jl` — derivative vs central finite differences
- `U14/probe4_names_validation.jl` — names, collisions, validation, eager errors
- `U14/probe5_symbolics_roundtrip.jl` — Symbolics adapter round trip

## Leads

### U14-1 — Knobs.jl:355-357 + 288-298: `@knob dep::T` on an expression-defined knob mutates the registry, then throws, with no epoch bump — MEDIUM

`_knob_define!` calls `_resolve_knob_type_locked!` (which sets `entry.type = T`
and REPLACES the cached `entry.value` with the converted value) *before* the
`entry.expression !== nothing` guard at :364-368 throws "already defined by the
expression". The epoch-bump fix at :369-383 explicitly covers only the
independent-knob branch; the dependent branch throws first.

Measured (probe 1): `@knob a = 0.1; @knob b = a * 1.0; knob_value(:b)` then
`@knob b::Float32` throws ArgumentError, and afterwards:
- `knob_value(:b)` = `0.1f0::Float32` (was `0.1::Float64`; Float64(0.1f0) =
  0.10000000149011612 — the number changed);
- `knob_epoch()` 16 → 16 (NOT bumped): a compiled task keeps tracking the old
  value while the registry reports the new one — the exact stale-physics class
  named in the audit brief;
- dependents of `b` are NOT invalidated (`_invalidate_dependents_locked!` never
  runs on this path), so their caches are stale too;
- `entry.type` is permanently `Float32`: after `set_knob!(:a, 0.2)`,
  `knob_value(:b) == 0.2f0::Float32` — silent precision degradation from a call
  that reported an error.

Violated invariants: "all errors happen here … never silent" (definition-time
errors must not leave partial state); "Monotone counter bumped by every knob
mutation" (knob_epoch docstring, Knobs.jl:122-129).
Repro: `scratchpad/U14/probe1_retype_mutation.jl`.

### U14-2 — Knobs.jl:845-854: left-nested `^` prints without parentheses; string round trip changes the value 64 → 512 — MEDIUM

`_knob_expr_string(::KnobCall)` gives operand 1 required precedence `p` and uses
the strict comparison `p < prec` for parenthesization, so a `^` node nested as
the FIRST argument of another `^` is printed bare. But `^` is right-associative
in Julia. Measured (probe 2): `e = @knob_expr((u^v)^w)` with u=2, v=3, w=2:
`string(e) == "u ^ v ^ w"`, `knob_expression(string(e))` rebuilds `u ^ (v ^ w)`,
`e == e2` is `false`, `knob_value(e) == 64.0` vs `knob_value(e2) == 512.0`.
Right-nested `a^(b^c)` round-trips correctly (control in the probe).

Violated invariant: docs/knob_control.md:30 "lossless printing
(`knob_expression(string(e)) == e`)"; Knobs.jl:833 "round-trips through
knob_expression"; serialization silently corrupts semantics.

Secondary (same serialization surface): constant folding in the derivative's
smart constructors can produce non-finite `KnobConst`s —
`knob_derivative(@knob_expr(x/0.0), :x)` returns `KnobConst(NaN)` (symbolic.jl:96,
0/0) — and `repr(NaN)`/`repr(Inf)` reparse as *Symbols*, i.e. `KnobRef(:NaN)`:
`knob_expression(string(d))` errors "unknown knob NaN".
Repro: `scratchpad/U14/probe2_string_roundtrip.jl`.

### U14-3 — Knobs.jl:101-104/160-163 vs 326-341: a knob named `pi`/`π`/`ℯ` is declarable but silently unreachable from expressions — LOW

Nothing stops `@knob pi = 3.0` (accepted; `knob_value(:pi) == 3.0`,
`knobs.pi == 3.0`), but `_lower_knob` checks `_KNOB_NAMED_CONSTANTS` before
`KnobRef`, so `@knob_expr(pi)` lowers to `KnobConst(3.141592653589793)` — the
registry and the expression language disagree about the same name with no
error anywhere. Violated invariant: "unknown knobs … are immediate errors,
never silent" (Knobs.jl:20-21) — here a *known* knob is silently shadowed.
Either the declaration should be rejected or the reference should resolve to
the knob. Repro: `scratchpad/U14/probe4_names_validation.jl`.

### U14-4 — Knobs.jl:471-476: root-binding collision error leaves the knob registered — LOW

The `@knob` macro expansion runs `$define` (registers the knob, bumps the
epoch) and only then `_ensure_knob_root`, which throws when the root already
names a non-KnobNamespace binding. Measured (probe 4): after
`@knob sin.x = 1.0` errors ("cannot bind knob namespace sin"),
`list_knobs() == [Symbol("sin.x")]` and `knobs.sin.x` reads 1.0. Partial
mutation on a thrown declaration (same invariant as U14-1, lesser consequence:
the knob remains fully usable via the `knobs` root).
Repro: `scratchpad/U14/probe4_names_validation.jl`.

### U14-5 — symbolic.jl:41-42: no public adapter-availability query; example and test call the internal `_symbolics_adapter_active` (audit lead A-1) — LOW

`examples/knob_control.jl:151` and `test/runtests.jl:7221` branch on
`Octopus._symbolics_adapter_active()`, an unexported underscore function absent
from `docs/public_api.md` (which lists `knob_symbolic`/`knob_from_symbolic`,
:171-172). Any user script that wants graceful degradation must reach into
internals. Characterization: export a documented query (e.g.
`knob_symbolics_available()` or `symbolics_adapter_active()`) next to
`knob_symbolic` in the public API and the "Knob Control" section of
`docs/registry_snapshot.md`, and use it in the example/tests. No probe needed;
grep evidence above.

### U14-6 — docs/knob_control.md:199-209 vs symbolic.jl:13-31 + ext: doc claims "install it … and the adapter activates"; package mode requires an explicit `using Symbolics` — LOW (doc drift)

The doc says Symbolics is "loaded with the same optional pattern as CUDA in
`src/beam/Beam.jl`" (a try-import at Octopus load: install ⇒ active). That is
true only in script mode (symbolic.jl:313-319). In package mode the [weakdeps]
extension activates only when the *session* loads Symbolics; installing alone
does nothing. The runtime error text (symbolic.jl:45-53) states the correct
rule; the design doc still describes the pre-R3 mechanism.

### U14-7 — docs/knob_control.md:169-171 vs Knobs.jl:866-872: `2 * e` raises a bare MethodError, not the promised directed error — LOW (doc drift)

Doc: "`2 * e` and `Float64(e)` do not silently evaluate — eager conversion
raises a directed error." Measured (probe 4): `Float64(e)` and `float(e)` raise
the directed ArgumentError (Knobs.jl:868-872), but `2 * e` raises
`MethodError: no method matching *(::Int64, ::KnobCall)`. Safe (still an
error), but the doc promises guidance that arithmetic composition does not get.

## Minor notes (not leads)

- `_KnobEntry.path` (Knobs.jl:111) is stored and never read anywhere.
- Non-Real thunk `rhs_thunk()` (Knobs.jl:391) runs arbitrary user code while
  holding `_KNOB_LOCK`; ReentrantLock makes same-thread reentry safe, but a
  thunk that blocks on another thread's knob access can deadlock. Theoretical.
- `knob_derivative(e, some_KnobCall)` / `knob_dependents(KnobCall)` hit a raw
  MethodError on `_knob_path` instead of a directed message (KnobRef works, as
  the doc's `@knob_expr(path)` idiom requires).

## Sound (invariant → how verified)

1. **Epoch on every public mutation path** — probe 1 enumerates: `@knob` new
   independent / reassign / new dotted / new dependent / redefine dependent /
   retype-independent-with-value-change, `set_knob!`, `knobs.c = v`,
   namespace assignment, `_forget_knob!`, `reset_knobs!` — all 11 bump.
   (The one non-bumping mutation found is the error path of U14-1.)
2. **Task epoch gate** — Tasks.jl:522-539 and interface.jl:2253-2270 read
   `kepoch`/`sepoch` *before* compiling, so a concurrent mutation causes at
   worst one spurious recompile, never staleness; both clear their plan caches
   on rebuild; both also gate on `_spec_epoch`, which Knowledge.jl:75-94 bumps
   on every `ElementSpec` setproperty! and beam_line.jl:76-84 on every
   LineEntry override — post-construction `@knob_expr` binding reaches a built
   task (doc §2 "Binding an existing element" holds).
3. **Native derivative correctness** — probe 3: 9 nontrivial shapes
   (tan/sqrt/division nest, multi-reference product `a*b*a`, `sin(a*b)+a^b`
   both wrt a and b, exp/cosh, cbrt∘(log+atan+asin), inv·log10+tanh, abs) match
   central finite differences to rel ≤ 3e-9 (registry chain 2.1e-7, FD-step
   artifact at cur=1000). Chain THROUGH the registry: `d(k1)/d(cur)` =
   `xfer*brho/brho^2` = 6.165228113440197e-4 vs exact `xfer/brho` =
   6.165228113440198e-4; total vs partial (`through_registry=false`) both exact.
4. **Non-smooth refusal** — `sign`, `min`, `max`, `atan(y,x)`, `log(b,x)` all
   raise the "not implemented … non-smooth or multi-branch" ArgumentError;
   `d(abs)/dx` at 0 returns 0.0 exactly as documented ("abs at 0 aside");
   derivative wrt an unreferenced knob is 0.0.
5. **Definition-time validation** — probe 4: free symbol, arbitrary call
   (`println`), comparison `>`, indexing, string literal argument, wrong arity
   (`sqrt(q,q)`), ternary/control flow: all rejected at build with directed
   messages listing the whitelist. Symbol-typed knob inside arithmetic is
   accepted at build (value-dependent, cannot be known) and rejected at eval
   naming the operand and its type — deferred but loud, matching the design.
6. **Cycles** — rejected at install through the transitive closure
   (Knobs.jl:307-308) plus a belt-and-braces runtime check (:567); derivative
   has its own cycle guard (symbolic.jl:160).
7. **Cache invalidation invariant** — a dependent's cache can only be non-nothing
   if its inputs were evaluated (evaluation caches bottom-up), so the
   early-stop recursion in `_invalidate_dependents_locked!` (:238-250) is
   sound; install/assign paths clear the whole downstream cone. (Broken only
   via the U14-1 error path.)
8. **Namespace integrity** — value/namespace collisions rejected in both
   directions with exact messages; redefinition allowed; unicode paths work;
   `knobs` root reads/writes; `KnobNamespace.prefix` field access is
   getfield-based throughout so a knob named `prefix` cannot corrupt it;
   root-binding collision with an existing non-namespace binding is rejected
   (modulo U14-4's ordering).
9. **Symbolics adapter round trip** — probe 5 (adapter active, script mode +
   stacked env): 12 shapes including dotted refs, two-knob `^`, `min`, `atan2`,
   two-arg `log`, left-nested `^`, unary minus — all value-identical (rel 0.0);
   4 shapes structurally normalized (sub→`+ -1*`, etc.) exactly as the doc
   allows ("up to algebraic normalization"); dotted knob names survive as
   `var"HSR.a"` and map back to the same registry keys; an undeclared variable
   coming back is rejected ("unknown knob nope.nothere"); registration is
   Ref-based (no method-overwrite trap) and happens in `__init__`
   (precompile-safe); `Project.toml` [weakdeps]/[extensions]/[compat]/[extras]
   entries are consistent.
10. **resolve_knobs / eval typing** — specs without knob params returned
    unchanged (identity check `_has_knob_parameters` covers tuples and
    vectors of specs); tuple params resolved element-wise; receipt carries
    element kind, epoch, and sorted resolved pairs; `_eval_knob_node`
    deliberately does NOT cast to Float64 (dual-number/TPS pass-through,
    commented :585-592); dependent values converted to the declared type with
    a named error; unset knob evaluation raises a named ArgumentError;
    `Float64(e)`/`float(e)` raise the directed eager-conversion error.

Example `examples/knob_control.jl` cross-checked line-by-line against current
signatures; its only internal-API use is `_symbolics_adapter_active` (U14-5).
