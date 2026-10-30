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
       validate_element_metadata, allowed_physics_keywords, allowed_param_units,
       set_param!

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
U9-2). NO KIND EXTENDS IT TODAY: the real repair -- completing the schemas so
every read key is declared -- landed 2026-08-15 for the six lattice-magnet
kinds (all 23 body keys, one merged `_LATTICE_BODY_PARAMS` table, every entry
under the effectiveness sweep; record in
docs/history/todo_ledger_archive.md, U9-2). The mechanism is kept as the
stopgap for a future kind caught mid-repair, but the standing rule is the
schema tells the truth and this list stays empty.

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
    # `maxlog`, because this fires more than once per spec (2026-08-05_b audit,
    # U12-18). The warning lives in the inner constructor -- the right choke
    # point for construction -- but `resolve_knobs` rebuilds
    # `ElementSpec{Kind}(resolved)` on every `compile_runtime` of a
    # knob-carrying spec, so the constructor and its warning run again each
    # time. Its own design note says "One warning at construction names the
    # unrecognized keys"; a knob sweep recompiling a thousand times said it a
    # thousand times. Keyed by kind and key set, so a genuinely different typo
    # elsewhere still speaks up.
    @warn "ElementSpec{$(repr(Kind))}: unknown parameter(s) stored as descriptive " *
          "metadata only — if one is a typo of a physics parameter, it is NOT " *
          "being tracked. Deliberate metadata can use set_param! to stay silent." kind = Kind unknown = sort!(unknown; by = string) maxlog = 1 _id = Symbol(:unknown_spec_keys_, Kind, :_, hash(sort!(copy(unknown); by = string)))
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
    ParamMeta(; required=false, unit="", default=nothing, meaning="",
              alternatives=())

Declarative metadata for one element-construction parameter.

`alternatives` declares the parameter's other legitimate values — the enum
for a Symbol/flag parameter (`misalign_convention`'s `(:bmad, :madx)`), or
explicit hand-picked values where the generic numeric perturbation asks the
wrong question. It is the machine-readable half of what `meaning` says in
prose, and the parameter-effectiveness contract derives its perturbations
from it: before `alternatives`, every Symbol parameter was structurally
unperturbable and the contract could not check that `fringe`, `bend_model`,
or the misalignment convention reached the map at all (U4-12). Declared
alternatives replace the generic candidate rule for that parameter, so they
also serve `Real` parameters whose only falsifiable moves are specific
values. An empty tuple means "no declaration"; validity of each alternative
is arbitrated by the constructor at probe time, exactly as numeric
perturbations are (U4-3). The two readings are told apart by the default's
type: for a Symbol or type default the tuple is the enum and
`validate_element_metadata` requires the default to be one of its members;
for a numeric default the tuple is perturbation values and need not contain
it (the aperture's limits default to `Inf` against shrunken alternatives).
"""
struct ParamMeta
    required::Bool
    unit::String
    default::Any
    meaning::String
    alternatives::Tuple
end
ParamMeta(; required::Bool=false, unit="", default=nothing, meaning="",
          alternatives::Tuple=()) =
    ParamMeta(required, String(unit), default, String(meaning), alternatives)

# Schema entries for the placement keys, spliced into every registered kind's
# `parameters` declaration (`_PLACEMENT_PARAMS...`, or `_placement_param(:key;
# meaning=...)` below where a kind has more to say about one) so
# `parameter_schema`, `element_help`, and the parameter-effectiveness contract
# see what the compile wraps consume for every kind — before this, the schemas
# under-declared what `compile_runtime` reads (2026-08-05 audit, U13-2
# completion). `validate_element_metadata` holds every kind's entries to this
# table's unit, default and alternatives (F-171). Kinds where a placement
# parameter conjugates to exactly nothing (an identity map, a constant kick)
# say why in `DEFAULT_INACTIVE_ELEMENT_PARAMS`; the reasons are map structure,
# not sweep output, because a mathematically inert conjugation can still move
# the last bit through the (v - d) + d round trip.
const _PLACEMENT_PARAMS = (
    # `name` is here for the same reason the placement keys are: the beam-line
    # walker reads `getparam(child, :name, "")` for every entry and the design
    # promises provenance paths like `ARC1/QF[3]`, but only `:line` and
    # `:aperture` declared it -- so naming an ordinary lattice element warned
    # that the value was "NOT being tracked", on the one parameter whose whole
    # purpose is to be carried rather than consumed (2026-08-05_b audit,
    # U15-12). Those two kinds keep their own, more specific `meaning`; a
    # per-kind entry wins over this one.
    name=ParamMeta(default="",
        meaning="label for this element, carried into beam-line provenance paths (ARC1/QF[3]) and into diagnostics that name an element rather than an index; read by the line walker, never by a tracking kernel"),
    # `numeric_type` is here for the same reason: the number type a kind's
    # runtime compiles in is a property of EVERY kind, one rule (owner
    # decision 2026-10-16, fix H of the crab-cavity noise neighbour audit).
    # The untyped friendly constructor leaves it unset -- `numeric_type(spec)`
    # then promotes the stored parameters over a Float64 floor -- and the
    # `Spec{T}` form every kind has stores `T` (`_typed_spec_params`). The two
    # tracking precisions are its `alternatives`, so the parameter-effectiveness
    # contract perturbs it and checks the typed form reaches the map.
    numeric_type=ParamMeta(default=Float64, alternatives=(Float64, Float32),
        meaning="the number type the compiled runtime is built in, read by numeric_type(spec) at compile_runtime: unset by the untyped friendly constructor (the promotion of the stored parameters over a Float64 floor, so Float32 inputs give a Float64 element and a dual or complex input widens it), stored as T by the kind's Spec{T} form -- Spec{Float32}(; ...) is the Float32 element, and Spec(; numeric_type=Float32, ...) is the same element by keyword; a beam whose element type differs from the element's is refused by name when a task compiles the line"),
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
    misalign_convention=ParamMeta(default=:bmad, alternatives=(:bmad, :madx),
        meaning="which code's misalignment convention to follow, :bmad or :madx; they differ in rotation-composition order, the arc point the displacement anchors at, and the frame an error is stated in against a ref_tilt"),
    ref_tilt=ParamMeta(default=0, unit="rad",
        meaning="DESIGN roll of the element about s — geometry, not an error; wraps outside the misalignment, and a :madx alignment error against it is stated in the unrolled design frame"),
)

"""
    _placement_param(key; meaning) -> ParamMeta

The `_PLACEMENT_PARAMS` entry for `key` with a kind-specific `meaning` and
NOTHING else changed: `required`, `unit`, `default` and `alternatives` come from
the one table. A kind that has more to say about a placement key than the
generic sentence (the bend's `tilt` against its `ref_tilt`, the thin kinds'
zero-length reading of the convention, the line's rigid girder) declares it
through this rather than by writing its own `ParamMeta`: 13 of the 31 kinds had
copied the entries by hand and 79 of those copies had drifted -- every one had
lost its unit, and seven kinds' `misalign_convention` had lost the
`alternatives` the effectiveness contract needs to perturb a Symbol parameter at
all (2026-10-18 comprehensive audit, F-171). `validate_element_metadata` holds
every registered kind's placement entries to the table.
"""
function _placement_param(key::Symbol; meaning::AbstractString)
    base = _PLACEMENT_PARAMS[key]
    return ParamMeta(base.required, base.unit, base.default, String(meaning), base.alternatives)
end

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
    :acceleration,
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
    # A task-managed experimental reset for repeated fixed-input noise trials.
    :phase_space_reset,
    :noise_response,
    # An element kind that declares turn-by-turn modulation rule parameters;
    # see src/elements/turn_modulated.jl.
    :turn_modulation,
    # A composite of other elements. One word rather than mislabelling a line
    # as something it is not; the vocabulary is controlled precisely so that
    # additions are deliberate.
    :beam_line,
])

"""Return the current controlled physics-keyword set."""
allowed_physics_keywords() = copy(ALLOWED_PHYSICS_KEYWORDS)

"""
The controlled vocabulary for `ParamMeta.unit`, mirroring
`ALLOWED_PHYSICS_KEYWORDS` above.

`unit` is NOT decoration. Besides `element_help`, it has a BEHAVIOURAL consumer:
`_perturb_is_physical` (`src/contracts/Contracts.jl`) reads
`pmeta.unit in ("m", "rad")` to decide whether the parameter-effectiveness
contract perturbs an integer-declared parameter by a physical amount
(`1.0e-3`) or by an enum-style step. So a misspelt unit does not merely print
oddly -- it silently downgrades a physical parameter to an enum probe, and the
contract still passes, testing something weaker than it claims. That is the
"a check that cannot fail" family one level out, and it is why this field earns
a vocabulary rather than staying free text (2026-08-06 audit U12-6; closed
2026-09-07).

Empty means "dimensionless or unspecified" and is admitted: 233 of the 255
`ParamMeta` declarations do not set a unit at all.

MEMBERSHIP HERE IS NOT THE SAME AS BEING PHYSICAL. `Hz` is a legitimate unit and
is admitted, but `_perturb_is_physical` treats only `m` and `rad` as physical;
adding a unit here does not change the contract's perturbation policy, and
changing that policy is a separate decision with its own evidence.
"""
const ALLOWED_PARAM_UNITS = Set{String}([
    "",      # dimensionless, or deliberately unspecified
    "m",     # length; physical to the effectiveness contract
    "rad",   # angle; physical to the effectiveness contract
    "Hz",    # frequency
])

"""Return the current controlled parameter-unit vocabulary."""
allowed_param_units() = copy(ALLOWED_PARAM_UNITS)

"""
    _help_mentions_parameter(help, key) -> Bool

Whether `help` mentions `key` as a word rather than as an accidental substring.

Julia identifiers may contain letters, digits, underscores and `!`, so a
mention is a match not flanked by any of those (2026-08-05_b audit, U12-5).
"""
function _help_mentions_parameter(help::AbstractString, key::Symbol)
    name = string(key)
    isvalid_char(c) = isletter(c) || isdigit(c) || c == '_' || c == '!'
    start = 1
    while true
        r = findnext(name, help, start)
        r === nothing && return false
        before = first(r) == 1 ? nothing : help[prevind(help, first(r))]
        after_i = nextind(help, last(r))
        after = after_i > lastindex(help) ? nothing : help[after_i]
        okbefore = before === nothing || !isvalid_char(before)
        okafter = after === nothing || !isvalid_char(after)
        (okbefore && okafter) && return true
        start = nextind(help, first(r))
    end
end

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
    # A second declaration for an already-registered kind used to win or lose
    # silently by include order (2026-08-05_b audit, U12-7). Both tables were
    # assigned unconditionally, `register_element_spec!` de-duplicates the type
    # list, and `validate_element_metadata`'s duplicate detector keys on
    # `seen_kinds` while iterating `registered_element_specs()` -- so two blocks
    # sharing one spec_type are seen exactly once and the loser is invisible.
    # Measured: re-registering `:drift` with a changed description replaced it
    # outright, with `validate passed = true, errors = 0`. That is "loud beats
    # silent" inverted, on the table every other registry derives from.
    #
    # A warning rather than an error: tests legitimately register and remove
    # temporary kinds (the contract tripwire controls do exactly that), and the
    # replacement itself is a valid operation. What was missing was any signal.
    if haskey(ELEMENT_META_BY_KIND, meta.kind)
        previous = ELEMENT_META_BY_KIND[meta.kind]
        previous === meta || previous.spec_type !== meta.spec_type ||
            @warn "element kind re-registered: a second declaration replaced the \
                   first, which is what a copy-pasted or merge-duplicated \
                   @element_spec block looks like. The winner is decided by \
                   include order." kind = meta.kind spec_type = meta.spec_type
    end
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

# The untyped form stores its inputs as given and compiles in
# `numeric_type(spec)`, the Float64-floor promotion; `numeric_type = T` as a
# keyword routes to the typed form, which is how reflection and the
# parameter-effectiveness contract reach it.
MyElementSpec(; numeric_type=nothing, strength, tracking_method=Symplectic6DMap(), kwargs...) =
    numeric_type === nothing ?
        ElementSpec{:my_element}(_spec_params(; strength, tracking_method, kwargs...)) :
        MyElementSpec{numeric_type}(; strength, tracking_method, kwargs...)

# The typed form stores `numeric_type = T` and its floating-point inputs as `T`.
function (::Type{MyElementSpec{T}})(; strength,
                                    tracking_method=Symplectic6DMap(),
                                    kwargs...) where {T}
    return ElementSpec{:my_element}(
        _typed_spec_params(T; strength=strength,
                           tracking_method=tracking_method,
                           kwargs...)
    )
end

# `T<:Number`, the ONE numeric type parameter: `_required_beam_eltype` derives
# the beam element type the kind requires from it.
struct MyElement{M<:AbstractTrackingMethod,T<:Number} <: AbstractTrackOp
    method::M
    strength::T
end

function MyElement(spec::ElementSpec{:my_element},
                   method::AbstractTrackingMethod=tracking_method(spec))
    T = numeric_type(spec)
    return MyElement(method, T(param(spec, :strength)))
end

# The cross-backend rounding class (`CrossBackendRounding`, src/track/Track.jl):
# per coordinate, whether the CPU and CUDA kernels agree bitwise (never written,
# or written by arithmetic exact under any FMA fusion) or within a stated
# number of ulps of the coordinate's scale, and why. No default: a kind without
# a method is refused by name, and the suite measures every declaration.
_cross_backend_rounding(::MyElement) = _rounding_class(
    untouched=(:x, :y, :z, :pz), ulp=(:px, :py), ulp_bound=8,
    why="the kick `px - strength x` fuses on the device and rounds twice on the host")

@element_spec begin
    kind = :my_element
    spec_type = ElementSpec{:my_element}
    friendly_constructor = MyElementSpec
    runtime_type = MyElement
    description = "Short physics description."
    keywords = [:my_element]
    tracking_methods = [Symplectic6DMap]
    contracts = DataType[]
    analyses = [TwissDispersionAnalysis]
    parameters = (
        strength=ParamMeta(required=true, meaning="element strength"),
        tracking_method=ParamMeta(default=Symplectic6DMap(),
                                  meaning="per-element tracking method"),
        _PLACEMENT_PARAMS...,   # placement, name and numeric_type: every kind
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
- declare `TwissDispersionAnalysis` on every kind whose `tracking_methods` contain `Symplectic6DMap` and not `NonSymplectic6DMap` (the suite's set tripwires derive that set and fail on a kind that departs from it); use `PlaceholderAnalysis` only for kinds that have no analysis;
- the numeric type follows ONE rule for every kind (owner decision 2026-10-16): the compile constructor builds the runtime in `numeric_type(spec)`, the promotion of the stored parameters over a `Float64` floor for an untyped friendly constructor (a `Float32` input gives a `Float64` element, a dual or complex input widens it, nothing narrows) and the stored `numeric_type` for the `Spec{T}` form -- which every kind has, so every kind can sit in a `Float32` line; the typed form stores `_typed_spec_params(T; ...)` (floating-point inputs as `T`, `numeric_type = T`) and the untyped form routes `numeric_type=T` to it, storing no type itself (an untyped form that builds through its typed one drops the stored type again with `_floor_form`, so a dual or BigFloat placed later by a knob or a placement override still widens the element); declare the schema entry by splicing `_PLACEMENT_PARAMS...` (or `numeric_type=_PLACEMENT_PARAMS.numeric_type`); the runtime struct carries `T<:Number` as its one numeric type parameter, from which `_required_beam_eltype` (`src/track/Track.jl`) derives the beam element type the kind requires, so a task refuses a beam of another type by name; the suite pins the derived set against the registry;
- declare the cross-backend rounding class on the runtime type (`_cross_backend_rounding`, `CrossBackendRounding` in `src/track/Track.jl`): for each of the six coordinates `:untouched`, `:bitwise` (written by single IEEE operations or arithmetic exact under any FMA fusion) or `:ulp` with a bound in ulps of the coordinate's scale and a `why` naming the operations; the device fuses `a b + c` into one FMA and its libm differs from the host's on transcendentals, so anything else is `:ulp`; there is no default, and the suite's "Cross-backend rounding classes" testset derives the set of types that must declare and measures every registry example against its declaration (the measurement wins);
- declare the placement keys by splicing `_PLACEMENT_PARAMS...`, or through `_placement_param(:key; meaning=...)` where the kind has more to say about one: `validate_element_metadata` holds every placement entry to the table's unit, default and alternatives, compares EVERY declared default (the example's or not) with the map omitting the parameter compiles to, requires a Symbol or type default to lie within its `alternatives`, and refuses empty descriptions, keywords, meanings and construction help (F-168, F-171, F-172);
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

The number type a spec's runtime is built in -- the one rule every compile
constructor follows (owner decision 2026-10-16): the stored `numeric_type`
parameter when the spec was built by a kind's `Spec{T}` form (or given
`numeric_type=T` by keyword), otherwise the promotion of the stored numeric
parameters over the `default` floor.

`Float64` for an ordinary element: integers and `Float32` inputs to an untyped
friendly constructor land on the floor, so nothing is ever narrowed silently,
and the promoted type when a parameter is a dual number or a truncated power
series — which is what lets a derivative be taken with respect to a
*parameter* (a strength, a length, an alignment error) rather than only with
respect to a coordinate. Coordinate derivatives need none of this: the
coordinates promote against `Float64` fields on their own. `Spec{Float32}(; ...)`
is the Float32 element of every kind; a stored type that is not a `Number` type
is refused here by name.

Non-numeric parameters are ignored, and so are unresolved knob expressions —
they are numbers by the time `compile_runtime` reaches a runtime constructor,
and ignoring them here means an unresolved spec still reports a usable type.
"""
function numeric_type(spec::ElementSpec, default::Type=Float64)
    stored = get(getfield(spec, :params), :numeric_type, nothing)
    if stored !== nothing
        (stored isa Type && stored <: Number) || throw(ArgumentError(
            "ElementSpec{$(repr(kind(spec)))}: numeric_type must be a Number type " *
            "(Float64, Float32, a dual or complex type); got $(repr(stored))"))
        return stored
    end
    return foldl(_promote_param_type, values(getfield(spec, :params)); init=default)
end
numeric_type(x, default::Type=Float64) = default

"""
    _typed_spec_params(T; kwargs...) -> Dict{Symbol,Any}

The stored parameters of a kind's `Spec{T}` form: every keyword as given, with
floating-point values (scalars, tuples, arrays) converted to `T`, and
`numeric_type = T`, which `numeric_type(spec)` returns and every compile
constructor builds in. Integers, Bools, Symbols, strings, rule objects and knob
expressions are stored untouched (an integer count stays a count; `L = 1`
compiles to `T(1)`); a dual or complex value is stored as given and converts
at compile only when `T` can hold it, so the typed form is the precision the
caller spelled, never a promotion.
"""
function _typed_spec_params(::Type{T}; kwargs...) where {T}
    params = Dict{Symbol,Any}(Symbol(k) => _as_numeric_type(T, v) for (k, v) in pairs(kwargs))
    params[:numeric_type] = T
    return params
end
_as_numeric_type(::Type{T}, v::AbstractFloat) where {T} = T(v)
_as_numeric_type(::Type{T}, v::Tuple) where {T} = map(x -> _as_numeric_type(T, x), v)
_as_numeric_type(::Type{T}, v::AbstractArray{<:AbstractFloat}) where {T} = T.(v)
_as_numeric_type(::Type{T}, v) where {T} = v

"""
    _stamp_numeric_type!(params::Dict, T) -> params

`numeric_type = T` written into the stored parameters of a typed form that
converted its values to `T` by hand (the linear maps, `Linear6DSpec`, the
chromaticity kick, the strong beams, the radiation element, the crab cavity):
the same stored type `_typed_spec_params` writes, over any `numeric_type`
keyword that reached the typed form.
"""
_stamp_numeric_type!(params::Dict{Symbol,Any}, ::Type{T}) where {T} =
    (params[:numeric_type] = T; params)

"""
    _floor_form(spec, requested) -> spec

The UNTYPED form of a kind whose untyped constructor builds through its typed
one (the linear maps, `Linear6DSpec`, the chromaticity kick, the strong beams,
the radiation element, the crab cavity): the stored `numeric_type` is dropped
again unless the caller requested one (`numeric_type=T` by keyword), so the
untyped form stores no type and `numeric_type(spec)` re-derives its promotion
from the stored values at every compile -- a dual or BigFloat placed later by a
knob or a placement override still widens the element (2026-08-05_b audit,
U9-6), where a stored type would have narrowed it silently. Only an explicit
`Spec{T}` or `numeric_type=T` stores the type.
"""
function _floor_form(spec::ElementSpec, requested)
    requested === nothing && delete!(getfield(spec, :params), :numeric_type)
    return spec
end

"""
    _with_numeric_type(spec, T) -> ElementSpec

`spec` with `numeric_type = T` stored and its other parameters unchanged, for a
compile constructor that hands a sub-spec the type of the element it builds:
the Gaussian strong beam compiles its `thin` in its own type.
"""
_with_numeric_type(spec::ElementSpec{Kind}, ::Type{T}) where {Kind,T} =
    ElementSpec{Kind}(merge(getfield(spec, :params), Dict{Symbol,Any}(:numeric_type => T)))

_promote_param_type(T::Type, v::Number) = promote_type(T, typeof(v))
_promote_param_type(T::Type, v::Union{Tuple,AbstractArray}) =
    foldl(_promote_param_type, v; init=T)
_promote_param_type(T::Type, v) = T

"""Return whether an `ElementSpec` contains a parameter key."""
hasparam(spec::ElementSpec, key::Symbol) = haskey(spec.params, key)

"""
    _declared_param(spec::ElementSpec, key::Symbol)

The stored value of `key`, else the default the kind's registered schema
declares for it: a runtime constructor reads a declared default from the ONE
place it is declared instead of restating it beside a `getparam` fallback. A
key that is absent and has no declared default (a required key, or one whose
default is `nothing`) is refused by name -- the kind, the key, the remedy --
never with a raw `KeyError`.

Until the 2026-10-18 comprehensive audit (F-93) the runtime constructors of
`crab_dispersion`, `momentum_dispersion`, `xy_coupling`, `chromaticity_kick`
and `lumped_radiation` read their defaulted keys with a bare `spec.params[key]`
(or, after the F-55 fix, refused EVERY absent key by name, the defaulted ones
included), so the documented flexible form `ElementSpec{:crab_dispersion}(;
zeta1=0.1)` failed while its schema declared `zeta2 = 0`.
"""
function _declared_param(spec::ElementSpec, key::Symbol)
    params = getfield(spec, :params)
    haskey(params, key) && return params[key]
    meta = get(ELEMENT_META_BY_KIND, kind(spec), nothing)
    pmeta = meta === nothing ? nothing : get(meta.parameters, key, nothing)
    pmeta isa ParamMeta && !pmeta.required && pmeta.default !== nothing && return pmeta.default
    throw(ArgumentError(
        "ElementSpec{:$(kind(spec))} is missing the parameter $(key) its runtime constructor " *
        "reads, and its schema declares no default for it; the flexible form requires every " *
        "required parameter the friendly constructor would supply (see " *
        "construction_help(ElementSpec{:$(kind(spec))}))"))
end

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
    # A non-empty tuple of `nothing`s against an empty-tuple default is the
    # per-slot spelling of inactive -- what a per-harmonic constructor stores
    # when the keyword was omitted (the crab cavity's `phase_noise`:
    # `_rule_tuple` coerces `()` to `N` times `nothing`). Rendering it beside
    # the `default=()` the parameter lines print showed two spellings of
    # inactive for one kind and advertised an unset keyword as a deliberate
    # value (2026-10-13 neighbour audit, U6-4). Only against the `()` default:
    # a tuple of `nothing`s against a numeric default is a real choice.
    value isa Tuple && !isempty(value) && meta.default === () &&
        all(x -> x === nothing, value) && return true
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
    # Declared alternatives are half the point of the field: the enum a user
    # can actually set. Rendering them was forgotten when the field landed
    # (2026-08-16 neighbour audit) -- machine-readable but invisible in
    # element_help is the same shape as declared-but-not-consumed.
    !isempty(meta.alternatives) &&
        push!(parts, "alternatives=" * join(repr.(meta.alternatives), ", "))
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
Whether a compiled example is (or wraps) an instance of a declared runtime type.

"Is (or wraps)": a spec carrying a misalignment or a ref_tilt compiles to a
wrapper around the declared runtime, and the bare `isa` falsely rejected any such
example (2026-08-05 audit, U13-4). The wrapper types are defined later in the
include order; the names resolve at call time.

Those four lines used to sit BETWEEN this docstring and the `function` line as
comments, which detaches the docstring on Julia 1.12 with no warning
(2026-08-05_b audit, U12-9) -- the exact gotcha the U13-4 audit itself recorded,
reintroduced by the U13-4 fix. The "Every export is documented" tripwire cannot
see it, because it iterates `names(Octopus)` and this is not exported.
"""
function _compiled_matches_runtime(compiled, rt::Type)
    compiled isa rt && return true
    # Derived from STRUCTURE, not a hand list of wrapper types (2026-08-05_b
    # audit, U12-10). This named `MisalignedElement` and `RefTilted` explicitly,
    # inside `src/knowledge/`, so any future generic wrapper -- a girder, a
    # slice container -- had to be hand-added here or every example carrying it
    # was falsely rejected: the same hand-copied-knowledge shape, with no
    # tripwire. A placement wrapper is exactly a runtime op that holds its
    # subject in an `inner` field, which both of those do and which a new one
    # would too.
    #
    # `CompositeLine` is deliberately NOT unwrapped: it holds `ops`, a tuple of
    # several operations, so there is no single inner runtime it could be said
    # to match -- and that is why the field test, rather than "any wrapper",
    # is the right rule.
    hasfield(typeof(compiled), :inner) &&
        return _compiled_matches_runtime(getfield(compiled, :inner), rt)
    return false
end

# Metadata and parameter-effectiveness probes share the real execution entry.
# Ordinary maps are scalar-callable; a task-managed operation specializes this
# helper with a capture/mutate/restore witness, never an identity fallback.
_element_metadata_probe(spec, coordinates) = collect(compile_runtime(spec)(coordinates...))
_element_probe_placement_supported(::Type) = true

"""
Compare each declared `ParamMeta.default` against the runtime it produces, for
EVERY non-required key that declares one.

The checkable property is that OMITTING a parameter compiles to the same map as
passing its declared default. It is checked whether or not the kind's example
sets the key: until the 2026-10-20 fix batch the loop skipped every key the
example left at its default (`haskey(base, key) || continue`), which was 531 of
the 608 declared defaults, every one on `:drift` and `:marker`, and the very
`quadrupole.nst` an earlier version of this docstring cited as its
discriminating example (2026-10-18 comprehensive audit, F-168: `drift.h`
redeclared from 0 to 6 validated clean while the compiled map moved).

Ordinary maps use a scalar coordinate probe. A task-managed operation uses
`_element_metadata_probe` to exercise its real lifecycle; phase-space reset
captures, mutates every coordinate, and restores through `TrackingTask`.
Unsupported scalar tracking is never substituted with an identity map.

Two bases, and no silent skip:

  * the kind's example, with `key` removed on one side and set to the declared
    default on the other -- the strong form, because the example's other
    parameters make the key observable (`nst` splits a LOADED quadrupole);
  * when the constructor REFUSES the declared default beside the example, the
    example's REQUIRED parameters alone, where the key has no twin to conflict
    with. That is the two-spellings refusal the constructors make by design: an
    explicit `k1` beside the folded `kn[2]` it conflicts with, the bend's
    `angle` beside its folded `h`/`b0`. The pairs compared this way are returned
    in `on_required_base`, so the weaker form is visible and the suite can
    re-derive that each one is refused beside its example.

Anything else that refuses is an ERROR naming the key, never a skip: a declared
default the constructor rejects on the bare base too (a default nothing can
pass is a metadata lie), an example that does not build without one of its
optional keys, a kind with declared defaults and no friendly constructor to
pass them through. Returns `(; pairs, checked, on_required_base)`; on a clean
tree `checked == pairs`.

Verified discriminating on both bases: with `quadrupole.nst`'s declared default
(1) the two compile identically and with a wrong one (7) they do not; with
`quadrupole.k1`'s declared default (0), compared on `{L}` alone, they compile
identically and with a wrong one (3) they do not.
"""
function _check_declared_defaults!(errors, T, meta, example)
    on_required_base = Tuple{Symbol,Symbol}[]
    example isa ElementSpec || return (pairs=0, checked=0, on_required_base=on_required_base)
    schema = parameter_schema(T)
    declared = [(key, pmeta) for (key, pmeta) in pairs(schema)
                if pmeta isa ParamMeta && pmeta.default !== nothing && !pmeta.required]
    npairs = length(declared)
    npairs == 0 && return (pairs=0, checked=0, on_required_base=on_required_base)
    ctor = meta.friendly_constructor
    if ctor === nothing
        push!(errors, "ElementMeta $(meta.kind) declares $(npairs) parameter default(s) " *
                      "but has no friendly_constructor through which to verify them")
        return (pairs=npairs, checked=0, on_required_base=on_required_base)
    end
    base = Dict{Symbol,Any}(params(example))
    required_base = Dict{Symbol,Any}(k => v for (k, v) in base
                                     if haskey(schema, k) && schema[k] isa ParamMeta &&
                                        schema[k].required)
    u = (1.0e-3, 2.0e-4, -5.0e-4, 1.0e-4, 1.0e-3, 3.0e-4)
    track(p) = _element_metadata_probe(ctor(; p...), u)
    arms(b, key, default) = begin
        without = copy(b); delete!(without, key)
        withdef = copy(b); withdef[key] = default
        (without, withdef)
    end
    # An example that does not build or compile as it stands has no defaults
    # to compare against; the example-compiles check names the reason, and one
    # line here keeps the unchecked pairs visible instead of one line per key.
    try
        track(base)
    catch err
        push!(errors, "ElementMeta $(meta.kind): its $(npairs) declared default(s) cannot be " *
                      "checked because the example itself does not build or compile " *
                      "through the friendly constructor: $(first(sprint(showerror, err), 160))")
        return (pairs=npairs, checked=0, on_required_base=on_required_base)
    end
    checked = 0
    for (key, pmeta) in declared
        without, withdef = arms(base, key, pmeta.default)
        omitted = try
            track(without)
        catch err
            push!(errors, "ElementMeta $(meta.kind) example does not build or compile " *
                          "without its optional parameter $(key): $(sprint(showerror, err))")
            continue
        end
        reduced = false
        compiled = try
            track(withdef)
        catch err_full
            # Refused beside the example: the two-spellings case. The same key
            # on the required parameters alone has no twin to conflict with.
            try
                without2, withdef2 = arms(required_base, key, pmeta.default)
                omitted = track(without2)
                reduced = true
                track(withdef2)
            catch err_reduced
                push!(errors,
                    "ElementMeta $(meta.kind) parameter $(key) declares default " *
                    "$(repr(pmeta.default)) that the constructor refuses, beside the " *
                    "example ($(first(sprint(showerror, err_full), 160))) and on the " *
                    "example's required parameters alone " *
                    "($(first(sprint(showerror, err_reduced), 160))); a default nothing " *
                    "can pass is a metadata lie")
                continue
            end
        end
        checked += 1
        reduced && push!(on_required_base, (meta.kind, key))
        omitted == compiled || push!(errors,
            "ElementMeta $(meta.kind) parameter $(key) declares default " *
            "$(repr(pmeta.default)) but omitting it compiles to a different map" *
            (reduced ? " (compared on the example's required parameters alone)" : ""))
    end
    return (pairs=npairs, checked=checked, on_required_base=on_required_base)
end

"""
The registry's method ANSWERS against its method LIST, for one kind: a kind
that declares tracking methods must answer a declared one from
`default_method(T)` and from `tracking_method(example)`, and a kind that
declares none must refuse both by name, as `compile_runtime(spec, method)`
refuses an explicit request on it. The `:line` answered `Symplectic6DMap()` to
both while its compile refused that very request (2026-10-18 comprehensive
audit, F-174).
"""
function _check_method_answers!(errors, T, meta, example)
    queries = Any[("default_method", () -> default_method(T))]
    example isa ElementSpec &&
        push!(queries, ("tracking_method(example)", () -> tracking_method(example)))
    for (label, query) in queries
        answered, err = try
            (typeof(query()), nothing)
        catch e
            (nothing, e)
        end
        if isempty(meta.tracking_methods)
            err isa ArgumentError || push!(errors,
                "ElementMeta $(meta.kind) declares no tracking method but $(label) " *
                (answered === nothing ? "throws $(typeof(err))" : "answers $(answered)") *
                "; a kind without methods must refuse by name, as compile_runtime does")
        elseif answered === nothing
            push!(errors, "ElementMeta $(meta.kind) $(label) throws: $(sprint(showerror, err))")
        elseif !(answered in meta.tracking_methods)
            push!(errors, "ElementMeta $(meta.kind) $(label) answers $(answered), which is " *
                          "not a declared tracking method")
        end
    end
    return errors
end

"""
    validate_element_metadata(; throw_on_error=false)
        -> (; passed, errors, default_pairs, defaults_checked, defaults_on_required_base)

Validate the registered element metadata table. This is intended for CI,
notebooks, and agent self-checks after adding or editing an element.

Checks include:

- every registered spec has exactly one `ElementMeta`
- every required parameter appears in `example_spec`
- no parameter is both required and given a default
- every declared tracking method resolves to a runtime type, and every
  runtime-type entry is a declared tracking method (the map is what
  `compile_runtime` executes; the list is what the registry publishes)
- friendly constructor metadata agrees with the raw `ElementSpec{kind}` type
- declared tracking methods, contracts, and analyses are subtypes of their
  architectural roots, and the example actually compiles to a declared
  runtime type -- the non-circular consumer checks added after the injected-
  defect measurement (audit part 7, K3: 1 of 13 lies caught before them)
- every declared `ParamMeta.default` compiles to the map omitting the
  parameter compiles to, for EVERY non-required key that declares one, the
  example's or not (`_check_declared_defaults!`; the counts come back as
  `default_pairs` and `defaults_checked`, equal on a clean tree, and
  `defaults_on_required_base`, the keys compared on the example's required
  parameters alone because the constructor refuses the default beside the
  example's folded twin)
- a discrete (non-numeric) default lies within its declared `alternatives`
- the description, the keywords, the construction help and every parameter
  meaning are non-empty: the free text `element_help` and the registry hand
  to a reader
- every kind's placement entries (`_PLACEMENT_PARAM_KEYS`, plus `name` and
  `numeric_type` where declared) agree with `_PLACEMENT_PARAMS` in
  `required`, `unit`, `default` and `alternatives`; only the meaning may be
  the kind's own, through `_placement_param`
- `default_method` and the example's `tracking_method` answer a declared
  method, and refuse by name for a kind that declares none

The last five landed with the 2026-10-20 fix batch (2026-10-18 comprehensive
audit, F-168, F-171, F-172, F-174: each was shown validating a wrong entry
clean before it landed).
"""
function validate_element_metadata(; throw_on_error::Bool=false)
    errors = String[]
    seen_kinds = Set{Symbol}()
    default_pairs = 0
    defaults_checked = 0
    defaults_on_required_base = Tuple{Symbol,Symbol}[]

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

        schema = parameter_schema(T)
        for (key, pmeta) in pairs(schema)
            if pmeta isa ParamMeta
                # The unit is drawn from a controlled vocabulary, for the same
                # reason the keywords above are: it drives behaviour. See
                # `ALLOWED_PARAM_UNITS`. Measured when this landed: the whole
                # registry declares only "m", "rad" and "Hz", so this passes on
                # a correct tree and bites on the next typo.
                pmeta.unit in ALLOWED_PARAM_UNITS || push!(errors,
                    "ElementMeta $(meta.kind) parameter $(key) declares " *
                    "unrecognised unit $(repr(pmeta.unit)); allowed: " *
                    join(sort!(collect(ALLOWED_PARAM_UNITS)), ", "))
                if pmeta.required && pmeta.default !== nothing
                    push!(errors, "ElementMeta $(meta.kind) parameter $(key) is required but has a default")
                end
                # The per-parameter free text: `meaning` is what `element_help`
                # prints beside the key and the only prose a reader has for it;
                # an empty one validated clean (2026-10-18 comprehensive audit,
                # F-172 / U25-9).
                isempty(pmeta.meaning) && push!(errors,
                    "ElementMeta $(meta.kind) parameter $(key) has an empty meaning")
                # A discrete default lies within its declared alternatives: for
                # a Symbol (or a type, `numeric_type`) the alternatives ARE the
                # enum, and a default outside it is a value the parameter does
                # not take (`misalign_convention = :elegant` against
                # `(:bmad, :madx)` validated clean; F-172 / U25-8). A NUMERIC
                # default is exempt because alternatives mean something else
                # there -- hand-picked perturbation values for the effectiveness
                # sweep, which the aperture's `Inf` limits deliberately sit
                # outside of (U4-1). `Bool <: Number`, so a flag is exempt too;
                # its perturbation is its negation.
                if !isempty(pmeta.alternatives) && pmeta.default !== nothing &&
                   !(pmeta.default isa Number) && !(pmeta.default in pmeta.alternatives)
                    push!(errors,
                        "ElementMeta $(meta.kind) parameter $(key) declares default " *
                        "$(repr(pmeta.default)) outside its alternatives $(pmeta.alternatives)")
                end
                if pmeta.required && example isa ElementSpec && !hasparam(example, key)
                    push!(errors, "ElementMeta $(meta.kind) example is missing required parameter $(key)")
                end
                # Word boundaries, not a bare substring (2026-08-05_b audit,
                # U12-5). `occursin(string(key), help)` is satisfied by any
                # accidental substring, and for short parameter names almost any
                # English sentence contains one: with schema keys `a` and `b`,
                # the help text "Absolutely tracking_method." mentions neither
                # and passed. A check that a one-letter name cannot fail is not
                # a check.
                _help_mentions_parameter(construction_help(T), key) ||
                    push!(errors, "ElementMeta $(meta.kind) construction_help does not mention parameter $(key)")
            end
        end

        # The kind-level free text. The description is what `description(T)`,
        # `element_help` and the registry snapshot hand to anyone asking what
        # the kind is, the keywords are how an agent finds it, the construction
        # help is how it is built; each validated clean when empty (2026-10-18
        # comprehensive audit, F-172 / U25-9). The non-element registry types
        # have had the "Every registry type describes itself" tripwire since
        # U12-17; the element side had none.
        isempty(meta.description) &&
            push!(errors, "ElementMeta $(meta.kind) has an empty description")
        isempty(meta.keywords) &&
            push!(errors, "ElementMeta $(meta.kind) declares no physics keywords")
        isempty(meta.construction_help) &&
            push!(errors, "ElementMeta $(meta.kind) has an empty construction_help")

        # Every kind's placement entries against the ONE table they are meant to
        # be spliced from. `compile_runtime`'s wraps read these keys for every
        # kind, the effectiveness contract perturbs a Symbol one from the
        # table's `alternatives`, and `element_help` prints the table's units --
        # so a kind that writes its own copies (13 did, and 79 of those copies
        # had drifted: every unit lost, seven kinds' `misalign_convention`
        # without the alternatives that make it perturbable at all; 2026-10-18
        # comprehensive audit, F-171) is held to the table's `required`,
        # `unit`, `default` and `alternatives`, while its `meaning` may say more
        # (`_placement_param(key; meaning=...)` is the spelling for that). A
        # kind with a schema must declare every placement key: an undeclared
        # one is a key the unknown-key warning reports as untracked while the
        # compile reads it (the U13-2 shape). `name` and `numeric_type` are
        # held to the table where declared (`:line` declares no numeric type:
        # a composite's type is its placements').
        if !isempty(keys(schema))
            for (key, ref) in pairs(_PLACEMENT_PARAMS)
                if !haskey(schema, key)
                    key in _PLACEMENT_PARAM_KEYS && push!(errors,
                        "ElementMeta $(meta.kind) does not declare the placement parameter " *
                        "$(key), which compile_runtime consumes for every kind; splice " *
                        "_PLACEMENT_PARAMS... into its schema")
                    continue
                end
                entry = schema[key]
                entry isa ParamMeta || continue
                (entry.required == ref.required && entry.unit == ref.unit &&
                 isequal(entry.default, ref.default) && entry.alternatives == ref.alternatives) ||
                    push!(errors,
                        "ElementMeta $(meta.kind) placement parameter $(key) departs from " *
                        "_PLACEMENT_PARAMS (required $(entry.required) vs $(ref.required), unit " *
                        "$(repr(entry.unit)) vs $(repr(ref.unit)), default $(repr(entry.default)) " *
                        "vs $(repr(ref.default)), alternatives $(entry.alternatives) vs " *
                        "$(ref.alternatives)); declare it through _placement_param(key; " *
                        "meaning=...) so that only the meaning is the kind's own")
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
        #
        # EVERY declared default, not only the ones the example sets: the loop
        # used to skip a key the example left at its default, which was 531 of
        # 608 pairs (2026-10-18 comprehensive audit, F-168). The counts are
        # returned so a skip is visible as `defaults_checked < default_pairs`.
        counts = _check_declared_defaults!(errors, T, meta, example)
        default_pairs += counts.pairs
        defaults_checked += counts.checked
        append!(defaults_on_required_base, counts.on_required_base)

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
        for method in meta.tracking_methods
            (method isa Type && method <: AbstractTrackingMethod) ||
                push!(errors, "ElementMeta $(meta.kind) declares tracking method $(method), which is not an AbstractTrackingMethod")
            haskey(meta.runtime_types, method) ||
                push!(errors, "ElementMeta $(meta.kind) has no runtime type for $(method)")
        end
        # ... and the other direction: every runtime-type entry is a declared
        # tracking method. `compile_runtime` gates on the runtime map alone, so
        # an entry the method list does not carry is a method the kind compiles
        # under while `supported_tracking_methods`, the Twiss-rule tripwire and
        # the registry snapshot all deny it (2026-10-18 comprehensive audit,
        # F-172 / U25-5: `Damping6DMap => LatticeMagnet` added to the drift's
        # map validated clean and compiled; an emptied method list over an
        # intact map validated clean too).
        for method in keys(meta.runtime_types)
            method in meta.tracking_methods || push!(errors,
                "ElementMeta $(meta.kind) maps $(method) to a runtime type but does not " *
                "declare it in tracking_methods; compile_runtime would honour a method " *
                "the registry denies")
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

        # The registry's method ANSWERS agree with its method LIST: a declared
        # method from `default_method(T)` and `tracking_method(example)` on a
        # kind that declares methods, a refusal by name on a kind that declares
        # none, as `compile_runtime(spec, method)` refuses. The line answered
        # `Symplectic6DMap()` to both queries while its compile refused that
        # very request (2026-10-18 comprehensive audit, F-174).
        _check_method_answers!(errors, T, meta, example)

        friendly = meta.friendly_constructor
        if friendly !== nothing
            # These were three TAUTOLOGIES until 2026-09-07 (2026-08-06 audit,
            # U12-8). They compared `parameter_schema(T)` with
            # `parameter_schema(friendly)`, `construction_help(T)` with
            # `construction_help(friendly)`, and the two examples' kinds -- and
            # every one of those accessors is `_element_meta_or_nothing(x)`
            # followed by a field read (:746-754, :779-787, :762-770). `T` is
            # registered in `ELEMENT_META_BY_SPEC_TYPE` and `friendly` in
            # `ELEMENT_META_BY_FRIENDLY_TYPE` pointing at the SAME `ElementMeta`
            # object, so all three compared one field of one object with itself.
            # They could not fail for any content, correct or not, while their
            # messages claimed the friendly constructor had been checked against
            # the raw spec. A check that executes and cannot fail is worse than
            # an unrun one, because it reads as coverage.
            #
            # Replaced by two whose sides come from different places.
            #
            # (1) The table binding, stated honestly rather than implied. It CAN
            # fail: a second `@element_spec` block naming the same
            # `friendly_constructor`, or `register_friendly_alias!` (:448-452)
            # onto a type another block already declared, rebinds
            # `ELEMENT_META_BY_FRIENDLY_TYPE` and the last write wins.
            resolved = _element_meta_or_nothing(friendly)
            resolved === meta || push!(errors,
                "ElementMeta $(meta.kind) friendly_constructor $(friendly) resolves to " *
                (resolved === nothing ? "no ElementMeta" : "ElementMeta $(resolved.kind)") *
                "; a second @element_spec block or register_friendly_alias! claimed it")
            # (2) What the constructor actually BUILDS -- the non-circular half,
            # and the check the old three only claimed to be. `kind` reads the
            # spec's type parameter (:610) and a friendly constructor hardcodes
            # its own `ElementSpec{k}`; neither consults `ELEMENT_META_BY_*`, so
            # these two sides can genuinely differ. It is the same move this
            # file already makes for the example at :1124-1130 ("the
            # non-circular consumer check: the example must actually compile").
            #
            # Measured before enabling, over the whole registry: 31 friendly
            # constructors, all build from their own example's parameters, all
            # yield the declared kind -- so this passes on a correct tree and is
            # not a latent gate break.
            if example isa ElementSpec
                built = try
                    friendly(; params(example)...)
                catch err
                    push!(errors,
                        "ElementMeta $(meta.kind) friendly_constructor $(friendly) does not " *
                        "build from its own example's parameters: $(sprint(showerror, err))")
                    nothing
                end
                built === nothing || kind(built) == meta.kind || push!(errors,
                    "ElementMeta $(meta.kind) friendly_constructor $(friendly) builds " *
                    "$(kind(built)), not the declared $(meta.kind)")
            end
        end
    end

    result = (passed=isempty(errors), errors=errors, default_pairs=default_pairs,
              defaults_checked=defaults_checked,
              defaults_on_required_base=defaults_on_required_base)
    if throw_on_error && !result.passed
        throw(ArgumentError("element metadata validation failed:\n" * join(errors, "\n")))
    end
    return result
end

"""
    tracking_method(spec)

Return the tracking method selected by an element spec. `ElementSpec` values
may carry `:tracking_method` in their flexible parameter dictionary; otherwise
the element's `default_method` is used -- which refuses by name for a kind that
declares no tracking method (the composite `:line`), so this query never
answers a method `compile_runtime(spec, method)` would reject (2026-10-18
comprehensive audit, F-174).
"""
tracking_method(spec::AbstractElementSpec) = _tracking_method_object(default_method(spec))
function tracking_method(spec::ElementSpec)
    # The stored method first and `default_method` only when there is none:
    # `getparam(spec, :tracking_method, default_method(spec))` evaluated the
    # fallback eagerly, and the fallback refuses for a method-less kind.
    stored = getparam(spec, :tracking_method, nothing)
    return _tracking_method_object(stored === nothing ? default_method(spec) : stored)
end

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
    #
    # Turn-by-turn modulation wraps INNERMOST (`docs/design/turn_modulation.md`,
    # section 4.2): the modulated quantity is the element's OWN parameter (a
    # crab cavity's RF phase or strength), while the other two wraps act on the
    # frame around the element, so the realised element must sit inside the
    # frame transforms. `_turn_modulation_wrap` (`src/elements/turn_modulated.jl`)
    # is the identity for every kind that declares no rule parameters.
    return _ref_tilt_wrap(resolved,
                          _misalignment_wrap(resolved,
                              _turn_modulation_wrap(resolved, T(resolved, method_object))))
end

# Generic fallback: specs without knob parameters pass through unchanged. The
# `ElementSpec` method that evaluates knob expressions lives in
# `src/knobs/Knobs.jl` (included after this file).
resolve_knobs(spec) = spec
