export with_overrides

"""
    with_overrides(lattice::Lattice, (selector => (param = value, ...))...; name = lattice.name) -> Lattice
    with_overrides(machine::Machine, lattice_name, (selector => (param = value, ...))...; name = machine.name) -> Machine

The derived lattice of design D11 (`docs/design/machine_description.md`): the
third variation route beside knobs (numbers that move) and placement
overrides written in place (`entry.k = v`). It copies the source lattice's
placements, as `BeamLine(; entries)` copies them, so the variant shares no
mutable state with the source; applies every pair's overrides to every
placement its selector matches; and returns a NEW `Lattice` with the source's
reference, knob roots and numeric type, both construction tripwires run again
on the result. The source lattice, its line and its module are untouched, so
the pristine lattice and the variant coexist in one process, and the
variant's snapshot (`write_machine`) shows the overrides as placement data,
`{ ref = "QF", path = "...", overrides = { kn = [...] } }`.

`selector` is anything [`find_entries`](@ref) takes: a `Selector` (`sel"ARC1/QF[*]"`),
a `String` parsed as one, a `Regex` matched against the rendered path, a
`Symbol` matched against the placement tags, a `Type` (the stored spec type
`ElementSpec{:quadrupole}`, a kind's friendly constructor type
`QuadrupoleSpec`, a hook type), or a predicate `LineEntry -> Bool`. The
right-hand side is a `NamedTuple` or a `Dict{Symbol}` of parameter => value;
a value is anything a placement override holds (a number, a knob expression,
a tuple, a rule object). Every key passes the guards an in-place override
passes (`setproperty!(::LineEntry, ...)`): a folded named strength (`k1` on a
quadrupole: write `kn`), a line placement's structure or length (`entries`,
`name`, `L`) and a key on a placement that is not an element spec (a hook or
a marker has no parameters to override) are refused by name with the remedy.
A selector that matches no placement is refused by name, with the selector
and the lattice's paths (loud beats silent: a variant that changed nothing is
a study that measured nothing). Later pairs win over earlier ones on the same
placement and key, and an override the source placement already carries is
replaced by the new value. Placements inside a nested line kept whole are not
addressed (the kept-whole line is one placement of the top line): derive that
line's lattice first and rebuild.

The machine form replaces the named lattice by its variant (the lattice keeps
its name, the machine's key) and returns a new `Machine` with the machine's
other lattices as they are and the shared roots kept, its own tripwire run
again; an unknown name is refused listing the keys, as `machine[name]` does.

```julia
dba_trim = with_overrides(lattice, sel"DBA_RING/QF[2]" => (kn = (0.0, 1.52),))
scan     = [with_overrides(lattice, QuadrupoleSpec => (nst = n,); name = "DBA_nst\$n") for n in (2, 4, 8)]
eic_var  = with_overrides(eic, :ESR, :crab => (phase_noise = (WhiteNoise(1e-5; rng_id = 11), nothing, nothing),))
```
"""
function with_overrides(lattice::Lattice, pairs::Pair...; name::AbstractString=getfield(lattice, :name))
    error("with_overrides: not implemented yet (stage 5 skeleton)")   # STUB (unit A)
end
function with_overrides(machine::Machine, which::Union{Symbol,AbstractString}, pairs::Pair...;
                        name::AbstractString=getfield(machine, :name))
    error("with_overrides(machine, ...): not implemented yet (stage 5 skeleton)")   # STUB (unit A)
end

"""
    _overrides_line(line::ElementSpec{:line}, pairs, where::AbstractString) -> ElementSpec{:line}

The copy of `line` with the pairs' overrides applied: every placement copied
(`_copy_line_entry`), each pair's selector resolved through `find_entries` on
the SOURCE line (a selector matching nothing refused by name, naming `where`,
the selector and the line's paths), each key checked by `_overrides_check_key`
and written into the copy's `overrides`; the line's own parameters (its
`numeric_type`, offsets) carried as they are through the keyword form
`BeamLine(; name, entries, kwargs...)`, which keeps the provenance paths.
"""
function _overrides_line(line::ElementSpec{:line}, pairs, where::AbstractString)
    error("_overrides_line: not implemented yet (stage 5 skeleton)")   # STUB (unit A)
end

"""
    _overrides_check_key(entry::LineEntry, key::Symbol, where::AbstractString) -> nothing

The guards of an in-place override, by name: `_reject_folded_override` and
`_reject_line_placement_override` as `setproperty!(::LineEntry, ...)` runs
them, and the refusal of a key on a placement whose spec is not an
`ElementSpec` (a hook, a marker), which the in-place route does not refuse
today (stage-3 lead; the audit of stage 5 decides whether it should).
"""
function _overrides_check_key(entry::LineEntry, key::Symbol, where::AbstractString)
    error("_overrides_check_key: not implemented yet (stage 5 skeleton)")   # STUB (unit A)
end

"""
    _overrides_table(rhs, where::AbstractString) -> Vector{Pair{Symbol,Any}}

The right-hand side of a pair as parameter => value pairs: a `NamedTuple`, a
`Dict` with `Symbol` keys, or a vector or tuple of `Symbol => value` pairs;
anything else, an empty table and a non-`Symbol` key refused by name.
"""
function _overrides_table(rhs, where::AbstractString)
    error("_overrides_table: not implemented yet (stage 5 skeleton)")   # STUB (unit A)
end
