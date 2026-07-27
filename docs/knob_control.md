# Knob Control: Deferred Parameter Expressions

Design note for the `@knob` subsystem (`src/knobs/Knobs.jl`,
`src/knobs/symbolic.jl`). A knob is a named value such as
`HSR.power_supply.arc_quad`; element parameters may be *expressions* over
knobs, stored as data and evaluated when the tracking line or lattice is
built. One knob then drives many element parameters — the classic
`Q1.K1 = K`, `Q2.K1 = -K` pattern, or a single half-crossing-angle knob
feeding the Lorentz boost pair and every crab-cavity strength.

## 1. Design: expressions stored as data

A knob-controlled parameter is stored as a small **closed expression tree** —
an *intermediate representation*, meaning the formula is kept as a plain data
structure rather than as executable code. Three node types:

- `KnobRef` — a reference to a knob by flattened path;
- `KnobConst` — a numeric literal;
- `KnobCall` — a whitelisted operator (`+ - * / ^`, `sqrt`, trig/hyperbolic,
  `exp`/`log`, `abs`, `min`/`max`, …) applied to child expressions.

Storing the formula as data is the accelerator-code mainstream: MAD-X deferred
expressions (`:=`) and Xsuite's `xdeps` dependency system are both expression
trees with explicit dependency graphs, and Octopus follows that line. Keeping
the tree *closed* — exactly these three node types over a fixed operator
whitelist, rather than arbitrary Julia code — is what buys every property this
codebase's rules ask for (`AGENTS.md`): definition-time validation (unknown
knobs, unsupported operators, wrong arities, dependency cycles are all
immediate errors — never silent), lossless printing
(`knob_expression(string(e)) == e`), plain-struct serialization, static
dependency extraction, native symbolic differentiation, and a 1:1 mapping to
external symbolic packages. Knob expressions are data, not programs: there is
deliberately no control flow. If an operation is genuinely missing, extend the
whitelist with a *named pure function* — the name stays in the stored tree, so
introspection degrades gracefully instead of silently.

## 2. Semantics

**Declaration and types.** `@knob path.to.name` declares an independent knob
(unset; evaluating it before assignment is an error, never a default).
`@knob path.to.name::T` declares its value type — the default is `Float64`,
and assigned values are converted to the declared type (a lossy assignment
such as `1.5` into an `Int` knob is an error, never a truncation).
`@knob path = 1000.0` declares-and-assigns. `@knob path = expression` declares
a *dependent* knob; `@knob a = b` is an alias. Dependent knobs require a
`Real` declared type (expressions evaluate numerically); non-`Real` knobs
(`Symbol`, `Bool`, ...) hold plain values and can drive non-numeric element
parameters through a bare knob reference. Every knob referenced by an
expression must already be declared — declaration-before-use is what catches
typos at definition time. Redefinition is allowed and rewires the dependency
graph; cycles are rejected.

**Namespaces are names, not modules.** `HSR.power_supply.arc_quad` is
flattened to the single key `Symbol("HSR.power_supply.arc_quad")` in a flat
registry; `list_knobs("HSR.power_supply")` and `knob_report(prefix="HSR")`
give the hierarchical views.

**Assignment.** Declaring a dotted knob binds its root namespace (`HSR`, `ip`,
...) as a `KnobNamespace` constant in the calling module, so afterwards plain
Julia syntax reads and writes knobs — no strings:

```julia
@knob ip.half_crossing_angle::Float64 = 12.5e-3
ip.half_crossing_angle              # read: 0.0125
ip.half_crossing_angle = 15.0e-3    # assign
```

The exported `knobs` constant is the root namespace covering every knob, which
is also the assignment path for *undotted* knobs (`@knob x` then
`knobs.x = 1.0`) — a bare global name cannot intercept `x = 1.0`, which in
Julia simply rebinds the variable. The macro form `@knob x = 1.0` and the
programmatic form `set_knob!(:x, 1.0)` (accepting `Symbol`, `String`, or
`KnobRef`) do the same thing; all of them convert to the declared type,
invalidate dependents, and bump the epoch.

**Mutation and invalidation.** Assigning a dependent knob is an error (change
its inputs or redefine it). Dependent values are memoized and invalidated
transitively through the reverse dependency edges. Every mutation bumps a
global epoch (`knob_epoch()`).

**Evaluation point.** Element parameters carry expressions through the
flexible constructor,

```julia
q1 = ElementSpec{:crab_dispersion}(;
    zeta1 = @knob_expr(HSR.power_supply.arc_quad * HSR.current_transfer / HSR.B_rho),
    zeta2 = 0.0, zeta3 = 0.0, zeta4 = 0.0,
    tracking_method = Symplectic6DMap())
```

and are resolved at exactly one place: `compile_runtime` calls
`resolve_knobs(spec)` immediately before the runtime constructor, replacing
every knob expression (scalars and tuples of scalars) with values. Runtime
tracking objects therefore never carry knobs — they stay compact, isbits, and
GPU-compatible, and the kernels are untouched. Each resolution emits a
`:knob_resolution` execution-audit receipt naming the element kind, epoch, and
resolved values.

**Binding an existing element.** Element parameters are properties of the
spec, so an element defined first can be bound to a knob afterwards:

```julia
q1 = ElementSpec{:crab_dispersion}(; zeta1 = 0.0, zeta2 = 0.0, zeta3 = 0.0,
    zeta4 = 0.0, tracking_method = Symplectic6DMap())
q1.zeta1 = @knob_expr(HSR.arc_k1)     # live binding
```

Property assignment is validated against the element's registered parameter
schema (unknown names are typos and are rejected with the valid list; new
metadata keys go through `spec.params[:key] = value`), and every in-place
parameter mutation bumps a global *spec epoch* that task caches check next to
the knob epoch — so a binding added after a task was built reaches that task
at its next `execute!`, exactly like a knob assignment. One trap to know:
`q1.zeta1 = HSR.arc_k1` (without `@knob_expr`) reads the knob's *current
value* through the namespace and binds a constant snapshot; only
`@knob_expr(...)` stores the live expression.

Two consequences to know:

- The **flexible form is required**. The friendly constructors
  (`CrabDispersionSpec(...)`, `LorentzBoostSpec(...)`, …) convert parameters
  eagerly (`T(value)`), which cannot defer; handing them a knob expression
  raises a directed error. The flexible form must supply every parameter its
  runtime constructor reads, exactly as each element's `construction_help`
  documents.
- **Task recompilation is epoch-based.** `TrackingTask` and `StrongStrongTask`
  cache compiled runtime lines; lines containing knob parameters record the
  epoch and recompile when it has moved. A knob assignment therefore reaches
  an already-constructed task at its **next `execute!`**. Mid-execution
  turn-dependent modulation remains the job of `ScheduledAction`/`update!`
  (see `weak_strong_6d_model.md` §6); extending the epoch check into the turn
  loop is recorded as future work below.

**Verification.** `validate(KnobEffectivenessContract())` checks the whole
chain at the consumer boundary: a knob-driven element tracks identically to
its directly-parameterized twin; a knob assignment recompiles the same task
object; the audit receipt is emitted; and the unset/cycle/dependent-set guards
fire. Knob entry points are listed in `docs/registry_snapshot.md` ("Knob
Control").

## 3. The symbolic layer

Two tiers, both consequences of the closed expression tree
(`src/knobs/symbolic.jl`):

**Native differentiation, zero dependencies.** `knob_derivative(expr, path)`
applies the chain rule over the whitelist with constant folding, and — with
`through_registry=true` (default) — chains *through* dependent knobs'
registered expressions. `knob_derivative(@knob_expr(HSR.k1),
@knob_expr(HSR.power_supply.arc_quad))` is therefore the total sensitivity
`∂k₁/∂I`, the response-matrix primitive (tune knobs, orthogonal knob
construction). Results are valid but only lightly simplified; feed them to the
Symbolics adapter for aggressive simplification. Non-smooth operators (`sign`,
`min`, `max`, two-argument `log`/`atan`) refuse differentiation rather than
return a wrong branch.

**Symbolics.jl adapter, optional.** `knob_symbolic(expr)` builds a Symbolics
expression with one variable per knob path; `knob_from_symbolic` converts back
through the same lowering and validation (function-object heads from
`Symbolics.toexpr` are mapped back through the whitelist). Symbolics is loaded
with the same optional pattern as CUDA in `src/beam/Beam.jl`: install it in an
environment on your load path (`import Pkg; Pkg.add("Symbolics")`) and the
adapter activates; without it, only these two functions error (with
instructions) and everything else — including `knob_derivative` — works. The
universal bridge `knob_to_expr`/`knob_expression` (expression tree ↔ Julia
`Expr`/string) needs no packages at all and is the interface any other
symbolic tool can target.

## 4. Limitations and future work

- **Scalar-shaped values.** A knob holds one value of its declared type;
  expressions resolve scalar and tuple-of-scalar element parameters. No units,
  no array-valued knobs.
- **Next-`execute!` granularity.** Knob changes land when the line is next
  compiled, not mid-execution; per-turn knob ramps inside one `execute!` call
  would need the epoch check moved into the turn loop (and per-turn
  `resolve_knobs` cost accounting) — the clean extension, not done yet.
- **Bare names need `knobs.` or the macro for assignment.** Plain `x = 1.0`
  rebinds a Julia global and cannot be intercepted; only dotted knobs get
  native assignment syntax. This is a language constraint, and one more reason
  knobs are namespaced.
- **Simplification is minimal** (constant folding and identity elimination in
  the derivative's smart constructors). By design: the stored tree is a
  faithful record of what the user wrote; use the Symbolics adapter to
  normalize.
- **The registry is global state**, guarded by a lock; `reset_knobs!()` wipes
  it (tests). Serialization of specs holding knob expressions round-trips as
  plain structs, but the registry itself is not persisted with them — a saved
  lattice needs its knob definitions re-declared (or a future
  `save_knobs`/`load_knobs` pair).

## 5. Precedents

MAD-X deferred expressions (`:=`), Bmad/Tao overlays and groups, and Xsuite
`xdeps` (expression trees + dependency graph; the closest relative).
