export TurnModulated, WhiteNoise, PinkNoise, TurnTable, update, update_line, realize

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
#   - this file: the rules (`WhiteNoise`, `PinkNoise`, `TurnTable`), the scalar rule
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
`TurnTable`). A concrete rule defines `_turn_offset` (its value on one turn,
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
`_turn_modulation_provenance!` documents: `:white`, `:pink` or `:table`.
Deliberately no fallback, as for `realize`: a rule without a label is a
`MethodError` when the receipt is built, not an unlabelled slot.
"""
_rule_kind(::WhiteNoise) = :white
_rule_kind(::PinkNoise) = :pink
_rule_kind(::TurnTable) = :table

"""
    _turn_rule_names() -> String

The rule catalogue as prose, `"PinkNoise, TurnTable, WhiteNoise"`: the concrete
subtypes of `AbstractTurnRule` sorted by name, DERIVED from the type tree for
the crab cavity's `_rule_tuple` and the RF cavity's `_rule_scalar` messages and
pinned by the suite's catalogue tripwire (AGENTS.md: never hand-copy a case
list). `_concrete_octopus_subtypes`
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
    _collect_turn_modulation_ids!(ids::Vector{UInt64}, element) -> ids

Collect the `rng_id` of every stochastic turn-modulation rule declared on the
SPECS of a line (tuples, vectors, `LineEntry`, `ElementSpec{:line}` descended
as `_collect_radiation_ids!` does), one entry per distinct id per element, so
`_warn_duplicate_turn_modulation_streams` can warn when two elements share a
stream. ONE generic method on `ElementSpec` reads the rule objects through the
kind's `_turn_rule_values` and pushes each DISTINCT `rng_id` among them (every
rule carrying an `rng_id` field; `WhiteNoise` and `PinkNoise` today) once: one
id shared by every slot of one element contributes one entry (the slots keep
the draws independent) and does not warn; the same id on two elements
contributes two and does. Kinds that declare rule parameters add a
`_turn_rule_values` method, not a collector method.
"""
_collect_turn_modulation_ids!(ids::Vector{UInt64}, element) = ids
_collect_turn_modulation_ids!(ids::Vector{UInt64}, elements::Tuple) =
    (foreach(e -> _collect_turn_modulation_ids!(ids, e), elements); ids)
_collect_turn_modulation_ids!(ids::Vector{UInt64}, elements::AbstractVector) =
    (foreach(e -> _collect_turn_modulation_ids!(ids, e), elements); ids)
# The spec the placement COMPILES -- overrides merged, `_effective_spec` in
# src/tasks/Tasks.jl -- as every `LineEntry` collector reads it, so a rule
# given only through a placement override is seen (U1-2).
_collect_turn_modulation_ids!(ids::Vector{UInt64}, entry::LineEntry) =
    _collect_turn_modulation_ids!(ids, _effective_spec(entry))
function _collect_turn_modulation_ids!(ids::Vector{UInt64}, element::ElementSpec{:line})
    foreach(e -> _collect_turn_modulation_ids!(ids, e), line_entries(element))
    return ids
end
function _collect_turn_modulation_ids!(ids::Vector{UInt64}, spec::ElementSpec)
    seen = UInt64[]
    for rule in _turn_rule_values(spec)
        hasfield(typeof(rule), :rng_id) || continue
        rule.rng_id in seen || push!(seen, rule.rng_id)
    end
    append!(ids, seen)
    return ids
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
