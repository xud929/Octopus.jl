export ReferenceParticle, Lattice

# ---------------------------------------------------------------------------
# The machine description, stage 2 (design note docs/design/machine_description.md:
# D3 the record, D7 the knob roots, D12 the reference particle, D15 the
# additive task acceptance, D16 where it lives). `Lattice` is a small record
# around a top-level `BeamLine`: the line, the entrance `ReferenceParticle`,
# the knob roots the line's expressions must live under, the numeric type
# every element must share, and a name for provenance. It is NOT a parameter
# set on the line (a line carrying parameters of its own stops dissolving when
# nested, beam_line_composition.md section 10) and NOT a Core Object: a
# record, like `LinearOptics`, with no abstract root and no registry category.
# Nothing here reaches a kernel; the runtime is derived from the line as
# today, and a task given a `Lattice` sees exactly the placements the bare
# line gives (`_element_tuple`, src/tasks/Tasks.jl; `_linearizable`,
# src/analysis/one_turn_matrix.jl).
# ---------------------------------------------------------------------------

"""
    ReferenceParticle(; charge, mc2, E0)     # total energy in eV
    ReferenceParticle(; charge, mc2, p0c)    # or the momentum p0 c in eV

The reference particle of a lattice (design D12): the species as the charge in
units of e and the rest energy `mc2` in eV, and the momentum as either the
total energy `E0` or `p0c`, both in eV, exactly one of the two (`E0` is what
is stored; `p0c` gives `E0 = sqrt(p0c^2 + mc2^2)`). The relativistic factors
follow from the existing accessors, `reference_beta_gamma(ref)`,
`reference_beta(ref)` and `reference_gamma(ref)`, so a script that derives
`beta0, gamma0` by hand today derives them from the lattice's reference
instead.

Refused by name at construction: a non-finite or zero `charge`; a non-finite
or non-positive `mc2`; both or neither of `E0` and `p0c`; an `E0` not above
`mc2` (a reference at rest has no direction and `beta0 = 0` divides every
cavity); a non-finite or non-positive `p0c`.

Stage 2 of the machine description accepts the type and carries it on the
[`Lattice`](@ref); the consumers that spell the reference by hand today
(`Beam`'s `charge`, `mc2`, `E0`; the cavities' `beta0`, `gamma0`; the
strong-beam kick scale) keep their keywords and are unified in a compile-path
campaign of their own (design D12 and section 3).
"""
struct ReferenceParticle
    charge::Float64
    mc2::Float64
    E0::Float64
end

function ReferenceParticle(; charge, mc2, E0=nothing, p0c=nothing)
    # The refusals of the docstring, by name, before anything is built. An
    # OUTER constructor: the default inner one stays available to tests that
    # need a raw instance.
    (charge isa Real && isfinite(charge) && !iszero(charge)) || throw(ArgumentError(
        "ReferenceParticle: `charge` must be a finite, nonzero number of elementary " *
        "charges (1 for a proton, -1 for an electron); got $(repr(charge))"))
    (mc2 isa Real && isfinite(mc2) && mc2 > 0) || throw(ArgumentError(
        "ReferenceParticle: `mc2` must be a finite, positive rest energy in eV " *
        "(PMASS_EV for a proton, EMASS_EV for an electron); got $(repr(mc2))"))
    if E0 !== nothing && p0c !== nothing
        throw(ArgumentError(
            "ReferenceParticle: give exactly one of `E0` (the total energy in eV) and " *
            "`p0c` (the momentum times c in eV), not both; got E0 = $(repr(E0)) and " *
            "p0c = $(repr(p0c))"))
    elseif E0 === nothing && p0c === nothing
        throw(ArgumentError(
            "ReferenceParticle: give exactly one of `E0` (the total energy in eV) and " *
            "`p0c` (the momentum times c in eV); neither was given"))
    end
    if E0 !== nothing
        (E0 isa Real && isfinite(E0) && E0 > mc2) || throw(ArgumentError(
            "ReferenceParticle: `E0` is the TOTAL energy in eV and must exceed " *
            "`mc2` = $(mc2) eV (a reference at rest has no direction and beta0 = 0 " *
            "divides every cavity); got E0 = $(repr(E0))"))
        return ReferenceParticle(Float64(charge), Float64(mc2), Float64(E0))
    end
    (p0c isa Real && isfinite(p0c) && p0c > 0) || throw(ArgumentError(
        "ReferenceParticle: `p0c` must be a finite, positive momentum times c in eV; " *
        "got $(repr(p0c))"))
    return ReferenceParticle(Float64(charge), Float64(mc2),
                             sqrt(Float64(p0c)^2 + Float64(mc2)^2))
end

reference_beta_gamma(ref::ReferenceParticle) = reference_beta_gamma(ref.E0, ref.mc2)
reference_beta(ref::ReferenceParticle) = reference_beta(ref.E0, ref.mc2)
reference_gamma(ref::ReferenceParticle) = reference_gamma(ref.E0, ref.mc2)

function Base.show(io::IO, ref::ReferenceParticle)
    # One line, with units: ReferenceParticle(charge = 1.0, mc2 = 9.38e8 eV, E0 = 3.0e9 eV)
    print(io, "ReferenceParticle(charge = ", ref.charge, ", mc2 = ", ref.mc2, " eV, E0 = ", ref.E0, " eV)")
end

"""
    Lattice(name; line, reference=nothing, knob_root=nothing, eltype=Float64)

A beam's lattice: a top-level [`BeamLine`](@ref) with the context the line does
not carry (design D3). `name` is the lattice's provenance label; `line` is the
sequence, an `ElementSpec{:line}` built by `BeamLine`; `reference` is the
entrance [`ReferenceParticle`](@ref) (D12), carried and not yet consumed by the
elements; `knob_root` names the knob namespace(s) every knob expression in the
line must live under (one root, or a tuple of roots when the lattice also reads
a shared namespace such as `ip`), as a `Symbol` or `String`; `eltype` is the
numeric type every element must share. The record is immutable; its fields
are read as `lattice.line`, `lattice.reference`, `lattice.knob_roots`,
`lattice.name` and `eltype(lattice)`.

Two tripwires run at construction, so a convention becomes a check (D7):

- **Knob roots.** The knob registry is process-global and its namespaces are
  names, not modules (`docs/knob_control.md`, section 2), so two lattice
  modules declaring one path would share a knob silently. Every knob the
  line's expressions depend on, transitively and through placement overrides,
  must sit under one of the declared roots; a dependency outside them, or any
  dependency when no root is declared, is refused by name with the element's
  provenance path, the parameter, the knob path and the declared roots.
- **Numeric type.** An element built by a kind's typed form (`Spec{T}` or
  `numeric_type=T`) must store exactly `eltype`; an element built by an
  untyped friendly constructor is accepted when the promotion of its stored
  numeric parameters over `eltype` is `eltype` itself, and refused when a
  parameter is wider (a `Float64` literal in a `Float32` lattice: build it
  with the typed form or the `@elements Float32` header). A kind storing no
  numeric value (a marker, a line with nothing of its own) passes. The rule
  is the compile rule of `numeric_type(spec)` read against the lattice's
  type, and a nested line kept whole is checked with its own parameters and
  its members.

Two lattices are `==` when their names, numeric types, roots, references and
lines agree structurally: the same placements in order, each with the same
spec kind and parameters (knob expressions compared as trees), the same
provenance path, tags and overrides. Including a declarative lattice module
twice therefore builds an equal lattice (design D8), which the suite pins on
the shipped example.

A `Lattice` is accepted wherever a task or an analysis takes a line:
`TrackingTask(lattice; ...)` and `analyze(analysis, lattice)` see the
placements the bare line gives (D15; `StrongStrongTask` and `Machine` are
stage 3). `line_entries`, `s_positions`, `find_entries` and `knob_report`
forward to the line.

Refused by name: a `line` that is not an `ElementSpec{:line}` (a bare spec, a
tuple or a vector: wrap it in `BeamLine(name, ...)`); an `eltype` that is not
a `Number` type; an empty or malformed `knob_root`.
"""
struct Lattice
    name::String
    line::ElementSpec{:line}
    reference::Union{Nothing,ReferenceParticle}
    knob_roots::Tuple{Vararg{Symbol}}
    eltype::DataType
end

function Lattice(name::AbstractString; line, reference::Union{Nothing,ReferenceParticle}=nothing,
                 knob_root=nothing, eltype::Type=Float64)
    if !(line isa ElementSpec{:line})
        what = line isa ElementSpec ? "a bare ElementSpec{$(repr(kind(line)))}" :
               line isa Tuple ? "a Tuple of $(length(line)) element(s)" :
               line isa AbstractVector ? "a Vector of $(length(line)) element(s)" :
               "a value of type $(typeof(line))"
        throw(ArgumentError(
            "Lattice($(repr(String(name)))): `line` must be an ElementSpec{:line} built by " *
            "BeamLine; got $(what). Wrap the elements in a line first: " *
            "BeamLine($(repr(String(name))), element1, element2, ...)"))
    end
    (eltype isa DataType && eltype <: Number) || throw(ArgumentError(
        "Lattice($(repr(String(name)))): `eltype` must be a Number type such as Float64 or " *
        "Float32, the numeric type every element of the lattice must share; got " *
        "$(repr(eltype))"))
    roots = _lattice_knob_roots(knob_root)
    _lattice_check_eltype(line, eltype)
    _lattice_check_knob_roots(line, roots)
    return Lattice(String(name), line, reference, roots, eltype)
end

"""
    _lattice_knob_roots(knob_root) -> Tuple{Vararg{Symbol}}

`nothing` gives `()`; a `Symbol` or `String` gives one root; a tuple or vector
of them gives several. An empty string, a name with leading or trailing dots,
or a non-name value is refused by name.
"""
function _lattice_knob_roots(knob_root)
    knob_root === nothing && return ()
    if knob_root isa Union{Symbol,AbstractString}
        s = String(knob_root)
        isempty(s) && throw(ArgumentError(
            "Lattice: `knob_root` is empty; name the knob namespace the line's expressions " *
            "live under (knob_root=:ring, or a tuple such as knob_root=(:ring, :ip)), or " *
            "leave it `nothing` for a line that reads no knob"))
        (startswith(s, ".") || endswith(s, ".") || occursin("..", s)) && throw(ArgumentError(
            "Lattice: `knob_root` $(repr(s)) is malformed: a knob namespace is a dotted name " *
            "with no leading, trailing or doubled dots (ring, HSR.arc)"))
        all(c -> c == '.' || c == '_' || c == '!' || isletter(c) || isdigit(c), s) || throw(ArgumentError(
            "Lattice: `knob_root` $(repr(s)) is not a knob name: a knob namespace is a dotted " *
            "name of identifiers (ring, HSR.arc), as `@knob` would declare it"))
        return (Symbol(s),)
    end
    if knob_root isa Union{Tuple,AbstractVector}
        isempty(knob_root) && throw(ArgumentError(
            "Lattice: `knob_root` is an empty $(knob_root isa Tuple ? "tuple" : "vector"); " *
            "name at least one knob namespace, or pass `nothing` for a line that reads no knob"))
        roots = Symbol[]
        for r in knob_root
            r isa Union{Symbol,AbstractString} || throw(ArgumentError(
                "Lattice: every entry of `knob_root` must be a Symbol or a String naming a " *
                "knob namespace; got $(repr(r)) of type $(typeof(r)) in $(repr(knob_root))"))
            push!(roots, only(_lattice_knob_roots(r)))
        end
        return Tuple(roots)
    end
    throw(ArgumentError(
        "Lattice: `knob_root` must be `nothing`, a Symbol, a String, or a tuple or vector " *
        "of those (knob_root=:ring, knob_root=(:ring, :ip)); got $(repr(knob_root)) of type " *
        "$(typeof(knob_root))"))
end

"""
    _lattice_check_knob_roots(line::ElementSpec{:line}, roots) -> nothing

The D7 tripwire. Walks every knob binding site of the line
(`_knob_binding_sites!`, the wiring view's walker: the line's own parameters,
every placement through its MERGED parameters, nested lines kept whole) and
every knob each site's expression depends on (`_site_knobs`, then
`knob_dependencies(...; transitive=true)` through dependent knobs), and
requires each path to lie under one of `roots` (`_knob_under_prefix`). Refuses
by name: with no roots declared, the first dependency found names the remedy
(`knob_root=`); otherwise the site's provenance path, parameter, expression
text, the offending knob path and the declared roots.
"""
function _lattice_check_knob_roots(line::ElementSpec{:line}, roots::Tuple{Vararg{Symbol}})
    sites = NamedTuple{(:site, :param, :expr),Tuple{String,String,Any}}[]
    _knob_binding_sites!(sites, line, Ref(0))
    prefixes = map(string, roots)
    for s in sites
        # Every knob the site reads directly, then, for each one the registry
        # knows, every knob it depends on through its own expression. A path
        # not yet declared has no expression to follow; its own path is still
        # checked, so a typo outside the roots is refused before it is declared.
        for d in _site_knobs(s.expr)
            deps = _lattice_knob_declared(d) ? knob_dependencies(d; transitive=true) : Symbol[]
            for p in (d, deps...)
                any(r -> _knob_under_prefix(p, r), prefixes) && continue
                via = p === d ? "" : " (a dependency of knob $(d))"
                isempty(roots) && throw(ArgumentError(
                    "Lattice: the line reads knob $(p)$(via) at $(s.site) :: $(s.param) = " *
                    "$(string(s.expr)), but the lattice declares no knob root. Name the knob " *
                    "namespace(s) the line's expressions live under: knob_root=:" *
                    "$(first(split(string(p), '.'))) (one root, or a tuple of roots such " *
                    "as knob_root=(:ring, :ip))"))
                throw(ArgumentError(
                    "Lattice: knob $(p)$(via), read at $(s.site) :: $(s.param) = " *
                    "$(string(s.expr)), lies outside the declared knob root(s) " *
                    "$(join(prefixes, ", ")): every knob the line depends on, transitively " *
                    "and through placement overrides, must sit under a declared root. Add " *
                    "its namespace to knob_root, or move the knob under a declared root."))
            end
        end
    end
    return nothing
end

# Whether the registry knows `path`: `knob_dependencies(path; transitive=true)`
# refuses an unknown knob by name, and the tripwire follows the dependents of
# the knobs that exist only.
_lattice_knob_declared(path::Symbol) = lock(() -> haskey(_KNOB_TABLE, path), _KNOB_LOCK)

"""
    _lattice_check_eltype(line::ElementSpec{:line}, T::Type) -> nothing

The numeric-type tripwire of the docstring: the line's own parameters, then
every placement's merged parameters (`_merged_params`), nested lines kept
whole descended into. A stored `numeric_type` must be `T` exactly; otherwise
`numeric_type(spec_like, T) === T` must hold (the promotion of the stored
numeric parameters over the lattice's type is the lattice's type), which also
admits a kind storing no numeric value. Refused by name with the provenance
path, the kind, the offending type and the remedy.
"""
function _lattice_check_eltype(line::ElementSpec{:line}, ::Type{T}) where {T}
    _lattice_check_params_eltype(_line_site(line), :line, getfield(line, :params), T)
    for entry in line_entries(line)
        _lattice_check_entry_eltype(entry, T)
    end
    return nothing
end

# A placement through its MERGED parameters (an override is a stored value
# too); a nested line kept whole on its own merged parameters, then its
# members at their own paths. A placement whose spec is not an element spec
# (nothing the compile rule types) is skipped, as the knob walker skips it.
function _lattice_check_entry_eltype(entry::LineEntry, ::Type{T}) where {T}
    spec = getfield(entry, :spec)
    spec isa AbstractElementSpec || return nothing
    k = spec isa ElementSpec ? kind(spec) : nameof(typeof(spec))
    _lattice_check_params_eltype(entry_path(entry), k, _merged_params(entry), T)
    if spec isa ElementSpec{:line}
        for member in line_entries(spec)
            _lattice_check_entry_eltype(member, T)
        end
    end
    return nothing
end

"""
    _lattice_params_numeric_type(params, T) -> Type

The compile rule of `numeric_type(spec, T)` read on a parameter dictionary
(`numeric_type` takes a spec; a placement's merged parameters are a `Dict`):
the fold of `_promote_param_type` over the stored values from the floor `T`,
so non-numeric values and knob expressions are ignored and a kind storing no
numeric value reports `T` itself. Does not read a stored `numeric_type`; the
caller compares that one for identity.
"""
_lattice_params_numeric_type(params::AbstractDict, ::Type{T}) where {T} =
    foldl(_promote_param_type, values(params); init=T)

function _lattice_check_params_eltype(site::AbstractString, k::Symbol, params::AbstractDict,
                                      ::Type{T}) where {T}
    stored = get(params, :numeric_type, nothing)
    if stored !== nothing
        stored === T && return nothing
        throw(ArgumentError(
            "Lattice: $(site) ($(k)) stores numeric_type = $(stored), but the lattice's " *
            "numeric type is $(T), and every element of a lattice shares its eltype. Build " *
            "the element with $(_lattice_typed_form(k, T)), or declare the lattice with " *
            "eltype=$(stored)."))
    end
    P = _lattice_params_numeric_type(params, T)
    P === T && return nothing
    throw(ArgumentError(
        "Lattice: $(site) ($(k)) stores a numeric parameter wider than the lattice's " *
        "numeric type $(T): the promotion of its stored parameters over $(T) is $(P) (an " *
        "untyped friendly constructor stores its literals as given, so a Float64 literal " *
        "lands in a Float32 lattice as Float64). Build the element with " *
        "$(_lattice_typed_form(k, T)), or declare the lattice with eltype=$(P)."))
end

# The remedy's spelling: the kind's typed form through its registered friendly
# constructor (`QuadrupoleSpec{Float32}(...)`), the `@elements T` header for a
# block of them, or, for a line's own parameters, values of the type itself.
function _lattice_typed_form(k::Symbol, ::Type{T}) where {T}
    k === :line && return "its own parameters as $(T) values (x_offset = $(T)(1.0e-3), ...)"
    meta = _element_meta_or_nothing(k)
    ctor = meta === nothing ? nothing : meta.friendly_constructor
    ctor === nothing && return "the typed form (numeric_type=$(T)) or inside an `@elements $(T)` header"
    return "the typed form $(nameof(ctor)){$(T)}(...) or inside an `@elements $(T)` header"
end

# Structural equality of two lattices. Specs compare by kind and parameters
# (`params` dictionaries key by key through this walker, so nested specs,
# `LineEntry` vectors, tuples, arrays, rule objects and knob expressions
# compare by content; numbers with `isequal`, so NaN pins hold), placements by
# spec, path, tags and overrides. Defined on `Lattice` ONLY: `ElementSpec` and
# `LineEntry` keep their identity `==`, which `find_entries`, `unique` and the
# family query `e.spec === qf` rely on.
Base.:(==)(a::Lattice, b::Lattice) =
    getfield(a, :name) == getfield(b, :name) &&
    getfield(a, :eltype) === getfield(b, :eltype) &&
    getfield(a, :knob_roots) == getfield(b, :knob_roots) &&
    getfield(a, :reference) == getfield(b, :reference) &&
    _lattice_structurally_equal(getfield(a, :line), getfield(b, :line))
# Consistent with `==`: the name, the numeric type, the roots, the reference,
# then the placement count and every placement's spec kind and provenance
# path, all of which equal lattices share; parameter values stay out of the
# hash so NaN pins and `isequal` numbers never split a pair `==` joins.
function Base.hash(a::Lattice, h::UInt)
    h = hash(getfield(a, :name), h)
    h = hash(getfield(a, :eltype), h)
    h = hash(getfield(a, :knob_roots), h)
    ref = getfield(a, :reference)
    h = ref === nothing ? hash(nothing, h) : hash((ref.charge, ref.mc2, ref.E0), h)
    entries = line_entries(getfield(a, :line))
    h = hash(length(entries), h)
    for entry in entries
        spec = getfield(entry, :spec)
        h = hash(spec isa ElementSpec ? kind(spec) : nameof(typeof(spec)), h)
        h = hash(getfield(entry, :path), h)
    end
    return h
end
function _lattice_structurally_equal(a, b)
    if a isa ElementSpec
        b isa ElementSpec || return false
        kind(a) === kind(b) || return false
        return _lattice_structurally_equal(getfield(a, :params), getfield(b, :params))
    elseif a isa LineEntry
        b isa LineEntry || return false
        return _lattice_structurally_equal(getfield(a, :spec), getfield(b, :spec)) &&
               getfield(a, :path) == getfield(b, :path) &&
               getfield(a, :tags) == getfield(b, :tags) &&
               _lattice_structurally_equal(getfield(a, :overrides), getfield(b, :overrides))
    elseif a isa AbstractDict
        b isa AbstractDict || return false
        length(a) == length(b) || return false
        for (k, v) in a
            haskey(b, k) || return false
            _lattice_structurally_equal(v, b[k]) || return false
        end
        return true
    elseif a isa Tuple
        b isa Tuple || return false
        length(a) == length(b) || return false
        return all(i -> _lattice_structurally_equal(a[i], b[i]), eachindex(a))
    elseif a isa AbstractArray
        b isa AbstractArray || return false
        size(a) == size(b) || return false
        return all(i -> _lattice_structurally_equal(a[i], b[i]), eachindex(a))
    elseif a isa Number
        return b isa Number && isequal(a, b)
    elseif a isa AbstractKnobExpression
        return b isa AbstractKnobExpression && a == b
    elseif a isa Type || a isa Function
        return a === b
    elseif a isa Union{Symbol,AbstractString,Nothing,AbstractSet}
        return a == b
    end
    # Any other struct (a tracking method, a rule object): same type, every
    # field structurally equal.
    typeof(a) === typeof(b) || return false
    for f in fieldnames(typeof(a))
        _lattice_structurally_equal(getfield(a, f), getfield(b, f)) || return false
    end
    return true
end

Base.eltype(lattice::Lattice) = getfield(lattice, :eltype)
line_entries(lattice::Lattice) = line_entries(getfield(lattice, :line))
s_positions(lattice::Lattice) = s_positions(getfield(lattice, :line))
find_entries(lattice::Lattice, sel) = find_entries(getfield(lattice, :line), sel)
knob_report(lattice::Lattice; kwargs...) = knob_report(getfield(lattice, :line); kwargs...)

function Base.show(io::IO, lattice::Lattice)
    # One line: Lattice("DBA_RING": 10 placements, 5.2 m, Float64, reference ..., knob roots (ring,))
    line = getfield(lattice, :line)
    n = length(line_entries(line))
    ref = getfield(lattice, :reference)
    roots = getfield(lattice, :knob_roots)
    print(io, "Lattice(", repr(getfield(lattice, :name)), ": ", n, " placement",
          n == 1 ? "" : "s", ", ", total_length(line), " m, ", getfield(lattice, :eltype), ", ")
    ref === nothing ? print(io, "no reference") : print(io, "reference ", ref)
    if isempty(roots)
        print(io, ", no knob roots)")
    else
        print(io, ", knob roots (", join(string.(roots), ", "), length(roots) == 1 ? ",))" : "))")
    end
end
