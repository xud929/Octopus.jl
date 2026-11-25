export Machine

"""
    Machine(name; lattices, knob_root=nothing)
    Machine(lattice::Lattice)

The facility's namespace of definitions (design note
`docs/design/machine_description.md`, decision D5): its lattices by name, in
declaration order, and the knob roots the lattices share. A machine holds
nothing about how its lattices connect, no closure, and no interaction-point
concept; pairing two lattices is the task's business (D6), and a machine may
hold a linac, a ramping ring and transfer lines beside a collider's two rings.
A task given a bare `Lattice` is a one-lattice machine implicitly, so the
single-ring user never sees this level; `Machine(lattice)` is the explicit
spelling of the same thing and equals `Machine(lattice.name; lattices =
(lattice,))`.

`lattices` is a `Lattice` or a tuple or vector of them, at least one; the
lattice names are the machine's keys and must be unique (a duplicate is
refused by name). `knob_root` names the SHARED knob namespaces, the ones more
than one lattice may read (the half crossing angle both rings' boosts and crab
cavities read: `ip` in `examples/knob_control.jl`), in the spellings
`Lattice` takes: a `Symbol`, a `String`, or a tuple or vector of them.

One tripwire runs at construction, the machine-level half of D7. The knob
registry is process-global and its namespaces are names, not modules
(`docs/knob_control.md`, section 2), so two lattices declaring one root read
one set of knobs whether or not anyone meant them to. A root declared by two
or more lattices must therefore be among the machine's shared roots, and no
two distinct roots of the machine (every lattice's roots and the shared ones
together) may overlap, one being a dotted prefix of the other (`ring` and
`ring.arc`: every `ring.arc.*` knob would sit under both). Each refusal names
the root, the lattices declaring it and the remedy (declare the root shared on
the machine when the sharing is intended, or give each lattice a root of its
own). Nothing else is checked here: each lattice checked its own knob
dependencies and numeric type when it was built, and a machine may hold
lattices of different numeric types and references, since no consumer reads
two of them as one.

Reading the machine: `machine[:ESR]` or `machine["ESR"]` is the lattice of
that name (an unknown name is refused listing the names the machine holds),
`keys(machine)` the names in declaration order, `haskey(machine, :ESR)`,
`length(machine)` the lattice count, and iteration yields the lattices in
order; `machine.name`, `machine.lattices` and `machine.knob_roots` are the
stored fields. Two machines are `==` when their names and shared roots agree
and their lattices agree pairwise in order by `Lattice`'s structural equality;
`hash` is consistent with it; `show` prints one line.

Where a machine is accepted: `StrongStrongTask(machine, :ESR, :HSR; ...)`
pairs two lattices by name, beam 1 with the first (the same name twice is
legal: two beams in one ring, as the strong-strong contracts build their
cases); `StrongStrongTask(machine; ...)` takes a machine of exactly two
lattices in declaration order and refuses any other count by name;
`TrackingTask(machine)`, `analyze(analysis, machine)` and
`one_turn_matrix(machine)` take a one-lattice machine through the one site a
`Lattice` enters by (`_element_tuple`, D15), and a machine of several lattices
handed where one line is wanted is refused by name with the remedy
(`machine[:NAME]`, or the pairing form). In every case the task sees exactly
the placements the lattice's bare line gives: the runtime it compiles, its
kernels and its per-turn work are those of the tuple spelling, which the suite
pins by comparing the compiled runtimes and the tracked coordinates of the two
spellings.

Not in this record: beam definitions and machine-level reference particles
(listed by D5; a `Lattice` carries its entrance reference, and no runtime
consumer reads a machine-level one yet, so none is stored, a stage-3 decision
recorded in `docs/history/machine_description_stage3_2026_11_25.md`); the
TOML form, `write_machine` and `read_machine` (stage 4, D13); `with_overrides`
(stage 5, D11). Not a Core Object (D16): a record over the lattice layer, like
`Lattice` and `LinearOptics`.

```julia
esr = Lattice("ESR"; line = esr_line, reference = electron, knob_root = (:esr, :ip))
hsr = Lattice("HSR"; line = hsr_line, reference = proton, knob_root = (:hsr, :ip))
eic = Machine("EIC"; lattices = (esr, hsr), knob_root = :ip)
task = StrongStrongTask(eic, :ESR, :HSR; policy = policy)
keys(eic)                      # ("ESR", "HSR")
eic[:HSR] === hsr              # true
Machine(esr) == Machine("ESR"; lattices = (esr,))   # the implicit one-lattice machine
```
"""
struct Machine
    name::String
    lattices::Tuple{Vararg{Lattice}}
    knob_roots::Tuple{Vararg{Symbol}}
end

function Machine(name::AbstractString; lattices, knob_root=nothing)
    stored = _machine_lattices(String(name), lattices)
    roots = _lattice_knob_roots(knob_root, "Machine")
    _machine_check_knob_roots(String(name), stored, roots)
    return Machine(String(name), stored, roots)
end

# The implicit one-lattice machine made explicit (D5).
Machine(lattice::Lattice) = Machine(getfield(lattice, :name); lattices=(lattice,))

"""
    _machine_lattices(name::String, lattices) -> Tuple{Vararg{Lattice}}

`lattices` as the stored tuple: one `Lattice`, or a tuple or vector of them.
Refused by name, each message starting `Machine("<name>"):`: an empty tuple or
vector; an entry that is not a `Lattice` (a bare `BeamLine`, a tuple of
elements: wrap it in `Lattice(name; line = ...)` first); two lattices of one
name (the names are the machine's keys); any other value.
"""
function _machine_lattices(name::String, lattices)
    who = "Machine($(repr(name)))"
    lattices isa Lattice && return (lattices,)
    if lattices isa Union{Tuple,AbstractVector}
        isempty(lattices) && throw(ArgumentError(
            "$(who): `lattices` is an empty $(lattices isa Tuple ? "tuple" : "vector"); a " *
            "machine holds at least one Lattice (lattices = (lattice,), or a single Lattice)"))
        for (i, l) in enumerate(lattices)
            l isa Lattice || throw(ArgumentError(
                "$(who): entry $(i) of `lattices` is not a Lattice; got " *
                _machine_describe_entry(l) * ". Wrap each line in a lattice first: " *
                "Lattice(name; line = BeamLine(name, element1, element2, ...))"))
        end
        names = String[getfield(l, :name) for l in lattices]
        for (i, n) in enumerate(names)
            j = findfirst(==(n), names)
            j == i || throw(ArgumentError(
                "$(who): two lattices named $(repr(n)) (entries $(j) and $(i) of `lattices`); " *
                "the lattice names are the machine's keys and must be unique. Give each " *
                "lattice a name of its own: Lattice(\"$(n)_2\"; line = ...)"))
        end
        return Tuple(Lattice[l for l in lattices])
    end
    throw(ArgumentError(
        "$(who): `lattices` must be a Lattice or a tuple or vector of them (lattices = " *
        "(esr, hsr)); got $(_machine_describe_entry(lattices))"))
end

# What a non-Lattice `lattices` entry is, for the refusal: a bare line by its
# name, a bare element spec by its kind, a tuple or vector by its length, any
# other value by its type.
_machine_describe_entry(x) =
    x isa ElementSpec{:line} ? "a bare BeamLine $(repr(line_name(x)))" :
    x isa ElementSpec ? "a bare ElementSpec{$(repr(kind(x)))}" :
    x isa Tuple ? "a Tuple of $(length(x)) element(s)" :
    x isa AbstractVector ? "a Vector of $(length(x)) element(s)" :
    "a value of type $(typeof(x))"

"""
    _machine_check_knob_roots(name::String, lattices, roots) -> nothing

The machine-level knob-root tripwire (D7). Every root declared by two or more
lattices must be one of the machine's shared `roots`; refused by name with the
root, the lattices declaring it and the remedy (`knob_root = :<root>` on the
machine when the sharing is intended, a root of its own per lattice otherwise).
No two distinct roots of the machine, the lattices' and the shared ones
together, may overlap as dotted prefixes (`_knob_root_overlaps`); refused by
name with both roots and where each is declared.
"""
function _machine_check_knob_roots(name::String, lattices::Tuple{Vararg{Lattice}},
                                   roots::Tuple{Vararg{Symbol}})
    who = "Machine($(repr(name)))"
    # Where each root is declared: the lattices by name, the machine as "the
    # machine's shared roots"; declaration order kept for the messages.
    declared = Pair{Symbol,Vector{String}}[]
    declare!(root, by) = begin
        i = findfirst(d -> first(d) === root, declared)
        i === nothing ? push!(declared, root => [by]) : push!(last(declared[i]), by)
        nothing
    end
    for l in lattices, r in getfield(l, :knob_roots)
        declare!(r, "lattice $(repr(getfield(l, :name)))")
    end
    for r in roots
        declare!(r, "the machine's shared knob roots")
    end
    # A root two or more lattices declare reads ONE set of knobs (the registry
    # is process-global): the sharing must be declared on the machine.
    for (root, by) in declared
        lattice_users = unique(filter(startswith("lattice "), by))
        length(lattice_users) >= 2 && !(root in roots) && throw(ArgumentError(
            "$(who): knob root $(root) is declared by $(length(lattice_users)) lattices " *
            "($(join(lattice_users, ", "))), so they read ONE set of knobs, but the machine " *
            "does not declare it shared. Declare the sharing when it is intended: " *
            "Machine($(repr(name)); lattices = ..., knob_root = :$(root)); otherwise give " *
            "each lattice a root of its own (knob_root = :<lattice>_$(root))"))
    end
    # No two distinct roots of the machine may nest as dotted prefixes.
    for i in eachindex(declared), j in i+1:lastindex(declared)
        a, by_a = declared[i]
        b, by_b = declared[j]
        _knob_root_overlaps(a, b) && throw(ArgumentError(
            "$(who): knob roots $(a) (declared by $(join(by_a, ", "))) and $(b) (declared by " *
            "$(join(by_b, ", "))) overlap: one is a dotted prefix of the other, so every knob " *
            "under the longer sits under both. Use roots that do not nest (one root per " *
            "lattice, such as $(a)_1 and $(a)_2), or declare ONE root for both lattices and " *
            "share it on the machine (knob_root = :$(a))"))
    end
    return nothing
end

"""
    _knob_root_overlaps(a::Symbol, b::Symbol) -> Bool

Whether two DISTINCT knob roots overlap: one is a dotted prefix of the other
(`ring` and `ring.arc`), so a knob under the longer sits under both. Equal
roots do not overlap (they are one root); `ring` and `ringx` do not either, the
rule `_knob_under_prefix` applies.
"""
function _knob_root_overlaps(a::Symbol, b::Symbol)
    a === b && return false
    sa, sb = string(a), string(b)
    return _knob_under_prefix(sa, sb) || _knob_under_prefix(sb, sa)
end

"""
    _machine_only_lattice(machine::Machine, consumer::AbstractString) -> Lattice

The one lattice of a one-lattice machine, for the consumers that take one line
(`_element_tuple`, the one-turn-matrix helpers). A machine of several lattices
is refused by name: the machine, its lattice count and names, the `consumer`
asking, and the remedy (`machine[:NAME]` for one lattice, `StrongStrongTask(
machine, :A, :B)` for a pair).
"""
function _machine_only_lattice(machine::Machine, consumer::AbstractString)
    lattices = getfield(machine, :lattices)
    length(lattices) == 1 && return lattices[1]
    names = join(map(l -> repr(getfield(l, :name)), lattices), ", ")
    throw(ArgumentError(
        "Machine($(repr(getfield(machine, :name)))): $(consumer) takes one line, but the " *
        "machine holds $(length(lattices)) lattices ($(names)). Name the lattice meant: " *
        "machine[:$(getfield(lattices[1], :name))] (one lattice), or pair two of them with " *
        "StrongStrongTask(machine, :$(getfield(lattices[1], :name)), " *
        ":$(getfield(lattices[2], :name)))"))
end

# The readers: the lattice names are the keys, in declaration order.
function Base.getindex(machine::Machine, name::Union{Symbol,AbstractString})
    key = String(name)
    for l in getfield(machine, :lattices)
        getfield(l, :name) == key && return l
    end
    throw(ArgumentError(
        "Machine($(repr(getfield(machine, :name)))): no lattice named $(repr(key)); the " *
        "machine holds $(join(map(repr, keys(machine)), ", ")) (keys(machine)). Index it " *
        "by one of those names: machine[:$(getfield(first(getfield(machine, :lattices)), :name))]"))
end
Base.haskey(machine::Machine, name::Union{Symbol,AbstractString}) =
    any(l -> getfield(l, :name) == String(name), getfield(machine, :lattices))
Base.keys(machine::Machine) = map(l -> getfield(l, :name), getfield(machine, :lattices))
Base.length(machine::Machine) = length(getfield(machine, :lattices))
Base.iterate(machine::Machine, state...) = iterate(getfield(machine, :lattices), state...)
Base.eltype(::Type{Machine}) = Lattice
# Two machines are equal when their names and shared roots agree and their
# lattices agree pairwise in order, by `Lattice`'s structural equality (the
# lattice count included: `==` on tuples of unequal length is false).
Base.:(==)(a::Machine, b::Machine) =
    getfield(a, :name) == getfield(b, :name) &&
    getfield(a, :knob_roots) == getfield(b, :knob_roots) &&
    getfield(a, :lattices) == getfield(b, :lattices)
# Consistent with `==`: the name, the shared roots, then every lattice through
# `hash(::Lattice)`, which equal lattices share.
function Base.hash(a::Machine, h::UInt)
    h = hash(getfield(a, :name), h)
    h = hash(getfield(a, :knob_roots), h)
    for l in getfield(a, :lattices)
        h = hash(l, h)
    end
    return h
end

function Base.show(io::IO, machine::Machine)
    # One line: Machine("EIC": 2 lattices ESR (13 placements), HSR (12 placements), shared knob roots (ip,))
    lattices = getfield(machine, :lattices)
    roots = getfield(machine, :knob_roots)
    n = length(lattices)
    print(io, "Machine(", repr(getfield(machine, :name)), ": ", n, " lattice", n == 1 ? " " : "s ")
    print(io, join(map(lattices) do l
        m = length(line_entries(getfield(l, :line)))
        string(getfield(l, :name), " (", m, " placement", m == 1 ? "" : "s", ")")
    end, ", "))
    if isempty(roots)
        print(io, ", no shared knob roots)")
    else
        print(io, ", shared knob roots (", join(string.(roots), ", "), length(roots) == 1 ? ",))" : "))")
    end
end
