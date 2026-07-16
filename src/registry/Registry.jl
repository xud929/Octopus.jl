export OctopusRegistry, build_registry, summarize_registry,
       registry_snapshot_markdown, write_registry_snapshot

using InteractiveUtils: subtypes

"""
    OctopusRegistry

Reflection-generated registry of architectural types currently loaded in the
Octopus module. The registry is derived from Julia's type graph rather than
edited as external metadata.
"""
struct OctopusRegistry
    elements::Vector{Any}
    tracking_methods::Vector{Any}
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
        _subtypes_recursive(AbstractExecutionPolicy),
        _subtypes_recursive(AbstractPhysicsContract),
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
        println(io, "- `", _type_string(meta.spec_type), "` via `", nameof(meta.friendly_constructor), "`")
        println(io, "  - Physics keywords: ", _markdown_type_list(meta.keywords; symbol=true))
        println(io, "  - Supported tracking methods: ", _markdown_type_list(meta.tracking_methods))
        println(io, "  - Required contracts: ", _markdown_type_list(meta.contracts))
        println(io, "  - Supported analyses: ", _markdown_type_list(meta.analyses))
        println(io, "  - Runtime mappings: ", _runtime_mapping_string(meta))
        println(io, "  - Construction metadata: `parameter_schema`, `example_spec`, `construction_help`")
        println(io)
    end

    _write_type_section(io, "Tracking Methods", reg.tracking_methods)
    _write_type_section(io, "Execution Policies", reg.policies)
    _write_type_section(io, "Physics Contracts", reg.contracts)
    _write_type_section(io, "Analyses", reg.analyses)
    _write_type_section(io, "Examples", reg.examples)
    _write_type_section(io, "Tasks", reg.tasks)

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
    append!(out, Any[BeamParams, Phase6DRep, Beam])
    return unique(out)
end
