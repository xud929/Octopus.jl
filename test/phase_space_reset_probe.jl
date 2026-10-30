# Independent one-turn oracle for PhaseSpaceResetSpec. Shared by the suite,
# the real MPI launcher child, and validation/phase_space_reset_consistency.jl.
# Functions only: loading this file neither tracks nor chooses a backend.
# The reference makes ordinary explicit array copies and never calls a reset
# helper. Both paths record noise offsets and all six coordinates at every
# turn, so a repeated-turn-zero or missing-reset implementation cannot pass.

psr_probe_kinds() = (:none, :table, :white, :pink, :radiation)
psr_probe_seed() = UInt64(0x50535220261029)

function psr_probe_initial(::Type{T}; n::Int=17) where {T}
    return Octopus.Phase6DRep(
        T[8.0e-4 * sin(0.73i) for i in 1:n],
        T[1.0e-4 * cos(0.51i) for i in 1:n],
        T[4.0e-4 * sin(0.31i) for i in 1:n],
        T[2.0e-5 * cos(0.37i) for i in 1:n],
        T[1.0e-2 * sin(0.19i) for i in 1:n],
        T[3.0e-4 * cos(0.29i) for i in 1:n])
end

function psr_probe_copy(rep, policy; rank::Int=0, nranks::Int=1)
    r = Octopus._mp_shard_range(length(rep), nranks, rank)
    arrays = map(a -> copy(a[r]), Octopus.coordinate_arrays(rep))
    if policy isa Octopus.CUDAExecutionPolicy
        return Octopus.Phase6DRep(map(Octopus.CUDA.CuArray, arrays)...)
    end
    return Octopus.Phase6DRep(arrays...)
end

function psr_probe_line(::Type{T}, kind::Symbol; losses::Bool=false) where {T}
    kind in psr_probe_kinds() || throw(ArgumentError("unknown reset probe kind"))
    rule = if kind === :table
        Octopus.TurnTable(T[0.0, 0.17, 0.24, 0.0, 0.09, -0.13, 0.03, 0.0]; name="reset_oracle")
    elseif kind === :white
        Octopus.WhiteNoise(T(0.08))
    elseif kind === :pink
        Octopus.PinkNoise(T(0.08); octaves=4)
    else
        nothing
    end
    cavity = Octopus.ThinCrabCavitySpec{1,T}(T(394.0e6);
        strengthX=(T(0.08),), strengthY=(T(0.02),),
        phase=(T(0.015),), phase_noise=(rule,))
    drift = Octopus.DriftSpec{T}(L=T(0.75))
    physical = if kind === :radiation
        (cavity, Octopus.LumpedRadSpec{T}(damping_turns=(T(40), T(50), T(60)),
            sigma=(T(1e-4), T(2e-4), T(1e-3)), is_damping=false,
            is_excitation=true), drift)
    else
        (cavity, drift)
    end
    return losses ? (physical..., Octopus.ApertureSpec{T}(shape=:rectangle,
        x_limit=T(0.0018), y_limit=T(0.0018), name="trial_aperture")) : physical
end

function psr_probe_snapshot_rows(path, name)
    rows = read(Octopus.TaskOutput(path), :snapshot; name=name)
    matrix = hcat(rows.turn, rows.particle_id, rows.x, rows.px, rows.y,
                  rows.py, rows.z, rows.pz)
    order = sortperm(1:size(matrix, 1); by=i -> (matrix[i, 1], matrix[i, 2]))
    return matrix[order, :]
end

function psr_probe_noise(path)
    values = Dict{Tuple{Int,String},Float64}()
    for execution in Octopus.turn_modulation_provenance(path)
        for element in execution.elements, slot in element.slots
            slot.series === nothing && error("reset oracle requested noise recording but got no series")
            for (i, value) in enumerate(slot.series)
                values[(element.first_turn + i - 1, slot.slot)] = value
            end
        end
    end
    return values
end

function psr_probe_loss_rows(path, reset::Bool)
    out = Octopus.TaskOutput(path)
    rows = reset ? read(out, :reset_losses; name="reset") : read(out, :losses)
    matrix = hcat(rows.turn, rows.particle_id, rows.element_id,
                  rows.x, rows.px, rows.y, rows.py, rows.z, rows.pz)
    order = sortperm(1:size(matrix, 1); by=i -> (matrix[i, 1], matrix[i, 2]))
    return matrix[order, :]
end

"""NaN-aware comparison in coordinate scale; alive/dead identity is separate."""
function psr_probe_difference(a, b; atol::Real=0, rtol::Real=0)
    size(a) == size(b) || return (equal=false, bitwise=false, max_abs=Inf)
    good = true
    exact = true
    worst = 0.0
    for (x, y) in zip(a, b)
        exact &= isequal(x, y)
        if isfinite(x) && isfinite(y)
            gap = abs(x - y)
            worst = max(worst, gap)
            good &= gap <= atol + rtol * max(abs(x), abs(y))
        else
            good &= isnan(x) && isnan(y)
        end
    end
    return (equal=good, bitwise=exact, max_abs=worst)
end

"""Compare backend coordinates at each reference coordinate's own scale."""
function psr_probe_backend_difference(a, b, ::Type{T}; identity_columns::Int=2) where {T}
    size(a) == size(b) || return (equal=false, identity_equal=false,
        loss_mask_equal=false, max_abs=Inf, scaled_max=fill(Inf, 6))
    identities = isequal(a[:, 1:identity_columns], b[:, 1:identity_columns])
    masks = isfinite.(a[:, identity_columns+1:end]) == isfinite.(b[:, identity_columns+1:end])
    accepted = identities && masks
    worst = 0.0
    scaled = Float64[]
    for column in (identity_columns+1):size(a, 2)
        reference = @view b[:, column]
        scale = maximum((abs(x) for x in reference if isfinite(x)); init=0.0)
        rtol = T === Float64 ? 1e-10 : 64eps(T)
        atol = T === Float64 ? 1e-10 : rtol * scale
        comparison = psr_probe_difference(@view(a[:, column]), reference; atol=atol, rtol=rtol)
        accepted &= comparison.equal
        worst = max(worst, comparison.max_abs)
        push!(scaled, scale > 0 ? comparison.max_abs / scale :
                      (comparison.max_abs == 0 ? 0.0 : Inf))
    end
    return (equal=accepted, identity_equal=identities, loss_mask_equal=masks,
            max_abs=worst, scaled_max=scaled)
end

"""
Run the reset line and an independent fresh-copy, one-turn reference. All MPI
ranks call this together using a common directory and explicitly supplied
rank/count; only rank zero reads the gathered artifact. `chunks` must sum to
`turns` and changes only the reset path's execute boundaries. Absolute turns,
the physical element objects (and their RNG IDs), seed and policy are shared.
"""
function psr_probe_verify(policy, directory; T=Float64, kind::Symbol=:table,
                          losses::Bool=false, n::Int=17, turns::Int=4,
                          first_turn::Int=0, chunks=(turns,), rank::Int=0,
                          nranks::Int=1, prefix::AbstractString="probe", line_override=nothing)
    sum(chunks) == turns || throw(ArgumentError("reset probe chunks must sum to turns"))
    mkpath(directory)
    reset_path = joinpath(directory, prefix * "_reset.h5")
    reference_path = joinpath(directory, prefix * "_reference.h5")
    initial = psr_probe_initial(T; n=n)
    line = line_override === nothing ? psr_probe_line(T, kind; losses=losses) : line_override
    make_artifact(path) = Octopus.RunArtifact(path; append=true, capacity=2,
                                             record_turn_modulation=true)
    function make_task(path, reset)
        start = Octopus.ScheduledObserver(Octopus.CoordinateSnapshotObserver(name="starts"))
        elements = reset ? (Octopus.PhaseSpaceResetSpec{T}(), start, line...) : (start, line...)
        return Octopus.TrackingTask(elements; policy=policy,
            hooks=(Octopus.CoordinateSnapshotObserver(name="samples"),),
            artifact=make_artifact(path))
    end
    reset_task = make_task(reset_path, true)
    reference_task = make_task(reference_path, false)
    rep = psr_probe_copy(initial, policy; rank=rank, nranks=nranks)
    Octopus.set_global_rng!(seed=psr_probe_seed(), method=:philox)
    audit = Octopus.ExecutionAudit()
    Octopus.with_execution_audit(audit) do
        for (i, count) in enumerate(chunks)
            if i == 1
                Octopus.execute!(reset_task, rep; turns=count, start_turn=first_turn)
            else
                Octopus.execute!(reset_task, rep; turns=count)
            end
        end
    end
    Octopus.set_global_rng!(seed=psr_probe_seed(), method=:philox)
    for turn in first_turn:(first_turn + turns - 1)
        # This explicit copy is the independent oracle. In particular it does
        # not ask the reset task or its captured arrays for the reference.
        fresh = psr_probe_copy(initial, policy; rank=rank, nranks=nranks)
        Octopus.execute!(reference_task, fresh; turns=1, start_turn=turn)
    end
    rank == 0 || return (root=false, task=reset_task, rep=rep)
    reset_rows = psr_probe_snapshot_rows(reset_path, "samples")
    reference_rows = psr_probe_snapshot_rows(reference_path, "samples")
    starts = psr_probe_snapshot_rows(reset_path, "starts")
    expected_starts = reduce(vcat, [hcat(fill(Float64(t), n), collect(1.0:n),
        map(Array, Octopus.coordinate_arrays(initial))...) for t in first_turn:(first_turn + turns - 1)])
    noise_reset = psr_probe_noise(reset_path)
    noise_reference = psr_probe_noise(reference_path)
    reset_losses = losses ? psr_probe_loss_rows(reset_path, true) : zeros(0, 9)
    reference_losses = losses ? psr_probe_loss_rows(reference_path, false) : zeros(0, 9)
    trials = read(Octopus.TaskOutput(reset_path), :reset_trials; name="reset")
    expected_turns = Float64.(collect(first_turn:(first_turn + turns - 1)))
    # Exact is the intended same-backend oracle: the same physical segment
    # and observer boundaries run in both paths. A caller comparing CPU/CUDA
    # uses the established backend tolerance separately.
    comparison = psr_probe_difference(reset_rows, reference_rows)
    loss_comparison = psr_probe_difference(reset_losses, reference_losses)
    return (root=true, task=reset_task, rep=rep, initial=initial, line=line,
            reset_path=reset_path, reference_path=reference_path,
            rows=reset_rows, reference_rows=reference_rows, starts=starts,
            coordinates=comparison, losses=loss_comparison,
            reset_loss_rows=reset_losses, reference_loss_rows=reference_losses,
            starts_exact=isequal(starts, expected_starts),
            noise_equal=isequal(noise_reset, noise_reference),
            noise_count=length(noise_reset), noise=noise_reset,
            row_count=size(reset_rows, 1), expected_rows=n * turns,
            trials=trials, trial_turns_exact=trials.turn == expected_turns,
            receipts=Octopus.execution_receipts(audit),
            window_summary=Octopus.phase_space_reset_summary(reset_task))
end

function psr_probe_pass(result)
    !result.root && return true
    return result.coordinates.equal && result.losses.equal && result.starts_exact &&
           result.noise_equal && result.row_count == result.expected_rows &&
           result.trial_turns_exact
end
