# Per-trial loss accounting for task-managed phase-space reset. The ordinary
# LossRecord remains a bounded, backend-local scratch record; this lifecycle
# consumes it before the next restore clears it. Permanent-loss tracking never
# calls these helpers. See docs/design/phase_space_reset.md.

const _RESET_TRIAL_COLUMNS = [
    "turn", "reference_epoch", "capture_turn", "particles", "live", "dead",
    "logged", "unattributed", "completed", "folded",
]
const _RESET_LOSS_COLUMNS = [
    "turn", "reference_epoch", "capture_turn", "completed", "folded",
    "particle_id", "element_id", "x", "px", "y", "py", "z", "pz",
]

"""Task-owned accounting for the latest admitted reset execution window."""
mutable struct ResetTrialLedger
    admitted::Bool
    last_trial::Union{Nothing,NamedTuple}
    completed_trials::Int
    attempted_particle_trials::Int
    survivor_particle_trials::Int
    aperture_loss_events::Int
    unattributed_loss_events::Int
    by_aperture::Vector{Int}
    aperture_names::Vector{String}
    pending_names::Vector{String}
    live_flags::Any
    pending::Bool
    turn::Int64
    reference_epoch::Int64
    capture_turn::Int64
    trial_key::String
    loss_key::String
end

ResetTrialLedger() = ResetTrialLedger(false, nothing, 0, 0, 0, 0, 0, Int[], String[],
                                    String[], nothing, false, -1, 0, -1, "", "")

"""
Count non-finite particles without moving CUDA coordinates to the host. The
device mask is allocated once and reused; only the integer reduction result
crosses the device boundary. The ordinary count/loss APIs retain their existing
behavior; reset trials use this explicitly because they reconcile every turn.
"""
function _reset_count_dead!(ledger::ResetTrialLedger, rep::Phase6DRep)
    if _HAS_CUDA && rep.x isa CUDA.CuArray
        flags = ledger.live_flags
        if !(flags isa CUDA.CuArray{Bool}) || length(flags) != length(rep) ||
           CUDA.device(flags) != CUDA.device(rep.x)
            flags = similar(rep.x, Bool)
            ledger.live_flags = flags
        end
        flags .= is_live.(rep.x, rep.px, rep.y, rep.py, rep.z, rep.pz)
        dead = length(rep) - Int(sum(flags))
        _record_execution!(:phase_space_reset_liveness, CUDABackend,
                           (particles=length(rep), dead=dead,
                            host_coordinate_copies=0, reduction=:device))
        return dead
    end
    ledger.live_flags = nothing
    return count_dead(rep)
end

function _reset_local_loss_summary(ledger::ResetTrialLedger, rep, record)
    dead = _reset_count_dead!(ledger, rep)
    counts = Int.(loss_counts(record))
    logged = sum(counts)
    return (particles=length(rep), live=length(rep) - dead, dead=dead,
            logged=logged, unattributed=dead - logged, by_aperture=counts,
            names=aperture_names(record))
end

"""
Validate and bind the two reset products before the artifact commits. The
previous window's in-memory summary survives a refusal; the admitted turn loop
calls `_start_reset_trial_window!` after the commit to begin the new window.
"""
function _bind_reset_trials!(ledger::ResetTrialLedger, art, name::AbstractString,
                             first_turn::Integer, names)
    identity = isempty(name) ? "reset" : String(name)
    if art === nothing
        ledger.trial_key = ""
        ledger.loss_key = ""
        ledger.pending_names = String.(names)
        return nothing
    end
    columns = vcat(_RESET_TRIAL_COLUMNS,
                   ["aperture_$(i)" for i in eachindex(names)])
    attrs = (; loss_semantics="per_trial",
             (Symbol("aperture_name_$(i)") => String(names[i]) for i in eachindex(names))...)
    trial_key = "reset_trials/" * identity
    loss_key = "reset_losses/" * identity
    refused = Int[0]
    root_error = nothing
    if _mp_is_root()
        try
            # Epochs label changing references; aperture labels still describe
            # every retained row. A changed label must not rename old events
            # when the probe protocol rewrites attributes at commit.
            for key in (trial_key, loss_key)
                art.file === nothing && break
                haskey(art.file, key) || continue
                stored = HDF5.attributes(art.file[key])
                stored_names = sort!([String(k) for k in keys(stored)
                                      if startswith(String(k), "aperture_name_")])
                expected_names = sort!(["aperture_name_$(i)" for i in eachindex(names)])
                stored_names == expected_names || throw(ArgumentError(
                    "continued phase-space reset output has a different aperture catalogue"))
                for i in eachindex(names)
                    String(read(stored["aperture_name_$(i)"])) == String(names[i]) ||
                        throw(ArgumentError(
                            "continued phase-space reset output has different aperture names"))
                end
            end
            _ra_bind_probe!(art, "reset_trials", identity, columns, Int(first_turn); attrs=attrs)
            _ra_bind_probe!(art, "reset_losses", identity, copy(_RESET_LOSS_COLUMNS),
                            Int(first_turn); attrs=attrs)
        catch err
            root_error = err
            refused[1] = 1
        end
    end
    _mp_bcast!(refused)
    if refused[1] != 0
        root_error === nothing || throw(root_error)
        throw(ArgumentError("the root rank refused phase-space reset output binding"))
    end
    ledger.trial_key = trial_key
    ledger.loss_key = loss_key
    ledger.pending_names = String.(names)
    return nothing
end

"""Start a reset window only after every admission check and output commit."""
function _start_reset_trial_window!(ledger::ResetTrialLedger)
    ledger.admitted = true
    ledger.last_trial = nothing
    ledger.completed_trials = 0
    ledger.attempted_particle_trials = 0
    ledger.survivor_particle_trials = 0
    ledger.aperture_loss_events = 0
    ledger.unattributed_loss_events = 0
    ledger.aperture_names = copy(ledger.pending_names)
    resize!(ledger.by_aperture, length(ledger.aperture_names))
    fill!(ledger.by_aperture, 0)
    ledger.pending = false
    ledger.turn = -1
    return nothing
end

"""
Begin one trial with clean loss scratch on its existing backend. The task
passes the reference epoch and original capture turn alongside the current
absolute turn; none of these values changes the stochastic tracking context.
"""
function _begin_reset_trial!(ledger::ResetTrialLedger, record, ctx::TrackingContext,
                             reference_epoch::Integer, capture_turn::Integer=ctx.turn)
    ledger.pending && throw(ArgumentError(
        "phase-space reset cannot start another trial before the pending trial is finalized"))
    if record !== nothing
        fill!(record.counts, zero(eltype(record.counts)))
        record.slots === nothing || fill!(record.slots, zero(eltype(record.slots)))
    end
    ledger.turn = ctx.turn
    ledger.reference_epoch = Int64(reference_epoch)
    ledger.capture_turn = Int64(capture_turn)
    ledger.pending = true
    return nothing
end

function _reset_trial_row(ledger::ResetTrialLedger, summary, completed::Bool, folded::Bool)
    return (turn=ledger.turn, reference_epoch=ledger.reference_epoch,
            capture_turn=ledger.capture_turn, particles=summary.particles,
            live=summary.live, dead=summary.dead, logged=summary.logged,
            unattributed=summary.unattributed, completed=completed, folded=folded,
            by_aperture=Tuple(summary.by_aperture), aperture_names=Tuple(summary.names))
end

function _reset_trial_matrix(row)
    values = (row.turn, row.reference_epoch, row.capture_turn, row.particles,
              row.live, row.dead, row.logged, row.unattributed,
              Int(row.completed), Int(row.folded), row.by_aperture...)
    return reshape(Float64[values...], 1, :)
end

function _reset_trial_event_rows(ledger::ResetTrialLedger, record, shard_offset::Integer,
                                 completed::Bool, folded::Bool; local_logged::Integer)
    # Reuse the count already reduced for this trial. An empty-loss rank need
    # not transfer its 8N device slots merely to discover an empty event list,
    # but it still enters the same gather as every other rank. With no
    # apertures every rank has record === nothing and contributes empty rows.
    local_rows = if local_logged == 0
        zeros(Float64, 0, length(LOSS_RECORD_COLUMNS))
    else
        _ra_gathered_loss_rows(record, shard_offset; gather=false)
    end
    local_rows === nothing && throw(ArgumentError(
        "phase-space reset artifact output requires per-particle aperture loss slots"))
    source = folded ? _mp_gather_rows(local_rows) : local_rows
    rows = Matrix{Float64}(undef, size(source, 1), length(_RESET_LOSS_COLUMNS))
    for i in axes(source, 1)
        rows[i, 1] = ledger.turn
        rows[i, 2] = ledger.reference_epoch
        rows[i, 3] = ledger.capture_turn
        rows[i, 4] = Int(completed)
        rows[i, 5] = Int(folded)
    end
    for (j, name) in pairs(LOSS_RECORD_COLUMNS)
        name == "turn" && continue
        destination = findfirst(==(name), _RESET_LOSS_COLUMNS)
        destination === nothing && error("reset loss output is missing a loss-record column")
        rows[:, destination] = source[:, j]
    end
    return rows
end

"""
Finalize the pending trial, retaining its outcome before any restoration.
Success folds small counts and requested loss rows across ranks. A failure
calls this outside the execution-policy scope with `completed=false` and
`folded=false`: no collective is issued and any written rows explicitly
describe only the root rank's partial trial. The caller preserves the original
tracking exception if this best-effort finalization also fails.
"""
function _finish_reset_trial!(ledger::ResetTrialLedger, rep, record, art;
                              completed::Bool=true, folded::Bool=true,
                              shard_offset::Integer=0)
    ledger.pending || return nothing
    local_summary = _reset_local_loss_summary(ledger, rep, record)
    summary = folded ? _global_loss_summary(local_summary) : local_summary
    row = _reset_trial_row(ledger, summary, completed, folded)
    if art !== nothing
        events = _reset_trial_event_rows(ledger, record, shard_offset, completed, folded;
                                         local_logged=local_summary.logged)
        write_error = nothing
        refused = Int[0]
        try
            _ra_write_reset_trial!(art, ledger.trial_key, ledger.loss_key,
                                  _reset_trial_matrix(row), events, ledger.turn)
        catch err
            write_error = err
            refused[1] = 1
        end
        # A root-side HDF5 failure must stop every rank before any can enter
        # the next trial's reduction. Crash finalization deliberately performs
        # no such agreement: some ranks may already be unwinding.
        folded && _mp_bcast!(refused)
        if refused[1] != 0
            write_error === nothing || throw(write_error)
            throw(ArgumentError("the root rank could not write phase-space reset trial output"))
        end
    end
    # Store only after output succeeded. A failed write leaves pending=true;
    # the failure finalizer replaces this turn's partial output, never appends
    # a duplicate completed/partial pair for the same trial.
    ledger.last_trial = row
    if completed
        ledger.completed_trials += 1
        ledger.attempted_particle_trials += summary.particles
        ledger.survivor_particle_trials += summary.live
        ledger.aperture_loss_events += summary.logged
        ledger.unattributed_loss_events += summary.unattributed
        for i in eachindex(ledger.by_aperture)
            ledger.by_aperture[i] += summary.by_aperture[i]
        end
    end
    ledger.pending = false
    if _mp_is_root() && summary.unattributed != 0
        @warn "phase-space reset trial contains particles lost with no aperture responsible; their unattributed loss count is recorded before restoration" turn=ledger.turn unattributed=summary.unattributed dead=summary.dead logged=summary.logged
    end
    policy = _ACTIVE_RESOLVED_POLICY[]
    backend = policy isa AbstractResolvedExecutionPolicy ? backend_type(policy) : :unknown
    _record_execution!(:phase_space_reset_trial, backend,
        merge(row, (flush_mode=art === nothing ? :none : :per_trial,
                    capacity_applies=false)))
    return row
end
