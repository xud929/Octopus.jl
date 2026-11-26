export ReferenceParticle, Lattice, reference_energy

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
    ReferenceParticle(; charge, mc2, E0)        # the total energy in eV
    ReferenceParticle(; charge, mc2, p0c)       # or the momentum times c in eV
    ReferenceParticle(; charge, mc2, gamma0)    # or the Lorentz factor
    ReferenceParticle(; charge, mc2, brho)      # or the magnetic rigidity B rho in T m
    ReferenceParticle(:proton; E0 = 275e9)      # a species preset: :proton, :electron, :positron

The reference particle of a lattice (design D12; the richer, immutable record
of R4, `docs/design/machine_description_followups.md`, 2026-11-26): the
species as the charge in units of e and the rest energy `mc2` in eV, both
required numbers (a species preset supplies them from the named constants of
`src/constants/Constants.jl`, `PMASS_EV` and `EMASS_EV`; an ion goes through
the explicit form), and the energy as exactly ONE of `E0` (the total energy in
eV), `p0c` (the momentum times c in eV), `gamma0` (the Lorentz factor) or
`brho` (the magnetic rigidity in T m), a number or a knob expression (design
D10). Nothing is defaulted: a defaulted physics number is a silent wrong value.

Derived ONCE, in this constructor, and stored as fields of the immutable
record (MAD-X's `BEAM` keeps the same quantities on a mutable global and
recomputes them at every update; an immutable record with one constructor
cannot go stale): `E0`, `p0c`, `gamma0`, `beta0`, `brho` and `r0`, with

    gamma0 = E0 / mc2                        beta0 = sqrt((gamma0 - 1) (gamma0 + 1)) / gamma0
    p0c    = sqrt((E0 - mc2) (E0 + mc2))     brho  = p0c / (c |charge|)        [T m, p0c in eV]
    r0     = RE * ME0 / mc2                  [m, the classical radius of a unit charge of rest energy mc2]

the factored forms keeping their digits near `gamma0 = 1` (`reference_beta`,
`src/track/longitudinal.jl`; `_reference_pair_fold` is the one source of the
pair for the cavities and this record), and the other spellings inverted
exactly (`E0 = sqrt(p0c^2 + mc2^2)`, `E0 = gamma0 mc2`, `p0c = brho c |charge|`).
The typed value is stored in its own field as given and the others are derived
from it. `beta0` is not an input: at 10 GeV an electron's `beta0` is
`1 - 1.3e-9`, which nobody types. With a knob expression as the energy the
derived quantities are expression trees over it, built from the whitelisted
operations, that resolve at compile like every other parameter (a ramp is a
knob on the reference, R7); `charge` and `mc2` stay numbers, so `r0` is always
a number. The accessors `reference_beta(ref)`, `reference_gamma(ref)` and
`reference_beta_gamma(ref)` read the fields.

The key typed at construction is kept (`energy_key`: `:E0`, `:p0c`, `:gamma0`
or `:brho`): it is the stored parameter the snapshot writes (D13), so a
reference given as `p0c` round-trips to the bit, and two references compare
`==` structurally -- the same charge, mass, typed key and energy value (knob
expressions as trees); two physically equal references typed through
different keys are not `==` (compare `ref1.E0 == ref2.E0` for that).

Refused by name at construction: a non-finite or zero `charge`, or one that is
not a number; a non-finite or non-positive `mc2`, or one that is not a
number; two or more energy spellings, or none; a numeric `E0` not above `mc2`
(a reference at rest has no direction and `beta0 = 0` divides every cavity),
a `gamma0` not above 1, a non-positive or non-finite `p0c` or `brho`, or an
energy that is neither a number nor a knob expression; a species outside the
presets; `charge` or `mc2` given beside a species. A knob-given energy is
checked only when it resolves (the bare `DomainError` of the derived tree's
`sqrt`, the open row of `todo.md`).

Consumers: [`Lattice`](@ref) carries it (a knob-given energy must read knobs
under the lattice's declared roots, like every expression of the line);
`Beam(N, policy; reference = ref)` takes `charge`, `mc2`, `E0` and `r0` from
it (resolving a knob-given energy at construction); the cavities take `beta0`
and `gamma0` (`thin_rf_cavity(f; voltage = V, reference = ref)`).
"""
struct ReferenceParticle{E}
    charge::Float64
    mc2::Float64
    # The typed energy key as its index into `_REFERENCE_ENERGY_KEYS` (a
    # `Symbol` field would cost the record its isbits property, which the
    # numeric form keeps); read as the property `energy_key`.
    energy_index::UInt8
    E0::E
    p0c::E
    gamma0::E
    beta0::E
    brho::E
    r0::Float64
end

"""The four spellings of the energy, the key typed at construction being the stored parameter."""
const _REFERENCE_ENERGY_KEYS = (:E0, :p0c, :gamma0, :brho)
_reference_energy_index(key::Symbol) = UInt8(findfirst(==(key), _REFERENCE_ENERGY_KEYS))

# `ref.energy_key` is the typed key as a `Symbol`; every other property is a field.
Base.getproperty(ref::ReferenceParticle, s::Symbol) =
    s === :energy_key ? _REFERENCE_ENERGY_KEYS[getfield(ref, :energy_index)] : getfield(ref, s)
Base.propertynames(::ReferenceParticle) =
    (:charge, :mc2, :energy_key, :E0, :p0c, :gamma0, :beta0, :brho, :r0)

# The species presets: the charge in units of e and the rest energy, BY NAME
# from the shared constants, the energy still required (MAD-X's PARTICLE=PROTON
# convenience without its defaults). An ion is spelled through the explicit
# form. The suite pins every preset number as `===` one of the named constants.
const _REFERENCE_SPECIES = (
    proton=(charge=1.0, mc2=PMASS_EV),
    electron=(charge=-1.0, mc2=EMASS_EV),
    positron=(charge=1.0, mc2=EMASS_EV),
)

function ReferenceParticle(; charge, mc2, E0=nothing, p0c=nothing, gamma0=nothing, brho=nothing)
    # The refusals of the docstring, by name, before anything is built. An
    # OUTER constructor: the default inner one stays available to tests that
    # need a raw instance.
    (charge isa Real && isfinite(charge) && !iszero(charge)) || throw(ArgumentError(
        "ReferenceParticle: `charge` must be a finite, nonzero number of elementary " *
        "charges (1 for a proton, -1 for an electron); got $(repr(charge))"))
    (mc2 isa Real && isfinite(mc2) && mc2 > 0) || throw(ArgumentError(
        "ReferenceParticle: `mc2` must be a finite, positive rest energy in eV " *
        "(PMASS_EV for a proton, EMASS_EV for an electron); got $(repr(mc2))"))
    given = [(k, v) for (k, v) in zip(_REFERENCE_ENERGY_KEYS, (E0, p0c, gamma0, brho)) if v !== nothing]
    length(given) == 1 || throw(ArgumentError(
        "ReferenceParticle: give exactly one of `E0` (the total energy in eV), `p0c` (the " *
        "momentum times c in eV), `gamma0` (the Lorentz factor) and `brho` (the magnetic " *
        "rigidity in T m), not " *
        (isempty(given) ? "none; neither was given" :
         "$(length(given)); got " * join(("$(k) = $(repr(v))" for (k, v) in given), " and "))))
    key, value = only(given)
    q, m = Float64(charge), Float64(mc2)
    if value isa Real
        x = Float64(value)
        isfinite(x) || throw(ArgumentError(
            "ReferenceParticle: `$(key)` must be finite; got $(key) = $(repr(value))"))
        if key === :E0
            x > m || throw(ArgumentError(
                "ReferenceParticle: `E0` is the TOTAL energy in eV and must exceed " *
                "`mc2` = $(m) eV (a reference at rest has no direction and beta0 = 0 " *
                "divides every cavity); got E0 = $(repr(value))"))
        elseif key === :gamma0
            x > 1 || throw(ArgumentError(
                "ReferenceParticle: `gamma0` is the Lorentz factor and must exceed 1 (a " *
                "reference at rest has no direction and beta0 = 0 divides every cavity); " *
                "got gamma0 = $(repr(value))"))
        else
            x > 0 || throw(ArgumentError(
                "ReferenceParticle: `$(key)` must be a positive " *
                (key === :p0c ? "momentum times c in eV" : "magnetic rigidity in T m") *
                "; got $(key) = $(repr(value))"))
        end
        d = _reference_derive(q, m, key, x)
        return ReferenceParticle{Float64}(q, m, _reference_energy_index(key), d.E0, d.p0c, d.gamma0,
                                          d.beta0, d.brho, _reference_r0(m))
    end
    value isa AbstractKnobExpression || throw(ArgumentError(
        "ReferenceParticle: `$(key)` must be a number or a knob expression (@knob_expr(...)); " *
        "got $(repr(value))"))
    d = _reference_derive(q, m, key, value)
    return ReferenceParticle{AbstractKnobExpression}(q, m, _reference_energy_index(key), d.E0, d.p0c,
                                                     d.gamma0, d.beta0, d.brho, _reference_r0(m))
end

function ReferenceParticle(species::Symbol; kwargs...)
    haskey(_REFERENCE_SPECIES, species) || throw(ArgumentError(
        "ReferenceParticle: unknown species $(repr(species)); the presets are " *
        join((":$(k)" for k in keys(_REFERENCE_SPECIES)), ", ") *
        ". Spell another species through the explicit form ReferenceParticle(; charge, mc2, " *
        "E0 | p0c | gamma0 | brho)"))
    preset = _REFERENCE_SPECIES[species]
    for k in (:charge, :mc2)
        haskey(kwargs, k) && throw(ArgumentError(
            "ReferenceParticle(:$(species)): `$(k)` is fixed by the species preset " *
            "($(k) = $(preset[k])); drop it, or use the explicit form " *
            "ReferenceParticle(; charge, mc2, ...)"))
    end
    return ReferenceParticle(; charge=preset.charge, mc2=preset.mc2, kwargs...)
end

"""The classical radius of a unit charge of rest energy `mc2`, `RE * ME0 / mc2` in metres (R3)."""
_reference_r0(mc2::Float64) = RE * ME0 / mc2

"""
    _reference_derive(charge, mc2, key, value) -> (; E0, p0c, gamma0, beta0, brho)

The derived quantities of a reference from the typed energy `value` under
`key`, through `_knob_arith` and `_reference_pair_fold`, so a number gives
numbers by the formulas of `reference_gamma` and `reference_beta` (bitwise
what the accessors computed from `E0` and `mc2` before the fields existed)
and a knob expression gives expression trees over the whitelisted operations
(design D10). The typed value is returned in its own slot unchanged.
"""
function _reference_derive(charge::Float64, mc2::Float64, key::Symbol, value)
    c_q = CLIGHT * abs(charge)
    E0 = key === :E0 ? value :
         key === :p0c ? _knob_arith(:sqrt, _knob_arith(:+, _knob_arith(:*, value, value), mc2 * mc2)) :
         key === :gamma0 ? _knob_arith(:*, value, mc2) :
         begin
             p = _knob_arith(:*, value, c_q)
             _knob_arith(:sqrt, _knob_arith(:+, _knob_arith(:*, p, p), mc2 * mc2))
         end
    p0c = key === :p0c ? value :
          key === :brho ? _knob_arith(:*, value, c_q) :
          _knob_arith(:sqrt, _knob_arith(:*, _knob_arith(:-, E0, mc2), _knob_arith(:+, E0, mc2)))
    beta0, g = _reference_pair_fold(E0, mc2)
    gamma0 = key === :gamma0 ? value : g
    if key === :gamma0
        # The typed Lorentz factor is the stored one; beta0 follows from it by
        # the same factored form the pair fold uses.
        beta0 = _knob_arith(:/, _knob_arith(:sqrt, _knob_arith(:*, _knob_arith(:-, gamma0, 1),
                                                                 _knob_arith(:+, gamma0, 1))), gamma0)
    end
    brho = key === :brho ? value : _knob_arith(:/, p0c, c_q)
    return (; E0, p0c, gamma0, beta0, brho)
end

"""The energy value as typed at construction: `getfield(ref, ref.energy_key)`, a number or a knob expression."""
reference_energy(ref::ReferenceParticle) = getfield(ref, ref.energy_key)

reference_beta_gamma(ref::ReferenceParticle) = (ref.beta0, ref.gamma0)
reference_beta(ref::ReferenceParticle) = ref.beta0
reference_gamma(ref::ReferenceParticle) = ref.gamma0

# Structural equality over the stored inputs: charge, mass, the typed key and
# its value (a knob expression as a tree); the derived fields follow from them.
Base.:(==)(a::ReferenceParticle, b::ReferenceParticle) =
    a.charge == b.charge && a.mc2 == b.mc2 && a.energy_key === b.energy_key &&
    reference_energy(a) == reference_energy(b)
Base.hash(a::ReferenceParticle, h::UInt) =
    hash((:reference_particle, a.charge, a.mc2, a.energy_key, reference_energy(a)), h)

function Base.show(io::IO, ref::ReferenceParticle)
    # One line, with units, the energy under its typed key:
    # ReferenceParticle(charge = 1.0, mc2 = 9.38e8 eV, E0 = 3.0e9 eV)
    key = ref.energy_key
    unit = key === :gamma0 ? "" : key === :brho ? " T m" : " eV"
    print(io, "ReferenceParticle(charge = ", ref.charge, ", mc2 = ", ref.mc2, " eV, ", key, " = ",
          reference_energy(ref), unit, ")")
end

"""
    _lattice_check_reference_knob_roots(reference, roots) -> nothing

The D7 tripwire for the reference particle (R4, 2026-11-26): a knob-given
energy must read knobs under one of the lattice's declared roots, transitively,
exactly as the line's expressions must (`_lattice_check_knob_roots`); refused
by name with the key, the expression text, the knob path and the roots. A
numeric reference, or none, has nothing to check.
"""
function _lattice_check_reference_knob_roots(reference, roots::Tuple{Vararg{Symbol}})
    reference === nothing && return nothing
    value = reference_energy(reference)
    value isa AbstractKnobExpression || return nothing
    prefixes = map(string, roots)
    key = reference.energy_key
    for d in _site_knobs(value)
        deps = _lattice_knob_declared(d) ? knob_dependencies(d; transitive=true) : Symbol[]
        for p in (d, deps...)
            any(r -> _knob_under_prefix(p, r), prefixes) && continue
            via = p === d ? "" : " (a dependency of knob $(d))"
            isempty(roots) && throw(ArgumentError(
                "Lattice: the reference particle reads knob $(p)$(via) in its $(key) = " *
                "$(string(value)), but the lattice declares no knob root. Name the knob " *
                "namespace(s) the lattice's expressions live under: knob_root=:" *
                "$(first(split(string(p), '.')))"))
            throw(ArgumentError(
                "Lattice: knob $(p)$(via), read by the reference particle's $(key) = " *
                "$(string(value)), lies outside the declared knob root(s) " *
                "$(join(prefixes, ", ")): every knob the lattice depends on must sit under " *
                "a declared root. Add its namespace to knob_root, or move the knob under a " *
                "declared root."))
        end
    end
    return nothing
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
  provenance path, the parameter, the knob path and the declared roots. A
  reference particle whose energy is a knob expression (R4, 2026-11-26) is
  checked by the same rule, with the energy key in place of the path.
- **Numeric type.** The compile's own answer, re-read against `eltype`. An
  element built by a kind's typed form (`Spec{T}` or `numeric_type=T`) must
  store exactly `eltype`; an element built by an untyped friendly constructor
  compiles in the promotion of its stored numeric parameters over a `Float64`
  FLOOR (`numeric_type(spec)`), never narrower, and must compile in `eltype`.
  So a `Float64` lattice accepts every untyped element whose values are
  `Float64` or narrower (the marker, storing no numeric value, included) and
  refuses a wider literal (a `BigFloat`, a dual); a `Float32` lattice refuses
  EVERY untyped element, the marker included, because the compile types it
  `Float64` and a task would then refuse the `Float32` beam by name. The
  remedy is the typed form: `numeric_type = Float32` on the kind's
  constructor, or the `@elements Float32` header, which types every element
  it emits. A nested line kept whole is checked on its merged parameters by
  the wrap's own rule (`_wrap_numeric_type`: built in its members' type while
  the line's own parameters promote to the floor, widened by a wider offset;
  `BeamLine(...; numeric_type = T)` declares it), then its members; the
  top-level line's own parameters are checked when it carries state of its
  own, since a dissolving line never compiles as an element.

The two tripwires run at construction only: a knob redefined or declared
afterwards is not re-checked (a derived lattice, stage 5, runs them again).

Two lattices are `==` when their names, numeric types, roots, references and
lines agree structurally: the same placements in order, each with the same
spec kind and parameters (knob expressions compared as trees), the same
provenance path, tags and overrides. Equality is structural over the stored
values, so a function-valued parameter (a `TuneFunction`) compares by identity
and an automatically assigned stream id (`rng_id = 0`, a fresh stream per
build) differs per build; the include-twice equality of design D8 therefore
holds for modules whose elements carry neither, as the shipped DBA module
does, and the suite pins it on that example.

A `Lattice` is accepted wherever a task or an analysis takes a line,
`StrongStrongTask(lattice1, lattice2; ...)` included: `TrackingTask(lattice;
...)`, `StrongStrongTask` and `analyze(analysis, lattice)` see the placements
the bare line gives (D15, one site: `_element_tuple`); `Machine` is stage 3.
`line_entries`, `s_positions`, `find_entries` and `knob_report` forward to
the line.

Refused by name: a `line` that is not an `ElementSpec{:line}` (a bare spec, a
tuple or a vector: wrap it in `BeamLine(name, ...)`); an `eltype` that is not
a concrete `Number` type (`Number` and `Real` are abstract, and every element
must share ONE type); an empty or malformed `knob_root` (a segment that is not
an identifier, a reserved constant name such as `pi`).
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
    (eltype isa Type && eltype <: Number) || throw(ArgumentError(
        "Lattice($(repr(String(name)))): `eltype` must be a Number type such as Float64 or " *
        "Float32, the numeric type every element of the lattice must share; got " *
        "$(repr(eltype))"))
    # An abstract type would void the one-type rule: `promote_type(Number, X)` is
    # `Number` for every `X`, so a `Number` lattice accepted Float32, Float64 and
    # BigFloat elements side by side.
    isconcretetype(eltype) || throw(ArgumentError(
        "Lattice($(repr(String(name)))): `eltype` must be a concrete Number type such as " *
        "Float64 or Float32; got $(repr(eltype)) (" *
        (isabstracttype(eltype) ? "abstract" : "not a concrete type") *
        ": every element must share ONE type)"))
    roots = _lattice_knob_roots(knob_root)
    _lattice_check_eltype(line, eltype)
    _lattice_check_knob_roots(line, roots)
    _lattice_check_reference_knob_roots(reference, roots)
    return Lattice(String(name), line, reference, roots, eltype)
end

"""
    _lattice_knob_roots(knob_root, who::AbstractString="Lattice") -> Tuple{Vararg{Symbol}}

`nothing` gives `()`; a `Symbol` or `String` gives one root; a tuple or vector
of them gives several. Refused by name: an empty string; a name with leading,
trailing or doubled dots; a segment that is not a Julia identifier
(`Base.isidentifier`; `1abc`); a root that is one of the knob
expression language's reserved constant names (`pi`, `π`, `ℯ`, `NaN`, `Inf`,
the keys of `_KNOB_NAMED_CONSTANTS`), which `@knob` itself refuses to declare;
a non-name value; in a tuple or vector, a root declared twice, and a root that
sits under another declared root (`(:ring, "ring.arc")`: every knob under
`ring.arc` is under `ring` already, so only `ring` is declared). Every message
begins `who * ":"`: `Lattice` keeps the default,
`Machine` passes its own name since its shared roots take the same spellings
(stage 3).
"""
function _lattice_knob_roots(knob_root, who::AbstractString="Lattice")
    knob_root === nothing && return ()
    if knob_root isa Union{Symbol,AbstractString}
        s = String(knob_root)
        isempty(s) && throw(ArgumentError(
            "$(who): `knob_root` is empty; name the knob namespace the line's expressions " *
            "live under (knob_root=:ring, or a tuple such as knob_root=(:ring, :ip)), or " *
            "leave it `nothing` for a line that reads no knob"))
        (startswith(s, ".") || endswith(s, ".") || occursin("..", s)) && throw(ArgumentError(
            "$(who): `knob_root` $(repr(s)) is malformed: a knob namespace is a dotted name " *
            "with no leading, trailing or doubled dots (ring, HSR.arc)"))
        all(seg -> Base.isidentifier(seg), split(s, '.')) || throw(ArgumentError(
            "$(who): `knob_root` $(repr(s)) is not a knob name: a knob namespace is a dotted " *
            "name whose every segment is a Julia identifier (ring, HSR.arc), as " *
            "`@knob` declares it"))
        haskey(_KNOB_NAMED_CONSTANTS, Symbol(s)) && throw(ArgumentError(
            "$(who): `knob_root` $(repr(s)) is a reserved name: knob expressions read " *
            "$(s) as the literal constant $(_KNOB_NAMED_CONSTANTS[Symbol(s)]), so `@knob` " *
            "refuses to declare a knob under it; pick a namespaced root such as consts"))
        return (Symbol(s),)
    end
    if knob_root isa Union{Tuple,AbstractVector}
        isempty(knob_root) && throw(ArgumentError(
            "$(who): `knob_root` is an empty $(knob_root isa Tuple ? "tuple" : "vector"); " *
            "name at least one knob namespace, or pass `nothing` for a line that reads no knob"))
        roots = Symbol[]
        for r in knob_root
            r isa Union{Symbol,AbstractString} || throw(ArgumentError(
                "$(who): every entry of `knob_root` must be a Symbol or a String naming a " *
                "knob namespace; got $(repr(r)) of type $(typeof(r)) in $(repr(knob_root))"))
            push!(roots, only(_lattice_knob_roots(r, who)))
        end
        # A root under another declared root is declared twice: every knob
        # under ring.arc is under ring already, so the pair names one namespace
        # two ways (stage 3; the machine-level tripwire refuses the same nesting
        # across lattices and shared roots).
        for i in eachindex(roots), j in i+1:lastindex(roots)
            a, b = roots[i], roots[j]
            a === b && throw(ArgumentError(
                "$(who): `knob_root` declares $(a) twice ($(repr(knob_root))); declare it once"))
            outer, inner = _knob_under_prefix(string(b), string(a)) ? (a, b) :
                           _knob_under_prefix(string(a), string(b)) ? (b, a) : (nothing, nothing)
            outer === nothing || throw(ArgumentError(
                "$(who): `knob_root` $(inner) sits under $(outer), which is declared too " *
                "($(repr(knob_root))); declare only $(outer): a knob under $(inner) is under " *
                "$(outer) already"))
        end
        return Tuple(roots)
    end
    throw(ArgumentError(
        "$(who): `knob_root` must be `nothing`, a Symbol, a String, or a tuple or vector " *
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

The numeric-type tripwire of the docstring: the compile's own answer re-read
against `T`. Every placement is checked through its merged parameters
(`_merged_params`; `compile_runtime(::LineEntry)` merges, then compiles), a
nested line kept whole on its merged parameters and then its members, and the
top-level line's own parameters only when it carries state of its own (a
dissolving line never compiles as an element; `_element_tuple`). Refused by
name with the provenance path, the kind, the type the element compiles in and
the remedy.
"""
function _lattice_check_eltype(line::ElementSpec{:line}, ::Type{T}) where {T}
    _line_has_own_state(line) &&
        _lattice_check_line_eltype(_line_site(line), getfield(line, :params), line, T)
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
    if spec isa ElementSpec{:line}
        _lattice_check_line_eltype(entry_path(entry), _merged_params(entry), spec, T)
        for member in line_entries(spec)
            _lattice_check_entry_eltype(member, T)
        end
        return nothing
    end
    k = spec isa ElementSpec ? kind(spec) : nameof(typeof(spec))
    _lattice_check_params_eltype(entry_path(entry), k, _merged_params(entry), T)
    return nothing
end

"""
    _lattice_params_numeric_type(params) -> Type

The compile rule of `numeric_type(spec)` read on a parameter dictionary
(`numeric_type` takes a spec; a placement's merged parameters are a `Dict`):
the fold of `_promote_param_type` over the stored values from the `Float64`
FLOOR the compile folds from (src/knowledge/Knowledge.jl), so non-numeric
values and knob expressions are ignored, a kind storing no numeric value
reports `Float64`, and a `Float32` or `Int` literal lands on `Float64` exactly
as it compiles. Does not read a stored `numeric_type`; the caller compares
that one for identity.
"""
_lattice_params_numeric_type(params::AbstractDict) =
    foldl(_promote_param_type, values(params); init=Float64)

# An element: a stored `numeric_type` must be `T` itself; otherwise the type
# the compile gives it (`numeric_type(spec)`, the Float64-floor fold over the
# merged parameters) must be `T`. In a Float32 lattice this refuses EVERY
# untyped element, the marker included: the compile types it Float64 and a
# task then refuses the Float32 beam by name (`_check_beam_eltype`,
# src/track/Track.jl); the lattice says so first, at its construction.
function _lattice_check_params_eltype(site::AbstractString, k::Symbol, params::AbstractDict,
                                      ::Type{T}) where {T}
    stored = get(params, :numeric_type, nothing)
    if stored !== nothing
        stored === T || throw(ArgumentError(
            "Lattice: $(site) ($(k)) stores numeric_type = $(stored), but the lattice's " *
            "numeric type is $(T), and every element of a lattice shares its eltype. Build " *
            "the element with $(_lattice_typed_form(k, T)), or declare the lattice with " *
            "eltype=$(stored)."))
        _lattice_check_typed_values(site, k, params, T)
        return nothing
    end
    P = _lattice_params_numeric_type(params)
    P === T && return nothing
    throw(ArgumentError(
        "Lattice: $(site) ($(k)) compiles in $(P), not the lattice's numeric type $(T): an " *
        "untyped element's type is the promotion of its stored numeric parameters over the " *
        "Float64 floor (`numeric_type`), never narrower than Float64, and a task refuses a " *
        "$(T) beam at an element compiled in $(P) by name. " * _lattice_eltype_remedy(k, T, P)))
end

"""
    _lattice_check_typed_values(site, k, params, T)

The R6 half of the typed element's check (2026-11-26, the audit's B-11): a typed
element holds no value wider than its type. The merged view includes placement
overrides, so an in-place override, `with_overrides`, the spec route, the
flexible form and the snapshot reader all refuse here, with the typed form's own
message (`_numeric_type_refusal`) behind the provenance path.
"""
function _lattice_check_typed_values(site::AbstractString, k::Symbol, params::AbstractDict,
                                     ::Type{T}) where {T}
    for key in sort!(collect(keys(params)); by=string)
        key === :numeric_type && continue
        W = _widest_float_type(params[key])
        (W === nothing || _numeric_type_holds(T, W)) || throw(ArgumentError(
            "Lattice: $(site) ($(k)): " * _numeric_type_refusal(T, W, key)))
    end
    return nothing
end

# The remedy of an untyped element or line whose promotion `P` differs from the
# lattice's `T`: the typed form narrows a Float64 (or narrower) value into `T`,
# so it is the remedy exactly when `T` holds `P` (R6); a value wider than
# Float64 has no typed form to narrow into and the remedies are the value in
# Float64 or narrower, or a lattice of its type.
function _lattice_eltype_remedy(k::Symbol, ::Type{T}, ::Type{P}) where {T,P}
    _numeric_type_holds(T, P) && return "Build the $(k === :line ? "line" : "element") with " *
        "$(_lattice_typed_form(k, T)), or declare the lattice with eltype=$(P)."
    return "A typed element never narrows a value wider than Float64 (R6, 2026-11-26), so give " *
        "the value in Float64 or narrower, or declare the lattice with eltype=$(P)."
end

# A line kept whole: its wrap is built in `_wrap_numeric_type(spec, inner)`
# (src/elements/misalignment.jl): the members' common type when the line's
# own promotion is the Float64 floor, otherwise the promotion of that type
# with the line's own (a stored `numeric_type`, or own parameters that widen
# past Float64: a BigFloat or dual offset), and the line's own type alone when
# it holds no element member. The members are each required to be `T` by
# their own checks, so the members' type is `T` here.
function _lattice_check_line_eltype(site::AbstractString, params::AbstractDict,
                                    spec::ElementSpec{:line}, ::Type{T}) where {T}
    stored = get(params, :numeric_type, nothing)
    if stored !== nothing
        stored === T || throw(ArgumentError(
            "Lattice: $(site) (line) stores numeric_type = $(stored), but the lattice's " *
            "numeric type is $(T), and every element of a lattice shares its eltype. Build " *
            "the line with $(_lattice_typed_form(:line, T)), or declare the lattice with " *
            "eltype=$(stored)."))
        _lattice_check_typed_values(site, :line, params, T)
        return nothing
    end
    own = _lattice_params_numeric_type(params)
    wrap = !_lattice_line_has_element_members(spec) ? own :
           own === Float64 ? T : promote_type(T, own)
    wrap === T && return nothing
    throw(ArgumentError(
        "Lattice: $(site) (line) compiles in $(wrap), not the lattice's numeric type $(T): " *
        "a line kept whole is wrapped in its members' type while its own parameters " *
        "promote to the Float64 floor; a wider value (a BigFloat or dual offset) widens " *
        "the wrap (`_wrap_numeric_type`), and a line with no element member has only its " *
        "own type ($(own)). " * _lattice_eltype_remedy(:line, T, wrap)))
end

# Whether a line holds at least one element placement, nested lines descended:
# the wrap then has a members' type to be built in.
function _lattice_line_has_element_members(line::ElementSpec{:line})
    for entry in line_entries(line)
        child = getfield(entry, :spec)
        if child isa ElementSpec{:line}
            _lattice_line_has_element_members(child) && return true
        elseif child isa AbstractElementSpec
            return true
        end
    end
    return false
end

# The remedy's spelling: the keyword route `numeric_type = T`, which every
# kind's friendly constructor routes to its typed form (the `@elements` macro's
# own route) and which holds for a kind whose typed form has more parameters
# than `Spec{T}` (`ThinCrabCavitySpec{N,T}`: `ThinCrabCavitySpec{Float32}(f)`
# binds N and dies), the `@elements T` header for a block of them, and for a
# line the same keyword on `BeamLine`, stored as the line's own type.
function _lattice_typed_form(k::Symbol, ::Type{T}) where {T}
    k === :line && return "BeamLine(...; numeric_type = $(T))"
    meta = _element_meta_or_nothing(k)
    ctor = meta === nothing ? nothing : meta.friendly_constructor
    ctor === nothing && return "its typed form (numeric_type = $(T)), or inside an `@elements $(T)` header"
    return "$(nameof(ctor))(...; numeric_type = $(T)), or inside an `@elements $(T)` header"
end

# Structural equality of two lattices. Specs compare by kind and parameters
# (`params` dictionaries key by key through this walker, so nested specs,
# `LineEntry` vectors, tuples, arrays, rule objects and knob expressions
# compare by content; numbers with `isequal`, so NaN pins hold), placements by
# spec, path, tags and overrides, an in-line observer with an option schema by
# that schema's values (its configuration view, never its run state; the walker's
# observer branch). Defined on `Lattice` ONLY: `ElementSpec` and
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
    elseif a isa AbstractBeamObserver && hasmethod(observer_option_schema, Tuple{typeof(a)})
        # An observer with an option schema compares by its configuration view, the
        # schema's values -- what the snapshot writes for it (D6) -- not by every field:
        # the artifact-view observers keep run state in the object (a `MomentObserver`'s
        # row buffer, record count and artifact handle, a `BPMObserver`'s readings), so a
        # lattice whose observers had run was no longer `==` its pristine twin (the
        # stage-5 neighbour audit, lead C-2). An observer type without a schema (a
        # user's) keeps the field walk below, run state included.
        b isa AbstractBeamObserver && typeof(a) === typeof(b) || return false
        for key in keys(observer_option_schema(a))
            _lattice_structurally_equal(getproperty(a, key), getproperty(b, key)) || return false
        end
        return true
    end
    # Any other value: same type, then a primitive (an `@enum` such as
    # `XYCouplingMode`, which has no fields, so the field walk below found
    # every pair of its values equal) by identity, a struct (a tracking
    # method, a rule object) field by field.
    typeof(a) === typeof(b) || return false
    isprimitivetype(typeof(a)) && return a === b
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
    # A knob-valued length (`DriftSpec(L=@knob_expr(ring.len))`, design D10)
    # evaluates its knob here; a knob declared and not yet assigned is a legal
    # lattice whose display must not throw (stage 2 review, F9).
    length_text = try
        string(total_length(line), " m")
    catch err
        err isa ArgumentError || rethrow()
        string("length pending (", err.msg, ")")
    end
    print(io, "Lattice(", repr(getfield(lattice, :name)), ": ", n, " placement",
          n == 1 ? "" : "s", ", ", length_text, ", ", getfield(lattice, :eltype), ", ")
    ref === nothing ? print(io, "no reference") : print(io, "reference ", ref)
    if isempty(roots)
        print(io, ", no knob roots)")
    else
        print(io, ", knob roots (", join(string.(roots), ", "), length(roots) == 1 ? ",))" : "))")
    end
end
