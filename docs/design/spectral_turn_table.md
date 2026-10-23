# A spectral producer for `TurnTable`: per-turn tables from a target spectrum

> **Status: designed 2026-10-15 in owner discussion; the open questions of
> section 9 decided by the owner 2026-10-16 (the dated line under each
> question: Q2, Q4, Q5 and Q6 as proposed, Q3 with both amplitude models
> behind the keyword `amplitudes = :fixed | :rayleigh`, `:fixed` the
> default, carried by the dated remarks under D5 and D7 and in section 4,
> Q1 as proposed and extended the same day by D11: the entry point in a
> line is the spec-level rule `SpectralNoise`, resolved into a `TurnTable`
> when the line compiles, the named function kept for offline tables);
> stage 1 landed as c3c6c2c, gated 2026-10-16 in both CPU arms with CUDA
> active and pushed (record
> `../history/spectral_turn_table_2026_10_16.md`).** Parent note `turn_modulation.md` (the rule interface, D7, and
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

## 3. Decisions (decided by the owner 2026-10-16, section 9)

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

(2026-10-16, D11: the factory's second keyword is `rng_id`, not `stream`,
refused at 0 and not claimed in the registry, the equal-digest warning
being its sharing check, so the keying reads `(seed, RNG_PHILOX, slot,
rng_id, k, 1)` (2026-10-22: `slot`, as review F1 below and the factory's
keyword say; `0` was the pre-F1 keying); the rule `SpectralNoise` claims its
`rng_id` at construction as
`WhiteNoise` and `PinkNoise` do, 0 auto-assigning a fresh id, and takes
`seed = global_rng_seed()` when the line compiles, so inside a line the
author writes no seed and the task constructor's sharing warning is the
protection, as for the live rules.)

(2026-10-16, review F1, fixed the same day: the key gains the SLOT in its
turn field, `octopus_uniform01(seed, RNG_PHILOX, slot, rng_id, k, 1)` and the
pair `(seed, RNG_PHILOX, slot, rng_id, k, 2)`, the factory's keyword `slot`
(default 0, offline tables unchanged) and the resolution passing each
rule's slot (crab cavity phase `i -> i`, strength `i -> N + i`; RF cavity 1
and 2), the canonical name gaining `slot=<s>`. Without it two
`SpectralNoise` sharing one explicit `rng_id` on two slots of ONE element
resolved to identical tables with no warning, where the live rules promise
independent draws per slot under one id. Offline slot 0 keeps the
documented coincidence with a `Beam`'s turn-0 cells; slot >= 1 does not,
and under one shared id shares turn-`slot` cells with radiation particle
`k` and BPM occurrence `k` as the older classes already do among themselves.
Landed as `_spectral_slot`, `_spectral_name`, `_spectral_synthesis` and
`_resolve_turn_rule(rule, slot, T)` in `src/elements/turn_modulated.jl` with
the call sites in both cavities; offline tables bitwise unchanged against
six pre-fix tables.)

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

(2026-10-16, the owner's answer to Q3: both, through the keyword
`amplitudes = :fixed | :rayleigh`, `:fixed` the default. `:fixed` is the
construction above, the owner's: the rms over the period and the
periodogram per bin exact to rounding. `:rayleigh` multiplies each bin's
unit phasor by a standard complex normal `z_k` from the counter RNG, keyed
as the phase is, so that the fixed table is the Rayleigh table with `|z_k|`
forced to 1; the scale `c` is the same, set from the expected power, so
`sigma` is the EXPECTED rms and the bin powers are exponentially
distributed around the target: a stationary Gaussian process matching the
target statistically. The two meanings of `sigma`: the exact rms under
`:fixed`; the expected rms under `:rayleigh`, the realised rms scattering
with relative standard deviation `1 / (2 sqrt(K_eff))`, where `K_eff =
(Σ_k w_k)² / Σ_k w_k²` over the band weights `w_k = 2 a_k²` (Nyquist weight
one) equals `K` for `:flat` and is smaller for a sloped preset (294 of the
32765 bins for `:pink` over `(2^-14, 1/2)` at `N = 2^16`), while the band
mean of the periodogram over the target has relative standard deviation
`1 / sqrt(K)` for either preset. The canonical name of D7 records the
choice.)

(2026-10-16, after landing: the Rayleigh moduli are `rho_k = |z_k|`, `z_k =
(n_1 + i n_2) / sqrt(2)` with `(n_1, n_2) = octopus_normal_pair(seed,
RNG_PHILOX, slot, rng_id, k, 2)` (2026-10-22: `slot`, as review F1 and the
factory's keyword say; `0` was the pre-F1 keying), the Box-Muller pair 2 of
the phase's cell,
components 3-4 and NOT 2-3: component 2 is the second output of the pair
built from the phase's own uniform and would tie the modulus to the phase.
The phase and the scale `c` are the fixed table's, so the fixed table is
the Rayleigh table with every `rho_k` forced to 1. Measured at landing,
kurtosis does not separate the two amplitude modes on a wide band, both
near 0; the periodogram spread does, which is what the suite's falsifier
pins.)

(2026-10-16, review nit: under `:rayleigh` the Nyquist bin, made real with
the sign of `cos(phi)`, carries a Rayleigh modulus rather than the
half-normal one a real Gaussian bin would have; its expected power is
unaffected.)

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

(2026-10-16, after landing and review: two refusals the list above lacks,
a spectrum that vanishes on every bin with `sigma > 0` (the implementer's
addition, "pass sigma = 0 for a quiet table or a spectrum with power in
the band") and a non-callable custom `S` (review nit, refused by name through `applicable`; `_spectral_slot`
likewise refuses a negative or non-integer `slot`); a third from the
neighbour audit's fix group F (U1-7): a custom label that is a preset's
name, `"flat" => S` with `S` not the preset's own shape (case and blank
padding do not make it distinct), because D7 records the label and not `S`,
so such a table was named `spectral(flat; ...)` byte for byte like the
preset's and only the digest told them apart; the
few-bins warning is raised once per rule construction through a warn flag,
not a content-keyed `maxlog` (review F2: that keying silenced later rules
with another `sigma` or spectrum), and the resolution at compile never
warns.)

**D7. The provenance name is canonical.** Unless the caller passes `name`,
the table is named

```
spectral(<label>; sigma=<sigma>, band=<lb>..<ub>, turns=<N>, seed=<seed>, rng_id=<rng_id>, slot=<s>, amplitudes=<fixed|rayleigh>)
```

with the floats in shortest round-trip form and `<label>` the preset
symbol or the custom label verbatim, so the receipt and the artifact
carry the physics that made the table beside its digest. The digest stays
what it is today, FNV-1a over the bytes of what actually ran. (2026-10-16:
the name gains `, amplitudes=<fixed|rayleigh>`, the owner's Q3 decision,
D5; and with D11 the field `stream=` reads `rng_id=`, the rule's table
carrying the global seed in force at compile and its claimed id, so the
receipt shows how to regenerate the table offline with the factory;
and with review F1 (the D4 remark) the field `slot=<s>` after `rng_id=`,
the slot the rule occupies on its element, 0 for an offline table -- the
template above re-issued with it by the 2026-10-16 neighbour audit.)

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

(2026-10-16, review nit: on heterogeneous MPI ranks each rank synthesises
the rule's table at its own compile with its own FFTW, so the tables may
differ in the last bits across ranks; the digest in the provenance is the
writing rank's.)

**D10. The stateless band rule stays deferred.** A per-turn evaluation of
the same sum (`K` cosines per turn, no table) would remove the memory,
8 bytes per turn per slot replicated on every MPI rank, 64 MB per rank for
eight slots at a million turns, 640 MB at ten million. That is the trigger
for building it; until a study runs that long on many ranks, the table is
the right tool and this function is how it is made.

**D11 (owner decision 2026-10-16, after the section 9 answers). The entry
point in a line is a spec-level rule, not only a factory.**
`SpectralNoise(sigma, band, spectrum; rng_id=0, turns, amplitudes=:fixed,
f_rev=nothing) <: AbstractTurnRule`, the interface of `WhiteNoise` and
`PinkNoise`: `rng_id` claimed at construction, 0 auto-assigns a fresh id,
the task constructor's sharing warning applies. It is resolved into a
`TurnTable{T}` when the line compiles, in the cavity's `compile_runtime`
where the element type is known, with `seed = global_rng_seed()` and the
claimed `rng_id`, so at run time it is a table: D7, the recorder, the
one-particle probe and the provenance (kind `table`; the canonical name
carrying `seed=` and `rng_id=`) are untouched. The one stated difference
from the live rules: the table takes the global seed in force when the
line compiles. The standalone `spectral_turn_table(spectrum, sigma, band;
turns, seed, rng_id, ...)` stays for offline tables and is the forward
call the rule's resolution makes (one synthesis body); its second keyword
is `rng_id`, not `stream`, refused at 0 and not claimed in the registry,
the equal-digest warning being its sharing check. Reason, the owner's:
white and pink carry no seed because the seed is global; a rule that reads
the same seed keeps one interface across the four rule kinds, and an
explicit seed is needed only outside a line.

(2026-10-16, after landing: "when the line compiles" is the task's first
`execute!`, a direct `compile_runtime(spec)`, and every recompile -- a knob
assignment or a spec mutation bumps the epoch -- and not task construction;
each compile that resolves the rule re-synthesises the table (the
implementer measured 0.058 s at 2^20 turns with `:fixed`, 0.081 s with
`:rayleigh`), which a knob sweep that recompiles per step pays per step; a
`set_global_rng!` after the first `execute!` that triggers no recompile
leaves the table in place while `WhiteNoise` and `PinkNoise` follow the new
seed from the next turn, the canonical name recording the seed the table
used. The resolution landed in `_resolve_turn_rule`, called from both
cavities' `_turn_modulation_wrap`; the fewer-than-32-bins warning fires once
per rule construction (`maxlog = 1`), not at every compile.)

(2026-10-16, the crab-cavity noise neighbour audit, fix B; owner decision:
warn, the table stays frozen. A resolved table carries the global seed it
was synthesised under (`TurnTable.resolved_seed`, `nothing` on every other
table; set by `_resolve_turn_rule` alone), and every `execute!` of both task
kinds warns while `global_rng_seed()` differs from it, naming the element,
the slot, both seeds, that the series are unchanged and the remedy -- rebuild
the task, which compiles its line at its first `execute!`; before, a
`set_global_rng!` between two windows left the canonical name as the only
evidence (U3-2). And because a `SpectralNoise` has no digest before it
resolves, the constructor's two sharing checks saw neither a rule beside its
offline `spectral_turn_table` of the same seed, rng_id and slot nor the
tables of one spec placed twice: once per compilation, tied to the compile
cache fill of either task kind, the RESOLVED line is walked
(`_warn_resolved_duplicate_tables`, src/tasks/Tasks.jl) and equal digests on
two modulated elements warn by name, worded for two placements of one spec
or for two distinct elements; one table on two slots of one element stays
the silent common-mode choice of D4 (U1-6 / S3-2 / U3-3 / S5-3). The
harness `test/examples/crab_cavity_noise.jl` synthesises its spectral tables
over at least 256 turns so that a 2-turn smoke run, whose synthesis holds one
Nyquist bin, no longer carries identical tables on three of four phase slots
(U7-2). Fix group F of the same audit: the three checks warn once per cause.
The constructor's two word one spec object placed twice as placements and
distinct specs as distinct elements (U8-16), and the task keeps the ids and
digests they named (`ReportedSharing`, src/tasks/Tasks.jl) so the
resolved-line check skips what they covered -- two placements of one spec,
two offline copies of one table, two `SpectralNoise` on one explicit id --
and names what they could not see, the rule beside its offline twin first.)

(2026-10-16, review: per-slot independence under one `rng_id`, as the live
rules give it: the resolution passes the rule's slot into the key (F1,
D4), so two `SpectralNoise` sharing an explicit id on two slots of one
cavity resolve to distinct tables, pinned by regressions (distinct digests,
correlation below `4/sqrt(2 K_eff)` in magnitude: at most 0.147 at `K_eff`
372.6 in the landed test) and by the tie test passing the slot. A third recompile trigger (F5): the loss record's
identity, so a re-run on a beam of another shape or backend recompiles and
re-synthesises under the then-current seed, the receipt's name showing the
seed. The `maxlog = 1` of the sentence above is superseded (F2): the rule
warns at construction through a warn flag and the resolution never.)

## 4. The function

(2026-10-16, D11: the rule first, the factory second; one synthesis body.)

```julia
SpectralNoise(sigma, band, spectrum; rng_id=0, turns, amplitudes=:fixed,
              f_rev=nothing) <: AbstractTurnRule           # in a line (D11)
spectral_turn_table(spectrum, sigma, band; turns, seed, rng_id, slot=0,
                    f_rev=nothing, amplitudes=:fixed, T=Float64,
                    name=nothing) -> TurnTable{T}         # offline; the rule's forward call
```

- `spectrum`: `:flat`, `:pink`, or `"<label>" => S`, with `S(f)` the PSD
  shape evaluated at the band's frequencies (D2).
- `sigma`: the rms over the band, in the slot's unit: radians on a phase
  slot, the dimensionless relative factor on a strength slot (the exact
  rms under `amplitudes = :fixed`, the expected rms under `:rayleigh`, D5).
- `band`: `(lb, ub)` in cycles per turn, or in hertz when `f_rev` is given
  (D3).
- `turns`: mandatory on both (D6). `seed`: the factory's, mandatory (D4);
  the rule takes `global_rng_seed()` when the line compiles (D11).
  `rng_id`: on the rule as on `WhiteNoise` and `PinkNoise`, 0 (the default)
  auto-assigning a fresh id and an explicit id claimed; on the factory
  mandatory, refused at 0 and not claimed (D11; this keyword was `stream`
  before D11). `slot` (2026-10-16, review F1): on the factory the table's
  slot in the key's turn field, 0 (the default) for an offline table; the
  rule passes its own slot at resolution and has no such keyword.
- `amplitudes`: `:fixed` (default) or `:rayleigh` (2026-10-16, the owner's
  Q3 decision; the dated remark under D5): the owner's exact construction,
  or a stationary Gaussian process with `sigma` the expected rms, each
  bin's unit phasor times a standard complex normal from the counter RNG at
  the same scale `c`; recorded in the name (D7). No other default changes.

Algorithm: bins `k` in the band; `a_k = sqrt(S(k/N))` (or of `k f_rev/N`);
`φ_k` from Philox (D4); `X_k = c a_k cis(φ_k)` (times `z_k` under
`amplitudes = :rayleigh`), the Nyquist entry made real;
zeros elsewhere; `irfft(X, N)`; convert to `T`; `TurnTable(x; name)`. The
rule's resolution in the cavity's `compile_runtime` calls the factory with
the claimed id and the global seed and hands the table to the wrap, so the
runtime element holds a `TurnTable{T}` and no `SpectralNoise` (D11). Cost
`O(N log N)`: 0.058-0.071 s and 8.4 MB at 2^20 turns as landed (the
implementer's 0.058 s with `:fixed`, the fixer's 0.063-0.070 s, the
reviewer's 71 ms; the D11 remark and the record; the section 6 sketch's
0.62 s of 2026-10-12 was the pre-implementation figure, corrected here by
the 2026-10-16 neighbour audit), dominated by the transform; a sweep of
thirty band centres is about two seconds of synthesis against hours of
tracking.

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
per-turn cost. (2026-10-16, D11: the rule type `SpectralNoise` lives
beside `WhiteNoise` and `PinkNoise` in the same file and is exported; its
resolution into a table sits where the cavity's `compile_runtime` builds
the `TurnModulated` wrap, the element type being known there; the compiled
line and the device see only the table.)

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
   one process give equal digests; `rng_id + 1` (2026-10-16; `stream + 1`
   before D11) gives a different digest
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
9. **Rayleigh statistics** (2026-10-16, the owner's Q3 decision; the
   tolerances as sent to the implementer, derived in the stage 1 record's
   section 2.1 note). `amplitudes = :rayleigh` for `:flat` and `:pink` at
   `N = 2^16`: the band mean of the periodogram over `c² S(f_k)` within
   `5/sqrt(K)` of 1 (each bin's ratio is `|z_k|²`, exponential with unit
   mean and unit variance); the rms within `5/(2 sqrt(K_eff))` of `sigma`
   relative, `K_eff = (Σ_k w_k)² / Σ_k w_k²` over `w_k = 2 a_k²` (`K` for
   `:flat`, 294 of the 32765 bins for `:pink` over `(2^-14, 1/2)`, so the
   pin is five sigma for both presets where `5/(2 sqrt(K))` would be half a
   sigma for `:pink`); every bin outside the band below 1e-12 of the band's
   peak; the kurtosis falsifier: a two-bin fixed band of adjacent bins,
   whose in-sample excess kurtosis is exactly -0.75 and phase-independent
   (adjacent bins have no fourth-order resonance; a pair `(k, 3k)` would),
   asserted below -0.5, against a wide `:flat` Rayleigh band within ±0.15
   of 0 (in-sample standard deviation about 0.015 at `2^16` turns), the
   `:pink` value printed without a pin (its in-sample scatter is about
   0.066, extremes ±0.124 in 20 draws).
10. **The tie between the rule and the factory** (2026-10-16, D11). A
    one-particle `TrackingTask` with `record_turn_modulation = true` on a
    line carrying `SpectralNoise(sigma, band, spectrum; rng_id = r, turns =
    N)` under `set_global_rng!(seed = s)`: the recorded series equals the
    table of `spectral_turn_table(spectrum, sigma, band; turns = N, seed =
    s, rng_id = r)` bitwise in the same process, and the `:turn_modulation`
    receipt and the artifact carry kind `table` and the canonical name with
    `seed=s` and `rng_id=r`; the compiled line holds no `SpectralNoise`
    (every rule of the runtime element is a `TurnTable{T}` of the line's
    `T`); two `SpectralNoise` with `rng_id = 0` on one line auto-assign
    distinct ids and tables of distinct digests, and an explicit id shared
    by two cavities fires the task constructor's sharing warning as it does
    for `WhiteNoise`.

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
  (2026-10-16, D11: the `:spectral` branch builds `SpectralNoise` exactly as
  the white and pink branches build their rules, with the per-slot `rng_id`
  those branches assign; `table_seed` is unused for it, the seed being the
  global one in force when the line compiles; the harness's third toggle
  is `OCTOPUS_SPECTRAL_AMPLITUDES`.)
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

The owner answered these on 2026-10-16 (the dated line under each
question): Q1, Q2, Q4, Q5 and Q6 as proposed, Q3 with both amplitude models
behind a keyword. Stage 1 implements the answers; its record is
`../history/spectral_turn_table_2026_10_16.md`.

- **Q1. Entry point.** The named function `spectral_turn_table` (proposal),
  or also a constructor method `TurnTable(spectrum, sigma, band; ...)`
  as first proposed in discussion, or only the constructor.
  Decided by the owner 2026-10-16: the named function, no constructor
  method; and, later the same day (D11), the spec-level rule
  `SpectralNoise` with the interface of `WhiteNoise` and `PinkNoise`,
  resolved into a `TurnTable` when the line compiles through the named
  function, which stays for offline tables.
- **Q2. Band units.** Tunes by default with `f_rev` for hertz (proposal),
  or hertz by default with `f_rev` mandatory.
  Decided by the owner 2026-10-16: tunes by default, `f_rev` for a band
  given in hertz.
- **Q3. Amplitudes.** Fixed amplitudes only, the owner's construction and
  the exact-spectrum property (proposal), or a `gaussian = true` keyword
  for Rayleigh amplitudes as well.
  Decided by the owner 2026-10-16, departing from the proposal: a keyword
  `amplitudes = :fixed | :rayleigh`, `:fixed` the default, both offered.
  Fixed: the owner's construction, exact rms and exact periodogram (D5 as
  written). Rayleigh: each bin's unit phasor times a standard complex
  normal from the counter RNG, keyed as the phase is, so the fixed table is
  the Rayleigh table with `|z_k|` forced to 1; the same scale `c` from the
  expected power, so `sigma` is the expected rms and the bin powers are
  exponentially distributed around the target: a stationary Gaussian
  process matching the target statistically. The dated remarks under D5
  and D7 and the signature of section 4 carry it.
- **Q4. Presets.** `:flat` and `:pink` (proposal); whether `:brown` (1/f²)
  or a white floor plus 1/f combination is worth a preset, or stays a
  labelled custom function.
  Decided by the owner 2026-10-16: the presets `:flat` and `:pink` only;
  anything else is a labelled custom function.
- **Q5. Example integration.** A new `:spectral` rule value beside `:table`
  (proposal), or replacing the `:table` value's `randn` tables by the
  `:flat` preset over the full band.
  Decided by the owner 2026-10-16: a new `:spectral` rule value beside
  `:table`; the `:table` value keeps its `randn` white tables.
- **Q6. The equal-digest warning** at the task constructor (proposal), or
  silence, leaving independence to the author.
  Decided by the owner 2026-10-16: the equal-digest warning at the task
  constructor.

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
