export AbstractSchedule, AbstractBeamObserver, AbstractBeamAction,
       AlwaysSchedule, EveryNSteps, AtTurns, PredicateSchedule,
       should_run, ScheduledObserver, ScheduledAction,
       BeamMomentObserver, JLD2BeamMomentObserver,
       CoordinateSnapshotObserver, LuminosityObserver, BeamSwapAction,
       observe!, apply_action!, run_observers!, run_actions!,
       prepare_observers!, finalize_observers!, requires_elementwise_tracking

abstract type AbstractSchedule end
abstract type AbstractBeamObserver end
abstract type AbstractBeamAction end

"""Run on every turn."""
struct AlwaysSchedule <: AbstractSchedule end

"""
    EveryNSteps(; start=0, stop=typemax(Int), step=1)

Run on turns `start, start + step, ...` while `turn < stop`.
"""
struct EveryNSteps <: AbstractSchedule
    start::Int
    stop::Int
    step::Int
end
function EveryNSteps(; start::Integer=0, stop::Integer=typemax(Int), step::Integer=1)
    step > 0 || throw(ArgumentError("step must be positive"))
    return EveryNSteps(Int(start), Int(stop), Int(step))
end

"""Run on an explicit set of turns."""
struct AtTurns <: AbstractSchedule
    turns::Set{Int}
end
AtTurns(turns) = AtTurns(Set(Int.(turns)))

"""Run when `predicate(ctx)` returns true."""
struct PredicateSchedule{F} <: AbstractSchedule
    predicate::F
end

should_run(::AlwaysSchedule, ctx::TrackingContext) = true
should_run(schedule::EveryNSteps, ctx::TrackingContext) =
    ctx.turn >= schedule.start &&
    ctx.turn < schedule.stop &&
    (ctx.turn - schedule.start) % schedule.step == 0
should_run(schedule::AtTurns, ctx::TrackingContext) = ctx.turn in schedule.turns
should_run(schedule::PredicateSchedule, ctx::TrackingContext) = Bool(schedule.predicate(ctx))

"""
    ScheduledObserver(observer, schedule=AlwaysSchedule())

Read-only tracking hook. When passed through `TrackingTask(...; hooks=...)`,
observers run after a turn finishes. When placed inside the element line,
observers run at that location in the line.
"""
struct ScheduledObserver{O<:AbstractBeamObserver,S<:AbstractSchedule}
    observer::O
    schedule::S
end
ScheduledObserver(observer::AbstractBeamObserver, schedule::AbstractSchedule=AlwaysSchedule()) =
    ScheduledObserver{typeof(observer),typeof(schedule)}(observer, schedule)

"""
    ScheduledAction(action, schedule=AlwaysSchedule())

State-mutating tracking hook. When passed through `TrackingTask(...; hooks=...)`,
actions run before a turn starts. When placed inside the element line, actions
run at that location in the line.
"""
struct ScheduledAction{A<:AbstractBeamAction,S<:AbstractSchedule}
    action::A
    schedule::S
end
ScheduledAction(action::AbstractBeamAction, schedule::AbstractSchedule=AlwaysSchedule()) =
    ScheduledAction{typeof(action),typeof(schedule)}(action, schedule)

function run_observers!(observers, ctx::TrackingContext, rep)
    for raw in _hook_tuple(observers)
        item = _as_scheduled_observer(raw)
        if should_run(item.schedule, ctx)
            observe!(item.observer, ctx, rep)
        end
    end
    return nothing
end

function prepare_observers!(observers, runtime_elems)
    for raw in _hook_tuple(observers)
        item = _as_scheduled_observer(raw)
        prepare_observer!(item.observer, runtime_elems)
    end
    return nothing
end

prepare_observer!(observer::AbstractBeamObserver, runtime_elems) = nothing

function finalize_observers!(observers)
    for raw in _hook_tuple(observers)
        item = _as_scheduled_observer(raw)
        finalize_observer!(item.observer)
    end
    return nothing
end

finalize_observer!(observer::AbstractBeamObserver) = nothing

function requires_elementwise_tracking(observers)
    for raw in _hook_tuple(observers)
        item = _as_scheduled_observer(raw)
        requires_elementwise_tracking(item.observer) && return true
    end
    return false
end

function requires_elementwise_tracking(observers, ctx::TrackingContext)
    for raw in _hook_tuple(observers)
        item = _as_scheduled_observer(raw)
        should_run(item.schedule, ctx) || continue
        requires_elementwise_tracking(item.observer) && return true
    end
    return false
end

requires_elementwise_tracking(observer::AbstractBeamObserver) = false

function run_actions!(actions, ctx::TrackingContext, rep)
    for raw in _hook_tuple(actions)
        item = _as_scheduled_action(raw)
        if should_run(item.schedule, ctx)
            apply_action!(item.action, ctx, rep)
        end
    end
    return nothing
end

_hook_tuple(hooks::Tuple) = hooks
_hook_tuple(hooks::AbstractVector) = Tuple(hooks)
_hook_tuple(::Nothing) = ()
_hook_tuple(hook::ScheduledObserver) = (hook,)
_hook_tuple(hook::ScheduledAction) = (hook,)
_hook_tuple(hook::AbstractBeamObserver) = (hook,)
_hook_tuple(hook::AbstractBeamAction) = (hook,)

_as_scheduled_observer(item::ScheduledObserver) = item
_as_scheduled_observer(item::AbstractBeamObserver) = ScheduledObserver(item)
_as_scheduled_action(item::ScheduledAction) = item
_as_scheduled_action(item::AbstractBeamAction) = ScheduledAction(item)

function _next_line_hook_index!(hook_counter)
    hook_counter[] += 1
    return hook_counter[]
end

function _line_entry_or_nothing(observer::ScheduledObserver, hook_counter)
    return LineObserverEntry(observer, _next_line_hook_index!(hook_counter))
end
function _line_entry_or_nothing(observer::AbstractBeamObserver, hook_counter)
    return _line_entry_or_nothing(ScheduledObserver(observer), hook_counter)
end
function _line_entry_or_nothing(action::ScheduledAction, hook_counter)
    return LineActionEntry(action, _next_line_hook_index!(hook_counter))
end
function _line_entry_or_nothing(action::AbstractBeamAction, hook_counter)
    return _line_entry_or_nothing(ScheduledAction(action), hook_counter)
end

_line_entry_active(entry::LineObserverEntry, ctx) =
    should_run(entry.observer.schedule, ctx)
_line_entry_active(entry::LineActionEntry, ctx) =
    should_run(entry.action.schedule, ctx)
_line_entry_requires_diagnostics(entry::LineObserverEntry) =
    requires_elementwise_tracking(entry.observer.observer)
_line_entry_requires_diagnostics(entry::LineActionEntry) = false

function classify_task_hooks(hooks=(), actions=(), observers=())
    action_items = Any[]
    observer_items = Any[]
    for hook in _hook_tuple(hooks)
        _push_task_hook!(action_items, observer_items, hook)
    end
    for action in _hook_tuple(actions)
        _push_task_hook!(action_items, observer_items, action)
    end
    for observer in _hook_tuple(observers)
        _push_task_hook!(action_items, observer_items, observer)
    end
    return Tuple(action_items), Tuple(observer_items)
end

_push_task_hook!(actions, observers, hook::ScheduledAction) =
    push!(actions, hook)
_push_task_hook!(actions, observers, hook::AbstractBeamAction) =
    push!(actions, ScheduledAction(hook))
_push_task_hook!(actions, observers, hook::ScheduledObserver) =
    push!(observers, hook)
_push_task_hook!(actions, observers, hook::AbstractBeamObserver) =
    push!(observers, ScheduledObserver(hook))
function _push_task_hook!(actions, observers, hook)
    throw(ArgumentError("unsupported task hook type $(typeof(hook)); use ScheduledAction, ScheduledObserver, AbstractBeamAction, or AbstractBeamObserver"))
end

mutable struct BeamMomentObserver <: AbstractBeamObserver
    path::String
    buffer_capacity::Int
    buffer_turns::Vector{Float64}
    buffer::Vector{Vector{Float64}}
    record_count::Int
    initialized::Bool
end

"""
    BeamMomentObserver(path; capacity=1)

Write turn, means, upper-triangular covariance, and diagonal fourth central
moments to an Octopus compact binary moment-output file.
"""
function BeamMomentObserver(path::AbstractString; capacity::Integer=1)
    capacity >= 0 || throw(ArgumentError("capacity must be nonnegative"))
    return BeamMomentObserver(String(path), Int(capacity), Float64[], Vector{Float64}[], 0, false)
end

mutable struct JLD2BeamMomentObserver <: AbstractBeamObserver
    path::String
    buffer_capacity::Int
    buffer_turns::Vector{Float64}
    buffer::Vector{Any}
    record_count::Int
    initialized::Bool
end

"""
    JLD2BeamMomentObserver(path; capacity=1)

Write beam statistics to a Julia-native JLD2 file.

The file uses a columnar layout:

- `turn`: vector of observed turn numbers.
- `data`: dense matrix with one row per observed turn and flattened statistic
  columns.
- `mean`, `rms`, `emittance`, and `diagonal_fourth_central`: one row per
  observed turn.
- `covariance`: array with shape `(record_count, 6, 6)`.
- `xz_covariance` and `yz_covariance`: vectors.

Column metadata is stored under `metadata/column_names`.
"""
function JLD2BeamMomentObserver(path::AbstractString; capacity::Integer=1)
    capacity >= 0 || throw(ArgumentError("capacity must be nonnegative"))
    return JLD2BeamMomentObserver(String(path), Int(capacity), Float64[], Any[], 0, false)
end

mutable struct CoordinateSnapshotObserver <: AbstractBeamObserver
    path::String
    npart::Union{Nothing,Int}
    append::Bool
end

"""
    CoordinateSnapshotObserver(path; npart=nothing, append=true)

Write coordinate snapshots in the Octopus compact coordinate record format.
"""
function CoordinateSnapshotObserver(path::AbstractString; npart=nothing, append::Bool=true)
    return CoordinateSnapshotObserver(String(path), npart === nothing ? nothing : Int(npart), append)
end

mutable struct LuminosityObserver <: AbstractBeamObserver
    path::String
    elements::Tuple
    initialized::Bool
end

"""
    LuminosityObserver(path)

Write one row per observed turn: turn number followed by positive luminosity
values reported by runtime beam-beam elements in the task line.

This observer requests diagnostic tracking. `TrackingTask` then keeps ordinary
line segments fused while isolating beam-beam runtime elements so they can
update their `last_luminosity` field.
"""
LuminosityObserver(path::AbstractString) = LuminosityObserver(String(path), (), false)

struct BeamSwapAction{F} <: AbstractBeamAction
    provider::F
end

"""
    BeamSwapAction(provider)

Replace the current representation with the `Phase6DRep` or `Beam` returned by
`provider(ctx)`. If `provider` accepts no arguments, it is called as
`provider()`.
"""
BeamSwapAction(provider) = BeamSwapAction{typeof(provider)}(provider)

function observe!(observer::BeamMomentObserver, ctx::TrackingContext, rep)
    observer.buffer_capacity == 0 && return nothing
    observer.initialized || _initialize_moment_file!(observer)
    push!(observer.buffer_turns, Float64(ctx.turn))
    push!(observer.buffer, _moment_output_row(beam_statistics(rep; diagonal_fourth=true)))
    length(observer.buffer) >= observer.buffer_capacity && _flush_moment_buffer!(observer)
    return nothing
end

function observe!(observer::JLD2BeamMomentObserver, ctx::TrackingContext, rep)
    observer.buffer_capacity == 0 && return nothing
    observer.initialized || _initialize_jld2_moment_file!(observer)
    push!(observer.buffer_turns, Float64(ctx.turn))
    push!(observer.buffer, beam_statistics(rep; diagonal_fourth=true))
    length(observer.buffer) >= observer.buffer_capacity && _flush_jld2_moment_buffer!(observer)
    return nothing
end

function observe!(observer::CoordinateSnapshotObserver, ctx::TrackingContext, rep)
    npart = observer.npart === nothing ? length(rep) : observer.npart
    write_beam_coordinates(observer.path, rep; npart=npart, append=observer.append)
    observer.append = true
    return nothing
end

function observe!(observer::LuminosityObserver, ctx::TrackingContext, rep)
    mode = observer.initialized ? "a" : "w"
    open(observer.path, mode) do io
        print(io, ctx.turn, '\t')
        for elem in observer.elements
            lum = luminosity(elem, ctx, rep)
            lum > 0.0 && print(io, lum, '\t')
        end
        print(io, '\n')
    end
    observer.initialized = true
    return nothing
end

function prepare_observer!(observer::LuminosityObserver, runtime_elems)
    observer.elements = runtime_elems
    return nothing
end

requires_elementwise_tracking(::LuminosityObserver) = true

function apply_action!(action::BeamSwapAction, ctx::TrackingContext, rep)
    replacement = _call_provider(action.provider, ctx)
    replacement_rep = replacement isa Beam ? replacement.rep : replacement
    _copy_rep!(rep, replacement_rep)
    return nothing
end

function _call_provider(provider, ctx)
    return applicable(provider, ctx) ? provider(ctx) : provider()
end

function _moment_output_row(stats)
    row = Float64[]
    append!(row, Float64.(stats.mean))
    for i in 1:6, j in i:6
        push!(row, Float64(stats.covariance[i, j]))
    end
    append!(row, Float64.(stats.diagonal_fourth_central))
    return row
end

function _initialize_moment_file!(observer::BeamMomentObserver)
    fmt = "turn"
    for i in 1:6
        fmt *= ",mu$i"
    end
    for i in 1:6, j in i:6
        fmt *= ",sigma$i$j"
    end
    for i in 1:6
        fmt *= ",kappa$i"
    end
    open(observer.path, "w") do io
        write(io, Int32(0))
        write(io, Int32(sizeof(fmt)))
        write(io, codeunits(fmt))
    end
    observer.initialized = true
    return nothing
end

function _flush_moment_buffer!(observer::BeamMomentObserver)
    isempty(observer.buffer) && return nothing
    open(observer.path, "r+") do io
        observer.record_count += length(observer.buffer)
        seekstart(io)
        write(io, Int32(observer.record_count))
        seekend(io)
        for (turn, row) in zip(observer.buffer_turns, observer.buffer)
            write(io, Float64(turn))
            write(io, Float64.(row))
        end
    end
    empty!(observer.buffer_turns)
    empty!(observer.buffer)
    return nothing
end

finalize_observer!(observer::BeamMomentObserver) =
    _flush_moment_buffer!(observer)

function _initialize_jld2_moment_file!(observer::JLD2BeamMomentObserver)
    JLD2.jldopen(observer.path, "w") do file
        file["metadata/format"] = "Octopus.JLD2BeamMomentObserver"
        file["metadata/layout"] = "columnar_v2"
        file["metadata/labels"] = ["x", "px", "y", "py", "z", "pz"]
        file["metadata/covariance_layout"] = "full_6x6"
        file["metadata/column_names"] = _jld2_moment_column_names()
        file["record_count"] = Int64(0)
    end
    observer.initialized = true
    return nothing
end

function _flush_jld2_moment_buffer!(observer::JLD2BeamMomentObserver)
    isempty(observer.buffer) && return nothing
    JLD2.jldopen(observer.path, "r+") do file
        _append_jld2_moment_columns!(file, observer)
    end
    empty!(observer.buffer_turns)
    empty!(observer.buffer)
    return nothing
end

finalize_observer!(observer::JLD2BeamMomentObserver) =
    _flush_jld2_moment_buffer!(observer)

function _jld2_moment_column_names()
    labels = ["x", "px", "y", "py", "z", "pz"]
    names = String["turn"]
    append!(names, ["mean_$label" for label in labels])
    append!(names, ["cov_$(labels[i])_$(labels[j])" for i in 1:6 for j in 1:6])
    append!(names, ["rms_$label" for label in labels])
    append!(names, ["emit_x", "emit_y", "emit_z"])
    push!(names, "xz_covariance")
    push!(names, "yz_covariance")
    append!(names, ["diagonal_fourth_$label" for label in labels])
    return names
end

function _append_jld2_moment_columns!(file, observer::JLD2BeamMomentObserver)
    new_turn = Float64.(observer.buffer_turns)
    new_mean = _rows_matrix(stats -> stats.mean, observer.buffer, 6)
    new_covariance = _rows_covariance(observer.buffer)
    new_rms = _rows_matrix(stats -> stats.rms, observer.buffer, 6)
    new_emittance = _rows_matrix(stats -> stats.emittance, observer.buffer, 3)
    new_xz = Float64[stats.xz_covariance for stats in observer.buffer]
    new_yz = Float64[stats.yz_covariance for stats in observer.buffer]
    new_fourth = _rows_matrix(stats -> stats.diagonal_fourth_central, observer.buffer, 6)
    new_data = _jld2_moment_data_matrix(
        new_turn, new_mean, new_covariance, new_rms, new_emittance, new_xz, new_yz, new_fourth,
    )

    turn = _jld2_read_or_empty(file, "turn", Float64[])
    mean = _jld2_read_or_empty(file, "mean", zeros(Float64, 0, 6))
    covariance = _jld2_read_or_empty(file, "covariance", zeros(Float64, 0, 6, 6))
    rms = _jld2_read_or_empty(file, "rms", zeros(Float64, 0, 6))
    emittance = _jld2_read_or_empty(file, "emittance", zeros(Float64, 0, 3))
    xz = _jld2_read_or_empty(file, "xz_covariance", Float64[])
    yz = _jld2_read_or_empty(file, "yz_covariance", Float64[])
    fourth = _jld2_read_or_empty(file, "diagonal_fourth_central", zeros(Float64, 0, 6))
    data = _jld2_read_or_empty(file, "data", zeros(Float64, 0, length(_jld2_moment_column_names())))

    turn = vcat(turn, new_turn)
    mean = vcat(mean, new_mean)
    covariance = cat(covariance, new_covariance; dims=1)
    rms = vcat(rms, new_rms)
    emittance = vcat(emittance, new_emittance)
    xz = vcat(xz, new_xz)
    yz = vcat(yz, new_yz)
    fourth = vcat(fourth, new_fourth)
    data = vcat(data, new_data)

    observer.record_count = length(turn)
    _jld2_replace!(file, "turn", turn)
    _jld2_replace!(file, "data", data)
    _jld2_replace!(file, "mean", mean)
    _jld2_replace!(file, "covariance", covariance)
    _jld2_replace!(file, "rms", rms)
    _jld2_replace!(file, "emittance", emittance)
    _jld2_replace!(file, "xz_covariance", xz)
    _jld2_replace!(file, "yz_covariance", yz)
    _jld2_replace!(file, "diagonal_fourth_central", fourth)
    _jld2_replace!(file, "record_count", Int64(observer.record_count))
    return nothing
end

_jld2_read_or_empty(file, key::AbstractString, default) =
    haskey(file, key) ? file[key] : default

function _jld2_replace!(file, key::AbstractString, value)
    haskey(file, key) && delete!(file, key)
    file[key] = value
    return nothing
end

function _rows_matrix(getter, stats_buffer, width::Integer)
    out = Matrix{Float64}(undef, length(stats_buffer), width)
    for (i, stats) in pairs(stats_buffer)
        out[i, :] .= Float64.(getter(stats))
    end
    return out
end

function _rows_covariance(stats_buffer)
    out = Array{Float64}(undef, length(stats_buffer), 6, 6)
    for (i, stats) in pairs(stats_buffer)
        out[i, :, :] .= Float64.(stats.covariance)
    end
    return out
end

function _jld2_moment_data_matrix(turn, mean, covariance, rms, emittance, xz, yz, fourth)
    n = length(turn)
    data = Matrix{Float64}(undef, n, length(_jld2_moment_column_names()))
    col = 1
    data[:, col] .= turn; col += 1
    data[:, col:(col + 5)] .= mean; col += 6
    data[:, col:(col + 35)] .= reshape(covariance, n, 36); col += 36
    data[:, col:(col + 5)] .= rms; col += 6
    data[:, col:(col + 2)] .= emittance; col += 3
    data[:, col] .= xz; col += 1
    data[:, col] .= yz; col += 1
    data[:, col:(col + 5)] .= fourth
    return data
end

function _copy_rep!(dest, src)
    length(dest) == length(src) || throw(DimensionMismatch("replacement beam length does not match destination"))
    for (d, s) in zip(coordinate_arrays(dest), coordinate_arrays(src))
        d .= s
    end
    return dest
end
