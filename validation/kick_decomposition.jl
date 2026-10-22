#=
Kick-error SYSTEMATIC versus FLUCTUATION decomposition of the PIC solver
(referee round 13, R2 M3, of the 2026 Octopus paper).

For a fixed macroparticle count, draw R independent source realizations of a
Gaussian beam and, at each of the 81x81 field points spanning +-4 sigma, split
the kick error against the exact Bassetti-Erskine kick into

    bias        = mean over realizations   (systematic: mesh discretization)
    fluctuation = std  over realizations   (sampling noise reaching the kick)

per mesh (64^2, 128^2, 256^2), per deposition kernel (CIC, TSC) and per aspect
ratio (round, flat 11:1), on identical sources. The paper's noise-floor
dichotomy is about the second quantity and had only ever measured the median
of the total; this measures both. The sampling floor of the BIAS statistic is
measured rather than assumed, by a sign-flip (Rademacher) bootstrap of the
centred residuals (`bias_floor_bootstrap`; the uncentred bootstrap and the
Rayleigh comparator `f sqrt(ln 2 / R)` are recorded beside it).

Reference model: the exact Bassetti-Erskine kick (`gaussian_beambeam_kick`).
Solver: `PICPoissonSolver` on its production path (`_pic_interaction_grids`,
`_pic_solve_field`, `_pic_interpolate_kick`), integrated-log Green kernel, CIC
and TSC. Every metric is the median over field points, normalized by the peak
exact kick. This is a CHARACTERIZATION: every number is printed and written to
the TSV, nothing is gated.

Inputs (environment; every OCTOPUS_KD_* name here is checked against the reads
at load, both directions):

    OCTOPUS_KD_R=100          source realizations per row
    OCTOPUS_KD_NBOOT=200      bootstrap draws of the bias floor
    OCTOPUS_KD_SEED=20260728  the ensemble seed; the default reproduces the
                              archived draw bit for bit

Output: `result/kick_decomposition_R<R>.tsv`, with `_seed<seed>` appended for
a seed other than the default -- the archived file is
`result/kick_decomposition_R100.tsv` (its rows: family, grid, deposit, n_macro,
R, bias, fluctuation, total_median, bias_floor_bootstrap, bias_floor_rayleigh,
bias_floor_bootstrap_uncentered), plus the printed table. The name used to
carry a hard-coded `R100` whatever OCTOPUS_KD_R was, so a reduced run
overwrote the archived name with non-R100 rows (comprehensive audit
2026-10-18, F-227).

Run from the project root (CPU; the archived R = 100, NBOOT = 200 takes about
an hour; R = 4, NBOOT = 10 a few minutes):

    julia --startup-file=no --project=. validation/kick_decomposition.jl

History: this file was derived from validation/noise_floor_meshswap.jl and
until 2026-10-20 carried that script's header (a four-solver table, a
"round-beam correctness gate", a `data/` output) and a 160-line byte-identical
dead copy of its body -- the soft-Gaussian, hybrid and spectral helpers, called
by nothing here; only `pic_kicks` was live (comprehensive audit 2026-10-18,
F-226).
=#

const OCTOPUS_ROOT = normpath(joinpath(@__DIR__, ".."))
mkpath(joinpath(OCTOPUS_ROOT, "result"))

if !isdefined(Main, :Octopus)
    include(joinpath(OCTOPUS_ROOT, "src", "Octopus.jl"))
end
using .Octopus
const O = Octopus
using Random
using Statistics
using Printf

# The header's OCTOPUS_KD_* list against what this file reads, so the two cannot
# drift (the three names were read and undocumented until 2026-10-20,
# comprehensive audit 2026-10-18 F-227; the pattern is
# profiling/benchmark_strong_strong_pic.jl).
let text = read(@__FILE__, String)
    header, body = split(text, "=#"; limit=2)
    named = Set(m.match for m in eachmatch(r"OCTOPUS_KD_[A-Z_]+", header))
    read_names = Set(m.match for m in eachmatch(r"OCTOPUS_KD_[A-Z_]+", body))
    named == read_names || error("header drift: named but never read " *
        string(sort!(collect(setdiff(named, read_names)))) * "; read but not named " *
        string(sort!(collect(setdiff(read_names, named)))))
end

const KD_R = parse(Int, get(ENV, "OCTOPUS_KD_R", "100"))
const KD_NBOOT = parse(Int, get(ENV, "OCTOPUS_KD_NBOOT", "200"))
# Replicate ensembles must not overwrite the archived draw: only the default
# seed writes the unsuffixed file.
const KD_SEED = parse(Int, get(ENV, "OCTOPUS_KD_SEED", "20260728"))
KD_R >= 2 || error("OCTOPUS_KD_R=$(KD_R): the fluctuation is a standard deviation over realizations and needs at least 2")
KD_NBOOT >= 1 || error("OCTOPUS_KD_NBOOT=$(KD_NBOOT) must be at least 1")

# PIC on its production path (grids, deposit, Green FFT, interpolation).
function pic_kicks(sx, sy, xf, yf; grid, method)
    solver = PICPoissonSolver(; grid = (grid, grid), deposit_method = method,
                              green_type = :integrated)
    sgrid, fgrid = O._pic_interaction_grids(solver,
        minimum(sx), maximum(sx), minimum(sy), maximum(sy),
        min(minimum(xf), minimum(sx)), max(maximum(xf), maximum(sx)),
        min(minimum(yf), minimum(sy)), max(maximum(yf), maximum(sy)))
    phi, Ex, Ey = O._pic_solve_field(solver, sx, sy, sgrid, fgrid)
    ns = length(sx)
    kx = Vector{Float64}(undef, length(xf)); ky = similar(kx)
    for k in eachindex(xf)
        ex, ey, _ = O._pic_interpolate_kick(solver, fgrid, xf[k], yf[k],
                                            phi, Ex, Ey, phi, Ex, Ey, 1.0, 0.0)
        kx[k] = 2ex / ns; ky[k] = 2ey / ns
    end
    return kx, ky
end

# ---------------------------------------------------------------------------
# Kick-error SYSTEMATIC vs FLUCTUATION decomposition (referee round 13, R2 M3).
# For a fixed particle count, draw R independent source realizations and, at
# each of the 81x81 field points, split the kick error into
#   bias        = mean over realizations   (systematic, mesh discretization)
#   fluctuation = std  over realizations   (sampling noise reaching the kick)
# The paper's dichotomy is about the SECOND quantity but has only ever
# measured the median of the total. This measures both, per mesh and per
# deposition kernel, on identical sources.
# ---------------------------------------------------------------------------
function decompose(sigx, sigy; grid, method, n, R, seed)
    xg = collect(range(-4sigx, 4sigx; length = 81))
    yg = collect(range(-4sigy, 4sigy; length = 81))
    xf = Float64[]; yf = Float64[]
    for Y in yg, X in xg
        push!(xf, X); push!(yf, Y)
    end
    kex = similar(xf); key = similar(yf)
    for k in eachindex(xf)
        kex[k], key[k] = gaussian_beambeam_kick(sigx, sigy, xf[k], yf[k])
    end
    gnorm = maximum(hypot.(kex, key))
    ex = zeros(length(xf), R); ey = zeros(length(xf), R)
    rng = MersenneTwister(seed)
    for r in 1:R
        sx = sigx .* randn(rng, n); sy = sigy .* randn(rng, n)
        kx, ky = pic_kicks(sx, sy, xf, yf; grid = grid, method = method)
        ex[:, r] .= kx .- kex
        ey[:, r] .= ky .- key
    end
    bias = [hypot(sum(@view ex[k, :]) / R, sum(@view ey[k, :]) / R) for k in eachindex(xf)]
    fluc = [hypot(std(@view ex[k, :]), std(@view ey[k, :])) for k in eachindex(xf)]
    tot  = [median([hypot(ex[k, r], ey[k, r]) for r in 1:R]) for k in eachindex(xf)]
    b, f = median(bias) / gnorm, median(fluc) / gnorm

    # Sampling-noise floor of the BIAS statistic, measured rather than assumed.
    # Analytic forms require assumptions the data need not satisfy (isotropic
    # per-component scatter, a single fluctuation scale).  Instead we measure
    # the null directly with a sign-flip (Rademacher) bootstrap: multiplying
    # each realization's error by a random +-1 leaves the per-point
    # fluctuation structure untouched while destroying any true systematic, so
    # the resulting median |mean| IS the floor, with no distributional
    # assumption.  We report the median over bootstrap draws.
    # The flips must be applied to the CENTERED residuals.  Flipping the raw
    # errors leaves mu*(1/R)sum(s_r), a residual of the true systematic itself
    # of scale |mu|/sqrt(R), which inflates the null wherever the systematic is
    # large -- exactly the rows where the floor matters least, but it biases the
    # comparison.  Centering first removes the systematic exactly, leaving a
    # pure fluctuation null.
    nboot = KD_NBOOT
    brng = MersenneTwister(seed + 991)
    mx = [sum(@view ex[k, :]) / R for k in eachindex(xf)]
    my = [sum(@view ey[k, :]) / R for k in eachindex(xf)]
    nulls = Vector{Float64}(undef, nboot)
    nulls_raw = Vector{Float64}(undef, nboot)
    sgn = Vector{Float64}(undef, R)
    for t in 1:nboot
        for r in 1:R
            sgn[r] = rand(brng, Bool) ? 1.0 : -1.0
        end
        nulls[t] = median([
            hypot(sum((ex[k, r] - mx[k]) * sgn[r] for r in 1:R) / R,
                  sum((ey[k, r] - my[k]) * sgn[r] for r in 1:R) / R)
            for k in eachindex(xf)]) / gnorm
        nulls_raw[t] = median([
            hypot(sum(ex[k, r] * sgn[r] for r in 1:R) / R,
                  sum(ey[k, r] * sgn[r] for r in 1:R) / R)
            for k in eachindex(xf)]) / gnorm
    end
    floor_boot = median(nulls)
    floor_boot_uncentered = median(nulls_raw)
    # Analytic comparators, for the record only.
    floor_rayleigh = f * sqrt(log(2) / R)
    return b, f, median(tot) / gnorm, floor_boot, floor_rayleigh, floor_boot_uncentered
end

# The file name says what the rows hold: the realization count, and the seed
# when it is not the archived one (header).
const OUT2 = joinpath(@__DIR__, "..", "result",
                      "kick_decomposition_R$(KD_R)" *
                      (KD_SEED == 20260728 ? "" : "_seed$(KD_SEED)") * ".tsv")
open(OUT2, "w") do io
    println(io, "# Kick-error systematic/fluctuation split, 81x81 field grid +-4 sigma,")
    println(io, "# median over field points, normalized by peak exact kick.")
    println(io, "# R independent source realizations per row (R = $(KD_R), seed = $(KD_SEED), bootstrap draws = $(KD_NBOOT)).")
    println(io, "family\tgrid\tdeposit\tn_macro\tR\tbias\tfluctuation\ttotal_median\tbias_floor_bootstrap\tbias_floor_rayleigh\tbias_floor_bootstrap_uncentered")
    for (fam, sx, sy) in (("round", 2.0e-3, 2.0e-3), ("flat11", 2.0e-3, 2.0e-3 / 11))
        for grid in (64, 128, 256)
            for method in Octopus._PIC_DEPOSIT_METHODS
                n = 100_000
                # The ensemble seed was hardcoded, so every archived row came
                # from ONE source-realization draw and carried no uncertainty.
                # Referee replication showed that draw is not representative:
                # the flat 64^2->256^2 fluctuation rise reads +15.6% here and
                # +16.9..+19.3% over six fresh ensembles.  Parameterized so the
                # spread across ensembles can be measured and quoted; the
                # default reproduces the archived file bit-for-bit.
                b, f, t, fl, flr, flu = decompose(sx, sy; grid = grid, method = method,
                                                  n = n, R = KD_R, seed = KD_SEED)
                @printf("%-7s %4d^2 %s n=%.0e  bias=%.3e  fluct=%.3e  total=%.3e\n",
                        fam, grid, method, n, b, f, t)
                println(io, fam, "\t", grid, "\t", method, "\t", n, "\t", KD_R,
                        "\t", b, "\t", f, "\t", t, "\t", fl, "\t", flr, "\t", flu)
                flush(io)
            end
        end
    end
end
println("wrote ", OUT2)
