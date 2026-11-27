#=
Run suite testsets EXTRACTED from the suite's files, by title, before the full
gate. A development checkpoint, never the finish line (AGENTS.md: the gate the
verification matrix names runs on the final tree); it exists because the
suite's sweeps and a campaign's own testsets run in seconds after `using
Octopus`, while the full lane takes about a hundred minutes, and because a
block that fails extracted fails for a reason the gate would only report later
(the 2026-10 lesson: the Core.Box sweep and the detached-docstring sweep killed
two gate attempts that this would have caught first). Since the 2026-11-27
split, `Pkg.test(test_args=["only=<file>"])` runs a whole suite file under the
driver's tripwire (docs/design/testing_lanes.md, section 1); this tool is the
finer grain, one block.

Run from the project root (the main project, so `using Octopus` resolves):

    julia --project=. --threads=4 test/run_extracted_testsets.jl \
        "Every export is documented" "No docstring is detached by comment lines"

It lives at the test root beside the suite's probe files, not under
test/examples/: every `.jl` there is a HARNESS the suite runs and requires to
write under OCTOPUS_RESULT_DIR ("Every example script runs against the
current interface"), which this tool, a runner of suite blocks, is not.

Each block is found in the suite's files (`test/suite/*.jl`) by its title --
a column-0 `@testset "<title>"` or a lane-gated `if _lane_gate("<title>")`
block -- through the parser (`test/suite_structure.jl`), and evaluated in
Main with `_lane_full()` and `_lane_gate(...)` answering true, after
`test/suite/common.jl` (what every suite file may reach for) and the
file-level definitions of the block's own file that the block mentions,
transitively (a helper's helpers, a test observer's `Octopus.` methods), in
source order. That resolution is what the single-file runner lacked: it
evaluated the test observers only, and a block naming another helper errored
with `UndefVarError` here and was left to the gate.

Limits, stated so a reader does not mistake an extracted error for a suite
failure: state an earlier testset of the same file leaves behind (a registry
claim, a file under the result directory, a global a `let` block at file level
assigned) is absent here, and `OCTOPUS_EXTRACT_PRELUDE=<file>` includes a
Julia file first (a place for one run's own definitions). Exit status: 1 when
any block failed, else 0; the log is the evidence, read it.
=#
using Octopus, Test, LinearAlgebra, Random
const _HAS_CUDA = Octopus._HAS_CUDA
_lane_full() = true
_lane_gate(name::AbstractString) = true
include(joinpath(@__DIR__, "suite_structure.jl"))
include(joinpath(@__DIR__, "suite", "common.jl"))      # _SUITE_FILES, CUDA_TESTS_ACTIVE, the shared helpers
let prelude = get(ENV, "OCTOPUS_EXTRACT_PRELUDE", "")
    isempty(prelude) || (println("=== prelude: ", prelude, " ==="); Base.include(Main, prelude))
end
const SUITE = Dict(f => let text = read(joinpath(_suite_dir(), f), String)
                            (lines=split(text, '\n'; keepempty=true), units=suite_units(text; filename=f))
                        end for f in _SUITE_FILES)
# the block by title: exactly one across the files
function find_block(title)
    hits = [(f, u) for f in _SUITE_FILES for u in SUITE[f].units if u.kind in (:testset, :gated) && u.name == title]
    length(hits) == 1 || error("title $(repr(title)): $(length(hits)) blocks across " * join(_SUITE_FILES, ", "))
    return hits[1]
end
# the file-level definitions of `f` the block reaches, transitively, in source order
function needed_units(f, block::SuiteUnit)
    units = SUITE[f].units
    frontier = unit_symbols(block)
    chosen = Set{Int}()
    while true
        before = length(chosen)
        defined = Set(Symbol(n) for k in chosen if units[k].kind === :def for n in unit_names(units[k]))
        for (k, u) in enumerate(units)
            k in chosen && continue
            take = (u.kind === :def && any(Symbol(n) in frontier for n in unit_names(u))) ||
                   (u.kind === :method && !isdisjoint(unit_symbols(u), defined))
            take || continue
            push!(chosen, k)
            union!(frontier, unit_symbols(u))
        end
        length(chosen) == before && break
    end
    return [units[k] for k in sort!(collect(chosen))]
end
const FAILED = String[]
for title in ARGS
    f, block = find_block(title)
    lines = SUITE[f].lines
    for u in needed_units(f, block)
        u.kind === :def && all(isdefined(Main, Symbol(n)) for n in unit_names(u)) && continue
        Core.eval(Main, Meta.parseall(unit_text(lines, u); filename="$(f)[def $(u.name)]"))
    end
    println("=== extracted: ", title, " (", f, ") ===")
    try
        Core.eval(Main, Meta.parseall(unit_text(lines, block); filename="$(f)[$(title)]"))
    catch e
        push!(FAILED, title)
        println("!!! block failed: ", title, " -- ", sprint(showerror, e)[1:min(end, 400)])
    end
end
println("=== extracted run finished; failed blocks: ", length(FAILED), " ===")
foreach(t -> println("  FAILED: ", t), FAILED)
isempty(FAILED) || exit(1)
