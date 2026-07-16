export AbstractPoissonSolver, LongitudinalSlicing, longitudinal_slices,
       GaussianPoissonSolver, PICPoissonSolver,
       StrongStrongGaussianPoissonSolver, StrongStrongCollision,
       StrongStrongTask, collide!

"""
    AbstractPoissonSolver

Interface for live-beam beam-beam solvers used by `StrongStrongTask`.

A solver advances two `Beam` objects at one collision point and returns a
luminosity estimate:

```julia
collide!(solver, beam1, beam2, backend) -> luminosity
```

The current concrete implementations are `GaussianPoissonSolver` and
`PICPoissonSolver`.
"""
abstract type AbstractPoissonSolver <: AbstractOctopusObject end

# Internal performance thresholds. Below these slice sizes, serial CPU work is
# usually cheaper than thread scheduling and per-thread reduction overhead.
const _STRONG_STRONG_PARALLEL_MOMENT_MIN = 4096
const _STRONG_STRONG_PARALLEL_KICK_MIN = 4096
const _PIC_PARALLEL_DEPOSIT_MIN = 4096

# Safety margin, in grid cells, required before reusing a shifted PIC Green
# template for a new source/field domain.
const _PIC_TEMPLATE_MARGIN_CELLS = 1.5

struct _PICFieldWorkspace{T}
    phi::Matrix{T}
    Ex::Matrix{T}
    Ey::Matrix{T}
end

struct _PICCPUWorkspace{T}
    charge::Matrix{T}
    spectral::Matrix{Complex{T}}
    green::Matrix{T}
    green_fft::Matrix{Complex{T}}
    fft_plan::Any
    ifft_plan::Any
    local_charge::Vector{Matrix{T}}
    left::_PICFieldWorkspace{T}
    right::_PICFieldWorkspace{T}
    luminosity_q1::Matrix{T}
    luminosity_q2::Matrix{T}
end

struct _PICGridTemplate{T}
    source_width::T
    source_height::T
    field_width::T
    field_height::T
    dx::T
    dy::T
    hx::T
    hy::T
    green_fft::Matrix{Complex{T}}
end

struct _PICGreenKey{T}
    green_type::Symbol
    nx::Int
    ny::Int
    source_x0::T
    source_y0::T
    source_width::T
    source_height::T
    field_x0::T
    field_y0::T
    field_width::T
    field_height::T
end

mutable struct _PICExactGreenCache{T}
    greens::Dict{_PICGreenKey{T},Matrix{Complex{T}}}
    hits::Int
    misses::Int
end

mutable struct _PICGridTemplateCache{T}
    templates::Vector{_PICGridTemplate{T}}
    hits::Int
    misses::Int
end

function _pic_cpu_workspace(::Type{T}, nx::Integer, ny::Integer) where {T}
    charge = zeros(T, 2nx, 2ny)
    spectral = zeros(Complex{T}, 2nx, 2ny)
    green = zeros(T, 2nx, 2ny)
    green_fft = zeros(Complex{T}, 2nx, 2ny)
    fft_plan = plan_fft!(spectral)
    ifft_plan = plan_ifft!(spectral)
    local_charge = [similar(charge) for _ in 1:Threads.nthreads()]
    left = _PICFieldWorkspace(zeros(T, nx, ny), zeros(T, nx, ny), zeros(T, nx, ny))
    right = _PICFieldWorkspace(zeros(T, nx, ny), zeros(T, nx, ny), zeros(T, nx, ny))
    return _PICCPUWorkspace{T}(
        charge, spectral, green, green_fft, fft_plan, ifft_plan, local_charge, left, right,
        zeros(T, nx + 1, ny + 1), zeros(T, nx + 1, ny + 1),
    )
end

"""
    LongitudinalSlicing(; nslices=1, method=:equal_area, resolution=100,
                         center_position=:centroid, positions=Float64[])

Longitudinal slicing configuration for live-beam collisions.

Supported methods:

- `:equal_area`: choose slice boundaries so each slice has nearly equal
  macroparticle count using a histogram/interpolation estimate.
- `:equal_count`: choose exact empirical equal-count slices by sorting the
  current macroparticles by longitudinal coordinate.
- `:equal_width`: choose uniformly spaced boundaries between the current
  minimum and maximum longitudinal coordinates.
- `:specified`: use `positions` as internal boundaries in units of beam
  longitudinal rms around the beam mean.

`center_position` may be `:centroid` or `:midpoint`.
"""
Base.@kwdef struct LongitudinalSlicing <: AbstractOctopusObject
    nslices::Int = 1
    method::Symbol = :equal_area
    resolution::Int = 100
    center_position::Symbol = :centroid
    positions::Vector{Float64} = Float64[]
end

function LongitudinalSlicing(nslices::Integer; kwargs...)
    return LongitudinalSlicing(; nslices=Int(nslices), kwargs...)
end

"""
    GaussianPoissonSolver(; kbb1=nothing, kbb2=nothing,
                           luminosity_scale=nothing,
                           slicing=LongitudinalSlicing(),
                           min_sigma=eps(Float64),
                           gaussian_when_luminosity=2,
                           ignore_centroid1=false,
                           ignore_centroid2=false)

Soft-Gaussian strong-strong collision solver. At each collision it computes
longitudinal slices of both live beams, orders slice-pair collisions by
collision time, applies thin Gaussian beam-beam kicks to both beams, and returns
a luminosity estimate. For each slice pair, the source slice is represented by
its transverse Gaussian moments at the slice center; each field particle uses a
per-particle drifted source moment at its own collision point. This follows the
no-interpolation soft-Gaussian path.

`kbb1` scales the kick applied to beam 1 by beam 2. `kbb2` scales the kick
applied to beam 2 by beam 1. If either is `nothing`, it is derived from
`BeamParams` as:

```julia
kbb1 = beam1.charge * beam2.charge * beam1.r0 * beam2.npart * beam1.mc2 / beam1.E0
kbb2 = beam1.charge * beam2.charge * beam2.r0 * beam1.npart * beam2.mc2 / beam2.E0
```

`luminosity_scale` defaults to a macroparticle-to-physical-particle
normalization for the beam sampled by the luminosity estimate. This solver is a
sliced moment-based Poisson approximation, not a grid PIC solver.
"""
Base.@kwdef struct GaussianPoissonSolver{T<:Real} <: AbstractPoissonSolver
    kbb1::Union{Nothing,T} = nothing
    kbb2::Union{Nothing,T} = nothing
    luminosity_scale::Union{Nothing,T} = nothing
    slicing::LongitudinalSlicing = LongitudinalSlicing()
    min_sigma::T = eps(T)
    gaussian_when_luminosity::Int = 2
    ignore_centroid1::Bool = false
    ignore_centroid2::Bool = false
end

GaussianPoissonSolver(; kwargs...) = GaussianPoissonSolver{Float64}(; kwargs...)

const StrongStrongGaussianPoissonSolver = GaussianPoissonSolver

"""
    PICPoissonSolver(; kbb1=nothing, kbb2=nothing, luminosity_scale=nothing,
                      grid=(128, 128), deposit_method=:CIC,
                      green_type=:integrated,
                      green_cache=:none,
                      longitudinal_kick=true,
                      slicing=LongitudinalSlicing())

Grid particle-in-cell strong-strong collision solver. Each directed slice-pair
interaction deposits the source slice onto a transverse mesh at the left and
right longitudinal boundaries of the field slice, solves the open 2D Poisson
problem by zero-padded FFT convolution with a logarithmic Green function,
interpolates the transverse field onto the field particles according to their
longitudinal coordinates, and applies the resulting kick.

If `longitudinal_kick=true`, the field particles also receive the
potential-difference longitudinal kick and the corresponding virtual-drift
`pz` terms used by the Hirata-map branch of the reference PIC algorithm.
This is the default. Set `longitudinal_kick=false` for a transverse-only map.

`deposit_method` may be `:CIC` or `:TSC`. `green_type` may be `:integrated`
or `:standard`; the integrated Green function is the robust default and uses a
cell-integrated logarithmic kernel.

`green_cache` may be `:none`, `:exact`, or `:grid_template`. The exact cache
reuses Green FFTs for identical source/field grids. The template cache reuses
shifted source/field grid geometry when a translated cached template can cover
the current source and field domains with deposition/interpolation margin.

CUDA execution uses atomic grid deposition and CUDA FFT convolution. The first
CUDA implementation is correctness-oriented; later versions may replace atomic
deposition with binned or tiled reductions for dense beams.
"""
Base.@kwdef struct PICPoissonSolver{T<:Real} <: AbstractPoissonSolver
    kbb1::Union{Nothing,T} = nothing
    kbb2::Union{Nothing,T} = nothing
    luminosity_scale::Union{Nothing,T} = nothing
    grid::Tuple{Int,Int} = (128, 128)
    deposit_method::Symbol = :CIC
    green_type::Symbol = :integrated
    green_cache::Symbol = :none
    longitudinal_kick::Bool = true
    slicing::LongitudinalSlicing = LongitudinalSlicing()
end

PICPoissonSolver(; kwargs...) = PICPoissonSolver{Float64}(; kwargs...)

"""
    StrongStrongCollision(label; poisson_solver=nothing)

Line-level strong-strong collision marker. Place matching markers in both beam
lines at the physical collision location.

The marker may carry a collision-specific `poisson_solver`. If it does not,
`StrongStrongTask` uses its default solver.

```julia
ip = StrongStrongCollision(:ip; poisson_solver=GaussianPoissonSolver())
line1 = (arc1_to_ip, ip, arc1_after_ip)
line2 = (arc2_to_ip, ip, arc2_after_ip)
```
"""
struct StrongStrongCollision{S} <: AbstractOctopusObject
    label::Symbol
    poisson_solver::S
end

StrongStrongCollision(label; poisson_solver=nothing) =
    StrongStrongCollision(Symbol(label), poisson_solver)

"""
    StrongStrongTask(line1, line2; policy=nothing,
                     default_poisson_solver=GaussianPoissonSolver(),
                     luminosity_path=nothing)

Track two live beams through ordinary tracking lines containing matching
`StrongStrongCollision` markers.

The two lines must contain the same ordered collision labels. Ordinary elements
before, between, and after collision markers are compiled into fused tracking
segments whenever possible. The execution backend is inferred from the two beam
containers passed to `execute!`. If `policy` is provided, it is treated as an
explicit assertion and must match both beam backends. The immutable
`TrackingContext` used by context-aware stochastic tracking snapshots the
Octopus global RNG state at execution time.

```julia
ip = StrongStrongCollision(:ip; poisson_solver=solver)
line1 = (arc1_to_ip, ip, arc1_after_ip)
line2 = (arc2_to_ip, ip, arc2_after_ip)
task = StrongStrongTask(line1, line2)
execute!(task, beam1, beam2; turns=10)
```
"""
struct StrongStrongTask{L1<:Tuple,L2<:Tuple,S<:AbstractPoissonSolver} <: AbstractTask
    line1::L1
    line2::L2
    policy::Union{Nothing,AbstractExecutionPolicy}
    default_poisson_solver::S
    luminosity_path::Union{Nothing,String}
    runtime_entries_cache1::Base.RefValue{Any}
    runtime_entries_cache2::Base.RefValue{Any}
    plan_cache1::Dict{Any,Any}
    plan_cache2::Dict{Any,Any}
    runtime_cache::Dict{Any,Any}
end

function StrongStrongTask(line1, line2;
                          policy::Union{Nothing,AbstractExecutionPolicy}=nothing,
                          seed=nothing,
                          default_poisson_solver::AbstractPoissonSolver=GaussianPoissonSolver(),
                          poisson_solver::Union{Nothing,AbstractPoissonSolver}=nothing,
                          luminosity_path::Union{Nothing,AbstractString}=nothing)
    line_tuple1 = _element_tuple(line1)
    line_tuple2 = _element_tuple(line2)
    seed !== nothing && @warn "StrongStrongTask seed keyword is deprecated; use set_global_rng!(seed=...) instead." seed
    solver = poisson_solver === nothing ? default_poisson_solver : poisson_solver
    return StrongStrongTask(
        line_tuple1,
        line_tuple2,
        policy,
        solver,
        luminosity_path === nothing ? nothing : String(luminosity_path),
        Ref{Any}(nothing),
        Ref{Any}(nothing),
        Dict{Any,Any}(),
        Dict{Any,Any}(),
        Dict{Any,Any}(),
    )
end

"""
    execute!(task::StrongStrongTask, beam1, beam2; turns=1)

Execute a strong-strong task in place. Returns `(beam1, beam2)`.
"""
function execute!(task::StrongStrongTask, beam1::Beam, beam2::Beam; turns::Integer=1)
    backend = _execution_backend(task, beam1, beam2)
    blocks1 = _strong_strong_runtime_blocks(task, 1)
    blocks2 = _strong_strong_runtime_blocks(task, 2)
    _validate_strong_strong_blocks(blocks1, blocks2)
    prepare_observers!(_line_observers(blocks1), _strong_strong_physics_line(blocks1))
    prepare_observers!(_line_observers(blocks2), _strong_strong_physics_line(blocks2))
    ctx = TrackingContext()
    if task.luminosity_path === nothing
        _execute_strong_strong_turns!(task, beam1, beam2, blocks1, blocks2, backend, ctx, Int(turns), nothing)
    else
        open(task.luminosity_path, "w") do io
            _execute_strong_strong_turns!(task, beam1, beam2, blocks1, blocks2, backend, ctx, Int(turns), io)
        end
    end
    _finalize_strong_strong_line_observers!(blocks1)
    _finalize_strong_strong_line_observers!(blocks2)
    return beam1, beam2
end

function _execution_backend(task::StrongStrongTask, beam1::Beam{BTAG1}, beam2::Beam{BTAG2}) where {BTAG1<:AbstractExecutionBackend,BTAG2<:AbstractExecutionBackend}
    BTAG1 === BTAG2 || throw(ArgumentError(
        "strong-strong tracking requires both beams to use the same backend; got $(BTAG1) and $(BTAG2)."
    ))
    task.policy === nothing && return BTAG1
    requested = backend_type(task.policy)
    requested === BTAG1 || throw(ArgumentError(
        "task policy requests $(requested), but beam storage requires $(BTAG1). " *
        "Construct both beams with the same backend or omit the task policy."
    ))
    return requested
end

function _execute_strong_strong_turns!(task, beam1, beam2, blocks1, blocks2, backend, ctx, turns::Int, io)
    streams = _strong_strong_segment_streams(backend)
    memory_log_every = _strong_strong_cuda_memory_log_every(backend)
    for turn in 0:(turns - 1)
        ctx = with_turn(ctx, turn)
        io === nothing || print(io, turn)
        turn_range = _cuda_nvtx_push(backend, "strongstrong turn")
        for j in eachindex(blocks1)
            line_range = _cuda_nvtx_push(backend, "strongstrong line tracking")
            _execute_strong_strong_segment_pair!(
                beam1.rep, blocks1[j].entries, task.plan_cache1,
                beam2.rep, blocks2[j].entries, task.plan_cache2,
                backend, ctx, streams,
            )
            _cuda_nvtx_pop(backend, line_range)
            if blocks1[j].collision !== nothing
                solver = _collision_solver(task, blocks1[j].collision, blocks2[j].collision)
                collision_range = _cuda_nvtx_push(backend, "strongstrong collision")
                lum = _strong_strong_collide!(
                    task, blocks1[j].collision.label, solver, beam1, beam2, backend,
                )
                _cuda_nvtx_pop(backend, collision_range)
                io === nothing || print(io, '\t', lum)
            end
        end
        _cuda_nvtx_pop(backend, turn_range)
        io === nothing || println(io)
        _strong_strong_maybe_log_cuda_memory(backend, turn, memory_log_every)
    end
    return nothing
end

function _strong_strong_collide!(task::StrongStrongTask, label::Symbol,
                                 solver::AbstractPoissonSolver,
                                 beam1::Beam, beam2::Beam, backend)
    return collide!(solver, beam1, beam2, backend)
end

_cuda_nvtx_enabled() = get(ENV, "OCTOPUS_CUDA_NVTX", "0") in ("1", "true", "TRUE", "yes", "YES")

function _cuda_nvtx_push(backend, message::AbstractString)
    backend === CUDABackend || return false
    (_HAS_CUDA && _cuda_nvtx_enabled()) || return false
    CUDA.NVTX.range_push(message=String(message))
    return true
end

function _cuda_nvtx_pop(backend, active::Bool)
    (backend === CUDABackend && active && _HAS_CUDA) || return nothing
    CUDA.NVTX.range_pop()
    return nothing
end

function _strong_strong_cuda_memory_log_every(backend)
    backend === CUDABackend || return 0
    return max(parse(Int, get(ENV, "OCTOPUS_CUDA_MEMORY_LOG_EVERY", "0")), 0)
end

function _strong_strong_maybe_log_cuda_memory(backend, turn::Integer, every::Integer)
    backend === CUDABackend || return nothing
    every > 0 || return nothing
    (turn == 0 || (turn + 1) % every == 0) || return nothing
    _HAS_CUDA || return nothing
    free = CUDA.free_memory()
    total = CUDA.total_memory()
    reserved = CUDA.cached_memory()
    used = CUDA.used_memory()
    println(
        "CUDA memory after turn $(turn): " *
        "free=$(Base.format_bytes(free)), total=$(Base.format_bytes(total)), " *
        "pool_used=$(Base.format_bytes(used)), pool_reserved=$(Base.format_bytes(reserved))"
    )
    return nothing
end

function _execute_strong_strong_segment_pair!(rep1, entries1::Tuple, plan_cache1,
                                              rep2, entries2::Tuple, plan_cache2,
                                              backend, ctx, streams)
    if backend === CUDABackend && streams !== nothing
        _execute_strong_strong_segment!(rep1, entries1, plan_cache1, backend, ctx, streams[1])
        _execute_strong_strong_segment!(rep2, entries2, plan_cache2, backend, ctx, streams[2])
        CUDA.synchronize(streams[1])
        CUDA.synchronize(streams[2])
    else
        _execute_strong_strong_segment!(rep1, entries1, plan_cache1, backend, ctx)
        _execute_strong_strong_segment!(rep2, entries2, plan_cache2, backend, ctx)
    end
    return nothing
end

function _strong_strong_segment_streams(backend)
    if backend === CUDABackend
        _HAS_CUDA || error("CUDABackend requires CUDA.jl to be available.")
        return (CUDA.CuStream(), CUDA.CuStream())
    end
    return nothing
end

function _execute_strong_strong_segment!(rep, entries::Tuple, plan_cache, backend, ctx, stream=nothing)
    isempty(entries) && return nothing
    plan_key = _active_plan_key(entries, ctx, false)
    plan = get!(plan_cache, plan_key) do
        _build_tracking_plan(entries, plan_key)
    end
    _execute_tracking_plan_turn!(rep, plan, backend, ctx; stream=stream)
    return nothing
end

struct StrongStrongBlock{E,C}
    entries::E
    collision::C
end

function _strong_strong_runtime_blocks(task::StrongStrongTask, which::Integer)
    cache = which == 1 ? task.runtime_entries_cache1 : task.runtime_entries_cache2
    cached = cache[]
    cached === nothing || return cached
    line = which == 1 ? task.line1 : task.line2
    blocks = _split_strong_strong_line(line)
    cache[] = blocks
    empty!(which == 1 ? task.plan_cache1 : task.plan_cache2)
    return blocks
end

function _split_strong_strong_line(line::Tuple)
    blocks = Any[]
    current = Any[]
    hook_counter = Ref(0)
    _append_strong_strong_line!(blocks, current, line, hook_counter)
    push!(blocks, StrongStrongBlock(Tuple(current), nothing))
    return Tuple(blocks)
end

function _append_strong_strong_line!(blocks, current, line::Tuple, hook_counter)
    for item in line
        _append_strong_strong_line!(blocks, current, item, hook_counter)
    end
    return nothing
end

function _append_strong_strong_line!(blocks, current, line::AbstractVector, hook_counter)
    for item in line
        _append_strong_strong_line!(blocks, current, item, hook_counter)
    end
    return nothing
end

function _append_strong_strong_line!(blocks, current, collision::StrongStrongCollision, hook_counter)
    push!(blocks, StrongStrongBlock(Tuple(current), collision))
    empty!(current)
    return nothing
end

function _append_strong_strong_line!(blocks, current, element, hook_counter)
    before = length(current)
    _append_runtime_line!(current, element, hook_counter)
    length(current) >= before || error("internal strong-strong line construction error")
    return nothing
end

function _validate_strong_strong_blocks(blocks1::Tuple, blocks2::Tuple)
    length(blocks1) == length(blocks2) ||
        throw(ArgumentError("line1 and line2 must contain the same number of StrongStrongCollision markers"))
    for (i, (b1, b2)) in enumerate(zip(blocks1, blocks2))
        c1, c2 = b1.collision, b2.collision
        if c1 === nothing || c2 === nothing
            c1 === c2 || throw(ArgumentError("line1 and line2 collision marker mismatch at block $i"))
        elseif c1.label != c2.label
            throw(ArgumentError("line1 collision $(c1.label) does not match line2 collision $(c2.label) at block $i"))
        end
    end
    return nothing
end

function _collision_solver(task::StrongStrongTask, c1::StrongStrongCollision, c2::StrongStrongCollision)
    s1 = c1.poisson_solver
    s2 = c2.poisson_solver
    if s1 !== nothing && s2 !== nothing && s1 !== s2
        throw(ArgumentError("collision $(c1.label) specifies different Poisson solver objects in line1 and line2"))
    end
    s1 !== nothing && return s1
    s2 !== nothing && return s2
    return task.default_poisson_solver
end

function _line_observers(lines::Tuple)
    observers = Any[]
    for block in lines, entry in block.entries
        entry isa LineObserverEntry && push!(observers, entry.observer.observer)
    end
    return Tuple(observers)
end

function _strong_strong_physics_line(lines::Tuple)
    elems = Any[]
    for block in lines, entry in block.entries
        entry isa PhysicsEntry && push!(elems, entry.element)
    end
    return Tuple(elems)
end

function _finalize_strong_strong_line_observers!(lines::Tuple)
    for block in lines
        _finalize_line_observers!(block.entries)
    end
    return nothing
end
