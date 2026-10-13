if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus

#=
Turn-modulation spectra (docs/design/turn_modulation.md, section 5.5 and test 9
of section 8): the shipped stochastic rules `WhiteNoise` and `PinkNoise`
(Voss-McCartney) have the spectra the note measured, and the pink rule is
stateless. Both sequences are built through the PUBLIC path a run tracks: a
`ThinCrabCavitySpec{1}` carrying the rule as `phase_noise` is compiled with
`compile_runtime` and realised once per absolute turn with `realize`, exactly
what `update` does inside `execute!`; the realised phase minus the nominal one
is the per-turn offset. Spectra come from the periodogram summed per octave
band and normalised to the top octave, as the note's table.

Run from the project root:

    julia --project=. validation/turn_modulation_spectra.jl

Environment knobs:

    OCTOPUS_SPECTRA_TURNS   turns per sequence, a power of two >= 1024
                            (default 65536, the note's size)
    OCTOPUS_SPECTRA_SEED    the task seed (default 42, the note's)

The rules are `WhiteNoise(1.0; rng_id=7)` and `PinkNoise(1.0; rng_id=7,
octaves=16)` on slot 1 (the phase of harmonic 1), the counter RNG method
Philox; the sequence index is the absolute zero-based turn (the note's demo
used turns 1..N and raw `octopus_normal`, so its numbers differ in the last
digits from this script's).

Verdicts and tolerances (every one must hold for PASS):

    white slope   least-squares slope of log2(band power) per octave over the
                  TRUSTED bands: +1 +- 0.15 (white power doubles per octave)
    pink slope    the same over the trusted bands: 0 +- 0.2 (1/f is flat per
                  octave; the construction's ripple is about a factor 1.3
                  across twelve octaves in the note's table, log2 +- 0.4 band
                  to band, far less in a fitted slope)
    pink rms      sqrt(mean(x^2)) of the pink sequence for sigma = 1 within
                  [0.8, 1.25]: this script's own bound, set after the measured
                  65536-turn value (1.0043) so it passes with margin; the K
                  generators are independent unit normals, so the expectation
                  of rms^2 is exactly 1 at any length, but the slow generators
                  (one holds for 2^15 turns) take few values in one run: the
                  one-sigma scatter of the rms is 7.6 % at 65536 turns and
                  13.8 % at 16384 (Var[rms^2] = (2/(K^2 N)) sum_k 2^k
                  (2K - 1 - 2k), with a heavy upper tail; Monte Carlo over
                  2048 streams: 0.6 % of streams fall outside the band at
                  65536 turns, 5.9 % at 16384, which is why the suite's
                  16384-turn twin states its own quantile bound). The sample
                  standard deviation about the run's MEAN is printed beside it
                  with its expectation
                  E[s^2] = (N/(N-1)) (1 - (1/K) sum_{k=0}^{K-1} min(2^k, N)/N):
                  generator k contributes 2^k/N to Var(mean) while 2^k <= N
                  and exactly 1 once 2^k > N, its single value being removed
                  by the mean entirely (0.9375 at 65536 turns, where every
                  2^k < N; 0.8126 at 16384, std 0.9014, where generators 14
                  and 15 hold for the whole run). The earlier printed form
                  1 - (2^K - 1)/(K N) charged generator 15 with 2 instead of
                  1 (0.7500, std 0.8660 at 16384; Monte Carlo 0.8125 +- 0.0027
                  over 2048 streams; 2026-10-13 neighbour audit, U7-3). It is
                  not the verdict.
    stateless     the pink offset on one turn computed alone, from a fresh
                  compile, equals the sequence's entry for that turn exactly.

The two lowest octave bands (2 and 4 periodogram bins) have too few bins to
trust and are excluded from the slopes, as the note says; they are printed.
The note's own slope definition (the two-endpoint change over ALL bands,
+1.09 white and -0.11 pink at 65536 turns) is printed for comparison and is
not a verdict.

Prints the band table, the slopes, the rms values, the statelessness check and
one machine-readable line

    TM-SPECTRA white_slope=<v> pink_slope=<v> white_rms=<v> pink_rms=<v> stateless=<bool> turns=<N> seed=<s> verdict=PASS|FAIL

and exits with status 1 on any failed verdict. When the git-ignored directory
`result/` exists under the project root, the band table is written there as
`turn_modulation_spectra.tsv`. The suite runs a reduced-size twin of these
verdicts (16384 turns, same rules, seed and tolerances) in the testset
"Turn modulation: white and pink spectra".
=#

using FFTW, Printf

const TURNS = parse(Int, get(ENV, "OCTOPUS_SPECTRA_TURNS", "65536"))
const SEED = parse(UInt64, get(ENV, "OCTOPUS_SPECTRA_SEED", "42"))
const RNG_ID = 7
const OCTAVES = 16
const WHITE_SLOPE_TOL = 0.15
const PINK_SLOPE_TOL = 0.20
const PINK_RMS_BOUNDS = (0.8, 1.25)
const UNTRUSTED_LOW_BANDS = 2

(TURNS >= 1024 && ispow2(TURNS)) || error(
    "OCTOPUS_SPECTRA_TURNS must be a power of two >= 1024 (whole octave bands); got $(TURNS)")

# The sequence a run would track: the realised phase offset of harmonic 1 on
# every absolute turn 0:nturns-1, through compile_runtime and realize.
function compiled_cavity(rule)
    spec = ThinCrabCavitySpec{1}(394.0e6; strengthX=(2.0e-3,), phase=(0.0,), phase_noise=(rule,))
    w = compile_runtime(spec)
    w isa TurnModulated || error("compile_runtime did not wrap the cavity; got a $(typeof(w))")
    return w
end
realised_offset(w::TurnModulated, turn::Integer) =
    Octopus.realize(w.rule, w.base, TrackingContext(turn=turn, seed=SEED, rng_method=:philox))[1].phase[1] -
    w.base.phase[1]
function offset_sequence(rule, nturns::Int)
    w = compiled_cavity(rule)
    return [realised_offset(w, t) for t in 0:nturns-1]
end

# Power per octave band of the periodogram, normalised to the top octave:
# band i (1-based) sums bins 2^i .. 2^(i+1) - 1 of the one-sided spectrum of
# the mean-subtracted sequence (bin j is frequency (j - 1) / N in f_rev units).
# White power doubles per octave; 1/f power is equal per octave.
function octave_power(seq::Vector{Float64})
    mu = sum(seq) / length(seq)
    P = abs2.(rfft(seq .- mu))
    bands = Float64[]
    bins = Int[]
    lo = 2
    while 2lo <= length(P)
        push!(bands, sum(@view P[lo:2lo-1]))
        push!(bins, lo)
        lo *= 2
    end
    return bands ./ bands[end], bins
end

# Least-squares slope of log2(power) against the band index (one unit per
# octave) over the trusted bands; the note's two-endpoint change over all
# bands is kept beside it for comparison.
function fitted_slope(bands::Vector{Float64}, first::Int)
    y = log2.(bands[first:end])
    x = collect(Float64, 0:length(y)-1)
    xm, ym = sum(x) / length(x), sum(y) / length(y)
    return sum((x .- xm) .* (y .- ym)) / sum(abs2, x .- xm)
end
endpoint_slope(bands::Vector{Float64}) =
    (log2(bands[end]) - log2(bands[1])) / (length(bands) - 1)
rms(seq) = sqrt(sum(abs2, seq) / length(seq))
sample_std(seq) = (mu = sum(seq) / length(seq); sqrt(sum(abs2, seq .- mu) / (length(seq) - 1)))
# E[s^2] of the pink sum about its own mean (header): generator k holds N/2^k
# independent values when 2^k <= N, contributing 2^k/N to Var(mean), and ONE
# value when 2^k > N, contributing exactly 1, which the mean removes.
pink_svar(K, N) = (N / (N - 1)) * (1 - sum(min(2.0^k, N) for k in 0:K-1) / (K * N))
# Band i holds bins 2^i .. 2^(i+1) - 1 of the one-sided periodogram, bin j being
# frequency (j - 1)/N (the convention above), so its frequencies run
# (2^i - 1)/N .. (2^(i+1) - 2)/N; the labels 2^i/N .. 2^(i+1)/N printed until
# 2026-10-13 were one bin high (neighbour audit, U7-5; no verdict reads them).
band_f_lo(i) = (2.0^i - 1) / TURNS
band_f_hi(i) = (2.0^(i + 1) - 2) / TURNS

white_rule = WhiteNoise(1.0; rng_id=RNG_ID)
pink_rule = PinkNoise(1.0; rng_id=RNG_ID, octaves=OCTAVES)
seq_white = offset_sequence(white_rule, TURNS)
seq_pink = offset_sequence(pink_rule, TURNS)
pw, bins = octave_power(seq_white)
pp, _ = octave_power(seq_pink)
nb = length(pw)
first_trusted = UNTRUSTED_LOW_BANDS + 1

println("turn-modulation spectra: turns = $(TURNS), seed = $(SEED), rng_id = $(RNG_ID), ",
        "rng_method = philox, pink octaves = $(OCTAVES)")
println("rules through ThinCrabCavitySpec{1}(394.0e6; strengthX=(2.0e-3,), phase=(0.0,), phase_noise=(rule,)), slot 1")
println()
println("octave band (f_rev units)      bins      white       pink    (power, top octave = 1)")
for i in 1:nb
    mark = i < first_trusted ? "   (untrusted: too few bins)" : ""
    @printf("  %.1e .. %.1e     %6d   %8.3f   %8.3f%s\n", band_f_lo(i), band_f_hi(i), bins[i], pw[i], pp[i], mark)
end
white_slope = fitted_slope(pw, first_trusted)
pink_slope = fitted_slope(pp, first_trusted)
println()
@printf("log2 power change per octave, least squares over the %d trusted bands: white %+.3f   pink %+.3f   (expected +1 and 0)\n",
        nb - UNTRUSTED_LOW_BANDS, white_slope, pink_slope)
@printf("the note's definition (two-endpoint, all %d bands):                   white %+.3f   pink %+.3f   (note: +1.09 and -0.11)\n",
        nb, endpoint_slope(pw), endpoint_slope(pp))
white_rms = rms(seq_white)
pink_rms = rms(seq_pink)
@printf("sample rms about zero (sigma = 1):   white %.4f   pink %.4f   (pink bound [%.2f, %.2f])\n",
        white_rms, pink_rms, PINK_RMS_BOUNDS...)
@printf("sample std about the run's mean:     white %.4f   pink %.4f   (pink expectation %.4f: E[s^2] = (N/(N-1)) (1 - (1/K) sum_k min(2^k, N)/N))\n",
        sample_std(seq_white), sample_std(seq_pink), sqrt(pink_svar(OCTAVES, TURNS)))

# Statelessness: the pink value on one turn from a fresh compile, no history.
check_turn = min(40000, TURNS - 1)
pink_alone = realised_offset(compiled_cavity(pink_rule), check_turn)
stateless = pink_alone == seq_pink[check_turn + 1]
println("pink offset on turn $(check_turn) computed alone == sequence entry: ", stateless,
        @sprintf("   (%.6e)", pink_alone))

white_ok = abs(white_slope - 1.0) <= WHITE_SLOPE_TOL
pink_ok = abs(pink_slope) <= PINK_SLOPE_TOL
rms_ok = PINK_RMS_BOUNDS[1] <= pink_rms <= PINK_RMS_BOUNDS[2]
println()
println("verdicts: white slope within +1 +- $(WHITE_SLOPE_TOL): ", white_ok ? "PASS" : "FAIL",
        "; pink slope within 0 +- $(PINK_SLOPE_TOL): ", pink_ok ? "PASS" : "FAIL",
        "; pink rms within [$(PINK_RMS_BOUNDS[1]), $(PINK_RMS_BOUNDS[2])]: ", rms_ok ? "PASS" : "FAIL",
        "; stateless: ", stateless ? "PASS" : "FAIL")
verdict = white_ok && pink_ok && rms_ok && stateless

result_dir = joinpath(@__DIR__, "..", "result")
if isdir(result_dir)
    out = joinpath(result_dir, "turn_modulation_spectra.tsv")
    open(out, "w") do io
        println(io, "band\tf_lo_frev\tf_hi_frev\tbins\twhite_power\tpink_power\ttrusted")
        for i in 1:nb
            println(io, i, '\t', band_f_lo(i), '\t', band_f_hi(i), '\t', bins[i], '\t',
                    pw[i], '\t', pp[i], '\t', i >= first_trusted)
        end
        println(io, "# turns=$(TURNS) seed=$(SEED) rng_id=$(RNG_ID) octaves=$(OCTAVES) ",
                "white_slope=$(white_slope) pink_slope=$(pink_slope) white_rms=$(white_rms) ",
                "pink_rms=$(pink_rms) stateless=$(stateless) verdict=$(verdict ? "PASS" : "FAIL")")
    end
    println("wrote ", normpath(out))
end

@printf("TM-SPECTRA white_slope=%.4f pink_slope=%.4f white_rms=%.4f pink_rms=%.4f stateless=%s turns=%d seed=%d verdict=%s\n",
        white_slope, pink_slope, white_rms, pink_rms, stateless, TURNS, SEED, verdict ? "PASS" : "FAIL")
verdict || exit(1)
