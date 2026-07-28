#=
EIC-like asymmetric coherent modes: strong-strong simulation versus the
coupled Vlasov mode analysis of validation/coherent_mode_vlasov_theory.jl
(theory note: docs/theory/coherent_beam_beam_modes.md, section 4).

The theory predicts, for the head-on equivalent of the strong-strong example
constants (xi_e = 0.088/0.100 in x/y, xi_p = 0.0094):

- NO coherent dipole mode detaches from the incoherent continua in either
  plane (x: bands well separated by the 0.148 tune split; y: the electron
  continuum [0.14, 0.24] swallows the proton tune, top mode exactly at the
  electron continuum edge);
- therefore both beams' centroid responses should be Landau-damped: broad
  spectral structure confined to the predicted continua, with no persistent
  narrow lines outside them.

This script runs that head-on equivalent with the real 2D PIC solver (single
slice, rigid linear lattice, no crossing angle / crabs / chromaticity /
radiation — matching the theory model's assumptions), kicks both beams by
0.1 sigma in x and y, records both beams' turn-by-turn centroids, and writes
Hann-windowed amplitude spectra plus the theory band edges for the overlay
figure (result/eic_mode_comparison.png, drawn by plot_coherent_mode_theory.py).

The decoherence signature is also quantified directly: the centroid envelope
decay time of each beam (turns to fall to 1/e of the initial offset),
compared between planes.

Run:  julia --threads=8 --project=. validation/coherent_mode_eic_comparison.jl
(~4-8 min at defaults; OCTOPUS_EIC_CMP_TURNS / OCTOPUS_EIC_CMP_N_MACRO override)

Outputs: result/eic_mode_spectra.tsv, result/eic_mode_envelopes.tsv.
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus
using Statistics
import FFTW

const TURNS = parse(Int, get(ENV, "OCTOPUS_EIC_CMP_TURNS", "4096"))
const N_MACRO = parse(Int, get(ENV, "OCTOPUS_EIC_CMP_N_MACRO", "20000"))
const RESULT_DIR = joinpath(@__DIR__, "..", "result")

# Strong-strong example constants (head-on equivalent).
ele = (E=10.0e9, mass=EMASS_EV, charge=-1.0, N=1.7203e11,
       sigma=(106.0e-6, 9.5e-6, 0.7e-2), beta=(0.55, 0.056, 0.7e-2 / 5.5e-4),
       tune=(0.08, 0.14, -0.069))
pro = (E=275.0e9, mass=PMASS_EV, charge=1.0, N=0.6881e11,
       sigma=(95.0e-6, 8.5e-6, 6.0e-2), beta=(0.8, 0.072, 6.0e-2 / 6.6e-4),
       tune=(0.228, 0.210, -0.01))

xi_of(src, wit, r0_wit, gamma_wit, i) =
    src.N * r0_wit * wit.beta[i] /
    (2pi * gamma_wit * src.sigma[i] * (src.sigma[i] + src.sigma[3 - i == 2 ? 2 : 1]))
# (index helper: for i=1 the pairing sigma_x*(sigma_x+sigma_y); for i=2
#  sigma_y*(sigma_x+sigma_y))
xi_pair(src, wit, r0_wit, gamma_wit) = (
    src.N * r0_wit * wit.beta[1] /
        (2pi * gamma_wit * src.sigma[1] * (src.sigma[1] + src.sigma[2])),
    src.N * r0_wit * wit.beta[2] /
        (2pi * gamma_wit * src.sigma[2] * (src.sigma[1] + src.sigma[2])),
)

gamma_e = ele.E / ele.mass
gamma_p = pro.E / pro.mass
r0_e = RE * ME0 / ele.mass
r0_p = RE * ME0 / pro.mass
xi_e = xi_pair(pro, ele, r0_e, gamma_e)
xi_p = xi_pair(ele, pro, r0_p, gamma_p)

set_global_rng!(seed=20260727, method=:philox)
policy = CPUThreadsExecutionPolicy()
offset(b) = (0.1 * b.sigma[1], 0.0, 0.1 * b.sigma[2], 0.0, 0.0, 0.0)
beam_e = Beam(N_MACRO, policy, Float64;
    beta=ele.beta, alpha=(0.0, 0.0, 0.0), sigma=ele.sigma, cutoff=5.0,
    rng_id=1, charge=ele.charge, mc2=ele.mass, E0=ele.E, r0=r0_e,
    npart=ele.N, initial_offset=offset(ele))
beam_p = Beam(N_MACRO, policy, Float64;
    beta=pro.beta, alpha=(0.0, 0.0, 0.0), sigma=pro.sigma, cutoff=5.0,
    rng_id=2, charge=pro.charge, mc2=pro.mass, E0=pro.E, r0=r0_p,
    npart=pro.N, initial_offset=offset(pro))

slicing = LongitudinalSlicing(; method=:normal_quantile, nslices=1,
                              center_position=:centroid)
solver = PICPoissonSolver(; slicing=slicing, grid=(128, 128),
    deposit_method=:CIC, green_type=:integrated, green_cache=:slice_pair,
    longitudinal_kick=false)
ip = StrongStrongCollision(:ip; poisson_solver=solver)
one_turn(b) = Linear6DSpec{Float64}(;
    beta1=b.beta, beta2=b.beta, alpha1=(0.0, 0.0, 0.0), alpha2=(0.0, 0.0, 0.0),
    dmu=2pi .* b.tune)
task = StrongStrongTask((ip, one_turn(ele)), (ip, one_turn(pro)); policy=policy)

println("EIC-like head-on coherent-mode comparison")
println("  xi_e = ", round.(xi_e; digits=4), "   xi_p = ", round.(xi_p; digits=4))
println("  theory continua x: e ", round.((ele.tune[1], ele.tune[1] + xi_e[1]); digits=4),
        "  p ", round.((pro.tune[1], pro.tune[1] + xi_p[1]); digits=4))
println("  theory continua y: e ", round.((ele.tune[2], ele.tune[2] + xi_e[2]); digits=4),
        "  p ", round.((pro.tune[2], pro.tune[2] + xi_p[2]); digits=4))
println("  turns=$(TURNS)  n_macro=$(N_MACRO)/beam")

cex = Vector{Float64}(undef, TURNS); cey = similar(cex)
cpx = similar(cex); cpy = similar(cex)
elapsed = @elapsed for t in 1:TURNS
    execute!(task, beam_e, beam_p; turns=1)
    cex[t] = mean(beam_e.rep.x); cey[t] = mean(beam_e.rep.y)
    cpx[t] = mean(beam_p.rep.x); cpy[t] = mean(beam_p.rep.y)
end
println("  tracked in ", round(elapsed; digits=0), " s")

hann(n) = [0.5 - 0.5 * cospi(2 * (i - 1) / n) for i in 1:n]
function spectrum(sig)
    n = length(sig)
    a = abs.(FFTW.rfft((sig .- mean(sig)) .* hann(n)))
    freq = (0:(length(a) - 1)) ./ n
    return freq, a
end

"""1/e decoherence time of the centroid envelope (turns), from the running
peak of |centroid| in windows of 32 turns."""
function decoherence_turns(sig, sigma0)
    win = 32
    env = [maximum(abs.(view(sig, i:min(i + win - 1, length(sig)))))
           for i in 1:win:(length(sig) - win)]
    target = 0.1 * sigma0 / exp(1)
    for (i, e) in enumerate(env)
        e < target && return (i - 0.5) * win
    end
    return Inf
end

mkpath(RESULT_DIR)
open(joinpath(RESULT_DIR, "eic_mode_spectra.tsv"), "w") do io
    println(io, "freq\tamp_e_x\tamp_p_x\tamp_e_y\tamp_p_y")
    fx, aex = spectrum(cex); _, apx = spectrum(cpx)
    _, aey = spectrum(cey); _, apy = spectrum(cpy)
    for i in eachindex(fx)
        println(io, fx[i], '\t', aex[i], '\t', apx[i], '\t', aey[i], '\t', apy[i])
    end
end
open(joinpath(RESULT_DIR, "eic_mode_envelopes.tsv"), "w") do io
    println(io, "signal\tdecoherence_turns")
    for (name, sig, s0) in (("e_x", cex, ele.sigma[1]), ("p_x", cpx, pro.sigma[1]),
                            ("e_y", cey, ele.sigma[2]), ("p_y", cpy, pro.sigma[2]))
        tau = decoherence_turns(sig, s0)
        println(io, name, '\t', tau)
        println("  ", name, " centroid decoherence: ",
                tau == Inf ? "persists over the full run" : "~$(round(Int, tau)) turns")
    end
end

# Peak locations for the printed comparison.
for (plane, se, sp, bands) in (
        (:x, cex, cpx, ((ele.tune[1], ele.tune[1] + xi_e[1]),
                        (pro.tune[1], pro.tune[1] + xi_p[1]))),
        (:y, cey, cpy, ((ele.tune[2], ele.tune[2] + xi_e[2]),
                        (pro.tune[2], pro.tune[2] + xi_p[2]))))
    for (name, sig) in ((:e, se), (:p, sp))
        f, a = spectrum(sig)
        k = argmax(a[2:(end - 1)]) + 1
        peak = f[k]
        ine = bands[1][1] - 0.003 <= peak <= bands[1][2] + 0.003
        inp = bands[2][1] - 0.003 <= peak <= bands[2][2] + 0.003
        println("  ", plane, " ", name, "-beam spectral peak at ",
                round(peak; digits=4), "  (in e-band: ", ine,
                ", in p-band: ", inp, ")")
    end
end
println()
println("TSVs written; overlay figure: plot_coherent_mode_theory.py -> result/eic_mode_comparison.png")
