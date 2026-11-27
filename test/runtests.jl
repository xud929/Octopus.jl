# ---------------------------------------------------------------------------
# The suite's driver (docs/design/testing_lanes.md, sections 1 and 4).
#
# `Pkg.test` runs this file. It parses the lane and the `only=` selection,
# loads the test-only dependencies and what every suite file may reach for
# (`suite/common.jl`), runs the layout tripwire on the suite's own files,
# includes those files in the order `_SUITE_FILES` states, and ends with the
# accounting banner. The testsets live under `test/suite/` (since 2026-11-27,
# when the single file was split): `core.jl` holds the structural sweeps every
# run executes, each other file is an area selectable alone, and `legacy.jl`
# is the single-file suite's body, peeled into area files one at a time by
# `test/move_testsets.jl`.
#
# Lanes. Default is the FULL suite; `Pkg.test(test_args=["lane=fast"])`
# selects the development-checkpoint lane, which skips the sections the suite
# files register through `_lane_gate`, printing one loud LANE SKIP line per
# section and an accounting banner at the end. The fast lane is a checkpoint,
# never a finish line: the full-suite gate at CI settings remains the bar
# before any PUSH (owner decision 2026-09-04, AGENTS.md "Definition of Done";
# it was before any commit until then), and the design note's matrix lists
# the change classes for which the full gate (with CUDA active) is mandatory.
#
# Selection. `Pkg.test(test_args=["only=<file>[,<file>]"])`, the basenames of
# `test/suite/` without `.jl`, runs `core.jl` and the named files only (so
# `only=core` is the structural smoke run) and ends by naming every file it
# did not run. An `only=` run is a checkpoint exactly as the fast lane is; it
# earns no authority anywhere else, and the two combine (`lane=fast` inside
# the selected files).
#
# An unknown lane, an unknown file name, or any other argument is an error,
# never a silent fallback to full -- a typo must not produce a vacuous verdict.
# ---------------------------------------------------------------------------
const _TEST_LANE = let
    lanes = [split(a, '='; limit=2)[2] for a in ARGS if startswith(a, "lane=")]
    length(lanes) > 1 && error("multiple lane= arguments: $(lanes)")
    lane = isempty(lanes) ? "full" : String(lanes[1])
    lane in ("full", "fast") ||
        error("unknown test lane $(repr(lane)); valid: lane=full, lane=fast")
    lane
end
const _ONLY_FILES = let
    onlys = [split(a, '='; limit=2)[2] for a in ARGS if startswith(a, "only=")]
    length(onlys) > 1 && error("multiple only= arguments: $(onlys)")
    isempty(onlys) ? nothing : String.(filter(!isempty, strip.(split(onlys[1], ','))))
end
for a in ARGS
    startswith(a, "lane=") || startswith(a, "only=") ||
        error("unknown test argument $(repr(a)); valid: lane=full|fast, only=<suite file>[,<suite file>]")
end
const _LANE_SKIPPED = String[]
_lane_full() = _TEST_LANE == "full"
function _lane_gate(name::AbstractString)
    _lane_full() && return true
    push!(_LANE_SKIPPED, String(name))
    printstyled("LANE SKIP [$(_TEST_LANE)]: $(name)\n"; color=:yellow, bold=true)
    return false
end

using Test
using Octopus
using LinearAlgebra
# Seeded sweeps whose sample values must not be dyadic (see the TSC weight
# testset -- a dyadic-only grid cannot fail on the defect it names, audit U20-1).
using Random
# Capturing warnings as evidence: a testset that asserts a solver did NOT clip
# charge has to be able to see the warning it must not find (audit U19-2).
using Logging
# Test-only: Octopus takes no runtime dependency on any AD package.
using ForwardDiff
# Test-only: loading Symbolics activates the OctopusSymbolicsExt weak-dep
# extension, so the suite exercises the adapter the way a user reaches it.
# Before the extension existed the adapter was dead in package mode and the
# round-trip test silently took its unavailable branch forever (part 6, R3).
using Symbolics
# Test-only, and deliberately NOT `using MPI`: this process must stay a
# serial-passthrough one so the passthrough assertions below mean what they
# say. MPICH_jll is here only for its `mpiexec`, which the multi-process
# section launches; loading a jll triggers no package extension.
using MPICH_jll

include(joinpath(@__DIR__, "suite_structure.jl"))
include(joinpath(@__DIR__, "suite", "common.jl"))

# The files this run includes: every one, or `core.jl` plus the selection.
const _SELECTED_FILES = if _ONLY_FILES === nothing
    copy(_SUITE_FILES)
else
    valid = [f[1:end-3] for f in _SUITE_FILES]
    for o in _ONLY_FILES
        o in valid || error("unknown suite file $(repr(o)) in only=; valid: " * join(valid, ", "))
    end
    [f for f in _SUITE_FILES if f == "core.jl" || f[1:end-3] in _ONLY_FILES]
end

# The layout the split rests on, checked before any suite file runs, in every
# lane and every selection: the directory IS the include list (a file nobody
# includes is a check that never runs, the F2 failure mode); every block
# title and every column-0 helper name is unique across the files (the mover
# and the extracted runner address blocks by title); and no file reaches for
# a helper another file defines, `common.jl` excepted -- the property that
# lets an `only=` run execute a file in the state the full lane gives it. The
# rule is shown failing on a synthetic pair before it is applied to the tree.
@testset "Suite files: the directory is the include list, titles and helpers are unique, and no file reaches for another file's helpers" begin
    files = vcat("common.jl", _SUITE_FILES)
    on_disk = sort(filter(f -> endswith(f, ".jl"), readdir(_suite_dir())))
    @test on_disk == sort(files)
    @test allunique(_SUITE_FILES) && _SUITE_FILES[1] == "core.jl" && !("common.jl" in _SUITE_FILES)
    let pair = Dict("a.jl" => suite_units("helper(x) = x\n@testset \"T\" begin\n    @test helper(1) == 1\nend\n"; filename="a.jl"),
                    "b.jl" => suite_units("@testset \"U\" begin\n    @test helper(2) == 2\nend\n"; filename="b.jl"),
                    "common.jl" => suite_units("shared() = 3\n"; filename="common.jl"))
        @test suite_cross_references(pair) == ["b.jl uses helper of a.jl"]
        pair["b.jl"] = suite_units("@testset \"T\" begin\n    @test shared() == 3\nend\n"; filename="b.jl")
        @test suite_cross_references(pair) == ["title \"T\" appears in a.jl, b.jl"]
        pair["b.jl"] = suite_units("helper(x) = 2x\n@testset \"U\" begin\n    @test helper(2) == 4\nend\n"; filename="b.jl")
        @test suite_cross_references(pair) == ["helper is defined in both a.jl and b.jl"]
    end
    units = Dict(f => suite_units(read(joinpath(_suite_dir(), f), String); filename=f) for f in files)
    violations = suite_cross_references(units)
    isempty(violations) || @info "SUITE LAYOUT: the files below are not self-contained" violations
    @test isempty(violations)
end

for f in _SELECTED_FILES
    include(joinpath(_suite_dir(), f))
end

# Lane and selection accounting (docs/design/testing_lanes.md, section 4): a
# skipped check only stops counting when the skip is visible. Silence here
# would be the F2 failure mode.
if !_lane_full()
    printstyled("\n=== $(uppercase(_TEST_LANE)) LANE: $(length(_LANE_SKIPPED)) heavyweight sections SKIPPED ===\n";
                color=:yellow, bold=true)
    for name in _LANE_SKIPPED
        println("  skipped: ", name)
    end
    printstyled("This lane is a development checkpoint, not a finish line: the full-suite\n" *
                "gate at CI settings is still owed before any push (owner decision 2026-09-04).\n"; color=:yellow)
end
if _ONLY_FILES !== nothing
    not_run = [f for f in _SUITE_FILES if !(f in _SELECTED_FILES)]
    printstyled("\n=== ONLY $(join(_ONLY_FILES, ",")): $(length(not_run)) suite files NOT RUN ===\n"; color=:yellow, bold=true)
    for f in not_run
        println("  not run: ", f)
    end
    printstyled("An only= run is a development checkpoint, not a finish line: the full-suite\n" *
                "gate at CI settings is still owed before any push (owner decision 2026-09-04).\n"; color=:yellow)
end
