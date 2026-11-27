#=
The suite's files as UNITS: each top-level expression with its line span, the
comment run directly above it, its kind and its name, read through Julia's
parser. Shared by the driver's layout tripwire (`test/runtests.jl`), the block
mover (`test/move_testsets.jl`) and the extracted-testset runner
(`test/run_extracted_testsets.jl`), so that the three read a suite file one
way. Not a regex over indentation: the lane-gated testsets sit at column 0
inside their `if _lane_gate(...)`, and several column-0 `end` lines close
indented openers, so "the first column-0 `end`" is not where a block ends;
`Meta.parseall` is. No dependency on Octopus or Test: a plain `include`.
=#

struct SuiteUnit
    kind::Symbol      # :testset, :gated, :block, :def, :method, :using, :other
    name::String      # the title (:testset, :gated), the defined name (:def, :method), else ""
    prefix::Int       # first line of the comment run directly above the unit (== first when none)
    first::Int        # first line of the expression
    last::Int         # last line of the expression (trailing blank and comment lines excluded)
    expr::Any
end

_su_comment(l) = startswith(lstrip(l), "#")
_su_blank(l) = isempty(strip(l))

# The name a signature or type head defines: `f(x)`, `f(x)::T`, `f(x) where T`,
# `Octopus.f(x)`, `S{T} <: U`, `(::Type{T})(x)` (reported as `Type`).
function _su_signature_name(sig)
    sig isa Symbol && return string(sig)
    sig isa Expr || return ""
    h = sig.head
    h in (:call, :where, :curly, :(<:)) && return _su_signature_name(sig.args[1])
    h === :(::) && return _su_signature_name(sig.args[1])
    if h === :(.) && length(sig.args) == 2
        field = sig.args[2] isa QuoteNode ? sig.args[2].value : sig.args[2]
        return string(_su_signature_name(sig.args[1]), ".", field)
    end
    return ""
end

# `a, b` on the left of `=`: the names, comma-joined (`unit_names` splits them).
_su_tuple_names(t) = join((string(a) for a in t.args if a isa Symbol), ",")

function _su_classify(ex)
    ex isa Expr || return (:other, "")
    h = ex.head
    if h === :macrocall
        m = ex.args[1]
        if m === Symbol("@testset")
            title = length(ex.args) >= 3 && ex.args[3] isa String ? ex.args[3] : ""
            return (:testset, title)
        elseif m isa GlobalRef && m.mod === Core && m.name === Symbol("@doc")
            return _su_classify(ex.args[end])          # a documented definition
        end
        inner = ex.args[end]                           # `@inline f(x) = ...`, `Base.@propagate_inbounds function ...`
        kind, name = inner isa Expr ? _su_classify(inner) : (:other, "")
        return kind in (:def, :method) ? (kind, name) : (:other, "")
    elseif h === :if
        c = ex.args[1]
        if c isa Expr && c.head === :call && c.args[1] === :_lane_gate && length(c.args) == 2 && c.args[2] isa String
            return (:gated, c.args[2])
        end
        return (:block, "")
    elseif h in (:let, :for, :while, :block, :try)
        return (:block, "")
    elseif h === :function || h === :(=)
        lhs = ex.args[1]
        if h === :(=) && lhs isa Symbol
            return (:def, string(lhs))                 # a file-level assignment
        elseif h === :(=) && lhs isa Expr && lhs.head === :tuple
            return (:def, _su_tuple_names(lhs))        # `a, b = ...`
        end
        n = _su_signature_name(lhs)
        isempty(n) && return (:other, "")
        return (occursin(".", n) ? :method : :def, n)
    elseif h === :macro
        return (:def, "@" * _su_signature_name(ex.args[1]))
    elseif h === :struct
        return (:def, _su_signature_name(ex.args[2]))
    elseif h === :abstract || h === :primitive
        return (:def, _su_signature_name(ex.args[1]))
    elseif h === :const
        inner = ex.args[1]
        inner isa Expr && inner.head === :(=) || return (:other, "")
        lhs = inner.args[1]
        lhs isa Expr && lhs.head === :tuple && return (:def, _su_tuple_names(lhs))   # `const a, b = ...`
        return (:def, _su_signature_name(lhs))
    elseif h === :using || h === :import
        return (:using, "")
    end
    return (:other, "")
end

"""
    suite_units(text; filename="suite") -> Vector{SuiteUnit}

The top-level expressions of a suite file with their spans. A parse `:error`
or `:incomplete` is an error here (a same-anchor merge once left a testset
unclosed and `Meta.parseall` called it `:incomplete`, docs/experiences.md).
"""
function suite_units(text::AbstractString; filename::AbstractString="suite")
    lines = split(text, '\n'; keepempty=true)
    top = Meta.parseall(String(text); filename=String(filename))
    top isa Expr && top.head === :toplevel || error("$(filename): not a toplevel parse")
    starts = Int[]
    exprs = Any[]
    line = 0
    for a in top.args
        if a isa LineNumberNode
            line = a.line
        else
            a isa Expr && a.head in (:error, :incomplete) &&
                error("$(filename) line $(line): parse $(a.head): $(sprint(show, a)[1:min(end, 200)])")
            push!(starts, line)
            push!(exprs, a)
        end
    end
    n = length(lines)
    units = SuiteUnit[]
    for (k, s) in enumerate(starts)
        e = k < length(starts) ? starts[k + 1] - 1 : n
        while e > s && (_su_blank(lines[e]) || _su_comment(lines[e]))
            e -= 1
        end
        floor = isempty(units) ? 0 : units[end].last
        p = s - 1
        while p > floor && _su_comment(lines[p])
            p -= 1
        end
        kind, name = _su_classify(exprs[k])
        push!(units, SuiteUnit(kind, name, p + 1, s, e, exprs[k]))
    end
    return units
end

function _su_symbols!(acc::Set{Symbol}, x)
    if x isa Symbol
        push!(acc, x)
    elseif x isa Expr
        if x.head === :(.) && length(x.args) == 2 && x.args[2] isa QuoteNode
            _su_symbols!(acc, x.args[1])               # `M.f`: the module is a reference, the field is not
        else
            foreach(a -> _su_symbols!(acc, a), x.args)
        end
    elseif x isa QuoteNode
        _su_symbols!(acc, x.value)
    end
    return acc
end

"Every symbol the unit's expression mentions (fields after a dot excluded)."
unit_symbols(u::SuiteUnit) = _su_symbols!(Set{Symbol}(), u.expr)

"The names a `:def` unit defines (several for `const a, b = ...`), else the unit's name alone."
unit_names(u::SuiteUnit) = u.kind === :def ? String.(split(u.name, ','; keepempty=false)) : [u.name]

"The text of a unit with the comment run above it."
unit_text(lines::AbstractVector, u::SuiteUnit) = join(lines[u.prefix:u.last], "\n")

"""
    suite_cross_references(units_by_file; shared=("common.jl",)) -> Vector{String}

The layout rule of the split suite: a file may use the column-0 definitions of
the `shared` files and its own, and no other file's. Returns one line per
violation (`"<file> uses <name> of <other file>"`), plus one per definition
name or block title that two files carry.
"""
function suite_cross_references(units_by_file::AbstractDict; shared=("common.jl",))
    files = sort(collect(keys(units_by_file)))
    defs = Dict(f => Set(n for u in units_by_file[f] if u.kind === :def for n in unit_names(u)) for f in files)
    syms = Dict(f => (isempty(units_by_file[f]) ? Set{Symbol}() :
                      union((unit_symbols(u) for u in units_by_file[f])...)) for f in files)
    out = String[]
    for f in files, g in files
        (f == g || g in shared) && continue
        for name in sort(collect(defs[g]))
            Symbol(name) in syms[f] && !(name in defs[f]) && push!(out, "$(f) uses $(name) of $(g)")
        end
    end
    for (i, f) in enumerate(files), g in files[i + 1:end]
        for name in sort(collect(intersect(defs[f], defs[g])))
            push!(out, "$(name) is defined in both $(f) and $(g)")
        end
    end
    titles = Dict{String,Vector{String}}()
    for f in files, u in units_by_file[f]
        u.kind in (:testset, :gated) && !isempty(u.name) && push!(get!(titles, u.name, String[]), f)
    end
    for (t, fs) in sort(collect(titles); by=first)
        length(fs) > 1 && push!(out, "title $(repr(t)) appears in " * join(fs, ", "))
    end
    return out
end
