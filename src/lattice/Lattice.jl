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
    # TODO(unit A): the refusals of the docstring, by name, before anything is
    # built; then `new`-equivalent construction with Float64 fields. Keep this
    # an OUTER constructor so the default inner one stays available to tests
    # that need a raw instance.
    error("TODO unit A: ReferenceParticle keyword constructor")
end

reference_beta_gamma(ref::ReferenceParticle) = reference_beta_gamma(ref.E0, ref.mc2)
reference_beta(ref::ReferenceParticle) = reference_beta(ref.E0, ref.mc2)
reference_gamma(ref::ReferenceParticle) = reference_gamma(ref.E0, ref.mc2)

function Base.show(io::IO, ref::ReferenceParticle)
    # TODO(unit A): one line, e.g. ReferenceParticle(charge = 1.0, mc2 = 9.38e8 eV, E0 = 3.0e9 eV)
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
    # TODO(unit A): refusals of the docstring by name; then
    #   roots = _lattice_knob_roots(knob_root)
    #   _lattice_check_eltype(line, eltype)
    #   _lattice_check_knob_roots(line, roots)
    #   Lattice(String(name), line, reference, roots, eltype)
    error("TODO unit A: Lattice keyword constructor")
end

"""
    _lattice_knob_roots(knob_root) -> Tuple{Vararg{Symbol}}

`nothing` gives `()`; a `Symbol` or `String` gives one root; a tuple or vector
of them gives several. An empty string, a name with leading or trailing dots,
or a non-name value is refused by name.
"""
function _lattice_knob_roots(knob_root)
    error("TODO unit A")
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
    error("TODO unit A")
end

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
    error("TODO unit A")
end

# Structural equality of two lattices. Specs compare by kind and parameters
# (`params` dictionaries key by key through this walker, so nested specs,
# `LineEntry` vectors, tuples, arrays, rule objects and knob expressions
# compare by content; numbers with `isequal`, so NaN pins hold), placements by
# spec, path, tags and overrides. Defined on `Lattice` ONLY: `ElementSpec` and
# `LineEntry` keep their identity `==`, which `find_entries`, `unique` and the
# family query `e.spec === qf` rely on.
Base.:(==)(a::Lattice, b::Lattice) = error("TODO unit A: structural equality")
Base.hash(a::Lattice, h::UInt) = error("TODO unit A: consistent with ==")
function _lattice_structurally_equal(a, b)
    error("TODO unit A")
end

Base.eltype(lattice::Lattice) = getfield(lattice, :eltype)
line_entries(lattice::Lattice) = line_entries(getfield(lattice, :line))
s_positions(lattice::Lattice) = s_positions(getfield(lattice, :line))
find_entries(lattice::Lattice, sel) = find_entries(getfield(lattice, :line), sel)
knob_report(lattice::Lattice; kwargs...) = knob_report(getfield(lattice, :line); kwargs...)

function Base.show(io::IO, lattice::Lattice)
    # TODO(unit A): one line -- Lattice("DBA_RING": 10 placements, 5.2 m, Float64, reference ..., knob roots (ring,))
    print(io, "Lattice(", repr(getfield(lattice, :name)), ")")
end
