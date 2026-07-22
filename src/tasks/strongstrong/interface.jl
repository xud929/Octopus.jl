export AbstractPoissonSolver, LongitudinalSlicing, longitudinal_slices,
       slicing_option_schema,
       gaussian_slice_centers, collision_pair_batches,
       GaussianPoissonSolver, PICPoissonSolver,
       CUDAPICLaunchConfig, cuda_pic_launch_option_schema,
       SolverOptionMeta, solver_option_schema, solver_configuration, solver_help,
       StrongStrongGaussianPoissonSolver, StrongStrongCollision,
       StrongStrongDiagnostics, DiagnosticsOptionMeta, diagnostics_option_schema,
       diagnostics_help, StrongStrongTask, turn_timings,
       pic_phase_timings, diagnostic_summary, collide!

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

const _CUDA_PIC_LAUNCH_FAMILIES = (
    :gather_scatter, :deposition, :kick, :field, :spectral, :green, :luminosity,
)

"""
    CUDAPICLaunchConfig(; gather_scatter_threads=nothing,
                         deposition_threads=nothing, kick_threads=nothing,
                         field_threads=nothing, spectral_threads=nothing,
                         green_threads=nothing, luminosity_threads=nothing)

Optional CUDA-only PIC launch overrides. `nothing` inherits the thread count
from `CUDAExecutionPolicy`. PIC block counts remain derived from the particle,
grid, spectral, or reduction topology. Luminosity threads must be a power of
two because the current overlap kernel uses a tree reduction.
"""
struct CUDAPICLaunchConfig <: AbstractOctopusObject
    gather_scatter_threads::Union{Nothing,Int}
    deposition_threads::Union{Nothing,Int}
    kick_threads::Union{Nothing,Int}
    field_threads::Union{Nothing,Int}
    spectral_threads::Union{Nothing,Int}
    green_threads::Union{Nothing,Int}
    luminosity_threads::Union{Nothing,Int}
end

function CUDAPICLaunchConfig(; gather_scatter_threads=nothing,
                             deposition_threads=nothing,
                             kick_threads=nothing,
                             field_threads=nothing,
                             spectral_threads=nothing,
                             green_threads=nothing,
                             luminosity_threads=nothing)
    values = map(
        value -> value === nothing ? nothing : Int(value),
        (gather_scatter_threads, deposition_threads, kick_threads, field_threads,
         spectral_threads, green_threads, luminosity_threads),
    )
    all(value -> value === nothing || 1 <= value <= 1024, values) ||
        throw(ArgumentError("CUDA PIC thread counts must be nothing or integers in 1:1024"))
    lum = values[7]
    lum === nothing || ispow2(lum) || throw(ArgumentError(
        "luminosity_threads must be a power of two for the current tree reduction; got $(lum)"))
    return CUDAPICLaunchConfig(values...)
end

struct ResolvedCUDAPICLaunchConfig
    gather_scatter::Int
    deposition::Int
    kick::Int
    field::Int
    spectral::Int
    green::Int
    luminosity::Int
end

const _CUDA_PIC_LAUNCH_OPTION_SCHEMA = (
    gather_scatter_threads=ConfigurationOptionMeta(Union{Nothing,Int}, nothing,
        "Threads for slice gather/scatter and mask-index construction.";
        supported_backends=(CUDABackend,), consumer=:cuda_pic_launch),
    deposition_threads=ConfigurationOptionMeta(Union{Nothing,Int}, nothing,
        "Threads for particle-to-grid deposition.";
        supported_backends=(CUDABackend,), consumer=:cuda_pic_launch),
    kick_threads=ConfigurationOptionMeta(Union{Nothing,Int}, nothing,
        "Threads for field interpolation and particle kicks.";
        supported_backends=(CUDABackend,), consumer=:cuda_pic_launch),
    field_threads=ConfigurationOptionMeta(Union{Nothing,Int}, nothing,
        "Threads for transverse field derivatives.";
        supported_backends=(CUDABackend,), consumer=:cuda_pic_launch),
    spectral_threads=ConfigurationOptionMeta(Union{Nothing,Int}, nothing,
        "Threads for Octopus spectral multiply kernels; cuFFT remains library-managed.";
        supported_backends=(CUDABackend,), consumer=:cuda_pic_launch),
    green_threads=ConfigurationOptionMeta(Union{Nothing,Int}, nothing,
        "Threads for Green-kernel construction.";
        supported_backends=(CUDABackend,), consumer=:cuda_pic_launch),
    luminosity_threads=ConfigurationOptionMeta(Union{Nothing,Int}, nothing,
        "Power-of-two thread count for luminosity deposition/reduction.";
        supported_backends=(CUDABackend,), consumer=:cuda_pic_launch),
)

cuda_pic_launch_option_schema(::Type{CUDAPICLaunchConfig}=CUDAPICLaunchConfig) =
    _CUDA_PIC_LAUNCH_OPTION_SCHEMA
cuda_pic_launch_option_schema(::CUDAPICLaunchConfig) = _CUDA_PIC_LAUNCH_OPTION_SCHEMA

function configuration_report(config::CUDAPICLaunchConfig,
                              policy::CUDAExecutionPolicy=CUDAExecutionPolicy())
    return Tuple(ConfigurationEntry(name, getproperty(config, name),
        something(getproperty(config, name), policy.launch.threads),
        getproperty(config, name) === nothing ? :inherited : :resolved,
        getproperty(config, name) === nothing ? "inherited from CUDAExecutionPolicy" :
                                               "explicit CUDA PIC override",
        meta.consumer) for (name, meta) in pairs(cuda_pic_launch_option_schema(config)))
end

const _ACTIVE_CUDA_PIC_LAUNCH_CONFIG = Base.ScopedValues.ScopedValue{Any}(nothing)

function _cuda_pic_configuration(solver)
    configs = solver.backend_configurations
    matches = filter(config -> config isa CUDAPICLaunchConfig, configs)
    length(matches) <= 1 || throw(ArgumentError(
        "PICPoissonSolver accepts at most one CUDAPICLaunchConfig"))
    return isempty(matches) ? nothing : first(matches)
end

function _resolve_cuda_pic_configuration(solver, policy::ResolvedCUDAExecutionPolicy)
    config = _cuda_pic_configuration(solver)
    value(field) = config === nothing ? nothing : getproperty(config, field)
    inherited(field) = something(value(field), policy.threads)
    resolved = ResolvedCUDAPICLaunchConfig(
        inherited(:gather_scatter_threads), inherited(:deposition_threads),
        inherited(:kick_threads), inherited(:field_threads),
        inherited(:spectral_threads), inherited(:green_threads),
        inherited(:luminosity_threads),
    )
    ispow2(resolved.luminosity) || throw(ArgumentError(
        "resolved luminosity threads must be a power of two; got $(resolved.luminosity). " *
        "Set CUDAPICLaunchConfig(luminosity_threads=...) when the generic CUDA thread count is not a power of two."))
    device = CUDA.CuDevice(policy.device)
    max_threads = CUDA.attribute(device, CUDA.DEVICE_ATTRIBUTE_MAX_THREADS_PER_BLOCK)
    for family in _CUDA_PIC_LAUNCH_FAMILIES
        threads = getproperty(resolved, family)
        threads <= max_threads || throw(ArgumentError(
            "CUDA PIC $(family) threads $(threads) exceed device $(policy.device) maximum $(max_threads)"))
    end
    return resolved
end

function _with_solver_execution_configuration(f::F, solver, policy) where {F}
    if solver isa PICPoissonSolver && policy isa ResolvedCUDAExecutionPolicy
        resolved = _resolve_cuda_pic_configuration(solver, policy)
        return Base.ScopedValues.with(_ACTIVE_CUDA_PIC_LAUNCH_CONFIG => resolved) do
            f()
        end
    end
    if solver isa PICPoissonSolver && !isempty(solver.backend_configurations)
        _record_execution!(:cuda_pic_configuration, backend_type(policy),
                           (status=:inactive_backend,))
    end
    return f()
end

function _cuda_pic_threads(family::Symbol)
    family in _CUDA_PIC_LAUNCH_FAMILIES || throw(ArgumentError(
        "unknown CUDA PIC launch family $(family)"))
    config = _ACTIVE_CUDA_PIC_LAUNCH_CONFIG[]
    config isa ResolvedCUDAPICLaunchConfig || return 256
    threads = getproperty(config, family)
    _record_execution!(:cuda_pic_launch, CUDABackend, (family=family, threads=threads))
    return threads
end

"""
    StrongStrongDiagnostics(; record_turn_times=false, memory_log_every=0,
                              pic_timing=false, pic_timing_detail=false,
                              cache_stats=false, nvtx=false)

Explicit diagnostic and profiling configuration for `StrongStrongTask`.
Detailed PIC timing synchronizes CUDA subphases and can perturb throughput;
leave it disabled for production timing. `memory_log_every=0` disables memory
logging. These options observe execution and must not change tracking results.
"""
struct StrongStrongDiagnostics <: AbstractOctopusObject
    record_turn_times::Bool
    memory_log_every::Int
    pic_timing::Bool
    pic_timing_detail::Bool
    cache_stats::Bool
    nvtx::Bool
end

function StrongStrongDiagnostics(; record_turn_times::Bool=false,
                                 memory_log_every::Integer=0,
                                 pic_timing::Bool=false,
                                 pic_timing_detail::Bool=false,
                                 cache_stats::Bool=false,
                                 nvtx::Bool=false)
    memory_log_every >= 0 || throw(ArgumentError("memory_log_every must be nonnegative"))
    return StrongStrongDiagnostics(record_turn_times, Int(memory_log_every), pic_timing,
                                   pic_timing_detail, cache_stats, nvtx)
end

"""Structured metadata for one `StrongStrongDiagnostics` option."""
struct DiagnosticsOptionMeta
    option_type::Any
    default::Any
    meaning::String
    supported_backends::Tuple
    perturbs_timing::Bool
    consumer::Symbol
end

DiagnosticsOptionMeta(option_type, default, meaning;
                      supported_backends=(CPUThreadsBackend, CUDABackend),
                      perturbs_timing=false, consumer=:strong_strong_diagnostics) =
    DiagnosticsOptionMeta(option_type, default, String(meaning),
                          Tuple(supported_backends), perturbs_timing, Symbol(consumer))

const _STRONG_STRONG_DIAGNOSTICS_OPTION_SCHEMA = (
    record_turn_times=DiagnosticsOptionMeta(Bool, false,
        "Synchronize at complete-turn boundaries and record wall-clock seconds."; perturbs_timing=true),
    memory_log_every=DiagnosticsOptionMeta(Int, 0,
        "Print CUDA allocator state every N turns; zero disables logging.";
        supported_backends=(CUDABackend,), perturbs_timing=true),
    pic_timing=DiagnosticsOptionMeta(Bool, false,
        "Collect and print CUDA PIC phase timing records.";
        supported_backends=(CUDABackend,), perturbs_timing=true),
    pic_timing_detail=DiagnosticsOptionMeta(Bool, false,
        "Synchronize CUDA PIC subphases for an additive detailed breakdown.";
        supported_backends=(CUDABackend,), perturbs_timing=true),
    cache_stats=DiagnosticsOptionMeta(Bool, false,
        "Print PIC Green-cache reuse and rebuild counters."),
    nvtx=DiagnosticsOptionMeta(Bool, false,
        "Emit CUDA NVTX ranges for external profilers.";
        supported_backends=(CUDABackend,), perturbs_timing=true),
)

"""Return structured metadata for every `StrongStrongDiagnostics` option."""
diagnostics_option_schema(::Type{StrongStrongDiagnostics}=StrongStrongDiagnostics) =
    _STRONG_STRONG_DIAGNOSTICS_OPTION_SCHEMA
diagnostics_option_schema(::StrongStrongDiagnostics) = _STRONG_STRONG_DIAGNOSTICS_OPTION_SCHEMA

"""Print discoverable help for `StrongStrongDiagnostics` options."""
function diagnostics_help(; io::IO=stdout)
    println(io, "StrongStrongDiagnostics options:")
    for (name, meta) in pairs(diagnostics_option_schema())
        backends = join(string.(meta.supported_backends), ", ")
        println(io, "  - ", name, "::", meta.option_type, " = ", repr(meta.default))
        println(io, "      ", meta.meaning)
        println(io, "      backends=", backends, "; perturbs_timing=", meta.perturbs_timing,
                "; consumer=", meta.consumer)
    end
    return nothing
end
diagnostics_help(io::IO) = diagnostics_help(; io)

const _DEFAULT_STRONG_STRONG_DIAGNOSTICS = StrongStrongDiagnostics()
const _ACTIVE_STRONG_STRONG_DIAGNOSTICS = Base.ScopedValues.ScopedValue(_DEFAULT_STRONG_STRONG_DIAGNOSTICS)
const _ACTIVE_PIC_PHASE_TIMING_SINK = Base.ScopedValues.ScopedValue{Any}(nothing)
const _ACTIVE_PIC_TIMING_CONTEXT = Base.ScopedValues.ScopedValue{Any}(nothing)
const _ACTIVE_PIC_LUMINOSITY_PAIR_SINK = Base.ScopedValues.ScopedValue{Any}(nothing)
_strong_strong_diagnostics() = _ACTIVE_STRONG_STRONG_DIAGNOSTICS[]

"""Structured metadata for one public solver constructor option."""
struct SolverOptionMeta
    option_type::Any
    default::Any
    meaning::String
    supported_backends::Tuple
    category::Symbol
    environment_override::Union{Nothing,String}
    dependencies::Tuple{Vararg{Symbol}}
    consumer::Symbol
end

SolverOptionMeta(option_type, default, meaning;
                 supported_backends=(CPUThreadsBackend, CUDABackend),
                 category=:numerical, environment_override=nothing,
                 dependencies=(), consumer=:solver_runtime) =
    SolverOptionMeta(option_type, default, String(meaning), Tuple(supported_backends),
                     Symbol(category), environment_override === nothing ? nothing : String(environment_override),
                     Tuple(Symbol.(dependencies)), Symbol(consumer))

"""Return structured constructor-option metadata for a solver type or instance."""
solver_option_schema(::Type{<:AbstractPoissonSolver}) = NamedTuple()
solver_option_schema(solver::AbstractPoissonSolver) = solver_option_schema(typeof(solver))

"""Return current public option fields, plus solver-specific resolved values."""
function _solver_configured_values(solver::AbstractPoissonSolver)
    schema = solver_option_schema(solver)
    return (; (name => getproperty(solver, name) for name in keys(schema))...)
end
solver_configuration(solver::AbstractPoissonSolver) = _solver_configured_values(solver)

"""Print structured solver configuration help."""
function solver_help(; io::IO=stdout)
    println(io, "Available strong-strong solvers:")
    for T in build_registry().solvers
        println(io, "  - ", T)
    end
    println(io, "Use solver_help(PICPoissonSolver) or solver_option_schema(PICPoissonSolver).")
    return nothing
end

function solver_help(solver_type::Type{<:AbstractPoissonSolver}; io::IO=stdout)
    println(io, "Solver: ", solver_type)
    schema = solver_option_schema(solver_type)
    isempty(keys(schema)) && return println(io, "No structured solver-option metadata is registered.")
    println(io, "Options:")
    for (name, meta) in pairs(schema)
        backends = join((string(B) for B in meta.supported_backends), ", ")
        println(io, "  - ", name, "::", meta.option_type, " = ", repr(meta.default))
        println(io, "      ", meta.meaning)
        println(io, "      category=", meta.category, "; backends=", backends,
                "; consumer=", meta.consumer)
        meta.environment_override === nothing ||
            println(io, "      debug override=", meta.environment_override)
        isempty(meta.dependencies) || println(io, "      dependencies=", join(meta.dependencies, ", "))
    end
    return nothing
end
function solver_help(solver::AbstractPoissonSolver; io::IO=stdout)
    solver_help(typeof(solver); io=io)
    println(io, "Current/resolved values:")
    for (name, value) in pairs(solver_configuration(solver))
        println(io, "  - ", name, " = ", repr(value))
    end
    return nothing
end
solver_help(io::IO) = solver_help(; io=io)
solver_help(io::IO, solver) = solver_help(solver; io=io)

collide!(solver::AbstractPoissonSolver, beam1::Beam, beam2::Beam, backend, ctx::TrackingContext) =
    collide!(solver, beam1, beam2, backend)

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

mutable struct _PICSlicePairGreenEntry{T}
    source_grid::Any
    field_grid::Any
    green_fft::Matrix{Complex{T}}
    uses::Int
    rebuilds::Int
end

mutable struct _PICSlicePairGreenCache{T}
    entries::Dict{Tuple{Int,Int,Int},_PICSlicePairGreenEntry{T}}
    hits::Int
    misses::Int
    rebuilds::Int
end

function _pic_cpu_workspace(::Type{T}, nx::Integer, ny::Integer) where {T}
    charge = zeros(T, 2nx, 2ny)
    spectral = zeros(Complex{T}, 2nx, 2ny)
    green = zeros(T, 2nx, 2ny)
    green_fft = zeros(Complex{T}, 2nx, 2ny)
    fft_plan = plan_fft!(spectral)
    ifft_plan = plan_ifft!(spectral)
    local_charge = [similar(charge) for _ in 1:_cpu_worker_count()]
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
- `:normal_quantile`: choose equal-probability normal-distribution quantile
  boundaries from the current longitudinal mean/rms. Slice centers are still
  controlled by `center_position`, and slice weights come from the
  macroparticle counts in each slice.
- `:specified`: use `positions` as internal boundaries in units of beam
  longitudinal rms around the beam mean.

`center_position` may be `:centroid` or `:midpoint`.
"""
struct LongitudinalSlicing <: AbstractOctopusObject
    nslices::Int
    method::Symbol
    resolution::Int
    center_position::Symbol
    positions::Vector{Float64}
end

Base.:(==)(a::LongitudinalSlicing, b::LongitudinalSlicing) =
    a.nslices == b.nslices && a.method == b.method &&
    a.resolution == b.resolution && a.center_position == b.center_position &&
    a.positions == b.positions
Base.isequal(a::LongitudinalSlicing, b::LongitudinalSlicing) = a == b
Base.hash(s::LongitudinalSlicing, h::UInt) =
    hash((s.nslices, s.method, s.resolution, s.center_position, s.positions), h)

function LongitudinalSlicing(; nslices::Integer=1, method::Symbol=:equal_area,
                             resolution::Integer=100,
                             center_position::Symbol=:centroid,
                             positions=Float64[])
    nslices > 0 || throw(ArgumentError("nslices must be positive"))
    resolution > 0 || throw(ArgumentError("slicing resolution must be positive"))
    method in (:equal_area, :equal_count, :equal_width, :equal_spaced,
               :normal_quantile, :gaussian, :Gaussian, :specified) ||
        throw(ArgumentError("unsupported longitudinal slicing method $(repr(method))"))
    center_position in (:centroid, :midpoint) || throw(ArgumentError(
        "center_position must be :centroid or :midpoint"))
    values = Float64.(positions)
    method === :specified && length(values) != nslices - 1 && throw(ArgumentError(
        "specified slicing requires nslices-1 internal positions"))
    return LongitudinalSlicing(Int(nslices), method, Int(resolution), center_position, values)
end

function LongitudinalSlicing(nslices::Integer; kwargs...)
    return LongitudinalSlicing(; nslices=Int(nslices), kwargs...)
end

const _LONGITUDINAL_SLICING_OPTION_SCHEMA = (
    nslices=ConfigurationOptionMeta(Int, 1, "Number of longitudinal slices.";
        category=:physics, consumer=:longitudinal_slicing),
    method=ConfigurationOptionMeta(Symbol, :equal_area, "Slice-boundary construction method.";
        category=:numerical, consumer=:longitudinal_slicing),
    resolution=ConfigurationOptionMeta(Int, 100, "Histogram resolution per slice.";
        category=:numerical, dependencies=(:method,), consumer=:longitudinal_slicing),
    center_position=ConfigurationOptionMeta(Symbol, :centroid, "Slice center convention.";
        category=:physics, consumer=:longitudinal_slicing),
    positions=ConfigurationOptionMeta(Vector{Float64}, Float64[],
        "Internal boundaries for :specified slicing.";
        category=:physics, dependencies=(:method,), consumer=:longitudinal_slicing),
)
slicing_option_schema(::Type{LongitudinalSlicing}=LongitudinalSlicing) =
    _LONGITUDINAL_SLICING_OPTION_SCHEMA
slicing_option_schema(::LongitudinalSlicing) = _LONGITUDINAL_SLICING_OPTION_SCHEMA

function configuration_report(slicing::LongitudinalSlicing)
    return Tuple(ConfigurationEntry(name, getproperty(slicing, name), getproperty(slicing, name),
        (name === :resolution && slicing.method !== :equal_area) ||
        (name === :positions && slicing.method !== :specified) ? :inactive_dependency : :resolved,
        name === :resolution && slicing.method !== :equal_area ?
            "resolution is unused by the selected slicing method" :
        name === :positions && slicing.method !== :specified ?
            "positions are used only by :specified slicing" :
            "validated longitudinal slicing configuration",
        meta.consumer) for (name, meta) in pairs(slicing_option_schema(slicing)))
end

"""
    GaussianPoissonSolver(; kbb1=nothing, kbb2=nothing,
                           luminosity_scale=nothing,
                           slicing=LongitudinalSlicing(),
                           slicing1=nothing, slicing2=nothing,
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

`slicing` applies the same longitudinal slicing to both beams. Use `slicing1`
and `slicing2` to specify different slicing configurations for beam 1 and beam
2.
"""
struct GaussianPoissonSolver{T<:Real} <: AbstractPoissonSolver
    kbb1::Union{Nothing,T}
    kbb2::Union{Nothing,T}
    luminosity_scale::Union{Nothing,T}
    slicing::LongitudinalSlicing
    slicing1::LongitudinalSlicing
    slicing2::LongitudinalSlicing
    requested_slicing1::Union{Nothing,LongitudinalSlicing}
    requested_slicing2::Union{Nothing,LongitudinalSlicing}
    min_sigma::T
    gaussian_when_luminosity::Int
    ignore_centroid1::Bool
    ignore_centroid2::Bool
end

_optional_solver_value(::Type{T}, value) where {T<:Real} =
    value === nothing ? nothing : T(value)

function GaussianPoissonSolver{T}(; kbb1=nothing, kbb2=nothing,
                                  luminosity_scale=nothing,
                                  slicing::LongitudinalSlicing=LongitudinalSlicing(),
                                  slicing1=nothing,
                                  slicing2=nothing,
                                  min_sigma=eps(T),
                                  gaussian_when_luminosity::Integer=2,
                                  ignore_centroid1::Bool=false,
                                  ignore_centroid2::Bool=false) where {T<:Real}
    s1 = slicing1 === nothing ? slicing : slicing1
    s2 = slicing2 === nothing ? slicing : slicing2
    min_sigma >= 0 || throw(ArgumentError("min_sigma must be nonnegative"))
    gaussian_when_luminosity in (1, 2) || throw(ArgumentError(
        "gaussian_when_luminosity must be 1 or 2"))
    return GaussianPoissonSolver{T}(
        _optional_solver_value(T, kbb1),
        _optional_solver_value(T, kbb2),
        _optional_solver_value(T, luminosity_scale),
        slicing,
        s1,
        s2,
        slicing1,
        slicing2,
        T(min_sigma),
        Int(gaussian_when_luminosity),
        ignore_centroid1,
        ignore_centroid2,
    )
end

GaussianPoissonSolver(; kwargs...) = GaussianPoissonSolver{Float64}(; kwargs...)

function solver_configuration(solver::GaussianPoissonSolver)
    configured = _solver_configured_values(solver)
    return merge(configured, (
        slicing1=solver.requested_slicing1,
        slicing2=solver.requested_slicing2,
        resolved_slicing1=solver.slicing1,
        resolved_slicing2=solver.slicing2,
    ))
end

const _GAUSSIAN_SOLVER_OPTION_SCHEMA = (
    kbb1=SolverOptionMeta(Union{Nothing,Real}, nothing,
        "Optional beam-1 kick-scale override."; category=:physics_override),
    kbb2=SolverOptionMeta(Union{Nothing,Real}, nothing,
        "Optional beam-2 kick-scale override."; category=:physics_override),
    luminosity_scale=SolverOptionMeta(Union{Nothing,Real}, nothing,
        "Optional luminosity normalization override."; category=:physics_override),
    slicing=SolverOptionMeta(LongitudinalSlicing, LongitudinalSlicing(),
        "Shared longitudinal slicing configuration."; category=:physics),
    slicing1=SolverOptionMeta(Union{Nothing,LongitudinalSlicing}, nothing,
        "Optional beam-1 slicing override."; category=:physics, dependencies=(:slicing,)),
    slicing2=SolverOptionMeta(Union{Nothing,LongitudinalSlicing}, nothing,
        "Optional beam-2 slicing override."; category=:physics, dependencies=(:slicing,)),
    min_sigma=SolverOptionMeta(Real, eps(Float64),
        "Lower transverse RMS bound used by Gaussian moments."; category=:numerical),
    gaussian_when_luminosity=SolverOptionMeta(Int, 2,
        "Select beam 1 or beam 2 macroparticle sampling for luminosity."; category=:numerical),
    ignore_centroid1=SolverOptionMeta(Bool, false,
        "Ignore beam-1 slice centroids in Gaussian moments."; category=:physics),
    ignore_centroid2=SolverOptionMeta(Bool, false,
        "Ignore beam-2 slice centroids in Gaussian moments."; category=:physics),
)

solver_option_schema(::Type{<:GaussianPoissonSolver}) = _GAUSSIAN_SOLVER_OPTION_SCHEMA

const StrongStrongGaussianPoissonSolver = GaussianPoissonSolver

"""
    PICPoissonSolver(; kbb1=nothing, kbb2=nothing, luminosity_scale=nothing,
                      grid=(128, 128), deposit_method=:CIC,
                      green_type=:integrated,
                      green_cache=:slice_pair,
                      slice_pair_green_min_ratio=0.50,
                      slice_pair_green_growth=0.25,
                      longitudinal_kick=true,
                      batch_mode=:wavefront,
                      cuda_async=true,
                      cuda_batch_fft=true,
                      cuda_wavefront_fft=true,
                      cuda_indexed_wavefront=true,
                      luminosity_grid=nothing,
                      luminosity_deposit_method=nothing,
                      luminosity_schedule=nothing,
                      slicing=LongitudinalSlicing(),
                      slicing1=nothing, slicing2=nothing)

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

`green_cache` may be `:none` or `:slice_pair`. The slice-pair cache keeps two
Green FFTs per slice-pair, one per beam-beam direction, and reuses each for the
left/right source-boundary charge planes when the current source and field
domains still fit inside the cached grids. `slice_pair_green_min_ratio`
controls when a cached grid is considered too large for the current domain; a
value of `0.50` means the current requested width and height must both be at
least half of the cached width and height. `slice_pair_green_growth` is the
fractional grid enlargement used when building or rebuilding a cached entry; a
value of `0.25` builds a grid 1.25 times larger than the current request.
`batch_mode` may be `:sequential` or `:wavefront`. Sequential mode preserves
the original one-slice-pair-at-a-time execution. Wavefront mode groups ready,
non-overlapping slice pairs with `collision_pair_batches`; it currently affects
the CUDA PIC path.
The CUDA execution options are explicit solver configuration. `cuda_async`
enables overlapping CUDA field work, `cuda_batch_fft` enables batched FFT
solves, `cuda_wavefront_fft` enables the wavefront FFT path, and
`cuda_indexed_wavefront` operates directly through slice indices without
reordering canonical particle storage. Shell examples may map environment
variables into these constructor options; runtime code does not read them.
`luminosity_schedule` may be `nothing` or a schedule such as
`EveryNSteps(step=10)` or `AtTurns([0, 100])`. `nothing` computes luminosity
on every turn. When the schedule does not run, PIC still applies beam-beam
kicks but returns `NaN` for luminosity to mark that it was intentionally not
computed. `StrongStrongTask` does not write those skipped turns to its
luminosity output file; the file contains only evaluated turns. A luminosity
that evaluates to `NaN` on a scheduled turn is still written so numerical
failures remain visible and are not confused with schedule skips.
The first output row contains `turn` followed by collision labels in line
order, so each luminosity column remains identifiable for multiple IPs.
`luminosity_grid` may be `nothing` or a transverse `(nx, ny)` mesh. `nothing`
inherits the dimensions of `grid`, preserving the historical behavior; the
luminosity deposition workspace remains separate from the force grids. An
explicit value changes only luminosity deposition and does not change the PIC
force solve.
`luminosity_deposit_method` may be `nothing`, `:CIC`, or `:TSC`. `nothing`
inherits `deposit_method`; an explicit method changes only luminosity
deposition. This keeps force and luminosity deposition consistent by default
while allowing controlled quadrature studies.

CUDA execution uses atomic grid deposition and CUDA FFT convolution. The first
CUDA implementation is correctness-oriented; later versions may replace atomic
deposition with binned or tiled reductions for dense beams.

`slicing` applies the same longitudinal slicing to both beams. Use `slicing1`
and `slicing2` to specify different slicing configurations for beam 1 and beam
2.
"""
struct PICPoissonSolver{T<:Real} <: AbstractPoissonSolver
    kbb1::Union{Nothing,T}
    kbb2::Union{Nothing,T}
    luminosity_scale::Union{Nothing,T}
    grid::Tuple{Int,Int}
    deposit_method::Symbol
    green_type::Symbol
    green_cache::Symbol
    slice_pair_green_min_ratio::T
    slice_pair_green_growth::T
    longitudinal_kick::Bool
    batch_mode::Symbol
    cuda_async::Bool
    cuda_batch_fft::Bool
    cuda_wavefront_fft::Bool
    cuda_indexed_wavefront::Bool
    luminosity_grid::Union{Nothing,Tuple{Int,Int}}
    luminosity_deposit_method::Union{Nothing,Symbol}
    luminosity_schedule::Union{Nothing,AbstractSchedule}
    slicing::LongitudinalSlicing
    slicing1::LongitudinalSlicing
    slicing2::LongitudinalSlicing
    requested_slicing1::Union{Nothing,LongitudinalSlicing}
    requested_slicing2::Union{Nothing,LongitudinalSlicing}
    backend_configurations::Tuple
end

function PICPoissonSolver{T}(; kbb1=nothing, kbb2=nothing,
                             luminosity_scale=nothing,
                             grid=(128, 128),
                             deposit_method::Symbol=:CIC,
                             green_type::Symbol=:integrated,
                             green_cache::Symbol=:slice_pair,
                             slice_pair_green_min_ratio=0.50,
                             slice_pair_green_growth=0.25,
                             longitudinal_kick::Bool=true,
                             batch_mode::Symbol=:wavefront,
                             cuda_async::Bool=true,
                             cuda_batch_fft::Bool=true,
                             cuda_wavefront_fft::Bool=true,
                             cuda_indexed_wavefront::Bool=true,
                             luminosity_grid=nothing,
                             luminosity_deposit_method::Union{Nothing,Symbol}=nothing,
                             luminosity_schedule::Union{Nothing,AbstractSchedule}=nothing,
                             slicing::LongitudinalSlicing=LongitudinalSlicing(),
                             slicing1=nothing,
                             slicing2=nothing,
                             backend_configurations=()) where {T<:Real}
    s1 = slicing1 === nothing ? slicing : slicing1
    s2 = slicing2 === nothing ? slicing : slicing2
    min_ratio = T(slice_pair_green_min_ratio)
    growth = T(slice_pair_green_growth)
    zero(T) < min_ratio <= one(T) || throw(ArgumentError(
        "slice_pair_green_min_ratio must be in (0, 1]; got $(slice_pair_green_min_ratio)."
    ))
    growth >= zero(T) || throw(ArgumentError(
        "slice_pair_green_growth must be non-negative; got $(slice_pair_green_growth)."
    ))
    grid_value = (Int(grid[1]), Int(grid[2]))
    all(>=(5), grid_value) || throw(ArgumentError(
        "PICPoissonSolver grid dimensions must both be at least 5; got $(grid)."))
    deposit_method in (:CIC, :TSC) || throw(ArgumentError(
        "deposit_method must be :CIC or :TSC; got $(repr(deposit_method))."))
    green_type in (:integrated, :standard) || throw(ArgumentError(
        "green_type must be :integrated or :standard; got $(repr(green_type))."))
    green_cache in (:none, :slice_pair) || throw(ArgumentError(
        "green_cache must be :none or :slice_pair; got $(repr(green_cache))."))
    batch_mode in (:sequential, :wavefront) || throw(ArgumentError(
        "batch_mode must be :sequential or :wavefront; got $(repr(batch_mode))."))
    lum_grid = luminosity_grid === nothing ? nothing :
        (Int(luminosity_grid[1]), Int(luminosity_grid[2]))
    lum_grid === nothing || all(>=(3), lum_grid) || throw(ArgumentError(
        "luminosity_grid dimensions must both be at least 3; got $(luminosity_grid)."
    ))
    (luminosity_deposit_method === nothing ||
     luminosity_deposit_method === :CIC || luminosity_deposit_method === :TSC) ||
        throw(ArgumentError(
            "luminosity_deposit_method must be nothing, :CIC, or :TSC; got $(repr(luminosity_deposit_method))."
        ))
    configs = Tuple(backend_configurations)
    all(config -> config isa CUDAPICLaunchConfig, configs) || throw(ArgumentError(
        "PIC backend_configurations currently accepts only CUDAPICLaunchConfig values"))
    count(config -> config isa CUDAPICLaunchConfig, configs) <= 1 || throw(ArgumentError(
        "PICPoissonSolver accepts at most one CUDAPICLaunchConfig"))
    return PICPoissonSolver{T}(
        _optional_solver_value(T, kbb1),
        _optional_solver_value(T, kbb2),
        _optional_solver_value(T, luminosity_scale),
        grid_value,
        deposit_method,
        green_type,
        green_cache,
        min_ratio,
        growth,
        longitudinal_kick,
        batch_mode,
        cuda_async,
        cuda_batch_fft,
        cuda_wavefront_fft,
        cuda_indexed_wavefront,
        lum_grid,
        luminosity_deposit_method,
        luminosity_schedule,
        slicing,
        s1,
        s2,
        slicing1,
        slicing2,
        configs,
    )
end

PICPoissonSolver(; kwargs...) = PICPoissonSolver{Float64}(; kwargs...)

_pic_luminosity_grid(solver::PICPoissonSolver) =
    solver.luminosity_grid === nothing ? solver.grid : solver.luminosity_grid

_pic_luminosity_deposit_method(solver::PICPoissonSolver) =
    solver.luminosity_deposit_method === nothing ? solver.deposit_method : solver.luminosity_deposit_method

function solver_configuration(solver::PICPoissonSolver)
    configured = _solver_configured_values(solver)
    return merge(configured, (
        slicing1=solver.requested_slicing1,
        slicing2=solver.requested_slicing2,
        resolved_slicing1=solver.slicing1,
        resolved_slicing2=solver.slicing2,
        resolved_luminosity_grid=_pic_luminosity_grid(solver),
        resolved_luminosity_deposit_method=_pic_luminosity_deposit_method(solver),
    ))
end

const _PIC_SOLVER_OPTION_SCHEMA = (
    kbb1 = SolverOptionMeta(Union{Nothing,Real}, nothing,
        "Optional beam-1 kick-scale override."; category=:physics_override),
    kbb2 = SolverOptionMeta(Union{Nothing,Real}, nothing,
        "Optional beam-2 kick-scale override."; category=:physics_override),
    luminosity_scale = SolverOptionMeta(Union{Nothing,Real}, nothing,
        "Optional luminosity normalization override."; category=:physics_override),
    grid = SolverOptionMeta(Tuple{Int,Int}, (128, 128),
        "Physical transverse PIC mesh dimensions."),
    deposit_method = SolverOptionMeta(Symbol, :CIC,
        "Particle-to-grid deposition and field-interpolation method; :CIC or :TSC."),
    green_type = SolverOptionMeta(Symbol, :integrated,
        "Open-boundary logarithmic Green kernel; :integrated or :standard."),
    green_cache = SolverOptionMeta(Symbol, :slice_pair,
        "Persistent Green FFT caching mode; :slice_pair or :none."; category=:execution),
    slice_pair_green_min_ratio = SolverOptionMeta(Real, 0.50,
        "Minimum requested-to-cached domain ratio before rebuilding a slice-pair Green entry.";
        category=:accuracy_performance, dependencies=(:green_cache,)),
    slice_pair_green_growth = SolverOptionMeta(Real, 0.25,
        "Fractional domain enlargement when building a slice-pair Green entry.";
        category=:accuracy_performance, dependencies=(:green_cache,)),
    longitudinal_kick = SolverOptionMeta(Bool, true,
        "Apply the Hirata-map potential-difference longitudinal kick."; category=:physics),
    batch_mode = SolverOptionMeta(Symbol, :wavefront,
        "Slice-pair scheduling mode; :wavefront or :sequential.";
        category=:execution, consumer=:cuda_pic_algorithm),
    cuda_async = SolverOptionMeta(Bool, true,
        "Overlap independent CUDA field work.";
        supported_backends=(CUDABackend,), category=:execution,
        consumer=:cuda_pic_algorithm),
    cuda_batch_fft = SolverOptionMeta(Bool, true,
        "Use batched CUDA FFT field solves.";
        supported_backends=(CUDABackend,), category=:execution,
        dependencies=(:cuda_async,), consumer=:cuda_pic_algorithm),
    cuda_wavefront_fft = SolverOptionMeta(Bool, true,
        "Batch FFT planes across each CUDA collision wavefront.";
        supported_backends=(CUDABackend,), category=:execution,
        dependencies=(:batch_mode, :cuda_async, :cuda_batch_fft),
        consumer=:cuda_pic_algorithm),
    cuda_indexed_wavefront = SolverOptionMeta(Bool, true,
        "Track slice membership by indices without gathering, sorting, or changing particle IDs.";
        supported_backends=(CUDABackend,), category=:execution,
        dependencies=(:batch_mode, :cuda_async, :cuda_batch_fft, :cuda_wavefront_fft),
        consumer=:cuda_pic_algorithm),
    luminosity_grid = SolverOptionMeta(Union{Nothing,Tuple{Int,Int}}, nothing,
        "Optional luminosity-only transverse mesh; nothing inherits the PIC force-grid dimensions.";
        category=:accuracy_performance),
    luminosity_deposit_method = SolverOptionMeta(Union{Nothing,Symbol}, nothing,
        "Luminosity deposition method; nothing inherits deposit_method, or set :CIC/:TSC explicitly.";
        category=:accuracy_performance, dependencies=(:deposit_method,)),
    luminosity_schedule = SolverOptionMeta(Union{Nothing,AbstractSchedule}, nothing,
        "Schedule for luminosity evaluation; nothing evaluates every turn."; category=:diagnostic),
    slicing = SolverOptionMeta(LongitudinalSlicing, LongitudinalSlicing(),
        "Shared longitudinal slicing configuration for both beams."; category=:physics),
    slicing1 = SolverOptionMeta(Union{Nothing,LongitudinalSlicing}, nothing,
        "Optional beam-1 slicing override."; category=:physics, dependencies=(:slicing,)),
    slicing2 = SolverOptionMeta(Union{Nothing,LongitudinalSlicing}, nothing,
        "Optional beam-2 slicing override."; category=:physics, dependencies=(:slicing,)),
    backend_configurations = SolverOptionMeta(Tuple, (),
        "Optional backend-specific implementation configuration, currently CUDAPICLaunchConfig.";
        supported_backends=(CUDABackend,), category=:execution),
)

solver_option_schema(::Type{<:PICPoissonSolver}) = _PIC_SOLVER_OPTION_SCHEMA

function _pic_option_active(name::Symbol, solver::PICPoissonSolver)
    name === :slice_pair_green_min_ratio && return solver.green_cache === :slice_pair
    name === :slice_pair_green_growth && return solver.green_cache === :slice_pair
    name === :cuda_batch_fft && return solver.cuda_async
    name === :cuda_wavefront_fft &&
        return solver.batch_mode === :wavefront && solver.cuda_async && solver.cuda_batch_fft
    name === :cuda_indexed_wavefront &&
        return solver.batch_mode === :wavefront && solver.cuda_async &&
               solver.cuda_batch_fft && solver.cuda_wavefront_fft
    return true
end

function configuration_report(solver::PICPoissonSolver;
                              policy::Union{Nothing,AbstractExecutionPolicy}=nothing,
                              backend=nothing)
    selected_backend = backend === nothing ?
        (policy === nothing ? nothing : backend_type(policy)) : backend
    configured = solver_configuration(solver)
    entries = ConfigurationEntry[]
    for (name, meta) in pairs(solver_option_schema(solver))
        requested = getproperty(configured, name)
        if selected_backend !== nothing && !(selected_backend in meta.supported_backends)
            push!(entries, ConfigurationEntry(name, requested, requested, :inactive_backend,
                "option does not apply to $(selected_backend)", meta.consumer))
        elseif !_pic_option_active(name, solver)
            push!(entries, ConfigurationEntry(name, requested, requested, :inactive_dependency,
                "one or more declared dependencies disable this option", meta.consumer))
        else
            resolved = name === :luminosity_grid ? configured.resolved_luminosity_grid :
                       name === :luminosity_deposit_method ? configured.resolved_luminosity_deposit_method :
                       name === :slicing1 ? configured.resolved_slicing1 :
                       name === :slicing2 ? configured.resolved_slicing2 : requested
            status = requested === nothing && resolved !== nothing ? :inherited : :resolved
            push!(entries, ConfigurationEntry(name, requested, resolved, status,
                status === :inherited ? "inherited from the associated shared option" :
                                        "validated solver configuration",
                meta.consumer))
        end
    end
    if selected_backend === CUDABackend
        cuda_policy = policy isa GPUExecutionPolicy ? _legacy_cuda_policy(policy) : policy
        generic_threads = cuda_policy isa CUDAExecutionPolicy ? cuda_policy.launch.threads : 256
        config = _cuda_pic_configuration(solver)
        for family in _CUDA_PIC_LAUNCH_FAMILIES
            field = Symbol(family, :_threads)
            requested = config === nothing ? nothing : getproperty(config, field)
            resolved = something(requested, generic_threads)
            push!(entries, ConfigurationEntry(Symbol(:cuda_pic_, family, :_threads),
                requested, resolved, requested === nothing ? :inherited : :resolved,
                requested === nothing ? "inherited from CUDAExecutionPolicy" :
                                        "explicit CUDAPICLaunchConfig override",
                :cuda_pic_launch))
        end
    end
    return Tuple(entries)
end

function configuration_report(solver::GaussianPoissonSolver;
                              policy::Union{Nothing,AbstractExecutionPolicy}=nothing,
                              backend=nothing)
    configured = solver_configuration(solver)
    entries = ConfigurationEntry[]
    for (name, meta) in pairs(solver_option_schema(solver))
        requested = getproperty(configured, name)
        resolved = name === :slicing1 ? configured.resolved_slicing1 :
                   name === :slicing2 ? configured.resolved_slicing2 : requested
        status = requested === nothing && resolved !== nothing ? :inherited : :resolved
        push!(entries, ConfigurationEntry(name, requested, resolved, status,
            status === :inherited ? "inherited from shared slicing" :
                                    "validated Gaussian solver configuration",
            meta.consumer))
    end
    return Tuple(entries)
end

function configuration_report(diagnostics::StrongStrongDiagnostics; backend=nothing)
    entries = ConfigurationEntry[]
    for (name, meta) in pairs(diagnostics_option_schema(diagnostics))
        requested = getproperty(diagnostics, name)
        if backend !== nothing && !(backend in meta.supported_backends)
            push!(entries, ConfigurationEntry(name, requested, requested, :inactive_backend,
                "diagnostic does not apply to $(backend)", meta.consumer))
        else
            push!(entries, ConfigurationEntry(name, requested, requested, :resolved,
                "validated diagnostic configuration", meta.consumer))
        end
    end
    return Tuple(entries)
end

function validate_configuration_metadata()
    errors = String[]
    for policy_type in (CPUThreadsExecutionPolicy, CUDAExecutionPolicy, GPUExecutionPolicy)
        schema = policy_option_schema(policy_type)
        for (name, meta) in pairs(schema)
            meta.consumer === :unspecified && push!(errors,
                "$(policy_type).$(name) has no runtime consumer")
        end
    end
    default_cpu = CPUThreadsExecutionPolicy()
    policy_option_schema(default_cpu).threads.default === :auto ||
        push!(errors, "CPU policy metadata default disagrees with constructor")
    default_cuda = CUDAExecutionPolicy()
    default_cuda.launch.threads == policy_option_schema(default_cuda).threads.default ||
        push!(errors, "CUDA thread metadata default disagrees with constructor")
    default_cuda.launch.blocks == policy_option_schema(default_cuda).blocks.default ||
        push!(errors, "CUDA block metadata default disagrees with constructor")
    Set(fieldnames(CUDALaunchConfig)) == Set((:threads, :blocks)) ||
        push!(errors, "CUDALaunchConfig public fields changed without metadata review")
    policy_option_schema(GPUExecutionPolicy).threads.default == 256 ||
        push!(errors, "legacy GPU thread metadata default disagrees with constructor")
    policy_option_schema(GPUExecutionPolicy).blocks.default == 256 ||
        push!(errors, "legacy GPU block metadata default disagrees with constructor")

    Set(keys(slicing_option_schema())) == Set(fieldnames(LongitudinalSlicing)) ||
        push!(errors, "LongitudinalSlicing fields and metadata keys disagree")
    default_slicing = LongitudinalSlicing()
    for (name, meta) in pairs(slicing_option_schema())
        meta.consumer === :unspecified && push!(errors,
            "LongitudinalSlicing.$(name) has no runtime consumer")
        isequal(getproperty(default_slicing, name), meta.default) || push!(errors,
            "LongitudinalSlicing.$(name) metadata default disagrees with constructor")
    end

    Set(keys(cuda_pic_launch_option_schema())) == Set(fieldnames(CUDAPICLaunchConfig)) ||
        push!(errors, "CUDAPICLaunchConfig fields and metadata keys disagree")
    for (name, meta) in pairs(cuda_pic_launch_option_schema())
        meta.consumer === :unspecified && push!(errors,
            "CUDAPICLaunchConfig.$(name) has no runtime consumer")
    end
    solver_fields = Set(fieldnames(PICPoissonSolver))
    schema_fields = Set(keys(solver_option_schema(PICPoissonSolver)))
    internal_fields = Set((:requested_slicing1, :requested_slicing2))
    schema_fields == setdiff(solver_fields, internal_fields) || push!(errors,
        "PICPoissonSolver fields and solver_option_schema keys disagree")
    for (name, meta) in pairs(solver_option_schema(PICPoissonSolver))
        meta.consumer === :unspecified && push!(errors,
            "PICPoissonSolver.$(name) has no runtime consumer")
    end
    default_pic = solver_configuration(PICPoissonSolver())
    for (name, meta) in pairs(solver_option_schema(PICPoissonSolver))
        isequal(getproperty(default_pic, name), meta.default) || push!(errors,
            "PICPoissonSolver.$(name) metadata default disagrees with constructor")
    end
    gaussian_fields = Set(fieldnames(GaussianPoissonSolver))
    gaussian_schema_fields = Set(keys(solver_option_schema(GaussianPoissonSolver)))
    gaussian_schema_fields == setdiff(gaussian_fields, internal_fields) || push!(errors,
        "GaussianPoissonSolver fields and solver_option_schema keys disagree")
    default_gaussian = solver_configuration(GaussianPoissonSolver())
    for (name, meta) in pairs(solver_option_schema(GaussianPoissonSolver))
        meta.consumer === :unspecified && push!(errors,
            "GaussianPoissonSolver.$(name) has no runtime consumer")
        isequal(getproperty(default_gaussian, name), meta.default) || push!(errors,
            "GaussianPoissonSolver.$(name) metadata default disagrees with constructor")
    end
    Set(keys(diagnostics_option_schema())) == Set(fieldnames(StrongStrongDiagnostics)) ||
        push!(errors, "StrongStrongDiagnostics fields and metadata keys disagree")
    default_diagnostics = StrongStrongDiagnostics()
    for (name, meta) in pairs(diagnostics_option_schema())
        meta.consumer === :unspecified && push!(errors,
            "StrongStrongDiagnostics.$(name) has no runtime consumer")
        isequal(getproperty(default_diagnostics, name), meta.default) || push!(errors,
            "StrongStrongDiagnostics.$(name) metadata default disagrees with constructor")
    end
    for schedule_type in (AlwaysSchedule, EveryNSteps, AtTurns)
        for (name, meta) in pairs(schedule_option_schema(schedule_type))
            meta.consumer === :unspecified && push!(errors,
                "$(schedule_type).$(name) has no runtime consumer")
        end
    end
    default_every = EveryNSteps()
    for (name, meta) in pairs(schedule_option_schema(default_every))
        isequal(getproperty(default_every, name), meta.default) || push!(errors,
            "EveryNSteps.$(name) metadata default disagrees with constructor")
    end
    for (_, meta) in pairs(schedule_option_schema(PredicateSchedule(identity)))
        meta.consumer === :unspecified && push!(errors,
            "PredicateSchedule has no runtime consumer")
    end
    observer_instances = (
        BeamMomentObserver("metadata.bin"),
        JLD2BeamMomentObserver("metadata.jld2"),
        MomentObserver("metadata.h5"),
        CoordinateSnapshotObserver("metadata.coord"),
        LuminosityObserver("metadata.lum"),
    )
    for observer_type in (BeamMomentObserver, JLD2BeamMomentObserver, MomentObserver,
                          CoordinateSnapshotObserver, LuminosityObserver)
        for (name, meta) in pairs(observer_option_schema(observer_type))
            meta.consumer === :unspecified && push!(errors,
                "$(observer_type).$(name) has no runtime consumer")
        end
    end
    for observer in observer_instances
        schema_names = Set(keys(observer_option_schema(observer)))
        report_names = Set(entry.name for entry in configuration_report(observer))
        schema_names == report_names || push!(errors,
            "$(typeof(observer)) schema and configuration-report keys disagree")
    end
    isempty(errors) || throw(ArgumentError(join(errors, '\n')))
    return true
end

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
segments whenever possible. With `policy=nothing`, an execution policy is
inferred from the two beam containers passed to `execute!`. An explicit policy
must match both beams, including the CUDA device, and is resolved once for both
line streams and collision solvers. The immutable
`TrackingContext` used by context-aware stochastic tracking snapshots the
Octopus global RNG state at execution time.

```julia
ip = StrongStrongCollision(:ip; poisson_solver=solver)
line1 = (arc1_to_ip, ip, arc1_after_ip)
line2 = (arc2_to_ip, ip, arc2_after_ip)
task = StrongStrongTask(line1, line2)
execute!(task, beam1, beam2; turns=10)
```

Pass `diagnostics=StrongStrongDiagnostics(record_turn_times=true)` to
synchronize once at each turn boundary and record complete-turn wall time.
Retrieve structured results with `diagnostic_summary(task)`. The legacy
`record_turn_times` task keyword remains as a compatibility adapter.

Use `validate(StrongStrongGaussianBackendConsistencyContract())` to check the
soft-Gaussian solver across CPU and CUDA. Use
`validate(StrongStrongPICBackendConsistencyContract())` to check PIC
coordinates, luminosity, and persistent cache history.
"""
struct StrongStrongTask{L1<:Tuple,L2<:Tuple,S<:AbstractPoissonSolver} <: AbstractTask
    line1::L1
    line2::L2
    policy::Union{Nothing,AbstractExecutionPolicy}
    default_poisson_solver::S
    luminosity_path::Union{Nothing,String}
    diagnostics::StrongStrongDiagnostics
    turn_times::Vector{Float64}
    pic_phase_times::Vector{Any}
    runtime_entries_cache1::Base.RefValue{Any}
    runtime_entries_cache2::Base.RefValue{Any}
    plan_cache1::Dict{Any,Any}
    plan_cache2::Dict{Any,Any}
    runtime_cache::Dict{Any,Any}
end

function configuration_report(task::StrongStrongTask, beam1::Beam, beam2::Beam)
    policy = _resolve_strong_strong_policy(task, beam1, beam2)
    public_policy = task.policy === nothing ?
        (backend_type(policy) === CPUThreadsBackend ? CPUThreadsExecutionPolicy() : CUDAExecutionPolicy()) :
        task.policy
    blocks1 = _strong_strong_runtime_blocks(task, 1)
    blocks2 = _strong_strong_runtime_blocks(task, 2)
    _validate_strong_strong_blocks(blocks1, blocks2)
    solvers = unique(_collision_solver(task, block1.collision, block2.collision)
                     for (block1, block2) in zip(blocks1, blocks2)
                     if block1.collision !== nothing)
    return (
        policy=configuration_report(public_policy, beam1.rep),
        output=(ConfigurationEntry(:luminosity_path, task.luminosity_path,
            task.luminosity_path,
            task.luminosity_path === nothing ? :inactive_dependency : :resolved,
            task.luminosity_path === nothing ? "luminosity file output disabled" :
                                               "active task-level luminosity output path",
            :strong_strong_output),),
        diagnostics=configuration_report(task.diagnostics; backend=backend_type(policy)),
        solvers=Tuple(configuration_report(solver; policy=public_policy,
                                           backend=backend_type(policy)) for solver in solvers),
    )
end

required_contracts(::Type{<:StrongStrongTask}) =
    DataType[StrongStrongGaussianBackendConsistencyContract,
             StrongStrongPICBackendConsistencyContract]
required_contracts(::StrongStrongTask) =
    DataType[StrongStrongGaussianBackendConsistencyContract,
             StrongStrongPICBackendConsistencyContract]

function StrongStrongTask(line1, line2;
                          policy::Union{Nothing,AbstractExecutionPolicy}=nothing,
                          seed=nothing,
                          default_poisson_solver::AbstractPoissonSolver=GaussianPoissonSolver(),
                          poisson_solver::Union{Nothing,AbstractPoissonSolver}=nothing,
                          luminosity_path::Union{Nothing,AbstractString}=nothing,
                          diagnostics::StrongStrongDiagnostics=StrongStrongDiagnostics(),
                          record_turn_times::Union{Nothing,Bool}=nothing)
    line_tuple1 = _element_tuple(line1)
    line_tuple2 = _element_tuple(line2)
    seed !== nothing && @warn "StrongStrongTask seed keyword is deprecated; use set_global_rng!(seed=...) instead." seed
    solver = poisson_solver === nothing ? default_poisson_solver : poisson_solver
    if record_turn_times !== nothing
        diagnostics == StrongStrongDiagnostics() || throw(ArgumentError(
            "use either diagnostics or the compatibility record_turn_times keyword, not both"
        ))
        diagnostics = StrongStrongDiagnostics(record_turn_times=record_turn_times)
    end
    return StrongStrongTask(
        line_tuple1,
        line_tuple2,
        policy,
        solver,
        luminosity_path === nothing ? nothing : String(luminosity_path),
        diagnostics,
        Float64[],
        Any[],
        Ref{Any}(nothing),
        Ref{Any}(nothing),
        Dict{Any,Any}(),
        Dict{Any,Any}(),
        Dict{Any,Any}(),
    )
end

"""Return complete-turn timings in seconds from the most recent task execution."""
turn_timings(task::StrongStrongTask) = copy(task.turn_times)
"""Return structured CUDA PIC phase records from the most recent execution."""
pic_phase_timings(task::StrongStrongTask) = copy(task.pic_phase_times)
"""Return explicit diagnostic configuration and collected timing results."""
diagnostic_summary(task::StrongStrongTask) = (
    configuration=task.diagnostics,
    turn_timings=turn_timings(task),
    pic_phase_timings=pic_phase_timings(task),
)

"""
    execute!(task::StrongStrongTask, beam1, beam2; turns=1)

Execute a strong-strong task in place. Returns `(beam1, beam2)`.
"""
function execute!(task::StrongStrongTask, beam1::Beam, beam2::Beam; turns::Integer=1)
    empty!(task.turn_times)
    empty!(task.pic_phase_times)
    policy = _resolve_strong_strong_policy(task, beam1, beam2)
    return _with_execution_policy(policy) do
        _execute_strong_strong_task!(task, beam1, beam2, Int(turns), policy)
    end
end

function _execute_strong_strong_task!(task, beam1, beam2, turns::Int, policy)
    _warn_inactive_diagnostics(task.diagnostics, backend_type(policy))
    _record_execution!(:strong_strong_diagnostics, backend_type(policy), (
        record_turn_times=task.diagnostics.record_turn_times,
        memory_log_every=task.diagnostics.memory_log_every,
        pic_timing=task.diagnostics.pic_timing,
        pic_timing_detail=task.diagnostics.pic_timing_detail,
        cache_stats=task.diagnostics.cache_stats,
        nvtx=task.diagnostics.nvtx,
    ))
    _record_execution!(:strong_strong_output, backend_type(policy),
                       (luminosity_path=task.luminosity_path,))
    blocks1 = _strong_strong_runtime_blocks(task, 1)
    blocks2 = _strong_strong_runtime_blocks(task, 2)
    _validate_strong_strong_blocks(blocks1, blocks2)
    _preflight_solver_configurations!(task, blocks1, blocks2, policy)
    prepare_observers!(_line_observers(blocks1), _strong_strong_physics_line(blocks1); turns=Int(turns))
    prepare_observers!(_line_observers(blocks2), _strong_strong_physics_line(blocks2); turns=Int(turns))
    try
        ctx = TrackingContext()
        Base.ScopedValues.with(_ACTIVE_STRONG_STRONG_DIAGNOSTICS => task.diagnostics,
                               _ACTIVE_PIC_PHASE_TIMING_SINK => task.pic_phase_times) do
            if task.luminosity_path === nothing
                _execute_strong_strong_turns!(task, beam1, beam2, blocks1, blocks2, policy, ctx, turns, nothing)
            else
                open(task.luminosity_path, "w") do io
                    _write_strong_strong_luminosity_header(io, blocks1)
                    _execute_strong_strong_turns!(task, beam1, beam2, blocks1, blocks2, policy, ctx, turns, io)
                end
            end
        end
    finally
        _finalize_strong_strong_line_observers!(blocks1)
        _finalize_strong_strong_line_observers!(blocks2)
    end
    return beam1, beam2
end

function _preflight_solver_configurations!(task, blocks1, blocks2, policy)
    inactive = Set{Symbol}()
    for (block1, block2) in zip(blocks1, blocks2)
        block1.collision === nothing && continue
        solver = _collision_solver(task, block1.collision, block2.collision)
        solver isa PICPoissonSolver || continue
        if policy isa ResolvedCUDAExecutionPolicy
            _resolve_cuda_pic_configuration(solver, policy)
        else
            for (name, meta) in pairs(solver_option_schema(solver))
                CPUThreadsBackend in meta.supported_backends && continue
                requested = getproperty(solver_configuration(solver), name)
                isequal(requested, meta.default) || push!(inactive, name)
            end
        end
    end
    isempty(inactive) || @warn "non-default CUDA PIC options are inactive on CPU storage" options=sort!(collect(inactive))
    return nothing
end

function _warn_inactive_diagnostics(diagnostics::StrongStrongDiagnostics, backend)
    inactive = Symbol[]
    for (name, meta) in pairs(diagnostics_option_schema(diagnostics))
        backend in meta.supported_backends && continue
        isequal(getproperty(diagnostics, name), meta.default) || push!(inactive, name)
    end
    isempty(inactive) || @warn "non-default diagnostics are inactive on the selected backend" backend options=inactive
    return nothing
end

function _write_strong_strong_luminosity_header(io, blocks)
    print(io, "turn")
    for block in blocks
        block.collision === nothing || print(io, '\t', block.collision.label)
    end
    println(io)
    return nothing
end

function _resolve_strong_strong_policy(task::StrongStrongTask,
                                       beam1::Beam{BTAG1}, beam2::Beam{BTAG2}) where {BTAG1<:AbstractExecutionBackend,BTAG2<:AbstractExecutionBackend}
    BTAG1 === BTAG2 || throw(ArgumentError(
        "strong-strong tracking requires both beams to use the same backend; got $(BTAG1) and $(BTAG2)."
    ))
    policy1 = _resolve_execution_policy(task.policy, beam1.rep)
    policy2 = _resolve_execution_policy(task.policy, beam2.rep)
    typeof(policy1) === typeof(policy2) || throw(ArgumentError(
        "strong-strong beams resolved to different execution policies"))
    if policy1 isa ResolvedCUDAExecutionPolicy
        policy1.device == policy2.device || throw(ArgumentError(
            "strong-strong CUDA beams must reside on the same device; got $(policy1.device) and $(policy2.device)"))
    end
    return policy1
end

function _execute_strong_strong_turns!(task, beam1, beam2, blocks1, blocks2, policy, ctx, turns::Int, io)
    backend = backend_type(policy)
    streams = _strong_strong_segment_streams(policy)
    memory_log_every = _strong_strong_cuda_memory_log_every(backend)
    for turn in 0:(turns - 1)
        turn_t0 = task.diagnostics.record_turn_times ? time_ns() : UInt64(0)
        ctx = with_turn(ctx, turn)
        luminosities = io === nothing ? nothing : Float64[]
        luminosity_evaluated = io === nothing ? nothing : Bool[]
        turn_range = _cuda_nvtx_push(backend, "strongstrong turn")
        for j in eachindex(blocks1)
            line_range = _cuda_nvtx_push(backend, "strongstrong line tracking")
            _execute_strong_strong_segment_pair!(
                beam1.rep, blocks1[j].entries, task.plan_cache1,
                beam2.rep, blocks2[j].entries, task.plan_cache2,
                policy, ctx, streams, j,
            )
            _cuda_nvtx_pop(backend, line_range)
            if blocks1[j].collision !== nothing
                solver = _collision_solver(task, blocks1[j].collision, blocks2[j].collision)
                luminosity_evaluated === nothing ||
                    push!(luminosity_evaluated, _strong_strong_luminosity_evaluated(solver, ctx))
                collision_range = _cuda_nvtx_push(backend, "strongstrong collision")
                lum = _strong_strong_collide!(
                    task, blocks1[j].collision.label, solver, beam1, beam2, policy, ctx,
                )
                _cuda_nvtx_pop(backend, collision_range)
                luminosities === nothing || push!(luminosities, Float64(lum))
            end
        end
        _cuda_nvtx_pop(backend, turn_range)
        if luminosities !== nothing && !isempty(luminosities) && all(luminosity_evaluated)
            print(io, turn)
            for lum in luminosities
                print(io, '\t', lum)
            end
            println(io)
        end
        _strong_strong_maybe_log_cuda_memory(backend, turn, memory_log_every)
        if task.diagnostics.record_turn_times
            backend === CUDABackend && CUDA.synchronize()
            push!(task.turn_times, (time_ns() - turn_t0) * 1.0e-9)
        end
    end
    return nothing
end

function _strong_strong_collide!(task::StrongStrongTask, label::Symbol,
                                 solver::AbstractPoissonSolver,
                                 beam1::Beam, beam2::Beam, policy, ctx::TrackingContext)
    return Base.ScopedValues.with(_ACTIVE_PIC_TIMING_CONTEXT => (label=label, turn=ctx.turn)) do
        _record_execution!(:strong_strong_collision, backend_type(policy),
                           (solver=Symbol(nameof(typeof(solver))), turn=ctx.turn))
        if solver isa PICPoissonSolver
            _record_execution!(:solver_runtime, backend_type(policy), (
                deposit_method=solver.deposit_method,
                green_type=solver.green_type,
                green_cache=solver.green_cache,
                longitudinal_kick=solver.longitudinal_kick,
                batch_mode=solver.batch_mode,
                cuda_async=solver.cuda_async,
                cuda_batch_fft=solver.cuda_batch_fft,
                cuda_wavefront_fft=solver.cuda_wavefront_fft,
                cuda_indexed_wavefront=solver.cuda_indexed_wavefront,
                luminosity_grid=_pic_luminosity_grid(solver),
                luminosity_deposit_method=_pic_luminosity_deposit_method(solver),
            ))
        end
        _with_solver_execution_configuration(solver, policy) do
            _strong_strong_collide_backend!(
                task, label, solver, beam1, beam2, backend_type(policy), ctx,
            )
        end
    end
end

function _strong_strong_collide_backend!(task, label, solver, beam1, beam2, backend, ctx)
    return collide!(solver, beam1, beam2, backend, ctx)
end

_pic_compute_luminosity(::PICPoissonSolver, ::Nothing) = true
function _pic_compute_luminosity(solver::PICPoissonSolver, ctx::TrackingContext)
    schedule = solver.luminosity_schedule
    evaluated = schedule === nothing || should_run(schedule, ctx)
    active_policy = _ACTIVE_RESOLVED_POLICY[]
    active_backend = active_policy isa AbstractResolvedExecutionPolicy ?
        backend_type(active_policy) : :unknown
    _record_execution!(:pic_luminosity_schedule, active_backend,
                       (turn=ctx.turn, evaluated=evaluated,
                        schedule=schedule === nothing ? :every_turn : Symbol(nameof(typeof(schedule)))))
    return evaluated
end

_strong_strong_luminosity_evaluated(::AbstractPoissonSolver, ::TrackingContext) = true
_strong_strong_luminosity_evaluated(solver::PICPoissonSolver, ctx::TrackingContext) =
    _pic_compute_luminosity(solver, ctx)

_cuda_nvtx_enabled() = _strong_strong_diagnostics().nvtx

function _cuda_nvtx_push(backend, message::AbstractString)
    backend === CUDABackend || return false
    (_HAS_CUDA && _cuda_nvtx_enabled()) || return false
    NVTX.range_push(message=String(message))
    return true
end

function _cuda_nvtx_pop(backend, active::Bool)
    (backend === CUDABackend && active && _HAS_CUDA) || return nothing
    NVTX.range_pop()
    return nothing
end

function _strong_strong_cuda_memory_log_every(backend)
    backend === CUDABackend || return 0
    return _strong_strong_diagnostics().memory_log_every
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
                                              policy, ctx, streams, block_index::Integer)
    if policy isa ResolvedCUDAExecutionPolicy && streams !== nothing
        _execute_strong_strong_segment!(rep1, entries1, plan_cache1, policy, ctx, block_index, streams[1])
        _execute_strong_strong_segment!(rep2, entries2, plan_cache2, policy, ctx, block_index, streams[2])
        CUDA.synchronize(streams[1])
        CUDA.synchronize(streams[2])
    else
        _execute_strong_strong_segment!(rep1, entries1, plan_cache1, policy, ctx, block_index)
        _execute_strong_strong_segment!(rep2, entries2, plan_cache2, policy, ctx, block_index)
    end
    return nothing
end

function _strong_strong_segment_streams(policy)
    if policy isa ResolvedCUDAExecutionPolicy
        _HAS_CUDA || error("CUDABackend requires CUDA.jl to be available.")
        return (CUDA.CuStream(), CUDA.CuStream())
    end
    return nothing
end

function _execute_strong_strong_segment!(rep, entries::Tuple, plan_cache, policy, ctx,
                                         block_index::Integer, stream=nothing)
    isempty(entries) && return nothing
    # Active-hook state alone is not unique: blocks before and after a collision
    # commonly have the same hook state but contain different physics elements.
    plan_key = (Int(block_index), _active_plan_key(entries, ctx, false))
    plan = get!(plan_cache, plan_key) do
        _build_tracking_plan(entries, plan_key[2])
    end
    _execute_tracking_plan_turn!(rep, plan, policy, ctx; stream=stream)
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
        entry isa LineObserverEntry && push!(observers, entry.observer)
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
