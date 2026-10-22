export knob_derivative, knob_symbolic, knob_from_symbolic,
       knob_symbolics_available

#=
Symbolic layer over the knob expression tree.

Two tiers, both consequences of the expression tree being closed:

1. Native differentiation (`knob_derivative`) — the chain rule over the
   operator whitelist, with constant folding. No dependencies. Derivatives
   chain THROUGH dependent knobs in the registry, so
   `knob_derivative(expr, :current)` is the full sensitivity even when `expr`
   references intermediate knobs defined by their own expressions. This is the
   response-matrix primitive.

2. A `Symbolics.jl` adapter (`knob_symbolic` / `knob_from_symbolic`) — the
   knob tree maps 1:1 onto Symbolics expression trees, enabling simplification, general
   calculus, and code generation. Symbolics is an OPTIONAL dependency,
   declared under `[weakdeps]`: loading Symbolics next to Octopus activates
   the `OctopusSymbolicsExt` package extension, which registers the adapter
   implementation through `_register_symbolic_adapter!` below.

   History, kept because the failure was subtle (audit part 6, R3): the gate
   used to be a bare `import Symbolics` in a `try` here, which resolves
   against the *load path* in script mode (`include("src/Octopus.jl")`)
   and against Octopus's *declared dependencies* in package mode
   (`using Octopus`) — so the adapter worked for developers, who load the
   script form `AGENTS.md` prescribes, and was permanently dead for users and
   for `test/runtests.jl`, with an error message telling them to install a
   package they may already have had. The extension serves package mode; the
   script-mode `include` at the bottom of this file serves developers, since
   the extension loader never runs for a module built by `include`.
=#

# The adapter implementation, registered by `ext/OctopusSymbolicsExt.jl`
# (package mode) or the script-mode include at the bottom of this file. A Ref
# rather than overridable methods, so neither activation route can collide
# with a method defined here (the overwrite trap of audit part 6 §8.7).
const _SYMBOLIC_ADAPTER = Ref{Any}(nothing)
_register_symbolic_adapter!(to, from) =
    (_SYMBOLIC_ADAPTER[] = (to=to, from=from); nothing)
"""True when the Symbolics adapter is active in this session."""
_symbolics_adapter_active() = _SYMBOLIC_ADAPTER[] !== nothing

"""
    knob_symbolics_available()

True when the optional `Symbolics.jl` adapter is active in this session, i.e.
when [`knob_symbolic`](@ref) and [`knob_from_symbolic`](@ref) will work instead
of raising their directed error — the public query for graceful degradation
(scripts that use the adapter when present and skip it otherwise). In package
mode (`using Octopus`) the adapter activates when the session loads Symbolics
(`using Symbolics`) through the `OctopusSymbolicsExt` weak-dependency
extension; in script mode (`include("src/Octopus.jl")`) it activates during the
include when Symbolics is importable from the load path (the active project and
the environments stacked after it); a Symbolics that is importable but fails to
load leaves the adapter inactive with a warning naming the error. Everything
else in the knob system, including [`knob_derivative`](@ref), never needs
Symbolics.
"""
knob_symbolics_available() = _symbolics_adapter_active()
function _symbolic_adapter()
    impl = _SYMBOLIC_ADAPTER[]
    impl === nothing && throw(ArgumentError(
        "the Symbolics adapter is not active. Load Symbolics in this session " *
        "(`using Symbolics`, installing it first if needed): Octopus declares " *
        "it as a weak dependency, so the OctopusSymbolicsExt extension then " *
        "activates automatically. In script mode " *
        "(`include(\"src/Octopus.jl\")`) the adapter instead activates during " *
        "the include when Symbolics is importable from the load path (a " *
        "warning at the include names a Symbolics that failed to load). " *
        "The knob system itself, including knob_derivative, has no such " *
        "dependency and is unaffected."))
    return impl
end

# Reverse operator map (function object -> whitelist symbol), used when lowering
# Julia `Expr`s that carry function *values* — e.g. `Symbolics.toexpr` output.
const _KNOB_OPERATOR_SYMBOLS = Dict{Function,Symbol}(
    spec[1] => name for (name, spec) in _KNOB_OPERATORS
)

# ---------------------------------------------------------------------------
# Simplifying constructors (constant folding, identity elimination)
# ---------------------------------------------------------------------------

_kconst(x) = KnobConst(Float64(x))
_is_const(n, v) = n isa KnobConst && n.value == v

function _kadd(a::AbstractKnobExpression, b::AbstractKnobExpression)
    a isa KnobConst && b isa KnobConst && return _kconst(a.value + b.value)
    _is_const(a, 0.0) && return b
    _is_const(b, 0.0) && return a
    return KnobCall(:+, AbstractKnobExpression[a, b])
end

function _ksub(a::AbstractKnobExpression, b::AbstractKnobExpression)
    a isa KnobConst && b isa KnobConst && return _kconst(a.value - b.value)
    _is_const(b, 0.0) && return a
    _is_const(a, 0.0) && return KnobCall(:-, AbstractKnobExpression[b])
    return KnobCall(:-, AbstractKnobExpression[a, b])
end

_kneg(a::AbstractKnobExpression) =
    a isa KnobConst ? _kconst(-a.value) : KnobCall(:-, AbstractKnobExpression[a])

function _kmul(a::AbstractKnobExpression, b::AbstractKnobExpression)
    a isa KnobConst && b isa KnobConst && return _kconst(a.value * b.value)
    (_is_const(a, 0.0) || _is_const(b, 0.0)) && return _kconst(0.0)
    _is_const(a, 1.0) && return b
    _is_const(b, 1.0) && return a
    return KnobCall(:*, AbstractKnobExpression[a, b])
end

function _kdiv(a::AbstractKnobExpression, b::AbstractKnobExpression)
    a isa KnobConst && b isa KnobConst && return _kconst(a.value / b.value)
    _is_const(a, 0.0) && return _kconst(0.0)
    _is_const(b, 1.0) && return a
    return KnobCall(:/, AbstractKnobExpression[a, b])
end

function _kpow(a::AbstractKnobExpression, b::AbstractKnobExpression)
    a isa KnobConst && b isa KnobConst && return _kconst(a.value ^ b.value)
    _is_const(b, 1.0) && return a
    _is_const(b, 0.0) && return _kconst(1.0)
    return KnobCall(:^, AbstractKnobExpression[a, b])
end

_kcall(op::Symbol, args...) = KnobCall(op, AbstractKnobExpression[args...])

# ---------------------------------------------------------------------------
# Native differentiation
# ---------------------------------------------------------------------------

"""
    knob_derivative(expression, path; through_registry=true)
    knob_derivative(knob_path, path; through_registry=true)

Symbolic derivative of a knob expression (or of a dependent knob's defining
expression) with respect to the knob `path`, returned as a knob expression
with constants folded. Evaluate it with `knob_value`. `path` (and a
`knob_path` first argument) may be a `Symbol("m.k1")`, a `String`, or a
`KnobRef` such as `@knob_expr(m.k1)`; a bare `:m.k1` is not a `Symbol` but
`getproperty(:m, :k1)`.

With `through_registry=true` (default) the chain rule follows *dependent* knobs
through their registered expressions, so the result is the total sensitivity —
the response-matrix entry `∂(parameter)/∂(knob)`:

```julia
@knob m.brho = 81.1
@knob m.xfer = 0.05
@knob m.current = 1000.0
@knob m.k1 = m.current * m.xfer / m.brho
dk1_dI = knob_derivative("m.k1", "m.current")   # -> (m.xfer * m.brho) / m.brho ^ 2.0, i.e. m.xfer / m.brho
```

The differentiation variable is looked up like every other knob argument: an
undeclared or mistyped `path` raises an `ArgumentError` naming it (it used to
yield the constant `0.0`, a silent column of zeros in a response matrix), and
with `through_registry=true` a *dependent* `path` is refused with directions,
because the total derivative with respect to a quantity other knobs define is
not defined (which of its inputs moves?); so is a tree naming a knob since
forgotten, exactly as `knob_value` refuses it.

With `through_registry=false`, every `KnobRef` other than `path` is treated as
an independent symbol (the partial derivative), `path` itself may be a
dependent knob, and no reference is looked up. Non-smooth operators (`abs` at
0 aside, `sign`, `min`, `max`) and the two-argument `log`/`atan` raise an
error rather than returning a wrong branch.
"""
function knob_derivative(x, path_like; through_registry::Bool=true)
    path = _knob_path(path_like)
    node = lock(_KNOB_LOCK) do
        # The variable is validated against the registry FIRST (2026-10-18
        # audit, F-181): before, only `x` was, and a typo in `path` matched no
        # leaf and chained through nothing, so every derivative came out 0.0
        # where set_knob!, knob_value, knob_dependents and @knob_expr refuse
        # the same typo by name.
        entry = get(_KNOB_TABLE, path, nothing)
        entry === nothing && throw(ArgumentError(
            "unknown knob $(path) as the differentiation variable; declare it " *
            "with @knob $(path) (set_knob!, knob_value and @knob_expr refuse " *
            "the same name)"))
        if through_registry && entry.expression !== nothing
            inputs = join(sort!(collect(_knob_direct_dependencies(entry.expression));
                                by=string), ", ")
            throw(ArgumentError(
                "knob $(path) is defined by the expression " *
                "$(_knob_expr_string(entry.expression)); the total derivative " *
                "(through_registry=true) is taken with respect to an independent " *
                "knob: differentiate with respect to its inputs ($(inputs)), or " *
                "pass through_registry=false for the partial derivative that " *
                "treats $(path) as a free symbol"))
        end
        x isa AbstractKnobExpression && return x
        xentry = get(_KNOB_TABLE, _knob_path(x), nothing)
        xentry === nothing && throw(ArgumentError("unknown knob $(_knob_path(x))"))
        xentry.expression === nothing ? KnobRef(_knob_path(x)) : xentry.expression
    end
    return _kderiv(node, path, through_registry, Set{Symbol}())
end

_kderiv(::KnobConst, ::Symbol, ::Bool, ::Set{Symbol}) = _kconst(0.0)

function _kderiv(n::KnobRef, path::Symbol, through::Bool, active::Set{Symbol})
    n.path === path && return _kconst(1.0)
    through || return _kconst(0.0)
    found, expr = lock(_KNOB_LOCK) do
        entry = get(_KNOB_TABLE, n.path, nothing)
        entry === nothing ? (false, nothing) : (true, entry.expression)
    end
    # The registry is being consulted, so a name it does not hold is an error,
    # as it is for knob_value of the same tree -- not an independent symbol: a
    # tree built before _forget_knob!/reset_knobs! used to differentiate
    # without complaint (2026-10-18 audit, F-181).
    found || throw(ArgumentError(
        "unknown knob $(n.path) referenced by the expression being " *
        "differentiated; declare it with @knob $(n.path), or pass " *
        "through_registry=false to treat every reference as a free symbol"))
    expr === nothing && return _kconst(0.0)
    n.path in active && throw(ArgumentError("knob dependency cycle at $(n.path)"))
    push!(active, n.path)
    d = _kderiv(expr, path, through, active)
    delete!(active, n.path)
    return d
end

function _kderiv(n::KnobCall, path::Symbol, through::Bool, active::Set{Symbol})
    d(a) = _kderiv(a, path, through, active)
    a = n.args
    op = n.op
    if op === :+
        out = d(a[1])
        for i in 2:length(a)
            out = _kadd(out, d(a[i]))
        end
        return out
    elseif op === :-
        length(a) == 1 && return _kneg(d(a[1]))
        return _ksub(d(a[1]), d(a[2]))
    elseif op === :*
        out = _kconst(0.0)
        for i in eachindex(a)
            term = d(a[i])
            for j in eachindex(a)
                j == i && continue
                term = _kmul(term, a[j])
            end
            out = _kadd(out, term)
        end
        return out
    elseif op === :/
        num = _ksub(_kmul(d(a[1]), a[2]), _kmul(a[1], d(a[2])))
        return _kdiv(num, _kpow(a[2], _kconst(2.0)))
    elseif op === :^
        base, expo = a[1], a[2]
        if expo isa KnobConst
            return _kmul(_kmul(expo, _kpow(base, _kconst(expo.value - 1))), d(base))
        end
        # general a^b: a^b * (db*log(a) + b*da/a)
        return _kmul(_kpow(base, expo),
                     _kadd(_kmul(d(expo), _kcall(:log, base)),
                           _kdiv(_kmul(expo, d(base)), base)))
    elseif op === :sqrt
        return _kdiv(d(a[1]), _kmul(_kconst(2.0), _kcall(:sqrt, a[1])))
    elseif op === :cbrt
        return _kdiv(d(a[1]),
                     _kmul(_kconst(3.0), _kpow(_kcall(:cbrt, a[1]), _kconst(2.0))))
    elseif op === :inv
        return _kneg(_kdiv(d(a[1]), _kpow(a[1], _kconst(2.0))))
    elseif op === :abs
        return _kmul(_kcall(:sign, a[1]), d(a[1]))
    elseif op === :exp
        return _kmul(_kcall(:exp, a[1]), d(a[1]))
    elseif op === :log && length(a) == 1
        return _kdiv(d(a[1]), a[1])
    elseif op === :log10
        return _kdiv(d(a[1]), _kmul(_kconst(log(10.0)), a[1]))
    elseif op === :sin
        return _kmul(_kcall(:cos, a[1]), d(a[1]))
    elseif op === :cos
        return _kneg(_kmul(_kcall(:sin, a[1]), d(a[1])))
    elseif op === :tan
        return _kmul(_kadd(_kconst(1.0), _kpow(_kcall(:tan, a[1]), _kconst(2.0))), d(a[1]))
    elseif op === :asin
        return _kdiv(d(a[1]),
                     _kcall(:sqrt, _ksub(_kconst(1.0), _kpow(a[1], _kconst(2.0)))))
    elseif op === :acos
        return _kneg(_kdiv(d(a[1]),
                           _kcall(:sqrt, _ksub(_kconst(1.0), _kpow(a[1], _kconst(2.0))))))
    elseif op === :atan && length(a) == 1
        return _kdiv(d(a[1]), _kadd(_kconst(1.0), _kpow(a[1], _kconst(2.0))))
    elseif op === :sinh
        return _kmul(_kcall(:cosh, a[1]), d(a[1]))
    elseif op === :cosh
        return _kmul(_kcall(:sinh, a[1]), d(a[1]))
    elseif op === :tanh
        return _kmul(_ksub(_kconst(1.0), _kpow(_kcall(:tanh, a[1]), _kconst(2.0))), d(a[1]))
    end
    throw(ArgumentError(
        "knob_derivative is not implemented for operator $(op) with " *
        "$(length(a)) argument(s) (non-smooth or multi-branch)"))
end

# ---------------------------------------------------------------------------
# Symbolics.jl adapter (optional dependency)
# ---------------------------------------------------------------------------

"""
    knob_symbolic(expression)
    knob_symbolic(knob_path)

Convert a knob expression (or a dependent knob's defining expression) to a
`Symbolics.jl` expression, with one Symbolics variable per referenced knob,
named by its full path. Requires `Symbolics` to be loadable from your
environment (`import Pkg; Pkg.add("Symbolics")`); everything else in the knob
system works without it. Convert back with [`knob_from_symbolic`](@ref).
"""
function knob_symbolic(x)
    adapter = _symbolic_adapter()
    node = x isa AbstractKnobExpression ? x : lock(_KNOB_LOCK) do
        entry = get(_KNOB_TABLE, _knob_path(x), nothing)
        entry === nothing && throw(ArgumentError("unknown knob $(_knob_path(x))"))
        entry.expression === nothing ? KnobRef(_knob_path(x)) : entry.expression
    end
    return adapter.to(node)
end

"""
    knob_from_symbolic(symbolic_expression)

Convert a `Symbolics.jl` expression back to the knob expression tree, through the same
lowering and whitelist validation as `@knob_expr`. Variables must be named by
knob paths (as produced by [`knob_symbolic`](@ref)); referenced knobs must be
declared. Round trip: `knob_from_symbolic(knob_symbolic(e))` is equivalent to
`e` up to algebraic normalization by Symbolics.
"""
knob_from_symbolic(x) = _symbolic_adapter().from(x)

"""
Build and register the adapter against a loaded `Symbolics` module.

Called from `OctopusSymbolicsExt.__init__` in package mode -- at `__init__`
and not at the extension's top level, because a top-level registration runs
during PRECOMPILATION and its mutation of `_SYMBOLIC_ADAPTER` is discarded
with the precompile process -- and from the script-mode activation below.
Closures over the module argument rather than methods dispatching on
Symbolics types, so both routes share one implementation and neither can
overwrite a method defined here (audit part 6 §8.7).
"""
function _activate_symbolics_adapter!(S::Module)
    to(n) = n isa KnobConst ? n.value :
            n isa KnobRef ? S.variable(n.path) :
            n isa KnobCall ? _KNOB_OPERATORS[n.op][1]((to(a) for a in n.args)...) :
            throw(ArgumentError("unexpected knob expression node $(typeof(n))"))
    function from(x)
        # Symbolics.Num is <: Real, so unwrap it before the literal branch.
        x isa S.Num && return from(S.toexpr(x))
        x isa Real && return KnobConst(Float64(x))
        node = _lower_knob(x)
        lock(_KNOB_LOCK) do
            _validate_refs_locked(node)
        end
        return node
    end
    _register_symbolic_adapter!(to, from)
    return nothing
end

"""
    _script_mode_weakdep_gate(name, attempt) -> Bool

Run `attempt()` -- the `import` of the weak dependency `name` -- and say
whether it succeeded. An `ArgumentError` is the import's own not-available
verdict (package mode: Octopus declares no such strong dependency; script
mode: nothing in the load path provides it) and closes the gate quietly. Any
other error means the package is importable and FAILED TO LOAD (a broken
precompile, a version conflict): that is reported with a warning naming the
package and the error, and the gate still closes, so an include never dies on
an optional package and never hides its failure either. The gate used to be a
bare `catch`, which turned every failure into "install Symbolics" (2026-10-18
audit, F-184).
"""
function _script_mode_weakdep_gate(name::Symbol, attempt)
    try
        attempt()
        return true
    catch err
        err isa ArgumentError && return false
        @warn "the optional package $(name) is importable but failed to load; " *
              "its Octopus adapter stays inactive" exception=(err, catch_backtrace())
        return false
    end
end

# Script mode: a module built by `include("src/Octopus.jl")` never triggers
# the package-extension loader, so activate the adapter here when Symbolics is
# importable from the load path (the active project and the environments
# stacked after it). In package mode this `import` throws (Symbolics is a
# weak, not strong, dependency) and the extension takes over.
const _HAS_SYMBOLICS_SCRIPT_MODE =
    _script_mode_weakdep_gate(:Symbolics, () -> @eval import Symbolics)
_HAS_SYMBOLICS_SCRIPT_MODE && _activate_symbolics_adapter!(Symbolics)
