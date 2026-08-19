export BeamLine, LineEntry, Selector, @sel_str, line_entries, line_name,
       entry_path, entry_tags, s_positions, find_entries

# ---------------------------------------------------------------------------
# Beam lines.
#
# Design, read against MAD-X, Bmad, elegant, Accelerator Toolbox and JuAcc:
# `docs/theory/beam_line_composition.md`. The four decisions that shape this
# file, each argued there:
#
#   1. A line is an ElementSpec, not a new core object, so it inherits
#      metadata, misalignment and knob resolution for free. AGENTS.md lists
#      categories, not instances.
#   2. Nesting, reflection and repetition are CONSTRUCTION syntax. A line that
#      carries nothing of its own dissolves at construction; one that carries a
#      misalignment survives as a single entry, which is what a cryostat is.
#   3. A line holds PLACEMENTS, not specs -- `[qf, d, qf]` shares one object,
#      and the two occurrences differ in s, provenance and alignment.
#   4. A parameter may live on the spec or the placement; placement wins.
#
# Reflection is `reverse`, and it reverses ORDER ONLY, matching MAD-X and Bmad.
# It does not swap `e1`/`e2` or any other end-specific parameter. Going
# backwards *through* elements is a different feature (Bmad's `--`) and is not
# implemented.
# ---------------------------------------------------------------------------

"""
    LineEntry(spec, path, tags, overrides)

One **placement** of a spec in a line: the occurrence, not the definition.

`[qf, d, qf]` shares a single `qf` object, and that is deliberate — retuning
`qf.k1` retunes the family, which is what optics matching wants. But the two
occurrences sit at different `s`, belong to different assemblies and carry
different alignment errors, so everything per-occurrence lives here instead of
on the spec. Bmad and MAD-X both split element definitions from occurrences for
the same reason.

- `spec` — the shared definition, or a nested `BeamLine` that stayed composite.
- `path` — assembly provenance as `(name, ordinal)` segments, rendered
  `ARC1/CQS[3]/QF[1]`.
- `tags` — cross-cutting labels. A magnet is in a cryostat *and* on a power
  supply *and* in a survey group, and those do not nest, which is why this is a
  set rather than a second path.
- `overrides` — per-placement parameter values, which win over the spec.

Overrides are reachable as properties, so `entry.x_offset = 1e-3` misaligns this
occurrence alone. Note that an override **detaches** the parameter from the
family permanently: a later `qf.k1 = ...` will not move it back. That is right
for an alignment error and wrong for a trim supply, which is main bus *plus*
trim — use a knob expression for that, since `resolve_knobs` runs after the
merge precisely so an override may be one.
"""
struct LineEntry
    spec::Any
    path::Vector{Tuple{String,Int}}
    tags::Set{Symbol}
    overrides::Dict{Symbol,Any}
end

LineEntry(spec, path) = LineEntry(spec, path, Set{Symbol}(), Dict{Symbol,Any}())

const _ENTRY_FIELDS = (:spec, :path, :tags, :overrides)

function Base.getproperty(entry::LineEntry, name::Symbol)
    name in _ENTRY_FIELDS && return getfield(entry, name)
    return getparam(entry, name)
end

"""
Writing a property writes an **override**, never the shared spec, so one
misaligned magnet cannot silently misalign its whole family. Bumps the spec
epoch for the same reason a spec mutation does: tasks already built from this
line must recompile at their next `execute!`.
"""
function Base.setproperty!(entry::LineEntry, name::Symbol, value)
    name in _ENTRY_FIELDS &&
        throw(ArgumentError("LineEntry.$(name) is structural and cannot be assigned; \
                             set a parameter instead, or rebuild the line"))
    _reject_folded_override(getfield(entry, :spec), name)
    getfield(entry, :overrides)[name] = value
    _SPEC_EPOCH[] += 1
    return value
end

Base.propertynames(entry::LineEntry, ::Bool=false) =
    (sort!(collect(keys(_merged_params(entry))); by=string)..., _ENTRY_FIELDS...)

"""
Named strengths are folded into `kn`/`ks` by the friendly constructors, and
`angle` into `h`/`b0`, so a spec built as `QuadrupoleSpec(k1=1.7)` stores `kn`
and no `k1` at all. An override named `k1` would therefore be written, reported
and never read — the silent no-op the parameter-effectiveness contract exists to
catch. Rejected at the point of assignment, where the message can say what to
write instead.
"""
function _reject_folded_override(spec, name::Symbol)
    spec isa ElementSpec || return nothing
    k = kind(spec)
    if k === :sbend && (name === :angle)
        throw(ArgumentError(
            "`angle` is folded into `h` and `b0` when a bend is constructed, so a \
             placement override named `angle` would never be read. Override `h` and \
             `b0` instead."))
    end
    if k === :sbend && (name === :chord)
        throw(ArgumentError(
            "`chord` is folded into the arc length `L` by RBendSpec at construction, \
             so a placement override named `chord` would never be read. Override `L` \
             with the arc length instead: L = chord * (angle/2) / sin(angle/2)."))
    end
    named = get(_FOLDED_NAMED_STRENGTHS, k, nothing)
    named === nothing && return nothing
    nk, sk = get(_FOLDED_TUPLE_KEYS, k, (:kn, :ks))
    for (nkey, skey, idx) in named
        if name === nkey || name === skey
            tuple_name = String(name === nkey ? nk : sk)
            throw(ArgumentError(
                "`$(name)` is folded into `$(tuple_name)[$(idx + 1)]` when the element \
                 is constructed, so an override or assignment named `$(name)` would \
                 never be read. Assign `$(tuple_name)` instead, e.g. \
                 `$(tuple_name) = $(ntuple(i -> i == idx + 1 ? :value : 0.0, idx + 1))`."))
        end
    end
    return nothing
end

# `_FOLDED_NAMED_STRENGTHS` / `_FOLDED_TUPLE_KEYS`, which this guard reads,
# are declared in lattice_magnets.jl and POPULATED BESIDE EACH FOLD SITE
# (lattice_magnets.jl, thin_elements.jl, solenoid.jl) rather than hand-listed
# here: this file's one-place table fell behind twice (U11-3, U15-7), and
# `_fold_named_strengths` now verifies its caller's kind against the registry
# at every construction, so an undeclared fold site fails its own
# @element_spec example at include time instead of silently narrowing this
# guard (U15-7 closure, 2026-08-07).

"""Spec parameters with this placement's overrides applied on top."""
function _merged_params(entry::LineEntry)
    spec = getfield(entry, :spec)
    base = spec isa ElementSpec ? getfield(spec, :params) : Dict{Symbol,Any}()
    overrides = getfield(entry, :overrides)
    isempty(overrides) && return base
    return merge(base, overrides)
end

getparam(entry::LineEntry, key::Symbol, default=nothing) =
    get(_merged_params(entry), key, default)
param(entry::LineEntry, key::Symbol) = _merged_params(entry)[key]

# The task epoch gate asks `_has_knob_parameters(task.elements)` to decide
# whether a knob assignment must recompile the line. A `BeamLine` hands the
# task a tuple of placements, not of specs, so without these two methods every
# placement fell through to the `false` fallback and no knob change ever
# reached a task built from a line -- `set_knob!` changed nothing while
# `knob_value` reported the new number (audit part 7, T1). A knob can sit in
# the placement's spec or in its overrides; either makes the compiled runtime
# knob-dependent. A line kept whole (one carrying state of its own) resolves
# its placements' knobs when its composite runtime is compiled, so it is
# knob-dependent whenever its own parameters or any placement is.
_has_knob_parameters(entry::LineEntry) =
    _has_knob_parameters(getfield(entry, :spec)) ||
    any(_param_has_knob, values(getfield(entry, :overrides)))
_has_knob_parameters(line::ElementSpec{:line}) =
    any(_param_has_knob, values(params(line))) ||
    _has_knob_parameters(line_entries(line))

"""Rendered provenance, e.g. `ARC1/CQS[3]/QF[1]`."""
entry_path(entry::LineEntry) =
    join((o == 1 ? n : "$(n)[$(o)]" for (n, o) in getfield(entry, :path)), "/")
entry_tags(entry::LineEntry) = getfield(entry, :tags)

Base.show(io::IO, entry::LineEntry) =
    print(io, "LineEntry(", entry_path(entry), " :: ",
          getfield(entry, :spec) isa ElementSpec ? kind(getfield(entry, :spec)) :
              nameof(typeof(getfield(entry, :spec))),
          isempty(getfield(entry, :overrides)) ? "" : ", overridden", ")")

"""
    compile_runtime(entry::LineEntry[, method])

Compile a placement: merge overrides over the spec, **then** compile.

The order matters and is not incidental. `compile_runtime` evaluates knob
expressions through `resolve_knobs`, so merging first is what lets an override
*be* a knob expression — a trim quad that tracks the main bus and adds its own
offset. Merging afterwards would silently reduce overrides to plain numbers.
"""
function compile_runtime(entry::LineEntry, args...)
    spec = getfield(entry, :spec)
    overrides = getfield(entry, :overrides)
    isempty(overrides) && return compile_runtime(spec, args...)
    merged = ElementSpec{kind(spec)}(_merged_params(entry))
    return compile_runtime(merged, args...)
end

# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

# An abstract type rather than a bare function, matching PatchSpec and
# SBendSpec: the metadata registry keys friendly constructors by type, so a
# function cannot be one.
abstract type BeamLine end

"""
    BeamLine(name, children...; tags=(), kwargs...)

A sequence of elements, expanded flat at construction with provenance recorded
on each placement.

```julia
cqs = BeamLine("CQS", corrector, quadrupole, sextupole)
arc = BeamLine("ARC1", cqs, dipole, cqs, dipole)
```

`arc` holds eight placements, and the quadrupole in the second module answers to
`ARC1/CQS[2]/QUADRUPOLE[1]`. Children may be specs, other lines, in-line hooks,
or vectors and tuples of those; `reverse` reflects and `repeat` repeats, both
being ordinary Julia.

**Nesting is construction syntax and does not survive**, matching every code
this was read against — with one exception that is the point of the design.
A line carrying parameters of its own does not dissolve; it stays a single
placement whose spec is the line. So a cryostat is one entry:

```julia
cryo = BeamLine("CRYO1", q1, q2, q3; x_offset = 2.0e-4)   # one placement
```

and misaligning it moves its contents rigidly, because `_misalignment_wrap`
wraps whatever `compile_runtime` produces. That is Bmad's `girder`, on machinery
already pinned against PTC.

Reflection reverses **order only** — `reverse` does not swap `e1`/`e2` — which
is what MAD-X and Bmad both mean by it.
"""
function BeamLine(name::AbstractString, children...; tags=(), kwargs...)
    entries = LineEntry[]
    counts = Dict{String,Int}()
    tagset = Set{Symbol}(Symbol(t) for t in tags)
    for child in children
        _append_line_child!(entries, counts, child, tagset)
    end
    myname = String(name)
    for e in entries
        pushfirst!(getfield(e, :path), (myname, 1))
    end
    params = Dict{Symbol,Any}(kwargs)
    _reject_line_length(params)
    params[:name] = myname
    params[:entries] = entries
    return ElementSpec{:line}(params)
end

_append_line_child!(entries, counts, child::Union{Tuple,AbstractVector}, tags) =
    (foreach(c -> _append_line_child!(entries, counts, c, tags), child); entries)

function _append_line_child!(entries, counts, child, tags)
    if child isa ElementSpec{:line} && !_line_has_own_state(child)
        # Dissolves. Its entries keep their internal provenance; only the
        # ordinal of its own leading segment is fixed by this parent, since a
        # line reused twice is two assemblies.
        sub = getparam(child, :entries, LineEntry[])
        subname = String(getparam(child, :name, "line"))
        occ = _next_ordinal!(counts, subname)
        for e in sub
            path = copy(getfield(e, :path))
            path[1] = (subname, occ)
            push!(entries, LineEntry(getfield(e, :spec), path,
                                     union(getfield(e, :tags), tags),
                                     copy(getfield(e, :overrides))))
        end
        return entries
    end
    label = _entry_label(child)
    occ = _next_ordinal!(counts, label)
    push!(entries, LineEntry(child, [(label, occ)], copy(tags), Dict{Symbol,Any}()))
    return entries
end

# A placement handed back as a child -- which is what `reverse`, `repeat` and
# ordinary slicing produce -- is re-placed on its spec. It gets a fresh path in
# the new line rather than keeping the old one, because it is genuinely a new
# occurrence; its tags and overrides travel with it.
function _append_line_child!(entries, counts, child::LineEntry, tags)
    spec = getfield(child, :spec)
    label = _entry_label(spec)
    occ = _next_ordinal!(counts, label)
    push!(entries, LineEntry(spec, [(label, occ)],
                             union(getfield(child, :tags), tags),
                             copy(getfield(child, :overrides))))
    return entries
end

_next_ordinal!(counts, label) = (counts[label] = get(counts, label, 0) + 1)

"""
Reflection: **order only**, which is what MAD-X and Bmad both mean by it. It does
not swap `e1`/`e2` or any other end-specific parameter, so a reflected arc of
asymmetric bends still enters through the faces it entered before. Going
backwards *through* elements is a separate feature and is not implemented.
"""
function Base.reverse(spec::ElementSpec{:line})
    # Rebuild through the params Dict, not the positional constructor: the
    # positional rebuild dropped every OWN parameter (x_offset, tilt,
    # misalign_convention, ...), so a reflected cryostat silently lost its
    # rigidity and dissolved (2026-08-05 audit, U11-2). Reflection is order
    # only, over this line's placements; a kept-whole sub-line placement is
    # one unit and its interior order is its own.
    p = copy(getfield(spec, :params))
    # Each placement is COPIED, not re-listed. Reusing the `LineEntry` objects
    # made the reflected line share their `overrides` Dict and `path` Vector
    # with the source, so a per-occurrence override written on one appeared on
    # the other: `rev[1] === inner[2]`, and `rev[1].k1 = 9.9` set
    # `getparam(inner[2], :k1) == 9.9` (2026-08-05_b audit, U15-3). That
    # contradicts the composition model directly -- theory/beam_line_composition
    # §7b: "Error parameters must not share. Every physical magnet has its own
    # misalignment. Two occurrences with a common x_offset would be a fiction."
    # `_append_line_child!` copies for this same reason; the U11-2 fix replaced
    # a positional rebuild that went through it with a direct re-listing.
    p[:entries] = Tuple(_copy_line_entry(e) for e in reverse(collect(line_entries(spec))))
    return ElementSpec{:line}(p)
end

"""A placement copy that shares no mutable state with its original."""
_copy_line_entry(e::LineEntry) = LineEntry(
    getfield(e, :spec),
    copy(getfield(e, :path)),
    copy(getfield(e, :tags)),
    copy(getfield(e, :overrides)),
)

"""Repetition: `repeat(cell, 8)` is eight placements of the cell's contents."""
Base.repeat(spec::ElementSpec{:line}, n::Integer) =
    (n >= 1 || throw(ArgumentError("repeat count must be positive, got $n"));
     BeamLine(line_name(spec), ntuple(_ -> spec, n)...))

"""
Whether a line carries anything of its own, and therefore stays a single
placement rather than dissolving (§10 of the design note). `name` and `entries`
are structure; anything else — a misalignment, a tracking method — is state.
"""
_line_has_own_state(spec::ElementSpec{:line}) =
    any(k -> k !== :name && k !== :entries, keys(getfield(spec, :params)))

"""
Path segment for a child: its `name` parameter when it has one, otherwise its
element kind, so an unnamed lattice still addresses as `ARC1/QUADRUPOLE[7]`.
"""
function _entry_label(child)
    if child isa ElementSpec
        nm = getparam(child, :name, "")
        nm isa AbstractString && !isempty(nm) && return String(nm)
        return uppercase(String(kind(child)))
    end
    return uppercase(String(nameof(typeof(child))))
end

"""
    BeamLine(; name="", entries=LineEntry[], kwargs...)

Rebuild a line from placements that already exist, skipping expansion.

This is how a slice becomes a line — `BeamLine(; name="HEAD", entries=arc[1:5])` —
and it is the form reflection introspection uses, since every element kind must
be constructible from its parameters by keyword alone.
"""
function BeamLine(; name::AbstractString="", entries=LineEntry[], kwargs...)
    params = Dict{Symbol,Any}(kwargs)
    _reject_line_length(params)
    params[:name] = String(name)
    params[:entries] = collect(LineEntry, entries)
    return ElementSpec{:line}(params)
end

"""
A line's length is DERIVED from its contents, so setting one is rejected.

Accepting it re-opened the walker split that U11-1 closed: the arc-position
walkers consult `hasparam(spec, :L)` first, while `total_length` always re-sums
the entries and `compile_runtime`'s survey merge overwrites any stored `:L` with
the computed total. A user-set value was therefore honoured by one set of
walkers and ignored by the other -- measured `total_length = 1.4` against
`_placement_length = 99.0` for the same line, and `s_positions` of its parent
reading [0.0, 99.0]. A bare `L=` also silently turned a structural line into a
girder, because `_line_has_own_state` counts any key but `:name`/`:entries`
(2026-08-05_b audit, U15-6).

The `:L` ParamMeta stays: `compile_runtime` builds its survey spec by merging
the computed total under that key, so the parameter is real -- it is just not
one a user supplies.
"""
function _reject_line_length(params)
    haskey(params, :L) || return params
    throw(ArgumentError(
        "a beam line's `L` is derived from its contents and cannot be set. " *
        "It is computed by `total_length`, and a supplied value would be " *
        "honoured by the arc-position walkers while `total_length` and the " *
        "survey ignored it. Remove `L`; to give a line its own length, give " *
        "its contents theirs."))
end

"""The placements of a line, in order."""
line_entries(spec::ElementSpec{:line}) = getparam(spec, :entries, LineEntry[])
line_name(spec::ElementSpec{:line}) = String(getparam(spec, :name, ""))

Base.length(spec::ElementSpec{:line}) = length(line_entries(spec))
Base.getindex(spec::ElementSpec{:line}, i::Integer) = line_entries(spec)[i]
Base.getindex(spec::ElementSpec{:line}, I) = line_entries(spec)[I]
Base.iterate(spec::ElementSpec{:line}, st=1) =
    st > length(spec) ? nothing : (spec[st], st + 1)
Base.firstindex(spec::ElementSpec{:line}) = 1
Base.lastindex(spec::ElementSpec{:line}) = length(spec)

"""
Length of a placement as a plain `Float64`, evaluating a knob-valued `:L`.

`Float64(::AbstractKnobExpression)` raises the directed eager-conversion error,
and knob-driven lengths are a documented first-class feature, so a bare
`Float64(getparam(...))` here made every arc-length walk over UNRESOLVED specs
throw. The one that mattered ran in the loss-file rewrite (then
`_write_task_loss_log`, today the artifact's `/losses` write), i.e. AFTER all
tracking had completed: a run with a loss file requested and a knob-valued
length tracked to the end and then died at the reporting step, losing the results. The
same walk runs in `execute!`'s catch block, so it also masked whatever original
error had stopped the run (2026-08-05_b audit, U13-5; and see U13-2).
"""
_placement_length_value(v) = v isa AbstractKnobExpression ? Float64(knob_value(v)) : Float64(v)

"""
Physical length of one placement. An own-state (non-dissolved) sub-line
stores no `:L` of its own, so every arc-length walker counted a nested
cryostat as ZERO — `s_positions`, `total_length`, the loss file's
`aperture_s`, and a misaligned parent's survey were all short by the
assembly's length (2026-08-05 audit, U11-1). The length of such a placement
is its contents'.
"""
_placement_length(e) = _placement_length_value(getparam(e, :L, 0.0))
function _placement_length(entry::LineEntry)
    spec = getfield(entry, :spec)
    if spec isa ElementSpec{:line}
        # A placement-level `:L` on a LINE was stored, reported by `getparam`,
        # and never read here -- the return above fired first (2026-08-05_b
        # audit, U15-8). "Placement wins" (beam_line_composition.md §7b) is the
        # rule for element placements, and honouring it HERE would re-open the
        # split U15-6 closed: `total_length` always re-sums the entries, so a
        # line whose placement claimed a different length would be one length to
        # one walker and another to the other. The constructor already refuses
        # `L` on a line for exactly that reason, so the placement refuses it too
        # rather than storing a value it will not use.
        haskey(getfield(entry, :overrides), :L) && throw(ArgumentError(
            "a beam line's arc length is computed from its entries and cannot be " *
            "overridden on the placement either: `L` was set on this placement of " *
            "line $(repr(getparam(spec, :name, ""))). `total_length` re-sums the " *
            "entries regardless, so the two would disagree. Change the entries, or " *
            "wrap the line in an element that does carry its own length."))
        return total_length(spec)
    end
    return _placement_length_value(getparam(entry, :L, 0.0))
end
_placement_length(spec::ElementSpec{:line}) =
    hasparam(spec, :L) ? Float64(param(spec, :L)) : total_length(spec)

"""
    s_positions(line)

Arc position of every placement: the summed `L` of everything ahead of it.

Computed rather than cached, like `_aperture_s_positions`. A `PatchSpec` carries
its path length in `dz` and not `L`, so a line containing one reports arc length
that omits it — see the design note; and this is arc length only, never where a
magnet sits in space.
"""
function s_positions(spec::ElementSpec{:line})
    entries = line_entries(spec)
    out = Vector{Float64}(undef, length(entries))
    s = 0.0
    for (i, e) in enumerate(entries)
        out[i] = s
        s += _placement_length(e)
    end
    return out
end

# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

"""One path segment of a [`Selector`](@ref)."""
struct SelectorSegment
    name::String                      # "*" matches any
    ordinal::Union{Nothing,Int}       # nothing matches any occurrence
    descendant::Bool                  # preceded by `//`
end

"""
    Selector

A compiled path selector, in XPath's shape: `/` for hierarchy, `//` for any
depth, `[n]` for a 1-based ordinal, `*` for a wildcard.

Written with the [`@sel_str`](@ref) macro, which parses once so a selector is a
value to keep rather than a string re-parsed at each call:

```julia
sel"ARC1/CQS[3]"        # the third CQS module
sel"ARC1//quadrupole"   # every quadrupole anywhere under ARC1
sel"ARC1/CQS[*]/QF"     # the QF of every CQS module
```

A segment matches an entry's name or, for an unnamed element, its kind. There
are deliberately **no attribute predicates**: a `Function` selector passed to
[`find_entries`](@ref) covers them with no grammar to parse or document.
"""
struct Selector
    segments::Vector{SelectorSegment}
end

Base.show(io::IO, s::Selector) = print(io, "sel\"", _render(s), "\"")
_render(s::Selector) = join((string(seg.descendant ? "/" : "", seg.name,
                                    seg.ordinal === nothing ? "" : "[$(seg.ordinal)]")
                             for seg in s.segments), "/")

"""
    sel"ARC1/CQS[3]"

Parse a [`Selector`](@ref) at macro-expansion time, so a malformed path is an
error where it is written rather than at the call that uses it.
"""
macro sel_str(str)
    return QuoteNode(_parse_selector(str))
end

function _parse_selector(str::AbstractString)
    isempty(strip(str)) && throw(ArgumentError("empty selector"))
    segments = SelectorSegment[]
    descendant = false
    for (i, part) in enumerate(split(str, '/'))
        if isempty(part)
            i == 1 && continue          # a leading "/" is just an anchor
            descendant = true
            continue
        end
        push!(segments, _parse_segment(part, str, descendant))
        descendant = false
    end
    isempty(segments) && throw(ArgumentError("selector $(repr(str)) has no segments"))
    return Selector(segments)
end

function _parse_segment(part::AbstractString, whole::AbstractString, descendant::Bool)
    m = match(r"^([^\[\]]+)(?:\[(\*|\d+)\])?$", part)
    m === nothing && throw(ArgumentError(
        "cannot parse $(repr(String(part))) in selector $(repr(String(whole))); \
         expected NAME, NAME[n] or NAME[*]"))
    ord = m.captures[2]
    ordinal = ord === nothing || ord == "*" ? nothing : parse(Int, ord)
    ordinal !== nothing && ordinal < 1 && throw(ArgumentError(
        "ordinals are 1-based; got $(ordinal) in selector $(repr(String(whole)))"))
    return SelectorSegment(String(m.captures[1]), ordinal, descendant)
end

_segment_matches(seg::SelectorSegment, (name, ord)::Tuple{String,Int}) =
    (seg.name == "*" || _label_equal(seg.name, name)) &&
    (seg.ordinal === nothing || seg.ordinal == ord)

# Names are compared case-insensitively: lattice files disagree about case and
# nobody means `QF` and `qf` to be different magnets.
_label_equal(a, b) = lowercase(a) == lowercase(b)

"""
Whether a selector matches a **prefix** of a path. Prefix, so selecting an
assembly selects everything inside it: `ARC1/CQS[3]` yields the module's
elements, not just a node standing for the module.
"""
function _path_matches(segments, path, si::Int=1, pi::Int=1)
    si > length(segments) && return true
    seg = segments[si]
    if seg.descendant
        for k in pi:length(path)
            _segment_matches(seg, path[k]) &&
                _path_matches(segments, path, si + 1, k + 1) && return true
        end
        return false
    end
    pi > length(path) && return false
    return _segment_matches(seg, path[pi]) && _path_matches(segments, path, si + 1, pi + 1)
end

"""
    find_entries(line, selector) -> Vector{Int}

Indices of the placements a selector matches. One entry point for every kind of
lookup, as Accelerator Toolbox does with `Refpts`, instead of a family of
`by_name`/`by_class`/`by_regex` functions each with `first`/`last` variants —
`first(find_entries(...))` already exists.

`selector` may be a [`Selector`](@ref), a `String` (parsed as one), a `Regex`
matched against the rendered path, a `Symbol` matched against tags, a `Type`
matched against the spec, or any predicate `LineEntry -> Bool`.

```julia
find_entries(line, sel"ARC1/CQS[3]")
find_entries(line, r"^ARC1/CQS")
find_entries(line, :cryostat)                     # a tag
find_entries(line, e -> getparam(e, :L, 0) > 1)   # anything else
```
"""
find_entries(spec::ElementSpec{:line}, selector) =
    findall(e -> _entry_matches(e, selector), line_entries(spec))

_entry_matches(e::LineEntry, s::Selector) = _path_matches(s.segments, getfield(e, :path))
_entry_matches(e::LineEntry, s::AbstractString) = _entry_matches(e, _parse_selector(s))
_entry_matches(e::LineEntry, s::Regex) = occursin(s, entry_path(e))
_entry_matches(e::LineEntry, s::Symbol) = s in getfield(e, :tags)
_entry_matches(e::LineEntry, s::Type) = getfield(e, :spec) isa s
_entry_matches(e::LineEntry, s) = Bool(s(e))

# ---------------------------------------------------------------------------
# Composite runtime, for a line that did not dissolve.
#
# This is what makes a cryostat work. A line carrying a misalignment stays one
# placement, compiles to one op, and `_misalignment_wrap` encloses the whole
# thing -- frame change in, every contained element tracked, frame change out.
# That is Bmad's `girder`, using the machinery the misalignment work already
# pinned against PTC, and it is the reason `ElementSpec` was the right base.
# ---------------------------------------------------------------------------

"""
    CompositeLine(ops)

The runtime of a line that stayed composite: its elements' runtimes, tracked in
order as a single map.
"""
struct CompositeLine{T<:Tuple} <: AbstractTrackOp
    ops::T
end

# Both call paths delegate to `fusedTrack`, which is `@generated` and unrolls
# the (possibly nested) op tuple at COMPILE time.
#
# The runtime `for op in elem.ops` these replace could not compile for CUDA:
# indexing a heterogeneous `Tuple` with a non-constant index lowers to
# `ijl_get_nth_field_checked`, which has no device implementation, so a
# kept-whole line — a girder or cryostat, this file's flagship feature — threw
# `InvalidIRError` on a `CuArray` rep for every assembly whose members were not
# all one concrete type, i.e. every realistic one. A homogeneous line happened
# to compile, which is why it survived (2026-08-05_b audit, U15-1).
#
# Delegating also lets each op supply its OWN tracking method, via its own call
# operator, instead of having the first op's method imposed on all of them —
# so a mixed-method assembly (an aperture is `NonSymplectic6DMap`, a magnet
# `Symplectic6DMap`) now tracks on this path as it already did on the ctx path
# (U15-4). The `method` argument is retained for signature compatibility with
# the `track_particle` family and is deliberately unused.
@inline track_particle(::AbstractTrackingMethod, elem::CompositeLine,
                       x, px, y, py, z, pz) =
    fusedTrack(elem.ops, x, px, y, py, z, pz)

@inline (elem::CompositeLine)(x, px, y, py, z, pz) =
    fusedTrack(elem.ops, x, px, y, py, z, pz)

# Forward the tracking context to every member op (F13, 2026-08-05 audit):
# a stochastic element inside a composite line must see the same ctx it
# would see placed directly in the task line.
@inline (elem::CompositeLine)(ctx::TrackingContext, particle_id,
                              x, px, y, py, z, pz) =
    fusedTrack(ctx, elem.ops, particle_id, x, px, y, py, z, pz)

# A composite has no method of its own; it borrows its first element's, which is
# what the wrappers ask for when a misaligned line is tracked directly.
_inner_method(elem::CompositeLine) =
    isempty(elem.ops) ? Symplectic6DMap() : _inner_method(first(elem.ops))

"""Total arc length of a line, used for the survey when it is misaligned."""
total_length(spec::ElementSpec{:line}) =
    sum(_placement_length, line_entries(spec); init=0.0)

function compile_runtime(spec::ElementSpec{:line}, args...)
    # A line has no tracking method of its own -- each placement compiles with
    # its own -- and the metadata advertises none. Accepting and discarding an
    # explicit request here made the line silently "support" every method
    # (audit part 7, K8), against the rule that a non-default request must be
    # honoured or rejected.
    isempty(args) || throw(ArgumentError(
        "a line has no tracking method of its own; each placement compiles " *
        "with its spec's tracking_method. Set tracking_method on the " *
        "placements instead of passing one to compile_runtime for the line."))
    resolved = resolve_knobs(spec)
    ops = Tuple(compile_runtime(e) for e in line_entries(resolved))
    # The survey needs the line's length, which is derived rather than stored --
    # storing it would count as "own state" and stop every line from dissolving.
    geom = ElementSpec{:line}(merge(getfield(resolved, :params),
                                    Dict{Symbol,Any}(:L => total_length(resolved))))
    # The girder faces come from the line's COMPOSED floor-plan frames, not a
    # straight 1D survey: `design` hands `_misalignment_wrap` the frame at the
    # reference point (entrance or arc-length centre, per convention) and at
    # the exit, walked with the same `_floor_step`s the `survey` export
    # composes. Until 2026-08-16 the wrap read h = 0 from `geom` and built
    # both faces straight, so a misaligned line whose contents BEND had an
    # exit patch wrong at first order in the bend angle -- measured against
    # the same rigid displacement applied to the bend directly:
    # max|girder - element| = 1.0e-6 at angle 1e-3, 1.99e-4 at 0.198, 4.05e-4
    # at 0.4, exactly dx*theta, and exactly 0 for a straight body (2026-08-05_b
    # audit, U15-2; closed when the floor plan supplied the frames the wrap
    # always needed). The same comparison is now the EXACTNESS pin: girder
    # equals element to 1e-14 at every angle, both conventions, and the loud
    # "surveyed as STRAIGHT" warning retired with the limitation it announced.
    design = function (::Type{T}, which::Symbol) where {T}
        starget = which === :entrance ? 0.0 : Float64(total_length(resolved)) / 2
        Wr, Vr, We, Ve = _girder_design_frames(resolved, starget)
        return (map(T, Wr), map(T, Vr), map(T, We), map(T, Ve))
    end
    return _ref_tilt_wrap(geom, _misalignment_wrap(geom, CompositeLine(ops);
                                                   design=design))
end

# The old U15-2 warning path's helpers (`_line_is_misaligned`,
# `_line_net_bend`) are gone with the warning itself (2026-08-16): the girder
# survey is exact now, `_misalignment_wrap` already no-ops on an unaligned
# line, and a helper that existed only to decide whether the straight survey
# was a lie has nothing left to decide.

@element_spec begin
    kind = :line
    spec_type = ElementSpec{:line}
    friendly_constructor = BeamLine
    description = "A sequence of elements, expanded flat with per-placement provenance."
    keywords = [:beam_line, :thick_element]
    tracking_methods = DataType[]
    contracts = DataType[]
    analyses = [PlaceholderAnalysis]
    parameters = (
        name=ParamMeta(default="", meaning="line name; becomes the leading path segment of every placement it contains"),
        entries=ParamMeta(default=(), meaning="the expanded placements. Built by BeamLine(name, children...) from nested children; the keyword form takes them ready-made, which is how a slice becomes a line"),
        x_offset=ParamMeta(default=0, meaning="misalignment of the WHOLE LINE, which is what makes a girder or cryostat: a line carrying one does not dissolve into its parent, it stays a single placement and moves its contents rigidly. The assembly survey is STRAIGHT: if the line contains bends its exit patch is wrong at first order in the bend angle (order dx*theta), and compiling one warns. Misalign bending elements individually where that matters"),
        y_offset=ParamMeta(default=0, meaning="vertical misalignment of the whole line"),
        z_offset=ParamMeta(default=0, meaning="longitudinal misalignment of the whole line"),
        x_pitch=ParamMeta(default=0, meaning="rotation of the whole line about the y axis, in radians"),
        y_pitch=ParamMeta(default=0, meaning="rotation of the whole line about the x axis, in radians"),
        tilt=ParamMeta(default=0, meaning="roll of the whole line about the longitudinal axis, in radians"),
        misalign_convention=_COMMON_PARAMS.misalign_convention,
        L=ParamMeta(default=0.0, unit="m", meaning="total arc length of the expanded line. DERIVED, not settable: `compile_runtime` merges the computed `total_length` under this key so a nested own-state line surveys at its real length rather than zero, and `BeamLine` rejects a supplied `L`. Nothing stores it on a user's line, so a supplied value would be honoured by the arc-position walkers and ignored by `total_length` and the survey"),
        ref_tilt=_PLACEMENT_PARAMS.ref_tilt,
    )
    example = BeamLine("CELL", QuadrupoleSpec(L=0.4, k1=1.7, nst=2))
    construction_help = "Friendly constructor: BeamLine(name, children...; tags=(), kwargs...); children may be element specs, other lines, in-line hooks, or vectors/tuples of those. Nesting, reverse (reflection -- ORDER ONLY, it does not swap e1/e2) and repeat are construction syntax and expand away, with provenance kept per placement so ARC1/CQS[3] stays addressable. A line given a misalignment does NOT dissolve: it stays one placement and moves its contents rigidly, which is how a cryostat or girder is expressed. Select with find_entries(line, sel\"ARC1/CQS[3]\"), which also takes a Regex, a tag Symbol, a Type or a predicate. Keyword form BeamLine(; name, entries) rebuilds a line from existing placements. The misalignment keywords x_offset, y_offset, z_offset, x_pitch, y_pitch and tilt displace the WHOLE line rigidly and are what make it a girder, with misalign_convention choosing the reference point and rotation order exactly as it does for a single magnet. A line's arc length L is COMPUTED from its entries and is not a keyword: setting it is rejected, because the walkers that read a stored L and the ones that re-sum the entries would then disagree (2026-08-05_b audit, U15-6). Design: docs/theory/beam_line_composition.md. Placement (every kind, consumed by the compile-time misalignment and design-roll wraps): x_offset, y_offset, z_offset [m], x_pitch, y_pitch, tilt, ref_tilt [rad], misalign_convention (:bmad or :madx). name: an optional label, carried into beam-line provenance paths and diagnostics, never read by a tracking kernel."
end

# ---------------------------------------------------------------------------
# The container-scoped knob report: the WIRING view of the knob system.
# ---------------------------------------------------------------------------

"""
    knob_report(elements; prefix="", io=stdout)

The **wiring** view of the knob system, scoped to the given container — a
line spec, a `BeamLine`, or a tuple of specs/placements: which element
parameters hold knob expressions, printed in both directions (per knob, the
driven sites; per site, the expression and its current value). The
zero-argument `knob_report(; prefix)` remains the **registry** view — the
declared knobs and their values; this method answers the question the
registry cannot: *what does this knob actually drive in this lattice?*

Derived on demand from the specs themselves, never registered: expressions
are plain values that are copied freely (placement overrides, line
expansion, spec merges), so a global binding registry would go stale the
way stored copies always do here. The cost of the derive-on-demand choice
is the container scope — the same knob can drive two lines differently, and
the report answers only for the elements it is handed. A knob expression
bound to a plain Julia variable is deliberately invisible: an expression is
inert until it is stored on a spec parameter, and findability begins there.

Placement overrides are read through the merged view, so an
expression-valued override reports at its placement path. Expressions
nested in tuple strengths report with their index (`kn[2]`). Sites whose
expressions read no knob under `prefix` are filtered out when a prefix is
given.

The two reference designs, measured (2026-08-14): Tao prints a lord's
slaves with expression text and evaluated contributions and a slave's
"Controller Lord(s)" — but Bmad sums stacked overlays into one attribute,
where an Octopus parameter holds exactly one expression; Xsuite's
`.xdeps.info()` gives per-variable `controlled_targets` from a live global
graph, which it can afford because every assignment flows through its
ref/view machinery — Octopus expressions are plain values, hence this
query. MAD-X has the forward direction only; elegant has neither.
"""
function knob_report(elements::Union{Tuple,AbstractVector,ElementSpec{:line}};
                     prefix::AbstractString="", io::IO=stdout)
    sites = NamedTuple{(:site, :param, :expr),Tuple{String,String,Any}}[]
    _knob_binding_sites!(sites, elements, Ref(0))
    if !isempty(prefix)
        filter!(s -> any(d -> startswith(String(d), prefix),
                         _site_knobs(s.expr)), sites)
    end
    if isempty(sites)
        println(io, isempty(prefix) ?
            "No knob-driven parameters in the given elements." :
            "No knob-driven parameters under $(repr(prefix)) in the given elements.")
        return nothing
    end
    render(s) = begin
        val = try
            string(knob_value(s.expr))
        catch err
            "unassigned: " * sprint(showerror, err)
        end
        "$(s.site) :: $(s.param) = $(string(s.expr))  (= $(val))"
    end
    byknob = Dict{Symbol,Vector{Int}}()
    for (i, s) in enumerate(sites), d in _site_knobs(s.expr)
        push!(get!(Vector{Int}, byknob, d), i)
    end
    println(io, "Knob-driven parameters ($(length(sites)) site(s); ",
            "registry view: knob_report()):")
    println(io)
    println(io, "By knob:")
    for d in sort!(collect(keys(byknob)); by=string)
        println(io, "  ", d, " = ",
                try string(knob_value(d)) catch; "<unassigned>" end)
        for i in byknob[d]
            println(io, "    ", render(sites[i]))
        end
    end
    println(io)
    println(io, "By site:")
    for s in sites
        println(io, "  ", render(s),
                "  [knobs: ", join(string.(_site_knobs(s.expr)), ", "), "]")
    end
    return nothing
end

# The knobs a binding SITE reads. `knob_dependencies` deliberately reports a
# bare KnobRef's own dependencies (empty for an independent knob) because it
# answers "what does this knob read"; a wiring site bound to a bare reference
# depends on THAT knob, so the ref's own path joins the set here.
_site_knobs(expr::KnobRef) = Symbol[_knob_path(expr)]
_site_knobs(expr) = knob_dependencies(expr)

_knob_binding_sites!(out, elements::Union{Tuple,AbstractVector}, ordinal) =
    (foreach(e -> _knob_binding_sites!(out, e, ordinal), elements); out)
_knob_binding_sites!(out, line::ElementSpec{:line}, ordinal) =
    _knob_binding_sites!(out, line_entries(line), ordinal)
function _knob_binding_sites!(out, entry::LineEntry, ordinal)
    spec = getfield(entry, :spec)
    spec isa ElementSpec{:line} &&
        return _knob_binding_sites!(out, line_entries(spec), ordinal)
    spec isa AbstractElementSpec || return out
    ordinal[] += 1
    _knob_param_sites!(out, entry_path(entry), _merged_params(entry))
    return out
end
function _knob_binding_sites!(out, element, ordinal)
    element isa AbstractElementSpec || return out
    if element isa ElementSpec{:line}
        return _knob_binding_sites!(out, line_entries(element), ordinal)
    end
    ordinal[] += 1
    _knob_param_sites!(out, "elements[$(ordinal[])] ($(kind(element)))",
                       getfield(element, :params))
    return out
end

function _knob_param_sites!(out, site::AbstractString, params)
    for (key, val) in sort!(collect(params); by=x -> string(x[1]))
        _param_has_knob(val) || continue
        _knob_value_sites!(out, String(site), String(key), val)
    end
    return out
end
_knob_value_sites!(out, site, label, v) = nothing
_knob_value_sites!(out, site, label, v::AbstractKnobExpression) =
    push!(out, (site=site, param=label, expr=v))
function _knob_value_sites!(out, site, label, v::Union{Tuple,AbstractArray})
    for (i, x) in enumerate(v)
        _param_has_knob(x) && _knob_value_sites!(out, site, "$(label)[$(i)]", x)
    end
    return nothing
end
