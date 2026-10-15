# Crab cavity amplitude noise as a relative factor on both planes: the strength rule's semantics change (2026-10-15)

Status: in progress 2026-10-15, stage 0 of
[`../design/turn_modulation_record.md`](../design/turn_modulation_record.md)
(section 7). The owner decided the semantics on 2026-10-15 (section 1); the
implementation (section 2, landed 2026-10-15), the re-validation of the
amplitude arms (section 3, run 2026-10-15) and the gate (section
5, both arms green 2026-10-15 after one crashed native attempt) are this
batch's and carry their numbers. This record corrects the frozen
[`crab_cavity_noise_validation_2026_10_14.md`](crab_cavity_noise_validation_2026_10_14.md)
where that record described the superseded semantics (section 4); the
frozen record itself is not edited. Every verdict carries its number here; a
`result/` path is not evidence and none is cited as one.

## 1 The decision and its reasoning

One voltage driver excites a cavity's horizontal and vertical kick, so one
relative amplitude error `d` scales both, `S_X (1 + d)` and `S_Y (1 + d)`; a
second driver is a second cavity. The strength rule (`strength_noise`, per
harmonic on the crab cavity, scalar on the RF cavity) therefore realises a
dimensionless relative factor, and the RF cavity's voltage follows the same
convention, `V (1 + d)`. Decided by the owner on 2026-10-15
(`../design/turn_modulation_record.md`, section 5 and section 8 item 3;
`../design/turn_modulation.md`, section 10).

**What it replaces.** The shipped additive semantics, one absolute offset in
the strengths' unit added to both `strengthX[i]` and `strengthY[i]`, was the
2026-10-12 default taken in the owner's absence (the stage 1 record; the
turn-modulation row of `docs/todo.md`). It made a horizontal cavity
(`strengthY = 0`) kick vertically: the theory note
(`../theory/crab_cavity_noise_response.md`, section 3.2 as it then read)
predicted vertical emittance growth at 0.865 of the horizontal rate under
amplitude noise (9.5e-7 against 1.10e-6 per turn at the production point,
relative rms 1e-4), and the 2026-10-14 sweep measured 1.16 (A1: y 1.180e-6
against x 1.021e-6 per turn), the beam-beam coupling of the note's section
4.5 adding to the 0.865.

**What changes and what does not.** Under the relative semantics the
horizontal physics is unchanged: the absolute horizontal kick error is
`S_X d`, the same number as before for the same relative rms (the example's
harmonic 1, `S_X = 5.1684e-4` per m at 1e-4 relative: 5.168e-8 per m under
either convention), so the horizontal predictions of the theory note's
section 6 stand. The vertical kick of a horizontal cavity is zero, so
whatever vertical growth the colliding amplitude runs show is the beam-beam
coupling alone. The falsifier is vertical emittance growth under horizontal
amplitude noise WITHOUT beam-beam. For users: the rule's `sigma` is now the
relative rms itself (the example hands `strength_rel_rms = 1e-4`, times
`scale`, over directly instead of multiplying by `|strengthX[i]|`); a
strength `TurnTable` holds relative factors, and a table produced for the
additive convention is wrong by the nominal strength. In the recording
design the recorded offset of a strength slot is dimensionless and the
reader forms `S (1 + d)` from the stored nominal
(`../design/turn_modulation_record.md`, D3 and D7).

**The realised sequences change, the statistics do not.** The draw `n` of a
slot is a pure function of (seed, `rng_id`, slot, turn) and is unchanged.
Under the old semantics the harmonic-`i` offset was `1e-4 |S_X[i]| n`; under
the new one it is `S_X[i] 1e-4 n`. The example's harmonic 2 has a negative
nominal (weight -1/3, `S_X[2] = -1.2921e-4` per m), so its kick sequence
changes sign, and the products round differently in the last bits on both
harmonics. The amplitude re-runs are therefore new realisations of the same
ensemble, not bitwise repeats of the 2026-10-14 runs: the horizontal rates
are expected equal within the single-realisation scatter, not bitwise.

## 2 What changed

Landed 2026-10-15: 459 lines added and 214 removed over seven files (the
two cavity sources, the wrapper's prose, the suite, the example, the
harness, the validation script); every testset title unchanged.

- `src/elements/crab_cavity.jl`: `realize(::CrabCavityNoise, ...)` forms
  `strengthX[i] * (1 + d_i)` and `strengthY[i] * (1 + d_i)` from the one
  realised factor per active harmonic instead of adding the offset to both;
  the `ParamMeta` of `strength_noise` (meaning: a dimensionless relative
  factor on both planes); the docstrings of the spec and the container.
  Landed as `strengthX[a] * (one(T) + d_a)` and `strengthY[b] * (one(T) +
  d_b)`, the phase additive and unchanged, the hook pure and
  type-preserving with its `(element, successor)` return; the `ParamMeta`
  meaning says relative, dimensionless, both planes, one driver, while its
  unit field keeps the vocabulary's dimensionless spelling, the empty
  string, since `ALLOWED_PARAM_UNITS` admits only it, `m`, `rad` and `Hz`;
  the spec docstring, the construction help and the container, `realize`
  and wrap docstrings reworded; in `turn_modulated.jl` the header's D7
  line, the rule docstrings and the `TurnTable` docstring (relative
  factors on a strength slot, radians on a phase slot).
- `src/elements/rf_cavity.jl`: `realize(::RFCavityNoise, ...)` forms
  `strength * (1 + d)`; the `ParamMeta` of its `strength_noise`. Landed as
  `base.strength * (one(T) + dstrength)` with the spec docstring, meaning,
  construction help and docstrings reworded.
- Tests: nine assertions in four testsets went red on the new source for
  the semantics reason (for instance `0.001999876 == 0.001938148`) and were
  re-pinned with the formula stated beside each: the rules testset
  (`2e-3 (1 + d5)` and `1e-3 (1 + d5)` for the both-planes fixture, the
  old additive pin asserted false), "Turn modulation: slot bounds and labels
  at the wrap" (`strengthX[32] (1 + d64)` and `strengthY[32] === 0.0`),
  the spectra testset's part (h) (`S (1 + d)`, `strengthY[1] === 0.0`) and
  "Turn modulation: the RF cavity by the same wrap" part (b)
  (`V (1 + 1e-7 draw)`, the additive pin asserted false). New assertions: a
  `ThinCrabCavitySpec{3}` with `strengthX = (2e-3, 0, 0)` and a white rule
  on harmonic 1 realises `strengthY[1] === 0.0` on turns 0 to 7 and
  `strengthX[1] == 2e-3 (1 + d)` with `d` the hook's draw, harmonics 2 and
  3 bitwise untouched; a fixture with both planes non-zero scales both by
  the same factor; the RF cavity realises `V (1 + d)` on turns 0 to 3; a
  zero strength table leaves the strengths bitwise unchanged and a table
  holding 0.5 scales by exactly 1.5 on both cavities. Green extracted on the
  CPU: rules 358/358, slot bounds 26/26, spectra 45/45, RF 141 pass with
  one pre-existing broken, kernel-boundary effectiveness 57/57, artifact
  provenance 127/127, strong-strong window 20/20.
- `examples/crab_cavity_noise.jl` and `test/examples/crab_cavity_noise.jl`:
  the strength rules take `strength_rel_rms * scale` directly (no
  multiplication by `|strengthX[i]|`); the synthetic table records of the
  strength slots are relative factors; the summary line and the receipt
  report the relative sigma. Landed: sigma is `strength_rel_rms * scale`;
  the headers and comments state the relative scaling and the one-driver
  reasoning in one sentence; the harness header says
  `OCTOPUS_STRENGTH_REL_RMS` is the rule's sigma directly, that the strength
  columns of `OCTOPUS_TABLE_FILE` hold relative factors, and that the
  CRAB-NOISE line's `strength_rel_rms=` field is the sigma that ran.
- `validation/crab_cavity_noise_response.jl`: part `noise` judges the
  strength slots' rms against `sigma = 1e-4 * scale` and replaces "the
  strengthX offset equals the strengthY offset" by "both planes carry the
  same factor, and `strengthY` stays 0 on a horizontal cavity"; part
  `control`'s covariance propagation applies the linearised kick with the
  relative factor (`px -= S_X d z`, `py -= S_Y d z`, zero here,
  `pz -= d (S_X x + S_Y y)`); part `report`'s amplitude predictions carry no
  vertical rate (the coupling only), its falsifier line reads "vertical
  growth under horizontal amplitude noise without the strong beam", and the
  horizontal items are unchanged. Landed (352 lines changed): part `noise`
  sets the strength sigma to the relative rms, recovers the factor
  `(strengthX - S)/S` for the statistics while the bitwise pink and table
  items use the rules' own values, and adds an `exact` verdict per cavity
  (phase equals nominal plus `d`, `strengthX == S (1 + d)`, `strengthY ===
  0.0`, bitwise on every turn at scale 1 and 10) with a recovered-against-
  value tolerance of 4 ulp; part `tablefile` writes the rules' exact values
  and asserts the planes; part `control` propagates `dX = sum_i c_i S_X,i
  d_i` and `dY = sum_i c_i S_Y,i d_i` (zero here) and adds the vertical
  verdict `|y - baseline| <= 0.05` of the propagated horizontal slope with
  the falsifier line; part `report` retires `ref_amp_white_y` (passing it
  errors), prints the amplitude vertical rows as the beam-beam coupling
  only, judges B0's vertical baseline against the phase prediction, makes
  the amplitude runs' vertical fit-quality items information, and judges C2
  by `|eps_c y rate| <= 0.05 x 1.10e-6` with the falsifier "vertical growth
  under horizontal amplitude noise without beam-beam"; the horizontal
  reference 1.10e-6 is unchanged. On the CPU the noise part passes 157 of
  157 checks with the strength slots at sigma = 1e-4: white rms/sigma
  1.00139, 1.00352, 0.99885, 0.99797 (band 0.83 %); pink over 2^20 turns
  0.99473, 1.02968, 1.02395, 0.97918 (band [0.9545, 1.0594]); table
  0.99562, 1.00530, 1.00281, 0.99764; the exact verdicts pass for every rule
  and cavity; scale-10 linearity within 1e-12. Run on the 2026-10-14
  additive data the new C2 vertical verdict fails and its falsifier fires
  (`y = 1.993e-7`, 0.18 of 1.10e-6), so the check can fail.
- Documents, this batch: the theory note (sections 1, 3.1, 3.2, 4.5, 6, 7
  and 8 item 2), `design/turn_modulation.md` (status, D7, 4.1, 5.6, 10),
  `design/turn_modulation_record.md` (status), `public_api.md` ("Turn
  Modulation"), `README.md`, `todo.md`, this record.
- `docs/registry_snapshot.md`: expected unchanged; at b3a06b1 it carries no
  `strength_noise` text (0 matches), so the metadata rewording does not
  reach it. Confirmed on the final source: the generated snapshot equals
  the tracked file; nothing written.

## 3 Re-validation (run 2026-10-15)

The amplitude arms of the 2026-10-14 sweep and the covariance control re-run
on the GPU under the relative semantics with the same seeds (task seed
123456789), stream ids (strength slots tccb 14, 15 and tcca 24, 25), fit
window [2000, T] and baselines (B0 for the colliding runs, C0 for the
control): A05 (scale 0.5, 1e5 turns), A1 (1, 1e5), A2 (2, 25000), A4 (4,
25000), A4s (4, 12500), AP1 (pink, 2^17), AT1 (table, 1e5), C2 (kbb = 0,
chromaticity 0/0, 1e5) and part `control`'s covariance propagation on C2;
part `noise` for the strength slots. About an hour on the GPU at the
2026-10-14 per-turn costs (5.7 to 6.4 ms per turn at N = 2e5).

Expectations, each beside the 2026-10-14 numbers in brackets:

| arm | horizontal rate per turn: expected unchanged within the two-half scatter [2026-10-14 measured; prediction; ratio] | vertical rate per turn: expected the beam-beam coupling only [2026-10-14 measured under the additive semantics; its then prediction] |
|---|---|---|
| A05 | [2.535e-7; 2.75e-7; 0.922] | [3.135e-7; 2.375e-7] |
| A1 | [1.021e-6, halves 1.046 / 1.003; 1.10e-6; 0.928] | [1.180e-6, halves 1.173 / 1.200; 9.5e-7] |
| A2 | [4.248e-6; 4.40e-6; 0.965] | [4.368e-6; 3.80e-6] |
| A4 | [1.693e-5, halves 1.975 / 1.613; 1.76e-5; 0.962] | [1.677e-5; 1.52e-5] |
| A4s | [1.144 of the prediction, first-to-second-half ratio 1.282] | [not separately recorded] |
| AP1 | [1.578e-7, halves 1.538 / 1.576; 1.6e-7; AP1/A1 = 0.155 against 0.15] | [2.183e-7; AP1/A1 = 0.185 against 0.17] |
| AT1 | [1.096e-6, halves 1.076 / 1.116; 1.10e-6; 0.997] | [1.124e-6; AT1/A1 = 0.953] |
| C2 | eps_c [+6.36e-7; covariance propagation 6.329e-7; 1.0042] | eps_c expected at the C0 baseline (C0: J_raw +5.3e-17 per turn) [+1.99e-7; propagation 1.982e-7; 1.0058] |

Further expectations:

- The amplitude exponent from A05, A1 and A2 stays 2 within +-0.1 [2.017].
- Part `noise`: the strength slots' rms/sigma within 0.83 % of 1 against
  sigma = 1e-4 (white and table; 3 sqrt(1/(2N)) at N = 65536), the pink
  slots inside the 2^20-turn band [0.9545, 1.0594]; the realised
  `strengthX[i]` equals `S_X[i] (1 + d)` and `strengthY[i]` stays 0 bitwise
  on every turn of both cavities; harmonic 3 and the base element untouched
  bitwise; `scale` exact.
- The phase arms (W1, W2, W3, P1, T1, T2, C1, C3) are untouched by the
  change and are not re-run; their 2026-10-14 numbers stand, including the
  vertical coupling ratio 0.205 under W1.
- Verdicts: a horizontal rate outside its 2026-10-14 two-half scatter is a
  defect of the implementation (the absolute horizontal error is unchanged
  by construction); a C2 vertical eps_c growth above the C0 baseline is the
  falsifier of section 1; the colliding runs' vertical rates are recorded as
  the measured coupling under amplitude noise, the first such measurement
  free of the additive kick.

Run 2026-10-15, 13:10 to 14:42 EDT, on the RTX 4500 Ada (shared: another
process held 11.9 GB idle; utilisation 87 to 94 % during the arms, 0 %
before and after), N = 2e5, radiation off, 5.84 to 7.30 ms per turn, host
load 3.8 at launch, the cases B0, A05, A1, A2, A4, A4s, AP1, AT1, C0 and
C2 (91 min). B0 and C0 reproduce their 2026-10-14 artifacts bitwise (the
moments and luminosity groups identical), which licenses reusing the phase
arms' 2026-10-14 rows beside the new ones.

Measured (relative per-turn rates of J_raw, baseline-subtracted; halves not
subtracted; the 2026-10-14 value in brackets):

| arm | horizontal | vertical |
|---|---|---|
| A05 | 2.500e-7 [halves 2.533 / 2.595] (2.535e-7); 0.909 of 2.75e-7 | 7.41e-8 [7.52 / 7.55] (3.135e-7); 0.97 of the former excess 7.6e-8 |
| A1 | 1.030e-6 [1.030 / 1.020] (1.021e-6); 0.936 of 1.10e-6 | 1.930e-7 [1.897 / 1.936] (1.180e-6); 0.84 of 2.3e-7 |
| A2 | 4.182e-6 [4.569 / 4.173] (4.248e-6); 0.950 of 4.40e-6 | 3.565e-7 [4.079 / 3.410] (4.368e-6); 0.63 of 5.7e-7 |
| A4 | 1.675e-5 [1.816 / 1.682] (1.693e-5); 0.951; information, 39 % growth | 7.34e-7 (1.677e-5) |
| A4s | 1.837e-5 [1.868 / 1.770] (2.014e-5); 1.044; information, 19 % growth | 6.75e-7 (1.763e-5) |
| AP1 | 1.545e-7 [1.454 / 1.485] (1.578e-7); AP1/A1 = 0.150, 1.000 of rho_bar 0.15 | 4.76e-8 (2.183e-7); AP1/A1 0.247, information |
| AT1 | 1.085e-6 [1.098 / 1.093] (1.096e-6); 0.987; AT1/A1 1.054 | 1.76e-7 (1.124e-6) |
| C2 | eps_c +3.402e-7 [8.77e-8 / 6.80e-7] against the propagated 3.383e-7, ratio 1.0057, series rms deviation 0.0034 of the growth (6.356e-7: a new realisation, since harmonic 2's kick sequence changes sign under the relative convention, and one realisation carries the 100 % floor) | eps_c +5.341e-17, exactly C0's +5.341e-17; difference -1.07e-21, 3.2e-15 of the propagated horizontal slope and 9.7e-16 of 1.10e-6 against the 0.05 tolerance (1.993e-7) |

Verdicts: the horizontal rates changed by -1.4, +0.8, -1.6, -2.1 and
-1.0 % (A05, A1, A2, AP1, AT1), inside the 2026-10-14 two-half spreads
(0.07 to 0.86 of them) and the 2-sigma single-realisation band, so they are
unchanged as construction requires; the new halves are tighter (0.5 to
2.5 % of the rate for A05, A1 and AT1) and A2's two-half difference is
0.095 of the rate (the one 2026-10-14 fail, at 0.215, passes); the
exponent over A05, A1 and A2 is 2.038 (2.017), within 2 +- 0.1; the
vertical rates with the strong beam are the beam-beam coupling alone, 0.97,
0.84 and 0.63 of the former excesses, with y/x = 0.296, 0.187 and 0.085
falling with the scale like the phase arms' 0.205, 0.128 and 0.072; the
beam-beam-off control's vertical emittance is identical to the no-noise
baseline, so the falsifier of section 1 did not fire. The report passes 29
of 29 checks on the ten re-run cases and 60 of 60 with the phase arms'
2026-10-14 rows merged (the same report on the 2026-10-14 additive data:
60 checks, 2 fails, as it must); the control passes (C1 centroid 3.12e-5,
covariance 3 of 3); the noise part passes 157 of 157, with the strength
slots at sigma = 1e-4: white rms/sigma 1.00139, 1.00352, 0.99885, 0.99797;
pink over 2^20 turns 0.99473, 1.02968, 1.02395, 0.97918 inside [0.9545,
1.0594]; table 0.99562, 1.00530, 1.00281, 0.99764; `strengthX == S (1 + d)`
and `strengthY === 0.0` bitwise on every turn at scale 1 and 10 under
white, pink and table; the recovered factor within 0.97 ulp of the rule's
value. One diagnostic defect surfaced: the report's realised-drive
band-power line (item 8b) still built its strength rules with the absolute
convention and read the vertical strength, which the relative semantics
keeps at zero, so it printed NaN; fixed after the run (the rules at the
relative sigma, the factor recovered from the horizontal plane, the band
weights carrying `S_X,i^2`) and the report re-run on the same data: A1's
realised drive band power half1/half2 = 1.138 against the measured
half-slope ratio 1.009, AP1's 1.099 against 0.979, every verdict and total
unchanged (29 of 29; 60 of 60).

## 4 Corrections to the 2026-10-14 record

The frozen record is right about what it measured; the semantics it
measured are superseded. Read it with:

- Section 2 item 5 (and the theory note's then section 1 bullet (ii),
  section 3.2 and section 8 item 2, which it cites): "a strength offset is
  ONE absolute number per turn added to both `strengthX[i]` and
  `strengthY[i]`" describes the semantics shipped from 2026-10-12 to
  2026-10-15. From this batch on, the offset is a relative factor on both
  planes, and a horizontal cavity's amplitude noise kicks horizontally only.
- Section 3's predictions table, amplitude rows in y (white 9.5e-7, pink
  1.6e-7 per turn): predictions of the superseded semantics. Under the
  relative semantics they are 0 without the strong beam and the coupling
  only with it.
- Section 5's amplitude rows: the vertical measurements (A1 1.180e-6, A4
  1.677e-5, AP1 2.183e-7, AT1 1.124e-6 per turn; A05 3.135e-7 and A2
  4.368e-6 in the acceptance paragraph; C2's vertical eps_c +1.99e-7) and
  the "vertical excess" numbers over the both-planes prediction (+0.242 at
  scale 1, +0.160 and +0.103 at scale 4, +0.352 pink, +0.183 table) are
  measurements of the superseded semantics and excesses over a prediction
  that no longer applies; the horizontal rows stand. The covariance
  control's vertical agreement (1.0058) verified that the additive kick
  reached `strengthY`, which is exactly the behaviour removed.
- Section 4's "both planes: the realised strengthX offset equals the
  strengthY offset within 0.5 ulp": true of the additive semantics; the
  relative semantics' check is that both planes carry the same factor and
  that `strengthY` stays 0 on a horizontal cavity.
- Section 6's vertical ratios (AP1/A1 0.185 in y, AT1/A1 0.953 in y):
  information about the superseded semantics.
- Section 8 item 1: decided 2026-10-15, relative; its last sentence ("under
  a relative scaling the vertical plane would receive nothing here and these
  rates would vanish") is what section 3 of this record measures.

## 5 Verification

Matrix classes this batch touches, to be read from the diff once it exists:
element spec, metadata and help output (`validate_element_metadata()`, both
`element_help` forms, the snapshot); contracts and acceptance (every test
probing the additive strength offset found first; the kernel-boundary
effectiveness testset); examples (the script runs; the catalogue entry
unchanged); validation (the script reproduces; this record committed);
CUDA-reachable code is untouched while `realize` stays host-side, but the
realised element reaches the device, so the CPU/CUDA identity testset and
the backend-consistency scripts run; docs plus anything else: the full gate.
The gate is the full gate at four threads, CUDA active, in both CPU arms
(native and the AVX2 parity arm) on the batch's final tree before the push.

The full gate ran on the committed tree f7cfe6a in both CPU arms, CUDA
active, four threads. The first native attempt (14:57:52 to 15:25:49 EDT)
did not finish: the test process died with signal 11 after every printed
testset had passed, through "Accelerating cavity changes the reference
exactly (Scope B)", at the point where the suite precompiled
`ArrayInterfaceCUDAExt` mid-run on the networked depot, whose compiled cache
was being rewritten at the time; no test failed and no Julia crash report
was written. The AVX2 arm then ran on the same tree and passed, and the
native arm was rerun alone and passed through the same point:

| arm | start to end, EDT, 2026-10-15 | rows | assertions | exit |
|---|---|---|---|---|
| native, first attempt | 14:57:52 to 15:25:49 | none printed after the crash | none | signal 11, no test failed |
| AVX2 (OpenBLAS Haswell kernels, LLVM target haswell) | 15:25:49 to 16:18:44 | 332 | 149397 of 149397 | 0 |
| native, rerun | 16:19:12 to 17:08:28 | 332 | 149397 of 149397 | 0 |

```bash
julia --project=. --threads=4 -e 'using Pkg; Pkg.test(julia_args=["--threads=4"])'
OPENBLAS_CORETYPE=Haswell julia -C haswell --project=. --threads=4 \
  -e 'using Pkg; Pkg.test(julia_args=["--threads=4", "-C", "haswell"])'
```

Both passing arms end in "Testing Octopus tests passed"; no summary row
carries a Fail, Error or Broken column; their sorted row sets are
identical; nothing was skipped; CUDA was active, 36 rows per arm naming it.
Against the previous gate on f858107 (332 rows, 149351 assertions) the row
count is unchanged and 46 assertions were added, the re-pinned and new
strength assertions of section 2; "Every example script runs against the
current interface" 21/21 (10 min 50 s native, 10 min 39 s AVX2) and "The
developer harnesses run divided under an MPI launcher" 10/10 ran in both.
Checks on the same tree before the gate: the extracted sweeps (exit 0), a
fast lane (exit 0, 316 rows, 147217/147217, the fifteen standard loud
skips) and "Architecture integrity" 28/28; the registry snapshot equals the
generated text. Not verified: CI on this tree, which is not pushed at the
time of writing; the cause of the first attempt's crash, which did not
recur.

## 6 Ledger

- `docs/todo.md`: the turn-modulation row's both-planes owner item reads
  "implementation in progress 2026-10-15 (stage 0)"; the record-note row's
  state gains "stage 0 in progress 2026-10-15".
- `docs/experiences.md`: no entry yet. The candidate lesson, to land with the
  re-validation if it holds: a default taken in the owner's absence on a
  physics convention is costed in the physics it implies before a validation
  campaign measures it as if it were the specification; here the additive
  default produced a vertical emittance growth that two records carried as
  a prediction and a measurement before the owner saw the convention.
- Documents changed in this batch: section 2's documents bullet.
- The implementer's and the validation agent's details replace the three
  markers; the status line changes to the gate's result when the push lands.
