# Independent particle-tune references shared by the suite, validation script,
# and MPI child. Loading this file defines helpers only. The dense reference
# writes the canonical matrices explicitly, in BigFloat, and never calls the
# implementation's normalization, rotation, sampling, or binding helpers.
import LinearAlgebra
import Random

pt_probe_seed() = UInt64(0x5054554e20261030)
pt_probe_planes() = (:nux, :nuy, :nuz)
pt_probe_subsets() = Tuple(Tuple(pt_probe_planes()[j] for j in 1:3 if mask & (1 << (j - 1)) != 0) for mask in 1:7)

function pt_probe_optics(::Type{T}; periodic=false, unit=false) where {T}
    b1 = unit ? (1, 1, 1) : (1.7, 0.8, 3.2)
    a1 = unit ? (0, 0, 0) : (0.23, -0.19, 0.11)
    z1 = unit ? (0, 0, 0, 0) : (0.031, -0.017, 0.013, 0.009)
    e1 = unit ? (0, 0, 0, 0) : (0.043, 0.011, -0.019, 0.007)
    r1 = unit ? (0, 0, 0, 0) : (0.051, -0.023, 0.017, 0.037)
    return (beta1=T.(b1), alpha1=T.(a1), zeta1=T.(z1), eta1=T.(e1), R1=T.(r1),
        beta2=T.(periodic || unit ? b1 : (2.1, 1.3, 2.7)),
        alpha2=T.(periodic || unit ? a1 : (-0.13, 0.29, -0.07)),
        zeta2=T.(periodic || unit ? z1 : (-0.021, 0.027, 0.018, -0.012)),
        eta2=T.(periodic || unit ? e1 : (0.016, -0.023, 0.029, 0.014)),
        R2=T.(periodic || unit ? r1 : (-0.031, 0.019, 0.023, -0.041)),
        dmu=T.(2pi .* (0.19, 0.31, -0.013)))
end

function pt_probe_initial(::Type{T}; n=17) where {T}
    Octopus.Phase6DRep(
        T[0.003sin(0.73i) for i in 1:n], T[0.001cos(0.51i) for i in 1:n],
        T[0.002sin(0.31i) for i in 1:n], T[0.0007cos(0.37i) for i in 1:n],
        T[0.007sin(0.19i) for i in 1:n], T[0.002cos(0.29i) for i in 1:n])
end

function pt_probe_copy(rep, policy; rank=0, nranks=1)
    interval = Octopus._mp_shard_range(length(rep), nranks, rank)
    arrays = map(a -> copy(Array(a)[interval]), Octopus.coordinate_arrays(rep))
    policy isa Octopus.CUDAExecutionPolicy && (arrays = map(Octopus.CUDA.CuArray, arrays))
    Octopus.Phase6DRep(arrays...)
end

pt_probe_rows(rep) = hcat(map(Array, Octopus.coordinate_arrays(rep))...)

function pt_probe_labels(::Type{T}, n) where {T}
    (nux=T[0.17 + 0.031sin(0.37i) for i in 1:n],
     nuy=T[0.29 - 0.023cos(0.29i) for i in 1:n],
     nuz=T[-0.017 + 0.004sin(0.43i) for i in 1:n])
end

function pt_probe_basis(beta, alpha, zeta, eta, coupling)
    # Explicit independent dense matrices, not the flat runtime helpers.
    B = zeros(BigFloat, 6, 6)
    Z = Matrix{BigFloat}(LinearAlgebra.I, 6, 6)
    E = copy(Z)
    C = copy(Z)
    for j in 1:3
        q, p = 2j - 1, 2j
        root = sqrt(BigFloat(beta[j]))
        B[q, q] = root
        B[p, q] = -BigFloat(alpha[j]) / root
        B[p, p] = inv(root)
    end
    Z[1:4, 5] = BigFloat.(collect(zeta))
    Z[6, 1:4] = BigFloat[zeta[2], -zeta[1], zeta[4], -zeta[3]]
    E[1:4, 6] = BigFloat.(collect(eta))
    E[5, 1:4] = BigFloat[-eta[2], eta[1], -eta[4], eta[3]]
    c = BigFloat.(coupling)
    g = sqrt(1 - c[1] * c[4] + c[2] * c[3])
    for j in 1:4
        C[j, j] = g
    end
    C[1:2, 3:4] = [c[1] c[2]; c[3] c[4]]
    C[3:4, 1:2] = [-c[4] c[2]; c[3] -c[1]]
    Z * E * C * B
end

function pt_probe_matrix(optics, labels, particle; wrong_basis=false)
    entrance = pt_probe_basis(optics.beta1, optics.alpha1, optics.zeta1, optics.eta1, optics.R1)
    exit = wrong_basis ? entrance : pt_probe_basis(optics.beta2, optics.alpha2, optics.zeta2, optics.eta2, optics.R2)
    R = zeros(BigFloat, 6, 6)
    for plane in 1:3
        mu = 2big(pi) * BigFloat(labels[plane][particle])
        s, c = sincos(mu)
        q, p = 2plane - 1, 2plane
        R[q, q] = R[p, p] = c
        R[q, p] = s
        R[p, q] = -s
    end
    exit * R * inv(entrance)
end

function pt_probe_reference(optics, labels, initial; turns=1, wrong_basis=false)
    rows = pt_probe_rows(initial)
    result = Matrix{Float64}(undef, size(rows))
    for i in axes(rows, 1)
        M = pt_probe_matrix(optics, labels, i; wrong_basis=wrong_basis)
        result[i, :] = Float64.(M^turns * BigFloat.(rows[i, :]))
    end
    result
end

"""Forward-error comparison in each coordinate's observed scale, never unit scale.
The 128-rounding allowance covers two six-term products, normalization and
phase preparation. `turns` accounts for accumulation over the bounded fixtures.
"""
function pt_probe_difference(actual, expected, ::Type{T}; turns=1, allowance=128, coordinate_scales=nothing) where {T}
    size(actual) == size(expected) || return (equal=false, max_abs=Inf, max_ratio=Inf)
    worst = 0.0
    ratio = 0.0
    worst_case = nothing
    for j in axes(expected, 2)
        scale = maximum(abs, expected[:, j]; init=0.0)
        coordinate_scales === nothing || (scale = max(scale, coordinate_scales[j]))
        bound = allowance * eps(T) * max(1, turns) * scale
        for i in axes(expected, 1)
            a, b = actual[i, j], expected[i, j]
            if !(isfinite(a) && isfinite(b))
                isequal(a, b) || return (equal=false, max_abs=Inf, max_ratio=Inf)
                continue
            end
            gap = abs(a - b)
            worst = max(worst, gap)
            scaled = iszero(bound) ? (iszero(gap) ? 0.0 : Inf) : gap / bound
            if scaled > ratio
                ratio = scaled
                worst_case = (row=i, column=j, scale=scale, bound=bound,
                    actual=a, expected=b, abs_error=gap)
            end
        end
    end
    (equal=ratio <= 1, max_abs=worst, max_ratio=ratio, worst_case=worst_case)
end

struct PTProbeUniform
    lo::Float64
    hi::Float64
end
Random.rand(rng::Random.AbstractRNG, d::PTProbeUniform) = d.lo + (d.hi - d.lo) * rand(rng)

struct PTProbeJoint end
function Random.rand(rng::Random.AbstractRNG, ::PTProbeJoint)
    u = rand(rng)
    (0.17 + 0.03u, -0.02 + 0.006u)
end

struct PTProbeJointN
    n::Int
end
function Random.rand(rng::Random.AbstractRNG, d::PTProbeJointN)
    value = 0.1 + 0.01rand(rng)
    d.n == 1 ? value : ntuple(j -> j * value, d.n)
end

struct PTProbeCallable end
(::PTProbeCallable)(x, px, y, py, z, pz) = 0.23 + x - px + y - py + z - pz

struct PTProbeVariableDraws end
function Random.rand(rng::Random.AbstractRNG, ::PTProbeVariableDraws)
    u = rand(rng)
    for _ in 1:(1 + floor(Int, 7u))
        rand(rng)
    end
    0.15 + 0.03rand(rng)
end

struct PTProbeBadDistribution end
Random.rand(rng::Random.AbstractRNG, ::PTProbeBadDistribution) = NaN

# CPU-only failure injection: a task can have mutated a first particle before
# a later particle raises. It exercises the admission/loss rollback boundary.
struct PTProbeFailSecond <: Octopus.AbstractTrackOp
    enabled::Base.RefValue{Bool}
end
(op::PTProbeFailSecond)(ctx::Octopus.TrackingContext, id, x, px, y, py, z, pz) =
    op.enabled[] && id == 2 ? error("particle-tune regression deliberately fails particle two") :
    (x, px, y, py, z, pz)

mutable struct PTProbeAxesGate
    enabled::Bool
    arrived::Channel{Nothing}
    release::Channel{Nothing}
end
mutable struct PTProbeGateVector{T} <: AbstractVector{T}
    data::Vector{T}
    gate::PTProbeAxesGate
    first_coordinate::Bool
end
Base.IndexStyle(::Type{<:PTProbeGateVector}) = IndexLinear()
Base.size(v::PTProbeGateVector) = size(v.data)
Base.length(v::PTProbeGateVector) = length(v.data)
Base.getindex(v::PTProbeGateVector, i::Int) = v.data[i]
Base.setindex!(v::PTProbeGateVector, x, i::Int) = (v.data[i] = x)
function Base.axes(v::PTProbeGateVector)
    if v.first_coordinate && v.gate.enabled
        put!(v.gate.arrived, nothing)
        take!(v.gate.release)
    end
    axes(v.data)
end

function pt_probe_concurrent_admission()
    gate = PTProbeAxesGate(false, Channel{Nothing}(2), Channel{Nothing}(2))
    rep = Octopus.Phase6DRep(ntuple(k -> PTProbeGateVector(fill(0.001k, 8), gate, k == 1), 6)...)
    spec = Octopus.Linear6DSpec(beta1=(1.0, 1.0, 1.0), dmu=(0.3, 0.4, -0.05), particle_tunes=(nux=0.21,))
    task = Octopus.TrackingTask((spec,); policy=Octopus.CPUThreadsExecutionPolicy(threads=1), loss_report=false)
    Octopus.execute!(task, rep; turns=1)
    gate.enabled = true
    finished = Channel{Any}(2)
    jobs = [Threads.@spawn begin
        result = try
            Octopus.execute!(task, rep; turns=1)
            (ok=true, error="")
        catch err
            (ok=false, error=sprint(showerror, err))
        end
        put!(finished, result)
    end for _ in 1:2]
    arrived = 0
    results = Any[]
    deadline = time()+10
    while arrived+length(results) < 2 && time() < deadline
        while isready(gate.arrived)
            take!(gate.arrived)
            arrived += 1
        end
        while isready(finished)
            push!(results, take!(finished))
        end
        sleep(0.01)
    end
    # At this barrier the accepted call has entered the public task boundary,
    # but has not marked the tune manager running. Both clear APIs must use
    # the same entry guard; their refusals must not release the active call.
    running_before_clear = task.particle_tunes[].running
    clear_errors = Any[]
    guards_after_clear = Int[]
    for clear in (Octopus.clear_particle_tunes!, Octopus.clear_phase_space_reset!)
        push!(clear_errors, try clear(task); nothing catch err; err end)
        push!(guards_after_clear, task.execution_guard[])
    end
    gate.enabled = false
    for _ in 1:arrived
        put!(gate.release, nothing)
    end
    timedwait(() -> all(istaskdone, jobs), 10; pollint=0.01) === :ok ||
        error("concurrent particle-tune witness did not finish after bounded barrier release")
    foreach(fetch, jobs)
    while isready(finished)
        push!(results, take!(finished))
    end
    # A subsequent call proves the guard is released on both completion paths.
    Octopus.execute!(task, rep; turns=1)
    clears_after_run = (Octopus.clear_particle_tunes!(task) === task,
                        Octopus.clear_phase_space_reset!(task) === task)
    Octopus.execute!(task, rep; turns=1)
    (arrived=arrived, results=results, task=task, running_before_clear=running_before_clear,
     clear_errors=clear_errors, guards_after_clear=guards_after_clear, clears_after_run=clears_after_run)
end

struct PTProbeAdapterDraws end

mutable struct PTProbeBoundaryRNG <: Random.AbstractRNG
    first::Bool
end
function Random.rand(rng::PTProbeBoundaryRNG)
    if rng.first
        rng.first = false
        return prevfloat(1.0)
    end
    return 0.5
end

function Random.rand(rng::Random.AbstractRNG, ::PTProbeAdapterDraws)
    # Exercise the documented adapter surface through the public sampler
    # protocol, not by constructing an internal RNG in the test.
    u = rand(rng, Float32)
    integer = rand(rng, UInt32)
    chosen = rand(rng, 1:7)
    normal = randn(rng)
    bulk = rand(rng, Float64, 3)
    for T in (Bool, Int8, Int16, Int32, Int64, Int128, UInt8, UInt16, UInt32, UInt64, UInt128)
        rand(rng, T) isa T || error("adapter returned the wrong integer type")
        eltype(rand(rng, T, 3)) === T || error("adapter returned the wrong bulk integer type")
    end
    0.2 + 0.001 * (Float64(u) + Float64(integer % UInt32(11)) + chosen + normal + sum(bulk))
end

"""One dense-map case; the optional shard uses a globally indexed direct table."""
function pt_probe_dense(policy; T=Float64, n=17, turns=3, rank=0, nranks=1)
    optics = pt_probe_optics(T)
    labels = pt_probe_labels(T, n)
    initial = pt_probe_initial(T; n=n)
    spec = Octopus.Linear6DSpec{T}(; optics..., particle_tunes=labels)
    task = Octopus.TrackingTask((spec,); policy=policy)
    rep = pt_probe_copy(initial, policy; rank=rank, nranks=nranks)
    audit = Octopus.with_execution_audit() do
        Octopus.execute!(task, rep; turns=turns)
    end
    interval = Octopus._mp_shard_range(n, nranks, rank)
    reference = pt_probe_reference(optics, labels, initial; turns=turns)[interval, :]
    rows = pt_probe_rows(rep)
    receipts = Octopus.execution_receipts(audit)
    consumer = policy isa Octopus.CUDAExecutionPolicy ? :cuda_fused_launch : :cpu_logical_workers
    launches = filter(r -> r.consumer === consumer, receipts)
    actual_threads = sort!(unique([consumer === :cuda_fused_launch ? r.values.threads : r.values.workers for r in launches]))
    requested_threads = policy isa Octopus.CUDAExecutionPolicy ? policy.launch.threads : policy.threads
    length(launches) >= turns && actual_threads == [requested_threads] ||
        error("particle-tune tracking did not execute the requested worker/launch count: $actual_threads versus $requested_threads")
    (task=task, rep=rep, initial=initial, optics=optics, labels=labels,
     rows=rows, reference=reference, comparison=pt_probe_difference(rows, reference, T; turns=turns),
     tables=Octopus.particle_tune_tables(task), receipts=receipts,
     execution=(consumer=consumer, threads=only(actual_threads), launches=length(launches)))
end

function pt_probe_covariance(rows)
    center = sum(rows; dims=1) / size(rows, 1)
    shifted = rows .- center
    transpose(shifted) * shifted / size(rows, 1)
end

"""Exact finite-ensemble phase sum and prescribed-kick convolution.
All references are explicit complex powers/sums, not recursive tracking.
"""
function pt_probe_response(policy; T=Float64, n=17, turns=64, kicks=false, spread=true)
    labels = pt_probe_labels(T, n)
    if !spread
        labels = NamedTuple{pt_probe_planes()}(map(a -> fill(first(a), n), values(labels)))
    end
    optics = pt_probe_optics(T; unit=true)
    spec = Octopus.Linear6DSpec{T}(; optics..., particle_tunes=labels)
    hkick = Octopus.HKickerSpec{T}(hkick=zero(T))
    vkick = Octopus.VKickerSpec{T}(vkick=zero(T))
    task = Octopus.TrackingTask(kicks ? (spec, hkick, vkick) : (spec,); policy=policy)
    w0 = ComplexF64[0.003 + 0.001im, -0.002 + 0.0007im, 0.007 - 0.002im]
    initial = Octopus.Phase6DRep((fill(T(isodd(j) ? real(w0[(j+1)÷2]) : imag(w0[j÷2])), n) for j in 1:6)...)
    rep = pt_probe_copy(initial, policy)
    initial_rows = pt_probe_rows(initial)
    # The oracle starts from the values actually representable in T.
    w0 = [complex(Float64(initial_rows[1, 2j-1]), Float64(initial_rows[1, 2j])) for j in 1:3]
    sequences = (T[4e-5sin(0.61k) for k in 1:turns], T[2e-5cos(0.37k) for k in 1:turns], zeros(T, turns))
    worst = 0.0
    max_gap = 0.0
    action_relative = 0.0
    centroid_gap = 0.0
    covariance_gap = 0.0
    phasor_gap = 0.0
    worst_case = nothing
    output_scaled_max_ratio = 0.0
    output_scale_worst_case = nothing
    for turn in 1:turns
        if kicks
            hkick.hkick = sequences[1][turn]
            vkick.vkick = sequences[2][turn]
        end
        Octopus.execute!(task, rep; turns=1)
        actual = pt_probe_rows(rep)
        reference = similar(actual, Float64)
        for plane in 1:3, particle in 1:n
            r = cis(-2pi * Float64(labels[plane][particle]))
            response = r^turn * w0[plane]
            if kicks
                response += im * sum(r^(turn - k) * Float64(sequences[plane][k]) for k in 1:turn)
            end
            reference[particle, 2plane-1] = real(response)
            reference[particle, 2plane] = imag(response)
            if !kicks
                action = actual[particle, 2plane-1]^2 + actual[particle, 2plane]^2
                action_relative = max(action_relative, abs(action / abs2(w0[plane]) - 1))
                actual_phase = complex(actual[particle, 2plane-1], actual[particle, 2plane]) / w0[plane]
                phasor_gap = max(phasor_gap, abs(actual_phase - r^turn))
            end
        end
        # A zero-spread centroid can cross zero in an entire coordinate
        # column. Its arithmetic error is carried by the phase-plane amplitude
        # and each earlier kick, not the cancelling final coordinate. Rotations
        # preserve amplitude, so |w0| + sum|kick| is a forward-propagated bound.
        amplitudes = ntuple(3) do plane
            abs(w0[plane]) + (kicks ? sum(abs, sequences[plane][1:turn]) : 0)
        end
        coordinate_scales = ntuple(j -> amplitudes[(j+1)÷2], 6)
        output_comparison = pt_probe_difference(actual, reference, T; turns=turn)
        if output_comparison.max_ratio > output_scaled_max_ratio
            column = output_comparison.worst_case.column
            output_scaled_max_ratio = output_comparison.max_ratio
            output_scale_worst_case = (turn=turn, comparison=output_comparison.worst_case,
                phase_plane_amplitude=coordinate_scales[column],
                propagated_bound=128eps(T)*turn*coordinate_scales[column])
        end
        comparison = pt_probe_difference(actual, reference, T; turns=turn, coordinate_scales=coordinate_scales)
        if comparison.max_ratio > worst
            column = comparison.worst_case.column
            plane = (column+1)÷2
            amplitude = abs(w0[plane]) + (kicks ? sum(abs, sequences[plane][1:turn]) : 0)
            worst_case = (turn=turn, comparison=comparison.worst_case,
                phase_plane_amplitude=amplitude,
                propagated_bound=128eps(T)*turn*amplitude)
        end
        worst = max(worst, comparison.max_ratio)
        max_gap = max(max_gap, comparison.max_abs)
        centroid_gap = max(centroid_gap, maximum(abs, sum(actual-reference; dims=1) / n))
        covariance_gap = max(covariance_gap, maximum(abs, pt_probe_covariance(actual) - pt_probe_covariance(reference)))
    end
    (task=task, rep=rep, labels=labels, max_ratio=worst, max_abs=max_gap,
     action_relative=action_relative, phasor_gap=phasor_gap,
     centroid_gap=centroid_gap, covariance_gap=covariance_gap,
     worst_case=worst_case,
     output_scaled_max_ratio=output_scaled_max_ratio, output_scale_worst_case=output_scale_worst_case,
     turns=turns, kicks=kicks, spread=spread)
end
