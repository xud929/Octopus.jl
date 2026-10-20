#=
Crab cavity RF noise on a colliding beam: three questions, four parts
(docs/design/turn_modulation.md sections 5.1-5.6; the EIC weak-strong case of
examples/weak_strong_tracking.jl -- 275 GeV protons, a 197 MHz two-harmonic
crab with weights (4/3, -1/3, 0), half crossing angle 12.5 mrad, crab beta
1300 m, beta* 0.8 m, sigma_x* 95 um, tunes 0.228/0.210, a rigid Gaussian
electron strong beam). The production noise point is an RF phase noise of
rms 10 urad and a relative amplitude noise of rms 1e-4 on harmonics 1 and 2
of BOTH proton crab cavities (tccb before the IP, tcca after it).

    (1) does each rule generate the specified noise?           part `noise`
    (2) what is the beam-beam response (emittance, luminosity)? parts `pilot`, `sweep`
    (3) how do the rules compare at equal rms?                  part `report`

Run from the project root; the first argument selects the part, the rest are
`key=value` overrides (every key is documented below; defaults in brackets):

    julia --project=. validation/crab_cavity_noise_response.jl noise     [turns=65536 scale_check=10 table_turns=1048576 long_turns=1048576 rms_streams=4096 out=<dir>]
    julia --project=. validation/crab_cavity_noise_response.jl tablefile [path=<out>/W1_realised_offsets.tsv turns=100000 scale=1 phase_rms=10e-6 strength_rel_rms=0 out=<dir>]
    julia --project=. validation/crab_cavity_noise_response.jl pilot     [turns=6000 n_macro=100000 turns_timing=1000 n_macro_timing=1000000 moment_step=1 gpu=1 threads=4 n0=2000 artifact_dir=<out> out=<dir>]
    julia --project=. validation/crab_cavity_noise_response.jl sweep     tag=<tag> [cases=B0,W1,A1,W2,W3,P1,T2,A4,AP1,AT1,C0,C1,C2,T1 turns=100000 turns_pink=131072 turns_a4=25000 turns_a4s=12500 n_macro=1000000 moment_step=1 gpu=1 threads=4 n0=2000 radiation=0 artifact_dir=<out> table_file=<out>/W1_realised_offsets_T<turns>.tsv out=<dir>]
    julia --project=. validation/crab_cavity_noise_response.jl control   tsv=<sweep tsv> [case=C1 baseline=C0 tol_centroid=0.01 cov_cases=C0,C1,C3,C2 tol_c2=0.10 tol_c2_y=0.05 n0=2000]
    julia --project=. validation/crab_cavity_noise_response.jl report    tsv=<sweep tsv> [ref_y_over_x_phase=<none> ref_phase_white_x=1.72e-7 ref_amp_white_x=1.10e-6 ref_pink_ratio_x=0.15 ref_pink_ratio_y=0.17 tol_rate=1.25 tol_exp=0.1 tol_ratio=0.25 tol_t1=1e-10 tol_epsc_frac=0.8 tol_jc_frac=0.10 tol_baseline=0.05 tol_halves=0.20 tol_resid=0.05 tol_c1_epsc=0.01]

An override key a part does not read is REFUSED by name before the part's
work starts (comprehensive audit 2026-10-18, F-207: `tol_ration=0.01` gave
60/60 PASS where `tol_ratio=0.01` fails, so a misspelt tolerance was judged
at its default); every part reads all of its keys at entry and then asserts
that no key of the command line is left unread, naming the stray key and the
keys it does read. `out` (every part) is the output directory, default `result/crab_noise/`
under the project root (git-ignored; never evidence). Everything a verdict
rests on is printed and written to TSV there. The theory behind parts
`pilot`, `sweep` and `report` is docs/theory/crab_cavity_noise_response.md
(section 7 is the plan this script executes; section 6 the reference
numbers, which enter `report` only as its overridable defaults).

PART `noise` (question 1; CPU, about two and a half minutes after the
Octopus load, the three spectral cases included).
Reference model: the rule contracts of the design note. `WhiteNoise(sigma)` is
a per-turn iid normal of rms `sigma`, flat spectrum. `PinkNoise(sigma;
octaves=16)` is the Voss-McCartney sum of 16 unit-normal generators over
sqrt(16) times sigma, per-turn rms `sigma`, equal power per octave band from
f_rev/2^16 to f_rev/2 with the construction's ripple. `TurnTable(record)` is a
pure consumer: the realised offset on absolute turn t is `record[t+1]`
bitwise, and the record's FNV-1a digest travels in the run artifact. The
sequences are produced the way a run produces them: a
`ThinCrabCavitySpec{3}(197.0e6; strengthX = cc_strength_x, strengthY = (0,0,0),
phase = (0,0,0), phase_noise = (r1, r2, nothing), strength_noise = (s1, s2,
nothing))` with the example's strengths (`cckick = tan(12.5e-3) /
sqrt(0.8 * 1300.0)`, weights (4/3, -1/3, 0)) is compiled with
`compile_runtime` into a `TurnModulated`, and the PURE hook `Octopus.update`
realises it on every absolute turn 0:N-1 (N = `turns`, default 65536 = 2^16,
a power of two for whole octave bands) with a `TrackingContext(turn, seed =
123456789, rng_method = :philox)` -- the example's seed, the context
`execute!` builds. Per rule the specification is sigma_phase = 10e-6 rad on
harmonics 1-2 and sigma_strength = 1e-4 on harmonics 1-2 -- the RELATIVE rms
itself: a strength value d is a dimensionless factor the cavity realises as
strengthX_i (1 + d) and strengthY_i (1 + d), one voltage driver per cavity
(owner decision, relative since 2026-10-15; before, one absolute offset of
rms 1e-4 |strengthX_i| was ADDED to both planes) --
harmonic 3 (weight 0) inactive; two cavities with the example's explicit
stream ids (examples/crab_cavity_noise.jl: tccb `10 + slot`, tcca `20 +
slot`, slot = i for `phase_noise[i]` and 3 + i for `strength_noise[i]`, so
11, 12, 14, 15 and 21, 22, 24, 25). The table rule's record is the example's
synthetic Gaussian white sequence: a master `Random.Xoshiro(20261014)` hands
each active slot, in construction order (tccb phase 1, phase 2, strength 1,
strength 2, then tcca), a `UInt64` seed, and the slot's record is `sigma .*
randn(Xoshiro(seed), table_turns)` with `table_turns` = 1048576 (the
example's default; override `table_turns=`), named
`<cavity>_<slot>_synthetic_white`; the realised turns 0:N-1 are compared with
the first N entries.

Error metrics and tolerances (each printed as PASS/FAIL with its number):
  rms          sample rms about zero over the realised offsets of a slot
               against the specified sigma. White and table: |rms/sigma - 1|
               <= 3 sqrt(1/(2N)) (0.83 % at 65536: the one-sigma of the rms
               of N iid normals is sqrt(1/(2N))). Pink: the finite-run rms
               wanders with the slow generators; the one-sigma from
               Var[rms^2]/sigma^4 = (2/(K^2 N)) sum_{k<K} 2^k (2K - 1 - 2k)
               is 7.65 % at K = 16, N = 65536 (the `PinkNoise` docstring and
               docs/history/turn_modulation_stages3_4_2026_10_13.md, U7-4,
               which corrected the stage 1-2 record's "several percent" to
               this figure; design note section 5.5), and the distribution
               is NOT Gaussian: 8192 synthetic streams of the construction
               (the scratch probe of 2026-10-13) put 0.98 % of streams
               outside a 3-sigma band, all above it (99.9 % quantile 1.324,
               maximum 1.466), and one production slot drew 1.3425 (p =
               0.085 %) whose stream converged to 0.995 by 2^20 turns. So
               the pink rms VERDICT is taken on the slot realised over
               `long_turns` (default 2^20) turns through the same hook,
               against the two-sided 99 % band [q(0.5 %), q(99.5 %)] of the
               construction's rms over `rms_streams` (default 4096)
               synthetic streams of that length (band and stream count
               printed; owner decision 2026-10-14), and the N-turn rms is
               printed as INFO with its Monte Carlo two-sided p-value (the
               2048 reference streams at N), so the record shows the
               finite-run scatter. The construction itself is checked
               sharply by the next two items.
  pink cells   the realised pink sequence equals, bitwise, the rule's
               documented construction rebuilt from the counter RNG: the sum
               over k = 0..K-1 of `octopus_normal(seed, philox, turn >> k,
               rng_id, 0, 1024 + slot + 64 (k + 1))` times sigma over sqrt(K)
               (the key layout above `_RULE_COMPONENT_BASE` in
               src/elements/turn_modulated.jl), accumulated in the rule's
               order.
  pink draws   the M = sum_k max(1, N / 2^k) distinct generator draws the
               run used (131070 at N = 2^16) are unit normals: their mean
               square within 1 +- 3 sqrt(2/M) (1.2 %), a test the slow
               generators' tail cannot move; the values of the three slowest
               generators are printed, since they carry a finite run's rms
               excursion.
  mean         |mean| <= 3 sigma_mean. White and table: sigma_mean =
               sigma/sqrt(N). Pink: generator k holds N/2^k independent
               values, so Var[mean] = sigma^2 (2^K - 1)/(K N) (sigma_mean =
               0.25 sigma at K = 16, N = 2^16), not sigma/sqrt(N).
  spectrum     power per octave band of the periodogram (band i sums bins
               2^i .. 2^(i+1)-1 of the one-sided spectrum of the
               mean-subtracted sequence, normalised to the top octave; the
               two lowest bands, 2 and 4 bins, are printed and not judged),
               as validation/turn_modulation_spectra.jl. White and table:
               least-squares slope of log2(power) per octave +1 +- 0.15;
               pink: 0 +- 0.2, and the band SHAPE against the construction
               itself: 2048 synthetic Voss-McCartney streams (K unit-normal
               generators, generator k holding one randn for 2^k turns, the
               holds aligned to turn 0 as the rule's `turn >> k` keying, over
               sqrt(K)) give the mean and sd of every band's log2 power at
               this N; the slot's standardized band deviations z_i over the
               trusted bands below the top octave (the normaliser, whose
               deviation is zero by construction) must satisfy sum z_i^2 <=
               the 99.9 % quantile of chi^2 with that many degrees of freedom
               (Wilson-Hilferty approximation, 31.3 for 11 bands; the log2
               power of an 8-bin band is only roughly normal, so the quantile
               is approximate).
               The construction's expected band ratios (its ripple) are
               printed. A fixed factor-2 band per octave, tried first, failed
               two of eight slots at 2.03 and 2.05 on bands whose 8 to 16
               bins scatter by 25 to 35 % one-sigma: a statistical bound has
               to carry the band's own scatter.
  independence sample cross-correlation rho between every pair of the eight
               active slot sequences (four per cavity, two cavities) at lag
               0, |rho| <= 3 se. For white and table se = 1/sqrt(N) (the
               brief's 3/sqrt(N) = 0.0117). For pink that se is wrong by an
               order of magnitude: two independent 1/f sequences have
               Var[rho] = (1/N) sum_k rho_x(k) rho_y(k) (Bartlett), so se is
               computed from the two sequences' sample autocorrelations for
               every pair and printed; for white pairs it reproduces
               1/sqrt(N) to a few percent.
  exact        on every turn the element applied the rules' own values
               (`_turn_offset`: sigma times the counter-RNG draw, the pink
               sum, the table entry) BITWISE: phase_i == nominal + d on a
               phase slot and, on a strength slot, strengthX_i == strengthX_i
               (1 + d) with strengthY_i EXACTLY 0.0 (nominal 0: a horizontal
               cavity's amplitude noise kicks nothing vertically -- the
               falsifier of the one-driver decision of 2026-10-15; the
               additive semantics before it put d itself on the Y plane).
               The pink-construction and table items compare the rules' own
               values; the strength sequences the statistics read are the
               factors recovered from the realised X plane,
               (strengthX_realised - strengthX)/strengthX: the subtraction is
               exact (Sterbenz), the (1 + d) rounding, the product's and the
               division's each cost up to one ulp of 1, so the recovered
               factor is within 4 eps(1.0) of d (checked and printed).
  inactive     harmonic 3 (phase and strength) and the base element are
               untouched bitwise on every turn.
  scale        rebuilding every rule with sigma x `scale_check` (the record
               x `scale_check` for the table) multiplies every realised
               sequence by exactly that factor: |rms_scaled/(scale rms) - 1|
               <= 1e-12 (the same normals, scaled).
  table        every slot's realised value equals the record bitwise on every
               turn (the rule's value, applied by the element per the `exact`
               item; a strength slot's recovered factors agree with the
               record to 4 eps(1.0)); a short CPU
               `TrackingTask` run (256 macroparticles, 16 turns, the
               table-carrying cavity alone) writes a run artifact whose
               `turn_modulation_provenance(path)` lists both cavities, each
               slot with kind :table, the rule's digest, name and length, and
               `read(TaskOutput(path), :turn_modulation)` returns the same.
  recorded     per rule, a CPU `TrackingTask` of the two cavities alone (the
               same 256-macroparticle beam) tracks N turns from turn 0 with
               the artifact's `record_turn_modulation = true`
               (docs/design/turn_modulation_record.md), and the `series`
               every active slot reads back through the public reader
               (`turn_modulation_provenance(path)`) equals the hook's replay
               above -- the rules' own values on turns 0:N-1 -- BITWISE, and
               for the table rule the record's first N entries as well: the
               turn loop of `execute!` handed the element the value the pure
               hook produces on every turn and the recorder wrote that value,
               not a re-evaluation (D5 of the record note). Cheap: a few
               seconds per rule.
  spectral     the spectral producer and the consumer together
               (docs/design/spectral_turn_table.md, section 6, check 7).
               Three cases: the :flat preset over the narrow band (3e-3,
               4e-3) cycles per turn and the :pink preset over (2^-14, 1/2),
               both with fixed amplitudes, and :flat over the narrow band
               with Rayleigh amplitudes. Per case the eight slots carry
               `SpectralNoise(sigma, band, preset; rng_id, turns = N,
               amplitudes)` with the example's stream ids (11, 12, 14, 15
               and 21, 22, 24, 25), the rule parallel to WhiteNoise and
               PinkNoise that resolves when the line compiles into a
               TurnTable under the global seed 123456789 (`set_global_rng!`,
               the keying of the white and pink rules), through the same CPU
               `TrackingTask` of the two cavities alone (the
               256-macroparticle beam) over the N turns from turn 0 with
               `record_turn_modulation = true`. The record per slot is the
               library factory's own table under that keying,
               `spectral_turn_table(preset, sigma, band; turns = N, seed =
               123456789, rng_id, slot, amplitudes)` with `slot` the slot
               index the rule sits in (phase harmonic i -> i, strength
               harmonic i -> 3 + i; the resolved table is keyed on it as
               well, so one rng_id per cavity would still give independent
               tables per slot): every slot's recorded series
               equals it BITWISE, and the provenance entry carries kind
               :table, its digest, its canonical name and length N (the
               rule resolved to the factory's table, and the consumer and
               the recorder applied and wrote it). The periodogram is |X_k|^2 of
               the recorded series, X = rfft(series) unnormalised (bins k =
               0..N/2), compared with the design's c^2 S(f_k): S the
               preset's shape, 1 (flat) or 1/f (pink), at f_k = k/N on the
               band bins k with lb <= k/N <= ub (k >= 1 always), and c^2 =
               sigma^2 N^2 / (2 sum_interior S(f_k) + S(1/2) when the
               Nyquist bin is in the band), the analytic normalisation (D5;
               a constant factor in S cancels in |X_k|^2 / c^2, so the
               SHAPE is what is pinned). Fixed amplitudes: |X_k|^2 / c^2
               equals S(f_k) within 1e-10 relative on every band bin, every
               bin outside the band (the DC bin included) is below 1e-12 of
               the band's peak, and the rms equals sigma within 1e-12
               relative. Rayleigh amplitudes, statistics only (the bin
               powers are exponential about c^2 S(f_k), mean 1 and variance
               1 per bin, and sigma is the EXPECTED rms): the band mean of
               |X_k|^2 / (c^2 S(f_k)) within 5/sqrt(K) of 1 (K band bins,
               five one-sigmas of a mean of K exponentials); the rms within
               5/(2 sqrt(K)) relative of sigma (for a flat band rms^2/sigma^2
               is the mean of K exponentials, one-sigma 1/sqrt(K), the
               rms's half of it); the out-of-band bins below 1e-12 of the
               peak as before; and, the anti-vacuity of the statistical
               pins, the sample variance of the K ratios at least 0.1 (fixed
               amplitudes give exactly 0; exponential bin powers give 1 with
               one-sigma about sqrt(8/K)). At N = 65536 the narrow band
               holds K = 66 bins and the pink band 32765, the Nyquist bin
               included; below K = 8 bins (a `turns=` override under 2048)
               the Rayleigh statistics are not evaluable and the item is a
               counted FAIL naming the bin count. Three execute! runs of a
               few seconds each, the periodograms milliseconds.
Outputs: `<out>/noise_summary.tsv` (one row per rule, cavity, slot and
check), `<out>/noise_correlations.tsv` (one row per pair),
`<out>/noise_pink_bands.tsv` (per pink slot and band: measured, reference
mean and sd, z), the artifacts
`<out>/noise_table_provenance.h5`, `<out>/noise_recorded_<rule>.h5` (one
per rule, the recorded series) and
`<out>/noise_recorded_spectral_<preset>_<amplitudes>.h5` (one per spectral
case), and one machine-readable line
`CRAB-NOISE-RULES turns=... checks=... failed=... verdict=PASS|FAIL`; exit 1
on any FAIL.

PART `tablefile`: realises the white rules the harness builds for the given
(phase_rms, strength_rel_rms, scale) on turns 0:turns-1 with the harness's
seed (123456789), stream ids (tccb 10 + slot, tcca 20 + slot) and slots, and
writes them as the table file the harness's OCTOPUS_TABLE_FILE reads: a TSV
with one column per active slot, `<cavity>_phase_noise_<i>` /
`<cavity>_strength_noise_<i>`, one row per turn, each value its shortest
round-trip repr (exact Float64). The phase offset is `sigma * n` exactly
(nominal phase 0); the strength factor is the rule's own value `sigma * n`
(`_turn_offset`), exact -- the realised strength is strengthX (1 + sigma n),
from which the factor is not recoverable bitwise -- and the X plane is
asserted equal to strengthX (1 + d), the Y plane to 0.0, turn by turn.
Prints each column's FNV-1a digest, the value the run artifact records.

PART `pilot` (the calibration; GPU). Runs the developer harness
test/examples/crab_cavity_noise.jl as a subprocess per case,
`julia --startup-file=no --project=<root> --threads=<threads> <harness>`
with the environment OCTOPUS_USE_GPU=<gpu> OCTOPUS_NOISE_RULE=<rule>
OCTOPUS_NOISE_SCALE=<s> OCTOPUS_PHASE_RMS=<10e-6|0>
OCTOPUS_STRENGTH_REL_RMS=<1e-4|0> OCTOPUS_PINK_OCTAVES=16 OCTOPUS_TURNS=<T>
OCTOPUS_N_MACRO=<N> OCTOPUS_KBB_SCALE=<k> OCTOPUS_CHROMATICITY=<xi,xi>
OCTOPUS_RADIATION=0 OCTOPUS_RESULT_DIR=<artifact_dir> OCTOPUS_CASE_NAME=<name>
OCTOPUS_MOMENT_STEP=<m> [OCTOPUS_TABLE_FILE=<tsv>], logs to
`<out>/logs/<name>.log` (the load average at launch on its first line) and
parses the harness's final line
    CRAB-NOISE rule=.. scale=.. [phase_rms=.. strength_rel_rms=.. chrom=..] turns=.. n_macro=..
               kbb_scale=.. radiation=.. seed=.. artifact=<path> eps_x_first=.. eps_x_last=..
               eps_y_first=.. eps_y_last=.. lumi_mean=.. wall_s=.. ms_per_turn=..
               [ranks=.. threads=.. steady_ms_per_turn=..] [record=.. rms_<label>=.. ...
               spectrum=.. band=.. amplitudes=..] [device=<n|NA>]
The bracketed trailing fields arrived with the harness's MPI arm (2026-10-14:
the recorded rank count, the per-process worker count, the post-warm-up
median turn time or NA), the recording (2026-10-15), the spectral rule and
the device readback (2026-10-16); the parser reads the line as key=value
tokens, so fields a check does not name are carried and ignored.
The receipt's READBACKS must match the request (a configuration you set is
not one the code read; the harness header's "READBACKS" paragraph names
which fields are read back from the compiled line, the artifact's ledger and
the execution receipts and which are the request as read): rule, scale,
turns, n_macro, kbb_scale and radiation must match; phase_rms and
strength_rel_rms (the EFFECTIVE sigmas, request x scale, 0 under rule none),
chrom (`xi_x,xi_y`) and table_file (path or `none`) must match when present
and must be present whenever the request departs from the harness default;
device must be present (a harness predating it cannot show which device
ran), an integer index under gpu=1 and NA under gpu=0; a table-fed run must
carry the file's column digests in its `/turn_modulation` provenance. A run
that cannot show this is an error, not a row.
Estimators (plan, section 2) from `read(TaskOutput(path), :moments; name =
"weak_beam")` -- the means `m100000`, `m010000` and the CENTRAL second
moments `m200000`, `m110000`, `m020000` (vertical `m001000`, `m000100`,
`m002000`, `m001100`, `m000200`), one row per recorded turn:
    J_raw = [(m200000 + m100000^2)/beta* + beta* (m020000 + m010000^2)]/2
    eps_c = sqrt(m200000 m020000 - m110000^2)
    J_c   = [m100000^2/beta* + beta* m010000^2]/2
with beta* = 0.8 m (x), 0.072 m (y). Each is fit by ordinary least squares
to a line over turns [n0, T] (n0 = 2000, past the decoherence transient);
the TSV holds the slope, its residual standard error (a LOWER bound for
autocorrelated residuals), the value at n0, the two-half slopes, the
residual rms, the J_c mean (whole window and second half) and maximum, the
centroid rms, and max |J_raw - eps_c - J_c|/eps; rates are slopes over the
design emittances eps_x = 1.128e-8 m, eps_y = 1.004e-9 m. The luminosity
`read(out, :luminosity; name = "strong_beam_1")` gives its mean and
relative trend over the same window.
Pilot cases (radiation off; T = `turns`, N = `n_macro`): white at scale 100
(phase and strength), white at scale 30, none (the baseline drift), white at
scale 100 with kbb_scale = 0, and a timing case (none, `turns_timing` turns
at `n_macro_timing`) that measures ms_per_turn at the sweep's N. Prints the
fitted rates, whether scale 100 is resolved above the baseline and the
one-sample estimator noise sqrt(2/N), the kbb = 0 / full ratio, ms_per_turn
at both N and the sweep's projected wall clock. Outputs `<out>/pilot.tsv`.
Artifacts go to `artifact_dir` (pass a local disk: per-turn observer writes
on a networked filesystem are the dominant cost) and are copied under
`<out>/artifacts/`.

PART `sweep` (the plan's section 4, 14 runs plus the optional C3; every
case radiation off, moment step 1; `cases=` selects and orders them):
    B0  none                       kbb 1 chrom 2,2  T        baseline
    W1 W2 W3  phase white s=1,2,4  kbb 1 chrom 2,2  T        rates, exponent
    P1  phase pink (16 octaves)    kbb 1 chrom 2,2  T_pink   pink/white
    T1  phase table = W1's realised draws (OCTOPUS_TABLE_FILE)   T   bitwise W1
    T2  phase table = seeded synthetic white record             T
    A1 A4  strength white s=1,4    kbb 1 chrom 2,2  T, T_a4  x and y rates (A4: 25k turns, 39 % growth, INFO)
    A4s strength white s=4         kbb 1 chrom 2,2  T_a4s    12500 turns, 21 % growth: INFO, the regime's edge
    A05 A2  strength white s=0.5,2 kbb 1 chrom 2,2  T, T_a4  the small-growth amplitude set (with A1): rates, exponent
    AP1 strength pink              kbb 1 chrom 2,2  T_pink
    AT1 strength table (seeded)    kbb 1 chrom 2,2  T
    C0  none                       kbb 0 chrom 0,0  T        linear baseline
    C1  phase white s=1            kbb 0 chrom 0,0  T        direct term, centroid
    C2  strength white s=1         kbb 0 chrom 0,0  T        direct term in eps_c
    C3  phase white s=1 (optional) kbb 0 chrom 2,2  T        chromatic decoherence
One TSV row per case (every receipt field plus the fits) appended to
`<out>/sweep_<tag>.tsv`; resumable: a case whose row is in the TSV is
skipped, a case whose log already holds a CRAB-NOISE line and whose artifact
exists is re-read (fits recomputed) without re-running, anything else runs.
T1's table file is built by `tablefile` when missing.

PART `report`: the plan's acceptance (section 5) on a sweep TSV, each item
PASS/FAIL with its number and tolerance, rates baseline-subtracted (B0 for
the colliding runs, C0 for the kbb = 0 chrom 0 controls):
 (1) W1, W2, W3, A05, A1, A2, T2, AT1 horizontal J_raw rates within a
     factor tol_rate of the reference (ref_* times s^2); A4s (12500 turns,
     21 % growth) and A4 (25000 turns, 39 %) INFO as the small-growth
     regime's edge; the B0 slope below tol_baseline of the s = 1 prediction;
 (1b) INFO rows "beam-beam-mediated vertical response": the y/x rate ratio
     under phase noise (W1-W3, P1, T1, T2; measured/predicted when
     ref_y_over_x_phase is given) and the vertical rate under amplitude
     noise (A05-A4, AP1, AT1), the beam-beam coupling ALONE since the
     relative strength rule leaves strengthY = 0 (no both-planes term,
     2026-10-15; `ref_amp_white_y` is retired and refused); judged only
     through the kbb = 0 controls: C1 must show no vertical growth beyond C0
     (6) and C2 none either (7), both at 5 % of the predicted x rate;
 (2) exponent of rate against s from W1-W3 and A05, A1, A2 (weighted log-log fit
     over the cases resolved at 2 se) equal to 2 within tol_exp;
 (3) P1/W1 (x), AP1/A1 (x) within tol_ratio of ref_pink_ratio_x; AP1/A1 (y)
     printed against ref_pink_ratio_y as INFO (it carries the vertical
     response);
 (4) T1's moment columns equal W1's within tol_t1 relative (reads both
     artifact copies);
 (5) colliding runs: eps_c slope >= tol_epsc_frac of the J_raw slope; the
     J_c second-half mean below tol_jc_frac of the total growth; the
     vertical rate under phase noise is printed (y/x), the plane mapping
     being judged on C1;
 (6) C1: eps_c slope below tol_c1_epsc of the predicted raw rate; no
     vertical growth (|y rate| <= 5 % of the predicted x rate: without the
     strong beam nothing couples the planes, so growth there would be the
     code's); the centroid against the realisation-aware linear prediction
     is part `control` (below), which `report` points to;
 (7) C2: the diffusion prediction of the eps_c x slope is INFO only (the
     kick sequence is common to every particle and does not decohere
     without tune spread, so one realisation's rate has a 100 % floor); the
     x verdict is part `control`'s covariance propagation; no vertical
     growth beyond C0 (|y eps_c rate| <= 5 % of the predicted x rate) is a
     verdict: under the relative strength rule a horizontal cavity's
     amplitude noise excites nothing vertically without beam-beam, the
     falsifier of the 2026-10-15 decision (the additive semantics grew y at
     0.87 of the x prediction, measured 1.99e-7 per turn on 2026-10-14); the
     centroid action below 10/N of eps (sampling) stays a verdict;
 (8) fit quality: the two-half slopes within tol_halves of the rate and the
     residual rms below tol_resid of the growth for the white drives; A4s
     and A4 (21 % and 39 % growth) are INFO; (8b) derives the single-realisation scatter
     of a band-power rate from 2000 synthetic streams (white and pink equal,
     1/sqrt(bins)) and prints the realised drives' half-to-half band-power
     ratios beside the measured half-slope ratios -- the pink runs' two-half
     and residual items are INFO with the reason printed.
Falsifiers are printed by name when they trigger: no s^2 scaling; pink equal
to white; W1 closer to (4/3)^2, 1/<cos^2 kz> or 2 times the prediction than
to it; T1 differing from W1; vertical growth under phase noise without the
strong beam (C1) or under horizontal amplitude noise without the strong beam
(C2). The
reference numbers are arguments with the theory note's section 6 values as
defaults; no verdict uses a constant that is not printed.
Prints `CRAB-NOISE-REPORT checks=.. failed=.. verdict=PASS|FAIL`; exit 1 on FAIL.

PART `control` (acceptance 6, the sharp linear check): with kbb = 0 and
chromaticity 0 every map the centroid meets is linear or composes to the
identity, so the centroid difference between C1 and C0 (same seed, same
initial sample) is the response to the realised kick sequence
dpx_c(n) = -sum_i s_i [<cos(i k z)> sin(dphi) + <sin(i k z)> (cos(dphi) - 1)]/(i k)
with the offsets regenerated through the rules' own path and the bunch
factors from the harness's initial sample, propagated through tccb2ip_inv,
tccb, tccb2ip, ip2tcca, tcca, ip2tcca_inv, one_turn (the observer's row n
holds the state after the pass of turn n). Metric: rms deviation of the
predicted from the measured normalised centroid (x/sqrt(beta*), px
sqrt(beta*)) over the run, relative to the measured rms excursion, PASS
below tol_centroid (1 %); the one-turn-shifted alignment is printed as a
diagnostic. Writes `<out>/control_<case>_centroid.tsv` (a decimated
turn-by-turn table) and `CRAB-NOISE-CONTROL ... verdict=PASS|FAIL`.
The same part then runs the covariance propagation (acceptance 7) over
`cov_cases` (default C0,C1,C3,C2): the initial sample's central 6x6 second
moments propagated turn by turn through the same maps with the REALISED
relative strength factors d_i of both cavities (S -> S (1 + d_i), so the
per-turn kick change is dpx = -S_X,i d_i sin(i k z)/(i k), dpy = -S_Y,i d_i
sin(i k z)/(i k), zero for the EIC cavity whose strengthY is 0, and dpz =
-(S_X,i x + S_Y,i y) d_i cos(i k z)) and the linearised shipped kick px -= dX
z, py -= dY z, pz -= dX x + dY y, dX = sum_i <cos(i k z)> S_X,i d_i, dY =
sum_i <cos(i k z)> S_Y,i d_i = 0 here (the regression of -S d sin(i k z)/(i k)
and -S d x cos(i k z) on the coordinates for the sampled Gaussian z; the
unexplained nonlinear variance, 0.06 % at k sigma_z = 0.25 and 1.0 % at 0.50,
and the error of a bare linearisation, 6 % and 27 %, are printed). Validated
where the answer is known -- C0 flat, C1 and C3 flat in the model (a dipole
drive), their measured eps_c slopes being the model's floor (the z-dependence
of the phase kick) and the chromatic decoherence it does not contain -- and
judged on C2: the measured eps_c x slope against the propagated one over
[n0, T] within `tol_c2` (0.10; the model residual is 0.1 %, the fit windows
are identical, so the margin is two orders of magnitude), and the measured
eps_c y slope minus the baseline's within `tol_c2_y` (0.05) of the propagated
x slope, the propagated y being exactly flat (dY = 0). Exact for a linear
kick on any distribution, so no decoherence is required: a flat y falsifies a
strength factor that reached strengthY = 0 as the additive both-planes
semantics did before 2026-10-15 (it predicted 0.87 of the x rate; the
FALSIFIER line names it), an x agreement falsifies a kick model other than
-S_X d sin(i k z)/(i k) with the realised d. Prints
`CRAB-NOISE-CONTROL-COVARIANCE checks=.. failed=.. verdict=..`.
=#

const PART = isempty(ARGS) ? "" : ARGS[1]
const PARTS = ("noise", "tablefile", "pilot", "sweep", "report", "control")
PART in PARTS || error("first argument must be one of $(join(PARTS, ", ")); got $(repr(PART)). " *
                       "See the header of this file.")

# key=value overrides after the part name.
const OPTS = Dict{String,String}()
for a in ARGS[2:end]
    m = match(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", a)
    m === nothing && error("argument $(repr(a)) is not key=value")
    OPTS[m.captures[1]] = m.captures[2]
end
# Every key a part reads is recorded, and `assert_options_consumed` (called by
# each part after its option block, before any work) refuses by name any key of
# the command line nothing read. Before 2026-10-20 a misspelt key kept its
# default silently and the verdict was taken on a number the operator did not
# set (comprehensive audit 2026-10-18, F-207). The set of known keys is DERIVED
# from the reads, not listed: a new `opt(...)` is known the moment it is written.
const OPTS_CONSUMED = Set{String}()
opt(key, default) = (push!(OPTS_CONSUMED, key); get(OPTS, key, default))
opt_int(key, default) = parse(Int, opt(key, string(default)))
opt_float(key, default) = parse(Float64, opt(key, string(default)))
has_opt(key) = (push!(OPTS_CONSUMED, key); haskey(OPTS, key))
function assert_options_consumed(part)
    unread = sort!(collect(setdiff(keys(OPTS), OPTS_CONSUMED)))
    isempty(unread) && return nothing
    error("part $(part) does not read the override key(s) $(join(unread, ", ")): a key " *
          "nothing reads would leave its default in force silently. The keys this part " *
          "reads are $(join(sort!(collect(OPTS_CONSUMED)), ", ")) (see the header).")
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const OUT_DIR = normpath(opt("out", joinpath(ROOT, "result", "crab_noise")))

if !isdefined(Main, :Octopus)
    include(joinpath(ROOT, "src", "Octopus.jl"))
end
using .Octopus
import FFTW
using Printf, Random, Statistics, LinearAlgebra

# ---------------------------------------------------------------------------
# The production point, shared by the parts (the example's numbers).
# ---------------------------------------------------------------------------
const SEED = 123456789                 # examples/weak_strong_tracking.jl
const CC_FREQUENCY = 197.0e6
const HALF_CROSSING = 12.5e-3
const BETA_X_STAR = 0.8
const CRAB_BETA_X = 1300.0
const HARMONIC_WEIGHTS = (4.0 / 3.0, -1.0 / 3.0, 0.0)
const CCKICK = tan(HALF_CROSSING) / sqrt(BETA_X_STAR * CRAB_BETA_X)
const CC_STRENGTH_X = CCKICK .* HARMONIC_WEIGHTS
const SIGMA_PHASE = 10.0e-6            # rad, harmonics 1-2
const REL_AMPLITUDE = 1.0e-4           # the strength rule's sigma, the RELATIVE rms (S (1 + d)), harmonics 1-2
const CC_STRENGTH_Y = (0.0, 0.0, 0.0)  # the example's vertical strengths: a horizontal cavity
const RNG_ID_BASE = (tccb = 10, tcca = 20) # the example's: rng_id = base + slot
const TABLE_SEED = 20261014                # the example's table_seed
const TABLE_TURNS_DEFAULT = 1_048_576      # the example's table_turns
const PINK_OCTAVES = 16

# ---------------------------------------------------------------------------
# Part `noise`.
# ---------------------------------------------------------------------------
# Spectral helpers after validation/turn_modulation_spectra.jl (that script
# runs at include, so its functions are restated here with the same
# definitions): power per octave band normalised to the top octave, the
# least-squares slope over the trusted bands.
function octave_power(seq::Vector{Float64})
    mu = sum(seq) / length(seq)
    P = abs2.(FFTW.rfft(seq .- mu))
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
function fitted_slope(bands::Vector{Float64}, first::Int)
    y = log2.(bands[first:end])
    x = collect(Float64, 0:length(y)-1)
    xm, ym = mean(x), mean(y)
    return sum((x .- xm) .* (y .- ym)) / sum(abs2, x .- xm)
end
rms(seq) = sqrt(sum(abs2, seq) / length(seq))

# Sample autocorrelation (biased, lags 0:N-1) through the FFT, for Bartlett's
# variance of a lag-0 cross-correlation between two independent sequences:
# Var[rho] = (1/N) sum_{|k|<N} rho_x(k) rho_y(k).
function autocorr(seq::Vector{Float64})
    N = length(seq)
    x = vcat(seq .- mean(seq), zeros(N))
    P = abs2.(FFTW.fft(x))
    acf = real.(FFTW.ifft(P))[1:N] ./ N
    return acf ./ acf[1]
end
function cross_corr(a::Vector{Float64}, b::Vector{Float64})
    da, db = a .- mean(a), b .- mean(b)
    return sum(da .* db) / sqrt(sum(abs2, da) * sum(abs2, db))
end
bartlett_se(ra::Vector{Float64}, rb::Vector{Float64}) =
    sqrt((1 + 2 * sum(@view(ra[2:end]) .* @view(rb[2:end]))) / length(ra))

# The pink statistics named in the header (K generators, N turns).
pink_rms_one_sigma(K, N) = 0.5 * sqrt((2 / (K^2 * N)) * sum(2.0^k * (2K - 1 - 2k) for k in 0:K-1))
pink_mean_sigma(K, N) = sqrt((2.0^K - 1) / (K * N))

# The example's synthetic white records (examples/crab_cavity_noise.jl,
# `noise_rule`): a master Xoshiro(seed) hands each active slot a UInt64 seed
# in construction order (tccb phase 1, phase 2, strength 1, strength 2, then
# tcca) and the slot's record is `sigma .* randn(Xoshiro(seed), L)`. `sigmas`
# holds the eight slot sigmas in that order, already scaled.
function synthetic_tables(sigmas::Vector{Float64}, L::Int; seed=TABLE_SEED)
    master = Random.Xoshiro(seed)
    return [sigma .* randn(Random.Xoshiro(rand(master, UInt64)), L) for sigma in sigmas]
end

# The Monte Carlo reference of the pink construction's band statistics at
# this N: mean and sd over `streams` synthetic Voss-McCartney streams of the
# log2 normalised octave powers (generator k is one randn per 2^k turns, the
# holds aligned to turn 0 as the rule's `turn >> k` keying; a generator
# slower than the run holds one value throughout).
function pink_band_reference(N::Int, K::Int; streams::Int=2048, seed::Int=1)
    rng = Random.Xoshiro(seed)
    logs = Vector{Vector{Float64}}()
    rms_ratios = zeros(streams)
    acc = zeros(N)
    for s in 1:streams
        fill!(acc, 0.0)
        for k in 0:K-1
            g = randn(rng, max(1, N >> k))
            acc .+= @view(repeat(g; inner=1 << k)[1:N])
        end
        acc ./= sqrt(K)
        rms_ratios[s] = rms(acc)
        bands, _ = octave_power(acc)
        push!(logs, log2.(bands))
    end
    M = reduce(hcat, logs)
    return vec(mean(M; dims=2)), vec(std(M; dims=2)), sort!(rms_ratios)
end
# The construction's finite-run rms over `streams` synthetic streams of N
# turns (rms only, allocation-free accumulation), sorted; the pink rms
# verdict band is its 0.5 % and 99.5 % quantiles at `long_turns`.
function pink_rms_mc_fn(N::Int, K::Int; streams::Int, seed::Int = 2)
    rng = Random.Xoshiro(seed)
    out = zeros(streams)
    acc = zeros(N)
    for s in 1:streams
        fill!(acc, 0.0)
        for k in 0:K-1
            g = randn(rng, ((N - 1) >> k) + 1)
            @inbounds for t in 0:N-1
                acc[t+1] += g[(t >> k) + 1]
            end
        end
        out[s] = sqrt(sum(abs2, acc) / (K * N))
    end
    return sort!(out)
end
quantile_sorted(sorted::Vector{Float64}, q::Float64) = sorted[clamp(round(Int, q * length(sorted)), 1, length(sorted))]

# Two-sided Monte Carlo p-value of an rms ratio under the construction.
mc_pvalue(sorted::Vector{Float64}, ratio::Float64) =
    min(1.0, 2 * min(count(>=(ratio), sorted), count(<=(ratio), sorted)) / length(sorted))

# The pink rule's documented construction rebuilt from the counter RNG for
# one slot: generator k's distinct draws for the run (indices 0:n-1 of
# `turn >> k`, n = max(1, N >> k)), the key layout of
# src/elements/turn_modulated.jl (particle slot 0, component
# `_RULE_COMPONENT_BASE + slot + _PINK_COMPONENT_STRIDE * (k + 1)`).
function pink_generators(rng_id::Int, slot::Int, N::Int, K::Int)
    code = Octopus.rng_method_code(:philox)
    return [[Octopus.octopus_normal(UInt64(SEED), code, Int64(j), UInt64(rng_id), 0,
                                    Octopus._RULE_COMPONENT_BASE + slot + Octopus._PINK_COMPONENT_STRIDE * (k + 1),
                                    Float64) for j in 0:max(1, N >> k)-1] for k in 0:K-1]
end
# The sequence the rule computes from those draws, in its accumulation order.
function pink_reconstruct(gens, sigma::Float64, N::Int, K::Int)
    out = zeros(N)
    for t in 0:N-1
        acc = 0.0
        for k in 0:K-1
            acc += gens[k+1][(t >> k) + 1]
        end
        out[t+1] = sigma * acc / sqrt(Float64(K))
    end
    return out
end
# Wilson-Hilferty approximation of the chi^2 quantile with nu degrees of
# freedom at the normal quantile z (z = 3.0902 for p = 0.999).
chi2_quantile_wh(nu, z) = nu * (1 - 2 / (9nu) + z * sqrt(2 / (9nu)))^3

# One cavity's spec at `scale` times the specification for `rule`
# (:white, :pink, :table, :spectral); `tables` holds that cavity's four
# records built at that scale for :table (raw vectors), and for :spectral
# the NamedTuple `(preset, band, amplitudes, turns)` of the `SpectralNoise`
# rule every slot carries (the rule keys on the slot's rng_id and the global
# seed, as the white and pink rules do, and resolves into a TurnTable when
# the line compiles). Stream ids and the synthetic table names are the
# example's.
function cavity_spec(rule::Symbol, scale::Float64, cav::Symbol, tables)
    base = RNG_ID_BASE[cav]
    sig_phase = scale * SIGMA_PHASE
    sig_strength = (scale * REL_AMPLITUDE, scale * REL_AMPLITUDE)   # the relative rms itself, no |strengthX_i| factor
    make(sigma, slot, k, label) =
        rule === :white ? WhiteNoise(sigma; rng_id=base + slot) :
        rule === :pink ? PinkNoise(sigma; rng_id=base + slot, octaves=PINK_OCTAVES) :
        rule === :spectral ? SpectralNoise(sigma, tables.band, tables.preset; rng_id=base + slot,
                                           turns=tables.turns, amplitudes=tables.amplitudes) :
        TurnTable(tables[k]; name="$(cav)_$(label)_synthetic_white")
    phase_rules = (make(sig_phase, 1, 1, "phase_noise[1]"), make(sig_phase, 2, 2, "phase_noise[2]"), nothing)
    strength_rules = (make(sig_strength[1], 4, 3, "strength_noise[1]"),
                      make(sig_strength[2], 5, 4, "strength_noise[2]"), nothing)
    return ThinCrabCavitySpec{3}(CC_FREQUENCY; strengthX=CC_STRENGTH_X, strengthY=CC_STRENGTH_Y,
                                 phase=(0.0, 0.0, 0.0), phase_noise=phase_rules,
                                 strength_noise=strength_rules)
end

# Realise a compiled cavity on turns 0:N-1 through the pure hook. Returns
#   seqs    the four active slot sequences AS THE ELEMENT CARRIES THEM: phase
#           1, phase 2 as the realised phase minus the nominal (exact, nominal
#           0); strength 1, strength 2 as the RELATIVE factor recovered from
#           the X plane, (strengthX_realised - strengthX)/strengthX -- the
#           subtraction is exact by Sterbenz, the (1 + d) rounding, the
#           product's and the division's each cost up to one ulp of 1;
#   draws   the rules' own values on each turn (`_turn_offset`: phase slots
#           1, 2 and strength slots 3 + i), the bitwise reference for the
#           pink-construction and table items;
#   exact_ok whether the element applied every value BITWISE on every turn:
#           phase_i == nominal + d (additive) and strengthX_i == strengthX_i
#           (1 + d) with strengthY_i === 0.0 (relative, 2026-10-15: a
#           horizontal cavity's amplitude noise kicks nothing vertically);
#   worst_recover_ulps  max |recovered - d| over the strength slots in eps(1.0);
#   inactive_ok  whether the inactive harmonic 3 stayed untouched.
function realise_sequences(w::TurnModulated, N::Int)
    base = w.base
    seqs = [zeros(N) for _ in 1:4]
    draws = [zeros(N) for _ in 1:4]
    exact_ok = true
    worst_recover_ulps = 0.0
    inactive_ok = true
    for t in 0:N-1
        ctx = TrackingContext(turn=t, seed=SEED, rng_method=:philox)
        u = Octopus.update(w, ctx)
        typeof(u) === typeof(w) || error("update changed the wrapper type on turn $(t)")
        c = u.inner
        for i in 1:2
            dp = Octopus._turn_offset(w.rule.phase[i], ctx, i, Float64)[1]
            draws[i][t+1] = dp
            seqs[i][t+1] = c.phase[i] - base.phase[i]
            exact_ok &= c.phase[i] == base.phase[i] + dp
            d = Octopus._turn_offset(w.rule.strength[i], ctx, 3 + i, Float64)[1]
            draws[2+i][t+1] = d
            exact_ok &= c.strengthX[i] == base.strengthX[i] * (1 + d) && c.strengthY[i] === 0.0
            recovered = (c.strengthX[i] - base.strengthX[i]) / base.strengthX[i]
            seqs[2+i][t+1] = recovered
            worst_recover_ulps = max(worst_recover_ulps, abs(recovered - d) / eps(1.0))
        end
        inactive_ok &= c.phase[3] == base.phase[3] && c.strengthX[3] == base.strengthX[3] &&
                       c.strengthY[3] == base.strengthY[3] && u.base === w.base
    end
    return seqs, draws, exact_ok, worst_recover_ulps, inactive_ok
end

function run_noise_part()
    N = opt_int("turns", 65536)
    (N >= 1024 && ispow2(N)) || error("turns must be a power of two >= 1024 (whole octave bands); got $(N)")
    scale_check = opt_float("scale_check", 10.0)
    L = opt_int("table_turns", TABLE_TURNS_DEFAULT)
    L >= N || error("table_turns ($(L)) must cover the realised turns ($(N))")
    N_LONG = opt_int("long_turns", 1_048_576)
    N_LONG >= N || error("long_turns ($(N_LONG)) must be at least turns ($(N))")
    rms_streams = opt_int("rms_streams", 4096)
    assert_options_consumed("noise")
    mkpath(OUT_DIR)
    set_global_rng!(seed=SEED, method=:philox)

    example_path = joinpath(ROOT, "examples", "crab_cavity_noise.jl")
    println("crab cavity noise, part noise: turns = $(N), seed = $(SEED), rng_method = philox, ",
            "rng_ids tccb = $(RNG_ID_BASE.tccb) + slot, tcca = $(RNG_ID_BASE.tcca) + slot (slots 1, 2, 4, 5), pink octaves = $(PINK_OCTAVES), ",
            "table_turns = $(L), table_seed = $(TABLE_SEED)")
    @printf("specification: sigma_phase = %.3e rad (h1, h2), added to the phase; sigma_strength = %.1e (h1, h2), the RELATIVE rms: a value d scales strengthX_i = (%.4e, %.4e) to strengthX_i (1 + d) and strengthY_i = 0 stays exactly 0 (relative, 2026-10-15); h3 inactive\n",
            SIGMA_PHASE, REL_AMPLITUDE, CC_STRENGTH_X[1], CC_STRENGTH_X[2])
    println("the stream ids, the table construction (master Xoshiro($(TABLE_SEED)), one UInt64 seed per active slot in construction order, sigma .* randn) and the table names follow examples/crab_cavity_noise.jl",
            isfile(example_path) ? " (present in this tree)" : " (NOT present in this tree: the construction is the one its 2026-10-13 text declared)")
    println()

    slot_labels = ["phase_noise[1]", "phase_noise[2]", "strength_noise[1]", "strength_noise[2]"]
    slot_sigmas = [SIGMA_PHASE, SIGMA_PHASE, REL_AMPLITUDE, REL_AMPLITUDE]   # rad, rad, relative, relative
    cavities = (:tccb, :tcca)
    sigmas8 = vcat(slot_sigmas, slot_sigmas)
    all_tables = synthetic_tables(sigmas8, L)
    all_tables_s = synthetic_tables(scale_check .* sigmas8, L)
    tables = Dict(:tccb => all_tables[1:4], :tcca => all_tables[5:8])
    tables_s = Dict(:tccb => all_tables_s[1:4], :tcca => all_tables_s[5:8])

    # The pink construction's own band statistics at this N (header).
    pink_mu, pink_sd, pink_rms_mc = pink_band_reference(N, PINK_OCTAVES)
    first_trusted = 3
    nb_ref = length(pink_mu)
    n_shape = nb_ref - first_trusted          # trusted bands below the top octave
    pink_q_max = chi2_quantile_wh(n_shape, 3.0902)
    println("pink reference ($(length(pink_rms_mc)) synthetic Voss-McCartney streams, K = $(PINK_OCTAVES), N = $(N)): expected band power relative to the top octave and the sd of its log2")
    for i in eachindex(pink_mu)
        @printf("  band %2d  bins %6d .. %6d   expected %.3f   sd(log2) %.3f%s\n", i, 2^i, 2^(i + 1) - 1,
                2.0^pink_mu[i], pink_sd[i], i < first_trusted ? "   (untrusted: too few bins)" : i == nb_ref ? "   (the normaliser)" : "")
    end
    @printf("  band-shape verdict per slot: sum of z^2 over the %d trusted bands below the top octave <= %.1f (chi^2 99.9 %% quantile, Wilson-Hilferty)\n", n_shape, pink_q_max)
    @printf("  rms/sigma of the construction over these streams at N = %d: mean %.4f, sd %.4f (formula %.4f), quantiles 1 %% %.4f, 99 %% %.4f, 99.9 %% %.4f, max %.4f (INFO only)\n",
            N, mean(pink_rms_mc), std(pink_rms_mc), pink_rms_one_sigma(PINK_OCTAVES, N), pink_rms_mc[max(1, round(Int, 0.01length(pink_rms_mc)))],
            pink_rms_mc[round(Int, 0.99length(pink_rms_mc))], pink_rms_mc[round(Int, 0.999length(pink_rms_mc))], pink_rms_mc[end])
    pink_rms_long_mc = pink_rms_mc_fn(N_LONG, PINK_OCTAVES; streams = rms_streams)
    pink_band = (quantile_sorted(pink_rms_long_mc, 0.005), quantile_sorted(pink_rms_long_mc, 0.995))
    @printf("  pink rms VERDICT band at %d turns: rms/sigma within [%.4f, %.4f] (two-sided 99 %%: the 0.5 %% and 99.5 %% quantiles over %d synthetic streams; mean %.4f, sd %.4f, formula %.4f)\n\n",
            N_LONG, pink_band[1], pink_band[2], rms_streams, mean(pink_rms_long_mc), std(pink_rms_long_mc), pink_rms_one_sigma(PINK_OCTAVES, N_LONG))
    pink_rows = String[]
    push!(pink_rows, join(["cavity", "slot", "band", "bins", "measured", "ref_mean_log2", "ref_sd_log2", "z", "trusted"], '\t'))

    checks = 0
    failed = 0
    rows = String[]
    corr_rows = String[]
    function verdict!(ok::Bool, label::String, value::String, tol::String)
        checks += 1
        ok || (failed += 1)
        println("  ", ok ? "PASS" : "FAIL", "  ", rpad(label, 56), value, "   (", tol, ")")
        return ok
    end

    pink_sigma_rms = pink_rms_one_sigma(PINK_OCTAVES, N)
    pink_sigma_mean = pink_mean_sigma(PINK_OCTAVES, N)
    white_tol = 3 * sqrt(1 / (2N))
    @printf("tolerances: white/table rms +-%.3f%%; pink rms judged over %d turns against the construction's 99 %% Monte Carlo band (below), the %d-turn value INFO with its p-value (one-sigma %.3f%% from Var[rms^2] at K = %d, N = %d); mean 3 sigma_mean (pink sigma_mean = %.4f sigma)\n\n",
            100white_tol, N_LONG, N, 100pink_sigma_rms, PINK_OCTAVES, N, pink_sigma_mean)

    push!(rows, join(["rule", "cavity", "slot", "check", "value", "expected", "tolerance", "pass"], '\t'))
    push!(corr_rows, join(["rule", "slot_a", "slot_b", "rho", "bartlett_se", "tolerance", "pass"], '\t'))
    rule_seqs = Dict{Symbol,Vector{Vector{Float64}}}()   # 8 sequences per rule, slot order
    table_rule_digests = Dict{Symbol,Vector{UInt64}}()
    # The rules' own values per (rule, cavity), four slots over turns 0:N-1:
    # the bitwise reference of the `recorded` item below.
    rule_draws = Dict{Tuple{Symbol,Symbol},Vector{Vector{Float64}}}()
    for rule in (:white, :pink, :table)
        println("rule $(rule)")
        seqs8 = Vector{Float64}[]
        for cav in cavities
            spec = cavity_spec(rule, 1.0, cav, tables[cav])
            w = compile_runtime(spec)
            w isa TurnModulated || error("compile_runtime did not wrap the $(cav) cavity; got a $(typeof(w))")
            # `rule_values`, not `draws`: the pink item below rebinds `draws` to the
            # generator vector (a name clash that made the item compare a scalar).
            seqs, rule_values, exact_ok, recover_ulps, inactive_ok = realise_sequences(w, N)
            append!(seqs8, seqs)
            rule_draws[(rule, cav)] = rule_values
            # The pink rms verdict reads the slot over the long window (header).
            seqs_long = rule === :pink ? realise_sequences(w, N_LONG)[1] : nothing
            if rule === :table
                table_rule_digests[cav] = [r.digest for r in (w.rule.phase[1], w.rule.phase[2], w.rule.strength[1], w.rule.strength[2])]
            end
            # Scale linearity: the same draws at scale_check times the specification.
            w_s = compile_runtime(cavity_spec(rule, scale_check, cav, tables_s[cav]))
            seqs_s, _, exact_ok_s, _, _ = realise_sequences(w_s, N)
            for (k, label) in enumerate(slot_labels)
                sigma = slot_sigmas[k]
                s = seqs[k]
                r = rms(s)
                mu = mean(s)
                is_pink = rule === :pink
                if is_pink
                    pval = mc_pvalue(pink_rms_mc, r / sigma)
                    @printf("  INFO  %-56s%.5f  (rms %.4e, sigma %.4e)  MC two-sided p %s at N = %d over %d streams; one-sigma %.2f %%, 3-sigma band would be +-%.4f\n",
                            "$(cav) $(label) rms/sigma over $(N) turns", r / sigma, r, sigma,
                            pval == 0 ? @sprintf("< %.4f", 1 / length(pink_rms_mc)) : @sprintf("= %.4f", pval), N, length(pink_rms_mc), 100pink_sigma_rms, 3pink_sigma_rms)
                    push!(rows, join([rule, cav, label, "rms_ratio_info_N", r / sigma, 1.0, 3pink_sigma_rms, "info"], '\t'))
                    r_long = rms(seqs_long[k])
                    ok = verdict!(pink_band[1] <= r_long / sigma <= pink_band[2], "$(cav) $(label) rms/sigma over $(N_LONG) turns",
                                  @sprintf("%.5f  (rms %.4e, sigma %.4e)", r_long / sigma, r_long, sigma),
                                  @sprintf("within [%.4f, %.4f], the construction's 99 %% band over %d streams", pink_band[1], pink_band[2], rms_streams))
                    push!(rows, join([rule, cav, label, "rms_ratio_long", r_long / sigma, 1.0, "[$(pink_band[1]),$(pink_band[2])]", ok], '\t'))
                else
                    ok = verdict!(abs(r / sigma - 1) <= white_tol, "$(cav) $(label) rms/sigma",
                                  @sprintf("%.5f  (rms %.4e, sigma %.4e)", r / sigma, r, sigma),
                                  @sprintf("|ratio - 1| <= %.4f", white_tol))
                    push!(rows, join([rule, cav, label, "rms_ratio", r / sigma, 1.0, white_tol, ok], '\t'))
                end
                if is_pink
                    slot_no = k <= 2 ? k : k + 1
                    gens = pink_generators(RNG_ID_BASE[cav] + slot_no, slot_no, N, PINK_OCTAVES)
                    rec = pink_reconstruct(gens, sigma, N, PINK_OCTAVES)
                    # The rule's own value is the bitwise object; the element carries it as
                    # phase + d or strengthX (1 + d), asserted by the exact item below.
                    same_cells = rec == rule_values[k]
                    ok = verdict!(same_cells, "$(cav) $(label) == counter-RNG construction",
                                  string(same_cells), "bitwise, sum_k normal(turn >> k) sigma / sqrt(K), key layout of turn_modulated.jl; the rule's value, applied by the element per the exact item")
                    push!(rows, join([rule, cav, label, "pink_cells_bitwise", same_cells, true, "exact", ok], '\t'))
                    draws = reduce(vcat, gens)
                    M = length(draws)
                    msq = mean(abs2, draws)
                    dtol = 3 * sqrt(2 / M)
                    ok = verdict!(abs(msq - 1) <= dtol, "$(cav) $(label) generator draws unit variance",
                                  @sprintf("mean square %.4f over %d distinct draws; slowest generators k=%d: %s, k=%d: %s, k=%d: %s",
                                           msq, M, PINK_OCTAVES - 1, join([@sprintf("%+.2f", v) for v in gens[end]], ","),
                                           PINK_OCTAVES - 2, join([@sprintf("%+.2f", v) for v in gens[end-1]], ","),
                                           PINK_OCTAVES - 3, join([@sprintf("%+.2f", v) for v in gens[end-2]], ",")),
                                  @sprintf("|mean square - 1| <= %.4f", dtol))
                    push!(rows, join([rule, cav, label, "pink_draws_msq", msq, 1.0, dtol, ok], '\t'))
                end
                mtol = 3 * sigma * (is_pink ? pink_sigma_mean : 1 / sqrt(N))
                ok = verdict!(abs(mu) <= mtol, "$(cav) $(label) mean",
                              @sprintf("%+.4e", mu), @sprintf("|mean| <= %.4e", mtol))
                push!(rows, join([rule, cav, label, "mean", mu, 0.0, mtol, ok], '\t'))
                bands, bins = octave_power(s)
                slope = fitted_slope(bands, first_trusted)
                expected = is_pink ? 0.0 : 1.0
                stol = is_pink ? 0.20 : 0.15
                ok = verdict!(abs(slope - expected) <= stol, "$(cav) $(label) log2 power/octave slope",
                              @sprintf("%+.3f over %d trusted bands", slope, length(bands) - first_trusted + 1),
                              @sprintf("%+.1f +- %.2f", expected, stol))
                push!(rows, join([rule, cav, label, "octave_slope", slope, expected, stol, ok], '\t'))
                if is_pink
                    z = (log2.(bands) .- pink_mu) ./ pink_sd
                    for i in eachindex(bands)
                        push!(pink_rows, join([cav, label, i, bins[i], bands[i], pink_mu[i], pink_sd[i], z[i], i >= first_trusted], '\t'))
                    end
                    zt = z[first_trusted:end-1]
                    Q = sum(abs2, zt)
                    worst_i = argmax(abs.(zt)) + first_trusted - 1
                    bmin, bmax = extrema(bands[first_trusted:end])
                    ok = verdict!(Q <= pink_q_max, "$(cav) $(label) pink band shape",
                                  @sprintf("sum z^2 = %.1f, worst |z| = %.2f at band %d (%.3f vs expected %.3f); trusted bands in [%.3f, %.3f]",
                                           Q, abs(z[worst_i]), worst_i, bands[worst_i], 2.0^pink_mu[worst_i], bmin, bmax),
                                  @sprintf("sum z^2 <= %.1f over %d bands", pink_q_max, n_shape))
                    push!(rows, join([rule, cav, label, "pink_band_chi2", Q, n_shape, pink_q_max, ok], '\t'))
                end
                ratio_s = rms(seqs_s[k]) / (scale_check * r)
                ok = verdict!(abs(ratio_s - 1) <= 1e-12, "$(cav) $(label) rms at scale $(scale_check)",
                              @sprintf("rms_scaled/(scale rms) = %.15f", ratio_s), "|ratio - 1| <= 1e-12")
                push!(rows, join([rule, cav, label, "scale_linearity", ratio_s, 1.0, 1e-12, ok], '\t'))
                if rule === :table
                    rec = tables[cav][k][1:N]
                    exact = rule_values[k] == rec
                    ok = verdict!(exact, "$(cav) $(label) realised value == record bitwise",
                                  string(exact), "every turn, the record's first $(N) entries (the rule's value; applied by the element per the exact item)")
                    push!(rows, join([rule, cav, label, "table_bitwise", exact, true, "exact", ok], '\t'))
                    if k > 2
                        # The factor recovered from the realised X plane carries the roundings.
                        dev = maximum(abs.(seqs[k] .- rec)) / eps(1.0)
                        ok = verdict!(dev <= 4, "$(cav) $(label) recovered factor == record",
                                      @sprintf("worst %.2f ulp(1)", dev), "<= 4 ulp(1)")
                        push!(rows, join([rule, cav, label, "table_recovered_ulps", dev, 0.0, 4, ok], '\t'))
                    end
                end
            end
            # The element applies every value bitwise: phase + d on a phase slot and,
            # by the relative semantics (owner decision 2026-10-15), one factor d per
            # harmonic on both planes -- strengthX (1 + d), the zero vertical nominal
            # staying EXACTLY 0.0, the falsifier of the decision (the additive
            # semantics before it put d itself on the Y plane).
            ok = verdict!(exact_ok && exact_ok_s, "$(cav) exact: phase + d; X == S (1 + d), Y === 0.0",
                          "bitwise on every turn at scale 1 ($(exact_ok)) and at scale $(scale_check) ($(exact_ok_s))", "exact (strength relative, 2026-10-15)")
            push!(rows, join([rule, cav, "all active slots", "exact_application", exact_ok && exact_ok_s, true, "exact", ok], '\t'))
            ok = verdict!(recover_ulps <= 4, "$(cav) recovered strength factor vs the rule's value",
                          @sprintf("worst %.2f ulp(1)", recover_ulps), "<= 4 ulp(1): the (1 + d), product and division roundings")
            push!(rows, join([rule, cav, "strength_noise[1:2]", "recovered_factor_ulps", recover_ulps, 0.0, 4, ok], '\t'))
            ok = verdict!(inactive_ok, "$(cav) harmonic 3 and base untouched", string(inactive_ok), "bitwise")
            push!(rows, join([rule, cav, "harmonic 3", "inactive", inactive_ok, true, "exact", ok], '\t'))
        end
        rule_seqs[rule] = seqs8
        # Independence: every pair of the eight active slot sequences.
        acfs = [autocorr(s) for s in seqs8]
        labels8 = vcat(["tccb $(l)" for l in slot_labels], ["tcca $(l)" for l in slot_labels])
        worst = 0.0
        worst_pair = ""
        npairs = 0
        nbad = 0
        for a in 1:8, b in a+1:8
            rho = cross_corr(seqs8[a], seqs8[b])
            se = bartlett_se(acfs[a], acfs[b])
            ok = abs(rho) <= 3se
            npairs += 1
            ok || (nbad += 1)
            if abs(rho) / se > worst
                worst = abs(rho) / se
                worst_pair = "$(labels8[a]) x $(labels8[b]): rho = $(@sprintf("%+.4f", rho)), se = $(@sprintf("%.4f", se))"
            end
            push!(corr_rows, join([rule, labels8[a], labels8[b], rho, se, 3se, ok], '\t'))
        end
        verdict!(nbad == 0, "slot and cavity independence ($(npairs) pairs)",
                 "worst |rho|/se = $(@sprintf("%.2f", worst)) at $(worst_pair)",
                 rule === :pink ? "|rho| <= 3 se (Bartlett; 3/sqrt(N) = $(@sprintf("%.4f", 3 / sqrt(N))) would be wrong for 1/f)" :
                                  "|rho| <= 3 se (Bartlett ~ 3/sqrt(N) = $(@sprintf("%.4f", 3 / sqrt(N))))")
        println()
    end

    # The table rule's provenance through a run artifact.
    println("table provenance through a run artifact")
    artifact_path = joinpath(OUT_DIR, "noise_table_provenance.h5")
    policy = CPUThreadsExecutionPolicy(threads=:auto)
    beam = Beam(256, policy, Float64;
                beta=(BETA_X_STAR, 0.072, 6.0e-2 / 6.6e-4), alpha=(0.0, 0.0, 0.0),
                emit=((95.0e-6)^2 / BETA_X_STAR, (8.5e-6)^2 / 0.072, 6.0e-2 * 6.6e-4),
                cutoff=5.0, rng_id=1, charge=1.0, mc2=PMASS_EV, E0=275.0e9,
                r0=RE * ME0 / PMASS_EV, npart=0.6881e11)
    specs = (cavity_spec(:table, 1.0, :tccb, tables[:tccb]),
             cavity_spec(:table, 1.0, :tcca, tables[:tcca]))
    task = TrackingTask(specs; policy=policy, artifact=RunArtifact(artifact_path; capacity=64))
    execute!(task, beam; turns=16)
    prov = turn_modulation_provenance(artifact_path)
    ok = verdict!(length(prov) == 1 && length(prov[1].elements) == 2,
                  "artifact lists one execution with two modulated elements",
                  "executions = $(length(prov)), elements = $(isempty(prov) ? 0 : length(prov[1].elements))", "1 and 2")
    push!(rows, join(["table", "both", "-", "provenance_elements", isempty(prov) ? 0 : length(prov[1].elements), 2, "exact", ok], '\t'))
    if ok
        for (c, cav) in enumerate(cavities)
            el = prov[1].elements[c]
            slots = el.slots
            kinds_ok = el.element == "ThinCrabCavity" && length(slots) == 4 && all(s.kind === :table for s in slots)
            digests = [s.digest for s in slots]
            expected = table_rule_digests[cav]
            digest_ok = digests == expected
            length_ok = all(s.length == L for s in slots)
            labels_ok = [s.slot for s in slots] == slot_labels
            names_ok = [s.name for s in slots] == ["$(cav)_$(l)_synthetic_white" for l in slot_labels]
            ok = verdict!(kinds_ok && digest_ok && length_ok && labels_ok && names_ok,
                          "$(cav) provenance: 4 table slots, digests, names, length",
                          "digests " * join([@sprintf("%016x", d) for d in digests], ","),
                          "== the rules' FNV-1a digests, length $(L), labels $(join(slot_labels, ",")), names <cavity>_<slot>_synthetic_white")
            push!(rows, join(["table", cav, "all", "provenance_digests", digest_ok && kinds_ok && length_ok && labels_ok && names_ok, true, "exact", ok], '\t'))
        end
    end
    same = read(TaskOutput(artifact_path), :turn_modulation) == prov
    ok = verdict!(same, "read(out, :turn_modulation) == turn_modulation_provenance", string(same), "equal")
    push!(rows, join(["table", "both", "-", "read_turn_modulation", same, true, "exact", ok], '\t'))

    # The recorded series through a run artifact (`record_turn_modulation =
    # true`; docs/design/turn_modulation_record.md, the `recorded` item of the
    # header): per rule, the two cavities alone track the same beam over the
    # N turns from turn 0 with the artifact recording, and every active slot's
    # `series`, read back through the public reader, must equal the hook's
    # replay above (`rule_draws`, the rules' own values on turns 0:N-1)
    # bitwise -- and, for the table rule, the record's first N entries. The
    # global seed is the task's context key, reset before each run as the
    # replay's `TrackingContext(seed = SEED, rng_method = :philox)` keyed it.
    println()
    println("recorded series through a run artifact (record_turn_modulation = true, $(N) turns from turn 0, the two cavities alone)")
    for rule in (:white, :pink, :table)
        recorded_path = joinpath(OUT_DIR, "noise_recorded_$(rule).h5")
        set_global_rng!(seed=SEED, method=:philox)
        specs_r = (cavity_spec(rule, 1.0, :tccb, tables[:tccb]),
                   cavity_spec(rule, 1.0, :tcca, tables[:tcca]))
        task_r = TrackingTask(specs_r; policy=policy,
                              artifact=RunArtifact(recorded_path; capacity=1024, record_turn_modulation=true))
        t_run = @elapsed execute!(task_r, beam; turns=N)
        prov_r = turn_modulation_provenance(recorded_path)
        shape_ok = length(prov_r) == 1 && length(prov_r[1].elements) == 2
        ok = verdict!(shape_ok, "$(rule): recording artifact lists one execution with two elements",
                      "executions = $(length(prov_r)), elements = $(isempty(prov_r) ? 0 : length(prov_r[1].elements)), execute! $(round(t_run; digits=1)) s",
                      "1 and 2")
        push!(rows, join([rule, "both", "-", "recorded_elements", isempty(prov_r) ? 0 : length(prov_r[1].elements), 2, "exact", ok], '\t'))
        shape_ok || continue
        for (c, cav) in enumerate(cavities)
            el = prov_r[1].elements[c]
            draws = rule_draws[(rule, cav)]
            labels_ok = [s.slot for s in el.slots] == slot_labels
            lengths = [s.series === nothing ? 0 : length(s.series) for s in el.slots]
            series_ok = labels_ok && all(el.slots[k].series !== nothing && el.slots[k].series == draws[k] for k in 1:4)
            record_ok = rule !== :table || all(el.slots[k].series == tables[cav][k][1:N] for k in 1:4)
            ok = verdict!(series_ok && record_ok, "$(cav) recorded series == hook replay ($(rule))",
                          "lengths $(lengths), labels $(labels_ok), bitwise $(series_ok)" *
                          (rule === :table ? ", == record $(record_ok)" : ""),
                          "bitwise over $(N) turns, 4 slots" * (rule === :table ? "; and the record's first $(N) entries" : ""))
            push!(rows, join([rule, cav, "all active slots", "recorded_series_bitwise", series_ok && record_ok, true, "exact", ok], '\t'))
        end
    end

    # The spectral producer and the consumer together (docs/design/
    # spectral_turn_table.md, section 6, check 7; the `spectral` item of the
    # header). The eight slots carry `SpectralNoise` rules on the example's
    # stream ids, resolved when the line compiles under the global seed, and
    # the same two-cavity task tracks the N turns from turn 0 with the
    # artifact recording. The record per slot is the library factory's own
    # table under that keying (`spectral_turn_table` with seed = SEED and the
    # slot's rng_id): every slot's recorded series must equal it bitwise (the
    # rule resolved to the factory's table; the consumer applied, and the
    # recorder wrote, its values), and the recorded series' periodogram must
    # be the design's: with fixed amplitudes |X_k|^2 = c^2 S(f_k) on every band bin,
    # c^2 = sigma^2 N^2 / (2 sum_interior S(f_k) + S(1/2) [the Nyquist bin,
    # when in the band]) the analytic normalisation (D5), roundoff elsewhere,
    # and the rms sigma; with Rayleigh amplitudes the bin powers are
    # exponential about c^2 S(f_k) and only the statistics are pinned. The
    # presets' shapes are evaluated here as S = 1 (flat) and S = 1/f (pink);
    # a constant factor in S cancels in |X_k|^2 / c^2, so the SHAPE is what
    # is pinned, not the preset's scale.
    println()
    rng_ids8 = [RNG_ID_BASE.tccb .+ (1, 2, 4, 5)..., RNG_ID_BASE.tcca .+ (1, 2, 4, 5)...]
    println("spectral rules through a run artifact (SpectralNoise resolved at compile; record_turn_modulation = true, $(N) turns from turn 0, ",
            "the two cavities alone; global seed $(SEED), rng_ids $(join(rng_ids8, ",")); the record per slot is spectral_turn_table under the same keying)")
    spectral_cases = (
        (preset = :flat, band = (3.0e-3, 4.0e-3), amplitudes = :fixed, S = f -> 1.0),
        (preset = :pink, band = (2.0^-14, 0.5), amplitudes = :fixed, S = f -> 1 / f),
        (preset = :flat, band = (3.0e-3, 4.0e-3), amplitudes = :rayleigh, S = f -> 1.0),
    )
    for case in spectral_cases
        tag = "$(case.preset)_$(case.amplitudes)"
        rule_tag = "spectral_$(tag)"
        lb, ub = case.band
        # The band bins as the factory defines them (D3): k with lb <= k/N <= ub, k >= 1.
        kband = [k for k in 1:(N ÷ 2) if lb <= k / N <= ub]
        K = length(kband)
        nyquist_in = iseven(N) && (N ÷ 2) in kband
        S_band = [case.S(k / N) for k in kband]
        # The analytic normalisation: interior bins count twice, the Nyquist bin once.
        weight_sum = 2 * sum(S_band) - (nyquist_in ? case.S(0.5) : 0.0)
        println("  case $(tag): band $(lb)..$(ub) cycles/turn, K = $(K) bins" *
                (K > 0 ? " (k = $(first(kband))..$(last(kband)))" : "") *
                ", Nyquist bin in the band: $(nyquist_in), amplitudes $(case.amplitudes)")
        # The record: the factory's table under the keying the rule resolves
        # with (the global seed SEED, the slot's rng_id and the slot index:
        # phase harmonic i -> i, strength harmonic i -> 3 + i on this
        # three-harmonic cavity).
        slots8 = [1, 2, 4, 5, 1, 2, 4, 5]
        refs8 = [spectral_turn_table(case.preset, sigmas8[j], case.band;
                                     turns = N, seed = SEED, rng_id = rng_ids8[j], slot = slots8[j],
                                     amplitudes = case.amplitudes)
                 for j in 1:8]
        recorded_path = joinpath(OUT_DIR, "noise_recorded_spectral_$(tag).h5")
        set_global_rng!(seed = SEED, method = :philox)
        spectral_params = (preset = case.preset, band = case.band, amplitudes = case.amplitudes, turns = N)
        specs_sp = (cavity_spec(:spectral, 1.0, :tccb, spectral_params),
                    cavity_spec(:spectral, 1.0, :tcca, spectral_params))
        task_sp = TrackingTask(specs_sp; policy = policy,
                               artifact = RunArtifact(recorded_path; capacity = 1024, record_turn_modulation = true))
        t_run = @elapsed execute!(task_sp, beam; turns = N)
        prov_sp = turn_modulation_provenance(recorded_path)
        shape_ok = length(prov_sp) == 1 && length(prov_sp[1].elements) == 2
        ok = verdict!(shape_ok, "spectral $(tag): artifact lists one execution with two elements",
                      "executions = $(length(prov_sp)), elements = $(isempty(prov_sp) ? 0 : length(prov_sp[1].elements)), execute! $(round(t_run; digits = 1)) s",
                      "1 and 2")
        push!(rows, join([rule_tag, "both", "-", "recorded_elements", isempty(prov_sp) ? 0 : length(prov_sp[1].elements), 2, "exact", ok], '\t'))
        shape_ok || continue
        for (c, cav) in enumerate(cavities), k in 1:4
            j = 4 * (c - 1) + k
            s = prov_sp[1].elements[c].slots[k]
            tbl = refs8[j]
            sigma = sigmas8[j]
            label = slot_labels[k]
            series_ok = s.slot == label && s.series !== nothing && s.series == tbl.offsets
            prov_ok = s.kind === :table && s.digest == tbl.digest && s.name == tbl.name && s.length == N
            ok = verdict!(series_ok && prov_ok, "$(cav) $(label) recorded series == factory table ($(tag))",
                          "bitwise $(series_ok); provenance kind :table, digest, name, length $(N): $(prov_ok) " *
                          "(recorded kind $(s.kind), name $(repr(s.name)); factory name $(repr(tbl.name)))",
                          "exact, over $(N) turns; rng_id $(rng_ids8[j]), seed $(SEED)")
            push!(rows, join([rule_tag, cav, label, "spectral_series_bitwise", series_ok && prov_ok, true, "exact", ok], '\t'))
            series_ok || continue
            x = s.series
            P = abs2.(FFTW.rfft(x))                    # |X_k|^2 for k = 0..N/2, the unnormalised DFT
            c2 = sigma^2 * N^2 / weight_sum
            ratios = P[kband .+ 1] ./ (c2 .* S_band)   # 1 up to rounding for fixed amplitudes, Exp(1) for Rayleigh
            peak = maximum(P[kband .+ 1])
            outside = setdiff(0:(N ÷ 2), kband)
            out_rel = maximum(P[outside .+ 1]) / peak
            dc_rel = P[1] / peak
            r = rms(x)
            if case.amplitudes === :fixed
                rel = maximum(abs.(ratios .- 1))
                ok = verdict!(rel <= 1e-10, "$(cav) $(label) periodogram / c^2 == S(f_k) on the band ($(tag))",
                              @sprintf("max relative error %.3e over %d bins", rel, K), "<= 1e-10 relative, every band bin")
                push!(rows, join([rule_tag, cav, label, "spectral_periodogram_rel", rel, 0.0, 1e-10, ok], '\t'))
                ok = verdict!(abs(r / sigma - 1) <= 1e-12, "$(cav) $(label) rms == sigma ($(tag))",
                              @sprintf("rms/sigma - 1 = %+.3e (rms %.6e, sigma %.1e)", r / sigma - 1, r, sigma),
                              "|ratio - 1| <= 1e-12: the analytic normalisation over the table's period")
                push!(rows, join([rule_tag, cav, label, "spectral_rms_rel", r / sigma - 1, 0.0, 1e-12, ok], '\t'))
            elseif K < 8
                # The statistical pins below are a mean and a variance over the
                # band's K bins; below 8 bins they say nothing (one bin has no
                # variance), so the item is a counted FAIL naming the bin count
                # rather than a NaN verdict or a silent skip.
                ok = verdict!(false, "$(cav) $(label) Rayleigh statistics ($(tag))",
                              "K = $(K) band bin(s) at N = $(N)",
                              "not evaluable below K = 8 bins (the narrow band holds 66 at the default 65536 turns); raise turns")
                push!(rows, join([rule_tag, cav, label, "spectral_rayleigh_not_evaluable", K, ">=8", "K >= 8", ok], '\t'))
            else
                m = mean(ratios)
                v = var(ratios)
                tol_m = 5 / sqrt(K)
                ok = verdict!(abs(m - 1) <= tol_m, "$(cav) $(label) band mean of periodogram / (c^2 S) ($(tag))",
                              @sprintf("%.4f over %d bins", m, K),
                              @sprintf("|mean - 1| <= 5/sqrt(K) = %.4f: exponential bin powers, mean 1, variance 1", tol_m))
                push!(rows, join([rule_tag, cav, label, "spectral_ratio_mean", m, 1.0, tol_m, ok], '\t'))
                ok = verdict!(v >= 0.1, "$(cav) $(label) scatter of the bin powers present ($(tag))",
                              @sprintf("sample variance of the %d ratios %.3f", K, v),
                              @sprintf(">= 0.1 (anti-vacuity: fixed amplitudes give exactly 0; exponential powers 1 +- %.2f)", sqrt(8 / K)))
                push!(rows, join([rule_tag, cav, label, "spectral_ratio_var", v, 1.0, ">=0.1", ok], '\t'))
                tol_r = 5 / (2 * sqrt(K))
                ok = verdict!(abs(r / sigma - 1) <= tol_r, "$(cav) $(label) rms/sigma ($(tag))",
                              @sprintf("%.5f (rms %.6e, sigma %.1e)", r / sigma, r, sigma),
                              @sprintf("|ratio - 1| <= 5/(2 sqrt(K)) = %.4f: sigma is the EXPECTED rms", tol_r))
                push!(rows, join([rule_tag, cav, label, "spectral_rms_ratio", r / sigma, 1.0, tol_r, ok], '\t'))
            end
            ok = verdict!(out_rel <= 1e-12, "$(cav) $(label) out-of-band and DC power ($(tag))",
                          @sprintf("max |X_k|^2 / band peak = %.3e over %d out-of-band bins, DC %.3e", out_rel, length(outside), dc_rel),
                          "<= 1e-12 of the band's peak (the transform's roundoff; the DC bin included)")
            push!(rows, join([rule_tag, cav, label, "spectral_out_of_band", out_rel, 0.0, 1e-12, ok], '\t'))
        end
    end

    summary_path = joinpath(OUT_DIR, "noise_summary.tsv")
    open(summary_path, "w") do io
        foreach(r -> println(io, r), rows)
        println(io, "# turns=$(N) long_turns=$(N_LONG) rms_streams=$(rms_streams) pink_rms_band=$(pink_band) seed=$(SEED) rng_id_base=$(RNG_ID_BASE) pink_octaves=$(PINK_OCTAVES) table_seed=$(TABLE_SEED) table_turns=$(L) scale_check=$(scale_check) checks=$(checks) failed=$(failed)")
    end
    corr_path = joinpath(OUT_DIR, "noise_correlations.tsv")
    open(corr_path, "w") do io
        foreach(r -> println(io, r), corr_rows)
    end
    bands_path = joinpath(OUT_DIR, "noise_pink_bands.tsv")
    open(bands_path, "w") do io
        foreach(r -> println(io, r), pink_rows)
    end
    println()
    println("wrote ", summary_path, ", ", corr_path, " and ", bands_path, "; artifact ", artifact_path)
    verdict = failed == 0
    println("CRAB-NOISE-RULES turns=$(N) checks=$(checks) failed=$(failed) verdict=$(verdict ? "PASS" : "FAIL")")
    verdict || exit(1)
end

# ---------------------------------------------------------------------------
# The subprocess driver and the fits (parts `tablefile`, `pilot`, `sweep`).
# Design: docs/theory/crab_cavity_noise_response.md section 7 and the
# campaign plan (result/crab_noise/D1/plan.md, committed with the record).
# ---------------------------------------------------------------------------
const HARNESS = joinpath(ROOT, "test", "examples", "crab_cavity_noise.jl")
const BETA_STAR = (x = BETA_X_STAR, y = 0.072)
const EPS_DESIGN = (x = (95.0e-6)^2 / BETA_X_STAR, y = (8.5e-6)^2 / 0.072)   # the example's emittances
const N0_DEFAULT = 2000                                                       # fit window start (the decoherence transient)
const RECEIPT_FIELDS = ["rule", "scale", "phase_rms", "strength_rel_rms", "chrom", "turns", "n_macro",
                        "kbb_scale", "radiation", "seed", "artifact", "eps_x_first", "eps_x_last",
                        "eps_y_first", "eps_y_last", "lumi_mean", "wall_s", "ms_per_turn"]
const PLANE_FIT_FIELDS = ["jraw_slope", "jraw_se", "jraw_y0", "jraw_h1", "jraw_h2", "jraw_resid",
                          "epsc_slope", "epsc_se", "epsc_y0", "epsc_h1", "epsc_h2", "epsc_resid",
                          "jc_mean", "jc_mean2", "jc_max", "cen_rms", "identity_max"]
const FIT_FIELDS = vcat(["n_rows", "n_window", "t_first", "t_last", "n0"],
                        ["$(f)_x" for f in PLANE_FIT_FIELDS], ["$(f)_y" for f in PLANE_FIT_FIELDS],
                        ["lumi_rows", "lumi_mean_fit", "lumi_trend", "lumi_trend_se"])
const TSV_HEADER = join(vcat(["id", "case", "artifact_copy", "table_file", "load_at_launch"], RECEIPT_FIELDS, FIT_FIELDS), '\t')

# The sweep of the plan (section 4): id, rule, scale, whether the phase and
# the strength rules are active, kbb_scale, chromaticity, the turn class.
# `phase = 0` sends OCTOPUS_PHASE_RMS=0 (no phase rule), `strength = 0`
# OCTOPUS_STRENGTH_REL_RMS=0. T1 is the table fed with W1's realised draws.
const SWEEP_CASES = (
    (id = "B0", rule = "none", scale = 1.0, phase = 1, strength = 1, kbb = 1.0, chrom = "2,2", tkind = :T, table = false),
    (id = "W1", rule = "white", scale = 1.0, phase = 1, strength = 0, kbb = 1.0, chrom = "2,2", tkind = :T, table = false),
    (id = "A1", rule = "white", scale = 1.0, phase = 0, strength = 1, kbb = 1.0, chrom = "2,2", tkind = :T, table = false),
    (id = "W2", rule = "white", scale = 2.0, phase = 1, strength = 0, kbb = 1.0, chrom = "2,2", tkind = :T, table = false),
    (id = "W3", rule = "white", scale = 4.0, phase = 1, strength = 0, kbb = 1.0, chrom = "2,2", tkind = :T, table = false),
    (id = "P1", rule = "pink", scale = 1.0, phase = 1, strength = 0, kbb = 1.0, chrom = "2,2", tkind = :Tpink, table = false),
    (id = "T2", rule = "table", scale = 1.0, phase = 1, strength = 0, kbb = 1.0, chrom = "2,2", tkind = :T, table = false),
    (id = "A4", rule = "white", scale = 4.0, phase = 0, strength = 1, kbb = 1.0, chrom = "2,2", tkind = :Ta4, table = false),
    (id = "A4s", rule = "white", scale = 4.0, phase = 0, strength = 1, kbb = 1.0, chrom = "2,2", tkind = :Ta4s, table = false),
    (id = "A2", rule = "white", scale = 2.0, phase = 0, strength = 1, kbb = 1.0, chrom = "2,2", tkind = :Ta4, table = false),
    (id = "A05", rule = "white", scale = 0.5, phase = 0, strength = 1, kbb = 1.0, chrom = "2,2", tkind = :T, table = false),
    (id = "AP1", rule = "pink", scale = 1.0, phase = 0, strength = 1, kbb = 1.0, chrom = "2,2", tkind = :Tpink, table = false),
    (id = "AT1", rule = "table", scale = 1.0, phase = 0, strength = 1, kbb = 1.0, chrom = "2,2", tkind = :T, table = false),
    (id = "C0", rule = "none", scale = 1.0, phase = 1, strength = 1, kbb = 0.0, chrom = "0,0", tkind = :T, table = false),
    (id = "C1", rule = "white", scale = 1.0, phase = 1, strength = 0, kbb = 0.0, chrom = "0,0", tkind = :T, table = false),
    (id = "C2", rule = "white", scale = 1.0, phase = 0, strength = 1, kbb = 0.0, chrom = "0,0", tkind = :T, table = false),
    (id = "T1", rule = "table", scale = 1.0, phase = 1, strength = 0, kbb = 1.0, chrom = "2,2", tkind = :T, table = true),
    (id = "C3", rule = "white", scale = 1.0, phase = 1, strength = 0, kbb = 0.0, chrom = "2,2", tkind = :T, table = false),
)
const SWEEP_DEFAULT_ORDER = "B0,W1,A1,W2,W3,P1,T2,A4,AP1,AT1,C0,C1,C2,T1"

tag_num(s) = replace(string(s), "." => "p", "-" => "m")
sweep_case_name(c, turns, n_macro) =
    "$(c.id)_$(c.rule)_s$(tag_num(c.scale))_p$(c.phase)_a$(c.strength)_k$(tag_num(c.kbb))_c$(replace(c.chrom, "," => ""))_T$(turns)_N$(n_macro)"

load_average() = try
    parse(Float64, split(read("/proc/loadavg", String))[1])
catch
    NaN
end

function parse_receipt_line(log_path::AbstractString)
    isfile(log_path) || return nothing
    line = nothing
    for l in eachline(log_path)
        startswith(l, "CRAB-NOISE ") && (line = l)
    end
    line === nothing && return nothing
    fields = Dict{String,String}()
    for tok in split(line)[2:end]
        kv = split(tok, "="; limit = 2)
        length(kv) == 2 && (fields[String(kv[1])] = String(kv[2]))
    end
    return fields
end

# Realise the white rules the harness would build for (phase_rms,
# strength_rel_rms, scale) on turns 0:turns-1 -- the same seed, stream ids
# (10 + slot, 20 + slot) and slots as the harness -- and write them as the
# table file the harness's OCTOPUS_TABLE_FILE reads: a TSV with one column
# per active slot, `<cavity>_phase_noise_<i>` / `<cavity>_strength_noise_<i>`,
# one row per turn, every value printed as its shortest round-trip repr
# (exact Float64). The phase offset is `sigma * n` exactly (nominal phase 0);
# the strength factor is the rule's own value `sigma * n` (`_turn_offset`),
# exact, with the realised X plane asserted equal to strengthX (1 + d) and the
# Y plane to 0.0 on every turn (relative semantics, 2026-10-15).
function write_table_file(path::AbstractString; turns::Int, scale::Float64, phase_rms::Float64,
                          strength_rel_rms::Float64)
    set_global_rng!(seed = SEED, method = :philox)
    cols = Pair{String,Vector{Float64}}[]
    for (cav, base) in pairs(RNG_ID_BASE)
        rule(sigma, slot) = sigma > 0 ? WhiteNoise(sigma; rng_id = base + slot) : nothing
        sp = scale * phase_rms
        ss = scale * strength_rel_rms          # the relative rms, the rule's sigma (S (1 + d))
        spec = ThinCrabCavitySpec{3}(CC_FREQUENCY; strengthX = CC_STRENGTH_X, strengthY = CC_STRENGTH_Y,
                                     phase = (0.0, 0.0, 0.0),
                                     phase_noise = (rule(sp, 1), rule(sp, 2), nothing),
                                     strength_noise = (rule(ss, 4), rule(ss, 5), nothing))
        w = compile_runtime(spec)
        w isa TurnModulated || error("no rule active for the table file (phase_rms = $(phase_rms), strength_rel_rms = $(strength_rel_rms))")
        ph = [zeros(turns), zeros(turns)]
        st = [zeros(turns), zeros(turns)]
        for t in 0:turns-1
            ctx = TrackingContext(turn = t, seed = SEED, rng_method = :philox)
            u = Octopus.update(w, ctx)
            for i in 1:2
                ph[i][t+1] = u.inner.phase[i] - w.base.phase[i]
                if ss > 0
                    d = Octopus._turn_offset(w.rule.strength[i], ctx, 3 + i, Float64)[1]
                    u.inner.strengthX[i] == w.base.strengthX[i] * (1 + d) || error(
                        "turn $(t), $(cav) strength_noise[$(i)]: the realised strengthX is not strengthX (1 + d) for the rule's value d")
                    u.inner.strengthY[i] === 0.0 || error(
                        "turn $(t), $(cav) strength_noise[$(i)]: the realised strengthY is $(u.inner.strengthY[i]), not 0.0 -- the relative semantics did not hold")
                    st[i][t+1] = d
                end
            end
        end
        sp > 0 && foreach(i -> push!(cols, "$(cav)_phase_noise_$(i)" => ph[i]), 1:2)
        ss > 0 && foreach(i -> push!(cols, "$(cav)_strength_noise_$(i)" => st[i]), 1:2)
    end
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, join(first.(cols), '\t'))
        for t in 1:turns
            println(io, join((repr(c.second[t]) for c in cols), '\t'))
        end
    end
    digests = Dict(c.first => Octopus._fnv1a64(reinterpret(UInt8, c.second)) for c in cols)
    println("wrote table file ", path, ": ", turns, " turns, columns ", join(first.(cols), ", "))
    return digests
end

# The FNV-1a digests of a table file's columns, as a TurnTable built from the
# parsed Float64 vectors would record them.
function table_file_digests(path::AbstractString)
    lines = readlines(path)
    header = split(lines[1], '\t')
    cols = [Float64[] for _ in header]
    for l in lines[2:end]
        isempty(l) && continue
        vals = split(l, '\t')
        for (k, v) in enumerate(vals)
            push!(cols[k], parse(Float64, v))
        end
    end
    return Dict(String(header[k]) => Octopus._fnv1a64(reinterpret(UInt8, cols[k])) for k in eachindex(header))
end

# Verify a table-fed run against the file it was fed: every active table slot
# of the artifact's provenance carries the digest of the matching column.
function verify_table_digests(artifact::AbstractString, table_file::AbstractString)
    want = table_file_digests(table_file)
    prov = turn_modulation_provenance(artifact)
    isempty(prov) && error("the T1 artifact $(artifact) records no turn modulation")
    problems = String[]
    seen = 0
    for (c, el) in enumerate(prov[end].elements)
        cav = c == 1 ? "tccb" : "tcca"
        for s in el.slots
            s.kind === :table || (push!(problems, "$(cav) $(s.slot) is $(s.kind), not a table"); continue)
            key = cav * "_" * replace(replace(s.slot, "[" => "_"), "]" => "")
            haskey(want, key) || (push!(problems, "$(cav) $(s.slot): no column $(key) in the file"); continue)
            seen += 1
            s.digest == want[key] || push!(problems, @sprintf("%s %s: digest %016x != file column %016x", cav, s.slot, s.digest, want[key]))
        end
    end
    seen == 0 && push!(problems, "no table slot found in the provenance")
    return problems
end

# Run one harness case as a subprocess and return the parsed receipt fields.
function run_case(; name, rule, scale, phase_rms, strength_rel_rms, turns, n_macro, kbb, chrom, radiation,
                  moment_step, gpu, threads, artifact_dir, table_file)
    isfile(HARNESS) || error("the developer harness $(HARNESS) does not exist yet")
    logdir = joinpath(OUT_DIR, "logs")
    mkpath(logdir)
    mkpath(artifact_dir)
    log_path = joinpath(logdir, name * ".log")
    env = ["OCTOPUS_USE_GPU" => string(gpu), "OCTOPUS_NOISE_RULE" => string(rule),
           "OCTOPUS_NOISE_SCALE" => string(scale), "OCTOPUS_PHASE_RMS" => string(phase_rms),
           "OCTOPUS_STRENGTH_REL_RMS" => string(strength_rel_rms), "OCTOPUS_PINK_OCTAVES" => string(PINK_OCTAVES),
           "OCTOPUS_TURNS" => string(turns), "OCTOPUS_N_MACRO" => string(n_macro),
           "OCTOPUS_KBB_SCALE" => string(kbb), "OCTOPUS_CHROMATICITY" => chrom,
           "OCTOPUS_RADIATION" => string(radiation), "OCTOPUS_RESULT_DIR" => artifact_dir,
           "OCTOPUS_CASE_NAME" => name, "OCTOPUS_MOMENT_STEP" => string(moment_step)]
    table_file === nothing || push!(env, "OCTOPUS_TABLE_FILE" => table_file)
    cmd = addenv(`julia --startup-file=no --project=$(ROOT) --threads=$(threads) $(HARNESS)`, env...)
    load = load_average()
    println("running ", name, " (load average at launch ", load, "): ",
            join(["$(k)=$(v)" for (k, v) in env], " "), " -> ", log_path)
    flush(stdout)
    t0 = time()
    ok = open(log_path, "w") do io
        println(io, "# launched ", Libc.strftime("%Y-%m-%d %H:%M:%S", time()), " load_average=", load)
        println(io, "# ", join(["$(k)=$(v)" for (k, v) in env], " "))
        flush(io)
        success(pipeline(cmd; stdout = io, stderr = io))
    end
    @printf("  subprocess %s in %.1f s\n", ok ? "finished" : "FAILED", time() - t0)
    ok || error("the harness failed for case $(name); see $(log_path)")
    fields = parse_receipt_line(log_path)
    fields === nothing && error("no CRAB-NOISE line in $(log_path)")
    fields["load_at_launch"] = string(load)
    return fields
end

# The receipt's readbacks must match what was requested (AGENTS.md: a
# configuration you set is not a configuration the code read). kbb_scale,
# radiation, chrom and seed are READ BACK by the harness from the compiled
# line the task tracked and from the artifact's ledger, device from the
# `:cuda_device` receipt (2026-10-16 neighbour audit, U7-3 and U7-4; the
# harness header's "READBACKS" paragraph), so comparing them with the
# request here is a check and not an echo of the request against itself.
# rule, scale, turns, n_macro, kbb_scale and radiation must match. The
# harness reports the EFFECTIVE sigmas (`phase_rms` = OCTOPUS_PHASE_RMS x
# scale, `strength_rel_rms` = OCTOPUS_STRENGTH_REL_RMS x scale, both 0 under
# rule none), `chrom` as `xi_x,xi_y` and `table_file` as the path or `none`;
# each must match when present, and must be present whenever the request
# departs from the harness default (a harness predating the field cannot
# show it read it). `device` must be present, an integer under gpu = 1 and NA
# under gpu = 0.
function verify_receipt(fields, name; rule, scale, phase_rms, strength_rel_rms, turns, n_macro, kbb, chrom, radiation,
                        gpu, table_file = nothing)
    same(a, b) = isapprox(parse(Float64, a), b; rtol = 1e-9, atol = 0.0)
    problems = String[]
    if haskey(fields, "device")
        if gpu == 1
            tryparse(Int, fields["device"]) === nothing &&
                push!(problems, "device=$(fields["device"]) is not a CUDA device index although OCTOPUS_USE_GPU=1 was requested")
        else
            fields["device"] == "NA" || push!(problems, "device=$(fields["device"]) but OCTOPUS_USE_GPU=0 was requested (a CPU run records no device)")
        end
    else
        push!(problems, "the receipt has no device field, so the harness cannot show which device ran (OCTOPUS_USE_GPU=$(gpu))")
    end
    fields["rule"] == string(rule) || push!(problems, "rule=$(fields["rule"]) != $(rule)")
    same(fields["scale"], scale) || push!(problems, "scale=$(fields["scale"]) != $(scale)")
    parse(Int, fields["turns"]) == turns || push!(problems, "turns=$(fields["turns"]) != $(turns)")
    parse(Int, fields["n_macro"]) == n_macro || push!(problems, "n_macro=$(fields["n_macro"]) != $(n_macro)")
    same(fields["kbb_scale"], kbb) || push!(problems, "kbb_scale=$(fields["kbb_scale"]) != $(kbb)")
    parse(Int, fields["radiation"]) == radiation || push!(problems, "radiation=$(fields["radiation"]) != $(radiation)")
    for (key, want, default) in (("phase_rms", phase_rms, SIGMA_PHASE), ("strength_rel_rms", strength_rel_rms, REL_AMPLITUDE))
        effective = rule == "none" ? 0.0 : want * scale
        if haskey(fields, key)
            (effective == 0 ? parse(Float64, fields[key]) == 0 : same(fields[key], effective)) ||
                push!(problems, "$(key)=$(fields[key]) != the effective $(effective) (request $(want) x scale $(scale))")
        elseif rule != "none" && want != default
            push!(problems, "the receipt has no $(key) field, so the harness may not have read OCTOPUS_$(uppercase(key))=$(want)")
        end
    end
    if haskey(fields, "chrom")
        got = parse.(Float64, split(replace(fields["chrom"], "(" => "", ")" => ""), ','))
        wanted = parse.(Float64, split(chrom, ','))
        got == wanted || push!(problems, "chrom=$(fields["chrom"]) != $(chrom)")
    elseif chrom != "2,2"
        push!(problems, "the receipt has no chrom field, so the harness may not have read OCTOPUS_CHROMATICITY=$(chrom)")
    end
    if table_file !== nothing
        get(fields, "table_file", "") == table_file || push!(problems, "table_file=$(get(fields, "table_file", "<absent>")) != $(table_file)")
    elseif haskey(fields, "table_file")
        fields["table_file"] == "none" || push!(problems, "table_file=$(fields["table_file"]) but none was requested")
    end
    isempty(problems) || error("case $(name): the harness receipt does not state the requested configuration: " * join(problems, "; "))
    return nothing
end

# Ordinary least squares of y against x: value at x[1], slope, se(slope)
# from the residuals, r^2 and the residual rms.
function linear_fit(x::Vector{Float64}, y::Vector{Float64})
    n = length(x)
    n >= 3 || return (y0 = NaN, slope = NaN, se = NaN, r2 = NaN, resid_rms = NaN)
    xm, ym = mean(x), mean(y)
    sxx = sum(abs2, x .- xm)
    slope = sum((x .- xm) .* (y .- ym)) / sxx
    a = ym - slope * xm
    resid = y .- (a .+ slope .* x)
    s2 = sum(abs2, resid) / (n - 2)
    sst = sum(abs2, y .- ym)
    return (y0 = a + slope * x[1], slope = slope, se = sqrt(s2 / sxx),
            r2 = sst > 0 ? 1 - sum(abs2, resid) / sst : NaN, resid_rms = sqrt(sum(abs2, resid) / n))
end

function moment_column(m, sym::Symbol)
    hasproperty(m, sym) || error("the moments table has no column $(sym); columns: $(join(string.(propertynames(m)), ", "))")
    return Vector{Float64}(getproperty(m, sym))
end

# The plan's estimators from the moments table (means and CENTRAL second
# moments): J_raw = [(<x^2>_c + <x>^2)/beta* + beta* (<px^2>_c + <px>^2)]/2,
# eps_c = sqrt(<x^2>_c <px^2>_c - <x px>_c^2), J_c = [<x>^2/beta* + beta* <px>^2]/2.
function plane_series(m, plane::Symbol)
    mu1, mu2, c20, c11, c02 = plane === :x ? (:m100000, :m010000, :m200000, :m110000, :m020000) :
                                              (:m001000, :m000100, :m002000, :m001100, :m000200)
    b = BETA_STAR[plane]
    x1, p1 = moment_column(m, mu1), moment_column(m, mu2)
    s20, s11, s02 = moment_column(m, c20), moment_column(m, c11), moment_column(m, c02)
    jraw = @. ((s20 + x1^2) / b + b * (s02 + p1^2)) / 2
    epsc = @. sqrt(max(s20 * s02 - s11^2, 0.0))
    jc = @. (x1^2 / b + b * p1^2) / 2
    return (jraw = jraw, epsc = epsc, jc = jc, cen = x1)
end

# Window fits [n0, T]: slope, se, value at the window start, the two-half
# slopes and the residual rms.
function window_fit(t::Vector{Float64}, y::Vector{Float64})
    f = linear_fit(t, y)
    h = length(t) ÷ 2
    f1 = linear_fit(t[1:h], y[1:h])
    f2 = linear_fit(t[h+1:end], y[h+1:end])
    return (slope = f.slope, se = f.se, y0 = f.y0, h1 = f1.slope, h2 = f2.slope, resid = f.resid_rms)
end

function fit_artifact(path::AbstractString; n0::Int = N0_DEFAULT)
    out = TaskOutput(path)
    m = read(out, :moments; name = "weak_beam")
    turn = Vector{Float64}(m.turn)
    idx = findall(>=(n0), turn)
    length(idx) >= 10 || error("fewer than 10 moment rows at turns >= $(n0) in $(path) (rows $(length(turn)), last turn $(turn[end]))")
    t = turn[idx]
    fits = Dict{String,Any}("n_rows" => length(turn), "n_window" => length(idx), "t_first" => t[1], "t_last" => t[end], "n0" => n0)
    for plane in (:x, :y)
        s = plane_series(m, plane)
        p = string(plane)
        fr = window_fit(t, s.jraw[idx])
        fe = window_fit(t, s.epsc[idx])
        jc = s.jc[idx]
        h = length(idx) ÷ 2
        fits["jraw_slope_$p"], fits["jraw_se_$p"], fits["jraw_y0_$p"] = fr.slope, fr.se, fr.y0
        fits["jraw_h1_$p"], fits["jraw_h2_$p"], fits["jraw_resid_$p"] = fr.h1, fr.h2, fr.resid
        fits["epsc_slope_$p"], fits["epsc_se_$p"], fits["epsc_y0_$p"] = fe.slope, fe.se, fe.y0
        fits["epsc_h1_$p"], fits["epsc_h2_$p"], fits["epsc_resid_$p"] = fe.h1, fe.h2, fe.resid
        fits["jc_mean_$p"], fits["jc_mean2_$p"], fits["jc_max_$p"] = mean(jc), mean(jc[h+1:end]), maximum(jc)
        fits["cen_rms_$p"] = sqrt(mean(abs2, s.cen[idx]))
        fits["identity_max_$p"] = maximum(abs.(s.jraw[idx] .- s.epsc[idx] .- jc)) / EPS_DESIGN[plane]
    end
    lum = read(out, :luminosity; name = "strong_beam_1")
    lt, lv = Vector{Float64}(lum.turn), Vector{Float64}(lum.value)
    li = findall(>=(n0), lt)
    fl = linear_fit(lt[li], lv[li])
    lmean = mean(lv[li])
    fits["lumi_rows"], fits["lumi_mean_fit"] = length(lt), lmean
    fits["lumi_trend"], fits["lumi_trend_se"] = fl.slope / lmean, fl.se / lmean
    return fits
end

tsv_row(id, name, copy_path, table_file, fields, fits) =
    join(vcat([id, name, copy_path, table_file === nothing ? "-" : table_file, get(fields, "load_at_launch", "NA")],
              [get(fields, f, "NA") for f in RECEIPT_FIELDS], [string(fits[f]) for f in FIT_FIELDS]), '\t')

function read_tsv(path::AbstractString)
    rows = Dict{String,String}[]
    isfile(path) || return rows
    header = nothing
    for l in eachline(path)
        (isempty(l) || startswith(l, "#")) && continue
        cols = split(l, '\t')
        if header === nothing
            header = String.(cols)
            continue
        end
        push!(rows, Dict(header[i] => String(cols[i]) for i in 1:min(length(header), length(cols))))
    end
    return rows
end

# One case end to end with the resumption rules of the header: a row in the
# TSV skips it; a receipt in its log with the artifact present is re-read
# (fits recomputed) without re-running; anything else runs. The artifact is
# written to `artifact_dir` (local disk) and copied under <out>/artifacts/.
function case_row(c; id, name, turns, n_macro, moment_step, gpu, threads, radiation, artifact_dir, n0, table_file, done::Set{String})
    name in done && (println("skipping ", name, ": row present"); return nothing)
    log_path = joinpath(OUT_DIR, "logs", name * ".log")
    fields = parse_receipt_line(log_path)
    phase_rms = c.phase == 1 ? SIGMA_PHASE : 0.0
    strength_rel_rms = c.strength == 1 ? REL_AMPLITUDE : 0.0
    if fields !== nothing && haskey(fields, "artifact") && isfile(fields["artifact"])
        println("re-reading ", name, ": receipt and artifact present, not re-run")
        haskey(fields, "load_at_launch") || (fields["load_at_launch"] = "NA")
    else
        fields = run_case(; name, rule = c.rule, scale = c.scale, phase_rms, strength_rel_rms, turns, n_macro,
                          kbb = c.kbb, chrom = c.chrom, radiation, moment_step, gpu, threads, artifact_dir, table_file)
    end
    verify_receipt(fields, name; rule = c.rule, scale = c.scale, phase_rms, strength_rel_rms, turns, n_macro,
                   kbb = c.kbb, chrom = c.chrom, radiation, gpu, table_file)
    if table_file !== nothing
        problems = verify_table_digests(fields["artifact"], table_file)
        isempty(problems) || error("case $(name): the table-fed run does not carry the file's digests: " * join(problems, "; "))
        println("  table digests of ", basename(table_file), " verified in the artifact's provenance")
    end
    fits = fit_artifact(fields["artifact"]; n0)
    copy_path = fields["artifact"]
    if normpath(artifact_dir) != normpath(OUT_DIR)
        mkpath(joinpath(OUT_DIR, "artifacts"))
        copy_path = joinpath(OUT_DIR, "artifacts", basename(fields["artifact"]))
        cp(fields["artifact"], copy_path; force = true)
    end
    return (id = id, name = name, fields = fields, fits = fits, copy_path = copy_path, table_file = table_file)
end

function print_case(r)
    f, t = r.fields, r.fits
    @printf("  %-6s %-52s J_raw x %+.3e +- %.1e /turn (halves %+.3e %+.3e)  eps_c x %+.3e  J_raw y %+.3e  eps_c y %+.3e  lumi %.4e trend %+.2e  %s ms/turn\n",
            r.id, r.name, t["jraw_slope_x"] / EPS_DESIGN.x, t["jraw_se_x"] / EPS_DESIGN.x, t["jraw_h1_x"] / EPS_DESIGN.x,
            t["jraw_h2_x"] / EPS_DESIGN.x, t["epsc_slope_x"] / EPS_DESIGN.x, t["jraw_slope_y"] / EPS_DESIGN.y,
            t["epsc_slope_y"] / EPS_DESIGN.y, t["lumi_mean_fit"], t["lumi_trend"], get(f, "ms_per_turn", "NA"))
end

function run_tablefile_part()
    path = opt("path", joinpath(OUT_DIR, "W1_realised_offsets.tsv"))
    turns = opt_int("turns", 100_000)
    scale = opt_float("scale", 1.0)
    phase_rms = opt_float("phase_rms", SIGMA_PHASE)
    strength_rel_rms = opt_float("strength_rel_rms", 0.0)
    assert_options_consumed("tablefile")
    mkpath(OUT_DIR)
    digests = write_table_file(path; turns, scale, phase_rms, strength_rel_rms)
    for (k, d) in sort(collect(digests))
        @printf("  %-24s digest %016x\n", k, d)
    end
    println("CRAB-NOISE-TABLEFILE path=$(path) turns=$(turns) scale=$(scale) phase_rms=$(phase_rms) strength_rel_rms=$(strength_rel_rms)")
end

function run_pilot_part()
    turns = opt_int("turns", 6000)
    n_macro = opt_int("n_macro", 100_000)
    turns_timing = opt_int("turns_timing", 1000)
    n_macro_timing = opt_int("n_macro_timing", 1_000_000)
    moment_step = opt_int("moment_step", 1)
    gpu = opt_int("gpu", 1)
    threads = opt_int("threads", 4)
    n0 = opt_int("n0", N0_DEFAULT)
    artifact_dir = normpath(opt("artifact_dir", OUT_DIR))
    assert_options_consumed("pilot")
    mkpath(OUT_DIR)
    tsv = joinpath(OUT_DIR, "pilot.tsv")
    done = Set(r["case"] for r in read_tsv(tsv))
    isfile(tsv) || open(io -> println(io, TSV_HEADER), tsv, "w")
    println("crab cavity noise, part pilot: turns = $(turns), n_macro = $(n_macro), moment_step = $(moment_step), gpu = $(gpu), threads = $(threads), radiation = 0, fit window [$(n0), $(turns)]; timing case: none at n_macro = $(n_macro_timing), $(turns_timing) turns")
    cases = [(id = "PW100", rule = "white", scale = 100.0, phase = 1, strength = 1, kbb = 1.0, chrom = "2,2", turns = turns, n = n_macro),
             (id = "PW30", rule = "white", scale = 30.0, phase = 1, strength = 1, kbb = 1.0, chrom = "2,2", turns = turns, n = n_macro),
             (id = "PN", rule = "none", scale = 1.0, phase = 1, strength = 1, kbb = 1.0, chrom = "2,2", turns = turns, n = n_macro),
             (id = "PW100K0", rule = "white", scale = 100.0, phase = 1, strength = 1, kbb = 0.0, chrom = "2,2", turns = turns, n = n_macro),
             (id = "PTIME", rule = "none", scale = 1.0, phase = 1, strength = 1, kbb = 1.0, chrom = "2,2", turns = turns_timing, n = n_macro_timing)]
    for c in cases
        name = sweep_case_name(c, c.turns, c.n)
        r = case_row(c; id = c.id, name, turns = c.turns, n_macro = c.n, moment_step, gpu, threads, radiation = 0,
                     artifact_dir, n0 = c.id == "PTIME" ? 0 : n0, table_file = nothing, done)
        r === nothing && continue
        open(io -> println(io, tsv_row(r.id, r.name, r.copy_path, r.table_file, r.fields, r.fits)), tsv, "a")
        print_case(r)
    end
    rows = read_tsv(tsv)
    byid = Dict(r["id"] => r for r in rows)
    num(r, k) = parse(Float64, r[k])
    println()
    println("pilot fits: relative J_raw slope per turn over [$(n0), T] (OLS; se from residuals, a lower bound for autocorrelated residuals):")
    for r in rows
        @printf("  %-8s J_raw x %+.3e +- %.1e (halves %+.3e, %+.3e)  eps_c x %+.3e +- %.1e  J_c x mean %.3e  J_raw y %+.3e  eps_c y %+.3e  lumi %.4e trend %+.2e  %s ms/turn (N = %s, load %s)\n",
                r["id"], num(r, "jraw_slope_x") / EPS_DESIGN.x, num(r, "jraw_se_x") / EPS_DESIGN.x,
                num(r, "jraw_h1_x") / EPS_DESIGN.x, num(r, "jraw_h2_x") / EPS_DESIGN.x,
                num(r, "epsc_slope_x") / EPS_DESIGN.x, num(r, "epsc_se_x") / EPS_DESIGN.x, num(r, "jc_mean_x") / EPS_DESIGN.x,
                num(r, "jraw_slope_y") / EPS_DESIGN.y, num(r, "epsc_slope_y") / EPS_DESIGN.y,
                num(r, "lumi_mean_fit"), num(r, "lumi_trend"), r["ms_per_turn"], r["n_macro"], r["load_at_launch"])
    end
    if all(haskey(byid, k) for k in ("PW100", "PW30", "PN", "PW100K0"))
        rate(id) = num(byid[id], "jraw_slope_x") / EPS_DESIGN.x
        se(id) = num(byid[id], "jraw_se_x") / EPS_DESIGN.x
        r100, r30, rn, rk0 = rate("PW100"), rate("PW30"), rate("PN"), rate("PW100K0")
        sample_noise = sqrt(2 / n_macro)
        println()
        @printf("scale 100 rate_x %+.3e vs baseline (none) %+.3e: excess %.3e = %.1f se (quadrature); one-sample estimator noise sqrt(2/N) = %.2e\n",
                r100, rn, r100 - rn, (r100 - rn) / hypot(se("PW100"), se("PN")), sample_noise)
        @printf("scale 30 / scale 100 baseline-subtracted rate ratio %.3f (expected 0.09 for a rate quadratic in the amplitude, in the small-growth regime only)\n", (r30 - rn) / (r100 - rn))
        @printf("kbb = 0 / full rate ratio at scale 100: %.3f (baseline-subtracted %.3f); eps_c slopes kbb = 0 %+.3e vs full %+.3e\n",
                rk0 / r100, (rk0 - rn) / (r100 - rn), num(byid["PW100K0"], "epsc_slope_x") / EPS_DESIGN.x, num(byid["PW100"], "epsc_slope_x") / EPS_DESIGN.x)
    end
    if haskey(byid, "PTIME")
        c = num(byid["PTIME"], "ms_per_turn")
        @printf("ms_per_turn at N = %s: %.2f (JIT of the first turn included over %s turns); sweep budget 1.5e6 turn-runs -> %.1f h; the plan drops to N = 2e5 above 13 ms/turn\n",
                byid["PTIME"]["n_macro"], c, byid["PTIME"]["turns"], 1.5e6 * c / 3.6e6)
    end
    println("wrote ", tsv)
end

function run_sweep_part()
    tag = opt("tag", "")
    isempty(tag) && error("sweep needs tag=<tag> (names the TSV sweep_<tag>.tsv)")
    ids = String.(split(opt("cases", SWEEP_DEFAULT_ORDER), ','))
    turns = opt_int("turns", 100_000)
    turns_pink = opt_int("turns_pink", 131072)
    turns_a4 = opt_int("turns_a4", 25_000)
    turns_a4s = opt_int("turns_a4s", 12_500)
    n_macro = opt_int("n_macro", 1_000_000)
    moment_step = opt_int("moment_step", 1)
    gpu = opt_int("gpu", 1)
    threads = opt_int("threads", 4)
    n0 = opt_int("n0", N0_DEFAULT)
    radiation = opt_int("radiation", 0)
    artifact_dir = normpath(opt("artifact_dir", OUT_DIR))
    table_file = opt("table_file", joinpath(OUT_DIR, "W1_realised_offsets_T$(turns).tsv"))
    assert_options_consumed("sweep")
    mkpath(OUT_DIR)
    tsv = joinpath(OUT_DIR, "sweep_$(tag).tsv")
    done = Set(r["case"] for r in read_tsv(tsv))
    isfile(tsv) || open(io -> println(io, TSV_HEADER), tsv, "w")
    println("crab cavity noise, part sweep $(tag): cases = $(join(ids, ",")), turns = $(turns) (pink $(turns_pink), A4 $(turns_a4), A4s $(turns_a4s)), n_macro = $(n_macro), moment_step = $(moment_step), gpu = $(gpu), threads = $(threads), radiation = $(radiation), fit window from turn $(n0), artifacts under $(artifact_dir), TSV $(tsv)")
    bycase = Dict(c.id => c for c in SWEEP_CASES)
    for id in ids
        haskey(bycase, id) || error("unknown sweep case $(id); known: $(join([c.id for c in SWEEP_CASES], ", "))")
        c = bycase[id]
        T = c.tkind === :Tpink ? turns_pink : c.tkind === :Ta4 ? turns_a4 : c.tkind === :Ta4s ? turns_a4s : turns
        tf = nothing
        if c.table
            if !isfile(table_file)
                println("building the W1 draws table file for T1: ", table_file)
                write_table_file(table_file; turns = T, scale = 1.0, phase_rms = SIGMA_PHASE, strength_rel_rms = 0.0)
            end
            tf = table_file
        end
        r = case_row(c; id, name = sweep_case_name(c, T, n_macro), turns = T, n_macro, moment_step, gpu, threads,
                     radiation, artifact_dir, n0, table_file = tf, done)
        r === nothing && continue
        open(io -> println(io, tsv_row(r.id, r.name, r.copy_path, r.table_file, r.fields, r.fits)), tsv, "a")
        print_case(r)
        flush(stdout)
    end
    println("sweep $(tag) done; wrote ", tsv)
end

# ---------------------------------------------------------------------------
# Part `report`: the plan's acceptance on a sweep TSV (plus the T1 == W1
# artifact comparison, which reads the two artifacts).
# ---------------------------------------------------------------------------
# The beam-beam parameter of the weak beam at the IP from the strong beam's
# sizes, xi = N r_p beta* / (2 pi gamma sigma (sigma_x + sigma_y)).
function beam_beam_xi()
    rp = RE * ME0 / PMASS_EV
    gam = 275.0e9 / PMASS_EV
    sx, sy = 95.0e-6, 8.5e-6
    return (x = 1.7203e11 * rp * BETA_X_STAR / (2pi * gam * sx * (sx + sy)),
            y = 1.7203e11 * rp * 0.072 / (2pi * gam * sy * (sx + sy)))
end
# Mean periodogram of `seq` over the band [lo, hi] (cycles per turn) and its bin count.
function band_average(seq::Vector{Float64}, lo::Float64, hi::Float64)
    N = length(seq)
    P = abs2.(FFTW.rfft(seq .- mean(seq)))
    j1 = max(2, round(Int, lo * N) + 1)
    j2 = min(length(P), round(Int, hi * N) + 1)
    return mean(@view P[j1:j2]), j2 - j1 + 1
end
# sd/mean of the band average over `streams` synthetic streams of N turns, a
# white drive and the Voss-McCartney pink construction: the single-realisation
# scatter of a rate proportional to the drive's band power.
function band_scatter_mc(N::Int, lo::Float64, hi::Float64; streams::Int = 2000, seed::Int = 3)
    rng = Random.Xoshiro(seed)
    bw, bp = zeros(streams), zeros(streams)
    nb = 0
    acc = zeros(N)
    for s in 1:streams
        bw[s], nb = band_average(randn(rng, N), lo, hi)
        fill!(acc, 0.0)
        for k in 0:PINK_OCTAVES-1
            g = randn(rng, ((N - 1) >> k) + 1)
            @inbounds for t in 0:N-1
                acc[t+1] += g[(t >> k) + 1]
            end
        end
        bp[s], _ = band_average(acc, lo, hi)
    end
    return (white = std(bw) / mean(bw), pink = std(bp) / mean(bp), bins = nb)
end
# The realised drive of a sweep row (its rule, effective sigmas and the
# harness's stream ids, through the rules' own path) and the ratio of its
# kick-weighted band power between the two halves of the run.
function realised_band_ratio(r, lo::Float64, hi::Float64)
    T = parse(Int, r["turns"])
    phase_sigma = r["phase_rms"] != "NA" ? parse(Float64, r["phase_rms"]) : 0.0
    strength_rel = r["strength_rel_rms"] != "NA" ? parse(Float64, r["strength_rel_rms"]) : 0.0
    r["rule"] in ("white", "pink") || return NaN
    kcc = 2pi * CC_FREQUENCY / CLIGHT
    sz = 6.0e-2
    mk(sigma, id) = r["rule"] == "white" ? WhiteNoise(sigma; rng_id = id) : PinkNoise(sigma; rng_id = id, octaves = PINK_OCTAVES)
    power = [0.0, 0.0]
    for (cav, base) in pairs(RNG_ID_BASE)
        if phase_sigma > 0
            spec = ThinCrabCavitySpec{3}(CC_FREQUENCY; strengthX = CC_STRENGTH_X, strengthY = (0.0, 0.0, 0.0), phase = (0.0, 0.0, 0.0),
                                         phase_noise = (mk(phase_sigma, base + 1), mk(phase_sigma, base + 2), nothing))
            weights = [(abs(CC_STRENGTH_X[i]) * exp(-(i * kcc * sz)^2 / 2) / (i * kcc))^2 for i in 1:2]
            pick = (u, i) -> u.inner.phase[i]
        elseif strength_rel > 0
            # The relative rule (2026-10-15): sigma is the relative rms itself, the
            # realised factor d is dimensionless and the kick it drives is
            # -S_X,i d sin(i k z)/(i k), so S_X,i^2 enters the band-power weights;
            # d is recovered from the X plane (strengthY stays exactly 0).
            spec = ThinCrabCavitySpec{3}(CC_FREQUENCY; strengthX = CC_STRENGTH_X, strengthY = CC_STRENGTH_Y, phase = (0.0, 0.0, 0.0),
                                         strength_noise = (mk(strength_rel, base + 4), mk(strength_rel, base + 5), nothing))
            weights = [CC_STRENGTH_X[i]^2 * exp(-(i * kcc * sz)^2) * sz^2 for i in 1:2]
            pick = (u, i) -> (u.inner.strengthX[i] - CC_STRENGTH_X[i]) / CC_STRENGTH_X[i]
        else
            return NaN
        end
        w = compile_runtime(spec)
        seq = [zeros(T), zeros(T)]
        for t in 0:T-1
            u = Octopus.update(w, TrackingContext(turn = t, seed = SEED, rng_method = :philox))
            seq[1][t+1] = pick(u, 1)
            seq[2][t+1] = pick(u, 2)
        end
        half = T ÷ 2
        for (h, part) in enumerate((1:half, half+1:T))
            power[h] += sum(weights[i] * band_average(seq[i][part], lo, hi)[1] for i in 1:2)
        end
    end
    return power[1] / power[2]
end

function run_report_part()
    tsv = opt("tsv", "")
    isempty(tsv) && error("report needs tsv=<sweep tsv>")
    # Reference numbers (docs/theory/crab_cavity_noise_response.md section 6)
    # and tolerances (section 7), every one overridable.
    has_opt("ref_amp_white_y") && error(
        "ref_amp_white_y is retired (2026-10-15): the relative strength rule leaves strengthY = 0, so there is " *
        "no both-planes vertical prediction; the vertical rate under amplitude noise is the beam-beam coupling " *
        "alone (INFO) and C2 must show none without beam-beam (7)")
    ref = (phase_white_x = opt_float("ref_phase_white_x", 1.72e-7),
           amp_white_x = opt_float("ref_amp_white_x", 1.10e-6),
           pink_ratio_x = opt_float("ref_pink_ratio_x", 0.15),
           pink_ratio_y = opt_float("ref_pink_ratio_y", 0.17),
           y_over_x_phase = has_opt("ref_y_over_x_phase") ? opt_float("ref_y_over_x_phase", 0.0) : nothing)
    tol_rate = opt_float("tol_rate", 1.25)
    tol_exp = opt_float("tol_exp", 0.1)
    tol_ratio = opt_float("tol_ratio", 0.25)
    tol_t1 = opt_float("tol_t1", 1e-10)
    tol_epsc_frac = opt_float("tol_epsc_frac", 0.8)
    tol_jc_frac = opt_float("tol_jc_frac", 0.10)
    tol_baseline = opt_float("tol_baseline", 0.05)
    tol_halves = opt_float("tol_halves", 0.20)
    tol_resid = opt_float("tol_resid", 0.05)
    tol_c1_epsc = opt_float("tol_c1_epsc", 0.01)
    assert_options_consumed("report")
    rows = read_tsv(tsv)
    isempty(rows) && error("no rows in $(tsv)")
    byid = Dict(r["id"] => r for r in rows)
    num(r, k) = parse(Float64, r[k])
    checks, failed = 0, 0
    function verdict!(ok, label, value, tol)
        checks += 1
        ok || (failed += 1)
        println("  ", ok ? "PASS" : "FAIL", "  ", rpad(label, 50), value, "   (", tol, ")")
    end
    note(msg) = println("  NOTE  ", msg)
    println("crab cavity noise, part report on ", tsv, " (", length(rows), " rows: ", join(sort(collect(keys(byid))), ", "), ")")
    println("reference rates per turn at scale 1 (relative d<J_raw>/dn): phase white x $(ref.phase_white_x); amplitude white x $(ref.amp_white_x) (y: none -- the relative strength rule leaves strengthY = 0, so the vertical response is the beam-beam coupling alone, INFO); pink/white $(ref.pink_ratio_x) (x), $(ref.pink_ratio_y) (y); scaling s^2")

    # Baselines by (kbb, chrom): B0 for the colliding runs, C0 for the linear controls.
    baseline_for(r) = num(r, "kbb_scale") == 0 && replace(r["chrom"], " " => "") in ("0,0", "(0.0,0.0)", "0.0,0.0") ? get(byid, "C0", nothing) :
                      num(r, "kbb_scale") == 1 ? get(byid, "B0", nothing) : nothing
    function rate(r, key, plane; sub = true)
        eps = EPS_DESIGN[plane]
        b = sub ? baseline_for(r) : nothing
        s = num(r, "$(key)_slope_$(plane)") - (b === nothing ? 0.0 : num(b, "$(key)_slope_$(plane)"))
        se = hypot(num(r, "$(key)_se_$(plane)"), b === nothing ? 0.0 : num(b, "$(key)_se_$(plane)"))
        return s / eps, se / eps, b !== nothing
    end
    println()
    println("rates (relative per turn, baseline-subtracted where a baseline row exists; halves and residuals from the TSV):")
    for id in [c.id for c in SWEEP_CASES if haskey(byid, c.id)]
        r = byid[id]
        rx, sx, subbed = rate(r, "jraw", :x)
        ex, _, _ = rate(r, "epsc", :x)
        ry, sy, _ = rate(r, "jraw", :y)
        ey, _, _ = rate(r, "epsc", :y)
        growth_x = num(r, "jraw_slope_x") * (num(r, "t_last") - num(r, "t_first"))
        @printf("  %-4s %-6s s=%-4s kbb=%-3s chrom=%-6s T=%-7s  J_raw x %+.3e +- %.1e  eps_c x %+.3e  J_raw y %+.3e  eps_c y %+.3e  halves x %+.3e/%+.3e  resid/growth x %.3f  J_c2/growth x %.3f  lumi %.4e trend %+.2e%s  %s ms/turn\n",
                id, r["rule"], r["scale"], r["kbb_scale"], r["chrom"], r["turns"], rx, sx, ex, ry, ey,
                num(r, "jraw_h1_x") / EPS_DESIGN.x, num(r, "jraw_h2_x") / EPS_DESIGN.x,
                growth_x == 0 ? NaN : num(r, "jraw_resid_x") / abs(growth_x), growth_x == 0 ? NaN : num(r, "jc_mean2_x") / abs(growth_x),
                num(r, "lumi_mean_fit"), num(r, "lumi_trend"), subbed ? "" : "  [no baseline row]", r["ms_per_turn"])
    end

    println()
    println("(1) rates against the reference, within a factor $(tol_rate); baseline below $(100tol_baseline) % of the s = 1 phase prediction")
    rates = Dict{Tuple{String,Symbol},Tuple{Float64,Float64}}()
    for id in keys(byid), plane in (:x, :y)
        rates[(id, plane)] = rate(byid[id], "jraw", plane)[1:2]
    end
    function within_factor(id, plane, pred, label)
        haskey(byid, id) || (note("$(id) missing: $(label) not checked"); return)
        (m, se) = rates[(id, plane)]
        verdict!(pred > 0 && 1 / tol_rate <= m / pred <= tol_rate, label,
                 @sprintf("measured %+.3e +- %.1e, predicted %.3e, ratio %.3f", m, se, pred, m / pred),
                 @sprintf("ratio within [%.2f, %.2f]", 1 / tol_rate, tol_rate))
        return m / pred
    end
    ratio_w1 = within_factor("W1", :x, ref.phase_white_x, "W1 phase white x")
    within_factor("W2", :x, 4ref.phase_white_x, "W2 phase white x (s = 2)")
    within_factor("W3", :x, 16ref.phase_white_x, "W3 phase white x (s = 4)")
    within_factor("A1", :x, ref.amp_white_x, "A1 amplitude white x")
    within_factor("A05", :x, 0.25ref.amp_white_x, "A05 amplitude white x (s = 0.5)")
    within_factor("A2", :x, 4ref.amp_white_x, "A2 amplitude white x (s = 2, 25000 turns)")
    for (id, T) in (("A4s", 12500), ("A4", 25000))
        haskey(byid, id) || continue
        r = byid[id]
        (m, se) = rates[(id, :x)]
        growth = m * (num(r, "t_last") - num(r, "t_first"))
        @printf("  INFO  %-50s measured %+.3e, predicted %.3e, ratio %.3f; halves %+.3e/%+.3e (first/second %.3f), luminosity trend %+.2e per turn; growth %.0f %% over the window: the small-growth regime's edge, decelerating (INFO; the exponent uses A05, A1, A2)\n",
                "$(id) amplitude white x (s = 4, $(T) turns)", m, 16ref.amp_white_x, m / (16ref.amp_white_x), num(r, "jraw_h1_x") / EPS_DESIGN.x, num(r, "jraw_h2_x") / EPS_DESIGN.x,
                num(r, "jraw_h1_x") / num(r, "jraw_h2_x"), num(r, "lumi_trend"), 100growth)
    end
    within_factor("T2", :x, ref.phase_white_x, "T2 phase table (seeded white) x")
    within_factor("AT1", :x, ref.amp_white_x, "AT1 amplitude table x")
    println()
    println("(1b) beam-beam-mediated vertical response (INFO; judged only through the kbb = 0 controls C1 and C2 in (6) and (7))")
    for id in ("W1", "W2", "W3", "P1", "T1", "T2")
        haskey(byid, id) || continue
        (ry, sy) = rates[(id, :y)]; (rx, sx) = rates[(id, :x)]
        q = ry / rx
        qse = abs(q) * hypot(sy / ry, sx / rx)
        @printf("  INFO  %-50s y/x = %.4f +- %.4f (y %+.3e, x %+.3e per turn)%s\n", "$(id) beam-beam-mediated vertical response (phase)", q, qse, ry, rx,
                ref.y_over_x_phase === nothing ? "   (no ref_y_over_x_phase supplied)" : @sprintf("   measured/predicted %.3f (ref %.4f)", q / ref.y_over_x_phase, ref.y_over_x_phase))
    end
    for id in ("A05", "A1", "A2", "A4s", "A4", "AP1", "AT1")
        haskey(byid, id) || continue
        (ry, sy) = rates[(id, :y)]; (rx, sx) = rates[(id, :x)]
        @printf("  INFO  %-50s y %+.3e +- %.1e, y/x = %.4f (x %+.3e): the beam-beam coupling alone -- the relative strength rule leaves strengthY = 0 (no both-planes term, 2026-10-15); judged on C2 in (7)\n",
                "$(id) beam-beam-mediated vertical response (amplitude)", ry, sy, ry / rx, rx)
    end
    if haskey(byid, "B0")
        b = byid["B0"]
        for plane in (:x, :y)
            bs = num(b, "jraw_slope_$(plane)") / EPS_DESIGN[plane]
            # Both planes against the smallest s = 1 prediction, the phase x rate: no
            # vertical prediction exists under the relative strength rule (strengthY = 0).
            pred = ref.phase_white_x
            verdict!(abs(bs) <= tol_baseline * pred, "B0 baseline J_raw slope $(plane)",
                     @sprintf("%+.3e per turn = %.3f of the s = 1 prediction %.2e", bs, abs(bs) / pred, pred),
                     @sprintf("<= %.2f of it", tol_baseline))
        end
    else
        note("B0 missing: colliding rates are not baseline-subtracted")
    end
    if ratio_w1 !== nothing
        for (f, why) in ((16 / 9, "(4/3)^2: harmonic 1 alone or the weights squared twice"), (9 / 16, "(3/4)^2"),
                         (1.06, "1/<cos^2 kz>: bunch factor dropped"), (1 / 1.06, "<cos^2 kz> applied twice"),
                         (2.0, "x2: both cavities or both harmonics on one stream"), (0.5, "x1/2: one cavity or one harmonic silent"))
            # Fires only when the ratio is closer to the alternative factor than to 1 and within 10 % of it.
            (abs(ratio_w1 - f) < abs(ratio_w1 - 1) && abs(ratio_w1 / f - 1) <= 0.1) &&
                println("  FALSIFIER  W1/prediction = $(round(ratio_w1; digits=3)) is closer to $(round(f; digits=3)) than to 1: $(why)")
        end
    end

    println()
    println("(2) exponent of rate against scale (weighted log-log fit): 2 +- $(tol_exp)")
    function exponent(ids, label)
        pts = [(parse(Float64, byid[id]["scale"]), rates[(id, :x)]...) for id in ids if haskey(byid, id)]
        pts = [p for p in pts if p[2] > 2p[3]]
        length(pts) >= 2 || (note("$(label): fewer than two resolved points (rate > 2 se)"); return)
        xs = log.(getindex.(pts, 1)); ys = log.(getindex.(pts, 2)); ws = (getindex.(pts, 2) ./ getindex.(pts, 3)) .^ 2
        W = sum(ws); xm = sum(ws .* xs) / W; ym = sum(ws .* ys) / W
        sxx = sum(ws .* (xs .- xm) .^ 2)
        p = sum(ws .* (xs .- xm) .* (ys .- ym)) / sxx
        verdict!(abs(p - 2) <= tol_exp, "$(label) exponent", @sprintf("p = %.3f +- %.3f over %d points", p, sqrt(1 / sxx), length(pts)), @sprintf("2 +- %.2f", tol_exp))
        abs(p - 2) > 0.3 && println("  FALSIFIER  $(label): no s^2 scaling (p = $(round(p; digits=3))): the rule's sigma is not what the kick sees")
    end
    exponent(["W1", "W2", "W3"], "phase white W1-W3")
    exponent(["A05", "A1", "A2"], "amplitude white A05, A1, A2 (small-growth set)")

    println()
    println("(3) pink/white rate ratios within +- $(100tol_ratio) % of rho_bar")
    function pink_ratio(pid, wid, plane, rho, label)
        (haskey(byid, pid) && haskey(byid, wid)) || (note("$(label): $(pid) or $(wid) missing"); return)
        (rp, sp) = rates[(pid, plane)]; (rw, sw) = rates[(wid, plane)]
        q = rp / rw
        qse = abs(q) * hypot(sp / rp, sw / rw)
        verdict!(abs(q / rho - 1) <= tol_ratio, label, @sprintf("%.3f +- %.3f, rho_bar %.3f, measured/predicted %.3f", q, qse, rho, q / rho),
                 @sprintf("within %.0f %% of rho_bar", 100tol_ratio))
        q > 0.8 && println("  FALSIFIER  $(label) = $(round(q; digits=3)): pink equal to white, the rule's spectrum is ignored")
    end
    pink_ratio("P1", "W1", :x, ref.pink_ratio_x, "P1/W1 phase x")
    pink_ratio("AP1", "A1", :x, ref.pink_ratio_x, "AP1/A1 amplitude x")
    if haskey(byid, "AP1") && haskey(byid, "A1")
        (rp, sp) = rates[("AP1", :y)]; (rw, sw) = rates[("A1", :y)]
        q = rp / rw
        @printf("  INFO  %-50s %.3f +- %.3f, rho_bar_y %.3f (vertical: the beam-beam coupling alone under the relative strength rule, no verdict)\n", "AP1/A1 amplitude y", q, abs(q) * hypot(sp / rp, sw / rw), ref.pink_ratio_y)
    end

    println()
    println("(4) T1 (table of W1's realised draws) reproduces W1: every moment column within $(tol_t1) relative")
    if haskey(byid, "T1") && haskey(byid, "W1")
        p1, pw = byid["T1"]["artifact_copy"], byid["W1"]["artifact_copy"]
        if isfile(p1) && isfile(pw)
            m1 = read(TaskOutput(p1), :moments; name = "weak_beam")
            mw = read(TaskOutput(pw), :moments; name = "weak_beam")
            worst, worst_col = 0.0, :none
            for col in propertynames(mw)
                # The probe group carries the scalar arc position `s` beside its columns; compare the columns.
                getproperty(mw, col) isa AbstractVector || continue
                a, b = Vector{Float64}(getproperty(mw, col)), Vector{Float64}(getproperty(m1, col))
                length(a) == length(b) || (worst = Inf; worst_col = col; break)
                d = maximum(abs.(a .- b) ./ max.(abs.(a), abs.(b), 1e-300))
                d > worst && (worst = d; worst_col = col)
            end
            verdict!(worst <= tol_t1, "T1 == W1 moment columns", @sprintf("worst relative difference %.3e in %s (bitwise equal: %s)", worst, worst_col, worst == 0), @sprintf("<= %.0e", tol_t1))
            worst > tol_t1 && println("  FALSIFIER  T1 differs from W1: the table and the white paths add different numbers")
        else
            note("T1 or W1 artifact copy missing ($(p1), $(pw))")
        end
    else
        note("T1 or W1 missing")
    end

    println()
    println("(5) beam-beam on: eps_c slope >= $(tol_epsc_frac) of the J_raw slope; J_c mean over the second half < $(100tol_jc_frac) % of the total growth; (8) halves within $(100tol_halves) % of the rate, residual rms < $(100tol_resid) % of the growth (white drives; for the pink runs these two are INFO, see (8b))")
    for id in ("W1", "W2", "W3", "P1", "T1", "T2", "A05", "A1", "A2", "AP1", "AT1", "A4s", "A4")
        haskey(byid, id) || continue
        r = byid[id]
        is_pink = r["rule"] == "pink"
        is_info = id in ("A4", "A4s")
        for plane in (id in ("A05", "A1", "A2", "A4s", "A4", "AP1", "AT1") ? (:x, :y) : (:x,))
            (rj, sj) = rates[(id, plane)]
            (re, _) = rate(r, "epsc", plane)
            growth = rj * (num(r, "t_last") - num(r, "t_first"))
            jc2 = num(r, "jc_mean2_$(plane)") / EPS_DESIGN[plane]
            h1 = num(r, "jraw_h1_$(plane)") / EPS_DESIGN[plane]; h2 = num(r, "jraw_h2_$(plane)") / EPS_DESIGN[plane]
            resid = num(r, "jraw_resid_$(plane)") / EPS_DESIGN[plane]
            # The vertical plane of an amplitude run is the beam-beam coupling alone
            # (the relative strength rule leaves strengthY = 0): no prediction, so its
            # fit-quality items are INFO; C2 judges the plane in (7).
            is_y_amp = plane === :y && id in ("A05", "A1", "A2", "A4s", "A4", "AP1", "AT1")
            if is_info || is_y_amp
                reason = is_y_amp ? "the vertical response under amplitude noise is the beam-beam coupling alone (relative strength rule, strengthY = 0, 2026-10-15): no prediction, no verdict; C2 judges the plane in (7)" :
                                    "$(r["turns"]) turns at $(round(Int, 100growth)) % growth, the regime's edge (the small-growth set A05, A1, A2 carries the verdicts)"
                @printf("  INFO  %-50s eps_c/J_raw %.3f, J_c2/growth %.3f, halves %+.3e/%+.3e (first/second %.3f, difference %.3f of the rate), residual/growth %.3f; %s\n",
                        "$(id) $(plane) fit quality", re / rj, jc2 / growth, h1, h2, h1 / h2, abs(h1 - h2) / abs(rj), resid / abs(growth), reason)
                continue
            end
            verdict!(re >= tol_epsc_frac * rj, "$(id) $(plane) eps_c slope / J_raw slope", @sprintf("%.3f (eps_c %+.3e, J_raw %+.3e)", re / rj, re, rj), @sprintf(">= %.2f", tol_epsc_frac))
            verdict!(jc2 < tol_jc_frac * growth, "$(id) $(plane) J_c second-half mean / growth", @sprintf("%.3f (J_c %.3e, growth %.3e relative)", jc2 / growth, jc2, growth), @sprintf("< %.2f", tol_jc_frac))
            if is_pink
                @printf("  INFO  %-50s %+.3e and %+.3e (difference %.3f of the rate; the white tolerance would be %.2f); residual rms / growth %.3f (white tolerance %.2f): INFO for a pink drive, see (8b)\n",
                        "$(id) $(plane) two-half slopes and residual", h1, h2, abs(h1 - h2) / abs(rj), tol_halves, resid / abs(growth), tol_resid)
            else
                verdict!(abs(h1 - h2) <= tol_halves * abs(rj), "$(id) $(plane) two-half slopes", @sprintf("%+.3e and %+.3e (difference %.3f of the rate; not baseline-subtracted)", h1, h2, abs(h1 - h2) / abs(rj)), @sprintf("difference <= %.2f of the rate", tol_halves))
                verdict!(resid <= tol_resid * abs(growth), "$(id) $(plane) residual rms / growth", @sprintf("%.3f", resid / abs(growth)), @sprintf("<= %.2f", tol_resid))
            end
        end
        if id in ("W1", "W2", "W3", "P1", "T1", "T2")
            # The vertical growth under phase noise with the strong beam ON is
            # printed as a measurement; whether the planes are as coded is
            # decided by the kbb = 0 control C1 in (6), where no beam-beam
            # coupling exists.
            (ry, _) = rates[(id, :y)]; (rx, _) = rates[(id, :x)]
            @printf("  INFO  %s vertical J_raw rate under phase noise with beam-beam on: y/x = %.4f (y %+.3e); the plane mapping is judged on C1 below\n", id, ry / rx, ry)
        end
    end

    println()
    println("(8b) single-realisation scatter of a rate proportional to the drive's band-averaged periodogram over the tune-spread band (plan: 0.35 xi wide at nu = 0.228), white against pink, and the realised drives' band power per half")
    xi = beam_beam_xi()
    bw = 0.35 * xi.x
    lo, hi = 0.228 - bw / 2, 0.228 + bw / 2
    @printf("  xi_x = %.5f, xi_y = %.5f (N_e r_p beta*/(2 pi gamma sigma (sigma_x + sigma_y))); band [%.5f, %.5f]\n", xi.x, xi.y, lo, hi)
    for T in sort(unique(parse(Int, byid[id]["turns"]) for id in ("W1", "P1", "A1", "AP1") if haskey(byid, id)))
        mc = band_scatter_mc(T ÷ 2, lo, hi)
        @printf("  half window %d turns (%d bins): sd/mean of the band average white %.4f, pink %.4f (1/sqrt(bins) %.4f) over 2000 streams; a 2-sigma two-half difference is %.3f of the rate\n",
                T ÷ 2, mc.bins, mc.white, mc.pink, 1 / sqrt(mc.bins), 2 * sqrt(2) * mc.pink)
    end
    for id in ("W1", "P1", "A1", "AP1")
        haskey(byid, id) || continue
        r = byid[id]
        q = realised_band_ratio(r, lo, hi)
        @printf("  %-4s realised drive band power half1/half2 = %.3f against the measured J_raw x half-slope ratio %.3f\n", id, q, num(r, "jraw_h1_x") / num(r, "jraw_h2_x"))
    end
    println("  the pink construction's band statistics at nu = 0.228 equal a white drive's, so no pink-specific tolerance follows from this model; where the measured half-slope ratios exceed the realised drives' band-power ratios the scatter sits in the beam's response, not in the drive, and the two-half and residual items stay INFO for the pink runs")

    println()
    println("(6) C1 linear phase control (kbb = 0, chrom 0): eps_c slope below $(100tol_c1_epsc) % of the predicted raw rate; J_raw - eps_c - J_c identity; (7) C2 linear amplitude control: the first-moment prediction in x is INFO (a single realisation without tune spread has a 100 % floor), the x verdict is part `control`'s covariance propagation, and no vertical growth beyond C0 is a verdict (the relative strength rule leaves strengthY = 0)")
    if haskey(byid, "C1")
        r = byid["C1"]
        (re, see) = rate(r, "epsc", :x)
        verdict!(abs(re) <= tol_c1_epsc * ref.phase_white_x, "C1 eps_c x slope / predicted raw rate", @sprintf("%+.3e +- %.1e = %.4f of %.2e", re, see, re / ref.phase_white_x, ref.phase_white_x), @sprintf("|.| <= %.2f", tol_c1_epsc))
        (rj, _) = rate(r, "jraw", :x)
        @printf("  INFO  C1 J_raw x rate %+.3e (one random walk: the plan's single-realisation floor is 100 %%, no verdict); J_c mean %.3e, max %.3e relative; identity max |J_raw - eps_c - J_c|/eps = %.3e (x), %.3e (y)\n",
                rj, num(r, "jc_mean_x") / EPS_DESIGN.x, num(r, "jc_max_x") / EPS_DESIGN.x, num(r, "identity_max_x"), num(r, "identity_max_y"))
        (ry1, sy1) = rate(r, "jraw", :y)
        verdict!(abs(ry1) <= 0.05 * ref.phase_white_x, "C1 no vertical growth beyond C0 under phase noise (kbb = 0): judges (1b)",
                 @sprintf("y J_raw rate %+.3e +- %.1e = %.2e of the predicted x rate", ry1, sy1, abs(ry1) / ref.phase_white_x), "<= 0.05 of it")
        abs(ry1) > 0.05 * ref.phase_white_x && println("  FALSIFIER  C1: vertical growth under phase noise without beam-beam, the planes are not as coded")
        if haskey(byid, "W1")
            (ryw, _) = rates[("W1", :y)]
            abs(ry1) <= 0.05 * ref.phase_white_x && ryw > 0.05 * ref.phase_white_x &&
                println("  INFO  W1 grows vertically under phase noise ($(ryw) per turn) while C1 does not: a beam-beam-mediated coupling, outside the linear note's \"phase y 0\"")
        end
        println("  INFO  C1 centroid against the realisation-aware linear prediction: part `control` (julia --project=. validation/crab_cavity_noise_response.jl control tsv=<this tsv>)")
    else
        note("C1 missing")
    end
    if haskey(byid, "C2")
        r = byid["C2"]
        (re, see) = rate(r, "epsc", :x)
        @printf("  INFO  %-50s %+.3e +- %.1e, first-moment prediction %.3e, ratio %.3f; halves %+.3e/%+.3e: the kick sequence is common to every particle and without tune spread does not decohere, so a rate fit has the 100 %% single-realisation floor; judged by `control` (covariance propagation, `P control tsv=<this tsv>`)\n",
                "C2 eps_c x slope vs the diffusion prediction", re, see, ref.amp_white_x, re / ref.amp_white_x, num(r, "epsc_h1_x") / EPS_DESIGN.x, num(r, "epsc_h2_x") / EPS_DESIGN.x)
        # The relative strength rule's falsifier (owner decision 2026-10-15):
        # strengthY = 0 stays exactly 0, so without beam-beam the vertical
        # emittance must not grow beyond C0 (the additive both-planes semantics
        # before it grew y at 0.87 of the x prediction, measured +1.99e-7 per
        # turn in eps_c on 2026-10-14).
        (rey, seey) = rate(r, "epsc", :y)
        verdict!(abs(rey) <= 0.05 * ref.amp_white_x, "C2 no vertical growth beyond C0 under amplitude noise (kbb = 0): judges (1b)",
                 @sprintf("y eps_c rate %+.3e +- %.1e = %.2e of the predicted x rate %.2e; halves %+.3e/%+.3e", rey, seey, abs(rey) / ref.amp_white_x, ref.amp_white_x,
                          num(r, "epsc_h1_y") / EPS_DESIGN.y, num(r, "epsc_h2_y") / EPS_DESIGN.y), "<= 0.05 of it")
        abs(rey) > 0.05 * ref.amp_white_x && println("  FALSIFIER  C2: vertical growth under horizontal amplitude noise without beam-beam -- the strength factor reached strengthY (the additive both-planes semantics predicted 0.87 of the x rate)")
        for plane in (:x, :y)
            n = parse(Float64, r["n_macro"])
            jc = num(r, "jc_mean_$(plane)") / EPS_DESIGN[plane]
            verdict!(jc <= 10 / n, "C2 $(plane) centroid action / eps (sampling: 1/N = $(1 / n))", @sprintf("%.3e", jc), "<= 10/N")
        end
    else
        note("C2 missing")
    end
    if haskey(byid, "C3")
        r = byid["C3"]
        @printf("  INFO  C3 (kbb = 0, chrom 2/2): eps_c x rate %+.3e vs J_raw %+.3e; J_c mean %.3e max %.3e relative\n",
                rate(r, "epsc", :x; sub = false)[1], rate(r, "jraw", :x; sub = false)[1], num(r, "jc_mean_x") / EPS_DESIGN.x, num(r, "jc_max_x") / EPS_DESIGN.x)
    end
    println()
    println("CRAB-NOISE-REPORT checks=$(checks) failed=$(failed) verdict=$(failed == 0 ? "PASS" : "FAIL")")
    failed == 0 || exit(1)
end

# ---------------------------------------------------------------------------
# Part `control`: the realisation-aware linear predictions of the kbb = 0
# controls -- C1's centroid (acceptance 6) and, from the same sample and maps,
# the covariance propagation that judges C2 (acceptance 7): the central 6x6
# second moments of the initial sample propagated turn by turn with the
# realised strength offsets and the linearised shipped kick (crab_cavity.jl,
# track_particle: dpx -= sx sin(theta)/(i k), dpy -= sy sin(theta)/(i k),
# dpz -= (sx x + sy y) cos(theta) with sx = s_i + Delta_i, sy = Delta_i; the
# noise part regressed on the coordinates for the sampled Gaussian z gives
# px -= d z, py -= d z, pz -= d (x + y) with d = sum_i <cos(i k z)> Delta_i, the
# symplectic map of H = d (x + y) z; the unexplained nonlinear variance is
# 0.06 % (k sigma_z = 0.25) and 0.8 % (0.50) of each harmonic's kick). A
# linear map propagates second moments exactly on any distribution, so the
# prediction follows the realisation and needs no decoherence; it is
# validated on C0 (flat) and C1/C3 (dipole drive: flat; the measured eps_c
# slopes are the model's floor and the chromatic conversion) before judging
# C2 within `tol_c2`. With kbb = 0 and chromaticity 0 every map
# the centroid meets is linear or composes to the identity (boost, zero-charge
# strong beam, unboost; the chromaticity kick at xi = 0), so the centroid
# difference between the noisy run and its baseline (same seed, same initial
# sample) is the response to the per-turn kick sequence of each cavity,
#     dpx_c(n) = -sum_i s_i [<cos(i k z)> sin(dphi_c,i(n)) + <sin(i k z)> (cos(dphi_c,i(n)) - 1)] / (i k),
# dphi being the realised phase offsets (a pure function of seed, rng_id and
# turn, regenerated through the rules' own path) and the bunch factors the
# sampled means of the initial distribution (their turn-to-turn change is
# sampling noise of order 1e-3 of themselves). The propagation follows the
# line: tccb2ip_inv, kick at tccb, tccb2ip, [IP: identity], ip2tcca, kick at
# tcca, ip2tcca_inv, one_turn; the observer at the line end records the state
# after the pass of turn n in the row labelled n. Compared in normalised
# coordinates (x/sqrt(beta*), px sqrt(beta*)): the rms deviation over the run
# relative to the rms excursion must be below `tol_centroid` (1 %).
# ---------------------------------------------------------------------------
function linear6d_matrix(; beta1, beta2, dmu)
    spec = Linear6DSpec{Float64}(; beta1, beta2, alpha1 = (0.0, 0.0, 0.0), alpha2 = (0.0, 0.0, 0.0), dmu,
                                  zeta1 = (0.0, 0.0, 0.0, 0.0), eta1 = (0.0, 0.0, 0.0, 0.0), R1 = (0.0, 0.0, 0.0, 0.0),
                                  zeta2 = (0.0, 0.0, 0.0, 0.0), eta2 = (0.0, 0.0, 0.0, 0.0), R2 = (0.0, 0.0, 0.0, 0.0))
    return Matrix(Linear6D(spec))
end

function run_control_part()
    tsv = opt("tsv", "")
    isempty(tsv) && error("control needs tsv=<sweep tsv>")
    case_id = opt("case", "C1")
    base_id = opt("baseline", "C0")
    tol = opt_float("tol_centroid", 0.01)
    cov_ids = String.(split(opt("cov_cases", "C0,C1,C3,C2"), ','))
    tol_c2 = opt_float("tol_c2", 0.10)
    tol_c2_y = opt_float("tol_c2_y", 0.05)   # the vertical verdict: |y - baseline| <= this of the propagated x slope
    n0 = opt_int("n0", N0_DEFAULT)
    assert_options_consumed("control")
    # Every other part creates its output directory; this one wrote
    # `control_<case>_centroid.tsv` into an `out=` directory it never created,
    # so a fresh `out=` crashed it after the centroid verdict and before the
    # covariance verdicts and both machine-readable lines (comprehensive audit
    # 2026-10-18, F-207). It only ever worked because `sweep` had created the
    # default directory first.
    mkpath(OUT_DIR)
    rows = read_tsv(tsv)
    byid = Dict(r["id"] => r for r in rows)
    haskey(byid, base_id) || error("the baseline row $(base_id) is needed in $(tsv)")
    ids_present = [id for id in vcat([case_id], cov_ids) if haskey(byid, id)]
    n_macro = parse(Int, byid[base_id]["n_macro"])
    all(parse(Int, byid[id]["n_macro"]) == n_macro for id in ids_present) || error("the control runs must share n_macro (the initial sample)")
    checks, failed = 0, 0
    function verdict!(ok, label, value, tolerance)
        checks += 1
        ok || (failed += 1)
        println("  ", ok ? "PASS" : "FAIL", "  ", rpad(label, 60), value, "   (", tolerance, ")")
    end
    println("crab cavity noise, part control on ", tsv, ": centroid test $(case_id) vs $(base_id); covariance test on $(join([id for id in cov_ids if haskey(byid, id)], ", ")); N = $(n_macro)")

    # The harness's initial sample (CPU storage draws the same counter-RNG
    # cells as the device): the bunch factors and the central 6x6 covariance.
    set_global_rng!(seed = SEED, method = :philox)
    beta_z = 6.0e-2 / 6.6e-4
    beam = Beam(n_macro, CPUThreadsExecutionPolicy(threads = :auto), Float64;
                beta = (BETA_X_STAR, 0.072, beta_z), alpha = (0.0, 0.0, 0.0),
                emit = ((95.0e-6)^2 / BETA_X_STAR, (8.5e-6)^2 / 0.072, 6.0e-2 * 6.6e-4),
                cutoff = 5.0, rng_id = 1, charge = 1.0, mc2 = PMASS_EV, E0 = 275.0e9,
                r0 = RE * ME0 / PMASS_EV, npart = 0.6881e11)
    coords = hcat((Vector{Float64}(getfield(beam.rep, f)) for f in (:x, :px, :y, :py, :z, :pz))...)
    Σ0 = cov(coords; corrected = false)
    z = coords[:, 5]
    kcc = 2pi * CC_FREQUENCY / CLIGHT
    bunch = [mean(cos.(i * kcc .* z)) for i in 1:2]
    sinf = [mean(sin.(i * kcc .* z)) for i in 1:2]
    sz2 = mean(abs2, z .- mean(z))
    @printf("bunch factors <cos(i k z)> = %.6f, %.6f (Gaussian exp(-(i k sigma_z)^2/2) = %.6f, %.6f); <sin(i k z)> = %+.2e, %+.2e; sample sigma_z = %.5f m\n",
            bunch[1], bunch[2], exp(-(kcc * 0.06)^2 / 2), exp(-(2kcc * 0.06)^2 / 2), sinf[1], sinf[2], sqrt(sz2))
    # The linear maps of the line, from the same Linear6DSpec constructions.
    Mb = linear6d_matrix(beta1 = (CRAB_BETA_X, 100.0, beta_z), beta2 = (BETA_X_STAR, 0.072, beta_z), dmu = (pi / 2, 0.0, 0.0))
    Ma = linear6d_matrix(beta1 = (BETA_X_STAR, 0.072, beta_z), beta2 = (CRAB_BETA_X, 100.0, beta_z), dmu = (pi / 2, 0.0, 0.0))
    Mt = linear6d_matrix(beta1 = (BETA_X_STAR, 0.072, beta_z), beta2 = (BETA_X_STAR, 0.072, beta_z),
                         dmu = (2pi * 0.228, 2pi * 0.210, 2pi * (-0.01)))
    Mb_inv, Ma_inv = inv(Mb), inv(Ma)
    # The realised values of one cavity through the rules' own path: phase
    # offsets (slots 1, 2) or RELATIVE strength factors d (slots 4, 5; the
    # cavity realises strengthX_i (1 + d), asserted here turn by turn, and its
    # strengthY_i = 0 stays exactly 0 -- relative semantics, 2026-10-15), white
    # rules at `sigma_i`.
    function realised_white(cav, kind::Symbol, sigmas, turns)
        base = RNG_ID_BASE[cav]
        if kind === :phase
            spec = ThinCrabCavitySpec{3}(CC_FREQUENCY; strengthX = CC_STRENGTH_X, strengthY = CC_STRENGTH_Y, phase = (0.0, 0.0, 0.0),
                                         phase_noise = (WhiteNoise(sigmas[1]; rng_id = base + 1), WhiteNoise(sigmas[2]; rng_id = base + 2), nothing))
        else
            spec = ThinCrabCavitySpec{3}(CC_FREQUENCY; strengthX = CC_STRENGTH_X, strengthY = CC_STRENGTH_Y, phase = (0.0, 0.0, 0.0),
                                         strength_noise = (WhiteNoise(sigmas[1]; rng_id = base + 4), WhiteNoise(sigmas[2]; rng_id = base + 5), nothing))
        end
        w = compile_runtime(spec)
        seq = [zeros(turns), zeros(turns)]
        for t in 0:turns-1
            ctx = TrackingContext(turn = t, seed = SEED, rng_method = :philox)
            u = Octopus.update(w, ctx)
            for i in 1:2
                if kind === :phase
                    seq[i][t+1] = u.inner.phase[i]
                else
                    d = Octopus._turn_offset(w.rule.strength[i], ctx, 3 + i, Float64)[1]
                    u.inner.strengthX[i] == CC_STRENGTH_X[i] * (1 + d) || error(
                        "turn $(t), $(cav) strength_noise[$(i)]: the realised strengthX is not strengthX (1 + d) for the rule's value d")
                    u.inner.strengthY[i] === 0.0 || error(
                        "turn $(t), $(cav) strength_noise[$(i)]: the realised strengthY is $(u.inner.strengthY[i]), not 0.0 -- the relative semantics did not hold")
                    seq[i][t+1] = d
                end
            end
        end
        return seq
    end
    effective(r, key) = haskey(r, key) && r[key] != "NA" ? parse(Float64, r[key]) : NaN

    # ---- the centroid test (acceptance 6) ----
    if haskey(byid, case_id)
        r1, r0 = byid[case_id], byid[base_id]
        (parse(Float64, r1["kbb_scale"]) == 0 && parse(Float64, r0["kbb_scale"]) == 0) || error("the centroid test needs kbb_scale = 0 on both runs")
        r1["rule"] == "white" || error("the centroid test regenerates WhiteNoise offsets; $(case_id) is $(r1["rule"])")
        turns = parse(Int, r1["turns"])
        phase_sigma = effective(r1, "phase_rms")
        isfinite(phase_sigma) || (phase_sigma = SIGMA_PHASE * parse(Float64, r1["scale"]))
        m1 = read(TaskOutput(r1["artifact_copy"]), :moments; name = "weak_beam")
        m0 = read(TaskOutput(r0["artifact_copy"]), :moments; name = "weak_beam")
        t1 = Vector{Float64}(m1.turn)
        t1 == Vector{Float64}(m0.turn) || error("the two runs' turn axes differ")
        dx = Vector{Float64}(m1.m100000) .- Vector{Float64}(m0.m100000)
        dpx = Vector{Float64}(m1.m010000) .- Vector{Float64}(m0.m010000)
        println()
        println("centroid test: $(case_id) against $(base_id), $(turns) turns, phase sigma $(phase_sigma) rad")
        dphi = Dict(cav => realised_white(cav, :phase, (phase_sigma, phase_sigma), turns) for cav in (:tccb, :tcca))
        kick(cav, n) = -sum(CC_STRENGTH_X[i] * (bunch[i] * sin(dphi[cav][i][n+1]) + sinf[i] * (cos(dphi[cav][i][n+1]) - 1)) / (i * kcc) for i in 1:2)
        X = zeros(6)
        x_pred, px_pred = zeros(turns), zeros(turns)
        for n in 0:turns-1
            X = Mb_inv * X
            X[2] += kick(:tccb, n)
            X = Mb * X
            X = Ma * X
            X[2] += kick(:tcca, n)
            X = Ma_inv * X
            X = Mt * X
            x_pred[n+1], px_pred[n+1] = X[1], X[2]
        end
        idx = [Int(t) + 1 for t in t1 if 0 <= t < turns]
        length(idx) == length(t1) || error("moment rows outside the run's turns")
        b = BETA_X_STAR
        meas = vcat(dx ./ sqrt(b), dpx .* sqrt(b))
        pred = vcat(x_pred[idx] ./ sqrt(b), px_pred[idx] .* sqrt(b))
        pred_shift = vcat(vcat(0.0, x_pred[idx][1:end-1]) ./ sqrt(b), vcat(0.0, px_pred[idx][1:end-1]) .* sqrt(b))
        rms_meas = sqrt(mean(abs2, meas))
        dev = sqrt(mean(abs2, meas .- pred)) / rms_meas
        dev_shift = sqrt(mean(abs2, meas .- pred_shift)) / rms_meas
        corr = cross_corr(meas, pred)
        @printf("centroid excursion rms (normalised, sqrt(m)) %.3e; predicted %.3e; rms deviation / excursion %.2e (correlation %.9f); with the prediction shifted one turn later %.4f\n",
                rms_meas, sqrt(mean(abs2, pred)), dev, corr, dev_shift)
        verdict!(dev <= tol, "$(case_id) centroid against the realisation-aware linear prediction",
                 @sprintf("rms deviation %.2e of the excursion", dev), "<= $(tol)")
        dev_shift < dev && println("  NOTE  the one-turn-shifted alignment fits better ($(round(dev_shift; digits = 5))): the observer's row convention assumed here (row n = after the pass of turn n) is then wrong")
        out_path = joinpath(OUT_DIR, "control_$(case_id)_centroid.tsv")
        open(out_path, "w") do io
            println(io, "turn\tdx_measured\tdx_predicted\tdpx_measured\tdpx_predicted")
            step = max(1, length(idx) ÷ 20000)
            for k in 1:step:length(idx)
                println(io, Int(t1[k]), '\t', dx[k], '\t', x_pred[idx[k]], '\t', dpx[k], '\t', px_pred[idx[k]])
            end
        end
        println("wrote ", out_path, " (every $(max(1, length(idx) ÷ 20000))th turn)")
        println("CRAB-NOISE-CONTROL case=$(case_id) baseline=$(base_id) deviation=$(dev) correlation=$(corr) verdict=$(dev <= tol ? "PASS" : "FAIL")")
    else
        println("  NOTE  $(case_id) missing: the centroid test is skipped")
    end

    # ---- the covariance test (acceptance 7) ----
    println()
    println("covariance test: the central 6x6 second moments of the initial sample propagated through the line's linear maps with the realised RELATIVE strength factors d_i of both cavities (S -> S (1 + d_i): dpx = -S_X,i d_i sin(i k z)/(i k), dpy = -S_Y,i d_i sin(i k z)/(i k), dpz = -(S_X,i x + S_Y,i y) d_i cos(i k z)) and the linearised shipped kick px -= dX z, py -= dY z, pz -= dX x + dY y, dX = sum_i c_i S_X,i d_i, dY = sum_i c_i S_Y,i d_i -- zero here (strengthY = 0), so the propagated eps_c y is flat and the measured one must sit at the baseline (the relative semantics' falsifier)")
    exact_var = [(1 - exp(-2 * (i * kcc)^2 * sz2)) / 2 / ((i * kcc)^2 * sz2) for i in 1:2]
    @printf("linear-kick model at k sigma_z = %.3f and %.3f: a pure linearisation (c_i = 1) overstates the kick variance by %.1f %% and %.1f %% (exact <sin^2(i k z)>/(i k)^2 over sigma_z^2 = %.4f, %.4f); with the regression coefficients c_i = <cos(i k z)> the unexplained variance is %.2f %% and %.2f %% of each harmonic's (harmonic 2 carries %.1f %% of the kick variance), %.2f %% of the summed kick\n",
            kcc * sqrt(sz2), 2kcc * sqrt(sz2), 100(1 / exact_var[1] - 1), 100(1 / exact_var[2] - 1), exact_var[1], exact_var[2],
            100(1 - bunch[1]^2 / exact_var[1]), 100(1 - bunch[2]^2 / exact_var[2]),
            100 * CC_STRENGTH_X[2]^2 / (CC_STRENGTH_X[1]^2 + CC_STRENGTH_X[2]^2),
            100 * (CC_STRENGTH_X[1]^2 * (exact_var[1] - bunch[1]^2) + CC_STRENGTH_X[2]^2 * (exact_var[2] - bunch[2]^2)) /
                (CC_STRENGTH_X[1]^2 * exact_var[1] + CC_STRENGTH_X[2]^2 * exact_var[2]))
    GX = zeros(6, 6)
    GX[2, 5] = -1.0; GX[6, 1] = -1.0      # px -= dX z, pz -= dX x
    GY = zeros(6, 6)
    GY[4, 5] = -1.0; GY[6, 3] = -1.0      # py -= dY z, pz -= dY y (dY = 0 for a horizontal cavity)
    I6 = Matrix{Float64}(I, 6, 6)
    for id in cov_ids
        haskey(byid, id) || (println("  NOTE  $(id) missing: not propagated"); continue)
        r = byid[id]
        parse(Float64, r["kbb_scale"]) == 0 || (println("  NOTE  $(id) has kbb_scale != 0: the linear propagation does not apply"); continue)
        turns = parse(Int, r["turns"])
        strength_sigma_rel = effective(r, "strength_rel_rms")
        phase_sigma = effective(r, "phase_rms")
        chrom = r["chrom"]
        has_strength = r["rule"] == "white" && isfinite(strength_sigma_rel) && strength_sigma_rel > 0
        if r["rule"] != "none" && r["rule"] != "white"
            println("  NOTE  $(id) is a $(r["rule"]) run: the test regenerates white offsets only")
            continue
        end
        dX = Dict(cav => zeros(turns) for cav in (:tccb, :tcca))
        dY = Dict(cav => zeros(turns) for cav in (:tccb, :tcca))
        if has_strength
            for cav in (:tccb, :tcca)
                # The relative factors d_i (the rule's sigma is the relative rms itself);
                # the kick change per plane is the nominal strength times d_i.
                Δ = realised_white(cav, :strength, (strength_sigma_rel, strength_sigma_rel), turns)
                dX[cav] .= bunch[1] * CC_STRENGTH_X[1] .* Δ[1] .+ bunch[2] * CC_STRENGTH_X[2] .* Δ[2]
                dY[cav] .= bunch[1] * CC_STRENGTH_Y[1] .* Δ[1] .+ bunch[2] * CC_STRENGTH_Y[2] .* Δ[2]
            end
        end
        Σ = copy(Σ0)
        ex_pred, ey_pred = zeros(turns), zeros(turns)
        for n in 1:turns
            Σ = Mb_inv * Σ * transpose(Mb_inv)
            K = I6 + dX[:tccb][n] * GX + dY[:tccb][n] * GY
            Σ = K * Σ * transpose(K)
            Σ = Mb * Σ * transpose(Mb)
            Σ = Ma * Σ * transpose(Ma)
            K = I6 + dX[:tcca][n] * GX + dY[:tcca][n] * GY
            Σ = K * Σ * transpose(K)
            Σ = Ma_inv * Σ * transpose(Ma_inv)
            Σ = Mt * Σ * transpose(Mt)
            ex_pred[n] = sqrt(max(Σ[1, 1] * Σ[2, 2] - Σ[1, 2]^2, 0.0))
            ey_pred[n] = sqrt(max(Σ[3, 3] * Σ[4, 4] - Σ[3, 4]^2, 0.0))
        end
        m = read(TaskOutput(r["artifact_copy"]), :moments; name = "weak_beam")
        t = Vector{Float64}(m.turn)
        idx = [Int(tt) + 1 for tt in t if 0 <= tt < turns]
        length(idx) == length(t) || error("moment rows outside the run's turns")
        win = findall(>=(n0), t)
        # The baseline's series for the vertical verdict (same seed, same sample, no drive).
        m_base = (has_strength && id != base_id) ? read(TaskOutput(byid[base_id]["artifact_copy"]), :moments; name = "weak_beam") : nothing
        fp_x = window_fit(t[win], ex_pred[idx][win])
        for (plane, pred) in ((:x, ex_pred), (:y, ey_pred))
            meas = plane_series(m, plane).epsc
            fm = window_fit(t[win], meas[win])
            fp = window_fit(t[win], pred[idx][win])
            eps = EPS_DESIGN[plane]
            growth = fm.slope * (t[win[end]] - t[win[1]])
            series_dev = sqrt(mean(abs2, meas[idx] .- pred[idx])) / max(abs(growth), 1e-300)
            label = "$(id) eps_c $(plane)"
            if has_strength && plane === :x
                ratio = fm.slope / fp.slope
                verdict!(abs(ratio - 1) <= tol_c2, label * " measured / propagated slope",
                         @sprintf("measured %+.3e, propagated %+.3e per turn (relative), ratio %.4f; halves measured %+.3e/%+.3e, propagated %+.3e/%+.3e; series rms deviation %.4f of the growth",
                                  fm.slope / eps, fp.slope / eps, ratio, fm.h1 / eps, fm.h2 / eps, fp.h1 / eps, fp.h2 / eps, series_dev),
                         @sprintf("|ratio - 1| <= %.2f", tol_c2))
            elseif has_strength
                # The vertical plane: dY = 0, so the propagated eps_c y is exactly flat and
                # the measured slope minus the baseline's must vanish to tol_c2_y of the
                # propagated x slope -- the relative semantics' falsifier (the additive
                # both-planes semantics before 2026-10-15 predicted 0.87 of the x rate).
                base_slope = 0.0
                base_text = "no baseline row"
                if m_base !== nothing
                    tb = Vector{Float64}(m_base.turn)
                    if tb == t
                        base_slope = window_fit(tb[win], plane_series(m_base, plane).epsc[win]).slope
                        base_text = @sprintf("baseline %s %+.3e", base_id, base_slope / eps)
                    else
                        base_text = "baseline $(base_id) has another turn axis: not subtracted"
                    end
                end
                ry = (fm.slope - base_slope) / eps
                rx_prop = fp_x.slope / EPS_DESIGN.x
                ok_y = abs(ry) <= tol_c2_y * rx_prop
                verdict!(ok_y, label * " no growth beyond the baseline (dY = 0)",
                         @sprintf("measured %+.3e, %s, difference %+.3e per turn (relative) = %.2e of the propagated x slope %+.3e; propagated y %+.3e",
                                  fm.slope / eps, base_text, ry, abs(ry) / rx_prop, rx_prop, fp.slope / eps),
                         @sprintf("|.| <= %.2f of it", tol_c2_y))
                ok_y || println("  FALSIFIER  $(id): vertical growth under horizontal amplitude noise without beam-beam -- the strength factor reached strengthY (the additive both-planes semantics before 2026-10-15 predicted 0.87 of the x rate)")
            else
                expectation = r["rule"] == "none" ? "no drive: both flat" :
                              (chrom in ("0.0,0.0", "0,0") ? "phase noise is a dipole drive: the linear model keeps eps_c flat; the measured slope is the floor the model misses (the z-dependence of the phase kick, cos(i k z) = 1 - (i k z)^2/2 + ...)" :
                                                              "phase noise with chromaticity $(chrom): the linear model without chromaticity keeps eps_c flat and does NOT reproduce the measured growth (chromatic decoherence of the centroid walk into eps_c)")
                @printf("  INFO  %-60s measured %+.3e, propagated %+.3e per turn (relative); %s\n", label, fm.slope / eps, fp.slope / eps, expectation)
            end
        end
        if has_strength
            println("  INFO  $(id): the propagation is exact for a linear kick on any distribution and needs no decoherence; a flat y (at the baseline) falsifies a strength factor that reached strengthY = 0 as the additive both-planes semantics did before 2026-10-15, an x agreement falsifies a kick model other than -S_X d sin(i k z)/(i k) with the realised relative factor d")
        end
    end
    println("CRAB-NOISE-CONTROL-COVARIANCE checks=$(checks) failed=$(failed) verdict=$(failed == 0 ? "PASS" : "FAIL")")
    failed == 0 || exit(1)
end

if PART == "noise"
    run_noise_part()
elseif PART == "tablefile"
    run_tablefile_part()
elseif PART == "pilot"
    run_pilot_part()
elseif PART == "sweep"
    run_sweep_part()
elseif PART == "control"
    run_control_part()
else
    run_report_part()
end
