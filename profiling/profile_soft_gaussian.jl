#=
Profile the strong-strong soft-Gaussian solver.

Run from the project root:

    julia --project=. profiling/profile_soft_gaussian.jl

Controls:

    OCTOPUS_SOFT_PROFILE_N=200000
    OCTOPUS_SOFT_PROFILE_NSLICES=15
    OCTOPUS_SOFT_PROFILE_REPEATS=5
    OCTOPUS_SOFT_PROFILE_BACKEND=auto
    OCTOPUS_SOFT_PROFILE_FULL_TRACKING=true

The isolated collision timing clones identical beams, warms compilation, and
then measures synchronized `collide!` calls for sequential/wavefront and
uncoupled/coupled covariance modes. The optional full-tracking timing runs
`examples/strong_strong_tracking.jl` through the normal task pipeline with the
Gaussian solver selected.
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus

const N = parse(Int, get(ENV, "OCTOPUS_SOFT_PROFILE_N", "200000"))
const NSLICES = parse(Int, get(ENV, "OCTOPUS_SOFT_PROFILE_NSLICES", "15"))
const REPEATS = parse(Int, get(ENV, "OCTOPUS_SOFT_PROFILE_REPEATS", "5"))
const BACKEND_CHOICE = lowercase(get(ENV, "OCTOPUS_SOFT_PROFILE_BACKEND", "auto"))
const RUN_FULL_TRACKING = lowercase(get(ENV, "OCTOPUS_SOFT_PROFILE_FULL_TRACKING", "true")) in
    ("1", "true", "yes", "on")

function soft_profile_backends()
    if BACKEND_CHOICE == "cpu"
        return (CPUThreadsBackend,)
    elseif BACKEND_CHOICE == "cuda"
        return (CUDABackend,)
    elseif BACKEND_CHOICE == "auto"
        if isdefined(Octopus, :_HAS_CUDA) && Octopus._HAS_CUDA && Octopus.CUDA.functional(false)
            return (CPUThreadsBackend, CUDABackend)
        end
        return (CPUThreadsBackend,)
    end
    error("OCTOPUS_SOFT_PROFILE_BACKEND must be auto, cpu, or cuda")
end

function soft_profile_base_beams()
    contract = StrongStrongGaussianBackendConsistencyContract(
        n_particles=N, turns=1, nslices=NSLICES)
    return Octopus._strong_strong_contract_base_beams(contract)
end

function clone_beam(beam, ::Type{CPUThreadsBackend})
    rep = Octopus._contract_rep_for_backend(beam.rep, CPUThreadsBackend)
    return Beam{CPUThreadsBackend,typeof(beam.params),typeof(rep)}(beam.params, rep)
end

function clone_beam(beam, ::Type{CUDABackend})
    rep = Octopus._contract_rep_for_backend(beam.rep, CUDABackend)
    return Beam{CUDABackend,typeof(beam.params),typeof(rep)}(beam.params, rep)
end

function synchronize_backend(::Type{CPUThreadsBackend}) end
function synchronize_backend(::Type{CUDABackend})
    Octopus.CUDA.synchronize()
end

_mean(values) = sum(values) / length(values)
function _median(values)
    sorted = sort(collect(values))
    n = length(sorted)
    middle = cld(n, 2)
    return isodd(n) ? sorted[middle] : (sorted[middle] + sorted[middle + 1]) / 2
end

function time_isolated_collision(backend, solver, base1, base2)
    warm1 = clone_beam(base1, backend)
    warm2 = clone_beam(base2, backend)
    collide!(solver, warm1, warm2, backend)
    synchronize_backend(backend)

    times = Float64[]
    luminosity = 0.0
    for _ in 1:REPEATS
        beam1 = clone_beam(base1, backend)
        beam2 = clone_beam(base2, backend)
        synchronize_backend(backend)
        elapsed = @elapsed begin
            luminosity = collide!(solver, beam1, beam2, backend)
            synchronize_backend(backend)
        end
        push!(times, elapsed)
    end
    return (times=times, mean=_mean(times), median=_median(times),
            minimum=minimum(times), luminosity=luminosity)
end

function run_soft_gaussian_profile()
    base1, base2 = soft_profile_base_beams()
    slicing = LongitudinalSlicing(
        method=:normal_quantile, nslices=NSLICES, center_position=:centroid)
    rows = Any[]
    for backend in soft_profile_backends()
        for include_sigma_xy in (false, true), batch_mode in (:sequential, :wavefront)
            backend === CPUThreadsBackend && batch_mode === :wavefront && continue
            solver = GaussianPoissonSolver(
                slicing=slicing, include_sigma_xy=include_sigma_xy,
                virtual_drift=:hirata, batch_mode=batch_mode)
            result = time_isolated_collision(backend, solver, base1, base2)
            push!(rows, merge(result, (
                backend=nameof(backend),
                include_sigma_xy=include_sigma_xy,
                batch_mode=batch_mode,
            )))
        end
    end
    return rows
end

function run_full_tracking_profile()
    RUN_FULL_TRACKING || return nothing
    ENV["OCTOPUS_USE_GPU"] = get(ENV, "OCTOPUS_USE_GPU", "0")
    ENV["OCTOPUS_POISSON_SOLVER"] = "gaussian"
    ENV["OCTOPUS_TURNS"] = get(ENV, "OCTOPUS_TURNS", "3")
    ENV["OCTOPUS_N_MACRO"] = get(ENV, "OCTOPUS_N_MACRO", "20000")
    ENV["OCTOPUS_DISABLE_MOMENTS"] = get(ENV, "OCTOPUS_DISABLE_MOMENTS", "1")
    ENV["OCTOPUS_DISABLE_LUMINOSITY_OUTPUT"] = get(ENV, "OCTOPUS_DISABLE_LUMINOSITY_OUTPUT", "1")
    ENV["OCTOPUS_RECORD_TURN_TIMES"] = get(ENV, "OCTOPUS_RECORD_TURN_TIMES", "1")
    println()
    println("Full strong-strong example timing")
    return include(joinpath(@__DIR__, "..", "examples", "strong_strong_tracking.jl"))
end

function print_profile_rows(rows)
    println("Soft-Gaussian isolated collision profile")
    println("  particles_per_beam = ", N)
    println("  slices = ", NSLICES)
    println("  repeats = ", REPEATS)
    for row in rows
        println("  backend = ", row.backend,
                ", include_sigma_xy = ", row.include_sigma_xy,
                ", batch_mode = ", row.batch_mode,
                ", mean_seconds = ", row.mean,
                ", median_seconds = ", row.median,
                ", min_seconds = ", row.minimum,
                ", luminosity = ", row.luminosity,
                ", samples = ", row.times)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    rows = run_soft_gaussian_profile()
    print_profile_rows(rows)
    run_full_tracking_profile()
end
