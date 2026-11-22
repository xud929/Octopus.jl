#=
Run suite testsets EXTRACTED from test/runtests.jl, by title, before the full
gate. A development checkpoint, never the finish line (AGENTS.md: the gate the
verification matrix names runs on the final tree); it exists because the
suite's sweeps and a campaign's own testsets run in seconds after `using
Octopus`, while the full lane takes about ninety minutes, and because a block
that fails extracted fails for a reason the gate would only report later (the
2026-10 lesson: the Core.Box sweep and the detached-docstring sweep killed two
gate attempts that this would have caught first).

Run from the project root (the main project, so `using Octopus` resolves):

    julia --project=. --threads=4 test/run_extracted_testsets.jl \
        "Every export is documented" "No docstring is detached by comment lines"

It lives at the test root beside the suite's probe files, not under
test/examples/: every `.jl` there is a HARNESS the suite runs and requires to
write under OCTOPUS_RESULT_DIR ("Every example script runs against the
current interface"), which this tool, a runner of suite blocks, is not.

Each block is cut out of test/runtests.jl by its title, from the column-0
`@testset "<title>"` line to the first bare `end` at column 0, and evaluated
in Main with `_lane_full()` and `_lane_gate(...)` answering true; the
file-level test observers (`struct X <: Octopus.AbstractBeamObserver` and the
`Octopus.` method lines that follow them) a block names are evaluated first.

Limits, stated so a reader does not mistake an extracted error for a suite
failure: file-level helpers other than observers (test fixtures, helper
functions, `using ForwardDiff`) are NOT evaluated, so a block that names one
errors with `UndefVarError` here and is left to the gate; the per-block
summaries print what ran. `OCTOPUS_EXTRACT_PRELUDE=<file>` includes a Julia
file first (a place to define such helpers for one run; the stage-2 audit of
2026-11-22 used one that cut the needed helper definitions out of the suite
by name). Exit status: 1 when any block failed, else 0; the log is the
evidence, read it.
=#
using Octopus, Test, LinearAlgebra, Random
const _HAS_CUDA = Octopus._HAS_CUDA
const CUDA_TESTS_ACTIVE = Octopus._HAS_CUDA && Octopus.CUDA.functional()
_lane_full() = true
_lane_gate(name::AbstractString) = true
let prelude = get(ENV, "OCTOPUS_EXTRACT_PRELUDE", "")
    isempty(prelude) || (println("=== prelude: ", prelude, " ==="); Base.include(Main, prelude))
end
root = pkgdir(Octopus)
lines = readlines(joinpath(root, "test", "runtests.jl"))
function block(title)
    start = findfirst(l -> startswith(l, "@testset \"" * title * "\""), lines)
    start === nothing && error("no testset titled $(repr(title))")
    stop = findnext(l -> l == "end", lines, start)
    return join(lines[start:stop], "\n")
end
# name => definition text, for every file-level test observer
function observer_defs()
    defs = Dict{String,String}()
    for (i, l) in enumerate(lines)
        m = match(r"^(?:mutable )?struct (\w+) <: Octopus\.AbstractBeamObserver", l)
        m === nothing && continue
        stop = endswith(l, " end") ? i : findnext(==("end"), lines, i)
        j = stop + 1
        while j <= length(lines) && (startswith(lines[j], "Octopus.") || startswith(lines[j], "    "))
            j += 1
        end
        defs[m.captures[1]] = join(lines[i:j-1], "\n")
    end
    return defs
end
defs = observer_defs()
const FAILED = String[]
for title in ARGS
    text = block(title)
    for (name, def) in defs
        occursin(name, text) || continue
        isdefined(Main, Symbol(name)) && continue
        Core.eval(Main, Meta.parseall(def; filename="runtests.jl[def " * name * "]"))
    end
    println("=== extracted: ", title, " ===")
    try
        Core.eval(Main, Meta.parseall(text; filename="runtests.jl[" * title * "]"))
    catch e
        push!(FAILED, title)
        println("!!! block failed: ", title, " -- ", sprint(showerror, e)[1:min(end, 400)])
    end
end
println("=== extracted run finished; failed blocks: ", length(FAILED), " ===")
foreach(t -> println("  FAILED: ", t), FAILED)
isempty(FAILED) || exit(1)
