# A spectral producer for `TurnTable`: per-turn tables from a target spectrum

> **Status: designed 2026-10-15 in owner discussion, not implemented. The
> decisions of section 3 are proposals the discussion converged on; the
> owner confirms them through the open questions of section 9 before stage
> 1 starts.** Parent note `turn_modulation.md` (the rule interface, D7, and
> its section 6, the producer sketch this note promotes into the library);
> the recorder of `turn_modulation_record.md` is what makes the verification
> of section 6 a one-liner.

## 1. The problem

The three turn-modulation rules fix the spectral shape of the noise they
produce: `WhiteNoise` is flat, `PinkNoise` is 1/f over its octave band, and
`TurnTable` applies whatever sequence it is given. The measurement the crab
cavity noise programme is built around, the emittance growth rate as a
function of where the noise power sits relative to the betatron sidebands
(`../theory/crab_cavity_noise_response.md`), needs noise whose spectrum the
user chooses: a narrow band placed on a sideband and swept across it, a
measured low-level RF spectrum, a 1/f slope over a chosen band, a white
floor plus a line. Today that takes a script outside the repository that
synthesises the sequence and hands it to `TurnTable`, as the owner's own
narrow-band generator does:

```julia
function noise(f0, bw, N, fs, sigma)        # the owner's generator, 2026-10-15
    f = rfftfreq(N, fs)
    index = findall((f .>= f0 - bw/2) .& (f .<= f0 + bw/2))
    A = zeros(Complex{Float64}, length(f))
    A[index] .= [exp(1im * 2pi * rand()) for _ in index]
    ret = irfft(A, N)
    ret .*= sigma / std(ret)
    return ret
end
```

That works, and nothing blocks a study now. What it lacks is what the rest
of the turn-modulation layer insists on: the physics that made the table
(centre, width, shape, rms, seed) is not in the run's provenance, only the
table's digest is; the phases come from an unseeded global `rand()`; a
sweep over the band centre is a file per point; and two slots built the
same way with the same seed would carry identical, fully correlated noise
without anyone being told. This note designs one library function that
produces a `TurnTable` from a target spectrum with those properties built
in, on the producer's side of the D7 boundary.

## 2. What exists

- **`TurnTable` is a pure consumer** (`turn_modulation.md`, D7, owner
  decision 2026-10-12): it applies a value per absolute turn, refuses a
  window it cannot cover (`first_turn + turns <= length(offsets)`, never
  wraps), refuses a table of another element type than the line's, and
  records an FNV-1a digest and a `name` in the provenance receipt and the
  artifact. Spectrum synthesis, normalisation, Gaussianity and periodicity
  are explicitly the producer's. This note adds a producer; the consumer is
  untouched.
- **The producer sketch** (`turn_modulation.md`, section 6, "for
  illustration only"): frequency-domain shaping after Timmer and König with
  fixed bin amplitudes `|X_k| = sqrt(S(f_k) f_rev N / 2)`, a Philox phase
  per bin, DC zero, Nyquist real, `irfft`. Measured 2026-10-12 at 2^20
  turns: 8.4 MB, 0.62 s, the rms equal to the integral of `S` to five
  digits, power per octave 1.000 against the target in all nineteen bands,
  regenerated identically from the same seed. The function of this note is
  that sketch with the owner's band limits and rms normalisation, a
  provenance name, and refusals.
- **The example's synthetic tables** (`examples/crab_cavity_noise.jl`,
  `:table`): `sigma .* randn(Xoshiro(substream), table_turns)` per slot,
  one `Xoshiro` master per `table_seed`; the validation's `synthetic_tables`
  is the same construction. They stay as the white-table precedent; the
  factory does not replace them (section 7).
- **The recorder** (`turn_modulation_record.md`, landed 2026-10-15): with
  `record_turn_modulation = true` the artifact holds the offsets the
  element used, so a periodogram of the recorded series against the target
  spectrum verifies the producer and the consumer together, in one read.
- **FFTW is a core dependency** (`using FFTW` in `src/Octopus.jl`, the PIC
  spectral solvers), so the synthesis needs no new package.

## 3. Decisions (proposed; owner to confirm, section 9)

**D1. One function, on the producer's side of D7.** A factory that returns a
`TurnTable{T}`; the rule itself gains no field and no behaviour. Nothing in
the runtime changes: no new rule kind, no provenance kind, no CUDA, MPI,
allocation or concurrency surface. The whole existing contract (digest,
window check, recorder, the one-particle probe) applies to the result as to
any table.

**D2. The spectrum argument is a power spectral density shape.** The
function takes `spectrum` as a preset symbol (`:flat`, `:pink`) or as
`label => S` with `S(f) >= 0` the one-sided PSD shape, and uses
`sqrt(S(f_k))` as the bin amplitude. This is the classic trap and the
docstring says so: `f -> 1/f` as an amplitude would give a 1/f² (brown)
spectrum, not pink. Only the shape matters (D5), so the units of `f` inside
`S` are irrelevant: `1/f` in hertz and `1/f` in tunes give the same table.

**D3. The band is a pair of modulation tunes, and the DC bin is never in
it.** `band = (lb, ub)` in cycles per turn with `0 < lb < ub <= 1/2`; the
bins are the `k` with `lb <= k/N <= ub`, so `k >= 1` always and a spectrum
that diverges at zero is never evaluated there. A keyword `f_rev` lets the
band (and `S`'s argument) be given in hertz and converts; the provenance
name records tunes. The Nyquist bin (`k = N/2`, present when `ub = 1/2` and
`N` is even) is real, as `irfft` requires, and counts once in the
normalisation where interior bins count twice.

**D4. Phases from the Octopus counter RNG, `seed` and `stream` mandatory.**
The phase of bin `k` is `2π · octopus_uniform01(seed, RNG_PHILOX, 0, stream,
k, 1)`, the keying the section 6 sketch used: a function of `(seed, stream,
k)` alone, stable across sessions and Julia versions, independent of the
task's own seed, which the factory runs before and cannot see. Neither
argument has a default: two slots built with the same `(seed, stream)` are
identical tables, and the only protection against that is that the author
had to write both numbers. In addition the task constructor, which already
warns when two cavities share an `rng_id`, warns when two `TurnTable`s on
different cavities carry equal digests (a cheap comparison it does not make
today).

**D5. Fixed bin amplitudes and an analytic normalisation to `sigma`.** With
`a_k = sqrt(S(f_k))` the sequence is

```
x_n = (2c/N) Σ_k a_k cos(2π k n/N + φ_k)          (interior bins)
```

and over one full period the bins are orthogonal, so the variance is
exactly `(2c²/N²) Σ_k a_k²` (the Nyquist term, when present, enters with
weight one). The scale is therefore `c = sigma N / sqrt(2 Σ_k a_k²)` with no
sample statistic involved: the rms over a period equals `sigma` to rounding,
and the periodogram per bin equals `c² S(f_k)` to rounding, exactly as in
the section 6 measurement. The owner's `sigma / std(ret)` is this constant
up to the Bessel factor `sqrt(N/(N-1))`, 5e-7 at a million turns. Fixed
amplitudes reproduce the target spectrum exactly and give a sequence that is
Gaussian only in the limit of many bins; Rayleigh-distributed amplitudes
(multiply the phasor by a complex normal) would give a stationary Gaussian
process that matches the target statistically. The default is fixed, the
owner's construction; question Q3 asks whether Rayleigh is offered.

**D6. `turns` is mandatory and the refusals are loud.** The table covers
`turns = N` entries, periodic in `N` with no power below `1/N`, and must be
at least as long as the run (the consumer refuses otherwise; this is not
the factory's check). Refused by name: `N < 2`; a band with no bin (`K = 0`,
the message states `lb`, `ub`, `N` and the first bin `1/N`); `lb <= 0`,
`lb >= ub`, `ub > 1/2`; a negative, infinite or NaN `S(f_k)` on any bin
(the bin and its frequency named); non-finite or negative `sigma` (the
rules' `_check_rule_sigma`); a custom spectrum without a label. Warned,
not refused: fewer than 32 bins in the band, because a handful of
sinusoids is a deterministic waveform rather than noise.

**D7. The provenance name is canonical.** Unless the caller passes `name`,
the table is named

```
spectral(<label>; sigma=<sigma>, band=<lb>..<ub>, turns=<N>, seed=<seed>, stream=<stream>)
```

with the floats in shortest round-trip form and `<label>` the preset
symbol or the custom label verbatim, so the receipt and the artifact
carry the physics that made the table beside its digest. The digest stays
what it is today, FNV-1a over the bytes of what actually ran.

**D8. Element type by keyword, `Float64` default.** `T = Float32` produces
a `Float32` table for a `Float32` line (the consumer refuses a mismatch);
the synthesis runs in `Float64` and converts at the end.

**D9. Reproducibility is stated, not overstated.** The phases are bitwise
reproducible everywhere. The `irfft` is FFTW's, whose last bits depend on
the plan FFTW chooses for the machine and build, so the same arguments give
the same table to rounding across machines and bitwise only on the same
machine and FFTW; the digest follows the bytes. Consequently no test pins
a digest value across the two gate arms; tests pin the statistics (D5) and
the same-process regeneration.

**D10. The stateless band rule stays deferred.** A per-turn evaluation of
the same sum (`K` cosines per turn, no table) would remove the memory,
8 bytes per turn per slot replicated on every MPI rank, 64 MB per rank for
eight slots at a million turns, 640 MB at ten million. That is the trigger
for building it; until a study runs that long on many ranks, the table is
the right tool and this function is how it is made.

## 4. The function

```julia
spectral_turn_table(spectrum, sigma, band; turns, seed, stream,
                    f_rev=nothing, T=Float64, name=nothing) -> TurnTable{T}
```

- `spectrum`: `:flat`, `:pink`, or `"<label>" => S`, with `S(f)` the PSD
  shape evaluated at the band's frequencies (D2).
- `sigma`: the rms over the band, in the slot's unit: radians on a phase
  slot, the dimensionless relative factor on a strength slot.
- `band`: `(lb, ub)` in cycles per turn, or in hertz when `f_rev` is given
  (D3).
- `turns`, `seed`, `stream`: mandatory (D4, D6).

Algorithm: bins `k` in the band; `a_k = sqrt(S(k/N))` (or of `k f_rev/N`);
`φ_k` from Philox (D4); `X_k = c a_k cis(φ_k)`, the Nyquist entry made real;
zeros elsewhere; `irfft(X, N)`; convert to `T`; `TurnTable(x; name)`. Cost
`O(N log N)`: 0.62 s and 8.4 MB at 2^20 turns on the section 6 machine,
dominated by the transform; a sweep of thirty band centres is twenty
seconds of synthesis against hours of tracking.

Question Q1 asks whether the same body is also exposed as a constructor
method, `TurnTable(spectrum, sigma, band; kwargs...)`, which the type of the
first argument (a `Symbol` or a `Pair`, never a vector) keeps distinct from
`TurnTable(offsets; name)`. The named function is the proposal because a
call that reads `TurnTable(:pink, 1e-5, (1e-4, 1e-2); turns=...)` hides
that a synthesis with a seed is happening.

## 5. Where it lives

`src/elements/turn_modulated.jl`, after `TurnTable` and its digest, with the
presets as a small table (symbol, label, `S`) that the docstring and the
help output derive from, not a hand-copied list; exported; `?spectral_turn_table`
carries D2 and D5 in full. It is host-side construction code: not
CUDA-reachable, no closure that the `Core.Box` sweep could see, no
per-turn cost.

## 6. Verification plan

Each check is a test the suite runs; the numbers go into the record.

1. **Exact rms and exact periodogram.** For `:flat` and `:pink` at
   `N = 2^16`: the population rms of the table equals `sigma` within
   1e-12 relative; the periodogram divided by `c²` equals `S(f_k)` within
   1e-10 relative on every band bin; every bin outside the band is below
   1e-12 of the band's peak; the DC component is zero.
2. **Slope.** The pink preset over `(2^-14, 1/2)`: log2 power change per
   octave 0 within 0.02 across the twelve full octaves (the section 5.5
   table reports the stateless `PinkNoise` at -0.11 with its construction's
   ripple; the factory has none, which the test states).
3. **Equality with the owner's generator.** The owner's `noise` function,
   written into the test with its phases injected from the same Philox
   source, equals the `:flat` table over the same band to 1e-12 relative
   once its `std` is the population form; this ties the new function to
   the method already used.
4. **Reproducibility and independence.** Two calls with equal arguments in
   one process give equal digests; `stream + 1` gives a different digest
   and a sample correlation below `4/sqrt(N)`; the task constructor warns
   on two cavities carrying tables of equal digest and stays silent
   otherwise (D4).
5. **Refusals by name** (D6), each with its message asserted, and the
   `K < 32` warning captured with `@test_logs`.
6. **Provenance.** A run with a spectral table on one slot writes the
   canonical name and the digest into the `:turn_modulation` receipt and
   the artifact's slot group, read back through `turn_modulation_provenance`.
7. **The producer and the consumer together, through the recorder.** A
   one-particle `TrackingTask` with `record_turn_modulation = true` over
   `N` turns: the recorded series equals the table bitwise, and its
   periodogram passes check 1. The one-particle probe testset itself needs
   no change (a table is a table), which the test states.
8. **Backends.** Check 7 on CPU threads and CUDA; the two-rank MPI arm of
   the harness with `rule = :spectral` (section 7), the arms of the gate run
   one after the other (the 2026-10-15 lesson in the stage 1 record).

## 7. Documentation and examples

- `docs/public_api.md`: the function beside the three rules, with the D2
  warning; `docs/registry_snapshot.md` unchanged unless the export lands in
  a registry (it is a function, not a Core Object).
- `examples/crab_cavity_noise.jl` and its harness: a new rule value
  `:spectral` with `spectrum` (preset or label-function pair), `band` and
  `table_seed` reused as the seed, each slot its own stream in slot order
  as the `:table` substreams are; the existing `:table` value keeps its
  `randn` white tables as the measured precedent (section 2). Toggles
  `OCTOPUS_SPECTRUM`, `OCTOPUS_BAND`. The printed rms table of the example
  reads the realised rms from the record as it does for the other rules.
- `validation/crab_cavity_noise_response.jl`: the `noise` part gains the
  spectral case of check 7; a band sweep across a sideband is a later
  campaign with its own record and is not part of this note.
- `turn_modulation.md` section 6 gains one dated sentence pointing here.

## 8. Staging and cost

One batch, one session: the function and presets, the warning at the task
constructor, the tests of section 6, the docs, the example toggle, the
validation item, the record, and the two-arm gate with the arms run
sequentially. Nothing stateful, nothing on the device, no new receipt.

## 9. Open questions for the owner

- **Q1. Entry point.** The named function `spectral_turn_table` (proposal),
  or also a constructor method `TurnTable(spectrum, sigma, band; ...)`
  as first proposed in discussion, or only the constructor.
- **Q2. Band units.** Tunes by default with `f_rev` for hertz (proposal),
  or hertz by default with `f_rev` mandatory.
- **Q3. Amplitudes.** Fixed amplitudes only, the owner's construction and
  the exact-spectrum property (proposal), or a `gaussian = true` keyword
  for Rayleigh amplitudes as well.
- **Q4. Presets.** `:flat` and `:pink` (proposal); whether `:brown` (1/f²)
  or a white floor plus 1/f combination is worth a preset, or stays a
  labelled custom function.
- **Q5. Example integration.** A new `:spectral` rule value beside `:table`
  (proposal), or replacing the `:table` value's `randn` tables by the
  `:flat` preset over the full band.
- **Q6. The equal-digest warning** at the task constructor (proposal), or
  silence, leaving independence to the author.

## 10. References

- `turn_modulation.md`: D7 (the consumer boundary), section 5.5 (measured
  spectra of the shipped rules), section 6 (the producer sketch and its
  2026-10-12 measurement), reference [9] (Timmer and König, the
  frequency-domain synthesis of a process with a given spectrum).
- `turn_modulation_record.md` and
  `../history/turn_modulation_record_2026_10_15.md`: the recorder, the
  one-particle probe, the gate-arm lesson.
- `../theory/crab_cavity_noise_response.md`: the response the spectrum
  placement is for.
- The owner's `noise(f0, bw, N, fs, sigma)` generator (section 1).
