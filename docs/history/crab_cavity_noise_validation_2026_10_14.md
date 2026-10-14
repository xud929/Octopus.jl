# Crab cavity noise example and validation: the first physics use of turn-by-turn modulation (2026-10-14)

Status: in progress 2026-10-14. The example, its harness, the catalogue
entry, the theory note and the validation script landed on the branch
`crab-noise-example` on top of the turn-modulation batch pushed 2026-10-13
as `6995151` (stages 1-4 of `docs/design/turn_modulation.md`; CI run 448
green); the rule checks and the sweep ran 2026-10-14 (sections 4-6: 147 of
147 rule checks; 77 acceptance items, 76 pass, the one fail explained);
the two-arm full gate ran green on the batch's commit 90a15be (section
7); the vertical coupling ratio stays measured, not derived (section 5, an
owner row). Every verdict carries its number here (never a `result/` path,
which is not evidence); a claim whose number is not in this file is not
made.

The campaign asks three questions of the turn-modulation rules on a
colliding beam -- do they generate the specified noise, what is the
beam-beam response, how do the rules compare -- at the owner's production
point: RF phase noise of rms 10 urad and relative amplitude noise of rms
1e-4 on the proton crab cavities of the EIC weak-strong case.

## 1 What landed

- `examples/crab_cavity_noise.jl`: the weak-strong EIC crab-crossing case of
  `examples/weak_strong_tracking.jl` (275 GeV protons, a 197 MHz
  two-harmonic crab with weights (4/3, -1/3, 0), half crossing angle
  12.5 mrad, crab beta 1300 m, beta* 0.8 m, tunes 0.228/0.210, a rigid
  Gaussian electron strong beam), numbers unchanged, with one input block
  added: `crab_noise` (`rule` :white, :pink, :table or :none; `phase_rms`;
  `strength_rel_rms`; `scale`; `pink_octaves`; `table_turns`; `table_seed`).
  Both proton crab cavities, `tccb` upstream and `tcca` downstream of the
  IP, carry `phase_noise` and `strength_noise` rules on their active
  harmonics with explicit stream ids. The run executes inside
  `with_execution_audit`, and the script prints the policy, the
  `:turn_modulation` execution receipt, the artifact's provenance per
  element and slot, the luminosity mean and the weak beam's first and last
  recorded rms emittances. `case_name` derives from the rule and the scale
  (`crab_noise_white_x1`), so sweeps never collide on output paths. The
  suite-sized default (2 turns, 10000 macroparticles) makes the receipt and
  the provenance authoritative and the emittance growth a measurement only
  for long runs, which the header says.
- `test/examples/crab_cavity_noise.jl`: the configurable harness of the
  same case: run size, device, the rule and its amplitudes, the
  chromaticity, a file-fed table (`OCTOPUS_TABLE_FILE`, a TSV of absolute
  per-turn offsets per slot) and two A/B toggles, the beam-beam kick
  (`OCTOPUS_KBB_SCALE`, 0 keeps the luminosity bookkeeping) and radiation
  (`OCTOPUS_RADIATION`), through `OCTOPUS_*` variables, each consumed and
  each refused outside its grammar; it ends with one machine-readable
  `CRAB-NOISE` line carrying the EFFECTIVE configuration that ran, the
  artifact path, the first and last rms emittances, the luminosity mean,
  the wall time and the ms per turn.
- `src/examples/Examples.jl`: the `ReferenceExample` catalogue entry for the
  example, naming the three questions, the harness and the study; the only
  change under `src/`. `docs/registry_snapshot.md` lists the example TYPES
  (`BenchmarkExample`, `ReferenceExample`, `ResearchStudyExample`), not the
  catalogue's entries, so the snapshot is unchanged by this batch.
- `docs/theory/crab_cavity_noise_response.md`: the kick error of a per-turn
  phase or strength offset on one harmonic of a thin crab cavity, its
  mapping to an IP offset for the upstream and the downstream cavity, the
  emittance growth of the weak beam under white and coloured sequences, the
  spectral form of the rate and the Voss-McCartney pink ratio, the
  production-point numbers (section 6, copied in section 3 below), the
  measurement plan (section 7) and the owner-facing ambiguities (section 8).
- `validation/crab_cavity_noise_response.jl`: six parts, `noise`,
  `tablefile`, `pilot`, `sweep`, `report` and `control`, with `key=value`
  overrides; its `validation/README.md` section states the reference model,
  the metrics, the tolerances, the run commands and the outputs. Every
  reference number enters `report` as an overridable argument whose default
  is the theory note's value, and no verdict uses a constant that is not
  printed.
- The suite (`test/runtests.jl`): the testset "Every example script runs
  against the current interface" now derives the clean examples from
  `example_catalog()` and the harnesses from the files under
  `test/examples/`, with tripwires: a script under `examples/` the
  catalogue does not name, or a catalogue entry whose script is missing,
  fails by name; population floors of 5 examples and 3 harnesses; one line
  printed per script; the files each run records on its `artifact = <path>`
  line are removed afterwards and anything else left under
  `result/<seed>/` fails (the leftover tripwire); the harnesses run with
  `OCTOPUS_RESULT_DIR` pointing into a temporary directory. The sibling
  testset "The developer harnesses run divided under an MPI launcher"
  derives its harness list the same way, each harness either reading
  `OCTOPUS_USE_MPI` or refusing it by name. Extracted and green on this
  tree: the example testset 21/21 (6 before; eight scripts, the new example
  220 s and its harness 238 s among them), the MPI harness testset 8/8
  (4 before). The registry snapshot is unchanged by the catalogue entry
  (regenerated and compared identical). The harness file changed during the
  sweep in presentation only (element labels, an `env_parse` helper, the
  effective-rms line), the physics and the summary line unchanged, so all
  15 sweep runs share one physics.
- Documentation: this record; `docs/README.md` (the theory note and this
  record indexed); `docs/public_api.md` ("Turn Modulation": the example,
  the theory note and the receipt-reading idiom); `docs/design/turn_modulation.md`
  (the status block's cross-reference, the section 10 open question's
  number); `docs/todo.md` (the campaign row, the turn-modulation row's
  state and owner list, two friction rows); `validation/README.md`.

## 2 Specification and interpretations

The owner's specification is an RF phase noise of rms 10 urad and a
relative amplitude noise of rms 1e-4 on the proton crab cavities, with the
white, pink and table rules under test at the same rms. The theory note's
section 8 flags the interpretations below for the owner; the example, the
harness and the validation script implement them as stated.

1. **Per-harmonic independent streams.** 10 urad applies to each active
   harmonic (1 and 2; harmonic 3 has weight 0 and stays `nothing`) of each
   cavity independently, as separate LLRF systems. The alternative is a
   common timing jitter, under which harmonic i sees i times the
   fundamental's phase noise and the two harmonics' kick errors are fully
   correlated; it gives 0.59 of the independent rate (theory note, section
   2.4; 1.01e-7 against 1.72e-7 per turn).
2. **The amplitude sigma.** The strength rule of harmonic i has the absolute
   sigma `1e-4 |strengthX[i]|`, where `strengthX = cckick .* weights` with
   `cckick = tan(12.5e-3) / sqrt(0.8 * 1300)`; `scale` multiplies both the
   phase and the strength sigma.
3. **Both cavities independent.** The stream ids are explicit: tccb uses
   10 + slot and tcca 20 + slot, slot = i for `phase_noise[i]` and 3 + i for
   `strength_noise[i]`, so 11, 12, 14, 15 and 21, 22, 24, 25; the beam
   claims 1 and the radiation element 2. The two cavities' ranges are
   disjoint because two elements sharing one id draw identical offsets
   (the task constructor warns); within one cavity the slot is part of the
   counter-RNG key, so the per-slot ids serve the record, not independence.
4. **The synthetic table record.** Under `rule = :table` a master
   `Random.Xoshiro(20261014)` hands each active slot, in construction order
   (tccb phase 1, phase 2, strength 1, strength 2, then tcca), a `UInt64`
   seed, and the slot's record is `sigma .* randn(Xoshiro(seed), table_turns)`,
   Gaussian white of the stated rms, `table_turns = 1048576` in the example
   and exactly the run's turns in the harness (the task refuses a table
   shorter than the run and never wraps one), named
   `<cavity>_<slot>_synthetic_white`; the record's FNV-1a digest, name and
   length travel in the artifact's `/turn_modulation` group. A measured
   LLRF record (phase in rad, strength in the cavity's unit, one entry per
   absolute turn) is passed the same way; the harness reads one from a TSV
   through `OCTOPUS_TABLE_FILE`, which the validation script also uses to
   feed W1's realised offsets back through the table rule (T1).
5. **The both-planes strength semantics.** A strength offset is ONE absolute
   number per turn added to both `strengthX[i]` and `strengthY[i]`
   (`?ThinCrabCavitySpec`; design decision in `docs/design/turn_modulation.md`
   section 10, taken 2026-10-12 from the note's default, owner to confirm).
   With `strengthY = 0` here the vertical plane receives a pure noise kick
   of the same absolute rms, so amplitude noise grows the vertical emittance
   at 0.87 of the horizontal predicted rate. The shipped behaviour is kept
   and measured (A1: 1.180e-6 against 1.021e-6 per turn, 1.16 of the
   horizontal, the beam-beam-mediated coupling of section 5 adding to the
   0.87); the decision is section 8's first item.
6. **The sweep's fixed points.** Radiation off (the crab noise is the only
   stochastic drive), chromaticity (2, 2) for the colliding runs and (0, 0)
   with `kbb = 0` for the linear controls, moment rows every turn, the fit
   window starting at n0 = 2000 turns, the design emittances
   eps_x = 1.128e-8 m and eps_y = 1.004e-9 m as the rates' denominators,
   the task seed 123456789 for every case.

## 3 Predictions

The theory note's section 6, copied: f_rev = 78196.75 Hz, 2.815e8 turns per
hour; rates are d<J>/dn relative to the emittance of the plane, summed over
both cavities and both active harmonics with independent streams; a scale
factor s on the rms multiplies every rate by s^2 (the small-offset regime
holds to s of order 100).

| noise | rule | plane | per turn | per hour | doubling time |
|---|---|---|---|---|---|
| phase, sigma_phi = 10 urad | white | x | 1.72e-7 | 48.5 | 51 s |
| | pink (rho_bar_x = 0.15) | x | 2.5e-8 | 7.1 | 350 s |
| | table, white record | x | as white | | |
| | any | y | 0 | | |
| amplitude, sigma_A = 1e-4 | white | x | 1.10e-6 | 309 | 8 s |
| | white | y | 9.5e-7 | 267 | 9 s |
| | pink (rho_bar) | x | 1.6e-7 | 45 | 55 s |
| | pink (rho_bar) | y | 1.6e-7 | 45 | 55 s |
| phase, common-timing alternative | white | x | 1.01e-7 | 28.5 | 87 s |

Harmonic 2 carries 1.3 % of the phase-noise rate and 5 % of the
amplitude-noise rate. The central values carry the exact bunch averages, a
1-2 % dynamic-beta correction and, for pink, a +-7 % tune-band weighting;
the note believes the predictions good to 10 % (white) and 15 % (pink),
and states that a measured rate outside [1/1.3, 1.3] times the prediction
is a defect, not a model correction. The pink ratios are rho_bar_x = 0.15
+- 0.01 and rho_bar_y = 0.17 +- 0.01, defined against the rule's ensemble
sigma (normalising by a record's sample variance inflates them by 7 %).
The statistics the plan sizes against: one moment sample's sampling noise
is sqrt(2/N) relative (1.4e-3 at N = 1e6), almost fully correlated across
turns; the floor of a single-realisation rate is the realised spectrum,
about 5 % at T = 1e5 with the strong beam on and 100 % with it off, which
is why the `kbb = 0` phase control is judged by the realisation-aware linear
prediction rather than by a rate fit. On the size of the point: a per-turn
white sequence of rms 10 urad is a one-sided PSD of 2.6e-15 rad^2/Hz flat
to 39 kHz, a very noisy LLRF; by the s^2 law the 1 %-per-hour point is
0.14 urad of per-turn-equivalent white phase noise, or an amplitude rms of
5.7e-7.

## 4 Question 1: the rules generate the specified noise

Part `noise` of the validation script realises the eight active slots
(four per cavity) the way a run does -- the example's
`ThinCrabCavitySpec{3}` compiled into a `TurnModulated`, the pure
`Octopus.update` hook on every absolute turn with a `TrackingContext(turn,
seed = 123456789, rng_method = :philox)` -- for 65536 turns per rule, and
judges, each with its number: the sample rms against sigma (white and
table within 3 sqrt(1/(2N)) = 0.83 %; pink within 23 %, three times the
construction's 7.65 % one-sigma at K = 16, with a Monte Carlo p-value
beside it), the pink cells rebuilt bitwise from the counter RNG and the
unit normality of its generator draws (mean square within 1.2 %), the mean
within three times its one-sigma, the octave-band spectrum (white and
table slope +1 +- 0.15 per octave, pink 0 +- 0.2 and the band shape against
2048 synthetic streams at the 99.9 % chi-square quantile), the pairwise
independence of the eight slots at lag 0 (|rho| <= 3 se, Bartlett's se for
pink), the strength offset equal on both planes to 4 ulp, harmonic 3 and
the base element untouched bitwise, the `scale` factor exact to 1e-12, the
table realised bitwise from its record and its digest, name and length in
the artifact provenance of a short CPU `TrackingTask` run.

**Result: 147 checks, 147 pass** (`CRAB-NOISE-RULES checks=147 failed=0
verdict=PASS`), eight slots per rule -- two cavities, phase and strength,
harmonics 1 and 2 -- with the explicit stream ids tccb 11, 12, 14, 15 and
tcca 21, 22, 24, 25, seed 123456789, Philox.

- rms: white rms/sigma within 0.83 % of 1 on every slot (3 sqrt(1/(2N)) at
  N = 65536), table likewise within 0.83 %. Pink: the verdict is taken at
  2^20 turns against the construction's own 99 % Monte Carlo band
  [0.9545, 1.0594] (4096 synthetic streams; sd 0.0194, the formula's
  0.0191): the eight slots' rms/sigma are 1.013, 0.979, 0.995, 1.030,
  1.007, 0.959, 1.024, 0.979, all inside. The 65536-turn pink values are
  recorded as information with their Monte Carlo p-values: one slot, tccb
  strength harmonic 1, sits at 1.3425 with p < 0.0005 -- its k = 14
  generator, one value per 16384 turns, drew +1.44, -2.81, +0.45, +1.88 --
  and converges to 1.188, 1.080, 1.030, 0.995 at 2^17, 2^18, 2^19, 2^20
  turns. A 3-sigma Gaussian band is the wrong shape for one pink
  realisation at 2^16 turns (the distribution's upper tail is the slow
  generators' few values), which is why the verdict moved to 2^20, where
  the slowest generator holds 64 values.
- mean: consistent with zero on every slot, white and table against
  sigma/sqrt(N), pink against its own sigma_mean = 0.25 sigma (K = 16,
  N = 2^16).
- spectrum: white and table log2-power slope per octave between +0.977 and
  +1.046 against +1 +- 0.15; pink between -0.104 and -0.003 against
  0 +- 0.2; the pink band shape against the 2048-stream Monte Carlo
  reference by chi-square over the 11 trusted bands passes on every pink
  slot.
- independence: all 28 pairs of the eight slot sequences per rule, with
  Bartlett's standard error (0.0039 for white and table, 0.058 for pink):
  worst |rho|/se 1.98 (white), 1.91 (table), 2.39 (pink), all below 3.
- both planes: the realised strengthX offset equals the strengthY offset
  within 0.5 ulp on every turn; harmonic 3 (phase and strength) and the
  base element are untouched bitwise.
- scale: rebuilding every rule at ten times sigma multiplies every realised
  sequence by exactly 10, to 1e-15.
- table: the realised sequence equals its record bitwise on every turn; the
  short CPU `TrackingTask` run's artifact provenance lists 2 elements x 4
  table slots with the records' FNV-1a digests and names, and
  `read(out, :turn_modulation)` equals `turn_modulation_provenance(path)`.

## 5 Question 2: the beam-beam response

Parts `pilot` and `sweep` run the harness as a subprocess per case on the
GPU and read the artifact's `/moments/weak_beam` into the three estimators
of the note's section 7: the raw action J_raw, the central emittance eps_c
and the centroid action J_c per plane, each fit by least squares over turns
[2000, T] after subtracting the no-noise baseline with the same seed, as
rates relative to the design emittances; the luminosity's mean and relative
trend over the same window. The receipt of every case must state the
requested configuration (rule, scale, turns, macroparticles, `kbb_scale`,
radiation, the effective sigmas, the chromaticity, a table file's digests)
or the case is an error, not a row.

| run | rule | s | kbb | chromaticity | turns | purpose |
|---|---|---|---|---|---|---|
| B0 | none | - | on | 2/2 | 1e5 | baseline: drift floor of J_raw and eps_c; mismatch transient |
| W1 W2 W3 | phase white | 1, 2, 4 | on | 2/2 | 1e5 | rate against 1.72e-7 s^2; exponent; eps_c follows J_raw; J_c bounded |
| P1 | phase pink (16 octaves) | 1 | on | 2/2 | 2^17 | pink/white against rho_bar_x |
| T1 | phase table = W1's realised offsets | 1 | on | 2/2 | 1e5 | bitwise reproduction of W1 |
| T2 | phase table = seeded white record | 1 | on | 2/2 | 1e5 | the table reproduces the white rate |
| A1 A4 | strength white | 1, 4 | on | 2/2 | 1e5, 2.5e4 | x and y rates; no centroid motion |
| AP1 | strength pink | 1 | on | 2/2 | 2^17 | pink/white in x and y |
| AT1 | strength table = seeded white record | 1 | on | 2/2 | 1e5 | the table reproduces white |
| C0 | none | - | 0 | 0/0 | 1e5 | linear baseline |
| C1 | phase white | 1 | 0 | 0/0 | 1e5 | direct term: centroid against the exact linear prediction; eps_c flat |
| C2 | strength white | 1 | 0 | 0/0 | 1e5 | direct term lands in eps_c; centroid flat |
| C3 (optional) | phase white | 1 | 0 | 2/2 | 1e5 | reversible chromatic decoherence below 7 % of J_c |

**The sweep.** 15 runs (the 14 planned and the optional C3), N = 2e5
macroparticles, T = 1e5 turns (the pink runs 2^17 = 131072, A4 25000),
radiation off, moment rows every turn, on one CUDA device shared with
another process at 96 % utilisation: at that load N = 1e6 cost 31 ms per
turn, so the plan's fallback N = 2e5 applied (sampling floor sqrt(2/N) =
3.2e-3 relative per moment sample; the pilot served this sizing and is not
otherwise quoted); 5.7 to 6.4 ms per turn, 00:51 to 04:22 EDT 2026-10-14.
Rates are the relative d<J_raw>/dn per turn from a least-squares line over
turns [2000, T], baseline-subtracted (B0 for the colliding runs, C0 for the
kbb = 0 controls); the slopes of the two halves of the window are the
scatter, in brackets.

| case | rule | x rate per turn [first half / second half] | y rate per turn | prediction (x) | measured / predicted |
|---|---|---|---|---|---|
| B0 | none | -1.3e-10 | +9.1e-10 | 0 | drift 0.001 of the s = 1 predictions |
| W1 | phase white, s = 1 | 1.764e-7 [1.901 / 1.687] | 3.61e-8 | 1.72e-7 | 1.026 |
| W2 | phase white, s = 2 | 7.119e-7 [7.640 / 6.699] | 9.1e-8 | 6.88e-7 | 1.035 |
| W3 | phase white, s = 4 | 2.817e-6 [2.933 / 2.670] | 2.04e-7 | 2.75e-6 | 1.024 |
| P1 | phase pink | 2.474e-8 [2.649 / 2.086] | 9.6e-9 | 2.5e-8 | section 6 (pink/white) |
| T1 | phase table = W1's realised draws | 1.764e-7 | as W1 | as W1 | every moment column bitwise identical to W1 |
| T2 | phase table, synthetic white record | 1.758e-7 [1.769 / 1.752] | 4.1e-8 | 1.72e-7 | 1.022 |
| A1 | amplitude white, s = 1 | 1.021e-6 [1.046 / 1.003] | 1.180e-6 [1.173 / 1.200] | 1.10e-6; y (both planes) 9.5e-7 | x 0.928; y 1.242 |
| A4 | amplitude white, s = 4, 25000 turns | 1.693e-5 [1.975 / 1.613] | 1.677e-5 | 1.76e-5; y 1.52e-5 | x 0.962; y 1.103 |
| AP1 | amplitude pink | 1.578e-7 [1.538 / 1.576] | 2.183e-7 | 1.6e-7 | section 6 (pink/white) |
| AT1 | amplitude table, synthetic white record | 1.096e-6 [1.076 / 1.116] | 1.124e-6 | 1.10e-6 | 0.997 |
| C0 | none, kbb = 0, chromaticity 0/0 | -4.2e-17 | +5.3e-17 | 0 | linear baseline |
| C1 | phase white, kbb = 0, chromaticity 0/0 | J_raw +5.19e-7 [1.15 / 10.4] (one random walk); eps_c +1.34e-9 | J_raw +4.7e-21 | linear control | below |
| C2 | amplitude white, kbb = 0, chromaticity 0/0 | J_raw +6.54e-7; eps_c +6.36e-7 | eps_c +1.99e-7 | linear control | below |
| C3 | phase white, kbb = 0, chromaticity 2/2 | J_raw +5.17e-7; eps_c +1.21e-8 | | chromatic decoherence | eps_c 0.023 of J_raw |

The relative luminosity trend per turn over the fit window: W1 -5.1e-8, A1
-4.6e-7, A4 -6.2e-6. Exponents of the rate against the scale: phase
(W1-W3) 1.996, amplitude (A1, A4) 2.026, against 2 +- 0.1. On every
colliding run eps_c/J_raw = 1.000 and the centroid's action stays below
0.002 of the growth: the growth is true emittance, decohered by the
beam-beam tune spread (acceptance 5).

**The finding.** Under purely horizontal phase noise the vertical emittance
grows: at 0.205 of the horizontal rate in W1 (3.61e-8 against 1.764e-7 per
turn), 0.128 at s = 2, 0.072 at s = 4 and 0.389 for pink, where the note's
linear treatment predicts zero. It is absent without beam-beam: C1's
vertical J_raw rate, 4.7e-21 per turn, is 2.7e-14 of the predicted
horizontal rate, no growth beyond C0. The vertical growth is therefore the
beam-beam force's x-dependence of the vertical kick acting on the
horizontal offset noise, a term the note did not carry; the same coupling
lifts the amplitude runs' vertical rate above the both-planes prediction
(+0.242 at s = 1, +0.103 at s = 4). The ratio the theory note derives for
it: the ratio's derivation is open (theory note section 4.5 and an owner
row in `docs/todo.md`; two agent attempts were lost to API timeouts); the
measured values stand as the record: 0.205, 0.128 and 0.072 at scales 1, 2
and 4, 0.389 for the pink drive, and the amplitude runs' vertical excess
+0.242 (scale 1), +0.160 and +0.103 (scale 4, two windows), +0.352 (pink),
+0.183 (table).

**Controls.** C1's centroid follows the realisation-aware linear prediction
(part `control`: rms deviation 3.1e-5 of the excursion, correlation
0.9999999996; the prediction shifted by one turn deviates by 1.31, so the
alignment is unambiguous; the bunch factors <cos(i k z)> of the sampled z
are 0.969781 and 0.884484 against the Gaussian 0.969781 and 0.884494), and
its eps_c slope is 0.0078 of the predicted raw rate (acceptance 6, the
1 % bound). C2, the strength control without beam-beam, grows eps_c in both
planes (x +6.36e-7, y +1.99e-7 per turn), so the both-planes semantics is
present in the tracked kick; its acceptance item, a first-moment ratio to
the prediction (x 0.578, y 0.210, both outside [0.8, 1.25], on which the
report's falsifier line "no vertical growth under amplitude noise" fired),
was not a valid test: without tune spread the common kick sequence does
not decohere and a single realisation carries a 100 % floor. It is being
replaced by a second-moment covariance-propagation test, which passes: the
initial sample's central 6x6 moments, propagated turn by turn with the
realised strength offsets of both cavities and the linearised shipped kick
(px -= d z, py -= d z, pz -= d (x + y), with d the bunch-averaged cosine
factor times the offset; the linearisation leaves 0.1 % of the summed kick
variance unexplained at k sigma_z = 0.25 and 0.50), reproduce C2's central
emittance growth to 1.0042 in x (measured 6.356e-7 against propagated
6.329e-7 per turn) and 1.0058 in y (1.993e-7 against 1.982e-7), the two
halves alike, the series within 0.19 % and 0.33 % of the growth; the method
was validated on C0 (flat, -4.2e-17 against -4.4e-17), on C1 (a flat
eps_c predicted; the measured +1.335e-9 is the phase kick's z-dependence)
and on C3 (the measured +1.213e-8 is chromatic decoherence, outside the
linear model). It falsifies a strength offset that does not reach
`strengthY` and any kick other than -Delta sin(ikz)/(ik) with the realised
Delta, and invokes no decoherence.

**Acceptance so far: 71 of 76 checks pass.** The five fails: P1's two
scatter items (two-half difference 0.227 of the rate against 0.20;
residual rms 0.0501 of the growth against 0.05 -- the larger
single-realisation scatter of a 1/f drive, for which a pink-specific
tolerance was derived and found unnecessary: 2000 synthetic streams give
the pink construction the same scatter of the band-averaged power at the
tune as white, 1/sqrt(bins) = 0.061 to 0.071 for the half windows, and the
realised drives' half-to-half band-power ratios (W1 1.017, P1 1.010, A1
1.138, AP1 1.099) do not track the measured half-slope ratios (1.127,
1.269, 1.043, 0.976), so the scatter sits in the beam's response; the two
pink items are recorded as information with that reason); A4's two-half difference
0.214 (deceleration at 39 % growth, the edge of the small-growth regime; a
12500-turn re-run, A4s, is not stationary either, 1.144 of the prediction
with a first-to-second-half ratio 1.282 at 21 % growth, so both A4 rows are
information at the regime's edge and the amplitude exponent is taken from
the small-growth set A05 (scale 0.5, 1e5 turns, 2.5 % growth: x 2.535e-7
per turn, 0.922 of the s^2-scaled 2.75e-7; y 3.135e-7, 1.320 of the
both-planes 2.375e-7), A1 and A2 (scale 2, 25000 turns, 10 % growth: x
4.248e-6, 0.965 of 4.40e-6; y 4.368e-6, 1.150 of 3.80e-6): exponent 2.017,
within 2 +- 0.1, the three points scattering by 4 % about s^2); and C2's two items (above). Final
count: 77 checks, 76 pass, 1 fail, A2's two-half difference 0.215 of the
rate against 0.20: the amplitude-noise response under beam-beam
decelerates early (first-to-second-half ratios 1.23 at 25000 turns, 1.22
and 1.28 for A4 and A4s, against 1.04 over A1's 1e5 turns, with the
drives' band power steady), a physics observation of the early-time
response rather than a drive or fit artefact; the phase runs' halves run
1.10 to 1.14, inside the band.

## 6 Question 3: the rules compared

At equal rms the three rules differ only in spectrum: white and a white
table record must give the same rate, and the pink rule, whose power sits
below the betatron sidebands, 0.15 (x) and 0.17 (y) of it. Part `report`
judges P1/W1 and AP1/A1 within 25 % of those ratios, T1's moment columns
equal to W1's to 1e-10 relative on every column (bitwise expected; the
tolerance covers reduction order), T2 and AT1 within a factor 1.25 of the
white prediction, and prints the falsifiers by name when they trigger (no
s^2 scaling; pink equal to white; W1 off by (4/3)^2, by 1/<cos^2 kz> or
by 2; T1 differing from W1; vertical growth under phase noise; none under
amplitude noise).

**Result.** At equal rms, pink/white = 0.140 in x for phase noise (P1/W1;
0.935 of the predicted rho_bar_x = 0.15, inside the 25 % tolerance) and
0.155 for amplitude noise (AP1/A1 in x; 1.030 of 0.15); the vertical AP1/A1
is 0.185 against rho_bar_y = 0.17 (information, not a verdict: the vertical
rates include the beam-beam-mediated coupling of section 5). Table against
white: T2/W1 = 0.997 (a synthetic white record reproduces the white rule's
rate); T1 equals W1 bitwise on every moment column (the table rule, fed the
white rule's realised draws through the harness's `OCTOPUS_TABLE_FILE`,
reproduces the white run exactly, and the file's column digests are the
ones T1's provenance records); AT1/A1 = 1.073 in x and 0.953 in y. The
spectrum, not the rms, sets the response: pink's 0.14 to 0.15 is the
Voss-McCartney power at the betatron tune relative to white's, as the
note's section 5 derives. Falsifiers: none of "no s^2 scaling" (exponents
1.996 and 2.026), "pink equal to white" (0.140), "W1 off by (4/3)^2, by
1/<cos^2 kz> or by 2" (1.026) or "T1 differing from W1" (bitwise equal)
triggered; "vertical growth under phase noise" is judged on the linear
control C1, where there is none (2.7e-14 of the horizontal prediction), and
W1's vertical growth with beam-beam on is reported beside it as the finding
of section 5; the C2 falsifier line is the invalid first-moment item of
section 5 (`CRAB-NOISE-REPORT checks=76 failed=5 verdict=FAIL` at this
stage; the line after the re-runs is section 5's final count).

## 7 Verification

The matrix classes this batch touches, read from the diff: examples (the
script runs; the catalogue entry; the full gate, example execution being
full-lane only); validation (the script reproduces; this record committed;
the full gate before the commit carrying the claim); docs plus anything
else (the full gate). The only change under `src/` is the catalogue entry
in `src/examples/Examples.jl`: no kernel, `compile_runtime`, policy or
contract changed, so the CUDA, concurrency and backend-consistency rows
are not triggered by this batch; the sweep's GPU runs are measurements
recorded in section 5, not a gate requirement, and the registry snapshot is
unchanged (section 1). Targeted checks before the gate: the example at its
default size on CPU and, where a device is functional, on CUDA; the
harness's default run; part `noise`; the index walk of `docs/README.md`.

The full gate ran on the committed tree 90a15be (working tree clean, the
HEAD recorded in each log header) in both CPU arms, CUDA active, four
threads, one arm after the other on the same host, the GPU shared with
another user's process throughout:

| arm | start to end, EDT, 2026-10-14 | rows | assertions | exit |
|---|---|---|---|---|
| native | 05:42:37 to 08:06:16 | 332 | 149349 of 149349 | 0 |
| AVX2 (OpenBLAS Haswell kernels, LLVM target haswell) | 08:06:16 to 10:12:14 | 332 | 149349 of 149349 | 0 |

```bash
julia --project=. --threads=4 -e 'using Pkg; Pkg.test(julia_args=["--threads=4"])'
OPENBLAS_CORETYPE=Haswell julia -C haswell --project=. --threads=4 \
  -e 'using Pkg; Pkg.test(julia_args=["--threads=4", "-C", "haswell"])'
```

Both arms end in "Testing Octopus tests passed"; no summary row carries a
Fail, Error or Broken column; the sorted row sets of the two arms are
identical; nothing was skipped; CUDA was active, 36 rows per arm naming it.
Against the stages 3-4 gate on b99f6b7 (332 rows, 149326 assertions) the
row count is unchanged and 23 assertions were added: "Every example script
runs against the current interface" 21/21 (was 6/6; 32 min on the native
arm, 35 on the AVX2 arm; the eight scripts each exit 0, the new example in
281 s and its harness in 242 s on the native arm), "The developer harnesses
run divided under an MPI launcher" 8/8 (was 4/4), and the catalogue testset
with the new entry. The turn-modulation rows are unchanged from the stages
3-4 gate (effectiveness 57/57, rules 321/321, slot bounds 25/25, spectra
44/44, RF cavity 140/140, artifact 127/127, strong-strong window 20/20,
CPU/CUDA identity 39/39). Checks before the gate: the extracted sweeps
(exit 0) and a fast lane (exit 0, 316 rows, 147178/147178, the fifteen
standard loud skips) on the tree one docs step earlier, and "Architecture
integrity" 28/28 on the final docs. Not verified: CI on this tree, which is
not pushed at the time of writing. Added after the push: pushed 2026-10-14 as
20bbfaa (this record's commit on top of 90a15be); CI run 449 on it
completed green (runner znver4, 31 min, the usual stage 6 identity-pin
notices). The suite rows this batch changes, "Every example script runs
against the current interface" (21/21, its list derived from the
catalogue) and "The developer harnesses run divided under an MPI
launcher" (8/8), ran extracted and green (section 1); with
`test/runtests.jl` in the diff the test-infrastructure class applies as
well, so the fast lane's skip banner is checked at the gate.

## 8 Owner items and ledger

Owner decisions this campaign raises or sharpens (the theory note's section
8; the turn-modulation row of `docs/todo.md` carries the first with its
number):

1. **The both-planes strength semantics.** The strength rule adds one
   absolute offset to both planes' strengths of its harmonic, so a
   horizontal crab cavity with amplitude noise kicks vertically and the
   vertical emittance grows at 0.87 of the horizontal predicted rate
   (9.5e-7 against 1.10e-6 per turn at the production point); a physical
   voltage error scales both planes proportionally and would give no
   vertical noise here. Alternative: a relative (multiplicative) scaling
   per harmonic. Measured under the shipped semantics (section 5): A1's
   vertical rate 1.180e-6 per turn against the both-planes prediction
   9.5e-7 (1.242; the excess is the beam-beam-mediated coupling of the
   finding), A4 1.677e-5 against 1.52e-5 (1.103), AT1 1.124e-6, and C2
   without beam-beam 1.99e-7 in eps_c: the vertical kick is present as
   coded. Under a relative scaling the vertical plane would receive
   nothing here and these rates would vanish, so the decision changes a
   measured response, not only a convention.
2. **Per-harmonic independent streams versus common timing.** Adopted:
   independent, 10 urad on each active harmonic of each cavity; common
   timing gives 0.59 of the phase-noise rate.
3. **The production point is loud.** Doubling times of a minute (phase)
   and eight seconds (amplitude): a fine test point, where 1e5 turns give
   2-11 % growth, not an LLRF specification; the 1 %/h-equivalent per-turn
   rms is 0.14 urad / 5.7e-7.
4. **The beam-beam-mediated change of the raw rate is 1-2 %**, below the
   planned statistics; what the `kbb = 0` controls show is the decoherence
   (central against raw emittance), not a beam-beam enhancement.
5. **Pink scatter tolerances.** The report's fit-quality items, a two-half
   slope difference within 0.20 of the rate and a residual rms within 0.05
   of the growth, were set for a white drive; P1 fails both narrowly
   (0.227, 0.0501) because a 1/f drive's single-realisation spectral
   scatter was suspected to be larger. The derivation (section 5) found
   the pink construction's band-power scatter equal to white's and the
   measured half-slope ratios uncorrelated with the drives' band power, so
   the scatter sits in the beam's response and no pink-specific tolerance
   follows; the two items are information rows, not a defect of the rule
   (P1's rate is 0.935 of its prediction). Open for the owner: whether the
   fit-quality items should be verdicts at all for a single realisation.
6. **The C2 test design.** The linear amplitude control's first-moment
   acceptance, the ratio of the eps_c rate to the prediction, assumed a
   decoherence that a kbb = 0, chromaticity-0 line does not provide; the
   replacement propagates the second moments through the linear maps under
   the realised kick sequence and compares the covariance turn by turn;
   it landed in part `control` and passes on C2 to 1.0042 (x) and 1.0058
   (y) after validation on C0, C1 and C3 (section 5). Nothing remains open
   here; the first-moment numbers stay in the report as information.

Ledger rows added to `docs/todo.md` on 2026-10-14, from the example
implementer's friction list:

- The `:turn_modulation` receipt and the artifact provenance name an
  element by its type only (`ThinCrabCavity (beam 1)` twice for the two
  cavities; the artifact's subgroup index is the only position, the receipt
  has none), so the example hand-numbers stream ids per cavity and names its
  tables by cavity to tell them apart.
- `rng_id = 0` takes the next id from a process-global counter, so the
  provenance of a run depends on construction order; the example and the
  harness hand-number every id (tccb 10 + slot, tcca 20 + slot).
- An explicit `rng_id` colliding with an earlier fresh id is undetected:
  `claim_rng_id!` only raises the auto-assign counter past an explicit id,
  so a fresh consumer built first with id k and an explicit `rng_id = k`
  chosen afterwards share a stream silently (its docstring says so); the
  example's hand-numbering sidesteps it.

Ledger changes in the same batch: the turn-modulation row's state cell
records the push of stages 3-4 (6995151, CI run 448 green) and its owner
list gains item 1 above; the campaign row "Crab cavity noise example and
validation" records the sweep's results (71 of 76, the five explained)
with the final acceptance as its next step; the deliverables paragraph of
`docs/design/twiss_dispersion_analysis.md` now says the DBA-ring example is
catalogued and the suite derives its list from the catalogue (its
"example runner list" wording was stale). No entry in
`docs/experiences.md` yet: a lesson lands there when the sweep teaches one.
