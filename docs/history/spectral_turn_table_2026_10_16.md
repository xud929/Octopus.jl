# A spectral producer for `TurnTable`: stage 1, `spectral_turn_table` (2026-10-16)

Status: stage 1 implementation landed 2026-10-16 in the worktree, uncommitted
(section 1; the implementer's testsets green through the stage runner with
CUDA active, section 2.2); reviewed the same day, the five findings fixed
and re-verified (section 4); the examples update landed the same day on the
fixed tree (section 3); committed as c3c6c2c and gated the same day in both
CPU arms with CUDA active, the arms one after the other (section 5), pushed
on the owner's authorisation. Stage 1 of
[`../design/spectral_turn_table.md`](../design/spectral_turn_table.md) (its
section 8: one batch, one session), the design the owner discussed on
2026-10-15; the owner gave the go-ahead to implement on 2026-10-15
("fan-out subagents to implement spectral turn table") and decided the open
questions of its section 9 on 2026-10-16 (the dated lines there): Q1 the
named function `spectral_turn_table`, no constructor method, and, later the
same day, the spec-level rule `SpectralNoise` with the interface of
`WhiteNoise` and `PinkNoise`, resolved into a `TurnTable` when the line
compiles through the function, which stays for offline tables (D11, owner
decision 2026-10-16); Q2 the
band in modulation tunes by default with `f_rev` for hertz; Q3, departing
from the proposal, a keyword `amplitudes = :fixed | :rayleigh` with `:fixed`
the default and both offered (fixed: the owner's construction, exact rms and
exact periodogram; Rayleigh: each bin's unit phasor times a standard complex
normal from the counter RNG, keyed as the phase is so that the fixed table is
the Rayleigh table with `|z_k|` forced to 1, at the same scale `c` from the
expected power, so `sigma` is the expected rms and the bin powers are
exponentially distributed around the target, a stationary Gaussian process
matching the target statistically); Q4 the presets `:flat` and `:pink` only;
Q5 a new `:spectral` rule value beside `:table` in the example and the
harness; Q6 the equal-digest warning at the task constructor. The batch is
implemented by three agents in parallel: the
implementer (the function and the rule `SpectralNoise` with its resolution
at compile in `src/elements/turn_modulated.jl` and the cavities, the warning
in `src/tasks/Tasks.jl`, the new testsets in `test/runtests.jl`, a
`docs/public_api.md` paragraph), the examples agent (the `:spectral` rule
value in the example and the harness, the `spectral` item of the validation's
`noise` part, the catalogue entry) and, after both, a read-only review of the
diff; then the two-arm gate with the arms run one after the other (the
2026-10-15 lesson of
[`turn_modulation_record_2026_10_15.md`](turn_modulation_record_2026_10_15.md),
section 5) and the push, both authorised by the owner on 2026-10-16. Parent
notes: `../design/turn_modulation.md` (D7, the consumer boundary this
function sits on the producer's side of; section 6, the sketch it promotes)
and `../design/turn_modulation_record.md` (the recorder, which makes check 7
below a one-liner). This record carries what stage 1 landed (section 1), the
design's verification plan and its numbers (section 2), the examples update
(section 3), the review and its fixes (section 4), the gate (section 5) and
the ledger (section 6). The `impl`, `tests`, `review` and `examples` markers were
filled on 2026-10-16 from the implementer's, the reviewer's, the fixer's and
the examples agent's reports, each code location checked against the landed
source in the worktree and each runtime number attributed to its run; the
bracketed `[...: pending]` markers that remain stand where the gate's
(`gate`) details go, each naming what fills it. A `result/` path is not evidence
and none is cited as one.

## 1 What landed

The design in one paragraph (D1-D11 of the note): one exported factory on
the producer's side of D7 and, by D11, a spec-level rule resolved through
it into a table when the line compiles,

```julia
SpectralNoise(sigma, band, spectrum; rng_id=0, turns, amplitudes=:fixed,
              f_rev=nothing) <: AbstractTurnRule
spectral_turn_table(spectrum, sigma, band; turns, seed, rng_id, slot=0,
                    f_rev=nothing, amplitudes=:fixed, T=Float64,
                    name=nothing) -> TurnTable{T}
```

with `spectrum` a power spectral density SHAPE (`:flat`, `:pink`, or
`"<label>" => S` with `sqrt(S(f_k))` the bin amplitude; `f -> 1/f` as an
amplitude would be brown, not pink, D2); `band = (lb, ub)` in cycles per
turn with `0 < lb < ub <= 1/2`, the bins `lb <= k/N <= ub`, so the DC bin is
never in the band and the Nyquist bin, when present, is real and counts once
(D3; `f_rev` converts a band given in hertz, the name records tunes); the
phase of bin `k` from `2π · octopus_uniform01(seed, RNG_PHILOX, slot, rng_id,
k, 1)`, the turn field carrying the table's SLOT (0 for an offline table,
the factory's `slot` keyword; the rule's own slot when the resolution
synthesises it: review F1, section 4), with the factory's `seed` and `rng_id`
mandatory, `rng_id` refused at 0
and not claimed in the registry (D4 as amended by D11); amplitudes `a_k =
sqrt(S(f_k))` with the analytic scale `c = sigma N / sqrt(2 Σ_k a_k²)` (the
Nyquist term with weight one): under `amplitudes = :fixed`, the default, the
rms over one period equals `sigma` to rounding and the periodogram per bin
equals `c² S(f_k)` to rounding; under `amplitudes = :rayleigh` each bin's
amplitude is multiplied by `rho_k = |z_k|`, `z_k = (n_1 + i n_2)/sqrt(2)`
with `(n_1, n_2) = octopus_normal_pair(seed, RNG_PHILOX, slot, rng_id, k, 2)`,
the Box-Muller pair 2 of the phase's cell (components 3-4, not 2-3:
component 2 is the second output of the pair built from the phase's own
uniform and would tie modulus to phase), the phase and the scale `c` those
of the fixed table, so `sigma` is the expected rms and the bin powers are
exponential around the target, a stationary Gaussian process matching the
target statistically (D5, the owner's Q3 decision of 2026-10-16, the
keying as landed); `turns = N` mandatory, the refusals by
name and the warning below 32 bins (D6); the canonical provenance name
`spectral(<label>; sigma=<sigma>, band=<lb>..<ub>, turns=<N>, seed=<seed>,
rng_id=<rng_id>, slot=<s>, amplitudes=<fixed|rayleigh>)` unless `name` is
passed, the
digest FNV-1a over the bytes as for any table (D7); `T` by
keyword, `Float64` default, the synthesis in `Float64` and converted at the
end (D8); phases bitwise reproducible everywhere, the `irfft` FFTW's, so the
table is equal to rounding across machines and bitwise on one machine and
FFTW build, and no test pins a digest across the two gate arms (D9); the
stateless band rule deferred (D10). The consumer `TurnTable` is untouched: no
new rule kind, no provenance kind, no CUDA, MPI, allocation or concurrency
surface; the window check, the type check, the digest, the recorder and the
one-particle probe apply to the result as to any table. D11: the rule
`SpectralNoise`, the interface of the live rules (`rng_id` claimed at
construction, 0 auto-assigning a fresh id, the task constructor's sharing
warning), is resolved in the cavity's `compile_runtime`, where the element
type is known, into the factory's table with `seed = global_rng_seed()`, the
claimed `rng_id` and the rule's slot (review F1), so the runtime element
holds a `TurnTable{T}` and the
provenance reads kind `table` with the canonical name carrying `seed=` and
`rng_id=`; the one stated difference from the live rules is that the table
takes the global seed in force when the line compiles. Compile means the
task's first `execute!`, a direct `compile_runtime(spec)`, and every
recompile (a knob assignment or a spec mutation bumps the epoch; a re-run on
a beam of another shape or backend changes the loss record the runtime
entries are keyed on, review F5), not task construction; each compile that resolves the rule pays one synthesis (the
implementer: 0.058 s at 2^20 turns, the cost bullet); a `set_global_rng!`
after the first `execute!` that triggers no recompile leaves the table while
`WhiteNoise` and `PinkNoise` follow the new seed from the next turn, and the
canonical name records the seed the table used (stated after landing,
2026-10-16; D11's dated remark).

- The function (D1-D5, D7-D9), its `amplitudes` keyword (`:fixed` the
  default, `:rayleigh`; the owner's Q3 decision of 2026-10-16) and its
  `slot` keyword (review F1, the fixer, 2026-10-16).
  `spectral_turn_table(spectrum, sigma, band; turns, seed, rng_id, slot=0,
  f_rev=nothing, amplitudes=:fixed, T=Float64, name=nothing)` at
  `src/elements/turn_modulated.jl` lines 694-698 (its docstring 532-693),
  exported on line 1 beside `SpectralNoise`, forwards to the shared body
  `_spectral_table(who, spectrum, sigma, band, turns, seed, rng_id, slot,
  f_rev, amplitudes, T, name, warn::Bool)` (lines 706-720), the one body
  behind the factory and the rule's resolution: the `T <: AbstractFloat`
  check, the plan, the keys through `_spectral_key` (374), the `rng_id = 0`
  refusal by name ("0, the live rules' auto-assign, is refused here because
  an offline table is data and claims no stream (put SpectralNoise on the
  element for an assigned stream)"), the slot through `_spectral_slot`
  (384-390, a non-negative integer), then the synthesis.
  `_spectral_plan(who, spectrum, sigma, band, turns, f_rev, amplitudes,
  warn)` (lines 425-481, docstring 406-424) resolves the shape through
  `_spectral_shape` (318-340), validates `amplitudes`, `turns` and `sigma`
  (the rules' `_check_rule_sigma(who, s)`), converts the band through
  `_spectral_band` (342; `lb`, `ub` in tunes and the scale `S`'s argument
  carries, hertz under `f_rev`), finds the band bins as the UnitRange
  `kmin:kmax` of the `k` with `lb <= k/N <= ub` (consecutive, so no vector),
  checks `S` callable on one frequency through `applicable` (453), warns
  below 32 bins when `warn` is set, flags the Nyquist bin (`iseven(N) &&
  kmax == N÷2`), accumulates `Σ_k (2 or 1) a_k²` with `a_k = sqrt(S(f_k))`
  evaluated through `_spectral_bin_frequency(k, N, scale)` (404, the one
  expression the plan and the synthesis share), refuses a spectrum
  vanishing on every bin with `sigma > 0`, and returns `(label, S, sigma,
  N, lb, ub, scale, bins, nyquist, c)` with `c = s N / sqrt(weight)` and no
  amplitude vector. `_spectral_synthesis(plan, seed, rng_id, slot,
  amplitudes, T, name)` (lines 502-531, docstring 483-501) sets bin `k` to
  `c a_k rho_k cis(phi_k)`, `a_k` recomputed from the plan's spectrum,
  `phi_k = 2π octopus_uniform01(seed, RNG_PHILOX, slot, rng_id, k, 1)` and
  `rho_k = 1` or `sqrt((n_1² + n_2²)/2)` from `octopus_normal_pair(seed,
  RNG_PHILOX, slot, rng_id, k, 2)`, the Nyquist entry real with the sign of
  `cos(phi)`, then `irfft(X, N)`, the conversion to `T` when `T !==
  Float64`, and `TurnTable(table; name)` with the canonical name from
  `_spectral_name(label, sigma, lb, ub, N, seed, rng_id, slot, amplitudes)`
  (395-398: the floats through `repr`, the band in tunes, `slot=<s>` after
  `rng_id=`) unless `name` is given; at `slot = 0` the table is bitwise the
  one the body produced before the slot entered the key (the fixer: six
  pre-fix tables, digests unchanged). The presets: `_spectral_flat(f) =
  1.0` and `_spectral_pink(f) = 1.0 / f` (303-304) in `_SPECTRAL_PRESETS`
  (305; `:flat` with label "flat" and formula "S(f) = 1, white over the
  band", `:pink` with label "pink" and formula "S(f) = 1/f, equal power per
  octave"), from which `_spectral_preset_lines()` (309, interpolated into
  both docstrings) and `_spectral_preset_names()` (311, the unknown-preset
  refusal) derive. The docstring carries D2 (the amplitude-versus-PSD trap
  with the brown negative control named), D5 for both amplitude models
  (the exact rms and periodogram under `:fixed`; the expected rms and its
  `1/(2 sqrt(K_eff))` scatter under `:rayleigh`, `K_eff` defined; the
  Nyquist bin's Rayleigh modulus, 647-651), the keying with the slot
  (579-591) and the components 3-4 reason (627-638), the cell-sharing note
  (656-664), the name format, the refusal list, D9 and the cost. The
  key-layout comment above `_RULE_COMPONENT_BASE` (lines 124-147, the
  constant at 148), rewritten by the fixer: the TURN field carries the
  table's slot, 0 offline and the rule's `_slot_rules` number at
  resolution; particle slot = the bin `k >= 1`, component 1 for the phase
  and the Box-Muller pair 2 (components 3-4) for a Rayleigh modulus;
  disjoint from the rules on every slot (particle index `k >= 1` against
  the rules' 0, components 1 and 3-4 against the band `>= 1024`), so a
  table and a rule never share a cell whatever their ids; offline slot 0
  keeps the documented coincidence with a `Beam`'s turn-0
  initial-distribution cells for particle `k` under the same seed and
  `rng_id` (an offline table's `(seed, rng_id)` must not repeat the task
  seed with a beam's `rng_id`); a resolved table (slot >= 1) never touches
  turn 0 and, under one shared id, shares turn-`slot` cells with radiation
  particle `k` and the BPM's occurrence `k`, as the three older classes
  already share among themselves.
- The rule and its resolution (D11). `struct SpectralNoise{F} <:
  AbstractTurnRule` (`turn_modulated.jl` lines 787-798: `sigma`, `band` as
  given, `lb` and `ub` in tunes, `label`, `S::F` the shape as a type
  parameter that never reaches the runtime, `turns`, `amplitudes`, `f_rev`,
  `rng_id`); the constructor `SpectralNoise(sigma, band, spectrum; rng_id=0,
  turns, amplitudes=:fixed, f_rev=nothing)` at 799-810 (a malformed `rng_id`
  refused first by `_rule_stream_id`'s own message so no plan is built and
  no few-bins warning printed for a refused rule; the plan through
  `_spectral_plan("SpectralNoise", ..., true)` at 805, the warning on; the
  stream claimed LAST through `_rule_stream_id`, `next_rng_id!()` for 0 and
  `claim_rng_id!` otherwise, as for `WhiteNoise` and `PinkNoise`); exported
  on line 1; its docstring at 722-786 (compile is the first `execute!`, a
  direct `compile_runtime`, every recompile: a knob assignment or a spec
  mutation bumps the epoch and, review F5 at 767-774, a re-run on a beam of
  another shape or backend changes the loss record the runtime entries are
  keyed on, `_runtime_entries` of Tasks.jl; the `set_global_rng!`
  behaviour; the cost per compile). The root docstring of `AbstractTurnRule`
  names the four rules (86-87). `_rule_kind(::SpectralNoise) = :spectral`
  (928); `_turn_offset(::SpectralNoise, ...)` throws the static
  `ArgumentError` "SpectralNoise resolves to a TurnTable when the line
  compiles (_resolve_turn_rule in _turn_modulation_wrap); it never realises
  a turn itself" (972-974); `_turn_rule_names()` (943-944, its docstring
  932-942 quoting no literal, the review's nit fixed) derives the catalogue
  from the type tree, "PinkNoise, SpectralNoise, TurnTable, WhiteNoise". The
  resolution: `_resolve_turn_rule(rule, slot::Integer, ::Type{T}) = rule`
  (832) and the `SpectralNoise` method (833-837) calling the shared body
  `_spectral_table("SpectralNoise", rule.label => rule.S, rule.sigma,
  rule.band, rule.turns, global_rng_seed(), rule.rng_id, slot, rule.f_rev,
  rule.amplitudes, T, nothing, false)`, the canonical name and the warning
  off; `_resolve_turn_rules(rules::NTuple{K,Any}, first_slot, T)` (838-839)
  numbers a tuple `first_slot + i - 1` through `ntuple(..., Val(K))`; the
  two-argument forms are gone and only three-argument call sites remain in
  `src/`: `src/elements/crab_cavity.jl` 382-385 (`phase_rules` from slot 1,
  `strength_rules` from `N + 1`; the comment 378-381; the docstrings 290-301
  and 357-369) and `src/elements/rf_cavity.jl` 527-529 (phase slot 1,
  strength slot 2; the comment 522-526; the docstring 509-513), on the
  coerced rule tuple before `_check_rule_numeric_types` and the container
  build, so the runtime element holds a `TurnTable{T}` and `_slot_rules`,
  `_realize_draws`, `_slot_nominals` and the provenance walks are untouched
  (receipt kind `:table`). Metadata: the `phase_noise` and `strength_noise`
  `ParamMeta` meanings and the `construction_help` name `SpectralNoise`
  (crab_cavity.jl 243-249; rf_cavity.jl 431-437, the rule list reading
  "WhiteNoise, PinkNoise, TurnTable, SpectralNoise"), hand-written lists
  and not derived from `_turn_rule_names()` (review F4: the rules testset's
  tripwire name-checks the `construction_help` and both meanings of both
  kinds, and caught the crab's strength meaning lacking `PinkNoise`, fixed
  at crab_cavity.jl 244); the fixer reports `validate_element_metadata()`
  passed and all six `element_help` forms naming every rule. The file
  header (line 35) lists the rule. The registry snapshot: regenerated equal
  to the tracked file by the implementer and again by the fixer;
  `docs/registry_snapshot.md` is unmodified in the worktree.
- The refusals and the warning (D6). All in `_spectral_plan` and its
  helpers, prefixed by the caller's name (`spectral_turn_table:` or
  `SpectralNoise:`), each an `ArgumentError` carrying the numbers:
  `amplitudes` other than `:fixed` or `:rayleigh` (the message states both
  meanings); `turns` not an integer or below 2; `sigma` not real, and
  non-finite or negative through `_check_rule_sigma`; the band refusals of
  `_spectral_band` (`lb <= 0`, `lb >= ub`, `ub > 1/2`, a non-positive
  `f_rev`); a band with no bin ("no bin lies in the band lb = ..ub = ..
  cycles per turn at turns = N: the bins are k/N for k = 1, 2, ..., the
  first being 1/N = ..; widen the band or lengthen the table"); a custom
  `S` not callable on one `Float64` frequency, through `applicable`
  (453-456, the review's nit; an `S` of two arguments included); a
  non-finite or negative `S(f_k)` on any bin ("bin k = .. (f = .. cycles
  per turn | Hz) gave .."); a spectrum that vanishes on every bin with
  `sigma > 0`, a refusal the design did not list ("pass sigma = 0 for a
  quiet table or a spectrum with power in the band"); an unknown preset
  (the message lists `_spectral_preset_names()`) and a custom spectrum with
  an empty label (`_spectral_shape`); on the factory also a `T` that is not
  an `AbstractFloat`, a negative or non-integer `seed` or `rng_id`
  (`_spectral_key`), `rng_id = 0`, and a negative or non-integer `slot`
  (`_spectral_slot`). Warned, not refused: fewer than 32 bins, "only K
  bin(s) lie in the band lb..ub cycles per turn at N turns; fewer than 32
  sinusoids is a deterministic waveform rather than noise (widen the band
  or lengthen the table)", with `bins`, `band` and `turns` attached (lines
  455-460), raised when the plan's `warn` flag is set: `true` from the
  factory (697) and from the rule's constructor (805), `false` from the
  resolution (837), so a rule warns once when it is built and never at a
  compile. As the implementer landed it the warning carried `maxlog = 1`
  under an `_id` keyed on `(K, N, lb, ub)`, which silenced later rules with
  another `sigma` or spectrum; review F2 replaced it with the flag (section
  4).
- The equal-digest warning at the task constructor (D4, Q6).
  `_warn_duplicate_turn_tables(elements::Tuple)` (`src/tasks/Tasks.jl` lines
  453-465, docstring from 438), called first from
  `_warn_duplicate_turn_modulation_streams` (line 427, inside the function at
  426), which the `TrackingTask` constructor calls (line 209) and the
  strong-strong task calls over both lines (`src/tasks/strongstrong/interface.jl`
  line 2400, a file the batch does not change), so both tasks get it. The
  digests come from `_collect_turn_tables!` (`turn_modulated.jl` lines
  1505-1517, its docstring just above): one entry `(digest, element, slot,
  name)` per DISTINCT digest per element over the walk `_each_turn_rule_spec`
  (lines 1456-1464), shared with `_collect_turn_modulation_ids!` (whose
  behaviour the implementer re-probed unchanged, 7 direct probes); only a
  rule carrying a `digest` field counts (`TurnTable` today; white and pink
  carry none), so one table on two slots of a single cavity does not warn,
  equal digests on two elements do and distinct digests are silent. The
  message: "multiple turn-modulation tables on different elements carry the
  same digest: their per-turn offsets are identical (fully correlated
  noise). Build each element's table with its own seed or rng_id, or hand
  each its own record.", with `digests` and `tables` (one entry per site,
  "<kind> slot <n>: \"<name>\" digest 0x..").
- The tests (the implementer's runs through the stage runner, S1B
  preamble, `CUDA_TESTS_ACTIVE=true`, then the fixer's after the review's
  fixes, CUDA active; neither report names the host). NEW "Spectral turn
  table: exact spectrum, rms, phases and refusals" (`test/runtests.jl` line
  10740, to 11271; 351 of 351 at landing, 382 of 382 after the fixes): (a)
  the preset table and the docstrings; (b) check 1 for `:flat` over `(1e-3,
  1e-2)` and `:pink` over `(2^-14, 1/2)`, and both at `N = 64` with the
  Nyquist bin; (c) check 2, the slope within ±0.02 and equal to the
  harmonic-sum expectation to 1e-9; (d) negative controls, the
  pink-against-flat periodogram ratio above 0.5; (e) check 3, the owner's
  generator to 1e-12 with a shifted-phase control; (f) check 4,
  reproducibility (the names pinned as text, no digest value), `rng_id + 1`
  and `seed + 1` digests differ, correlation at most `4/sqrt(2 K_eff)` on
  the band-limited tables and `4/sqrt(N)` on the full-band flat table,
  `f_rev = 2^16` bitwise against the tunes band, the hertz-band periodogram,
  `Float32`, `sigma = 0`; (g) the Rayleigh statistics (row 1r); (h) the
  equal-digest warning on `TrackingTask`, `StrongStrongTask` and a
  crab-plus-RF line, silent for distinct digests and for one table on two
  slots of one cavity; (i) 31 factory refusals by message including `rng_id
  = 0`, the `K < 32` warning's content, 32 bins silent and 31 warning; (j)
  13 `SpectralNoise` refusals prefixed "SpectralNoise:", a refused rule
  claiming no stream, `turns` mandatory, `rng_id = 0` auto-assigning
  distinct ids, an explicit id claimed, the `_turn_offset` refusal,
  `_rule_kind`; after the fixes also the `slot` block (10973-11003: `slot =
  0` bitwise the default, slot 1 another table named `slot=1`, the sample
  correlation of the two), the refusals of a negative or non-integer `slot`,
  a non-callable `S` and an `S` of two arguments, and the F2 regression
  (11180-11204: three few-bin constructions of one band warn three times, a
  construction plus two compiles once, no `maxlog` or `_id` in the log).
  NEW "Spectral turn table: the producer through the consumer and the
  recorder" (line 11272, to 11577; 76 of 76 at landing, 98 of 98 after the
  fixes): (a) check 6; (b) check 7 with an offline pink table of `N = 4096`
  on CPU and CUDA; (c) the compiled line holds no `SpectralNoise` (crab, RF,
  mixed, the task's runtime entries), two compiles under one seed give equal
  digests, another seed another digest with `seed=100` in the name, an
  `rng_id = 0` pair distinct, the digest equal to the offline table's for
  `(seed, rng_id, slot)`; (d) the tie (row 7t); (e) the shared-`rng_id`
  warning for two `SpectralNoise` with one explicit id, silent for distinct
  ids, and the equal-digest warning for one offline table on two cavities;
  after the fixes the tie runs through slot 1 and the offline slot-0 table
  differs (11421-11433), the RF strength slot ties with slot 2 under seed
  100 (11440-11449), `phase_noise[2]` resolves at slot 2 (11462-11470), the
  recorded provenance name carries `slot=1` (11487) and the offline table's
  `slot=0` (11353), and section (f), the F1 regression (11533-11570): one
  explicit `rng_id` on two slots of ONE element (crab two phase slots, phase
  plus strength, RF both slots) gives distinct digests and a correlation at
  most 0.147 in magnitude at `K_eff` 372.6; the `reset_rng_id_counter!(0)`
  of F3 is gone (none left in the suite; the comment at 11410-11412 says
  why). Adjusted "Turn modulation: rules, wrapper and the pure hook" (line
  9940; 528 of 528 at landing, 536 of 536 after the fixes): its instance
  table gains `SpectralNoise` and the derived rule set pins the four kinds
  (10415), its draw comparison reads the first slot of the COMPILED rule
  (10607, a `TurnTable` for `SpectralNoise`), and its metadata tripwire (j)
  name-checks the `strength_noise` meanings of both kinds beside the
  `phase_noise` ones and the `construction_help` (the comment 10456-10462,
  the loop 10492-10495; review F4). Red evidence: at landing the negative
  controls inside the testsets (pink against flat, brown against pink, the
  shifted-phase generator, each mirrored pin asserted to fail by a stated
  margin), no run of the new testsets on the pre-change source being in the
  report; for the fixes, the fixer's red log on the pre-fix tree, 4 passed
  and 6 failed each for the defect's reason (equal digests, correlation
  1.0; F2 "1 == 3"), 10 of 10 after. Neighbours green (the implementer's
  counts at landing and the fixer's after): RF cavity 147, provenance 127,
  realised modulation 268, the one-particle probe 376 (CPU, CUDA, two-rank
  MPI), slot bounds 26, kernel boundary 57, CPU/CUDA identity 39; at
  landing also white and pink spectra 45, strong-strong window 20, every
  export documented 1. The extracted sweeps exit 0 both times (the stage 6
  pin tripwire, the `Core.Box` sweep, the detached-docstring sweep); the
  snapshot regenerated equal to the tracked file both times;
  `validate_element_metadata()` passed both times and all six `element_help`
  forms name every rule. Not run by either: the full gate and the fast
  lane; nothing committed.
- Cost measured at landing (the implementer's numbers, host not named in the
  report; the minimum of 3 runs at 2^20 turns, `:pink`): `:fixed` 0.0583 s
  and 39.10 MB allocated (the table itself 8.39 MB); `:rayleigh` 0.0812 s
  and 39.10 MB; against the design's 0.62 s and 8.4 MB at 2^20 turns on the
  2026-10-12 machine. Each compile that resolves a `SpectralNoise` pays this
  once. The review's run (section 4): 71 ms at 2^20 turns and 1.56 s at
  2^24, FFTW single-threaded; the transient synthesis memory about 4.7
  times the table (37 MiB for 8 MiB at 2^20, 683 MiB at 2^24). After the
  review's nit (the fixer, `bins` a UnitRange and no amplitude vector): at
  2^20 turns 24.0 MiB allocated for the 8.0 MiB table, 3.0 times, against
  37.3 MiB (4.66 times) before; at 2^22 96.0 against 159.2 MiB; 0.063 s
  against 0.070 s `:fixed`, 0.082 against 0.086 s `:rayleigh` (the
  `_spectral_synthesis` docstring, 495-499).
- Documents, this batch: `docs/public_api.md` ("Turn Modulation":
  `?SpectralNoise` and `?spectral_turn_table` in the help block, lines
  213-214; the paragraph at 221-261, the rule first and the factory as its
  offline form with `slot = 0`, the D2 trap, both meanings of `sigma`, the
  seed-at-compile difference "the first `execute!`, or a recompile after a
  knob assignment", the key `(seed, rng_id, slot, bin)` with the slot
  numbering per cavity, the canonical name with `slot=..`, the two-line
  example); `docs/design/spectral_turn_table.md` (the status line; a dated
  decision line under each of section 9's six questions; D11 and the dated
  remarks); `docs/design/turn_modulation.md` (section 6's dated pointer
  sentence; the section 10 fix); `docs/README.md` (this record indexed in
  the history section; the design-note entry); `docs/todo.md` (the spectral
  producer row); `docs/experiences.md` (the coordinator's entry, section 6);
  this record. `docs/registry_snapshot.md`: unmodified in the worktree, the
  regeneration equal to the tracked file (the function and the rule are not
  Core Objects; no rule type appears in it). Source files of the
  implementer's batch and of the review's fixes (`git status` of the
  worktree, 2026-10-16): `src/elements/turn_modulated.jl`,
  `src/elements/crab_cavity.jl`, `src/elements/rf_cavity.jl`,
  `src/tasks/Tasks.jl`, `test/runtests.jl`, `docs/public_api.md`;
  `src/tasks/strongstrong/interface.jl` unchanged; the fixes touched the
  first three, the suite and `docs/public_api.md`. After the examples update
  (section 3) the batch also changed `examples/crab_cavity_noise.jl`,
  `test/examples/crab_cavity_noise.jl`,
  `validation/crab_cavity_noise_response.jl` and `src/examples/Examples.jl`
  (the examples agent), and `validation/README.md` and the example
  paragraph of `docs/public_api.md` (this record's author, section 6).

## 2 Verification

**2.1 The plan.** The design note's section 6: each check is a test the
suite runs and its numbers go here. Checks 1-7 are the suite's, in the
implementer's two testsets; check 8, the backends, splits between the suite
(check 7 on CUDA, `@test_skip` without a device) and the harness (the
two-rank MPI arm with `rule = :spectral`, the examples agent's), with the
gate's arms run one after the other. The last row is the examples agent's
validation item (the design's section 7). One row per check; the tolerance
is the design's and the measured number is the test's own printout.

| check (design section 6) | what is asserted | tolerance (design) | measured | verdict |
|---|---|---|---|---|
| 1 exact rms and exact periodogram (`amplitudes = :fixed`, the default) | `:flat` and `:pink` at `N = 2^16`: the population rms of the table against `sigma`; the periodogram divided by `c²` against `S(f_k)` on every band bin; every bin outside the band against the band's peak; the DC component | 1e-12 relative; 1e-10 relative; below 1e-12 of the peak; exactly zero | `N = 2^16`, `sigma = 1e-5`, seed 2026, `rng_id` 11 (the implementer): `:flat` over `(1e-3, 1e-2)`: rms relative error 2.2e-16, worst periodogram relative error 8.9e-16, out-of-band over peak 6.6e-32, DC over peak 1.5e-33; `:pink` over `(2^-14, 1/2)`: -1.2e-15, 1.8e-14, 3.4e-33, 5.0e-35, the mean over `sigma` 1.6e-17; both presets also at `N = 64` with the Nyquist bin | PASS (the implementer's run, testset A item (b)) |
| 1r Rayleigh statistics (`amplitudes = :rayleigh`; the owner's Q3 decision of 2026-10-16; the design's item 9, beside check 1) | `:flat` and `:pink` at `N = 2^16`: the band mean of the periodogram over `c² S(f_k)`; the rms of the table against `sigma`; every bin outside the band against the band's peak; the kurtosis falsifier: a two-bin fixed band of adjacent bins (in-sample excess kurtosis exactly -0.75, phase-independent) against a wide `:flat` Rayleigh band, the `:pink` value printed | band mean within `5/sqrt(K)` of 1; rms within `5/(2 sqrt(K_eff))` of `sigma` relative, `K_eff = (Σ w_k)²/Σ w_k²` over `w_k = 2 a_k²` (`K` for `:flat`, 294 of 32765 bins for `:pink`); out-of-band below 1e-12 of the peak; the two-bin control below -0.5, the wide `:flat` Rayleigh band within ±0.15 of 0, `:pink` without a pin (the tolerances sent to the implementer 2026-10-16; the note below the table) | `:pink` Rayleigh: band-mean ratio 1.0018 (bound `5/sqrt(K)` = 0.0276 at `K` = 32765), variance ratio 1.011 (an added check, bound `5 sqrt(8/K)`), rms relative -0.035 (bound `5/(2 sqrt(K_eff))` = 0.146 at `K_eff` 294.4); out-of-band and DC at most 1e-12 of the peak asserted; the falsifier: the Rayleigh periodogram's max abs(ratio - 1) above 0.5 against the fixed table's periodogram variance at most 1e-20; the phases identical bin for bin to the fixed table and the moduli equal to the documented draws; digest reproducibility; `rng_id + 1` correlations 0.037 (`:flat`) and -0.036 (`:pink`), bound `4/sqrt(K_eff)`; kurtosis: excess 0.030 for the wide `:flat` Rayleigh band (bound 0.15), 0.022 for the wide `:flat` FIXED band -- kurtosis does not separate the two amplitude modes on a wide band, both near 0, the periodogram spread does -- 0.0125 printed for the wide `:pink` Rayleigh band, exactly -0.75 for the two-bin fixed control (bound -0.5); the `:flat` Rayleigh band-mean and rms values are not in the report | PASS (testset A item (g)) |
| 2 slope | the pink preset over `(2^-14, 1/2)`: the log2 power change per octave across the twelve full octaves (the stateless `PinkNoise` reads -0.11 with its construction's ripple in the parent note's section 5.5; the factory has none, which the test states) | 0 within 0.02 | `:pink` -0.0083 per octave over the twelve octaves, equal to the harmonic-sum expectation to 1e-9; the controls: `:flat` +1.0000000000000067, brown (`1/f` as an amplitude) -1.017 | PASS (testset A items (c), (d)) |
| 3 equality with the owner's generator | the owner's `noise(f0, bw, N, fs, sigma)` written into the test, its phases injected from the same Philox source and its `std` the population form, against the `:flat` table over the same band | 1e-12 relative | equality to 1e-12 relative asserted, with a shifted-phase control that fails it; the measured maximum is not in the report | PASS (testset A item (e)) |
| 4 reproducibility and independence | two calls with equal arguments in one process: equal digests; `rng_id + 1`: a different digest and the sample correlation of the two tables; the task constructor warns on two cavities carrying tables of equal digest and stays silent otherwise (D4) | correlation below `4/sqrt(N)` | equal arguments: equal digests (the names pinned as text, no digest value); `rng_id + 1` and `seed + 1`: different digests; correlation bound `4/sqrt(2 K_eff)` on the band-limited tables and `4/sqrt(N)` on the full-band flat table (the values not in the report); `f_rev = 2^16` reproduces the tunes table bitwise and the hertz band's periodogram passes; `Float32` and `sigma = 0` covered; the equal-digest warning fires on `TrackingTask`, `StrongStrongTask` and a crab-plus-RF line and stays silent for distinct digests and for one table on two slots of one cavity (the `@test_logs` patterns not quoted in the report); after review F1 the regression, section (f) of the consumer testset (lines 11533-11570): one explicit `rng_id` on two slots of ONE element (crab two phase slots, phase plus strength, RF both slots) gives distinct digests and a correlation at most 0.147 in magnitude at `K_eff` 372.6, red on the pre-fix tree (equal digests, correlation 1.0) | PASS (testset A items (f), (h); the F1 regression after the fix) |
| 5 refusals by name | each D6 refusal with its message asserted; the fewer-than-32-bins warning captured with `@test_logs` | the exact messages | 31 factory refusals asserted by message, `rng_id = 0` included; 13 `SpectralNoise` refusals prefixed "SpectralNoise:"; the `K < 32` warning's content asserted, 32 bins silent and 31 warning; after the fixes also a negative or non-integer `slot`, a non-callable `S` and an `S` of two arguments refused by name, and the F2 regression (lines 11180-11204: three few-bin constructions warn three times, a construction plus two compiles once), red on the pre-fix tree ("1 == 3") | PASS (testset A items (i), (j); the slot and `S` refusals and the F2 regression after the fix) |
| 6 provenance | a run with a spectral table on one slot: the canonical name (carrying `seed=` and `rng_id=`) and the digest, kind `table`, in the `:turn_modulation` receipt and in the artifact's slot group, read back through `turn_modulation_provenance` | equality | the receipt, the artifact, the reader and the HDF5 `name` and `kind` attributes (the recorded name string is not quoted in the report) | PASS (testset B item (a)) |
| 7 the producer and the consumer together, through the recorder | a one-particle `TrackingTask` with `record_turn_modulation = true` over `N` turns: the recorded series equals the table bitwise and its periodogram passes check 1; the one-particle probe testset itself needs no change (a table is a table), which the test states | bitwise; check 1's | an offline `:pink` table of `N = 4096`: the recorded series bitwise equal to the table, check 1 on the recorded series (its worst ratio not in the report), the window refusal naming the table; on CPU threads and on CUDA (ran) | PASS (testset B item (b)) |
| 7t the tie between the rule and the factory (D11, owner decision 2026-10-16; the design's item 10) | a one-particle `TrackingTask` with `record_turn_modulation = true` on a line carrying `SpectralNoise(sigma, band, spectrum; rng_id = r, turns = N)` under `set_global_rng!(seed = s)`: the recorded series against the table of `spectral_turn_table(spectrum, sigma, band; turns = N, seed = s, rng_id = r)` in the same process; the receipt and the artifact: kind `table`, the canonical name with `seed=s` and `rng_id=r`; the compiled line holds no `SpectralNoise` (every runtime rule a `TurnTable{T}`); two `SpectralNoise` with `rng_id = 0` on one line; an explicit id shared by two cavities | bitwise; equality; type identity; distinct ids and distinct digests; the sharing warning fires | `set_global_rng!(seed = 99)` and `SpectralNoise(...; rng_id = 7)`: the recorded series equals `spectral_turn_table(...; seed = 99, rng_id = 7)` bitwise on CPU and CUDA, kind `:table`; a `set_global_rng!` after the first `execute!` leaves the table (the second receipt carries the same digest and a name saying `seed=99`); the compiled line holds no `SpectralNoise` (crab, RF, mixed, the task's runtime entries); two compiles under one seed give equal digests, another seed another digest with `seed=100` in the name; an `rng_id = 0` pair distinct; the shared-`rng_id` warning for two `SpectralNoise` with one explicit id, silent for distinct ids; the equal-digest warning for one offline table on two cavities (`N` and the auto-assigned ids not in the report); after review F1 the tie runs through slot 1 and the offline slot-0 table differs (lines 11421-11433), the RF strength slot ties with slot 2 under seed 100 (11440-11449), `phase_noise[2]` resolves at slot 2 (11462-11470), the recorded provenance name carries `slot=1` (11487) and the offline table's `slot=0` (11353) | PASS (testset B items (c), (d), (e); the slot ties after the fix) |
| 8 backends | check 7 on CPU threads and on CUDA (`_HAS_CUDA && CUDA.functional()`; `@test_skip` without a device), the series bitwise against the CPU's; the two-rank MPI arm of the harness with `rule = :spectral` (section 3) | check 7's; the series bitwise across backends (host-side realisation) | check 7 and the tie ran on CPU threads and on CUDA (testset B items (b), (d)); the one-particle probe testset 376 of 376 on CPU, CUDA and the two-rank MPI arm, unchanged; the harness's MPI arm with `rule = spectral` ran on two ranks (the `MPICH_jll` `mpiexec`, package mode, `--threads=4`, 37 s): `ranks=2 threads=4`, rank 1 tracked its shard, rank 0's checks green (every series bitwise against the record, the provenance names), one artifact (section 3) | PASS for the suite's arms (the implementer) and for the harness's MPI arm (the examples agent) |
| the validation's `spectral` item (design section 7) | `validation/crab_cavity_noise_response.jl`, part `noise`: the spectral case of check 7 at the part's turn count, the recorded series against the table and its periodogram against the target | bitwise against the table; the periodogram per check 1 | three cases (section 3): `:flat` over `(3e-3, 4e-3)` fixed, `:pink` over `(2^-14, 1/2)` fixed, `:flat` narrow Rayleigh, eight `SpectralNoise` slots each; the part's line `CRAB-NOISE-RULES turns=65536 checks=273 failed=0 verdict=PASS`, 2:31 wall, the three `execute!` runs 3.4-4.0 s each; flat_fixed (K = 66) max relative periodogram error 8.9e-16, rms over sigma minus 1 within [0, 2.2e-16], out-of-band at most 4.0e-32 of the peak over 32703 bins, DC at most 3.4e-34; pink_fixed (K = 32765, the Nyquist bin in the band) 1.97e-14, -1.22e-15, out-of-band 2.9e-33 over 4 bins, DC 2.6e-34; flat_rayleigh (K = 66) band means in [0.803, 1.137] against 0.6155, sample variances [0.622, 1.805], rms over sigma in [0.896, 1.066] against 0.3077, out-of-band at most 2.1e-32; all 24 series equal to the factory table bitwise with slot-bearing names (e.g. `rng_id=14, slot=4`); the artifacts `noise_recorded_spectral_<preset>_<amplitudes>.h5`; the host not named in the report | PASS (the examples agent's run on the fixed tree) |

Note on the Rayleigh row's tolerances (2026-10-16, written with this
skeleton from the formulas of D5 and a 200-draw numpy simulation at `N =
2^16`, band `(2^-14, 1/2)`, `default_rng(20261016)`; the skeleton's
forecast behind the corrected tolerances the row and the design's item 9
now carry, which the landed test's own printout replaces). The realised
rms under `:rayleigh` scatters with relative standard deviation `1/(2
sqrt(K_eff))`, `K_eff = (Σ w_k)²/Σ w_k²` over the band weights `w_k = 2
a_k²` (Nyquist weight one): `K_eff = K` for `:flat` (simulated 0.0026
against `1/(2 sqrt(K))` = 0.0028), but 294 of the 32765 bins for `:pink`
(simulated 0.0285 against `1/(2 sqrt(K_eff))` = 0.0291), so `5/(2 sqrt(K))`
is a five-sigma band for `:flat` and a half-sigma band for `:pink`, which
correct code fails about two times in three; hence `K_eff` in the row. The
band mean of the
periodogram over the target has relative standard deviation `1/sqrt(K)` for
either preset (each ratio is `|z_k|²`, exponential with unit mean and unit
variance), so `5/sqrt(K)` is five sigma for both. The in-sample excess
kurtosis of a table of `K` sinusoids is `-1.5 Σ b_k⁴/(Σ b_k²)²` in the
realised amplitudes `b_k` when no four bins resonate (`±k1 ±k2 ±k3 ±k4 !=
0`), `-1.5/K` for equal fixed amplitudes; consecutive bins do resonate (`k1
+ k2 = k3 + k4`), so 8 consecutive fixed bins read -0.23 with standard
deviation 0.62 over the phase draws (extremes -1.16 and +3.11), two bins
read -0.75 exactly and phase-independently, three consecutive bins -0.54 ±
0.47. "Below -0.5" therefore holds for a two-bin fixed control of adjacent
bins (a pair `(k, 3k)` would resonate) and not reliably for 8 consecutive
bins; hence the two-bin control in the row. The wide Rayleigh band's
in-sample excess kurtosis: `:flat` 0.000 ± 0.015, `:pink` -0.002 ± 0.066
with extremes ±0.124 in 20 draws, so ±0.15 is ten sigma for `:flat` and
about 2.3 sigma for `:pink`; hence the `:flat` pin and the `:pink` value
printed without one. Measured by the implementer (row 1r): 0.030 for the
wide `:flat` Rayleigh band against 0.022 for the wide `:flat` fixed band,
so kurtosis does not separate the two amplitude modes on a wide band (both
near 0); the periodogram spread does, which is the falsifier the row pins.

**2.2 Results.** Verified 2026-10-16 by the implementer through the stage
runner (S1B preamble, `CUDA_TESTS_ACTIVE=true`; the host is not named in the
report): "Spectral turn table: exact spectrum, rms, phases and refusals" 351
of 351, "Spectral turn table: the producer through the consumer and the
recorder" 76 of 76 with its CUDA arms run, "Turn modulation: rules, wrapper
and the pure hook" 528 of 528, the neighbours as listed in section 1's
tests bullet; and again by the fixer after the review's fixes (the stage
runner, CUDA active): 382 of 382, 98 of 98 and 536 of 536, with RF cavity
147, provenance 127, realised modulation 268, the one-particle probe 376,
slot bounds 26, kernel boundary 57 and CPU/CUDA identity 39, each in full.
The rows of 2.1 map to testset A items (b)-(j) and testset B items (a)-(e)
as each row states, the fixes' regressions appended to rows 4, 5 and 7t.
Red evidence: at landing the negative controls inside the testsets (pink
against flat, brown against pink, the shifted-phase generator, the mirrored
pins), not a run of the new testsets on the pre-change source; for the
fixes the fixer's red log on the pre-fix tree, 4 passed and 6 failed each
for the defect's reason, 10 of 10 after. Not verified by either at landing:
the full gate and the fast lane; the MPI harness arm (the examples
agent's); nothing committed.

## 3 The examples update

Decided as Q5 (the design's section 7): a new `:spectral` rule value beside
`:table`, the `:table` value keeping its `randn` white tables as the
measured precedent (design section 2); the example's configuration gains
`spectrum` (a preset symbol or a label-function pair) and `band`, and its
`:spectral` branch builds `SpectralNoise` exactly as the white and pink
branches build their rules, with the per-slot `rng_id` those branches
assign, `table_seed` unused for it since the seed is the global one in
force when the line compiles (D11, owner decision 2026-10-16); the harness
gains the toggles
`OCTOPUS_SPECTRUM`, `OCTOPUS_BAND` and `OCTOPUS_SPECTRAL_AMPLITUDES` (the
owner's Q3 decision of 2026-10-16) and its `CRAB-NOISE` line an
`amplitudes=` field; the example's printed per-slot rms
table reads the realised rms from the record as it does for the other
rules; the validation's `noise` part gains the spectral case of check 7; the
catalogue entry names the new rule value. On the pre-change tree 12b4d75 the
rule set is `:white | :pink | :table | :none` (`examples/crab_cavity_noise.jl`
line 46 in the header and lines 375-376 in the check; the rule construction
and the `:table` master stream at lines 385-396), the harness's `:table`
sites are `test/examples/crab_cavity_noise.jl` lines 419, 733 and 772-773,
the catalogue entry is `src/examples/Examples.jl` lines 87-105, and the
validation's `synthetic_tables` and `recorded` item are
`validation/crab_cavity_noise_response.jl` line 480 and lines 895-919.

- The example (`examples/crab_cavity_noise.jl`, +177 lines, the examples
  agent): the rule set `:white | :pink | :table | :spectral | :none` (the
  header's line 50; the check at 446-447); the `:spectral` branch of
  `noise_rule` (lines 461-475) returns `SpectralNoise(sigma, cn.band,
  cn.spectrum; rng_id = rng_id, turns = cn.table_turns, amplitudes =
  cn.amplitudes)`, parallel to the white and pink branches with the same
  explicit ids (10 + slot on `tccb`, 20 + slot on `tcca`) and the run's
  global seed, `table_seed` read by `:table` only (the header says so,
  lines 55-62 and 237-246); the config fields `spectrum = :pink`, `band =
  (1.0 / 2^16, 0.5)` and `amplitudes = :fixed` (lines 247-270; the band is
  the `:pink` rule's 16-octave band, so the two rules compare at equal rms
  and band, the exact `1/f` spectrum against the Voss-McCartney
  approximation), `table_turns` shared with `:table`; the header's question
  list, INPUTS, a `:spectral` paragraph (lines 79-103: the D2 trap, the D3
  band, the D5 normalisation, the canonical name with `seed`, `rng_id`,
  `slot` and `amplitudes`) and OUTPUTS; `case_name` adds the spectrum's
  label (`crab_noise_spectral_pink_x1`, lines 107-108); the printed rms
  table's expected column (lines 806-822): with fixed amplitudes "1 exactly
  up to rounding (analytic normalisation over the whole period)" when the
  run covers the table's period, otherwise "no pin (partial period: n of N
  table turns)", with Rayleigh amplitudes "no pin (Rayleigh amplitudes:
  sigma is the expected rms)"; the `:table` value unchanged; the default
  rule stays `:white`. The crab cavities carry N = 3 harmonics with
  harmonics 1 and 2 active, so the active slots are 1, 2 (phase) and 4, 5
  (strength).
- The harness (`test/examples/crab_cavity_noise.jl`, +254 lines): the
  toggles `OCTOPUS_SPECTRUM` (`flat` or `pink`, default `pink`),
  `OCTOPUS_BAND` (`<lb>,<ub>` in cycles per turn, the example's band by
  default) and `OCTOPUS_SPECTRAL_AMPLITUDES` (`fixed` or `rayleigh`, default
  `fixed`), documented in the header (lines 147-180) and parsed at 498-535,
  each refused by name under any other rule and on bad grammar (8 refusals;
  fewer than 32 bins warns and does not refuse, line 522); under `rule =
  spectral` each slot carries `SpectralNoise(sigma, cn.band, cn.spectrum;
  rng_id, turns = cn.table_turns, amplitudes)` and its record is
  `spectral_turn_table(cn.spectrum, sigma, cn.band; turns = cn.table_turns,
  seed = global_rng_seed(), rng_id, slot, amplitudes)` with `slot = i` for a
  phase slot and `N_harmonics + i` for a strength slot (lines 866-882; N =
  3, so slots 1, 2, 4, 5); on the rank holding the file every recorded
  series must equal its record bitwise, the provenance name must contain
  `seed=<the global seed>` and `rng_id=<id>` and equal the record's
  canonical name, kind `:table`; with fixed amplitudes the rms equals sigma
  within 1e-9 relative when the series is the whole table period (lines
  1323-1340), otherwise printed without a pin; with Rayleigh amplitudes the
  ratio is printed with `1 +- 1/(2 sqrt(K))` labelled as the flat-band
  one-sigma, no pin; the `CRAB-NOISE` line gains `spectrum= band=
  amplitudes=` after every pre-existing field (lines 1405-1407; `none` under
  the other rules), and both consumers of that line, the profiling driver's
  `crab_line` regex (`profiling/crab_cavity_noise_backends.jl` line 440) and
  the validation's `parse_receipt_line`
  (`validation/crab_cavity_noise_response.jl` line 1207), read all 22 old
  fields of the new line (the examples agent's check); the MPI arm kept. At
  2 turns the `K < 32` warning prints 16 times (8 constructions plus 8
  reference factory calls), expected and said in the header.
- The catalogue entry (`src/examples/Examples.jl` lines 87-108): the
  summary now reads "white, pink, a tabulated record or a spectral rule
  (SpectralNoise: a target spectrum over a chosen band, fixed or Rayleigh
  amplitudes, resolved into a table when the line compiles) through one
  switch"; its object list names `SpectralNoise` beside the other rule
  types (added by the coordinator before the commit, 2026-10-16, after the
  record's first draft had noted it missing).
  `example_catalog()` is not restated in the examples agent's report;
  `validate_element_metadata()` passed in the fixer's run on the same
  tree.
- The validation item (`validation/crab_cavity_noise_response.jl`, +205
  lines): part `noise` gains the `spectral` item (the header's description
  at lines 185-237, the artifacts at 245; the code from line 1000 to 1127;
  `cavity_spec` gained the `:spectral` branch, line 633): three cases,
  `:flat` over `(3e-3, 4e-3)` with fixed amplitudes, `:pink` over `(2^-14,
  1/2)` with fixed amplitudes, `:flat` over the narrow band with Rayleigh
  amplitudes; per case eight `SpectralNoise` slots (`rng_id`s 11, 12, 14, 15
  and 21, 22, 24, 25) through the two-cavity CPU `TrackingTask` of the
  256-macroparticle beam, N = 65536 turns from turn 0 with the record on;
  the record per slot the factory's table with `seed = SEED`, the `rng_id`
  and the slot (1, 2, 4, 5); checks per slot: the series equal to the table
  bitwise plus the provenance (kind `:table`, digest, name, length); the
  periodogram `abs2.(rfft(series))` over `c² = sigma² N² / (2 Σ_interior
  S(f_k) + S(1/2) when the Nyquist bin is in the band)`; fixed amplitudes:
  the ratio within 1e-10 per band bin, every out-of-band bin including DC at
  most 1e-12 of the band peak, the rms over sigma within 1e-12; Rayleigh
  amplitudes: the band mean within `5/sqrt(K)` of 1, the rms within `5/(2
  sqrt(K))` of sigma (a flat band, `K_eff = K`), the sample variance of the
  ratios at least 0.1 (anti-vacuity: fixed amplitudes give exactly 0), the
  out-of-band bins as before; below K = 8 bins (a `turns=` override under
  2048) a counted FAIL naming the bin count; the artifacts
  `noise_recorded_spectral_<preset>_<amplitudes>.h5`; the header's runtime
  now "about two and a half minutes after the Octopus load, the three
  spectral cases included" (lines 32-33). The run and its numbers: the
  validation row of section 2.1. `validation/README.md` was not changed by
  the examples agent; this record's author added the `recorded` and
  `spectral` items and the runtime (section 6).
- The runs (the examples agent, on the fixed tree; the host is not named in
  the report): (a) a copy of the example with `rule = :spectral` (the file's
  default stays `:white`), CUDA chosen by `:auto`, exit 0, 1:25 wall; the
  provenance names e.g. `spectral(pink; sigma=1.0e-5,
  band=1.52587890625e-5..0.5, turns=1048576, seed=123456789, rng_id=11,
  slot=1, amplitudes=fixed)`; the rms rows "no pin (partial period: 2 of
  1048576 table turns)". (b) The harness, every run exit 0: CPU pink at 2
  turns (58 s), its `CRAB-NOISE` line `rule=spectral ... turns=2
  n_macro=10000 ... seed=123456789 ... ranks=1 threads=16
  steady_ms_per_turn=NA record=true rms_tccb_phase_noise_1=1.0e-5
  rms_tccb_phase_noise_2=1.0e-5 rms_tccb_strength_noise_1=0.0001
  rms_tccb_strength_noise_2=0.0001 rms_tcca_phase_noise_1=1.0e-5
  rms_tcca_phase_noise_2=1.0e-5 rms_tcca_strength_noise_1=0.0001
  rms_tcca_strength_noise_2=0.0001 spectrum=pink band=1.52587890625e-5,0.5
  amplitudes=fixed`; CUDA pink (1:23), the same fields, all eight series
  bitwise, ratio 1.0; MPI on two ranks, pink (the `MPICH_jll` `mpiexec`,
  package mode, `--threads=4`, 37 s), `ranks=2 threads=4`, rank 1 tracked
  its shard, rank 0's checks green, one artifact; CPU flat over `(3e-3,
  4e-3)` at 65536 turns and 1024 macroparticles (3:51 wall, `execute!` 187
  s), `rms_* = 1.0e-5` and `0.0001` exactly, K = 66 bins, no warning; CPU
  Rayleigh pink at 4096 turns (1:10), ratios 0.899-1.123 printed with the
  flat-band one-sigma 0.0110 (K = 2048), no pin. (c) The validation `noise`
  part: the validation row of section 2.1. (d) The stage runner from the
  worktree's `test/`: "Every example script runs against the current
  interface" green, 21 of 21, 9m17.4s (the crab example 81.5 s, the crab
  harness 55.7 s). (e) Red probes (scratch preambles, not suite tests; the
  harness at `rule spectral flat 3e-3,4e-3`, 4096 turns): an entry nudged
  by one ulp, "the recorded series differs from the record's first 4096
  entries; first difference at entry 1: ..."; a shortened series, "the
  recorded series has 4095 entries for a run of 4096 turns"; a wrong
  amplitude (the synthesis scaled by 1.001), "rms 1.0009999999999999e-5
  against sigma 1.0e-5, ratio 1.001, outside 1 +- 1e-9 ... the analytic
  normalisation did not hold"; the validation probes at `turns=1024`: the
  nudge FAILs bitwise in all three cases, the amplitude FAILs with "max
  relative error 2.001e-03" and "rms == sigma +1.000e-03" on both fixed
  cases, while the Rayleigh statistics, five-sigma pins, do not see 0.1 %,
  as designed. Not done by the examples agent: the full gate; MPI at two
  ranks only.
- Defects met on the way: none reported by the examples agent.

## 4 The review and its fixes

A read-only review of the implementer's diff against the design note's
decisions, run 2026-10-16 after the implementation landed (the examples
agent's update is reviewed separately, section 3), found the logic sound:
the D5 synthesis (odd and even `N`, the Nyquist sign, the DC bin, `Float32`,
`sigma = 0`, the hertz path); the single resolution site (the wrap
construction of `compile_runtime`, `src/knowledge/Knowledge.jl` lines
1397-1399, `_turn_modulation_wrap(resolved, T(resolved, method_object))`
innermost of the three wraps, reached through `BeamLine`, the misaligned
placements and both task kinds and reused by `_survey_rebind`; no
`SpectralNoise` leaks into a compiled line; the wrapper type identical to
one built around a hand-made table; `update_line` at 0 B); the seed timing
(the runtime cache keys on the knob epoch, the spec epoch and the loss
record, never on the seed, so the compile-time seed behaviour holds by
construction); the warnings' per-element semantics; the collector refactor
(`_each_turn_rule_spec`: the same shapes, order and semantics); the arity at
every caller; `_RA_KINDS` correctly without a `:spectral` kind (the artifact
records kind `table`); the tests' negative controls and `K_eff` bounds; no
digest pinned; the metadata and help; the cost (71 ms at 2^20 turns and
1.56 s at 2^24 on the reviewer's run; FFTW single-threaded, so the bits do
not depend on the thread count). Five findings and four nits, all fixed the
same day by a fixer and re-verified (every location below checked on the
worktree):

- F1 (HIGH, confirmed by running): two `SpectralNoise` with one explicit
  `rng_id` on two slots of ONE element resolved to identical tables with no
  warning, because the synthesis keyed on `(seed, rng_id, bin)` only, while
  the live rules key on the slot as well (`_RULE_COMPONENT_BASE + slot`) and
  promise independent draws per entry under one id; the equal-digest
  warning is per element, so one element's two equal tables read to it as
  the deliberate common-mode choice its docstring exempts. Fix, landed: the
  factory gains `slot` (default 0, offline tables unchanged) entering the
  counter-RNG key in the TURN field (`_spectral_slot`, `turn_modulated.jl`
  384-390; `_spectral_synthesis(plan, seed, rng_id, slot, amplitudes, T,
  name)` 502-531 keying `octopus_uniform01(seed, RNG_PHILOX, slot, rng_id,
  k, 1)` and `octopus_normal_pair(seed, RNG_PHILOX, slot, rng_id, k, 2)`;
  `spectral_turn_table(...; slot=0, ...)` 694-698 forwarding to the shared
  body `_spectral_table(who, spectrum, sigma, band, turns, seed, rng_id,
  slot, f_rev, amplitudes, T, name, warn)` 706-720); the resolution passes
  each rule's slot (`_resolve_turn_rule(rule, slot, T)` and
  `_resolve_turn_rules(rules, first_slot, T)` 832-839, the two-argument
  forms removed and only three-argument call sites left in `src/`:
  crab_cavity.jl 382-385, phase from slot 1 and strength from `N + 1`, with
  the docstrings 290-301 and 357-369; rf_cavity.jl 527-529, phase 1 and
  strength 2, with the docstring 509-513); the canonical name gains
  `slot=<s>` after `rng_id=` (`_spectral_name(label, sigma, lb, ub, N, seed,
  rng_id, slot, amplitudes)`, 395-398); the key-layout comment rewritten
  (124-147: the slot in the turn field; disjoint from the rules by particle
  index `k >= 1` against 0 and components 1 and 3-4 against the band `>=
  1024`; offline slot 0 keeps the `Beam` turn-0 coincidence, slot >= 1
  never touches turn 0 and under one shared id shares turn-`slot` cells
  with radiation particle `k` and BPM occurrence `k`, as the older classes
  already do among themselves); the docstrings of `spectral_turn_table`
  (579-591, 627-638, 656-664) and `SpectralNoise` (758-768). Offline tables
  bitwise unchanged against six pre-fix tables, digests unchanged.
  Regressions: the producer testset's `slot` block (10973-11003), the
  consumer testset's section (f) (11533-11570: crab two phase slots, phase
  plus strength, RF both slots under one explicit id, distinct digests and
  a correlation at most 0.147 in magnitude at `K_eff` 372.6), the ties
  through slots 1 and 2 (11421-11449) and `phase_noise[2]` at slot 2
  (11462-11470), `slot=1` in the recorded provenance name (11487).
- F2 (LOW, confirmed): the few-bins warning's `maxlog = 1` keyed on `(K, N,
  lb, ub)` silenced later rules with another `sigma` or spectrum. Fix,
  landed: `_spectral_plan(who, spectrum, sigma, band, turns, f_rev,
  amplitudes, warn::Bool)` (425), `true` from the constructor (805) and the
  factory (697), `false` from `_resolve_turn_rule` (837); `maxlog` and `_id`
  dropped (455-460); the rule warns at construction and the resolution
  never. Regression 11180-11204 (three few-bin constructions, three
  warnings; a construction plus two compiles, one).
- F3 (LOW, plausible): the consumer testset's `reset_rng_id_counter!(0)`
  could make later auto-assigned ids collide with explicit ids,
  order-dependently. Fix, landed: deleted; no reset left in the suite (the
  comment at 11410-11412 says why, every id assertion relative).
- F4 (LOW): the `ParamMeta` meanings and the `construction_help` are
  hand-written rule lists, not derived from `_turn_rule_names()` (section
  1's rule bullet says so); the tripwire covered the `construction_help`
  and the `phase_noise` meanings only. Fix, landed: tripwire (j) extended to
  the `strength_noise` meanings of both kinds (10456-10462, the loop
  10492-10495); it caught the crab's strength meaning lacking `PinkNoise`,
  fixed at crab_cavity.jl 244.
- F5 (LOW): the `SpectralNoise` docstring names the loss-record identity as
  the third recompile trigger (767-774): a re-run on a beam of another
  shape or backend recompiles and re-synthesises under the then-current
  seed, the receipt's name showing the seed (D11's dated remark).
- Nits, landed: a non-callable custom `S` refused by name through
  `applicable` (453-456; D6); the `_turn_rule_names` docstring quotes no
  literal (932-942); the `AbstractTurnRule` root docstring names
  `SpectralNoise` (86-87); the Rayleigh modulus at the Nyquist bin is
  Rayleigh rather than half-normal, expectation unaffected, said in the
  factory docstring (647-651; D5); the transient synthesis memory, 4.66
  times the table (37.3 MiB for 8 MiB at 2^20, 159.2 MiB at 2^22), reduced
  to 3.0 times (24.0 MiB; 96.0 MiB at 2^22) by keeping `bins` as a UnitRange
  and no amplitude vector (`_spectral_bin_frequency` 404), 0.070 to 0.063 s
  `:fixed` and 0.086 to 0.082 s `:rayleigh` at 2^20 (the `_spectral_synthesis`
  docstring 495-499); on heterogeneous MPI ranks each rank's FFTW may differ
  in the last bits (D9's dated remark, not a code change).

The fixer's verification: the red log on the pre-fix tree, 4 passed and 6
failed each for the defect's reason (equal digests, correlation 1.0; F2
"1 == 3"), 10 of 10 after; the stage runner after the fixes with CUDA
active: producer 382 of 382, consumer 98 of 98, rules 536 of 536, RF 147,
provenance 127, realised modulation 268, the one-particle probe 376, slot
bounds 26, kernel boundary 57, CPU/CUDA identity 39; `validate_element_metadata()`
passed; all six `element_help` forms name every rule; the snapshot
regenerated equal to the tracked file; the sweeps exit 0.
`docs/experiences.md` gained the F1 lesson, "A new consumer of a keyed RNG
must carry every dimension the existing promise spans", written by the
coordinator (line 1569 in the worktree).

## 5 Verification and gate

Matrix classes, read from the planned diff and to be confirmed against
`git diff --name-only` on the batch's commit: public documentation and APIs
(a new exported function with its docstring, the `docs/public_api.md`
paragraph, the docs index entry, the snapshot unchanged: full gate); test
infrastructure (`test/runtests.jl` gains two testsets: the skip banner still
appears; full); examples (the example, the harness and the catalogue entry
change: the script runs, the catalogue entry; example execution is
full-lane only; the examples agent's stage-runner run of the example testset,
21 of 21, section 3, the full gate owed); validation (the `noise` part's new item: the script
reproduces and its record is committed here, before the commit carrying the
claim); element kernels and `compile_runtime` (D11: the cavity's
`compile_runtime` resolves the rule into a table, the kernels untouched):
`validation/tracking_backend_consistency.jl` and the symplecticity case,
full; element spec, metadata and help output (D11: the rule joins the
kinds the `phase_noise` and `strength_noise` parameters accept):
`validate_element_metadata()`, both `element_help` forms and the snapshot,
full; symbol, arity and launch sites: two new symbols
(`spectral_turn_table`, `SpectralNoise`), nothing removed or renamed, no
launch site (a repo-wide `src/` grep for each names the definition, the
export and the callers: the grep on the fixed worktree, 2026-10-16: `src/elements/turn_modulated.jl` 40 lines, the definitions, the export, the key layout, the docstrings and the resolution; `src/elements/crab_cavity.jl` 7 and `src/elements/rf_cavity.jl` 6, the metadata, the wrap comments and the resolution calls; `src/tasks/Tasks.jl` 2, the warning docstrings; `src/examples/Examples.jl` 1, the examples agent's catalogue entrythe examples agent's catalogue entry); contracts,
tolerances, acceptance and rejection: no existing
acceptance or rejection changes, the refusals being a new function's and the
equal-digest warning additive (the review confirmed it: the warnings' per-element semantics sound, the tests probing the task constructor's warnings in both new testsets; F1's fix adds the factory keyword `slot` with default 0 and a `slot=` field to the canonical name, no name being pinned outside this batch; offline tables bitwise unchanged against six pre-fix tables, the fixer); concurrency
surfaces: none (host-side construction code, no worker closure, no
reduction, no counter-RNG change; the `Core.Box` sweep runs in the gate
regardless); CUDA-reachable code: none, the table reaching the device
through the existing `TurnTable` conversion, beyond the CUDA arm of check 7
(the review confirmed it: no `SpectralNoise` leaks into a compiled line, the wrapper type identical to one around a hand-built table), so the gate runs with CUDA active and the
backend-consistency scripts are not owed by this class; public
configuration: none (no policy, solver, task or output option;
`validate_configuration_metadata()` runs in the gate). Docs plus source: the
full gate at four threads, CUDA active, in both CPU arms (native and the
AVX2 parity arm) on the batch's final tree before the push, THE ARMS RUN ONE
AFTER THE OTHER: two suites in one worktree raced in the example testset's
cleanup on 2026-10-15 (the precedent's section 5; the `docs/todo.md` row of
that date). Baseline: the precedent's gate, 334 rows and 150148 assertions
per arm on 77c0bcc.

```bash
julia --project=. --threads=4 -e 'using Pkg; Pkg.test(julia_args=["--threads=4"])'
OPENBLAS_CORETYPE=Haswell julia -C haswell --project=. --threads=4 \
  -e 'using Pkg; Pkg.test(julia_args=["--threads=4", "-C", "haswell"])'
```

Before the gate, on the final tree: the extracted sweeps (the stage 6 pin
tripwire, the `Core.Box` sweep, the detached-docstring sweep), the fast lane,
and the registry snapshot regenerated against the tracked file. Gated: c3c6c2c, the batch's commit, `git status` clean at the start of both
arms (`dirty=0` and `dirty=0` in the logs' first lines); host
acnlinj4 (Xeon Gold 6430, sapphirerapids; RTX 4500 Ada; julia 1.12.4). The
extracted sweeps on the final source tree: exit 0 (the stage 6 pin
tripwire, the `Core.Box` sweep and the detached-docstring sweep 2 of 2
each). The fast lane on the final tree, 02:09:08 to 02:29:42 EDT: 321 rows,
148621 assertions passed, 1 `@test_skip` (the RF testset's second-thread
tripwire, which both full arms run), 16 loud lane skips. The registry
snapshot regenerated identical to the tracked file (the implementer's and
the fixer's checks).

| arm | start (EDT) | end (EDT) | rows | assertions | exit |
|---|---|---|---|---|---|
| native | 02:30:10 | 03:21:28 | 336 | 150700 of 150700 | 0 |
| AVX2 parity (`OPENBLAS_CORETYPE=Haswell`, `-C haswell`), started after the native arm ended | 03:21:28 | 04:12:11 | 336 | 150700 of 150700 | 0 |

Against the baseline of the stage 1 record batch (334 rows, 150148
assertions per arm on 77c0bcc) this batch adds 2 rows (the two
spectral testsets) and 552 assertions, identically in both arms.
Every CUDA-gated testset reports its assertions and neither log carries a
skipped, not-exercised or lane-skip line; nothing was skipped; no red
attempt (the arms ran one after the other, as the 2026-10-15 race demands).
One summary row in each log, "Element parameters carry their own number
type" (29 of 29), is split by an interleaved method-overwrite warning from
the suite's `BPMObserver` schema redefinition, its numbers standing on the
following line; a log artefact of buffered stderr, counted from that line.
The push: c3c6c2c and this record commit, pushed together right after this
commit on the owner's authorisation of 2026-10-16 ("After the test pass,
please push too"); the CI run's number, runner class, duration and stage 6
identity pins go into the `docs/todo.md` row by the next bookkeeping
commit, and CI covers the CPU testsets only, having no GPU. Not verified:
CI on this tree at this writing; the strong-strong recorder on CUDA
(unchanged since the stage 1 record); the last-bit agreement of FFTW
across heterogeneous MPI ranks (D9, not exercised: the two-rank arms ran
on one host); the example's `:spectral` configuration inside the suite (the
example and harness defaults stay `:white`, so the suite's example testset
ran them white; the spectral arms ran outside the suite, section 3, and
the rule's own coverage is the two spectral testsets).

## 6 Ledger

- `docs/todo.md`: the spectral producer row's state reads "stage 1 in
  progress 2026-10-16 (record `history/spectral_turn_table_2026_10_16.md`)"
  at this writing, its three cells kept; the record commit changes it to
  "stage 1 landed as c3c6c2c, gated 2026-10-16 in both CPU arms with CUDA
  active, the arms one after the other, and pushed"; the batch opens no
  row.
- `docs/README.md`: this record indexed in the history section after
  `turn_modulation_record_2026_10_15.md`; the design-note entry for
  `spectral_turn_table.md` reads "stage 1 in progress 2026-10-16" with the
  record's name and the section 9 decisions.
- `docs/design/spectral_turn_table.md`: the status line reads "decided by
  the owner 2026-10-16 ... stage 1 in progress 2026-10-16"; each of section
  9's six questions carries the owner's dated decision, the questions
  themselves standing (Q1 extended by D11); D11 added as the owner's
  decision of 2026-10-16 (the rule `SpectralNoise`, its resolution at
  compile, the factory's `rng_id` keyword); D4, D5 and D7 carry dated
  remarks (the `rng_id` keying and claim, the `amplitudes` keyword with the
  two meanings of `sigma`, the name's `rng_id=` and `amplitudes=` fields);
  section 4 shows the rule first and the factory second; section 5 names
  where the rule lives; section 6 gains items 9 (the Rayleigh statistics
  with the corrected tolerances) and 10 (the tie) and item 4 reads
  `rng_id + 1`; section 7 says the example builds `SpectralNoise`.
- `docs/design/turn_modulation.md`: section 6's dated pointer sentence says
  the implementation is in progress 2026-10-16; section 10's stale
  "(2026-10-15, not implemented)" about the record note now reads "stage 1
  landed 2026-10-15 as 77c0bcc, pushed as a710f5a" (the coordinator's
  correction of 2026-10-16).
- `docs/public_api.md`: the implementer's help entries (lines 213-214) and
  paragraph (lines 221-261), section 1's documents bullet; the example
  paragraph below them (from line 283) gained, by this record's author on
  2026-10-16, the spectral rule in the switch list, the three harness
  toggles read under `OCTOPUS_NOISE_RULE=spectral` and the `CRAB-NOISE`
  line's trailing fields `spectrum= band= amplitudes=`.
- `validation/README.md`: the crab-noise section's part `noise` describes
  the `recorded` item (2026-10-15) and the `spectral` item, its runtime
  reads "about two and a half minutes" and the outputs list names the
  recorded artifacts (this record's author, 2026-10-16).
- `docs/experiences.md`: the entry "A new consumer of a keyed RNG must carry
  every dimension the existing promise spans", written by the coordinator
  (line 1569 in the worktree; the F1 lesson of section 4).
- Markers: section 1's `impl` markers and the `tests` markers of sections
  1 and 2 were filled on 2026-10-16 from the implementer's report, the
  `review` markers the same day from the reviewer's findings and the fixer's
  report, each code location checked against the landed source in the
  worktree (the line numbers of sections 1 and 4 are the fixed tree's; the
  implementer's pre-fix numbers, such as the preset table at 292, were
  replaced) and each runtime number attributed to its run; section 3's
  `examples` markers were filled on 2026-10-16 from the examples agent's
  report with every file location checked in the worktree (the runs'
  numbers are the agent's); the `gate` markers of sections 5 and 6 are to be
  filled from the two arms' logs after the run, the push and the CI run, by
  the record commit and the bookkeeping commit that follows it.
