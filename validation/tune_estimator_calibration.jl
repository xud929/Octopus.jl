# Calibration of the Hann-window + parabolic-interpolation tune estimator on
# synthetic two-tone signals mimicking sigma/pi dipole spectra, where the true
# tunes are known by construction.
#
# Error metric: median, p95 and maximum of |Q_hat - Q_1| over 500 trials.
# Writes no files -- the printed calibration table is the output. Paper-cited.
#
# Run from the project root:
#
#     julia --startup-file=no --project=. validation/tune_estimator_calibration.jl
#
# (Metric, run command and the no-output note were all missing until the
# 2026-08-05_b audit, U25-12.)
import FFTW
using Statistics, Random
function ftune(sig)
    n = length(sig); m = sum(sig)/n
    w = [0.5 - 0.5*cospi(2*(i-1)/n) for i in 1:n]
    a = abs.(FFTW.rfft((sig .- m).*w))
    k = argmax(a[2:end-1]) + 1
    y1,y2,y3 = a[k-1],a[k],a[k+1]; d = y1-2y2+y3
    (k - 1 + (d==0 ? 0.0 : 0.5*(y1-y3)/d))/n
end
rng = MersenneTwister(20260728)
n = 8192
errs = Float64[]
for trial in 1:500
    Q1 = 0.30 + 0.04*rand(rng)
    Q2 = Q1 + 0.004 + 0.004*rand(rng)      # separation 0.004-0.008 (~xi..1.6xi)
    r  = 0.1 + 0.9*rand(rng)               # secondary/primary amplitude
    p1, p2 = 2pi*rand(rng), 2pi*rand(rng)
    noise = 0.05
    s = [cos(2pi*Q1*t + p1) + r*cos(2pi*Q2*t + p2) + noise*randn(rng) for t in 1:n]
    push!(errs, abs(ftune(s) - Q1))
end
println("n_trials=500  median=", round(median(errs); sigdigits=2),
        "  p95=", round(quantile(errs, 0.95); sigdigits=2),
        "  max=", round(maximum(errs); sigdigits=2))
