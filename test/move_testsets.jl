#=
Move top-level suite blocks and file-level helpers between the suite's files,
by title and by name (the 2026-11-27 suite split, docs/design/testing_lanes.md
section 1). The suite is `test/runtests.jl` (the driver) plus the files it
includes from `test/suite/`; each file is self-contained but for
`test/suite/common.jl`, which the driver's layout tripwire enforces. This tool
is how a testset changes file without being retyped: it cuts the unit out of
one file verbatim, with the comment run directly above it, appends it to
another in source order, and REPORTS the file-level helpers the moved units
still reach for in the source file, so that they can be moved too (into the
destination when only moved units use them, into `common.jl` when both sides
do). Units are read through the parser (`test/suite_structure.jl`), never
by indentation.

    julia --startup-file=no test/move_testsets.jl --from test/suite/legacy.jl \
        --to test/suite/artifact_observers.jl --titles titles.txt \
        [--names helper1,helper2] [--dry-run]

`--titles` names a file with one title per line: of a column-0
`@testset "<title>"` or of a lane-gated `if _lane_gate("<title>")` block.
`--names` lists file-level definitions (functions, structs, consts, macros,
one-line methods, assignments) to move by name; a moved struct takes along
the `Module.method(...)` definitions that mention it. `--dry-run` prints the
plan and the report and writes nothing. Exit status 1 when a title or name is
not found exactly once (names: at least once), else 0. Blank lines between
units stay where they are; a run of three or more left by a cut is folded to
two. A comment separated from the unit below it by a blank line is not part
of that unit and stays behind: read the plan.
=#

include(joinpath(@__DIR__, "suite_structure.jl"))

const _USAGE = "usage: julia --startup-file=no test/move_testsets.jl --from F --to G [--titles TITLES_FILE] [--names a,b] [--dry-run]"

function parse_args(args)
    opts = Dict{String,Any}("dry-run" => false, "titles" => String[], "names" => String[])
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--dry-run"
            opts["dry-run"] = true
        elseif a in ("--from", "--to", "--titles", "--names")
            i < length(args) || error(_USAGE)
            v = args[i + 1]
            if a == "--titles"
                append!(opts["titles"], filter(!isempty, strip.(readlines(v))))
            elseif a == "--names"
                append!(opts["names"], filter(!isempty, strip.(split(v, ','))))
            else
                opts[a[3:end]] = v
            end
            i += 1
        else
            error("unknown argument $(repr(a))\n" * _USAGE)
        end
        i += 1
    end
    haskey(opts, "from") && haskey(opts, "to") || error(_USAGE)
    return opts
end

function main(args)
    opts = parse_args(args)
    from, to = opts["from"], opts["to"]
    text = read(from, String)
    lines = split(text, '\n'; keepempty=true)
    units = suite_units(text; filename=from)
    chosen = falses(length(units))
    missing = String[]
    for title in opts["titles"]
        hits = findall(u -> u.kind in (:testset, :gated) && u.name == title, units)
        length(hits) == 1 || (push!(missing, "title $(repr(title)): $(length(hits)) matches"); continue)
        chosen[hits[1]] = true
    end
    for name in opts["names"]
        hits = findall(u -> u.kind === :def && name in unit_names(u), units)
        isempty(hits) && (push!(missing, "name $(repr(name)): no definition"); continue)
        chosen[hits] .= true
        for (k, u) in enumerate(units)            # a struct takes its Module.method definitions along
            u.kind === :method && Symbol(name) in unit_symbols(u) && (chosen[k] = true)
        end
    end
    if !isempty(missing)
        foreach(m -> println(stderr, "NOT FOUND: ", m), missing)
        exit(1)
    end
    moved = findall(chosen)
    isempty(moved) && error("nothing selected")
    owned = falses(length(lines))
    for k in moved, i in units[k].prefix:units[k].last
        owned[i] = true
    end
    moved_text = join([lines[i] for i in eachindex(lines) if owned[i]], "\n")
    remaining = String[]
    blanks = 0
    for i in eachindex(lines)
        owned[i] && continue
        if isempty(strip(lines[i]))
            blanks += 1
            blanks <= 2 && push!(remaining, String(lines[i]))
        else
            blanks = 0
            push!(remaining, String(lines[i]))
        end
    end
    # ---- the plan ----
    println("plan: $(length(moved)) units, $(count(owned)) lines from $(from) to $(to)")
    for k in moved
        u = units[k]
        label = isempty(u.name) ? String(lines[u.first])[1:min(end, 80)] : u.name
        println("  $(u.prefix == u.first ? "" : "$(u.prefix)+")$(u.first)-$(u.last)  $(u.kind)  $(label)")
    end
    # ---- the report: helpers across the cut, both directions ----
    moved_syms = union(Set{Symbol}(), (unit_symbols(units[k]) for k in moved)...)
    kept = [u for (k, u) in enumerate(units) if !chosen[k]]
    kept_syms = union(Set{Symbol}(), (unit_symbols(u) for u in kept)...)
    println("\nhelpers the moved units still reach for in $(from) (move them too, or into common.jl):")
    left = [u for u in kept if u.kind === :def && any(Symbol(n) in moved_syms for n in unit_names(u))]
    for u in left
        # a `Module.method(::T)` definition travels with its struct T, so it is not a second user
        others = [v for v in kept if v !== u && !(v.kind === :method && any(Symbol(n) in unit_symbols(v) for n in unit_names(u)))]
        both = any(Symbol(n) in union(Set{Symbol}(), (unit_symbols(v) for v in others)...) for n in unit_names(u))
        println("  $(u.name) (line $(u.first)) -- used by the moved text", both ? " AND by the remaining file: common.jl" : " only: move it along")
    end
    isempty(left) && println("  none")
    println("\nmoved helpers the remaining file still uses (they belong in common.jl instead):")
    back = [units[k] for k in moved if units[k].kind === :def && any(Symbol(n) in kept_syms for n in unit_names(units[k]))]
    foreach(u -> println("  $(u.name) (line $(u.first))"), back)
    isempty(back) && println("  none")
    opts["dry-run"] && (println("\ndry run: nothing written"); return)
    # ---- write ----
    dest = isfile(to) ? read(to, String) : "# $(basename(to)): suite units moved from $(basename(from)) by test/move_testsets.jl\n"
    endswith(dest, "\n") || (dest *= "\n")
    open(to, "w") do io
        write(io, dest, "\n", moved_text, "\n")
    end
    open(from, "w") do io
        write(io, join(remaining, "\n"))
        endswith(remaining[end], "\n") || write(io, "\n")
    end
    # both results must still parse: the cut is verified, not assumed
    suite_units(read(to, String); filename=to)
    suite_units(read(from, String); filename=from)
    println("\nwritten: $(to) (+$(count(owned)) lines), $(from) ($(length(remaining)) lines); both parse")
end

main(ARGS)
