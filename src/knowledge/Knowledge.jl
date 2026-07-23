export AbstractOctopusObject,
       AbstractElementSpec, AbstractTrackingMethod, AbstractExecutionPolicy,
       AbstractContract, AbstractPhysicsContract, AbstractImplementationContract,
       AbstractBackendConsistencyContract, AbstractAnalysis, AbstractExample, AbstractTask,
       name, physics_keywords, supported_tracking_methods, tracking_method,
       supported_analyses,
       required_contracts, runtime_type, description, compile_runtime,
       ElementSpec, kind, params, param, getparam, hasparam,
       ParamMeta, ElementMeta, element_meta, register_element_meta!, @element_spec,
       register_element_spec!, registered_element_specs,
       parameter_schema, example_spec, construction_help, element_help,
       validate_element_metadata, allowed_physics_keywords

"""Root type for structured, introspectable architectural objects in Octopus."""
abstract type AbstractOctopusObject end

"""
    AbstractElementSpec

Structured description of a physics element. Element specs carry physics
meaning, supported tracking methods, analyses, validation contracts, and
metadata that can be inspected by humans, scripts, and AI agents. They are not
runtime tracking objects.
"""
abstract type AbstractElementSpec <: AbstractOctopusObject end

"""
    ElementSpec{Kind}(params)
    ElementSpec{Kind}(; kwargs...)

Flexible user- and agent-facing element specification. `Kind` identifies the
physics element category, while `params::Dict{Symbol,Any}` stores required and
optional descriptive fields such as strengths, aperture, alignment, errors, and
metadata.

Runtime tracking structs should extract only the execution data they need from
an `ElementSpec`; they should not carry arbitrary dictionaries.

Use friendly constructors such as `ThinCrabCavitySpec(...)` for normal user
code. Query `element_help(...)`, `parameter_schema(...)`, `example_spec(...)`,
and `construction_help(...)` when constructing an unfamiliar element kind.
"""
struct ElementSpec{Kind} <: AbstractElementSpec
    params::Dict{Symbol,Any}
end

ElementSpec{Kind}(; kwargs...) where {Kind} =
    ElementSpec{Kind}(Dict{Symbol,Any}(Symbol(k) => v for (k, v) in pairs(kwargs)))

"""
    ParamMeta(; required=false, unit="", default=nothing, meaning="")

Declarative metadata for one element-construction parameter.
"""
struct ParamMeta
    required::Bool
    unit::String
    default::Any
    meaning::String
end
ParamMeta(; required::Bool=false, unit="", default=nothing, meaning="") =
    ParamMeta(required, String(unit), default, String(meaning))

"""
    ElementMeta(; kind, spec_type, friendly_constructor, runtime_type, runtime_types,
                 description, keywords, tracking_methods, contracts, analyses,
                 parameters, example, construction_help)

Single declarative metadata record for an element kind. Human-maintained
element metadata should live in one `ElementMeta` declaration, usually through
the `@element_spec` macro.
"""
struct ElementMeta
    kind::Symbol
    spec_type::Any
    friendly_constructor::Any
    runtime_type::Any
    runtime_types::Dict{DataType,Any}
    description::String
    keywords::Vector{Symbol}
    tracking_methods::Vector{DataType}
    contracts::Vector{DataType}
    analyses::Vector{DataType}
    parameters::NamedTuple
    example::Any
    construction_help::String
end

function ElementMeta(; kind::Symbol, spec_type, friendly_constructor=nothing,
                     runtime_type=nothing, runtime_types=nothing,
                     description="", keywords=Symbol[],
                     tracking_methods=DataType[], contracts=DataType[], analyses=DataType[],
                     parameters=NamedTuple(), example=nothing,
                     construction_help="")
    method_vec = DataType[tracking_methods...]
    runtime_map = _runtime_types_dict(runtime_type, runtime_types, method_vec)
    return ElementMeta(
        kind,
        spec_type,
        friendly_constructor,
        runtime_type,
        runtime_map,
        String(description),
        Symbol[keywords...],
        method_vec,
        DataType[contracts...],
        DataType[analyses...],
        parameters,
        example,
        String(construction_help),
    )
end

function _runtime_types_dict(runtime_type, runtime_types, methods::Vector{DataType})
    if runtime_types !== nothing
        return Dict{DataType,Any}(k => v for (k, v) in pairs(runtime_types))
    end
    runtime_type === nothing && return Dict{DataType,Any}()
    return Dict{DataType,Any}(method => runtime_type for method in methods)
end

const REGISTERED_ELEMENT_SPECS = Any[]
const ELEMENT_META_BY_SPEC_TYPE = IdDict{Any,ElementMeta}()
const ELEMENT_META_BY_FRIENDLY_TYPE = IdDict{Any,ElementMeta}()
const ELEMENT_META_BY_KIND = Dict{Symbol,ElementMeta}()
const ALLOWED_PHYSICS_KEYWORDS = Set{Symbol}([
    :crab_dispersion,
    :momentum_dispersion,
    :xy_coupling,
    :thin_element,
    :crab_cavity,
    :harmonic,
    :lorentz_boost,
    :reverse_lorentz_boost,
    :coordinate_transform,
    :quasi_symplectic,
    :radiation,
    :beam_beam,
    :nonlinear_interaction,
])

"""Return the current controlled physics-keyword set."""
allowed_physics_keywords() = copy(ALLOWED_PHYSICS_KEYWORDS)

"""Register an `ElementSpec{Kind}` type for reflection-generated registries."""
function register_element_spec!(T)
    T in REGISTERED_ELEMENT_SPECS || push!(REGISTERED_ELEMENT_SPECS, T)
    return T
end

"""Return registered concrete `ElementSpec{Kind}` types."""
registered_element_specs() = copy(REGISTERED_ELEMENT_SPECS)

"""
    register_element_meta!(meta)

Register declarative metadata for an element kind and add its `spec_type` to
the element registry.
"""
function register_element_meta!(meta::ElementMeta)
    register_element_spec!(meta.spec_type)
    ELEMENT_META_BY_SPEC_TYPE[meta.spec_type] = meta
    meta.friendly_constructor === nothing ||
        (ELEMENT_META_BY_FRIENDLY_TYPE[meta.friendly_constructor] = meta)
    ELEMENT_META_BY_KIND[meta.kind] = meta
    return meta
end

"""
    @element_spec begin
        kind = :my_element
        spec_type = ElementSpec{:my_element}
        friendly_constructor = MyElementSpec
        runtime_type = MyElement
        ...
    end

Register one declarative metadata block for an element kind. Use `runtime_type`
for one supported tracking method, or `runtime_types` for a per-method runtime
mapping when one accelerator element type supports multiple tracking methods.

Minimal pattern for a new accelerator element type:

```julia
abstract type MyElementSpec{T} end

MyElementSpec(; strength, tracking_method=Symplectic6DMap(), kwargs...) =
    MyElementSpec{Float64}(; strength, tracking_method, kwargs...)

function (::Type{MyElementSpec{T}})(; strength,
                                    tracking_method=Symplectic6DMap(),
                                    kwargs...) where {T}
    return ElementSpec{:my_element}(
        _spec_params(; strength=T(strength),
                     tracking_method=tracking_method,
                     kwargs...)
    )
end

struct MyElement{M<:AbstractTrackingMethod,T<:AbstractFloat} <: AbstractTrackOp
    method::M
    strength::T
end

MyElement(spec::ElementSpec{:my_element},
          method::AbstractTrackingMethod=tracking_method(spec)) =
    MyElement(method, param(spec, :strength))

@element_spec begin
    kind = :my_element
    spec_type = ElementSpec{:my_element}
    friendly_constructor = MyElementSpec
    runtime_type = MyElement
    description = "Short physics description."
    keywords = [:my_element]
    tracking_methods = [Symplectic6DMap]
    contracts = DataType[]
    analyses = [PlaceholderAnalysis]
    parameters = (
        strength=ParamMeta(required=true, meaning="element strength"),
        tracking_method=ParamMeta(default=Symplectic6DMap(),
                                  meaning="per-element tracking method"),
    )
    example = MyElementSpec(strength=0.1)
    construction_help = "Friendly constructor: MyElementSpec(; strength, tracking_method=Symplectic6DMap(), kwargs...)."
end
```

Validation checklist:

- keep specs in `src/elements/` and generic tracking infrastructure in
  `src/track/`;
- keep descriptive fields in `ElementSpec{kind}` and execution-only fields in
  compact runtime structs;
- use `friendly_constructor`, not `friendly`;
- use `DataType[]` for contracts until real validation implementations exist;
- use `PlaceholderAnalysis` until real analysis implementations exist;
- run `validate_element_metadata()`;
- run `element_help(MyElementSpec)` and `element_help(:my_element)`;
- smoke-test execution through `TrackingTask`.
"""
macro element_spec(block)
    assignments = block isa Expr && block.head == :block ? block.args : Any[block]
    kwargs = Any[]
    for item in assignments
        item isa LineNumberNode && continue
        if item isa Expr && item.head == :(=) && item.args[1] isa Symbol
            push!(kwargs, Expr(:kw, item.args[1], esc(item.args[2])))
        end
    end
    return :(register_element_meta!(ElementMeta(; $(kwargs...))))
end

"""Return declarative metadata for an element query."""
function element_meta(query)
    meta = _element_meta_or_nothing(query)
    meta === nothing && throw(ArgumentError("no ElementMeta registered for $query"))
    return meta
end

function _element_meta_or_nothing(spec::AbstractElementSpec)
    return _element_meta_or_nothing(typeof(spec))
end

function _element_meta_or_nothing(kind::Symbol)
    return get(ELEMENT_META_BY_KIND, kind, nothing)
end

function _element_meta_or_nothing(T::Type)
    meta = get(ELEMENT_META_BY_SPEC_TYPE, T, nothing)
    meta !== nothing && return meta
    meta = get(ELEMENT_META_BY_FRIENDLY_TYPE, T, nothing)
    meta !== nothing && return meta

    for (friendly, candidate) in ELEMENT_META_BY_FRIENDLY_TYPE
        try
            T <: friendly && return candidate
        catch
        end
    end
    return nothing
end

"""Numerical algorithm used to propagate phase-space coordinates."""
abstract type AbstractTrackingMethod <: AbstractOctopusObject end

"""Numerical execution decisions such as slicing, threading, GPU, or MPI."""
abstract type AbstractExecutionPolicy <: AbstractOctopusObject end

"""Executable validation rule for a scientific-software implementation."""
abstract type AbstractContract <: AbstractOctopusObject end

"""Contract that validates physical correctness or a physics-level invariant."""
abstract type AbstractPhysicsContract <: AbstractContract end

"""Contract that validates a numerical or runtime implementation property."""
abstract type AbstractImplementationContract <: AbstractContract end

"""Implementation contract comparing results across execution backends."""
abstract type AbstractBackendConsistencyContract <: AbstractImplementationContract end

"""Post-processing or accelerator-physics analysis."""
abstract type AbstractAnalysis <: AbstractOctopusObject end

"""Curated precedent that AI agents may imitate."""
abstract type AbstractExample <: AbstractOctopusObject end

"""Complete workflow tying specs, tracking methods, policies, contracts, and analyses."""
abstract type AbstractTask <: AbstractOctopusObject end

"""
    name(T::Type{<:AbstractOctopusObject})
    name(x::AbstractOctopusObject)

Return the registry-facing symbolic name for an Octopus architectural type or
instance. This is intended for summaries, generated registries, and agent
queries.
"""
name(::Type{T}) where {T<:AbstractOctopusObject} = nameof(T)
name(x::AbstractOctopusObject) = name(typeof(x))
name(::Type{ElementSpec{Kind}}) where {Kind} = Kind
name(x::ElementSpec) = kind(x)

"""Return the element kind symbol for `ElementSpec{Kind}`."""
kind(::Type{ElementSpec{Kind}}) where {Kind} = Kind
kind(x::ElementSpec) = kind(typeof(x))

"""Return the flexible parameter dictionary stored by an `ElementSpec`."""
params(spec::ElementSpec) = spec.params

"""Return a required parameter from an `ElementSpec`, throwing if absent."""
param(spec::ElementSpec, key::Symbol) = spec.params[key]

"""Return an optional parameter from an `ElementSpec`."""
getparam(spec::ElementSpec, key::Symbol, default=nothing) = get(spec.params, key, default)

"""Return whether an `ElementSpec` contains a parameter key."""
hasparam(spec::ElementSpec, key::Symbol) = haskey(spec.params, key)

"""
    description(T::Type{<:AbstractOctopusObject})
    description(x::AbstractOctopusObject)

Return a short description for humans, scripts, and agents that inspect the
registry. Concrete specs, tracking methods, policies, contracts, and analyses
should extend this method.
"""
function description(T::Type{<:AbstractOctopusObject})
    meta = _element_meta_or_nothing(T)
    return meta === nothing ? "" : meta.description
end
description(x::AbstractOctopusObject) = description(typeof(x))
function description(T::Type)
    meta = _element_meta_or_nothing(T)
    return meta === nothing ? "" : meta.description
end

"""
    physics_keywords(spec)

Return symbolic physics tags for an element spec. Agents use these tags to
locate related implementations and examples.
"""
function physics_keywords(T::Type{<:AbstractElementSpec})
    meta = _element_meta_or_nothing(T)
    return meta === nothing ? Symbol[] : meta.keywords
end
physics_keywords(x::AbstractElementSpec) = physics_keywords(typeof(x))
function physics_keywords(T::Type)
    meta = _element_meta_or_nothing(T)
    return meta === nothing ? Symbol[] : meta.keywords
end

"""
    supported_tracking_methods(spec)

Return tracking method types supported by an element spec. Element specs should
extend this to advertise valid numerical algorithms.
"""
function supported_tracking_methods(T::Type{<:AbstractElementSpec})
    meta = _element_meta_or_nothing(T)
    return meta === nothing ? Type{<:AbstractTrackingMethod}[] : meta.tracking_methods
end
supported_tracking_methods(x::AbstractElementSpec) = supported_tracking_methods(typeof(x))
function supported_tracking_methods(T::Type)
    meta = _element_meta_or_nothing(T)
    return meta === nothing ? Type{<:AbstractTrackingMethod}[] : meta.tracking_methods
end

"""
    supported_analyses(spec)

Return analysis types that are meaningful for an element spec.
"""
function supported_analyses(T::Type{<:AbstractElementSpec})
    meta = _element_meta_or_nothing(T)
    return meta === nothing ? Type{<:AbstractAnalysis}[] : meta.analyses
end
supported_analyses(x::AbstractElementSpec) = supported_analyses(typeof(x))
function supported_analyses(T::Type)
    meta = _element_meta_or_nothing(T)
    return meta === nothing ? Type{<:AbstractAnalysis}[] : meta.analyses
end

"""
    required_contracts(spec)

Return contract types that should validate an implementation of the
given element spec.
"""
function required_contracts(T::Type{<:AbstractElementSpec})
    meta = _element_meta_or_nothing(T)
    return meta === nothing ? Type{<:AbstractContract}[] : meta.contracts
end
required_contracts(x::AbstractElementSpec) = required_contracts(typeof(x))
function required_contracts(T::Type)
    meta = _element_meta_or_nothing(T)
    return meta === nothing ? Type{<:AbstractContract}[] : meta.contracts
end

"""
    parameter_schema(spec_type)
    parameter_schema(spec)

Return structured construction metadata for an element spec. Concrete
`ElementSpec{Kind}` implementations should define required keys, optional keys,
units, defaults, and meanings.
"""
function parameter_schema(T::Type{<:AbstractElementSpec})
    meta = _element_meta_or_nothing(T)
    return meta === nothing ? NamedTuple() : meta.parameters
end
parameter_schema(x::AbstractElementSpec) = parameter_schema(typeof(x))
function parameter_schema(T::Type)
    meta = _element_meta_or_nothing(T)
    return meta === nothing ? NamedTuple() : meta.parameters
end

"""
    example_spec(spec_type)
    example_spec(spec)

Return a small working example spec for a concrete element kind.
"""
function example_spec(T::Type{<:AbstractElementSpec})
    meta = _element_meta_or_nothing(T)
    return meta === nothing ? nothing : meta.example
end
example_spec(x::AbstractElementSpec) = example_spec(typeof(x))
function example_spec(T::Type)
    meta = _element_meta_or_nothing(T)
    return meta === nothing ? nothing : meta.example
end

"""
    construction_help(spec_type)
    construction_help(spec)

Return concise human-readable guidance for constructing a concrete element
spec.
"""
function construction_help(T::Type{<:AbstractElementSpec})
    meta = _element_meta_or_nothing(T)
    return meta === nothing ? "" : meta.construction_help
end
construction_help(x::AbstractElementSpec) = construction_help(typeof(x))
function construction_help(T::Type)
    meta = _element_meta_or_nothing(T)
    return meta === nothing ? "" : meta.construction_help
end

"""
    element_help()
    element_help(query; io=stdout)

Print a compact construction and metadata guide for an element kind. `query`
may be a kind symbol such as `:lorentz_boost`, an `ElementSpec{kind}` type, a
friendly constructor name such as `LorentzBoostSpec`, or an existing
`ElementSpec` instance.

Use this when you do not remember the lower-level metadata query functions.
The displayed information is generated from `parameter_schema`,
`example_spec`, `construction_help`, `physics_keywords`, `supported_tracking_methods`,
`required_contracts`, and `supported_analyses`.
"""
function element_help(; io::IO=stdout)
    println(io, "Available element specs:")
    for T in registered_element_specs()
        println(io, "  - ", name(T))
    end
    println(io)
    println(io, "Use element_help(:kind), element_help(FriendlySpecName), or element_help(spec).")
    println(io, "Useful lower-level queries: parameter_schema, example_spec, construction_help, kind, params.")
    return nothing
end

element_help(io::IO) = element_help(; io=io)
element_help(io::IO, query) = element_help(query; io=io)

function element_help(query; io::IO=stdout)
    T = _element_help_target(query)
    example = example_spec(T)
    label = _element_help_label(T)
    kind_label = _element_help_kind_label(T, example)

    println(io, "Element kind: :", kind_label)
    desc = description(T)
    isempty(desc) || println(io, "Description: ", desc)
    label == string(T) || println(io, "Friendly query: ", label)
    println(io, "Spec type: ", T)
    println(io, "Construction:")
    help = construction_help(T)
    println(io, isempty(help) ? "  No construction_help is registered." : _indent_lines(help, "  "))

    schema = parameter_schema(T)
    println(io, "Parameters:")
    if isempty(keys(schema))
        println(io, "  No parameter_schema is registered.")
    else
        for (key, meta) in pairs(schema)
            println(io, "  - ", key, _schema_meta_suffix(meta))
        end
    end

    println(io, "Example:")
    if example === nothing
        println(io, "  No example_spec is registered.")
    else
        println(io, "  ", _example_spec_string(T, example))
        println(io, "  example type: ", typeof(example))
    end

    println(io, "Physics keywords: ", physics_keywords(T))
    println(io, "Supported tracking methods: ", _type_list_string(supported_tracking_methods(T)))
    println(io, "Required contracts: ", _type_list_string(required_contracts(T)))
    println(io, "Supported analyses: ", _type_list_string(supported_analyses(T)))
    println(io, "Related queries:")
    println(io, "  parameter_schema(", label, ")")
    println(io, "  example_spec(", label, ")")
    println(io, "  construction_help(", label, ")")
    return nothing
end

_element_help_target(spec::AbstractElementSpec) = typeof(spec)
_element_help_target(T::Type) = T
function _element_help_target(kind::Symbol)
    for T in registered_element_specs()
        name(T) == kind && return T
    end
    throw(ArgumentError("unknown element kind: $kind"))
end

_element_help_label(::Type{ElementSpec{Kind}}) where {Kind} = _raw_spec_type_string(ElementSpec{Kind})
_element_help_label(T::Type) = string(nameof(T))

function _element_help_kind_label(::Type{ElementSpec{Kind}}, example) where {Kind}
    return string(Kind)
end
function _element_help_kind_label(T::Type, example)
    example isa ElementSpec && return string(kind(example))
    return string(nameof(T))
end

_raw_spec_type_string(::Type{ElementSpec{Kind}}) where {Kind} =
    "ElementSpec{:" * string(Kind) * "}"
_raw_spec_type_string(T::Type) = string(T)

function _example_spec_string(T::Type, spec::ElementSpec)
    return _raw_spec_type_string(typeof(spec)) * "(; " * _spec_kwargs_string(T, spec) * ")"
end
_example_spec_string(::Type, example) = repr(example)

function _spec_kwargs_string(T::Type, spec::ElementSpec)
    schema = parameter_schema(T)
    ordered_keys = Symbol[]
    append!(ordered_keys, collect(keys(schema)))
    extras = sort!(setdiff(collect(keys(params(spec))), ordered_keys))
    append!(ordered_keys, extras)
    present_keys = filter(k -> hasparam(spec, k) && !_omit_example_key(schema, k, param(spec, k)), ordered_keys)
    return join(("$(k)=" * _example_value_string(param(spec, k)) for k in present_keys), ", ")
end

_example_value_string(value) = repr(value)
_example_value_string(value::ElementSpec) =
    _raw_spec_type_string(typeof(value)) * "(; " * _spec_kwargs_string(typeof(value), value) * ")"

function _omit_example_key(schema, key::Symbol, value)
    haskey(schema, key) || return false
    meta = schema[key]
    meta isa ParamMeta || return false
    meta.required && return false
    value === nothing && return true
    meta.default === nothing && return false
    try
        return value == meta.default
    catch
        return false
    end
end

function _schema_meta_suffix(meta)
    meta isa ParamMeta && return _schema_meta_suffix_param(meta)
    parts = String[]
    haskey(meta, :required) && push!(parts, meta.required ? "required" : "optional")
    haskey(meta, :unit) && !isempty(string(meta.unit)) && push!(parts, "unit=$(meta.unit)")
    haskey(meta, :default) && meta.default !== nothing && push!(parts, "default=$(meta.default)")
    haskey(meta, :meaning) && !isempty(string(meta.meaning)) && push!(parts, string(meta.meaning))
    return isempty(parts) ? "" : " (" * join(parts, "; ") * ")"
end

function _schema_meta_suffix_param(meta::ParamMeta)
    parts = String[]
    push!(parts, meta.required ? "required" : "optional")
    !isempty(meta.unit) && push!(parts, "unit=$(meta.unit)")
    meta.default !== nothing && push!(parts, "default=$(meta.default)")
    !isempty(meta.meaning) && push!(parts, meta.meaning)
    return " (" * join(parts, "; ") * ")"
end

function _type_list_string(types)
    isempty(types) && return "[]"
    return "[" * join(string.(nameof.(types)), ", ") * "]"
end

function _indent_lines(text::AbstractString, prefix::AbstractString)
    return join((prefix * line for line in split(text, '\n')), "\n")
end

"""
    validate_element_metadata(; throw_on_error=false)

Validate the registered element metadata table. This is intended for CI,
notebooks, and agent self-checks after adding or editing an element.

Checks include:

- every registered spec has exactly one `ElementMeta`
- every required parameter appears in `example_spec`
- no parameter is both required and given a default
- every declared tracking method resolves to a runtime type
- friendly constructor metadata agrees with the raw `ElementSpec{kind}` type
"""
function validate_element_metadata(; throw_on_error::Bool=false)
    errors = String[]
    seen_kinds = Set{Symbol}()

    for T in registered_element_specs()
        meta = _element_meta_or_nothing(T)
        if meta === nothing
            push!(errors, "missing ElementMeta for registered spec $(T)")
            continue
        end

        meta.kind in seen_kinds && push!(errors, "duplicate ElementMeta kind $(meta.kind)")
        push!(seen_kinds, meta.kind)
        meta.spec_type === T || push!(errors, "ElementMeta $(meta.kind) spec_type does not match registry entry")

        example = example_spec(T)
        example isa ElementSpec || push!(errors, "ElementMeta $(meta.kind) example is not an ElementSpec")
        if example isa ElementSpec && kind(example) != meta.kind
            push!(errors, "ElementMeta $(meta.kind) example kind is $(kind(example))")
        end

        for keyword in meta.keywords
            keyword in ALLOWED_PHYSICS_KEYWORDS ||
                push!(errors, "ElementMeta $(meta.kind) has unapproved physics keyword $(keyword)")
        end

        for (key, pmeta) in pairs(parameter_schema(T))
            if pmeta isa ParamMeta
                if pmeta.required && pmeta.default !== nothing
                    push!(errors, "ElementMeta $(meta.kind) parameter $(key) is required but has a default")
                end
                if pmeta.required && example isa ElementSpec && !hasparam(example, key)
                    push!(errors, "ElementMeta $(meta.kind) example is missing required parameter $(key)")
                end
                occursin(string(key), construction_help(T)) ||
                    push!(errors, "ElementMeta $(meta.kind) construction_help does not mention parameter $(key)")
            end
        end

        if example isa ElementSpec
            schema_keys = Set(keys(parameter_schema(T)))
            for key in keys(params(example))
                key in schema_keys ||
                    push!(errors, "ElementMeta $(meta.kind) example contains undeclared parameter $(key)")
            end
        end

        for tracking_method in supported_tracking_methods(T)
            tracking_method in meta.tracking_methods ||
                push!(errors, "ElementMeta $(meta.kind) tracking method $(nameof(tracking_method)) is not registered in metadata")
            haskey(meta.runtime_types, tracking_method) ||
                push!(errors, "ElementMeta $(meta.kind) has no runtime type for $(nameof(tracking_method))")
        end

        friendly = meta.friendly_constructor
        if friendly !== nothing
            raw_schema = parameter_schema(T)
            friendly_schema = parameter_schema(friendly)
            raw_schema == friendly_schema ||
                push!(errors, "ElementMeta $(meta.kind) friendly_constructor schema disagrees with raw spec")
            construction_help(T) == construction_help(friendly) ||
                push!(errors, "ElementMeta $(meta.kind) friendly_constructor construction_help disagrees with raw spec")
            friendly_example = example_spec(friendly)
            if friendly_example isa ElementSpec && example isa ElementSpec
                kind(friendly_example) == kind(example) ||
                    push!(errors, "ElementMeta $(meta.kind) friendly_constructor example kind disagrees with raw spec")
            else
                push!(errors, "ElementMeta $(meta.kind) friendly_constructor example is not an ElementSpec")
            end
        end
    end

    result = (passed=isempty(errors), errors=errors)
    if throw_on_error && !result.passed
        throw(ArgumentError("element metadata validation failed:\n" * join(errors, "\n")))
    end
    return result
end

"""
    tracking_method(spec)

Return the tracking method selected by an element spec. `ElementSpec` values
may carry `:tracking_method` in their flexible parameter dictionary; otherwise
the element's `default_method` is used.
"""
tracking_method(spec::AbstractElementSpec) = _tracking_method_object(default_method(spec))
tracking_method(spec::ElementSpec) =
    _tracking_method_object(getparam(spec, :tracking_method, default_method(spec)))

_tracking_method_type(::Type{M}) where {M<:AbstractTrackingMethod} = M
_tracking_method_type(method::AbstractTrackingMethod) = typeof(method)
_tracking_method_object(::Type{M}) where {M<:AbstractTrackingMethod} = M()
_tracking_method_object(method::AbstractTrackingMethod) = method

"""
    runtime_type(spec_type, tracking_method)
    runtime_type(spec, tracking_method)

Return the concrete runtime tracking type produced for an element spec under a
tracking method. Execution policies select where a compiled runtime object is
tracked; they should not change the runtime type unless a future method
explicitly models that as metadata.
"""
function runtime_type(T::Type{<:AbstractElementSpec}, method::Type{<:AbstractTrackingMethod})
    meta = _element_meta_or_nothing(T)
    meta === nothing && return nothing
    return get(meta.runtime_types, method, nothing)
end
runtime_type(T::Type{<:AbstractElementSpec}, method::AbstractTrackingMethod) =
    runtime_type(T, typeof(method))
runtime_type(spec::AbstractElementSpec, method) =
    runtime_type(typeof(spec), method)
function runtime_type(T::Type, method::Type{<:AbstractTrackingMethod})
    meta = _element_meta_or_nothing(T)
    meta === nothing && return nothing
    return get(meta.runtime_types, method, nothing)
end
runtime_type(T::Type, method::AbstractTrackingMethod) = runtime_type(T, typeof(method))

"""
    compile_runtime(spec)
    compile_runtime(spec, tracking_method)

Compile an `AbstractElementSpec` into the compact runtime object used by
tracking kernels. The target type is resolved through `runtime_type` and must
provide a constructor of the form `RuntimeType(spec, tracking_method)`.
"""
compile_runtime(spec::AbstractElementSpec) = compile_runtime(spec, tracking_method(spec))

function compile_runtime(spec::AbstractElementSpec, method)
    method_object = _tracking_method_object(method)
    T = runtime_type(spec, method_object)
    T === nothing && throw(MethodError(compile_runtime, (spec, method)))
    return T(spec, method_object)
end
