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
   `numeric_type`, so every element of the block shares the lattice's type.
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
    # TODO(unit B): (T, block) = _elements_header(args) -- `@elements begin ... end`
    # gives T = :Float64, `@elements T begin ... end` gives the escaped T;
    # refuse any other shape by name. Then esc(_elements_rewrite_block(block, T)).
    error("TODO unit B: @elements")
end

"""
    @element T X = kind(...)
    @element X = kind(...)           # T = Float64

One declaration under the rules of [`@elements`](@ref): the same rewriting of a
registered kind name onto its friendly constructor, the binding name as the
default `name`, the numeric type from the header.
"""
macro element(args...)
    error("TODO unit B: @element")
end

"""
    _elements_header(args) -> (T::Union{Symbol,Expr}, block::Expr)

Split the macro arguments into the numeric type and the block (or the single
statement for `@element`). Refuses by name a block that is not a `begin ...
end`, a header that is not a type expression, and extra arguments.
"""
function _elements_header(args)
    error("TODO unit B")
end

"""
    _elements_kind_constructor(head) -> Union{Nothing,Tuple{Symbol,Any}}

`(kind, friendly_constructor)` when `head` is a `Symbol` naming a registered
kind (`ELEMENT_META_BY_KIND`), `nothing` otherwise; a registered kind with no
friendly constructor throws the rule-4 refusal, naming the kind and the
flexible form.
"""
function _elements_kind_constructor(head)
    error("TODO unit B")
end

"""
    _elements_rewrite_block(block::Expr, T) -> Expr

Walk the block's top-level statements and rewrite each through
[`_elements_rewrite_statement`](@ref); line numbers and non-statement
expressions pass through.
"""
function _elements_rewrite_block(block::Expr, T)
    error("TODO unit B")
end

"""
    _elements_rewrite_statement(stmt, T) -> Any

`X = kind(args...; kws...)` and `const X = ...` become the constructor call
with `name = "X"` unless a `name` keyword is given; a bare kind call becomes
the constructor call without a name; a `line(...)` call becomes
`BeamLine(name, children...; kws...)`. The constructor is spliced as a
`GlobalRef` into this module, so the expansion does not depend on what the
caller has imported; user arguments are kept as written (the caller `esc`s
the whole result).
"""
function _elements_rewrite_statement(stmt, T)
    error("TODO unit B")
end
