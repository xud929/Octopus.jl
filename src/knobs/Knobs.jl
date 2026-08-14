export AbstractKnobExpression, KnobRef, KnobConst, KnobCall, KnobNamespace,
       @knob, @knob_expr, knobs,
       set_knob!, knob_value, knob_expression, knob_to_expr,
       list_knobs, knob_report, knob_dependencies, knob_dependents,
       knob_epoch, reset_knobs!, resolve_knobs

#=
Knob control (deferred parameter expressions).

A knob is a named value with a hierarchical path such as
`HSR.power_supply.arc_quad`. Element parameters may be *expressions* over knobs
instead of numbers; the expression is stored as a small closed expression tree
(an intermediate representation: the formula kept as data, not as executable
code) and is resolved to a value when `compile_runtime` builds the runtime
element. Design rationale and semantics are in `docs/knob_control.md`.

The expression tree is deliberately closed: knob references, numeric literals,
and a whitelisted operator set. That is what makes an expression printable,
serializable, statically analyzable for its dependency graph, convertible
to/from Julia `Expr` for symbolic packages, and validated at definition time
(unknown knobs and unsupported functions are immediate errors, never silent).
=#

# ---------------------------------------------------------------------------
# Expression tree
# ---------------------------------------------------------------------------

"""
    AbstractKnobExpression

Closed expression tree for knob-controlled parameters. Concrete nodes are
[`KnobRef`](@ref) (a reference to a named knob), [`KnobConst`](@ref) (a numeric
literal), and [`KnobCall`](@ref) (a whitelisted operator applied to child
expressions). Build values of this type with [`@knob_expr`](@ref) or
[`knob_expression`](@ref); evaluate with [`knob_value`](@ref); convert to a
Julia `Expr` with [`knob_to_expr`](@ref).

An `AbstractKnobExpression` stored as an `ElementSpec` parameter (through the
flexible `ElementSpec{kind}(; ...)` constructor) is resolved to a number by
`compile_runtime` via [`resolve_knobs`](@ref), so runtime tracking objects
never carry knobs.
"""
abstract type AbstractKnobExpression end

"""Reference to a knob by its flattened hierarchical path, e.g.
`KnobRef(Symbol("HSR.power_supply.arc_quad"))`."""
struct KnobRef <: AbstractKnobExpression
    path::Symbol
end

"""Numeric literal inside a knob expression."""
struct KnobConst <: AbstractKnobExpression
    value::Float64
end

"""Whitelisted operator applied to child knob expressions."""
struct KnobCall <: AbstractKnobExpression
    op::Symbol
    args::Vector{AbstractKnobExpression}
end

Base.:(==)(a::KnobRef, b::KnobRef) = a.path === b.path
# `isequal`, not `==`: tree equality is STRUCTURAL, and the documented
# round-trip invariant `knob_expression(string(e)) == e` must hold for a
# constant-folded NaN too (2026-08-05 audit, U14-2). Consistent with `hash`.
Base.:(==)(a::KnobConst, b::KnobConst) = isequal(a.value, b.value)
Base.:(==)(a::KnobCall, b::KnobCall) =
    a.op === b.op && length(a.args) == length(b.args) &&
    all(a.args[i] == b.args[i] for i in eachindex(a.args))
Base.hash(a::KnobRef, h::UInt) = hash((:knob_ref, a.path), h)
Base.hash(a::KnobConst, h::UInt) = hash((:knob_const, a.value), h)
Base.hash(a::KnobCall, h::UInt) = hash((:knob_call, a.op, Tuple(hash.(a.args))), h)

# The operator whitelist: name => (function, allowed argument-count range).
# Deliberately small and free of control flow; a knob expression is data, not a
# program. Extend only with pure scalar functions.
const _KNOB_OPERATORS = Dict{Symbol,Tuple{Function,UnitRange{Int}}}(
    :+ => (+, 1:32),
    :- => (-, 1:2),
    :* => (*, 2:32),
    :/ => (/, 2:2),
    :^ => (^, 2:2),
    :sqrt => (sqrt, 1:1),
    :cbrt => (cbrt, 1:1),
    :abs => (abs, 1:1),
    :inv => (inv, 1:1),
    :sign => (sign, 1:1),
    :exp => (exp, 1:1),
    :log => (log, 1:2),
    :log10 => (log10, 1:1),
    :sin => (sin, 1:1),
    :cos => (cos, 1:1),
    :tan => (tan, 1:1),
    :asin => (asin, 1:1),
    :acos => (acos, 1:1),
    :atan => (atan, 1:2),
    :sinh => (sinh, 1:1),
    :cosh => (cosh, 1:1),
    :tanh => (tanh, 1:1),
    :min => (min, 2:32),
    :max => (max, 2:32),
)

# Named constants allowed as bare symbols inside expressions. NaN and Inf are
# here because `repr` of a non-finite KnobConst prints exactly these names, and
# accepting them keeps the string round trip total over derivative constant
# folds (2026-08-05 audit, U14-2). Every key is also a FORBIDDEN knob name:
# `_knob_define!` rejects it, because `@knob_expr` would read the name as the
# constant and silently shadow the knob (2026-08-05 audit, U14-3).
const _KNOB_NAMED_CONSTANTS = Dict{Symbol,Float64}(
    :pi => Float64(pi), :π => Float64(pi), :ℯ => Float64(ℯ),
    :NaN => NaN, :Inf => Inf,
)

# ---------------------------------------------------------------------------
# Knob registry
# ---------------------------------------------------------------------------

mutable struct _KnobEntry
    path::Symbol
    type::Type                      # declared value type (default Float64)
    expression::Union{Nothing,AbstractKnobExpression}  # nothing => independent
    value::Any                      # independent: the set value; dependent: cache
    dependents::Set{Symbol}         # direct reverse dependency edges
end

const _KNOB_TABLE = Dict{Symbol,_KnobEntry}()
const _KNOB_LOCK = ReentrantLock()
const _KNOB_EPOCH = Ref{UInt64}(0)

"""
    knob_epoch()

Monotone counter bumped by every knob mutation (`@knob`, `set_knob!`,
`reset_knobs!`). Task runtime caches store the epoch at compile time and
recompile knob-dependent lines when it has moved, so a knob change reaches an
already-constructed task at its next `execute!`.
"""
knob_epoch() = _KNOB_EPOCH[]

_knob_path(path::Symbol) = path
_knob_path(path::AbstractString) = Symbol(path)
_knob_path(ref::KnobRef) = ref.path

# ---------------------------------------------------------------------------
# Lowering: Julia syntax -> expression tree (definition-time validation)
# ---------------------------------------------------------------------------

function _flatten_knob_path(ex)
    ex isa Symbol && return ex
    if ex isa Expr && ex.head === :. && length(ex.args) == 2 && ex.args[2] isa QuoteNode
        return Symbol(string(_flatten_knob_path(ex.args[1]), '.', ex.args[2].value))
    end
    throw(ArgumentError("a knob path must be a dotted name such as " *
                        "HSR.power_supply.arc_quad; got $(repr(ex))"))
end

_strip_block(ex) = ex
function _strip_block(ex::Expr)
    if ex.head === :block
        stmts = [a for a in ex.args if !(a isa LineNumberNode)]
        length(stmts) == 1 && return _strip_block(stmts[1])
    end
    return ex
end

function _lower_knob(ex)
    ex = _strip_block(ex)
    ex isa Real && return KnobConst(Float64(ex))
    if ex isa Symbol
        haskey(_KNOB_NAMED_CONSTANTS, ex) && return KnobConst(_KNOB_NAMED_CONSTANTS[ex])
        return KnobRef(ex)
    end
    if ex isa Expr
        ex.head === :. && return KnobRef(_flatten_knob_path(ex))
        if ex.head === :call
            op = ex.args[1]
            if op isa Function
                # `Symbolics.toexpr` and friends embed function *values*; map
                # them back to their whitelist names.
                op = get(_KNOB_OPERATOR_SYMBOLS, op, nothing)
                op === nothing && throw(ArgumentError(
                    "function $(ex.args[1]) is not in the knob operator whitelist"))
            end
            op isa Symbol || throw(ArgumentError(
                "knob expressions support only named operators; got $(repr(op))"))
            spec = get(_KNOB_OPERATORS, op, nothing)
            spec === nothing && throw(ArgumentError(
                "operator $(op) is not in the knob whitelist " *
                "($(join(sort!(collect(keys(_KNOB_OPERATORS))), ", "))). " *
                "Knob expressions are data, not programs; register a named pure " *
                "function in the whitelist if a new operation is genuinely needed."))
            args = AbstractKnobExpression[_lower_knob(a) for a in ex.args[2:end]]
            length(args) in spec[2] || throw(ArgumentError(
                "operator $(op) takes $(spec[2]) arguments; got $(length(args))"))
            # `-Inf` prints as the negation CALL of the named constant `Inf`
            # (Julia has no negative literal for it); fold that back so
            # `KnobConst(-Inf)` round-trips as itself (2026-08-05 audit, U14-2).
            #
            # Extended to FINITE negated literals too (2026-08-05_b audit,
            # U13-8). `KnobCall(:-, [KnobConst(5.0)])` prints as "-5.0", which
            # Julia's parser reads back as the literal `KnobConst(-5.0)`, so
            # `knob_expression(string(e)) == e` was false: the value survived
            # and the tree did not. Folding here makes printing and parsing
            # agree for every negated literal rather than only the non-finite
            # ones -- `-(-5.0)`, `-u`, `+(5.0)` and the rest already round-trip.
            if op === :- && length(args) == 1 && args[1] isa KnobConst
                return KnobConst(-(args[1]::KnobConst).value)
            end
            return KnobCall(op, args)
        end
    end
    throw(ArgumentError(
        "unsupported construct in knob expression: $(repr(ex)). Knob expressions " *
        "are built from knob paths, numbers, and whitelisted operators only — no " *
        "control flow, no interpolation, no arbitrary calls."))
end

"""Direct knob paths referenced by an expression."""
function _knob_direct_dependencies(node::AbstractKnobExpression)
    out = Set{Symbol}()
    _collect_refs!(out, node)
    return out
end
_collect_refs!(out, n::KnobRef) = (push!(out, n.path); out)
_collect_refs!(out, ::KnobConst) = out
function _collect_refs!(out, n::KnobCall)
    for a in n.args
        _collect_refs!(out, a)
    end
    return out
end

# Transitive dependency closure through registered expressions. Caller holds the lock.
function _knob_closure_locked(paths::Set{Symbol})
    seen = Set{Symbol}()
    frontier = collect(paths)
    while !isempty(frontier)
        p = pop!(frontier)
        p in seen && continue
        push!(seen, p)
        entry = get(_KNOB_TABLE, p, nothing)
        entry === nothing && continue
        entry.expression === nothing && continue
        for d in _knob_direct_dependencies(entry.expression)
            d in seen || push!(frontier, d)
        end
    end
    return seen
end

function _validate_refs_locked(node::AbstractKnobExpression)
    for d in sort!(collect(_knob_direct_dependencies(node)))
        haskey(_KNOB_TABLE, d) || throw(ArgumentError(
            "unknown knob $(d) referenced in a knob expression; declare it first " *
            "with @knob $(d) (declaration-before-use catches typos at definition time)"))
    end
    return node
end

function _invalidate_dependents_locked!(path::Symbol)
    entry = get(_KNOB_TABLE, path, nothing)
    entry === nothing && return nothing
    for q in entry.dependents
        e = get(_KNOB_TABLE, q, nothing)
        e === nothing && continue
        if e.value !== nothing
            e.value = nothing
            _invalidate_dependents_locked!(q)
        end
    end
    return nothing
end

function _remove_reverse_edges_locked!(path::Symbol, expression)
    expression === nothing && return nothing
    for d in _knob_direct_dependencies(expression)
        e = get(_KNOB_TABLE, d, nothing)
        e === nothing || delete!(e.dependents, path)
    end
    return nothing
end

# A knob path may not be both a value and a namespace: declaring `a.b` when
# `a.b.c` exists (or vice versa) is a structural error, and it would make
# namespace property access ambiguous.
function _check_namespace_collision_locked(path::Symbol)
    haskey(_KNOB_TABLE, path) && return nothing
    s = string(path)
    for p in keys(_KNOB_TABLE)
        q = string(p)
        startswith(q, s * ".") && throw(ArgumentError(
            "cannot declare knob $(path): it is a namespace containing knob $(p)"))
        startswith(s, q * ".") && throw(ArgumentError(
            "cannot declare knob $(path): $(p) is already a knob, not a namespace"))
    end
    return nothing
end

_convert_knob_value(path::Symbol, T::Type, value) =
    try
        convert(T, value)
    catch
        throw(ArgumentError(
            "knob $(path) is declared ::$(T); cannot convert " *
            "$(repr(value))::$(typeof(value)) to it"))
    end

# Resolve the declared type for a (re)declaration: an explicit annotation wins,
# an existing entry keeps its type, and new knobs default to Float64. Pure by
# design (2026-08-05 audit, U14-1): the retype itself — which CONVERTS the
# stored value, i.e. mutates — is applied only on success paths, after every
# guard, so a rejected call leaves the registry untouched.
function _declared_knob_type_locked(path::Symbol, T::Union{Nothing,Type})
    T === nothing || return T
    entry = get(_KNOB_TABLE, path, nothing)
    return entry === nothing ? Float64 : entry.type
end

# Does declaring `path` need to bump the global epoch?
#
# The epoch is the recompilation gate: `Tasks.jl` and the strong-strong executor
# rebuild their runtime lines whenever it moves, so a bump costs a full
# `compile_runtime` over every element of every knob-dependent task. Declaring a
# knob name that is NOT already in the table cannot invalidate anything, because
# nothing can reference it yet: `_validate_refs_locked` enforces
# declaration-before-use, so no live `AbstractKnobExpression` names it and no
# compiled runtime depends on it.
#
# The load-bearing half of that argument is DELETION. A stale expression built
# before `_forget_knob!` or `reset_knobs!` still holds the name, so re-declaring
# it makes that expression resolvable again with a different value -- but both
# removal paths bump the epoch themselves, so any task compiled before the
# deletion is already past its gate and recompiles on its next execute either
# way. Skipping the bump here therefore never leaves a task reading a value the
# registry no longer holds. If a future removal path stops bumping, this
# reasoning breaks and the skip must come back out.
#
# Measured on a 50-element knob-driven line, 20 executes with one unrelated
# brand-new knob declared before each: 36.7 ms -> 10.6 ms, against a 10.5 ms
# floor with no declarations at all (2026-08-05_b audit, U13-7).
@inline _knob_declaration_bumps_epoch(entry) = entry !== nothing

function _install_dependent_locked!(path::Symbol, T::Type, node::AbstractKnobExpression)
    T <: Real || throw(ArgumentError(
        "knob $(path) is declared ::$(T); expression-defined knobs must have a " *
        "Real value type (expressions evaluate numerically)"))
    _check_namespace_collision_locked(path)
    _validate_refs_locked(node)
    deps = _knob_direct_dependencies(node)
    path in _knob_closure_locked(deps) && throw(ArgumentError(
        "defining knob $(path) with this expression would create a dependency cycle"))
    entry = get(_KNOB_TABLE, path, nothing)
    bump = _knob_declaration_bumps_epoch(entry)
    if entry === nothing
        entry = _KnobEntry(path, T, nothing, nothing, Set{Symbol}())
        _KNOB_TABLE[path] = entry
    else
        _remove_reverse_edges_locked!(path, entry.expression)
        entry.type = T
    end
    entry.expression = node
    entry.value = nothing
    for d in deps
        push!(_KNOB_TABLE[d].dependents, path)
    end
    _invalidate_dependents_locked!(path)
    bump && (_KNOB_EPOCH[] += 1)
    return KnobRef(path)
end

function _install_independent_locked!(path::Symbol, T::Type, value)
    _check_namespace_collision_locked(path)
    value = _convert_knob_value(path, T, value)
    entry = get(_KNOB_TABLE, path, nothing)
    bump = _knob_declaration_bumps_epoch(entry)
    if entry === nothing
        entry = _KnobEntry(path, T, nothing, value, Set{Symbol}())
        _KNOB_TABLE[path] = entry
    else
        _remove_reverse_edges_locked!(path, entry.expression)
        entry.type = T
        entry.expression = nothing
        entry.value = value
    end
    _invalidate_dependents_locked!(path)
    bump && (_KNOB_EPOCH[] += 1)
    return KnobRef(path)
end

"""
Runtime backend of the `@knob` macro. `T` is the declared type (or `nothing`),
`rhs` is the quoted right-hand side (or `nothing` for a bare declaration), and
`rhs_thunk` evaluates the right-hand side as plain Julia code — used only for
non-`Real` declared types, where the expression tree does not apply.
"""
function _knob_define!(path::Symbol, T::Union{Nothing,Type}, rhs, rhs_thunk)
    lock(_KNOB_LOCK) do
        # A name the expression language reads as a literal constant can never
        # be reached by a KnobRef (`@knob_expr(pi)` lowers to KnobConst, checked
        # BEFORE the KnobRef branch), so registering it would leave the registry
        # and the expression language silently disagreeing about one name.
        # Reject at declaration (2026-08-05 audit, U14-3).
        haskey(_KNOB_NAMED_CONSTANTS, path) && throw(ArgumentError(
            "cannot declare a knob named $(path): knob expressions read $(path) " *
            "as the literal constant $(_KNOB_NAMED_CONSTANTS[path]), so the " *
            "knob would be unreachable from every expression; pick a " *
            "namespaced name instead (e.g. consts.$(path))"))
        entry = get(_KNOB_TABLE, path, nothing)
        Tdecl = _declared_knob_type_locked(path, T)
        if rhs === nothing
            # Bare (re)declaration. The guard runs BEFORE the retype below,
            # because the retype converts the stored value — a mutation — and a
            # call that throws must leave the registry untouched (2026-08-05
            # audit, U14-1: this guard used to run after the retype, so
            # `@knob dep::Float32` on an expression-defined knob converted the
            # cached value, kept the new type, threw, and never bumped the
            # epoch — the silent-stale-physics class).
            entry !== nothing && entry.expression !== nothing && throw(ArgumentError(
                "knob $(path) is already defined by the expression " *
                "$(_knob_expr_string(entry.expression)); redefine it explicitly " *
                "with @knob $(path) = <expression or value>"))
            if entry === nothing
                _check_namespace_collision_locked(path)
                _KNOB_TABLE[path] = _KnobEntry(path, Tdecl, nothing, nothing, Set{Symbol}())
                # No bump: see `_knob_declaration_bumps_epoch` (U13-7).
            elseif entry.type !== Tdecl
                # `@knob p::T` on an existing independent knob is a value
                # mutation even though it looks like a pure annotation: the
                # stored value is converted to T. When the number changes,
                # everything downstream is stale, and without the bump the
                # staleness is SILENT: `knob_value` reports the new value while
                # dependent caches and every compiled runtime keep the old one,
                # because nothing bumps the epoch that `Tasks.jl` and the
                # strong-strong executor gate recompilation on.
                #
                # Measured before the epoch fix: `@knob a = 0.1; @knob b = a * 1.0`
                # then `@knob a::Float32` left `knob_value(:a) == 0.1f0`
                # (0.10000000149011612) while `knob_value(:b)` stayed 0.1, with
                # the epoch unmoved. `set_knob!` has always done both of these.
                v = entry.value === nothing ? nothing :
                    _convert_knob_value(path, Tdecl, entry.value)
                entry.type = Tdecl
                if v !== nothing
                    # The TYPE change counts, not only a change of number.
                    # `isequal` compares across types, so Float64 1.7 ->
                    # BigFloat, Float32 1.7f0 -> Float64 and 2.0 -> Int 2 all
                    # report "unchanged" while `entry.type` and
                    # `typeof(entry.value)` both move. A knob's value type is
                    # exactly what `numeric_type(resolve_knobs(spec))` promotes
                    # over, so a fresh `compile_runtime` then yields a different
                    # ELEMENT type while `_runtime_entries`' gate sees no epoch
                    # motion and every already-built task keeps compiling at the
                    # old precision -- indefinitely. Widening a knob's declared
                    # type is the documented way to seed an AD or
                    # extended-precision sweep, so doing it on a live task
                    # silently doing nothing is the whole failure
                    # (2026-08-05_b audit, U13-1).
                    changed = !isequal(entry.value, v) || typeof(entry.value) !== typeof(v)
                    entry.value = v
                    if changed
                        _invalidate_dependents_locked!(path)
                        _KNOB_EPOCH[] += 1
                    end
                end
            end
            return KnobRef(path)
        end
        if !(Tdecl <: Real)
            rhs_thunk === nothing && throw(ArgumentError(
                "knob $(path) is declared ::$(Tdecl); non-Real knobs can only be " *
                "defined through the @knob macro, which evaluates the right-hand " *
                "side as ordinary Julia code"))
            return _install_independent_locked!(path, Tdecl, rhs_thunk())
        end
        node = _lower_knob(rhs)
        node isa KnobConst &&
            return _install_independent_locked!(path, Tdecl, node.value)
        return _install_dependent_locked!(path, Tdecl, node)
    end
end

# Two-argument convenience (tests, programmatic definition): default type rules.
_knob_define!(path::Symbol, rhs) = _knob_define!(path, nothing, rhs, nothing)

"""Runtime backend of the `@knob_expr` macro; validates references immediately."""
function _knob_expression_build(rhs)
    node = _lower_knob(rhs)
    lock(_KNOB_LOCK) do
        _validate_refs_locked(node)
    end
    return node
end

# ---------------------------------------------------------------------------
# Public macros and functions
# ---------------------------------------------------------------------------

"""
    @knob path.to.name
    @knob path.to.name::T
    @knob path.to.name = value
    @knob path.to.name::T = value
    @knob path.to.name = expression

Declare or (re)define a knob. The hierarchical dotted name is flattened to one
path key (`Symbol("path.to.name")`) in a flat global registry — namespaces are
names, not modules. Forms:

- bare declaration: registers an *independent* knob with no value yet
  (evaluating it before it is assigned is an error, never a silent default);
- `= value`: an independent knob holding that value. Re-invoking this form is
  the macro spelling of assignment; for a dotted knob, plain assignment
  through its namespace object (`path.to.name = value`, see
  [`KnobNamespace`](@ref)) does the same without a macro;
- `= expression`: a *dependent* knob whose value is the stored expression over
  other knobs, evaluated on demand and cached. `@knob a = b` makes `a` an
  alias of `b`.

`::T` declares the knob's value type; the default is `Float64`. Assigned
values are converted to the declared type (a lossy assignment such as `1.5`
into an `Int` knob is an error). Expression-defined knobs require `T <: Real`;
for other declared types (`Symbol`, `Bool`, ...) the right-hand side is
evaluated as ordinary Julia code and stored as a plain value.

Expressions are captured as syntax and lowered to the closed expression tree
at definition time: every referenced knob must already be declared, only
whitelisted operators are accepted, and dependency cycles are rejected — all
errors happen here, not at tracking time. Declaring a dotted knob also binds
its root namespace (e.g. `HSR`) as a [`KnobNamespace`](@ref) constant in the
calling module, enabling plain-assignment access. Returns a [`KnobRef`](@ref).

```julia
@knob HSR.B_rho = 81.1
@knob HSR.power_supply.arc_quad::Float64   # declared, value assigned later
@knob HSR.k1 = HSR.power_supply.arc_quad * HSR.current_transfer / HSR.B_rho

HSR.power_supply.arc_quad = 1000.0         # plain assignment via the namespace
```
"""
macro knob(ex)
    lhs, rhs = ex isa Expr && ex.head === :(=) ? (ex.args[1], ex.args[2]) : (ex, nothing)
    T = nothing
    if lhs isa Expr && lhs.head === :(::) && length(lhs.args) == 2
        lhs, T = lhs.args[1], lhs.args[2]
    end
    path = _flatten_knob_path(lhs)
    type_arg = T === nothing ? :nothing : esc(T)
    thunk_arg = rhs === nothing ? :nothing : :(() -> $(esc(rhs)))
    define = :(_knob_define!($(QuoteNode(path)), $type_arg,
                             $(QuoteNode(rhs)), $thunk_arg))
    root = Symbol(first(split(string(path), '.')))
    root === path && return define
    # Root-binding validation BEFORE registration: `_ensure_knob_root` throwing
    # after `$define` left the knob registered and the epoch bumped by a failed
    # declaration (2026-08-05 audit, U14-4: `@knob sin.x = 1.0` errored yet
    # `list_knobs()` contained `sin.x`). The binding itself still happens after,
    # so a `$define` rejection creates no namespace constant either.
    return quote
        _check_knob_root($(QuoteNode(root)), $(__module__))
        local ref = $define
        _ensure_knob_root($(QuoteNode(root)), $(__module__))
        ref
    end
end

"""
    @knob_expr expression

Capture `expression` as an [`AbstractKnobExpression`](@ref) without registering
a knob. This is how a knob-controlled parameter enters an element: store the
result in the flexible `ElementSpec{kind}(; param=...)` constructor and
`compile_runtime` resolves it when the tracking line is built. Referenced knobs
must already be declared (typos fail here, at construction time).

The result is a first-class value, usable outside element specs as well: it
stays live against the registry, so `knob_value(e)` evaluates it against the
*current* knob state wherever you hold it, and it is the input to
`knob_dependencies`, `knob_derivative`, `knob_symbolic`, and the
`string`/`knob_expression` serialization round trip. It is deliberately not a
number — eager conversion raises a directed error; compose expressions
syntactically, and call `knob_value` where the number is needed.

```julia
q1 = ElementSpec{:crab_dispersion}(;
    zeta1 = @knob_expr(HSR.power_supply.arc_quad * HSR.current_transfer / HSR.B_rho),
    tracking_method = Symplectic6DMap())
```

The eagerly-converting friendly constructors (`CrabDispersionSpec(...)` etc.)
cannot defer a knob expression and raise a directed error if handed one.
"""
macro knob_expr(ex)
    return :(_knob_expression_build($(QuoteNode(ex))))
end

"""
    set_knob!(path, value)

Set an *independent* knob's value; the value is converted to the knob's
declared type. `path` may be a `Symbol`, `String`, or `KnobRef`; for dotted
knobs, plain assignment through the namespace object
(`HSR.power_supply.arc_quad = 1000.0`) or through the [`knobs`](@ref) root
(`knobs.x = 1.0`) calls this function. Setting a dependent
(expression-defined) knob is an error — change its inputs, or redefine it with
`@knob`. Invalidates every dependent knob's cached value and bumps
[`knob_epoch`](@ref), so knob-dependent tasks recompile their runtime elements
at the next `execute!`.
"""
function set_knob!(path_like, value)
    path = _knob_path(path_like)
    lock(_KNOB_LOCK) do
        entry = get(_KNOB_TABLE, path, nothing)
        entry === nothing && throw(ArgumentError(
            "unknown knob $(path); declare it first with @knob $(path)"))
        entry.expression === nothing || throw(ArgumentError(
            "knob $(path) is defined by the expression " *
            "$(_knob_expr_string(entry.expression)); set its independent inputs " *
            "instead, or redefine it with @knob $(path) = value"))
        entry.value = _convert_knob_value(path, entry.type, value)
        _invalidate_dependents_locked!(path)
        _KNOB_EPOCH[] += 1
        return entry.value
    end
end

"""
    knob_value(path)
    knob_value(expression)

Evaluate a knob or a knob expression, memoizing dependent-knob values until an
upstream assignment invalidates them. The result has the knob's declared type
(`Float64` unless annotated); expression evaluation is numeric. An independent
knob with no value raises an `ArgumentError` naming the knob.
"""
function knob_value(path_like::Union{Symbol,AbstractString,KnobRef})
    path = _knob_path(path_like)
    lock(_KNOB_LOCK) do
        return _knob_value_locked(path, Set{Symbol}())
    end
end

knob_value(node::AbstractKnobExpression) = lock(_KNOB_LOCK) do
    _eval_knob_node(node, Set{Symbol}())
end
knob_value(x::Real) = Float64(x)

function _knob_value_locked(path::Symbol, active::Set{Symbol})
    entry = get(_KNOB_TABLE, path, nothing)
    entry === nothing && throw(ArgumentError(
        "unknown knob $(path); declare it with @knob $(path)"))
    entry.value === nothing || return entry.value
    entry.expression === nothing && throw(ArgumentError(
        "knob $(path) has no value; assign it with @knob $(path) = value, " *
        "$(path) = value through its namespace, or set_knob!"))
    path in active && throw(ArgumentError("knob dependency cycle at $(path)"))
    push!(active, path)
    v = _eval_knob_node(entry.expression, active)
    delete!(active, path)
    entry.value = _convert_knob_value(path, entry.type, v)
    return entry.value
end

_eval_knob_node(n::KnobConst, ::Set{Symbol}) = n.value
_eval_knob_node(n::KnobRef, active::Set{Symbol}) = _knob_value_locked(n.path, active)
function _eval_knob_node(n::KnobCall, active::Set{Symbol})
    f = _KNOB_OPERATORS[n.op][1]
    vals = Any[_eval_knob_node(a, active) for a in n.args]
    for (a, v) in zip(n.args, vals)
        v isa Real || throw(ArgumentError(
            "knob expression operand $(a) evaluated to the non-numeric value " *
            "$(repr(v))::$(typeof(v)); only Real-typed knobs can appear inside " *
            "arithmetic expressions"))
    end
    # NOT `Float64(...)`: a knob may hold a dual number or a truncated power
    # series, and casting here would evaluate the expression correctly and then
    # throw the derivative away -- silently, since the value would be right.
    # A knob is a machine control, so differentiating with respect to one is the
    # most useful derivative there is; `bus` feeding a whole magnet family gives
    # the family's response in a single pass.
    return f(vals...)
end

# ---------------------------------------------------------------------------
# Namespace objects: plain-assignment access without strings
# ---------------------------------------------------------------------------

"""
    KnobNamespace

Live view of one level of the knob namespace hierarchy. Reading a property
returns the knob's value (or the next `KnobNamespace` level); assigning a
property calls [`set_knob!`](@ref). Declaring a dotted knob with `@knob` binds
its root namespace as a constant in the calling module, so afterwards plain
Julia syntax reads and writes knobs — no strings involved:

```julia
@knob ip.half_crossing_angle::Float64 = 12.5e-3
ip.half_crossing_angle              # 0.0125
ip.half_crossing_angle = 15.0e-3    # same as set_knob!
```

The exported [`knobs`](@ref) constant is the root-level namespace covering
every registered knob, including undotted ones.
"""
struct KnobNamespace
    prefix::Symbol   # Symbol("") for the root
end

"""
    knobs

The root [`KnobNamespace`](@ref): `knobs.x` reads knob `x`, `knobs.x = 1.0`
assigns it, and `knobs.HSR.power_supply.arc_quad` walks dotted paths. This is
the plain-assignment interface for undotted knobs, whose names cannot carry a
namespace binding of their own.
"""
const knobs = KnobNamespace(Symbol(""))

_knob_child_path(ns::KnobNamespace, s::Symbol) =
    getfield(ns, :prefix) === Symbol("") ? s :
    Symbol(string(getfield(ns, :prefix), '.', s))

_is_namespace_prefix_locked(path::Symbol) =
    any(startswith(string(p), string(path) * ".") for p in keys(_KNOB_TABLE))

function Base.getproperty(ns::KnobNamespace, s::Symbol)
    full = _knob_child_path(ns, s)
    lock(_KNOB_LOCK) do
        haskey(_KNOB_TABLE, full) && return _knob_value_locked(full, Set{Symbol}())
        _is_namespace_prefix_locked(full) && return KnobNamespace(full)
        throw(ArgumentError(
            "no knob or knob namespace named $(full); declare it with @knob $(full)"))
    end
end

Base.setproperty!(ns::KnobNamespace, s::Symbol, value) =
    set_knob!(_knob_child_path(ns, s), value)

function Base.propertynames(ns::KnobNamespace, ::Bool=false)
    prestr = getfield(ns, :prefix) === Symbol("") ? "" :
        string(getfield(ns, :prefix), '.')
    names = Set{Symbol}()
    lock(_KNOB_LOCK) do
        for p in keys(_KNOB_TABLE)
            s = string(p)
            startswith(s, prestr) || continue
            push!(names, Symbol(first(split(s[length(prestr)+1:end], '.'))))
        end
    end
    return Tuple(sort!(collect(names); by=string))
end

Base.show(io::IO, ns::KnobNamespace) =
    print(io, "KnobNamespace(",
          getfield(ns, :prefix) === Symbol("") ? "<root>" : getfield(ns, :prefix),
          ")")

"""Reject binding `root` when `mod` already names something that is not a
`KnobNamespace`. Split from [`_ensure_knob_root`](@ref) so `@knob` can validate
BEFORE registering the knob — the collision throwing after registration left
the knob in the registry (2026-08-05 audit, U14-4)."""
function _check_knob_root(root::Symbol, mod::Module)
    # The binding may have been created at runtime by an earlier @knob in the
    # same function body, i.e. in a newer world than the running method; go
    # through invokelatest for world-age-correct access (Julia >= 1.12).
    Base.invokelatest(isdefined, mod, root) || return nothing
    b = Base.invokelatest(getglobal, mod, root)
    b isa KnobNamespace || throw(ArgumentError(
        "cannot bind knob namespace $(root): $(mod).$(root) already names " *
        "a $(typeof(b)); pick a different knob root or rename that binding"))
    return nothing
end

"""Bind `root` as a `KnobNamespace` constant in `mod` (idempotent); called by
`@knob` for dotted paths so plain assignment works after declaration."""
function _ensure_knob_root(root::Symbol, mod::Module)
    _check_knob_root(root, mod)
    Base.invokelatest(isdefined, mod, root) && return nothing
    Core.eval(mod, :(const $root = $(KnobNamespace(root))))
    return nothing
end

"""
    knob_expression(text::AbstractString)

Parse `text` into the knob expression tree through the same lowering and
validation as `@knob_expr`. With [`knob_to_expr`](@ref) and `string(expr)` this
gives lossless round trips for serialization and symbolic-package interop.
"""
knob_expression(text::AbstractString) = _knob_expression_build(Meta.parse(text))

"""
    knob_to_expr(expression)

Convert a knob expression-tree node back to a Julia `Expr`/literal — the
bridge to symbolic packages (build `Symbolics.jl` variables for each `KnobRef`
and substitute).
"""
knob_to_expr(n::KnobConst) = n.value
knob_to_expr(n::KnobRef) = Meta.parse(string(n.path))
knob_to_expr(n::KnobCall) = Expr(:call, n.op, map(knob_to_expr, n.args)...)

"""
    list_knobs(prefix="")

Sorted paths of all registered knobs, optionally filtered by a namespace
prefix such as `"HSR.power_supply"`.
"""
function list_knobs(prefix::AbstractString="")
    lock(_KNOB_LOCK) do
        paths = collect(keys(_KNOB_TABLE))
        isempty(prefix) || filter!(p -> startswith(string(p), prefix), paths)
        return sort!(paths; by=string)
    end
end

"""
    knob_dependencies(path_or_expression; transitive=false)

Knob paths a knob or expression reads, as a sorted vector. `transitive=true`
follows dependent knobs through their own expressions.
"""
function knob_dependencies(x; transitive::Bool=false)
    # A bare KnobRef is a path handle (as from @knob_expr(a.b)): report the
    # knob's own dependencies, not the reference node itself.
    node = x isa AbstractKnobExpression && !(x isa KnobRef) ? x : lock(_KNOB_LOCK) do
        entry = get(_KNOB_TABLE, _knob_path(x), nothing)
        entry === nothing && throw(ArgumentError("unknown knob $(_knob_path(x))"))
        entry.expression === nothing ? KnobConst(0.0) : entry.expression
    end
    direct = _knob_direct_dependencies(node)
    transitive || return sort!(collect(direct); by=string)
    lock(_KNOB_LOCK) do
        return sort!(collect(_knob_closure_locked(direct)); by=string)
    end
end

"""
    knob_dependents(path; transitive=false)

Knobs whose value depends on `path`, as a sorted vector. Note this covers the
knob registry only; element parameters holding `@knob_expr` values are found
through their specs (`resolve_knobs`, `knob_report`).
"""
function knob_dependents(path_like; transitive::Bool=false)
    path = _knob_path(path_like)
    lock(_KNOB_LOCK) do
        entry = get(_KNOB_TABLE, path, nothing)
        entry === nothing && throw(ArgumentError("unknown knob $(path)"))
        transitive || return sort!(collect(entry.dependents); by=string)
        seen = Set{Symbol}()
        frontier = collect(entry.dependents)
        while !isempty(frontier)
            q = pop!(frontier)
            q in seen && continue
            push!(seen, q)
            e = get(_KNOB_TABLE, q, nothing)
            e === nothing || append!(frontier, collect(e.dependents))
        end
        return sort!(collect(seen); by=string)
    end
end

"""
    knob_report(; prefix="", io=stdout)

Print every registered knob (optionally under a namespace prefix): its current
value (or `unset`/`pending`), its defining expression for dependent knobs, and
its direct dependents.

This is the **registry** view — the knob namespace. It deliberately does not
know which element parameters hold expressions: for that, hand a container to
`knob_report(elements; ...)` (defined with the beam line machinery), the
**wiring** view that walks the given line/tuple and reports what each knob
actually drives. `docs/knob_control.md` §2a has the split and its reasons.
"""
function knob_report(; prefix::AbstractString="", io::IO=stdout)
    paths = list_knobs(prefix)
    if isempty(paths)
        println(io, isempty(prefix) ? "No knobs are registered." :
                    "No knobs are registered under $(repr(prefix)).")
        return nothing
    end
    println(io, "Knobs", isempty(prefix) ? "" : " under $(prefix)", ":")
    lock(_KNOB_LOCK) do
        for p in paths
            entry = _KNOB_TABLE[p]
            value = entry.value === nothing ?
                (entry.expression === nothing ? "unset" : "pending") :
                repr(entry.value)
            defn = entry.expression === nothing ? "independent" :
                ":= " * _knob_expr_string(entry.expression)
            typetag = entry.type === Float64 ? "" : string("::", entry.type)
            println(io, "  - ", p, typetag, " = ", value, "   (", defn, ")")
            isempty(entry.dependents) ||
                println(io, "      dependents: ",
                        join(sort!(collect(entry.dependents); by=string), ", "))
        end
    end
    return nothing
end

"""
    reset_knobs!()

Remove every registered knob and bump the epoch. Intended for tests and
interactive resets; specs holding `@knob_expr` values will error on their next
`compile_runtime` until the knobs are redeclared.
"""
function reset_knobs!()
    lock(_KNOB_LOCK) do
        empty!(_KNOB_TABLE)
        _KNOB_EPOCH[] += 1
    end
    return nothing
end

"""Internal: remove one knob and scrub its edges (contract cleanup)."""
function _forget_knob!(path_like)
    path = _knob_path(path_like)
    lock(_KNOB_LOCK) do
        entry = get(_KNOB_TABLE, path, nothing)
        entry === nothing && return nothing
        _remove_reverse_edges_locked!(path, entry.expression)
        _invalidate_dependents_locked!(path)
        for (_, e) in _KNOB_TABLE
            delete!(e.dependents, path)
        end
        delete!(_KNOB_TABLE, path)
        _KNOB_EPOCH[] += 1
        return nothing
    end
end

# ---------------------------------------------------------------------------
# Printing (surface syntax; round-trips through knob_expression)
# ---------------------------------------------------------------------------

_knob_prec(op::Symbol) =
    op === :+ || op === :- ? 1 : op === :* || op === :/ ? 2 : op === :^ ? 3 : 4

_knob_expr_string(n::KnobRef, prec::Int=0) = string(n.path)
function _knob_expr_string(n::KnobConst, prec::Int=0)
    s = repr(n.value)
    return n.value < 0 && prec > 0 ? "($s)" : s
end
function _knob_expr_string(n::KnobCall, prec::Int=0)
    if n.op in (:+, :-, :*, :/, :^) && length(n.args) >= 2
        p = _knob_prec(n.op)
        pieces = String[]
        for a in n.args
            # Every operand must out-rank its parent, so a nested call of the
            # SAME precedence always parenthesizes. Anything weaker re-associates
            # through the documented round trip
            # `knob_expression(string(e)) == e` (docs/knob_control.md).
            #
            # This was arrived at twice. The first pass (2026-08-05 audit,
            # U14-2) special-cased `^` (right-associative: `(u^v)^w` printed
            # "u ^ v ^ w" reparsed as `u^(v^w)`, 64 silently becoming 512) and
            # the right operand of `-` and `/`, but left `+` and `*` bare on the
            # grounds that they associate. They do not, in floating point:
            # `a + (b + c)` printed "a + b + c", reparsed to a flat 3-ary call,
            # and with a = 1e16, b = -1e16, c = 1 the value moved 0.0 -> 1.0
            # (2026-08-05_b audit, U20-2). Precedence still separates the
            # levels, so `a + b * c` keeps its natural form; only same-level
            # nesting gains parentheses, which is exactly the ambiguity.
            push!(pieces, _knob_expr_string(a, p + 1))
        end
        s = join(pieces, " $(n.op) ")
        return p < prec ? "($s)" : s
    elseif n.op === :- && length(n.args) == 1
        s = "-" * _knob_expr_string(n.args[1], 3)
        return prec > 1 ? "($s)" : s
    end
    return string(n.op, "(", join((_knob_expr_string(a) for a in n.args), ", "), ")")
end

Base.show(io::IO, n::KnobRef) = print(io, _knob_expr_string(n))
Base.show(io::IO, n::KnobConst) = print(io, _knob_expr_string(n))
Base.show(io::IO, n::KnobCall) = print(io, _knob_expr_string(n))

# Friendly constructors convert parameters eagerly (`T(value)`), which would
# either fail obscurely or force premature evaluation. Fail with directions.
# Every Number, not just AbstractFloat: `Int(e)` deserves the same directions
# (2026-08-05 audit, U14-7).
(::Type{T})(::AbstractKnobExpression) where {T<:Number} = throw(ArgumentError(
    "a knob expression cannot be converted to a number eagerly. Use the flexible " *
    "ElementSpec{kind}(; param=@knob_expr(...)) constructor so compile_runtime " *
    "defers evaluation, or call knob_value(expression) to evaluate now."))
Base.float(x::AbstractKnobExpression) = Float64(x)

# The design doc promises `2 * e` a DIRECTED error, not a bare MethodError:
# mixing numbers (or other expressions) into expression objects through
# ordinary arithmetic is the number-one composition trap, and before the
# 2026-08-05 audit (U14-7) only `Float64(e)`/`float(e)` got directions while
# `2 * e` fell through to `MethodError: no method matching *(::Int64, ...)`.
_knob_eager_arithmetic_error(op::Symbol) = throw(ArgumentError(
    "a knob expression is not a number; $(op) does not evaluate it eagerly. " *
    "Compose expressions syntactically — @knob_expr(2 * x) or knob_expression " *
    "— so the result stays a validated, printable expression, or call " *
    "knob_value(expression) where the number is needed."))
for op in (:+, :-, :*, :/, :^)
    @eval Base.$op(::Number, ::AbstractKnobExpression) =
        _knob_eager_arithmetic_error($(QuoteNode(op)))
    @eval Base.$op(::AbstractKnobExpression, ::Number) =
        _knob_eager_arithmetic_error($(QuoteNode(op)))
    @eval Base.$op(::AbstractKnobExpression, ::AbstractKnobExpression) =
        _knob_eager_arithmetic_error($(QuoteNode(op)))
end

# ---------------------------------------------------------------------------
# compile_runtime integration
# ---------------------------------------------------------------------------

# The detector and the resolver MUST have the same reach.
#
# `_param_has_knob` used to test one level only (`v isa Tuple && any(x -> x isa
# AbstractKnobExpression, v)`) while `_resolve_knob_param(v::Tuple)` was already
# fully recursive. The detector, not the resolver, is the binding constraint --
# `resolve_knobs` returns the spec unchanged when the detector says no -- so a
# knob expression inside a NESTED tuple or a vector-valued parameter was
# invisible: the raw expression object reached the runtime constructor, and the
# epoch gate in `Tasks.jl` treated the task as knob-free, so a later `set_knob!`
# never reached it. `docs/knob_control.md` listed "no array-valued knobs" as a
# limitation, but the limitation was enforced by nothing -- it degraded
# silently, which is the one outcome this repository does not accept
# (2026-08-05_b audit, U13-9).
#
# Both sides now recurse over the same container shapes, so the property to hold
# on to is `_param_has_knob(v) == (_resolve_knob_param(v) !== v)` for every
# shape either one understands. Anything else (a Dict, a struct) is still opaque
# to both, consistently.
_param_has_knob(v) = v isa AbstractKnobExpression
_param_has_knob(v::Union{Tuple,NamedTuple,AbstractArray}) = any(_param_has_knob, v)

"""True when a line/spec/container holds any knob-expression parameter."""
_has_knob_parameters(x) = false
_has_knob_parameters(t::Tuple) = any(_has_knob_parameters, t)
_has_knob_parameters(v::AbstractVector) = any(_has_knob_parameters, v)
_has_knob_parameters(spec::ElementSpec) = any(_param_has_knob, values(params(spec)))

_resolve_knob_param(v) = v
_resolve_knob_param(v::AbstractKnobExpression) = knob_value(v)
_resolve_knob_param(v::Union{Tuple,NamedTuple}) = map(_resolve_knob_param, v)
# Guarded, unlike the tuple method: mapping a knob-free array would copy it on
# every `resolve_knobs`, and `resolve_knobs` walks EVERY parameter of a spec
# once any one of them holds a knob.
_resolve_knob_param(v::AbstractArray) =
    _param_has_knob(v) ? map(_resolve_knob_param, v) : v

"""
    resolve_knobs(spec)

Return `spec` with every knob-expression parameter evaluated to its value
(scalars and tuples of scalars; a bare knob reference resolves to the knob's
declared type, so `Symbol`- or `Bool`-typed knobs can drive non-numeric
parameters). Specs without knob parameters are returned unchanged.
`compile_runtime` calls this before constructing the runtime
element, so knob evaluation happens exactly when the tracking line or lattice
is built and runtime objects never carry knobs. Emits a `:knob_resolution`
execution-audit receipt naming the resolved parameters and their values.
"""
function resolve_knobs(spec::ElementSpec{Kind}) where {Kind}
    _has_knob_parameters(spec) || return spec
    resolved = Dict{Symbol,Any}()
    receipts = Pair{Symbol,Any}[]
    for (key, value) in params(spec)
        r = _resolve_knob_param(value)
        resolved[key] = r
        _param_has_knob(value) && push!(receipts, key => r)
    end
    _record_execution!(:knob_resolution, nothing,
                       (element=Kind, epoch=knob_epoch(),
                        resolved=Tuple(sort!(receipts; by=first))))
    return ElementSpec{Kind}(resolved)
end
