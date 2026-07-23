#=
Compare strong-strong Poisson solver variants on identical deterministic beams.

Reference model: live-beam strong-strong collision with the production-shaped
flat beams used by `examples/strong_strong_tracking.jl`. The solvers are not
expected to agree particle by particle. This script records how they differ in:

- complete collision-turn time and allocation;
- luminosity per collision turn;
- final beam mean, rms, and emittance;
- coordinate RMS/max differences against a selected reference solver.

Run from the project root:

    julia --project=. validation/strong_strong_spectral_comparison.jl

Useful controls:

    OCTOPUS_SPECTRAL_COMPARE_N=20000
    OCTOPUS_SPECTRAL_COMPARE_TURNS=3
    OCTOPUS_SPECTRAL_COMPARE_NSLICES=15
    OCTOPUS_SPECTRAL_COMPARE_GRID=128,1024
    OCTOPUS_SPECTRAL_COMPARE_FREE_GRID=48,48
    OCTOPUS_SPECTRAL_COMPARE_INCLUDE_GRID_FREE=1
    OCTOPUS_SPECTRAL_COMPARE_BACKEND=cpu
    OCTOPUS_SPECTRAL_COMPARE_OUTPUT=result/strong_strong_spectral_comparison
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus
using Printf
using Statistics

const COORD_LABELS = (:x, :px, :y, :py, :z, :pz)

function _parse_grid(text)
    parts = parse.(Int, split(text, ','))
    length(parts) == 2 || error("grid must be nx,ny; got $text")
    return (parts[1], parts[2])
end

const N = parse(Int, get(ENV, "OCTOPUS_SPECTRAL_COMPARE_N", "20000"))
const TURNS = parse(Int, get(ENV, "OCTOPUS_SPECTRAL_COMPARE_TURNS", "3"))
const NSLICES = parse(Int, get(ENV, "OCTOPUS_SPECTRAL_COMPARE_NSLICES", "15"))
const GRID = _parse_grid(get(ENV, "OCTOPUS_SPECTRAL_COMPARE_GRID", "128,1024"))
const FREE_GRID = _parse_grid(get(ENV, "OCTOPUS_SPECTRAL_COMPARE_FREE_GRID", "48,48"))
const INCLUDE_GRID_FREE = get(ENV, "OCTOPUS_SPECTRAL_COMPARE_INCLUDE_GRID_FREE", "1") in
    ("1", "true", "TRUE", "yes", "YES")
const BACKEND_NAME = Symbol(lowercase(get(ENV, "OCTOPUS_SPECTRAL_COMPARE_BACKEND", "cpu")))
const OUTPUT_PREFIX = get(ENV, "OCTOPUS_SPECTRAL_COMPARE_OUTPUT",
    joinpath(@__DIR__, "..", "result", "strong_strong_spectral_comparison"))

function production_pair(n)
    set_global_rng!(seed=123456789, method=:philox)
    ele = Beam(n, CPUThreadsBackend, Float64;
        beta=(0.55, 0.056, 0.7e-2 / 5.5e-4),
        alpha=(0.0, 0.0, 0.0),
        sigma=(106.0e-6, 9.5e-6, 0.7e-2),
        cutoff=5.0, rng_id=1, charge=-1.0, mc2=EMASS_EV, E0=10.0e9,
        r0=RE * ME0 / EMASS_EV, npart=1.7203e11)
    pro = Beam(n, CPUThreadsBackend, Float64;
        beta=(0.8, 0.072, 6.0e-2 / 6.6e-4),
        alpha=(0.0, 0.0, 0.0),
        sigma=(95.0e-6, 8.5e-6, 6.0e-2),
        cutoff=5.0, rng_id=2, charge=1.0, mc2=PMASS_EV, E0=275.0e9,
        r0=RE * ME0 / PMASS_EV, npart=0.6881e11)
    return ele, pro
end

function clone_beam(beam, ::Type{CPUThreadsBackend})
    rep = Phase6DRep((copy(a) for a in coordinate_arrays(beam.rep))...)
    return Beam{CPUThreadsBackend,typeof(beam.params),typeof(rep)}(beam.params, rep)
end

function clone_beam(beam, ::Type{CUDABackend})
    Octopus._HAS_CUDA && Octopus.CUDA.functional(false) ||
        error("OCTOPUS_SPECTRAL_COMPARE_BACKEND=cuda requested, but CUDA is not functional")
    rep = Phase6DRep((Octopus.CUDA.CuArray(copy(a)) for a in coordinate_arrays(beam.rep))...)
    return Beam{CUDABackend,typeof(beam.params),typeof(rep)}(beam.params, rep)
end

function clone_pair(base1, base2, backend)
    return clone_beam(base1, backend), clone_beam(base2, backend)
end

function run_collision_turns!(solver, beam1, beam2, turns, backend)
    luminosities = Vector{Float64}(undef, turns)
    for turn in 1:turns
        luminosities[turn] = Float64(collide!(solver, beam1, beam2, backend))
        backend === CUDABackend && Octopus.CUDA.synchronize()
    end
    return luminosities
end

function timed_run(name, solver, base1, base2, backend; turns=TURNS)
    warm1, warm2 = clone_pair(base1, base2, backend)
    run_collision_turns!(solver, warm1, warm2, 1, backend)

    beam1, beam2 = clone_pair(base1, base2, backend)
    GC.gc()
    luminosities = Float64[]
    elapsed = Ref(0.0)
    bytes = @allocated begin
        t0 = time_ns()
        luminosities = run_collision_turns!(solver, beam1, beam2, turns, backend)
        elapsed[] = (time_ns() - t0) * 1.0e-9
    end
    return (
        name=Symbol(name), solver=solver, beam1=beam1, beam2=beam2,
        luminosities=luminosities, seconds=elapsed[],
        seconds_per_turn=elapsed[] / turns, bytes=bytes,
    )
end

function stats_rows(result, beamname, beam)
    stats = beam_statistics(beam)
    rows = String[]
    for (i, label) in enumerate(stats.labels)
        push!(rows, @sprintf("%s\t%s\t%s\tmean\t%.16e", result.name, beamname, label, stats.mean[i]))
        push!(rows, @sprintf("%s\t%s\t%s\trms\t%.16e", result.name, beamname, label, stats.rms[i]))
    end
    for (i, label) in enumerate((:x, :y, :z))
        push!(rows, @sprintf("%s\t%s\t%s\temittance\t%.16e", result.name, beamname, label, stats.emittance[i]))
    end
    return rows
end

function coordinate_difference_rows(result, reference, beamname, beam, refbeam)
    rows = String[]
    for (label, actual, expected) in zip(COORD_LABELS, coordinate_arrays(beam.rep), coordinate_arrays(refbeam.rep))
        actual_host = Array(actual)
        expected_host = Array(expected)
        delta = actual_host .- expected_host
        rms_delta = sqrt(mean(abs2, delta))
        max_delta = maximum(abs, delta)
        ref_rms = sqrt(mean(abs2, expected_host .- mean(expected_host)))
        rel_rms_delta = rms_delta / max(ref_rms, eps(Float64))
        push!(rows, @sprintf("%s\t%s\t%s\t%s\t%.16e\t%.16e\t%.16e",
            result.name, reference.name, beamname, label, rms_delta, max_delta, rel_rms_delta))
    end
    return rows
end

function field_microbenchmark(solver, base1, base2)
    slices1 = longitudinal_slices(base1.rep, solver.slicing1)
    slices2 = longitudinal_slices(base2.rep, solver.slicing2)
    i = cld(length(slices1.indices), 2)
    j = cld(length(slices2.indices), 2)
    sx = @view base1.rep.x[slices1.indices[i]]
    sy = @view base1.rep.y[slices1.indices[i]]
    fx = @view base2.rep.x[slices2.indices[j]]
    fy = @view base2.rep.y[slices2.indices[j]]
    Lx, Ly = Octopus._spectral_box(solver, base1.rep.x, base1.rep.y, base2.rep.x, base2.rep.y)
    Octopus._spectral_field(solver, sx, sy, fx, fy, Lx, Ly)
    GC.gc()
    elapsed = Ref(0.0)
    bytes = @allocated begin
        t0 = time_ns()
        Octopus._spectral_field(solver, sx, sy, fx, fy, Lx, Ly)
        elapsed[] = (time_ns() - t0) * 1.0e-9
    end
    return (seconds=elapsed[], bytes=bytes, ns=length(sx), nf=length(fx), Lx=Lx, Ly=Ly)
end

function main()
    mkpath(dirname(OUTPUT_PREFIX))
    backend = BACKEND_NAME === :cpu ? CPUThreadsBackend :
              BACKEND_NAME === :cuda ? CUDABackend :
              error("OCTOPUS_SPECTRAL_COMPARE_BACKEND must be cpu or cuda; got $(BACKEND_NAME)")
    base1, base2 = production_pair(N)
    slicing = LongitudinalSlicing(nslices=NSLICES, method=:normal_quantile, center_position=:centroid)
    solvers = Pair{Symbol,Any}[
        :gaussian => GaussianPoissonSolver(slicing=slicing, longitudinal_kick=true,
            virtual_drift=:hirata, include_sigma_xy=false, batch_mode=:wavefront),
        :pic => PICPoissonSolver(slicing=slicing, grid=(128, 128), deposit_method=:CIC,
            green_type=:integrated, green_cache=:slice_pair, longitudinal_kick=true,
            batch_mode=:wavefront),
        :spectral_grid => SpectralPoissonSolver(slicing=slicing, method=:grid,
            grid=GRID, domain_factor=16.0),
    ]
    if INCLUDE_GRID_FREE && backend === CPUThreadsBackend
        push!(solvers, :spectral_grid_free => SpectralPoissonSolver(slicing=slicing,
            method=:grid_free, grid=FREE_GRID, domain_factor=16.0))
    end

    results = Any[]
    for (name, solver) in solvers
        @info "running solver" name turns=TURNS n=N backend=BACKEND_NAME
        push!(results, timed_run(name, solver, base1, base2, backend; turns=TURNS))
    end

    timing_path = OUTPUT_PREFIX * "_timing.tsv"
    open(timing_path, "w") do io
        println(io, "solver\tbackend\tparticles_per_beam\tturns\tslices\tgrid\tseconds\tseconds_per_turn\tallocated_bytes\tfinal_luminosity")
        for r in results
            grid_text = r.solver isa SpectralPoissonSolver ? string(r.solver.grid) :
                        r.solver isa PICPoissonSolver ? string(r.solver.grid) : "-"
            println(io, join((r.name, BACKEND_NAME, N, TURNS, NSLICES, grid_text,
                @sprintf("%.16e", r.seconds),
                @sprintf("%.16e", r.seconds_per_turn), r.bytes,
                @sprintf("%.16e", r.luminosities[end])), '\t'))
        end
    end

    lum_path = OUTPUT_PREFIX * "_luminosity.tsv"
    open(lum_path, "w") do io
        println(io, "turn\t" * join(string.(getfield.(results, :name)), '\t'))
        for turn in 1:TURNS
            println(io, join((turn, (@sprintf("%.16e", r.luminosities[turn]) for r in results)...), '\t'))
        end
    end

    moment_path = OUTPUT_PREFIX * "_moments.tsv"
    open(moment_path, "w") do io
        println(io, "solver\tbeam\tcoordinate\tmetric\tvalue")
        for r in results
            println.(Ref(io), stats_rows(r, "beam1", r.beam1))
            println.(Ref(io), stats_rows(r, "beam2", r.beam2))
        end
    end

    reference = first(r for r in results if r.name === :pic)
    diff_path = OUTPUT_PREFIX * "_coordinate_differences.tsv"
    open(diff_path, "w") do io
        println(io, "solver\treference\tbeam\tcoordinate\trms_delta\tmax_abs_delta\trelative_rms_delta")
        for r in results
            r === reference && continue
            println.(Ref(io), coordinate_difference_rows(r, reference, "beam1", r.beam1, reference.beam1))
            println.(Ref(io), coordinate_difference_rows(r, reference, "beam2", r.beam2, reference.beam2))
        end
    end

    profile_path = OUTPUT_PREFIX * "_field_microprofile.tsv"
    open(profile_path, "w") do io
        println(io, "solver\tgrid\tsource_particles\tfield_particles\tLx\tLy\tseconds\tallocated_bytes")
        for (name, solver) in solvers
            solver isa SpectralPoissonSolver || continue
            backend === CPUThreadsBackend || continue
            p = field_microbenchmark(solver, base1, base2)
            println(io, join((name, solver.grid, p.ns, p.nf,
                @sprintf("%.16e", p.Lx), @sprintf("%.16e", p.Ly),
                @sprintf("%.16e", p.seconds), p.bytes), '\t'))
        end
    end

    println("Strong-strong spectral comparison")
    println("  particles_per_beam = ", N)
    println("  backend = ", BACKEND_NAME)
    println("  turns = ", TURNS)
    println("  slices = ", NSLICES)
    println("  grid = ", GRID)
    println("  free_grid = ", INCLUDE_GRID_FREE ? string(FREE_GRID) : "disabled")
    println("  timing = ", timing_path)
    println("  luminosity = ", lum_path)
    println("  moments = ", moment_path)
    println("  coordinate_differences = ", diff_path)
    println("  field_microprofile = ", profile_path)
    for r in results
        println("  ", r.name, "_seconds_per_turn = ", r.seconds_per_turn)
        println("  ", r.name, "_final_luminosity = ", r.luminosities[end])
    end
end

main()
