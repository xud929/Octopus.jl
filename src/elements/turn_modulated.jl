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
# tuple longer than 32 allocates); no new runtime cavity -- `TurnModulated`
# is the third compile-time wrapper beside `MisalignedElement` and `RefTilted`
# and forwards tracking to the REALISED element (D4); nominal and realised
# stay separate so the contextless `track!` path, where no update ever runs,
# tracks the noiseless element (D5, the RF-cavity lesson); rules may carry
# state but need not (D6); the table rule is a pure consumer of additive
# per-turn offsets in the parameter's own unit (D7, owner decision); the rule
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
#     interface `_turn_offset`, the element-level `realize`, the wrapper and
#     its forwards, the pure hook `update` / `update_line`, the window check
#     walk `_check_turn_window`, the modulation-stream collector;
#   - `src/elements/crab_cavity.jl`: the crab cavity's rule container
#     `CrabCavityNoise`, its `realize`, `_turn_modulation_wrap` for the kind,
#     the `phase_noise` / `strength_noise` parameters and their metadata;
#   - `src/knowledge/Knowledge.jl`: `compile_runtime` applies
#     `_turn_modulation_wrap` INNERMOST, then the misalignment, then the roll;
#   - `src/tasks/Tasks.jl`: the two turn loops call `update_line`, the
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
`TurnTable`). A concrete rule defines `_turn_offset` (its additive offset on
one turn) and `_rule_kind` (its provenance kind label). The rule catalogue is
DERIVED from the concrete subtypes of this root (`_turn_rule_names`, the crab
cavity's `_is_turn_rule`, the generic `_push_rule_slot!`, the suite's catalogue
tripwire), never hand-copied into a case list.
"""
abstract type AbstractTurnRule end

# The key layout of the counter RNG, `octopus_normal(seed, method, turn,
# rng_id, particle_slot, component, T)`, as used in this tree, so that no two
# consumers can share a cell even on one `rng_id`:
#   - radiation (`src/elements/radiation.jl`): particle slot = the particle id
#     (>= 1), components 1-6;
#   - the BPM reading noise (`src/tasks/BPMObserver.jl`): particle slot = the
#     reading's occurrence within the turn (0, 1, ...), components 1-2;
#   - the turn-modulation rules (this file): particle slot 0, components in
#     the band `_RULE_COMPONENT_BASE + slot` (white) and
#     `_RULE_COMPONENT_BASE + slot + _PINK_COMPONENT_STRIDE * (k + 1)` (pink
#     generator k), `slot` being the element's parameter slot (`1:2N` on a
#     crab cavity).
# Without the base (review finding S1, 2026-10-12) a white rule on slot 1 or 2
# and a noisy BPM's occurrence 0 sharing an `rng_id` drew the SAME normal.
const _RULE_COMPONENT_BASE = 1024
# The component band of a pink rule's K generators: generator k of slot s draws
# component `_RULE_COMPONENT_BASE + s + _PINK_COMPONENT_STRIDE * (k + 1)`, while
# a `WhiteNoise` on slot s draws `_RULE_COMPONENT_BASE + s`. The crab cavity's
# slots run `1:2N`, so white components and pink bands stay disjoint while
# `2N <= 64` (assumed, not enforced: a crab cavity has few harmonics).
const _PINK_COMPONENT_STRIDE = 64

"""
    _rule_stream_id(rng_id::Integer) -> UInt64

The stream id a stochastic rule's keyword constructor records: `0` assigns a
fresh stream (`next_rng_id!`); an explicit id is claimed (`claim_rng_id!`) so
the auto-assign counter never reissues it, as `LumpedRadSpec` and
`BPMObserver` do (`src/elements/radiation.jl`; 2026-08-05_b audit U14-2).
"""
_rule_stream_id(rng_id::Integer) = rng_id == 0 ? next_rng_id!() : claim_rng_id!(rng_id)

# The shared guard of the stochastic rules' `sigma`. The keyword constructors
# run it BEFORE `_rule_stream_id`, so a refused rule claims no stream.
function _check_rule_sigma(rule::String, sigma::AbstractFloat)
    isfinite(sigma) || throw(ArgumentError("$(rule): sigma must be finite; got $(sigma)"))
    sigma >= 0 || throw(ArgumentError("$(rule): sigma must be non-negative; got $(sigma)"))
    return nothing
end

"""
    WhiteNoise(sigma; rng_id=0)

A per-turn additive offset drawn once per turn from a standard normal scaled
by `sigma`, in the unit of the parameter it modulates (rad on a phase, the
strength unit on a strength). Stateless: the draw is the Octopus counter RNG
(`octopus_normal`, Philox4x32) keyed on `(seed, turn, rng_id)` with the
particle-index slot fixed at 0 and the component `_RULE_COMPONENT_BASE + slot`
(the band reserved for the rules; the key layout is documented above), so the
sequence is a function of the task's seed, the absolute turn and `rng_id`,
identical on every backend and whether the run is one `execute!` or many.
`slot` is supplied by the element that owns the rule (the crab cavity uses the
harmonic index for a phase and `N + harmonic` for a strength), so one `rng_id`
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
function WhiteNoise(sigma::Real; rng_id::Integer=0)
    s = float(sigma)
    _check_rule_sigma("WhiteNoise", s)
    return WhiteNoise{typeof(s)}(s, _rule_stream_id(rng_id))
end

"""
    TurnTable(offsets::AbstractVector{<:AbstractFloat}; name="")

A per-turn table of additive offsets in the parameter's own unit: entry `i`
is the offset applied on ABSOLUTE turn `i - 1` (one-based storage of the
task's zero-based turn), so the first entry is the first turn of the run and
a checkpoint restored with `start_turn = N` reads entry `N + 1`. Stateless:
the table is data.

A pure CONSUMER (design decision D7, owner, 2026-10-12): spectrum synthesis,
the revolution frequency, unit conversion, normalisation, Gaussianity and
periodicity are the producer's; this rule neither checks nor claims them. It
owns exactly the additive semantics, the absolute-turn indexing, the
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

A per-turn additive offset with an approximately 1/f (pink) spectrum, in the
unit of the parameter it modulates (rad on a phase, the strength unit on a
strength), by the Voss-McCartney construction of the design note's section
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
element draw from disjoint component bands as long as `2N <= 64` (a crab
cavity carries a few harmonics; assumed, not enforced). Two ELEMENTS sharing
an `rng_id` draw identical values and the task constructor warns, as for
`WhiteNoise`. `rng_id = 0` (the default) assigns a fresh stream; an explicit
id is claimed so the auto-assign counter never reissues it, as `LumpedRadSpec`
and `BPMObserver` do.

`sigma` is the per-turn rms of the offset: the `K` generators are independent
unit normals, so their sum over `sqrt(K)` has unit variance (the sample rms of
a finite run wanders with the low-frequency content; the spectra script
reports it). `sigma` must be finite and non-negative; zero is a quiet rule.
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
function PinkNoise(sigma::Real; rng_id::Integer=0, octaves::Integer=16)
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
the crab cavity's `_rule_tuple` messages and pinned by the suite's catalogue
tripwire (AGENTS.md: never hand-copy a case list). `_concrete_octopus_subtypes`
lives in `src/tasks/strongstrong/interface.jl`, included after this file; the
call is made only inside an error path or a test at run time, so the late
binding is harmless (the precedent is `_alternative_method_names` in
`src/analysis/one_turn_matrix.jl`).
"""
_turn_rule_names() =
    join(sort!(String[string(nameof(T)) for T in _concrete_octopus_subtypes(AbstractTurnRule)]), ", ")

# ---------------------------------------------------------------------------
# The scalar rule interface. A rule is a per-turn additive offset generator
# for ONE scalar parameter slot of an element; the element's `realize` method
# decides which slots exist and hands each rule its slot number. Stateless
# rules return themselves as `rule′`; a stateful one (an IIR filter, documented
# in the design note's section 5.3 and not shipped here) returns its successor.
# ---------------------------------------------------------------------------

"""
    _turn_offset(rule, ctx::TrackingContext, slot::Integer, ::Type{T}) -> (offset::T, rule′)

The additive offset `rule` contributes on turn `ctx.turn` to the parameter
slot `slot` of an element whose numeric type is `T`, with the rule's successor
(`rule` itself for every stateless rule). `nothing` is the inactive rule:
offset zero, no draw, no state.
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
    _check_rule_window(rule, first_turn::Int64, nturns::Int, where::AbstractString)

Throw an `ArgumentError` if `rule` cannot serve every turn of the window
`first_turn:(first_turn + nturns - 1)`; return `nothing` otherwise. Only a
`TurnTable` has a window constraint (`first_turn + nturns <= length(offsets)`);
`nothing`, `WhiteNoise` and `PinkNoise` serve any turn. `where` names the element and slot
for the message. Called by the `_check_turn_window` walk before the first turn
of every `execute!`.
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
container (`CrabCavityNoise` for `ThinCrabCavity`, `src/elements/crab_cavity.jl`);
there is deliberately no generic fallback -- a rule the element does not
understand is a `MethodError` at the first turn, not a silently unmodulated
run.
"""
function realize end

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
TurnModulated(base, rule) = TurnModulated(base, base, rule)

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
contextless `track!` path never updates, which is what keeps it tracking the
nominal element.
"""
update(elem, ctx::TrackingContext) = elem

function update(w::TurnModulated{E,R}, ctx::TrackingContext) where {E,R}
    inner, rule = realize(w.rule, w.base, ctx)
    # The explicit type parameters are the type-preservation assertion: a
    # realised element or successor rule of another type is a conversion error
    # here, not a tuple of a new type in the kernel.
    return TurnModulated{E,R}(w.base, inner, rule)
end
# The frame wrappers rebuild themselves around the updated element they hold,
# carrying their own frame data unchanged; the kept-whole sub-line rebuilds its
# op tuple through `update_line`, so nesting depth does not matter.
update(elem::MisalignedElement, ctx::TrackingContext) =
    MisalignedElement(update(elem.inner, ctx), elem.qin, elem.oin, elem.qout, elem.oout)
update(elem::RefTilted, ctx::TrackingContext) =
    RefTilted(update(elem.inner, ctx), elem.c, elem.s)
update(elem::CompositeLine, ctx::TrackingContext) =
    CompositeLine(update_line(elem.ops, ctx))

"""
    update_line(line::Tuple, ctx::TrackingContext) -> line′

`update` applied to every element of a runtime line tuple, nested tuples
included, rebuilt with `ntuple(..., Val(N))` so the result is a stack copy of
the same tuple type with zero allocation (`docs/design/turn_modulation.md`,
section 7: 20 ns for 40 elements; `Base.map` over a tuple longer than 32
elements takes the generic path and allocated 79 kB per turn). The suite pins
`typeof(update_line(line, ctx)) === typeof(line)` and zero allocation on a
line longer than 32 elements.
"""
@inline update_line(line::Tuple, ctx::TrackingContext) =
    ntuple(i -> _update_entry(line[i], ctx), Val(length(line)))
@inline _update_entry(e::Tuple, ctx::TrackingContext) = update_line(e, ctx)
@inline _update_entry(e, ctx::TrackingContext) = update(e, ctx)

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
# The wrapper forwards to its rule container, which names the element and slot
# in `where` (the crab container's method in crab_cavity.jl visits its
# per-harmonic entries, "ThinCrabCavity phase_noise[i]" and the like).
_check_turn_window(w::TurnModulated, first_turn::Int64, nturns::Int) =
    _check_rule_window(w.rule, first_turn, nturns, string(nameof(typeof(w.base))))
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
stream. Kinds that declare rule parameters add a method
(`ElementSpec{:thin_crab_cavity}`, `src/elements/crab_cavity.jl`).
"""
_collect_turn_modulation_ids!(ids::Vector{UInt64}, element) = ids
_collect_turn_modulation_ids!(ids::Vector{UInt64}, elements::Tuple) =
    (foreach(e -> _collect_turn_modulation_ids!(ids, e), elements); ids)
_collect_turn_modulation_ids!(ids::Vector{UInt64}, elements::AbstractVector) =
    (foreach(e -> _collect_turn_modulation_ids!(ids, e), elements); ids)
_collect_turn_modulation_ids!(ids::Vector{UInt64}, entry::LineEntry) =
    _collect_turn_modulation_ids!(ids, getfield(entry, :spec))
function _collect_turn_modulation_ids!(ids::Vector{UInt64}, element::ElementSpec{:line})
    foreach(e -> _collect_turn_modulation_ids!(ids, e), line_entries(element))
    return ids
end

"""
    _turn_modulation_wrap(spec, inner)

Wrap the compiled runtime element `inner` in a `TurnModulated` when `spec`
carries an active turn-modulation rule, and return it untouched otherwise.
Called from `compile_runtime` innermost of the three wraps. The generic method
is the identity: a kind that declares no rule parameters compiles to exactly
the runtime object it always did. Kinds that do declare them add a method on
their spec type (`ElementSpec{:thin_crab_cavity}` in `src/elements/crab_cavity.jl`).
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
    slot = (slot = "phase_noise[1]",        # parameter name and harmonic index
            kind = :white,                  # :white, :pink or :table
            rng_id = UInt64,                # the white or pink rule's stream; 0 for a table
            digest = UInt64,                # the table's FNV-1a digest; 0 for white and pink
            name = String,                  # the table's name; "" for white and pink
            length = Int)                   # the table's length; 0 for white and pink

Descends the wrappers and `CompositeLine` like `_check_turn_window`; the
element-specific rule container contributes its slots through a method of
`_turn_modulation_slots(rules) -> Vector` (the crab cavity's in
`src/elements/crab_cavity.jl`).
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
    _turn_modulation_slots(rules) -> Vector

The ACTIVE slot entries of an element-level rule container, in slot order, each
of the shape `_turn_modulation_provenance!` documents. Deliberately no generic
fallback, as for `realize`: a container without a method is a `MethodError`
when the receipt is built, not a modulated element silently missing from the
run's provenance. The crab cavity's method is in `src/elements/crab_cavity.jl`;
it builds each entry through `_push_rule_slot!` below.
"""
function _turn_modulation_slots end

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
