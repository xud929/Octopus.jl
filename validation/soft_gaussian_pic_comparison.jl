#=
Characterize one identical live-beam collision with the soft-Gaussian and PIC
solvers. The two models are not expected to agree particle by particle: the
soft solver replaces each live slice by its measured Gaussian covariance,
whereas PIC retains sampled non-Gaussian structure on a finite mesh.

Run from the project root:

    julia --project=. validation/soft_gaussian_pic_comparison.jl

Controls:

    OCTOPUS_SOFT_PIC_N=100000
    OCTOPUS_SOFT_PIC_NSLICES=15
    OCTOPUS_SOFT_PIC_GRID=128
    OCTOPUS_SOFT_SIGMA_XY=false
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus
using Statistics

const N = parse(Int, get(ENV, "OCTOPUS_SOFT_PIC_N", "100000"))
const NSLICES = parse(Int, get(ENV, "OCTOPUS_SOFT_PIC_NSLICES", "15"))
const GRID = parse(Int, get(ENV, "OCTOPUS_SOFT_PIC_GRID", "128"))
const INCLUDE_SIGMA_XY = parse(Bool, lowercase(
    get(ENV, "OCTOPUS_SOFT_SIGMA_XY", "false")))

available, reason = Octopus._contract_backends_available(CUDABackend)
available || error("CUDA is required for this comparison: $reason")

contract = StrongStrongGaussianBackendConsistencyContract(
    n_particles=N, turns=1, nslices=NSLICES)
base1, base2 = Octopus._strong_strong_contract_base_beams(contract)

function gpu_clone(beam)
    rep = Octopus._contract_rep_for_backend(beam.rep, CUDABackend)
    return Beam{CUDABackend,typeof(beam.params),typeof(rep)}(beam.params, rep)
end

function run_solver(solver)
    beam1 = gpu_clone(base1)
    beam2 = gpu_clone(base2)
    # Compile outside the reported measurement, using disposable beams.
    warm1 = gpu_clone(base1)
    warm2 = gpu_clone(base2)
    collide!(solver, warm1, warm2, CUDABackend)
    Octopus.CUDA.synchronize()
    elapsed = @elapsed begin
        luminosity = collide!(solver, beam1, beam2, CUDABackend)
        Octopus.CUDA.synchronize()
    end
    return beam1, beam2, luminosity, elapsed
end

slicing = LongitudinalSlicing(
    method=:normal_quantile, nslices=NSLICES, center_position=:centroid)
soft_solver = GaussianPoissonSolver(
    slicing=slicing, include_sigma_xy=INCLUDE_SIGMA_XY,
    virtual_drift=:hirata, batch_mode=:wavefront)
pic_solver = PICPoissonSolver(
    slicing=slicing, grid=(GRID, GRID), deposit_method=:CIC,
    green_type=:integrated, green_cache=:slice_pair,
    batch_mode=:wavefront, longitudinal_kick=true,
    cuda_async=true, cuda_batch_fft=true, cuda_wavefront_fft=true,
    cuda_indexed_wavefront=true)

soft1, soft2, soft_luminosity, soft_seconds = run_solver(soft_solver)
pic1, pic2, pic_luminosity, pic_seconds = run_solver(pic_solver)

function host_statistics(beam)
    arrays = map(Array, coordinate_arrays(beam.rep))
    centers = [mean(a) for a in arrays]
    return (
        mean=centers,
        rms=[sqrt(mean(abs2, a .- center)) for (a, center) in zip(arrays, centers)],
    )
end

function comparison(soft, pic)
    soft_stats = host_statistics(soft)
    pic_stats = host_statistics(pic)
    soft_arrays = map(Array, coordinate_arrays(soft.rep))
    pic_arrays = map(Array, coordinate_arrays(pic.rep))
    coordinate_rms_difference = [
        sqrt(mean(abs2, a .- b)) for (a, b) in zip(soft_arrays, pic_arrays)]
    rms_relative_difference = abs.(soft_stats.rms .- pic_stats.rms) ./
        max.(abs.(pic_stats.rms), eps(Float64))
    return (; soft=soft_stats, pic=pic_stats,
            coordinate_rms_difference, rms_relative_difference)
end

beam1 = comparison(soft1, pic1)
beam2 = comparison(soft2, pic2)
luminosity_relative_difference = abs(soft_luminosity - pic_luminosity) /
    max(abs(pic_luminosity), eps(Float64))

println("Soft-Gaussian versus PIC live-beam comparison")
println("  particles_per_beam = ", N)
println("  slices = ", NSLICES)
println("  pic_grid = ", (GRID, GRID))
println("  include_sigma_xy = ", INCLUDE_SIGMA_XY)
println("  soft_seconds = ", soft_seconds)
println("  pic_seconds = ", pic_seconds)
println("  soft_luminosity = ", soft_luminosity)
println("  pic_luminosity = ", pic_luminosity)
println("  luminosity_relative_difference = ", luminosity_relative_difference)
for (name, result) in (("beam1", beam1), ("beam2", beam2))
    println("  ", name, "_soft_rms = ", result.soft.rms)
    println("  ", name, "_pic_rms = ", result.pic.rms)
    println("  ", name, "_rms_relative_difference = ", result.rms_relative_difference)
    println("  ", name, "_coordinate_rms_difference = ",
            result.coordinate_rms_difference)
end
