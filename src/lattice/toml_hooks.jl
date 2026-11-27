# The snapshot codec for the objects a line holds beside its elements (design
# D6 and D13): in-line hooks (`ScheduledObserver`, `ScheduledAction`), the
# collision markers with their solvers, the schedules, the solvers' nested
# option objects, and the turn rules. Included after the tasks, whose types
# these methods name; the codec's dispatch points and the element rules live
# in src/lattice/toml.jl.
#
# Every type here is registered in `_TOML_OBJECT_TYPES` beside its methods
# (`_toml_register_object!`); the three function-holding types are refused by name and
# listed by `_toml_refused_object_types()`, which the suite's tripwire reads.
# Option values go through `_toml_option_encode` / `_toml_option_decode`,
# typed by the schemas' `option_type`, so no type marker is written that a
# schema already states.

"""
    _toml_register_object!(T::Type) -> T

Register `T` in `_TOML_OBJECT_TYPES` under `string(nameof(T))`, the name its
snapshot tables carry as `type = "<name>"`; a parametric type registers its
`UnionAll` (`WhiteNoise`, not `WhiteNoise{Float64}`), which is what
`nameof(typeof(x))` names for every instance. A second registration of one
name must be the same type: two types sharing a name could not be told apart
on reading, so that is refused.
"""
function _toml_register_object!(T::Type)
    key = string(nameof(T))
    existing = get(_TOML_OBJECT_TYPES, key, nothing)
    (existing === nothing || existing === T) || throw(ArgumentError(
        "machine snapshot: the object type name \"$(key)\" is already registered for " *
        "$(existing) and cannot also name $(T)"))
    _TOML_OBJECT_TYPES[key] = T
    return T
end

"""
    _toml_option_encode(v, ctx::_TomlContext)

The option-value rules of the hook, marker, solver, schedule and rule tables
(the format's "Hooks, markers and solvers" rule): the TOML value of one option
value, whose type the reader knows from the type's option schema, so the
encoding carries no type marker a schema already states. `nothing` is the
inline table `{ nothing = true }` as the element value rules spell it (the
emitter's inline-table form); a `Symbol` is a bare string (the schema
says it is a symbol); an integer prints as a decimal TOML integer (`UInt64`
stream ids included; one outside the signed 64-bit range TOML can hold is
refused by name); a float as its `Float64` value; a tuple or vector as an
array of its values; a set as the sorted array of its values; any other
object (a nested slicing, a schedule, a virtual drift, a launch
configuration, a solver) through `_toml_encode_object`, whose fallback
refuses by name what nothing registered; a number of another class through
the element value rules (`_toml_encode_value`), which refuse what they do not
cover.
"""
_toml_option_encode(::Nothing, ctx::_TomlContext) = _toml_encode_value(nothing, nothing, ctx)
_toml_option_encode(v::Bool, ctx::_TomlContext) = v
function _toml_option_encode(v::Integer, ctx::_TomlContext)
    (v >= typemin(Int64) && v <= typemax(Int64)) || _toml_refuse(ctx,
        "the integer $(v) is outside the signed 64-bit range a TOML integer can hold")
    return Int64(v)
end
_toml_option_encode(v::AbstractFloat, ctx::_TomlContext) = Float64(v)
_toml_option_encode(v::Number, ctx::_TomlContext) = _toml_encode_value(v, nothing, ctx)
_toml_option_encode(v::Symbol, ctx::_TomlContext) = String(v)
_toml_option_encode(v::AbstractString, ctx::_TomlContext) = String(v)
_toml_option_encode(v::Union{Tuple,AbstractVector}, ctx::_TomlContext) =
    Any[_toml_option_encode(e, _toml_at(ctx, "[$(i)]")) for (i, e) in enumerate(v)]
_toml_option_encode(v::AbstractSet, ctx::_TomlContext) =
    Any[_toml_option_encode(e, _toml_at(ctx, "[$(i)]")) for (i, e) in enumerate(sort!(collect(v)))]
_toml_option_encode(v, ctx::_TomlContext) = _toml_encode_object(v, ctx)

"""
    _toml_option_decode(x, T::Type, ctx::_TomlContext)

Read one option value written by `_toml_option_encode` back as a value of
the option's declared type `T` (the schema's `option_type`, a `Union` allowed):
the member of `T` that admits the TOML value's class decides the Julia class.
`{ nothing = true }` is `nothing` where `T` admits it; a table with `type`
is an object through `_toml_decode_object`, checked against `T`; another
inline table (`{ expr = ... }`, `{ symbol = ... }`, `{ tuple = [...] }`) goes
through the element value rules; a string is a `Symbol` where `T` admits one
and a `String` otherwise; an integer becomes the integer member (`Int`,
`UInt64`), the float member when only a float is admitted, and stays an
integer under `Real`; a float needs a float-admitting member (an integer
option refuses a float by name); an array becomes a tuple, a set or a
vector, by the member admitting it, each element decoded by the member's
element type. Every mismatch is refused by name with the declared type.
"""
function _toml_option_decode(x, T::Type, ctx::_TomlContext)
    # The emitter's inline-table form, met when a table is decoded straight
    # from an encoder's output rather than from parsed text.
    x isa _TomlTable && return _toml_option_decode(Dict{String,Any}(x.pairs), T, ctx)
    members = Base.uniontypes(T)
    admits(pred) = findfirst(pred, members)
    if x isa AbstractDict
        if haskey(x, "nothing")
            Nothing in members || _toml_refuse(ctx, "nothing where a value of type $(T) belongs")
            return nothing
        elseif haskey(x, "type")
            obj = _toml_decode_object(x, ctx)
            obj isa T || _toml_refuse(ctx,
                "a $(nameof(typeof(obj))) where a value of type $(T) belongs")
            return obj
        else
            v = _toml_decode_value(x, nothing, ctx)
            v isa T || _toml_refuse(ctx, "a $(typeof(v)) where a value of type $(T) belongs")
            return v
        end
    elseif x isa Bool
        admits(S -> Bool <: S) === nothing && _toml_refuse(ctx,
            "a boolean where a value of type $(T) belongs")
        return x
    elseif x isa Integer
        int_index = something(admits(S -> S !== Bool && S <: Integer), admits(S -> Integer <: S),
                              admits(S -> S <: AbstractFloat), 0)
        int_index == 0 && _toml_refuse(ctx, "the integer $(x) where a value of type $(T) belongs")
        IntMember = members[int_index]
        return (IntMember <: Integer || IntMember <: AbstractFloat) ? IntMember(x) : x
    elseif x isa AbstractFloat
        float_index = something(admits(S -> S <: AbstractFloat), admits(S -> AbstractFloat <: S), 0)
        float_index == 0 && _toml_refuse(ctx, "the float $(x) where a value of type $(T) belongs")
        FloatMember = members[float_index]
        return FloatMember <: AbstractFloat ? FloatMember(x) : x
    elseif x isa AbstractString
        admits(S -> Symbol <: S) === nothing || return Symbol(x)
        admits(S -> String <: S) === nothing || return String(x)
        _toml_refuse(ctx, "the string $(repr(x)) where a value of type $(T) belongs")
    elseif x isa AbstractVector
        tuple_index = admits(S -> S <: Tuple)
        if tuple_index !== nothing
            TupleMember = members[tuple_index]
            params = TupleMember === Tuple ? () : TupleMember.parameters
            n = length(x)
            (isempty(params) || (length(params) == n && !any(p -> p isa Core.TypeofVararg, params))) ||
                _toml_refuse(ctx, "an array of $(n) values where a $(TupleMember) belongs")
            return Tuple(_toml_option_decode(x[k], isempty(params) ? Any : params[k], _toml_at(ctx, "[$(k)]"))
                         for k in 1:n)
        end
        set_index = admits(S -> S <: AbstractSet)
        if set_index !== nothing
            set_eltype = eltype(members[set_index])
            return Set(_toml_option_decode(e, set_eltype, _toml_at(ctx, "[$(k)]")) for (k, e) in enumerate(x))
        end
        vector_index = admits(S -> S <: AbstractVector || AbstractVector <: S)
        vector_index === nothing && _toml_refuse(ctx, "an array where a value of type $(T) belongs")
        vec_eltype = members[vector_index] <: AbstractVector ? eltype(members[vector_index]) : Any
        decoded = Any[_toml_option_decode(e, vec_eltype, _toml_at(ctx, "[$(k)]")) for (k, e) in enumerate(x)]
        return vec_eltype === Any ? decoded : convert(Vector{vec_eltype}, decoded)
    end
    _toml_refuse(ctx, "a $(typeof(x)) value where a value of type $(T) belongs")
end

"""
    _toml_schema_table(x, schema::NamedTuple, values, ctx::_TomlContext) -> Dict{String,Any}

The table of an object printed by its option schema: `type = "<name>"` and,
for every schema key, `values[key]` through `_toml_option_encode` (`values`
is the object itself when its options are its fields, as for the observers
and schedules, and `solver_configuration(solver)` for a solver, whose
`slicing1`/`slicing2` fields hold the RESOLVED slicings while the schema
keys name the requested ones). Only schema keys print: a `resolved_*` entry
of a solver's configuration is derived, never stored.
"""
function _toml_schema_table(x, schema::NamedTuple, values, ctx::_TomlContext)
    tbl = Dict{String,Any}("type" => string(nameof(typeof(x))))
    for key in keys(schema)
        name = string(key)
        tbl[name] = _toml_option_encode(getproperty(values, key), _toml_at(ctx, name))
    end
    return tbl
end

"""
    _toml_schema_kwargs(T::Type, schema::NamedTuple, tbl::AbstractDict, ctx::_TomlContext) -> Dict{Symbol,Any}

The keyword arguments a schema-typed object is rebuilt from: every key of
`tbl` but `type`, in sorted order, decoded by its schema entry's
`option_type` through `_toml_option_decode`. A key the schema does not
declare is refused by name with the declared keys listed; a declared key the
table omits is left to the constructor's default, exactly as the keyword it
stands for would be.
"""
function _toml_schema_kwargs(T::Type, schema::NamedTuple, tbl::AbstractDict, ctx::_TomlContext)
    kwargs = Dict{Symbol,Any}()
    for key in sort!(collect(keys(tbl)))
        key == "type" && continue
        sym = Symbol(key)
        haskey(schema, sym) || _toml_refuse(ctx,
            "unknown key \"$(key)\" for $(nameof(T)); the keys are: " *
            join(string.(keys(schema)), ", "))
        kwargs[sym] = _toml_option_decode(tbl[key], getproperty(schema, sym).option_type,
                                          _toml_at(ctx, key))
    end
    return kwargs
end

# ---------------------------------------------------------------------------
# In-line hooks (D6): the scheduled wrappers, each an object sub-table and a
# schedule sub-table.
# ---------------------------------------------------------------------------

"""
    _toml_encode_object(x::ScheduledObserver, ctx)
    _toml_decode_object(::Type{<:ScheduledObserver}, tbl, ctx)

An in-line observer hook: `type = "ScheduledObserver"`, `observer` the
observer's own table and `schedule` the schedule's, each by its type's
rules. Rebuilt as `ScheduledObserver(observer, schedule)`; a missing
sub-table, a key other than the two, or a sub-table that decodes to
something other than an observer or a schedule is refused by name.
"""
function _toml_encode_object(x::ScheduledObserver, ctx::_TomlContext)
    return Dict{String,Any}(
        "type" => "ScheduledObserver",
        "observer" => _toml_encode_object(x.observer, _toml_at(ctx, "observer")),
        "schedule" => _toml_encode_object(x.schedule, _toml_at(ctx, "schedule")),
    )
end
function _toml_decode_object(::Type{<:ScheduledObserver}, tbl::AbstractDict, ctx::_TomlContext)
    observer = _toml_hook_part(tbl, "observer", AbstractBeamObserver, "ScheduledObserver", ctx)
    schedule = _toml_hook_part(tbl, "schedule", AbstractSchedule, "ScheduledObserver", ctx)
    return ScheduledObserver(observer, schedule)
end
_toml_register_object!(ScheduledObserver)

"""
    _toml_hook_part(tbl, key, ::Type{T}, owner, ctx) -> T

One sub-table of a scheduled hook (`observer`, `action` or `schedule`)
decoded through `_toml_decode_object` and checked to be a `T`, after the
hook's keys (`type`, the object key, `schedule`) are checked and an unknown
one refused by name. `owner` names the hook type in messages.
"""
function _toml_hook_part(tbl::AbstractDict, key::AbstractString, ::Type{T}, owner::AbstractString,
                         ctx::_TomlContext) where {T}
    object_key = owner == "ScheduledAction" ? "action" : "observer"
    for k in sort!(collect(keys(tbl)))
        k in ("type", object_key, "schedule") || _toml_refuse(ctx,
            "unknown key \"$(k)\" for $(owner); the keys are: $(object_key), schedule")
    end
    haskey(tbl, key) || _toml_refuse(ctx, "$(owner) needs a `$(key)` table and has none")
    part = tbl[key]
    part isa AbstractDict && haskey(part, "type") || _toml_refuse(_toml_at(ctx, key),
        "$(owner).$(key) must be a table with a `type`")
    value = _toml_decode_object(part, _toml_at(ctx, key))
    value isa T || _toml_refuse(_toml_at(ctx, key),
        "$(owner).$(key) decoded to a $(nameof(typeof(value))), not a $(nameof(T))")
    return value
end

"""
    _toml_encode_object(x::ScheduledAction, ctx)
    _toml_decode_object(::Type{<:ScheduledAction}, tbl, ctx)
    _toml_encode_object(x::AbstractBeamAction, ctx)

An in-line action hook: `type = "ScheduledAction"`, `action` the action's
table and `schedule` the schedule's, rebuilt as `ScheduledAction(action,
schedule)` under the checks of `_toml_hook_part`. `ReferenceRamp` has its own
rules below; `BeamSwapAction` holds the function that provides the
replacement beam and is refused by name (it is on
`_toml_refused_object_types`), and an action of any other type is refused as
having no option schema to print by.
"""
function _toml_encode_object(x::ScheduledAction, ctx::_TomlContext)
    return Dict{String,Any}(
        "type" => "ScheduledAction",
        "action" => _toml_encode_object(x.action, _toml_at(ctx, "action")),
        "schedule" => _toml_encode_object(x.schedule, _toml_at(ctx, "schedule")),
    )
end
function _toml_decode_object(::Type{<:ScheduledAction}, tbl::AbstractDict, ctx::_TomlContext)
    action = _toml_hook_part(tbl, "action", AbstractBeamAction, "ScheduledAction", ctx)
    schedule = _toml_hook_part(tbl, "schedule", AbstractSchedule, "ScheduledAction", ctx)
    return ScheduledAction(action, schedule)
end
_toml_register_object!(ScheduledAction)
_toml_encode_object(x::BeamSwapAction, ctx::_TomlContext) = _toml_refuse(ctx,
    "a BeamSwapAction holds the function `provider` that supplies the replacement " *
    "beam and cannot be snapshotted; place the action from code when the machine is reloaded")
_toml_encode_object(x::AbstractBeamAction, ctx::_TomlContext) = _toml_refuse(ctx,
    "a $(nameof(typeof(x))) action has no option schema to print by and cannot be snapshotted")

"""
    _toml_encode_object(x::ReferenceRamp, ctx)
    _toml_decode_object(::Type{<:ReferenceRamp}, tbl, ctx)

The ramp action (docs/theory/reference_ramp.md): `type = "ReferenceRamp"`,
`reference` the reference particle's table (`_toml_reference_table`, its
energy the knob expression), `start_turn`, `name` (left out when empty),
`program = { sha256, length }` the energy program as a bulk table by digest
(`_toml_store_table!`; the sidecar and the artifact's `/machine_tables` hold
it) and `companions`, an array of `{ knob, program = { sha256, length } }`,
left out when there are none. Read back through the constructor, which
recomputes the digests the text carries; a table whose digest differs from
the text's is refused by the table seam (`_toml_table`), a `length` that
does not match the table, an unknown key, a missing part and the
constructor's own refusals by name with the table's path.
"""
function _toml_encode_object(x::ReferenceRamp, ctx::_TomlContext)
    tbl = Dict{String,Any}(
        "type" => "ReferenceRamp",
        "reference" => _toml_reference_table(x.reference, _toml_at(ctx, "reference")),
        "start_turn" => Int64(x.start_turn),
        "program" => _toml_ramp_program_table(x.program, _toml_at(ctx, "program")),
    )
    isempty(x.name) || (tbl["name"] = x.name)
    if !isempty(x.companions)
        tbl["companions"] = Any[
            _TomlTable("knob" => String(c.knob),
                       "program" => _toml_ramp_program_table(c.program, _toml_at(ctx, "companions")))
            for c in x.companions]
    end
    return tbl
end
_toml_ramp_program_table(program::Vector{Float64}, ctx::_TomlContext) =
    _TomlTable("sha256" => _toml_store_table!(ctx, program), "length" => length(program))
# The direct round trip (encode, then decode without a text in between, as the
# suite's tripwire does) hands the decoder the encoder's inline tables; the
# parsed text hands it dictionaries. Both read as dictionaries here.
_toml_ramp_plain(x) = x
_toml_ramp_plain(t::_TomlTable) = Dict{String,Any}(k => _toml_ramp_plain(v) for (k, v) in t.pairs)
function _toml_ramp_program(tbl::AbstractDict, key::AbstractString, ctx::_TomlContext)
    p = _toml_ramp_plain(get(tbl, key, nothing))
    p isa AbstractDict || _toml_refuse(ctx,
        "ReferenceRamp needs `$(key) = { sha256 = \"...\", length = n }`, the program as a bulk table by digest")
    pctx = _toml_at(ctx, key)
    _toml_only_keys(p, ("sha256", "length"), :ReferenceRamp, pctx)
    (haskey(p, "sha256") && p["sha256"] isa AbstractString) || _toml_refuse(pctx,
        "`$(key)` needs `sha256`, the table's digest as a string")
    data = _toml_table(pctx, p["sha256"])
    if haskey(p, "length")
        n = p["length"]
        (n isa Integer && !(n isa Bool) && n == length(data)) || _toml_refuse(pctx,
            "`length` = $(repr(n)) does not match the table's $(length(data)) entries")
    end
    return data
end
function _toml_decode_object(::Type{<:ReferenceRamp}, tbl::AbstractDict, ctx::_TomlContext)
    _toml_only_keys(tbl, ("type", "reference", "start_turn", "name", "program", "companions"),
                    :ReferenceRamp, ctx)
    ref_tbl = _toml_ramp_plain(get(tbl, "reference", nothing))
    ref_tbl isa AbstractDict || _toml_refuse(ctx, "ReferenceRamp needs a `reference` table")
    reference = _toml_decode_reference(ref_tbl, _toml_at(ctx, "reference"))
    program = _toml_ramp_program(tbl, "program", ctx)
    start_turn = get(tbl, "start_turn", 0)
    (start_turn isa Integer && !(start_turn isa Bool)) || _toml_refuse(_toml_at(ctx, "start_turn"),
        "`start_turn` must be an integer; got $(repr(start_turn))")
    name = get(tbl, "name", "")
    name isa AbstractString || _toml_refuse(_toml_at(ctx, "name"), "`name` must be a string; got $(repr(name))")
    companions = Pair{Symbol,Vector{Float64}}[]
    if haskey(tbl, "companions")
        raw = tbl["companions"]
        raw isa AbstractVector || _toml_refuse(_toml_at(ctx, "companions"),
            "`companions` must be an array of { knob, program } tables; got $(repr(raw))")
        for (i, c) in enumerate(raw)
            cctx = _toml_at(ctx, "companions[$(i)]")
            c = _toml_ramp_plain(c)
            c isa AbstractDict || _toml_refuse(cctx, "a companion must be a { knob, program } table; got $(repr(c))")
            _toml_only_keys(c, ("knob", "program"), :ReferenceRamp, cctx)
            (haskey(c, "knob") && c["knob"] isa AbstractString) || _toml_refuse(cctx,
                "a companion needs `knob`, the knob path as a string")
            push!(companions, Symbol(c["knob"]) => _toml_ramp_program(c, "program", cctx))
        end
    end
    return _toml_construct(ctx, :ReferenceRamp) do
        ReferenceRamp(program; reference, start_turn=Int(start_turn), name=String(name),
                      companions=Tuple(companions))
    end
end
_toml_register_object!(ReferenceRamp)

# ---------------------------------------------------------------------------
# Collision markers with the solver on them.
# ---------------------------------------------------------------------------

"""
    _toml_encode_object(x::StrongStrongCollision, ctx)
    _toml_decode_object(::Type{<:StrongStrongCollision}, tbl, ctx)

A collision marker: `type = "StrongStrongCollision"`, `label` the pairing
label as a string, `poisson_solver` the solver's table by its option schema
or `{ nothing = true }` for a marker without one. Rebuilt as
`StrongStrongCollision(Symbol(label); poisson_solver)`; a missing label, an
unknown key, or a `poisson_solver` that is neither a solver nor `nothing` is
refused by name. Two lattices placing ONE marker object write one table
referenced twice (the line codec keeps object identity); the task pairs
markers by label and compares their solvers by configuration, so a reloaded
marker pairs as the original did.
"""
function _toml_encode_object(x::StrongStrongCollision, ctx::_TomlContext)
    solver = x.poisson_solver
    return Dict{String,Any}(
        "type" => "StrongStrongCollision",
        "label" => String(x.label),
        "poisson_solver" => solver === nothing ? Dict{String,Any}("nothing" => true) :
                            _toml_encode_object(solver, _toml_at(ctx, "poisson_solver")),
    )
end
function _toml_decode_object(::Type{<:StrongStrongCollision}, tbl::AbstractDict, ctx::_TomlContext)
    for k in sort!(collect(keys(tbl)))
        k in ("type", "label", "poisson_solver") || _toml_refuse(ctx,
            "unknown key \"$(k)\" for StrongStrongCollision; the keys are: label, poisson_solver")
    end
    haskey(tbl, "label") || _toml_refuse(ctx, "StrongStrongCollision needs a `label` and has none")
    label = tbl["label"]
    label isa AbstractString || _toml_refuse(_toml_at(ctx, "label"),
        "StrongStrongCollision.label must be a string; got a $(typeof(label))")
    solver = _toml_option_decode(get(tbl, "poisson_solver", Dict{String,Any}("nothing" => true)),
                                 Union{Nothing,AbstractPoissonSolver}, _toml_at(ctx, "poisson_solver"))
    return StrongStrongCollision(Symbol(label); poisson_solver=solver)
end
_toml_register_object!(StrongStrongCollision)

# ---------------------------------------------------------------------------
# The Poisson solvers, by their option schemas.
# ---------------------------------------------------------------------------

"""
    _toml_solver_numeric_type(solver::AbstractPoissonSolver) -> Type

The solver's numeric type, the first type parameter of every solver type
(`PICPoissonSolver{T}`, `GaussianPoissonSolver{T,D,Coupled,Longitudinal}`,
`SpectralPoissonSolver{T}`, `GaussianPICPoissonSolver{T}`): the type its
keyword constructor `Solver{T}(; ...)` is called with.
"""
_toml_solver_numeric_type(solver::AbstractPoissonSolver) = typeof(solver).parameters[1]

"""
    _toml_encode_object(x::AbstractPoissonSolver, ctx)
    _toml_decode_object(::Type{S}, tbl, ctx) where {S<:AbstractPoissonSolver}

A solver by its `solver_option_schema`: `type = "<name>"` and every schema
key with its REQUESTED value from `solver_configuration` (`slicing1` and
`slicing2` are the overrides as given, `nothing` when none was; the
configuration's `resolved_*` entries are derived and never printed), nested
option objects (a `LongitudinalSlicing`, a schedule, a virtual drift, a
`CUDAPICLaunchConfig` in `backend_configurations`) recursively by theirs.
Rebuilt as `S{ctx.numeric_type}(; options...)`, the keyword constructor the
schema keys name (pinned by `validate_configuration_metadata`), so the
lattice's numeric type types the solver: a solver whose own numeric type
differs from the lattice's is refused at write rather than retyped silently.
A solver type with an empty schema is refused by name; the four solvers are
registered below and the suite's tripwire, walking the solver type tree at
run time, refuses a concrete solver that is neither registered nor on the
refusal list. An option value the constructor refuses is refused with the
table's path and the constructor's message.
"""
function _toml_encode_object(x::AbstractPoissonSolver, ctx::_TomlContext)
    schema = solver_option_schema(x)
    isempty(schema) && _toml_refuse(ctx,
        "a $(nameof(typeof(x))) solver has no option schema to print by and cannot be snapshotted")
    T = _toml_solver_numeric_type(x)
    T === ctx.numeric_type || _toml_refuse(ctx,
        "the $(nameof(typeof(x))) solver's numeric type $(T) differs from the lattice's " *
        "$(ctx.numeric_type); the snapshot rebuilds a solver in the lattice's type, so build " *
        "the solver as $(nameof(typeof(x))){$(ctx.numeric_type)}(; ...) or the lattice in $(T)")
    return _toml_schema_table(x, schema, solver_configuration(x), ctx)
end
function _toml_decode_object(::Type{S}, tbl::AbstractDict, ctx::_TomlContext) where {S<:AbstractPoissonSolver}
    kwargs = _toml_schema_kwargs(S, solver_option_schema(S), tbl, ctx)
    return _toml_construct(ctx, nameof(S)) do
        S{ctx.numeric_type}(; kwargs...)
    end
end
# Registered by name beside the methods that read them, the four solvers
# with a schema; the type-tree walk that checks completeness is the suite's
# tripwire, which refuses a concrete solver that is neither registered here
# nor on `_toml_refused_object_types()`.
_toml_register_object!(GaussianPoissonSolver)
_toml_register_object!(PICPoissonSolver)
_toml_register_object!(SpectralPoissonSolver)
_toml_register_object!(GaussianPICPoissonSolver)

"""
    _toml_construct(build, ctx::_TomlContext, name::Symbol)

Run `build()`, the keyword constructor of a snapshotted object, and turn an
`ArgumentError` it throws (an option value it refuses) into the codec's
refusal at the table's path, keeping the constructor's message; any other
error propagates as it is.
"""
function _toml_construct(build, ctx::_TomlContext, name::Symbol)
    try
        return build()
    catch err
        err isa ArgumentError || rethrow()
        _toml_refuse(ctx, "$(name) refused its options: " * err.msg)
    end
end

# ---------------------------------------------------------------------------
# The solvers' nested option objects.
# ---------------------------------------------------------------------------

"""
    _toml_encode_object(x::LongitudinalSlicing, ctx)
    _toml_decode_object(::Type{LongitudinalSlicing}, tbl, ctx)
    _toml_encode_object(x::CUDAPICLaunchConfig, ctx)
    _toml_decode_object(::Type{CUDAPICLaunchConfig}, tbl, ctx)

The two option objects with schemas of their own (`slicing_option_schema`,
`cuda_pic_launch_option_schema`), printed by them (`positions` as an array
of floats, the thread counts as integers or `{ nothing = true }`) and rebuilt
through their keyword constructors.
"""
_toml_encode_object(x::LongitudinalSlicing, ctx::_TomlContext) =
    _toml_schema_table(x, slicing_option_schema(), x, ctx)
function _toml_decode_object(::Type{LongitudinalSlicing}, tbl::AbstractDict, ctx::_TomlContext)
    kwargs = _toml_schema_kwargs(LongitudinalSlicing, slicing_option_schema(), tbl, ctx)
    return _toml_construct(ctx, :LongitudinalSlicing) do
        LongitudinalSlicing(; kwargs...)
    end
end
_toml_register_object!(LongitudinalSlicing)
_toml_encode_object(x::CUDAPICLaunchConfig, ctx::_TomlContext) =
    _toml_schema_table(x, cuda_pic_launch_option_schema(), x, ctx)
function _toml_decode_object(::Type{CUDAPICLaunchConfig}, tbl::AbstractDict, ctx::_TomlContext)
    kwargs = _toml_schema_kwargs(CUDAPICLaunchConfig, cuda_pic_launch_option_schema(), tbl, ctx)
    return _toml_construct(ctx, :CUDAPICLaunchConfig) do
        CUDAPICLaunchConfig(; kwargs...)
    end
end
_toml_register_object!(CUDAPICLaunchConfig)

"""
    _toml_encode_object(x::AbstractVirtualDrift, ctx)
    _toml_decode_object(::Type{D}, tbl, ctx) where {D<:AbstractVirtualDrift}
    _toml_encode_object(x::UnsafeVirtualDrift, ctx)
    _toml_decode_object(::Type{<:UnsafeVirtualDrift}, tbl, ctx)

The soft-Gaussian solver's `virtual_drift`: a field-less drift model prints
as `{ type = "<name>" }` alone and is rebuilt as `D()`; an
`UnsafeVirtualDrift` prints `{ type = "UnsafeVirtualDrift", name = "<key>" }`
with its model's key in `_UNSAFE_VIRTUAL_DRIFT_TYPES` and is rebuilt through
`UnsafeVirtualDrift(Symbol(name))`, the documented route. Every concrete
drift type is registered below (the suite's tripwire walks the type tree).
Any key beside `type` (and `name` for the unsafe wrapper) is refused by name.
"""
function _toml_encode_object(x::AbstractVirtualDrift, ctx::_TomlContext)
    fieldcount(typeof(x)) == 0 || _toml_refuse(ctx,
        "a $(nameof(typeof(x))) virtual drift has fields and no option schema to print them by")
    return Dict{String,Any}("type" => string(nameof(typeof(x))))
end
function _toml_decode_object(::Type{D}, tbl::AbstractDict, ctx::_TomlContext) where {D<:AbstractVirtualDrift}
    _toml_only_keys(tbl, ("type",), nameof(D), ctx)
    return D()
end
function _toml_encode_object(x::UnsafeVirtualDrift, ctx::_TomlContext)
    i = findfirst(T -> x.model isa T, values(_UNSAFE_VIRTUAL_DRIFT_TYPES))
    i === nothing && _toml_refuse(ctx,
        "the UnsafeVirtualDrift model $(nameof(typeof(x.model))) has no name in _UNSAFE_VIRTUAL_DRIFT_TYPES")
    return Dict{String,Any}("type" => "UnsafeVirtualDrift",
                            "name" => String(keys(_UNSAFE_VIRTUAL_DRIFT_TYPES)[i]))
end
function _toml_decode_object(::Type{<:UnsafeVirtualDrift}, tbl::AbstractDict, ctx::_TomlContext)
    _toml_only_keys(tbl, ("type", "name"), :UnsafeVirtualDrift, ctx)
    haskey(tbl, "name") || _toml_refuse(ctx, "UnsafeVirtualDrift needs a `name` and has none")
    name = tbl["name"]
    name isa AbstractString || _toml_refuse(_toml_at(ctx, "name"),
        "UnsafeVirtualDrift.name must be a string; got a $(typeof(name))")
    return _toml_construct(ctx, :UnsafeVirtualDrift) do
        UnsafeVirtualDrift(Symbol(name))
    end
end
# By name, as the solvers above (the completeness walk is the suite's).
_toml_register_object!(HirataParaxialDrift)
_toml_register_object!(ChromaticDrift)
_toml_register_object!(ExactHamiltonianDrift)
_toml_register_object!(_ChromaticFrozenEnergyDrift)
_toml_register_object!(_ParaxialFrozenLongitudinalDrift)
_toml_register_object!(UnsafeVirtualDrift)

"""
    _toml_only_keys(tbl, allowed, name::Symbol, ctx)

Refuse by name any key of `tbl` outside `allowed`, listing the allowed keys
other than `type`, for the objects whose tables carry fixed keys rather than
a schema.
"""
function _toml_only_keys(tbl::AbstractDict, allowed, name::Symbol, ctx::_TomlContext)
    others = [a for a in allowed if a != "type"]
    for k in sort!(collect(keys(tbl)))
        k in allowed || _toml_refuse(ctx,
            "unknown key \"$(k)\" for $(name); " *
            (isempty(others) ? "it takes no key beside type" : "the keys are: " * join(others, ", ")))
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Schedules, by `schedule_option_schema`.
# ---------------------------------------------------------------------------

"""
    _toml_encode_object(x::AbstractSchedule, ctx)
    _toml_decode_object(::Type{AlwaysSchedule}, tbl, ctx)
    _toml_decode_object(::Type{EveryNSteps}, tbl, ctx)
    _toml_decode_object(::Type{AtTurns}, tbl, ctx)
    _toml_encode_object(x::PredicateSchedule, ctx)

A schedule by its `schedule_option_schema`: `AlwaysSchedule` is
`{ type = "AlwaysSchedule" }` alone, `EveryNSteps` prints `start`, `step` and
`stop` only when one was given (the default, `typemax(Int)`, "no stop", is
left out and read back as the constructor's default; R8d of the follow-ups
note, 2026-11-26, closing the audit's C-6, which saw `stop =
9223372036854775807` in every snapshot of a default schedule), `AtTurns`
prints `turns` as the sorted array of its set; rebuilt through
`EveryNSteps(; ...)` and `AtTurns(Set)`. A `PredicateSchedule` holds the predicate function and
is refused by name (on `_toml_refused_object_types`); a schedule type whose
schema declares a `Function` option is refused the same way.
"""
function _toml_encode_object(x::AbstractSchedule, ctx::_TomlContext)
    schema = schedule_option_schema(x)
    for (key, meta) in pairs(schema)
        meta.option_type === Function && _toml_refuse(ctx,
            "a $(nameof(typeof(x))) schedule holds the function `$(key)` and cannot be snapshotted")
    end
    tbl = _toml_schema_table(x, schema, x, ctx)
    # "No stop" is the constructor's default, not a number anyone typed.
    x isa EveryNSteps && x.stop == typemax(Int) && delete!(tbl, "stop")
    return tbl
end
_toml_encode_object(x::PredicateSchedule, ctx::_TomlContext) = _toml_refuse(ctx,
    "a PredicateSchedule holds the function `predicate` and cannot be snapshotted; " *
    "use EveryNSteps or AtTurns, or attach the predicate-scheduled hook from code when the " *
    "machine is reloaded")
function _toml_decode_object(::Type{AlwaysSchedule}, tbl::AbstractDict, ctx::_TomlContext)
    _toml_only_keys(tbl, ("type",), :AlwaysSchedule, ctx)
    return AlwaysSchedule()
end
function _toml_decode_object(::Type{EveryNSteps}, tbl::AbstractDict, ctx::_TomlContext)
    kwargs = _toml_schema_kwargs(EveryNSteps, schedule_option_schema(EveryNSteps), tbl, ctx)
    return _toml_construct(ctx, :EveryNSteps) do
        EveryNSteps(; kwargs...)
    end
end
function _toml_decode_object(::Type{AtTurns}, tbl::AbstractDict, ctx::_TomlContext)
    kwargs = _toml_schema_kwargs(AtTurns, schedule_option_schema(AtTurns), tbl, ctx)
    return AtTurns(get(kwargs, :turns, Set{Int}()))
end
_toml_register_object!(AlwaysSchedule)
_toml_register_object!(EveryNSteps)
_toml_register_object!(AtTurns)

# ---------------------------------------------------------------------------
# Observers, by `observer_option_schema`.
# ---------------------------------------------------------------------------

"""
    _toml_encode_object(x::MomentObserver, ctx)
    _toml_decode_object(::Type{MomentObserver}, tbl, ctx)

A moment probe by its schema: `name` and `moments`, the resolved selection
as the array of the moments' canonical column names (`name(::Moment)`,
`"m100000"` for the mean of `x`; `Moment(::String)` parses them back, a
documented total round trip), in the stored order. Rebuilt through the
constructor's `moments` keyword, which takes the resolved selection itself,
so the reloaded probe's `moments` tuple is the original's. A moment name
that does not parse is refused by name with the constructor's message.
"""
function _toml_encode_object(x::MomentObserver, ctx::_TomlContext)
    return Dict{String,Any}(
        "type" => "MomentObserver",
        "name" => String(x.name),
        "moments" => Any[name(m) for m in x.moments],
    )
end
function _toml_decode_object(::Type{MomentObserver}, tbl::AbstractDict, ctx::_TomlContext)
    schema = observer_option_schema(MomentObserver)
    _toml_only_keys(tbl, ("type", string.(keys(schema))...), :MomentObserver, ctx)
    haskey(tbl, "name") || _toml_refuse(ctx, "MomentObserver needs a `name` and has none")
    probe_name = _toml_option_decode(tbl["name"], String, _toml_at(ctx, "name"))
    raw = get(tbl, "moments", Any[])
    raw isa AbstractVector && all(m -> m isa AbstractString, raw) || _toml_refuse(_toml_at(ctx, "moments"),
        "MomentObserver.moments must be an array of moment names (\"m100000\" for the mean of x)")
    return _toml_construct(ctx, :MomentObserver) do
        MomentObserver(; name=probe_name, moments=Tuple(Moment(String(m)) for m in raw))
    end
end
_toml_register_object!(MomentObserver)

"""
    _toml_encode_object(x::CoordinateSnapshotObserver, ctx)
    _toml_decode_object(::Type{CoordinateSnapshotObserver}, tbl, ctx)
    _toml_encode_object(x::BPMObserver, ctx)
    _toml_decode_object(::Type{BPMObserver}, tbl, ctx)

The snapshot probe and the beam position monitor by their schemas: every
schema key is a field, printed by the option rules (`npart` an integer or
`{ nothing = true }`; the BPM's `rng_id` a decimal integer, its offsets,
gains, readouts and noise floats, `artifact` a boolean) and rebuilt through
the keyword constructors (`BPMObserver(name; ...)` takes its name first).
Reading a BPM claims its stream id as the constructor does for an explicit
id: the reloaded monitor draws the original's noise.
"""
_toml_encode_object(x::CoordinateSnapshotObserver, ctx::_TomlContext) =
    _toml_schema_table(x, observer_option_schema(CoordinateSnapshotObserver), x, ctx)
function _toml_decode_object(::Type{CoordinateSnapshotObserver}, tbl::AbstractDict, ctx::_TomlContext)
    kwargs = _toml_schema_kwargs(CoordinateSnapshotObserver, observer_option_schema(CoordinateSnapshotObserver), tbl, ctx)
    haskey(kwargs, :name) || _toml_refuse(ctx, "CoordinateSnapshotObserver needs a `name` and has none")
    return _toml_construct(ctx, :CoordinateSnapshotObserver) do
        CoordinateSnapshotObserver(; kwargs...)
    end
end
_toml_register_object!(CoordinateSnapshotObserver)
_toml_encode_object(x::BPMObserver, ctx::_TomlContext) =
    _toml_schema_table(x, observer_option_schema(BPMObserver), x, ctx)
function _toml_decode_object(::Type{BPMObserver}, tbl::AbstractDict, ctx::_TomlContext)
    kwargs = _toml_schema_kwargs(BPMObserver, observer_option_schema(BPMObserver), tbl, ctx)
    bpm_name = pop!(kwargs, :name, "bpm")
    return _toml_construct(ctx, :BPMObserver) do
        BPMObserver(bpm_name; kwargs...)
    end
end
_toml_register_object!(BPMObserver)

# ---------------------------------------------------------------------------
# Turn rules: the stochastic rules by their fields, the table by reference to
# the sidecar, the spectral rule refused.
# ---------------------------------------------------------------------------

"""
    _toml_encode_object(x::Union{WhiteNoise,PinkNoise}, ctx)
    _toml_decode_object(::Type{<:WhiteNoise}, tbl, ctx)
    _toml_decode_object(::Type{<:PinkNoise}, tbl, ctx)

The stochastic turn rules by their fields: `sigma` as a float, `rng_id` as a
decimal integer (the claimed stream, so the reloaded rule draws the
original's noise), `octaves` for the pink rule. Rebuilt through
`WhiteNoise(sigma; rng_id)` and `PinkNoise(sigma; rng_id, octaves)` with
`sigma` in the lattice's numeric type (`ctx.numeric_type`), the type the
line compiles the rule against; a rule whose float type differs from the
lattice's is refused at write rather than retyped silently.
"""
function _toml_encode_object(x::Union{WhiteNoise,PinkNoise}, ctx::_TomlContext)
    typeof(x.sigma) === ctx.numeric_type || _toml_refuse(ctx,
        "the $(nameof(typeof(x))) rule's float type $(typeof(x.sigma)) differs from the lattice's " *
        "$(ctx.numeric_type); the snapshot rebuilds a rule in the lattice's type")
    tbl = Dict{String,Any}("type" => string(nameof(typeof(x))),
                           "sigma" => _toml_option_encode(x.sigma, _toml_at(ctx, "sigma")),
                           "rng_id" => _toml_option_encode(x.rng_id, _toml_at(ctx, "rng_id")))
    x isa PinkNoise && (tbl["octaves"] = _toml_option_encode(x.octaves, _toml_at(ctx, "octaves")))
    return tbl
end
function _toml_rule_fields(tbl::AbstractDict, name::Symbol, keys_allowed, ctx::_TomlContext)
    _toml_only_keys(tbl, ("type", keys_allowed...), name, ctx)
    haskey(tbl, "sigma") || _toml_refuse(ctx, "$(name) needs a `sigma` and has none")
    sigma = _toml_option_decode(tbl["sigma"], ctx.numeric_type, _toml_at(ctx, "sigma"))
    rng_id = _toml_option_decode(get(tbl, "rng_id", 0), UInt64, _toml_at(ctx, "rng_id"))
    return sigma, rng_id
end
function _toml_decode_object(::Type{<:WhiteNoise}, tbl::AbstractDict, ctx::_TomlContext)
    sigma, rng_id = _toml_rule_fields(tbl, :WhiteNoise, ("sigma", "rng_id"), ctx)
    return _toml_construct(ctx, :WhiteNoise) do
        WhiteNoise(sigma; rng_id=rng_id)
    end
end
function _toml_decode_object(::Type{<:PinkNoise}, tbl::AbstractDict, ctx::_TomlContext)
    sigma, rng_id = _toml_rule_fields(tbl, :PinkNoise, ("sigma", "rng_id", "octaves"), ctx)
    octaves = _toml_option_decode(get(tbl, "octaves", 16), Int, _toml_at(ctx, "octaves"))
    return _toml_construct(ctx, :PinkNoise) do
        PinkNoise(sigma; rng_id=rng_id, octaves=octaves)
    end
end
_toml_register_object!(WhiteNoise)
_toml_register_object!(PinkNoise)

"""
    _toml_encode_object(x::TurnTable, ctx)
    _toml_decode_object(::Type{<:TurnTable}, tbl, ctx)

A turn table by reference: its offsets go to the context's tables through
`_toml_store_table!` (the sidecar, or the run artifact's table group) and
the text carries `{ type = "TurnTable", name = "...", length = n, sha256 =
"<hex>" }`. Reading loads the vector under the digest through `_toml_table`
(which verifies the digest of what it loads and refuses a missing table by
name), refuses a length other than the stated one, and rebuilds
`TurnTable(offsets; name)` in the lattice's numeric type, which recomputes
the FNV-1a provenance digest from the same bytes. A table whose element type
differs from the lattice's is refused at write (the compile step refuses
such a table too), and so is a table carrying a `resolved_seed`: that
provenance belongs to a table the compile step synthesised from a
`SpectralNoise`, and a snapshot cannot carry it; snapshot the spec's rule,
or build a plain `TurnTable(table.offsets; name)`.
"""
function _toml_encode_object(x::TurnTable, ctx::_TomlContext)
    eltype(x.offsets) === ctx.numeric_type || _toml_refuse(ctx,
        "the TurnTable's element type $(eltype(x.offsets)) differs from the lattice's " *
        "$(ctx.numeric_type); build the table in the lattice's type (the compile step refuses the mismatch too)")
    x.resolved_seed === nothing || _toml_refuse(ctx,
        "the TurnTable \"$(x.name)\" carries a resolved_seed ($(x.resolved_seed)), the provenance of a " *
        "table synthesised at compile from a SpectralNoise; a snapshot holds the spec's rule or a " *
        "plain TurnTable(table.offsets; name), never the synthesised table")
    digest = _toml_store_table!(_toml_at(ctx, "sha256"), x.offsets)
    return Dict{String,Any}("type" => "TurnTable", "name" => String(x.name),
                            "length" => length(x.offsets), "sha256" => String(digest))
end
function _toml_decode_object(::Type{<:TurnTable}, tbl::AbstractDict, ctx::_TomlContext)
    _toml_only_keys(tbl, ("type", "name", "length", "sha256"), :TurnTable, ctx)
    for key in ("length", "sha256")
        haskey(tbl, key) || _toml_refuse(ctx, "TurnTable needs a `$(key)` and has none")
    end
    table_name = _toml_option_decode(get(tbl, "name", ""), String, _toml_at(ctx, "name"))
    n = _toml_option_decode(tbl["length"], Int, _toml_at(ctx, "length"))
    digest = _toml_option_decode(tbl["sha256"], String, _toml_at(ctx, "sha256"))
    offsets = _toml_table(_toml_at(ctx, "sha256"), digest)
    length(offsets) == n || _toml_refuse(_toml_at(ctx, "length"),
        "the TurnTable \"$(table_name)\" states $(n) turns and its table $(digest) holds $(length(offsets))")
    return _toml_construct(ctx, :TurnTable) do
        TurnTable(convert(Vector{ctx.numeric_type}, offsets); name=table_name)
    end
end
_toml_register_object!(TurnTable)
_toml_encode_object(x::SpectralNoise, ctx::_TomlContext) = _toml_refuse(ctx,
    "a SpectralNoise holds the spectral shape function `S` and cannot be snapshotted; resolve it to " *
    "a TurnTable first (spectral_turn_table) and place that, or attach the rule from code when the " *
    "machine is reloaded")

# ---------------------------------------------------------------------------
# The documented refusal list.
# ---------------------------------------------------------------------------

"""
    _toml_refused_object_types() -> Tuple{Vararg{Type}}

The object types a snapshot refuses by name because they hold a function:
`PredicateSchedule` (the predicate), `BeamSwapAction` (the beam provider),
`SpectralNoise` (the spectral shape `S`). Each has an `_toml_encode_object`
method naming the field and the remedy. The suite's tripwire derives every
concrete observer, schedule, action, solver and turn rule the registry knows
and every nested option type the solver schemas reference, and checks that
each is either in `_TOML_OBJECT_TYPES` or here and never in both, so a new
type cannot fall through unnoticed.
"""
_toml_refused_object_types() = (PredicateSchedule, BeamSwapAction, SpectralNoise)
