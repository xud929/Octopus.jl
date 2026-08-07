# `Vector{Type}`, not `Vector{DataType}`. Most of this repository's own Core
# Objects are parametric -- `StrongStrongTask`, `Beam`, `ElementSpec`,
# `PICPoissonSolver` -- and a bare parametric name is a `UnionAll`, which does
# not convert to `DataType`. So the field as declared could not hold the objects
# an example is FOR, which is part of why these three types went years without
# ever being instantiated (2026-08-05_b audit, U12-16). Strictly widening: a
# caller still passing `DataType[...]` converts.

export ReferenceExample, BenchmarkExample, ResearchStudyExample,
       example_catalog, example_script_path

"""
    ReferenceExample(title, summary, objects)

Curated architectural precedent that agents may use as implementation guidance.
"""
struct ReferenceExample <: AbstractExample
    title::String
    summary::String
    objects::Vector{Type}
end

"""
    BenchmarkExample(title, summary, objects)

Performance or scaling example associated with a set of architectural objects.
"""
struct BenchmarkExample <: AbstractExample
    title::String
    summary::String
    objects::Vector{Type}
end

"""
    ResearchStudyExample(title, summary, objects)

Research-oriented example. These are useful context but should be treated as
less normative than `ReferenceExample`.
"""
struct ResearchStudyExample <: AbstractExample
    title::String
    summary::String
    objects::Vector{Type}
end

# ---------------------------------------------------------------------------
# The catalogue.
#
# `Example` is one of AGENTS.md's seven Core Objects, and its entire runtime
# realisation used to be the three struct definitions above -- never
# instantiated anywhere, so `summarize_registry().examples` answered "which
# examples should an agent imitate?" with three empty type NAMES, and the
# registry snapshot listed the same three under "## Examples". The curated
# precedents actually live as scripts in `examples/`, which the registry did
# not know about (2026-08-05_b audit, U12-16).
#
# `path` is a repository-relative string rather than a resolved path so the
# entry stays valid in a snapshot; `example_script_path` resolves it.
# ---------------------------------------------------------------------------

"""
    example_catalog() -> Vector{AbstractExample}

The curated example scripts, as `Example` objects the registry can answer with.

Each entry names a committed script under `examples/`, the Core Objects it
demonstrates, and what it is a precedent FOR. Resolve an entry's script with
[`example_script_path`](@ref).
"""
function example_catalog()
    return AbstractExample[
        ReferenceExample(
            "examples/strong_strong_tracking.jl",
            "Crab-crossing electron-proton collision with two live beams through a " *
            "Poisson solver. The production-shaped precedent for a strong-strong " *
            "simulation: how to build the two beams, the collision element, the " *
            "solver and its slicing, and what to observe. Its configurable " *
            "development harness is test/examples/strong_strong_tracking.jl.",
            Type[StrongStrongTask, StrongStrongCollision, PICPoissonSolver,
                     LongitudinalSlicing, Beam]),
        ReferenceExample(
            "examples/weak_strong_tracking.jl",
            "A live weak proton beam colliding with a fixed soft-Gaussian strong " *
            "beam through a crab crossing. The precedent for weak-strong work, " *
            "and the smaller of the two tracking examples to read first.",
            Type[TrackingTask, ThinStrongBeamSpec, ThinCrabCavitySpec, Beam]),
        ReferenceExample(
            "examples/knob_control.jl",
            "One knob driving many element parameters, in two production-shaped " *
            "scenarios built on the strong-strong example's constants. The " *
            "precedent for parameterising a lattice rather than editing it.",
            Type[KnobRef, TrackingTask, ElementSpec]),
    ]
end

"""
    example_script_path(example) -> String

Absolute path of an [`example_catalog`](@ref) entry's script, resolved against
the package root. Throws if the script is missing, so a catalogue entry that
has been renamed or deleted cannot go unnoticed.
"""
function example_script_path(example::AbstractExample)
    root = normpath(joinpath(@__DIR__, "..", ".."))
    path = joinpath(root, example.title)
    isfile(path) || throw(ArgumentError(
        "example catalogue entry $(repr(example.title)) names a script that " *
        "does not exist at $(path); the catalogue in src/examples/Examples.jl " *
        "has fallen behind the repository"))
    return path
end

# `description` methods for these three types live in `src/registry/Registry.jl`
# beside every other object's, and are not repeated here.
