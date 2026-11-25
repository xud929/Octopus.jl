export @elements, @element

# ---------------------------------------------------------------------------
# The element block (design note docs/design/machine_description.md, D9): a
# purely syntactic mapping from registered kind names onto the friendly
# constructors, so a lattice module reads like a lattice file while every
# value, every check and every error stays the constructor's own.
# ---------------------------------------------------------------------------

"""
    @elements T begin ... end
    @elements begin ... end          # T = Float64

Declare elements by kind name. Inside the block, a call whose head is a
registered element kind (`quadrupole`, `drift`, `sbend`, `thin_rf_cavity`,
`marker`, ..., the keys of `element_meta`) is rewritten onto that kind's
friendly constructor (`element_meta(kind).friendly_constructor`), with the
numeric type `T` of the block header applied through the `numeric_type=T`
keyword every kind's constructor routes to its typed form, so

    @elements Float64 begin
        QF = quadrupole(L = 0.35, k1 = 1.5)
    end

is `QF = QuadrupoleSpec(; name = "QF", numeric_type = Float64, L = 0.35, k1 = 1.5)`.
The rules, and nothing more (D9):

1. The binding name is the default `name`; an explicit `name =` wins (an
   imported name such as `MQXA.1L5` is not a Julia identifier). A kind call
   that is not bound (`line(QF, D)` as a child) gets no name.
2. `line(...)` is the `:line` kind and becomes `BeamLine(name, children...;
   kwargs...)`: positional children, no `numeric_type` (a line has no numeric
   type of its own, and a parameter on a line would stop it dissolving).
3. `T` comes from the header, `Float64` when omitted, and is applied to every
   kind call the block emits; the constructor stores it as the element's
   `numeric_type`, so every element of the block shares the lattice's type
   (an explicit `numeric_type =` on one call wins, as an explicit `name =` does).
4. A kind whose metadata declares no friendly constructor is refused at
   expansion, by name, with the remedy: the flexible `ElementSpec{kind}(; ...)`
   form, which stays available inside the block.
5. Anything whose head is not a registered kind name is left untouched:
   helper calls, `LinearOptics` points, `StrongStrongCollision` markers,
   `ThinCrabCavitySpec{1}(...)` spelled directly, constants, knob
   declarations.
6. The mapping is syntactic; every value error comes from the constructor
   with the kind's own message, and positional arguments (a cavity's
   `frequency`) pass through in place.

Statements handled: `X = call`, `const X = call`, a bare `call`, with
docstrings and line numbers preserved; everything else passes through
unchanged. See [`@element`](@ref) for a single declaration and
[`Lattice`](@ref) for the record the block's line goes into.
"""
macro elements(args...)
    T, block = _elements_header(args)
    return esc(_elements_rewrite_block(block, T))
end

"""
    @element T X = kind(...)
    @element X = kind(...)           # T = Float64

One declaration under the rules of [`@elements`](@ref): the same rewriting of a
registered kind name onto its friendly constructor, the binding name as the
default `name`, the numeric type from the header.
"""
macro element(args...)
    T, stmt = _elements_header(args; single=true)
    return esc(_elements_rewrite_statement(stmt, T))
end

"""
    _elements_header(args; single=false) -> (T::Union{Symbol,Expr}, body)

Split the macro arguments into the numeric type and the body: the `begin ...
end` block of `@elements`, or the single statement of `@element` (`single =
true`). One argument gives `T = :Float64`; two give the header as written.
Refuses by name a wrong argument count, a header that is not a type
expression (a name such as `Float64`, a qualified name or a parametric type),
a block body that is not a `begin ... end`, and a single statement that is
one.
"""
function _elements_header(args; single::Bool=false)
    macro_name = single ? "@element" : "@elements"
    shape = single ? "`@element [T] X = kind(...)`" : "`@elements [T] begin ... end`"
    length(args) in (1, 2) || throw(ArgumentError(
        "$macro_name takes one or two arguments, $shape; got $(length(args))"))
    T = length(args) == 2 ? args[1] : :Float64
    _elements_is_type_expr(T) || throw(ArgumentError(
        "$macro_name: the header must be a type expression (a name such as `Float64`, " *
        "a qualified name or a parametric type); got `$(T)`"))
    body = args[end]
    isblock = body isa Expr && body.head === :block
    if single
        isblock && throw(ArgumentError(
            "@element takes one statement, `X = kind(...)`; a `begin ... end` block " *
            "is the shape of @elements"))
    else
        isblock || throw(ArgumentError(
            "@elements: the body must be a `begin ... end` block; got `$(body)`"))
    end
    return (T, body)
end

"""A header is a type expression: a name, a qualified name (`A.B`) or a parametric type (`A{B}`)."""
_elements_is_type_expr(T::Symbol) = true
_elements_is_type_expr(T::Expr) = T.head === :curly || T.head === :.
_elements_is_type_expr(T) = false

"""
    _elements_kind_constructor(head, registry=ELEMENT_META_BY_KIND) -> Union{Nothing,Tuple{Symbol,Any}}

`(kind, friendly_constructor)` when `head` is a `Symbol` naming a registered
kind (a key of `registry`, the element registry by default; a test passes its
own `Dict{Symbol,ElementMeta}`), `nothing` otherwise; a registered kind with
no friendly constructor throws the rule-4 refusal, naming the kind and the
flexible form.
"""
function _elements_kind_constructor(head, registry=ELEMENT_META_BY_KIND)
    head isa Symbol || return nothing
    meta = get(registry, head, nothing)
    meta === nothing && return nothing
    ctor = meta.friendly_constructor
    ctor === nothing && throw(ArgumentError(
        "@elements: the element kind `$(head)` declares no friendly constructor, so " *
        "`$(head)(...)` has nothing to expand onto; write it in the flexible form " *
        "`ElementSpec{:$(head)}(; ...)` inside the block"))
    return (head, ctor)
end

"""
    _elements_rewrite_block(block::Expr, T; registry=ELEMENT_META_BY_KIND) -> Expr

Walk the block's top-level statements and rewrite each through
[`_elements_rewrite_statement`](@ref); line numbers and non-statement
expressions pass through. The result is a new `begin ... end` block (an empty
block stays empty).
"""
function _elements_rewrite_block(block::Expr, T; registry=ELEMENT_META_BY_KIND)
    block.head === :block || throw(ArgumentError(
        "@elements: the body must be a `begin ... end` block; got `$(block)`"))
    return Expr(:block, [_elements_rewrite_statement(stmt, T; registry) for stmt in block.args]...)
end

"""
    _elements_rewrite_statement(stmt, T; registry=ELEMENT_META_BY_KIND) -> Any

`X = kind(args...; kws...)` and `const X = ...` become the constructor call
with `name = "X"` unless a `name` keyword is given; a bare kind call becomes
the constructor call without a name; a `line(...)` call becomes
`BeamLine(name, children...; kws...)`; a docstring-wrapped statement keeps
its docstring. The constructor is spliced as the object itself (the type or
function `element_meta(kind).friendly_constructor`), never as a name, so the
expansion does not depend on what the caller has imported; user arguments are
kept as written (the caller `esc`s the whole result). Anything else -- a
`LineNumberNode`, a binding whose right-hand side is not a kind call, a tuple
assignment, another macro call -- is returned unchanged. The call-level rule
is [`_elements_rewrite_call`](@ref).
"""
function _elements_rewrite_statement(stmt, T; registry=ELEMENT_META_BY_KIND)
    stmt isa Expr || return stmt
    if stmt.head === :macrocall && length(stmt.args) == 4 && _elements_is_doc_macro(stmt.args[1])
        return Expr(:macrocall, stmt.args[1], stmt.args[2], stmt.args[3],
                    _elements_rewrite_statement(stmt.args[4], T; registry))
    elseif stmt.head === :const && length(stmt.args) == 1
        return Expr(:const, _elements_rewrite_statement(stmt.args[1], T; registry))
    elseif stmt.head === :(=) && length(stmt.args) == 2 && stmt.args[1] isa Symbol
        return Expr(:(=), stmt.args[1],
                    _elements_rewrite_call(stmt.args[2], T, String(stmt.args[1]); registry))
    elseif stmt.head === :call
        return _elements_rewrite_call(stmt, T, nothing; registry)
    end
    return stmt
end

"""The parser's docstring wrapper, `Core.@doc` as a `GlobalRef`, or `@doc` written out."""
_elements_is_doc_macro(x) = x === Symbol("@doc") || (x isa GlobalRef && x.name === Symbol("@doc"))

"""
    _elements_rewrite_call(call, T, binding; registry=ELEMENT_META_BY_KIND) -> Any

The call-level rule. `call` is returned unchanged unless it is
`Expr(:call, head, ...)` with `head` a `Symbol` naming a registered kind
([`_elements_kind_constructor`](@ref)). Keyword arguments written after `;`
(`Expr(:parameters, ...)`) and among the positional arguments
(`Expr(:kw, k, v)`) are gathered in order; a positional argument that is
itself a kind call (`line(QF, D)` as a child of a line) is rewritten without
a name. A kind other than `:line` becomes
`ctor(; name = binding, numeric_type = T, kws...)` with the positional
arguments in place: `name` only when `binding` is a `String` and no `name`
keyword is given, `numeric_type` only when none is given (an explicit
`numeric_type =` wins, like an explicit `name =`). The `:line` kind becomes
`BeamLine(name, children...; kws...)`: the explicit `name =` keyword, else the
binding, else `""`, moved to the first positional argument, and no
`numeric_type`.
"""
function _elements_rewrite_call(call, T, binding; registry=ELEMENT_META_BY_KIND)
    (call isa Expr && call.head === :call && !isempty(call.args)) || return call
    found = _elements_kind_constructor(call.args[1], registry)
    found === nothing && return call
    kind, ctor = found
    positional = Any[]
    keywords = Any[]
    for arg in call.args[2:end]
        if arg isa Expr && arg.head === :parameters
            append!(keywords, arg.args)
        elseif arg isa Expr && arg.head === :kw
            push!(keywords, arg)
        else
            push!(positional, _elements_rewrite_call(arg, T, nothing; registry))
        end
    end
    if kind === :line
        i = findfirst(_elements_is_name_keyword, keywords)
        name_expr = i === nothing ? something(binding, "") : _elements_keyword_value(keywords[i])
        i === nothing || deleteat!(keywords, i)
        isempty(keywords) && return Expr(:call, ctor, name_expr, positional...)
        return Expr(:call, ctor, Expr(:parameters, keywords...), name_expr, positional...)
    end
    emitted = Any[]
    (binding === nothing || any(_elements_is_name_keyword, keywords)) ||
        push!(emitted, Expr(:kw, :name, binding))
    any(_elements_is_numeric_type_keyword, keywords) ||
        push!(emitted, Expr(:kw, :numeric_type, T))
    return Expr(:call, ctor, Expr(:parameters, emitted..., keywords...), positional...)
end

"""A keyword entry for `key`: `Expr(:kw, key, value)` or the `f(; key)` shorthand (the bare `Symbol`)."""
_elements_is_keyword(entry, key::Symbol) =
    entry === key || (entry isa Expr && entry.head === :kw && entry.args[1] === key)
_elements_is_name_keyword(entry) = _elements_is_keyword(entry, :name)
_elements_is_numeric_type_keyword(entry) = _elements_is_keyword(entry, :numeric_type)

"""The value expression of a keyword entry: the bare `Symbol` of the shorthand, else the `Expr(:kw)` value."""
_elements_keyword_value(entry) = entry isa Symbol ? entry : entry.args[2]
