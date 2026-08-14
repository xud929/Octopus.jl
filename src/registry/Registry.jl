export OctopusRegistry, build_registry, summarize_registry,
       registry_snapshot_markdown, write_registry_snapshot

using InteractiveUtils: subtypes

"""
    OctopusRegistry

Reflection-generated registry of architectural types currently loaded in the
Octopus module. The type lists are derived from Julia's type graph rather than
edited as external metadata; three short index sections of the generated
snapshot -- Task Diagnostics, Knob Control, and the Runtime Objects preamble --
are maintained by hand inside `registry_snapshot_markdown`, because they index
macros and workflows that are not types (audit part 7, K7 corrected the
previous claim that everything here was derived).
"""
struct OctopusRegistry
    elements::Vector{Any}
    tracking_methods::Vector{Any}
    solvers::Vector{Any}
    policies::Vector{Any}
    contracts::Vector{Any}
    analyses::Vector{Any}
    examples::Vector{Any}
    tasks::Vector{Any}
end

function _subtypes_recursive(T)
    out = Any[]
    for S in subtypes(T)
        push!(out, S)
        append!(out, _subtypes_recursive(S))
    end
    return unique(out)
end

"""
    build_registry()

Discover loaded Octopus architectural types. Element specs come from
`register_element_spec!`; tracking methods, policies, contracts, analyses,
examples, and tasks are discovered by recursively walking their abstract type
trees.
"""
function build_registry()
    return OctopusRegistry(
        registered_element_specs(),
        _subtypes_recursive(AbstractTrackingMethod),
        _subtypes_recursive(AbstractPoissonSolver),
        _subtypes_recursive(AbstractExecutionPolicy),
        _subtypes_recursive(AbstractContract),
        _subtypes_recursive(AbstractAnalysis),
        _subtypes_recursive(AbstractExample),
        _subtypes_recursive(AbstractTask),
    )
end

"""
    summarize_registry([registry])

Return a compact named tuple of symbolic type names from an `OctopusRegistry`.
This is useful for notebooks, diagnostics, and AI-agent orientation.
"""
function summarize_registry(reg::OctopusRegistry=build_registry())
    return (
        elements = name.(reg.elements),
        tracking_methods = name.(reg.tracking_methods),
        solvers = name.(reg.solvers),
        policies = name.(reg.policies),
        contracts = name.(reg.contracts),
        analyses = name.(reg.analyses),
        examples = name.(reg.examples),
        tasks = name.(reg.tasks),
    )
end

"""
    registry_snapshot_markdown([registry])

Generate the Markdown content for `docs/registry_snapshot.md` from the live
registry and `ElementMeta` table.
"""
function registry_snapshot_markdown(reg::OctopusRegistry=build_registry())
    io = IOBuffer()
    println(io, "# Octopus Registry Snapshot")
    println(io)
    println(io, "This file is generated from the live Octopus registry and element metadata.")
    println(io)
    println(io, "Regenerate it from the project root with:")
    println(io)
    println(io, "```julia")
    println(io, "include(\"src/Octopus.jl\")")
    println(io, "using .Octopus")
    println(io, "write_registry_snapshot()")
    println(io, "```")
    println(io)
    println(io, "Element specs are registered as flexible `ElementSpec{kind}` types. Friendly")
    println(io, "constructor names remain the user-facing way to build those specs.")
    println(io)

    println(io, "## Element Specs")
    println(io)
    for T in reg.elements
        meta = element_meta(T)
        # `friendly_constructor = nothing` is explicitly permitted by
        # ElementMeta; the snapshot must report it, not crash on `nameof`
        # (audit part 7, K6).
        friendly = meta.friendly_constructor === nothing ?
            "(no friendly constructor)" : "`" * string(nameof(meta.friendly_constructor)) * "`"
        println(io, "- `", _type_string(meta.spec_type), "` via ", friendly)
        println(io, "  - Physics keywords: ", _markdown_type_list(meta.keywords; symbol=true))
        println(io, "  - Supported tracking methods: ", _markdown_type_list(meta.tracking_methods))
        println(io, "  - Required contracts: ", _markdown_type_list(meta.contracts))
        println(io, "  - Supported analyses: ", _markdown_type_list(meta.analyses))
        println(io, "  - Runtime mappings: ", _runtime_mapping_string(meta))
        println(io, "  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`")
        println(io)
    end

    _write_type_section(io, "Tracking Methods", reg.tracking_methods)
    println(io, "## Strong-Strong Solvers")
    println(io)
    for T in reg.solvers
        println(io, "- `", nameof(T), "`")
        isempty(keys(solver_option_schema(T))) ||
            println(io, "  - Construction metadata: `solver_option_schema`, `solver_help`")
    end
    println(io)
    _write_type_section(io, "Execution Policies", reg.policies)
    _write_type_section(io, "Contracts", reg.contracts)
    _write_type_section(io, "Analyses", reg.analyses)
    _write_type_section(io, "Examples", reg.examples)
    _write_type_section(io, "Tasks", reg.tasks)

    println(io, "## Task Diagnostics")
    println(io)
    println(io, "- `StrongStrongDiagnostics`")
    println(io, "  - Construction metadata: `diagnostics_option_schema`, `diagnostics_help`")
    println(io)

    println(io, "## Knob Control")
    println(io)
    println(io, "- `@knob`, `@knob_expr`, `knobs`/`KnobNamespace` (plain-assignment access),")
    println(io, "  `set_knob!`, `knob_value` (deferred parameter expressions stored as")
    println(io, "  data; see `docs/knob_control.md`)")
    println(io, "  - Introspection: `list_knobs`, `knob_report`, `knob_dependencies`,")
    println(io, "    `knob_dependents`")
    println(io, "  - Symbolic layer: `knob_derivative`, `knob_to_expr`/`knob_expression`,")
    println(io, "    `knob_symbolic`/`knob_from_symbolic` (optional Symbolics.jl adapter;")
    println(io, "    `knob_symbolics_available` reports whether it is active)")
    println(io, "  - Element binding: construction-time (`param=@knob_expr(...)`) or")
    println(io, "    post-construction (`spec.param = @knob_expr(...)`)")
    println(io, "  - Runtime consumer: `compile_runtime` via `resolve_knobs`; verified by")
    println(io, "    `KnobEffectivenessContract`")
    println(io)

    println(io, "## Runtime Objects")
    println(io)
    println(io, "Runtime element objects live under `src/elements/`. Generic tracking helpers")
    println(io, "live under `src/track/`.")
    println(io)
    for T in _runtime_object_types(reg)
        println(io, "- `", nameof(T), "`")
    end

    return String(take!(io))
end

"""
    write_registry_snapshot(path=\"docs/registry_snapshot.md\")

Write `registry_snapshot_markdown()` to `path`.
"""
function write_registry_snapshot(path::AbstractString="docs/registry_snapshot.md")
    open(path, "w") do io
        write(io, registry_snapshot_markdown())
    end
    return path
end

function _write_type_section(io, title, types)
    println(io, "## ", title)
    println(io)
    for T in types
        println(io, "- `", nameof(T), "`")
    end
    println(io)
end

function _markdown_type_list(values; symbol=false)
    isempty(values) && return "`[]`"
    if symbol
        return join(("`:" * string(v) * "`" for v in values), ", ")
    end
    return join(("`" * string(nameof(v)) * "`" for v in values), ", ")
end

function _runtime_mapping_string(meta)
    isempty(meta.runtime_types) && return "`[]`"
    pairs = String[]
    for method in meta.tracking_methods
        haskey(meta.runtime_types, method) || continue
        push!(pairs, "`$(nameof(method)) => $(nameof(meta.runtime_types[method]))`")
    end
    return join(pairs, ", ")
end

_type_string(::Type{ElementSpec{Kind}}) where {Kind} = "ElementSpec{:" * string(Kind) * "}"
_type_string(T::Type) = string(T)

function _runtime_object_types(reg::OctopusRegistry)
    out = Any[]
    for T in reg.elements
        meta = element_meta(T)
        append!(out, values(meta.runtime_types))
    end
    # Hand-appended, deliberately: these are runtime objects with no owning
    # element meta. BeamParams/Phase6DRep/Beam are the beam layer; the three
    # wrappers are what any misaligned/rolled/kept-whole placement compiles
    # THROUGH, and were missing from the snapshot entirely (2026-08-05
    # audit, U13-6 — the file header once claimed only meta-derived content
    # here).
    append!(out, Any[BeamParams, Phase6DRep, Beam,
                     MisalignedElement, RefTilted, CompositeLine])
    return unique(out)
end

# ---------------------------------------------------------------------------
# Registry self-description
# ---------------------------------------------------------------------------
#
# `description(T)` falls back to `_element_meta_or_nothing(T)`, which is
# `nothing` for every non-element type, and then returns "". Fifteen of the 35
# types the registry publishes described themselves to any agent that asked as
# the empty string -- including all four Poisson solvers, both flagship task
# types and all three example categories -- while `description`'s own docstring
# says these types "should extend this method" (2026-08-05_b audit, U12-17).
# There was no tripwire, in contrast with the 336/336 export-docstring one.

description(::Type{TrackingTask}) =
    "Single-beam tracking task: a compiled line, a hook schedule and an execution policy, executed for a number of turns."
description(::Type{StrongStrongTask}) =
    "Two-beam strong-strong task: a pair of lines sharing collision points, whose beams act on each other through a Poisson solver."

description(::Type{GaussianPoissonSolver}) =
    "Sliced soft-Gaussian strong-strong solver: each slice acts through the analytic Bassetti-Erskine kick of the other beam's fitted Gaussian."
description(::Type{PICPoissonSolver}) =
    "Particle-in-cell strong-strong solver: charge deposited on a transverse mesh, the field from an FFT Green convolution, interpolated back to particles."
description(::Type{GaussianPICPoissonSolver}) =
    "Gaussian-subtracted PIC solver: the analytic Gaussian part is handled exactly and only the residual goes through the mesh, so the grid error is nearly grid-independent."
description(::Type{SpectralPoissonSolver}) =
    "Spectral sine-series strong-strong solver: the potential is expanded in Dirichlet sine modes on a fixed box, in a grid or grid-free variant."

description(::Type{AbstractGPUExecutionPolicy}) =
    "Taxonomy node for GPU execution policies; concrete subtypes carry the device and launch geometry."
description(::Type{AbstractPhysicsContract}) =
    "Contract asserting a physical property of the model, checkable against theory or an external code."
description(::Type{AbstractImplementationContract}) =
    "Contract asserting a property of the implementation rather than of the physics, such as a declared option reaching its consumer."
description(::Type{AbstractBackendConsistencyContract}) =
    "Contract asserting that two execution backends produce the same result for the same input."
description(::Type{ElementParameterEffectivenessContract}) =
    "Checks that every declared element parameter reaches the compiled map, by perturbing one at a time and tracking a probe particle."
description(::Type{PTCConsistencyContract}) =
    "Checks Octopus element maps against a committed MAD-X/PTC reference table."
description(::Type{MADXSurveyConsistencyContract}) =
    "Checks the arc survey (s positions, placement lengths, total length) against a committed MAD-X SURVEY reference, element for element."

description(::Type{BenchmarkExample}) =
    "Example category: a performance measurement with a recorded configuration and reference timing."
description(::Type{ReferenceExample}) =
    "Example category: a canonical usage the documentation and tests refer to."
description(::Type{ResearchStudyExample}) =
    "Example category: an exploratory study, whose numbers are findings rather than gates."

"""
    registry_types_without_description() -> Vector{Tuple{Symbol,Type}}

Every type the registry publishes whose `description` is empty, as
`(section, type)` pairs.

The tripwire behind `description`'s "should extend this method": a type that
joins the registry and does not describe itself is invisible to any agent that
asks the registry what it is, and nothing used to notice (2026-08-05_b audit,
U12-17).
"""
function registry_types_without_description(reg::OctopusRegistry=build_registry())
    out = Tuple{Symbol,Type}[]
    for name in propertynames(reg)
        section = getproperty(reg, name)
        section isa Union{Tuple,AbstractVector} || continue
        for T in section
            T isa Type || continue
            isempty(description(T)) && push!(out, (name, T))
        end
    end
    return out
end

"""
    runtime_object_types_missing_from_snapshot() -> Vector{Type}

Concrete `AbstractTrackOp` subtypes absent from the Runtime Objects section.

`_runtime_object_types` derives most of its content from element metadata and
then hand-appends six types with no owning meta -- a fourth hand-maintained
piece the `OctopusRegistry` docstring did not declare and nothing checked
(2026-08-05_b audit, U12-19). The U13-6 repair fixed that list's *staleness*
and left its *structure*: the next wrapper or beam-scale runtime type still
needs a hand edit, with nothing failing when it is forgotten.

This is the missing comparison. It is a soft list -- it reports rather than
throws -- so the caller decides; the suite asserts it is empty.
"""
function runtime_object_types_missing_from_snapshot(reg::OctopusRegistry=build_registry())
    listed = Set{Any}(_runtime_object_types(reg))
    missing = Any[]
    for T in _subtypes_recursive(AbstractTrackOp)
        isabstracttype(T) && continue
        parentmodule(T) === (@__MODULE__) || continue
        T in listed && continue
        push!(missing, T)
    end
    return sort!(missing; by = t -> string(nameof(t)))
end
