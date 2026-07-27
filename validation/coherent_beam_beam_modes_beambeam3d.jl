#=
Cross-code companion to `coherent_beam_beam_modes.jl`: extract the sigma/pi
coherent-mode tunes and the Yokoya factor Lambda from a BeamBeam3D run of the
SAME symmetric round-beam configuration, using the identical spectral analysis
(Hann window + parabolic peak interpolation on the sum/difference centroid
signals).

BeamBeam3D (Qiang, Furman, Ryne; https://github.com/beam-beam/BeamBeam3D) is
the reference PIC strong-strong code for ring colliders. Its per-turn moment
files hold the centroids: fort.24/fort.25 are beam 1 x/y (columns: turn,
centroid, rms, momentum centroid, momentum rms, correlation, emittances) and
fort.34/fort.35 are beam 2 x/y. The matching input deck lives in the
BeamBeam3D checkout under `coherent_modes/` (10 GeV e+ e-, beta* = 0.55 m,
sigma = 106 um round, xi = 0.005 via npart = 8.9141e9, tunes .31/.32, one
slice, 128x128 transverse grid, 100k macroparticles, 8192 turns, 0.1-sigma
offset on beam 1 only) — the same physics case as the Octopus benchmark.

Run after the BeamBeam3D job has finished:

    julia --project=. validation/coherent_beam_beam_modes_beambeam3d.jl [rundir]

`rundir` defaults to OCTOPUS_BB3D_RUNDIR or
/cfs/ad/dxu/Library/BeamBeam3D/coherent_modes.
=#

using Statistics
import FFTW

rundir = length(ARGS) >= 1 ? ARGS[1] :
    get(ENV, "OCTOPUS_BB3D_RUNDIR", "/cfs/ad/dxu/Library/BeamBeam3D/coherent_modes")
xi = parse(Float64, get(ENV, "OCTOPUS_BB3D_XI", "0.005"))
bare = (x = 0.31, y = 0.32)

# Same estimator as validation/coherent_beam_beam_modes.jl.
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

centroid_column(path) = [parse(Float64, split(line)[2])
                         for line in eachline(path) if !isempty(strip(line))]

println("BeamBeam3D coherent-mode analysis  (rundir = $(rundir), xi = $(xi))")
for (plane, f1, f2, q0) in ((:x, "fort.24", "fort.34", bare.x),
                            (:y, "fort.25", "fort.35", bare.y))
    c1 = centroid_column(joinpath(rundir, f1))
    c2 = centroid_column(joinpath(rundir, f2))
    n = min(length(c1), length(c2))
    # Use the largest power-of-two prefix so the resolution matches the
    # Octopus run's 8192-turn FFT.
    n = 1 << floor(Int, log2(n))
    q_sigma = fractional_tune(c1[1:n] .+ c2[1:n])
    q_pi = fractional_tune(c1[1:n] .- c2[1:n])
    lambda = (q_pi - q_sigma) / xi
    println("  $(plane) ($(n) turns): Q_sigma=$(round(q_sigma; digits=6)) ",
            "(bare $(q0), drift $(round(q_sigma - q0; sigdigits=2)))   ",
            "Q_pi=$(round(q_pi; digits=6))   Lambda=$(round(lambda; digits=3))")
end
println()
println("Compare with the Octopus run (validation/coherent_beam_beam_modes.jl):")
println("  PIC 1.199/1.206 (x/y), GaussianPIC 1.200/1.207, soft-Gaussian 1.096/1.101.")
