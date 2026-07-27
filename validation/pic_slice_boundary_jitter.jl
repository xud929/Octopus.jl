#=
Per-turn re-slicing jitter of the longitudinal slice boundaries.

Reference model: the strong-strong PIC collision rebuilds slice boundaries every
turn from the instantaneous z distribution (docs/todo.md, "Slice longitudinal
interpolation" item 5). Under `:equal_area` the internal boundaries are sample
quantiles and the outermost boundaries are pinned to single extreme
macroparticles, so a deterministic interpolation error becomes a fluctuating
one. The frozen-slicing z-scan cannot see this by construction; this script
measures it directly.

Method: track the strong-strong example beams (10 GeV e- vs 275 GeV p, EIC-like
parameters from examples/strong_strong_tracking.jl) through a PIC collision plus
one-turn linear maps (synchrotron rotation included; crab/boost omitted — the
jitter mechanism is re-sampling of the churning z distribution, which those
elements do not change qualitatively). Each turn, longitudinal slices are
computed for BOTH beams under BOTH slicing methods (`:equal_area` and
`:normal_quantile`) from the same coordinates, and every boundary and center is
recorded.

Error metric: per boundary/center, the standard deviation over turns divided by
the beam's z rms ("/sigma_z"), reported separately for the internal boundaries
(mean and max over boundaries), the two outermost boundaries (z extrema, shared
by both methods), and the slice centers.

Inputs (environment overrides): OCTOPUS_JITTER_NPART (default 100_000),
OCTOPUS_JITTER_TURNS (64), OCTOPUS_JITTER_NSLICES (15), OCTOPUS_JITTER_GRID (64),
OCTOPUS_JITTER_SEED (123456789).

Output: result/pic_slice_boundary_jitter.tsv (one row per beam x method) plus a
printed summary table.

Run from the project root:

    julia --threads=8 --project=. validation/pic_slice_boundary_jitter.jl
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus
using Statistics

_env(name, default) = haskey(ENV, name) ? parse(Int, ENV[name]) : default

npart = _env("OCTOPUS_JITTER_NPART", 100_000)
turns = _env("OCTOPUS_JITTER_TURNS", 64)
nslices = _env("OCTOPUS_JITTER_NSLICES", 15)
grid_n = _env("OCTOPUS_JITTER_GRID", 64)
seed = _env("OCTOPUS_JITTER_SEED", 123456789)

set_global_rng!(seed=seed, method=:philox)
policy = CPUThreadsExecutionPolicy()

ele_beta = (0.55, 0.056, 0.7e-2 / 5.5e-4)
pro_beta = (0.8, 0.072, 6.0e-2 / 6.6e-4)
beam_ele = Beam(npart, policy, Float64; beta=ele_beta, alpha=(0.0, 0.0, 0.0),
    sigma=(106.0e-6, 9.5e-6, 0.7e-2), cutoff=5.0, rng_id=1,
    charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7203e11)
beam_pro = Beam(npart, policy, Float64; beta=pro_beta, alpha=(0.0, 0.0, 0.0),
    sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0, rng_id=2,
    charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.6881e11)

slicing_production = LongitudinalSlicing(method=:normal_quantile, nslices=nslices,
                                         center_position=:centroid)
slicing_equal_area = LongitudinalSlicing(method=:equal_area, nslices=nslices,
                                         center_position=:centroid)
solver = PICPoissonSolver(; slicing=slicing_production, grid=(grid_n, grid_n))

one_turn_e = Linear6DSpec{Float64}(; beta1=ele_beta, beta2=ele_beta,
    alpha1=(0.0, 0.0, 0.0), alpha2=(0.0, 0.0, 0.0), dmu=2pi .* (0.08, 0.14, -0.069))
one_turn_p = Linear6DSpec{Float64}(; beta1=pro_beta, beta2=pro_beta,
    alpha1=(0.0, 0.0, 0.0), alpha2=(0.0, 0.0, 0.0), dmu=2pi .* (0.228, 0.210, -0.01))
ip = StrongStrongCollision(:ip; poisson_solver=solver)
task = StrongStrongTask((ip, one_turn_e), (ip, one_turn_p))

# boundaries[turn] :: Vector, centers[turn] :: Vector, per (beam, method)
records = Dict((beam, method) => (boundaries=Vector{Vector{Float64}}(),
                                  centers=Vector{Vector{Float64}}())
               for beam in (:electron, :proton),
                   method in (:equal_area, :normal_quantile))

for turn in 1:turns
    execute!(task, beam_ele, beam_pro; turns=1)
    for (beam_name, beam) in ((:electron, beam_ele), (:proton, beam_pro))
        for (method_name, slicing) in ((:equal_area, slicing_equal_area),
                                       (:normal_quantile, slicing_production))
            slices = longitudinal_slices(beam.rep, slicing)
            rec = records[(beam_name, method_name)]
            push!(rec.boundaries, copy(slices.boundary))
            push!(rec.centers, copy(slices.center))
        end
    end
end

result_dir = joinpath(@__DIR__, "..", "result")
mkpath(result_dir)
out_path = joinpath(result_dir, "pic_slice_boundary_jitter.tsv")

open(out_path, "w") do io
    println(io, join(("beam", "method", "npart", "turns", "nslices", "sigma_z",
                      "internal_mean", "internal_max", "outer_lo", "outer_hi",
                      "center_mean", "center_max"), '\t'))
    println("slice-boundary jitter, std over $(turns) turns / sigma_z " *
            "($(npart) macroparticles, $(nslices) slices):")
    println(rpad("beam/method", 28), rpad("internal mean", 15), rpad("internal max", 15),
            rpad("outer lo", 12), rpad("outer hi", 12), rpad("center mean", 13), "center max")
    for beam in (:electron, :proton), method in (:equal_area, :normal_quantile)
        rec = records[(beam, method)]
        B = reduce(hcat, rec.boundaries)   # (nslices+1) x turns
        C = reduce(hcat, rec.centers)      # nslices x turns
        sigz = beam === :electron ? 0.7e-2 : 6.0e-2
        bstd = [std(B[k, :]) for k in 1:size(B, 1)] ./ sigz
        cstd = [std(C[k, :]) for k in 1:size(C, 1)] ./ sigz
        internal = bstd[2:(end - 1)]
        row = (string(beam), string(method), npart, turns, nslices, sigz,
               mean(internal), maximum(internal), bstd[1], bstd[end],
               mean(cstd), maximum(cstd))
        println(io, join(row, '\t'))
        println(rpad("$(beam)/$(method)", 28),
                rpad(round(mean(internal); sigdigits=3), 15),
                rpad(round(maximum(internal); sigdigits=3), 15),
                rpad(round(bstd[1]; sigdigits=3), 12),
                rpad(round(bstd[end]; sigdigits=3), 12),
                rpad(round(mean(cstd); sigdigits=3), 13),
                round(maximum(cstd); sigdigits=3))
    end
end
println("wrote ", out_path)
