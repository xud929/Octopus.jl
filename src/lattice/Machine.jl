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
    # STUB (unit A): normalise `lattices` through `_machine_lattices`, the roots
    # through `_lattice_knob_roots(knob_root, "Machine")`, run
    # `_machine_check_knob_roots`, then build the record.
    error("Machine: not implemented yet (stage 3 skeleton)")
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
    error("_machine_lattices: not implemented yet (stage 3 skeleton)")   # STUB (unit A)
end

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
    error("_machine_check_knob_roots: not implemented yet (stage 3 skeleton)")   # STUB (unit A)
end

"""
    _knob_root_overlaps(a::Symbol, b::Symbol) -> Bool

Whether two DISTINCT knob roots overlap: one is a dotted prefix of the other
(`ring` and `ring.arc`), so a knob under the longer sits under both. Equal
roots do not overlap (they are one root); `ring` and `ringx` do not either, the
rule `_knob_under_prefix` applies.
"""
function _knob_root_overlaps(a::Symbol, b::Symbol)
    error("_knob_root_overlaps: not implemented yet (stage 3 skeleton)")   # STUB (unit A)
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
    error("_machine_only_lattice: not implemented yet (stage 3 skeleton)")   # STUB (unit A)
end

# STUBS (unit A): the readers.
#   Base.getindex(machine::Machine, name::Union{Symbol,AbstractString}) -> Lattice (unknown refused listing keys)
#   Base.haskey(machine::Machine, name::Union{Symbol,AbstractString}) -> Bool
#   Base.keys(machine::Machine) -> Tuple of String, declaration order
#   Base.length(machine::Machine), Base.iterate(machine::Machine, state...) over the lattices,
#   Base.eltype(::Type{Machine}) = Lattice
# STUBS (unit A): Base.:(==), Base.hash (consistent with ==; lattices hashed through `hash(::Lattice)`),
#   Base.show(io, machine) one line:
#   Machine("EIC": 2 lattices ESR (13 placements), HSR (12 placements), shared knob roots (ip,))
#   / Machine("ESR": 1 lattice ESR (13 placements), no shared knob roots)
