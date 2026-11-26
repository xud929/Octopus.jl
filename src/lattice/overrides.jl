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
`name`, `L`), a key on a hook placement (a `ScheduledObserver` is not an
element spec and has no parameters to override) and a key the placement's
kind does not declare (`L` on a marker, `k1` on a drift, a misspelling: the
snapshot's own table of a kind's keys, `_toml_declared_keys`) are refused by
name with the remedy. A selector that matches no placement is refused by
name, with the selector and the lattice's paths, and so is a call with no
pair at all (loud beats silent: a variant that changed nothing is a study
that measured nothing). Later pairs win over earlier ones on the same
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
    where = "with_overrides($(repr(getfield(lattice, :name))))"
    isempty(pairs) && throw(ArgumentError(
        "$(where): no `selector => overrides` pair was given, so the variant would be a copy " *
        "that changed nothing. Name the placements and the parameters to vary, e.g. " *
        "with_overrides(lattice, sel\"RING/QF[2]\" => (kn = (0.0, 1.52),))"))
    line = _overrides_line(getfield(lattice, :line), pairs, where)
    # No `_SPEC_EPOCH` bump here, unlike the in-place route: nothing shared was
    # mutated. The source's placements and specs are untouched (the copies hold
    # the overrides, the spec objects are the same), and a task built from the
    # variant compiles it fresh; a task built from the source has nothing to
    # recompile.
    roots = getfield(lattice, :knob_roots)
    return Lattice(String(name); line, reference=getfield(lattice, :reference),
                   knob_root=isempty(roots) ? nothing : roots, eltype=getfield(lattice, :eltype))
end
function with_overrides(machine::Machine, which::Union{Symbol,AbstractString}, pairs::Pair...;
                        name::AbstractString=getfield(machine, :name))
    where = "with_overrides($(repr(getfield(machine, :name))))"
    key = String(which)
    haskey(machine, key) || throw(ArgumentError(
        "$(where): no lattice named $(repr(key)); the machine holds " *
        join(map(repr, keys(machine)), ", ") * " (keys(machine)). Name one of those: " *
        "with_overrides(machine, :$(first(keys(machine))), selector => (param = value,))"))
    source = machine[key]
    variant = with_overrides(source, pairs...)      # keeps its name, the machine's key
    lattices = Tuple(Lattice[l === source ? variant : l for l in getfield(machine, :lattices)])
    roots = getfield(machine, :knob_roots)
    return Machine(String(name); lattices, knob_root=isempty(roots) ? nothing : roots)
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
    source = line_entries(line)
    copies = LineEntry[_copy_line_entry(e) for e in source]
    for pair in pairs
        pair isa Pair || throw(ArgumentError(
            "$(where): every argument after the lattice is a `selector => overrides` pair; got " *
            "$(repr(pair)) of type $(typeof(pair))"))
        selector, rhs = pair
        table = _overrides_table(rhs, where)
        matched = find_entries(line, selector)
        isempty(matched) && throw(ArgumentError(
            "$(where): the selector $(repr(selector)) matches no placement of line " *
            "$(repr(line_name(line))), so the variant would change nothing. The line's " *
            "placements are: " * join(map(entry_path, source), ", ") * ". Address one of " *
            "those paths (sel\"...\", a Regex), a tag (Symbol), a spec type or a predicate"))
        for i in matched
            target = copies[i]
            for (key, value) in table
                _overrides_check_key(target, key, where)
                getfield(target, :overrides)[key] = value
            end
        end
    end
    # The line's own parameters (`numeric_type`, offsets) as they are; `name`
    # and `entries` are the keyword form's own arguments.
    own = Dict{Symbol,Any}(k => v for (k, v) in getfield(line, :params) if k !== :name && k !== :entries)
    return BeamLine(; name=line_name(line), entries=copies, own...)
end

"""
    _overrides_check_key(entry::LineEntry, key::Symbol, where::AbstractString) -> nothing

The guards of an in-place override, by name: `_reject_folded_override` and
`_reject_line_placement_override` as `setproperty!(::LineEntry, ...)` runs
them (their messages prefixed with `where` and the placement's path), and two
refusals the in-place route does not make today (stage-3 lead; the audit of
stage 5 decides whether it should): a key on a placement whose spec is not an
`ElementSpec` (a hook such as `ScheduledObserver`: `compile_runtime(entry)`
would die on `kind(spec)` with a non-empty override table), and a key the
placement's kind does not declare, read from the snapshot codec's one table
of a kind's keys (`_toml_declared_keys`: the registry's parameters, the
placement keys, `name`, `numeric_type`), so `L` on a marker (an
`ElementSpec{:marker}` with no physics parameter) or a misspelled key is
refused with the kind's declared keys instead of being stored and read by
nothing. A line placement's keys are its own state and are not checked
against the registry; its structure and length are the second guard's.
"""
function _overrides_check_key(entry::LineEntry, key::Symbol, where::AbstractString)
    spec = getfield(entry, :spec)
    path = entry_path(entry)
    key in _ENTRY_FIELDS && throw(ArgumentError(
        "$(where): `$(key)` is structural on placement $(path) (LineEntry.$(key)) and cannot " *
        "be overridden; override a parameter of the element instead, or rebuild the line"))
    if !(spec isa ElementSpec)
        what = nameof(typeof(spec))
        throw(ArgumentError(
            "$(where): placement $(path) is a $(what), not an element spec, and has no " *
            "parameters to override (`$(key)` was given): a hook is placed as the object it " *
            "is. Build the line with the $(what) you mean in that position instead"))
    end
    # The two guards of the in-place route, their messages kept and prefixed
    # with the placement they refuse.
    try
        _reject_folded_override(spec, key)
        _reject_line_placement_override(spec, key)
    catch err
        err isa ArgumentError || rethrow()
        throw(ArgumentError("$(where): placement $(path): " * err.msg))
    end
    # A key the kind does not declare (a marker's `L`, a drift's `k1`, a typo)
    # would be stored, written by nothing a compile reads, and refused by the
    # snapshot's writer and reader (`_toml_declared_keys`, the codec's one table
    # of a kind's keys: its parameters, the placement keys, `name`,
    # `numeric_type`): refused here, where the message can name the kind's keys.
    # A line placement's keys are its own state (offsets, `numeric_type`),
    # guarded above; the registry declares no parameter list for it.
    if !(spec isa ElementSpec{:line})
        meta = _element_meta_or_nothing(kind(spec))
        if meta !== nothing
            declared = _toml_declared_keys(meta)
            key in declared || throw(ArgumentError(
                "$(where): `$(key)` is not a parameter the kind $(repr(kind(spec))) declares, so " *
                "an override named `$(key)` on placement $(path) would be stored and read by " *
                "nothing (and the snapshot would refuse it); its declared keys are " *
                join(sort!(map(string, collect(declared))), ", ") * ". Check the spelling " *
                "with element_help($(repr(kind(spec))))"))
        end
    end
    return nothing
end

"""
    _overrides_table(rhs, where::AbstractString) -> Vector{Pair{Symbol,Any}}

The right-hand side of a pair as parameter => value pairs: a `NamedTuple`, a
`Dict` with `Symbol` keys, or a vector or tuple of `Symbol => value` pairs;
anything else, an empty table and a non-`Symbol` key refused by name.
"""
function _overrides_table(rhs, where::AbstractString)
    out = Pair{Symbol,Any}[]
    if rhs isa NamedTuple
        for (k, v) in Base.pairs(rhs)
            push!(out, k => v)
        end
    elseif rhs isa AbstractDict
        for (k, v) in rhs
            k isa Symbol || throw(ArgumentError(
                "$(where): an override key must be a Symbol naming the parameter; got the key " *
                "$(repr(k)) of type $(typeof(k)) in $(repr(rhs)). Write the table as a NamedTuple " *
                "(kn = (0.0, 1.5),) or as Dict(:kn => (0.0, 1.5))"))
            push!(out, k => v)
        end
        sort!(out; by=p -> string(first(p)))    # a Dict iterates in no fixed order
    elseif rhs isa Union{AbstractVector,Tuple} && all(x -> x isa Pair, rhs)
        for p in rhs
            k = first(p)
            k isa Symbol || throw(ArgumentError(
                "$(where): an override key must be a Symbol naming the parameter; got the key " *
                "$(repr(k)) of type $(typeof(k)) in $(repr(rhs)). Write the pairs as " *
                ":kn => (0.0, 1.5), or the table as a NamedTuple (kn = (0.0, 1.5),)"))
            push!(out, k => last(p))
        end
    else
        throw(ArgumentError(
            "$(where): the right-hand side of a selector pair must be the overrides as a " *
            "NamedTuple (kn = (0.0, 1.5),), a Dict with Symbol keys, or a vector or tuple of " *
            ":param => value pairs; got $(repr(rhs)) of type $(typeof(rhs))"))
    end
    isempty(out) && throw(ArgumentError(
        "$(where): the override table $(repr(rhs)) is empty, so the variant would change " *
        "nothing on the placements it selects; name at least one parameter => value"))
    return out
end
