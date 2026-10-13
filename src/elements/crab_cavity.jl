export ThinCrabCavitySpec, ThinCrabCavity

"""
    ThinCrabCavitySpec{N}(frequency; strengthX=(), strengthY=(), phase=(),
                          phase_noise=(), strength_noise=(),
                          tracking_method=Symplectic6DMap(), kwargs...)
    ThinCrabCavitySpec(; frequency, N, kwargs...)

Friendly constructor for `ElementSpec{:thin_crab_cavity}`: a zero-length
two-dimensional crab cavity with `N` harmonics, each carrying a horizontal
strength, a vertical strength, and a phase. `frequency` is in Hz and must be
finite and nonzero. Extra keyword arguments are stored as descriptive spec
metadata. See `element_help(:thin_crab_cavity)` for the parameter schema.

`phase_noise` and `strength_noise` declare turn-by-turn modulation, one entry
per harmonic: each entry is `nothing` (inactive, the default for every
harmonic when the keyword is omitted or `()`) or a rule, `WhiteNoise(sigma;
rng_id)`, `PinkNoise(sigma; rng_id, octaves)` or `TurnTable(offsets; name)`,
whose realised additive offset is applied once per turn by the
`TurnModulated` wrap that `compile_runtime` builds around the nominal cavity
(`docs/design/turn_modulation.md`). A `phase_noise` offset is in rad; a
`strength_noise` offset is in the unit of `strengthX`/`strengthY` and is added
to BOTH planes' strengths of its harmonic. The nominal values stored here,
knob-driven or not, are never changed by a rule. The whole keyword is a tuple
(or vector) of `N` entries or `()`: a bare `nothing`, the RF cavity's scalar
spelling of inactive, is refused here and at compile with a message naming
the parameter (an owner item in `docs/todo.md` decides whether to accept it).
A `PinkNoise` on a cavity with more than 32 harmonics is refused at compile
(the pink stride, `src/elements/turn_modulated.jl`).

This docstring sits on the abstract type because a docstring on the
`function (::Type{ThinCrabCavitySpec{N}})(...)` method below binds to
`Core.Type`, where `?ThinCrabCavitySpec` cannot show it (2026-10-13
neighbour audit, U6-1; the suite's docstring sweep guards the shape).
"""
abstract type ThinCrabCavitySpec{N} end

# Keyword form: reflection builds every kind by keyword alone (the N harmonic
# count arrives as an ordinary keyword there), and a spec rebuilt from
# `parameter_schema` must round trip (2026-08-05 audit, U3-7).
ThinCrabCavitySpec(; frequency, N, kwargs...) =
    ThinCrabCavitySpec{Int(N)}(frequency; kwargs...)

# Documented on the abstract type above (U6-1): no docstring here on purpose.
function (::Type{ThinCrabCavitySpec{N}})(frequency::Real;
                                         strengthX=(),
                                         strengthY=(),
                                         phase=(),
                                         phase_noise=(),
                                         strength_noise=(),
                                         tracking_method=Symplectic6DMap(),
                                         kwargs...) where {N}
    T = typeof(float(frequency))
    _validate_crab_frequency(T(frequency))
    return ElementSpec{:thin_crab_cavity}(
        _spec_params(;
            N=N,
            frequency=T(frequency),
            strengthX=_harmonic_tuple(Val(N), strengthX, T),
            strengthY=_harmonic_tuple(Val(N), strengthY, T),
            phase=_harmonic_tuple(Val(N), phase, T),
            phase_noise=_rule_tuple(Val(N), phase_noise, :phase_noise),
            strength_noise=_rule_tuple(Val(N), strength_noise, :strength_noise),
            tracking_method=tracking_method,
            kwargs...,
        ),
    )
end

# `T<:Number` rather than `T<:AbstractFloat`: a dual number is `<:Real` and a
# truncated power series is `<:Number`, so the tighter bound refuses a parameter
# derivative outright. Float64 still satisfies it, so nothing else changes.
"""
    ThinCrabCavity{N}(frequency; strengthX, strengthY, phase)

Runtime thin 2D crab cavity with `N` harmonics: `N` is a type parameter,
and the harmonic data are stored in fixed-size tuples for CPU/GPU tracking.
`frequency` must be finite and nonzero.

The map applies the kick

```text
px -= strengthX[i] * sin(i*kcc*z + phase[i]) / (i*kcc)
py -= strengthY[i] * sin(i*kcc*z + phase[i]) / (i*kcc)
pz -= (strengthX[i]*x + strengthY[i]*y) * cos(i*kcc*z + phase[i])
```

for `i = 1:N`, leaving `x`, `y`, and `z` unchanged.

**Model boundary — the phase reads `z`, not arrival time.** Two effects are
deliberately absent, both assessed 2026-08-14 (F16 neighbour walk): the
`β` factor between `z` and `z₁ = z/β` (recorded below at 4.6e-3 rad for
2.5 GeV/7 mm), and the velocity slip accumulated since the ring cavity's
per-turn correction, `Δs·(β/β₀ − 1)` with `Δs < C`. At production crab
parameters the slip is negligible — EIC 275 GeV proton: 1.8e-4 rad of
crabbing phase (7.4e-4 of `k·σ_z`), far below RF phase-control tolerance;
10 GeV electron: 8e-8 rad. It matters only in the moderate-energy regime
F16 itself lived in (2.5 GeV, C = 100 m: 0.118 rad), where no crab
operates; the survey channel and `_velocity_slip_g` stand ready if one
ever does.
"""
struct ThinCrabCavity{N,M<:AbstractTrackingMethod,T<:Number} <: AbstractTrackOp
    method::M
    kcc::T
    strengthX::NTuple{N,T}
    strengthY::NTuple{N,T}
    phase::NTuple{N,T}
end

function ThinCrabCavity{N}(frequency::Real;
                           strengthX=(),
                           strengthY=(),
                           phase=()) where {N}
    T = typeof(float(frequency))
    _validate_crab_frequency(T(frequency))
    kcc = T(2) * T(pi) * T(frequency) / T(CLIGHT)
    return ThinCrabCavity{N,Symplectic6DMap,T}(
        Symplectic6DMap(),
        kcc,
        _harmonic_tuple(Val(N), strengthX, T),
        _harmonic_tuple(Val(N), strengthY, T),
        _harmonic_tuple(Val(N), phase, T),
    )
end

function ThinCrabCavity(spec::ElementSpec{:thin_crab_cavity}, method::AbstractTrackingMethod=tracking_method(spec))
    N = param(spec, :N)
    frequency = param(spec, :frequency)
    T = typeof(float(frequency))
    _validate_crab_frequency(T(frequency))
    return ThinCrabCavity{N,typeof(method),T}(
        method,
        T(2) * T(pi) * T(frequency) / T(CLIGHT),
        _harmonic_tuple(Val(N), param(spec, :strengthX), T),
        _harmonic_tuple(Val(N), param(spec, :strengthY), T),
        _harmonic_tuple(Val(N), param(spec, :phase), T),
    )
end

function _validate_crab_frequency(frequency)
    isfinite(frequency) && !iszero(frequency) || throw(ArgumentError(
        "thin crab-cavity frequency must be finite and nonzero; got $(frequency)"))
    return frequency
end

Base.getindex(cavity::ThinCrabCavity, row::Integer, harmonic::Integer) =
    _cavity_get(cavity, row, harmonic)
Base.getindex(spec::ElementSpec{:thin_crab_cavity}, row::Integer, harmonic::Integer) =
    _spec_cavity_get(spec, row, harmonic)

@inline function track_particle(::Symplectic6DMap, cavity::ThinCrabCavity{N,M,T}, x0, px0, y0, py0, z0, pz0) where {N,M,T}
    dpx = zero(T)
    dpy = zero(T)
    dpz = zero(T)
    for i in 1:N
        ikcc = T(i) * cavity.kcc
        θ = ikcc * z0 + cavity.phase[i]
        s = sin(θ)
        c = cos(θ)
        sx = cavity.strengthX[i]
        sy = cavity.strengthY[i]
        dpx -= sx * s / ikcc
        dpy -= sy * s / ikcc
        dpz -= (sx * x0 + sy * y0) * c
    end
    return x0, px0 + dpx, y0, py0 + dpy, z0, pz0 + dpz
end

@inline (cavity::ThinCrabCavity)(x0, px0, y0, py0, z0, pz0) =
    track_particle(cavity.method, cavity, x0, px0, y0, py0, z0, pz0)

function _harmonic_tuple(::Val{N}, values, ::Type{T}) where {N,T}
    if values === () || length(values) == 0
        return ntuple(_ -> zero(T), N)
    end
    length(values) == N || throw(ArgumentError("expected $N harmonic values, got $(length(values))"))
    return ntuple(i -> T(values[i]), N)
end

# Defined here, above the `@element_spec` block, for the same reason
# `_harmonic_tuple` is: the block constructs the example at include time
# through the friendly constructor, which calls both.
"""
    _rule_tuple(::Val{N}, values, parameter::Symbol) -> Tuple

Coerce a `phase_noise` / `strength_noise` keyword to a tuple of `N` entries,
each `nothing` or a rule (a concrete `AbstractTurnRule`; the messages name the
catalogue through `_turn_rule_names()`): `()` or any empty collection (the
default) becomes `N` times `nothing`; a value that is not a tuple or vector, a
length other than `N`, or an entry that is neither `nothing` nor a rule throws
an `ArgumentError` naming the parameter (and, for an entry, its index and
type). The result is a plain `Tuple` whose entry types may differ, so one
harmonic can carry a rule while the others stay inactive. Called by the
friendly constructor and again by `_turn_modulation_wrap`, so a raw
`ElementSpec{:thin_crab_cavity}(; ...)` carrying an uncoerced value is checked
at compile. The rule machinery itself lives in
`src/elements/turn_modulated.jl`; see the block at the end of this file.
"""
function _rule_tuple(::Val{N}, values, parameter::Symbol) where {N}
    values isa Union{Tuple,AbstractVector} || throw(ArgumentError(
        "$(parameter) must be a tuple of $(N) entries, each nothing or a rule " *
        "($(_turn_rule_names())); got a $(typeof(values))"))
    if length(values) == 0
        return ntuple(_ -> nothing, N)
    end
    length(values) == N || throw(ArgumentError(
        "expected $(N) $(parameter) entries, got $(length(values))"))
    for (index, entry) in enumerate(values)
        _is_turn_rule(entry) || throw(ArgumentError(
            "$(parameter)[$(index)] must be nothing or a rule ($(_turn_rule_names())); " *
            "got a $(typeof(entry))"))
    end
    return ntuple(k -> values[k], N)
end

# A body-level `isa` rather than dispatch on the rule root: this file is
# included before `turn_modulated.jl` defines `AbstractTurnRule`, so the root
# may appear in a function body (resolved at the call) but not in a method
# signature here. The catalogue is the root's concrete subtypes, never a list.
_is_turn_rule(entry) = entry === nothing || entry isa AbstractTurnRule

@element_spec begin
    kind = :thin_crab_cavity
    spec_type = ElementSpec{:thin_crab_cavity}
    friendly_constructor = ThinCrabCavitySpec
    runtime_type = ThinCrabCavity
    description = "Flexible thin 2D crab cavity specification with fixed harmonic count."
    keywords = [:thin_element, :crab_cavity, :harmonic, :turn_modulation]
    tracking_methods = [Symplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract]
    analyses = [TwissDispersionAnalysis]
    parameters = (
        N=ParamMeta(required=true, meaning="maximum harmonic count encoded by ThinCrabCavitySpec{N}"),
        frequency=ParamMeta(required=true, unit="Hz", meaning="RF frequency"),
        strengthX=ParamMeta(default=(), meaning="horizontal kick strength tuple of length N"),
        strengthY=ParamMeta(default=(), meaning="vertical kick strength tuple of length N"),
        phase=ParamMeta(unit="rad", default=(), meaning="phase tuple of length N"),
        phase_noise=ParamMeta(unit="rad", default=(), meaning="per-harmonic turn-by-turn additive phase modulation, tuple of length N: each entry nothing (inactive) or a rule (WhiteNoise, PinkNoise, TurnTable) realised once per turn on the host by the TurnModulated wrap at compile_runtime, never read by the kernel; see src/elements/turn_modulated.jl"),
        strength_noise=ParamMeta(default=(), meaning="per-harmonic turn-by-turn additive strength modulation in the unit of strengthX/strengthY, tuple of length N: each entry nothing or a rule; one realised offset per harmonic is added to both planes"),
        tracking_method=ParamMeta(default=Symplectic6DMap(), meaning="per-element tracking method"),
        _PLACEMENT_PARAMS...,
    )
    example = ThinCrabCavitySpec{2}(1.0e8; strengthX=(1.0, 0.5), strengthY=(0.25, 0.125), phase=(0.0, 0.1))
    construction_help = "Friendly constructor: ThinCrabCavitySpec{N}(frequency; strengthX, strengthY, phase, phase_noise, strength_noise, tracking_method=Symplectic6DMap(), kwargs...). Equivalent flexible form: ElementSpec{:thin_crab_cavity}(; N=N, frequency=frequency, strengthX=strengthX, strengthY=strengthY, phase=phase, phase_noise=phase_noise, strength_noise=strength_noise, tracking_method=tracking_method, kwargs...). Harmonic tuples must have length N; omitted tuples are filled with zeros. Turn-by-turn modulation: phase_noise and strength_noise are per-harmonic tuples of length N whose entries are nothing (inactive, the default when the keyword is omitted or ()) or a rule, WhiteNoise(sigma; rng_id), PinkNoise(sigma; rng_id, octaves) or TurnTable(offsets; name); the rule's realised additive offset (rad for phase_noise; the strength unit for strength_noise, added to both planes of its harmonic) is applied once per turn by the TurnModulated wrap that compile_runtime builds, never by the kernel. The whole keyword must be a tuple or vector of N entries or (): a bare nothing (the RF cavity's scalar spelling of inactive) is refused at construction and at compile, not read as all-inactive; a PinkNoise on a cavity with more than 32 harmonics is refused at compile (the pink stride of the counter-RNG keying). Placement (every kind, consumed by the compile-time misalignment and design-roll wraps): x_offset, y_offset, z_offset [m], x_pitch, y_pitch, tilt, ref_tilt [rad], misalign_convention (:bmad or :madx). name: an optional label, carried into beam-line provenance paths and diagnostics, never read by a tracking kernel."
end

@inline function _cavity_get(cavity, row::Integer, harmonic::Integer)
    (1 <= harmonic <= length(cavity.phase)) ||
        throw(BoundsError(cavity, (row, harmonic)))
    if row == 1
        return cavity.strengthX[harmonic]
    elseif row == 2
        return cavity.strengthY[harmonic]
    elseif row == 3
        return cavity.phase[harmonic]
    else
        throw(BoundsError(cavity, (row, harmonic)))
    end
end

@inline function _spec_cavity_get(spec::ElementSpec{:thin_crab_cavity}, row::Integer, harmonic::Integer)
    N = param(spec, :N)
    (1 <= harmonic <= N) || throw(BoundsError(spec, (row, harmonic)))
    if row == 1
        return param(spec, :strengthX)[harmonic]
    elseif row == 2
        return param(spec, :strengthY)[harmonic]
    elseif row == 3
        return param(spec, :phase)[harmonic]
    else
        throw(BoundsError(spec, (row, harmonic)))
    end
end

# ---------------------------------------------------------------------------
# Turn-by-turn modulation of the crab cavity: RF phase and amplitude noise.
# Generic machinery (the wrapper, the rules, the hook) lives in
# `src/elements/turn_modulated.jl`; this block is the crab cavity's side of
# the seam. Design: `docs/design/turn_modulation.md`, sections 4.1, 4.2, 5.
# ---------------------------------------------------------------------------

"""
    CrabCavityNoise(phase::Tuple, strength::Tuple)

The rule container `TurnModulated` carries for a `ThinCrabCavity{N}`: one
entry per harmonic for the phase (`phase_noise`, rad) and one per harmonic for
the strength (`strength_noise`, the unit of `strengthX`/`strengthY`), each
`nothing` (inactive) or a rule (`WhiteNoise`, `PinkNoise`, `TurnTable`). One realised
strength offset per harmonic is added to BOTH planes' strengths, which is what
one cavity voltage does. Slot numbering handed to `_turn_offset`: harmonic `i`
of the phase is slot `i`, of the strength slot `N + i`, so one `rng_id` shared
by every entry of one cavity still draws independently per entry.
"""
struct CrabCavityNoise{P<:Tuple,S<:Tuple}
    phase::P
    strength::S
end

"""
    realize(rules::CrabCavityNoise, base::ThinCrabCavity{N,M,T}, ctx) -> (cavity, rules′)

The cavity to track on turn `ctx.turn`: `base` with each harmonic's realised
phase offset added to `phase[i]` and its realised strength offset added to
both `strengthX[i]` and `strengthY[i]`, together with the rules' successors.
Phase harmonic `i` is handed slot `i`, strength harmonic `i` slot `N + i`.
Every tuple is rebuilt with `ntuple(..., Val(N))`, so the result has exactly
the type of `base` and the call allocates nothing; the successor container has
the type of `rules` because every shipped rule is stateless.
"""
function realize(rules::CrabCavityNoise, base::ThinCrabCavity{N,M,T},
                 ctx::TrackingContext) where {N,M,T}
    phase_draws = ntuple(i -> _turn_offset(rules.phase[i], ctx, i, T), Val(N))
    strength_draws = ntuple(j -> _turn_offset(rules.strength[j], ctx, N + j, T), Val(N))
    realised = ThinCrabCavity{N,M,T}(
        base.method,
        base.kcc,
        ntuple(a -> base.strengthX[a] + strength_draws[a][1], Val(N)),
        ntuple(b -> base.strengthY[b] + strength_draws[b][1], Val(N)),
        ntuple(c -> base.phase[c] + phase_draws[c][1], Val(N)),
    )
    successor = CrabCavityNoise(
        ntuple(p -> phase_draws[p][2], Val(N)),
        ntuple(q -> strength_draws[q][2], Val(N)),
    )
    return realised, successor
end

"""
    _turn_modulation_wrap(spec::ElementSpec{:thin_crab_cavity}, inner::ThinCrabCavity)

The crab cavity's method of the compile-time wrap: `inner` itself when every
`phase_noise` and `strength_noise` entry is `nothing`, otherwise
`TurnModulated(inner, CrabCavityNoise(phase_rules, strength_rules))`. Both
parameters pass through `_rule_tuple` here as well, so a raw spec is checked.
A rule bound to a numeric type (`_rule_numeric_type`, a `TurnTable{T′}`) other
than the cavity's `T` is refused with an `ArgumentError` rather than promoted.
`inner` is the NOMINAL cavity: a knob-driven `phase` has already resolved
into it, and the rule's offset is added at run time on top of it.
"""
function _turn_modulation_wrap(spec::ElementSpec{:thin_crab_cavity}, inner::ThinCrabCavity{N,M,T}) where {N,M,T}
    phase_rules = _rule_tuple(Val(N), getparam(spec, :phase_noise, ()), :phase_noise)
    strength_rules = _rule_tuple(Val(N), getparam(spec, :strength_noise, ()), :strength_noise)
    if all(r -> r === nothing, phase_rules) && all(r -> r === nothing, strength_rules)
        return inner
    end
    _check_rule_numeric_types(phase_rules, :phase_noise, T)
    _check_rule_numeric_types(strength_rules, :strength_noise, T)
    return TurnModulated(inner, CrabCavityNoise(phase_rules, strength_rules))
end

function _check_rule_numeric_types(rules::Tuple, parameter::Symbol, ::Type{T}) where {T}
    for (index, rule) in enumerate(rules)
        bound = _rule_numeric_type(rule)
        (bound === nothing || bound === T) || throw(ArgumentError(
            "$(parameter)[$(index)]: a $(bound) turn table on a $(T) cavity is refused " *
            "rather than promoted; convert the table to $(T)"))
    end
    return nothing
end

"""
    _slot_rules(rules::CrabCavityNoise) -> Tuple

The container's `2N` slots in SLOT ORDER -- the `N` phase harmonics, then the
`N` strength harmonics, the numbering `realize` hands `_turn_offset` -- as
`("phase_noise[i]", rule)` and `("strength_noise[i]", rule)` pairs, inactive
slots included (`rule === nothing`). The slot protocol of
`src/elements/turn_modulated.jl`: the window check (`_check_container_window`,
"ThinCrabCavity phase_noise[2]" in its message) and the provenance slots
(`_turn_modulation_slots`, the `(slot, kind, rng_id, digest, name, length)`
entries of the ACTIVE slots) are built from this declaration, not from
per-container walks.
"""
function _slot_rules(rules::CrabCavityNoise)
    phase = ntuple(i -> ("phase_noise[$(i)]", rules.phase[i]), length(rules.phase))
    strength = ntuple(i -> ("strength_noise[$(i)]", rules.strength[i]), length(rules.strength))
    return (phase..., strength...)
end

"""
    _turn_rule_values(spec::ElementSpec{:thin_crab_cavity}) -> Vector{Any}

The `2N` entries of the spec's `phase_noise` and `strength_noise` tuples in
slot order, each passed through `_rule_tuple` so a malformed raw spec fails
here as it would at compile. The generic `_collect_turn_modulation_ids!`
(`src/elements/turn_modulated.jl`) draws the distinct stream ids from them:
one id shared by every entry of one cavity is reported once (the slots keep
the draws independent) and does not warn; the same id on two cavities does.
"""
function _turn_rule_values(spec::ElementSpec{:thin_crab_cavity})
    N = Int(param(spec, :N))
    values = Any[]
    for key in (:phase_noise, :strength_noise)
        append!(values, _rule_tuple(Val(N), getparam(spec, key, ()), key))
    end
    return values
end

# `_push_rule_slot!`, the entry builder (one generic method on the rule root
# instead of a per-type chain), and the generic walks over `_slot_rules` and
# `_turn_rule_values` live in `src/elements/turn_modulated.jl`.
