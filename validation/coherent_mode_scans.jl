#=
Measured Yokoya factor scans with the real 2D strong-strong PIC solver:
Y versus beam flatness and Y versus beam-beam parameter, the simulation
counterparts of the theory curves from coherent_mode_vlasov_theory.jl.
Both use the symmetric single-IP coherent-mode setup of
validation/coherent_beam_beam_modes.jl (equal e+ e- beams, rigid linear
lattice, one slice, 0.1-sigma dipole kick on beam 1, sum/difference centroid
FFTs). The x-plane Yokoya factor is reported; xi_x is computed from
xi_x = N r0 beta_x / (2 pi gamma sigma_x (sigma_x + sigma_y)).

Outputs: result/yokoya_vs_aspect_measured.tsv (r = sigma_y/sigma_x scan),
         result/yokoya_vs_xi_measured.tsv     (round-beam xi scan).

Run:  julia --threads=8 --project=. validation/coherent_mode_scans.jl
(~10-15 min at defaults; OCTOPUS_CMS_TURNS / OCTOPUS_CMS_N_MACRO override)
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus
using Statistics
import FFTW

const TURNS = parse(Int, get(ENV, "OCTOPUS_CMS_TURNS", "2048"))
const N_MACRO = parse(Int, get(ENV, "OCTOPUS_CMS_N_MACRO", "20000"))
const RESULT_DIR = joinpath(@__DIR__, "..", "result")

function fractional_tune(signal)
    n = length(signal)
    w = [0.5 - 0.5 * cospi(2 * (i - 1) / n) for i in 1:n]
    a = abs.(FFTW.rfft((signal .- mean(signal)) .* w))
    k = argmax(a[2:(end - 1)]) + 1
    y1, y2, y3 = a[k - 1], a[k], a[k + 1]
    d = y1 - 2y2 + y3
    return (k - 1 + (d == 0 ? 0.0 : 0.5 * (y1 - y3) / d)) / n
end

"""One symmetric coherent-mode run; returns the x-plane Yokoya factor."""
function measure_Y(; aspect=1.0, xi_x=0.005, turns=TURNS, n_macro=N_MACRO)
    set_global_rng!(seed=20260727, method=:philox)
    policy = CPUThreadsExecutionPolicy()
    energy = 10.0e9
    gamma_rel = energy / EMASS_EV
    r0 = RE * ME0 / EMASS_EV
    sigx = 106.0e-6
    sigy = aspect * sigx
    beta = (0.55, 0.55, 0.7e-2 / 5.5e-4)
    sigma = (sigx, sigy, 0.7e-2)
    npart = xi_x * 2pi * gamma_rel * sigx * (sigx + sigy) / (r0 * beta[1])

    offset1 = (0.1 * sigx, 0.0, 0.1 * sigy, 0.0, 0.0, 0.0)
    beam1 = Beam(n_macro, policy, Float64;
        beta=beta, alpha=(0.0, 0.0, 0.0), sigma=sigma, cutoff=5.0, rng_id=1,
        charge=-1.0, mc2=EMASS_EV, E0=energy, r0=r0, npart=npart,
        initial_offset=offset1)
    beam2 = Beam(n_macro, policy, Float64;
        beta=beta, alpha=(0.0, 0.0, 0.0), sigma=sigma, cutoff=5.0, rng_id=2,
        charge=+1.0, mc2=EMASS_EV, E0=energy, r0=r0, npart=npart)

    slicing = LongitudinalSlicing(; method=:normal_quantile, nslices=1,
                                  center_position=:centroid)
    solver = PICPoissonSolver(; slicing=slicing, grid=(128, 128),
        deposit_method=:CIC, green_type=:integrated, green_cache=:slice_pair,
        longitudinal_kick=false)
    ip = StrongStrongCollision(:ip; poisson_solver=solver)
    one_turn = Linear6DSpec{Float64}(;
        beta1=beta, beta2=beta, alpha1=(0.0, 0.0, 0.0), alpha2=(0.0, 0.0, 0.0),
        dmu=2pi .* (0.31, 0.32, -0.01))
    task = StrongStrongTask((ip, one_turn), (ip, one_turn); policy=policy)

    c1 = Vector{Float64}(undef, turns); c2 = similar(c1)
    for t in 1:turns
        execute!(task, beam1, beam2; turns=1)
        c1[t] = mean(beam1.rep.x); c2[t] = mean(beam2.rep.x)
    end
    q_sigma = fractional_tune(c1 .+ c2)
    q_pi = fractional_tune(c1 .- c2)
    return (Y=(q_pi - q_sigma) / xi_x, q_sigma=q_sigma)
end

if get(ENV, "OCTOPUS_CMS_LIB_ONLY", "0") == "1"
    # Definitions only.
else

mkpath(RESULT_DIR)
println("Measured 2D PIC Yokoya factor (turns=$(TURNS), n_macro=$(N_MACRO)/beam)")
println()
println("flatness scan (xi_x = 0.005):")
open(joinpath(RESULT_DIR, "yokoya_vs_aspect_measured.tsv"), "w") do io
    println(io, "aspect_ratio\tY_measured\tq_sigma")
    for r in (0.05, 0.09, 0.2, 0.5, 1.0)
        t = @elapsed out = measure_Y(; aspect=r)
        println(io, r, '\t', out.Y, '\t', out.q_sigma)
        println("  r = ", rpad(r, 5), "  Y = ", round(out.Y; digits=3),
                "   (Q_sigma = ", round(out.q_sigma; digits=5), ", ",
                round(t; digits=0), " s)")
    end
end
println()
println("xi scan (round beams):")
open(joinpath(RESULT_DIR, "yokoya_vs_xi_measured.tsv"), "w") do io
    println(io, "xi\tY_measured\tq_sigma")
    for xi in (0.0025, 0.005, 0.01, 0.02)
        t = @elapsed out = measure_Y(; xi_x=xi)
        println(io, xi, '\t', out.Y, '\t', out.q_sigma)
        println("  xi = ", rpad(xi, 7), "  Y = ", round(out.Y; digits=3),
                "   (", round(t; digits=0), " s)")
    end
end
println()
println("TSVs written to result/.")

end # OCTOPUS_CMS_LIB_ONLY guard
