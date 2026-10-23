#=
Calibration of the coherent-mode tune estimator -- the package's own
`Octopus._coherent_fractional_tune` (Hann window plus parabolic interpolation
of the FFT peak, the estimator `CoherentModePhysicsContract` judges with and
the coherent-mode validation scripts call) -- on synthetic two-tone signals
mimicking sigma/pi dipole spectra, where the true tunes are known by
construction. Until 2026-10-22 this file certified a private copy of the
estimator, one of six hand copies across `validation/` (2026-10-18
comprehensive audit, F-243/U54-7); the two package-free scripts that keep a
copy (the BeamBeam3D post-processor and the standalone Vlasov theory script)
are held to the package's function by the suite.

Signal: n = 8192 turns of cos(2 pi Q1 t + p1) + r cos(2 pi Q2 t + p2) + 0.05
randn, Q1 uniform in [0.30, 0.34), the separation Q2 - Q1 uniform in
[0.004, 0.008) (about xi to 1.6 xi of the coherent-mode benchmark), the
secondary amplitude r uniform in [0.1, 1.0), random phases;
`MersenneTwister(20260728)`, the draws in the order of the 2026-07-28 run.

Error metric and verdicts: the median and the 95th percentile of
|Q_hat - Q_1| over the trials, PASS when median <= 1e-5 and p95 <= 2e-5.
These are REGRESSION bounds on the estimator's resolution with about a factor
two of margin over the measured values (median 4.8e-6, p95 6.5e-6 over 500
trials, 2026-10-18 audit U54 and the 2026-10-22 record; a bin is 1/8192 =
1.2e-4, so the interpolation resolves a twentieth of a bin), not derived error
bars. The maximum is INFO: as r approaches 1 the estimator may lock onto the
secondary tone, so the maximum is the tone separation itself (0.0078
measured), a wrong-peak event rather than resolution; the number of such
trials (error above 1e-3) is printed beside it. Writes no files; prints one
machine-readable line

    TUNE-CAL n_trials=.. median=.. p95=.. max=.. wrong_peak=.. verdict=PASS|FAIL

and exits 1 on FAIL. Paper-cited.

Environment: OCTOPUS_TUNE_CAL_TRIALS (default 500) sets the trial count.

Run from the project root:

    julia --startup-file=no --project=. validation/tune_estimator_calibration.jl
=#
if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus
using Statistics, Random, Printf

const N_TRIALS = parse(Int, get(ENV, "OCTOPUS_TUNE_CAL_TRIALS", "500"))
const MEDIAN_BOUND = 1.0e-5
const P95_BOUND = 2.0e-5
const WRONG_PEAK = 1.0e-3      # above this the other tone was taken for the primary

ftune(sig) = Octopus._coherent_fractional_tune(sig)
rng = MersenneTwister(20260728)
n = 8192
errs = Float64[]
for trial in 1:N_TRIALS
    Q1 = 0.30 + 0.04*rand(rng)
    Q2 = Q1 + 0.004 + 0.004*rand(rng)      # separation 0.004-0.008 (~xi..1.6xi)
    r  = 0.1 + 0.9*rand(rng)               # secondary/primary amplitude
    p1, p2 = 2pi*rand(rng), 2pi*rand(rng)
    noise = 0.05
    s = [cos(2pi*Q1*t + p1) + r*cos(2pi*Q2*t + p2) + noise*randn(rng) for t in 1:n]
    push!(errs, abs(ftune(s) - Q1))
end
med, p95, mx = median(errs), quantile(errs, 0.95), maximum(errs)
wrong = count(>(WRONG_PEAK), errs)
println("n_trials=", N_TRIALS, "  median=", round(med; sigdigits=2),
        "  p95=", round(p95; sigdigits=2),
        "  max=", round(mx; sigdigits=2))
println("  median <= ", MEDIAN_BOUND, ": ", med <= MEDIAN_BOUND ? "PASS" : "FAIL",
        ";  p95 <= ", P95_BOUND, ": ", p95 <= P95_BOUND ? "PASS" : "FAIL",
        ";  INFO max ", @sprintf("%.2e", mx), " with ", wrong, " wrong-peak trial(s) (error > ", WRONG_PEAK,
        ": the secondary tone taken for the primary as r -> 1)")
verdict = med <= MEDIAN_BOUND && p95 <= P95_BOUND
@printf("TUNE-CAL n_trials=%d median=%.3e p95=%.3e max=%.3e wrong_peak=%d verdict=%s\n",
        N_TRIALS, med, p95, mx, wrong, verdict ? "PASS" : "FAIL")
verdict || exit(1)
