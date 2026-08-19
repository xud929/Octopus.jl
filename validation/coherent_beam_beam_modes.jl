#=
Coherent beam-beam mode benchmark: sigma/pi mode split and the Yokoya factor.

Physics. Two identical rigid-lattice beams colliding at one IP support two
coherent dipole modes: the sigma mode (barycenters in phase) at the unperturbed
tune Q0, and the pi mode (out of phase) shifted by Lambda * xi, where xi is the
incoherent beam-beam parameter. The size of Lambda is a sharp discriminator of
how much self-consistent physics a strong-strong field solver captures:

- A rigid-bunch model gives Lambda = 1 and is known to *underestimate* the
  shift: the coherent force between two displaced Gaussians has half the
  incoherent gradient (effective width sqrt(2) sigma), and the relative offset
  doubles it back. Distribution-shape feedback never enters the dipole mode.
  The adaptive-sigma soft-Gaussian model adds part of that feedback and lands
  slightly above 1 (measured ~1.10 here), still below the Vlasov band.
- The self-consistent Vlasov result (Yokoya & Koiso, Part. Accel. 27 (1990)
  181; Herr & Pieloni, CAS lecture, arXiv:1601.05235) is Lambda = 1.2-1.3,
  the precise value depending on the horizontal/vertical beam-size ratio,
  with round beams at the low end (~1.2, the value used in LHC/RHIC
  round-beam studies). The distribution deforms coherently and carries the pi
  mode outside the incoherent continuum [Q0, Q0 + xi]. Reproducing
  Lambda in this band is the standard acceptance test for PIC-based
  strong-strong codes (BeamBeam3D lineage; White et al., arXiv:1410.5623 use
  the same 0.1-sigma kick + centroid FFT method at RHIC).

So the *expected* outcome here is a split by solver family:
GaussianPoissonSolver clearly below the Vlasov band, PICPoissonSolver and
GaussianPICPoissonSolver inside it at the round-beam value ~1.2.

First-run headline (8192 turns, 100k macroparticles/beam, xi = 0.005):
soft-Gaussian Lambda = 1.096/1.101 (x/y), PIC 1.199/1.206,
GaussianPIC 1.200/1.207; sigma mode at the bare tune to < 4e-6 in all runs.

IMPORTANT SCOPE NOTE: the Vlasov value applies to a SYMMETRIC collision (equal
beams, equal tunes, equal xi). This benchmark therefore uses a purpose-built
symmetric round-beam e+e- configuration (EIC-flavored electron optics,
mirrored), NOT the asymmetric EIC production case. In an asymmetric collider
the coherent modes are eigenvectors of a coupled two-beam system whose
positions depend on the tune split and the xi ratio; there is no single
literature Lambda to gate against, and spectra of the production case should
be reported as a demonstration, not compared to 1.33.

Method. Both beams are launched with a small dipole offset on beam 1 only
(0.1 sigma in x and y). Turn-by-turn barycenters are recorded with
MomentObserver; the sum signal (x1+x2) isolates the sigma line and the
difference signal (x1-x2) the pi line. Tunes are extracted with a
Hann-windowed FFT and parabolic peak interpolation (resolution ~1e-5 at the
default 8192 turns). Lambda = (Q_pi - Q_sigma) / xi per plane, with xi
computed analytically from the beam parameters (round:
xi = N r0 beta / (4 pi gamma sigma^2)).

Single longitudinal slice, no crossing angle, no crabs/boosts, no
chromaticity, no radiation: a clean 4D coherent benchmark. The kick sign is
attractive (e+e-), so modes shift up in tune.

Run (CPU, ~10-20 min at defaults; reduce turns/n_macro for a quick check):

    julia --threads=8 --project=. validation/coherent_beam_beam_modes.jl

Environment overrides: OCTOPUS_CBB_TURNS, OCTOPUS_CBB_N_MACRO,
OCTOPUS_CBB_SOLVERS (comma list from gaussian,pic,gaussian_pic).
Moment files are written under result/ and overwritten on each run.
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus
using Statistics
import FFTW

config = (
    turns = parse(Int, get(ENV, "OCTOPUS_CBB_TURNS", "8192")),
    n_macro = parse(Int, get(ENV, "OCTOPUS_CBB_N_MACRO", "100000")),
    solvers = Symbol.(split(get(ENV, "OCTOPUS_CBB_SOLVERS", "gaussian,pic,gaussian_pic"), ',')),
    xi_target = 0.005,          # per-IP beam-beam parameter (small => linear regime)
    offset_sigma = 0.1,         # initial dipole offset of beam 1, in units of sigma
    tune = (0.31, 0.32, -0.01), # away from low-order resonances; equal for both beams
    energy = 10.0e9,            # e+/e- at 10 GeV
    beta = (0.55, 0.55, 0.7e-2 / 5.5e-4),
    sigma = (106.0e-6, 106.0e-6, 0.7e-2),   # round transverse beam
    cutoff = 5.0,
    pic_grid = (128, 128),
    gpic_grid = (64, 64),
    seed = 20260727,
    result_dir = joinpath(@__DIR__, "..", "result"),
)

# ---------------------------------------------------------------------------
# Analytic beam-beam parameter and the bunch population that realizes it.
# Round beams: xi = N r0 beta / (4 pi gamma sigma^2).
# ---------------------------------------------------------------------------
gamma_rel = config.energy / EMASS_EV
r0 = RE * ME0 / EMASS_EV
npart = config.xi_target * 4pi * gamma_rel * config.sigma[1]^2 / (r0 * config.beta[1])
xi = (npart * r0 * config.beta[1] / (4pi * gamma_rel * config.sigma[1]^2),
      npart * r0 * config.beta[2] / (4pi * gamma_rel * config.sigma[2]^2))

# ---------------------------------------------------------------------------
# Tune extraction: Hann window + parabolic interpolation of the FFT peak.
# ---------------------------------------------------------------------------
function fractional_tune(signal::AbstractVector{<:Real})
    n = length(signal)
    w = [0.5 - 0.5 * cospi(2 * (i - 1) / n) for i in 1:n]
    a = abs.(FFTW.rfft((signal .- mean(signal)) .* w))
    interior = 2:(length(a) - 1)
    k = interior[argmax(view(a, interior))]
    y1, y2, y3 = a[k - 1], a[k], a[k + 1]
    denom = y1 - 2y2 + y3
    delta = denom == 0 ? 0.0 : 0.5 * (y1 - y3) / denom
    return (k - 1 + delta) / n
end

# ---------------------------------------------------------------------------
# One benchmark run for a given solver kind. Fresh beams each run (same seed)
# so the solvers see identical initial conditions.
# ---------------------------------------------------------------------------
function build_solver(kind::Symbol, slicing)
    kind === :gaussian && return GaussianPoissonSolver(;
        slicing = slicing, longitudinal_kick = false)
    kind === :pic && return PICPoissonSolver(;
        slicing = slicing, grid = config.pic_grid, deposit_method = :CIC,
        green_type = :integrated, green_cache = :slice_pair,
        longitudinal_kick = false)
    kind === :gaussian_pic && return GaussianPICPoissonSolver(;
        slicing = slicing, grid = config.gpic_grid, longitudinal_kick = false)
    throw(ArgumentError("unknown solver kind $(kind)"))
end

function run_case(kind::Symbol)
    set_global_rng!(seed = config.seed, method = :philox)
    policy = CPUThreadsExecutionPolicy()

    offset1 = (config.offset_sigma * config.sigma[1], 0.0,
               config.offset_sigma * config.sigma[2], 0.0, 0.0, 0.0)
    beam1 = Beam(config.n_macro, policy, Float64;
        beta = config.beta, alpha = (0.0, 0.0, 0.0), sigma = config.sigma,
        cutoff = config.cutoff, rng_id = 1, charge = -1.0, mc2 = EMASS_EV,
        E0 = config.energy, r0 = r0, npart = npart, initial_offset = offset1)
    beam2 = Beam(config.n_macro, policy, Float64;
        beta = config.beta, alpha = (0.0, 0.0, 0.0), sigma = config.sigma,
        cutoff = config.cutoff, rng_id = 2, charge = +1.0, mc2 = EMASS_EV,
        E0 = config.energy, r0 = r0, npart = npart)

    slicing = LongitudinalSlicing(; method = :normal_quantile, nslices = 1,
                                  center_position = :centroid)
    solver = build_solver(kind, slicing)
    ip = StrongStrongCollision(:ip; poisson_solver = solver)

    one_turn(tune) = Linear6DSpec{Float64}(;
        beta1 = config.beta, beta2 = config.beta,
        alpha1 = (0.0, 0.0, 0.0), alpha2 = (0.0, 0.0, 0.0),
        dmu = 2pi .* tune)

    mkpath(config.result_dir)
    path1 = joinpath(config.result_dir, "coherent_modes_$(kind).beam1.h5")
    path2 = joinpath(config.result_dir, "coherent_modes_$(kind).beam2.h5")
    rm(path1; force = true)
    rm(path2; force = true)
    schedule = EveryNSteps(; start = 0, stop = config.turns, step = 1)
    obs1 = ScheduledObserver(
        MomentObserver(path1; orders = 1:1, capacity = config.turns + 1), schedule)
    obs2 = ScheduledObserver(
        MomentObserver(path2; orders = 1:1, capacity = config.turns + 1), schedule)

    line1 = (ip, one_turn(config.tune), obs1)
    line2 = (ip, one_turn(config.tune), obs2)
    task = StrongStrongTask(line1, line2; policy = policy)
    elapsed = @elapsed execute!(task, beam1, beam2; turns = config.turns)

    m1 = MomentOutput(path1)
    m2 = MomentOutput(path2)
    result = Dict{Symbol,Any}(:elapsed => elapsed)
    for (plane, moment) in ((:x, Moment(; x = 1)), (:y, Moment(; y = 1)))
        c1 = read(m1, moment)
        c2 = read(m2, moment)
        q_sigma = fractional_tune(c1 .+ c2)
        q_pi = fractional_tune(c1 .- c2)
        result[plane] = (q_sigma = q_sigma, q_pi = q_pi)
    end
    return result
end

# ---------------------------------------------------------------------------
# Run all requested solvers and report.
# ---------------------------------------------------------------------------
println("Coherent beam-beam mode benchmark (symmetric round e+e-, single IP)")
println("  turns=$(config.turns)  n_macro=$(config.n_macro)/beam  ",
        "npart=$(round(npart; sigdigits=5))  xi=($(round(xi[1]; sigdigits=4)), ",
        "$(round(xi[2]; sigdigits=4)))")
println("  bare tunes Qx=$(config.tune[1]) Qy=$(config.tune[2]);  ",
        "FFT resolution ~$(round(1.0 / config.turns; sigdigits=2)) ",
        "(interpolated ~1e-5)")
println("  expectation: soft-Gaussian Lambda ~ 1.0-1.1 (moment closure, underestimates);")
println("               PIC / GaussianPIC Lambda in the Vlasov band 1.2-1.3,")
println("               round beams at the low end ~1.2 (Yokoya & Koiso 1990)")
println()

for kind in config.solvers
    r = run_case(kind)
    println("solver = $(kind)   ($(round(r[:elapsed]; sigdigits=3)) s)")
    for (plane, q0, xip) in ((:x, config.tune[1], xi[1]), (:y, config.tune[2], xi[2]))
        p = r[plane]
        lambda = (p.q_pi - p.q_sigma) / xip
        println("  $(plane): Q_sigma=$(round(p.q_sigma; digits=6)) ",
                "(bare $(q0), drift $(round(p.q_sigma - q0; sigdigits=2)))   ",
                "Q_pi=$(round(p.q_pi; digits=6))   ",
                "Lambda=$(round(lambda; digits=3))")
    end
end
println()
println("Notes: Q_sigma should sit at the bare tune (the sigma mode is unshifted");
println("for identical beams). Lambda is (Q_pi - Q_sigma)/xi per plane. The")
println("asymmetric EIC production case has no single theory Lambda; run it as a")
println("demonstration only.")
