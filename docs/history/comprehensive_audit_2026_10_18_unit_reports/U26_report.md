# U26: Knobs.jl + symbolic.jl + ext/ (ForwardDiff, MPI, Symbolics extensions)

Reading unit of the 2026-10-18 comprehensive audit; tree `/cfs/ad/dxu/Library/Julia/Octopus` at
commit 24e8683, read-only. Every claim below is a LEAD, not a finding. Severity guesses are the
unit's; the auditor decides.

## Region

| File | Lines | Depth |
|---|---|---|
| `src/knobs/Knobs.jl` | 1-1077 | every line |
| `src/knobs/symbolic.jl` | 1-335 | every line |
| `ext/OctopusForwardDiffExt.jl` | 1-15 | every line |
| `ext/OctopusForwardDiffRules.jl` | 1-51 | every line |
| `ext/OctopusMPIExt.jl` | 1-267 | every line |
| `ext/OctopusSymbolicsExt.jl` | 1-19 | every line |

Total 1764 lines, all read. References read in full: `docs/knob_control.md` (294 lines),
`examples/knob_control.jl` (200 lines), `docs/experiences.md` 504-545 ("A weak dependency's
extension does not exist for an `include`d module"), `Project.toml`.

Seam excerpts read to check what the region's contracts rest on (not audited as regions):
`src/policies/Policies.jl` 470-480, 515-560, 605-700, 1026-1062, 1080-1120, 1130-1240 (the
core's serial passthroughs and wrappers); `src/tasks/Tasks.jl` 1636-1680 and
`src/tasks/strongstrong/interface.jl` 3228-3260 (the two knob-epoch gates);
`src/elements/beam_line.jl` 840-935 (the wiring view's use of `knob_dependencies`);
`src/analysis/one_turn_matrix.jl` 200-235, 315-360 and `src/elements/strong_beam.jl` 930-950
(the core fallbacks the ForwardDiff rules add to); `src/Octopus.jl` 100-180 (include order and
the script-mode ForwardDiff activation); `src/math/SpecialMath.jl:14` (`faddeeva_w` primal).

## Provenance

READ line by line: the six region files in full, in file order, plus the references and seam
excerpts listed above. Hypotheses anchored: (1) epoch invalidation on every mutation path,
(2) the weak dependencies' two load modes, (3) symbolic knob evaluation and the realised-value
receipt, (4) MPI/Symbolics extension vs the core's passthrough.

EXECUTED (scratch: `result/comprehensive_audit_2026_10_18/probes/U26/`, logs beside each script;
package mode is `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4`; the weak deps
come from a stacked `JULIA_LOAD_PATH` because the Octopus manifest holds none of them —
`@v1.12` supplies Symbolics 7.33.0 and MPI, the scratch env `probes/U26/fdenv` built offline
supplies ForwardDiff 1.4.6):

1. `knob_semantics_probe.jl` (package mode, `knob_semantics_probe.log`): every mutation path's
   epoch delta and dependent-cache state; constant-expression rhs; `-0.0` round trip; unicode
   namespace; `knob_value(::Real)`; the `:knob_resolution` receipt. Key numbers in Leads/Clean.
2. `load_modes_package_probe.jl` (package mode, stacked `@v1.12`, `load_modes_package_probe.log`):
   no extension before a trigger, three directed errors from the core; Symbolics extension
   attaches, round trip relative difference 0.0; the run aborted at the ForwardDiff trigger
   because no manifest in that stack lists ForwardDiff (`Base.require` by PkgId: "does not seem
   to be installed") — superseded by probe 6.
3. `load_modes_script_probe.jl` run A (`--project=.`, default LOAD_PATH `["@","@v#.#","@stdlib"]`,
   `load_modes_script_probe_A.log`): include 30.4 s, `PkgId(Main.Octopus) = PkgId(nothing,"Main")`,
   `_HAS_FORWARDDIFF_SCRIPT_MODE=false`, `_HAS_SYMBOLICS_SCRIPT_MODE=true` (Symbolics resolved
   from `@v1.12`), all three `get_extension` are `nothing`, and `using MPI` after the include
   leaves `_mp_allsum_impl!` at 1 method and `_mp_open_communicator(MPIBackendTag())` = `nothing`.
   Run B (stacked with `fdenv`, `load_modes_script_probe_B.log`): `_HAS_FORWARDDIFF_SCRIPT_MODE=true`,
   `_forward_diff_linearization_available()=true`, still no extension.
4. `mpi_ext_probe.sh` / `mpi_ext_probe.jl` (2 ranks under `MPI.mpiexec()`, `mpi_ext_probe.log`):
   the extension's collectives called directly on `COMM_WORLD`; `all_ok=true` on both ranks;
   timed-kind table recorded.
5. `derivative_path_probe.jl` (package mode, `derivative_path_probe.log`): `knob_derivative`
   on a mistyped / undeclared / dependent / forgotten path; string-prefix filters; declare-then-use
   inside a function (Julia 1.12.4 world-age warning captured).
6. `forwarddiff_package_probe.jl` (package mode, stacked `fdenv`, `forwarddiff_package_probe.log`):
   the four ForwardDiff rules against finite differences and the complex step; knobs carrying
   duals; `compile_runtime` through a dual knob.
7. `mpi_shadow_probe.jl` (package mode, stacked `@v1.12`, `mpi_shadow_probe.log`): `which` for all
   21 `_mp_*` core/extension pairs.

Also executed: `julia -e 'Meta.parse(":m.k1")'` for Lead U26-5.

## Leads

### LEAD U26-1 [Moderate, confidence high] src/knobs/symbolic.jl:168
Claim: `knob_derivative(expr, path)` never looks `path` up in the registry, so a mistyped, undeclared or forgotten knob path yields the constant `0.0` instead of an error, while `set_knob!`, `knob_dependents`, `knob_value` and `@knob_expr` all refuse the same typo. (Hypothesis 3.)
Mechanism: `_kderiv(n::KnobRef, path, through, active)` (symbolic.jl:168-181) tests `n.path === path`, otherwise chains through the registry entry of `n.path`; a `path` matching no leaf and no dependent contributes zero at every leaf, and `knob_derivative` (symbolic.jl:155-164) validates only `x`, never `path_like`. The same missing lookup makes a DEPENDENT differentiation variable's result depend on how the expression is spelled: `knob_derivative(Symbol("m.k1"), Symbol("m.k1")) == 0.0` (its expression holds no ref to itself) while `knob_derivative(@knob_expr(m.k1 * m.brho), Symbol("m.k1")) == m.brho` (the ref matches before the chain), although the docstring says `path` is "the independent knob". A tree naming a knob since removed by `_forget_knob!` differentiates without complaint (result `f.b`) where `knob_value` of the same tree throws. A response-matrix column (`docs/knob_control.md` §4, "the response-matrix primitive") built from a mistyped knob is a silent column of zeros. The documented `knob_derivative(e, @knob_expr(path))` form is safe because `@knob_expr` validates; the `Symbol`/`String` forms the signature accepts are not.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus -e 'using Octopus; @knob m.brho=81.1; @knob m.xfer=0.05; @knob m.current=1000.0; @knob m.k1=m.current*m.xfer/m.brho; e=@knob_expr(m.k1*m.brho); println(knob_derivative(e, Symbol("m.curent")), " ", knob_derivative(e, "nosuch.knob"), " ", knob_derivative(Symbol("m.k1"), Symbol("m.k1")), " ", knob_derivative(e, Symbol("m.k1")))'` prints `0.0 0.0 0.0 m.brho`; expected an `ArgumentError: unknown knob m.curent` like `set_knob!(Symbol("m.curent"), 1.0)` gives. Log: `probes/U26/derivative_path_probe.log`.

### LEAD U26-2 [Minor, confidence high] src/knobs/Knobs.jl:946
Claim: a negative-zero literal as the base of `^` breaks the documented round trip `knob_expression(string(e)) == e` and flips the sign of the value: `@knob_expr((-0.0)^2)` prints `-0.0 ^ 2.0`, which reparses as `-(0.0 ^ 2.0)`. (Out of hypothesis.)
Mechanism: `_knob_expr_string(::KnobConst, prec)` parenthesizes a literal only when `n.value < 0 && prec > 0`; `-0.0 < 0` is false. Julia binds a leading minus on a numeric literal looser than `^` (`-2^2 == -4`), the one operator where the parenthesis matters, so the tree becomes `KnobCall(:-, [KnobCall(:^, ...)])`, and `==` on `KnobConst` is `isequal` (line 66, by the U14-2 design), so `KnobConst(0.0) != KnobConst(-0.0)` as well. `signbit(n.value)` in place of `n.value < 0` closes it; `-Inf` and finite negatives already round-trip (U14-2, U13-8 folds).
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus -e 'using Octopus; e=@knob_expr((-0.0)^2); s=string(e); r=knob_expression(s); println(repr(s), " ", r==e, " ", knob_value(e), " ", knob_value(r))'` prints `"-0.0 ^ 2.0" false 0.0 -0.0`; the control `(-2.0)^2` prints `"(-2.0) ^ 2.0" true`. Log: `probes/U26/knob_semantics_probe.log`.

### LEAD U26-3 [Minor, confidence high] src/knobs/Knobs.jl:748
Claim: `Base.propertynames(::KnobNamespace)` strips the prefix with `s[length(prestr)+1:end]`, a character count used as a byte index, so a namespace root containing a multi-byte character reports wrong child names silently: `propertynames(Δ)` is `(Symbol(""),)` after `@knob Δ.x = 1.0`. (Out of hypothesis.)
Mechanism: `length("Δ.") == 2` but `ncodeunits("Δ.") == 3`, so `"Δ.x"[3:end] == ".x"` whose first dot-separated piece is the empty string; a prefix whose character count lands inside a multi-byte character would throw `StringIndexError` instead. Every other prefix walker in the file (`_is_namespace_prefix_locked` 724-725, `_check_namespace_collision_locked` 287-298, `list_knobs` 813) uses `startswith` and is byte-correct, so the namespace itself works (`Δ.x` reads 1.0, `knob_report(prefix="Δ")` lists it) and only tab completion and `propertynames` lie. `s[ncodeunits(prestr)+1:end]` or `chopprefix(s, prestr)` fixes it.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus -e 'using Octopus; @knob Δ.x = 1.0; @knob plainroot.x = 1.0; println(propertynames(Δ), " ", Δ.x, " ", propertynames(plainroot))'` prints `(Symbol(""),) 1.0 (:x,)`; expected `(:x,)` for both. Log: `probes/U26/knob_semantics_probe.log`.

### LEAD U26-4 [Minor, confidence high] ext/OctopusMPIExt.jl:227
Claim: `_mp_bcast_impl!` (227), `_mp_bcast_scalar_impl` (230), `_mp_barrier_impl` (233) and `_mp_gather_rows_impl` (242-265) call MPI without `_mp_timed`, so `_mp_collective_times()` — documented at `src/policies/Policies.jl:543-551` as "per kind of collective, (calls, nanoseconds) spent inside the extension's MPI calls" — never contains `:bcast`, `:bcast_scalar`, `:barrier` or `:gather_rows`, although the core records receipts under exactly those kinds. (Hypothesis 4.)
Mechanism: the other collectives wrap their MPI call in `_mp_timed(f, kind)` (allsum, allminmax, allmin, allmax, exchange_columns, isend, irecv, the waits, test); these four do not. The barrier is the one collective whose wall time is pure load imbalance, so the instrument meant to say "what division costs" (its own docstring; `docs/design/multi_process_policy.md:98, 851`) is blind precisely there, and the benchmark that prints the table (`profiling/benchmark_collide_cpu.jl:332`) shows an absent kind, which reads as zero cost. Two hand-kept kind lists (core receipts, extension clocks) with no tripwire — defect class 2.
Repro: `bash /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U26/mpi_ext_probe.sh` (2 ranks) prints `timed kinds after allsum/exchange/gather/minmax/bcast/barrier: [:allmax, :allmin, :allminmax, :allsum, :exchange_columns]` and `NOT timed although called: [:bcast, :bcast_scalar, :barrier, :gather_rows]`. Static form: the 12 kinds of `grep -o "_record_collective!(:[a-z_]*" src/policies/Policies.jl | sort -u` against the 8 of `grep -o "_mp_timed(:[a-z_]*\|, :[a-z_]*)" ext/OctopusMPIExt.jl | sort -u`.

### LEAD U26-5 [Minor, confidence high] src/knobs/symbolic.jl:147
Claim: the `knob_derivative` docstring example `dk1_dI = knob_derivative(:m.k1, :m.current)` cannot run: `:m.k1` parses as `getproperty(:m, :k1)` and raises `FieldError: type Symbol has no field k1`; a dotted path must be `Symbol("m.k1")`, `"m.k1"` or `@knob_expr(m.k1)`. The same example declares `m.brho` and `m.xfer` but never `m.current`, so the corrected call would still throw "unknown knob". (Out of hypothesis; defect class 14.)
Mechanism: documentation as claims; `docs/knob_control.md` §4 uses the `@knob_expr` form and runs.
Repro: `julia -e 'ex = Meta.parse(":m.k1"); println(ex.head, " ", ex.args); eval(ex)'` prints `. Any[:(:m), :(:k1)]` then the FieldError.

### LEAD U26-6 [Minor, confidence med] src/knobs/Knobs.jl:477
Claim: a right-hand side that is an expression over constants only (`@knob k = 2pi`, `2*3`, `1/3`, `sqrt(2)`) installs a DEPENDENT knob with no inputs; `set_knob!(:k, v)` and `knobs.k = v` then refuse with "set its independent inputs instead", and there are none. (Out of hypothesis.)
Mechanism: the independent/dependent decision in `_knob_define!` is `node isa KnobConst` (476-479), i.e. literal or negated literal only; `_lower_knob` folds nothing else, so the tree `KnobCall(:*, [2.0, 3.14159...])` has empty `knob_dependencies`. The value is right (6.283...), `knob_report` prints `:= 2.0 * 3.141592653589793` and `pending`; the harm is a refusal with wrong advice and a knob the documented assignment forms cannot drive (`docs/knob_control.md` §2 "Assignment": the macro, the namespace and `set_knob!` "do the same thing" — not for this knob). Folding a ref-free tree to `KnobConst(knob_value(node))` at definition would make it independent.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus -e 'using Octopus; @knob k = 2pi; println(knob_dependencies(:k)); set_knob!(:k, 1.0)'` prints `Symbol[]` then `ArgumentError: knob k is defined by the expression 2.0 * 3.141592653589793; set its independent inputs instead, or redefine it with @knob k = value`. Log: `probes/U26/knob_semantics_probe.log`.

### LEAD U26-7 [Minor, confidence med] src/knobs/Knobs.jl:813
Claim: `list_knobs(prefix)`, `knob_report(; prefix)` (via `list_knobs`) and the wiring report's filter (`src/elements/beam_line.jl:843`, seam) select by string prefix, not namespace prefix: `"HSR"` also selects `HSRx.y`, `"HSR.power"` also selects `HSR.powerful.other`, although the docstrings say "a namespace prefix such as HSR.power_supply". (Out of hypothesis; defect class 3.)
Mechanism: `startswith(string(p), prefix)` with no `"."` boundary, while the two structural walkers over the same registry — `_is_namespace_prefix_locked` (725) and `_check_namespace_collision_locked` (292-294) — match `prefix * "."`; three walkers disagree on what a namespace is. Harmless for physics; a report over-includes.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus -e 'using Octopus; @knob HSR.power_supply.arc_quad=1000.0; @knob HSR.powerful.other=1.0; @knob HSRx.y=2.0; println(list_knobs("HSR")); println(list_knobs("HSR.power"))'` prints three then two paths; expected two then one. Log: `probes/U26/derivative_path_probe.log`.

### LEAD U26-8 [Minor, confidence med] src/knobs/Knobs.jl:780
Claim: the documented plain-syntax pattern (`@knob ip.x = ...` then `ip.x` / `ip.x = ...`, `docs/knob_control.md:61-69`, the `@knob` docstring) works at top level but, inside one function body, already triggers Julia 1.12's world-age deprecation — "Detected access to binding `Main.fn_root` in a world prior to its definition world ... This code will error in future versions of Julia" — and neither docstring nor design note carries the caveat. (Out of hypothesis; forward-compatibility of the documented API.)
Mechanism: `_ensure_knob_root` creates the namespace `const` with `Core.eval` at run time; Octopus's own accesses go through `Base.invokelatest` (764-768, 779) but user code compiled before the binding existed does not. Each top-level statement is a new world, so the examples are silent.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus -e 'using Octopus; function f(); @knob fn_root.x = 1.5; return fn_root.x; end; println(f())'` prints the WARNING block then `1.5`; with `--depwarn=error` it throws (the future behaviour). Log: `probes/U26/derivative_path_probe.log`.

### LEAD U26-9 [Minor, confidence low] src/knobs/Knobs.jl:646
Claim: `knob_value(x::Real) = Float64(x)` casts every plain number to `Float64` — `knob_value(big(1.0))::Float64`, `knob_value(1) == 1.0` — and raises a bare `MethodError` on a `ForwardDiff.Dual`, against the docstring ("the result has the knob's declared type") and the comment at 675-681 that refuses exactly this cast in `_eval_knob_node` because it throws a derivative away silently. (Out of hypothesis.)
Mechanism: an undocumented convenience method; no `src/` caller (grep `knob_value(` outside `src/knobs/` finds only expression arguments), so the blast radius is user code that funnels mixed number-or-expression parameters through `knob_value`.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus -e 'using Octopus; println(typeof(knob_value(big(1.0))), " ", repr(knob_value(1)))'` prints `Float64 1.0`. Logs: `probes/U26/knob_semantics_probe.log`, `forwarddiff_package_probe.log` ("knob_value(::Real) on a dual: MethodError").

### LEAD U26-10 [Minor, confidence low] src/knobs/symbolic.jl:329
Claim: the script-mode gate `const _HAS_SYMBOLICS_SCRIPT_MODE = try @eval import Symbolics; true catch false end` turns every failure — a broken or non-precompilable Symbolics, a version conflict — into "adapter inactive" with a directed error that tells the user to install Symbolics; and it resolves against the whole `LOAD_PATH`, not "the active project" as symbolic.jl:55, 67, 327, `docs/knob_control.md:249` and `src/Octopus.jl:164` say. The same pattern sits at `src/Octopus.jl:169-175` for ForwardDiff (seam). (Hypothesis 2; defect classes 6 and 14.)
Mechanism: a bare `catch` swallows the error class; `import` inside `Main.Octopus` goes through the default stack `["@", "@v#.#", "@stdlib"]`, so which rules a developer's script-mode Octopus has depends silently on their default environment. Measured: under `--project=.` with no Symbolics in the Octopus manifest, Symbolics activated from `~/.julia/environments/v1.12`.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U26/load_modes_script_probe.jl` prints `LOAD_PATH=["@", "@v#.#", "@stdlib"]`, `identify_package(ForwardDiff) = nothing`, `identify_package(Symbolics) = ...QcpTa/src/Symbolics.jl`, `_HAS_SYMBOLICS_SCRIPT_MODE=true`. Log: `probes/U26/load_modes_script_probe_A.log`.

### LEAD U26-11 [Minor, confidence low] src/knobs/Knobs.jl:1074
Claim: `resolve_knobs` evaluates every knob parameter (each `knob_value` takes and releases `_KNOB_LOCK` separately) and only then records `epoch=knob_epoch()`, so a `set_knob!` interleaved between the evaluations and the read stamps the `:knob_resolution` receipt with an epoch newer than the values it carries. (Hypothesis 3; defect class 7/11, receipt only.)
Mechanism: the recompilation gates are safe — `Tasks.jl:1663` and `interface.jl:3249` read the epoch BEFORE compiling and write the cache only after a successful compile, so a mutation during compile is caught at the next `execute!` — but the receipt, the thing "assert what the run recorded" points a reader at, can pair new epoch with old values. Reading the epoch once before the loop, or holding the lock across the resolution, closes it. Not measured (needs a concurrent mutator).
Repro: by reading: in `src/knobs/Knobs.jl`, `grep -n "epoch=knob_epoch()"` lands after the `for (key, value) in params(spec)` loop that calls `_resolve_knob_param` → `knob_value`.

## Clean

Each item names what was compared with what, and the number.

- Hypothesis 1, epoch and cache on every mutation path (probe 1, package mode): three new
  declarations move the epoch by 0 (the U13-7 skip); `set_knob!` +1 with both dependent caches
  cleared and `c` re-evaluating 3.0 → 6.0; namespace assignment +1 (9.0); `@knob a = 4.0` +1
  (12.0); `@knob b = a*3` (expression redefinition) +1 (16.0); `@knob a::Float32` on an exact
  value +1 with the dependent cache cleared (the U13-1 type-change rule); the same retype again
  +0; independent → dependent conversion +1 (20.0); `_forget_knob!` +1 with both downstream
  caches cleared and evaluation refusing "unknown knob d"; re-declaring the forgotten name +0 and
  `c` re-evaluates to 40.0 through the already-bumped epoch; bare declaration + retype of an
  unassigned knob +0; `::Real → ::Float64` on an unchanged Float64 value +0; `reset_knobs!` +1.
  The symbolic adapter has no registry mutation path (`knob_from_symbolic` only builds a tree),
  so there is no "symbolic rebind" to invalidate. The no-bump-on-new-name argument
  (Knobs.jl:320-342) holds because both removal paths bump and both gates read the epoch before
  compiling and cache after success (Tasks.jl:1653-1670, interface.jl:3241-3252, read).
- Detector/resolver parity (read): `_param_has_knob` and `_resolve_knob_param` recurse over the
  same `Tuple`/`NamedTuple`/`AbstractArray` shapes; `_has_knob_parameters` covers `Tuple`,
  `AbstractVector`, `ElementSpec`, `LineEntry` (spec + overrides) and `ElementSpec{:line}`
  (params + entries, beam_line.jl:160-165). `grep "<: AbstractElementSpec" src/` finds only
  `ElementSpec{Kind}`; `TurnModulated` is a runtime `AbstractTrackOp` built by `compile_runtime`,
  so the spec-level walk has no wrapper type to miss. The suite pins the detector at
  `test/runtests.jl:16358-16367`.
- Hypothesis 3, the receipt (probe 1): `:knob_resolution` carries `element=:quadrupole`, the
  epoch, and `resolved=(:kn => (0.0, 0.3),)`; after `set_knob!` the next compile's receipt holds
  epoch+1 and `(0.0, 0.4)`, and `compile_runtime(spec).kn == (0.0, 0.4)`. A `::Symbol` knob
  resolves to `:bmad::Symbol`. Evaluation order is the tree's (post-order, memoized per knob
  under the lock); there are no units in the knob layer (documented, `docs/knob_control.md` §5).
- Guards from earlier audits still fire (probe 1 first run, probe 5): `@knob ascii.x` refused
  because `Main.ascii` names a function (U14-4, registry untouched); `@knob_expr(m.curent)`,
  `set_knob!` and `knob_dependents` on the typo refuse; named constants cannot be knob names
  (read, 404-408); dependency cycles are rejected through the old expression of the knob being
  redefined (read, 351-352); `@knob k2 = -5` is independent (U13-8 fold).
- Derivative table (symbolic.jl:183-258) checked rule by rule against the chain rule by reading:
  `+` (n-ary), unary and binary `-`, n-ary product rule, quotient, `^` with constant and general
  exponent, `sqrt`, `cbrt`, `inv`, `abs → sign`, `exp`, `log`, `log10`, `sin`, `cos`, `tan`,
  `asin`, `acos`, `atan`, `sinh`, `cosh`, `tanh`; `sign`, `min`, `max`, two-argument `log` and
  `atan` throw as documented. Probe 2: native `∂/∂m.current` of `m.k1*m.brho + m.k1 -
  2 m.current²/√m.xfer` is −17888.4932 (chains through `m.k1`) against Symbolics' −17888.5438
  (treats `m.k1` as free); the 0.0506 difference is exactly `xfer + xfer/brho`, so both are
  right under their stated semantics. The example's finite-difference check lives in
  `examples/knob_control.jl:185-191`.
- Printing/parsing round trip: the U14-2 / U13-8 / U20-2 cases (negated literals, `-Inf`,
  same-precedence nesting) read correct; `(-2.0)^2` round-trips (probe 1 control). Only the
  `-0.0` literal fails (U26-2).
- Hypothesis 2 and 4, Symbolics (probes 2, 3): package mode — no extension and a directed error
  before `using Symbolics`, `OctopusSymbolicsExt` attached after, `knob_symbolics_available()`
  true, `knob_from_symbolic(knob_symbolic(e))` evaluates to the same number (relative
  difference 0.0), function-value heads `+ * / ^ sqrt` and rational constants mapped back,
  undeclared variable refused. Script mode — the adapter activates at include when Symbolics is
  importable, and `Base.get_extension(Main.Octopus, ·)` is `nothing` for all three extensions in
  every script-mode run, exactly as `docs/experiences.md:504-545` records. `__init__`
  registration (ext) vs top-level registration (script) both reach `_SYMBOLIC_ADAPTER`.
- Hypothesis 2, ForwardDiff (probes 3B, 6): package mode — before `using ForwardDiff` the core
  has 1 `faddeeva_w` method, 3 `_near_round_conditioning_factor` methods, `_linearize(FD)` throws
  the directed two-route message and `_forward_diff_linearization_available()` is false; after,
  the extension attaches and each count gains one method from `OctopusForwardDiffExt`. Rule 1:
  `Dual{Float64}` → 64.0, `Dual{Float32}` → 8.0, nested `Dual{Dual{Float64}}` → 64.0,
  `Dual{Float16}` refused by the core's own error. Rule 2: the holomorphic Faddeeva derivative
  against central differences (h = 1e-6) at four points — relative differences 1.8e-10, 8.8e-11,
  2.5e-9, 6.7e-13 (x-direction) and ≤ 3.3e-10 (y-direction), primal bitwise equal to the real
  evaluation, Cauchy–Riemann `g_y == i·g_x` exact (0.0). Rule 3: `_linearize(ForwardDiff)` vs
  the complex step on a compiled quadrupole and thin crab cavity, max |ΔJ| 5.6e-17 and 2.2e-19
  with max |J| ≈ 1; `one_turn_matrix(quad; method=ForwardDiffLinearization())` records the method
  in its provenance. Rule 4: `_is_method_number` true for a `Dual` value and type, false for
  `Float64` and `Complex`; `_involves_method_number` walks `Vector{Dual}` and
  `Tuple{Dual,Float64}`. Script mode with ForwardDiff importable: `_HAS_FORWARDDIFF_SCRIPT_MODE=true`
  and the `_linearize` method present inside `Main.Octopus` with no extension (shared rules file).
- Knobs through duals (probe 6): a `::Float64` dependent knob refuses a dual loudly
  ("declared ::Float64; cannot convert Dual..."), a `::Real` dependent carries it
  (`Dual(6.0, 3.0)`), `knob_value(@knob_expr(ad.a^2))` is `Dual(4.0, 4.0)`, and
  `compile_runtime` of a spec whose `kn` holds a dual knob yields a
  `LatticeMagnet{Symplectic6DMap, Dual{…}}` with `kn = (Dual(0,0), Dual(0.2, 0.1))`.
- Hypothesis 4, MPI (probes 4, 7): all 21 `_mp_*` core/extension pairs have exactly two methods
  and `which` sends an `MPI.Comm`/`MPIBackendTag` call to `OctopusMPIExt` and a
  `Nothing`-communicator call to `Octopus` — no shadowing in either direction; the core's
  wrappers convert `root`, `dest`, `tag` to `Int` before the `_impl` call (Policies.jl:684, 697,
  1086, 1090) so the extension's `::Int` signatures match. At 2 ranks: `_mp_allsum_impl!` is
  bitwise equal to the rank-ordered fold `((0 + A_0[i]) + A_1[i])` at n = 5, 2047 (gather path),
  2048, 4096, 5000 (reduce-scatter path, odd sizes exercising the padding), and every rank holds
  rank 0's bits; `_mp_exchange_columns_impl` delivers sender-rank-ordered, sender-column-ordered
  columns with the right per-sender counts; `_mp_gather_rows_impl` gathers in rank order on rank 0
  and returns a 0-row matrix elsewhere; `allminmax`, `allmin!`, `allmax!`, `bcast!` (root 1),
  scalar bcast of a tuple all correct; `all_ok=true` on both ranks.
- Load order and precompile safety (read): `_KNOB_OPERATOR_SYMBOLS` is defined in symbolic.jl
  and only called at run time by `_lower_knob`; the Symbolics registration mutates a `Ref` in
  `__init__`, the ForwardDiff rules are method definitions, and `[weakdeps]`/`[extensions]` in
  `Project.toml` name all three extensions with their triggers.
- Lock discipline (read): every registry read and write is under the `ReentrantLock`
  `_KNOB_LOCK`, including the memoizing fill in `_knob_value_locked`.

Style only, not leads: `_kmul`/`_kdiv` fold `0*x → 0` and `0/x → 0` (standard symbolic
convention, wrong only at `Inf`/`NaN` operands); the `@knob` macro builds the `rhs_thunk`
closure for `Real` knobs too, where it is never called; `_lower_knob` converts every literal to
`Float64` (an `Int128` literal rounds silently — documented as "numeric literal").

## Unchecked

- MPI at more than 2 ranks, and the point-to-point extension methods (`_mp_isend_impl`,
  `_mp_irecv_impl!`, `_mp_wait_all_impl`, `_mp_test_all_impl`, `_mp_wait_any_impl`) were read
  but not executed; the dataflow protocol that drives them is another unit's region.
- `Symbolics.toexpr` heads for every whitelisted operator: only `+ * / ^ sqrt` and rational
  constants were exercised; a head Symbolics emits that is not in `_KNOB_OPERATOR_SYMBOLS`
  (e.g. `ifelse`, `NaNMath` functions) was not provoked — by reading it throws the whitelist error.
- The ForwardDiff rules were exercised numerically in package mode only; in script mode only
  the flag and method presence were measured (the rules are one shared file).
- The receipt race of U26-11 was not measured (no concurrent mutator probe).
- The wiring view `knob_report(elements)` beyond its use of `knob_dependencies`
  (`beam_line.jl:840-930`) is outside the region and was read only for the seam.
- `faddeeva_w(::Complex{Float32})` primal correctness: the Float32 dual evaluation returned
  finite numbers but was not compared against a reference.
- The documented buffer-reuse contract of `_mp_exchange_columns_impl` (the caller must be done
  with a receive matrix before the next exchange of the same shape) was not probed.
