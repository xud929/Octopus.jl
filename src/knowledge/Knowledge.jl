export AbstractOctopusObject,
       AbstractElementSpec, AbstractTrackingMethod, AbstractExecutionPolicy,
       AbstractContract, AbstractPhysicsContract, AbstractImplementationContract,
       AbstractBackendConsistencyContract, AbstractAnalysis, AbstractExample, AbstractTask,
       name, physics_keywords, supported_tracking_methods, tracking_method,
       supported_analyses,
       required_contracts, runtime_type, description, compile_runtime,
       ElementSpec, kind, params, param, getparam, hasparam, numeric_type,
       ParamMeta, ElementMeta, element_meta, register_element_meta!, @element_spec,
       register_element_spec!, register_friendly_alias!, registered_element_specs,
       parameter_schema, example_spec, construction_help, element_help,
       validate_element_metadata, allowed_physics_keywords, set_param!

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

Parameters are readable and assignable as properties: `spec.zeta1` reads a
stored parameter, and `spec.zeta1 = value` updates it in place — the natural
way to *bind an existing element to a knob* after construction
(`spec.zeta1 = @knob_expr(HSR.arc_k1)`). Assignments are validated against the
element's parameter schema when one is registered (unknown names are typos,
rejected with the valid list); genuinely new metadata keys go through
`set_param!(spec, :key, value)` — NOT the raw `spec.params[:key] = value`
Dict, which skips the recompile epoch below and leaves an already-built task
tracking stale physics (2026-08-05 audit, U13-2). Placement keys the compile
consumes for every kind (offsets, pitches, tilt, `ref_tilt`,
`misalign_convention`) are always assignable. Every in-place parameter
mutation bumps a global
spec epoch, so tasks already built from this spec recompile their runtime line
at the next `execute!` — exactly like knob assignment.
"""
struct ElementSpec{Kind} <: AbstractElementSpec
    params::Dict{Symbol,Any}
    function ElementSpec{Kind}(params::Dict{Symbol,Any}) where {Kind}
        spec = new{Kind}(params)
        # Every construction route funnels through here, so this is the one
        # choke point for the unknown-key warning (2026-08-05 audit, U13-1).
        _warn_unknown_spec_keys(ElementSpec{Kind}, params)
        return spec
    end
end

ElementSpec{Kind}(; kwargs...) where {Kind} =
    ElementSpec{Kind}(Dict{Symbol,Any}(Symbol(k) => v for (k, v) in pairs(kwargs)))

# Placement keys `compile_runtime` consumes for EVERY kind — the misalignment
# and design-orbit-roll wraps read them regardless of the element's own
# schema (`_misalignment_wrap`, `_ref_tilt_wrap`), so `setproperty!` accepts
# them and the unknown-key warning below exempts them. Before this list, the
# documented binding path rejected physically meaningful input on 17 of 30
# kinds (`DriftSpec(L=0.5, x_offset=1e-3)` compiled to a MisalignedElement
# while `d.x_offset = 1e-3` threw; 2026-08-05 audit, U13-2). Registered kinds
# now also declare them per-kind through `_PLACEMENT_PARAMS` below; this list
# keeps the acceptance working for kinds registered without it.
const _PLACEMENT_PARAM_KEYS = (:x_offset, :y_offset, :z_offset, :x_pitch,
                               :y_pitch, :tilt, :misalign_convention, :ref_tilt)

# Loud, not strict: every friendly constructor documents "extra keyword
# arguments are stored as descriptive spec metadata", so an unknown key is
# LEGAL — but it is also exactly what a typo of a physics parameter looks
# like, and a typo tracked silently is silent wrong physics (measured: an
# out-of-schema `e1 = 0.2` on a quadrupole shifts tracking by 7.7e-7;
# 2026-08-05 audit, U3-10/U13-1/U10-10). One warning at construction names
# the unrecognized keys; `set_param!` is the deliberate-metadata door that
# stays silent.
"""
    _extra_tracked_keys(kind) -> Tuple{Vararg{Symbol}}

Keys the compiled runtime for `kind` reads that its own `parameters` schema does
not declare.

Only the unknown-key WARNING consults this: it exists so that warning cannot
tell a user a key is untracked when the runtime reads it (2026-08-05_b audit,
U9-2). Completing the schemas themselves is the real repair and is recorded on
docs/todo.md, because it widens the parameter-effectiveness sweep by ~80 entries
and each has to be either verified or exempted with a reason.

The fallback is empty, so a kind that does not extend this is unaffected.
"""
_extra_tracked_keys(::Val) = ()

function _warn_unknown_spec_keys(::Type{ElementSpec{Kind}}, params::Dict{Symbol,Any}) where {Kind}
    meta = get(ELEMENT_META_BY_KIND, Kind, nothing)
    # No meta yet: `@element_spec` example expressions run before their own
    # registration, and unregistered kinds have no schema to check against.
    (meta === nothing || isempty(meta.parameters)) && return nothing
    # Keys the compiled runtime genuinely reads, beyond this kind's own schema.
    # Warning about one of these would say "it is NOT being tracked" about a key
    # that changes tracking by up to 5.8e-2 -- loud AND wrong, which is worse
    # than silent (2026-08-05_b audit, U9-2). `_lattice_magnet` reads the same
    # 23 body keys for every kind it compiles while each kind declares only its
    # own subset, so e.g. `e1` on a quadrupole is read (measured 7.7e-7 shift)
    # and was being reported as untracked.
    extra = _extra_tracked_keys(Val(Kind))
    unknown = [k for k in keys(params)
               if !haskey(meta.parameters, k) && !(k in _PLACEMENT_PARAM_KEYS) &&
                  !(k in extra)]
    isempty(unknown) && return nothing
    @warn "ElementSpec{$(repr(Kind))}: unknown parameter(s) stored as descriptive " *
          "metadata only — if one is a typo of a physics parameter, it is NOT " *
          "being tracked. Deliberate metadata can use set_param! to stay silent." kind = Kind unknown = sort!(unknown; by = string)
    return nothing
end

# Bumped by every in-place ElementSpec parameter mutation; task runtime caches
# compare it (next to the knob epoch) so a post-construction binding reaches an
# already-built task at its next execute!.
const _SPEC_EPOCH = Ref{UInt64}(0)
_spec_epoch() = _SPEC_EPOCH[]

function Base.getproperty(spec::ElementSpec{Kind}, name::Symbol) where {Kind}
    name === :params && return getfield(spec, :params)
    p = getfield(spec, :params)
    haskey(p, name) || throw(ArgumentError(
        "ElementSpec{$(repr(Kind))} has no parameter $(name); stored parameters: " *
        join(sort!(collect(keys(p)); by=string), ", ")))
    return p[name]
end

function Base.setproperty!(spec::ElementSpec{Kind}, name::Symbol, value) where {Kind}
    name === :params && throw(ArgumentError(
        "params is the ElementSpec storage field; assign individual parameters " *
        "(spec.zeta1 = ...) instead"))
    # Folded construction sugar (k1, k2l, angle, ...) is read only at
    # construction; the runtime reads the folded tuples, so a
    # post-construction assignment to the sugar name was stored and never
    # read (2026-08-05 audit, U11-4). The line-placement guard owns the
    # table and throws with the right remedy for both paths.
    _reject_folded_override(spec, name)
    p = getfield(spec, :params)
    if !haskey(p, name) && !(name in _PLACEMENT_PARAM_KEYS)
        meta = _element_meta_or_nothing(spec)
        if meta !== nothing && !isempty(meta.parameters) &&
           !haskey(meta.parameters, name)
            throw(ArgumentError(
                "element kind $(repr(Kind)) has no parameter $(name); valid " *
                "parameters: " *
                join(sort!(collect(propertynames(meta.parameters)); by=string), ", ") *
                ". For a new metadata key, use set_param!(spec, $(repr(name)), value) " *
                "— the raw spec.params[...] = ... form skips the recompile epoch."))
        end
    end
    p[name] = value
    _SPEC_EPOCH[] += 1
    return value
end

"""
    set_param!(spec, key, value)

Set any spec parameter or metadata key, bypassing the schema check but NOT
the recompile epoch: a mutation through the raw `spec.params[key] = value`
Dict never bumps `_SPEC_EPOCH`, so an already-built task would keep tracking
the stale compile (2026-08-05 audit, U13-2). This is the deliberate door for
out-of-schema metadata; schema-checked physics parameters read better as
`spec.key = value`.
"""
function set_param!(spec::ElementSpec, key::Symbol, value)
    getfield(spec, :params)[key] = value
    _SPEC_EPOCH[] += 1
    return value
end

Base.propertynames(spec::ElementSpec, ::Bool=false) =
    (sort!(collect(keys(getfield(spec, :params))); by=string)..., :params)

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

# Schema entries for the placement keys, spliced into every registered kind's
# `parameters` declaration (`_PLACEMENT_PARAMS...`) so `parameter_schema`,
# `element_help`, and the parameter-effectiveness contract see what the
# compile wraps consume for every kind — before this, the schemas
# under-declared what `compile_runtime` reads (2026-08-05 audit, U13-2
# completion). Kinds where a placement parameter conjugates to exactly
# nothing (an identity map, a constant kick) say why in
# `DEFAULT_INACTIVE_ELEMENT_PARAMS`; the reasons are map structure, not
# sweep output, because a mathematically inert conjugation can still move
# the last bit through the (v - d) + d round trip.
const _PLACEMENT_PARAMS = (
    x_offset=ParamMeta(default=0, unit="m",
        meaning="horizontal displacement of the element body, a placement error consumed by the generic misalignment wrap at compile_runtime, not by the element kernel; see src/elements/misalignment.jl"),
    y_offset=ParamMeta(default=0, unit="m",
        meaning="vertical displacement of the element body; see x_offset"),
    z_offset=ParamMeta(default=0, unit="m",
        meaning="longitudinal displacement of the element body along the local reference direction; see x_offset"),
    x_pitch=ParamMeta(default=0, unit="rad",
        meaning="rotation of the body in the x-s plane (about the vertical axis); see x_offset"),
    y_pitch=ParamMeta(default=0, unit="rad",
        meaning="rotation of the body in the y-s plane (about the horizontal transverse axis); see x_offset"),
    tilt=ParamMeta(default=0, unit="rad",
        meaning="roll of the body about s, an alignment ERROR measured against the design orbit; the design roll is ref_tilt"),
    misalign_convention=ParamMeta(default=:bmad,
        meaning="which code's misalignment convention to follow, :bmad or :madx; they differ in rotation-composition order, the arc point the displacement anchors at, and the frame an error is stated in against a ref_tilt"),
    ref_tilt=ParamMeta(default=0, unit="rad",
        meaning="DESIGN roll of the element about s — geometry, not an error; wraps outside the misalignment, and a :madx alignment error against it is stated in the unrolled design frame"),
)

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
    :lattice_magnet,
    :thick_element,
    :placeholder,
    :collimation,
    :particle_loss,
    # A composite of other elements. One word rather than mislabelling a line
    # as something it is not; the vocabulary is controlled precisely so that
    # additions are deliberate.
    :beam_line,
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
    register_friendly_alias!(T, query)

Register an additional friendly constructor type for an existing
`ElementMeta`, for a constructor that builds another kind's spec —
`RBendSpec`, which constructs an `ElementSpec{:sbend}` with parallel pole
faces. Without the alias, type-level queries (`element_help(RBendSpec)`,
`required_contracts(RBendSpec)`) silently miss the registry and report an
empty, confident answer about a validated element (audit part 7, K1); the
*instance* always resolved correctly through its kind.
"""
function register_friendly_alias!(T, query)
    meta = element_meta(query)
    ELEMENT_META_BY_FRIENDLY_TYPE[T] = meta
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

"""
    numeric_type(spec, default=Float64)

The number type a spec's runtime should be built in, promoted over its numeric
parameters.

`Float64` for an ordinary element, and the promoted type when a parameter is a
dual number or a truncated power series — which is what lets a derivative be
taken with respect to a *parameter* (a strength, a length, an alignment error)
rather than only with respect to a coordinate. Coordinate derivatives need none
of this: the coordinates promote against `Float64` fields on their own.

Non-numeric parameters are ignored, and so are unresolved knob expressions —
they are numbers by the time `compile_runtime` reaches a runtime constructor,
and ignoring them here means an unresolved spec still reports a usable type.
"""
numeric_type(spec::ElementSpec, default::Type=Float64) =
    foldl(_promote_param_type, values(getfield(spec, :params)); init=default)
numeric_type(x, default::Type=Float64) = default

_promote_param_type(T::Type, v::Number) = promote_type(T, typeof(v))
_promote_param_type(T::Type, v::Union{Tuple,AbstractArray}) =
    foldl(_promote_param_type, v; init=T)
_promote_param_type(T::Type, v) = T

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
    return meta === nothing ? Symbol[] : copy(meta.keywords)
end
physics_keywords(x::AbstractElementSpec) = physics_keywords(typeof(x))
function physics_keywords(T::Type)
    meta = _element_meta_or_nothing(T)
    return meta === nothing ? Symbol[] : copy(meta.keywords)
end

"""
    supported_tracking_methods(spec)

Return tracking method types supported by an element spec. Element specs should
extend this to advertise valid numerical algorithms.
"""
function supported_tracking_methods(T::Type{<:AbstractElementSpec})
    meta = _element_meta_or_nothing(T)
    return meta === nothing ? Type{<:AbstractTrackingMethod}[] : copy(meta.tracking_methods)
end
supported_tracking_methods(x::AbstractElementSpec) = supported_tracking_methods(typeof(x))
function supported_tracking_methods(T::Type)
    meta = _element_meta_or_nothing(T)
    return meta === nothing ? Type{<:AbstractTrackingMethod}[] : copy(meta.tracking_methods)
end

"""
    supported_analyses(spec)

Return analysis types that are meaningful for an element spec.
"""
function supported_analyses(T::Type{<:AbstractElementSpec})
    meta = _element_meta_or_nothing(T)
    return meta === nothing ? Type{<:AbstractAnalysis}[] : copy(meta.analyses)
end
supported_analyses(x::AbstractElementSpec) = supported_analyses(typeof(x))
function supported_analyses(T::Type)
    meta = _element_meta_or_nothing(T)
    return meta === nothing ? Type{<:AbstractAnalysis}[] : copy(meta.analyses)
end

"""
    required_contracts(spec)

Return contract types that should validate an implementation of the
given element spec.

This and the other list-returning queries (`physics_keywords`,
`supported_tracking_methods`, `supported_analyses`) return a **copy**: the
lists are the registry's own state, and handing them out live meant
`push!(required_contracts(ElementSpec{:sbend}), Int64)` permanently corrupted
the registry in-process while validation still passed (audit part 7, K5) --
inconsistent with the copy discipline `registered_element_specs` follows.
"""
function required_contracts(T::Type{<:AbstractElementSpec})
    meta = _element_meta_or_nothing(T)
    return meta === nothing ? Type{<:AbstractContract}[] : copy(meta.contracts)
end
required_contracts(x::AbstractElementSpec) = required_contracts(typeof(x))
function required_contracts(T::Type)
    meta = _element_meta_or_nothing(T)
    return meta === nothing ? Type{<:AbstractContract}[] : copy(meta.contracts)
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

"""Whether a compiled example is (or wraps) an instance of a declared runtime type."""
# "Is (or wraps)": a spec carrying a misalignment or a ref_tilt compiles to
# a wrapper around the declared runtime, and the bare `isa` falsely rejected
# any such example (2026-08-05 audit, U13-4). The wrapper types are defined
# later in the include order; the names resolve at call time.
function _compiled_matches_runtime(compiled, rt::Type)
    compiled isa rt && return true
    if compiled isa MisalignedElement || compiled isa RefTilted
        return _compiled_matches_runtime(compiled.inner, rt)
    end
    return false
end

"""
Compare each declared `ParamMeta.default` against the runtime it produces.

The checkable property is that OMITTING a parameter compiles to the same map as
passing its declared default. Anything a kind cannot be built or compiled from
is skipped rather than guessed at, and the skip is silent by design: this runs
over every registered kind and a construction failure is the
`ElementParameterEffectivenessContract`'s business, not this check's.

Verified discriminating: with `quadrupole.nst`'s declared default (1) the two
compile identically, and with a wrong one (7) they do not.
"""
function _check_declared_defaults!(errors, T, meta, example)
    example isa ElementSpec || return errors
    ctor = meta.friendly_constructor
    ctor === nothing && return errors
    base = try
        Dict{Symbol,Any}(params(example))
    catch
        return errors
    end
    u = (1.0e-3, 2.0e-4, -5.0e-4, 1.0e-4, 1.0e-3, 3.0e-4)
    for (key, pmeta) in pairs(parameter_schema(T))
        pmeta isa ParamMeta || continue
        pmeta.default === nothing && continue
        pmeta.required && continue
        haskey(base, key) || continue
        without = copy(base); delete!(without, key)
        withdef = copy(base); withdef[key] = pmeta.default
        omitted = try collect(compile_runtime(ctor(; without...))(u...)) catch; continue end
        declared = try collect(compile_runtime(ctor(; withdef...))(u...)) catch; continue end
        omitted == declared || push!(errors,
            "ElementMeta $(meta.kind) parameter $(key) declares default " *
            "$(repr(pmeta.default)) but omitting it compiles to a different map")
    end
    return errors
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
- declared tracking methods, contracts, and analyses are subtypes of their
  architectural roots, and the example actually compiles to a declared
  runtime type -- the non-circular consumer checks added after the injected-
  defect measurement (audit part 7, K3: 1 of 13 lies caught before them)
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

        # Declared defaults are checked against the RUNTIME, not merely stored.
        #
        # `ParamMeta.default` was decoration: it was read in exactly one place
        # (the required-with-a-default check above) and otherwise only for
        # display, so `element_help`, `parameter_schema` and every generated doc
        # could state a default the constructor contradicts. The machinery for
        # this already existed one layer over -- `validate_configuration_metadata`
        # compares every policy, solver, schedule and observer option against its
        # constructor -- and elements got no such pass (2026-08-05_b audit,
        # U12-1).
        #
        # The property checked is the one that can actually be wrong: OMITTING a
        # parameter must compile to the same map as passing its declared
        # default. Comparing the declared default against the example's stored
        # value would be meaningless -- an example is meant to demonstrate
        # non-default values, and 31 of 72 such pairs differ for exactly that
        # reason.
        _check_declared_defaults!(errors, T, meta, example)

        if example isa ElementSpec
            schema_keys = Set(keys(parameter_schema(T)))
            for key in keys(params(example))
                key in schema_keys ||
                    push!(errors, "ElementMeta $(meta.kind) example contains undeclared parameter $(key)")
            end
        end

        # These checks run against the DECLARATIONS, not against query
        # functions that merely return them: the previous loop iterated
        # `supported_tracking_methods(T)` -- which returns
        # `meta.tracking_methods` -- and then asked whether each element was in
        # `meta.tracking_methods`, a tautology that let a fabricated method
        # list validate clean (audit part 7, K3). Injected-defect measurement
        # before this rewrite: 1 of 13 metadata lies caught.
        for tracking_method in meta.tracking_methods
            (tracking_method isa Type && tracking_method <: AbstractTrackingMethod) ||
                push!(errors, "ElementMeta $(meta.kind) declares tracking method $(tracking_method), which is not an AbstractTrackingMethod")
            haskey(meta.runtime_types, tracking_method) ||
                push!(errors, "ElementMeta $(meta.kind) has no runtime type for $(tracking_method)")
        end
        for contract in meta.contracts
            (contract isa Type && contract <: AbstractContract) ||
                push!(errors, "ElementMeta $(meta.kind) declares contract $(contract), which is not an AbstractContract")
        end
        for analysis in meta.analyses
            (analysis isa Type && analysis <: AbstractAnalysis) ||
                push!(errors, "ElementMeta $(meta.kind) declares analysis $(analysis), which is not an AbstractAnalysis")
        end
        # `runtime_type` (singular) is stored for display but the queries read
        # the per-method map, so the two could silently disagree (audit
        # part 7, K4).
        if meta.runtime_type !== nothing && !isempty(meta.runtime_types)
            meta.runtime_type in values(meta.runtime_types) ||
                push!(errors, "ElementMeta $(meta.kind) runtime_type $(meta.runtime_type) is not in its runtime_types map")
        end
        # The non-circular consumer check: the example must actually compile,
        # and to a declared runtime type. This is the check that catches a
        # metadata list the implementation cannot honour, which the tautology
        # above never could.
        # No `!isempty(meta.runtime_types)` gate on COMPILING: an empty
        # tracking-methods list once disabled this check entirely, so a kind
        # like `:line` shipped an example nothing ever compiled (2026-08-05
        # audit, U13-3). Only the declared-runtime MATCH needs the map.
        if example isa ElementSpec
            compiled = try
                compile_runtime(example)
            catch err
                push!(errors, "ElementMeta $(meta.kind) example does not compile: $(sprint(showerror, err))")
                nothing
            end
            if compiled !== nothing && isempty(meta.runtime_types) &&
               meta.runtime_type isa Type
                _compiled_matches_runtime(compiled, meta.runtime_type) || push!(errors,
                    "ElementMeta $(meta.kind) example compiles to $(typeof(compiled)), not its declared runtime_type")
            end
            if compiled !== nothing && !isempty(meta.runtime_types)
                any(rt -> rt isa Type && _compiled_matches_runtime(compiled, rt),
                    values(meta.runtime_types)) ||
                    push!(errors, "ElementMeta $(meta.kind) example compiles to $(typeof(compiled)), which is not a declared runtime type")

                # EVERY declared mapping, not just the example's own.
                #
                # The check above is `any(...)` over ONE compiled example, and
                # `compile_runtime(example)` selects the example's own
                # `:tracking_method` -- so for a kind declaring several methods,
                # the other entries were never constructed and could name
                # anything. `haskey(meta.runtime_types, method)` proves an entry
                # EXISTS, never that it is right. Live exposure at the time:
                # `:lumped_radiation` declares Radiation6DMap, Damping6DMap and
                # Diffusion6DMap while its example uses the first, leaving two of
                # three mappings unvalidated (2026-08-05_b audit, U12-4).
                if length(meta.runtime_types) > 1
                    for (method, rt) in pairs(meta.runtime_types)
                        rt isa Type || continue
                        c = try
                            compile_runtime(example, method())
                        catch err
                            push!(errors,
                                "ElementMeta $(meta.kind) declares $(method) but its " *
                                "example cannot compile with it: $(sprint(showerror, err))")
                            continue
                        end
                        _compiled_matches_runtime(c, rt) || push!(errors,
                            "ElementMeta $(meta.kind) maps $(method) to $(rt) but " *
                            "compiling with it yields $(typeof(c))")
                    end
                end
            end
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

Knob-expression parameters (see `@knob_expr`) are evaluated here, through
`resolve_knobs`, immediately before the runtime constructor runs — this is the
single point where deferred knob expressions become numbers, so runtime
tracking objects never carry knobs.
"""
compile_runtime(spec::AbstractElementSpec) = compile_runtime(spec, tracking_method(spec))

function compile_runtime(spec::AbstractElementSpec, method)
    method_object = _tracking_method_object(method)
    T = runtime_type(spec, method_object)
    T === nothing && throw(MethodError(compile_runtime, (spec, method)))
    resolved = resolve_knobs(spec)
    # A misalignment is a property of where an element sits, not of how it
    # tracks, so it wraps the runtime here rather than being reimplemented
    # inside each element. `_misalignment_wrap` returns its argument untouched
    # when the spec carries no displacement, so an aligned element is exactly
    # what it was. Defined in `src/elements/misalignment.jl`.
    #
    # `ref_tilt` wraps OUTSIDE the misalignment, and the nesting is the physics:
    # the roll is design geometry, the misalignment is an error measured against
    # that design, so the design orbit rolls first and the body error is taken
    # relative to the rolled magnet. Both wrappers pass their argument through
    # untouched when the spec asks for nothing, so an ordinary element compiles
    # to exactly the runtime object it always did.
    return _ref_tilt_wrap(resolved,
                          _misalignment_wrap(resolved, T(resolved, method_object)))
end

# Generic fallback: specs without knob parameters pass through unchanged. The
# `ElementSpec` method that evaluates knob expressions lives in
# `src/knobs/Knobs.jl` (included after this file).
resolve_knobs(spec) = spec
