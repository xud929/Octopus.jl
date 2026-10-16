export TurnModulated, WhiteNoise, PinkNoise, TurnTable, SpectralNoise, spectral_turn_table, update, update_line, realize

# ---------------------------------------------------------------------------
# Turn-by-turn modulation: a parameter that takes a different value on every
# turn of one tracking run (crab cavity RF phase and amplitude noise first).
#
# Design: `docs/design/turn_modulation.md` (decisions D1-D8, measured costs,
# the rule catalogue). The shape, in one paragraph: the variation is
# element-owned per-turn STATE realised once per turn on the host (D1), from
# the compiled runtime object and the `TrackingContext`, never from the spec
# (D2); the per-turn hook `update(elem, ctx)` is PURE and type-preserving and
# every segment's element tuple is rebuilt each turn with `ntuple(..., Val(N))`
# (D3, section 7: 20 ns and zero allocation for 40 elements; `map` over a
# tuple of 32 or more entries allocates); no new runtime cavity -- `TurnModulated`
# is the third compile-time wrapper beside `MisalignedElement` and `RefTilted`
# and forwards tracking to the REALISED element (D4); nominal and realised
# stay separate so the contextless `track!` path, where no update ever runs,
# tracks the noiseless element (D5, the RF-cavity lesson); rules may carry
# state but need not (D6); the table rule is a pure consumer of per-turn
# values in the slot's own unit -- offsets in rad on a phase, dimensionless
# relative factors on a strength, realised as `S (1 + d)` (D7, owner
# decision; the strength relative since 2026-10-15, before that one offset
# added to both planes); the rule
# never reaches the device -- the kernel sees only the realised element (D8).
#
# One deliberate deviation from the note's field names: the realised element
# is the field `inner`, not `current`. Every walk that unwraps a wrapper by
# STRUCTURE rather than by a hand list (`_compiled_matches_runtime` in
# `src/knowledge/Knowledge.jl`, 2026-08-05_b audit U12-10) looks for a field
# named `inner`, and the suite's derived wrapper set uses the same rule, so
# the name is what makes this wrapper a sibling to those walks for free.
#
# Where the pieces live:
#   - this file: the rules (`WhiteNoise`, `PinkNoise`, `TurnTable`; the spec-level
#     `SpectralNoise`, resolved to a `TurnTable` at compile by `_resolve_turn_rule`,
#     and its offline form `spectral_turn_table`), the scalar rule
#     interface `_turn_offset`, the element-level `realize` and the one
#     evaluation behind it, `_realize_draws` (the realised element, the
#     successors AND the draws, so the run artifact's recorder shares the
#     evaluation that built the element: `docs/design/turn_modulation_record.md`
#     D5), the wrapper and its forwards, the pure hook `update` / `update_line`
#     in its plain and its recording (`sink`) forms, the SLOT PROTOCOL
#     (`_slot_rules` and `_slot_nominals` on a rule container,
#     `_turn_rule_values` on a spec) and
#     the walks generic over it: the window check `_check_turn_window`
#     / `_check_container_window`, the provenance slots
#     `_turn_modulation_slots`, the recorder's columns
#     `_turn_modulation_columns!`, the modulation-stream collector
#     `_collect_turn_modulation_ids!`;
#   - `src/elements/crab_cavity.jl`: the crab cavity's rule container
#     `CrabCavityNoise` (2N slots), its `_realize_draws` / `realize`,
#     `_turn_modulation_wrap` for
#     the kind, its `_slot_rules` / `_slot_nominals` / `_turn_rule_values`,
#     the per-harmonic
#     `phase_noise` / `strength_noise` tuples and their metadata;
#   - `src/elements/rf_cavity.jl`: the thin RF cavity by the same wrap (stage
#     3): `RFCavityNoise` (two scalar slots, phase then strength), its
#     `_realize_draws` / `realize`, `_turn_modulation_wrap`, `_slot_rules` /
#     `_slot_nominals` / `_turn_rule_values`,
#     the scalar `phase_noise` / `strength_noise` parameters; the accelerating
#     cavity gets no rule (single-pass);
#   - `src/tasks/RunArtifact.jl`: the series recorder (`TurnModulationRecorder`,
#     the sink the recording hook hands each element's draws to, the
#     `record_turn_modulation` option, the `series` dataset and the nominal
#     attributes beside the provenance, the extended readers);
#   - `src/knowledge/Knowledge.jl`: `compile_runtime` applies
#     `_turn_modulation_wrap` INNERMOST, then the misalignment, then the roll;
#   - `src/tasks/Tasks.jl`: the two turn loops call `update_line` (the
#     general loop's segments in the recording form, with the artifact's sink
#     or `nothing`), the
#     segments hold their tuple in a `Base.RefValue`, `execute!` runs the
#     window check before the first turn and records the provenance receipt,
#     the task constructor warns on duplicate modulation streams, and the
#     wrapper joins `_survey_rebind`, `_descend_strong_beams!`,
#     `_hidden_strong_beam_count`;
#   - `src/track/phase6d_track.jl`: the device conversion drops the wrapper
#     to its realised element (`Adapt.adapt_structure`), so the fused tuple
#     handed to CUDA never carries a rule;
#   - `src/registry/Registry.jl`: the wrapper is a runtime object of the
#     snapshot; `src/elements/aperture.jl`: `_requires_tracking_context`.
# ---------------------------------------------------------------------------

"""
    AbstractTurnRule

The root of every per-slot turn-modulation rule (`WhiteNoise`, `PinkNoise`,
`TurnTable`, `SpectralNoise`). A concrete rule defines `_turn_offset` (its value on one turn,
which the element's `realize` adds to a phase or scales a strength by as
`S (1 + d)`) and `_rule_kind` (its provenance kind label). The rule catalogue is
DERIVED from the concrete subtypes of this root (`_turn_rule_names`, the crab
cavity's `_is_turn_rule`, the generic `_push_rule_slot!`, the suite's catalogue
tripwire), never hand-copied into a case list.
"""
abstract type AbstractTurnRule end

# The key layout of the counter RNG, `octopus_normal(seed, method, turn,
# rng_id, particle_slot, component, T)`, as used in this tree. What separates
# one stochastic consumer from another is the CLAIMED `rng_id` (`next_rng_id!`
# assigns a fresh stream, `claim_rng_id!` records an explicit one so the
# counter never reissues it) and the method tag; the cells below are NOT
# disjoint among the three older classes on one shared id -- the Beam initial
# distribution and radiation share their turn-0 cells (the U14-2 pair
# `claim_rng_id!` was written for), and a BPM's occurrence o >= 1 shares
# radiation particle o's components 1-2 on every turn (measured 2026-10-13,
# neighbour audit U7-2/U7-7: 62 cross-consumer cell equalities among those
# three, ledgered). What the layout DOES separate is the rules from every
# other class: particle slot 0 with a component in the band `>=
# _RULE_COMPONENT_BASE` is a cell no other consumer draws (0 of the 62
# equalities involve a rule), and within one element the pink stride keeps
# the pink generators apart from each other and from the white slots while
# the container has at most `_PINK_COMPONENT_STRIDE` slots -- enforced at the
# wrap by `_check_slot_rules` (below), not assumed.
#   - the Beam initial distribution (`src/beam/Beam.jl`): turn 0, particle
#     slot = the particle index (>= 1), components 1-6 (the coordinate);
#   - radiation (`src/elements/radiation.jl`): particle slot = the particle id
#     (>= 1), components 1-6;
#   - the BPM reading noise (`src/tasks/BPMObserver.jl`): particle slot = the
#     reading's occurrence within the turn (0, 1, ...), components 1-2;
#   - the turn-modulation rules (this file): particle slot 0, components in
#     the band `_RULE_COMPONENT_BASE + slot` (white) and
#     `_RULE_COMPONENT_BASE + slot + _PINK_COMPONENT_STRIDE * (k + 1)` (pink
#     generator k), `slot` being the element's parameter slot (`1:2N` on a
#     crab cavity, 1-2 on an RF cavity).
#   - the spectral tables (`spectral_turn_table`, host-side, under its own
#     `seed` and `rng_id` arguments; `SpectralNoise` under the global seed at
#     compile and its claimed `rng_id`): the TURN field carries the table's
#     SLOT -- 0 for an offline table, the rule's slot (`1:2N` on a crab
#     cavity, 1-2 on an RF cavity, the numbering of `_slot_rules`) when
#     `_resolve_turn_rule` synthesises it (review F1, 2026-10-16: keyed on
#     `(seed, rng_id, bin)` alone, two rules sharing one explicit id on two
#     slots of ONE element were one table, silently) -- particle slot = the
#     frequency bin k (>= 1), component 1 for the bin's phase and the
#     Box-Muller pair 2 (components 3-4) for a Rayleigh modulus. Disjoint
#     from the rules above on every slot (particle index k >= 1 against the
#     rules' 0; components 1 and 3-4 against the band `>=
#     _RULE_COMPONENT_BASE`), so a table and a rule never share a cell
#     whatever their ids. Offline slot 0 keeps the documented coincidence
#     with a Beam's turn-0 initial-distribution cells for particle k under
#     the same seed and rng_id (an offline table's (seed, rng_id) must not
#     repeat the task seed with a beam's rng_id; design D4, the keying of the
#     section 6 sketch of docs/design/turn_modulation.md); a resolved table
#     (slot >= 1) never touches turn 0 and cannot meet them, while under one
#     shared id it shares turn `slot`'s cells with radiation particle k and
#     the BPM's occurrence k, as the three older classes already share among
#     themselves.
# Without the base (review finding S1, 2026-10-12) a white rule on slot 1 or 2
# and a noisy BPM's occurrence 0 sharing an `rng_id` drew the SAME normal.
const _RULE_COMPONENT_BASE = 1024
# The component band of a pink rule's K generators: generator k of slot s draws
# component `_RULE_COMPONENT_BASE + s + _PINK_COMPONENT_STRIDE * (k + 1)`, while
# a `WhiteNoise` on slot s draws `_RULE_COMPONENT_BASE + s`. White components
# and pink bands stay disjoint only while the container's slots number at most
# `_PINK_COMPONENT_STRIDE`: on slot `s + 64` a white rule draws pink slot s's
# generator 0 and a pink rule its generators shifted by one (measured 2026-10-13,
# neighbour audit U7-1: a 33-harmonic crab cavity, 66 slots, drew identical
# normals on 64 of 64 turns). ENFORCED, not assumed: the two-argument
# `TurnModulated(base, rule)` constructor runs `_check_slot_rules`, which
# refuses a container of more than this many slots carrying a `PinkNoise`.
const _PINK_COMPONENT_STRIDE = 64

"""
    _rule_stream_id(rng_id) -> UInt64

The stream id a stochastic rule's keyword constructor records: `0` assigns a
fresh stream (`next_rng_id!`); an explicit id is claimed (`claim_rng_id!`) so
the auto-assign counter never reissues it, as `LumpedRadSpec` and
`BPMObserver` do (`src/elements/radiation.jl`; 2026-08-05_b audit U14-2).
Anything but a non-negative integer is an `ArgumentError` naming the keyword
and the value, raised BEFORE any stream is claimed (a negative id once died in
`UInt64` with an `InexactError`, a non-integer one in the keyword's type;
2026-10-13 neighbour audit, U7-6).
"""
function _rule_stream_id(rng_id)
    (rng_id isa Integer && rng_id >= 0) || throw(ArgumentError(
        "rng_id must be a non-negative integer (0 assigns a fresh stream, an explicit " *
        "id is claimed); got $(repr(rng_id))"))
    return rng_id == 0 ? next_rng_id!() : claim_rng_id!(rng_id)
end

# The shared guard of the stochastic rules' `sigma`. The keyword constructors
# run it BEFORE `_rule_stream_id`, so a refused rule claims no stream.
function _check_rule_sigma(rule::String, sigma::AbstractFloat)
    isfinite(sigma) || throw(ArgumentError("$(rule): sigma must be finite; got $(sigma)"))
    sigma >= 0 || throw(ArgumentError("$(rule): sigma must be non-negative; got $(sigma)"))
    return nothing
end

"""
    WhiteNoise(sigma; rng_id=0)

A per-turn value drawn once per turn from a standard normal scaled by
`sigma`, in the slot's unit: an offset in rad added to a phase; on a strength
a dimensionless relative factor `d`, realised by the element as `S (1 + d)`,
so `sigma` IS the relative rms of the strength (relative, 2026-10-15).
Stateless: the draw is the Octopus counter RNG
(`octopus_normal`, Philox4x32) keyed on `(seed, turn, rng_id)` with the
particle-index slot fixed at 0 and the component `_RULE_COMPONENT_BASE + slot`
(the band reserved for the rules; the key layout is documented above), so the
sequence is a function of the task's seed, the absolute turn and `rng_id`,
identical on every backend and whether the run is one `execute!` or many.
`slot` is supplied by the element that owns the rule (the crab cavity uses the
harmonic index for a phase and `N + harmonic` for a strength; the RF cavity
slot 1 for its phase and 2 for its strength), so one `rng_id`
on every entry of one cavity still gives independent draws per entry; two
CAVITIES sharing an `rng_id` draw identical values and the task constructor
warns, as it does for two radiation placements sharing a stream. `rng_id = 0`
(the default) assigns a fresh stream; an explicit id is claimed so the
auto-assign counter never reissues it, as `LumpedRadSpec` and `BPMObserver` do.
`sigma` must be finite and non-negative; zero is a quiet rule (the realised
value equals the nominal one). `sigma` is converted to the element's numeric
type at realisation (a `Float32` sigma on a `Float64` cavity is promoted),
while a `TurnTable` is refused on a type mismatch because its storage would
otherwise be copied silently -- the asymmetry is deliberate.
"""
struct WhiteNoise{T<:AbstractFloat} <: AbstractTurnRule
    sigma::T
    rng_id::UInt64
    function WhiteNoise{T}(sigma::T, rng_id::UInt64) where {T<:AbstractFloat}
        _check_rule_sigma("WhiteNoise", sigma)
        return new{T}(sigma, rng_id)
    end
end
function WhiteNoise(sigma::Real; rng_id=0)
    s = float(sigma)
    _check_rule_sigma("WhiteNoise", s)
    return WhiteNoise{typeof(s)}(s, _rule_stream_id(rng_id))
end

"""
    TurnTable(offsets::AbstractVector{<:AbstractFloat}; name="")

A per-turn table of values in the slot's own unit -- on a phase slot offsets
in rad, added to the phase; on a strength slot dimensionless RELATIVE factors
`d`, realised by the element as `S (1 + d)` (relative, 2026-10-15; the phase
stays additive) -- where entry `i` is the value applied on ABSOLUTE turn
`i - 1` (one-based storage of the task's zero-based turn), so the first entry
is the first turn of the run and a checkpoint restored with `start_turn = N`
reads entry `N + 1`. Stateless: the table is data.

A pure CONSUMER (design decision D7, owner, 2026-10-12): spectrum synthesis,
the revolution frequency, unit conversion, normalisation, Gaussianity and
periodicity are the producer's; this rule neither checks nor claims them. It
owns exactly the value-as-is semantics (an entry is applied unscaled, by the
element's `realize`), the absolute-turn indexing, the
guardrails (length at least one, every entry finite, element type equal to
the line's numeric type -- a `Float32` table on a `Float64` line is refused
at compile, no silent promotion) and provenance: `digest` (FNV-1a 64 over
the raw bytes, stable across sessions and Julia versions) and `name` are
recorded in the run's provenance receipt. Before the first turn of every
`execute!` window the task checks `first_turn + turns <= length(offsets)`
and throws otherwise, so a run never runs out mid-window and never wraps
(a wrapped sequence is periodic in the table length and would correlate
turn `t` with turn `t - N` silently).
"""
struct TurnTable{T<:AbstractFloat} <: AbstractTurnRule
    offsets::Vector{T}
    digest::UInt64
    name::String
end

function TurnTable(offsets::AbstractVector{T}; name::AbstractString="") where {T<:AbstractFloat}
    length(offsets) >= 1 || throw(ArgumentError(
        "TurnTable: the table must hold at least one turn; got an empty vector"))
    bad = findfirst(!isfinite, offsets)
    bad === nothing || throw(ArgumentError(
        "TurnTable: every entry must be finite; entry $(bad) is $(offsets[bad])"))
    vec = collect(offsets)
    return TurnTable{T}(vec, _fnv1a64(reinterpret(UInt8, vec)), String(name))
end

"""
    _fnv1a64(bytes) -> UInt64

FNV-1a, 64-bit, over a byte vector: the content digest a `TurnTable` records
as provenance. Chosen over `hash` because `Base.hash` is not stable across
Julia versions and the digest is written into run artifacts and records.
"""
function _fnv1a64(bytes::AbstractVector{UInt8})
    h = 0xcbf29ce484222325
    for b in bytes
        h = (h ⊻ UInt64(b)) * 0x100000001b3
    end
    return h
end

# ---------------------------------------------------------------------------
# The spectral producer (`docs/design/spectral_turn_table.md`, D1-D10; owner's
# go-ahead 2026-10-15, stage 1 2026-10-16): one synthesis body behind two
# entries. `spectral_turn_table` builds a `TurnTable` offline from a target
# spectrum under a `(seed, rng_id)` the caller writes down; `SpectralNoise` is
# the spec-level rule that resolves into that table when the line compiles
# (`_resolve_turn_rule`, called by both cavities' `_turn_modulation_wrap`),
# under the global seed in force and a claimed `rng_id`, so at run time it IS
# a table: D7, the recorder, the probe, the provenance writer and readers are
# untouched. Host-side construction code only: not CUDA-reachable, no per-turn
# cost, no new runtime rule.
# ---------------------------------------------------------------------------

# The preset spectra: one table the docstrings' lists, `?spectral_turn_table`,
# `?SpectralNoise` and the unknown-preset refusal all derive from (never a
# hand-copied list). Each entry is the PSD SHAPE `S(f)` (D2), evaluated at the
# band's bins only, never at f = 0 (D3).
_spectral_flat(f) = 1.0
_spectral_pink(f) = 1.0 / f
const _SPECTRAL_PRESETS = (
    flat = (label = "flat", formula = "S(f) = 1, white over the band", S = _spectral_flat),
    pink = (label = "pink", formula = "S(f) = 1/f, equal power per octave", S = _spectral_pink),
)
_spectral_preset_lines() =
    join(("  - `:$(k)` -- $(p.formula)" for (k, p) in pairs(_SPECTRAL_PRESETS)), "\n")
_spectral_preset_names() = join((repr(k) for k in keys(_SPECTRAL_PRESETS)), ", ")
const _SPECTRAL_AMPLITUDES = (:fixed, :rayleigh)

# The spectrum argument resolved to `(label, S)`: a preset symbol from the
# table above, or a `"<label>" => S` pair with a non-empty label (the label is
# what the canonical name records, D7, so an empty one is refused, D6). `who`
# prefixes every refusal with the entry that raised it.
function _spectral_shape(who::String, spectrum::Symbol)
    haskey(_SPECTRAL_PRESETS, spectrum) || throw(ArgumentError(
        "$(who): unknown preset $(repr(spectrum)); the presets are " *
        _spectral_preset_names() * ", or pass a custom \"<label>\" => S pair with S the " *
        "one-sided power spectral density shape"))
    preset = _SPECTRAL_PRESETS[spectrum]
    return preset.label, preset.S
end
function _spectral_shape(who::String, spectrum::Pair{<:AbstractString,<:Any})
    label = String(first(spectrum))
    isempty(strip(label)) && throw(ArgumentError(
        "$(who): a custom spectrum needs a non-empty label (it names the spectrum in the " *
        "table's canonical name and the run's provenance); got \"\" => S"))
    return label, last(spectrum)
end
_spectral_shape(who::String, spectrum) = throw(ArgumentError(
    "$(who): spectrum must be a preset Symbol (" * _spectral_preset_names() *
    ") or a \"<label>\" => S pair with S the one-sided power spectral density shape; got " *
    repr(spectrum)))

# The band `(lb, ub)` validated and converted to cycles per turn: with `f_rev`
# the edges are in hertz and are divided by it. Returns `(lb, ub, scale)` with
# `scale` the factor that turns a bin's tune into the argument `S` sees (1 in
# tunes, `f_rev` in hertz). Every refusal carries the numbers (D6).
function _spectral_band(who::String, band, f_rev)
    (band isa Tuple && length(band) == 2 && band[1] isa Real && band[2] isa Real) ||
        throw(ArgumentError(
            "$(who): band must be a pair (lb, ub) of modulation tunes in cycles per turn " *
            "(or in hertz when f_rev is given); got $(repr(band))"))
    lo, hi = Float64(band[1]), Float64(band[2])
    (isfinite(lo) && isfinite(hi)) || throw(ArgumentError(
        "$(who): the band edges must be finite; got (lb, ub) = ($(lo), $(hi))"))
    if f_rev === nothing
        scale = 1.0
    else
        (f_rev isa Real && isfinite(f_rev) && f_rev > 0) || throw(ArgumentError(
            "$(who): f_rev must be a positive finite revolution frequency in hertz (it " *
            "converts a band given in hertz to cycles per turn); got $(repr(f_rev))"))
        scale = Float64(f_rev)
    end
    lb, ub = lo / scale, hi / scale
    hz = f_rev === nothing ? "" : " (the band $(lo)..$(hi) Hz at f_rev = $(scale) Hz)"
    lb > 0 || throw(ArgumentError(
        "$(who): the band's lower edge must be positive (the DC bin is never in the " *
        "band); got lb = $(lb) cycles per turn$(hz)"))
    lb < ub || throw(ArgumentError(
        "$(who): the band's lower edge must lie below its upper edge; got lb = $(lb), " *
        "ub = $(ub) cycles per turn$(hz)"))
    ub <= 0.5 || throw(ArgumentError(
        "$(who): the band's upper edge must not exceed the Nyquist tune 1/2; got " *
        "ub = $(ub) cycles per turn$(hz)"))
    return lb, ub, scale
end

# `seed` and `rng_id` as the counter RNG takes them: non-negative integers, a
# refusal naming the keyword rather than an `InexactError` from `UInt64`.
function _spectral_key(who::String, value, keyword::Symbol)
    (value isa Integer && value >= 0) || throw(ArgumentError(
        "$(who): $(keyword) must be a non-negative integer (the bin phases are a function " *
        "of (seed, rng_id, slot, bin) and nothing else); got $(repr(value))"))
    return UInt64(value)
end

# The table's slot, the counter RNG's turn field in its keying: 0 for an
# offline table, the rule's slot when `_resolve_turn_rule` synthesises it (the
# key layout above `_RULE_COMPONENT_BASE`; review F1, 2026-10-16).
function _spectral_slot(who::String, slot)
    (slot isa Integer && slot >= 0) || throw(ArgumentError(
        "$(who): slot must be a non-negative integer (0 for an offline table; a rule " *
        "resolved at compile passes its slot, which enters the bin keying beside seed and " *
        "rng_id); got $(repr(slot))"))
    return Int(slot)
end

# The canonical name (D7): the physics that made the table, beside its digest
# in the receipt and the artifact. Floats in shortest round-trip form, the
# band in cycles per turn whatever unit the caller used.
_spectral_name(label, sigma::Float64, lb::Float64, ub::Float64, N::Int, seed::UInt64,
               rng_id::UInt64, slot::Int, amplitudes::Symbol) =
    "spectral($(label); sigma=$(repr(sigma)), band=$(repr(lb))..$(repr(ub)), turns=$(N), " *
    "seed=$(string(seed)), rng_id=$(string(rng_id)), slot=$(slot), amplitudes=$(string(amplitudes)))"

# The frequency `S` sees for bin `k` of an `N`-turn table: the tune `k / N`, or
# `k f_rev / N` in hertz when the band was given in hertz (`scale = f_rev`).
# One expression for the plan's validation and the synthesis's amplitude, so
# the two cannot drift.
_spectral_bin_frequency(k::Int, N::Int, scale::Float64) = scale == 1.0 ? k / N : k * scale / N

"""
    _spectral_plan(who, spectrum, sigma, band, turns, f_rev, amplitudes, warn::Bool) -> NamedTuple

Everything the synthesis needs that does not depend on the keys: the resolved
`(label, S)`, `sigma` as a `Float64`, `N`, the band in cycles per turn and the
scale `S`'s argument carries, the band bins as a `UnitRange` (the `k` with
`lb <= k/N <= ub` are consecutive), whether the last bin is Nyquist and the
scale `c` of D5. The bin amplitudes `a_k = sqrt(S(f_k))` are validated and
summed here and recomputed bin by bin in the synthesis; no vector per bin is
kept (review nit, 2026-10-16: the bin and amplitude vectors were two of the
synthesis's transients). Every refusal of D6 lives here, so the factory and
the `SpectralNoise` constructor validate identically (`who` names the entry
in the messages). The fewer-than-32-bins warning is printed when `warn` is
set -- `true` from the factory and the rule's constructor, `false` from
`_resolve_turn_rule`, whose rule warned at construction -- and carries no
`maxlog`: a content-keyed `maxlog` silenced every later few-bin rule of
another `sigma` or spectrum in the same process (review F2, 2026-10-16),
while the compile path, which a knob sweep runs per step, never warns.
"""
function _spectral_plan(who::String, spectrum, sigma, band, turns, f_rev, amplitudes, warn::Bool)
    label, S = _spectral_shape(who, spectrum)
    (amplitudes isa Symbol && amplitudes in _SPECTRAL_AMPLITUDES) || throw(ArgumentError(
        "$(who): amplitudes must be :fixed (every bin at its target amplitude: exact rms " *
        "and exact periodogram) or :rayleigh (Rayleigh-distributed bin amplitudes: a " *
        "stationary Gaussian process matching the target in expectation); got " *
        repr(amplitudes)))
    (turns isa Integer && turns >= 2) || throw(ArgumentError(
        "$(who): turns must be an integer of at least 2 (the table's period, to be made " *
        "at least as long as the run); got $(repr(turns))"))
    N = Int(turns)
    sigma isa Real || throw(ArgumentError(
        "$(who): sigma must be a real rms in the slot's unit; got $(repr(sigma))"))
    s = Float64(sigma)
    _check_rule_sigma(who, s)
    lb, ub, scale = _spectral_band(who, band, f_rev)
    half = N ÷ 2
    # The band bins are the k with lb <= k/N <= ub; k/N is monotonic in k, so
    # they are consecutive and a UnitRange holds them without a vector.
    inband(k) = lb <= k / N <= ub
    kmin = findfirst(inband, 1:half)
    kmin === nothing && throw(ArgumentError(
        "$(who): no bin lies in the band lb = $(lb)..ub = $(ub) cycles per turn at " *
        "turns = $(N): the bins are k/N for k = 1, 2, ..., the first being 1/N = $(1 / N); " *
        "widen the band or lengthen the table"))
    kmax = findlast(inband, 1:half)
    bins = kmin:kmax
    K = length(bins)
    applicable(S, _spectral_bin_frequency(kmin, N, scale)) || throw(ArgumentError(
        "$(who): the custom spectrum's S must be callable on one frequency, S(f) with f a " *
        "Float64 (the one-sided power spectral density shape, evaluated on the band's bins); " *
        "got $(repr(S)), which is not"))
    if warn && K < 32
        @warn("$(who): only $(K) bin(s) lie in the band $(lb)..$(ub) cycles per turn at " *
              "$(N) turns; fewer than 32 sinusoids is a deterministic waveform rather than " *
              "noise (widen the band or lengthen the table)",
              bins = K, band = (lb, ub), turns = N)
    end
    nyquist = iseven(N) && kmax == half
    weight = 0.0
    for k in bins
        f = _spectral_bin_frequency(k, N, scale)
        v = S(f)
        (v isa Real && isfinite(v) && v >= 0) || throw(ArgumentError(
            "$(who): S(f) must be finite and non-negative on every bin of the band; bin " *
            "k = $(k) (f = $(f)$(scale == 1.0 ? " cycles per turn" : " Hz")) gave $(repr(v))"))
        amplitude = sqrt(Float64(v))
        weight += (nyquist && k == kmax ? 1.0 : 2.0) * amplitude^2
    end
    (weight > 0.0 || s == 0.0) || throw(ArgumentError(
        "$(who): S(f) vanishes on every bin of the band $(lb)..$(ub), so no table of rms " *
        "sigma = $(s) exists; pass sigma = 0 for a quiet table or a spectrum with power in " *
        "the band"))
    c = weight > 0.0 ? s * N / sqrt(weight) : 0.0
    return (label = label, S = S, sigma = s, N = N, lb = lb, ub = ub, scale = scale,
            bins = bins, nyquist = nyquist, c = c)
end

"""
    _spectral_synthesis(plan, seed::UInt64, rng_id::UInt64, slot::Int, amplitudes, ::Type{T}, name) -> TurnTable{T}

The one synthesis body (design D4, D5; the Rayleigh variant of the owner's Q3
decision; the slot in the key, review F1 2026-10-16): bin `k` of the plan
carries `c a_k rho_k cis(phi_k)` with `a_k = sqrt(S(f_k))` recomputed from
the plan's spectrum, `phi_k = 2 pi octopus_uniform01(seed, RNG_PHILOX, slot,
rng_id, k, 1)` and `rho_k = 1` (`:fixed`) or `|z_k|`, `z_k = (n_1 + i n_2) /
sqrt(2)` from `octopus_normal_pair(seed, RNG_PHILOX, slot, rng_id, k, 2)`
(`:rayleigh`); the Nyquist entry real with the sign of `cos(phi)`; zeros
elsewhere; `irfft`; conversion to `T`; the canonical name unless `name` is
given. At `slot = 0` the table is bitwise the one this body produced before
the slot entered the key. Transient memory: the complex spectrum (`8 N`
bytes), the transform's output and the table's own copy, with no vector per
bin -- measured at 2^20 turns: 24.0 MiB allocated for an 8.0 MiB table,
3.0 times its bytes, against 37.3 MiB (4.7 times) when a pushed bin vector
and an amplitude vector were kept, in 0.063 s against 0.070 s (`:rayleigh`
0.082 s; review nit, 2026-10-16).
"""
function _spectral_synthesis(plan, seed::UInt64, rng_id::UInt64, slot::Int, amplitudes::Symbol,
                             ::Type{T}, name) where {T<:AbstractFloat}
    N, bins, c, S, scale = plan.N, plan.bins, plan.c, plan.S, plan.scale
    half = N ÷ 2
    kmax = last(bins)
    rayleigh = amplitudes === :rayleigh
    X = zeros(ComplexF64, half + 1)
    for k in bins
        amplitude = sqrt(Float64(S(_spectral_bin_frequency(k, N, scale))))
        phi = 2pi * octopus_uniform01(seed, RNG_PHILOX, slot, rng_id, k, 1, Float64)
        rho = 1.0
        if rayleigh
            n1, n2 = octopus_normal_pair(seed, RNG_PHILOX, slot, rng_id, k, 2, Float64)
            rho = sqrt((n1 * n1 + n2 * n2) / 2)
        end
        magnitude = c * amplitude * rho
        if plan.nyquist && k == kmax
            X[k + 1] = complex(cos(phi) >= 0 ? magnitude : -magnitude)
        else
            X[k + 1] = magnitude * cis(phi)
        end
    end
    x = irfft(X, N)
    table = T === Float64 ? x : T.(x)
    tag = name === nothing ?
          _spectral_name(plan.label, plan.sigma, plan.lb, plan.ub, N, seed, rng_id, slot, amplitudes) :
          String(name)
    return TurnTable(table; name=tag)
end

"""
    spectral_turn_table(spectrum, sigma, band; turns, seed, rng_id, slot=0,
                        f_rev=nothing, amplitudes=:fixed, T=Float64, name=nothing) -> TurnTable{T}

Synthesise a [`TurnTable`](@ref) of `turns` per-turn values whose one-sided
power spectrum has the shape `spectrum` over the modulation band `band` and
whose rms is `sigma`, by frequency-domain shaping (Timmer and König; design
note `docs/design/spectral_turn_table.md`, decisions D1-D10). The OFFLINE
form of [`SpectralNoise`](@ref): the same synthesis under a `(seed, rng_id)`
the caller writes down, for a table built outside a line (a sweep script, a
file, a table shared on purpose). A producer on the producer's side of the
table rule's D7 boundary: the result is an ordinary `TurnTable` -- digest,
window check, recorder and provenance apply to it as to any table -- and
nothing in the runtime changes.

Arguments:

- `spectrum`: a preset symbol, or `"<label>" => S` with `S(f) >= 0` the
  ONE-SIDED POWER SPECTRAL DENSITY SHAPE of the noise. Only the shape matters
  (the level is `sigma`'s), so the unit of `f` inside `S` is irrelevant:
  `1/f` in hertz and `1/f` in cycles per turn give the same table. The
  presets, one table this list and the unknown-preset refusal derive from:
$(_spectral_preset_lines())
- `sigma`: the rms of the table over one period, in the slot's own unit:
  radians on a phase slot, the dimensionless relative factor on a strength
  slot. Finite and non-negative; `0` gives a quiet table. With
  `amplitudes = :fixed` it is the rms EXACTLY (to rounding); with
  `amplitudes = :rayleigh` it is the EXPECTED rms, the realised rms of one
  table scattering by about `1 / (2 sqrt(K_eff))` of it around that value
  (`K_eff = (sum w_k)^2 / sum w_k^2` over the band weights `w_k = 2 a_k^2`,
  the Nyquist weight `a_k^2`: the number of bins for a flat band, far fewer
  for a 1/f band whose power sits in its lowest bins).
- `band`: `(lb, ub)` in cycles per turn (modulation tunes), `0 < lb < ub <=
  1/2`. With `f_rev`, the revolution frequency in hertz, the band AND the
  argument of `S` are in hertz, `f_k = k f_rev / turns`; the canonical name
  records the band in cycles per turn either way.
- `turns`: the table length `N`, at least 2, and at least as long as the run
  (the consumer refuses a window it cannot cover; that check is the table
  rule's, not this function's). The table is periodic in `N` and holds no
  power below `1/N`.
- `seed`, `rng_id`: the keys of the bin phases (below), both mandatory, both
  non-negative integers, `rng_id` positive. NOT claimed in the stream
  registry (`claim_rng_id!`): an offline table is data, so `rng_id = 0`, the
  live rules' auto-assign, is refused by name, and the only sharing check an
  offline table gets is the task constructor's equal-digest warning -- two
  tables built with the same `(seed, rng_id)` over the same bins are the same
  noise. `SpectralNoise` on the element claims its stream like `WhiteNoise`.
- `slot`: the table's slot on its element, entering the bin keying beside
  `seed` and `rng_id` as the counter RNG's turn field; `0` (the default) for
  an offline table. `_resolve_turn_rule` synthesises a `SpectralNoise` with
  the rule's slot -- a crab cavity's phase harmonic `i` is slot `i` and its
  strength harmonic `i` slot `N + i`, an RF cavity's phase 1 and strength 2,
  the numbering of `_slot_rules` -- so one `rng_id` on several slots of one
  cavity gives INDEPENDENT tables, as it gives the live rules independent
  draws per entry, while two cavities sharing an explicit id resolve to
  identical tables slot for slot (the task constructor's shared-id warning).
  To regenerate a resolved table offline, pass the slot its canonical name
  records. (Review F1, 2026-10-16: keyed on `(seed, rng_id, bin)` alone, two
  rules sharing one id on two slots of ONE element were one table, silently.)
- `f_rev`: see `band`. `amplitudes`: `:fixed` (default) or `:rayleigh`,
  below. `T`: the table's element type (`Float32` for a `Float32` line; the
  synthesis runs in `Float64` and converts at the end). `name`: replaces the
  canonical name.

The amplitude is the SQUARE ROOT of the spectrum. Bin `k` of the band carries
`a_k = sqrt(S(f_k))`, so `"pink" => f -> 1/f` is pink (power `1/f`, equal
power per octave) because the function is read as a power density. This is
the classic trap: `1/f` handed as an AMPLITUDE -- which is what writing
`f -> 1/f^2` here would mean -- is a `1/f^2` (brown) spectrum, one unit
steeper per octave; the suite pins the slope of that mistake as a negative
control. The bins are the `k` with `lb <= k/N <= ub`, so `k >= 1` always and
a spectrum that diverges at zero is never evaluated there; `S` must be finite
and non-negative on every bin. The Nyquist bin (`k = N/2`, present when
`ub = 1/2` and `N` is even) is real, as `irfft` requires, and counts once in
the normalisation where interior bins count twice.

Phases: bin `k` carries `phi_k = 2 pi octopus_uniform01(seed, RNG_PHILOX,
slot, rng_id, k, 1)`, the Octopus counter RNG with the table's `slot` in the
turn field, stream `rng_id`, particle index `k`, component 1 -- a function of
`(seed, rng_id, slot, k)` alone, identical on every machine and Julia
version, independent of the task's own seed (this function runs outside the
task and cannot see it). At `slot = 0` the cells are those a `Beam`'s initial
distribution draws for particle `k`'s first coordinate under the same seed
and `rng_id` (the key layout above `_RULE_COMPONENT_BASE`), so do not reuse
the task seed with a beam's `rng_id` as an offline table's `(seed, rng_id)`;
a resolved table (`slot >= 1`) never touches turn 0, and no table shares a
cell with a live rule on any slot (particle index `k >= 1` against the
rules' 0, components 1 and 3-4 against their band).

Normalisation (D5), `amplitudes = :fixed`: the table is

    x_n = (2c/N) sum_k a_k cos(2 pi k n / N + phi_k)      (+ (c/N) a_{N/2} (-1)^n at Nyquist)

and over one full period the bins are orthogonal, so the population variance
is EXACTLY `(c^2 / N^2) (2 sum_interior a_k^2 + a_Nyquist^2)`. The scale is
therefore the constant `c = sigma N / sqrt(2 sum_interior a_k^2 + a_Nyquist^2)`
-- no sample statistic: the rms over a period equals `sigma` to rounding and
the periodogram `|X_k|^2` of the table equals `c^2 S(f_k)` on every band bin
to rounding, zero elsewhere. The owner's `sigma / std(ret)` normalisation is
this constant up to the Bessel factor `sqrt(N / (N - 1))`. Fixed amplitudes
reproduce the target spectrum exactly and give a sequence that is Gaussian
only in the limit of many bins (a handful of sinusoids is a deterministic
waveform, which is why fewer than 32 bins in the band warns).

`amplitudes = :rayleigh`: each bin's amplitude is multiplied by
`rho_k = |z_k|` with `z_k = (n_1 + i n_2) / sqrt(2)` a standard complex
normal, `n_1, n_2` the counter RNG's `octopus_normal_pair(seed, RNG_PHILOX,
0, rng_id, k, 2)` (components 3 and 4 of the same cell as the phase -- pair
2, NOT components 2 and 3, because component 2 is the second output of the
Box-Muller pair built from the phase's own uniform and would tie the
amplitude to the phase). The phase of every bin is the same as in the fixed
table, the scale `c` is the same constant (`E rho_k^2 = 1`), and the fixed
table is the Rayleigh table with every `rho_k` forced to 1. The result is a
stationary Gaussian process whose periodogram per bin is exponentially
distributed around `c^2 S(f_k)` and whose rms is `sigma` in expectation: the
target spectrum is matched statistically, not exactly. At the Nyquist bin,
whose entry is real, the modulus is the same Rayleigh `rho_k` with the sign
of `cos(phi_k)` rather than the half-normal modulus a real Gaussian bin
would have; its expected power is unaffected, which is all the normalisation
uses.

Canonical name (D7), unless `name` is given:

    spectral(<label>; sigma=<sigma>, band=<lb>..<ub>, turns=<N>, seed=<seed>, rng_id=<rng_id>, slot=<slot>, amplitudes=<fixed|rayleigh>)

with the floats in shortest round-trip form, the band in cycles per turn,
`slot=0` on an offline table and `<label>` the preset symbol or the custom
label verbatim, so the provenance receipt and the run artifact carry the
physics that made the table beside its digest (FNV-1a over the bytes of what
actually ran) and the arguments that regenerate it.

Refused with an `ArgumentError` that carries the numbers (D6): `turns < 2`;
a band with no bin (the message states `lb`, `ub`, `N` and the first bin
`1/N`); `lb <= 0`, `lb >= ub`, `ub > 1/2`; a negative, infinite or NaN
`S(f_k)` on any bin (the bin and its frequency named); a spectrum that
vanishes on every bin with `sigma > 0`; non-finite or negative `sigma`; a
custom spectrum with an empty label or whose `S` is not callable on a
frequency; an unknown preset; `amplitudes` other than `:fixed` or
`:rayleigh`; a `T` that is not an `AbstractFloat`; a negative or non-integer
`seed`, `rng_id`, `slot` or `turns`; `rng_id = 0`; a non-positive `f_rev`.
Warned, not refused: fewer than 32 bins in the band (the count and the band
in the message), once per table built here or per rule constructed, never
again when a rule's table is synthesised at compile.

Reproducibility (D9): the phases and the Rayleigh moduli are bitwise
reproducible everywhere. The inverse transform is FFTW's, whose last bits
depend on the plan FFTW chooses for the machine and build, so the same
arguments give the same table to rounding across machines and bitwise only
on the same machine and FFTW; the digest follows the bytes. No test pins a
digest value; the suite pins the statistics above and same-process
regeneration.

Cost `O(N log N)`, dominated by the transform (section 4 of the design note
quotes 0.62 s and 8.4 MB at 2^20 turns on its machine; the stage 1 record
carries this machine's numbers); a sweep of band centres is seconds of
synthesis against hours of tracking.

```julia
table = spectral_turn_table(:pink, 1.0e-5, (1.0e-4, 1.0e-2); turns = 2^20, seed = 42, rng_id = 1)
cavity = ThinCrabCavitySpec{1}(394.0e6; strengthX = (2.0e-3,), phase = (0.0,), phase_noise = (table,))
```
"""
function spectral_turn_table(spectrum, sigma, band; turns, seed, rng_id, slot=0, f_rev=nothing,
                             amplitudes=:fixed, T=Float64, name=nothing)
    return _spectral_table("spectral_turn_table", spectrum, sigma, band, turns, seed, rng_id, slot,
                           f_rev, amplitudes, T, name, true)
end

# The one body behind the factory and `_resolve_turn_rule` (its forward call,
# design D11): the factory's own refusals (`T`, the keys, `rng_id = 0`, the
# slot), then the plan and the synthesis; `who` prefixes the messages and
# `warn` switches the few-bins warning (`_spectral_plan`): on for the factory
# and the rule's constructor, off for the resolution of a rule that warned
# when it was built (review F2, 2026-10-16).
function _spectral_table(who::String, spectrum, sigma, band, turns, seed, rng_id, slot, f_rev,
                         amplitudes, T, name, warn::Bool)
    (T isa Type && T <: AbstractFloat) || throw(ArgumentError(
        "$(who): T must be an AbstractFloat type (the table's element type, " *
        "equal to the line's); got $(repr(T))"))
    plan = _spectral_plan(who, spectrum, sigma, band, turns, f_rev, amplitudes, warn)
    seed_key = _spectral_key(who, seed, :seed)
    rng_key = _spectral_key(who, rng_id, :rng_id)
    rng_key == 0 && throw(ArgumentError(
        "$(who): rng_id must be a positive integer naming the table's stream; " *
        "0, the live rules' auto-assign, is refused here because an offline table is data " *
        "and claims no stream (put SpectralNoise on the element for an assigned stream); got 0"))
    slot_key = _spectral_slot(who, slot)
    return _spectral_synthesis(plan, seed_key, rng_key, slot_key, amplitudes, T, name)
end

"""
    SpectralNoise(sigma, band, spectrum; rng_id=0, turns, amplitudes=:fixed, f_rev=nothing)

The spec-level turn-modulation rule for noise of a chosen spectrum: a
per-turn table of `turns` values whose one-sided power spectrum has the
shape `spectrum` over the modulation band `band` and whose rms is `sigma`
(in the slot's unit: radians on a phase slot, the dimensionless relative
factor on a strength slot), synthesised when the line COMPILES. In
`compile_runtime` (`_turn_modulation_wrap` of the crab cavity and of the RF
cavity, through `_resolve_turn_rule`) every `SpectralNoise` in a rule tuple
becomes the `TurnTable{T}` that [`spectral_turn_table`](@ref) returns for
`seed = global_rng_seed()`, the rule's claimed `rng_id` and the entry's SLOT
(a crab cavity's phase harmonic `i` is slot `i` and its strength harmonic
`i` slot `N + i`; an RF cavity's phase is 1 and its strength 2), with the
line's element type `T`; the other rules pass through unchanged. At run time it
therefore IS a table: the table rule's D7 semantics, the window check
(`first_turn + turns <= length`), the recorder, the one-particle probe and
the provenance all apply unchanged, the receipt and the artifact record the
kind `:table` with the canonical name
`spectral(<label>; sigma=.., band=.., turns=.., seed=.., rng_id=.., slot=.., amplitudes=..)`
beside the digest, and a compiled line never holds a `SpectralNoise` (the
suite pins it). `spectrum` is a preset or `"<label>" => S` with `S(f) >= 0`
the one-sided POWER SPECTRAL DENSITY shape and the bin amplitude
`sqrt(S(f_k))`: `f -> 1/f` is pink, while `1/f` handed as an amplitude --
the PSD `f -> 1/f^2` -- would be brown, one unit per octave steeper (D2).
The arguments, the normalisation (exact rms and periodogram with `:fixed`,
`sigma` the EXPECTED rms with `:rayleigh`), the phase keying, the refusals
and the fewer-than-32-bins warning are those of `spectral_turn_table`,
applied at CONSTRUCTION here (a refused rule claims no stream, as
`WhiteNoise` and `PinkNoise`); the presets:
$(_spectral_preset_lines())

Stream semantics are the live rules' (`_rule_stream_id`): `rng_id = 0`, the
default, assigns a fresh stream (`next_rng_id!`), an explicit id is claimed
(`claim_rng_id!`) so the auto-assign counter never reissues it. The slot
enters the table's keying as it enters a `WhiteNoise` draw, so one `rng_id`
on several slots of ONE cavity gives independent tables, exactly as it gives
the live rules independent draws per entry (review F1, 2026-10-16: before,
such rules resolved to one table with no warning). Two rules with equal
explicit ids on two ELEMENTS, under one global seed, resolve to identical
tables slot for slot: the task constructor's shared-`rng_id` warning fires
for them as for two `WhiteNoise` rules (the equal-digest warning covers
tables built offline).

The one difference from the live rules: a `WhiteNoise` or `PinkNoise` reads
the global seed on every turn through the `TrackingContext`, while this
rule's table takes the global seed in force WHEN THE LINE COMPILES -- the
first `execute!` of a task, a direct `compile_runtime(spec)`, and again at
any recompile: a knob assignment or a spec mutation bumps the epoch, and a
re-run of the task on a beam of another shape or backend changes the loss
record its runtime entries are keyed on (`_runtime_entries`,
src/tasks/Tasks.jl), so the line recompiles and the table is re-synthesised
under the then-current seed. A `set_global_rng!` after a compile that no
such change follows alters white and pink draws from the next turn but not
the table until the next compile; the canonical name records the seed the
table used, so the receipt says which. Each compile that
resolves the rule pays one synthesis (`O(N log N)`; tens of milliseconds at
2^20 turns), which a knob sweep that recompiles per step pays per step.

```julia
set_global_rng!(seed = 42)
rule = SpectralNoise(1.0e-5, (1.0e-4, 1.0e-2), :pink; rng_id = 7, turns = 2^20)
cavity = ThinCrabCavitySpec{1}(394.0e6; strengthX = (2.0e-3,), phase = (0.0,), phase_noise = (rule,))
```
"""
struct SpectralNoise{F} <: AbstractTurnRule
    sigma::Float64
    band::Tuple{Float64,Float64}    # as given: hertz when `f_rev` is set, else cycles per turn
    lb::Float64                     # the band in cycles per turn
    ub::Float64
    label::String
    S::F                            # the PSD shape; a type parameter that never reaches the runtime
    turns::Int
    amplitudes::Symbol
    f_rev::Union{Nothing,Float64}
    rng_id::UInt64
end
function SpectralNoise(sigma, band, spectrum; rng_id=0, turns, amplitudes=:fixed, f_rev=nothing)
    # A malformed rng_id is refused first, by `_rule_stream_id`'s own message, so
    # that no plan is built (and no few-bins warning printed) for a rule that is
    # refused anyway; the stream is CLAIMED last, after every other refusal, as
    # for `WhiteNoise` and `PinkNoise`.
    (rng_id isa Integer && rng_id >= 0) || _rule_stream_id(rng_id)
    plan = _spectral_plan("SpectralNoise", spectrum, sigma, band, turns, f_rev, amplitudes, true)
    return SpectralNoise{typeof(plan.S)}(plan.sigma, (Float64(band[1]), Float64(band[2])),
                                         plan.lb, plan.ub, plan.label, plan.S, plan.N, amplitudes,
                                         f_rev === nothing ? nothing : Float64(f_rev),
                                         _rule_stream_id(rng_id))
end

"""
    _resolve_turn_rule(rule, slot::Integer, ::Type{T}) -> rule or TurnTable{T}
    _resolve_turn_rules(rules::Tuple, first_slot::Integer, ::Type{T}) -> Tuple

The compile-time resolution step of both cavities' `_turn_modulation_wrap`,
run on the coerced rule tuple before the container is built: a
`SpectralNoise` becomes the `TurnTable{T}` of `spectral_turn_table` under
`global_rng_seed()`, the rule's claimed `rng_id` and the entry's `slot` --
the number `realize` hands `_turn_offset` for that entry, so the table is
keyed per slot as a live rule's draws are (review F1, 2026-10-16) -- through
the one synthesis body (`_spectral_table`, which does not repeat the
few-bins warning the rule printed at construction, review F2); `nothing`,
the live rules and a table pass through unchanged. `_resolve_turn_rules`
numbers a tuple's entries `first_slot, first_slot + 1, ...` (the crab cavity
passes 1 for its phase tuple and `N + 1` for its strength tuple, the RF
cavity resolves its two scalars with 1 and 2: the numbering of
`_slot_rules`). Downstream of this step -- `_slot_rules`, `_realize_draws`,
`_slot_nominals`, the window check, the provenance walks -- nothing knows
the rule existed.
"""
_resolve_turn_rule(rule, slot::Integer, ::Type{T}) where {T} = rule
function _resolve_turn_rule(rule::SpectralNoise, slot::Integer, ::Type{T}) where {T}
    return _spectral_table("SpectralNoise", rule.label => rule.S, rule.sigma, rule.band, rule.turns,
                           global_rng_seed(), rule.rng_id, slot, rule.f_rev, rule.amplitudes, T,
                           nothing, false)
end
_resolve_turn_rules(rules::NTuple{K,Any}, first_slot::Integer, ::Type{T}) where {K,T} =
    ntuple(i -> _resolve_turn_rule(rules[i], first_slot + i - 1, T), Val(K))

# The octave guard of `PinkNoise`, shared by both constructors and run before
# the stream id is assigned, like `_check_rule_sigma`.
_check_pink_octaves(octaves::Int) =
    1 <= octaves <= 62 ? nothing : throw(ArgumentError(
        "PinkNoise: octaves must be between 1 and 62 (generator k holds its draw " *
        "for 2^k turns of the Int64 turn counter); got $(octaves)"))

"""
    PinkNoise(sigma; rng_id=0, octaves=16)

A per-turn value with an approximately 1/f (pink) spectrum, in the slot's
unit (an offset in rad on a phase; on a strength a dimensionless relative
factor `d`, realised as `S (1 + d)`, so `sigma` is the relative rms), by the
Voss-McCartney construction of the design note's section
5.2 (Voss and Clarke [6]; McCartney's variant as described by Whittle [7]):
the sum of `octaves` (`K`) independent unit-normal generators, generator `k`
(`k = 0, ..., K - 1`) holding its value for `2^k` turns, divided by `sqrt(K)`
and scaled by `sigma`. `octaves` sets the approximation band: 1/f from
`f_rev / 2^K` up to `f_rev / 2`, with the construction's known ripple, within
a factor 1.7 band to band across the twelve trusted octaves measured in
`validation/turn_modulation_spectra.jl` (every trusted octave band within
0.738 to 1.241 of the top octave's power at 65536 turns under the rule
component band of 2026-10-12; the note's section 5.5 table); below
`f_rev / 2^K` the spectrum is flat. `1 <= octaves <= 62`.

Stateless, like `WhiteNoise`: generator `k` is the counter-RNG draw
`octopus_normal(seed, method, turn >> k, rng_id, 0, component, T)`, keyed on
`turn >> k` rather than on `turn` -- the key IS the hold, so no state is
carried and the offset on turn `t` is a pure function of `(seed, t, rng_id,
slot)`: identical on every backend, whether the run is one `execute!` or
many, and under a `start_turn` reposition. Generator `k` of slot `s` draws
component `_RULE_COMPONENT_BASE + s + _PINK_COMPONENT_STRIDE * (k + 1)`,
stride 64, while a `WhiteNoise` draws `_RULE_COMPONENT_BASE + s` itself (the
key layout is documented above `_RULE_COMPONENT_BASE`); the crab cavity's
slots run `1:2N`, so a white and a pink rule sharing one `rng_id` on one
element draw from disjoint component bands as long as the element has at
most 64 slots -- ENFORCED at the wrap: `TurnModulated(base, rule)` refuses a
container of more than `_PINK_COMPONENT_STRIDE` slots carrying a `PinkNoise`
through `_check_slot_rules` (a crab cavity with a pink rule has at most 32
harmonics; with white and table rules only, any number). Two ELEMENTS sharing
an `rng_id` draw identical values and the task constructor warns, as for
`WhiteNoise`. `rng_id = 0` (the default) assigns a fresh stream; an explicit
id is claimed so the auto-assign counter never reissues it, as `LumpedRadSpec`
and `BPMObserver` do.

`sigma` is the per-turn rms of the offset: the `K` generators are independent
unit normals, so their sum over `sqrt(K)` has unit variance, but the sample
rms of ONE finite run wanders with the low-frequency content -- its one-sigma
scatter is 7.6 % at 65536 turns and 13.8 % at 16384 (`Var[rms^2] =
(2/(K^2 N)) sum_k 2^k (2K - 1 - 2k)`, K = 16; Monte Carlo over 2048 streams
agrees), with a heavy upper tail; the spectra script reports the measured
value. `sigma` must be finite and non-negative; zero is a quiet rule.
As for `WhiteNoise`, `sigma` is converted to the element's numeric type at
realisation (a `Float32` sigma on a `Float64` cavity is promoted), while a
`TurnTable` is refused on a type mismatch because its storage would otherwise
be copied silently -- the asymmetry is deliberate.
"""
struct PinkNoise{T<:AbstractFloat} <: AbstractTurnRule
    sigma::T
    rng_id::UInt64
    octaves::Int
    function PinkNoise{T}(sigma::T, rng_id::UInt64, octaves::Int) where {T<:AbstractFloat}
        _check_rule_sigma("PinkNoise", sigma)
        _check_pink_octaves(octaves)
        return new{T}(sigma, rng_id, octaves)
    end
end
function PinkNoise(sigma::Real; rng_id=0, octaves::Integer=16)
    s = float(sigma)
    _check_rule_sigma("PinkNoise", s)
    _check_pink_octaves(Int(octaves))
    return PinkNoise{typeof(s)}(s, _rule_stream_id(rng_id), Int(octaves))
end

"""
    _rule_kind(rule) -> Symbol

The provenance kind label of a rule, the `kind` field of the slot entry that
`_turn_modulation_provenance!` documents: `:white`, `:pink` or `:table`
(`:spectral` labels the spec-level `SpectralNoise`, which a compiled line never
holds -- `_resolve_turn_rule` -- so no receipt carries it).
Deliberately no fallback, as for `realize`: a rule without a label is a
`MethodError` when the receipt is built, not an unlabelled slot.
"""
_rule_kind(::WhiteNoise) = :white
_rule_kind(::PinkNoise) = :pink
_rule_kind(::TurnTable) = :table
_rule_kind(::SpectralNoise) = :spectral

"""
    _turn_rule_names() -> String

The rule catalogue as prose: the names of the concrete subtypes of
`AbstractTurnRule`, sorted and joined by `", "`, DERIVED from the type tree for
the crab cavity's `_rule_tuple` and the RF cavity's `_rule_scalar` messages and
pinned by the suite's catalogue tripwire (AGENTS.md: never hand-copy a case
list; this docstring quotes no literal for the same reason). `_concrete_octopus_subtypes`
lives in `src/tasks/strongstrong/interface.jl`, included after this file; the
call is made only inside an error path or a test at run time, so the late
binding is harmless (the precedent is `_alternative_method_names` in
`src/analysis/one_turn_matrix.jl`).
"""
_turn_rule_names() =
    join(sort!(String[string(nameof(T)) for T in _concrete_octopus_subtypes(AbstractTurnRule)]), ", ")

# ---------------------------------------------------------------------------
# The scalar rule interface. A rule is a per-turn value generator for ONE
# scalar parameter slot of an element; the element's `realize` method decides
# which slots exist, hands each rule its slot number and applies the value
# (added to a phase; a strength is scaled as `S (1 + d)`). Stateless
# rules return themselves as `rule′`; a stateful one (an IIR filter, documented
# in the design note's section 5.3 and not shipped here) returns its successor.
# ---------------------------------------------------------------------------

"""
    _turn_offset(rule, ctx::TrackingContext, slot::Integer, ::Type{T}) -> (offset::T, rule′)

The value `rule` contributes on turn `ctx.turn` to the parameter slot `slot`
of an element whose numeric type is `T`, with the rule's successor (`rule`
itself for every stateless rule): an offset the element adds to a phase, a
relative factor `d` it scales a strength by as `S (1 + d)`. `nothing` is the
inactive rule: value zero, no draw, no state.
"""
@inline _turn_offset(::Nothing, ctx::TrackingContext, slot::Integer, ::Type{T}) where {T} =
    (zero(T), nothing)

# A `SpectralNoise` never realises a turn: `_resolve_turn_rule` turns it into a
# `TurnTable{T}` when the line compiles, so reaching this method means a rule
# container was built around the unresolved spec-level rule (the suite pins
# that a compiled line holds none). Static message: a rule's `_turn_offset` is
# host-side, but every rule method keeps the kernel-safe form.
@inline _turn_offset(::SpectralNoise, ctx::TrackingContext, slot::Integer, ::Type{T}) where {T} =
    throw(ArgumentError("SpectralNoise resolves to a TurnTable when the line compiles " *
                        "(_resolve_turn_rule in _turn_modulation_wrap); it never realises a turn itself"))

@inline function _turn_offset(rule::WhiteNoise, ctx::TrackingContext, slot::Integer,
                              ::Type{T}) where {T}
    # Particle-index slot fixed at 0 and the component in the rules' band (the
    # key layout above `_RULE_COMPONENT_BASE`): one draw per (seed, turn,
    # rng_id, slot), the same on every backend and however the run is split
    # into calls, and never the cell a BPM or a radiation element draws.
    n = octopus_normal(ctx.seed, ctx.rng_method, ctx.turn, rule.rng_id, 0,
                       _RULE_COMPONENT_BASE + slot, T)
    return (T(rule.sigma) * n, rule)
end

@inline function _turn_offset(rule::PinkNoise, ctx::TrackingContext, slot::Integer,
                              ::Type{T}) where {T}
    # Voss-McCartney: generator k is keyed on `turn >> k` (an arithmetic shift of
    # the non-negative Int64 turn), so it holds its draw for 2^k turns without
    # carrying state; the K unit normals over sqrt(K) have unit variance, so
    # `sigma` is the per-turn rms. Component band per generator: see
    # `_RULE_COMPONENT_BASE` and `_PINK_COMPONENT_STRIDE`.
    K = rule.octaves
    acc = zero(T)
    for k in 0:K-1
        acc += octopus_normal(ctx.seed, ctx.rng_method, ctx.turn >> k, rule.rng_id, 0,
                              _RULE_COMPONENT_BASE + slot + _PINK_COMPONENT_STRIDE * (k + 1), T)
    end
    return (T(rule.sigma) * acc / sqrt(T(K)), rule)
end

@inline function _turn_offset(rule::TurnTable{T}, ctx::TrackingContext, slot::Integer,
                              ::Type{T}) where {T}
    # Bounds-CHECKED unconditionally (an explicit `checkbounds`, immune to a
    # caller's `@inbounds`): a `BoundsError` is the honest failure of the by-hand
    # `update_line` + `track!` path, which has no window check.
    i = ctx.turn + 1
    checkbounds(rule.offsets, i)
    return (@inbounds(rule.offsets[i]), rule)
end

"""
    _slot_draws(rules::Tuple, ctx::TrackingContext, first_slot::Int, ::Type{T}) -> Tuple
    _slot_values(draws::Tuple) -> Tuple
    _slot_successors(draws::Tuple) -> Tuple

`_turn_offset` over a tuple of per-slot rules -- slot `first_slot` for the
first entry, `first_slot + 1` for the next, and so on -- as the tuple of the
rules' `(value, rule′)` pairs, and the two projections of such a tuple: the
values (one `T` per slot) and the successors (one rule per slot). Unrolled by
`@generated` with LITERAL indices (`rules[1]`, `rules[2]`, ...), so each
entry's type is its own slot's, as `getfield` with a constant index infers
it, with no constant propagation involved. The form these replace,
`ntuple(i -> _turn_offset(rules[i], ctx, i, T), Val(N))`, is type-stable only
on a HOMOGENEOUS container (every slot the same rule type): on a mixed one --
`nothing` beside a rule, or a `PinkNoise`, whose loop keeps the closure from
being inlineable -- `rules[i]` infers as a `Union`, Julia skips the constant
propagation that would resolve it (a closure whose inferred body is not
inlineable is judged not worth propagating into), the draws tuple and the
successor container infer as `Union`s, and `realize`, `update` and
`update_line` on that element allocate: 336 B per `realize` and 640 B per
`update` on a `(nothing, WhiteNoise)` crab cavity on the main checkout
(c070750), 688 and 720 B with the recording hook, 14400 B per turn on a
40-element line, 0 B after this unrolling (review F1, 2026-10-15; the table
in `docs/design/turn_modulation.md`, section 7). `Base.map` over tuples is
type-stable the same way but takes a `Vector{Any}` path from 32 entries on
(measured: 592 B at 32 entries, 0 at 31), which is why the generated form is
used instead. Generated bodies are compile-time and serial (the suite's
`Core.Box` sweep skips them by design).
"""
@inline @generated function _slot_draws(rules::Tuple, ctx::TrackingContext, first_slot::Int,
                                        ::Type{T}) where {T}
    calls = [:(_turn_offset(rules[$i], ctx, first_slot + $(i - 1), T)) for i in 1:fieldcount(rules)]
    return :(($(calls...),))
end

@inline @generated function _slot_values(draws::Tuple)
    return :(($([:(draws[$i][1]) for i in 1:fieldcount(draws)]...),))
end

@inline @generated function _slot_successors(draws::Tuple)
    return :(($([:(draws[$i][2]) for i in 1:fieldcount(draws)]...),))
end

"""
    _check_rule_window(rule, first_turn::Int64, nturns::Int, where::AbstractString)

Throw an `ArgumentError` if `rule` cannot serve every turn of the window
`first_turn:(first_turn + nturns - 1)`; return `nothing` otherwise. Only a
`TurnTable` has a window constraint (`first_turn + nturns <= length(offsets)`);
`nothing`, `WhiteNoise` and `PinkNoise` serve any turn. `where` names the element and slot
for the message. Called once per slot by `_check_container_window` below,
which the `_check_turn_window` walk reaches for every `TurnModulated` before
the first turn of every `execute!`.
"""
_check_rule_window(rule, first_turn::Int64, nturns::Int, where::AbstractString) = nothing

function _check_rule_window(rule::TurnTable, first_turn::Int64, nturns::Int,
                            where::AbstractString)
    # An unnamed table is said so rather than printed as the empty string "".
    label = isempty(rule.name) ? "unnamed turn table" : "turn table $(repr(rule.name))"
    first_turn + nturns <= length(rule.offsets) || throw(ArgumentError(
        "the $(label) on $(where) holds $(length(rule.offsets)) " *
        "turns but the window runs turns $(first_turn) to $(first_turn + nturns - 1) " *
        "(absolute, zero-based): a table never wraps, extend it or shorten the run"))
    return nothing
end

# ---------------------------------------------------------------------------
# The slot protocol (stage 3, the RF cavity by the same wrap). An element's
# rule CONTAINER -- the `rule` field of its `TurnModulated` -- declares its
# scalar slots once, through `_slot_rules`, and its SPEC declares the rule
# objects it holds through `_turn_rule_values`; the three container-level
# walks (the window check, the provenance slots, the stream-id collection)
# are generic over those two declarations, so a new modulated kind adds its
# `realize`, its `_turn_modulation_wrap` and these two methods, and no walk
# is hand-copied. `realize` stays per container: it is the element's own
# arithmetic, not a walk.
# ---------------------------------------------------------------------------

"""
    _slot_rules(rules) -> Tuple

The scalar slots of an element-level rule container, in SLOT ORDER (the slot
number its `realize` hands `_turn_offset`), as `(label::String, rule)` pairs:
`rule` is `nothing` (inactive) or a concrete `AbstractTurnRule`, `label` the
parameter name the provenance receipt and the window message print
(`"phase_noise[2]"` on a crab cavity, `"phase_noise"` on an RF cavity, whose
phase is a scalar). Inactive slots are included; the consumers skip them.
Deliberately no generic fallback, as for `realize`: a container without a
method is a `MethodError` at the first window check or receipt, not a
modulated element silently missing from the run's provenance. Every container
with a `realize` method defines one -- the suite's container tripwire pins the
two method sets against each other: `CrabCavityNoise` in
`src/elements/crab_cavity.jl`, `RFCavityNoise` in `src/elements/rf_cavity.jl`.
"""
function _slot_rules end

"""
    _slot_nominals(rules, base) -> Tuple

The NOMINAL parameters the slots of a rule container act on, in SLOT order and
aligned one-to-one with `_slot_rules` (the recorder's walk checks the two
lengths agree), one NamedTuple per slot read from `base`, the compiled nominal
element, never from a realised one: on a `CrabCavityNoise` over a
`ThinCrabCavity` the harmonic's `(phase, strengthX, strengthY)` for both its
phase slot and its strength slot; on an `RFCavityNoise` over a `ThinRFCavity`
`(phase, strength)` for either slot. The run artifact writes each active
slot's NamedTuple as the `nominal_<name>` attributes of its provenance group
(`docs/design/turn_modulation_record.md`, D3 and D7), so a reader forms the
realised value from a recorded offset exactly as `realize` does -- `phase + d`
on a phase slot, `strength * (1 + d)` on a strength slot -- while the record
itself holds the rule's output. Per container like `_slot_rules`, deliberately
without a fallback; the suite's container tripwire pins the method set.
"""
function _slot_nominals end

"""
    _check_container_window(rules, first_turn::Int64, nturns::Int, where::AbstractString)

Have every slot of a rule container check the window through the scalar
`_check_rule_window`, naming the slot after the element: `where * " " * label`
(`"ThinCrabCavity phase_noise[2]"`, `"ThinRFCavity strength_noise"`); only a
`TurnTable` can refuse. One generic method over `_slot_rules`, called by the
`_check_turn_window` walk for every `TurnModulated` it meets. A separate
function from the scalar `_check_rule_window` on purpose: that one's generic
no-op (which every stateless rule relies on) must never be what a container
falls to.
"""
function _check_container_window(rules, first_turn::Int64, nturns::Int, where::AbstractString)
    for (label, rule) in _slot_rules(rules)
        _check_rule_window(rule, first_turn, nturns, where * " " * label)
    end
    return nothing
end

"""
    _check_slot_rules(rules) -> nothing

Validate a rule container's slot declaration once, at the wrap: the
two-argument `TurnModulated(base, rule)` constructor -- the one choke point
every modulated element passes, from both cavities' `_turn_modulation_wrap` --
calls it on every container, so the checks are generic over `_slot_rules` and
no kind repeats them. `_check_slot_table` does the work on the declared
`(label, rule)` table and throws an `ArgumentError`:

- more than `_PINK_COMPONENT_STRIDE` slots with a `PinkNoise` on any of them
  (2026-10-13 neighbour audit, U7-1): pink generator k of slot s draws the
  component `_RULE_COMPONENT_BASE + s + 64 (k + 1)`, so slot `s + 64` of the
  same container -- a white rule's own component, or another pink rule's
  generator band shifted by one -- is the same cell under one `rng_id`;
  measured on a 33-harmonic crab cavity (66 slots), identical draws on 64 of
  64 turns. The bound is the pink rule's: a container of any size carrying
  white and table rules only passes;
- a slot label that is empty, contains `'/'` or repeats within the container
  (the label half of U5-2): the labels name the window message and the run
  artifact's `/turn_modulation/<slot>/...` datasets, so an empty, nested or
  duplicate name would be a silently missing or overwritten group.
"""
_check_slot_rules(rules) = _check_slot_table(_slot_rules(rules))

function _check_slot_table(slots::Tuple)
    n = length(slots)
    if n > _PINK_COMPONENT_STRIDE && any(p -> p[2] isa PinkNoise, slots)
        throw(ArgumentError(
            "a turn-modulation container declares $(n) slots, more than the pink stride " *
            "$(_PINK_COMPONENT_STRIDE): PinkNoise generators are keyed by component " *
            "offsets of $(_PINK_COMPONENT_STRIDE) per generator, so a PinkNoise on one slot " *
            "would share its counter-RNG stream with another rule's slot " *
            "$(_PINK_COMPONENT_STRIDE) further on under the same rng_id (identical draws). " *
            "Keep a crab cavity carrying a PinkNoise to at most " *
            "$(_PINK_COMPONENT_STRIDE ÷ 2) harmonics, or use WhiteNoise and TurnTable rules only"))
    end
    seen = Set{String}()
    for (label, _) in slots
        label isa String || throw(ArgumentError(
            "a turn-modulation slot label must be a String; got a $(typeof(label))"))
        isempty(label) && throw(ArgumentError(
            "a turn-modulation slot label is empty; every slot of a rule container needs " *
            "a non-empty label (the parameter name, indexed per harmonic on a crab cavity)"))
        occursin('/', label) && throw(ArgumentError(
            "the turn-modulation slot label $(repr(label)) contains '/', which would nest " *
            "it inside the run artifact's /turn_modulation group; use a flat name"))
        label in seen && throw(ArgumentError(
            "the turn-modulation slot label $(repr(label)) appears twice in one container; " *
            "slot labels must be unique within an element"))
        push!(seen, label)
    end
    return nothing
end

"""
    _rule_numeric_type(rule) -> Union{Nothing,DataType}

The numeric element type a rule is bound to, or `nothing` for a rule that
adapts to the element's (`nothing`, `WhiteNoise`, `PinkNoise` -- their `sigma` is
converted to the element's `T` at realisation). A `TurnTable{T}` is bound to `T`:
`_turn_modulation_wrap` refuses a table whose type differs from the compiled
element's rather than promoting silently.
"""
_rule_numeric_type(rule) = nothing
_rule_numeric_type(rule::TurnTable{T}) where {T} = T
# `PinkNoise` deliberately has no method here: like `WhiteNoise` it adapts to
# the element's `T` through the generic `nothing`.

"""
    realize(rule, base, ctx::TrackingContext) -> (element, rule′)

Produce the element to track on turn `ctx.turn` from the NOMINAL element
`base` and the element-level rule `rule`, together with the rule's successor.
The returned element has the same concrete type as `base`. Every element
kind that supports turn modulation defines a method for its own rule
container (`CrabCavityNoise` for `ThinCrabCavity`, `src/elements/crab_cavity.jl`;
`RFCavityNoise` for `ThinRFCavity`, `src/elements/rf_cavity.jl`), and every
such container also declares its slots through `_slot_rules` (the slot
protocol below); there is deliberately no generic fallback -- a rule the
element does not understand is a `MethodError` at the first turn, not a
silently unmodulated run.

Every shipped rule returns ITSELF as `rule′` (a pure function of `ctx`; the
suite's stateless-rule tripwire pins it for every rule of the derived
catalogue in every shipped container). The task layer keeps a successor only
within one `execute!` call on the fast loop and within one plan on the general
loop, so a stateful rule -- which design D6 admits -- is an owner decision
before it ships: persist successors or forbid state (2026-10-13 neighbour
audit, U1-1).

Each container's method is the two-element projection of its `_realize_draws`
(below), the ONE evaluation that also yields the draws the run artifact
records; `realize` keeps this `(element, rule′)` contract for the hand-realised
references and the tests that use it.
"""
function realize end

"""
    _realize_draws(rules, base, ctx::TrackingContext) -> (element, rules′, draws::Tuple)

The one evaluation behind `realize` (`docs/design/turn_modulation_record.md`,
D5): the element to track on turn `ctx.turn`, the rules' successors, and the
DRAWS -- the value `_turn_offset` returned for EVERY slot of the container, in
SLOT order (the order of `_slot_rules`, `2N` entries on a `CrabCavityNoise`,
two on an `RFCavityNoise`): an offset in rad on a phase slot, the
dimensionless relative factor `d` on a strength slot, `zero(T)` on an inactive
slot. The element is built FROM these very values, so a recorder handed the
tuple records what the element used by construction, without reading the
element back (which would miss a replay by a relative 1e-12, `(S + d) - S`
not being `d`) and without evaluating a rule a second time. The recording
hook (`update(elem, ctx, sink)` below) is its only caller besides `realize`;
the tuple is isbits and dead on the plain hook, so the off path pays nothing.
Per container, like `realize` and with the same deliberate absence of a
generic fallback; the suite's container tripwire pins the method set against
`_slot_rules`.
"""
function _realize_draws end

# ---------------------------------------------------------------------------
# The wrapper.
# ---------------------------------------------------------------------------

"""
    TurnModulated(base, rule)
    TurnModulated(base, inner, rule)

An element whose parameters change from turn to turn inside one tracking run.
`base` is the nominal element, untouched after compile; `inner` is the
REALISED element for the turn being tracked, which every tracking forward
reads; `rule` produces `inner` from `base` and the `TrackingContext` through
`realize`. The two-argument form starts with `inner === base`, so until the
first `update` -- and forever on the contextless `track!` path, where no
update runs -- the wrapper tracks the nominal element (design decision D5).
It is also where the container's slot declaration is validated, once per
compile, through `_check_slot_rules` (the pink-stride bound and the slot
labels): every modulated element passes through it, so a container that
cannot be keyed or labelled safely is refused at compile, never realised. The
three-argument form (the survey rebind, the per-turn `update` through the
parametric constructor) does not repeat the check.

Built by `compile_runtime` through `_turn_modulation_wrap`, INNERMOST of the
three compile-time wraps (then `MisalignedElement`, then `RefTilted`), because
the modulated quantity is the element's own parameter while the other two act
on the frame around it. Symplectic whenever the realised element is. The rule
may hold host data (a `TurnTable`), so the wrapper is not necessarily isbits
and never reaches a kernel: the device conversion in `src/track/phase6d_track.jl`
drops it to `inner` at launch (design decision D8).
"""
struct TurnModulated{E,R} <: AbstractTrackOp
    base::E
    inner::E
    rule::R
end
function TurnModulated(base, rule)
    _check_slot_rules(rule)
    return TurnModulated(base, base, rule)
end

# The forwards MisalignedElement defines, plus the context-aware call whose
# absence on that wrapper once dropped the context of a wrapped stochastic
# element (F13, 2026-08-05 audit), defined from the start.
@inline track_particle(method::AbstractTrackingMethod, w::TurnModulated, x, px, y, py, z, pz) =
    track_particle(method, w.inner, x, px, y, py, z, pz)
@inline (w::TurnModulated)(x, px, y, py, z, pz) =
    track_particle(_inner_method(w.inner), w.inner, x, px, y, py, z, pz)
@inline (w::TurnModulated)(ctx::TrackingContext, particle_id, x, px, y, py, z, pz) =
    w.inner(ctx, particle_id, x, px, y, py, z, pz)
@inline track_luminous(w::TurnModulated, mask, ctx::TrackingContext, particle_id,
                       x, px, y, py, z, pz) =
    track_luminous(w.inner, mask, ctx, particle_id, x, px, y, py, z, pz)
_inner_method(w::TurnModulated) = _inner_method(w.inner)
# A bare `track!` through a modulated element tracks the nominal one by design
# (D5), so the wrapper requires a context only if the element inside does.
_requires_tracking_context(w::TurnModulated) = _requires_tracking_context(w.inner)

# ---------------------------------------------------------------------------
# The pure per-turn hook. Replaces the mutating `update!` (one hook, one
# meaning); `src/tasks/Tasks.jl` calls `update_line` on every segment's tuple
# at the start of every turn and stores the rebuilt tuple back.
# ---------------------------------------------------------------------------

"""
    update(elem, ctx::TrackingContext) -> elem′

Per-turn runtime-element hook, PURE and type-preserving: return the element to
track on turn `ctx.turn`, of the same concrete type as `elem`, and `elem`
itself for the ordinary element (the default, free). `TurnModulated` realises
its inner element through `realize`; the frame wrappers and `CompositeLine`
forward into what they hold and rebuild themselves around the result, so a
modulated element inside a misaligned, rolled or kept-whole sub-line is
updated like a bare one. Called from the task's turn loops only -- the
contextless `track!` path never updates, which is what keeps it tracking
`inner`, the nominal element while no update has run. The rebuilt wrapper
carries the rule's successor, which every shipped rule returns as itself; the
loops do not persist a successor across `execute!` calls or plans (see
`realize` and `execute!`).
"""
update(elem, ctx::TrackingContext) = update(elem, ctx, nothing)

"""
    update(elem, ctx::TrackingContext, sink) -> elem′

The RECORDING form of the pure hook (`docs/design/turn_modulation_record.md`,
D5): the same rebuild as `update(elem, ctx)`, with every modulated element's
draws -- the tuple `_realize_draws` returns beside the realised element --
handed to `sink` through `_record_turn_draws!(sink, draws)`, in LINE order,
the order the provenance walk lists the elements. One evaluation feeds both
the element and the recorder, so the recorded sequence and the one the kick
used cannot disagree. `sink === nothing` IS the plain hook: the two-argument
form forwards here with `nothing`, `_record_turn_draws!(::Nothing, _)` is a
no-op and the draws tuple is dead code, so a run without the artifact's
`record_turn_modulation` pays nothing (the suite keeps its zero-allocation
and type-preservation pins on the two-argument form). The sink's protocol
(per-turn begin and end, the flush through the artifact's `capacity`) is the
recorder's, `TurnModulationRecorder` in `src/tasks/RunArtifact.jl`.
"""
update(elem, ctx::TrackingContext, sink) = elem

function update(w::TurnModulated{E,R}, ctx::TrackingContext, sink) where {E,R}
    inner, rule, draws = _realize_draws(w.rule, w.base, ctx)
    _record_turn_draws!(sink, draws)
    # The explicit type parameters are the type-preservation assertion: a
    # realised element or successor rule of another type is a conversion error
    # here, not a tuple of a new type in the kernel.
    return TurnModulated{E,R}(w.base, inner, rule)
end
# The frame wrappers rebuild themselves around the updated element they hold,
# carrying their own frame data unchanged; the kept-whole sub-line rebuilds its
# op tuple through `update_line`, so nesting depth does not matter.
update(elem::MisalignedElement, ctx::TrackingContext, sink) =
    MisalignedElement(update(elem.inner, ctx, sink), elem.qin, elem.oin, elem.qout, elem.oout)
update(elem::RefTilted, ctx::TrackingContext, sink) =
    RefTilted(update(elem.inner, ctx, sink), elem.c, elem.s)
update(elem::CompositeLine, ctx::TrackingContext, sink) =
    CompositeLine(update_line(elem.ops, ctx, sink))

"""
    _record_turn_draws!(sink, draws::Tuple) -> nothing

Hand one modulated element's draws of the current turn to the recording sink:
the no-op on `nothing` (the plain hook), the recorder's method in
`src/tasks/RunArtifact.jl`, which keeps the ACTIVE slots' values and refuses an
element the provenance did not list.
"""
_record_turn_draws!(::Nothing, draws::Tuple) = nothing

"""
    update_line(line::Tuple, ctx::TrackingContext) -> line′
    update_line(line::Tuple, ctx::TrackingContext, sink) -> line′

`update` applied to every element of a runtime line tuple, nested tuples
included, rebuilt with `ntuple(..., Val(N))` so the result is a stack copy of
the same tuple type with zero allocation (`docs/design/turn_modulation.md`,
section 7: 20 ns for 40 elements; `Base.map` over a tuple of 32 or more
entries takes the generic path and allocated 79 kB per turn). The suite pins
`typeof(update_line(line, ctx)) === typeof(line)` and zero allocation on a
line longer than 32 elements, on homogeneous and on mixed rule containers
(`_slot_draws`), on both hooks. The three-argument form is the recording hook
applied to the line (`sink` as for `update`; `nothing` is the plain form);
`ntuple` evaluates its entries in index order, which is what makes the
recorder meet the modulated elements in line order.
"""
@inline update_line(line::Tuple, ctx::TrackingContext) = update_line(line, ctx, nothing)
@inline update_line(line::Tuple, ctx::TrackingContext, sink) =
    ntuple(i -> _update_entry(line[i], ctx, sink), Val(length(line)))
@inline _update_entry(e::Tuple, ctx::TrackingContext, sink) = update_line(e, ctx, sink)
@inline _update_entry(e, ctx::TrackingContext, sink) = update(e, ctx, sink)

# ---------------------------------------------------------------------------
# The walks a wrapper joins. The window check and the stream collector are
# new walks; they descend the same three wrappers, the kept-whole line and the
# nested tuples that `update` does.
# ---------------------------------------------------------------------------

"""
    _check_turn_window(elem, first_turn::Int64, nturns::Int)

Walk a compiled runtime line (tuples, the three wrappers, `CompositeLine`) and
have every rule check that it can serve the window through `_check_rule_window`;
`execute!` calls this before the first turn of every call. A plain element is
a no-op.
"""
_check_turn_window(elem, first_turn::Int64, nturns::Int) = nothing
_check_turn_window(elems::Tuple, first_turn::Int64, nturns::Int) =
    (foreach(e -> _check_turn_window(e, first_turn, nturns), elems); nothing)
# The wrapper forwards to the container-level check, generic over the
# container's `_slot_rules`, which names the element and slot in `where`
# ("ThinCrabCavity phase_noise[i]", "ThinRFCavity strength_noise").
_check_turn_window(w::TurnModulated, first_turn::Int64, nturns::Int) =
    _check_container_window(w.rule, first_turn, nturns, string(nameof(typeof(w.base))))
_check_turn_window(elem::Union{MisalignedElement,RefTilted}, first_turn::Int64, nturns::Int) =
    _check_turn_window(elem.inner, first_turn, nturns)
_check_turn_window(elem::CompositeLine, first_turn::Int64, nturns::Int) =
    _check_turn_window(elem.ops, first_turn, nturns)

"""
    _each_turn_rule_spec(f, element)

Apply `f` to every element spec a line holds: tuples, vectors, a `LineEntry`
(the spec the placement COMPILES, `_effective_spec` in src/tasks/Tasks.jl,
overrides merged, so a rule given only through a placement override is seen,
U1-2), an `ElementSpec{:line}` descended into its entries, as
`_collect_radiation_ids!` walks. The ONE walk behind
`_collect_turn_modulation_ids!` and `_collect_turn_tables!`, so a container
one collector sees the other sees too (the two-walker lesson of the aperture
collectors, audit part 7, T3).
"""
_each_turn_rule_spec(f, element) = nothing
_each_turn_rule_spec(f, elements::Tuple) =
    (foreach(e -> _each_turn_rule_spec(f, e), elements); nothing)
_each_turn_rule_spec(f, elements::AbstractVector) =
    (foreach(e -> _each_turn_rule_spec(f, e), elements); nothing)
_each_turn_rule_spec(f, entry::LineEntry) = _each_turn_rule_spec(f, _effective_spec(entry))
_each_turn_rule_spec(f, element::ElementSpec{:line}) =
    (foreach(e -> _each_turn_rule_spec(f, e), line_entries(element)); nothing)
_each_turn_rule_spec(f, spec::ElementSpec) = (f(spec); nothing)

"""
    _collect_turn_modulation_ids!(ids::Vector{UInt64}, element) -> ids

Collect the `rng_id` of every stochastic turn-modulation rule declared on the
SPECS of a line (the walk of `_each_turn_rule_spec`), one entry per distinct
id per element, so `_warn_duplicate_turn_modulation_streams` can warn when two
elements share a stream. Each spec's rule objects are read through the kind's
`_turn_rule_values`, and each DISTINCT `rng_id` among them (every rule
carrying an `rng_id` field; `WhiteNoise` and `PinkNoise` today) is pushed
once: one id shared by every slot of one element contributes one entry (the
slots keep the draws independent) and does not warn; the same id on two
elements contributes two and does. Kinds that declare rule parameters add a
`_turn_rule_values` method, not a collector method.
"""
function _collect_turn_modulation_ids!(ids::Vector{UInt64}, element)
    _each_turn_rule_spec(element) do spec
        seen = UInt64[]
        for rule in _turn_rule_values(spec)
            hasfield(typeof(rule), :rng_id) || continue
            rule.rng_id in seen || push!(seen, rule.rng_id)
        end
        append!(ids, seen)
    end
    return ids
end

"""
    _collect_turn_tables!(tables::Vector, element) -> tables

The table sibling of `_collect_turn_modulation_ids!`, over the same walk: one
entry `(digest, element, slot, name)` per DISTINCT table digest per element
(every rule carrying a `digest` field; `TurnTable` today), `element` the
spec's kind symbol and `slot` the position in the kind's `_turn_rule_values`
(the container's slot number: `1:2N` on a crab cavity, 1-2 on an RF cavity),
so `_warn_duplicate_turn_tables` (src/tasks/Tasks.jl) can warn when two
elements carry tables of equal digest -- identical per-turn offsets -- while
one table on two slots of a single element contributes one entry and does not
warn (design `docs/design/spectral_turn_table.md`, D4).
"""
function _collect_turn_tables!(tables::Vector, element)
    _each_turn_rule_spec(element) do spec
        kind = name(typeof(spec))
        seen = UInt64[]
        for (slot, rule) in enumerate(_turn_rule_values(spec))
            hasfield(typeof(rule), :digest) || continue
            rule.digest in seen && continue
            push!(seen, rule.digest)
            push!(tables, (digest = rule.digest, element = kind, slot = slot,
                           name = String(rule.name)))
        end
    end
    return tables
end

"""
    _turn_rule_values(spec) -> Vector{Any}

Every rule object the spec's turn-modulation parameters hold, in slot order and
`nothing` entries included, each coerced through the kind's own coercion
(`_rule_tuple`, `_rule_scalar`) so a raw spec that bypassed the friendly
constructor is checked here as it would be at compile. The generic method
answers an empty vector: an element kind without rule parameters holds none.
This ONE fallback is legitimate, unlike one on `_slot_rules` or `realize`,
because the suite's kind tripwire pins which kinds have rules -- every kind
with a specific `_turn_modulation_wrap` method must own a specific
`_turn_rule_values` method -- so a kind that would fall to it is named there.
`ElementSpec{:thin_crab_cavity}` (`src/elements/crab_cavity.jl`) and
`ElementSpec{:thin_rf_cavity}` (`src/elements/rf_cavity.jl`) define theirs.
"""
_turn_rule_values(spec) = Any[]

"""
    _turn_modulation_wrap(spec, inner)

Wrap the compiled runtime element `inner` in a `TurnModulated` when `spec`
carries an active turn-modulation rule, and return it untouched otherwise.
Called from `compile_runtime` innermost of the three wraps. The generic method
is the identity: a kind that declares no rule parameters compiles to exactly
the runtime object it always did. Kinds that do declare them add a method on
their spec type (`ElementSpec{:thin_crab_cavity}` in `src/elements/crab_cavity.jl`,
`ElementSpec{:thin_rf_cavity}` in `src/elements/rf_cavity.jl`); the suite's
kind tripwire derives that set from the methods of this function and requires
each member's metadata, exemption rows, `_turn_rule_values` and container
`_slot_rules`.
"""
_turn_modulation_wrap(spec, inner) = inner

"""
    _turn_modulation_provenance!(out::Vector{Any}, elem) -> out

Collect one entry per modulated element of a compiled line, in line order, for
the `:turn_modulation` provenance receipt that `execute!` records and for the
run artifact's `/turn_modulation` group. The entry shape is fixed so both
consumers can rely on it:

    (element = "ThinCrabCavity",            # nameof the realised element's type
     slots   = [slot, slot, ...])           # ACTIVE slots only, in slot order
    slot = (slot = "phase_noise[1]",        # the container's slot label: parameter name and
                                            # harmonic index on a crab cavity, the bare
                                            # parameter name ("phase_noise") on an RF cavity
            kind = :white,                  # :white, :pink or :table
            rng_id = UInt64,                # the white or pink rule's stream; 0 for a table
            digest = UInt64,                # the table's FNV-1a digest; 0 for white and pink
            name = String,                  # the table's name; "" for white and pink
            length = Int)                   # the table's length; 0 for white and pink

Descends the wrappers and `CompositeLine` like `_check_turn_window`; the
element-specific rule container contributes its slots through
`_turn_modulation_slots(rules) -> Vector`, generic over the container's
`_slot_rules` declaration (the slot protocol above).
"""
_turn_modulation_provenance!(out::Vector, elem) = out
_turn_modulation_provenance!(out::Vector, elems::Tuple) =
    (foreach(e -> _turn_modulation_provenance!(out, e), elems); out)
_turn_modulation_provenance!(out::Vector, w::TurnModulated) =
    (push!(out, (element = string(nameof(typeof(w.inner))),
                 slots = _turn_modulation_slots(w.rule))); out)
_turn_modulation_provenance!(out::Vector, elem::Union{MisalignedElement,RefTilted}) =
    _turn_modulation_provenance!(out, elem.inner)
_turn_modulation_provenance!(out::Vector, elem::CompositeLine) =
    _turn_modulation_provenance!(out, elem.ops)

"""
    _turn_modulation_columns!(out::Vector, elem) -> out

The run artifact's side of the provenance walk: one entry per modulated element
of a compiled line, in the SAME order as `_turn_modulation_provenance!` (the
same five methods over the same wrappers; the suite's wrapper-walk tripwire
pins both), each

    (active  = [k, ...],          # the ACTIVE slots' indices into the draws tuple
                                  # `_realize_draws` returns, in slot order
     nominal = [NamedTuple, ...]) # the same slots' `_slot_nominals` entries

so `active[j]` is the column the recorder keeps for the `j`-th provenance slot
of the element and `nominal[j]` the nominal attributes written on that slot's
group. Generic over `_slot_rules` and `_slot_nominals`; a container whose two
declarations disagree in length is refused by name rather than recorded
misaligned.
"""
_turn_modulation_columns!(out::Vector, elem) = out
_turn_modulation_columns!(out::Vector, elems::Tuple) =
    (foreach(e -> _turn_modulation_columns!(out, e), elems); out)
function _turn_modulation_columns!(out::Vector, w::TurnModulated)
    slots = _slot_rules(w.rule)
    nominals = _slot_nominals(w.rule, w.base)
    length(nominals) == length(slots) || throw(ArgumentError(
        "$(nameof(typeof(w.base))): _slot_nominals declares $(length(nominals)) slot(s) but " *
        "_slot_rules declares $(length(slots)); the two must align slot for slot"))
    active = Int[]
    nominal = NamedTuple[]
    for (k, (_, rule)) in enumerate(slots)
        rule === nothing && continue
        push!(active, k)
        push!(nominal, nominals[k])
    end
    push!(out, (active = active, nominal = nominal))
    return out
end
_turn_modulation_columns!(out::Vector, elem::Union{MisalignedElement,RefTilted}) =
    _turn_modulation_columns!(out, elem.inner)
_turn_modulation_columns!(out::Vector, elem::CompositeLine) =
    _turn_modulation_columns!(out, elem.ops)

"""
    _turn_modulation_slots(rules) -> Vector

The ACTIVE slot entries of an element-level rule container, in slot order, each
of the shape `_turn_modulation_provenance!` documents: ONE generic method over
the container's `_slot_rules`, building each entry through `_push_rule_slot!`
below (an inactive slot appends nothing). No per-container method and no
fallback of its own: a container without a `_slot_rules` method is a
`MethodError` when the receipt is built, not a modulated element silently
missing from the run's provenance.
"""
function _turn_modulation_slots(rules)
    slots = Any[]
    for (label, rule) in _slot_rules(rules)
        _push_rule_slot!(slots, rule, label)
    end
    return slots
end

"""
    _push_rule_slot!(slots::Vector{Any}, rule, label::String) -> slots

Append the provenance entry of one ACTIVE slot, in the shape
`_turn_modulation_provenance!` documents, built generically from the rule's
fields: `kind` from `_rule_kind`, `rng_id` when the rule carries one (the
stochastic rules), `digest`, `name` and `length` when it carries a table
(`TurnTable`), zeros and `""` otherwise -- so a new rule needs a `_rule_kind`
method and nothing here (the per-type `isa` chain this replaces was a
hand-copied catalogue). `nothing`, the inactive slot, appends nothing. Called
by each element's `_turn_modulation_slots` with its own slot label.
"""
_push_rule_slot!(slots::Vector{Any}, ::Nothing, label::String) = slots
function _push_rule_slot!(slots::Vector{Any}, rule::AbstractTurnRule, label::String)
    R = typeof(rule)
    push!(slots, (slot=label,
                  kind=_rule_kind(rule),
                  rng_id=hasfield(R, :rng_id) ? rule.rng_id : UInt64(0),
                  digest=hasfield(R, :digest) ? rule.digest : UInt64(0),
                  name=hasfield(R, :name) ? rule.name : "",
                  length=hasfield(R, :offsets) ? length(rule.offsets) : 0))
    return slots
end
