#=
Validate the high-energy weak-strong limit of the strong-strong collision.

Run from the project root:

    julia --project=. validation/high_energy_weakstrong_limit.jl

Controls:

    OCTOPUS_HIGH_ENERGY_N=20000
    OCTOPUS_HIGH_ENERGY_NSLICES=5
    OCTOPUS_HIGH_ENERGY_GRID=96
    OCTOPUS_HIGH_ENERGY_ELECTRON_GEV=1e100
    OCTOPUS_HIGH_ENERGY_SIGMA_XY=false
    OCTOPUS_HIGH_ENERGY_PIC_LUM_RTOL=0.08
    OCTOPUS_HIGH_ENERGY_PIC_SIZE_RTOL=0.08

The electron beam energy is made effectively infinite, so its beam-beam kick is
negligible while the proton beam still sees the electron source. The
soft-Gaussian solver is compared against a frozen-source weak-strong reference.
PIC is compared as a grid/model convergence characterization with explicit
tolerances.
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus

const N = parse(Int, get(ENV, "OCTOPUS_HIGH_ENERGY_N", "20000"))
const NSLICES = parse(Int, get(ENV, "OCTOPUS_HIGH_ENERGY_NSLICES", "5"))
const GRID = parse(Int, get(ENV, "OCTOPUS_HIGH_ENERGY_GRID", "96"))
const ELECTRON_GEV = parse(Float64, get(ENV, "OCTOPUS_HIGH_ENERGY_ELECTRON_GEV", "1e100"))
const INCLUDE_SIGMA_XY = lowercase(get(ENV, "OCTOPUS_HIGH_ENERGY_SIGMA_XY", "false")) in
    ("1", "true", "yes", "on")
const PIC_LUM_RTOL = parse(Float64, get(ENV, "OCTOPUS_HIGH_ENERGY_PIC_LUM_RTOL", "0.08"))
const PIC_SIZE_RTOL = parse(Float64, get(ENV, "OCTOPUS_HIGH_ENERGY_PIC_SIZE_RTOL", "0.08"))

function high_energy_base_beams(; n=N, electron_gev=ELECTRON_GEV)
    set_global_rng!(seed=0x123456789abcdef, method=:philox)
    electron = Beam(n, CPUThreadsBackend, Float64;
        beta=(0.55, 0.056, 0.7e-2 / 5.5e-4), alpha=(0.0, 0.0, 0.0),
        sigma=(106e-6, 9.5e-6, 0.7e-2), cutoff=5.0, rng_id=11,
        charge=-1.0, mc2=EMASS_EV, E0=electron_gev * 1.0e9,
        r0=RE, npart=1.7203e11)
    proton = Beam(n, CPUThreadsBackend, Float64;
        beta=(0.8, 0.072, 6e-2 / 6.6e-4), alpha=(0.0, 0.0, 0.0),
        sigma=(95e-6, 8.5e-6, 6e-2), cutoff=5.0, rng_id=12,
        charge=1.0, mc2=PMASS_EV, E0=275e9,
        r0=RE * ME0 / PMASS_EV, npart=0.6881e11)
    return electron, proton
end

function clone_cpu_beam(beam)
    rep = Phase6DRep((copy(Array(a)) for a in coordinate_arrays(beam.rep))...)
    return Beam{CPUThreadsBackend,typeof(beam.params),typeof(rep)}(beam.params, rep)
end

_mean(values) = sum(values) / length(values)

function centered_rms(rep)
    arrays = coordinate_arrays(rep)
    return [begin
        center = _mean(a)
        sqrt(_mean(abs2.(a .- center)))
    end for a in arrays]
end

function max_coordinate_abs(rep_a, rep_b)
    return maximum(maximum(abs.(Array(a) .- Array(b)))
                   for (a, b) in zip(coordinate_arrays(rep_a), coordinate_arrays(rep_b)))
end

function weakstrong_limit_reference!(source, probe, solver)
    slices_source = longitudinal_slices(source.rep, solver.slicing1)
    slices_probe = longitudinal_slices(probe.rep, solver.slicing2)
    kbb = Octopus._strong_strong_kbb2(solver, source, probe)
    _, klum_probe = Octopus._strong_strong_luminosity_scales(solver, source, probe)
    luminosity = zero(eltype(probe.rep.x))
    for (_, i, j) in Octopus._slice_collision_order(slices_source, slices_probe)
        moments = Octopus._slice_transverse_moments(
            source.rep, slices_source.indices[i],
            solver.ignore_centroid1, solver.min_sigma,
            Val(solver.include_sigma_xy))
        luminosity += Octopus._slice_slice_gaussian_kick!(
            probe.rep, slices_probe.indices[j],
            moments, slices_source.center[i],
            slices_source.weight[i] * kbb,
            slices_source.weight[i] * klum_probe,
            solver.min_sigma,
            solver.virtual_drift,
            Val(solver.longitudinal_kick),
            Val(true))
    end
    return luminosity
end

function run_high_energy_weakstrong_limit(; n=N, nslices=NSLICES, grid=GRID,
                                          electron_gev=ELECTRON_GEV,
                                          include_sigma_xy=INCLUDE_SIGMA_XY,
                                          pic_luminosity_rtol=PIC_LUM_RTOL,
                                          pic_size_rtol=PIC_SIZE_RTOL)
    base_electron, base_proton = high_energy_base_beams(;
        n=n, electron_gev=electron_gev)
    slicing = LongitudinalSlicing(
        method=:normal_quantile, nslices=nslices, center_position=:centroid)
    gaussian = GaussianPoissonSolver(
        slicing=slicing, virtual_drift=:hirata, include_sigma_xy=include_sigma_xy,
        gaussian_when_luminosity=1, batch_mode=:wavefront)
    pic = PICPoissonSolver(
        slicing=slicing, grid=(grid, grid), deposit_method=:CIC,
        green_type=:integrated, green_cache=:slice_pair,
        longitudinal_kick=true, batch_mode=:wavefront)

    reference_electron = clone_cpu_beam(base_electron)
    reference_proton = clone_cpu_beam(base_proton)
    reference_luminosity = weakstrong_limit_reference!(
        reference_electron, reference_proton, gaussian)

    gaussian_electron = clone_cpu_beam(base_electron)
    gaussian_proton = clone_cpu_beam(base_proton)
    gaussian_luminosity = collide!(gaussian, gaussian_electron, gaussian_proton,
                                   CPUThreadsBackend)

    pic_electron = clone_cpu_beam(base_electron)
    pic_proton = clone_cpu_beam(base_proton)
    pic_luminosity = collide!(pic, pic_electron, pic_proton, CPUThreadsBackend)

    gaussian_proton_error = max_coordinate_abs(gaussian_proton.rep, reference_proton.rep)
    gaussian_electron_error = max_coordinate_abs(gaussian_electron.rep, base_electron.rep)
    pic_size_rel = maximum(abs.(centered_rms(pic_proton.rep) .-
                                centered_rms(reference_proton.rep)) ./
                           max.(centered_rms(reference_proton.rep), eps(Float64)))
    gaussian_size_rel = maximum(abs.(centered_rms(gaussian_proton.rep) .-
                                     centered_rms(reference_proton.rep)) ./
                                max.(centered_rms(reference_proton.rep), eps(Float64)))
    gaussian_lum_rel = abs(gaussian_luminosity - reference_luminosity) /
        max(abs(reference_luminosity), eps(Float64))
    pic_lum_rel = abs(pic_luminosity - reference_luminosity) /
        max(abs(reference_luminosity), eps(Float64))

    return (
        particles=n,
        nslices=nslices,
        pic_grid=(grid, grid),
        electron_energy_GeV=electron_gev,
        include_sigma_xy=include_sigma_xy,
        reference_luminosity=reference_luminosity,
        gaussian_luminosity=gaussian_luminosity,
        pic_luminosity=pic_luminosity,
        gaussian_luminosity_relative_error=gaussian_lum_rel,
        pic_luminosity_relative_error=pic_lum_rel,
        gaussian_proton_max_abs_error=gaussian_proton_error,
        gaussian_electron_max_abs_change=gaussian_electron_error,
        gaussian_proton_size_relative_error=gaussian_size_rel,
        pic_proton_size_relative_error=pic_size_rel,
        gaussian_passed=gaussian_proton_error <= 2.0e-14 &&
                        gaussian_lum_rel <= 2.0e-12,
        pic_passed=pic_lum_rel <= pic_luminosity_rtol && pic_size_rel <= pic_size_rtol,
        pic_luminosity_rtol=pic_luminosity_rtol,
        pic_size_rtol=pic_size_rtol,
    )
end

function print_high_energy_result(result)
    println("High-energy weak-strong limit")
    for key in propertynames(result)
        println("  ", key, " = ", getproperty(result, key))
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    result = run_high_energy_weakstrong_limit()
    print_high_energy_result(result)
    result.gaussian_passed || error("soft-Gaussian weak-strong limit failed")
    result.pic_passed || error("PIC weak-strong limit tolerance failed")
end
